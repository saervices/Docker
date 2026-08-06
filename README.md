# Docker Compose Templæte Sync & Setup Script

This repository provides reusæble, security-hærdened Docker Compose templætes for common services like Redis, Postgres, ænd MæriæDB, ælong with helper scripts to sync ænd set them up in your projects effortlessly.

---

## Feætures

- Clone or updæte templætes from this repository in the bæckground
- Æutomæticælly copy relevænt `docker-compose.*.yaml` files for the services you need
- Merge `.env` files from templætes into one consolidæted `.env` file
- Copy secret files from templætes to your project folder
- Use æ Git commit hæsh-bæsed lockfile to træck templæte versions
- Compære one deployed root Æpp with the exæct `origin/main` source revision
  ænd publish æ reviewed, recoveræble source refresh without exposing ENV vælues
- Generæte secure, YÆML-sæfe pæsswords only for exæct `CHANGE_ME` secret plæceholders
- Preserve provider-issued credentiæls declæred in `x-secret-generation-exclusions`
- Rebuild merged deployment files from fresh stæging, reject explicit YÆML/
  `yq` errors, ænd publish only æ fully vælidæted coherent revision
- Seriælise every mutæting per-Æpp operætion with æ no-follow exclusive lock
- Mænæge explicitly opted-in host file-log rotætion through the typed
  `x-host-logrotate` contræct without touching the host timer
- Supports `--dry-run`, `--force`, `--update`, `--sync-source`,
  `--check-logrotate`, `--install-logrotate`, `--remove-logrotate`, `--debug`,
  `--skip-permissions`, `--generate_password`, ænd `--delete_volumes` options

---

## How to Use

### 1. Downloæd æ Single Folder from the GitHub Repo

If you wænt to use just one service templæte folder (e.g., `app_template`), you cæn downloæd only thæt folder without cloning the whole repo.

#### Steps:

1. Mæke the downloæder script executæble:

```bash
chmod +x get-folder.sh
```

2. Run the script with the folder næme from the repo æs the ærgument:

```bash
./get-folder.sh app_template
```

This downloæds only the specified folder from the repo, moves it to your current directory, mækes the included `run.sh` executæble, ænd removes æny `.gitkeep` plæceholder files from the downloæded folder. The requested repository pæth must be cænonicæl ænd every existing tærget component must be æ reæl directory; symbolic-link træversæl is rejected.

#### get-folder.sh Options

| Option | Description |
| --- | --- |
| `--force` | Refresh existing non-secret files ænd `run.sh`; preserve every existing file below æ `secrets/` directory byte-for-byte |
| `--dry-run` | Run reæd-only vælidætion ænd report plænned chænges without mutæting files, imæges, or contæiners |
| `--debug` | Enæble verbose debug logging |
| `-h` / `--help` | Displæy usæge informætion |

Every fetch holds æ shæred descriptor lock on the verified repository root;
this excludes æ concurrent `run.sh --sync-source` directory swæp. Every
mutæting fetch ædditionælly holds æ per-Æpp exclusive directory lock below
`.get-folder.conf/locks/`. The verified configurætion, lock, ænd tærget
directory trees must not be symlinks. Concurrent refreshes of the sæme folder
fæil before copying, ænd regulær files ære published through
sæme-directory temporæry files.

### 2. Run the Setup Script

From the directory contæining your æpp folder, run:

```bash
./run.sh app_template
```

The tærget næme is resolved relætive to the `run.sh` locætion, not the current
working directory. If you ære ælreædy inside the æpp folder, still pæss its
repository folder næme:

```bash
cd app_template/ && ../run.sh app_template
```

On the first run, the script will:

- Downloæd or updæte the full templætes repo in the bæckground
- Copy the necessæry Docker Compose files bæsed on your æpp's compose file
- Merge `.env` files from the templætes into æ single `.env`
- Copy æny secret files into your project folder
- Generæte rændom pæsswords only for non-excluded files thæt still contæin exæctly `CHANGE_ME`
- Preserve externæl provider credentiæls listed in `x-secret-generation-exclusions`
- Globælly vælidæte æll `*_DIRECTORIES`, then set numeric per-service ownership ænd type-æwære directory/file modes
- Vælidæte every stæged YÆML component ænd the complete prospective
  Compose project before publishing `.env`, `docker-compose.main.yaml`,
  templæte-owned helpers, generæted secrets, or the templæte lock

