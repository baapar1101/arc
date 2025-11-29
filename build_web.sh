#!/usr/bin/env bash

set -euo pipefail

# Build script for Flutter Web in this repo.
# Creates a web build that uses https://hsxn.hesabix.ir/ as the API base URL by default.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

DEFAULT_MODE="release" # debug|profile|release
DEFAULT_BUILD_DIR="build/web"
DEFAULT_API_BASE_URL="https://hsxn.hesabix.ir"

USER_PROJECT=""
MODE="$DEFAULT_MODE"
BUILD_DIR=""
API_BASE_URL="$DEFAULT_API_BASE_URL"
CLEAN_BUILD=false
INSTALL_DEPS=false

print_usage() {
  cat <<EOF
Usage: ./build_web.sh [--project <path>] [--mode <debug|profile|release>] [--build-dir <dir>] [--api-base-url <url>] [--clean] [--install-deps] [--help]

Options:
  --project PATH     مسیر پروژه فلاتر (حاوی pubspec.yaml). در صورت عدم تعیین، به‌صورت خودکار تشخیص می‌شود.
  --mode MODE        نوع build: debug، profile یا release (پیش‌فرض: $DEFAULT_MODE).
  --build-dir DIR    مسیر build directory (پیش‌فرض: $DEFAULT_BUILD_DIR).
  --api-base-url     آدرس پایه API (پیش‌فرض: $DEFAULT_API_BASE_URL).
  --clean            پاک کردن build directory قبل از build.
  --install-deps     نصب وابستگی‌ها قبل از build.
  -h, --help         نمایش راهنما.

نمونه اجرا:
  ./build_web.sh
  ./build_web.sh --mode debug --clean
  ./build_web.sh --project hesabixUI/hesabix_ui
  ./build_web.sh --api-base-url https://hsxn.hesabix.ir
EOF
}

warn() { echo "[warn] $*" >&2; }
die() { echo "[error] $*" >&2; exit 1; }

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

ensure_flutter_in_path() {
  if cmd_exists flutter; then
    return 0
  fi
  local SNAP_FLUTTER_BIN="$HOME/snap/flutter/common/flutter/bin"
  if [ -d "$SNAP_FLUTTER_BIN" ]; then
    export PATH="$PATH:$SNAP_FLUTTER_BIN"
  fi
  if ! cmd_exists flutter; then
    die "Flutter یافت نشد. لطفاً آن‌را نصب کرده یا PATH را تنظیم کنید. مسیر پیشنهادی: $SNAP_FLUTTER_BIN"
  fi
}

is_flutter_project_dir() {
  local dir="$1"
  [ -f "$dir/pubspec.yaml" ] || return 1
  # حداقل بررسی: وجود sdk: flutter در pubspec.yaml
  if grep -qiE "sdk:\s*flutter" "$dir/pubspec.yaml"; then
    return 0
  fi
  # برخی قالب‌ها ممکن است شکل دیگری داشته باشند؛ صرف وجود pubspec را کافی بدانیم
  return 0
}

auto_detect_project_dir() {
  # اولویت: آرگومان کاربر → متغیر محیطی → مسیر متداول → جستجو در hesabixUI
  if [ -n "$USER_PROJECT" ]; then
    local p="$USER_PROJECT"
    [ -d "$p" ] || die "مسیر پروژه موجود نیست: $p"
    is_flutter_project_dir "$p" || die "pubspec.yaml معتبر در مسیر یافت نشد: $p"
    echo "$(cd "$p" && pwd)"
    return 0
  fi

  if [ -n "${FLUTTER_APP_DIR:-}" ]; then
    local p="$FLUTTER_APP_DIR"
    if [ -d "$p" ] && is_flutter_project_dir "$p"; then
      echo "$(cd "$p" && pwd)"
      return 0
    fi
  fi

  # مسیر متداول این ریپو
  local common_path="$REPO_ROOT/hesabixUI/hesabix_ui"
  if [ -d "$common_path" ] && is_flutter_project_dir "$common_path"; then
    echo "$common_path"
    return 0
  fi

  # جستجو در hesabixUI برای نزدیک‌ترین pubspec.yaml
  local search_root="$REPO_ROOT/hesabixUI"
  if [ -d "$search_root" ]; then
    # محدود به عمق 3 برای سرعت
    local found
    found=$(find "$search_root" -maxdepth 3 -type f -name pubspec.yaml 2>/dev/null | head -n 1 || true)
    if [ -n "$found" ]; then
      echo "$(cd "$(dirname "$found")" && pwd)"
      return 0
    fi
  fi

  die "پروژه فلاتر یافت نشد. لطفاً با --project مسیر را مشخص کنید."
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || die "مقدار برای --project وارد نشده است"
      USER_PROJECT="$2"; shift 2 ;;
    --mode)
      [[ $# -ge 2 ]] || die "مقدار برای --mode وارد نشده است"
      MODE="$2"; shift 2 ;;
    --build-dir)
      [[ $# -ge 2 ]] || die "مقدار برای --build-dir وارد نشده است"
      BUILD_DIR="$2"; shift 2 ;;
    --api-base-url)
      [[ $# -ge 2 ]] || die "مقدار برای --api-base-url وارد نشده است"
      API_BASE_URL="$2"; shift 2 ;;
    --clean)
      CLEAN_BUILD=true; shift ;;
    --install-deps)
      INSTALL_DEPS=true; shift ;;
    -h|--help)
      print_usage; exit 0 ;;
    *)
      warn "آرگومان ناشناخته: $1"; shift ;;
  esac
