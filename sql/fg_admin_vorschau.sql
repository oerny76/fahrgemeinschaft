-- Vorschlag, NICHT automatisch ausgeführt. Bitte im Supabase SQL Editor einspielen.
-- Zweck: Der Admin sieht in einer Vorschau, was die Familie eines Kindes auf ihrer Seite sieht.
--
-- Die Funktion liefert genau die Daten, die die Eltern-Seite für dieses Kind bekommt:
--   fg_mein_status (Stand beider Strecken) und fg_angebote (freie Plätze, je Strecke).
-- Dafür ruft sie die bestehenden Funktionen mit dem Zugangscode des Kindes auf.
-- Der Zugangscode des Kindes verlässt die Datenbank dabei nicht. Es wird nur der Inhalt geliefert.
--
-- Voraussetzung (schon eingespielt): fg_anmerkung_zustieg_admin.sql (Hilfsfunktionen admin_pruefen
-- und zugang_zu_kind) und fg_eltern_anzeige.sql.
-- Diese Datei enthält KEINE Namen.

create or replace function public.fg_admin_vorschau(p_admin_token text, p_kind_id text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare v_token text;
begin
  perform fahrgemeinschaft.admin_pruefen(p_admin_token);
  v_token := fahrgemeinschaft.zugang_zu_kind(p_kind_id);
  return jsonb_build_object(
    'status', public.fg_mein_status(v_token),
    'angebote', jsonb_build_object(
      'hin', public.fg_angebote(v_token, 'hin'),
      'rueck', public.fg_angebote(v_token, 'rueck')));
end $function$;

revoke all on function public.fg_admin_vorschau(text, text) from public;
grant execute on function public.fg_admin_vorschau(text, text) to anon, authenticated;
