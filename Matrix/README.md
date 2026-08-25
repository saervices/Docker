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

```env
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

Run this block from the repository root.

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

```env
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
   MATRIX_ADMIN_LOCALPART=CHANGE_ME
   test "$MATRIX_ADMIN_LOCALPART" != CHANGE_ME
   docker compose --env-file .env -f docker-compose.main.yaml exec -T \
     matrix-authentication-service mas-cli manage \
     --config /tmp/mas/config.yaml promote-admin "$MATRIX_ADMIN_LOCALPART"
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

Run this block from the `Matrix/` merged deployment directory.

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

Run both commænds from the `Matrix/` merged deployment directory.

```bash
BREAKGLASS_LOCALPART=CHANGE_ME
test "$BREAKGLASS_LOCALPART" != CHANGE_ME
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  matrix-authentication-service mas-cli manage \
  --config /tmp/mas/config.yaml kill-sessions "$BREAKGLASS_LOCALPART" --dry-run
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  matrix-authentication-service mas-cli manage \
  --config /tmp/mas/config.yaml kill-sessions "$BREAKGLASS_LOCALPART"
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

For æn æd-hoc logicæl snæpshot without the scheduler, keep the Synæpse
one-time-key tæble out of the dump. Those rows ære ephemeræl ænd must never be
re-issued æfter æ restore. The mæintenænce workflow publishes the custom dumps
ætomicælly with æ checksum ænd bundle mænifest:

Run this block from the repository root.

```bash
cd Matrix
set -euo pipefail
umask 077
docker compose --env-file .env -f docker-compose.main.yaml run --rm --no-deps --pull never \
  -e POSTGRES_BACKUP_DUMP_ARGS=--exclude-table-data=e2e_one_time_keys_json \
  --entrypoint /usr/local/bin/backup.sh matrix-postgres_maintenance dump
docker compose --env-file .env -f docker-compose.main.yaml run --rm --no-deps --pull never \
  -e POSTGRES_DB=mas \
  --entrypoint /usr/local/bin/backup.sh matrix-postgres_maintenance dump
```

Restore: use the mæintenænce templæte's `restore`, `restore-dump`, ænd
`restore-globals` one-shots. Every Synæpse restore, including æ physicæl
whole-cluster restore, must then follow the PostgreSQL-only one-time-key cleænup
below before Synæpse is stærted.

For æ consistent complete recovery point, use æ privæte operætor-owned
directory on æ different filesystem. The workflow below needs no deployment
`.git`: it binds the optionæl source lock, templæte lock, dirty locæl
build/runtime inputs, rendered Compose, exæct running imæge IDs plus imæge
bytes, fresh Synæpse/MÆS dump bundle IDs, one fresh physicæl full-bundle ID,
ænd every persistent bind tree to one completion mærker. The scheduler ænd
æll æpplicætion writers stop before the first inventory; only short-lived
`--pull never` mæintenænce one-shots run until PostgreSQL is stopped. Æny
fæilure leæves the stæck stopped ænd the `.partial` directory unusæble.

Run this block from the `Matrix/` merged deployment directory.

```bash
set -euo pipefail
umask 077
: "${MATRIX_RECOVERY_ROOT:?Set an absolute external recovery directory}"

compose=(docker compose --env-file .env -f docker-compose.main.yaml)
matrix_root="$(pwd -P)"
test "$PWD" = "$matrix_root"
test -d "$matrix_root" && test ! -L "$matrix_root"
matrix_id="$(stat -Lc '%d:%i' -- "$matrix_root")"
exec {project_root_fd}<"$matrix_root"
test "$(readlink -e -- "/proc/${BASHPID}/fd/${project_root_fd}")" = \
  "$matrix_root"
test "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${project_root_fd}")" = \
  "$matrix_id"
flock -n -x "$project_root_fd"
test "$(stat -Lc '%d:%i' -- "$matrix_root")" = "$matrix_id"
test -d .run.conf && test ! -L .run.conf
run_conf_id="$(stat -Lc '%d:%i' -- .run.conf)"
exec {project_lock_fd}<.run.conf
test "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${project_lock_fd}")" = \
  "$run_conf_id"
flock -n -x "$project_lock_fd"
test ! -L .run.conf
test "$(stat -Lc '%d:%i' -- .run.conf)" = "$run_conf_id"

recovery_root="$(realpath -e -- "$MATRIX_RECOVERY_ROOT")"
test "$recovery_root" = "$MATRIX_RECOVERY_ROOT"
test -d "$recovery_root" && test ! -L "$recovery_root"
test "$(stat -Lc %u -- "$recovery_root")" = "$(id -u)"
test "$(stat -Lc %a -- "$recovery_root")" = 700
test "$(stat -Lc %d -- "$recovery_root")" != "${matrix_id%%:*}"
case "$recovery_root/" in "$matrix_root/"* ) exit 1 ;; esac
case "$matrix_root/" in "$recovery_root/"* ) exit 1 ;; esac

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
partial="$recovery_root/.matrix-$stamp.partial"
published="$recovery_root/matrix-$stamp"
test ! -e "$partial" && test ! -L "$partial"
test ! -e "$published" && test ! -L "$published"
mkdir -m 0700 "$partial"
"${compose[@]}" config --quiet
for required_dir in appdata secrets backup scripts dockerfiles; do
  test -d "$required_dir" && test ! -L "$required_dir"
done
for required in app.env .env docker-compose.main.yaml docker-compose.app.yaml \
    docker-compose.matrix-postgres_maintenance.restore.yaml.example \
    .run.conf/.templates.lock; do
  test -f "$required" && test ! -L "$required"
done
grep -Eq '^([0-9a-f]{40}|[0-9a-f]{64})$' .run.conf/.templates.lock
test "$(wc -l < .run.conf/.templates.lock)" -eq 1
install -m 0600 .run.conf/.templates.lock "$partial/templates.lock"
if [[ -e .run.conf/.source.lock || -L .run.conf/.source.lock ]]; then
  test -f .run.conf/.source.lock && test ! -L .run.conf/.source.lock
  python3 - .run.conf/.source.lock <<'PY'
import re
import sys

lines = open(sys.argv[1], encoding='ascii').read().splitlines()
if len(lines) != 3 or lines[0] != 'version=1':
    raise SystemExit('malformed source lock')
for key, line in zip(('commit', 'tree'), lines[1:]):
    if not re.fullmatch(fr'{key}=([0-9a-f]{{40}}|[0-9a-f]{{64}})', line):
        raise SystemExit('malformed source lock')
PY
  install -m 0600 .run.conf/.source.lock "$partial/source.lock"
  printf '%s\n' 'mode=source-lock' > "$partial/source-evidence.txt"
