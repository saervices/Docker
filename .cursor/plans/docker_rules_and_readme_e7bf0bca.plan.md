---
name: Docker Rules and README
overview: Create a complete set of User Rules and Workspace Rules for the Docker Compose template project, including the distinctive Æ/æ branding system. Additionally, fix inconsistencies in the README and document missing features.
todos:
  - id: user-rules
    content: Write User Rules text block for Cursor Settings + reference copy at .cursor/user-rules-reference.md
    status: completed
  - id: branding-rule
    content: Create .cursor/rules/branding.mdc with full Æ/æ branding specification
    status: completed
  - id: architecture-rule
    content: Create .cursor/rules/architecture.mdc with project structure conventions
    status: completed
  - id: docker-compose-rule
    content: Create .cursor/rules/docker-compose.mdc with YAML conventions
    status: completed
  - id: security-rule
    content: Create .cursor/rules/security.mdc with hardening standards
    status: completed
  - id: shell-scripting-rule
    content: Create .cursor/rules/shell-scripting.mdc with Bash conventions
    status: completed
  - id: templates-rule
    content: Create .cursor/rules/templates.mdc with template creation guide
    status: completed
  - id: workflows-rule
    content: Create .cursor/rules/workflows.mdc with dev workflow documentation
    status: completed
  - id: troubleshooting-rule
    content: Create .cursor/rules/troubleshooting.mdc with debugging guide
    status: completed
  - id: readme-rule
    content: Create .cursor/rules/readme.mdc with README writing standards
    status: completed
  - id: fix-readme
    content: "Fix README.md: correct examples, add missing sections, apply Æ/æ branding"
    status: completed
  - id: fix-scripts
    content: Add --help/-h to run.sh and get-folder.sh, add DIRECTORIES to app_template/.env
    status: completed
  - id: git-rule
    content: Create .cursor/rules/git.mdc with branching, commit conventions, and review process
    status: completed
  - id: env-files-rule
    content: Create .cursor/rules/env-files.mdc with .env conventions, merge logic, and OVERWRITES pattern
    status: completed
  - id: validation-rule
    content: Create .cursor/rules/validation.mdc with pre-commit and post-deployment validation checklist
    status: completed
isProject: false
---

# Docker Compose Template Project: Rules and README Overhaul

## Part 1: User Rules (Cursor Settings)

These rules must be written as a text block that the user manually pastes into **Cursor Settings > General > Rules for AI**. Additionally, a reference copy will be saved at `.cursor/user-rules-reference.md` so the content is version-controlled and visible in the workspace.

**Proposed User Rules content** (high-level, project-agnostic):

- Default communication language: respond in the language the user writes in
- Prefer English for all code, comments, commit messages, and documentation
- Always use Context7 MCP for library documentation lookups
- Shell scripts: always use `bash`, strict mode (`set -euo pipefail`), structured logging
- Docker-first mindset: security-hardened containers, least privilege, Docker secrets over env vars
- Never commit real passwords/secrets; use placeholders like `CHANGE_ME`
- Plans go to `.cursor/plans/`

---

## Part 2: Workspace Rules (`.cursor/rules/*.mdc`)

### 2.1 `branding.mdc` (alwaysApply: true)

The most critical rule -- defines the Danish Æ/æ branding system used throughout all files. The characters are the actual Unicode glyphs: uppercase `Æ` (U+00C6) and lowercase `æ` (U+00E6).

Key content:

- **Character replacement**: In all comments (YAML, Bash, .env, Markdown), replace lowercase `a` with `æ` and uppercase `A` with `Æ`. Code identifiers (variable names, YAML keys, Docker directives) stay in normal English.
- **Main section header** (`#` + 66 `Æ` characters):

```
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- SECTION TITLE
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
```

- **Subsection header** (`#` + 34 `æ` characters):

```
#ææææææææææææææææææææææææææææææææææ
# SUBSECTION TITLE
#ææææææææææææææææææææææææææææææææææ
```

- **.env section titles** include service prefix: `# --- SERVICE --- TITLE` (e.g., `# --- ÆPP --- CONTÆINER BÆSICS`)
- **YAML section titles** omit service prefix: `# --- TITLE` (e.g., `# --- CONTÆINER BÆSICS`)
- **SPDX header**: `# SPDX-License-Identifier: MIT` + `# Copyright (c) 2025 it.særvices`
- Reference examples from [app_template/.env](app_template/.env) and [app_template/docker-compose.app.yaml](app_template/docker-compose.app.yaml)

