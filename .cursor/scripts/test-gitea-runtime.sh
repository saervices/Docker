#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

# Reæl no-cæche Giteæ imæge ænd descriptor-reæder runtime gæte.

set -Eeuo pipefail

readonly REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
readonly BASE_IMAGE="${GITEA_RUNTIME_BASE_IMAGE:-docker.gitea.com/gitea:1-rootless}"
readonly GO_IMAGE="${GITEA_RUNTIME_GO_IMAGE:-docker.io/library/golang:alpine}"
readonly AUDIT_TAG="gitea-runtime-audit-$$:local"
TEST_ROOT="$(mktemp -d -t gitea-runtime.XXXXXXXX)"
IMAGE_CREATED=false
COMPOSE_STARTED=false
OIDC_LABEL_STARTED=false
readonly COMPOSE_PROJECT="gitea-binding-audit-$$"
readonly OIDC_LABEL_PROJECT="gitea-oidc-label-audit-$$"
readonly ORPHAN_NAME="gitea-binding-orphan-$$"
readonly OIDC_BOUNDARY_NAME="gitea-oidc-boundary-audit-$$"

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ "$status" -ne 0 && -d "$TEST_ROOT" ]]; then
    printf 'Giteæ runtime gæte fæiled; redæcted fixture outputs follow:\n' >&2
    for diagnostic in "$TEST_ROOT"/*.out; do
      [[ -f "$diagnostic" ]] || continue
      printf '%s\n' "--- ${diagnostic##*/}" >&2
      sed -n '1,120p' "$diagnostic" \
      | sed 's/runtime-provider-client-secret/[REDACTED]/g' >&2
    done
  fi
  docker rm -f "$OIDC_BOUNDARY_NAME" >/dev/null 2>&1 || true
  if [[ "$OIDC_LABEL_STARTED" == true ]]; then
    env -i PATH="$PATH" HOME="${HOME:?}" docker compose \
      --project-name "$OIDC_LABEL_PROJECT" \
      -f "$TEST_ROOT/oidc-label-compose.yaml" down --remove-orphans \
      >/dev/null 2>&1 || status=1
  fi
  if [[ "$COMPOSE_STARTED" == true ]]; then
    docker rm -f "$ORPHAN_NAME" >/dev/null 2>&1 || true
    env -i PATH="$PATH" HOME="${HOME:?}" docker compose \
      --project-name "$COMPOSE_PROJECT" \
      --env-file "$TEST_ROOT/compose.env" \
      -f "$TEST_ROOT/compose.yaml" down --volumes --remove-orphans \
      >/dev/null 2>&1 || status=1
  fi
  if [[ "$IMAGE_CREATED" == true ]]; then
    docker image rm "$AUDIT_TAG" >/dev/null 2>&1 || status=1
  fi
  case "$TEST_ROOT" in
    /tmp/gitea-runtime.*) rm -rf -- "$TEST_ROOT" ;;
    *) status=1 ;;
  esac
  exit "$status"
}
trap cleanup EXIT INT TERM

docker pull "$BASE_IMAGE" >/dev/null
docker pull "$GO_IMAGE" >/dev/null
docker build --pull --no-cache --target gitea-runtime \
  --build-arg "GITEA_BASE_IMAGE=$BASE_IMAGE" \
  --build-arg "GITEA_GO_IMAGE=$GO_IMAGE" \
  --tag "$AUDIT_TAG" "$REPO_ROOT/Gitea/dockerfiles"
IMAGE_CREATED=true

docker image inspect "$BASE_IMAGE" "$AUDIT_TAG" >"$TEST_ROOT/images.json"
python3 - "$TEST_ROOT/images.json" <<'PY'
import json
import sys

base, built = json.load(open(sys.argv[1], encoding="utf-8"))
base_config = base["Config"]
built_config = built["Config"]
expected_entrypoint = [
    "/usr/bin/dumb-init",
    "--",
    "/usr/local/bin/docker-entrypoint.sh",
]
if base_config.get("User") != "1000:1000":
    raise SystemExit(f"unreviewed vendor User drift: {base_config.get('User')!r}")
if base_config.get("Entrypoint") != expected_entrypoint:
    raise SystemExit(
        f"unreviewed vendor Entrypoint drift: {base_config.get('Entrypoint')!r}"
    )
if base_config.get("Cmd") not in (None, []):
    raise SystemExit(f"unreviewed vendor Cmd drift: {base_config.get('Cmd')!r}")
for key in ("User", "Entrypoint", "Cmd", "WorkingDir", "ExposedPorts", "Volumes"):
    if built_config.get(key) != base_config.get(key):
        raise SystemExit(f"final image changed vendor {key}")
