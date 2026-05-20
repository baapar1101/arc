#!/usr/bin/env bash
# نصب سایت gradle.mirror.hesabix.ir — الگوی maven.mirror (۸۰ + ۴۴۳ + self-signed در /etc/nginx/ssl)
# اجرا: sudo bash scripts/install_gradle_mirror_nginx.sh
# ساخت دوبارهٔ گواهی: sudo env REGENERATE_GRADLE_MIRROR_SSL=1 bash scripts/install_gradle_mirror_nginx.sh

set -euo pipefail

CONF_NAME="gradle.mirror.hesabix.ir.conf"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_BASE="${REPO_ROOT}/hesabixAPI/${CONF_NAME}"
SNIPPET_SRC="${REPO_ROOT}/hesabixAPI/nginx-snippets/gradle.mirror-hesabix-server.inc"
SNIPPET_DST="/etc/nginx/snippets/gradle.mirror-hesabix-server.inc"
DST_AVAILABLE="/etc/nginx/sites-available/${CONF_NAME}"
DST_ENABLED="/etc/nginx/sites-enabled/${CONF_NAME}"
CACHE_DIR="/var/cache/nginx/gradle_mirror_cache"
ACME_ROOT="/var/lib/hesabix/acme"
SSL_DIR="/etc/nginx/ssl"
SSL_KEY="${SSL_DIR}/gradle.mirror.hesabix.ir.key"
SSL_FULL="${SSL_DIR}/gradle.mirror.hesabix.ir.fullchain.pem"

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

generate_self_signed() {
  echo "ایجاد/به‌روزرسانی گواهی self-signed در $SSL_DIR ..."
  if ! command -v openssl >/dev/null 2>&1; then
    echo "openssl نصب نیست." >&2
    return 1
  fi
  local old_umask
  old_umask="$(umask)"
  umask 077
  local tmpdir
  tmpdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap 'rm -rf "$tmpdir"; umask "$old_umask"; trap - RETURN' RETURN
  if ! openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
    -keyout "$tmpdir/key.pem" -out "$tmpdir/fullchain.pem" \
    -subj "/CN=gradle.mirror.hesabix.ir" \
    -addext "subjectAltName=DNS:gradle.mirror.hesabix.ir" 2>/dev/null; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 825 \
      -keyout "$tmpdir/key.pem" -out "$tmpdir/fullchain.pem" \
      -subj "/CN=gradle.mirror.hesabix.ir"
  fi
  install -m 0640 -o root -g root "$tmpdir/key.pem" "$SSL_KEY"
  install -m 0644 -o root -g root "$tmpdir/fullchain.pem" "$SSL_FULL"
}

if [[ "${REGENERATE_GRADLE_MIRROR_SSL:-}" == "1" ]]; then
  generate_self_signed || exit 1
elif [[ ! -f "$SSL_KEY" || ! -f "$SSL_FULL" ]]; then
  generate_self_signed || exit 1
fi

install -m 0644 "$SNIPPET_SRC" "$SNIPPET_DST"
if [[ -d "$CACHE_DIR" ]] && ls -A "$CACHE_DIR" >/dev/null 2>&1; then
  rm -rf "${CACHE_DIR}/"*
  echo "کش gradle_mirror_cache خالی شد (پس از تغییر upstream یا نگاشت مسیر توصیه می‌شود)."
fi
cp -a "$SRC_BASE" "$DST_AVAILABLE"
chmod 644 "$DST_AVAILABLE"
ln -sf "$DST_AVAILABLE" "$DST_ENABLED"

if nginx -t; then
  systemctl reload nginx
  echo "OK: $DST_ENABLED — nginx reload (HTTP+HTTPS)."
  echo "تست سلامت (بدون upstream): curl -skI 'https://127.0.0.1/android/maven2' -H 'Host: gradle.mirror.hesabix.ir' | head -3"
  echo "تست زیپ: curl -skI -H 'Host: gradle.mirror.hesabix.ir' 'https://127.0.0.1/distributions/gradle-8.12-all.zip' | head -5"
else
  echo "nginx -t ناموفق" >&2
  exit 1
fi
