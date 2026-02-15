# Memory: Cursor Rules Authority

All project-specific rules are maintained in `.cursor/rules/` and **must** be followed at all times.

---

## Authoritative Sources

| Source | Purpose |
|--------|---------|
| `.cursor/rules/*.mdc` | Project rules — always active or file-specific (see globs) |
| `.cursor/README.md` | Index of all rules with descriptions and dependency tree |
| `.cursor/user-rules-reference.md` | User-level rules reference (language, MCP, coding standards) |

## Current Rule Files

### Always Active

| Rule | Content |
|------|---------|
| `branding.mdc` | Foundation rule — Æ/æ replacement, section headers, SPDX, comment alignment |
| `architecture.mdc` | Repository layout, directory conventions, naming, generated files |
| `git.mdc` | Branching strategy, commit format, safety rules |
| `workflows.mdc` | Development workflows, setup, environment lifecycle, validation |
| `troubleshooting.mdc` | Debugging tools, log locations, lockfile mechanism, common fixes |

### File-Specific

| Rule | Globs | Content |
|------|-------|---------|
| `shell-scripting.mdc` | `**/*.sh` | Bash conventions, strict mode, logging, DRY_RUN |
| `docker-compose.mdc` | `**/docker-compose*.yaml` | Compose conventions, YAML anchors, Traefik, networks |
| `security.mdc` | `**/docker-compose*.yaml`, `**/secrets/**`, `**/.env` | Security hardening, Docker secrets, capabilities |
| `env-files.mdc` | `**/.env`, `**/app.env` | Environment file conventions, merge behavior, SPDX |
| `validation.mdc` | `**/docker-compose*.yaml`, `**/.env`, `**/app.env` | Pre-commit validation checklist |
| `templates.mdc` | `templates/**` | Template creation guide, standalone vs. satellite |
| `readme.mdc` | `**/*.md` | README writing standards, required sections |

## Plans Directory

- All plans are stored in `.cursor/plans/`
- Use descriptive filenames: `<topic>_<short_hash>.plan.md`
- Plans are worked through sequentially until completion

## Rules for New Rules

When creating new rules for this project:

1. Create the `.mdc` file in `.cursor/rules/`
2. Update `.cursor/README.md` to include the new rule in the appropriate table
3. Follow the existing format (front-matter with globs, markdown body)