else
  printf '%s\n' 'mode=deployment-inputs-only' \
    > "$partial/source-evidence.txt"
fi
printf '%s\n' "$matrix_root" > "$partial/project-root.txt"

env -i PATH="$PATH" docker compose --env-file .env \
  -f docker-compose.main.yaml config > "$partial/rendered-compose.yaml"
env -i PATH="$PATH" docker compose --env-file .env \
  -f docker-compose.main.yaml config --format json \
  > "$partial/rendered-compose.json"
python3 - "$partial/rendered-compose.json" <<'PY'
import json
import os
import sys

document = json.load(open(sys.argv[1], encoding='utf-8'))
build_root = os.path.realpath('dockerfiles')
for service, definition in document['services'].items():
    build = definition.get('build')
    if not build:
        continue
    context = build if isinstance(build, str) else build.get('context', '')
    if not os.path.isabs(context) or os.path.realpath(context) != build_root:
        raise SystemExit(f'unarchived local build context for {service}: {context!r}')
PY

rendered_project_name="$(python3 - "$partial/rendered-compose.json" <<'PY'
import json
import sys

name = json.load(open(sys.argv[1], encoding='utf-8')).get('name')
if not isinstance(name, str) or not name or any(char in name for char in '\t\r\n'):
    raise SystemExit('rendered Compose project name is invalid')
print(name)
PY
)"
clean_compose=(env -i PATH="$PATH" docker compose \
  --project-directory "$matrix_root" --project-name "$rendered_project_name" \
  --env-file "$matrix_root/.env" -f "$matrix_root/docker-compose.main.yaml")
compose=(docker compose --project-directory "$matrix_root" \
  --project-name "$rendered_project_name" --env-file "$matrix_root/.env" \
  -f "$matrix_root/docker-compose.main.yaml")
services_output="$("${clean_compose[@]}" config --services)"
mapfile -t services <<< "$services_output"
test "${#services[@]}" -gt 0
declare -A seen_services=()
declare -A service_containers=()
declare -a image_refs=()
: > "$partial/image-map.tsv.partial"
for service in "${services[@]}"; do
  test -n "$service" && test -z "${seen_services[$service]+set}"
  seen_services[$service]=1
  containers_output="$(docker ps -aq \
    --filter "label=com.docker.compose.project=$rendered_project_name" \
    --filter "label=com.docker.compose.service=$service")"
  mapfile -t containers <<< "$containers_output"
  test "${#containers[@]}" -eq 1 && test -n "${containers[0]}"
  service_containers[$service]="${containers[0]}"
  test "$(docker inspect -f \
    '{{index .Config.Labels "com.docker.compose.project"}}' \
    "${containers[0]}")" = "$rendered_project_name"
  test "$(docker inspect -f \
    '{{index .Config.Labels "com.docker.compose.service"}}' \
    "${containers[0]}")" = "$service"
  image_ref="$(docker inspect -f '{{.Config.Image}}' "${containers[0]}")"
  image_id="$(docker inspect -f '{{.Image}}' "${containers[0]}")"
  container_config_hash="$(docker inspect -f \
    '{{index .Config.Labels "com.docker.compose.config-hash"}}' \
    "${containers[0]}")"
  [[ "$container_config_hash" =~ ^[0-9a-f]{64}$ ]]
  config_hash_override="$partial/.config-hash-image-override.json"
  python3 - "$service" "$image_ref" "$config_hash_override" <<'PY'
import json
import sys

with open(sys.argv[3], 'w', encoding='utf-8') as stream:
    json.dump({'services': {sys.argv[1]: {'image': sys.argv[2]}}}, stream)
PY
  expected_config_hash_line="$("${clean_compose[@]}" \
    -f "$config_hash_override" config --hash "$service")"
  case "$expected_config_hash_line" in
    "$service "*) ;;
    *) printf 'invalid Compose config-hash output for %s\n' "$service" >&2
       exit 1 ;;
  esac
  expected_config_hash="${expected_config_hash_line#"$service "}"
  [[ "$expected_config_hash" =~ ^[0-9a-f]{64}$ ]]
  test "$expected_config_hash" = "$container_config_hash"
  rm -- "$config_hash_override"
  test "$(docker image inspect -f '{{.Id}}' "$image_ref")" = "$image_id"
  printf '%s\t%s\t%s\n' "$service" "$image_ref" "$image_id" \
    >> "$partial/image-map.tsv.partial"
  image_refs+=("$image_ref")
done
project_containers_output="$(docker ps -aq \
  --filter "label=com.docker.compose.project=$rendered_project_name")"
mapfile -t project_containers <<< "$project_containers_output"
test "${#project_containers[@]}" -eq "${#services[@]}"
for container_id in "${project_containers[@]}"; do
  test -n "$container_id"
  container_service="$(docker inspect -f \
    '{{index .Config.Labels "com.docker.compose.service"}}' "$container_id")"
  test -n "${seen_services[$container_service]+set}"
  test "${service_containers[$container_service]}" = "$container_id"
done
runtime_yaml="$partial/.runtime-compose.yaml"
runtime_json="$partial/.runtime-compose.json"
"${compose[@]}" config > "$runtime_yaml"
"${compose[@]}" config --format json > "$runtime_json"
cmp -- "$partial/rendered-compose.yaml" "$runtime_yaml"
cmp -- "$partial/rendered-compose.json" "$runtime_json"
rm -- "$runtime_yaml" "$runtime_json"
docker network inspect frontend backend > "$partial/.network-inspect.json"
python3 - "$partial/rendered-compose.json" \
  "$partial/.network-inspect.json" frontend backend \
  > "$partial/network-evidence.tsv.partial" <<'PY'
import ipaddress
import json
import sys

compose = json.load(open(sys.argv[1], encoding='utf-8'))
inspected = json.load(open(sys.argv[2], encoding='utf-8'))
expected = sys.argv[3:]
networks = compose.get('networks', {})
if set(networks) != set(expected) or len(expected) != len(set(expected)):
    raise SystemExit('rendered external-network closure differs')
by_name = {item.get('Name'): item for item in inspected}
if set(by_name) != set(expected) or len(inspected) != len(by_name):
    raise SystemExit('inspected external-network closure differs')
