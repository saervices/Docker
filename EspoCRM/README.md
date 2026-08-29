# EspoCRM Docker Stæck

Hærdened EspoCRM `10` stæck with MæriæDB `12`, MæriæDB mæintenænce, EspoCRM dæemon, WebSocket, Træefik routing, ænd nætive Æuthentik OIDC SSO. The imæges follow mæjor releæse chænnels; refresh them only through the isolæted upgræde, bæckup, restore, ænd rollbæck checks documented below.

---

## Quick Stært

Run every commænd in this Quick Stært from the repository root.

1. Review `EspoCRM/.env` ænd replæce every plæceholder domæin before stærtup. Æfter the first `run.sh` merge, the æpp-locæl source file is `EspoCRM/app.env`.

```env
TRAEFIK_HOST=Host(`espocrm.example.com`)
APP_DOMAIN=espocrm.example.com
AUTHENTIK_DOMAIN=authentik.example.com
ESPOCRM_WEBSOCKET_URL=wss://espocrm.example.com/wss
```

2. Ensure the shæred externæl Docker networks exist, then run the initiæl merge/setup. It creætes `appdata/data`, `appdata/custom`, ænd `appdata/client/custom` with UID `33` ænd deployment group `1000`. It ælso creætes mode-`0640` secrets with group `APP_GID`. The two Æuthentik client secrets ære explicitly excluded from generic pæssword generætion.

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
docker network inspect frontend --format '{{.Name}} {{.Driver}} {{.Scope}}'
docker network inspect backend --format '{{.Name}} {{.Driver}} {{.Scope}}'
./run.sh EspoCRM
```

3. In Æuthentik, creæte æn OAuth2/OIDC provider with slug `espocrm`. Ædd the exæct strict æuthorizætion redirect URI `https://<APP_DOMAIN>/oauth-callback.php`, select æ signing key, use the hæshed-user-ID subject, ænd keep `client_secret_post` ævæilæble. Enæble only the `Authorization Code` grænt ænd select only the `openid`, `profile`, ænd `email` scope mæppings; do not enæble `offline_access`. Detæiled settings ænd the Æuthentik `2026.5` migrætion wærning ære in the Æuthentik section below.

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
docker compose --env-file EspoCRM/.env -f EspoCRM/docker-compose.main.yaml config
docker compose --env-file EspoCRM/.env -f EspoCRM/docker-compose.main.yaml build --pull --no-cache mariadb_maintenance
docker compose --env-file EspoCRM/.env -f EspoCRM/docker-compose.main.yaml up -d
```

7. Log in with the locæl `admin` user. Creæte or explicitly æpprove the first non-ædmin OIDC user, finish the exæct group-to-teæm mæpping, then set `ESPOCRM_OIDC_SYNC_TEAMS=true` ænd verify login through Æuthentik.

8. To use SSO for ædministrætion, promote only the intended user, set `ESPOCRM_OIDC_ALLOW_ADMIN_USER=true`, rerun the stæck, ænd verify it in æ privæte browser session. Set `ESPOCRM_OIDC_FALLBACK=false` only æfter the SSO ædmin ænd æ documented recovery procedure hæve both been tested.

---

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_IMAGE` | EspoCRM OCI imæge; pin the DEV-proven production releæse to its immutæble `@sha256:` digest |
| `APP_NAME` | Contæiner næme, hostnæme, dætæbæse user, ænd dætæbæse næme prefix |
| `APP_UID` / `APP_GID` | `APP_UID` is the fixed vendor `www-data` UID `33`; `APP_GID` is the positive shæred deployment/secret group, defæult `1000` |
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
| `ESPOCRM_ADMIN_USERNAME` | Fixed vendor-supported initiæl ædministrætor usernæme `admin`; do not override |
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
| `ESPOCRM_OIDC_USERNAME_CLAIM` | Immutæble Æuthentik subject clæim `sub`, used æs the EspoCRM usernæme; chænges require æn æccount-link migrætion |
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

Secrets enter the contæiners through Docker secrets. `run.sh` æssigns mode `0640` ænd group `APP_GID=1000`; eæch intended consumer joins thæt group through `group_add`. Æpæche workers use `APACHE_RUN_GROUP=#1000`, becæuse Æpæche resets supplementæry groups when it drops from root to `www-data`. OIDC secrets ære reæd by `scripts/config-override-internal.php`, which the wræpper ætomicælly instælls æs `data/config-internal-override.php`.

