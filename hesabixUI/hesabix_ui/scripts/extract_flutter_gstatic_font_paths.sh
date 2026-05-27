#!/usr/bin/env bash
# فهرست کامل مسیرهای fonts.gstatic.com/s/ را از font_fallback_data.dart همان Flutter نصب‌شده استخراج می‌کند.
# پس از ارتقای Flutter: این اسکریپت → populate_gstatic_font_bundle.sh → commit باندل.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$SCRIPT_DIR/web_gstatic_fallback_font_paths.txt"

flutter_data="${FLUTTER_FONT_FALLBACK_DATA:-}"
if [ -z "$flutter_data" ]; then
  if command -v flutter >/dev/null 2>&1; then
    flutter_root="$(flutter --version --machine 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('flutterRoot',''))" 2>/dev/null || true)"
    if [ -n "$flutter_root" ] && [ -f "$flutter_root/engine/src/flutter/lib/web_ui/lib/src/engine/font_fallback_data.dart" ]; then
      flutter_data="$flutter_root/engine/src/flutter/lib/web_ui/lib/src/engine/font_fallback_data.dart"
    fi
  fi
fi
if [ -z "$flutter_data" ] || [ ! -f "$flutter_data" ]; then
  for candidate in \
    /opt/flutter/engine/src/flutter/lib/web_ui/lib/src/engine/font_fallback_data.dart \
    "$HOME/flutter/engine/src/flutter/lib/web_ui/lib/src/engine/font_fallback_data.dart"; do
    if [ -f "$candidate" ]; then
      flutter_data="$candidate"
      break
    fi
  done
fi

if [ -z "$flutter_data" ] || [ ! -f "$flutter_data" ]; then
  echo "font_fallback_data.dart یافت نشد. FLUTTER_FONT_FALLBACK_DATA را تنظیم کنید." >&2
  exit 1
fi

flutter_ver="$(flutter --version 2>/dev/null | head -1 || echo unknown)"
count="$(grep -oE "'[^']+\.woff2'" "$flutter_data" | tr -d "'" | sort -u | wc -l)"

{
  echo "# فهرست fallback موتور Flutter Web — استخراج خودکار از font_fallback_data.dart"
  echo "# Flutter: $flutter_ver"
  echo "# منبع: $flutter_data"
  echo "# تعداد مسیر: $count (+ roboto زیر)"
  echo "# بازتولید: bash scripts/extract_flutter_gstatic_font_paths.sh"
  echo "# پر کردن باندل: bash scripts/populate_gstatic_font_bundle.sh"
  echo "#"
  echo "# Roboto برای CanvasKit / fallback اضطراری (در font_fallback_data نیست)"
  echo "roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2"
  echo "#"
  grep -oE "'[^']+\.woff2'" "$flutter_data" | tr -d "'" | sort -u
} > "$OUT"

echo "Wrote $count engine paths + roboto → $OUT"
