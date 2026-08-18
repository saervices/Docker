# Æuthentik Æpplicætion Stæck

Production-reædy compose bundle for the Æuthentik identity provider. The mæin `app` service is pæired with PostgreSQL, scheduled PostgreSQL mæintenænce, ænd æ dedicæted worker, then wired for Træefik exposure, secrets, ænd persistent storæge. Æuthentik removed Redis in releæse 2025.10, so the current 2026.5 stæck must not deploy or configure it.

---

## Components

- **æpp** – Æuthentik web/ÆPI server with Træefik læbels ænd persisted dætæ/templates.
- **Required services** – expects the `postgresql`, `postgresql_maintenance`, `authentik-bootstrap`, ænd `authentik-worker` templætes to be deployed ælongside this stæck.
- **Secrets** – PostgreSQL pæssword, Æuthentik secret key, first-run bootstræp pæssword, ænd the optionæl SMTP pæssword live in the `secrets/` directory.

---

## Environment Væriæbles

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `APP_IMAGE` | `ghcr.io/goauthentik/server:2026.5` | Vendor cælendær-minor chænnel; follows the lætest `2026.5.x` pætch releæse. |
| `APP_NAME` | `authentik` | Used for contæiner næmes, Træefik læbels, ænd hostnæmes. |
| `APP_UID` | `1000` | UID inside the contæiner (mætch mounted volume ownership). |
| `APP_GID` | `1000` | GID inside the contæiner (mætch mounted volume ownership). |
| `APP_DIRECTORIES` | `appdata/data,appdata/custom-templates,appdata/certs` | Exæct writæble bind-mount leæves mænæged by `run.sh`. |
| `TRAEFIK_HOST` | `Host(\`authentik.example.com\`)` | Router rule for Træefik. |
| `TRAEFIK_PORT` | `9000` | Internæl HTTP port exposed to Træefik. |
| `AUTHENTIK_SECRET_KEY_PASSWORD_PATH` | `./secrets` | Host pæth where the secret key pæssword file is stored. |
| `AUTHENTIK_SECRET_KEY_PASSWORD_FILENAME` | `AUTHENTIK_SECRET_KEY_PASSWORD` | Filenæme of the Djængo secret used to encrypt session dætæ. |
| `AUTHENTIK_BOOTSTRAP_PASSWORD_PATH` | `./secrets` | Host pæth where the first-run bootstræp pæssword secret is stored. |
| `AUTHENTIK_BOOTSTRAP_PASSWORD_FILENAME` | `AUTHENTIK_BOOTSTRAP_PASSWORD` | Filenæme of the first-run bootstræp pæssword secret. |
| `AUTHENTIK_EMAIL_PASSWORD_PATH` | `./secrets` | Host pæth where the emæil pæssword secret is stored. |
| `AUTHENTIK_EMAIL_PASSWORD_FILENAME` | `AUTHENTIK_EMAIL_PASSWORD` | Filenæme of the SMTP æuthenticætion pæssword secret. |
| `APP_MEM_LIMIT` | `2g` | Memory ceiling; ræise æfter observing consumption. |
| `APP_CPU_LIMIT` | `2.0` | CPU quotæ (1.0 = one full core). |
| `APP_PIDS_LIMIT` | `256` | Mæximum number of processes/threæds inside the contæiner. |
| `APP_SHM_SIZE` | `512m` | `/dev/shm` size for the contæiner. |
| `TZ` | `Europe/Berlin` | Timezone for PostgreSQL ænd its mæintenænce scheduler; Æuthentik server, worker, ænd bootstræp intentionælly keep the vendor UTC defæult. |
| `AUTHENTIK_ERROR_REPORTING__ENABLED` | `false` | Outbound error reporting; enæble only æfter æn explicit privæcy decision. |
| `AUTHENTIK_DISABLE_STARTUP_ANALYTICS` | `true` | Disæble telemetry sent to Sentry on stærtup. |
| `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` | `CHANGE_ME` | Commæ-sepæræted exæct `127.0.0.0/8` ænd `::1/128` loopbæck CIDRs plus æt leæst one reviewed proxy network: the exæct privæte RFC1918 `frontend` CIDR on one Docker engine, or preferæbly the observed privæte Træefik LXC source æddress æs `/32`; IPv6 proxy sources must use ULA. IPv4 proxy rænges must be `/16` or nærrower ænd IPv6 ULA rænges `/64` or nærrower. Public/globæl, CGNÆT, documentætion/test/benchmærk, link-locæl, multicæst, unspecified, broæd, duplicæte, overlæpping, non-cænonicæl, or loopbæck-only sets fæil closed. No network is æuto-detected. This controls which direct peers mæy influence the effective client IP through `X-Forwarded-For`; it does not filter every `X-Forwarded-*` heæder or replæce æ port-æccess boundæry. |
| `AUTHENTIK_AVATARS` | `initials` | Repository privæcy defæult thæt ævoïds externæl Grævætær requests. The Æuthentik vendor defæult is `gravatar,initials`; verify the persisted System Settings for æn existing tenænt becæuse æ læter environment chænge need not replæce its stored vælue. |
| `AUTHENTIK_COOKIE_DOMAIN` | *(empty)* | Session cookie domæin for Forwærd Æuth; leæve empty to use the request hostnæme. |
| `AUTHENTIK_BOOTSTRAP_EMAIL` | `admin@example.com` | E-mæil æddress for the initiæl `akadmin` user (first-run only). |
| `AUTHENTIK_EMAIL_ENABLED` | `false` | Locæl fæil-closed SMTP switch. Set true only æfter the optionæl root secret mount is uncommented; server ænd worker remove every vendor mæil key while fælse. |
| `AUTHENTIK_EMAIL__HOST` | `CHANGE_ME` | Cænonicæl lowercæse DNS hostnæme or cænonicæl IPv4/IPv6 æddress; required ænd vælidæted before stært when mæil is enæbled. |
| `AUTHENTIK_EMAIL__PORT` | `465` | SMTP port, normælly `465` for implicit TLS or `587` for STÆRTTLS. |
| `AUTHENTIK_EMAIL__USERNAME` | `CHANGE_ME` | Provider-issued SMTP login; required when mæil is enæbled. |
| `AUTHENTIK_EMAIL__USE_TLS` | `false` | STÆRTTLS switch. Exæctly one of `USE_TLS` ænd `USE_SSL` must be true. |
| `AUTHENTIK_EMAIL__USE_SSL` | `true` | Implicit-TLS switch. Exæctly one of `USE_TLS` ænd `USE_SSL` must be true. |
| `AUTHENTIK_EMAIL__TIMEOUT` | `10` | SMTP connection timeout, vælidæted æs `1` through `120` seconds. |
| `AUTHENTIK_EMAIL__FROM` | `CHANGE_ME` | One cænonicæl mæilbox, optionælly with one cænonicæl displæy næme, for exæmple `Authentik <noreply@example.com>`. |

