#!/usr/bin/env bash

set -euo pipefail

# Development script: runs backend (Python API) and frontend (Flutter Web) together
# with live logs and hot reload for both.
#
# - Backend: uvicorn with --reload (Python hot reload)
# - Frontend: flutter run -d web-server in debug mode (Flutter hot reload)
# - Both outputs appear in the same terminal. Ctrl+C stops both.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
API_DIR="$REPO_ROOT/hesabixAPI"
DEFAULT_API_PORT=8000
DEFAULT_WEB_PORT=8080
DEFAULT_HOST="127.0.0.1"
DEFAULT_MODE="debug"
DEFAULT_API_BASE_URL="http://localhost:8000"

USER_PROJECT=""
API_PORT="$DEFAULT_API_PORT"
WEB_PORT="$DEFAULT_WEB_PORT"
HOST="$DEFAULT_HOST"
MODE="$DEFAULT_MODE"
API_BASE_URL="$DEFAULT_API_BASE_URL"
SKIP_SETUP=false

warn() { echo "[warn] $*" >&2; }
die() { echo "[error] $*" >&2; exit 1; }
info() { echo "[dev] $*"; }

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

ensure_flutter_in_path() {
  if cmd_exists flutter; then
    return 0
  fi
  for candidate in "/opt/flutter/bin" "/snap/bin" "$HOME/snap/flutter/current/flutter/bin" "$HOME/snap/flutter/common/flutter/bin"; do
    if [ -x "${candidate}/flutter" ]; then
      export PATH="${candidate}:$PATH"
      return 0
    fi
  done
  die "Flutter not found. Please install it or configure PATH."
}

is_flutter_project_dir() {
  local dir="$1"
  [ -f "$dir/pubspec.yaml" ] || return 1
  grep -qiE "sdk:\s*flutter" "$dir/pubspec.yaml" 2>/dev/null || true
  return 0
}

auto_detect_project_dir() {
  if [ -n "$USER_PROJECT" ]; then
    [ -d "$USER_PROJECT" ] || die "Project path does not exist: $USER_PROJECT"
    is_flutter_project_dir "$USER_PROJECT" || die "Valid pubspec.yaml not found: $USER_PROJECT"
    echo "$(cd "$USER_PROJECT" && pwd)"
    return 0
  fi
  if [ -n "${FLUTTER_APP_DIR:-}" ] && [ -d "$FLUTTER_APP_DIR" ] && is_flutter_project_dir "$FLUTTER_APP_DIR"; then
    echo "$(cd "$FLUTTER_APP_DIR" && pwd)"
    return 0
  fi
  local common_path="$REPO_ROOT/hesabixUI/hesabix_ui"
  if [ -d "$common_path" ] && is_flutter_project_dir "$common_path"; then
    echo "$common_path"
    return 0
  fi
  local found
  found=$(find "$REPO_ROOT/hesabixUI" -maxdepth 3 -type f -name pubspec.yaml 2>/dev/null | head -n 1 || true)
  if [ -n "$found" ]; then
    echo "$(cd "$(dirname "$found")" && pwd)"
    return 0
  fi
  die "Flutter project not found. Use --project PATH."
}

port_in_use() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -tuln 2>/dev/null | grep -q ":[${p}]\>" || return 1
  else
    netstat -tuln 2>/dev/null | grep -q ":[${p}]\>" || return 1
  fi
}

