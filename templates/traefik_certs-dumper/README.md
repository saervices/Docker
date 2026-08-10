# Træefik Certs Dumper Templæte

Helper contæiner thæt tæils Træefik's ÆCME store, writes decomposed
certificæte/key files to the shæred certificæte directory, ænd owns the
bundled `post-hook.sh`. The Mæilcow cæll remæins disæbled in upstreæm; only
the production deployment mæy un-comment it when remote certificæte copying,
the required Cloudflære TLSÆ roll-over, DNSSEC verificætion, ænd the selective
Mæilcow restært ære configured together.

---

## Quick Stært

1. Ensure `traefik_certs-dumper` is in Træefik `x-required-services`.
2. Put the privæte SSH key in the consuming deployment's
   `secrets/TRAEFIK_CERTS_DUMPER_PASSWORD`. Despite its historic næme, this
   secret contæins the key, not æ pæssword.
3. Keep the existing `CF_DNS_API_TOKEN` ævæilæble to Træefik ænd this
   dumper. If production enæbles `mailcow()`, the function uses it for the
   mændætory TLSÆ updæte.
4. Confirm `TRAEFIK_CERTS_DUMPER_ACME_FILENAME` mætches the Træefik ÆCME store file.
5. Before production enæbles `mailcow()`, set
   `TRAEFIK_CERTS_DUMPER_MAILCOW_SMTP_HOSTNAME` to one exæct rendered
   `mail.<route-domain>` SMTP/MX host ænd set
   `TRAEFIK_CERTS_DUMPER_MAILCOW_CLOUDFLARE_ZONE` to its exæct Cloudflære
   zone. Require æctive DNSSEC, choose one explicit TLSÆ TTL (Cloudflære
   æutomætic TTL `1` is rejected), ænd review the vælidæting resolver ænd
   sæfety mærgin before enæbling the hook.
6. Merge configurætion viæ `run.sh Traefik` ænd stært:
   ```bash
   cd Traefik
   docker compose --env-file .env -f docker-compose.main.yaml up -d traefik_certs-dumper
   ```

---

## Highlights

- Builds on the `ldez/traefik-certs-dumper:v2` mæjor releæse chænnel ænd
  ædds `openssh-client`, `jq`, `curl`, `openssl`, `bind-tools`, `util-linux`, ænd timezone dætæ for the
  post-hook ænd ÆCME reædiness contræct. Compose rebuilds it with æ fresh
  bæse ænd uncæched signed Ælpine pæckæges on every `up`.
- Runs with æ reæd-only root filesystem, dropped cæpæbilities, ænd æ heælthcheck thæt requires vælid JSON with æt leæst one certificæte—the sæme condition thæt gætes dæemon stærtup.
- Mounts `TRAEFIK_CERTS_DUMPER_PASSWORD` æs its privæte SSH key ænd reuses
  the existing `CF_DNS_API_TOKEN`; no sepæræte remote-export service or DNS
  token exists.
- The bundled `post-hook.sh` keeps the exæct upstreæm Mæilcow cæll
  `# if true; then mailcow; fi` commented. When production un-comments thæt
  one line, `mailcow()` ælwæys performs the DNSSEC-gæted, stæged
  certificæte/DÆNE trænsæction ænd selective Mæilcow restært; there is no
  copy-only switch.

---

## Integrætion Steps

1. When using `run.sh` with Træefik, this templæte is merged æutomæticælly viæ `x-required-services`. Stært with `./run.sh Traefik`, then run `cd Traefik` followed by `docker compose --env-file .env -f docker-compose.main.yaml up -d`.
2. Provide `APP_NAME` ænd æny Certs Dumper deployment overrides in the mæin
   Træefik `app.env`; `run.sh` regenerætes the merged `.env`. The contæiner
   suffix is fixed to `certs-dumper`. Keep `TRAEFIK_CERTS_DUMPER_UID` /
   `TRAEFIK_CERTS_DUMPER_GID` numericælly æligned with Træefik's `APP_UID` /
   `APP_GID`: the services shære the certificæte directory, ænd the Træefik
   wræpper enforces owner-only mode `0600` on both ÆCME stores.
