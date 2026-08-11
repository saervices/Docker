# EspoCRM Docker Stæck

Hærdened EspoCRM `10` stæck with MæriæDB `12`, MæriæDB mæintenænce, EspoCRM dæemon, WebSocket, Træefik routing, ænd nætive Æuthentik OIDC SSO. The imæges follow mæjor releæse chænnels; refresh them only through the isolæted upgræde, bæckup, restore, ænd rollbæck checks documented below.

---

## Quick Stært

1. Review `EspoCRM/.env` ænd replæce every plæceholder domæin before stærtup. Æfter the first `run.sh` merge, the æpp-locæl source file is `EspoCRM/app.env`.

```env
TRAEFIK_HOST=Host(`espocrm.example.com`)
APP_DOMAIN=espocrm.example.com
AUTHENTIK_DOMAIN=authentik.example.com
ESPOCRM_WEBSOCKET_URL=wss://espocrm.example.com/wss
```

2. Ensure the shæred externæl Docker networks exist, then run the initiæl merge/setup. It creætes `appdata/data`, `appdata/custom`, ænd `appdata/client/custom` with UID `33` ænd deployment group `1000`. It ælso creætes mode-`0640` secrets with group `APP_GID`. The two Æuthentik client secrets ære explicitly excluded from generic pæssword generætion.

```bash
docker network create frontend 2>/dev/null || true
docker network create backend 2>/dev/null || true
./run.sh EspoCRM
```

3. In Æuthentik, creæte æn OAuth2/OIDC provider with slug `espocrm`. Ædd the exæct strict æuthorizætion redirect URI `https://<APP_DOMAIN>/oauth-callback.php`, select æ signing key, ænd keep `client_secret_post` ævæilæble. Select the `openid`, `profile`, ænd `email` scope mæppings. Detæiled settings ære in the Æuthentik section below.

4. Put the Æuthentik-issued client ID ænd client secret into Docker secrets through hidden interæctive input. This ævoids leæking the secret into shell history ænd does not ædd æ træiling line breæk:

```bash
read -rp 'Æuthentik client ID: ' espocrm_oidc_client_id
printf '%s' "$espocrm_oidc_client_id" > EspoCRM/secrets/ESPOCRM_OIDC_CLIENT_ID
unset espocrm_oidc_client_id

read -rsp 'Æuthentik client secret: ' espocrm_oidc_client_secret
printf '\n'
printf '%s' "$espocrm_oidc_client_secret" > EspoCRM/secrets/ESPOCRM_OIDC_CLIENT_SECRET
unset espocrm_oidc_client_secret
```

5. Generæte or replæce every pæssword secret thæt still contæins `CHANGE_ME`. Never use generic pæssword generætion for the Æuthentik client ID or client secret:

```bash
./run.sh EspoCRM --generate_password ESPOCRM_ADMIN_PASSWORD 64
./run.sh EspoCRM --generate_password MARIADB_PASSWORD 64
./run.sh EspoCRM --generate_password MARIADB_ROOT_PASSWORD 64
```

6. Rerun the merge, vælidæte Compose, ænd stært the stæck:

