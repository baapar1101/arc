#!/usr/bin/env bash

set -euo pipefail

# Build script for Flutter Android in this repo.
# Creates Android App Bundle (AAB) and APK files for release.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

DEFAULT_MODE="release" # debug|profile|release
DEFAULT_BUILD_AAB=true
DEFAULT_BUILD_APK=true
DEFAULT_BUILD_UNIVERSAL_APK=false
DEFAULT_BUILD_SPLIT_APK=true
DEFAULT_API_BASE_URL="https://hsxn.hesabix.ir"

USER_PROJECT=""
MODE="$DEFAULT_MODE"
BUILD_AAB="$DEFAULT_BUILD_AAB"
BUILD_APK="$DEFAULT_BUILD_APK"
BUILD_UNIVERSAL_APK="$DEFAULT_BUILD_UNIVERSAL_APK"
BUILD_SPLIT_APK="$DEFAULT_BUILD_SPLIT_APK"
API_BASE_URL="$DEFAULT_API_BASE_URL"
CLEAN_BUILD=false
INSTALL_DEPS=false

print_usage() {
  cat <<EOF
Usage: ./build_android.sh [--project <path>] [--mode <debug|profile|release>] [--api-base-url <url>] [--aab] [--no-aab] [--apk] [--no-apk] [--universal-apk] [--split-apk] [--clean] [--install-deps] [--help]

Options:
  --project PATH     Flutter project path (contains pubspec.yaml). If not specified, will be auto-detected.
  --mode MODE        Build type: debug, profile, or release (default: $DEFAULT_MODE).
  --api-base-url URL API base URL (default: $DEFAULT_API_BASE_URL).
  --aab              Build Android App Bundle (default: enabled).
  --no-aab           Skip building Android App Bundle.
  --apk              Build APK files (default: enabled).
  --no-apk           Skip building APK files.
  --universal-apk    Build universal APK (includes all ABIs, default: disabled).
  --split-apk        Build split APKs per ABI (default: enabled).
  --clean            Clean build directory before building.
  --install-deps     Install dependencies before building.
  -h, --help         Show help.

Usage examples:
  ./build_android.sh
  ./build_android.sh --mode release --clean
  ./build_android.sh --project hesabixUI/hesabix_ui
  ./build_android.sh --api-base-url https://hsxn.hesabix.ir
  ./build_android.sh --universal-apk --no-split-apk
  ./build_android.sh --aab --no-apk
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
  local FLUTTER_SDK_PATH="${FLUTTER_SDK_PATH:-/root/flutter}"
  if [ -d "$FLUTTER_SDK_PATH/bin" ]; then
    export PATH="$PATH:$FLUTTER_SDK_PATH/bin"
  fi
  if ! cmd_exists flutter; then
    die "Flutter not found. Please install it or configure PATH. Suggested path: $FLUTTER_SDK_PATH/bin"
  fi
}

is_flutter_project_dir() {
  local dir="$1"
  [ -f "$dir/pubspec.yaml" ] || return 1
  if grep -qiE "sdk:\s*flutter" "$dir/pubspec.yaml"; then
    return 0
  fi
  return 0
}

auto_detect_project_dir() {
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

  local common_path="$REPO_ROOT/hesabixUI/hesabix_ui"
  if [ -d "$common_path" ] && is_flutter_project_dir "$common_path"; then
    echo "$common_path"
    return 0
  fi

  local search_root="$REPO_ROOT/hesabixUI"
  if [ -d "$search_root" ]; then
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
    --api-base-url)
      [[ $# -ge 2 ]] || die "Value for --api-base-url not provided"
      API_BASE_URL="$2"; shift 2 ;;
    --aab)
      BUILD_AAB=true; shift ;;
    --no-aab)
      BUILD_AAB=false; shift ;;
    --apk)
      BUILD_APK=true; shift ;;
    --no-apk)
      BUILD_APK=false; shift ;;
    --universal-apk)
      BUILD_UNIVERSAL_APK=true; shift ;;
    --split-apk)
      BUILD_SPLIT_APK=true; shift ;;
    --no-split-apk)
      BUILD_SPLIT_APK=false; shift ;;
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

echo "Repo root: $REPO_ROOT"
echo "Project path: $APP_DIR"
echo "Mode: $MODE"
echo "API Base URL: $API_BASE_URL"
echo "Build AAB: $BUILD_AAB"
echo "Build APK: $BUILD_APK"
echo "Universal APK: $BUILD_UNIVERSAL_APK"
echo "Split APK: $BUILD_SPLIT_APK"

