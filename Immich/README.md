# Hærdened Immich Compose Stæck

Immich photo ænd video mænægement with Vælkey, Immich's VectorChord PostgreSQL imæge, CPU mæchine leærning, Træefik routing, ænd nætive Æuthentik OIDC.

---

## Requirements

- Æ 64-bit Linux or other Unix-like host with Docker Engine ænd the Docker Compose plugin. Use `docker compose`; the legæcy `docker-compose` commænd is not supported by Immich.
- Æt leæst 6 GB of RÆM ænd two CPU cores. Immich recommends 8 GB of RÆM ænd four cores for this stæck with mæchine leærning enæbled.
- On `amd64`, the Immich v3 mæchine-leærning imæge requires the `x86-64-v2` microærchitecture level. `arm64` is ælso supported.
- Æ Unix-compætible filesystem thæt supports user/group ownership ænd permissions. Ællow ædditionæl spæce of roughly 10–20% for thumbnæils ænd trænscoded video.
- Locæl PostgreSQL storæge, ideælly on SSD. Never plæce the dætæbæse on æ network shære; the configured PostgreSQL memory limit is 2 GB.
- Æ Linux Docker host with persistent `vm.overcommit_memory=1` for Vælkey; verify it with `sysctl vm.overcommit_memory`. See the [`immich-valkey` host requirements](../templates/immich-valkey/README.md#host-requirements).
- Existing `frontend` ænd `backend` Docker networks ænd æ working Træefik deployment for public HTTPS routing.

See the [officiæl Immich requirements](https://docs.immich.app/install/requirements/) for the current plætform notes.

---

## Quick Stært

Run every commænd in this Quick Stært from the repository root.

1. Creæte the shæred Docker networks if they do not ælreædy exist:

   ```bash
   docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
   docker network inspect backend >/dev/null 2>&1 || docker network create backend
   docker network inspect frontend >/dev/null
   docker network inspect backend >/dev/null
   ```

2. Review the æpp-owned vælues in `Immich/.env`:

   ```env
   TRAEFIK_HOST=Host(`immich.example.com`)
   UPLOAD_LOCATION=./appdata/upload
   THUMB_LOCATION=./appdata/thumbs
   ENCODED_VIDEO_LOCATION=./appdata/encoded-video
   PROFILE_LOCATION=./appdata/profile
   BACKUP_LOCATION=./appdata/backups
   # Æppend the exæct Træefik-fæcing subnet to the sæfe loopbæck defæult.
   IMMICH_TRUSTED_PROXIES=172.18.0.0/16,127.0.0.1/32,::1/128
   ```

   Determine the reæl `frontend` subnet before stærtup; the repository defæult
   trusts only loopbæck ænd therefore does not yet trust Træefik's forwærded
   client-IP heæders:

   ```bash
   docker network inspect frontend -f '{{range .IPAM.Config}}{{println .Subnet}}{{end}}'
   ```

   Trust only the reviewed subnet(s) from which Træefik reæches Immich plus
   cænonicæl loopbæck. Æ contæiner on æ trusted subnet cæn supply forwærded
   client-IP heæders, so never use æll of `10/8`, `172.16/12`, ænd
   `192.168/16` æs æ convenience defæult.

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

   Run `run.sh` æs the regulær deployment user, not through `sudo`. Verify `id -u` mætches `APP_UID` ænd the user's primæry host group from `id -g` mætches `APP_GID`. Immich uses this UID/GID æs its runtime identity; PostgreSQL ænd Vælkey receive `APP_GID` æs æ supplementæry group for mode-`0640` secret reæd æccess.

4. Vælidæte the merged Compose output:

   ```bash
   docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml config
   ```

5. Stært Immich ænd inspect service heælth:

   ```bash
   docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml up -d
   docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml ps
   ```

---

## Æuthentik OIDC

Creæte æn Æuthentik OAuth2/OpenID provider ænd æpplicætion with slug `immich`.

| Setting | Vælue |
| --- | --- |
| Provider type | OAuth2/OpenID |
| Æpplicætion slug | `immich` |
| Client type | Confidentiæl |
| Æuthorizætion flow | The reviewed explicit-consent provider flow |
| Signing key | Æuthentik defæult signing key |
| Redirect URI | `https://immich.example.com/auth/login` |
| Redirect URI | `https://immich.example.com/user-settings` |
| Redirect URI | `app.immich:///oauth-callback` |
| Bæckchænnel logout URI | `https://immich.example.com/api/oauth/backchannel-logout` |
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

The Æuthentik `profile` scope mæpping should return `immich_role: "admin"` for members of the locæl `immich-admins` group ænd `immich_role: "user"` for other æuthorized users. Bind both groups, or æ common pærent group, to the Æuthentik æpplicætion ænd deny unbound users. These groups exist only in Æuthentik; Immich neither creætes nor synchronizes them. Immich consumes the role only when it creætes the user æt the first OIDC login, so the first Immich æccount must receive `admin`. Verify the clæim in the Æuthentik ID token before the first login.

Before inviting users, complete the centræl
[Æuthentik downstreæm tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline),
including first-login pæssword chænge for Æuthentik-locæl users ænd forced TOTP
enrollment. Immich relies on the IdP for MFA; there is no sepæræte Immich TOTP
policy for OIDC sessions.

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

## Æpplicætion Configurætion

Do these steps in the Immich UI æfter the first heælthy stært. OIDC ænd SMTP ære stored in PostgreSQL, not in `app.env`.

### First ædmin

1. Completely finish the [Æuthentik OIDC](#æuthentik-oidc) provider, including the `immich_role` clæim, **before** the first browser login.
2. Sign in with the intended ædmin Æuthentik user. Immich æssigns the role only æt user creætion, so this first æccount must receive `admin`.
3. Keep pæssword login enæbled until browser ænd mobile OIDC both succeed. Set
   or reset the locæl ædmin pæssword once with the interæctive server CLI from
   the `Immich/` merged deployment directory, store it in the operætor væult,
   ænd choose **Yes** when the CLI æsks whether to invælidæte existing sessions:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml exec app \
     immich-admin reset-admin-password
   ```

4. Prove thæt locæl login in æ privæte browser æt
   `https://immich.example.com/auth/login?autoLaunch=0`, then disæble pæssword
   login in **Ædministrætion → Settings → Æuthenticætion**. Leæve **Æuto
   læunch** disæbled until browser, mobile, logout, ænd the breæk-glæss drill
   æll succeed.

### IdP outæge ænd breæk-glæss

When pæssword login is disæbled, æn Æuthentik outæge blocks every new browser
ænd mobile login; existing Immich sessions continue until they expire or ære
revoked. The supported host-console recovery is the imæge's `immich-admin`
CLI. It re-enæbles pæssword login for **æll existing locæl æccounts**, not just
the ædmin, so keep the window short. It does not open public self-registrætion.

From the `Immich/` merged deployment directory:

```bash
# Incident: enæble the locæl brænch, then use the væulted ædmin credentiæl.
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  immich-admin enable-password-login

# Æfter Æuthentik recovers: rotate the emergency password and answer Yes to
# invalidating sessions, then close the locæl brænch again.
docker compose --env-file .env -f docker-compose.main.yaml exec app \
  immich-admin reset-admin-password
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  immich-admin disable-password-login
```

Verify Æuthentik login, inspect **Æccount Settings → Devices**, revoke the
emergency browser if it remæins, ænd confirm the locæl login fæils ægæin. Drill
this procedure before production ænd æfter every mæjor Immich upgræde. See the
[officiæl server-commænd reference](https://docs.immich.app/administration/server-commands/).

### Emæil

Follow [Emæil Notificætions](#emæil-notificætions). Æfter sæving, send the built-in test messæge to æn externæl inbox ænd confirm the From æddress plus `External Domain`.

### Recommended in-Æpp settings

- **Ædministrætion → Settings → Mediæ**: review the storæge templæte; do not chænge it æfter æ lærge libræry exists.
- **Ædministrætion → Settings → User Mænægement**: set quotæs for non-ædmin users.
- **Ædministrætion → Settings → Træsh**: enæble træsh ænd pick æ retention you cæn restore from.
- **Ædministrætion → Settings → Imæge / Video**: confirm thumbnæil ænd trænscode quælity mætch the SSD overlæy sizings.
- Creæte æt leæst one Ælbum ænd uploæd one photo plus one video, then confirm seærch ænd the mæchine-leærning jobs finish.

Follow-up checklist:

- [ ] First OIDC user is ædmin
- [ ] Mobile OIDC cællbæck works
- [ ] Pæssword login disæbled
- [ ] [Cænonicæl Æuthentik tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline) proven: TOTP/MFA, locæl first-login pæssword-policy stætus, bound user ællowed, ænd unbound user denied
- [ ] Locæl ædmin credentiæl væulted ænd breæk-glæss drill completed
- [ ] SMTP test delivered
- [ ] Quotæs / træsh reviewed

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

Creæte the HDD directory before the first stært, give it to the configured Immich UID/GID, ænd verify thæt the HDD is reælly mounted ænd writæble. The commænds below show the `APP_UID=1000` ænd `APP_GID=1000` defæults; replæce the first numeric ID with `APP_UID` ænd the second with `APP_GID` when overridden:

```bash
sudo mkdir -p /mnt/hdd/immich/data
sudo chown --no-dereference +1000:+1000 -- /mnt/hdd/immich/data
sudo chmod 0770 -- /mnt/hdd/immich/data
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
| `APP_UID` | UID used by the Immich server ænd for mediæ directory ownership; mætch the deployment user's numeric `id -u`. |
| `APP_GID` | GID used by the Immich server, mediæ directory ownership, ænd shæred mode-`0640` secret reæd æccess; mætch the deployment user's primæry numeric `id -g`. |
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
| `IMMICH_TRUSTED_PROXIES` | CIDRs trusted for forwærded client IP heæders; the sæfe defæult is loopbæck-only, so æppend the exæct Træefik `frontend` subnet before deployment. |

### Merged Templæte Væriæbles

`run.sh` merges these service-prefixed templæte vælues into `Immich/.env`. The individuæl templæte REÆDMEs describe them in more detæil.

| Væriæble | Purpose |
| --- | --- |
| `IMMICH_POSTGRES_IMAGE` | Officiæl Immich PostgreSQL 18 compætibility bundle with VectorChord 1.1.1 ænd pgvector 0.8.5. GHCR publishes no moving `:18` or PostgreSQL-18 composite tæg, so the vendor's exæct extension bundle is required. |
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

For æ consistent mænuæl recovery point, use æn externæl operætor-owned
directory, stop the only dætæbæse/mediæ writer, ænd bind the PostgreSQL custom
ærchive, exæctly five storæge ærchives, deployment inputs, source/template
locks, rendered Compose, ænd recoveræble imæge bytes to one completion mærker.
The procedure does not require `.git` in the deployment directory:

Run this block from the repository root.

```bash
set -euo pipefail
umask 077
cd Immich
IMMICH_BACKUP_ROOT=/srv/backups/immich
IMMICH_PROJECT_ROOT="$(pwd -P)"
test "$PWD" = "$IMMICH_PROJECT_ROOT"
test -d "$IMMICH_PROJECT_ROOT" && test ! -L "$IMMICH_PROJECT_ROOT"
test -n "$IMMICH_BACKUP_ROOT" \
  && test "${IMMICH_BACKUP_ROOT#/}" != "$IMMICH_BACKUP_ROOT"
test "$(realpath -m -- "$IMMICH_BACKUP_ROOT")" = "$IMMICH_BACKUP_ROOT"
case "$IMMICH_BACKUP_ROOT/" in "$IMMICH_PROJECT_ROOT/"* ) exit 1 ;; esac
case "$IMMICH_PROJECT_ROOT/" in "$IMMICH_BACKUP_ROOT/"* ) exit 1 ;; esac
IMMICH_BACKUP_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
IMMICH_BACKUP_DIR="${IMMICH_BACKUP_ROOT}/${IMMICH_BACKUP_STAMP}"
install -d -m 0700 "$IMMICH_BACKUP_ROOT"
mkdir -m 0700 "$IMMICH_BACKUP_DIR"
test ! -L "$IMMICH_BACKUP_ROOT" && test -d "$IMMICH_BACKUP_ROOT"
test "$(realpath -e -- "$IMMICH_BACKUP_ROOT")" = "$IMMICH_BACKUP_ROOT"
test "$(stat -Lc %u -- "$IMMICH_BACKUP_ROOT")" = "$(id -u)"
test "$(stat -Lc %a -- "$IMMICH_BACKUP_ROOT")" = 700
IMMICH_PROJECT_ID="$(stat -Lc '%d:%i' -- "$IMMICH_PROJECT_ROOT")"
exec {project_root_fd}<"$IMMICH_PROJECT_ROOT"
test "$(readlink -e -- "/proc/${BASHPID}/fd/${project_root_fd}")" = \
  "$IMMICH_PROJECT_ROOT"
test "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${project_root_fd}")" = \
  "$IMMICH_PROJECT_ID"
flock -n -x "$project_root_fd"
test "$(stat -Lc '%d:%i' -- "$IMMICH_PROJECT_ROOT")" = "$IMMICH_PROJECT_ID"
test -d .run.conf && test ! -L .run.conf
IMMICH_RUN_CONF_ID="$(stat -Lc '%d:%i' -- .run.conf)"
exec {project_lock_fd}<.run.conf
test "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${project_lock_fd}")" = \
  "$IMMICH_RUN_CONF_ID"
flock -n -x "$project_lock_fd"
test ! -L .run.conf
test "$(stat -Lc '%d:%i' -- .run.conf)" = "$IMMICH_RUN_CONF_ID"
printf '%s\n' "$IMMICH_PROJECT_ROOT" > "$IMMICH_BACKUP_DIR/project-root.txt"

test -f .run.conf/.templates.lock && test ! -L .run.conf/.templates.lock
grep -Eq '^([0-9a-f]{40}|[0-9a-f]{64})$' .run.conf/.templates.lock
test "$(wc -l < .run.conf/.templates.lock)" -eq 1
install -m 0600 .run.conf/.templates.lock \
  "$IMMICH_BACKUP_DIR/templates.lock"
if [[ -e .run.conf/.source.lock || -L .run.conf/.source.lock ]]; then
  test -f .run.conf/.source.lock && test ! -L .run.conf/.source.lock
  python3 - .run.conf/.source.lock <<'PY'
import re
import sys

lines = open(sys.argv[1], encoding='ascii').read().splitlines()
if len(lines) != 3 or lines[0] != 'version=1':
    raise SystemExit('malformed source lock')
for key, line in zip(('commit', 'tree'), lines[1:]):
    if not re.fullmatch(fr'{key}=([0-9a-f]{{40}}|[0-9a-f]{{64}})', line):
        raise SystemExit('malformed source lock')
PY
  install -m 0600 .run.conf/.source.lock "$IMMICH_BACKUP_DIR/source.lock"
  printf '%s\n' 'mode=source-lock' > "$IMMICH_BACKUP_DIR/source-evidence.txt"
else
  printf '%s\n' 'mode=deployment-inputs-only' \
    > "$IMMICH_BACKUP_DIR/source-evidence.txt"
fi

env -i PATH="$PATH" docker compose --env-file .env \
  -f docker-compose.main.yaml config \
  > "$IMMICH_BACKUP_DIR/rendered-compose.yaml"
env -i PATH="$PATH" docker compose --env-file .env \
  -f docker-compose.main.yaml config --format json \
  > "$IMMICH_BACKUP_DIR/rendered-compose.json"
rendered_project_name="$(python3 - \
  "$IMMICH_BACKUP_DIR/rendered-compose.json" <<'PY'
import json
import sys

name = json.load(open(sys.argv[1], encoding='utf-8')).get('name')
if not isinstance(name, str) or not name or any(char in name for char in '\t\r\n'):
    raise SystemExit('rendered Compose project name is invalid')
print(name)
PY
)"
clean_compose=(env -i PATH="$PATH" docker compose \
  --project-directory "$IMMICH_PROJECT_ROOT" \
  --project-name "$rendered_project_name" \
  --env-file "$IMMICH_PROJECT_ROOT/.env" \
  -f "$IMMICH_PROJECT_ROOT/docker-compose.main.yaml")
