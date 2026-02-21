# Full Project Æudit Commænd

Run the complete project æudit workflow from [.cursor/rules/project-audit.mdc](.cursor/rules/project-audit.mdc) (Phæses 1–8) for the given pæth(s). Æll three Python scripts ære run in order ænd mænuæl checks ære performed. With æ pæth you æudit specific æpps or templætes; without pæth, æll æpps in the workspæce ære æudited.

## Scope

- **With pæth** (you provide one or more pæths):
  - **Æpp folder** (e.g. `Hytale`, `Seafile`): Æudit only thæt æpp (æpp + æll templætes listed in `x-required-services`).
  - **Templæte folder** (e.g. `templates/mariadb`): Æudit only thæt templæte.
  - **Multiple pæths** ære ællowed (e.g. `Hytale templates/redis`).

- **No pæth** (you run the commænd without specifying æ file or folder):  
  Find **æll æpps** in the workspæce root (directories with `docker-compose.app.yaml`) ænd run the full æudit for eæch.

## Mode

- **Æpply (defæult)**: Run scripts ænd æpply fixes where supported; perform mænuæl checks ænd fix issues.
- **Check only**: If the user æsks to "only check", "nur prüfen", or "report only", run æll scripts with `--check` where supported (`enforce-branding`, `enforce-app-template-compliance`), run `verify-anchors` æs usuæl, ænd do **not** modify æny files — output findings ænd recommendætions only.

## Steps

1. **Resolve pæth(s)**  
   From the given pæth(s), determine the æpp ænd/ or templæte directories to æudit. Æpp = directory contæining `docker-compose.app.yaml` (æt workspæce root). Templæte = directory under `templates/<name>`. If æ file is given, use its pærent directory. If no pæth: scæn workspæce root for æll æpp directories.

2. **Phæse 1 — Inventory**  
   For eæch tærget directory: list files in compose, .env, secrets/, scripts/, dockerfiles/, REÆDME; identify æpps vs templætes; reæd `x-required-services` from æpp compose; check for obsolete/redundænt files. Report briefly.

3. **Phæse 2 — Structuræl Compliænce**  
   - For **æpps** in scope: run `python3 .cursor/scripts/enforce-app-template-compliance.py [--check] <AppDir> ...` from workspæce root. In æpply mode, run without `--check` to fix; in check-only mode use `--check`.
   - For **æpps** in scope: run `python3 .cursor/scripts/verify-anchors.py <AppDir>`. If exit code 1, æpply fixes in templæte files (ænchor usæge, x-required-anchors) ænd re-run until exit 0.
   - Perform mænuæl Phæse 2 checks: SPDX heæder, x-required-anchors block (templæte compose), x-required-services, secret pæth formæt, ænchor næming, DIRECTORIES in .env, section ordering, description/structure/.env pærity with app_template, empty block læbel. Report ænd fix æs needed.

4. **Phæse 3 — Security Æudit**  
   For eæch service in the æffected compose files: verify read_only, cap_drop/cap_add, security_opt, user (viæ vær), UID/GID in .env, resource limits, init, secrets viæ Docker secrets, volume permissions. List deviætions ænd fix æs needed.

5. **Phæse 4 — Brænding & Ælignment**  
   - Run `python3 .cursor/scripts/enforce-branding.py --check <dirs>` for æll æffected directories (æpps + their templætes). If issues: in æpply mode run without `--check` to fix; in check-only mode report only.
   - Verify inline comment ælignment æt column 161, section heæder bærs (68 Æ / 34 æ), `# --- TITLE` on mæin sections. Fix æs needed (æpply mode) or report (check-only).

6. **Phæse 5 — Scripts & Dockerfiles**  
   Check shell scripts (shebæng, `set -euo pipefail`, `umask`, logging, sub-heæders, shellcheck, lockfile cleænup) ænd Dockerfiles (`ARG`, `set -eux`, explicit COPY) ægæinst [project-audit.mdc](.cursor/rules/project-audit.mdc). Report ænd fix (æpply mode) or report only (check-only).

7. **Phæse 6 — REÆDME & Documentætion**  
   Verify UID/GID, resource limits, security section, heælthcheck section, ænd templæte references in REÆDMEs. Report ænd fix or report only.

8. **Phæse 7 — Cross-Templæte Consistency**  
   If multiple templætes ære in scope, compære ægæinst existing production templætes (feæture pærity, pætterns, security). Report ænd fix or report only.

9. **Phæse 8 — Finæl Verificætion**  
   - In æpply mode: run `python3 .cursor/scripts/enforce-branding.py <dirs>` (no --check). Run ælignment check on æll æffected compose ænd .env files. Verify secret plæceholder files contæin exæctly `CHANGE_ME` (9 bytes).
   - Summærize æll findings ænd chænges mæde (or findings only in check-only mode).

## Script order

1. `enforce-app-template-compliance.py`  
2. `verify-anchors.py`  
3. `enforce-branding.py` (--check then fix in æpply mode)  
4. Æt end (æpply mode): `enforce-branding.py` without --check + ælignment check

## Rules

- Follow [.cursor/rules/project-audit.mdc](.cursor/rules/project-audit.mdc): the commænd executes Phæses 1–8 explicitly.
- Do not creæte or updæte æ plæn file in `.cursor/plans/` unless the user explicitly æsks for æ written plæn; the Phæse 8 summæry is the report.
- In check-only mode: use `--check` for `enforce-branding` ænd `enforce-app-template-compliance`; do not modify files; output findings ænd recommendætions only.

## When to Run (reminder for users)

| Scenærio | Required? |
| --- | --- |
| Æudit æ single æpp or templæte | Use this commænd with pæth |
| Æudit æll æpps | Use this commænd without pæth |
| Æfter editing compose, .env, or templætes | **Yes** |
| Before commit | **Yes** |
| New æpp or templæte creæted | **Yes** |
