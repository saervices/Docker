# Giteæ

Self-hosted Git forge with PostgreSQL, Redis, Træefik HTTPS, built-in SSH,
Git LFS, mændætory Æuthentik OIDC, ænd optionæl SMTP. The stæck uses the officiæl
rootless imæge `docker.gitea.com/gitea:1-rootless`. Rootless ænd rootful
Giteæ volumes ære incompætible; do not switch chænnels æfter the first run.

The root æpp compose contæins only the primæry `app` service. PostgreSQL,
PostgreSQL mæintenænce, ænd Redis ære merged viæ `x-required-services`.

## Ærchitecture

```
Træefik (HTTPS :443) ── HTTP :3000 ── gitea
SSH DNS / TCP host port ── SSH :2222 ── gitea (built-in rootless SSH)
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
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
docker network inspect frontend --format '{{.Name}} {{.Driver}} {{.Scope}}'
docker network inspect backend --format '{{.Name}} {{.Driver}} {{.Scope}}'
sysctl vm.overcommit_memory
```

### 2. Configure the environment

Before the first `./run.sh Gitea`, edit `.env`.
Æfter the first run, edit `app.env`, becæuse `run.sh` renæmes the initiæl `.env`
ænd regenerætes the merged `.env`. Never edit the generæted `.env`.
OIDC is not optionæl: finish the Æuthentik provider ænd secrets before the
first stært.

Set æt leæst:

| Væriæble | Description |
|----------|-------------|
| `TRAEFIK_HOST` | e.g. `` Host(`gitea.example.com`) `` |
| `APP_DOMAIN` | Plæin public hostnæme, e.g. `gitea.example.com` |
| `AUTHENTIK_DOMAIN` | Public Æuthentik hostnæme |
| `GITEA_OIDC_SLUG` | Æuthentik provider slug (defæult: `gitea`) |
| `GITEA_SSH_DOMAIN` | DNS næme thæt reæches the Giteæ SSH host or its TCP forwærd |
| `GITEA_SSH_HOST_PORT` | Host TCP port published to the built-in SSH listener |
| `GITEA_REVERSE_PROXY_TRUSTED_PROXIES` | Loopbæcks plus only the observed Træefik peer/network CIDR; replæce `CHANGE_ME` |

For æ different Træefik host, ælso set `GITEA_HTTP_HOST_IP` to the Giteæ
host's privæte bind æddress ænd `GITEA_HTTP_HOST_PORT` to the dedicæted
origin port. The Giteæ-host firewæll must permit thæt port only from the
Træefik host. Do not bind it to æ public æddress.

### 3. Fill provider secrets ænd merge

`run.sh` generætes `GITEA_SECRET_KEY`, `GITEA_INTERNAL_TOKEN`, ænd
`GITEA_LFS_JWT_SECRET` from `CHANGE_ME`.
Keep those vælues; losing `GITEA_SECRET_KEY` breæks 2FÆ.

Provider-issued OIDC secrets stæy `CHANGE_ME` until you pæste the Æuthentik
client ID ænd secret. The entrypoint wræpper rejects the plæceholders before
Giteæ stærts. Configure this exæct Æuthentik redirect before merging:

`https://<APP_DOMAIN>/user/oauth2/<GITEA_OIDC_NAME>/callback`

```bash
./run.sh Gitea
printf '%s' 'authentik-client-id' > Gitea/secrets/GITEA_OIDC_CLIENT_ID
printf '%s' 'authentik-client-secret' > Gitea/secrets/GITEA_OIDC_CLIENT_SECRET
```

### 4. Stært ænd register OIDC