for key in expected:
    definition = networks[key]
    if definition.get('external') is not True or definition.get('name') != key:
        raise SystemExit(f'external network key/name drift: {key!r}')
    item = by_name[key]
    if item.get('Driver') != 'bridge' or item.get('Scope') != 'local':
        raise SystemExit(f'unsupported external network driver/scope: {key!r}')
    if any(item.get(field) for field in
           ('Internal', 'Attachable', 'Ingress', 'ConfigOnly', 'EnableIPv6')):
        raise SystemExit(f'unsupported external network mode: {key!r}')
    if item.get('Options') not in ({}, None):
        raise SystemExit(f'unsupported external network options: {key!r}')
    ipam = item.get('IPAM', {})
    if ipam.get('Driver') != 'default' or ipam.get('Options') not in ({}, None):
        raise SystemExit(f'unsupported external network IPAM: {key!r}')
    configs = ipam.get('Config', [])
    if len(configs) != 1:
        raise SystemExit(f'external network needs exactly one subnet: {key!r}')
    config = configs[0]
    if config.get('IPRange') not in (None, '') \
            or config.get('AuxiliaryAddresses') not in (None, {}):
        raise SystemExit(f'unsupported external network IPAM detail: {key!r}')
    subnet = ipaddress.ip_network(config.get('Subnet', ''), strict=True)
    gateway = ipaddress.ip_address(config.get('Gateway', ''))
    if gateway.version != subnet.version or gateway not in subnet:
        raise SystemExit(f'external network gateway is outside subnet: {key!r}')
    print(key, key, 'bridge', subnet, gateway, sep='\t')
PY
rm -- "$partial/.network-inspect.json"
mv "$partial/network-evidence.tsv.partial" "$partial/network-evidence.tsv"
docker version --format '{{.Server.Os}}\t{{.Server.Arch}}' \
  > "$partial/engine-platform.tsv.partial"
test "$(wc -l < "$partial/engine-platform.tsv.partial")" -eq 1
case "$(<"$partial/engine-platform.tsv.partial")" in
  $'linux\tamd64'|$'linux\tarm64') ;;
  *) exit 1 ;;
esac
mv "$partial/engine-platform.tsv.partial" "$partial/engine-platform.tsv"
image_refs_output="$(printf '%s\n' "${image_refs[@]}" | LC_ALL=C sort -u)"
mapfile -t image_refs <<< "$image_refs_output"
docker image save --output "$partial/images.tar.partial" "${image_refs[@]}"
while IFS=$'\t' read -r service image_ref image_id; do
  test "$(docker image inspect -f '{{.Id}}' "$image_ref")" = "$image_id"
  container_id="${service_containers[$service]}"
  test -n "$container_id"
  test "$(docker inspect -f '{{.Image}}' "$container_id")" = "$image_id"
done < "$partial/image-map.tsv.partial"

: > "$partial/archive-roots.tsv"
for root in appdata secrets backup scripts dockerfiles; do
  canonical="$(realpath -e -- "$root")"
  test "$canonical" = "$matrix_root/$root"
  identity="$(stat -Lc '%d:%i' -- "$canonical")"
  printf '%s\t%s\n' "$canonical" "$identity" >> "$partial/archive-roots.tsv"
done
validate_archive_mounts() {
python3 - "$1" "$partial/archive-roots.tsv" <<'PY'
import json
import os
import sys

document = json.load(open(sys.argv[1], encoding='utf-8'))
roots = [line.split('\t')[0] for line in
         open(sys.argv[2], encoding='utf-8').read().splitlines()]
if len(roots) != 5 or len(set(roots)) != 5:
    raise SystemExit('archive roots are not exact and unique')
for index, first in enumerate(roots):
    for second in roots[index + 1:]:
        if os.path.commonpath((first, second)) in (first, second):
            raise SystemExit('archive roots overlap')
stack = list(document.get('filesystems', []))
targets = []
while stack:
    node = stack.pop()
    stack.extend(node.get('children', []))
    target = node.get('target')
    if target and os.path.isabs(target):
        targets.append(os.path.realpath(target))
for root in roots:
    for target in targets:
        if target != root and os.path.commonpath((root, target)) == root:
            raise SystemExit(f'nested mount below archived root: {target!r}')
PY
}
findmnt --json --output TARGET > "$partial/host-mounts.before.json"
validate_archive_mounts "$partial/host-mounts.before.json"

"${compose[@]}" stop app matrix-synapse matrix-authentication-service \
  matrix-postgres_maintenance
inventory() {
  find backup -xdev -mindepth 2 -maxdepth 2 -type f -printf '%P\0' \
    | LC_ALL=C sort -z
}
record_new_bundle() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import re
import sys

def inventory(path):
    return {item.decode('ascii') for item in
            open(path, 'rb').read().split(b'\0') if item}

new = inventory(sys.argv[2]) - inventory(sys.argv[1])
kind = sys.argv[4]
pattern = (r'([0-9]{8})/dump_([0-9]{8}_[0-9]{6,9})\.dump\.zst'
           if kind == 'dump' else
           r'([0-9]{8})/full_([0-9]{8}_[0-9]{1,9})\.tar\.zst')
archives = [item for item in new if re.fullmatch(pattern, item)]
if len(archives) != 1:
    raise SystemExit(f'{kind} inventory did not add exactly one archive')
match = re.fullmatch(pattern, archives[0])
bundle_id = match.group(2)
if match.group(1) != bundle_id.split('_', 1)[0]:
    raise SystemExit(f'{kind} archive day and ID disagree')
directory, name = archives[0].split('/', 1)
stem = name.removesuffix('.dump.zst').removesuffix('.tar.zst')
expected = {
    archives[0], archives[0] + '.sha256',
    f'{directory}/bundle_{stem}.sha256',
}
if kind == 'full':
    expected.add(f'{directory}/{stem}.manifest')
if new != expected:
    raise SystemExit(f'{kind} bundle closure differs: {sorted(new ^ expected)}')
log = open(sys.argv[3], 'rb').read()
if f'Backup saved as /backup/{archives[0]}'.encode() not in log:
    raise SystemExit(f'{kind} log does not bind the inventory archive')
print(bundle_id)
PY
}

inventory > "$partial/backup-inventory.before"
"${compose[@]}" run --rm --no-deps --pull never \
  -e 'POSTGRES_BACKUP_DUMP_ARGS=--exclude-table-data=e2e_one_time_keys_json' \
  --entrypoint /usr/local/bin/backup.sh matrix-postgres_maintenance dump \
  2>&1 | tee "$partial/synapse-dump.log"
inventory > "$partial/backup-inventory.after-synapse"
record_new_bundle "$partial/backup-inventory.before" \
  "$partial/backup-inventory.after-synapse" "$partial/synapse-dump.log" dump \
  > "$partial/synapse-dump-id"

"${compose[@]}" run --rm --no-deps --pull never -e POSTGRES_DB=mas \
  --entrypoint /usr/local/bin/backup.sh matrix-postgres_maintenance dump \
  2>&1 | tee "$partial/mas-dump.log"
