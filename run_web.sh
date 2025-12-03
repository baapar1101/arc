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
  --project PATH   Flutter project path (contains pubspec.yaml). If not specified, will be auto-detected.
  --host HOST      Host for web server (default: $DEFAULT_HOST).
  --port PORT      Web server port. If not specified, nearest free port from $DEFAULT_PORT will be selected.
  --mode MODE      Run type: release or debug (default: $DEFAULT_MODE).
  --api-base-url  API base URL passed to app as --dart-define.
  -h, --help       Show help.

Usage examples:
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
    die "Flutter not found. Please install it or configure PATH. Suggested path: $SNAP_FLUTTER_BIN"
  fi
}

is_flutter_project_dir() {
  local dir="$1"
  [ -f "$dir/pubspec.yaml" ] || return 1
  # Minimum check: presence of sdk: flutter in pubspec.yaml
  if grep -qiE "sdk:\s*flutter" "$dir/pubspec.yaml"; then
    return 0
  fi
  # Some templates may have different format; just having pubspec is enough
  return 0
}

auto_detect_project_dir() {
  # Priority: user argument → environment variable → common path → search in hesabixUI
  if [ -n "$USER_PROJECT" ]; then
    local p="$USER_PROJECT"
    [ -d "$p" ] || die "Project path does not exist: $p"
    is_flutter_project_dir "$p" || die "Valid pubspec.yaml not found in path: $p"
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

  # Common path in this repo
  local common_path="$REPO_ROOT/hesabixUI/hesabix_ui"
  if [ -d "$common_path" ] && is_flutter_project_dir "$common_path"; then
    echo "$common_path"
    return 0
  fi

  # Search in hesabixUI for nearest pubspec.yaml
  local search_root="$REPO_ROOT/hesabixUI"
  if [ -d "$search_root" ]; then
    # Limited to depth 3 for speed
    local found
    found=$(find "$search_root" -maxdepth 3 -type f -name pubspec.yaml 2>/dev/null | head -n 1 || true)
    if [ -n "$found" ]; then
      echo "$(cd "$(dirname "$found")" && pwd)"
      return 0
    fi
  fi

  die "Flutter project not found. Please specify path with --project."
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
  die "Free port between $start and $end not found."
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || die "Value for --project not provided"
      USER_PROJECT="$2"; shift 2 ;;
    --host)
      [[ $# -ge 2 ]] || die "Value for --host not provided"
      HOST="$2"; shift 2 ;;
    --port)
      [[ $# -ge 2 ]] || die "Value for --port not provided"
      PORT="$2"; shift 2 ;;
    --mode)
      [[ $# -ge 2 ]] || die "Value for --mode not provided"
      MODE="$2"; shift 2 ;;
    --api-base-url)
      [[ $# -ge 2 ]] || die "Value for --api-base-url not provided"
      API_BASE_URL="$2"; shift 2 ;;
    -h|--help)
      print_usage; exit 0 ;;
    *)
      warn "Unknown argument: $1"; shift ;;
  esac
done

case "$MODE" in
  release|debug) ;;
  *) die "Invalid mode: $MODE (allowed: release|debug)" ;;
esac

ensure_flutter_in_path

APP_DIR="$(auto_detect_project_dir)"

if [ -z "${PORT:-}" ]; then
  PORT="$(find_free_port "$DEFAULT_PORT")"
else
  if port_in_use "$PORT"; then
    die "Port $PORT is in use. Choose another port or run without --port."
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

echo "Repo root: $REPO_ROOT"
echo "Project path: $APP_DIR"
echo "Host: $HOST  | Port: $PORT  | Mode: $MODE"
echo "Command: flutter run -d web-server $MODE_FLAG --web-port $PORT --web-hostname $HOST ${DART_DEFINE_ARGS[*]:-}"

cd "$APP_DIR"

# Configure mirror to resolve pub.dev access issues
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

exec flutter run -d web-server $MODE_FLAG --web-port "$PORT" --web-hostname "$HOST" ${DART_DEFINE_ARGS[@]:-}


