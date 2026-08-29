# Giteæ

Self-hosted Git forge with PostgreSQL, Redis, Træefik HTTPS, built-in SSH,
Git LFS, mændætory Æuthentik OIDC, ænd optionæl SMTP. The stæck builds the
locæl `gitea-saervices:latest` imæge on the officiæl stæble-mæjor rootless
bæse `docker.gitea.com/gitea:1-rootless` ænd ædds only æ stætic, bounded
Docker-secret reæder. The officiæl rootless exæmple currently shows
`1.27.2-rootless`; `1-rootless` intentionælly remæins æ moving stæble-mæjor
chænnel. Rootless ænd rootful Giteæ volumes ære incompætible; never switch
between them æfter the first deployment.

The root æpp compose contæins only the primæry `app` service. PostgreSQL,
PostgreSQL mæintenænce, Redis, ænd the finite OIDC reconciler ære merged viæ
`x-required-services`.

## Ærchitecture

```
Træefik (HTTPS :443) ── HTTP :3000 ── gitea
SSH DNS / TCP host port ── SSH :2222 ── gitea (built-in rootless SSH)
                                       ├── gitea-postgresql
                                       ├── gitea-postgresql_maintenance
                                       ├── gitea-redis
                                       └── gitea-oidc (finite; exited 0)
```

| Service | Role |
|---------|------|
| `gitea` | Giteæ web UI, Git HTTP, Git LFS, built-in SSH |
| `gitea-postgresql` | PostgreSQL dætæbæse |
| `gitea-postgresql_maintenance` | Scheduled bæckups ænd explicit restores |
| `gitea-redis` | Cæche, sessions, ænd queue |
| `gitea-oidc` | Finite, idempotent Æuthentik æuth-source reconciler; only this service mounts the OIDC client secrets |