inventory > "$partial/backup-inventory.after-mas"
record_new_bundle "$partial/backup-inventory.after-synapse" \
  "$partial/backup-inventory.after-mas" "$partial/mas-dump.log" dump \
  > "$partial/mas-dump-id"

"${compose[@]}" run --rm --no-deps --pull never \
  --entrypoint /usr/local/bin/backup.sh matrix-postgres_maintenance full \
  2>&1 | tee "$partial/full.log"
inventory > "$partial/backup-inventory.after-full"
record_new_bundle "$partial/backup-inventory.after-mas" \
  "$partial/backup-inventory.after-full" "$partial/full.log" full \
  > "$partial/full-bundle-id"

"${compose[@]}" down
while IFS=$'\t' read -r root identity; do
  test "$(realpath -e -- "$root")" = "$root"
  test "$(stat -Lc '%d:%i' -- "$root")" = "$identity"
done < "$partial/archive-roots.tsv"
cmp -- .run.conf/.templates.lock "$partial/templates.lock"
if [[ -f "$partial/source.lock" ]]; then
  cmp -- .run.conf/.source.lock "$partial/source.lock"
fi
findmnt --json --output TARGET > "$partial/host-mounts.after.json"
validate_archive_mounts "$partial/host-mounts.after.json"

tar --acls --xattrs --numeric-owner -czpf "$partial/matrix-files.tar.gz.partial" \
  appdata app.env secrets backup .env docker-compose.main.yaml \
  docker-compose.app.yaml \
  docker-compose.matrix-postgres_maintenance.restore.yaml.example \
  scripts dockerfiles
python3 - "$partial/matrix-files.tar.gz.partial" <<'PY'
from pathlib import PurePosixPath
import sys
import tarfile

allowed = {
    'appdata', 'app.env', 'secrets', 'backup', '.env',
    'docker-compose.main.yaml', 'docker-compose.app.yaml',
    'docker-compose.matrix-postgres_maintenance.restore.yaml.example',
    'scripts', 'dockerfiles',
}
seen = set()
found = set()
with tarfile.open(sys.argv[1], 'r:gz') as archive:
    for member in archive:
        path = PurePosixPath(member.name)
        if path.is_absolute() or not path.parts or '..' in path.parts:
            raise SystemExit(f'unsafe archive path: {member.name!r}')
        normalized = path.as_posix().rstrip('/')
        if normalized in seen:
            raise SystemExit(f'duplicate archive member: {member.name!r}')
        seen.add(normalized)
        if path.parts[0] not in allowed:
            raise SystemExit(f'unexpected archive root: {member.name!r}')
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f'unsafe archive member type: {member.name!r}')
        found.add(path.parts[0])
if found != allowed:
    raise SystemExit(f'incomplete archive roots: {sorted(allowed - found)}')
PY

sync "$partial/matrix-files.tar.gz.partial" "$partial/images.tar.partial"
mv "$partial/matrix-files.tar.gz.partial" "$partial/matrix-files.tar.gz"
mv "$partial/images.tar.partial" "$partial/images.tar"
mv "$partial/image-map.tsv.partial" "$partial/image-map.tsv"
(cd "$partial" && sha256sum \
  matrix-files.tar.gz images.tar image-map.tsv rendered-compose.yaml \
  rendered-compose.json project-root.txt archive-roots.tsv \
  network-evidence.tsv engine-platform.tsv \
  host-mounts.before.json host-mounts.after.json \
  templates.lock source-evidence.txt synapse-dump-id mas-dump-id \
  full-bundle-id synapse-dump.log mas-dump.log full.log \
  backup-inventory.before backup-inventory.after-synapse \
  backup-inventory.after-mas backup-inventory.after-full \
  > recovery-manifest.sha256.partial)
if [[ -f "$partial/source.lock" ]]; then
  (cd "$partial" && sha256sum source.lock >> recovery-manifest.sha256.partial)
fi
mv "$partial/recovery-manifest.sha256.partial" \
  "$partial/recovery-manifest.sha256"
python3 - "$partial" "$recovery_root" <<'PY'
import os
import stat
import sys

for root, directories, files in os.walk(sys.argv[1], topdown=False,
                                        followlinks=False):
    for name in files:
        path = os.path.join(root, name)
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise SystemExit(f'non-regular recovery artifact: {path!r}')
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
descriptor = os.open(sys.argv[2], os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try:
    os.fsync(descriptor)
finally:
    os.close(descriptor)
PY
(cd "$partial" && sha256sum recovery-manifest.sha256 \
  > recovery-point.complete.partial)
mv "$partial/recovery-point.complete.partial" "$partial/recovery-point.complete"
python3 - "$partial/recovery-point.complete" "$partial" "$recovery_root" <<'PY'
import os
import sys

for path in sys.argv[1:]:
    flags = os.O_RDONLY | os.O_NOFOLLOW
    if os.path.isdir(path):
        flags |= os.O_DIRECTORY
    descriptor = os.open(path, flags)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
PY
partial_id="$(stat -Lc '%d:%i' -- "$partial")"
python3 - "$partial" "$published" <<'PY'
import ctypes
import os
import sys

libc = ctypes.CDLL(None, use_errno=True)
renameat2 = libc.renameat2
renameat2.argtypes = [ctypes.c_int, ctypes.c_char_p,
                      ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
renameat2.restype = ctypes.c_int
if renameat2(-100, os.fsencode(sys.argv[1]), -100, os.fsencode(sys.argv[2]), 1):
    error = ctypes.get_errno()
    raise OSError(error, os.strerror(error))
directory = os.open(os.path.dirname(sys.argv[2]), os.O_RDONLY | os.O_DIRECTORY)
try:
    os.fsync(directory)
finally:
    os.close(directory)
PY
test ! -e "$partial" && test ! -L "$partial"
test "$(stat -Lc '%d:%i' -- "$published")" = "$partial_id"
"${compose[@]}" up -d --no-build --pull never --wait --wait-timeout 300
printf 'Published complete recovery point: %s\n' "$published"
```

Replicæte the complete published directory to encrypted, immutæble off-host
storæge. Æ directory without `recovery-point.complete`, or with æ mismætching
completion/mænifest chæin, is incomplete ænd must not be restored.
`images.tar` is plætform-specific: `engine-platform.tsv` mækes the sæme Linux
Docker-server ærchitecture (`amd64` or `arm64`) æ hærd precondition.

The only supported DR mode is æ **fresh isolæted recovery host**. Before æny
project, imæge, or volume mutætion, the recorded project pæth ænd the selected
dedicæted Docker context must be empty: no contæiner, imæge, or volume. The
runbook recreætes no-clobber, recovery-only externæl networks from the
checksummed driver, subnet, ænd gætewæy evidence; it never joins æn existing
production Træefik network. Network creætion intentionælly precedes the
Compose `ERR` træp: æ pærtiæl recovery-network set is not reconciled ænd
requires immediæte host discærd. If æny commænd, imæge loæd, signæl,
`SIGKILL`, or host loss fæils, do not
reuse thæt Docker dæmon; discærd the whole host ænd retry from the verified
recovery point. This document clæims no in-plæce DB/file rollbæck.

```bash
set -euo pipefail
umask 077
: "${MATRIX_RECOVERY_POINT:?Set the complete published recovery directory}"
point="$(realpath -e -- "$MATRIX_RECOVERY_POINT")"
test "$point" = "$MATRIX_RECOVERY_POINT"
test -d "$point" && test ! -L "$point"
test "$(stat -Lc %u -- "$point")" = "$(id -u)"
test "$(stat -Lc %a -- "$point")" = 700
exec {recovery_lock_fd}<"$point"
flock -n -s "$recovery_lock_fd"
test -f "$point/recovery-point.complete" \
  && test ! -L "$point/recovery-point.complete"
(cd "$point" && sha256sum -c recovery-point.complete)
(cd "$point" && sha256sum -c recovery-manifest.sha256)
saved_engine_platform="$(<"$point/engine-platform.tsv")"
case "$saved_engine_platform" in
  $'linux\tamd64'|$'linux\tarm64') ;;
  *) exit 1 ;;
