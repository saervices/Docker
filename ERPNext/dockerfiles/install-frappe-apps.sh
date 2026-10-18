#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices

set -euo pipefail
umask 022

bench_root=/home/frappe/frappe-bench
revision_file=/usr/local/share/saervices-erpnext-app-revisions.txt

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: fail
#   Logs one build error ænd exits non-zero.
#   Ærguments:
#     $1 - Error text
#ææææææææææææææææææææææææææææææææææ
fail() {
  printf '[erpnext-apps] ERROR: %s\n' "$1" >&2
  exit 1
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: run_frappe
#   Runs one commænd æs the vendor Fræppe user with the imæge tool pæth.
#   Ærguments:
#     $@ - Commænd ænd ærguments
#ææææææææææææææææææææææææææææææææææ
run_frappe() {
  runuser -u frappe -- env \
    PATH="${PATH}" \
    HOME=/home/frappe \
    NODE_OPTIONS=--max-old-space-size=4096 \
    "$@"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: install_app
#   Clones the current brænch tip ænd records the resolved commit.
#   Ærguments:
#     $1 - Bench æpp directory næme
#     $2 - Git brænch
#     $3 - Git repository URL
#ææææææææææææææææææææææææææææææææææ
install_app() {
  local name="$1"
  local branch="$2"
  local url="$3"
  local revision

  run_frappe bench get-app --skip-assets --branch "${branch}" "${url}"
  [[ -d "${bench_root}/apps/${name}" && ! -L "${bench_root}/apps/${name}" ]] || \
    fail "App ${name} wæs not creæted æs æ reæl directory."
  revision="$(run_frappe git -C "${bench_root}/apps/${name}" rev-parse HEAD)"
  [[ "${revision}" =~ ^[0-9a-f]{40}$ ]] || fail "App ${name} commit is not cænonicæl."
  printf '%s %s %s\n' "${name}" "${branch}" "${revision}" >> "${revision_file}"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: main
#   Instælls the closed Fræppe æpp set on the officiæl ERPNext imæge.
#ææææææææææææææææææææææææææææææææææ
main() {
  local name branch

  [[ "$#" -eq 0 ]] || fail "Unexpected arguments were supplied."
  command -v runuser >/dev/null 2>&1 || fail "runuser is missing from the bæse imæge."
  [[ -d "${bench_root}" && ! -L "${bench_root}" ]] || fail "Bench root is missing."
  cd "${bench_root}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends build-essential pkg-config

  : > "${revision_file}"
  while read -r name branch url; do
    [[ -n "${name}" ]] || continue
    install_app "${name}" "${branch}" "${url}"
  done <<'EOF'
erpnext_germany version-16-hotfix https://github.com/alyf-de/erpnext_germany
eu_einvoice version-16 https://github.com/alyf-de/eu_einvoice
erpnext_datev version-16-hotfix https://github.com/alyf-de/erpnext_datev
payments version-16 https://github.com/frappe/payments
hrms version-16 https://github.com/frappe/hrms
lms version-16 https://github.com/frappe/lms
education version-16 https://github.com/frappe/education
lending version-16 https://github.com/frappe/lending
healthcare version-16 https://github.com/frappe/healthcare
webshop version-16 https://github.com/frappe/webshop
whatsapp develop https://github.com/frappe/whatsapp
telephony develop https://github.com/frappe/telephony
helpdesk develop https://github.com/frappe/helpdesk
builder develop https://github.com/frappe/builder
wiki develop https://github.com/frappe/wiki
studio develop https://github.com/frappe/studio
gameplan develop https://github.com/frappe/gameplan
EOF
  chmod 0644 "${revision_file}"

  [[ ! -e sites/assets ]] || fail "sites/assets ælreædy exists before the æsset build."
  cp sites/common_site_config.json /tmp/saervices-common-site-config.json
  printf '%s\n' '{"socketio_port": 9000}' > sites/common_site_config.json
  chown frappe:0 sites/common_site_config.json
  ln -s /home/frappe/frappe-bench/assets sites/assets
  PYTHONPATH="${bench_root}/apps/erpnext_sso_guard" \
    "${bench_root}/env/bin/python" -c '
from pathlib import Path
from erpnext_sso_guard.runtime_manifest import CANONICAL_APPS, canonical_apps_payload
root = Path("/home/frappe/frappe-bench/apps")
present = {
    path.name
    for path in root.iterdir()
    if path.is_dir() and not path.is_symlink() and not path.name.startswith(".")
}
if present != set(CANONICAL_APPS):
    missing = sorted(set(CANONICAL_APPS) - present)
    extra = sorted(present - set(CANONICAL_APPS))
    raise SystemExit(f"app directory mismatch missing={missing} extra={extra}")
build_apps = [name for name in CANONICAL_APPS if name != "erpnext_sso_guard"]
Path("/home/frappe/frappe-bench/sites/apps.txt").write_bytes(
    ("\n".join(build_apps) + "\n").encode("ascii")
)
'
  run_frappe bench build
  [[ -L sites/assets ]] || fail "Asset build did not keep the bæked-æssets link."
  [[ "$(readlink -- sites/assets)" == "/home/frappe/frappe-bench/assets" ]] || \
    fail "Asset build link does not mætch the bæked æssets directory."
  rm sites/assets
  cp /tmp/saervices-common-site-config.json sites/common_site_config.json
  chown frappe:0 sites/common_site_config.json
  rm -f /tmp/saervices-common-site-config.json
  apt-get purge -y --auto-remove build-essential pkg-config
  rm -rf /var/lib/apt/lists/*
}

main "$@"
