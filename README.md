# Fahrgemeinschaft

Kleine Eingabeseite für Fahrgemeinschaften zu einem Klassenausflug.
Eine einzige Datei: `index.html`. Sie spricht nur mit den Supabase-Funktionen `public.fg_*`.

## Veröffentlichen (GitHub Pages)

1. Dateien ins Repo `oerny76/fahrgemeinschaft` auf `main` pushen.
2. Auf GitHub: Settings, Pages, "Deploy from a branch", Branch `main`, Ordner `/ (root)`, Save.
3. Nach ein bis zwei Minuten ist die Seite erreichbar unter
   `https://oerny76.github.io/fahrgemeinschaft/`.

## Links pro Familie bauen

Der Zugangscode (Token) kommt hinter `#t=`:

    https://oerny76.github.io/fahrgemeinschaft/#t=<TOKEN>

Beispiel in Google Sheets oder Excel, wenn der Token in Spalte B steht:

    ="https://oerny76.github.io/fahrgemeinschaft/#t="&B2

Wichtig:
- Das Zeichen `#` bleibt stehen, nicht durch `?` ersetzen. Nach dem `#` landet der Code nicht in Server-Logs.
- Jede Familie bekommt ihren eigenen Link. Der Link gibt Zugriff auf die Angaben genau eines Kindes.
- Die Seite entfernt den Code nach dem Laden aus der Adresszeile. Bei Neuladen bitte den Link noch einmal öffnen.

## Sicherheit

- Im Code steht nur der Publishable Key. Der darf öffentlich sein.
- Niemals den service_role Key oder den secret Key in dieses Repo legen.

## Admin-Übersicht

Die Seite `admin.html` zeigt den Gesamtstand und exportiert ihn als CSV.

1. Einmal in Supabase (SQL Editor) die Datei `sql/fg_admin_uebersicht.sql` ausführen.
2. Admin-Code erzeugen und kopieren:

       insert into fahrgemeinschaft.admin_zugang (notiz) values ('Elternbeirat') returning token;

3. Link öffnen: `https://oerny76.github.io/fahrgemeinschaft/admin.html#a=<TOKEN>`
4. Link nicht weitergeben. Er zeigt die Angaben aller Kinder.
5. Code ungültig machen: `delete from fahrgemeinschaft.admin_zugang where token = '<TOKEN>';`

## Admin als App auf dem iPhone

1. Admin-Link in Safari öffnen (`.../admin.html#a=<TOKEN>`), dann Teilen, "Zum Home-Bildschirm".
2. Die App vom Home-Bildschirm starten. Sie hat einen eigenen Speicher und kennt den Code aus Safari nicht.
3. Im Feld "Admin-Code" den Code (oder den ganzen Link) einfügen und "Anmelden" tippen.
   Mit "Auf diesem Gerät angemeldet bleiben" fragt die App nicht mehr nach.
4. "Abmelden" löscht den Code vom Gerät.

Bei Handyverlust den Code in Supabase löschen (siehe oben), dann ist er überall ungültig.

## Admin trägt manuell ein

In der Übersicht hat jede Strecke eine Taste "Ändern". Der Admin kann dort für jedes Kind
"Fährt selbst" (mit Plätzen und Orten), "Sucht einen Platz" (mit Ort und Fahrer),
"Anders geregelt" setzen und Mitfahrende entfernen. Die Familie sieht die Änderung auf ihrer Seite.

Die Admin-Funktionen rufen die bestehenden Funktionen der Eltern-Seite auf, damit dieselben Regeln
gelten (freie Plätze, Wechsel mit Mitfahrenden). Sie stehen in `sql/fg_anmerkung_zustieg_admin.sql`.

## Anmerkung und anderer Ort

Alle Angaben haben jetzt eine freiwillige Anmerkung (bis 200 Zeichen). Dazu gibt es einen anderen Ort
(bis 100 Zeichen): Wer einen Platz sucht, wählt "Anderer Ort" und trägt ihn ein. Wer fährt, kann einen
anderen Treffpunkt für Mitfahrende angeben. Die Anmerkung sehen nur die Beteiligten (Fahrer und Mitfahrende)
und der Admin. Bei "Anders geregelt" sieht sie nur der Admin.

### Einspielen, Reihenfolge

1. In Supabase (SQL Editor) `sql/fg_anmerkung_zustieg_admin.sql` ausführen. Das ist die einzige neue Datei.
   Voraussetzung: `fg_admin_uebersicht.sql` und `fg_mein_status_mitfahrende_mit_id.sql` sind schon eingespielt.
2. Danach die Seiten veröffentlichen. Die bisherigen Seiten laufen auch nach Schritt 1 unverändert weiter.

## Eltern statt Kinder in der Auswahl

Die Tabelle `fahrgemeinschaft.kinder` hat die Spalten `elternteil_1` (Mutter), `elternteil_2` (Vater) und
`eltern_anzeige` (berechnet, z. B. "Mia K. oder Paul K." oder "Eva D."). Die Namen sind
personenbezogen und stehen nur in der Datenbank, nicht in diesem Repo.

Die Seiten zeigen bei Fahrern die Eltern, mit Rückfall auf den Namen des Kindes, wenn keine Eltern
gespeichert sind. Dafür einspielen: `sql/fg_eltern_anzeige.sql` (ersetzt drei Funktionen, enthält keine Namen).
Die Seiten laufen auch ohne diese Datei, zeigen dann aber weiter die Kinder.

## Vorschau: Was sieht die Familie?

In der Admin-Übersicht ist jeder Kindername eine Taste. Ein Klick öffnet die Vorschau der Seite der Familie:
auf dem Desktop als Seitenleiste neben der Tabelle, auf dem Handy als Überlagerung über die ganze Breite.
Die Vorschau ist die echte Eltern-Seite im Vorschau-Modus (`index.html#vorschau`). Sie bekommt ihre Daten
von der Admin-Seite, kennt keinen Zugangscode, alle Eingaben sind gesperrt und sie ruft die Datenbank nicht
selbst auf. Nach einer Änderung im Admin-Dialog lädt sich die Vorschau neu.

Einmal in Supabase einspielen: `sql/fg_admin_vorschau.sql` (liefert dieselben Daten wie die Eltern-Seite).
