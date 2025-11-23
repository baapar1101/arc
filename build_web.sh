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

# Build کردن Flutter برای Web
echo "Build کردن Flutter برای Web..."
echo "دستور: flutter build web --$MODE --dart-define API_BASE_URL=$API_BASE_URL"

flutter build web --"$MODE" "${DART_DEFINE_ARGS[@]}"

echo "Build کامل شد!"
echo "فایل‌های build شده در مسیر زیر قرار دارند: $BUILD_DIR"
echo "برای سرو کردن، می‌توانید از یک وب‌سرور استفاده کنید:"
echo "  cd $BUILD_DIR && python3 -m http.server 8080"
echo "یا از nginx/apache برای سرو کردن استفاده کنید."


