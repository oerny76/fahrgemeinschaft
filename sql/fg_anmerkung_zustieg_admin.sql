-- Vorschlag, NICHT automatisch ausgeführt. Bitte im Supabase SQL Editor einspielen.
-- Diese EINE Datei enthält alles Neue:
--   A) Anmerkung (bis 200 Zeichen) und "Anderer Ort" (bis 100 Zeichen) für alle Angaben
--   B) Der Admin kann für jedes Kind manuell eintragen
-- Sie ersetzt die frühere Datei fg_admin_eingabe.sql (die nicht mehr eingespielt werden muss).
--
-- Voraussetzung (schon eingespielt): fg_admin_uebersicht.sql und
-- fg_mein_status_mitfahrende_mit_id.sql. Diese Datei kann danach direkt laufen.
--
-- Reihenfolge: ZUERST diese Datei einspielen, DANACH die neuen Seiten veröffentlichen.
-- Die bisherigen Seiten funktionieren auch nach dem Einspielen unverändert weiter.

-- ============================================================
-- A1) Neue Spalten und erweiterte Auswahl
-- ============================================================
alter table fahrgemeinschaft.bedarf
  add column if not exists ort_text text,
  add column if not exists anmerkung text;

alter table fahrgemeinschaft.bedarf drop constraint if exists bedarf_ort_text_check;
alter table fahrgemeinschaft.bedarf add constraint bedarf_ort_text_check
  check (ort_text is null or char_length(ort_text) <= 100);

alter table fahrgemeinschaft.bedarf drop constraint if exists bedarf_anmerkung_check;
alter table fahrgemeinschaft.bedarf add constraint bedarf_anmerkung_check
  check (anmerkung is null or char_length(anmerkung) <= 200);

-- ort_typ bekommt den dritten Wert 'anderer'
alter table fahrgemeinschaft.bedarf drop constraint if exists bedarf_ort_typ_check;
alter table fahrgemeinschaft.bedarf add constraint bedarf_ort_typ_check
  check (ort_typ = any (array['schule'::text, 'wohnort'::text, 'anderer'::text]));

-- ============================================================
-- A2) fg_setze_option: zwei neue Parameter (mit Standardwert)
--     Die alte Funktion wird ersetzt, nicht überladen, damit der Aufruf eindeutig bleibt.
--     Alte Aufrufe mit sechs Parametern funktionieren weiter.
-- ============================================================
drop function if exists public.fg_setze_option(text, text, text, text, integer, text);

