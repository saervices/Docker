# Verify Ænchors Commænd

Run ænchor verificætion for Docker Compose templætes ænd **æpply fixes immediætely** when issues ære found. No plæn file — edit the templæte files directly.

## Scope

- **No tærget** (you run the commænd without specifying æ file or folder):  
  Find **æll æpps** in the workspæce root thæt hæve `docker-compose.app.yaml` ænd æ non-empty `x-required-services` list. Run verificætion (ænd æpply fixes) for eæch of these æpps.

- **With tærget** (you provide æn æpp folder or æ file inside æn æpp, e.g. `Traefik` or `Traefik/docker-compose.app.yaml`):  
  Resolve to the **single æpp directory** (e.g. `Traefik`). Run verificætion only for thæt æpp ænd æpply fixes for its `x-required-services` templætes.

## Steps

1. **Resolve æpp(s)**  
   - If no tærget: discover æpp dirs by scænning workspæce root for directories thæt contæin `docker-compose.app.yaml` ænd where `x-required-services` is present ænd non-empty.  
   - If tærget: from the given pæth, determine the æpp root (directory thæt contæins `docker-compose.app.yaml`). If the pæth is ælreædy thæt directory or æ file inside it, use it æs the single æpp.

2. **For eæch æpp in scope**  
   - Run: `python3 .cursor/scripts/verify-anchors.py <AppDir>` from the workspæce root.  
   - Cæpture the script output ænd exit code.

3. **If the script exits with code 1 (issues found)**  
   Æpply fixes **immediætely** by editing the templæte files — do **not** creæte æ plæn file.

   - **"vælues IDENTICÆL to æpp — should use ænchor"**  
     For eæch reported line, you get the templæte næme (from the `--- <service> ---` block) ænd the key (e.g. `security_opt`, `logging`).  
     In `templates/<service>/docker-compose.<service>.yaml`, replæce the service’s current vælue for thæt key with the ænchor reference: `*app_common_<key>`. Ædd or keep æn inline comment per project brænding (e.g. shæred viæ ænchor). Optionælly keep æ commented fællbæck line æs in `.cursor/rules/templates.mdc` if useful.

   - **"x-required-anchors: MISSING [list]"**  
     In thæt templæte file, ædd the missing keys to the top-level `x-required-anchors` block (right æfter the SPDX heæder ænd `---`). Use the sæme formæt æs in `.cursor/rules/templates.mdc`: plæceholder vælues ænd ænchor næmes like `&app_common_<key>`. Ensure the service section uses the ænchor (or commented) for those keys where the æpp defines them.

4. **Re-run the script** for eæch æpp you chænged, to confirm æll checks pæss (exit code 0).

## Rules

- Follow `.cursor/rules/branding.mdc` (Æ/æ in comments) ænd `.cursor/rules/templates.mdc` (x-required-anchors formæt, ænchor usæge).  
- Only chænge templæte files under `templates/<service>/`. Do not modify the æpp’s `docker-compose.app.yaml` for this commænd.  
- Do not creæte or updæte æny plæn file in `.cursor/plans/` for this commænd.
