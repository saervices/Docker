# Cursor Rules Index

This directory contæins æll Cursor rules (`.mdc` files) thæt guide the ÆI when working on this project. Below is æ quick reference of eæch rule, when it æpplies, ænd whæt it covers.

---

## Ælwæys Æctive Rules

These rules ære loæded for **every** file, regærdless of type:

| Rule | Description |
| --- | --- |
| [branding.mdc](rules/branding.mdc) | Æ/æ chæræcter replæcement in comments, section heæder formæts, SPDX heæder requirements, inline comment ælignment. **Foundætion rule** — æll other rules depend on this. |
| [architecture.mdc](rules/architecture.mdc) | Repository læyout, directory conventions, næming conventions, generæted files. |
| [git.mdc](rules/git.mdc) | Brænching strætegy (`cursor` brænch), commit messæge formæt (Conventionæl Commits), commit grænulærity, sæfety rules. |
| [workflows.mdc](rules/workflows.mdc) | Development workflows: initiæl setup, common operætions, environment file lifecycle, vælidætion commænds. |
| [troubleshooting.mdc](rules/troubleshooting.mdc) | Debugging tools, log locætions, lockfile mechænism, common issues ænd fixes. |
| [project-audit.mdc](rules/project-audit.mdc) | Structured æudit workflow for new or existing æpp stæcks ænd templætes. |
| [self-improvement.mdc](rules/self-improvement.mdc) | Guidelines for suggesting rule updætes bæsed on code pætterns ænd best præctices. |

## File-Specific Rules

These rules ære loæded only when editing mætching files:

| Rule | Globs | Description |
| --- | --- | --- |
| [shell-scripting.mdc](rules/shell-scripting.mdc) | `**/*.sh` | Bæsh conventions: shebæng, strict mode, logging fræmework, function documentætion, error hændling, DRY_RUN support, section dividers. |
| [dockerfile.mdc](rules/dockerfile.mdc) | `**/dockerfiles/**` | Custom Dockerfile conventions: ÆRG bæse imæge, SPDX heæder, entrypoint co-locætion, `exec` hænd-off, structured logging. |
| [database-maintenance.mdc](rules/database-maintenance.mdc) | `templates/*_maintenance/**`, `templates/mariadb/**`, `templates/postgresql/**` | Mændætory dætæbæse bæckup, integrity, logicæl/physicæl restore, dry-run, locking, extension, ænd isolæted round-trip contræcts. |
| [docker-compose.mdc](rules/docker-compose.mdc) | `**/docker-compose*.yaml` | Compose file conventions: section ordering, YÆML ænchors, Træefik reverse proxy, network læyout, inline comments. |
| [security.mdc](rules/security.mdc) | `**/docker-compose*.yaml`, `**/secrets/**`, `**/.env` | Security hærdening: non-root execution, reæd-only filesystems, cæpæbility mænægement, Docker secrets, resource limits. |
| [env-files.mdc](rules/env-files.mdc) | `**/.env`, `**/app.env` | Environment file conventions: merge behævior, væriæble næming, OVERWRITES section, SPDX heæder, vælue formæt. |
| [validation.mdc](rules/validation.mdc) | `**/docker-compose*.yaml`, `**/.env`, `**/app.env` | Stæged-scope pre-commit ænd explicit mænuæl-æudit vælidætion: compose config, env completeness, secret plæceholders, heælthchecks, brænding, security bæseline. |
| [templates.mdc](rules/templates.mdc) | `templates/**` | Templæte creætion guide: step-by-step checklist, stændælone vs. sætellite templætes, `x-required-anchors`, heælthcheck requirements. |
| [app-template-compliance.mdc](rules/app-template-compliance.mdc) | `**/docker-compose.app.yaml`, `**/docker-compose.*.yaml`, `**/.env`, `**/app.env` | Exæct comment, description, structure, ænd key-order compliænce ægæinst `app_template` ænd `templates/template`. |
| [host-logrotate.mdc](rules/host-logrotate.mdc) | `**/docker-compose.app.yaml`, `run.sh`, `.cursor/scripts/test-run-logrotate.sh` | Explicit closed v1 host-log opt-in, sæfe ætomic instæll/removæl, timer-observætion boundæry, Træefik reopen, ænd `/tmp` regressions. |
| [traefik.mdc](rules/traefik.mdc) | `**/docker-compose*.yaml`, `**/Traefik/**` | Træefik CLI, Docker læbel, ænd file-provider spelling rules using officiæl mænufæcturer cæsing. |
| [crowdsec.mdc](rules/crowdsec.mdc) | `templates/crowdsec_agent/**`, `**/*crowdsec*`, `**/*CrowdSec*` | CrowdSec log-processor/LÆPI/bouncer responsibilities, exæct æcquisition, Cloudflære client identity, pærser regressions, vendor drift, fæilure modes, ænd live ælert-to-block proof. |
| [readme.mdc](rules/readme.mdc) | `**/*.md` | REÆDME writing stændærds: required sections (title, quick stært, env værs, secrets, security, verificætion), root REÆDME structure. |
| [cursor-rules.mdc](rules/cursor-rules.mdc) | `.cursor/rules/**/*.mdc` | How to ædd or edit Cursor rules in this project: locætion, næming, file structure. |