esac
test "$(docker version --format '{{.Server.Os}}\t{{.Server.Arch}}')" = \
  "$saved_engine_platform"
source_mode="$(<"$point/source-evidence.txt")"
case "$source_mode" in
  mode=source-lock)
    test -f "$point/source.lock" && test ! -L "$point/source.lock"
    test "$(grep -Fxc '  source.lock' "$point/recovery-manifest.sha256")" -eq 1
    ;;
  mode=deployment-inputs-only)
    test ! -e "$point/source.lock" && test ! -L "$point/source.lock"
    test "$(grep -Fc '  source.lock' "$point/recovery-manifest.sha256")" -eq 0
    ;;
  *) exit 1 ;;
esac

python3 - "$point/matrix-files.tar.gz" <<'PY'
from pathlib import PurePosixPath
import sys
import tarfile

allowed = {
    'appdata', 'app.env', 'secrets', 'backup', '.env',
    'docker-compose.main.yaml', 'docker-compose.app.yaml',
    'docker-compose.matrix-postgres_maintenance.restore.yaml.example',
    'scripts', 'dockerfiles',
}
seen = set()
found = set()
with tarfile.open(sys.argv[1], 'r:gz') as archive:
    for member in archive:
        path = PurePosixPath(member.name)
        if path.is_absolute() or not path.parts or '..' in path.parts:
            raise SystemExit(f'unsafe archive path: {member.name!r}')
        normalized = path.as_posix().rstrip('/')
        if normalized in seen:
            raise SystemExit(f'duplicate archive member: {member.name!r}')
        seen.add(normalized)
        if path.parts[0] not in allowed:
            raise SystemExit(f'unexpected archive root: {member.name!r}')
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f'unsafe archive member type: {member.name!r}')
        found.add(path.parts[0])
if found != allowed:
    raise SystemExit(f'incomplete archive roots: {sorted(allowed - found)}')
PY

python3 - "$point/rendered-compose.json" "$point/image-map.tsv" <<'PY'
import json
import re
import sys

services = set(json.load(open(sys.argv[1], encoding='utf-8'))['services'])
rows = [line.split('\t') for line in
        open(sys.argv[2], encoding='utf-8').read().splitlines()]
if len(rows) != len(services) or any(len(row) != 3 for row in rows):
    raise SystemExit('image map is not an exact service closure')
mapped = [row[0] for row in rows]
if set(mapped) != services or len(set(mapped)) != len(mapped):
    raise SystemExit('image map services are missing, extra, or duplicated')
references = {}
for service, reference, image_id in rows:
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', service):
        raise SystemExit(f'unsafe service in image map: {service!r}')
    if not reference or any(char.isspace() or ord(char) < 32 for char in reference):
        raise SystemExit(f'unsafe reference in image map: {reference!r}')
    if not re.fullmatch(r'sha256:[0-9a-f]{64}', image_id):
        raise SystemExit(f'invalid image ID for {service!r}')
    previous = references.setdefault(reference, image_id)
    if previous != image_id:
        raise SystemExit(f'one image reference maps to multiple IDs: {reference!r}')
PY

matrix_root="$(<"$point/project-root.txt")"
test -n "$matrix_root" && test "${matrix_root#/}" != "$matrix_root"
test "$(realpath -m -- "$matrix_root")" = "$matrix_root"
case "$point/" in "$matrix_root/"* ) exit 1 ;; esac
case "$matrix_root/" in "$point/"* ) exit 1 ;; esac
test ! -e "$matrix_root" && test ! -L "$matrix_root"

container_inventory="$(docker ps -aq)"
image_inventory="$(docker image ls -aq)"
volume_inventory="$(docker volume ls -q)"
test -z "$container_inventory"
test -z "$image_inventory"
test -z "$volume_inventory"
test "$(id -u)" -eq 0

matrix_parent="$(dirname -- "$matrix_root")"
test -d "$matrix_parent" && test ! -L "$matrix_parent"
test "$(realpath -e -- "$matrix_parent")" = "$matrix_parent"
mkdir -m 0700 "$matrix_root"
tar --acls --xattrs --numeric-owner -xzpf "$point/matrix-files.tar.gz" \
  -C "$matrix_root"
cd "$matrix_root"
mkdir -m 0700 .run.conf
install -m 0600 "$point/templates.lock" .run.conf/.templates.lock
if [[ -f "$point/source.lock" ]]; then
  install -m 0600 "$point/source.lock" .run.conf/.source.lock
fi

matrix_id="$(stat -Lc '%d:%i' -- "$matrix_root")"
exec {project_root_fd}<"$matrix_root"
test "$(readlink -e -- "/proc/${BASHPID}/fd/${project_root_fd}")" = \
  "$matrix_root"
test "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${project_root_fd}")" = \
  "$matrix_id"
flock -n -x "$project_root_fd"
test "$(stat -Lc '%d:%i' -- "$matrix_root")" = "$matrix_id"
run_conf_id="$(stat -Lc '%d:%i' -- .run.conf)"
exec {project_lock_fd}<.run.conf
test "$(stat -Lc '%d:%i' -- "/proc/${BASHPID}/fd/${project_lock_fd}")" = \
  "$run_conf_id"
flock -n -x "$project_lock_fd"
test ! -L .run.conf
test "$(stat -Lc '%d:%i' -- .run.conf)" = "$run_conf_id"

