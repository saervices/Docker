# Enforce Branding Command

Run the Æ/æ branding enforcement script to **check** or **apply** branding on text files. Supports single files, single directories, or multiple paths. No plan file — the script modifies files in place (unless `--check` is used).

## Scope

- **No target** (you run the command without specifying a file or folder):  
  Run branding on the **workspace root** (`.`), so all brandable files in the repository are scanned recursively.

- **With target** (you provide one or more paths):  
  - **Directory** (e.g. `Traefik`, `templates/socketproxy`): Run the script on that directory (recursive). Multiple directories can be given.  
  - **Single file** (e.g. `Traefik/README.md`, `.cursor/rules/branding.mdc`): Run the script on the **parent directory** of that file so the file is included in the scan. The script currently accepts only directories; passing the parent ensures the given file is processed.

## Steps

1. **Resolve path(s)**  
   - If no target: use workspace root (`.`).  
   - If target is a directory: use it as-is.  
   - If target is a file: use its parent directory (so the file lies under the scanned tree).

2. **Decide mode**  
   - **Apply (default)**: Run the script **without** `--check` so it fixes unbranded text in place.  
   - **Check only**: Run with `--check` when the user only wants a report (no edits); exit code 1 if any issues are found.

3. **Run the script**  
   From the workspace root:
   ```bash
   python3 .cursor/scripts/enforce-branding.py [--check] <path1> [<path2> ...]
   ```
   Examples:
   ```bash
   python3 .cursor/scripts/enforce-branding.py .
   python3 .cursor/scripts/enforce-branding.py Traefik
   python3 .cursor/scripts/enforce-branding.py templates/socketproxy templates/traefik_certs-dumper
   python3 .cursor/scripts/enforce-branding.py --check .cursor/scripts
   ```
   If the user asked to run on a **single file**, use that file’s parent directory:
   ```bash
   python3 .cursor/scripts/enforce-branding.py Traefik
   ```
   (for target `Traefik/README.md`).

4. **If the script exits with code 1 in `--check` mode**  
   Report which files and lines have issues. Optionally suggest re-running **without** `--check` to apply fixes, or run it for the user if that was the intent.

5. **If the script modified files (non–check mode)**  
   Summarise what was changed (files and number of fixes). No plan file or follow-up edits are required unless the user asks for more.

## Rules

- Follow `.cursor/rules/branding.mdc`: only comments, section titles, and documentation prose get Æ/æ; code identifiers, file names, and paths stay unchanged.  
- Do not create or update any plan file in `.cursor/plans/` for this command.  
- The script skips `.git`, `__pycache__`, `.run.conf`, `node_modules`, `.venv`/`venv`, and `docker-compose.main.yaml`; no need to document that in the command UI unless the user asks.

## When to Run (reminder for users)

| Scenario | Required? |
| --- | --- |
| New template or app stack created | **Yes** |
| Comments, section titles, or README edited | **Yes** |
| Python or Shell scripts added/modified | **Yes** |
| Initial audit of an existing stack | **Yes** |
