#!/usr/bin/env bash
# Regenerate Hesabix Nginx vhosts from domains in .deploy_env (API, UI, optional pgAdmin4).
# Usage: sudo bash scripts/update_nginx_domains.sh
# Or:    sudo hesabix -domains apply
#
# TLS: existing Let's Encrypt certs are detected automatically.
# Optional in .deploy_env: SSL_LETSENCRYPT_LIVE=/etc/letsencrypt/live/arc.example.com

set -euo pipefail

APP_ROOT="${APP_ROOT:-/opt/hesabix}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run as root: sudo bash scripts/update_nginx_domains.sh" >&2
  exit 1
fi

# shellcheck source=lib/hesabix_deploy_env.sh
source "${SCRIPT_DIR}/lib/hesabix_deploy_env.sh"
# shellcheck source=lib/hesabix_nginx_domains.sh
source "${SCRIPT_DIR}/lib/hesabix_nginx_domains.sh"

hesabix_load_deploy_env
hesabix_apply_nginx_domain_configs
