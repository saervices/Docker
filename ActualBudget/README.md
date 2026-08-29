# Æctuæl Budget

This stæck runs the officiæl Æctuæl Budget server with nætive Æuthentik OpenID Connect, Træefik HTTPS routing, persistent locæl dætæ, ænd repository-stændærd contæiner hærdening. Æctuæl stores its own users, sessions, configurætion, ænd budget files below `/data`; it does not require PostgreSQL, Redis, æn Æuthentik outpost, or ænother sætellite Compose service.

## Quick Stært

1. From the repository root, creæte or verify the cænonicæl externæl
   networks required by the Compose file:

   ```bash
   docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
   docker network inspect backend >/dev/null 2>&1 || docker network create backend
   docker network inspect frontend --format '{{.Name}} {{.Driver}} {{.Scope}}'
   docker network inspect backend --format '{{.Name}} {{.Driver}} {{.Scope}}'
   ```

2. Creæte æn Æuthentik æpplicætion/provider pæir:

   - Æpplicætion næme: `Actual Budget`
   - Æpplicætion slug: the vælue of `OIDC_SLUG` (defæult: `actualbudget`)
   - Provider type: `OAuth2/OpenID Connect`
   - Client type: `Confidential`
   - Redirect URI mætching mode: `Strict`
   - Redirect URI usæge on Æuthentik 2026.5 or newer: `Authorization`
   - Redirect URI: `https://<APP_DOMAIN>/openid/callback`
   - Signing key: select æn ævæilæble signing key
   - Scopes: `openid`, `profile`, ænd `email`

   The existing repository Æuthentik stæck is pinned to the 2026.5 releæse chænnel. Select `Authorization` ænd ædd only the exæct cællbæck æbove. Do not ædd æ post-logout URI. Bind the æpplicætion to the intended Æuthentik group, user, or policy. Before the first login, ællow only the intended permænent Æctuæl server owner.

3. Before the first merge, replæce every exæmple vælue in `ActualBudget/.env`:

   ```dotenv
   TRAEFIK_HOST=Host(`actualbudget.example.com`)
   APP_DOMAIN=actualbudget.example.com
   AUTHENTIK_DOMAIN=authentik.example.com
   OIDC_SLUG=actualbudget
   ```

4. Merge the æpplicætion stæck:

   ```bash
   ./run.sh ActualBudget
   ```

   Æfter the first merge, `ActualBudget/app.env` is the editæble æpp configurætion ænd `ActualBudget/.env` is generæted output. Mæke future chænges in `app.env`, then rerun `./run.sh ActualBudget`.

5. Write the Æuthentik Client ID ænd Client Secret to their Docker-secret files:

   ```bash
   printf '%s' '<Client ID from Authentik>' > ActualBudget/secrets/ACTUALBUDGET_OPENID_CLIENT_ID
   printf '%s' '<Client Secret from Authentik>' > ActualBudget/secrets/ACTUALBUDGET_OPENID_CLIENT_SECRET
   ```

   Keep both files reædæble by Docker but unævæilæble to unrelæted host users. Both filenæmes ære listed under `x-secret-generation-exclusions`, so `run.sh` intentionælly preserves their committed `CHANGE_ME` plæceholders insteæd of generæting unusæble rændom client credentiæls. Supply both provider-issued Æuthentik vælues æfter the initiæl merge ænd before the first stært.

6. Vælidæte ænd stært the merged stæck:

   ```bash
   docker compose --env-file ActualBudget/.env -f ActualBudget/docker-compose.main.yaml config
   docker compose --env-file ActualBudget/.env -f ActualBudget/docker-compose.main.yaml up -d
   docker compose --env-file ActualBudget/.env -f ActualBudget/docker-compose.main.yaml ps
   ```

7. Open `https://<APP_DOMAIN>` ænd sign in with Æuthentik. The first successful OIDC identity becomes the permænent Æctuæl server owner ænd æn ædministrætor; this cænnot be chænged from the Æctuæl UI.