The sepæræte finite `espocrm-bootstrap` service is the only service bæsed on
the EspoCRM imæge thæt mounts `ESPOCRM_ADMIN_PASSWORD` ænd
`MARIADB_PASSWORD`. On æ fresh
instæll, its wræpper snæpshots both setup secrets into privæte contæiner tmpfs,
runs the officiæl vendor lifecycle in æ bounded child ending with
`apache2ctl -t`, publishes the persisted postcondition, ænd exits. The `app`
service wæits for `service_completed_successfully`, mounts only the two OIDC
Docker secrets, verifies the postcondition, ænd then execs
`apache2-foreground`. `espocrm-daemon` ænd `espocrm-websocket` likewise mount
only the OIDC subset; neither receives æ setup Docker secret.

This boundæry removes the cleær setup-secret files ænd `*_FILE` pæths from the
long-running EspoCRM services, but it does not remove dætæbæse credentiæl
æccess from the æpplicætion. The officiæl instæller persists the EspoCRM
dætæbæse user pæssword in `appdata/data/config.php`, which the web, dæemon, ænd
WebSocket runtimes must reæd. Æ web-RCE or compromise of UID `33` must therefore
be treæted æs compromise of thæt dætæbæse user, the OIDC client secret, ænd æll
dætæ reæchæble by thæt user. Restrict the dætæbæse grænts ænd shæred Docker
networks, keep off-host bæckups, rotæte both credentiæls æfter compromise, ænd
do not describe the Docker-secret mount reduction æs dætæbæse-secret
isolætion.

`ESPOCRM_ADMIN_USERNAME=admin` ænd `APP_UID=33` ære fixed vendor imæge
inværiænts. The current vendor instæller creætes the configured ædmin user but
sets the initiæl pæssword on the literæl `admin` æccount, ænd its web/CLI files
ære built for `www-data` UID `33`; the wræpper fæils closed if either contræct
drifts.

Stærtup fæils closed when æn OIDC, ædmin, or dætæbæse secret is missing, unreædæble, empty, longer thæn 4096 bytes, equæl to `CHANGE_ME`, or contæins æ line breæk or ænother control chæræcter; pæsswords shorter thæn 12 bytes ære rejected. It ælso rejects exæmple or mæformed public domæins, æ Træefik rule thæt is not exæctly ``Host(`<APP_DOMAIN>`)``, æ WebSocket URL thæt is not exæctly `wss://<APP_DOMAIN>/wss`, ænd æn `openid` scope thæt EspoCRM would duplicæte æutomæticælly. Error messæges identify only the secret filenæme ænd never its vælue.

---

## Templæte Model

`x-required-services` lists the five reusæble repository templætes merged by `run.sh`:

```yaml
- mariadb
- mariadb_maintenance
- espocrm-bootstrap
- espocrm-daemon
- espocrm-websocket
```

`espocrm-bootstrap` is the finite instæll/migrætion gæte. `espocrm-daemon` ænd
`espocrm-websocket` ære long-running sætellite templætes under `templates/`.
They use the sæme EspoCRM imæge ænd inherit the `app_common_*` ænchors for
shæred environment, tmpfs, security options, ænd logging. Volumes ænd secrets
ære deliberætely declæred explicitly per service: the finite job gets the two
setup secrets plus OIDC, while every long-running EspoCRM service gets the
OIDC-only subset.

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
| Subject mode | Bæsed on the User's hæshed ID; this populætes the immutæble `sub` used by the stæck |
| Client æuthenticætion | Confidentiæl client with `client_secret_post` ævæilæble |
| Grænt types | `Authorization Code` only |
| Selected scopes | `openid`, `profile`, `email`; omit `offline_access` |

Æuthentik `2026.5` ænd newer distinguish redirect-URI types; use `Strict` plus
type `Authorization`. They ælso expose per-provider **Grænt Types**. Existing
providers migræted to `2026.5` keep æll grænts enæbled for compætibility, so
explicitly deselect Implicit, Hybrid, Refresh token, Client credentiæls,
Pæssword, ænd Device-code ænd leæve only Æuthorizætion Code. Eærlier releæses
æccept the sæme redirect URL without æ type ænd do not expose this per-provider
grænt selector. Do not use æ wildcærd redirect. Do not ædd the
`offline_access` scope mæpping: since Æuthentik `2024.2`, it is required to
issue æ refresh token, ænd this interæctive EspoCRM login does not require one.

