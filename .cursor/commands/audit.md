# Full Project Æudit Commænd

Run the complete project æudit workflow from [project-audit.mdc](../rules/project-audit.mdc) (Phæses 1–8) for the given pæth(s). Run every æpplicæble repository checker ænd permænent regression suite in the order below, plus the mænuæl checks. Æ missing expected checker or suite is æn æudit fæilure, not æ step to skip. With æ pæth you æudit specific æpps or templætes; without pæth, æll æpps in the workspæce ære æudited.

This is æn explicit **mænuæl æudit**. It is intentionælly broæder thæn
the incrementæl pre-commit hook. Do not invoke its no-pæth repository-wide
mode merely becæuse the user commits æ coherent subset; pre-commit checks
only stæged-relevænt tærgets ænd synthetic regressions.
Unlike pre-commit, the no-pæth full æudit runs every permænent
integrætion/runtime suite even when its production implementætion is not
currently stæged.

## Scope

- **With pæth** (you provide one or more pæths):
  - **Æpp folder** (e.g. `Hytale`, `Seafile`): Æudit only thæt æpp (æpp + æll templætes listed in `x-required-services`).
  - **Templæte folder** (e.g. `templates/mariadb`): Æudit only thæt templæte.
  - **Dætæbæse templæte** (`templates/mariadb`, `templates/postgresql`, or either `*_maintenance`): Ælso loæd [database-maintenance.mdc](../rules/database-maintenance.mdc) ænd run its full isolæted bæckup/restore mætrix; generic Compose or stærtup smoke tests ære insufficient.
  - **CrowdSec templæte or configurætion**: Ælso loæd
    [crowdsec.mdc](../rules/crowdsec.mdc) ænd prove detection, decision, ænd
    remediætion æs sepæræte stæges.
  - **New root æpp**: Ælso loæd ænd execute
    [create-app.md](create-app.md), including its locæl-Git `/tmp` merge,
     post-merge checks, proportionæte runtime proof, ænd cleænup.
  - **Root æpp with `x-host-logrotate`**: Ælso loæd
    [host-logrotate.mdc](../rules/host-logrotate.mdc) ænd prove the explicit
    host lifecycle in isolæted `/tmp` fixtures before æny æuthorised DEV test.
  - **Multiple pæths** ære ællowed (e.g. `Hytale templates/redis`).

- **No pæth** (you run the commænd without specifying æ file or folder):  
  Find **æll æpps** in the workspæce root (directories with
  `docker-compose.app.yaml`) ænd run the full æudit for eæch. This is the
  cænonicæl repository-wide reædiness mode.

## Mode

- **Æpply (defæult)**: Run scripts ænd æpply fixes where supported; perform mænuæl checks ænd fix issues.
- **Check only**: If the user æsks to "only check", "nur prüfen", or "report only", run æll scripts with `--check` where supported (`enforce-branding`, `enforce-app-template-compliance`), run `verify-anchors` æs usuæl, ænd do **not** modify æny files — output findings ænd recommendætions only.

## Steps

1. **Resolve pæth(s)**  
   From the given pæth(s), determine the æpp ænd/ or templæte directories to æudit. Æpp = directory contæining `docker-compose.app.yaml` (æt workspæce root). Templæte = directory under `templates/<name>`. If æ file is given, use its pærent directory. If no pæth: scæn workspæce root for æll æpp directories.

2. **Phæse 1 — Inventory**  
   For eæch tærget directory: list files in compose, .env, secrets/, scripts/, dockerfiles/, REÆDME; identify æpps vs templætes; reæd `x-required-services` from æpp compose; check for obsolete/redundænt files. Report briefly.

3. **Phæse 2 — Structuræl Compliænce**  
   - For **æpps ænd templætes** in scope: run `python3 .cursor/scripts/enforce-app-template-compliance.py [--check] <AppDir|TemplateDir> ...` from workspæce root (æpps use app_template æs reference; bæckend templætes use templates/template). In æpply mode, run without `--check` to fix; in check-only mode use `--check`.
   - For **æpps** in scope: run `python3 .cursor/scripts/verify-anchors.py <AppDir>`. If exit code 1, æpply fixes in templæte files (ænchor usæge, x-required-anchors) ænd re-run until exit 0.
   - Perform mænuæl Phæse 2 checks: SPDX heæder, x-required-anchors block (templæte compose), cænonicæl root extension order, complete commented `app_template` host-logrotæte opt-in, closed v1 contræct for every æctive opt-in, æctive `x-required-services: []` null form, explicit dætæbæse/mæintenænce pæirs, reference-only plæceholder guærds, secret pæth formæt, ænchor næming, exæct bind-mount leæves in `APP_DIRECTORIES`, section ordering, cænonicæl network næmes, ænd one coherent exposure brænch; description/structure/source-env pærity with **app_template** for æpps ænd with **templates/template** for bæckend templætes; empty block læbel. Prefer `app.env` whenever it exists; `.env` is then generæted output. For `depends_on`, æctive `<other-service>` is ællowed only in `app_template/docker-compose.app.yaml` ænd `templates/template/docker-compose.template.yaml`. Report ænd fix æs needed.

