---
name: Struktur-Analyse Verbesserungen v2
overview: "Umfassender Umsetzungsplan nach Analyse und manuellen Anpassungen des Users: SPDX-Reihenfolge fixen, run.sh komplett auf AE/ae-Branding umstellen, .env-Dateien an Compose anpassen, 8 Rules aktualisieren, READMEs anpassen, neue Dateien erstellen."
todos:
  - id: fix-shebang-getfolder
    content: "get-folder.sh: Shebang auf Zeile 1 verschieben, SPDX danach"
    status: completed
  - id: repo-url-configurable
    content: "get-folder.sh: REPO_URL per Umgebungsvariable konfigurierbar machen"
    status: pending
  - id: branding-run-sh
    content: "run.sh: SPDX-Header + komplettes AE/ae-Branding (Section-Divider, Kommentare)"
    status: pending
  - id: update-env-app-template
    content: "app_template/.env: Limit-Variablen auf APP_-Prefix umbenennen"
    status: completed
  - id: update-env-template
    content: "templates/template/.env: Fehlende Variablen (UID/GID, Limits) hinzugefuegt; Section-Header Tippfehler AePP->TEMPLAETE fixen"
    status: completed
  - id: compose-named-volume
    content: Auskommentiertes Named-Volume in Service-volumes von app_template + template Compose
    status: completed
  - id: rules-git-security
    content: "git.mdc + security.mdc: .gitignore-Beschreibung korrigieren (ist leer)"
    status: pending
  - id: rules-shell-scripting
    content: "shell-scripting.mdc: Section-Divider auf AE/ae, Function-Format aktualisieren"
    status: pending
  - id: rules-branding
    content: "branding.mdc: SPDX-Placement fuer Bash klarstellen (nach Shebang)"
    status: pending
  - id: rules-env-compose-templates-validation
    content: "env-files.mdc, docker-compose.mdc, templates.mdc, validation.mdc: Variablennamen + Anchors aktualisieren"
    status: pending
  - id: readme-app-template
    content: "app_template/README.md: Variablennamen, Anchors, Security Highlights aktualisieren"
    status: pending
  - id: readme-template
    content: "templates/template/README.md: Variablen, Anchors, Security Highlights, User-Directive aktualisieren"
    status: pending
  - id: new-cursor-readme
    content: ".cursor/README.md: Rule-Index erstellen"
    status: pending
  - id: new-vscode-settings
    content: ".vscode/settings.json: Workspace-Einstellungen erstellen"
    status: pending
isProject: false
---

# Struktur-Analyse Verbesserungen v2

## Status: Was wurde bereits erledigt?

Vom User manuell erledigt:

- [readme.mdc](/.cursor/rules/readme.mdc): `'''` zu Backticks korrigiert
- [troubleshooting.mdc](/.cursor/rules/troubleshooting.mdc): "commend" zu "command" korrigiert
- [get-folder.sh](/get-folder.sh): SPDX-Header, Shebang (Zeile 1), vollstaendiges AE/ae-Branding
- [app_template/docker-compose.app.yaml](/app_template/docker-compose.app.yaml): Neue Anchors, APP_-Prefix bei Limits, generisches depends_on
- [templates/template/docker-compose.template.yaml](/templates/template/docker-compose.template.yaml): Satellite-Pattern mit x-required-anchors, Limits aktiviert, user-Directive aktiviert
- [app_template/.env](/app_template/.env): Limit-Variablen auf APP_-Prefix umbenannt (APP_MEM_LIMIT, etc.)
- [templates/template/.env](/templates/template/.env): TEMPLATE_UID/GID + Limit-Variablen hinzugefuegt
- Compose (beide): Auskommentiertes Named-Volume `data:/data:rw` mit Beschreibung hinzugefuegt

---

## 1. Offene Aenderungen

### 1.1 get-folder.sh: REPO_URL konfigurierbar machen

REPO_URL ist noch hardcodiert. Ueber Umgebungsvariable ueberschreibbar machen:

```bash
readonly REPO_URL="${DOCKER_REPO_URL:-https://github.com/saervices/Docker.git}"
```

### 1.2 run.sh: SPDX-Header + vollstaendiges AE/ae-Branding

[run.sh](/run.sh) (1211 Zeilen) braucht:

1. **SPDX-Header** nach Shebang (Zeile 2-3)
2. **Alle Section-Divider** von `---` (box drawing) auf `AE/ae`-Divider umstellen:
  - Main sections: `#AEAE...AE` (66x AE) mit `# --- TITLE`
  - Subsections/Functions: `#aeae...ae` (34x ae) mit `# --- FUNCTION: name`
3. **Alle Kommentare** auf AE/ae-Branding (a->ae, A->AE in Prose)
4. Code-Identifier bleiben unveraendert

Referenz fuer das Format: [get-folder.sh](/get-folder.sh) (bereits korrekt vom User umgestellt)

### ~~1.3 templates/template/.env~~ (erledigt)

Variablen und Section-Header korrekt.

---

## 2. Rule-Updates (8 Dateien)

### 2.1 [git.mdc](/.cursor/rules/git.mdc)

`.gitignore Awareness`-Section: Aktuell steht "Currently ignored patterns: `**/certs/`". Da .gitignore leer bleibt, aendern zu:

