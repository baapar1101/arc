#!/usr/bin/env bash
# اگر hesabix-ui روی همین میزبان با nginx نصب باشد، بلاک‌های version.json،
# flutter_service_worker.js و ورودی‌های اصلی Flutter (بدون کش یک‌ساله) را اضافه/تکمیل می‌کند؛
# سپس nginx -t و reload (نیاز به sudo روی غیر root).

set -euo pipefail

NGINX_UI_CONF="${NGINX_UI_CONF:-/etc/nginx/sites-available/hesabix-ui.conf}"

log() { echo "[ensure-nginx-ui] $*"; }
warn() { echo "[ensure-nginx-ui] WARN: $*" >&2; }

if ! command -v nginx >/dev/null 2>&1; then
  log "nginx در PATH نیست؛ رد می‌شود."
  exit 0
fi

if [[ ! -f "$NGINX_UI_CONF" ]]; then
  log "فایل پیکربندی یافت نشد: $NGINX_UI_CONF — رد می‌شود."
  exit 0
fi

has_main=0 has_boot=0 has_v=0 has_sw=0
grep -qE '^\s*location\s*=\s*/main\.dart\.js\s*\{' "$NGINX_UI_CONF" 2>/dev/null && has_main=1
grep -qE '^\s*location\s*=\s*/flutter_bootstrap\.js\s*\{' "$NGINX_UI_CONF" 2>/dev/null && has_boot=1
grep -qE '^\s*location\s*=\s*/version\.json\s*\{' "$NGINX_UI_CONF" 2>/dev/null && has_v=1
grep -qE '^\s*location\s*=\s*/flutter_service_worker\.js\s*\{' "$NGINX_UI_CONF" 2>/dev/null && has_sw=1

if [[ "$has_main" -eq 1 && "$has_boot" -eq 1 ]]; then
  log "ورودی‌های JS Flutter (bootstrap + main) قبلاً در $NGINX_UI_CONF اعمال شده‌اند؛ بدون تغییر."
  exit 0
fi

if [[ "$has_v" -eq 1 && "$has_sw" -eq 0 ]] || [[ "$has_v" -eq 0 && "$has_sw" -eq 1 ]]; then
  warn "فقط یکی از دو location (version یا SW) در $NGINX_UI_CONF هست؛ برای جلوگیری از بلاک تکراری، خودتان تکمیل کنید."
  exit 0
fi

SUDO=()
if [[ "$(id -u)" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
  else
    warn "نیاز به نوشتن در $NGINX_UI_CONF و reload؛ sudo در دسترس نیست."
    exit 1
  fi
fi

if [[ ! -r "$NGINX_UI_CONF" ]]; then
  warn "خواندن $NGINX_UI_CONF ممکن نیست."
  exit 1
fi

BLOCKFILE="$(mktemp)"
ENTRYFILE="$(mktemp)"
ENTRY_BOOT="$(mktemp)"
ENTRY_MAIN="$(mktemp)"
TMP="$(mktemp)"
trap 'rm -f "$TMP" "$BLOCKFILE" "$ENTRYFILE" "$ENTRY_BOOT" "$ENTRY_MAIN"' EXIT

cat > "$ENTRY_BOOT" <<'BOOTBLK'
  # hesabix: flutter entry js no long-cache (managed by scripts/ensure_nginx_ui_version_probe.sh)
  location = /flutter_bootstrap.js {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
    try_files $uri =404;
  }

BOOTBLK

cat > "$ENTRY_MAIN" <<'MAINBLK'
  location = /main.dart.js {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
    try_files $uri =404;
  }

MAINBLK

{
  [[ "$has_boot" -eq 0 ]] && cat "$ENTRY_BOOT"
  [[ "$has_main" -eq 0 ]] && cat "$ENTRY_MAIN"
} >"$ENTRYFILE"

cat > "$BLOCKFILE" <<'NGINXBLK'
  # hesabix: ui version probe + SW cache (managed by scripts/ensure_nginx_ui_version_probe.sh)
  # نسخهٔ build (همیشه تازه؛ پایهٔ تشخیص به‌روزرسانی در کلاینت)
  location = /version.json {
    add_header Cache-Control "no-store" always;
    expires off;
    try_files $uri =404;
  }

  # Service Worker نباید با immutable یک‌ساله قفل شود
  location = /flutter_service_worker.js {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
    try_files $uri =404;
  }

  # hesabix: flutter entry js no long-cache (managed by scripts/ensure_nginx_ui_version_probe.sh)
  location = /flutter_bootstrap.js {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
    try_files $uri =404;
  }

  location = /main.dart.js {
    add_header Cache-Control "no-cache, must-revalidate" always;
    expires off;
    try_files $uri =404;
  }

NGINXBLK

BF="$BLOCKFILE"
if [[ "$has_v" -eq 1 && "$has_sw" -eq 1 ]]; then
  BF="$ENTRYFILE"
  log "به‌روزرسانی جزئی: افزودن ورودی‌های flutter_bootstrap.js و main.dart.js..."
else
  log "درج کامل بلاک version + SW + entry JS..."
fi

awk -v bf="$BF" '
  BEGIN { inserted=0 }
  inserted==0 && $0 ~ /^  location \/ \{/ {
    while ((getline line < bf) > 0) print line
    close(bf)
    inserted=1
  }
  { print }
' "$NGINX_UI_CONF" > "$TMP"

if ! grep -qE '^  location = /flutter_bootstrap\.js' "$TMP" || ! grep -qE '^  location = /main\.dart\.js' "$TMP"; then
  warn "الگوی «  location / {» در $NGINX_UI_CONF پیدا نشد یا درج entry JS ناموفق بود."
  exit 1
fi

if cmp -s "$NGINX_UI_CONF" "$TMP"; then
  log "بدون تغییر."
  exit 0
fi

"${SUDO[@]}" cp -a "$NGINX_UI_CONF" "${NGINX_UI_CONF}.bak.$(date +%Y%m%d%H%M%S)"
"${SUDO[@]}" cp "$TMP" "$NGINX_UI_CONF"
log "پیکربندی به‌روز شد: $NGINX_UI_CONF (پشتیبان .bak.* ساخته شد)"

if "${SUDO[@]}" nginx -t 2>&1; then
  if "${SUDO[@]}" systemctl reload nginx 2>/dev/null; then
    log "nginx با موفقیت reload شد."
  elif command -v service >/dev/null 2>&1 && "${SUDO[@]}" service nginx reload 2>/dev/null; then
    log "nginx با service reload شد."
  else
    warn "nginx -t موفق بود ولی reload انجام نشد؛ دستی: sudo systemctl reload nginx"
    exit 1
  fi
else
  warn "nginx -t ناموفق؛ فایل قبلی را از .bak بازگردانی کنید."
  exit 1
fi

exit 0