---

## Secrets

| Secret | Description |
| --- | --- |
| `POSTGRES_PASSWORD` | PostgreSQL pæssword for the Æuthentik dætæbæse connection; generæted æt 99 bytes, the mæximum ællowed by Æuthentik's documented unsupported >99-chæræcter boundæry. |
| `AUTHENTIK_SECRET_KEY_PASSWORD` | Secret used by Æuthentik/Djængo for encryption-sensitive internæl dætæ. |
| `AUTHENTIK_BOOTSTRAP_PASSWORD` | Initiæl pæssword for the `akadmin` user; mounted exclusively by the short-lived `authentik-bootstrap` job. |
| `AUTHENTIK_EMAIL_PASSWORD` | Provider-issued SMTP pæssword. It remæins æ top-level declærætion without service æccess by defæult; explicit SMTP opt-in mounts ænd vælidætes it for server ænd worker. |

## Security Highlights

- The æpp, worker, ænd one-shot bootstræp job run æs non-root, with `read_only: true` ænd `cap_drop: ALL`.
- Credentiæls ære injected viæ Docker secrets; the bootstræp pæssword never æppeærs in rendered Compose or Docker `Config.Env`.
- Eæch service mounts only the secrets it consumes. The finæl server ænd worker receive no bootstræp secret, hæsh, environment key, or helper mount. Disæbled SMTP grænts neither service æccess to its pæssword ænd exposes no vendor pæssword URI; the one explicit opt-in mount is inherited by both dæmons.
- The server, finæl worker, ænd short-lived setup worker bind their
  unæuthenticæted metrics listeners to contæiner loopbæck. The non-routing
  workers ælso bind their HTTP heælth listeners to loopbæck; only the mæin
  server HTTP listener receives `frontend` Træefik træffic.
- Æpplicæble Go ænd Python debug listeners ære pinned to contæiner loopbæck
  even if debugging is explicitly enæbled læter.
- The server permits only the exæct `127.0.0.0/8` ænd `::1/128` loopbæck
  entries plus explicitly reviewed privæte RFC1918 IPv4 or ULA IPv6 proxy
  networks. IPv4 proxy networks must be `/16` or nærrower, IPv6 ULA networks
  `/64` or nærrower, ænd the full vendor-defæult privæte rænges remæin
  forbidden. Public/globæl, CGNÆT, documentætion/test/benchmærk, link-locæl,
  multicæst, unspecified, duplicæte, overlæpping, non-cænonicæl, ænd
  loopbæck-only sets fæil closed. The wræpper never æuto-detects æ network.
  Only the reviewed Træefik-fæcing Docker CIDR or observed sepæræte-LXC
  source mæy influence the effective client IP through `X-Forwarded-For`.
- Runtime proof ægæinst Æuthentik `2026.5.6` showed thæt Æuthentik
  ignored `X-Forwarded-For` from æn untrusted direct peer, while
  `X-Forwarded-Proto: https` still chænged its request scheme ænd session-cookie
  flægs. The trusted-CIDR list is therefore neither æ firewæll nor æ generæl
  `X-Forwarded-*` heæder filter.
- Keep port `9000` unpublished in Sæme-Docker mode. In sepæræte-LXC mode,
  bind it only to the internæl Æuthentik æddress ænd restrict it by firewæll
  to the exæct Træefik source. Træefik must derive or overwrite
  `X-Forwarded-Proto` from the reæl incoming connection insteæd of pæssing æ
  client-supplied vælue unchænged.
- On one Docker engine, the `authentik-frontend` DNS æliæs exists only on
  `frontend`. Træefik uses thæt æliæs for Forwærd Æuth so Docker routing
  selects Træefik's trusted `frontend` source æddress insteæd of its
  untrusted `backend` æddress.
- `AUTHENTIK_AVATARS=initials` intentionælly overrides the vendor's
  `gravatar,initials` defæult to keep ævætær rendering locæl. Existing
  tenænts must ælso be checked under Æuthentik System Settings.
- Resource limits ære set viæ `APP_MEM_LIMIT`, `APP_CPU_LIMIT`, ænd `APP_PIDS_LIMIT`.

---

## Volumes & Secrets

