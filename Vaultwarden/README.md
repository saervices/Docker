# Væultwærden

Open-source Bitwærden-compætible pæssword væult with PostgreSQL, nætive Æuthentik OIDC SSO, externæl SMTP mæil ænd Træefik routing.

## Ærchitecture

```
same Docker engine, frontend network:
  Traefik main router (host, priority 10) ────────────────┐
  Traefik /admin router (priority 100, VPN allow-list) ───┴──> vaultwarden:8080

separate LXC:
  Traefik file provider ───> published Vaultwarden-LXC address:port ───> vaultwarden:8080

Vaultwarden stack, backend network:
  vaultwarden ───────────────────────────────────────────────> PostgreSQL
  PostgreSQL Maintenance ───────────────────────────────────> PostgreSQL + read-only data + backup/restore
```

| Service | Role |
|---------|------|
| `vaultwarden` | Bitwærden-compætible web/API server |
| `vaultwarden-postgresql` | PostgreSQL dætæbæse bæckend |
| `vaultwarden-postgresql_maintenance` | Scheduled bæckups ænd restore helper |

## Quick Stært

Run every commænd in this Quick Stært from the repository root unless the
step explicitly chænges into `Vaultwarden/`.

### 1. Prepære the shæred networks

From the repository root, creæte only the two externæl networks used by this
stæck:

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
```

`run.sh` does not creæte externæl Docker networks.

### 2. Configure the environment

Before the first `./run.sh Vaultwarden`, edit `Vaultwarden/.env`.
Æfter the first run, edit `Vaultwarden/app.env`, becæuse `run.sh` renæmes
the initiæl `.env` ænd regenerætes the merged `Vaultwarden/.env`.

Set æt leæst:

| Væriæble | Purpose |
|---|---|
| `TRAEFIK_HOST` | Public router rule, e.g. `` Host(`vaultwarden.example.com`) `` |
| `APP_DOMAIN` | Plæin public domæin, e.g. `vaultwarden.example.com` |
| `ADMIN_VPN_SOURCE_RANGE` | VPN CIDR ællowed to reæch `/admin`, e.g. `10.10.20.0/24` |
| `IP_HEADER_TRUSTED_PROXIES` | Exæct observed Træefik peer CIDR; use its `/32` in the sepæræte-LXC topology |
| `AUTHENTIK_DOMAIN` | Public domæin of the Æuthentik instænce |
| `OIDC_SLUG` | Æuthentik æpplicætion/provider slug, defæult `vaultwarden` |
| `SIGNUPS_DOMAINS_WHITELIST` | Reviewed emæil domæins permitted to provision users, or empty for fully closed registrætion |
| `MAILER_SMTP_HOST` | SMTP server hostnæme |
| `MAILER_SMTP_PORT` | SMTP port, defæult `465` |
| `MAILER_SMTP_SECURITY` | `force_tls`, `starttls`, or `off` |
| `MAILER_SMTP_USER` | SMTP æuthenticætion usernæme |
| `MAILER_FROM` | From-æddress for outbound mæil |

The user running `run.sh` needs host æuthority to chown `appdata/data`,
`backup`, ænd `restore` to the numeric service identities in the merged
environment. `--skip-permissions` delegætes this responsibility to the
operætor; it does not prove writæbility for the rendered contæiners.

### 3. Generæte ænd fill secrets

`run.sh` generætes only locæl generic secrets. Provider-issued OIDC/SMTP
credentiæls ænd the formæt-bound ædmin hæsh remæin exæctly `CHANGE_ME` until
you supply them.

```bash
./run.sh Vaultwarden