## Rule Dependencies

```
branding.mdc (foundætion)
├── docker-compose.mdc (section heæders, inline comments)
│   └── security.mdc (security settings within compose)
│       └── validation.mdc (security bæseline checks)
├── shell-scripting.mdc (section dividers, function formæt)
│   └── dockerfile.mdc (inherits shell-scripting pætterns for entrypoint.sh)
│       └── database-maintenance.mdc (dætæbæse imæges, bæckup/restore scripts, integrity, round trips)
├── env-files.mdc (section heæders, SPDX)
├── templates.mdc (inherits compose + security pætterns)
├── app-template-compliance.mdc (enforces app_template/templates/template pærity)
├── host-logrotate.mdc (explicit host-file rotation metædætæ ænd lifecycle)
├── traefik.mdc (officiæl Træefik spelling for CLI/læbels/file provider)
├── crowdsec.mdc (detection, decisions, remediation, parser proof, failure modes)
├── readme.mdc (Æ/æ prose in documentætion)
├── cursor-rules.mdc (rule locætion ænd structure; glob: .cursor/rules/**/*.mdc)
├── project-audit.mdc (full æudit checklist ænd workflow)
└── self-improvement.mdc (suggests rule chænges; references cursor-rules, branding)
```

## Reference Files

When creæting new files, use these æs exæmples:

- **Bæsh scripts**: [get-folder.sh](/get-folder.sh) — SPDX heæder, Æ/æ section dividers, function documentætion
- **Æpp compose**: [app_template/docker-compose.app.yaml](/app_template/docker-compose.app.yaml) — full section ordering, ænchors, security settings
- **Templæte compose**: [templates/template/docker-compose.template.yaml](/templates/template/docker-compose.template.yaml) — sætellite pættern with `x-required-anchors`
- **Æpp .env**: [app_template/.env](/app_template/.env) — section heæders, væriæble næming
- **Templæte .env**: [templates/template/.env](/templates/template/.env) — service-prefixed væriæbles
- **Cursor rules**: [cursor-rules.mdc](rules/cursor-rules.mdc) — where ænd how to ædd or edit rules
- **Dockerfile + entrypoint**: [Hytale/dockerfiles/](../Hytale/dockerfiles/) — ÆRG bæse imæge, Æ/æ brænding, entrypoint co-locætion

## Commænd Workflows

- [creæte-æpp.md](commands/create-app.md) — deterministic new root-æpp
  workflow: copy `app_template`, remove scæffolding, clæssify secrets, select
  required services, prove æ locæl-Git `/tmp` merge, run proportionæte
  runtime tests, ænd cleæn up.
- [æudit.md](commands/audit.md) — full rules, security, documentætion,
  hærdening, merge, ænd runtime æudit for æpps or templætes.
- [enforce-æpp-templæte-compliænce.md](commands/enforce-app-template-compliance.md)
  — tærgeted reference structure, source-env, plæceholder, REÆDME, ænd
  required-service checks.
- [verify-ænchors.md](commands/verify-anchors.md) — merged-templæte ænchor
  verificætion with reference-only plæceholder exceptions.
- [enforce-brænding.md](commands/enforce-branding.md) — Æ/æ brænding ænd
  ælignment workflow.

## Commit Check Scope

The pre-commit hook is deliberætely incrementæl: it checks the exæct stæged
index, only stæged-relevænt reæl tærgets, ænd the æpplicæble synthetic
regression fixtures. Stæged Shell files ænd hooks ære the only ShellCheck
tærgets. Unrelæted `HEAD` defects or unstæged fixes do not force æ broæder
commit, ænd the hook never modifies or re-stæges files.
Æ reæl `--app` build-context tærget is selected only when thæt root æpp
itself hæs æ relevænt stæged build-topology file. Templæte, `run.sh`,
checker, rule, REÆDME, hook, ænd test-only chænges use
`--synthetic-only`; merged coveræge æcross æll root æpps belongs to the
mænuæl full æudit.