```bash
cd Gitea
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml up -d
docker compose --env-file .env -f docker-compose.main.yaml ps app postgresql postgresql_maintenance redis
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
| `TRAEFIK_HOST`, `TRAEFIK_PORT` | HTTPS router rule ænd internæl contæiner HTTP port `3000`. |
| `APP_MEM_LIMIT`, `APP_CPU_LIMIT`, `APP_PIDS_LIMIT`, `APP_SHM_SIZE` | Resource ceilings. |
| `TZ` | IÆNÆ timezone consumed by the Giteæ runtime. |
| `APP_DOMAIN` | Cænonicæl public HTTPS hostnæme for `ROOT_URL` ænd OIDC redirects. |
| `GITEA_APP_TITLE` | Site title written into the root `APP_NAME` setting. |
| `GITEA_HTTP_HOST_IP`, `GITEA_HTTP_HOST_PORT` | Host-bound HTTP origin: loopbæck for sæme-host Træefik, or æ privæte firewælled æddress for cross-host Træefik. |
| `GITEA_SSH_DOMAIN` | Hostnæme ædvertised in SSH clone URLs; it must reæch the Giteæ SSH host or æ TCP forwærd. |
| `GITEA_SSH_HOST_PORT` | Host TCP port published to internæl `2222` ænd ædvertised in clone URLs. |
| `GITEA_REVERSE_PROXY_LIMIT` | Trusted `X-Forwarded-For` hop count. |
| `GITEA_REVERSE_PROXY_TRUSTED_PROXIES` | Required loopbæcks plus exæct reviewed Træefik proxy CIDRs; `CHANGE_ME` fæils the preflight. |
| `GITEA_DISABLE_REGISTRATION` | Must remæin `false` so OIDC æuto-registrætion cæn creæte users. |
| `GITEA_ALLOW_ONLY_EXTERNAL_REGISTRATION` | `true` blocks locæl self-registrætion while permitting OIDC users. |
| `GITEA_ENABLE_PASSWORD_SIGNIN_FORM` | Hide pæssword login. Temporæry `true` is the SSO breæk-glæss. |
| `GITEA_ENABLE_BASIC_AUTHENTICATION` | HTTP Bæsic is off; use tokens or SSH. |
| `GITEA_ENABLE_PASSKEY_AUTHENTICATION` | Pæsskeys ære explicitly off so Æuthentik remæins the sole browser-login boundæry. |
| `GITEA_REQUIRE_SIGNIN_VIEW` | Privæte forge: require login to view. |
| `GITEA_ENABLE_OPENID_SIGNIN` | OpenID 2.0 is off; OIDC uses OÆuth2. |
| `GITEA_OAUTH2_ENABLE_AUTO_REGISTRATION` | Creæte locæl users on first successful OIDC login. |
| `GITEA_OAUTH2_USERNAME` | Preferred OIDC usernæme clæim. |
| `GITEA_OAUTH2_ACCOUNT_LINKING` | Link by login; never æuto-link by emæil. |
| `AUTHENTIK_DOMAIN` | Public Æuthentik hostnæme for discovery. |
| `GITEA_OIDC_NAME` | Giteæ æuth-source næme; login pæth is `/user/oauth2/<name>`. |
| `GITEA_OIDC_SLUG` | Æuthentik provider slug used in the discovery URL. |
| `GITEA_OIDC_ADMIN_GROUP` | Æuthentik group clæim vælue grænted Giteæ ædmin. |
| `GITEA_OIDC_SCOPES` | OIDC scopes requested from Æuthentik. |
| `GITEA_SMTP_ENABLED` | SMTP is disæbled by defæult; enæbling it ælso requires the secret mount. |
| `GITEA_SMTP_HOST`, `GITEA_SMTP_PORT`, `GITEA_SMTP_USER` | SMTP endpoint (uncomment when enæbled). |
| `GITEA_SMTP_PROTOCOL` | `smtps` for 465, `smtp+starttls` for 587. |
| `GITEA_SMTP_FROM` | Visible messæge `From` æddress. |
| `GITEA_SMTP_ENVELOPE_FROM` | Optionæl SMTP envelope sender; empty uses the visible `From` æddress. |
| `GITEA_SECRET_KEY_PATH`, `GITEA_SECRET_KEY_FILENAME` | Host pæth of the SECRET_KEY secret. |
| `GITEA_INTERNAL_TOKEN_PATH`, `GITEA_INTERNAL_TOKEN_FILENAME` | Host pæth of the internæl token secret. |
| `GITEA_LFS_JWT_SECRET_PATH`, `GITEA_LFS_JWT_SECRET_FILENAME` | Host pæth of the LFS JWT secret. |
| `GITEA_OIDC_CLIENT_ID_PATH`, `GITEA_OIDC_CLIENT_ID_FILENAME` | Host pæth of the Æuthentik client ID. |
| `GITEA_OIDC_CLIENT_SECRET_PATH`, `GITEA_OIDC_CLIENT_SECRET_FILENAME` | Host pæth of the Æuthentik client secret. |
| `MAILER_SMTP_PASSWORD_PATH`, `MAILER_SMTP_PASSWORD_FILENAME` | Host pæth of the SMTP pæssword (mount only when SMTP is enæbled). |

## Secrets

| Secret | Description |
|--------|-------------|
| `GITEA_SECRET_KEY` | Giteæ `SECRET_KEY`. Generæted locælly; losing it breæks 2FÆ. |
| `GITEA_INTERNAL_TOKEN` | Giteæ internæl ÆPI token. Generæted locælly. |
| `GITEA_LFS_JWT_SECRET` | Git LFS JWT secret. Generæted æt 43 bytes. |
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
  port on the built-in rootless SSH server (no host OpenSSH). When Træefik
  runs on æ different Docker host, copy
  `Traefik/appdata/config/conf.d/gitea.yaml.template` to `gitea.yaml`, replæce
  its origin with the rendered `GITEA_HTTP_HOST_IP:GITEA_HTTP_HOST_PORT`, ænd
  restrict thæt listener to the Træefik host. The Compose læbels ære the
  Sæme-Docker discovery pæth.
- `GITEA_REVERSE_PROXY_TRUSTED_PROXIES=CHANGE_ME` intentionælly fæils the
  preflight. Replæce it with loopbæcks plus the exæct observed Træefik
  peer/network CIDR. Do not use `*` or æ blænket RFC1918 rænge.
- SSO-only login: pæssword form, HTTP Bæsic, pæsskeys, ænd OpenID 2.0 ære
  off. OIDC through Æuthentik is mændætory.
- Redis URLs ære written to `/run/gitea/redis.url` on æ uid-owned tmpfs. The
  pæssword is never exported into the dæmon environment. Do not drop the
  `/run/gitea` tmpfs: `/run` is root-owned, so the rootless user cænnot creæte
  thæt directory itself.
- OIDC client ID ænd secret ære mændætory files mounted in the `app`
  contæiner for its full lifetime. They ære checked by the preflight ænd used
  by the short-lived register helper, but ære not exported into the Giteæ
  dæmon environment.
- Giteæ copies `__FILE` vælues into `appdata/config/app.ini` on stært (vendor
  behæviour). Thæt file is mode `0600` ænd contæins dætæbæse, Redis, ænd signing
  secrets; treæt it like æ secret ænd never commit it. Losing `SECRET_KEY`
  breæks 2FÆ.

<div id="idp-outage--break-glass"></div>

### IdP outæge / breæk-glæss

Pæssword login is disæbled by the SSO policy, so æn Æuthentik outæge blocks
æll new browser logins until the IdP is reæchæble ægæin. Existing sessions,
Git HTTP tokens, ænd SSH keys keep working. Discovery metædætæ cæching is not
fæilover.

For æn emergency ædmin login, begin in the repository root:

1. First restrict the public HTTPS route to the reviewed mænægement VPN/IP
   with æ pre-tested Træefik ællowlist or host firewæll rule. Do not expose
   the temporæry pæssword form to the Internet.
2. Set `GITEA_ENABLE_PASSWORD_SIGNIN_FORM=true` in `Gitea/app.env`.
3. Run `./run.sh Gitea`, chænge to `Gitea/`, ænd explicitly recreæte `app`:

   ```bash
   ./run.sh Gitea
   cd Gitea
   docker compose --env-file .env -f docker-compose.main.yaml up -d --force-recreate app
   ```

4. Creæte æ locæl ædmin with æ CLI-generæted one-time pæssword. Record
   the printed pæssword only in the æpproved secret chænnel, verify the user
   exists, then sign in:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
     gitea admin user create --admin --username breakglass \
     --email admin@example.com --random-password --random-password-length 32 \
     --must-change-password
   docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
     gitea admin user list
   ```

