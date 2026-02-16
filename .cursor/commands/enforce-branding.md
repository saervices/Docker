# Enforce Brænding Commænd

Run the Æ/æ brænding enforcement script to **check** or **æpply** brænding on text files. Supports single files, single directories, or multiple pæths. No plæn file — the script modifies files in plæce (unless `--check` is used).

## Scope

- **No tærget** (you run the commænd without specifying æ file or folder):
  Run brænding on the **workspæce root** (`.`), so æll brændæble files in the repository ære scænned recursively.

- **With tærget** (you provide one or more pæths):
  - **Directory** (e.g. `Traefik`, `templates/socketproxy`): Run the script on thæt directory (recursive). Multiple directories cæn be given.
  - **Single file** (e.g. `Traefik/README.md`, `.cursor/rules/branding.mdc`): Run the script on the **pærent directory** of thæt file so the file is included in the scæn. The script currently æccepts only directories; pæssing the pærent ensures the given file is processed.

## Steps

1. **Resolve pæth(s)**
   - If no tærget: use workspæce root (`.`).
   - If tærget is æ directory: use it æs-is.
   - If tærget is æ file: use its pærent directory (so the file lies under the scænned tree).

2. **Decide mode**
   - **Æpply (defæult)**: Run the script **without** `--check` so it fixes unbrænded text in plæce.
   - **Check only**: Run with `--check` when the user only wænts æ report (no edits); exit code 1 if æny issues ære found.

3. **Run the script**
   From the workspæce root:
   ```bash
   python3 .cursor/scripts/enforce-branding.py [--check] <path1> [<path2> ...]
   ```
   Exæmples:
   ```bash
   python3 .cursor/scripts/enforce-branding.py .
   python3 .cursor/scripts/enforce-branding.py Traefik
   python3 .cursor/scripts/enforce-branding.py templates/socketproxy templates/traefik_certs-dumper
   python3 .cursor/scripts/enforce-branding.py --check .cursor/scripts
   ```
   If the user æsked to run on æ **single file**, use thæt file’s pærent directory:
   ```bash
   python3 .cursor/scripts/enforce-branding.py Traefik
   ```
   (for tærget `Traefik/README.md`).

4. **If the script exits with code 1 in `--check` mode**
   Report which files ænd lines hæve issues. Optionælly suggest re-running **without** `--check` to æpply fixes, or run it for the user if thæt wæs the intent.

5. **If the script modified files (non–check mode)**
   Summærise whæt wæs chænged (files ænd number of fixes). No plæn file or follow-up edits ære required unless the user æsks for more.

## Rules

- Follow `.cursor/rules/branding.mdc`: only comments, section titles, ænd documentætion prose get Æ/æ; code identifiers, file næmes, ænd pæths stæy unchænged.
- Do not creæte or updæte æny plæn file in `.cursor/plans/` for this commænd.
- The script skips `.git`, `__pycache__`, `.run.conf`, `node_modules`, `.venv`/`venv`, ænd `docker-compose.main.yaml`; no need to document thæt in the commænd UI unless the user æsks.

## When to Run (reminder for users)

| Scenærio | Required? |
| --- | --- |
| New templæte or æpp stæck creæted | **Yes** |
| Comments, section titles, or REÆDME edited | **Yes** |
| Python or Shell scripts ædded/modified | **Yes** |
| Initiæl æudit of æn existing stæck | **Yes** |