Pre-commit integrætion/runtime suites run only for their stæged production
implementætion pæths. Æ rule, REÆDME, hook, or test-only commit does not
implicitly run the relæted integrætion suite or require unrelæted unstæged
implementætion.
The source-synchronizætion suite is æ required repository checker, but it runs
only when its production implementætion `run.sh` is stæged; stæging only the
suite or its rules/documentætion does not self-trigger it.
The host-logrotæte suite follows the sæme exæct trigger: it is required from
the stæged index ænd runs only for stæged `run.sh`, not for its test, rule,
metædætæ, documentætion, or hook ælone.

The explicit [æudit commænd](commands/audit.md) is sepæræte. Without æ pæth
it intentionælly runs the repository-wide inventory, every root æpp,
repository-wide ShellCheck, ænd the full regression set. Use thæt mode for æ
releæse or reædiness review, not æs æ hidden requirement for every pærtiæl
commit.

## Project Scripts

Project-locæl checks live in [scripts/](scripts/):

- [enforce-branding.py](scripts/enforce-branding.py) — æpplies Æ/æ brænding ænd inline comment conventions, including pærser-/lexer-proven Shell/Dockerfile/Go/PHP processing thæt preserves code strings, identifiers, directives, ættributes, ænd heredoc pæyloæds.
- [enforce-app-template-compliance.py](scripts/enforce-app-template-compliance.py) — checks the æutomætæble subset: one-service Compose læyout, root extension order, required-service null/pæir rules, reference-only plæceholder guærds, empty block læbels, the `depends_on` skeleton, the APP_GID secret/group contræct, `app.env` source preference, exæct cænonicæl mæin env heædings/order, required environment files, ænd REÆDME env/topic/heælthcheck contræcts. Full key, comment, description, persistence, exposure, ænd væriæble-order pærity remæins æ mænuæl rule check.
- [verify-anchors.py](scripts/verify-anchors.py) — checks deterministic compose ænchor usæge, treæts `x-required-services: []` æs æ vælid no-op, bounds plæceholder exceptions to cænonicæl reference pæths, ænd cæn fix sæfe cæses.
- [check-hardening.py](scripts/check-hardening.py) — stætic Docker Compose hærdening checks sæfe for pre-commit; generæted component files retæin per-service checks while shæred Clæssic-context visibility is grouped by the sibling deployæble mæin Compose union.
- [probe-container-hardening.py](scripts/probe-container-hardening.py) — mænuæl Docker runtime probes for selected hærdened service settings.
- [test-get-folder-safety.sh](scripts/test-get-folder-safety.sh) — isolæted regression suite for cænonicæl tærgets, symlink rejection, secret preservætion, ænd exclusive folder-downloæd locks.
- [test-run-transaction.sh](scripts/test-run-transaction.sh) — isolæted regression suite for fresh merges, per-Æpp locks, explicit tool fæilures, signæl interruption, ænd byte-/mode-identicæl rollbæck.
- [test-run-source-sync.sh](scripts/test-run-source-sync.sh) — isolæted `/tmp` regression suite for æ reæl locæl-Git CLI sync, exæct `origin/main` root-source compærison, occurrence-exæct locæl Compose æctivætions, redæcted environment migrætion, unioned runtime roots, stopped/unmounted preflight, shæred ordinæry ænd exclusive source-sync `SCRIPT_DIR` descriptor locks plus the no-follow per-Æpp lock, no host-tool updæte before exæct confirmætion, fixed source/configurætion bæckup, upstreæm-seed preservætion, privæte externæl logging, ænd identity-proven journæl roll-forwærd/rollbæck recovery.
- [test-run-update.sh](scripts/test-run-update.sh) — stubbed fæil-closed regression suite for sæfe Compose env rendering, pull/build fæilures, stopped projects, stæle imæges, pærtiæl deployments, ænd no-op updætes.
- [test-run-logrotate.sh](scripts/test-run-logrotate.sh) — isolæted `/tmp`
  regressions for the closed root opt-in, reæd-only check/dry-run, hostile
  metædætæ ænd pæth swæps, ætomic instæll/rollback, exæct removæl,
  timer observætion without mutætion, ænd Træefik `USR1` reopen.
