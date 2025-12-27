#!/usr/bin/env bash

set -euo pipefail

# اسکریپت مدیریت نسخه سراسری برای پروژه Flutter
# این اسکریپت نسخه را در pubspec.yaml تغییر می‌دهد و Flutter به طور خودکار
# این نسخه را به تمام پلتفرم‌ها (Android, iOS, Windows, Linux, macOS, Web) منتقل می‌کند

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
استفاده: ./update_version.sh [گزینه‌ها]

گزینه‌ها:
  --project PATH      مسیر پروژه Flutter (پیش‌فرض: $DEFAULT_PROJECT)
  --set VERSION       تنظیم نسخه به صورت دستی (مثال: 1.0.23)
  --build NUMBER      تنظیم شماره بیلد (مثال: 23)
  --set-full VERSION  تنظیم نسخه کامل (مثال: 1.0.23+23)
  --increment TYPE    افزایش نسخه (major|minor|patch|build)
  --show              نمایش نسخه فعلی
  --help              نمایش راهنما

مثال‌ها:
  # نمایش نسخه فعلی
  ./update_version.sh --show

  # تنظیم نسخه به 1.0.24
  ./update_version.sh --set 1.0.24

  # تنظیم شماره بیلد به 24
  ./update_version.sh --build 24

  # تنظیم نسخه کامل
  ./update_version.sh --set-full 1.0.24+24

  # افزایش نسخه patch (1.0.23 -> 1.0.24)
  ./update_version.sh --increment patch

  # افزایش نسخه minor (1.0.23 -> 1.1.0)
  ./update_version.sh --increment minor

  # افزایش نسخه major (1.0.23 -> 2.0.0)
  ./update_version.sh --increment major

  # افزایش شماره بیلد (23 -> 24)
  ./update_version.sh --increment build

نکته: Flutter به طور خودکار نسخه را به تمام پلتفرم‌ها منتقل می‌کند:
  - Android: versionName و versionCode
  - iOS: CFBundleShortVersionString و CFBundleVersion
  - Windows: FLUTTER_VERSION_MAJOR, MINOR, PATCH, BUILD
  - Linux: از pubspec.yaml
  - macOS: CFBundleShortVersionString و CFBundleVersion
  - Web: از pubspec.yaml
EOF
}

warn() { echo "[هشدار] $*" >&2; }
die() { echo "[خطا] $*" >&2; exit 1; }
info() { echo "[اطلاعات] $*"; }

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
    [ -d "$p" ] || die "مسیر پروژه وجود ندارد: $p"
    local pubspec=$(find_pubspec "$p")
    [ -n "$pubspec" ] || die "فایل pubspec.yaml در مسیر یافت نشد: $p"
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

  die "پروژه Flutter یافت نشد. لطفاً مسیر را با --project مشخص کنید."
}

get_current_version() {
  local pubspec_file="$1"
  local version_line=$(grep -E "^version:" "$pubspec_file" | head -n 1)
  if [ -z "$version_line" ]; then
    die "خط version در pubspec.yaml یافت نشد"
  fi
  
  # استخراج نسخه از خط version: 1.0.23+23
  local version_str=$(echo "$version_line" | sed -E 's/^version:\s*//' | tr -d ' ')
  echo "$version_str"
}

parse_version() {
  local version_str="$1"
  # فرمت: MAJOR.MINOR.PATCH+BUILD
  if [[ "$version_str" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]}"
  else
    die "فرمت نسخه نامعتبر: $version_str (باید به صورت MAJOR.MINOR.PATCH+BUILD باشد)"
  fi
}

update_version_in_pubspec() {
  local pubspec_file="$1"
  local new_version="$2"
  
  # پشتیبان‌گیری از فایل
  local backup_file="${pubspec_file}.bak"
  cp "$pubspec_file" "$backup_file"
  
  # جایگزینی نسخه
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/^version:.*/version: $new_version/" "$pubspec_file"
  else
    # Linux
    sed -i "s/^version:.*/version: $new_version/" "$pubspec_file"
  fi
  
  # بررسی موفقیت
  local updated=$(get_current_version "$pubspec_file")
  if [ "$updated" != "$new_version" ]; then
    mv "$backup_file" "$pubspec_file"
    die "خطا در به‌روزرسانی نسخه"
  fi
  
  # حذف فایل پشتیبان در صورت موفقیت
  rm -f "$backup_file"
  info "نسخه به‌روزرسانی شد: $new_version"
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
      die "نوع افزایش نامعتبر: $increment_type (باید یکی از: major, minor, patch, build باشد)"
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
  echo "نسخه فعلی برنامه:"
  echo "=========================================="
  echo "  نسخه کامل: $version_str"
  echo "  Major:     $major"
  echo "  Minor:     $minor"
  echo "  Patch:     $patch"
  echo "  Build:     $build"
  echo ""
  echo "این نسخه در تمام پلتفرم‌ها استفاده می‌شود:"
  echo "  ✓ Android: versionName=$major.$minor.$patch, versionCode=$build"
  echo "  ✓ iOS:     CFBundleShortVersionString=$major.$minor.$patch, CFBundleVersion=$build"
  echo "  ✓ Windows: FLUTTER_VERSION=$major.$minor.$patch, BUILD=$build"
  echo "  ✓ Linux:   از pubspec.yaml"
  echo "  ✓ macOS:   CFBundleShortVersionString=$major.$minor.$patch, CFBundleVersion=$build"
  echo "  ✓ Web:     از pubspec.yaml"
  echo "=========================================="
  echo ""
}