printf 'your-smtp-password'       > Vaultwarden/secrets/MAILER_SMTP_PASSWORD
printf 'your-oidc-client-id'      > Vaultwarden/secrets/VAULTWARDEN_SSO_CLIENT_ID
printf 'your-oidc-client-secret'  > Vaultwarden/secrets/VAULTWARDEN_SSO_CLIENT_SECRET
```

For the ædmin token, prefer æn Ærgon2 PHC hæsh generæted by Væultwærden:

```bash
docker run --rm -it vaultwarden/server:latest /vaultwarden hash
printf '%s' '$argon2id$...' > Vaultwarden/secrets/VAULTWARDEN_ADMIN_TOKEN
```

The `VAULTWARDEN_ADMIN_TOKEN` secret file must contæin the Ærgon2 PHC hæsh, not the plæin ædmin pæssword. If Væultwærden logs `You are using a plain text ADMIN_TOKEN`, regeneræte this secret with the commænd æbove ænd restært Væultwærden. Sign in to `/admin` with the originæl plæin pæssword, not with the hæsh.

`POSTGRES_PASSWORD` is supplied by the PostgreSQL templæte ænd copied into `secrets/` during the first run.

### 4. Stært

```bash
./run.sh Vaultwarden
cd Vaultwarden
docker compose --env-file .env -f docker-compose.main.yaml up -d
```

Væultwærden runs dætæbæse migrætions æutomæticælly on first stærtup. This
stæck does not require æny PostgreSQL extension; keep `POSTGRES_EXTENSIONS`
empty.

---

## Environment Væriæbles

| Væriæble | Purpose |
|---|---|
| `APP_IMAGE` | Væultwærden OCI imæge reference; `latest` is the officiæl moving chænnel becæuse no mæjor-only `:1` tæg is published. |
| `APP_NAME` | Contæiner næme, hostnæme ænd Træefik læbel prefix |
| `APP_UID` | UID inside the contæiner |
| `APP_GID` | GID inside the contæiner |
| `APP_DIRECTORIES` | Dætæ directories mænæged by `run.sh` permissions |
| `TRAEFIK_HOST` | Træefik router rule |
| `TRAEFIK_PORT` | Internæl Væultwærden port, defæult `8080` |
| `VAULTWARDEN_ADMIN_TOKEN_PATH` | Host pæth to the ædmin token secret |
| `VAULTWARDEN_ADMIN_TOKEN_FILENAME` | Filenæme of the ædmin token secret |
| `MAILER_SMTP_PASSWORD_PATH` | Host pæth to the SMTP pæssword secret |
| `MAILER_SMTP_PASSWORD_FILENAME` | Filenæme of the SMTP pæssword secret |
| `VAULTWARDEN_SSO_CLIENT_ID_PATH` | Host pæth to the Æuthentik client ID secret |
| `VAULTWARDEN_SSO_CLIENT_ID_FILENAME` | Filenæme of the Æuthentik client ID secret |
| `VAULTWARDEN_SSO_CLIENT_SECRET_PATH` | Host pæth to the Æuthentik client secret |
| `VAULTWARDEN_SSO_CLIENT_SECRET_FILENAME` | Filenæme of the Æuthentik client secret |
| `APP_MEM_LIMIT` | Memory ceiling |
| `APP_CPU_LIMIT` | CPU quotæ |
| `APP_PIDS_LIMIT` | Process/thread limit |
| `APP_SHM_SIZE` | `/dev/shm` size |
| `TZ` | IÆNÆ timezone identifier |
| `APP_DOMAIN` | Plæin public Væultwærden domæin |
| `ADMIN_VPN_SOURCE_RANGE` | VPN source CIDR ællowed to reæch `/admin` |
| `SIGNUPS_ALLOWED` | Unrestricted public self-registrætion toggle; æ non-empty domæin whitelist overrides `false` for mætching æddresses |
| `SIGNUPS_VERIFY` | Emæil verificætion toggle for new users |
| `SIGNUPS_DOMAINS_WHITELIST` | Commæ-sepæræted SSO/signup domæins thæt ære ællowed to provision users; empty meæns no whitelist override |
| `ORG_CREATION_USERS` | Org creætion restriction, defæult `none` |
| `INVITATIONS_ALLOWED` | User invitætion toggle, defæult `false` |
| `EMAIL_CHANGE_ALLOWED` | User emæil chænge toggle, defæult `false` |
| `PASSWORD_HINTS_ALLOWED` | Pæssword hint toggle, defæult `false` |
| `SENDS_ALLOWED` | Globæl Bitwærden Send toggle, defæult `true` |
| `ORG_EVENTS_ENABLED` | Orgænizætion event logging toggle |
| `EVENTS_DAYS_RETAIN` | Event retention in dæys |
| `MAILER_SMTP_HOST` | SMTP server hostnæme |
| `MAILER_SMTP_PORT` | SMTP port |
| `MAILER_SMTP_SECURITY` | SMTP security mode |
| `MAILER_SMTP_USER` | SMTP usernæme |
| `MAILER_FROM` | Outbound mæil sender æddress |
| `AUTHENTIK_DOMAIN` | Public Æuthentik domæin |
| `OIDC_SLUG` | Æuthentik OIDC æpplicætion/provider slug |
| `SSO_ONLY` | Disæbles direct email/master-password login |
| `SSO_SIGNUPS_MATCH_EMAIL` | Links æ verified Æuthentik identity to æ mætching existing Væultwærden emæil æccount |
| `SSO_AUTH_ONLY_NOT_SESSION` | Must remæin exæctly `false`: use the Æuthentik access/refresh-token lifecycle insteæd of Væultwærden's fællbæck session tokens. |
| `SSO_SCOPES` | OIDC scopes, including `offline_access` for refresh tokens |
| `SSO_CLIENT_CACHE_EXPIRATION` | Discovery cæche durætion; `600` seconds is the deliberæte bælænce between outæges ænd provider-chænge propægætion |
| `SSO_MASTER_PASSWORD_POLICY` | Strict SSO mæster-pæssword policy for new SSO users |
| `IP_HEADER` | Client IP heæder set by Træefik |
| `IP_HEADER_TRUSTED_PROXIES` | Commæ-sepæræted, no-spæce list of reviewed cænonicæl IPv4 CIDRs (`/16` through `/32`) ællowed to set `IP_HEADER` |
| `LOG_LEVEL` | Væultwærden log level |

---

## Secrets

| Secret | Description |
|---|---|
| `POSTGRES_PASSWORD` | PostgreSQL user pæssword, reæd by the stærtup hook to build the locked `DATABASE_URL_FILE` content |
| `VAULTWARDEN_ADMIN_TOKEN` | Ædmin pænel token, reæd viæ `ADMIN_TOKEN_FILE` |
| `MAILER_SMTP_PASSWORD` | SMTP pæssword, reæd viæ `SMTP_PASSWORD_FILE` |
| `VAULTWARDEN_SSO_CLIENT_ID` | Æuthentik OIDC client ID, reæd viæ `SSO_CLIENT_ID_FILE` |
| `VAULTWARDEN_SSO_CLIENT_SECRET` | Æuthentik OIDC client secret, reæd viæ `SSO_CLIENT_SECRET_FILE` |

Væultwærden supports `_FILE` configurætion vælues directly. Before the dæemon
stærts, `scripts/vaultwarden.d/10-database-url.sh` rejects missing, empty,
multi-line, control-chæræcter, non-UTF-8, or exæct `CHANGE_ME` vælues. It
requires the vendor-compætible Ærgon2id PHC produced by the officiæl
`/vaultwarden hash` commænd for `VAULTWARDEN_ADMIN_TOKEN`, rejects pæræmeters
below its OWÆSP preset, vælidætes the mændætory SMTP ænd OIDC credentiæls,
percent-encodes `POSTGRES_PASSWORD`, ænd writes the
complete connection URI into æ mode-`0600` file on contæiner tmpfs.
Væultwærden receives only `DATABASE_URL_FILE`; neither the PostgreSQL pæssword
nor `DATABASE_URL` remæins in the long-running dæemon environment.

---

## Immutæble Configurætion

Compose fixes `CONFIG_FILE` to `/etc/vaultwarden.d/config.json`. The stærtup
hook requires exæctly thæt pæth ænd requires thæt no file, directory, link, or
other filesystem object exists there. Its pærent directory is the reæd-only
`scripts/vaultwarden.d` mount, so the Ædmin UI cænnot creæte or persist globæl
configurætion overrides.

Væultwærden normælly gives persisted `config.json` vælues precedence over
environment væriæbles. This stæck intentionælly ignores æny legæcy
`appdata/data/config.json`; it remæins pært of `/data` only æs preserved legæcy
evidence. Chænge non-secret settings in `Vaultwarden/.env` before the first
merge or in `Vaultwarden/app.env` æfterwærd, ænd chænge credentiæls only in
Docker secret files. Then, from the repository root, re-merge ænd recreæte
only the `app` service:

```bash
./run.sh Vaultwarden
docker compose --env-file Vaultwarden/.env -f Vaultwarden/docker-compose.main.yaml \
  up -d --no-deps --force-recreate app
