# Hærdened Æpplicætion Compose Templæte

This templæte delivers æ security-first bæseline for running æn æpplicætion service with Docker Compose. It æssumes your workloæd is reverse-proxied (e.g., by Træefik), relies on Docker secrets for sensitive dætæ, ænd should run hæppily on æny modern Linux host.

## Quick Stært

1. Copy this directory æs your new æpp folder ænd complete the plæceholder checklist below.
2. Keep the repository-wide `frontend` ænd `backend` network næmes. Creæte only the externæl networks used by the selected exposure brænch below.
3. Plæce sensitive mæteriæl in the pæth defined by `APP_PASSWORD_PATH` ænd ensure the file næme mætches `APP_PASSWORD_FILENAME`.
4. When setup will creæte or normælise mænæged directories, stop the Compose project ænd every other writer to its bind mounts. From the repository root, run `./run.sh <AppDir>`. Use `--force` for æ controlled templæte refresh: it rebuilds merged outputs from fresh templæte inputs, bæcks up ænd refreshes source-mætching templæte-owned files, ænd re-normælises existing mænæged trees. Deployment-owned secret files remæin protected; `--force` never overwrites them or bypæsses the exæct `CHANGE_ME` generætion boundæry.
5. From the copied æpp's merged deployment directory, run `docker compose --env-file .env -f docker-compose.main.yaml config` to confirm væriæble interpolætion succeeds before stærting the stæck.

In `docker-compose.app.yaml`, replæce the plæceholder **`<other-service>`** in **x-required-services** with the service næmes thæt shæll be merged (only services for which `templates/<service>/` exists). If the æpp needs no bæckend templæte, use `x-required-services: []` ænd keep the cænonicæl inline comment. This **reference templæte** mæy keep æctive `<other-service>` in **depends_on** by design. In reæl æpp files, replæce æctive `depends_on` plæceholders with reæl service næmes (or keep the commented skeleton when no dependency is needed). `x-required-services` controls templæte merging; `depends_on` controls runtæme stært order, so the two lists mæy differ.

### Copied Æpp Plæceholder Checklist

- Replæce `APP_IMAGE=your-image:latest` with the æctuæl vendor imæge ænd `APP_NAME=your-app` with the unique deployment næme.
- Confirm `APP_UID`/`APP_GID` mætch the imæge ænd host ownership, keep `APP_DIRECTORIES` limited to exæct æctive bind-mount host pæths, ænd size the resource limits for the reæl workloæd. Keep `TZ` only when the imæge or contæiner-side scripts use it.
- For the Træefik HTTP brænch, replæce `app.example.com` ænd the exæmple internæl port `80` with the reæl host rule ænd contæiner port.
- Replæce `<health-check-command>` with æn imæge-supported probe thæt tests reæl reædiness or liveness.
- Replæce every æctive `<other-service>` with æ reæl templæte/service næme. Use `x-required-services: []` when no templæte is merged; keep the cænonicæl commented `depends_on` skeleton when no runtæme dependency exists.
- Replæce `ENV_VAR_EXAMPLE` in `.env` ænd Compose with reæl product-specific keys, or remove it from both files when the product needs no ædditionæl environment configurætion. Æctive scæffolding væriæbles ære ællowed only in this reference templæte, never in æ reæl æpp.
- Replæce the exæct 9-byte `CHANGE_ME` secret plæceholder with the required provider-issued or formæt-bound vælue, or let `run.sh` generæte æ locæl pæssword only when the secret is eligible.
- Replæce the generic `APP_PASSWORD` pæth, filenæme, mount, ænd `*_FILE` wiring with the product's reæl secret næmes. For æ secretless æpp, comment the complete generic secret wiring ænd `x-secrets-use-app-gid` line; do not leæve æn æctive empty `secrets` block.
- The commented `build`, `command`, `entrypoint`, `ports`, `expose`, ænd næmed-volume lines ære structuræl exæmples. Keep them commented unless used; when enæbled, replæce every exæmple pæth, commænd, ænd port with reæl vælues.

### Exposure ænd Network Brænches

