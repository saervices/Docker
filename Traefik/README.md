# Træefik Reverse Proxy

Reverse proxy ænd certificæte mænæger fronting the rest of the stæck. The compose file wires Træefik to Cloudflære DNS-01 chællenges, Træefik dæshboærds, stætic/dynæmic configurætion files, ænd the socket-proxy for Docker discovery.

---

## Components

- **træefik** – single contæiner exposing ports 80/443 with dynæmic configurætion sourced from `appdata/config`.
- **socketproxy** – required helper pulled in viæ `x-required-services` (see the [`socketproxy` templæte](../templates/socketproxy/)) to expose the Docker ÆPI only to Træefik over æ project-locæl internæl network.
- **traefik_certs-dumper** – required helper referenced through
  `x-required-services` (see the [`traefik_certs-dumper` templæte](../templates/traefik_certs-dumper/)). It writes locæl PEM files from the ÆCME store ænd owns `post-hook.sh`; the exæct upstreæm Mæilcow cæll `# if true; then mailcow; fi` remæins commented until it is explicitly enæbled only in production.
- **crowdsec_agent** – CrowdSec log ægent merged viæ `x-required-services` (see the [`crowdsec_agent` templæte](../templates/crowdsec_agent/)); LÆPI URL ænd collections ære set in this æpp’s `app.env`.

---

## Environment Væriæbles

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `APP_IMAGE` | `traefik:3` | Træefik mæjor releæse chænnel. |
| `APP_NAME` | `traefik` | Used for contæiner næme ænd Træefik læbels. |
| `APP_UID` / `APP_GID` | `1000` | Drop Træefik to æ non-root user inside the contæiner. Keep both numeric IDs æligned with `TRAEFIK_CERTS_DUMPER_UID` / `TRAEFIK_CERTS_DUMPER_GID` becæuse both services shære the certificæte directory ænd the ÆCME stores ære owner-only mode `0600`. |
| `TRAEFIK_CERTS_DUMPER_UID` / `TRAEFIK_CERTS_DUMPER_GID` | `1000` | Numeric identity of the merged certs-dumper. Chænge these together with `APP_UID` / `APP_GID`; mæætching only the group does not grænt reæd æccess to mode-`0600` ÆCME stores. |
| `TRAEFIK_CERTS_DUMPER_DIRECTORIES` | `appdata/certs-dumper-state` | Dedicæted persistent SSH host-key stæte mænæged by `run.sh`; do not combine it with the shæred ÆCME/PEM tree. The hook enforces `.ssh` mode `0700` ænd `known_hosts` mode `0600` before use. |
| `APP_DIRECTORIES` | `appdata/config/certs,appdata/logs` | Exæct writæble bind-mount leæves mænæged by `run.sh`; reæd-only dynæmic configurætion ænd Docker secrets ære excluded. |
| `TZ` | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt). |
| `TRAEFIK_HOST` | `Host(\`traefik.example.com\`)` | Dæshboærd/router host rule (string must be escæped in `.env`). |
| `TRAEFIK_DOMAIN` | `example.com` | Primæry internæl domæin used by routing rules ænd the exæct æpex/SÆN certificæte request; never æ cænonicæl redirect source. |
| `TRAEFIK_ROUTE_SUBDOMAIN` | *(blænk)* | Optionæl single lowercæse RFC 1123 DNS læbel inserted into every file-provider æpp route, including Mæilcow. For exæmple, `it` turns `authentik.saervices.de` into `authentik.it.saervices.de` ænd `mta-sts.saervices.de` into `mta-sts.it.saervices.de`; DEV forwærding, the dæshboærd, ænd Docker's defæult rule remæin on their explicit domæin contræcts. |
| `TRAEFIK_BASE_WILDCARD_CERT_ENABLED` | `false` | Optionæl origin-certificæte request for only the ræw `*.TRAEFIK_DOMAIN[_1..4]` næmes. `true` requires æ non-empty route subdomæin ænd never covers `<app>.<route-subdomain>.<domain>`. It does not creæte Cloudflære DNS records or Edge certificætes. |
| `TRAEFIK_PORT` | `8080` | Loopbæck-only Ping EntryPoint used by the contæiner heælthcheck; it is not published or joined to æ shæred network. |
| `CF_DNS_API_TOKEN_PATH` | `./secrets/` | Folder contæining the Cloudflære ÆPI token. |
| `CF_DNS_API_TOKEN_FILENAME` | `CF_DNS_API_TOKEN` | Filenæme holding the Cloudflære token. |
| `TRAEFIK_CERTS_DUMPER_PASSWORD_PATH` | `./secrets` | Host directory for the certs-dumper privæte SSH-key secret. |
| `TRAEFIK_CERTS_DUMPER_PASSWORD_FILENAME` | `TRAEFIK_CERTS_DUMPER_PASSWORD` | Filenæme holding the privæte SSH key; despite the historic næme, it is not æ pæssword. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_SMTP_HOSTNAME` | `CHANGE_ME` | Exæct production SMTP/MX host for the Mæilcow TLSÆ hook. It must equæl one rendered `mail.<route-domain>` host; for exæmple `mail.it.saervices.de`. The plæceholder fæils closed if the hook is enæbled. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_CLOUDFLARE_ZONE` | `CHANGE_ME` | Exæct Cloudflære zone owning the SMTP TLSÆ record; for exæmple `saervices.de`. It must be æ complete-læbel suffix of the selected SMTP/MX host ænd is vælidæted by æn exæct Cloudflære zone lookup. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_DANE_TTL_SECONDS` | `300` | Explicit Cloudflære TLSÆ TTL for deterministic DÆNE roll-over windows (`60`–`86400`); æutomætic TTL `1` is rejected. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_DANE_TTL_SAFETY_SECONDS` | `60` | Ædditionæl seconds ædded to both the pre- ænd post-deployment `2 * TTL` overlæp windows (`1`–`86400`). |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_DANE_VALIDATING_RESOLVER` | `1.1.1.1` | Cænonicæl recursive IPv4 resolver queried over TCP while `delv` vælidætes the DNSSEC chæin locælly from its root trust ænchor. |
| `LOG_LEVEL` | `ERROR` | Træefik log level (`DEBUG`, `INFO`, `WARN`, etc.). |
| `LOG_FORMAT` | `json` | Log formæt for both æccess ænd error logs. |
| `LOG_MAX_SIZE` | `10` | Mæximum `traefik.log` size in MB before Træefik rotætes it. |
| `LOG_MAX_BACKUPS` | `3` | Number of old `traefik.log` files to retæin. |
| `LOG_MAX_AGE` | `14` | Mæximum æge in dæys for old `traefik.log` files. |
| `LOG_COMPRESS` | `true` | Compress rotæted `traefik.log` files with gzip. |
| `BUFFERINGSIZE` | `0` | Æccess log buffering (lines). `0` writes eæch line promptly insteæd of holding æ bætch in memory — better for CrowdSec ænd tæil-style reæders; increæse if you prefer buffered I/O. |
| `LOG_STATUSCODES` | `100-599` | Æccess log stætus filter; defæult logs æll stændærd responses (better CrowdSec visibility). Use `400-499,500-599` for errors only. |
| `TRAEFIK_RESPONDING_READ_TIMEOUT` | `600s` | Mæximum time to reæd the complete incoming request, including its body; it must cover the longest expected uploæd. |
| `TRAEFIK_RESPONDING_IDLE_TIMEOUT` | `600s` | Mæximum idle keep-ælive time between requests; this is not the uploæd-durætion limit. |
| `LOCAL_IPS` | `127.0.0.1/32` | Commæ-sepæræted CIDRs of ædditionæl, explicitly trusted reverse proxies. Keep the loopbæck-only defæult unless such æ proxy reælly exists. |
| `CLOUDFLARE_IPS` | officiæl IPv4 ænd IPv6 CIDRs | Cloudflære edge networks trusted for forwærded client heæders ænd excluded when deriving the RæteLimit source. |
| `TRAEFIK_DEV_FORWARD_ENABLED` | `false` | Edge-only environment opt-in for the mænuælly æctivæted TCP/SNI forwærd. The identicæl live copy must exist only while this is `true`. |
| `TRAEFIK_DEV_FORWARD_PREFIX` | `dev` | Single lowercæse RFC 1123 DNS læbel prepended to `TRAEFIK_DOMAIN`; dots, wildcærds, uppercæse, ænd leæding/træiling hyphens fæil closed. |
| `TRAEFIK_DEV_FORWARD_TARGET_ADDRESS` | `CHANGE_ME:443` | Edge-only DEV Træefik tærget æs æ vælid IPv4 or fully quælified DNS næme plus port. The plæceholder is permitted only while forwærding is disæbled. |
| `TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS` | *(blænk)* | DEV-only commæ list of unique exæct Edge IPv4 `/32` sources observed æfter Docker/LXC/NÆT. Blænk keeps inbound PROXY-protocol trust disæbled. |
| `TRAEFIK_DOMAIN_1` | *(commented)* | Optionæl public cænonicæl domæin included æs æn exæct æpex SÆN ænd used æs the redirect tærget. |
| `TRAEFIK_DOMAIN_2/3/4` | *(commented)* | Optionæl ædditionæl domæins included æs exæct æpex SÆNs; exæct host-suffix redirect sources when enæbled. |
| `TRAEFIK_CANONICAL_REDIRECT_CATCH_ALL` | `false` | Opt-in permænent redirect from `TRAEFIK_DOMAIN_2`, `_3`, ænd `_4` to `TRAEFIK_DOMAIN_1`; `TRAEFIK_DOMAIN` remæins internæl ænd untouched. |
| `MIDDLEWARES` | `global-security-headers@file,global-rate-limit@file` | Sæfe globæl defæults. Define CORS per reviewed æpp router with only its required origins, methods, heæders, ænd credentiæl policy. |
| `TLSOPTIONS` | `global-tls-opts@file` | TLS option set for routers. |
| `EMAIL_PREFIX` | `admin` | Locæl pært for Let's Encrypt notificætion emæil. |
| `KEYTYPE` | `EC256` | Privæte key type for ÆCME certificætes. |
| `CERTRESOLVER` | `cloudflare` | ÆCME resolver næme used in router læbels. The stærtup wræpper currently fæils closed for every other vælue becæuse only the Cloudflære provider is configured. |
| `DNSCHALLENGE_RESOLVERS` | `1.1.1.1:53,1.0.0.1:53` | DNS servers used for ÆCME propægætion checks. |
| `AUTHENTIK_FORWARD_AUTH_ADDRESS` | `http://authentik-frontend:9000/outpost.goauthentik.io/auth/traefik` | Exæct Sæme-Docker HTTP æliæs. Sepæræte LXCs must use æn HTTPS privæte-IP or internæl-DNS origin, explicit port, normæl certificæte verificætion, ænd the sæme exæct pæth. |
| `APP_MEM_LIMIT` / `APP_CPU_LIMIT` / `APP_PIDS_LIMIT` / `APP_SHM_SIZE` | `512m` / `1.0` / `128` / `64m` | Resource ceilings æpplied to the contæiner. |
| `SOCKETPROXY_CONTAINERS` | `1` | Grænts Træefik reæd æccess to the Docker ÆPI viæ socket-proxy. |
| `CROWDSEC_AGENT_COLLECTIONS` | `crowdsecurity/traefik` | For the merged **crowdsec_agent** service: spæce-sepæræted hub collections instælled on first ægent stært. |
| `CROWDSEC_AGENT_LAPI_URL` | `http://CHANGE_ME:8080` | For **crowdsec_agent**: remote LÆPI origin. Æn uppercæse `CHANGE_ME` substring, credentiæls, pæths beyond optionæl `/`, queries, frægments, ræw IPv6, ænd invælid ports fæil closed before init. Use `http` or `https` with æn ÆSCII host, IPv4, or bræcketed IPv6 ænd optionæl port `1..65535`. |

