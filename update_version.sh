#!/usr/bin/env bash

set -euo pipefail

# Global version management script for the Flutter project
# Updates version in pubspec.yaml; Flutter propagates it to all platforms
# (Android, iOS, Windows, Linux, macOS, Web)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

DEFAULT_PROJECT="hesabixUI/hesabix_ui"

USER_PROJECT=""
ACTION=""
VERSION=""
BUILD_NUMBER=""
INCREMENT_TYPE=""

print_usage() {
  cat <<EOF
Usage: ./update_version.sh [options]

Options:
  --project PATH      Path to Flutter project (default: $DEFAULT_PROJECT)
  --set VERSION       Set semantic version manually (e.g. 1.0.23)
  --build NUMBER      Set build number (e.g. 23)
  --set-full VERSION  Set full version (e.g. 1.0.23+23)
  --increment TYPE    Bump version (major|minor|patch|build)
  --show              Show current version
  --help              Show this help

Examples:
  # Show current version
  ./update_version.sh --show

  # Set version to 1.0.24
  ./update_version.sh --set 1.0.24

  # Set build number to 24
  ./update_version.sh --build 24

  # Set full version
  ./update_version.sh --set-full 1.0.24+24

  # Bump patch (1.0.23 -> 1.0.24)
  ./update_version.sh --increment patch

  # Bump minor (1.0.23 -> 1.1.0)
  ./update_version.sh --increment minor

  # Bump major (1.0.23 -> 2.0.0)
  ./update_version.sh --increment major

  # Bump build number (23 -> 24)
  ./update_version.sh --increment build

Note: Flutter propagates this version to all platforms:
  - Android: versionName and versionCode
  - iOS: CFBundleShortVersionString and CFBundleVersion
  - Windows: FLUTTER_VERSION_MAJOR, MINOR, PATCH, BUILD
  - Linux: from pubspec.yaml
  - macOS: CFBundleShortVersionString and CFBundleVersion
  - Web: from pubspec.yaml
EOF
}

warn() { echo "[WARN] $*" >&2; }
die() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO] $*"; }

find_pubspec() {
  local search_dir="$1"
  if [ -f "$search_dir/pubspec.yaml" ]; then
    echo "$search_dir/pubspec.yaml"
    return 0
  fi
  return 1
}

auto_detect_project_dir() {
  if [ -n "$USER_PROJECT" ]; then
    local p="$USER_PROJECT"
    [ -d "$p" ] || die "Project path does not exist: $p"
    local pubspec=$(find_pubspec "$p")
    [ -n "$pubspec" ] || die "pubspec.yaml not found under: $p"
    echo "$(cd "$p" && pwd)"
    return 0
  fi

  if [ -n "${FLUTTER_APP_DIR:-}" ]; then
    local p="$FLUTTER_APP_DIR"
    if [ -d "$p" ]; then
      local pubspec=$(find_pubspec "$p")
      if [ -n "$pubspec" ]; then
        echo "$(cd "$p" && pwd)"
        return 0
      fi
    fi
  fi

  local common_path="$REPO_ROOT/$DEFAULT_PROJECT"
  if [ -d "$common_path" ]; then
    local pubspec=$(find_pubspec "$common_path")
    if [ -n "$pubspec" ]; then
      echo "$(cd "$common_path" && pwd)"
      return 0
    fi
  fi

  die "Flutter project not found. Specify path with --project."
}

get_current_version() {
  local pubspec_file="$1"
  local version_line=$(grep -E "^version:" "$pubspec_file" | head -n 1)
  if [ -z "$version_line" ]; then
    die "No version: line found in pubspec.yaml"
  fi

  # Parse version line: version: 1.0.23+23
  local version_str=$(echo "$version_line" | sed -E 's/^version:\s*//' | tr -d ' ')
  echo "$version_str"
}

parse_version() {
  local version_str="$1"
  # Format: MAJOR.MINOR.PATCH+BUILD
  if [[ "$version_str" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]}"
  else
    die "Invalid version format: $version_str (expected MAJOR.MINOR.PATCH+BUILD)"
  fi
}

update_version_in_pubspec() {
  local pubspec_file="$1"
  local new_version="$2"

  # Backup file
  local backup_file="${pubspec_file}.bak"
  cp "$pubspec_file" "$backup_file"

  # Replace version line
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s/^version:.*/version: $new_version/" "$pubspec_file"
  else
    sed -i "s/^version:.*/version: $new_version/" "$pubspec_file"
  fi

  # Verify
  local updated=$(get_current_version "$pubspec_file")
  if [ "$updated" != "$new_version" ]; then
    mv "$backup_file" "$pubspec_file"
    die "Failed to update version"
  fi

  rm -f "$backup_file"
  info "Version updated: $new_version"
}

