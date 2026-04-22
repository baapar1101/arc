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

# Noto Sans Armenian — همان مسیر gstatic که موتور وب درخواست می‌کند (باندل در assets؛ بیلد آفلاین)
SRC_ARMENIAN="$APP_DIR/assets/fonts/notosansarmenian.woff2"
DEST_ARMENIAN="$TARGET_ROOT/fonts/gstatic/s/notosansarmenian/v43/ZgN0jOZKPa7CHqq0h37c7ReDUubm2SEdFXp7ig73qtTY5idb74R9UdM3y2nZLorxb60nYy6zF3Eg.woff2"
mirror_file "$SRC_ARMENIAN" "$DEST_ARMENIAN" "Noto Sans Armenian"

# Noto Color Emoji — همان نام‌های sliceای که موتور با fontFallbackBaseUrl درخواست می‌کند
# منبع ترجیحی: assets/fonts/notocoloremoji.woff2 (همان محتوا به هر مسیر gstatic کپی می‌شود)
PATHS_FILE="$SCRIPT_DIR/web_gstatic_fallback_font_paths.txt"
GSTATIC_BASE="https://fonts.gstatic.com/s"
SRC_NOTO_COLOR_EMOJI="$APP_DIR/assets/fonts/notocoloremoji.woff2"

download_gstatic_slice_if_missing() {
  local rel="${1:?}"
  local dest="$TARGET_ROOT/fonts/gstatic/s/$rel"
  if [ -f "$dest" ]; then
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  if ! command -v curl >/dev/null 2>&1; then
    echo "[warn] sync_font_fallback_mirror: curl یافت نشد؛ نمی‌توان Noto Color Emoji را گرفت: $rel" >&2
    return 0
  fi
  if curl -fsSL --retry 2 --connect-timeout 20 "${GSTATIC_BASE}/${rel}" -o "$dest.tmp" && mv -f "$dest.tmp" "$dest"; then
    echo "[info] آینهٔ fallback موتور (Noto Color Emoji، دانلود): $dest"
  else
    rm -f "$dest.tmp" "$dest"
    echo "[warn] sync_font_fallback_mirror: دانلود ناموفق (اینترنت/فایروال؟): $rel" >&2
  fi
}

if [ -f "$PATHS_FILE" ]; then
  if [ -f "$SRC_NOTO_COLOR_EMOJI" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [[ "$line" =~ ^# ]] && continue
      [[ -z "${line// }" ]] && continue
      [[ "$line" == notocoloremoji/* ]] || continue
      mirror_file "$SRC_NOTO_COLOR_EMOJI" "$TARGET_ROOT/fonts/gstatic/s/$line" "Noto Color Emoji → $line"
    done < "$PATHS_FILE"
  else
    echo "[warn] sync_font_fallback_mirror: $SRC_NOTO_COLOR_EMOJI یافت نشد؛ تلاش دانلود از gstatic برای sliceها" >&2
    while IFS= read -r line || [ -n "$line" ]; do
      [[ "$line" =~ ^# ]] && continue
      [[ -z "${line// }" ]] && continue
      [[ "$line" == notocoloremoji/* ]] || continue
      download_gstatic_slice_if_missing "$line"
    done < "$PATHS_FILE"
  fi
else
  echo "[warn] sync_font_fallback_mirror: فایل فهرست مسیرها یافت نشد: $PATHS_FILE" >&2
fi
