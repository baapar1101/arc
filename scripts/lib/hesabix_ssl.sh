#!/usr/bin/env bash
# Let's Encrypt / certbot management for Hesabix.

HESABIX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hesabix_deploy_env.sh
source "${HESABIX_LIB_DIR}/hesabix_deploy_env.sh"
# shellcheck source=hesabix_letsencrypt.sh
source "${HESABIX_LIB_DIR}/hesabix_letsencrypt.sh"
# shellcheck source=hesabix_nginx_domains.sh
source "${HESABIX_LIB_DIR}/hesabix_nginx_domains.sh"

hesabix_ensure_certbot() {
  if command -v certbot >/dev/null 2>&1; then
    return 0
  fi
  echo ">> Installing certbot and python3-certbot-nginx..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y certbot python3-certbot-nginx
}

hesabix_enable_certbot_timer() {
  systemctl enable certbot.timer 2>/dev/null || true
  systemctl start certbot.timer 2>/dev/null || true
}

hesabix_default_certbot_email() {
  local domain="$1"
  if [[ -n "${CERTBOT_EMAIL:-}" ]]; then
    printf '%s' "${CERTBOT_EMAIL}"
    return 0
  fi
  if [[ -n "${PGADMIN4_EMAIL:-}" ]] && [[ "${domain}" == "${PGADMIN4_DOMAIN:-}" ]]; then
    printf '%s' "${PGADMIN4_EMAIL}"
    return 0
  fi
  printf '%s' "admin@${domain}"
}

# Issue or renew cert for one domain via nginx plugin; then resync Hesabix nginx templates.
hesabix_ssl_enable_for_domain() {
  local domain="$1"
  local email="${2:-}"
  [[ -z "${domain}" ]] && { echo "Domain is required." >&2; return 1; }
  [[ -z "${email}" ]] && email="$(hesabix_default_certbot_email "${domain}")"

  if hesabix_domain_has_ssl "${domain}"; then
    echo ">> SSL already present for ${domain}; skipping certbot issue."
    return 0
  fi

  hesabix_ensure_certbot
  echo ">> Requesting Let's Encrypt certificate for ${domain} (email: ${email})..."
  if certbot --nginx -d "${domain}" --redirect --non-interactive --agree-tos -m "${email}"; then
    hesabix_enable_certbot_timer
    echo "✓ SSL enabled for ${domain}."
    return 0
  fi
  echo "Failed to issue SSL for ${domain}. Check DNS and port 80/443 accessibility." >&2
  return 1
}

hesabix_ssl_status() {
  hesabix_load_deploy_env || return 1

  local dom live scheme
  echo "SSL / Let's Encrypt status"
  echo "=========================="
  for dom in "${API_DOMAIN}" "${UI_DOMAIN}"; do
    [[ -z "${dom}" ]] && continue
    if live="$(hesabix_pick_letsencrypt_live_for_domain "${dom}" 2>/dev/null)"; then
      echo "  ${dom}: HTTPS (cert: ${live})"
    else
      echo "  ${dom}: HTTP only (no cert found)"
    fi
  done
  if [[ -n "${PGADMIN4_DOMAIN:-}" ]]; then
    if live="$(hesabix_pick_letsencrypt_live_for_domain "${PGADMIN4_DOMAIN}" 2>/dev/null)"; then
      echo "  ${PGADMIN4_DOMAIN} (pgAdmin4): HTTPS (cert: ${live})"
    else
      echo "  ${PGADMIN4_DOMAIN} (pgAdmin4): HTTP only"
    fi
  fi
  if [[ -n "${SSL_LETSENCRYPT_LIVE:-}" ]]; then
    echo "  SSL_LETSENCRYPT_LIVE override: ${SSL_LETSENCRYPT_LIVE}"
  fi
  if [[ -n "${API_PUBLIC_SCHEME:-}" ]]; then
    echo "  API_PUBLIC_SCHEME override: ${API_PUBLIC_SCHEME}"
  fi
  if systemctl is-enabled certbot.timer >/dev/null 2>&1; then
    echo "  certbot.timer: enabled (auto-renewal)"
  else
    echo "  certbot.timer: not enabled"
  fi
  echo
  local api_s ui_s
  # shellcheck source=/dev/null
  [[ -r "${APP_ROOT}/app/scripts/api_public_scheme.sh" ]] && source "${APP_ROOT}/app/scripts/api_public_scheme.sh"
  api_s="$(hesabix_resolve_api_public_scheme 2>/dev/null || echo http)"
  ui_s="$(hesabix_resolve_ui_public_scheme)"
  echo "Access URLs:"
  echo "  API:  ${api_s}://${API_DOMAIN}/api/v1/health"
  echo "  UI:   ${ui_s}://${UI_DOMAIN}/"
}

hesabix_ssl_enable_targets() {
  local targets=() email="" sync_nginx=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --api) targets+=(api) ;;
      --ui) targets+=(ui) ;;
      --pgadmin) targets+=(pgadmin) ;;
      --all) targets=(api ui pgadmin) ;;
      --email)
        [[ $# -ge 2 ]] || { echo "--email requires a value." >&2; return 1; }
        email="$2"
        shift
        ;;
      --no-sync-nginx) sync_nginx=0 ;;
      *)
        echo "Unknown option: $1" >&2
        return 1
        ;;
    esac
    shift
  done

  hesabix_load_deploy_env || return 1
  [[ -n "${email}" ]] && export CERTBOT_EMAIL="${email}"

  if [[ ${#targets[@]} -eq 0 ]]; then
    targets=(api ui)
    if [[ -n "${PGADMIN4_DOMAIN:-}" ]]; then
      targets+=(pgadmin)
    fi
  fi

  local t rc=0
  for t in "${targets[@]}"; do
    case "${t}" in
      api)
        hesabix_ssl_enable_for_domain "${API_DOMAIN}" "${email}" || rc=1
        ;;
      ui)
        hesabix_ssl_enable_for_domain "${UI_DOMAIN}" "${email}" || rc=1
        ;;
      pgadmin)
        if [[ -z "${PGADMIN4_DOMAIN:-}" ]]; then
          echo "pgAdmin4 is not configured (PGADMIN4_DOMAIN empty)." >&2
          rc=1
        else
          hesabix_ssl_enable_for_domain "${PGADMIN4_DOMAIN}" "${email}" || rc=1
        fi
        ;;
    esac
  done

  if [[ "${sync_nginx}" -eq 1 ]]; then
    hesabix_apply_nginx_domain_configs || rc=1
  fi
  return "${rc}"
}

hesabix_ssl_renew() {
  local dry_run=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=1 ;;
      *) echo "Unknown option: $1" >&2; return 1 ;;
    esac
    shift
  done

  if ! command -v certbot >/dev/null 2>&1; then
    echo "certbot is not installed." >&2
    return 1
  fi

  if [[ "${dry_run}" -eq 1 ]]; then
    echo ">> certbot renew --dry-run"
    certbot renew --dry-run
  else
    echo ">> certbot renew"
    certbot renew
    hesabix_load_deploy_env && hesabix_apply_nginx_domain_configs 1
    systemctl reload nginx 2>/dev/null || true
    echo "✓ Certificate renewal finished."
  fi
}
