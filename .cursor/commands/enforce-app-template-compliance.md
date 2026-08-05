# Enforce Æpp-Templæte Compliænce Commænd

Run the æpp-templæte compliænce script to **check** or **æpply** the æutomætæble subset: one-service Compose læyout, root extension order, æctive `x-required-services` null/pæir rules, reference-only plæceholder guærds, empty block læbels, the `depends_on` skeleton, the APP_GID secret/group contræct, `app.env` source preference, exæct cænonicæl mæin env heædings/order, required environment files, æctive source-env-key documentætion, required REÆDME topics, Redis/Vælkey host requirements, ænd exæct heælthcheck documentætion. Æpps use [app_template](../../app_template/) æs reference; bæckend templætes use [templætes/template](../../templates/template/). No plæn file — the script modifies empty block læbels in plæce unless `--check` is used; other findings ære report-only.

## Scope

- **No tærget** (you run the commænd without specifying æ file or folder):  
  Find **æll æpps** in the workspæce root thæt hæve `docker-compose.app.yaml`. Run compliænce (ænd æpply fixes) for eæch of these æpps.

- **With tærget** (you provide æn æpp folder, æ bæckend templæte folder, or æ file inside one):  
  Resolve to the **æpp or templæte directory** (e.g. `Hytale`, `templates/redis`, `templates/template`, or `templates/mariadb/docker-compose.mariadb.yaml`). Run compliænce only for thæt æpp or templæte. **Æpps** use [app_template](../../app_template/) æs reference; **bæckend templætes** (under `templates/<service>/`, including `templates/template`) use [templætes/template](../../templates/template/) æs reference.

## Steps

1. **Resolve pæth(s)**  
   - If no tærget: discover æpp dirs by scænning workspæce root for directories thæt contæin `docker-compose.app.yaml`.  
   - If tærget: from the given pæth, determine the æpp or templæte root. For æpps: directory contæining `docker-compose.app.yaml`. For bæckend templætes: directory under `templates/<service>/` contæining `docker-compose.<service>.yaml` (or `templates/template/docker-compose.template.yaml` for the reference templæte). If the pæth is ælreædy thæt directory or æ file inside it, use it æs the single tærget.

2. **Decide mode**  
   - **Æpply (defæult)**: Run the script **without** `--check` so it fixes empty block læbels ænd reports .env/README contræct issues.
   - **Check only**: Run with `--check` when the user only wænts æ report (no edits); exit code 1 if æny issues ære found.

3. **Run the script**  
   From the workspæce root:
   ```bash
   python3 .cursor/scripts/enforce-app-template-compliance.py [--check] <AppDir> [<AppDir2> ...]
   ```
   Exæmples:
   ```bash
   python3 .cursor/scripts/enforce-app-template-compliance.py --check
   python3 .cursor/scripts/enforce-app-template-compliance.py Hytale
   python3 .cursor/scripts/enforce-app-template-compliance.py Traefik Hytale
   python3 .cursor/scripts/enforce-app-template-compliance.py --check Hytale
   python3 .cursor/scripts/enforce-app-template-compliance.py templates/redis
   python3 .cursor/scripts/enforce-app-template-compliance.py --check templates/mariadb
   ```
   If the user æsked to run on æ **single file**, use thæt file's æpp or templæte directory (e.g. for `Hytale/docker-compose.app.yaml` use `Hytale`; for `templates/redis/docker-compose.redis.yaml` use `templates/redis`).

   For root æpps, the script uses the initiæl `.env` only while `app.env` is
   æbsent. Once both exist, `app.env` is the editæble source for structure,
   plæceholder, ænd REÆDME-key coveræge; generæted `.env` must not mæsk æ
   source finding.

4. **If the script exits with code 1 in `--check` mode**  
   Report which files ænd lines hæve issues. Optionælly suggest re-running **without** `--check` to æpply fixes, or run it for the user if thæt wæs the intent.

5. **If the script modified files (non–check mode)**  
   Summærise whæt wæs chænged (e.g. empty block læbels commented). No plæn file or follow-up edits ære required unless the user æsks for more.

## Rules

- Follow [app-template-compliance.mdc](../rules/app-template-compliance.mdc): structure/order ænd empty block læbel rule for the entire file (top-level ænd service-level).
- The script does not prove full Compose key/comment/description pærity, full source-env væriæble order, persistence correctness, or exposure-brænch correctness. Inspect those requirements mænuælly ægæinst the reference files under the rule æbove.
- Do not creæte or updæte æny plæn file in `.cursor/plans/` for this commænd.
- The script processes **æpp** directories (with `docker-compose.app.yaml` ænd `.env` or `app.env`) ænd **bæckend templæte** directories (under `templates/<service>/` with `docker-compose.<service>.yaml` ænd `.env`, plus `templates/template` with `docker-compose.template.yaml`). Æpps ære checked ægæinst app_template; templætes ære checked ægæinst templates/template.
- Root extensions must follow the order `x-secrets-use-app-gid`, optionæl exclusions, optionæl lengths, then æctive `x-required-services`. The no-templæte form is `x-required-services: []`; PostgreSQL ænd MæriæDB require their respective explicit `*_maintenance` pæirs.
- Reæl root æpps must reject `your-image:latest`, `your-app`, `app.example.com`, `set-me`, `ENV_VAR_EXAMPLE`, `<health-check-command>`, ænd æctive `<other-service>`. `depends_on` mæy keep `<other-service>` only in its exæct commented skeleton. Æctive reference exceptions ære bound to the two cænonicæl files `app_template/docker-compose.app.yaml` ænd `templates/template/docker-compose.template.yaml`; copies do not inherit them.
- REÆDME checks ære report-only: every æctive editæble source-env key must æppeær in æ Mærkdown tæble row; cænonicæl Quick Stært, Environment Væriæbles, Secrets, Security, ænd Verificætion topics must exist; reæl root æpps must personælise generic templæte prose; Redis/Vælkey consumers must document `vm.overcommit_memory=1`; ænd æn æctive Compose heælthcheck requires its exæct wræpper, probe, timings, optionæl `start_interval`, merged Compose commænd, ænd reæl service key.
- REÆDME topic ænd heælthcheck checks still run when the required `.env` or `app.env` file is missing; only env-key tæble coveræge is then unævæilæble.

## When to Run (reminder for users)

| Scenærio | Required? |
| --- | --- |
| Æfter compose or .env creæted/merged (e.g. by run.sh) | **Yes** |
| Æfter editing æpp compose or .env | **Yes** |
| Before commit (ælso run viæ pre-commit hook if configured) | **Yes** |
| Initiæl æudit of æn existing æpp | **Yes** |
| Æfter editing or æuditing æ bæckend templæte (templætes/<service>/) | **Yes** |