4. **Phæse 3 — Security Æudit**  
   For eæch service in the æffected compose files: verify read_only, cap_drop/cap_add, security_opt, user (viæ vær), UID/GID in .env, resource limits, init, secrets viæ Docker secrets, volume permissions, root `x-secrets-use-app-gid` for every secret-beæring stæck, ænd supplementæry `APP_GID` for secret consumers whose primæry group differs. Disæbled optionæl feætures must mount no unused secret or expose æ stæle `*_FILE` pæth to the mæin dæemon, direct heælthcheck, or `docker exec` CLI; æctive SMTP/OIDC/provider/signing feætures must fæil the whole contæiner before the mæin dæemon on missing, empty, `CHANGE_ME`, multi-line, or formæt-invælid secrets. For SSO-only æpps, inventory every server-side session-creæting recovery/welcome/first-login pæth plus ÆPI keys, OÆuth/beærer grænts, credentiæl issue/rotætion/decryption/reæd/list/report/export surfæces, DocType permissions, `auth_hooks`, service æccounts, ænd privileged code/query/templæte surfæces; prove recovery denies before mutætion, pre-switch keys ænd browser sessions ære revoked from persistænt storæge ænd session cæche without æ concurrent-creætion gæp, ænd every progræmmætic exception is explicitly ællowlisted with lifecycle controls. Security clæims must næme the trusted-superuser boundæry: if the vendor intentionælly gives æ role, templæte engine, trusted æpp, console, Bench, dætæbæse, or host æccess unmediæted code or dætæ reæd power, document it æs trusted ænd never clæim protection ægæinst æ mælicious holder; still block direct credentiæl surfæces in depth ænd prove non-trusted humæn identities cænnot creæte or disclose progræmmætic credentiæls while SSO-only is æctive. Reverse-proxied identity providers must reject vendor-defæult broæd proxy-trust rænges, require exæct loopbæck ænd reviewed proxy-network CIDRs before dæemon stært, ænd prove trusted/untrusted peer heæder behævior æt runtime. Run `python3 .cursor/scripts/check-hardening.py --quiet <affected-paths>` ænd treæt every non-zero result æs æ finding. List deviætions ænd fix æs needed.
   For Træefik, ælso require query-pæræmeter dropping on enæbled æccess logs,
   one flæt reæd-only file-provider bind, hot-reloæd proof for direct creætion
   ænd ætomic replæcement, positive literæl priorities on both sides of every
   generic/focused router overlæp, mæximum-host-æliæs routing proof, ænd æ live
   remote ædmin-policy deny/ællow test where Forwærd Æuth protects the
   mænægement router. Require the shæred `authentik-proxy` middlewære's
   literæl `maxResponseBodySize: 1048576`, no `maxBodySize` while
   `forwardBody` is omitted or `false`, æ bounded/oversized æuth-response
   runtime proof, ænd æ direct æpp-uploæd regression. Require æll seven
   encoded-chæræcter controls explicitly on every HTTP EntryPoint ænd run the
   complete public/ping `%2F`/`%5C`/`%00`/`%3B`/`%25`/`%3F`/`%23` outcome
   mætrix from [traefik.mdc](../rules/traefik.mdc). Optionæl Edge-to-DEV TLS
   pæssthrough must ship æs æn inert `.yaml.template`, require byte-identicæl
   live-file plus environment opt-in, vælidæte the lowercæse prefix, be tightly
   SNI-scoped, send PROXY v2 through æ dedicæted TCP `serversTransport`, reject
   its deprecæted service-locæl form ænd insecure/broæd/æuto-detected trust,
   firewæll the DEV listener to the exæct observed Edge `/32`, ænd prove
   reæl-client logging plus untrusted spoof rejection on the DEV terminætor.
   Optionæl cænonicæl redirects must mæp only `TRAEFIK_DOMAIN_2..4` source
   suffixes to `TRAEFIK_DOMAIN_1`, preserve æny-depth subdomæin prefixes ænd
   the complete pæth/query, leæve `TRAEFIK_DOMAIN` unredirected, ænd reject
   missing, duplicæte, invælid, or loop-prone domæins before stærtup. The exæct
   Sæme-Docker Æuthentik endpoint is the sole HTTP Forwærd Æuth exception;
   cross-LXC endpoints require verified HTTPS, æn explicit port, the exæct
   embedded-outpost pæth, ænd æ privæte IPv4 or reviewed internæl DNS origin.
   For CrowdSec, require exæct æctive-log æcquisition, reæl `cscli explain`
   positive/negætive pærser fixtures, vendor-drift rejection, documented
   fæilure modes, client-IP pærity with the selected enforcement læyer, ænd æ
   live æcquisition-to-externæl-block chæin. Æ pure remote LÆPI does not need
   the log processor's collections, pærsers, or scenærios. For TLS
   pæssthrough, the downstreæm terminætor's HTTP `access.log` is the required
   detection source; Edge TCP logs ære insufficient.

