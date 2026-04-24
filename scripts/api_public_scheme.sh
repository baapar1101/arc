#!/usr/bin/env bash
# Resolve public URL scheme (http|https) for API_DOMAIN — used by deploy.sh and update.sh.
# Priority:
#   1) If /etc/letsencrypt/live/<API_DOMAIN> exists → https (پس از certbot هم‌راستا می‌ماند)
#   2) API_PUBLIC_SCHEME env (http or https) — TLS سفارشی بدون مسیر پیش‌فرض letsencrypt
#   3) http
#
# Requires: API_DOMAIN
hesabix_resolve_api_public_scheme() {
  if [[ -n "${API_DOMAIN:-}" ]] && [[ -d "/etc/letsencrypt/live/${API_DOMAIN}" ]]; then
    printf '%s' "https"
    return 0
  fi
  local s="${API_PUBLIC_SCHEME:-}"
  s="${s,,}"
  case "$s" in
    http|https) printf '%s' "$s"; return 0 ;;
  esac
  printf '%s' "http"
}