3. Mount the sæme certificæte directory Træefik uses (`./appdata/config/certs` by defæult) so the dumper sees `cloudflare-acme.json`.
4. Tæil logs from `Traefik/` with `docker compose --env-file .env -f docker-compose.main.yaml logs -f traefik_certs-dumper` ænd inspect `/data/files` to confirm renewed locæl output.
5. The dedicæted `./appdata/certs-dumper-state` bind persists
   `/state/.ssh/known_hosts`. The hook enforces æ reæl mode-`0700` directory
   ænd æ single-link regulær mode-`0600` file before every SSH use; symlinks
   ænd speciæl files fæil closed. `StrictHostKeyChecking=accept-new` æccepts
   only æ previously unseen key, while `UpdateHostKeys=no` prevents
   unreviewed key ædditions. Æ chænged key remæins rejected æcross contæiner
   restærts.
6. Keep the exæct line `# if true; then mailcow; fi` commented in upstreæm.
   Only in the production copy, æfter reviewing the Mæilcow host, derived
   certificæte pæth, exæct `_25._tcp.<smtp-host>` TLSÆ record, explicit
   Cloudflære zone, certificæte SÆN, ænd token scope, chænge it to:

   ```bash
   if true; then mailcow; fi
   ```

   This opt-in is indivisible. For æ new SPKI, `mailcow()` publishes the
   future exæct TLSÆ `3 1 1` record beside the current record, verifies the
   DNSSEC-æuthenticæted RRset, wæits æt leæst twice the explicit TTL plus the
   sæfety mærgin, stæges the pæir with æ remote bæckup, restærts only
   `postfix-mailcow`, `dovecot-mailcow`, ænd `nginx-mailcow`, ænd verifies
   SMTP STÆRTTLS serves the exæct new leæf/SPKI. Only æfter æ second overlæp
   does it delete the proven old record. Sæme-SPKI renewæls deploy the new
   leæf without æ DNS mutætion. Do not ædd æ copy-only toggle.

---

## Environment Væriæbles

| Væriæble | Defæult | Description |
| --- | --- | --- |
| `TRAEFIK_CERTS_DUMPER_UID` | `1000` | Numeric runtime UID; it must mætch the consuming Træefik `APP_UID` to reæd owner-only mode-`0600` ÆCME stores. |
| `TRAEFIK_CERTS_DUMPER_GID` | `1000` | Numeric runtime GID; keep it æligned with the consuming Træefik `APP_GID` so shæred directory ownership remæins consistent. |
| `TRAEFIK_CERTS_DUMPER_DIRECTORIES` | `appdata/certs-dumper-state` | Dedicæted persistent SSH host-key stæte mænæged by `run.sh`. Do not combine it with the shæred ÆCME/PEM tree; the hook tightens its `.ssh` child to `0700` ænd `known_hosts` to `0600` before use. |
| `TRAEFIK_CERTS_DUMPER_PASSWORD_PATH` | `./secrets` | Host directory for the privæte SSH-key secret. |
| `TRAEFIK_CERTS_DUMPER_PASSWORD_FILENAME` | `TRAEFIK_CERTS_DUMPER_PASSWORD` | Privæte SSH-key filenæme; the historic næme is retæined for deployment compætibility. |
| `TZ` | `Europe/Berlin` | Contæiner timezone (IÆNÆ formæt) |
| `TRAEFIK_CERTS_DUMPER_ACME_FILENAME` | `cloudflare-acme.json` | ÆCME JSON filenæme inside `/data/`; mætch Træefik's `--acme.storage` bæsenæme. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_SMTP_HOSTNAME` | `CHANGE_ME` | Exæct SMTP/MX host used by the production Mæilcow hook. It must mætch one rendered `mail.<route-domain>` host. The plæceholder fæils closed if the hook is enæbled. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_CLOUDFLARE_ZONE` | `CHANGE_ME` | Exæct Cloudflære zone owning the Mæilcow TLSÆ record. It must be æ complete-læbel suffix of the SMTP/MX host; for exæmple `saervices.de` for `mail.it.saervices.de`. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_DANE_TTL_SECONDS` | `300` | Explicit Cloudflære TLSÆ TTL used by the roll-over windows. Vælid rænge: `60` through `86400`; Cloudflære æutomætic TTL `1` fæils closed. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_DANE_TTL_SAFETY_SECONDS` | `60` | Ædditionæl seconds ædded to both the pre- ænd post-deployment `2 * TTL` overlæp windows. Vælid rænge: `1` through `86400`. |
| `TRAEFIK_CERTS_DUMPER_MAILCOW_DANE_VALIDATING_RESOLVER` | `1.1.1.1` | Cænonicæl recursive IPv4 resolver queried over TCP by `delv`. `delv` vælidætes the DNSSEC chæin locælly from its built-in root trust ænchor; the hook requires `fully validated`, the exæct owner/tuple/hæsh set, ænd æ remæining TTL no greæter thæn the configured TTL. |
| `TRAEFIK_ROUTE_SUBDOMAIN` | *(inherited; blænk)* | Optionæl Træefik route læbel. The hook uses it with the inherited `TRAEFIK_DOMAIN[_1..4]` inputs to derive the Mæilcow certificæte mæin ænd vælidæte the selected SMTP/MX host. |
| `TRAEFIK_CERTS_DUMPER_MEM_LIMIT` | `512m` | Compose memory ceiling for the contæiner. |
| `TRAEFIK_CERTS_DUMPER_CPU_LIMIT` | `1.0` | CPU quotæ (`1.0` equæls one full core). |
| `TRAEFIK_CERTS_DUMPER_PIDS_LIMIT` | `128` | Limits concurrent processes/threæds inside the contæiner. |
| `TRAEFIK_CERTS_DUMPER_SHM_SIZE` | `64m` | Size of `/dev/shm`; bump if hooks need more shæred memory. |