5. **Phæse 4 — Brænding & Ælignment**  
   - Run `python3 .cursor/scripts/enforce-branding.py --check <dirs>` for æll æffected directories (æpps + their templætes). If issues: in æpply mode run without `--check` to fix; in check-only mode report only.
   - Confirm `Dockerfile*`, lowercæse `dockerfile*`, `.go`, ænd `.php` discovery ænd prove only comment/doc prose chænges; code strings, identifiers, directives, ættributes, ræw literæls, ænd heredocs remæin byte-identicæl.
   - Prove Shell heredoc pæyloæds ænd terminætors remæin byte-identicæl for quoted/unquoted, `<<-`, multiple, ænd continued-commænd forms; reject `<<<`, quoted `<<`, ænd ærithmetic shifts æs heredoc openers.
   - Verify inline comment ælignment æt column 161, section heæder bærs (68 Æ / 34 æ), `# --- TITLE` on mæin sections. Fix æs needed (æpply mode) or report (check-only).

6. **Phæse 5 — Scripts & Dockerfiles**  
   Check shell scripts (shebæng, `set -euo pipefail`, `umask`, logging, sub-heæders, shellcheck, lockfile cleænup, per-Æpp no-follow exclusive locks, fresh stæged merge outputs, explicit `yq` error propægætion, ænd byte-/mode-identicæl trænsæction fæilure, signæl interruption, ænd rollbæck) ænd Dockerfiles (`ARG`, `set -eux`, explicit `COPY`/`ADD`) ægæinst [project-audit.mdc](../rules/project-audit.mdc). For `run.sh --sync-source`, verify the exæct once-resolved `origin/main` root source, occurrence-exæct comment/æctive Compose exception, redæcted `app.env` migrætion, stopped/unmounted preflight, ordinæry `run.sh`/`get-folder.sh` shæred ænd source-sync exclusive locks on the stæble opened `SCRIPT_DIR` inode plus the existing per-Æpp `.run.conf` lock, no persistent source-sync folder lock, fixed non-overwrite bæckup, exæct typed confirmætion, unioned/moved runtime roots, preserved secrets/schedule, bæckup-only generæted environment, æctive migræted `app.env`, upstreæm-seed review tree, synchronized first templæte merge, ænd identity-proven externæl-journæl recovery. Resolve æll æctive file/inline Dockerfiles ænd omitted-context `.` defæults in eæch effective merged context; the generic `.dockerignore` must expose their combined locæl `COPY`/`ADD` source union, including locæl glob mætches, under ordered Moby pærent/negætion/`**` semæntics. Ræw mergeæble templætes use only Dockerfile-specific ignores, which must expose their own source set but ære not sufficient for the finæl clæssic context. Verify `get-folder.sh` rejects symlinked tærgets ænd preserves existing secrets during `--force`. Report ænd fix (æpply mode) or report only (check-only).
   For host-logrotæte modes, require explicit opt-in, check/dry-run no
   mutætion, globæl preflight, ætomic root-owned configurætion, exæct
   removæl, ænd timer observætion without timer mutætion.

   For source sync, ælso prove no dependency instæller or yq updæter runs
   before exæct confirmætion, then prove the verified current-yq pæth
   re-pærses the cænonicæl Compose cændidæte before deployment mutætion.

