# Super-Papagei auf einem UGREEN-NAS (UGOS Pro)

Ohne Kommandozeile, nur über die Docker-App von UGOS. Auf anderen NAS mit Docker-Oberfläche (Synology Container Manager, QNAP Container Station) läuft es sinngemäß gleich.

## 1. Image holen

1. **Docker → Image → Lokal → Image hinzufügen → Von Paketquelle**
2. Imagename: `ghcr.io/hendrikheidsiek/super-papagei`, Version: `latest`
3. **Bestätigen**.

## 2. Container erstellen

Beim Image auf **+** klicken.

- **Containername:** `super-papagei`, **Automatischer Neustart:** an
- **Port:** einen freien NAS-Port (z. B. `8380`) auf Container-Port `8080`

**Volumes**

| NAS-Ordner | Pfad im Container | Rechte |
|---|---|---|
| deine Hörbuch-Freigabe | `/audiobooks` | Nur-Lesen |
| ein eigener Ordner, z. B. `docker/super-papagei/data` | `/data` | Lesen/Schreiben |

`/data` enthält Datenbank (Konten, Fortschritt, Lesezeichen), Profilbilder und Cover-Cache. Diesen Ordner ins Backup aufnehmen.

Achtung beim Ordner-Auswählen: UGOS übernimmt den Ordner, der im Dialog **geöffnet** ist, nicht die markierte Zeile. Also in den Zielordner hineinklicken und dann bestätigen. Danach mit der Maus auf den Pfad zeigen und prüfen.

**Umgebungsvariablen** (vorbelegt, nur anpassen)

- `ADMIN_USERNAME`: dein Benutzername
- `ADMIN_PASSWORD`: UGOS akzeptiert keine leeren Werte. Entweder ein Passwort eintragen oder die Zeile mit ⊖ entfernen; dann steht ein Zufallspasswort einmalig im Container-Protokoll. **Sofort notieren.**
- `PUID` / `PGID`: von UGOS vorbelegt, so lassen
- `PORT`, `LIBRARY_PATH`, `DATA_PATH`: nicht ändern

## 3. Prüfen

- Browser: `http://<NAS-IP>:8380/api/health` → `{"ok":true,…}`
- Container → `super-papagei` → **Protokoll**: nach ein bis zwei Minuten `scan done`.

## 4. Updates

**Container → super-papagei → ⋯ → Aktualisieren → Version `latest` → Bestätigen.** UGOS holt das neue Image und behält alle Einstellungen. Die Daten in `/data` bleiben erhalten.

Prüfen: Im Protokoll darf danach **nicht** „Admin-Konto angelegt“ stehen, sonst ist der falsche `/data`-Ordner eingebunden.

## Admin-Passwort vergessen

Im Datenordner eine Textdatei `passwort-zuruecksetzen.txt` mit dem neuen Passwort anlegen (mindestens 8 Zeichen). Der Server übernimmt es innerhalb von 20 Sekunden und löscht die Datei; im Protokoll steht dann „Neues Passwort … gesetzt“.