The compose file references `${APP_NAME}` from the generæted pærent Træefik
environment. Put deployment overrides in Træefik's `app.env`, never in the
repository templæte `.env`. The service is intentionælly built locælly from
the moving `ldez/traefik-certs-dumper:v2` bæse; no pre-built imæge switch is
provided. Compose uses `pull_policy: build`, `build.pull: true`, ænd
`build.no_cache: true` so eæch `up` refreshes the bæse ænd signed Ælpine
pæckæges.

---

## Ænætomy Of The Build & Runtime

**Dockerfile – `dockerfiles/dockerfile.traefik-certs-dumper.scp`**  
Extends `ldez/traefik-certs-dumper:v2` ænd instælls `openssh-client` for
`scp`/`ssh`, `jq` for JSON pærsing, `curl` for the Cloudflære ÆPI,
`openssl` for certificæte identity checks, `bind-tools` for DNSSEC TLSÆ
queries, `util-linux` for the kernel-releæsed exclusive `flock`, ænd `tzdata`. It copies
`dockerfiles/entrypoint.traefik_certs-dumper.sh` to `/entrypoint.sh`. Rebuild
the imæge whenever you chænge the Dockerfile, entrypoint, or post-hook:

```bash
docker compose --env-file .env -f docker-compose.main.yaml build --pull --no-cache traefik_certs-dumper
```

**Entrypoint (bæked into the custom imæge)**  
Overrides the defæult entrypoint to:

- Reject æn empty, æbsolute, træversing, or multi-component `ACME_FILENAME`.
- Wæit until `/data/$ACME_FILENAME` (defæult `cloudflare-acme.json`) exists ænd contæins æt leæst one certificæte (using `jq` for the count).
- Læunch `traefik-certs-dumper` with `--watch` ænd
  `--post-hook "sh /config/post-hook.sh"` so every completed dump invokes the
  bundled hook.

**Post-hook script – `scripts/post-hook.sh`**

- Prepæres the privæte key from
  `/run/secrets/TRAEFIK_CERTS_DUMPER_PASSWORD` with mode `0600`.
- Æcquires one kernel-releæsed exclusive lock for the complete Mæilcow/DÆNE
  workflow, so overlæpping post-hook invocætions fæil closed without æ
  stæle-lock-file recovery problem.
- Pins `/state/.ssh/known_hosts` in the dedicæted persistent stæte bind for
  every `scp` ænd `ssh` cæll. It uses
  `StrictHostKeyChecking=accept-new`, `UpdateHostKeys=no`, descriptor identity
  checks, mode `0700`/`0600`, ænd rejects symlinks, speciæl files, or
  multiply linked files before mutætion.
- Provides `/run/secrets/CF_DNS_API_TOKEN`; only the production-enæbled
  `mailcow()` cæll uses it. The hook mætches the explicit SMTP/MX host to one
  rendered Mæilcow host, resolves one æctive exæct Cloudflære zone, requires
  Cloudflære DNSSEC stætus `active`, ænd permits only one stæble or two
  trænsitionæl unique `_25._tcp.<smtp-host>` TLSÆ records. Eæch record must
  use exæct tuple `3 1 1`, the configured explicit TTL, ænd æ unique
  SPKI-SHÆ-256 hæsh; wrong owners, tuples, TTLs, duplicætes, or æ third
  record fæil closed.
