#!/usr/bin/env bash
# یک‌بار (با دسترسی به fonts.gstatic.com) فایل‌های woff2 را در assets/gstatic_font_bundle/s/ می‌ریزد.
# پس از به‌روز کردن web_gstatic_fallback_font_paths.txt یا ارتقای Flutter، در صورت نیاز دوباره اجرا کنید.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PATHS_FILE="$SCRIPT_DIR/web_gstatic_fallback_font_paths.txt"
BUNDLE_S="$APP_DIR/assets/gstatic_font_bundle/s"
GSTATIC_BASE="${GSTATIC_BASE_URL:-https://fonts.gstatic.com/s}"
GSTATIC_BASE="${GSTATIC_BASE%/}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl لازم است." >&2
  exit 1
fi

download_one() {
  local rel="${1:?}"
  local dest="$BUNDLE_S/$rel"
  mkdir -p "$(dirname "$dest")"
  if [ -f "$dest" ]; then
    echo "[skip] exists: $rel"
    return 0
  fi
  echo "[get] $rel"
  if ! curl -fsSL --retry 3 --connect-timeout 25 --max-time 120 "${GSTATIC_BASE}/${rel}" -o "$dest.tmp"; then
    echo "[warn] ناموفق: $rel" >&2
    rm -f "$dest.tmp"
    return 0
  fi
  mv -f "$dest.tmp" "$dest"
}

# Roboto (کانواس‌کیت) — در فهرست paths نیست
download_one "roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2"
# Noto Sans SC — در فهرست به‌صورت کامنت است
download_one "notosanssc/v37/k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FrY9HbczS.woff2"

while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  [[ "$line" =~ ^# ]] && continue
  [[ -z "${line// }" ]] && continue
  [[ "$line" == notocoloremoji/* ]] && continue
  download_one "$line"
done < "$PATHS_FILE"

echo "Done. Bundle root: $BUNDLE_S"