done

case "$MODE" in
  debug|profile|release) ;;
  *) die "mode نامعتبر است: $MODE (مجاز: debug|profile|release)" ;;
esac

ensure_flutter_in_path

APP_DIR="$(auto_detect_project_dir)"

if [ -z "$BUILD_DIR" ]; then
  BUILD_DIR="$DEFAULT_BUILD_DIR"
fi

# تبدیل به مسیر مطلق
BUILD_DIR="$(cd "$APP_DIR" && realpath -m "$BUILD_DIR")"

echo "ریشه ریپو: $REPO_ROOT"
echo "مسیر پروژه: $APP_DIR"
echo "حالت: $MODE"
echo "مسیر build: $BUILD_DIR"
echo "آدرس API: $API_BASE_URL"

cd "$APP_DIR"

# تنظیم mirror برای حل مشکل دسترسی به pub.dev
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

# نصب وابستگی‌ها در صورت درخواست
if [ "$INSTALL_DEPS" = true ]; then
  echo "نصب وابستگی‌ها..."
  flutter pub get
fi

# پاک کردن build directory در صورت درخواست
if [ "$CLEAN_BUILD" = true ]; then
  echo "پاک کردن build directory..."
  rm -rf "$BUILD_DIR"
fi

# تنظیم آرگومان‌های dart-define برای آدرس API
DART_DEFINE_ARGS=(--dart-define "API_BASE_URL=$API_BASE_URL")

# تعیین استراتژی PWA و بهینه‌سازی‌ها بر اساس mode
BUILD_FLAGS=()

# برای حالت release، از PWA strategy و بهینه‌سازی‌های کامل استفاده می‌کنیم
if [ "$MODE" = "release" ]; then
  BUILD_FLAGS+=(--pwa-strategy offline-first)
  BUILD_FLAGS+=(--base-href /)
  BUILD_FLAGS+=(--optimization-level 4)
  echo "Build کردن Flutter برای Web (Production) با بهینه‌سازی‌های کامل..."
  echo "  - PWA Strategy: offline-first (Service Worker فعال)"
  echo "  - Base Href: /"
  echo "  - Optimization Level: 4 (حداکثر بهینه‌سازی)"
else
  # برای debug/profile، فقط base-href را اضافه می‌کنیم
  BUILD_FLAGS+=(--base-href /)
  echo "Build کردن Flutter برای Web ($MODE) با بهینه‌سازی‌های پایه..."
  echo "  - Base Href: /"
fi

echo "دستور کامل: flutter build web --$MODE ${BUILD_FLAGS[*]} --dart-define API_BASE_URL=$API_BASE_URL"
echo ""

flutter build web --"$MODE" "${BUILD_FLAGS[@]}" "${DART_DEFINE_ARGS[@]}"

# اصلاح flutter_bootstrap.js برای استفاده از CanvasKit محلی به جای CDN
echo ""
echo "اصلاح flutter_bootstrap.js برای استفاده از CanvasKit محلی..."
FIX_SCRIPT="$APP_DIR/scripts/fix_canvaskit_local.sh"
if [ -f "$FIX_SCRIPT" ]; then
  if [ -x "$FIX_SCRIPT" ]; then
    "$FIX_SCRIPT" "$BUILD_DIR" || warn "خطا در اجرای اسکریپت اصلاح CanvasKit (ممکن است مشکلی نباشد)"
  else
    warn "اسکریپت fix_canvaskit_local.sh قابل اجرا نیست. در حال تنظیم مجوز..."
    chmod +x "$FIX_SCRIPT" && "$FIX_SCRIPT" "$BUILD_DIR" || warn "خطا در اجرای اسکریپت اصلاح CanvasKit"
  fi
