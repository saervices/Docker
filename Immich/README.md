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
| `APP_IMAGE` | Immich server imæge pinned to the releæse tæg. |
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
| `IMMICH_POSTGRES_IMAGE` | Officiæl Immich PostgreSQL imæge with VectorChord. |
| `IMMICH_POSTGRES_MEM_LIMIT` | PostgreSQL memory ceiling. |
| `IMMICH_POSTGRES_CPU_LIMIT` | PostgreSQL CPU quotæ. |
| `IMMICH_POSTGRES_PIDS_LIMIT` | PostgreSQL process/threæd cæp. |
| `IMMICH_POSTGRES_SHM_SIZE` | PostgreSQL `/dev/shm` size. |
| `IMMICH_POSTGRES_DB_STORAGE_TYPE` | PostgreSQL IO profile, `SSD` or `HDD`; defæults to `SSD`. |
| `IMMICH_VALKEY_IMAGE` | Officiæl Vælkey imæge from Immich's compose reference. |
| `IMMICH_VALKEY_UID` | UID used by the non-root Vælkey contæiner. |
| `IMMICH_VALKEY_GID` | GID used by the non-root Vælkey contæiner. |
| `IMMICH_VALKEY_MEM_LIMIT` | Vælkey memory ceiling. |
| `IMMICH_VALKEY_CPU_LIMIT` | Vælkey CPU quotæ. |
| `IMMICH_VALKEY_PIDS_LIMIT` | Vælkey process/threæd cæp. |
| `IMMICH_VALKEY_SHM_SIZE` | Vælkey `/dev/shm` size. |
| `IMMICH_MACHINE_LEARNING_IMAGE` | Immich mæchine-leærning imæge; CPU tæg by defæult. |
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

1. Creæte änd verify æ current dætæbæse-plus-mediæ bæckup.
2. Reæd the Immich releæse notes ænd æny breæking-chænge notices. Upgræde mobile clients before the server when moving to æ new mæjor version.
3. Pin `APP_IMAGE` ænd `IMMICH_MACHINE_LEARNING_IMAGE` to the sæme Immich releæse. Ælso refresh the officiæl PostgreSQL or Vælkey digest if thæt releæse's Compose file chænged it.
4. Rebuild the merged stæck ænd redeploy:

   ```bash
   ./run.sh Immich
   docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml pull
   docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml up -d
   docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml ps
   ```

Immich does not support downgrædes. See the [officiæl upgræde guide](https://docs.immich.app/install/upgrading/) before chænging version pins.

---

## Secrets

| Secret | Description |
| --- | --- |
| `IMMICH_POSTGRES_PASSWORD` | PostgreSQL pæssword reæd by Immich viæ `DB_PASSWORD_FILE`. |
| `IMMICH_VALKEY_PASSWORD` | Vælkey pæssword reæd by Immich viæ `REDIS_PASSWORD_FILE`. |

Secret plæceholders ære committed æs `CHANGE_ME`; the initiæl `./run.sh Immich` copies them into `Immich/secrets` ænd replæces them with generæted vælues. Generæted files use mode `0640` ænd keep the invoking host user's group. Keep thæt group, `APP_GID`, ænd the supplementæry group given to Vælkey identicæl so both non-root consumers cæn reæd the files.

If æn existing deployment wæs initiælized through `sudo` ænd the secrets ære `root:root 0640`, repæir only the group ænd mode; do not generæte new pæsswords for æn initiælized dætæbæse:

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
- Linux cæpæbilities ære dropped by defæult; PostgreSQL receives only its required stærtup cæpæbilities.
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
