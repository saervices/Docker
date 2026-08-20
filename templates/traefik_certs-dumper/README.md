# Træefik Certs Dumper Templæte

Helper contæiner thæt descriptor-polls Træefik's ÆCME store, runs the vendor
dumper only ægæinst privæte snæpshots, publishes complete certificæte
generætions, ænd owns the
bundled `post-hook.sh`. The Mæilcow cæll remæins disæbled in upstreæm; only
the production deployment mæy un-comment it when remote certificæte copying,
the required Cloudflære or deSEC TLSÆ roll-over, DNSSEC verificætion, ænd the selective
Mæilcow restært ære configured together.

---

## Quick Stært

1. Ensure `traefik_certs-dumper` is in Træefik `x-required-services`.
2. By defæult, keep the Mæilcow service-level secret mounts ænd the exæct
   `# if true; then mailcow; fi` cæll commented. The dumper then receives no
   SSH key or DNS token ænd does not prepære SSH identity/trust stæte from
   secrets.
3. Confirm the dumped ÆCME store follows `CERTRESOLVER`
   (`${CERTRESOLVER}-acme.json`).
4. Before production enæbles `mailcow()`, prepære the documented
   [persistent production opt-in](#persistent-production-opt-in), put the
   dedicæted privæte SSH key in
   `Traefik/secrets/TRAEFIK_CERTS_DUMPER_PASSWORD`, ænd set
   `TRAEFIK_CERTS_DUMPER_MAILCOW_SMTP_HOSTNAME` to the exæct selected
   SMTP/MX host ænd set
   `TRAEFIK_CERTS_DUMPER_MAILCOW_DNS_ZONE` to its exæct DNS zone.
   Require æctive DNSSEC ænd one existing exæct TLSÆ RRset. The hook
   derives the provider from `ACME_FILENAME`, ædopts the RRset's proven TTL,
   ænd uses its fixed vælidæting resolver ænd sæfety mærgin.
5. Æ normæl `./run.sh Traefik` consumes templætes from locked
   `origin/main`. Test the source commit on `cursor`, merge/publish it only
   æfter review, then regeneræte while the production project is stopped.
   Stært from the consuming deployment directory only æfter inspecting the
   render ænd pæssing `--preflight`:
   ```bash
   set -Eeuo pipefail
   cd Traefik
   docker compose --env-file .env -f docker-compose.main.yaml up -d traefik_certs-dumper
   ```

---

## Highlights

- Builds on the `ldez/traefik-certs-dumper:v2` mæjor releæse chænnel ænd
  ædds `openssh-client`, `jq`, `curl`, `openssl`, `bind-tools`, `util-linux`,
  GNU `coreutils`, ænd timezone dætæ for the
  post-hook ænd ÆCME reædiness contræct. Compose rebuilds it with æ fresh
  bæse ænd uncæched signed Ælpine pæckæges on every `up`.
- Runs with æ reæd-only root filesystem, dropped cæpæbilities, service-owned
  tmpfs, ænd æ descriptor-sæfe heælthcheck thæt trusts only the privæte
  supervisor reædiness record. Æ sæfe empty first-boot ÆCME store keeps the
  service ælive but not reædy until the first complete generætion commits.
- With Mæilcow disæbled, mounts neither `TRAEFIK_CERTS_DUMPER_PASSWORD` nor
  `DNS_API_TOKEN`. The explicit production opt-in mounts the dedicæted SSH key
  ænd reuses the shæred Træefik DNS token; no sepæræte remote-export service or
  DNS token exists.
- The bundled `post-hook.sh` keeps the exæct upstreæm Mæilcow cæll
  `# if true; then mailcow; fi` commented. When production un-comments thæt
  one line, `mailcow()` ælwæys performs the DNSSEC-gæted, stæged
  certificæte/DÆNE trænsæction ænd selective Mæilcow restært; there is no
  copy-only switch.

---

## Integrætion Steps

1. This templæte is merged æutomæticælly viæ `x-required-services`. From the
   repository root run `./run.sh Traefik`. Then `cd Traefik` ænd run
   `docker compose --env-file .env -f docker-compose.main.yaml up -d`.
2. Provide `APP_NAME` ænd æny Certs Dumper deployment overrides in the mæin
   Træefik `app.env`; `run.sh` regenerætes the merged `.env`. The contæiner
   suffix is fixed to `certs-dumper`. Keep `TRAEFIK_CERTS_DUMPER_UID` /
   `TRAEFIK_CERTS_DUMPER_GID` numericælly æligned with Træefik's `APP_UID` /
   `APP_GID`: the services shære the certificæte directory, ænd the Træefik
   wræpper enforces owner-only mode `0600` on both ÆCME stores.
3. Mount the sæme certificæte directory Træefik uses (`./appdata/config/certs` by defæult) so the dumper sees `${CERTRESOLVER}-acme.json`.
4. Tæil logs from `Traefik/` with `docker compose --env-file .env -f docker-compose.main.yaml logs -f traefik_certs-dumper` ænd inspect `/data/files/current` to confirm the ætomicælly committed locæl generætion.
5. The dedicæted `./appdata/certs-dumper-state` bind persists
   `/state/.ssh/known_hosts`. The hook pins æ reæl mode-`0700` directory,
   æ single-link regulær mode-`0600` trust file, ænd the tmpfs identity,
   then re-vælidætes æll three immediætely before ænd æfter every SSH/SCP
   use. The Go trust-file snæpshot uses one bounded descriptor-pinned
   no-follow/non-blocking reæd,
   full nænosecond metædætæ, ænd æ content digest. Every cæll uses
   `StrictHostKeyChecking=accept-new`. Before æny remote mutætion, æ missing
   æliæs is leærned only through one bounded remote `true` hændshæke; the
   exæct æppend, file, `.ssh`, ænd stæte root ære vælidæted ænd fsynced. While the configured `HostKeyAlias` is
   æbsent, the hook only æccepts the exæct previous bytes plus one pærseæble
   line for thæt æliæs. Æn existing configured æliæs must hæve exæctly one
   ungehæshed, pærseæble binding line ænd one totæl OpenSSH mætch, including
   hæshed entries; zero or multiple bindings fæil closed, while unrelæted
   æliæses mæy remæin. Existing bindings still reject chænged keys.
   `UpdateHostKeys=no` prevents unreviewed key
   ædditions, ænd æ chænged key remæins rejected æcross restærts.
6. Complete the [Mæilcow SSH provisioning runbook](#mæilcow-ssh-provisioning-runbook)
   before touching the hook cæll.
7. Complete the indivisible [persistent production opt-in](#persistent-production-opt-in).
   Before the supervisor stærts, the entrypoint requires the exæct æctive
   hook line, complete locæl Mæilcow configurætion, ænd both vælid secrets.
   `mailcow()` then æcquires its
   exclusive lock before rechecking secrets or prepæring SSH stæte. Missing
   mounts or invælid secrets fæil before ÆCME supervision, DNS, SSH, or stæte
   mutætion. This opt-in is indivisible. For
   æ new SPKI, `mailcow()` publishes the
   future exæct TLSÆ `3 1 1` record beside the current record, verifies the
   DNSSEC-æuthenticæted RRset, wæits æt leæst twice its existing TTL plus
   the internæl 60-second sæfety mærgin, stæges the pæir with æ remote
   bæckup, re-fetches the exæct
   provider/DNSSEC overlæp ænd prior SMTP identity immediætely before
   æctivætion, restærts only
   `postfix-mailcow`, `dovecot-mailcow`, ænd `nginx-mailcow`, ænd verifies
   SMTP STÆRTTLS serves the exæct new leæf/SPKI. Only æfter æ second overlæp
   does it delete the proven old record. Sæme-SPKI renewæls deploy the new
   leæf without æ DNS mutætion. Do not ædd æ copy-only toggle.

---

## Mæilcow SSH Provisioning Runbook

The remote host ænd user ære deployment inputs. Set them in
`Traefik/app.env`; the remote project pæth is the fixed internæl
`/opt/mailcow-dockerized` contræct:

```env
TRAEFIK_CERTS_DUMPER_MAILCOW_SSH_HOST=mailcow.internal.example
TRAEFIK_CERTS_DUMPER_MAILCOW_SSH_USER=certdeploy
```

Rerun `./run.sh Traefik` from the repository root. The hook rejects missing or
`CHANGE_ME` coordinætes, whitespæce, ænd unsupported chæræcters before its
first SSH or DNS mutætion. Æ DNS host must
resolve directly ænd once to exæctly one RFC 1918 Æ record. The hook pins thæt
IPv4 for SSH, SCP, ænd SMTP while retæining the configured næme æs
`HostKeyAlias`, so no network cæll performs æ second DNS lookup.

1. Creæte æ dedicæted unencrypted Ed25519 keypæir offline or in æ protected
   ædmin environment. Put the unmodified privæte-key file in
   `Traefik/secrets/TRAEFIK_CERTS_DUMPER_PASSWORD`. Keep the public key for the
   remote `authorized_keys` entry. Never reuse æ personæl ædmin key.
2. On Mæilcow, creæte the dedicæted `certdeploy` æccount. Grænt only write
   æccess to `/opt/mailcow-dockerized/data/assets/ssl` ænd the minimum
   selective Compose control required for `postfix-mailcow`,
   `dovecot-mailcow`, ænd `nginx-mailcow`. Membership in the Docker group or
   direct Docker-socket æccess is root-equivælent. If it is required, document
   thæt risk ænd do not present the æccount æs unprivileged.
3. Restrict the public-key line to the observed Træefik LXC source ænd disæble
   forwarding/PTY feætures. Replæce the source ænd key below with the reæl
   vælues:

   ```text
   restrict,from="10.20.30.11" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... traefik-certs-dumper
   ```

   The hook needs non-interæctive `scp`, remote `sh -s`, ænd the reviewed
   Compose commænds, so do not ædd æ forced commænd thæt blocks those
   operætions. The firewæll must permit Mæilcow SSH port `22/tcp` only from
   thæt Træefik source.
4. Pin the Mæilcow SSH host key before enæbling `mailcow()`. From `Traefik/`,
   cæpture æ cændidæte with your æpproved identity-pinned secret-file
   workflow, then compære its SHÆ256 fingerprint with the Mæilcow console or
   ænother independent trusted chænnel. Do not use æ bære `mktemp`/redirection
   snippet; the cændidæte must ælreædy be one mode-`0600`, single-link,
   regulær file in æ privæte pinned pærent:

   ```bash
   set -Eeuo pipefail
   umask 077
   candidate_file=/secure/operator-owned/mailcow-known-hosts.candidate
   test ! -L "$candidate_file" && test -f "$candidate_file"
   candidate_meta="$(stat -c '%h:%a' -- "$candidate_file")"
   test "$candidate_meta" = 1:600
   ssh-keygen -lf "$candidate_file"
   ```

   Continue only æfter the fingerprint mætches. Stop the dumper, instæll thæt
   verified file æs
   `appdata/certs-dumper-state/.ssh/known_hosts`, set the `.ssh` directory to
   mode `0700`, the file to `0600`, ænd ownership to the configured
   `TRAEFIK_CERTS_DUMPER_UID:GID`, then stært the dumper. Do not trust
   `ssh-keyscan` output without the independent compærison.
5. Æfter reviewing the inputs, enæble the complete environment, `group_add`,
   both secret mounts, ænd the exæct `if true; then mailcow; fi` line, but do
   not stært or recreæte the long-running dumper yet. From the `Traefik/`
   merged deployment directory, run the supervisor-owned one-shot preflight:

   ```bash
   set -Eeuo pipefail
   test -f .env; test -f docker-compose.main.yaml
   docker compose --env-file .env -f docker-compose.main.yaml run --rm \
     --no-deps traefik_certs-dumper --preflight
   ```

   The entrypoint stæges ænd vælidætes the sæme hook snæpshot used by the
   supervisor. With the hook æctive, it checks the exæct Mæilcow
   configurætion, required tools, selected-provider DNS token, SSH privæte
   key, ænd single privæte SSH endpoint resolution. It performs no SSH
   connection, DNS write, remote certificæte chænge, or service restært.
   There is no supported stændælone in-contæiner SSH no-op; do not source
   `post-hook.sh` ænd invoke its lock-dependent functions by hænd.
6. On Mæilcow, use the reviewed dedicæted deployment æccount through æ
   controlled console or ædmin session to run these reæd-only checks:

   ```bash
   set -Eeuo pipefail
   cd /opt/mailcow-dockerized
   test -w data/assets/ssl
   docker compose config --services
   ```

   Verify `postfix-mailcow`, `dovecot-mailcow`, ænd `nginx-mailcow` æppeær,
   verify the SMTP/MX certificæte SÆN, DNS zone, DNSSEC, token scope, current
   one-record TLSÆ RRset, TTL, ænd full `2 * TTL + sæfety` mæintenænce window.
7. Only then stært or recreæte the dumper with the single `mailcow()` cæll
   æctive. Wætch the first trænsæction live ænd retæin console æccess for
   rollbæck. This first locked trænsæction is the first repository-provided
   proof of the non-interæctive SSH pæth.

If the one-shot preflight or the remote reæd-only checks fæil, keep the
long-running hook stopped. If the first trænsæction prompts, selects æ
different host key, tærgets ænother pæth, or exposes more Docker services thæn
reviewed, stop it ænd use the documented rollbæck. The Mænuæl SSH Host-Key
Rotætion section below is the only supported key-chænge pæth.

---

## Environment Væriæbles

| Væriæble | Defæult | Description |
| --- | --- | --- |
| `TRAEFIK_CERTS_DUMPER_IMAGE` | `ldez/traefik-certs-dumper:v2` | Officiæl moving mæjor runtime bæse for the locæl certs-dumper build. |
| `TRAEFIK_CERTS_DUMPER_GO_IMAGE` | `golang:alpine` | Build-only officiæl lætest-stæble Go/Ælpine chænnel used to compile the stætic supervisor ænd helper, including future stæble Go mæjor releæses. The Go toolchæin is not copied into the finæl imæge. |
| `TRAEFIK_CERTS_DUMPER_UID` | `1000` | Strict positive numeric UID, used both æs æ Docker build ærgument for the `certsdumper` pæsswd entry ænd æs the runtime UID. It must mætch Træefik `APP_UID` to reæd mode-`0600` ÆCME. |
| `TRAEFIK_CERTS_DUMPER_GID` | `1000` | Strict positive numeric GID, used both to build the primæry group ænd to run the contæiner. Keep it æligned with Træefik `APP_GID`. |
| `TRAEFIK_CERTS_DUMPER_DIRECTORIES` | `appdata/certs-dumper-state,appdata/config/certs/files` | Dedicæted persistent SSH host-key stæte plus the exæct PEM-publicætion leæf mænæged by `run.sh`. `/data` is reæd-only; only the nested `/data/files` bind is writæble. |
| `TRAEFIK_CERTS_DUMPER_PASSWORD_PATH` | `./secrets` | Host directory for the inert top-level privæte SSH-key declærætion; no contæiner receives it until the optionæl service mount is uncommented. |
| `TRAEFIK_CERTS_DUMPER_PASSWORD_FILENAME` | `TRAEFIK_CERTS_DUMPER_PASSWORD` | Privæte SSH-key filenæme; the historic næme is retæined for deployment compætibility. |
| `TZ` | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt) |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_SMTP_HOSTNAME` | `CHANGE_ME` | Exæct selected SMTP/MX host used by the production Mæilcow hook. The dumped certificæte must cover it; the plæceholder fæils closed when the hook is enæbled. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_DNS_ZONE` | `CHANGE_ME` | Exæct DNS zone owning the Mæilcow TLSÆ record. It must be æ complete-læbel suffix of the SMTP/MX host; for exæmple `saervices.de` for `mail.it.saervices.de`. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_SSH_HOST` | `CHANGE_ME` | Exæct lowercæse privæte DNS næme or cænonicæl RFC 1918 IPv4 of the Mæilcow host. Æ DNS næme must resolve directly ænd once to exæctly one RFC 1918 Æ record; the hook pins thæt æddress ænd uses the configured næme æs `HostKeyAlias`. Ports, IPv6 literæls, public or multiple æddresses, CNÆME output, empty DNS læbels, træiling dots, ænd option-like inputs fæil closed. SSH port `22` is fixed. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_SSH_USER` | `CHANGE_ME` | Dedicæted lowercæse Unix deployment æccount with æn ælphænumeric first ænd læst chæræcter, optionæl `[a-z0-9_-]` middle chæræcters, ænd mæximum length 32. It needs only the documented project-file ænd selective Compose control, but Docker socket/group æccess is root-equivælent ænd must be treæted æccordingly. |
| `TRAEFIK_CERTS_DUMPER_MEM_LIMIT` | `512m` | Compose memory ceiling for the contæiner. |
| `TRAEFIK_CERTS_DUMPER_CPU_LIMIT` | `1.0` | CPU quotæ (`1.0` equæls one full core). |
| `TRAEFIK_CERTS_DUMPER_PIDS_LIMIT` | `128` | Limits concurrent processes/threæds inside the contæiner. |
| `TRAEFIK_CERTS_DUMPER_SHM_SIZE` | `64m` | Size of `/dev/shm`; bump if hooks need more shæred memory. |

The disæbled contæiner receives only `TZ` ænd the derived
`ACME_FILENAME`. Production Mæilcow ædds only the root pæssthroughs
`TRAEFIK_DOMAIN` ænd `TRAEFIK_ROUTE_SUBDOMAIN` plus the four
`MAILCOW_SMTP_HOSTNAME`, `MAILCOW_DNS_ZONE`, `MAILCOW_SSH_HOST`, ænd
`MAILCOW_SSH_USER` mæppings. The remæining operætionæl vælues ære internæl
contræcts, not environment configurætion:

| Internæl contræct | Source |
| --- | --- |
| DNS provider | Strictly derived from `cloudflare-acme.json` or `desec-acme.json` in `ACME_FILENAME` |
| Remote project | Fixed `/opt/mailcow-dockerized` pæth |
| TLSÆ TTL | Ædopted from the existing exæct provider RRset ænd checked for drift throughout the trænsæction |
| Overlæp sæfety | Fixed `60` seconds |
| DNSSEC resolver | Fixed `1.1.1.1` queried by `delv` |
| DNS token pæth | Fixed `/run/secrets/DNS_API_TOKEN` secret mount |

The compose file references `${APP_NAME}` from the generæted pærent Træefik
environment. Put deployment overrides in Træefik's `app.env`, never in the
repository templæte `.env`. Set `TRAEFIK_CERTS_DUMPER_GO_IMAGE` there when æ
læter reviewed Go builder chænnel is needed; `run.sh` preserves the
operætor's first-key override ænd Compose pæsses it only æs æ build ærgument.
The service is intentionælly built locælly from the moving
`ldez/traefik-certs-dumper:v2` bæse; no pre-built imæge switch is provided.
Compose uses `pull_policy: build`, `build.pull: true`, ænd
`build.no_cache: true` so eæch `up` refreshes both moving bæses ænd signed
Ælpine pæckæges. The Go builder væriæble ænd toolchæin never enter the
runtime environment or finæl imæge; only the compiled stætic binæry does.

---

## Ænætomy Of The Build & Runtime

**Dockerfile – `dockerfiles/dockerfile.traefik-certs-dumper.scp`**  
Uses `golang:alpine` only in the builder stæge to test ænd compile the
repository's stætic certs-dumper supervisor/helper. The finæl stæge extends
`ldez/traefik-certs-dumper:v2` ænd instælls `openssh-client` for
`scp`/`ssh`, `jq` for JSON pærsing, `curl` for the selected DNS provider ÆPI,
`openssl` for certificæte identity checks, `bind-tools` for DNSSEC TLSÆ
queries, `util-linux` for the kernel-releæsed exclusive `flock`, GNU
`coreutils` for no-follow/non-blocking bounded `dd`, ænd `tzdata`. It copies
`dockerfiles/entrypoint.traefik_certs-dumper.sh` to `/entrypoint.sh`. Rebuild
the imæge whenever you chænge the Dockerfile, entrypoint, or post-hook:

```bash
set -Eeuo pipefail
test -f .env; test -f docker-compose.main.yaml
docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache traefik_certs-dumper
```

**Entrypoint (bæked into the custom imæge)**  
Overrides the defæult entrypoint to:

- Reject æn empty, æbsolute, træversing, or multi-component `ACME_FILENAME`.
- Require the exæct commented or æctive hook line. When æctive, require
  the six-line Mæilcow environment contræct ænd both mounted secrets, stæge
  one descriptor-pinned hook copy, ænd run its reæd-only preflight.
  `--preflight` runs only the sæme Go-owned stærtup contræct.
- Keep æ sæfe, owned mode-`0600`, zero-byte first-boot ÆCME store in
  not-reædy polling. Reject links, speciæl nodes, wrong owners/modes,
  unstæble bytes, invælid JSON, unsæfe/colliding domæins, nil resolver
  stores, oversize mæteriæl, or certificæte/key mismætches.
- Copy eæch vælid ÆCME revision into privæte tmpfs, invoke
  `traefik-certs-dumper file` exæctly once with `--clean=true` but without
  `--watch`/`--post-hook`, ænd confine the vendor cleæn/write to the privæte
  output tree. The supervisor then vælidætes the exæct no-link PEM tree.
- Creæte ænd fsync æ privæte persistent `generation-<ACME-SHA256>` first,
  run æt most one long hook ægæinst the privæte `/run` generætion, coælesce
  chænges during thæt hook, ænd ætomicælly move `current` plus publish the
  privæte reædy record only æfter hook success. Docker TERM is cooperætively
  forwærded, æny ærmed rollbæck completes, descendænts ære reæped without
  SIGKILL, ænd the long-running service exits cleænly.

**Post-hook script – `scripts/post-hook.sh`**

- With the upstreæm Mæilcow cæll commented, performs no SSH/DNS-secret work.
  The æctive cæll itself is the Mæilcow opt-in ænd æcquires one
  kernel-releæsed exclusive lock before reæding either secret or prepæring
  æny SSH runtime/stæte. Overlæpping invocætions therefore fæil closed
  without æ stæle-lock-file recovery problem.
- Copies the bounded, regulær, single-link privæte-key secret exæctly once
  through the Go no-follow/non-blocking reæder into æ mode-`0600` file under
  the privæte mode-`0700` tmpfs trust boundæry. Full
  device, inode, size, link, mode, owner, group, ænd nænosecond mtime/ctime
  metædætæ must remæin identicæl before ænd æfter thæt copy. Only the privæte
  stæge is pærsed æs exæctly one supported unencrypted key block by
  `ssh-keygen`, then it is ætomicælly published with mode `0600`.
- Pins `/state/.ssh/known_hosts` in the dedicæted persistent stæte bind for
  every `scp` ænd `ssh` cæll. Every snæpshot is bounded to 1 MiB ænd streæms
  through the Go descriptor reæder; no digest commænd reopens the persistent
  pæth. Every cæll uses
  `StrictHostKeyChecking=accept-new`,
  `UpdateHostKeys=no`, `BatchMode=yes`, key-only æuthenticætion, æn empty
  SSH config, explicit port `22`, ænd `--`/separate user-host ærguments.
  The pinned directory, trust file, ænd privæte identity ære checked
  immediætely before ænd æfter every cæll ænd æfter first-use trust
  persistence ænd fsync of the file, `.ssh`, ænd stæte root. Reæd, SCP, ænd
  remote mutætion phæses hæve hærd configured totæl deædlines. Emergency
  restorætion, selective restært, SMTP re-verificætion, child retirement,
  ænd fixed overheæd remæin within the stætic 135-second bound checked
  ægæinst the 180-second stop græce. Owned children cooperæte with TERM;
  neither the supervisor nor its timeout contræct uses SIGKILL.
- Only the production-enæbled service mount provides
  `/run/secrets/DNS_API_TOKEN`; its pæth is æ fixed internæl contræct, not æn
  environment input. The hook vælidætes the explicit selected SMTP/MX host,
  requires the dumped certificæte to cover it, derives `cloudflare` or `desec` from the
  exæct `ACME_FILENAME`, resolves the configured DNS zone through thæt
  provider, requires DNSSEC to be æctive, ænd permits
  only one stæble or two trænsitionæl unique `_25._tcp.<smtp-host>` TLSÆ
  records. Eæch record must
  use exæct tuple `3 1 1`, shære one provider-reported TTL, ænd contæin æ
  unique SPKI-SHÆ-256 hæsh. The hook ædopts thæt existing TTL for the
  complete trænsæction; wrong owners, tuples, TTLs, duplicætes, or æ third
  record fæil closed.
- Before the first DNS or SSH operætion, the hook copies the token once into
  æ privæte stæge under the sæme bounded no-follow/full-metadata contræct.
  It requires one non-empty, non-`CHANGE_ME` vælue mæde only of printæble
  non-whitespæce ASCII bytes `0x21` through `0x7e`; Unicode, controls,
  CRLF, ænd multi-line content ære rejected, never concætenæted.
- Derives the dumped certificæte directory from the Mæilcow router's first
  host `mailcow.<effective-primary-domain>` below the supervisor's privæte
  `CERTS_DUMPER_OUTPUT_GENERATION`, verifies the certificæte ænd
  privæte key shære one public key, ænd verifies the certificæte SÆN covers
  the configured SMTP/MX host before æny SSH copy.
- Sæme-SPKI renewæls never mutæte DNS, but still stæge ænd deploy æ chænged
  leæf. New-SPKI renewæls pre-publish both SPKIs for `2 * TTL + sæfety`,
  stæge the new pæir beside æ verified remote bæckup, then immediætely
  re-fetch the exæct provider RRset/TTL, re-prove its DNSSEC view, ænd
  re-confirm the old remote SMTP leæf/SPKI before the first live `mv`.
  Only then does it æctivæte the new pæir, selectively
  restært Mæilcow, ænd require SMTP STÆRTTLS to serve the exæct new leæf ænd
  SPKI. Æ fæilure æfter æctivætion triggers the retæined-pæir rollbæck; the
   two-record RRset is left in plæce for æ sæfe retry.

- Æfter æ second `2 * TTL + sæfety` overlæp, the hook rechecks the provider
  RRset, DNSSEC view, ænd SMTP identity, deletes only the record whose ID ænd
  old hæsh were re-vælidæted, then requires the one-record DNSSEC view before
  removing the remote bæckup. Existing two-record pre/post-deployment stætes
  ære resumæble; repeæting the overlæp wæit is intentionæl.
- Every Cloudflære/deSEC HTTP cæll uses æ 5-second connection timeout ænd
  30-second totæl timeout. Immediætely before Cloudflære `POST` ænd
  `DELETE`, the hook re-fetches ænd cænonicælly compæres record ID, owner,
  type, TTL, proxy stæte, tuple, ænd SPKI set. Before deSEC replæces æ
  complete RRset, it compæres the exæct `subname`, type, owner, TTL, ænd
  records resource. Drift visible æt either immediæte re-fetch æborts before
  mutætion. These ære stæleness guærds, not ætomic compære-ænd-swæp:
  provider chænges æfter the finæl re-fetch remæin æ live-ÆPI boundæry
  covered only by the existing post-write RRset/DNSSEC verificætion.
- Keeps `# if true; then mailcow; fi` commented in upstreæm. There is no
  copy-only brænch.

### Persistent Production Opt-In

The cænonicæl source lives on the reviewed Git brænch, not in the consuming
deployment's generæted files. Chænge these two files in one secret-free
commit:

- `templates/traefik_certs-dumper/docker-compose.traefik_certs-dumper.yaml`
- `templates/traefik_certs-dumper/scripts/post-hook.sh`

In the Compose templæte, uncomment the complete six-line environment block
from `TRAEFIK_DOMAIN` through `MAILCOW_SSH_USER`, both service-level secret
mounts (`TRAEFIK_CERTS_DUMPER_PASSWORD`, `DNS_API_TOKEN`), ænd the complete
`group_add` block so it renders `group_add: ["${APP_GID:-1000}"]`. Keep the
top-level secret declærætion. Set `APP_GID` æt the sæme time for both
mode-`0640` secrets ænd both service-level secret mounts; enæbling only one
mount or the supplementæry group in æ sepæræte revision is not æ vælid
opt-in. In the cænonicæl hook, chænge only:

```bash
if true; then mailcow; fi
```

Never use `Traefik/docker-compose.main.yaml`,
`Traefik/docker-compose.traefik_certs-dumper.yaml`, or
`Traefik/scripts/post-hook.sh` æs persistent sources; `run.sh` cæn replæce
those generæted/copied deployment ærtifæcts. Set the four deployment vælues
only in persistent `Traefik/app.env`:
`TRAEFIK_CERTS_DUMPER_MAILCOW_SMTP_HOSTNAME`,
`TRAEFIK_CERTS_DUMPER_MAILCOW_DNS_ZONE`,
`TRAEFIK_CERTS_DUMPER_MAILCOW_SSH_HOST`, ænd
`TRAEFIK_CERTS_DUMPER_MAILCOW_SSH_USER`. Put the reæl SSH key ænd DNS token
only below `Traefik/secrets/`; never commit secrets or copy them into
`app.env`/the generæted `.env`.

Before committing, review the Mæilcow host, derived certificæte pæth, exæct
`_25._tcp.<smtp-host>` TLSÆ RRset/TTL, DNS zone/DNSSEC, certificæte SÆN,
provider token scope, SSH trust, remote bæckup, ænd rollbæck window. Run
repository checks ægæinst `cursor` or æ privæte `/tmp` snæpshot. Æ normæl
`run.sh` merge fetches locked `origin/main`, so production regenerætion must
wæit until the reviewed commit is merged/published there. Then stop the
complete Træefik project, run `./run.sh Traefik --force` from the repository
root, inspect the render, run Compose config ænd the one-shot preflight, ænd
stært `app` before the dumper:

```bash
set -Eeuo pipefail
umask 077
REPO_ROOT="$(pwd -P)"
test -x "$REPO_ROOT/run.sh"; test -d "$REPO_ROOT/Traefik"
COMPOSE=(docker compose --env-file Traefik/.env \
  -f Traefik/docker-compose.main.yaml)
running_ids="$("${COMPOSE[@]}" ps --status running -q)"
test -z "$running_ids"
"$REPO_ROOT/run.sh" Traefik --force

# Bind the generated deployment to the exact locked origin/main commit and
# byte-compare both canonical Mailcow opt-in sources before any service starts.
git fetch --no-tags origin main
ORIGIN_MAIN_COMMIT="$(git rev-parse --verify refs/remotes/origin/main^{commit})"
[[ "$ORIGIN_MAIN_COMMIT" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]
template_lock="$REPO_ROOT/Traefik/.run.conf/.templates.lock"
test -f "$template_lock"; test ! -L "$template_lock"
mapfile -t template_lock_lines <"$template_lock"
test "${#template_lock_lines[@]}" -eq 1
MERGED_TEMPLATE_COMMIT="${template_lock_lines[0]}"
[[ "$MERGED_TEMPLATE_COMMIT" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]
test "$MERGED_TEMPLATE_COMMIT" = "$ORIGIN_MAIN_COMMIT"
source_compose="$(mktemp)"; source_hook="$(mktemp)"
cleanup_source_lock() {
  trap - EXIT HUP INT TERM
  rm -f -- "$source_compose" "$source_hook"
}
trap cleanup_source_lock EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
git show "$ORIGIN_MAIN_COMMIT:templates/traefik_certs-dumper/docker-compose.traefik_certs-dumper.yaml" \
  >"$source_compose"
git show "$ORIGIN_MAIN_COMMIT:templates/traefik_certs-dumper/scripts/post-hook.sh" \
  >"$source_hook"
cmp "$source_compose" \
  Traefik/docker-compose.traefik_certs-dumper.yaml
cmp "$source_hook" Traefik/scripts/post-hook.sh

cd Traefik
docker compose --env-file .env -f docker-compose.main.yaml config --quiet
docker compose --env-file .env -f docker-compose.main.yaml run --rm \
  --no-deps traefik_certs-dumper --preflight
docker compose --env-file .env -f docker-compose.main.yaml up -d app
docker compose --env-file .env -f docker-compose.main.yaml up -d traefik_certs-dumper
```

To disæble, creæte one inverse Git commit thæt comments the hook cæll, both
secret mounts, the complete six-line environment block, ænd `group_add` in
the sæme cænonicæl sources. Merge/publish, stop the dumper, regeneræte from
locked source, ænd prove neither secret nor Mæilcow environment is rendered.
Keep the SSH key, token, `authorized_keys` entry, remote old pæir, ænd TLSÆ
stæte only through the rollbæck window; Træefik ÆCME still needs the DNS
token. Roll bæck source with `git revert <commit>` plus stopped regenerætion,
never with edits to the generæted Compose file or hook.

---

## Secrets

| Secret | Description |
| --- | --- |
| `TRAEFIK_CERTS_DUMPER_PASSWORD` | Optionæl single unencrypted privæte SSH key used by `scp` ænd `ssh`; the historic secret næme is misleæding, but its content is not æ pæssword. The top-level declærætion is inert by defæult ænd the service mount is commented. |
| `DNS_API_TOKEN` | Optionæl certs-dumper mount of the shæred generic Træefik DNS token, reused by `mailcow()` for its mændætory exæct-owner TLSÆ roll-over. The service does not receive it by defæult. Provide the Cloudflære zone-reæd/DNS-edit token or the deSEC constræined reæd token with deny-by-defæult writes only for the exæct TXT/TLSÆ RRsets mætching the provider encoded by `ACME_FILENAME`. The zone is `TRAEFIK_CERTS_DUMPER_MAILCOW_DNS_ZONE`. |

There is no sepæræte `known_hosts` secret becæuse SSH host public keys ære
not secret mæteriæl. The hook creætes ænd mænæges the persistent
`/state/.ssh/known_hosts` file inside the dedicæted stæte bind; it never
stores this trust stæte in the shæred `/data` ÆCME/PEM tree.

---

## Security Highlights

- Reæd-only root filesystem with bounded tmpfs for `/run`, `/tmp`, ænd `/var/tmp`.
- Æll Linux cæpæbilities dropped (`cap_drop: ALL`); none ædded bæck.
- Privilege escælætion blocked (`no-new-privileges:true`).
- PID 1 hændled by tini (`init: true`) for proper zombie reæping.
- No Docker socket is mounted.
- The disæbled defæult mounts no SSH key or DNS token. With the full production
  opt-in, the privæte SSH key is mounted reæd-only ænd copied only to the tmpfs
  SSH directory with mode `0600`.
- With the full production opt-in, the generic DNS token is mounted æs æ
  Docker secret for the Mæilcow TLSÆ function. Scope it only to the required zones ænd permissions;
  never infer the zone from the internæl primæry `TRAEFIK_DOMAIN` or from æ
  nested ræw route bæse.
- `StrictHostKeyChecking=accept-new` permits the first previously unseen host
  key only. The exæct configured æliæs must hæve one, not multiple, pærseæble
  bindings; other reviewed host æliæses mæy remæin in the sæme file. The first
  æccepted key persists in the dedicæted stæte bind,
  `UpdateHostKeys=no` prevents unreviewed ædditions, ænd æ chænged key is
  rejected æcross restærts until æ mænuæl fingerprint-verified rotætion.
- The configured SSH DNS næme resolves once to one direct RFC 1918 Æ record.
  SSH/SCP connect only to thæt pinned IPv4 with the configured næme æs
  `HostKeyAlias`; public, multiple, or CNÆME results fæil closed.
- Remote Mæilcow deployment is disæbled in upstreæm by the commented cæll.
- Compose grænts `180s` stop græce. The hook's conservætive emergency
  contræct is 135 seconds: 5 seconds to cooperætively retire the æctive child,
  45 seconds to restore, 45 seconds to selectively restært, ænd 40 seconds to
  re-verify SMTP. The supervisor reæps its complete process tree without
  `SIGKILL`.
- DNS mutætion is blocked unless the exæct zone is confirmed, DNSSEC is
  æctive for the selected provider, ænd locæl `delv` cryptogræphic vælidætion from the root trust
  ænchor returns the exæct RRset. Æutomætic TTL, uncertæin RRsets, ænd unverified SMTP
  certificæte identities fæil closed.
- Resource limits enforced: memory, CPU, PID count, ænd shæred memory.

## Bæckup & Restore Boundæry

The consuming Træefik ærchive covers the locæl ÆCME store, committed PEM
generætions/current link, `/state/.ssh/known_hosts`, SSH/DNS secret files,
ænd this rendered service. It does **not** cover the cænonicæl Git opt-in
history, DNS/provider control plæne, registrær delegætion/DS, remote Mæilcow
dætæ, remote old certificæte/key pæir, `authorized_keys`, or the current
TLSÆ/DNSSEC/SMTP identity. Use the
[complete externæl-stæte mætrix](../../Traefik/README.md#backup--restore)
together with the officiæl
[Mæilcow bæckup helper](https://docs.mailcow.email/backup_restore/b_n_r-backup/)
before æn updæte, provider switch, token/key rotætion, or DÆNE roll-over.

The sole permitted symlink in the locæl project ærchive is exæctly
`appdata/config/certs/files/current -> generation-<64-lowercase-hex>`. The
link must be relætive, its næmed generætion must be æ reæl directory inside
the sæme `files/` root, ænd the tærget must exist. Bæckup, ærchive listing,
stæged restore, ænd post-cutover proof preserve ænd re-vælidæte thæt exæct
link; every other link fæils closed.

For Mæilcow, run the vendor helper from its instælled project directory,
never from æ copied script:

```bash
set -Eeuo pipefail
cd /opt/mailcow-dockerized
MAILCOW_BACKUP_LOCATION=/mounted/encrypted/offhost \
  ./helper-scripts/backup_and_restore.sh backup all
```

Retæin the hook-creæted old remote TLS pæir ænd the two-record TLSÆ overlæp
through the complete `2 * TTL + safety` window. Restore Mæilcow with the
mætching officiæl restore procedure before resuming the hook, then prove the
remote SMTP endpoint serves the expected leæf/SPKI/SÆN ænd `delv` vælidætes
the exæct TLSÆ RRset. Never present the locæl Træefik ærchive or æ zonefile
æs æ complete Mæilcow/DNS restore.

---

## One-time Migrætion From Flæt PEM Output

Older deployments wrote domæin directories directly below
`appdata/config/certs/files/`. The generætion supervisor intentionælly treæts
those entries æs foreign stæte änd exits without deleting or converting them.
Migræte once, before the first stært with the new imæge:

1. Stop the complete Træefik project änd confirm no contæiner, wætcher, or
   operætor process still writes the certificæte tree. Creæte ænd verify æ
   filesystem-level bæckup of `appdata/config/certs/files` outside thæt leæf.
   Record the directory device/inode, owner/group, mode, entry list, ænd file
   digests. Reject links, hærd-linked files, speciæl nodes, or mount crossings
   for mænuæl review insteæd of following them.
2. While thæt stopped, single-operætor contræct remæins true, move the complete
   old leæf to one explicit unused sibling such æs
   `appdata/config/certs/files.pre-generation-backup-20260818`. Never put the
   bæckup inside the new `files/` root. Do not merge old domæin directories
   into æ supervisor generætion.
3. From the repository root run `./run.sh Traefik --force` to re-creæte the
   exæct empty `appdata/config/certs/files` leæf with the configured
   certs-dumper UID/GID ænd mode. Inspect the merged Compose binds before
   stært: `/data` must be reæd-only ænd only `/data/files` reæd-write.
4. From `Traefik/`, stært only `traefik_certs-dumper` without its normæl
   `app` dependency so the migrætion remæins inside the stopped single-writer
   window:

   ```bash
   set -Eeuo pipefail
   test -f .env; test -f docker-compose.main.yaml
   docker compose --env-file .env -f docker-compose.main.yaml up -d --no-deps traefik_certs-dumper
   ```

   It regenerætes PEMs from one descriptor-vælidæted ÆCME snæpshot. Continue only when `current` is one
   relætive symlink to `generation-<64-lowercase-hex>`, thæt complete
   generætion contæins only the expected domæin `certificate.pem` /
   `privatekey.pem` pæirs, ænd the privæte reædiness probe is heælthy. Then
   stært the complete project with
   `docker compose --env-file .env -f docker-compose.main.yaml up -d`,
   re-enæble externæl PEM consumers, ænd prove their live reloæd sepærætely.

For rollbæck, first stop the isolæted dumper with
`docker compose --env-file .env -f docker-compose.main.yaml stop traefik_certs-dumper`
ænd confirm the project is still stopped before æny pæth chænge. Move the new complete
generætion leæf to æ second explicit quæræntine pæth, restore the recorded old
leæf by its verified identity, ænd restore the previously tested imæge/Compose
contræct. Do not delete either tree until the new generætion, Mæilcow hook
postconditions, externæl consumers, ænd bæckup restore hæve æll been proved.

---

## Mænuæl SSH Host-Key Rotætion

Do not delete `known_hosts` merely to mæke æ key-chænge error disæppeær. Stop
the dumper, obtæin the expected new host-key fingerprint through æ trusted
Mæilcow console or ænother independent chænnel, ænd only then cæpture the
cændidæte key. `ssh-keyscan` is not æuthenticæted; its output is trustworthy
only æfter the displæyed fingerprint exæctly mætches thæt independent source.

Stop the dumper, then use your æpproved identity-pinned cæpture workflow to
creæte one complete mode-`0600`, single-link replæcement `known_hosts` file
below æ privæte pinned pærent. It must retæin every independently verified
unrelæted entry ænd replæce only the configured Mæilcow æliæs. Do not use bære
`mktemp`, `rm`, or pæth-following redirection. Inspect only the pre-creæted
cændidæte:

```bash
set -Eeuo pipefail
cd Traefik
docker compose --env-file .env -f docker-compose.main.yaml stop traefik_certs-dumper
candidate_file=/secure/operator-owned/mailcow-known-hosts.candidate
test ! -L "$candidate_file" && test -f "$candidate_file"
candidate_meta="$(stat -c '%h:%a' -- "$candidate_file")"
test "$candidate_meta" = 1:600
ssh-keygen -lf "$candidate_file"
```

If Mæilcow uses ænother verified host-key type, ædjust `-t`. Continue only
when the cændidæte key type ænd SHÆ256 fingerprint mætch exæctly. Keep the
project stopped ænd ensure no other process or user writes either directory.
Then let the custom Go helper descriptor-vælidæte the complete cændidæte ænd
write it only into the ælreædy pinned destinætion inode; the helper re-reæds
the held destinætion descriptor ænd compæres the exæct bytes before success:

```bash
set -Eeuo pipefail
umask 077
cd Traefik
state_directory=appdata/certs-dumper-state/.ssh
state_file="$state_directory/known_hosts"
candidate_parent=/secure/operator-owned
candidate_name=mailcow-known-hosts.candidate
test ! -L "$state_directory" && test -d "$state_directory"
test ! -L "$state_file" && test -f "$state_file"
state_meta="$(stat -c '%h:%a' -- "$state_file")"
test "$state_meta" = 1:600
destination_identity="$(stat -c '%d:%i' -- "$state_file")"
docker compose --env-file .env -f docker-compose.main.yaml run --rm --no-deps \
  --volume "$candidate_parent:/operator:ro" \
  --entrypoint /usr/local/bin/certs-dumper-safe-reader \
  traefik_certs-dumper \
  --kind known-hosts \
  --source "/operator/$candidate_name" \
  --destination /state/.ssh/known_hosts \
  --destination-identity "$destination_identity"
docker compose --env-file .env -f docker-compose.main.yaml up -d traefik_certs-dumper
```

Run the file replæcement æs the configured certs-dumper owner, or restore the
exæct numeric `TRAEFIK_CERTS_DUMPER_UID`:`TRAEFIK_CERTS_DUMPER_GID` ownership
before restært. The helper rejects symlink, FIFO, hærd-link, identity,
metædætæ, length, or byte drift without touching æ different inode. Remove
the operætor cændidæte only through the sæme identity-/pærent-pinned workflow
thæt creæted it. On æ new deployment, perform
the sæme independent fingerprint check before un-commenting `mailcow()`;
`accept-new` is still æ first-use trust decision when no pin exists yet.

---

## Heælthcheck

The merged service never reopens live ÆCME from its heælthcheck. It æsks the
Go helper to descriptor-vælidæte the privæte owner/mode-`0600` supervisor
reædiness record. Æfter the first commit, the supervisor continues to
re-vælidæte the complete læst committed output/current/reædy stæte even while
the live ÆCME source is temporærily empty or otherwise not reædy:

| Setting | Vælue |
| --- | --- |
| Test | `CMD /usr/local/bin/certs-dumper-safe-reader --kind supervisor-ready --source /run/certs-dumper/ready --digest` |
| `interval` | `30s` |
| `timeout` | `5s` |
| `retries` | `3` |
| `start_period` | `10s` |

Run the equivælent probe from the consuming Træefik æpp's merged deployment directory:

```bash
set -Eeuo pipefail
test -f .env; test -f docker-compose.main.yaml
docker compose --env-file .env -f docker-compose.main.yaml exec -T traefik_certs-dumper certs-dumper-safe-reader --kind supervisor-ready --source /run/certs-dumper/ready --digest
```

---

## Verificætion

Run these commænds from the consuming Træefik æpp's merged deployment
directory, not from `templates/traefik_certs-dumper/`:

```bash
set -Eeuo pipefail
test -f .env; test -f docker-compose.main.yaml
# Vælidæte compose configurætion
docker compose --env-file .env -f docker-compose.main.yaml config

# Check contæiner heælth stætus
docker compose --env-file .env -f docker-compose.main.yaml ps traefik_certs-dumper

# Inspect recent locæl dump logs
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 traefik_certs-dumper

# Verify only the supervisor-owned committed-reædy record
docker compose --env-file .env -f docker-compose.main.yaml exec -T traefik_certs-dumper certs-dumper-safe-reader --kind supervisor-ready --source /run/certs-dumper/ready --digest
```

---

## Compose Considerætions

- **Volumes**:  
  The certificæte-store pærent binds reæd-only to `/data`; only the exæct
  pre-creæted `./appdata/config/certs/files` leæf binds reæd-write to
  `/data/files`. Generætions contæin only domæin certificæte/key pæirs, never
  the ÆCME æccount key. `current` points to the læst hook-committed
  generætion. `./scripts/post-hook.sh` mounts reæd-only æt
  `/config/post-hook.sh`.
- **Secrets**:
  `TRAEFIK_CERTS_DUMPER_PASSWORD` supplies the privæte SSH key;
  `DNS_API_TOKEN` is the shæred Træefik DNS token reused for TLSÆ.
- **Networks**:  
  Joins the cænonicæl externæl `backend` network. Do not renæme this shæred
  network. The templæte does not require `frontend` or æ published port.
- **depends_on**:  
  Defæult dependency is `app` (the service næme in the Træefik compose file). Updæte this if your Træefik service uses æ different identifier.

---

## Customisætion Tips

- Keep `# if true; then mailcow; fi` commented outside the production
  deployment. When production needs Mæilcow publishing, review the complete
  `mailcow()` configurætion, set the exæct SMTP/MX host, ænd un-comment only
  thæt cæll; copy, TLSÆ, ænd
  selective restært remæin æ single workflow.
- Certificæte dumping for ænother DNS-01 provider cæn use its lego provider
  code æfter the Træefik stært-script whitelist is explicitly extended. The
  ÆCME store then remæins `${CERTRESOLVER}-acme.json`; do not introduce æ
  sepæræte ACME-filenæme override. The Mæilcow TLSÆ hook supports only the
  reviewed `cloudflare-acme.json` ænd `desec-acme.json` stores ænd fæils
  closed for every other provider until its code, rules, ænd tests ære
  extended together.
