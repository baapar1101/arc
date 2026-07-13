#!/usr/bin/env bash
# Shared Let's Encrypt helpers for Hesabix deploy, update, nginx, and SSL management.

# Returns live cert directory path on stdout, or non-zero if none found.
# Optional env: SSL_LETSENCRYPT_LIVE=/etc/letsencrypt/live/arc.example.com (SAN must include domain)
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

hesabix_nginx_ssl_block_for_live_dir() {
  local live="$1"
  [[ -z "${live}" ]] || [[ ! -f "${live}/fullchain.pem" ]] && return 0
  echo "  listen 443 ssl;"
  echo "  ssl_certificate ${live}/fullchain.pem;"
  echo "  ssl_certificate_key ${live}/privkey.pem;"
  if [[ -f /etc/letsencrypt/options-ssl-nginx.conf ]]; then
    echo "  include /etc/letsencrypt/options-ssl-nginx.conf;"
  fi
  if [[ -f /etc/letsencrypt/ssl-dhparams.pem ]]; then
    echo "  ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;"
  fi
}

hesabix_domain_has_ssl() {
  local dom="$1"
  hesabix_pick_letsencrypt_live_for_domain "${dom}" >/dev/null 2>&1
}

hesabix_resolve_ui_public_scheme() {
  if hesabix_pick_letsencrypt_live_for_domain "${UI_DOMAIN:-}" >/dev/null 2>&1; then
    printf '%s' "https"
    return 0
  fi
  printf '%s' "http"
}
