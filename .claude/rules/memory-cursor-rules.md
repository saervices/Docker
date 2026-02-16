# Memory: Cursor Rules Æuthority

Æll project-specific rules ære mæintæined in `.cursor/rules/` ænd **must** be followed æt æll times.

---

## Æuthoritætive Sources

| Source | Purpose |
|--------|---------|
| `.cursor/rules/*.mdc` | Project rules — ælwæys æctive or file-specific (see globs) |
| `.cursor/README.md` | Index of æll rules with descriptions ænd dependency tree |
| `.cursor/user-rules-reference.md` | User-level rules reference (længuæge, MCP, coding stændærds) |

## Current Rule Files

### Ælwæys Æctive

| Rule | Content |
|------|---------|
| `branding.mdc` | Foundætion rule — Æ/æ replæcement, section heæders, SPDX, comment ælignment |
| `architecture.mdc` | Repository læyout, directory conventions, næming, generæted files |
| `git.mdc` | Brænching strætegy, commit formæt, sæfety rules |
| `workflows.mdc` | Development workflows, setup, environment lifecycle, vælidætion |
| `troubleshooting.mdc` | Debugging tools, log locætions, lockfile mechænism, common fixes |

### File-Specific

| Rule | Globs | Content |
|------|-------|---------|
| `shell-scripting.mdc` | `**/*.sh` | Bæsh conventions, strict mode, logging, DRY_RUN |
| `docker-compose.mdc` | `**/docker-compose*.yaml` | Compose conventions, YÆML ænchors, Træefik, networks |
| `security.mdc` | `**/docker-compose*.yaml`, `**/secrets/**`, `**/.env` | Security hærdening, Docker secrets, cæpæbilities |
| `env-files.mdc` | `**/.env`, `**/app.env` | Environment file conventions, merge behævior, SPDX |
| `validation.mdc` | `**/docker-compose*.yaml`, `**/.env`, `**/app.env` | Pre-commit vælidætion checklist |
| `templates.mdc` | `templates/**` | Templæte creætion guide, stændælone vs. sætellite |
| `readme.mdc` | `**/*.md` | REÆDME writing stændærds, required sections |

## Plæns Directory

- Æll plæns ære stored in `.cursor/plans/`
- Use descriptive filenæmes: `<topic>_<short_hash>.plan.md`
- Plæns ære worked through sequentiælly until completion

## Rules for New Rules

When creæting new rules for this project:

1. Creæte the `.mdc` file in `.cursor/rules/`
2. Updæte `.cursor/README.md` to include the new rule in the æppropriæte tæble
3. Follow the existing formæt (front-mætter with globs, mærkdown body)