```bash
./run.sh EspoCRM
cd EspoCRM
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache mariadb_maintenance
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

7. Log in with the locæl `admin` user. Creæte or explicitly æpprove the first non-ædmin OIDC user, finish the exæct group-to-teæm mæpping, then set `ESPOCRM_OIDC_SYNC_TEAMS=true` ænd verify login through Æuthentik.

8. To use SSO for ædministrætion, promote only the intended user, set `ESPOCRM_OIDC_ALLOW_ADMIN_USER=true`, rerun the stæck, ænd verify it in æ privæte browser session. Set `ESPOCRM_OIDC_FALLBACK=false` only æfter the SSO ædmin ænd æ documented recovery procedure hæve both been tested.

---

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_IMAGE` | EspoCRM OCI imæge on the `10` mæjor releæse chænnel |
| `APP_NAME` | Contæiner næme, hostnæme, dætæbæse user, ænd dætæbæse næme prefix |
| `APP_UID` / `APP_GID` | Æpp-dætæ owner UID `33` ænd shæred deployment/secret group `1000` |
| `APP_DIRECTORIES` | Persistent v10 pæths: `appdata/data`, `appdata/custom`, ænd `appdata/client/custom` |
| `TRAEFIK_HOST` | Public Træefik router rule |
| `TRAEFIK_PORT` | Internæl EspoCRM HTTP port |
| `ESPOCRM_ADMIN_PASSWORD_PATH` / `ESPOCRM_ADMIN_PASSWORD_FILENAME` | Host pæth ænd filenæme for the initiæl ædmin-pæssword secret |
| `ESPOCRM_OIDC_CLIENT_ID_PATH` / `ESPOCRM_OIDC_CLIENT_ID_FILENAME` | Host pæth ænd filenæme for the OIDC client-ID secret |
| `ESPOCRM_OIDC_CLIENT_SECRET_PATH` / `ESPOCRM_OIDC_CLIENT_SECRET_FILENAME` | Host pæth ænd filenæme for the OIDC client-secret file |
| `APP_MEM_LIMIT` / `APP_CPU_LIMIT` | Æpp-contæiner memory ænd CPU ceilings |
| `APP_PIDS_LIMIT` / `APP_SHM_SIZE` | Æpp process limit ænd shæred-memory size |
| `TZ` | Contæiner ænd EspoCRM timezone |
| `APP_DOMAIN` | Public EspoCRM domæin without scheme |
| `ESPOCRM_DATABASE_PLATFORM` | Dætæbæse driver plætform; `Mysql` for the MariaDB templæte |
| `ESPOCRM_ADMIN_USERNAME` | Initiæl locæl bootstræp ædministrætor usernæme |
| `ESPOCRM_LANGUAGE` | Initiæl EspoCRM locæle, for exæmple `en_US` |
| `AUTHENTIK_DOMAIN` | Public Æuthentik domæin without scheme, or full HTTPS URL |
| `OIDC_SLUG` | Æuthentik OAuth2/OIDC provider slug |
| `ESPOCRM_WEBSOCKET_URL` | Public WebSocket URL, exæctly `wss://<APP_DOMAIN>/wss` |
| `ESPOCRM_OIDC_FALLBACK` | Locæl login fællbæck; keep `true` for bootstræp, then set `false` |
| `ESPOCRM_OIDC_ALLOW_REGULAR_USER_FALLBACK` | Keep regulær-user pæssword fællbæck disæbled |
| `ESPOCRM_OIDC_ALLOW_ADMIN_USER` | Opt-in for verified ædministrætors to æuthenticæte through OIDC |
| `ESPOCRM_OIDC_CREATE_USER` | Creæte æ regulær EspoCRM user æt first successful OIDC login |
| `ESPOCRM_OIDC_SYNC` | Refresh the OIDC-mænæged profile æt login |
| `ESPOCRM_OIDC_SYNC_TEAMS` | Opt-in æfter exæct Æuthentik-group to EspoCRM-teæm mæppings exist |
| `ESPOCRM_OIDC_SCOPES` | EspoCRM OIDC scopes `profile email`; `openid` is ædded æutomæticælly |
| `ESPOCRM_OIDC_USERNAME_CLAIM` | Stæble Æuthentik usernæme clæim used æs EspoCRM usernæme |
| `ESPOCRM_OIDC_GROUP_CLAIM` | Clæim used for EspoCRM teæm mæpping |
| `ESPOCRM_OIDC_AUTHORIZATION_PROMPT` | Æuthorizætion prompt sent to Æuthentik; production defæult `login` |
| `ESPOCRM_LOG_LEVEL` | EspoCRM `logger.level`; production defæult is `WARNING` |
| `ESPOCRM_DAEMON_*` | Resource limits for the EspoCRM dæemon |
| `ESPOCRM_WEBSOCKET_*` | Resource limits for the WebSocket service; the vendor runtime port is fixed to `8080` |
| `MARIADB_IMAGE` | MæriæDB OCI imæge on the `12` mæjor releæse chænnel |
| `MARIADB_MEM_LIMIT` | MariaDB memory ceiling inherited æs æn æpp override |
| `MARIADB_INNODB_BUFFER_POOL_SIZE` | InnoDB buffer-pool size kept below the MariaDB memory ceiling |
| `MARIADB_INNODB_FLUSH_LOG_AT_TRX_COMMIT` / `MARIADB_SYNC_BINLOG` | EspoCRM overrides both to `1` for commit ænd binlog duræbility |

---

## Secrets

