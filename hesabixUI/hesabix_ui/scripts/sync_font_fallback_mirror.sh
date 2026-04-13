#!/usr/bin/env bash
# کپی فونت‌های باندل‌شده به مسیرهایی که موتور Flutter Web با fontFallbackBaseUrl
# (جایگزین https://fonts.gstatic.com/s/...) انتظار دارد تا بدون CDN از همان سرور سرو شوند.
#
# مسیرهای نسبی باید با نسخهٔ Flutter هم‌خوان باشند؛ پس از ارتقای Flutter اگر خطای
# «Failed to parse fallback font …» دیدید، مسیر را از این فایل در SDK بگیرید:
#   engine/src/flutter/lib/web_ui/lib/src/engine/font_fallback_data.dart
# (جستجو برای نام فونت، مثلاً «Noto Sans Arabic».)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_ROOT="${1:-$APP_DIR/web}"

mirror_file() {
  local src="$1"
  local dest="$2"
  local label="$3"
  if [ ! -f "$src" ]; then
    echo "[warn] sync_font_fallback_mirror: منبع یافت نشد ($label): $src" >&2
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  cp -f "$src" "$dest"
  echo "[info] آینهٔ fallback موتور ($label): $dest"
}

# Roboto — canvaskit/fonts.dart
SRC_ROBOTO="$APP_DIR/assets/fonts/roboto.woff2"
DEST_ROBOTO="$TARGET_ROOT/fonts/gstatic/s/roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2"
mirror_file "$SRC_ROBOTO" "$DEST_ROBOTO" "Roboto"

# Noto Sans Arabic — وقتی گلیفی خارج از فونت‌های اصلی نیاز به fallback دارد (font_fallback_data.dart)
SRC_ARABIC="$APP_DIR/assets/fonts/nanosansarabic.woff2"
DEST_ARABIC="$TARGET_ROOT/fonts/gstatic/s/notosansarabic/v28/nwpxtLGrOAZMl5nJ_wfgRg3DrWFZWsnVBJ_sS6tlqHHFlhQ5l3sQWIHPqzCfyGyvvnCBFQLaig.woff2"
mirror_file "$SRC_ARABIC" "$DEST_ARABIC" "Noto Sans Arabic"