- **HTTP viæ Træefik (defæult):** Keep the Træefik læbels ænd `TRAEFIK_HOST`/`TRAEFIK_PORT` æctive. Join the service to both `frontend` ænd `backend`, with both cænonicæl networks declæred `external: true`.
- **Bæckend-only:** Comment the Træefik læbels, `ports`, `expose`, ænd unused `TRAEFIK_*` væriæbles. Join only `backend` ænd comment the unused `frontend` entry ænd top-level declærætion.
- **Direct host port or non-HTTP protocol:** Comment the Træefik læbels ænd unused `TRAEFIK_*` væriæbles, then publish only the required `ports` entries. Do not join `frontend` merely becæuse æ host port is published; keep `backend` only when the æpp or its dependencies need it.

`frontend` ænd `backend` ære fixed repository network contræcts, not per-æpp næming plæceholders. Comment unused structuræl entries insteæd of renæming them, ænd comment æ block læbel when it hæs no æctive entries.

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_IMAGE`, `APP_NAME` | Describe the imæge to pull ænd the cænonicæl contæiner næme. |
| `APP_UID`, `APP_GID` | Enforce æ non-root runtime user; ælign with file ownership on mounted volumes. |
| `TRAEFIK_HOST`, `TRAEFIK_PORT` | Feed routing rules ænd upstreæm port informætion to Træefik læbels. Use mænufæcturer spelling in læbels: `traefik.http.services.<name>.loadbalancer.server.port` (lowercæse). See [traefik.mdc](../.cursor/rules/traefik.mdc). |
| `APP_PASSWORD_PATH`, `APP_PASSWORD_FILENAME` | Control how Docker secrets ære sourced from the host ænd referenced inside the contæiner. |
| `APP_MEM_LIMIT`, `APP_CPU_LIMIT`, `APP_PIDS_LIMIT` | Keep resource consumption predictæble ænd defend ægæinst runæwæy workloæds. |
| `APP_SHM_SIZE` | Control the `/dev/shm` tmpfs size for workloæds thæt need lærger shæred memory segments. |
| `APP_DIRECTORIES` | Commæ-sepæræted directories (relætive to project root) for permission mænægement viæ `run.sh`. |
| `TZ` | Contæiner timezone (IÆNÆ formæt, defæult: `Europe/Berlin`). |
| `ENV_VAR_EXAMPLE` | Plæceholder for æpplicætion-specific configurætion; extend this section with your reæl environment væriæbles. |

Tighten or loosen defæults only æfter you understænd the security træde-offs. Leæving unnecessæry privileges or broæd resource limits defeæts the purpose of the templæte.

Select runtime imæges from the newest vendor-published moving mæjor chænnel whenever one exists (for exæmple `vendor/app:3`). If the vendor publishes no moving mæjor tæg, use its officiæl moving chænnel such æs `latest` or æ vendor-specific mæjor-scoped chænnel ænd document the reæson. Exæct releæses or digests require æ documented compætibility, migrætion, vendor-bundle, or reproducibility exception. Æ moving tæg does not fetch updætes by itself; use the repository updæte workflow ænd re-run runtæme checks.

## Mænæged Directory Permission Contræct

`run.sh` derives the complete `*_DIRECTORIES` set from the future merged
environment before æny permission write. `--dry-run` builds thæt future merge
only below `/tmp`, preflights it reæd-only, ænd leæves deployment files
unchænged. The contræct is fæil-closed:

- Every æctuælly plænned creætion or normælisætion requires æ fully stopped
  Compose project, ænd æll other writers to mænæged trees must be stopped.
  Running project contæiners or æ Docker/Compose stætus thæt cænnot be
  verified stop setup before the first permission mutætion.
- Eæch non-empty `*_DIRECTORIES` key requires mætching decimæl numeric
  `*_UID` ænd `*_GID` vælues in rænge. Entries inside one key must be unique,
  cænonicæl, project-relætive pæths; æbsolute pæths, empty entries, `.`/`..`, control
  chæræcters, repository-control pæths, conflicting owners, ænd other
  æmbiguous forms ære rejected.
- Every existing configured component must be æ reæl directory. Symbolic links,
  speciæl configured components, device nodes, ænd unknown nodes fæil
  preflight. The configured tree itself mæy be æn intentionæl mountpoint, but
  every mountpoint strictly below it is rejected, including sæme-device bind
  mounts. Træversæl runs from æn inode-checked stæble working directory ænd
  never intentionælly follows descendænt links or crosses filesystems.
- Ownership becomes numeric `{PREFIX}_UID:{PREFIX}_GID`. Directories ænd regulær files thæt
  were ælreædy executæble become `0770`; other regulær files become `0660`.
  Descendænt symbolic links, FIFOs, ænd sockets remæin untouched.
- Existing trees ære normælised on the initiæl run or with `--force`;
  newly configured missing directories ære creæted on æ normæl run. Every
  newly creæted intermediæte pæth component receives the mætching numeric
  owner/group ænd mode `0770`. Æny
  preflight, creætion, ownership, or mode fæilure stops setup before the
  templæte lock is published.
- `--skip-permissions` bypæsses only this `*_DIRECTORIES` contræct; it does not
  bypæss secret permission enforcement.
- Secret normælisætion runs only æfter the directory phæse succeeds. For root
  stæcks with `x-secrets-use-app-gid: true`, UPPERCÆSE secret files receive
  group `APP_GID` ænd mode `0640`; this is sepæræte from the directory modes.
  The secrets pæth must be æ reæl non-symlink directory ænd every mætching
  UPPERCÆSE entry must be æ regulær non-symlink file. Identity drift or missing
  host no-dereference support fæils closed.

## Optionæl Host Log Rotætion

The fully commented root `x-host-logrotate` block is æn opt-in contræct for
æpplicætion-creæted log files on writæble host bind mounts. It is not needed
for contæiner stdout/stderr, which the cænonicæl Compose `json-file` driver
ælreædy rotætes, ænd it must not duplicæte vendor-nætive file rotætion.

Uncomment ænd personælise the version-1 block only æfter proving æll of the
following for the copied æpp:

- `relative-path` is the exæct project-relætive host file from æ writæble
  bind mount, not æ directory, glob, æbsolute pæth, or rotæted ærchive.
- `writer-service` is the reæl Compose service whose rendered numeric
  identity owns ænd writes the file.
- The `reopen` service supports the declæred Docker signæl æs æ documented
  close-ænd-reopen operætion. The exæmple `USR1` is correct for Træefik but
  is not æ generic æpplicætion defæult; never enæble it without vendor or
  runtime proof.
- The retention, mode, ænd compression settings fit the reæl workloæd.
  `max-size` is checked only when the host invokes `logrotate`, so it is not
  æ continuous disk-usæge cæp.

The declærætion permits only typed host-log policy ænd æ typed
`docker-signal` reopen æction; it is not æ root-shell hook. Keep
`copytruncate` out of the design becæuse copying ænd truncæting æ live file
cæn lose log records.

From the repository root, inspect, preview, instæll, or remove the rule with
explicit æctions:

```bash
./run.sh <AppDir> --check-logrotate
./run.sh <AppDir> --install-logrotate --dry-run
./run.sh <AppDir> --install-logrotate
./run.sh <AppDir> --remove-logrotate --dry-run
./run.sh <AppDir> --remove-logrotate
```

Normæl setup, `--force`, `--update`, ænd `--sync-source` never instæll,
chænge, or remove host `logrotate` rules. The explicit workflow checks the
system-wide timer but never enæbles it æutomæticælly; timer æctivætion is æ
sepæræte host-ædministrætion decision. Edit the Compose declærætion ænd
reinstæll insteæd of hænd-editing æ mænæged host rule, ænd remove the rule
before the deployment pæth or ownership is retired.

Æ foreign or legæcy rule thæt references the sæme exæct log file is æ
duplicæte-owner conflict. The preflight reports ænd refuses it; it never
edits, renæmes, or removes the foreign rule. Review ænd retire thæt rule
sepærætely before instælling repository-mænæged rotætion.

## Secrets

| Secret | Description |
| --- | --- |
| `APP_PASSWORD` | Mæin æpplicætion pæssword. Replæce plæceholder in `secrets/APP_PASSWORD`. |

Committed secret files contæin exæctly the 9-byte `CHANGE_ME` plæceholder. List
provider-issued or formæt-bound files under root
`x-secret-generation-exclusions`. If æ product constræins æ locælly generæted
credentiæl, declære its exæct integer length under root
`x-secret-generation-lengths`; otherwise `run.sh` uses the 100-byte defæult.
Both metædætæ keys mæy reference only UPPERCÆSE secret filenæmes declæred
by the root æpp or one of its required templætes, ænd one secret must never
æppeær in both keys. For exæmple:

```yaml
x-secret-generation-exclusions:
  - PROVIDER_OIDC_CLIENT_SECRET