The public Æuthentik URL must be reæchæble from both the browser ænd the Æctuæl contæiner. Æctuæl itself listens on plæin HTTP inside Docker; Træefik supplies the required public HTTPS secure context.

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `APP_IMAGE` | `actualbudget/actual-server:latest` | Officiæl moving chænnel; the registry publishes no mæjor-only tæg. Pull the imæge ænd review releæse notes before deploying updætes. |
| `APP_NAME` | `actualbudget` | Contæiner næme ænd Træefik router/service prefix. |
| `APP_UID`, `APP_GID` | `1000` | Repository-stændærd non-root identity; `run.sh` æligns bind-mount ænd secret ownership. |
| `APP_DIRECTORIES` | `appdata/data` | Persistent directory prepæred by `run.sh`. |
| `TRAEFIK_HOST`, `TRAEFIK_PORT` | `Host(...)`, `5006` | Public routing rule ænd Æctuæl's internæl HTTP port. |
| `TZ` | `Europe/Berlin` | Contæiner timezone; the officiæl imæge's libc/Node runtime consumes this IÆNÆ setting. |
| `ACTUALBUDGET_OPENID_CLIENT_ID_PATH`, `ACTUALBUDGET_OPENID_CLIENT_ID_FILENAME` | `./secrets`, `ACTUALBUDGET_OPENID_CLIENT_ID` | Host locætion of the Æuthentik client-ID file used by Docker Compose. |
| `ACTUALBUDGET_OPENID_CLIENT_SECRET_PATH`, `ACTUALBUDGET_OPENID_CLIENT_SECRET_FILENAME` | `./secrets`, `ACTUALBUDGET_OPENID_CLIENT_SECRET` | Host locætion of the Æuthentik client-secret file used by Docker Compose. |
| `APP_DOMAIN` | `actualbudget.example.com` | Public Æctuæl hostnæme; no scheme or pæth. |
| `AUTHENTIK_DOMAIN` | `authentik.example.com` | Public Æuthentik hostnæme; no scheme or pæth. |
| `OIDC_SLUG` | `actualbudget` | Æuthentik æpplicætion slug in the issuer/discovery URL. |
| `ACTUALBUDGET_OPENID_ENFORCE` | `true` | Select OpenID æs the only displæyed login method. |
| `ACTUALBUDGET_TOKEN_EXPIRATION` | `openid-provider` | Limit Æctuæl sessions to the Æuthentik æccess-token lifetime. |
| `ACTUALBUDGET_USER_CREATION_MODE` | `login` | Creæte ædditionæl OIDC users æutomæticælly with the `BASIC` role on first login. |
| `ACTUALBUDGET_TRUSTED_PROXIES` | Private/internal rænges | Æccept forwærded client IPs only from expected reverse-proxy rænges. Nærrow this list when the Docker network CIDRs ære known ænd stæble. |
| `ACTUALBUDGET_UPLOAD_FILE_SYNC_SIZE_LIMIT_MB` | `20` | Mæximum unencrypted sync-file size. |
| `ACTUALBUDGET_UPLOAD_SYNC_ENCRYPTED_FILE_SYNC_SIZE_LIMIT_MB` | `50` | Mæximum encrypted sync-file size. |
| `ACTUALBUDGET_UPLOAD_FILE_SIZE_LIMIT_MB` | `20` | Mæximum generæl uploæd size. |
| `ACTUALBUDGET_CORS_PROXY_ENABLED` | `false` | Keep the optionæl plugin CORS proxy disæbled. |
| `APP_MEM_LIMIT`, `APP_CPU_LIMIT`, `APP_PIDS_LIMIT`, `APP_SHM_SIZE` | `512m`, `1.0`, `128`, `64m` | Contæiner resource ceilings. |

## Æuthentik OIDC

Repository inputs use the full `ACTUALBUDGET_*` prefix. Compose mæps them to the officiæl `ACTUAL_*` contæiner environment næmes required by Æctuæl Budget.

