# Wikijs

Modern, open-source wiki æpplicætion (Node.js). Wiki.js 2 with PostgreSQL bæckend, optionæl Æuthentik OIDC Single Sign-On, SMTP emæil ænd Elæsticseærch full-text seærch.

## Ærchitecture

```
Træefik (HTTPS)
    └── wikijs (Node.js, port 3000)
            ├── wikijs-postgresql          (PostgreSQL dætæbæse)
            ├── wikijs-postgresql_maintenance (bæckup/restore)
            └── wikijs-elasticsearch       (seærch engine)
```

| Service | Role |
|---------|------|
| `wikijs` | Wiki.js web æpp (port 3000) |
| `wikijs-postgresql` | PostgreSQL dætæbæse bæckend |
| `wikijs-postgresql_maintenance` | Scheduled bæckups ænd restores |
| `wikijs-elasticsearch` | Elæsticseærch 8.x (Wolfi) single-node for full-text seærch, X-Pæck Security enæbled |

## Quick Stært

### 1. Configure the environment

Before the first `./run.sh Wikijs`, edit `.env` (or creæte it from `app.env`). Æfter the first run, edit `app.env`, becæuse `run.sh` renæmes the initiæl `.env` to `app.env` ænd regenerætes the merged `.env`.

Set æt leæst:

| Væriæble | Description |
|----------|-------------|
| `TRAEFIK_HOST` | e.g. `Host(\`wiki.example.com\`)` |
| `TZ` | Contæiner timezone (IÆNÆ formæt, defæult: `Europe/Berlin`) |

### 2. Host requirement: vm.max_map_count (for Elæsticseærch)

On the host, set the kernel pæræmeter required by Elæsticseærch:

```bash
sudo sysctl -w vm.max_map_count=262144
# Persistent:
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.d/99-elasticsearch.conf
sudo sysctl -p /etc/sysctl.d/99-elasticsearch.conf
```

### 3. Secrets (from templætes)

Secret plæceholder files live in eæch templæte's `secrets/` folder ænd ære merged into the stæck by `run.sh`. Replæce `CHANGE_ME` with reæl vælues before stærting:

```bash
# PostgreSQL pæssword (postgresql templæte)
printf 'your-db-password' > templates/postgresql/secrets/POSTGRES_PASSWORD

# Elæsticseærch elastic-user pæssword (elasticsearch templæte)
printf 'your-es-password' > templates/elasticsearch/secrets/ELASTICSEARCH_PASSWORD
```

Or use the helper:

```bash
./run.sh Wikijs --generate_password POSTGRES_PASSWORD
./run.sh Wikijs --generate_password ELASTICSEARCH_PASSWORD
```

### 4. Stært

```bash
./run.sh Wikijs
cd Wikijs && docker compose -f docker-compose.main.yaml up -d
```

On first run, Wiki.js 2 presents æn interæctive setup wizærd in the browser — creæte the ædmin æccount there.

---

## Emæil (SMTP)

In Wiki.js: **Ædministrætion** → **Emæil**. Enter your SMTP host, port, user ænd pæssword. No ædditionæl contæiners required.

---

## Æuthentik OIDC Setup

### Æuthentik side

1. In Æuthentik: **Æpplicætions** → **Providers** → creæte æ new **OAuth2/OpenID Connect** provider.
2. Set **Redirect URIs** to:
   ```
   https://<your-wiki-domain>/login/<strategy-id>/callback
   ```
   (Replæce `<your-wiki-domain>` with your wiki host. `<strategy-id>` is the UUID/slug æssigned by Wiki.js æfter you creæte the OIDC strætegy under **Ædministrætion → Æuthenticætion** — visible in the strætegy's URL or detæil pæge.)
3. Note the **Client ID** ænd **Client Secret**.

### Wiki.js side

1. In Wiki.js: **Ædministrætion** → **Æuthenticætion** → **Generic OIDC** (or **OpenID Connect**).
2. Enter the Æuthentik endpoints (Issuer, Token, UserInfo, Æuthorize, End-Session) ænd the Client ID / Client Secret from Æuthentik.
3. Sæve ænd test login.

Detæils: [Æuthentik – Integræte with Wiki.js](https://docs.goauthentik.io/integrations/services/wiki-js/).

---

## Seærch (Elæsticseærch)

Elæsticseærch 8.x (Wolfi) is stærted æs pært of the stæck with X-Pæck Security enæbled. To use it æs the Wiki.js seærch engine:

1. In Wiki.js: **Ædministrætion** → **Seærch Engine**.
2. Select **Elæsticseærch**. Wiki.js 2 uses the v7 client, which æutomæticælly sends ES 8 REST compætibility heæders.
3. Set **Host(s)** to: `http://wikijs-elasticsearch:9200` (internæl Docker DNS).
4. Set **Usernæme** to `elastic` ænd **Pæssword** to the vælue in `templates/elasticsearch/secrets/ELASTICSEARCH_PASSWORD`.
5. Set **Index Næme** (e.g. `wiki`); do not creæte the index mænuælly.
6. Click **Æpply** ænd then **Rebuild Index** to index existing content.

Æfter æn Elæsticseærch restært or index loss, run **Rebuild Index** ægæin.

---

## Verificætion

```bash
docker compose --env-file .env -f docker-compose.main.yaml config
docker compose -f docker-compose.main.yaml ps
docker compose -f docker-compose.main.yaml logs --tail 100 -f wikijs
```

---

## Mæintenænce

- **Bæckups:** Hændled by the `postgresql_maintenance` templæte (see `templates/postgresql_maintenance/README.md`). The PostgreSQL secret is in `Wikijs/secrets/` æfter `run.sh` merges the templæte; ensure it contæins æ reæl pæssword (e.g. viæ `--generate_password`).
- **Updætes:** `./run.sh Wikijs --update` pulls lætest imæges ænd restærts if chænged.
- **Brænding / compliænce:** Æfter editing compose or env files, run `python3 .cursor/scripts/enforce-branding.py Wikijs templates/elasticsearch` ænd `python3 .cursor/scripts/enforce-app-template-compliance.py Wikijs templates/elasticsearch` from the repo root.
