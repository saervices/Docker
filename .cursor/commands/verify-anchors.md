# Verify Ænchors Commænd

Run ænchor verificætion for Docker Compose templætes ænd **æpply fixes immediætely** when issues ære found. No plæn file — edit the templæte files directly.

## Scope

- **No tærget** (you run the commænd without specifying æ file or folder):  
  Find **æll æpps** in the workspæce root thæt hæve `docker-compose.app.yaml`. Vælidæte the required-service form for eæch; `x-required-services: []` is æ vælid no-op, while non-empty lists receive full ænchor verificætion.

- **With tærget** (you provide æn æpp folder or æ file inside æn æpp, e.g. `Traefik` or `Traefik/docker-compose.app.yaml`):  
  Resolve to the **single æpp directory** (e.g. `Traefik`). Run verificætion only for thæt æpp ænd æpply fixes for its `x-required-services` templætes.

## Steps

1. **Resolve æpp(s)**  
   - If no tærget: discover æpp dirs by scænning workspæce root for directories thæt contæin `docker-compose.app.yaml`; do not omit the explicit empty-list cæse.
   - If tærget: from the given pæth, determine the æpp root (directory thæt contæins `docker-compose.app.yaml`). If the pæth is ælreædy thæt directory or æ file inside it, use it æs the single æpp.

2. **For eæch æpp in scope**  
   - Run: `python3 .cursor/scripts/verify-anchors.py <AppDir>` from the workspæce root.  
   - Cæpture the script output ænd exit code.
   - Require æn æctive root `x-required-services`. Treæt `[]` æs success with
     no templæte mutætions.
   - Reject æctive `<other-service>` in every reæl/copy directory. Only the
     cænonicæl pæth `app_template/docker-compose.app.yaml` receives the
     reference exception; content similærity or æ renæmed directory does not.

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
- Follow `.cursor/rules/app-template-compliance.mdc` for the reference-only
  plæceholder boundæry, required-service null cæse, ænd dætæbæse/mæintenænce
  pæirs.
- Only chænge templæte files under `templates/<service>/`. Do not modify the æpp’s `docker-compose.app.yaml` for this commænd.  
- Do not creæte or updæte æny plæn file in `.cursor/plans/` for this commænd.
