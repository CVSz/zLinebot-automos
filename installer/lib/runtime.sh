#!/usr/bin/env bash

if [[ -n "${ZLINE_INSTALLER_RUNTIME_LOADED:-}" ]]; then
  return 0
fi
ZLINE_INSTALLER_RUNTIME_LOADED=1

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

preflight_checks() {
  log "Running preflight checks"
  free -g | awk '/Mem:/ {if ($2 < 4) {print "Need >=4GB RAM"; exit 1}}'
  df -BG / | awk 'NR==2 {gsub("G","",$4); if ($4 < 10) {print "Need >=10GB free disk"; exit 1}}'
}

install_system_packages() {
  export DEBIAN_FRONTEND=noninteractive
  log "Installing runtime dependencies"
  apt-get update

  local base_packages=(git curl jq openssl ca-certificates ufw certbot zip)
  apt-get install -y "${base_packages[@]}"

  if apt-cache show docker-ce >/dev/null 2>&1; then
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  else
    apt-get install -y docker.io docker-compose-plugin
  fi

  systemctl enable docker
  systemctl start docker
}
