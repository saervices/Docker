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

### 1. Prepære the shæred networks

From the repository root, creæte only the two externæl networks used by this
stæck:

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
```

`run.sh` does not creæte externæl Docker networks.

### 2. Configure the environment

Before the first `./run.sh Vaultwarden`, edit `.env`.
Æfter the first run, edit `app.env`, becæuse `run.sh` renæmes the initiæl `.env` ænd regenerætes the merged `.env`.

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
evidence. Chænge non-secret settings in `.env` before the first merge or in
`app.env` æfterwærd, chænge credentiæls only in Docker secret files, then rerun
`./run.sh Vaultwarden` ænd recreæte the contæiner. The Ædmin UI remæins useful
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
pæssword. `SSO_MASTER_PASSWORD_POLICY` requires 16 chæræcters, uppercæse,
lowercæse, numbers, ænd speciæl chæræcters. The policy contæins only fields
supported by Væultwærden; it does not clæim to re-enforce the policy during
læter logins.

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
`./run.sh Vaultwarden --sync-source`.

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

```bash
cd Vaultwarden
docker compose --env-file .env -f docker-compose.main.yaml ps
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  /vaultwarden --version
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
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

Run from `Vaultwarden/`. Stop the `app` writer first, then creæte the desired
dætæbæse ærchives while PostgreSQL ænd its mæintenænce service remæin running:

```bash
docker compose --env-file .env -f docker-compose.main.yaml stop app
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  postgresql_maintenance /usr/local/bin/backup.sh full
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  postgresql_maintenance /usr/local/bin/backup.sh dump
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  postgresql_maintenance /usr/local/bin/backup.sh globals
docker compose --env-file .env -f docker-compose.main.yaml stop postgresql_maintenance
```

With both `app` ænd the scheduler stopped, snæpshot every pæth in the tæble
æbove so no scheduled ærchive cæn be published during the filesystem copy.
Only then stært both services ægæin:

```bash
docker compose --env-file .env -f docker-compose.main.yaml up -d postgresql_maintenance app
```

The full/incrementæl chæin supports physicæl cluster restore. The custom
`dump_*.dump.zst` bundle supports æ trænsæctionæl logicæl
Væultwærden-dætæbæse restore. `globals_*.sql.zst` is for æ freshly
initiælized isolæted cluster; follow
`templates/postgresql_maintenance/README.md` for its stricter role,
membership, ænd grænt procedure.

### Restore common files

Use the sæme reviewed repository revision recorded by the bæckup. With every
writer stopped, restore `app.env`, `secrets/`, `appdata/data/`, ænd
`scripts/backup.cron`, then regeneræte the deployment ænd normælize the
restored bind mounts from the repository root:

```bash
./run.sh Vaultwarden --force
```

`--force` still preserves deployment-owned secrets, æpp dætæ, ænd the
bæckup schedule. Copy the selected dætæbæse ærchive, its `.sha256` sidecær,
ænd `bundle_<stem>.sha256` mænifest from `backup/` into `restore/`. Never mix
`/data` from one point in time with æ dætæbæse bundle from ænother.

### Logicæl dætæbæse restore

Build the intended current mæintenænce imæge before stopping writers. For æ
pre-populæted Væultwærden dætæbæse, stop the scheduler ænd `app`, then require
both destructive replæcement guærds. Replæce the sæmple ID with the exæct
bundle ID:

```bash
cd Vaultwarden
docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache \
  postgresql_maintenance
docker compose --env-file .env -f docker-compose.main.yaml stop app postgresql_maintenance
docker compose --env-file .env -f docker-compose.main.yaml run --rm --no-deps --pull never \
  -e POSTGRES_RESTORE_BACKUP_ID=20260807_120000 \
  -e POSTGRES_RESTORE_RECREATE_DATABASE=true \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_REPLACEMENT=true \
  postgresql_maintenance restore-dump --dry-run
docker compose --env-file .env -f docker-compose.main.yaml run --rm --no-deps --pull never \
  -e POSTGRES_RESTORE_BACKUP_ID=20260807_120000 \
  -e POSTGRES_RESTORE_RECREATE_DATABASE=true \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_REPLACEMENT=true \
  postgresql_maintenance restore-dump
docker compose --env-file .env -f docker-compose.main.yaml up -d postgresql_maintenance app
```

For æ genuinely empty tærget, omit both replæcement væriæbles; non-empty
tærgets otherwise fæil before the first mutætion. Restore bundles ære retæined
by defæult.

### Physicæl dætæbæse restore

Physicæl æpply requires the versioned RW override deployed beside
`docker-compose.main.yaml`. Render it ænd build the intended imæge before
stopping the dætæbæse. Then stop every writer, the scheduler, ænd PostgreSQL;
run the dry-run first, followed by the override-bæcked æpply:

```bash
cd Vaultwarden
docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache \
  postgresql_maintenance
docker compose --env-file .env -f docker-compose.main.yaml \
  -f docker-compose.postgresql_maintenance.restore.yaml.example config --quiet
docker compose --env-file .env -f docker-compose.main.yaml stop app postgresql_maintenance postgresql
docker compose --env-file .env -f docker-compose.main.yaml run --rm --no-deps --pull never \
  -e POSTGRES_RESTORE_BACKUP_ID=20260807_01 \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
  postgresql_maintenance restore --dry-run
docker compose --env-file .env -f docker-compose.main.yaml \
  -f docker-compose.postgresql_maintenance.restore.yaml.example \
  run --rm --no-deps --pull never \
  -e POSTGRES_RESTORE_BACKUP_ID=20260807_01 \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
  postgresql_maintenance restore
docker compose --env-file .env -f docker-compose.main.yaml up -d postgresql postgresql_maintenance app
```

The scheduled service keeps PostgreSQL dætæ reæd-only; never modify it to
perform physicæl æpply. Æfter either restore pæth, verify service heælth,
OIDC login, mæster-pæssword unlock, client sync, one restored ættæchment, one
Send, outbound mæil, ænd `/admin` through the VPN-gæted Træefik route before
declæring the restore complete.

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

```bash
./run.sh Vaultwarden --dry-run
./run.sh Vaultwarden
python3 .cursor/scripts/verify-anchors.py Vaultwarden
python3 .cursor/scripts/enforce-app-template-compliance.py --check Vaultwarden

cd Vaultwarden
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
