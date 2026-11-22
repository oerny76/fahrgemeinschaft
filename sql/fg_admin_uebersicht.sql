-- Vorschlag, NICHT automatisch ausgeführt. Bitte im Supabase SQL Editor einspielen.
-- Zweck: Gesamtübersicht für die Admin-Seite (admin.html).
-- Sicherheit: Die Funktion liefert nur Daten, wenn ein gültiger Admin-Code übergeben wird.
-- Der Code steht in einer eigenen Tabelle, die für den öffentlichen Key nicht lesbar ist (RLS ohne Policy).

create table if not exists fahrgemeinschaft.admin_zugang (
  token text primary key default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  notiz text,
  erstellt_am timestamptz not null default now()
);
alter table fahrgemeinschaft.admin_zugang enable row level security;
revoke all on fahrgemeinschaft.admin_zugang from anon, authenticated;

create or replace function public.fg_admin_uebersicht(p_admin_token text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
begin
  if p_admin_token is null
     or not exists (select 1 from fahrgemeinschaft.admin_zugang where token = p_admin_token) then
    raise exception 'Ungültiger Zugangslink.';
  end if;

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
          'plaetze_frei', b.plaetze_frei,
          'stationen', b.stationen,
          'aktualisiert_am', b.aktualisiert_am,
          'faehrt_mit', (select f.anzeige_name
                         from fahrgemeinschaft.mitfahrt m
                         join fahrgemeinschaft.kinder f on f.id = m.fahrer_kind_id
                         where m.kind_id = k.id and m.richtung = r.richtung),
          'mitfahrende', (select coalesce(jsonb_agg(mk.anzeige_name order by mk.id), '[]'::jsonb)
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

revoke all on function public.fg_admin_uebersicht(text) from public;
grant execute on function public.fg_admin_uebersicht(text) to anon, authenticated;

-- Admin-Code erzeugen (einmal ausführen, Ergebnis kopieren):
-- insert into fahrgemeinschaft.admin_zugang (notiz) values ('Elternbeirat') returning token;
-- Link: https://oerny76.github.io/fahrgemeinschaft/admin.html#a=<TOKEN>
-- Code später ungültig machen: delete from fahrgemeinschaft.admin_zugang where token = '<TOKEN>';
