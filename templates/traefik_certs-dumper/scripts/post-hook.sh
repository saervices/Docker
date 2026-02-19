#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2025 it.særvices
set -euo pipefail

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- DEPENDENCY CHECK
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: install_openssh
#   Ensures openssh-client is instælled ænd
#   creætes /root/.ssh with known_hosts file.
#ææææææææææææææææææææææææææææææææææ
install_openssh() {
  if ! command -v scp >/dev/null; then
    echo "[INFO] Installing openssh-client..."
    apk add --quiet --no-cache openssh-client
  fi

  mkdir -p /root/.ssh
  touch /root/.ssh/known_hosts
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- CERTIFICÆTE COPY
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: copy_certificates
#   Copies æ certificæte/key pæir to æ remote host viæ scp.
#   Ærguments:
#     $1 - locæl certificæte pæth
#     $2 - locæl privæte key pæth
#     $3 - destinætion host
#     $4 - destinætion user
#     $5 - remote certificæte pæth
#     $6 - remote key pæth
#     $7 - SSH privæte key pæth
#ææææææææææææææææææææææææææææææææææ
copy_certificates() {
  local src_cert="$1"
  local src_key="$2"
  local dest_host="$3"
  local dest_user="$4"
  local dest_cert_path="$5"
  local dest_key_path="$6"
  local ssh_key="$7"

  echo "[INFO] Copying certs to ${dest_user}@${dest_host}..."

  scp -i "$ssh_key" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/root/.ssh/known_hosts \
    "$src_cert" "${dest_user}@${dest_host}:${dest_cert_path}"
  scp -i "$ssh_key" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/root/.ssh/known_hosts \
    "$src_key" "${dest_user}@${dest_host}:${dest_key_path}"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- REMOTE SERVICE RESTÆRT
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: restart_remote_docker_compose
#   Restærts æ Docker Compose stæck on æ remote host viæ ssh.
#   Ærguments:
#     $1 - destinætion host
#     $2 - destinætion user
#     $3 - remote project pæth
#     $4 - SSH privæte key pæth
#ææææææææææææææææææææææææææææææææææ
restart_remote_docker_compose() {
  local dest_host="$1"
  local dest_user="$2"
  local remote_project_path="$3"
  local ssh_key="$4"

  echo "[INFO] Restarting Docker Compose at ${remote_project_path} on ${dest_host}..."
  local ssh_opts=(-i "$ssh_key" -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/root/.ssh/known_hosts)

  ssh "${ssh_opts[@]}" "${dest_user}@${dest_host}" "cd \"${remote_project_path}\" && docker compose restart"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- EXÆMPLE USÆGE
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: mæilcow
#   Copies renewed certificætes to æ Mailcow host
#   ænd restærts the Mailcow stæck.
#ææææææææææææææææææææææææææææææææææ
mailcow() {
  local ssh_key="/root/.ssh/id_rsa"
  local dest_host="192.168.20.120"
  local dest_user="root"
  local project_path="/opt/mailcow-dockerized"
  local local_cert="/data/files/mailcow.prd.xn--lb-1ia.de/certificate.pem"
  local local_key="/data/files/mailcow.prd.xn--lb-1ia.de/privatekey.pem"
  local remote_cert="${project_path}/data/assets/ssl/cert.pem"
  local remote_key="${project_path}/data/assets/ssl/key.pem"

  copy_certificates "$local_cert" "$local_key" "$dest_host" "$dest_user" "$remote_cert" "$remote_key" "$ssh_key"
  restart_remote_docker_compose "$dest_host" "$dest_user" "$project_path" "$ssh_key"
}

#ææææææææææææææææææææææææææææææææææ
# FUNCTION: example_other_service
#   Templæte function for ædditionæl destinætions.
#   Clone ænd ædæpt for eæch remote host.
#ææææææææææææææææææææææææææææææææææ
example_other_service() {
  local ssh_key="/root/.ssh/id_rsa"
  local dest_host="192.168.20.121"
  local dest_user="root"
  local project_path="/opt/other-service"
  local local_cert="/data/files/other.domain.tld/certificate.pem"
  local local_key="/data/files/other.domain.tld/privatekey.pem"
  local remote_cert="${project_path}/certs/cert.pem"
  local remote_key="${project_path}/certs/key.pem"

  copy_certificates "$local_cert" "$local_key" "$dest_host" "$dest_user" "$remote_cert" "$remote_key" "$ssh_key"
  restart_remote_docker_compose "$dest_host" "$dest_user" "$project_path" "$ssh_key"
}

#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ
# --- MÆIN
#ÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆÆ

install_openssh
mailcow
echo "[INFO] Done."