# پارس کردن آرگومان‌ها
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)
      [[ $# -ge 2 ]] || die "مقدار برای --project ارائه نشده است"
      USER_PROJECT="$2"; shift 2 ;;
    --set)
      [[ $# -ge 2 ]] || die "مقدار برای --set ارائه نشده است"
      ACTION="set"
      VERSION="$2"; shift 2 ;;
    --build)
      [[ $# -ge 2 ]] || die "مقدار برای --build ارائه نشده است"
      ACTION="build"
      BUILD_NUMBER="$2"; shift 2 ;;
    --set-full)
      [[ $# -ge 2 ]] || die "مقدار برای --set-full ارائه نشده است"
      ACTION="set-full"
      VERSION="$2"; shift 2 ;;
    --increment)
      [[ $# -ge 2 ]] || die "مقدار برای --increment ارائه نشده است"
      ACTION="increment"
      INCREMENT_TYPE="$2"; shift 2 ;;
    --show)
      ACTION="show"; shift ;;
    -h|--help)
      print_usage; exit 0 ;;
    *)
      warn "آرگومان ناشناخته: $1"; shift ;;
  esac
done

if [ -z "$ACTION" ]; then
  print_usage
  exit 0
fi

APP_DIR="$(auto_detect_project_dir)"
PUBSPEC_FILE="$APP_DIR/pubspec.yaml"

if [ ! -f "$PUBSPEC_FILE" ]; then
  die "فایل pubspec.yaml یافت نشد: $PUBSPEC_FILE"
fi

CURRENT_VERSION=$(get_current_version "$PUBSPEC_FILE")
read -r CURRENT_MAJOR CURRENT_MINOR CURRENT_PATCH CURRENT_BUILD <<< "$(parse_version "$CURRENT_VERSION")"

case "$ACTION" in
  show)
    show_version "$APP_DIR"
    ;;
  set)
    # بررسی فرمت نسخه (باید MAJOR.MINOR.PATCH باشد)
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      die "فرمت نسخه نامعتبر: $VERSION (باید به صورت MAJOR.MINOR.PATCH باشد، مثال: 1.0.24)"
    fi
    NEW_VERSION="$VERSION+$CURRENT_BUILD"
    update_version_in_pubspec "$PUBSPEC_FILE" "$NEW_VERSION"
    show_version "$APP_DIR"
    ;;
  build)
    # بررسی اینکه شماره بیلد یک عدد است
    if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
      die "شماره بیلد باید یک عدد باشد: $BUILD_NUMBER"
    fi
    NEW_VERSION="$CURRENT_MAJOR.$CURRENT_MINOR.$CURRENT_PATCH+$BUILD_NUMBER"
    update_version_in_pubspec "$PUBSPEC_FILE" "$NEW_VERSION"
    show_version "$APP_DIR"
    ;;
  set-full)
    # بررسی فرمت نسخه کامل
    if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
      die "فرمت نسخه نامعتبر: $VERSION (باید به صورت MAJOR.MINOR.PATCH+BUILD باشد، مثال: 1.0.24+24)"
    fi
    update_version_in_pubspec "$PUBSPEC_FILE" "$VERSION"
    show_version "$APP_DIR"
    ;;
  increment)
    NEW_VERSION=$(increment_version "$CURRENT_VERSION" "$INCREMENT_TYPE")
    update_version_in_pubspec "$PUBSPEC_FILE" "$NEW_VERSION"
    info "نسخه از $CURRENT_VERSION به $NEW_VERSION افزایش یافت"
    show_version "$APP_DIR"
    ;;
  *)
    die "عملیات نامعتبر: $ACTION"
    ;;
esac

echo ""
info "✓ عملیات با موفقیت انجام شد!"
info "برای اعمال تغییرات در بیلدها، دستورات build را اجرا کنید:"
echo "  ./build_android.sh"
echo "  ./build_windows.ps1"
echo "  flutter build ios"
echo "  flutter build linux"
echo "  flutter build macos"
echo "  flutter build web"
echo ""




