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
USE_OFFLINE_CACHE=false

print_usage() {
  cat <<EOF
Usage: ./build_web.sh [--project <path>] [--mode <debug|profile|release>] [--build-dir <dir>] [--api-base-url <url>] [--clean] [--install-deps] [--offline] [--help]

Options:
  --project PATH     Flutter project path (contains pubspec.yaml). If not specified, will be auto-detected.
  --mode MODE        Build type: debug, profile, or release (default: $DEFAULT_MODE).
  --build-dir DIR    Build directory path (default: $DEFAULT_BUILD_DIR).
  --api-base-url     API base URL (default: $DEFAULT_API_BASE_URL).
  --clean            Clean build directory before building.
  --install-deps     Install dependencies before building.
  --offline          Use offline cache for pub dependencies (no network access).
  -h, --help         Show help.

Usage examples:
  ./build_web.sh
  ./build_web.sh --mode debug --clean
  ./build_web.sh --project hesabixUI/hesabix_ui
  ./build_web.sh --api-base-url https://hsxn.hesabix.ir
  ./build_web.sh --offline
EOF
}

warn() { echo "[warn] $*" >&2; }
die() { echo "[error] $*" >&2; exit 1; }

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

ensure_flutter_in_path() {
  if cmd_exists flutter; then
    return 0
  fi
  # Check common install locations (deploy.sh may install to /opt/flutter)
  for candidate in "/opt/flutter/bin" "/snap/bin" "$HOME/snap/flutter/current/flutter/bin" "$HOME/snap/flutter/common/flutter/bin"; do
    if [ -x "${candidate}/flutter" ]; then
      export PATH="${candidate}:$PATH"
      return 0
    fi
  done
  if ! cmd_exists flutter; then
    die "Flutter not found. Please install it or configure PATH. Suggested: sudo snap install flutter --classic, or deploy.sh will install to /opt/flutter."
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

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || die "Value for --project not provided"
      USER_PROJECT="$2"; shift 2 ;;
    --mode)
      [[ $# -ge 2 ]] || die "Value for --mode not provided"
      MODE="$2"; shift 2 ;;
    --build-dir)
      [[ $# -ge 2 ]] || die "Value for --build-dir not provided"
      BUILD_DIR="$2"; shift 2 ;;
    --api-base-url)
      [[ $# -ge 2 ]] || die "Value for --api-base-url not provided"
      API_BASE_URL="$2"; shift 2 ;;
    --clean)
      CLEAN_BUILD=true; shift ;;
    --install-deps)
      INSTALL_DEPS=true; shift ;;
    --offline)
      USE_OFFLINE_CACHE=true; shift ;;
    -h|--help)
      print_usage; exit 0 ;;
    *)
      warn "Unknown argument: $1"; shift ;;
  esac
done

case "$MODE" in
  debug|profile|release) ;;
  *) die "Invalid mode: $MODE (allowed: debug|profile|release)" ;;
esac

ensure_flutter_in_path

APP_DIR="$(auto_detect_project_dir)"

if [ -z "$BUILD_DIR" ]; then
  BUILD_DIR="$DEFAULT_BUILD_DIR"
fi

# Convert to absolute path
BUILD_DIR="$(cd "$APP_DIR" && realpath -m "$BUILD_DIR")"

echo "Repo root: $REPO_ROOT"
echo "Project path: $APP_DIR"
echo "Mode: $MODE"
echo "Build path: $BUILD_DIR"
echo "API URL: $API_BASE_URL"

cd "$APP_DIR"