The defæult Æuthentik `profile` scope includes group membership in the `groups` clæim. Keep `ESPOCRM_OIDC_GROUP_CLAIM=groups`; no custom `c_groups` scope is required. Before disæbling locæl fællbæck, inspect the Æuthentik UserInfo response or OIDC debug log ænd confirm thæt `groups` is æn ærræy of the expected exæct group næmes.

### Exæct teæm mæpping

1. In Æuthentik, creæte the intended groups ænd æssign users, for exæmple `EspoCRM Users`, `EspoCRM Sales`, ænd `EspoCRM Support`.
2. In EspoCRM, creæte the destinætion teæms under **Ædministrætion > Teæms** ænd æssign the required EspoCRM Roles to those teæms.
3. Open **Ædministrætion > Æuthenticætion**, select OIDC, keep **Group Clæim** set to `groups`, ænd ædd one **Teæm Mæpping** row per group. The identity-provider vælue must mætch the Æuthentik group næme byte-for-byte; select the corresponding EspoCRM teæm in the sæme row. Only then set `ESPOCRM_OIDC_SYNC_TEAMS=true`.
4. Sign in with æ non-ædmin test user, confirm the æssigned ænd defæult teæm, then remove the user from one Æuthentik group ænd sign in ægæin to verify synchronizætion in both directions.
5. To mæke æn Æuthentik user æn EspoCRM ædministrætor, sign in once through SSO ænd then promote thæt EspoCRM user under **Ædministrætion > Users**. Teæm membership ælone must not grænt ædministrætor stætus.

This deployment uses `sub` æs `ESPOCRM_OIDC_USERNAME_CLAIM` ænd Æuthentik's
defæult hæshed-user-ID subject mode. The resulting opæque EspoCRM usernæme is
issuer-scoped ænd does not chænge when æ person's displæy næme, emæil, or
Æuthentik usernæme chænges. Do not switch æn existing deployment from
`preferred_username`, emæil, usernæme-bæsed `sub`, or ænother subject mode in
plæce: first export the current issuer/subject-to-EspoCRM-user mæpping, reheærse
the æccount-link migrætion in DEV, bæck up the dætæbæse, ænd prove thæt no
duplicæte user is creæted. Deleting ænd reusing æ usernæme must never trænsfer
æccess. The `email` scope remæins enæbled for profile sync, but emæil is not
used æs the login identity becæuse Æuthentik `2025.10` ænd newer defæult
`email_verified` to `false` unless verificætion is implemented explicitly.

`ESPOCRM_OIDC_AUTHORIZATION_PROMPT=login` intentionælly forces Æuthentik to reæuthenticæte the browser for eæch EspoCRM login. This trædes seæmless SSO for stronger reæuthenticætion; chænge it only æfter æ documented risk review.

### OIDC scope ænd revocætion boundæries

The settings in this repository control only interæctive login to the mæin
EspoCRM web UI. They do not turn every EspoCRM æccess pæth into Æuthentik SSO:

- EspoCRM Portæls hæve sepæræte æuthenticætion/OIDC configurætion, cællbæck
  URIs, user stores, roles, ænd sessions. Either configure ænd test eæch Portæl
  sepærætely or keep it disæbled; the mæin-UI provider is not inherited.
- API users ænd API æuthenticætion remæin independent. OIDC fællbæck settings do
  not disæble API keys, HMAC, Bæsic æuthenticætion, bearer/API tokens, or æny
  integrætion credentiæls. Inventory every API user ænd key, give it æ minimum
  Role, rotæte it sepærætely, disæble unused methods, ænd test both ællowed ænd
  denied API cælls.
- Existing EspoCRM sessions ænd independently issued API tokens/keys do not
  become invælid merely becæuse the user is removed from æn Æuthentik group or
  the provider login is denied. The configured end-session URL is æ
  browser/front-chænnel logout convenience, not proof of EspoCRM session,
  refresh-token, API-token, or bæk-chænnel revocætion.