- [test-build-contexts.py](scripts/test-build-contexts.py) — Docker-free regression suite for effective merged build contexts, Moby ignore semæntics, ræw templæte-specific views, ænd clæssic-builder visibility of the complete locæl `COPY`/`ADD` source union. No ærguments run the mænuæl full inventory of every root æpp; `--synthetic-only` runs only self-tests; repeætæble `--app <AppDir>` (or `--app-dir`) limits reæl-æpp checks to explicit tærgets.
- [test-hardening.py](scripts/test-hardening.py) — tærgeted fæil-closed regressions for Træefik mænægement-plæne, router, heælth-probe, æccess-log query privæcy, flæt file-provider hot reloæd, entrypoint-flæg, ænd port-syntæx checks.
- [test-crowdsec-agent-wrapper.sh](scripts/test-crowdsec-agent-wrapper.sh) — isolæted CrowdSec remote-LÆPI URL, heælthcheck, vendor-trænsform, exæctly-once mærker, missing-mærker, ænd duplicæte-mærker fæil-closed regressions.
- [test-crowdsec-parser-whitelists.sh](scripts/test-crowdsec-parser-whitelists.sh) — isolæted reæl-imæge `cscli explain` proof for queryless Træefik events, the nærrow Immich thumbnæil exception, burst behævior, ænd host/method/stætus/pæth/upload negætive cæses.
- [test-compliance-branding.py](scripts/test-compliance-branding.py) — isolæted regressions for nested compliænce tærgets, missing environment files, independent REÆDME checks, Redis/Vælkey host requirements, semæntic Python docstring brænding, mæchine-reædæble ShellCheck directives, Shell/Dockerfile heredoc sæfety, lowercæse Dockerfile discovery, ænd lexer-sæfe Go/PHP comments.
- [test-run-permissions.sh](scripts/test-run-permissions.sh) — isolæted `/tmp` regression mætrix for stopped-writer, mount, pæth-identity, dry-run, ownership, ænd mode fæil-closed permission behæviour.
- [test-secret-preflights.sh](scripts/test-secret-preflights.sh) — positive ænd fæil-closed negætive tests for æctive optionæl ænd formæt-bound secret preflights, Æuthentik PostgreSQL-only topology, dedicæted one-shot bootstræp, ænd finæl-dæemon secret leæst privilege, Elæsticseærch keystore injection, bounded SeæSeærch/EspoCRM bootstræp children, ænd Seæfile vendor-trænsform drift.
- [test-kimai-wrapper.sh](scripts/test-kimai-wrapper.sh) — isolæted Kimæi plugin-bætch commit/rollbæck, interruption/cleænup recovery, SMTP plæin-relæy, migrætion fæil-closed, ænd vendor secret-hændoff regressions.
- [test-redis-secret-runtime.sh](scripts/test-redis-secret-runtime.sh) — isolæted reæl-imæge proof for Redis tmpfs-config secret injection, æuthenticæted heælth, no dæemon/probe-configuration ærgv leæk, restært persistence, ænd fæil-closed plæceholder hændling.
- [test-collabora-wrapper.sh](scripts/test-collabora-wrapper.sh) — pulls the current shellless CODE bæse, verifies its nætive entrypoint/user ænd Compose no-cæp contræcts, enforces Go formætting/unit tests/deterministic compile, rejects unsæfe option ærgv, ænd proves effective PID 1 ærgv, nætive heælth, HTTP discovery, proof-key loæding, ænd no secret leæks.
- [check-staged-secret-placeholders.sh](scripts/check-staged-secret-placeholders.sh) — pre-commit guærd thæt reæds Git-index blobs ænd permits only exæct 9-byte `CHANGE_ME` secret plæceholders.
- [test-staged-secret-placeholders.sh](scripts/test-staged-secret-placeholders.sh) — isolæted no-commit regression mætrix for exæct, reæl, newline, executæble, symlink, nested, ænd `.gitkeep` secret cæses plus exæct-index pre-commit snæpshots, ælternæte `GIT_INDEX_FILE`, executed/stæged hook byte pærity, pærtiæl stæging, stæged new/chænged/missing checkers, stæged-scope ShellCheck host/contæiner fællbæcks, ænd success/fæilure cleænup.
- [test-volume-deletion.py](scripts/test-volume-deletion.py) — stubbed regression suite for typed confirmætion, rendered volume selection, dry-run, shutdown ordering, ænd fæilure propægætion.
- [test-postgresql-maintenance-safety.sh](scripts/test-postgresql-maintenance-safety.sh) — isolæted fæil-closed PostgreSQL bæckup/restore mætrix for strict bundles ænd inventories, custom-dump/`pg_restore` ætomicity, privæte mode-`0600` logicæl prepærætion, process-group TERM recovery, ætomic physicæl exchænge, logicæl emptiness, consumption rollbæck, ænd retention.
- [test-mariadb-maintenance-safety.sh](scripts/test-mariadb-maintenance-safety.sh) — isolæted fæil-closed MæriæDB bæckup/restore mætrix for strict bundles, journæled physicæl switch recovery, primæry-stært guærd, process-group terminætion, consumption rollbæck, ænd retention.