# Function to check accessibility of a URL (with SSL issues support)
check_url_accessibility() {
  local url="$1"
  local timeout="${2:-5}"
  # Try with SSL verification
  if curl -s --connect-timeout "$timeout" --max-time "$timeout" -I "$url" >/dev/null 2>&1; then
    return 0
  fi
  # If SSL fails, try without verification (for internal mirrors only)
  if curl -k -s --connect-timeout "$timeout" --max-time "$timeout" -I "$url" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Function to find best available mirror
# Priority: Chinese mirrors → Official → Other mirrors
find_available_mirror() {
  local mirrors=(
    # Hesabix internal mirror (Iran) — if available, prefer it
    "https://shell.hesabix.ir/dart-pub|https://shell.hesabix.ir/flutter"
    # Chinese mirrors (for servers inside China or restricted networks)
    "https://mirrors.tuna.tsinghua.edu.cn/dart-pub|https://mirrors.tuna.tsinghua.edu.cn/flutter"
    "https://mirror.sjtu.edu.cn/dart-pub|https://mirror.sjtu.edu.cn"
    "https://pub.flutter-io.cn|https://storage.flutter-io.cn"
    # Official mirror (if DNS works)
    "https://pub.dev|https://storage.googleapis.com"
    # Other alternative mirrors
    "https://mirrors.cloud.tencent.com/dart-pub|https://mirrors.cloud.tencent.com/flutter"
  )
  
  echo "Checking ${#mirrors[@]} different mirrors..." >&2
  
  for mirror_pair in "${mirrors[@]}"; do
    IFS='|' read -r pub_url storage_url <<< "$mirror_pair"
    echo "  Checking: $pub_url" >&2
    if check_url_accessibility "$pub_url" 5; then
      echo "  ✓ Available!" >&2
      echo "$pub_url|$storage_url"
      return 0
    else
      echo "  ✗ Not available" >&2
    fi
  done
  
  return 1
}

# Configure Flutter mirror
# Priority: environment variables → find available mirror → default
if [ -z "${PUB_HOSTED_URL:-}" ] || [ -z "${FLUTTER_STORAGE_BASE_URL:-}" ]; then
  echo "Checking Flutter mirror accessibility..."
  
  if available_mirror=$(find_available_mirror); then
    IFS='|' read -r pub_url storage_url <<< "$available_mirror"
    export PUB_HOSTED_URL="$pub_url"
    export FLUTTER_STORAGE_BASE_URL="$storage_url"
    echo "✓ Available mirror found: $PUB_HOSTED_URL"
  else
    # If no mirror is reachable, continue with offline cache mode.
    # Do NOT stop build here; later dependency step will run `flutter pub get --offline`.
    USE_OFFLINE_CACHE=true
    warn ""
    warn "=========================================="
    warn "⚠ Warning: No accessible mirror found!"
    warn "=========================================="
    warn ""
    warn "All mirrors checked and not available:"
    warn "  - mirrors.tuna.tsinghua.edu.cn"
    warn "  - mirror.sjtu.edu.cn"
    warn "  - pub.flutter-io.cn"
    warn "  - pub.dev"
    warn "  - mirrors.cloud.tencent.com"
    warn ""
    warn "No mirror selected. Will try offline cache mode for pub dependencies."
    warn ""
    warn "Suggested solutions:"
    warn "  1. Check internet connection: ping 8.8.8.8"
    warn "  2. Check DNS: nslookup pub.dev"
    warn "  3. Configure DNS: cd /var/www/ark && ./fix_dns.sh"
    warn "  4. Manually use mirror:"
    warn "     export PUB_HOSTED_URL='https://mirrors.tuna.tsinghua.edu.cn/dart-pub'"
    warn "     export FLUTTER_STORAGE_BASE_URL='https://mirrors.tuna.tsinghua.edu.cn/flutter'"
    warn "  5. Check firewall or proxy"
    warn ""
    warn "For complete guide, refer to TROUBLESHOOTING_DNS.md file."
    warn ""
  fi
fi

echo "Using Pub Hosted URL: $PUB_HOSTED_URL"
echo "Using Flutter Storage URL: $FLUTTER_STORAGE_BASE_URL"
if [ "$USE_OFFLINE_CACHE" = true ]; then
  echo "Dependency strategy: offline cache (flutter pub get --offline)"
fi

# Install dependencies if requested
if [ "$INSTALL_DEPS" = true ]; then
  echo "Installing dependencies..."
  if ! flutter pub get; then
    if [ "$USE_OFFLINE_CACHE" = true ]; then
      warn "Online dependency install failed/no mirror. Trying offline cache..."
      if ! flutter pub get --offline; then
        die "Dependency install failed in offline mode too. Populate cache first on a machine with internet (copy PUB_CACHE/.pub-cache), then retry."
      fi
    else
      die "Flutter/Dart step failed. If the process was 'Killed', the server likely ran out of memory (OOM). Add swap or use a machine with more RAM, then re-run."
    fi
  fi
elif [ ! -d "$APP_DIR/.dart_tool" ] || [ ! -f "$APP_DIR/pubspec.lock" ]; then
  echo "Dependencies not installed. Installing..."
  if ! flutter pub get; then
    if [ "$USE_OFFLINE_CACHE" = true ]; then
      warn "Online dependency install failed/no mirror. Trying offline cache..."
      if ! flutter pub get --offline; then
        warn "Offline cache install failed too. Build may fail unless dependency cache is preloaded."
        warn "  cd $APP_DIR && flutter pub get --offline"
      fi
    else
      warn "Flutter/Dart step failed (if 'Killed', increase RAM or add swap). Trying to continue..."
      warn "  cd $APP_DIR && flutter pub get"
    fi
  fi
fi

# Clean build directory if requested
if [ "$CLEAN_BUILD" = true ]; then
  echo "Cleaning build directory..."
  rm -rf "$BUILD_DIR"
fi

# Configure dart-define arguments for API URL
DART_DEFINE_ARGS=(--dart-define "API_BASE_URL=$API_BASE_URL")

# Determine PWA strategy and optimizations based on mode
BUILD_FLAGS=()

# Memory check first (used for optimization level and workers)
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/ {print $2}')
AVAILABLE_RAM_MB=$(free -m | awk '/^Mem:/ {print $7}')
LOW_RAM=0
[ "$TOTAL_RAM_MB" -lt 2500 ] && LOW_RAM=1

# For release mode, use PWA strategy and full optimizations
if [ "$MODE" = "release" ]; then
  BUILD_FLAGS+=(--pwa-strategy offline-first)
  BUILD_FLAGS+=(--base-href /)
  # On low-RAM use -O1 to avoid dart2js OOM (exit code -9). Otherwise -O2.
  if [ "$LOW_RAM" -eq 1 ]; then
    BUILD_FLAGS+=(--optimization-level 1)
    echo "Building Flutter for Web (Production) with low-memory settings..."
    echo "  - PWA Strategy: offline-first (Service Worker enabled)"
    echo "  - Base Href: /"
    echo "  - Optimization Level: 1 (reduces memory use on <2.5GB RAM)"
  else
    BUILD_FLAGS+=(--optimization-level 2)
    echo "Building Flutter for Web (Production) with full optimizations..."
    echo "  - PWA Strategy: offline-first (Service Worker enabled)"
    echo "  - Base Href: /"
    echo "  - Optimization Level: 2 (balanced optimization)"
  fi
else
  BUILD_FLAGS+=(--base-href /)
  echo "Building Flutter for Web ($MODE) with basic optimizations..."
  echo "  - Base Href: /"
fi

echo "Full command: flutter build web --$MODE ${BUILD_FLAGS[*]} --dart-define API_BASE_URL=$API_BASE_URL"
echo ""

# Configure CPU workers: on low-RAM use 1 worker only to avoid OOM
AVAILABLE_CORES=$(nproc)
if [ "$LOW_RAM" -eq 1 ]; then
  BUILD_WORKERS=1
  echo "CPU: 1 worker (low-memory mode to avoid OOM)"
else
  BUILD_WORKERS=$((AVAILABLE_CORES * 80 / 100))
  [ "$BUILD_WORKERS" -lt 1 ] && BUILD_WORKERS=1
  [ "$BUILD_WORKERS" -gt 16 ] && BUILD_WORKERS=16
  echo "CPU Optimization: cores=$AVAILABLE_CORES, workers=$BUILD_WORKERS"
fi
echo ""

# Heap for dart2js: on low-RAM cap at 512MB so process is not OOM-killed
if [ "$LOW_RAM" -eq 1 ]; then
  HEAP_SIZE_MB=$((AVAILABLE_RAM_MB * 45 / 100))
  [ "$HEAP_SIZE_MB" -lt 256 ] && HEAP_SIZE_MB=256
  [ "$HEAP_SIZE_MB" -gt 512 ] && HEAP_SIZE_MB=512
else
  HEAP_SIZE_MB=$((AVAILABLE_RAM_MB * 65 / 100))
  [ "$HEAP_SIZE_MB" -lt 1024 ] && HEAP_SIZE_MB=1024
  [ "$HEAP_SIZE_MB" -gt 16384 ] && HEAP_SIZE_MB=16384
fi

echo "Memory: Total=${TOTAL_RAM_MB}MB Available=${AVAILABLE_RAM_MB}MB Dart heap=${HEAP_SIZE_MB}MB"
echo ""

export DART_VM_OPTIONS="--old-gen-heap-size=$HEAP_SIZE_MB"
export DART_COMPILE_JS_WORKERS="$BUILD_WORKERS"

# Check available memory details
echo "System Memory Status:"
free -h | head -2
echo ""

# Run build with memory settings and parallel compilation
# Flutter always outputs to build/web inside the project; copy to BUILD_DIR if different
FLUTTER_OUTPUT="$APP_DIR/build/web"
if ! flutter build web --"$MODE" "${BUILD_FLAGS[@]}" "${DART_DEFINE_ARGS[@]}"; then
  die "flutter build web failed. If you saw 'exit code -9' or 'Killed', the server ran out of memory (OOM). Add more swap or use a machine with more RAM, then re-run."
fi
# Copy to custom build-dir when user specified a path other than default
if [ "$BUILD_DIR" != "$FLUTTER_OUTPUT" ]; then
  echo "Copying build output to $BUILD_DIR ..."
  mkdir -p "$BUILD_DIR"
  cp -r "$FLUTTER_OUTPUT"/* "$BUILD_DIR/" || die "Failed to copy build output to $BUILD_DIR"
fi
if [ ! -f "$BUILD_DIR/index.html" ]; then
  die "flutter build web did not produce index.html. Flutter SDK may be broken (e.g. Dart SDK download failed). Try: rm -rf /opt/flutter && re-run deploy with mirror set."
fi

# Fix flutter_bootstrap.js to use local CanvasKit instead of CDN
echo ""
echo "Fixing flutter_bootstrap.js to use local CanvasKit..."
FIX_SCRIPT="$APP_DIR/scripts/fix_canvaskit_local.sh"
if [ -f "$FIX_SCRIPT" ]; then
  if [ -x "$FIX_SCRIPT" ]; then
    "$FIX_SCRIPT" "$BUILD_DIR" || warn "Error running CanvasKit fix script (may not be a problem)"
  else
    warn "fix_canvaskit_local.sh script is not executable. Setting permissions..."
    chmod +x "$FIX_SCRIPT" && "$FIX_SCRIPT" "$BUILD_DIR" || warn "Error running CanvasKit fix script"
  fi
else
  warn "fix_canvaskit_local.sh script not found. Creating..."
  mkdir -p "$APP_DIR/scripts"
  cat > "$FIX_SCRIPT" << 'EOF'
#!/usr/bin/env bash
BUILD_DIR="${1:-build/web}"
if [ -f "$BUILD_DIR/flutter_bootstrap.js" ]; then
  sed -i 's/_flutter\.loader\.load();/_flutter.loader.load({config: {canvasKitBaseUrl: "canvaskit\/", renderer: "canvaskit", useLocalCanvasKit: true}});/g' "$BUILD_DIR/flutter_bootstrap.js"
  echo "✓ flutter_bootstrap.js fixed"
fi
EOF
  chmod +x "$FIX_SCRIPT"
  "$FIX_SCRIPT" "$BUILD_DIR"
fi

# Check icon files
echo ""
echo "Checking icon files..."
ICON_DIR="$BUILD_DIR/icons"
REQUIRED_ICONS=("Icon-192.png" "Icon-512.png" "Icon-maskable-192.png" "Icon-maskable-512.png")
MISSING_ICONS=()

if [ ! -d "$ICON_DIR" ]; then
  warn "Icons folder not found in build directory: $ICON_DIR"
  warn "Creating icons folder and copying files from web/icons..."
  mkdir -p "$ICON_DIR"
  if [ -d "$APP_DIR/web/icons" ]; then
    cp -r "$APP_DIR/web/icons"/* "$ICON_DIR/" 2>/dev/null || true
  else
    warn "web/icons folder not found in project!"
  fi
fi

for icon in "${REQUIRED_ICONS[@]}"; do
  if [ ! -f "$ICON_DIR/$icon" ]; then
    MISSING_ICONS+=("$icon")
  fi
done

if [ ${#MISSING_ICONS[@]} -gt 0 ]; then
  warn "Following icon files not found:"
  for icon in "${MISSING_ICONS[@]}"; do
    warn "  - $icon"
  done
  warn "Copying icon files from web/icons..."
  if [ -d "$APP_DIR/web/icons" ]; then
    mkdir -p "$ICON_DIR"
    cp -r "$APP_DIR/web/icons"/* "$ICON_DIR/" 2>/dev/null || true
    echo "Icon files copied."
  else
    warn "web/icons folder not found in project! Please add icon files manually."
  fi
else
  echo "✓ All icon files are present."
fi

# Check manifest.json existence
if [ ! -f "$BUILD_DIR/manifest.json" ]; then
  warn "manifest.json file not found! Copying from web/manifest.json..."
  if [ -f "$APP_DIR/web/manifest.json" ]; then
    cp "$APP_DIR/web/manifest.json" "$BUILD_DIR/" 2>/dev/null || true
  fi
fi

# Copy built files to Apache deployment path
# DISABLED: Deployment to /var/www/arc.hesabix.ir is disabled
# DEPLOY_DIR="/var/www/arc.hesabix.ir"
# if [ -d "$BUILD_DIR" ] && [ -n "$(ls -A "$BUILD_DIR" 2>/dev/null)" ]; then
#   echo ""
#   echo "Copying built files to deployment path..."
#   if [ -d "$DEPLOY_DIR" ] || mkdir -p "$DEPLOY_DIR" 2>/dev/null; then
#     # Use optimized rsync with light compression and progress
#     # --compress-level=1 for fast compression with minimal CPU overhead
#     rsync -azP --compress-level=1 --delete "$BUILD_DIR/" "$DEPLOY_DIR/" 2>/dev/null || {
#       warn "Error copying files to $DEPLOY_DIR"
#       warn "Please copy files manually:"
#       warn "  rsync -azP --compress-level=1 --delete $BUILD_DIR/ $DEPLOY_DIR/"
#     }
#     chown -R www-data:www-data "$DEPLOY_DIR" 2>/dev/null || true
#     echo "✓ Files copied to $DEPLOY_DIR"
#   else
#     warn "Cannot create folder $DEPLOY_DIR. Please check permissions."
#   fi
# else
#   warn "Build path is empty or doesn't exist: $BUILD_DIR"
# fi

echo ""
echo "=========================================="
echo "✓ Build completed!"
echo "=========================================="
echo "Built files are located at:"
echo "  $BUILD_DIR"
echo ""
if [ "$MODE" = "release" ]; then
  echo "✓ Applied optimizations:"
  echo "  - Mode: Production (Release)"
  echo "  - Service Worker: Enabled (offline-first strategy)"
  echo "  - Optimization Level: 2 (balanced optimization)"
  echo "  - Parallel Workers: $BUILD_WORKERS (80% of $AVAILABLE_CORES cores)"
  echo "  - Heap Size: ${HEAP_SIZE_MB}MB (80% of ${TOTAL_RAM_MB}MB RAM)"
  echo "  - Base Href: /"
  echo "  - API Base URL: $API_BASE_URL"
  echo ""
  echo "Note: Service Worker automatically caches static files"
  echo "      and improves performance and enables offline usage."
else
  echo "✓ Applied optimizations:"
  echo "  - Mode: $MODE"
  echo "  - Renderer: CanvasKit"
  echo "  - Parallel Workers: $BUILD_WORKERS (80% of $AVAILABLE_CORES cores)"
  echo "  - Heap Size: ${HEAP_SIZE_MB}MB (80% of ${TOTAL_RAM_MB}MB RAM)"
  echo "  - Base Href: /"
  echo "  - API Base URL: $API_BASE_URL"
fi
echo ""
echo "To serve, you can use a web server:"
echo "  cd $BUILD_DIR && python3 -m http.server 8080"
echo "or use nginx/apache for serving."
echo ""