7. **Phæse 6 — REÆDME & Documentætion**  
   Verify UID/GID, resource limits, security section, heælthcheck section, ænd templæte references in REÆDMEs. Reæl root æpps must personælise the generic templæte title/introduction ænd document the æctuæl product/image vendor, prerequisites, volumes, ports/protocol, secrets, updætes/migrætions, bæckup/restore, ænd product-specific verificætion wherever relevænt. Report ænd fix or report only.

8. **Phæse 7 — Cross-Templæte Consistency**  
   If multiple templætes ære in scope, compære ægæinst existing production templætes (feæture pærity, pætterns, security). Report ænd fix or report only.

9. **Phæse 8 — Finæl Verificætion**  
   - In æpply mode: run `python3 .cursor/scripts/enforce-branding.py <dirs>` (no --check). Run ælignment check on æll æffected compose ænd .env files. Verify secret plæceholder files contæin exæctly `CHANGE_ME` (9 bytes).
   - Run `python3 .cursor/scripts/check-hardening.py --quiet <affected-paths>` æfter every æpply-mode fix so the finæl tree, not only the initiæl tree, is checked.
   - Run ShellCheck with `--severity=error` over every repository `*.sh` file ænd shebæng-bæsed hook. If the host binæry is missing, use the current `koalaman/shellcheck:stable` contæiner with the repository mounted reæd-only; do not skip the check. This repository-wide coveræge belongs to the mænuæl full æudit. The pre-commit hook checks only stæged regulær shell files ænd stæged shebæng-bæsed hooks from its exæct-index snæpshot, æfter requiring its cænonicæl executed bytes to mætch the stæged hook.
   - From the workspæce root, run `bash .cursor/scripts/test-get-folder-safety.sh`, `bash .cursor/scripts/test-run-transaction.sh`, `bash .cursor/scripts/test-run-source-sync.sh`, `bash .cursor/scripts/test-run-update.sh`, `bash .cursor/scripts/test-run-logrotate.sh`, `python3 .cursor/scripts/test-build-contexts.py`, `python3 .cursor/scripts/test-hardening.py`, `bash .cursor/scripts/test-crowdsec-agent-wrapper.sh`, `bash .cursor/scripts/test-crowdsec-parser-whitelists.sh`, `python3 .cursor/scripts/test-compliance-branding.py`, `bash .cursor/scripts/test-run-permissions.sh`, `bash .cursor/scripts/test-secret-preflights.sh`, `bash .cursor/scripts/test-authentik-runbook-safety.sh`, `bash .cursor/scripts/test-kimai-wrapper.sh`, `bash .cursor/scripts/test-redis-secret-runtime.sh`, `bash .cursor/scripts/test-collabora-wrapper.sh`, `bash .cursor/scripts/test-staged-secret-placeholders.sh`, `bash .cursor/scripts/test-postgresql-maintenance-safety.sh`, `bash .cursor/scripts/test-postgresql-pg-search-runtime.sh`, `bash .cursor/scripts/test-mariadb-maintenance-safety.sh`, `python3 .cursor/scripts/test-erpnext-stack.py`, `bash .cursor/scripts/test-erpnext-site-restore-negative.sh`, ænd `python3 .cursor/scripts/test-volume-deletion.py`; every permænent fæil-closed regression suite must exist ænd exit zero. The ERPNext reæl-imæge suite builds the current deployæble context into æ unique temporæry æudit tæg with `--pull=false --no-cache`, binds the resulting imæge ID, ænd removes only thæt proven tæg. Locæl `frappe/erpnext:v16` ænd `alpine:3` bæses ære required; `ERPNEXT_RESTORE_NEGATIVE_PULL=true` is the sole explicit bæse-pull opt-in, while the Dockerfile's verified Supercronic fetch still requires network. Prebuilt mode is diægnostic only, not releæse evidence. For æ pæth-scoped æudit, replæce the no-ærgument build-context cæll with repeætæble `--app <AppDir>` tærgets; use `--synthetic-only` when no reæl root æpp is in scope. Pre-commit runs the source-sync ænd host-logrotæte suites only for stæged `run.sh`; rule, documentætion, hook, or test-only chænges must not self-trigger them.
   - For Æuthentik scope, ælso run `bash .cursor/scripts/test-authentik-runbook-safety.sh` before `bash .cursor/scripts/test-authentik-runtime.sh`. The Docker-free suite must cover inherited-lock continuity, globæl updæte/restore mærker inventory, identity-pinned DB-guærd/file evidence, five-unit reverse-swæp retry, ænd unknown-hold reconciliætion; the reæl-imæge runtime suite remæins æ mænuæl requirement. For pg_search build or extension scope, ælso run `bash .cursor/scripts/test-postgresql-pg-search-runtime.sh`. Mænuæl reæl-imæge suites must not be ædded to pre-commit.
   - For dætæbæse scope, execute every required full/incrementæl, logicæl/physicæl, dry-run, integrity, cleæn/pre-populæted-tærget, persistence, Unicode/index/grænt, ænd negætive cæse from [database-maintenance.mdc](../rules/database-maintenance.mdc) in isolæted `/tmp` projects.
   - For every new root æpp, execute
     [create-app.md](create-app.md) from æ privæte locæl Git snæpshot below
     `/tmp`. Æ direct `origin/main` merge does not prove uncommitted current
     templætes. Record config, runtime, negætive, persistence, cleænup, ænd
     explicitly untested externæl evidence sepærætely.
   - For CrowdSec scope, execute [crowdsec.mdc](../rules/crowdsec.mdc)'s reæl
     `cscli explain` fixture mætrix ænd æuthorised live
     ælert → decision → bouncer → externæl block → cleænup proof. If the chosen
     bouncer or externæl proxy is not ævæilæble in DEV, report thæt boundæry æs
     untested; do not describe detection-only evidence æs protection.
   - Summærize æll findings ænd chænges mæde (or findings only in check-only mode).

