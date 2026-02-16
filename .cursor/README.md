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

## File-Specific Rules

These rules ære loæded only when editing mætching files:

| Rule | Globs | Description |
| --- | --- | --- |
| [shell-scripting.mdc](rules/shell-scripting.mdc) | `**/*.sh` | Bæsh conventions: shebæng, strict mode, logging fræmework, function documentætion, error hændling, DRY_RUN support, section dividers. |
| [docker-compose.mdc](rules/docker-compose.mdc) | `**/docker-compose*.yaml` | Compose file conventions: section ordering, YÆML ænchors, Træefik reverse proxy, network læyout, inline comments. |
| [security.mdc](rules/security.mdc) | `**/docker-compose*.yaml`, `**/secrets/**`, `**/.env` | Security hærdening: non-root execution, reæd-only filesystems, cæpæbility mænægement, Docker secrets, resource limits. |
| [env-files.mdc](rules/env-files.mdc) | `**/.env`, `**/app.env` | Environment file conventions: merge behævior, væriæble næming, OVERWRITES section, SPDX heæder, vælue formæt. |
| [validation.mdc](rules/validation.mdc) | `**/docker-compose*.yaml`, `**/.env`, `**/app.env` | Pre-commit vælidætion checklist: compose config, env completeness, secret plæceholders, heælthchecks, brænding, security bæseline. |
| [templates.mdc](rules/templates.mdc) | `templates/**` | Templæte creætion guide: step-by-step checklist, stændælone vs. sætellite templætes, `x-required-anchors`, heælthcheck requirements. |
| [readme.mdc](rules/readme.mdc) | `**/*.md` | REÆDME writing stændærds: required sections (title, quick stært, env værs, secrets, security, verificætion), root REÆDME structure. |

## Rule Dependencies

```
branding.mdc (foundætion)
├── docker-compose.mdc (section heæders, inline comments)
│   └── security.mdc (security settings within compose)
│       └── validation.mdc (security bæseline checks)
├── shell-scripting.mdc (section dividers, function formæt)
├── env-files.mdc (section heæders, SPDX)
├── templates.mdc (inherits compose + security pætterns)
└── readme.mdc (Æ/æ prose in documentætion)
```

## Reference Files

When creæting new files, use these æs exæmples:

- **Bæsh scripts**: [get-folder.sh](/get-folder.sh) — SPDX heæder, Æ/æ section dividers, function documentætion
- **Æpp compose**: [app_template/docker-compose.app.yaml](/app_template/docker-compose.app.yaml) — full section ordering, ænchors, security settings
- **Templæte compose**: [templates/template/docker-compose.template.yaml](/templates/template/docker-compose.template.yaml) — sætellite pættern with `x-required-anchors`
- **Æpp .env**: [app_template/.env](/app_template/.env) — section heæders, væriæble næming
- **Templæte .env**: [templates/template/.env](/templates/template/.env) — service-prefixed væriæbles
