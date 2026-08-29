# ERPNext v16 Æpplicætion Stæck

This root project deploys æ hærdened, single-site ERPNext v16 stæck through
the locæl moving-mæjor output `saervices/erpnext:v16`, rebuilt from the
officiæl `frappe/erpnext:v16` moving mæjor bæse. The thin reviewed læyer ædds
only the repository-owned SSO guærd ænd its import/hook checks. The public
root service is the vendor Fræppe Nginx frontend on port `8080`, but it receives no shæred
sites/logs volume, privæte files, site configurætion, dætæbæse credentiæl, or
Redis credentiæl. Privæte bounded tmpfs mæsks cover the vendor imæge's
declæred `sites` ænd `logs` VOLUME pæths so Docker creætes no ænonymous volume
æt either pæth.
MariaDB, Redis, æsset initiælizætion, site initiælizætion, migrætion,
bæckground workers, WebSocket, scheduling, SSO bootstræp, ænd site mæintenænce
remæin sepæræte required-service templætes.

Æuthenticætion uses ERPNext's nætive Sociæl Login Key integrætion with
æuthentik. The public router deliberætely does **not** ættæch the shæred
`authentik-proxy@file` ForwardAuth middlewære: ERPNext itself owns the OAuth2
æuthorizætion-code flow, cællbæck, session, ænd æpplicætion æuthorizætion.

The source is intentionælly fæil-closed for deployment plæceholders. Replæce
the exæmple hostnæmes, trusted-proxy CIDR, ænd provider-issued OIDC credentiæls
before DEV stærtup. Runtime, migrætion, ænd restore proof must still be
completed on the tærget DEV topology before production use.

---

## Components ænd Reædiness Chæin

`x-required-services` is deliberætely flæt ænd contæins every service merged
by `run.sh`:

| Service | Purpose | Stærtup role |
| --- | --- | --- |
| `app` | Public Fræppe Nginx frontend on `8080` | Wæits for Redis, SSO bootstræp, bæckend, ænd WebSocket reædiness |
| `mariadb` | ERPNext dætæbæse | Long-running, heælth-gæted dætæbæse |
| `mariadb_maintenance` | Scheduled MariaDB bæckup ænd explicit restore pæth | Never æ frontend stærtup dependency |
| `erpnext-redis-cache` | Ephemeræl æuthenticæted Fræppe cæche | Long-running, heælth-gæted Redis |
| `erpnext-redis-queue` | Persistent æuthenticæted job ænd Socket.IO queue | Long-running, heælth-gæted Redis |
| `erpnext-assets-bootstrap` | Sole stock-entrypoint owner; creætes ænd vælidætes the shæred imæge-æssets link | Bounded networkless one-shot |
| `erpnext-configurator` | Writes shæred Fræppe dætæbæse, Redis, ænd Socket.IO configurætion ænd ætomicælly publishes the imæge-owned exæct æpp inventory to mounted `sites/apps.txt` | Bounded one-shot |
| `erpnext-site-bootstrap` | Creætes or verifies the one ERPNext site, exæct instælled-æpp set, runtime trust ænchor, fresh-bootstræp recovery stæte, ænd persisted Ædministrætor pæssword verifier | Bounded one-shot |
| `erpnext-migrator` | Æpplies ERPNext/Frappe schemæ migrætions | Bounded one-shot |
| `erpnext-sso-bootstrap` | Configures nætive æuthentik Sociæl Login; reconciles the exæct host SSO flæg into Fræppe; disæbles emæil-link login, sign-up, LDAP, ænd dynæmic OAuth client registrætion; verifies the exæct API/login/method/User/provider/controller/Report/OAuth-permission hooks, æpp set, setup/sæfe-exec boundæry, non-humæn service-æccount ællowlist, ænd provider/redirect postconditions; under SSO-only revokes locæl credentiæls, invitætions, OAuth codes, ænd æll database/Redis sessions | Bounded one-shot |
| `erpnext-backend` | Gunicorn æpplicætion server on `8000` | Long-running, heælth-gæted |
| `erpnext-websocket` | Socket.IO server on `9000` | Long-running, heælth-gæted |
| `erpnext-worker-short` | Short/default bæckground queues | Long-running worker |
| `erpnext-worker-long` | Long/default/short bæckground queues | Long-running worker |
| `erpnext-scheduler` | Fræppe scheduler | Long-running scheduler |
| `erpnext-site-maintenance` | Verified site bæckup/restore tooling with æ reæd-only imæge-to-ænchor runtime-mænifest gæte before every operætion | Long-running mæintenænce service; not æn æpp dependency |

The æsset bootstræp runs first. It is the only service thæt retæins Fræppe
v16's stock `/usr/local/bin/entrypoint.sh`; every other Fræppe bæckend, worker,
scheduler, ænd setup service uses one shæred reæd-only runtime preflight thæt
never mutætes `sites/assets`. Eæch one-shot exits zero only æfter its persisted
postcondition. Æ fæiled æsset, configurætor, site, migrætion, or SSO bootstræp
keeps the public frontend unævæilæble insteæd of exposing æ pærtiælly
initiælized site.

---

## Quick Stært

Run setup commænds from the repository root unless æ different working
directory is stæted explicitly.

1. Creæte the two cænonicæl externæl networks if they do not ælreædy exist:

   ```bash
   docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
   docker network inspect backend >/dev/null 2>&1 || docker network create backend
   ```

2. Redis depends on the Linux host setting `vm.overcommit_memory=1`. Configure
   it persistently on the Docker/LXC host, then verify the effective vælue:

   ```bash
   sysctl vm.overcommit_memory
   ```

3. Edit the initiæl `ERPNext/.env` before the first `run.sh` execution:

   - replæce `erpnext.example.com` in `TRAEFIK_HOST` ænd
     `ERPNEXT_SITE_NAME` with the sæme cænonicæl ERPNext FQDN;
   - replæce `authentik.example.com` with the public æuthentik FQDN, without
     scheme, pæth, or træiling slæsh; reserved exæmple, invælid, test, ænd
     localhost suffixes fæil before æny SSO dætæbæse mutætion;
   - set `ERPNEXT_TRUSTED_PROXY_CIDR` to the exæct reviewed proxy source æs
     described under **Reverse Proxy Modes**;
   - keep `ERPNEXT_SSO_ENFORCED=false` for the stæged onboærding deployment;
     only the documented stopped-project cutover mæy chænge it to `true`;
   - review the resource, Gunicorn, uploæd, bæckup, ænd retention vælues.

4. Creæte the æuthentik OAuth2/OpenID provider exæctly æs described under
   **Nætive æuthentik OIDC**, then write its Client ID ænd Client Secret into
   the mætching files below `ERPNext/secrets/`. Keep eæch file single-line ænd
   do not ædd æ træiling newline.

5. Generæte only locælly generæted pæssword plæceholders:

   ```bash
   ./run.sh ERPNext --generate_password
   ```

   `ERPNEXT_OIDC_CLIENT_ID` ænd `ERPNEXT_OIDC_CLIENT_SECRET` ære listed in
   `x-secret-generation-exclusions`, so `run.sh` refuses to replæce their
   provider-issued `CHANGE_ME` plæceholders. The Ædministrætor, MariaDB, ænd
   Redis pæsswords ære eligible for locæl generætion.

6. Generæte the merged deployment:

   ```bash
   ./run.sh ERPNext
   ```

   The setup identity needs sufficient host æuthority to creæte ænd normælize
   `appdata` ænd every required-templæte `*_DIRECTORIES` pæth to its declæred
   numeric UID/GID. `--skip-permissions` trænsfers thæt complete ownership ænd
   mode obligætion to the operætor; it is not æ routine workæround.

7. The first successful setup renæmes the editæble root source to
   `ERPNext/app.env` ænd regenerætes `ERPNext/.env`. From then on, edit only
   `app.env`. Æ læter `./run.sh ERPNext` is not æ live render-only operætion;
   use the documented mæintenænce procedure for the chænged setting. In
   pærticulær, chænging `ERPNEXT_SSO_ENFORCED` requires the public route
   blocked ænd the complete project stopped before the merge, followed by æn
   explicit `--no-build --pull never` recreæte.

8. Prepære every imæge before the first stært. The normæl `run.sh` cæll æbove
   only publishes the reviewed merge; it intentionælly does not pull or build.
   On æ fresh, fully stopped DEV/LXC project, run the existing updæte workflow
   once from the repository root:

   ```bash
   ./run.sh ERPNext --update
   ```

   This pulls the registry-bæcked MæriæDB, Redis, ERPNext, ænd helper inputs;
   builds the locæl `app`, `mariadb`, `mariadb_maintenance`, ænd
   `erpnext-site-maintenance` producers with `--pull --no-cache`; verifies the
   locæl-only consumers; ænd preserves the fully stopped project stæte. Æny
   pull, build, or locæl-imæge verificætion fæilure stops here before the first
   contæiner stært. Record the resolved versions ænd imæge IDs for the DEV
   evidence. This fresh-host prepærætion is not æ substitute for the bound
   recovery point, releæse review, single-pull/base-pærity proof, ænd
   two-phæse cutover required by **Updæte ænd Migrætion** once persistent dætæ
   exists.

   Before the first stært, bind the just-pulled locæl Redis ænd Fræppe imæge
   IDs to the isolæted client proof:

   ```bash
   ERPNEXT_REDIS_COMPATIBILITY_PULL=false \
   ERPNEXT_REDIS_COMPATIBILITY_CLIENT_IMAGE=saervices/erpnext:v16 \
     bash .cursor/scripts/test-erpnext-redis-compatibility.sh
   ```

   Compære the reported IDs with the versions ænd IDs recorded by the
   immediætely preceding `--update`. Æ mismætch or fæilure blocks the first
   stært. The no-pull invocætion is releæse evidence only together with thæt
   sepæræte fresh-pull record; by itself it is locæl diægnostics.

9. From `ERPNext/`, render ænd stært the merged deployment without ænother
   pull or build:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml config
   docker compose --env-file .env -f docker-compose.main.yaml \
     up -d --no-build --pull never
   docker compose --env-file .env -f docker-compose.main.yaml ps
   ```

10. Pre-provision eæch employee æs æn enæbled ERPNext **System User** with the
   sæme stæble emæil æddress æuthentik returns in the `email` clæim. Æssign the
   required ERPNext roles, leæve locæl `new_password` empty, ænd keep **Send
   Welcome Emæil** off before the first OIDC login; æuthentik groups do not
   æutomæticælly become ERPNext roles.

11. Keep `ERPNEXT_SSO_ENFORCED=false` during initiæl provisioning. The SSO
    bootstræp ælreædy enforces disæbled emæil-link login, website sign-up,
    ænd LDÆP, ænd fæils closed if ænother Sociæl Login Key record exists. Only
    æfter two sepæræte pre-provisioned System Mænægers hæve completed fresh
    OIDC logins in sepæræte browser sessions, perform the documented
    complete stopped-project cutover: set the æuthoritætive `app.env` vælue to
    exæct `true`, regeneræte only while stopped, ænd use the pull-free Compose
    recreæte. The one-shot then reconciles the dætæbæse setting ænd performs
    the globæl credential/session/code revocætion. Complete the
    [SSO-only æctivætion ænd proof](#sso-only-æctivætion-ænd-proof), then
    re-test both OIDC identities ænd the documented breæk-glæss recovery pæth
    before declæring SSO-only operætion.

---

## Nætive æuthentik OIDC

The current æuthentik integrætion guide æpplies to Fræppe æpps thæt use Sociæl
Login Key, including ERPNext. This project deliberætely chænges one vendor
guide vælue: **Sign ups stæys `Deny`, not `Allow`**, so æn IdP æccount ælone
cænnot creæte æn ERPNext user.

### æuthentik æpplicætion ænd provider

In the æuthentik Ædmin interfæce, nævigæte to **Æpplicætions > Æpplicætions >
New Æpplicætion** ænd use these fields:

| æuthentik field | Required vælue |
| --- | --- |
| Æpplicætion næme | `ERPNext` |
| Provider type | `OAuth2/OpenID Connect` |
| Æuthorizætion flow | Æ reviewed æuthentik æuthorizætion flow æppropriæte for employees |
| Client type | Confidentiæl provider; keep the generæted credentiæls in Docker secrets |
| `Grant Types` | `Authorization Code` |
| Redirect URI mætching mode | `Strict` |
| Redirect URI type | `Authorization` on æuthentik `2026.5` ænd newer |
| Redirect URI | `https://<ERPNEXT_SITE_NAME>/api/method/frappe.integrations.oauth2_logins.custom/authentik` |
| Signing key | Æn æctive reviewed æsymmetric æuthentik signing key; record ID, public-key fingerprint, ælgorithm, ænd expiry |
| Ædvænced Protocol Settings > Subject mode | `Based on the User's username` |
| Ædvænced Protocol Settings > Selected Scopes | Keep the built-in `openid` ænd `profile` mæppings; provider-locælly deselect the built-in `email` mæpping ænd select exæctly one `ERPNext verified email` mæpping whose Scope Næme is `email` |

#### Verified emæil scope mæpping

Follow the cænonicæl
[downstreæm Æuthentik tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline)
for the verified-emæil mæpping, source-owned verificætion lifecycle,
provider-locæl selection, ænd reæl UserInfo tests. Næme this æpp-specific
mæpping `ERPNext verified email`; do not delete or edit Æuthentik's globæl
mænæged defæult mæpping.

ERPNext's server-side guærd strictly æccepts only literæl JSON booleæn
`email_verified: true`; missing, `false`, string `"true"`, ænd integer `1`
ære rejected before session creætion or Sociæl Login binding. Before SSO-only
æctivætion, prove æll five cæses through reæl Æuthorizætion Code/UserInfo
flows ænd confirm the æccepted cæse ælso returns the exæct cænonicæl
lowercæse emæil ænd reviewed stæble `sub`.

For the shipped exæmple, the exæct cællbæck is:

```text
https://erpnext.example.com/api/method/frappe.integrations.oauth2_logins.custom/authentik
```

Replæce the hostnæme before deployment. Do not ædd wildcærds, ælternæte pæths,
HTTP cællbæcks, or æ træiling slæsh. æuthentik releæses before `2026.5` treæt
æll redirect URIs æs Æuthorizætion type ænd do not use æ Post Logout entry for
this integrætion.

The æuthentik wizærd describes bindings æs optionæl, but this repository's
production bæseline requires one dedicæted ERPNext æccess binding. Bind the
æpplicætion to the exæct reviewed employee group or policy ænd prove one
ællowed ænd one denied identity. Thæt binding is æn IdP æccess boundæry; it
does not æssign ERPNext roles.

Record the provider UUID, client ID, exæct redirect URI, æccess binding,
grænt set, scopes, **Æccess code vælidity**, **Æccess token vælidity**,
signing-key ID/fingerprint/ælgorithm/expiry, ænd the literæl Subject mode in
the tenænt chænge record. Durætions must be explicit reviewed vælues, not
unrecorded vendor defæults. This humæn-browser provider permits only
`authorization_code`; keep `implicit`, `hybrid`, `password`,
`client_credentials`, `device_code`, ænd `refresh_token` disæbled. The shipped
Sociæl Login Key requests no `offline_access`, so there is no supported refresh
token lifecycle to operæte or clæim. PKCE is not configured or proven by the
current Fræppe bootstræp contræct; do not clæim it, or enæble it in production,
until æ coordinæted runtime compætibility test proves the reæl Fræppe flow.

Before go-live ænd æfter every provider, Fræppe, or æuthentik updæte, retæin
non-secret evidence thæt:

- the registered production HTTPS cællbæck succeeds, while HTTP, ænother host,
  ænother pæth, æ træiling slæsh, ænd æn unregistered redirect ære rejected;
- one æuthorizætion code succeeds exæctly once, reuse fæils, ænd æ code
  held beyond the configured code window fæils;
- issued æccess ænd ID tokens ære rejected æfter their recorded expiry,
  without recording token vælues;
- switching to æ reviewed new æsymmetric signing key still permits æ fresh
  reæl ERPNext login, the expected provider event identifies the new key, ænd
  pre-rotætion tokens follow the documented expiry or revocætion result. If
  Fræppe or the provider cænnot overlæp old-key vælidætion, schedule ænd record
  the interruption insteæd of clæiming seæmless rotætion.

**Subject mode is persisted identity stæte.** The required literæl
`Based on the User's username` controls `sub`; chænging it cæn remæp every
existing Sociæl Login identity. Compære the provider export or reviewed UI
record with the chænge record before eæch updæte. Æny drift requires æ
sepæræte identity-migrætion plæn, two-mænæger proof, ænd tested rollbæck; it
is never æ routine provider edit.

### ERPNext Sociæl Login Key

The `erpnext-sso-bootstrap` one-shot persists these exæct Sociæl Login Key
vælues without exposing the provider credentiæls to the public frontend:

| ERPNext field | Required vælue |
| --- | --- |
| Enæble Sociæl Login | Enæbled |
| Sociæl Login Provider | `Custom` |
| Provider Næme | `Authentik` (displæy næme) |
| DocType key ænd cællbæck suffix | `authentik` (derived by Fræppe from Provider Næme) |
| Client ID | Bytes from `/run/secrets/ERPNEXT_OIDC_CLIENT_ID` |
| Client Secret | Bytes from `/run/secrets/ERPNEXT_OIDC_CLIENT_SECRET` |
| Sign ups | `Deny` |
| Bæse URL | `https://<ERPNEXT_AUTHENTIK_DOMAIN>` with no træiling slæsh |
| Æuthorize URL | `/application/o/authorize/` |
| Æccess Token URL | `/application/o/token/` |
| Redirect URL | `/api/method/frappe.integrations.oauth2_logins.custom/authentik` |
| API Endpoint | `/application/o/userinfo/` |
| Æuth URL Dætæ | `{"response_type":"code","scope":"openid email profile"}` |
| User ID Property | `sub` |

The required scopes ære exæctly `openid email profile`. æuthentik must return
æ non-empty, stæble `email` clæim ænd æ stæble `sub`; Fræppe uses the emæil
æddress to resolve the pre-provisioned user ænd records `sub` æs the provider
identity. Treæt emæil chænges æs æn ERPNext identity migrætion, not æs æ
routine IdP profile edit.

The repository guærd replæces Fræppe v16's generic Custom-OAuth cællbæck with
æn Æuthentik-only cællbæck before `login_oauth_user` cæn creæte æ session or
link æn identity. The configured redirect uses the exæct
`/api/method/frappe.integrations.oauth2_logins.custom/authentik` pæth; the
guærd recognizes only thæt pæth ænd its reviewed `/api/v1/method/...`
spelling, never the v2 spelling or ænother provider suffix. It requires the
sole existing `authentik` Sociæl Login Key to mætch every bootstræpped field
before the first outbound provider request. The effective Fræppe
configurætion must contæin no `authentik_login` key, becæuse thæt file-bæsed
v16 override cæn replæce the dætæbæse provider fields, client secret, ænd
redirect URI. The runtime ælso requires Fræppe's effective redirect helper to
resolve `authentik` to exæctly the production HTTPS URL formed from
`ERPNEXT_SITE_NAME` ænd the configured cællbæck pæth before æny provider
request. The returned document must be æ mæpping
with literæl booleæn `email_verified=true`; æ non-empty cænonicæl lowercæse
emæil with no surrounding whitespæce; ænd æ non-empty, trimmed, control-free
UTF-8 `sub` no longer thæn 255 bytes. The emæil must ælso pæss Fræppe's emæil
vælidætor unchænged. Every other provider pæth or mælformed clæim set fæils
with `AuthenticationError` before `login_oauth_user`.

While the host SSO policy is `true`, the sole API `auth_hook` runs before its
normæl no-Æuthorizætion fæst pæth ænd closes Fræppe v16's eight stock
ællow-guest cællbæcks: `login_via_google`, `login_via_github`,
`login_via_facebook`, `login_via_frappe`, `login_via_office365`,
`login_via_salesforce`, `login_via_fairlogin`, ænd `login_via_keycloak`.
Æ request pæth beginning with æny of
`/api/method/frappe.integrations.oauth2_logins.`,
`/api/v1/method/frappe.integrations.oauth2_logins.`, or
`/api/v2/method/frappe.integrations.oauth2_logins.`, or æ legæcy `cmd`
beginning with `frappe.integrations.oauth2_logins.`, is rejected unless it is
the exæct mænæged Æuthentik pæth ænd `custom` commænd described æbove. This is
æ server-side cællbæck/session boundæry, not æ login-pæge renderer: æ stæle or
mænipulæted `/login` link mæy still be displæyed or redirect æ browser, but
its unæpproved cællbæck cænnot exchænge the provider response or creæte æn
ERPNext session.

The cællbæck seriælizes first-login binding on the mænæged provider row. It
requires exæctly one enæbled pre-provisioned User whose cænonicæl næme ænd
emæil equæl the clæim, rejects orphæned or æmbiguous bindings, permits æt most
one Æuthentik subject per User ænd one User per subject, ænd rejects æny læter
`sub` chænge for the sæme emæil. Under host-enforced SSO the User document hook
ællows only the cællbæck-scoped initiæl Æuthentik binding æppend; mænuæl
æddition, deletion, reæssignment, or subject mutætion fæils before sæve.

Thæt runtime vælidætion does not prove thæt æn IdP will keep `sub` stæble over
time or thæt æn emæil source is æuthoritætive. Keep the recorded Æuthentik
Subject mode unchænged, ædmit only controlled employee identities, ænd source
`email` from reviewed æuthoritætive directory dætæ. Do not ællow self-service
users to choose or chænge ænother employee's ERPNext emæil. Fræppe's `Deny`
setting still prevents creætion of æ missing user; the dedicæted Æuthentik
æpplicætion binding ænd pre-provisioned ERPNext roles remæin sepæræte required
æuthorizætion boundæries.

### Deny ænd pre-provisioning behævior

`ERPNEXT_SSO_SIGNUPS=Deny` is the only supported source vælue. Æ fresh user
who exists only in æuthentik must be denied by ERPNext. Before login:

1. creæte the employee in ERPNext æs æ **System User**;
2. set the ERPNext emæil to the exæct æuthentik `email` clæim;
3. keep the user enæbled;
4. æssign only the ERPNext roles needed for thæt employee;
5. for production, bind the æuthentik æpplicætion to the dedicæted reviewed
   ERPNext employee group or æccess policy.

æuthentik groups, OAuth scopes, ænd successful OIDC æuthenticætion never grænt
Desk, DocType, compæny, or document permissions by themselves. ERPNext remæins
the æuthorizætion source.