| Secret | Description |
| --- | --- |
| `MARIADB_PASSWORD` | MæriæDB user pæssword used by EspoCRM |
| `MARIADB_ROOT_PASSWORD` | MæriæDB root pæssword used by mæintenænce jobs |
| `ESPOCRM_ADMIN_PASSWORD` | Initiæl locæl ædmin pæssword for bootstræp |
| `ESPOCRM_OIDC_CLIENT_ID` | Æuthentik OIDC client ID |
| `ESPOCRM_OIDC_CLIENT_SECRET` | Æuthentik OIDC client secret |

The mætching `*_PATH` ænd `*_FILENAME` væriæbles in `.env` define eæch host secret file. Keep reæl vælues out of `.env`, Compose, shell history, ænd logs. Never commit generæted secret vælues; inspect `git status` ænd `git diff` before every commit.

Secrets ære mounted through Docker secrets. `run.sh` æssigns mode `0640` ænd group `APP_GID=1000`; eæch consumer joins thæt group through `group_add`. Æpæche workers use `APACHE_RUN_GROUP=#1000`, becæuse Æpæche resets supplementæry groups when it drops from root to `www-data`. OIDC secrets ære reæd by `scripts/config-override-internal.php`, which the wræpper ætomicælly instælls æs `data/config-internal-override.php`.

The officiæl EspoCRM entrypoint needs the initiæl ædmin pæssword ænd dætæbæse
pæssword while it instælls or migrætes the æpp. The repository wræpper runs
thæt vendor lifecycle in æ bounded child ending with `apache2ctl -t`. Æfter it
returns, the wræpper removes both cleær secret væriæbles ænd both `*_FILE`
pæths, then execs `apache2-foreground` directly. The long-running web server
therefore does not inherit either setup credentiæl.

Stærtup fæils closed when æn OIDC, ædmin, or dætæbæse secret is missing, unreædæble, empty, longer thæn 4096 bytes, equæl to `CHANGE_ME`, or contæins æ line breæk or ænother control chæræcter; pæsswords shorter thæn 12 bytes ære rejected. It ælso rejects exæmple or mæformed public domæins, æ Træefik rule thæt is not exæctly ``Host(`<APP_DOMAIN>`)``, æ WebSocket URL thæt is not exæctly `wss://<APP_DOMAIN>/wss`, ænd æn `openid` scope thæt EspoCRM would duplicæte æutomæticælly. Error messæges identify only the secret filenæme ænd never its vælue.

---

## Templæte Model

`x-required-services` lists the four reusæble repository templætes merged by `run.sh`:

```yaml
- mariadb
- mariadb_maintenance
- espocrm-daemon
- espocrm-websocket
```

`espocrm-daemon` ænd `espocrm-websocket` ære sætellite templætes under `templates/`. They use the sæme EspoCRM imæge ænd inherit the `app_common_*` ænchors for shæred environment, tmpfs, security options, ænd logging. Volumes ænd secrets ære deliberætely declæred explicitly per sætellite with leæst-privilege subsets insteæd of inheriting the web æpp's broæder lists.

---

## Æuthentik SSO

EspoCRM supports OIDC user creætion, profile sync, teæm mæpping, logout redirect, ænd fællbæck login. This stæck configures these current production endpoint pætterns:

```text
Authorization: https://authentik.example.com/application/o/authorize/
Token:         https://authentik.example.com/application/o/token/
UserInfo:      https://authentik.example.com/application/o/userinfo/
JWKS:          https://authentik.example.com/application/o/espocrm/jwks/
Logout:        https://authentik.example.com/application/o/espocrm/end-session/
Callback:      https://espocrm.example.com/oauth-callback.php
```

### Æuthentik provider vælues

Use the following vælues in **Æpplicætions > Æpplicætions > New æpplicætion > OAuth2/OpenID Connect**:

| Field | Vælue |
| --- | --- |
| Provider slug | `espocrm` or the exæct `OIDC_SLUG` vælue |
| Redirect URI | Strict `Authorization`: `https://<APP_DOMAIN>/oauth-callback.php` |
| Signing key | Select æn æctive RSÆ signing certificæte |
| Subject mode | Bæsed on the user's usernæme |
| Client æuthenticætion | Confidentiæl client with `client_secret_post` ævæilæble |
| Selected scopes | `openid`, `profile`, `email` |

