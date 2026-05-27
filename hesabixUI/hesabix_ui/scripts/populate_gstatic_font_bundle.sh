#!/usr/bin/env bash
# فایل‌های woff2 را در assets/gstatic_font_bundle/s/ می‌ریزد (فهرست کامل موتور Flutter Web).
# ایران / تحریم: GSTATIC_BASE_URL برای آینه؛ POPULATE_FONT_PARALLEL؛ اجرای مجدد = resume.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PATHS_FILE="$SCRIPT_DIR/web_gstatic_fallback_font_paths.txt"
BUNDLE_S="$APP_DIR/assets/gstatic_font_bundle/s"
GSTATIC_BASE="${GSTATIC_BASE_URL:-https://fonts.gstatic.com/s}"
GSTATIC_BASE="${GSTATIC_BASE%/}"
PARALLEL="${POPULATE_FONT_PARALLEL:-8}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl لازم است." >&2
  exit 1
fi

if [ ! -f "$PATHS_FILE" ]; then
  echo "فهرست یافت نشد. ابتدا: bash scripts/extract_flutter_gstatic_font_paths.sh" >&2
  exit 1
fi

TMP_LIST="$(mktemp)"
trap 'rm -f "$TMP_LIST"' EXIT

while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  [[ "$line" =~ ^# ]] && continue
  [[ -z "${line// }" ]] && continue
  [[ "$line" == notocoloremoji/* ]] && continue
  if [ ! -s "$BUNDLE_S/$line" ]; then
    printf '%s\n' "$line"
  fi
done < "$PATHS_FILE" > "$TMP_LIST"

todo="$(wc -l < "$TMP_LIST" | tr -d ' ')"
if [ "$todo" -eq 0 ]; then
  echo "باندل کامل است."
  exit 0
fi

echo "دانلود $todo فایل از $GSTATIC_BASE (موازی=$PARALLEL) ..."

export BUNDLE_S GSTATIC_BASE
xargs -P "$PARALLEL" -I {} bash -c '
  rel="$1"
  dest="$BUNDLE_S/$rel"
  mkdir -p "$(dirname "$dest")"
  if curl --retry 5 --retry-delay 2 --connect-timeout 30 --max-time 180 -fsSL \
      "$GSTATIC_BASE/$rel" -o "$dest.tmp" 2>/dev/null && [ -s "$dest.tmp" ]; then
    mv -f "$dest.tmp" "$dest"
    echo "[ok] $rel"
  else
    rm -f "$dest.tmp"
    echo "[fail] $rel" >&2
  fi
' _ {} < "$TMP_LIST"

missing=0
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  [[ "$line" =~ ^# ]] && continue
  [[ -z "${line// }" ]] && continue
  [[ "$line" == notocoloremoji/* ]] && continue
  if [ ! -s "$BUNDLE_S/$line" ]; then
    echo "[missing] $line" >&2
    missing=$((missing + 1))
  fi
done < "$PATHS_FILE"

if [ "$missing" -gt 0 ]; then
  echo "[error] $missing فایل در باندل نیست — دوباره اجرا کنید." >&2
  exit 1
fi
count="$(find "$BUNDLE_S" -name '*.woff2' | wc -l)"
echo "Done. Bundle: $BUNDLE_S — $count woff2 files"
