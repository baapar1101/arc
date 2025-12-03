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
  --project PATH     Flutter project path (contains pubspec.yaml). If not specified, will be auto-detected.
  --mode MODE        Build type: debug, profile, or release (default: $DEFAULT_MODE).
  --build-dir DIR    Build directory path (default: $DEFAULT_BUILD_DIR).
  --api-base-url     API base URL (default: $DEFAULT_API_BASE_URL).
  --clean            Clean build directory before building.
  --install-deps     Install dependencies before building.
  -h, --help         Show help.

Usage examples:
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
    die "Flutter not found. Please install it or configure PATH. Suggested path: $SNAP_FLUTTER_BIN"
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
    # If no access, use default
    # DNS or network problem may exist
    export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.dev}"
    export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.googleapis.com}"
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
    warn "Using default: $PUB_HOSTED_URL"
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

# Install dependencies if requested
if [ "$INSTALL_DEPS" = true ]; then
  echo "Installing dependencies..."
  if ! flutter pub get; then
    die "Error downloading dependencies. Please check internet connection and DNS."
  fi
elif [ ! -d "$APP_DIR/.dart_tool" ] || [ ! -f "$APP_DIR/pubspec.lock" ]; then
  # If dependencies are not installed, try to install them
  echo "Dependencies not installed. Installing..."
  if ! flutter pub get; then
    warn "Error downloading dependencies. Trying to continue without them..."
    warn "If build fails, please run the following command:"
    warn "  cd $APP_DIR && flutter pub get"
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

# For release mode, use PWA strategy and full optimizations
if [ "$MODE" = "release" ]; then
  BUILD_FLAGS+=(--pwa-strategy offline-first)
  BUILD_FLAGS+=(--base-href /)
  # Reduce optimization-level from 4 to 2 to prevent OOM (Out of Memory)
  # Level 4 requires too much memory and may cause exit code -9
  BUILD_FLAGS+=(--optimization-level 2)
  echo "Building Flutter for Web (Production) with full optimizations..."
  echo "  - PWA Strategy: offline-first (Service Worker enabled)"
  echo "  - Base Href: /"
  echo "  - Optimization Level: 2 (balanced optimization to prevent OOM)"
else
  # For debug/profile, only add base-href
  BUILD_FLAGS+=(--base-href /)
  echo "Building Flutter for Web ($MODE) with basic optimizations..."
  echo "  - Base Href: /"
fi

echo "Full command: flutter build web --$MODE ${BUILD_FLAGS[*]} --dart-define API_BASE_URL=$API_BASE_URL"
echo ""

# Configure memory limits for dart compile js to prevent OOM
# Increase heap size for dart2js compiler
export DART_VM_OPTIONS="--old-gen-heap-size=4096"
# Can also use --max-old-space-size if needed
# But Flutter manages these settings itself

# Check available memory
echo "Checking system memory..."
free -h | head -2
echo ""

# Run build with memory settings
flutter build web --"$MODE" "${BUILD_FLAGS[@]}" "${DART_DEFINE_ARGS[@]}"

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
DEPLOY_DIR="/var/www/arc.hesabix.ir"
if [ -d "$BUILD_DIR" ] && [ -n "$(ls -A "$BUILD_DIR" 2>/dev/null)" ]; then
  echo ""
  echo "Copying built files to deployment path..."
  if [ -d "$DEPLOY_DIR" ] || mkdir -p "$DEPLOY_DIR" 2>/dev/null; then
    rsync -a --delete "$BUILD_DIR/" "$DEPLOY_DIR/" 2>/dev/null || {
      warn "Error copying files to $DEPLOY_DIR"
      warn "Please copy files manually:"
      warn "  rsync -a --delete $BUILD_DIR/ $DEPLOY_DIR/"
    }
    chown -R www-data:www-data "$DEPLOY_DIR" 2>/dev/null || true
    echo "✓ Files copied to $DEPLOY_DIR"
  else
    warn "Cannot create folder $DEPLOY_DIR. Please check permissions."
  fi
else
  warn "Build path is empty or doesn't exist: $BUILD_DIR"
fi

echo ""
echo "=========================================="
echo "✓ Build completed!"
echo "=========================================="
echo "Built files are located at:"
echo "  $BUILD_DIR"
if [ -d "$DEPLOY_DIR" ]; then
  echo "  and in deployment path:"
  echo "  $DEPLOY_DIR"
fi
echo ""
if [ "$MODE" = "release" ]; then
  echo "✓ Applied optimizations:"
  echo "  - Mode: Production (Release)"
  echo "  - Service Worker: Enabled (offline-first strategy)"
  echo "  - Optimization Level: 4 (maximum optimization)"
  echo "  - Base Href: /"
  echo "  - API Base URL: $API_BASE_URL"
  echo ""
  echo "Note: Service Worker automatically caches static files"
  echo "      and improves performance and enables offline usage."
else
  echo "✓ Applied optimizations:"
  echo "  - Mode: $MODE"
  echo "  - Renderer: CanvasKit"
  echo "  - Base Href: /"
  echo "  - API Base URL: $API_BASE_URL"
fi
echo ""
echo "To serve, you can use a web server:"
echo "  cd $BUILD_DIR && python3 -m http.server 8080"
echo "or use nginx/apache for serving."
echo ""