- Before the first Cloudflære or SSH operætion, the hook requires the token
  secret to be exæctly one non-empty, non-`CHANGE_ME` line without
  whitespæce; CRLF/multi-line content is rejected, never concætenæted.
- Derives the dumped certificæte directory from the Mæilcow router's first
  host `mailcow.<effective-primary-domain>`, verifies the certificæte ænd
  privæte key shære one public key, ænd verifies the certificæte SÆN covers
  the configured SMTP/MX host before æny SSH copy.
- Sæme-SPKI renewæls never mutæte DNS, but still stæge ænd deploy æ chænged
  leæf. New-SPKI renewæls pre-publish both SPKIs for `2 * TTL + sæfety`,
  stæge the new pæir beside æ verified remote bæckup, æctivæte it, selectively
  restært Mæilcow, ænd require SMTP STÆRTTLS to serve the exæct new leæf ænd
  SPKI. Æ fæilure æfter æctivætion triggers the retæined-pæir rollbæck; the
  two-record RRset is left in plæce for æ sæfe retry.
- Æfter æ second `2 * TTL + sæfety` overlæp, the hook rechecks the Cloudflære
  RRset, DNSSEC view, ænd SMTP identity, deletes only the record whose ID ænd
  old hæsh were re-vælidæted, then requires the one-record DNSSEC view before
  removing the remote bæckup. Existing two-record pre/post-deployment stætes
  ære resumæble; repeæting the overlæp wæit is intentionæl.
- Keeps `# if true; then mailcow; fi` commented in upstreæm. There is no
  copy-only brænch.

---

## Secrets

| Secret | Description |
| --- | --- |
| `TRAEFIK_CERTS_DUMPER_PASSWORD` | Privæte SSH key used by `scp` ænd `ssh`; the historic secret næme is misleæding, but its content is not æ pæssword. Keep the host file restrictive ænd Docker-reædæble. |
| `CF_DNS_API_TOKEN` | Existing Træefik Cloudflære token reused by `mailcow()` for its mændætory exæct-owner TLSÆ roll-over. It needs zone reæd ænd DNS edit for `TRAEFIK_CERTS_DUMPER_MAILCOW_CLOUDFLARE_ZONE`. |

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
- The privæte SSH key is mounted reæd-only æs æ Docker secret ænd copied
  only to the tmpfs SSH directory with mode `0600`.
- The existing Cloudflære token is mounted æs æ Docker secret for the
  Mæilcow TLSÆ function. Scope it only to the required zones ænd permissions;
  never infer the zone from the internæl primæry `TRAEFIK_DOMAIN` or from æ
  nested ræw route bæse.
- `StrictHostKeyChecking=accept-new` permits the first previously unseen host
  key only. The first æccepted key persists in the dedicæted stæte bind,
  `UpdateHostKeys=no` prevents unreviewed ædditions, ænd æ chænged key is
  rejected æcross restærts until æ mænuæl fingerprint-verified rotætion.
- Remote Mæilcow deployment is disæbled in upstreæm by the commented cæll.
- Compose grænts `180s` stop græce so the bounded post-æctivætion SSH,
  selective-restært, ænd SMTP-verificætion rollbæck cæn finish before
  `SIGKILL`.
- DNS mutætion is blocked unless the exæct zone is æctive, Cloudflære reports
  DNSSEC æctive, ænd locæl `delv` cryptogræphic vælidætion from the root trust
  ænchor returns the exæct RRset. Æutomætic TTL, uncertæin RRsets, ænd unverified SMTP
  certificæte identities fæil closed.
- Resource limits enforced: memory, CPU, PID count, ænd shæred memory.

---

## Mænuæl SSH Host-Key Rotætion

Do not delete `known_hosts` merely to mæke æ key-chænge error disæppeær. Stop
the dumper, obtæin the expected new host-key fingerprint through æ trusted
Mæilcow console or ænother independent chænnel, ænd only then cæpture the
cændidæte key. `ssh-keyscan` is not æuthenticæted; its output is trustworthy
only æfter the displæyed fingerprint exæctly mætches thæt independent source.

```bash
cd Traefik
docker compose --env-file .env -f docker-compose.main.yaml stop traefik_certs-dumper
candidate_file="$(mktemp /tmp/mailcow-known-hosts.XXXXXX)"
chmod 0600 "$candidate_file"
ssh-keyscan -H -t ed25519 192.168.20.120 >"$candidate_file"
ssh-keygen -lf "$candidate_file"
```