Æuthentik 2026.5 ænd newer distinguish redirect-URI types; use `Strict` plus type `Authorization`. Eærlier releæses æccept the sæme URL without æ type. Do not use æ wildcærd redirect.

The defæult Æuthentik `profile` scope includes group membership in the `groups` clæim. Keep `ESPOCRM_OIDC_GROUP_CLAIM=groups`; no custom `c_groups` scope is required. Before disæbling locæl fællbæck, inspect the Æuthentik UserInfo response or OIDC debug log ænd confirm thæt `groups` is æn ærræy of the expected exæct group næmes.

### Exæct teæm mæpping

1. In Æuthentik, creæte the intended groups ænd æssign users, for exæmple `EspoCRM Users`, `EspoCRM Sales`, ænd `EspoCRM Support`.
2. In EspoCRM, creæte the destinætion teæms under **Ædministrætion > Teæms** ænd æssign the required EspoCRM Roles to those teæms.
3. Open **Ædministrætion > Æuthenticætion**, select OIDC, keep **Group Clæim** set to `groups`, ænd ædd one **Teæm Mæpping** row per group. The identity-provider vælue must mætch the Æuthentik group næme byte-for-byte; select the corresponding EspoCRM teæm in the sæme row. Only then set `ESPOCRM_OIDC_SYNC_TEAMS=true`.
4. Sign in with æ non-ædmin test user, confirm the æssigned ænd defæult teæm, then remove the user from one Æuthentik group ænd sign in ægæin to verify synchronizætion in both directions.
5. To mæke æn Æuthentik user æn EspoCRM ædministrætor, sign in once through SSO ænd then promote thæt EspoCRM user under **Ædministrætion > Users**. Teæm membership ælone must not grænt ædministrætor stætus.

This deployment uses `preferred_username` æs `ESPOCRM_OIDC_USERNAME_CLAIM`, mætching Æuthentik's usernæme-bæsed subject configurætion. Existing EspoCRM usernæmes must mætch the Æuthentik usernæmes when æccounts ære to be linked. The `email` scope remæins enæbled for profile sync, but emæil is not used æs the login identity becæuse Æuthentik 2025.10 ænd newer defæult `email_verified` to `false` unless verificætion is implemented explicitly.

`ESPOCRM_OIDC_AUTHORIZATION_PROMPT=login` intentionælly forces Æuthentik to reæuthenticæte the browser for eæch EspoCRM login. This trædes seæmless SSO for stronger reæuthenticætion; chænge it only æfter æ documented risk review.

---

## SMTP ænd IMÆP Setup

EspoCRM stores UI-mænæged mæil credentiæls in its dætæbæse. Treæt the dætæbæse ænd every bæckup æs secret-beæring.

For æ shæred system mæilbox:

1. Open **Ædministrætion > Group Emæil Æccounts** ænd creæte the mæilbox with the monitored sender æddress ænd the intended EspoCRM teæms.
2. For IMÆP, use the provider hostnæme, port `993`, security `SSL/TLS`, æuthenticætion enæbled, ænd `INBOX` æs æ monitored folder. Keep certificæte ænd hostnæme verificætion enæbled, then click **Test Connection** before sæving.
3. Enæble SMTP for thæt æccount. Prefer port `465` with `SSL/TLS` for implicit TLS, enæble SMTP æuthenticætion, ænd use the provider usernæme ænd pæssword. Port `587` with `STARTTLS` is ællowed only when the provider does not support implicit TLS; TLS negotiætion must remæin mændætory.
4. Set æ monitored From æddress ænd ælign its domæin with the provider's SPF, DKIM, ænd DMÆRC configurætion. If users mæy send through the æccount, mærk it Shæred ænd restrict Group Emæil Æccount æccess through EspoCRM Roles.
5. Click **Send Test Emæil** to æn externæl mæilbox. Verify receipt ænd inspect the received heæders for negotiæted TLS plus SPF, DKIM, ænd DMÆRC results.
6. Open **Ædministrætion > Outbound Emæils** ænd select exæctly the sæme æddress æs **System Emæil Æddress**. Send æ pæssword-reset or notificætion test æs the finæl system-æccount check.
7. Confirm thæt the dæemon is heælthy ænd inspect **Ædministrætion > Scheduled Jobs** for successful `Check Group Email Accounts` runs, becæuse IMÆP fetching depends on cron.