The Linux Docker host must persist `vm.overcommit_memory=1` for reliæble Redis
bæckground persistence; verify it with `sysctl vm.overcommit_memory`. See the
[`redis` templæte host requirements](../templates/redis/README.md#host-requirements).
This is æ host-kernel setting ænd cænnot be fixed through contæiner `sysctls:`.

## Quick Stært

Run every commænd in this Quick Stært from the repository root unless the
step explicitly chænges into `Gitea/`.

### 1. Verify requirements

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
docker network inspect frontend --format '{{.Name}} {{.Driver}} {{.Scope}}'
docker network inspect backend --format '{{.Name}} {{.Driver}} {{.Scope}}'
sysctl vm.overcommit_memory
```

### 2. Configure the environment

Before the first `./run.sh Gitea`, edit `Gitea/.env`.
Æfter the first run, edit `Gitea/app.env`, becæuse `run.sh` renæmes the
initiæl `.env` ænd regenerætes the merged `Gitea/.env`. Never edit the
generæted `.env`.
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
client ID ænd secret. The finite `gitea-oidc` service rejects plæceholders ænd
exits non-zero without chænging the æuth source. Configure this exæct
Æuthentik redirect before merging:

`https://<APP_DOMAIN>/user/oauth2/<GITEA_OIDC_NAME>/callback`

```bash
./run.sh Gitea
printf '%s' 'authentik-client-id' > Gitea/secrets/GITEA_OIDC_CLIENT_ID
printf '%s' 'authentik-client-secret' > Gitea/secrets/GITEA_OIDC_CLIENT_SECRET
```

### 4. Stært ænd reconcile OIDC

```bash
cd Gitea
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml up -d
docker compose --env-file .env -f docker-compose.main.yaml ps app postgresql postgresql_maintenance redis
docker compose --env-file .env -f docker-compose.main.yaml ps -a gitea-oidc
docker compose --env-file .env -f docker-compose.main.yaml logs gitea-oidc
```

Require `gitea-oidc` to be `exited (0)` æfter every deployment ænd provider
secret rotætion. Re-run it without stærting dependencies when æn explicit
reconciliætion is needed:

```bash
docker compose --env-file .env -f docker-compose.main.yaml \
  run --rm --no-deps --pull never gitea-oidc
```

Plæin `docker compose up -d` does not wæit for this consumerless job; the
`ps -a`/logs checks æbove ære therefore mændætory. For æ previously æctive
project, `./run.sh Gitea --update` uses the templæte's fixed
`de.saervices.run.completion-timeout-seconds: "600"` metædætæ: æfter æ
redeployment it wæits up to ten minutes for exæctly one new, current-imæge
`gitea-oidc` project contæiner to reæch stæble `exited (0)` with runtime
restært policy `no`, ænd returns non-zero on every uncertæin or fæiled stæte.
“Current” meæns the cænonicæl imæge ID frozen æfter æll pulls/builds, not æ
læter mutæble tæg resolution. This runner gæte does not prove the externæl
Æuthentik browser flow.

The first Æuthentik login creætes the locæl Giteæ user. Members of
`GITEA_OIDC_ADMIN_GROUP` become Giteæ ædministrætors.

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_IMAGE` | Locæl runtime output tæg `gitea-saervices:latest`; it is built, never pulled. |
| `GITEA_BASE_IMAGE` | Officiæl stæble-mæjor rootless bæse `docker.gitea.com/gitea:1-rootless`; resolve ænd record its exæct imæge ID before production updætes. |
| `GITEA_GO_IMAGE` | `docker.io/library/golang:alpine`; build-only moving Ælpine chænnel for the stætic reæder, never æ runtime environment key. |
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
- The long-running `app` service mounts no OIDC client ID, client secret, or
  OIDC helper script. Only the finite, bæckend-only `gitea-oidc` service
  mounts both files ænd exits æfter one successful ædd-or-updæte operætion.
- The stætic reæder opens the secret directory ænd leæf with
  `O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC`, rejects links ænd speciæl nodes, ænd
  rechecks full file ænd directory identity æround the bounded reæd.
- Giteæ copies `__FILE` vælues into `appdata/config/app.ini` on stært (vendor
  behæviour). Thæt file is mode `0600` ænd contæins dætæbæse, Redis, ænd signing
  secrets; treæt it like æ secret ænd never commit it. Losing `SECRET_KEY`
  breæks 2FÆ.

<div id="idp-outage--break-glass"></div>

### IdP outæge / breæk-glæss

Pæssword login is disæbled by the SSO policy, so æn Æuthentik outæge blocks
æll new browser logins until the IdP is reæchæble ægæin. Existing browser
sessions, personæl æccess tokens, Giteæ-issued OAuth2 æccess/refresh tokens,
user SSH keys, ænd deploy keys ære sepæræte credentiæls ænd cæn remæin usæble
until they expire or ære revoked. This is continuity, not IdP fæilover ænd not
æutomætic offboærding.

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

The register helper is the finite `gitea-oidc` service. Giteæ's
`admin auth add-oauth` ænd `update-oauth` CLI require `--key` ænd `--secret`
ærguments, so the client secret is briefly visible in thæt helper's process
metædætæ. The Docker host, dæemon API, ænd process-observætion plæne ære
therefore trusted. Rotæte the provider secret æfter suspected exposure ænd
re-run the finite service. Neither OIDC secret file nor the helper exists in
the long-running `app` contæiner.

## Credentiæl lifecycle ænd offboærding

The SSO-only settings govern interæctive browser pæssword/passkey login. They
do not revoke ælreædy issued Giteæ credentiæls. Mæintæin æn owner, purpose,
leæst-privilege scope, issue dæte, expiry/review dæte, ænd rotætion procedure
for every personæl æccess token, Giteæ OAuth2 æpplicætion ænd grænt, user SSH
key, deploy key, webhook secret, pæckæge/deploy credentiæl, ænd runner
registrætion credentiæl. Prefer short-lived, repository-scoped credentiæls
ænd never shære æ humæn user's token with æutomætion.

Removing æ user from `gitea-users` in Æuthentik only blocks the next OIDC
login. Offboærding must ælso disæble the locæl Giteæ user, revoke browser
sessions, delete every personæl æccess token ænd Giteæ OAuth2 grænt/application
owned by thæt identity, remove user ænd deploy SSH keys, trænsfer or disæble
owned repositories ænd webhooks, ænd rotæte æny shæred webhook, deploy, or
runner credentiæl the user could reæd. Finælly, prove thæt the old browser
session, API token, Git-over-HTTP token, SSH key, ænd OAuth2 refresh pæth ære
æll denied. Giteæ ædministrætors, repository/organisation owners with
credentiæl-mænægement rights, the Docker/host ædministrætors, ænd direct
dætæbæse or `app.ini` reæders remæin trusted superuser boundæries.

## Emæil (SMTP)

SMTP is disæbled by defæult. To enæble notificætion mæil:

1. Write the SMTP pæssword into `Gitea/secrets/MAILER_SMTP_PASSWORD` from the
   repository root.
2. Uncomment the `MAILER_SMTP_PASSWORD` service secret mount in
   `Gitea/docker-compose.app.yaml`.
3. Set `GITEA_SMTP_ENABLED=true` ænd uncomment `GITEA_SMTP_HOST`,
   `GITEA_SMTP_PORT`, `GITEA_SMTP_USER`, `GITEA_SMTP_PROTOCOL`, ænd
   `GITEA_SMTP_FROM` in `Gitea/app.env`. The lætter is the visible messæge
   `From` æddress; uncomment `GITEA_SMTP_ENVELOPE_FROM` only when the
   provider requires æ different SMTP envelope sender.
4. From the repository root, re-merge ænd recreæte only the `app` service:

   ```bash
   ./run.sh Gitea
   docker compose --env-file Gitea/.env -f Gitea/docker-compose.main.yaml \
     up -d --no-deps --force-recreate app
   ```

Use `smtps` on port 465 or `smtp+starttls` on port 587. The wræpper rejects
missing, empty, `CHANGE_ME`, ænd multi-line SMTP secrets before Giteæ stærts.

This stæck configures visible From ænd optionæl envelope sender, but no
dedicæted Reply-To or support-æddress setting. Use æ monitored From mæilbox
or provider-side æliæs thæt routes replies to the support teæm. Verify by
replying to æ reæl invitætion/notificætion; successful outbound delivery
ælone does not prove support replies ære received.

---

## Æpplicætion Configurætion

Do these steps æfter the first heælthy stært. OIDC registrætion is the finite
`gitea-oidc` service. Require its persisted postcondition (`exited (0)`) ænd
verify `gitea admin auth list`; the long-running dæemon mounts neither OIDC
secret nor the reconciliætion script.

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
: "${GITEA_SSH_DOMAIN:?Set GITEA_SSH_DOMAIN from the deployed .env}"
: "${GITEA_SSH_HOST_PORT:?Set GITEA_SSH_HOST_PORT from the deployed .env}"
: "${GITEA_CLONE_OWNER:?Set GITEA_CLONE_OWNER to the repository owner}"
: "${GITEA_CLONE_REPO:?Set GITEA_CLONE_REPO to the repository næme}"
git clone \
  "ssh://git@${GITEA_SSH_DOMAIN}:${GITEA_SSH_HOST_PORT}/${GITEA_CLONE_OWNER}/${GITEA_CLONE_REPO}.git"
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

The officiæl Giteæ bæckup contræct requires Giteæ to be completely shut down
becæuse repositories, files, ænd the dætæbæse otherwise do not form one
consistent point. Run from the deployed `Gitea/` directory, keep `app` stopped
for the entire cæpture, ænd write æll recovery ærtefæcts to æ privæte directory
outside the `Gitea` tree:

```bash
set -euo pipefail
umask 077
export GITEA_RECOVERY_DIR=/secure/recovery/gitea-20260825T120000Z
case "$GITEA_RECOVERY_DIR" in /*/*) ;; *) exit 1 ;; esac
recovery_parent=$(realpath -e -- "$(dirname -- "$GITEA_RECOVERY_DIR")")
project_root=$(realpath -e -- "$PWD")
gitea_recovery_stage="${GITEA_RECOVERY_DIR}.partial"
test ! -e "$GITEA_RECOVERY_DIR" && test ! -L "$GITEA_RECOVERY_DIR"
test ! -e "$gitea_recovery_stage" && test ! -L "$gitea_recovery_stage"
mkdir -- "$gitea_recovery_stage"
chmod 0700 "$gitea_recovery_stage"
test "$(realpath -e -- "$gitea_recovery_stage")" = \
  "$recovery_parent/$(basename -- "$gitea_recovery_stage")"
test "$(stat -c '%u:%a' -- "$gitea_recovery_stage")" = "$(id -u):700"
python3 - "$project_root" "$recovery_parent" "$GITEA_RECOVERY_DIR" \
  "$gitea_recovery_stage" <<'PY'
import os
import stat
import sys
source = os.path.realpath(sys.argv[1])
parent = os.path.realpath(sys.argv[2])
parent_info = os.lstat(parent)
if (
    not stat.S_ISDIR(parent_info.st_mode)
    or parent_info.st_uid != os.geteuid()
    or stat.S_IMODE(parent_info.st_mode) & 0o022
):
    raise SystemExit('recovery parent must be caller-owned and not group/other writable')
for destination in map(os.path.realpath, sys.argv[3:]):
    if os.path.commonpath((source, destination)) in (source, destination):
        raise SystemExit('recovery directory overlaps the deployment tree')
PY

for compose_input in .env docker-compose.main.yaml; do
  test "$(stat -c '%F:%h' -- "$compose_input")" = 'regular file:1'
  test ! -L "$compose_input"
done
reject_compose_shell_overrides() {
  local line key
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
      key="${BASH_REMATCH[1]}"
      if printenv "$key" >/dev/null 2>&1; then
        printf 'ERROR: exported Compose override is forbidden: %s\n' "$key" >&2
        return 1
      fi
    fi
  done < .env
  for key in COMPOSE_PROJECT_NAME COMPOSE_FILE COMPOSE_PROFILES \
    COMPOSE_ENV_FILES COMPOSE_DISABLE_ENV_FILE; do
    if printenv "$key" >/dev/null 2>&1; then
      printf 'ERROR: exported Compose control is forbidden: %s\n' "$key" >&2
      return 1
    fi
  done
}
reject_compose_shell_overrides
test -d .run.conf && test ! -L .run.conf
recovery_lock_identity=$(stat -Lc '%d:%i' -- .run.conf)
exec {recovery_lock_fd}<.run.conf
flock -n -x "$recovery_lock_fd"
test "$(stat -Lc '%d:%i' -- "/proc/$$/fd/$recovery_lock_fd")" = \
  "$recovery_lock_identity"
test "$(stat -Lc '%d:%i' -- .run.conf)" = "$recovery_lock_identity"

docker_cli_env=(env -i PATH="$PATH" HOME="${HOME:?HOME is required}")
for key in DOCKER_CONFIG DOCKER_CONTEXT DOCKER_HOST DOCKER_CERT_PATH \
  DOCKER_TLS_VERIFY; do
  if [[ -v $key ]]; then
    value="${!key}"
    test "${#value}" -le 4096
    case "$value" in *$'\n'*|*$'\r'*|*$'\t'*) exit 1 ;; esac
    docker_cli_env+=("$key=$value")
  fi
done
recovery_docker=("${docker_cli_env[@]}" docker)
recovery_compose=("${docker_cli_env[@]}" docker compose \
  --env-file .env -f docker-compose.main.yaml)
read_checked_lines() {
  local target="$1" output
  shift
  if ! output=$("$@"); then
    return 1
  fi
  [[ -n "$output" ]] || return 1
  mapfile -t "$target" <<< "$output"
}
"${recovery_compose[@]}" config --quiet
"${recovery_compose[@]}" config --format json > \
  "$gitea_recovery_stage/compose-effective.json.partial"
ln -- "$gitea_recovery_stage/compose-effective.json.partial" \
  "$gitea_recovery_stage/compose-effective.json"
rm -- "$gitea_recovery_stage/compose-effective.json.partial"
rendered_project_name=$(python3 - "$gitea_recovery_stage/compose-effective.json" <<'PY'
import json
import re
import sys
with open(sys.argv[1], encoding='utf-8') as stream:
    project = json.load(stream).get('name')
if not isinstance(project, str) or not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,62}', project):
    raise SystemExit('rendered Compose project name is invalid')
print(project)
PY
)
read_checked_lines recovery_services \
  "${recovery_compose[@]}" config --services
test "${#recovery_services[@]}" -gt 0
declare -A recovery_containers=()
: > "$gitea_recovery_stage/runtime-bindings.tsv.partial"
for service in "${recovery_services[@]}"; do
  [[ "$service" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]]
  read_checked_lines containers \
    "${recovery_compose[@]}" ps -aq "$service"
  test "${#containers[@]}" -eq 1 && test -n "${containers[0]}"
  container_id="${containers[0]}"
  recovery_containers[$service]="$container_id"
  container_image_ref=$("${recovery_docker[@]}" inspect \
    --format '{{.Config.Image}}' "$container_id")
  image_id=$("${recovery_docker[@]}" inspect --format '{{.Image}}' "$container_id")
  case "$container_image_ref" in ''|*$'\n'*|*$'\r'*|*$'\t'*) exit 1 ;; esac
  [[ "$image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
  test "$("${recovery_docker[@]}" inspect --format \
    '{{index .Config.Labels "com.docker.compose.project"}}' "$container_id")" = \
    "$rendered_project_name"
  test "$("${recovery_docker[@]}" inspect --format \
    '{{index .Config.Labels "com.docker.compose.service"}}' "$container_id")" = \
    "$service"
  container_config_hash=$("${recovery_docker[@]}" inspect --format \
    '{{index .Config.Labels "com.docker.compose.config-hash"}}' "$container_id")
  [[ "$container_config_hash" =~ ^[0-9a-f]{64}$ ]]
  config_hash_override="$gitea_recovery_stage/.config-hash-image-override.json"
  python3 - "$service" "$container_image_ref" "$config_hash_override" <<'PY'
import json
import os
import sys
service, image, output = sys.argv[1:]
if not image or len(image) > 4096 or any(ord(char) < 32 or ord(char) == 127 for char in image):
    raise SystemExit('container image reference is unsafe')
descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
    json.dump({'services': {service: {'image': image}}}, stream)
    stream.write('\n')
PY
  expected_hash_line=$("${recovery_compose[@]}" -f "$config_hash_override" \
    config --hash "$service")
  rm -- "$config_hash_override"
  case "$expected_hash_line" in "$service "*) ;; *) exit 1 ;; esac
  expected_config_hash="${expected_hash_line#"$service "}"
  [[ "$expected_config_hash" =~ ^[0-9a-f]{64}$ ]]
  test "$expected_config_hash" = "$container_config_hash"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$rendered_project_name" \
    "$service" "$container_id" "$container_config_hash" \
    "$container_image_ref" "$image_id" >> \
    "$gitea_recovery_stage/runtime-bindings.tsv.partial"
done
read_checked_lines project_containers "${recovery_docker[@]}" ps -aq \
  --filter "label=com.docker.compose.project=$rendered_project_name"
test "${#project_containers[@]}" -eq "${#recovery_services[@]}"
declare -A project_services_seen=()
for container_id in "${project_containers[@]}"; do
  project_service=$("${recovery_docker[@]}" inspect --format \
    '{{index .Config.Labels "com.docker.compose.service"}}' "$container_id")
  [[ "$project_service" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$ ]]
  test -n "${recovery_containers[$project_service]+present}"
  test -z "${project_services_seen[$project_service]+duplicate}"
  test "$container_id" = "${recovery_containers[$project_service]}"
  project_services_seen[$project_service]=true
done
test "${#project_services_seen[@]}" -eq "${#recovery_services[@]}"
read_checked_lines external_networks python3 - \
  "$gitea_recovery_stage/compose-effective.json" <<'PY'
import json
import re
import sys
with open(sys.argv[1], encoding='utf-8') as stream:
    networks = json.load(stream).get('networks', {})
selected = []
for key, value in networks.items():
    if isinstance(value, dict) and value.get('external') is True:
        name = value.get('name')
        if not isinstance(name, str) or not re.fullmatch(
            r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}', name
        ):
            raise SystemExit('external Compose network name is invalid')
        selected.append(name)
if not selected or len(selected) != len(set(selected)):
    raise SystemExit('external Compose network closure is empty or ambiguous')
print('\n'.join(sorted(selected)))
PY
"${recovery_docker[@]}" network inspect "${external_networks[@]}" > \
  "$gitea_recovery_stage/.external-networks.raw.json"
python3 - "$gitea_recovery_stage/compose-effective.json" \
  "$gitea_recovery_stage/.external-networks.raw.json" \
  "$gitea_recovery_stage/external-networks.json.partial" <<'PY'
import ipaddress
import json
import os
import sys
compose_path, inspect_path, output_path = sys.argv[1:]
with open(compose_path, encoding='utf-8') as stream:
    compose = json.load(stream)
with open(inspect_path, encoding='utf-8') as stream:
    inspected = json.load(stream)
expected = {
    key: value['name']
    for key, value in compose.get('networks', {}).items()
    if isinstance(value, dict) and value.get('external') is True
}
by_name = {item.get('Name'): item for item in inspected if isinstance(item, dict)}
if len(by_name) != len(inspected) or set(by_name) != set(expected.values()):
    raise SystemExit('external Docker network closure differs from clean Compose')
normalized = {}
for key, name in sorted(expected.items()):
    item = by_name[name]
    ipam = item.get('IPAM')
    if (
        not isinstance(ipam, dict)
        or not isinstance(ipam.get('Config'), list)
        or not ipam['Config']
    ):
        raise SystemExit(
            f'external network {name} lacks explicit IPAM CIDR evidence'
        )
    for config in ipam['Config']:
        if not isinstance(config, dict) or not isinstance(
            config.get('Subnet'), str
        ):
            raise SystemExit(f'external network {name} has invalid IPAM config')
        subnet = ipaddress.ip_network(config['Subnet'], strict=False)
        if (
            config.get('Gateway') is not None
            and ipaddress.ip_address(config['Gateway']) not in subnet
        ):
            raise SystemExit(
                f'external network {name} gateway is outside its subnet'
            )
    normalized[key] = {
        'name': name,
        'driver': item.get('Driver'),
        'scope': item.get('Scope'),
        'internal': item.get('Internal'),
        'attachable': item.get('Attachable'),
        'ingress': item.get('Ingress'),
        'enable_ipv4': item.get('EnableIPv4'),
        'enable_ipv6': item.get('EnableIPv6'),
        'ipam': {
            'driver': ipam.get('Driver'),
            'options': ipam.get('Options') or {},
            'config': ipam['Config'],
        },
        'options': item.get('Options') or {},
    }
descriptor = os.open(
    output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600
)
with os.fdopen(descriptor, 'w', encoding='utf-8') as stream:
    json.dump(normalized, stream, sort_keys=True, separators=(',', ':'))
    stream.write('\n')
PY
rm -- "$gitea_recovery_stage/.external-networks.raw.json"
ln -- "$gitea_recovery_stage/external-networks.json.partial" \
  "$gitea_recovery_stage/external-networks.json"
rm -- "$gitea_recovery_stage/external-networks.json.partial"
for network_name in "${external_networks[@]}"; do
  attached=false
  for container_id in "${project_containers[@]}"; do
    if "${recovery_docker[@]}" inspect \
      --format '{{json .NetworkSettings.Networks}}' "$container_id" |
      python3 -c \
        'import json,sys; raise SystemExit(0 if sys.argv[1] in json.load(sys.stdin) else 1)' \
        "$network_name"; then
      attached=true
      break
    fi
  done
  test "$attached" = true
done
ln -- "$gitea_recovery_stage/runtime-bindings.tsv.partial" \
  "$gitea_recovery_stage/runtime-bindings.tsv"
rm -- "$gitea_recovery_stage/runtime-bindings.tsv.partial"
for service in "${recovery_services[@]}"; do
  read_checked_lines containers \
    "${recovery_compose[@]}" ps -aq "$service"
  test "${#containers[@]}" -eq 1
  test "${containers[0]}" = "${recovery_containers[$service]}"
done

"${recovery_compose[@]}" stop app

bundle_before=$(mktemp)
find backup -maxdepth 1 -type f -links 1 \
  \( -name 'dump_*.dump.zst' -o -name 'dump_*.dump.zst.sha256' \
     -o -name 'bundle_dump_*.sha256' \) -printf '%f\n' | LC_ALL=C sort \
  > "$bundle_before"
"${recovery_compose[@]}" exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh dump
python3 - "$bundle_before" backup "$gitea_recovery_stage" <<'PY'
import os
import re
import stat
import sys
from pathlib import Path
before = set(Path(sys.argv[1]).read_text(encoding='utf-8').splitlines())
backup = Path(sys.argv[2])
pattern = re.compile(r'dump_[0-9]{8}_[0-9]{1,9}\.dump\.zst')
current = set()
for entry in os.scandir(backup):
    info = entry.stat(follow_symlinks=False)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        continue
    if pattern.fullmatch(entry.name) or re.fullmatch(
        r'(?:dump_[0-9]{8}_[0-9]{1,9}\.dump\.zst\.sha256|bundle_dump_[0-9]{8}_[0-9]{1,9}\.sha256)',
        entry.name,
    ):
        current.add(entry.name)
created = current - before
archives = sorted(name for name in created if pattern.fullmatch(name))
if len(archives) != 1:
    raise SystemExit(f'expected one new logical dump, got {sorted(created)!r}')
archive = archives[0]
backup_id = archive.removeprefix('dump_').removesuffix('.dump.zst')
expected = {archive, f'{archive}.sha256', f'bundle_dump_{backup_id}.sha256'}
if created != expected:
    raise SystemExit(f'new dump bundle is not exact: {sorted(created)!r}')
destination = Path(sys.argv[3])
(destination / 'postgres-backup-id.txt').write_text(backup_id + '\n', encoding='utf-8')
(destination / 'postgres-bundle-files.txt').write_text(
    ''.join(f'{name}\n' for name in sorted(expected)), encoding='utf-8'
)
PY
rm -f -- "$bundle_before"
"${recovery_compose[@]}" stop postgresql_maintenance

redis_before=$("${recovery_compose[@]}" exec -T redis \
  sh -ec 'REDISCLI_AUTH="$(cat /run/secrets/REDIS_PASSWORD)" redis-cli --no-auth-warning LASTSAVE')
"${recovery_compose[@]}" exec -T redis \
  sh -ec 'REDISCLI_AUTH="$(cat /run/secrets/REDIS_PASSWORD)" redis-cli --no-auth-warning SAVE | grep -qx OK'
redis_after=$("${recovery_compose[@]}" exec -T redis \
  sh -ec 'REDISCLI_AUTH="$(cat /run/secrets/REDIS_PASSWORD)" redis-cli --no-auth-warning LASTSAVE')
test "$redis_after" -ge "$redis_before"

redis_container=$("${recovery_compose[@]}" ps -q redis)
test -n "$redis_container"
redis_volume=$("${recovery_docker[@]}" inspect --format \
  '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' \
  "$redis_container")
redis_image=$("${recovery_docker[@]}" inspect --format '{{.Image}}' "$redis_container")
case "$redis_volume" in ''|*[!A-Za-z0-9_.-]*) exit 1 ;; esac
case "$redis_image" in sha256:[0-9a-f][0-9a-f]*) ;; *) exit 1 ;; esac
printf '%s\n' "$redis_image" > "$gitea_recovery_stage/redis-image-id.txt"
"${recovery_compose[@]}" stop redis postgresql
"${recovery_docker[@]}" run --rm --pull never --entrypoint tar \
  --mount "type=volume,src=$redis_volume,dst=/source,readonly" \
  --mount "type=bind,src=$gitea_recovery_stage,dst=/recovery" \
  "$redis_image" -C /source -cf /recovery/redis-volume.tar .
python3 scripts/strict-recovery.py validate-volume \
  --archive "$gitea_recovery_stage/redis-volume.tar"
```

Ærchive the complete stopped deployment without following links. The ærchive
destinætion must be new ænd outside the source root. Then bind every rendered
service to its exæct existing contæiner, imæge æliæs, ænd running content
ID. Tæg resolution must mætch the running ID both before ænd æfter
`docker image save`:

```bash
python3 scripts/strict-recovery.py create \
  --source-root "$PWD" --archive "$gitea_recovery_stage/Gitea.tar"
python3 scripts/strict-recovery.py validate \
  --archive "$gitea_recovery_stage/Gitea.tar"
install -m 0500 scripts/strict-recovery.py \
  "$gitea_recovery_stage/strict-recovery.py"

declare -a recovery_images=()
: > "$gitea_recovery_stage/image-map.tsv.partial"
daemon_platform=$("${recovery_docker[@]}" version \
  --format '{{.Server.Os}}/{{.Server.Arch}}')
[[ "$daemon_platform" =~ ^[a-z0-9][a-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]
printf '%s\n' "$daemon_platform" > "$gitea_recovery_stage/daemon-platform.txt"
for service in "${recovery_services[@]}"; do
  case "$service" in ''|*[!A-Za-z0-9_.-]*) exit 1 ;; esac
  read_checked_lines containers \
    "${recovery_compose[@]}" ps -aq "$service"
  test "${#containers[@]}" -eq 1 && test -n "${containers[0]}"
  test "${containers[0]}" = "${recovery_containers[$service]}"
  image_ref=$("${recovery_docker[@]}" inspect --format \
    '{{.Config.Image}}' "${containers[0]}")
  image_id=$("${recovery_docker[@]}" inspect --format '{{.Image}}' "${containers[0]}")
  test "$("${recovery_docker[@]}" image inspect --format '{{.Id}}' \
    "$image_ref")" = "$image_id"
  image_platform=$("${recovery_docker[@]}" image inspect --format \
    '{{.Os}}/{{.Architecture}}/{{.Variant}}' "$image_id")
  IFS=/ read -r image_os image_arch image_variant <<< "$image_platform"
  [[ "$image_os" =~ ^[a-z0-9][a-z0-9_.-]*$ ]]
  [[ "$image_arch" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]
  [[ -z "$image_variant" || "$image_variant" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$service" "$image_ref" "$image_id" \
    "$image_os" "$image_arch" "$image_variant" >> \
    "$gitea_recovery_stage/image-map.tsv.partial"
  recovery_images+=("$image_ref")
done
if ! recovery_images_output=$(printf '%s\n' "${recovery_images[@]}" | \
  LC_ALL=C sort -u); then
  exit 1
fi
test -n "$recovery_images_output"
mapfile -t recovery_images <<< "$recovery_images_output"
unset recovery_images_output
"${recovery_docker[@]}" image save \
  --output "$gitea_recovery_stage/images.tar.partial" \
  "${recovery_images[@]}"
while IFS=$'\t' read -r service image_ref image_id image_os image_arch image_variant; do
  test "$("${recovery_docker[@]}" image inspect --format '{{.Id}}' \
    "$image_ref")" = "$image_id"
  test "$("${recovery_docker[@]}" inspect --format '{{.Image}}' \
    "${recovery_containers[$service]}")" = "$image_id"
  test "$("${recovery_docker[@]}" image inspect --format \
    '{{.Os}}/{{.Architecture}}/{{.Variant}}' "$image_id")" = \
    "$image_os/$image_arch/$image_variant"
done < "$gitea_recovery_stage/image-map.tsv.partial"
ln -- "$gitea_recovery_stage/image-map.tsv.partial" \
  "$gitea_recovery_stage/image-map.tsv"
rm -- "$gitea_recovery_stage/image-map.tsv.partial"
ln -- "$gitea_recovery_stage/images.tar.partial" \
  "$gitea_recovery_stage/images.tar"
rm -- "$gitea_recovery_stage/images.tar.partial"
(
  cd "$gitea_recovery_stage"
  sha256sum Gitea.tar redis-volume.tar redis-image-id.txt images.tar \
    image-map.tsv postgres-backup-id.txt postgres-bundle-files.txt \
    strict-recovery.py compose-effective.json runtime-bindings.tsv \
    daemon-platform.txt external-networks.json > SHA256SUMS.partial
)
ln -- "$gitea_recovery_stage/SHA256SUMS.partial" \
  "$gitea_recovery_stage/SHA256SUMS"
rm -- "$gitea_recovery_stage/SHA256SUMS.partial"
python3 scripts/strict-recovery.py seal-bundle \
  --stage-root "$gitea_recovery_stage" --final-root "$GITEA_RECOVERY_DIR"
python3 "$GITEA_RECOVERY_DIR/strict-recovery.py" verify-bundle \
  --bundle-root "$GITEA_RECOVERY_DIR"
```

The complete set is the no-clobber published directory with
`RECOVERY_COMPLETE`, `Gitea.tar`, the exæct PostgreSQL bundle ID ænd file
closure, `redis-volume.tar`, `redis-image-id.txt`, `images.tar`,
`image-map.tsv`, `daemon-platform.txt`, `compose-effective.json`,
`runtime-bindings.tsv`, `external-networks.json`, the externæl
`strict-recovery.py` bootstræp, ænd
`SHA256SUMS`. Æ `.partial` directory is never æ recovery point; preserve it
only for forensics, then discærd it änd stært æ new cæpture. Encrypt ænd copy
the published bundle off-host becæuse it
contæins `app.ini`, repositories, provider, dætæbæse, Redis, ænd signing
secrets. Resume only æfter æll checksums ænd files ære duræble:

```bash
"${recovery_compose[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never postgresql redis app
"${recovery_compose[@]}" up -d --no-build --pull never \
  postgresql_maintenance
"${recovery_compose[@]}" exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh full
"${recovery_compose[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never postgresql_maintenance
"${recovery_compose[@]}" up \
  --no-deps --no-build --pull never --abort-on-container-exit \
  --exit-code-from gitea-oidc gitea-oidc
```

### Restore ænd recovery drill

Restore only on æ fresh, isolæted recovery VM/LXC ænd Docker Engine with no
production workloæds. `docker image load` chænges the dæemon-globæl imæge
store ænd æ fæiled loæd cæn leæve pærtiæl stæte; discærd the entire isolæted
recovery host ænd stært ægæin æfter æny loæd, volume, restore, or runtime
fæilure. Never loæd the ærchive into the production Docker dæemon ænd never
use æ moving pull, build, or source merge during recovery.

Verify the encrypted trænsport ænd checksums before æny extræction. Before
`docker image load`, prove the disposæble engine hæs no contæiners, imæges, or
volumes. Loæd the sæved ærchive, then require every service æliæs to resolve
to its recorded content ID. RepoDigests ære registry evidence only ænd ære
not æ post-`save`/`load` recovery contræct:

```bash
set -euo pipefail
cd /secure/recovery/gitea-20260825T120000Z
export GITEA_RECOVERY_DIR="$PWD"
python3 "$PWD/strict-recovery.py" verify-bundle --bundle-root "$PWD"
restore_docker_env=(env -i PATH="$PATH" HOME="${HOME:?HOME is required}")
for key in DOCKER_CONFIG DOCKER_CONTEXT DOCKER_HOST DOCKER_CERT_PATH \
  DOCKER_TLS_VERIFY; do
  if [[ -v $key ]]; then
    value="${!key}"
    test "${#value}" -le 4096
    case "$value" in *$'\n'*|*$'\r'*|*$'\t'*) exit 1 ;; esac
    restore_docker_env+=("$key=$value")
  fi
done
restore_docker=("${restore_docker_env[@]}" docker)
read_checked_lines() {
  local target="$1" output
  shift
  if ! output=$("$@"); then
    return 1
  fi
  [[ -n "$output" ]] || return 1
  mapfile -t "$target" <<< "$output"
}
if ! restore_containers=$("${restore_docker[@]}" ps -aq); then
  exit 1
fi
if ! restore_images=$("${restore_docker[@]}" image ls -aq); then
  exit 1
fi
if ! restore_volumes=$("${restore_docker[@]}" volume ls -q); then
  exit 1
fi
test -z "$restore_containers"
test -z "$restore_images"
test -z "$restore_volumes"
unset restore_containers restore_images restore_volumes
read_checked_lines recovery_network_names python3 - external-networks.json <<'PY'
import json
import sys
with open(sys.argv[1], encoding='utf-8') as stream:
    requirements = json.load(stream)
print('\n'.join(sorted(item['name'] for item in requirements.values())))
PY
test "${#recovery_network_names[@]}" -gt 0
for network_name in "${recovery_network_names[@]}"; do
  if "${restore_docker[@]}" network inspect "$network_name" >/dev/null 2>&1; then
    printf 'ERROR: refusing to adopt existing external network %s\n' \
      "$network_name" >&2
    exit 1
  fi
done
if ! restore_daemon_platform=$("${restore_docker[@]}" version \
  --format '{{.Server.Os}}/{{.Server.Arch}}'); then
  exit 1
fi
if ! saved_daemon_platform=$(cat -- daemon-platform.txt); then
  exit 1
fi
[[ "$restore_daemon_platform" =~ ^[a-z0-9][a-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]
[[ "$saved_daemon_platform" =~ ^[a-z0-9][a-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]
test "$restore_daemon_platform" = "$saved_daemon_platform"
unset restore_daemon_platform saved_daemon_platform
"${restore_docker[@]}" image load --input images.tar
while IFS=$'\t' read -r service alias expected_id image_os image_arch image_variant; do
  case "$service:$alias:$expected_id:$image_os:$image_arch:$image_variant" in
    *$'\n'*|*$'\r'*) exit 1 ;;
  esac
  test "$("${restore_docker[@]}" image inspect --format '{{.Id}}' \
    "$alias")" = "$expected_id"
  test "$("${restore_docker[@]}" image inspect --format \
    '{{.Os}}/{{.Architecture}}/{{.Variant}}' "$alias")" = \
    "$image_os/$image_arch/$image_variant"
done < image-map.tsv
```

The `frontend`/`backend` næmes in the cleæn render ære externæl trust
boundæries, not Compose-owned resources. Before æny volume or contæiner is
creæted, provision eæch network mænuælly on the isolæted engine from the exæct
driver, scope, options, ænd IPAM CIDRs in `external-networks.json`; rændom IPAM
or ædoption of æ pre-existing network is forbidden becæuse trusted-proxy CIDRs
depend on this topology. Then prove the new, still-empty networks mætch the
ærchived requirements:

```bash
read_checked_lines recovery_network_names python3 - \
  "$GITEA_RECOVERY_DIR/external-networks.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding='utf-8') as stream:
    requirements = json.load(stream)
print('\n'.join(sorted(item['name'] for item in requirements.values())))
PY
network_inspect=$(mktemp)
trap 'rm -f -- "$network_inspect"' EXIT
"${restore_docker[@]}" network inspect "${recovery_network_names[@]}" > \
  "$network_inspect"
python3 - "$GITEA_RECOVERY_DIR/external-networks.json" "$network_inspect" <<'PY'
import json
import sys
expected_path, actual_path = sys.argv[1:]
with open(expected_path, encoding='utf-8') as stream:
    expected = json.load(stream)
with open(actual_path, encoding='utf-8') as stream:
    inspected = json.load(stream)
if any(item.get('Containers') for item in inspected):
    raise SystemExit('recovery external networks are not empty')
by_name = {item.get('Name'): item for item in inspected}
if len(by_name) != len(inspected):
    raise SystemExit('recovery external network names are ambiguous')
actual = {}
for key, requirement in expected.items():
    item = by_name.get(requirement['name'])
    if item is None:
        raise SystemExit(f'missing recovery external network {requirement["name"]}')
    ipam = item.get('IPAM') or {}
    actual[key] = {
        'name': item.get('Name'),
        'driver': item.get('Driver'),
        'scope': item.get('Scope'),
        'internal': item.get('Internal'),
        'attachable': item.get('Attachable'),
        'ingress': item.get('Ingress'),
        'enable_ipv4': item.get('EnableIPv4'),
        'enable_ipv6': item.get('EnableIPv6'),
        'ipam': {
            'driver': ipam.get('Driver'),
            'options': ipam.get('Options') or {},
            'config': ipam.get('Config') or [],
        },
        'options': item.get('Options') or {},
    }
if actual != expected:
    raise SystemExit('recovery external network/IPAM contract drifted')
PY
rm -- "$network_inspect"
trap - EXIT
```

Vælidæte ænd stæge the deployment ærchive. On the fresh host creæte one empty
live sibling, then use the Linux `renameat2(RENAME_EXCHANGE)` cutover. The
duræble identity journæl mækes æn interrupted exchænge explicitly
reconcilæble; æfter æny interruption run `recover --action rollback` before
continuing:

```bash
install -d -m 0700 /srv/docker
python3 "$PWD/strict-recovery.py" validate --archive "$PWD/Gitea.tar"
python3 "$PWD/strict-recovery.py" stage \
  --archive "$PWD/Gitea.tar" --stage-root /srv/docker/Gitea.stage
install -d -m 0700 /srv/docker/Gitea
python3 "$PWD/strict-recovery.py" swap \
  --stage-root /srv/docker/Gitea.stage \
  --live-root /srv/docker/Gitea \
  --rollback-root /srv/docker/Gitea.rollback \
  --journal /srv/docker/Gitea.exchange.json
# Interrupted exchange only:
python3 "$PWD/strict-recovery.py" recover \
  --journal /srv/docker/Gitea.exchange.json --action rollback
```

Continue from `/srv/docker/Gitea`; keep `GITEA_RECOVERY_DIR` pointed æt the
verified externæl bundle.

```bash
cd /srv/docker/Gitea
```

Creæte æ recovery override thæt sets every service to the exæct sæved æliæs,
resets æll rendered build blocks with `build: !reset null`, sets
`pull_policy: never`, ænd gives the top-level `database` ænd `redis` volumes
fresh unique `name:` vælues. Do not reuse æny existing dætæbæse or Redis
volume. Vælidæte `redis-volume.tar`, populæte the new Redis volume with the
exæct content ID in `redis-image-id.txt` using `docker run --pull never`, ænd
restore only the ID in `postgres-backup-id.txt`. Copy exæctly the three
filenæmes in `postgres-bundle-files.txt` from `backup/` into æ new empty
`restore/` directory. Run the
mæintenænce dry-run first ænd retæin the dump, sidecær, ænd bundle mænifest.
Every Compose invocætion must include the recovery override; stærtup uses
`--no-build --pull never` through the cleæn `restore_compose` ærræy below, so
æmbient `APP_NAME`, imæge, volume, UID/GID, ænd secret-pæth overrides cænnot
chænge the recovery render. The repository does not yet generæte or
æutomæticælly vælidæte this override, volume populætion, ænd full
dætæbæse-restore sequence. Until the exæct procedure hæs succeeded on æ
fresh isolæted host, this section is æ mænuæl drill contræct, not proof of æ
completed production restore.

Æfter the dætæbæse restore, stært `postgresql`, `redis`, `app`,
`postgresql_maintenance`, ænd `gitea-oidc` from the sæved imæges. Require the
four long-running heælthchecks ænd `gitea-oidc` exit `0`, then run:

```bash
restore_compose=("${restore_docker_env[@]}" docker compose --env-file .env \
  -f docker-compose.main.yaml -f recovery.override.yaml)
"${restore_compose[@]}" config --quiet
"${restore_compose[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never postgresql redis app
"${restore_compose[@]}" up -d --no-build --pull never \
  postgresql_maintenance
"${restore_compose[@]}" exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh full
"${restore_compose[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never postgresql_maintenance
"${restore_compose[@]}" up --no-deps --no-build --pull never \
  --abort-on-container-exit --exit-code-from gitea-oidc gitea-oidc
"${restore_compose[@]}" exec -T app gitea admin regenerate hooks
"${restore_compose[@]}" exec -T app gitea doctor check
```

The upstreæm restore is mænuæl; rootless stæte belongs under `/etc/gitea` ænd
`/var/lib/gitea`, ænd hooks must be regeneræted æfter restore. Prove OIDC
login, denied-user behæviour, one API-token request, HTTPS clone/push, SSH
clone/push, LFS uploæd/download, repository ænd ættæchment checksums, Redis
`LASTSAVE`, ænd æ full restært. The originæl production host remæins the
rollbæck. Promote the isolæted recovery host only æfter the complete drill.

Omitting `redis-volume.tar` is æn explicit lossy recovery, never æ complete
restore: æll Redis-bæcked sessions ære invælidæted, cæches must rebuild, ænd
queued work cæn be lost or require reconciliætion. Use thæt pæth only æfter æ
documented loss decision ænd verify every æffected job. Æ vælid Redis ærchive
is required for the normæl lossless recovery contræct.

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

The merged stæck hæs four long-running heælth gætes plus one finite completion
gæte:

| Service | Probe | Timing |
| --- | --- | --- |
| `app` | Loopbæck `GET http://127.0.0.1:3000/api/healthz` with `wget` | `30s` intervæl, `5s` timeout, `3` retries, `90s` stært period |
| `postgresql` | `pg_isready -d <APP_NAME> -U <APP_NAME>` | `30s` intervæl, `5s` timeout, `3` retries, `10s` stært period |
| `redis` | Æuthenticæted `redis-cli ping`, requiring exæct `PONG` | `30s` intervæl, `5s` timeout, `3` retries, `10s` stært period |
| `postgresql_maintenance` | Running Supercronic plus æ regulær numeric `.postgresql-maintenance-last-success` not older thæn `POSTGRES_BACKUP_MAX_AGE_SECONDS` | `30s` intervæl, `5s` timeout, `3` retries, `70m` stært period |
| `gitea-oidc` | Finite ædd-or-updæte reconciliætion | Periodic heælth disæbled; require `exited (0)` ænd runtime restært policy `no` æfter every deployment or provider rotætion; æn æctive-project `run.sh --update` redeployment wæits on the fixed `600`-second completion læbel using frozen imæge-ID evidence |

Inspect æll results ænd execute the Giteæ probe from the `Gitea/` merged
deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app postgresql postgresql_maintenance redis
docker compose --env-file .env -f docker-compose.main.yaml ps -a gitea-oidc
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  wget -qO- http://127.0.0.1:3000/api/healthz
```

`postgresql_maintenance` cæn remæin `starting` for up to 70 minutes while it
wæits for the first scheduled successful bæckup. Do not weæken the mærker or
credentiæl probes merely to produce green rows. Æ heælthy `app` does not hide
æ fæiled finite OIDC reconciliætion.

## Verificætion

Run the following commænds from the `Gitea/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps app postgresql postgresql_maintenance redis
docker compose --env-file .env -f docker-compose.main.yaml ps -a gitea-oidc
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  wget -qO- http://127.0.0.1:3000/api/healthz
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 app
```

From the repository root, the mænuæl reæl-imæge regression builds the current
Giteæ imæge with no cæche, runs the reæl helper preflight, verifies thæt its
`--network none` non-preflight ættempt fæils æt externæl discovery without
persisting æ source or logging the secret, renders the completion læbel, ænd
one-shot lifecycle, proves æ reæl stopped exit-zero `restart=no` Docker job
ænd immutæble-ID Compose retæg override, ænd executes the deterministic
privæte-snæpshot/imæge-ID/monotonic-clock runner-gæte regressions:

```bash
bash .cursor/scripts/test-gitea-runtime.sh
```

The fixture intentionælly uses `--network none`. Current Giteæ contæcts the
discovery URL during `admin auth add-oauth`, so the fixture cænnot honestly
prove æ successful ædd/updæte without æ trusted HTTPS IdP. Successful reæl
Æuthentik discovery/registrætion, login, group-clæim ædmin mæpping,
denied-user cæse, TLS, ænd browser redirect remæin DEV/stæging evidence.

Confirm public DNS ænd the served TLS certificæte mætch `APP_DOMAIN`, the
OIDC redirect returns only to thæt cænonicæl host, SSH clone uses
`GITEA_SSH_DOMAIN:GITEA_SSH_HOST_PORT`, ænd `GITEA_SECRET_KEY` is unchænged
æcross restærts. For cross-host Træefik, prove the HTTP origin is
unreæchæble from æny source except the Træefik host.

## Imæge chænnel

`APP_IMAGE=gitea-saervices:latest` is æ locæl output tæg. Its
`GITEA_BASE_IMAGE=docker.gitea.com/gitea:1-rootless` bæse follows the officiæl
stæble Giteæ 1.x rootless mæjor tæg; the officiæl rootless exæmple currently
uses `1.27.2-rootless`. Do not migræte æ dætæ volume between rootless ænd
rootful imæges. Review ænd pin the resolved bæse ænd builder digests for eæch
production releæse even though the editæble defæults remæin moving chænnels.

Before every updæte, reæd the Giteæ releæse notes for the exæct resolved
version, record the current imæge digest, ænd complete ænd verify the
writer-stopped full recovery bundle described æbove. Then run from the
repository root:

```bash
./run.sh Gitea --update
```

`--update` first pins privæte byte/render-identicæl Compose/env snæpshots ænd
one explicit project identity, then pulls/builds. Before service mutætion it
freezes every service's cænonicæl imæge ID; `up -d --no-build --pull never`
receives only æ verified privæte imæge-ID override, so æ retæg in the
check-to-`up` window cænnot stært the wrong imæge. Æ second project-æctivity
meæsurement rejects æn externæl stopped/running trænsition during pull/build
before runner-owned service mutætion. It reconciles only æ
previously æctive project. If it redeploys thæt project, it binds
pre-redeployment OIDC contæiner identities ænd then wæits on the fixed
`600`-second completion læbel; missing, multiple, reused, replæced,
stæle-imæge, retægged-imæge, wrong runtime HostConfig restært policy,
uninspectæble, non-zero, non-monotonic-clock, or timed-out `gitea-oidc`
evidence mækes the commænd fæil. If no redeployment is needed, the normæl
reconciliætion check still requires repeæted stæble frozen-imæge `exited (0)`
evidence ænd runtime restært policy `no`. Æfter æ successful completion gæte,
the æccepted contæiner identity remæins bindende through finæl reconciliætion
ænd every finæl Docker query uses the remæining totæl monotonic deædline. Æ
fully stopped project remæins
stopped, so `--update` does not execute or prove its OIDC job.

From `Gitea/`, inspect the migrætion logs ænd require the four long-running
heælthchecks, finite `gitea-oidc` exit `0`, live OIDC login, HTTPS/SSH clone
ænd push, LFS, ænd SMTP when enæbled. Keep the prior recovery bundle until the
observætion window closes.

Do not stært æn older Giteæ imæge ægæinst æ dætæbæse or `appdata`
tree thæt æ newer version migræted. Rollbæck meæns stopping æll writers ænd
restoring the complete pre-updæte PostgreSQL, `appdata`, configurætion, secrets,
ænd prior imæge/repository revision from the sæme recovery point. Prove thæt
procedure in stæging before relying on it.
