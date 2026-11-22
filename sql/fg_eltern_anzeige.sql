-- Vorschlag, NICHT automatisch ausgeführt. Bitte im Supabase SQL Editor einspielen.
-- Zweck: Die Funktionen liefern zusätzlich die Eltern (Anzeigetext), damit die Seiten
-- statt der Kinder die Eltern anzeigen können, z. B. "Mia K. oder Paul K.".
--
-- Voraussetzung (schon eingespielt): fg_anmerkung_zustieg_admin.sql und die Spalten
-- elternteil_1, elternteil_2, eltern_anzeige in fahrgemeinschaft.kinder.
--
-- Diese Datei enthält KEINE Namen. Sie ändert nur drei Funktionen (gleiche Signaturen).
-- Alte Seiten funktionieren unverändert weiter, sie ignorieren die neuen Felder.
-- Reihenfolge: ZUERST diese Datei einspielen, DANACH die neuen Seiten veröffentlichen.
-- (Die neuen Seiten laufen auch ohne diese Datei, zeigen dann aber weiter die Kinder.)

-- ============================================================
-- fg_mein_status: Eltern des Fahrers und der Mitfahrenden
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
                                                   'eltern', f.eltern_anzeige,
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
                                    'eltern', mk.eltern_anzeige,
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
-- fg_angebote: Eltern des Fahrers
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
             'kind_id', k.id, 'name', k.anzeige_name, 'eltern', k.eltern_anzeige,
             'stationen', b.stationen,
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
-- fg_admin_uebersicht: Eltern je Kind, beim Fahrer und bei den Mitfahrenden
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
      'eltern', k.eltern_anzeige,
      'elternteil_1', k.elternteil_1,
      'elternteil_2', k.elternteil_2,
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
          'faehrt_mit_eltern', (select f.eltern_anzeige
                                from fahrgemeinschaft.mitfahrt m
                                join fahrgemeinschaft.kinder f on f.id = m.fahrer_kind_id
                                where m.kind_id = k.id and m.richtung = r.richtung),
          'faehrt_mit_id', (select m.fahrer_kind_id
                            from fahrgemeinschaft.mitfahrt m
                            where m.kind_id = k.id and m.richtung = r.richtung),
          'mitfahrende', (select coalesce(jsonb_agg(
                                    jsonb_build_object('kind_id', mk.id, 'name', mk.anzeige_name,
                                                       'eltern', mk.eltern_anzeige)
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