compose=(docker compose --project-directory "$IMMICH_PROJECT_ROOT" \
  --project-name "$rendered_project_name" \
  --env-file "$IMMICH_PROJECT_ROOT/.env" \
  -f "$IMMICH_PROJECT_ROOT/docker-compose.main.yaml")
python3 - "$IMMICH_BACKUP_DIR/rendered-compose.json" \
  "$IMMICH_PROJECT_ROOT" "$IMMICH_BACKUP_ROOT" \
  > "$IMMICH_BACKUP_DIR/media-paths.tsv" <<'PY'
import json
import os
from pathlib import Path
import stat
import sys

wanted = {
    '/data': 'upload',
    '/data/thumbs': 'thumbs',
    '/data/encoded-video': 'encoded-video',
    '/data/profile': 'profile',
    '/data/backups': 'backups',
}
document = json.load(open(sys.argv[1], encoding='utf-8'))
project_root = os.path.realpath(sys.argv[2])
backup_root = os.path.realpath(sys.argv[3])
protected = [os.path.realpath(path) for path in (
    'scripts', 'secrets', '.run.conf', 'app.env', '.env',
    'docker-compose.main.yaml', 'docker-compose.app.yaml',
) if os.path.lexists(path)]
volumes = document['services']['app']['volumes']
selected = {}
for volume in volumes:
    target = volume.get('target')
    if target not in wanted:
        continue
    if target in selected or volume.get('type') != 'bind':
        raise SystemExit(f'invalid or duplicate media mount: {target!r}')
    source = volume.get('source', '')
    if not os.path.isabs(source) or any(char in source for char in '\t\r\n'):
        raise SystemExit(f'non-canonical media source: {source!r}')
    if '..' in source.split(os.sep) or os.path.normpath(source) != source:
        raise SystemExit(f'non-canonical media source: {source!r}')
    absolute = os.path.abspath(source)
    canonical = os.path.realpath(source)
    if absolute != canonical:
        raise SystemExit(f'media source traverses a symlink: {source!r}')
    if canonical == project_root \
            or os.path.commonpath((canonical, project_root)) == canonical:
        raise SystemExit(f'media source contains the project root: {source!r}')
    if os.path.commonpath((canonical, backup_root)) in (canonical, backup_root):
        raise SystemExit(f'media source overlaps the recovery root: {source!r}')
    for deployment_path in protected:
        if os.path.commonpath((canonical, deployment_path)) in \
                (canonical, deployment_path):
            raise SystemExit(
                f'media source overlaps deployment input: {source!r}')
    info = os.lstat(source)
    if not stat.S_ISDIR(info.st_mode):
        raise SystemExit(f'media source is not a directory: {source!r}')
    marker_path = Path(source) / '.immich'
    marker = os.lstat(marker_path)
    if not stat.S_ISREG(marker.st_mode) or marker.st_nlink != 1:
        raise SystemExit(f'invalid .immich marker: {marker_path!s}')
    selected[target] = (canonical, info, marker)