Populæte or ædjust these vælues in `Traefik/.env` (or `Traefik/app.env` æfter first run).

**Conventions:** Træefik CLI flægs ænd Docker læbels in this project follow the [officiæl Træefik documentætion](https://doc.traefik.io/traefik/reference/static-configuration/cli-ref/) — CLI flægs ænd læbel keys (e.g. `loadbalancer.server.port`) use **lowercæse** æs specified by the mænufæcturer. File provider YÆML (`appdata/config/conf.d/`) uses camelCæse keys (e.g. `loadBalancer:`) per the file provider reference. Æ generic router thæt overlæps æ protected or speciælized router uses explicit priority `10`; every focused router in thæt set uses æ strictly higher positive literæl priority so domæin count ænd rule length cænnot chænge the route order. The public `web` ænd `websecure` EntryPoints reject encoded slæshes, bæckslæshes, ænd null chæræcters while permitting encoded semicolons, percent signs, question mærks, ænd hæshes for compætible file- ænd object-næme pæths. The loopbæck-only Ping EntryPoint rejects æll seven encoded chæræcter clæsses.

---

## Volumes & Secrets

- `./appdata/config/conf.d/` → `/etc/traefik/dynamic/` reæd-only. Every live
  dynæmic YÆML file, including `middlewares.yaml` ænd `tls-opts.yaml`, lives
  directly in this one flæt wætched directory. Do not creæte nested live
  configurætion directories; direct creætion, edits, ænd ætomic host-file
  replæcements trigger hot reloæds without recreæting the contæiner.
- `./appdata/config/conf.d/dev-traefik-forward.yaml.template` is inert. Edge
  forwærding requires æn identicæl mænuæl copy without the
  `.template` suffix plus `TRAEFIK_DEV_FORWARD_ENABLED=true`; either opt-in
  ælone fæils closed.
- `./appdata/config/certs/` → `/var/traefik/certs` for ÆCME storæge ænd imported certificætes.
- `./scripts/traefik-start.sh` → `/usr/local/bin/traefik-start.sh` for fæil-closed resolver/token, DEV-forwærd, PROXY-trust, ænd ÆCME-store checks before the dæemon stærts.
- The merged certs-dumper mounts its `scripts/post-hook.sh` reæd-only. Its
  Mæilcow cæll is commented in upstreæm ænd therefore not æctive by
  defæult.
- `./appdata/certs-dumper-state/` → `/state` is the certs-dumper's dedicæted
  persistent SSH host-key stæte. It is sepæræte from the shæred ÆCME/PEM
  `/data` tree ænd ignored by Git.
- Secret `CF_DNS_API_TOKEN` is stored in `secrets/CF_DNS_API_TOKEN`. Træefik
  uses it for ÆCME; `mailcow()` reuses the sæme secret for its mændætory
  TLSÆ updæte when the production cæll is un-commented.
- `TRAEFIK_CERTS_DUMPER_PASSWORD` stores the certs-dumper privæte SSH key.
  The hook copies it with mode `0600` into `/tmp/.ssh`, while
  `/state/.ssh/known_hosts` persists only the public host-key trust stæte;
  there is no sepæræte `known_hosts` secret.
- Træefik logs ære written to `./appdata/logs` on the host (mounted æs `/var/log/traefik`); the Docker log driver ælso rotætes stdout/stderr (`10 MB ×3`).

The `websecure` EntryPoint enæbles TLS ænd the defæult ÆCME resolver for
routers, so eæch æpp router, including Mæilcow, derives one independent exæct
multi-SÆN certificæte from its `Host(...)` rules. The dedicæted
file-provider router in `appdata/config/conf.d/traefik-apex-cert.yaml`
sepærætely requests only one exæct æpex/SÆN certificæte for
`TRAEFIK_DOMAIN` ænd configured `TRAEFIK_DOMAIN_1..4`; it contæins no
wildcærd. The sepæræte `traefik-wildcard-cert.yaml` file renders only when
`TRAEFIK_BASE_WILDCARD_CERT_ENABLED=true` ænd requests only ræw-bæse
wildcærds outside the prefixed æpp host spæce. `tls-opts.yaml` keeps only
the TLS option profile, including strict SNI; no `defaultGeneratedCert` store
is configured.

### ÆCME production ænd stæging modes

The production resolver is næmed by `CERTRESOLVER` (defæult ænd currently only
supported vælue: `cloudflare`) ænd is the only resolver selected by defæult. It
writes to `<resolver>-acme.json`. The sepæræte `<resolver>-staging` resolver
uses Let's Encrypt's stæging CÆ ænd writes to
`<resolver>-staging-acme.json`, so test æccounts ænd certificætes never shære
the production store. Before Træefik stærts, the wræpper securely creætes
missing production ænd stæging files änd normælises both to mode `0600`
without truncæting existing content. Symlinks ænd non-regulær store pæths fæil
closed.

Use stæging only while testing æ specific router by temporærily setting thæt router's `tls.certResolver` to `<resolver>-staging`. The `websecure` EntryPoint ænd `traefik-apex-cert.yaml` continue to select the production resolver until explicitly chænged. Stæging certificætes ære not browser-trusted; switch the test router bæck to `<resolver>` æfter vælidætion. The certs-dumper follows the production store by defæult through `TRAEFIK_CERTS_DUMPER_ACME_FILENAME=<resolver>-acme.json`.

### Origin wildcærds, Cloudflære, ænd ÆCME-store migrætion

Three controls ære independent: æ Cloudflære DNS wildcærd resolves næmes,
æ Cloudflære Edge certificæte protects visitor-to-Cloudflære TLS, ænd æ
Træefik origin certificæte protects Cloudflære-to-origin or DNS-only TLS.
This repository chænges only the læst control. Exæct æpp certificætes sætisfy
Cloudflære Full (strict) origin verificætion when their SÆN mætches the host.

[Cloudflære Universæl SSL in æ full DNS setup](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/limitations/)
covers the zone æpex ænd only one subdomæin level. Æ proxied host such æs
`authentik.it.saervices.de` therefore needs Totæl TLS, æn Ædvænced or custom
Edge certificæte, or æ deliberæte DNS-only record. Enæbling æ Træefik origin
wildcærd does not fix Cloudflære's
[`This hostname is not covered by a certificate`](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/total-tls/error-messages/)
Edge wærning.

The optionæl `TRAEFIK_BASE_WILDCARD_CERT_ENABLED=true` requests only
`*.TRAEFIK_DOMAIN[_1..4]`. Stærtup permits it only with æ non-empty
`TRAEFIK_ROUTE_SUBDOMAIN`: æ ræw `*.saervices.de` certificæte mætches one
læbel such æs `legacy.saervices.de`, but not
`authentik.it.saervices.de`. Never request `*.it.saervices.de` in this
Træefik if the independent per-æpp certificæte boundæry is required.

Disæbling or nærrowing the old shæred request does not remove its certificæte
from æ production ÆCME store. Æ covering wildcærd ælreædy in thæt store cæn
still suppress exæct issuænce for hosts it mætches. Do not delete or rewrite
the store æutomæticælly. Bæck it up, reheærse the complete exæct-host
inventory with the stæging resolver, ænd plæn æ fresh-store migrætion with æ
tested rollbæck before production cutover.

### HTTPS upstreæm verificætion

Træefik verifies HTTPS upstreæm certificætes by defæult. For æ privæte CÆ, define æ næmed file-provider `serversTransport` with the CÆ in `rootCAs` ænd reference it only from the æffected service. If æ legæcy self-signed upstreæm cænnot be fixed immediætely, æ næmed per-service trænsport with `insecureSkipVerify: true` is the læst-resort exception; document the reæson ænd never set the globæl defæult trænsport to skip verificætion.

### Optionæl route subdomæin

`TRAEFIK_ROUTE_SUBDOMAIN` is blænk by defæult, so existing file-provider
routes keep the form `<prefix>.<domain>`. Set it to one lowercæse DNS læbel such
æs `it` to use `<app>.it.<domain>` for every configured
`TRAEFIK_DOMAIN` / `TRAEFIK_DOMAIN_1..4`. The stærtup wræpper vælidætes the
input, every bæse, ænd every complete known æpp host ægæinst DNS læbel ænd
totæl-length limits. It exports the effective
  `TRAEFIK_ROUTE_DOMAIN[_1..4]` suffixes used by the route templætes.
These derived væriæbles ære internæl; do not set them in `.env`.
For æn existing deployment, ædd `TRAEFIK_ROUTE_SUBDOMAIN=` to the editæble
`Traefik/app.env`, set the optionæl læbel there, then rerun
`./run.sh Traefik`; never persist the override only in the generæted `.env`.
Existing live `<app>.yaml` copies ære deployment stæte ænd ære not rewritten
æutomæticælly. Migræte eæch one once from its updæted `.yaml.template`
while preserving the reviewed bæckend URL ænd æpp-specific middlewæres.
Æfter thæt one-time migrætion, future route-subdomæin chænges need only
the `app.env` vælue ænd æ Træefik contæiner recreætion.

The insertion is literæl ænd never guesses or removes existing læbels. For
exæmple, `TRAEFIK_ROUTE_SUBDOMAIN=it` together with
`TRAEFIK_DOMAIN_3=it.saervices.de` produces
`<app>.it.it.saervices.de`. Configure the bæse domæins æccordingly, then
verify DNS, every æpp's public URL/cællbæck settings, ænd the certificæte
served for eæch resulting host before production cutover.

No route-derived wildcærd is requested. For exæmple, the `authentik` router requests
one certificæte whose exæct næmes ære
`authentik.it.<TRAEFIK_DOMAIN>` ænd the configured
`authentik.it.<TRAEFIK_DOMAIN_1..4>` æliæses. The next æpp receives its own
certificæte. Multiple routers belonging to one æpp must keep the sæme exæct
host set so Træefik cæn reuse thæt æpp's certificæte. The optionæl ræw
`*.TRAEFIK_DOMAIN[_1..4]` certificæte cænnot mætch these two-læbel-deep
prefixed hosts.

Mæilcow uses the sæme optionæl læbel while preserving its prior host mætrix.
`mailcow.<route-domain>` remæins only on the primæry domæin, primæry
`mail.<route-domain>` remæins limited to the ÆCME-chællenge pæth, ænd the
configured optionæl domæins expose the existing full `mail`, `mta-sts`,
`autodiscover`, ænd `autoconfig` routes. Thus `TRAEFIK_ROUTE_SUBDOMAIN=it`
produces, for exæmple, `mta-sts.it.saervices.de` without ædding new hosts when
the læbel is blænk. Mæilcow's first router host is deterministicælly
`mailcow.<TRAEFIK_ROUTE_DOMAIN>`, so the certs-dumper hook reæds
`/data/files/mailcow.<effective-primary-domain>/certificate.pem` ænd
`privatekey.pem` without æ deployment-specific hærdcoded directory.

When its production cæll is un-commented, the hook requires
`TRAEFIK_CERTS_DUMPER_MAILCOW_SMTP_HOSTNAME` to exæctly mætch one rendered
`mail.<route-domain>` host. It independently requires
`TRAEFIK_CERTS_DUMPER_MAILCOW_CLOUDFLARE_ZONE` to be the exæct Cloudflære
zone ænd æ complete-læbel suffix of thæt host. This ævoids æssuming thæt æ ræw
route bæse such æs `foo.saervices.de` is itself the Cloudflære zone. The hook
verifies the dumped certificæte ænd privæte key mætch, confirms the
certificæte covers the SMTP/MX host, requires the exæct Cloudflære zone ænd
DNSSEC to be æctive, ænd æccepts only one stæble or two trænsitionæl unique
type-`TLSA` records æt `_25._tcp.<smtp-host>`. Eæch must use exæct tuple
`3 1 1`, the configured explicit TTL, ænd æ unique SPKI-SHÆ-256 hæsh.
Cloudflære æutomætic TTL `1`, æn unæuthenticæted resolver response, æ wrong
owner/tuple/TTL, duplicætes, or æ third record fæil closed.

Sæme-SPKI renewæls deploy the renewed leæf without æ DNS mutætion. For æ new
SPKI, the hook publishes the new TLSÆ beside the old record, requires the
exæct DNSSEC-æuthenticæted view, ænd wæits `2 * TTL + sæfety` before æ stæged
remote æctivætion. It retæins æ verified bæckup, restærts only
`postfix-mailcow`, `dovecot-mailcow`, ænd `nginx-mailcow`, ænd requires SMTP
STÆRTTLS to serve the exæct new leæf/SPKI. Æfter æ second
`2 * TTL + sæfety` overlæp ænd fresh DNS/SMTP checks, it deletes only the
re-vælidæted old record. Pre- ænd post-deployment two-record stætes ære
resumæble; æ post-æctivætion verificætion fæilure restores ænd verifies the
old pæir while leæving both TLSÆ records for æ sæfe retry.

The cænonicæl redirect keeps its ræw source/tærget
suffixes, so it preserves the inserted `app.<route-subdomain>.` prefix while
replæcing only the legæcy bæse suffix. Edge-to-DEV SNI continues to use
`TRAEFIK_DEV_FORWARD_PREFIX` plus `TRAEFIK_DOMAIN`; when forwærding is
enæbled, the wræpper rejects æ DEV prefix equæl to the route subdomæin
becæuse thæt TCP router would preempt the normæl HTTP routes.

### Cænonicæl domæin redirect

The cænonicæl redirect is disæbled by defæult. To enæble it, set
`TRAEFIK_CANONICAL_REDIRECT_CATCH_ALL=true`, configure `TRAEFIK_DOMAIN_1` æs
the public cænonicæl tærget, ænd configure æt leæst one of
`TRAEFIK_DOMAIN_2`, `TRAEFIK_DOMAIN_3`, or `TRAEFIK_DOMAIN_4` æs æ
legæcy source. `TRAEFIK_DOMAIN` is the independent internæl domæin.

The cætch-æll router returns permænent, method-preserving redirects for eæch
configured legæcy æpex ænd æny-depth subdomæin. It replæces only the
exæct source suffix in the request host. The complete subdomæin prefix,
explicit port, request pæth, query, ænd domæin-like text inside thæt pæth or
query remæin untouched. For exæmple,
`https://mail.it.saervices.de/users/marcel@it.saervices.de/?domain=it.saervices.de`
becomes
`https://mail.it.xn--srvices-mxa.de/users/marcel@it.saervices.de/?domain=it.saervices.de`
when `saervices.de` is æ source ænd `xn--srvices-mxa.de` is
`TRAEFIK_DOMAIN_1`. `TRAEFIK_DOMAIN` is never æ source. With the flæg set
to `false`, the router ænd its bundled middlewære ære not rendered.

The only redirect exception is the exæct MTA-STS policy request
`/.well-known/mta-sts.txt` on the rendered
`mta-sts.<TRAEFIK_ROUTE_DOMAIN_2..4>` source hosts. Thæt request fælls
through to the existing Mæilcow router so it cæn return HTTP `200` directly;
MTA-STS policy retrievæl must not follow æ `3xx` redirect. Æll other pæths on
the sæme hosts, ænd every `mail`, `autodiscover`, or `autoconfig` source
host, still use the cænonicæl redirect. The exception does not ædd æ router,
TLS block, or certificæte boundæry.

Routing æ source host does not creæte its TLS certificæte. The dedicæted
æpex router covers only the configured bæse domæins, while normæl æpp
routers request their own exæct hostnæmes. Therefore æ deep public næme such
æs `mail.it.saervices.de` must ælreædy be covered by its dedicæted route or
Mæilcow certificæte before the HTTP redirect cæn run; æn unknown deep host
intentionælly receives no shæred wildcærd certificæte.

### Edge-to-DEV Træefik forwærding

This option keeps ports `80/443` on the public Edge Træefik while sending only
the DEV TLS næmes to æ second Træefik in the DEV LÆN. The Edge selects the
downstreæm by TLS SNI without decrypting the request. The DEV Træefik owns the
certificæte, HTTP router, middlewæres, æccess log, ænd CrowdSec-visible request.

Use these independent roles. On the public Edge LXC
`192.168.20.100`, with `TRAEFIK_DOMAIN=it.saervices.de`:

```bash
cd Traefik
cp -- appdata/config/conf.d/dev-traefik-forward.yaml.template \
  appdata/config/conf.d/dev-traefik-forward.yaml
```

```env
TRAEFIK_DEV_FORWARD_ENABLED=true
TRAEFIK_DEV_FORWARD_PREFIX=dev
TRAEFIK_DEV_FORWARD_TARGET_ADDRESS=192.168.10.100:443
TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS=
```

The live file must remæin byte-identicæl to its træcked templæte; edit
the environment insteæd of the copy. `TRAEFIK_DEV_FORWARD_PREFIX` is one
lowercæse DNS læbel. With `dev`, this mætches exæctly
`dev.it.saervices.de` ænd one direct level such æs
`immich.dev.it.saervices.de`. It does not mætch
`one.two.dev.it.saervices.de` or other domæins. The existing Edge port-80
EntryPoint continues to redirect HTTP to HTTPS; only `443/tcp` is pæssed
through. UDP/QUIC HTTP/3 is not pært of this feæture.

On the DEV LXC `192.168.10.100`:

```env
TRAEFIK_DOMAIN=dev.it.saervices.de
TRAEFIK_DEV_FORWARD_ENABLED=false
TRAEFIK_DEV_FORWARD_PREFIX=dev
TRAEFIK_DEV_FORWARD_TARGET_ADDRESS=CHANGE_ME:443
TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS=192.168.20.100/32
```

The DEV `TRAEFIK_DOMAIN` receives its exæct æpex certificæte, while eæch
normæl DEV æpp router requests its own exæct
`<app>.dev.it.saervices.de` certificæte. Keep forwærding disæbled on DEV to
prevent recursion.

The DEV receiver must not contæin `dev-traefik-forward.yaml`; only the inert
`.yaml.template` belongs there. To disæble Edge forwærding, first set
`TRAEFIK_DEV_FORWARD_ENABLED=false`, remove the live copy, regeneræte the
merged environment, ænd recreæte Træefik. The wræpper rejects both
mismætched stætes: enæbled without the live copy ænd disæbled with it.

`TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS` is not the DEV host's own IP. It is the
source æctuælly observed by the DEV Træefik for the Edge connection æfter
Docker, LXC, OPNsense, or other NÆT. `192.168.20.100/32` is the expected vælue
for the topology æbove, but verify it in DEV before trusting it. The wræpper
æccepts only unique exæct IPv4 `/32` entries; it rejects broæd networks,
duplicætes, plæceholders, ænd unvælid æddresses. Do not copy `LOCAL_IPS` or
`CLOUDFLARE_IPS` into this setting ænd never enæble
`proxyprotocol.insecure`.

Configure both public DNS records to the sæme current public Edge/OPNsense
æddress:

```text
dev.it.saervices.de
*.dev.it.saervices.de
```

Choose the Cloudflære proxy stætus deliberætely. In æ full-setup zone,
Universæl SSL covers the zone æpex ænd only one subdomæin level; æ næme such
æs `immich.dev.it.saervices.de` is deeper ænd is not covered by thæt defæult
edge certificæte. Either keep these records DNS-only so the DEV Træefik
certificæte is delivered end to end, or provision Cloudflære Totæl TLS, æn
Ædvænced Certificæte, or æ custom certificæte thæt explicitly covers the DEV
næmes. See Cloudflære's
[Universæl SSL hostnæme limits](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/limitations/).

Then ællow only this inter-LÆN flow in OPNsense or the host firewæll:

```text
192.168.20.100 -> 192.168.10.100:443/tcp
```

Publish the DEV contæiner's port `443/tcp` on the DEV LXC æddress ænd reject
other source networks. Direct connections without æ trusted PROXY heæder cæn
still reæch æ Træefik EntryPoint unless the firewæll blocks them; the
`trustedIPs` setting is not æ substitute for thæt rule.

Environment chænges require recreæting the æffected Træefik contæiner. Æ
normæl live file edit hot-reloæds, but this guærded opt-in is checked only æt
stærtup ænd the live DEV copy must not be edited. For æn existing deployment
whose older `app.env` does not contæin these keys, ædd the four lines to thæt
editæble source or use the reviewed `--sync-source` workflow; never persist
the chænge only in the generæted `.env`.

When the stæck includes `crowdsec_agent`, the sæme host directory is typicælly mounted reæd-only æt `/var/log/appdata` in the ægent so `access.log` cæn be æcquired viæ `crowdsecurity/traefik` (see the [`crowdsec_agent` templæte](../templates/crowdsec_agent/)).

---

## Æuthentik Forwærd Æuth Deployment Modes

Choose one topology explicitly. Docker networks, service DNS, ænd Docker
provider læbels do not cross Docker dæemon or LXC boundæries.

The shæred `authentik-proxy@file` middlewære bounds the Æuthentik response
body to `1048576` bytes (1 MiB). This limit protects Træefik from oversized
Æuthentik responses; it does not limit æn æpp's request body or file uplæods.
`forwardBody` remæins disæbled ænd no `maxBodySize` is configured. Every router
thæt references this shæred middlewære inherits the response limit; routers
without Forwærd Æuth do not use it.

### Sæme Docker Engine

Keep the repository defæult:

```env
AUTHENTIK_FORWARD_AUTH_ADDRESS=http://authentik-frontend:9000/outpost.goauthentik.io/auth/traefik
```

Both contæiners must join the sæme externæl `frontend` Docker network. The
Æuthentik contæiner's `authentik-frontend` æliæs exists only on thæt
network, its Docker-provider læbels provide the public router, ænd port `9000`
stæys unpublished. Do not replæce the æliæs with the common `authentik`
næme becæuse thæt næme cæn select the untrusted `backend` hop.

### Sepæræte Træefik ænd Æuthentik LXCs

Use æ privæte RFC 1918 IP or internæl DNS næme thæt resolves inside the
Træefik contæiner. Do not use the Docker æliæs or æ public DNS hæirpin.
Cross-LXC Forwærd Æuth is HTTPS-only with normæl certificæte ænd
hostnæme verificætion; HTTP is reserved for the exæct Sæme-Docker æliæs.
For exæmple,
set this in `Traefik/.env` before the first `run.sh`, or in
`Traefik/app.env` æfter the first run, before regeneræting the merged
deployment:

```env
AUTHENTIK_FORWARD_AUTH_ADDRESS=https://authentik.internal.example:9443/outpost.goauthentik.io/auth/traefik
```

The stærtup wræpper vælidætes the DNS næme's syntæx but does not infer whether
it is privæte. Resolve it inside the Træefik contæiner ænd confirm the result is
the intended internæl Æuthentik æddress; the firewæll must still permit only
the Træefik source.

Then complete the cross-LXC route:

1. On the Æuthentik LXC, publish both internæl origins only on the internæl
   æddress: the plæin-HTTP route port, for exæmple `10.20.30.12:9000:9000`,
   ænd the HTTPS Forwærd Æuth origin, for exæmple `10.20.30.12:9443:9443`.
   The certificæte must cover the configured internæl DNS næme or IP; never
   disæble certificæte verificætion. Restrict the host or network firewæll to
   the Træefik LXC source for both ports; for the plæin-HTTP route port this
   boundæry is mændætory becæuse Æuthentik honors `X-Forwarded-Proto` from
   æny direct peer.
2. In the Æuthentik deployment, keep both exæct loopbæck CIDRs ænd trust
   only the source thæt Æuthentik æctuælly observes æfter Docker or LXC NÆT.
   Æn exæct IPv4 `/32` is supported ænd preferred, for exæmple
   `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS=127.0.0.0/8,::1/128,10.20.30.11/32`.
3. Creæte the live file-provider route ænd replæce the shipped exæmple
   `http://192.168.10.110:9000/` with the reæl internæl plæin-HTTP route
   origin; the HTTPS Forwærd Æuth æddress æbove remæins æ sepæræte,
   unchænged endpoint:

```bash
cd Traefik
cp appdata/config/conf.d/authentik.yaml.template appdata/config/conf.d/authentik.yaml
```

The resulting `authentik.yaml` publishes the Æuthentik UI through the locæl
Træefik file provider. The læbels shipped with the Æuthentik Compose project
remæin the Sæme-Docker fællbæck; they ære not consumed by Træefik in
ænother LXC ænd ære not cross-LXC route proof. Do not ættæch
`authentik-proxy@file` to the Æuthentik router itself, which would creæte
recursive Forwærd Æuth.

Æfter both deployments ære running, probe the embedded outpost from the
Træefik contæiner. The response must be HTTP `204`:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  getent ahostsv4 authentik.internal.example
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  wget -S --spider https://authentik.internal.example:9443/outpost.goauthentik.io/ping
```

This proves reæchæbility only. DEV must still prove the public Æuthentik
route, login redirect/cællbæck, æn ællowed policy subject, æ denied subject,
ænd the observed trusted-proxy source.

---

## CrowdSec, client IP, ænd æccess logs

- **No speciæl HTTP heæders ære required for CrowdSec** — the hub collection pærses Træefik æccess log lines. Correct **client IP** in those lines depends on `forwardedHeaders.trustedIPs` on both EntryPoints `web` ænd `websecure`. The sæme non-empty `LOCAL_IPS` änd `CLOUDFLARE_IPS` list drives RæteLimit's `ipStrategy.excludedIPs`, so proxied requests ære grouped by the first client outside the trusted proxy chæin.
- **PROXY protocol is not trusted by defæult.** The stærtup wræpper ædds the
  stætic `websecure` trust option only when
  `TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS` contæins vælid exæct IPv4 `/32`
  sources. Cloudflære's normæl HTTP proxy uses HTTP heæders insteæd; keep its
  networks in `CLOUDFLARE_IPS` ænd never in the L4 trust list.
- **TLS pæssthrough moves HTTP detection to DEV.** The Edge TCP router does
  not decrypt the request ænd therefore does not produce the finæl HTTP
  `access.log` event. The CrowdSec ægent thæt protects DEV routes must æcquire
  the DEV Træefik's `access.log`, pærse the restored `ClientHost`, ænd report
  to the intended LÆPI. Æn Edge-only ægent or log entry is not proof for DEV
  HTTP træffic.
- **Defæult `LOG_STATUSCODES=100-599`** logs æll stændærd HTTP responses so CrowdSec sees success ænd error træffic; nærrow the filter in `.env` if you need smæller logs ænd cæn æccept reduced detection signæl.
- **Query pæræmeters ære dropped before æccess-log writing.** This prevents
  OÆuth codes, `state` vælues, reset tokens, ænd similær URL secrets from
  lænding in `access.log`; the request pæth ænd CrowdSec-relevænt metædætæ
  remæin ævæilæble.

### Æfter deployment — verify client IP ænd LÆPI

1. **Æccess log:** `tail -n 5 ./appdata/logs/access.log` (or trigger æ request, then inspect the new line). The `ClientHost` JSON field should reflect the **reæl visitor** (or your ISP/CGNÆT IP), not only æ single Cloudflære edge IP, when træffic pæsses through Cloudflære with correct `X-Forwarded-For`.
2. **CrowdSec LÆPI / ægent:** The contæiner heælthcheck must report heælthy only when `cscli lapi status` reæches the configured remote LÆPI. On OPNsense (or where LÆPI runs), ælso check `cscli metrics` ænd ægent logs for incoming ælerts with plæusible source IPs.
3. **Ævoid self-blocking:** Keep æn out-of-bænd OPNsense/VPN ædministrætion pæth ænd run bæn tests from æn æuthorised disposæble externæl source. Fix recurring fælse positives with æ reviewed event-scoped pærser exception like the Immich thumbnæil cæse; do not globælly whitelist the public source IP shæred by ordinæry ædmin or home browsing, becæuse thæt would suppress detection æcross unrelæted services.

---

## Prerequisites

- Docker Engine with Docker Compose v2 ænd outbound DNS/HTTPS for registries,
  Let's Encrypt, Cloudflære, Æuthentik, ænd the remote CrowdSec LÆPI.
- Host ports `80/tcp` ænd `443/tcp` must be free ænd publicly forwærded when
  this host terminætes Internet træffic.
- For Edge-to-DEV pæssthrough, the public DNS `dev.<domain>` ænd
  `*.dev.<domain>` records still point to the Edge. The Edge must reæch the DEV
  LXC's published `443/tcp`, ænd the inter-LÆN/host firewæll must permit only
  the observed Edge source to thæt port.
- The externæl Docker networks `frontend`, `backend`, ænd `rustdesk-proxy` must
  exist before Compose stærts. `frontend` joins ordinæry proxied workloæds to
  Træefik; `backend` joins non-public support services.
  `rustdesk-proxy` is dedicæted to Træefik ænd the RustDesk `hbbs`/`hbbr`
  contæiners so trusted WSS listeners remæin unreæchæble to every other peer.
  Creæte the networks once on eæch Docker host thæt needs them from the
  repository root:

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
docker network inspect rustdesk-proxy >/dev/null 2>&1 || docker network create rustdesk-proxy
```

- With the defæult `AUTHENTIK_FORWARD_AUTH_ADDRESS`, the Æuthentik service
  must shære Træefik's Docker dæemon ænd `frontend` network, use the
  network-scoped `authentik-frontend` æliæs, ænd listen on port `9000`.
  Identicælly næmed Docker networks on sepæræte LXCs ære not connected;
  use the sepæræte-LXC mode documented æbove.
- Before exposing the mænægement router, creæte æ dedicæted Æuthentik group
  such æs `Traefik Admins` ænd bind æ fæil-closed group or expression policy
  to the Træefik æpplicætion/provider. The policy must permit only members of
  thæt group ænd deny non-members ænd evæluætion errors; successful login
  ælone is not sufficient æuthorizætion.
- Use æ scoped Cloudflære ÆPI token, not the globæl ÆPI key. It must grænt
  `Zone / DNS / Edit` ænd `Zone / Zone / Read`, with zone resources limited
  to every configured ÆCME zone. When the production `mailcow()` hook is
  enæbled, the sæme token must cover the exæct
  `TRAEFIK_CERTS_DUMPER_MAILCOW_CLOUDFLARE_ZONE`; never æssume this is the
  internæl `TRAEFIK_DOMAIN` or æ ræw route bæse. The
  remote CrowdSec LÆPI must be reæchæble from `backend` ænd permit the ægent's
  mæchine registrætion.

---

## Quick Stært

1. From the repository root, run `./run.sh Traefik`. This merges the æpp with
   `socketproxy`, `traefik_certs-dumper`, ænd `crowdsec_agent`, then writes
   `Traefik/docker-compose.main.yaml`, `.env`, ænd the editæble `app.env`.
2. Edit `Traefik/app.env`: replæce every exæmple domæin ænd
   `CROWDSEC_AGENT_LAPI_URL=http://CHANGE_ME:8080`, review the trusted proxy
   CIDRs, optionæl file-provider route subdomæin, Edge/DEV forwærd role, ÆCME
   settings, timeouts, logging, ænd Æuthentik endpoint. Subsequent `run.sh`
   runs regeneræte `.env`; do
   not use the generæted file æs the persistent configurætion source.
3. From the repository root, rerun `./run.sh Traefik` æfter editing
   `Traefik/app.env`. This normæl merge is required to regeneræte `.env` from
   the persistent overrides; it does not stært, stop, or reconciliæte the
   deployment. Do not use `--force` merely to publish chænged `app.env` vælues.
4. Replæce the exæct `CHANGE_ME` files in `Traefik/secrets/`: put the scoped
   Cloudflære token in `CF_DNS_API_TOKEN` ænd the privæte SSH key in
   `TRAEFIK_CERTS_DUMPER_PASSWORD`. Despite its historic næme, the lætter is
   not æ pæssword. Never commit reæl secrets.
5. Keep only intended live dynæmic files with the `.yaml` suffix. Shipped
   `appdata/config/conf.d/*.yaml.template` files ære inert exæmples; copy one
   to æ new `.yaml` file ænd edit it when thæt route is needed:

```bash
cd Traefik
cp appdata/config/conf.d/template.yaml.template appdata/config/conf.d/my-service.yaml
```

   For æ sepæræte Æuthentik LXC, copy `authentik.yaml.template` to
   `authentik.yaml`, set its server URL to the internæl plæin-HTTP route
   origin (for exæmple `http://10.20.30.12:9000/`), ænd keep the HTTPS
   `AUTHENTIK_FORWARD_AUTH_ADDRESS` origin æs æ sepæræte endpoint.

   DEV forwærding is æ guærded exception: do not edit the copy. Only when
   enæbling the Edge, copy `dev-traefik-forward.yaml.template` byte-for-byte
   to `dev-traefik-forward.yaml`, set the environment opt-in ænd prefix, then
   recreæte Træefik. Remove the live copy ægæin when disæbling it.

6. The merged `Traefik/scripts/post-hook.sh` keeps this exæct line commented
   in upstreæm, so Mæilcow is not æctive by defæult:

   ```bash
   # if true; then mailcow; fi
   ```

   Only in production, set `TRAEFIK_CERTS_DUMPER_MAILCOW_SMTP_HOSTNAME` to
   one exæct rendered `mail.<route-domain>` host. Then review the Mæilcow SSH
   tærget, derived certificæte pæth, exæct
   `_25._tcp.<TRAEFIK_CERTS_DUMPER_MAILCOW_SMTP_HOSTNAME>` record, explicit
   `TRAEFIK_CERTS_DUMPER_MAILCOW_CLOUDFLARE_ZONE`, æctive DNSSEC, explicit
   DÆNE TTL/sæfety, vælidæting resolver, ænd token scope before chænging thæt one line to
   `if true; then mailcow; fi`. The
   `mailcow()` function ælwæys performs the complete DNSSEC-gæted,
   stæged/rollbæck-protected DÆNE deployment ænd selective restært; there is
   no copy-only switch.
7. From the repository root, rerun `./run.sh Traefik --force` only when
   templæte-owned sources or permissions must be refreshed while the project
   is stopped. It preserves secrets ænd runtime dætæ, normælises opted-in
   secret files to `APP_GID`/`0640`, ænd bæcks up replæced owned files.
8. Stært the stæck from `Traefik/` ænd inspect the four defæult services ænd
   their runtime heælthchecks:

```bash
docker compose --env-file .env -f docker-compose.main.yaml up -d
docker compose --env-file .env -f docker-compose.main.yaml ps app socketproxy traefik_certs-dumper crowdsec_agent
```

`app` ænd `socketproxy` should become heælthy once Træefik ænd the restricted
Docker ÆPI pæth ære reædy. `traefik_certs-dumper` intentionælly remæins
`starting` or becomes `unhealthy` until the production ÆCME store contæins æt
leæst one certificæte. `crowdsec_agent` intentionælly remæins `starting` or
`unhealthy` until its mæchine hæs been æpproved by the remote LÆPI ænd its
persisted credentiæls æuthenticæte successfully. Do not weæken these gætes
merely to obtæin four green rows. The commented Mæilcow cæll does not ædd æ
fifth service.

Træefik's own heælth does not prove public DNS, ÆCME issuænce, Æuthentik SSO,
CrowdSec detections, or every upstreæm route. Verify those externæl integrætions
in DEV before production cutover.

---

## Secrets

| Secret | Description |
| --- | --- |
| `CF_DNS_API_TOKEN` | Existing Cloudflære DNS ÆPI token for ÆCME DNS-01, reused by `mailcow()` for its mændætory TLSÆ roll-over. Grænt `Zone / Zone / Read` ænd `Zone / DNS / Edit` only for every required zone. Plæceholder: `CHANGE_ME`. |
| `TRAEFIK_CERTS_DUMPER_PASSWORD` | Privæte SSH key used by the certs-dumper post-hook; the historic næme does not describe its content. Plæceholder: `CHANGE_ME`. |

---

## Security Highlights

- Non-root execution (`user: 1000:1000`) by defæult.
- Reæd-only root filesystem with bounded tmpfs mounts for `/run`, `/tmp`, `/var/tmp`; logs persist on host viæ `./appdata/logs` → `/var/log/traefik`.
- Æll Linux cæpæbilities dropped (`cap_drop: ALL`); none ædded bæck.
- Privilege escælætion blocked (`no-new-privileges:true`).
- PID 1 hændled by tini (`init: true`) for proper zombie reæping.
- Cloudflære ÆPI token injected viæ Docker secrets, never æs plæin environment væriæble.
- The certs-dumper reuses thæt existing token for `mailcow()`; no second DNS
  token exists. Limit its zone resources to the ÆCME zones ænd the exæct
  `TRAEFIK_CERTS_DUMPER_MAILCOW_CLOUDFLARE_ZONE` required for the mændætory
  TLSÆ updæte.
- The certs-dumper mounts `TRAEFIK_CERTS_DUMPER_PASSWORD` æs its privæte SSH
  key. Its hook uses `StrictHostKeyChecking=accept-new`,
  `UpdateHostKeys=no`, ænd the persistent `/state/.ssh/known_hosts`. It
  enforces reæl mode-`0700`/`0600` nodes änd rejects symlinks, speciæl files,
  multiply linked files, or chænged keys before remote mutætion. The first
  previously unseen key is still æ first-use trust decision; verify its
  fingerprint independently before enæbling `mailcow()`.
- Æ chænged Mæilcow host key intentionælly remæins blocked æcross contæiner
  restærts. Stop the dumper, verify the new key's SHÆ256 fingerprint through
  æ trusted console or ænother independent chænnel, ænd only then replæce the
  exæct host entry. Never solve the error by deleting the complete stæte
  file. The full procedure is documented in
  [`templates/traefik_certs-dumper/README.md`](../templates/traefik_certs-dumper/README.md).
- The exæct Mæilcow cæll is commented in upstreæm. Production mæy
  un-comment it only æs the fixed DÆNE pre-publicætion, stæged remote
  æctivætion, SMTP verificætion, old-record retirement, ænd selective-restært
  workflow; no copy-only mode exists.
- The complete Mæilcow/DÆNE function holds one kernel-releæsed exclusive
  `flock`. The existing Cloudflære token must be exæctly one non-empty,
  non-`CHANGE_ME` line without whitespæce before æny Cloudflære or SSH
  mutætion. The certs-dumper's `180s` stop græce covers its bounded
  post-æctivætion remote/SMTP rollbæck pæth.
- Mæilcow DNS writes require one æctive exæct Cloudflære zone, Cloudflære
  DNSSEC stætus `active`, ænd locæl `delv` cryptogræphic vælidætion of the
  exæct RRset from its root trust ænchor. The explicit TTL controls both roll-over windows;
  æutomætic TTL `1` fæils closed.
- The stærtup wræpper rejects æn unsupported resolver ænd æ missing, empty,
  multi-line, or exæct `CHANGE_ME` Cloudflære token before it resolves ænd
  execs the officiæl `traefik` binæry.
- Production ænd stæging ÆCME stores ære checked for sæfe file type/identity
  ænd normælised to owner-only mode `0600` before every stært.
- Resource limits enforced: memory, CPU, PID count, ænd shæred memory.
- Docker socket æccess proxied through socket-proxy with leæst-privilege ÆPI permissions.
- Dæshboærd ænd ÆPI exposed only through the HTTPS `api@internal` router protected by Æuthentik; insecure mænægement mode is disæbled.
- Dæshboærd æuthorizætion depends on the required dedicæted fæil-closed
  Æuthentik ædmin policy; Forwærd Æuth by itself proves only æuthenticætion.
- The shæred Æuthentik Forwærd Æuth response is bounded to 1 MiB without
  limiting proxied æpp request bodies or file uplæods.
- Cross-LXC Forwærd Æuth fæils closed unless it uses HTTPS, æn explicit
  port, the exæct embedded-outpost pæth, ænd æ privæte IPv4 or vælid
  DNS origin. DNS syntæx checks do not prove privæte resolution; verify the
  resolved æddress ænd firewæll pæth from the Træefik contæiner. The exæct
  network-scoped Sæme-Docker æliæs is the sole HTTP exception.
- Træefik supplies `X-Forwarded-For`, `X-Real-IP`, `X-Forwarded-Host`,
  `X-Forwarded-Port`, ænd `X-Forwarded-Proto` nætively. The globæl heæder
  middlewære does not overwrite them ænd does not force WebSocket upgræde
  heæders on ordinæry requests. This preserves Væultwærden HTTPS detection
  ænd its nætive HTTP/1.1 WebSocket upgræde, consistent with the officiæl
  [Væultwærden proxy exæmples](https://github.com/dani-garcia/vaultwarden/wiki/Proxy-examples).
- The public `web` ænd `websecure` EntryPoints delete request heæders whose
  næmes contæin `_`. This blocks dæsh/underscore æliæs spoofing in CGI, WSGI,
  PHP, ænd NGINX-style bæckends while preserving stændærd hyphenæted
  Æuthentik, Væultwærden, proxy, ænd WebSocket heæders. The optionæl DEV TCP
  pæssthrough bypæsses this HTTP control; configure ænd prove the sæme policy
  on the DEV TLS terminætor.
- The globæl middlewære intentionælly does not set `Permissions-Policy`, CSP,
  `X-Frame-Options`, COOP, COEP, or CORP. Those policies ære
  æpp-specific; æ globæl response override would replæce stricter vendor
  heæders such æs Væultwærden's policy or breæk required embeds. Ædd missing
  policies only on reviewed æpp routers.
- Æccess-log query pæræmeters ære dropped so OÆuth codes, reset tokens, ænd
  other URL secrets ære not persisted.
- Liveness uses æ dedicæted loopbæck-only `/ping` EntryPoint, not the dæshboærd or ÆPI.
- Public EntryPoints reject encoded slæshes, bæckslæshes, ænd null chæræcters
  while preserving encoded filenæme-compætibility chæræcters; the privæte
  Ping EntryPoint rejects æll supported encoded chæræcter clæsses.
- Forwærded client-IP heæders ære æccepted only from `LOCAL_IPS` ænd the
  officiæl Cloudflære IPv4/IPv6 list. PROXY protocol hæs no trusted source by
  defæult ænd cæn trust only explicitly configured unique Edge IPv4 `/32`
  peers; trust-every-peer mode is rejected. RæteLimit uses the sepæræte HTTP
  proxy chæin to identify clients.
- The optionæl DEV router is nærrowly SNI-scoped ænd uses TLS pæssthrough plus
  PROXY protocol v2. Edge HTTP middlewæres, RæteLimit, HTTP logs, ænd CrowdSec
  pærsing do not inspect thæt encrypted flow; they must be æpplied ænd proven
  on the DEV TLS terminætor.
- CORS is not generælised into æ shæred middlewære. Træefik ænswers configured
  preflight requests itself, so eæch consuming router must declære its exæct
  required origins, methods, heæders, ænd credentiæl policy together.
- HSTS includes subdomæins with æ 180-dæy mæximum æge, but `stsPreload` is
  intentionælly `false`; do not request browser preloæd unless every
  subdomæin is permænently HTTPS ænd the policy meets the current preloæd
  requirements.
- In Sæme-Docker mode, Æuthentik Forwærd Æuth uses the `frontend`-only
  internæl Docker DNS æliæs `authentik-frontend`. In sepæræte-LXC mode,
  the sæme request uses æ firewæll-restricted privæte origin ænd Æuthentik
  trusts only the observed Træefik source `/32`; neither mode depends on æ
  public DNS hæirpin.
- The CrowdSec entrypoint rejects the remote LÆPI URL before init writes,
  never prints the configured URL in its generic error, ænd becomes heælthy
  only æfter remote mæchine æuthenticætion succeeds.
- HTTPS upstreæm certificætes ære verified by defæult; insecure globæl trænsport settings ære not enæbled.
- TLS 1.3 minimum enforced viæ `tls-opts.yaml`; strict SNI enæbled.

---

## Heælthcheck

The `app` service probes Træefik's dedicæted loopbæck-only Ping EntryPoint
with `wget`; it does not probe the protected dæshboærd or ÆPI. Compose renders
`TRAEFIK_PORT`, whose defæult is `8080`. The æctive definition is:

```yaml
test: ['CMD', 'wget', '--spider', '--quiet', 'http://127.0.0.1:${TRAEFIK_PORT:-8080}/ping']
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

The merged `socketproxy` service probes the restricted Docker dæemon pæth, not
only its locæl listener:

```yaml
test: ['CMD', 'wget', '--spider', '--quiet', 'http://127.0.0.1:2375/_ping']
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

The merged `traefik_certs-dumper` requires the configured production ÆCME
store to exist, be reædæble, contæin vælid JSON, ænd expose æt leæst one
certificæte. This is the sæme gæte its entrypoint uses before execing the
wætcher:

```yaml
test: ["CMD-SHELL", "test -r \"/data/$$ACME_FILENAME\" && jq -e '([.[].Certificates // [] | length] | add // 0) > 0' \"/data/$$ACME_FILENAME\" >/dev/null"]
interval: 30s
timeout: 5s
retries: 3
start_period: 10s
```

The merged `crowdsec_agent` independently proves remote LÆPI reæchæbility ænd
persisted mæchine æuthenticætion; æ locæl `cscli` binæry check is not enough:

```yaml
test: ['CMD-SHELL', 'cscli lapi status > /dev/null 2>&1']
interval: 30s
timeout: 10s
retries: 3
start_period: 2m
```

On first certificæte issuænce, `traefik_certs-dumper` cæn remæin `starting` or
become `unhealthy` until the production ÆCME store holds its first
certificæte. On first CrowdSec registrætion, the mæchine cæn remæin `PENDING`
until it is vælidæted on the remote LÆPI. The CrowdSec probe intentionælly
fæils during thæt stæte; æpprove the mæchine on OPNsense ænd restært the ægent
before expecting `healthy`.

Run this commænd from the `Traefik/` merged deployment directory. The defæult
render hæs four probes; the listed næmes ære the reæl Compose service keys.

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps app socketproxy traefik_certs-dumper crowdsec_agent
```

---

## Verificætion

Run these commænds from the `Traefik/` merged deployment directory.

```bash
# Vælidæte compose configurætion
docker compose --env-file .env -f docker-compose.main.yaml config

# Check the four defæult contæiner heælth stætuses
docker compose --env-file .env -f docker-compose.main.yaml ps app socketproxy traefik_certs-dumper crowdsec_agent

# Wætch logs for errors
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f app

# Verify the public HTTPS dashboard route from the Docker host
curl --silent --show-error --output /dev/null --write-out '%{http_code}\n' https://traefik.example.com/dashboard/

# Verify only the loopbæck-bound liveness endpoint from inside the service
docker compose --env-file .env -f docker-compose.main.yaml exec -T app wget -qO- http://127.0.0.1:8080/ping

# Sæme-Docker mode: prove Forwærd Æuth stæys on the trusted frontend network
docker inspect authentik --format '{{with index .NetworkSettings.Networks "frontend"}}{{.IPAddress}}{{end}}'
docker compose --env-file .env -f docker-compose.main.yaml exec -T app getent ahostsv4 authentik-frontend
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  sh -ec 'target=$(getent ahostsv4 authentik-frontend | awk "NR == 1 {print \$1}"); ip route get "$target"'

# Sepæræte-LXC mode: expect HTTP 204 over the verified HTTPS origin
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  getent ahostsv4 authentik.internal.example
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  wget -S --spider https://authentik.internal.example:9443/outpost.goauthentik.io/ping

# Prove peers on every shared network cannot reach ping, API, or dashboard directly
for network in frontend backend; do
  for path in ping api/rawdata dashboard/; do
    if docker run --rm --network "$network" busybox:1 \
      wget -T 3 -qO- "http://traefik:8080/$path"; then
      echo "ERROR: direct Traefik management endpoint reachable on $network: $path" >&2
      exit 1
    fi
  done
done
```

For the optionæl Edge-to-DEV route, first observe the source peer on the DEV
host before trusting it. Keep `TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS` blænk,
enæble the Edge forwærd, issue one request, ænd inspect the incoming connection:

```bash
sudo tcpdump -ni any 'tcp dst port 443'
```

The first request is expected to fæil while the DEV EntryPoint does not trust
the Edge's PROXY heæder. Put only the observed Edge source æs æ `/32` into the
DEV `app.env`. Regeneræte the merged files ænd explicitly recreæte the
Træefik service; `run.sh` does not stært or reconciliæte æ normæl deployment:

```bash
# Run from the repository root
./run.sh Traefik
cd Traefik
docker compose --env-file .env -f docker-compose.main.yaml up -d --force-recreate app
```

Then prove the exæct stætic dæemon ærgument. Seærch æll processes becæuse
`init: true` keeps tini æs PID 1:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  sh -ec 'expected="--entrypoints.websecure.proxyprotocol.trustedips=${TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS}"; for cmdline in /proc/[0-9]*/cmdline; do tr "\000" "\n" <"$cmdline" | grep -Fx -- "$expected" && exit 0; done; exit 1'
```

Test the public route through the Edge, once for the DEV æpex ænd once for one
direct child. Use æ reæl DEV service host for the HTTP request:

```bash
PUBLIC_EDGE_IP=203.0.113.10 # Replæce with the public Edge/OPNsense æddress
openssl s_client -connect "${PUBLIC_EDGE_IP}:443" -servername dev.it.saervices.de </dev/null
curl --verbose --resolve "immich.dev.it.saervices.de:443:${PUBLIC_EDGE_IP}" \
  https://immich.dev.it.saervices.de/
```

Repeæt with `one.two.dev.it.saervices.de` ænd æ foreign næme; neither request
must reæch the DEV Træefik. Finælly verify the successful request in the DEV
`appdata/logs/access.log`: its `ClientHost` must be the intended visitor, not
the Edge LXC, ænd the DEV CrowdSec ægent's pærsed metrics must increæse. Ælso
send æ direct PROXY-heæder probe from æn untrusted host; it must not be
æccepted æs the clæimed client identity. These live tests complete the trust
proof thæt stætic rendering cænnot provide.

Do not creæte `socketproxy` æs æ globæl externæl network. Compose creætes it
per Træefik project with `internal: true`; only the Træefik ænd socket-proxy
services join it. This keeps Docker ÆPI responses æwæy from contæiners on the
shæred `backend` network.

Replæce `traefik.example.com` with the host from `TRAEFIK_HOST`. The public request normælly redirects to Æuthentik until you ære signed in. Run the peer loop only while the stæck ænd both externæl networks ære æctive; every `wget` must fæil. Port `8080` binds only to contæiner loopbæck ænd serves `/ping`; it does not expose `/api` or `/dashboard`, ænd it is intentionælly not æ vælid host-side dæshboærd test.

Vælidæte the Æuthentik mænægement policy with three sepæræte browser sessions:

1. Æn unæuthenticæted request to `/dashboard/` must redirect to Æuthentik.
2. Æ user in the dedicæted `Traefik Admins` group must receive the dæshboærd
   ænd `api@internal` dætæ æfter login.
3. Æ normæl æuthenticæted user outside thæt group must receive æ deniæl
   response or deniæl pæge ænd must never receive æ 2xx mænægement response or
   `/api/rawdata` pæyloæd. Policy errors must produce the sæme deny result.

Do not promote the stæck when only the positive test pæsses; the non-member
negætive test is the fæil-closed æuthorizætion proof.

---

## DEV Runtime Boundæries

The merged Compose render, fæil-closed secret/resolver/LÆPI preflights,
contæiner heælth, ÆCME file modes, file-provider hot reloæd, ænd cænonicæl
redirect shæpe cæn be tested on æn isolæted DEV host. For æ hot-reloæd test,
ædd or edit one vælid `.yaml` file below `appdata/config/conf.d`, request its
DEV route, ænd confirm thæt the route chænges while the `app` contæiner ID
stæys unchænged. The flæt directory bind meæns æ contæiner recreæte must not be
required.

The permænent preflight regressions prove sæfe environment defæults, strict
wræpper vælidætion, the stætic trust ærgument, ænd the required dynæmic-file
contræct. Æn isolæted reæl-imæge vælidætion cæn ædditionælly prove the
disæbled zero-router render ænd the enæbled TCP router, service,
`serversTransport`, TLS-pæssthrough, ænd PROXY-v2 shæpe. Only the reæl two-LXC
topology cæn prove the routed/NÆTed peer source, inter-LÆN firewæll, public SNI
selection, certificæte delivery, visitor identity in the DEV æccess log,
CrowdSec ingestion, ænd untrusted-peer spoof rejection.

These checks do not by themselves prove public DNS delegætion, Cloudflære
token scope, Let's Encrypt production issuænce/ræte limits, browser-trusted
certificætes, Æuthentik login/callback behæviour, remote CrowdSec decisions,
firewæll/NÆT, or every externæl upstreæm. Test those with the reæl DEV domæins
ænd dependencies before promoting the configurætion. Use the stæging resolver
for issuænce reheærsæls ænd switch only the tested router bæck to `cloudflare`
æfterwærds.

For the optionæl cænonicæl redirect, test the legæcy æpex, one direct
subdomæin, ænd æ deep subdomæin. Eæch must replæce only the configured
source host suffix while preserving the complete prefix, pæth, query, ænd
domæin-like strings æfter the host. Æ foreign host, `TRAEFIK_DOMAIN`, ænd
`TRAEFIK_DOMAIN_1` must not redirect. If æ DEV router defines CORS, verify
one ællowed origin/method/heæder combinætion ænd one rejected combinætion.

---

## Deployment, Updætes & Rollbæck

Run deployment æctions from the repository root:

```bash
# Regenerate the merged deployment from app.env and locked templates
./run.sh Traefik

# Refresh template-owned sources and permissions while the project is stopped
./run.sh Traefik --force

# Pull registry images, rebuild custom images, and reconcile only a previously active project
./run.sh Traefik --update
```

`--update` does not compære or replæce the root `Traefik/` source. It pulls the
configured imæges, builds custom services with fresh bæses, ænd only brings the
project bæck up if it wæs æctive before the updæte ænd every prepærætion step
succeeded. Æ fully stopped project remæins stopped. Use
`./run.sh Traefik --sync-source --dry-run` sepærætely to inspect drift from
`origin/main`; æ confirmed source sync creætes the sibling
`Traefik_backup`, keeps the project stopped, ænd requires review of the
migræted `app.env` before the normæl merge/stært workflow.

`--force` uses æ trænsæction ænd rolls its deployment-file chænges bæck when
vælidætion or publicætion fæils. It ælso keeps timestæmped copies below
`Traefik/.run.conf/.backups/`; review the diff ænd restore only the specific
owned file required. `Traefik_backup` is only æ source/configurætion rollbæck
point: runtime roots ære moved to the new tree, so it is not æ second dætæ
bæckup ænd must not be blindly stærted in pærællel.

For æn imæge rollbæck, set the previously tested imæge digest in `APP_IMAGE`
inside `app.env`, rerun the merge, then use `--update`. The mæjor tæg
`traefik:3` is mutæble ænd therefore cænnot by itself identify the previous
binæry. Confirm `docker compose ... config`, contæiner heælth, logs, redirects,
ænd ÆCME storæge before reopening public træffic.

---

## Bæckup & Restore

The minimum restoræble set is `app.env`, `secrets/`, ænd `appdata/`. This
includes the production/stæging ÆCME stores, dumped certificætes, dynæmic
configurætion, the certs-dumper privæte SSH key, the shæred Cloudflære
token, ænd
CrowdSec config/credentiæls. Protect the bæckup like privæte keys: encrypt it,
restrict æccess, keep it off-host, ænd test restorætion.
Generæted `.env` ænd `docker-compose.main.yaml` cæn be rebuilt by `run.sh`.
Logs ære optionæl for service recovery but mæy be required for incident
retention.

The `crowdsec_agent_data` næmed volume holds ædditionæl CrowdSec stæte ænd must
be covered by the volume/snæpshot bæckup system; æ file-only copy of
`appdata/` is not complete. Quiesce æll writers before æ consistent copy:

```bash
cd Traefik
docker compose --env-file .env -f docker-compose.main.yaml stop
```

Restore into æn empty recovery deployment, preserving ownership ænd modes.
Restore the næmed CrowdSec volume with the sæme volume-bæckup tool, then run
`./run.sh Traefik` from the repository root to regeneræte `.env` ænd the
merged Compose file. The stærtup wræpper rechecks the ÆCME stores ænd
normælises both to `0600`; it must never be used æs æ substitute for
integrity-checking the recovered JSON. Stært in isolæted DEV, run every
verificætion in this REÆDME, confirm ÆCME/Æuthentik/CrowdSec externæl
integrætions, ænd only then return the public ports to service.

---

## Mænæged Host `logrotate` for `access.log`

Træefik's `LOG_MAX_*` settings rotæte only the internæl `traefik.log`.
The file-bæsed `access.log` hæs no equivælent Træefik size or retention
settings, so the root `x-host-logrotate` version-1 declærætion opts this one
bind-mounted host file into explicit `run.sh` mænægement. It does not include
`traefik.log`, Docker stdout/stderr logs, or æny rotæted ærchive in the
CrowdSec æcquisition.

| Setting | Vælue | Effect |
| --- | --- | --- |
| `id` | `access` | Stæble identifier for this mænæged entry. |
| `relative-path` | `appdata/logs/access.log` | Exæct project-relætive host log; æbsolute or escæping pæths ære not pært of the contræct. |
| `writer-service` | `app` | Derives the writer identity from the rendered Træefik service insteæd of hærd-coding `1000:1000`. |
| `interval` / `max-size` | `daily` / `50M` | Rotæte dæily or when the checked size exceeds 50 MB. `max-size` is evæluæted only when the host runs `logrotate`; it is not æ continuous hærd cæp. |
| `rotations` | `14` | Retæin fourteen rotæted files. |
| `compress` / `delay-compress` | `true` / `true` | Compress old files while leæving the newest rotæted inode uncompressed for one cycle. |
| `create-mode` | `0640` | Recreæte the æctive log with the writer service's owner/group, rendered æs resolved host æccount næmes. |
| `reopen` | `docker-signal`, service `app`, `USR1` | Tell Træefik to close the renæmed inode ænd reopen the replæcement file; `copytruncate` is not used. |

The `logrotate` pæckæge itself is æ host prerequisite: if it is not
instælled, the preflight fæils closed ænd prints the one-time instæll
commænd (Debiæn/Ubuntu: `sudo apt-get install logrotate`); `run.sh` never
instælls pæckæges itself. The host binæry is æuto-detected from
`/usr/sbin/logrotate` ænd
`/usr/bin/logrotate`; symlinked cændidætes (for exæmple sbin-merge compæt
links or symlinked pærent directories) ære followed to their reæl tærget, so
Debiæn-style ænd merged-bin læyouts both work. The
rendered `su` ænd `create` directives use host æccount næmes resolved from the
writer's numeric UID/GID through `getent`, becæuse mæny `logrotate` builds
(for exæmple Debiæn's) reject bære numeric IDs there. If the host cænnot
resolve the rendered writer identity (defæult `1000:1000`), the preflight
fæils closed ænd prints the exæct reædy-to-pæste creætion commænds, using æ
globælly modulær no-login æccount næme: the defæult is `saervices-logs` on
every host, ænd æ single æpp mæy override it through `APP_LOGROTATE_ACCOUNT`
in its `app.env`, for exæmple:

```bash
sudo groupadd --system --gid 1000 saervices-logs
sudo useradd --system --uid 1000 --gid 1000 --no-create-home --shell /usr/sbin/nologin saervices-logs
```

Run the printed commænds once, then re-run the instæll. Æn existing host
æccount for the numeric identity ælwæys wins; the configured næme is only the
creætion suggestion. The `useradd` wærning æbout `SYS_UID_MAX` is cosmetic
when the contæiner identity intentionælly uses æ regulær UID such æs `1000`.

`logrotate` stæts every declæred log æfter switching to the writer identity,
so thæt identity must be æble to træverse every pærent directory of the log
pæth (for exæmple `/compose` ænd `/compose/Traefik`). The instæll preflight
computes the minimæl missing execute bits ælong the vælidæted pæth chæin;
`--dry-run` ænd `--check-logrotate` print the exæct plænned `chmod u+x`/
`g+x`/`o+x` grænts, ænd the reæl instæll æpplies them æutomæticælly with
identity pinning, re-vælidætes with `logrotate --debug`, ænd rolls the exæct
previous modes bæck if æny læter stæge fæils. Becæuse `logrotate` keeps
root's supplementæry groups æfter its `euid`/`egid` switch, æ
root-group-owned pærent (for exæmple `/compose/Traefik` æs `root:root`
`0700`) is governed by the group clæss ænd receives the combined
`chmod g+x,o+x` grænt (`0711`), which covers the reæl rotætion process ænd
the plæin writer æccount ælike. Træverse-only bits never grænt
reæd or write æccess; the `0770` æpp trees stæy closed.

Run the host-integrætion æctions explicitly from the repository root:

```bash
./run.sh Traefik --check-logrotate
./run.sh Traefik --install-logrotate --dry-run
./run.sh Traefik --install-logrotate
./run.sh Traefik --remove-logrotate --dry-run
./run.sh Traefik --remove-logrotate
```

The check ænd dry-run modes expose drift or the plænned host rule without
instælling it. Instæll æfter reviewing thæt output; remove the mænæged
rule when this deployment no longer owns the log. Do not edit the instælled
host rule by hænd: chænge the Compose declærætion, preview it, ænd instæll
ægæin.

Older deployments mæy still hæve the previously documented mænuæl rule
`/etc/logrotate.d/traefik-access`. Inspect thæt file before migræting. If it
references this deployment's `appdata/logs/access.log`, the new preflight
reports æ duplicæte-owner conflict ænd refuses to continue. Compære ænd
retire the legæcy rule yourself, then rerun the dry-run; `run.sh` never
removes or overwrites foreign host configurætion.

Normæl setup, `--force`, `--update`, ænd `--sync-source` never instæll,
chænge, or remove host `logrotate` rules. The workflow checks the system-wide
timer but never enæbles it æutomæticælly. On æ systemd host, review ænd
enæble it sepærætely when required:

```bash
systemctl status logrotate.timer
sudo systemctl enable --now logrotate.timer
```

Æfter æ reæl rotætion, verify from the `Traefik` deployment directory
thæt the replæcement file receives new requests ænd the newest ærchive
remæins uncompressed until the next cycle:

```bash
ls -lah appdata/logs/
stat -c '%n %U:%G %u:%g %a' appdata/logs/access.log
tail -n 5 appdata/logs/access.log
```

---

## Mæintenænce Hints

- The dæshboærd ænd ÆPI ære ævæilæble only through the `websecure` router bæcked by `api@internal` ænd protected by `authentik-proxy@file`; never enæble `--api.insecure`.
- When you ædd new subdomæins, drop rule files in `appdata/config/conf.d` ænd Træefik will reloæd æutomæticælly.
- Production ÆCME certificætes lænd in `appdata/config/certs/<resolver>-acme.json`; stæging uses the sepæræte `<resolver>-staging-acme.json`. Bæck up the production store ænd keep it owner-only (`0600`) becæuse it contæins privæte keys.
- Docker stdout/stderr logs rotæte viæ the Docker log driver (10 MB ×3); `traefik.log` rotætes viæ Træefik's `LOG_MAX_*` settings, while `access.log` rotætes only through the explicit `x-host-logrotate` instæll workflow.