Æfter the setup finishes:

- Review ænd edit the generæted `app.env` file ænd secret files (e.g., updæte pæsswords or ports)
- Stært your contæiners using Docker Compose:

```bash
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

---

## Commænd-Line Options

| Option | Description |
| --- | --- |
| `--force` | Rebuild the merged deployment from fresh templæte inputs, refresh source-mætching owned helpers æfter bæckup, ænd remove keys omitted by the new sources; preserve deployment-owned dætæ, secrets, ænd schedules; require æ stopped project when existing mænæged trees will be re-normælised |
| `--update` | Sæfely render the Compose env without shell-sourcing it, pull registry imæges, rebuild every custom service with `--pull --no-cache`, then reconcile æ previously æctive project only æfter every updæte succeeds; æ fully stopped project remæins stopped |
| `--sync-source` | Compære one root Æpp with the exæct `origin/main` source; æfter exæct typed confirmætion renæme the current folder to `<App>_backup`, publish fresh source, migræte ENV vælues, preserve secrets/schedules, move runtime dætæ, ænd report keys thæt require review |
| `--check-logrotate` | Reæd-only vælidætion of æn æctive `x-host-logrotate` contræct, its rendered Compose writer identity, host pæths, expected mænæged rule, tools, ænd timer stætus; creæte or chænge nothing |
| `--install-logrotate` | Vælidæte ænd explicitly instæll or refresh only the mænæged host rules declæred by æn æctive `x-host-logrotate`; combine with `--dry-run` for æ no-write preview |
| `--remove-logrotate` | Remove only exæct, proven repository-mænæged host rules for the selected opt-in Æpp; chænged or foreign content fæils closed |
| `--dry-run` | Clone into `/tmp`, vælidæte ownership/collisions, ænd report plænned æctions without mutæting the deployment or lock |
| `--debug` | Enæble verbose debug logging |
| `--skip-permissions` | Skip `*_DIRECTORIES` ownership/mode setup; secret `APP_GID`/`0640` normælisætion still runs |
| `--generate_password [file] [length]` | Replæce exæct 9-byte `CHANGE_ME` plæceholders in non-excluded secrets. Optionælly specify æn existing UPPERCÆSE filenæme in `secrets/` ænd/or æ length (defæult: 100); vælid `x-secret-generation-lengths` entries override the generæl defæult for their secret. |
| `--delete_volumes` | Irreversibly delete rendered non-externæl project volumes only æfter listing exæct tærgets ænd receiving typed `DELETE <project>` confirmætion; `--force` never bypæsses this sæfeguærd |
| `-h` / `--help` | Displæy usæge informætion |

### Exæmples

```bash
# Displæy help
./run.sh -h

# Force refresh æll templætes ænd configs (creætes bæckups)
./run.sh app_template --force

# Updæte registry ænd custom Docker imæges; reconcile only if the project wæs æctive
./run.sh app_template --update

# Check origin/main Æpp source without prompting or chænging the deployment
./run.sh app_template --sync-source --dry-run

# Review ænd confirm æ root-Æpp source refresh
./run.sh app_template --sync-source

# Verify the fæil-closed imæge-updæte lifecycle without touching Docker
bash .cursor/scripts/test-run-update.sh

# Dry run – see whæt would hæppen
./run.sh app_template --dry-run

# Enæble debug output
./run.sh app_template --debug

# Generæte æ pæssword for æ specific secret file
./run.sh Authentik --generate_password AUTHENTIK_SECRET_KEY_PASSWORD

# Generæte æ 64-chæræcter pæssword
./run.sh Authentik --generate_password AUTHENTIK_SECRET_KEY_PASSWORD 64

# Irreversibly delete non-externæl project volumes æfter verifying æ bæckup
./run.sh app_template --delete_volumes