PY

mkdir -m 0700 "$TEST_ROOT/secrets"
printf '%s' 'reader-positive-ä✓' >"$TEST_ROOT/secrets/VALID"
positive="$(docker run --rm --pull never --network none --read-only \
  --entrypoint /usr/local/bin/gitea-secret-reader \
  --mount "type=bind,src=$TEST_ROOT/secrets,dst=/run/secrets,readonly" \
  "$AUDIT_TAG" --directory /run/secrets VALID)"
[[ "$positive" == 'reader-positive-ä✓' ]]

docker run --rm --pull never --network none --read-only \
  --entrypoint /bin/sh "$AUDIT_TAG" -ec \
  'test "$(id -u):$(id -g)" = 1000:1000; test -x /usr/local/bin/gitea-secret-reader; /usr/local/bin/gitea --version' \
  >"$TEST_ROOT/version.out"
grep -Eq '^gitea version [0-9]+\.[0-9]+\.[0-9]+' "$TEST_ROOT/version.out"

mkdir -m 0700 "$TEST_ROOT/gitea-config" "$TEST_ROOT/gitea-data" \
  "$TEST_ROOT/oidc-secrets"
cat >"$TEST_ROOT/gitea-config/app.ini" <<'EOF'
APP_NAME = Audit
RUN_USER = git
[database]
DB_TYPE = sqlite3
PATH = /var/lib/gitea/data/gitea.db
[security]
INSTALL_LOCK = true
[server]
ROOT_URL = http://gitea.example.test/
HTTP_ADDR = 127.0.0.1
HTTP_PORT = 3000
EOF
printf '%s' 'runtime-provider-client-id' \
  >"$TEST_ROOT/oidc-secrets/GITEA_OIDC_CLIENT_ID"
printf '%s' 'runtime-provider-client-secret' \
  >"$TEST_ROOT/oidc-secrets/GITEA_OIDC_CLIENT_SECRET"

docker run --rm --pull never --network none \
  --mount "type=bind,src=$TEST_ROOT/gitea-config,dst=/etc/gitea" \
  --mount "type=bind,src=$TEST_ROOT/gitea-data,dst=/var/lib/gitea" \
  --entrypoint /usr/local/bin/gitea "$AUDIT_TAG" \
  --config /etc/gitea/app.ini migrate >"$TEST_ROOT/migrate.out" 2>&1

oidc_helper=(docker run --rm --pull never --network none --read-only \
  --name "$OIDC_BOUNDARY_NAME" \
  --tmpfs /tmp:rw,noexec,nosuid,nodev,uid=1000,gid=1000,mode=0700 \
  --mount "type=bind,src=$TEST_ROOT/gitea-config,dst=/etc/gitea,readonly" \
  --mount "type=bind,src=$TEST_ROOT/gitea-data,dst=/var/lib/gitea" \
  --mount "type=bind,src=$TEST_ROOT/oidc-secrets,dst=/run/secrets,readonly" \
  --mount "type=bind,src=$REPO_ROOT/Gitea/scripts/gitea-register-oidc.sh,dst=/gitea-register-oidc.sh,readonly" \
  --env AUTHENTIK_DOMAIN=authentik.example.test \
  --env APP_DOMAIN=gitea.example.test \
  --env GITEA_OIDC_NAME=authentik \
  --env GITEA_OIDC_SLUG=gitea \
  --env GITEA_OIDC_ADMIN_GROUP=gitea-admins \
  --env 'GITEA_OIDC_SCOPES=openid email profile groups' \
  --env GITEA_BIN=/usr/local/bin/gitea \
  --env GITEA_APP_INI=/etc/gitea/app.ini \
  --entrypoint /bin/sh "$AUDIT_TAG" /gitea-register-oidc.sh)
"${oidc_helper[@]}" --preflight-only >"$TEST_ROOT/oidc-preflight.out" 2>&1
grep -Fq 'Preflight succeeded for source authentik.' \
  "$TEST_ROOT/oidc-preflight.out"
set +e
timeout 30 "${oidc_helper[@]}" >"$TEST_ROOT/oidc-discovery-boundary.out" 2>&1
oidc_status=$?
set -e
[[ "$oidc_status" -ne 0 && "$oidc_status" -ne 124 ]]
grep -Fq 'Adding OIDC source authentik.' \
  "$TEST_ROOT/oidc-discovery-boundary.out"
grep -Fq 'Failed to initialize OpenID Connect Provider' \
  "$TEST_ROOT/oidc-discovery-boundary.out"