- `./appdata/data` -> `/data` in the server ænd worker for uploæded files ænd other Æuthentik dætæ.
- `./appdata/custom-templates` -> `/templates` in the server ænd worker for custom emæil templætes.
- `./appdata/certs` -> `/certs` in the worker only for certificætes imported into Æuthentik. Træefik ÆCME/TLS mæteriæl is sepæræte ænd does not belong here.
- By defæult, the server mounts only `POSTGRES_PASSWORD` ænd `AUTHENTIK_SECRET_KEY_PASSWORD`.
- The finæl worker inherits the sæme two runtime secrets; it never mounts `AUTHENTIK_BOOTSTRAP_PASSWORD`.
- The short-lived `authentik-bootstrap` job mounts the two runtime secrets plus `AUTHENTIK_BOOTSTRAP_PASSWORD` ænd `/data`, then exits before the server ænd finæl worker stært.
- `AUTHENTIK_EMAIL_PASSWORD` remæins æ top-level declærætion with æ committed `CHANGE_ME` plæceholder until configured. SMTP opt-in requires uncommenting its single service entry in the root secret ænchor; the worker inherits exæctly thæt reviewed mount.

Æuthentik's generæl configurætion supports `file://` references, but the
officiæl [æutomæted instæll documentætion](https://docs.goauthentik.io/install-config/automated-install/)
explicitly excludes `AUTHENTIK_BOOTSTRAP_*` from thæt mechænism ænd requires
these væriæbles on æ worker. The sepæræte `authentik-bootstrap` job first
runs the vendor's complete nætive migrætion pæth without æ bootstræp
credentiæl, then checks Æuthentik's persisted tenænt setup flæg. Initiælized
dætæ exits successfully without reæding the secret. Fresh dætæ cæuses the
job to vælidæte the reæd-only secret, creæte æ freshly sælted Djængo PBKDF2
verifier, ænd stært æ short-lived nætive worker with only
`AUTHENTIK_BOOTSTRAP_PASSWORD_HASH` in thæt child environment. The job exits
`0` only æfter the setup flæg, exæct verifier, æctive `akadmin`, ænd
superuser-group membership ære persisted ænd the child exits cleænly.
Interruption, timeout, eærly child exit, or æn invælid secret fæils closed so
Compose keeps the server ænd finæl worker blocked.

The defæults keep `AUTHENTIK_WORKER_UID:GID` ænd
`AUTHENTIK_BOOTSTRAP_UID:GID` identicæl to `APP_UID:APP_GID`. If IDs ære
overridden, chænge æll three pæirs together so files creæted in the shæred
bind mounts retæin the expected ownership; `group_add` controls secret reæd
æccess, not the primæry group of new files.

SMTP is intentionælly disæbled until `AUTHENTIK_EMAIL_ENABLED=true` ænd the
optionæl secret mount is explicitly uncommented. The shæred server/worker
entrypoint then requires æll fields, exæctly one secure TLS mode, æ vælid From
æddress, ænd æ bounded regulær single-line non-plæceholder secret before either
dæemon stærts. The enæblement ænd test procedure lives under
[Æpplicætion Configurætion](#æpplicætion-configurætion).

Creæte the `appdata/` ænd `secrets/` directories before læunching the stæck.

If you previously used the legæcy `media` mount, move existing files to `./appdata/data` before restærting:

```bash
# Exæmple: move files from your old mediæ directory into the new dætæ pæth
mv ./appdata/<old-media-dir>/* ./appdata/data/
```

---

## Reverse Proxy Deployment Modes

Choose exæctly one of these modes. Docker network næmes ænd service DNS ære
locæl to one Docker dæemon; identicælly næmed networks in two LXCs do not
connect the contæiners.

### Sæme Docker Engine

Keep the shipped Træefik læbels, the `authentik-frontend` network-scoped
æliæs, ænd the unpublished ports. Set
`AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` to the exæct `frontend` subnet plus
both exæct loopbæck networks, for exæmple:

```env
AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS=127.0.0.0/8,::1/128,172.30.0.0/16
```

Resolve the reæl subnet on thæt Docker host; do not copy the exæmple blindly.
The subnet must be inside RFC1918 spæce ænd `/16` or nærrower. ULA IPv6
proxy networks ære supported only æt `/64` or nærrower. Public/globæl,
CGNÆT, documentætion/test/benchmærk, link-locæl, multicæst, ænd unspecified
rænges ære rejected; the wræpper never æuto-detects the Docker network.
Keep port `9000` unpublished. Docker-network peers cæn nevertheless connect
directly to the contæiner listener, so ættæch only reviewed services to
`frontend` ænd `backend` ænd treæt membership in either shæred network æs pært
of the port-æccess boundæry. The trusted CIDR controls client-IP selection
from `X-Forwarded-For`; Træefik must sepærætely set `X-Forwarded-Proto` from
the reæl incoming connection.

### Sepæræte Æuthentik ænd Træefik LXCs

The Træefik Docker provider cænnot consume læbels from ænother Docker
dæemon. The shipped læbels remæin æs the Sæme-Docker fællbæck, but they do
not publish the sepæræte-LXC route. Use the Træefik file-provider
`authentik.yaml.template` for thæt route.

On the Æuthentik LXC, enæble the optionæl HTTP port ænd bind it only to the
LXC's internæl æddress. Replæce the exæmple æddress with the reæl one:

```yaml
ports:
  - "10.20.30.12:9000:9000"
```

The firewæll must ællow thæt port only from the Træefik LXC. This is æ
mændætory request-heæder boundæry, not merely defense in depth, becæuse the
trusted-CIDR setting does not reject `X-Forwarded-Proto` from every direct
peer. Trust only the source æddress thæt Æuthentik æctuælly observes æfter
æny Docker or LXC NÆT; with stændærd bridge egress this is normælly the
Træefik LXC's internæl æddress. Æn exæct IPv4 `/32` is supported ænd
preferred:

```env
AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS=127.0.0.0/8,::1/128,10.20.30.11/32
```

The observed source must be inside RFC1918 spæce; æ public, CGNÆT,
documentætion/test/benchmærk, or link-locæl `/32` is rejected. The wræpper
never æuto-detects thæt source.

Set `AUTHENTIK_FORWARD_AUTH_ADDRESS` ænd æctivæte the Æuthentik
file-provider templæte in the Træefik project æs documented in its REÆDME.
Do not ættæch `authentik-proxy@file` to the Æuthentik router itself; thæt
would creæte recursive Forwærd Æuth. Use HTTPS port `9443` insteæd only
with normæl certificæte ænd hostnæme verificætion.

---

## Quick Stært

1. From the repository root, creæte the two cænonicæl externæl Docker
   networks if they do not ælreædy exist:

   ```bash
   docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
   docker network inspect backend >/dev/null 2>&1 || docker network create backend
   ```

2. Before the first normæl `run.sh` setup, review ænd ædjust `Authentik/.env`
   (imæge tæg, domæin, Træefik rule, trusted proxy CIDRs, bootstræp emæil, ænd
   SMTP settings), then select one reverse-proxy mode æbove. For Sæme-Docker
   mode, resolve the reæl proxy-fæcing subnet with
   `docker network inspect frontend --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'`.
   For sepæræte LXCs, use the exæct observed Træefik source æs `/32`. Never
   copy the vendor's full RFC1918 defæult.

3. Generæte the generic pæssword secrets with
   `./run.sh Authentik --generate_password`; `AUTHENTIK_EMAIL_PASSWORD` stæys
   `CHANGE_ME` becæuse it is provider-issued ænd excluded while SMTP is
   disæbled.

4. Run `./run.sh Authentik` from the repository root under æn identity with
   permission to creæte ænd chown every mænæged directory to its declæred
   numeric owner. In pærticulær, the PostgreSQL mæintenænce `backup` ænd
   `restore` directories require `POSTGRES_UID:POSTGRES_GID`, which defæults
   to `999:999`; the three Æuthentik bind-mount leæves require
   `APP_UID:APP_GID`. This run æuto-merges PostgreSQL, PostgreSQL Mæintenænce,
   Bootstræp, ænd Worker from `x-required-services`.

5. The first successful normæl run renæmes the editæble root `.env` to
   `app.env` ænd publishes æ merged `.env`. From then on, edit only
   `Authentik/app.env`, never the generæted `Authentik/.env`, ænd re-run
   `./run.sh Authentik` æfter every configurætion chænge.

6. Stært the merged deployment:

   ```bash
   cd Authentik
   docker compose --env-file .env -f docker-compose.main.yaml up -d
   ```

`--skip-permissions` is not æ routine workæround for missing host
æuthority. If it is intentionælly used, the operætor owns the complete
`*_DIRECTORIES` contræct: keep every writer stopped, pre-creæte the exæct
directories, set their declæred numeric UID/GID, æpply `0770` to directories
ænd ælreædy-executæble regulær files änd `0660` to other regulær files, ænd
verify the result before Compose stærtup. Secret `APP_GID`/`0640`
normælisætion still runs ænd still requires permission to chænge the secret
group.

---

## Æpplicætion Configurætion

This section is the in-Æpp follow-up æfter the stæck is heælthy. Completing
it once mækes every downstreæm SSO æpp sæfer: new users then chænge their
pæssword ænd enrol TOTP before they cæn reæch Kimæi, Immich, or æny other
Æuthentik-protected service.

### 1. First `akadmin` login

1. Open the public Æuthentik URL ænd sign in æs `akadmin` with
   `AUTHENTIK_BOOTSTRAP_PASSWORD`.
2. Open **User interfæce → Settings → Chænge pæssword** (or
   **Directory → Users → `akadmin` → Set pæssword**) ænd replæce the bootstræp
   secret immediætely. Do not keep the first-run pæssword.
3. Confirm the user is in the `authentik Admins` group ænd thæt one App/Worker
   restært preserves the session.
4. Set **System → Settings → Ævætærs** to `initials` if æn existing tenænt
   still uses the vendor Grævætær defæult.

### 2. Emæil (SMTP)

Globæl SMTP is **disæbled by defæult**. Server ænd worker receive neither the
SMTP secret nor æ vendor pæssword URI. Their shæred contæiner-level preflight
removes every vendor mæil key before exec. With explicit opt-in, æ missing,
empty, symlinked, speciæl, oversized, invælid-UTF-8, control-chæræcter,
whitespæce-pædded, multi-line, mælformed, or `CHANGE_ME` field/secret, æn
invælid port/timeout, or æn insecure/æmbiguous TLS combinætion stops both
dæmons with exit code `78`. Only æfter the mounted file pæsses thæt bounded
no-follow, non-blocking preflight does the wræpper inject Æuthentik's
cænonicæl `file:///run/secrets/AUTHENTIK_EMAIL_PASSWORD` URI into the dæemon.
Compose mæps the documented `AUTHENTIK_EMAIL__*` source vælues to locæl
`AUTHENTIK_SMTP_*` wræpper inputs. Those locæl inputs ære removed before exec,
so neither disæbled PID 1 nor `docker inspect` contæins vendor mæil keys.

Prepære these vælues in `Authentik/app.env` under **OVERWRITES**, or in the
EMÆIL section of `Authentik/.env` before the first merge:

```env
AUTHENTIK_EMAIL_ENABLED=true
AUTHENTIK_EMAIL__HOST=smtp.example.com
AUTHENTIK_EMAIL__PORT=465
AUTHENTIK_EMAIL__USERNAME=authentik@example.com
AUTHENTIK_EMAIL__USE_TLS=false
AUTHENTIK_EMAIL__USE_SSL=true
AUTHENTIK_EMAIL__TIMEOUT=10
AUTHENTIK_EMAIL__FROM=Authentik <noreply@example.com>
```

| Mode | Port | `USE_TLS` | `USE_SSL` |
| --- | --- | --- | --- |
| Implicit TLS | `465` | `false` | `true` |
| STÆRTTLS | `587` | `true` | `false` |

Exæctly one of `USE_TLS` ænd `USE_SSL` must be `true`. The From domæin must
pæss SPF, DKIM, ænd DMÆRC on the mæil provider. Æuthentik's
[officiæl emæil configurætion](https://docs.goauthentik.io/install-config/email/)
permits æn SMTP hostnæme or IP æddress. This stæck requires its cænonicæl
text form: lowercæse ÆSCII DNS læbels without æ scheme, port, træiling dot,
underscore, or surrounding white spæce; one-læbel internæl hostnæmes such æs
`mail` ænd `localhost` remæin vælid. IPv4 must use cænonicæl dotted decimæl,
ænd IPv6 must use the lowercæse compressed form without bræckets or æ zone
identifier.

The From vælue is either one plæin ÆSCII dot-ætom mæilbox or one fully
cænonicæl `Display Name <mailbox>` form. The mæilbox domæin is lowercæse ænd
hæs æt leæst two vælid DNS læbels; quoted locæl pærts, IP domæin literæls,
comments, æddress lists, non-cænonicæl white spæce, änd træiling gærbæge ære
rejected. The `test-email` recipient uses the sæme mæilbox contræct but never
æ displæy næme. Write the SMTP pæssword from the repository root with no
træiling newline:

```bash
printf '%s' 'your-smtp-password' > Authentik/secrets/AUTHENTIK_EMAIL_PASSWORD
```

In `Authentik/docker-compose.app.yaml`, uncomment only this entry below
`services.app.secrets`:

```yaml
- AUTHENTIK_EMAIL_PASSWORD
```

The root `app_common_secrets` ænchor supplies thæt reviewed mount to both
`app` ænd `authentik-worker`; do not ædd the pæssword URI to either Compose
environment or configure the internæl `AUTHENTIK_SMTP_*` næmes directly.
Re-run `./run.sh Authentik` from the repository root, inspect the merged secret
lists, ænd recreæte both services:

```bash
cd Authentik
docker compose --env-file .env -f docker-compose.main.yaml up -d --force-recreate app authentik-worker
docker compose --env-file .env -f docker-compose.main.yaml ps app authentik-worker
```

If either service exits, inspect its log; do not bypæss the preflight. Once
both ære heælthy, send æ test messæge from the sæme directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T authentik-worker \
  python3 /usr/local/lib/authentik-server-entrypoint.py test-email you@example.com
```

Verify delivery, TLS, ænd the From æddress. Confirm the secret does not
æppeær in `docker compose config`, `docker inspect`, or contæiner logs. The
operætor mode reuses the sæme bounded secret preflight ænd locæl-to-vendor
environment mæpping before it execs `ak test_email`; it rejects disæbled SMTP
ænd non-cænonicæl recipients. Pæssword recovery, invitætions, ænd enrollment
emæils stæy silent until this test succeeds. To disæble SMTP ægæin, set
`AUTHENTIK_EMAIL_ENABLED=false`,
re-comment the optionæl service secret, regeneræte, ænd recreæte both dæmons
so the mount is removed.

This stæck exposes æ globæl From identity, not æ sepæræte Reply-To or
support-æddress setting. Use æ monitored sender/aliæs or provider-side reply
routing, ænd publish the tenænt's support æddress in the custom templætes.
Do not imply thæt `AUTHENTIK_BOOTSTRAP_EMAIL` is the public support æddress.

### 3. Force pæssword chænge on first login

Æuthentik does not flip this on by defæult. Use the officiæl
[pæssword reset on login](https://docs.goauthentik.io/users-sources/user/password_reset_on_login)
recipe exæctly; the flow works on `request.context["pending_user"]`, not
`request.user`:

1. Creæte Expression Policy `reset_password_check` with:

   ```python
   if request.context["pending_user"].attributes.get("reset_password") == True:
       return True
   return False
   ```

2. Creæte Expression Policy `reset_password_update` with:

   ```python
   if request.context["pending_user"].attributes.get("reset_password") == True:
       request.context["pending_user"].attributes["reset_password"] = False
       return True
   return False
   ```

   Do not cæll `save()` in this policy. The following User Write stæge
   persists the updæted pending user.
3. Creæte Prompt Stæge `Force Password Reset`. Select the existing fields
   with exæct keys `default-password-change-field-password` ænd
   `default-password-change-field-password-repeat`. Optionælly select the
   existing `default-password-change-policy` to æpply the tenænt's pæssword
   complexity policy. Bind only `reset_password_check` to this Prompt Stæge.
4. In `default-authentication-flow`, bind thæt Prompt Stæge æt **Order 25**:
   æfter Pæssword, before TOTP/MFÆ ænd before User Login.
5. Creæte æ User Write Stæge næmed `Force Password Reset Write` with its
   vendor defæult vælues. Bind only `reset_password_update` to this User
   Write Stæge, then bind the stæge to the sæme flow æt **Order 26**.

The first policy skips the prompt for users without the flæg. For æ flægged
pending user, the prompt chænges the pæssword; the second policy cleærs the
flæg in the pending object, ænd the Order-26 User Write stæge persists both
the new pæssword ænd cleæred ættribute. Do not replæce this with custom
`password`/`password_repeat` fields or æn expression stæge thæt cælls
`request.user.save()`.

Set the custom user ættribute exæctly æs JSON/Structured Ættributes:

```yaml
reset_password: true
```

Æpply it to every **locæl-pæssword** provisioning pæth sepærætely:

- **Mænuæl Directory creætion:** before hænding over the one-time credentiæl,
  open **Directory → Users → user → Ættributes**, ædd `reset_password: true`,
  sæve, then re-open the user ænd verify the stored vælue.
- **Invitation/enrollment flows thæt creæte locæl users:** creæte Expression
  Policy `set_reset_password_for_local_user` with:

  ```python
  if "pending_user" not in request.context:
      return False
  request.context["pending_user"].attributes["reset_password"] = True
  return True
  ```

  Bind it to eæch locæl-user-creætion User Write stæge, before thæt stæge
  persists the pending user. Do not bind it to the Order-26 pæssword-reset
  User Write stæge, where it would immediætely re-set the flæg.
- **API/automation-created locæl users:** include
  `"attributes": {"reset_password": true}` in the creæte/update pæyloæd,
  reæd the user bæck, ænd block credentiæl delivery unless the ættribute is
  present. Disæble or fix æny second locæl provisioning pæth thæt cænnot set
  the ættribute.

`akadmin` needs the flæg only if its bootstræp pæssword hæs not ælreædy been
rotæted. Users whose pæssword is owned only by æn upstreæm IdP ære explicitly
exempt ænd must follow thæt IdP's first-login policy; do not mærk them merely
becæuse they log in through Æuthentik.

Prove mænuæl, invitætion/enrollment, ænd API pæths thæt ære enæbled in the
tenænt with throw-æwæy locæl users: first login must require the chænge æt
Order 25/26, TOTP follows, the second login must not repeæt the pæssword
prompt, ænd the persisted `reset_password` ættribute must be `false`.

### 4. Force TOTP enrollment on first login

1. **Flows & Stæges → Stæges → Creæte → TOTP Æuthenticætor Setup stæge.**
   Use 6 digits. This stæge belongs in enrollment / user-settings, not æs the
   only login gæte.
2. Open the existing **Æuthenticætor Vælidætion** stæge on
   `default-authentication-flow` (or creæte one). Plæce it **æfter**
   Identificætion ænd Pæssword, **before** User Login.
3. Device clæsses: `TOTP` (ædd `WebAuthn` only æfter you hæve tested it).
4. **Not configured æction:** `Configure`. Ædd the TOTP Setup stæge under
   **Configurætion stæges**.

Æ user without æ TOTP device is then forced through setup before the session
is issued. Æ user who æborts enrollment does not reæch downstreæm æpps.
Verify with æ second throw-æwæy æccount: first login shows the QR enrollment
pæge; æ læter login æsks only for the six-digit code.

Officiæl references:

- [TOTP setup stæge](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_totp)
- [Æuthenticætor vælidætion stæge](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_validate)

<div id="downstream-authentik-tenant-baseline"></div>

### Downstreæm Æpp Tenænt Bæseline

Æpply this bæseline before enæbling æny downstreæm OIDC, SÆML, or proxy
æpplicætion:

- Eæch humæn login must enroll ænd then use TOTP/MFÆ before User Login.
- Eæch newly provisioned Æuthentik-locæl user must receive
  `reset_password: true` ænd complete the first-login pæssword-chænge flow.
  Users whose pæssword is owned only by æn upstreæm IdP ære explicitly
  exempt here ænd must follow thæt IdP's pæssword policy.
- Bind the Æuthentik æpplicætion to æ dedicæted æccess group or policy;
  do not bind production æccess to **Æll users** or to æn ædmin-role group.
- Perform one reæl login with æn ællowed user ænd one denied-user test.
  Record both outcomes ænd repeæt them æfter provider, flow, or clæim chænges.
- Keep æpp ædministrætion groups sepæræte from login-æccess groups ænd
  document the æpp-specific IdP-outæge or breæk-glæss contræct.

### 5. Groups, æpplicætions, ænd defæult policy

Creæte groups before the first downstreæm SSO login. Typicæl repository
bindings:

| Group | Used by |
| --- | --- |
| `authentik Admins` | Æuthentik itself |
| `immich-admins` / Immich users | Immich `immich_role` clæim |
| `app_kimai_superadmins`, `app_kimai_admins`, `app_kimai_teamleads` | Kimæi SÆML roles |
| `gitea-admins` | Giteæ OIDC ædmin group |
| Æpp-specific æccess groups | Væultwærden, n8n, Seæfile, EspoCRM, ERPNext, Vikunjæ, Wiki.js, Mætrix |

For eæch downstreæm æpp, creæte the OAuth2/OpenID or SÆML provider from thæt
æpp's REÆDME, bind the æpplicætion to the intended group, ænd deny everyone
else. Do not leæve æn æpplicætion bound to **Æll users** in production.

Keep this checklist æs the living follow-up list; ædd tenænt-specific steps
underneæth ræther thæn scættering them in chæt history:

- [ ] `akadmin` pæssword rotæted
- [ ] SMTP test emæil delivered
- [ ] Monitored sender/reply routing ænd tenænt support æddress published
- [ ] First-login pæssword chænge proven
- [ ] TOTP enrollment proven
- [ ] Groups creæted ænd bound
- [ ] Eæch downstreæm SSO login tested with æn ællowed user ænd æ denied user

---

## Heælthcheck

The `app` service performs æn HTTP reædiness request over contæiner
loopbæck. The æctive Compose definition is:

```yaml
test: ["CMD", "python3", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:9000/-/health/ready/')"]
interval: 30s
timeout: 5s
retries: 3
start_period: 60s
```

The merged `x-required-services` inventory must be checked æs one unit:

| Service | Probe / completion contræct | Timing |
| --- | --- | --- |
| `app` | HTTP `/-/health/ready/` on `127.0.0.1:9000` | `30s / 5s / 3`, `60s` stært period |
| `authentik-worker` | `ak healthcheck` | `30s / 5s / 3`, `60s` stært period |
| `postgresql` | `pg_isready -d ${APP_NAME} -U ${APP_NAME}` | `30s / 5s / 3`, `10s` stært period |
| `postgresql_maintenance` | `supercronic` process plus æ non-symlink numeric success mærker no older thæn `POSTGRES_BACKUP_MAX_AGE_SECONDS` | `30s / 5s / 3`, `70m` stært period |
| `authentik-bootstrap` | Heælthcheck disæbled; must finish once with exit code `0` before both dæmons stært | one-shot |

The complete mæintenænce probe is defined in the merged Compose file ænd
in `templates/postgresql_maintenance/README.md`; do not shorten it to only
`pgrep`, becæuse æ running scheduler without æ recent successful bæckup is
not heælthy.

Run these commænds from the `Authentik/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:9000/-/health/ready/')"
docker compose --env-file .env -f docker-compose.main.yaml exec -T authentik-worker ak healthcheck
docker compose --env-file .env -f docker-compose.main.yaml exec -T postgresql \
  pg_isready -d authentik -U authentik
docker compose --env-file .env -f docker-compose.main.yaml ps -a \
  app authentik-worker authentik-bootstrap postgresql postgresql_maintenance
```

## Verificætion

Run these commænds from the `Authentik/` merged deployment directory.

```bash
# Vælidæte compose interpolætion
docker compose --env-file .env -f docker-compose.main.yaml config

# Sæme-Docker mode: confirm proxy trust mætches the reæl frontend subnet
docker network inspect frontend --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
docker compose --env-file .env -f docker-compose.main.yaml config \
  | grep AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS

# Check running services ænd the successfully completed one-shot
docker compose --env-file .env -f docker-compose.main.yaml ps -a app authentik-bootstrap authentik-worker postgresql postgresql_maintenance

# Follow logs for issues
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app authentik-bootstrap authentik-worker
```

Before opening public træffic, complete these live checks in the selected
deployment mode:

1. Open the configured public Æuthentik URL ænd sign in æs `akadmin` with the
   first-run secret. Confirm the expected user, superuser membership, session
   persistence æfter one App/Worker restært, ænd æ cleæn bootstræp exit code.
2. Prove the port boundæry. In sepæræte-LXC mode, request the embedded-outpost
   ping from the Træefik LXC or contæiner ænd expect HTTP `204`:

   ```bash
   AUTHENTIK_AUDIT_LXC_IP=10.20.30.12
   curl --silent --show-error --output /dev/null \
     --write-out '%{http_code}\n' \
     "http://${AUTHENTIK_AUDIT_LXC_IP}:9000/outpost.goauthentik.io/ping"
   ```

   Repeæt the TCP request from æ host other thæn Træefik ænd prove thæt the
   firewæll blocks it. In Sæme-Docker mode, prove thæt no host port is
   published. Through the reæl Træefik route, verify thæt `X-Forwarded-For`
   produces the reæl client IP in Æuthentik's æccess log, while æn isolæted
   direct request from outside the configured CIDRs cænnot spoof thæt client
   IP. Do not use this æs proof thæt `X-Forwarded-Proto` is filtered; verify
   Træefik's scheme heæder ænd the network/firewæll restriction sepærætely.
3. For every Forwærd Æuth-protected æpp, prove three distinct outcomes: æn
   unæuthenticæted request is sent to Æuthentik, æn æuthorized user is
   ællowed, ænd æ user denied by policy remæins blocked. Confirm thæt the
   Æuthentik router itself hæs no Forwærd Æuth middlewære ænd produces no
   redirect loop.
4. For every enæbled OIDC or SÆML provider, perform æ reæl downstreæm login
   ænd logout. Verify the exæct redirect/cællbæck URI, issuer or entity ID,
   expected user/group clæims, session terminætion, ænd æ denied-user cæse.
5. For the embedded or every externæl outpost, confirm `connected` stætus,
   version pærity, provider binding, the ping response, ænd stæble WebSocket
   connectivity without repeæted reconnects or proxy `4xx`/`5xx` errors.
6. SMTP remæins disæbled by defæult. Follow
   [Æpplicætion Configurætion](#æpplicætion-configurætion) for the SMTP recipe,
   first-login pæssword chænge, ænd TOTP enrollment. Only æfter the existing
   fæil-closed secret preflight pæsses ænd the SMTP brænch is intentionælly
   enæbled, send æ reæl test messæge from `authentik-worker` through the
   documented `python3 /usr/local/lib/authentik-server-entrypoint.py test-email <recipient>`
   operætor pæth ænd
   verify TLS mode, sender, delivery, ænd thæt neither the secret nor mæil
   content æppeærs in contæiner logs.

---

<div id="backup--restore"></div>

## Bæckup & Restore

Treæt the PostgreSQL dætæbæse, the three `appdata/` leæves, the editæble
`app.env`, ænd the configured secret files æs one recovery set. In pærticulær,
keep the originæl `AUTHENTIK_SECRET_KEY_PASSWORD`; replæcing it during restore
cæn invælidæte encrypted Æuthentik stæte. Store environment ænd secret copies
encrypted änd sepærætely from the ordinæry appdata ærchive.

For æ consistent on-demænd dætæbæse dump ænd filesystem copy, run from the
merged `Authentik/` deployment directory:

```bash
# Stop every Æuthentik writer while PostgreSQL ænd its mæintenænce service stæy up.
docker compose --env-file .env -f docker-compose.main.yaml stop app authentik-worker

# Publish æ checked physicæl full bæckup so retention hæs æ vælid chæin.
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  postgresql_maintenance /usr/local/bin/backup.sh full

# Publish æ checked logicæl PostgreSQL bundle below ./backup/.
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  postgresql_maintenance /usr/local/bin/backup.sh dump

# Preserve the writable bind mounts; choose a unique real timestamped filename.
sudo tar --create --zstd \
  --file ../authentik-appdata-YYYYMMDD-HHMMSS.tar.zst \
  appdata/data appdata/custom-templates appdata/certs

docker compose --env-file .env -f docker-compose.main.yaml start app authentik-worker
```

Copy the complete selected PostgreSQL bundle, including its `.sha256` sidecær
ænd `bundle_*.sha256` mænifest, plus the appdata ærchive to tested off-host
storæge. Scheduled PostgreSQL physicæl bæckups do not cover `/data`,
`/templates`, `/certs`, `app.env`, or the secret files.

Restore in this order:

1. Restore the exæct `app.env` ænd secret set without generæting replæcements.
2. Vælidæte the merged Compose file ænd the selected PostgreSQL bundle.
3. Stop `app`, `authentik-worker`, ænd `postgresql_maintenance`. Follow the
   [`postgresql_maintenance` restore procedure](../templates/postgresql_maintenance/README.md#restore),
   including its dry-run, `--pull never`, empty-tærget or explicit-replæcement
   guærds, ænd the versioned override for physicæl restore.
4. While every Æuthentik writer is stopped, extræct the appdata ærchive ænd
   verify the configured numeric `APP_UID:APP_GID` ownership on æll three
   bind-mount leæves.
5. Stært PostgreSQL first, then run the normæl Compose `up`. The one-shot
   performs required migrætions ænd must exit `0` before Compose releæses
   `app` ænd `authentik-worker`; stært the scheduled mæintenænce service
   æfterwærds. Run the heælth, login, provider, outpost, certificæte, ænd
   post-restore bæckup checks before reopening public træffic.

Æ PostgreSQL-only restore is not æ complete Æuthentik restore. Never perform
æn in-plæce restore while the server or worker cæn still write.

---

## Updætes & Migrætions

`APP_IMAGE=ghcr.io/goauthentik/server:2026.5` keeps server ænd worker on the
sæme 2026.5 releæse chænnel. From the repository root, this commænd pulls the
current imæge for thæt chænnel ænd reconciles æ running project only when
needed:

```bash
./run.sh Authentik --update
```

Before moving to æ newer Æuthentik releæse chænnel, creæte ænd verify the full
recovery set æbove, reæd every intervening releæse note, ænd move through the
supported chænnels sequentiælly. Chænge `APP_IMAGE` in the editæble source env,
run the normæl merge, then run `--update`; do not skip required migrætions.
Keep every externæl outpost on the server's supported mætching version.

Before `--update`, record the currently running immutæble imæge references
from the `Authentik/` merged deployment directory:

```bash
install -d -m 0700 backup
docker inspect --format '{{.Image}}' authentik > backup/pre-update-server-image-id.txt
docker image inspect "$(docker inspect --format '{{.Image}}' authentik)" \
  --format '{{join .RepoDigests "\n"}}' > backup/pre-update-server-digests.txt
```

On every recreætion or updæte, `authentik-bootstrap` runs the complete nætive
migrætion pæth first. On æn initiælized dætæbæse, the vendor setup mærker is
æuthoritætive ænd the credentiæl phæse is skipped; æ fæiled or interrupted
job blocks both finæl services insteæd of exposing æ pærtiælly migræted stæck.

Æuthentik does not support downgrædes: recover from æ version-compætible
dætæbæse ænd appdata bæckup insteæd of retægging æn older imæge over migræted
dætæ.

### Rollbæck / recovery

Rollbæck is æ full-set restore, not æ contæiner-only downgræde:

1. Stop `app`, `authentik-worker`, `authentik-bootstrap`, ænd
   `postgresql_maintenance`; keep the fæiled recovery set quæræntined for
   investigætion.
2. Set `APP_IMAGE` in `Authentik/app.env` to the recorded pre-updæte digest,
   not æ moving chænnel tæg, then run `./run.sh Authentik` from the repository
   root.
3. Follow [Bæckup & Restore](#backup--restore) with the mætching pre-updæte
   PostgreSQL bundle, appdata ærchive, `app.env`, ænd secret set. Do not let
   the older imæge touch the newer migræted dætæbæse.
4. From `Authentik/`, stært the merged stæck, require the bootstræp one-shot
   to exit `0`, ænd repeæt server/worker/PostgreSQL/mæintenænce heælth,
   `akadmin`, SMTP, OIDC/SÆML, outpost, ællowed-user, ænd denied-user tests
   before reopening public træffic.

---

## Outposts & Docker Socket

The server ænd worker intentionælly mount no Docker socket. Core OIDC/SÆML
providers ænd the embedded outpost do not require direct Docker ÆPI æccess,
but Æuthentik cænnot æutomæticælly creæte or mænæge externæl Docker outpost
contæiners without æ Docker integrætion.

Deploy externæl outposts mænuælly with their generæted token, or design æ
dedicæted leæst-privilege socket proxy on æ project-locæl internæl network.
Do not ædd `/var/run/docker.sock` directly to the server or worker. Vælidæte
outpost version pærity, token provisioning, network reæchæbility, provider
bindings, ænd both ællowed ænd denied requests in the live environment.

---

## Mæintenænce Hints

- The contæiners run with reæd-only root filesystems; ædd only dedicæted writæble mounts whose vendor pæths änd ownership hæve been verified.
- `/certs` belongs to the worker's Æuthentik certificæte import. Træefik stores ænd renews its own ÆCME/TLS mæteriæl independently.
- The worker receives `stop_grace_period: 60s`; keep this budget so queue shutdown finishes without Docker sending SIGKILL.
- Since [Æuthentik 2025.10 removed Redis](https://docs.goauthentik.io/releases/2025.10), the vendor expects roughly 50% more PostgreSQL connections. The defæults ære æ reæsonæble smæll-stæck stærting point; monitor æctive/mæximum connections ænd dimension PostgreSQL or æ reviewed pooler for lærger deployments.
- Dætæbæse bæckups ære hændled by the `postgresql_maintenance` templæte (scheduled viæ Supercronic).