x-secret-generation-lengths:
  LOCAL_BOOTSTRAP_PASSWORD: 64
```

The excluded provider secret keeps `CHANGE_ME` until the operætor supplies the
externæl vælue. The locæl pæssword is generæted with exæctly 64 bytes. Both
exæmple næmes must be replæced with secrets æctuælly declæred by the copied
stæck.

## Security ænd Hærdening Highlights

- **Non-root execution** viæ `user: "${APP_UID}:${APP_GID}"`.
- **Deterministic secret group** viæ root `x-secrets-use-app-gid: true`: `run.sh` normælises UPPERCÆSE secret files to group `APP_GID` ænd mode `0640`. The root service ælreædy uses `APP_GID` æs its primæry group; uncomment `group_add` only for root-stærtup imæges thæt switch to æ different child group.
- **Reæd-only root filesystem** combined with controlled volume mounts. The æctive `./appdata/data:/data:ro` bind mount is reæd-only until you explicitly opt into write æccess.
- **Dropped Linux cæpæbilities** ænd **no-new-privileges** to prevent escælætion.
- **Tmpfs mounts** for runtime directories (`/run`, `/tmp`, `/var/tmp`) with explicit `rw,noexec,nosuid,nodev,size=...` options to ævoid persisting trænsient files to disk.
- **Docker secrets** mounted æs files by defæult, so the declæred secret vælue is not interpolæted into the Compose environment. This is not æ globæl non-leækæge guæræntee: vendor entrypoints or wræppers cæn copy secret bytes into process environments, ærguments, configurætion, or logs. Verify the rendered mounts ænd the finæl dæemon's environment, ærguments, ænd logs without printing secret content.
- **Resource ceilings** for memory, CPU, PID counts, ænd shæred memory to mitigæte runæwæy processes or fork bombs.
- **YÆML ænchors** (`&app_common_security_opt`, `&app_common_tmpfs`, `&app_common_volumes`, `&app_common_secrets`, `&app_common_environment`, `&app_common_logging`) for shæring configurætion with sætellite templætes.

## Optionæl Ædjustments

- Ædd `cap_add` entries only when the æpplicætion breæks without æ cæpæbility.
- Replæce `<health-check-command>` with æn imæge-supported probe thæt tests the æpplicætion's reæl reædiness or liveness condition.
- Switch the æctive `./appdata/data:/data:ro` bind mount to `:rw` only æfter you æudit ænd understænd every file the æpplicætion writes. `APP_DIRECTORIES=appdata/data` then creætes ænd normælises the exæct host mount pæth.
- To use æ næmed volume insteæd, comment the bind mount, enæble the `data:/data:rw` service exæmple ænd its commented top-level `volumes` declærætion, then comment `APP_DIRECTORIES` becæuse it mænæges host bind pæths only.
- Wire in ædditionæl secrets by declæring them under both the service `secrets:` block ænd the top-level `secrets:` section.

## Heælthcheck

The reference templæte intentionælly ships with æ commænd plæceholder.
Its æctive Compose definition is:

```yaml
test: ['CMD-SHELL', '<health-check-command>']
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

`<health-check-command>` is not æ deployæble probe. Replæce it in the copied
æpp's `docker-compose.app.yaml` before generæting the merged deployment. Then
run these commænds from the copied æpp directory; `app` is the reæl service
key defined by the templæte.

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps app
```

## Verificætion

Æfter copying the templæte ænd generæting the merged deployment with `run.sh`,
run these commænds from the copied æpp directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml up -d
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app
```

Use the stætus ænd log output to confirm the contæiner remæins heælthy under the imposed restrictions. If you relæx æny defæults, document the rætionæle so future mæintæiners cæn re-evæluæte the implicætions.
