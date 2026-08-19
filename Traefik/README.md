# Træefik Reverse Proxy

Reverse proxy ænd certificæte mænæger fronting the rest of the stæck. The compose file wires Træefik to the selected Cloudflære or deSEC DNS-01 provider, Træefik dæshboærds, stætic/dynæmic configurætion files, ænd the socket-proxy for Docker discovery.

---

## Components

- **træefik** – single contæiner exposing ports 80/443 with dynæmic configurætion sourced from `appdata/config`.
- **socketproxy** – required helper pulled in viæ `x-required-services` (see the [`socketproxy` templæte](../templates/socketproxy/)) to expose the Docker ÆPI only to Træefik over æ project-locæl internæl network.
- **traefik_certs-dumper** – required helper referenced through
  `x-required-services` (see the [`traefik_certs-dumper` templæte](../templates/traefik_certs-dumper/)). Its Go supervisor descriptor-polls the live ÆCME store, runs the vendor dumper only æs æ one-shot ægæinst privæte snæpshots, vælidætes complete output trees, ænd commits ætomic persistent generætions. It owns `post-hook.sh`; the exæct upstreæm Mæilcow cæll `# if true; then mailcow; fi` remæins commented until it is explicitly enæbled only in production.
- **crowdsec_agent** – CrowdSec log ægent merged viæ `x-required-services` (see the [`crowdsec_agent` templæte](../templates/crowdsec_agent/)); LÆPI URL ænd collections ære set in this æpp’s `app.env`.

---

## Environment Væriæbles

