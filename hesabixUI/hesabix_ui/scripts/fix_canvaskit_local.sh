#!/usr/bin/env bash
# اسکریپت برای اصلاح flutter_bootstrap.js برای استفاده از CanvasKit محلی

set -euo pipefail

BUILD_DIR="${1:-build/web}"

if [ ! -f "$BUILD_DIR/flutter_bootstrap.js" ]; then
  echo "خطا: فایل flutter_bootstrap.js یافت نشد در: $BUILD_DIR"
  exit 1
fi

echo "اصلاح flutter_bootstrap.js برای استفاده از CanvasKit محلی..."

# اصلاح خط که _flutter.loader.load() را فراخوانی می‌کند
# این خط را تغییر می‌دهیم تا از local CanvasKit استفاده کند
sed -i 's/_flutter\.loader\.load();/_flutter.loader.load({config: {canvasKitBaseUrl: "canvaskit\/", renderer: "canvaskit", useLocalCanvasKit: true}});/g' "$BUILD_DIR/flutter_bootstrap.js"

# همچنین باید اطمینان حاصل کنیم که buildConfig هم useLocalCanvasKit دارد
# این کار از طریق index.html انجام می‌شود، اما برای اطمینان بیشتر:
if grep -q '"useLocalCanvasKit":true' "$BUILD_DIR/flutter_bootstrap.js"; then
  echo "✓ flutter_bootstrap.js قبلاً با useLocalCanvasKit تنظیم شده"
else
  # اضافه کردن useLocalCanvasKit به buildConfig
  sed -i 's/"buildConfig":\s*{/"buildConfig": { "useLocalCanvasKit": true, /g' "$BUILD_DIR/flutter_bootstrap.js" || true
fi

echo "✓ flutter_bootstrap.js اصلاح شد تا از CanvasKit محلی استفاده کند"

# بررسی اینکه آیا پوشه canvaskit وجود دارد
if [ ! -d "$BUILD_DIR/canvaskit" ]; then
  echo "هشدار: پوشه canvaskit در $BUILD_DIR یافت نشد!"
  echo "      ممکن است نیاز باشد که Flutter را با --web-renderer canvaskit rebuild کنید."
else
  echo "✓ پوشه canvaskit موجود است"
fi