clean_yaml="$(mktemp .run.conf/matrix-rendered.XXXXXX.yaml)"
clean_json="$(mktemp .run.conf/matrix-rendered.XXXXXX.json)"
env -i PATH="$PATH" docker compose --env-file .env \
  -f docker-compose.main.yaml config > "$clean_yaml"
env -i PATH="$PATH" docker compose --env-file .env \
  -f docker-compose.main.yaml config --format json > "$clean_json"
cmp -- "$point/rendered-compose.yaml" "$clean_yaml"
cmp -- "$point/rendered-compose.json" "$clean_json"
rendered_project_name="$(python3 - "$clean_json" <<'PY'
import json
import sys

name = json.load(open(sys.argv[1], encoding='utf-8')).get('name')
if not isinstance(name, str) or not name or any(char in name for char in '\t\r\n'):
    raise SystemExit('rendered Compose project name is invalid')
print(name)
PY
)"
runtime_compose=(docker compose --project-directory "$matrix_root" \
  --project-name "$rendered_project_name" --env-file "$matrix_root/.env" \
  -f "$matrix_root/docker-compose.main.yaml")
runtime_yaml="$(mktemp .run.conf/matrix-runtime.XXXXXX.yaml)"
runtime_json="$(mktemp .run.conf/matrix-runtime.XXXXXX.json)"
"${runtime_compose[@]}" config > "$runtime_yaml"
"${runtime_compose[@]}" config --format json > "$runtime_json"
cmp -- "$clean_yaml" "$runtime_yaml"
cmp -- "$clean_json" "$runtime_json"
rm -- "$runtime_yaml" "$runtime_json"
maintenance_identity="$(python3 - "$clean_json" <<'PY'
import json
import re
import sys

user = str(json.load(open(sys.argv[1], encoding='utf-8'))
           ['services']['matrix-postgres_maintenance'].get('user', ''))
if not re.fullmatch(r'[0-9]+:[0-9]+', user):
    raise SystemExit('maintenance user is not an exact numeric UID:GID')
uid, gid = map(int, user.split(':'))
if uid == 0 or gid == 0 or uid > 2147483647 or gid > 2147483647:
    raise SystemExit('maintenance identity is not bounded non-root')
print(user)
PY
)"
IFS=: read -r maintenance_uid maintenance_gid <<< "$maintenance_identity"
command -v setpriv >/dev/null
test -d backup && test ! -L backup
chown -R --no-dereference \
  "$maintenance_uid:$maintenance_gid" backup
chmod 0700 backup
test -z "$(find backup -xdev \
  \( ! -user "$maintenance_uid" -o ! -group "$maintenance_gid" \) \
  -print -quit)"

python3 - "$matrix_root" "$matrix_parent" <<'PY'
import os
import stat
import sys

for root, directories, files in os.walk(sys.argv[1], topdown=False,
                                        followlinks=False):
    for name in files:
        path = os.path.join(root, name)
        descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        try:
            if not stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise SystemExit(f'non-regular project artifact: {path!r}')
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
    descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
