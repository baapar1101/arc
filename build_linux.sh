#!/usr/bin/env bash

set -euo pipefail

# Build script for Flutter Linux Desktop in this repo.
# Creates a standalone executable for Linux.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

DEFAULT_MODE="release" # debug|profile|release
DEFAULT_BUILD_DIR="build/linux"
DEFAULT_OUTPUT_DIR="build/linux_release"

USER_PROJECT=""
MODE="$DEFAULT_MODE"
BUILD_DIR=""
OUTPUT_DIR=""
CLEAN_BUILD=false
INSTALL_DEPS=false
API_BASE_URL=""
CREATE_ARCHIVE=false

print_usage() {
  cat <<EOF
Usage: ./build_linux.sh [--project <path>] [--mode <debug|profile|release>] [--build-dir <dir>] [--output-dir <dir>] [--clean] [--install-deps] [--api-base-url <url>] [--archive] [--help]

Options:
  --project PATH     مسیر پروژه فلاتر (حاوی pubspec.yaml). در صورت عدم تعیین، به‌صورت خودکار تشخیص می‌شود.
  --mode MODE        نوع build: debug، profile یا release (پیش‌فرض: $DEFAULT_MODE).
  --build-dir DIR    مسیر build directory (پیش‌فرض: $DEFAULT_BUILD_DIR).
  --output-dir DIR   مسیر خروجی نهایی (پیش‌فرض: $DEFAULT_OUTPUT_DIR).
  --clean            پاک کردن build directory قبل از build.
  --install-deps     نصب وابستگی‌ها قبل از build.
  --api-base-url     آدرس پایه API که به برنامه به‌صورت --dart-define پاس داده می‌شود.
  --archive          ایجاد فایل tar.gz از خروجی.
  -h, --help         نمایش راهنما.

نمونه اجرا:
  ./build_linux.sh
  ./build_linux.sh --mode debug --clean
  ./build_linux.sh --project hesabixUI/hesabix_ui --archive
  ./build_linux.sh --api-base-url http://localhost:8000 --mode release --archive
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

check_linux_dependencies() {
  echo "بررسی وابستگی‌های Linux..."
  
  local missing_deps=()
  
  # بررسی وجود GTK development libraries
  if ! pkg-config --exists gtk+-3.0; then
    missing_deps+=("libgtk-3-dev")
  fi
  
  # بررسی وجود CMake
  if ! cmd_exists cmake; then
    missing_deps+=("cmake")
  fi
  
  # بررسی وجود Ninja
  if ! cmd_exists ninja; then
    missing_deps+=("ninja-build")
  fi
  
  # بررسی وجود C++ compiler
  if ! cmd_exists clang++; then
    missing_deps+=("clang")
  fi
  
  # بررسی وجود build-essential
  if ! cmd_exists gcc; then
    missing_deps+=("build-essential")
  fi
  
  if [ ${#missing_deps[@]} -gt 0 ]; then
    echo "نصب وابستگی‌های مورد نیاز..."
    echo "بسته‌های مورد نیاز: ${missing_deps[*]}"
    
    # تشخیص توزیع Linux
    if command -v apt >/dev/null 2>&1; then
      # Ubuntu/Debian
      echo "تشخیص توزیع: Ubuntu/Debian"
      sudo apt update
      sudo apt install -y "${missing_deps[@]}"
    elif command -v dnf >/dev/null 2>&1; then
      # Fedora/RHEL
      echo "تشخیص توزیع: Fedora/RHEL"
      sudo dnf install -y "${missing_deps[@]}"
    elif command -v pacman >/dev/null 2>&1; then
      # Arch Linux
      echo "تشخیص توزیع: Arch Linux"
      sudo pacman -S --noconfirm "${missing_deps[@]}"
    else
      die "توزیع Linux پشتیبانی شده یافت نشد. لطفاً وابستگی‌ها را به‌صورت دستی نصب کنید: ${missing_deps[*]}"
    fi
    
    echo "وابستگی‌ها نصب شدند."
  else
    echo "همه وابستگی‌های مورد نیاز موجود هستند."
  fi
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
    --output-dir)
      [[ $# -ge 2 ]] || die "مقدار برای --output-dir وارد نشده است"
      OUTPUT_DIR="$2"; shift 2 ;;
    --clean)
      CLEAN_BUILD=true; shift ;;
    --install-deps)
      INSTALL_DEPS=true; shift ;;
    --api-base-url)
      [[ $# -ge 2 ]] || die "مقدار برای --api-base-url وارد نشده است"
      API_BASE_URL="$2"; shift 2 ;;
    --archive)
      CREATE_ARCHIVE=true; shift ;;
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
check_linux_dependencies

APP_DIR="$(auto_detect_project_dir)"

if [ -z "$BUILD_DIR" ]; then
  BUILD_DIR="$DEFAULT_BUILD_DIR"
fi

if [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
fi

# تبدیل به مسیر مطلق
BUILD_DIR="$(cd "$APP_DIR" && realpath -m "$BUILD_DIR")"
OUTPUT_DIR="$(cd "$APP_DIR" && realpath -m "$OUTPUT_DIR")"

echo "ریشه ریپو: $REPO_ROOT"
echo "مسیر پروژه: $APP_DIR"
echo "حالت: $MODE"
echo "مسیر build: $BUILD_DIR"
echo "مسیر خروجی: $OUTPUT_DIR"

cd "$APP_DIR"

# تنظیم mirror برای حل مشکل دسترسی به pub.dev
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

# تنظیم C++ compiler flags برای حل مشکل deprecated warnings
export CXXFLAGS="-Wno-deprecated-literal-operator"
export CFLAGS="-Wno-deprecated-literal-operator"

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

# تنظیم آرگومان‌های dart-define
DART_DEFINE_ARGS=()
if [ -n "$API_BASE_URL" ]; then
  DART_DEFINE_ARGS+=(--dart-define "API_BASE_URL=$API_BASE_URL")
fi

# Build کردن Flutter برای Linux
echo "Build کردن Flutter برای Linux..."
echo "دستور: flutter build linux --$MODE ${DART_DEFINE_ARGS[*]:-}"

flutter build linux --"$MODE" ${DART_DEFINE_ARGS[@]:-}

# کپی کردن فایل‌های build شده به مسیر خروجی
echo "کپی کردن فایل‌های build شده..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# کپی کردن bundle از build directory
if [ -d "$BUILD_DIR/x64/$MODE/bundle" ]; then
  cp -r "$BUILD_DIR/x64/$MODE/bundle"/* "$OUTPUT_DIR/"
  echo "فایل‌های build شده در مسیر زیر کپی شدند: $OUTPUT_DIR"
else
  die "مسیر bundle یافت نشد: $BUILD_DIR/x64/$MODE/bundle"
fi

# ایجاد فایل اجرایی
EXECUTABLE_NAME="hesabix_ui"
if [ -f "$OUTPUT_DIR/$EXECUTABLE_NAME" ]; then
  chmod +x "$OUTPUT_DIR/$EXECUTABLE_NAME"
  echo "فایل اجرایی: $OUTPUT_DIR/$EXECUTABLE_NAME"
else
  warn "فایل اجرایی یافت نشد: $OUTPUT_DIR/$EXECUTABLE_NAME"
fi

# ایجاد archive در صورت درخواست
if [ "$CREATE_ARCHIVE" = true ]; then
  ARCHIVE_NAME="hesabix_ui_linux_${MODE}_$(date +%Y%m%d_%H%M%S).tar.gz"
  ARCHIVE_PATH="$(dirname "$OUTPUT_DIR")/$ARCHIVE_NAME"
  
  echo "ایجاد archive: $ARCHIVE_PATH"
  cd "$(dirname "$OUTPUT_DIR")"
  tar -czf "$ARCHIVE_PATH" "$(basename "$OUTPUT_DIR")"
  
  echo "Archive ایجاد شد: $ARCHIVE_PATH"
  echo "برای اجرا: tar -xzf $ARCHIVE_NAME && cd $(basename "$OUTPUT_DIR") && ./$EXECUTABLE_NAME"
fi

echo "Build کامل شد!"
echo "برای اجرا: cd $OUTPUT_DIR && ./$EXECUTABLE_NAME"