if set(selected) != set(wanted):
    raise SystemExit(f'expected exactly five media mounts, got {sorted(selected)}')
paths = [selected[target][0] for target in wanted]
identities = [(selected[target][1].st_dev, selected[target][1].st_ino)
              for target in wanted]
if len(set(paths)) != 5 or len(set(identities)) != 5:
    raise SystemExit('media sources must be canonical and unique')
for index, first in enumerate(paths):
    for second in paths[index + 1:]:
        if os.path.commonpath((first, second)) in (first, second):
            raise SystemExit('media sources must not be ancestors or descendants')
for target, label in wanted.items():
    source, info, marker = selected[target]
    print(label, target, source, info.st_dev, info.st_ino,
          marker.st_dev, marker.st_ino, sep='\t')
PY

services_output="$("${clean_compose[@]}" config --services)"
mapfile -t services <<< "$services_output"
test "${#services[@]}" -gt 0
declare -A seen_services=()
declare -A service_containers=()
declare -a image_refs=()
: > "$IMMICH_BACKUP_DIR/image-map.tsv.partial"
for service in "${services[@]}"; do
  test -n "$service" && test -z "${seen_services[$service]+set}"
  seen_services[$service]=1
  containers_output="$(docker ps -aq \
    --filter "label=com.docker.compose.project=$rendered_project_name" \
    --filter "label=com.docker.compose.service=$service")"
  mapfile -t containers <<< "$containers_output"
  test "${#containers[@]}" -eq 1
  test -n "${containers[0]}"
  service_containers[$service]="${containers[0]}"
  test "$(docker inspect -f \
    '{{index .Config.Labels "com.docker.compose.project"}}' \
    "${containers[0]}")" = "$rendered_project_name"
  test "$(docker inspect -f \
    '{{index .Config.Labels "com.docker.compose.service"}}' \
    "${containers[0]}")" = "$service"
  image_ref="$(docker inspect -f '{{.Config.Image}}' "${containers[0]}")"
  image_id="$(docker inspect -f '{{.Image}}' "${containers[0]}")"
  container_config_hash="$(docker inspect -f \
    '{{index .Config.Labels "com.docker.compose.config-hash"}}' \
    "${containers[0]}")"
  [[ "$container_config_hash" =~ ^[0-9a-f]{64}$ ]]
  config_hash_override="$IMMICH_BACKUP_DIR/.config-hash-image-override.json"
  python3 - "$service" "$image_ref" "$config_hash_override" <<'PY'
import json
import sys

with open(sys.argv[3], 'w', encoding='utf-8') as stream:
    json.dump({'services': {sys.argv[1]: {'image': sys.argv[2]}}}, stream)
PY
  expected_config_hash_line="$("${clean_compose[@]}" \
    -f "$config_hash_override" config --hash "$service")"
  case "$expected_config_hash_line" in
    "$service "*) ;;
    *) printf 'invalid Compose config-hash output for %s\n' "$service" >&2
       exit 1 ;;
  esac
  expected_config_hash="${expected_config_hash_line#"$service "}"
  [[ "$expected_config_hash" =~ ^[0-9a-f]{64}$ ]]
  test "$expected_config_hash" = "$container_config_hash"
  rm -- "$config_hash_override"
  test "$(docker image inspect -f '{{.Id}}' "$image_ref")" = "$image_id"
  printf '%s\t%s\t%s\n' "$service" "$image_ref" "$image_id" \
    >> "$IMMICH_BACKUP_DIR/image-map.tsv.partial"
  image_refs+=("$image_ref")
done
project_containers_output="$(docker ps -aq \
  --filter "label=com.docker.compose.project=$rendered_project_name")"
mapfile -t project_containers <<< "$project_containers_output"
test "${#project_containers[@]}" -eq "${#services[@]}"
for container_id in "${project_containers[@]}"; do
  test -n "$container_id"
  container_service="$(docker inspect -f \
    '{{index .Config.Labels "com.docker.compose.service"}}' "$container_id")"
  test -n "${seen_services[$container_service]+set}"
  test "${service_containers[$container_service]}" = "$container_id"
done
runtime_yaml="$IMMICH_BACKUP_DIR/.runtime-compose.yaml"
runtime_json="$IMMICH_BACKUP_DIR/.runtime-compose.json"
"${compose[@]}" config > "$runtime_yaml"
"${compose[@]}" config --format json > "$runtime_json"
cmp -- "$IMMICH_BACKUP_DIR/rendered-compose.yaml" "$runtime_yaml"
cmp -- "$IMMICH_BACKUP_DIR/rendered-compose.json" "$runtime_json"
rm -- "$runtime_yaml" "$runtime_json"
docker network inspect frontend backend \
  > "$IMMICH_BACKUP_DIR/.network-inspect.json"
python3 - "$IMMICH_BACKUP_DIR/rendered-compose.json" \
  "$IMMICH_BACKUP_DIR/.network-inspect.json" frontend backend \
  > "$IMMICH_BACKUP_DIR/network-evidence.tsv.partial" <<'PY'
import ipaddress
import json
import sys

compose = json.load(open(sys.argv[1], encoding='utf-8'))
inspected = json.load(open(sys.argv[2], encoding='utf-8'))
expected = sys.argv[3:]
networks = compose.get('networks', {})
if set(networks) != set(expected) or len(expected) != len(set(expected)):
    raise SystemExit('rendered external-network closure differs')
by_name = {item.get('Name'): item for item in inspected}
if set(by_name) != set(expected) or len(inspected) != len(by_name):
    raise SystemExit('inspected external-network closure differs')
for key in expected:
    definition = networks[key]
    if definition.get('external') is not True or definition.get('name') != key:
        raise SystemExit(f'external network key/name drift: {key!r}')
    item = by_name[key]
    if item.get('Driver') != 'bridge' or item.get('Scope') != 'local':
        raise SystemExit(f'unsupported external network driver/scope: {key!r}')
    if any(item.get(field) for field in
           ('Internal', 'Attachable', 'Ingress', 'ConfigOnly', 'EnableIPv6')):
        raise SystemExit(f'unsupported external network mode: {key!r}')
    if item.get('Options') not in ({}, None):
        raise SystemExit(f'unsupported external network options: {key!r}')
    ipam = item.get('IPAM', {})
    if ipam.get('Driver') != 'default' or ipam.get('Options') not in ({}, None):
        raise SystemExit(f'unsupported external network IPAM: {key!r}')
    configs = ipam.get('Config', [])
    if len(configs) != 1:
        raise SystemExit(f'external network needs exactly one subnet: {key!r}')
    config = configs[0]
    if config.get('IPRange') not in (None, '') \
            or config.get('AuxiliaryAddresses') not in (None, {}):
        raise SystemExit(f'unsupported external network IPAM detail: {key!r}')
    subnet = ipaddress.ip_network(config.get('Subnet', ''), strict=True)
    gateway = ipaddress.ip_address(config.get('Gateway', ''))
    if gateway.version != subnet.version or gateway not in subnet:
        raise SystemExit(f'external network gateway is outside subnet: {key!r}')
    print(key, key, 'bridge', subnet, gateway, sep='\t')
PY
rm -- "$IMMICH_BACKUP_DIR/.network-inspect.json"
mv "$IMMICH_BACKUP_DIR/network-evidence.tsv.partial" \
  "$IMMICH_BACKUP_DIR/network-evidence.tsv"
docker version --format '{{.Server.Os}}\t{{.Server.Arch}}' \
  > "$IMMICH_BACKUP_DIR/engine-platform.tsv.partial"
test "$(wc -l < "$IMMICH_BACKUP_DIR/engine-platform.tsv.partial")" -eq 1
case "$(<"$IMMICH_BACKUP_DIR/engine-platform.tsv.partial")" in
  $'linux\tamd64'|$'linux\tarm64') ;;
  *) exit 1 ;;
esac
mv "$IMMICH_BACKUP_DIR/engine-platform.tsv.partial" \
  "$IMMICH_BACKUP_DIR/engine-platform.tsv"

"${compose[@]}" stop app
"${compose[@]}" exec -T \
  immich-postgres sh -ec \
  'exec pg_dump --format=custom --clean --if-exists --dbname="$POSTGRES_DB" --username="$POSTGRES_USER"' \
  > "$IMMICH_BACKUP_DIR/immich-database.dump.partial"
"${compose[@]}" exec -T \
  immich-postgres pg_restore --list \
  < "$IMMICH_BACKUP_DIR/immich-database.dump.partial" >/dev/null
mv "$IMMICH_BACKUP_DIR/immich-database.dump.partial" \
  "$IMMICH_BACKUP_DIR/immich-database.dump"

image_refs_output="$(printf '%s\n' "${image_refs[@]}" | LC_ALL=C sort -u)"
mapfile -t image_refs <<< "$image_refs_output"
docker image save --output "$IMMICH_BACKUP_DIR/images.tar.partial" \
  "${image_refs[@]}"
while IFS=$'\t' read -r service image_ref image_id; do
  test "$(docker image inspect -f '{{.Id}}' "$image_ref")" = "$image_id"
  test "$(docker inspect -f '{{.Image}}' \
    "${service_containers[$service]}")" = "$image_id"
done < "$IMMICH_BACKUP_DIR/image-map.tsv.partial"

python3 - "$IMMICH_BACKUP_DIR/rendered-compose.json" <<'PY'
import json
import os
import sys