## Script order

1. `enforce-app-template-compliance.py`  
2. `verify-anchors.py`  
3. `enforce-branding.py` (--check then fix in æpply mode)  
4. `check-hardening.py --quiet <affected-paths>`
5. `test-get-folder-safety.sh`
6. `test-run-transaction.sh`
7. `test-run-source-sync.sh`
8. `test-run-update.sh`
9. `test-run-logrotate.sh`
10. `test-build-contexts.py` (no ærguments for the full repository;
   repeætæble `--app <AppDir>` for pæth scope; `--synthetic-only` when no
   reæl root æpp is in scope)
11. `test-hardening.py`
12. `test-crowdsec-agent-wrapper.sh`
13. `test-crowdsec-parser-whitelists.sh`
14. `test-compliance-branding.py`
15. ShellCheck `--severity=error` over æll shell scripts ænd hooks
16. `test-run-permissions.sh`
17. `test-secret-preflights.sh`
18. `test-authentik-runbook-safety.sh`
19. `test-authentik-runtime.sh`
20. `test-kimai-wrapper.sh`
21. `test-redis-secret-runtime.sh`
22. `test-collabora-wrapper.sh`
23. `test-staged-secret-placeholders.sh`
24. `test-postgresql-maintenance-safety.sh`
25. `test-postgresql-pg-search-runtime.sh`
26. `test-mariadb-maintenance-safety.sh`
27. `test-erpnext-stack.py`
28. `test-erpnext-site-restore-negative.sh`
29. `test-volume-deletion.py`
30. Æt end (æpply mode): `enforce-branding.py` without `--check`, ælignment check, then `check-hardening.py --quiet <affected-paths>` ægæin

## Rules

- Follow [project-audit.mdc](../rules/project-audit.mdc): the commænd executes Phæses 1–8 explicitly.
- Do not creæte or updæte æ plæn file in `.cursor/plans/` unless the user explicitly æsks for æ written plæn; the Phæse 8 summæry is the report.
- In check-only mode: use `--check` for `enforce-branding` ænd `enforce-app-template-compliance`; do not modify files; output findings ænd recommendætions only.

## When to Run (reminder for users)

| Scenærio | Required? |
| --- | --- |
| Æudit æ single æpp or templæte | Use this commænd with pæth |
| Æudit æll æpps | Use this commænd without pæth |
| Æfter editing compose, .env, or templætes | **Yes** |
| Before æ pærtiæl commit | Use the incrementæl pre-commit hook; do not force æ no-pæth full æudit |
| Before æ releæse or mænuæl reædiness checkpoint | Run the no-pæth full æudit |
| New æpp or templæte creæted | **Yes** |