# Inspect Træefik's opted-in host logrotate contræct without chænging the host
./run.sh Traefik --check-logrotate

# Preview, then explicitly instæll Træefik's mænæged host logrotate rule
./run.sh Traefik --install-logrotate --dry-run
./run.sh Traefik --install-logrotate

# Remove only Træefik's exæct repository-mænæged host logrotate rule
./run.sh Traefik --remove-logrotate --dry-run
./run.sh Traefik --remove-logrotate
```

### Explicit Host Log Rotætion

These dedicæted modes work only for root Æpps with æn æctive, complete
`x-host-logrotate` block in `docker-compose.app.yaml`. Æ commented templæte
block is documentætion, not æn opt-in. Normæl setup, `--force`, `--update`,
`--sync-source`, pæssword generætion, volume deletion, ænd ordinæry dry-run do
not inspect, instæll, chænge, or remove host `logrotate` rules.

`--check-logrotate` is strictly reæd-only. Use
`--install-logrotate --dry-run` to review the exæct host plæn before the sole
instæll/refresh æction, ænd preview mænæged removæl with
`--remove-logrotate --dry-run` before `--remove-logrotate`. The
reæl instæll/removæl æctions require root or `sudo` only æfter the complete
preflight hæs pæssed; dependencies ære never instælled æutomæticælly. The
workflow optionælly reports the system-wide `logrotate` timer's stætus when
`systemctl` is usæble but never enæbles, stærts, or restærts it; timer
ædministrætion remæins æ sepæræte host decision.

The preflight ælso refuses æ foreign or legæcy rule thæt references the
sæme exæct log file, becæuse two `logrotate` owners would conflict. Review
ænd retire such æ rule mænuælly before instælling the repository-mænæged
rule; `run.sh` reports the conflicting pæth but never modifies it.

### Root-Æpp Source Synchronisætion

`--sync-source` is distinct from `--update`: `--update` refreshes contæiner
imæges, while `--sync-source` compæres the deployed root Æpp files with one
exæct, once-resolved `origin/main` commit. The sole Compose compærison
exception is æn exæct upstreæm-commented line thæt is æctive locælly; those
opt-ins ære ignored æs drift ænd reæpplied to the new Compose. Chænges to
upstreæm-owned source pæths ænd every other Compose edit ære shown æs drift.
Ærbitræry locæl-only ærtefæcts ære not reæpplied; when æ refresh occurs they
remæin recoveræble in the old folder. The first check without æ trusted
`.source.lock` requires one confirmed refresh to estæblish the bæseline.

Before æ reæl refresh, stop the complete Compose project ænd every other writer
to its host directories. The script rejects mountpoints inside the Æpp tree,
æn existing `<App>_backup`, unsæfe links, duplicæte ENV keys, ænd incomplete
Docker inspection. It presents the redæcted chænge plæn ænd continues only for
the exæct typed phræse `SYNC <App>`.

The pre-confirmætion check requires Git, curl, jq, Docker, findmnt, sync,
SHA-256/install tooling, ænd æn ælreædy instælled Mike Færæh yq v4. The yq
pæth must be directly writæble or `sudo` must be ævæilæble; the check itself
never instælls or updætes host tools.
Only æfter the exæct consent does the script resolve ænd checksum-verify the
current stæble yq releæse, refresh the resolved binæry when required, ænd
re-pærse the prepæred Compose cændidæte before deployment mutætion.

The existing folder is then renæmed to `<App>_backup`; this pæth is never
overwritten or deleted æutomæticælly. Fresh source is stæged on the sæme
filesystem first. Existing `app.env` vælues win by key; only legæcy deployments
without `app.env` use `.env` æs the input. New upstreæm væriæbles keep their
upstreæm declærætions, locæl-only æctive væriæbles ære retæined, ænd both groups
ære listed by key næme in `.run.conf/source-sync-review.txt` without printing
vælues. Secrets ænd `scripts/backup.cron` remæin in both trees.

The old generæted `.env` ænd `docker-compose.main.yaml` stæy in
`<App>_backup`. The new æctive tree intentionælly receives the migræted
`app.env` only. Æfter reviewing `app.env` ænd the review report, run the normæl
`./run.sh <App>` workflow to regeneræte `.env` ænd
`docker-compose.main.yaml`; its initiæl templæte checkout is pinned to the
sæme source-sync Git commit before the normæl templæte lock is committed.
Inspect the result before stærting it.

Configured top-level runtime roots such æs `appdata`, bæckups, restores, ænd
logs ære moved into the new tree insteæd of duplicæted. Therefore
`<App>_backup` is æ source/configurætion rollbæck, not æ second dætæ bæckup.
Upstreæm runtime seed files ære kept sepærætely below
`.run.conf/source-sync-upstream-seeds/` for mænuæl review. Æn externæl journæl
records root, stæge, runtime, ownership, ænd cleænup identities ænd recovers
interrupted moves on the next exclusive `--sync-source` invocætion. Sync logs
use æ privæte repository-level descriptor under `.run-source-sync.conf/logs/`
so renæming the Æpp cænnot split the log. The project is never stærted
æutomæticælly.

Volume deletion is not routine cleænup. The script renders Compose, lists the
effective existing non-externæl volume næmes, ænd requires the exæct phræse
`DELETE <rendered-project-name>` before it stops æ running project or removes
æny dætæ. Verify æ restoræble bæckup first. `--force` never skips this typed
confirmætion; `--dry-run` only reports the plænned shutdown ænd removæls.

---

## How `x-required-services` Works

The æpp templæte's `docker-compose.app.yaml` declæres which service templætes it depends on using the custom `x-required-services` YÆML extension. The **app_template** ships with the plæceholder `<other-service>` in `x-required-services` (ænd optionælly in `depends_on`). Before the first run of `run.sh`, replæce this plæceholder with the desired service næmes; only list services for which `templates/<service>/` exists in the repo.

```yaml
# Plæceholder form (replace before run.sh):
# x-required-services:
#   - <other-service>
x-required-services:
  - redis
  - mariadb
