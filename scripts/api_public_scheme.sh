#!/usr/bin/env bash
# Resolve public URL scheme (http|https) for API_DOMAIN — used by deploy.sh and update.sh.
# Priority:
#   1) Let's Encrypt cert for API_DOMAIN (direct path or SAN on another live cert)
#   2) API_PUBLIC_SCHEME env (http or https) — custom TLS without default letsencrypt path
#   3) http
#
# Requires: API_DOMAIN
# Optional: SSL_LETSENCRYPT_LIVE=/etc/letsencrypt/live/arc.example.com (must include API_DOMAIN in SAN)

if ! declare -F hesabix_pick_letsencrypt_live_for_domain >/dev/null 2>&1; then
  _HESABIX_SCHEME_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/hesabix_letsencrypt.sh"
  if [[ -r "${_HESABIX_SCHEME_LIB}" ]]; then
    # shellcheck source=lib/hesabix_letsencrypt.sh
    source "${_HESABIX_SCHEME_LIB}"
  else
  hesabix_pick_letsencrypt_live_for_domain() {
    local dom="$1"
    [[ -z "${dom}" ]] && return 1
    if [[ -n "${SSL_LETSENCRYPT_LIVE:-}" ]] && [[ -f "${SSL_LETSENCRYPT_LIVE}/fullchain.pem" ]]; then
      if openssl x509 -in "${SSL_LETSENCRYPT_LIVE}/fullchain.pem" -noout -text 2>/dev/null | grep -q "DNS:${dom}"; then
        echo "${SSL_LETSENCRYPT_LIVE}"
        return 0
      fi
    fi
    if [[ -f "/etc/letsencrypt/live/${dom}/fullchain.pem" ]]; then
      echo "/etc/letsencrypt/live/${dom}"
      return 0
    fi
    local d
    for d in /etc/letsencrypt/live/*; do
      [[ -f "${d}/fullchain.pem" ]] || continue
      if openssl x509 -in "${d}/fullchain.pem" -noout -text 2>/dev/null | grep -q "DNS:${dom}"; then
        echo "${d}"
        return 0
      fi
    done
    return 1
  }
  fi
fi

hesabix_resolve_api_public_scheme() {
  if hesabix_pick_letsencrypt_live_for_domain "${API_DOMAIN:-}" >/dev/null 2>&1; then
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
