#!/usr/bin/env bash
# فونت‌های fallback موتور Flutter Web را در web/build کپی می‌کند (fontFallbackBaseUrl در index.html).
# منبع: assets/gstatic_font_bundle — بدون وابستگی به fonts.gstatic.com در runtime.
#
# پس از ارتقای Flutter:
#   bash scripts/extract_flutter_gstatic_font_paths.sh
#   bash scripts/populate_gstatic_font_bundle.sh
#   commit باندل
#
# خانواده‌های تاریخی/نادر (هیروگلیف، میخی، …) به‌صورت پیش‌فرض sync نمی‌شوند تا
# حجم دیپلوی کم بماند. برای شامل کردن کامل: SYNC_FONT_INCLUDE_RARE=1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_ROOT="${1:-$APP_DIR/web}"
PATHS_FILE="$SCRIPT_DIR/web_gstatic_fallback_font_paths.txt"
BUNDLE_S="$APP_DIR/assets/gstatic_font_bundle/s"
RARE_FAMILIES_FILE="$SCRIPT_DIR/web_gstatic_rare_families.txt"

SYNC_FONT_FETCH_NETWORK="${SYNC_FONT_FETCH_NETWORK:-0}"
SYNC_FONT_STRICT="${SYNC_FONT_STRICT:-0}"
SYNC_FONT_INCLUDE_RARE="${SYNC_FONT_INCLUDE_RARE:-0}"

is_rare_family() {
  local rel="$1"
  local fam="${rel%%/*}"
  [ -f "$RARE_FAMILIES_FILE" ] || return 1
  grep -vE '^\s*(#|$)' "$RARE_FAMILIES_FILE" | grep -qxF "$fam"
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
    echo "[info] not in bundle, temporary download: $rel" >&2
    mkdir -p "$(dirname "$dest")"
    if curl -fsSL --retry 2 --connect-timeout 25 --max-time 120 "${base}/${rel}" -o "$dest.tmp" && mv -f "$dest.tmp" "$dest"; then
      return 0
    fi
    rm -f "$dest.tmp" "$dest"
  fi
  echo "[warn] file is not in the bundle: $src — populate_gstatic_font_bundle.sh" >&2
  return 1
}

if [ ! -f "$PATHS_FILE" ]; then
  echo "[error] path list not found: $PATHS_FILE" >&2
  exit 1
fi

missing=0
copied=0
skipped_rare=0
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  [[ "$line" =~ ^# ]] && continue
  [[ -z "${line// }" ]] && continue
  if [ "$SYNC_FONT_INCLUDE_RARE" != "1" ] && is_rare_family "$line"; then
    skipped_rare=$((skipped_rare + 1))
    # حذف نسخهٔ قبلی در هدف تا stub/فایل کهنه نماند
    rm -f "$TARGET_ROOT/fonts/gstatic/s/$line"
    continue
  fi
  if copy_from_bundle "$line"; then
    copied=$((copied + 1))
  else
    missing=$((missing + 1))
  fi
done < "$PATHS_FILE"

echo "[info] font mirror: $copied files in $TARGET_ROOT/fonts/gstatic/s/ (skipped rare=$skipped_rare)"
if [ "$missing" -gt 0 ]; then
  echo "[warn] $missing paths missing files — UI may 404" >&2
  if [ "$SYNC_FONT_STRICT" = "1" ]; then
    exit 1
  fi
fi