document = json.load(open(sys.argv[1], encoding='utf-8'))
for service, definition in document['services'].items():
    build = definition.get('build')
    if build:
        raise SystemExit(f'unarchived local build context for {service}: {build!r}')
PY
tar --acls --xattrs --numeric-owner \
  -cpf "$IMMICH_BACKUP_DIR/deployment-inputs.tar.partial" \
  app.env .env docker-compose.main.yaml docker-compose.app.yaml \
  scripts secrets
python3 - "$IMMICH_BACKUP_DIR/deployment-inputs.tar.partial" <<'PY'
from pathlib import PurePosixPath
import sys
import tarfile

allowed = {
    'app.env', '.env', 'docker-compose.main.yaml',
    'docker-compose.app.yaml', 'scripts', 'secrets',
}
seen = set()
found = set()
with tarfile.open(sys.argv[1], 'r:') as archive:
    for member in archive:
        path = PurePosixPath(member.name)
        if path.is_absolute() or not path.parts or '..' in path.parts:
            raise SystemExit(f'unsafe deployment path: {member.name!r}')
        normalized = path.as_posix().rstrip('/')
        if normalized in seen:
            raise SystemExit(f'duplicate deployment member: {member.name!r}')
        seen.add(normalized)
        root = path.parts[0]
        if root not in allowed:
            raise SystemExit(f'unexpected deployment root: {member.name!r}')
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f'unsafe deployment member type: {member.name!r}')
        found.add(root)
if found != allowed:
    raise SystemExit(f'incomplete deployment roots: {sorted(allowed - found)}')
PY

: > "$IMMICH_BACKUP_DIR/media-manifest.tsv.partial"
findmnt --json --output TARGET > "$IMMICH_BACKUP_DIR/host-mounts.json"
python3 - "$IMMICH_BACKUP_DIR/host-mounts.json" \
  "$IMMICH_BACKUP_DIR/media-paths.tsv" <<'PY'
import json
import os
import sys

document = json.load(open(sys.argv[1], encoding='utf-8'))
sources = [line.split('\t')[2] for line in
           open(sys.argv[2], encoding='utf-8').read().splitlines()]
stack = list(document.get('filesystems', []))
targets = []
while stack:
    node = stack.pop()
    stack.extend(node.get('children', []))
    target = node.get('target')
    if target and os.path.isabs(target):
        targets.append(os.path.realpath(target))
for source in sources:
    for target in targets:
        if target != source and os.path.commonpath((source, target)) == source:
            raise SystemExit(f'nested mount below Immich media path: {target!r}')
PY
while IFS=$'\t' read -r label target source source_dev source_ino \
    marker_dev marker_ino; do
  test "$(realpath -e -- "$source")" = "$source"
  test ! -L "$source" && test -d "$source"
  test "$(stat -Lc '%d:%i' -- "$source")" = "${source_dev}:${source_ino}"
  test -f "$source/.immich" && test ! -L "$source/.immich"
  test "$(stat -Lc '%d:%i' -- "$source/.immich")" = \
    "${marker_dev}:${marker_ino}"
  test "$(stat -Lc '%h' -- "$source/.immich")" -eq 1
  media_archive="media-${label}.tar"
  tar --acls --xattrs --numeric-owner \
    -cpf "$IMMICH_BACKUP_DIR/${media_archive}.partial" -C "$source" .
  python3 - "$IMMICH_BACKUP_DIR/${media_archive}.partial" <<'PY'
import posixpath
import sys
import tarfile

seen = set()
marker = False
with tarfile.open(sys.argv[1], 'r:') as archive:
    for member in archive:
        raw = member.name
        if raw == '.':
            normalized = '.'
        elif raw.startswith('./'):
            relative = raw[2:]
            if any(part in ('', '.', '..') for part in relative.split('/')):
                raise SystemExit(f'non-canonical media path: {raw!r}')
            normalized = posixpath.normpath(relative)
        else:
            raise SystemExit(f'non-staged media path: {raw!r}')
        if normalized == '..' or normalized.startswith('../') \
                or posixpath.isabs(normalized):
            raise SystemExit(f'unsafe media path: {raw!r}')
        if normalized in seen:
            raise SystemExit(f'duplicate media member: {raw!r}')
        seen.add(normalized)
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f'unsafe media member type: {raw!r}')
        if normalized == '.immich':
            if not member.isfile():
                raise SystemExit('.immich marker is not a regular file')
            marker = True
if not marker:
    raise SystemExit('media archive lacks .immich marker')
PY
  sync "$IMMICH_BACKUP_DIR/${media_archive}.partial"
  mv "$IMMICH_BACKUP_DIR/${media_archive}.partial" \
    "$IMMICH_BACKUP_DIR/$media_archive"
  archive_sha="$(sha256sum "$IMMICH_BACKUP_DIR/$media_archive")"
  archive_sha="${archive_sha%% *}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$label" "$target" "$source" "$source_dev:$source_ino" \
    "$media_archive" "$archive_sha" \
    >> "$IMMICH_BACKUP_DIR/media-manifest.tsv.partial"
done < "$IMMICH_BACKUP_DIR/media-paths.tsv"
test "$(wc -l < "$IMMICH_BACKUP_DIR/media-manifest.tsv.partial")" -eq 5

sync "$IMMICH_BACKUP_DIR/deployment-inputs.tar.partial" \
  "$IMMICH_BACKUP_DIR/images.tar.partial"
mv "$IMMICH_BACKUP_DIR/deployment-inputs.tar.partial" \
  "$IMMICH_BACKUP_DIR/deployment-inputs.tar"
mv "$IMMICH_BACKUP_DIR/images.tar.partial" "$IMMICH_BACKUP_DIR/images.tar"
mv "$IMMICH_BACKUP_DIR/image-map.tsv.partial" \
  "$IMMICH_BACKUP_DIR/image-map.tsv"
mv "$IMMICH_BACKUP_DIR/media-manifest.tsv.partial" \
  "$IMMICH_BACKUP_DIR/media-manifest.tsv"
(cd "$IMMICH_BACKUP_DIR" && sha256sum \
  immich-database.dump deployment-inputs.tar images.tar image-map.tsv \
  rendered-compose.yaml rendered-compose.json media-paths.tsv host-mounts.json \
  media-manifest.tsv network-evidence.tsv engine-platform.tsv \
  project-root.txt source-evidence.txt templates.lock \
  > recovery-manifest.sha256.partial)
if [[ -f "$IMMICH_BACKUP_DIR/source.lock" ]]; then
  (cd "$IMMICH_BACKUP_DIR" && sha256sum source.lock \
    >> recovery-manifest.sha256.partial)
fi
while IFS=$'\t' read -r label target source source_identity \
    media_archive archive_sha; do
  test "$(sha256sum "$IMMICH_BACKUP_DIR/$media_archive" | cut -d' ' -f1)" = \
    "$archive_sha"
done < "$IMMICH_BACKUP_DIR/media-manifest.tsv"
mv "$IMMICH_BACKUP_DIR/recovery-manifest.sha256.partial" \
  "$IMMICH_BACKUP_DIR/recovery-manifest.sha256"
python3 - "$IMMICH_BACKUP_DIR" "$IMMICH_BACKUP_ROOT" <<'PY'
import os
import stat
import sys

for root, directories, files in os.walk(sys.argv[1], topdown=False, followlinks=False):
    for name in files:
        path = os.path.join(root, name)
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise SystemExit(f'non-regular recovery artifact: {path!r}')
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
descriptor = os.open(sys.argv[2], os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try:
    os.fsync(descriptor)
finally:
    os.close(descriptor)
PY
(cd "$IMMICH_BACKUP_DIR" && sha256sum recovery-manifest.sha256 \
  > recovery-point.complete.partial)
mv "$IMMICH_BACKUP_DIR/recovery-point.complete.partial" \
  "$IMMICH_BACKUP_DIR/recovery-point.complete"
python3 - "$IMMICH_BACKUP_DIR/recovery-point.complete" \
  "$IMMICH_BACKUP_DIR" "$IMMICH_BACKUP_ROOT" <<'PY'
import os
import sys

for path in sys.argv[1:]:
    flags = os.O_RDONLY | os.O_NOFOLLOW
    if os.path.isdir(path):
        flags |= os.O_DIRECTORY
    descriptor = os.open(path, flags)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
PY

# Only after the complete recovery directory is verified off-host:
"${compose[@]}" up -d \
  --no-build --pull never --wait --wait-timeout 300 app
```

The five mænifest rows correspond exæctly to `/data`, `/data/thumbs`,
`/data/encoded-video`, `/data/profile`, ænd `/data/backups`. Cænonicæl-pæth,
directory, uniqueness, inode, non-symlink, ænd regulær single-link `.immich`
checks run before ænd æfter the writer stops. Every newly creæted pærtiæl tær
is rejected before completion if it contæins æ duplicæte, link, device, FIFO,
socket, unexpected pæth, or no mærker. If the server cænnot be stopped, there
is no equivælent ætomic recovery point; læbel such æ copy cræsh-consistent
only. The recovery-only externæl-network override keeps the checksummed
frontend/backend subnets required by the trusted-proxy policy, uses new
no-clobber næmes, ænd proves the exæct restored service-member closure.
The OCI ærchive is plætform-specific: `engine-platform.tsv` requires the sæme
Linux Docker-server ærchitecture, ænd `amd64` recovery still requires
Immich's documented `x86-64-v2` CPU level; `arm64` is the other supported
ærchitecture.
ænd do not use it æs releæse evidence.

This runbook intentionælly supports only æ **fresh isolæted recovery host**.
It refuses æn existing project directory or configured mediæ pæth, ænd the
selected dedicæted Docker context must contæin no contæiner, imæge, or volume.
Therefore æ pærtiæl imæge loæd or fæiled dætæbæse/media recovery cænnot mutæte
æn æctive tæg or expose æ mixed generætion to production: the whole isolæted
host is discærded before retry. Æn in-plæce restore needs æ sepærætely tested
dætæbæse-clone plus five-pæth duræble rollbæck trænsæction; this document does
not clæim one. Network creætion intentionælly precedes the Compose `ERR` træp:
æ pærtiæl recovery-network set is not reconciled ænd requires immediæte host
discærd.

Restore the ærchived project æt the exæct cænonicæl pæth recorded by the
bæckup so æ cleæn render cæn compære byte-for-byte with sæved Compose. Vælidæte
the deployment tær first, creæte the æbsent project directory, extræct there,
instæll the ærchived locks, ænd æcquire the sæme project locks æs `run.sh`:

```bash
set -euo pipefail
umask 077
IMMICH_BACKUP_DIR=/srv/backups/immich/YYYYMMDDTHHMMSSZ
IMMICH_BACKUP_DIR="$(realpath -e -- "$IMMICH_BACKUP_DIR")"
test -d "$IMMICH_BACKUP_DIR" && test ! -L "$IMMICH_BACKUP_DIR"
test "$(stat -Lc %u -- "$IMMICH_BACKUP_DIR")" = "$(id -u)"
test "$(stat -Lc %a -- "$IMMICH_BACKUP_DIR")" = 700
exec {recovery_lock_fd}<"$IMMICH_BACKUP_DIR"
flock -n -s "$recovery_lock_fd"
test -f "$IMMICH_BACKUP_DIR/recovery-point.complete"
(cd "$IMMICH_BACKUP_DIR" && sha256sum -c recovery-point.complete)
(cd "$IMMICH_BACKUP_DIR" && sha256sum -c recovery-manifest.sha256)
saved_engine_platform="$(<"$IMMICH_BACKUP_DIR/engine-platform.tsv")"
case "$saved_engine_platform" in
  $'linux\tamd64'|$'linux\tarm64') ;;
  *) exit 1 ;;