grep -Fq 'https://authentik.example.test/application/o/gitea/.well-known/openid-configuration' \
  "$TEST_ROOT/oidc-discovery-boundary.out"
! grep -FRq 'runtime-provider-client-secret' "$TEST_ROOT"/*.out

docker run --rm --pull never --network none \
  --mount "type=bind,src=$TEST_ROOT/gitea-config,dst=/etc/gitea,readonly" \
  --mount "type=bind,src=$TEST_ROOT/gitea-data,dst=/var/lib/gitea" \
  --entrypoint /usr/local/bin/gitea "$AUDIT_TAG" \
  --config /etc/gitea/app.ini admin auth list >"$TEST_ROOT/auth-list.out"
python3 - "$TEST_ROOT/auth-list.out" <<'PY'
import sys

rows = [line.split() for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
if rows[:1] != [["ID", "Name", "Type", "Enabled"]]:
    raise SystemExit(f"unreviewed Gitea auth-list header drift: {rows[:1]!r}")
matches = [row for row in rows[1:] if len(row) >= 2 and row[1] == "authentik"]
if matches:
    raise SystemExit(f"failed discovery persisted an OIDC source: {matches!r}")
PY

python3 - "$REPO_ROOT/templates/gitea-oidc/docker-compose.gitea-oidc.yaml" \
  "$TEST_ROOT/oidc-label-compose.yaml" "$AUDIT_TAG" <<'PY'
import sys

import yaml

source_path, fixture_path, image = sys.argv[1:]
text = open(source_path, encoding="utf-8").read()
label = "de.saervices.run.completion-timeout-seconds"
if text.count(f"      {label}:") != 1:
    raise SystemExit("completion label must occur exactly once as a mapping key")
document = yaml.safe_load(text)
service = document["services"]["gitea-oidc"]
labels = service.get("labels")
if not isinstance(labels, dict):
    raise SystemExit("gitea-oidc labels must use mapping form")
reserved = sorted(key for key in labels if key.startswith("de.saervices.run.completion-"))
if reserved != [label] or labels[label] != "600":
    raise SystemExit(f"unexpected completion labels: {labels!r}")
if service.get("restart") != "no":
    raise SystemExit("labelled gitea-oidc service must use restart no")
if service.get("scale", 1) != 1:
    raise SystemExit("labelled gitea-oidc service must use effective scale one")
deploy = service.get("deploy") or {}
if deploy.get("replicas", 1) != 1:
    raise SystemExit("labelled gitea-oidc service must use one deploy replica")
if "restart_policy" in deploy:
    raise SystemExit("labelled gitea-oidc service must not declare deploy restart_policy")
with open(fixture_path, "w", encoding="utf-8") as fixture:
    yaml.safe_dump(
        {
            "services": {
                "gitea-oidc": {
                    "image": image,
                    "pull_policy": "never",
                    "restart": service["restart"],
                    "labels": labels,
                    "network_mode": "none",
                    "entrypoint": ["/bin/sh", "-c"],
                    "command": ["exit 0"],
                }
            }
        },
        fixture,
        sort_keys=True,
    )
PY
env -i PATH="$PATH" HOME="${HOME:?}" docker compose \
  --project-name "${COMPOSE_PROJECT}-oidc-label" \
  -f "$TEST_ROOT/oidc-label-compose.yaml" config --format json \
  >"$TEST_ROOT/oidc-label-rendered.json"
python3 - "$TEST_ROOT/oidc-label-rendered.json" <<'PY'
import json
import sys

service = json.load(open(sys.argv[1], encoding="utf-8"))["services"]["gitea-oidc"]
expected = {"de.saervices.run.completion-timeout-seconds": "600"}
if service.get("labels") != expected:
    raise SystemExit(f"rendered completion label drift: {service.get('labels')!r}")
if service.get("restart") != "no" or service.get("pull_policy") != "never":
    raise SystemExit("rendered finite-job lifecycle contract drift")
if service.get("scale", 1) != 1:
    raise SystemExit("rendered finite-job scale drift")
deploy = service.get("deploy") or {}
if deploy.get("replicas", 1) != 1 or "restart_policy" in deploy:
    raise SystemExit("rendered finite-job deploy lifecycle drift")
PY

oidc_label_compose=(env -i PATH="$PATH" HOME="${HOME:?}" docker compose \
  --project-name "$OIDC_LABEL_PROJECT" \
  -f "$TEST_ROOT/oidc-label-compose.yaml")
OIDC_LABEL_STARTED=true
"${oidc_label_compose[@]}" up -d --no-build --pull never
oidc_label_container="$("${oidc_label_compose[@]}" ps -aq gitea-oidc)"
[[ -n "$oidc_label_container" ]]
[[ "$(docker wait "$oidc_label_container")" == 0 ]]
oidc_label_state_a="$(docker inspect --format \
  '{{.State.Status}} {{.State.Running}} {{.State.ExitCode}} {{.HostConfig.RestartPolicy.Name}}' \
  "$oidc_label_container")"
oidc_label_state_b="$(docker inspect --format \
  '{{.State.Status}} {{.State.Running}} {{.State.ExitCode}} {{.HostConfig.RestartPolicy.Name}}' \
  "$oidc_label_container")"
[[ "$oidc_label_state_a" == 'exited false 0 no' && \
   "$oidc_label_state_b" == "$oidc_label_state_a" ]]
"${oidc_label_compose[@]}" down --remove-orphans >/dev/null
OIDC_LABEL_STARTED=false

printf '%s\n' \
  'services:' \
  '  gitea-oidc:' \
  "    image: $AUDIT_TAG" \
  '    labels:' \
  '      de.saervices.run.completion-timeout-seconds: "600"' \
  '      de.saervices.run.completion-timeout-seconds: "601"' \
  >"$TEST_ROOT/oidc-duplicate-label.yaml"
set +e
env -i PATH="$PATH" HOME="${HOME:?}" docker compose \
  --project-name "${COMPOSE_PROJECT}-duplicate-label" \
  -f "$TEST_ROOT/oidc-duplicate-label.yaml" config --format json \
  >"$TEST_ROOT/oidc-duplicate-label.out" 2>&1
duplicate_label_status=$?
set -e
[[ "$duplicate_label_status" -ne 0 ]]

bash "$REPO_ROOT/.cursor/scripts/test-run-update.sh" "$REPO_ROOT/run.sh" \
  >"$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS post-start-running-then-success' "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS post-start-timeout-fails-closed' "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS post-start-cardinality-fails-closed' "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS post-start-identity-state-races-fail-closed' \
  "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS completed-job-replacement-during-peer-wait-fails' \
  "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS post-start-image-drift-fails-closed' "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS pre-up-retag-uses-frozen-override' "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS override-contract-drift-fails-before-shutdown' \
  "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS snapshot-project-contract' "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS snapshot-cleanup-on-signals' "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS compose-env-project-swaps-fail-closed' \
  "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS monotonic-clock-uncertainty-fails-closed' \
  "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS runtime-restart-policy-drift-fails-closed' \
  "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS final-completion-identity-hostconfig-fail-closed' \
  "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS unequal-completion-deadlines-no-starvation' \
  "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS final-reconciliation-query-bounded' \
  "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS external-start-during-build-fails-closed' \
  "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS invalid-post-start-timeouts-fail-closed' \
  "$TEST_ROOT/runner-gate.out"
grep -Fq 'PASS conflicting-post-start-contracts-fail-closed' \
  "$TEST_ROOT/runner-gate.out"
grep -Eq '^Result: ([3-9][0-9]|[1-9][0-9]{2,}) passed, 0 failed$' \
  "$TEST_ROOT/runner-gate.out"

ln -s VALID "$TEST_ROOT/secrets/LINK"
ln "$TEST_ROOT/secrets/VALID" "$TEST_ROOT/secrets/HARDLINK"
mkfifo "$TEST_ROOT/secrets/FIFO"
for hostile in LINK HARDLINK FIFO; do
  set +e
  timeout 10 docker run --rm --pull never --network none --read-only \
    --entrypoint /usr/local/bin/gitea-secret-reader \
    --mount "type=bind,src=$TEST_ROOT/secrets,dst=/run/secrets,readonly" \
    "$AUDIT_TAG" --directory /run/secrets "$hostile" \
    >"$TEST_ROOT/$hostile.out" 2>&1
  status=$?
  set -e
  [[ "$status" -ne 0 && "$status" -ne 124 ]]
  ! grep -Fq 'reader-positive-ä✓' "$TEST_ROOT/$hostile.out"
done

mkdir -m 0700 "$TEST_ROOT/binding-data"
printf '%s\n' \
  "services:" \
  "  fixture:" \
  "    image: $AUDIT_TAG" \
  "    pull_policy: never" \
  "    entrypoint: [/bin/sh, -c]" \
  "    command: [\"trap 'exit 0' TERM; while :; do sleep 1; done\"]" \
  "    environment:" \
  "      BINDING_VALUE: clean" \
  "    volumes:" \
  "      - type: volume" \
  "        source: database" \
  "        target: /binding-data" \
  "volumes:" \
  "  database:" \
  '    name: ${DATABASE_VOLUME:?DATABASE_VOLUME required}' \
  >"$TEST_ROOT/compose.yaml"
printf '%s\n' 'DATABASE_VOLUME=gitea-binding-clean' >"$TEST_ROOT/compose.env"
binding_compose=(env -i PATH="$PATH" HOME="${HOME:?}" docker compose \
  --project-name "$COMPOSE_PROJECT" --env-file "$TEST_ROOT/compose.env" \
  -f "$TEST_ROOT/compose.yaml")
COMPOSE_STARTED=true
"${binding_compose[@]}" up -d --no-build --pull never
binding_container="$("${binding_compose[@]}" ps -q fixture)"
test -n "$binding_container"
binding_image_ref="$(docker inspect --format '{{.Config.Image}}' \
  "$binding_container")"
binding_image_id="$(docker inspect --format '{{.Image}}' "$binding_container")"
binding_hash="$(docker inspect --format \
  '{{index .Config.Labels "com.docker.compose.config-hash"}}' \
  "$binding_container")"
printf '{"services":{"fixture":{"image":"%s"}}}\n' "$binding_image_id" \
  >"$TEST_ROOT/image-override.json"
expected_hash_line="$("${binding_compose[@]}" \
  -f "$TEST_ROOT/image-override.json" config --hash fixture)"
[[ "$expected_hash_line" != "fixture $binding_hash" ]]
docker image tag "$BASE_IMAGE" "$AUDIT_TAG"
"${binding_compose[@]}" -f "$TEST_ROOT/image-override.json" \
  up -d --force-recreate --no-build --pull never
binding_container="$("${binding_compose[@]}" ps -q fixture)"
[[ "$(docker inspect --format '{{.Image}}' "$binding_container")" == \
  "$binding_image_id" ]]
[[ "$(docker inspect --format '{{.Config.Image}}' "$binding_container")" == \
  "$binding_image_id" ]]
[[ "$(docker inspect --format \
  '{{index .Config.Labels "com.docker.compose.config-hash"}}' \
  "$binding_container")" == "${expected_hash_line#fixture }" ]]
docker image tag "$binding_image_id" "$AUDIT_TAG"
printf '%s\n' \
  'services:' \
  '  fixture:' \
  '    environment:' \
  '      BINDING_VALUE: drifted' \
  >"$TEST_ROOT/config-drift.yaml"
drift_hash_line="$("${binding_compose[@]}" \
  -f "$TEST_ROOT/image-override.json" -f "$TEST_ROOT/config-drift.yaml" \
  config --hash fixture)"
[[ "$drift_hash_line" != "fixture $binding_hash" ]]
test "$(docker image inspect --format '{{.Id}}' "$binding_image_ref")" = \
  "$binding_image_id"

docker run -d --pull never --network none --name "$ORPHAN_NAME" \
  --label "com.docker.compose.project=$COMPOSE_PROJECT" \
  --label 'com.docker.compose.service=removed-writer' \
  --entrypoint /bin/sh "$AUDIT_TAG" -c \
  "trap 'exit 0' TERM; while :; do sleep 1; done" >/dev/null
mapfile -t configured_services < <("${binding_compose[@]}" config --services)
mapfile -t project_containers < <(docker ps -aq \
  --filter "label=com.docker.compose.project=$COMPOSE_PROJECT")
[[ "${#configured_services[@]}" -eq 1 && "${#project_containers[@]}" -eq 2 ]]

ambient_volume="$(DATABASE_VOLUME=gitea-binding-forbidden docker compose \
  --project-name "$COMPOSE_PROJECT" --env-file "$TEST_ROOT/compose.env" \
  -f "$TEST_ROOT/compose.yaml" config --format json | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["volumes"]["database"]["name"])')"
clean_volume="$("${binding_compose[@]}" config --format json | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["volumes"]["database"]["name"])')"
[[ "$ambient_volume" == gitea-binding-forbidden ]]
[[ "$clean_volume" == gitea-binding-clean ]]

docker rm -f "$ORPHAN_NAME" >/dev/null
"${binding_compose[@]}" down --volumes --remove-orphans >/dev/null
COMPOSE_STARTED=false

docker image rm "$AUDIT_TAG" >/dev/null
IMAGE_CREATED=false
! docker image inspect "$AUDIT_TAG" >/dev/null 2>&1
printf 'PASS: Giteæ no-cæche build, runtime reæder/OIDC preflight, fail-closed externæl discovery boundæry, one-shot lifecycle, immutable-ID runner/Compose gætes, drift, orphæn, ænd cleæn-env contræcts\n'