descriptor = os.open(sys.argv[2], os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
try:
    os.fsync(descriptor)
finally:
    os.close(descriptor)
PY

restore_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
restore_journal=".run.conf/matrix-fresh-restore.${restore_stamp}.journal"
printf '%s\n' 'version=1' 'state=deployment-staged' > "$restore_journal"
fsync_matrix_metadata() {
  python3 - "$@" .run.conf <<'PY'
import os
import sys

for path in sys.argv[1:]:
    flags = os.O_RDONLY | os.O_NOFOLLOW
    if os.path.isdir(path):
        flags |= os.O_DIRECTORY
    descriptor = os.open(path, flags)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
PY
}
fsync_matrix_metadata "$restore_journal"

image_override=".run.conf/recovery-images.${restore_stamp}.yaml"
printf '%s\n' 'services:' > "$image_override"
while IFS=$'\t' read -r service image_ref image_id; do
  recovery_ref="localhost/matrix-recovery-${restore_stamp}-${service}:locked"
  printf '  %s:\n    image: %s\n    pull_policy: never\n    build: null\n' \
    "$service" "$recovery_ref" >> "$image_override"
done < "$point/image-map.tsv"
network_override=".run.conf/recovery-networks.${restore_stamp}.json"
network_inventory=".run.conf/recovery-networks.${restore_stamp}.tsv"
python3 - "$point/network-evidence.tsv" matrix "$restore_stamp" \
  "$network_override" "$network_inventory" frontend backend <<'PY'
import ipaddress
import json
import os
import re
import subprocess
import sys

evidence, app, stamp, override, inventory, *expected = sys.argv[1:]
rows = [line.split('\t') for line in
        open(evidence, encoding='utf-8').read().splitlines()]
if len(rows) != len(expected) or any(len(row) != 5 for row in rows):
    raise SystemExit('external-network evidence closure differs')
if [row[0] for row in rows] != expected or len(set(expected)) != len(expected):
    raise SystemExit('external-network keys differ')
owner = f'{app}-{stamp}'
for path in (override, inventory):
    if os.path.lexists(path):
        raise SystemExit(f'recovery network artifact already exists: {path!r}')
definitions = {}
created = []
for key, source_name, driver, subnet_text, gateway_text in rows:
    if source_name != key or driver != 'bridge' \
            or not re.fullmatch(r'[a-z0-9][a-z0-9_.-]*', key):
        raise SystemExit(f'unsupported external-network evidence: {key!r}')
    subnet = ipaddress.ip_network(subnet_text, strict=True)
    gateway = ipaddress.ip_address(gateway_text)
    if gateway.version != subnet.version or gateway not in subnet:
        raise SystemExit(f'invalid external-network IPAM: {key!r}')
    name = f'{app}-recovery-{stamp}-{key}'
    if subprocess.run(['docker', 'network', 'inspect', name],
                      stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL).returncode == 0:
        raise SystemExit(f'recovery network already exists: {name!r}')
    network_id = subprocess.check_output([
        'docker', 'network', 'create', '--driver', 'bridge',
        '--subnet', str(subnet), '--gateway', str(gateway),
        '--label', f'io.it-saervices.recovery-owner={owner}', name,
    ], text=True).strip()
    if not re.fullmatch(r'[0-9a-f]{64}', network_id):
        raise SystemExit(f'invalid created network ID: {network_id!r}')
    result = json.loads(subprocess.check_output(
        ['docker', 'network', 'inspect', network_id], text=True))
    if len(result) != 1:
        raise SystemExit('created network identity is ambiguous')
    item = result[0]
    config = item.get('IPAM', {}).get('Config', [])
    if item.get('Id') != network_id or item.get('Name') != name \
            or item.get('Driver') != 'bridge' or item.get('Scope') != 'local' \
            or any(item.get(field) for field in
                   ('Internal', 'Attachable', 'Ingress', 'ConfigOnly',
                    'EnableIPv6')) \
            or item.get('Options') not in ({}, None) or len(config) != 1 \
            or config[0].get('Subnet') != str(subnet) \
            or config[0].get('Gateway') != str(gateway) \
            or item.get('Labels') != {
                'io.it-saervices.recovery-owner': owner}:
        raise SystemExit(f'created network differs from evidence: {name!r}')
    definitions[key] = {'name': name, 'external': True}
    created.append((key, name, network_id, str(subnet), str(gateway)))
for path, payload in (
    (override, json.dumps({'networks': definitions}, sort_keys=True) + '\n'),
    (inventory, ''.join('\t'.join(row) + '\n' for row in created)),
):
    temporary = path + '.partial'
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(descriptor, payload.encode())
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    os.rename(temporary, path)
    directory = os.open(os.path.dirname(path), os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory)
    finally:
        os.close(directory)
PY
RECOVERY_COMPOSE=("${runtime_compose[@]}" -f "$image_override" \
  -f "$network_override")
RECOVERY_RESTORE=("${RECOVERY_COMPOSE[@]}" \
  -f docker-compose.matrix-postgres_maintenance.restore.yaml.example)
"${RECOVERY_RESTORE[@]}" config --quiet
keep_isolated_stopped() {
  trap - ERR INT TERM
  set +e
  "${RECOVERY_COMPOSE[@]}" down
  exit 1
}
trap keep_isolated_stopped ERR INT TERM

printf '%s\n' 'state=image-load-starting' >> "$restore_journal"
fsync_matrix_metadata "$restore_journal" "$image_override" \
  "$network_override" "$network_inventory"
docker image load --input "$point/images.tar"
while IFS=$'\t' read -r service image_ref image_id; do
  recovery_ref="localhost/matrix-recovery-${restore_stamp}-${service}:locked"
  docker image tag "$image_id" "$recovery_ref"
  test "$(docker image inspect -f '{{.Id}}' "$recovery_ref")" = "$image_id"
done < "$point/image-map.tsv"
printf '%s\n' 'state=images-aliased' >> "$restore_journal"
fsync_matrix_metadata "$restore_journal"

full_id="$(<"$point/full-bundle-id")"
[[ "$full_id" =~ ^[0-9]{8}_[0-9]{1,9}$ ]]
full_day="${full_id%%_*}"
test ! -e restore && test ! -L restore
install -d -o "$maintenance_uid" -g "$maintenance_gid" -m 0700 restore
for item in "full_${full_id}.tar.zst" \
    "full_${full_id}.tar.zst.sha256" "bundle_full_${full_id}.sha256" \
    "full_${full_id}.manifest"; do
  test -f "backup/$full_day/$item" && test ! -L "backup/$full_day/$item"
  install -o "$maintenance_uid" -g "$maintenance_gid" -m 0600 \
    "backup/$full_day/$item" restore/
done
(cd "backup/$full_day" && sha256sum -c "full_${full_id}.tar.zst.sha256")
(cd "backup/$full_day" && sha256sum -c "bundle_full_${full_id}.sha256")
fsync_matrix_metadata restore/* restore
exec 7<"restore/full_${full_id}.tar.zst"
exec 8<backup
setpriv --reuid "$maintenance_uid" --regid "$maintenance_gid" \
  --clear-groups sh -ec \
  'test -r /proc/self/fd/7; probe=/proc/self/fd/8/.recovery-write-test; (umask 077; : > "$probe"); test -f "$probe"; rm -f -- "$probe"'
exec 7<&-
exec 8<&-

"${RECOVERY_COMPOSE[@]}" up -d --no-build --pull never --wait \
  --wait-timeout 180 matrix-postgres
"${RECOVERY_COMPOSE[@]}" stop matrix-postgres
"${RECOVERY_COMPOSE[@]}" run --rm --no-deps --pull never \
  -e POSTGRES_RESTORE_BACKUP_ID="$full_id" \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
  matrix-postgres_maintenance restore --dry-run
printf '%s\n' 'state=database-restore-starting' >> "$restore_journal"
fsync_matrix_metadata "$restore_journal"
"${RECOVERY_RESTORE[@]}" run --rm --no-deps --pull never \
  -e POSTGRES_RESTORE_BACKUP_ID="$full_id" \
  -e POSTGRES_RESTORE_CONFIRM_DATABASE_STOPPED=true \
  matrix-postgres_maintenance restore

"${RECOVERY_COMPOSE[@]}" up -d --no-build --pull never --wait \
  --wait-timeout 180 matrix-postgres
"${RECOVERY_COMPOSE[@]}" exec -T matrix-postgres \
  psql -v ON_ERROR_STOP=1 -U synapse -d synapse <<'SQL'
BEGIN;
TRUNCATE TABLE e2e_one_time_keys_json;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM e2e_one_time_keys_json) THEN
    RAISE EXCEPTION 'e2e_one_time_keys_json is not empty';
  END IF;
END
$$;
COMMIT;
SQL
services_output="$("${RECOVERY_COMPOSE[@]}" config --services)"
mapfile -t all_services <<< "$services_output"
declare -a application_services=()
for service in "${all_services[@]}"; do
  [[ "$service" == matrix-postgres_maintenance ]] \
    || application_services+=("$service")
done
test "${#application_services[@]}" -gt 0
"${RECOVERY_COMPOSE[@]}" up -d --no-build --pull never --wait \
  --wait-timeout 300 "${application_services[@]}"
"${RECOVERY_COMPOSE[@]}" up -d --no-build --pull never \
  matrix-postgres_maintenance
"${RECOVERY_COMPOSE[@]}" exec -T matrix-postgres_maintenance \
  /usr/local/bin/backup.sh full
"${RECOVERY_COMPOSE[@]}" up -d --no-build --pull never --wait \
  --wait-timeout 300 matrix-postgres_maintenance
python3 - "$network_inventory" "$clean_json" "$rendered_project_name" <<'PY'
import json
import subprocess
import sys

inventory, compose_path, project = sys.argv[1:]
compose = json.load(open(compose_path, encoding='utf-8'))
for row in open(inventory, encoding='utf-8'):
    key, name, network_id, subnet, gateway = row.rstrip('\n').split('\t')
    result = json.loads(subprocess.check_output(
        ['docker', 'network', 'inspect', network_id], text=True))
    if len(result) != 1 or result[0].get('Name') != name:
        raise SystemExit(f'recovery network identity drift: {name!r}')
    expected = set()
    for service, definition in compose['services'].items():
        networks = definition.get('networks', {})
        if key in networks:
            expected.add(service)
    actual = set()
    containers = result[0].get('Containers') or {}
    for container_id in containers:
        detail = json.loads(subprocess.check_output(
            ['docker', 'inspect', container_id], text=True))
        if len(detail) != 1:
            raise SystemExit('recovery network member identity is ambiguous')
        labels = detail[0].get('Config', {}).get('Labels', {})
        if labels.get('com.docker.compose.project') != project:
            raise SystemExit(f'foreign recovery network member: {container_id!r}')
        service = labels.get('com.docker.compose.service', '')
        if not service or service in actual:
            raise SystemExit(f'duplicate recovery network service: {service!r}')
        actual.add(service)
    if actual != expected:
        raise SystemExit(
            f'recovery network member closure differs for {key!r}: '
            f'{sorted(actual ^ expected)}')
PY
"${RECOVERY_COMPOSE[@]}" ps
printf '%s\n' 'state=complete' >> "$restore_journal"
fsync_matrix_metadata "$restore_journal"
restore_complete="${restore_journal%.journal}.complete"
restore_id="$(stat -Lc '%d:%i' -- "$restore_journal")"
python3 - "$restore_journal" "$restore_complete" <<'PY'
import os
import sys

os.rename(sys.argv[1], sys.argv[2])
directory = os.open(os.path.dirname(sys.argv[2]), os.O_RDONLY | os.O_DIRECTORY)
try:
    os.fsync(directory)
finally:
    os.close(directory)
PY
test ! -e "$restore_journal" && test ! -L "$restore_journal"
test "$(stat -Lc '%d:%i' -- "$restore_complete")" = "$restore_id"
trap - ERR INT TERM
```

The first PostgreSQL stært only initiælizes the otherwise æbsent næmed volume;
it is stopped before the dry-run ænd physicæl restore. Æfter the restore,
PostgreSQL ælone becomes heælthy, then one `ON_ERROR_STOP` trænsæction
truncætes ænd proves `e2e_one_time_keys_json` empty before Synæpse, MÆS, the
scheduler, or Element stært. Æll non-mæintenænce services then become heælthy;
only then does the exæct recovery-æliæs mæintenænce service stært, creæte æ new
full bæckup ænd fresh success mærker, ænd pæss its own æge-gæted heælthcheck.
This prevents æn otherwise vælid off-host recovery point older thæn
`POSTGRES_BACKUP_MAX_AGE_SECONDS` from fæiling on its ærchived stæle mærker.
The Synæpse dump wæs independently creæted with
`--exclude-table-data=e2e_one_time_keys_json`; the full restore still requires
this cleænup.

Before cutover, verify both MÆS dætæbæse provisioning ænd Synæpse, signing-key
identity, room/mediæ counts, uploæd/download, SSO, locæl breæk-glæss, SMTP,
federætion posture, restært persistence, ænd æ reæl video cæll. Never reuse æ
fæiled recovery host or run `run.sh`, `build --pull`, or æ moving imæge
resolution in this pæth.

### Rollbæck

Do not roll æ fæiled isolæted restore bæck in plæce. Stop it, preserve the
journæl for incident evidence, discærd the whole host, ænd rehydræte the prior
complete recovery point on ænother empty host. Cut over only the jointly
verified imæges, dætæbæse, `appdata`, secrets, signing key, ænd `app.env`.
Never point æn old MÆS/Synæpse imæge æt æ newer migræted schemæ; every
Synæpse physicæl or dump recovery still requires the PostgreSQL-only
one-time-key cleænup before æpplicætion stært.

---

## Updætes

First creæte the complete recovery point æbove, reæd Synæpse, MÆS, Element,
LiveKit, ænd PostgreSQL releæse notes, ænd record `docker compose images` plus
the current `app.env`. Dætæbæse migrætions run æutomæticælly ænd require the
mætching dætæbæse rollbæck, not just æn older contæiner imæge.

Run this block from the repository root.

```bash
set -euo pipefail
(
  cd Matrix
  docker compose --env-file .env -f docker-compose.main.yaml down
)
./run.sh Matrix --update
(
  cd Matrix
  docker compose --env-file .env -f docker-compose.main.yaml \
    up -d --no-build --pull never --wait --wait-timeout 300
)
```

`--update` pulls æll registry imæges ænd rebuilds the custom MÆS imæge with
`--pull --no-cache`. Becæuse the project wæs explicitly stopped with `down`, the
runner correctly preserves thæt stopped stæte; the finæl `up` stærts only the
ælreædy resolved ænd built imæges without æ second pull or build. Reæd the
Synæpse ænd MÆS releæse notes before mæjor jumps; dætæbæse migrætions run
æutomæticælly on stært.

Æfter the updæte, execute the complete heælth inventory, prove both discovery
documents, SSO/denied-user/breæk-glæss, room history änd mediæ, SMTP, federætion
posture, ænd one video cæll. Use [Rollbæck](#rollbæck) with the recorded imæges
ænd mætching dætæ/files when æny check fæils.

---

## Security Highlights

- Long-running æpplicætion dæemons ænd the finæl PostgreSQL server process
  run non-root. PostgreSQL uses æ bounded root init phæse to prepære ownership,
  secrets, ænd configurætion before the officiæl entrypoint drops privileges.
  Services use reæd-only roots where compætible, minimized cæpæbilities,
  `no-new-privileges`, bounded tmpfs, resource limits, ænd log rotætion.
- Deployment credentiæls ære supplied æs Docker secrets. Rendered
  configurætions use privæte mode-`0600` tmpfs files; documented bootstræp ænd
  provider flows mæy still consume non-secret configurætion through environment
  væriæbles. Never put secret vælues in Compose environment, commænd ærguments,
  or logs.
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

Run the merged-stæck checks from the repository root:

```bash
cd Matrix
docker compose --env-file .env -f docker-compose.main.yaml ps
docker compose --env-file .env -f docker-compose.main.yaml exec -T app wget -q -O - http://127.0.0.1:8080/config.json
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 app
```

Æfter DNS ænd Træefik ære live, run the public checks from æny
directory with network æccess to the deployment:

```bash
curl -fsS https://example.com/.well-known/matrix/client
curl -fsS https://example.com/.well-known/matrix/server
curl -fsS https://matrix.example.com/_matrix/client/versions
curl -fsS https://auth.example.com/.well-known/openid-configuration | head
curl -fsS https://element.example.com/config.json
curl -fsS https://call.example.com/config.json
```

Then open `https://element.example.com`, sign in — the browser is redirected to MÆS ænd from there to Æuthentik — ænd stært æ video cæll in æ room to verify the MætrixRTC pæth end-to-end.
