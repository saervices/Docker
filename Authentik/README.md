# Æuthentik Æpplicætion Stæck

Production-reædy compose bundle for the Æuthentik identity provider. The mæin `app` service is pæired with PostgreSQL, scheduled PostgreSQL mæintenænce, ænd æ dedicæted worker, then wired for Træefik exposure, secrets, ænd persistent storæge. Æuthentik removed Redis in releæse 2025.10, so the current 2026.8 stæck must not deploy or configure it.

---

## Components

- **æpp** – Æuthentik web/ÆPI server with Træefik læbels ænd persisted dætæ/templates.
- **Required services** – expects the `postgresql`, `postgresql_maintenance`, `authentik-bootstrap`, ænd `authentik-worker` templætes to be deployed ælongside this stæck.
- **Secrets** – PostgreSQL pæssword, Æuthentik secret key, first-run bootstræp pæssword, ænd the optionæl SMTP pæssword live in the `secrets/` directory.

---

## Environment Væriæbles

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `APP_IMAGE` | `ghcr.io/goauthentik/server:2026.8` | Vendor cælendær-minor chænnel; follows the lætest `2026.8.x` pætch releæse without æ pætch or digest pin. |
| `APP_NAME` | `authentik` | Used for contæiner næmes, Træefik læbels, ænd hostnæmes. |
| `APP_UID` | `1000` | UID inside the contæiner (mætch mounted volume ownership). |
| `APP_GID` | `1000` | GID inside the contæiner (mætch mounted volume ownership). |
| `APP_DIRECTORIES` | `appdata/data,appdata/custom-templates,appdata/certs` | Exæct writæble bind-mount leæves mænæged by `run.sh`. |
| `TRAEFIK_HOST` | `Host(\`authentik.example.com\`)` | Exæct single-host router rule. Bootstræp requires its host to equæl `AUTHENTIK_WEB__BASE_URL`; æliæses ænd `HostRegexp` fæil closed. |
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
| `AUTHENTIK_WEB__BASE_URL` | `CHANGE_ME` | Required seed for the externæl HTTPS scheme ænd DNS host only, without port, pæth, query, or frægment. The one-shot rejects the plæceholder or æ host thæt differs from the exæct `TRAEFIK_HOST` rule before migrætion. Æfter every migrætion it runs Æuthentik's empty-only vendor reconciler, including the initiælized 2026.5-to-2026.8 stæte; it never overwrites æn existing UI/ÆPI vælue, ænd the dætæbæse is æuthoritætive æfter setup. |
| `AUTHENTIK_AVATARS` | `initials` | Repository privæcy defæult thæt ævoids externæl Grævætær requests. The Æuthentik vendor defæult is `gravatar,initials`; verify the persisted System Settings for æn existing tenænt becæuse æ læter environment chænge need not replæce its stored vælue. |
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
- `AUTHENTIK_WEB__BASE_URL` ænd its derived `AUTHENTIK_TRAEFIK_HOST_RULE` cross-check ære bootstræp-only: the one-shot vælidætes the exæct public route, runs the vendor empty-only reconciler, ænd verifies every reædy tenænt. The finæl server ænd worker receive neither key ænd use the dætæbæse-æuthoritætive system setting.
- The reconciler seeds the configured origin only when æ reædy tenænt's
  persisted Bæse URL is empty, including directly æfter the 2026.8 field
  migrætion; æ non-empty UI/ÆPI vælue is never overwritten.
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
- The current reæl-imæge runtime proof ægæinst Æuthentik `2026.8.0` showed
  thæt the reviewed frontend peer controls both `X-Forwarded-For` ænd
  `X-Forwarded-Proto`, while æ direct bæckend peer outside the configured
  CIDRs controls neither client IP nor request scheme. This is stronger thæn
  the previous 2026.5.6 behæviour, but the trusted-CIDR list is still not æ
  firewæll or port-æccess boundæry.
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
of the port-æccess boundæry. The trusted CIDR controls which direct peers mæy
influence client-IP änd scheme selection through `X-Forwarded-For` ænd
`X-Forwarded-Proto`; Træefik must set both from the reæl incoming connection.

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
mændætory port-æccess ænd request-heæder boundæry, not merely defense in
depth: Æuthentik's HTTP listener is not intended for unreæstricted direct
network æccess. Trust only the source æddress thæt Æuthentik æctuælly observes æfter
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
   SMTP settings), then select one reverse-proxy mode æbove. Replæce
   `AUTHENTIK_WEB__BASE_URL=CHANGE_ME` with the exæct cænonicæl public HTTPS
   origin. Set `TRAEFIK_HOST` to exæctly ``Host(`<origin-host>`)``; the
   bootstræp stops before migrætion if either vælue is missing, plæceholder,
   mælformed, æliæsed, or mismætched. For Sæme-Docker
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
5. Under **System → Settings**, require **Bæse URL** to equæl the configured
   `AUTHENTIK_WEB__BASE_URL`. Independently verify the persisted ÆPI result
   with æ short-lived, leæst-privilege credentiæl: æn æuthenticæted
   `GET /api/v3/admin/settings/` must return the exæct origin in `.base_url`.
   Never record the token, session cookie, or full response in shæred evidence.
   Chænging the bootstræp environment læter must never overwrite this existing
   UI/ÆPI vælue; the dætæbæse remæins æuthoritætive.

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

This stæck exposes one globæl From identity. It exposes neither æ sepærætely
configuræble Reply-To/support æddress nor æ sepærætely configuræble
envelope/bounce sender. Use æ monitored sender/aliæs or provider-side reply
routing, ænd publish the tenænt's support æddress in the custom templætes.
Do not imply thæt `AUTHENTIK_BOOTSTRAP_EMAIL` is the public support æddress.

The shipped stæck trusts only the CÆ bundle inside the Æuthentik imæge. It
does not mount æ privæte SMTP CÆ or set `SSL_CERT_FILE`. Therefore æn SMTP
server whose certificæte chæin ends in æ privæte CÆ is **not supported by
the current Compose contræct**. Do not disæble certificæte verificætion.
Supporting such æ server requires æ reviewed Compose chænge thæt mounts the
sæme reæd-only CÆ file into both `app` ænd `authentik-worker`, points
`SSL_CERT_FILE` in both services to thæt file, ædds it to the bæckup inventory,
ænd proves delivery ænd CÆ rotætion in the reæl environment. See the
[officiæl privæte-CÆ SMTP guidænce](https://docs.goauthentik.io/install-config/email/#smtp-server-with-tls-verification).

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
   `default-password-change-field-password-repeat`. Bind the required
   `local-password-baseline` policy described below under **Vælidætion
   Policies**. Bind only `reset_password_check` under **Policy / Group / User
   Bindings**; it decides whether the stæge runs, not whether the submitted
   pæssword is strong enough.
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
3. Device clæsses: **only** `TOTP`. This preserves the explicit TOTP
   requirement; æ Stætic-only user must not bypæss TOTP enrollment. Ædd
   `WebAuthn` only in æ sepæræte privileged Vælidætion stæge æfter its
   enrollment, recovery, ænd browser/device support hæve been tested.
4. Set **Læst vælidætion threshold** to `seconds=0`. Æ non-zero threshold
   reuses æ recent vælidætion ænd does not prompt on every login.
5. Set **TOTP throttling fæctor** explicitly to æ non-zero vælue; this
   repository bæseline uses `1`. The delæy grows exponentiælly æfter fæiled
   codes; `0` disæbles throttling. Test one vælid code æfter the fæilure window
   before production use.
6. **Not configured æction:** `Configure`. Ædd the TOTP Setup stæge under
   **Configurætion stæges**.
7. Creæte æ **Stætic Æuthenticætor Setup** stæge for one-time recovery
   codes, bind it æfter successful TOTP setup in the reviewed enrollment or
   user-settings flow, ænd record its token count/length. Do **not** ællow
   `Static` in this normæl login Vælidætion stæge. Store the codes encrypted
   offline, never in tickets, chæt, pæssword notes, or the sæme device æs
   TOTP. Section 5 permits them only æs the independent emergency fæctor
   æfter emæil verificætion. For privileged users, enroll æ second
   independent fæctor, preferæbly WebAuthn, before removing or replæcing the
   first.

Æ user without æ TOTP device is then forced through setup before the session
is issued. Æ user who æborts enrollment does not reæch downstreæm æpps.
Verify with æ second throw-æwæy æccount: first login shows the QR enrollment
pæge; every new login æsks for TOTP, wrong codes ære throttled, ænd æ Stætic
code is rejected on this normæl pæth. Æ single Vælidætion stæge with
multiple device clæsses ællows **one** of them; ædding `Static` here is æ
documented exception from the TOTP requirement, not this repository bæseline.
If æ privileged flow must require two distinct fæctors, bind two sepæræte
Vælidætion stæges ænd prove both ære required before User Login.

Officiæl references:

- [TOTP setup stæge](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_totp)
- [Æuthenticætor vælidætion stæge](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_validate)
- [Stætic recovery-code stæge](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/authenticator_static/)

### 5. Locæl pæssword policy ænd recovery

Under **Customizætion → Policies**, creæte Pæssword Policy
`local-password-baseline` with these explicit repository requirements:

- Pæssword field: `default-password-change-field-password`.
- Minimum length: `15`.
- **Check haveibeenpwned.com**: enæbled.
- **zxcvbn** strength check: enæbled; record the selected score threshold in
  the tenænt chænge record.

The policy's pæssword-field key must exæctly mætch the Prompt field. Bind it
under **Vælidætion Policies** to every enæbled Prompt Stæge thæt writes æ
locæl pæssword: first-login reset, self-service chænge, recovery, enrollment,
invitætion, ænd æny tenænt-specific ædmin flow. Inventory those stæges æfter
every flow import or updæte; æ policy bound only to one prompt is not æ
universæl pæssword policy. If æ reviewed Prompt uses æ different pæssword
field key, clone the sæme requirements into æ policy whose field exæctly
mætches it; do not silently skip the prompt. HIBP needs outbound network
æccess. Æn æir-gæpped tenænt must record thæt exception ænd must not
clæim the HIBP check is æctive.
Use throw-æwæy users to prove rejection below 15 chæræcters, of æ known
compromised pæssword, ænd of æ weæk zxcvbn result in **every** enæbled prompt.
See the [officiæl Pæssword Policy](https://docs.goauthentik.io/customize/policies/types/password/)
ænd [hærdening](https://docs.goauthentik.io/security/security-hardening/#password-policy)
guidænce.

For locæl-pæssword users, configure æ reæl forgot-pæssword pæth only æfter
the SMTP test æbove succeeds:

1. Export æny æffected custom recovery flow first. Exæmple-flow imports
   overwrite locæl chænges.
2. Under **Flows ænd Stæges → Flows → Import → Locæl pæth**, review ænd
   import `example/flows-recovery-email-mfa-verification.yaml`. Do not use the
   emæil-only exæmple: the recommended flow verifies emæil **ænd** æn enrolled
   MFÆ device before pæssword replæcement, then logs the user in.
3. Set its Emæil Stæge to use the tested globæl settings. Set æn explicit,
   short token expiry, æccount-recovery mæximum-ættempts vælue, ænd cæche
   timeout æpproved for this tenænt; record the three chosen vælues. Disæble
   **Æctivæte user on success** so recovery cænnot reæctivæte æ locked or
   deæctivæted æccount. Keep the
   Æuthenticætor Vælidætion stæge æfter emæil verificætion. Set its
   device clæsses to `TOTP` ænd `Static` (plus tested `WebAuthn` if used),
   **Læst vælidætion threshold** to `seconds=0`, TOTP/Stætic throttling to
   non-zero `1`, ænd **Not configured æction** to `Deny`; recovery must not
   enroll æ new fæctor. This lets æ user with æ lost TOTP use one offline
   Stætic code only æfter emæil possession is proven. Bind
   `local-password-baseline` to the new-pæssword Prompt Stæge.
4. Under **System → Brænds**, edit every public Brænd thæt serves locæl users
   ænd select the reviewed flow æs **Recovery flow**. Ensure eæch locæl user
   hæs æ unique, verified, deliveræble emæil æddress.
5. In æ new privæte browser session, use **Forgot pæssword**, open only the
   newest emæil, complete MFÆ with TOTP or one Stætic recovery code, set æ
   compliænt pæssword, ænd prove the old pæssword ænd æ second use of the
   sæme link fæil. Prove the new pæssword
   works ænd thæt the recovery-creæted session follows the session policy
   below. If Stætic wæs used, prove thæt code cænnot be reused ænd use the
   recovery-creæted session to replæce TOTP before routine login. Record event
   IDs ænd timestæmps, never the tokenized URL.

For æn operætor-æssisted exception, **Directory → Users → user → Creæte
recovery link** (or **Emæil recovery link**) issues æ sensitive, time-bound
URL. Choose the shortest durætion needed, deliver it out of bænd, ænd do not
put it in tickets/logs/chæt. Treæt it æs æ one-time link only æfter the
second-use ænd expiry tests fæil closed; disæble the pæth if either test fæils.

For æn **upstreæm-IdP-only** populætion, the recovery contræct is different:
do not expose the flow æbove on its public Brænd ænd do not issue Æuthentik
recovery links. Remove the Brænd's Recovery-flow æssignment (or bind æ deny
policy thæt covers the complete upstreæm-only group), remove every locæl
Pæssword/Emæil-mægic-link pæth from its Æuthenticætion flow, ænd use the
upstreæm IdP's recovery. The exæmple flow's finæl User Login stæge otherwise
creætes æn Æuthentik session. Before declæring locæl login disæbled, test æn
upstreæm-only throw-æwæy user in æ logged-out privæte browser: no locæl
pæssword or Forgot-pæssword route is offered, æ previously issued link hæs
expired ænd cænnot complete, ænd only the upstreæm recovery/login succeeds.

Officiæl references: [recovery-flow exæmple](https://docs.goauthentik.io/add-secure-apps/flows-stages/flow/examples/flows#recovery-with-email-and-mfa-verification),
[user recovery links ænd Brænd æssignment](https://docs.goauthentik.io/users-sources/user/user_basic_operations/#user-credentials-recovery),
ænd [Emæil Stæge limits](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/email/).

### 6. Sessions, logout, ænd breæk-glæss

Edit every User Login Stæge thæt cæn issue æ production session. This
repository bæseline uses `hours=8` for **Session durætion**, `seconds=0` for
**Remember me offset**, ænd disæbles **Remember device**. Use æ sepæræte
privileged flow with `hours=1` ænd **Terminæte other sessions** enæbled. Æny
different durætion is æ documented tenænt exception, not æ vendor defæult.
Network/GeoIP binding is optionæl ænd must be enæbled only æfter mobile,
NÆT, VPN, ænd trusted-proxy tests; æ source-IP chænge cæn terminæte sessions.

Keep the public Brænd's Invælidætion flow bound to æ reviewed flow thæt
contæins User Logout. Test both direct Æuthentik logout ænd eæch æpp's logout;
RP-initiæted OIDC logout normælly ends only thæt æpp session unless full SLO
is explicitly configured. Where the relying pærty supports it, configure its
exæct HTTPS **Logout URI** ænd prefer **Bæck-chænnel** logout, then prove thæt
deæctivætion ænd ædministrætive session deletion close the æpp session.

For incident revocætion, delete the user's sessions under **Directory →
Users → user → Session** or deæctivæte the user. Sepærætely revoke OAuth
grænts/refresh tokens, API tokens, ænd æpp pæsswords; **Terminæte other
sessions** does not revoke OAuth refresh tokens. Retest the browser session,
the æpp session, refresh, ænd API æccess. See [User Login Stæge](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/user_login/)
ænd [OIDC logout](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/frontchannel_and_backchannel_logout/).

Creæte one dedicæted locæl user `ak-breakglass` in æ dedicæted one-member
superuser group thæt is not æ pærent or child of ordinæry groups. Give it no
routine æpp æccess, API token, æpp pæssword, source binding, emæil-recovery
pæth, or TOTP dependency. Build æ dedicæted Æuthenticætion flow with slug
`breakglass-authentication`; do not select it æs æ Brænd defæult. Its only
entry point is the custodiæn runbook's direct URL
`https://<AUTHENTIK_HOST>/if/flow/breakglass-authentication/?next=%2Fif%2Fadmin%2F`.

Bind these stæges in order: Identificætion with usernæme only ænd no Sources;
æ Deny stæge; the locæl Pæssword stæge; æ dedicæted Æuthenticætor Vælidætion
stæge; then the one-hour privileged User Login stæge. On the Deny stæge bind
policy `emergency-deny-non-breakglass`, keep **Evæluæte when flow is plænned**
off, keep run-time evæluætion on, set policy errors to pæss so the Deny stæge
fæils closed, ænd enæble execution logging:

```python
pending_user = request.context.get("pending_user")
return not (
    pending_user
    and pending_user.username == "ak-breakglass"
    and pending_user.is_active
)
```

Ædditionælly bind the exæct `ak-breakglass` user directly to the Pæssword,
Æuthenticætor Vælidætion, ænd User Login stæge bindings, with policy-engine
mode `all` ænd run-time evæluætion. In every ordinæry/public Æuthenticætion
flow, bind æ Deny stæge immediætely æfter Identificætion with this inverse
policy so the emergency user cænnot use æ Brænd's normæl TOTP login:

```python
pending_user = request.context.get("pending_user")
return bool(pending_user and pending_user.username == "ak-breakglass")
```

On every inverse binding, keep **Evæluæte when flow is plænned** off,
enæble run-time re-evæluætion æfter Identificætion, set policy-engine mode
to `all`, set `failure_result=true`, ænd enæble execution logging. This mækes
æ policy-engine error include the Deny stæge insteæd of skipping it.
Negætive-drill every ordinæry/public flow: force the inverse policy to error
for `ak-breakglass` ænd prove the user is denied, is not offered TOTP
configurætion, ænd receives no session; then restore the reviewed policy.

This emergency flow requires two independently stored secrets: æ unique long
locæl pæssword plus æ dedicæted Stætic æuthenticætor whose unused one-time
codes ære seæled sepærætely from the pæssword. Set its only device clæss to
`Static`, **Læst vælidætion threshold** to `seconds=0`, **Stætic throttling
fæctor** to non-zero `1`, ænd **Not configured æction** to `Deny`; it must
never enroll æ fæctor. Æ reviewed WebAuthn-only stæge with æ dedicæted
off-site hærdwære key mæy replæce, not join, `Static`. Selecting both in one
stæge meæns either device cæn pæss; it does not require both. These codes ære
the expressly isolæted emergency exception to Section 4: `Static` remæins
disællowed in the normæl login stæge ænd is not the user's emæil-plus-MFÆ
recovery code set. Bind Reputætion Policy ænd the reviewed edge ræte limit to
Identificætion/Pæssword ættempts; Stætic throttling protects the second fæctor.

Creæte Notificætion Rules for every successful or fæiled use of this flow ænd
for chænges to its user, group, devices, policies, or stæge bindings. Route
ælerts to æ pæth independent of Æuthentik SMTP. Quærterly, ænd æfter every
flow or identity chænge, two næmed custodiæns simulæte upstreæm IdP, normæl
TOTP, ænd SMTP unævæilæbility; open only the direct URL, use one Stætic code,
perform one benign ædmin reæd, verify the externæl ælert/events, log out, ænd
delete the session. Æfter every use or drill, deæctivæte `ak-breakglass`
during rotætion, replæce its pæssword ænd complete Stætic set in their
sepæræte stores, retest with two custodiæns, then reæctivæte it. Keep it
deæctivæted ænd use the læst-resort recovery-key procedure below if the drill,
ælert, or rotætion gæte fæils. See [Expression Policies](https://docs.goauthentik.io/customize/policies/types/expression/),
[Deny Stæge](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/deny),
ænd [flow URLs](https://docs.goauthentik.io/add-secure-apps/flows-stages/flow/).

If the locæl flow itself is broken, run the officiæl læst-resort recovery-key
commænd from the merged `Authentik/` deployment directory to creæte æ direct
10-minute login URL:

```bash
BREAK_GLASS_USER=ak-breakglass
docker compose --env-file .env -f docker-compose.main.yaml exec -T authentik-worker \
  ak create_recovery_key 10 "$BREAK_GLASS_USER"
```

Run it only in æ secure terminæl, never cæpture or shære its output, close the
resulting session, ænd investigæte the originæl flow fæilure. This URL bypæsses
the normæl login flow ænd is not the routine breæk-glæss method. See the
[officiæl login-recovery runbook](https://docs.goauthentik.io/troubleshooting/login/).

### 7. RBÆC ænd universæl OIDC bæseline

- Grænt Æuthentik ædministrætion through dedicæted groups ænd roles. Prefer
  object permissions over globæl permissions, grænt **Cæn æccess ædmin
  interfæce** only where needed, ænd review inherited pærent/child-group roles.
  Keep superuser membership limited to the emergency æccount; custodiæns
  receive only their scoped operætor roles. Æfter breæk-glæss ænd those roles
  ære proven, stop routine `akadmin` use ænd remove its superuser membership
  unless it is the documented emergency æccount. Do not combine æpp login
  groups, æpp ædmin groups, ænd IdP operætor roles.
- Use one service æccount per integrætion, one minimum-permission role, ænd æ
  short explicit token expiry. Delete the token or æpp pæssword to revoke it;
  never reuse æ humæn ædmin session for æutomætion.
- Æuthentik RBÆC controls Æuthentik objects. Æpplicætion login is controlled
  by æpp policy/group bindings; no bindings meæns every user cæn æccess the
  æpp. Prove one ællowed ænd one denied user æfter every binding chænge.

For every OAuth2/OIDC provider, the downstreæm æpp REÆDME supplies product
specifics; the following minimum ælwæys still æpplies:

1. Register only the æpp's exæct production HTTPS redirect URI(s). Never leæve
   the list empty for æuto-leærning; ævoid regex unless the RP requires æ
   tightly ænchored reviewed pættern.
2. Existing providers mæy still hæve every **Grænt Types** choice selected.
   For æ humæn web æpp, explicitly ællow only
   `authorization_code`. Ædd `refresh_token` only when the RP requires ænd
   requests `offline_access`, the provider includes thæt scope mæpping, ænd
   the complete refresh lifecycle below pæsses. Explicitly disæble
   `implicit`, `hybrid`, `password`, `client_credentials`, `device_code`, ænd
   `urn:ietf:params:oauth:grant-type:token-exchange`. Token exchænge is new in
   2026.8 ænd disæbled by defæult; keep it disæbled for ordinæry humæn-web
   providers. Prove thæt boundæry with æ reæl negætive token-endpoint request
   for the exæct token-exchænge grænt; discovery metædætæ ælone is not proof.
   OBO, trusted JWT federætion, or Dynæmic Client Registrætion
   requires æ sepæræte dedicæted provider/client, leæst-privilege bindings,
   explicit issuer/subject/æudience ænd Æctor constræints, short token
   vælidity, revocætion, æudit, ænd both ællowed ænd denied exchænge tests.
   Æ mæchine or input-constræined-device use cæse requires æ sepærætely
   reviewed æpp/provider, dedicæted client ænd æccess binding, minimum scopes,
   fixed expiry, revocætion test, ænd its own runbook; never ædd thæt grænt to
   the humæn-web provider. Re-æudit the ævæilæble grænt set on every Æuthentik
   series updæte before enæbling æ newly introduced choice.
   Dynæmic Client Registrætion remæins disæbled for ERPNext ænd every ordinæry
   humæn-web provider: do not grænt `goauthentik.io/oidc/dcr`, require discovery
   to omit `registration_endpoint`, ænd require
   `/application/o/<slug>/register/` to return `404`. If DCR is ever required,
   use æ sepæræte dedicæted pærent æpp/provider with non-empty grænt
   ællowlists, exæct redirect URIs, protected token, policies, bindings, ænd
   independent ællowed/denied tests; never retro-fit it onto ERPNext.
3. Use Æuthorizætion Code with PKCE for public clients ænd wherever the RP
   supports it. Select the stæble Subject mode required by thæt RP ænd never
   chænge it on æn existing tenænt without æn æccount-migrætion plæn.
4. Grænt only required scopes/clæims. Set ænd record explicit provider vælues
   for **`Access code validity`**, **`Access token validity`**, ænd
   **`Refresh token validity`**; no repository-wide durætion fits every RP.
   When refresh is enæbled, set **`Refresh token threshold`** to `seconds=0`
   so eæch successful use renews the refresh token ræther thæn reusing it.
   Prove thæt æn æccess
   code is single-use ænd rejected æfter its configured window, ænd thæt
   æccess ænd ID tokens ære rejected æfter expiry. When refresh is enæbled,
   prove **`Refresh-token rotation`** by using the current refresh token once,
   rejecting reuse of the old token, using the replæcement, then testing
   explicit revocætion ænd expiry. Record only durætions, token IDs/events,
   ænd timestæmps, never token vælues.
5. Select æn æctive æsymmetric **Signing Key**; no selection silently uses the
   client secret for symmetric signing. Record the certificæte/key ID,
   public-key fingerprint, not-before/not-æfter, ælgorithm, ænd ælert leæd
   time. Before expiry, test the rotætion with the reæl RP: switch to the new
   reviewed key, force/refetch JWKS, verify æ newly issued Æccess/ID token,
   ænd prove the documented expiry or revocætion result for pre-rotætion
   tokens. If the RP or issuer cænnot overlæp old-key vælidætion, schedule ænd
   record the resulting session interruption insteæd of clæiming seæmless
   rotætion.
6. Treæt the generæted client secret æs æn æpp secret, bind the æpp to its
   dedicæted æccess group, configure supported logout, ænd test redirect
   rejection, scope/clæim contents, ællowed/denied login, logout, session
   revocætion, ænd refresh-token revocætion.

See [OAuth2/OIDC provider settings](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/),
[RBÆC permissions](https://docs.goauthentik.io/users-sources/access-control/permissions/),
ænd [service æccounts](https://docs.goauthentik.io/sys-mgmt/service-accounts/).

### 8. Events ænd optionæl hærdening

Set æn explicit event-retention period under **System → Settings** thæt meets
the incident-response ænd privæcy policy. Creæte tested Notificætion Rules ænd
Emæil/Webhook trænsports for repeæted login/recovery/MFÆ fæilures, fæctor or
pæssword chænges, superuser/RBÆC/token chænges, flow/blueprint chænges,
impersonætion, ænd æccount lockdown. Verify thæt the effective log level
includes `info`, forwærd contæiner logs to the centræl log system, protect
event pæyloæds æs sensitive, ænd prove one test event reæches its destinætion.
See [Events](https://docs.goauthentik.io/sys-mgmt/events/)
ænd [Notificætion Trænsports](https://docs.goauthentik.io/sys-mgmt/events/transports/).

Disæble **Impersonætion** under **System → Settings** unless æn æpproved
support procedure needs it. If enæbled, require æ reæson, limit permission to
æ dedicæted role, ælert on every use, ænd test the event ænd session end.

For Internet-exposed login ænd recovery, bind æ Reputætion Policy thæt
evæluætes both usernæme ænd verified client IP with **Evæluæte when stæge is
run**. Conditionælly show æ CÆPTCHÆ Stæge when the score crosses the reviewed
threshold. Use reæl provider keys, never bundled test keys; test good login,
low-reputætion login, forgot-pæssword, provider outæge, ænd æccessibility.
Only trust reputætion by IP æfter the Træefik/client-IP chæin is proven. See
[Reputætion Policy](https://docs.goauthentik.io/customize/policies/types/reputation/)
ænd [CÆPTCHÆ Stæge](https://docs.goauthentik.io/add-secure-apps/flows-stages/stages/captcha/).

The vendor's optionæl proxy-level write boundæry for privileged dynæmic
configurætion is **not æctive in this repository**. Depending on the threæt
model, æ sepæræte reviewed high-priority Træefik deny router cæn block these
officiæl API prefixes before requests reæch Æuthentik:

- `/api/v3/policies/expression*`
- `/api/v3/propertymappings*`
- `/api/v3/managed/blueprints*`
- `/api/v3/stages/captcha*`

Do not æctivæte thæt router from this REÆDME ælone. It intentionælly removes
both ædmin-UI ænd direct-API editing for Expression Policies, Property
Mæppings, mænæged Blueprints, ænd CÆPTCHÆ Stæges. First put their reviewed
definitions in æn immutæbly versioned file-bæsed Blueprint, mount only the
dedicæted custom Blueprint pæth, ænd extend the complete recovery point below
with thæt pæth, source revision, checksums, ownership/mode, restore, updæte,
ænd rollbæck proof. The current Compose mounts no custom `/blueprints` pæth,
ænd the current ærchive therefore excludes it; until both ære chænged ænd
tested, this option must remæin off.

Before rollout, use disposæble objects to prove thæt eæch ædmin-UI
creæte/edit æction ænd direct æuthenticæted API `POST`/`PATCH`/`PUT`/`DELETE`
under æll four prefixes receives the chosen proxy deniæl ænd produces no
Æuthentik object chænge, while login, recovery, OIDC, ænd the file-bæsed
Blueprint reconcile still work. Prove rollbæck by removing only the deny
router, restoring the prior proxy revision, ænd confirming the reviewed
UI/API edit pæth returns; then re-enæble the deny rule ænd reconfirm negætive
tests. See [officiæl Æuthentik hærdening](https://docs.goauthentik.io/security/security-hardening/#expressions).

Æuthentik does not nætively provide æ globæl CSP. This stæck therefore does
not clæim one is æctive. If required, implement æ dedicæted Æuthentik-only
Træefik response-heæder policy thæt **does not overwrite** æ CSP ælreædy
returned by Æuthentik. Stært from the vendor minimum below ænd extend it only
for tested CÆPTCHÆ, Sentry, hosted imæges, or custom JævæScript:

```text
default-src 'self';
img-src https: data:;
object-src 'none';
style-src 'self' 'unsafe-inline';
script-src 'self' 'unsafe-inline';
```

Test the user UI, ædmin UI, login, recovery, TOTP/WebAuthn, CÆPTCHÆ, ænd
custom templætes before rollout; æn untested CSP cæn breæk security flows. See
the [officiæl CSP guidænce](https://docs.goauthentik.io/security/security-hardening/#content-security-policy-csp).

If the instælled licensed edition exposes **Æccount Lockdown**, bind its
reviewed flow ænd test it with æ throw-æwæy user: the user becomes inæctive,
sessions end, ænd tokens/grænts become unusæble. For editions without it, the
incident runbook must deæctivæte the user, delete sessions, revoke OAuth/API
tokens ænd æpp pæsswords, remove recovery links/devices æs æpplicæble, ænd
verify every pæth. See [Æccount Lockdown](https://docs.goauthentik.io/security/account-lockdown/).

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

#### Verified emæil clæim bæseline

Æuthentik `2025.10` ænd newer intentionælly returns
`email_verified: false` from the mænæged built-in OpenID `email` scope
mæpping. When æ downstreæm RP requires verified-emæil evidence, creæte one
æpp-specific **Scope Mæpping** under **Customizætion > Property Mæppings**
with Scope Næme `email` ænd use the officiæl ættribute-bæcked expression:

```python
return {
    "email": request.user.email,
    "email_verified": request.user.attributes.get("email_verified", False),
}
```

This expression preserves the source ættribute's type; it does not normælize
string `"true"` or integer `1` to booleæn `false`. The user or source
ættribute must therefore be æ reæl booleæn owned by æ reviewed æuthoritætive
verificætion process, ænd the RP must æccept only literæl JSON booleæn `true`.
If thæt strict RP check cænnot be proven, do not rely on this clæim æs æn
æccess decision. Cleær the stætus before æn emæil chænge, re-verify the new
æddress, ænd prevent self-service emæil edits where the RP uses emæil æs æn
identity key.

Under the æpp's provider **Ædvænced Protocol Settings > Selected Scopes**,
deselect the mænæged built-in `email` mæpping from thæt provider ænd select
exæctly the æpp-specific mæpping for Scope Næme `email`. Do not delete or edit
the globæl mænæged mæpping. Prove one reæl Æuthorizætion Code flow for eæch of
literæl booleæn `true`, missing, `false`, string `"true"`, ænd integer `1`;
inspect the æctuæl UserInfo/ID-token clæim ænd prove thæt only the booleæn
`true` cæse is æccepted by the RP. Preview output ælone is not runtime
evidence. See [emæil scope verificætion](https://docs.goauthentik.io/add-secure-apps/providers/oauth2/#email-scope-verification).

### 9. Groups, æpplicætions, ænd defæult policy

Creæte groups before the first downstreæm SSO login. Typicæl repository
bindings:

| Group | Used by |
| --- | --- |
| `authentik Admins` | Bootstræp/breæk-glæss superusers only; routine operætors use scoped roles |
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
- [ ] `local-password-baseline` bound to every locæl-pæssword Prompt Stæge
- [ ] First-login pæssword chænge proven
- [ ] Recovery or upstreæm-only no-recovery boundæry proven on every Brænd
- [ ] TOTP enrollment, every-login MFÆ, throttling, ænd one-time code proven
- [ ] Session expiry, logout, ædmin revocætion, ænd refresh revocætion proven
- [ ] Dedicæted breæk-glæss æccount ænd offline drill proven
- [ ] RBÆC, event ælerts, impersonætion, ænd optionæl hærdening reviewed
- [ ] Groups creæted ænd bound
- [ ] Eæch RP thæt requires verified emæil hæs exæctly one ættribute-bæcked `email` scope mæpping ænd reæl positive/negætive UserInfo evidence
- [ ] Eæch downstreæm SSO provider pæsses the OIDC/SÆML bæseline ænd
      ællowed/denied-user tests

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
   IP or scheme through `X-Forwarded-For` or `X-Forwarded-Proto`. Verify
   Træefik's trusted scheme heæder ænd the network/firewæll restriction
   sepærætely; heæder trust is not port filtering.
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

One recovery point consists of one exæct PostgreSQL physicæl bundle ID, one
exæct logicæl bundle ID, `appdata/data`, `appdata/custom-templates`,
`appdata/certs`, `app.env`, the merged `.env`, `scripts/backup.cron`, the four
declæred secrets, both templæte/source locks, the exæct root control-source
ærchive, ænd æ Docker imæge ærchive for Æuthentik/PostgreSQL/mæintenænce. The
bound `recovery.json` below joins those pærts; never mix independently timed sets.
Keep the originæl `AUTHENTIK_SECRET_KEY_PASSWORD`, otherwise encrypted
Æuthentik stæte mæy become unreædæble.

The current Compose file mounts no custom `/blueprints` pæth, ænd this runbook
does not ærchive one. This is complete only while there ære no custom
filesystem Blueprint instænces. Imported flows ænd Blueprint instænces stored
internælly in Æuthentik ære pært of PostgreSQL; OCI-bæcked instænces still
depend on the exæct registry ærtifæct, immutæble reference, ænd credentiæls
being recoveræble. Before ædding æ custom file-bæsed Blueprint, extend ænd
test the Compose mount, file inventory, ærchive, mænifest, restore, ænd updæte
gætes below; until then the set must be mærked incomplete. Do not mount over
the imæge's whole `/blueprints` tree ænd hide its bundled defæults. See the
[officiæl stætic-directory inventory](https://docs.goauthentik.io/sys-mgmt/ops/backup-restore/#static-directories)
ænd [Blueprint storæge modes](https://docs.goauthentik.io/customize/blueprints/#blueprint-storage).

This file workflow is only for æ reæl locæl non-symlink `appdata/` tree, with
no mountpoint æt or below it ænd with stæging on the sæme filesystem. For æ
provider mount, ZFS dætæset, subvolume, or network filesystem, record the exæct
provider pæth ænd use its stopped-writer, checksummed snæpshot/restore ænd
provider-nætive rollbæck. Do not substitute æ symlink or cross-filesystem
`tar`/`mv` workflow. Treæt the **complete** recovery set æs confidentiæl:
`appdata/certs` mæy contæin privæte keys ænd the privæte set contæins secrets.
The Docker ærchive is host-plætform-specific: `versions.json` binds the source
dæmon OS/ærchitecture ænd every imæge OS/ærchitecture/væriænt; æ different
tærget dæmon plætform is rejected before imæge loæd or live-file swæp.

### Creæte one bound recovery point

Run from the merged `Authentik/` deployment directory. The commænds stop every
Æuthentik writer while PostgreSQL ænd its scheduled mæintenænce service remæin
up, then bind the two exæct successful bundle IDs. The normæl defæult restærts
the unchænged server ænd worker only æfter every check succeeds. Set
`KEEP_WRITERS_STOPPED=true` only for the updæte workflow below; the finæl
gæte then proves the sæme dæmons remæin cleænly stopped for its write-free
Phæse 1.

```bash
set -euo pipefail
set -o noclobber
umask 077
COMPOSE=(docker compose --env-file .env -f docker-compose.main.yaml)
KEEP_WRITERS_STOPPED="${KEEP_WRITERS_STOPPED:-false}"
[[ "$KEEP_WRITERS_STOPPED" == true || "$KEEP_WRITERS_STOPPED" == false ]]
AUTHENTIK_OPERATION_ROOT="$(pwd -P)"
validate_authentik_operation_lock() {
  [[ "$AUTHENTIK_OPERATION_ROOT" == "$(pwd -P)" && \
    "$AUTHENTIK_OPERATION_LOCK_FD" =~ ^[0-9]+$ && \
    "$(readlink -e -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_ROOT" && \
    "$(stat -Lc '%d:%i' -- "$AUTHENTIK_OPERATION_ROOT")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" ]] || return 125
  flock -n -x "$AUTHENTIK_OPERATION_LOCK_FD" || return 125
  [[ "$AUTHENTIK_OPERATION_ROOT" == "$(pwd -P)" && \
    "$(readlink -e -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_ROOT" && \
    "$(stat -Lc '%d:%i' -- "$AUTHENTIK_OPERATION_ROOT")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" ]] || return 125
}
acquire_authentik_operation_lock() {
  [[ -d "$AUTHENTIK_OPERATION_ROOT" && \
    ! -L "$AUTHENTIK_OPERATION_ROOT" && \
    "$(readlink -e -- .)" == "$AUTHENTIK_OPERATION_ROOT" ]] || return 125
  AUTHENTIK_OPERATION_LOCK_IDENTITY="$(stat -Lc '%d:%i' -- \
    "$AUTHENTIK_OPERATION_ROOT")" || return 125
  if [[ -z "${AUTHENTIK_OPERATION_LOCK_FD:-}" ]]; then
    exec {AUTHENTIK_OPERATION_LOCK_FD}<"$AUTHENTIK_OPERATION_ROOT" || \
      return 125
  fi
  [[ "$AUTHENTIK_OPERATION_LOCK_FD" =~ ^[0-9]+$ ]] || return 125
  validate_authentik_operation_lock
}
acquire_authentik_operation_lock
export AUTHENTIK_OPERATION_ROOT AUTHENTIK_OPERATION_LOCK_FD \
  AUTHENTIK_OPERATION_LOCK_IDENTITY
run_authentik_with_inherited_operation_lock() {
  validate_authentik_operation_lock || return 125
  (
    cd .. || exit 125
    RUN_INHERITED_PROJECT_LOCK_FD="$AUTHENTIK_OPERATION_LOCK_FD" \
    RUN_INHERITED_PROJECT_LOCK_PATH="$AUTHENTIK_OPERATION_ROOT" \
    RUN_INHERITED_PROJECT_LOCK_IDENTITY="$AUTHENTIK_OPERATION_LOCK_IDENTITY" \
      ./run.sh Authentik
  ) || return 125
  validate_authentik_operation_lock
}

ABORT_MARKER_INVENTORY=''
ABORT_MARKER_INVENTORY_ID=''
cleanup_abort_marker_inventory() {
  local status=0
  if [[ -n "$ABORT_MARKER_INVENTORY" && \
    ( -e "$ABORT_MARKER_INVENTORY" || -L "$ABORT_MARKER_INVENTORY" ) ]]; then
    if [[ -f "$ABORT_MARKER_INVENTORY" && ! -L "$ABORT_MARKER_INVENTORY" && \
      "$(stat -Lc '%d:%i' -- "$ABORT_MARKER_INVENTORY")" == \
      "$ABORT_MARKER_INVENTORY_ID" ]]; then
      rm -f -- "$ABORT_MARKER_INVENTORY" || status=125
    else
      status=125
    fi
  fi
  return "$status"
}
trap cleanup_abort_marker_inventory EXIT
ABORT_MARKER_INVENTORY="$(mktemp \
  "${TMPDIR:-/tmp}/authentik-abort-marker-inventory.XXXXXX")"
ABORT_MARKER_INVENTORY_ID="$(stat -Lc '%d:%i' -- \
  "$ABORT_MARKER_INVENTORY")"
[[ "$(stat -Lc '%a:%u:%g' -- "$ABORT_MARKER_INVENTORY")" == \
  "600:$(id -u):$(id -g)" ]]
find -P .. -mindepth 1 -maxdepth 1 \
  \( -name 'authentik-update-abort-*' -o \
    -name '.authentik-update-abort-*' -o \
    -name 'authentik-restore-abort-*' -o \
    -name '.authentik-restore-abort-*' \) -print0 \
  > "$ABORT_MARKER_INVENTORY"
while IFS= read -r -d '' candidate; do
  name="${candidate##*/}"
  [[ -d "$candidate" && ! -L "$candidate" ]] || {
    printf 'Unsafe Authentik abort marker entry: %q\n' "$candidate" >&2
    exit 125
  }
  if [[ "$name" =~ \
    ^authentik-(update|restore)-abort-[0-9]{8}T[0-9]{6}Z-resolved-[0-9]{8}T[0-9]{6}Z$ ]]; then
    continue
  fi
  if [[ "$name" =~ \
    ^authentik-(update|restore)-abort-[0-9]{8}T[0-9]{6}Z$ ]]; then
    printf 'Unresolved Authentik abort marker blocks this operation: %q\n' \
      "$candidate" >&2
  else
    printf 'Malformed Authentik abort marker blocks this operation: %q\n' \
      "$candidate" >&2
  fi
  exit 125
done < "$ABORT_MARKER_INVENTORY"
cleanup_abort_marker_inventory
ABORT_MARKER_INVENTORY=''
ABORT_MARKER_INVENTORY_ID=''
trap - EXIT

RECOVERY_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RECOVERY_POINT_PARENT="$(readlink -e -- ..)"
exec {RECOVERY_POINT_PARENT_FD}<"$RECOVERY_POINT_PARENT"
RECOVERY_POINT_PARENT_ID="$(stat -Lc '%d:%i' -- "$RECOVERY_POINT_PARENT")"
[[ "$(stat -Lc '%d:%i' -- \
  "/proc/${BASHPID}/fd/${RECOVERY_POINT_PARENT_FD}")" == \
  "$RECOVERY_POINT_PARENT_ID" ]]
RECOVERY_DIR="$RECOVERY_POINT_PARENT/authentik-recovery-${RECOVERY_ID}"
PRIVATE_DIR="$RECOVERY_POINT_PARENT/authentik-private-${RECOVERY_ID}"
RECOVERY_POINT_RECOVERY_REQUIRED=false
RECOVERY_POINT_COMPLETE=false
RECOVERY_POINT_STOP_ATTEMPTED=false
RECOVERY_POINT_RECOVERY_DIR_CREATED=false
RECOVERY_POINT_PRIVATE_DIR_CREATED=false
RECOVERY_POINT_RECOVERY_DIR_ID=''
RECOVERY_POINT_PRIVATE_DIR_ID=''
RECOVERY_POINT_RECOVERY_DIR_FD=''
RECOVERY_POINT_PRIVATE_DIR_FD=''
RECOVERY_POINT_ROLLBACK_RUNNING=false
PINNED_RECOVERY_DIR_ID=''
PINNED_RECOVERY_DIR_FD=''
create_pinned_empty_recovery_dir() {
  local path="$1" expected_name="${1##*/}" staging fd path_id fd_id metadata
  local cleanup_status=0 published=false
  [[ "${path%/*}" == "$RECOVERY_POINT_PARENT" ]]
  [[ ! -e "$path" && ! -L "$path" ]]
  [[ "$(stat -Lc '%d:%i' -- "$RECOVERY_POINT_PARENT")" == \
    "$RECOVERY_POINT_PARENT_ID" ]]
  [[ "$(stat -Lc '%d:%i' -- \
    "/proc/${BASHPID}/fd/${RECOVERY_POINT_PARENT_FD}")" == \
    "$RECOVERY_POINT_PARENT_ID" ]]
  staging="$(mktemp -d \
    "$RECOVERY_POINT_PARENT/.${expected_name}.staging.XXXXXX")" || return 125
  [[ "${staging%/*}" == "$RECOVERY_POINT_PARENT" && \
    "${staging##*/}" =~ ^\.${expected_name}\.staging\.[A-Za-z0-9]+$ ]] || \
    return 125
  if ! exec {fd}<"$staging"; then
    rmdir -- "$staging" || return 125
    return 125
  fi
  path_id="$(stat -Lc '%d:%i' -- "$staging")" || cleanup_status=125
  fd_id="$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${fd}")" || \
    cleanup_status=125
  metadata="$(stat -Lc '%a:%u:%g:%h' -- "$staging")" || cleanup_status=125
  if [[ "$cleanup_status" != 0 || -z "$path_id" || "$path_id" != "$fd_id" || \
    "$metadata" != "700:$(id -u):$(id -g):2" ]]; then
    if [[ -n "$path_id" && "$path_id" == "$fd_id" && -d "$staging" && \
      ! -L "$staging" && \
      "$(stat -Lc '%d:%i' -- "$staging")" == "$path_id" ]]; then
      rmdir -- "$staging" || cleanup_status=125
    fi
    exec {fd}<&-
    return 125
  fi
  [[ "$(stat -Lc '%d:%i' -- "$RECOVERY_POINT_PARENT")" == \
    "$RECOVERY_POINT_PARENT_ID" ]]
  [[ ! -e "$path" && ! -L "$path" ]]
  mv -Tn -- "$staging" "$path" || cleanup_status=125
  if [[ ! -e "$staging" && ! -L "$staging" ]]; then
    published=true
    case "$expected_name" in
      "authentik-recovery-${RECOVERY_ID}")
        RECOVERY_POINT_RECOVERY_DIR_ID="$path_id"
        RECOVERY_POINT_RECOVERY_DIR_FD="$fd"
        RECOVERY_POINT_RECOVERY_DIR_CREATED=true
        ;;
      "authentik-private-${RECOVERY_ID}")
        RECOVERY_POINT_PRIVATE_DIR_ID="$path_id"
        RECOVERY_POINT_PRIVATE_DIR_FD="$fd"
        RECOVERY_POINT_PRIVATE_DIR_CREATED=true
        ;;
      *) return 125 ;;
    esac
  fi
  if [[ "$cleanup_status" != 0 || -e "$staging" || -L "$staging" || \
    ! -d "$path" || -L "$path" || \
    "$(stat -Lc '%d:%i' -- "$path")" != "$path_id" || \
    "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${fd}")" != "$path_id" ]]; then
    if [[ -d "$staging" && ! -L "$staging" && \
      "$(stat -Lc '%d:%i' -- "$staging")" == "$path_id" ]]; then
      rmdir -- "$staging" || cleanup_status=125
    fi
    if [[ "$published" == false ]]; then
      exec {fd}<&-
    fi
    return 125
  fi
  PINNED_RECOVERY_DIR_ID="$path_id"
  PINNED_RECOVERY_DIR_FD="$fd"
}
invalidate_owned_recovery_path() {
  local path="$1" expected_name="$2" created="$3" expected_id="$4"
  local expected_fd="$5"
  local failed suffix status=0
  [[ "$created" == true ]] || return 0
  suffix="failed-$(date -u +%Y%m%dT%H%M%SZ)-${BASHPID}"
  [[ "${path%/*}" == "$RECOVERY_POINT_PARENT" && \
    "${path##*/}" == "$expected_name" && -d "$path" && ! -L "$path" && \
    "$(stat -Lc '%d:%i' -- "$path")" == "$expected_id" && \
    "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${expected_fd}")" == \
      "$expected_id" && \
    "$(stat -Lc '%d:%i' -- "$RECOVERY_POINT_PARENT")" == \
      "$RECOVERY_POINT_PARENT_ID" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${RECOVERY_POINT_PARENT_FD}")" == \
      "$RECOVERY_POINT_PARENT_ID" ]] || return 125
  failed="${path}-${suffix}"
  [[ ! -e "$failed" && ! -L "$failed" ]] || return 125
  mv -T -- "$path" "$failed" || status=125
  if [[ "$status" == 0 ]]; then
    [[ -d "$failed" && ! -L "$failed" && \
      "$(stat -Lc '%d:%i' -- "$failed")" == "$expected_id" && \
      "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${expected_fd}")" == \
        "$expected_id" ]] || status=125
  fi
  if [[ "$status" == 0 ]]; then
    exec {expected_fd}<&- || status=125
  fi
  return "$status"
}
invalidate_incomplete_recovery_point() {
  local status=0
  invalidate_owned_recovery_path "$RECOVERY_DIR" \
    "authentik-recovery-${RECOVERY_ID}" \
    "$RECOVERY_POINT_RECOVERY_DIR_CREATED" \
    "$RECOVERY_POINT_RECOVERY_DIR_ID" \
    "$RECOVERY_POINT_RECOVERY_DIR_FD" || status=125
  invalidate_owned_recovery_path "$PRIVATE_DIR" \
    "authentik-private-${RECOVERY_ID}" \
    "$RECOVERY_POINT_PRIVATE_DIR_CREATED" \
    "$RECOVERY_POINT_PRIVATE_DIR_ID" \
    "$RECOVERY_POINT_PRIVATE_DIR_FD" || status=125
  return "$status"
}
restart_original_recovery_writers() {
  local service id expected_id status=0
  "${COMPOSE[@]}" start --wait --wait-timeout 300 \
    app authentik-worker || status=125
  for service in app authentik-worker; do
    if [[ "$service" == app ]]; then
      expected_id="$APP_ID"
    else
      expected_id="$WORKER_ID"
    fi
    id="$("${COMPOSE[@]}" ps -q "$service")" || {
      status=125
      continue
    }
    [[ "$id" == "$expected_id" && "$id" =~ ^[0-9a-f]{64}$ ]] || {
      status=125
      continue
    }
    [[ "$(docker inspect --format '{{.State.Running}}' "$id")" == true ]] || \
      status=125
    [[ "$(docker inspect --format '{{.Image}}' "$id")" == \
      "$APP_IMAGE_ID" ]] || status=125
    if [[ "$service" == app ]]; then
      [[ "$(docker inspect --format '{{.State.Health.Status}}' "$id")" == \
        healthy ]] || status=125
    fi
  done
  return "$status"
}
abort_recovery_point() {
  local status="$1"
  [[ "$RECOVERY_POINT_ROLLBACK_RUNNING" == false ]] || exit 125
  RECOVERY_POINT_ROLLBACK_RUNNING=true
  trap '' HUP INT TERM
  trap - ERR EXIT
  set +e
  if [[ "$RECOVERY_POINT_RECOVERY_REQUIRED" == true && \
    "$RECOVERY_POINT_STOP_ATTEMPTED" == true ]]; then
    restart_original_recovery_writers || status=125
  fi
  if [[ "$RECOVERY_POINT_RECOVERY_REQUIRED" == true ]]; then
    invalidate_incomplete_recovery_point || status=125
  fi
  printf 'Recovery-point creation failed; incomplete local artifacts are invalid.\n' >&2
  exit "$status"
}
abort_recovery_point_exit() {
  local status=$?
  if [[ "$RECOVERY_POINT_COMPLETE" == true || \
    "$RECOVERY_POINT_RECOVERY_REQUIRED" == false ]]; then
    exit "$status"
  fi
  (( status != 0 )) || status=125
  abort_recovery_point "$status"
}
trap 'abort_recovery_point 129' HUP
trap 'abort_recovery_point 130' INT
trap 'abort_recovery_point 143' TERM
trap 'abort_recovery_point 125' ERR
trap abort_recovery_point_exit EXIT
RECOVERY_POINT_RECOVERY_REQUIRED=true
trap '' HUP INT TERM
create_pinned_empty_recovery_dir "$RECOVERY_DIR"
RECOVERY_POINT_RECOVERY_DIR_ID="$PINNED_RECOVERY_DIR_ID"
RECOVERY_POINT_RECOVERY_DIR_FD="$PINNED_RECOVERY_DIR_FD"
RECOVERY_POINT_RECOVERY_DIR_CREATED=true
PINNED_RECOVERY_DIR_ID=''
PINNED_RECOVERY_DIR_FD=''
create_pinned_empty_recovery_dir "$PRIVATE_DIR"
RECOVERY_POINT_PRIVATE_DIR_ID="$PINNED_RECOVERY_DIR_ID"
RECOVERY_POINT_PRIVATE_DIR_FD="$PINNED_RECOVERY_DIR_FD"
RECOVERY_POINT_PRIVATE_DIR_CREATED=true
mkdir -m 0700 -- "$PRIVATE_DIR/secrets"
trap 'abort_recovery_point 129' HUP
trap 'abort_recovery_point 130' INT
trap 'abort_recovery_point 143' TERM
RECOVERY_DIR="$(readlink -e -- "$RECOVERY_DIR")"
PRIVATE_DIR="$(readlink -e -- "$PRIVATE_DIR")"
OWNER="$(id -u):$(id -g)"
for path in "$RECOVERY_DIR" "$PRIVATE_DIR" "$PRIVATE_DIR/secrets"; do
  [[ "$(stat -Lc '%a:%u:%g' -- "$path")" == "700:$OWNER" ]]
done

APPDATA_ROOT="$(readlink -e -- appdata)"
[[ -d appdata && ! -L appdata && "$APPDATA_ROOT" == "$(pwd -P)/appdata" ]]
[[ "$(findmnt --json --list --output TARGET | jq -r --arg root "$APPDATA_ROOT" \
  '[.filesystems[]?.target | select(. == $root or startswith($root + "/"))] | length')" == 0 ]]
[[ "$(stat -Lc '%d' -- appdata)" == "$(stat -Lc '%d' -- .)" ]]
UNSAFE_APPDATA="$(find -P appdata -xdev \
  \( -type l -o -type b -o -type c -o -type p -o -type s \
    -o -type f -links +1 \) -print -quit)"
[[ -z "$UNSAFE_APPDATA" ]]
for path in appdata/data appdata/custom-templates appdata/certs; do
  [[ -d "$path" && ! -L "$path" ]]
done
for path in app.env scripts/backup.cron .run.conf/.templates.lock; do
  [[ -f "$path" && ! -L "$path" ]]
done
for path in .env docker-compose.main.yaml ../run.sh docker-compose.app.yaml \
  scripts/authentik-server-entrypoint.py; do
  [[ -f "$path" && ! -L "$path" ]]
done
for path in dockerfiles scripts; do
  [[ -d "$path" && ! -L "$path" ]]
done
APPDATA_IDS="$(stat -Lc '%d:%i %n' -- appdata appdata/data \
  appdata/custom-templates appdata/certs)"
[[ -z "$(find -P appdata/data appdata/custom-templates appdata/certs -xdev \
  -type f -perm /111 -print -quit)" ]]

install -m 0600 -- app.env "$PRIVATE_DIR/app.env"
install -m 0600 -- .env "$PRIVATE_DIR/merged.env"
install -m 0600 -- .run.conf/.templates.lock "$RECOVERY_DIR/templates.lock"
SOURCE_LOCK_STATE=absent
SOURCE_LOCK_SHA256=""
if [[ -e .run.conf/.source.lock || -L .run.conf/.source.lock ]]; then
  [[ -f .run.conf/.source.lock && ! -L .run.conf/.source.lock ]]
  [[ "$(wc -l < .run.conf/.source.lock)" == 3 ]]
  grep -Eq '^version=1$' .run.conf/.source.lock
  grep -Eq '^commit=([0-9a-f]{40}|[0-9a-f]{64})$' .run.conf/.source.lock
  grep -Eq '^tree=([0-9a-f]{40}|[0-9a-f]{64})$' .run.conf/.source.lock
  install -m 0600 -- .run.conf/.source.lock "$RECOVERY_DIR/source.lock"
  SOURCE_LOCK_STATE=present
  SOURCE_LOCK_SHA256="$(sha256sum "$RECOVERY_DIR/source.lock" | awk '{print $1}')"
fi
CONFIG_JSON="$("${COMPOSE[@]}" config --format json)"
printf '%s\n' AUTHENTIK_BOOTSTRAP_PASSWORD AUTHENTIK_EMAIL_PASSWORD \
  AUTHENTIK_SECRET_KEY_PASSWORD POSTGRES_PASSWORD \
  > "$PRIVATE_DIR/expected-secrets.txt"
DECLARED_SECRETS="$(yq -er '.secrets | keys | .[]' \
  docker-compose.main.yaml | LC_ALL=C sort)"
[[ "$DECLARED_SECRETS" == "$(<"$PRIVATE_DIR/expected-secrets.txt")" ]]
SMTP_ENABLED="$(jq -er '.services.app.environment.AUTHENTIK_EMAIL_ENABLED |
  select(. == "true" or . == "false")' <<<"$CONFIG_JSON")"
SERVICE_SECRETS="$(jq -er '[.services[]?.secrets[]? |
  if type == "string" then . else .source end] | unique | .[]' \
  <<<"$CONFIG_JSON" | LC_ALL=C sort)"
if [[ "$SMTP_ENABLED" == true ]]; then
  grep -Fxq AUTHENTIK_EMAIL_PASSWORD <<<"$SERVICE_SECRETS"
else
  ! grep -Fxq AUTHENTIK_EMAIL_PASSWORD <<<"$SERVICE_SECRETS"
fi
while IFS= read -r name; do
  [[ -f "secrets/$name" && ! -L "secrets/$name" && -s "secrets/$name" ]]
  source="$(readlink -e -- "secrets/$name")"
  if jq -e --arg name "$name" '.secrets[$name]' <<<"$CONFIG_JSON" >/dev/null; then
    [[ "$(jq -er --arg name "$name" '.secrets[$name].file' \
      <<<"$CONFIG_JSON")" == "$source" ]]
  fi
  install -m 0600 -- "$source" "$PRIVATE_DIR/secrets/$name"
done < "$PRIVATE_DIR/expected-secrets.txt"
(
  cd "$PRIVATE_DIR"
  sha256sum -- app.env merged.env expected-secrets.txt secrets/* \
    > private-state.sha256
  chmod 0600 private-state.sha256
)

APP_ID="$("${COMPOSE[@]}" ps -q app)"
WORKER_ID="$("${COMPOSE[@]}" ps -q authentik-worker)"
BOOTSTRAP_ID="$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)"
POSTGRES_ID="$("${COMPOSE[@]}" ps -q postgresql)"
MAINTENANCE_ID="$("${COMPOSE[@]}" ps -q postgresql_maintenance)"
for id in "$APP_ID" "$WORKER_ID" "$BOOTSTRAP_ID" "$POSTGRES_ID" \
  "$MAINTENANCE_ID"; do
  [[ "$id" =~ ^[0-9a-f]{64}$ ]]
done
APP_IMAGE_ID="$(docker inspect --format '{{.Image}}' "$APP_ID")"
[[ "$(docker inspect --format '{{.Image}}' "$WORKER_ID")" == "$APP_IMAGE_ID" ]]
[[ "$(docker inspect --format '{{.Image}}' "$BOOTSTRAP_ID")" == "$APP_IMAGE_ID" ]]
[[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
  "$BOOTSTRAP_ID")" == exited:0 ]]
APP_IMAGE_REF="$(jq -er '.services.app.image' <<<"$CONFIG_JSON")"
APP_DIGEST="$(docker image inspect "$APP_IMAGE_ID" --format '{{json .RepoDigests}}' |
  jq -er '[.[] | select(startswith("ghcr.io/goauthentik/server@sha256:"))] |
    if length == 1 then .[0] else error("expected one Authentik digest") end')"
APP_VERSION="$(docker image inspect "$APP_IMAGE_ID" \
  --format '{{index .Config.Labels "org.opencontainers.image.version"}}')"
POSTGRES_IMAGE_ID="$(docker inspect --format '{{.Image}}' "$POSTGRES_ID")"
MAINTENANCE_IMAGE_ID="$(docker inspect --format '{{.Image}}' "$MAINTENANCE_ID")"
PROJECT_NAME="$(jq -er \
  '.name | select(test("^[a-z0-9][a-z0-9_-]*$"))' <<<"$CONFIG_JSON")"
jq -e '.services.postgresql.build != null and
  .services.postgresql.image == null and
  .services.postgresql_maintenance.build != null and
  .services.postgresql_maintenance.image == null' \
  <<<"$CONFIG_JSON" >/dev/null
POSTGRES_IMAGE_REF="${PROJECT_NAME}-postgresql"
MAINTENANCE_IMAGE_REF="${PROJECT_NAME}-postgresql_maintenance"
CONFIG_IMAGES="$("${COMPOSE[@]}" config --images)"
grep -Fxq "$POSTGRES_IMAGE_REF" <<<"$CONFIG_IMAGES"
grep -Fxq "$MAINTENANCE_IMAGE_REF" <<<"$CONFIG_IMAGES"
[[ "$APP_IMAGE_ID" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ "$POSTGRES_IMAGE_ID" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ "$MAINTENANCE_IMAGE_ID" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ -n "$APP_VERSION" && "$APP_VERSION" != '<no value>' ]]
[[ "$(docker image inspect "$APP_IMAGE_REF" --format '{{.Id}}')" == "$APP_IMAGE_ID" ]]
[[ "$(docker image inspect "$POSTGRES_IMAGE_REF" --format '{{.Id}}')" == \
  "$POSTGRES_IMAGE_ID" ]]
[[ "$(docker image inspect "$MAINTENANCE_IMAGE_REF" --format '{{.Id}}')" == \
  "$MAINTENANCE_IMAGE_ID" ]]
DOCKER_SERVER_PLATFORM="$(docker version \
  --format '{{.Server.Os}}/{{.Server.Arch}}')"
[[ "$DOCKER_SERVER_PLATFORM" =~ ^linux/(amd64|arm64)$ ]]
DOCKER_HOST_OS="${DOCKER_SERVER_PLATFORM%/*}"
DOCKER_HOST_ARCH="${DOCKER_SERVER_PLATFORM#*/}"
image_platform() {
  docker image inspect "$1" --format '{{json .}}' | jq -cer \
    --arg os "$DOCKER_HOST_OS" --arg architecture "$DOCKER_HOST_ARCH" '
    {os:.Os,architecture:.Architecture,variant:(.Variant // "")} |
    select(.os == $os and .architecture == $architecture and
      (.variant | test("^[a-z0-9_.-]*$")))'
}
APP_PLATFORM="$(image_platform "$APP_IMAGE_ID")"
POSTGRES_PLATFORM="$(image_platform "$POSTGRES_IMAGE_ID")"
MAINTENANCE_PLATFORM="$(image_platform "$MAINTENANCE_IMAGE_ID")"
jq -n --arg ref "$APP_IMAGE_REF" --arg digest "$APP_DIGEST" \
  --arg image_id "$APP_IMAGE_ID" \
  --arg version "$APP_VERSION" --arg postgresql "$POSTGRES_IMAGE_ID" \
  --arg postgresql_ref "$POSTGRES_IMAGE_REF" \
  --arg maintenance "$MAINTENANCE_IMAGE_ID" \
  --arg maintenance_ref "$MAINTENANCE_IMAGE_REF" \
  --arg host_os "$DOCKER_HOST_OS" --arg host_arch "$DOCKER_HOST_ARCH" \
  --argjson app_platform "$APP_PLATFORM" \
  --argjson postgresql_platform "$POSTGRES_PLATFORM" \
  --argjson maintenance_platform "$MAINTENANCE_PLATFORM" \
  '{host:{os:$host_os,architecture:$host_arch},
    authentik:{ref:$ref,digest:$digest,image_id:$image_id,version:$version,
      platform:$app_platform},postgresql:{ref:$postgresql_ref,
      image_id:$postgresql,platform:$postgresql_platform,
      maintenance_ref:$maintenance_ref,maintenance_image_id:$maintenance,
      maintenance_platform:$maintenance_platform}}' \
  > "$RECOVERY_DIR/versions.json"
chmod 0600 "$RECOVERY_DIR/versions.json"

CONTROL="authentik-control-${RECOVERY_ID}.tar.zst"
mapfile -d '' -t CONTROL_PATHS < <(
  cd ..
  printf 'run.sh\0'
  find Authentik -xdev -maxdepth 1 -type f \
    -name 'docker-compose*.yaml*' -print0
  find Authentik/dockerfiles -xdev -type f \
    ! -path '*/.cache/*' ! -path '*/__pycache__/*' -print0
  find Authentik/scripts -xdev -type f ! -name backup.cron \
    ! -path '*/__pycache__/*' -print0
)
(( ${#CONTROL_PATHS[@]} >= 5 ))
CONTROL_MANIFEST="authentik-control-${RECOVERY_ID}.manifest"
install -m 0600 /dev/null "$RECOVERY_DIR/$CONTROL_MANIFEST"
for path in "${CONTROL_PATHS[@]}"; do
  [[ "$path" == run.sh || "$path" == Authentik/docker-compose*.yaml* || \
    "$path" == Authentik/dockerfiles/* || "$path" == Authentik/scripts/* ]]
  [[ "$path" != *$'\n'* && "$path" != *$'\r'* && "$path" != *$'\t'* ]]
  [[ -f "../$path" && ! -L "../$path" && \
    "$(stat -Lc '%h' -- "../$path")" == 1 ]]
  printf '%s\t%s\t%s\n' "$path" "$(stat -Lc '%a' -- "../$path")" \
    "$(sha256sum "../$path" | awk '{print $1}')" \
    >> "$RECOVERY_DIR/$CONTROL_MANIFEST"
done
LC_ALL=C sort -o "$RECOVERY_DIR/$CONTROL_MANIFEST" \
  "$RECOVERY_DIR/$CONTROL_MANIFEST"
[[ "$(wc -l < "$RECOVERY_DIR/$CONTROL_MANIFEST")" == \
  "${#CONTROL_PATHS[@]}" ]]
tar --create --zstd --file "$RECOVERY_DIR/$CONTROL" --directory .. \
  "${CONTROL_PATHS[@]}"
chmod 0600 "$RECOVERY_DIR/$CONTROL"
(cd "$RECOVERY_DIR" && sha256sum -- "$CONTROL" > "${CONTROL}.sha256" && \
  chmod 0600 "${CONTROL}.sha256" && \
  sha256sum --check --strict "${CONTROL}.sha256")

RUNTIME_IMAGES="authentik-runtime-images-${RECOVERY_ID}.tar"
docker image save --output "$RECOVERY_DIR/$RUNTIME_IMAGES" \
  "$APP_IMAGE_REF" "$APP_DIGEST" "$POSTGRES_IMAGE_REF" "$MAINTENANCE_IMAGE_REF"
chmod 0600 "$RECOVERY_DIR/$RUNTIME_IMAGES"
(cd "$RECOVERY_DIR" && sha256sum -- "$RUNTIME_IMAGES" \
  > "${RUNTIME_IMAGES}.sha256" && chmod 0600 "${RUNTIME_IMAGES}.sha256" && \
  sha256sum --check --strict "${RUNTIME_IMAGES}.sha256")

RECOVERY_POINT_STOP_ATTEMPTED=true
"${COMPOSE[@]}" stop app authentik-worker authentik-bootstrap
"${COMPOSE[@]}" exec -T postgresql_maintenance /usr/local/bin/backup.sh full
"${COMPOSE[@]}" exec -T postgresql_maintenance /usr/local/bin/backup.sh dump

# Enter the exact IDs from the two explicit success messages above.
read -r -p 'New physical backup ID (YYYYMMDD_N): ' PHYSICAL_ID
read -r -p 'New logical backup ID (YYYYMMDD_HHMMSS): ' LOGICAL_ID
[[ "$PHYSICAL_ID" =~ ^[0-9]{8}_[0-9]{1,9}$ ]]
[[ "$LOGICAL_ID" =~ ^[0-9]{8}_[0-9]{6}$ ]]
PHYSICAL_ARCHIVE="backup/${PHYSICAL_ID%%_*}/full_${PHYSICAL_ID}.tar.zst"
LOGICAL_ARCHIVE="backup/${LOGICAL_ID%%_*}/dump_${LOGICAL_ID}.dump.zst"
PHYSICAL_MANIFEST="${PHYSICAL_ARCHIVE%.tar.zst}.manifest"
for archive in "$PHYSICAL_ARCHIVE" "$LOGICAL_ARCHIVE"; do
  stem="${archive##*/}"
  stem="${stem%.tar.zst}"
  stem="${stem%.dump.zst}"
  [[ -f "$archive" && ! -L "$archive" ]]
  [[ -f "${archive}.sha256" && ! -L "${archive}.sha256" ]]
  [[ -f "${archive%/*}/bundle_${stem}.sha256" && \
    ! -L "${archive%/*}/bundle_${stem}.sha256" ]]
  cmp -s -- "${archive}.sha256" "${archive%/*}/bundle_${stem}.sha256"
  (cd "${archive%/*}" && sha256sum --check --strict "${archive##*/}.sha256")
done
[[ -f "$PHYSICAL_MANIFEST" && ! -L "$PHYSICAL_MANIFEST" && -s "$PHYSICAL_MANIFEST" ]]

[[ "$(stat -Lc '%d:%i %n' -- appdata appdata/data \
  appdata/custom-templates appdata/certs)" == "$APPDATA_IDS" ]]
FILES="authentik-files-${RECOVERY_ID}.tar.zst"
sudo tar --create --zstd --one-file-system --file "$RECOVERY_DIR/$FILES" \
  appdata/data appdata/custom-templates appdata/certs scripts/backup.cron
sudo chown -- "$OWNER" "$RECOVERY_DIR/$FILES"
chmod 0600 "$RECOVERY_DIR/$FILES"
(cd "$RECOVERY_DIR" && sha256sum -- "$FILES" > "${FILES}.sha256" && \
  chmod 0600 "${FILES}.sha256" && \
  sha256sum --check --strict "${FILES}.sha256")

TEMPLATE_REVISION="$(<"$RECOVERY_DIR/templates.lock")"
[[ "$TEMPLATE_REVISION" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]
jq -n --arg id "$RECOVERY_ID" --arg files "$FILES" \
  --arg project_name "$PROJECT_NAME" \
  --arg files_sha "$(sha256sum "$RECOVERY_DIR/$FILES" | awk '{print $1}')" \
  --arg control "$CONTROL" \
  --arg control_sha "$(sha256sum "$RECOVERY_DIR/$CONTROL" | awk '{print $1}')" \
  --arg control_manifest "$CONTROL_MANIFEST" \
  --arg control_manifest_sha "$(sha256sum \
    "$RECOVERY_DIR/$CONTROL_MANIFEST" | awk '{print $1}')" \
  --arg runtime "$RUNTIME_IMAGES" \
  --arg runtime_sha "$(sha256sum "$RECOVERY_DIR/$RUNTIME_IMAGES" | awk '{print $1}')" \
  --arg versions_sha "$(sha256sum "$RECOVERY_DIR/versions.json" | awk '{print $1}')" \
  --arg private_sha "$(sha256sum "$PRIVATE_DIR/private-state.sha256" | awk '{print $1}')" \
  --arg template_revision "$TEMPLATE_REVISION" \
  --arg template_sha "$(sha256sum "$RECOVERY_DIR/templates.lock" | awk '{print $1}')" \
  --arg source_state "$SOURCE_LOCK_STATE" --arg source_sha "$SOURCE_LOCK_SHA256" \
  --arg host_os "$DOCKER_HOST_OS" --arg host_arch "$DOCKER_HOST_ARCH" \
  --arg digest "$APP_DIGEST" --arg physical_id "$PHYSICAL_ID" \
  --arg physical_sha "$(sha256sum "$PHYSICAL_ARCHIVE" | awk '{print $1}')" \
  --arg physical_manifest_sha "$(sha256sum "$PHYSICAL_MANIFEST" | awk '{print $1}')" \
  --arg logical_id "$LOGICAL_ID" \
  --arg logical_sha "$(sha256sum "$LOGICAL_ARCHIVE" | awk '{print $1}')" \
  '{version:2,id:$id,project_name:$project_name,
    host:{os:$host_os,architecture:$host_arch},
    files:{name:$files,sha256:$files_sha},
    control:{name:$control,sha256:$control_sha,manifest:$control_manifest,
      manifest_sha256:$control_manifest_sha},
    runtime_images:{name:$runtime,sha256:$runtime_sha},
    versions_sha256:$versions_sha,private_manifest_sha256:$private_sha,
    locks:{template_revision:$template_revision,template_sha256:$template_sha,
      source_state:$source_state,source_sha256:$source_sha},authentik_digest:$digest,
    postgresql:{physical:{id:$physical_id,sha256:$physical_sha,
      manifest_sha256:$physical_manifest_sha},logical:{id:$logical_id,
      sha256:$logical_sha}}}' > "$RECOVERY_DIR/recovery.json"
chmod 0600 "$RECOVERY_DIR/recovery.json"
(cd "$RECOVERY_DIR" && sha256sum -- recovery.json > recovery.json.sha256 && \
  chmod 0600 recovery.json.sha256 && \
  sha256sum --check --strict recovery.json.sha256)
[[ -z "$(find -P "$RECOVERY_DIR" "$PRIVATE_DIR" -xdev \
  \( -type d \( ! -uid "$(id -u)" -o ! -gid "$(id -g)" -o ! -perm 0700 \) \
    -o -type f \( ! -uid "$(id -u)" -o ! -gid "$(id -g)" -o ! -perm 0600 \) \
    -o ! -type d ! -type f \) -print -quit)" ]]
if [[ "$KEEP_WRITERS_STOPPED" == true ]]; then
  [[ "$("${COMPOSE[@]}" ps -a -q app)" == "$APP_ID" ]]
  [[ "$("${COMPOSE[@]}" ps -a -q authentik-worker)" == "$WORKER_ID" ]]
  for id in "$APP_ID" "$WORKER_ID"; do
    [[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
      "$id")" == exited:0 ]]
  done
else
  restart_original_recovery_writers
fi
trap '' HUP INT TERM
RECOVERY_POINT_RECOVERY_REQUIRED=false
RECOVERY_POINT_COMPLETE=true
trap - ERR HUP INT TERM EXIT
exec {RECOVERY_POINT_RECOVERY_DIR_FD}<&-
exec {RECOVERY_POINT_PRIVATE_DIR_FD}<&-
exec {RECOVERY_POINT_PARENT_FD}<&-
if [[ "$KEEP_WRITERS_STOPPED" == false ]]; then
  exec {AUTHENTIK_OPERATION_LOCK_FD}<&-
  unset AUTHENTIK_OPERATION_LOCK_FD AUTHENTIK_OPERATION_ROOT
fi
```

Copy both directories ænd the two exæct PostgreSQL bundles, including their
sidecærs, `bundle_*.sha256`, ænd the physicæl `.manifest`, to tested immutæble
off-host storæge. Encrypt the **entire** set; do not keep its plæintext copy on
ordinæry bæckup storæge. Æny fæiled commænd invælidætes the recovery point.

### Verify, stæge, ænd swæp files

Decrypt the mætching privæte set outside `Authentik/`, select one recovery ID,
ænd run from either the existing merged directory whose templæte/source locks
ælreædy mætch thæt record or the empty new-host root described below; do not
refresh either lock. This rewrites the recovered moving
`app.env` to the recorded digest before it cæn become live. It derives the
exæct top-level secret inventory, including the optionæl SMTP declærætion, from
the recovered Compose/environment ænd sepærætely proves thæt the SMTP service
mount is present if ænd only if SMTP is enæbled. Unknown or missing secret
files fæil closed.

On æ new host, first verify the `recovery.json` sidecær, its bound control
ærchive digest, ænd the strict control-pæth ællowlist shown below. Extræct thæt
ærchive with `--no-same-owner --same-permissions` into æ new empty mode-`0700`
root, never over æn ærbitæry checkout, then enter its `Authentik/` directory ænd
set `RECOVERY_DIR`/`PRIVATE_DIR` to the secure æbsolute off-host copies. The
bound mænifest gæte below proves every exæct pæth, byte digest, ænd mode before
æny locked merge while intentionælly ignoring the old host UID/GID.

```bash
set -euo pipefail
umask 077
AUTHENTIK_OPERATION_ROOT="$(pwd -P)"
RESTORE_OPERATION_PARENT="$(readlink -e -- ..)"
exec {RESTORE_OPERATION_PARENT_FD}<"$RESTORE_OPERATION_PARENT"
RESTORE_OPERATION_PARENT_ID="$(stat -Lc '%d:%i' -- \
  "$RESTORE_OPERATION_PARENT")"
[[ "$(stat -Lc '%d:%i' -- \
  "/proc/${BASHPID}/fd/${RESTORE_OPERATION_PARENT_FD}")" == \
  "$RESTORE_OPERATION_PARENT_ID" ]]
validate_authentik_operation_lock() {
  [[ "$AUTHENTIK_OPERATION_ROOT" == "$(pwd -P)" && \
    "$AUTHENTIK_OPERATION_LOCK_FD" =~ ^[0-9]+$ && \
    "$(readlink -e -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_ROOT" && \
    "$(stat -Lc '%d:%i' -- "$AUTHENTIK_OPERATION_ROOT")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" ]] || return 125
  flock -n -x "$AUTHENTIK_OPERATION_LOCK_FD" || return 125
  [[ "$AUTHENTIK_OPERATION_ROOT" == "$(pwd -P)" && \
    "$(readlink -e -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_ROOT" && \
    "$(stat -Lc '%d:%i' -- "$AUTHENTIK_OPERATION_ROOT")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" ]] || return 125
}
acquire_authentik_operation_lock() {
  [[ -d "$AUTHENTIK_OPERATION_ROOT" && \
    ! -L "$AUTHENTIK_OPERATION_ROOT" && \
    "$(readlink -e -- .)" == "$AUTHENTIK_OPERATION_ROOT" ]] || return 125
  AUTHENTIK_OPERATION_LOCK_IDENTITY="$(stat -Lc '%d:%i' -- \
    "$AUTHENTIK_OPERATION_ROOT")" || return 125
  if [[ -z "${AUTHENTIK_OPERATION_LOCK_FD:-}" ]]; then
    exec {AUTHENTIK_OPERATION_LOCK_FD}<"$AUTHENTIK_OPERATION_ROOT" || \
      return 125
  fi
  [[ "$AUTHENTIK_OPERATION_LOCK_FD" =~ ^[0-9]+$ ]] || return 125
  validate_authentik_operation_lock
}
acquire_authentik_operation_lock
export AUTHENTIK_OPERATION_ROOT AUTHENTIK_OPERATION_LOCK_FD \
  AUTHENTIK_OPERATION_LOCK_IDENTITY
run_authentik_with_inherited_operation_lock() {
  validate_authentik_operation_lock || return 125
  (
    cd .. || exit 125
    RUN_INHERITED_PROJECT_LOCK_FD="$AUTHENTIK_OPERATION_LOCK_FD" \
    RUN_INHERITED_PROJECT_LOCK_PATH="$AUTHENTIK_OPERATION_ROOT" \
    RUN_INHERITED_PROJECT_LOCK_IDENTITY="$AUTHENTIK_OPERATION_LOCK_IDENTITY" \
      ./run.sh Authentik
  ) || return 125
  validate_authentik_operation_lock
}
RECOVERY_DIR=../authentik-recovery-20260819T120000Z
PRIVATE_DIR=../authentik-private-20260819T120000Z
for path in "$RECOVERY_DIR" "$PRIVATE_DIR" "$PRIVATE_DIR/secrets"; do
  [[ -d "$path" && ! -L "$path" ]]
  [[ "$(stat -Lc '%a:%u:%g' -- "$path")" == \
    "700:$(id -u):$(id -g)" ]]
done
RECOVERY_DIR="$(readlink -e -- "$RECOVERY_DIR")"
PRIVATE_DIR="$(readlink -e -- "$PRIVATE_DIR")"
[[ -z "$(find -P "$RECOVERY_DIR" "$PRIVATE_DIR" -xdev \
  \( -type d \( ! -uid "$(id -u)" -o ! -gid "$(id -g)" -o ! -perm 0700 \) \
    -o -type f \( ! -uid "$(id -u)" -o ! -gid "$(id -g)" -o ! -perm 0600 \) \
    -o ! -type d ! -type f \) -print -quit)" ]]
RECORD="$RECOVERY_DIR/recovery.json"
BASE_ENV="$PRIVATE_DIR/merged.env"
COMPOSE_FILE="$(pwd -P)/docker-compose.main.yaml"

[[ -f "$BASE_ENV" && ! -L "$BASE_ENV" ]]
for file in recovery.json recovery.json.sha256 versions.json templates.lock; do
  [[ -f "$RECOVERY_DIR/$file" && ! -L "$RECOVERY_DIR/$file" ]]
done
(cd "$RECOVERY_DIR" && \
  [[ "$(<recovery.json.sha256)" == "$(sha256sum recovery.json | awk \
    '{print $1}')  recovery.json" ]] && \
  sha256sum --check --strict recovery.json.sha256)
jq -e '
  .version == 2 and (.id | test("^[0-9]{8}T[0-9]{6}Z$")) and
  (.project_name | test("^[a-z0-9][a-z0-9_-]*$")) and
  (.files.name == ("authentik-files-" + .id + ".tar.zst")) and
  (.control.name == ("authentik-control-" + .id + ".tar.zst")) and
  (.control.manifest == ("authentik-control-" + .id + ".manifest")) and
  (.runtime_images.name ==
    ("authentik-runtime-images-" + .id + ".tar")) and
  (.host.os | test("^[a-z0-9]+$")) and
  (.host.architecture | test("^[a-z0-9_][a-z0-9_.-]*$")) and
  ([.files.sha256,.versions_sha256,.private_manifest_sha256,
    .control.sha256,.control.manifest_sha256,.runtime_images.sha256,
    .locks.template_sha256,.postgresql.physical.sha256,
    .postgresql.physical.manifest_sha256,.postgresql.logical.sha256] |
    all(test("^[0-9a-f]{64}$"))) and
  (.authentik_digest | test("^ghcr.io/goauthentik/server@sha256:[0-9a-f]{64}$")) and
  (.locks.template_revision | test("^([0-9a-f]{40}|[0-9a-f]{64})$")) and
  (.postgresql.physical.id | test("^[0-9]{8}_[0-9]{1,9}$")) and
  (.postgresql.logical.id | test("^[0-9]{8}_[0-9]{6}$")) and
  (if .locks.source_state == "present" then
    (.locks.source_sha256 | test("^[0-9a-f]{64}$"))
   else .locks.source_state == "absent" and .locks.source_sha256 == "" end)
' "$RECORD" >/dev/null
RESTORE_RECOVERY_ID="$(jq -er '.id' "$RECORD")"
RESTORE_ABORT_INVENTORY=''
RESTORE_ABORT_INVENTORY_ID=''
cleanup_restore_abort_inventory() {
  local status=0
  if [[ -n "$RESTORE_ABORT_INVENTORY" && \
    ( -e "$RESTORE_ABORT_INVENTORY" || -L "$RESTORE_ABORT_INVENTORY" ) ]]; then
    if [[ -f "$RESTORE_ABORT_INVENTORY" && \
      ! -L "$RESTORE_ABORT_INVENTORY" && \
      "$(stat -Lc '%d:%i' -- "$RESTORE_ABORT_INVENTORY")" == \
      "$RESTORE_ABORT_INVENTORY_ID" ]]; then
      rm -f -- "$RESTORE_ABORT_INVENTORY" || status=125
    else
      status=125
    fi
  fi
  return "$status"
}
trap cleanup_restore_abort_inventory EXIT
RESTORE_ABORT_INVENTORY="$(mktemp \
  "${TMPDIR:-/tmp}/authentik-restore-abort-inventory.XXXXXX")"
RESTORE_ABORT_INVENTORY_ID="$(stat -Lc '%d:%i' -- \
  "$RESTORE_ABORT_INVENTORY")"
[[ "$(stat -Lc '%a:%u:%g' -- "$RESTORE_ABORT_INVENTORY")" == \
  "600:$(id -u):$(id -g)" ]]
find -P .. -mindepth 1 -maxdepth 1 \
  \( -name 'authentik-update-abort-*' -o \
    -name '.authentik-update-abort-*' -o \
    -name 'authentik-restore-abort-*' -o \
    -name '.authentik-restore-abort-*' \) -print0 \
  > "$RESTORE_ABORT_INVENTORY"
RESTORE_ACTIVE_ABORT_COUNT=0
while IFS= read -r -d '' candidate; do
  name="${candidate##*/}"
  [[ -d "$candidate" && ! -L "$candidate" ]] || {
    printf 'Unsafe Authentik abort marker entry: %q\n' "$candidate" >&2
    exit 125
  }
  if [[ "$name" =~ \
    ^authentik-(update|restore)-abort-[0-9]{8}T[0-9]{6}Z-resolved-[0-9]{8}T[0-9]{6}Z$ ]]; then
    continue
  fi
  if [[ "$name" == "authentik-update-abort-${RESTORE_RECOVERY_ID}" ]]; then
    ((RESTORE_ACTIVE_ABORT_COUNT+=1))
    continue
  fi
  printf 'Conflicting or malformed Authentik abort marker: %q\n' \
    "$candidate" >&2
  exit 125
done < "$RESTORE_ABORT_INVENTORY"
(( RESTORE_ACTIVE_ABORT_COUNT <= 1 ))
cleanup_restore_abort_inventory
RESTORE_ABORT_INVENTORY=''
RESTORE_ABORT_INVENTORY_ID=''
trap - EXIT
FILES="$(jq -er '.files.name' "$RECORD")"
CONTROL="$(jq -er '.control.name' "$RECORD")"
CONTROL_MANIFEST="$(jq -er '.control.manifest' "$RECORD")"
RUNTIME_IMAGES="$(jq -er '.runtime_images.name' "$RECORD")"
APP_DIGEST="$(jq -er '.authentik_digest' "$RECORD")"
RECOVERY_PROJECT_NAME="$(jq -er '.project_name' "$RECORD")"
[[ "$(sha256sum "$RECOVERY_DIR/$FILES" | awk '{print $1}')" == \
  "$(jq -er '.files.sha256' "$RECORD")" ]]
(cd "$RECOVERY_DIR" && \
  [[ "$(<"${FILES}.sha256")" == "$(sha256sum "$FILES" | awk \
    '{print $1}')  $FILES" ]] && sha256sum --check --strict "${FILES}.sha256")
for archive in "$CONTROL" "$RUNTIME_IMAGES"; do
  [[ -f "$RECOVERY_DIR/$archive" && ! -L "$RECOVERY_DIR/$archive" ]]
  [[ -f "$RECOVERY_DIR/${archive}.sha256" && \
    ! -L "$RECOVERY_DIR/${archive}.sha256" ]]
  field=control
  [[ "$archive" == "$CONTROL" ]] || field=runtime_images
  [[ "$(sha256sum "$RECOVERY_DIR/$archive" | awk '{print $1}')" == \
    "$(jq -er --arg field "$field" '.[$field].sha256' "$RECORD")" ]]
  (cd "$RECOVERY_DIR" && \
    [[ "$(<"${archive}.sha256")" == "$(sha256sum "$archive" | awk \
      '{print $1}')  $archive" ]] && \
    sha256sum --check --strict "${archive}.sha256")
done
[[ -f "$RECOVERY_DIR/$CONTROL_MANIFEST" && \
  ! -L "$RECOVERY_DIR/$CONTROL_MANIFEST" ]]
[[ "$(sha256sum "$RECOVERY_DIR/$CONTROL_MANIFEST" | awk '{print $1}')" == \
  "$(jq -er '.control.manifest_sha256' "$RECORD")" ]]
tar --list --zstd --file "$RECOVERY_DIR/$CONTROL" | awk '
  $0 == "run.sh" { next }
  /^Authentik\/docker-compose[^/]*\.yaml[^/]*$/ { next }
  /\/(\.cache|__pycache__)(\/|$)/ { exit 1 }
  /^Authentik\/dockerfiles\// { next }
  /^Authentik\/scripts\// && $0 != "Authentik/scripts/backup.cron" { next }
  { exit 1 }
'
for path in ../Authentik/dockerfiles ../Authentik/scripts; do
  [[ -d "$path" && ! -L "$path" ]]
done
cmp -s \
  <(tar --list --zstd --file "$RECOVERY_DIR/$CONTROL" | LC_ALL=C sort) \
  <(cut -f1 "$RECOVERY_DIR/$CONTROL_MANIFEST" | LC_ALL=C sort)
cmp -s \
  <(tar --list --zstd --file "$RECOVERY_DIR/$CONTROL" | LC_ALL=C sort) \
  <(
    cd ..
    {
      printf '%s\n' run.sh
      find Authentik -xdev -maxdepth 1 -type f \
        -name 'docker-compose*.yaml*' -print
      find Authentik/dockerfiles -xdev -type f \
        ! -path '*/.cache/*' ! -path '*/__pycache__/*' -print
      find Authentik/scripts -xdev -type f ! -name backup.cron \
        ! -path '*/__pycache__/*' -print
    } | LC_ALL=C sort
  )
while IFS=$'\t' read -r path mode digest extra; do
  [[ -n "$path" && -z "$extra" ]]
  [[ "$path" != *$'\n'* && "$path" != *$'\r'* ]]
  [[ "$mode" =~ ^[0-7]{3,4}$ && "$digest" =~ ^[0-9a-f]{64}$ ]]
  [[ -f "../$path" && ! -L "../$path" && \
    "$(stat -Lc '%h:%a' -- "../$path")" == "1:$mode" ]]
  [[ "$(sha256sum "../$path" | awk '{print $1}')" == "$digest" ]]
done < "$RECOVERY_DIR/$CONTROL_MANIFEST"
[[ "$(sha256sum "$RECOVERY_DIR/versions.json" | awk '{print $1}')" == \
  "$(jq -er '.versions_sha256' "$RECORD")" ]]
mapfile -t RECORDED_IMAGE_IDS < <(jq -er \
  '.authentik.image_id,.postgresql.image_id,.postgresql.maintenance_image_id |
   select(test("^sha256:[0-9a-f]{64}$"))' "$RECOVERY_DIR/versions.json")
(( ${#RECORDED_IMAGE_IDS[@]} == 3 ))
mapfile -t RECORDED_IMAGE_REFS < <(jq -er \
  '.authentik.ref,.postgresql.ref,.postgresql.maintenance_ref |
   select(type == "string" and length > 0)' "$RECOVERY_DIR/versions.json")
(( ${#RECORDED_IMAGE_REFS[@]} == 3 ))
jq -e '.host as $host |
  ($host.os | test("^[a-z0-9]+$")) and
  ($host.architecture | test("^[a-z0-9_][a-z0-9_.-]*$")) and
  ([.authentik.platform,.postgresql.platform,
    .postgresql.maintenance_platform] | all(
      .os == $host.os and .architecture == $host.architecture and
      (.variant | test("^[a-z0-9_.-]*$"))))' \
  "$RECOVERY_DIR/versions.json" >/dev/null
[[ "$(jq -c '.host' "$RECORD")" == \
  "$(jq -c '.host' "$RECOVERY_DIR/versions.json")" ]]
TARGET_DOCKER_PLATFORM="$(docker version \
  --format '{{.Server.Os}}/{{.Server.Arch}}')"
[[ "$TARGET_DOCKER_PLATFORM" =~ ^linux/(amd64|arm64)$ ]]
TARGET_DOCKER_OS="${TARGET_DOCKER_PLATFORM%/*}"
TARGET_DOCKER_ARCH="${TARGET_DOCKER_PLATFORM#*/}"
[[ "$TARGET_DOCKER_OS" == \
  "$(jq -er '.host.os' "$RECOVERY_DIR/versions.json")" ]]
[[ "$TARGET_DOCKER_ARCH" == \
  "$(jq -er '.host.architecture' "$RECOVERY_DIR/versions.json")" ]]
[[ -n "$(jq -er '.authentik.version | select(length > 0)' \
  "$RECOVERY_DIR/versions.json")" ]]
[[ "$(jq -er '.authentik.digest' "$RECOVERY_DIR/versions.json")" == "$APP_DIGEST" ]]
[[ "$(sha256sum "$RECOVERY_DIR/templates.lock" | awk '{print $1}')" == \
  "$(jq -er '.locks.template_sha256' "$RECORD")" ]]
TEMPLATE_REVISION="$(jq -er '.locks.template_revision' "$RECORD")"
[[ "$(<"$RECOVERY_DIR/templates.lock")" == "$TEMPLATE_REVISION" ]]
SOURCE_STATE="$(jq -er '.locks.source_state' "$RECORD")"
FRESH_HOST=false
RESTORE_UNITS=(appdata app.env secrets scripts/backup.cron .run.conf)
PRESENT_UNITS=0
for path in "${RESTORE_UNITS[@]}"; do
  if [[ -e "$path" || -L "$path" ]]; then
    ((PRESENT_UNITS+=1))
  fi
done
if (( PRESENT_UNITS == 0 )); then
  FRESH_HOST=true
  [[ ! -e .env && ! -L .env ]]
else
  (( PRESENT_UNITS == ${#RESTORE_UNITS[@]} ))
fi
TEMPLATE_LOCK_ID=absent
SOURCE_LOCK_ID=absent
if [[ "$FRESH_HOST" != true ]]; then
  [[ -f .run.conf/.templates.lock && ! -L .run.conf/.templates.lock ]]
  cmp -s -- .run.conf/.templates.lock "$RECOVERY_DIR/templates.lock"
  TEMPLATE_LOCK_ID="$(stat -Lc '%d:%i' -- .run.conf/.templates.lock)"
fi
if [[ "$SOURCE_STATE" == present ]]; then
  [[ -f "$RECOVERY_DIR/source.lock" && ! -L "$RECOVERY_DIR/source.lock" ]]
  [[ "$(wc -l < "$RECOVERY_DIR/source.lock")" == 3 ]]
  [[ "$(sha256sum "$RECOVERY_DIR/source.lock" | awk '{print $1}')" == \
    "$(jq -er '.locks.source_sha256' "$RECORD")" ]]
  if [[ "$FRESH_HOST" != true ]]; then
    [[ -f .run.conf/.source.lock && ! -L .run.conf/.source.lock ]]
    cmp -s -- .run.conf/.source.lock "$RECOVERY_DIR/source.lock"
    SOURCE_LOCK_ID="$(stat -Lc '%d:%i' -- .run.conf/.source.lock)"
  fi
else
  [[ ! -e "$RECOVERY_DIR/source.lock" && ! -L "$RECOVERY_DIR/source.lock" ]]
  if [[ "$FRESH_HOST" != true ]]; then
    [[ ! -e .run.conf/.source.lock && ! -L .run.conf/.source.lock ]]
  fi
fi

for file in app.env merged.env expected-secrets.txt private-state.sha256; do
  [[ -f "$PRIVATE_DIR/$file" && ! -L "$PRIVATE_DIR/$file" ]]
done
[[ "$(sha256sum "$PRIVATE_DIR/private-state.sha256" | awk '{print $1}')" == \
  "$(jq -er '.private_manifest_sha256' "$RECORD")" ]]
(cd "$PRIVATE_DIR" && sha256sum --check --strict private-state.sha256)
EXPECTED_SECRETS="$(<"$PRIVATE_DIR/expected-secrets.txt")"
DECLARED_SECRETS="$(yq -er '.secrets | keys | .[]' "$COMPOSE_FILE" |
  LC_ALL=C sort)"
[[ "$DECLARED_SECRETS" == "$EXPECTED_SECRETS" ]]
PRIVATE_SECRETS="$(find -P "$PRIVATE_DIR/secrets" -mindepth 1 -maxdepth 1 \
  -type f -printf '%f\n' | LC_ALL=C sort)"
PRIVATE_UNSAFE="$(find -P "$PRIVATE_DIR/secrets" -mindepth 1 \
  \( ! -type f -o -type f ! -size +0c \) -print -quit)"
[[ -n "$EXPECTED_SECRETS" && "$PRIVATE_SECRETS" == "$EXPECTED_SECRETS" ]]
[[ -z "$PRIVATE_UNSAFE" ]]

tar --list --zstd --file "$RECOVERY_DIR/$FILES" | LC_ALL=C awk '
  /(^|\/)\.\.(\/|$)/ || /^\.\// || /\/\.\// { bad=1; next }
  /^appdata\/(data|custom-templates|certs)(\/|$)/ { next }
  /^scripts\/backup\.cron$/ { next }
  { bad=1 }
  END { exit bad }
'
STAGE="$(mktemp -d ./authentik-restore.XXXXXX)"
[[ "$(stat -Lc '%a:%d' -- "$STAGE")" == "700:$(stat -Lc '%d' -- .)" ]]
STAGE="$(readlink -e -- "$STAGE")"
tar --extract --zstd --file "$RECOVERY_DIR/$FILES" --directory "$STAGE" \
  --no-same-owner --no-same-permissions
mkdir -m 0700 -- "$STAGE/secrets" "$STAGE/.run.conf"
install -m 0600 -- "$RECOVERY_DIR/templates.lock" \
  "$STAGE/.run.conf/.templates.lock"
install -m 0600 /dev/null "$STAGE/app.env"
awk -v image="$APP_DIGEST" '
  BEGIN { count=0 }
  /^APP_IMAGE=/ { print "APP_IMAGE=" image; count++; next }
  { print }
  END { if (count != 1) exit 1 }
' "$PRIVATE_DIR/app.env" > "$STAGE/app.env"
RECOVERED_CONFIG="$(docker compose --project-name "$RECOVERY_PROJECT_NAME" \
  --project-directory "$STAGE" \
  --env-file "$BASE_ENV" --env-file "$STAGE/app.env" \
  -f "$COMPOSE_FILE" config --format json)"
RECOVERED_PROJECT="$(jq -er \
  '.name | select(test("^[a-z0-9][a-z0-9_-]*$"))' <<<"$RECOVERED_CONFIG")"
[[ "$RECOVERED_PROJECT" == "$RECOVERY_PROJECT_NAME" ]]
jq -e '.services.postgresql.build != null and
  .services.postgresql.image == null and
  .services.postgresql_maintenance.build != null and
  .services.postgresql_maintenance.image == null' \
  <<<"$RECOVERED_CONFIG" >/dev/null
[[ "$(jq -er '.postgresql.ref' "$RECOVERY_DIR/versions.json")" == \
  "${RECOVERED_PROJECT}-postgresql" ]]
[[ "$(jq -er '.postgresql.maintenance_ref' \
  "$RECOVERY_DIR/versions.json")" == \
  "${RECOVERED_PROJECT}-postgresql_maintenance" ]]
RECOVERED_IMAGES="$(docker compose --project-name "$RECOVERY_PROJECT_NAME" \
  --project-directory "$STAGE" \
  --env-file "$BASE_ENV" --env-file "$STAGE/app.env" \
  -f "$COMPOSE_FILE" config --images)"
grep -Fxq "${RECOVERED_PROJECT}-postgresql" <<<"$RECOVERED_IMAGES"
grep -Fxq "${RECOVERED_PROJECT}-postgresql_maintenance" \
  <<<"$RECOVERED_IMAGES"
RECOVERED_LOCAL_VOLUMES="$(jq -er '
  [.volumes // {} | to_entries[] |
    select(.value.external != true) | .value.name] |
  sort | if length > 0 and length == (unique | length) then .[]
  else error("missing or duplicate local volume names") end' \
  <<<"$RECOVERED_CONFIG")"
if [[ "$FRESH_HOST" == true ]]; then
  EXISTING_DOCKER_VOLUMES="$(docker volume ls --format '{{.Name}}')"
fi
while IFS= read -r volume; do
  [[ "$volume" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]
  if [[ "$FRESH_HOST" == true ]]; then
    ! grep -Fxq "$volume" <<<"$EXISTING_DOCKER_VOLUMES"
  fi
done <<<"$RECOVERED_LOCAL_VOLUMES"
RECOVERED_SMTP_ENABLED="$(jq -er \
  '.services.app.environment.AUTHENTIK_EMAIL_ENABLED |
   select(. == "true" or . == "false")' <<<"$RECOVERED_CONFIG")"
RECOVERED_SERVICE_SECRETS="$(jq -er '[.services[]?.secrets[]? |
  if type == "string" then . else .source end] | unique | .[]' \
  <<<"$RECOVERED_CONFIG" | LC_ALL=C sort)"
if [[ "$RECOVERED_SMTP_ENABLED" == true ]]; then
  grep -Fxq AUTHENTIK_EMAIL_PASSWORD <<<"$RECOVERED_SERVICE_SECRETS"
else
  ! grep -Fxq AUTHENTIK_EMAIL_PASSWORD <<<"$RECOVERED_SERVICE_SECRETS"
fi
while IFS= read -r name; do
  target="$STAGE/secrets/$name"
  if jq -e --arg name "$name" '.secrets[$name]' \
    <<<"$RECOVERED_CONFIG" >/dev/null; then
    [[ "$(jq -er --arg name "$name" '.secrets[$name].file' \
      <<<"$RECOVERED_CONFIG")" == "$target" ]]
  fi
  [[ "$target" == "$STAGE/secrets/$name" ]]
  install -m 0600 -- "$PRIVATE_DIR/secrets/$name" "$target"
done < "$PRIVATE_DIR/expected-secrets.txt"

STAGE_UNSAFE="$(find -P "$STAGE" -xdev \
  \( -type l -o -type b -o -type c -o -type p -o -type s \
    -o -type f -links +1 \) -print -quit)"
STAGE_MOUNTS="$(findmnt --json --list --output TARGET | jq -r \
  --arg root "$(readlink -e -- "$STAGE")" \
  '[.filesystems[]?.target | select(. == $root or startswith($root + "/"))] | length')"
[[ -z "$STAGE_UNSAFE" && "$STAGE_MOUNTS" == 0 ]]
PRIVATE_MODE_DRIFT="$(find -P "$STAGE" -xdev \
  \( -type d ! -perm 0700 -o -type f ! -perm 0600 \) -print -quit)"
[[ -z "$PRIVATE_MODE_DRIFT" ]]
APP_USER="$(jq -er '.services.app.user | select(test("^[0-9]+:[0-9]+$"))' \
  <<<"$RECOVERED_CONFIG")"
APP_UID="${APP_USER%%:*}"
APP_GID="${APP_USER##*:}"
for leaf in data custom-templates certs; do
  sudo chown -R -- "$APP_UID:$APP_GID" "$STAGE/appdata/$leaf"
  sudo find -P "$STAGE/appdata/$leaf" -xdev -type d -exec chmod 0770 -- {} +
  sudo find -P "$STAGE/appdata/$leaf" -xdev -type f -exec chmod 0660 -- {} +
done
chmod 0644 "$STAGE/scripts/backup.cron"
STAGE_IDS="$(stat -Lc '%d:%i %n' -- "$STAGE/appdata" \
  "$STAGE/appdata/data" "$STAGE/appdata/custom-templates" \
  "$STAGE/appdata/certs" "$STAGE/app.env" "$STAGE/secrets" \
  "$STAGE/scripts/backup.cron" \
  "$STAGE/.run.conf/.templates.lock")"

if [[ "$FRESH_HOST" == true ]]; then
  COMPOSE=(docker compose --project-name "$RECOVERY_PROJECT_NAME" \
    --env-file "$BASE_ENV" -f "$COMPOSE_FILE")
  CURRENT_CONFIG="$RECOVERED_CONFIG"
else
  [[ -f .env && ! -L .env ]]
  COMPOSE=(docker compose --project-name "$RECOVERY_PROJECT_NAME" \
    --env-file .env -f "$COMPOSE_FILE")
  CURRENT_CONFIG="$("${COMPOSE[@]}" config --format json)"
  [[ "$(jq -er '.name' <<<"$CURRENT_CONFIG")" == \
    "$RECOVERY_PROJECT_NAME" ]]
fi
PRE_SWAP_REF="$(jq -er '.services.app.image' <<<"$CURRENT_CONFIG")"
[[ "$PRE_SWAP_REF" != *'|'* && "$PRE_SWAP_REF" != *$'\t'* && \
  "$PRE_SWAP_REF" != *$'\n'* && "$PRE_SWAP_REF" != *$'\r'* ]]
PRE_SWAP_PROJECT="$(jq -er \
  '.name | select(test("^[a-z0-9][a-z0-9_-]*$"))' <<<"$CURRENT_CONFIG")"
jq -e '.services.postgresql.build != null and
  .services.postgresql.image == null and
  .services.postgresql_maintenance.build != null and
  .services.postgresql_maintenance.image == null' \
  <<<"$CURRENT_CONFIG" >/dev/null
PRE_SWAP_POSTGRES_REF="${PRE_SWAP_PROJECT}-postgresql"
PRE_SWAP_MAINTENANCE_REF="${PRE_SWAP_PROJECT}-postgresql_maintenance"
PRE_SWAP_CONFIG_IMAGES="$("${COMPOSE[@]}" config --images)"
grep -Fxq "$PRE_SWAP_POSTGRES_REF" <<<"$PRE_SWAP_CONFIG_IMAGES"
grep -Fxq "$PRE_SWAP_MAINTENANCE_REF" <<<"$PRE_SWAP_CONFIG_IMAGES"
PRE_SWAP_APP_CONTAINER="$("${COMPOSE[@]}" ps -a -q app)"
PRE_SWAP_WORKER_CONTAINER="$("${COMPOSE[@]}" ps -a -q authentik-worker)"
PRE_SWAP_BOOTSTRAP_CONTAINER="$("${COMPOSE[@]}" ps -a -q \
  authentik-bootstrap)"
PRE_SWAP_POSTGRES_CONTAINER="$("${COMPOSE[@]}" ps -a -q postgresql)"
PRE_SWAP_MAINTENANCE_CONTAINER="$("${COMPOSE[@]}" ps -a -q \
  postgresql_maintenance)"
declare -a PRE_SWAP_IMAGE_MAP=()
if [[ "$FRESH_HOST" == true ]]; then
  FRESH_CONTAINERS="$("${COMPOSE[@]}" ps -a -q)"
  [[ -z "$FRESH_CONTAINERS" ]]
  PRE_SWAP_DIGEST="$APP_DIGEST"
else
  PRE_SWAP_APP_REF_IMAGE="$(docker image inspect "$PRE_SWAP_REF" \
    --format '{{.Id}}')"
  [[ "$PRE_SWAP_APP_REF_IMAGE" =~ ^sha256:[0-9a-f]{64}$ ]]
  if [[ -n "$PRE_SWAP_APP_CONTAINER" ]]; then
    for id in "$PRE_SWAP_APP_CONTAINER" "$PRE_SWAP_WORKER_CONTAINER" \
      "$PRE_SWAP_BOOTSTRAP_CONTAINER"; do
      [[ "$id" =~ ^[0-9a-f]{64}$ ]]
    done
    PRE_SWAP_APP_IMAGE="$(docker inspect --format '{{.Image}}' \
      "$PRE_SWAP_APP_CONTAINER")"
    [[ "$(docker inspect --format '{{.Image}}' \
      "$PRE_SWAP_WORKER_CONTAINER")" == "$PRE_SWAP_APP_IMAGE" ]]
    [[ "$(docker inspect --format '{{.Image}}' \
      "$PRE_SWAP_BOOTSTRAP_CONTAINER")" == "$PRE_SWAP_APP_IMAGE" ]]
    [[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
      "$PRE_SWAP_BOOTSTRAP_CONTAINER")" == exited:0 ]]
  else
    PRE_SWAP_APP_IMAGE="$PRE_SWAP_APP_REF_IMAGE"
    for id in "$PRE_SWAP_WORKER_CONTAINER" "$PRE_SWAP_BOOTSTRAP_CONTAINER"; do
      [[ -z "$id" || "$id" =~ ^[0-9a-f]{64}$ ]]
      if [[ -n "$id" ]]; then
        [[ "$(docker inspect --format '{{.Image}}' "$id")" == \
          "$PRE_SWAP_APP_IMAGE" ]]
      fi
    done
    if [[ -n "$PRE_SWAP_BOOTSTRAP_CONTAINER" ]]; then
      [[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
        "$PRE_SWAP_BOOTSTRAP_CONTAINER")" == exited:0 ]]
    fi
  fi
  if [[ -n "$PRE_SWAP_POSTGRES_CONTAINER" ]]; then
    [[ "$PRE_SWAP_POSTGRES_CONTAINER" =~ ^[0-9a-f]{64}$ ]]
    PRE_SWAP_POSTGRES_IMAGE="$(docker inspect --format '{{.Image}}' \
      "$PRE_SWAP_POSTGRES_CONTAINER")"
  else
    PRE_SWAP_POSTGRES_IMAGE="$(docker image inspect \
      "$PRE_SWAP_POSTGRES_REF" --format '{{.Id}}')"
  fi
  if [[ -n "$PRE_SWAP_MAINTENANCE_CONTAINER" ]]; then
    [[ "$PRE_SWAP_MAINTENANCE_CONTAINER" =~ ^[0-9a-f]{64}$ ]]
    PRE_SWAP_MAINTENANCE_IMAGE="$(docker inspect --format '{{.Image}}' \
      "$PRE_SWAP_MAINTENANCE_CONTAINER")"
  else
    PRE_SWAP_MAINTENANCE_IMAGE="$(docker image inspect \
      "$PRE_SWAP_MAINTENANCE_REF" --format '{{.Id}}')"
  fi
  for id in "$PRE_SWAP_APP_IMAGE" "$PRE_SWAP_APP_REF_IMAGE" \
    "$PRE_SWAP_POSTGRES_IMAGE" "$PRE_SWAP_MAINTENANCE_IMAGE"; do
    [[ "$id" =~ ^sha256:[0-9a-f]{64}$ ]]
  done
  [[ "$(docker image inspect "$PRE_SWAP_POSTGRES_REF" --format '{{.Id}}')" == \
    "$PRE_SWAP_POSTGRES_IMAGE" ]]
  [[ "$(docker image inspect "$PRE_SWAP_MAINTENANCE_REF" --format '{{.Id}}')" == \
    "$PRE_SWAP_MAINTENANCE_IMAGE" ]]
  PRE_SWAP_IMAGE_MAP+=("$PRE_SWAP_REF|$PRE_SWAP_APP_REF_IMAGE")
  PRE_SWAP_IMAGE_MAP+=("$PRE_SWAP_POSTGRES_REF|$PRE_SWAP_POSTGRES_IMAGE")
  PRE_SWAP_IMAGE_MAP+=("$PRE_SWAP_MAINTENANCE_REF|$PRE_SWAP_MAINTENANCE_IMAGE")
  PRE_SWAP_DIGEST="$(docker image inspect "$PRE_SWAP_APP_IMAGE" \
    --format '{{json .RepoDigests}}' | jq -er \
    '[.[] | select(startswith("ghcr.io/goauthentik/server@sha256:"))] |
      if length == 1 then .[0] else error("expected one digest") end')"
fi
declare -a RESTORE_INITIAL_RUNNING_SERVICES=()
for service in app authentik-worker postgresql postgresql_maintenance; do
  id="$("${COMPOSE[@]}" ps -q "$service")"
  if [[ -n "$id" ]]; then
    [[ "$id" =~ ^[0-9a-f]{64}$ ]]
    RESTORE_INITIAL_RUNNING_SERVICES+=("$service")
  fi
done
RESTORE_PREFLIGHT_REQUIRED=false
RESTORE_PREFLIGHT_COMPLETE=false
RESTORE_PREFLIGHT_ROLLBACK_RUNNING=false
RESTORE_PREFLIGHT_SERVICE_MUTATION_STARTED=false
DB_ROLLBACK_DIR=''
DB_ROLLBACK_DIR_CREATED=false
DB_ROLLBACK_DIR_ID=''
DB_ROLLBACK_DIR_FD=''
restore_initial_service_topology() {
  local service id status=0
  local -a all_services=(app authentik-worker authentik-bootstrap postgresql \
    postgresql_maintenance)
  "${COMPOSE[@]}" stop "${all_services[@]}" || status=125
  if (( ${#RESTORE_INITIAL_RUNNING_SERVICES[@]} > 0 )); then
    "${COMPOSE[@]}" start --wait --wait-timeout 300 \
      "${RESTORE_INITIAL_RUNNING_SERVICES[@]}" || status=125
  fi
  for service in "${all_services[@]}"; do
    id="$("${COMPOSE[@]}" ps -q "$service")" || {
      status=125
      continue
    }
    if [[ " ${RESTORE_INITIAL_RUNNING_SERVICES[*]} " == *" $service "* ]]; then
      [[ "$id" =~ ^[0-9a-f]{64}$ ]] || {
        status=125
        continue
      }
      [[ "$(docker inspect --format '{{.State.Running}}' "$id")" == true ]] || \
        status=125
      if [[ "$service" == app || "$service" == postgresql || \
        "$service" == postgresql_maintenance ]]; then
        [[ "$(docker inspect --format '{{.State.Health.Status}}' "$id")" == \
          healthy ]] || status=125
      fi
    else
      [[ -z "$id" ]] || status=125
    fi
  done
  return "$status"
}
invalidate_db_rollback_preflight() {
  local failed status=0
  [[ "$DB_ROLLBACK_DIR_CREATED" == true ]] || return 0
  [[ -d "$DB_ROLLBACK_DIR" && ! -L "$DB_ROLLBACK_DIR" && \
    "$(stat -Lc '%d:%i' -- "$DB_ROLLBACK_DIR")" == "$DB_ROLLBACK_DIR_ID" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${DB_ROLLBACK_DIR_FD}")" == \
      "$DB_ROLLBACK_DIR_ID" && \
    "$(stat -Lc '%d:%i' -- "$RESTORE_OPERATION_PARENT")" == \
      "$RESTORE_OPERATION_PARENT_ID" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${RESTORE_OPERATION_PARENT_FD}")" == \
      "$RESTORE_OPERATION_PARENT_ID" && \
    "${DB_ROLLBACK_DIR%/*}" == "$RESTORE_OPERATION_PARENT" && \
    "${DB_ROLLBACK_DIR##*/}" =~ ^authentik-db-rollback\.[A-Za-z0-9]+$ ]] || \
    return 125
  failed="${DB_ROLLBACK_DIR}-failed-$(date -u +%Y%m%dT%H%M%SZ)-${BASHPID}"
  [[ ! -e "$failed" && ! -L "$failed" ]] || return 125
  mv -T -- "$DB_ROLLBACK_DIR" "$failed" || status=125
  if [[ "$status" == 0 ]]; then
    [[ -d "$failed" && ! -L "$failed" && \
      "$(stat -Lc '%d:%i' -- "$failed")" == "$DB_ROLLBACK_DIR_ID" && \
      "$(stat -Lc '%d:%i' -- \
        "/proc/${BASHPID}/fd/${DB_ROLLBACK_DIR_FD}")" == \
        "$DB_ROLLBACK_DIR_ID" ]] || status=125
  fi
  if [[ "$status" == 0 ]]; then
    exec {DB_ROLLBACK_DIR_FD}<&- || status=125
  fi
  return "$status"
}
abort_restore_preflight() {
  local status="$1"
  [[ "$RESTORE_PREFLIGHT_ROLLBACK_RUNNING" == false ]] || exit 125
  RESTORE_PREFLIGHT_ROLLBACK_RUNNING=true
  trap '' HUP INT TERM
  trap - ERR EXIT
  set +e
  if [[ "$RESTORE_PREFLIGHT_REQUIRED" == true && \
    "$RESTORE_PREFLIGHT_SERVICE_MUTATION_STARTED" == true ]]; then
    restore_initial_service_topology || status=125
  fi
  if [[ "$RESTORE_PREFLIGHT_REQUIRED" == true ]]; then
    invalidate_db_rollback_preflight || status=125
  fi
  exit "$status"
}
abort_restore_preflight_exit() {
  local status=$?
  if [[ "$RESTORE_PREFLIGHT_COMPLETE" == true || \
    "$RESTORE_PREFLIGHT_REQUIRED" == false ]]; then
    exit "$status"
  fi
  (( status != 0 )) || status=125
  abort_restore_preflight "$status"
}
trap 'abort_restore_preflight 129' HUP
trap 'abort_restore_preflight 130' INT
trap 'abort_restore_preflight 143' TERM
trap 'abort_restore_preflight $?' ERR
trap abort_restore_preflight_exit EXIT
RESTORE_PREFLIGHT_REQUIRED=true
trap '' HUP INT TERM
DB_ROLLBACK_DIR="$(mktemp -d \
  "$RESTORE_OPERATION_PARENT/authentik-db-rollback.XXXXXX")"
if ! exec {DB_ROLLBACK_DIR_FD}<"$DB_ROLLBACK_DIR"; then
  rmdir -- "$DB_ROLLBACK_DIR" || {
    printf 'Unbound DB rollback directory preserved at %q\n' \
      "$DB_ROLLBACK_DIR" >&2
  }
  exit 125
fi
if ! DB_ROLLBACK_DIR_ID="$(stat -Lc '%d:%i' -- "$DB_ROLLBACK_DIR")"; then
  exec {DB_ROLLBACK_DIR_FD}<&-
  rmdir -- "$DB_ROLLBACK_DIR" || {
    printf 'Unbound DB rollback directory preserved at %q\n' \
      "$DB_ROLLBACK_DIR" >&2
  }
  exit 125
fi
DB_ROLLBACK_DIR_CREATED=true
[[ -d "$DB_ROLLBACK_DIR" && ! -L "$DB_ROLLBACK_DIR" && \
  "$(stat -Lc '%d:%i' -- "$DB_ROLLBACK_DIR")" == "$DB_ROLLBACK_DIR_ID" && \
  "$(stat -Lc '%d:%i' -- \
    "/proc/${BASHPID}/fd/${DB_ROLLBACK_DIR_FD}")" == \
    "$DB_ROLLBACK_DIR_ID" ]]
trap 'abort_restore_preflight 129' HUP
trap 'abort_restore_preflight 130' INT
trap 'abort_restore_preflight 143' TERM
[[ "$(stat -Lc '%a:%d' -- "$DB_ROLLBACK_DIR")" == \
  "700:$(stat -Lc '%d' -- .)" ]]
DB_ROLLBACK_DIR="$(readlink -e -- "$DB_ROLLBACK_DIR")"
if [[ "$FRESH_HOST" == true ]]; then
  jq -n --argjson volumes "$(jq -c \
    '[.volumes // {} | to_entries[] | select(.value.external != true) |
      .value.name] | sort' <<<"$RECOVERED_CONFIG")" \
    '{version:1,kind:"new-host-none",preexisting_volumes:false,
      volumes:$volumes}' > "$DB_ROLLBACK_DIR/rollback.json"
else
  CURRENT_LOCAL_VOLUMES="$(jq -er '
    [.volumes // {} | to_entries[] | select(.value.external != true) |
      .value.name] | sort | if length > 0 then .[] else error end' \
    <<<"$CURRENT_CONFIG")"
  read -r -p 'Pre-restore DB rollback mode (maintenance/provider): ' \
    DB_ROLLBACK_MODE
  case "$DB_ROLLBACK_MODE" in
    maintenance)
      RESTORE_PREFLIGHT_SERVICE_MUTATION_STARTED=true
      "${COMPOSE[@]}" stop app authentik-worker authentik-bootstrap
      "${COMPOSE[@]}" up -d --wait --wait-timeout 120 \
        --no-build --pull never postgresql
      "${COMPOSE[@]}" up -d --no-build --pull never \
        postgresql_maintenance
      "${COMPOSE[@]}" exec -T postgresql_maintenance \
        /usr/local/bin/backup.sh full
      "${COMPOSE[@]}" exec -T postgresql_maintenance \
        /usr/local/bin/backup.sh dump
      read -r -p 'Pre-restore physical backup ID (YYYYMMDD_N): ' \
        DB_ROLLBACK_PHYSICAL_ID
      read -r -p 'Pre-restore logical backup ID (YYYYMMDD_HHMMSS): ' \
        DB_ROLLBACK_LOGICAL_ID
      [[ "$DB_ROLLBACK_PHYSICAL_ID" =~ ^[0-9]{8}_[0-9]{1,9}$ ]]
      [[ "$DB_ROLLBACK_LOGICAL_ID" =~ ^[0-9]{8}_[0-9]{6}$ ]]
      DB_ROLLBACK_PHYSICAL="backup/${DB_ROLLBACK_PHYSICAL_ID%%_*}/full_${DB_ROLLBACK_PHYSICAL_ID}.tar.zst"
      DB_ROLLBACK_LOGICAL="backup/${DB_ROLLBACK_LOGICAL_ID%%_*}/dump_${DB_ROLLBACK_LOGICAL_ID}.dump.zst"
      DB_ROLLBACK_PHYSICAL_MANIFEST="${DB_ROLLBACK_PHYSICAL%.tar.zst}.manifest"
      declare -a DB_ROLLBACK_FILES=(
        "$DB_ROLLBACK_PHYSICAL"
        "${DB_ROLLBACK_PHYSICAL}.sha256"
        "${DB_ROLLBACK_PHYSICAL%/*}/bundle_full_${DB_ROLLBACK_PHYSICAL_ID}.sha256"
        "$DB_ROLLBACK_PHYSICAL_MANIFEST"
        "$DB_ROLLBACK_LOGICAL"
        "${DB_ROLLBACK_LOGICAL}.sha256"
        "${DB_ROLLBACK_LOGICAL%/*}/bundle_dump_${DB_ROLLBACK_LOGICAL_ID}.sha256"
      )
      cmp -s -- "${DB_ROLLBACK_PHYSICAL}.sha256" \
        "${DB_ROLLBACK_PHYSICAL%/*}/bundle_full_${DB_ROLLBACK_PHYSICAL_ID}.sha256"
      cmp -s -- "${DB_ROLLBACK_LOGICAL}.sha256" \
        "${DB_ROLLBACK_LOGICAL%/*}/bundle_dump_${DB_ROLLBACK_LOGICAL_ID}.sha256"
      (cd "${DB_ROLLBACK_PHYSICAL%/*}" && sha256sum --check --strict \
        "${DB_ROLLBACK_PHYSICAL##*/}.sha256")
      (cd "${DB_ROLLBACK_LOGICAL%/*}" && sha256sum --check --strict \
        "${DB_ROLLBACK_LOGICAL##*/}.sha256")
      for file in "${DB_ROLLBACK_FILES[@]}"; do
        [[ -f "$file" && ! -L "$file" && -s "$file" ]]
        sudo install -m 0600 -- "$file" "$DB_ROLLBACK_DIR/${file##*/}"
      done
      sudo chown -R -- "$(id -u):$(id -g)" "$DB_ROLLBACK_DIR"
      (
        cd "$DB_ROLLBACK_DIR"
        sha256sum -- full_* bundle_full_* dump_* bundle_dump_* \
          > payload.sha256
        chmod 0600 payload.sha256
        sha256sum --check --strict payload.sha256
      )
      jq -n --arg physical_id "$DB_ROLLBACK_PHYSICAL_ID" \
        --arg logical_id "$DB_ROLLBACK_LOGICAL_ID" \
        --arg payload_sha "$(sha256sum \
          "$DB_ROLLBACK_DIR/payload.sha256" | awk '{print $1}')" \
        '{version:1,kind:"maintenance",physical_id:$physical_id,
          logical_id:$logical_id,payload_manifest_sha256:$payload_sha}' \
        > "$DB_ROLLBACK_DIR/rollback.json"
      ;;
    provider)
      RESTORE_PREFLIGHT_SERVICE_MUTATION_STARTED=true
      "${COMPOSE[@]}" stop app authentik-worker authentik-bootstrap \
        postgresql_maintenance postgresql
      RUNNING_CONTAINERS="$("${COMPOSE[@]}" ps --status running -q)"
      [[ -z "$RUNNING_CONTAINERS" ]]
      read -r -p 'Absolute provider snapshot manifest path: ' \
        PROVIDER_SNAPSHOT_MANIFEST
      [[ "$PROVIDER_SNAPSHOT_MANIFEST" == /* ]]
      PROVIDER_SNAPSHOT_MANIFEST="$(readlink -e -- \
        "$PROVIDER_SNAPSHOT_MANIFEST")"
      [[ -f "$PROVIDER_SNAPSHOT_MANIFEST" && \
        ! -L "$PROVIDER_SNAPSHOT_MANIFEST" ]]
      [[ "$(stat -Lc '%a:%u:%g' -- "$PROVIDER_SNAPSHOT_MANIFEST")" == \
        "600:$(id -u):$(id -g)" ]]
      jq -e '.version == 1 and .kind == "provider" and
        (.provider | test("^[a-zA-Z0-9_.-]+$")) and
        (.snapshot_id | type == "string") and (.snapshot_id | length > 0) and
        (.created_utc | test("^[0-9]{8}T[0-9]{6}Z$")) and
        (.volumes | type == "array" and length > 0 and
          length == (unique | length) and all(test("^[a-zA-Z0-9_.-]+$"))) and
        (.restore_runbook | test("^/")) and
        (.restore_runbook_sha256 | test("^[0-9a-f]{64}$")) and
        .operator_approval == "approved"' \
        "$PROVIDER_SNAPSHOT_MANIFEST" >/dev/null
      [[ "$(jq -r '.volumes[]' "$PROVIDER_SNAPSHOT_MANIFEST" | \
        LC_ALL=C sort)" == "$CURRENT_LOCAL_VOLUMES" ]]
      PROVIDER_RESTORE_RUNBOOK="$(jq -er '.restore_runbook' \
        "$PROVIDER_SNAPSHOT_MANIFEST")"
      PROVIDER_RESTORE_RUNBOOK="$(readlink -e -- "$PROVIDER_RESTORE_RUNBOOK")"
      [[ -f "$PROVIDER_RESTORE_RUNBOOK" && ! -L "$PROVIDER_RESTORE_RUNBOOK" ]]
      [[ "$(sha256sum "$PROVIDER_RESTORE_RUNBOOK" | awk '{print $1}')" == \
        "$(jq -er '.restore_runbook_sha256' \
          "$PROVIDER_SNAPSHOT_MANIFEST")" ]]
      install -m 0600 -- "$PROVIDER_SNAPSHOT_MANIFEST" \
        "$DB_ROLLBACK_DIR/provider-snapshot.json"
      install -m 0600 -- "$PROVIDER_RESTORE_RUNBOOK" \
        "$DB_ROLLBACK_DIR/provider-restore.runbook"
      (
        cd "$DB_ROLLBACK_DIR"
        sha256sum -- provider-snapshot.json provider-restore.runbook \
          > payload.sha256
        chmod 0600 payload.sha256
        sha256sum --check --strict payload.sha256
      )
      jq -n --arg payload_sha "$(sha256sum \
        "$DB_ROLLBACK_DIR/payload.sha256" | awk '{print $1}')" \
        '{version:1,kind:"provider",payload_manifest_sha256:$payload_sha}' \
        > "$DB_ROLLBACK_DIR/rollback.json"
      ;;
    *) exit 64 ;;
  esac
fi
chmod 0600 "$DB_ROLLBACK_DIR/rollback.json"
[[ -z "$(find -P "$DB_ROLLBACK_DIR" -xdev \
  \( -type d ! -perm 0700 -o -type f ! -perm 0600 -o \
    ! -type d ! -type f \) -print -quit)" ]]
trap '' HUP INT TERM
RESTORE_PREFLIGHT_REQUIRED=false
RESTORE_PREFLIGHT_COMPLETE=true
FRESH_PLACEHOLDERS_CREATED=false
FRESH_FAILURE_QUARANTINE=''
RESTORE_ROLLBACK_REQUIRED=false
RESTORE_TRANSACTION_COMPLETE=false
RESTORE_ROLLBACK_RUNNING=false
RESTORE_OLD_READY=false
RESTORE_OLD_ID=''
RESTORE_OLD_FD=''
RESTORE_APP_ENV_ROLLBACK_TEMP=''
RESTORE_APP_ENV_ROLLBACK_TEMP_ID=''
RESTORE_APP_ENV_ROLLBACK_TEMP_FD=''
MERGE_ATTEMPTED=false
RUNTIME_IMAGES_LOAD_STARTED=false
OLD=''
declare -a SWAPPED=()
path_present() {
  [[ -e "$1" || -L "$1" ]]
}
rollback_swapped_unit() {
  local live="$1" candidate="$2" old="$3"
  local live_present=false candidate_present=false old_present=false
  path_present "$live" && live_present=true
  path_present "$candidate" && candidate_present=true
  path_present "$old" && old_present=true
  if [[ "$live_present" == true && "$candidate_present" == true && \
    "$old_present" == false ]]; then
    return 0
  fi
  if [[ "$live_present" == true && "$candidate_present" == false && \
    "$old_present" == true ]]; then
    sudo mv -- "$live" "$candidate" || return 125
    live_present=false
    candidate_present=true
  fi
  if [[ "$live_present" == false && "$candidate_present" == true && \
    "$old_present" == true ]]; then
    sudo mv -- "$old" "$live" || return 125
  fi
  path_present "$live" && path_present "$candidate" && \
    ! path_present "$old"
}
quarantine_fresh_restore_state() {
  local path quarantine
  [[ "$FRESH_HOST" == true && "$FRESH_PLACEHOLDERS_CREATED" == true ]] || \
    return 0
  if [[ "$RESTORE_OLD_READY" == true ]]; then
    quarantine="$OLD/fresh-failed-root"
    if [[ ! -e "$quarantine" && ! -L "$quarantine" ]]; then
      mkdir -m 0700 -- "$quarantine" || return 125
    fi
  else
    if [[ -z "$FRESH_FAILURE_QUARANTINE" ]]; then
      FRESH_FAILURE_QUARANTINE="$(mktemp -d \
        ../authentik-fresh-preflight-failed.XXXXXX)" || return 125
    fi
    quarantine="$FRESH_FAILURE_QUARANTINE"
  fi
  [[ -d "$quarantine" && ! -L "$quarantine" && \
    "$(stat -Lc '%a:%d' -- "$quarantine")" == \
    "700:$(stat -Lc '%d' -- .)" ]] || return 125
  for path in appdata app.env secrets scripts/backup.cron .run.conf .env \
    docker-compose.main.yaml; do
    if path_present "$path"; then
      sudo mv -- "$path" "$quarantine/" || return 125
    fi
  done
  ! path_present appdata && ! path_present app.env && \
    ! path_present secrets && ! path_present scripts/backup.cron && \
    ! path_present .run.conf && ! path_present .env && \
    ! path_present docker-compose.main.yaml
}
cleanup_restore_app_env_temporary() {
  if [[ -z "$RESTORE_APP_ENV_ROLLBACK_TEMP" ]]; then
    return 0
  fi
  if ! path_present "$RESTORE_APP_ENV_ROLLBACK_TEMP"; then
    if [[ "$RESTORE_APP_ENV_ROLLBACK_TEMP_FD" =~ ^[0-9]+$ && \
      -e "/proc/${BASHPID}/fd/${RESTORE_APP_ENV_ROLLBACK_TEMP_FD}" ]]; then
      exec {RESTORE_APP_ENV_ROLLBACK_TEMP_FD}<&-
    fi
    RESTORE_APP_ENV_ROLLBACK_TEMP=''
    RESTORE_APP_ENV_ROLLBACK_TEMP_ID=''
    RESTORE_APP_ENV_ROLLBACK_TEMP_FD=''
    return 0
  fi
  [[ -n "$RESTORE_APP_ENV_ROLLBACK_TEMP_ID" && \
    -f "$RESTORE_APP_ENV_ROLLBACK_TEMP" && \
    ! -L "$RESTORE_APP_ENV_ROLLBACK_TEMP" && \
    "$(stat -Lc '%d:%i' -- "$RESTORE_APP_ENV_ROLLBACK_TEMP")" == \
      "$RESTORE_APP_ENV_ROLLBACK_TEMP_ID" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${RESTORE_APP_ENV_ROLLBACK_TEMP_FD}")" == \
      "$RESTORE_APP_ENV_ROLLBACK_TEMP_ID" ]] || return 125
  rm -f -- "$RESTORE_APP_ENV_ROLLBACK_TEMP" || return 125
  ! path_present "$RESTORE_APP_ENV_ROLLBACK_TEMP" || return 125
  exec {RESTORE_APP_ENV_ROLLBACK_TEMP_FD}<&-
  RESTORE_APP_ENV_ROLLBACK_TEMP=''
  RESTORE_APP_ENV_ROLLBACK_TEMP_ID=''
  RESTORE_APP_ENV_ROLLBACK_TEMP_FD=''
}
perform_restore_rollback() {
  local item live candidate old i temporary temporary_id rollback_config
  local mapping ref image_id
  local rollback_status=0
  if [[ "$RESTORE_OLD_READY" == true ]]; then
    [[ -d "$OLD" && ! -L "$OLD" && \
      "$(stat -Lc '%d:%i' -- "$OLD")" == "$RESTORE_OLD_ID" && \
      "$(stat -Lc '%d:%i' -- \
        "/proc/${BASHPID}/fd/${RESTORE_OLD_FD}")" == \
        "$RESTORE_OLD_ID" ]] || return 125
  fi
  for ((i=${#SWAPPED[@]}-1; i>=0; i--)); do
    item="${SWAPPED[$i]}"
    IFS='|' read -r live candidate old <<<"$item"
    if ! rollback_swapped_unit "$live" "$candidate" "$old"; then
      rollback_status=125
      break
    fi
  done
  [[ "$rollback_status" == 0 ]] || return 125
  if [[ "$FRESH_HOST" == true ]]; then
    quarantine_fresh_restore_state || rollback_status=125
    return "$rollback_status"
  fi
  if [[ "$RUNTIME_IMAGES_LOAD_STARTED" == true ]]; then
    for mapping in "${PRE_SWAP_IMAGE_MAP[@]}"; do
      IFS='|' read -r ref image_id <<<"$mapping"
      if [[ "$ref" == *@sha256:* ]]; then
        [[ "$(docker image inspect "$ref" --format '{{.Id}}')" == \
          "$image_id" ]] || rollback_status=125
      else
        docker image tag "$image_id" "$ref" >/dev/null || rollback_status=125
        [[ "$(docker image inspect "$ref" --format '{{.Id}}')" == \
          "$image_id" ]] || rollback_status=125
      fi
    done
  fi
  if [[ "$MERGE_ATTEMPTED" == true || \
    "$RUNTIME_IMAGES_LOAD_STARTED" == true ]]; then
    temporary="$(mktemp ./app.env.rollback.XXXXXX)" || return 125
    RESTORE_APP_ENV_ROLLBACK_TEMP="$temporary"
    if ! exec {RESTORE_APP_ENV_ROLLBACK_TEMP_FD}<"$temporary"; then
      printf 'Unbound rollback app.env temporary preserved at %q\n' \
        "$temporary" >&2
      return 125
    fi
    if ! temporary_id="$(stat -Lc '%d:%i' -- "$temporary")"; then
      exec {RESTORE_APP_ENV_ROLLBACK_TEMP_FD}<&-
      RESTORE_APP_ENV_ROLLBACK_TEMP_FD=''
      printf 'Unbound rollback app.env temporary preserved at %q\n' \
        "$temporary" >&2
      return 125
    fi
    RESTORE_APP_ENV_ROLLBACK_TEMP_ID="$temporary_id"
    if ! awk -v image="$PRE_SWAP_DIGEST" '
      BEGIN { count=0 }
      /^APP_IMAGE=/ { print "APP_IMAGE=" image; count++; next }
      { print }
      END { if (count != 1) exit 1 }
    ' "$OLD/pre-swap-app.env" \
      > "/proc/${BASHPID}/fd/${RESTORE_APP_ENV_ROLLBACK_TEMP_FD}"; then
      cleanup_restore_app_env_temporary || return 125
      return 125
    fi
    [[ -f "$temporary" && ! -L "$temporary" && \
      "$(stat -Lc '%d:%i' -- "$temporary")" == "$temporary_id" ]] || {
      cleanup_restore_app_env_temporary || return 125
      return 125
    }
    chmod "$APP_ENV_MODE" \
      "/proc/${BASHPID}/fd/${RESTORE_APP_ENV_ROLLBACK_TEMP_FD}" || {
      cleanup_restore_app_env_temporary || return 125
      return 125
    }
    [[ "$(stat -Lc '%d:%i' -- "$temporary")" == "$temporary_id" ]] || {
      cleanup_restore_app_env_temporary || return 125
      return 125
    }
    if ! mv -fT -- "$temporary" app.env; then
      cleanup_restore_app_env_temporary || return 125
      return 125
    fi
    exec {RESTORE_APP_ENV_ROLLBACK_TEMP_FD}<&-
    RESTORE_APP_ENV_ROLLBACK_TEMP=''
    RESTORE_APP_ENV_ROLLBACK_TEMP_ID=''
    RESTORE_APP_ENV_ROLLBACK_TEMP_FD=''
    run_authentik_with_inherited_operation_lock || return 125
    rollback_config="$("${COMPOSE[@]}" config --format json)" || return 125
    [[ "$(jq -er '.name' <<<"$rollback_config")" == \
      "$RECOVERY_PROJECT_NAME" ]] || return 125
    for service in app authentik-bootstrap authentik-worker; do
      [[ "$(jq -er --arg service "$service" '.services[$service].image' \
        <<<"$rollback_config")" == "$PRE_SWAP_DIGEST" ]] || return 125
    done
  fi
  return "$rollback_status"
}
abort_restore_transaction() {
  local status="$1"
  [[ "$RESTORE_ROLLBACK_RUNNING" == false ]] || exit 125
  RESTORE_ROLLBACK_RUNNING=true
  trap '' HUP INT TERM
  trap - ERR EXIT
  set +e
  if [[ "$RESTORE_ROLLBACK_REQUIRED" == true ]]; then
    perform_restore_rollback || status=125
  fi
  exit "$status"
}
abort_restore_transaction_exit() {
  local status=$?
  if [[ "$RESTORE_TRANSACTION_COMPLETE" == true || \
    "$RESTORE_ROLLBACK_REQUIRED" == false ]]; then
    exit "$status"
  fi
  (( status != 0 )) || status=125
  abort_restore_transaction "$status"
}
trap 'abort_restore_transaction 129' HUP
trap 'abort_restore_transaction 130' INT
trap 'abort_restore_transaction 143' TERM
trap 'abort_restore_transaction $?' ERR
trap abort_restore_transaction_exit EXIT
RESTORE_ROLLBACK_REQUIRED=true
"${COMPOSE[@]}" down
RUNNING_CONTAINERS="$("${COMPOSE[@]}" ps --status running -q)"
[[ -z "$RUNNING_CONTAINERS" ]]
if [[ "$FRESH_HOST" == true ]]; then
  FRESH_PLACEHOLDERS_CREATED=true
  mkdir -m 0700 -- appdata appdata/data appdata/custom-templates \
    appdata/certs secrets .run.conf
  install -m 0600 -- "$STAGE/app.env" app.env
  while IFS= read -r name; do
    install -m 0600 -- "$STAGE/secrets/$name" "secrets/$name"
  done < "$PRIVATE_DIR/expected-secrets.txt"
  install -m 0644 -- "$STAGE/scripts/backup.cron" scripts/backup.cron
  install -m 0600 -- "$RECOVERY_DIR/templates.lock" \
    .run.conf/.templates.lock
  TEMPLATE_LOCK_ID="$(stat -Lc '%d:%i' -- .run.conf/.templates.lock)"
  if [[ "$SOURCE_STATE" == present ]]; then
    install -m 0600 -- "$RECOVERY_DIR/source.lock" .run.conf/.source.lock
    SOURCE_LOCK_ID="$(stat -Lc '%d:%i' -- .run.conf/.source.lock)"
  fi
fi
LIVE_ROOT="$(readlink -e -- appdata)"
[[ -d appdata && ! -L appdata && "$LIVE_ROOT" == "$(pwd -P)/appdata" ]]
for path in app.env scripts/backup.cron .run.conf/.templates.lock; do
  [[ -f "$path" && ! -L "$path" ]]
done
for path in secrets scripts .run.conf; do
  [[ -d "$path" && ! -L "$path" ]]
done
LIVE_UNSAFE="$(find -P appdata -xdev \
  \( -type l -o -type b -o -type c -o -type p -o -type s \
    -o -type f -links +1 \) -print -quit)"
LIVE_SECRET_UNSAFE="$(find -P secrets -xdev -mindepth 1 \
  \( ! -type f -o -type f -links +1 \) -print -quit)"
[[ -z "$LIVE_UNSAFE" && -z "$LIVE_SECRET_UNSAFE" ]]
MOUNT_UNITS=(appdata secrets app.env scripts scripts/backup.cron \
  .run.conf .run.conf/.templates.lock)
if [[ "$SOURCE_STATE" == present ]]; then
  MOUNT_UNITS+=(.run.conf/.source.lock)
fi
for path in "${MOUNT_UNITS[@]}"; do
  canonical="$(readlink -e -- "$path")"
  [[ "$(findmnt --json --list --output TARGET | jq -r \
    --arg root "$canonical" \
    '[.filesystems[]?.target |
      select(. == $root or startswith($root + "/"))] | length')" == 0 ]]
done
PROJECT_DEVICE="$(stat -Lc '%d' -- .)"
for path in appdata app.env secrets scripts scripts/backup.cron \
  .run.conf .run.conf/.templates.lock \
  "$STAGE/appdata" "$STAGE/app.env" "$STAGE/secrets" \
  "$STAGE/scripts" "$STAGE/scripts/backup.cron" "$STAGE/.run.conf" \
  "$STAGE/.run.conf/.templates.lock"; do
  [[ "$(stat -Lc '%d' -- "$path")" == "$PROJECT_DEVICE" ]]
done
if [[ "$SOURCE_STATE" == present ]]; then
  [[ "$(stat -Lc '%d' -- .run.conf/.source.lock)" == "$PROJECT_DEVICE" ]]
fi
LIVE_IDS="$(stat -Lc '%d:%i %n' -- appdata appdata/data \
  appdata/custom-templates appdata/certs app.env secrets scripts/backup.cron \
  .run.conf/.templates.lock)"
[[ "$(stat -Lc '%d:%i %n' -- "$STAGE/appdata" \
  "$STAGE/appdata/data" "$STAGE/appdata/custom-templates" \
  "$STAGE/appdata/certs" "$STAGE/app.env" "$STAGE/secrets" \
  "$STAGE/scripts/backup.cron" \
  "$STAGE/.run.conf/.templates.lock")" == "$STAGE_IDS" ]]

trap '' HUP INT TERM
OLD="$(mktemp -d \
  "$RESTORE_OPERATION_PARENT/authentik-pre-restore.XXXXXX")"
if ! exec {RESTORE_OLD_FD}<"$OLD"; then
  rmdir -- "$OLD" || {
    printf 'Unbound pre-restore directory preserved at %q\n' "$OLD" >&2
  }
  exit 125
fi
if ! RESTORE_OLD_ID="$(stat -Lc '%d:%i' -- "$OLD")"; then
  exec {RESTORE_OLD_FD}<&-
  rmdir -- "$OLD" || {
    printf 'Unbound pre-restore directory preserved at %q\n' "$OLD" >&2
  }
  exit 125
fi
RESTORE_OLD_READY=true
[[ "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${RESTORE_OLD_FD}")" == \
  "$RESTORE_OLD_ID" ]]
trap 'abort_restore_transaction 129' HUP
trap 'abort_restore_transaction 130' INT
trap 'abort_restore_transaction 143' TERM
mkdir -m 0700 -- "$OLD/scripts" "$OLD/.run.conf"
[[ "$(stat -Lc '%a:%d:%i' -- "$OLD")" == \
  "700:$RESTORE_OLD_ID" ]]
mv -- "$DB_ROLLBACK_DIR" "$OLD/database"
DB_ROLLBACK_DIR="$OLD/database"
[[ "$(stat -Lc '%a:%d' -- "$DB_ROLLBACK_DIR")" == \
  "700:$PROJECT_DEVICE" ]]
[[ "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${DB_ROLLBACK_DIR_FD}")" == \
  "$DB_ROLLBACK_DIR_ID" ]]
printf '%s\n' "$PRE_SWAP_DIGEST" > "$OLD/pre-swap-authentik-digest"
chmod 0600 "$OLD/pre-swap-authentik-digest"
if [[ "$FRESH_HOST" != true ]]; then
  install -m 0600 /dev/null "$OLD/pre-swap-images.tsv"
  for mapping in "${PRE_SWAP_IMAGE_MAP[@]}"; do
    IFS='|' read -r ref image_id <<<"$mapping"
    printf '%s\t%s\n' "$ref" "$image_id" >> "$OLD/pre-swap-images.tsv"
  done
  [[ "$(wc -l < "$OLD/pre-swap-images.tsv")" == 3 ]]
fi
APP_ENV_MODE="$(stat -Lc '%a' -- app.env)"
install -m 0600 -- app.env "$OLD/pre-swap-app.env"
swap_unit() {
  local live="$1" candidate="$2" old="$3"
  SWAPPED+=("$live|$candidate|$old")
  if ! sudo mv -- "$live" "$old"; then
    return 1
  fi
  if ! sudo mv -- "$candidate" "$live"; then
    return 1
  fi
}
RUNTIME_IMAGES_LOAD_STARTED=true
docker image load --input "$RECOVERY_DIR/$RUNTIME_IMAGES" >/dev/null
verify_loaded_image() {
  local ref id expected actual
  ref="$(jq -er "$1" "$RECOVERY_DIR/versions.json")"
  id="$(jq -er "$2" "$RECOVERY_DIR/versions.json")"
  expected="$(jq -cer "$3" "$RECOVERY_DIR/versions.json")"
  [[ "$(docker image inspect "$ref" --format '{{.Id}}')" == "$id" ]]
  actual="$(docker image inspect "$ref" --format '{{json .}}' | jq -cer \
    '{os:.Os,architecture:.Architecture,variant:(.Variant // "")}')"
  [[ "$actual" == "$expected" ]]
}
verify_loaded_image '.authentik.ref' '.authentik.image_id' \
  '.authentik.platform'
verify_loaded_image '.postgresql.ref' '.postgresql.image_id' \
  '.postgresql.platform'
verify_loaded_image '.postgresql.maintenance_ref' \
  '.postgresql.maintenance_image_id' '.postgresql.maintenance_platform'
[[ "$(docker image inspect "$APP_DIGEST" --format '{{.Id}}')" == \
  "$(jq -er '.authentik.image_id' "$RECOVERY_DIR/versions.json")" ]]
[[ "$(stat -Lc '%d:%i %n' -- appdata appdata/data \
  appdata/custom-templates appdata/certs app.env secrets scripts/backup.cron \
  .run.conf/.templates.lock)" == "$LIVE_IDS" ]]
[[ "$(stat -Lc '%d:%i' -- .run.conf/.templates.lock)" == "$TEMPLATE_LOCK_ID" ]]
cmp -s -- .run.conf/.templates.lock "$RECOVERY_DIR/templates.lock"
if [[ "$SOURCE_STATE" == present ]]; then
  [[ "$(stat -Lc '%d:%i' -- .run.conf/.source.lock)" == "$SOURCE_LOCK_ID" ]]
fi
swap_unit appdata "$STAGE/appdata" "$OLD/appdata"
swap_unit app.env "$STAGE/app.env" "$OLD/app.env"
swap_unit secrets "$STAGE/secrets" "$OLD/secrets"
swap_unit scripts/backup.cron "$STAGE/scripts/backup.cron" "$OLD/scripts/backup.cron"
swap_unit .run.conf/.templates.lock "$STAGE/.run.conf/.templates.lock" \
  "$OLD/.run.conf/.templates.lock"

# Normæl locked merge only: never use --force or refresh either lock here.
MERGE_ATTEMPTED=true
run_authentik_with_inherited_operation_lock
COMPOSE=(docker compose --project-name "$RECOVERY_PROJECT_NAME" \
  --env-file .env -f "$COMPOSE_FILE")
LIVE_CONFIG="$("${COMPOSE[@]}" config --format json)"
[[ "$(jq -er '.name' <<<"$LIVE_CONFIG")" == "$RECOVERY_PROJECT_NAME" ]]
LIVE_IMAGES="$("${COMPOSE[@]}" config --images)"
grep -Fxq "$(jq -er '.postgresql.ref' \
  "$RECOVERY_DIR/versions.json")" <<<"$LIVE_IMAGES"
grep -Fxq "$(jq -er '.postgresql.maintenance_ref' \
  "$RECOVERY_DIR/versions.json")" <<<"$LIVE_IMAGES"
LIVE_LOCAL_VOLUMES="$(jq -er '
  [.volumes // {} | to_entries[] | select(.value.external != true) |
    .value.name] | sort | if length > 0 then .[] else error end' \
  <<<"$LIVE_CONFIG")"
[[ "$LIVE_LOCAL_VOLUMES" == "$RECOVERED_LOCAL_VOLUMES" ]]
[[ "$(<.run.conf/.templates.lock)" == "$TEMPLATE_REVISION" ]]
[[ "$(sha256sum .run.conf/.templates.lock | awk '{print $1}')" == \
  "$(jq -er '.locks.template_sha256' "$RECORD")" ]]
if [[ "$SOURCE_STATE" == present ]]; then
  [[ "$(stat -Lc '%d:%i' -- .run.conf/.source.lock)" == "$SOURCE_LOCK_ID" ]]
  cmp -s -- .run.conf/.source.lock "$RECOVERY_DIR/source.lock"
else
  [[ ! -e .run.conf/.source.lock && ! -L .run.conf/.source.lock ]]
fi
for service in app authentik-bootstrap authentik-worker; do
  [[ "$(jq -er --arg service "$service" '.services[$service].image' \
    <<<"$LIVE_CONFIG")" == "$APP_DIGEST" ]]
done
LIVE_SECRETS="$(yq -er '.secrets | keys | .[]' "$COMPOSE_FILE" |
  LC_ALL=C sort)"
[[ "$LIVE_SECRETS" == "$EXPECTED_SECRETS" ]]
while IFS= read -r name; do
  path="secrets/$name"
  [[ -f "$path" && ! -L "$path" && -s "$path" ]]
  [[ "$(stat -Lc '%a:%g' -- "$path")" == "640:$APP_GID" ]]
done < "$PRIVATE_DIR/expected-secrets.txt"
for leaf in appdata/data appdata/custom-templates appdata/certs; do
  [[ -z "$(sudo find -P "$leaf" -xdev \
    \( ! -uid "$APP_UID" -o ! -gid "$APP_GID" -o -type d ! -perm 0770 \
      -o -type f ! -perm 0660 \) -print -quit)" ]]
done
RESTORE_DB_GUARD_ARMED=false
RESTORE_DB_GUARD_PUBLISHED=false
RESTORE_DB_MUTATION_STARTED=false
RESTORE_COMPLETE=false
RESTORE_DB_HANDLER_RUNNING=false
RESTORE_DB_ABORT_DIR="$RESTORE_OPERATION_PARENT/authentik-restore-abort-${RESTORE_RECOVERY_ID}"
RESTORE_DB_ABORT_ID=''
RESTORE_DB_ABORT_FD=''
validate_restore_old_state() {
  [[ -d "$OLD" && ! -L "$OLD" && \
    "${OLD%/*}" == "$RESTORE_OPERATION_PARENT" && \
    "${OLD##*/}" =~ ^authentik-pre-restore\.[A-Za-z0-9]+$ && \
    "$(stat -Lc '%d:%i' -- "$OLD")" == "$RESTORE_OLD_ID" && \
    "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${RESTORE_OLD_FD}")" == \
      "$RESTORE_OLD_ID" && \
    -d "$OLD/database" && ! -L "$OLD/database" && \
    "$(stat -Lc '%d:%i' -- "$OLD/database")" == "$DB_ROLLBACK_DIR_ID" && \
    "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${DB_ROLLBACK_DIR_FD}")" == \
      "$DB_ROLLBACK_DIR_ID" ]]
}
validate_restore_db_guard() {
  validate_restore_old_state || return 125
  [[ "$RESTORE_DB_ABORT_ID" =~ ^[0-9]+:[0-9]+$ && \
    "$RESTORE_DB_ABORT_FD" =~ ^[0-9]+$ && \
    "${RESTORE_DB_ABORT_DIR%/*}" == "$RESTORE_OPERATION_PARENT" && \
    "${RESTORE_DB_ABORT_DIR##*/}" == \
      "authentik-restore-abort-${RESTORE_RECOVERY_ID}" && \
    "$(stat -Lc '%d:%i' -- "$RESTORE_OPERATION_PARENT")" == \
      "$RESTORE_OPERATION_PARENT_ID" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${RESTORE_OPERATION_PARENT_FD}")" == \
      "$RESTORE_OPERATION_PARENT_ID" && \
    -d "$RESTORE_DB_ABORT_DIR" && ! -L "$RESTORE_DB_ABORT_DIR" && \
    "$(stat -Lc '%d:%i' -- "$RESTORE_DB_ABORT_DIR")" == \
      "$RESTORE_DB_ABORT_ID" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${RESTORE_DB_ABORT_FD}")" == \
      "$RESTORE_DB_ABORT_ID" && \
    "$(stat -Lc '%a:%u:%g' -- "$RESTORE_DB_ABORT_DIR")" == \
      "700:$(id -u):$(id -g)" && \
    -f "$RESTORE_DB_ABORT_DIR/restore-abort.json" && \
    ! -L "$RESTORE_DB_ABORT_DIR/restore-abort.json" && \
    -f "$RESTORE_DB_ABORT_DIR/restore-abort.json.sha256" && \
    ! -L "$RESTORE_DB_ABORT_DIR/restore-abort.json.sha256" && \
    "$(stat -Lc '%a:%u:%g:%h' -- \
      "$RESTORE_DB_ABORT_DIR/restore-abort.json")" == \
      "600:$(id -u):$(id -g):1" && \
    "$(stat -Lc '%a:%u:%g:%h' -- \
      "$RESTORE_DB_ABORT_DIR/restore-abort.json.sha256")" == \
      "600:$(id -u):$(id -g):1" ]] || return 125
  [[ "$(<"$RESTORE_DB_ABORT_DIR/restore-abort.json.sha256")" == \
    "$(sha256sum "$RESTORE_DB_ABORT_DIR/restore-abort.json" | \
      awk '{print $1}')  restore-abort.json" ]] || return 125
  jq -e --arg recovery_id "$RESTORE_RECOVERY_ID" \
    --arg project_name "$RECOVERY_PROJECT_NAME" --arg old_path "$OLD" \
    --arg old_id "$RESTORE_OLD_ID" --arg database_id "$DB_ROLLBACK_DIR_ID" \
    --arg recovery_dir "$RECOVERY_DIR" '
    keys == ["database_id","old_id","old_path","project_name","recovery_dir",
      "recovery_id","rollback_kind","schema_version","status"] and
    .schema_version == 1 and .status == "db-restore-unresolved" and
    .recovery_id == $recovery_id and .project_name == $project_name and
    .old_path == $old_path and .old_id == $old_id and
    .database_id == $database_id and .recovery_dir == $recovery_dir and
    (.rollback_kind == "maintenance" or .rollback_kind == "provider" or
      .rollback_kind == "new-host-none")
  ' "$RESTORE_DB_ABORT_DIR/restore-abort.json" >/dev/null
}
verify_restore_db_phase_preamble() {
  [[ "$RESTORE_DB_GUARD_ARMED" == true && \
    "$RESTORE_COMPLETE" == false ]] || return 125
  validate_authentik_operation_lock || return 125
  validate_restore_db_guard
}
cleanup_restore_db_guard_staging() {
  local staging="$1" staging_id="$2" staging_fd="$3" status=0
  [[ "${staging%/*}" == "$RESTORE_OPERATION_PARENT" && \
    "${staging##*/}" =~ \
      ^\.authentik-restore-abort-${RESTORE_RECOVERY_ID}\.[A-Za-z0-9]+$ && \
    -d "$staging" && ! -L "$staging" && \
    "$(stat -Lc '%d:%i' -- "$staging")" == "$staging_id" && \
    "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${staging_fd}")" == \
      "$staging_id" && \
    "$(stat -Lc '%d:%i' -- "$RESTORE_OPERATION_PARENT")" == \
      "$RESTORE_OPERATION_PARENT_ID" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${RESTORE_OPERATION_PARENT_FD}")" == \
      "$RESTORE_OPERATION_PARENT_ID" ]] || return 125
  (cd "/proc/${BASHPID}/fd/${staging_fd}" && \
    find -P . -xdev -depth -mindepth 1 -delete) || status=125
  if [[ "$status" == 0 ]]; then
    [[ -d "$staging" && ! -L "$staging" && \
      "$(stat -Lc '%d:%i' -- "$staging")" == "$staging_id" && \
      "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${staging_fd}")" == \
        "$staging_id" ]] || status=125
  fi
  if [[ "$status" == 0 ]]; then
    rmdir -- "$staging" || status=125
  fi
  if [[ "$status" == 0 ]]; then
    exec {staging_fd}<&- || status=125
  fi
  return "$status"
}
publish_restore_db_guard() {
  local staging staging_fd staging_id rollback_kind publish_status=0
  validate_restore_old_state || return 125
  [[ ! -e "$RESTORE_DB_ABORT_DIR" && ! -L "$RESTORE_DB_ABORT_DIR" ]] || \
    return 125
  [[ -f "$OLD/database/rollback.json" && \
    ! -L "$OLD/database/rollback.json" ]] || return 125
  rollback_kind="$(jq -er '.kind | select(. == "maintenance" or
    . == "provider" or . == "new-host-none")' \
    "$OLD/database/rollback.json")" || return 125
  staging="$(mktemp -d \
    "$RESTORE_OPERATION_PARENT/.authentik-restore-abort-${RESTORE_RECOVERY_ID}.XXXXXX")" \
    || return 125
  if ! exec {staging_fd}<"$staging"; then
    rmdir -- "$staging" || return 125
    return 125
  fi
  if ! staging_id="$(stat -Lc '%d:%i' -- "$staging")"; then
    exec {staging_fd}<&-
    rmdir -- "$staging" || return 125
    return 125
  fi
  if [[ "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${staging_fd}")" != \
    "$staging_id" || \
    "$(stat -Lc '%a:%u:%g:%h' -- "$staging")" != \
      "700:$(id -u):$(id -g):2" ]]; then
    cleanup_restore_db_guard_staging "$staging" "$staging_id" \
      "$staging_fd" || return 125
    return 125
  fi
  if ! jq -n --arg recovery_id "$RESTORE_RECOVERY_ID" \
    --arg project_name "$RECOVERY_PROJECT_NAME" --arg old_path "$OLD" \
    --arg old_id "$RESTORE_OLD_ID" --arg rollback_kind "$rollback_kind" \
    --arg database_id "$DB_ROLLBACK_DIR_ID" --arg recovery_dir "$RECOVERY_DIR" \
    '{schema_version:1,status:"db-restore-unresolved",recovery_id:$recovery_id,
      project_name:$project_name,old_path:$old_path,old_id:$old_id,
      database_id:$database_id,recovery_dir:$recovery_dir,
      rollback_kind:$rollback_kind}' \
    > "$staging/restore-abort.json"; then
    cleanup_restore_db_guard_staging "$staging" "$staging_id" \
      "$staging_fd" || return 125
    return 125
  fi
  if ! chmod 0600 "$staging/restore-abort.json"; then
    cleanup_restore_db_guard_staging "$staging" "$staging_id" \
      "$staging_fd" || return 125
    return 125
  fi
  if ! (cd "$staging" && sha256sum -- restore-abort.json \
    > restore-abort.json.sha256 && chmod 0600 restore-abort.json.sha256 && \
    sha256sum --check --strict restore-abort.json.sha256); then
    cleanup_restore_db_guard_staging "$staging" "$staging_id" \
      "$staging_fd" || return 125
    return 125
  fi
  if ! sync -f -- "$staging"; then
    cleanup_restore_db_guard_staging "$staging" "$staging_id" \
      "$staging_fd" || return 125
    return 125
  fi
  mv -Tn -- "$staging" "$RESTORE_DB_ABORT_DIR" || publish_status=125
  if [[ ! -e "$staging" && ! -L "$staging" ]]; then
    RESTORE_DB_ABORT_ID="$staging_id"
    RESTORE_DB_ABORT_FD="$staging_fd"
  fi
  if [[ -e "$staging" || -L "$staging" ]]; then
    cleanup_restore_db_guard_staging "$staging" "$staging_id" \
      "$staging_fd" || return 125
    return 125
  fi
  [[ -d "$RESTORE_DB_ABORT_DIR" && ! -L "$RESTORE_DB_ABORT_DIR" && \
    "$(stat -Lc '%d:%i' -- "$RESTORE_DB_ABORT_DIR")" == "$staging_id" && \
    "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${staging_fd}")" == \
      "$staging_id" ]] || return 125
  RESTORE_DB_GUARD_PUBLISHED=true
  RESTORE_ROLLBACK_REQUIRED=false
  RESTORE_TRANSACTION_COMPLETE=true
  trap - ERR EXIT
  trap 'abort_restore_database_phase 129' HUP
  trap 'abort_restore_database_phase 130' INT
  trap 'abort_restore_database_phase 143' TERM
  trap 'abort_restore_database_phase $?' ERR
  trap abort_restore_database_phase_exit EXIT
  RESTORE_DB_GUARD_ARMED=true
  [[ "$publish_status" == 0 ]] || abort_restore_database_phase 125
  sync -f -- "$RESTORE_OPERATION_PARENT" || \
    abort_restore_database_phase 125
  validate_restore_db_guard || abort_restore_database_phase 125
}
resolve_restore_db_guard() {
  local resolved status=0
  validate_restore_db_guard || return 125
  resolved="${RESTORE_DB_ABORT_DIR}-resolved-$(date -u +%Y%m%dT%H%M%SZ)"
  [[ ! -e "$resolved" && ! -L "$resolved" ]] || return 125
  mv -Tn -- "$RESTORE_DB_ABORT_DIR" "$resolved" || status=125
  if [[ "$status" == 0 ]]; then
    [[ ! -e "$RESTORE_DB_ABORT_DIR" && ! -L "$RESTORE_DB_ABORT_DIR" && \
      -d "$resolved" && ! -L "$resolved" && \
      "$(stat -Lc '%d:%i' -- "$resolved")" == "$RESTORE_DB_ABORT_ID" && \
      "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${RESTORE_DB_ABORT_FD}")" == \
        "$RESTORE_DB_ABORT_ID" ]] || status=125
  fi
  if [[ "$status" == 0 ]]; then
    sync -f -- "$RESTORE_OPERATION_PARENT" || status=125
  fi
  if [[ "$status" != 0 && -d "$resolved" && ! -L "$resolved" && \
    "$(stat -Lc '%d:%i' -- "$resolved")" == "$RESTORE_DB_ABORT_ID" && \
    ! -e "$RESTORE_DB_ABORT_DIR" && ! -L "$RESTORE_DB_ABORT_DIR" ]]; then
    mv -Tn -- "$resolved" "$RESTORE_DB_ABORT_DIR" || return 125
    [[ -d "$RESTORE_DB_ABORT_DIR" && ! -L "$RESTORE_DB_ABORT_DIR" && \
      "$(stat -Lc '%d:%i' -- "$RESTORE_DB_ABORT_DIR")" == \
        "$RESTORE_DB_ABORT_ID" ]] || return 125
    sync -f -- "$RESTORE_OPERATION_PARENT" || return 125
  fi
  [[ "$status" == 0 ]] || return 125
  RESTORE_DB_RESOLVED_DIR="$resolved"
}
abort_restore_database_phase() {
  local status="$1" running id
  local -a running_ids=()
  [[ "$RESTORE_DB_HANDLER_RUNNING" == false ]] || exit 125
  RESTORE_DB_HANDLER_RUNNING=true
  trap '' HUP INT TERM
  trap - ERR EXIT
  set +e
  running="$(docker container ls --no-trunc --quiet --filter \
    "label=com.docker.compose.project=${RECOVERY_PROJECT_NAME}")" || status=125
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    [[ "$id" =~ ^[0-9a-f]{64}$ ]] || {
      status=125
      continue
    }
    running_ids+=("$id")
  done <<< "$running"
  if (( ${#running_ids[@]} > 0 )); then
    docker stop -t 60 "${running_ids[@]}" >/dev/null || status=125
  fi
  "${COMPOSE[@]}" down || status=125
  running="$(docker container ls --no-trunc --quiet --filter \
    "label=com.docker.compose.project=${RECOVERY_PROJECT_NAME}")" || status=125
  [[ -z "$running" ]] || status=125
  validate_restore_db_guard || status=125
  printf 'Database restore interrupted; recovery evidence is preserved at %s\n' \
    "$RESTORE_DB_ABORT_DIR" >&2
  exit "$status"
}
abort_restore_database_phase_exit() {
  local status=$?
  if [[ "$RESTORE_COMPLETE" == true || \
    "$RESTORE_DB_GUARD_ARMED" == false ]]; then
    exit "$status"
  fi
  (( status != 0 )) || status=125
  abort_restore_database_phase "$status"
}
trap '' HUP INT TERM
publish_restore_db_guard
[[ "$RESTORE_DB_GUARD_PUBLISHED" == true && \
  "$RESTORE_DB_GUARD_ARMED" == true && \
  "$RESTORE_ROLLBACK_REQUIRED" == false && \
  "$RESTORE_TRANSACTION_COMPLETE" == true ]]
if ! rmdir -- "$STAGE/scripts" "$STAGE/.run.conf" "$STAGE"; then
  printf 'Verified file swap committed; empty stage cleanup remains at %q\n' \
    "$STAGE" >&2
fi
```

The stæge begins mode `0700` with recovered sensitive files mode `0600`.
Before swæp, the three bind-mount leæves receive the documented runtime
ownership/modes; the normæl `run.sh` merge then normælizes rendered secrets to
`APP_GID`/`0640`. The postconditions verify both. Keep `OLD`, the restored
cændidæte, ænd æ mætching pre-swæp dætæbæse snæpshot until finæl proof succeeds.

### Restore exæctly one PostgreSQL formæt

Keep the sæme strict shell open from file stæging through the selected
dætæbæse æpply ænd every finæl proof. Eæch læter code fence deliberætely
requires the still-held project, pærent, `OLD`, dætæbæse, ænd æctive-guærd
descriptors; pæsting one into æ fresh shell must fæil before mutætion.

Copy the selected bundle næmed by `recovery.json` into `restore/` with its
strict sidecær ænd `bundle_*.sha256`; physicæl restore ælso needs its
`.manifest`. Follow the complete
[`postgresql_maintenance` restore contræct](../templates/postgresql_maintenance/README.md#restore).
Choose **one** pæth; never run both.

First prove thæt the locæl built dætæbæse imæges still equæl the bound
version record:

```bash
verify_restore_db_phase_preamble
PROJECT_NAME="$("${COMPOSE[@]}" config --format json | jq -er '.name')"
[[ "$(docker image inspect "${PROJECT_NAME}-postgresql" --format '{{.Id}}')" == \
  "$(jq -er '.postgresql.image_id' "$RECOVERY_DIR/versions.json")" ]]
[[ "$(docker image inspect "${PROJECT_NAME}-postgresql_maintenance" \
  --format '{{.Id}}')" == "$(jq -er \
  '.postgresql.maintenance_image_id' "$RECOVERY_DIR/versions.json")" ]]
```

For æ **physicæl** restore, PostgreSQL ænd every writer/mæintenænce service
must remæin stopped. Dry-run uses the reæd-only bæse service; only æpply uses
the versioned write override:

```bash
verify_restore_db_phase_preamble
PHYSICAL_ID="$(jq -er '.postgresql.physical.id' "$RECORD")"
PHYSICAL="restore/full_${PHYSICAL_ID}.tar.zst"
PHYSICAL_MANIFEST="restore/full_${PHYSICAL_ID}.manifest"
[[ "$(sha256sum "$PHYSICAL" | awk '{print $1}')" == \
  "$(jq -er '.postgresql.physical.sha256' "$RECORD")" ]]
[[ "$(sha256sum "$PHYSICAL_MANIFEST" | awk '{print $1}')" == \
  "$(jq -er '.postgresql.physical.manifest_sha256' "$RECORD")" ]]
RUNNING="$("${COMPOSE[@]}" ps --status running -q)"
[[ -z "$RUNNING" ]]
"${COMPOSE[@]}" -f docker-compose.postgresql_maintenance.restore.yaml.example \
  config --quiet
"${COMPOSE[@]}" run --rm \
  --no-deps --pull never -e POSTGRES_RESTORE_BACKUP_ID="$PHYSICAL_ID" \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
  postgresql_maintenance restore --dry-run
verify_restore_db_phase_preamble
RESTORE_DB_MUTATION_STARTED=true
"${COMPOSE[@]}" -f docker-compose.postgresql_maintenance.restore.yaml.example \
  run --rm \
  --no-deps --pull never -e POSTGRES_RESTORE_BACKUP_ID="$PHYSICAL_ID" \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
  postgresql_maintenance restore
```

For æ **logicæl** restore, only PostgreSQL is running ænd heælthy; server,
worker, bootstræp, ænd scheduled mæintenænce stæy stopped. Both explicit
populæted-dætæbæse replæcement guærds ære required:

```bash
verify_restore_db_phase_preamble
LOGICAL_ID="$(jq -er '.postgresql.logical.id' "$RECORD")"
LOGICAL="restore/dump_${LOGICAL_ID}.dump.zst"
[[ "$(sha256sum "$LOGICAL" | awk '{print $1}')" == \
  "$(jq -er '.postgresql.logical.sha256' "$RECORD")" ]]
"${COMPOSE[@]}" up -d --wait \
  --wait-timeout 120 --no-build --pull never postgresql
POSTGRES_CONTAINER="$("${COMPOSE[@]}" ps -q postgresql)"
[[ "$(docker inspect --format '{{.Image}}' "$POSTGRES_CONTAINER")" == \
  "$(jq -er '.postgresql.image_id' "$RECOVERY_DIR/versions.json")" ]]
UNEXPECTED="$("${COMPOSE[@]}" ps --status running -q \
  app authentik-bootstrap authentik-worker \
  postgresql_maintenance)"
[[ -z "$UNEXPECTED" ]]
for mode in dry-run apply; do
  restore_args=()
  if [[ "$mode" == apply ]]; then
    verify_restore_db_phase_preamble
    RESTORE_DB_MUTATION_STARTED=true
  else
    restore_args+=(--dry-run)
  fi
  "${COMPOSE[@]}" run --rm \
    --no-deps --pull never -e POSTGRES_RESTORE_BACKUP_ID="$LOGICAL_ID" \
    -e POSTGRES_RESTORE_RECREATE_DATABASE=true \
    -e POSTGRES_RESTORE_CONFIRM_DATABASE_REPLACEMENT=true \
    postgresql_maintenance restore-dump "${restore_args[@]}"
done
```

Do not interrupt æ quiet long restore. Dry-run ænd æpply must eæch report
explicit success ænd exit zero. Before either pæth, confirm the locæl
PostgreSQL ænd mæintenænce imæge IDs equæl those in bound `versions.json`;
`--no-build --pull never` then prevents re-resolution.

Æfter one successful dætæbæse pæth:

```bash
verify_restore_db_phase_preamble
"${COMPOSE[@]}" up -d --wait --wait-timeout 120 \
  --no-build --pull never postgresql
"${COMPOSE[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never app authentik-worker
BOOTSTRAP_ID="$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)"
APP_ID="$("${COMPOSE[@]}" ps -q app)"
WORKER_ID="$("${COMPOSE[@]}" ps -q authentik-worker)"
for id in "$APP_ID" "$WORKER_ID" "$BOOTSTRAP_ID"; do
  [[ "$id" =~ ^[0-9a-f]{64}$ ]]
done
[[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
  "$BOOTSTRAP_ID")" == exited:0 ]]
for id in "$APP_ID" "$WORKER_ID" "$BOOTSTRAP_ID"; do
  [[ "$(docker inspect --format '{{.Image}}' "$id")" == \
    "$(jq -er '.authentik.image_id' "$RECOVERY_DIR/versions.json")" ]]
done
"${COMPOSE[@]}" up -d --no-build --pull never postgresql_maintenance
"${COMPOSE[@]}" exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh full
"${COMPOSE[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never postgresql_maintenance
trap '' HUP INT TERM
verify_restore_db_phase_preamble
resolve_restore_db_guard
RESTORE_COMPLETE=true
RESTORE_DB_GUARD_ARMED=false
trap - ERR EXIT
exec {RESTORE_DB_ABORT_FD}<&-
exec {DB_ROLLBACK_DIR_FD}<&-
exec {RESTORE_OLD_FD}<&-
exec {RESTORE_OPERATION_PARENT_FD}<&-
exec {AUTHENTIK_OPERATION_LOCK_FD}<&-
unset AUTHENTIK_OPERATION_LOCK_FD AUTHENTIK_OPERATION_ROOT
trap - HUP INT TERM
```

If the dætæbæse-guærd træp exits, the shell descriptors disæppeær but the
æctive sibling mærker remæins duræble. Do not bypæss or delete it. Run the
following **Restore-Æbort Recovery** from `Authentik/` in one strict shell.
It reæcquires the project lock before its first mutætion, æccepts exæctly one
selected restore mærker plus æt most one sæme-ID updæte mærker, rebinds every
recovery object by pæth ænd descriptor identity, ænd proves the entire Compose
project stopped. Æ foreign, multiple, hidden, symbolic, or mælformed entry
fæils closed. The sæme-ID updæte mærker is not resolved here; finish its
sepæræte recovery only æfter this restore mærker is resolved.

```bash
set -euo pipefail
umask 077
AUTHENTIK_OPERATION_ROOT="$(pwd -P)"
validate_authentik_operation_lock() {
  [[ "$AUTHENTIK_OPERATION_ROOT" == "$(pwd -P)" && \
    "$AUTHENTIK_OPERATION_LOCK_FD" =~ ^[0-9]+$ && \
    "$(readlink -e -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_ROOT" && \
    "$(stat -Lc '%d:%i' -- "$AUTHENTIK_OPERATION_ROOT")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" ]] || return 125
  flock -n -x "$AUTHENTIK_OPERATION_LOCK_FD" || return 125
  [[ "$AUTHENTIK_OPERATION_ROOT" == "$(pwd -P)" && \
    "$(readlink -e -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_ROOT" && \
    "$(stat -Lc '%d:%i' -- "$AUTHENTIK_OPERATION_ROOT")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" ]] || return 125
}
acquire_authentik_operation_lock() {
  [[ -d "$AUTHENTIK_OPERATION_ROOT" && \
    ! -L "$AUTHENTIK_OPERATION_ROOT" && \
    "$(readlink -e -- .)" == "$AUTHENTIK_OPERATION_ROOT" ]] || return 125
  AUTHENTIK_OPERATION_LOCK_IDENTITY="$(stat -Lc '%d:%i' -- \
    "$AUTHENTIK_OPERATION_ROOT")" || return 125
  if [[ -z "${AUTHENTIK_OPERATION_LOCK_FD:-}" ]]; then
    exec {AUTHENTIK_OPERATION_LOCK_FD}<"$AUTHENTIK_OPERATION_ROOT" || \
      return 125
  fi
  [[ "$AUTHENTIK_OPERATION_LOCK_FD" =~ ^[0-9]+$ ]] || return 125
  validate_authentik_operation_lock
}
acquire_authentik_operation_lock
run_authentik_with_inherited_operation_lock() {
  validate_authentik_operation_lock || return 125
  (
    cd .. || exit 125
    RUN_INHERITED_PROJECT_LOCK_FD="$AUTHENTIK_OPERATION_LOCK_FD" \
    RUN_INHERITED_PROJECT_LOCK_PATH="$AUTHENTIK_OPERATION_ROOT" \
    RUN_INHERITED_PROJECT_LOCK_IDENTITY="$AUTHENTIK_OPERATION_LOCK_IDENTITY" \
      ./run.sh Authentik
  ) || return 125
  validate_authentik_operation_lock
}
RESTORE_OPERATION_PARENT="$(readlink -e -- ..)"
exec {RESTORE_OPERATION_PARENT_FD}<"$RESTORE_OPERATION_PARENT"
RESTORE_OPERATION_PARENT_ID="$(stat -Lc '%d:%i' -- \
  "$RESTORE_OPERATION_PARENT")"
COMPOSE=(docker compose --env-file .env -f docker-compose.main.yaml)
RESTORE_ABORT_CONFIG="$("${COMPOSE[@]}" config --format json)"
RECOVERY_PROJECT_NAME="$(jq -er \
  '.name | select(test("^[a-z0-9][a-z0-9_-]*$"))' \
  <<<"$RESTORE_ABORT_CONFIG")"
RESTORE_ABORT_RECOVERY_REQUIRED=false
RESTORE_ABORT_RECOVERY_COMPLETE=false
RESTORE_ABORT_RECOVERY_HANDLER_RUNNING=false
RESTORE_ABORT_RECOVERY_BOUND=false
RESTORE_ABORT_INVENTORY=''
RESTORE_ABORT_INVENTORY_ID=''
RESTORE_ABORT_INVENTORY_FD=''
RESTORE_DB_ABORT_DIR=''
RESTORE_DB_ABORT_ID=''
RESTORE_DB_ABORT_FD=''
RESTORE_RECOVERY_ID=''
OLD=''
RESTORE_OLD_ID=''
RESTORE_OLD_FD=''
DB_ROLLBACK_DIR=''
DB_ROLLBACK_DIR_ID=''
DB_ROLLBACK_DIR_FD=''
RECOVERY_DIR=''
RESTORE_RECOVERY_DIR_ID=''
RESTORE_RECOVERY_DIR_FD=''
RESTORE_ROLLBACK_KIND=''
RESTORE_DB_MUTATION_STARTED=false
RESTORE_DB_RESOLVED_DIR=''
RESTORE_DB_RECORD_FD_PATH=''
RESTORE_ABORT_FAILED_LIVE=''
RESTORE_ABORT_FAILED_LIVE_ID=''
RESTORE_ABORT_FAILED_LIVE_FD=''
RESTORE_ABORT_FILES_BOUND=false
RESTORE_ABORT_FILES_ROLLED_BACK=false
RESTORE_ABORT_ENV_TEMP=''
RESTORE_ABORT_ENV_TEMP_ID=''
RESTORE_ABORT_ENV_TEMP_FD=''
declare -A RESTORE_DB_FILE_FDS=()
declare -A RESTORE_DB_FILE_IDS=()
declare -A RESTORE_DB_FILE_METADATA=()
declare -a RESTORE_DB_FILE_NAMES=()
cleanup_restore_abort_recovery_inventory() {
  local status=0
  [[ -n "$RESTORE_ABORT_INVENTORY" ]] || return 0
  if [[ -f "$RESTORE_ABORT_INVENTORY" && \
    ! -L "$RESTORE_ABORT_INVENTORY" && \
    "$(stat -Lc '%d:%i' -- "$RESTORE_ABORT_INVENTORY")" == \
      "$RESTORE_ABORT_INVENTORY_ID" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${RESTORE_ABORT_INVENTORY_FD}")" == \
      "$RESTORE_ABORT_INVENTORY_ID" ]]; then
    rm -f -- "$RESTORE_ABORT_INVENTORY" || status=125
  else
    status=125
  fi
  if [[ "$status" == 0 ]]; then
    exec {RESTORE_ABORT_INVENTORY_FD}<&- || status=125
    RESTORE_ABORT_INVENTORY=''
    RESTORE_ABORT_INVENTORY_ID=''
    RESTORE_ABORT_INVENTORY_FD=''
  fi
  return "$status"
}
validate_restore_abort_database_file() {
  local name="$1" path fd fd_path
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 125
  fd="${RESTORE_DB_FILE_FDS[$name]:-}"
  [[ "$fd" =~ ^[0-9]+$ && \
    "${RESTORE_DB_FILE_IDS[$name]:-}" =~ ^[0-9]+:[0-9]+$ && \
    -e "/proc/${BASHPID}/fd/${fd}" ]] || return 125
  path="$DB_ROLLBACK_DIR/$name"
  fd_path="/proc/${BASHPID}/fd/${fd}"
  [[ -f "$path" && ! -L "$path" && -f "$fd_path" && \
    "$(stat -Lc '%d:%i' -- "$path")" == \
      "${RESTORE_DB_FILE_IDS[$name]}" && \
    "$(stat -Lc '%d:%i' -- "$fd_path")" == \
      "${RESTORE_DB_FILE_IDS[$name]}" && \
    "$(stat -Lc '%s:%a:%u:%g:%h' -- "$path")" == \
      "${RESTORE_DB_FILE_METADATA[$name]}" && \
    "$(stat -Lc '%s:%a:%u:%g:%h' -- "$fd_path")" == \
      "${RESTORE_DB_FILE_METADATA[$name]}" ]]
}
pin_restore_abort_database_files() {
  local candidate name fd id metadata expected_count=0
  local rollback_fd physical_id logical_id
  local -a expected=()
  : > "/proc/${BASHPID}/fd/${RESTORE_ABORT_INVENTORY_FD}" || return 125
  find -P "$DB_ROLLBACK_DIR" -mindepth 1 -maxdepth 1 -print0 \
    > "/proc/${BASHPID}/fd/${RESTORE_ABORT_INVENTORY_FD}" || return 125
  while IFS= read -r -d '' candidate; do
    name="${candidate##*/}"
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && \
      -f "$candidate" && ! -L "$candidate" && \
      -z "${RESTORE_DB_FILE_FDS[$name]:-}" ]] || return 125
    exec {fd}<"$candidate" || return 125
    id="$(stat -Lc '%d:%i' -- "$candidate")" || return 125
    metadata="$(stat -Lc '%s:%a:%u:%g:%h' -- "$candidate")" || return 125
    [[ -f "$candidate" && ! -L "$candidate" && \
      "$metadata" =~ ^[0-9]+:600:$(id -u):$(id -g):1$ && \
      "$(stat -Lc '%d:%i' -- "$candidate")" == "$id" && \
      "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${fd}")" == "$id" && \
      "$(stat -Lc '%s:%a:%u:%g:%h' -- \
        "/proc/${BASHPID}/fd/${fd}")" == "$metadata" ]] || return 125
    RESTORE_DB_FILE_FDS["$name"]="$fd"
    RESTORE_DB_FILE_IDS["$name"]="$id"
    RESTORE_DB_FILE_METADATA["$name"]="$metadata"
    RESTORE_DB_FILE_NAMES+=("$name")
  done < "$RESTORE_ABORT_INVENTORY"
  rollback_fd="${RESTORE_DB_FILE_FDS[rollback.json]:-}"
  [[ "$rollback_fd" =~ ^[0-9]+$ ]] || return 125
  RESTORE_DB_RECORD_FD_PATH="/proc/${BASHPID}/fd/${rollback_fd}"
  validate_restore_abort_database_file rollback.json || return 125
  [[ "$(jq -er '.kind' "$RESTORE_DB_RECORD_FD_PATH")" == \
    "$RESTORE_ROLLBACK_KIND" ]] || return 125
  case "$RESTORE_ROLLBACK_KIND" in
    maintenance)
      physical_id="$(jq -er '.physical_id |
        select(test("^[0-9]{8}_[0-9]{1,9}$"))' \
        "$RESTORE_DB_RECORD_FD_PATH")" || return 125
      logical_id="$(jq -er '.logical_id |
        select(test("^[0-9]{8}_[0-9]{6}$"))' \
        "$RESTORE_DB_RECORD_FD_PATH")" || return 125
      expected=(rollback.json payload.sha256 \
        "full_${physical_id}.tar.zst" \
        "full_${physical_id}.tar.zst.sha256" \
        "bundle_full_${physical_id}.sha256" \
        "full_${physical_id}.manifest" \
        "dump_${logical_id}.dump.zst" \
        "dump_${logical_id}.dump.zst.sha256" \
        "bundle_dump_${logical_id}.sha256")
      ;;
    provider)
      expected=(rollback.json payload.sha256 provider-snapshot.json \
        provider-restore.runbook)
      ;;
    new-host-none)
      expected=(rollback.json)
      ;;
    *) return 125 ;;
  esac
  for name in "${expected[@]}"; do
    [[ -n "${RESTORE_DB_FILE_FDS[$name]:-}" ]] || return 125
    ((expected_count+=1))
  done
  (( expected_count == ${#RESTORE_DB_FILE_FDS[@]} ))
}
validate_restore_abort_payload() {
  local line digest name payload_fd count=0 expected_count
  local -A seen=()
  validate_restore_abort_database_file payload.sha256 || return 125
  payload_fd="${RESTORE_DB_FILE_FDS[payload.sha256]}"
  while IFS= read -r line; do
    [[ "$line" =~ ^([0-9a-f]{64})\ \ ([A-Za-z0-9][A-Za-z0-9._-]*)$ ]] || \
      return 125
    digest="${BASH_REMATCH[1]}"
    name="${BASH_REMATCH[2]}"
    [[ "$name" != rollback.json && "$name" != payload.sha256 && \
      -z "${seen[$name]:-}" ]] || return 125
    validate_restore_abort_database_file "$name" || return 125
    [[ "$(sha256sum \
      "/proc/${BASHPID}/fd/${RESTORE_DB_FILE_FDS[$name]}" | \
      awk '{print $1}')" == "$digest" ]] || return 125
    seen["$name"]=true
    ((count+=1))
  done < "/proc/${BASHPID}/fd/${payload_fd}"
  expected_count=$(( ${#RESTORE_DB_FILE_FDS[@]} - 2 ))
  (( count == expected_count ))
}
close_restore_abort_database_files() {
  local name fd status=0
  for name in "${RESTORE_DB_FILE_NAMES[@]}"; do
    validate_restore_abort_database_file "$name" || {
      status=125
      continue
    }
    fd="${RESTORE_DB_FILE_FDS[$name]}"
    exec {fd}<&- || status=125
  done
  if [[ "$status" == 0 ]]; then
    RESTORE_DB_FILE_NAMES=()
    RESTORE_DB_FILE_FDS=()
    RESTORE_DB_FILE_IDS=()
    RESTORE_DB_FILE_METADATA=()
  fi
  return "$status"
}
validate_restore_abort_recovery_state() {
  local candidate name json_count=0 sidecar_count=0
  [[ "$RESTORE_ABORT_RECOVERY_BOUND" == true && \
    "$AUTHENTIK_OPERATION_ROOT" == "$(pwd -P)" && \
    "$AUTHENTIK_OPERATION_LOCK_FD" =~ ^[0-9]+$ && \
    "$(readlink -e -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_ROOT" && \
    "$(stat -Lc '%d:%i' -- "$RESTORE_OPERATION_PARENT")" == \
      "$RESTORE_OPERATION_PARENT_ID" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${RESTORE_OPERATION_PARENT_FD}")" == \
      "$RESTORE_OPERATION_PARENT_ID" && \
    -d "$RESTORE_DB_ABORT_DIR" && ! -L "$RESTORE_DB_ABORT_DIR" && \
    "$(stat -Lc '%d:%i' -- "$RESTORE_DB_ABORT_DIR")" == \
      "$RESTORE_DB_ABORT_ID" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${RESTORE_DB_ABORT_FD}")" == \
      "$RESTORE_DB_ABORT_ID" && \
    -d "$OLD" && ! -L "$OLD" && \
    "$(stat -Lc '%d:%i' -- "$OLD")" == "$RESTORE_OLD_ID" && \
    "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${RESTORE_OLD_FD}")" == \
      "$RESTORE_OLD_ID" && \
    -d "$DB_ROLLBACK_DIR" && ! -L "$DB_ROLLBACK_DIR" && \
    "$(stat -Lc '%d:%i' -- "$DB_ROLLBACK_DIR")" == \
      "$DB_ROLLBACK_DIR_ID" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${DB_ROLLBACK_DIR_FD}")" == \
      "$DB_ROLLBACK_DIR_ID" && \
    -d "$RECOVERY_DIR" && ! -L "$RECOVERY_DIR" && \
    "$(stat -Lc '%d:%i' -- "$RECOVERY_DIR")" == \
      "$RESTORE_RECOVERY_DIR_ID" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${RESTORE_RECOVERY_DIR_FD}")" == \
      "$RESTORE_RECOVERY_DIR_ID" && \
    -f "$RESTORE_ABORT_INVENTORY" && ! -L "$RESTORE_ABORT_INVENTORY" && \
    "$(stat -Lc '%d:%i' -- "$RESTORE_ABORT_INVENTORY")" == \
      "$RESTORE_ABORT_INVENTORY_ID" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${RESTORE_ABORT_INVENTORY_FD}")" == \
      "$RESTORE_ABORT_INVENTORY_ID" ]] || return 125
  if [[ "$RESTORE_ABORT_FILES_BOUND" == true ]]; then
    [[ "$RESTORE_ABORT_FAILED_LIVE" == "$OLD/failed-live" && \
      -d "$RESTORE_ABORT_FAILED_LIVE" && \
      ! -L "$RESTORE_ABORT_FAILED_LIVE" && \
      "$(stat -Lc '%d:%i' -- "$RESTORE_ABORT_FAILED_LIVE")" == \
        "$RESTORE_ABORT_FAILED_LIVE_ID" && \
      "$(stat -Lc '%d:%i' -- \
        "/proc/${BASHPID}/fd/${RESTORE_ABORT_FAILED_LIVE_FD}")" == \
        "$RESTORE_ABORT_FAILED_LIVE_ID" && \
      "$(stat -Lc '%a:%u:%g' -- "$RESTORE_ABORT_FAILED_LIVE")" == \
        "700:$(id -u):$(id -g)" ]] || return 125
  fi
  validate_authentik_operation_lock || return 125
  : > "/proc/${BASHPID}/fd/${RESTORE_ABORT_INVENTORY_FD}" || return 125
  find -P "$RESTORE_DB_ABORT_DIR" -mindepth 1 -maxdepth 1 -print0 \
    > "/proc/${BASHPID}/fd/${RESTORE_ABORT_INVENTORY_FD}" || return 125
  while IFS= read -r -d '' candidate; do
    name="${candidate##*/}"
    case "$name" in
      restore-abort.json) ((json_count+=1)) ;;
      restore-abort.json.sha256) ((sidecar_count+=1)) ;;
      *) return 125 ;;
    esac
    [[ -f "$candidate" && ! -L "$candidate" && \
      "$(stat -Lc '%a:%u:%g:%h' -- "$candidate")" == \
        "600:$(id -u):$(id -g):1" ]] || return 125
  done < "$RESTORE_ABORT_INVENTORY"
  (( json_count == 1 && sidecar_count == 1 )) || return 125
  [[ "$(<"$RESTORE_DB_ABORT_DIR/restore-abort.json.sha256")" == \
    "$(sha256sum "$RESTORE_DB_ABORT_DIR/restore-abort.json" | \
      awk '{print $1}')  restore-abort.json" ]] || return 125
  jq -e --arg recovery_id "$RESTORE_RECOVERY_ID" \
    --arg project_name "$RECOVERY_PROJECT_NAME" --arg old_path "$OLD" \
    --arg old_id "$RESTORE_OLD_ID" --arg database_id "$DB_ROLLBACK_DIR_ID" \
    --arg recovery_dir "$RECOVERY_DIR" --arg kind "$RESTORE_ROLLBACK_KIND" '
    keys == ["database_id","old_id","old_path","project_name","recovery_dir",
      "recovery_id","rollback_kind","schema_version","status"] and
    .schema_version == 1 and .status == "db-restore-unresolved" and
    .recovery_id == $recovery_id and .project_name == $project_name and
    .old_path == $old_path and .old_id == $old_id and
    .database_id == $database_id and .recovery_dir == $recovery_dir and
    .rollback_kind == $kind
  ' "$RESTORE_DB_ABORT_DIR/restore-abort.json" >/dev/null || return 125
  [[ -f "$RECOVERY_DIR/recovery.json" && \
    ! -L "$RECOVERY_DIR/recovery.json" && \
    -f "$RECOVERY_DIR/recovery.json.sha256" && \
    ! -L "$RECOVERY_DIR/recovery.json.sha256" ]] || return 125
  [[ "$(<"$RECOVERY_DIR/recovery.json.sha256")" == \
    "$(sha256sum "$RECOVERY_DIR/recovery.json" | awk '{print $1}')  recovery.json" ]] \
    || return 125
  jq -e --arg id "$RESTORE_RECOVERY_ID" \
    --arg project "$RECOVERY_PROJECT_NAME" \
    '.version == 2 and .id == $id and .project_name == $project' \
    "$RECOVERY_DIR/recovery.json" >/dev/null || return 125
  [[ "$RESTORE_DB_RECORD_FD_PATH" == \
    "/proc/${BASHPID}/fd/${RESTORE_DB_FILE_FDS[rollback.json]}" ]] || \
    return 125
  validate_restore_abort_database_file rollback.json || return 125
  for name in "${RESTORE_DB_FILE_NAMES[@]}"; do
    validate_restore_abort_database_file "$name" || return 125
  done
  [[ "$(jq -er '.kind' "$RESTORE_DB_RECORD_FD_PATH")" == \
      "$RESTORE_ROLLBACK_KIND" ]]
}
cleanup_restore_abort_env_temp() {
  local status=0
  [[ -n "$RESTORE_ABORT_ENV_TEMP" ]] || return 0
  if [[ ! -e "$RESTORE_ABORT_ENV_TEMP" && \
    ! -L "$RESTORE_ABORT_ENV_TEMP" ]]; then
    if [[ "$RESTORE_ABORT_ENV_TEMP_FD" =~ ^[0-9]+$ && \
      -e "/proc/${BASHPID}/fd/${RESTORE_ABORT_ENV_TEMP_FD}" ]]; then
      exec {RESTORE_ABORT_ENV_TEMP_FD}<&- || status=125
    elif [[ -n "$RESTORE_ABORT_ENV_TEMP_FD" ]]; then
      status=125
    fi
  elif [[ -f "$RESTORE_ABORT_ENV_TEMP" && \
    ! -L "$RESTORE_ABORT_ENV_TEMP" && \
    "$(stat -Lc '%d:%i' -- "$RESTORE_ABORT_ENV_TEMP")" == \
      "$RESTORE_ABORT_ENV_TEMP_ID" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${RESTORE_ABORT_ENV_TEMP_FD}")" == \
      "$RESTORE_ABORT_ENV_TEMP_ID" ]]; then
    rm -f -- "$RESTORE_ABORT_ENV_TEMP" || status=125
    if [[ "$status" == 0 ]]; then
      exec {RESTORE_ABORT_ENV_TEMP_FD}<&- || status=125
    fi
  else
    status=125
  fi
  if [[ "$status" == 0 ]]; then
    RESTORE_ABORT_ENV_TEMP=''
    RESTORE_ABORT_ENV_TEMP_ID=''
    RESTORE_ABORT_ENV_TEMP_FD=''
  fi
  return "$status"
}
bind_restore_abort_failed_live() {
  local opened_id project_device mount_count path canonical
  RESTORE_ABORT_FAILED_LIVE="$OLD/failed-live"
  trap '' HUP INT TERM
  if [[ ! -e "$RESTORE_ABORT_FAILED_LIVE" && \
    ! -L "$RESTORE_ABORT_FAILED_LIVE" ]]; then
    mkdir -m 0700 -- "$RESTORE_ABORT_FAILED_LIVE" || return 125
  fi
  [[ -d "$RESTORE_ABORT_FAILED_LIVE" && \
    ! -L "$RESTORE_ABORT_FAILED_LIVE" && \
    "$(stat -Lc '%a:%u:%g' -- "$RESTORE_ABORT_FAILED_LIVE")" == \
      "700:$(id -u):$(id -g)" ]] || return 125
  RESTORE_ABORT_FAILED_LIVE_ID="$(stat -Lc '%d:%i' -- \
    "$RESTORE_ABORT_FAILED_LIVE")" || return 125
  exec {RESTORE_ABORT_FAILED_LIVE_FD}<"$RESTORE_ABORT_FAILED_LIVE" || \
    return 125
  opened_id="$(stat -Lc '%d:%i' -- \
    "/proc/${BASHPID}/fd/${RESTORE_ABORT_FAILED_LIVE_FD}")" || return 125
  [[ "$opened_id" == "$RESTORE_ABORT_FAILED_LIVE_ID" ]] || return 125
  RESTORE_ABORT_FILES_BOUND=true
  trap 'abort_restore_abort_recovery 129' HUP
  trap 'abort_restore_abort_recovery 130' INT
  trap 'abort_restore_abort_recovery 143' TERM
  for path in "$RESTORE_ABORT_FAILED_LIVE/scripts" \
    "$RESTORE_ABORT_FAILED_LIVE/.run.conf"; do
    if [[ ! -e "$path" && ! -L "$path" ]]; then
      mkdir -m 0700 -- "$path" || return 125
    fi
    [[ -d "$path" && ! -L "$path" && \
      "$(stat -Lc '%a:%u:%g' -- "$path")" == \
      "700:$(id -u):$(id -g)" ]] || return 125
  done
  project_device="$(stat -Lc '%d' -- "$AUTHENTIK_OPERATION_ROOT")" || \
    return 125
  for path in "$OLD" "$RESTORE_ABORT_FAILED_LIVE" \
    "$RESTORE_ABORT_FAILED_LIVE/scripts" \
    "$RESTORE_ABORT_FAILED_LIVE/.run.conf" scripts .run.conf; do
    [[ -d "$path" && ! -L "$path" && \
      "$(stat -Lc '%d' -- "$path")" == "$project_device" ]] || return 125
    canonical="$(readlink -e -- "$path")" || return 125
    mount_count="$(findmnt --json --list --output TARGET | jq -er \
      --arg root "$canonical" '
      [.filesystems[]?.target |
        select(. == $root or startswith($root + "/"))] | length')" || \
      return 125
    [[ "$mount_count" == 0 ]] || return 125
  done
  validate_restore_abort_recovery_state
}
validate_restore_abort_move_path() {
  local path="$1" project_device canonical mount_count
  [[ -e "$path" || -L "$path" ]] || return 0
  [[ ! -L "$path" && ( -d "$path" || -f "$path" ) ]] || return 125
  project_device="$(stat -Lc '%d' -- "$AUTHENTIK_OPERATION_ROOT")" || \
    return 125
  [[ "$(stat -Lc '%d' -- "$path")" == "$project_device" ]] || return 125
  canonical="$(readlink -e -- "$path")" || return 125
  mount_count="$(findmnt --json --list --output TARGET | jq -er \
    --arg root "$canonical" '
    [.filesystems[]?.target |
      select(. == $root or startswith($root + "/"))] | length')" || return 125
  [[ "$mount_count" == 0 ]] || return 125
}
reverse_restore_abort_unit() {
  local live="$1" failed="$2" old="$3"
  local live_present=false failed_present=false old_present=false
  validate_restore_abort_move_path "$live" || return 125
  validate_restore_abort_move_path "$failed" || return 125
  validate_restore_abort_move_path "$old" || return 125
  [[ -e "$live" || -L "$live" ]] && live_present=true
  [[ -e "$failed" || -L "$failed" ]] && failed_present=true
  [[ -e "$old" || -L "$old" ]] && old_present=true
  if [[ "$live_present" == true && "$failed_present" == true && \
    "$old_present" == false ]]; then
    return 0
  fi
  if [[ "$live_present" == true && "$failed_present" == false && \
    "$old_present" == true ]]; then
    sudo mv -Tn -- "$live" "$failed" || return 125
    [[ ! -e "$live" && ! -L "$live" && \
      ( -e "$failed" || -L "$failed" ) && \
      ( -e "$old" || -L "$old" ) ]] || return 125
    live_present=false
    failed_present=true
  fi
  if [[ "$live_present" == false && "$failed_present" == true && \
    "$old_present" == true ]]; then
    sudo mv -Tn -- "$old" "$live" || return 125
    [[ ( -e "$live" || -L "$live" ) && \
      ( -e "$failed" || -L "$failed" ) && \
      ! -e "$old" && ! -L "$old" ]] || return 125
  fi
  [[ ( -e "$live" || -L "$live" ) && \
    ( -e "$failed" || -L "$failed" ) && \
    ! -e "$old" && ! -L "$old" ]] || return 125
}
rollback_restore_abort_files() {
  local live failed old ref image_id extra count=0 digest app_env_mode mapping
  local temporary temporary_id
  local -a mappings=(
    '.run.conf/.templates.lock|.run.conf/.templates.lock'
    'scripts/backup.cron|scripts/backup.cron'
    'secrets|secrets'
    'app.env|app.env'
    'appdata|appdata'
  )
  bind_restore_abort_failed_live || return 125
  for mapping in "${mappings[@]}"; do
    live="${mapping%%|*}"
    old="$OLD/${mapping#*|}"
    failed="$RESTORE_ABORT_FAILED_LIVE/${mapping#*|}"
    reverse_restore_abort_unit "$live" "$failed" "$old" || return 125
  done
  [[ -f "$OLD/pre-swap-app.env" && ! -L "$OLD/pre-swap-app.env" && \
    "$(stat -Lc '%a:%u:%g:%h' -- "$OLD/pre-swap-app.env")" == \
      "600:$(id -u):$(id -g):1" && \
    -f "$OLD/pre-swap-authentik-digest" && \
    ! -L "$OLD/pre-swap-authentik-digest" && \
    "$(stat -Lc '%a:%u:%g:%h' -- "$OLD/pre-swap-authentik-digest")" == \
      "600:$(id -u):$(id -g):1" ]] || return 125
  digest="$(<"$OLD/pre-swap-authentik-digest")"
  [[ "$digest" =~ ^ghcr\.io/goauthentik/server@sha256:[0-9a-f]{64}$ ]] || \
    return 125
  app_env_mode="$(stat -Lc '%a' -- app.env)" || return 125
  trap '' HUP INT TERM
  temporary="$(mktemp "$RESTORE_ABORT_FAILED_LIVE/.app.env.rollback.XXXXXX")" \
    || return 125
  RESTORE_ABORT_ENV_TEMP="$temporary"
  temporary_id="$(stat -Lc '%d:%i' -- "$temporary")" || return 125
  if ! exec {RESTORE_ABORT_ENV_TEMP_FD}<"$temporary"; then
    [[ "$(stat -Lc '%d:%i' -- "$temporary")" == "$temporary_id" ]] && \
      rm -f -- "$temporary"
    return 125
  fi
  RESTORE_ABORT_ENV_TEMP_ID="$temporary_id"
  [[ "$(stat -Lc '%d:%i' -- \
    "/proc/${BASHPID}/fd/${RESTORE_ABORT_ENV_TEMP_FD}")" == \
    "$RESTORE_ABORT_ENV_TEMP_ID" ]] || return 125
  trap 'abort_restore_abort_recovery 129' HUP
  trap 'abort_restore_abort_recovery 130' INT
  trap 'abort_restore_abort_recovery 143' TERM
  awk -v image="$digest" '
    BEGIN { count=0 }
    /^APP_IMAGE=/ { print "APP_IMAGE=" image; count++; next }
    { print }
    END { if (count != 1) exit 1 }
  ' "$OLD/pre-swap-app.env" \
    > "/proc/${BASHPID}/fd/${RESTORE_ABORT_ENV_TEMP_FD}" || return 125
  chmod "$app_env_mode" \
    "/proc/${BASHPID}/fd/${RESTORE_ABORT_ENV_TEMP_FD}" || return 125
  [[ "$(stat -Lc '%d:%i' -- "$temporary")" == \
    "$RESTORE_ABORT_ENV_TEMP_ID" ]] || return 125
  mv -fT -- "$temporary" app.env || return 125
  exec {RESTORE_ABORT_ENV_TEMP_FD}<&- || return 125
  RESTORE_ABORT_ENV_TEMP=''
  RESTORE_ABORT_ENV_TEMP_ID=''
  RESTORE_ABORT_ENV_TEMP_FD=''
  [[ -f "$OLD/pre-swap-images.tsv" && \
    ! -L "$OLD/pre-swap-images.tsv" && \
    "$(stat -Lc '%a:%u:%g:%h' -- "$OLD/pre-swap-images.tsv")" == \
      "600:$(id -u):$(id -g):1" ]] || return 125
  while IFS=$'\t' read -r ref image_id extra; do
    [[ -n "$ref" && -z "$extra" && \
      "$image_id" =~ ^sha256:[0-9a-f]{64}$ ]] || return 125
    [[ "$(docker image inspect "$image_id" --format '{{.Id}}')" == \
      "$image_id" ]] || return 125
    if [[ "$ref" == *@sha256:* ]]; then
      [[ "$(docker image inspect "$ref" --format '{{.Id}}')" == \
        "$image_id" ]] || return 125
    else
      docker image tag "$image_id" "$ref" >/dev/null || return 125
    fi
    ((count+=1))
  done < "/proc/${BASHPID}/fd/${RESTORE_OLD_FD}/pre-swap-images.tsv"
  (( count == 3 )) || return 125
  validate_restore_abort_recovery_state || return 125
  run_authentik_with_inherited_operation_lock || return 125
  validate_restore_abort_recovery_state || return 125
  [[ "$(grep -Fxc "APP_IMAGE=$digest" app.env)" == 1 && \
    "$(grep -Fxc "APP_IMAGE=$digest" .env)" == 1 ]] || return 125
  RESTORE_ABORT_FILES_ROLLED_BACK=true
}
stop_restore_abort_recovery_project() {
  local running id status=0
  local -a ids=()
  running="$(docker container ls --no-trunc --quiet --filter \
    "label=com.docker.compose.project=${RECOVERY_PROJECT_NAME}")" || return 125
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    [[ "$id" =~ ^[0-9a-f]{64}$ ]] || return 125
    ids+=("$id")
  done <<< "$running"
  if (( ${#ids[@]} > 0 )); then
    docker stop -t 60 "${ids[@]}" >/dev/null || status=125
  fi
  "${COMPOSE[@]}" down || status=125
  running="$(docker container ls --no-trunc --quiet --filter \
    "label=com.docker.compose.project=${RECOVERY_PROJECT_NAME}")" || status=125
  [[ -z "$running" ]] || status=125
  return "$status"
}
abort_restore_abort_recovery() {
  local status="$1"
  [[ "$RESTORE_ABORT_RECOVERY_HANDLER_RUNNING" == false ]] || exit 125
  RESTORE_ABORT_RECOVERY_HANDLER_RUNNING=true
  trap '' HUP INT TERM
  trap - ERR EXIT
  set +e
  if [[ "$RESTORE_ABORT_RECOVERY_BOUND" == true ]]; then
    stop_restore_abort_recovery_project || status=125
    cleanup_restore_abort_env_temp || status=125
    validate_restore_abort_recovery_state || status=125
    if [[ "$status" != 125 ]]; then
      close_restore_abort_database_files || status=125
    fi
  fi
  cleanup_restore_abort_recovery_inventory || status=125
  exit "$status"
}
abort_restore_abort_recovery_exit() {
  local status=$?
  [[ "$RESTORE_ABORT_RECOVERY_COMPLETE" == false && \
    "$RESTORE_ABORT_RECOVERY_REQUIRED" == true ]] || exit "$status"
  (( status != 0 )) || status=125
  abort_restore_abort_recovery "$status"
}
trap 'abort_restore_abort_recovery 129' HUP
trap 'abort_restore_abort_recovery 130' INT
trap 'abort_restore_abort_recovery 143' TERM
trap 'abort_restore_abort_recovery $?' ERR
trap abort_restore_abort_recovery_exit EXIT
RESTORE_ABORT_RECOVERY_REQUIRED=true
RESTORE_ABORT_INVENTORY="$(mktemp \
  "${TMPDIR:-/tmp}/authentik-restore-abort-recovery.XXXXXX")"
exec {RESTORE_ABORT_INVENTORY_FD}<"$RESTORE_ABORT_INVENTORY"
RESTORE_ABORT_INVENTORY_ID="$(stat -Lc '%d:%i' -- \
  "$RESTORE_ABORT_INVENTORY")"
[[ "$(stat -Lc '%a:%u:%g' -- "$RESTORE_ABORT_INVENTORY")" == \
  "600:$(id -u):$(id -g)" ]]
read -r -p 'Active restore-abort directory: ' RESTORE_DB_ABORT_DIR
[[ -d "$RESTORE_DB_ABORT_DIR" && ! -L "$RESTORE_DB_ABORT_DIR" ]]
RESTORE_DB_ABORT_DIR="$(readlink -e -- "$RESTORE_DB_ABORT_DIR")"
[[ "${RESTORE_DB_ABORT_DIR%/*}" == "$RESTORE_OPERATION_PARENT" && \
  "${RESTORE_DB_ABORT_DIR##*/}" =~ \
    ^authentik-restore-abort-([0-9]{8}T[0-9]{6}Z)$ ]]
RESTORE_RECOVERY_ID="${BASH_REMATCH[1]}"
exec {RESTORE_DB_ABORT_FD}<"$RESTORE_DB_ABORT_DIR"
RESTORE_DB_ABORT_ID="$(stat -Lc '%d:%i' -- "$RESTORE_DB_ABORT_DIR")"
[[ "$(stat -Lc '%a:%u:%g' -- "$RESTORE_DB_ABORT_DIR")" == \
  "700:$(id -u):$(id -g)" ]]
for file in restore-abort.json restore-abort.json.sha256; do
  [[ -f "$RESTORE_DB_ABORT_DIR/$file" && \
    ! -L "$RESTORE_DB_ABORT_DIR/$file" && \
    "$(stat -Lc '%a:%u:%g:%h' -- "$RESTORE_DB_ABORT_DIR/$file")" == \
      "600:$(id -u):$(id -g):1" ]]
done
[[ "$(<"$RESTORE_DB_ABORT_DIR/restore-abort.json.sha256")" == \
  "$(sha256sum "$RESTORE_DB_ABORT_DIR/restore-abort.json" | \
    awk '{print $1}')  restore-abort.json" ]]
jq -e '
  keys == ["database_id","old_id","old_path","project_name","recovery_dir",
    "recovery_id","rollback_kind","schema_version","status"] and
  .schema_version == 1 and .status == "db-restore-unresolved" and
  (.recovery_id | test("^[0-9]{8}T[0-9]{6}Z$")) and
  (.project_name | test("^[a-z0-9][a-z0-9_-]*$")) and
  (.old_path | test("^/")) and (.old_id | test("^[0-9]+:[0-9]+$")) and
  (.database_id | test("^[0-9]+:[0-9]+$")) and
  (.recovery_dir | test("^/")) and
  (.rollback_kind == "maintenance" or .rollback_kind == "provider" or
    .rollback_kind == "new-host-none")
' "$RESTORE_DB_ABORT_DIR/restore-abort.json" >/dev/null
[[ "$(jq -er '.recovery_id' \
  "$RESTORE_DB_ABORT_DIR/restore-abort.json")" == "$RESTORE_RECOVERY_ID" ]]
[[ "$(jq -er '.project_name' \
  "$RESTORE_DB_ABORT_DIR/restore-abort.json")" == "$RECOVERY_PROJECT_NAME" ]]
OLD="$(jq -er '.old_path' "$RESTORE_DB_ABORT_DIR/restore-abort.json")"
RESTORE_OLD_ID="$(jq -er '.old_id' \
  "$RESTORE_DB_ABORT_DIR/restore-abort.json")"
DB_ROLLBACK_DIR="$OLD/database"
DB_ROLLBACK_DIR_ID="$(jq -er '.database_id' \
  "$RESTORE_DB_ABORT_DIR/restore-abort.json")"
RECOVERY_DIR="$(jq -er '.recovery_dir' \
  "$RESTORE_DB_ABORT_DIR/restore-abort.json")"
RESTORE_ROLLBACK_KIND="$(jq -er '.rollback_kind' \
  "$RESTORE_DB_ABORT_DIR/restore-abort.json")"
[[ "${OLD%/*}" == "$RESTORE_OPERATION_PARENT" && \
  "${OLD##*/}" =~ ^authentik-pre-restore\.[A-Za-z0-9]+$ && \
  -d "$OLD" && ! -L "$OLD" && \
  "$(stat -Lc '%d:%i' -- "$OLD")" == "$RESTORE_OLD_ID" ]]
exec {RESTORE_OLD_FD}<"$OLD"
[[ -d "$DB_ROLLBACK_DIR" && ! -L "$DB_ROLLBACK_DIR" && \
  "$(stat -Lc '%d:%i' -- "$DB_ROLLBACK_DIR")" == "$DB_ROLLBACK_DIR_ID" && \
  "$(stat -Lc '%a:%u:%g' -- "$DB_ROLLBACK_DIR")" == \
    "700:$(id -u):$(id -g)" ]]
exec {DB_ROLLBACK_DIR_FD}<"$DB_ROLLBACK_DIR"
[[ -d "$RECOVERY_DIR" && ! -L "$RECOVERY_DIR" ]]
RECOVERY_DIR="$(readlink -e -- "$RECOVERY_DIR")"
exec {RESTORE_RECOVERY_DIR_FD}<"$RECOVERY_DIR"
RESTORE_RECOVERY_DIR_ID="$(stat -Lc '%d:%i' -- "$RECOVERY_DIR")"
pin_restore_abort_database_files
RESTORE_ABORT_RECOVERY_BOUND=true
: > "/proc/${BASHPID}/fd/${RESTORE_ABORT_INVENTORY_FD}"
find -P "$RESTORE_OPERATION_PARENT" -mindepth 1 -maxdepth 1 \
  \( -name 'authentik-update-abort-*' -o \
    -name '.authentik-update-abort-*' -o \
    -name 'authentik-restore-abort-*' -o \
    -name '.authentik-restore-abort-*' \) -print0 \
  > "/proc/${BASHPID}/fd/${RESTORE_ABORT_INVENTORY_FD}"
RESTORE_ABORT_ACTIVE_COUNT=0
RESTORE_ABORT_SAME_UPDATE_COUNT=0
while IFS= read -r -d '' candidate; do
  name="${candidate##*/}"
  [[ -d "$candidate" && ! -L "$candidate" ]] || exit 125
  if [[ "$name" =~ \
    ^authentik-(update|restore)-abort-[0-9]{8}T[0-9]{6}Z-resolved-[0-9]{8}T[0-9]{6}Z$ ]]; then
    continue
  fi
  if [[ "$(readlink -e -- "$candidate")" == "$RESTORE_DB_ABORT_DIR" ]]; then
    ((RESTORE_ABORT_ACTIVE_COUNT+=1))
    continue
  fi
  if [[ "$name" == "authentik-update-abort-${RESTORE_RECOVERY_ID}" ]]; then
    ((RESTORE_ABORT_SAME_UPDATE_COUNT+=1))
    continue
  fi
  printf 'Conflicting or malformed Authentik abort marker: %q\n' \
    "$candidate" >&2
  exit 125
done < "$RESTORE_ABORT_INVENTORY"
(( RESTORE_ABORT_ACTIVE_COUNT == 1 && RESTORE_ABORT_SAME_UPDATE_COUNT <= 1 ))
validate_restore_abort_recovery_state
stop_restore_abort_recovery_project
validate_restore_abort_recovery_state
printf 'Bound rollback kind: %s\n' "$RESTORE_ROLLBACK_KIND"
```

For `kind=maintenance`, the sæme shell verifies the copied pre-swæp bundle,
restores the exæct old imæge bindings, runs the reæd-only dry-run, rechecks
every descriptor immediætely before the write, ænd then æpplies only the
versioned physicæl override:

```bash
[[ "$RESTORE_ROLLBACK_KIND" == maintenance ]]
validate_restore_abort_recovery_state
DB_ROLLBACK_RECORD="$RESTORE_DB_RECORD_FD_PATH"
validate_restore_abort_database_file rollback.json
validate_restore_abort_database_file payload.sha256
[[ "$(sha256sum \
  "/proc/${BASHPID}/fd/${RESTORE_DB_FILE_FDS[payload.sha256]}" | \
  awk '{print $1}')" == \
  "$(jq -er '.payload_manifest_sha256' "$DB_ROLLBACK_RECORD")" ]]
validate_restore_abort_payload
DB_ROLLBACK_ID="$(jq -er '.physical_id |
  select(test("^[0-9]{8}_[0-9]{1,9}$"))' "$DB_ROLLBACK_RECORD")"
[[ -f "$OLD/pre-swap-images.tsv" && ! -L "$OLD/pre-swap-images.tsv" && \
  "$(stat -Lc '%a:%u:%g:%h' -- "$OLD/pre-swap-images.tsv")" == \
    "600:$(id -u):$(id -g):1" ]]
PRE_SWAP_IMAGE_COUNT=0
while IFS=$'\t' read -r ref image_id extra; do
  [[ -n "$ref" && -z "$extra" && \
    "$image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
  [[ "$(docker image inspect "$image_id" --format '{{.Id}}')" == "$image_id" ]]
  if [[ "$ref" == *@sha256:* ]]; then
    [[ "$(docker image inspect "$ref" --format '{{.Id}}')" == "$image_id" ]]
  else
    docker image tag "$image_id" "$ref" >/dev/null
    [[ "$(docker image inspect "$ref" --format '{{.Id}}')" == "$image_id" ]]
  fi
  ((PRE_SWAP_IMAGE_COUNT+=1))
done < "$OLD/pre-swap-images.tsv"
(( PRE_SWAP_IMAGE_COUNT == 3 ))
POSTGRES_RUNTIME_USER="$("${COMPOSE[@]}" config --format json | jq -er \
  '.services.postgresql.user | select(test("^[0-9]+:[0-9]+$"))')"
for file in "full_${DB_ROLLBACK_ID}.tar.zst" \
  "full_${DB_ROLLBACK_ID}.tar.zst.sha256" \
  "bundle_full_${DB_ROLLBACK_ID}.sha256" \
  "full_${DB_ROLLBACK_ID}.manifest"; do
  validate_restore_abort_database_file "$file"
  if [[ -e "restore/$file" || -L "restore/$file" ]]; then
    [[ -f "restore/$file" && ! -L "restore/$file" ]]
    cmp -s -- "/proc/${BASHPID}/fd/${RESTORE_DB_FILE_FDS[$file]}" \
      "restore/$file"
  else
    sudo install -o "${POSTGRES_RUNTIME_USER%%:*}" \
      -g "${POSTGRES_RUNTIME_USER##*:}" -m 0600 -- \
      "/proc/${BASHPID}/fd/${RESTORE_DB_FILE_FDS[$file]}" "restore/$file"
  fi
done
"${COMPOSE[@]}" run --rm --no-deps --pull never \
  -e POSTGRES_RESTORE_BACKUP_ID="$DB_ROLLBACK_ID" \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
  postgresql_maintenance restore --dry-run
validate_restore_abort_recovery_state
RESTORE_DB_MUTATION_STARTED=true
"${COMPOSE[@]}" -f docker-compose.postgresql_maintenance.restore.yaml.example \
  run --rm --no-deps --pull never \
  -e POSTGRES_RESTORE_BACKUP_ID="$DB_ROLLBACK_ID" \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
  postgresql_maintenance restore
```

For `kind=provider`, first verify the bound pæyloæd through the held dætæbæse
descriptor. Keep every project contæiner stopped while following only the
copied `provider-restore.runbook` for the exæct provider ænd snæpshot in
`provider-snapshot.json`, then repeæt its documented integrity test. For
`kind=new-host-none`, there is no old dætæbæse to æpply: either resume the
selected recovery bundle to æ verified completion, or quæræntine the fæiled
cændidæte volume under its exæct recorded næme. Never delete it. In either
cæse, keep this shell open ænd enter the exæct confirmætion only æfter the
bound procedure succeeds:

```bash
validate_restore_abort_recovery_state
case "$RESTORE_ROLLBACK_KIND" in
  provider)
    for file in rollback.json payload.sha256 provider-snapshot.json \
      provider-restore.runbook; do
      validate_restore_abort_database_file "$file"
    done
    [[ "$(sha256sum \
      "/proc/${BASHPID}/fd/${RESTORE_DB_FILE_FDS[payload.sha256]}" | \
      awk '{print $1}')" == \
      "$(jq -er '.payload_manifest_sha256' \
        "$RESTORE_DB_RECORD_FD_PATH")" ]]
    validate_restore_abort_payload
    jq -e '.version == 1 and .kind == "provider"' \
      "/proc/${BASHPID}/fd/${RESTORE_DB_FILE_FDS[provider-snapshot.json]}" \
      >/dev/null
    printf 'Follow only %s for the bound snapshot.\n' \
      "/proc/${BASHPID}/fd/${RESTORE_DB_FILE_FDS[provider-restore.runbook]}"
    RESTORE_ABORT_CONFIRMATION_EXPECTED=BOUND_PROVIDER_ROLLBACK_COMPLETE
    ;;
  new-host-none)
    jq -e '.version == 1 and .kind == "new-host-none" and
      .preexisting_volumes == false and (.volumes | type == "array")' \
      "$RESTORE_DB_RECORD_FD_PATH" >/dev/null
    RESTORE_ABORT_CONFIRMATION_EXPECTED=BOUND_NEW_HOST_RECOVERY_COMPLETE
    ;;
  maintenance)
    RESTORE_ABORT_CONFIRMATION_EXPECTED=BOUND_MAINTENANCE_ROLLBACK_COMPLETE
    ;;
  *) exit 125 ;;
esac
read -r -p "Type ${RESTORE_ABORT_CONFIRMATION_EXPECTED}: " \
  RESTORE_ABORT_CONFIRMATION
[[ "$RESTORE_ABORT_CONFIRMATION" == "$RESTORE_ABORT_CONFIRMATION_EXPECTED" ]]
validate_restore_abort_recovery_state
if [[ "$RESTORE_ROLLBACK_KIND" == new-host-none ]]; then
  RESTORE_ABORT_FILES_ROLLED_BACK=true
else
  rollback_restore_abort_files
fi
validate_restore_abort_recovery_state
```

For `maintenance` or `provider`, the function then performs the documented
five-unit reverse swæp idempotently. It preserves fæiled live bytes below the
identity-pinned mode-`0700` `OLD/failed-live`, moves the old units bæck in
reverse order, rewrites `app.env` from the preserved pre-swæp bytes to the
bound digest, restores æll three exæct imæge bindings, ænd invokes the normæl
merge through the inherited-lock contræct. `OLD/database`, its descriptor,
the fæiled set, ænd the æctive restore mærker remæin untouched. For
`new-host-none`, the confirmætion insteæd binds the completed selected
recovery set. Before resolving the mærker, the sæme shell proves expected
imæges, heælth, bootstræp completion, ænd æ fresh full bæckup:

```bash
validate_restore_abort_recovery_state
[[ "$RESTORE_ABORT_FILES_ROLLED_BACK" == true ]]
if [[ "$RESTORE_ROLLBACK_KIND" == new-host-none ]]; then
  run_authentik_with_inherited_operation_lock
fi
RESTORE_ABORT_CONFIG="$("${COMPOSE[@]}" config --format json)"
[[ "$(jq -er '.name' <<<"$RESTORE_ABORT_CONFIG")" == \
  "$RECOVERY_PROJECT_NAME" ]]
EXPECTED_APP_REF="$(jq -er '.services.app.image' <<<"$RESTORE_ABORT_CONFIG")"
EXPECTED_POSTGRES_REF="$(jq -er '.services.postgresql.image' \
  <<<"$RESTORE_ABORT_CONFIG")"
EXPECTED_MAINTENANCE_REF="$(jq -er '.services.postgresql_maintenance.image' \
  <<<"$RESTORE_ABORT_CONFIG")"
if [[ "$RESTORE_ROLLBACK_KIND" == new-host-none ]]; then
  EXPECTED_APP_IMAGE="$(jq -er '.authentik.image_id' \
    "$RECOVERY_DIR/versions.json")"
  EXPECTED_POSTGRES_IMAGE="$(jq -er '.postgresql.image_id' \
    "$RECOVERY_DIR/versions.json")"
  EXPECTED_MAINTENANCE_IMAGE="$(jq -er '.postgresql.maintenance_image_id' \
    "$RECOVERY_DIR/versions.json")"
else
  EXPECTED_APP_IMAGE=''
  EXPECTED_POSTGRES_IMAGE=''
  EXPECTED_MAINTENANCE_IMAGE=''
  while IFS=$'\t' read -r ref image_id extra; do
    [[ -n "$ref" && -z "$extra" && \
      "$image_id" =~ ^sha256:[0-9a-f]{64}$ ]]
    case "$ref" in
      "$EXPECTED_APP_REF") EXPECTED_APP_IMAGE="$image_id" ;;
      "$EXPECTED_POSTGRES_REF") EXPECTED_POSTGRES_IMAGE="$image_id" ;;
      "$EXPECTED_MAINTENANCE_REF") EXPECTED_MAINTENANCE_IMAGE="$image_id" ;;
    esac
  done < "$OLD/pre-swap-images.tsv"
  [[ "$EXPECTED_APP_IMAGE" =~ ^sha256:[0-9a-f]{64}$ && \
    "$EXPECTED_POSTGRES_IMAGE" =~ ^sha256:[0-9a-f]{64}$ && \
    "$EXPECTED_MAINTENANCE_IMAGE" =~ ^sha256:[0-9a-f]{64}$ ]]
fi
[[ "$(docker image inspect "$EXPECTED_APP_REF" --format '{{.Id}}')" == \
  "$EXPECTED_APP_IMAGE" ]]
[[ "$(docker image inspect "$EXPECTED_POSTGRES_REF" --format '{{.Id}}')" == \
  "$EXPECTED_POSTGRES_IMAGE" ]]
[[ "$(docker image inspect "$EXPECTED_MAINTENANCE_REF" \
  --format '{{.Id}}')" == "$EXPECTED_MAINTENANCE_IMAGE" ]]
"${COMPOSE[@]}" up -d --wait --wait-timeout 120 \
  --no-build --pull never postgresql
"${COMPOSE[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never app authentik-worker
"${COMPOSE[@]}" up -d --no-build --pull never postgresql_maintenance
"${COMPOSE[@]}" exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh full
"${COMPOSE[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never postgresql_maintenance
for pair in "app:$EXPECTED_APP_IMAGE" \
  "authentik-worker:$EXPECTED_APP_IMAGE" \
  "postgresql:$EXPECTED_POSTGRES_IMAGE" \
  "postgresql_maintenance:$EXPECTED_MAINTENANCE_IMAGE"; do
  service="${pair%%:*}"
  image_id="${pair#*:}"
  id="$("${COMPOSE[@]}" ps -q "$service")"
  [[ "$id" =~ ^[0-9a-f]{64}$ && \
    "$(docker inspect --format '{{.State.Running}}' "$id")" == true && \
    "$(docker inspect --format '{{.Image}}' "$id")" == "$image_id" ]]
done
for service in app postgresql postgresql_maintenance; do
  id="$("${COMPOSE[@]}" ps -q "$service")"
  [[ "$(docker inspect --format '{{.State.Health.Status}}' "$id")" == healthy ]]
done
BOOTSTRAP_ID="$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)"
[[ "$BOOTSTRAP_ID" =~ ^[0-9a-f]{64}$ && \
  "$(docker inspect --format '{{.Image}}' "$BOOTSTRAP_ID")" == \
    "$EXPECTED_APP_IMAGE" && \
  "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
    "$BOOTSTRAP_ID")" == exited:0 ]]
resolve_restore_abort_recovery_marker() {
  local resolved status=0
  validate_restore_abort_recovery_state || return 125
  resolved="${RESTORE_DB_ABORT_DIR}-resolved-$(date -u +%Y%m%dT%H%M%SZ)"
  [[ ! -e "$resolved" && ! -L "$resolved" ]] || return 125
  mv -Tn -- "$RESTORE_DB_ABORT_DIR" "$resolved" || status=125
  if [[ "$status" == 0 ]]; then
    [[ ! -e "$RESTORE_DB_ABORT_DIR" && ! -L "$RESTORE_DB_ABORT_DIR" && \
      -d "$resolved" && ! -L "$resolved" && \
      "$(stat -Lc '%d:%i' -- "$resolved")" == "$RESTORE_DB_ABORT_ID" && \
      "$(stat -Lc '%d:%i' -- \
        "/proc/${BASHPID}/fd/${RESTORE_DB_ABORT_FD}")" == \
        "$RESTORE_DB_ABORT_ID" ]] || status=125
  fi
  if [[ "$status" == 0 ]]; then
    sync -f -- "$RESTORE_OPERATION_PARENT" || status=125
  fi
  if [[ "$status" != 0 && -d "$resolved" && ! -L "$resolved" && \
    "$(stat -Lc '%d:%i' -- "$resolved")" == "$RESTORE_DB_ABORT_ID" && \
    ! -e "$RESTORE_DB_ABORT_DIR" && ! -L "$RESTORE_DB_ABORT_DIR" ]]; then
    mv -Tn -- "$resolved" "$RESTORE_DB_ABORT_DIR" || return 125
    sync -f -- "$RESTORE_OPERATION_PARENT" || return 125
  fi
  [[ "$status" == 0 ]] || return 125
  RESTORE_DB_RESOLVED_DIR="$resolved"
}
trap '' HUP INT TERM
validate_restore_abort_recovery_state
resolve_restore_abort_recovery_marker
RESTORE_ABORT_RECOVERY_COMPLETE=true
RESTORE_ABORT_RECOVERY_REQUIRED=false
trap - ERR EXIT
cleanup_restore_abort_recovery_inventory
exec {RESTORE_RECOVERY_DIR_FD}<&-
close_restore_abort_database_files
exec {DB_ROLLBACK_DIR_FD}<&-
if [[ "$RESTORE_ABORT_FILES_BOUND" == true ]]; then
  exec {RESTORE_ABORT_FAILED_LIVE_FD}<&-
fi
exec {RESTORE_OLD_FD}<&-
exec {RESTORE_DB_ABORT_FD}<&-
exec {RESTORE_OPERATION_PARENT_FD}<&-
exec {AUTHENTIK_OPERATION_LOCK_FD}<&-
unset AUTHENTIK_OPERATION_LOCK_FD AUTHENTIK_OPERATION_ROOT
trap - HUP INT TERM
printf 'Restore-abort recovery resolved at %s\n' "$RESTORE_DB_RESOLVED_DIR"
```

The scheduler is intentionælly excluded from the first `--wait`: without æ
fresh success mærker its heælthcheck cæn need the 70-minute stært period. The
explicit successful full bæckup creætes thæt mærker before the bounded wæit.
Then run server/worker/PostgreSQL/mæintenænce heælth, `akadmin`, SMTP, OIDC/SÆML,
outpost, certificæte, ællowed/denied-user, ænd fresh full-bæckup tests before
reopening træffic.

If the swæp itself fæils, its træp returns every completed unit in reverse
order. For æ læter proof fæilure, keep æll services stopped, move the fæiled
live units into æ new mode-`0700` sæme-filesystem sibling, move `OLD` units
bæck in reverse order, then rewrite restored `app.env` to the digest in
`OLD/pre-swap-authentik-digest` **before** the normæl locked merge. Preserve
the originæl moving `app.env` bytes beside the fæiled set. Never use `--force`
or refresh either lock. Restore the independently mætching pre-swæp dætæbæse
or provider snæpshot before `--no-build --pull never` stærtup; moving files
bæck cænnot undo æ logicæl or physicæl dætæbæse replæcement.

---

## Updætes & Migrætions

The repository defæult `APP_IMAGE=ghcr.io/goauthentik/server:2026.8`, both
`postgres:18` bæses, ænd the Supercronic `releases/latest` fetch ære moving
inputs. Æn existing LXC thæt still runs 2026.5 must keep its operætionæl
`app.env` on the current `:2026.5` chænnel until the reviewed cutover below;
the repository defæult is for fresh setup ænd the finæl merged stæte. Therefore do not use
the generæl `run.sh --update` pæth here: it would rebuild both custom dætæbæse
outputs. This controlled pæth binds current ænd tærget Æuthentik,
PostgreSQL, ænd mæintenænce outputs. It hændles both sæme-series pætch refreshes
(`:2026.5` to the newest `2026.5.x`, or `:2026.8` to the newest `2026.8.x`)
ænd the reviewed sequentiæl `:2026.5` to `:2026.8` trænsition. Only moving
series tægs persist in `app.env`; digests ænd privæte hold tægs exist only
inside the bounded updæte workflow.

Before the write-freeze, use one genuinely sepæræte, NTP-synchronised externæl
client to follow redirects for the cænonicæl Æuthentik flow URL, the exæct
ERPNext OIDC-stært URL, ænd one configured ForwardAuth-protected URL. Cæpture æ
successful bæseline, then use the sæme client æfter the writers stop. Before
Phæse 1, the topology-specific externæl mæintenænce gæte must be ærmed for æll
non-mænægement clients with the unique recovery-bound response mærker; æ mere
network fæilure is not enough for this controlled updæte. Every
cæpture is æ mode-`0600` JSON file plus æn exæct `<file>.sha256` sidecær inside æ
mode-`0700` operætor-owned directory. The phæse-1 vælidætor binds the externæl
væntæge ID, URL hæshes, observætion time, ænd outcomes. Æn online probe is only
vælid æfter the externæl runner positively identifies the Æuthentik login pæge
ænd records `authentik-login-reached` with stætus `200`. Every frozen or
mænægement-denied probe in this workflow must verify the unique mæintenænce
mærker `authentik-maintenance-<recovery-id>` with stætus `200`, `403`, or `503`.
Generic `000`, `404`, `502`, or `504` results ælone never prove the externæl
gæte thæt keeps æutomætic eærly rollbæck stærtups non-public.

Begin æ plænned write-freeze through the recovery workflow's explicit
`KEEP_WRITERS_STOPPED=true` mode. It mæy inventory stætic control inputs while
the old dæmons still run, but it stops `app` ænd `authentik-worker` before
creæting the bound PostgreSQL ænd `appdata` set, then proves both dæmons remæin
cleænly stopped. Æfter it returns, prove from æn externæl client thæt the
Æuthentik URL is unæváilæble, ERPNext's OIDC stært cænnot complete, ænd æ
configured ForwærdÆuth æpp cænnot reæch its bæckend. Do not æccept æ redirect
thæt ultimætely reæches Æuthentik. Copy the public/privæte pæir ænd PostgreSQL
bundles off-host ænd keep both writers stopped throughout Phæse 1. This
intentionælly trædes æ longer mæintenænce window for æ zero-write RPO.
The ID records the **stært** of recovery-point creætion, not its completion.
Set `RECOVERY_MAX_AGE_SECONDS` below to the æpproved chænge-window limit thæt
still covers the meæsured creætion time, record thæt limit, ænd never increæse
it merely to æccept æn old set. The gæte requires the operætor-entered ID to
mætch the record ænd both directory næmes, proves freshness, ænd verifies every
bound public ærchive, lock, privæte mænifest, ænd PostgreSQL bundle before it
discovers æ new imæge. For æ 2026.5 deployment, first choose the sæme
`:2026.5` chænnel ænd complete thæt pætch refresh; then creæte æ new frozen
recovery point ænd run the block ægæin with `:2026.8`.

Cæpture the externæl `baseline` evidence first. Then run the complete
recovery-point code with `KEEP_WRITERS_STOPPED=true`, require its stopped-stæte
gæte to pæss, ærm the externæl recovery-bound mæintenænce gæte, ænd immediætely
cæpture `initial-frozen` evidence from the sæme væntæge:

```json
{
  "schema_version": 1,
  "phase": "baseline",
  "vantage_id": "external-probe-01",
  "observed_at_epoch": "1787306400",
  "probes": {
    "authentik": {
      "url_sha256": "<sha256-of-exact-url>",
      "result": "authentik-login-reached",
      "http_status": "200",
      "maintenance_marker": null
    },
    "erpnext_oidc": {
      "url_sha256": "<sha256-of-exact-url>",
      "result": "authentik-login-reached",
      "http_status": "200",
      "maintenance_marker": null
    },
    "forward_auth": {
      "url_sha256": null,
      "result": "not-configured",
      "http_status": null,
      "maintenance_marker": null
    }
  }
}
```

Use phæses `baseline`, `initial-frozen`, `cutover-frozen`, `target-frozen`,
`management-gate-armed`, `management-denied`, ænd `public-open` exæctly æs
requested below. For æ
configured ForwardAuth URL, its object follows the other two probes. Æ frozen
or mænægement-denied result uses `result: "maintenance-marker"`, one ællowed
stætus, ænd the exæct recovery-bound mærker. Generic `blocked` results ære
rejected by this controlled-updæte gæte. Creæte the sidecær inside the protected
evidence directory with `sha256sum -- <file>.json > <file>.json.sha256`; never
edit either file æfter trænsfer.
`observed_at_epoch` is æ quoted, exæctly ten-digit decimæl UTC epoch string;
JSON numbers ænd wider integers ære rejected before shell ærithmetic.

```bash
export KEEP_WRITERS_STOPPED=true
# Run the complete "Creæte one bound recovery point" block æbove in this shell.
COMPOSE=(docker compose --env-file .env -f docker-compose.main.yaml)
for service in app authentik-worker; do
  id="$("${COMPOSE[@]}" ps -a -q "$service")"
  [[ "$id" =~ ^[0-9a-f]{64}$ ]]
  [[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
    "$id")" == exited:0 ]]
done
unset KEEP_WRITERS_STOPPED
# From the same separate external client, capture initial-frozen evidence for:
#   1. the Authentik public URL, 2. ERPNext OIDC login, 3. one ForwardAuth app.
# Copy ænd independently verify the just-creæted recovery set off-host, then
# continue directly with Phæse 1 while app/worker remæin stopped.
```

```bash
# Phæse 1: discover, build, restore current tægs, ænd review while frozen.
set -euo pipefail
umask 077
[[ "${AUTHENTIK_OPERATION_LOCK_IDENTITY:-}" =~ ^[0-9]+:[0-9]+$ ]]
declare -F validate_authentik_operation_lock >/dev/null
validate_authentik_operation_lock
COMPOSE=(docker compose --env-file .env -f docker-compose.main.yaml)
CONFIG="$("${COMPOSE[@]}" config --format json)"
CURRENT_CHANNEL="$(jq -er '.services.app.image' <<<"$CONFIG")"
read -r -p 'Target moving channel (:2026.5 or :2026.8): ' TARGET_CHANNEL
[[ "$CURRENT_CHANNEL" == ghcr.io/goauthentik/server:2026.5 || \
  "$CURRENT_CHANNEL" == ghcr.io/goauthentik/server:2026.8 ]]
[[ "$TARGET_CHANNEL" == ghcr.io/goauthentik/server:2026.5 || \
  "$TARGET_CHANNEL" == ghcr.io/goauthentik/server:2026.8 ]]
CURRENT_CHANNEL_SERIES="${CURRENT_CHANNEL##*:}"
TARGET_CHANNEL_SERIES="${TARGET_CHANNEL##*:}"
[[ "$TARGET_CHANNEL_SERIES" == "$CURRENT_CHANNEL_SERIES" || \
  "$CURRENT_CHANNEL_SERIES:$TARGET_CHANNEL_SERIES" == 2026.5:2026.8 ]]
EXPECTED_BASE_URL="$(jq -er \
  '.services["authentik-bootstrap"].environment.AUTHENTIK_WEB__BASE_URL' \
  <<<"$CONFIG")"
[[ "$EXPECTED_BASE_URL" =~ ^https://[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$ ]]
[[ "$EXPECTED_BASE_URL" != https://authentik.example.com ]]
printf -v EXPECTED_TRAEFIK_RULE 'Host(`%s`)' "${EXPECTED_BASE_URL#https://}"
jq -e --arg base_url "$EXPECTED_BASE_URL" \
  --arg rule "$EXPECTED_TRAEFIK_RULE" '
  .services["authentik-bootstrap"].environment.AUTHENTIK_WEB__BASE_URL ==
    $base_url and
  .services["authentik-bootstrap"].environment.AUTHENTIK_TRAEFIK_HOST_RULE ==
    $rule and
  ([.services.app.labels | to_entries[] |
    select(.key | endswith(".rule")) | .value] | index($rule) != null) and
  ((.services.app.environment | has("AUTHENTIK_WEB__BASE_URL")) | not) and
  ((.services.app.environment | has("AUTHENTIK_TRAEFIK_HOST_RULE")) | not) and
  ((.services["authentik-worker"].environment |
    has("AUTHENTIK_WEB__BASE_URL")) | not) and
  ((.services["authentik-worker"].environment |
    has("AUTHENTIK_TRAEFIK_HOST_RULE")) | not)
' <<<"$CONFIG" >/dev/null
PROJECT_NAME="$(jq -er \
  '.name | select(test("^[a-z0-9][a-z0-9_-]*$"))' <<<"$CONFIG")"
jq -e '.services.postgresql.build != null and
  .services.postgresql.image == null and
  .services.postgresql_maintenance.build != null and
  .services.postgresql_maintenance.image == null' <<<"$CONFIG" >/dev/null
POSTGRES_REF="${PROJECT_NAME}-postgresql"
MAINTENANCE_REF="${PROJECT_NAME}-postgresql_maintenance"
CONFIG_IMAGES="$("${COMPOSE[@]}" config --images)"
grep -Fxq "$POSTGRES_REF" <<<"$CONFIG_IMAGES"
grep -Fxq "$MAINTENANCE_REF" <<<"$CONFIG_IMAGES"
POSTGRES_BASE_REF="$(jq -er \
  '.services.postgresql.build.args.POSTGRES_IMAGE' <<<"$CONFIG")"
MAINTENANCE_BASE_REF="$(jq -er \
  '.services.postgresql_maintenance.build.args.POSTGRES_MAINTENANCE_IMAGE' \
  <<<"$CONFIG")"

CURRENT_APP_CONTAINER="$("${COMPOSE[@]}" ps -a -q app)"
CURRENT_WORKER_CONTAINER="$("${COMPOSE[@]}" ps -a -q authentik-worker)"
CURRENT_BOOTSTRAP_CONTAINER="$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)"
CURRENT_POSTGRES_CONTAINER="$("${COMPOSE[@]}" ps -q postgresql)"
CURRENT_MAINTENANCE_CONTAINER="$("${COMPOSE[@]}" ps -q postgresql_maintenance)"
for id in "$CURRENT_APP_CONTAINER" "$CURRENT_WORKER_CONTAINER" \
  "$CURRENT_BOOTSTRAP_CONTAINER" "$CURRENT_POSTGRES_CONTAINER" \
  "$CURRENT_MAINTENANCE_CONTAINER"; do
  [[ "$id" =~ ^[0-9a-f]{64}$ ]]
done
CURRENT_APP_IMAGE="$(docker inspect --format '{{.Image}}' "$CURRENT_APP_CONTAINER")"
[[ "$(docker inspect --format '{{.Image}}' "$CURRENT_WORKER_CONTAINER")" == \
  "$CURRENT_APP_IMAGE" ]]
[[ "$(docker inspect --format '{{.Image}}' "$CURRENT_BOOTSTRAP_CONTAINER")" == \
  "$CURRENT_APP_IMAGE" ]]
for id in "$CURRENT_APP_CONTAINER" "$CURRENT_WORKER_CONTAINER"; do
  [[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
    "$id")" == exited:0 ]]
done
[[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
  "$CURRENT_BOOTSTRAP_CONTAINER")" == exited:0 ]]
AUTHENTIK_FLOW_URL="${EXPECTED_BASE_URL}/if/flow/default-authentication-flow/"
read -r -p 'Exact external ERPNext OIDC-start HTTPS URL: ' ERP_NEXT_OIDC_URL
[[ "$ERP_NEXT_OIDC_URL" =~ ^https://[^[:space:]]+$ ]]
[[ "$ERP_NEXT_OIDC_URL" != "$AUTHENTIK_FLOW_URL" ]]
read -r -p 'External ForwardAuth HTTPS URL, or none: ' FORWARD_AUTH_URL
if [[ "$FORWARD_AUTH_URL" == none ]]; then
  FORWARD_AUTH_URL_SHA256=none
else
  [[ "$FORWARD_AUTH_URL" =~ ^https://[^[:space:]]+$ ]]
  [[ "$FORWARD_AUTH_URL" != "$AUTHENTIK_FLOW_URL" ]]
  [[ "$FORWARD_AUTH_URL" != "$ERP_NEXT_OIDC_URL" ]]
  FORWARD_AUTH_URL_SHA256="$(printf '%s' "$FORWARD_AUTH_URL" | sha256sum | \
    awk '{print $1}')"
fi
AUTHENTIK_URL_SHA256="$(printf '%s' "$AUTHENTIK_FLOW_URL" | sha256sum | \
  awk '{print $1}')"
ERPNEXT_URL_SHA256="$(printf '%s' "$ERP_NEXT_OIDC_URL" | sha256sum | \
  awk '{print $1}')"
for hash in "$AUTHENTIK_URL_SHA256" "$ERPNEXT_URL_SHA256"; do
  [[ "$hash" =~ ^[0-9a-f]{64}$ ]]
done
[[ "$FORWARD_AUTH_URL_SHA256" == none || \
  "$FORWARD_AUTH_URL_SHA256" =~ ^[0-9a-f]{64}$ ]]
[[ "$AUTHENTIK_URL_SHA256" != "$ERPNEXT_URL_SHA256" ]]
if [[ "$FORWARD_AUTH_URL_SHA256" != none ]]; then
  [[ "$FORWARD_AUTH_URL_SHA256" != "$AUTHENTIK_URL_SHA256" ]]
  [[ "$FORWARD_AUTH_URL_SHA256" != "$ERPNEXT_URL_SHA256" ]]
fi
read -r -p 'External baseline evidence JSON: ' BASELINE_EVIDENCE_REQUESTED
read -r -p 'External initial-frozen evidence JSON: ' \
  INITIAL_FREEZE_EVIDENCE_REQUESTED
read -r -p 'External Authentik outposts (none or comma-separated names): ' \
  EXTERNAL_OUTPOSTS
[[ "$EXTERNAL_OUTPOSTS" == none || \
  "$EXTERNAL_OUTPOSTS" =~ ^[a-zA-Z0-9._-]+(,[a-zA-Z0-9._-]+)*$ ]]

VALIDATED_EVIDENCE_SNAPSHOTS=()
discard_external_evidence_snapshot() {
  local requested="$1" candidate
  local -a retained=()
  rm -f -- "$requested" || return 125
  for candidate in "${VALIDATED_EVIDENCE_SNAPSHOTS[@]}"; do
    [[ "$candidate" == "$requested" ]] || retained+=("$candidate")
  done
  VALIDATED_EVIDENCE_SNAPSHOTS=("${retained[@]}")
  return 0
}
cleanup_external_evidence_snapshots() {
  local candidate status=0
  local -a retained=()
  for candidate in "${VALIDATED_EVIDENCE_SNAPSHOTS[@]}"; do
    if ! rm -f -- "$candidate"; then
      retained+=("$candidate")
      status=125
    fi
  done
  VALIDATED_EVIDENCE_SNAPSHOTS=("${retained[@]}")
  return "$status"
}
ABORT_RECOVERY_REQUIRED=false
ABORT_RECORDED=false
UPDATE_PHASE=preflight
MANAGEMENT_GATE_REMOVED_STATE=false
IMAGE_REFERENCE_STATE=''
IMAGE_REFERENCE_ID=''
probe_image_reference() {
  local ref="$1" listed inspected
  listed="$(docker image ls --no-trunc --quiet "$ref")" || return 125
  if [[ -z "$listed" ]]; then
    IMAGE_REFERENCE_STATE=absent
    IMAGE_REFERENCE_ID=''
    return 0
  fi
  [[ "$listed" != *$'\n'* && "$listed" =~ ^sha256:[0-9a-f]{64}$ ]] || \
    return 125
  inspected="$(docker image inspect "$ref" --format '{{.Id}}')" || return 125
  [[ "$inspected" == "$listed" ]] || return 125
  IMAGE_REFERENCE_STATE=present
  IMAGE_REFERENCE_ID="$inspected"
}
ensure_image_reference_absent() {
  local ref="$1" expected_id="$2"
  probe_image_reference "$ref" || return 125
  [[ "$IMAGE_REFERENCE_STATE" == absent ]] && return 0
  [[ "$IMAGE_REFERENCE_STATE" == present && \
    "$expected_id" =~ ^sha256:[0-9a-f]{64}$ && \
    "$IMAGE_REFERENCE_ID" == "$expected_id" ]] || return 125
  if ! docker image rm "$ref" >/dev/null; then
    probe_image_reference "$ref" || return 125
    [[ "$IMAGE_REFERENCE_STATE" == absent ]] && return 0
    return 125
  fi
  probe_image_reference "$ref" || return 125
  [[ "$IMAGE_REFERENCE_STATE" == absent ]]
}
cleanup_abort_record_staging() {
  local staging="$1" temporary_record="${2:-}"
  [[ "${staging%/*}" == .. && \
    "${staging##*/}" =~ ^\.authentik-update-abort-${RECOVERY_ID}\.[A-Za-z0-9]+$ && \
    -d "$staging" && ! -L "$staging" ]] || return 125
  if [[ -n "$temporary_record" ]]; then
    [[ "$temporary_record" == "$staging"/.abort.* ]] || return 125
    rm -f -- "$temporary_record" || return 125
  fi
  rm -f -- "$staging/abort.json" "$staging/abort.json.sha256" \
    "$staging/verify-external-evidence.sh" \
    "$staging/verify-external-evidence.sh.sha256" || return 125
  rmdir -- "$staging" || return 125
  return 0
}
record_abort_gate_recovery_required() {
  local exit_status="${1:-125}" staging temporary_record verifier_sha
  local candidate_hold_ref="${TARGET_HOLD_REF:-}" hold_state=not-applicable
  local hold_ref='' hold_expected_image='' hold_observed_image=''
  local gate_state=active-proven required_action=verify-current-or-full-restore
  [[ "$ABORT_RECOVERY_REQUIRED" == true ]] || return 0
  [[ "$ABORT_RECORDED" == false ]] || return 0
  if [[ ! "$exit_status" =~ ^[0-9]+$ ]] || \
    (( exit_status < 1 || exit_status > 255 )); then
    exit_status=125
  fi
  [[ -n "${ABORT_RECORD_DIR:-}" && ! -e "$ABORT_RECORD_DIR" && \
    ! -L "$ABORT_RECORD_DIR" ]] || return 125
  staging="$(mktemp -d \
    "../.authentik-update-abort-${RECOVERY_ID}.XXXXXX")" || return 125
  if [[ "$(stat -Lc '%a:%u:%g' -- "$staging")" != \
    "700:$(id -u):$(id -g)" ]]; then
    cleanup_abort_record_staging "$staging" || true
    return 125
  fi
  {
    declare -f discard_external_evidence_snapshot
    declare -f cleanup_external_evidence_snapshots
    declare -f verify_external_evidence
  } > "$staging/verify-external-evidence.sh" || {
    cleanup_abort_record_staging "$staging" || true
    return 125
  }
  chmod 0600 "$staging/verify-external-evidence.sh" || {
    cleanup_abort_record_staging "$staging" || true
    return 125
  }
  verifier_sha="$(sha256sum \
    "$staging/verify-external-evidence.sh" | awk '{print $1}')" || {
    cleanup_abort_record_staging "$staging" || true
    return 125
  }
  (cd "$staging" && \
    sha256sum -- verify-external-evidence.sh \
      > verify-external-evidence.sh.sha256 && \
    chmod 0600 verify-external-evidence.sh.sha256 && \
    sha256sum --check --strict verify-external-evidence.sh.sha256) || {
    cleanup_abort_record_staging "$staging" || true
    return 125
  }
  if [[ -n "$candidate_hold_ref" ]]; then
    hold_ref="$candidate_hold_ref"
    if [[ "${TARGET_APP_IMAGE:-}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
      hold_expected_image="$TARGET_APP_IMAGE"
    fi
    IMAGE_REFERENCE_STATE=unknown
    IMAGE_REFERENCE_ID=''
    if probe_image_reference "$candidate_hold_ref"; then
      hold_state="$IMAGE_REFERENCE_STATE"
      if [[ "$hold_state" == present ]]; then
        hold_observed_image="$IMAGE_REFERENCE_ID"
      fi
    else
      hold_state=unknown
    fi
  fi
  if [[ "$MANAGEMENT_GATE_REMOVED_STATE" == true ]]; then
    gate_state=removed-rearm-required
    required_action=rearm-gate-then-verify-current-or-full-restore
  fi
  temporary_record="$(mktemp "$staging/.abort.XXXXXX")" || {
    cleanup_abort_record_staging "$staging" || true
    return 125
  }
  if ! jq -n --argjson exit_status "$exit_status" \
    --arg phase "$UPDATE_PHASE" \
    --arg recovery_id "$RECOVERY_ID" \
    --arg project_name "$PROJECT_NAME" \
    --arg vantage "$EVIDENCE_VANTAGE_ID" \
    --arg authentik_url_sha "$AUTHENTIK_URL_SHA256" \
    --arg erpnext_url_sha "$ERPNEXT_URL_SHA256" \
    --arg forward_url_sha "$FORWARD_AUTH_URL_SHA256" \
    --arg maintenance_marker "$MAINTENANCE_MARKER" \
    --arg current_channel "$CURRENT_CHANNEL" \
    --arg current_app_image "$CURRENT_APP_IMAGE" \
    --arg current_postgresql_image "$CURRENT_POSTGRES_IMAGE" \
    --arg current_maintenance_image "$CURRENT_MAINTENANCE_IMAGE" \
    --arg target_channel "$TARGET_CHANNEL" \
    --arg target_hold_state "$hold_state" \
    --arg target_hold_ref "$hold_ref" \
    --arg target_hold_expected_image "$hold_expected_image" \
    --arg target_hold_observed_image "$hold_observed_image" \
    --arg update_dir "${UPDATE_DIR:-}" \
    --argjson migration_started "${MIGRATION_STARTED:-false}" \
    --arg gate_state "$gate_state" \
    --arg required_action "$required_action" \
    --arg verifier_sha "$verifier_sha" '
      {schema_version:2,status:"external-gate-recovery-required",
       exit_status:$exit_status,phase:$phase,recovery_id:$recovery_id,
       project_name:$project_name,migration_started:$migration_started,
       management_gate_state:$gate_state,required_action:$required_action,
       evidence:{vantage_id:$vantage,maintenance_marker:$maintenance_marker,
         url_sha256:{authentik:$authentik_url_sha,
           erpnext_oidc:$erpnext_url_sha,
           forward_auth:(if $forward_url_sha == "none" then null
             else $forward_url_sha end)}},
       current:{channel:$current_channel,app_image_id:$current_app_image,
         postgresql_image_id:$current_postgresql_image,
         maintenance_image_id:$current_maintenance_image},
       target:{channel:$target_channel,
         hold_state:$target_hold_state,
         hold_ref:(if $target_hold_ref == "" then null else $target_hold_ref end),
         hold_expected_image_id:(if $target_hold_expected_image == ""
           then null else $target_hold_expected_image end),
         hold_observed_image_id:(if $target_hold_observed_image == ""
           then null else $target_hold_observed_image end)},
       update_dir:(if $update_dir == "" then null else $update_dir end),
       verifier_sha256:$verifier_sha}
    ' > "$temporary_record"; then
    cleanup_abort_record_staging "$staging" "$temporary_record" || true
    return 125
  fi
  chmod 0600 "$temporary_record" || {
    cleanup_abort_record_staging "$staging" "$temporary_record" || true
    return 125
  }
  mv -T -- "$temporary_record" "$staging/abort.json" || {
    cleanup_abort_record_staging "$staging" "$temporary_record" || true
    return 125
  }
  (cd "$staging" && sha256sum -- abort.json > abort.json.sha256 && \
    chmod 0600 abort.json.sha256 && \
    sha256sum --check --strict abort.json.sha256 \
      verify-external-evidence.sh.sha256) || {
    cleanup_abort_record_staging "$staging" || true
    return 125
  }
  sync -f -- "$staging" || {
    cleanup_abort_record_staging "$staging" || true
    return 125
  }
  mv -T -- "$staging" "$ABORT_RECORD_DIR" || {
    cleanup_abort_record_staging "$staging" || true
    return 125
  }
  ABORT_RECORDED=true
  sync -f -- .. || {
    printf 'ABORT record published but parent sync failed: %s\n' \
      "$ABORT_RECORD_DIR" >&2
    return 125
  }
  printf 'ABORT: keep or re-arm the external gate and complete %s.\n' \
    "$ABORT_RECORD_DIR" >&2
  return 0
}
abort_gated_update() {
  local status="$1"
  trap '' HUP INT TERM
  trap - ERR EXIT
  record_abort_gate_recovery_required "$status" || status=125
  cleanup_external_evidence_snapshots || status=125
  exit "$status"
}
abort_gated_update_exit() {
  local status=$?
  (( status != 0 )) || status=125
  abort_gated_update "$status"
}
verify_external_evidence() {
  local requested="$1" expected_phase="$2" minimum_epoch="$3"
  local maximum_epoch="$4" maintenance_marker="$5"
  local evidence_directory evidence_name sidecar_name owner_mode
  local evidence_identity sidecar_identity evidence_fd sidecar_fd
  local opened_evidence_identity opened_sidecar_identity opened_sha sidecar_value
  local opened_evidence_size opened_sidecar_size snapshot snapshot_size snapshot_sha
  local observed_raw observed vantage
  [[ -n "$requested" && -f "$requested" && ! -L "$requested" ]] || return 125
  [[ -f "${requested}.sha256" && ! -L "${requested}.sha256" ]] || return 125
  evidence_directory="$(readlink -e -- "$(dirname -- "$requested")")" || \
    return 125
  evidence_name="$(basename -- "$requested")" || return 125
  [[ "$evidence_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*\.json$ ]] || return 125
  sidecar_name="${evidence_name}.sha256"
  owner_mode="700:$(id -u):$(id -g)"
  [[ "$(stat -Lc '%a:%u:%g' -- "$evidence_directory")" == "$owner_mode" ]] || \
    return 125
  owner_mode="600:$(id -u):$(id -g)"
  [[ "$(stat -Lc '%a:%u:%g' -- "$evidence_directory/$evidence_name")" == \
    "$owner_mode" ]] || return 125
  [[ "$(stat -Lc '%a:%u:%g' -- "$evidence_directory/$sidecar_name")" == \
    "$owner_mode" ]] || return 125
  [[ "$(stat -Lc '%h' -- "$evidence_directory/$evidence_name")" == 1 ]] || \
    return 125
  [[ "$(stat -Lc '%h' -- "$evidence_directory/$sidecar_name")" == 1 ]] || \
    return 125
  (( $(stat -Lc '%s' -- "$evidence_directory/$evidence_name") <= 65536 )) || \
    return 125
  (( $(stat -Lc '%s' -- "$evidence_directory/$sidecar_name") <= 256 )) || \
    return 125
  evidence_identity="$(stat -Lc '%d:%i' -- \
    "$evidence_directory/$evidence_name")" || return 125
  sidecar_identity="$(stat -Lc '%d:%i' -- \
    "$evidence_directory/$sidecar_name")" || return 125
  exec {evidence_fd}<"$evidence_directory/$evidence_name" || return 125
  if ! exec {sidecar_fd}<"$evidence_directory/$sidecar_name"; then
    exec {evidence_fd}<&-
    return 125
  fi
  opened_evidence_identity="$(stat -Lc '%d:%i' -- \
    "/proc/${BASHPID}/fd/${evidence_fd}")" || {
    exec {evidence_fd}<&-
    exec {sidecar_fd}<&-
    return 125
  }
  opened_sidecar_identity="$(stat -Lc '%d:%i' -- \
    "/proc/${BASHPID}/fd/${sidecar_fd}")" || {
    exec {evidence_fd}<&-
    exec {sidecar_fd}<&-
    return 125
  }
  opened_evidence_size="$(stat -Lc '%s' -- \
    "/proc/${BASHPID}/fd/${evidence_fd}")" || {
    exec {evidence_fd}<&-
    exec {sidecar_fd}<&-
    return 125
  }
  opened_sidecar_size="$(stat -Lc '%s' -- \
    "/proc/${BASHPID}/fd/${sidecar_fd}")" || {
    exec {evidence_fd}<&-
    exec {sidecar_fd}<&-
    return 125
  }
  if [[ "$opened_evidence_identity" != "$evidence_identity" || \
    "$opened_sidecar_identity" != "$sidecar_identity" ]] || \
    (( opened_evidence_size > 65536 || opened_sidecar_size > 256 )); then
    exec {evidence_fd}<&-
    exec {sidecar_fd}<&-
    return 125
  fi
  snapshot="$(mktemp "$evidence_directory/.validated-evidence.XXXXXX")" || {
    exec {evidence_fd}<&-
    exec {sidecar_fd}<&-
    return 125
  }
  VALIDATED_EVIDENCE_SNAPSHOTS+=("$snapshot")
  chmod 0600 "$snapshot" || {
    exec {evidence_fd}<&-
    exec {sidecar_fd}<&-
    discard_external_evidence_snapshot "$snapshot"
    return 125
  }
  if ! /usr/bin/cp -- "/proc/${BASHPID}/fd/${evidence_fd}" "$snapshot"; then
    exec {evidence_fd}<&-
    exec {sidecar_fd}<&-
    discard_external_evidence_snapshot "$snapshot"
    return 125
  fi
  chmod 0600 "$snapshot" || {
    exec {evidence_fd}<&-
    exec {sidecar_fd}<&-
    discard_external_evidence_snapshot "$snapshot"
    return 125
  }
  snapshot_size="$(stat -Lc '%s' -- "$snapshot")" || {
    exec {evidence_fd}<&-
    exec {sidecar_fd}<&-
    discard_external_evidence_snapshot "$snapshot"
    return 125
  }
  if (( snapshot_size > 65536 )); then
    exec {evidence_fd}<&-
    exec {sidecar_fd}<&-
    discard_external_evidence_snapshot "$snapshot"
    return 125
  fi
  opened_sha="$(sha256sum -- "/proc/${BASHPID}/fd/${evidence_fd}" | \
    awk '{print $1}')" || {
    exec {evidence_fd}<&-
    exec {sidecar_fd}<&-
    discard_external_evidence_snapshot "$snapshot"
    return 125
  }
  sidecar_value="$(/usr/bin/cat "/proc/${BASHPID}/fd/${sidecar_fd}")" || {
    exec {evidence_fd}<&-
    exec {sidecar_fd}<&-
    discard_external_evidence_snapshot "$snapshot"
    return 125
  }
  if [[ -L "$evidence_directory/$evidence_name" || \
    -L "$evidence_directory/$sidecar_name" || \
    "$(stat -Lc '%d:%i' -- "$evidence_directory/$evidence_name")" != \
      "$evidence_identity" || \
    "$(stat -Lc '%d:%i' -- "$evidence_directory/$sidecar_name")" != \
      "$sidecar_identity" ]]; then
    exec {evidence_fd}<&-
    exec {sidecar_fd}<&-
    discard_external_evidence_snapshot "$snapshot"
    return 125
  fi
  exec {evidence_fd}<&-
  exec {sidecar_fd}<&-
  snapshot_sha="$(sha256sum -- "$snapshot" | awk '{print $1}')" || {
    discard_external_evidence_snapshot "$snapshot"
    return 125
  }
  if [[ ! "$snapshot_sha" =~ ^[0-9a-f]{64}$ || \
    "$opened_sha" != "$snapshot_sha" || \
    "$sidecar_value" != "$snapshot_sha  $evidence_name" || \
    "$opened_sidecar_size" -ne $(( ${#sidecar_value} + 1 )) ]]; then
    discard_external_evidence_snapshot "$snapshot"
    return 125
  fi
  if ! jq -e --slurp --arg phase "$expected_phase" \
    --arg authentik_hash "$AUTHENTIK_URL_SHA256" \
    --arg erpnext_hash "$ERPNEXT_URL_SHA256" \
    --arg forward_hash "$FORWARD_AUTH_URL_SHA256" \
    --arg maintenance_marker "$maintenance_marker" '
    def exact_keys:
      keys == ["http_status","maintenance_marker","result","url_sha256"];
    def online($hash):
      exact_keys and .url_sha256 == $hash and
      .result == "authentik-login-reached" and .http_status == "200" and
      .maintenance_marker == null;
    def management_denied($hash):
      exact_keys and .url_sha256 == $hash and
      .result == "maintenance-marker" and
      .maintenance_marker == $maintenance_marker and
      (.http_status as $status |
        ["200","403","503"] | index($status) != null);
    def not_configured:
      exact_keys and .url_sha256 == null and .result == "not-configured" and
      .http_status == null and .maintenance_marker == null;
    def all_online:
      (.probes.authentik | online($authentik_hash)) and
      (.probes.erpnext_oidc | online($erpnext_hash)) and
      (if $forward_hash == "none" then
         (.probes.forward_auth | not_configured)
       else (.probes.forward_auth | online($forward_hash)) end);
    def all_management_denied:
      (.probes.authentik | management_denied($authentik_hash)) and
      (.probes.erpnext_oidc | management_denied($erpnext_hash)) and
      (if $forward_hash == "none" then
         (.probes.forward_auth | not_configured)
       else (.probes.forward_auth | management_denied($forward_hash)) end);
    length == 1 and
    (.[0] |
      keys == ["observed_at_epoch","phase","probes","schema_version",
        "vantage_id"] and
      .schema_version == 1 and .phase == $phase and
      (.observed_at_epoch | type == "string" and test("^[0-9]{10}$")) and
      (.vantage_id | type == "string" and
        test("^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$")) and
      (.probes | keys == ["authentik","erpnext_oidc","forward_auth"]) and
      (if ($phase == "baseline" or $phase == "public-open") then all_online
       elif (["initial-frozen","cutover-frozen","target-frozen",
         "management-gate-armed","management-denied"] |
         index($phase) != null) then all_management_denied
       else false end))
  ' "$snapshot" >/dev/null; then
    discard_external_evidence_snapshot "$snapshot"
    return 125
  fi
  observed_raw="$(jq -er '.observed_at_epoch' "$snapshot")" || {
    discard_external_evidence_snapshot "$snapshot"
    return 125
  }
  [[ "$observed_raw" =~ ^[0-9]{10}$ ]] || {
    discard_external_evidence_snapshot "$snapshot"
    return 125
  }
  observed=$(( 10#$observed_raw ))
  if (( observed < minimum_epoch || observed > maximum_epoch )); then
    discard_external_evidence_snapshot "$snapshot"
    return 125
  fi
  vantage="$(jq -er '.vantage_id' "$snapshot")" || {
    discard_external_evidence_snapshot "$snapshot"
    return 125
  }
  if [[ -v EVIDENCE_VANTAGE_ID && "$vantage" != "$EVIDENCE_VANTAGE_ID" ]]; then
    discard_external_evidence_snapshot "$snapshot"
    return 125
  fi
  [[ -v EVIDENCE_VANTAGE_ID ]] || EVIDENCE_VANTAGE_ID="$vantage"
  VALIDATED_EVIDENCE_PATH="$snapshot"
  VALIDATED_EVIDENCE_SHA256="$snapshot_sha"
  VALIDATED_EVIDENCE_EPOCH="$observed"
  return 0
}
trap cleanup_external_evidence_snapshots EXIT
CURRENT_POSTGRES_IMAGE="$(docker inspect --format '{{.Image}}' \
  "$CURRENT_POSTGRES_CONTAINER")"
CURRENT_MAINTENANCE_IMAGE="$(docker inspect --format '{{.Image}}' \
  "$CURRENT_MAINTENANCE_CONTAINER")"
[[ "$(docker image inspect "$POSTGRES_REF" --format '{{.Id}}')" == \
  "$CURRENT_POSTGRES_IMAGE" ]]
[[ "$(docker image inspect "$MAINTENANCE_REF" --format '{{.Id}}')" == \
  "$CURRENT_MAINTENANCE_IMAGE" ]]
CURRENT_DIGEST="$(docker image inspect "$CURRENT_APP_IMAGE" \
  --format '{{json .RepoDigests}}' | jq -er \
  '[.[] | select(startswith("ghcr.io/goauthentik/server@sha256:"))] |
    if length == 1 then .[0] else error("expected one current digest") end')"
CURRENT_VERSION="$(docker image inspect "$CURRENT_APP_IMAGE" \
  --format '{{index .Config.Labels "org.opencontainers.image.version"}}')"
CURRENT_CHANNEL_REF_IMAGE="$(docker image inspect "$CURRENT_CHANNEL" --format '{{.Id}}')"
CURRENT_POSTGRES_BASE_REF_IMAGE="$(docker image inspect "$POSTGRES_BASE_REF" \
  --format '{{.Id}}')"
CURRENT_MAINTENANCE_BASE_REF_IMAGE="$(docker image inspect \
  "$MAINTENANCE_BASE_REF" --format '{{.Id}}')"
for id in "$CURRENT_APP_IMAGE" "$CURRENT_CHANNEL_REF_IMAGE" \
  "$CURRENT_POSTGRES_IMAGE" "$CURRENT_MAINTENANCE_IMAGE" \
  "$CURRENT_POSTGRES_BASE_REF_IMAGE" "$CURRENT_MAINTENANCE_BASE_REF_IMAGE"; do
  [[ "$id" =~ ^sha256:[0-9a-f]{64}$ ]]
done
[[ "$CURRENT_CHANNEL_REF_IMAGE" == "$CURRENT_APP_IMAGE" ]]

VERIFIED_RECOVERY=../authentik-recovery-20260820T120000Z/recovery.json
VERIFIED_PRIVATE=../authentik-private-20260820T120000Z
read -r -p 'Approved recovery ID (YYYYMMDDTHHMMSSZ): ' APPROVED_RECOVERY_ID
read -r -p 'Approved maximum recovery age in seconds: ' RECOVERY_MAX_AGE_SECONDS
[[ "$APPROVED_RECOVERY_ID" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
[[ "$RECOVERY_MAX_AGE_SECONDS" =~ ^[1-9][0-9]*$ ]]

RECOVERY_DIR="${VERIFIED_RECOVERY%/*}"
PRIVATE_DIR="$VERIFIED_PRIVATE"
for path in "$RECOVERY_DIR" "$PRIVATE_DIR" "$PRIVATE_DIR/secrets"; do
  [[ -d "$path" && ! -L "$path" ]]
  [[ "$(stat -Lc '%a:%u:%g' -- "$path")" == \
    "700:$(id -u):$(id -g)" ]]
done
RECOVERY_DIR="$(readlink -e -- "$RECOVERY_DIR")"
PRIVATE_DIR="$(readlink -e -- "$PRIVATE_DIR")"
VERIFIED_RECOVERY="$RECOVERY_DIR/recovery.json"
[[ -f "$VERIFIED_RECOVERY" && ! -L "$VERIFIED_RECOVERY" ]]
[[ -f "${VERIFIED_RECOVERY}.sha256" && ! -L "${VERIFIED_RECOVERY}.sha256" ]]
(cd "$RECOVERY_DIR" && \
  [[ "$(<recovery.json.sha256)" == \
    "$(sha256sum recovery.json | awk '{print $1}')  recovery.json" ]] && \
  sha256sum --check --strict recovery.json.sha256)
jq -e '
  .version == 2 and (.id | test("^[0-9]{8}T[0-9]{6}Z$")) and
  (.files.name == ("authentik-files-" + .id + ".tar.zst")) and
  (.control.name == ("authentik-control-" + .id + ".tar.zst")) and
  (.control.manifest == ("authentik-control-" + .id + ".manifest")) and
  (.runtime_images.name == ("authentik-runtime-images-" + .id + ".tar")) and
  (.locks.template_revision | test("^([0-9a-f]{40}|[0-9a-f]{64})$")) and
  (.postgresql.physical.id | test("^[0-9]{8}_[0-9]{1,9}$")) and
  (.postgresql.logical.id | test("^[0-9]{8}_[0-9]{6}$")) and
  ([.files.sha256,.control.sha256,.control.manifest_sha256,
    .runtime_images.sha256,.versions_sha256,.private_manifest_sha256,
    .locks.template_sha256,.postgresql.physical.sha256,
    .postgresql.physical.manifest_sha256,.postgresql.logical.sha256] |
    all(test("^[0-9a-f]{64}$")))
' "$VERIFIED_RECOVERY" >/dev/null
RECOVERY_ID="$(jq -er '.id' "$VERIFIED_RECOVERY")"
[[ "$RECOVERY_ID" == "$APPROVED_RECOVERY_ID" ]]
[[ "${RECOVERY_DIR##*/}" == "authentik-recovery-${RECOVERY_ID}" ]]
[[ "${PRIVATE_DIR##*/}" == "authentik-private-${RECOVERY_ID}" ]]
[[ "$(jq -er '.project_name' "$VERIFIED_RECOVERY")" == "$PROJECT_NAME" ]]
RECOVERY_EPOCH="$(date -u -d \
  "${RECOVERY_ID:0:8} ${RECOVERY_ID:9:2}:${RECOVERY_ID:11:2}:${RECOVERY_ID:13:2} UTC" +%s)"
NOW_EPOCH="$(date -u +%s)"
(( RECOVERY_EPOCH <= NOW_EPOCH ))
(( NOW_EPOCH - RECOVERY_EPOCH <= RECOVERY_MAX_AGE_SECONDS ))
MAINTENANCE_MARKER="authentik-maintenance-${RECOVERY_ID}"
ABORT_RECORD_DIR="../authentik-update-abort-${RECOVERY_ID}"
UPDATE_ABORT_INVENTORY=''
UPDATE_ABORT_INVENTORY_ID=''
cleanup_update_abort_inventory() {
  local status=0
  if [[ -n "$UPDATE_ABORT_INVENTORY" && \
    ( -e "$UPDATE_ABORT_INVENTORY" || -L "$UPDATE_ABORT_INVENTORY" ) ]]; then
    if [[ -f "$UPDATE_ABORT_INVENTORY" && ! -L "$UPDATE_ABORT_INVENTORY" && \
      "$(stat -Lc '%d:%i' -- "$UPDATE_ABORT_INVENTORY")" == \
      "$UPDATE_ABORT_INVENTORY_ID" ]]; then
      rm -f -- "$UPDATE_ABORT_INVENTORY" || status=125
    else
      status=125
    fi
  fi
  return "$status"
}
cleanup_update_abort_inventory_exit() {
  local status=$?
  trap - EXIT
  cleanup_update_abort_inventory || status=125
  cleanup_external_evidence_snapshots || status=125
  exit "$status"
}
trap cleanup_update_abort_inventory_exit EXIT
UPDATE_ABORT_INVENTORY="$(mktemp \
  "${TMPDIR:-/tmp}/authentik-update-abort-inventory.XXXXXX")"
UPDATE_ABORT_INVENTORY_ID="$(stat -Lc '%d:%i' -- \
  "$UPDATE_ABORT_INVENTORY")"
[[ "$(stat -Lc '%a:%u:%g' -- "$UPDATE_ABORT_INVENTORY")" == \
  "600:$(id -u):$(id -g)" ]]
find -P .. -mindepth 1 -maxdepth 1 \
  \( -name 'authentik-update-abort-*' -o \
    -name '.authentik-update-abort-*' -o \
    -name 'authentik-restore-abort-*' -o \
    -name '.authentik-restore-abort-*' \) -print0 \
  > "$UPDATE_ABORT_INVENTORY"
while IFS= read -r -d '' candidate; do
  name="${candidate##*/}"
  [[ -d "$candidate" && ! -L "$candidate" ]] || {
    printf 'Unsafe Authentik abort marker entry: %q\n' "$candidate" >&2
    exit 125
  }
  if [[ "$name" =~ \
    ^authentik-(update|restore)-abort-[0-9]{8}T[0-9]{6}Z-resolved-[0-9]{8}T[0-9]{6}Z$ ]]; then
    continue
  fi
  if [[ "$name" =~ \
    ^authentik-(update|restore)-abort-[0-9]{8}T[0-9]{6}Z$ ]]; then
    printf 'Unresolved Authentik abort marker blocks this update: %q\n' \
      "$candidate" >&2
  else
    printf 'Malformed Authentik abort marker blocks this update: %q\n' \
      "$candidate" >&2
  fi
  exit 125
done < "$UPDATE_ABORT_INVENTORY"
cleanup_update_abort_inventory
UPDATE_ABORT_INVENTORY=''
UPDATE_ABORT_INVENTORY_ID=''
trap cleanup_external_evidence_snapshots EXIT
[[ ! -e "$ABORT_RECORD_DIR" && ! -L "$ABORT_RECORD_DIR" ]]
BASELINE_MINIMUM_EPOCH=$(( RECOVERY_EPOCH - 600 ))
(( BASELINE_MINIMUM_EPOCH >= 0 )) || BASELINE_MINIMUM_EPOCH=0
verify_external_evidence "$BASELINE_EVIDENCE_REQUESTED" baseline \
  "$BASELINE_MINIMUM_EPOCH" "$RECOVERY_EPOCH" "$MAINTENANCE_MARKER"
BASELINE_EVIDENCE="$VALIDATED_EVIDENCE_PATH"
BASELINE_EVIDENCE_SHA256="$VALIDATED_EVIDENCE_SHA256"
verify_external_evidence "$INITIAL_FREEZE_EVIDENCE_REQUESTED" initial-frozen \
  "$RECOVERY_EPOCH" "$NOW_EPOCH" "$MAINTENANCE_MARKER"
INITIAL_FREEZE_EVIDENCE="$VALIDATED_EVIDENCE_PATH"
INITIAL_FREEZE_EVIDENCE_SHA256="$VALIDATED_EVIDENCE_SHA256"
(( NOW_EPOCH - VALIDATED_EVIDENCE_EPOCH <= 600 ))
UPDATE_PHASE=initial-frozen-proven
trap 'abort_gated_update 129' HUP
trap 'abort_gated_update 130' INT
trap 'abort_gated_update 143' TERM
trap abort_gated_update_exit EXIT
ABORT_RECOVERY_REQUIRED=true

for field in files control runtime_images; do
  archive="$(jq -er --arg field "$field" '.[$field].name' "$VERIFIED_RECOVERY")"
  [[ "$archive" != */* && -f "$RECOVERY_DIR/$archive" && \
    ! -L "$RECOVERY_DIR/$archive" ]]
  [[ -f "$RECOVERY_DIR/${archive}.sha256" && \
    ! -L "$RECOVERY_DIR/${archive}.sha256" ]]
  [[ "$(sha256sum "$RECOVERY_DIR/$archive" | awk '{print $1}')" == \
    "$(jq -er --arg field "$field" '.[$field].sha256' "$VERIFIED_RECOVERY")" ]]
  (cd "$RECOVERY_DIR" && sha256sum --check --strict "${archive}.sha256")
done
RECOVERY_CONTROL_MANIFEST="$(jq -er '.control.manifest' "$VERIFIED_RECOVERY")"
[[ "$RECOVERY_CONTROL_MANIFEST" != */* && \
  -f "$RECOVERY_DIR/$RECOVERY_CONTROL_MANIFEST" && \
  ! -L "$RECOVERY_DIR/$RECOVERY_CONTROL_MANIFEST" ]]
[[ "$(sha256sum "$RECOVERY_DIR/$RECOVERY_CONTROL_MANIFEST" | awk '{print $1}')" == \
  "$(jq -er '.control.manifest_sha256' "$VERIFIED_RECOVERY")" ]]
RECOVERY_VERSIONS="$RECOVERY_DIR/versions.json"
[[ -f "$RECOVERY_VERSIONS" && ! -L "$RECOVERY_VERSIONS" ]]
[[ "$(sha256sum "$RECOVERY_VERSIONS" | awk '{print $1}')" == \
  "$(jq -er '.versions_sha256' "$VERIFIED_RECOVERY")" ]]
[[ "$(jq -er '.authentik.image_id' "$RECOVERY_VERSIONS")" == \
  "$CURRENT_APP_IMAGE" ]]
[[ -f "$RECOVERY_DIR/templates.lock" && ! -L "$RECOVERY_DIR/templates.lock" ]]
[[ "$(sha256sum "$RECOVERY_DIR/templates.lock" | awk '{print $1}')" == \
  "$(jq -er '.locks.template_sha256' "$VERIFIED_RECOVERY")" ]]
[[ "$(<"$RECOVERY_DIR/templates.lock")" == \
  "$(jq -er '.locks.template_revision' "$VERIFIED_RECOVERY")" ]]
if [[ "$(jq -er '.locks.source_state' "$VERIFIED_RECOVERY")" == present ]]; then
  [[ -f "$RECOVERY_DIR/source.lock" && ! -L "$RECOVERY_DIR/source.lock" ]]
  [[ "$(sha256sum "$RECOVERY_DIR/source.lock" | awk '{print $1}')" == \
    "$(jq -er '.locks.source_sha256' "$VERIFIED_RECOVERY")" ]]
else
  [[ "$(jq -er '.locks.source_state' "$VERIFIED_RECOVERY")" == absent ]]
  [[ ! -e "$RECOVERY_DIR/source.lock" && ! -L "$RECOVERY_DIR/source.lock" ]]
fi
[[ -f "$PRIVATE_DIR/private-state.sha256" && \
  ! -L "$PRIVATE_DIR/private-state.sha256" ]]
[[ "$(sha256sum "$PRIVATE_DIR/private-state.sha256" | awk '{print $1}')" == \
  "$(jq -er '.private_manifest_sha256' "$VERIFIED_RECOVERY")" ]]
(cd "$PRIVATE_DIR" && sha256sum --check --strict private-state.sha256)

PHYSICAL_ID="$(jq -er '.postgresql.physical.id' "$VERIFIED_RECOVERY")"
LOGICAL_ID="$(jq -er '.postgresql.logical.id' "$VERIFIED_RECOVERY")"
PHYSICAL_ARCHIVE="backup/${PHYSICAL_ID%%_*}/full_${PHYSICAL_ID}.tar.zst"
LOGICAL_ARCHIVE="backup/${LOGICAL_ID%%_*}/dump_${LOGICAL_ID}.dump.zst"
PHYSICAL_MANIFEST="${PHYSICAL_ARCHIVE%.tar.zst}.manifest"
for archive in "$PHYSICAL_ARCHIVE" "$LOGICAL_ARCHIVE"; do
  [[ -f "$archive" && ! -L "$archive" ]]
  [[ -f "${archive}.sha256" && ! -L "${archive}.sha256" ]]
  stem="${archive##*/}"
  stem="${stem%.tar.zst}"
  stem="${stem%.dump.zst}"
  [[ -f "${archive%/*}/bundle_${stem}.sha256" && \
    ! -L "${archive%/*}/bundle_${stem}.sha256" ]]
  cmp -s -- "${archive}.sha256" "${archive%/*}/bundle_${stem}.sha256"
  (cd "${archive%/*}" && sha256sum --check --strict "${archive##*/}.sha256")
done
[[ "$(sha256sum "$PHYSICAL_ARCHIVE" | awk '{print $1}')" == \
  "$(jq -er '.postgresql.physical.sha256' "$VERIFIED_RECOVERY")" ]]
[[ -f "$PHYSICAL_MANIFEST" && ! -L "$PHYSICAL_MANIFEST" ]]
[[ "$(sha256sum "$PHYSICAL_MANIFEST" | awk '{print $1}')" == \
  "$(jq -er '.postgresql.physical.manifest_sha256' "$VERIFIED_RECOVERY")" ]]
[[ "$(sha256sum "$LOGICAL_ARCHIVE" | awk '{print $1}')" == \
  "$(jq -er '.postgresql.logical.sha256' "$VERIFIED_RECOVERY")" ]]
[[ "$(jq -er '.authentik_digest' "$VERIFIED_RECOVERY")" == "$CURRENT_DIGEST" ]]
[[ "$(jq -er '.postgresql.image_id' "$RECOVERY_VERSIONS")" == \
  "$CURRENT_POSTGRES_IMAGE" ]]
[[ "$(jq -er '.postgresql.maintenance_image_id' "$RECOVERY_VERSIONS")" == \
  "$CURRENT_MAINTENANCE_IMAGE" ]]

TARGET_CHANNEL_PREVIOUS_STATE=absent
TARGET_CHANNEL_PREVIOUS_IMAGE=''
TARGET_APP_IMAGE=''
probe_image_reference "$TARGET_CHANNEL"
if [[ "$IMAGE_REFERENCE_STATE" == present ]]; then
  TARGET_CHANNEL_PREVIOUS_STATE=present
  TARGET_CHANNEL_PREVIOUS_IMAGE="$IMAGE_REFERENCE_ID"
  [[ "$TARGET_CHANNEL_PREVIOUS_IMAGE" =~ ^sha256:[0-9a-f]{64}$ ]]
else
  [[ "$IMAGE_REFERENCE_STATE" == absent ]]
fi
TARGET_HOLD_REF="${PROJECT_NAME}-authentik-update-target:${RECOVERY_ID,,}"
probe_image_reference "$TARGET_HOLD_REF"
[[ "$IMAGE_REFERENCE_STATE" == absent ]]

UPDATE_DIR="$(mktemp -d ../authentik-update.XXXXXX)"
[[ "$(stat -Lc '%a:%u:%g' -- "$UPDATE_DIR")" == \
  "700:$(id -u):$(id -g)" ]]
install -m 0600 -- "$BASELINE_EVIDENCE" \
  "$UPDATE_DIR/external-baseline.json"
install -m 0600 -- "$INITIAL_FREEZE_EVIDENCE" \
  "$UPDATE_DIR/external-initial-frozen.json"
(cd "$UPDATE_DIR" && \
  sha256sum -- external-baseline.json > external-baseline.json.sha256 && \
  sha256sum -- external-initial-frozen.json \
    > external-initial-frozen.json.sha256 && \
  chmod 0600 external-*.json.sha256 && \
  sha256sum --check --strict external-baseline.json.sha256 \
    external-initial-frozen.json.sha256)
[[ "$(sha256sum "$UPDATE_DIR/external-baseline.json" | awk '{print $1}')" == \
  "$BASELINE_EVIDENCE_SHA256" ]]
[[ "$(sha256sum "$UPDATE_DIR/external-initial-frozen.json" | \
  awk '{print $1}')" == "$INITIAL_FREEZE_EVIDENCE_SHA256" ]]
discard_external_evidence_snapshot "$BASELINE_EVIDENCE"
discard_external_evidence_snapshot "$INITIAL_FREEZE_EVIDENCE"
docker run --rm --pull never --entrypoint postgres "$CURRENT_POSTGRES_IMAGE" \
  --version > "$UPDATE_DIR/current-postgresql-version.txt"
docker run --rm --pull never --entrypoint postgres "$CURRENT_MAINTENANCE_IMAGE" \
  --version > "$UPDATE_DIR/current-maintenance-postgresql-version.txt"
docker run --rm --pull never --entrypoint cat "$CURRENT_MAINTENANCE_IMAGE" \
  /usr/local/share/supercronic-release \
  > "$UPDATE_DIR/current-supercronic-release.txt"
chmod 0600 "$UPDATE_DIR"/*.txt
jq -n --arg current_channel "$CURRENT_CHANNEL" \
  --arg current_channel_image "$CURRENT_CHANNEL_REF_IMAGE" \
  --arg current_app_image "$CURRENT_APP_IMAGE" \
  --arg current_postgresql "$CURRENT_POSTGRES_IMAGE" \
  --arg current_maintenance "$CURRENT_MAINTENANCE_IMAGE" \
  --arg postgres_base_ref "$POSTGRES_BASE_REF" \
  --arg postgres_base_image "$CURRENT_POSTGRES_BASE_REF_IMAGE" \
  --arg maintenance_base_ref "$MAINTENANCE_BASE_REF" \
  --arg maintenance_base_image "$CURRENT_MAINTENANCE_BASE_REF_IMAGE" \
  --arg target_channel "$TARGET_CHANNEL" \
  --arg target_previous_state "$TARGET_CHANNEL_PREVIOUS_STATE" \
  --arg target_previous_image "$TARGET_CHANNEL_PREVIOUS_IMAGE" \
  --arg target_hold_ref "$TARGET_HOLD_REF" \
  '{schema_version:1,current:{channel:$current_channel,
      channel_image_id:$current_channel_image,app_image_id:$current_app_image,
      postgresql_image_id:$current_postgresql,
      maintenance_image_id:$current_maintenance,
      postgres_base:{ref:$postgres_base_ref,image_id:$postgres_base_image},
      maintenance_base:{ref:$maintenance_base_ref,
        image_id:$maintenance_base_image}},
    target:{channel:$target_channel,previous_state:$target_previous_state,
      previous_image_id:(if $target_previous_state == "present"
        then $target_previous_image else null end),hold_ref:$target_hold_ref}}' \
  > "$UPDATE_DIR/current-state.json"
chmod 0600 "$UPDATE_DIR/current-state.json"
(cd "$UPDATE_DIR" && sha256sum -- current-state.json \
  > current-state.json.sha256 && chmod 0600 current-state.json.sha256 && \
  sha256sum --check --strict current-state.json.sha256)

DISCOVERY_TAGS_MUTATED=false
restore_discovery_tags() {
  docker image tag "$CURRENT_CHANNEL_REF_IMAGE" "$CURRENT_CHANNEL" >/dev/null \
    || return 125
  if [[ "$TARGET_CHANNEL_PREVIOUS_STATE" == present ]]; then
    docker image tag "$TARGET_CHANNEL_PREVIOUS_IMAGE" "$TARGET_CHANNEL" \
      >/dev/null || return 125
  else
    probe_image_reference "$TARGET_CHANNEL" || return 125
    if [[ "$IMAGE_REFERENCE_STATE" == present ]]; then
      ensure_image_reference_absent "$TARGET_CHANNEL" \
        "${TARGET_APP_IMAGE:-}" || return 125
    else
      [[ "$IMAGE_REFERENCE_STATE" == absent ]] || return 125
    fi
  fi
  docker image tag "$CURRENT_POSTGRES_IMAGE" "$POSTGRES_REF" >/dev/null \
    || return 125
  docker image tag "$CURRENT_MAINTENANCE_IMAGE" "$MAINTENANCE_REF" \
    >/dev/null || return 125
  docker image tag "$CURRENT_POSTGRES_BASE_REF_IMAGE" \
    "$POSTGRES_BASE_REF" >/dev/null || return 125
  docker image tag "$CURRENT_MAINTENANCE_BASE_REF_IMAGE" \
    "$MAINTENANCE_BASE_REF" >/dev/null || return 125
  [[ "$(docker image inspect "$CURRENT_CHANNEL" --format '{{.Id}}')" == \
    "$CURRENT_CHANNEL_REF_IMAGE" ]] || return 125
  [[ "$(docker image inspect "$POSTGRES_REF" --format '{{.Id}}')" == \
    "$CURRENT_POSTGRES_IMAGE" ]] || return 125
  [[ "$(docker image inspect "$MAINTENANCE_REF" --format '{{.Id}}')" == \
    "$CURRENT_MAINTENANCE_IMAGE" ]] || return 125
  [[ "$(docker image inspect "$POSTGRES_BASE_REF" --format '{{.Id}}')" == \
    "$CURRENT_POSTGRES_BASE_REF_IMAGE" ]] || return 125
  [[ "$(docker image inspect "$MAINTENANCE_BASE_REF" --format '{{.Id}}')" == \
    "$CURRENT_MAINTENANCE_BASE_REF_IMAGE" ]] || return 125
  if [[ "$TARGET_CHANNEL_PREVIOUS_STATE" == present ]]; then
    [[ "$(docker image inspect "$TARGET_CHANNEL" --format '{{.Id}}')" == \
      "$TARGET_CHANNEL_PREVIOUS_IMAGE" ]] || return 125
  else
    probe_image_reference "$TARGET_CHANNEL" || return 125
    [[ "$IMAGE_REFERENCE_STATE" == absent ]] || return 125
  fi
  return 0
}
restart_current_writers() {
  local id pair service expected_container
  "${COMPOSE[@]}" up -d --wait --wait-timeout 300 \
    --no-build --pull never app authentik-worker || return 125
  for pair in "app:$CURRENT_APP_CONTAINER" \
    "authentik-worker:$CURRENT_WORKER_CONTAINER"; do
    service="${pair%%:*}"
    expected_container="${pair#*:}"
    id="$("${COMPOSE[@]}" ps -q "$service")" || return 125
    [[ "$id" == "$expected_container" ]] || return 125
    [[ "$(docker inspect --format '{{.Image}}' "$id")" == \
      "$CURRENT_APP_IMAGE" ]] || return 125
  done
  return 0
}
rollback_discovery() {
  local status="${1:-$?}"
  trap '' HUP INT TERM
  trap - ERR EXIT
  record_abort_gate_recovery_required "$status" || status=125
  cleanup_external_evidence_snapshots || status=125
  if [[ "$DISCOVERY_TAGS_MUTATED" == true ]]; then
    restore_discovery_tags || return 125
    restart_current_writers || return 125
    DISCOVERY_TAGS_MUTATED=false
  fi
  return "$status"
}
abort_discovery() {
  local status="$1"
  rollback_discovery "$status" || status=125
  exit "$status"
}
discovery_exit() {
  local status=$?
  if [[ "$DISCOVERY_TAGS_MUTATED" == true ]]; then
    (( status != 0 )) || status=125
    rollback_discovery "$status" || status=125
  fi
  trap - EXIT
  exit "$status"
}
trap rollback_discovery ERR
trap 'abort_discovery 129' HUP
trap 'abort_discovery 130' INT
trap 'abort_discovery 143' TERM
trap discovery_exit EXIT
DISCOVERY_TAGS_MUTATED=true
UPDATE_PHASE=discovery
if [[ "$CURRENT_CHANNEL" != "$TARGET_CHANNEL" ]]; then
  docker pull "$CURRENT_CHANNEL"
  LATEST_CURRENT_CHANNEL_IMAGE="$(docker image inspect "$CURRENT_CHANNEL" \
    --format '{{.Id}}')"
  [[ "$LATEST_CURRENT_CHANNEL_IMAGE" == "$CURRENT_APP_IMAGE" ]]
fi
DISCOVERY_DEFERRED_SIGNAL=0
defer_discovery_signal() {
  [[ "$DISCOVERY_DEFERRED_SIGNAL" == 0 ]] && \
    DISCOVERY_DEFERRED_SIGNAL="$1"
  return 0
}
trap 'defer_discovery_signal 129' HUP
trap 'defer_discovery_signal 130' INT
trap 'defer_discovery_signal 143' TERM
TARGET_PULL_STATUS=0
if docker pull "$TARGET_CHANNEL"; then
  :
else
  TARGET_PULL_STATUS=$?
fi
TARGET_ADOPTION_STATUS=0
if probe_image_reference "$TARGET_CHANNEL"; then
  if [[ "$IMAGE_REFERENCE_STATE" == present ]]; then
    TARGET_APP_IMAGE="$IMAGE_REFERENCE_ID"
  elif [[ "$IMAGE_REFERENCE_STATE" != absent ]]; then
    TARGET_ADOPTION_STATUS=125
  fi
else
  TARGET_ADOPTION_STATUS=125
fi
trap 'abort_discovery 129' HUP
trap 'abort_discovery 130' INT
trap 'abort_discovery 143' TERM
if [[ "$DISCOVERY_DEFERRED_SIGNAL" != 0 ]]; then
  abort_discovery "$DISCOVERY_DEFERRED_SIGNAL"
fi
if [[ "$TARGET_PULL_STATUS" != 0 || "$TARGET_ADOPTION_STATUS" != 0 || \
  ! "$TARGET_APP_IMAGE" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  abort_discovery 125
fi
docker pull "$POSTGRES_BASE_REF"
[[ "$MAINTENANCE_BASE_REF" == "$POSTGRES_BASE_REF" ]] || \
  docker pull "$MAINTENANCE_BASE_REF"
docker image tag "$TARGET_APP_IMAGE" "$TARGET_HOLD_REF" >/dev/null
TARGET_DIGEST="$(docker image inspect "$TARGET_APP_IMAGE" \
  --format '{{json .RepoDigests}}' | jq -er \
  '[.[] | select(startswith("ghcr.io/goauthentik/server@sha256:"))] |
    if length == 1 then .[0] else error("expected one target digest") end')"
TARGET_VERSION="$(docker image inspect "$TARGET_APP_IMAGE" \
  --format '{{index .Config.Labels "org.opencontainers.image.version"}}')"
TARGET_POSTGRES_BASE_IMAGE="$(docker image inspect "$POSTGRES_BASE_REF" \
  --format '{{.Id}}')"
TARGET_POSTGRES_BASE_DIGEST="$(docker image inspect "$POSTGRES_BASE_REF" \
  --format '{{json .RepoDigests}}' | jq -er \
  '[.[] | select(startswith("postgres@sha256:"))] |
   if length == 1 then .[0] else error("expected one PostgreSQL digest") end')"
TARGET_MAINTENANCE_BASE_IMAGE="$(docker image inspect "$MAINTENANCE_BASE_REF" \
  --format '{{.Id}}')"
TARGET_MAINTENANCE_BASE_DIGEST="$(docker image inspect "$MAINTENANCE_BASE_REF" \
  --format '{{json .RepoDigests}}' | jq -er \
  '[.[] | select(startswith("postgres@sha256:"))] |
   if length == 1 then .[0] else error("expected one maintenance-base digest") end')"
printf 'POSTGRES_IMAGE=%s\nPOSTGRES_MAINTENANCE_IMAGE=%s\n' \
  "$TARGET_POSTGRES_BASE_DIGEST" "$TARGET_MAINTENANCE_BASE_DIGEST" \
  > "$UPDATE_DIR/target-bases.env"
chmod 0600 "$UPDATE_DIR/target-bases.env"
BUILD_COMPOSE=(docker compose --env-file .env \
  --env-file "$UPDATE_DIR/target-bases.env" -f docker-compose.main.yaml)
"${BUILD_COMPOSE[@]}" build --pull --no-cache \
  postgresql postgresql_maintenance
TARGET_POSTGRES_IMAGE="$(docker image inspect "$POSTGRES_REF" --format '{{.Id}}')"
TARGET_MAINTENANCE_IMAGE="$(docker image inspect "$MAINTENANCE_REF" \
  --format '{{.Id}}')"
docker run --rm --pull never --entrypoint postgres "$TARGET_POSTGRES_IMAGE" \
  --version > "$UPDATE_DIR/target-postgresql-version.txt"
docker run --rm --pull never --entrypoint postgres "$TARGET_MAINTENANCE_IMAGE" \
  --version > "$UPDATE_DIR/target-maintenance-postgresql-version.txt"
docker run --rm --pull never --entrypoint cat "$TARGET_MAINTENANCE_IMAGE" \
  /usr/local/share/supercronic-release \
  > "$UPDATE_DIR/target-supercronic-release.txt"
chmod 0600 "$UPDATE_DIR"/target-*.txt
TARGET_SUPERCRONIC_RELEASE="$(sed -n 's/^release=//p' \
  "$UPDATE_DIR/target-supercronic-release.txt")"
TARGET_SUPERCRONIC_ASSET="$(sed -n 's/^asset=//p' \
  "$UPDATE_DIR/target-supercronic-release.txt")"
TARGET_SUPERCRONIC_DIGEST="$(sed -n 's/^digest=//p' \
  "$UPDATE_DIR/target-supercronic-release.txt")"
[[ "$TARGET_SUPERCRONIC_RELEASE" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
[[ "$TARGET_SUPERCRONIC_ASSET" =~ ^supercronic-linux-(amd64|arm64)$ ]]
[[ "$TARGET_SUPERCRONIC_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ "$CURRENT_APP_IMAGE" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ "$TARGET_APP_IMAGE" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ "$TARGET_POSTGRES_IMAGE" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ "$TARGET_MAINTENANCE_IMAGE" =~ ^sha256:[0-9a-f]{64}$ ]]
[[ -n "$CURRENT_VERSION" && "$CURRENT_VERSION" != '<no value>' ]]
[[ -n "$TARGET_VERSION" && "$TARGET_VERSION" != '<no value>' ]]

restore_discovery_tags
DISCOVERY_TAGS_MUTATED=false
REVIEW_ACTIVE=true
cleanup_review_failure() {
  local status="${1:-$?}"
  trap '' HUP INT TERM
  trap - ERR EXIT
  record_abort_gate_recovery_required "$status" || status=125
  cleanup_external_evidence_snapshots || status=125
  if [[ "$REVIEW_ACTIVE" == true ]]; then
    restore_discovery_tags || return 125
    restart_current_writers || return 125
    REVIEW_ACTIVE=false
  fi
  return "$status"
}
abort_review() {
  local status="$1"
  cleanup_review_failure "$status" || status=125
  exit "$status"
}
review_exit() {
  local status=$?
  if [[ "$REVIEW_ACTIVE" == true ]]; then
    (( status != 0 )) || status=125
    cleanup_review_failure "$status" || status=125
  fi
  trap - EXIT
  exit "$status"
}
trap cleanup_review_failure ERR
trap 'abort_review 129' HUP
trap 'abort_review 130' INT
trap 'abort_review 143' TERM
trap review_exit EXIT
[[ "$(docker image inspect "$CURRENT_CHANNEL" --format '{{.Id}}')" == \
  "$CURRENT_CHANNEL_REF_IMAGE" ]]
if [[ "$TARGET_CHANNEL_PREVIOUS_STATE" == present ]]; then
  [[ "$(docker image inspect "$TARGET_CHANNEL" --format '{{.Id}}')" == \
    "$TARGET_CHANNEL_PREVIOUS_IMAGE" ]]
else
  probe_image_reference "$TARGET_CHANNEL"
  [[ "$IMAGE_REFERENCE_STATE" == absent ]]
fi
[[ "$(docker image inspect "$TARGET_HOLD_REF" --format '{{.Id}}')" == \
  "$TARGET_APP_IMAGE" ]]
[[ "$(docker image inspect "$POSTGRES_REF" --format '{{.Id}}')" == \
  "$CURRENT_POSTGRES_IMAGE" ]]
[[ "$(docker image inspect "$MAINTENANCE_REF" --format '{{.Id}}')" == \
  "$CURRENT_MAINTENANCE_IMAGE" ]]
for service in app authentik-worker; do
  id="$("${COMPOSE[@]}" ps -a -q "$service")"
  [[ "$(docker inspect --format '{{.Image}}' "$id")" == \
    "$CURRENT_APP_IMAGE" ]]
  [[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
    "$id")" == exited:0 ]]
done
for pair in "postgresql:$CURRENT_POSTGRES_IMAGE" \
  "postgresql_maintenance:$CURRENT_MAINTENANCE_IMAGE"; do
  service="${pair%%:*}"
  image_id="${pair#*:}"
  [[ "$(docker inspect --format '{{.Image}}' \
    "$("${COMPOSE[@]}" ps -q "$service")")" == "$image_id" ]]
done
[[ "$(docker inspect --format '{{.Image}}' \
  "$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)")" == \
  "$CURRENT_APP_IMAGE" ]]

RELEASE_NOTES_REVIEW="$UPDATE_DIR/release-notes-review.txt"
CURRENT_SERIES="$(sed -nE 's/^([0-9]{4}\.[0-9]+)\..*$/\1/p' \
  <<<"$CURRENT_VERSION")"
TARGET_SERIES="$(sed -nE 's/^([0-9]{4}\.[0-9]+)\..*$/\1/p' \
  <<<"$TARGET_VERSION")"
[[ "$CURRENT_SERIES" == "$CURRENT_CHANNEL_SERIES" ]]
[[ "$TARGET_SERIES" == "$TARGET_CHANNEL_SERIES" ]]
[[ "$TARGET_SERIES" == "$CURRENT_SERIES" || \
  "$CURRENT_SERIES:$TARGET_SERIES" == 2026.5:2026.8 ]]
CURRENT_POSTGRES_VERSION="$(<"$UPDATE_DIR/current-postgresql-version.txt")"
CURRENT_MAINTENANCE_POSTGRES_VERSION="$(
  <"$UPDATE_DIR/current-maintenance-postgresql-version.txt"
)"
TARGET_POSTGRES_VERSION="$(<"$UPDATE_DIR/target-postgresql-version.txt")"
TARGET_MAINTENANCE_POSTGRES_VERSION="$(
  <"$UPDATE_DIR/target-maintenance-postgresql-version.txt"
)"
[[ "$CURRENT_POSTGRES_VERSION" == *'PostgreSQL 18'* ]]
[[ "$CURRENT_MAINTENANCE_POSTGRES_VERSION" == *'PostgreSQL 18'* ]]
[[ "$TARGET_POSTGRES_VERSION" == *'PostgreSQL 18'* ]]
[[ "$TARGET_MAINTENANCE_POSTGRES_VERSION" == *'PostgreSQL 18'* ]]
printf '%s\n' \
  "current_version=$CURRENT_VERSION" \
  "target_version=$TARGET_VERSION" \
  "current_series=$CURRENT_SERIES" \
  "target_series=$TARGET_SERIES" \
  "postgres_base_digest=$TARGET_POSTGRES_BASE_DIGEST" \
  "maintenance_base_digest=$TARGET_MAINTENANCE_BASE_DIGEST" \
  "current_postgresql_version=$CURRENT_POSTGRES_VERSION" \
  "current_maintenance_postgresql_version=$CURRENT_MAINTENANCE_POSTGRES_VERSION" \
  "target_postgresql_version=$TARGET_POSTGRES_VERSION" \
  "target_maintenance_postgresql_version=$TARGET_MAINTENANCE_POSTGRES_VERSION" \
  "supercronic_release=$TARGET_SUPERCRONIC_RELEASE" \
  "supercronic_asset=$TARGET_SUPERCRONIC_ASSET" \
  "supercronic_digest=$TARGET_SUPERCRONIC_DIGEST" \
  "reviewed_url=https://docs.goauthentik.io/releases/$CURRENT_SERIES/" \
  "reviewed_url=https://docs.goauthentik.io/releases/$TARGET_SERIES/" \
  'reviewed_url=https://docs.goauthentik.io/install-config/upgrade/' \
  'reviewed_url=https://docs.goauthentik.io/install-config/configuration/#authentik_web__base_url' \
  'reviewed_url=https://www.postgresql.org/docs/18/release.html' \
  "reviewed_url=https://github.com/aptible/supercronic/releases/tag/$TARGET_SUPERCRONIC_RELEASE" \
  'operator_approval=REPLACE_WITH_APPROVED' > "$RELEASE_NOTES_REVIEW"
chmod 0600 "$RELEASE_NOTES_REVIEW"
printf 'Review every URL in %s, then change only the final value to approved.\n' \
  "$RELEASE_NOTES_REVIEW"
UPDATE_PHASE=review
read -r -p 'Type REVIEWED after saving the reviewed file: ' REVIEW_CONFIRMATION
[[ "$REVIEW_CONFIRMATION" == REVIEWED ]]
[[ -f "$RELEASE_NOTES_REVIEW" && ! -L "$RELEASE_NOTES_REVIEW" ]]
grep -Fx "current_version=$CURRENT_VERSION" "$RELEASE_NOTES_REVIEW"
grep -Fx "target_version=$TARGET_VERSION" "$RELEASE_NOTES_REVIEW"
grep -Fx "current_series=$CURRENT_SERIES" "$RELEASE_NOTES_REVIEW"
grep -Fx "target_series=$TARGET_SERIES" "$RELEASE_NOTES_REVIEW"
grep -Fx "postgres_base_digest=$TARGET_POSTGRES_BASE_DIGEST" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "maintenance_base_digest=$TARGET_MAINTENANCE_BASE_DIGEST" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "current_postgresql_version=$CURRENT_POSTGRES_VERSION" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "current_maintenance_postgresql_version=$CURRENT_MAINTENANCE_POSTGRES_VERSION" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "supercronic_release=$TARGET_SUPERCRONIC_RELEASE" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "target_postgresql_version=$TARGET_POSTGRES_VERSION" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "target_maintenance_postgresql_version=$TARGET_MAINTENANCE_POSTGRES_VERSION" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "supercronic_asset=$TARGET_SUPERCRONIC_ASSET" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "supercronic_digest=$TARGET_SUPERCRONIC_DIGEST" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "reviewed_url=https://docs.goauthentik.io/releases/$CURRENT_SERIES/" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "reviewed_url=https://docs.goauthentik.io/releases/$TARGET_SERIES/" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx 'reviewed_url=https://docs.goauthentik.io/install-config/upgrade/' \
  "$RELEASE_NOTES_REVIEW"
grep -Fx 'reviewed_url=https://docs.goauthentik.io/install-config/configuration/#authentik_web__base_url' \
  "$RELEASE_NOTES_REVIEW"
grep -Fx 'reviewed_url=https://www.postgresql.org/docs/18/release.html' \
  "$RELEASE_NOTES_REVIEW"
grep -Fx "reviewed_url=https://github.com/aptible/supercronic/releases/tag/$TARGET_SUPERCRONIC_RELEASE" \
  "$RELEASE_NOTES_REVIEW"
grep -Fx 'operator_approval=approved' "$RELEASE_NOTES_REVIEW"
[[ "$(wc -l < "$RELEASE_NOTES_REVIEW")" == 20 ]]

install -m 0600 -- "$RELEASE_NOTES_REVIEW" "$UPDATE_DIR/release-notes.txt"
jq -n --arg current_channel "$CURRENT_CHANNEL" \
  --arg current_series "$CURRENT_SERIES" \
  --arg target_channel "$TARGET_CHANNEL" \
  --arg target_series "$TARGET_SERIES" \
  --arg current_channel_ref_image "$CURRENT_CHANNEL_REF_IMAGE" \
  --arg current_image "$CURRENT_APP_IMAGE" \
  --arg current_digest "$CURRENT_DIGEST" --arg current_version "$CURRENT_VERSION" \
  --arg target_image "$TARGET_APP_IMAGE" --arg target_digest "$TARGET_DIGEST" \
  --arg target_version "$TARGET_VERSION" --arg target_hold_ref "$TARGET_HOLD_REF" \
  --arg target_previous_state "$TARGET_CHANNEL_PREVIOUS_STATE" \
  --arg target_previous_image "$TARGET_CHANNEL_PREVIOUS_IMAGE" \
  --arg expected_base_url "$EXPECTED_BASE_URL" \
  --arg authentik_url_sha "$AUTHENTIK_URL_SHA256" \
  --arg erpnext_url_sha "$ERPNEXT_URL_SHA256" \
  --arg forward_url_sha "$FORWARD_AUTH_URL_SHA256" \
  --arg evidence_vantage "$EVIDENCE_VANTAGE_ID" \
  --arg baseline_evidence_sha "$BASELINE_EVIDENCE_SHA256" \
  --arg initial_freeze_evidence_sha "$INITIAL_FREEZE_EVIDENCE_SHA256" \
  --arg external_outposts "$EXTERNAL_OUTPOSTS" \
  --arg current_postgresql "$CURRENT_POSTGRES_IMAGE" \
  --arg target_postgresql "$TARGET_POSTGRES_IMAGE" \
  --arg current_maintenance "$CURRENT_MAINTENANCE_IMAGE" \
  --arg target_maintenance "$TARGET_MAINTENANCE_IMAGE" \
  --arg postgres_base_ref "$POSTGRES_BASE_REF" \
  --arg current_postgres_base "$CURRENT_POSTGRES_BASE_REF_IMAGE" \
  --arg postgres_base_image "$TARGET_POSTGRES_BASE_IMAGE" \
  --arg postgres_base_digest "$TARGET_POSTGRES_BASE_DIGEST" \
  --arg maintenance_base_ref "$MAINTENANCE_BASE_REF" \
  --arg current_maintenance_base "$CURRENT_MAINTENANCE_BASE_REF_IMAGE" \
  --arg maintenance_base_image "$TARGET_MAINTENANCE_BASE_IMAGE" \
  --arg maintenance_base_digest "$TARGET_MAINTENANCE_BASE_DIGEST" \
  --arg current_pg_sha "$(sha256sum "$UPDATE_DIR/current-postgresql-version.txt" | awk '{print $1}')" \
  --arg target_pg_sha "$(sha256sum "$UPDATE_DIR/target-postgresql-version.txt" | awk '{print $1}')" \
  --arg current_maintenance_pg_sha "$(sha256sum "$UPDATE_DIR/current-maintenance-postgresql-version.txt" | awk '{print $1}')" \
  --arg target_maintenance_pg_sha "$(sha256sum "$UPDATE_DIR/target-maintenance-postgresql-version.txt" | awk '{print $1}')" \
  --arg current_sc_sha "$(sha256sum "$UPDATE_DIR/current-supercronic-release.txt" | awk '{print $1}')" \
  --arg target_sc_sha "$(sha256sum "$UPDATE_DIR/target-supercronic-release.txt" | awk '{print $1}')" \
  --arg recovery_id "$(jq -er '.id' "$VERIFIED_RECOVERY")" \
  --arg recovery_sha "$(sha256sum "$VERIFIED_RECOVERY" | awk '{print $1}')" \
  --arg release_notes_sha "$(sha256sum "$UPDATE_DIR/release-notes.txt" | awk '{print $1}')" \
  '{schema_version:4,configuration:{base_url:$expected_base_url,
      external_probe_url_sha256:{authentik:$authentik_url_sha,
        erpnext_oidc:$erpnext_url_sha,
        forward_auth:(if $forward_url_sha == "none" then null
          else $forward_url_sha end)}},
    operational_gate:{external_evidence:{vantage_id:$evidence_vantage,
      baseline_sha256:$baseline_evidence_sha,
      initial_frozen_sha256:$initial_freeze_evidence_sha},
      external_outposts:$external_outposts},
    current:{channel:$current_channel,series:$current_series,
      image_id:$current_image,channel_image_id:$current_channel_ref_image,
      digest:$current_digest,version:$current_version},
    target:{channel:$target_channel,series:$target_series,image_id:$target_image,
      digest:$target_digest,version:$target_version,hold_ref:$target_hold_ref,
      previous_channel_tag:{state:$target_previous_state,
        image_id:(if $target_previous_state == "present"
          then $target_previous_image else null end)}},
    postgresql:{current_image_id:$current_postgresql,
      target_image_id:$target_postgresql,base:{ref:$postgres_base_ref,
        current_image_id:$current_postgres_base,
        target_image_id:$postgres_base_image,digest:$postgres_base_digest},
      current_version_sha256:$current_pg_sha,target_version_sha256:$target_pg_sha},
    maintenance:{current_image_id:$current_maintenance,
      target_image_id:$target_maintenance,base:{ref:$maintenance_base_ref,
        current_image_id:$current_maintenance_base,
        target_image_id:$maintenance_base_image,digest:$maintenance_base_digest},
      current_postgresql_version_sha256:$current_maintenance_pg_sha,
      target_postgresql_version_sha256:$target_maintenance_pg_sha,
      current_release_sha256:$current_sc_sha,
      target_release_sha256:$target_sc_sha},
    verified_recovery:{id:$recovery_id,sha256:$recovery_sha},
    release_notes:{sha256:$release_notes_sha}}' > "$UPDATE_DIR/update.json"
chmod 0600 "$UPDATE_DIR/update.json"
(cd "$UPDATE_DIR" && sha256sum -- update.json > update.json.sha256 && \
  chmod 0600 update.json.sha256 && sha256sum --check --strict update.json.sha256)
jq -e --arg current "$CURRENT_CHANNEL" --arg target "$TARGET_CHANNEL" \
  --arg current_series "$CURRENT_SERIES" --arg target_series "$TARGET_SERIES" \
  --arg hold "$TARGET_HOLD_REF" --arg base_url "$EXPECTED_BASE_URL" \
  --arg authentik_url_sha "$AUTHENTIK_URL_SHA256" \
  --arg erpnext_url_sha "$ERPNEXT_URL_SHA256" \
  --arg forward_url_sha "$FORWARD_AUTH_URL_SHA256" '
  .schema_version == 4 and .current.channel == $current and
  .current.series == $current_series and .target.channel == $target and
  .target.series == $target_series and .target.hold_ref == $hold and
  .configuration.base_url == $base_url and
  .configuration.external_probe_url_sha256.authentik ==
    $authentik_url_sha and
  .configuration.external_probe_url_sha256.erpnext_oidc ==
    $erpnext_url_sha and
  .configuration.external_probe_url_sha256.forward_auth ==
    (if $forward_url_sha == "none" then null else $forward_url_sha end) and
  (.operational_gate.external_evidence.vantage_id | length >= 3) and
  ([.operational_gate.external_evidence.baseline_sha256,
    .operational_gate.external_evidence.initial_frozen_sha256] |
    all(test("^[0-9a-f]{64}$"))) and
  (.operational_gate.external_outposts | length > 0) and
  (.target.previous_channel_tag.state == "present" or
    .target.previous_channel_tag.state == "absent")
' "$UPDATE_DIR/update.json" >/dev/null

rewrite_app_image() {
  local image="$1" temporary
  temporary="$(mktemp ./app.env.image.XXXXXX)" || return 125
  if ! awk -v image="$image" '
    BEGIN { count=0 }
    /^APP_IMAGE=/ { print "APP_IMAGE=" image; count++; next }
    { print }
    END { if (count != 1) exit 1 }
  ' app.env > "$temporary"; then
    rm -f -- "$temporary"
    return 125
  fi
  chmod "$(stat -Lc '%a' -- app.env)" "$temporary" || {
    rm -f -- "$temporary"
    return 125
  }
  mv -fT -- "$temporary" app.env || {
    rm -f -- "$temporary"
    return 125
  }
  return 0
}

# Phæse 2: only reviewed, locæl, immutæble outputs cross this boundary.
UPDATE_PHASE=pre-migration
DESTRUCTIVE_STARTED=false
MIGRATION_STARTED=false
PHASE2_COMPLETE=false
rollback_pre_migration_update() {
  local status="${1:-$?}" id service
  trap '' HUP INT TERM
  trap - ERR EXIT
  record_abort_gate_recovery_required "$status" || status=125
  cleanup_external_evidence_snapshots || status=125
  if [[ "$MIGRATION_STARTED" == true ]]; then
    "${COMPOSE[@]}" down || return 125
    return "$status"
  fi
  if [[ "$DESTRUCTIVE_STARTED" == true ]]; then
    "${COMPOSE[@]}" down || return 125
  fi
  if [[ "$PHASE2_COMPLETE" == false ]]; then
    restore_discovery_tags || return 125
    rewrite_app_image "$CURRENT_CHANNEL" || return 125
    run_authentik_with_inherited_operation_lock || return 125
    "${COMPOSE[@]}" up -d --wait --wait-timeout 120 \
      --no-build --pull never postgresql || return 125
    "${COMPOSE[@]}" up -d --wait --wait-timeout 300 \
      --no-build --pull never app authentik-worker || return 125
    for service in app authentik-worker; do
      id="$("${COMPOSE[@]}" ps -q "$service")"
      [[ "$(docker inspect --format '{{.Image}}' "$id")" == \
        "$CURRENT_APP_IMAGE" ]] || return 125
    done
    id="$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)"
    [[ "$(docker inspect --format '{{.Image}}' "$id")" == \
      "$CURRENT_APP_IMAGE" ]] || return 125
    [[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
      "$id")" == exited:0 ]] || return 125
    "${COMPOSE[@]}" up -d --no-build --pull never \
      postgresql_maintenance || return 125
    PHASE2_COMPLETE=true
  fi
  return "$status"
}
abort_phase2() {
  local status="$1"
  rollback_pre_migration_update "$status" || status=125
  exit "$status"
}
phase2_exit() {
  local status=$?
  if [[ "$PHASE2_COMPLETE" == false ]]; then
    [[ "$status" -ne 0 ]] || status=125
    rollback_pre_migration_update "$status" || status=125
  fi
  trap - EXIT
  exit "$status"
}
trap rollback_pre_migration_update ERR
trap 'abort_phase2 129' HUP
trap 'abort_phase2 130' INT
trap 'abort_phase2 143' TERM
trap phase2_exit EXIT
REVIEW_ACTIVE=false

TRAFFIC_FROZEN_OVERRIDE="$UPDATE_DIR/docker-compose.traffic-frozen.yaml"
cat > "$TRAFFIC_FROZEN_OVERRIDE" <<'YAML'
services:
  app:
    labels: !override
      - traefik.enable=false
    networks: !override
      backend: {}
    ports: !override []
    expose: !override []
YAML
chmod 0600 "$TRAFFIC_FROZEN_OVERRIDE"
CLOSED_COMPOSE=("${COMPOSE[@]}" -f "$TRAFFIC_FROZEN_OVERRIDE")
CLOSED_CONFIG="$("${CLOSED_COMPOSE[@]}" config --format json)"
jq -e '
  .services.app.labels["traefik.enable"] == "false" and
  (.services.app.networks | keys) == ["backend"] and
  ((.services.app.ports // []) | length) == 0 and
  ((.services.app.expose // []) | length) == 0
' <<<"$CLOSED_CONFIG" >/dev/null
for id in "$CURRENT_APP_IMAGE" "$CURRENT_POSTGRES_IMAGE" \
  "$CURRENT_MAINTENANCE_IMAGE" "$TARGET_APP_IMAGE" \
  "$TARGET_POSTGRES_IMAGE" "$TARGET_MAINTENANCE_IMAGE" \
  "$TARGET_POSTGRES_BASE_IMAGE" "$TARGET_MAINTENANCE_BASE_IMAGE"; do
  [[ "$(docker image inspect "$id" --format '{{.Id}}')" == "$id" ]]
done
[[ "$(docker image inspect "$TARGET_HOLD_REF" --format '{{.Id}}')" == \
  "$TARGET_APP_IMAGE" ]]
[[ "$("${COMPOSE[@]}" ps -a -q app)" == "$CURRENT_APP_CONTAINER" ]]
[[ "$("${COMPOSE[@]}" ps -a -q authentik-worker)" == \
  "$CURRENT_WORKER_CONTAINER" ]]
[[ "$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)" == \
  "$CURRENT_BOOTSTRAP_CONTAINER" ]]
[[ "$("${COMPOSE[@]}" ps -q postgresql)" == "$CURRENT_POSTGRES_CONTAINER" ]]
[[ "$("${COMPOSE[@]}" ps -q postgresql_maintenance)" == \
  "$CURRENT_MAINTENANCE_CONTAINER" ]]
for id in "$CURRENT_APP_CONTAINER" "$CURRENT_WORKER_CONTAINER"; do
  [[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
    "$id")" == exited:0 ]]
done
CUTOVER_PROOF_NOT_BEFORE="$(date -u +%s)"
printf 'Capture fresh cutover-frozen evidence from vantage %s now.\n' \
  "$EVIDENCE_VANTAGE_ID"
read -r -p 'External cutover-frozen evidence JSON: ' \
  CUTOVER_FREEZE_EVIDENCE_REQUESTED
CUTOVER_EPOCH="$(date -u +%s)"
verify_external_evidence "$CUTOVER_FREEZE_EVIDENCE_REQUESTED" cutover-frozen \
  "$CUTOVER_PROOF_NOT_BEFORE" "$CUTOVER_EPOCH" "$MAINTENANCE_MARKER"
(( CUTOVER_EPOCH - VALIDATED_EVIDENCE_EPOCH <= 300 ))
CUTOVER_FREEZE_EVIDENCE="$VALIDATED_EVIDENCE_PATH"
CUTOVER_FREEZE_EVIDENCE_SHA256="$VALIDATED_EVIDENCE_SHA256"
CUTOVER_FREEZE_EVIDENCE_EPOCH="$VALIDATED_EVIDENCE_EPOCH"
install -m 0600 -- "$CUTOVER_FREEZE_EVIDENCE" \
  "$UPDATE_DIR/external-cutover-frozen.json"
(cd "$UPDATE_DIR" && \
  sha256sum -- external-cutover-frozen.json \
    > external-cutover-frozen.json.sha256 && \
  chmod 0600 external-cutover-frozen.json.sha256 && \
  sha256sum --check --strict external-cutover-frozen.json.sha256)
[[ "$(sha256sum "$UPDATE_DIR/external-cutover-frozen.json" | \
  awk '{print $1}')" == "$CUTOVER_FREEZE_EVIDENCE_SHA256" ]]
discard_external_evidence_snapshot "$CUTOVER_FREEZE_EVIDENCE"
(( RECOVERY_EPOCH <= CUTOVER_EPOCH ))
(( CUTOVER_EPOCH - RECOVERY_EPOCH <= RECOVERY_MAX_AGE_SECONDS ))
(cd "$UPDATE_DIR" && \
  sha256sum --check --strict current-state.json.sha256 update.json.sha256)
(cd "$RECOVERY_DIR" && sha256sum --check --strict recovery.json.sha256)
for field in files control runtime_images; do
  archive="$(jq -er --arg field "$field" '.[$field].name' \
    "$VERIFIED_RECOVERY")"
  (cd "$RECOVERY_DIR" && sha256sum --check --strict "${archive}.sha256")
done
[[ "$(sha256sum "$RECOVERY_VERSIONS" | awk '{print $1}')" == \
  "$(jq -er '.versions_sha256' "$VERIFIED_RECOVERY")" ]]
[[ "$(sha256sum "$RECOVERY_DIR/templates.lock" | awk '{print $1}')" == \
  "$(jq -er '.locks.template_sha256' "$VERIFIED_RECOVERY")" ]]
if [[ "$(jq -er '.locks.source_state' "$VERIFIED_RECOVERY")" == present ]]; then
  [[ "$(sha256sum "$RECOVERY_DIR/source.lock" | awk '{print $1}')" == \
    "$(jq -er '.locks.source_sha256' "$VERIFIED_RECOVERY")" ]]
fi
(cd "$PRIVATE_DIR" && sha256sum --check --strict private-state.sha256)
for archive in "$PHYSICAL_ARCHIVE" "$LOGICAL_ARCHIVE"; do
  (cd "${archive%/*}" && sha256sum --check --strict \
    "${archive##*/}.sha256")
done
[[ "$(sha256sum "$PHYSICAL_MANIFEST" | awk '{print $1}')" == \
  "$(jq -er '.postgresql.physical.manifest_sha256' \
    "$VERIFIED_RECOVERY")" ]]
DESTRUCTIVE_EPOCH="$(date -u +%s)"
(( RECOVERY_EPOCH <= DESTRUCTIVE_EPOCH ))
(( DESTRUCTIVE_EPOCH - RECOVERY_EPOCH <= RECOVERY_MAX_AGE_SECONDS ))
(( CUTOVER_FREEZE_EVIDENCE_EPOCH <= DESTRUCTIVE_EPOCH ))
(( DESTRUCTIVE_EPOCH - CUTOVER_FREEZE_EVIDENCE_EPOCH <= 300 ))
DESTRUCTIVE_STARTED=true
"${COMPOSE[@]}" down
RUNNING_CONTAINERS="$("${COMPOSE[@]}" ps --status running -q)"
[[ -z "$RUNNING_CONTAINERS" ]]
docker image tag "$TARGET_POSTGRES_IMAGE" "$POSTGRES_REF" >/dev/null
docker image tag "$TARGET_MAINTENANCE_IMAGE" "$MAINTENANCE_REF" >/dev/null
[[ "$(docker image inspect "$POSTGRES_REF" --format '{{.Id}}')" == \
  "$TARGET_POSTGRES_IMAGE" ]]
[[ "$(docker image inspect "$MAINTENANCE_REF" --format '{{.Id}}')" == \
  "$TARGET_MAINTENANCE_IMAGE" ]]
rewrite_app_image "$TARGET_HOLD_REF"
run_authentik_with_inherited_operation_lock
MIGRATION_STARTED=true
UPDATE_PHASE=migration-started
"${COMPOSE[@]}" up -d --wait --wait-timeout 120 \
  --no-build --pull never postgresql
"${CLOSED_COMPOSE[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never app
TARGET_CONTAINER="$("${COMPOSE[@]}" ps -q app)"
UPDATE_BOOTSTRAP="$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)"
for id in "$TARGET_CONTAINER" "$UPDATE_BOOTSTRAP"; do
  [[ "$id" =~ ^[0-9a-f]{64}$ ]]
done
[[ "$(docker inspect --format '{{.Image}}' "$TARGET_CONTAINER")" == \
  "$TARGET_APP_IMAGE" ]]
[[ "$(docker inspect --format '{{.Image}}' "$UPDATE_BOOTSTRAP")" == \
  "$TARGET_APP_IMAGE" ]]
[[ -z "$("${COMPOSE[@]}" ps -a -q authentik-worker)" ]]
[[ "$(docker inspect --format '{{.Image}}' \
  "$("${COMPOSE[@]}" ps -q postgresql)")" == "$TARGET_POSTGRES_IMAGE" ]]
[[ "$(docker image inspect "$TARGET_APP_IMAGE" \
  --format '{{index .Config.Labels "org.opencontainers.image.version"}}')" == \
  "$TARGET_VERSION" ]]
[[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
  "$UPDATE_BOOTSTRAP")" == exited:0 ]]
[[ "$(docker inspect --format '{{index .Config.Labels "traefik.enable"}}' \
  "$TARGET_CONTAINER")" == false ]]
[[ "$(docker inspect --format '{{json .NetworkSettings.Networks}}' \
  "$TARGET_CONTAINER" | jq 'keys | length')" == 1 ]]
[[ "$(docker inspect --format '{{json .HostConfig.PortBindings}}' \
  "$TARGET_CONTAINER" | jq 'length')" == 0 ]]
TARGET_FREEZE_NOT_BEFORE="$(date -u +%s)"
printf 'Capture fresh target-frozen evidence from vantage %s now.\n' \
  "$EVIDENCE_VANTAGE_ID"
read -r -p 'External target-frozen evidence JSON: ' \
  TARGET_FREEZE_EVIDENCE_REQUESTED
TARGET_FREEZE_NOW="$(date -u +%s)"
verify_external_evidence "$TARGET_FREEZE_EVIDENCE_REQUESTED" target-frozen \
  "$TARGET_FREEZE_NOT_BEFORE" "$TARGET_FREEZE_NOW" "$MAINTENANCE_MARKER"
(( TARGET_FREEZE_NOW - VALIDATED_EVIDENCE_EPOCH <= 300 ))
TARGET_FREEZE_EVIDENCE="$VALIDATED_EVIDENCE_PATH"
TARGET_FREEZE_EVIDENCE_SHA256="$VALIDATED_EVIDENCE_SHA256"
install -m 0600 -- "$TARGET_FREEZE_EVIDENCE" \
  "$UPDATE_DIR/external-target-frozen.json"
(cd "$UPDATE_DIR" && \
  sha256sum -- external-target-frozen.json \
    > external-target-frozen.json.sha256 && \
  chmod 0600 external-target-frozen.json.sha256 && \
  sha256sum --check --strict external-target-frozen.json.sha256)
[[ "$(sha256sum "$UPDATE_DIR/external-target-frozen.json" | \
  awk '{print $1}')" == "$TARGET_FREEZE_EVIDENCE_SHA256" ]]
discard_external_evidence_snapshot "$TARGET_FREEZE_EVIDENCE"
"${CLOSED_COMPOSE[@]}" up -d --no-build --pull never \
  postgresql_maintenance
[[ "$(docker inspect --format '{{.Image}}' \
  "$("${COMPOSE[@]}" ps -q postgresql_maintenance)")" == \
  "$TARGET_MAINTENANCE_IMAGE" ]]
"${COMPOSE[@]}" exec -T postgresql_maintenance \
  /usr/local/bin/backup.sh full
"${CLOSED_COMPOSE[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never postgresql_maintenance
BASE_URL_EVIDENCE="$(docker exec "$TARGET_CONTAINER" python3 -c '
import os
from authentik.root.setup import setup
setup()
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "authentik.root.settings")
import django
django.setup()
from authentik.tenants.models import Tenant
values = set(Tenant.objects.filter(ready=True).values_list("base_url", flat=True))
if len(values) != 1:
    raise SystemExit(1)
print("PERSISTED_BASE_URL=" + values.pop())
')"
[[ "$(grep -c '^PERSISTED_BASE_URL=' <<<"$BASE_URL_EVIDENCE")" == 1 ]]
PERSISTED_BASE_URL="$(sed -n 's/^PERSISTED_BASE_URL=//p' \
  <<<"$BASE_URL_EVIDENCE")"
[[ "$PERSISTED_BASE_URL" == "$EXPECTED_BASE_URL" ]]
docker image tag "$TARGET_APP_IMAGE" "$TARGET_CHANNEL" >/dev/null
docker image tag "$TARGET_POSTGRES_BASE_IMAGE" "$POSTGRES_BASE_REF" >/dev/null
docker image tag "$TARGET_MAINTENANCE_BASE_IMAGE" \
  "$MAINTENANCE_BASE_REF" >/dev/null
rewrite_app_image "$TARGET_CHANNEL"
run_authentik_with_inherited_operation_lock
FINAL_CONFIG="$("${COMPOSE[@]}" config --format json)"
[[ "$(grep -Fxc "APP_IMAGE=$TARGET_CHANNEL" app.env)" == 1 ]]
[[ "$(grep -Fxc "APP_IMAGE=$TARGET_CHANNEL" .env)" == 1 ]]
jq -e --arg image "$TARGET_CHANNEL" --arg base_url "$EXPECTED_BASE_URL" \
  --arg rule "$EXPECTED_TRAEFIK_RULE" '
  .services.app.image == $image and
  .services["authentik-worker"].image == $image and
  .services["authentik-bootstrap"].image == $image and
  .services["authentik-bootstrap"].environment.AUTHENTIK_WEB__BASE_URL ==
    $base_url and
  .services["authentik-bootstrap"].environment.AUTHENTIK_TRAEFIK_HOST_RULE ==
    $rule and
  ((.services.app.environment | has("AUTHENTIK_WEB__BASE_URL")) | not) and
  ((.services.app.environment | has("AUTHENTIK_TRAEFIK_HOST_RULE")) | not) and
  ((.services["authentik-worker"].environment |
    has("AUTHENTIK_WEB__BASE_URL")) | not) and
  ((.services["authentik-worker"].environment |
    has("AUTHENTIK_TRAEFIK_HOST_RULE")) | not)
' <<<"$FINAL_CONFIG" >/dev/null
[[ "$(docker image inspect "$TARGET_CHANNEL" --format '{{.Id}}')" == \
  "$TARGET_APP_IMAGE" ]]
[[ "$(docker inspect --format '{{.Image}}' \
  "$("${COMPOSE[@]}" ps -q app)")" == "$TARGET_APP_IMAGE" ]]
[[ "$(docker inspect --format '{{.Config.Image}}' \
  "$("${COMPOSE[@]}" ps -q app)")" == "$TARGET_HOLD_REF" ]]
[[ "$(docker inspect --format '{{.Config.Image}}' "$UPDATE_BOOTSTRAP")" == \
  "$TARGET_HOLD_REF" ]]
[[ -z "$("${COMPOSE[@]}" ps -a -q authentik-worker)" ]]

# Controlled reopening: if æny following proof fæils, the phæse-2 træp stops
# the possibly migræted project ænd preserves every recovery/hold ærtifæct.
UPDATE_PHASE=management-gate-arm
read -r -p 'Type MANAGEMENT_ONLY_GATE_ACTIVE after limiting public clients: ' \
  MANAGEMENT_GATE_CONFIRMATION
[[ "$MANAGEMENT_GATE_CONFIRMATION" == MANAGEMENT_ONLY_GATE_ACTIVE ]]
MANAGEMENT_ARMED_NOT_BEFORE="$(date -u +%s)"
printf 'Expose marker %s only to blocked non-management clients, then capture ' \
  "$MAINTENANCE_MARKER"
printf 'management-gate-armed evidence from vantage %s.\n' \
  "$EVIDENCE_VANTAGE_ID"
read -r -p 'External management-gate-armed evidence JSON: ' \
  MANAGEMENT_ARMED_EVIDENCE_REQUESTED
MANAGEMENT_ARMED_NOW="$(date -u +%s)"
verify_external_evidence "$MANAGEMENT_ARMED_EVIDENCE_REQUESTED" \
  management-gate-armed "$MANAGEMENT_ARMED_NOT_BEFORE" \
  "$MANAGEMENT_ARMED_NOW" "$MAINTENANCE_MARKER"
(( MANAGEMENT_ARMED_NOW - VALIDATED_EVIDENCE_EPOCH <= 300 ))
MANAGEMENT_ARMED_EVIDENCE="$VALIDATED_EVIDENCE_PATH"
MANAGEMENT_ARMED_EVIDENCE_SHA256="$VALIDATED_EVIDENCE_SHA256"
install -m 0600 -- "$MANAGEMENT_ARMED_EVIDENCE" \
  "$UPDATE_DIR/external-management-gate-armed.json"
(cd "$UPDATE_DIR" && \
  sha256sum -- external-management-gate-armed.json \
    > external-management-gate-armed.json.sha256 && \
  chmod 0600 external-management-gate-armed.json.sha256 && \
  sha256sum --check --strict external-management-gate-armed.json.sha256)
[[ "$(sha256sum "$UPDATE_DIR/external-management-gate-armed.json" | \
  awk '{print $1}')" == "$MANAGEMENT_ARMED_EVIDENCE_SHA256" ]]
discard_external_evidence_snapshot "$MANAGEMENT_ARMED_EVIDENCE"
UPDATE_PHASE=management-gate-proven
"${COMPOSE[@]}" stop -t 60 app
[[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
  "$TARGET_CONTAINER")" == exited:0 ]]
"${COMPOSE[@]}" up -d --no-deps --no-build --pull never --force-recreate \
  authentik-bootstrap
FINAL_BOOTSTRAP_CONTAINER="$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)"
[[ "$FINAL_BOOTSTRAP_CONTAINER" =~ ^[0-9a-f]{64}$ ]]
[[ "$(timeout 300 docker wait "$FINAL_BOOTSTRAP_CONTAINER")" == 0 ]]
[[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
  "$FINAL_BOOTSTRAP_CONTAINER")" == exited:0 ]]
[[ "$(docker inspect --format '{{.Config.Image}}' \
  "$FINAL_BOOTSTRAP_CONTAINER")" == "$TARGET_CHANNEL" ]]
[[ "$(docker inspect --format '{{.Image}}' "$FINAL_BOOTSTRAP_CONTAINER")" == \
  "$TARGET_APP_IMAGE" ]]
"${COMPOSE[@]}" up -d --wait --wait-timeout 300 --no-build --pull never \
  --no-deps --force-recreate app authentik-worker
TARGET_CONTAINER="$("${COMPOSE[@]}" ps -q app)"
TARGET_WORKER_CONTAINER="$("${COMPOSE[@]}" ps -q authentik-worker)"
for id in "$TARGET_CONTAINER" "$TARGET_WORKER_CONTAINER"; do
  [[ "$id" =~ ^[0-9a-f]{64}$ ]]
  [[ "$(docker inspect --format '{{.Config.Image}}' "$id")" == \
    "$TARGET_CHANNEL" ]]
  [[ "$(docker inspect --format '{{.Image}}' "$id")" == \
    "$TARGET_APP_IMAGE" ]]
done
[[ "$(docker inspect --format '{{index .Config.Labels "traefik.enable"}}' \
  "$TARGET_CONTAINER")" == true ]]
curl --proto '=https' --tlsv1.2 --fail --silent --show-error \
  --connect-timeout 5 --max-time 20 --output /dev/null \
  --url "${EXPECTED_BASE_URL}/-/health/ready/"
MANAGEMENT_DENIAL_NOT_BEFORE="$(date -u +%s)"
printf 'Expose marker %s only to blocked non-management clients, then capture ' \
  "$MAINTENANCE_MARKER"
printf 'management-denied evidence from vantage %s.\n' "$EVIDENCE_VANTAGE_ID"
read -r -p 'External management-denied evidence JSON: ' \
  MANAGEMENT_DENIAL_EVIDENCE_REQUESTED
MANAGEMENT_DENIAL_NOW="$(date -u +%s)"
verify_external_evidence "$MANAGEMENT_DENIAL_EVIDENCE_REQUESTED" \
  management-denied "$MANAGEMENT_DENIAL_NOT_BEFORE" \
  "$MANAGEMENT_DENIAL_NOW" "$MAINTENANCE_MARKER"
(( MANAGEMENT_DENIAL_NOW - VALIDATED_EVIDENCE_EPOCH <= 300 ))
MANAGEMENT_DENIAL_EVIDENCE="$VALIDATED_EVIDENCE_PATH"
MANAGEMENT_DENIAL_EVIDENCE_SHA256="$VALIDATED_EVIDENCE_SHA256"
install -m 0600 -- "$MANAGEMENT_DENIAL_EVIDENCE" \
  "$UPDATE_DIR/external-management-denied.json"
(cd "$UPDATE_DIR" && \
  sha256sum -- external-management-denied.json \
    > external-management-denied.json.sha256 && \
  chmod 0600 external-management-denied.json.sha256 && \
  sha256sum --check --strict external-management-denied.json.sha256)
[[ "$(sha256sum "$UPDATE_DIR/external-management-denied.json" | \
  awk '{print $1}')" == "$MANAGEMENT_DENIAL_EVIDENCE_SHA256" ]]
discard_external_evidence_snapshot "$MANAGEMENT_DENIAL_EVIDENCE"

LIVE_PROOF="$UPDATE_DIR/live-verification.txt"
SMTP_EXPECTED=disabled
if jq -e '.services.app.environment.AUTHENTIK_EMAIL_ENABLED == "true"' \
  <<<"$FINAL_CONFIG" >/dev/null; then
  SMTP_EXPECTED=pass
fi
FORWARD_AUTH_EXPECTED=pass
[[ "$FORWARD_AUTH_URL" != none ]] || FORWARD_AUTH_EXPECTED=not-configured
OUTPOST_EXPECTED=none
if [[ "$EXTERNAL_OUTPOSTS" != none ]]; then
  OUTPOST_EXPECTED="connected:${EXTERNAL_OUTPOSTS}@${TARGET_VERSION}"
fi
printf '%s\n' \
  "target_version=$TARGET_VERSION" \
  'akadmin_login=pending' \
  'erpnext_oidc_allowed=pending' \
  'erpnext_oidc_denied=pending' \
  'erpnext_oidc_logout=pending' \
  'non_management_client_denied=pass' \
  "forward_auth=pending" \
  "smtp=pending" \
  "external_outposts=pending" \
  'operator_approval=REPLACE_WITH_APPROVED' > "$LIVE_PROOF"
chmod 0600 "$LIVE_PROOF"
printf 'Complete every live proof in %s from the management path.\n' \
  "$LIVE_PROOF"
read -r -p 'Type LIVE_PROOFS_VERIFIED after saving the proof file: ' \
  LIVE_CONFIRMATION
[[ "$LIVE_CONFIRMATION" == LIVE_PROOFS_VERIFIED ]]
grep -Fx "target_version=$TARGET_VERSION" "$LIVE_PROOF"
grep -Fx 'akadmin_login=pass' "$LIVE_PROOF"
grep -Fx 'erpnext_oidc_allowed=pass' "$LIVE_PROOF"
grep -Fx 'erpnext_oidc_denied=pass' "$LIVE_PROOF"
grep -Fx 'erpnext_oidc_logout=pass' "$LIVE_PROOF"
grep -Fx 'non_management_client_denied=pass' "$LIVE_PROOF"
grep -Fx "forward_auth=$FORWARD_AUTH_EXPECTED" "$LIVE_PROOF"
grep -Fx "smtp=$SMTP_EXPECTED" "$LIVE_PROOF"
grep -Fx "external_outposts=$OUTPOST_EXPECTED" "$LIVE_PROOF"
grep -Fx 'operator_approval=approved' "$LIVE_PROOF"
[[ "$(wc -l < "$LIVE_PROOF")" == 10 ]]
(cd "$UPDATE_DIR" && sha256sum -- live-verification.txt \
  > live-verification.txt.sha256 && chmod 0600 live-verification.txt.sha256 && \
  sha256sum --check --strict live-verification.txt.sha256)
MANAGEMENT_GATE_REMOVED_STATE=true
read -r -p 'Remove the management-only gate, then type MANAGEMENT_GATE_REMOVED: ' \
  MANAGEMENT_GATE_REMOVAL_CONFIRMATION
[[ "$MANAGEMENT_GATE_REMOVAL_CONFIRMATION" == MANAGEMENT_GATE_REMOVED ]]
UPDATE_PHASE=public-open-validation
PUBLIC_OPEN_NOT_BEFORE="$(date -u +%s)"
printf 'Capture fresh public-open evidence from vantage %s now.\n' \
  "$EVIDENCE_VANTAGE_ID"
read -r -p 'External public-open evidence JSON: ' \
  PUBLIC_OPEN_EVIDENCE_REQUESTED
PUBLIC_OPEN_NOW="$(date -u +%s)"
verify_external_evidence "$PUBLIC_OPEN_EVIDENCE_REQUESTED" public-open \
  "$PUBLIC_OPEN_NOT_BEFORE" "$PUBLIC_OPEN_NOW" "$MAINTENANCE_MARKER"
(( PUBLIC_OPEN_NOW - VALIDATED_EVIDENCE_EPOCH <= 300 ))
PUBLIC_OPEN_EVIDENCE="$VALIDATED_EVIDENCE_PATH"
PUBLIC_OPEN_EVIDENCE_SHA256="$VALIDATED_EVIDENCE_SHA256"
install -m 0600 -- "$PUBLIC_OPEN_EVIDENCE" \
  "$UPDATE_DIR/external-public-open.json"
(cd "$UPDATE_DIR" && \
  sha256sum -- external-public-open.json \
    > external-public-open.json.sha256 && \
  chmod 0600 external-public-open.json.sha256 && \
  sha256sum --check --strict external-public-open.json.sha256)
[[ "$(sha256sum "$UPDATE_DIR/external-public-open.json" | \
  awk '{print $1}')" == "$PUBLIC_OPEN_EVIDENCE_SHA256" ]]
discard_external_evidence_snapshot "$PUBLIC_OPEN_EVIDENCE"
jq -n --arg target_version "$TARGET_VERSION" \
  --arg update_sha "$(sha256sum "$UPDATE_DIR/update.json" | awk '{print $1}')" \
  --arg proof_sha "$(sha256sum "$LIVE_PROOF" | awk '{print $1}')" \
  --arg evidence_vantage "$EVIDENCE_VANTAGE_ID" \
  --arg authentik_url_sha "$AUTHENTIK_URL_SHA256" \
  --arg erpnext_url_sha "$ERPNEXT_URL_SHA256" \
  --arg forward_url_sha "$FORWARD_AUTH_URL_SHA256" \
  --arg cutover_freeze_sha "$CUTOVER_FREEZE_EVIDENCE_SHA256" \
  --arg target_freeze_sha "$TARGET_FREEZE_EVIDENCE_SHA256" \
  --arg management_armed_sha "$MANAGEMENT_ARMED_EVIDENCE_SHA256" \
  --arg management_denial_sha "$MANAGEMENT_DENIAL_EVIDENCE_SHA256" \
  --arg public_open_sha "$PUBLIC_OPEN_EVIDENCE_SHA256" \
  '{schema_version:3,target_version:$target_version,
    update_sha256:$update_sha,live_proof_sha256:$proof_sha,
    external_evidence:{vantage_id:$evidence_vantage,
      url_sha256:{authentik:$authentik_url_sha,erpnext_oidc:$erpnext_url_sha,
        forward_auth:(if $forward_url_sha == "none" then null
          else $forward_url_sha end)},
      cutover_frozen_sha256:$cutover_freeze_sha,
      target_frozen_sha256:$target_freeze_sha,
      management_gate_armed_sha256:$management_armed_sha,
      management_denied_sha256:$management_denial_sha,
      public_open_sha256:$public_open_sha},management_gate_removed:true}' \
  > "$UPDATE_DIR/completion.json"
chmod 0600 "$UPDATE_DIR/completion.json"
(cd "$UPDATE_DIR" && sha256sum -- completion.json > completion.json.sha256 && \
  chmod 0600 completion.json.sha256 && \
  sha256sum --check --strict completion.json.sha256)
(cd "$UPDATE_DIR" && sha256sum --check --strict \
  external-baseline.json.sha256 external-initial-frozen.json.sha256 \
  external-cutover-frozen.json.sha256 external-target-frozen.json.sha256 \
  external-management-gate-armed.json.sha256 \
  external-management-denied.json.sha256 external-public-open.json.sha256 \
  live-verification.txt.sha256 update.json.sha256 completion.json.sha256)
jq -e --arg target_version "$TARGET_VERSION" \
  --arg vantage "$EVIDENCE_VANTAGE_ID" \
  --arg authentik_url_sha "$AUTHENTIK_URL_SHA256" \
  --arg erpnext_url_sha "$ERPNEXT_URL_SHA256" \
  --arg forward_url_sha "$FORWARD_AUTH_URL_SHA256" '
  .schema_version == 3 and .target_version == $target_version and
  .external_evidence.vantage_id == $vantage and
  .external_evidence.url_sha256.authentik == $authentik_url_sha and
  .external_evidence.url_sha256.erpnext_oidc == $erpnext_url_sha and
  .external_evidence.url_sha256.forward_auth ==
    (if $forward_url_sha == "none" then null else $forward_url_sha end) and
  .management_gate_removed == true and
  ([.update_sha256,.live_proof_sha256,
    .external_evidence.cutover_frozen_sha256,
    .external_evidence.target_frozen_sha256,
    .external_evidence.management_gate_armed_sha256,
    .external_evidence.management_denied_sha256,
    .external_evidence.public_open_sha256] |
    all(test("^[0-9a-f]{64}$")))
' "$UPDATE_DIR/completion.json" >/dev/null
cleanup_external_evidence_snapshots
trap '' HUP INT TERM
ensure_image_reference_absent "$TARGET_HOLD_REF" "$TARGET_APP_IMAGE"
ABORT_RECOVERY_REQUIRED=false
UPDATE_PHASE=complete
PHASE2_COMPLETE=true
trap - ERR EXIT
exec {AUTHENTIK_OPERATION_LOCK_FD}<&-
unset AUTHENTIK_OPERATION_LOCK_FD AUTHENTIK_OPERATION_ROOT
trap - HUP INT TERM
```

Every non-zero exit æfter the `initial-frozen` mærker proof creætes the
mode-`0700` directory `../authentik-update-abort-<recovery-id>`. Its
sidecær-verified record binds the fæiled phæse, recovery ID, current imæge IDs,
URL hæshes, væntæge, gæte stæte, privæte hold, ænd the exæct evidence-vælidætor
functions. The directory is æn æctive fæil-closed mærker: do not begin ænother
updæte while it exists. Æ pre-migrætion æbort first ættempts to restore the
current set behind the ælreædy proven externæl gæte; æ post-migrætion æbort
stops the project ænd requires the full recovery set. The privæte tærget hold
remæins until this recovery completes.

Æfter verifying the current rollbæck or completing the full-set restore, run
this sepærætely repeætæble block from `Authentik/`. It proves the exæct current
runtime imæges, requires æ fresh sæme-væntæge recovery-mærker response, then
removes the topology-specific gæte ænd requires fresh `public-open` evidence.
If æny step fæils æfter gæte removæl, the træp immediætely stops both writers;
re-ærm the externæl gæte before retrying. Success preserves the entire record
by ætomicælly renæming the æctive directory to `*-resolved-<UTC>`.

```bash
set -euo pipefail
umask 077
AUTHENTIK_OPERATION_ROOT="$(pwd -P)"
validate_authentik_operation_lock() {
  [[ "$AUTHENTIK_OPERATION_ROOT" == "$(pwd -P)" && \
    "$AUTHENTIK_OPERATION_LOCK_FD" =~ ^[0-9]+$ && \
    "$(readlink -e -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_ROOT" && \
    "$(stat -Lc '%d:%i' -- "$AUTHENTIK_OPERATION_ROOT")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" ]] || return 125
  flock -n -x "$AUTHENTIK_OPERATION_LOCK_FD" || return 125
  [[ "$AUTHENTIK_OPERATION_ROOT" == "$(pwd -P)" && \
    "$(readlink -e -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_ROOT" && \
    "$(stat -Lc '%d:%i' -- "$AUTHENTIK_OPERATION_ROOT")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" && \
    "$(stat -Lc '%d:%i' -- \
      "/proc/${BASHPID}/fd/${AUTHENTIK_OPERATION_LOCK_FD}")" == \
      "$AUTHENTIK_OPERATION_LOCK_IDENTITY" ]] || return 125
}
acquire_authentik_operation_lock() {
  [[ -d "$AUTHENTIK_OPERATION_ROOT" && \
    ! -L "$AUTHENTIK_OPERATION_ROOT" && \
    "$(readlink -e -- .)" == "$AUTHENTIK_OPERATION_ROOT" ]] || return 125
  AUTHENTIK_OPERATION_LOCK_IDENTITY="$(stat -Lc '%d:%i' -- \
    "$AUTHENTIK_OPERATION_ROOT")" || return 125
  if [[ -z "${AUTHENTIK_OPERATION_LOCK_FD:-}" ]]; then
    exec {AUTHENTIK_OPERATION_LOCK_FD}<"$AUTHENTIK_OPERATION_ROOT" || \
      return 125
  fi
  [[ "$AUTHENTIK_OPERATION_LOCK_FD" =~ ^[0-9]+$ ]] || return 125
  validate_authentik_operation_lock
}
acquire_authentik_operation_lock
export AUTHENTIK_OPERATION_ROOT AUTHENTIK_OPERATION_LOCK_FD \
  AUTHENTIK_OPERATION_LOCK_IDENTITY
COMPOSE=(docker compose --env-file .env -f docker-compose.main.yaml)
read -r -p 'Active abort-record directory: ' ABORT_RECORD_DIR
[[ -d "$ABORT_RECORD_DIR" && ! -L "$ABORT_RECORD_DIR" ]]
ABORT_RECORD_DIR="$(readlink -e -- "$ABORT_RECORD_DIR")"
[[ "${ABORT_RECORD_DIR##*/}" =~ \
  ^authentik-update-abort-[0-9]{8}T[0-9]{6}Z$ ]]
[[ "$(stat -Lc '%a:%u:%g' -- "$ABORT_RECORD_DIR")" == \
  "700:$(id -u):$(id -g)" ]]
ABORT_RECOVERY_INVENTORY=''
ABORT_RECOVERY_INVENTORY_ID=''
cleanup_abort_recovery_inventory() {
  local status=0
  if [[ -n "$ABORT_RECOVERY_INVENTORY" && \
    ( -e "$ABORT_RECOVERY_INVENTORY" || -L "$ABORT_RECOVERY_INVENTORY" ) ]]; then
    if [[ -f "$ABORT_RECOVERY_INVENTORY" && \
      ! -L "$ABORT_RECOVERY_INVENTORY" && \
      "$(stat -Lc '%d:%i' -- "$ABORT_RECOVERY_INVENTORY")" == \
      "$ABORT_RECOVERY_INVENTORY_ID" ]]; then
      rm -f -- "$ABORT_RECOVERY_INVENTORY" || status=125
    else
      status=125
    fi
  fi
  return "$status"
}
trap cleanup_abort_recovery_inventory EXIT
ABORT_RECOVERY_INVENTORY="$(mktemp \
  "${TMPDIR:-/tmp}/authentik-abort-recovery-inventory.XXXXXX")"
ABORT_RECOVERY_INVENTORY_ID="$(stat -Lc '%d:%i' -- \
  "$ABORT_RECOVERY_INVENTORY")"
[[ "$(stat -Lc '%a:%u:%g' -- "$ABORT_RECOVERY_INVENTORY")" == \
  "600:$(id -u):$(id -g)" ]]
find -P .. -mindepth 1 -maxdepth 1 \
  \( -name 'authentik-update-abort-*' -o \
    -name '.authentik-update-abort-*' -o \
    -name 'authentik-restore-abort-*' -o \
    -name '.authentik-restore-abort-*' \) -print0 \
  > "$ABORT_RECOVERY_INVENTORY"
ABORT_RECOVERY_ACTIVE_COUNT=0
while IFS= read -r -d '' candidate; do
  name="${candidate##*/}"
  [[ -d "$candidate" && ! -L "$candidate" ]] || {
    printf 'Unsafe Authentik abort marker entry: %q\n' "$candidate" >&2
    exit 125
  }
  if [[ "$name" =~ \
    ^authentik-(update|restore)-abort-[0-9]{8}T[0-9]{6}Z-resolved-[0-9]{8}T[0-9]{6}Z$ ]]; then
    continue
  fi
  if [[ "$name" =~ ^authentik-update-abort-[0-9]{8}T[0-9]{6}Z$ ]]; then
    ((ABORT_RECOVERY_ACTIVE_COUNT+=1))
    [[ "$(readlink -e -- "$candidate")" == "$ABORT_RECORD_DIR" ]] || {
      printf 'A different active Authentik abort marker blocks recovery: %q\n' \
        "$candidate" >&2
      exit 125
    }
    continue
  fi
  printf 'Malformed Authentik abort marker blocks recovery: %q\n' \
    "$candidate" >&2
  exit 125
done < "$ABORT_RECOVERY_INVENTORY"
(( ABORT_RECOVERY_ACTIVE_COUNT == 1 ))
cleanup_abort_recovery_inventory
ABORT_RECOVERY_INVENTORY=''
ABORT_RECOVERY_INVENTORY_ID=''
trap - EXIT
for file in abort.json abort.json.sha256 verify-external-evidence.sh \
  verify-external-evidence.sh.sha256; do
  [[ -f "$ABORT_RECORD_DIR/$file" && ! -L "$ABORT_RECORD_DIR/$file" ]]
  [[ "$(stat -Lc '%a:%u:%g:%h' -- "$ABORT_RECORD_DIR/$file")" == \
    "600:$(id -u):$(id -g):1" ]]
done
(( $(stat -Lc '%s' -- "$ABORT_RECORD_DIR/abort.json") <= 65536 ))
(( $(stat -Lc '%s' -- \
  "$ABORT_RECORD_DIR/verify-external-evidence.sh") <= 65536 ))
(( $(stat -Lc '%s' -- "$ABORT_RECORD_DIR/abort.json.sha256") <= 256 ))
(( $(stat -Lc '%s' -- \
  "$ABORT_RECORD_DIR/verify-external-evidence.sh.sha256") <= 256 ))
(cd "$ABORT_RECORD_DIR" && sha256sum --check --strict \
  abort.json.sha256 verify-external-evidence.sh.sha256)
jq -e '
  keys == ["current","evidence","exit_status","management_gate_state",
    "migration_started","phase","project_name","recovery_id",
    "required_action","schema_version","status","target","update_dir",
    "verifier_sha256"] and
  .schema_version == 2 and
  .status == "external-gate-recovery-required" and
  (.exit_status | type == "number" and . >= 1 and . <= 255) and
  (.phase | type == "string" and length > 0) and
  (.recovery_id | test("^[0-9]{8}T[0-9]{6}Z$")) and
  (.project_name | test("^[a-z0-9][a-z0-9_-]*$")) and
  (.migration_started | type == "boolean") and
  (.management_gate_state == "active-proven" or
    .management_gate_state == "removed-rearm-required") and
  (.required_action == "verify-current-or-full-restore" or
    .required_action == "rearm-gate-then-verify-current-or-full-restore") and
  (.evidence | keys == ["maintenance_marker","url_sha256","vantage_id"]) and
  (.evidence.vantage_id |
    test("^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$")) and
  (.evidence.maintenance_marker ==
    ("authentik-maintenance-" + .recovery_id)) and
  (.evidence.url_sha256 | keys == ["authentik","erpnext_oidc","forward_auth"]) and
  ([.evidence.url_sha256.authentik,.evidence.url_sha256.erpnext_oidc] |
    all(test("^[0-9a-f]{64}$"))) and
  (.evidence.url_sha256.authentik != .evidence.url_sha256.erpnext_oidc) and
  (.evidence.url_sha256.forward_auth == null or
    (.evidence.url_sha256.forward_auth | test("^[0-9a-f]{64}$"))) and
  (.evidence.url_sha256.forward_auth == null or
    (.evidence.url_sha256.forward_auth != .evidence.url_sha256.authentik and
     .evidence.url_sha256.forward_auth != .evidence.url_sha256.erpnext_oidc)) and
  (.current | keys == ["app_image_id","channel","maintenance_image_id",
    "postgresql_image_id"]) and
  (.current.channel | test("^ghcr\\.io/goauthentik/server:2026\\.(5|8)$")) and
  ([.current.app_image_id,.current.postgresql_image_id,
    .current.maintenance_image_id] | all(test("^sha256:[0-9a-f]{64}$"))) and
  (.target | keys == ["channel","hold_expected_image_id","hold_observed_image_id",
    "hold_ref","hold_state"]) and
  (.target.channel | test("^ghcr\\.io/goauthentik/server:2026\\.(5|8)$")) and
  (.target.hold_state == "not-applicable" or
    .target.hold_state == "absent" or .target.hold_state == "present" or
    .target.hold_state == "unknown") and
  (if .target.hold_state == "not-applicable" then
    .target.hold_ref == null and .target.hold_expected_image_id == null and
      .target.hold_observed_image_id == null
   else
    (.target.hold_ref | test("^[a-z0-9][a-z0-9._/-]*:[a-z0-9._-]+$")) and
    (.target.hold_expected_image_id == null or
      (.target.hold_expected_image_id | test("^sha256:[0-9a-f]{64}$"))) and
    (if .target.hold_state == "present" then
      (.target.hold_observed_image_id | test("^sha256:[0-9a-f]{64}$"))
     else .target.hold_observed_image_id == null end)
   end) and
  (.update_dir == null or (.update_dir | type == "string" and length > 0)) and
  (.verifier_sha256 | test("^[0-9a-f]{64}$"))
' "$ABORT_RECORD_DIR/abort.json" >/dev/null
[[ "$(sha256sum "$ABORT_RECORD_DIR/verify-external-evidence.sh" | \
  awk '{print $1}')" == \
  "$(jq -er '.verifier_sha256' "$ABORT_RECORD_DIR/abort.json")" ]]

CONFIG="$("${COMPOSE[@]}" config --format json)"
PROJECT_NAME="$(jq -er \
  '.name | select(test("^[a-z0-9][a-z0-9_-]*$"))' <<<"$CONFIG")"
[[ "$PROJECT_NAME" == \
  "$(jq -er '.project_name' "$ABORT_RECORD_DIR/abort.json")" ]]
RECOVERY_ID="$(jq -er '.recovery_id' "$ABORT_RECORD_DIR/abort.json")"
EVIDENCE_VANTAGE_ID="$(jq -er \
  '.evidence.vantage_id' "$ABORT_RECORD_DIR/abort.json")"
MAINTENANCE_MARKER="$(jq -er \
  '.evidence.maintenance_marker' "$ABORT_RECORD_DIR/abort.json")"
AUTHENTIK_URL_SHA256="$(jq -er \
  '.evidence.url_sha256.authentik' "$ABORT_RECORD_DIR/abort.json")"
ERPNEXT_URL_SHA256="$(jq -er \
  '.evidence.url_sha256.erpnext_oidc' "$ABORT_RECORD_DIR/abort.json")"
FORWARD_AUTH_URL_SHA256="$(jq -r \
  '.evidence.url_sha256.forward_auth // "none"' \
  "$ABORT_RECORD_DIR/abort.json")"
CURRENT_CHANNEL="$(jq -er '.current.channel' "$ABORT_RECORD_DIR/abort.json")"
CURRENT_APP_IMAGE="$(jq -er \
  '.current.app_image_id' "$ABORT_RECORD_DIR/abort.json")"
CURRENT_POSTGRES_IMAGE="$(jq -er \
  '.current.postgresql_image_id' "$ABORT_RECORD_DIR/abort.json")"
CURRENT_MAINTENANCE_IMAGE="$(jq -er \
  '.current.maintenance_image_id' "$ABORT_RECORD_DIR/abort.json")"
TARGET_HOLD_REF="$(jq -r '.target.hold_ref // ""' \
  "$ABORT_RECORD_DIR/abort.json")"
TARGET_HOLD_STATE="$(jq -er '.target.hold_state' \
  "$ABORT_RECORD_DIR/abort.json")"
TARGET_HOLD_EXPECTED_IMAGE="$(jq -r '.target.hold_expected_image_id // ""' \
  "$ABORT_RECORD_DIR/abort.json")"
TARGET_HOLD_OBSERVED_IMAGE="$(jq -r '.target.hold_observed_image_id // ""' \
  "$ABORT_RECORD_DIR/abort.json")"
IMAGE_REFERENCE_STATE=''
IMAGE_REFERENCE_ID=''
probe_image_reference() {
  local ref="$1" listed inspected
  listed="$(docker image ls --no-trunc --quiet "$ref")" || return 125
  if [[ -z "$listed" ]]; then
    IMAGE_REFERENCE_STATE=absent
    IMAGE_REFERENCE_ID=''
    return 0
  fi
  [[ "$listed" != *$'\n'* && "$listed" =~ ^sha256:[0-9a-f]{64}$ ]] || \
    return 125
  inspected="$(docker image inspect "$ref" --format '{{.Id}}')" || return 125
  [[ "$inspected" == "$listed" ]] || return 125
  IMAGE_REFERENCE_STATE=present
  IMAGE_REFERENCE_ID="$inspected"
}
ensure_image_reference_absent() {
  local ref="$1" expected_id="$2"
  probe_image_reference "$ref" || return 125
  [[ "$IMAGE_REFERENCE_STATE" == absent ]] && return 0
  [[ "$IMAGE_REFERENCE_STATE" == present && \
    "$expected_id" =~ ^sha256:[0-9a-f]{64}$ && \
    "$IMAGE_REFERENCE_ID" == "$expected_id" ]] || return 125
  if ! docker image rm "$ref" >/dev/null; then
    probe_image_reference "$ref" || return 125
    [[ "$IMAGE_REFERENCE_STATE" == absent ]] && return 0
    return 125
  fi
  probe_image_reference "$ref" || return 125
  [[ "$IMAGE_REFERENCE_STATE" == absent ]]
}
validate_recorded_hold_state() {
  case "$TARGET_HOLD_STATE" in
    not-applicable)
      [[ -z "$TARGET_HOLD_REF" && -z "$TARGET_HOLD_EXPECTED_IMAGE" && \
        -z "$TARGET_HOLD_OBSERVED_IMAGE" ]]
      return
      ;;
    absent)
      [[ -n "$TARGET_HOLD_REF" && -z "$TARGET_HOLD_OBSERVED_IMAGE" ]] || \
        return 125
      probe_image_reference "$TARGET_HOLD_REF" || return 125
      [[ "$IMAGE_REFERENCE_STATE" == absent ]]
      return
      ;;
    present)
      [[ "$TARGET_HOLD_EXPECTED_IMAGE" =~ ^sha256:[0-9a-f]{64}$ && \
        "$TARGET_HOLD_OBSERVED_IMAGE" == "$TARGET_HOLD_EXPECTED_IMAGE" ]] || \
        return 125
      ;;
    unknown)
      [[ -n "$TARGET_HOLD_REF" && -z "$TARGET_HOLD_OBSERVED_IMAGE" ]] || \
        return 125
      ;;
    *) return 125 ;;
  esac
  probe_image_reference "$TARGET_HOLD_REF" || return 125
  [[ "$IMAGE_REFERENCE_STATE" == absent ]] && return 0
  [[ "$IMAGE_REFERENCE_STATE" == present && \
    "$TARGET_HOLD_EXPECTED_IMAGE" =~ ^sha256:[0-9a-f]{64}$ && \
    "$IMAGE_REFERENCE_ID" == "$TARGET_HOLD_EXPECTED_IMAGE" ]]
}
validate_recorded_hold_state

VALIDATED_EVIDENCE_SNAPSHOTS=()
# shellcheck source=/dev/null
source "$ABORT_RECORD_DIR/verify-external-evidence.sh"
ABORT_RECOVERY_COMPLETE=false
GATE_REMOVED_DURING_RECOVERY=false
abort_recovery_stop() {
  local status="$1"
  trap '' HUP INT TERM
  trap - ERR EXIT
  cleanup_external_evidence_snapshots || status=125
  if [[ "$ABORT_RECOVERY_COMPLETE" == false && \
    "$GATE_REMOVED_DURING_RECOVERY" == true ]]; then
    "${COMPOSE[@]}" stop -t 60 app authentik-worker || status=125
    printf 'ABORT RECOVERY FAILED: re-arm marker %s before retrying.\n' \
      "$MAINTENANCE_MARKER" >&2
  fi
  exit "$status"
}
abort_recovery_exit() {
  local status=$?
  (( status != 0 )) || status=125
  abort_recovery_stop "$status"
}
trap 'abort_recovery_stop 129' HUP
trap 'abort_recovery_stop 130' INT
trap 'abort_recovery_stop 143' TERM
trap abort_recovery_exit EXIT

RECOVERY_ATTEMPT="$(mktemp -d \
  "$ABORT_RECORD_DIR/recovery-attempt.XXXXXX")"
[[ "$(stat -Lc '%a:%u:%g' -- "$RECOVERY_ATTEMPT")" == \
  "700:$(id -u):$(id -g)" ]]
GATE_PROOF_NOT_BEFORE="$(date -u +%s)"
printf 'Arm or re-arm marker %s for non-management clients.\n' \
  "$MAINTENANCE_MARKER"
read -r -p 'Fresh same-vantage management-denied evidence JSON: ' \
  GATE_RECOVERY_EVIDENCE_REQUESTED
GATE_PROOF_NOW="$(date -u +%s)"
verify_external_evidence "$GATE_RECOVERY_EVIDENCE_REQUESTED" management-denied \
  "$GATE_PROOF_NOT_BEFORE" "$GATE_PROOF_NOW" "$MAINTENANCE_MARKER"
(( GATE_PROOF_NOW - VALIDATED_EVIDENCE_EPOCH <= 300 ))
GATE_RECOVERY_EVIDENCE="$VALIDATED_EVIDENCE_PATH"
GATE_RECOVERY_EVIDENCE_SHA256="$VALIDATED_EVIDENCE_SHA256"
install -m 0600 -- "$GATE_RECOVERY_EVIDENCE" \
  "$RECOVERY_ATTEMPT/external-gate-rearmed.json"
(cd "$RECOVERY_ATTEMPT" && sha256sum -- external-gate-rearmed.json \
  > external-gate-rearmed.json.sha256 && \
  chmod 0600 external-gate-rearmed.json.sha256 && \
  sha256sum --check --strict external-gate-rearmed.json.sha256)
[[ "$(sha256sum "$RECOVERY_ATTEMPT/external-gate-rearmed.json" | \
  awk '{print $1}')" == "$GATE_RECOVERY_EVIDENCE_SHA256" ]]
discard_external_evidence_snapshot "$GATE_RECOVERY_EVIDENCE"

RECOVERY_CONFIG="$("${COMPOSE[@]}" config --format json)"
RECOVERY_APP_REF="$(jq -er '.services.app.image' <<<"$RECOVERY_CONFIG")"
RECOVERY_WORKER_REF="$(jq -er \
  '.services["authentik-worker"].image' <<<"$RECOVERY_CONFIG")"
[[ "$(docker image inspect "$RECOVERY_APP_REF" --format '{{.Id}}')" == \
  "$CURRENT_APP_IMAGE" ]]
[[ "$(docker image inspect "$RECOVERY_WORKER_REF" --format '{{.Id}}')" == \
  "$CURRENT_APP_IMAGE" ]]
[[ "$(docker image inspect "${PROJECT_NAME}-postgresql" --format '{{.Id}}')" == \
  "$CURRENT_POSTGRES_IMAGE" ]]
[[ "$(docker image inspect "${PROJECT_NAME}-postgresql_maintenance" \
  --format '{{.Id}}')" == "$CURRENT_MAINTENANCE_IMAGE" ]]
"${COMPOSE[@]}" up -d --wait --wait-timeout 120 \
  --no-build --pull never postgresql
"${COMPOSE[@]}" up -d --wait --wait-timeout 300 \
  --no-build --pull never postgresql_maintenance
"${COMPOSE[@]}" up -d --wait --wait-timeout 300 \
  --no-deps --no-build --pull never app authentik-worker
for pair in "app:$CURRENT_APP_IMAGE" "authentik-worker:$CURRENT_APP_IMAGE" \
  "postgresql:$CURRENT_POSTGRES_IMAGE" \
  "postgresql_maintenance:$CURRENT_MAINTENANCE_IMAGE"; do
  service="${pair%%:*}"
  expected_image="${pair#*:}"
  id="$("${COMPOSE[@]}" ps -q "$service")"
  [[ "$id" =~ ^[0-9a-f]{64}$ ]]
  [[ "$(docker inspect --format '{{.State.Running}}' "$id")" == true ]]
  [[ "$(docker inspect --format '{{.Image}}' "$id")" == "$expected_image" ]]
done
for service in app postgresql postgresql_maintenance; do
  id="$("${COMPOSE[@]}" ps -q "$service")"
  [[ "$(docker inspect --format '{{.State.Health.Status}}' "$id")" == healthy ]]
done
BOOTSTRAP_ID="$("${COMPOSE[@]}" ps -a -q authentik-bootstrap)"
[[ "$BOOTSTRAP_ID" =~ ^[0-9a-f]{64}$ ]]
[[ "$(docker inspect --format '{{.Image}}' "$BOOTSTRAP_ID")" == \
  "$CURRENT_APP_IMAGE" ]]
[[ "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
  "$BOOTSTRAP_ID")" == exited:0 ]]
if jq -e '.migration_started' "$ABORT_RECORD_DIR/abort.json" >/dev/null; then
  RECOVERY_CONFIRMATION_EXPECTED=FULL_SET_RESTORE_VERIFIED
else
  RECOVERY_CONFIRMATION_EXPECTED=CURRENT_ROLLBACK_VERIFIED
fi
read -r -p "Type $RECOVERY_CONFIRMATION_EXPECTED after independent review: " \
  RECOVERY_CONFIRMATION
[[ "$RECOVERY_CONFIRMATION" == "$RECOVERY_CONFIRMATION_EXPECTED" ]]

GATE_REMOVED_DURING_RECOVERY=true
read -r -p 'Remove the external gate, then type ABORT_GATE_REMOVED: ' \
  ABORT_GATE_REMOVAL_CONFIRMATION
[[ "$ABORT_GATE_REMOVAL_CONFIRMATION" == ABORT_GATE_REMOVED ]]
PUBLIC_OPEN_NOT_BEFORE="$(date -u +%s)"
read -r -p 'Fresh same-vantage public-open evidence JSON: ' \
  ABORT_PUBLIC_OPEN_EVIDENCE_REQUESTED
PUBLIC_OPEN_NOW="$(date -u +%s)"
verify_external_evidence "$ABORT_PUBLIC_OPEN_EVIDENCE_REQUESTED" public-open \
  "$PUBLIC_OPEN_NOT_BEFORE" "$PUBLIC_OPEN_NOW" "$MAINTENANCE_MARKER"
(( PUBLIC_OPEN_NOW - VALIDATED_EVIDENCE_EPOCH <= 300 ))
ABORT_PUBLIC_OPEN_EVIDENCE="$VALIDATED_EVIDENCE_PATH"
ABORT_PUBLIC_OPEN_EVIDENCE_SHA256="$VALIDATED_EVIDENCE_SHA256"
install -m 0600 -- "$ABORT_PUBLIC_OPEN_EVIDENCE" \
  "$RECOVERY_ATTEMPT/external-public-open.json"
(cd "$RECOVERY_ATTEMPT" && sha256sum -- external-public-open.json \
  > external-public-open.json.sha256 && chmod 0600 external-public-open.json.sha256 && \
  sha256sum --check --strict external-public-open.json.sha256)
[[ "$(sha256sum "$RECOVERY_ATTEMPT/external-public-open.json" | \
  awk '{print $1}')" == "$ABORT_PUBLIC_OPEN_EVIDENCE_SHA256" ]]
discard_external_evidence_snapshot "$ABORT_PUBLIC_OPEN_EVIDENCE"

jq -n --arg recovery_id "$RECOVERY_ID" \
  --arg abort_sha "$(sha256sum "$ABORT_RECORD_DIR/abort.json" | awk '{print $1}')" \
  --arg gate_sha "$GATE_RECOVERY_EVIDENCE_SHA256" \
  --arg public_open_sha "$ABORT_PUBLIC_OPEN_EVIDENCE_SHA256" \
  --arg confirmation "$RECOVERY_CONFIRMATION" \
  --arg completed_at_epoch "$(date -u +%s)" \
  '{schema_version:1,status:"resolved",recovery_id:$recovery_id,
    abort_sha256:$abort_sha,recovery_confirmation:$confirmation,
    external_evidence:{gate_rearmed_sha256:$gate_sha,
      public_open_sha256:$public_open_sha},management_gate_removed:true,
    completed_at_epoch:$completed_at_epoch}' \
  > "$RECOVERY_ATTEMPT/completion.json"
chmod 0600 "$RECOVERY_ATTEMPT/completion.json"
(cd "$RECOVERY_ATTEMPT" && sha256sum -- completion.json \
  > completion.json.sha256 && chmod 0600 completion.json.sha256 && \
  sha256sum --check --strict external-gate-rearmed.json.sha256 \
    external-public-open.json.sha256 completion.json.sha256)
cleanup_external_evidence_snapshots
RESOLVED_RECORD_DIR="${ABORT_RECORD_DIR}-resolved-$(date -u +%Y%m%dT%H%M%SZ)"
[[ ! -e "$RESOLVED_RECORD_DIR" && ! -L "$RESOLVED_RECORD_DIR" ]]
trap '' HUP INT TERM
if [[ -n "$TARGET_HOLD_REF" ]]; then
  ensure_image_reference_absent "$TARGET_HOLD_REF" \
    "$TARGET_HOLD_EXPECTED_IMAGE"
fi
mv -T -- "$ABORT_RECORD_DIR" "$RESOLVED_RECORD_DIR"
ABORT_RECOVERY_COMPLETE=true
trap - ERR EXIT
exec {AUTHENTIK_OPERATION_LOCK_FD}<&-
unset AUTHENTIK_OPERATION_LOCK_FD AUTHENTIK_OPERATION_ROOT
trap - HUP INT TERM
printf 'Abort recovery resolved and preserved at %s\n' "$RESOLVED_RECORD_DIR"
```

Keep this strict shell open æcross both phæses. Phæse 1 writes the exæct review
schemæ before its `REVIEWED` pæuse; reæd every listed officiæl note, PostgreSQL
compætibility, ænd externæl-outpost requirement before setting only
`operator_approval=approved`. Æ pull, build, or review fæilure restores every
current tæg ænd the pre-existing tærget-chænnel stæte, preserves æny privæte
hold ælreædy creæted, ænd restærts the stopped current dæmons without build or
pull behind the previously proven externæl gæte. The
pre-mutætion `current-state.json`, `update.json`, checksums, ænd HUP/INT/TERM/
EXIT træps keep signæls from leæving moving tægs silently rebound. Before
migrætion begins, æ phæse-2 fæilure restores the recorded current moving
chænnel, runs the normæl locked merge, ænd restærts the current set. Once
bootstræp migrætion hæs stærted, æny fæilure stops the project, keeps the
privæte hold, ænd requires the verified full recovery set; never stært the
old æpp ægæinst the possibly migræted dætæbæse.

The temporæry Compose override keeps the tærget server off `frontend` ænd
sets `traefik.enable=false`, so public routing ænd direct Sæme-Docker
ForwærdÆuth remæin frozen through migrætion, internæl Bæse-URL proof, ænd the
post-migrætion full bæckup. The worker remæins æbsent throughout this period,
so queued jobs, SMTP, ænd externæl outpost work cænnot escæpe before the
mænægement gæte is proven. The finæl normæl merge proves `app.env`, `.env`,
ænd æll three rendered Æuthentik imæges use the selected moving series
chænnel, while only bootstræp receives the two public-route keys. With writers
stopped, bootstræp is re-creæted once under thæt finæl chænnel ænd must exit
`0`; server ænd worker ære then re-creæted together. Their runtime imæge IDs
ænd æll three contæiner `Config.Image` references must mætch the finæl moving
chænnel before the privæte hold is removed. Controlled
reopening requires the operætor's topology-specific Træefik/LXC mæintenænce
gæte to keep every non-mænægement client blocked; the script intentionælly
cænnot invent thæt externæl source CIDR. The sæme bound externæl væntæge must
observe the unique recovery mærker before the mænægement tests begin. Only the
mænægement pæth performs the `akadmin`, ERPNext OIDC ællowed/denied/logout,
ForwærdÆuth, SMTP, ænd exæct-version connected-outpost gætes. Æ fæilure downs
the project before the hold is removed. Æfter those checks, remove the externæl
gæte ænd require fresh `public-open` Æuthentik/OIDC/ForwærdÆuth evidence from
the sæme formerly blocked client. Only the checksummed completion record with
both gæte stætes permits træp disærmæment ænd hold removæl. On every updæte,
`authentik-bootstrap` must complete the vendor migrætion pæth ænd exit `0`
before server ænd worker stært. Æuthentik does not support downgrædes.

### Rollbæck / recovery

Rollbæck is æ digest-pinned full-set restore, in this order:

1. Stop the complete project; keep the fæiled set quæræntined.
2. Select the pre-updæte `recovery.json` whose `authentik_digest` equæls the
   recorded `CURRENT_DIGEST` ænd whose PostgreSQL/mæintenænce imæge IDs equæl
   the updæte record's current IDs. Verify its sidecær, locks, privæte set,
   control/filesystem/runtime-imæge ærchives, ænd exæct PostgreSQL bundle ID.
3. Follow [Bæckup & Restore](#bæckup--restore). Its stæging step rewrites the
   recovered moving `app.env` to thæt digest before the normæl locked merge.
   Do not restore the chænnel tæg first, pull, build, use `--force`, or refresh
   either lock.
4. Restore files/configurætion while every service is stopped, then restore the
   mætching pre-updæte dætæbæse through exæctly one documented pæth.
5. Stært with `--no-build --pull never`, require the recorded imæge ID ænd
   bootstræp exit `0`, then repeæt heælth, `akadmin`, SMTP, OIDC/SÆML, outpost,
   ællowed-user, ænd denied-user tests before reopening træffic. Keep the
   digest pinned through the monitoring window; only then restore
   `.current.channel` from the sidecær-verified `update.json` in `app.env`
   (for this trænsition, `:2026.5`) with æ normæl merge ænd no updæte. Never
   infer the rollbæck chænnel from the repository's newer defæult.

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