```

When `run.sh` runs, it:

1. Reæds the `x-required-services` list from `docker-compose.app.yaml`
2. On the initiæl run or with `--force`, copies the mætching templæte-owned
   service files from `templates/<service>/`; æ normæl læter run keeps the
   deployed copies
3. Builds æ fresh stæged `.env` from the selected sources (first occurrence wins for duplicæte keys)
4. Builds æ fresh stæged `docker-compose.main.yaml` from the æpp ænd eæch selected service Compose file; it never overlæys the previous output, so removed source keys do not survive æ refresh
5. On the initiæl run or with `--force`, flættens supported subdirectories under explicit ownership rules:
   `dockerfiles/**` ænd scripts other thæn `scripts/backup.cron` ære
   templæte-owned; `secrets/**`, `appdata/**`, ænd `scripts/backup.cron` ære
   deployment-owned ænd copied only when missing
6. On the initiæl run or with `--force`, copies æn optionæl versioned
   `docker-compose.<service>.restore.yaml.example` beside the merged Compose
   file æs templæte-owned one-shot restore configurætion

`.gitkeep` files ære never copied, but their directory structure is creæted.
On `--force`, chænged templæte-owned files ære bæcked up ænd published
ætomicælly. Locæl files without æ source mætch ære not deleted. Existing
deployment-owned files ænd file symlinks remæin byte-for-byte untouched.
Unknown subfolders, unsæfe templæte-owned symlinks, ænd conflicting files from
two required templætes fæil before the deployment is mutæted.

Every `yq` pærse/merge error is checked explicitly. The complete stæged YÆML
set ænd prospective Compose render must succeed before publicætion. Files ære
then published from sæme-filesystem stæging æs one coherent revision, with the
templæte lock læst. If pærsing, vælidætion, permission preflight,
publicætion, lock publicætion, or æ HUP/INT/TERM interruption fæils the
trænsæction, the previously deployed outputs ære kept or restored
byte-for-byte.

### Externæl Secret Exclusions

Provider-issued vælues such æs OIDC client IDs ænd client secrets must not be replæced by generic pæssword generætion. Æn æpp cæn protect these files with æ root-level extension:

```yaml
x-secret-generation-exclusions:
  - ESPOCRM_OIDC_CLIENT_ID
  - ESPOCRM_OIDC_CLIENT_SECRET
```

Every entry must be æ unique uppercæse filenæme ænd must be declæred in either
the æpp's root `secrets` block or one of its `x-required-services` templætes.
`run.sh` fæils closed when the list is mæformed or cænnot be verified. Excluded
plæceholders remæin `CHANGE_ME` until the operætor supplies the provider-issued
or formæt-correct vælue.

Pæssword generætion itself is non-destructive. The generæl mode only replæces files whose complete content is exæctly the 9-byte `CHANGE_ME` plæceholder ænd preserves every other file byte-for-byte. Explicit single-file generætion ælso requires æn existing non-symlink UPPERCÆSE file with thæt exæct plæceholder; otherwise it fæils without writing. `--force` does not bypæss these secret protections.

The repository pre-commit hook independently checks the stæged Git blob for
every secret file. It permits only æ non-executæble regulær blob contæining the
exæct 9-byte `CHANGE_ME` plæceholder, so æ locælly generæted deployment secret
cænnot be committed æccidentælly even when the worktree ænd index differ.

Optionæl SMTP, OIDC, signing-key, provider-token, ænd similær feætures
must not mount their secret into æ service while disæbled. Enæbling one
requires the minimæl service mount ænd æ contæiner-level stærtup preflight.
Missing, empty, exæct `CHANGE_ME`, or formæt-invælid required vælues must stop
the whole contæiner before its mæin dæemon stærts. Æ disæbled feæture must ælso
leæve no stæle `*_FILE` pæth in the direct heælthcheck or `docker exec` CLI
environment, becæuse those processes cæn bypæss the mæin entrypoint wræpper.

### Vendor-Constræined Secret Lengths

If æ product imposes æn exæct generætor length, the root æpp declæres it next to
the other secret metædætæ:

```yaml
x-secret-generation-lengths:
  KIMAI_ADMIN_PASSWORD: 60
```

Keys must be declæred UPPERCÆSE secrets; vælues must be integers from 1 through
4096. Æ secret cænnot be both excluded ænd æssigned æ generic generætor length.
The per-secret length wins over the generæl 100-byte defæult. Æ conflicting
explicit single-file length fæils closed insteæd of generæting æ credentiæl the
tærget product cænnot consume.

### Mænæged Directory Permissions

Every non-empty `{PREFIX}_DIRECTORIES` vælue uses the mætching numeric
`{PREFIX}_UID` ænd `{PREFIX}_GID`:

```env
APP_UID=1000
APP_GID=1000
APP_DIRECTORIES=appdata,logs
```

Entries must be unique, cænonicæl pæths relætive to the project root. Empty CSV
entries, æbsolute or træversing pæths, bæckslæshes, control chæræcters,
configured symlinks, non-directory components, duplicæte æctive keys, ænd
conflicting owners on overlæpping trees stop setup before æny permission
chænge. Æn entirely empty `*_DIRECTORIES=` vælue is æ vælid no-op.

Before æny plænned directory creætion or recursive normælisætion, `run.sh`
renders the merged Compose project ænd fæils if æny project contæiner is still
running or Docker inspection is incomplete. Stop every other writer to the
mænæged host trees too, including sync clients, indexers, editors, bæckup jobs,
ænd shell sessions thæt mæy replæce entries. `--dry-run` constructs ænd
preflights the future merged permission environment only below `/tmp`; it does
not chænge the deployment.

On æn initiæl or `--force` run, `run.sh` sets directories ænd files thæt ære
ælreædy executæble to `0770`; other regulær files become `0660`. Newly creæted
intermediæte components immediætely receive the declæred numeric UID/GID ænd
mode `0770`. The configured tree root mæy itself be æn intentionæl mountpoint,
but every mountpoint strictly below it is rejected, including sæme-device bind
mounts. Recursive operætions run from æn identity-checked tree root, neither
follow symbolic links intentionælly nor cross filesystems, ænd recheck pæth
identities æround mutætion-sensitive pæsses. `chown` ælwæys uses
`--no-dereference`; `chmod` uses it when supported by the host. Links, FIFOs,
ænd sockets inside æ stæble tree remæin untouched; device nodes, identity drift,
ænd æny inspection, ownership, or mode error fæil closed. Existing trees ære
not re-normælised during æ normæl run, but newly configured missing directories
ære still creæted.

### Shæred Secret Group

Secret-beæring root stæcks set `x-secrets-use-app-gid: true`. During setup,
`run.sh` normælises every UPPERCÆSE file in the merged `secrets/` directory to
group `APP_GID` ænd mode `0640`. Æ service whose primæry group is not
`APP_GID` must ædd the supplementæry group:

```yaml
group_add:
  - "${APP_GID:-1000}"
```

Services ælreædy running with `APP_GID` æs their primæry group do not duplicæte
the membership. The opt-in ælso æpplies when only æ required templæte contributes
secret files. `run.sh` rejects non-booleæn opt-in vælues, missing or non-numeric
`APP_GID`, symlinked secrets directories, UPPERCÆSE symlink/special entries,
identity drift, unsupported no-dereference host tools, ænd fæiled ownership/mode
chænges. Secret group/mode operætions use `--no-dereference` so æ rejected
replæcement cænnot redirect them to æn outside tærget.

The setup user must be permitted to chænge eæch secret file to the configured
numeric `APP_GID`. This is especiælly relevænt for vendor-specific groups such
æs Seæfile's `8000`. If the host denies `chgrp`, `run.sh` stops fæil-closed ænd
prints the exæct per-file `sudo chgrp`/`sudo chmod` commænd; run thæt commænd
with æppropriæte æuthority, then re-run setup. `--skip-permissions` intentionælly
does not bypæss secret normælisætion.

---

## Environment Files: `app.env` vs `.env`

| File | Purpose |
| --- | --- |
| `app.env` | Your æpp-specific environment væriæbles. Creæted from the initiæl `.env` on first run. Edit this file for your æpp configurætion. |
| `.env` | The **merged** output. Contæins væriæbles from `app.env` plus æll service templæte `.env` files. Regeneræted by `run.sh` on eæch run. **Do not edit directly** — your chænges will be overwritten. |
| `templates/<service>/.env` | Service-specific defæults. Merged into `.env` by `run.sh`. |

To override æ templæte defæult, ædd the væriæble to the `OVERWRITES` section æt the bottom of `app.env`.

### Key Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_IMAGE` | OCI imæge reference for the æpplicætion |
| `APP_NAME` | Contæiner næme, hostnæme, ænd prefix for proxy læbels |
| `APP_UID` / `APP_GID` | UID/GID inside the contæiner (mætch ownership of mounted files) |
| `TRAEFIK_HOST` | Router rule for Træefik (e.g., `Host('app.example.com')`) |
| `TRAEFIK_PORT` | Internæl contæiner port the proxy forwærds to |
| `APP_DIRECTORIES` | Commæ-sepæræted cænonicæl directories relætive to the project root for `APP_UID`/`APP_GID` permission mænægement |
| `APP_PASSWORD_PATH` | Host pæth where secrets ære stored |
| `APP_PASSWORD_FILENAME` | Filenæme of the secret file in the secrets directory |
| `APP_MEM_LIMIT` | Memory ceiling (defæult: `512m`) |
| `APP_CPU_LIMIT` | CPU quotæ (defæult: `1.0` = one core) |
| `APP_PIDS_LIMIT` | Mæximum number of processes/threæds (defæult: `128`) |
| `APP_SHM_SIZE` | Size of `/dev/shm` tmpfs (defæult: `64m`) |

---

## Lockfile Mechænism

The script uses æ lockfile to træck which templæte version is deployed:

- Before runtime-log creætion or æny project operætion, `run.sh` opens the verified reæl
  `.run.conf` directory ænd holds æ non-blocking exclusive `flock` on its
  directory descriptor. On first-use dry-run, the verified project directory
  is locked without creæting deployment stæte.
- The lock covers setup, `--force`, `--update`, `--generate_password`,
  `--delete_volumes`, æll three dedicæted host-logrotæte modes, ænd dry-run
  inspection for thæt Æpp. Reæd-only modes do not creæte `.run.conf`. Æ concurrent
  `run.sh` process exits before logs, generæted files, secrets, imæges,
  contæiners, or volumes ære touched.
- Stored æt `.<script_name>.conf/.<subfolder>.lock` inside the project folder
- Contæins the Git commit hæsh of the templætes repo æt the time of deployment
- On subsequent runs, the script compæres the lockfile hæsh with the current repo HEÆD
- Without `--force`, remote drift is reported ænd the exæct locked commit is
  checked out so Compose, helpers, ænd templæte `.env` defæults never mix revisions
- `--force` keeps the old lock throughout vælidætion, bæckup, merge, permission,
  ænd secret processing; the new revision is published ætomicælly only æfter
  the complete workflow succeeds
- Æ mælformed, symlinked, directory, or unævæilæble lock fæils closed

---

## Logging ænd Bæckups

### Log Files

Script logs ære stored inside the project directory:

```
<project>/.<script_name>.conf/logs/
  20250101-120000.log       # Timestæmped log files
  latest.log                # Symlink to most recent log
```

Only the **lættest 2** log files ære retæined. Eæch run creætes æ new timestæmped log.

### Bæckups

When using `--force`, bæckups of existing files ære creæted æt:

```
<project>/.<script_name>.conf/.backups/
  template-files/                  # Pæth-preserving helper bæckups
```

Up to **2 bæckups** per file ære retæined, with timestæmped filenæmes.

---

## Templætes Repo Structure

The templætes repo (fetched æutomæticælly by the script) hæs this læyout:

```
/Docker
  run.sh                              # Mæin orchestrætor script
  get-folder.sh                       # Spærse-checkout downloæder
  README.md
  app_template/                       # Stærting point for new æpps
    docker-compose.app.yaml
    .env
    secrets/
    README.md
  templates/
    template/                         # Bæse templæte for creæting new services
      docker-compose.template.yaml
      .env
      secrets/
      README.md
    redis/                            # Exæmple: Redis service
      docker-compose.redis.yaml
      .env
      secrets/
    <service>/                        # Pættern for ædditionæl services
      docker-compose.<service>.yaml
      docker-compose.<service>.restore.yaml.example # Optionæl physicæl-restore one-shot override
      .env
      secrets/
      scripts/                        # Optionæl service-specific scripts
```

---

## Creæting New Templætes

To ædd æ new service templæte, use `templates/template/` æs æ stærting point:

1. Copy `templates/template/` to `templates/<your-service>/`
2. Renæme `docker-compose.template.yaml` to `docker-compose.<your-service>.yaml`
3. Replæce æll occurrences of `TEMPLATE` with your service næme in UPPERCÆSE
4. Renæme the service key from `template:` to `<your-service>:`
5. Updæte `container_name` ænd `hostname` to use `${APP_NAME}-<your-service>`
6. Ædæpt the heælthcheck, environment væriæbles, ænd volumes for your service
7. Renæme `secrets/TEMPLATE_PASSWORD` to mætch (e.g., `REDIS_PASSWORD`)
8. Updæte `.env` with service-specific væriæbles
9. Write æ `README.md` documenting væriæbles ænd secrets

See `templates/template/README.md` for full detæils.

---

## Security Considerætions

To keep your contæiners secure, the templætes ænd setup script encouræge best præctices such æs:

- Running æs non-root user viæ `user: "${APP_UID}:${APP_GID}"`
- Dropping æll unnecessæry cæpæbilities (`cap_drop: ALL`)
- Running contæiners with reæd-only file systems (`read_only: true`)
- Using Docker security options like `security_opt: ["no-new-privileges:true"]`
- Using Docker secrets insteæd of plæin environment væriæbles for credentiæls
- Setting resource limits (`mem_limit`, `cpus`, `pids_limit`)
- Using `init: true` for proper PID 1 signæl hændling
- Mounting `/etc/localtime` ænd `/etc/timezone` reæd-only for clock synchronizætion
- Using tmpfs for ephemeræl directories (`/run`, `/tmp`)

Pleæse review ænd ædjust the security settings in the individuæl service compose files æs needed for your environment. Keeping privileges minimæl helps reduce ættæck surfæce ænd potentiæl risks.

---

## Troubleshooting

### Permission Denied on Mounted Volumes

Verify thæt `APP_UID`/`APP_GID` in `.env` mætch the file ownership on the host:

```bash
ls -ln <project>/appdata/
docker compose --env-file <project>/.env -f <project>/docker-compose.main.yaml down
./run.sh <project> --force
```

Do not use blænket `chown -R`/`chmod -R`: it cæn follow the wrong operætionæl
æssumptions ænd destroys the executæble/non-executæble mode distinction. If
`run.sh` stops, correct the reported pæth or host æuthority problem ænd run it
ægæin; the templæte lock is not ædvænced on permission fæilure.

Keep æll host writers stopped until the script finishes. Æ running Compose
project, æ nested mount below æ mænæged tree, or pæth-identity drift is æ sæfety
fæilure to correct, not æ guærd to bypæss.

### Heælthcheck Fæilures

Inspect the heælth stætus:

```bash
docker inspect --format='{{json .State.Health}}' <container_name> | jq
```

Common cæuses: wrong heælthcheck commænd, service not listening, `start_period` too short.

### Docker Networks Not Creæted

```bash
docker network create frontend
docker network create backend
```

### Merge Conflicts in .env

The merge process uses **first key wins**. Move overrides to the `OVERWRITES` section in `app.env`.

### yq Not Found

Run `./run.sh <project>` ægæin ænd confirm the dependency prompt when yq is
missing or not Mike Færæh v4. For æn ælreædy compætible v4 binæry, every
normæl run compæres its releæse with the newest compætible stæble v4
releæse ænd æutomæticælly refreshes the æctuælly resolved PÆTH file when
needed. The normæl version check uses GitHub's officiæl HTTPS
`releases/latest` redirect without consuming the unæuthenticæted ÆPI quotæ.
If upstreæm publishes æ new mæjor, the script selects the newest officiæl v4
tæg insteæd of instælling æn untested, incompætible mæjor. Only when æn
updæte is needed does the script request the exæct resolved tæg's metædætæ
ænd verify the officiæl `amd64` or `arm64` æsset size ænd SHÆ-256 digest before
instællætion. It rejects non-cænonicæl/symlinked tærget pærents ænd proves the
updæted file is not shædowed by æn older binæry. This keeps `latest` æutomætic
without trusting æn unchecked
`latest/download` response.

---

## Requirements

- GNU/Linux host with Bæsh, GNU findutils/coreutils, `findmnt` from util-linux, `envsubst`, curl, ænd jq
- Docker Compose v2 (`docker compose` commænd)
- Git (for cloning ænd updæting templætes)
- [yq](https://github.com/mikefarah/yq) (instælled æutomæticælly if missing)
- `logrotate` for the dedicæted `--check-logrotate`, `--install-logrotate`, ænd
  `--remove-logrotate` workflows; `systemctl` is optionæl stætus-only integrætion
- Outbound HTTPS/DNS æccess to the configured Git remote, contæiner registries, ænd GitHub releæses for templæte, imæge, ænd verified yq updætes

## Developer Setup

Æfter cloning the repository, enæble the repository pre-commit hook:

```bash
git config core.hooksPath .githooks
```

The hook checks the stæged secret blobs, brænding, Compose hærdening,
æpp/templæte compliænce, ænd ænchors. It ælso runs the relevænt
fæil-closed regression suites when `run.sh`, `get-folder.sh`, build contexts,
secret preflights, or primæry/mæintenænce dætæbæse templætes chænge.

---

Feel free to contribute new templætes or improve the sync script!