increment_version() {
  local version_str="$1"
  local increment_type="$2"

  read -r major minor patch build <<< "$(parse_version "$version_str")"

  case "$increment_type" in
    major)
      major=$((major + 1))
      minor=0
      patch=0
      ;;
    minor)
      minor=$((minor + 1))
      patch=0
      ;;
    patch)
      patch=$((patch + 1))
      ;;
    build)
      build=$((build + 1))
      ;;
    *)
      die "Invalid increment type: $increment_type (use: major, minor, patch, build)"
      ;;
  esac

  echo "$major.$minor.$patch+$build"
}

show_version() {
  local pubspec_file="$1/pubspec.yaml"
  local version_str=$(get_current_version "$pubspec_file")
  read -r major minor patch build <<< "$(parse_version "$version_str")"

  echo ""
  echo "=========================================="
  echo "Current application version:"
  echo "=========================================="
  echo "  Full:  $version_str"
  echo "  Major: $major"
  echo "  Minor: $minor"
  echo "  Patch: $patch"
  echo "  Build: $build"
  echo ""
  echo "This version is used on all platforms:"
  echo "  OK Android: versionName=$major.$minor.$patch, versionCode=$build"
  echo "  OK iOS:     CFBundleShortVersionString=$major.$minor.$patch, CFBundleVersion=$build"
  echo "  OK Windows: FLUTTER_VERSION=$major.$minor.$patch, BUILD=$build"
  echo "  OK Linux:   from pubspec.yaml"
  echo "  OK macOS:   CFBundleShortVersionString=$major.$minor.$patch, CFBundleVersion=$build"
  echo "  OK Web:     from pubspec.yaml"
  echo "=========================================="
  echo ""
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || die "Missing value for --project"
      USER_PROJECT="$2"; shift 2 ;;
    --set)
      [[ $# -ge 2 ]] || die "Missing value for --set"
      ACTION="set"
      VERSION="$2"; shift 2 ;;
    --build)
      [[ $# -ge 2 ]] || die "Missing value for --build"
      ACTION="build"
      BUILD_NUMBER="$2"; shift 2 ;;
    --set-full)
      [[ $# -ge 2 ]] || die "Missing value for --set-full"
      ACTION="set-full"
      VERSION="$2"; shift 2 ;;
    --increment)
      [[ $# -ge 2 ]] || die "Missing value for --increment"
      ACTION="increment"
      INCREMENT_TYPE="$2"; shift 2 ;;
    --show)
      ACTION="show"; shift ;;
    -h|--help)
      print_usage; exit 0 ;;
    *)
      warn "Unknown argument: $1"; shift ;;
  esac
done

if [ -z "$ACTION" ]; then
  print_usage
  exit 0
fi

APP_DIR="$(auto_detect_project_dir)"
PUBSPEC_FILE="$APP_DIR/pubspec.yaml"

if [ ! -f "$PUBSPEC_FILE" ]; then
  die "pubspec.yaml not found: $PUBSPEC_FILE"
fi

CURRENT_VERSION=$(get_current_version "$PUBSPEC_FILE")
read -r CURRENT_MAJOR CURRENT_MINOR CURRENT_PATCH CURRENT_BUILD <<< "$(parse_version "$CURRENT_VERSION")"

case "$ACTION" in
  show)
    show_version "$APP_DIR"
    ;;
  set)
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      die "Invalid version format: $VERSION (expected MAJOR.MINOR.PATCH, e.g. 1.0.24)"
    fi
    NEW_VERSION="$VERSION+$CURRENT_BUILD"
    update_version_in_pubspec "$PUBSPEC_FILE" "$NEW_VERSION"
    show_version "$APP_DIR"
    ;;
  build)
    if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
      die "Build number must be numeric: $BUILD_NUMBER"
    fi
    NEW_VERSION="$CURRENT_MAJOR.$CURRENT_MINOR.$CURRENT_PATCH+$BUILD_NUMBER"
    update_version_in_pubspec "$PUBSPEC_FILE" "$NEW_VERSION"
    show_version "$APP_DIR"
    ;;
  set-full)
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
      die "Invalid version format: $VERSION (expected MAJOR.MINOR.PATCH+BUILD, e.g. 1.0.24+24)"
    fi
    update_version_in_pubspec "$PUBSPEC_FILE" "$VERSION"
    show_version "$APP_DIR"
    ;;
  increment)
    NEW_VERSION=$(increment_version "$CURRENT_VERSION" "$INCREMENT_TYPE")
    update_version_in_pubspec "$PUBSPEC_FILE" "$NEW_VERSION"
    info "Version bumped from $CURRENT_VERSION to $NEW_VERSION"
    show_version "$APP_DIR"
    ;;
  *)
    die "Invalid action: $ACTION"
    ;;
esac

echo ""
info "Done successfully."
info "Run build commands to propagate changes into binaries:"
echo "  ./build_android.sh"
echo "  ./build_windows.ps1"
echo "  flutter build ios"
echo "  flutter build linux"
echo "  flutter build macos"
echo "  flutter build web"
echo ""


