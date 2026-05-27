#!/usr/bin/env bash
# فونت‌های fallback موتور Flutter Web را در web/build کپی می‌کند (fontFallbackBaseUrl در index.html).
# منبع: assets/gstatic_font_bundle — بدون وابستگی به fonts.gstatic.com در runtime.
#
# پس از ارتقای Flutter:
#   bash scripts/extract_flutter_gstatic_font_paths.sh
#   bash scripts/populate_gstatic_font_bundle.sh
#   commit باندل
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_ROOT="${1:-$APP_DIR/web}"
PATHS_FILE="$SCRIPT_DIR/web_gstatic_fallback_font_paths.txt"
BUNDLE_S="$APP_DIR/assets/gstatic_font_bundle/s"
SRC_NOTO_COLOR_EMOJI="$APP_DIR/assets/fonts/notocoloremoji.woff2"

: "${SYNC_FONT_FETCH_NETWORK:-0}"
: "${SYNC_FONT_STRICT:-0}"

mirror_file() {
  local src="$1"
  local dest="$2"
  local label="${3:-}"
  if [ ! -f "$src" ]; then
    echo "[warn] sync_font_fallback_mirror: منبع یافت نشد${label:+ ($label)}: $src" >&2
    return 1
  fi
  mkdir -p "$(dirname "$dest")"
  cp -f "$src" "$dest"
}

copy_from_bundle() {
  local rel="${1:?}"
  local src="$BUNDLE_S/$rel"
  local dest="$TARGET_ROOT/fonts/gstatic/s/$rel"
  if [ -f "$src" ] && [ -s "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    cp -f "$src" "$dest"
    return 0
  fi
  if [ "$SYNC_FONT_FETCH_NETWORK" = "1" ] && command -v curl >/dev/null 2>&1; then
    local base="${GSTATIC_BASE_URL:-https://fonts.gstatic.com/s}"
    base="${base%/}"
    echo "[info] باندل نبود، دانلود موقت: $rel" >&2
    mkdir -p "$(dirname "$dest")"
    if curl -fsSL --retry 2 --connect-timeout 25 --max-time 120 "${base}/${rel}" -o "$dest.tmp" && mv -f "$dest.tmp" "$dest"; then
      return 0
    fi
    rm -f "$dest.tmp" "$dest"
  fi
  echo "[warn] فایل باندل نیست: $src — populate_gstatic_font_bundle.sh" >&2
  return 1
}

if [ ! -f "$PATHS_FILE" ]; then
  echo "[error] فهرست مسیرها یافت نشد: $PATHS_FILE" >&2
  exit 1
fi

missing=0
copied=0
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  [[ "$line" =~ ^# ]] && continue
  [[ -z "${line// }" ]] && continue
  if [[ "$line" == notocoloremoji/* ]]; then
    if [ -f "$SRC_NOTO_COLOR_EMOJI" ]; then
      mirror_file "$SRC_NOTO_COLOR_EMOJI" "$TARGET_ROOT/fonts/gstatic/s/$line" "Noto Color Emoji" && copied=$((copied + 1)) || missing=$((missing + 1))
    elif copy_from_bundle "$line"; then
      copied=$((copied + 1))
    else
      missing=$((missing + 1))
    fi
  else
    if copy_from_bundle "$line"; then
      copied=$((copied + 1))
    else
      missing=$((missing + 1))
    fi
  fi
done < "$PATHS_FILE"

echo "[info] font mirror: $copied فایل در $TARGET_ROOT/fonts/gstatic/s/"
if [ "$missing" -gt 0 ]; then
  echo "[warn] $missing مسیر بدون فایل — احتمال ۴۰۴ در UI" >&2
  if [ "$SYNC_FONT_STRICT" = "1" ]; then
    exit 1
  fi
fi