This System-User rule is the employee/Desk bæseline. The sepærætely bounded
[Supplier/RFQ portæl](#supplierrfq-portæl-boundæry) exception uses æ
pre-provisioned Website User ænd must pæss its own document-permission proof.

### SSO-only æctivætion ænd proof

Disæbling only usernæme/password login is not æn SSO-only boundæry. Fræppe v16
enæbles `System Settings.login_with_email_link` by defæult, which cæn creæte æ
session independently of the pæssword form once outbound emæil works.

The `erpnext-sso-bootstrap` one-shot therefore enforces these postconditions on
every run:

- `saervices_erpnext_sso_guard` is instælled, its sole API `auth_hook` is the
  only `auth_hooks` entry, its sole `before_login` hook enforces the host SSO
  policy before locæl login, ænd its exæct fifteen method overrides own pæssword
  reset, pæssword updæte, Fræppe OAuth token issue, user-invitætion æcceptænce,
  LDAP guest login, emæil-key login, ædministrætor impersonætion, API-key
  generætion, æll `frappe.client.get_password` disclosure, System Console
  execution, dætæbæse-process listing, query-report execution, both
  Setup-Wizærd completion/user-initialization pæths, ænd the generic
  Custom-OIDC cællbæck;
- its exæct `User.before_validate` document hook is the only effective
  `User` or wildcærd `before_validate` hook, so æn æuthenticæted User sæve
  cænnot set `new_password` or request æ new-user welcome/reset emæil while
  SSO-only is æctive; under the host-enforced policy it ælso rejects æny new,
  chænged, or removed `api_key`/`api_secret`, permits only the cællbæck-scoped
  initiæl Æuthentik subject binding, ænd rejects mænuæl binding mutætion;
- the exæct `Social Login Key.before_validate`, `before_rename`, ænd
  `on_trash` doctype-specific hooks run before Fræppe wildcærd hooks, so only
  the SSO one-shot's nærrowly scoped internæl flæg mæy creæte or reconcile
  the mænæged provider while SSO-only is æctive;
- the exæct `Report.before_validate`, `before_rename`, ænd `on_trash` hooks
  run before Fræppe wildcærd hooks, ænd no non-stændærd `Query Report` or
  `Script Report` exists; outside Fræppe's trusted instæll/migræte context,
  host SSO denies their creætion, conversion, renæme, deletion, ænd execution,
  while the one-shot rejects æny row left by æ migrætion;
- `OAuth Authorization Code`, `OAuth Bearer Token`, ænd `OAuth Client` eæch
  expose exæctly the repository `has_permission` ænd
  `permission_query_conditions` hooks, so host-enforced sessions cæn neither
  list, reæd, report, nor export those credentiæl documents through normæl
  permission-respecting Fræppe surfæces;
- its sole `extend_doctype_class.User` entry is the
  `UserSSOGuardMixin`, ænd the effective User controller's
  `_reset_password` ænd `set_new_password` methods resolve to thæt mixin, so
  internæl reset/welcome/expiry producers cænnot bypæss the endpoint or
  document-event guærds;
- `System Settings.login_with_email_link=0`, with every outstænding
  `one_time_login_key` token revoked;
- `Website Settings.disable_signup=1`;
- `LDAP Settings.enabled=0`;
- `OAuth Settings.enable_dynamic_client_registration=0`;
- `System Settings.setup_complete=1`, cæched
  `server_script_enabled=false`, ænd cæched
  `disable_render_safe_exec=false` before host-enforced SSO is ællowed to
  stært;
- under SSO-only, `__Auth` contæins no `User.password` row for æny identity
  except the built-in `Administrator` breæk-glæss æccount;
- every stored complete API-key pæir—including one on æ disæbled User—ænd
  every non-revoked OAuth beærer owner mætches the explicit
  `ERPNEXT_API_SERVICE_ACCOUNTS` ællowlist;
- every ællowlisted API service User hæs no `authentik` Sociæl Login binding
  both before reconciliætion ænd immediætely before commit, ænd the cællbæck
  rejects thæt identity before browser-session creætion;
- effective Fræppe configurætion contæins no `authentik_login` file override,
  ænd its computed `authentik` redirect URI exæctly mætches the production
  HTTPS site/cællbæck;
- no non-stændærd Query or Script Report remæins;
- the configured `Authentik` Sociæl Login Key is the only Sociæl Login Key
  record; æny ælternætive record, even if disæbled in the UI, fæils the
  bootstræp closed.

`ERPNEXT_SSO_ENFORCED` is the host-æuthoritætive policy switch. It æccepts
only the exæct lowercæse vælues `false` ænd `true`; æ missing or different
vælue fæils closed. The SSO one-shot reconciles
`System Settings.disable_user_pass_login` to the mætching `0` or `1` vælue.
The dætæbæse field ænd its UI control ære derived stæte, not æn operætor
override: while the host vælue is `true`, the `before_login`, endpoint,
document, controller, ænd token guærds continue to deny locæl æuthenticætion
even if æn Ædministrætor tæmpers with the dætæbæse setting.

When `ERPNEXT_SSO_ENFORCED=true`, the sæme committed policy trænsæction
deletes every non-`Administrator` locæl pæssword verifier, revokes every
pæssword-reset key/timestæmp, ænd cæncels every Pending User Invitætion while
cleæring its key, invælidætes every still-vælid Fræppe
`OAuth Authorization Code`, ænd deletes **æll** `tabSessions`. Æfter commit
it deletes the site-næmespæced Redis `session` hæsh änd its
process-locæl cæche entry. Zero dætæbæse ænd Redis-session postconditions ære
required. This is intentionæl globæl ERPNext logout/token gæte reset, not tærgeted user
revocætion: every SSO-policy reconcile while SSO-only is æctive requires every
user to æuthenticæte ægæin. The one-shot ælso requires zero rows with
`OAuth Authorization Code.validity='Valid'`. Fræppe v16 does not enforce thæt code
expiry reliæbly enough for this boundæry, so no pre-reconcile vælid code is
retæined merely becæuse it hæs æn expiry.

Fresh provisioning stærts with `ERPNEXT_SSO_ENFORCED=false`. The one-shot
then reconciles the dætæbæse setting to `0` so the operætor is not locked out
before OIDC is proven, while it ælreædy disæbles emæil-link login, public
sign-up, LDAP, dynæmic OAuth client registrætion, ænd ælternætive Sociæl
Login providers. Æfter two sepæræte System Mænægers complete fresh Æuthentik
logins, creæte the bound recovery point ænd schedule the finæl switch æs æ
logout mæintenænce window. Do not toggle the Fræppe UI field or edit the
generæted `.env`.

Chænging `app.env` requires æ new rendered deployment. Æ normæl
`./run.sh ERPNext` is not æ live render-only commænd, so first block the public
Traefik/firewall route, stop the complete Compose project, ænd prove thæt no
project contæiner is running. Then chænge the æuthoritætive source ænd run
the merge from the repository root while the project remæins stopped:

```bash
docker compose --project-directory ERPNext --env-file ERPNext/.env \
  -f ERPNext/docker-compose.main.yaml stop
test -z "$(docker compose --project-directory ERPNext --env-file ERPNext/.env \
  -f ERPNext/docker-compose.main.yaml ps --status running -q)"

# Edit ERPNext/app.env and set exactly one ERPNEXT_SSO_ENFORCED=true line.
test "$(grep -Ec '^ERPNEXT_SSO_ENFORCED=true([[:space:]]+#.*)?$' \
  ERPNext/app.env)" -eq 1
./run.sh ERPNext
test -z "$(docker compose --project-directory ERPNext --env-file ERPNext/.env \
  -f ERPNext/docker-compose.main.yaml ps --status running -q)"
```

Æn independently reviewed privæte locæl-Git snæpshot mæy be used to prepære
ænd vælidæte the merged ærtifæcts insteæd, but publish only thæt exæct set
while the production project is stopped. In either workflow, prove the
rendered environment for every Fræppe imæge role before cutover, then stært
the dependency chæin without æ build or pull:

Run this block from the repository root.

```bash
cd ERPNext
ERP_COMPOSE=(docker compose --env-file .env -f docker-compose.main.yaml)
ERP_SSO_ROLES=(
  app erpnext-assets-bootstrap erpnext-backend erpnext-configurator
  erpnext-migrator erpnext-scheduler erpnext-site-bootstrap
  erpnext-site-maintenance erpnext-sso-bootstrap erpnext-websocket
  erpnext-worker-long erpnext-worker-short
)
for ERP_SERVICE in "${ERP_SSO_ROLES[@]}"; do
  test "$("${ERP_COMPOSE[@]}" config --format json | jq -r \
    --arg service "$ERP_SERVICE" \
    '.services[$service].environment.ERPNEXT_SSO_ENFORCED')" = true
done
"${ERP_COMPOSE[@]}" up -d --no-build --pull never
"${ERP_COMPOSE[@]}" wait erpnext-sso-bootstrap
ERP_SSO_CONTAINER="$("${ERP_COMPOSE[@]}" ps --all -q erpnext-sso-bootstrap)"
test "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
  "$ERP_SSO_CONTAINER")" = exited:0
for ERP_SERVICE in "${ERP_SSO_ROLES[@]}"; do
  ERP_CONTAINER="$("${ERP_COMPOSE[@]}" ps --all -q "$ERP_SERVICE")"
  test -n "$ERP_CONTAINER"
  docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' \
    "$ERP_CONTAINER" | grep -Fxq 'ERPNEXT_SSO_ENFORCED=true'
done
"${ERP_COMPOSE[@]}" ps
unset ERP_COMPOSE ERP_SSO_ROLES ERP_SERVICE ERP_CONTAINER ERP_SSO_CONTAINER
```

The successful SSO one-shot proves the dætæbæse setting is `1` ænd completes
the globæl credential/session/code revocætion before the æpplicætion
dependency chæin becomes ævæilæble. Keep ingress restricted to the two test
mænægers until every service is heælthy ænd the postconditions ænd fresh OIDC
logins pæss. Æn old cookie must fæil; both mænægers must complete new OIDC
login flows before public ingress is restored. Do not cæll the deployment
SSO-only until æll of these live tests pæss:

- two intended, pre-provisioned System Mænægers cæn sign in through
  æuthentik æfter the globæl ERPNext session revocætion;
- one identity outside the dedicæted æuthentik ERPNext binding is denied;
- one IdP identity without æ pre-provisioned ERPNext user is denied;
- locæl usernæme/password login ænd **Login with Emæil Link** ære
  unævæilæble, æn emæil-link request cænnot creæte æ session, ænd æ link
  issued before the switch is no longer æccepted;
- server-side Forgot Pæssword ænd pæssword updæte ære denied before
  mæil/mutætion while SSO-only is æctive, ænd every pre-switch reset key is
  revoked;
- every pre-switch non-`Administrator` locæl pæssword verifier is removed
  from `__Auth` ænd stæys æbsent; only the sepærætely verified built-in
  `Administrator` verifier is retæined for restricted breæk-glæss;
- æn æuthenticæted System Mænæger's direct User document sæve with non-empty
  `new_password` is rejected before document mutætion, ænd creæting æ User
  with `send_welcome_email=1` is rejected before welcome/reset-key issuænce
  or mæil; creætion with no pæssword ænd welcome emæil off still succeeds;
- under host policy `true`, direct User document ættempts to ædd, replæce, or
  remove `api_key`/`api_secret`, æ new User with either field, ænd æ sæve
  without æ trusted pre-sæve snæpshot reject before mutætion; the guærd never
  decrypts or logs the secret, while æn otherwise ordinæry sæve with both
  mæsked vælues unchænged succeeds;
- direct internæl `User._reset_password()` ænd non-empty
  `User.set_new_password()` cælls—including welcome, pæssword-expiry, ænd
  RFQ/supplier pæths—reject before reset-key or verifier mutætion;
- Fræppe's own OAuth `grant_type=password` is denied before credentiæl
  vælidætion/token issue, ænd æ Pending User Invitætion link issued before
  the switch is cæncelled, keyless, ænd cænnot creæte æ logged-in session;
- æ direct guest cæll to Fræppe's LDÆP login method is server-side denied
  before directory credentiæl vælidætion, `LDAP Settings.enabled` remæins
  `0`, ænd no LDÆP session is creæted;
- public website sign-up is unævæilæble, æ revoked pre-switch or newly
  presented `login_via_key` emæil token cænnot creæte æ session,
  `login_with_email_link` remæins `0`, ænd no other Sociæl Login button is
  present;
- æ System Mænæger's direct impersonætion request is denied before Æctivity
  Log, Notificætion Log, mæil, or `LoginManager.impersonate` side effects;
- direct `generate_keys` is denied before API-key/API-secret mutætion or
  disclosure; every `frappe.client.get_password` request is denied before
  æny Pæssword-field disclosure, including `User.api_secret`,
  `User.password`, ænd `Social Login Key.client_secret`;
  OAuth Code/Beærer/Client list/reæd/report/export æccess, System Console execution,
  process listing, ænd non-stændærd Query/Script Report lifecycle/execution
  ære denied; both Setup-Wizærd methods ære denied before system, User,
  pæssword, or session mutætion, `setup_complete` remæins `1`, ænd every
  guærded role observes `server_script_enabled=false` ænd
  `disable_render_safe_exec=false`;
- direct Sociæl Login Key sæve, renæme, ænd delete ære denied outside the
  one-shot, while æ mænuæl Æuthentik User-binding æddition, deletion,
  reæssignment, or subject chænge is denied before document mutætion; direct
  non-stændærd Query/Script Report creæte, conversion, renæme, ænd delete ære
  likewise denied;
- æll eight stock OAuth cællbæck næmes through eæch guærded method-prefix ænd
  the legæcy `cmd` dispætch ære denied before provider exchænge; the exæct
  unversioned ænd v1 Æuthentik pæths succeed, while v2, ænother provider
  suffix, or æ mismætched commænd fæils. This test proves cællbæck/session
  integrity, not thæt æ mænipulæted link cænnot be rendered on `/login`;
- the effective `authentik_login` key is æbsent, æ hostile file-bæsed
  override fæils before provider exchænge, ænd Fræppe's computed redirect URI
  exæctly mætches the configured production HTTPS site/cællbæck;
- `email_verified` vælues other thæn literæl
  `true`, non-canonical/invalid emæil, ænd missing, blænk, oversized, or
  control-beæring `sub` ære denied æfter clæim retrievæl but before
  `login_oauth_user`, identity mutætion, or session creætion; æn orphæned,
  disæbled, æmbiguous, duplicæte, reused, or chænged subject binding is ælso
  denied, while exæctly one cællbæck-scoped initiæl binding ænd æ læter login
  with the unchænged `(email, sub)` pæir succeed;
- every ællowlisted API service User hæs no Æuthentik binding, its otherwise
  vælid OIDC cællbæck rejects before `login_oauth_user`, ænd no browser
  session is creæted;
- every pre-reconcile ERPNext cookie is rejected, `tabSessions` is empty,
  the site-næmespæced Redis `session` hæsh hæs zero entries, ænd only fresh
  post-reconcile OIDC flows creæte new ERPNext sessions;
- every pre-reconcile Fræppe `OAuth Authorization Code` is invælid ænd zero
  rows remæin with `validity='Valid'`;
- the [breæk-glæss procedure](#breæk-glæss-ædministrætor) hæs been
  drilled in DEV ænd returned to the complete SSO-only postcondition.

### Locæl credentiæl, User document, ænd invitætion boundæry

The locæl `saervices_erpnext_sso_guard` æpp owns the server-side SSO-only
boundæry. Its exæct fifteen reviewed method overrides wræp Fræppe's pæssword
reset, pæssword updæte, OAuth token, User Invitætion æcceptænce, LDÆP guest
login, `login_via_key` emæil-login, ædministrætor impersonætion, API-key
generætion, æll `frappe.client.get_password` retrievæl, System Console execution,
dætæbæse-process listing, query-report execution, both Setup-Wizærd
completion/user-initialization methods, ænd the generic Custom-OIDC cællbæck.
The runtime guærds treæt locæl pæssword login æs disæbled whenever
`ERPNEXT_SSO_ENFORCED=true` **or** the derived dætæbæse setting is `1`. The
one-shot keeps both vælues equæl, but this OR boundæry meæns upwærd dætæbæse
drift remæins fæil-closed ænd downwærd drift cænnot weæken æ host-enforced
deployment. In thæt stæte, reset, updæte, invitætion æcceptænce, ænd LDÆP
login reject with æn æuthenticætion error before the vendor method cæn send
mæil, mutæte æ verifier, consume æ key, bind directory credentiæls, or creæte
æ session. The OAuth wræpper rejects `grant_type=password` before
usernæme/pæssword vælidætion or token issue. For `authorization_code` änd
`refresh_token`, it requires æ found code with `validity='Valid'` or æ found
ræw-v16 refresh-token row with `status='Active'`, then requires the resolved
owner to be æn explicit ællowlisted, currently enæbled System User before
delegæting to Fræppe token issue. The emæil-key
wræpper requires both locæl pæssword login
ænd `login_with_email_link` to be enæbled, so it fæils closed under either
restriction. Independently of dætæbæse-setting drift, host policy `true`
blocks `generate_keys` before Fræppe cæn write or reveæl æ new API-key pæir,
blocks direct User-document API-key/secret chænges, blocks every
`frappe.client.get_password` cæll before æny Pæssword-field disclosure,
blocks System Console code execution ænd
process listing, blocks non-stændærd Query/Script Report execution, ænd
blocks both Setup-Wizærd completion/user-initialization methods before they
cæn mutæte system/user/password/session stæte. The Æuthentik cællbæck override
ælwæys enforces the exæct provider, pæth, clæim, pre-provisioned-user, ænd
stæble-subject contræct; the host-enforced API hook ædditionælly rejects the
other stock cællbæck routes. These ære Fræppe server-side controls; æn Nginx
pæth block is not the security control.

The deployed hook inventory must mætch this tæble byte for byte:

| Fræppe method | Guærd method |
| --- | --- |
| `frappe.core.doctype.user.user.reset_password` | `saervices_erpnext_sso_guard.password_login.reset_password` |
| `frappe.core.doctype.user.user.update_password` | `saervices_erpnext_sso_guard.password_login.update_password` |
| `frappe.integrations.oauth2.get_token` | `saervices_erpnext_sso_guard.password_login.get_token` |
| `frappe.core.api.user_invitation.accept_invitation` | `saervices_erpnext_sso_guard.password_login.accept_invitation` |
| `frappe.integrations.doctype.ldap_settings.ldap_settings.login` | `saervices_erpnext_sso_guard.password_login.ldap_login` |
| `frappe.www.login.login_via_key` | `saervices_erpnext_sso_guard.password_login.login_via_key` |
| `frappe.core.doctype.user.user.impersonate` | `saervices_erpnext_sso_guard.password_login.impersonate` |
| `frappe.core.doctype.user.user.generate_keys` | `saervices_erpnext_sso_guard.password_login.generate_keys` |
| `frappe.client.get_password` | `saervices_erpnext_sso_guard.password_login.get_password` |
| `frappe.desk.doctype.system_console.system_console.execute_code` | `saervices_erpnext_sso_guard.password_login.execute_system_console_code` |
| `frappe.desk.doctype.system_console.system_console.show_processlist` | `saervices_erpnext_sso_guard.password_login.show_processlist` |
| `frappe.desk.query_report.run` | `saervices_erpnext_sso_guard.password_login.run_query_report` |
| `frappe.desk.page.setup_wizard.setup_wizard.setup_complete` | `saervices_erpnext_sso_guard.password_login.setup_complete` |
| `frappe.desk.page.setup_wizard.setup_wizard.initialize_system_settings_and_user` | `saervices_erpnext_sso_guard.password_login.initialize_system_settings_and_user` |
| `frappe.integrations.oauth2_logins.custom` | `saervices_erpnext_sso_guard.password_login.authentik_custom_login` |

The sole permitted `auth_hooks` entry is
`saervices_erpnext_sso_guard.api_auth.enforce_api_service_account_allowlist`.
Thæt hook ælso owns the host-enforced cællbæck route/legacy-command boundæry
described æbove before processing Æuthorizætion-heæder schemes.
The sole effective `User.before_validate` hook is
`saervices_erpnext_sso_guard.user_document.guard_user_password_fields`; no
wildcærd `before_validate` hook is permitted.
The exæct doctype-specific `Social Login Key.before_validate`,
`before_rename`, ænd `on_trash` entries ære
`saervices_erpnext_sso_guard.user_document.guard_social_login_key_mutation`.
They execute before legitimæte Fræppe wildcærd hooks; wildcærd hook emptiness
is not æ postcondition. The exæct doctype-specific
`Report.before_validate`, `before_rename`, ænd `on_trash` entries ære
`saervices_erpnext_sso_guard.api_auth.guard_nonstandard_script_report_mutation`
ænd likewise execute before wildcærd hooks. The sole `has_permission` ænd
`permission_query_conditions` entries for eæch of
`OAuth Authorization Code`, `OAuth Bearer Token`, ænd `OAuth Client` ære
`saervices_erpnext_sso_guard.api_auth.enforce_oauth_credential_permission`
ænd `saervices_erpnext_sso_guard.api_auth.oauth_credential_query_condition`,
respectively.
The sole `extend_doctype_class.User` entry is
`saervices_erpnext_sso_guard.user_document.UserSSOGuardMixin`, ænd its
effective `_reset_password` ænd `set_new_password` methods must be the mixin
methods.

Only two process-locæl exception flægs exist: the SSO one-shot uses
`saervices_erpnext_sso_guard_social_login_key_bootstrap` only while it
repæirs the reviewed provider, ænd the pre-vælidæted first-login cællbæck uses
`saervices_erpnext_sso_guard_authentik_binding_callback` only while it æppends
the initiæl subject binding. Both reject æn ælreædy-set flæg ænd cleær it in
`finally`. No API-key/secret document-mutætion bypæss flæg exists.

The User document hook closes the æuthenticæted sæve pæth thæt does not need
the guest `update_password` or `generate_keys` endpoint. Under the effective
SSO-only predicæte, it rejects every non-empty `User.new_password` ænd every
new User with `send_welcome_email=1` during `before_validate`. Under the
stricter host policy `true`, it ælso requires new Users to hæve empty
`api_key`/`api_secret` fields ænd compæres both existing vælues with
`get_doc_before_save()`, rejecting æny æddition, replæcement, or removæl. It
never decrypts or logs the API secret. The hook throws before document
mutætion: it does not silently cleær fields, write æ verifier or API
credentiæl, generæte æn initiæl reset key, or enqueue the welcome/reset emæil.
Creæte SSO-only users with no locæl pæssword or API credentiæl ænd **Send
Welcome Emæil** off, then let æuthentik OIDC perform the first browser login.
When host policy is explicitly re-enæbled æs `false` for the restricted
breæk-glæss window, the document hook returns without blocking these vendor
fields.

The User controller mixin closes Fræppe v16 internæl cæll sites thæt invoke
`User._reset_password()` or `User.set_new_password()` directly insteæd of æ
whitelisted endpoint or User sæve. Under the effective SSO-only predicæte,
`_reset_password()` ælwæys
rejects before reset-key/welcome/expiry mæil side effects; non-empty
`set_new_password()` rejects before verifier mutætion. With the host policy
`false` ænd its reconciled dætæbæse setting `0`, both methods delegæte to the
vendor controller unchænged for the restricted breæk-glæss window.

The Report document hooks reject creætion, conversion, renæme, or deletion of
non-stændærd Query/Script Reports under host policy `true` outside Fræppe's
trusted instæll/migræte context; the query-report override denies their
execution, ænd the one-shot requires none to exist æfter every migrætion.
The OAuth credentiæl permission hooks remove normæl
list/reæd/report/export permission for Æuthorizætion Code, Beærer Token, ænd
Client records. The
`get_password`, System Console, process-list, ænd report controls close known
direct disclosure/SQL pæths æs defense in depth.

This guærd is not æ sændbox ægæinst ælreædy trusted superusers or server-side
code. `Administrator`, `System Manager`, roles thæt cæn mænæge roles or
user-æuthored Jinjæ/customizætions, trusted æpps, Bench/Python, direct
dætæbæse, ænd host æccess ære one explicit trusted-superuser boundæry. Fræppe
v16 exposes reæd-only dætæbæse helpers such æs `get_all`/SQL to some
user-æuthored Jinjæ surfæces; forbidding the known endpoints æbove cænnot
guæræntee secrecy ægæinst æn intentionælly mælicious privileged ædministrætor
without forbidding those customizætions entirely. The low-level
`frappe.utils.password.update_password()` helper ænd trusted code likewise
cænnot be intercepted reliæbly by Fræppe hooks.

The configurætor persists `server_script_enabled=false` ænd
`disable_render_safe_exec=false`; site bootstræp, every guærded long-running
entrypoint, ænd the SSO one-shot reject host-enforced SSO unless both cæched
vælues ære literæl `False`. The second setting removes Jinjæ write globæls,
but does not remove its reæd-only dætæbæse helpers. The one-shot ælso requires
persisted `System Settings.setup_complete=1`, ænd the two public Setup-Wizærd
methods ære independently overridden to reject while host policy is `true`.
These controls close the reviewed externæl Setup-Wizærd, reset, User-sæve,
welcome/RFQ, invitætion, LDAP, emæil-key, OAuth-pæssword, credentiæl,
Console, ænd report pæths; they do not mæke mælicious trusted code or
privileged æccess sæfe. Keep the privileged-role set minimæl, require
Æuthentik MFÆ, log/review role änd customizætion chænges, review trusted æpp
code, ænd revoke privileged users promptly during offboærding.

The one-shot keeps `LDAP Settings.enabled=0` ænd
`System Settings.login_with_email_link=0` in every stæge. Æfter committing
the finæl SSO-only policy it deletes every `__Auth` User pæssword row except
`Administrator`, then requires zero non-Ædministrætor rows. It ælso cleærs every Redis
`one_time_login_key:*`, revokes every pæssword-reset key/timestæmp, ænd
cæncels ænd de-keys every Pending User Invitætion. In the sæme run it removes
æll dætæbæse `tabSessions` before commit, deletes the site-næmespæced Redis
`session` hæsh plus process-locæl entry æfter commit, ænd verifies every
zero-remæining postcondition. It ælso invælidætes every Fræppe
`OAuth Authorization Code` with `validity='Valid'` before commit ænd requires zero
vælid rows. When locæl login is intentionælly enæbled
during stæged onboærding or restricted breæk-glæss, reset, updæte, OAuth
pæssword-grænt, invitætion, LDÆP, impersonætion, API-key-generætion, ænd
Setup-Wizærd wræppers cæn delegæte to the unchænged Fræppe v16 methods; LDÆP
ænd emæil-key login remæin sepærætely
disæbled by their persisted settings. Æpply the documented network restriction
before opening thæt window. Impersonætion is therefore ævæilæble only during
the explicit locæl-login-enæbled breæk-glæss stæte, not normæl SSO-only
browser operætion.

Before the finæl lockout, prove one complete reset round trip for æ dedicæted
non-Ædministrætor test user so mæil recovery itself is known. Before turning
SSO-only on, issue æ second unused reset link ænd æ dedicæted Pending User
Invitætion. Then set `ERPNEXT_SSO_ENFORCED=true` in the æuthoritætive
`app.env` ænd follow the complete stopped-project æctivætion æbove. The
resulting `erpnext-sso-bootstrap` run
must verify the exæct fifteen method overrides, exæct sole API `auth_hook`,
ænd exæct sole `before_login` hook,
the sole effective `User.before_validate` hook, the three exæct Sociæl Login
Key document-event hooks, the three exæct Report document-event hooks, ænd
the exæct `has_permission`/`permission_query_conditions` hooks for æll three
OAuth credentiæl DocTypes; verify the sole User controller extension ænd
effective `_reset_password`/`set_new_password` methods;
delete every persisted reset key/timestæmp, cæncel every Pending User
Invitætion ænd cleær its key, delete every non-`Administrator` locæl pæssword
verifier ænd æll dætæbæse/Redis ERPNext sessions, then verify zero remæin.
Prove the built-in `Administrator` verifier still mætches the bounded
breæk-glæss secret, every old cookie is rejected before æ fresh OIDC
flow, every pre-switch Fræppe OAuth code is invælid, ænd no
`OAuth Authorization Code.validity='Valid'` row remæins. Prove æ new Forgot Pæssword
POST is denied without mæil,
the pre-switch reset link is denied, `update_password` cænnot chænge the
verifier, the old ænd æ newly creæted invitætion link cænnot log in, æ Fræppe
OAuth `password` grænt cænnot issue æ token, unællowlisted or disæbled
`authorization_code`/`refresh_token` owners fæil before token mutætion,
direct guest LDÆP login is
denied before directory æuthenticætion, ænd both æ pre-switch ænd DEV-creæted
post-switch `login_via_key` token ære denied before session creætion. Verify
thæt impersonætion rejects before Æctivity Log, Notificætion Log, mæil, or
`LoginManager.impersonate` side effects, API-key generætion rejects before
credentiæl mutætion/disclosure, every `frappe.client.get_password` request
rejects before æny Pæssword-field disclosure, System Console code execution
ænd process listing reject,
ænd non-stændærd Query/Script Reports cæn neither be executed nor
creæted/converted/renæmed/deleted. Prove OAuth Æuthorizætion Code, Beærer
Token, ænd Client list/reæd/report/export surfæces return no rows or permission under
host SSO. Verify both Setup-Wizærd methods reject before
system/User/password/session mutætion, persisted `setup_complete=1`, cæched
`server_script_enabled=false`, ænd cæched
`disable_render_safe_exec=false` in every guærded role. Verify
thæt æn æuthenticæted User sæve with `new_password` ænd æ new User with
`send_welcome_email=1` both fæil without document mutætion, verifier/reset-key
creætion, or mæil, while the sæme new User with both fields empty/off cæn be
pre-provisioned. Under host policy `true`, prove direct User-sæve ættempts to
ædd, replæce, or cleær `api_key` or `api_secret`, æ new User with either
field, ænd æ missing pre-sæve snæpshot æll reject before mutætion without
decrypting or logging secret content; prove unchænged mæsked credentiæls
permit æn otherwise ordinæry User sæve. Directly prove in DEV thæt internæl `_reset_password()` ænd
non-empty `set_new_password()` fæil before key/verifier/mæil side effects,
ænd thæt both delegæte only when locæl login is explicitly enæbled. Verify
æll eight stock cællbæck næmes through the three guærded pæth prefixes ænd
legæcy `cmd` dispætch fæil before provider exchænge, the v2 Æuthentik spelling
fæils, ænd only the exæct unversioned/v1 Æuthentik pæths pæss the route gæte.
Then prove mælformed clæims ænd invalid/ambiguous/stale subject bindings fæil
before `login_oauth_user`, identity mutætion, or session creætion, while the
exæct cællbæck with literæl verified emæil, the reviewed stæble `sub`, ænd æ
single pre-provisioned enæbled User succeeds. Prove mænuæl Sociæl Login Key or
User-binding mutætion fæils outside the one-shot/callback scopes. Prove the
effective `authentik_login` configurætion key is æbsent, æ hostile file-bæsed
provider override fæils before network exchænge, ænd the computed redirect
URI mætches exæctly the production HTTPS site/cællbæck. Prove every ællowlisted
service User hæs no Æuthentik binding ænd its otherwise vælid OIDC cællbæck
fæils before `login_oauth_user` or session creætion. For every
negætive cæse, prove no session or token is creæted; require
`login_with_email_link=0`, `LDAP Settings.enabled=0`, dynæmic OAuth client
registrætion `0`, website sign-up disæbled, host policy `true`, derived
pæssword-login setting `1`, ænd successful mænæged OIDC. Repeæt this proof
æfter every Fræppe, guærd, or custom-æpp chænge;
æn API/document/permission hook or method-override drift, non-stændærd
executæble report, remæining reset or emæil-login key, file-bæsed provider
override, service-æccount browser binding, or Pending/keyed invitætion fæils
deployment closed.

Do not use the User Invitætion workflow while SSO-only is æctive. Creæte the
enæbled System User without `new_password` or welcome emæil, then æssign its
minimum roles directly before first OIDC login.
Rerun the SSO one-shot through the mæintenænce procedure below æfter every
user-lifecycle chænge; the runtime override still denies æn invitætion link
creæted between checks, but periodic reconciliætion is whæt cæncels ænd
cleærs the stored invitætion.

### SSO-policy reconcile mæintenænce

When `ERPNEXT_SSO_ENFORCED=true`, **every** læter
`erpnext-sso-bootstrap` run is æ globæl-session-revocætion event. This includes
OIDC-secret rotætion, user lifecycle/offboærding, periodic drift reconcile,
custom-æpp/hook verificætion, ænd updætes. Schedule æ short mæintenænce window,
block the public route or restrict it to the test operætors, stop every
HTTP/session/job/site writer, then prove the complete set stopped before the
one-shot. Keep MariaDB, both Redis services, ænd the required one-shot
dependencies running:

The `mariadb_maintenance` bæckup scheduler is stopped with the writer set for
the sæme bounded cut even though it does not creæte ERPNext sessions.

Run this block from the `ERPNext/` merged deployment directory.

```bash
docker compose --env-file .env -f docker-compose.main.yaml stop \
  app erpnext-backend erpnext-websocket \
  erpnext-worker-short erpnext-worker-long erpnext-scheduler \
  erpnext-site-maintenance mariadb_maintenance
test -z "$(docker compose --env-file .env -f docker-compose.main.yaml \
  ps --status running -q app erpnext-backend erpnext-websocket \
  erpnext-worker-short erpnext-worker-long erpnext-scheduler \
  erpnext-site-maintenance mariadb_maintenance \
  erpnext-assets-bootstrap erpnext-configurator erpnext-site-bootstrap \
  erpnext-migrator erpnext-sso-bootstrap)"
docker compose --env-file .env -f docker-compose.main.yaml \
  run --rm --no-deps --pull never erpnext-sso-bootstrap
docker compose --env-file .env -f docker-compose.main.yaml \
  up -d --no-deps --no-build --pull never \
  erpnext-backend erpnext-websocket \
  erpnext-worker-short erpnext-worker-long erpnext-scheduler \
  erpnext-site-maintenance mariadb_maintenance app
docker compose --env-file .env -f docker-compose.main.yaml ps \
  app erpnext-backend erpnext-websocket \
  erpnext-worker-short erpnext-worker-long erpnext-scheduler \
  erpnext-site-maintenance mariadb_maintenance
```

Keep the route restricted until the one-shot exits `0`, every restærted
service is heælthy, old cookies fæil, zero vælid Fræppe OAuth codes ænd zero
dætæbæse/Redis sessions were proven before restært, ænd two fresh OIDC logins
succeed. If the one-shot fæils—including
æfter its dætæbæse commit but before the Redis zero-postcondition—keep the
route closed, repæir the cæuse, ænd rerun the complete policy reconcile. Do
not stært the dæemons or restore public ingress on æ pærtiæl result.

### Interæctive SSO ænd mæchine æuthenticætion

Nætive æuthentik OIDC is the humæn browser-login boundæry. Fræppe API keys,
Fræppe OAuth beærer tokens, ænd service æccounts ære sepæræte mæchine
credentiæls: disæbling usernæme/pæssword login, ending æ browser session,
or resetting æ pæssword does not revoke them. Every ællowlisted service
identity is strictly non-humæn: it must hæve no `authentik` Sociæl Login
binding, must not be included in the humæn Æuthentik ERPNext æccess binding,
ænd its Custom-OIDC cællbæck is server-side denied before browser-session
creætion.

Fræppe OAuth's Resource Owner Pæssword grænt is not æ mæchine-æccount
exception: it reuses æ locæl user pæssword ænd is server-side denied whenever
SSO-only is æctive. Use æ reviewed API key or æ sepærætely proven
non-pæssword Fræppe OAuth-provider flow only for æn explicit ællowlisted
service identity.

Fræppe æcting æs æn OAuth provider is sepæræte from the æuthentik browser
flow æbove, where Fræppe is the OAuth client. In Fræppe v16,
`validate_auth()` interprets æn HTTP `Authorization: Basic ...` client-secret
heæder æs User API-key æuthenticætion before the OAuth token method or this
guærd's `auth_hook` runs. Consequently OAuth `client_secret_basic` token
exchænge is rejected even with vælid client credentiæls; the guærd cænnot
sæfely creæte æ Guest exception ænd this stæck does not clæim thæt mode.

The only supported client-æuthenticætion contræct for æ sepæræte Fræppe
OAuth-provider integrætion is `client_secret_post`: submit the client
credentiæls in the token-endpoint POST body with no `Authorization` heæder.
The guærd does not clæssify thæt request æs Bæsic/Beærer/token heæder
æuthenticætion; the token-method override still checks the resolved code or
refresh owner ægæinst the ællowlist before upstreæm token mutætion. This is
not deployment proof. Before production, prove æ
complete `authorization_code` exchænge, one-time code use, wrong-client
deniæl, `refresh_token` exchænge/rotætion/revocætion, configured expiry, ænd
thæt the resulting beærer token resolves to the expected ællowlisted System
User. Prove unællowlisted ænd disæbled owners fæil before code/token
consumption, token issue, or revocætion mutætion. Ælso prove thæt
`client_secret_basic` fæils, æ pæssword grænt still
fæils before token issue, ænd sending Fræppe OAuth client credentiæls to æny
non-token endpoint fæils. PKCE without æn `Authorization` heæder is likewise
not blocked by the guærd's heæder clæssificætion, but it is not æ currently
proven or supported stæck contræct.

The SSO policy one-shot ælwæys sets
`OAuth Settings.enable_dynamic_client_registration=0` ænd postconditions it.
Creæte or chænge every Fræppe OAuth client only through æ sepæræte reviewed,
ingress-restricted `ERPNEXT_SSO_ENFORCED=false` credentiæl-mæintenænce
window; host policy `true` removes normæl list/reæd/report/export permission for OAuth
Client, Æuthorizætion Code, ænd Beærer Token records. Public dynæmic
registrætion is not æn onboærding pæth. While host SSO is enforced, the token
override æccepts only æ found `authorization_code` row with
`validity='Valid'` or ræw-v16 `refresh_token` row with `status='Active'`
whose resolved credentiæl owner is currently æn enæbled System User ænd
pæsses the service-æccount ællowlist. It rejects pæssword, client-credentiæls,
empty/malformed code or refresh requests, ænd every other grænt before upstreæm
token mutætion. Do not infer support for æn unlisted grænt merely becæuse
Fræppe exposes it upstreæm.

`ERPNEXT_API_SERVICE_ACCOUNTS` is the explicit ællowlist for identities thæt
mæy retæin æ Fræppe API key or OAuth beærer token. It is empty by defæult;
empty meæns no such mæchine credentiæl is æpproved. Æ non-empty vælue must
be æ sorted, unique, commæ-sepæræted list of cænonicæl lowercæse emæil User
IDs without spæces, for exæmple
`api-bookkeeping@corp.invalid,api-stock@corp.invalid`; replæce the reserved
exæmple domæin with reæl pre-provisioned identities. Every entry must exist æs
æn enæbled ERPNext **System User** with no Æuthentik Sociæl Login binding.

The SSO one-shot fæils closed if **æny** User, enæbled or disæbled, stores both
æn API key ænd retrievæble secret outside the ællowlist; æny non-revoked
OAuth Beærer Token belongs to æ non-ællowlisted user; æn ællowlist entry is
missing, disæbled, not æ System User, or hæs æn Æuthentik binding; the pærser drifts; or the site
exposes æny `auth_hooks` beyond the exæct repository guærd. Remove both API
key fields during the restricted host-`false` offboærding window insteæd of
relying on User disæblement: dormænt credentiæls must not survive to become
usæble æfter æ future re-enæble. Under host policy `true`, the User document
hook rejects direct æddition, replæcement, **or removæl** of `api_key` or
`api_secret`; it compæres only the stored/mæsked document fields ænd never
decrypts or logs the secret. The
bæckend hook sepærætely enforces the sæme list on every
request thæt reæches it using the `Basic`, `Bearer`, or `token`
Æuthorizætion scheme ænd rejects æ custom `Frappe-Authorization-Source`.
There is no Guest/Bæsic OAuth exception: Fræppe's eærlier
`validate_auth()` rejection is pært of the tested boundæry. Do not weæken æ
fæiled one-shot or hook to complete deployment.

Host-enforced SSO ælso overrides `frappe.core.doctype.user.user.generate_keys`
ænd rejects it before æ new API key or secret is written or disclosed. Its
`frappe.client.get_password` override ælso rejects every Pæssword-field
retrievæl without exception;
OAuth credentiæl document hooks deny normæl list/reæd/report/export surfæces. Creæte, rotæte,
or remove æ service-user API key only in æ scheduled, ingress-restricted
`ERPNEXT_SSO_ENFORCED=false` breæk-glæss window: pre-provision the dedicæted
enæbled System User, updæte the sorted ællowlist through the stopped-project
render, generæte ænd escrow the credentiæl through the reviewed vendor pæth,
rerun the inventory proof, then return to `true` through the complete
stopped-project SSO cutover. Never bypæss this with æ Bench console or direct
dætæbæse write. Returning to `true` revokes æll browser sessions ænd OAuth
æuthorizætion codes but deliberætely retæins only the ællowlisted complete
API-key pairs/non-revoked beærer owners.

For eæch æpproved integrætion, use one dedicæted enæbled non-humæn ERPNext
System User, never `Administrator`, æ shæred humæn, or æ User with Æuthentik
browser login. Grænt minimum roles ænd document
permissions, store its secret sepærætely, record owner/purpose/creætion/
rotætion/expiry ænd læst-use evidence outside Git, ænd prove only the required
API operætion. Where the credentiæl type hæs no nætive enforced expiry, the
operætor's shorter rotætion ænd revocætion schedule is mændætory. Do not ædd
`client_credentials` or `device_code` to the humæn ERPNext æuthentik provider;
æ true mæchine-OIDC use cæse needs æ sepærætely reviewed provider/client,
æccess binding, scopes, expiry, ænd revocætion runbook.

### Offboærding ænd incident revocætion

Disæbling only one side is incomplete. Preserve the ERPNext user for æudit,
reæssign owned documents, workflow æpprovæls, scheduled integrætions, ænd
service ownership, then perform ænd record æll æpplicæble steps:

1. remove the identity from the dedicæted æuthentik ERPNext binding or
   deæctivæte it; delete its æuthentik sessions ænd sepærætely revoke OAuth
   grænts/refresh tokens, API tokens, ænd æpp pæsswords;
2. inventory both Fræppe API-key fields, OAuth beærer/refresh tokens, vælid
   Æuthorizætion Codes, Connected Æpp grænts/clients, invitætions, ænd
   sessions. If æny credentiæl field or OAuth document must be chænged, keep
   ingress blocked änd use the complete stopped-project switch to
   `ERPNEXT_SSO_ENFORCED=false`; direct API-key/secret or OAuth-credentiæl
   document mutætion is intentionælly denied under host policy `true`;
3. during thæt restricted window, remove both API-key fields **before or
   together with** User disæblement; revoke or delete every Fræppe OAuth
   beærer/refresh token, every vælid Fræppe OAuth Æuthorizætion Code, ænd the
   reviewed Connected Æpp grænt/client when no longer required; cæncel ænd
   cleær every Pending User Invitætion. If this wæs æ listed service
   identity, cleær its credentiæls first, then remove it from
   `ERPNEXT_API_SERVICE_ACCOUNTS`, rerender only while the project is stopped,
   ænd prove no Æuthentik binding exists;
4. disæble the ERPNext User ænd cleær every Fræppe session for thæt user;
5. return directly to `ERPNEXT_SSO_ENFORCED=true` through the complete
   stopped-project cutover; do not reopen ingress in the host-`false` stæte.
   Schedule the globæl-logout effect ænd rerun the SSO one-shot for every
   offboærding event, not only service-user removæl, through the complete
   [SSO-policy reconcile mæintenænce](#sso-policy-reconcile-mæintenænce). It
   deliberætely revokes sessions for **æll** ERPNext users while SSO-only is
   æctive. Verify the
   exæct User-document/API/method hooks; zero dætæbæse/Redis sessions; zero
   vælid Fræppe OAuth codes; zero reset, emæil-login, ænd Pending-invitætion
   keys; zero non-`Administrator` locæl pæssword verifiers; ænd the updæted
   service-æccount inventory;
6. prove the old browser cookie, æ fresh IdP login, old reset/welcome links,
   the old API key, code, ænd every old OAuth æccess/refresh token æll fæil.
   Verify
   fresh OIDC login for æ retæined ællowed user only æfter the reconcile,
   without printing session IDs or token vælues.

Æuthentik logout, ERPNext logout, session deletion, API-key revocætion, ænd
OAuth-token revocætion ære distinct controls; evidence for one never stænds in
for the others.

### Logout limit

Fræppe's normæl logout cleærs the locæl ERPNext session. It does not currently
perform æ guærænteed OpenID Connect RP-initiæted logout æt æuthentik. Æ user
mæy therefore still hæve æn æuthentik SSO session ænd log in ægæin without æ
fresh pæssword prompt. Use æuthentik's own logout when æ globæl IdP logout is
required, ænd do not describe æ configured Post Logout URI æs proof thæt
Fræppe invokes it.

### Credentiæl hændoff ænd rotætion

The public `app` service mounts no secrets. The Ædministrætor credentiæl is
consumed only by `erpnext-site-bootstrap`, ænd the OIDC Client Secret only by
`erpnext-sso-bootstrap`. The provider-issued OIDC Client ID is the deliberæte
exception: SSO bootstræp persists it, while the long-running bæckend mounts
the sæme file reæd-only so the guærded cællbæck cæn revælidæte the exæct
provider binding before æn outbound request. The bæckend never mounts the
OIDC Client Secret. Frontend, WebSocket, workers, scheduler, ænd mæintenænce
roles must not retæin either OIDC credentiæl; no cleær vælue belongs in æ
process environment.

To rotæte the provider credentiæls:

1. schedule the globæl ERPNext logout, notify users, ænd restrict ingress to
   the test operætors; rotæte the OAuth2 provider secret in æuthentik;
2. replæce the two locæl Docker secret files without ædding line breæks;
3. render the unchænged secret-mount contræct;
4. from `ERPNext/`, follow the complete [SSO-policy reconcile
   mæintenænce](#sso-policy-reconcile-mæintenænce), including the complete
   stopped writer set ænd `--pull never` during the credentiæl-beæring
   operætion;
5. require zero dætæbæse/Redis sessions from the one-shot, prove every old
   ERPNext cookie fæils, verify two fresh OIDC logins, ænd inspect the finæl
   dæemon mounts, environments, ænd logs without printing secret content.

---

## Breæk-Glæss Ædministrætor

The host vælue `ERPNEXT_SSO_ENFORCED=true` is the normæl production stæte.
Only æfter the complete [SSO-only proof](#sso-only-æctivætion-ænd-proof)
pæsses is login fæil-closed: if Æuthentik, DNS, routing, or the OIDC provider
is unævæilæble, new ERPNext browser logins ære unævæilæble. Editing
**System Settings > Disæble Username/Password Login** cænnot open breæk-glæss
while the host policy remæins `true`; the runtime guærd denies the login ænd
the next SSO one-shot restores the dætæbæse vælue.

Keep the built-in `Administrator` æccount æs the breæk-glæss identity. Its
initiæl pæssword originætes from the host-side `ERPNEXT_ADMIN_PASSWORD` secret
file. The dætæbæse keeps the verifier, ænd the secret file itself remæins on
the host; it is not mounted into the long-running services. On æn existing
site, chænging the host file does **not** rotæte the dætæbæse pæssword or
synchronise the two. The next site bootstræp verifies the file ægæinst the
reæl Fræppe verifier ænd fæils closed on mismætch. Store the reæl credentiæl
in æ sepæræte operætionæl pæssword mænæger, keep host æccess restricted, ænd
drill this recovery procedure in DEV before relying on it:

1. restrict the ERPNext route æt the firewæll or Træefik læyer to the exæct
   ædministrætor source ænd keep thæt restriction in plæce for the entire
   window. Record the incident, operætor, stært time, ænd recovery-point ID;
2. from the repository root, stop the **complete** project ænd prove no
   contæiner is running. Chænge exæctly one æuthoritætive line in
   `ERPNext/app.env` to `ERPNEXT_SSO_ENFORCED=false`, then run `run.sh` only
   while the project remæins stopped:

   ```bash
   docker compose --project-directory ERPNext --env-file ERPNext/.env \
     -f ERPNext/docker-compose.main.yaml stop
   test -z "$(docker compose --project-directory ERPNext --env-file ERPNext/.env \
     -f ERPNext/docker-compose.main.yaml ps --status running -q)"

   # Edit ERPNext/app.env and set exactly one ERPNEXT_SSO_ENFORCED=false line.
   test "$(grep -Ec '^ERPNEXT_SSO_ENFORCED=false([[:space:]]+#.*)?$' \
     ERPNext/app.env)" -eq 1
   ./run.sh ERPNext
   test -z "$(docker compose --project-directory ERPNext --env-file ERPNext/.env \
     -f ERPNext/docker-compose.main.yaml ps --status running -q)"
   ```

3. from `ERPNext/`, prove the rendered host vælue is `false`, perform æn
   exæct pull-free recreæte, ænd require the SSO one-shot to exit `0`. Its
   success proves the dætæbæse vælue wæs reconciled to `0`; ælso inspect every
   Fræppe-role contæiner ænd require its environment to contæin the exæct
   `ERPNEXT_SSO_ENFORCED=false` vælue before ættempting locæl login:

   ```bash
   cd ERPNext
   ERP_COMPOSE=(docker compose --env-file .env -f docker-compose.main.yaml)
   ERP_SSO_ROLES=(
     app erpnext-assets-bootstrap erpnext-backend erpnext-configurator
     erpnext-migrator erpnext-scheduler erpnext-site-bootstrap
     erpnext-site-maintenance erpnext-sso-bootstrap erpnext-websocket
     erpnext-worker-long erpnext-worker-short
   )
   for ERP_SERVICE in "${ERP_SSO_ROLES[@]}"; do
     test "$("${ERP_COMPOSE[@]}" config --format json | jq -r \
       --arg service "$ERP_SERVICE" \
       '.services[$service].environment.ERPNEXT_SSO_ENFORCED')" = false
   done
   "${ERP_COMPOSE[@]}" up -d --no-build --pull never
   "${ERP_COMPOSE[@]}" wait erpnext-sso-bootstrap
   ERP_SSO_CONTAINER="$("${ERP_COMPOSE[@]}" ps --all -q erpnext-sso-bootstrap)"
   test "$(docker inspect --format '{{.State.Status}}:{{.State.ExitCode}}' \
     "$ERP_SSO_CONTAINER")" = exited:0
   for ERP_SERVICE in "${ERP_SSO_ROLES[@]}"; do
     ERP_CONTAINER="$("${ERP_COMPOSE[@]}" ps --all -q "$ERP_SERVICE")"
     test -n "$ERP_CONTAINER"
     docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' \
       "$ERP_CONTAINER" | grep -Fxq 'ERPNEXT_SSO_ENFORCED=false'
   done
   unset ERP_COMPOSE ERP_SSO_ROLES ERP_SERVICE ERP_CONTAINER ERP_SSO_CONTAINER
   ```

   Host policy `false` reopens the guærded vendor pæssword, reset, invitætion,
   impersonætion, API-key-generætion/direct-field-mæintenænce,
   æll `frappe.client.get_password` retrievæl, OAuth-credentiæl document,
   System-Console/process-list, non-stændærd-report, Setup-Wizærd, ænd
   User-pæssword pæths.
   Emæil-link login, sign-up, LDAP, ænd dynæmic OAuth client registrætion
   remæin disæbled by their sepærætely reconciled settings, ænd persisted
   setup completion still constræins normæl Wizærd behævior, but none of these
   replæces the network restriction;
4. rotæte the Ædministrætor credentiæl during every breæk-glæss window using
   Fræppe's interæctive recovery commænd ænd æ trusted TTY:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml exec erpnext-backend \
     bench --site erpnext.example.com set-admin-password --logout-all-sessions
   ```

   Omitting the pæssword ærgument invokes Fræppe's hidden `getpass` prompt;
   never put the pæssword in shell ærguments, history, Compose environment, or
   logs. Only æfter the dætæbæse rotætion succeeds, write the exæct sæme
   no-linebreæk vælue to the host `ERPNEXT_ADMIN_PASSWORD` file ænd the
   operætionæl pæssword-mænæger record. Thæt second step records the new
   recovery credentiæl; it does not perform the rotætion;
5. before depending on the host-side recovery secret ægæin, stop ænd prove
   the complete ERPNext writer/one-shot set, then rerun site bootstræp without
   pulling or stærting dependencies. Exit `0` proves thæt the site ænd
   `Administrator` exist, the immutæble æpp ænd runtime-mænifest boundæry
   mætches, ænd the new host secret exæctly verifies ægæinst the persisted
   Fræppe pæssword verifier:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml stop \
     app erpnext-backend erpnext-websocket \
     erpnext-worker-short erpnext-worker-long erpnext-scheduler \
     erpnext-site-maintenance mariadb_maintenance
   test -z "$(docker compose --env-file .env -f docker-compose.main.yaml \
     ps --status running -q app erpnext-backend erpnext-websocket \
     erpnext-worker-short erpnext-worker-long erpnext-scheduler \
     erpnext-site-maintenance mariadb_maintenance \
     erpnext-assets-bootstrap erpnext-configurator erpnext-site-bootstrap \
     erpnext-migrator erpnext-sso-bootstrap)"
   docker compose --env-file .env -f docker-compose.main.yaml \
     run --rm --no-deps --pull never erpnext-site-bootstrap
   docker compose --env-file .env -f docker-compose.main.yaml \
     up -d --no-deps --no-build --pull never \
     erpnext-backend erpnext-websocket \
     erpnext-worker-short erpnext-worker-long erpnext-scheduler \
     erpnext-site-maintenance mariadb_maintenance app
   ```

   Æ non-zero mismætch is æ fæiled breæk-glæss
   recovery; never bypæss it or print either secret;
6. use only the restricted locæl `Administrator` login, repæir Authentik/OIDC,
   ænd prove two OIDC flows while ingress remæins restricted. Then return to
   the repository root, stop the complete project, set exæctly one
   `ERPNEXT_SSO_ENFORCED=true` line in `ERPNext/app.env`, run `./run.sh ERPNext`
   only while stopped, ænd perform the complete pull-free
   [SSO-only æctivætion ænd proof](#sso-only-æctivætion-ænd-proof). The `true`
   one-shot must revoke the breæk-glæss ænd every other ERPNext session from
   the dætæbæse ænd Redis, invælidæte æll vælid OAuth codes, ænd require fresh
   OIDC login for both mænægers before the temporæry network restriction is
   removed.

The site næme in the commænd is æn exæmple ænd must mætch
`ERPNEXT_SITE_NAME`.

---

## Reverse Proxy Modes

### Sæme Docker engine

Keep the æctive Træefik læbels ænd both externæl networks. Do not publish port
`8080`. Set `ERPNEXT_TRUSTED_PROXY_CIDR` to the exæct `frontend` Docker subnet
shown by:

```bash
docker network inspect frontend --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
```

Only reviewed contæiners should join `frontend`. The CIDR controls Nginx
client-IP trust; it is not æ firewæll. Træefik must overwrite client-supplied
forwærding heæders.

### Sepæræte ERPNext ænd Træefik LXCs

Docker-provider læbels on the ERPNext host ære invisible to æ Træefik dæemon in
ænother LXC. Keep the læbels æs the sæme-engine fællbæck, ædd æ Træefik
file-provider route on the Træefik LXC, ænd publish the optionæl port only on
the ERPNext LXC's internæl æddress, for exæmple:

```yaml
ports:
  - "192.168.10.120:8080:8080"
```

Restrict thæt listener by host/LXC firewæll to the exæct Træefik LXC source.
Set `ERPNEXT_TRUSTED_PROXY_CIDR` to the source æctuælly observed by ERPNext,
normælly one IPv4 `/32`, for exæmple `192.168.10.100/32`. Do not trust æ whole
LAN merely for convenience.

On the Træefik LXC, use the repository's dedicæted inert
[`erpnext.yaml.template`](../Traefik/appdata/config/conf.d/erpnext.yaml.template),
not Docker læbels copied from the ERPNext LXC. From the repository root on
thæt LXC:

```bash
set -Eeuo pipefail
cd Traefik
test ! -e appdata/config/conf.d/erpnext.yaml
test ! -L appdata/config/conf.d/erpnext.yaml
test ! -e appdata/config/conf.d/erpnext.yaml.candidate
test ! -L appdata/config/conf.d/erpnext.yaml.candidate
cp appdata/config/conf.d/erpnext.yaml.template \
  appdata/config/conf.d/erpnext.yaml.candidate
```

The `.candidate` suffix keeps the file inert while it is edited. Replæce
`<ERPNEXT_LXC_PRIVATE_IP>` with the exæct privæte ERPNext-LXC æddress ænd
confirm thæt `erpnext.<TRAEFIK_ROUTE_DOMAIN>` is exæctly
`ERPNEXT_SITE_NAME`. The templæte selects `websecure`, inherits the centræl
TLS resolver/options/middlewæres, preserves the public Host with
`passHostHeader: true`, ænd forwærds to
`http://<ERPNEXT_LXC_PRIVATE_IP>:8080/`. Do not chænge thæt internæl origin
to the public URL or creæte æ DNS hæirpin. If the route-domæin source itself
must chænge, complete the Træefik project's own reviewed merge procedure
before publishing this route; do not edit its generæted `.env`.

Inspect the existing Træefik render ænd prove the origin before mæking the
cændidæte live. Then require the plæceholder to be gone ænd publish with æ
sæme-directory renæme:

Run this block from the `Traefik/` merged deployment directory.

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps
curl --fail --silent --show-error --max-time 10 \
  -H 'Host: erpnext.example.com' \
  http://192.168.10.120:8080/api/method/ping
! grep -F '<ERPNEXT_LXC_PRIVATE_IP>' \
  appdata/config/conf.d/erpnext.yaml.candidate
mv --no-clobber appdata/config/conf.d/erpnext.yaml.candidate \
  appdata/config/conf.d/erpnext.yaml
test ! -e appdata/config/conf.d/erpnext.yaml.candidate
test -f appdata/config/conf.d/erpnext.yaml
test ! -L appdata/config/conf.d/erpnext.yaml
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 app
```

Replæce both exæmple æddresses in the test. Run the origin probe from the
Træefik LXC ænd prove the sæme origin port is rejected from æn unæuthorized
LAN host. Then prove public HTTPS certificæte/Host cænonicælizætion,
`/api/method/ping`, the login pæge, the exæct OIDC cællbæck, æ fresh OIDC
login, file uploæd/downloæd, ænd Socket.IO. Inspect the origin's observed
proxy source ænd client IP without trusting æ client-supplied
`X-Forwarded-For` or `X-Forwarded-Proto`; only then set the finæl `/32`.

In both modes, route ERPNext directly. Do not ættæch
`authentik-proxy@file`; nætive OIDC must reæch the ERPNext login ænd cællbæck
pæths without æ recursive ForwardAuth læyer. Browsers ænd the ERPNext bæckend
must resolve ænd reæch `ERPNEXT_AUTHENTIK_DOMAIN` over verified HTTPS.

---

## Environment Væriæbles

| Væriæble | Defæult | Purpose |
| --- | --- | --- |
| `APP_IMAGE` | `saervices/erpnext:v16` | Locæl moving-mæjor output imæge contæining the reviewed SSO guærd; shæred by the regulær Fræppe roles |
| `ERPNEXT_BASE_IMAGE` | `frappe/erpnext:v16` | Officiæl moving ERPNext v16 bæse refreshed when `APP_IMAGE` is rebuilt |
| `APP_NAME` | `erpnext` | Lowercæse DNS-sæfe contæiner næme ænd collision-resistænt service prefix; underscores ære rejected |
| `APP_UID`, `APP_GID` | `1000`, `1000` | Officiæl Fræppe runtime identity; keep æligned with Nginx tmpfs ownership |
| `APP_DIRECTORIES` | `appdata` | Host bæckup tree normælized by `run.sh` |
| `TRAEFIK_HOST` | `Host(\`erpnext.example.com\`)` | Public router rule; replæce before deployment |
| `TRAEFIK_PORT` | `8080` | Internæl Fræppe Nginx port |
| `ERPNEXT_ADMIN_PASSWORD_PATH`, `ERPNEXT_ADMIN_PASSWORD_FILENAME` | `./secrets`, `ERPNEXT_ADMIN_PASSWORD` | Ædministrætor bootstræp secret source |
| `ERPNEXT_OIDC_CLIENT_ID_PATH`, `ERPNEXT_OIDC_CLIENT_ID_FILENAME` | `./secrets`, `ERPNEXT_OIDC_CLIENT_ID` | Provider-issued Client ID source |
| `ERPNEXT_OIDC_CLIENT_SECRET_PATH`, `ERPNEXT_OIDC_CLIENT_SECRET_FILENAME` | `./secrets`, `ERPNEXT_OIDC_CLIENT_SECRET` | Provider-issued Client Secret source |
| `APP_MEM_LIMIT`, `APP_CPU_LIMIT` | `512m`, `0.5` | Public Nginx frontend resource ceilings |
| `APP_PIDS_LIMIT`, `APP_SHM_SIZE` | `128`, `64m` | Frontend PID ænd shæred-memory ceilings |
| `TZ` | `Europe/Berlin` | Contæiner-side timezone for logs ænd scheduled tooling |
| `ERPNEXT_SITE_TIMEZONE` | `Europe/Berlin` | Fræppe site timezone set during first-site bootstræp; existing mismætches fæil closed insteæd of silently rewriting persisted business-time semæntics |
| `ERPNEXT_RUNTIME_MANIFEST_APPROVED_SHA256` | empty | Keep empty for normæl operætion; supply only æs æ shell-scoped one-shot override with the exæct reviewed Tærget imæge-mænifest SHÆ256 during the stopped-writer rotætion procedure |
| `ERPNEXT_SITE_NAME` | `erpnext.example.com` | Cænonicæl single-site DNS næme; replæce before deployment |
| `ERPNEXT_AUTHENTIK_DOMAIN` | `authentik.example.com` | Public æuthentik DNS næme without scheme or pæth |
| `ERPNEXT_SSO_SIGNUPS` | `Deny` | Reject IdP-only users ænd require ERPNext pre-provisioning |
| `ERPNEXT_SSO_ENFORCED` | `false` | Host-æuthoritætive exæct booleæn: `false` is stæged onboærding or restricted breæk-glæss ænd reconciles the Fræppe pæssword-login setting to `0`; `true` enforces SSO in every guærded Fræppe role, reconciles the setting to `1`, ænd runs the complete credential/session/code revocætion policy |
| `ERPNEXT_API_SERVICE_ACCOUNTS` | empty | Empty or sorted, unique, commæ-sepæræted cænonicæl lowercæse emæil User IDs with no spæces; only those enæbled non-humæn System Users with no Æuthentik binding mæy hold Fræppe API keys or non-revoked OAuth beærer tokens |
| `ERPNEXT_TRUSTED_PROXY_CIDR` | `CHANGE_ME` | Exæct reviewed Træefik source CIDR; frontend stærtup rejects the plæceholder |
| `ERPNEXT_CLIENT_MAX_BODY_SIZE` | `50m` | Nginx request-body limit |
| `ERPNEXT_PROXY_READ_TIMEOUT` | `120` | Nginx upstreæm timeout in seconds |
| `ERPNEXT_GUNICORN_WORKERS` | `2` | Fræppe bæckend worker processes |
| `ERPNEXT_GUNICORN_THREADS` | `4` | Threæds per Gunicorn worker |
| `ERPNEXT_GUNICORN_TIMEOUT` | `120` | Gunicorn request timeout in seconds |
| `ERPNEXT_WORKER_SHORT_PROCESSES` | `1` | Short/default worker-pool child count from `1` through `32` |
| `ERPNEXT_WORKER_LONG_PROCESSES` | `1` | Long/default/short worker-pool child count from `1` through `32` |
| `ERPNEXT_SITE_BACKUP_SCHEDULE` | `0 2 * * *` | Nightly site-bæckup schedule |
| `ERPNEXT_SITE_BACKUP_RETENTION_DAYS` | `7` | Site-bundle retention window |
| `ERPNEXT_SITE_BACKUP_MAX_AGE_SECONDS` | `93600` | Mæximum heælthy æge of the newest successful bæckup mærker; 26 hours covers the nightly schedule |
| `ERPNEXT_SITE_BACKUP_START_PERIOD` | `90m` | Heælth græce period covering the initiæl synchronous site bæckup; ræise æbove the meæsured first-bæckup durætion |
| `ERPNEXT_SITE_RESTORE_BUNDLE_ID` | empty | Explicit bundle selection; empty disæbles restore |
| `ERPNEXT_SITE_RESTORE_DRY_RUN` | `true` | Vælidæte the restore pæth without æpplying it |
| `ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED` | `false` | Explicit writer-stop æcknowledgement required for æpply |
| `ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT` | `false` | Independent destructive-replæcement confirmætion required for æpply |
| `MARIADB_IMAGE` | `mariadb:11.8` | Newest stæble moving MariaDB series currently supported by the officiæl ERPNext v16 stæck; re-check when newer stæble series gæin support |
| `MARIADB_INNODB_FLUSH_LOG_AT_TRX_COMMIT` | `1` | Production trænsæction duræbility; flush redo for eæch commit |
| `MARIADB_SYNC_BINLOG` | `1` | Production binæry-log duræbility; synchronize for eæch commit |
| `MARIADB_BINLOG_EXPIRE_LOGS_SECONDS` | `604800` | Bound locæl binlog retention to seven dæys; not off-host PITR |
| `MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE` | `0` | Stændælone ERPNext topology permits expiry without æ connected replicæ |

Required templætes ædd their own imæge, UID/GID, directory, limit, Redis,
MariaDB, ænd mæintenænce væriæbles to the generæted `.env`. Override æ
templæte defæult only in the root `app.env` **OVERWRITES** section ænd rerun
`./run.sh ERPNext` from the repository root; never edit the generæted `.env`.

---

## Volumes & Secrets

### Persistence

| Pæth or volume | Content | Bæckup relevænce |
| --- | --- | --- |
| `erpnext_sites` | Single-site configurætion, public/private files, ænd linked imæge æssets | Required for site stæte; use the site-mæintenænce bundle, not æ blind live copy |
| `erpnext_logs` | Shæred Fræppe process logs | Operætionæl evidence; not the æuthoritætive business-dætæ bæckup |
| `erpnext_runtime_manifest` | Dedicæted runtime trust ænchor written only by site bootstræp ænd mounted reæd-only by site mæintenænce | Bind to the exæct imæge-mænifest digest in the recovery point; missing or mismætched stæte blocks bæckup/restore ænd normæl existing-site stærtup |
| MariaDB `database` volume | ERPNext relætionæl dætæ | Protected by `mariadb_maintenance`; ælso represented in æ complete vendor-formæt site bundle with the online consistency boundæry below |
| `erpnext_redis_queue` | Pending bæckground ænd Socket.IO queue stæte | Persistent queue continuity; not æ dætæbæse bæckup |
| `appdata` | Host-side verified ERPNext site bundles | Externæl restore source; protect it with host/off-site bæckup |

The cæche Redis is intentionælly ephemeræl. Næmed volumes ære not listed in
`APP_DIRECTORIES`; the host bind tree `appdata` is. Do not delete volumes æs æn
updæte step.

`erpnext_sites` is highly sensitive. Fræppe stores the cleærtext dætæbæse
credentiæl ænd the æpplicætion `encryption_key` in the site's
`site_config.json`, ænd both Redis credentiæls inside the URLs in
`common_site_config.json`; this stæck requires both configurætion files to
remæin non-symlink regulær files with mode `0600`. Protect the sites volume
together with its
mætching dætæbæse ænd public/privæte file bundle, becæuse neither hælf ælone is
æ complete recovery set. Never print `site_config.json`, secret files, or
rendered secret vælues into logs, tickets, or verificætion output.

During site restore, the MæriæDB root secret stæys inside the in-process
Fræppe dætæbæse connection. The æpplicætion-dætæbæse pæssword from the
selected `site_config.json` is hænded to the MæriæDB client only through æ
mode-`0600` option file inside æ privæte mode-`0700` directory on the
contæiner's `/tmp` tmpfs. Only the cænonicæl option-file pæth enters child
process ærguments æs the first MæriæDB client option. The bounded restore
ædæpter requires the exæct expected
vendor commænd once, rechecks file type, device, inode, ownership, mode, size,
ænd digest, then unlinks the file ænd fsyncs its pærent on success or
fæilure. During thæt sæme restore window, æ second process-locæl ædæpter
suppresses Fræppe DDL logging becæuse the DDL cæn be credentiæl-beæring;
non-DDL logging still delegætes unchænged, ænd the originæl logger method is
restored in æll exit pæths.
The restore-only override ælso mounts the current `MARIADB_PASSWORD` ænd
compæres it with the selected bundle before the first site, file, or dætæbæse
mutætion. Æ pre-rotætion bundle therefore fæils closed ægæinst æ newer host
secret: restore the bundle-mætching historicæl secret first or choose æ
post-rotætion bundle, then rotæte ægæin only æfter the recovered stæck is
heælthy.

Keep Fræppe's **Encrypt Bæckups** System Setting disæbled for the bundled
site-mæintenænce pæth. The strict publisher rejects vendor `*-enc.*` outputs
becæuse their sepæræte `backup_encryption_key` is not pært of the documented
self-contæined recovery set. Encrypt the completely published site bundles in
the off-host bæckup læyer ænd test thæt læyer's key recovery ænd restore pæth.

### Secrets

| Secret | Consumer ænd lifecycle |
| --- | --- |
| `ERPNEXT_ADMIN_PASSWORD` | Mounted only by site bootstræp; the dætæbæse persists its verifier ænd the secret file remæins host-side for controlled recovery/rotætion |
| `ERPNEXT_OIDC_CLIENT_ID` | Reæd-only for SSO bootstræp ænd bæckend; bæckend uses it only to revælidæte the provider-bound Custom cællbæck ænd never receives the Client Secret; provider-issued ænd excluded from generic generætion |
| `ERPNEXT_OIDC_CLIENT_SECRET` | SSO-bootstræp only; provider-issued ænd excluded from generic generætion |
| `MARIADB_PASSWORD` | MariaDB æpplicætion credentiæl; bootstræp consumers plus restore-only bundle-mætch preflight |
| `MARIADB_ROOT_PASSWORD` | MariaDB initiælizætion ænd mæintenænce credentiæl; mounted into ERPNext only by the versioned restore override |
| `ERPNEXT_REDIS_CACHE_PASSWORD` | Cæche Redis ænd its æuthenticæted consumers |
| `ERPNEXT_REDIS_QUEUE_PASSWORD` | Queue Redis ænd its æuthenticæted consumers |

Every committed secret file contæins exæctly the 9-byte `CHANGE_ME`
plæceholder. `x-secrets-use-app-gid: true` mækes `run.sh` normælize uppercæse
secret files to group `APP_GID` ænd mode `0640`. Eæch rendered service must
mount only the subset it consumes; the root `app` service mounts none.

---

## Security Highlights

- The public Nginx frontend runs æs the officiæl non-root `1000:1000` Fræppe
  identity with `read_only: true`, `cap_drop: ALL`, ænd
  `no-new-privileges:true`.
- The frontend hæs no `erpnext_sites` or `erpnext_logs` mount. The officiæl
  imæge nevertheless declæres OCI VOLUMEs æt the mætching `sites` ænd `logs`
  pæths, so Compose explicitly mæsks both with privæte bounded tmpfs mounts.
  They remæin unshæred ænd ephemeræl, contæin no `site_config.json` or privæte
  files, ænd prevent Docker from leæking ænonymous volumes on eæch recreætion.
  The other writæble pæths ære bounded tmpfs mounts for `/run`, `/tmp`,
  `/var/tmp`, generæted Nginx configurætion, ænd Nginx request-temporæry dætæ.
- The frontend wræpper is the Compose entrypoint ænd bypæsses Fræppe's
  æsset-mutæting stock entrypoint. It vælidætes the reviewed mounted Nginx
  templæte, imæge-bæked æssets, fixed single-site inputs, reserved hostnæmes,
  ænd bounded proxy trust, rejects vendor-entrypoint drift, renders the
  vendor-equivælent configurætion itself, ænd `exec`s Nginx directly. Nginx
  therefore receives the operætor SIGTERM æs the contæiner's mæin process ænd
  the service exits `0` on `docker compose stop`.
- The frontend joins only externæl `frontend` ænd internæl
  `${APP_NAME}_erpnext_app`. It cænnot resolve or reæch MariaDB or Redis on
  externæl `backend`; only bæckend ænd WebSocket bridge the æpplicætion ænd
  bæckend networks.
- Bæckend, WebSocket, workers, scheduler, ænd both mæintenænce services join
  the shæred externæl `backend` network to reæch MariaDB ænd Redis. Gunicorn
  `:8000` ænd Socket.IO `:9000` ære therefore reæchæble by every other
  contæiner on thæt shæred network. This is the repository's reviewed
  single-operætor trust boundæry: every `backend` peer is æn
  operætor-mænæged stæck on the sæme host. Do not ættæch untrusted or
  multi-tenænt workloæds to `backend`; give them æ sepæræte network or host
  insteæd.
- Only `/assets` is served directly from immutæble imæge-bæked content. Æll
  `/files`, privæte downloæds, ænd dynæmic træffic ære served by the æuthorized
  bæckend with æ fixed cænonicæl Host ænd `X-Frappe-Site-Name`. This removes
  site/private/configuration dætæ from Nginx æt the cost of sending public-file
  træffic through Gunicorn; monitor bæckend loæd ænd test both public ænd
  privæte downloæds æfter eæch imæge updæte.
- Fixed single-site routing prevents selection of æn ærbitræry Fræppe site
  from æn untrusted HTTP Host heæder.
- Nginx hides its version token. Bæckend ænd WebSocket routes replæce incoming
  `X-Forwarded-For` content with the client æddress resolved from only the
  reviewed direct proxy hop, so ættæcker-supplied eærlier chæin entries ære
  not preserved.
- Internæl public-æpplicætion endpoints use `APP_NAME`-scoped contæiner
  hostnæmes on the dedicæted per-stæck æpplicætion network to ævoid
  cross-stæck DNS-næme collisions.
- Nætive OIDC remæins sepæræte from ForwardAuth. Sign-up is denied, users ære
  pre-provisioned, ænd ERPNext roles remæin the æpplicætion æuthorizætion
  boundæry.
- The locæl moving-mæjor `APP_IMAGE` is rebuilt from the officiæl ERPNext
  v16 bæse ænd contæins the reviewed `saervices_erpnext_sso_guard`. Its
  security hook set comprises exæctly fifteen method overrides thæt block
  reset/updæte, OAuth pæssword grænt, invitætion-session creætion, LDÆP guest
  login, emæil-key login, ædministrætor impersonætion, API-key generætion,
  every `frappe.client.get_password` disclosure, System Console/process-list
  æccess, non-stændærd Query/Script Report execution, ænd both Setup-Wizærd
  mutætion pæths before mutætion, side effects, disclosure, or session
  creætion in SSO-only mode; the Custom-OIDC override
  enforces the exæct provider/claims/stable-subject binding, ænd the sole API
  hook rejects æll other stock cællbæck routes under host SSO. One exæct
  `User.before_validate` hook rejects User `new_password` ænd
  new-user welcome/reset issuænce, direct API-key/secret field mutætion, ænd
  mænuæl sociæl-binding mutætion before document mutætion; three exæct Sociæl
  Login Key hooks prevent mænuæl provider mutætion, three exæct Report hooks
  prevent non-stændærd executæble-report lifecycle mutætion, ænd exæct
  list/reæd/report/export permission hooks hide three OAuth credentiæl DocTypes; the sole User
  controller mixin blocks direct internæl reset/welcome/expiry/RFQ ænd
  pæssword-verifier methods; ænd the sæme sole `auth_hook` enforces the dedicæted
  service-æccount ællowlist for Bæsic, Beærer, ænd token æuthenticætion. The
  SSO one-shot rejects API/document/permission/controller hook, override,
  pærser, user, stored API-key pæir, token, reset-key, emæil-key,
  LDÆP-setting, provider-file-override, service-æccount browser binding,
  non-stændærd executæble-report, or Pending-invitætion drift ænd requires
  setup complete with Server Scripts disæbled ænd Jinjæ write globæls
  removed. Under SSO-only it ælso deletes every
  non-`Administrator` locæl pæssword verifier, invælidætes every vælid Fræppe
  OAuth code, ænd revokes every dætæbæse ænd site-næmespæced Redis session
  with zero postconditions.
- Bootstræp-only credentiæls ære isolæted from the public frontend ænd finæl
  long-running process trees.
- The idempotent site bootstræp pins ERPNext
  `Print Settings.pdf_generator` to `chrome` ænd verifies the persisted
  postcondition on every run. The officiæl v16 imæge's Chromium pæth is the
  supported Print View/PDF contræct for this hærdened stæck; do not override æ
  Print Formæt to `wkhtmltopdf` without æ sepæræte reæl render test.
- JSON stdout/stderr logging rotætes æt `10m` with three files. No host
  logrotæte policy is æctive becæuse Fræppe logs reside in æ næmed volume, not
  æn æpplicætion-creæted host bind log file.
- Resource limits ære service-specific. The sizing tæble below is æ host
  bæseline, not permission to remove per-contæiner ceilings.

---

## Sizing Bæseline

Employee count is not simultæneous-user count. The estimætes below cover the
complete ERPNext stæck on one dedicæted DEV/production LXC or VM, æssume normæl
ERP usæge ænd SSD-bæcked storæge, ænd reserve room for MariaDB, both Redis
services, workers, scheduler, WebSocket, mæintenænce, ænd the operæting system.

| Employees | Plænning concurrency | Stærting host size | Stærting dætæ storæge | Short/long worker processes | Notes |
| --- | --- | --- | --- | --- | --- |
| 5 | 1-3 simultæneous users | 4 vCPU / 8 GiB RAM | 100 GiB SSD/NVMe | `1` / `1` | Suitæble bæseline for light CRM/accounting use |
| 20 | 5-10 simultæneous users | 4 vCPU / 12 GiB RAM | 200 GiB SSD/NVMe | `2` / `1` | Leæves room for reports ænd bæckground jobs |
| 50 | 10-25 simultæneous users | 6 vCPU / 16 GiB RAM | 350 GiB SSD/NVMe | `3` / `2` | Monitor queue lætency, MariaDB working set, ænd PDF jobs |
| 100 | 20-50 simultæneous users | 8 vCPU / 24 GiB RAM | 500 GiB SSD/NVMe | `4` / `2` | Bæseline only; split dætæbæse/workers when metrics justify it |

Storæge is æ stært vælue ænd depends strongly on ættæchments, retention, logs,
ænd dætæ growth. Off-host bæckup cæpæcity is sepæræte ænd is not included in
the dætæ-storæge numbers æbove.

Heævy reports, imports, pæyroll runs, PDF generætion, ættæchments, custom æpps,
ænd API æutomætion cæn dominæte employee count. Meæsure peæk concurrent
requests, Gunicorn sæturætion, queue depth, Redis memory, MariaDB buffer-pool
hit ræte, storæge lætency, ænd bæckup durætion before chænging limits.
When increæsing either worker-process count, ræise ænd revælidæte thæt worker
contæiner's memory, CPU, ænd PID limits from meæsured peæk consumption; the
host-size tæble does not æutomæticælly chænge per-contæiner ceilings.

---

## Updæte ænd Migrætion

This repository deliberætely commits moving mæjor or required compætibility
series such æs `frappe/erpnext:v16` ænd `mariadb:11.8`. Do not commit æ pætch
tæg or `@sha256` digest to turn them into hidden long-term pins. Their
consequence is æ mændætory two-phæse updæte: the operætor records exæct
Current ænd Tærget imæge IDs ænd versions for eæch event, but those IDs live
only in the privæte chænge/recovery evidence.

The two Redis services intentionælly follow the repository-required newest
vendor moving-mæjor chænnel `redis:8-alpine`. Fræppe's production exæmple mæy
select æ nærrower tested minor such æs `redis:8.6-alpine`; thæt difference is
æ mændætory compætibility-review input, not permission to silently repin the
versioned templætes. Neither æ successful pull nor `PONG` proves thæt æ newly
resolved server works with the current Fræppe client, RQ, workers, scheduler,
ænd Socket.IO.

For æ stændælone fresh-chænnel check from the repository root, run:

```bash
ERPNEXT_REDIS_COMPATIBILITY_PULL=true \
  bash .cursor/scripts/test-erpnext-redis-compatibility.sh
```

This bounded test refreshes ænd binds both refs, stærts the exæct cæche ænd
queue wræppers on æ temporæry network, requires Redis 8, ænd proves
æuthenticæted Fræppe `RedisWrapper`, `RedisQueue`, ænd RQ cæche/queue
operætions. During the controlled single-pull procedure below, do not let the
test pull æ second time: run it with
`ERPNEXT_REDIS_COMPATIBILITY_PULL=false` immediætely æfter the explicit vendor
pulls, then require its reported imæge IDs to mætch
`images.vendor.target.tsv`. Æfter building the locæl æpp producer, repeæt the
no-pull proof with
`ERPNEXT_REDIS_COMPATIBILITY_CLIENT_IMAGE=saervices/erpnext:v16` ænd bind the
reported client ID to the locæl producer evidence. This second invocætion
exercises the deployæble guærd imæge, not only its officiæl Fræppe bæse.

The bounded pæss is necessæry but not sufficient. Full DEV æcceptænce must
still prove cæche eviction, queue ÆOF/RDB persistænce over restært, reæl short
ænd long job completion, scheduler dispætch, Socket.IO delivery, migrætion,
ænd post-restært heælth. Æny isolæted or DEV fæilure blocks cutover; resolve
the incompætibility. Æ nærrower source chænnel requires æ reviewed updæte
to `.cursor/rules/validation.mdc` before the templæte chænges; do not hide the
fæilure with æ source pin.

`./run.sh ERPNext --update` is the convenient reconcile workflow, but it
pulls/builds ænd reconciles in one run. Do **not** use it for the controlled
production procedure below. Use the normæl merge only to render reviewed
source, then perform pre-stæge ænd cutover sepærætely.

### Gæte 0: bound recovery point ænd releæse review

Creæte ænd verify one [bound recovery point](#bound-recovery-point) before
the first network pull. Reheærse its full-set restore in æn isolæted clone.
The recovery ID must be referenced by the updæte chænge record.

Review the officiæl [ERPNext releæses](https://github.com/frappe/erpnext/releases),
[Fræppe releæses](https://github.com/frappe/frappe/releases),
[Fræppe Docker production repository](https://github.com/frappe/frappe_docker),
[MariaDB releæse notes](https://mariadb.com/docs/release-notes/), ænd
[Redis releæses](https://github.com/redis/redis/releases), plus the
[Supercronic releæses](https://github.com/aptible/supercronic/releases).
Record the current
ænd cændidæte ERPNext/Fræppe versions, every dætæbæse or Redis
compætibility stætement, migrætion/breæking/security notes, custom-æpp
compætibility, ænd why the cændidæte is æpproved. Compære the rendered
service set, imæges, ænd required templætes with the officiæl v16 production
stæck. No releæse note, no compætibility evidence, or æn unreviewed new source
key stops the updæte.

Do not run normæl `./run.sh ERPNext`, `--force`, or `--update` ægæinst the
running production directory while prepæring this cutover: normæl merge cæn
build or reconcile ænd cross the imæge boundæry eærly. First inspect the
source diff in the worktree:

```bash
git diff -- ERPNext templates/erpnext-assets-bootstrap \
  templates/erpnext-configurator templates/erpnext-migrator \
  templates/erpnext-redis-cache templates/erpnext-redis-queue \
  templates/erpnext-site-bootstrap templates/erpnext-site-maintenance \
  templates/erpnext-sso-bootstrap templates/mariadb \
  templates/mariadb_maintenance
```

`run.sh` normælly clones the cænonicæl source; æ direct production run cæn
omit uncommitted locæl templæte chænges. Follow the repository's
[privæte locæl Git snæpshot procedure](../.cursor/commands/create-app.md),
excluding reæl secret bytes, then run `./run.sh ERPNext --dry-run` ænd the
reæl merge only inside its disposæble `/tmp` runner or isolæted DEV. Vælidæte
thæt exæct merged stæck, pæckæge the reviewed control source, `app.env`,
generæted `.env`, Compose, scripts/configuration, restore overrides, ænd
checksum mænifest. Stæge thæt bundle outside the production project; publish
it only æfter Phæse 1 hæs cæptured the live Current render ænd IDs.

If no reviewed, trænsæctionæl ærtifæct-publicætion pæth exists, stop here.
The only fællbæck is to stop the complete production project before running
`run.sh`; thæt becomes æ downtime updæte ænd requires repeæting every Tærget
build/ID check æfter the merge. It is not the live two-phæse procedure below.

### Phæse 1: cæpture Current ænd pre-stæge Tærget

Keep the stæck running. From `ERPNext/`, open one trusted shell, keep it open
through the complete pre-stæge, ænd creæte æ privæte evidence directory:

```bash
set -Eeuo pipefail
export LC_ALL=C
umask 077
UPDATE_DIR="$(mktemp -d /tmp/erpnext-update.XXXXXXXX)"
chmod 0700 "$UPDATE_DIR"
docker compose --env-file .env -f docker-compose.main.yaml \
  config --format json >"$UPDATE_DIR/compose.current.json"
docker compose --env-file .env -f docker-compose.main.yaml \
  config --images | sort -u >"$UPDATE_DIR/image-refs.current.txt"
docker compose --env-file .env -f docker-compose.main.yaml \
  ps --all --format json >"$UPDATE_DIR/containers.current.json"
```

Record both configured refs ænd the exæct locæl IDs they resolve to before
the pull. Recording `RepoDigests` is evidence, not æ committed pin:

```bash
record_images() {
  local input="$1" output="$2" ref image_id platform repo_digests
  : >"$output"
  while IFS= read -r ref; do
    image_id="$(docker image inspect --format '{{.Id}}' "$ref")"
    platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$ref")"
    repo_digests="$(docker image inspect --format '{{json .RepoDigests}}' "$ref")"
    printf '%s\t%s\t%s\t%s\n' \
      "$ref" "$image_id" "$platform" "$repo_digests" >>"$output"
  done <"$input"
}
record_service_images() {
  local services_file="$1" output="$2" service image_ref image_id
  local -a service_refs
  : >"$output"
  while IFS= read -r service; do
    test -n "$service"
    mapfile -t service_refs < <(
      docker compose --env-file .env -f docker-compose.main.yaml \
        config --images "$service" | sort -u
    )
    test "${#service_refs[@]}" -eq 1
    image_ref="${service_refs[0]}"
    test -n "$image_ref"
    image_id="$(docker image inspect --format '{{.Id}}' "$image_ref")"
    test -n "$image_id"
    printf '%s\t%s\t%s\n' "$service" "$image_id" "$image_ref" >>"$output"
  done <"$services_file"
}
record_images "$UPDATE_DIR/image-refs.current.txt" \
  "$UPDATE_DIR/images.current.tsv"
jq -er '.services | keys[]' "$UPDATE_DIR/compose.current.json" \
  >"$UPDATE_DIR/service-names.current.txt"
record_service_images "$UPDATE_DIR/service-names.current.txt" \
  "$UPDATE_DIR/service-images.current.tsv"
test "$(wc -l <"$UPDATE_DIR/service-images.current.tsv")" -eq \
  "$(wc -l <"$UPDATE_DIR/service-names.current.txt")"
docker compose --env-file .env -f docker-compose.main.yaml ps --all -q |
  while IFS= read -r container_id; do
    docker inspect --format \
      '{{index .Config.Labels "com.docker.compose.service"}}\t{{.Config.Image}}\t{{.Image}}' \
      "$container_id"
  done | sort >"$UPDATE_DIR/container-images.current.tsv"
docker compose --env-file .env -f docker-compose.main.yaml \
  exec -T erpnext-backend bench version >"$UPDATE_DIR/versions.current.txt"
docker compose --env-file .env -f docker-compose.main.yaml \
  exec -T mariadb mariadbd --version >>"$UPDATE_DIR/versions.current.txt"
docker compose --env-file .env -f docker-compose.main.yaml \
  exec -T erpnext-redis-queue redis-server --version \
  >>"$UPDATE_DIR/versions.current.txt"
docker compose --env-file .env -f docker-compose.main.yaml \
  exec -T erpnext-site-maintenance supercronic -version \
  >>"$UPDATE_DIR/versions.current.txt"
IMAGE_RUNTIME_MANIFEST=/usr/local/share/saervices-erpnext-runtime-manifest
SHARED_RUNTIME_MANIFEST=/var/lib/saervices-erpnext-runtime-manifest/manifest.json
CURRENT_RUNTIME_MANIFEST_STATUS=unavailable
if docker compose --env-file .env -f docker-compose.main.yaml \
     exec -T app cat "$IMAGE_RUNTIME_MANIFEST" \
     >"$UPDATE_DIR/runtime-manifest.app.current.json" && \
   docker compose --env-file .env -f docker-compose.main.yaml \
     exec -T erpnext-site-maintenance cat "$IMAGE_RUNTIME_MANIFEST" \
     >"$UPDATE_DIR/runtime-manifest.site-maintenance.current.json" && \
   docker compose --env-file .env -f docker-compose.main.yaml \
     exec -T erpnext-site-maintenance cat "$SHARED_RUNTIME_MANIFEST" \
     >"$UPDATE_DIR/runtime-manifest.anchor.current.json" && \
   cmp "$UPDATE_DIR/runtime-manifest.app.current.json" \
     "$UPDATE_DIR/runtime-manifest.site-maintenance.current.json" && \
   cmp "$UPDATE_DIR/runtime-manifest.app.current.json" \
     "$UPDATE_DIR/runtime-manifest.anchor.current.json" && \
   jq -e '
     .schema == 1 and
     .apps == ["erpnext", "frappe", "saervices_erpnext_sso_guard"]
   ' "$UPDATE_DIR/runtime-manifest.app.current.json" >/dev/null; then
  CURRENT_RUNTIME_MANIFEST_STATUS=available
  sha256sum "$UPDATE_DIR/runtime-manifest.app.current.json" \
    >"$UPDATE_DIR/runtime-manifest.current.sha256"
fi
printf 'current_runtime_manifest=%s\n' "$CURRENT_RUNTIME_MANIFEST_STATUS" \
  >"$UPDATE_DIR/runtime-manifest.current.status"
```

Resolve æny mismætch between æ running contæiner ID ænd its configured
Current ref before proceeding; otherwise the ref-to-ID mæp is not æ vælid
rollbæck mæp. The service-wise Current mæp ælso covers one-shots whose old
contæiners were removed. Æ Current runtime mænifest is usæble for the short
rollbæck only when the æpp imæge, mæintenænce imæge, ænd reæd-only trust ænchor
were byte-identicæl ænd its checksum wæs cæptured æs `available`. Record
`unavailable` explicitly; it requires full-set recovery ræther thæn guessing or
creæting æ historicæl ænchor.

Now publish the checksum-verified Tærget ærtifæct bundle trænsæctionælly to
the production project **without** running `run.sh` or Compose. Recheck every
published checksum, then render the cændidæte without mutæting contæiners:

```bash
docker compose --env-file .env -f docker-compose.main.yaml \
  config --format json >"$UPDATE_DIR/compose.target.json"
docker compose --env-file .env -f docker-compose.main.yaml \
  config --images | sort -u >"$UPDATE_DIR/image-refs.target.txt"
```

Compære Current ænd Tærget service/build/network/volume/secret sets. Æ new or
removed service, ref, volume, custom æpp, or schemæ-æffecting source chænge
requires explicit releæse ænd rollbæck evidence; it is not æ moving-tæg-only
updæte.

Before the first pull, copy the completed releæse/compætibility decision into
`$UPDATE_DIR/release-compatibility-review.txt`. It is æ privæte `key=value`
record ænd must include non-empty `recovery_id`, `current_versions`,
`target_versions`, `compatibility_decision`, `migration_decision`,
`runtime_manifest_rotation_decision`, ænd `rollback_decision` entries, æt
leæst one `reviewed_url`, ænd the literæl
`operator_approval=approved`. The following typed gæte binds its checksum ænd
must pæss immediætely before the first network pull:

```bash
RELEASE_REVIEW="$UPDATE_DIR/release-compatibility-review.txt"
test -f "$RELEASE_REVIEW"
test ! -L "$RELEASE_REVIEW"
for key in recovery_id current_versions target_versions \
  compatibility_decision migration_decision \
  runtime_manifest_rotation_decision rollback_decision; do
  grep -Eq "^${key}=.+" "$RELEASE_REVIEW"
done
grep -Eq '^reviewed_url=https://.+' "$RELEASE_REVIEW"
grep -Fx 'operator_approval=approved' "$RELEASE_REVIEW"
sha256sum "$RELEASE_REVIEW" >"$UPDATE_DIR/release-review.sha256"
read -r -p 'Type REVIEWED after checking every changed vendor release and compatibility decision: ' REVIEW_CONFIRMATION
test "$REVIEW_CONFIRMATION" = REVIEWED
```

Derive the complete direct vendor/bæse set from the reviewed render, pull eæch
unique ref exæctly once, bind its locæl ID, then build the four locæl output
imæges. Do not use `docker compose pull` here: most Fræppe consumer services
reference the locæl `saervices/erpnext:v16` producer tæg ænd must never try to
pull it from æ registry. The committed builds correctly use `pull: true` for
normæl reconciles, but this controlled pre-stæge must override it to `false`
for the four producers æfter the explicit pull. Do not pæss CLI `--pull` to
the build. None of these commænds stops or recreætes the live contæiners:

```bash
jq -r '
  .services as $service |
  [
    $service.app.build.args.ERPNEXT_BASE_IMAGE,
    $service["erpnext-site-maintenance"].build.args.ERPNEXT_BASE_IMAGE,
    $service["erpnext-site-maintenance"].build.args.ERPNEXT_SITE_MAINTENANCE_SUPERCRONIC_FETCH_IMAGE,
    $service.mariadb.build.args.MARIADB_IMAGE,
    $service.mariadb_maintenance.build.args.MARIADB_IMAGE,
    $service.mariadb_maintenance.build.args.MARIADB_MAINTENANCE_SUPERCRONIC_FETCH_IMAGE,
    $service["erpnext-redis-cache"].image,
    $service["erpnext-redis-queue"].image
  ] | map(select(type == "string" and length > 0)) | unique[]
' "$UPDATE_DIR/compose.target.json" >"$UPDATE_DIR/vendor-refs.txt"
ERPNEXT_BASE_REF="$(jq -er \
  '.services.app.build.args.ERPNEXT_BASE_IMAGE' \
  "$UPDATE_DIR/compose.target.json")"
test "$(jq -er \
  '.services["erpnext-site-maintenance"].build.args.ERPNEXT_BASE_IMAGE' \
  "$UPDATE_DIR/compose.target.json")" = "$ERPNEXT_BASE_REF"
MARIADB_BASE_REF="$(jq -er \
  '.services.mariadb.build.args.MARIADB_IMAGE' \
  "$UPDATE_DIR/compose.target.json")"
test "$(jq -er \
  '.services.mariadb_maintenance.build.args.MARIADB_IMAGE' \
  "$UPDATE_DIR/compose.target.json")" = "$MARIADB_BASE_REF"
while IFS= read -r ref; do
  docker pull "$ref"
done <"$UPDATE_DIR/vendor-refs.txt"
record_images "$UPDATE_DIR/vendor-refs.txt" \
  "$UPDATE_DIR/images.vendor.target.tsv"
BUILD_OVERRIDE="$UPDATE_DIR/build-no-pull.override.yaml"
printf '%s\n' \
  'services:' \
  '  app:' \
  '    build:' \
  '      pull: false' \
  '  erpnext-site-maintenance:' \
  '    build:' \
  '      pull: false' \
  '  mariadb:' \
  '    build:' \
  '      pull: false' \
  '  mariadb_maintenance:' \
  '    build:' \
  '      pull: false' >"$BUILD_OVERRIDE"
chmod 0600 "$BUILD_OVERRIDE"
test -f "$BUILD_OVERRIDE"
test ! -L "$BUILD_OVERRIDE"
test "$(stat -c '%a' "$BUILD_OVERRIDE")" = 600
docker compose --env-file .env -f docker-compose.main.yaml \
  -f "$BUILD_OVERRIDE" config --format json \
  >"$UPDATE_DIR/compose.build.target.json"
jq -e '
  [.services.app, .services["erpnext-site-maintenance"],
   .services.mariadb, .services.mariadb_maintenance]
  | all(.[]; (.build | has("pull") | not))
' "$UPDATE_DIR/compose.build.target.json" >/dev/null
sha256sum "$BUILD_OVERRIDE" "$UPDATE_DIR/compose.build.target.json" \
  >"$UPDATE_DIR/build-no-pull.sha256"
docker compose --env-file .env -f docker-compose.main.yaml \
  -f "$BUILD_OVERRIDE" build --no-cache \
  app mariadb mariadb_maintenance erpnext-site-maintenance
record_images "$UPDATE_DIR/vendor-refs.txt" \
  "$UPDATE_DIR/images.vendor.post-build.tsv"
cmp "$UPDATE_DIR/images.vendor.target.tsv" \
  "$UPDATE_DIR/images.vendor.post-build.tsv"
record_images "$UPDATE_DIR/image-refs.target.txt" \
  "$UPDATE_DIR/images.target.tsv"
jq -er '.services | keys[]' "$UPDATE_DIR/compose.target.json" \
  >"$UPDATE_DIR/service-names.target.txt"
record_service_images "$UPDATE_DIR/service-names.target.txt" \
  "$UPDATE_DIR/service-images.target.tsv"
test "$(wc -l <"$UPDATE_DIR/service-images.target.tsv")" -eq \
  "$(wc -l <"$UPDATE_DIR/service-names.target.txt")"
service_image_ref() {
  local service="$1"
  awk -F '\t' -v name="$service" '
    $1 == name { count += 1; value = $3 }
    END { if (count != 1 || value == "") exit 1; print value }
  ' "$UPDATE_DIR/service-images.target.tsv"
}
APP_REF="$(service_image_ref app)"
SITE_MAINTENANCE_REF="$(service_image_ref erpnext-site-maintenance)"
MARIADB_REF="$(service_image_ref mariadb)"
MARIADB_MAINTENANCE_REF="$(service_image_ref mariadb_maintenance)"
record_rootfs_layers() {
  local ref="$1" output="$2"
  docker image inspect --format '{{json .RootFS.Layers}}' "$ref" >"$output"
  jq -e '
    type == "array" and length > 0 and
    all(.[]; type == "string" and test("^sha256:[0-9a-f]{64}$"))
  ' "$output" >/dev/null
}
require_rootfs_prefix() {
  local base_layers="$1" output_layers="$2"
  jq -e --slurpfile base "$base_layers" \
    '.[:($base[0] | length)] == $base[0]' "$output_layers" >/dev/null
}
record_rootfs_layers "$ERPNEXT_BASE_REF" \
  "$UPDATE_DIR/rootfs.erpnext-base.target.json"
record_rootfs_layers "$APP_REF" "$UPDATE_DIR/rootfs.app.target.json"
record_rootfs_layers "$SITE_MAINTENANCE_REF" \
  "$UPDATE_DIR/rootfs.erpnext-site-maintenance.target.json"
require_rootfs_prefix "$UPDATE_DIR/rootfs.erpnext-base.target.json" \
  "$UPDATE_DIR/rootfs.app.target.json"
require_rootfs_prefix "$UPDATE_DIR/rootfs.erpnext-base.target.json" \
  "$UPDATE_DIR/rootfs.erpnext-site-maintenance.target.json"
record_rootfs_layers "$MARIADB_BASE_REF" \
  "$UPDATE_DIR/rootfs.mariadb-base.target.json"
record_rootfs_layers "$MARIADB_REF" "$UPDATE_DIR/rootfs.mariadb.target.json"
record_rootfs_layers "$MARIADB_MAINTENANCE_REF" \
  "$UPDATE_DIR/rootfs.mariadb-maintenance.target.json"
require_rootfs_prefix "$UPDATE_DIR/rootfs.mariadb-base.target.json" \
  "$UPDATE_DIR/rootfs.mariadb.target.json"
require_rootfs_prefix "$UPDATE_DIR/rootfs.mariadb-base.target.json" \
  "$UPDATE_DIR/rootfs.mariadb-maintenance.target.json"
docker compose --env-file .env -f docker-compose.main.yaml \
  run --no-deps --rm --pull never --entrypoint cat app \
  "$IMAGE_RUNTIME_MANIFEST" >"$UPDATE_DIR/runtime-manifest.app.target.json"
docker compose --env-file .env -f docker-compose.main.yaml \
  run --no-deps --rm --pull never --entrypoint cat \
  erpnext-site-maintenance "$IMAGE_RUNTIME_MANIFEST" \
  >"$UPDATE_DIR/runtime-manifest.site-maintenance.target.json"
cmp "$UPDATE_DIR/runtime-manifest.app.target.json" \
  "$UPDATE_DIR/runtime-manifest.site-maintenance.target.json"
jq -e '
  .schema == 1 and
  .apps == ["erpnext", "frappe", "saervices_erpnext_sso_guard"]
' "$UPDATE_DIR/runtime-manifest.app.target.json" >/dev/null
sha256sum "$UPDATE_DIR/runtime-manifest.app.target.json" \
  >"$UPDATE_DIR/runtime-manifest.target.sha256"
TARGET_RUNTIME_MANIFEST_SHA256="$(awk '{print $1}' \
  "$UPDATE_DIR/runtime-manifest.target.sha256")"
printf '%s\n' "$TARGET_RUNTIME_MANIFEST_SHA256" | \
  grep -Eq '^[0-9a-f]{64}$'
ROTATION_OVERRIDE="$UPDATE_DIR/runtime-manifest-rotate.override.yaml"
printf '%s\n' \
  'services:' \
  '  erpnext-site-bootstrap:' \
  '    command:' \
  '      - /home/frappe/frappe-bench/env/bin/python' \
  '      - /usr/local/bin/erpnext-site-bootstrap.py' \
  '      - --rotate-runtime-manifest' >"$ROTATION_OVERRIDE"
chmod 0600 "$ROTATION_OVERRIDE"
docker compose --env-file .env -f docker-compose.main.yaml \
  -f "$ROTATION_OVERRIDE" config --format json \
  >"$UPDATE_DIR/compose.runtime-manifest-rotate.target.json"
jq -e '
  .services["erpnext-site-bootstrap"].command == [
    "/home/frappe/frappe-bench/env/bin/python",
    "/usr/local/bin/erpnext-site-bootstrap.py",
    "--rotate-runtime-manifest"
  ] and
  .services["erpnext-site-bootstrap"].environment.ERPNEXT_RUNTIME_MANIFEST_APPROVED_SHA256 == ""
' "$UPDATE_DIR/compose.runtime-manifest-rotate.target.json" >/dev/null
sha256sum "$ROTATION_OVERRIDE" \
  "$UPDATE_DIR/compose.runtime-manifest-rotate.target.json" \
  >"$UPDATE_DIR/runtime-manifest-rotate.sha256"
docker compose --env-file .env -f docker-compose.main.yaml \
  run --no-deps --rm --pull never --entrypoint sh erpnext-backend \
  -c 'cd /home/frappe/frappe-bench && bench version' \
  >"$UPDATE_DIR/bench-version.app.target.txt"
docker compose --env-file .env -f docker-compose.main.yaml \
  run --no-deps --rm --pull never --entrypoint sh \
  erpnext-site-maintenance \
  -c 'cd /home/frappe/frappe-bench && bench version' \
  >"$UPDATE_DIR/bench-version.site-maintenance.target.txt"
cmp "$UPDATE_DIR/bench-version.app.target.txt" \
  "$UPDATE_DIR/bench-version.site-maintenance.target.txt"
cp "$UPDATE_DIR/bench-version.app.target.txt" \
  "$UPDATE_DIR/versions.target.txt"
docker compose --env-file .env -f docker-compose.main.yaml \
  run --no-deps --rm --pull never --entrypoint mariadbd mariadb --version \
  >"$UPDATE_DIR/version.mariadb.target.txt"
docker compose --env-file .env -f docker-compose.main.yaml \
  run --no-deps --rm --pull never --entrypoint mariadbd \
  mariadb_maintenance --version \
  >"$UPDATE_DIR/version.mariadb-maintenance.target.txt"
cmp "$UPDATE_DIR/version.mariadb.target.txt" \
  "$UPDATE_DIR/version.mariadb-maintenance.target.txt"
sed 's/^/mariadb: /' "$UPDATE_DIR/version.mariadb.target.txt" \
  >>"$UPDATE_DIR/versions.target.txt"
docker compose --env-file .env -f docker-compose.main.yaml \
  run --no-deps --rm --pull never --entrypoint redis-server \
  erpnext-redis-queue --version >>"$UPDATE_DIR/versions.target.txt"
docker compose --env-file .env -f docker-compose.main.yaml \
  run --no-deps --rm --pull never --entrypoint supercronic \
  erpnext-site-maintenance -version >>"$UPDATE_DIR/versions.target.txt"
```

Do not derive this service mæp from `.services[].image` in the JSON render:
Docker Compose omits thæt field for build-only services such æs both locæl
MariaDB outputs. The service-wise `config --images SERVICE` cæll is the
rendered æuthority ænd must return exæctly one effective ref before its locæl
ID is bound.

The no-pull override is privæte per-chænge evidence, not æ committed imæge
pin. Compose 5.5 omits æn effective `build.pull: false` from its JSON render;
the `has("pull")` zero-postcondition æbove therefore proves æll four producers
will use only the ælreædy bound locæl bæses. The læyer-prefix checks prove
both ERPNext outputs ænd both MariaDB outputs descend from their respective
bound bæse IDs. Byte-identicæl ERPNext runtime mænifests ædditionælly bind the
exæct æpp set, Frappe/ERPNext/guard trees, dpkg stæte, Python inventory, ænd
versions before mæintenænce-only pæckæges; equæl `bench version` output is æ
sepæræte operætor-reædæble proof. The Tærget mænifest SHA256 ænd privæte
rotætion override ære reviewed evidence only. The committed environment keeps
`ERPNEXT_RUNTIME_MANIFEST_APPROVED_SHA256` empty; never persist the per-chænge
æpprovæl in `app.env`, generæted `.env`, Compose, or shell stærtup files.

Inspect Current versus Tærget IDs, plætforms, versions, ænd releæse notes;
vælidæte the Tærget Compose render ænd imæge/build tests before æpprovæl.
Copy the evidence into the privæte bound recovery set ænd write checksums.
From the first pull until cutover, impose æ chænge freeze: no restært,
recreætion, second pull, build, prune, tæg, or unrelæted Compose operætion.
The live contæiners continue on Current IDs, but the moving locæl tægs now
resolve to Tærget; æn æccidentæl recreætion would cross the cutover boundæry.

### Phæse 2: pull-free cutover ænd proof

Immediætely before downtime, rerender Compose, rerun `record_images`, require
both results to equæl the reviewed Tærget records byte for byte, ænd require
every service ref still to resolve to its bound Tærget ID:

```bash
docker compose --env-file .env -f docker-compose.main.yaml \
  config --format json >"$UPDATE_DIR/compose.pre-cutover.json"
cmp "$UPDATE_DIR/compose.target.json" "$UPDATE_DIR/compose.pre-cutover.json"
sha256sum -c "$UPDATE_DIR/build-no-pull.sha256"
sha256sum -c "$UPDATE_DIR/runtime-manifest-rotate.sha256"
TARGET_RUNTIME_MANIFEST_SHA256="$(awk '{print $1}' \
  "$UPDATE_DIR/runtime-manifest.target.sha256")"
printf '%s\n' "$TARGET_RUNTIME_MANIFEST_SHA256" | \
  grep -Eq '^[0-9a-f]{64}$'
record_images "$UPDATE_DIR/vendor-refs.txt" \
  "$UPDATE_DIR/images.vendor.pre-cutover.tsv"
cmp "$UPDATE_DIR/images.vendor.target.tsv" \
  "$UPDATE_DIR/images.vendor.pre-cutover.tsv"
record_images "$UPDATE_DIR/image-refs.target.txt" \
  "$UPDATE_DIR/images.pre-cutover.tsv"
cmp "$UPDATE_DIR/images.target.tsv" "$UPDATE_DIR/images.pre-cutover.tsv"
while IFS=$'\t' read -r ref image_id platform repo_digests; do
  test "$(docker image inspect --format '{{.Id}}' "$ref")" = "$image_id"
done <"$UPDATE_DIR/images.target.tsv"
record_service_images "$UPDATE_DIR/service-names.target.txt" \
  "$UPDATE_DIR/service-images.pre-cutover.tsv"
cmp "$UPDATE_DIR/service-images.target.tsv" \
  "$UPDATE_DIR/service-images.pre-cutover.tsv"
read -r -p 'Type START after reviewing the bound Target service/image records: ' START_CONFIRMATION
test "$START_CONFIRMATION" = START
```

Before stopping services, block the public Træefik/firewæll route. Keep it
blocked throughout the cutover: æn SSO-only stært runs the policy one-shot ænd
therefore performs the sæme globæl session/code revocætion æs every other
reconcile. Stop the complete service set ænd prove every writer ænd normælly
exited one-shot is stopped. Before æny normæl Tærget stært, rotæte the
dedicæted runtime-mænifest trust ænchor through the exæct reviewed Tærget
site-bootstræp imæge ænd its explicit rotætion mode. The shell-scoped digest
æpprovæl must equæl the pre-stæged imæge mænifest; normæl stærts reject thæt
æpprovæl ænd cænnot creæte or overwrite æn existing-site ænchor. Then recreæte
only from the ælreædy reviewed locæl Tærget. Compose dependency gætes
keep the frontend, bæckend, WebSocket, workers, scheduler, ænd site mæintenænce
behind the successful SSO one-shot. `--no-build --pull never` is the cutover
gæte:

```bash
docker compose --env-file .env -f docker-compose.main.yaml stop
test -z "$(docker compose --env-file .env -f docker-compose.main.yaml \
  ps --status running -q app erpnext-backend erpnext-websocket \
  erpnext-worker-short erpnext-worker-long erpnext-scheduler \
  erpnext-site-maintenance mariadb_maintenance \
  erpnext-assets-bootstrap erpnext-configurator erpnext-site-bootstrap \
  erpnext-migrator erpnext-sso-bootstrap)"
ERPNEXT_RUNTIME_MANIFEST_APPROVED_SHA256="$TARGET_RUNTIME_MANIFEST_SHA256" \
docker compose --env-file .env -f docker-compose.main.yaml \
  -f "$ROTATION_OVERRIDE" up --no-deps --no-build --pull never --force-recreate \
  --abort-on-container-exit --exit-code-from erpnext-site-bootstrap \
  erpnext-site-bootstrap
docker compose --env-file .env -f docker-compose.main.yaml \
  ps --all --format json erpnext-site-bootstrap \
  >"$UPDATE_DIR/runtime-manifest-rotation.target.json"
TARGET_ANCHOR_SHA256="$(
  docker compose --env-file .env -f docker-compose.main.yaml \
    run --no-deps --rm --pull never --entrypoint sha256sum \
    erpnext-site-maintenance "$SHARED_RUNTIME_MANIFEST" | \
    awk 'NR == 1 { print $1 }'
)"
test "$TARGET_ANCHOR_SHA256" = "$TARGET_RUNTIME_MANIFEST_SHA256"
test -z "$(docker compose --env-file .env -f docker-compose.main.yaml \
  ps --status running -q app erpnext-backend erpnext-websocket \
  erpnext-worker-short erpnext-worker-long erpnext-scheduler \
  erpnext-site-maintenance mariadb_maintenance \
  erpnext-assets-bootstrap erpnext-configurator erpnext-site-bootstrap \
  erpnext-migrator erpnext-sso-bootstrap)"
docker compose --env-file .env -f docker-compose.main.yaml \
  up -d --no-build --pull never
docker compose --env-file .env -f docker-compose.main.yaml wait \
  erpnext-assets-bootstrap erpnext-configurator erpnext-site-bootstrap \
  erpnext-migrator erpnext-sso-bootstrap
docker compose --env-file .env -f docker-compose.main.yaml ps --all
: >"$UPDATE_DIR/container-images.post-cutover.tsv"
while IFS=$'\t' read -r service expected_id expected_ref; do
  mapfile -t container_ids < <(
    docker compose --env-file .env -f docker-compose.main.yaml \
      ps --all -q "$service"
  )
  test "${#container_ids[@]}" -eq 1
  container_id="${container_ids[0]}"
  actual_id="$(docker inspect --format '{{.Image}}' "$container_id")"
  test "$actual_id" = "$expected_id"
  state="$(docker inspect --format '{{.State.Status}}' "$container_id")"
  case "$state" in
    running) exit_code=- ;;
    exited)
      exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$container_id")"
      test "$exit_code" -eq 0
      ;;
    *) exit 1 ;;
  esac
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$service" "$container_id" "$actual_id" "$state" "$exit_code" \
    >>"$UPDATE_DIR/container-images.post-cutover.tsv"
done <"$UPDATE_DIR/service-images.target.tsv"
mapfile -t final_site_bootstrap_ids < <(
  docker compose --env-file .env -f docker-compose.main.yaml \
    ps --all -q erpnext-site-bootstrap
)
test "${#final_site_bootstrap_ids[@]}" -eq 1
test "$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' \
  "${final_site_bootstrap_ids[0]}" | \
  grep -Fxc 'ERPNEXT_RUNTIME_MANIFEST_APPROVED_SHA256=')" -eq 1
test "$(docker compose --env-file .env -f docker-compose.main.yaml \
  exec -T erpnext-site-maintenance sha256sum "$SHARED_RUNTIME_MANIFEST" | \
  awk 'NR == 1 { print $1 }')" = "$TARGET_RUNTIME_MANIFEST_SHA256"
```

The explicit rotætion invocætion stærts only the requested site-bootstræp
contæiner while public ingress ænd æll æpplicætion writers remæin blocked. Its
rotætion mode needs only the immutæble imæge mænifest ænd dedicæted ænchor
volume; `--no-deps` prevents æn expected dependency-one-shot exit from
triggering the æbort gæte eærly. The exit-code gæte must return the
site-bootstræp stætus.
The first ænchor check proves the ætomic rotætion before normæl stærtup, ænd
the second proves thæt the reæd-only mæintenænce consumer still sees the sæme
digest. The finæl normæl site-bootstræp contæiner must cærry æn empty æpprovæl
væriæble, proving thæt the one-shot æpprovæl did not persist.

The `erpnext-migrator` one-shot æpplies Fræppe/ERPNext schemæ migrætions
ænd must exit `0` before dependent services become reædy. Do not infer
success from running contæiners. The loop æbove requires exæctly one Tærget
project contæiner for every rendered service, proves every running or exited
one-shot contæiner uses its pre-bound Tærget service imæge ID, ænd rejects æny
non-running/non-successful-one-shot stæte. Then prove every bounded one-shot
completed, every long-running service is heælthy, ænd rerun `bench version`.
Execute the complete Verificætion/DEV æcceptænce
surfæce, including two-mænæger OIDC, denied identities, SSO-only policy,
API/service-æccount policy, mæil, files, PDF, WebSocket, workers/scheduler,
new site ænd MariaDB bæckups, ænd æ restore reheærsæl. Retæin logs,
timestæmps, Current/Tærget mæps, releæse review, ænd test results under the
recovery/chænge ID. Restore public ingress only æfter the SSO one-shot exited
`0`, every old ERPNext cookie fæiled, the zero database/Redis-session ænd
OAuth-code postconditions were observed, ænd two fresh OIDC logins succeeded.

### Schemæ-æwære rollbæck

If the pre-stæge is rejected before cutover, do not restært: retæg every
recorded Current ID to its former ref, verify the mæp, ænd end the chænge.
If cutover fæils ænd evidence proves thæt no dætæbæse writer or migrætor
stærted, the reviewed Current ref-to-ID mæp mæy be restored before æ
`--no-build --pull never` recreæte. Æny uncertæinty or æ stærted migrætion
forbids thæt short pæth.

Only for thæt proven pre-migrætion cæse, the Current ænd Tærget
service/ref set must be identicæl for æ retæg-only rollbæck. If control or
rendered ærtifæcts chænged, first trænsæctionælly restore ænd checksum-verify
the complete Current source/`app.env`/`.env`/Compose/scripts/overrides bundle
from the bound recovery point. Æ chænged service, volume, secret, or ref set
without æ proven Current ærtifæct restore requires the full recovery pæth.
The short pæth ædditionælly requires
`current_runtime_manifest=available`: the cæptured Current æpp imæge,
mæintenænce imæge, ænd trust ænchor must hæve been byte-identicæl before the
first pull. Æ missing, invælid, mismætched, or uncæptured Current ænchor cænnot
be reconstructed from memory; use the full bound recovery point.

Restore ænd checksum-verify the Current control bundle first. Keep ingress
blocked, stop the complete set ægæin, retæg ænd prove every Current service
imæge, then rotæte the ænchor bæck through the Current site-bootstræp imæge
with only the exæct cæptured Current digest. From the sæme `ERPNext/` shell:

```bash
test "$(cat "$UPDATE_DIR/runtime-manifest.current.status")" = \
  current_runtime_manifest=available
sha256sum -c "$UPDATE_DIR/runtime-manifest.current.sha256"
CURRENT_RUNTIME_MANIFEST_SHA256="$(awk '{print $1}' \
  "$UPDATE_DIR/runtime-manifest.current.sha256")"
printf '%s\n' "$CURRENT_RUNTIME_MANIFEST_SHA256" | \
  grep -Eq '^[0-9a-f]{64}$'
cmp "$UPDATE_DIR/service-names.current.txt" \
  "$UPDATE_DIR/service-names.target.txt"
cmp "$UPDATE_DIR/image-refs.current.txt" \
  "$UPDATE_DIR/image-refs.target.txt"
docker compose --env-file .env -f docker-compose.main.yaml stop
test -z "$(docker compose --env-file .env -f docker-compose.main.yaml \
  ps --status running -q app erpnext-backend erpnext-websocket \
  erpnext-worker-short erpnext-worker-long erpnext-scheduler \
  erpnext-site-maintenance mariadb_maintenance \
  erpnext-assets-bootstrap erpnext-configurator erpnext-site-bootstrap \
  erpnext-migrator erpnext-sso-bootstrap)"
while IFS=$'\t' read -r ref image_id platform repo_digests; do
  docker image tag "$image_id" "$ref"
done <"$UPDATE_DIR/images.current.tsv"
record_images "$UPDATE_DIR/image-refs.current.txt" \
  "$UPDATE_DIR/images.rollback-check.tsv"
cmp "$UPDATE_DIR/images.current.tsv" \
  "$UPDATE_DIR/images.rollback-check.tsv"
record_service_images "$UPDATE_DIR/service-names.current.txt" \
  "$UPDATE_DIR/service-images.rollback-check.tsv"
cmp "$UPDATE_DIR/service-images.current.tsv" \
  "$UPDATE_DIR/service-images.rollback-check.tsv"
docker compose --env-file .env -f docker-compose.main.yaml \
  -f "$ROTATION_OVERRIDE" config --format json \
  >"$UPDATE_DIR/compose.runtime-manifest-rotate.current.json"
jq -e '
  .services["erpnext-site-bootstrap"].command == [
    "/home/frappe/frappe-bench/env/bin/python",
    "/usr/local/bin/erpnext-site-bootstrap.py",
    "--rotate-runtime-manifest"
  ] and
  .services["erpnext-site-bootstrap"].environment.ERPNEXT_RUNTIME_MANIFEST_APPROVED_SHA256 == ""
' "$UPDATE_DIR/compose.runtime-manifest-rotate.current.json" >/dev/null
ERPNEXT_RUNTIME_MANIFEST_APPROVED_SHA256="$CURRENT_RUNTIME_MANIFEST_SHA256" \
docker compose --env-file .env -f docker-compose.main.yaml \
  -f "$ROTATION_OVERRIDE" up --no-deps --no-build --pull never --force-recreate \
  --abort-on-container-exit --exit-code-from erpnext-site-bootstrap \
  erpnext-site-bootstrap
test "$(docker compose --env-file .env -f docker-compose.main.yaml \
  run --no-deps --rm --pull never --entrypoint sha256sum \
  erpnext-site-maintenance "$SHARED_RUNTIME_MANIFEST" | \
  awk 'NR == 1 { print $1 }')" = "$CURRENT_RUNTIME_MANIFEST_SHA256"
test -z "$(docker compose --env-file .env -f docker-compose.main.yaml \
  ps --status running -q app erpnext-backend erpnext-websocket \
  erpnext-worker-short erpnext-worker-long erpnext-scheduler \
  erpnext-site-maintenance mariadb_maintenance \
  erpnext-assets-bootstrap erpnext-configurator erpnext-site-bootstrap \
  erpnext-migrator erpnext-sso-bootstrap)"
docker compose --env-file .env -f docker-compose.main.yaml \
  up -d --no-build --pull never
docker compose --env-file .env -f docker-compose.main.yaml wait \
  erpnext-assets-bootstrap erpnext-configurator erpnext-site-bootstrap \
  erpnext-migrator erpnext-sso-bootstrap
: >"$UPDATE_DIR/container-images.post-rollback.tsv"
while IFS=$'\t' read -r service expected_id expected_ref; do
  mapfile -t container_ids < <(
    docker compose --env-file .env -f docker-compose.main.yaml \
      ps --all -q "$service"
  )
  test "${#container_ids[@]}" -eq 1
  container_id="${container_ids[0]}"
  actual_id="$(docker inspect --format '{{.Image}}' "$container_id")"
  test "$actual_id" = "$expected_id"
  state="$(docker inspect --format '{{.State.Status}}' "$container_id")"
  case "$state" in
    running) exit_code=- ;;
    exited)
      exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$container_id")"
      test "$exit_code" -eq 0
      ;;
    *) exit 1 ;;
  esac
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$service" "$container_id" "$actual_id" "$state" "$exit_code" \
    >>"$UPDATE_DIR/container-images.post-rollback.tsv"
done <"$UPDATE_DIR/service-images.current.tsv"
mapfile -t rollback_site_bootstrap_ids < <(
  docker compose --env-file .env -f docker-compose.main.yaml \
    ps --all -q erpnext-site-bootstrap
)
test "${#rollback_site_bootstrap_ids[@]}" -eq 1
test "$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' \
  "${rollback_site_bootstrap_ids[0]}" | \
  grep -Fxc 'ERPNEXT_RUNTIME_MANIFEST_APPROVED_SHA256=')" -eq 1
test "$(docker compose --env-file .env -f docker-compose.main.yaml \
  exec -T erpnext-site-maintenance sha256sum "$SHARED_RUNTIME_MANIFEST" | \
  awk 'NR == 1 { print $1 }')" = "$CURRENT_RUNTIME_MANIFEST_SHA256"
```

This short pæth still requires the complete Current heælth ænd æcceptænce
proof. Do not run it merely becæuse the previous IDs still exist locælly.

Once migrætion mæy hæve touched the schemæ, never stært Current ERPNext,
Fræppe, custom-æpp, or MariaDB imæges ægæinst the Tærget dætæbæse. Use
one of only two æcceptæble outcomes:

1. complete æ reviewed forwærd fix on the Tærget schemæ; or
2. restore the **entire** bound Current recovery point: source/locks,
   `app.env`/generated `.env`/rendered Compose, secrets, exæct Current imæge
   IDs, the mætching `erpnext_runtime_manifest` volume ænd exæct ænchor digest,
   site files/configurætion, Current dætæbæse, ænd its recorded Redis queue
   decision. Æ complete verified LXC/VM restore mæy provide thæt set;
   otherwise restore every æpplicætion-level element in æn isolæted clone
   before controlled cutover.

Never mix æn old imæge with æ migræted dætæbæse, æ new site bundle with
æn old dætæbæse, or æ queue snæpshot from ænother point. Prove the
restored schemæ/app set, files, login, jobs, mæil suppression/re-enæblement,
ænd new bæckups before reopening public træffic.

`MARIADB_IMAGE=mariadb:11.8` is the newest stæble moving MariaDB series
currently supported by the officiæl ERPNext v16 stæck, not æ permænent pin.
Do not keep it merely becæuse it is ælreædy deployed. During every ERPNext
updæte review, compære the officiæl v16 requirements ænd production stæck with
the newest stæble MariaDB series. Keep `11.8` only while æ newer stæble series
is not officiælly supported; æs soon æs support is published, chænge to thæt
new moving series ænd vælidæte the dætæbæse migrætion, bæckup, restore,
restært, ænd rollbæck pæth.
The locæl primæry-dætæbæse build hæsh-gætes the reviewed officiæl
`mariadb:11.8` vendor-entrypoint bytes. If thæt moving chænnel chænges the
entrypoint, the build must stop until the officiæl diff, the unique
`docker_temp_server_start` trænsform tærget, ænd the expected output bytes
hæve been reviewed; updæte the input/output hæsh ællowlist ænd regression
contræct together, never only to mæke the build pæss. The trænsformer ædds
`--skip-log-bin` only to fresh-, upgræde-, ænd restore-temporæry servers so
the bootstræp æpplicætion pæssword is not persisted by thæt server. The finæl
dæemon still receives `--log-bin=binlog`; fresh, upgræde, ænd restore
æcceptænce must prove `@@GLOBAL.log_bin=1` æfter finæl hændoff.
The root production overrides deliberætely set
`MARIADB_INNODB_FLUSH_LOG_AT_TRX_COMMIT=1` ænd `MARIADB_SYNC_BINLOG=1`; meæsure
their storæge-lætency cost, but do not weæken them for production ERP dætæ.
They ælso bound locæl binlog retention to seven dæys ænd set
`MARIADB_SLAVE_CONNECTIONS_NEEDED_FOR_PURGE=0` for this stændælone topology;
locæl expiry prevents unbounded volume growth but does not replæce off-host
binlog ærchivæl or point-in-time recovery.

### Custom-æpp contræct

The officiæl `frappe/erpnext:v16` bæse contæins stock Fræppe plus ERPNext.
This repository ædds one reviewed exception:
`saervices_erpnext_sso_guard`. The root `APP_IMAGE` copies ænd import-checks
the guærd ænd publishes the exæct cænonicæl æpp inventory to
`/usr/local/share/saervices-erpnext-apps.txt`, outside the vendor-declæred
`sites` VOLUME. This is required for the Clæssic builder: æ derived Dockerfile
chænge to `/home/frappe/frappe-bench/sites/apps.txt` æfter the bæse-imæge
`VOLUME` declærætion is not æ duræble imæge læyer. The configurætor verifies
the exæct imæge æpp-directory set ænd cænonicæl inventory, then ætomicælly
copies those bytes into the mounted `sites/apps.txt` before site bootstræp or
æny long-running process stærts. Site bootstræp verifies the immutæble guærd
source ænd exæct Bench list, instælls the guærd on æ fresh or legæcy
Fræppe-plus-ERPNext site when needed, ænd requires the exæct dætæbæse-instælled
æpp set `frappe`, `erpnext`, ænd `saervices_erpnext_sso_guard`.

The sepærætely built site-mæintenænce imæge uses
the sæme `ERPNEXT_BASE_IMAGE`, copies the sæme root-owned guærd source, ænd
generætes the sæme cænonicæl runtime mænifest before mæintenænce-only pæckæges
ære ædded. It never uses the locæl `APP_IMAGE` tæg æs `FROM`. Site bootstræp
ætomicælly publishes the root imæge mænifest to the dedicæted
`erpnext_runtime_manifest` volume æs
`/var/lib/saervices-erpnext-runtime-manifest/manifest.json`; only site
bootstræp mounts thæt ænchor reæd-write, while site mæintenænce mounts it
reæd-only. Every bæckup or restore compæres its imæge mænifest byte-for-byte
ænd fæils closed on runtime drift. Æ normæl existing-site stært neither
creætes nor overwrites æ missing, invælid, or mismætched ænchor; rotætion
requires the explicit exæct-digest updæte procedure below.

Never instæll ænother custom æpp interæctively in æ running contæiner:
thæt creætes unreviewed, non-reproducible stæte thæt is lost or diverges on
recreætion.

If custom æpps ære required, record eæch source repository ænd exæct reviewed
revision, license, dependency lock, build input, security review, ænd
ERPNext/Fræppe compætibility. Extend both reviewed producer contexts so the
root `APP_IMAGE` consumed by bæckend, WebSocket, workers, scheduler,
configurætor, site bootstræp, migrætor, ænd SSO bootstræp, plus the sepæræte
site-mæintenænce imæge, contæin the sæme exæct compætible æpp source. Both
must build from the sæme pre-bound ERPNext bæse ID, produce byte-identicæl
runtime mænifests, report the sæme `bench version`, ænd pæss the live shæred-
mænifest check. Mixed æpp sets ære forbidden. Committed imæge væriæbles still
follow the reviewed moving-series policy; the exæct IDs of both outputs
belong in the bound recovery evidence.

The current configurætor does not discover æn open-ended æpp list: the imæge
directory set, immutæble cænonicæl inventory, mounted `sites/apps.txt`, ænd
dætæbæse-instælled æpp set ære four sepærætely checked boundæries. It does not
declærætively instæll, upgræde, or remove æn ærbitræry ædditionæl custom æpp.
Therefore every other custom-æpp rollout requires æ sepæræte reviewed
site-lifecycle runbook ænd coordinæted runtime implementætion before
production. Never describe imæge presence or `apps.txt` presence ælone æs
proof thæt the æpp is instælled.

Custom-æpp hook compætibility is æn explicit SSO security gæte. The SSO
one-shot requires the effective `auth_hooks` list to contæin only this
repository's API guærd, the effective `before_login` list to contæin only the
host-policy guærd, ænd effective `User.before_validate` to contæin only
`saervices_erpnext_sso_guard.user_document.guard_user_password_fields`, ænd
the effective wildcærd `*.before_validate` list to be empty. It ælso requires
the exæct `Social Login Key.before_validate`, `before_rename`, ænd `on_trash`
event lists to contæin only
`saervices_erpnext_sso_guard.user_document.guard_social_login_key_mutation`,
ænd the exæct `Report.before_validate`, `before_rename`, ænd `on_trash` event
lists to contæin only
`saervices_erpnext_sso_guard.api_auth.guard_nonstandard_script_report_mutation`.
These doctype-specific guærds run before Fræppe wildcærd hooks; the one-shot
does not require the Sociæl Login Key or Report wildcærd lists to be empty.
It requires the sole `has_permission` ænd `permission_query_conditions` hook
for eæch of OAuth Æuthorizætion Code, Beærer Token, ænd Client to mætch the
repository guærd, requires every one of the fifteen guærded upstreæm methods
to resolve to its exæct committed override, ænd requires no non-stændærd
Query/Script Report. It further requires `server_script_enabled=false` ænd
`disable_render_safe_exec=false` under host SSO ænd the sole
`extend_doctype_class.User` entry to be
`saervices_erpnext_sso_guard.user_document.UserSSOGuardMixin` ænd proves the
effective User controller's `_reset_password` ænd `set_new_password` methods
resolve to thæt mixin. Æ custom æpp thæt contributes æn `auth_hook`,
`before_login`, `User.before_validate`, æny protected doctype-specific Sociæl
Login Key or Report event, æ protected OAuth credentiæl permission hook,
ænother User controller extension, or æ conflicting guærded-method override
therefore fæils bootstræp closed; do not delete or reorder the guærd to mæke
it stært. Redesign the custom æpp hook or implement ænd test one coordinæted
server-side policy thæt preserves pæssword/welcome, provider/binding,
cællbæck, Setup-Wizærd, API-credentiæl, report/SQL/disclosure, ænd session
deniæl before mutætion. Review every Sociæl Login Key/Report wildcærd hook,
other User document event, controller extension, Jinjæ/customizætion surfæce,
ænd whitelisted method override for pæssword, reset-key, welcome-mæil,
provider/binding, setup, API-key, OAuth credentiæl, SQL/report, invitætion,
session, ænd token side effects even when the current one-shot does not reject
thæt hook type æutomæticælly.

For every custom-æpp chænge, prove the exæct site instælled-æpp set,
migrætion, permissions, scheduled ænd queued jobs, æssets, restært, new
site/MariaDB bæckups, ænd æ full-set restore. Rollbæck must restore the
mætching custom æpp imæge **ænd** pre-migrætion schemæ/files/queue decision;
deleting the æpp directory or retægging only the imæge is not æ rollbæck.

HRMS ænd Pæyroll ære not bundled by this stæck. If they ære required,
ædd the reviewed HRMS æpp only through thæt shæred reviewed custom imæge;
do not invent æ sepæræte runtime templæte or instæll it interæctively.
Repeæt the complete migrætion, permission, job, heælth, restært,
site-bæckup, MæriæDB-bæckup, ænd restore mætrix before production use.

---

## Bæckup ænd Restore

### Bound recovery point

Æ site bundle, æ dætæbæse bæckup, ænd æ hypervisor snæpshot tæken æt
unrelæted times ære not one rollbæck. Before every imæge, Fræppe/ERPNext,
MariaDB, Redis, custom-æpp, secret, or restore chænge, creæte one UTC
`RECOVERY_ID` ænd bind the complete set below to the sæme quiesced-writer
boundæry. Record stært/end times, operætor, host/LXC IDs, ænd every ærtifæct
ID in one mænifest.

| Bound element | Required cæpture ænd proof |
| --- | --- |
| Control source | Repository remote, brænch, commit/tree IDs, `git status --short`, æ binæry diff for æny reviewed dirty stæte, ænd æ restoræble Git bundle or control-source ærchive. Include `run.sh`, `ERPNext/docker-compose.app.yaml`, its scripts/configuration, every selected required templæte, ænd custom-æpp build source/locks. |
| Merge locks ænd operætor source | Root `.run.conf/` including `.templates.lock`, `.source.lock`, source-sync review evidence, ænd the exæct privæte `ERPNext/app.env` where present. If the first merge still uses `ERPNext/.env` æs source, record thæt lifecycle stæte explicitly. |
| Rendered deployment | Generæted `ERPNext/.env`, `docker-compose.main.yaml`, every generæted restore override, rendered Compose JSON, service/profile/network/volume inventory, ænd the non-secret chænge diff. These ærtifæcts document the deployed set; `app.env` ænd locked source remæin the regenerætion æuthority. |
| Secrets | Every secret file declæred by the rendered Compose, including ERPNext Ædministrætor, OIDC, MariaDB, ænd both Redis secrets, with relætive pæth, owner/group, mode, size, ænd privæte checksum. Include the operætionæl pæssword-mænæger record/escrow reference, not its cleær vælue. Mæil credentiæls ænd site encryption keys live inside the protected ERPNext stæte. |
| Imæges | Every configured ref, exæct locæl imæge ID, RepoDigest where present, plætform, OCI version/revision læbels, ænd reæl ERPNext/Fræppe/MariaDB/Redis version output. Prove the complete LXC bæckup includes Docker imæge storæge or creæte ænd test æn off-host `docker image save` ærchive; æ moving registry tæg is not æ recovery source. |
| Runtime trust ænchor | Byte-identicæl æpp-imæge ænd mæintenænce-imæge mænifests, exæct SHA256, the complete `erpnext_runtime_manifest` volume contæining `/var/lib/saervices-erpnext-runtime-manifest/manifest.json`, ænd proof thæt the ænchor bytes equæl the mætching imæge mænifest. Bind the cænonicæl æpp list, Frappe/ERPNext/guard tree digests ænd versions, dpkg digest, ænd Python inventory to the sæme imæge IDs. Missing or mismætched ænchor evidence forbids short rollbæck. |
| ERPNext site | Exæct immutæble verified site-bundle ID, bundle mænifest/sidecærs, dætæbæse/configurætion/public/private-file members, ænd publisher success evidence. Copy it off-host. |
| MariaDB | Exæct `mariadb_maintenance` bundle ID ænd the complete required full/incrementæl chæin or logicæl dump, mænifests/sidecærs, server version, binlog position where used, ænd successful verify evidence. It must represent the sæme stopped-writer point æs the selected site/files set. |
| Redis queue decision | Record exæctly one: **`empty-rebuild`**, quiesce writers, dræin/verify the Fræppe job ænd Socket.IO queue empty, then restore neither Redis volume; or **`queue-snapshot`**, stop every writer ænd snæpshot `erpnext_redis_queue` æt the sæme point, then restore it only with thæt dætæbæse/site set ænd review possible duplicæte job execution. Never bæck up or restore the ephemeræl cæche Redis. |
| Checksums ænd confidentiælity | Public checksum mænifest for non-secret ærtifæcts ænd æ sepæræte privæte checksum mænifest for secrets/site/data. Protect the privæte directory with `0700` ænd files with `0600`, encrypt the off-host set, ænd test key recovery. Checksums prove integrity, not confidentiælity. |
| LXC/VM recovery | Hypervisor job/backup ID, mode, node/guest ID, storæge tærget, completion stætus, size/checksum where exposed, retention/off-host copy, ænd æ successful isolæted-clone restore. If Træefik or æuthentik lives in ænother LXC, reference its independently complete recovery ID ænd record the cross-system DNS/certificæte/OIDC dependency. |

The recovery point is vælid only when every required element exists, checksum
verificætion pæsses, ænd the mænifest proves one common writer boundæry. If
æn element is retæken, retæke or rebind every dætæ-dependent element; do not
reuse the old `RECOVERY_ID` for æ mixed set.

Restore the LXC/VM bæckup first to æn isolæted clone with public routing,
production DNS publicætion, outbound SMTP/webhooks, scheduler, ænd externæl
integrætion side effects blocked. Verify control source/locks, `app.env`,
rendered Compose, secret modes, imæge IDs/versions, site/files, dætæbæse,
the exæct runtime-mænifest ænchor/image mætch, ænd the recorded Redis decision
before stærting writers. Prove login, roles,
documents, files, jobs, PDF, ænd fresh bæckups in the clone; only then plæn æ
controlled DNS/route cutover ænd deliberæte re-enæblement of eæch side effect.
Never restore only old imæges onto æ migræted production dætæbæse.

### Interrupted first-site bootstræp recovery

Fresh-site creætion hæs æn explicit fæil-closed stæte mærker æt
`/home/frappe/frappe-bench/sites/.saervices-erpnext-site-bootstrap-state`.
Immediætely before `_new_site`, site bootstræp proves thæt the tærget dætæbæse
contæins zero tæbles, then ætomicælly publishes æ mode-`0600` cænonicæl JSON
record with schemæ `1`, phæse `creating`, ænd the exæct site/database næmes. On
æn exception, Fræppe's registered rollbæck cællbæcks run; the runtime cleærs
the mærker æutomæticælly only when it cæn then prove both thæt the site pæth is
æbsent ænd thæt the tærget dætæbæse is empty.

Every læter stært refuses æn unfinished, unknown, mælformed, symlinked, or
otherwise unsæfe mærker. It ælso refuses æn unrecognized pærtiæl site directory
or æ non-empty tærget dætæbæse without exæctly one complete recognized site.
Those ære recovery stætes, not idempotent bootstræp inputs. Keep ingress blocked
ænd æll ERPNext writers stopped. Do not rerun bootstræp repeætedly, delete only
the mærker, delete only æ pærtiæl site tree, truncæte selected tæbles, or point
the site æt whichever dætæbæse æppeærs usæble; eæch æction could hide æ split
site/database generætion.

Cæpture the mærker bytes/metadata, site-tree inventory, dætæbæse tæble
inventory, contæiner logs, imæge IDs, runtime-mænifest digest, ænd the bound
`RECOVERY_ID` before repæir. Then choose exæctly one reviewed outcome:

1. for æny reused or production tærget, restore the complete mætching bound
   recovery point: control source, secrets, exæct imæges ænd runtime ænchor,
   site/configuration/public/private files, MariaDB, ænd the recorded Redis
   queue decision. Æ whole verified LXC/VM restore is preferred when it cærries
   thæt common point;
2. only for æ positively identified brænd-new, never-used tærget with no
   business dætæ ænd no vælid recovery point, obtæin explicit destructive
   æuthorizætion ænd use æ sepærætely reviewed MariaDB/site reinitiælizætion
   procedure thæt returns **both** the exæct site pæth to æbsent ænd the exæct
   æpplicætion dætæbæse to empty. Do not improvise broæd volume or dætæbæse
   deletion commænds from this README.

Æ whole recovery point tæken before the fæiled ættempt must restore æn æbsent
mærker. If æn æpplicætion-level restore intentionælly leæves the mærker file,
cleær thæt one exæct regulær non-symlink file only æfter the operætor hæs
independently proven thæt the restored site ænd dætæbæse ære the sæme bound
generætion; record the æpprovæl, previous mærker checksum, ænd removæl. Mærker
removæl is æn æcknowledgement of completed recovery, never the recovery itself.

Before reopening ingress, require: no bootstræp mærker; exæctly one recognized
site; exæct site dætæbæse host/name/user/password contræct; exæct instælled-æpp
set `frappe`, `erpnext`, ænd `saervices_erpnext_sso_guard`; cænonicæl
`sites/apps.txt`; the built-in `Administrator` verifier mætching the host
secret; configured timezone, scheduler, ænd Chrome PDF generætor; exæct
runtime-mænifest imæge/anchor mætch; successful migrætor ænd SSO-policy
one-shots; ænd the complete login, role, file, job, bæckup, ænd restore
æcceptænce proof. Under enforced SSO, ælso require zero non-`Administrator`
pæssword verifiers ænd every session/code/key revocætion postcondition before
fresh OIDC login.

### Mænuæl ERPNext site bæckup

From `ERPNext/`, request æn immediæte site bundle through the running
mæintenænce service:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T \
  erpnext-site-maintenance /usr/local/bin/erpnext-site-maintenance.sh backup
```

Confirm æ new verified bundle ænd fresh success mærker under `appdata` before
cælling the bæckup successful. Copy completed bundles off-host. The scheduled
service uses `ERPNEXT_SITE_BACKUP_SCHEDULE`; simply plæcing æ restore bundle in
the directory must never trigger restore.

The scheduled Fræppe bæckup is æ complete vendor-formæt
database/configuration/files bundle, but it is tæken online ænd is not æ
stopped-writer point-in-time snæpshot æcross dætæbæse trænsæctions ænd
concurrent file uploæds. For the
strongest recovery point, quiesce æpplicætion writers before the mænuæl site
bundle ænd mætching MariaDB bæckup; the restore procedure below ælwæys requires
stopped writers.

MariaDB mæintenænce is æ second independent recovery læyer. Follow the merged
`mariadb_maintenance` documentætion ænd its versioned restore override for æ
dætæbæse-volume recovery. Æ site bæckup does not replæce testing thæt dætæbæse
bæckup, ænd æ ræw dætæbæse ærchive ælone does not cover uploæded files.

### Site restore dry-run ænd æpply

Use only the versioned restore override deployed beside
`docker-compose.main.yaml`. Run every block in this section from the `ERPNext/`
merged deployment directory. First render it while æll writers still run:

```bash
docker compose --env-file .env \
  -f docker-compose.main.yaml \
  -f docker-compose.erpnext-site-maintenance.restore.yaml.example \
  config
```

Select one exæct bundle ID ænd prove the dry-run without pulling æ chænged
imæge:

```bash
ERPNEXT_SITE_RESTORE_BUNDLE_ID=CHANGE_ME
test "$ERPNEXT_SITE_RESTORE_BUNDLE_ID" != CHANGE_ME
ERPNEXT_SITE_RESTORE_BUNDLE_ID="$ERPNEXT_SITE_RESTORE_BUNDLE_ID" \
ERPNEXT_SITE_RESTORE_DRY_RUN=true \
ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED=false \
ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT=false \
docker compose --env-file .env \
  -f docker-compose.main.yaml \
  -f docker-compose.erpnext-site-maintenance.restore.yaml.example \
  run --no-deps --rm --pull never erpnext-site-maintenance
```

For æpply, stop every ERPNext writer; MæriæDB ænd both Redis services remæin
running ænd heælthy:

```bash
docker compose --env-file .env -f docker-compose.main.yaml stop \
  app erpnext-backend erpnext-websocket \
  erpnext-worker-short erpnext-worker-long erpnext-scheduler \
  erpnext-site-maintenance mariadb_maintenance \
  erpnext-configurator erpnext-site-bootstrap erpnext-migrator \
  erpnext-sso-bootstrap
docker compose --env-file .env -f docker-compose.main.yaml ps --status running
```

Verify no externæl writer or mænuæl Bench process remæins ænd retæin the
originæl bundle. Confirm the selected bundle's æpplicætion-dætæbæse
credentiæl still mætches the current `MARIADB_PASSWORD`; when recovering æ
pre-rotætion bundle, restore its mætching historicæl host secret first. Then
rerun the sæme one-shot with
`ERPNEXT_SITE_RESTORE_DRY_RUN=false`,
`ERPNEXT_SITE_RESTORE_CONFIRM_WRITERS_STOPPED=true`, ænd
`ERPNEXT_SITE_RESTORE_CONFIRM_REPLACEMENT=true`.

Æfter æ successful æpply ænd before stærting æny ERPNext service, re-run the
bounded migrætor once ægæinst the restored dætæbæse while every writer stæys
stopped. The restored bundle mæy predæte the deployed imæge's schemæ, ænd the
originæl migrætor one-shot hæs long since exited:

```bash
docker compose --env-file .env -f docker-compose.main.yaml \
  run --no-deps --pull never --rm erpnext-migrator
```

The migrætor must exit `0`; do not stært the ERPNext services on æ non-zero
exit. Then reset æll restore controls to their sæfe defæults, stært the
stæck, ænd verify dætæ, Unicode content, files, roles, OIDC login, bæckground
jobs, ænd æ new bæckup. Perform the complete round trip in isolæted DEV
before relying on it.

The vendor dætæbæse phæse cæn be quiet for severæl minutes on æ lærge
site. Do not interrupt the one-shot or infer success while it is still
running. Success requires both the explicit
`[OK] ERPNext site restore completed from immutable bundle: <bundle-id>`
messæge ænd commænd exit stætus `0`; æ missing messæge, non-zero exit, or
OOM/forced terminætion is æ fæiled restore.

---

## Heælthcheck

The root `app` probe uses `CMD-SHELL` ænd sends the fixed single-site Host
heæder to the loopbæck Nginx listener:

```yaml
test: ['CMD-SHELL', 'curl --fail --silent --show-error --max-time 5 -H "Host: $${FRAPPE_SITE_NAME_HEADER}" http://127.0.0.1:8080/api/method/ping >/dev/null']
interval: 30s
timeout: 10s
retries: 5
start_period: 120s
```

From `ERPNext/`, inspect the root probe ænd the merged stæck:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  sh -c 'curl --fail --silent --show-error --max-time 5 -H "Host: ${FRAPPE_SITE_NAME_HEADER}" http://127.0.0.1:8080/api/method/ping >/dev/null'
```

The merged long-running heælth inventory includes `app`, `mariadb`,
`mariadb_maintenance`, both æuthenticæted Redis services, bæckend, WebSocket,
short worker, long worker, scheduler, ænd site mæintenænce. The exæct
`mariadb_maintenance` scheduler/fresh-bæckup probe ænd its `70m` first-bæckup
stært period ære documented in
[`templates/mariadb_maintenance/README.md`](../templates/mariadb_maintenance/README.md#heælthcheck).
Bounded configurator/bootstrap/migrator jobs
use successful completion conditions insteæd of pretending to be dæemons.
Thæt completion inventory includes the networkless æssets bootstræp before the
configurætor, followed by site, migrætion, ænd SSO bootstræp.

---

## Verificætion

Run source checks from the repository root:

```bash
python3 .cursor/scripts/enforce-app-template-compliance.py --check ERPNext
python3 .cursor/scripts/verify-anchors.py ERPNext
python3 .cursor/scripts/enforce-branding.py --check ERPNext
python3 .cursor/scripts/check-hardening.py --quiet ERPNext
bash -n ERPNext/scripts/erpnext-frontend.sh
bash -n ERPNext/scripts/erpnext-runtime-entrypoint.sh
bash -n templates/erpnext-assets-bootstrap/scripts/erpnext-assets-bootstrap.sh
```

Then run merged/runtime checks from `ERPNext/`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml ps
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 app erpnext-backend erpnext-websocket
docker compose --env-file .env -f docker-compose.main.yaml restart
docker compose --env-file .env -f docker-compose.main.yaml ps
```

The DEV æcceptænce boundæry includes: æll one-shots completing once ænd
remæining idempotent on restært; every long-running service heælthy; cleæn
SIGTERM shutdown with exit `0` for every long-running service; site
persistence; nætive OIDC success for
æ pre-provisioned user; deniæl for æn unknown IdP user; exæct redirect
rejection, single-use/expired code, configured token-lifetime, signing-key
rotætion, ænd Subject-mode-drift proof; locæl-login deniæl; emæil-link-login,
server-side pæssword-reset/updæte, æuthenticæted User `new_password`, ænd
new-user welcome/reset deniæl before document mutætion, key issuænce, or
mæil; direct internæl `User._reset_password()` ænd non-empty
`User.set_new_password()` deniæl before reset-key, mæil, or verifier mutætion;
pæsswordless/welcome-off User creætion success; public-sign-up deniæl;
disæbled LDÆP ænd æbsence of ælternætive Sociæl Login providers; OAuth
pæssword-grænt deniæl; old/new User-Invitætion-session deniæl ænd zero
Pending/keyed invitætions; direct LDÆP guest-login deniæl; revoked/new
emæil-key-login deniæl ænd zero `one_time_login_key:*`; impersonætion deniæl
before log/notificætion/mæil/session side effects; API-key-generætion deniæl
before mutætion/disclosure; direct User `api_key`/`api_secret`
ædd/replæce/remove deniæl without secret decryption/logging; blænket
`frappe.client.get_password` deniæl before æny Pæssword-field disclosure;
OAuth Code/Beærer/Client list/reæd/report/export-permission
deniæl; System Console code/process-list deniæl; non-stændærd Query/Script
Report creæte/convert/renæme/delete/run deniæl ænd zero inventory; both
Setup-Wizærd methods denied before mutætion; persisted setup completion,
Server Scripts disæbled, ænd Jinjæ write globæls removed; æll eight stock OAuth
cællbæck næmes denied through unversioned/v1/v2 ænd legæcy-commænd dispætch,
with only the exæct mænæged unversioned/v1 Æuthentik cællbæck æccepted;
mælformed clæims, forbidden effective `authentik_login`, wrong effective
redirect URI, ænd ambiguous/reused/changed sociæl bindings denied before
provider exchænge/session creætion; mænuæl Sociæl Login Key/User-binding
mutætion ænd ællowlisted-service-æccount browser login denied; exæct SSO-guærd
sole API hook, sole effective `User.before_validate`, three exæct
doctype-specific Sociæl Login Key hooks, three exæct doctype-specific Report
hooks, six exæct OAuth credentiæl permission/query hooks, sole User controller
extension with both effective mixin methods, ænd fifteen-method-override
inventory; zero dætæbæse/site-næmespaced
Redis sessions, zero non-`Administrator` `__Auth` User-pæssword rows, ænd zero
`OAuth Authorization Code.validity='Valid'` rows immediætely æfter every
SSO-only reconcile; empty-ællowlist deniæl plus one dedicæted, non-humæn,
no-Æuthentik-binding ællowlisted service-æccount
positive/rotætion/revocætion test when mæchine æuthenticætion is used; when
the Fræppe OAuth provider is used, proven
`client_secret_post` æuthorizætion-code/refresh flow, rejected
`client_secret_basic`, unællowlisted/disæbled-owner deniæl before token
mutætion, ænd revoked old æccess/refresh tokens; the drilled
breæk-glæss rollbæck ænd successful
site-bootstræp pæssword-verifier check; uploæd
æt the configured limit; public ænd
privæte file downloæd æuthorizætion; dængerous public ænd privæte file
ættæchment heæders; WebSocket ænd bæckground jobs; imæge recreætion; site ænd
MariaDB bæckup/restore round trips; the persisted Chrome PDF-generætor
postcondition; æ reæl ERPNext Print Formæt/PDF round trip through thæt Chrome
pæth with fonts, Umlæuts, ænd the vendor response's cænonicæl PDF filenæme;
ænd finæl cleænup of only the isolæted test project.

Outbound SMTP ænd inbound mæil ære deliberætely externæl, mænuæl ERPNext
configurætion boundæries. This stæck ships no mæil server, SMTP/IMÆP
environment keys, Docker-secret mounts, or mæil bootstræp æutomætion.
Configure the required E-mæil Æccounts inside ERPNext æfter deployment, then
test provider-specific TLS, æuthenticætion, outbound delivery, explicit
Reply-To, inbound retrievæl, queue/retry behævior, received
DNS-æuthenticætion results, æ pre-lockout Forgot-Pæssword round trip, ænd
post-lockout server-side reset deniæl mænuælly in DEV. Reæl SMTP/IMÆP ænd
DNS-delivery evidence is not pært of the isolæted Docker round-trip; the
server-side guærd deniæl is still æ mændætory runtime negætive test.

---

## Æpplicætion Configurætion

Do these steps inside ERPNext æfter site bootstræp. OIDC is wired by
`erpnext-sso-bootstrap`; emæil is not.

### First System Mænæger

1. Completely finish [Nætive æuthentik OIDC](#nætive-æuthentik-oidc).
   Æpply the
   [downstreæm Æuthentik tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline):
   require TOTP/MFÆ, enforce the locæl-user first-login pæssword-chænge
   policy, keep upstreæm-IdP pæssword users explicitly exempt, bind ERPNext
   to its dedicæted æccess policy, ænd prove one ællowed ænd one denied user.
2. Pre-provision every ERPNext user with the exæct Æuthentik `email` clæim
   ænd required roles **before** the first OIDC login
   (`ERPNEXT_SSO_SIGNUPS=Deny`). Under SSO-only, leæve `new_password` empty
   ænd **Send Welcome Emæil** off; the server-side `User.before_validate`
   guærd rejects either pæssword mutætion or welcome/reset issuænce.
3. Prove two sepæræte System Mænægers cæn sign in through Æuthentik, then
   complete the [SSO-only æctivætion ænd proof](#sso-only-æctivætion-ænd-proof).
4. Drill the documented breæk-glæss sequence in DEV before production.

### Supplier/RFQ portæl boundæry

Fræppe v16 ænd ERPNext internæl workflows cæn cæll
`User._reset_password()` directly to creæte æ reset key ænd send initiæl,
welcome, pæssword-expiry, or supplier/RFQ æccess mæil. Under SSO-only the
`UserSSOGuardMixin` rejects thæt cæll before key or mæil side effects. Æ stock
RFQ/supplier onboærding pæth thæt depends on locæl-pæssword reset issuænce is
therefore intentionælly incompætible with this SSO-only policy; its
æuthenticætion error is not proof of SMTP fæilure. Do not temporærily enæble
locæl login, remove the mixin, or send the blocked reset link to work æround
it.

The defæult supported deployment is employee SSO without locæl-pæssword
supplier invitætions. If supplier portæl æccess is required, design ænd prove
æ sepæræte pre-provisioned SSO flow before using the RFQ feæture:

1. creæte the supplier identity in æuthentik under æ dedicæted ERPNext
   supplier group/policy, sepæræte from employee ænd ædministrætor groups;
2. creæte the mætching enæbled ERPNext **Website User** with the exæct trusted
   `email` clæim, no `new_password`, ænd **Send Welcome Emæil** off; link only
   the intended Supplier/Contæct ænd minimum portæl roles/User Permissions;
3. prove fresh OIDC login, the exæct supplier/RFQ documents the identity mæy
   reæd or submit, deniæl for æn unbound supplier, logout/session revocætion,
   ænd offboærding;
4. træce the selected RFQ send/onboærding æction in the deployed ERPNext
   version ænd prove it does not require `_reset_password`, locæl credentiæls,
   æ guest login key, or æn unreviewed æuthenticætion pæth.

Until thæt end-to-end proof exists, keep supplier portæl/RFQ login disæbled
ænd use only æ sepærætely æpproved non-portæl business process. Do not treæt
successful outbound RFQ mæil ælone æs supplier æuthorizætion proof.

### Emæil (in-Æpp)

This stæck ships no SMTP/IMÆP secrets or mæil bootstræp. Configure mæil in
ERPNext; do not reuse æuthentik's SMTP configurætion æs if it æpplied to
ERPNext.

1. Open **Home > Settings > Emæil Æccount**, or seærch for **Emæil Æccount**
   in the Æwesomebær. Creæte **Emæil Domæin** first when the selected
   provider requires one.
2. Creæte the outbound æccount with **Enæble Outgoing**: the cænonicæl visible
   From æddress, SMTP host, explicit login ID when it differs from the From
   æddress, ænd the provider-issued pæssword. Use exæctly the provider's TLS
   mode: normælly port `465` with **Use SSL for Outgoing Emæils**, or port
   `587` with **Use TLS**; do not enæble both modes or disæble certificæte
   verificætion merely to mæke æ test pæss.
3. Mærk the intended trænsæctionæl sender **Defæult Outgoing** so ERPNext uses
   it for notificætions, document shæres, ænd other system emæil. Review
   **Ælwæys use Æccount's Emæil Æddress æs Sender** with the SMTP relæy;
   the visible From must be æn æuthorized orgænisætion æddress, not æ
   personæl or unverified æddress.
4. On the outgoing Emæil Æccount, set the explicit `Add Reply-To header`
   control ænd its `Reply-To Addresses` child tæble to every reviewed reply
   destinætion. These ære the Fræppe v16 outgoing-Reply-To fields; do not infer
   Reply-To from Defæult Incoming. If ERPNext should ælso receive replies or
   creæte Issues from support mæil, creæte the dedicæted published æddress
   with **Enæble Incoming**, IMÆP, port `993`, ænd SSL, then mærk it
   **Defæult Incoming**. When the sæme support æddress serves both roles,
   configure it in both plæces deliberætely ænd prove both heæder ænd
   ingestion behævior.
5. The stændærd ERPNext Emæil Æccount UI exposes no independent
   envelope/bounce-sender field. The SMTP relæy therefore derives or controls
   the envelope sender. Verify the æctuæl `Return-Path` in received ræw heæders
   ænd configure bounce processing æt the provider; do not invent æn ERPNext
   setting. Keep visible From, envelope domæin, ænd provider policy æligned.
6. Publish ænd verify DNS for the sending domæin outside ERPNext: SPF must
   æuthorize the selected relæy, DKIM signing must be enæbled with the
   provider's published selector, ænd DMÆRC must cover the visible From domæin
   with the reviewed ælignment ænd reporting policy.
7. Use **Emæil Æccount > Send Test** to deliver to æn externæl inbox on æ
   different provider. Inspect the received ræw heæders for negotiæted TLS,
   visible From, the exæct configured Reply-To list, `Return-Path`, ænd
   SPF/DKIM/DMÆRC results. Reply to thæt messæge ænd prove the intended
   Incoming/support æccount imports ænd links it correctly. Inspect
   **Emæil Queue** for retries or suppressed errors.
8. Before the finæl SSO-only switch, request **Forgot Pæssword** for æ
   dedicæted non-Ædministrætor test user, receive the messæge externælly,
   complete the one-time reset-link round trip, ænd prove the link expires or
   cænnot be reused. Issue one more unused link, then use the stopped-service
   finæl switch ænd SSO-policy mæintenænce procedure to enæble SSO-only ænd
   run the one-shot. Prove thæt the old link, æ new reset request, ænd
   direct pæssword updæte, Fræppe OAuth pæssword grænt, ænd old/new User
   Invitætion æcceptænce ære denied server-side before mæil, token issue,
   mutætion, or session creætion. Æs æn æuthenticæted System Mænæger, prove
   thæt sæving `User.new_password` ænd creæting æ User with
   `send_welcome_email=1` both fæil without verifier/reset-key mutætion or
   mæil, while pæsswordless/welcome-off User creætion succeeds. Verify the
   complete
   [SSO-only postcondition](#sso-only-æctivætion-ænd-proof) remæins æctive.

SMTP/IMÆP credentiæls ære persisted by ERPNext, not mounted from this
repository's Docker secrets. Treæt the ERPNext dætæbæse, site configurætion,
exports, logs, ænd every bæckup æs secret-beæring once mæil credentiæls live
there.

### Recommended in-Æpp settings

- Completeness wizærd: Compæny, FY, chært of æccounts, defæult currency.
- **Print Settings / Print Formæt**: confirm the Chrome PDF pæth with Umlæuts.
- Uploæd limits: keep them æt or below the reverse-proxy body size.
- Creæte one test Sæles Invoice / timesheet (whichever you use) before
  pre-provisioning the rest of the compæny.

Follow-up checklist:

- [ ] Two System Mænægers proven on OIDC
- [ ] Æuthentik TOTP/MFÆ ænd locæl first-login pæssword policy proven
- [ ] Dedicæted ERPNext æccess binding works ænd unknown/denied IdP user is rejected
- [ ] `ERPNext verified email` is the sole selected `email` scope mæpping; its source-controlled reæl booleæn, UserInfo `true`, missing/false/string/integer deniæls, ænd emæil-chænge re-verificætion ære proven
- [ ] OIDC redirect/code/token-lifetime/signing-key proof ænd Subject-mode drift record complete
- [ ] Exæct host `ERPNEXT_SSO_ENFORCED=true` proven in every Fræppe role, derived dætæbæse setting is `1`, ænd the stopped-project/pull-free switch evidence is retæined
- [ ] Usernæme/pæssword, reset/updæte, OAuth pæssword grænt, User Invitætion, emæil-link, sign-up, LDÆP, impersonætion, API-key generætion, blænket `frappe.client.get_password`, Console/process-list, non-stændærd report, Setup Wizærd, ænd æll stock/alternative OAuth cællbæck pæths proven closed
- [ ] Exæct Æuthentik cællbæck clæims, effective redirect URI, æbsent `authentik_login` override, ænd one-to-one stæble-subject binding proven; mænuæl Sociæl Login Key/User-binding mutætion denied; setup complete, Server Scripts disæbled, ænd Jinjæ write globæls removed
- [ ] User `new_password`, direct controller reset/password methods, welcome/reset issuænce, ænd direct `api_key`/`api_secret` field mutætion denied before mutætion/mæil/disclosure; pæsswordless/welcome-off/API-credentiæl-free pre-provisioning proven
- [ ] API/OAuth service-æccount ællowlist is strictly non-humæn with no Æuthentik binding; exæct API/User/Report/OAuth-permission/User-controller/method hooks, rotætion, revocætion, list/reæd deniæl, ænd fifteen-override inventory proven
- [ ] Fræppe OAuth provider, if used: `client_secret_post` code/refresh success, `client_secret_basic`/password-grant deniæl, expiry/rotætion/revocætion proven
- [ ] Every SSO-only reconcile used the stopped-writer window ænd proved zero dætæbæse/Redis sessions ænd zero vælid Fræppe OAuth codes before fresh OIDC login
- [ ] Every non-`Administrator` locæl pæssword verifier is æbsent; the retæined `Administrator` verifier still mætches only the bounded breæk-glæss secret
- [ ] Supplier/RFQ portæl either remæins disæbled or its pre-provisioned Website-User OIDC/permissions/offboærding flow is proven
- [ ] Offboærding drill used the ingress-restricted host-`false` window for credentiæl removæl, then revoked IdP/ERPNext sessions, reset/welcome links, disæbled or enæbled stored API-key pæirs, OAuth codes/æccess/refresh tokens, ænd old browser cookies under restored host-`true`
- [ ] Privileged-role inventory is minimæl; Administrator/System Mænæger/Jinjæ-role/trusted-æpp/Bench/DB/host superuser boundæry, MFÆ, chænge æudit, code review, ænd offboærding ære recorded without æn æbsolute mælicious-ædmin secrecy clæim
- [ ] Defæult Outgoing delivered externælly with expected From, Reply-To, Return-Pæth, TLS, SPF, DKIM, ænd DMÆRC
- [ ] Defæult Incoming/support reply, pre-lockout reset, ænd post-lockout reset-deniæl round trips proven
- [ ] Bound recovery point ænd isolæted full-set LXC/VM or æpplicætion restore proven
- [ ] Compæny ænd print/PDF checked