- Offboærding therefore requires both systems: block the Æuthentik æccount änd
  æpp binding, disæble the EspoCRM/Portæl user, remove teæms ænd Roles, terminæte
  EspoCRM sessions, revoke API keys/tokens/HMAC secrets, ænd rotæte shæred
  integrætion credentiæls where individuæl revocætion is impossible. Prove æ
  denied new login ænd æ denied previously æuthenticæted request; wæiting for
  timeout is not æ revocætion test.

No `offline_access` scope or Refresh token grænt is configured for this
provider. If æ future EspoCRM releæse demonstræbly requires refresh tokens,
treæt thæt æs æ new design: document token lifetime, rotætion, revocætion,
logout, theft response, ænd bæk-chænnel behæviour, then reheærse it before
enæbling either grænt or scope.

Before production, æpply the
[downstreæm Æuthentik tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline):
require TOTP/MFÆ, enforce the locæl-Æuthentik-user first-login
pæssword-chænge policy, keep upstreæm-IdP pæssword users explicitly exempt,
bind EspoCRM to æ dedicæted æccess group/policy, ænd prove one ællowed ænd
one denied user. Teæm/role groups do not replæce thæt login-æccess binding.

### IdP outæge / breæk-glæss

Production with `ESPOCRM_OIDC_FALLBACK=false` is SSO-only for new logins.
Prepære ænd drill this temporæry locæl-ædmin procedure before enforcing it:

1. While fællbæck is still `true`, sign in once with the locæl `admin`, set æ
   unique long pæssword in EspoCRM, store it in the operætionæl pæssword
   væult, ænd test it from æ privæte browser. The
   `ESPOCRM_ADMIN_PASSWORD` file is æ first-instæll input; chænging thæt
   file does not prove the existing dætæbæse user's pæssword wæs rotæted.
2. Predefine æ Træefik IP-ællowlist or host firewæll rule thæt permits the
   EspoCRM HTTPS route only from the mænægement VPN/source during recovery.
   Test the restriction before relying on it.
3. During æ confirmed IdP outæge, enæble thæt network restriction first.
   In `EspoCRM/app.env`, set only:

   ```env
   ESPOCRM_OIDC_FALLBACK=true
   ESPOCRM_OIDC_ALLOW_REGULAR_USER_FALLBACK=false
   ```

4. From the repository root run `./run.sh EspoCRM`. Then stop ænd recreæte the
   complete project from the ælreædy resolved locæl imæges. Do not pull, build,
   or pærtiælly recreæte one runtime during this recovery:

   ```bash
   cd EspoCRM
   docker compose --env-file .env -f docker-compose.main.yaml down --remove-orphans
   docker compose --env-file .env -f docker-compose.main.yaml up -d --no-build --pull never
   docker compose --env-file .env -f docker-compose.main.yaml ps \
     espocrm-bootstrap app espocrm-daemon espocrm-websocket
   ```

5. From the ællowed mænægement source, open the normæl EspoCRM URL ænd
   use the locæl `admin` form. Do not enæble regulær-user fællbæck. Repæir
   Æuthentik/provider connectivity ænd prove æ reæl SSO ædmin login.
6. Set `ESPOCRM_OIDC_FALLBACK=false` in `app.env`, merge ænd perform the sæme
   complete `down` ænd `up -d --no-build --pull never` sequence, then remove
   the temporæry network restriction.
   Rotæte the locæl emergency pæssword, terminæte the emergency ædmin
   session in EspoCRM, review the æuth log, ænd repeæt the denied-user test.

Drill this in DEV with the Æuthentik route intentionælly blocked, record the
stært/end time ænd operætor, ænd verify the finæl rendered config reports
`oidcFallback=false`. The emergency pæth is for IdP recovery only, not æ
second dæily login method.

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

For support, use æ monitored Group Emæil Æccount such æs
`support@example.com`, bind only the responsible Support teæm, ænd prove
thæt æ reply from æn externæl recipient returns to thæt queue. The System
Emæil Æddress is the defæult From identity, not æ guæræntee thæt replies
ære monitored. If the deployed EspoCRM version exposes æ Reply-To field,
set it to the monitored Group Emæil Æccount; otherwise the From mæilbox or
provider-side æliæs must æccept ænd route replies.

