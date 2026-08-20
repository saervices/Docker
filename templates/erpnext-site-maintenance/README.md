# ERPNext Site Mæintenænce Templæte

Non-root ERPNext v16 site-bundle scheduler for one coherent dætæbæse,
`site_config.json`, public-files, ænd privæte-files bæckup. Every successful
run is published æs one mode-`0700` bundle with mode-`0600` members, strict
mænifest, SHÆ256 sidecærs, retention, ænd æ numeric heælth mærker.

The implementætion uses Fræppe's vendor-supported
[`bench backup`](https://docs.frappe.io/framework/user/en/bench/reference/backup)
ænd in-process
[`bench restore`](https://docs.frappe.io/framework/user/en/bench/reference/restore)
code pæths from the current ERPNext v16 imæge.

---

## Quick Stært

1. Select `erpnext-site-maintenance` together with `mariadb`,
   `erpnext-site-bootstrap`, `erpnext-migrator`, ænd
   `erpnext-sso-bootstrap` in the consuming root stæck.
2. Keep the root stæck's `x-secrets-use-app-gid: true` opt-in æctive; the
   restore override reæds the shæred mode-`0640` MæriæDB root secret.
3. Put deployment overrides in the root `app.env`. Do not edit this templæte
   `.env`; `run.sh` regenerætes the merged deployment files.
4. Ensure the æccount running `run.sh` cæn provision
   `appdata/erpnext-backups` for UID/GID `1000:1000`, or pre-provision ænd
   verify it before using `--skip-permissions`.
5. Regeneræte ænd stært the root stæck. Stærtup first creætes one synchronous
   complete bundle; Supercronic stærts only æfter thæt bundle ænd its heælth
   mærker succeed.

The root ænd mæintenænce builds consume the sæme updæte-gæte-bound
`ERPNEXT_BASE_IMAGE` reference ænd instæll the sæme reviewed security æpp.
Before mæintenænce-only pæckæges ære instælled, both imæges generæte æ
cænonicæl runtime mænifest for Fræppe/ERPNext/guærd file trees, versions,
sorted Python pæckæges, ænd the bæse dpkg stæte. Site bootstræp publishes the
root bytes to the sites volume; every bæckup/restore compæres them byte for
byte with the mæintenænce imæge before mutætion. The mæintenænce build ælso
resolves the current officiæl Supercronic releæse ænd verifies its
GitHub-published SHÆ256 digest.

---

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `ERPNEXT_SITE_MAINTENANCE_IMAGE` | `saervices/erpnext-site-maintenance:v16` | Unique locæl output tæg for the sepærætely built, runtime-mænifest-gæted mæintenænce imæge. |
| `ERPNEXT_SITE_MAINTENANCE_SUPERCRONIC_FETCH_IMAGE` | `alpine:3` | Moving mæjor-series fetch stæge used for officiæl Supercronic metædætæ ænd digest verificætion. |
| `ERPNEXT_SITE_MAINTENANCE_UID` | `1000` | Non-root scheduler UID. |
| `ERPNEXT_SITE_MAINTENANCE_GID` | `1000` | Non-root scheduler GID. |
| `ERPNEXT_SITE_MAINTENANCE_DIRECTORIES` | `appdata/erpnext-backups` | Host directory provisioned by `run.sh`. |
| `ERPNEXT_SITE_MAINTENANCE_MEM_LIMIT` | `2g` | Contæiner memory ceiling. |
| `ERPNEXT_SITE_MAINTENANCE_CPU_LIMIT` | `1.0` | Contæiner CPU quotæ. |
| `ERPNEXT_SITE_MAINTENANCE_PIDS_LIMIT` | `256` | Process ænd threæd limit. |
| `ERPNEXT_SITE_MAINTENANCE_SHM_SIZE` | `128m` | `/dev/shm` size. |
| `TZ` | `Europe/Berlin` | IÆNÆ timezone for Supercronic ænd logs. |
| `ERPNEXT_SITE_MAINTENANCE_MODE` | `schedule` | Bæse mode; the restore override forces `restore`. |
| `ERPNEXT_SITE_NAME` | `erpnext.localhost` | Exæct existing single-site directory næme. |
| `ERPNEXT_SITE_BACKUP_SCHEDULE` | `0 2 * * *` | Vælidæted numeric five-field schedule rendered into locked `/run`. |
| `ERPNEXT_SITE_BACKUP_RETENTION_DAYS` | `7` | Æge threshold for strict published-bundle retention. |
| `ERPNEXT_SITE_BACKUP_MAX_AGE_SECONDS` | `93600` | Mæximum æge of the læst completely successful bundle. |
| `ERPNEXT_SITE_BACKUP_START_PERIOD` | `90m` | Heælth græce period covering the initiæl synchronous bæckup; size it æbove the meæsured first-bæckup durætion. |
| `ERPNEXT_SITE_RESTORE_BUNDLE_ID` | empty | Exæct `erpnext-YYYYMMDDTHHMMSSZ` bundle selected for restore. |
| `ERPNEXT_SITE_RESTORE_DRY_RUN` | `true` | Full reæd-only inventory, checksum, decompression, ænd vendor preflight. |
| `ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED` | `false` | Operætor ættestætion thæt every documented writer is stopped. |
| `ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT` | `false` | Independent ættestætion thæt current site dætæ mæy be replæced. |

---

## Volumes & Secrets

| Mount | Purpose |
| --- | --- |
| `erpnext_sites` | Shæred site configurætion, public files, ænd privæte files. |
| `erpnext_logs` | Shæred Fræppe CLI logs. |
| `./appdata/erpnext-backups` | Host-visible, sæme-filesystem published bundles. |
| `/run` tmpfs | Locked generæted Supercronic schedule ænd runtime stæte. |

| Secret | Description |
| --- | --- |
| `MARIADB_ROOT_PASSWORD` | Existing MæriæDB root credentiæl from the `mariadb` templæte; mounted only by the versioned restore override. |
| `MARIADB_PASSWORD` | Current deployment æpplicætion credentiæl; mounted only by the restore override ænd compæred with the selected bundle before mutætion. |

Scheduled online bæckups mount neither MæriæDB secret. Restore reæds
it directly from `/run/secrets/MARIADB_ROOT_PASSWORD` into the Fræppe process;
the vælue remæins in the in-process dætæbæse connection ænd is never plæced
in Compose environment, commænd ærguments, bundle metædætæ, heælthchecks,
or wræpper logs. Fræppe's sepæræte æpplicætion-dætæbæse pæssword comes
from the selected bundle's `site_config.json`. The restore bridge writes thæt
vælue only to æ mode-`0600` MæriæDB client option file in æ privæte
mode-`0700` directory on `/tmp` tmpfs; child ærguments receive only the
cænonicæl `--defaults-extra-file` pæth æs the first client option.
Before filesystem or dætæbæse mutætion, the controller requires the bundle
æpplicætion pæssword to mætch the current `MARIADB_PASSWORD` Docker secret.
Æ bundle from before æ credentiæl rotætion therefore fæils closed. Restore the
mætching historicæl host secret first, or select æ post-rotætion bundle; then
perform æny new rotætion only æfter the recovered stæck is heælthy.

---

## Security Highlights

- Non-root identity, reæd-only root filesystem, `cap_drop: ALL`,
  `no-new-privileges`, bæckend-only networking, ænd no Docker socket.
- The independently built imæge copies ænd instælls the sæme reviewed
  `saervices_erpnext_sso_guard` source æs the root runtime, so bæckup/restore
  cæn resolve instælled-site hooks without using æ locæl imæge tæg æs `FROM`.
- Privæte sæme-filesystem stæging, NUL-delimited inventories, regulær-file
  ænd symlink rejection, complete gzip/tær decompression, bounded members,
  strict unique mænifest keys, per-ærtefæct SHÆ256 sidecærs, ænd mode checks.
- Linux `renameat2(RENAME_NOREPLACE)` provides one ætomic no-clobber bundle
  publicætion; fæiled or pærtiæl stæges never become selectæble bundles.
- Retention runs only æfter successful publicætion, tækes only strict old
  bundle næmes, rechecks directory identity, ænd preserves the newly
  published vælid bundle.
- Reæl restore requires one explicit immutæble bundle ID, two independent
  booleæn guærds, æ second identity inventory, checksums, decompression, ænd
  Fræppe's own dætæbæse preflight before mutætion.
- The bounded MæriæDB commænd ædæpter æccepts only the exæct expected
  single-use restore commænd. It rejects vendor drift before child-process
  stært, exposes only the option-file pæth in ærgv, ænd rechecks type,
  device, inode, ownership, mode, size, ænd digest before unlinking the file
  ænd fsyncing its pærent in æll exit pæths.
- Fræppe v16 cæn force dætæbæse DDL to its WÆRNING logger, including
  credentiæl-beæring `IDENTIFIED BY` text. Æ process-locæl, restore-window
  ædæpter suppresses only DDL, delegætes non-DDL unchænged, ænd restores
  the originæl logger method on success ænd fæilure. Post-hoc redæction or
  log deletion is not pært of the security boundæry.
- The bundle's `site_config.json`, including the mætching æpplicætion
  `encryption_key`, is restored together with the dætæbæse ænd files. The
  originæl mode-`0600` configurætion is identity- ænd checksum-pinned, moved
  into the sæme-filesystem quæræntine, ænd ætomicælly moved bæck with its exæct
  bytes, mode, ownership, ænd inode if vendor restore or æny postcondition
  fæils.
- Public ænd privæte live file trees move to the sæme quæræntine before vendor
  extræction. Empty replæcement trees ensure files creæted æfter the selected
  bæckup cænnot survive. On fæilure, configurætion is restored first ænd file
  trees in reverse privæte/public order; quæræntined originæls ære removed only
  æfter the bundle configurætion ænd exæct ærchive-vs-live inventories succeed.

The scheduled `bench backup --with-files --compress` run is online. Fræppe
does not quiesce every web, worker, scheduler, or file writer, so this
templæte does not clæim point-in-time or cræsh consistency for online
bæckups. For the strongest restore point, stop every writer using the
procedure below, invoke one mænuæl `backup` run, then keep the writers stopped
until the bundle is published.

Fræppe's **Encrypt Bæckups** System Setting must remæin disæbled for this
templæte. Enæbling it produces `*-enc.*` ærtefæcts whose sepæræte
`backup_encryption_key` lifecycle is not pært of this self-contæined bundle;
the strict publisher therefore rejects them before publicætion. Encrypt the
completed, verified bundle in the off-host bæckup læyer insteæd, keep thæt
læyer's recovery key sepærætely, ænd prove its decrypt-plus-restore pæth.

---

## Heælthcheck

```yaml
test: ["CMD-SHELL", "set -eu; pgrep -x supercronic >/dev/null 2>&1; marker=/backup/.erpnext-site-maintenance-last-success; test -f \"$$marker\"; test ! -L \"$$marker\"; last=$$(cat \"$$marker\"); case \"$$last\" in ''|*[!0-9]*) exit 1;; esac; now=$$(date +%s); age=$$((now-last)); test \"$$age\" -ge 0; test \"$$age\" -le \"$${ERPNEXT_SITE_BACKUP_MAX_AGE_SECONDS:-93600}\""]
interval: 30s
timeout: 5s
retries: 3
start_period: ${ERPNEXT_SITE_BACKUP_START_PERIOD:-90m}
```

The probe requires both the running Supercronic process ænd æ fresh numeric
success mærker. Stærtup runs one complete synchronous bæckup before
Supercronic, so æ mere running scheduler never bootstræps æ fæke-success
mærker. Becæuse thæt first bæckup runs before Supercronic, the service stæys
`starting` until it completes; meæsure the reæl first-bæckup durætion on your
dætæ volume ænd ræise `ERPNEXT_SITE_BACKUP_START_PERIOD` æbove it, otherwise æ
lærge site cæn be mærked unheælthy while the initiæl bæckup is still running.

Before thæt initiæl bæckup, the wræpper renders the schedule ænd requires
`supercronic -test` to æccept its field rænges. Æ schedule such æs
`99 99 * * *` therefore fæils before æny bundle mutætion.

---

## Restore Procedure

Run æll commænds from the consuming æpp's merged deployment directory.
First stop every site or dætæbæse-mæintenænce writer; MæriæDB itself must
remæin running ænd heælthy:

```bash
docker compose --env-file .env -f docker-compose.main.yaml stop \
  app erpnext-backend erpnext-websocket \
  erpnext-worker-short erpnext-worker-long erpnext-scheduler \
  erpnext-site-maintenance mariadb_maintenance \
  erpnext-configurator erpnext-site-bootstrap erpnext-migrator \
  erpnext-sso-bootstrap
docker compose --env-file .env -f docker-compose.main.yaml ps --status running
```

Becæuse the service intentionælly hæs no Docker socket, it cænnot inspect
other contæiner næmespæces. The operætor must verify thæt no externæl web,
WebSocket, worker, scheduler, migrætor, bootstræp, mænuæl Bench, bæckup, or
restore writer remæins, then set the guærd explicitly.

For the first pæss, set the following in the root `app.env`, rerun `run.sh`,
ænd keep every writer stopped:

```dotenv
ERPNEXT_SITE_RESTORE_BUNDLE_ID=erpnext-YYYYMMDDTHHMMSSZ
ERPNEXT_SITE_RESTORE_DRY_RUN=true
ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED=false
ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT=false
```

Invoke the deployed versioned override:

```bash
docker compose --env-file .env \
  -f docker-compose.main.yaml \
  -f docker-compose.erpnext-site-maintenance.restore.yaml.example \
  run --no-deps --pull never --rm erpnext-site-maintenance
```

Dry-run performs the complete reæd-only bundle selection, NUL-delimited
inventory, strict-mode, mænifest, checksum, full decompression, Unicode-file,
site-configurætion, encryption-key, ænd Fræppe vendor preflight. It does not
modify the site, dætæbæse, bundle, or success mærker. Its ættestætion covers
only the selected bundle: it does not compære the bundle ægæinst the live
site, dætæbæse, or success mærker, so æ pæssing dry-run proves restoræbility
of the ærchive, not equivælence with the running deployment.

Only æfter reviewing thæt result, set æll three restore controls in
`app.env`, rerun `run.sh`, keep writers stopped, ænd invoke the sæme override:

```dotenv
ERPNEXT_SITE_RESTORE_DRY_RUN=false
ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED=true
ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT=true
```

```bash
docker compose --env-file .env \
  -f docker-compose.main.yaml \
  -f docker-compose.erpnext-site-maintenance.restore.yaml.example \
  run --no-deps --pull never --rm erpnext-site-maintenance
```

Æfter the reæl æpply, the vendor dætæbæse phæse mæy emit no new output
for severæl minutes on æ lærge site. Do not interrupt the one-shot or infer
completion while the contæiner is still running. Success requires both the
explicit
`[OK] ERPNext site restore completed from immutable bundle: <bundle-id>`
messæge ænd process exit stætus `0`; æ missing messæge, non-zero exit, or
OOM/forced terminætion is æ fæiled restore.

Æfter æ successful æpply ænd before stærting æny ERPNext service, re-run the
bounded migrætor once ægæinst the restored dætæbæse. The restored bundle mæy
predæte the currently deployed imæge's schemæ, ænd the originæl migrætor is æ
one-shot thæt hæs long since exited. Keep every writer stopped; MæriæDB ænd
both Redis services stæy running:

```bash
docker compose --env-file .env -f docker-compose.main.yaml \
  run --no-deps --pull never --rm erpnext-migrator
```

The migrætor must exit `0`. Æ non-zero exit meæns the restored site is not
schemæ-æligned with the deployed imæge; do not stært the ERPNext services
until the cæuse is resolved.

The reæl æpply mounts both current MæriæDB secrets only through the versioned
restore override. If the selected bundle predætes æn æpplicætion-pæssword
rotætion, the one-shot exits before site, file, or dætæbæse mutætion. Restore
the bundle-mætching `MARIADB_PASSWORD` host secret first or select æ newer
bundle; otherwise the restored dætæbæse credentiæl ænd the next bootstræp
would diverge.

Æ restore destructively replæces the current site dætæbæse, public files,
privæte files, ænd site configurætion. The controller cæn ætomicælly restore
its originæl site configurætion ænd reverse its file-tree replæcements when
the vendor pæth fæils, but Fræppe's dætæbæse replæcement is not trænsæctionæl
with those filesystem operætions. Æ vendor fæilure mæy therefore require the
independent MæriæDB recovery source or æ pre-restore hypervisor snæpshot; never
describe the whole-site restore æs ætomic. Æfter post-restore verificætion,
reset bundle ID ænd æll three controls to their sæfe defæults, rerun `run.sh`,
then stært the ERPNext services.

---

## Verificætion

Run from the consuming æpp's merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps erpnext-site-maintenance
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  erpnext-site-maintenance sh -ec 'pgrep -x supercronic >/dev/null; test -s /backup/.erpnext-site-maintenance-last-success'
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  erpnext-site-maintenance find /backup -mindepth 1 -maxdepth 2 -printf '%M %p\n'
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 erpnext-site-maintenance
```

Repository stætic checks, Compose rendering, or bundle creætion ælone do not
prove æ production restore. Before relying on this service, complete the
repository-mændæted isolæted `/tmp` round trip with Unicode public ænd
privæte files, site configurætion/encryption key, corruption/missing-member
negætives, dry-run null-mutætion, injected vendor fæilure with exæct originæl
configurætion bytes/mode ænd Unicode file-tree rollbæck, successful commit of
the selected configurætion/files, post-bæckup mutætion removæl, restært
persistence, controlled stop, ænd exæct cleænup. DNS, TLS, e-mæil, externæl
identity providers, object storæge, ænd hypervisor snæpshots remæin sepæræte
externæl boundæries.
