-- Vorschlag, NICHT automatisch ausgeführt.
-- Einzige Änderung gegenüber der bestehenden Funktion:
-- "mitfahrende" liefert statt ["Tim J."] jetzt [{"kind_id": "K09", "name": "Tim J."}].
-- Damit kann die Seite die Taste "Entfernen" anzeigen (fg_mitfahrer_entfernen braucht die kind_id).
-- Die Seite versteht beide Formen, es ist also keine Eile beim Einspielen nötig.

CREATE OR REPLACE FUNCTION public.fg_mein_status(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
          'plaetze_frei', b.plaetze_frei,
          'stationen', b.stationen,
          'von', case when b.status = 'suche' then
                   case when r.richtung = 'hin'
                        then case b.ort_typ when 'schule' then 'Schule' else v_ort end
                        else 'Bahnhof Meitingen' end end,
          'nach', case when b.status = 'suche' then
                   case when r.richtung = 'hin'
                        then 'Bahnhof Meitingen'
                        else case b.ort_typ when 'schule' then 'Schule' else v_ort end end end,
          'faehrt_mit', (select jsonb_build_object('kind_id', f.id, 'name', f.anzeige_name, 'stationen', fb.stationen)
                         from fahrgemeinschaft.mitfahrt m
                         join fahrgemeinschaft.kinder f on f.id = m.fahrer_kind_id
                         join fahrgemeinschaft.bedarf fb on fb.kind_id = m.fahrer_kind_id and fb.richtung = m.richtung
                         where m.kind_id = v_id and m.richtung = r.richtung),
          'mitfahrende', (select coalesce(jsonb_agg(jsonb_build_object('kind_id', mk.id, 'name', mk.anzeige_name) order by mk.id), '[]'::jsonb)
                          from fahrgemeinschaft.mitfahrt m
                          join fahrgemeinschaft.kinder mk on mk.id = m.kind_id
                          where m.fahrer_kind_id = v_id and m.richtung = r.richtung)
        ) as obj
        from (values ('hin'), ('rueck')) as r(richtung)
        left join fahrgemeinschaft.bedarf b on b.kind_id = v_id and b.richtung = r.richtung
      ) s
    )
  );
end $function$;