esac
test "$(docker version --format '{{.Server.Os}}\t{{.Server.Arch}}')" = \
  "$saved_engine_platform"
source_mode="$(<"$IMMICH_BACKUP_DIR/source-evidence.txt")"
case "$source_mode" in
  mode=source-lock)
    test -f "$IMMICH_BACKUP_DIR/source.lock" \
      && test ! -L "$IMMICH_BACKUP_DIR/source.lock"
    test "$(grep -Fxc '  source.lock' \
      "$IMMICH_BACKUP_DIR/recovery-manifest.sha256")" -eq 1
    ;;
  mode=deployment-inputs-only)
    test ! -e "$IMMICH_BACKUP_DIR/source.lock" \
      && test ! -L "$IMMICH_BACKUP_DIR/source.lock"
    test "$(grep -Fc '  source.lock' \
      "$IMMICH_BACKUP_DIR/recovery-manifest.sha256")" -eq 0
    ;;
  *) exit 1 ;;
esac
python3 - "$IMMICH_BACKUP_DIR/rendered-compose.json" \
  "$IMMICH_BACKUP_DIR/image-map.tsv" <<'PY'
import json
import re
import sys

services = set(json.load(open(sys.argv[1], encoding='utf-8'))['services'])
rows = [line.split('\t') for line in
        open(sys.argv[2], encoding='utf-8').read().splitlines()]
if len(rows) != len(services) or any(len(row) != 3 for row in rows):
    raise SystemExit('image map is not an exact service closure')
mapped = [row[0] for row in rows]
if set(mapped) != services or len(set(mapped)) != len(mapped):
    raise SystemExit('image map services are missing, extra, or duplicated')
references = {}
for service, reference, image_id in rows:
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', service):
        raise SystemExit(f'unsafe service in image map: {service!r}')
    if not reference or any(char.isspace() or ord(char) < 32 for char in reference):
        raise SystemExit(f'unsafe reference in image map: {reference!r}')
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', image_id):
        raise SystemExit(f'invalid image ID for {service!r}')
    previous = references.setdefault(reference, image_id)
    if previous != image_id:
        raise SystemExit(f'one image reference maps to multiple IDs: {reference!r}')
PY
python3 - "$IMMICH_BACKUP_DIR/deployment-inputs.tar" <<'PY'
from pathlib import PurePosixPath
import sys
import tarfile

allowed = {
    'app.env', '.env', 'docker-compose.main.yaml',
    'docker-compose.app.yaml', 'scripts', 'secrets',
}
seen = set()
found = set()
with tarfile.open(sys.argv[1], 'r:') as archive:
    for member in archive:
        path = PurePosixPath(member.name)
        if path.is_absolute() or not path.parts or '..' in path.parts:
            raise SystemExit(f'unsafe deployment path: {member.name!r}')
        normalized = path.as_posix().rstrip('/')
        if normalized in seen:
            raise SystemExit(f'duplicate deployment member: {member.name!r}')
        seen.add(normalized)
        root = path.parts[0]
        if root not in allowed:
            raise SystemExit(f'unexpected deployment root: {member.name!r}')
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f'unsafe deployment member type: {member.name!r}')
        found.add(root)
if found != allowed:
    raise SystemExit(f'incomplete deployment roots: {sorted(allowed - found)}')
PY
IMMICH_PROJECT_ROOT="$(<"$IMMICH_BACKUP_DIR/project-root.txt")"
test -n "$IMMICH_PROJECT_ROOT" && test "${IMMICH_PROJECT_ROOT#/}" != \
  "$IMMICH_PROJECT_ROOT"
test "$(realpath -m -- "$IMMICH_PROJECT_ROOT")" = "$IMMICH_PROJECT_ROOT"
case "$IMMICH_BACKUP_DIR/" in "$IMMICH_PROJECT_ROOT/"* ) exit 1 ;; esac
case "$IMMICH_PROJECT_ROOT/" in "$IMMICH_BACKUP_DIR/"* ) exit 1 ;; esac
test ! -e "$IMMICH_PROJECT_ROOT" && test ! -L "$IMMICH_PROJECT_ROOT"
IMMICH_PROJECT_PARENT="$(dirname -- "$IMMICH_PROJECT_ROOT")"
test -d "$IMMICH_PROJECT_PARENT" && test ! -L "$IMMICH_PROJECT_PARENT"
test "$(realpath -e -- "$IMMICH_PROJECT_PARENT")" = "$IMMICH_PROJECT_PARENT"

# This fresh-host boundary runs before project, image, volume, or media mutation.
container_inventory="$(docker ps -aq)"
image_inventory="$(docker image ls -aq)"
volume_inventory="$(docker volume ls -q)"
test -z "$container_inventory"
test -z "$image_inventory"
test -z "$volume_inventory"
python3 - "$IMMICH_BACKUP_DIR/media-manifest.tsv" \
  "$IMMICH_PROJECT_ROOT" "$IMMICH_BACKUP_DIR" <<'PY'
import os
import re
import sys

rows = [line.split('\t') for line in
        open(sys.argv[1], encoding='utf-8').read().splitlines()]
project_root = sys.argv[2]
recovery_point = sys.argv[3]
expected = {
    ('upload', '/data'), ('thumbs', '/data/thumbs'),
    ('encoded-video', '/data/encoded-video'), ('profile', '/data/profile'),
    ('backups', '/data/backups'),
}
if len(rows) != 5 or {tuple(row[:2]) for row in rows} != expected:
    raise SystemExit('media manifest is not the exact five-path contract')
if any(len(row) != 6 or not re.fullmatch(r'[0-9a-f]{64}', row[5])
       for row in rows):
    raise SystemExit('malformed media manifest row')
paths = [row[2] for row in rows]
if len(set(paths)) != 5 or len({row[3] for row in rows}) != 5:
    raise SystemExit('media manifest paths or identities are not unique')
protected = [
    os.path.join(project_root, item) for item in
    ('scripts', 'secrets', '.run.conf', 'app.env', '.env',
     'docker-compose.main.yaml', 'docker-compose.app.yaml')
]
for path in paths:
    if not os.path.isabs(path) or any(char in path for char in '\t\r\n'):
        raise SystemExit('unsafe media target path')
    if os.path.normpath(path) != path or '..' in path.split(os.sep):
        raise SystemExit('non-canonical media target path')
    if os.path.lexists(path):
        raise SystemExit(f'media target already exists: {path!r}')
    if path == project_root or os.path.commonpath((path, project_root)) == path:
        raise SystemExit('media target contains the project root')
    if os.path.commonpath((path, recovery_point)) in (path, recovery_point):
        raise SystemExit('media target overlaps the recovery point')
    for deployment_path in protected:
        if os.path.commonpath((path, deployment_path)) in \
                (path, deployment_path):
            raise SystemExit('media target overlaps deployment input')
for index, first in enumerate(paths):
    for second in paths[index + 1:]:
        if os.path.commonpath((first, second)) in (first, second):
            raise SystemExit('media target paths overlap')
PY
mkdir -m 0700 "$IMMICH_PROJECT_ROOT"
tar --acls --xattrs --numeric-owner -xpf \
  "$IMMICH_BACKUP_DIR/deployment-inputs.tar" -C "$IMMICH_PROJECT_ROOT"
cd "$IMMICH_PROJECT_ROOT"
mkdir -m 0700 .run.conf
install -m 0600 "$IMMICH_BACKUP_DIR/templates.lock" \
  .run.conf/.templates.lock
