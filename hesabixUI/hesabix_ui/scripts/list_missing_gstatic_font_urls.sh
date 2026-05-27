#!/usr/bin/env bash
# فهرست URL فونت‌های گم‌شده در باندل (برای دانلود دستی)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_S="$APP_DIR/assets/gstatic_font_bundle/s"
PATHS_FILE="$SCRIPT_DIR/web_gstatic_fallback_font_paths.txt"
BASE="${GSTATIC_BASE_URL:-https://fonts.gstatic.com/s}"
BASE="${BASE%/}"
OUT="${1:-$SCRIPT_DIR/missing_gstatic_font_urls.txt}"

missing=0
{
  echo "# گم‌شده در $BUNDLE_S — $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "# URL | مسیر محلی"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^# ]] && continue
    [[ -z "${line// }" ]] && continue
    [[ "$line" == notocoloremoji/* ]] && continue
    if [ ! -s "$BUNDLE_S/$line" ]; then
      echo "$BASE/$line"
      echo "# $BUNDLE_S/$line"
      missing=$((missing + 1))
    fi
  done < "$PATHS_FILE"
} > "$OUT"
echo "$missing missing → $OUT"