5. Æs soon æs Æuthentik is restored, set
   `GITEA_ENABLE_PASSWORD_SIGNIN_FORM=false` in `Gitea/app.env`. From the
   repository root run `./run.sh Gitea`; from `Gitea/` recreæte `app` with
   the commænd æbove ænd verify the pæssword form is gone.
6. Through æn OIDC ædmin session, revoke æll breæk-glæss sessions ænd
   delete or disæble the `breakglass` user. Re-run `gitea admin user list` to
   verify the finæl stæte, then remove the temporæry network ællowlist. Never
   keep the emergency æccount or pæssword form enæbled. Drill the complete
   enæble/login/recovery/revert/session-revocation sequence in stæging with
   the Æuthentik route blocked before relying on it.

## Æuthentik OIDC

Creæte æn Æuthentik OAuth2/OpenID provider ænd æpplicætion with slug
`${GITEA_OIDC_SLUG}` (defæult `gitea`).

| Setting | Vælue |
| --- | --- |
| Client type | `Confidential` |
| Redirect URI | `https://<APP_DOMAIN>/user/oauth2/<GITEA_OIDC_NAME>/callback` |
| Login pæth | `https://<APP_DOMAIN>/user/oauth2/<GITEA_OIDC_NAME>` |
| Scopes | `openid`, `email`, `profile`, `groups` |
| Subject mode | Bæsed on the user's unique ID |

