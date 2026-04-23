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
  --project PATH     Flutter project path (contains pubspec.yaml). If not specified, will be auto-detected.
  --mode MODE        Build type: debug, profile, or release (default: $DEFAULT_MODE).
  --build-dir DIR    Build directory path (default: $DEFAULT_BUILD_DIR).
  --output-dir DIR   Final output path (default: $DEFAULT_OUTPUT_DIR).
  --clean            Clean build directory before building.
  --install-deps     Install dependencies before building.
  --api-base-url     API base URL passed to app as --dart-define.
  --archive          Create tar.gz file from output.
  -h, --help         Show help.

Usage examples:
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

check_linux_dependencies() {
  echo "Checking Linux dependencies..."
  
  local missing_deps=()
  
  # Check GTK development libraries
  if ! pkg-config --exists gtk+-3.0; then
    missing_deps+=("libgtk-3-dev")
  fi
  
  # Check CMake
  if ! cmd_exists cmake; then
    missing_deps+=("cmake")
  fi
  
  # Check Ninja
  if ! cmd_exists ninja; then
    missing_deps+=("ninja-build")
  fi
  
  # Check C++ compiler
  if ! cmd_exists clang++; then
    missing_deps+=("clang")
  fi
  
  # Check build-essential
  if ! cmd_exists gcc; then
    missing_deps+=("build-essential")
  fi
  
  if [ ${#missing_deps[@]} -gt 0 ]; then
    echo "Installing required dependencies..."
    echo "Required packages: ${missing_deps[*]}"
    
    # Detect Linux distribution
    if command -v apt >/dev/null 2>&1; then
      # Ubuntu/Debian
      echo "Detected distribution: Ubuntu/Debian"
      sudo apt update
      sudo apt install -y "${missing_deps[@]}"
    elif command -v dnf >/dev/null 2>&1; then
      # Fedora/RHEL
      echo "Detected distribution: Fedora/RHEL"
      sudo dnf install -y "${missing_deps[@]}"
    elif command -v pacman >/dev/null 2>&1; then
      # Arch Linux
      echo "Detected distribution: Arch Linux"
      sudo pacman -S --noconfirm "${missing_deps[@]}"
    else
      die "Supported Linux distribution not found. Please install dependencies manually: ${missing_deps[*]}"
    fi
    
    echo "Dependencies installed."
  else
    echo "All required dependencies are present."
  fi
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
    --output-dir)
      [[ $# -ge 2 ]] || die "Value for --output-dir not provided"
      OUTPUT_DIR="$2"; shift 2 ;;
    --clean)
      CLEAN_BUILD=true; shift ;;
    --install-deps)
      INSTALL_DEPS=true; shift ;;
    --api-base-url)
      [[ $# -ge 2 ]] || die "Value for --api-base-url not provided"
      API_BASE_URL="$2"; shift 2 ;;
    --archive)
      CREATE_ARCHIVE=true; shift ;;
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
check_linux_dependencies

APP_DIR="$(auto_detect_project_dir)"

if [ -z "$BUILD_DIR" ]; then
  BUILD_DIR="$DEFAULT_BUILD_DIR"
fi

if [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
fi

# Convert to absolute path
BUILD_DIR="$(cd "$APP_DIR" && realpath -m "$BUILD_DIR")"
OUTPUT_DIR="$(cd "$APP_DIR" && realpath -m "$OUTPUT_DIR")"

echo "Repo root: $REPO_ROOT"
echo "Project path: $APP_DIR"
echo "Mode: $MODE"
echo "Build path: $BUILD_DIR"
echo "Output path: $OUTPUT_DIR"

cd "$APP_DIR"

export PUB_HOSTED_URL="https://f.mirror.hesabix.ir/pub"
export FLUTTER_STORAGE_BASE_URL="https://f.mirror.hesabix.ir/gcs"

# Configure C++ compiler flags to resolve deprecated warnings
export CXXFLAGS="-Wno-deprecated-literal-operator"
export CFLAGS="-Wno-deprecated-literal-operator"

# Install dependencies if requested
if [ "$INSTALL_DEPS" = true ]; then
  echo "Installing dependencies..."
  flutter pub get
fi

# Clean build directory if requested
if [ "$CLEAN_BUILD" = true ]; then
  echo "Cleaning build directory..."
  rm -rf "$BUILD_DIR"
fi

# Configure dart-define arguments
DART_DEFINE_ARGS=()
if [ -n "$API_BASE_URL" ]; then
  DART_DEFINE_ARGS+=(--dart-define "API_BASE_URL=$API_BASE_URL")
fi

# Building Flutter for Linux
echo "Building Flutter for Linux..."
echo "Command: flutter build linux --$MODE ${DART_DEFINE_ARGS[*]:-}"

flutter build linux --"$MODE" ${DART_DEFINE_ARGS[@]:-}

# Copy built files to output path
echo "Copying built files..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Copy bundle from build directory
if [ -d "$BUILD_DIR/x64/$MODE/bundle" ]; then
  cp -r "$BUILD_DIR/x64/$MODE/bundle"/* "$OUTPUT_DIR/"
  echo "Built files copied to: $OUTPUT_DIR"
else
  die "Bundle path not found: $BUILD_DIR/x64/$MODE/bundle"
fi

# Create executable file
EXECUTABLE_NAME="hesabix_ui"
if [ -f "$OUTPUT_DIR/$EXECUTABLE_NAME" ]; then
  chmod +x "$OUTPUT_DIR/$EXECUTABLE_NAME"
  echo "Executable file: $OUTPUT_DIR/$EXECUTABLE_NAME"
else
  warn "Executable file not found: $OUTPUT_DIR/$EXECUTABLE_NAME"
fi

# Create archive if requested
if [ "$CREATE_ARCHIVE" = true ]; then
  ARCHIVE_NAME="hesabix_ui_linux_${MODE}_$(date +%Y%m%d_%H%M%S).tar.gz"
  ARCHIVE_PATH="$(dirname "$OUTPUT_DIR")/$ARCHIVE_NAME"
  
  echo "Creating archive: $ARCHIVE_PATH"
  cd "$(dirname "$OUTPUT_DIR")"
  tar -czf "$ARCHIVE_PATH" "$(basename "$OUTPUT_DIR")"
  
  echo "Archive created: $ARCHIVE_PATH"
  echo "To run: tar -xzf $ARCHIVE_NAME && cd $(basename "$OUTPUT_DIR") && ./$EXECUTABLE_NAME"
fi

echo "Build completed!"
echo "To run: cd $OUTPUT_DIR && ./$EXECUTABLE_NAME"
