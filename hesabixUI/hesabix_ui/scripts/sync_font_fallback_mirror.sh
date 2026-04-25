#!/usr/bin/env bash
# فونت‌های fallback موتور Flutter Web را در web/build کپی می‌کند تا از همان دامنهٔ UI سرو شوند
# (fontFallbackBaseUrl در index.html). منبع: باندل ثابت در repo — بدون fonts.gstatic.com در زمان بیلد.
#
# به‌روز کردن فهرست مسیرها پس از ارتقای Flutter: web_gstatic_fallback_font_paths.txt و سپس:
#   bash scripts/populate_gstatic_font_bundle.sh
# (با اینترنت؛ فایل‌های جدید را commit کنید.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_ROOT="${1:-$APP_DIR/web}"
PATHS_FILE="$SCRIPT_DIR/web_gstatic_fallback_font_paths.txt"
BUNDLE_S="$APP_DIR/assets/gstatic_font_bundle/s"
SRC_NOTO_COLOR_EMOJI="$APP_DIR/assets/fonts/notocoloremoji.woff2"

# فقط اگر باندل ناقص بود و SYNC_FONT_FETCH_NETWORK=1: دانلود موقت از gstatic (توسعه)
: "${SYNC_FONT_FETCH_NETWORK:-0}"

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
  echo "[info] آینهٔ fallback موتور${label:+ ($label)}: $dest"
}

copy_from_bundle() {
  local rel="${1:?}"
  local src="$BUNDLE_S/$rel"
  local dest="$TARGET_ROOT/fonts/gstatic/s/$rel"
  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dest")"
    cp -f "$src" "$dest"
    echo "[info] باندل → $dest"
    return 0
  fi
  if [ "$SYNC_FONT_FETCH_NETWORK" = "1" ] && command -v curl >/dev/null 2>&1; then
    local base="${GSTATIC_BASE_URL:-https://fonts.gstatic.com/s}"
    base="${base%/}"
    echo "[info] باندل نبود، دانلود موقت: $rel" >&2
    mkdir -p "$(dirname "$dest")"
    if curl -fsSL --retry 2 --connect-timeout 25 --max-time 120 "${base}/${rel}" -o "$dest.tmp" && mv -f "$dest.tmp" "$dest"; then
      echo "[info] دانلود → $dest"
      return 0
    fi
    rm -f "$dest.tmp" "$dest"
  fi
  echo "[warn] فایل باندل نیست: $src — برای پر کردن: scripts/populate_gstatic_font_bundle.sh" >&2
  return 1
}

# Roboto + Noto SC در فهرست paths نیستند؛ در باندل هستند
copy_from_bundle "roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2" || true
copy_from_bundle "notosanssc/v37/k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FrY9HbczS.woff2" || true

if [ -f "$PATHS_FILE" ]; then
  if [ ! -f "$SRC_NOTO_COLOR_EMOJI" ]; then
    echo "[warn] notocoloremoji: $SRC_NOTO_COLOR_EMOJI یافت نشد" >&2
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^# ]] && continue
    [[ -z "${line// }" ]] && continue
    if [[ "$line" == notocoloremoji/* ]]; then
      if [ -f "$SRC_NOTO_COLOR_EMOJI" ]; then
        mirror_file "$SRC_NOTO_COLOR_EMOJI" "$TARGET_ROOT/fonts/gstatic/s/$line" "Noto Color Emoji → $line" || true
      elif [ "$SYNC_FONT_FETCH_NETWORK" = "1" ]; then
        copy_from_bundle "$line" || true
      else
        echo "[warn] نمی‌توان slice ایموجی را ساخت: $line" >&2
      fi
    else
      copy_from_bundle "$line" || true
    fi
  done < "$PATHS_FILE"
else
  echo "[warn] فهرست مسیرها یافت نشد: $PATHS_FILE" >&2
fi