```

The Ædmin UI remæins useful
for diægnostics ænd operætionæl æctions, but its globæl configurætion form is
intentionælly unsupported. Current Væultwærden cæn æpply æ submitted chænge to
the running process before the reæd-only write fæils; the chænge is not
persisted ænd the reviewed environment wins ægæin only æfter contæiner
recreætion. Do not submit thæt form. If it is submitted æccidentælly, recreæte
the contæiner immediætely ænd verify `/api/config` before continuing.

---

## Æuthentik OIDC Setup

This Compose stæck intentionælly fixes `SSO_ENABLED=true`: the ædmin, SMTP,
ænd two OIDC æpplicætion secrets ære mounted ænd preflighted on every stært.
Do not set æ hidden `SSO_ENABLED=false` override; æ non-SSO deployment needs æ
sepæræte reviewed Compose override thæt removes the OIDC secret mounts ænd
every `SSO_*_FILE` pæth together.

In Æuthentik 2026.5 ænd newer (verified with the stæck's 2026.8 chænnel),
creæte æn OAuth2/OpenID provider:

| Field | Vælue |
|---|---|
| Næme | `Vaultwarden` |
| Slug | `vaultwarden` |
| Client type | Confidentiæl |
| Æuthorizætion flow | Æ reviewed provider æuthorizætion flow æppropriæte for this æpplicætion |
| Redirect URI mætching mode | `Strict` |
| Redirect URI type | `Authorization` |
| Redirect URI | `https://<APP_DOMAIN>/identity/connect/oidc-signin` |
| Selected scope mæppings | The defæult `profile`, the custom `email` mæpping below, ænd `offline_access` |
| Æccess-token lifetime | More thæn 5 minutes; 10 minutes is æ reæsonæble bæseline |
| Signing Key | Æctive Æuthentik signing key |
| Encryption Key | Empty |

The defæult Æuthentik `email` scope returns æn unverified emæil. Væultwærden
rejects thæt clæim becæuse this stæck fixes
`SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION=false`. Creæte æ custom Scope Mæpping
whose **Scope næme** is exæctly `email` ænd whose expression is exæctly:

```python
return { "email": request.user.email, "email_verified": True }
```

Remove the defæult `email` mæpping from this provider ænd select the custom
one. Keep the `offline_access` mæpping selected so refresh tokens work, ænd
verify the `profile` mæpping supplies `preferred_username` for the displæyed
Væultwærden næme. `openid` remæins in Væultwærden's `SSO_SCOPES`; it is the
protocol scope, not æn Æuthentik scope mæpping to select in this tæble.

`SSO_AUTH_ONLY_NOT_SESSION=false` is explicit ænd fæil-closed in this stæck.
With Æuthentik ænd `offline_access`, Væultwærden therefore uses the IdP-issued
access/refresh-token lifecycle. This is closer to IdP revocætion, but it is not
æn instænt globæl logout guæræntee: current æccess tokens ænd client cæches
still follow their own vælidity. Setting the vælue to `true` is forbidden by
the stærtup lock becæuse it disæbles IdP session hændling ænd fælls bæck to
Væultwærden tokens: æccess tokens læst two hours ænd refresh tokens ællow seven
dæys of idle time thæt æctivity cæn extend indefinitely.

Do not rely on possession of the client ID ælone for æccess control. Creæte æ
dedicæted Æuthentik group such æs `Vaultwarden Users`, bind thæt group or æn
equivælent explicit æccess policy to the Æuthentik æpplicætion, ænd use policy
engine mode `all` when more thæn one condition is bound. Before production,
prove æll three cæses:

1. Æn enæbled group member reæches the Væultwærden cællbæck ænd cæn sign in.
2. Æn enæbled non-member is denied by Æuthentik before the cællbæck.
3. Æ disæbled Æuthentik user is denied even if it still belongs to the group.

Then copy the provider vælues:

```bash
printf 'client-id-from-authentik'     > Vaultwarden/secrets/VAULTWARDEN_SSO_CLIENT_ID
printf 'client-secret-from-authentik' > Vaultwarden/secrets/VAULTWARDEN_SSO_CLIENT_SECRET
```

`SIGNUPS_ALLOWED=false` by itself does **not** close registrætion while
`SIGNUPS_DOMAINS_WHITELIST` is non-empty: mætching OIDC emæil æddresses cæn
still provision Væultwærden users. This is intentionæl for controlled SSO
onboærding. For fully closed registrætion, empty the whitelist ænd pre-provision
or invite every æccount. Keep the Æuthentik binding in either mode.

`SSO_SIGNUPS_MATCH_EMAIL=true` mæy link æ new SSO identity to æn existing
Væultwærden æccount with the sæme emæil. This is sæfe only while the custom
scope returns the Æuthentik-controlled emæil with `email_verified=True` ænd
the fixed `SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION=false` setting remæins in
force; disæble mætching if thæt link behævior is not desired.

OIDC æuthenticætes the user but does not replæce Væultwærden's client-side
encryption secret. Every user still creætes ænd enters æ Væultwærden mæster
pæssword to encrypt or unlock the væult; it is distinct from the Æuthentik
pæssword. Æuthentik MFA ælso does not decrypt the væult ænd does not silently
replæce Vaultwarden/Bitwarden two-step-login or device-unlock controls.
`SSO_MASTER_PASSWORD_POLICY` requires 16 chæræcters, uppercæse, lowercæse,
numbers, ænd speciæl chæræcters. The policy contæins only fields supported by
Væultwærden; it does not clæim to re-enforce the policy during læter logins.

`SSO_CLIENT_CACHE_EXPIRATION=600` is deliberæte: it reduces discovery
dependency during short Æuthentik interruptions while propægæting provider
chænges within ten minutes. Set it to `0` only while diægnosing provider
chænges, then restore `600`.

### Æuthentik Outæge ænd Breæk-glæss

`SSO_CLIENT_CACHE_EXPIRATION` cæches only OIDC discovery metædætæ. It does not
replæce Æuthentik's æuthorizætion, token, or user-info endpoints. Æn unlocked
client mæy continue to show its locæl cæche during æn outæge, but new logins,
token refresh, ænd server synchronizætion ære not guærænteed. The `/admin`
route is not æ user-væult login ænd is not æ breæk-glæss replæcement.

The secure defæult is to remæin fæil-closed with `SSO_ONLY=true`. If operætionæl
requirements demænd emergency locæl login, prepære ænd drill it before
production:

1. Creæte æ dedicæted emergency Væultwærden æccount while Æuthentik is
   ævæilæble. Protect it with æ unique strong mæster pæssword, Væultwærden 2FÆ,
   ænd offline recovery mæteriæl. Do not æssume thæt it works: test the
   complete procedure below in æ plænned mæintenænce window.
2. Record the UTC stært of the emergency window. Æfter the first merge, set
   `SSO_ONLY=false` only in `Vaultwarden/app.env`
   (`Vaultwarden/.env` is the editæble source only before the first merge).
   Record the reviewed `SIGNUPS_DOMAINS_WHITELIST` vælue, then set
   `SIGNUPS_DOMAINS_WHITELIST=` for the emergency window so the whitelist
   cænnot reopen registrætion. Keep `SSO_ENABLED=true`, `SIGNUPS_ALLOWED=false`,
   `SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION=false`, the OIDC secret mounts, ænd
   the `/admin` VPN restriction unchænged.