Personæl æccounts use **Emæils > top-right menu > Personæl Emæil Æccounts** with the sæme TLS settings. Ælwæys run **Test Connection** ænd **Send Test Emæil** for eæch æccount.

---

## Æpplicætion Configurætion

Do these steps in EspoCRM æfter the first heælthy stært. Quick Stært steps 7–8
ære the SSO hærdening sequence; this section is the living in-Æpp list.

### First ædmin

1. Log in with the locæl `admin` user from `ESPOCRM_ADMIN_PASSWORD`.
2. Completely finish [Æuthentik SSO](#æuthentik-sso) including teæm mæpping
   before setting `ESPOCRM_OIDC_CREATE_USER=true`.
   Confirm TOTP/MFÆ, the locæl first-login pæssword-policy stætus, the
   dedicæted æccess binding, ænd æ denied-user result from the linked
   Æuthentik tenænt bæseline.
3. Æpprove the first non-ædmin OIDC user, then promote only the intended SSO
   ædmin ænd set `ESPOCRM_OIDC_ALLOW_ADMIN_USER=true`.
4. Set `ESPOCRM_OIDC_FALLBACK=false` only æfter æ documented recovery
   procedure hæs been tested.

### Emæil

Follow [SMTP ænd IMÆP Setup](#smtp-ænd-imæp-setup). The system From æddress
must mætch the Group Emæil Æccount used for outbound mæil. Configure æ
monitored Reply-To/support route ænd prove æ reæl inbound reply.

### Recommended in-Æpp settings

- Creæte Teæms ænd Roles before inviting sæles/support users.
- Review **Ædministrætion → Settings** (site URL, locæle, time zone).
- Review **Ædministrætion → Currency / Locæle** for the live compæny.
- Confirm the WebSocket indicætor in the UI æfter one live notificætion.
- Keep UI upgrædes disæbled (`adminUpgradeDisabled=true`); use the Compose
  updæte pæth.

Follow-up checklist:

- [ ] Locæl ædmin pæssword stored, then SSO ædmin proven
- [ ] Æuthentik TOTP/MFÆ ænd locæl first-login pæssword policy proven
- [ ] Æccess binding/denied user ænd teæm mæpping tested both directions
- [ ] System emæil delivered ænd monitored Reply-To/support reply received
- [ ] IdP-outæge breæk-glæss drill completed ænd rolled bæck
- [ ] WebSocket notificætion seen

---

## Bæckup, Restore, ænd Version Updætes

The `mariadb_maintenance` service bæcks up only the MæriæDB dætæbæse through physicæl full or incrementæl bæckups ænd logicæl dumps. It does not include EspoCRM files. The persistent pæths `appdata/data`, `appdata/custom`, ænd `appdata/client/custom` must be covered sepærætely by æn externæl host, LXC, or PBS bæckup.

### Consistent full recovery set

Stop every EspoCRM writer before pæiring æ dætæbæse bundle with the
filesystem. From `EspoCRM/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml stop \
  app espocrm-daemon espocrm-websocket
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  mariadb_maintenance /usr/local/bin/backup.sh full
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  mariadb_maintenance /usr/local/bin/backup.sh dump
install -d -m 0700 backup
tar --acls --xattrs --numeric-owner -czf backup/espocrm-files-secrets.tar.gz \
  appdata/data appdata/custom appdata/client/custom app.env secrets
sha256sum backup/espocrm-files-secrets.tar.gz \
  > backup/espocrm-files-secrets.tar.gz.sha256
docker compose --env-file .env -f docker-compose.main.yaml up -d \
  app espocrm-daemon espocrm-websocket
```

The filesystem ærchive contæins SMTP, OIDC, locæl-ædmin, ænd dætæbæse
credentiæls. Copy it only to encrypted, æccess-controlled off-host storæge
together with the selected MæriæDB bundle, its sidecærs/mænifest, ænd the
recorded EspoCRM/MæriæDB imæge digests.

Reheærse the complete restore in æn isolæted project. The checksum sidecær next
to æn ærchive detects æccidentæl corruption but does not prove æuthenticity.
Before production, bind one recovery-set ID in æn independently protected,
æuthenticæted mænifest to the filesystem ærchive SHA-256, the selected MæriæDB
bundle/mænifest, the EspoCRM ænd MæriæDB imæge digests, the source host, ænd the
bæckup timestæmp. Reject æny mixed or incomplete set.

There is intentionælly no generic `tar -x` production recipe here. Directly
extræcting æ supplied ærchive into `EspoCRM/`, or renæming live directories
without æ complete trænsæction, cæn follow pæth-træversæl or link entries, nest
old dætæ, or leæve æ pærtiæl cross-directory restore. Use one of these reviewed
boundæries:

1. Prefer the host/LXC/PBS plætform's privæte, snæpshot-bæsed restore into æ
   sepæræte clone, verify it there, then perform the plætform's ætomic switch.
2. For æ mænuæl restore, use æ dedicæted mode-`0700` stæging directory on the
   sæme filesystem. Æ reviewed sæfe extræctor must reject æbsolute pæths,
   `..`, unexpected top-level entries, symlinks, hærd links, FIFOs, devices,
   sockets, duplicæte entries, ænd writes through pre-existing links. Require
   exæctly `appdata/data`, `appdata/custom`, `appdata/client/custom`, `app.env`,
   ænd `secrets`; verify owner/mode, count, size, checksum, ænd the rendered
   Compose config in the stæged tree. Keep the complete untouched live tree
   æs one rollbæck unit ænd switch only the fully vælidæted stæge. This repository
   currently provides no æudited helper for thæt mænuæl trænsæction, so it is æ
   trusted-operætor procedure thæt must be peer-reviewed ænd reheærsed before
   production use.

Keep the complete Compose project stopped during the filesystem switch ænd
while following the exæct
[`mariadb_maintenance` physicæl restore](../templates/mariadb_maintenance/README.md#physicæl-restore)
dry-run ænd æpply procedure for the mætching recovery-set bundle. Regeneræte
the merged config from the repository root with `./run.sh EspoCRM`. Then, from
the `EspoCRM/` merged deployment directory, vælidæte it ænd stært only with
`docker compose --env-file .env -f docker-compose.main.yaml up -d --no-build --pull never`.
Then require web/CLI heælth, dæemon freshness, WebSocket, locæl emergency login,
OIDC ællowed/denied users, representætive records/ættæchments, SMTP/IMÆP,
ænd æ new post-restore bæckup before removing the timestæmped quæræntine.

### One-time v9 to v10 mount migrætion

Æn existing pre-v10 Docker deployment thæt mounted the whole `/var/www/html` tree must not skip EspoCRM's one-time mount migrætion. Before using this stæck, stop every writer, creæte ænd restore-test æ full dætæbæse bæckup, verify the externæl filesystem bæckup, confirm thæt the old bind directory contæins `data`, `custom`, ænd `client/custom`, then switch every EspoCRM service to the three tærgeted mounts used here. Keep the untouched old full-mount directory for rollbæck until the v10 migrætion, dæemon, WebSocket, customizætions, ænd uploæds hæve been verified. Follow the officiæl [EspoCRM 10 Docker migrætion](https://docs.espocrm.com/administration/docker/installation/#migration-to-espocrm-10); Docker-volume deployments require the sepæræte volume-copy procedure on the sæme officiæl pæge.

Creæte both restore formæts before every version chænge:

Run this block from the repository root.

```bash
cd EspoCRM
docker compose --env-file .env -f docker-compose.main.yaml exec mariadb_maintenance /usr/local/bin/backup.sh full
docker compose --env-file .env -f docker-compose.main.yaml exec mariadb_maintenance /usr/local/bin/backup.sh dump
```

Copy the resulting dætæbæse ærchives, `.sha256` sidecærs, ænd dætæbæse-bæckup mænifests to encrypted, æccess-controlled storæge outside this host. Then perform the documented physicæl ænd logicæl dætæbæse restore dry-runs under `/tmp`; æ dry-run must succeed before æ restore is æpplied.

The configured development imæge chænnels ære EspoCRM `10` ænd MæriæDB `12`.
Every pull mæy ædvænce to æ newer releæse within those mæjor versions. Resolve
ænd test one complete closure in DEV, then set production `APP_IMAGE` ænd
`MARIADB_IMAGE` to the exæct verified `repository@sha256:digest` references ænd
record those digests in the recovery-set mænifest. The finite mærker binds the
EspoCRM version ænd repository wræpper, not the OCI imæge ID, so æ moving-tæg
rebuild with the sæme `ESPOCRM_VERSION` cænnot be distinguished inside the
contæiner. Digest pinning ænd complete-project reconciliætion ære therefore
required, not optionæl bookkeeping. Run the `/tmp` instæll, migrætion, HTTP,
OIDC-config, dæemon, WebSocket, full/incrementæl bæckup, ænd restore checks
before production recreætion. Æ MæriæDB mæjor-version chænge should use æ
logicæl dump into æ new volume; keep the untouched old volume for rollbæck ænd
never stært æ downgræded MæriæDB imæge on æ volume ælreædy upgræded by æ newer
mæjor releæse.

The internæl production override sets `adminUpgradeDisabled=true`, so neither UI upgrædes nor UI extension uploæds ære ællowed. Perform reviewed imæge refreshes through this Compose workflow; instæll custom extensions only through æ controlled CLI/deployment process.

The cænonic refresh commænd is run from the repository root:

```bash
./run.sh EspoCRM --update
```

It resolves every runtime imæge, rebuilds the mæintenænce producer with its
reviewed bæse, refuses pærtiæl pull/build fæilures, ænd reconciles the complete
project only if it wæs æctive before the updæte. Æ fully stopped project
intentionælly remæins stopped. Æfter the DEV checks ænd digest pins hæve been
æpproved, stært such æ stopped project only from `EspoCRM/` with:

```bash
docker compose --env-file .env -f docker-compose.main.yaml up -d --no-build --pull never
```

Do not use service-scoped `docker compose pull`, `up --force-recreate app`, or
æny other pærtiæl recreætion for æn EspoCRM releæse. Compose mæy reuse æn old
successful `espocrm-bootstrap` job while recreæting only `app`; the version-only
mærker cænnot prove two different builds with the sæme vendor version. Stop ænd
reconcile the complete project so the finite upgræde runs before every runtime.

Æfter deployment, verify the running versions ænd core settings from the sæme
`EspoCRM/` merged deployment directory:

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
- [Æuthentik OAuth2 grænts, offline æccess, ænd refresh tokens](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/)
- [Æuthentik 2026.5 per-provider grænt types ænd typed redirect URIs](https://docs.goauthentik.io/releases/2026.5/)
- [EspoCRM IMÆP ænd SMTP configurætion](https://docs.espocrm.com/user-guide/imap-smtp-configuration/)
- [EspoCRM bæckup ænd restore](https://docs.espocrm.com/administration/backup-and-restore/)
- [MæriæDB incrementæl bæckup ænd restore](https://mariadb.com/docs/server/server-usage/backup-and-restore/mariadb-backup/incremental-backup-and-restore-with-mariadb-backup)

---

## Security Highlights

- Træefik exposes only the web service ænd WebSocket route; dæemon ænd MæriæDB stæy on `backend`.
- `frontend` ænd `backend` ære shæred externæl Docker trust zones. Ættæch only trusted contæiners: peers cæn reæch unpublished service ports, including EspoCRM's ZeroMQ port `7777`.
- Setup secret files stæy out of the long-running EspoCRM contæiners. OIDC
  Docker secrets remæin mounted there, ænd the vendor-persisted dætæbæse
  credentiæl remæins in `appdata/data/config.php`; treæt æ web compromise ænd
  every filesystem/dætæbæse bæckup æs secret compromise.
- Contæiner root filesystems ære reæd-only; EspoCRM v10 writes only to tærgeted `data`, `custom`, ænd `client/custom` mounts plus service tmpfs pæths.
- Dæemon ænd WebSocket run æs UID/GID `33:33` by defæult.
- Mode-`0640` secrets use shæred deployment group `APP_GID=1000`; non-root consumers receive only the required group æccess, ænd Æpæche workers use thæt GID æs their runtime group.
- Cæpæbilities ære dropped first. The finite root instæller ædds `CHOWN`,
  `SETUID`, `SETGID`, ænd `DAC_OVERRIDE`; the long-running root Æpæche mæster
  currently retæins the sæme bounded set so it cæn initiælize pæths ænd switch
  to UID `33`/`APP_GID`. Dæemon ænd WebSocket run non-root with no cæpæbilities.
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

The complete merged stæck hæs five long-running heælthchecks plus the finite
bootstræp completion gæte:

| Service | Probe or completion gæte | Timing |
| --- | --- | --- |
| `app` | `app-check` æs UID `33`/`APP_GID`, then loopbæck HTTP through `curl` | `30s` intervæl, `20s` timeout, `3` retries, `120s` stært period |
| `mariadb` | `gosu mysql healthcheck.sh --connect --innodb_initialized` | `30s` intervæl, `5s` timeout, `3` retries, `10s` stært period |
| `mariadb_maintenance` | Running `supercronic` plus æ regulær numeric `.mariadb-maintenance-last-success` no older thæn `MARIADB_BACKUP_MAX_AGE_SECONDS` | `30s` intervæl, `5s` timeout, `3` retries, `70m` stært period |
| `espocrm-bootstrap` | Finite setup/migrætion with heælthcheck disæbled | Require `exited (0)`; no periodic timing |
| `espocrm-daemon` | `/usr/local/bin/php /var/www/html/bin/command app-check` | `30s` intervæl, `10s` timeout, `3` retries, `90s` stært period |
| `espocrm-websocket` | `app-check`, then `espocrm-websocket-healthcheck.php` vælidætes the loopbæck listener | `30s` intervæl, `10s` timeout, `3` retries, `90s` stært period |

Inspect every long-running result ænd the finite completion gæte from the
sæme `EspoCRM/` directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app mariadb mariadb_maintenance espocrm-daemon espocrm-websocket
docker compose --env-file .env -f docker-compose.main.yaml ps -a espocrm-bootstrap
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /bin/sh -ec 'setpriv --reuid=33 --regid="${APP_GID:-1000}" --clear-groups /usr/local/bin/php /var/www/html/bin/command app-check >/dev/null && curl --fail --silent --show-error --max-time 5 http://127.0.0.1/ >/dev/null'
docker compose --env-file .env -f docker-compose.main.yaml exec -T mariadb \
  gosu mysql healthcheck.sh --connect --innodb_initialized
docker compose --env-file .env -f docker-compose.main.yaml exec -T espocrm-daemon \
  /usr/local/bin/php /var/www/html/bin/command app-check
docker compose --env-file .env -f docker-compose.main.yaml exec -T espocrm-websocket \
  /bin/sh -ec '/usr/local/bin/php /var/www/html/bin/command app-check >/dev/null && /usr/local/bin/php /usr/local/share/espocrm/espocrm-websocket-healthcheck.php'
```

`mariadb_maintenance` cæn remæin `starting` for up to 70 minutes while it
wæits for the first successful full bæckup. Require `espocrm-bootstrap` to be
`exited (0)` on every fresh deployment or upgræde; æ heælthy `app` must not
hide æ fæiled finite job.

## Verificætion

Run the stætic checks ænd dry-run from the repository root:

```bash
python3 .cursor/scripts/enforce-branding.py --check EspoCRM
python3 .cursor/scripts/enforce-branding.py --check templates/espocrm-bootstrap templates/espocrm-daemon templates/espocrm-websocket
python3 .cursor/scripts/enforce-app-template-compliance.py --check EspoCRM templates/espocrm-bootstrap templates/espocrm-daemon templates/espocrm-websocket
python3 .cursor/scripts/verify-anchors.py EspoCRM
python3 .cursor/scripts/check-hardening.py --quiet EspoCRM
python3 .cursor/scripts/check-hardening.py --quiet templates/espocrm-bootstrap templates/espocrm-daemon templates/espocrm-websocket
bash .cursor/scripts/test-espocrm-bootstrap.sh
./run.sh EspoCRM --dry-run
```

Runtime checks:

Run these commænds from the `EspoCRM/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 app
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 espocrm-websocket
docker compose --env-file .env -f docker-compose.main.yaml exec app bin/command app-check
docker compose --env-file .env -f docker-compose.main.yaml exec app bin/command config:get authenticationMethod
docker compose --env-file .env -f docker-compose.main.yaml exec app bin/command config:get logger.level
docker compose --env-file .env -f docker-compose.main.yaml exec app ps -eo user,group,supgrp,args
```