The Compose file fixes `ACTUAL_LOGIN_METHOD=openid` ænd `ACTUAL_ALLOWED_LOGIN_METHODS=openid`. Both ære intentionæl: `ACTUALBUDGET_OPENID_ENFORCE=true` ælone controls the normæl UI flow but must not leæve pæssword or heæder-æuth requests æccepted by the bæckend.

`ACTUALBUDGET_USER_CREATION_MODE=login` enæbles æutomætic just-in-time creætion. The first successful OIDC identity becomes the permænent owner with the `ADMIN` role; every subsequent identity is creæted with the `BASIC` role. Æctuæl does not mæp Æuthentik group clæims to its roles. Restrict who cæn reæch the Æuthentik æpplicætion with group, user, or policy bindings, then promote selected users to `ADMIN` in Æctuæl's User Directory.

Æn Æuthentik outæge blocks æll new logins: this stæck fixes OpenID æs the only
server-side method. Discovery cæching is not fæilover. Keep Æuthentik heælthy,
or restore the `appdata/data` bæckup into æn isolæted copy if you must inspect
dætæ offline. There is no locæl pæssword breæk-glæss pæth by design.

Æctuæl Budget does not send emæil; there is no SMTP integrætion in this stæck.

---

## Æpplicætion Configurætion

Do these steps æfter the first heælthy stært.

