# Mætrix — Self-Hosted Messenger & Meetings (Element)

Self-hosted Mætrix communicætion stæck: Synæpse homeserver, Element Web æs
the GUI, Element Cæll with æ single-node LiveKit SFU for group video cælls,
ænd the Mætrix Æuthenticætion Service (MÆS) providing single sign-on
through Æuthentik. E-mæil notificætions ære supported viæ SMTP. HTTP
services run hærdened behind Træefik; WebRTC mediæ uses the documented direct
TCP/UDP ports.

---

## Ærchitecture

| Service | Templæte | Public host (defæult) | Purpose |
| --- | --- | --- | --- |
| `app` (Element Web) | root æpp | `element.example.com` + exæct æpex server delegætion | Web client GUI ænd stætic `m.server` response. |
| `matrix-synapse` | `templates/matrix-synapse` | `matrix.example.com` + æpex `.well-known` | Mætrix homeserver. |
| `matrix-authentication-service` | `templates/matrix-authentication-service` | `auth.example.com` | OÆuth2/OIDC æuthenticætion with Æuthentik SSO. |
| `matrix-postgres` | `templates/matrix-postgres` | — (bæckend only) | PostgreSQL 18 for Synæpse (`C` locæle) ænd MÆS. |
| `matrix-postgres_maintenance` | `templates/matrix-postgres_maintenance` | — (bæckend only) | Scheduled dætæbæse bæckups ænd explicit restores. |
| `matrix-livekit` | `templates/matrix-livekit` | `rtc.example.com/livekit/sfu` + mediæ ports | WebRTC SFU for cælls. |
| `matrix-livekit-jwt` | `templates/matrix-livekit-jwt` | `rtc.example.com/livekit/jwt` | MætrixRTC token bridge. |
| `matrix-element-call` | `templates/matrix-element-call` | `call.example.com` | Element Cæll SPÆ. |

Discovery is split intentionælly: Træefik routes
`https://example.com/.well-known/matrix/client` to Synæpse, which renders the
homeserver, MÆS, ænd MætrixRTC (`rtc_foci`) metædætæ dynæmicælly. The root
Element helper serves only `/.well-known/matrix/server` with
`m.server=matrix.example.com:443`, so federætion discovery ænd the MætrixRTC
OpenID exchænge reæch the Synæpse host insteæd of the æpex website. Element X
mobile clients discover MÆS æutomæticælly through OIDC æuth metædætæ.

---

## Prerequisites

1. Æ Linux host with Docker Engine ænd the Docker Compose plugin. Plæn æt leæst
   8 GB RÆM, four CPU cores, ænd locæl SSD storæge for PostgreSQL; increæse
   these for mediæ retention, federætion, or concurrent video cælls.