create or replace function public.fg_setze_option(
  p_token text,
  p_richtung text,
  p_status text,
  p_ort_typ text default 'schule',
  p_plaetze_frei integer default 0,
  p_stationen text default null,
  p_ort_text text default null,
  p_anmerkung text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_id text := fahrgemeinschaft.kind_zu_token(p_token);
  v_plaetze int := case when p_status = 'selbst' then coalesce(p_plaetze_frei, 0) else 0 end;
  v_stationen text := left(nullif(btrim(coalesce(p_stationen, '')), ''), 200);
  v_typ text := coalesce(p_ort_typ, 'schule');
  v_ort_text text := nullif(btrim(coalesce(p_ort_text, '')), '');
  v_anm text := nullif(btrim(coalesce(p_anmerkung, '')), '');
begin
  if p_richtung not in ('hin', 'rueck') then raise exception 'Ungültige Richtung.'; end if;
  if p_status not in ('selbst', 'suche', 'anderweitig') then raise exception 'Ungültige Option.'; end if;
  if v_typ not in ('schule', 'wohnort', 'anderer') then raise exception 'Ungültiges Ziel.'; end if;
  if v_plaetze < 0 or v_plaetze > 8 then raise exception 'Bitte 0 bis 8 freie Plätze angeben.'; end if;
  if v_plaetze > 0 and v_stationen is null then
    raise exception 'Bitte die Stationen der Fahrt angeben, z. B. Wertingen, Dillingen.';
  end if;
  if char_length(coalesce(v_ort_text, '')) > 100 then
    raise exception 'Der Ort ist zu lang. Es sind höchstens 100 Zeichen erlaubt.';
  end if;
  if char_length(coalesce(v_anm, '')) > 200 then
    raise exception 'Die Anmerkung ist zu lang. Es sind höchstens 200 Zeichen erlaubt.';
  end if;
  if p_status = 'suche' and v_typ = 'anderer' and v_ort_text is null then
    raise exception 'Bitte gib den anderen Ort an.';
  end if;

  -- Ort je nach Option vereinheitlichen
  if p_status = 'suche' then
    if v_typ <> 'anderer' then v_ort_text := null; end if;
  elsif p_status = 'selbst' then
    -- Beim Fahren ist der Ort ein freiwilliger anderer Treffpunkt für Mitfahrende
    if v_plaetze = 0 then v_ort_text := null; end if;
    v_typ := case when v_ort_text is not null then 'anderer' else 'schule' end;
  else
    v_typ := 'schule';
    v_ort_text := null;
  end if;

  insert into fahrgemeinschaft.bedarf
    (kind_id, richtung, status, ort_typ, plaetze_frei, stationen, ort_text, anmerkung)
  values
    (v_id, p_richtung, p_status, v_typ, v_plaetze::smallint,
     case when v_plaetze > 0 then v_stationen end, v_ort_text, v_anm)
  on conflict (kind_id, richtung) do update
    set status = excluded.status, ort_typ = excluded.ort_typ,
        plaetze_frei = excluded.plaetze_frei, stationen = excluded.stationen,
        ort_text = excluded.ort_text, anmerkung = excluded.anmerkung;

  return public.fg_mein_status(p_token);
end $function$;

revoke all on function public.fg_setze_option(text, text, text, text, integer, text, text, text) from public;
grant execute on function public.fg_setze_option(text, text, text, text, integer, text, text, text) to anon, authenticated;

-- ============================================================
-- A3) fg_mein_status: neue Felder ort_text, anmerkung; Angaben zum Fahrer und zu den Mitfahrenden
-- ============================================================
create or replace function public.fg_mein_status(p_token text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  v_id text := fahrgemeinschaft.kind_zu_token(p_token);
  v_ort text;
begin
  select ort into v_ort from fahrgemeinschaft.kinder where id = v_id;
  return jsonb_build_object(
    'kind', (select jsonb_build_object('id', k.id, 'name', k.anzeige_name, 'ort', k.ort)
             from fahrgemeinschaft.kinder k where k.id = v_id),
    'strecken', (
      select coalesce(jsonb_agg(s.obj order by s.richtung), '[]'::jsonb) from (
        select r.richtung, jsonb_build_object(
          'richtung', r.richtung,
          'status', b.status,
          'ort_typ', b.ort_typ,
          'ort_text', b.ort_text,
          'anmerkung', b.anmerkung,
          'plaetze_frei', b.plaetze_frei,
          'stationen', b.stationen,
          'von', case when b.status = 'suche' then
                   case when r.richtung = 'hin'
                        then case b.ort_typ when 'schule' then 'Schule' when 'anderer' then b.ort_text else v_ort end
                        else 'Bahnhof Meitingen' end end,
          'nach', case when b.status = 'suche' then
                   case when r.richtung = 'hin'
                        then 'Bahnhof Meitingen'
                        else case b.ort_typ when 'schule' then 'Schule' when 'anderer' then b.ort_text else v_ort end end end,
          'faehrt_mit', (select jsonb_build_object('kind_id', f.id, 'name', f.anzeige_name,
                                                   'stationen', fb.stationen,
                                                   'ort_text', fb.ort_text,
                                                   'anmerkung', fb.anmerkung)
                         from fahrgemeinschaft.mitfahrt m
                         join fahrgemeinschaft.kinder f on f.id = m.fahrer_kind_id
                         join fahrgemeinschaft.bedarf fb on fb.kind_id = m.fahrer_kind_id and fb.richtung = m.richtung
                         where m.kind_id = v_id and m.richtung = r.richtung),
          'mitfahrende', (select coalesce(jsonb_agg(jsonb_build_object(
                                    'kind_id', mk.id,
                                    'name', mk.anzeige_name,
                                    'ort', case mb.ort_typ when 'schule' then 'Schule'
                                                           when 'anderer' then mb.ort_text
                                                           else mk.ort end,
                                    'anmerkung', mb.anmerkung) order by mk.id), '[]'::jsonb)
                          from fahrgemeinschaft.mitfahrt m
                          join fahrgemeinschaft.kinder mk on mk.id = m.kind_id
                          join fahrgemeinschaft.bedarf mb on mb.kind_id = m.kind_id and mb.richtung = m.richtung
                          where m.fahrer_kind_id = v_id and m.richtung = r.richtung)
        ) as obj
        from (values ('hin'), ('rueck')) as r(richtung)
        left join fahrgemeinschaft.bedarf b on b.kind_id = v_id and b.richtung = r.richtung
      ) s
    )
  );
end $function$;

-- ============================================================
-- A4) fg_angebote: Treffpunkt und Anmerkung des Fahrers dazu
-- ============================================================
create or replace function public.fg_angebote(p_token text, p_richtung text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_id text := fahrgemeinschaft.kind_zu_token(p_token);
begin
  if p_richtung not in ('hin', 'rueck') then
    raise exception 'Ungültige Richtung.';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'kind_id', k.id, 'name', k.anzeige_name, 'stationen', b.stationen,
             'ort_text', b.ort_text, 'anmerkung', b.anmerkung,
             'frei', b.plaetze_frei - cnt.n) order by k.id)
    from fahrgemeinschaft.bedarf b
    join fahrgemeinschaft.kinder k on k.id = b.kind_id
    cross join lateral (select count(*)::int as n from fahrgemeinschaft.mitfahrt m
                        where m.fahrer_kind_id = b.kind_id and m.richtung = b.richtung) cnt
    where b.richtung = p_richtung and b.status = 'selbst' and b.kind_id <> v_id
      and b.plaetze_frei - cnt.n > 0
  ), '[]'::jsonb);