find_free_port() {
  local start=${1:-8080}
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

print_usage() {
  cat <<EOF
Usage: ./dev.sh [options]

Starts backend (Python API) and frontend (Flutter Web) for development with
live logs and hot reload. Both run in the same terminal; Ctrl+C stops both.

Options:
  --project PATH     Flutter project path (default: auto-detect hesabixUI/hesabix_ui).
  --api-port PORT    API port (default: $DEFAULT_API_PORT).
  --web-port PORT    Web server port (default: auto-detect from $DEFAULT_WEB_PORT).
  --host HOST        Web server hostname (default: $DEFAULT_HOST).
  --mode MODE        Flutter mode: debug or release (default: $DEFAULT_MODE).
  --api-base-url URL API base URL for Flutter (default: $DEFAULT_API_BASE_URL).
  --skip-setup       Skip venv/pub install (use if already set up).
  -h, --help         Show this help.

Examples:
  ./dev.sh
  ./dev.sh --mode debug --web-port 8081
  ./dev.sh --api-base-url http://localhost:8000
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || die "Value for --project required"
      USER_PROJECT="$2"; shift 2 ;;
    --api-port)
      [[ $# -ge 2 ]] || die "Value for --api-port required"
      API_PORT="$2"; shift 2 ;;
    --web-port)
      [[ $# -ge 2 ]] || die "Value for --web-port required"
      WEB_PORT="$2"; shift 2 ;;
    --host)
      [[ $# -ge 2 ]] || die "Value for --host required"
      HOST="$2"; shift 2 ;;
    --mode)
      [[ $# -ge 2 ]] || die "Value for --mode required"
      MODE="$2"; shift 2 ;;
    --api-base-url)
      [[ $# -ge 2 ]] || die "Value for --api-base-url required"
      API_BASE_URL="$2"; shift 2 ;;
    --skip-setup)
      SKIP_SETUP=true; shift ;;
    -h|--help)
      print_usage; exit 0 ;;
    *)
      warn "Unknown option: $1"; shift ;;
  esac
done

case "$MODE" in
  debug|release) ;;
  *) die "Invalid mode: $MODE (allowed: debug, release)" ;;
esac

# --- Setup ---
info "Preparing development environment..."

if [ "$SKIP_SETUP" != true ]; then
  # Backend setup
  if [ ! -d "$API_DIR" ]; then
    die "API directory not found: $API_DIR"
  fi
  info "Setting up backend..."
  cd "$API_DIR"
  if [ ! -d .venv ]; then
    python3 -m venv .venv
  fi
  source .venv/bin/activate
  python -m pip install --upgrade pip -q
  pip install --no-input -e .[dev] -q
  if [ ! -f .env ]; then
    cp -n env.example .env 2>/dev/null || true
  fi
  deactivate 2>/dev/null || true
  cd "$REPO_ROOT"
fi

ensure_flutter_in_path
APP_DIR="$(auto_detect_project_dir)"

if [ -z "${WEB_PORT:-}" ] || [ "$WEB_PORT" = "$DEFAULT_WEB_PORT" ]; then
  WEB_PORT="$(find_free_port "$DEFAULT_WEB_PORT")"
elif port_in_use "$WEB_PORT"; then
  die "Web port $WEB_PORT is in use."
fi

if port_in_use "$API_PORT"; then
  die "API port $API_PORT is in use. Stop the existing process or use --api-port."
fi

# --- Cleanup on exit ---
API_PID=""
cleanup() {
  if [ -n "$API_PID" ] && kill -0 "$API_PID" 2>/dev/null; then
    info "Stopping API (PID $API_PID)..."
    kill "$API_PID" 2>/dev/null || true
    wait "$API_PID" 2>/dev/null || true
  fi
  exit 0
}
trap cleanup EXIT INT TERM

# --- Start API in background ---
info "Starting API on port $API_PORT (uvicorn --reload)..."
(
  cd "$API_DIR"
  source .venv/bin/activate
  exec uvicorn app.main:app --reload --host 0.0.0.0 --port "$API_PORT"
) &
API_PID=$!

# Give API a moment to bind
sleep 2
if ! kill -0 "$API_PID" 2>/dev/null; then
  die "API failed to start. Check the output above."
fi

# --- Start Flutter in foreground ---
# Use API_BASE_URL; if default, ensure it matches actual API_PORT
FLUTTER_API_URL="$API_BASE_URL"
if [ "$API_BASE_URL" = "$DEFAULT_API_BASE_URL" ] && [ "$API_PORT" != "$DEFAULT_API_PORT" ]; then
  FLUTTER_API_URL="http://localhost:$API_PORT"
fi

MODE_FLAG=""
[ "$MODE" = "release" ] && MODE_FLAG="--release"

DART_DEFINE_ARGS=()
[ -n "$FLUTTER_API_URL" ] && DART_DEFINE_ARGS+=(--dart-define "API_BASE_URL=$FLUTTER_API_URL")

AVAILABLE_CORES=$(nproc 2>/dev/null || echo 4)
BUILD_WORKERS=$((AVAILABLE_CORES * 80 / 100))
[ "$BUILD_WORKERS" -lt 1 ] && BUILD_WORKERS=1
[ "$BUILD_WORKERS" -gt 16 ] && BUILD_WORKERS=16

export PUB_HOSTED_URL="https://f.mirror.hesabix.ir/pub"
export FLUTTER_STORAGE_BASE_URL="https://f.mirror.hesabix.ir/gcs"
export DART_COMPILE_JS_WORKERS="$BUILD_WORKERS"
[ "$MODE" = "debug" ] && export DART_VM_OPTIONS="--enable-asserts"

info "Starting Flutter Web on $HOST:$WEB_PORT (mode=$MODE, hot reload enabled)..."
info "API: http://localhost:$API_PORT  |  App: http://$HOST:$WEB_PORT"
info "Press Ctrl+C to stop both."
echo ""

cd "$APP_DIR"
exec flutter run -d web-server $MODE_FLAG --web-port "$WEB_PORT" --web-hostname "$HOST" "${DART_DEFINE_ARGS[@]:-}"