if [[ -f "$IMMICH_BACKUP_DIR/source.lock" ]]; then
  install -m 0600 "$IMMICH_BACKUP_DIR/source.lock" .run.conf/.source.lock
fi

IMMICH_PROJECT_ID="$(stat -Lc '%d:%i' -- "$IMMICH_PROJECT_ROOT")"
exec {project_root_fd}<"$IMMICH_PROJECT_ROOT"
test "$(readlink -e -- "/proc/${BASHPID}/fd/${project_root_fd}")" = \
  "$IMMICH_PROJECT_ROOT"
test "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${project_root_fd}")" = \
  "$IMMICH_PROJECT_ID"
flock -n -x "$project_root_fd"
test "$(stat -Lc '%d:%i' -- "$IMMICH_PROJECT_ROOT")" = "$IMMICH_PROJECT_ID"
IMMICH_RUN_CONF_ID="$(stat -Lc '%d:%i' -- .run.conf)"
exec {project_lock_fd}<.run.conf
test "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${project_lock_fd}")" = \
  "$IMMICH_RUN_CONF_ID"
flock -n -x "$project_lock_fd"
test ! -L .run.conf
test "$(stat -Lc '%d:%i' -- .run.conf)" = "$IMMICH_RUN_CONF_ID"

clean_rendered_yaml="$(mktemp .run.conf/immich-rendered.XXXXXX.yaml)"
clean_rendered_json="$(mktemp .run.conf/immich-rendered.XXXXXX.json)"
env -i PATH="$PATH" docker compose --env-file .env \
  -f docker-compose.main.yaml config > "$clean_rendered_yaml"
env -i PATH="$PATH" docker compose --env-file .env \
  -f docker-compose.main.yaml config --format json > "$clean_rendered_json"
cmp -- "$IMMICH_BACKUP_DIR/rendered-compose.yaml" "$clean_rendered_yaml"
cmp -- "$IMMICH_BACKUP_DIR/rendered-compose.json" "$clean_rendered_json"
rendered_project_name="$(python3 - "$clean_rendered_json" <<'PY'
import json
import sys

name = json.load(open(sys.argv[1], encoding='utf-8')).get('name')
if not isinstance(name, str) or not name or any(char in name for char in '\t\r\n'):
    raise SystemExit('rendered Compose project name is invalid')
print(name)
PY
)"
runtime_compose=(docker compose --project-directory "$IMMICH_PROJECT_ROOT" \
  --project-name "$rendered_project_name" \
  --env-file "$IMMICH_PROJECT_ROOT/.env" \
  -f "$IMMICH_PROJECT_ROOT/docker-compose.main.yaml")
runtime_yaml="$(mktemp .run.conf/immich-runtime.XXXXXX.yaml)"
runtime_json="$(mktemp .run.conf/immich-runtime.XXXXXX.json)"
"${runtime_compose[@]}" config > "$runtime_yaml"
"${runtime_compose[@]}" config --format json > "$runtime_json"
cmp -- "$clean_rendered_yaml" "$runtime_yaml"
cmp -- "$clean_rendered_json" "$runtime_json"
rm -- "$runtime_yaml" "$runtime_json"

python3 - "$IMMICH_PROJECT_ROOT" "$IMMICH_PROJECT_PARENT" <<'PY'
import os
import stat
import sys

for root, directories, files in os.walk(sys.argv[1], topdown=False,
                                        followlinks=False):
    for name in files:
        path = os.path.join(root, name)
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise SystemExit(f'non-regular project artifact: {path!r}')
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
descriptor = os.open(sys.argv[2], os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try:
    os.fsync(descriptor)
finally:
    os.close(descriptor)
PY

IMMICH_RESTORE_STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
IMMICH_MEDIA_JOURNAL=".run.conf/immich-media.${IMMICH_RESTORE_STAMP}.journal"
test ! -e "$IMMICH_MEDIA_JOURNAL" && test ! -L "$IMMICH_MEDIA_JOURNAL"
printf '%s\n' 'version=1' 'state=staging' > "$IMMICH_MEDIA_JOURNAL"
fsync_recovery_metadata() {
  python3 - "$@" .run.conf <<'PY'
import os
import sys

for path in sys.argv[1:]:
    flags = os.O_RDONLY | os.O_NOFOLLOW
    if os.path.isdir(path):
        flags |= os.O_DIRECTORY
    descriptor = os.open(path, flags)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
PY
}
fsync_recovery_metadata "$IMMICH_MEDIA_JOURNAL"
while IFS=$'\t' read -r label target source source_identity \
    media_archive archive_sha; do
  test "$(sha256sum "$IMMICH_BACKUP_DIR/$media_archive" | cut -d' ' -f1)" = \
    "$archive_sha"
  python3 - "$IMMICH_BACKUP_DIR/$media_archive" <<'PY'
import posixpath
import sys
import tarfile

seen = set()
marker = False
with tarfile.open(sys.argv[1], 'r:') as archive:
    for member in archive:
        raw = member.name
        if raw == '.':
            normalized = '.'
        elif raw.startswith('./'):
            relative = raw[2:]
            if any(part in ('', '.', '..') for part in relative.split('/')):
                raise SystemExit(f'non-canonical media path: {raw!r}')
            normalized = posixpath.normpath(relative)
        else:
            raise SystemExit(f'non-staged media path: {raw!r}')
        if normalized == '..' or normalized.startswith('../') \
                or posixpath.isabs(normalized) or normalized in seen:
            raise SystemExit(f'unsafe or duplicate media member: {raw!r}')
        seen.add(normalized)
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f'unsafe media member type: {raw!r}')
        if normalized == '.immich':
            if not member.isfile():
                raise SystemExit('.immich marker is not a regular file')
            marker = True
if not marker:
    raise SystemExit('media archive lacks .immich marker')
PY
  test "$(realpath -m -- "$source")" = "$source"
  test ! -e "$source" && test ! -L "$source"
  media_parent="$(dirname -- "$source")"
  if [[ ! -e "$media_parent" && ! -L "$media_parent" ]]; then
    media_grandparent="$(dirname -- "$media_parent")"
    test -d "$media_grandparent" && test ! -L "$media_grandparent"
    mkdir -m 0700 "$media_parent"
    python3 - "$media_parent" "$media_grandparent" <<'PY'
import os
import sys

for path in sys.argv[1:]:
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
PY
  fi
  test -d "$media_parent"
  test ! -L "$media_parent"
  test "$(realpath -e -- "$media_parent")" = "$media_parent"
  stage="${source}.immich-restore-${IMMICH_RESTORE_STAMP}"
  test ! -e "$stage" && test ! -L "$stage"
  mkdir -m 0700 "$stage"
  tar --acls --xattrs --numeric-owner -xpf \
    "$IMMICH_BACKUP_DIR/$media_archive" -C "$stage"
  test -f "$stage/.immich" && test ! -L "$stage/.immich"
  test "$(stat -Lc %h -- "$stage/.immich")" -eq 1
  stage_id="$(stat -Lc '%d:%i' -- "$stage")"
  printf 'staged\t%s\t%s\t%s\t%s\n' "$label" "$source" "$stage" \
    "$stage_id" >> "$IMMICH_MEDIA_JOURNAL"
done < "$IMMICH_BACKUP_DIR/media-manifest.tsv"
test "$(grep -c '^staged' "$IMMICH_MEDIA_JOURNAL")" -eq 5
fsync_recovery_metadata "$IMMICH_MEDIA_JOURNAL"

python3 - "$IMMICH_MEDIA_JOURNAL" <<'PY'
import os
import stat
import sys

for line in open(sys.argv[1], encoding='utf-8'):
    if not line.startswith('staged\t'):
        continue
    _, label, target, stage, identity = line.rstrip('\n').split('\t')
    for root, directories, files in os.walk(stage, topdown=False, followlinks=False):
        for name in files:
            path = os.path.join(root, name)
            descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
            try:
                if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                    raise SystemExit(f'non-regular staged media node: {path!r}')
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
        descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    descriptor = os.open(os.path.dirname(stage), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
PY

# The dedicated Docker context was proven empty. A partial load makes this host
# disposable; it can never alter an active tag. Recovery still uses aliases.
IMMICH_IMAGE_JOURNAL=".run.conf/immich-images.${IMMICH_RESTORE_STAMP}.journal"
printf '%s\n' 'version=1' 'state=empty-docker-context' \
  > "$IMMICH_IMAGE_JOURNAL"
fsync_recovery_metadata "$IMMICH_IMAGE_JOURNAL"
printf '%s\n' 'state=image-load-starting' >> "$IMMICH_IMAGE_JOURNAL"
fsync_recovery_metadata "$IMMICH_IMAGE_JOURNAL"
docker image load --input "$IMMICH_BACKUP_DIR/images.tar"
printf '%s\n' 'state=loaded' >> "$IMMICH_IMAGE_JOURNAL"
fsync_recovery_metadata "$IMMICH_IMAGE_JOURNAL"
IMMICH_IMAGE_OVERRIDE=".run.conf/recovery-images.${IMMICH_RESTORE_STAMP}.yaml"
printf '%s\n' 'services:' > "$IMMICH_IMAGE_OVERRIDE"
while IFS=$'\t' read -r service image_ref image_id; do
  recovery_ref="localhost/immich-recovery-${IMMICH_RESTORE_STAMP}-${service}:locked"
  docker image tag "$image_id" "$recovery_ref"
  test "$(docker image inspect -f '{{.Id}}' "$recovery_ref")" = "$image_id"
  printf '  %s:\n    image: %s\n    pull_policy: never\n    build: null\n' \
    "$service" "$recovery_ref" >> "$IMMICH_IMAGE_OVERRIDE"
done < "$IMMICH_BACKUP_DIR/image-map.tsv"
printf '%s\n' 'state=images-aliased' >> "$IMMICH_IMAGE_JOURNAL"
fsync_recovery_metadata "$IMMICH_IMAGE_JOURNAL" "$IMMICH_IMAGE_OVERRIDE"

# Publish five absent paths with true RENAME_NOREPLACE and durable progress.
stage_records_output="$(grep '^staged' "$IMMICH_MEDIA_JOURNAL")"
mapfile -t stage_records <<< "$stage_records_output"
test "${#stage_records[@]}" -eq 5
for stage_record in "${stage_records[@]}"; do
  IFS=$'\t' read -r record label target stage stage_id <<< "$stage_record"
  printf 'publishing\t%s\n' "$label" >> "$IMMICH_MEDIA_JOURNAL"
  fsync_recovery_metadata "$IMMICH_MEDIA_JOURNAL"
  python3 - "$stage" "$target" <<'PY'
import ctypes
import os
import sys

libc = ctypes.CDLL(None, use_errno=True)
renameat2 = libc.renameat2
renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p,
                      ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
renameat2.restype = ctypes.c_int
if renameat2(-100, os.fsencode(sys.argv[1]), -100, os.fsencode(sys.argv[2]), 1):
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error))
directory = os.open(os.path.dirname(sys.argv[2]), os.O_RDONLY | os.O_DIRECTORY)
try:
    os.fsync(directory)