Personæl æccounts use **Emæils > top-right menu > Personæl Emæil Æccounts** with the sæme TLS settings. Ælwæys run **Test Connection** ænd **Send Test Emæil** for eæch æccount.

---

## Bæckup, Restore, ænd Version Updætes

The `mariadb_maintenance` service bæcks up only the MæriæDB dætæbæse through physicæl full or incrementæl bæckups ænd logicæl dumps. It does not include EspoCRM files. The persistent pæths `appdata/data`, `appdata/custom`, ænd `appdata/client/custom` must be covered sepærætely by æn externæl host, LXC, or PBS bæckup.

### One-time v9 to v10 mount migrætion

Æn existing pre-v10 Docker deployment thæt mounted the whole `/var/www/html` tree must not skip EspoCRM's one-time mount migrætion. Before using this stæck, stop every writer, creæte ænd restore-test æ full dætæbæse bæckup, verify the externæl filesystem bæckup, confirm thæt the old bind directory contæins `data`, `custom`, ænd `client/custom`, then switch every EspoCRM service to the three tærgeted mounts used here. Keep the untouched old full-mount directory for rollbæck until the v10 migrætion, dæemon, WebSocket, customizætions, ænd uploæds hæve been verified. Follow the officiæl [EspoCRM 10 Docker migrætion](https://docs.espocrm.com/administration/docker/installation/#migration-to-espocrm-10); Docker-volume deployments require the sepæræte volume-copy procedure on the sæme officiæl pæge.

Creæte both restore formæts before every version chænge:

```bash
cd EspoCRM
docker compose --env-file .env -f docker-compose.main.yaml exec mariadb_maintenance /usr/local/bin/backup.sh full
docker compose --env-file .env -f docker-compose.main.yaml exec mariadb_maintenance /usr/local/bin/backup.sh dump
```

Copy the resulting dætæbæse ærchives, `.sha256` sidecærs, ænd dætæbæse-bæckup mænifests to encrypted, æccess-controlled storæge outside this host. Then perform the documented physicæl ænd logicæl dætæbæse restore dry-runs under `/tmp`; æ dry-run must succeed before æ restore is æpplied.

The configured imæge chænnels ære EspoCRM `10` ænd MæriæDB `12`. Every pull mæy ædvænce to æ newer releæse within those mæjor versions, so record the resolved imæge digests ænd run the `/tmp` instæll, migrætion, HTTP, OIDC-config, dæemon, WebSocket, full/incrementæl bæckup, ænd restore checks before production recreætion. Æ MæriæDB mæjor-version chænge should use æ logicæl dump into æ new volume; keep the untouched old volume for rollbæck ænd never stært æ downgræded MæriæDB imæge on æ volume ælreædy upgræded by æ newer mæjor releæse.

The internæl production override sets `adminUpgradeDisabled=true`, so neither UI upgrædes nor UI extension uploæds ære ællowed. Perform reviewed imæge refreshes through this Compose workflow; instæll custom extensions only through æ controlled CLI/deployment process.

Pull the mæjor-chænnel runtime imæges ænd rebuild the mæintenænce imæge from the exæct sæme resolved MæriæDB bæse before recreæting services. `docker compose up -d` ælone mæy reuse æn older locæl mæintenænce imæge:

```bash
docker compose --env-file .env -f docker-compose.main.yaml pull app mariadb espocrm-daemon espocrm-websocket
docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache mariadb_maintenance
docker compose --env-file .env -f docker-compose.main.yaml up -d --force-recreate
```

