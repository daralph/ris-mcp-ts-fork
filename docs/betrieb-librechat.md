# Betrieb mit LibreChat

Anleitung für Betreiber:innen, die den RIS-MCP-Server als Container im Compose-Netz einer
bestehenden LibreChat laufen lassen. Die Kurzfassung mit Fehlersuche steht im
[README](../README.md#anleitung-deutsch); hier steht, was für Einbau, Betrieb und Rückbau
zusätzlich nötig ist.

Image: `ghcr.io/daralph/ris-mcp-ts-fork`. Die Tags folgen dem Schema
`fork-<Upstream-Version>-<Nr>` (z. B. `fork-1.9.0-1`); `stable` zeigt auf das jeweils letzte.

## 1. Voraussetzungen

- LibreChat mit Docker Compose (Ordner mit `docker-compose.yml`, `.env`, `librechat.yaml`).
- Der Host darf Images von `ghcr.io` ziehen.

## 2. Einbau

1. `examples/librechat/docker-compose.override.yml` neben die `docker-compose.yml` der
   LibreChat legen. Gibt es dort schon eine Override-Datei, den Dienst `ris-mcp` und den
   Volume-Eintrag bei `api` übernehmen.
2. Den Block aus `examples/librechat/librechat.yaml` in die eigene `librechat.yaml` unter
   `mcpServers` einfügen.
3. In der `.env` der LibreChat (beide Variablen sind optional):

   | Variable | Bedeutung |
   |---|---|
   | `RIS_MCP_IMAGE_TAG` | Image-Tag, Standard `stable`. Für nachvollziehbare Stände einen festen Tag setzen, z. B. `fork-1.9.0-1`. |
   | `RIS_MCP_AUTH_TOKEN` | Bearer-Token für `/mcp`, z. B. aus `openssl rand -hex 32`. Leer = ohne Token. |

4. `docker compose up -d` ausführen. Nach Änderungen an `librechat.yaml` den Dienst `api`
   neu starten.

**Mit oder ohne Token:** Der Dienst veröffentlicht keinen Port und ist nur im Compose-Netz
erreichbar. Ein Token schützt zusätzlich gegen andere Container im selben Netz. Mit Token
bleiben die zwei `headers`-Zeilen im `librechat.yaml`-Block stehen, ohne Token werden sie
gelöscht.

## 3. Ressourcen

Aus `examples/librechat/docker-compose.override.yml`:

- Speicher: `mem_limit: 512m`
- Prozesse: `pids_limit: 128`
- Wurzeldateisystem schreibgeschützt (`read_only: true`), keine Capabilities
  (`cap_drop: [ALL]`), `no-new-privileges`. Der Server schreibt keine Dateien.
- CPU und Plattenplatz: keine Vorgabe im Repository, vom Betreiber zu prüfen. Außer dem
  Image belegt der Container keinen Plattenplatz.

## 4. Netz

- Eingehend: kein veröffentlichter Port. LibreChat erreicht den Dienst unter
  `http://ris-mcp:3000/mcp`.
- Ausgehend: ausschließlich HTTPS (Port 443) zu `data.bka.gv.at`, `www.ris.bka.gv.at` und
  `ris.bka.gv.at`. Andere Ziele lehnt der Server ab (`src/client.ts`).

## 5. LibreChat-Seite

- `timeout: 60000`, `initTimeout: 15000` (Millisekunden). Ein Abruf beim RIS läuft
  höchstens 30 Sekunden.
- `chatMenu: true` bietet den Server allen Nutzer:innen im MCP-Menü des Chats an.
- `serverInstructions: true` gibt dem Modell die Gebrauchsanweisung des Servers mit
  (welches Tool wofür, wie zitieren).
- LibreChat stellt die interaktiven Ansichten (Trefferliste, Dokumentansicht) nicht dar.
  Die Textantwort ist vollständig. Darum läuft der Server hier zustandslos
  (`MCP_STATELESS: 'true'`) und übersteht Neustarts ohne Sitzungsverlust.
- Alle Nutzer:innen kommen aus Sicht des Servers von einer IP. Das Beispiel setzt darum
  `RATE_LIMIT_PER_MINUTE: '600'` statt des Standards 60.
- Blockiert der SSRF-Schutz der LibreChat den internen Dienstnamen, `ris-mcp:3000` in
  `librechat.yaml` unter `mcpSettings.allowedAddresses` eintragen. Dieser Punkt ist noch
  nicht in einer laufenden LibreChat bestätigt.

## 6. Betrieb

- Logs: `docker compose logs ris-mcp`
- Zustand: `GET /health` (ohne Token); das Image bringt einen Docker-Healthcheck mit,
  `docker compose ps` zeigt `healthy`.
- Update: `RIS_MCP_IMAGE_TAG` auf den neuen Tag setzen, dann `docker compose pull ris-mcp`
  und `docker compose up -d ris-mcp`.
- Rückfall: den vorigen Tag eintragen und dieselben zwei Befehle ausführen.
- Rückbau: den Dienst `ris-mcp` aus der Override-Datei und den Eintrag `ris` aus
  `librechat.yaml` entfernen, `docker compose up -d --remove-orphans`.
- Ein Image vorab prüfen: `bash scripts/fork/smoke-test.sh <image>` (Healthcheck,
  `initialize`, 13 Tools, 401 ohne und 200 mit Token).

## 7. Datenhaltung

- Der Server speichert nichts dauerhaft und kennt keine Nutzerkennung. Es gibt nur einen
  Dokument-Cache im Arbeitsspeicher: höchstens 10 Einträge, 1.000.000 Zeichen, 10 Minuten
  (`src/document-cache.ts`). Im zustandslosen Betrieb lebt er nur für eine Anfrage.
- Nach außen gehen die Suchparameter und Dokument-Adressen, und zwar nur an das
  Rechtsinformationssystem des Bundes (siehe Abschnitt 4).
- Die RIS-Daten stehen unter CC BY 4.0. Jede erfolgreiche Antwort trägt die Quellenangabe.