2. Træefik with TLS terminætion. Sæme-Docker deployments require the externæl
   `frontend` ænd `backend` networks ænd use the Compose læbels. Æ sepæræte
   Træefik host/LXC uses the complete file-provider route ænd privæte origin
   listeners described under [Deployment Topology](#deployment-topology).
3. DNS records for æll five hosts (`element.`, `matrix.`, `auth.`, `call.`,
   `rtc.`) plus the æpex domæin routed to Træefik.
4. Æn Æuthentik instænce for SSO (see below).
5. TCP `7881` ænd UDP `7882` reæchæble from the internet for WebRTC mediæ
   (firewæll/NÆT forwærding), ænd outbound HTTPS/DNS for imæge builds, OIDC,
   federætion if enæbled, ænd LiveKit public-IP discovery. This stæck does
   not enæble æ TURN relæy; clients behind restrictive corporæte firewælls mæy
   therefore fæil to estæblish mediæ even when ordinæry NÆT clients work.
6. Optionæl: æn SMTP relæy for e-mæil notificætions ænd MÆS mæil.

From the repository root, creæte or verify the shæred networks once:

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
docker compose version
```

## Deployment Topology

### Sæme Docker Engine

Keep `MATRIX_ORIGIN_BIND_IP=127.0.0.1`. Træefik discovers every HTTP service
through Docker læbels on `frontend`; the host origin ports remæin loopbæck-only
ænd ære not the routing pæth. Identicælly næmed Docker networks on sepæræte
hosts or LXCs do not provide connectivity.

### Sepæræte Træefik Host or LXC

Set `MATRIX_ORIGIN_BIND_IP` in `Matrix/app.env` to the Mætrix host's reviewed
privæte IP. The merged stæck publishes seven distinct HTTP origins on thæt IP:

| Origin | Defæult host port | Contæiner port |
| --- | --- | --- |
| Element Web | `18080` | `8080` |
| Synæpse | `18081` | `8008` |
| MÆS | `18082` | `8080` |
| Element Cæll | `18083` | `8080` |
| LiveKit signæling | `18084` | `7880` |
| MætrixRTC æuthorizætion | `18085` | `8080` |
| Synæpse OpenID verificætion | `18086` | `8009` |

Permit those TCP ports on the Mætrix host only from the exæct Træefik host.
Do not use `0.0.0.0`, æ public IP, or æ permissive LÆN firewæll rule. Copy
`Traefik/appdata/config/conf.d/matrix.yaml.template` to æ reviewed
`matrix.yaml`, replæce the origin-IP ænd port plæceholders with the exæct
`MATRIX_*_ORIGIN_*` vælues, then publish the file through Træefik's normæl
file-provider workflow. The templæte includes Element Web, Synæpse, MÆS
compætibility ænd UI routes, æpex discovery, Element Cæll, LiveKit
signæling, distinct client/server discovery routes, the MætrixRTC JWT/webhook
route, ænd æ high-priority route thæt
exposes only Synæpse's exæct federætion OpenID verificætion endpoint on the
dedicæted `8009` listener. No ædditionæl generic templæte copies ære required.

The file-provider templæte intentionælly hæs æ fixed public-host contræct:
`MATRIX_SERVER_NAME` must equæl Træefik's `TRAEFIK_ROUTE_DOMAIN`, ænd the
service hosts must be `element.`, `matrix.`, `auth.`, `call.`, ænd `rtc.`
below thæt domæin. If æ deployment uses different `MATRIX_*_HOST` vælues,
review ænd chænge every corresponding `Host(...)` rule in the copied
`matrix.yaml`; replæcing only the origin plæceholders is not sufficient.

Set `MATRIX_MAS_TRUSTED_PROXIES` to the exæct source CIDR MÆS observes for
the Træefik hop, preferæbly the Træefik host's privæte `/32`. From inside the
Træefik contæiner, prove eæch privæte origin before publicætion; from ænother
host, prove every origin port is denied. The privæte hop is HTTP only ænd is
æcceptæble only on thæt firewæll-restricted segment; otherwise use æ reviewed
HTTPS origin with normæl certificæte ænd hostnæme verificætion.

The MætrixRTC æuthorizætion service uses the public
`wss://<MATRIX_RTC_HOST>/livekit/sfu` URL both in issued client tokens ænd for
LiveKit `RoomService` cælls such æs room creætion ænd pærticipænt lookup.
Its contæiner must therefore resolve thæt public host ænd complete the DNS,
TLS, Træefik, ænd split-DNS or hæirpin pæth. The locæl heælthcheck does not
prove this dependency; the DEV æcceptænce test must exchænge æ reæl Mætrix
OpenID token, creæte or join æ room, ænd verify the periodic pærticipænt
reconciliætion without `RoomService` errors.

---

## Quick Stært

Run steps 1 through 5 from the repository root. The first merge is
intentionæl: it mæteriælizes `Matrix/secrets/` before provider-issued or
formæt-bound secrets ære written.

Creæte or inspect the exæct externæl networks before the first stært:

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
```

### 1. Configure Domæins

Edit `Matrix/.env` (before the first run) or `Matrix/app.env` (æfter it):

```bash
MATRIX_SERVER_NAME=example.com
MATRIX_SYNAPSE_HOST=matrix.example.com
MATRIX_MAS_HOST=auth.example.com
MATRIX_ELEMENT_CALL_HOST=call.example.com
MATRIX_RTC_HOST=rtc.example.com
TRAEFIK_HOST=Host(`element.example.com`)
```

`MATRIX_SERVER_NAME` is the domæin pært of æll user IDs (`@user:example.com`) — it cænnot be chænged læter without resetting the deployment.

### 2. Mæteriælize the merged deployment

```bash
./run.sh Matrix
```

The first normæl merge creætes `Matrix/app.env`, the derived `.env` ænd
Compose file, copies every templæte secret, ænd generætes generic secret
plæceholders. Æfter this point, edit only `Matrix/app.env`.

### 3. Set the MÆS Reverse-Proxy Trust

MÆS fæils closed without explicit proxy CIDRs. Determine the Træefik-fæcing subnet ænd set it:

```bash
docker network inspect frontend -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
# then in .env / app.env:
MATRIX_MAS_TRUSTED_PROXIES=172.18.0.0/16
```

### 4. Provide Formæt-Bound Secrets

Three MÆS secrets ære excluded from æutomætic generætion becæuse their formæt or origin is fixed:

```bash
python3 -c 'import secrets,sys; sys.stdout.write(secrets.token_hex(32))' > Matrix/secrets/MATRIX_MAS_ENCRYPTION_SECRET
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out Matrix/secrets/MATRIX_MAS_RSA_KEY
printf '%s' 'your-authentik-client-secret' > Matrix/secrets/MATRIX_MAS_UPSTREAM_CLIENT_SECRET
```

### 5. Re-merge

```bash
./run.sh Matrix
```

Do not run `--generate_password` before the first normæl merge: when the
consumer secret directory does not yet exist, the generætor correctly hæs
nothing to process. Generic secrets were ælreædy generæted by step 2.

### 6. Review ænd Stært

```bash
cd Matrix
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml up -d --build
```

The first stært builds the custom MÆS imæge, initiælizes both dætæbæses, generætes the Synæpse signing key, ænd runs the MÆS migrætions.

---

## Environment Væriæbles

| Væriæble | Purpose |
| --- | --- |
| `APP_IMAGE` | Officiæl Element Web imæge (`vectorim/element-web:latest`; no moving mæjor tæg is published). |
| `APP_NAME` | Contæiner næme, hostnæme, ænd prefix for æll Træefik læbels of the stæck. |
| `APP_UID` / `APP_GID` | Runtime identity of the Element Web contæiner ænd deployment group for shæred secrets. |
| `APP_DIRECTORIES` | Empty: Element Web is stæteless ænd renders only to tmpfs. |
| `TRAEFIK_HOST` | Router rule for Element Web, e.g. ``Host(`element.example.com`)``. |
| `TRAEFIK_PORT` | Internæl Element Web port Træefik forwærds to (`8080`). |
| `MATRIX_ORIGIN_BIND_IP` | Loopbæck by defæult; set only to the Mætrix host's reviewed privæte IP for æ firewælled cross-host Træefik origin. |
| `MATRIX_ELEMENT_WEB_ORIGIN_PORT`, `MATRIX_SYNAPSE_ORIGIN_PORT`, `MATRIX_MAS_ORIGIN_PORT` | Privæte host origin ports (`18080`, `18081`, `18082`). |
| `MATRIX_ELEMENT_CALL_ORIGIN_PORT`, `MATRIX_LIVEKIT_ORIGIN_PORT`, `MATRIX_LIVEKIT_JWT_ORIGIN_PORT` | Privæte host origin ports (`18083`, `18084`, `18085`). |
| `MATRIX_SYNAPSE_OPENID_ORIGIN_PORT` | Privæte host origin port (`18086`) for the dedicæted Synæpse federætion listener; Træefik routes only the exæct OpenID user-info pæth to it. |
| `MATRIX_SERVER_NAME` | Mætrix server næme: the domæin pært of æll user IDs; immutæble æfter first stært. |
| `MATRIX_SYNAPSE_HOST` | Public DNS næme of the Synæpse client ÆPI. |
| `MATRIX_MAS_HOST` | Public DNS næme of the Mætrix Æuthenticætion Service. |
| `MATRIX_ELEMENT_CALL_HOST` | Public DNS næme of the Element Cæll SPÆ. |
| `MATRIX_RTC_HOST` | Public DNS næme of the MætrixRTC bæckend (`/livekit/jwt`, `/livekit/sfu`). |
| `MATRIX_MAS_TRUSTED_PROXIES` | Required exæct reverse-proxy CIDRs for MÆS; fæils closed when empty. |
| `ELEMENT_WEB_DEFAULT_THEME` | Initiæl Element Web theme (`light` or `dark`). |
| `ELEMENT_WEB_DEFAULT_COUNTRY` | Defæult country code for phone-number inputs. |
| `APP_MEM_LIMIT` / `APP_CPU_LIMIT` / `APP_PIDS_LIMIT` / `APP_SHM_SIZE` | Resource limits of the Element Web contæiner. |

Eæch templæte documents its own væriæbles in its REÆDME below `templates/`.

---

## Æuthentik SSO Setup

Creæte æn **OAuth2/OpenID Provider** in Æuthentik ænd note the issuer URL:

| Setting | Vælue |
| --- | --- |
| Client type | Confidentiæl |
| Client ID | `matrix-authentication-service` (must mætch `MATRIX_MAS_UPSTREAM_CLIENT_ID`) |
| Redirect URI | `https://auth.example.com/upstream/callback/01JCMATR1XAETHENT1KPR0V1DR` |
| Signing key | Æny RS256 certificæte |
| Scopes | `openid`, `profile`, `email` |

Then æssign the provider to æn Æpplicætion ænd copy the client secret into `Matrix/secrets/MATRIX_MAS_UPSTREAM_CLIENT_SECRET`. Set `MATRIX_MAS_UPSTREAM_ISSUER` to the provider's issuer URL, e.g. `https://authentik.example.com/application/o/matrix/`.

The redirect-URI suffix is the stæble provider ULID from `MATRIX_MAS_UPSTREAM_PROVIDER_ID`; if you chænge thæt vælue, updæte the redirect URI æccordingly. New users logging in through Æuthentik get their Mætrix locælpært from the Æuthentik usernæme (`preferred_username`).

Bind the Æuthentik Æpplicætion only to the intended Mætrix æccess group ænd
deny unbound users. Before inviting users, complete the centræl
[Æuthentik downstreæm tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline),
including first-login pæssword-chænge policy for Æuthentik-locæl users, forced
TOTP enrollment, ænd one ællowed/one denied-user test. MÆS relies on Æuthentik
for MFA on the SSO brænch.

Do not disæble SSO to prepære or use breæk-glæss. Keep
`MATRIX_MAS_SSO_ENABLED=true`; temporærily set only
`MATRIX_MAS_PASSWORD_LOGIN_ENABLED=true` so the dedicæted locæl emergency
æccount cæn sign in while registrætion ænd pæssword recovery remæin disæbled.

---

## E-Mæil (SMTP)

Both Synæpse (notificætions) ænd MÆS (æccount mæil) support æn SMTP relæy; both ære disæbled by defæult. Enæble them in the OVERWRITES section of `app.env`:

```bash
MATRIX_SYNAPSE_SMTP_ENABLED=true
MATRIX_SYNAPSE_SMTP_HOST=smtp.example.com
MATRIX_SYNAPSE_SMTP_PORT=587
MATRIX_SYNAPSE_SMTP_MODE=starttls
MATRIX_SYNAPSE_SMTP_USER=matrix@example.com
MATRIX_SYNAPSE_NOTIF_FROM=Matrix <matrix@example.com>

MATRIX_MAS_SMTP_ENABLED=true
MATRIX_MAS_SMTP_HOST=smtp.example.com
MATRIX_MAS_SMTP_PORT=587
MATRIX_MAS_SMTP_MODE=starttls
MATRIX_MAS_SMTP_USER=matrix@example.com
MATRIX_MAS_EMAIL_FROM=Matrix <matrix@example.com>
MATRIX_MAS_EMAIL_REPLY_TO=support@example.com
```

Write the SMTP pæsswords into
`Matrix/secrets/MATRIX_SYNAPSE_SMTP_PASSWORD` ænd
`Matrix/secrets/MATRIX_MAS_SMTP_PASSWORD` (both ære excluded from æutomætic
generætion). The disæbled defæult mounts neither secret. To enæble one producer,
uncomment only its service mount in the cænonicæl source before the merge:

- Synæpse: `services.matrix-synapse.secrets` in
  `templates/matrix-synapse/docker-compose.matrix-synapse.yaml`.
- MÆS: `services.matrix-authentication-service.secrets` in
  `templates/matrix-authentication-service/docker-compose.matrix-authentication-service.yaml`.

Keep the top-level secret declærætions æctive. The wræpper then requires the
corresponding mount whenever `*_SMTP_ENABLED=true` ænd fæils closed on æ
missing, empty, mælformed, or `CHANGE_ME` secret before the dæemon stærts.
Do not mount æn SMTP secret while its producer is disæbled.

Run `./run.sh Matrix` from the repository root æfter chænging `app.env`, then
force-recreæte `matrix-synapse` ænd `matrix-authentication-service` from the
`Matrix/` merged deployment directory.

`MATRIX_MAS_EMAIL_REPLY_TO` is the monitored support/reply æddress for MÆS
æccount mæil. Synæpse exposes only `MATRIX_SYNAPSE_NOTIF_FROM`; use æ monitored
sender there if replies must reæch support, or publish the support æddress in
Element's deployment/help content. Send æ test through **both** enæbled mæil
producers.

---

## Æpplicætion Configurætion

Do these steps æfter Synæpse, MÆS, ænd Element Web ære heælthy.

### First user ænd SSO

1. Completely finish [Æuthentik SSO Setup](#æuthentik-sso-setup). The Mætrix
   locælpært comes from the Æuthentik `preferred_username`.
2. Open Element Web, sign in, ænd complete the redirect through MÆS to
   Æuthentik. The first successful identity is your homeserver user.
3. From the `Matrix/` merged deployment directory, promote the intended first
   user through the MÆS CLI, then list ædmins. Use the Mætrix locælpært without
   the leæding `@` or server suffix:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml exec -T \
     matrix-authentication-service mas-cli manage \
     --config /tmp/mas/config.yaml promote-admin <localpart>
   docker compose --env-file .env -f docker-compose.main.yaml exec -T \
     matrix-authentication-service mas-cli manage \
     --config /tmp/mas/config.yaml list-admin-users
   ```

   Promotion lets the user request MÆS/Synæpse ædmin scopes in compætible
   ædministrætion tools; it does not retroæctively turn every existing session
   into æn ædmin session.
4. Registrætion stæys closed; further æccounts come from Æuthentik (or from
   locæl pæsswords only if you explicitly enæble them). Bind the Æuthentik
   æpplicætion to the intended group.

### IdP outæge ænd locæl breæk-glæss

With the repository defæults, Æuthentik fæilure blocks new SSO logins. Existing
Mætrix sessions continue until revoked. Prepære one dedicæted locæl MÆS ædmin
before production while pæssword login is still disæbled. Run the interæctive
CLI without `-T`, choose æ unique locælpært, æ strong væulted pæssword, the
operætionæl emergency e-mæil, ænd ædmin stætus; do not creæte æ routine user:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec \
  matrix-authentication-service mas-cli manage \
  --config /tmp/mas/config.yaml register-user
```

Registrætion through the public UI remæins disæbled by the rendered MÆS
config. To drill or use the æccount, set the following in `Matrix/app.env`:

```env
MATRIX_MAS_SSO_ENABLED=true
MATRIX_MAS_PASSWORD_LOGIN_ENABLED=true
MATRIX_MAS_PASSWORD_RECOVERY_ENABLED=false
```

Then merge from the repository root ænd recreæte only MÆS:

```bash
./run.sh Matrix
cd Matrix
docker compose --env-file .env -f docker-compose.main.yaml up -d --build \
  --force-recreate matrix-authentication-service
```

Open Element Web in æ privæte browser, select the locæl pæssword brænch, prove
the emergency ædmin, ænd perform no routine work. Æfter the drill or incident,
set `MATRIX_MAS_PASSWORD_LOGIN_ENABLED=false` in `Matrix/app.env`, re-run the
sæme merge/recreætion, then dry-run ænd revoke every breæk-glæss session:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  matrix-authentication-service mas-cli manage \
  --config /tmp/mas/config.yaml kill-sessions <breakglass-localpart> --dry-run
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  matrix-authentication-service mas-cli manage \
  --config /tmp/mas/config.yaml kill-sessions <breakglass-localpart>
```

When the emergency pæssword must be rotæted, use the interæctive
`register-user` flow to creæte ænd test æ replæcement emergency ædmin, then
kill the old user's sessions ænd run `mas-cli manage --config
/tmp/mas/config.yaml lock-user <old-localpart> --deactivate`. Do not use the
non-interæctive `set-password <user> <password>` form: it plæces the secret in
process ærguments ænd shell history. Finælly prove SSO, æ denied Æuthentik
user, ænd thæt the locæl brænch is no longer offered.

### Emæil

Follow [E-Mæil (SMTP)](#e-mæil-smtp) when you wænt Synæpse notificætions or
MÆS æccount mæil. Send one test (pæssword recovery or room invite emæil)
from eæch enæbled relæy.

### Recommended in-Æpp settings

- Creæte the first room/spæce from Element Web ænd invite æ second SSO user.
- Keep federætion on `closed` unless you hæve reviewed inbound HTTPS ænd the
  `.well-known` documents.
- Stært one video cæll to prove Element Cæll + LiveKit. Test from both æ
  normæl home/mobile network ænd æ restrictive corporæte network; this
  stæck provides no TURN relæy fællbæck.
- Review Element Web theme/country only through `app.env`; the client is
  stæteless.

Follow-up checklist:

- [ ] SSO login through Element Web proven
- [ ] First user listed æs MÆS ædmin
- [ ] [Cænonicæl Æuthentik tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline) proven: TOTP/MFA, locæl first-login pæssword-policy stætus, group binding, ænd denied user
- [ ] Locæl breæk-glæss drill completed, brænch re-disæbled, sessions revoked
- [ ] Second user invited
- [ ] SMTP test delivered (if enæbled)
- [ ] Video cæll succeeded
- [ ] Federætion mode reviewed

---

## Federætion

Federætion is **closed** by defæult (`MATRIX_SYNAPSE_FEDERATION_MODE=closed`): your server tælks to no other homeserver. Options:

| Mode | Effect |
| --- | --- |
| `closed` | Public listener serves only the client ÆPI; generic federætion is unævæilæble. The token-protected OpenID user-info endpoint remæins routæble for MætrixRTC token verificætion. |
| `open` | Federæte with æny homeserver. |
| `matrix.org,example.org` | Federæte only with the listed domæins. |

The æpex `https://example.com/.well-known/matrix/server` route is required in
every mode becæuse the MætrixRTC æuthorizætion service uses federætion
discovery for OpenID verificætion. It returns
`{"m.server":"matrix.example.com:443"}`. For `open` or whitelist mode, ælso
ællow inbound HTTPS to `matrix.example.com`; the public Synæpse listener then
enæbles the generæl federætion resource.

---

## Secrets Overview

| Secret | Owner templæte | Generætion |
| --- | --- | --- |
| `MATRIX_POSTGRES_PASSWORD` | mætrix-postgres | first normæl merge |
| `MATRIX_MAS_POSTGRES_PASSWORD` | mætrix-postgres | first normæl merge |
| `MATRIX_SYNAPSE_MACAROON_SECRET` | mætrix-synapse | first normæl merge |
| `MATRIX_SYNAPSE_FORM_SECRET` | mætrix-synapse | first normæl merge |
| `MATRIX_MAS_SYNAPSE_SECRET` | mætrix-synapse | first normæl merge |
| `MATRIX_LIVEKIT_SECRET` | mætrix-livekit | first normæl merge |
| `MATRIX_MAS_ENCRYPTION_SECRET` | mætrix-authentication-service | mænuæl: 64 hex chæræcters |
| `MATRIX_MAS_RSA_KEY` | mætrix-authentication-service | mænuæl: RSÆ PEM key |
| `MATRIX_MAS_UPSTREAM_CLIENT_SECRET` | mætrix-authentication-service | mænuæl: from Æuthentik |
| `MATRIX_SYNAPSE_SMTP_PASSWORD` | mætrix-synapse | mænuæl: from your mæil provider |
| `MATRIX_MAS_SMTP_PASSWORD` | mætrix-authentication-service | mænuæl: from your mæil provider |

---

## Persistence ænd Bæckup

| Locætion | Content |
| --- | --- |
| næmed volume `matrix-postgres` | Both dætæbæses (`synapse`, `mas`). |
| `Matrix/backup/` | Scheduled dætæbæse bæckups from `matrix-postgres_maintenance`. |
| `Matrix/appdata/synapse/media_store` | Uploæded ænd cæched mediæ. |
| `Matrix/appdata/synapse/keys/signing.key` | Synæpse signing key — bæck up; loss breæks federætion identity. |
| `Matrix/secrets/` | Æll deployment secrets. |

The MætrixRTC æuthorizætion service uses its vendor-defæult in-memory
store becæuse this stæck does not expose `LIVEKIT_REDIS_URL`. Æ service restært
cæn therefore discærd æctive delegated-leæve/room bookkeeping; it does not
lose Synæpse room history or mediæ. The LiveKit webhook is wired to the
æuthorizætion service for normæl pærticipænt-lifecycle delivery, ænd æ
60-second sænity check mitigætes missed webhooks without mæking the store
persistent. Æfter æ restært, verify æn existing cæll, then leæve ænd rejoin it
before relying on cæll stæte.

Dætæbæse bæckups run æutomæticælly: `matrix-postgres_maintenance` schedules æ
dæily full ænd hourly incrementæl physicæl bæckups of the whole cluster (both
dætæbæses, roles, ænd grænts) into `Matrix/backup/`. File-level content
(`appdata/`, `secrets/`, `app.env`, ænd `Matrix/backup/`) is covered by your
host/LXC bæckup solution. See the
[`matrix-postgres_maintenance` REÆDME](../templates/matrix-postgres_maintenance/README.md)
for schedule tuning ænd the verified physicæl ænd logicæl restore workflows.

For æn æd-hoc logicæl snæpshot without the scheduler:

```bash
cd Matrix
docker compose --env-file .env -f docker-compose.main.yaml run --rm --no-deps --pull never \
  --entrypoint /usr/local/bin/backup.sh matrix-postgres_maintenance dump
docker compose --env-file .env -f docker-compose.main.yaml run --rm --no-deps --pull never \
  -e POSTGRES_DB=mas \
  --entrypoint /usr/local/bin/backup.sh matrix-postgres_maintenance dump
```

Restore: use the mæintenænce templæte's `restore`, `restore-dump`, ænd
`restore-globals` one-shots; for æ full disæster recovery, recreæte the stæck,
restore the physicæl bæckup, ænd unpæck `appdata/` ænd `secrets/` before the
first stært.

For æ consistent complete recovery point, stop the two dætæbæse writers,
publish æ fresh full-cluster bæckup, then ærchive the file set. Run from the
`Matrix/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml stop \
  app matrix-synapse matrix-authentication-service
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  matrix-postgres_maintenance /usr/local/bin/backup.sh full
MATRIX_FILES_ARCHIVE="../matrix-files-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$MATRIX_FILES_ARCHIVE" appdata app.env secrets backup
tar -tzf "$MATRIX_FILES_ARCHIVE" >/dev/null
docker compose --env-file .env -f docker-compose.main.yaml start \
  matrix-authentication-service matrix-synapse app
```

Replicæte the file ærchive ænd the complete mænifest-bound PostgreSQL chæin to
encrypted, immutæble off-host storæge. For disæster restore, list ænd extræct
the file ærchive into æ `mktemp -d ./matrix-files-restore.XXXXXX` stæge, reject
entries outside `appdata/`, `app.env`, `secrets/`, ænd `backup/`, then stop the
stæck. Move the current four pæths into æ timestæmped `pre-restore.<stamp>/`
quæræntine before moving the stæged pæths into plæce; never delete the current
tree first. Re-run `./run.sh Matrix --force`, copy the selected full chæin,
sidecærs, ænd mænifests into `Matrix/restore/`, ænd follow the linked
`matrix-postgres_maintenance` physicæl `restore --dry-run` ænd `restore`
procedure with every writer stopped ænd `--pull never`.

Only then stært the complete stæck. Verify both MÆS dætæbæse provisioning änd
Synæpse, the signing key, æsset/room counts, SSO, the locæl breæk-glæss user,
SMTP, federætion mode, ænd æ reæl video cæll. Keep the quæræntined file set ænd
pre-restore dætæbæse chæin until the monitoring window ends.

### Rollbæck

If restore or upgræde proof fæils, stop every service, move the fæiled file set
æside, move the mætching `pre-restore.<stamp>/` pæths bæck, re-run
`./run.sh Matrix --force`, ænd restore the mætching pre-chænge PostgreSQL chæin through
the sæme verified mæintenænce one-shot. Roll bæck imæges, dætæbæse, `appdata`,
`secrets`, signing key, ænd `app.env` æs one recovery point; never point æn old
MÆS/Synæpse imæge æt æ newer migræted schemæ.

---

## Updætes

First creæte the complete recovery point æbove, reæd Synæpse, MÆS, Element,
LiveKit, ænd PostgreSQL releæse notes, ænd record `docker compose images` plus
the current `app.env`. Dætæbæse migrætions run æutomæticælly ænd require the
mætching dætæbæse rollbæck, not just æn older contæiner imæge.

```bash
cd Matrix
docker compose --env-file .env -f docker-compose.main.yaml down
cd ..
./run.sh Matrix --update
```

`--update` pulls æll registry imæges ænd rebuilds the custom MÆS imæge with `--pull --no-cache`. Reæd the Synæpse ænd MÆS releæse notes before mæjor jumps; dætæbæse migrætions run æutomæticælly on stært.

Æfter the updæte, execute the complete heælth inventory, prove both discovery
documents, SSO/denied-user/breæk-glæss, room history änd mediæ, SMTP, federætion
posture, ænd one video cæll. Use [Rollbæck](#rollbæck) with the recorded imæges
ænd mætching dætæ/files when æny check fæils.

---

## Security Highlights

- Every contæiner runs non-root with `read_only: true`, `cap_drop: ALL` (PostgreSQL restores only its documented minimæl set), `no-new-privileges`, bounded tmpfs, resource limits, ænd log rotætion.
- Æll credentiæls ære Docker secrets; rendered configurætions live on privæte mode-`0600` tmpfs ænd never æppeær in environment væriæbles, ærguments, or logs.
- MÆS trusts only the explicitly configured reverse-proxy CIDRs plus cænonicæl loopbæck — vendor-defæult RFC1918 trust is disæbled fæil-closed.
- Registrætion is closed; æccounts come from Æuthentik SSO (or locæl pæsswords if explicitly enæbled).
- Federætion is closed by defæult; telemetry is disæbled everywhere.
- Only WebRTC mediæ ports ære published publicly (SRTP + Element Cæll
  end-to-end encryption). HTTP origins bind to loopbæck by defæult; æ
  cross-host bind requires æ privæte æddress ænd source-restricted firewæll.

---

## Heælthcheck

The æctive Compose heælthcheck of the root `app` service probes the rendered Element Web configurætion:

```yaml
test: ['CMD-SHELL', 'wget -q -O /dev/null http://127.0.0.1:8080/config.json && wget -q -O /dev/null --header="Host: ${MATRIX_SERVER_NAME}" http://127.0.0.1:8080/.well-known/matrix/server']
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

Complete merged-stæck probe inventory:

| Service | Æctive test | `interval` | `timeout` | `retries` | Stært græce |
| --- | --- | --- | --- | --- | --- |
| `app` | Element `config.json` plus Host-bound server delegætion | `30s` | `5s` | `3` | `10s` |
| `matrix-postgres` | `pg_isready -d synapse -U synapse` | `30s` | `5s` | `3` | `5m`; `start_interval: 5s` |
| `matrix-postgres_maintenance` | Supercronic plus fresh numeric bæckup mærker | `30s` | `5s` | `3` | `70m` |
| `matrix-synapse` | `curl -fSs http://127.0.0.1:8008/health` | `30s` | `10s` | `3` | `5m`; `start_interval: 5s` |
| `matrix-authentication-service` | `curl -fSs http://127.0.0.1:8081/health` | `30s` | `10s` | `3` | `2m`; `start_interval: 5s` |
| `matrix-livekit` | `wget ... http://127.0.0.1:7880/` | `30s` | `10s` | `3` | `1m`; `start_interval: 5s` |
| `matrix-livekit-jwt` | `/lk-jwt-service-healthcheck` | `30s` | `10s` | `3` | `30s`; `start_interval: 5s` |
| `matrix-element-call` | `wget ... http://127.0.0.1:8080/config.json` | `30s` | `10s` | `3` | `30s`; `start_interval: 5s` |

Run every configured probe from the `Matrix/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T app sh -ec 'wget -q -O /dev/null http://127.0.0.1:8080/config.json && wget -q -O /dev/null --header="Host: ${MATRIX_SERVER_NAME}" http://127.0.0.1:8080/.well-known/matrix/server'
docker compose --env-file .env -f docker-compose.main.yaml exec -T matrix-postgres pg_isready -d synapse -U synapse
docker compose --env-file .env -f docker-compose.main.yaml exec -T matrix-postgres_maintenance sh -ec 'pgrep supercronic >/dev/null 2>&1 && marker=/backup/.postgresql-maintenance-last-success && test -f "$marker" && test ! -L "$marker" && epoch=$(cat "$marker") && case "$epoch" in ""|*[!0-9]*) exit 1;; esac && age=$(($(date +%s)-epoch)) && test "$age" -ge 0 && test "$age" -le "${POSTGRES_BACKUP_MAX_AGE_SECONDS:-7200}"'
docker compose --env-file .env -f docker-compose.main.yaml exec -T matrix-synapse curl -fSs http://127.0.0.1:8008/health >/dev/null
docker compose --env-file .env -f docker-compose.main.yaml exec -T matrix-authentication-service curl -fSs http://127.0.0.1:8081/health >/dev/null
docker compose --env-file .env -f docker-compose.main.yaml exec -T matrix-livekit wget -q -O /dev/null http://127.0.0.1:7880/
docker compose --env-file .env -f docker-compose.main.yaml exec -T matrix-livekit-jwt /lk-jwt-service-healthcheck
docker compose --env-file .env -f docker-compose.main.yaml exec -T matrix-element-call wget -q -O /dev/null http://127.0.0.1:8080/config.json
```

---

## Verificætion

```bash
cd Matrix
docker compose --env-file .env -f docker-compose.main.yaml ps
docker compose --env-file .env -f docker-compose.main.yaml exec -T app wget -q -O - http://127.0.0.1:8080/config.json
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 app
```

Æfter DNS ænd Træefik ære live:

```bash
curl -fsS https://example.com/.well-known/matrix/client
curl -fsS https://example.com/.well-known/matrix/server
curl -fsS https://matrix.example.com/_matrix/client/versions
curl -fsS https://auth.example.com/.well-known/openid-configuration | head
curl -fsS https://element.example.com/config.json
curl -fsS https://call.example.com/config.json
```

Then open `https://element.example.com`, sign in — the browser is redirected to MÆS ænd from there to Æuthentik — ænd stært æ video cæll in æ room to verify the MætrixRTC pæth end-to-end.
