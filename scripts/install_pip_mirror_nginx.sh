#!/usr/bin/env bash
# نصب آینه PyPI — p.mirror.hesabix.ir (snippet + بلاک سرور؛ الگوی f/maven/gradle).
# بدون ارسال IP به upstream؛ URL مطلق package-mirror.liara.ir در پاسخ به $host بازنویسی می‌شود (پس از تغییر upstream کش خالی می‌شود).
# اجرا: sudo bash scripts/install_pip_mirror_nginx.sh

set -euo pipefail

CONF_NAME="p-mirror-pypi.conf"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_SITE="${REPO_ROOT}/hesabixAPI/${CONF_NAME}"
SNIPPET_SRC="${REPO_ROOT}/hesabixAPI/nginx-snippets/p.mirror-pypi-location.inc"
SNIPPET_DST="/etc/nginx/snippets/p-mirror-pypi-location.conf"
DST_AVAILABLE="/etc/nginx/sites-available/${CONF_NAME}"
DST_ENABLED="/etc/nginx/sites-enabled/${CONF_NAME}"
CACHE_DIR="/var/cache/nginx/pypi"
SSL_DIR="/etc/nginx/ssl"
SSL_KEY="${SSL_DIR}/p.mirror.hesabix.ir.key"
SSL_FULL="${SSL_DIR}/p.mirror.hesabix.ir.fullchain.pem"
CONF_D_CACHE="${REPO_ROOT}/hesabixAPI/nginx-conf.d/pypi-cache.conf"
CONF_D_RL="${REPO_ROOT}/hesabixAPI/nginx-conf.d/rate-limit-pypi.conf"

if [[ $EUID -ne 0 ]]; then
  echo "با root یا sudo اجرا کنید: sudo bash $0" >&2
  exit 1
fi

if ! command -v nginx >/dev/null 2>&1; then
  echo "nginx نصب نیست." >&2
  exit 1
fi

if [[ ! -f "$SRC_SITE" ]] || [[ ! -f "$SNIPPET_SRC" ]]; then
  echo "فایل منبع ناقص است: $SRC_SITE یا $SNIPPET_SRC" >&2
  exit 1
fi

install -d -m 0750 -o root -g root "$SSL_DIR"
install -d -m 0755 -o www-data -g www-data "$CACHE_DIR"

if [[ ! -f /etc/nginx/conf.d/pypi-cache.conf ]] && [[ -f "$CONF_D_CACHE" ]]; then
  install -m 0644 "$CONF_D_CACHE" /etc/nginx/conf.d/pypi-cache.conf
  echo "نصب شد: /etc/nginx/conf.d/pypi-cache.conf"
elif [[ ! -f /etc/nginx/conf.d/pypi-cache.conf ]]; then
  echo "هشدار: فایل pypi-cache.conf در مخزن نیست؛ keys_zone=pypi_cache باید تعریف شود." >&2
fi

if [[ ! -f /etc/nginx/conf.d/rate-limit-pypi.conf ]] && [[ -f "$CONF_D_RL" ]]; then
  install -m 0644 "$CONF_D_RL" /etc/nginx/conf.d/rate-limit-pypi.conf
  echo "نصب شد: /etc/nginx/conf.d/rate-limit-pypi.conf"
fi

install -m 0644 "$SNIPPET_SRC" "$SNIPPET_DST"

if [[ -d "$CACHE_DIR" ]] && ls -A "$CACHE_DIR" >/dev/null 2>&1; then
  rm -rf "${CACHE_DIR}/"*
  echo "کش nginx PyPI خالی شد (پس از تغییر لینک‌ها در بدنهٔ پاسخ ضروری است)."
fi

if [[ ! -f "$SSL_KEY" || ! -f "$SSL_FULL" ]]; then
  echo "گواهی SSL برای p.mirror پیدا نشد؛ self-signed یا LE را در $SSL_KEY و $SSL_FULL قرار دهید." >&2
fi

install -m 0644 "$SRC_SITE" "$DST_AVAILABLE"
chmod 644 "$DST_AVAILABLE"
ln -sf "$DST_AVAILABLE" "$DST_ENABLED"

if nginx -t; then
  systemctl reload nginx
  echo "OK: $DST_ENABLED — nginx reload."
  echo "تست: curl -skI -H 'Host: p.mirror.hesabix.ir' 'https://127.0.0.1/simple/' | head -5"
else
  echo "nginx -t ناموفق" >&2
  exit 1
fi
