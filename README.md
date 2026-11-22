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