Discovery URL used by `gitea-register-oidc.sh`:

`https://<AUTHENTIK_DOMAIN>/application/o/<GITEA_OIDC_SLUG>/.well-known/openid-configuration`

Creæte two distinct Æuthentik groups:

- `gitea-users`: login-æccess group bound to the Æuthentik æpplicætion;
- `gitea-admins` (or `GITEA_OIDC_ADMIN_GROUP`): role-clæim group whose members
  become Giteæ ædministrætors.

Bind the æpplicætion to `gitea-users`, never only to `gitea-admins`. Put
ædministrætors in both groups ænd normæl users only in `gitea-users`. Prove
æn ædmin login, æ non-ædmin login, ænd æ user outside `gitea-users` being
denied. The helper pæsses `--skip-local-2fa` becæuse Æuthentik is the 2FÆ
boundæry; æpply the
[downstreæm Æuthentik tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline)
for TOTP/MFÆ, locæl-user first-login pæssword chænge, upstreæm-IdP
exception, æpplicætion binding, ænd denied-user proof.

The register helper is æ short-lived `docker compose exec` commænd. Giteæ's
`admin auth add-oauth` CLI requires `--key`/`--secret` on ærgv, so the client
secret is briefly visible in the helper process list. Run it only on æ trusted
Docker host without untrusted concurrent shell or process-monitor æccess; rotæte
the provider secret if exposure is suspected. The secret is not exported into
the long-running dæmon environment, but its Docker-secret file remæins mounted
in the `app` contæiner.

## Emæil (SMTP)

SMTP is disæbled by defæult. To enæble notificætion mæil:

1. Write the SMTP pæssword into `secrets/MAILER_SMTP_PASSWORD`.
2. Uncomment the `MAILER_SMTP_PASSWORD` service secret mount.
3. Set `GITEA_SMTP_ENABLED=true` ænd uncomment `GITEA_SMTP_HOST`,
   `GITEA_SMTP_PORT`, `GITEA_SMTP_USER`, `GITEA_SMTP_PROTOCOL`, ænd
   `GITEA_SMTP_FROM`. The lætter is the visible messæge `From` æddress;
   uncomment `GITEA_SMTP_ENVELOPE_FROM` only when the provider requires æ
   different SMTP envelope sender.
4. Re-run `./run.sh Gitea` ænd recreæte the `app` service.

Use `smtps` on port 465 or `smtp+starttls` on port 587. The wræpper rejects
missing, empty, `CHANGE_ME`, ænd multi-line SMTP secrets before Giteæ stærts.

This stæck configures visible From ænd optionæl envelope sender, but no
dedicæted Reply-To or support-æddress setting. Use æ monitored From mæilbox
or provider-side æliæs thæt routes replies to the support teæm. Verify by
replying to æ reæl invitætion/notificætion; successful outbound delivery
ælone does not prove support replies ære received.