### 2.2 `architecture.mdc` (alwaysApply: true)

Project structure and layout conventions:

- **Frontend apps**: `<app_name>/` at workspace root (e.g., `app_template/`)
- **Backend templates**: `templates/<service>/` (e.g., `templates/template/`, `templates/redis/`)
- **Root scripts**: `run.sh` (orchestrator), `get-folder.sh` (sparse checkout downloader)
- **Per-app/template folder structure**:
  - `docker-compose.<name>.yaml` -- main compose file
  - `.env` -- environment variables (becomes `app.env` after first run)
  - `secrets/` -- Docker secret files (placeholder content: `CHANGE_ME`)
  - `appdata/` -- persistent application data
  - `scripts/` -- service-specific scripts
  - `dockerfiles/` -- custom Dockerfiles
  - `README.md` -- documentation
- **Generated files** (by `run.sh`, never edit directly):
  - `docker-compose.main.yaml` -- merged compose output
  - `.env` (in deployed apps) -- merged env output
- **Config directory**: `.<script_name>.conf/` stores lockfiles, logs, backups

### 2.3 `docker-compose.mdc` (globs: `**/docker-compose*.yaml`)

Docker Compose conventions:

- **File naming**: `docker-compose.<service>.yaml` -- always lowercase service name
- **Section ordering** within a service (matches current templates):
  1. Container Basics (image, container_name, hostname, restart)
  2. Security Settings (user, read_only, cap_drop, cap_add, security_opt)
  3. System Runtime (init, stop_grace_period, oom_score_adj, tmpfs)
  4. Filesystem and Secrets (volumes, secrets)
  5. Networking / Reverse Proxy (labels, networks)
  6. Runtime / Environment (environment, logging, healthcheck)
  7. Dependencies (depends_on)
  8. System Limits (mem_limit, cpus, pids_limit, shm_size)
- `**x-required-services**`: declare backend dependencies in app compose files
- **YAML anchors**: use `&app_common_*` for shared config (tmpfs, volumes, secrets, environment)
- **Traefik**: always Traefik as reverse proxy; labels mandatory for frontend-facing services
- **Networks**: `frontend` (proxy-facing) + `backend` (internal) -- both external
- **Inline comments**: right-aligned, use Æ/æ branding

### 2.4 `security.mdc` (globs: `**/docker-compose*.yaml, **/secrets/*, **/.env`)

Docker security hardening standards:

- `user: "${APP_UID}:${APP_GID}"` -- non-root by default
- `read_only: true` -- lock root filesystem
- `cap_drop: ALL` -- remove all capabilities, add back only what's needed
- `security_opt: [no-new-privileges:true]`
- Docker secrets for ALL credentials (never plain env vars for passwords)
- Resource limits on every service: `mem_limit`, `cpus`, `pids_limit`, `shm_size`
- `init: true` for proper PID 1 handling
- tmpfs for `/run`, `/tmp`, `/var/tmp`
- Logging rotation: `json-file` driver, `max-size: 10m`, `max-file: 3`
- Bind mounts: `:ro` by default, `:rw` only when explicitly needed
- Secret file permissions: 600 on host
- `.gitignore`: `**/certs/` (already in place)

### 2.5 `shell-scripting.mdc` (globs: `**/*.sh`)

Bash script conventions:

- Shebang: `#!/usr/bin/env bash`
- Strict mode: `set -euo pipefail`
- Constants at top as `readonly`
- Logging functions: `log_ok`, `log_info`, `log_warn`, `log_error`, `log_debug`
- Color codes: GREEN/CYAN/YELLOW/RED/GREY/MAGENTA
- Every destructive action must support `DRY_RUN` mode
- Function documentation style: comment block with function name and description
- Section dividers use same Æ/æ branding as other files
- Error handling: `|| { log_error "..."; return 1; }` pattern
- Dependencies: check with `command -v` and offer interactive install
- Temp files: always use `mktemp` and register cleanup trap

### 2.6 `templates.mdc` (globs: `templates/**`)

Template creation guide:

- Copy `templates/template/` as starting point
- Rename `TEMPLATE` to service name (UPPERCASE in env vars, lowercase in YAML keys)
- Rename compose file: `docker-compose.<service>.yaml`
- Required files: compose YAML, `.env`, `secrets/<SERVICE>_PASSWORD`, `README.md`
- Standalone templates: no YAML anchors, configure each section individually
- Satellite templates: use `x-required-anchors` to inherit shared config from app
- Always include healthcheck (adapt tool to image: curl, wget, nc, pg_isready, etc.)
- Keep Traefik labels commented out for backend-only services

### 2.7 `workflows.mdc` (alwaysApply: true)

Development workflows:

- **Initial setup**: `./get-folder.sh <app_name>` then `./run.sh <app_name>`
- **Update templates**: `./run.sh <app_name> --force`
- **Update images**: `./run.sh <app_name> --update`
- **Generate passwords**: `./run.sh <app_name> --generate_password [file] [length]`
- **Delete volumes**: `./run.sh <app_name> --delete_volumes`
- **Debugging**: `--debug` for verbose output, `--dry-run` for simulation
- **env editing**: always edit `app.env`, never `.env` directly; use OVERWRITES section for template overrides
- **After changes**: run `docker compose -f docker-compose.main.yaml config` to validate

### 2.8 `troubleshooting.mdc` (alwaysApply: true)

Debugging and troubleshooting:

- **Logs location**: `.<script_name>.conf/logs/` (latest 2 retained), `latest.log` symlink
- **Lockfile**: `.<script_name>.conf/.<subfolder>.lock` -- delete to force re-clone
- **Backups**: `.<script_name>.conf/.backups/` created on `--force`
- **Common issues**: permission denied (check APP_UID/APP_GID), healthcheck failures, secret file not found, network not created
- **Validation**: `docker compose --env-file .env -f docker-compose.main.yaml config`
- **Container debugging**: `docker compose logs --tail 100 -f <service>`

### 2.9 `readme.mdc` (globs: `**/*.md`)

README writing standards:

- Every app and template directory MUST have a `README.md`
- Use Æ/æ branding in all prose (`a` -> `æ`, `A` -> `Æ`)
- Required sections: Quick Start, Environment Variables (table), Secrets (table), Security Highlights, Verification
- Verification section must include `docker compose config` command
- SPDX header not required in Markdown files

### 2.10 `git.mdc` (alwaysApply: true)

Git workflow and commit conventions:

- **Branching**: always commit to the `cursor` branch, never directly to `main`
- **Pre-commit review**: always show `git status` + `git diff --stat` and ask the user if they want to review changes before committing
- **Commit messages**: Conventional Commits format in English (`feat`, `fix`, `docs`, `chore`, `refactor`, `style`, `test`, `ci`)
- **Scope**: use affected area as scope (`run`, `get-folder`, `templates`, `app-template`, `rules`, `readme`, `env`, `security`)
- **Commit granularity**: bundle when changes serve the same logical purpose; separate when they serve different purposes
- **Safety**: never force-push to `main`, never amend pushed commits, never commit real secrets

### 2.11 `env-files.mdc` (globs: `**/.env, **/app.env`)

Environment file conventions:

- **File roles**: `app.env` (editable) vs `.env` (generated, never edit) vs `templates/<service>/.env` (template defaults)
- **Lifecycle**: `.env` renamed to `app.env` on first run; merged output written to `.env`
- **Merge behavior**: first key wins; duplicates trigger warning
- **Variable naming**: `SERVICE_VARNAME` pattern (e.g., `APP_IMAGE`, `REDIS_PASSWORD_PATH`)
- **OVERWRITES section**: bottom of `app.env` for overriding template defaults
- **Standard sections**: CONTAINER BASICS (incl. `DIRECTORIES`), TRAEFIK, FILESYSTEM & SECRETS, SYSTEM LIMITS, ENVIRONMENT VARIABLES, OVERWRITES
- **Values format**: no quotes, no spaces around `=`, no trailing whitespace

### 2.12 `validation.mdc` (globs: compose + env files)

Pre-commit and post-deployment validation checklist:

1. Docker Compose configuration validation (`docker compose config`)
2. Environment variable completeness (check all `?`-marked required vars)
3. Secret placeholder file verification (`CHANGE_ME` content, path/filename pairs)
4. Healthcheck validity (command available in image, correct port/endpoint)
5. Æ/æ branding compliance (comments, section headers, SPDX)
6. Security baseline (read_only, cap_drop, no-new-privileges, init, logging, secrets, resource limits)
7. Network configuration (frontend + backend for apps, backend only for services)
- Post-deployment: `docker compose ps`, `docker compose logs`, health status inspection

---

## Part 3: README.md Improvements

Identified issues in the current [README.md](README.md):

### 3.1 Command Examples Missing Project Folder Argument

The "Command-Line Options" examples section is incorrect. All commands require the project folder as the first positional argument, but several examples omit it:

```bash
# Current (WRONG):
./run.sh --force
./run.sh --update
./run.sh --dry-run
./run.sh --debug
./run.sh --delete_volumes

# Correct:
./run.sh app_template --force
./run.sh app_template --update
./run.sh app_template --dry-run
./run.sh app_template --debug
./run.sh app_template --delete_volumes
```

### 3.2 Missing Documentation

- The `DIRECTORIES` env variable (used by `run.sh` to set permissions via `set_permissions()`) is not documented anywhere in the README or .env templates. This should be added to the app_template `.env` file and documented in the README.
- Log file location (`.<script_name>.conf/logs/`) is not documented.
- Backup mechanism (`.<script_name>.conf/.backups/`) is mentioned only implicitly.

### 3.3 get-folder.sh Options Not Fully Documented

The README only shows basic usage. The script supports `--debug`, `--dry-run`, and `--force`, which should be documented.

### 3.4 Missing `--help` / `-h` Flag

Neither `run.sh` nor `get-folder.sh` supports `--help` or `-h`. Both have a `usage()` function but no way to invoke it from the command line. Suggest adding `-h|--help` to both scripts.

### 3.5 Proposed README Sections to Add/Fix

- Fix all command examples with project folder argument
- Add `get-folder.sh` options table
- Add a "Troubleshooting" section
- Add a "Logging and Backups" section
- Document `DIRECTORIES` env var in the environment table
- Add `--help` to examples once implemented

---

## Part 4: Script Improvements

### 4.1 Add `--help`/`-h` to both scripts

Add to `parse_args()` in both [run.sh](run.sh) and [get-folder.sh](get-folder.sh):

```bash
-h|--help)
  usage
  exit 0
  ;;
```

### 4.2 Add `DIRECTORIES` to app_template `.env`

The `run.sh` script reads `DIRECTORIES` from `.env` to set permissions, but the template `.env` doesn't include it. Add:

```
DIRECTORIES=appdata
```

### 4.3 Æ/æ branding in README.md

The main [README.md](README.md) currently uses normal English. According to the branding rules, all prose should use Æ/æ. This applies to the main README and both sub-READMEs.

---

## Summary of Files Created/Modified

**New files (13):**

- `.cursor/user-rules-reference.md` — reference copy of User Rules for Cursor Settings
- `.cursor/rules/branding.mdc` — Æ/æ branding specification
- `.cursor/rules/architecture.mdc` — project structure conventions
- `.cursor/rules/docker-compose.mdc` — Docker Compose YAML conventions
- `.cursor/rules/security.mdc` — security hardening standards
- `.cursor/rules/shell-scripting.mdc` — Bash script conventions
- `.cursor/rules/templates.mdc` — template creation guide
- `.cursor/rules/workflows.mdc` — development workflow documentation
- `.cursor/rules/troubleshooting.mdc` — debugging and troubleshooting guide
- `.cursor/rules/readme.mdc` — README writing standards
- `.cursor/rules/git.mdc` — Git workflow, branching, and commit conventions
- `.cursor/rules/env-files.mdc` — environment file conventions and merge logic
- `.cursor/rules/validation.mdc` — pre-commit and post-deployment validation checklist

**Modified files (4):**

- `README.md` — fixed command examples (added project folder argument), added missing sections (Key Environment Variables, Logging and Backups, Troubleshooting, get-folder.sh options), applied Æ/æ branding
- `run.sh` — added `-h`/`--help` flag to `parse_args()`
- `get-folder.sh` — added `-h`/`--help` flag to `parse_args()`
- `app_template/.env` — added `DIRECTORIES=appdata` to CONTÆINER BÆSICS section