finally:
    os.close(directory)
PY
  test ! -e "$stage" && test ! -L "$stage"
  test "$(stat -Lc '%d:%i' -- "$target")" = "$stage_id"
  printf 'published\t%s\t%s\n' "$label" "$stage_id" \
    >> "$IMMICH_MEDIA_JOURNAL"
  fsync_recovery_metadata "$IMMICH_MEDIA_JOURNAL"
done
test "$(grep -c '^published' "$IMMICH_MEDIA_JOURNAL")" -eq 5

IMMICH_NETWORK_OVERRIDE=\
".run.conf/recovery-networks.${IMMICH_RESTORE_STAMP}.json"
IMMICH_NETWORK_INVENTORY=\
".run.conf/recovery-networks.${IMMICH_RESTORE_STAMP}.tsv"
python3 - "$IMMICH_BACKUP_DIR/network-evidence.tsv" immich \
  "$IMMICH_RESTORE_STAMP" "$IMMICH_NETWORK_OVERRIDE" \
  "$IMMICH_NETWORK_INVENTORY" frontend backend <<'PY'
import ipaddress
import json
import os
import re
import subprocess
import sys

evidence, app, stamp, override, inventory, *expected = sys.argv[1:]
rows = [line.split('\t') for line in
        open(evidence, encoding='utf-8').read().splitlines()]
if len(rows) != len(expected) or any(len(row) != 5 for row in rows):
    raise SystemExit('external-network evidence closure differs')
if [row[0] for row in rows] != expected or len(set(expected)) != len(expected):
    raise SystemExit('external-network keys differ')
owner = f'{app}-{stamp}'
for path in (override, inventory):
    if os.path.lexists(path):
        raise SystemExit(f'recovery network artifact already exists: {path!r}')
definitions = {}
created = []
for key, source_name, driver, subnet_text, gateway_text in rows:
    if source_name != key or driver != 'bridge' \
            or not re.fullmatch(r'[a-z0-9][a-z0-9_.-]*', key):
        raise SystemExit(f'unsupported external-network evidence: {key!r}')
    subnet = ipaddress.ip_network(subnet_text, strict=True)
    gateway = ipaddress.ip_address(gateway_text)
    if gateway.version != subnet.version or gateway not in subnet:
        raise SystemExit(f'invalid external-network IPAM: {key!r}')
    name = f'{app}-recovery-{stamp}-{key}'
    if subprocess.run(['docker', 'network', 'inspect', name],
                      stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL).returncode == 0:
        raise SystemExit(f'recovery network already exists: {name!r}')
    network_id = subprocess.check_output([
        'docker', 'network', 'create', '--driver', 'bridge',
        '--subnet', str(subnet), '--gateway', str(gateway),
        '--label', f'io.it-saervices.recovery-owner={owner}', name,
    ], text=True).strip()
    if not re.fullmatch(r'[0-9a-f]{64}', network_id):
        raise SystemExit(f'invalid created network ID: {network_id!r}')
    result = json.loads(subprocess.check_output(
        ['docker', 'network', 'inspect', network_id], text=True))
    if len(result) != 1:
        raise SystemExit('created network identity is ambiguous')
    item = result[0]
    config = item.get('IPAM', {}).get('Config', [])
    if item.get('Id') != network_id or item.get('Name') != name \
            or item.get('Driver') != 'bridge' or item.get('Scope') != 'local' \
            or any(item.get(field) for field in
                   ('Internal', 'Attachable', 'Ingress', 'ConfigOnly',
                    'EnableIPv6')) \
            or item.get('Options') not in ({}, None) or len(config) != 1 \
            or config[0].get('Subnet') != str(subnet) \
            or config[0].get('Gateway') != str(gateway) \
            or item.get('Labels') != {
                'io.it-saervices.recovery-owner': owner}:
        raise SystemExit(f'created network differs from evidence: {name!r}')
    definitions[key] = {'name': name, 'external': True}
    created.append((key, name, network_id, str(subnet), str(gateway)))