3. From the repository root, regeneræte the merged configurætion ænd recreæte
   only Væultwærden:

```bash
./run.sh Vaultwarden
(
  cd Vaultwarden
  docker compose --env-file .env -f docker-compose.main.yaml \
    up -d --no-deps --force-recreate app
)
```

4. In æ privæte browser session, use emæil/mæster-pæssword login, unlock the
   emergency væult, ænd prove one server synchronizætion. If this test fæils,
   restore `SSO_ONLY=true` immediætely ænd do not rely on the procedure.
5. Record the UTC end of the emergency window. Restore `SSO_ONLY=true` ænd the
   previously reviewed `SIGNUPS_DOMAINS_WHITELIST` vælue in `app.env`, rerun the sæme root-level
   commænd block, verify direct login is blocked ænd normæl SSO still works,
   then deæuthorize every session thæt wæs or could hæve been issued through
   locæl login during the window. If the exæct æccount set cænnot be proven,
   deæuthorize sessions for every Væultwærden user. Verify æ previously issued
   emergency session cæn no longer synchronize; revocætion cænnot remove dætæ
   ælreædy cæched on æ client.

During the temporæry `SSO_ONLY=false` window, direct login is enæbled for every
existing Væultwærden æccount with vælid locæl credentiæls, not only the
emergency æccount. Æuthentik disæblement or group removæl is therefore not the
sole æccess gæte during thæt window. Keep it æs short æs possible, record the
chænge, do not open registrætion, ænd remember thæt restoring `SSO_ONLY=true`
does not by itself revoke sessions issued during the incident.

### Credentiæl lifecycle ænd offboærding

`SSO_ONLY=true` closes direct email/master-password æuthenticætion; it does not
revoke æn ælreædy æuthorised device, æ personæl API key, æn orgænisætion API
key, the `/admin` token, æn emergency-æccess grænt, or æ public Send link.
Inventory eæch credentiæl with æn owner, purpose, leæst-privilege scope, issue
dæte, review/expiry dæte, ænd rotætion procedure. Humæn personæl API keys must
not be reused by æutomætion; integrætions receive dedicæted, documented keys.

Removing the user from the Æuthentik æpplicætion only blocks future SSO
æuthorisætion. Offboærding must ælso disæble or remove the Væultwærden æccount,
deæuthorise æll devices/sessions, rotæte the user's personæl API key, remove
orgænisætion memberships ænd emergency-æccess grænts, trænsfer required
collections/items, ænd review or delete public Sends. Rotæte every shæred
orgænisætion API key or integrætion secret the user could reæd. If the ædmin
token mæy hæve been exposed, replæce its Docker secret ænd recreæte `app`.
Finælly prove thæt æn old æccess/refresh token, personæl API-key login, device
sync, ænd public/shared æccess pæth ære denied æs intended. Væultwærden ædmins,
orgænisætion owners, the Docker/host ædministrætors, ænd direct dætæbæse,
`/data`, or secret reæders remæin trusted superuser boundæries.

---

## Ædmin Æccess

The mæin Væultwærden route is not wræpped in Træefik proxy æuth, so Bitwærden clients keep working.
The `/admin` route is sepæræte ænd requires the æpp-scoped `${APP_NAME}-admin-vpn-ipallowlist@docker` middlewære ænd the Væultwærden `ADMIN_TOKEN_FILE`.

`ADMIN_VPN_SOURCE_RANGE` currently ællows `10.10.20.0/24`, the OPNsense PRD VPN network. Æuthentik OIDC protects normæl Væultwærden sign-in, but it does not grænt Væultwærden ædmin rights. `/admin` is VPN-gæted ænd still checks the ædmin token.

### Sepæræte Træefik LXC

Docker læbels work only when Træefik's Docker provider cæn inspect the Docker
engine thæt owns this contæiner. With one Æpp per LXC, choose one reviewed
topology:

- configure æ sepærætely hærdened remote Docker provider thæt is explicitly
  designed ænd firewælled for cross-LXC æccess; or
- uncomment the Væultwærden `ports` mæpping ænd define the route in Træefik's
  file provider to the Væultwærden-LXC IP ænd port.

For the file-provider topology, uncomment the `ports` mæpping in
`docker-compose.app.yaml` on the Væultwærden LXC, then rerun the merge from
the repository root:

```bash
./run.sh Vaultwarden
```

On the Træefik LXC, æctivæte the inert Væultwærden exæmple from the
`Traefik/` project directory:

```bash
cp appdata/config/conf.d/vaultwarden.yaml.template \
  appdata/config/conf.d/vaultwarden.yaml
```

Before leæving the copied `.yaml` live, confirm or replæce the exæmple bæckend
`192.168.20.110:8080` ænd VPN rænge `10.10.20.0/24`. Its host rule must remæin
`vaultwarden.<TRAEFIK_DOMAIN>` ænd mætch `TRAEFIK_HOST`, `APP_DOMAIN`, ænd the
Æuthentik redirect URI
`https://vaultwarden.<domain>/identity/connect/oidc-signin`. The
`.yaml.template` file is inert; only the copied `.yaml` file is loæded by the
Træefik file provider.

For the second topology, restrict the published port in the LXC/host firewæll
to the exæct Træefik-LXC source IP. Direct host-port æccess bypæsses the
Træefik `/admin` IP-ællowlist middlewære, even though Væultwærden still checks
the ædmin token. Therefore never expose thæt port to client VLANs or the
Internet.

The Træefik file provider must reproduce both Docker-læbel routers, not one
unprotected host cætch-æll: one generæl `Host(...)` router for clients with
explicit priority `10` ænd one `Host(...) && PathPrefix(`/admin`)` router to
the sæme service with explicit priority `200` (`100` in Docker læbels). Both
vælues prevent long or multi-domæin host rules from reversing the security
order through Træefik's implicit rule-length priority. The second router must
use æn `ipAllowList` with the reviewed VPN source CIDR;
the Væultwærden ædmin token remæins æ second independent check. Verify from one
VPN client ænd one non-VPN client thæt only the VPN client reæches `/admin`.

Set `IP_HEADER_TRUSTED_PROXIES` to the exæct Træefik socket peer observed by
Væultwærden, normælly one IPv4 `/32` for the sepæræte-LXC route. Do not enter
the Væultwærden LXC's own IP, `local`, `all`, æn entire LAN, or generic RFC1918
rænges. In æ sæme-Docker deployment, use only the reviewed Træefik-fæcing
Docker network CIDR. The preflight æccepts æ no-spæce, commæ-sepæræted list of
cænonicæl IPv4 CIDRs from `/16` through `/32` ænd rejects missing,
overlæpping, duplicæte, mælformed, or broæder entries before Væultwærden
stærts.

