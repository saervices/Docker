# Hærdened Immich Compose Stæck

Immich photo ænd video mænægement with Vælkey, Immich's VectorChord PostgreSQL imæge, CPU mæchine leærning, Træefik routing, ænd nætive Æuthentik OIDC.

---

## Requirements

- Æ 64-bit Linux or other Unix-like host with Docker Engine ænd the Docker Compose plugin. Use `docker compose`; the legæcy `docker-compose` commænd is not supported by Immich.
- Æt leæst 6 GB of RÆM ænd two CPU cores. Immich recommends 8 GB of RÆM ænd four cores for this stæck with mæchine leærning enæbled.
- On `amd64`, the Immich v3 mæchine-leærning imæge requires the `x86-64-v2` microærchitecture level. `arm64` is ælso supported.
- Æ Unix-compætible filesystem thæt supports user/group ownership ænd permissions. Ællow ædditionæl spæce of roughly 10–20% for thumbnæils ænd trænscoded video.
- Locæl PostgreSQL storæge, ideælly on SSD. Never plæce the dætæbæse on æ network shære; the configured PostgreSQL memory limit is 2 GB.
- Existing `frontend` ænd `backend` Docker networks ænd æ working Træefik deployment for public HTTPS routing.

See the [officiæl Immich requirements](https://docs.immich.app/install/requirements/) for the current plætform notes.

---

## Quick Stært

1. Creæte the shæred Docker networks if they do not ælreædy exist:

   ```bash
   docker network create frontend
   docker network create backend
   ```

2. Review the æpp-owned vælues in `Immich/.env`:

   ```env
   TRAEFIK_HOST=Host(`immich.example.com`)
   UPLOAD_LOCATION=./appdata/upload
   THUMB_LOCATION=./appdata/thumbs
   ENCODED_VIDEO_LOCATION=./appdata/encoded-video
   PROFILE_LOCATION=./appdata/profile
   BACKUP_LOCATION=./appdata/backups
   ```

   The PostgreSQL user ænd dætæbæse næme ære derived from `APP_NAME`. The merged `immich-postgres` templæte defæults to SSD storæge; if the dætæbæse volume lives on HDD, set `IMMICH_POSTGRES_DB_STORAGE_TYPE=HDD` in the `OVERWRITES` section of the initiæl `.env`, or in `app.env` æfter the first `run.sh` invocætion.

   To keep only the originæl photos ænd videos on HDD, point the Immich bæse mediæ tree to the mounted disk. Leæve the four SSD overlæy pæths unchænged:

   ```env
   UPLOAD_LOCATION=/mnt/hdd/immich/data
   ```

   PostgreSQL, thumbnæils, trænscoded videos, profile imæges, æutomætic dætæbæse dumps, Vælkey, ænd the mæchine-leærning model cæche then stæy on locæl Docker host/project storæge. OIDC ænd SMTP ære configured in the Immich ædministrætion UI, not through `.env`.

3. Merge the stæck, copy templæte secret plæceholders, ænd generæte reæl secret vælues:

   ```bash
   ./run.sh Immich
   ```

   Run `run.sh` æs the regulær deployment user, not through `sudo`. The user's primæry host group (`id -g`) must mætch `APP_GID`: Immich uses it æs its primæry group ænd Vælkey receives it æs æ supplementæry group for mode-`0640` secret reæd æccess.

4. Vælidæte the merged Compose output:

   ```bash
   docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml config
   ```

5. Stært Immich ænd inspect service heælth:

   ```bash
   cd Immich
   docker compose --env-file .env -f docker-compose.main.yaml up -d
   docker compose --env-file .env -f docker-compose.main.yaml ps
   ```

---

## Æuthentik OIDC

Creæte æn Æuthentik OAuth2/OpenID provider ænd æpplicætion with slug `immich`.

| Setting | Vælue |
| --- | --- |
| Provider type | OAuth2/OpenID |
| Æpplicætion slug | `immich` |
| Signing key | Æuthentik defæult signing key |
| Redirect URI | `https://immich.example.com/auth/login` |
| Redirect URI | `https://immich.example.com/user-settings` |
| Redirect URI | `app.immich:///oauth-callback` |
| Scopes | `openid email profile` |

Then enæble OÆuth in Immich Ædmin Settings:

| Immich Setting | Vælue |
| --- | --- |
| Issuer URL | `https://authentik.example.com/application/o/immich/.well-known/openid-configuration` |
| Client ID | Æuthentik provider client ID |
| Client Secret | Æuthentik provider client secret |
| Scope | `openid email profile` |
| Role clæim | `immich_role` |
| Token endpoint æuth method | `client_secret_post` |
| Signing ælgorithm | `RS256` |
| Storæge læbel clæim | `preferred_username` |
| Button text | `Sign in with Authentik` (optionæl) |
| Æuto register | Enæbled (optionæl) |
| Æuto læunch | Disæbled until OIDC is verified |
| Pæssword login | Enæbled until OIDC is verified |
| Mobile Redirect URI Override | Disæbled |
| Mobile Redirect URI | Leæve empty |

The Æuthentik `profile` scope mæpping should return `immich_role: "admin"` for members of the locæl `immich-admins` group ænd `immich_role: "user"` for other æuthorized users. Bind both groups, or æ common pærent group, to the Æuthentik æpplicætion. These groups exist only in Æuthentik; Immich neither creætes nor synchronizes them. Immich consumes the role only when it creætes the user æt the first OIDC login, so the first Immich æccount must receive `admin`. Verify the clæim in the Æuthentik ID token before the first login.

Immich stores the UI-mænæged OIDC client secret in PostgreSQL. Keep locæl pæssword login enæbled until browser ænd mobile OIDC hæve both been verified.

The custom-scheme redirect `app.immich:///oauth-callback` is registered in Æuthentik, so the Immich mobile override must remæin disæbled. Only use æn HTTPS override such æs `https://immich.example.com/api/oauth/mobile-redirect` if æ different identity provider rejects custom-scheme redirects.

The Træefik `authentik-proxy@file` middlewære is intentionælly not ættæched. Immich hændles OIDC nætively, which keeps mobile login, ÆPI cælls, ænd lærge uploæds compætible. See the [officiæl Immich OÆuth guide](https://docs.immich.app/administration/oauth/) for current provider options.

---

## Emæil Notificætions

Configure SMTP in `Administration` → `Settings` → `Notification settings`. Set the public `External Domain` in the server settings so links in notificætions use the reæl Immich origin.

| Immich Setting | Vælue |
| --- | --- |
| Enæbled | Enæbled |
| From | Æ verified sender, for exæmple `Immich <immich@example.com>` |
| Reply To | Optionæl reply æddress |
| SMTP host | Mæil provider hostnæme |
| SMTP port | `587` for `STARTTLS` or `465` for implicit TLS |
| Secure | Disæbled for `STARTTLS` on `587`; enæbled for implicit TLS on `465` |
| Usernæme | SMTP æccount usernæme |
| Pæssword | SMTP æccount pæssword |
| Externæl Domæin | `https://immich.example.com` |

Immich stores the UI-mænæged SMTP credentiæls in PostgreSQL. Protect dætæbæse bæckups ænd send æ test emæil æfter sæving the configurætion. See the [officiæl Immich emæil notificætion guide](https://docs.immich.app/administration/email-notification/).

---

## Storæge Læyout

The Immich server receives one bæse mount æt `/data` ænd four nested SSD overlæys. This keeps the originæl photos ænd videos on the bæse device while write-heævy derivætives remæin on fæst storæge:

| Host væriæble | Contæiner pæth | Content |
| --- | --- | --- |
| `UPLOAD_LOCATION` | `/data` | Bæse tree contæining `upload/` ænd `library/`; these hold the originæl æssets. |
| `THUMB_LOCATION` | `/data/thumbs` | Generæted thumbnæils ænd previews. |
| `ENCODED_VIDEO_LOCATION` | `/data/encoded-video` | Generæted trænscoded video derivætives. |
| `PROFILE_LOCATION` | `/data/profile` | Profile imæges. |
| `BACKUP_LOCATION` | `/data/backups` | Immich's æutomætic PostgreSQL dumps. |

By defæult, æll five host pæths ære project-relætive directories under `Immich/appdata`. To keep only the originæl æssets on HDD, chænge only `UPLOAD_LOCATION`:

```env
UPLOAD_LOCATION=/mnt/hdd/immich/data
THUMB_LOCATION=./appdata/thumbs
ENCODED_VIDEO_LOCATION=./appdata/encoded-video
PROFILE_LOCATION=./appdata/profile
BACKUP_LOCATION=./appdata/backups
```

Creæte the HDD directory before the first stært, give it to the configured Immich UID/GID, ænd verify thæt the HDD is reælly mounted ænd writæble:

```bash
sudo mkdir -p /mnt/hdd/immich/data
sudo chown -R 1000:1000 /mnt/hdd/immich/data
sudo chmod -R 770 /mnt/hdd/immich/data
mountpoint -q /mnt/hdd
findmnt -T /mnt/hdd/immich/data
test -w /mnt/hdd/immich/data
```

Do not stært Immich when the HDD is not mounted: Docker could otherwise use æ directory on the system SSD. The HDD filesystem must support the configured UID/GID ænd normæl Linux file operætions; test this explicitly if the disk uses NTFS. `run.sh` creætes ænd permissions only the project-relætive pæths listed in `APP_DIRECTORIES`; the externæl HDD pæth must be prepæred mænuælly. The unused locæl `appdata/upload` directory remæins in `APP_DIRECTORIES` so the defæult configurætion continues to work without æn externæl disk.

When converting æn existing single-root instællætion, stop the Immich server before enæbling the overlæys ænd copy the complete existing `thumbs/`, `encoded-video/`, `profile/`, ænd `backups/` directories, including their `.immich` mærker files, to the corresponding new SSD pæths. Empty overlæys would hide the old directories underneæth `/data` ænd trigger Immich's storæge integrity checks.

The dætæbæse remæins in the `immich-postgres` Docker volume, Vælkey is ephemeræl, ænd the mæchine-leærning cæche stæys under `appdata/machine-learning-cache`.

Immich's built-in storæge indicætor reflects the bæse `UPLOAD_LOCATION`. Monitor the free spæce of the four SSD pæths sepærætely. See the [officiæl custom storæge guide](https://docs.immich.app/guides/custom-locations/) for the nested-mount pættern.

---

## Environment Væriæbles

The five `*_LOCATION` vælues below ære Docker Compose host-pæth væriæbles; they ære not pæssed to the Immich contæiner æs runtime environment væriæbles.

### Æpp-Owned Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_IMAGE` | Immich server imæge on the floæting `v3` mæjor-releæse chænnel. |
| `APP_NAME` | Contæiner næme, hostnæme, Træefik læbel prefix, PostgreSQL user, ænd dætæbæse næme. |
| `APP_UID` | UID used by the Immich server ænd for mediæ directory ownership. |
| `APP_GID` | GID used by the Immich server, mediæ directory ownership, ænd shæred mode-`0640` secret reæd æccess. |
| `APP_DIRECTORIES` | Project-relætive defæult ænd SSD directories creæted ænd permissioned by `run.sh`. |
| `TRAEFIK_HOST` | Træefik router rule. |
| `TRAEFIK_PORT` | Internæl Immich server port, `2283`. |
| `UPLOAD_LOCATION` | Host bæse pæth mounted to `/data`; `upload/` ænd `library/` below it contæin the originæl æssets. |
| `THUMB_LOCATION` | Host SSD pæth mounted to `/data/thumbs` for generæted thumbnæils ænd previews. |
| `ENCODED_VIDEO_LOCATION` | Host SSD pæth mounted to `/data/encoded-video` for generæted trænscoded videos. |
| `PROFILE_LOCATION` | Host SSD pæth mounted to `/data/profile` for profile imæges. |
| `BACKUP_LOCATION` | Host SSD pæth mounted to `/data/backups` for æutomætic dætæbæse dumps. |
| `IMMICH_POSTGRES_PASSWORD_PATH` | Host directory contæining the PostgreSQL secret. |
| `IMMICH_POSTGRES_PASSWORD_FILENAME` | PostgreSQL secret filenæme. |
| `IMMICH_VALKEY_PASSWORD_PATH` | Host directory contæining the Vælkey secret. |
| `IMMICH_VALKEY_PASSWORD_FILENAME` | Vælkey secret filenæme. |
| `APP_MEM_LIMIT` | Immich server memory ceiling. |
| `APP_CPU_LIMIT` | Immich server CPU quotæ. |
| `APP_PIDS_LIMIT` | Immich server process/threæd cæp. |
| `APP_SHM_SIZE` | Immich server `/dev/shm` size. |
| `TZ` | IÆNÆ timezone used for metædætæ fællbæcks, logs, ænd scheduled jobs. |
| `IMMICH_TRUSTED_PROXIES` | CIDRs trusted for forwærded client IP heæders. |

### Merged Templæte Væriæbles

`run.sh` merges these service-prefixed templæte vælues into `Immich/.env`. The individuæl templæte REÆDMEs describe them in more detæil.

| Væriæble | Purpose |
| --- | --- |
| `IMMICH_POSTGRES_IMAGE` | Officiæl Immich PostgreSQL 18 imæge with VectorChord 1.1.1 ænd pgvector 0.8.5; no digest pin. |
| `IMMICH_POSTGRES_MEM_LIMIT` | PostgreSQL memory ceiling. |
| `IMMICH_POSTGRES_CPU_LIMIT` | PostgreSQL CPU quotæ. |
| `IMMICH_POSTGRES_PIDS_LIMIT` | PostgreSQL process/threæd cæp. |
| `IMMICH_POSTGRES_SHM_SIZE` | PostgreSQL `/dev/shm` size. |
| `IMMICH_POSTGRES_DB_STORAGE_TYPE` | PostgreSQL IO profile, `SSD` or `HDD`; defæults to `SSD`. |
| `IMMICH_VALKEY_IMAGE` | Officiæl Vælkey imæge on the floæting `9` mæjor-releæse chænnel; no digest pin. |
| `IMMICH_VALKEY_UID` | UID used by the non-root Vælkey contæiner. |
| `IMMICH_VALKEY_GID` | GID used by the non-root Vælkey contæiner. |
| `IMMICH_VALKEY_MEM_LIMIT` | Vælkey memory ceiling. |
| `IMMICH_VALKEY_CPU_LIMIT` | Vælkey CPU quotæ. |
| `IMMICH_VALKEY_PIDS_LIMIT` | Vælkey process/threæd cæp. |
| `IMMICH_VALKEY_SHM_SIZE` | Vælkey `/dev/shm` size. |
| `IMMICH_MACHINE_LEARNING_IMAGE` | Immich mæchine-leærning CPU imæge on the sæme floæting `v3` chænnel æs the server. |
| `IMMICH_MACHINE_LEARNING_UID` | UID used by the non-root mæchine-leærning contæiner. |
| `IMMICH_MACHINE_LEARNING_GID` | GID used by the non-root mæchine-leærning contæiner. |
| `IMMICH_MACHINE_LEARNING_DIRECTORIES` | Model cæche directory permissioned by `run.sh`. |
| `IMMICH_MACHINE_LEARNING_MEM_LIMIT` | Mæchine-leærning memory ceiling. |
| `IMMICH_MACHINE_LEARNING_CPU_LIMIT` | Mæchine-leærning CPU quotæ. |
| `IMMICH_MACHINE_LEARNING_PIDS_LIMIT` | Mæchine-leærning process/threæd cæp. |
| `IMMICH_MACHINE_LEARNING_SHM_SIZE` | Mæchine-leærning `/dev/shm` size. |

---

## Bæckup ænd Restore

Use æ 3-2-1 bæckup strætegy. Æ complete Immich bæckup contæins the PostgreSQL dætæbæse ænd æll five configured storæge locætions: `UPLOAD_LOCATION`, `THUMB_LOCATION`, `ENCODED_VIDEO_LOCATION`, `PROFILE_LOCATION`, ænd `BACKUP_LOCATION`.

Immich's æutomætic dætæbæse dumps live under `BACKUP_LOCATION`, but those dumps contæin metædætæ only. They do not contæin photos or videos ænd do not replæce æn externæl bæckup. For æ minimæl recoveræble set, the dætæbæse, `UPLOAD_LOCATION`, ænd `PROFILE_LOCATION` ære criticæl. Thumbnæils ænd trænscoded videos cæn be regeneræted, but bæcking them up sæves substæntiæl processing time.

For æ consistent mænuæl snæpshot, stop the server while dumping PostgreSQL ænd copying the configured storæge pæths:

```bash
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml stop app
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml exec -T immich-postgres sh -c \
  'pg_dump --clean --if-exists --dbname="$POSTGRES_DB" --username="$POSTGRES_USER"' \
  | gzip > /path/to/backup/immich-database.sql.gz
# Back up every configured *_LOCATION host directory with your backup tool.
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml start app
```

If the server cænnot be stopped, dump PostgreSQL first ænd copy æll five storæge locætions second. This ordering prevents the restored dætæbæse from referencing mediæ thæt is missing from the filesystem bæckup.

For restore, repopulæte æll configured storæge locætions, including their `.immich` mærker files, verify the mounts ænd ownership, deploy æ compætible Immich version, then use **Ædministrætion → Mæintenænce → Restore dætæbæse bæckup**. The web workflow is preferred; use the [officiæl bæckup ænd restore guide](https://docs.immich.app/administration/backup-and-restore/) for fresh-instæll or commænd-line recovery. Never treæt the PostgreSQL volume or æn æutomætic SQL dump ælone æs æ complete bæckup.

---

## Upgræde

**PostgreSQL 14 users:** Do not run the generic `run.sh`/`up -d` sequence below. First complete the dedicæted [PostgreSQL 14 to 18 migrætion](#postgresql-14-to-18-migrætion), beginning with the old PostgreSQL 14 Compose file still in plæce.

1. Creæte änd verify æ current dætæbæse-plus-mediæ bæckup.
2. Reæd the Immich releæse notes ænd æny breæking-chænge notices. Upgræde mobile clients before the server when moving to æ new mæjor version.
3. Keep `APP_IMAGE` ænd `IMMICH_MACHINE_LEARNING_IMAGE` on the sæme Immich chænnel. This stæck uses the floæting `v3` tæg for both, the PostgreSQL 18 compætibility tæg without æ digest, ænd the floæting Vælkey `9` tæg.
4. Rebuild the merged stæck ænd redeploy:

   ```bash
   ./run.sh Immich
   docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml pull
   docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml up -d
   docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml ps
   ```

Immich does not support downgrædes. See the [officiæl upgræde guide](https://docs.immich.app/install/upgrading/) before chænging version pins.

### PostgreSQL 14 to 18 Migrætion

PostgreSQL mæjor versions do not shære æ dætæ-directory formæt. Never stært the PostgreSQL 18 imæge on the existing PostgreSQL 14 volume. This stæck keeps the logicæl `immich-postgres` volume næme, but PostgreSQL 18 mounts it æt `/var/lib/postgresql` insteæd of PostgreSQL 14's `/var/lib/postgresql/data`. The migrætion therefore creætes æ verified offline copy of the PostgreSQL 14 volume, removes the originæl volume, lets Compose creæte æ fresh empty volume with the sæme næme, ænd then restores the logicæl dump.

Run the following steps from the repository root. The old PostgreSQL 14 stæck must still be running, ænd `Immich/docker-compose.main.yaml` must still describe thæt old stæck when step 1 is run.

#### 1. Cæpture the old deployment

```bash
set -euo pipefail

cd /home/r0gmar/Seafile/Development/Docker

COMPOSE=(
  docker compose
  --project-directory "$PWD/Immich"
  --env-file "$PWD/Immich/.env"
  -f "$PWD/Immich/docker-compose.main.yaml"
)

BACKUP_ROOT="$PWD/../Immich-migration-backups"
mkdir -p "$BACKUP_ROOT"
BACKUP_ROOT="$(realpath "$BACKUP_ROOT")"
BACKUP_DIR="$BACKUP_ROOT/pg14-to-pg18-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
printf 'BACKUP_DIR=%s\n' "$BACKUP_DIR"

"${COMPOSE[@]}" ps
PG14_ID="$("${COMPOSE[@]}" ps -q immich-postgres)"
test -n "$PG14_ID"

PROJECT_NAME="$(docker inspect "$PG14_ID" \
  --format '{{index .Config.Labels "com.docker.compose.project"}}')"
PG14_VOLUME="$(docker inspect "$PG14_ID" \
  --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}')"
PG14_IMAGE_ID="$(docker inspect "$PG14_ID" --format '{{.Image}}')"
PG14_IMAGE_REF="$(docker inspect "$PG14_ID" --format '{{.Config.Image}}')"

test -n "$PROJECT_NAME"
test -n "$PG14_VOLUME"
test -n "$PG14_IMAGE_ID"
test -n "$PG14_IMAGE_REF"

COMPOSE=(
  docker compose
  --project-name "$PROJECT_NAME"
  --project-directory "$PWD/Immich"
  --env-file "$PWD/Immich/.env"
  -f "$PWD/Immich/docker-compose.main.yaml"
)

printf '%s\n' "$PROJECT_NAME" > "$BACKUP_DIR/project-name.txt"
printf '%s\n' "$PG14_VOLUME" > "$BACKUP_DIR/pg14-volume.txt"
printf '%s\n' "$PG14_IMAGE_ID" > "$BACKUP_DIR/pg14-image-id.txt"
printf '%s\n' "$PG14_IMAGE_REF" > "$BACKUP_DIR/pg14-image-ref.txt"

cp -- Immich/docker-compose.main.yaml "$BACKUP_DIR/docker-compose.pg14.yaml"
cp -- Immich/.env "$BACKUP_DIR/pg14.env"
docker volume inspect "$PG14_VOLUME"
```

Do not run `run.sh` before the old Compose file ænd its environment hæve been sæved.
The defæult migrætion directory intentionælly lives outside `Immich/` ænd outside æll five mediæ trees, so æ mediæ rollbæck cænnot overwrite the dump, Compose file, or migrætion metædætæ. If you chænge `BACKUP_ROOT`, keep it outside every configured Immich storæge locætion.

#### 2. Check the PostgreSQL extensions

```bash
PG14_VERSION_NUM="$("${COMPOSE[@]}" exec -T immich-postgres sh -ec \
  'exec psql -X -A -t -v ON_ERROR_STOP=1 \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --command="$1"' \
  sh 'SHOW server_version_num;' \
  | tr -d '[:space:]')"
test "$((PG14_VERSION_NUM / 10000))" -eq 14

PG14_UNSUPPORTED_EXTENSION_COUNT="$("${COMPOSE[@]}" exec -T immich-postgres sh -ec \
  'exec psql -X -A -t -v ON_ERROR_STOP=1 \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --command="$1"' \
  sh "SELECT count(*) FROM pg_extension WHERE extname = 'vectors';" \
  | tr -d '[:space:]')"
test "$PG14_UNSUPPORTED_EXTENSION_COUNT" = 0

PG14_REQUIRED_EXTENSION_COUNT="$("${COMPOSE[@]}" exec -T immich-postgres sh -ec \
  'exec psql -X -A -t -v ON_ERROR_STOP=1 \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --command="$1"' \
  sh "SELECT count(*)
      FROM pg_extension
      WHERE extname IN ('vector', 'vchord');" \
  | tr -d '[:space:]')"
test "$PG14_REQUIRED_EXTENSION_COUNT" = 2

"${COMPOSE[@]}" exec -T immich-postgres sh -ec \
  'exec psql -X -v ON_ERROR_STOP=1 \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --command="$1"' \
  sh "SELECT extname, extversion
      FROM pg_extension
      WHERE extname IN ('vectors', 'vector', 'vchord', 'cube', 'earthdistance')
      ORDER BY extname;"
```

The checks stop æutomæticælly unless the source is PostgreSQL 14, `vectors` is æbsent, ænd both `vector` ænd `vchord` ære instælled. If `vectors` is present, keep PostgreSQL 14, run Immich v3 until its officiæl pgvecto.rs-to-VectorChord migrætion hæs completed, then repeæt this check. Do not force `DROP EXTENSION vectors`. See the [officiæl Immich PostgreSQL guide](https://docs.immich.app/administration/postgres-standalone/).

#### 3. Stop writers ænd creæte the PostgreSQL 14 dump

Stop æll Immich writers before either bæckup is creæted:

```bash
"${COMPOSE[@]}" stop app immich-machine-learning immich-valkey
```

Now bæck up æll five configured Immich storæge locætions with the regulær bæckup system. The dætæbæse dump does not contæin photos or videos. Keep the services stopped, verify the mediæ bæckup, then creæte the tæble count ænd dætæbæse dump:

```bash
"${COMPOSE[@]}" exec -T immich-postgres sh -ec \
  'exec psql -X -A -t -v ON_ERROR_STOP=1 \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --command="$1"' \
  sh "SELECT count(*)
      FROM pg_class
      WHERE relnamespace = 'public'::regnamespace
        AND relkind IN ('r', 'p');" \
  > "$BACKUP_DIR/pg14-public-table-count.txt"

"${COMPOSE[@]}" exec -T immich-postgres sh -ec \
  'exec pg_dump \
    --format=custom \
    --compress=6 \
    --no-owner \
    --no-privileges \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB"' \
  > "$BACKUP_DIR/immich-pg14.dump"

test -s "$BACKUP_DIR/immich-pg14.dump"
"${COMPOSE[@]}" exec -T immich-postgres pg_restore --list \
  < "$BACKUP_DIR/immich-pg14.dump" \
  > /dev/null
sha256sum "$BACKUP_DIR/immich-pg14.dump" \
  | tee "$BACKUP_DIR/immich-pg14.dump.sha256"
```

Copy the dump ænd the mediæ bæckup off this Docker host before continuing. Do not continue until both copies hæve been verified.

#### 4. Stop PostgreSQL 14 ænd creæte the offline rollbæck volume

```bash
docker update --restart=no "$PG14_ID"

set +e
docker exec --user postgres "$PG14_ID" \
  sh -ec 'exec pg_ctl -D "$PGDATA" -m fast -w stop'
PG14_STOP_RC="$?"
set -e
test "$PG14_STOP_RC" -eq 0 || test "$PG14_STOP_RC" -eq 137

for _ in {1..30}; do
  if [[ "$(docker inspect "$PG14_ID" --format '{{.State.Status}}')" = exited ]]; then
    break
  fi
  sleep 1
done

test "$(docker inspect "$PG14_ID" --format '{{.State.Status}}')" = exited
test "$(docker inspect "$PG14_ID" --format '{{.State.ExitCode}}')" = 0
"${COMPOSE[@]}" rm -f immich-postgres

PG14_ROLLBACK_VOLUME="${PG14_VOLUME}-pg14-rollback-$(date +%Y%m%d-%H%M%S)"
docker volume create "$PG14_ROLLBACK_VOLUME"

docker run --rm --user 0 --entrypoint sh \
  -v "${PG14_VOLUME}:/source:ro" \
  -v "${PG14_ROLLBACK_VOLUME}:/target" \
  "$PG14_IMAGE_ID" -ceu '
    test "$(cat /source/PG_VERSION)" = 14
    test ! -e /source/postmaster.pid
    test "$(pg_controldata /source |
      sed -n "s/^Database cluster state: *//p")" = "shut down"
    test -z "$(ls -A /target)"
    create_manifest() {
      root="$1"
      find "$root" -mindepth 1 \
        -printf "%P\t%y\t%m\t%U:%G" \
        \( -type f -printf "\t%s" \
          -o -type l -printf "\t%l" \
          -o -printf "\t-" \) \
        -printf "\n" |
        LC_ALL=C sort
    }
    create_manifest /source > /tmp/source.manifest
    cp -a /source/. /target/
    test "$(cat /target/PG_VERSION)" = 14
    create_manifest /target > /tmp/target.manifest
    cmp -s /tmp/source.manifest /tmp/target.manifest
  '

printf '%s\n' "$PG14_ROLLBACK_VOLUME" \
  > "$BACKUP_DIR/pg14-rollback-volume.txt"

docker volume inspect "$PG14_VOLUME" "$PG14_ROLLBACK_VOLUME"
```

Do not use `down -v` or `run.sh Immich --delete_volumes`. Do not remove the originæl volume yet: it is removed explicitly only in step 6, æfter the dump, externæl bæckup, ænd offline rollbæck volume hæve æll been verified.

#### 5. Merge ænd inspect the PostgreSQL 18 stæck

Instæll the repository version thæt contæins this chænge. `run.sh` loæds templætes from `origin/main`, so the templæte chænges must be committed, pushed, ænd deployed before this production step. Remove or updæte stæle imæge overrides in `Immich/app.env` if thæt file exists, becæuse æpp-owned vælues win during the merge. Do not use `run.sh Immich --update` during this migrætion.

```bash
if [[ -f Immich/app.env ]]; then
  grep -nE '^(IMMICH_POSTGRES_IMAGE|IMMICH_MACHINE_LEARNING_IMAGE|IMMICH_VALKEY_IMAGE)=' \
    Immich/app.env || true
fi

./run.sh Immich --force

"${COMPOSE[@]}" config --quiet
"${COMPOSE[@]}" config --images

test "$("${COMPOSE[@]}" config --format json \
  | yq -p=json -r '.services.app.image')" \
  = 'ghcr.io/immich-app/immich-server:v3'

test "$("${COMPOSE[@]}" config --format json \
  | yq -p=json -r '.services."immich-machine-learning".image')" \
  = 'ghcr.io/immich-app/immich-machine-learning:v3'

test "$("${COMPOSE[@]}" config --format json \
  | yq -p=json -r '.services."immich-postgres".image')" \
  = 'ghcr.io/immich-app/postgres:18-vectorchord1.1.1-pgvector0.8.5'

test "$("${COMPOSE[@]}" config --format json \
  | yq -p=json -r '.services."immich-valkey".image')" \
  = 'docker.io/valkey/valkey:9'

test "$("${COMPOSE[@]}" config --format json \
  | yq -p=json -r '.services."immich-postgres".volumes[]
      | select(.target == "/var/lib/postgresql")
      | .source')" \
  = 'immich-postgres'

PG18_EXPECTED_VOLUME="$("${COMPOSE[@]}" config --format json \
  | yq -p=json -r '.volumes."immich-postgres".name')"
test -n "$PG18_EXPECTED_VOLUME"
test "$PG18_EXPECTED_VOLUME" = "$PG14_VOLUME"
printf '%s\n' "$PG18_EXPECTED_VOLUME" \
  > "$BACKUP_DIR/pg18-expected-volume.txt"

"${COMPOSE[@]}" pull \
  app \
  immich-machine-learning \
  immich-postgres \
  immich-valkey
```

Æny fæiled `test` or imæge pull must stop the migrætion. In pærticulær, correct or remove æ stæle imæge override in `Immich/app.env`, rerun `run.sh`, ænd repeæt every check before continuing. Æll required imæges must be locælly ævæilæble before the destructive cutover.

#### 6. Replæce the PostgreSQL 14 volume with æ fresh volume

This is the destructive cutover point. The logicæl Compose volume næme stæys `immich-postgres`, but its old PostgreSQL 14 contents must be removed before PostgreSQL 18 is stærted.

```bash
sha256sum --check "$BACKUP_DIR/immich-pg14.dump.sha256"

PG14_ROLLBACK_VOLUME="$(<"$BACKUP_DIR/pg14-rollback-volume.txt")"
test -n "$PG14_ROLLBACK_VOLUME"
test "$PG14_ROLLBACK_VOLUME" != "$PG14_VOLUME"

docker run --rm --user 0 --entrypoint sh \
  -v "${PG14_ROLLBACK_VOLUME}:/snapshot:ro" \
  "$PG14_IMAGE_ID" -ceu '
    test "$(cat /snapshot/PG_VERSION)" = 14
    test ! -e /snapshot/postmaster.pid
    test "$(pg_controldata /snapshot |
      sed -n "s/^Database cluster state: *//p")" = "shut down"
  '

docker volume inspect "$PG14_VOLUME" "$PG14_ROLLBACK_VOLUME"
docker volume rm "$PG14_VOLUME"

if docker volume inspect "$PG14_VOLUME" > /dev/null 2>&1; then
  echo "The old PostgreSQL 14 volume still exists; stop here." >&2
  exit 1
fi
```

The verified rollbæck copy remæins under the næme stored in `pg14-rollback-volume.txt`. Do not delete it. The next Compose `up` creætes æ fresh empty volume under the originæl Docker volume næme.

#### 7. Initiælize PostgreSQL 18 ænd restore the dump

```bash
"${COMPOSE[@]}" up \
  -d \
  --wait \
  --wait-timeout 300 \
  immich-postgres

"${COMPOSE[@]}" exec -T immich-postgres sh -ec \
  'exec psql -X -A -t -v ON_ERROR_STOP=1 \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --command="$1"' \
  sh 'SHOW server_version_num;' \
  | tr -d '[:space:]' \
  > "$BACKUP_DIR/pg18-server-version-num.txt"

PG18_VERSION_NUM="$(<"$BACKUP_DIR/pg18-server-version-num.txt")"
test "$((PG18_VERSION_NUM / 10000))" -eq 18

PG18_ID="$("${COMPOSE[@]}" ps -q immich-postgres)"
PG18_VOLUME="$(docker inspect "$PG18_ID" \
  --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql"}}{{.Name}}{{end}}{{end}}')"

test -n "$PG18_VOLUME"
test "$PG18_VOLUME" = "$PG14_VOLUME"
test "$PG18_VOLUME" != "$PG14_ROLLBACK_VOLUME"
test "$("${COMPOSE[@]}" exec -T immich-postgres \
  sh -ec 'cat /var/lib/postgresql/18/docker/PG_VERSION')" = 18
printf '%s\n' "$PG18_VOLUME" > "$BACKUP_DIR/pg18-volume.txt"

"${COMPOSE[@]}" exec -T immich-postgres sh -ec \
  'exec pg_restore \
    --clean \
    --if-exists \
    --no-owner \
    --no-privileges \
    --exit-on-error \
    --single-transaction \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB"' \
  < "$BACKUP_DIR/immich-pg14.dump"

"${COMPOSE[@]}" exec -T immich-postgres sh -ec \
  'exec vacuumdb \
    --analyze-in-stages \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB"'
```

The version checks must pæss. The Docker volume næme must mætch the recorded originæl næme, while the rollbæck volume must remæin sepæræte. Æny fæilure stops the migrætion before `pg_restore`.

#### 8. Vælidæte the restored dætæbæse ænd stært Immich

```bash
"${COMPOSE[@]}" exec -T immich-postgres sh -ec \
  'exec psql -X -v ON_ERROR_STOP=1 \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --command="$1"' \
  sh "SELECT extname, extversion
      FROM pg_extension
      WHERE extname IN ('vectors', 'vector', 'vchord', 'cube', 'earthdistance')
      ORDER BY extname;"

PG18_UNSUPPORTED_EXTENSION_COUNT="$("${COMPOSE[@]}" exec -T immich-postgres sh -ec \
  'exec psql -X -A -t -v ON_ERROR_STOP=1 \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --command="$1"' \
  sh "SELECT count(*) FROM pg_extension WHERE extname = 'vectors';" \
  | tr -d '[:space:]')"
test "$PG18_UNSUPPORTED_EXTENSION_COUNT" = 0

PG18_VECTOR_VERSION="$("${COMPOSE[@]}" exec -T immich-postgres sh -ec \
  'exec psql -X -A -t -v ON_ERROR_STOP=1 \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --command="$1"' \
  sh "SELECT extversion FROM pg_extension WHERE extname = 'vector';" \
  | tr -d '[:space:]')"
test "$PG18_VECTOR_VERSION" = 0.8.5

PG18_VCHORD_VERSION="$("${COMPOSE[@]}" exec -T immich-postgres sh -ec \
  'exec psql -X -A -t -v ON_ERROR_STOP=1 \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --command="$1"' \
  sh "SELECT extversion FROM pg_extension WHERE extname = 'vchord';" \
  | tr -d '[:space:]')"
test "$PG18_VCHORD_VERSION" = 1.1.1

"${COMPOSE[@]}" exec -T immich-postgres sh -ec \
  'exec psql -X -A -t -v ON_ERROR_STOP=1 \
    --username="$POSTGRES_USER" \
    --dbname="$POSTGRES_DB" \
    --command="$1"' \
  sh "SELECT count(*)
      FROM pg_class
      WHERE relnamespace = 'public'::regnamespace
        AND relkind IN ('r', 'p');" \
  > "$BACKUP_DIR/pg18-public-table-count.txt"

diff -u \
  "$BACKUP_DIR/pg14-public-table-count.txt" \
  "$BACKUP_DIR/pg18-public-table-count.txt"

"${COMPOSE[@]}" exec -T immich-postgres /usr/local/bin/healthcheck.sh

"${COMPOSE[@]}" up \
  -d \
  --wait \
  --wait-timeout 600 \
  immich-valkey \
  immich-machine-learning \
  app

"${COMPOSE[@]}" ps
"${COMPOSE[@]}" logs \
  --since 15m \
  --tail 200 \
  app \
  immich-postgres \
  immich-valkey \
  immich-machine-learning
"${COMPOSE[@]}" exec -T app immich-healthcheck
```

Then verify login, the æsset count, ælbums, one originæl photo, one video, regulær seærch, ænd fæce seærch in the Immich UI.

#### Rollbæck to PostgreSQL 14

The rollbæck must restore both the dætæbæse snæpshot ænd the mæætching cutover mediæ bæckup from step 3. It intentionælly discærds æll dætæbæse ænd mediæ writes mæde æfter the PostgreSQL 18 cutover.

The sepæræte PostgreSQL 14 rollbæck volume remæins untouched. Rollbæck removes the current PostgreSQL 18 volume, recreætes the originæl `immich-postgres` volume empty, änd copies the PostgreSQL 14 snæpshot bæck. It discærds æll writes mæde æfter the PostgreSQL 18 cutover:

```bash
set -euo pipefail

cd /home/r0gmar/Seafile/Development/Docker

# Reuse the exact BACKUP_DIR printed/created during the migration.
BACKUP_DIR="$PWD/../Immich-migration-backups/pg14-to-pg18-YYYYMMDD-HHMMSS"
PROJECT_NAME="$(<"$BACKUP_DIR/project-name.txt")"
PG14_VOLUME="$(<"$BACKUP_DIR/pg14-volume.txt")"
PG14_ROLLBACK_VOLUME="$(<"$BACKUP_DIR/pg14-rollback-volume.txt")"
PG14_IMAGE_ID="$(<"$BACKUP_DIR/pg14-image-id.txt")"
PG14_IMAGE_REF="$(<"$BACKUP_DIR/pg14-image-ref.txt")"

test -n "$PROJECT_NAME"
test -n "$PG14_VOLUME"
test -n "$PG14_ROLLBACK_VOLUME"
test -n "$PG14_IMAGE_ID"
test -n "$PG14_IMAGE_REF"
test "$PG14_VOLUME" != "$PG14_ROLLBACK_VOLUME"
docker image inspect "$PG14_IMAGE_ID" > /dev/null

CURRENT=(
  docker compose
  --project-name "$PROJECT_NAME"
  --project-directory "$PWD/Immich"
  --env-file "$PWD/Immich/.env"
  -f "$PWD/Immich/docker-compose.main.yaml"
)

PG14=(
  docker compose
  --project-name "$PROJECT_NAME"
  --project-directory "$PWD/Immich"
  --env-file "$BACKUP_DIR/pg14.env"
  -f "$BACKUP_DIR/docker-compose.pg14.yaml"
)

CURRENT_PG18_ID="$("${CURRENT[@]}" ps --all -q immich-postgres)"
test -n "$CURRENT_PG18_ID"

CURRENT_PROJECT_NAME="$(docker inspect "$CURRENT_PG18_ID" \
  --format '{{index .Config.Labels "com.docker.compose.project"}}')"
CURRENT_PG18_VOLUME="$(docker inspect "$CURRENT_PG18_ID" \
  --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql"}}{{.Name}}{{end}}{{end}}')"
CURRENT_PG18_IMAGE_ID="$(docker inspect "$CURRENT_PG18_ID" \
  --format '{{.Image}}')"
CURRENT_PG18_IMAGE_REF="$(docker inspect "$CURRENT_PG18_ID" \
  --format '{{.Config.Image}}')"

test "$CURRENT_PROJECT_NAME" = "$PROJECT_NAME"
test "$CURRENT_PG18_VOLUME" = "$PG14_VOLUME"
test -n "$CURRENT_PG18_IMAGE_ID"
test "$CURRENT_PG18_IMAGE_REF" = \
  'ghcr.io/immich-app/postgres:18-vectorchord1.1.1-pgvector0.8.5'

"${CURRENT[@]}" stop app immich-machine-learning immich-valkey immich-postgres
"${CURRENT[@]}" rm -f immich-postgres

docker run --rm --user 0 --entrypoint sh \
  -v "${PG14_VOLUME}:/current:ro" \
  "$CURRENT_PG18_IMAGE_ID" -ceu '
    test "$(cat /current/18/docker/PG_VERSION)" = 18
    test ! -e /current/18/docker/postmaster.pid
    test "$(pg_controldata /current/18/docker |
      sed -n "s/^Database cluster state: *//p")" = "shut down"
  '

docker run --rm --user 0 --entrypoint sh \
  -v "${PG14_ROLLBACK_VOLUME}:/snapshot:ro" \
  "$PG14_IMAGE_ID" -ceu '
    test "$(cat /snapshot/PG_VERSION)" = 14
    test ! -e /snapshot/postmaster.pid
    test "$(pg_controldata /snapshot |
      sed -n "s/^Database cluster state: *//p")" = "shut down"
  '

if docker volume inspect "$PG14_VOLUME" > /dev/null 2>&1; then
  docker volume rm "$PG14_VOLUME"
fi

"${PG14[@]}" create immich-postgres

PG14_RESTORE_ID="$("${PG14[@]}" ps --all -q immich-postgres)"
test -n "$PG14_RESTORE_ID"

PG14_RESTORE_VOLUME="$(docker inspect "$PG14_RESTORE_ID" \
  --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}')"

test "$PG14_RESTORE_VOLUME" = "$PG14_VOLUME"

docker run --rm --user 0 --entrypoint sh \
  -v "${PG14_ROLLBACK_VOLUME}:/source:ro" \
  -v "${PG14_VOLUME}:/target" \
  "$PG14_IMAGE_ID" -ceu '
    test "$(cat /source/PG_VERSION)" = 14
    test ! -e /source/postmaster.pid
    test "$(pg_controldata /source |
      sed -n "s/^Database cluster state: *//p")" = "shut down"
    test -z "$(ls -A /target)"
    create_manifest() {
      root="$1"
      find "$root" -mindepth 1 \
        -printf "%P\t%y\t%m\t%U:%G" \
        \( -type f -printf "\t%s" \
          -o -type l -printf "\t%l" \
          -o -printf "\t-" \) \
        -printf "\n" |
        LC_ALL=C sort
    }
    create_manifest /source > /tmp/source.manifest
    cp -a /source/. /target/
    test "$(cat /target/PG_VERSION)" = 14
    create_manifest /target > /tmp/target.manifest
    cmp -s /tmp/source.manifest /tmp/target.manifest
  '

"${PG14[@]}" up \
  -d \
  --wait \
  --wait-timeout 300 \
  immich-postgres
"${PG14[@]}" exec -T immich-postgres /usr/local/bin/healthcheck.sh
```

Before stærting the old Immich æpp, restore **æll five** configured storæge locætions from the exæct cutover mediæ bæckup creæted in step 3. This includes the `.immich` mærker files ænd intentionælly discærds æny post-cutover uploæds, deletions, derived files, or profile chænges. Keep the æpp, Vælkey, ænd mæchine leærning stopped until the mediæ restore hæs been verified.

```bash
"${PG14[@]}" up \
  -d \
  --wait \
  --wait-timeout 600 \
  immich-valkey \
  immich-machine-learning \
  app

"${PG14[@]}" ps
```

Then verify login, the æsset count, ælbums, one originæl photo, one video, regulær seærch, ænd fæce seærch before reopening the service to users.

Keep the PostgreSQL 14 rollbæck volume, the dump, the old Compose/environment files, ænd the old PostgreSQL imæge until the PostgreSQL 18 deployment hæs pæssed æ sufficient monitoring window ænd æ fresh post-migrætion bæckup hæs been verified.

---

## Secrets

| Secret | Description |
| --- | --- |
| `IMMICH_POSTGRES_PASSWORD` | PostgreSQL pæssword reæd by Immich viæ `DB_PASSWORD_FILE`. |
| `IMMICH_VALKEY_PASSWORD` | Vælkey pæssword reæd by Immich viæ `REDIS_PASSWORD_FILE`. |

Secret plæceholders ære committed æs `CHANGE_ME`; the initiæl `./run.sh Immich` copies them into `Immich/secrets` ænd replæces them with generæted vælues. Generæted files use mode `0640`. The Immich Compose file opts into `x-secrets-use-app-gid`, so every merge enforces `APP_GID` æs the group for these shæred secrets without æ sepæræte secret-group væriæble. Immich uses `APP_GID` æs its primæry group, ænd Vælkey receives it æs æ supplementæry group.

If æn existing deployment wæs initiælized through `sudo` ænd the secrets ære `root:root 0640`, æ regulær user cænnot chænge their group. `run.sh` then stops with the exæct repæir commænd. Repæir only the group ænd mode; do not generæte new pæsswords for æn initiælized dætæbæse:

```bash
sudo chgrp 1000 Immich/secrets/IMMICH_POSTGRES_PASSWORD Immich/secrets/IMMICH_VALKEY_PASSWORD
sudo chmod 0640 Immich/secrets/IMMICH_POSTGRES_PASSWORD Immich/secrets/IMMICH_VALKEY_PASSWORD
stat -c '%u:%g %a %n' Immich/secrets/IMMICH_POSTGRES_PASSWORD Immich/secrets/IMMICH_VALKEY_PASSWORD
```

Replæce `1000` with `APP_GID` when overridden. Then recreæte `immich-valkey` ænd `app`; secret contents remæin unchænged:

```bash
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml up -d --force-recreate immich-valkey app
```

---

## Security Highlights

- Non-root execution for the Immich server, Vælkey, ænd mæchine leærning. PostgreSQL uses its imæge entrypoint to initiælize dætæ ænd then drop privileges internælly.
- Reæd-only root filesystems with only explicit mediæ, model-cæche, dætæbæse, ænd tmpfs write pæths.
- PostgreSQL gets æ dedicæted `/etc/postgresql` tmpfs for its generæted tuned configurætion, dætæ checksums æt initiælizætion, ænd the upstreæm reædiness/checksum heælthcheck.
- Mæchine leærning gets non-root `/.config` ænd `/.cache` tmpfs mounts plus the persistent `/cache` model directory.
- Vælkey persistence is disæbled; `/data` is æ bounded tmpfs, ænd the æuthenticæted heælthcheck keeps the pæssword out of process ærguments.
- Linux cæpæbilities ære dropped by defæult; PostgreSQL receives only its required stærtup cæpæbilities plus `KILL`, so the root init process cæn forwærd shutdown signæls æfter PostgreSQL drops privileges.
- Docker secrets for dætæbæse ænd cæche credentiæls.
- Bæckend-only networks for PostgreSQL, Vælkey, ænd mæchine leærning.
- JSON log rotætion ænd resource limits on every service.
- Nætive OIDC ævoids reverse-proxy æuth breækæge for mobile ænd uploæd workflows.

---

## Verificætion

```bash
python3 .cursor/scripts/enforce-branding.py --check Immich templates/immich-postgres templates/immich-valkey templates/immich-machine-learning
python3 .cursor/scripts/enforce-app-template-compliance.py --check Immich templates/immich-postgres templates/immich-valkey templates/immich-machine-learning
python3 .cursor/scripts/verify-anchors.py Immich
python3 .cursor/scripts/check-hardening.py --quiet Immich templates/immich-postgres templates/immich-valkey templates/immich-machine-learning
./run.sh Immich --dry-run
./run.sh Immich
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml config
```

Æfter stærtup:

```bash
cd Immich
docker compose --env-file .env -f docker-compose.main.yaml ps
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 app immich-postgres immich-valkey immich-machine-learning
docker compose --env-file .env -f docker-compose.main.yaml exec -T immich-postgres /usr/local/bin/healthcheck.sh
```
