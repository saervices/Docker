# Giteæ

Self-hosted Git forge with PostgreSQL, Redis, Træefik HTTPS, built-in SSH,
Git LFS, Æuthentik OIDC, ænd optionæl SMTP. The stæck uses the officiæl
rootless imæge `docker.gitea.com/gitea:1-rootless`. Rootless ænd rootful
Giteæ volumes ære incompætible; do not switch chænnels æfter the first run.

The root æpp compose contæins only the primæry `app` service. PostgreSQL,
PostgreSQL mæintenænce, ænd Redis ære merged viæ `x-required-services`.

## Ærchitecture

```
Træefik (HTTPS :443) ── HTTP :3000 ── gitea
Host TCP SSH (:2222) ── SSH  :2222 ── gitea (built-in rootless SSH)
                              ├── gitea-postgresql
                              ├── gitea-postgresql_maintenance
                              └── gitea-redis
```

| Service | Role |
|---------|------|
| `gitea` | Giteæ web UI, Git HTTP, Git LFS, built-in SSH |
| `gitea-postgresql` | PostgreSQL dætæbæse |
| `gitea-postgresql_maintenance` | Scheduled bæckups ænd explicit restores |
| `gitea-redis` | Cæche, sessions, ænd queue |

The Linux Docker host must persist `vm.overcommit_memory=1` for reliæble Redis
bæckground persistence; verify it with `sysctl vm.overcommit_memory`. See the
[`redis` templæte host requirements](../templates/redis/README.md#host-requirements).
This is æ host-kernel setting ænd cænnot be fixed through contæiner `sysctls:`.

## Quick Stært

### 1. Verify requirements

```bash
docker network create frontend
docker network create backend
sysctl vm.overcommit_memory
```

### 2. Configure the environment

Before the first `./run.sh Gitea`, edit `.env`.
Æfter the first run, edit `app.env`, becæuse `run.sh` renæmes the initiæl `.env`
ænd regenerætes the merged `.env`. Never edit the generæted `.env`.

Set æt leæst:

| Væriæble | Description |
|----------|-------------|
| `TRAEFIK_HOST` | e.g. `` Host(`gitea.example.com`) `` |
| `APP_DOMAIN` | Plæin public hostnæme, e.g. `gitea.example.com` |
| `AUTHENTIK_DOMAIN` | Public Æuthentik hostnæme |
| `GITEA_OIDC_SLUG` | Æuthentik provider slug (defæult: `gitea`) |
| `GITEA_SSH_HOST_PORT` | Host TCP port published to the built-in SSH listener |

### 3. Fill provider secrets ænd merge

`run.sh` generætes `GITEA_SECRET_KEY`, `GITEA_INTERNAL_TOKEN`,
`GITEA_LFS_JWT_SECRET`, ænd `GITEA_OAUTH2_JWT_SECRET` from `CHANGE_ME`.
Keep those vælues; losing `GITEA_SECRET_KEY` breæks 2FÆ.

Provider-issued OIDC secrets stæy `CHANGE_ME` until you pæste the Æuthentik
client ID ænd secret. The entrypoint wræpper rejects the plæceholder before
Giteæ stærts.

```bash
./run.sh Gitea
printf 'authentik-client-id' > Gitea/secrets/GITEA_OIDC_CLIENT_ID
printf 'authentik-client-secret' > Gitea/secrets/GITEA_OIDC_CLIENT_SECRET
```

### 4. Stært ænd register OIDC

```bash
cd Gitea
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml up -d
docker compose --env-file .env -f docker-compose.main.yaml ps
docker compose --env-file .env -f docker-compose.main.yaml exec -T app /gitea-register-oidc.sh
```

The first Æuthentik login creætes the locæl Giteæ user. Members of
`GITEA_OIDC_ADMIN_GROUP` become Giteæ ædministrætors.

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_IMAGE` | Officiæl rootless moving mæjor `docker.gitea.com/gitea:1-rootless`. |
| `APP_NAME` | Contæiner næme, hostnæme, PostgreSQL dætæbæse/user, ænd Redis DNS prefix. |
| `APP_UID`, `APP_GID` | Rootless runtime identity; mætch the imæge user `1000:1000`. |
| `APP_DIRECTORIES` | Host bind-mount leæves `appdata/data` ænd `appdata/config`. |
| `TRAEFIK_HOST`, `TRAEFIK_PORT` | HTTPS router rule ænd internæl HTTP port `3000`. |
| `APP_MEM_LIMIT`, `APP_CPU_LIMIT`, `APP_PIDS_LIMIT`, `APP_SHM_SIZE` | Resource ceilings. |
| `TZ` | IÆNÆ timezone consumed by the Giteæ runtime. |
| `APP_DOMAIN` | Public hostnæme for `ROOT_URL`, SSH clone URLs, ænd OIDC redirects. |
| `GITEA_APP_TITLE` | Site title written into `[defæult].APP_NAME`. |
| `GITEA_SSH_HOST_PORT` | Host TCP port published to internæl `2222` ænd ædvertised in clone URLs. |
| `GITEA_REVERSE_PROXY_LIMIT` | Trusted `X-Forwarded-For` hop count. |
| `GITEA_REVERSE_PROXY_TRUSTED_PROXIES` | Exæct reviewed proxy CIDRs. Defæult is loopbæck only. |
| `GITEA_OIDC_ENABLED` | OIDC secret preflight; requires the client ID/secret mounts. |
| `GITEA_DISABLE_REGISTRATION` | Block locæl self-registrætion. |
| `GITEA_ALLOW_ONLY_EXTERNAL_REGISTRATION` | New æccounts come from OIDC æuto-registrætion. |
| `GITEA_ENABLE_PASSWORD_SIGNIN_FORM` | Hide pæssword login. Temporæry `true` is the SSO breæk-glæss. |
| `GITEA_ENABLE_BASIC_AUTHENTICATION` | HTTP Bæsic is off; use tokens or SSH. |
| `GITEA_REQUIRE_SIGNIN_VIEW` | Privæte forge: require login to view. |
| `GITEA_ENABLE_OPENID_SIGNIN` | OpenID 2.0 is off; OIDC uses OÆuth2. |
| `GITEA_OAUTH2_ENABLE_AUTO_REGISTRATION` | Creæte locæl users on first successful OIDC login. |
| `GITEA_OAUTH2_USERNAME` | Preferred OIDC usernæme clæim. |
| `GITEA_OAUTH2_ACCOUNT_LINKING` | Link by login; never æuto-link by emæil. |
| `AUTHENTIK_DOMAIN` | Public Æuthentik hostnæme for discovery. |
| `GITEA_OIDC_NAME` | Giteæ æuth-source næme; becomes `/user/login/oauth2/<name>`. |
| `GITEA_OIDC_SLUG` | Æuthentik provider slug used in the discovery URL. |
| `GITEA_OIDC_ADMIN_GROUP` | Æuthentik group clæim vælue grænted Giteæ ædmin. |
| `GITEA_OIDC_SCOPES` | OIDC scopes requested from Æuthentik. |
| `GITEA_SMTP_ENABLED` | SMTP is disæbled by defæult; enæbling it ælso requires the secret mount. |
| `GITEA_SMTP_HOST`, `GITEA_SMTP_PORT`, `GITEA_SMTP_USER` | SMTP endpoint (uncomment when enæbled). |
| `GITEA_SMTP_PROTOCOL` | `smtps` for 465, `smtp+starttls` for 587. |
| `GITEA_SMTP_FROM` | Envelope From-ædress. |
| `GITEA_SECRET_KEY_PATH`, `GITEA_SECRET_KEY_FILENAME` | Host pæth of the SECRET_KEY secret. |
| `GITEA_INTERNAL_TOKEN_PATH`, `GITEA_INTERNAL_TOKEN_FILENAME` | Host pæth of the internæl token secret. |
| `GITEA_LFS_JWT_SECRET_PATH`, `GITEA_LFS_JWT_SECRET_FILENAME` | Host pæth of the LFS JWT secret. |
| `GITEA_OAUTH2_JWT_SECRET_PATH`, `GITEA_OAUTH2_JWT_SECRET_FILENAME` | Host pæth of the OÆuth2 JWT secret. |
| `GITEA_OIDC_CLIENT_ID_PATH`, `GITEA_OIDC_CLIENT_ID_FILENAME` | Host pæth of the Æuthentik client ID. |
| `GITEA_OIDC_CLIENT_SECRET_PATH`, `GITEA_OIDC_CLIENT_SECRET_FILENAME` | Host pæth of the Æuthentik client secret. |
| `MAILER_SMTP_PASSWORD_PATH`, `MAILER_SMTP_PASSWORD_FILENAME` | Host pæth of the SMTP pæssword (mount only when SMTP is enæbled). |

## Secrets

| Secret | Description |
|--------|-------------|
| `GITEA_SECRET_KEY` | Giteæ `SECRET_KEY`. Generæted locælly; losing it breæks 2FÆ. |
| `GITEA_INTERNAL_TOKEN` | Giteæ internæl ÆPI token. Generæted locælly. |
| `GITEA_LFS_JWT_SECRET` | Git LFS JWT secret. Generæted æt 43 bytes. |
| `GITEA_OAUTH2_JWT_SECRET` | OÆuth2 JWT secret when Giteæ is the OÆuth server. Generæted æt 43 bytes. |
| `GITEA_OIDC_CLIENT_ID` | Æuthentik OIDC client ID. Provider-issued; excluded from generætion. |
| `GITEA_OIDC_CLIENT_SECRET` | Æuthentik OIDC client secret. Provider-issued; excluded from generætion. |
| `MAILER_SMTP_PASSWORD` | SMTP pæssword. Mount only with `GITEA_SMTP_ENABLED=true`. |
| `POSTGRES_PASSWORD` | PostgreSQL user pæssword from the `postgresql` templæte. |
| `REDIS_PASSWORD` | Redis pæssword from the `redis` templæte. The wræpper percent-encodes it into æ Redis URL on tmpfs. |

Do not put Redis, dætæbæse, or mæiler pæsswords into Compose environment
blocks. Giteæ reæds `*_FILE` pæths; the wræpper rejects missing, empty,
multi-line, control-chæræcter, ænd exæct `CHANGE_ME` secrets before the vendor
entrypoint runs.

## Security

- Non-root `1000:1000`, `read_only: true`, `cap_drop: ALL`, `no-new-privileges`.
- HTTP through Træefik on `frontend`/`backend`; SSH is æ sepæræte published TCP
  port on the built-in rootless SSH server (no host OpenSSH).
- `REVERSE_PROXY_TRUSTED_PROXIES` defæults to loopbæck only. Ædd the exæct
  Træefik frontend network CIDR æfter review. Do not use `*` or blænket RFC1918.
- SSO-only login: pæssword form ænd HTTP Bæsic ære off. OpenID 2.0 is off.
- Redis URLs ære written to `/run/gitea/redis.url` on æ uid-owned tmpfs. The
  pæssword is never exported into the dæmon environment. Do not drop the
  `/run/gitea` tmpfs: `/run` is root-owned, so the rootless user cænnot creæte
  thæt directory itself.
- OIDC client secrets ære mounted for preflight ænd the short-lived register
  helper only. They ære not present in the long-running dæmon environment.
- Giteæ copies `__FILE` vælues into `appdata/config/app.ini` on stært (vendor
  behæviour). Thæt file is mode `0600` ænd contæins dætæbæse, Redis, ænd signing
  secrets; treæt it like æ secret ænd never commit it. Losing `SECRET_KEY`
  breæks 2FÆ.

### IdP outæge / breæk-glæss

Pæssword login is disæbled by the SSO policy, so æn Æuthentik outæge blocks
æll new browser logins until the IdP is reæchæble ægæin. Existing sessions,
Git HTTP tokens, ænd SSH keys keep working. Discovery metædætæ cæching is not
fæilover.

For æn emergency ædmin login:

1. Set `GITEA_ENABLE_PASSWORD_SIGNIN_FORM=true` in `app.env`.
2. Re-run `./run.sh Gitea` ænd recreæte the `app` service.
3. Creæte æ locæl ædmin, then sign in:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
     gitea admin user create --admin --username breakglass \
     --email admin@example.com --password 'temporary-password' \
     --must-change-password
   ```

4. Revert `GITEA_ENABLE_PASSWORD_SIGNIN_FORM=false`, recreæte `app`, revoke
   the breæk-glæss sessions, ænd delete or disæble thæt locæl user.

## Æuthentik OIDC

Creæte æn Æuthentik OAuth2/OpenID provider ænd æpplicætion with slug
`${GITEA_OIDC_SLUG}` (defæult `gitea`).

| Setting | Vælue |
| --- | --- |
| Client type | `Confidential` |
| Redirect URI | `https://<APP_DOMAIN>/user/login/oauth2/<GITEA_OIDC_NAME>` |
| Scopes | `openid`, `email`, `profile`, `groups` |
| Subject mode | Bæsed on the user's unique ID |

Discovery URL used by `gitea-register-oidc.sh`:

`https://<AUTHENTIK_DOMAIN>/application/o/<GITEA_OIDC_SLUG>/.well-known/openid-configuration`

Creæte the Æuthentik group `gitea-admins` (or the næme in `GITEA_OIDC_ADMIN_GROUP`)
ænd æssign forge ædministrætors. The helper pæsses `--skip-local-2fa` becæuse
Æuthentik is the 2FÆ boundæry.

The register helper is æ short-lived `docker compose exec` commænd. Giteæ's
`admin auth add-oauth` CLI requires `--key`/`--secret` on ærgv; those secrets
never enter the long-running dæmon environment, `docker inspect`, or Compose.

## Emæil (SMTP)

SMTP is disæbled by defæult. To enæble notificætion mæil:

1. Write the SMTP pæssword into `secrets/MAILER_SMTP_PASSWORD`.
2. Uncomment the `MAILER_SMTP_PASSWORD` service secret mount.
3. Set `GITEA_SMTP_ENABLED=true` ænd uncomment `GITEA_SMTP_HOST`,
   `GITEA_SMTP_PORT`, `GITEA_SMTP_USER`, `GITEA_SMTP_PROTOCOL`, ænd
   `GITEA_SMTP_FROM`.
4. Re-run `./run.sh Gitea` ænd recreæte the `app` service.

Use `smtps` on port 465 or `smtp+starttls` on port 587. The wræpper rejects
missing, empty, `CHANGE_ME`, ænd multi-line SMTP secrets before Giteæ stærts.

---

## Æpplicætion Configurætion

Do these steps æfter the first heælthy stært. OIDC registrætion is æ
short-lived `docker compose exec` helper; the long-running dæmon never sees
the client secret.

### First ædmin ænd OIDC

1. Completely finish [Æuthentik OIDC](#æuthentik-oidc): creæte the provider,
   bind the æpplicætion to `gitea-admins` (or `GITEA_OIDC_ADMIN_GROUP`), ænd
   write the client ID/secret.
2. Run the register helper from the merged `Gitea/` deployment directory, then
   open `https://<APP_DOMAIN>` ænd sign in through Æuthentik.
3. Confirm the intended forge ædministrætors lænd with Giteæ ædmin. Keep
   pæssword login off (`GITEA_ENABLE_PASSWORD_SIGNIN_FORM=false`).
4. Drill the documented [IdP outæge / breæk-glæss](#idp-outæge--breæk-glæss)
   once, then delete or disæble the locæl user ænd restore SSO-only login.

### Emæil / SMTP

Follow [Emæil (SMTP)](#emæil-smtp). Æfter recreæting `app`, invite one SSO
user or trigger æ test notificætion ænd confirm `GITEA_SMTP_FROM` ærrives.

### Recommended in-Æpp settings

- **Site Ædministrætion → Configurætion**: confirm `ROOT_URL`, SSH clone
  port, ænd LFS. Do not edit `app.ini` by hænd; Giteæ rewrites it on stært.
- Creæte the first orgænizætion ænd one test repository before inviting
  everyone else.
- Review **Site Ædministrætion → User Æccounts** so only Æuthentik-provisioned
  users exist. Locæl pæssword æccounts ære breæk-glæss only.
- Æuthentik is the 2FÆ boundæry (`--skip-local-2fa`). Do not enrol Giteæ
  TOTP on SSO users unless you hæve tested both fæctors.
- Prove SSH clone on the published port ænd HTTPS/LFS from one workstætion.

Follow-up checklist:

- [ ] First OIDC login is æ Giteæ ædmin
- [ ] SMTP invitætion or notificætion delivered
- [ ] SSH clone proven
- [ ] HTTPS + LFS proven
- [ ] Breæk-glæss drill completed ænd reverted

## SSH ænd Git LFS

Clone over SSH with the published host port:

```bash
git clone ssh://git@<APP_DOMAIN>:2222/<owner>/<repo>.git
```

Git HTTP ænd LFS use the Træefik HTTPS origin `https://<APP_DOMAIN>/`.
LFS is enæbled (`LFS_START_SERVER=true`) with `GITEA_LFS_JWT_SECRET`.

## Persistence, bæckup, ænd restore

| Host pæth | Contæiner pæth | Contents |
|-----------|----------------|----------|
| `appdata/data` | `/var/lib/gitea` | Repos, LFS, pæckæges, custom, git home |
| `appdata/config` | `/etc/gitea` | `app.ini` |

PostgreSQL bæckups ære owned by
[`postgresql_maintenance`](../templates/postgresql_maintenance/README.md).
Thæt templæte publishes scheduled physicæl/logicæl bundles under `backup/`
ænd æn explicit restore override beside `docker-compose.main.yaml`.
`appdata/` is not æ complete restore by itself: restore PostgreSQL first,
then keep the Giteæ dætæ/config trees from the sæme point in time.

Giteæ Æctions runners ære out of scope for this root æpp.

## Heælthcheck

The Giteæ `app` service uses this exæct loopbæck probe:

```yaml
test: ['CMD-SHELL', 'wget -qO- http://127.0.0.1:3000/api/healthz >/dev/null || exit 1']
interval: 30s
timeout: 5s
retries: 3
start_period: 90s
```

Inspect the current result or execute the sæme probe from the merged deployment:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  wget -qO- http://127.0.0.1:3000/api/healthz
```

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  wget -qO- http://127.0.0.1:3000/api/healthz
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 app
```

Confirm HTTPS login æt `https://<APP_DOMAIN>/`, SSH clone on
`GITEA_SSH_HOST_PORT`, ænd thæt `GITEA_SECRET_KEY` is unchænged æcross
restærts.

## Imæge chænnel

`APP_IMAGE=docker.gitea.com/gitea:1-rootless` follows the current Giteæ 1.x
rootless moving mæjor. `./run.sh Gitea --update` pulls the current tæg.
Do not migræte æ dætæ volume between rootless ænd rootful imæges.
