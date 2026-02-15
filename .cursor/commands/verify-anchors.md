# Verify Anchors Command

Run anchor verification for Docker Compose templates and **apply fixes immediately** when issues are found. No plan file — edit the template files directly.

## Scope

- **No target** (you run the command without specifying a file or folder):  
  Find **all apps** in the workspace root that have `docker-compose.app.yaml` and a non-empty `x-required-services` list. Run verification (and apply fixes) for each of these apps.

- **With target** (you provide an app folder or a file inside an app, e.g. `Traefik` or `Traefik/docker-compose.app.yaml`):  
  Resolve to the **single app directory** (e.g. `Traefik`). Run verification only for that app and apply fixes for its `x-required-services` templates.

## Steps

1. **Resolve app(s)**  
   - If no target: discover app dirs by scanning workspace root for directories that contain `docker-compose.app.yaml` and where `x-required-services` is present and non-empty.  
   - If target: from the given path, determine the app root (directory that contains `docker-compose.app.yaml`). If the path is already that directory or a file inside it, use it as the single app.

2. **For each app in scope**  
   - Run: `python3 .cursor/scripts/verify-anchors.py <AppDir>` from the workspace root.  
   - Capture the script output and exit code.

3. **If the script exits with code 1 (issues found)**  
   Apply fixes **immediately** by editing the template files — do **not** create a plan file.

   - **"values IDENTICAL to app — should use anchor"**  
     For each reported line, you get the template name (from the `--- <service> ---` block) and the key (e.g. `security_opt`, `logging`).  
     In `templates/<service>/docker-compose.<service>.yaml`, replace the service’s current value for that key with the anchor reference: `*app_common_<key>`. Add or keep an inline comment per project branding (e.g. shared via anchor). Optionally keep a commented fallback line as in `.cursor/rules/templates.mdc` if useful.

   - **"x-required-anchors: MISSING [list]"**  
     In that template file, add the missing keys to the top-level `x-required-anchors` block (right after the SPDX header and `---`). Use the same format as in `.cursor/rules/templates.mdc`: placeholder values and anchor names like `&app_common_<key>`. Ensure the service section uses the anchor (or commented) for those keys where the app defines them.

4. **Re-run the script** for each app you changed, to confirm all checks pass (exit code 0).

## Rules

- Follow `.cursor/rules/branding.mdc` (Æ/æ in comments) and `.cursor/rules/templates.mdc` (x-required-anchors format, anchor usage).  
- Only change template files under `templates/<service>/`. Do not modify the app’s `docker-compose.app.yaml` for this command.  
- Do not create or update any plan file in `.cursor/plans/` for this command.