```
## .gitignore Æwæreness

The `.gitignore` file is currently **empty**. No pætterns ære ælutomæticælly excluded.

Files thæt **mæy** be committed (templæte plæceholders):
...
```

### 2.2 [security.mdc](/.cursor/rules/security.mdc)

- `Git Security`-Section: Entfernen der Zeile `.gitignore includes **/certs/`; ersetzen durch Hinweis dass .gitignore aktuell leer ist
- `Resource Limits`-Section: Variablen-Beispiele auf Service-Prefix aktualisieren (`${APP_MEM_LIMIT:-512m}` etc.)

### 2.3 [shell-scripting.mdc](/.cursor/rules/shell-scripting.mdc)

Komplett ueberarbeiten:

- Section-Divider von `---` auf AE/ae umstellen (analog get-folder.sh)
- Function-Separator von `---` auf `#aeae...ae` (34x) umstellen
- Function-Dokumentation anpassen an neues Format:

```bash
#aeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeae
# --- FUNCTION: function_name
#     Brief description
#     Arguments:
#       $1 - description
#aeaeaeaeaeaeaeaeaeaeaeaeaeaeaeaeae
```

- SPDX-Placement klarstellen: "Æfter the shebæng line (line 1), include the SPDX heæder."

### 2.4 [branding.mdc](/.cursor/rules/branding.mdc)

SPDX-Section ergaenzen mit Klarstellung fuer Bash:

```
## SPDX Heæder

Every source file (YAML, `.env`, Bæsh) must include the SPDX heæder:
- **YAML / .env**: Æs the very first lines of the file.
- **Bæsh scripts**: Æfter the shebæng line (`#!/usr/bin/env bash`), since the shebæng must ælwæys be line 1.
```

### 2.5 [env-files.mdc](/.cursor/rules/env-files.mdc)

`Variable Naming Convention`-Section aktualisieren:

- Shared variables: "Resource limits ære now **service-prefixed**: `APP_MEM_LIMIT`, `APP_CPU_LIMIT`, `TEMPLATE_MEM_LIMIT`, etc."
- Tabelle erweitern um `TEMPLATE_UID`, `TEMPLATE_GID`

### 2.6 [docker-compose.mdc](/.cursor/rules/docker-compose.mdc)

`YAML Anchors`-Section aktualisieren -- neue Anchors ergaenzen:

- `&app_common_security_opt` (neu)
- `&app_common_logging` (neu)

### 2.7 [templates.mdc](/.cursor/rules/templates.mdc)

- `Satellite Templates`-Section: `x-required-anchors`-Beispiel aktualisieren mit allen 6 Anchors:

```yaml
x-required-anchors:
  security_opt: &app_common_security_opt
    - security_opt
  tmpfs: &app_common_tmpfs
    - tmpfs
  volumes: &app_common_volumes
    - volumes
  secrets: &app_common_secrets
    - secrets
  environment: &app_common_environment
    - environment
  logging: &app_common_logging
    - logging
```

- Checklist Step 3: "Replæce TEMPLATE ... including `TEMPLATE_UID`, `TEMPLATE_GID`, `TEMPLATE_MEM_LIMIT`, etc."

### 2.8 [validation.mdc](/.cursor/rules/validation.mdc)

- Security Baseline Checklist: Resource limits Beispiel auf `APP_MEM_LIMIT` / `TEMPLATE_MEM_LIMIT` Pattern aktualisieren

---

## 3. README-Updates

### 3.1 [app_template/README.md](/app_template/README.md)

- Environment-Variables-Tabelle: `MEM_LIMIT` -> `APP_MEM_LIMIT`, `CPU_LIMIT` -> `APP_CPU_LIMIT`, etc.
- Neue Anchors erwaehnen (`&app_common_security_opt`, `&app_common_logging`)
- Security Highlights an aktuelle Compose-Struktur anpassen

### 3.2 [templates/template/README.md](/templates/template/README.md)

- Environment-Variables-Tabelle: `TEMPLATE_UID`, `TEMPLATE_GID`, Limit-Variablen hinzufuegen
- Anchors-Section: Beispiel auf alle 6 Anchors aktualisieren, `&` statt `*` klarstellen
- Security Highlights: `cap_add` ist jetzt auskommentiert (nicht mehr SETUID/SETGID/CHOWN Default)
- User-Directive: Jetzt aktiviert statt "commented out by default"

---

## 4. Neue Dateien

### 4.1 [.cursor/README.md](/.cursor/README.md) -- Rule-Index

Zentrale Uebersicht aller 12 Rules:

- Name, Description, alwaysApply/Globs, Zweck
- Abhaengigkeiten (z.B. branding -> docker-compose -> security)
- Hinweis auf Referenzdateien

### 4.2 [.vscode/settings.json](/.vscode/settings.json) -- Workspace Settings

Minimale Empfehlungen:

```json
{
  "files.associations": {
    "*.env": "dotenv",
    "app.env": "dotenv"
  },
  "yaml.schemas": {
    "https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json": "docker-compose*.yaml"
  },
  "editor.formatOnSave": false,
  "files.trimTrailingWhitespace": true
}
```