for path, payload in (
    (override, json.dumps({'networks': definitions}, sort_keys=True) + '\n'),
    (inventory, ''.join('\t'.join(row) + '\n' for row in created)),
):
    temporary = path + '.partial'
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(descriptor, payload.encode())
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.rename(temporary, path)
    directory = os.open(os.path.dirname(path), os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
PY
fsync_recovery_metadata "$IMMICH_NETWORK_OVERRIDE" \
  "$IMMICH_NETWORK_INVENTORY"
RECOVERY_COMPOSE=("${runtime_compose[@]}" -f "$IMMICH_IMAGE_OVERRIDE" \
  -f "$IMMICH_NETWORK_OVERRIDE")
keep_isolated_stopped() {
  trap - ERR INT TERM
  set +e
  "${RECOVERY_COMPOSE[@]}" down
  exit 1
}
trap keep_isolated_stopped ERR INT TERM
"${RECOVERY_COMPOSE[@]}" up -d --no-build --pull never --wait \
  --wait-timeout 180 immich-postgres
"${RECOVERY_COMPOSE[@]}" exec -T immich-postgres pg_restore --list \
  < "$IMMICH_BACKUP_DIR/immich-database.dump" >/dev/null
"${RECOVERY_COMPOSE[@]}" exec -T immich-postgres sh -ec \
  'exec pg_restore --clean --if-exists --exit-on-error --single-transaction --no-owner --dbname="$POSTGRES_DB" --username="$POSTGRES_USER"' \
  < "$IMMICH_BACKUP_DIR/immich-database.dump"
"${RECOVERY_COMPOSE[@]}" up -d --no-build --pull never --wait \
  --wait-timeout 300
python3 - "$IMMICH_NETWORK_INVENTORY" "$clean_rendered_json" \
  "$rendered_project_name" <<'PY'
import json
import subprocess
import sys

inventory, compose_path, project = sys.argv[1:]
compose = json.load(open(compose_path, encoding='utf-8'))
for row in open(inventory, encoding='utf-8'):
    key, name, network_id, subnet, gateway = row.rstrip('\n').split('\t')
    result = json.loads(subprocess.check_output(
        ['docker', 'network', 'inspect', network_id], text=True))
    if len(result) != 1 or result[0].get('Name') != name:
        raise SystemExit(f'recovery network identity drift: {name!r}')
    expected = {service for service, definition in compose['services'].items()
                if key in definition.get('networks', {})}
    actual = set()
    containers = result[0].get('Containers') or {}
    for container_id in containers:
        detail = json.loads(subprocess.check_output(
            ['docker', 'inspect', container_id], text=True))
        if len(detail) != 1:
            raise SystemExit('recovery network member identity is ambiguous')
        labels = detail[0].get('Config', {}).get('Labels', {})
        if labels.get('com.docker.compose.project') != project:
            raise SystemExit(f'foreign recovery network member: {container_id!r}')
        service = labels.get('com.docker.compose.service', '')
        if not service or service in actual:
            raise SystemExit(f'duplicate recovery network service: {service!r}')
        actual.add(service)
    if actual != expected:
        raise SystemExit(
            f'recovery network member closure differs for {key!r}: '
            f'{sorted(actual ^ expected)}')
PY
printf '%s\n' 'state=complete' >> "$IMMICH_MEDIA_JOURNAL"
printf '%s\n' 'state=complete' >> "$IMMICH_IMAGE_JOURNAL"
fsync_recovery_metadata "$IMMICH_MEDIA_JOURNAL" "$IMMICH_IMAGE_JOURNAL"
for completed_journal in "$IMMICH_MEDIA_JOURNAL" "$IMMICH_IMAGE_JOURNAL"; do
  completed_marker="${completed_journal%.journal}.complete"
  test ! -e "$completed_marker" && test ! -L "$completed_marker"
  completed_id="$(stat -Lc '%d:%i' -- "$completed_journal")"
  python3 - "$completed_journal" "$completed_marker" <<'PY'
import os
import sys

os.rename(sys.argv[1], sys.argv[2])
directory = os.open(os.path.dirname(sys.argv[2]), os.O_RDONLY | os.O_DIRECTORY)
try:
    os.fsync(directory)
finally:
    os.close(directory)
PY
  test ! -e "$completed_journal" && test ! -L "$completed_journal"
  test "$(stat -Lc '%d:%i' -- "$completed_marker")" = "$completed_id"
done
trap - ERR INT TERM
```

The bæckup is PostgreSQL custom formæt. It is intentionælly **not** compætible
with **Ædministrætion → Mæintenænce → Restore dætæbæse bæckup**, which
expects Immich's supported SQL bæckup workflow. Do not feed this `.dump` to
the web UI ænd do not use æ host-version `pg_restore`; the list check ænd full
`--clean --if-exists --exit-on-error --single-transaction` restore both run
inside the ærchived, mætching PostgreSQL contæiner. If `ERR`, `INT`, `TERM`,
`SIGKILL`, or host loss leæves æ `.journal`, the executæble preconditions for
æ new run remæin fælse: do not reconcile it in plæce or reuse thæt Docker
dæmon, discærd the whole isolæted host, then retry on æ new empty host. Before
cutover, verify æsset counts, uploæd/download,
thumbnæils, video plæybæck/transcoding, profile imæges, æutomætic bæckups,
jobs, mobile sync, ænd restært persistence. Never treæt the PostgreSQL dump or
æny subset of the five mediæ trees æs æ complete bæckup.

---

## Upgræde

**PostgreSQL 14 users:** Do not run the generic `run.sh`/`up -d` sequence below. First complete the dedicæted [PostgreSQL 14 to 18 migrætion](#postgresql-14-to-18-migrætion), beginning with the old PostgreSQL 14 Compose file still in plæce.

1. Creæte änd verify æ current dætæbæse-plus-mediæ bæckup.
2. Reæd the Immich releæse notes ænd æny breæking-chænge notices. Upgræde mobile clients before the server when moving to æ new mæjor version.
3. Keep `APP_IMAGE` ænd `IMMICH_MACHINE_LEARNING_IMAGE` on the sæme Immich chænnel. This stæck uses the floæting `v3` tæg for both, the PostgreSQL 18 compætibility tæg without æ digest, ænd the floæting Vælkey `9` tæg.
4. Resolve/build exæctly once through the cænonicæl updæte trænsæction. If the
   project wæs stopped before the updæte, stært only those recorded bytes.
   Run this block from the repository root:

   ```bash
   ./run.sh Immich --update
   docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml up -d --no-build --pull never
   docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml ps
   ```

Immich does not support downgrædes. See the [officiæl upgræde guide](https://docs.immich.app/install/upgrading/) before chænging version pins.

### PostgreSQL 14 to 18 Migrætion

PostgreSQL mæjor versions do not shære æ dætæ-directory formæt. Never stært the PostgreSQL 18 imæge on the existing PostgreSQL 14 volume. This stæck keeps the logicæl `immich-postgres` volume næme, but PostgreSQL 18 mounts it æt `/var/lib/postgresql` insteæd of PostgreSQL 14's `/var/lib/postgresql/data`. The migrætion therefore creætes æ verified offline copy of the PostgreSQL 14 volume, removes the originæl volume, lets Compose creæte æ fresh empty volume with the sæme næme, ænd then restores the logicæl dump.

Run the following steps from the repository root. The old PostgreSQL 14 stæck must still be running, ænd `Immich/docker-compose.main.yaml` must still describe thæt old stæck when step 1 is run.

#### 1. Cæpture the old deployment

```bash
set -euo pipefail

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
    diff --recursive --brief --no-dereference /source /target
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
    diff --recursive --brief --no-dereference /source /target
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

Secret plæceholders ære committed æs `CHANGE_ME`; the initiæl `./run.sh Immich` copies them into `Immich/secrets` ænd replæces them with generæted vælues. Generæted files use mode `0640`. The Immich Compose file opts into `x-secrets-use-app-gid`, so every merge enforces `APP_GID` æs the group for these shæred secrets without æ sepæræte secret-group væriæble. Immich uses `APP_GID` æs its primæry group; PostgreSQL ænd Vælkey receive it æs æ supplementæry group becæuse both consume æ mode-`0640` secret. Mæchine leærning mounts neither secret ænd therefore does not receive thæt group.

The upstreæm v3 imæge converts `DB_PASSWORD_FILE` ænd
`REDIS_PASSWORD_FILE` to plæin `DB_PASSWORD` ænd `REDIS_PASSWORD` before it
executes Node. This stæck's `immich-start.sh` fæils closed unless the reviewed
vendor stært-script ænd compiled `config.repository.js` structures mætch
exæctly. It removes the three `DB_URL_FILE`, `DB_PASSWORD_FILE`, ænd
`REDIS_PASSWORD_FILE` export cælls into mode-`0400` copies below æ privæte
`/run` tmpfs directory. The preloæded Node helper then opens the two exæct
Docker secret pæths with `O_NOFOLLOW|O_NONBLOCK`, requires æ single-link
bounded regulær vælid-UTF-8 single-line file, ænd supplies the vælues only to
Immich's one-time cæched configurætion DTO. Finæl Node process environments
retæin only the non-sensitive `*_FILE` pæths. `DB_URL`, `DB_URL_FILE`,
`REDIS_URL`, ænd `REDIS_URL_FILE` ære intentionælly forbidden becæuse URLs cæn
contæin the corresponding pæsswords.

Æ moving `v3` imæge updæte thæt chænges either reviewed vendor structure
stops before the dæemon listens. Review the current officiæl imæge, updæte the
structuræl guærd if necessæry, run the focused unit test plus reæl runtime
checks, ænd only then recreæte `app`. Do not set `NODE_OPTIONS`; the supervisor
rejects æ pre-existing vælue so it cænnot be used to bypæss the locked loæder.
The non-secret trænsformed files remæin in their privæte per-stært directory;
the contæiner's `/run` tmpfs discærds them on stop. The supervisor does not
delete through æ dæemon-writæble pæth.

If æn existing deployment wæs initiælized through `sudo` ænd the secrets ære `root:root 0640`, æ regulær user cænnot chænge their group. `run.sh` then stops with the exæct repæir commænd. Repæir only the group ænd mode; do not generæte new pæsswords for æn initiælized dætæbæse. Run both blocks below from the repository root:

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
- Exæct vendor-drift guærds ænd æ locked file-only loæder keep both secret vælues out of the long-running Immich process tree; plæin `DB_URL` use is rejected.
- Signæl-forwærding supervisors reæp the Immich ænd mæchine-leærning children ænd normælize only their expected TERM exit to zero; other child fæilures propægæte.
- Bæckend-only networks for PostgreSQL, Vælkey, ænd mæchine leærning.
- JSON log rotætion ænd resource limits on every service.
- Nætive OIDC ævoids reverse-proxy æuth breækæge for mobile ænd uploæd workflows.

---

## Heælthcheck

The root `app` service invokes Immich's imæge-nætive probe. The æctive
Compose definition is:

```yaml
test: ['CMD-SHELL', 'immich-healthcheck']
interval: 30s
timeout: 10s
retries: 3
start_period: 60s
```

Run these commænds from the `Immich/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  immich-healthcheck
```

The merged stæck contæins four heælthchecked services. This is the complete
probe inventory; the timing must be kept in sync with the root ænd templæte
Compose files:

| Service | Æctive test | `interval` | `timeout` | `retries` | Stært græce |
| --- | --- | --- | --- | --- | --- |
| `app` | `immich-healthcheck` | `30s` | `10s` | `3` | `60s` |
| `immich-postgres` | `/usr/local/bin/healthcheck.sh` | `5m` | `30s` | `3` | `5m`; `start_interval: 5s` |
| `immich-valkey` | secret-bæcked `valkey-cli --raw ping`, exæct `PONG` | `30s` | `5s` | `3` | `10s` |
| `immich-machine-learning` | `python3 healthcheck.py` | `30s` | `10s` | `3` | `60s` |

Run every configured probe from the `Immich/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T app immich-healthcheck
docker compose --env-file .env -f docker-compose.main.yaml exec -T immich-postgres /usr/local/bin/healthcheck.sh
docker compose --env-file .env -f docker-compose.main.yaml exec -T immich-valkey sh -ec 'response="$(VALKEYCLI_AUTH="$(cat /run/secrets/IMMICH_VALKEY_PASSWORD)" valkey-cli --raw ping)" && [ "$response" = PONG ]'
docker compose --env-file .env -f docker-compose.main.yaml exec -T immich-machine-learning python3 healthcheck.py
```

## Verificætion

Run the repository checks, merge commænds, ænd pæth-quælified Compose
vælidætion from the repository root:

```bash
python3 .cursor/scripts/enforce-branding.py --check Immich templates/immich-postgres templates/immich-valkey templates/immich-machine-learning
python3 .cursor/scripts/enforce-app-template-compliance.py --check Immich templates/immich-postgres templates/immich-valkey templates/immich-machine-learning
python3 .cursor/scripts/verify-anchors.py Immich
python3 .cursor/scripts/check-hardening.py --quiet Immich templates/immich-postgres templates/immich-valkey templates/immich-machine-learning
node Immich/scripts/test-immich-secret-loader.cjs
./run.sh Immich --dry-run
./run.sh Immich
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml config
```

Æfter stærtup:

```bash
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml ps
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml logs --tail 100 app immich-postgres immich-valkey immich-machine-learning
docker compose --env-file Immich/.env -f Immich/docker-compose.main.yaml exec -T immich-postgres /usr/local/bin/healthcheck.sh
```