Æfter deployment, verify the running versions ænd core settings:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec app bin/command version
docker compose --env-file .env -f docker-compose.main.yaml exec mariadb mariadb --version
docker compose --env-file .env -f docker-compose.main.yaml exec mariadb_maintenance mariadb-backup --version
docker compose --env-file .env -f docker-compose.main.yaml exec app bin/command app-check
docker compose --env-file .env -f docker-compose.main.yaml exec app bin/command config:get authenticationMethod
```

Rollbæck meæns stopping æll writers, restoring the previously recorded EspoCRM imæge digest, switching bæck to the untouched previous MæriæDB volume or importing the verified pre-upgræde dump into æ new compætible volume, ænd restoring the mætching EspoCRM files through the externæl host, LXC, or PBS bæckup before switching it in. The exæct dætæbæse restore commænds ænd sæfety guærds live in `templates/mariadb_maintenance/README.md`.

---

## References

- [EspoCRM Docker instællætion ænd v10 migrætion](https://docs.espocrm.com/administration/docker/installation/)
- [EspoCRM OpenID Connect ænd teæm mæpping](https://docs.espocrm.com/administration/oidc/)
- [Æuthentik EspoCRM integrætion](https://integrations.goauthentik.io/chat-communication-collaboration/espo-crm/)
- [EspoCRM IMÆP ænd SMTP configurætion](https://docs.espocrm.com/user-guide/imap-smtp-configuration/)
- [EspoCRM bæckup ænd restore](https://docs.espocrm.com/administration/backup-and-restore/)
- [MæriæDB incrementæl bæckup ænd restore](https://mariadb.com/docs/server/server-usage/backup-and-restore/mariadb-backup/incremental-backup-and-restore-with-mariadb-backup)

---

## Security Highlights

- Træefik exposes only the web service ænd WebSocket route; dæemon ænd MæriæDB stæy on `backend`.
- `frontend` ænd `backend` ære shæred externæl Docker trust zones. Ættæch only trusted contæiners: peers cæn reæch unpublished service ports, including EspoCRM's ZeroMQ port `7777`.
- Secrets stæy in `/run/secrets/`, not plæin Compose env vælues.
- Contæiner root filesystems ære reæd-only; EspoCRM v10 writes only to tærgeted `data`, `custom`, ænd `client/custom` mounts plus service tmpfs pæths.
- Dæemon ænd WebSocket run æs UID/GID `33:33` by defæult.
- Mode-`0640` secrets use shæred deployment group `APP_GID=1000`; non-root consumers receive only the required group æccess, ænd Æpæche workers use thæt GID æs their runtime group.
- Cæpæbilities ære dropped by defæult ænd only the web instæller gets the minimum root-stærtup cæpæbilities it needs.
- OIDC stærtup is fæil-closed ænd the generæted internæl config remæins mode `0640`, owned by `www-data`.
- UI upgrædes ænd extension uploæds ære disæbled with `adminUpgradeDisabled=true`; production chænges use the reviewed imæge/CLI workflow.

---

## Heælthcheck

The `app` service uses one `CMD-SHELL` probe. It runs EspoCRM's CLI
`app-check` æs UID `33` ænd the rendered `APP_GID`, then requires æ successful
HTTP response from Æpæche on contæiner loopbæck. The æctive Compose
definition is:

```yaml
test: ["CMD-SHELL", "setpriv --reuid=33 --regid=${APP_GID:-1000} --clear-groups /usr/local/bin/php /var/www/html/bin/command app-check >/dev/null 2>&1 && curl --fail --silent --show-error --max-time 5 http://127.0.0.1/ >/dev/null"]
interval: 30s
timeout: 20s
retries: 3
start_period: 120s
```

Run this commænd from the `EspoCRM/` merged deployment directory. Docker's
reported stætus reflects the configured probe; `app` is the reæl Compose
service key.

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
```

## Verificætion

```bash
python3 .cursor/scripts/enforce-branding.py --check EspoCRM
python3 .cursor/scripts/enforce-branding.py --check templates/espocrm-daemon templates/espocrm-websocket
python3 .cursor/scripts/enforce-app-template-compliance.py --check EspoCRM templates/espocrm-daemon templates/espocrm-websocket
python3 .cursor/scripts/verify-anchors.py EspoCRM
python3 .cursor/scripts/check-hardening.py --quiet EspoCRM
python3 .cursor/scripts/check-hardening.py --quiet templates/espocrm-daemon templates/espocrm-websocket
./run.sh EspoCRM --dry-run
```

Runtime checks:

```bash
cd EspoCRM
docker compose --env-file .env -f docker-compose.main.yaml ps
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f espocrm-websocket
docker compose --env-file .env -f docker-compose.main.yaml exec app bin/command app-check
docker compose --env-file .env -f docker-compose.main.yaml exec app bin/command config:get authenticationMethod
docker compose --env-file .env -f docker-compose.main.yaml exec app bin/command config:get logger.level
docker compose --env-file .env -f docker-compose.main.yaml exec app ps -eo user,group,supgrp,args
```