end $function$;

-- ============================================================
-- B1) Hilfsfunktionen für den Admin (im nicht freigegebenen Schema)
-- ============================================================
create or replace function fahrgemeinschaft.admin_pruefen(p_admin_token text)
 returns void
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
begin
  if p_admin_token is null
     or not exists (select 1 from fahrgemeinschaft.admin_zugang where token = p_admin_token) then
    raise exception 'Ungültiger Zugangslink.';
  end if;
end $function$;

create or replace function fahrgemeinschaft.zugang_zu_kind(p_kind_id text)
 returns text
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v text;
begin
  select token into v from fahrgemeinschaft.zugang where kind_id = p_kind_id;
  if v is null then
    raise exception 'Dieses Kind gibt es nicht.';
  end if;
  return v;
end $function$;

revoke all on function fahrgemeinschaft.admin_pruefen(text) from public, anon, authenticated;
revoke all on function fahrgemeinschaft.zugang_zu_kind(text) from public, anon, authenticated;

-- ============================================================
-- B2) fg_admin_uebersicht: mit Anmerkung, Ort, Fahrer-Kennung und Mitfahrenden mit kind_id
-- ============================================================
create or replace function public.fg_admin_uebersicht(p_admin_token text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
begin
  perform fahrgemeinschaft.admin_pruefen(p_admin_token);

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'kind_id', k.id,
      'name', k.anzeige_name,
      'jahrgang', k.jahrgang,
      'ort', k.ort,
      'strecken', (
        select jsonb_object_agg(r.richtung, jsonb_build_object(
          'status', b.status,
          'ort_typ', b.ort_typ,
          'ort_text', b.ort_text,
          'anmerkung', b.anmerkung,
          'plaetze_frei', b.plaetze_frei,
          'stationen', b.stationen,
          'aktualisiert_am', b.aktualisiert_am,
          'faehrt_mit', (select f.anzeige_name
                         from fahrgemeinschaft.mitfahrt m
                         join fahrgemeinschaft.kinder f on f.id = m.fahrer_kind_id
                         where m.kind_id = k.id and m.richtung = r.richtung),
          'faehrt_mit_id', (select m.fahrer_kind_id
                            from fahrgemeinschaft.mitfahrt m
                            where m.kind_id = k.id and m.richtung = r.richtung),
          'mitfahrende', (select coalesce(jsonb_agg(
                                    jsonb_build_object('kind_id', mk.id, 'name', mk.anzeige_name)
                                    order by mk.id), '[]'::jsonb)
                          from fahrgemeinschaft.mitfahrt m
                          join fahrgemeinschaft.kinder mk on mk.id = m.kind_id
                          where m.fahrer_kind_id = k.id and m.richtung = r.richtung)
        ))
        from (values ('hin'), ('rueck')) as r(richtung)
        left join fahrgemeinschaft.bedarf b on b.kind_id = k.id and b.richtung = r.richtung
      )
    ) order by k.id)
    from fahrgemeinschaft.kinder k
  ), '[]'::jsonb);