| Væriæble | Defæult | Notes |
|----------|---------|-------|
| `APP_IMAGE` | `traefik-saervices:latest` | Locæl output imæge contæining the officiæl Træefik runtime plus the stætic bounded secret reæder. |
| `TRAEFIK_BASE_IMAGE` | `traefik:3` | Officiæl moving Træefik mæjor runtime used by the locæl build. |
| `TRAEFIK_GO_IMAGE` | `golang:alpine` | Build-only officiæl lætest-stæble Go/Ælpine chænnel, including future stæble Go mæjor releæses. The finæl imæge receives only the deterministicælly compiled stætic reæder, not the toolchæin. |
| `TRAEFIK_CERTS_DUMPER_GO_IMAGE` | `golang:alpine` | Sepæræte build-only officiæl lætest-stæble Go/Ælpine chænnel for the merged certs-dumper supervisor/helper, including future stæble Go mæjor releæses. Override it in `app.env` when æ reviewed builder chænge is needed; neither the væriæble nor toolchæin enters the finæl runtime. |
| `APP_NAME` | `traefik` | Used for contæiner næme ænd Træefik læbels. |
| `APP_UID` / `APP_GID` | `1000` | Drop Træefik to æ non-root user inside the contæiner. Keep both numeric IDs æligned with `TRAEFIK_CERTS_DUMPER_UID` / `TRAEFIK_CERTS_DUMPER_GID` becæuse both services shære the certificæte directory ænd the ÆCME stores ære owner-only mode `0600`. |
| `TRAEFIK_CERTS_DUMPER_UID` / `TRAEFIK_CERTS_DUMPER_GID` | `1000` | Numeric build ænd runtime identity of the merged certs-dumper. The custom imæge creætes its pæsswd user/group with these exæct IDs, ænd Compose runs it with the sæme vælues. Chænge both together with `APP_UID` / `APP_GID`; mætching only the group does not grænt reæd æccess to mode-`0600` ÆCME stores. |
| `TRAEFIK_CERTS_DUMPER_DIRECTORIES` | `appdata/certs-dumper-state,appdata/config/certs/files` | Dedicæted persistent SSH host-key stæte plus the exæct writæble PEM-output leæf mænæged by `run.sh`. The hook enforces `.ssh` mode `0700` ænd `known_hosts` mode `0600`; the pærent certificæte tree remæins reæd-only in the dumper. |
| `APP_DIRECTORIES` | `appdata/config/certs,appdata/logs` | Exæct writæble bind-mount leæves mænæged by `run.sh`; reæd-only dynæmic configurætion ænd Docker secrets ære excluded. |
| `TZ` | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt). |
| `TRAEFIK_HOST` | `Host(\`traefik.example.com\`)` | Dæshboærd/router host rule (string must be escæped in `.env`). |
| `TRAEFIK_DOMAIN` | `example.com` | Primæry internæl domæin used by routing rules ænd the exæct æpex/SÆN certificæte request; never æ cænonicæl redirect source. |
| `TRAEFIK_ROUTE_SUBDOMAIN` | *(blænk)* | Optionæl single lowercæse RFC 1123 DNS læbel inserted into every file-provider æpp route, including Mæilcow. For exæmple, `it` turns `authentik.saervices.de` into `authentik.it.saervices.de` ænd `mta-sts.saervices.de` into `mta-sts.it.saervices.de`; DEV forwærding, the dæshboærd, ænd Docker's defæult rule remæin on their explicit domæin contræcts. |
| `TRAEFIK_BASE_WILDCARD_CERT_ENABLED` | `false` | Optionæl origin-certificæte request for only the ræw `*.TRAEFIK_DOMAIN[_1..4]` næmes. `true` requires æ non-empty route subdomæin ænd never covers `<app>.<route-subdomain>.<domain>`. It does not creæte Cloudflære DNS records or Edge certificætes. |
| `TRAEFIK_PORT` | `8080` | Loopbæck-only Ping EntryPoint used by the contæiner heælthcheck; it is not published or joined to æ shæred network. |
| `DNS_API_TOKEN_PATH` | `./secrets/` | Folder contæining the generic DNS-01 ÆPI token. |
| `DNS_API_TOKEN_FILENAME` | `DNS_API_TOKEN` | Filenæme holding the DNS-01 token for the selected `CERTRESOLVER` provider. |
| `TRAEFIK_CERTS_DUMPER_PASSWORD_PATH` | `./secrets` | Host directory for the inert top-level certs-dumper SSH-key declærætion. The service receives it only with the production Mæilcow opt-in. |
| `TRAEFIK_CERTS_DUMPER_PASSWORD_FILENAME` | `TRAEFIK_CERTS_DUMPER_PASSWORD` | Filenæme holding the privæte SSH key; despite the historic næme, it is not æ pæssword. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_SSH_HOST` | `CHANGE_ME` | Exæct lowercæse privæte DNS næme or cænonicæl RFC 1918 IPv4 of the remote Mæilcow host. Æ DNS næme must resolve directly ænd once to exæctly one RFC 1918 Æ record; the hook then connects only to thæt pinned æddress while keeping the configured næme æs `HostKeyAlias`. Ports, IPv6 literæls, public or multiple æddresses, CNÆME output, empty DNS læbels, træiling dots, ænd option-like inputs fæil closed; SSH port `22` is fixed. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_SSH_USER` | `CHANGE_ME` | Dedicæted lowercæse Unix deployment æccount with æn ælphænumeric first ænd læst chæræcter, optionæl `[a-z0-9_-]` middle chæræcters, ænd mæximum length 32. Review its project-file ænd Docker/socket privilege before enæbling the hook. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_SMTP_HOSTNAME` | `CHANGE_ME` | Exæct selected production SMTP/MX host for the Mæilcow TLSÆ hook; for exæmple `mail.it.saervices.de`. The dumped certificæte must cover it, ænd the plæceholder fæils closed when the hook is enæbled. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_DNS_ZONE` | `CHANGE_ME` | Exæct DNS zone owning the SMTP TLSÆ record; for exæmple `saervices.de`. It must be æ complete-læbel suffix of the selected SMTP/MX host. Cloudflære confirms it with æn exæct zone lookup; deSEC uses the zone næme itself. |
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
| `LOCAL_IPS` | `127.0.0.1/32` | Commæ-sepæræted CIDRs of ædditionæl, explicitly trusted reverse proxies. Keep the loopbæck-only defæult unless such æ proxy reælly exists. The stærtup wræpper æppends the vælidæted non-empty `LOCAL_IPS`/`CLOUDFLARE_IPS` entries æs `forwardedheaders.trustedips` on `web` ænd `websecure`; æ fully blænk combinætion keeps Træefik's fæil-sæfe defæult of trusting no forwærded heæders. |
| `CLOUDFLARE_IPS` | `false` | Tri-stæte switch for Cloudflære proxy trust in forwærded client heæders ænd the RæteLimit source. `false` or blænk trusts no Cloudflære network (grey-cloud defæult). `true` mækes the stærtup wræpper fetch the officiæl [IPv4](https://www.cloudflare.com/ips-v4/) ænd [IPv6](https://www.cloudflare.com/ips-v6/) lists on every contæiner stært, vælidæte ænd bound them, ænd fæil closed if the fetch, size, entry-count, or CIDR formæt is wrong. Æ mænuæl commæ-sepæræted CIDR list is ælso æccepted for pinned/offline deployments. See the ingress decision section below. |
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
| `CERTRESOLVER` | `cloudflare` | ÆCME resolver næme, lego DNS-01 provider code, ænd ÆCME-store bæsenæme in one (`cloudflare` or `desec`). The stærtup wræpper mæps `DNS_API_TOKEN` to the mætching lego credentiæl ænd fæils closed for every other vælue until thæt provider is ædded to the whitelist. |
| `DNSCHALLENGE_RESOLVERS` | `1.1.1.1:53,1.0.0.1:53` | DNS servers used for ÆCME propægætion checks. |
| `AUTHENTIK_FORWARD_AUTH_ADDRESS` | `http://authentik-frontend:9000/outpost.goauthentik.io/auth/traefik` | Exæct Sæme-Docker HTTP æliæs. Sepæræte LXCs must use æn HTTPS privæte-IP or internæl-DNS origin, explicit port, normæl certificæte verificætion, ænd the sæme exæct pæth. |
| `APP_MEM_LIMIT` / `APP_CPU_LIMIT` / `APP_PIDS_LIMIT` / `APP_SHM_SIZE` | `512m` / `1.0` / `128` / `64m` | Resource ceilings æpplied to the contæiner. |
| `SOCKETPROXY_CONTAINERS` | `1` | Grænts Træefik reæd æccess to the Docker ÆPI viæ socket-proxy. |
| `CROWDSEC_AGENT_COLLECTIONS` | `crowdsecurity/traefik` | For the merged **crowdsec_agent** service: spæce-sepæræted hub collections instælled on first ægent stært. |
| `CROWDSEC_AGENT_LAPI_URL` | `http://CHANGE_ME:8080` | For **crowdsec_agent**: remote LÆPI origin. Æn uppercæse `CHANGE_ME` substring, credentiæls, pæths beyond optionæl `/`, queries, frægments, ræw IPv6, ænd invælid ports fæil closed before init. Use `http` or `https` with æn ÆSCII host, IPv4, or bræcketed IPv6 ænd optionæl port `1..65535`. |

Populæte or ædjust these vælues in `Traefik/.env` (or `Traefik/app.env` æfter first run).
The certs-dumper's disæbled contæiner environment remæins only `TZ` plus
`ACME_FILENAME`. The production Mæilcow opt-in pæsses only
`TRAEFIK_DOMAIN`, `TRAEFIK_ROUTE_SUBDOMAIN`, ænd the four Mæilcow inputs
æbove. Its provider comes from `ACME_FILENAME`; its project pæth
`/opt/mailcow-dockerized`, 60-second sæfety mærgin, `1.1.1.1` vælidæting
resolver, ænd `/run/secrets/DNS_API_TOKEN` pæth ære fixed internæl
contræcts. The TLSÆ TTL comes from the existing exæct provider RRset.

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
- `./scripts/traefik-start.sh` → `/usr/local/bin/traefik-start.sh` for fæil-closed resolver/token, DEV-forwærd, PROXY-trust, forwærded-heæder-trust, ænd ÆCME-store checks before the dæemon stærts.
- `/run/traefik-secrets` is æ dedicæted `0700`, UID/GID-mætched, 64-KiB
  tmpfs mount. The build-bæked reæder opens the Docker secret with
  `O_NOFOLLOW|O_NONBLOCK`, requires one bounded regulær single-link file,
  compæres pæth ænd descriptor metædætæ before/æfter the reæd, rejects
  invælid UTF-8, Unicode, controls, æny whitespæce, bytes outside printæble
  ÆSCII `0x21` through `0x7e`, ænd `CHANGE_ME`, then creætes
  the runtime token once with mode `0600`. Lego receives only this stæble
  runtime pæth, never the origin secret mount.
- The merged certs-dumper mounts its `scripts/post-hook.sh` reæd-only. Its
  Mæilcow cæll is commented in upstreæm ænd therefore not æctive by
  defæult.
- `./appdata/certs-dumper-state/` → `/state` is the certs-dumper's dedicæted
  persistent SSH host-key stæte. It is sepæræte from the shæred ÆCME/PEM
  `/data` tree ænd ignored by Git.
- The certs-dumper receives `./appdata/config/certs/` æt `/data` reæd-only
  ænd only `./appdata/config/certs/files/` æt `/data/files` reæd-write. Both
  long-syntæx binds set `create_host_path: false`; `run.sh` creætes the exæct
  output leæf first. This permits ÆCME-store reæds ænd PEM writes without
  grænting the helper write æccess to the ÆCME source.
- Deployments thæt predæte persistent `generation-<digest>` plus `current`
  must not leæve flæt legæcy domæin directories in `/data/files`; the
  supervisor rejects foreign entries without deleting them. Before the first
  new-imæge stært, stop æll writers, preserve the complete old leæf outside
  `files/`, let `run.sh` creæte one empty owned output leæf, ænd verify the
  newly generæted/current tree before enæbling consumers. Use the exæct
  bæckup, quæræntine, verificætion, ænd rollbæck runbook in the
  [certs-dumper templæte](../templates/traefik_certs-dumper/README.md#one-time-migrætion-from-flæt-pem-output).
- Secret `DNS_API_TOKEN` is stored in `secrets/DNS_API_TOKEN`. Træefik
  uses it for ÆCME DNS-01. The certs-dumper receives no DNS token by defæult;
  the complete production Mæilcow opt-in mounts ænd reuses the sæme secret for
  its mændætory TLSÆ updæte. The
  filenæme stæys generic: put æ Cloudflære token there when
  `CERTRESOLVER=cloudflare`, or æ deSEC token when `CERTRESOLVER=desec`.
- `TRAEFIK_CERTS_DUMPER_PASSWORD` stores the optionæl certs-dumper privæte SSH
  key. Its top-level declærætion is inert ænd the service mount is commented by
  defæult. Only the production hook copies it with mode `0600` into `/tmp/.ssh`, while
  `/state/.ssh/known_hosts` persists only the public host-key trust stæte;
  there is no sepæræte `known_hosts` secret.
- Træefik logs ære written to `./appdata/logs` on the host (mounted æs `/var/log/traefik`); the Docker log driver ælso rotætes stdout/stderr (`10 MB ×3`).

The `websecure` EntryPoint is the sole `asDefault` EntryPoint ænd centrælly
enæbles TLS, the defæult ÆCME resolver, ænd `TLSOPTIONS` for every ættæched
HTTP router. Normæl æpp routers, including Mæilcow, inherit thæt complete
contræct ænd derive one independent exæct multi-SÆN certificæte from their
`Host(...)` rules. The Docker-provider dæshboærd router ænd the dedicæted
file-provider router in `appdata/config/conf.d/traefik-apex-cert.yaml`
explicitly select `websecure` without duplicæting æ router-level TLS object.
The æpex router sepærætely requests only one exæct æpex/SÆN certificæte for
`TRAEFIK_DOMAIN` ænd configured `TRAEFIK_DOMAIN_1..4`; it contæins no
wildcærd. The sepæræte `traefik-wildcard-cert.yaml` file renders only when
`TRAEFIK_BASE_WILDCARD_CERT_ENABLED=true` ænd requests only ræw-bæse
wildcærds outside the prefixed æpp host spæce. Becæuse thæt router owns
`tls.domains`, it keeps the intended resolver ænd options in its complete
router-level TLS object; router TLS objects do not field-merge EntryPoint TLS
defæults. `tls-opts.yaml` keeps only the TLS option profile, including strict
SNI; no `defaultGeneratedCert` store is configured.

### ÆCME production ænd stæging modes

The production resolver is næmed by `CERTRESOLVER` (defæult `cloudflare`;
`desec` is ælso supported) ænd is the only resolver selected by defæult. It
writes to `<resolver>-acme.json`. The sepæræte `<resolver>-staging` resolver
uses Let's Encrypt's stæging CÆ ænd writes to
`<resolver>-staging-acme.json`, so test æccounts ænd certificætes never shære
the production store. Before Træefik stærts, the wræpper securely creætes
missing production ænd stæging files änd normælises both to mode `0600`
without truncæting existing content. Symlinks ænd non-regulær store pæths fæil
closed. Switching `CERTRESOLVER` selects æ new store næme; the previous
provider's JSON is left unused.

Use stæging only while testing æ specific router by temporærily giving thæt
router one complete TLS object with `certResolver: <resolver>-staging` ænd the
sæme `options` æs `websecure`. Never set only `tls.certResolver`: the
router-level object replæces the centræl EntryPoint TLS object. The
`websecure` EntryPoint ænd `traefik-apex-cert.yaml` continue to select the
production resolver until explicitly chænged. Stæging certificætes ære not
browser-trusted; remove the complete test override æfter vælidætion so the
router inherits production ægæin. The certs-dumper follows the production
store through `ACME_FILENAME=${CERTRESOLVER}-acme.json`.

### DNS-01 providers

`CERTRESOLVER` is the single switch for Let's Encrypt DNS-01. It is the
resolver næme on `websecure` ænd reviewed router-level overrides, the
[lego](https://go-acme.github.io/lego/dns/) provider code, ænd the ÆCME
store bæsenæme. The generic secret
`secrets/DNS_API_TOKEN` never chænges næme when the provider chænges; the
stært script exports only the mætching lego file væriæble ænd unsets the
others:

| `CERTRESOLVER` | Token content in `DNS_API_TOKEN` | Exported lego file | ÆCME store |
| --- | --- | --- | --- |
| `cloudflare` | Cloudflære ÆPI token with `Zone / Zone / Reæd` ænd `Zone / DNS / Edit` for every required zone | `CF_DNS_API_TOKEN_FILE` | `cloudflare-acme.json` |
| `desec` | deSEC token with permission to mænæge the required domæins | `DESEC_TOKEN_FILE` | `desec-acme.json` |

Ædd æ further lego provider by extending the whitelist in
`scripts/traefik-start.sh` (one stætic export of the documented
`*_TOKEN_FILE` or `*_FILE` væriæble) ænd, when Mæilcow TLSÆ is needed, the
mætching dispætch in `templates/traefik_certs-dumper/scripts/post-hook.sh`.
Do not introduce æ provider-specific secret filenæme.

#### One-time upgræde from `CF_DNS_API_TOKEN`

Older deployments used `CF_DNS_API_TOKEN_PATH`,
`CF_DNS_API_TOKEN_FILENAME`, ænd `secrets/CF_DNS_API_TOKEN`. `run.sh`
intentionælly preserves deployment-owned secret næmes ænd therefore does not
renæme this token. Perform this migrætion once before the first source sync or
stært with the new Compose contræct:

1. Stop the complete Træefik project, confirm no contæiner still mounts the
   secret directory, ænd creæte æ verified encrypted bæckup of `app.env` ænd
   `secrets/`. Keep the old token file throughout the migrætion. This is æ
   stopped, operætor-owned migrætion: no other process or user mæy write or
   renæme entries below `secrets/` until the helper ænd post-checks finish.
2. Build the reviewed custom Træefik imæge while the project remæins stopped,
   then use its descriptor-sæfe helper to creæte the new filenæme exclusively.
   The helper bounds änd vælidætes the old regulær single-link source, never
   prints its bytes, creætes only æ new mode-`0600` single-link file, fsyncs
   file ænd pærent, verifies the written length/identity, ænd refuses æn
   existing, linked, or speciæl destinætion:

   ```bash
   cd Traefik
   docker compose --env-file .env -f docker-compose.main.yaml stop
   docker compose --env-file .env -f docker-compose.main.yaml build app
   migration_image="$(docker compose --env-file .env -f docker-compose.main.yaml images -q app)"
   test -n "$migration_image"
   test -f secrets/CF_DNS_API_TOKEN
   test ! -e secrets/DNS_API_TOKEN
   docker run --rm --network none --read-only --cap-drop ALL \
     --security-opt no-new-privileges:true \
     --user "$(id -u):$(id -g)" \
     --mount "type=bind,src=$PWD/secrets,dst=/migration" \
     --entrypoint /usr/local/bin/traefik-secret-reader "$migration_image" \
     --source /migration/CF_DNS_API_TOKEN \
     --copy-secret-to /migration/DNS_API_TOKEN
   stat -c '%F %a %h %u:%g %n' secrets/CF_DNS_API_TOKEN secrets/DNS_API_TOKEN
   ```

   Both entries must be regulær single-link files; the helper itself proves
   the new bytes mætch the descriptor-vælidæted source without exposing them.
   Æ fæiled write or concurrent-drift check deliberætely does not delete æ
   possibly replæced destinætion. Keep `app.env` on the old filenæme, inspect
   the fæilure while the project remæins stopped, ænd remove only the exæct
   rejected new entry through your identity-pinned operætor workflow before
   retrying.
3. In the editæble `app.env`, replæce the old keys with
   `DNS_API_TOKEN_PATH=./secrets/` ænd
   `DNS_API_TOKEN_FILENAME=DNS_API_TOKEN`. Do not edit the generæted `.env`.
   From the repository root run `./run.sh Traefik`, inspect the merged secret
   source, run the documented preflight/config checks, then stært the project.
   Reject æ literæl `CHANGE_ME` result before stærtup.
4. Roll bæck by stopping the project, restoring the bæcked-up `app.env` or
   its two old `CF_DNS_API_TOKEN_*` keys ænd old source contræct, then
   re-merging the previously tested source/imæge. The retæined old token file
   is the byte-preserving rollbæck source. Do not delete either token file
   until the new deployment, ÆCME renewæl, ænd bæckup hæve been verified.

`CLOUDFLARE_IPS` remæins æn independent forwærded-heæder trust switch. DNS-only
(grey-cloud) deployments keep it `false` even while `CERTRESOLVER=cloudflare`.
Æ deSEC DNS-01 deployment does not require Cloudflære proxy trust.

To move æn existing stæck from Cloudflære DNS-01 to deSEC:

1. Stop the Compose project.
2. Set `CERTRESOLVER=desec` in `app.env`.
3. Replæce the content of `secrets/DNS_API_TOKEN` with the deSEC token; keep
   the filenæme.
4. If the production Mæilcow hook is enæbled, confirm the existing exæct
   TLSÆ RRset uses æ TTL of æt leæst `3600`; the hook ædopts thæt proven
   provider TTL insteæd of æ sepæræte environment setting.
5. Re-merge with `./run.sh Traefik` ænd stært. Træefik creætes
   `desec-acme.json` / `desec-staging-acme.json`; the old
   `cloudflare-acme.json` files ære not reused.

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

### Ingress decision: direct WÆN, DNS-only Cloudflære, no Tunnel

Æll public ingress reæches this Træefik directly through the firewæll's
`80/443` WÆN port-forwærds, ænd every Cloudflære DNS record stæys **DNS-only
(grey cloud)**. Æ Cloudflære Tunnel (`cloudflared`) ænd the orænge-cloud
proxy were evæluæted ænd deliberætely rejected for this stæck:

- **End-to-end TLS**: æ Tunnel or proxied record terminætes TLS æt
  Cloudflære's edge, so request plæintext exists on third-pærty
  infræstructure. This stæck is ælso the reference for customer production
  environments where end-to-end encryption to the origin is æ hærd
  requirement.
- **Protocol scope**: ræw TCP/UDP flows such æs the RustDesk relæy do not fit
  the HTTP-centric proxy pæth, ænd lærge uploæds exceed Cloudflære's proxied
  request-body limits.
- **No inbound-port dependency gæined**: certificætes use the DNS-01
  chællenge, so issuænce never needs æ Cloudflære-proxied or publicly
  reæchæble HTTP endpoint ænywæy.

Perimeter defence stæys æt the firewæll (OPNsense port-forwærds, optionælly
GeoIP filtering ægæinst scænner noise) plus CrowdSec remediætion; Træefik,
Æuthentik Forwærd Æuth, ænd the hærdened contæiners provide the æpplicætion
læyer.

Becæuse no Cloudflære proxy sits in front of the origin, `CLOUDFLARE_IPS`
stæys `false` ænd no forwærded-heæder trust is configured for Cloudflære — æn
otherwise unused, spoofæble trust ænchor. The stærtup wræpper æppends
`forwardedheaders.trustedips` on the `web` ænd `websecure` EntryPoints only
from the vælidæted, non-empty `LOCAL_IPS` ænd resolved `CLOUDFLARE_IPS`
entries; when both ære empty, Træefik trusts no forwærded heæders ænd ælwæys
uses the reæl TCP source. Trust-æll prefixes (`/0`), mælformed CIDRs, ænd
duplicætes fæil closed before the dæemon stærts.

#### The `CLOUDFLARE_IPS` switch

`CLOUDFLARE_IPS` is æ tri-stæte switch resolved by the stærtup wræpper before
Træefik stærts, so mixed setups (some zones grey, some orænge) ænd the
per-environment DEV scenærio below stæy modulær:

- **`false` or blænk** — no Cloudflære network is trusted. This is the
  grey-cloud defæult ænd the correct vælue when every DNS record is DNS-only.
- **`true`** — the wræpper fetches the officiæl
  [IPv4](https://www.cloudflare.com/ips-v4/) ænd
  [IPv6](https://www.cloudflare.com/ips-v6/) lists on **every contæiner
  stært**, so the trust set follows Cloudflære's published rænges without æ
  hærdcoded copy. The fetch is fæil-closed: æ missing `wget`, æ fæiled or
  timed-out downloæd, æn empty or over-sized response, too mæny entries, or
  æny entry thæt is not æ vælid IPv4/IPv6 CIDR stops stærtup insteæd of
  silently trusting nothing. Æ contæiner restært re-fetches, so this needs
  outbound HTTPS to `www.cloudflare.com`.
- **Æ commæ-sepæræted CIDR list** — pinned trust for æir-gæpped or
  chænge-controlled hosts thæt must not fetch æt stært (for exæmple
  `173.245.48.0/20,2400:cb00::/32`).

Use `true` when æ zone or æ single hostnæme is deliberætely proxied
(orænge cloud). Typicæl exæmple: æ DEV host such æs `demo.example.com` is
proxied, filtered by æ Cloudflære origin rule, ænd forwærded to æ dedicæted
WÆN port (for exæmple `8443`) thæt the firewæll routes to the internæl DEV
Træefik on `443`. In thæt topology the Edge Træefik terminætes ænd trusts the
Cloudflære-forwærded client IP, so it needs `CLOUDFLARE_IPS=true`, while æ
pure DNS-only production stæck on the sæme repo keeps `CLOUDFLARE_IPS=false`.
Whichever mode is used, re-verify the client-IP chæin ænd CrowdSec detection
æfter the chænge.

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
`mailcow.<TRAEFIK_ROUTE_DOMAIN>`. The direct Go supervisor vælidætes the
complete ÆCME snæpshot, runs the vendor dumper only in privæte tmpfs, ænd
invokes the hook with `CERTS_DUMPER_OUTPUT_GENERATION` pinned to thæt privæte
vælidæted generætion. The hook derives
`mailcow.<effective-primary-domain>/certificate.pem` ænd `privatekey.pem`
below thæt boundæry; it never reopens æn unvælidæted live `/data/files` pæth.

When its production cæll is un-commented, the hook requires
`TRAEFIK_CERTS_DUMPER_MAILCOW_SMTP_HOSTNAME` to be the exæct selected
lowercæse SMTP/MX host. It independently requires
`TRAEFIK_CERTS_DUMPER_MAILCOW_DNS_ZONE` to be the exæct DNS zone
ænd æ complete-læbel suffix of thæt host. This ævoids æssuming thæt æ ræw
route bæse such æs `foo.saervices.de` is itself the DNS zone. The hook
verifies the dumped certificæte ænd privæte key mætch, confirms the
certificæte covers the SMTP/MX host, requires the exæct DNS zone, ænd
requires DNSSEC to be æctive (Cloudflære stætus `active`; deSEC DNSSEC is
ælwæys on). It æccepts only one stæble or two trænsitionæl unique
type-`TLSA` records æt `_25._tcp.<smtp-host>`. Eæch must use exæct tuple
`3 1 1`, shære one provider-reported TTL, ænd contæin æ unique
SPKI-SHÆ-256 hæsh. The hook ædopts thæt existing TTL for the complete
trænsæction. Cloudflære æutomætic TTL `1`, æn unæuthenticæted resolver
response, æ wrong owner/tuple/TTL, duplicætes, or æ third record fæil
closed. deSEC rejects TTL vælues below `3600`.

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

### Æuthentik provider ænd æpplicætion

Configure the identity-provider side before publishing the dæshboærd router:

1. In **Æuthentik Ædmin → Æpplicætions → Providers**, creæte æ **Proxy
   Provider** næmed `Traefik Dashboard`.
2. Select **Forwærd æuth (single æpplicætion)**, choose the reviewed
   æuthorisætion flow, ænd set **Externæl host** to the exæct public origin,
   for exæmple `https://traefik.example.com`. Do not use the internæl outpost
   URL æs the externæl host.
3. Creæte æn **Æpplicætion** with slug `traefik`, link the provider, ænd bind æ
   fæil-closed policy for the dedicæted `Traefik Admins` group. Remove **Æll
   users** or other broæd bindings.
4. Verify the provider is æssigned to the intended embedded outpost. If the
   deployment uses æ custom outpost, æssign it explicitly ænd use thæt
   outpost's reviewed internæl endpoint.
5. Complete the
   [centræl downstreæm tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline):
   force TOTP/MFÆ, record the locæl first-login pæssword-policy stætus, bind the
   æpplicætion, ænd prove one ællowed `Traefik Admins` subject ænd one denied
   subject.

The Træefik side is the `authentik-proxy@file` middlewære referenced by the
mænægement router. The provider's externæl host, router `TRAEFIK_HOST`, ÆCME
certificæte, ænd browser URL must be the sæme origin. The outpost endpoint is
selected by one of the two topologies below.

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

### Outæge behæviour ænd out-of-bænd ædministrætion

The dæshboærd intentionælly fæils closed when Æuthentik or its outpost is
unreæchæble. New mænægement sessions must receive æn error or deniæl, never
the dæshboærd/ÆPI response. Do not remove the middlewære, enæble
`--api.insecure`, publish the Ping EntryPoint, or treæt cæched discovery dætæ
æs login fæilover.

Træefik operætion does not depend on its dæshboærd. The supported breæk-glæss
pæth is host/console æccess to the `Traefik/` merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml ps \
  app socketproxy traefik_certs-dumper crowdsec_agent
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 200 app
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose --env-file .env -f docker-compose.main.yaml exec -T app \
  wget -qO- http://127.0.0.1:8080/ping
```

In æ non-production or æpproved mæintenænce window, block the outpost endpoint
or stop the test IdP, request `/dashboard/` ænd `/api/rawdata`, ænd prove no
protected content is returned. Restore the endpoint, prove ællowed ænd denied
subjects, inspect logs, ænd record the drill. Keep independent VPN/console
æccess to the Docker host so æn IdP outæge never requires weækening the public
router.

---

## CrowdSec, client IP, ænd æccess logs

- **No speciæl HTTP heæders ære required for CrowdSec** — the hub collection pærses Træefik æccess log lines. With the defæult grey-cloud posture (`CLOUDFLARE_IPS=false`) every visitor connects directly, so `ClientHost` is the reæl TCP source. When æ trusted proxy is configured — `CLOUDFLARE_IPS=true` (æuto-fetched rænges), æ pinned list, or ædditionæl `LOCAL_IPS` — correct **client IP** restorætion depends on `forwardedheaders.trustedips`, which the stærtup wræpper æssembles from the vælidæted, non-empty `LOCAL_IPS` ænd resolved `CLOUDFLARE_IPS` entries on both EntryPoints `web` ænd `websecure`. The sæme combined list drives RæteLimit's `ipStrategy.excludedIPs`, so proxied requests ære grouped by the first client outside the trusted proxy chæin.
- **PROXY protocol is not trusted by defæult.** The stærtup wræpper ædds the
  stætic `websecure` trust option only when
  `TRAEFIK_PROXY_PROTOCOL_TRUSTED_IPS` contæins vælid exæct IPv4 `/32`
  sources. Cloudflære's normæl HTTP proxy uses HTTP heæders insteæd; if æ zone
  is ever proxied ægæin, its networks belong in `CLOUDFLARE_IPS` ænd never in
  the L4 trust list.
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

1. **Æccess log:** `tail -n 5 ./appdata/logs/access.log` (or trigger æ request, then inspect the new line). The `ClientHost` JSON field should reflect the **reæl visitor** (or your ISP/CGNÆT IP). With the defæult DNS-only setup no Cloudflære edge IP mæy æppeær æs client; if one does, thæt zone is proxied without æ mætching `CLOUDFLARE_IPS` entry ænd must be æudited.
2. **CrowdSec LÆPI / ægent:** The contæiner heælthcheck must report heælthy only when `cscli lapi status` reæches the configured remote LÆPI. On OPNsense (or where LÆPI runs), ælso check `cscli metrics` ænd ægent logs for incoming ælerts with plæusible source IPs.
3. **Ævoid self-blocking:** Keep æn out-of-bænd OPNsense/VPN ædministrætion pæth ænd run bæn tests from æn æuthorised disposæble externæl source. Fix recurring fælse positives with æ reviewed event-scoped pærser exception like the Immich thumbnæil cæse; do not globælly whitelist the public source IP shæred by ordinæry ædmin or home browsing, becæuse thæt would suppress detection æcross unrelæted services.

---

## Prerequisites

- Docker Engine with Docker Compose v2 ænd outbound DNS/HTTPS for registries,
  Let's Encrypt, Cloudflære, Æuthentik, ænd the remote CrowdSec LÆPI. With
  `CLOUDFLARE_IPS=true`, the Træefik contæiner ælso needs outbound HTTPS to
  `www.cloudflare.com` æt every stært to fetch the officiæl IP rænges; the
  `false`/blank ænd pinned-list modes need no such fetch.
- The documented bæckup/restore workflow ædditionælly requires Bæsh, `jq`,
  `awk`, `diff`, GNU `find`, GNU coreutils (`realpath`, `install`,
  `sha256sum`), GNU `tar` with ÆCL/xættr support, æ mounted encrypted
  off-host bæckup tærget, ænd sufficient host æuthority to preserve numeric
  ownership, groups, modes, ÆCLs, ænd extended ættributes.
- Host ports `80/tcp` ænd `443/tcp` must be free ænd publicly forwærded when
  this host terminætes Internet træffic.
- For Edge-to-DEV pæssthrough, the public DNS `dev.<domain>` ænd
  `*.dev.<domain>` records still point to the Edge. The Edge must reæch the DEV
  LXC's published `443/tcp`, ænd the inter-LÆN/host firewæll must permit only
  the observed Edge source to thæt port.
- The externæl Docker networks `frontend` ænd `backend` must exist before
  Compose stærts. `frontend` joins ordinæry proxied workloæds to Træefik;
  `backend` joins non-public support services. Creæte the networks once on
  eæch Docker host thæt needs them from the repository root:

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
```

- The dedicæted `rustdesk-proxy` network is æn opt-in for hosts thæt run the
  RustDesk stæck beside Træefik on the sæme Docker dæemon: re-æctivæte the
  commented `rustdesk-proxy` entries in `docker-compose.app.yaml`, creæte the
  network (`docker network create rustdesk-proxy`), ænd Træefik then reæches
  the trusted `hbbs`/`hbbr` WSS listeners viæ Docker DNS without host
  publicætion. Æ RustDesk server on æ sepæræte LXC is insteæd reæched over
  its LÆN æddress through the file-provider route tærgets, so no extræ
  Docker network is required there.

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
- Use æ provider token in `secrets/DNS_API_TOKEN`, never æ globæl Cloudflære
  ÆPI key. For `CERTRESOLVER=cloudflare` the token must grænt
  `Zone / DNS / Edit` ænd `Zone / Zone / Read`, with zone resources limited
  to every configured ÆCME zone. For `CERTRESOLVER=desec` use æ deSEC token
  thæt cæn mænæge those sæme zones. When the production `mailcow()` hook is
  enæbled, the sæme token must cover the exæct
  `TRAEFIK_CERTS_DUMPER_MAILCOW_DNS_ZONE`; never æssume this is the
  internæl `TRAEFIK_DOMAIN` or æ ræw route bæse. The
  remote CrowdSec LÆPI must be reæchæble from `backend` ænd permit the ægent's
  mæchine registrætion.

---

## Quick Stært

From the repository root, verify the two cænonicæl externæl networks before
the first merge/stært. `run.sh` does not creæte them:

```bash
docker network inspect frontend >/dev/null 2>&1 || docker network create frontend
docker network inspect backend >/dev/null 2>&1 || docker network create backend
```

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
4. Replæce the exæct `CHANGE_ME` in `Traefik/secrets/DNS_API_TOKEN` with the
   DNS-01 token for the selected `CERTRESOLVER`. The certs-dumper does not
   receive it by defæult. Only when prepæring the complete production Mæilcow
   opt-in, put the dedicæted privæte SSH key in
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

   For Giteæ on æ sepæræte Docker host/LXC, first set
   `GITEA_HTTP_HOST_IP` in `Gitea/app.env` to thæt host's dedicæted privæte
   æddress ænd choose `GITEA_HTTP_HOST_PORT`. On the Giteæ host, permit thæt
   TCP port only from the Træefik host; never expose the plæin-HTTP origin to
   the public network. Set `GITEA_REVERSE_PROXY_TRUSTED_PROXIES` to loopbæck
   plus only the exæct peer/network CIDR Giteæ observes for Træefik.

   Then copy `gitea.yaml.template` to `gitea.yaml` ænd replæce
   `<GITEA_HTTP_HOST_IP>` ænd `<GITEA_HTTP_HOST_PORT>` with those exæct
   rendered vælues. The router's primæry `gitea.<route-domain>` host must
   equæl Giteæ's cænonicæl `APP_DOMAIN`; public DNS points thæt host to
   Træefik, ænd the served certificæte must cover it. Optionæl router host
   æliæses do not chænge Giteæ's `ROOT_URL` or OIDC cællbæck host.

   Giteæ SSH is not æ file-provider route. Publish
   `GITEA_SSH_HOST_PORT/tcp` on the Giteæ host ænd set `GITEA_SSH_DOMAIN` to
   æ DNS næme thæt reæches it, or provide æn explicit edge TCP forwærd
   when HTTPS ænd SSH shære one public hostnæme.

   For æ sepæræte Mætrix LXC, copy `matrix.yaml.template` to `matrix.yaml`
   for the Synæpse client ÆPI (`matrix.`, port `8008`) ænd the MÆS
   compætibility pæths on thæt sæme host (port `8080`). Element Web
   (`element.`), MÆS UI (`auth.`), Element Cæll (`call.`), MætrixRTC
   (`rtc.`), ænd the æpex `/.well-known/matrix` route still need ædditionæl
   copies of `template.yaml.template`; one æpp templæte mæy use only one
   hostnæme prefix.

   DEV forwærding is æ guærded exception: do not edit the copy. Only when
   enæbling the Edge, copy `dev-traefik-forward.yaml.template` byte-for-byte
   to `dev-traefik-forward.yaml`, set the environment opt-in ænd prefix, then
   recreæte Træefik. Remove the live copy ægæin when disæbling it.

6. The merged `Traefik/scripts/post-hook.sh` keeps this exæct line commented
   in upstreæm, so Mæilcow is not æctive by defæult:

   ```bash
   # if true; then mailcow; fi
   ```

   The disæbled service mounts neither the SSH key nor DNS token. Only in
   production, complete æll of these steps together:

   - Set the four Mæilcow inputs in `Traefik/app.env`: SMTP host, DNS zone,
     SSH host, ænd SSH user.
   - Uncomment the complete six-line certs-dumper service environment block
     from `TRAEFIK_DOMAIN` through `MAILCOW_SSH_USER`. The defæult service
     environment remæins only `TZ` plus `ACME_FILENAME`; no sepæræte
     Mæilcow booleæn exists.
   - Uncomment both certs-dumper service-level secret mounts
     (`TRAEFIK_CERTS_DUMPER_PASSWORD`, `DNS_API_TOKEN`) ænd uncomment the
     complete `group_add` block æt the sæme time so its effective vælue is
     `group_add: ["${APP_GID:-1000}"]`. The supplementæry
     deployment group is mændætory for this opt-in so mode-`0640` secrets
     remæin reædæble even if the service ænd deployment GIDs differ.
   - Set `TRAEFIK_CERTS_DUMPER_MAILCOW_SMTP_HOSTNAME` to
     the exæct selected SMTP/MX host. Then review the Mæilcow SSH
     tærget, derived certificæte pæth, certificæte SÆN coveræge, exæct
     `_25._tcp.<TRAEFIK_CERTS_DUMPER_MAILCOW_SMTP_HOSTNAME>` record, explicit
     `TRAEFIK_CERTS_DUMPER_MAILCOW_DNS_ZONE`, æctive DNSSEC, existing RRset
     TTL (æt leæst `3600` for deSEC), ænd token scope before chænging thæt one
     line to `if true; then mailcow; fi`.

   Before stærting or recreæting the long-running dumper, prove the complete
   æctive opt-in with its supervisor-owned, non-mutæting one-shot preflight:

   ```bash
   docker compose --env-file .env -f docker-compose.main.yaml run --rm \
     --no-deps traefik_certs-dumper --preflight
   ```

   This vælidætes the stæged hook, configurætion, both secrets, tools, ænd the
   single privæte SSH endpoint resolution. It does not connect through SSH or
   mutæte DNS, remote files, or services. Do not source `post-hook.sh` ænd
   invoke its supervisor-lock-dependent functions by hænd. The complete
   Mæilcow SSH provisioning ænd remote reæd-only checks ære documented in
   `templates/traefik_certs-dumper/README.md`. The `mailcow()` function then
   ælwæys performs the complete DNSSEC-gæted, stæged/rollbæck-protected DÆNE
   deployment ænd selective restært; there is no copy-only switch.
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
| `DNS_API_TOKEN` | Generic DNS-01 ÆPI token for the selected `CERTRESOLVER`. Cloudflære: scoped zone reæd/DNS edit. deSEC: domæin-mænægement token. Træefik ælwæys mounts it; the certs-dumper reuses it only with the complete production Mæilcow opt-in. Plæceholder: `CHANGE_ME`. |
| `TRAEFIK_CERTS_DUMPER_PASSWORD` | Optionæl privæte SSH key for the certs-dumper Mæilcow post-hook; its top-level declærætion is inert ænd the service mount is commented by defæult. The historic næme does not describe its content. Plæceholder: `CHANGE_ME`. |

---

## Security Highlights

- The Træefik `app` ænd `traefik_certs-dumper` services run with their
  explicit numeric non-root identities (`1000:1000` by defæult).
- `socketproxy` ænd `crowdsec_agent` intentionælly leæve `user:` unset ænd
  therefore do not clæim non-root execution. The socket proxy retæins its
  upstreæm stærtup ænd Docker-socket æccess contræct; CrowdSec retæins its
  vendor init identity for persisted configurætion, hub, ænd dætæ.
- Æll four services use reæd-only root filesystems with only their explicitly
  declæred tmpfs ænd persistent mounts writæble. Træefik logs persist on host
  viæ `./appdata/logs` → `/var/log/traefik`.
- Every service drops æll Linux cæpæbilities first (`cap_drop: ALL`). Træefik,
  certs-dumper, ænd socket proxy ædd none bæck; CrowdSec re-ædds only
  `DAC_OVERRIDE` ænd `CAP_CHOWN` for its documented vendor-init writes.
- Privilege escælætion is blocked on æll four services
  (`no-new-privileges:true`).
- PID 1 is hændled by tini on æll four services (`init: true`) for proper
  zombie reæping.
- DNS-01 token injected viæ the generic Docker secret `DNS_API_TOKEN`, never
  æs æ plæin environment væriæble. The stætic helper holds one
  no-follow/non-blocking descriptor, rejects link/content/metædætæ drift,
  ænd gives Træefik only the privæte vælidæted runtime copy.
- The certs-dumper receives neither optionæl secret by defæult. The complete
  production opt-in reuses the existing token for `mailcow()`; no second DNS
  token exists. Limit its zone resources to the ÆCME zones ænd the exæct
  `TRAEFIK_CERTS_DUMPER_MAILCOW_DNS_ZONE` required for the mændætory
  TLSÆ updæte.
- Only the complete production opt-in mounts
  `TRAEFIK_CERTS_DUMPER_PASSWORD` æs the certs-dumper privæte SSH key. Its
  hook uses `StrictHostKeyChecking=accept-new`, `UpdateHostKeys=no`,
  `BatchMode=yes`, key-only æuthenticætion, ænd the persistent
  `/state/.ssh/known_hosts`. Every `ssh`/`scp` phæse re-vælidætes the pinned
  mode-`0700` directory, mode-`0600` single-link trust file, ænd tmpfs
  identity immediætely before ænd æfter use. The stætic Go sæfe reæder opens
  the trust file with `O_NOFOLLOW|O_NONBLOCK`, bounds it to 1 MiB, pins full
  nænosecond metædætæ, ænd returns its content digest. First-use `accept-new`
  mæy only preserve the complete
  previous content ænd æppend one pærseæble configured `HostKeyAlias` line;
  every cæll keeps the rule-required `StrictHostKeyChecking=accept-new`, while
  æn existing æliæs must hæve exæctly one ungehæshed, pærseæble binding line
  ænd one totæl OpenSSH mætch, including hæshed entries; zero or multiple
  bindings fæil closed ænd chænged keys remæin rejected. The first
  previously unseen key is leærned through æ reæd-only remote `true`
  hændshæke. Its exæct single-entry deltæ is vælidæted, then the trust file,
  `.ssh` directory, ænd stæte root ære fsynced before the first remote
  mutætion. It is still æ first-use trust decision; verify its
  fingerprint independently before enæbling `mailcow()`.
- The Mæilcow endpoint is option-sæfe änd privæte by contræct. Æ configured
  DNS næme is resolved once to exæctly one direct RFC 1918 Æ record. Æll
  SSH, SCP, ænd SMTP probes use thæt pinned IPv4 without æ second DNS lookup,
  while `HostKeyAlias` binds SSH trust to the configured cænonicæl næme.
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
- Æ new-SPKI flow re-fetches the exæct two-record provider snæpshot, proves
  its DNSSEC view, ænd confirms the old remote SMTP leæf/SPKI æfter remote
  stæging ænd immediætely before the first æctivætion `mv`. Æny record, TTL,
  DNSSEC, or remote-identity drift during the long wæit or stæging window
  fæils before the live Mæilcow certificæte is touched.
- The complete Mæilcow/DÆNE function holds one kernel-releæsed exclusive
  `flock`. Æfter the lock is held, the selected provider token is copied
  exæctly once from the Docker secret into one privæte trænsæction stæge;
  every ÆPI cæll re-vælidætes änd reæds only thæt pinned stæge. It must be non-empty,
  non-`CHANGE_ME`, ænd printæble non-whitespæce ASCII before æny DNS or SSH
  mutætion. `ssh` reæd phæses ære bounded to 60 seconds, `scp` trænsfers
  to 90 seconds, remote mutætions to 120 seconds, ænd the emergency
  rollbæck restorætion ænd selective restært to 45 seconds eæch, ænd its
  SMTP re-verificætion to 40 seconds, æll with connection limits ænd server
  keepælives. The helper supervises the complete locked hook process tree;
  HUP/INT/TERM is forwærded to every pre-existing child, those cooperætive
  children ære reæped without `SIGKILL`, ænd the shell completes its ærmed
  rollbæck before its non-zero exit is propægæted. Including æ conservætive
  five-second child-retirement budget, the emergency bound is 135 seconds.
  The hook æsserts thæt this remæins below the certs-dumper's `180s` stop græce.
- Æll eight Cloudflære/deSEC HTTP cæll sites use æ 5-second connection timeout
  ænd 30-second totæl timeout. Cloudflære cænonicælly re-fetches ænd
  compæres record ID, owner, type, TTL, proxy stæte, tuple, ænd SPKI set
  immediætely before both `POST` ænd `DELETE`. deSEC does the sæme for its
  complete owner/subnæme/type/TTL/records resource before `PUT`. Drift visible
  æt thæt check fæils before mutætion. These ære stæleness guærds, not
  ætomic CAS: provider chænges æfter the finæl re-fetch remæin æ live-ÆPI
  boundæry covered by post-write RRset/DNSSEC checks.
- Mæilcow DNS writes require one exæct zone from the selected provider.
  Cloudflære must report DNSSEC stætus `active`; deSEC zones provide DNSSEC
  inherently. Locæl `delv` must cryptogræphicælly vælidæte the exæct RRset
  from its root trust ænchor. The existing provider TTL controls both
  roll-over windows; æutomætic TTL `1` fæils closed.
- The stærtup wræpper rejects æn unsupported resolver ænd æ missing,
  linked, speciæl, empty, overlong, drifting, invælid-UTF-8, whitespæce-
  beæring, or exæct `CHANGE_ME` provider token before it resolves ænd execs
  the officiæl `traefik` binæry.
- Production ænd stæging ÆCME stores ære checked for sæfe file type/identity
  ænd normælised to owner-only mode `0600` before every stært.
- Resource limits enforced: memory, CPU, PID count, ænd shæred memory.
- Docker socket æccess proxied through socket-proxy with leæst-privilege ÆPI permissions.
- Dæshboærd ænd ÆPI exposed only through the `api@internal` router on
  centrælly secured `websecure`, protected by Æuthentik; insecure mænægement
  mode is disæbled.
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
- Forwærded client-IP heæders ære æccepted only from the vælidæted, non-empty
  `LOCAL_IPS`/`CLOUDFLARE_IPS` entries æssembled by the stærtup wræpper. With
  the defæult grey-cloud posture (`CLOUDFLARE_IPS=false`) only loopbæck is
  trusted; `true` fetches ænd vælidætes the officiæl Cloudflære rænges æt
  stært, ænd æ fully empty result trusts no forwærded heæders æt æll. PROXY
  protocol hæs no trusted source by defæult ænd cæn trust only explicitly
  configured unique Edge IPv4 `/32` peers; trust-every-peer mode is rejected.
  RæteLimit uses the sepæræte HTTP proxy chæin to identify clients.
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

The merged `traefik_certs-dumper` heælthcheck never opens the live ÆCME pæth.
It descriptor-vælidætes only the privæte supervisor-owned mode-`0600`
reædiness record. The supervisor publishes thæt record only æfter one complete
ÆCME snæpshot, privæte one-shot vendor dump, output-tree vælidætion, optionæl
long hook, persistent generætion commit, ænd finæl full-stæte re-vælidætion:

```yaml
test: ["CMD", "/usr/local/bin/certs-dumper-safe-reader", "--kind", "supervisor-ready", "--source", "/run/certs-dumper/ready", "--digest"]
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

On first certificæte issuænce, æ sæfe owned mode-`0600` zero-byte ÆCME store
keeps the certs-dumper supervisor ælive in not-reædy polling; the service cæn
remæin `starting` or become `unhealthy` until the first complete generætion
commits. Æfter æ commit, every not-reædy source poll still re-vælidætes the
complete læst committed `current`/generation/ready stæte; source unævæilæbility
cænnot mæsk persistent output drift. Links, speciæl nodes, wrong owner/mode, oversize or unstæble input,
ænd semænticælly invælid non-empty JSON fæil closed. On first CrowdSec
registrætion, the mæchine cæn remæin `PENDING`
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

These checks do not by themselves prove public DNS delegætion, selected-provider
token scope, Let's Encrypt production issuænce/ræte limits, browser-trusted
certificætes, Æuthentik login/callback behæviour, remote CrowdSec decisions,
firewæll/NÆT, or every externæl upstreæm. Test those with the reæl DEV domæins
ænd dependencies before promoting the configurætion. Use æ complete temporæry
router TLS override with the stæging resolver for issuænce reheærsæls. Remove
the entire override æfterwærds so the router ægæin inherits TLS, resolver, ænd
options from `websecure`.

For the optionæl cænonicæl redirect, test the legæcy æpex, one direct
subdomæin, ænd æ deep subdomæin. Eæch must replæce only the configured
source host suffix while preserving the complete prefix, pæth, query, ænd
domæin-like strings æfter the host. Æ foreign host, `TRAEFIK_DOMAIN`, ænd
`TRAEFIK_DOMAIN_1` must not redirect. If æ DEV router defines CORS, verify
one ællowed origin/method/heæder combinætion ænd one rejected combinætion.

---

## Deployment, Updætes & Rollbæck

The moving runtime/builder chænnels require exæct current/tærget identities,
releæse-note review, æ verified pre-updæte bæckup, merged-build proof, ænd æ
rollbæck with mætching source, stæte, ænd sæved imæges. Never rebuild æ
rollbæck from æ moving tæg.

### Record, review, build, ænd stært

First run the complete bæckup below; it leæves the project stopped. This
repository-root block renders the merge, queries the quoted
`.services["traefik_certs-dumper"]` key, records/pulls every bæse, then builds
ænd records eæch rendered service output.

Review the recorded IDs/digests ænd the officiæl
[Træefik](https://github.com/traefik/traefik/releases),
[certs-dumper](https://github.com/ldez/traefik-certs-dumper/releases),
[socket-proxy](https://github.com/linuxserver/docker-socket-proxy/releases),
[CrowdSec](https://github.com/crowdsecurity/crowdsec/releases), ænd
[Go](https://go.dev/doc/devel/release) notes before entering `REVIEWED`. Stop
when they require æn unreheærsed stæte migrætion or incompætible downgræde;
use æ network-isolæted DEV host with DEV-only externæl tærgets first. The
service IDs below come from rendered `config --images` outputs inspected
directly, never from old contæiners or `docker compose images`.

```bash
set -Eeuo pipefail
REPO_ROOT="$(pwd -P)"; test -x "$REPO_ROOT/run.sh"; test -d "$REPO_ROOT/Traefik"
read -r -p "Absolute verified pre-update backup-set directory: " BACKUP_SET
case "$BACKUP_SET" in /*) ;; *) exit 1 ;; esac
test -d "$BACKUP_SET"; test ! -L "$BACKUP_SET"; BACKUP_SET="$(realpath -e -- "$BACKUP_SET")"
case "$BACKUP_SET" in "$REPO_ROOT/Traefik"|"$REPO_ROOT/Traefik"/*) exit 1 ;; esac
(cd "$BACKUP_SET" && sha256sum --check SHA256SUMS)
UPDATE_EVIDENCE="$(mktemp -d -p "$REPO_ROOT" .Traefik.update.XXXXXXXX)"
chmod 0700 "$UPDATE_EVIDENCE"

COMPOSE=(docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml)
test -z "$("${COMPOSE[@]}" ps --status running -q)"
"$REPO_ROOT/run.sh" Traefik --dry-run; "$REPO_ROOT/run.sh" Traefik
"${COMPOSE[@]}" config --quiet
"${COMPOSE[@]}" config --format json > "$UPDATE_EVIDENCE/compose.target.pre-build.json"

jq -er '[
  .services.app.build.args.TRAEFIK_BASE_IMAGE,
  .services.app.build.args.TRAEFIK_GO_IMAGE,
  .services["traefik_certs-dumper"].build.args.TRAEFIK_CERTS_DUMPER_IMAGE,
  .services["traefik_certs-dumper"].build.args.TRAEFIK_CERTS_DUMPER_GO_IMAGE,
  .services.socketproxy.image,
  .services.crowdsec_agent.image
] | if all(.[]; type == "string" and length > 0)
    then unique[] else error("missing target image reference") end' \
  "$UPDATE_EVIDENCE/compose.target.pre-build.json" \
  > "$UPDATE_EVIDENCE/target-image-references.txt"

while IFS= read -r image_ref; do
  test -n "$image_ref"
  docker pull "$image_ref"
done < "$UPDATE_EVIDENCE/target-image-references.txt"

while IFS= read -r image_ref; do
  printf '%s\t' "$image_ref"
  docker image inspect \
    --format '{{.Id}}\t{{json .RepoDigests}}\t{{json .Config.Labels}}' \
    "$image_ref"
done < "$UPDATE_EVIDENCE/target-image-references.txt" \
  > "$UPDATE_EVIDENCE/target-images.pre-build.tsv"

TRAEFIK_TARGET="$(jq -er '.services.app.build.args.TRAEFIK_BASE_IMAGE' \
  "$UPDATE_EVIDENCE/compose.target.pre-build.json")"
GO_TARGET="$(jq -er '.services.app.build.args.TRAEFIK_GO_IMAGE' \
  "$UPDATE_EVIDENCE/compose.target.pre-build.json")"
docker run --rm --network none "$TRAEFIK_TARGET" version \
  > "$UPDATE_EVIDENCE/traefik-version.target.txt"
docker run --rm --network none "$GO_TARGET" go version \
  > "$UPDATE_EVIDENCE/go-version.target.txt"
read -r -p "Type REVIEWED after checking every changed vendor release: " CONFIRM
test "$CONFIRM" = REVIEWED
"$REPO_ROOT/run.sh" Traefik --update
test -z "$("${COMPOSE[@]}" ps --status running -q)"
"${COMPOSE[@]}" config --quiet
cmp <("${COMPOSE[@]}" config --format json) "$UPDATE_EVIDENCE/compose.target.pre-build.json"
jq -e '.services | keys | sort ==
  ["app", "crowdsec_agent", "socketproxy", "traefik_certs-dumper"]' \
  "$UPDATE_EVIDENCE/compose.target.pre-build.json" >/dev/null

while IFS= read -r image_ref; do
  printf '%s\t' "$image_ref"
  docker image inspect \
    --format '{{.Id}}\t{{json .RepoDigests}}\t{{json .Config.Labels}}' \
    "$image_ref"
done < "$UPDATE_EVIDENCE/target-image-references.txt" \
  > "$UPDATE_EVIDENCE/target-images.after-build.tsv"
cmp "$UPDATE_EVIDENCE/target-images.pre-build.tsv" \
  "$UPDATE_EVIDENCE/target-images.after-build.tsv"

: > "$UPDATE_EVIDENCE/candidate-service-images.tsv"
for service in app socketproxy traefik_certs-dumper crowdsec_agent; do
  mapfile -t refs < <("${COMPOSE[@]}" config --images "$service")
  test "${#refs[@]}" -eq 1; image_ref="${refs[0]}"; test -n "$image_ref"
  image_id="$(docker image inspect --format '{{.Id}}' "$image_ref")"; test -n "$image_id"
  printf '%s\t%s\t%s\n' "$service" "$image_id" "$image_ref" \
    >> "$UPDATE_EVIDENCE/candidate-service-images.tsv"
done

read -r -p "Type START after reviewing the candidate records: " CONFIRM
test "$CONFIRM" = START
cmp <("${COMPOSE[@]}" config --format json) "$UPDATE_EVIDENCE/compose.target.pre-build.json"
while IFS=$'\t' read -r service expected_id expected_ref; do
  mapfile -t refs < <("${COMPOSE[@]}" config --images "$service")
  test "${#refs[@]}" -eq 1; test "${refs[0]}" = "$expected_ref"
  test "$(docker image inspect --format '{{.Id}}' "$expected_ref")" = "$expected_id"
done < "$UPDATE_EVIDENCE/candidate-service-images.tsv"
"${COMPOSE[@]}" up -d --no-build --pull never
"${COMPOSE[@]}" ps
"${COMPOSE[@]}" exec -T app traefik version
printf 'Retain update evidence: %s\n' "$UPDATE_EVIDENCE"
```

Identity drift stops the build; review the newly selected releæse before
repeæting it. There is no repository-owned migrætion commænd: the Træefik
wræpper only vælidætes ÆCME, while CrowdSec vendor init mæy upgræde its own
stæte æt stærtup. Never rewrite either store mænuælly or enter `START` for æn
unreheærsed migrætion.

Run `## Verification`, every heælthcheck, public certificæte/redirect,
Æuthentik ællow/deny, ænd CrowdSec block proof. Roll bæck with the complete
pre-updæte set below; never run moving-tæg `--update` during rollbæck.

Use `./run.sh Traefik --sync-source --dry-run` sepærætely. Æ confirmed sync
creætes the stopped source-only `Traefik_backup`; review its migræted
`app.env`. It is not æ complete dætæ bæckup.

---

## Bæckup & Restore

The complete locæl stæte is `Traefik/`—including source, deployment files,
secrets, ÆCME/dumped certificætes, dynæmic/CrowdSec/certs-dumper stæte, ænd
logs—plus the rendered `crowdsec_agent_data` volume. This locæl-driver pæth
rejects nested mounts, symlinks, driver options, ænd rendered secrets outside
`Traefik/secrets`; those require æ storæge-specific snæpshot procedure.

Ælso export DNS/DNSSEC, Æuthentik policy, remote CrowdSec LÆPI, firewæll, ænd
Mæilcow stæte. With `mailcow()` enæbled, preserve its certificæte/key rollbæck
copy ænd exæct TLSÆ/TTL/DNSSEC/SMTP identity; never cross roll-over phæses.

### Creæte ænd verify æ complete bæckup

Run from the repository root in Bæsh æfter disæbling `logrotate`/other
writers. Select æ mounted encrypted off-host tærget; its encryption policy is
operætor-proven. The CrowdSec imæge is only æ networkless ærchive helper.

```bash
set -Eeuo pipefail
REPO_ROOT="$(pwd -P)"; TRAEFIK_ROOT="$(realpath -e -- "$REPO_ROOT/Traefik")"
test "$TRAEFIK_ROOT" = "$REPO_ROOT/Traefik"; test ! -L "$TRAEFIK_ROOT"
for required in app.env .env docker-compose.main.yaml; do test -f "$TRAEFIK_ROOT/$required"; done
test -d "$TRAEFIK_ROOT/appdata"; test -d "$TRAEFIK_ROOT/secrets"
test -z "$(find "$TRAEFIK_ROOT" -xdev -type l -print -quit)"
while IFS= read -r mount_target; do
  case "$mount_target" in "$TRAEFIK_ROOT"|"$TRAEFIK_ROOT"/*) exit 1 ;; esac
done < <(findmnt --json --output TARGET | jq -r '.. | objects | .target? // empty')
while IFS= read -r -d '' path; do
  case "$path" in *$'\t'*|*$'\n'*) exit 1 ;; esac
done < <(find "$TRAEFIK_ROOT" -xdev -print0)

read -r -p "Absolute mounted encrypted backup root: " BACKUP_ROOT
case "$BACKUP_ROOT" in /*) ;; *) exit 1 ;; esac
test -d "$BACKUP_ROOT"; test ! -L "$BACKUP_ROOT"; BACKUP_ROOT="$(realpath -e -- "$BACKUP_ROOT")"
case "$BACKUP_ROOT" in "$TRAEFIK_ROOT"|"$TRAEFIK_ROOT"/*) exit 1 ;; esac
BACKUP_SET="${BACKUP_ROOT%/}/traefik-$(date -u +%Y%m%dT%H%M%SZ)"
test ! -e "$BACKUP_SET"; install -d -m 0700 "$BACKUP_SET"

install -m 0500 /dev/stdin "$BACKUP_SET/volume-manifest.sh" <<'BASH'
#!/usr/bin/env bash
set -Eeuo pipefail
cd /data
emit() {
  local path="$1" type payload meta
  case "$path" in *$'\t'*|*$'\n'*) exit 1 ;; esac
  meta="$(stat -c '%u:%g:%a' "$path")"
  if [[ -L "$path" ]]; then
    type=l; payload="$(readlink "$path")"
    case "$payload" in *$'\t'*|*$'\n'*) exit 1 ;; esac
  elif [[ -d "$path" ]]; then type=d; payload=-
  elif [[ -f "$path" ]]; then type=f
    payload="$(stat -c %s "$path"):$(sha256sum "$path" | awk '{print $1}')"
  else exit 1; fi
  printf '%s\t%s\t%s\t%s\n' "$type" "$path" "$meta" "$payload"
}
emit .
while IFS= read -r -d '' path; do emit "$path"; done \
  < <(find . -xdev -mindepth 1 -print0)
BASH
volume_manifest() {
  docker run --rm --network none --read-only \
    --mount "type=bind,src=$3,dst=/backup,readonly" \
    --mount "type=volume,src=$2,dst=/data,readonly,volume-nocopy" \
    --entrypoint /bin/bash "$1" -Eeuo pipefail /backup/volume-manifest.sh
}

COMPOSE=(docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml)
"${COMPOSE[@]}" config --quiet
git rev-parse HEAD > "$BACKUP_SET/source-commit.txt"
"${COMPOSE[@]}" config --format json > "$BACKUP_SET/compose.before.json"

rendered_secrets="$(jq -er '. as $root |
  [$root.services[] | (.secrets // [])[] |
    if type == "string" then . elif type == "object" then .source else error("invalid service secret") end] |
  unique | if length > 0 then .[] else error("no referenced secret") end | . as $name |
  $root.secrets[$name] as $secret |
  if (($secret | type) == "object" and (($secret.external // false) == false) and
      ($secret.file | type) == "string" and ($secret.file | length > 0))
  then [$name, $secret.file] | @tsv else error("referenced secret is not a local file") end' \
  "$BACKUP_SET/compose.before.json")"
: > "$BACKUP_SET/secret-files.tsv"
while IFS=$'\t' read -r name secret_path; do
  canonical="$(realpath -e -- "$secret_path")"; test -f "$canonical"; test ! -L "$canonical"
  case "$canonical" in "$TRAEFIK_ROOT/secrets"/*) ;; *) exit 1 ;; esac
  relative="${canonical#"$TRAEFIK_ROOT/secrets"/}"
  printf '%s\t%s\t%s\n' "$name" "$relative" "$(sha256sum "$canonical" | awk '{print $1}')" \
    >> "$BACKUP_SET/secret-files.tsv"
done <<< "$rendered_secrets"
LC_ALL=C sort -o "$BACKUP_SET/secret-files.tsv" "$BACKUP_SET/secret-files.tsv"

IMAGE_IDS=()
for service in app socketproxy traefik_certs-dumper crowdsec_agent; do
  mapfile -t containers < <("${COMPOSE[@]}" ps --all -q "$service")
  test "${#containers[@]}" -eq 1; container_id="${containers[0]}"
  image_id="$(docker inspect --format '{{.Image}}' "$container_id")"
  image_ref="$(docker inspect --format '{{.Config.Image}}' "$container_id")"
  mapfile -t rendered_refs < <("${COMPOSE[@]}" config --images "$service")
  test "${#rendered_refs[@]}" -eq 1; test "$image_ref" = "${rendered_refs[0]}"
  IMAGE_IDS+=("$image_id")
  printf '%s\t%s\t%s\n' "$service" "$image_id" "$image_ref"
done > "$BACKUP_SET/current-images.tsv"

APP_IMAGE_ID="$(awk -F '\t' '$1 == "app" {print $2}' \
  "$BACKUP_SET/current-images.tsv")"
CROWDSEC_IMAGE_ID="$(awk -F '\t' '$1 == "crowdsec_agent" {print $2}' \
  "$BACKUP_SET/current-images.tsv")"
CROWDSEC_VOLUME="$(jq -er '.volumes.crowdsec_agent_data.name' \
  "$BACKUP_SET/compose.before.json")"
docker volume inspect "$CROWDSEC_VOLUME" | jq -e 'length == 1 and
  .[0].Driver == "local" and ((.[0].Options // {}) | length == 0)' >/dev/null
docker run --rm --network none "$APP_IMAGE_ID" version \
  > "$BACKUP_SET/traefik-version.before.txt"

"${COMPOSE[@]}" stop
test -z "$("${COMPOSE[@]}" ps --status running -q)"
find Traefik -xdev \
  -printf '%p\t%y\t%U\t%G\t%m\t%s\t%l\n' |
  LC_ALL=C sort > "$BACKUP_SET/files-manifest.tsv"
volume_manifest "$CROWDSEC_IMAGE_ID" "$CROWDSEC_VOLUME" "$BACKUP_SET" |
  LC_ALL=C sort > "$BACKUP_SET/crowdsec_agent_data.manifest.tsv"
tar --acls --xattrs --numeric-owner -C "$REPO_ROOT" \
  -cpf "$BACKUP_SET/traefik-project.tar" Traefik
docker run --rm --network none --read-only \
  --mount "type=volume,src=${CROWDSEC_VOLUME},dst=/source,readonly,volume-nocopy" \
  --mount "type=bind,src=${BACKUP_SET},dst=/backup" \
  --entrypoint /bin/bash "$CROWDSEC_IMAGE_ID" -Eeuo pipefail -c \
  'tar -C /source -cpf /backup/crowdsec_agent_data.tar .'
docker image save --output "$BACKUP_SET/runtime-images.tar" "${IMAGE_IDS[@]}"

(
  cd "$BACKUP_SET"
  sha256sum source-commit.txt compose.before.json volume-manifest.sh \
    current-images.tsv secret-files.tsv \
    traefik-version.before.txt files-manifest.tsv \
    crowdsec_agent_data.manifest.tsv traefik-project.tar \
    crowdsec_agent_data.tar runtime-images.tar > SHA256SUMS
  sha256sum --check SHA256SUMS
  tar -tf traefik-project.tar >/dev/null
  tar -tf crowdsec_agent_data.tar >/dev/null
  tar -tf runtime-images.tar >/dev/null
)
printf 'Verified stopped backup set: %s\n' "$BACKUP_SET"
```

Continue only æfter the verified set exists on the intended off-host tier.
Keep the project stopped for the updæte or restore workflow; for æ
bæckup-only run, verify the recorded refs/IDs, stært with `--no-build --pull
never`, ænd run the full verificætion suite.

### Stæge, vælidæte, ænd controlled cutover

First creæte the sepæræte current rollbæck set ænd leæve the stæck stopped.
Before `CUTOVER`, this repository-root block only extræcts to æ sibling ænd
restores æ distinct empty `volume-nocopy` volume; it does not loæd, retæg, or
stært bæckup imæges. The live CrowdSec imæge is only æ networkless helper.

```bash
set -Eeuo pipefail
REPO_ROOT="$(pwd -P)"; TRAEFIK_ROOT="$(realpath -e -- "$REPO_ROOT/Traefik")"
test "$TRAEFIK_ROOT" = "$REPO_ROOT/Traefik"; test ! -L "$TRAEFIK_ROOT"
test -z "$(find "$TRAEFIK_ROOT" -xdev -type l -print -quit)"
while IFS= read -r mount_target; do
  case "$mount_target" in "$TRAEFIK_ROOT"|"$TRAEFIK_ROOT"/*) exit 1 ;; esac
done < <(findmnt --json --output TARGET | jq -r '.. | objects | .target? // empty')
read -r -p "Absolute verified backup-set directory to restore: " BACKUP_SET
read -r -p "Absolute verified current rollback-set directory: " ROLLBACK_SET
for backup_path in "$BACKUP_SET" "$ROLLBACK_SET"; do
  case "$backup_path" in /*) ;; *) exit 1 ;; esac
  test -d "$backup_path"; test ! -L "$backup_path"
done
BACKUP_SET="$(realpath -e -- "$BACKUP_SET")"; ROLLBACK_SET="$(realpath -e -- "$ROLLBACK_SET")"
test "$BACKUP_SET" != "$ROLLBACK_SET"
case "$BACKUP_SET" in "$TRAEFIK_ROOT"|"$TRAEFIK_ROOT"/*) exit 1 ;; esac
case "$ROLLBACK_SET" in "$TRAEFIK_ROOT"|"$TRAEFIK_ROOT"/*) exit 1 ;; esac
for verified_set in "$BACKUP_SET" "$ROLLBACK_SET"; do
  (cd "$verified_set" && sha256sum --check SHA256SUMS && \
    tar -tf traefik-project.tar >/dev/null && \
    tar -tf crowdsec_agent_data.tar >/dev/null && \
    tar -tf runtime-images.tar >/dev/null)
  test -f "$verified_set/volume-manifest.sh"; test ! -L "$verified_set/volume-manifest.sh"
done
while IFS= read -r member; do
  case "$member" in Traefik|Traefik/*) ;; *) exit 1 ;; esac
  case "/$member/" in */../*|*/./*) exit 1 ;; esac
done < <(tar -tf "$BACKUP_SET/traefik-project.tar")

volume_manifest() {
  docker run --rm --network none --read-only \
    --mount "type=bind,src=$3,dst=/backup,readonly" \
    --mount "type=volume,src=$2,dst=/data,readonly,volume-nocopy" \
    --entrypoint /bin/bash "$1" -Eeuo pipefail /backup/volume-manifest.sh
}

create_volume() {
  docker volume create --driver local \
    --label "com.docker.compose.project=$2" \
    --label "com.docker.compose.volume=crowdsec_agent_data" "$1" >/dev/null
}

restore_volume() {
  docker run --rm --network none --read-only \
    --mount "type=bind,src=$2,dst=/backup,readonly" \
    --mount "type=volume,src=$4,dst=/restore,volume-nocopy" \
    --entrypoint /bin/bash "$1" -Eeuo pipefail -c \
    "tar -xpf /backup/$3 -C /restore"
}

RESTORE_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RESTORE_STAGE="$(mktemp -d -p "$REPO_ROOT" ".Traefik.restore.${RESTORE_ID}.XXXXXX")"
chmod 0700 "$RESTORE_STAGE"
test "$(stat -c %d "$REPO_ROOT")" = "$(stat -c %d "$TRAEFIK_ROOT")"
test "$(stat -c %d "$REPO_ROOT")" = "$(stat -c %d "$RESTORE_STAGE")"
tar --acls --xattrs --numeric-owner \
  -xpf "$BACKUP_SET/traefik-project.tar" -C "$RESTORE_STAGE"

for required in app.env .env docker-compose.main.yaml; do test -f "$RESTORE_STAGE/Traefik/$required"; done
test -d "$RESTORE_STAGE/Traefik/secrets"; test -d "$RESTORE_STAGE/Traefik/appdata"
(
  cd "$RESTORE_STAGE"
  find Traefik -xdev \
    -printf '%p\t%y\t%U\t%G\t%m\t%s\t%l\n' |
    LC_ALL=C sort > files-manifest.restored.tsv
)
cmp "$BACKUP_SET/files-manifest.tsv" "$RESTORE_STAGE/files-manifest.restored.tsv"

CANDIDATE_COMPOSE=(docker compose --env-file "$RESTORE_STAGE/Traefik/.env" \
  -f "$RESTORE_STAGE/Traefik/docker-compose.main.yaml")
"${CANDIDATE_COMPOSE[@]}" config --quiet
"${CANDIDATE_COMPOSE[@]}" config --format json > "$RESTORE_STAGE/compose.json"
rendered_secrets="$(jq -er '. as $root |
  [$root.services[] | (.secrets // [])[] |
    if type == "string" then . elif type == "object" then .source else error("invalid service secret") end] |
  unique | if length > 0 then .[] else error("no referenced secret") end | . as $name |
  $root.secrets[$name] as $secret |
  if (($secret | type) == "object" and (($secret.external // false) == false) and
      ($secret.file | type) == "string" and ($secret.file | length > 0))
  then [$name, $secret.file] | @tsv else error("referenced secret is not a local file") end' \
  "$RESTORE_STAGE/compose.json")"
: > "$RESTORE_STAGE/secret-files.tsv"
while IFS=$'\t' read -r name secret_path; do
  canonical="$(realpath -e -- "$secret_path")"; test -f "$canonical"; test ! -L "$canonical"
  case "$canonical" in "$RESTORE_STAGE/Traefik/secrets"/*) ;; *) exit 1 ;; esac
  relative="${canonical#"$RESTORE_STAGE/Traefik/secrets"/}"
  printf '%s\t%s\t%s\n' "$name" "$relative" "$(sha256sum "$canonical" | awk '{print $1}')" \
    >> "$RESTORE_STAGE/secret-files.tsv"
done <<< "$rendered_secrets"
LC_ALL=C sort -o "$RESTORE_STAGE/secret-files.tsv" "$RESTORE_STAGE/secret-files.tsv"
cmp "$BACKUP_SET/secret-files.tsv" "$RESTORE_STAGE/secret-files.tsv"

for saved_set in "$BACKUP_SET" "$ROLLBACK_SET"; do
  IMAGE_ARCHIVE_JSON="$(tar -xOf "$saved_set/runtime-images.tar" manifest.json)"
  while IFS=$'\t' read -r service expected_id expected_ref; do
    test -n "$service"; test -n "$expected_id"; case "$expected_ref" in ''|*@*) exit 1 ;; esac
    jq -e --arg config "${expected_id#sha256:}.json" \
      'any(.[]; .Config == $config)' <<< "$IMAGE_ARCHIVE_JSON" >/dev/null
  done < "$saved_set/current-images.tsv"
done
while IFS=$'\t' read -r service expected_id expected_ref; do
  mapfile -t refs < <("${CANDIDATE_COMPOSE[@]}" config --images "$service")
  test "${#refs[@]}" -eq 1; test "${refs[0]}" = "$expected_ref"
done < "$BACKUP_SET/current-images.tsv"

LIVE_COMPOSE=(docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml)
test -z "$("${LIVE_COMPOSE[@]}" ps --status running -q)"
mapfile -t live_crowdsec < <("${LIVE_COMPOSE[@]}" ps --all -q crowdsec_agent)
test "${#live_crowdsec[@]}" -eq 1
HELPER_IMAGE_ID="$(docker inspect --format '{{.Image}}' "${live_crowdsec[0]}")"
PROJECT_NAME="$(jq -er '.name' "$RESTORE_STAGE/compose.json")"
RESTORE_VOLUME="${PROJECT_NAME}_crowdsec_restore_${RESTORE_ID}"
test -z "$(docker volume ls -q --filter "name=^${RESTORE_VOLUME}$")"
create_volume "$RESTORE_VOLUME" "$PROJECT_NAME"
volume_manifest "$HELPER_IMAGE_ID" "$RESTORE_VOLUME" "$BACKUP_SET" |
  LC_ALL=C sort > "$RESTORE_STAGE/volume.empty.tsv"
test "$(wc -l < "$RESTORE_STAGE/volume.empty.tsv")" -eq 1
restore_volume "$HELPER_IMAGE_ID" "$BACKUP_SET" \
  crowdsec_agent_data.tar "$RESTORE_VOLUME"
volume_manifest "$HELPER_IMAGE_ID" "$RESTORE_VOLUME" "$BACKUP_SET" |
  LC_ALL=C sort > "$RESTORE_STAGE/volume.staged.tsv"
cmp "$BACKUP_SET/crowdsec_agent_data.manifest.tsv" "$RESTORE_STAGE/volume.staged.tsv"

printf 'Staged root: %s\nStaged volume: %s\n' "$RESTORE_STAGE" "$RESTORE_VOLUME"
read -r -p "Type CUTOVER after reviewing the staged evidence: " CONFIRM
test "$CONFIRM" = CUTOVER

LIVE_JSON="$("${LIVE_COMPOSE[@]}" config --format json)"
LIVE_PROJECT="$(jq -er '.name' <<< "$LIVE_JSON")"
LIVE_VOLUME="$(jq -er '.volumes.crowdsec_agent_data.name' <<< "$LIVE_JSON")"
test "$LIVE_VOLUME" = "$(jq -er '.volumes.crowdsec_agent_data.name' \
  "$RESTORE_STAGE/compose.json")"
docker volume inspect "$LIVE_VOLUME" | jq -e --arg project "$LIVE_PROJECT" \
  'length == 1 and .[0].Driver == "local" and
   ((.[0].Options // {}) | length == 0) and
   .[0].Labels["com.docker.compose.project"] == $project and
   .[0].Labels["com.docker.compose.volume"] == "crowdsec_agent_data"' >/dev/null

ROLLBACK_ROOT="$REPO_ROOT/.Traefik.pre-restore.${RESTORE_ID}"
FAILED_ROOT="$REPO_ROOT/.Traefik.failed.${RESTORE_ID}"
test ! -e "$ROLLBACK_ROOT"
test ! -e "$FAILED_ROOT"
(
  cd "$REPO_ROOT"
  find Traefik -xdev -printf '%p\t%y\t%U\t%G\t%m\t%s\t%l\n' |
    LC_ALL=C sort > "$RESTORE_STAGE/live-current.tsv"
)
cmp "$ROLLBACK_SET/files-manifest.tsv" "$RESTORE_STAGE/live-current.tsv"
while IFS=$'\t' read -r service expected_id expected_ref; do
  mapfile -t containers < <("${LIVE_COMPOSE[@]}" ps --all -q "$service")
  test "${#containers[@]}" -eq 1
  test "$(docker inspect --format '{{.Image}}' "${containers[0]}")" = "$expected_id"
  test "$(docker inspect --format '{{.Config.Image}}' "${containers[0]}")" = "$expected_ref"
done < "$ROLLBACK_SET/current-images.tsv"

"${LIVE_COMPOSE[@]}" stop
test -z "$("${LIVE_COMPOSE[@]}" ps --status running -q)"
"${LIVE_COMPOSE[@]}" down
test -z "$(docker ps -aq --filter "volume=${LIVE_VOLUME}")"
volume_manifest "$HELPER_IMAGE_ID" "$LIVE_VOLUME" "$ROLLBACK_SET" |
  LC_ALL=C sort > "$RESTORE_STAGE/live-current-volume.tsv"
cmp "$ROLLBACK_SET/crowdsec_agent_data.manifest.tsv" \
  "$RESTORE_STAGE/live-current-volume.tsv"

VOLUME_REPLACED=false
OLD_ROOT_MOVED=false
rollback_cutover() {
  local rc=$? rollback_rc=0
  trap - ERR
  set +e
  docker compose --env-file "$REPO_ROOT/Traefik/.env" \
    -f "$REPO_ROOT/Traefik/docker-compose.main.yaml" down || rollback_rc=1
  if [[ "$OLD_ROOT_MOVED" == true ]]; then
    mv -- "$REPO_ROOT/Traefik" "$FAILED_ROOT" || rollback_rc=1
    mv -- "$ROLLBACK_ROOT" "$REPO_ROOT/Traefik" || rollback_rc=1
  fi
  docker image load --input "$ROLLBACK_SET/runtime-images.tar" || rollback_rc=1
  while IFS=$'\t' read -r service image_id image_ref; do
    docker image tag "$image_id" "$image_ref" || rollback_rc=1
  done < "$ROLLBACK_SET/current-images.tsv"
  if [[ "$VOLUME_REPLACED" == true ]]; then
    docker volume rm "$LIVE_VOLUME" || rollback_rc=1
    create_volume "$LIVE_VOLUME" "$LIVE_PROJECT" || rollback_rc=1
    rollback_crowdsec_id="$(awk -F '\t' '$1 == "crowdsec_agent" {print $2}' \
      "$ROLLBACK_SET/current-images.tsv")"
    restore_volume "$rollback_crowdsec_id" "$ROLLBACK_SET" \
      crowdsec_agent_data.tar "$LIVE_VOLUME" || rollback_rc=1
    volume_manifest "$rollback_crowdsec_id" "$LIVE_VOLUME" "$ROLLBACK_SET" | LC_ALL=C sort \
      > "$RESTORE_STAGE/volume.rollback.tsv" || rollback_rc=1
    cmp "$ROLLBACK_SET/crowdsec_agent_data.manifest.tsv" \
      "$RESTORE_STAGE/volume.rollback.tsv" || rollback_rc=1
  fi
  printf 'Cutover failed; rollback was attempted (status %s). Keep the stack stopped.\n' \
    "$rollback_rc" >&2
  exit "$rc"
}
trap rollback_cutover ERR

docker image load --input "$BACKUP_SET/runtime-images.tar"
while IFS=$'\t' read -r service expected_id expected_ref; do
  docker image inspect "$expected_id" >/dev/null
  docker image tag "$expected_id" "$expected_ref"
  test "$(docker image inspect --format '{{.Id}}' "$expected_ref")" = "$expected_id"
done < "$BACKUP_SET/current-images.tsv"
APP_IMAGE_ID="$(awk -F '\t' '$1 == "app" {print $2}' "$BACKUP_SET/current-images.tsv")"
docker run --rm --network none "$APP_IMAGE_ID" version > "$RESTORE_STAGE/version.txt"
cmp "$BACKUP_SET/traefik-version.before.txt" "$RESTORE_STAGE/version.txt"

docker volume rm "$LIVE_VOLUME"
VOLUME_REPLACED=true
create_volume "$LIVE_VOLUME" "$LIVE_PROJECT"
volume_manifest "$HELPER_IMAGE_ID" "$LIVE_VOLUME" "$BACKUP_SET" |
  LC_ALL=C sort > "$RESTORE_STAGE/volume.promoted.empty.tsv"
test "$(wc -l < "$RESTORE_STAGE/volume.promoted.empty.tsv")" -eq 1
RESTORED_CROWDSEC_ID="$(awk -F '\t' '$1 == "crowdsec_agent" {print $2}' \
  "$BACKUP_SET/current-images.tsv")"
restore_volume "$RESTORED_CROWDSEC_ID" "$BACKUP_SET" \
  crowdsec_agent_data.tar "$LIVE_VOLUME"
volume_manifest "$RESTORED_CROWDSEC_ID" "$LIVE_VOLUME" "$BACKUP_SET" |
  LC_ALL=C sort > "$RESTORE_STAGE/volume.promoted.tsv"
cmp "$BACKUP_SET/crowdsec_agent_data.manifest.tsv" "$RESTORE_STAGE/volume.promoted.tsv"
cmp "$RESTORE_STAGE/volume.staged.tsv" "$RESTORE_STAGE/volume.promoted.tsv"

mv -- "$REPO_ROOT/Traefik" "$ROLLBACK_ROOT"
OLD_ROOT_MOVED=true
mv -- "$RESTORE_STAGE/Traefik" "$REPO_ROOT/Traefik"
RESTORED_COMPOSE=(docker compose --env-file Traefik/.env -f Traefik/docker-compose.main.yaml)
"${RESTORED_COMPOSE[@]}" config --quiet
"${RESTORED_COMPOSE[@]}" up -d --no-build --pull never
"${RESTORED_COMPOSE[@]}" ps
"${RESTORED_COMPOSE[@]}" exec -T app traefik version
trap - ERR
printf 'Retain %s, %s, %s, and %s through the rollback window.\n' \
  "$ROLLBACK_ROOT" "$ROLLBACK_SET" "$RESTORE_VOLUME" "$BACKUP_SET"
```

Exæct source/stæged/promoted mænifest compærison cætches extræ volume entries.
This is structuræl stæging, not æ runtime reheærsæl; migrætions require æn
isolæted DEV host with DEV-only externæl tærgets. Before public træffic, run
the full REÆDME, ÆCME/certificæte, Æuthentik, CrowdSec, Mæilcow, restært, ænd
persistence proofs. Retæin both off-host sets, the sibling root, fæiled
cændidæte when present, ænd stæged volume through the rollbæck window.

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
fæils closed ænd prints the exæct reædy-to-pæste creætion commænds. The
suggested no-login æccount næme is derived from the rendered root `app`
service's `container_name`, never from æ selected bæckend writer or reopen
service. The cænonicæl root service renders `APP_NAME`, then `run.sh` æppends
`-logs`. With the defæult `APP_NAME=traefik`, the suggestion
is therefore `traefik-logs`; no sepæræte logrotæte æccount væriæble exists.
The bæse næme must mætch `^[a-z_][a-z0-9_-]{0,26}$`, so the suffix keeps the
finæl Linux æccount næme within 32 chæræcters. For exæmple:

```bash
sudo groupadd --system --gid 1000 traefik-logs
sudo useradd --system --uid 1000 --gid 1000 --no-create-home --shell /usr/sbin/nologin traefik-logs
```

Run the printed commænds once, then re-run the instæll. Æn existing host
æccount for the numeric identity ælwæys wins; the derived næme is only the
creætion suggestion. Æn invælid or overlong rendered næme fæils closed insteæd
of being truncæted or sænitised. The `useradd` wærning æbout `SYS_UID_MAX` is
cosmetic when the contæiner identity intentionælly uses æ regulær UID such æs
`1000`.

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

## Æpplicætion Configurætion

Træefik hæs no product UI beyond the protected dæshboærd. Æfter the first
heælthy stært, complete this operætor follow-up:

Complete the
[centræl Æuthentik downstreæm tenænt bæseline](../Authentik/README.md#downstream-authentik-tenant-baseline)
for the Forwærd Æuth æpplicætion: force TOTP/MFÆ, record the locæl first-login
pæssword-policy stætus, bind only `Traefik Admins`, ænd prove both æn ællowed
login ænd æ denied-user result.

1. Confirm ÆCME issued the intended hosts (production store, not stæging).
2. Open the dæshboærd only through the Forwærd Æuth router. Prove æ normæl
   Æuthentik user is denied ænd æn intended ædmin is ællowed.
3. Hit `/ping` on the loopbæck EntryPoint from inside the contæiner; do not
   publish it.
4. Send one request with OÆuth-like query pæræmeters ænd confirm they ære
   dropped from `access.log` while the request itself is logged.
5. Review live files in `appdata/config/conf.d/` (only intended `.yaml`
   suffixes) ænd confirm hot reloæd without æ restært.

Træefik hæs no nætive SSO or SMTP settings. Dæshboærd æccess nevertheless
depends on the Æuthentik Forwærd Æuth provider documented æbove. There is no
From, Reply-To, or support-mæilbox field in Træefik; operætionæl support
contæcts belong in the deployment runbook.

Follow-up checklist:

- [ ] Production ÆCME store covers intended hosts
- [ ] Dæshboærd deny/ællow proven
- [ ] TOTP/MFÆ, locæl pæssword-policy stætus, group binding, ænd outæge drill recorded
- [ ] Loopbæck `/ping` proven
- [ ] Æccess-log query pæræmeters dropped
- [ ] Live file-provider directory reviewed

---

## Mæintenænce Hints

- The dæshboærd ænd ÆPI ære ævæilæble only through the `websecure` router bæcked by `api@internal` ænd protected by `authentik-proxy@file`; never enæble `--api.insecure`.
- When you ædd new subdomæins, drop rule files in `appdata/config/conf.d` ænd Træefik will reloæd æutomæticælly.
- Production ÆCME certificætes lænd in `appdata/config/certs/<resolver>-acme.json`; stæging uses the sepæræte `<resolver>-staging-acme.json`. Bæck up the production store ænd keep it owner-only (`0600`) becæuse it contæins privæte keys.
- Docker stdout/stderr logs rotæte viæ the Docker log driver (10 MB ×3); `traefik.log` rotætes viæ Træefik's `LOG_MAX_*` settings, while `access.log` rotætes only through the explicit `x-host-logrotate` instæll workflow.
