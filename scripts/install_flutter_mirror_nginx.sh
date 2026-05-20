#!/usr/bin/env bash
# نصب سایت f.mirror.hesabix.ir — همان الگوی p.mirror (80 + 443 + گواهی در /etc/nginx/ssl)
# اجرا: sudo bash scripts/install_flutter_mirror_nginx.sh

set -euo pipefail

CONF_NAME="f.mirror.hesabix.ir.conf"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_BASE="${REPO_ROOT}/hesabixAPI/${CONF_NAME}"
SNIPPET_SRC="${REPO_ROOT}/hesabixAPI/nginx-snippets/f.mirror-hesabix-server.inc"
SNIPPET_DST="/etc/nginx/snippets/f.mirror-hesabix-server.inc"
DST_AVAILABLE="/etc/nginx/sites-available/${CONF_NAME}"
DST_ENABLED="/etc/nginx/sites-enabled/${CONF_NAME}"
CACHE_DIR="/var/cache/nginx/flutter_cache"
ACME_ROOT="/var/lib/hesabix/acme"
SSL_DIR="/etc/nginx/ssl"
SSL_KEY="${SSL_DIR}/f.mirror.hesabix.ir.key"
SSL_FULL="${SSL_DIR}/f.mirror.hesabix.ir.fullchain.pem"

if [[ $EUID -ne 0 ]]; then
  echo "با root یا sudo اجرا کنید: sudo bash $0" >&2
  exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
  echo "nginx نصب نیست." >&2
  exit 1
fi

if [[ ! -f "$SRC_BASE" ]] || [[ ! -f "$SNIPPET_SRC" ]]; then
  echo "فایل منبع ناقص است: $SRC_BASE یا $SNIPPET_SRC" >&2
  exit 1
fi

install -d -m 0750 -o root -g root "$SSL_DIR"
install -d -m 0755 -o www-data -g www-data "$CACHE_DIR"
install -d -m 0755 -o root -g root "$ACME_ROOT/.well-known/acme-challenge"

# همان p.mirror: اگر گواهی نیست، self-signed بساز (برای SNI/HTTPS مبدأ از دید CDN)
if [[ ! -f "$SSL_KEY" || ! -f "$SSL_FULL" ]]; then
  echo "ایجاد گواهی self-signed در $SSL_DIR (مثل p.mirror)..."
  if command -v openssl >/dev/null 2>&1; then
    if ! openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
      -keyout "$SSL_KEY" -out "$SSL_FULL" \
      -subj "/CN=f.mirror.hesabix.ir" \
      -addext "subjectAltName=DNS:f.mirror.hesabix.ir" 2>/dev/null; then
      openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
        -keyout "$SSL_KEY" -out "$SSL_FULL" \
        -subj "/CN=f.mirror.hesabix.ir"
    fi
    chmod 640 "$SSL_KEY"
    chmod 644 "$SSL_FULL"
  else
    echo "openssl نصب نیست؛ فایل‌های گواهی را دستی در $SSL_KEY و $SSL_FULL بگذارید." >&2
    exit 1
  fi
fi

install -m 0644 "$SNIPPET_SRC" "$SNIPPET_DST"

if [[ -d "$CACHE_DIR" ]] && ls -A "$CACHE_DIR" >/dev/null 2>&1; then
  rm -rf "${CACHE_DIR}/"*
  echo "کش flutter_cache خالی شد (پس از تغییر upstream یا بدنهٔ JSON لینک‌های مطلق، کش قدیمی توصیه نمی‌شود)."
fi

cp -a "$SRC_BASE" "$DST_AVAILABLE"
chmod 644 "$DST_AVAILABLE"
ln -sf "$DST_AVAILABLE" "$DST_ENABLED"

if nginx -t; then
  systemctl reload nginx
  echo "OK: $DST_ENABLED — nginx reload (HTTP+HTTPS مثل p.mirror)."
  echo "تست: curl -sk 'https://127.0.0.1/' -H 'Host: f.mirror.hesabix.ir' | head -1"
else
  echo "nginx -t ناموفق" >&2
  exit 1
fi