cd "$APP_DIR"

export PUB_HOSTED_URL="https://f.mirror.hesabix.ir/pub"
export FLUTTER_STORAGE_BASE_URL="https://f.mirror.hesabix.ir/gcs"

echo "Using Pub Hosted URL: $PUB_HOSTED_URL"
echo "Using Flutter Storage URL: $FLUTTER_STORAGE_BASE_URL"

# Configure Android SDK and Java environment
setup_android_env() {
  # Detect Android SDK
  local android_sdk_path="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/opt/android-sdk}}"
  if [ -d "$android_sdk_path" ]; then
    export ANDROID_SDK_ROOT="$android_sdk_path"
    export ANDROID_HOME="$android_sdk_path"
    export PATH="$PATH:$android_sdk_path/cmdline-tools/latest/bin:$android_sdk_path/platform-tools"
    echo "✓ Android SDK found: $ANDROID_SDK_ROOT"
  else
    warn "Android SDK not found at $android_sdk_path"
    warn "Please set ANDROID_SDK_ROOT or ANDROID_HOME environment variable"
  fi

  # Detect Java
  local java_home="${JAVA_HOME:-}"
  if [ -z "$java_home" ]; then
    # Try to find Java 17 or newer
    if [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
      java_home="/usr/lib/jvm/java-17-openjdk-amd64"
    elif [ -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
      java_home="/usr/lib/jvm/java-11-openjdk-amd64"
    elif cmd_exists java; then
      java_home=$(dirname $(dirname $(readlink -f $(which java))))
    fi
  fi
  
  if [ -n "$java_home" ] && [ -d "$java_home" ]; then
    export JAVA_HOME="$java_home"
    export PATH="$JAVA_HOME/bin:$PATH"
    echo "✓ Java found: $JAVA_HOME"
    java -version 2>&1 | head -n 1 || true
  else
    warn "Java not found. Please install Java 11 or newer and set JAVA_HOME"
  fi
}

setup_android_env

# Install dependencies if requested
if [ "$INSTALL_DEPS" = true ]; then
  echo "Installing dependencies..."
  if ! flutter pub get; then
    die "Error downloading dependencies. Please check internet connection and DNS."
  fi
elif [ ! -d "$APP_DIR/.dart_tool" ] || [ ! -f "$APP_DIR/pubspec.lock" ]; then
  echo "Dependencies not installed. Installing..."
  if ! flutter pub get; then
    warn "Error downloading dependencies. Trying to continue without them..."
    warn "If build fails, please run: cd $APP_DIR && flutter pub get"
  fi
fi

# Clean build directory if requested
if [ "$CLEAN_BUILD" = true ]; then
  echo "Cleaning build directory..."
  flutter clean
fi

# Check keystore for release builds
check_keystore() {
  if [ "$MODE" != "release" ]; then
    return 0
  fi
  
  local keystore_props="$APP_DIR/android/keystore.properties"
  local keystore_file=""
  
  if [ -f "$keystore_props" ]; then
    # Extract storeFile from keystore.properties
    keystore_file=$(grep "^storeFile=" "$keystore_props" | cut -d'=' -f2 || echo "")
    if [ -n "$keystore_file" ]; then
      # Handle relative paths:
      # - Gradle's `file(...)` in `android/app/build.gradle.*` resolves relative to `android/app`
      # - Some teams store paths relative to `android/`
      if [[ "$keystore_file" != /* ]]; then
        local candidate_app="$APP_DIR/android/app/$keystore_file"
        local candidate_android="$APP_DIR/android/$keystore_file"
        if [ -f "$candidate_app" ]; then
          keystore_file="$candidate_app"
        elif [ -f "$candidate_android" ]; then
          keystore_file="$candidate_android"
        else
          # Default to android/ resolution for the warning message
          keystore_file="$candidate_android"
        fi
      fi
      if [ -f "$keystore_file" ]; then
        echo "✓ Keystore found: $keystore_file"
        return 0
      fi
    fi
  fi
  
  warn "⚠ Warning: Keystore not found for release build!"
  warn "  Release builds should be signed with a keystore."
  warn "  Keystore properties file: $keystore_props"
  warn "  The build will continue but may use debug signing."
  warn ""
  warn "  To create a keystore, run:"
  warn "    keytool -genkey -v -keystore $APP_DIR/android/keystore.jks \\"
  warn "      -keyalg RSA -keysize 2048 -validity 10000 \\"
  warn "      -alias release"
  warn ""
  warn "  Then create $keystore_props with:"
  warn "    storeFile=keystore.jks"
  warn "    storePassword=YOUR_STORE_PASSWORD"
  warn "    keyAlias=release"
  warn "    keyPassword=YOUR_KEY_PASSWORD"
}

check_keystore

# Build flags
BUILD_FLAGS=("--$MODE")
BUILD_FLAGS+=("--android-skip-build-dependency-validation")
BUILD_FLAGS+=("--dart-define" "API_BASE_URL=$API_BASE_URL")

# Configure CPU cores for parallel compilation
AVAILABLE_CORES=$(nproc)
BUILD_WORKERS=$((AVAILABLE_CORES * 80 / 100))
[ "$BUILD_WORKERS" -lt 1 ] && BUILD_WORKERS=1
[ "$BUILD_WORKERS" -gt 16 ] && BUILD_WORKERS=16

echo ""
echo "Build Configuration:"
echo "  Mode: $MODE"
echo "  API Base URL: $API_BASE_URL"
echo "  CPU cores: $AVAILABLE_CORES (using $BUILD_WORKERS workers)"
echo ""

# Build Android App Bundle
if [ "$BUILD_AAB" = true ]; then
  echo "=========================================="
  echo "Building Android App Bundle (AAB)..."
  echo "=========================================="
  if flutter build appbundle "${BUILD_FLAGS[@]}"; then
    aab_path="$APP_DIR/build/app/outputs/bundle/${MODE}/app-${MODE}.aab"
    if [ -f "$aab_path" ]; then
      echo "✓ AAB built successfully: $aab_path"
      ls -lh "$aab_path" || true
    fi
  else
    warn "Failed to build AAB"
  fi
  echo ""
fi

# Build APK files
if [ "$BUILD_APK" = true ]; then
  # Build universal APK
  if [ "$BUILD_UNIVERSAL_APK" = true ]; then
    echo "=========================================="
    echo "Building Universal APK (all ABIs)..."
    echo "=========================================="
    if flutter build apk "${BUILD_FLAGS[@]}"; then
      apk_path="$APP_DIR/build/app/outputs/flutter-apk/app-${MODE}.apk"
      if [ -f "$apk_path" ]; then
        echo "✓ Universal APK built successfully: $apk_path"
        ls -lh "$apk_path" || true
      fi
    else
      warn "Failed to build universal APK"
    fi
    echo ""
  fi

  # Build split APKs
  if [ "$BUILD_SPLIT_APK" = true ]; then
    echo "=========================================="
    echo "Building Split APKs (per ABI)..."
    echo "=========================================="
    if flutter build apk "${BUILD_FLAGS[@]}" --split-per-abi; then
      apk_dir="$APP_DIR/build/app/outputs/flutter-apk"
      echo "✓ Split APKs built successfully:"
      ls -lh "$apk_dir"/*-${MODE}.apk 2>/dev/null | grep -v "app-${MODE}.apk" || true
    else
      warn "Failed to build split APKs"
    fi
    echo ""
  fi
fi

# Summary
echo "=========================================="
echo "✓ Build completed!"
echo "=========================================="
echo ""
echo "Build Configuration:"
echo "  Mode: $MODE"
echo "  API Base URL: $API_BASE_URL"
echo ""

if [ "$BUILD_AAB" = true ]; then
  aab_path="$APP_DIR/build/app/outputs/bundle/${MODE}/app-${MODE}.aab"
  if [ -f "$aab_path" ]; then
    echo "📦 Android App Bundle (AAB):"
    echo "   $aab_path"
    echo ""
  fi
fi

if [ "$BUILD_APK" = true ]; then
  apk_dir="$APP_DIR/build/app/outputs/flutter-apk"
  if [ "$BUILD_UNIVERSAL_APK" = true ]; then
    apk_path="$apk_dir/app-${MODE}.apk"
    if [ -f "$apk_path" ]; then
      echo "📱 Universal APK:"
      echo "   $apk_path"
      echo ""
    fi
  fi
  
  if [ "$BUILD_SPLIT_APK" = true ]; then
    split_apks=$(ls "$apk_dir"/*-${MODE}.apk 2>/dev/null | grep -v "app-${MODE}.apk" || true)
    if [ -n "$split_apks" ]; then
      echo "📱 Split APKs:"
      echo "$split_apks" | while read -r apk; do
        echo "   $apk"
      done
      echo ""
    fi
  fi
fi

echo "Build outputs are located at:"
echo "  $APP_DIR/build/app/outputs/"
echo ""

