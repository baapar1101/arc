#!/usr/bin/env bash

set -euo pipefail

# Quick launcher for Flutter Web in this repo.
# Smartly detects Flutter binary and the app directory.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

DEFAULT_HOST="0.0.0.0"
DEFAULT_PORT=8080
DEFAULT_MODE="release" # release|debug

USER_PROJECT=""
HOST="$DEFAULT_HOST"
PORT=""
MODE="$DEFAULT_MODE"
API_BASE_URL=""

print_usage() {
  cat <<EOF
Usage: ./run_web.sh [--project <path>] [--host <host>] [--port <port>] [--mode <release|debug>] [--api-base-url <url>] [--help]

Options:
  --project PATH   مسیر پروژه فلاتر (حاوی pubspec.yaml). در صورت عدم تعیین، به‌صورت خودکار تشخیص می‌شود.
  --host HOST      میزبان برای سرو وب‌سرور (پیش‌فرض: $DEFAULT_HOST).
  --port PORT      پورت وب‌سرور. اگر تعیین نشود، نزدیک‌ترین پورت آزاد از $DEFAULT_PORT انتخاب می‌شود.
  --mode MODE      نوع اجرا: release یا debug (پیش‌فرض: $DEFAULT_MODE).
  --api-base-url  آدرس پایه API که به برنامه به‌صورت --dart-define پاس داده می‌شود.
  -h, --help       نمایش راهنما.

نمونه اجرا:
  ./run_web.sh
  ./run_web.sh --port 8081 --mode debug
  ./run_web.sh --project hesabixUI/hesabix_ui
  ./run_web.sh --api-base-url http://localhost:8000
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

port_in_use() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -tuln | grep -q ":[${p}]\>"
  else
    netstat -tuln 2>/dev/null | grep -q ":[${p}]\>" || return 1
  fi
}

find_free_port() {
  local start=${1:-$DEFAULT_PORT}
  local end=$((start + 50))
  local p
  for ((p=start; p<=end; p++)); do
    if ! port_in_use "$p"; then
      echo "$p"
      return 0
    fi
  done
  die "پورت آزاد بین $start و $end یافت نشد."
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || die "مقدار برای --project وارد نشده است"
      USER_PROJECT="$2"; shift 2 ;;
    --host)
      [[ $# -ge 2 ]] || die "مقدار برای --host وارد نشده است"
      HOST="$2"; shift 2 ;;
    --port)
      [[ $# -ge 2 ]] || die "مقدار برای --port وارد نشده است"
      PORT="$2"; shift 2 ;;
    --mode)
      [[ $# -ge 2 ]] || die "مقدار برای --mode وارد نشده است"
      MODE="$2"; shift 2 ;;
    --api-base-url)
      [[ $# -ge 2 ]] || die "مقدار برای --api-base-url وارد نشده است"
      API_BASE_URL="$2"; shift 2 ;;
    -h|--help)
      print_usage; exit 0 ;;
    *)
      warn "آرگومان ناشناخته: $1"; shift ;;
  esac
done

case "$MODE" in
  release|debug) ;;
  *) die "mode نامعتبر است: $MODE (مجاز: release|debug)" ;;
esac

ensure_flutter_in_path

APP_DIR="$(auto_detect_project_dir)"

if [ -z "${PORT:-}" ]; then
  PORT="$(find_free_port "$DEFAULT_PORT")"
else
  if port_in_use "$PORT"; then
    die "پورت $PORT در حال استفاده است. پورت دیگری انتخاب کنید یا بدون --port اجرا کنید."
  fi
fi

MODE_FLAG=""
if [ "$MODE" = "release" ]; then
  MODE_FLAG="--release"
fi

DART_DEFINE_ARGS=()
if [ -n "$API_BASE_URL" ]; then
  DART_DEFINE_ARGS+=(--dart-define "API_BASE_URL=$API_BASE_URL")
fi

echo "ریشه ریپو: $REPO_ROOT"
echo "مسیر پروژه: $APP_DIR"
echo "میزبان: $HOST  | پورت: $PORT  | حالت: $MODE"
echo "دستور: flutter run -d web-server $MODE_FLAG --web-port $PORT --web-hostname $HOST ${DART_DEFINE_ARGS[*]:-}"

cd "$APP_DIR"

# تنظیم mirror برای حل مشکل دسترسی به pub.dev
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

exec flutter run -d web-server $MODE_FLAG --web-port "$PORT" --web-hostname "$HOST" ${DART_DEFINE_ARGS[@]:-}