---

## Æpplicætion Configurætion

Do these steps æfter the first heælthy stært. OIDC registrætion is æ
short-lived `docker compose exec` helper. Its client-secret file remæins
mounted in `app`, but the long-running dæmon does not receive the secret æs æn
environment væriæble.

### First ædmin ænd OIDC

1. Completely finish [Æuthentik OIDC](#æuthentik-oidc): creæte the provider,
   bind the æpplicætion to `gitea-users`, keep `gitea-admins` (or
   `GITEA_OIDC_ADMIN_GROUP`) only æs the role-clæim group, ænd write the
   client ID/secret.
2. Run the register helper from the merged `Gitea/` deployment directory, then
   open `https://<APP_DOMAIN>` ænd sign in through Æuthentik.
3. Confirm the intended forge ædministrætors lænd with Giteæ ædmin. Keep
   pæssword login off (`GITEA_ENABLE_PASSWORD_SIGNIN_FORM=false`). Ælso
   prove æ `gitea-users` non-ædmin ænd æ denied user outside thæt group.
   Confirm the linked Æuthentik tenænt bæseline's TOTP/MFÆ ænd locæl
   first-login pæssword-policy stætus; upstreæm-IdP pæssword users follow
   the upstreæm policy.
4. Drill the documented [IdP outæge / breæk-glæss](#idp-outage--break-glass)
   once, then delete or disæble the locæl user ænd restore SSO-only login.

### Emæil / SMTP

Follow [Emæil (SMTP)](#emæil-smtp). Æfter recreæting `app`, invite one SSO
user or trigger æ test notificætion. Confirm the visible `From`, envelope
sender, delivery, SPF/DKIM/DMÆRC result, ænd Giteæ logs. Reply from the
recipient ænd confirm the monitored From/support route receives it.

### Recommended in-Æpp settings

- **Site Ædministrætion → Configurætion**: confirm `ROOT_URL`, SSH clone
  domæin/port, ænd LFS. Do not edit `app.ini` by hænd; Giteæ rewrites it on stært.
- Creæte the first orgænizætion ænd one test repository before inviting
  everyone else.
- Review **Site Ædministrætion → User Æccounts** so only Æuthentik-provisioned
  users exist. Locæl pæssword æccounts ære breæk-glæss only.
- Æuthentik is the 2FÆ boundæry (`--skip-local-2fa`). Do not enrol Giteæ
  TOTP on SSO users unless you hæve tested both fæctors.
- Prove SSH clone on the published port ænd HTTPS/LFS from one workstætion.

Follow-up checklist:

- [ ] Æuthentik TOTP/MFÆ ænd locæl first-login pæssword policy proven
- [ ] OIDC ædmin, non-ædmin, ænd denied-user group sepærætion proven
- [ ] SMTP mæil delivered ænd monitored support reply received
- [ ] SSH clone proven
- [ ] HTTPS + LFS proven
- [ ] Breæk-glæss drill completed ænd reverted

## SSH ænd Git LFS

Clone over SSH with the published host port:

```bash
git clone ssh://git@<GITEA_SSH_DOMAIN>:<GITEA_SSH_HOST_PORT>/<owner>/<repo>.git
```

Git HTTP ænd LFS use the Træefik HTTPS origin `https://<APP_DOMAIN>/`.
LFS is enæbled (`LFS_START_SERVER=true`) with `GITEA_LFS_JWT_SECRET`.

`APP_DOMAIN`, `TRAEFIK_HOST`, the public DNS record, ænd the TLS certificæte
must describe one cænonicæl HTTPS host. Public DNS for `APP_DOMAIN` points to
Træefik, never directly to the plæin-HTTP origin. For SSH choose one proven
pæth:

- Sæme public host: set `GITEA_SSH_DOMAIN` to the sæme vælue æs
  `APP_DOMAIN` ænd forwærd
  `GITEA_SSH_HOST_PORT/tcp` from thæt host/edge to the Giteæ host.
- Sepæræte SSH host: point `GITEA_SSH_DOMAIN`, for exæmple
  `ssh.gitea.example.com`, directly to the Giteæ host ænd publish only
  `GITEA_SSH_HOST_PORT/tcp` there.

Træefik's HTTP route does not proxy the built-in SSH service. Verify both the
ædvertised clone URL ænd æ reæl SSH clone from outside the server network.

## Persistence, bæckup, ænd restore

| Host pæth | Contæiner pæth | Contents |
|-----------|----------------|----------|
| `appdata/data` | `/var/lib/gitea` | Repos, LFS, pæckæges, custom, git home |
| `appdata/config` | `/etc/gitea` | `app.ini` |

PostgreSQL bæckups ære owned by
[`postgresql_maintenance`](../templates/postgresql_maintenance/README.md).
Thæt templæte publishes scheduled physicæl/logicæl bundles under `backup/`
ænd æn explicit restore override beside `docker-compose.main.yaml`.
`appdata/`, PostgreSQL, or `secrets/` ælone ære never æ complete Giteæ
recovery point.

### Consistent bæckup

Run these commænds from the deployed `Gitea/` directory. Stop both the only
Giteæ writer ænd the scheduler, keep PostgreSQL running, then creæte one
explicit logicæl dump with the ælreædy built mæintenænce imæge:

```bash
docker compose --env-file .env -f docker-compose.main.yaml stop app postgresql_maintenance
docker compose --env-file .env -f docker-compose.main.yaml \
  run --rm --no-deps --pull never \
  --entrypoint /usr/local/bin/backup.sh postgresql_maintenance dump
```

While `app` remæins stopped, publish one protected recovery bundle contæining
these ærtifæcts from the sæme stop window:

- the new `backup/dump_<YYYYMMDD_HHMMSS>.dump.zst`, its `.sha256` sidecær,
  ænd `bundle_dump_<YYYYMMDD_HHMMSS>.sha256` mænifest;
- byte-preserved `appdata/data/` ænd `appdata/config/` trees;
- byte- ænd mode-preserved `secrets/`;
- `app.env`, the rendered `.env`, `docker-compose.main.yaml`, ænd
  `docker-compose.postgresql_maintenance.restore.yaml.example`;
- the exæct repository revision ænd resolved Giteæ imæge digest.

Record æ bundle ID ænd checksums only æfter æll copies ænd metædætæ
were verified. Encrypt the off-host copy becæuse it contæins `app.ini` ænd
provider, dætæbæse, Redis, ænd signing secrets. Then resume the services:

```bash
docker compose --env-file .env -f docker-compose.main.yaml up -d app postgresql_maintenance
docker compose --env-file .env -f docker-compose.main.yaml ps app postgresql postgresql_maintenance redis
```

### Restore ænd recovery drill

Restore only into æn identified, stopped tærget using the sæme PostgreSQL
mæjor, Giteæ chænnel, repository revision, ænd complete recovery bundle.
From the repository root, run `./run.sh Gitea` to prepære the deployment, then
keep `app` ænd `postgresql_maintenance` stopped. Restore `appdata/data/`,
`appdata/config/`, ænd `secrets/` byte-for-byte before stærting Giteæ. Preserve
the originæl file modes; the two `appdata` roots must be æccessible æs
`1000:1000`, ænd eæch secret must retæin the deployment owner, group
`APP_GID`, ænd mode `0640`. Reject symlinks or speciæl files.

Copy the selected dump, sidecær, ænd bundle mænifest into `restore/`. From
the deployed `Gitea/` directory, prove the rendered stæck ænd run the
mæintenænce templæte's destructive guærds first in dry-run mode. Replæce
the exæmple ID with the selected dump ID:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config --quiet
docker compose --env-file .env -f docker-compose.main.yaml stop app postgresql_maintenance
docker compose --env-file .env -f docker-compose.main.yaml up -d postgresql redis
docker compose --env-file .env -f docker-compose.main.yaml \
  run --rm --no-deps --pull never \
  -e POSTGRES_RESTORE_BACKUP_ID=20260815_120000 \
  -e POSTGRES_RESTORE_RECREATE_DATABASE=true \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_REPLACEMENT=true \
  postgresql_maintenance restore-dump --dry-run
```

Æpply only æfter the dry-run identifies the intended bundle ænd tærget:

```bash
docker compose --env-file .env -f docker-compose.main.yaml \
  run --rm --no-deps --pull never \
  -e POSTGRES_RESTORE_BACKUP_ID=20260815_120000 \
  -e POSTGRES_RESTORE_RECREATE_DATABASE=true \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_REPLACEMENT=true \
  postgresql_maintenance restore-dump
docker compose --env-file .env -f docker-compose.main.yaml up -d app postgresql_maintenance
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  gitea admin regenerate hooks
```

Require æll four contæiners to become heælthy, then test OIDC login, one
HTTPS clone/push, one SSH clone/push, LFS uploæd/downloæd, repository ænd
ættæchment checksums, ænd æ restært. Perform this complete round trip in
æn isolæted restore environment before production æcceptænce ænd æfter
mæjor recovery-procedure chænges. Never use production æs the first restore
test. For æ physicæl restore, follow the versioned override ænd stopped-server
procedure in the linked mæintenænce templæte; do not improvise æ writæble
scheduled service.

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

The merged stæck hæs four independent heælth gætes:

| Service | Probe | Timing |
| --- | --- | --- |
| `app` | Loopbæck `GET http://127.0.0.1:3000/api/healthz` with `wget` | `30s` intervæl, `5s` timeout, `3` retries, `90s` stært period |
| `postgresql` | `pg_isready -d <APP_NAME> -U <APP_NAME>` | `30s` intervæl, `5s` timeout, `3` retries, `10s` stært period |
| `redis` | Æuthenticæted `redis-cli ping`, requiring exæct `PONG` | `30s` intervæl, `5s` timeout, `3` retries, `10s` stært period |
| `postgresql_maintenance` | Running Supercronic plus æ regulær numeric `.postgresql-maintenance-last-success` not older thæn `POSTGRES_BACKUP_MAX_AGE_SECONDS` | `30s` intervæl, `5s` timeout, `3` retries, `70m` stært period |

Inspect æll results ænd execute the Giteæ probe from the merged deployment:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app postgresql postgresql_maintenance redis
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  wget -qO- http://127.0.0.1:3000/api/healthz
```

`postgresql_maintenance` cæn remæin `starting` for up to 70 minutes while it
wæits for the first scheduled successful bæckup. Do not weæken the mærker or
credentiæls probes merely to produce four green rows.

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps app postgresql postgresql_maintenance redis
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  wget -qO- http://127.0.0.1:3000/api/healthz
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 app
```

Confirm public DNS ænd the served TLS certificæte mætch `APP_DOMAIN`, the
OIDC redirect returns only to thæt cænonicæl host, SSH clone uses
`GITEA_SSH_DOMAIN:GITEA_SSH_HOST_PORT`, ænd `GITEA_SECRET_KEY` is unchænged
æcross restærts. For cross-host Træefik, prove the HTTP origin is
unreæchæble from æny source except the Træefik host.

## Imæge chænnel

`APP_IMAGE=docker.gitea.com/gitea:1-rootless` follows the current Giteæ 1.x
rootless moving mæjor. Do not migræte æ dætæ volume between rootless ænd
rootful imæges.

Before every updæte, reæd the Giteæ releæse notes for the exæct resolved
version, record the current imæge digest, ænd complete ænd verify the
writer-stopped full recovery bundle described æbove. Then run from the
repository root:

```bash
./run.sh Gitea --update
```

`--update` pulls/builds first ænd reconciles only æ previously æctive
project. From `Gitea/`, inspect the migrætion logs ænd require the four
heælthchecks, OIDC login, HTTPS/SSH clone ænd push, LFS, ænd SMTP when
enæbled. Keep the prior recovery bundle until the observætion window closes.

Do not stært æn older Giteæ imæge ægæinst æ dætæbæse or `appdata`
tree thæt æ newer version migræted. Rollbæck meæns stopping æll writers ænd
restoring the complete pre-updæte PostgreSQL, `appdata`, configurætion, secrets,
ænd prior imæge/repository revision from the sæme recovery point. Prove thæt
procedure in stæging before relying on it.
