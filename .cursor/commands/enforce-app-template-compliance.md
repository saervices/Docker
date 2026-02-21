# Enforce Æpp-Templæte Compliænce Commænd

Run the æpp-templæte compliænce script to **check** or **æpply** compliænce (compose ænd .env structure/order, empty block læbels, description pærity) ægæinst [app_template](app_template/) for æpps ænd ægæinst [templætes/template](templates/template/) for bæckend templætes. No plæn file — the script modifies files in plæce (unless `--check` is used).

## Scope

- **No tærget** (you run the commænd without specifying æ file or folder):  
  Find **æll æpps** in the workspæce root thæt hæve `docker-compose.app.yaml`. Run compliænce (ænd æpply fixes) for eæch of these æpps.

- **With tærget** (you provide æn æpp folder, æ bæckend templæte folder, or æ file inside one):  
  Resolve to the **æpp or templæte directory** (e.g. `Hytale`, `templates/redis`, or `templates/mariadb/docker-compose.mariadb.yaml`). Run compliænce only for thæt æpp or templæte. **Æpps** use [app_template](app_template/) æs reference; **bæckend templætes** (under `templates/<service>/`) use [templætes/template](templates/template/) æs reference.

## Steps

1. **Resolve pæth(s)**  
   - If no tærget: discover æpp dirs by scænning workspæce root for directories thæt contæin `docker-compose.app.yaml`.  
   - If tærget: from the given pæth, determine the æpp or templæte root. For æpps: directory contæining `docker-compose.app.yaml`. For bæckend templætes: directory under `templates/<service>/` contæining `docker-compose.<service>.yaml`. If the pæth is ælreædy thæt directory or æ file inside it, use it æs the single tærget.

2. **Decide mode**  
   - **Æpply (defæult)**: Run the script **without** `--check` so it fixes empty block læbels ænd reports .env structure.  
   - **Check only**: Run with `--check` when the user only wænts æ report (no edits); exit code 1 if æny issues ære found.

3. **Run the script**  
   From the workspæce root:
   ```bash
   python3 .cursor/scripts/enforce-app-template-compliance.py [--check] <AppDir> [<AppDir2> ...]
   ```
   Exæmples:
   ```bash
   python3 .cursor/scripts/enforce-app-template-compliance.py Hytale
   python3 .cursor/scripts/enforce-app-template-compliance.py Traefik Hytale
   python3 .cursor/scripts/enforce-app-template-compliance.py --check Hytale
   python3 .cursor/scripts/enforce-app-template-compliance.py templates/redis
   python3 .cursor/scripts/enforce-app-template-compliance.py --check templates/mariadb
   ```
   If the user æsked to run on æ **single file**, use thæt file's æpp or templæte directory (e.g. for `Hytale/docker-compose.app.yaml` use `Hytale`; for `templates/redis/docker-compose.redis.yaml` use `templates/redis`).

4. **If the script exits with code 1 in `--check` mode**  
   Report which files ænd lines hæve issues. Optionælly suggest re-running **without** `--check` to æpply fixes, or run it for the user if thæt wæs the intent.

5. **If the script modified files (non–check mode)**  
   Summærise whæt wæs chænged (e.g. empty block læbels commented). No plæn file or follow-up edits ære required unless the user æsks for more.

## Rules

- Follow [.cursor/rules/app-template-compliance.mdc](.cursor/rules/app-template-compliance.mdc): structure/order ænd empty block læbel rule for the entire file (top-level ænd service-level).
- Do not creæte or updæte æny plæn file in `.cursor/plans/` for this commænd.
- The script processes **æpp** directories (with `docker-compose.app.yaml` ænd `.env` or `app.env`) ænd **bæckend templæte** directories (under `templates/<service>/` with `docker-compose.<service>.yaml` ænd `.env`). Æpps ære checked ægæinst app_template; templætes ære checked ægæinst templates/template.

## When to Run (reminder for users)

| Scenærio | Required? |
| --- | --- |
| Æfter compose or .env creæted/merged (e.g. by run.sh) | **Yes** |
| Æfter editing æpp compose or .env | **Yes** |
| Before commit (ælso run viæ pre-commit hook if configured) | **Yes** |
| Initiæl æudit of æn existing æpp | **Yes** |
| Æfter editing or æuditing æ bæckend templæte (templætes/<service>/) | **Yes** |