end $function$;

-- ============================================================
-- B3) Admin-Funktionen: rufen die Funktionen der Eltern-Seite auf (gleiche Regeln und Trigger)
--     Jede Funktion gibt die komplette Übersicht zurück.
-- ============================================================
create or replace function public.fg_admin_setze_option(
  p_admin_token text,
  p_kind_id text,
  p_richtung text,
  p_status text,
  p_ort_typ text default 'schule',
  p_plaetze_frei integer default 0,
  p_stationen text default null,
  p_ort_text text default null,
  p_anmerkung text default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  perform fahrgemeinschaft.admin_pruefen(p_admin_token);
  perform public.fg_setze_option(
    fahrgemeinschaft.zugang_zu_kind(p_kind_id),
    p_richtung, p_status, p_ort_typ, p_plaetze_frei, p_stationen, p_ort_text, p_anmerkung);
  return public.fg_admin_uebersicht(p_admin_token);
end $function$;

create or replace function public.fg_admin_buche(
  p_admin_token text,
  p_kind_id text,
  p_richtung text,
  p_fahrer_kind_id text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  perform fahrgemeinschaft.admin_pruefen(p_admin_token);
  perform public.fg_buche(
    fahrgemeinschaft.zugang_zu_kind(p_kind_id), p_richtung, p_fahrer_kind_id);
  return public.fg_admin_uebersicht(p_admin_token);
end $function$;

create or replace function public.fg_admin_storniere(
  p_admin_token text,
  p_kind_id text,
  p_richtung text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  perform fahrgemeinschaft.admin_pruefen(p_admin_token);
  perform public.fg_storniere(fahrgemeinschaft.zugang_zu_kind(p_kind_id), p_richtung);
  return public.fg_admin_uebersicht(p_admin_token);
end $function$;

revoke all on function public.fg_admin_setze_option(text, text, text, text, text, integer, text, text, text) from public;
revoke all on function public.fg_admin_buche(text, text, text, text) from public;
revoke all on function public.fg_admin_storniere(text, text, text) from public;
grant execute on function public.fg_admin_setze_option(text, text, text, text, text, integer, text, text, text) to anon, authenticated;
grant execute on function public.fg_admin_buche(text, text, text, text) to anon, authenticated;
grant execute on function public.fg_admin_storniere(text, text, text) to anon, authenticated;