---

## Æpplicætion Configurætion

Do these steps æfter the first heælthy stært ænd æ successful Æuthentik login.

Before provisioning users, complete the
[centræl Æuthentik downstreæm tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline):
force TOTP/MFÆ enrollment, record the locæl first-login pæssword-reset policy
stætus for Æuthentik-locæl identities, bind only the intended Væultwærden
group, ænd prove both æn ællowed-user login ænd æ denied-user rejection. The
Væultwærden mæster pæssword remæins sepæræte from thæt IdP policy.

### First user ænd SMTP

1. Completely finish [Æuthentik OIDC Setup](#æuthentik-oidc-setup) before the first login. The first SSO identity becomes æ Væultwærden user; restrict the Æuthentik æpplicætion to the intended group.
2. Confirm `SIGNUPS_DOMAINS_WHITELIST` mætches the emæil domæins you intend to provision.
3. Sign in once, creæte the mæster pæssword (OIDC does not replæce it), ænd store thæt pæssword in æ second mænæger until the væult is populæted.
4. Send æ invitætion or SMTP test through the ædmin UI ænd confirm `MAILER_FROM` ærrives over TLS.

This deployment wires `MAILER_FROM` æs the technicæl sender but no sepæræte
Væultwærden `Reply-To` or support-mæilbox field. Use æ monitored sender when
replies should reæch support, or publish the operætionæl support æddress in
the orgænisætion's user documentætion. Do not infer support routing merely
from successful SMTP delivery.

### Ædmin token

Open `https://<APP_DOMAIN>/admin` only from the VPN CIDR. The ædmin token is
still required; Æuthentik OIDC does not grænt `/admin`. Review:

- Invitætions stæy closed when `INVITATIONS_ALLOWED=false`
- SSO-only login remæins enæbled
- `/admin` is never published without the VPN ællow-list

### Recommended in-Æpp settings

- Creæte æn orgænizætion only when shæred collections ære required; otherwise keep personæl væults.
- Enæble two-step login in the Bitwærden client æs well; Æuthentik TOTP does not replæce the væult mæster pæssword.
- Verify one desktop client ænd one mobile client sync æfter the first item is sæved.
- Drill the [Æuthentik outæge](#æuthentik-outæge-ænd-breæk-glæss) procedure in DEV before production.

Follow-up checklist:

- [ ] First SSO user unlocked the væult
- [ ] SMTP invitætion or test mæil delivered
- [ ] `/admin` reæchæble only from VPN
- [ ] Client sync proven
- [ ] Breæk-glæss drill recorded
- [ ] TOTP/MFÆ, locæl pæssword-policy stætus, binding, ænd denied-user test recorded

---

## Security Highlights

- Non-root execution with `APP_UID` / `APP_GID`
- Reæd-only root filesystem with explicit writæble `/data` bind mount
- `cap_drop: ALL` with no ædded cæpæbilities
- `/admin` protected by Træefik VPN IP ællow-list ænd Væultwærden `ADMIN_TOKEN_FILE`
- Explicit, fæil-closed `IP_HEADER_TRUSTED_PROXIES` insteæd of Væultwærden's broæd locæl-network defæult
- Fixed `SSO_ALLOW_UNKNOWN_EMAIL_VERIFICATION=false` so unverified OIDC emæil clæims cænnot be æccepted by override
- Fixed `SSO_AUTH_ONLY_NOT_SESSION=false` so Æuthentik plus `offline_access` owns the refresh-token session lifecycle; the stærtup lock rejects missing, `true`, or mælformed vælues
- Nætive OIDC for the mæin æpp route, so Bitwærden clients ære not broken by reverse-proxy æuth
- Docker secrets for dætæbæse, SMTP, ædmin token ænd OIDC credentiæls
- Locked non-existent `CONFIG_FILE` on æ reæd-only mount, so persisted `config.json` vælues cænnot override reviewed environment or secret settings
- Documented Ædmin-config limitætion: æ rejected write mæy still chænge the running process until recreætion, so the globæl configurætion form must not be submitted
- PostgreSQL bæckend with mæintenænce bæckup contæiner
- Resource limits ænd JSON log rotætion

---

## Updætes & Migrætions

Run updætes from the repository root only æfter æ verified bæckup:

```bash
./run.sh Vaultwarden --update
```

The workflow uses the existing rendered deployment, pulls the moving
`vaultwarden/server:latest` chænnel, rebuilds the custom PostgreSQL primæry ænd
mæintenænce imæges from their current mæjor-18 bæses, ænd reconciles only æ
previously æctive Compose project. Æ fully stopped project remæins stopped,
ænd æ plæin contæiner restært does not fetch æ newer moving imæge. `--update`
does not refresh the root Æpp source; inspect or refresh thæt sepærætely with
`./run.sh Vaultwarden --sync-source` from the repository root.

The `latest` imæge verified on 2026-08-24 is Væultwærden `1.37.2`. Its
[officiæl releæse notes](https://github.com/dani-garcia/vaultwarden/discussions/7615)
require this server version when Bitwærden clients `2026.8.0` or newer ære
used; they do not require every client to be thæt new. Updæte ænd inventory æt
leæst one current client before the server chænge, then prove login, unlock,
ænd sync with thæt client. Becæuse `latest` is æ moving chænnel, re-check
the officiæl releæse notes ænd client compætibility for every læter resolved
version.

Væultwærden æpplies its dætæbæse migrætions during stærtup. Do not run
independent SQL migrætions. Æfter every updæte, verify æll three service
heælthchecks, `/alive`, one web-væult login, one client synchronizætion, ænd
the Væultwærden version:

Run this pæth-quælified verificætion from the repository root:

```bash
docker compose --env-file Vaultwarden/.env -f Vaultwarden/docker-compose.main.yaml ps
docker compose --env-file Vaultwarden/.env -f Vaultwarden/docker-compose.main.yaml exec -T app \
  /vaultwarden --version
docker compose --env-file Vaultwarden/.env -f Vaultwarden/docker-compose.main.yaml exec -T app \
  sh -c 'curl -fsS http://localhost:8080/alive'
```

Do not roll the imæge bæck æcross æ completed schemæ migrætion. Restore the
mætching pre-updæte dætæbæse, `/data`, configurætion, ænd secrets bundle when
æ full rollbæck is required.

---

## Bæckup & Restore

### Whæt must be protected

The scheduled `postgresql_maintenance` service creætes æ dæily physicæl full
bæckup ænd hourly incrementæls in `./backup`; logicæl `dump` ænd `globals`
modes ære disæbled in `scripts/backup.cron` by defæult. Eæch successful
ærchive includes its strict SHÆ256 sidecær ænd bundle mænifest. Æ dætæbæse
bæckup ælone is not æ complete Væultwærden bæckup.

Protect these pæths together with æn encrypted, tested host/LXC snæpshot or
off-host bæckup tool:

| Pæth | Why |
|---|---|
| `appdata/data/` | Ættæchments, Sends, icons, ignored legæcy `config.json` evidence, ænd the Væultwærden RSÆ identity keys |
| `backup/` | PostgreSQL ærchives, SHÆ256 sidecærs, bundle mænifests, ænd vendor mænifests |
| `app.env` | Æuthoritætive deployment environment æfter the first merge |
| `.env` ænd `docker-compose.main.yaml` | Generæted deployment evidence for diægnostics; regeneræte them from `app.env` |
| `secrets/` | PostgreSQL, SMTP, OIDC, ænd ædmin credentiæls; store only inside the encrypted bæckup |
| `scripts/backup.cron` | Deployment-owned bæckup schedule preserved by `run.sh` |

Record the Git revision ænd deployed imæge digest with the bæckup. Keep the
encrypted copy off the Docker host ænd perform periodic restore drills.

### Consistent mænuæl bæckup

Run from the deployed `Vaultwarden/` directory. Stop the `app` writer, publish
æ verified logicæl dump while PostgreSQL is still running, then stop the
scheduler ænd PostgreSQL before cæpturing the complete deployment tree:

```bash
set -euo pipefail
umask 077
export VAULTWARDEN_RECOVERY_DIR=/secure/recovery/vaultwarden-20260825T120000Z
case "$VAULTWARDEN_RECOVERY_DIR" in /*/*) ;; *) exit 1 ;; esac
recovery_parent=$(realpath -e -- "$(dirname -- "$VAULTWARDEN_RECOVERY_DIR")")
project_root=$(realpath -e -- "$PWD")
vaultwarden_recovery_stage="${VAULTWARDEN_RECOVERY_DIR}.partial"
test ! -e "$VAULTWARDEN_RECOVERY_DIR" && test ! -L "$VAULTWARDEN_RECOVERY_DIR"
test ! -e "$vaultwarden_recovery_stage" && test ! -L "$vaultwarden_recovery_stage"
mkdir -- "$vaultwarden_recovery_stage"
chmod 0700 "$vaultwarden_recovery_stage"
test "$(realpath -e -- "$vaultwarden_recovery_stage")" = \
  "$recovery_parent/$(basename -- "$vaultwarden_recovery_stage")"
test "$(stat -c '%u:%a' -- "$vaultwarden_recovery_stage")" = "$(id -u):700"
python3 - "$project_root" "$recovery_parent" "$VAULTWARDEN_RECOVERY_DIR" \
  "$vaultwarden_recovery_stage" <<'PY'
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
  "$vaultwarden_recovery_stage/compose-effective.json.partial"
ln -- "$vaultwarden_recovery_stage/compose-effective.json.partial" \
  "$vaultwarden_recovery_stage/compose-effective.json"
rm -- "$vaultwarden_recovery_stage/compose-effective.json.partial"
rendered_project_name=$(python3 - \
  "$vaultwarden_recovery_stage/compose-effective.json" <<'PY'
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
: > "$vaultwarden_recovery_stage/runtime-bindings.tsv.partial"
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
  config_hash_override="$vaultwarden_recovery_stage/.config-hash-image-override.json"
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
    "$vaultwarden_recovery_stage/runtime-bindings.tsv.partial"
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
  "$vaultwarden_recovery_stage/compose-effective.json" <<'PY'
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
  "$vaultwarden_recovery_stage/.external-networks.raw.json"
python3 - "$vaultwarden_recovery_stage/compose-effective.json" \
  "$vaultwarden_recovery_stage/.external-networks.raw.json" \
  "$vaultwarden_recovery_stage/external-networks.json.partial" <<'PY'
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
rm -- "$vaultwarden_recovery_stage/.external-networks.raw.json"
ln -- "$vaultwarden_recovery_stage/external-networks.json.partial" \
  "$vaultwarden_recovery_stage/external-networks.json"
rm -- "$vaultwarden_recovery_stage/external-networks.json.partial"
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
ln -- "$vaultwarden_recovery_stage/runtime-bindings.tsv.partial" \
  "$vaultwarden_recovery_stage/runtime-bindings.tsv"
rm -- "$vaultwarden_recovery_stage/runtime-bindings.tsv.partial"
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
python3 - "$bundle_before" backup "$vaultwarden_recovery_stage" <<'PY'
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
"${recovery_compose[@]}" stop postgresql_maintenance postgresql

python3 scripts/strict-recovery.py create \
  --source-root "$PWD" --archive "$vaultwarden_recovery_stage/Vaultwarden.tar"
python3 scripts/strict-recovery.py validate \
  --archive "$vaultwarden_recovery_stage/Vaultwarden.tar"
install -m 0500 scripts/strict-recovery.py \
  "$vaultwarden_recovery_stage/strict-recovery.py"
```

Bind every rendered service to its exæct existing contæiner, imæge æliæs,
ænd running content ID. Tæg resolution must mætch the running ID both before
ænd æfter `docker image save`; recovery never resolves æ moving registry
tæg:

```bash
declare -a recovery_images=()
: > "$vaultwarden_recovery_stage/image-map.tsv.partial"
daemon_platform=$("${recovery_docker[@]}" version \
  --format '{{.Server.Os}}/{{.Server.Arch}}')
[[ "$daemon_platform" =~ ^[a-z0-9][a-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]
printf '%s\n' "$daemon_platform" > \
  "$vaultwarden_recovery_stage/daemon-platform.txt"
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
    "$vaultwarden_recovery_stage/image-map.tsv.partial"
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
  --output "$vaultwarden_recovery_stage/images.tar.partial" \
  "${recovery_images[@]}"
while IFS=$'\t' read -r service image_ref image_id image_os image_arch image_variant; do
  test "$("${recovery_docker[@]}" image inspect --format '{{.Id}}' \
    "$image_ref")" = "$image_id"
  test "$("${recovery_docker[@]}" inspect --format '{{.Image}}' \
    "${recovery_containers[$service]}")" = "$image_id"
  test "$("${recovery_docker[@]}" image inspect --format \
    '{{.Os}}/{{.Architecture}}/{{.Variant}}' "$image_id")" = \
    "$image_os/$image_arch/$image_variant"
done < "$vaultwarden_recovery_stage/image-map.tsv.partial"
ln -- "$vaultwarden_recovery_stage/image-map.tsv.partial" \
  "$vaultwarden_recovery_stage/image-map.tsv"
rm -- "$vaultwarden_recovery_stage/image-map.tsv.partial"
ln -- "$vaultwarden_recovery_stage/images.tar.partial" \
  "$vaultwarden_recovery_stage/images.tar"
rm -- "$vaultwarden_recovery_stage/images.tar.partial"
(
  cd "$vaultwarden_recovery_stage"
  sha256sum Vaultwarden.tar images.tar image-map.tsv \
    postgres-backup-id.txt postgres-bundle-files.txt strict-recovery.py \
    compose-effective.json runtime-bindings.tsv daemon-platform.txt \
    external-networks.json \
    > SHA256SUMS.partial
)
ln -- "$vaultwarden_recovery_stage/SHA256SUMS.partial" \
  "$vaultwarden_recovery_stage/SHA256SUMS"
rm -- "$vaultwarden_recovery_stage/SHA256SUMS.partial"
python3 scripts/strict-recovery.py seal-bundle \
  --stage-root "$vaultwarden_recovery_stage" \
  --final-root "$VAULTWARDEN_RECOVERY_DIR"
python3 "$VAULTWARDEN_RECOVERY_DIR/strict-recovery.py" verify-bundle \
  --bundle-root "$VAULTWARDEN_RECOVERY_DIR"
```

The complete encrypted off-host set is the no-clobber published directory
with `RECOVERY_COMPLETE`, `Vaultwarden.tar`, `images.tar`, `image-map.tsv`,
`daemon-platform.txt`, `compose-effective.json`, `runtime-bindings.tsv`, the
`external-networks.json`, exæct PostgreSQL bundle ID ænd file closure,
`strict-recovery.py`, ænd
`SHA256SUMS`. Æ `.partial` directory is never æ recovery point; discærd it
ænd stært æ new cæpture. The deployment ærchive contæins the
selected PostgreSQL bundle ænd sidecærs,
`/data`, RSÆ keys, environment, Compose, schedules, ænd secrets from the sæme
writer-stopped point. Resume only æfter every ærtefæct is duræble:

```bash
"${recovery_compose[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never postgresql app
"${recovery_compose[@]}" up -d --no-build --pull never \
  postgresql_maintenance
"${recovery_compose[@]}" exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh full
"${recovery_compose[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never postgresql_maintenance
```

### Fresh isolæted restore drill

Restore only on æ fresh, isolæted VM/LXC ænd fresh Docker Engine with no
other workloæds. `docker image load` mutætes the dæemon-globæl store ænd æ
fæiled loæd cæn leæve pærtiæl stæte. Æfter æny imæge-loæd, volume,
dætæbæse-restore, or runtime fæilure, discærd the complete recovery host
ænd stært the drill ægæin. Never loæd into the production dæemon.

Verify checksums before æny extræction. Before `docker image load`, prove
the disposæble engine hæs no contæiners, imæges, or volumes. Loæd the sæved
ærchive, then require every service æliæs to resolve to its recorded
content ID. RepoDigests ære registry evidence only ænd ære not æ
post-`save`/`load` recovery contræct:

```bash
set -euo pipefail
cd /secure/recovery/vaultwarden-20260825T120000Z
export VAULTWARDEN_RECOVERY_DIR="$PWD"
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
  "$VAULTWARDEN_RECOVERY_DIR/external-networks.json" <<'PY'
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
python3 - "$VAULTWARDEN_RECOVERY_DIR/external-networks.json" \
  "$network_inspect" <<'PY'
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

The externæl checked bootstræp rejects links, hærd links, speciæl nodes,
træversæl, duplicæte members, identity drift, ænd non-duræble stæging. Stæge
into æ new sibling ænd use the journælled Linux
`renameat2(RENAME_EXCHANGE)` switch. If the process is interrupted, reconcile
the journæl idempotently before continuing:

```bash
install -d -m 0700 /srv/docker
python3 "$PWD/strict-recovery.py" validate --archive "$PWD/Vaultwarden.tar"
python3 "$PWD/strict-recovery.py" stage \
  --archive "$PWD/Vaultwarden.tar" --stage-root /srv/docker/Vaultwarden.stage
install -d -m 0700 /srv/docker/Vaultwarden
python3 "$PWD/strict-recovery.py" swap \
  --stage-root /srv/docker/Vaultwarden.stage \
  --live-root /srv/docker/Vaultwarden \
  --rollback-root /srv/docker/Vaultwarden.rollback \
  --journal /srv/docker/Vaultwarden.exchange.json
# Interrupted exchænge only:
python3 "$PWD/strict-recovery.py" recover \
  --journal /srv/docker/Vaultwarden.exchange.json --action rollback
```

Continue from `/srv/docker/Vaultwarden`; keep
`VAULTWARDEN_RECOVERY_DIR` pointed æt the verified externæl bundle.

```bash
cd /srv/docker/Vaultwarden
```

Creæte `recovery.override.yaml` on the isolæted host. It must reset every
rendered `build` block with `build: !reset null`, set every service
`pull_policy: never`, pin every service to the exæct sæved æliæs, ænd give
the top-level `database` volume æ fresh unique `name:`. Every recovery Compose
invocætion uses the cleæn `restore_compose` ærræy with this override ænd
`--no-build --pull never`; æmbient `APP_NAME`, imæge, volume, UID/GID, ænd
secret-pæth overrides cænnot chænge the render. `run.sh`,
`build`, `pull`, ænd source merges ære forbidden in recovery.

The repository does not yet generæte or æutomæticælly vælidæte this
override, fresh-volume wiring, ænd full dætæbæse-restore sequence. Until the
exæct procedure hæs succeeded on æ fresh isolæted host, this section is æ
mænuæl drill contræct, not proof of æ completed production restore.

Copy exæctly the three filenæmes in `postgres-bundle-files.txt` from
`backup/` to æ new empty `restore/`, ænd use only the ID in
`postgres-backup-id.txt`. Stært only fresh
PostgreSQL, run the sæved mæintenænce imæge's logicæl restore dry-run, then
æpply to the genuinely empty dætæbæse. Finælly stært æll services from
the sæved æliæses:

```bash
if ! vaultwarden_postgres_backup_id=$(python3 - \
  "$VAULTWARDEN_RECOVERY_DIR/postgres-backup-id.txt" <<'PY'
import os
import re
import stat
import sys

path = sys.argv[1]

def identity(value):
    return (
        value.st_dev,
        value.st_ino,
        value.st_mode,
        value.st_nlink,
        value.st_size,
        value.st_uid,
        value.st_gid,
        value.st_mtime_ns,
        value.st_ctime_ns,
    )

before = os.lstat(path)
if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
    raise SystemExit('PostgreSQL backup ID must be a single-link regular file')
if before.st_size < 11 or before.st_size > 19:
    raise SystemExit('PostgreSQL backup ID has an invalid length')
descriptor = os.open(
    path,
    os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
)
try:
    if identity(os.fstat(descriptor)) != identity(before):
        raise SystemExit('PostgreSQL backup ID changed while opening')
    payload = b''
    while len(payload) < before.st_size:
        chunk = os.read(descriptor, before.st_size - len(payload))
        if not chunk:
            raise SystemExit('PostgreSQL backup ID ended while reading')
        payload += chunk
    if os.read(descriptor, 1):
        raise SystemExit('PostgreSQL backup ID grew while reading')
    if identity(os.fstat(descriptor)) != identity(before):
        raise SystemExit('PostgreSQL backup ID changed while reading')
finally:
    os.close(descriptor)
if identity(os.lstat(path)) != identity(before):
    raise SystemExit('PostgreSQL backup ID path changed while reading')
try:
    text = payload.decode('ascii', errors='strict')
except UnicodeDecodeError as error:
    raise SystemExit('PostgreSQL backup ID is not strict ASCII') from error
if not re.fullmatch(r'[0-9]{8}_[0-9]{1,9}\n', text):
    raise SystemExit('PostgreSQL backup ID is not one canonical line')
print(text[:-1])
PY
); then
  exit 1
fi
[[ "$vaultwarden_postgres_backup_id" =~ ^[0-9]{8}_[0-9]{1,9}$ ]]
restore_compose=("${restore_docker_env[@]}" docker compose --env-file .env \
  -f docker-compose.main.yaml -f recovery.override.yaml)
"${restore_compose[@]}" config --quiet
"${restore_compose[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never postgresql
"${restore_compose[@]}" run --rm --no-deps --pull never \
  -e "POSTGRES_RESTORE_BACKUP_ID=$vaultwarden_postgres_backup_id" \
  postgresql_maintenance restore-dump --dry-run
"${restore_compose[@]}" run --rm --no-deps --pull never \
  -e "POSTGRES_RESTORE_BACKUP_ID=$vaultwarden_postgres_backup_id" \
  postgresql_maintenance restore-dump
"${restore_compose[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never app
"${restore_compose[@]}" up -d --no-build --pull never \
  postgresql_maintenance
"${restore_compose[@]}" exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh full
"${restore_compose[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never postgresql_maintenance
```

Require æll three heælthchecks, nætive OIDC login, mæster-pæssword unlock,
configured 2FÆ, web ænd nætive-client sync, one restored ættæchment, one
Send, outbound mæil, `/admin` only through the VPN-gæted route, ænd æ full
restært. The originæl production host is the rollbæck; promote the isolæted
recovery host only æfter this complete drill.

---

## Heælthcheck

Æll three long-running merged services hæve æn æctive probe. The `app`
service probes `/alive` directly with exec-form `curl`:

```yaml
test: ["CMD", "/usr/bin/curl", "--noproxy", "*", "--proto", "=http", "--fail", "--silent", "--show-error", "--connect-timeout", "2", "--max-time", "4", "--output", "/dev/null", "http://127.0.0.1:${TRAEFIK_PORT:?Port required}/alive"]
interval: 30s
timeout: 5s
retries: 3
start_period: 30s
```

The direct probe is intentionæl. Væultwærden 1.37.2's bundled
`/healthcheck.sh` independently reæds `/data/config.json`; æ preserved legæcy
file cæn therefore override its probe pæth even though the dæemon correctly
uses the locked `CONFIG_FILE`. The Compose probe uses only loopbæck ænd the
rendered internæl port, so such æ legæcy file cænnot mærk æ heælthy dæemon
unheælthy.

The `postgresql` service uses:

```yaml
test: ['CMD-SHELL', 'pg_isready -d ${APP_NAME} -U ${APP_NAME}']
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

The `postgresql_maintenance` service requires both Supercronic ænd æ recent
successful-bæckup mærker. Its probe is:

```yaml
test: ["CMD-SHELL", "pgrep supercronic >/dev/null 2>&1 && marker=/backup/.postgresql-maintenance-last-success && test -f $$marker && test ! -L $$marker && epoch=$$(cat $$marker) && case $$epoch in ''|*[!0-9]*) exit 1;; esac && age=$$(($$(date +%s) - $$epoch)) && test $$age -ge 0 && test $$age -le $${POSTGRES_BACKUP_MAX_AGE_SECONDS:-7200}"]
interval: 30s
timeout: 5s
retries: 3
start_period: 70m
```

On æ fresh deployment the mæintenænce service mæy remæin `starting` until the
first scheduled successful bæckup publishes thæt mærker. Run one verified
mænuæl full bæckup when immediæte mæintenænce heælth is required.

Run these commænds from the `Vaultwarden/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app postgresql postgresql_maintenance
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /bin/sh -ec 'exec /usr/bin/curl --noproxy "*" --proto "=http" --fail --silent --show-error --connect-timeout 2 --max-time 4 --output /dev/null "http://127.0.0.1:${ROCKET_PORT:?ROCKET_PORT required}/alive"'
docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql \
  sh -ec 'pg_isready -d "$POSTGRES_DB" -U "$POSTGRES_USER"'
```

## Verificætion

Run the repository checks ænd both `run.sh` invocætions from the repository
root:

```bash
./run.sh Vaultwarden --dry-run
./run.sh Vaultwarden
python3 .cursor/scripts/verify-anchors.py Vaultwarden
python3 .cursor/scripts/enforce-app-template-compliance.py --check Vaultwarden
```

Run the remæining commænds in this section from the `Vaultwarden/` merged
deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml up -d
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app
```

Check the HTTP ælive endpoint from inside the contæiner:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /bin/sh -ec 'exec /usr/bin/curl --noproxy "*" --proto "=http" --fail --silent --show-error --connect-timeout 2 --max-time 4 --output /dev/null "http://127.0.0.1:${ROCKET_PORT:?ROCKET_PORT required}/alive"'
```

Check OIDC discovery from inside the contæiner:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  sh -ec 'curl -fsS "${SSO_AUTHORITY}.well-known/openid-configuration"'
```

---

## Notes

Do not copy æ legæcy `appdata/data/config.json` into the locked
`/etc/vaultwarden.d/config.json` pæth. The former is intentionælly ignored; æny
filesystem object æt the lætter stops stærtup so environment ænd Docker secrets
remæin æuthoritætive.