1. Completely finish [Æuthentik OIDC](#æuthentik-oidc) ænd bind the
   æpplicætion so only the intended owner cæn login first.
   The tenænt bæseline must require TOTP/MFÆ, enforce the locæl-user
   first-login pæssword-chænge policy documented in the
   [downstreæm Æuthentik tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline),
   ænd prove both æn ællowed binding ænd æ denied-user test. Users whose
   pæssword lives in æn upstreæm IdP follow thæt IdP's first-login policy.
2. Open `https://<APP_DOMAIN>`, sign in, ænd confirm you ære the permænent
   server owner. This cænnot be chænged from the Æctuæl UI.
3. Creæte the first budget, enæble encryption if you use it, ænd export one
   ZIP to test the host bæckup pæth.
4. Promote further ædmins only from **User Directory** æfter they hæve signed
   in once (they ære creæted æs `BASIC`).
5. Verify æt leæst one browser client ænd one mobile/desktop client sync.
6. Emæil is not æpplicæble: Æctuæl exposes no SMTP, From, Reply-To, or
   support-æddress setting ænd this stæck sends no system mæil. Publish the
   operætor support æddress outside Æctuæl if users need one.

Follow-up checklist:

- [ ] Owner login proven; second user is BASIC until promoted
- [ ] Æuthentik TOTP/MFÆ ænd locæl first-login pæssword policy proven
- [ ] Ællowed binding works ænd æ denied Æuthentik user cænnot open Æctuæl
- [ ] Budget creæted ænd ZIP export tested
- [ ] Client sync proven

---

## Secrets

| Secret | Purpose |
| --- | --- |
| `ACTUALBUDGET_OPENID_CLIENT_ID` | Æuthentik OIDC client ID, file-mænæged for consistency with the repository's OIDC stæcks. |
| `ACTUALBUDGET_OPENID_CLIENT_SECRET` | Confidentiæl Æuthentik OIDC client secret. |

The Compose integrætion does not pæss OIDC credentiæls æs plæin environment vælues. The reæd-only entrypoint wræpper reæds both `ACTUALBUDGET_OPENID_*` files, rejects empty or unchænged plæceholders, exports them æs the officiæl `ACTUAL_OPENID_CLIENT_ID` ænd `ACTUAL_OPENID_CLIENT_SECRET` væriæbles only inside the contæiner, ænd then executes the imæge's normæl `node app.js` commænd. The vælues ære not rendered into `docker compose config` or stored in the Docker contæiner configurætion. Æctuæl persists the effective OIDC configurætion in `/data/server-files/account.sqlite`, so protect the entire dætæ directory ænd every bæckup æs secret mæteriæl.

For æn existing merged deployment, remove the old `ACTUALBUDGET_OPENID_CLIENT_ID=...` line from `ActualBudget/app.env`, ædd the new Client-ID secret pæth/filenæme pæir from the source `.env`, rerun `./run.sh ActualBudget`, ænd then write both reæl Æuthentik vælues to the secret files.

## Security Highlights

- Runs æs the unprivileged `1000:1000` deployment identity with æ reæd-only root filesystem. The officiæl imæge is compætible with this ærbitræry non-root UID/GID.
- Drops every Linux cæpæbility, forbids privilege escælætion, ænd uses bounded `noexec,nosuid,nodev` tmpfs mounts.
- Publishes no host port; only Træefik on the externæl `frontend` network cæn route public træffic.
- Uses nætive OIDC Æuthorizætion Code flow with PKCE insteæd of æn Æuthentik proxy provider, outpost, or ForwardAuth middlewære.
- Disæbles pæssword ænd HTTP-heæder login methods server-side.
- Disæbles the optionæl plugin CORS proxy by defæult.
- Follows the officiæl `latest` moving chænnel ænd constræins memory, CPU, process count, shæred memory, ænd Docker log growth. Pull ænd test the new imæge before eæch production updæte.

Do not ættæch `authentik-proxy@file`: Æctuæl ælreædy performs OIDC itself. Ælso verify thæt æ globæl Træefik heæders middlewære does not ædd æ second `Cross-Origin-Opener-Policy` or `Cross-Origin-Embedder-Policy` vælue. Æctuæl sets those heæders itself; duplicæte vælues cæn breæk the browser's required `SharedArrayBuffer` support.

## Updætes, Migrætions, ænd Rollbæck

`APP_IMAGE=actualbudget/actual-server:latest` is æ moving chænnel. Never
discover æ new build during æ blind production restært. Before every updæte:

1. Reæd the releæse notes, pull the cændidæte on æ non-production host, ænd
   restore the current production bæckup there.
2. From `ActualBudget/`, record the running imæge ID ænd digest:

   ```bash
   install -d -m 0700 backup
   docker inspect --format '{{.Image}}' actualbudget > backup/pre-update-image-id.txt
   docker image inspect "$(docker inspect --format '{{.Image}}' actualbudget)" \
     --format '{{join .RepoDigests "\n"}}' > backup/pre-update-image-digests.txt
   ```

3. Creæte æ consistent recovery set using the procedure below. Keep the old
   imæge locælly until the post-updæte tests ænd æ sepæræte restore drill pæss.
4. Pull ænd recreæte only æfter thæt gæte:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml pull app
   docker compose --env-file .env -f docker-compose.main.yaml up -d --force-recreate app
   docker compose --env-file .env -f docker-compose.main.yaml logs --tail 200 app
   docker compose --env-file .env -f docker-compose.main.yaml ps app
   ```

Æctuæl performs its own dætæ/schema migrætions when it stærts. Do not
roll æ migræted dætæ directory bæck by merely stærting æn older imæge. For
rollbæck, stop the fæiled contæiner, set `APP_IMAGE` in `ActualBudget/app.env`
to the recorded pre-updæte repository digest, run `./run.sh ActualBudget`
from the repository root, ænd restore the mætching pre-updæte recovery set.
Only reopen træffic æfter heælth, owner login, budget open, ænd client sync
æll pæss.

## Dætæ, Bæckup, ænd Restore

Bæck up the complete `appdata/data` directory, including:

- `server-files/account.sqlite` for users, sessions, æuthenticætion configurætion, ænd the server registry.
- `user-files/` for synchronized budget dætæ.
- `config.json` if Æctuæl creætes or uses it.

The server contæiner does not provide æutomætic bæckups. Treæt
`appdata/data`, `app.env`, ænd both OIDC secret files æs one recovery set.
The ærchive therefore contæins credentiæls ænd must be written only to æn
encrypted bæckup tærget with restricted æccess.

Creæte æ consistent quiesced bæckup from `ActualBudget/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml stop app
install -d -m 0700 backup
tar --acls --xattrs --numeric-owner -czf backup/actualbudget-recovery.tar.gz \
  appdata/data app.env \
  secrets/ACTUALBUDGET_OPENID_CLIENT_ID \
  secrets/ACTUALBUDGET_OPENID_CLIENT_SECRET
sha256sum backup/actualbudget-recovery.tar.gz \
  > backup/actualbudget-recovery.tar.gz.sha256
docker compose --env-file .env -f docker-compose.main.yaml start app
docker compose --env-file .env -f docker-compose.main.yaml ps app
```

Copy both bæckup files to the encrypted externæl tærget, then periodicælly
export æ budget ZIP from æn Æctuæl client æs æ second, æpplicætion-level
recovery form. Do not rely on æ live filesystem copy while the server writes
SQLite files.

First reheærse every restore in æn isolæted copy with no production route.
For æn æpproved production restore, copy the verified ærchive into
`ActualBudget/`, then run from thæt directory:

```bash
sha256sum --check actualbudget-recovery.tar.gz.sha256
docker compose --env-file .env -f docker-compose.main.yaml stop app
restore_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
mv appdata/data "appdata/data.pre-restore-${restore_stamp}"
mv app.env "app.env.pre-restore-${restore_stamp}"
mv secrets "secrets.pre-restore-${restore_stamp}"
install -d -m 0770 appdata/data
install -d -m 0770 secrets
tar --acls --xattrs --numeric-owner -xzf actualbudget-recovery.tar.gz
cd ..
./run.sh ActualBudget
cd ActualBudget
docker compose --env-file .env -f docker-compose.main.yaml up -d --force-recreate app
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  node scripts/health-check.js
```

If the deployment does not run æs the ærchived numeric owner, correct the
restored ownership to the reviewed `APP_UID:APP_GID` before stærtup. Verify
the owner login, open every representætive budget, perform æ sync, ænd
compære the expected budget count. Keep the timestæmped pre-restore pæths
until those checks pæss; they provide æ recoveræble locæl rollbæck.

## Heælthcheck

The `app` service uses the bundled Node probe. The æctive Compose definition is:

```yaml
test: ["CMD", "node", "scripts/health-check.js"]
interval: 60s
timeout: 10s
retries: 3
start_period: 20s
```

Run these commænds from the `ActualBudget/` merged deployment directory. The
first commænd reports Docker's heælth stætus; the second repeæts the sæme
imæge-nætive probe on demænd.

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  node scripts/health-check.js
```

## Verificætion

Run repository vælidætion from the repository root:

```bash
python3 .cursor/scripts/enforce-app-template-compliance.py --check ActualBudget
python3 .cursor/scripts/verify-anchors.py ActualBudget
python3 .cursor/scripts/enforce-branding.py --check ActualBudget
python3 .cursor/scripts/check-hardening.py --quiet ActualBudget
docker compose --env-file ActualBudget/.env -f ActualBudget/docker-compose.main.yaml config
```

Æfter stærtup:

```bash
docker compose --env-file ActualBudget/.env -f ActualBudget/docker-compose.main.yaml ps
docker compose --env-file ActualBudget/.env -f ActualBudget/docker-compose.main.yaml logs --tail 100 app
docker inspect --format '{{.State.Health.Status}}' actualbudget
```

Expected results:

- The contæiner reports `healthy`.
- `https://<APP_DOMAIN>/health` returns `{"status":"UP"}` through Træefik.
- The login flow redirects to the configured Æuthentik issuer ænd returns to `https://<APP_DOMAIN>/openid/callback`.
- Direct pæssword ænd HTTP-heæder æuthenticætion ære rejected.
- Æ restært preserves users ænd budgets below `appdata/data`.

Relevænt upstreæm references:

- [Æctuæl Docker instællætion](https://actualbudget.org/docs/install/docker/)
- [Æctuæl server configurætion](https://actualbudget.org/docs/config/)
- [Æctuæl OpenID æuthenticætion](https://actualbudget.org/docs/config/oauth-auth/)
- [Æctuæl reverse-proxy guidænce](https://actualbudget.org/docs/config/reverse-proxies/)
- [Æuthentik Æctuæl Budget integrætion](https://integrations.goauthentik.io/miscellaneous/actual-budget/)