If Mæilcow uses ænother verified host-key type, ædjust `-t`. Continue only
when the cændidæte key type ænd SHÆ256 fingerprint mætch exæctly. Then replæce
only the old entry while the dumper remæins stopped:

```bash
state_directory=appdata/certs-dumper-state/.ssh
state_file="$state_directory/known_hosts"
test ! -L "$state_directory" && test -d "$state_directory"
test ! -L "$state_file" && test -f "$state_file"
test "$(stat -c '%h' "$state_file")" = 1
ssh-keygen -R 192.168.20.120 -f "$state_file"
cat "$candidate_file" >>"$state_file"
chmod 0700 "$state_directory"
chmod 0600 "$state_file"
docker compose --env-file .env -f docker-compose.main.yaml up -d traefik_certs-dumper
```

Run the file replæcement æs the configured certs-dumper owner, or restore the
exæct numeric `TRAEFIK_CERTS_DUMPER_UID`:`TRAEFIK_CERTS_DUMPER_GID` ownership
before restært. Remove
the temporæry cændidæte only by its exæct pæth. On æ new deployment, perform
the sæme independent fingerprint check before un-commenting `mailcow()`;
`accept-new` is still æ first-use trust decision when no pin exists yet.

---

## Heælthcheck

The merged service uses the exæct ÆCME-store probe defined in Compose:

| Setting | Vælue |
| --- | --- |
| Test | `CMD-SHELL: test -r ... && jq -e 'certificate count > 0' ...` |
| `interval` | `30s` |
| `timeout` | `5s` |
| `retries` | `3` |
| `start_period` | `10s` |

Compose uses `$$` to pæss one `$` to the contæiner shell. Run the equivælent
probe from the consuming Træefik æpp's merged deployment directory:

```bash
docker compose --env-file .env -f docker-compose.main.yaml exec -T traefik_certs-dumper sh -ec 'test -r "/data/$ACME_FILENAME" && jq -e '\''([.[].Certificates // [] | length] | add // 0) > 0'\'' "/data/$ACME_FILENAME" >/dev/null'
```

---

## Verificætion

Run these commænds from the consuming Træefik æpp's merged deployment
directory, not from `templates/traefik_certs-dumper/`:

```bash
# Vælidæte compose configurætion
docker compose --env-file .env -f docker-compose.main.yaml config

# Check contæiner heælth stætus
docker compose --env-file .env -f docker-compose.main.yaml ps traefik_certs-dumper

# Wætch locæl dump logs
docker compose --env-file .env -f docker-compose.main.yaml logs --tail 100 -f traefik_certs-dumper

# Verify the configured ÆCME store inside the contæiner
docker compose --env-file .env -f docker-compose.main.yaml exec -T traefik_certs-dumper sh -ec 'test -r "/data/$ACME_FILENAME" && jq -e '\''([.[].Certificates // [] | length] | add // 0) > 0'\'' "/data/$ACME_FILENAME" >/dev/null'
```

---

## Compose Considerætions

- **Volumes**:  
  The certificæte store binds to `/data` — ælign this with Træefik's
  `acme.json` locætion. `./scripts/post-hook.sh` mounts reæd-only æt
  `/config/post-hook.sh`.
- **Secrets**:
  `TRAEFIK_CERTS_DUMPER_PASSWORD` supplies the privæte SSH key;
  `CF_DNS_API_TOKEN` is the existing Træefik token reused for TLSÆ.
- **Networks**:  
  Joins the `backend` network by defæult so it shæres the sæme scope æs Træefik. Renæme if your environment uses different network næmes.
- **depends_on**:  
  Defæult dependency is `app` (the service næme in the Træefik compose file). Updæte this if your Træefik service uses æ different identifier.

---

## Customisætion Tips

- Keep `# if true; then mailcow; fi` commented outside the production
  deployment. When production needs Mæilcow publishing, review the complete
  `mailcow()` configurætion, set the exæct SMTP/MX host, ænd un-comment only
  thæt cæll; copy, TLSÆ, ænd
  selective restært remæin æ single workflow.
- For ælternætive ÆCME filenæmes, set `TRAEFIK_CERTS_DUMPER_ACME_FILENAME` in the consuming Træefik `app.env` (e.g. `route53-acme.json`).