else
  warn "اسکریپت fix_canvaskit_local.sh یافت نشد. در حال ایجاد..."
  mkdir -p "$APP_DIR/scripts"
  cat > "$FIX_SCRIPT" << 'EOF'
#!/usr/bin/env bash
BUILD_DIR="${1:-build/web}"
if [ -f "$BUILD_DIR/flutter_bootstrap.js" ]; then
  sed -i 's/_flutter\.loader\.load();/_flutter.loader.load({config: {canvasKitBaseUrl: "canvaskit\/", renderer: "canvaskit", useLocalCanvasKit: true}});/g' "$BUILD_DIR/flutter_bootstrap.js"
  echo "✓ flutter_bootstrap.js اصلاح شد"
fi
EOF
  chmod +x "$FIX_SCRIPT"
  "$FIX_SCRIPT" "$BUILD_DIR"
fi

# بررسی وجود فایل‌های آیکون
echo ""
echo "بررسی فایل‌های آیکون..."
ICON_DIR="$BUILD_DIR/icons"
REQUIRED_ICONS=("Icon-192.png" "Icon-512.png" "Icon-maskable-192.png" "Icon-maskable-512.png")
MISSING_ICONS=()

if [ ! -d "$ICON_DIR" ]; then
  warn "پوشه icons در build directory یافت نشد: $ICON_DIR"
  warn "ایجاد پوشه icons و کپی فایل‌ها از web/icons..."
  mkdir -p "$ICON_DIR"
  if [ -d "$APP_DIR/web/icons" ]; then
    cp -r "$APP_DIR/web/icons"/* "$ICON_DIR/" 2>/dev/null || true
  else
    warn "پوشه web/icons در پروژه یافت نشد!"
  fi
fi

for icon in "${REQUIRED_ICONS[@]}"; do
  if [ ! -f "$ICON_DIR/$icon" ]; then
    MISSING_ICONS+=("$icon")
  fi
done

if [ ${#MISSING_ICONS[@]} -gt 0 ]; then
  warn "فایل‌های آیکون زیر یافت نشدند:"
  for icon in "${MISSING_ICONS[@]}"; do
    warn "  - $icon"
  done
  warn "در حال کپی فایل‌های آیکون از web/icons..."
  if [ -d "$APP_DIR/web/icons" ]; then
    mkdir -p "$ICON_DIR"
    cp -r "$APP_DIR/web/icons"/* "$ICON_DIR/" 2>/dev/null || true
    echo "فایل‌های آیکون کپی شدند."
  else
    warn "پوشه web/icons در پروژه یافت نشد! لطفاً فایل‌های آیکون را به صورت دستی اضافه کنید."
  fi
else
  echo "✓ تمام فایل‌های آیکون موجود هستند."
fi

# بررسی وجود manifest.json
if [ ! -f "$BUILD_DIR/manifest.json" ]; then
  warn "فایل manifest.json یافت نشد! در حال کپی از web/manifest.json..."
  if [ -f "$APP_DIR/web/manifest.json" ]; then
    cp "$APP_DIR/web/manifest.json" "$BUILD_DIR/" 2>/dev/null || true
  fi
fi

echo ""
echo "=========================================="
echo "✓ Build کامل شد!"
echo "=========================================="
echo "فایل‌های build شده در مسیر زیر قرار دارند:"
echo "  $BUILD_DIR"
echo ""
if [ "$MODE" = "release" ]; then
  echo "✓ بهینه‌سازی‌های اعمال شده:"
  echo "  - حالت: Production (Release)"
  echo "  - Service Worker: فعال (offline-first strategy)"
  echo "  - Optimization Level: 4 (حداکثر بهینه‌سازی)"
  echo "  - Base Href: /"
  echo "  - API Base URL: $API_BASE_URL"
  echo ""
  echo "نکته: Service Worker به صورت خودکار فایل‌های static را cache می‌کند"
  echo "      و باعث بهبود عملکرد و امکان استفاده offline می‌شود."
else
  echo "✓ بهینه‌سازی‌های اعمال شده:"
  echo "  - حالت: $MODE"
  echo "  - Renderer: CanvasKit"
  echo "  - Base Href: /"
  echo "  - API Base URL: $API_BASE_URL"
fi
echo ""
echo "برای سرو کردن، می‌توانید از یک وب‌سرور استفاده کنید:"
echo "  cd $BUILD_DIR && python3 -m http.server 8080"
echo "یا از nginx/apache برای سرو کردن استفاده کنید."
echo ""


