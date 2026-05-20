#!/usr/bin/env bash

set -euo pipefail

# Build script for Flutter Android in this repo.
# Creates Android App Bundle (AAB) and APK files for release.
#
# پس از pull اگر pubspec.lock یا third_party/desktop_drop عوض شد: cd hesabixUI/hesabix_ui && flutter pub get
#
# Mirrors & defaults align with deploy.sh:
#   - Pub / engine artifacts: f.mirror.hesabix.ir (override with PUB_HOSTED_URL, FLUTTER_STORAGE_BASE_URL)
#   - Flutter Linux SDK tarball: shell.hesabix.ir (override with FLUTTER_SDK_TARBALL_URL)
#   - NDK (Side by side): در صورت نبود، از Myket به‌صورت ZIP نصب می‌شود (HESABIX_ANDROID_SDK_MIRROR_BASE)
#   - ایندکس مخزن SDK (addons_list / repository2): با SDK_TEST_BASE_URL از HESABIX_ANDROID_SDK_REPO_MIRROR (پیش‌فرض maven.myket.ir/android/repository/)
#   - در صورت نبود cmdline-tools، نصب از ZIP آینه (commandlinetools-linux-*_latest.zip) تا sdkmanager در دسترس باشد.
#   - لایسنس SDK + نصب platform/build-tools با sdkmanager؛ اگر نصب شبکه‌ای نشد، ZIP از HESABIX_ANDROID_SDK_MIRROR_BASE (مثلاً build-tools_r35_linux.zip و platform-36_r01.zip روی Myket).
#   - خطاهای 503 روی manifestهای sys-img/emulator معمولاً ربطی به بیلد APK ندارند.
#   - Git fallbacks for SDK: FLUTTER_SDK_GIT_URL, then Tsinghua, then Gitee
# Env FLUTTER_SDK_INSTALL_DIR: extract/clone SDK here when not root (default: REPO_ROOT/.flutter_sdk)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

# Hesabix mirrors (defaults; overridden if corresponding env vars are already set)
DEFAULT_PUB_HOSTED_URL="https://f.mirror.hesabix.ir/pub"
DEFAULT_FLUTTER_STORAGE_BASE_URL="https://f.mirror.hesabix.ir/gcs"
DEFAULT_FLUTTER_SDK_TARBALL_URL="https://shell.hesabix.ir/flutter_linux_3.41.1-stable.tar.xz"

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
AUTO_SETUP_ANDROID=false
BOOTSTRAP_ONLY=false
BUILD_FAILED=false
# جزئیات خروجی: 0=ساکت، 1=flutter -v (پیش‌فرض)، 2=flutter -vv
BUILD_ANDROID_VERBOSE="${BUILD_ANDROID_VERBOSE:-1}"
# اگر 1 باشد، حافظه/هسته و آرگومان‌های Gradle به‌صورت خودکار تنظیم می‌شود (غیرفعال: 0)
BUILD_ANDROID_SMART_RESOURCES="${BUILD_ANDROID_SMART_RESOURCES:-1}"
# نصب خودکار NDK از آینهٔ داخلی (Myket) وقتی پوشهٔ ndk/<نسخه> نیست — برای دور زدن تحریم/دانلود گوگل
HESABIX_ANDROID_SDK_MIRROR_BASE="${HESABIX_ANDROID_SDK_MIRROR_BASE:-https://maven.myket.ir/android-sdk}"
HESABIX_SKIP_NDK_MIRROR="${HESABIX_SKIP_NDK_MIRROR:-0}"
# معادل dl.google.com/android/repository/ — برای sdkmanager و AGP (addons_list-6.xml و …)
HESABIX_ANDROID_SDK_REPO_MIRROR="${HESABIX_ANDROID_SDK_REPO_MIRROR:-https://maven.myket.ir/android/repository/}"
HESABIX_SKIP_ANDROID_REPO_MIRROR="${HESABIX_SKIP_ANDROID_REPO_MIRROR:-0}"
# قبل از Gradle: نوشتن hash لایسنس‌های رایج + yes | sdkmanager --licenses و نصب پکیج‌ها (پیش‌فرض platform 36 و build-tools 35)
HESABIX_SKIP_SDK_LICENSE_BOOTSTRAP="${HESABIX_SKIP_SDK_LICENSE_BOOTSTRAP:-0}"
HESABIX_SKIP_SDKMANAGER_INSTALL="${HESABIX_SKIP_SDKMANAGER_INSTALL:-0}"
HESABIX_SDKMANAGER_PACKAGES="${HESABIX_SDKMANAGER_PACKAGES:-platforms;android-36 build-tools;35.0.0}"
# اگر sdkmanager/Gradle نتوانند build-tools یا platform را بگیرند، از ZIP آینه (نام فایل روی Myket با _linux است نه -linux)
HESABIX_SKIP_SDK_ZIP_MIRROR="${HESABIX_SKIP_SDK_ZIP_MIRROR:-0}"
HESABIX_BUILD_TOOLS_LINUX_ZIP="${HESABIX_BUILD_TOOLS_LINUX_ZIP:-build-tools_r35_linux.zip}"
HESABIX_BUILD_TOOLS_LINUX_ZIP_SHA1="${HESABIX_BUILD_TOOLS_LINUX_ZIP_SHA1:-2cfaa0bbb2336e9ec18ed3ecea84fa2e2af607bc}"
HESABIX_BUILD_TOOLS_REVISION="${HESABIX_BUILD_TOOLS_REVISION:-35.0.0}"
HESABIX_PLATFORM_ZIP="${HESABIX_PLATFORM_ZIP:-platform-36_r01.zip}"
HESABIX_PLATFORM_ZIP_SHA1="${HESABIX_PLATFORM_ZIP_SHA1:-feed7041652a3744582bb233506013969dbadb46}"
HESABIX_ANDROID_PLATFORM_API="${HESABIX_ANDROID_PLATFORM_API:-36}"
HESABIX_SKIP_CMDLINE_TOOLS_MIRROR="${HESABIX_SKIP_CMDLINE_TOOLS_MIRROR:-0}"
HESABIX_CMDLINE_TOOLS_LINUX_ZIP="${HESABIX_CMDLINE_TOOLS_LINUX_ZIP:-commandlinetools-linux-11076708_latest.zip}"
HESABIX_CMDLINE_TOOLS_LINUX_ZIP_SHA1="${HESABIX_CMDLINE_TOOLS_LINUX_ZIP_SHA1:-d313adb7aedccf6cf0cfca51ec180f0059f5f8f8}"

print_usage() {
  cat <<EOF
Usage: ./build_android.sh [--project <path>] [--mode <debug|profile|release>] [--api-base-url <url>] [--aab] [--no-aab] [--apk] [--no-apk] [--universal-apk] [--split-apk] [--clean] [--install-deps] [--auto-setup-android] [--bootstrap-only] [--quiet] [--help]

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
  --auto-setup-android
                     Try automatic Android toolchain setup (Java + SDK packages) on Debian/Ubuntu.
  --bootstrap-only   Only setup/check prerequisites; skip pub get, clean, and build steps.
  --quiet            خروجی کم‌حجم (معادل BUILD_ANDROID_VERBOSE=0).
  -h, --help         Show help.

Environment (optional overrides; defaults match deploy.sh Hesabix mirrors):
  PUB_HOSTED_URL              Dart pub mirror (default: $DEFAULT_PUB_HOSTED_URL)
  FLUTTER_STORAGE_BASE_URL    Flutter engine/storage mirror (default: $DEFAULT_FLUTTER_STORAGE_BASE_URL)
  FLUTTER_SDK_TARBALL_URL     Linux SDK tarball URL (default: $DEFAULT_FLUTTER_SDK_TARBALL_URL)
  FLUTTER_SDK_INSTALL_DIR     Where to extract/clone SDK if missing (default: /opt/flutter as root, else REPO_ROOT/.flutter_sdk)
  FLUTTER_SDK_GIT_URL         Preferred git mirror if GitHub clone fails
  HESABIX_SKIP_MIRROR_TRUSTSTORE
                     Skip auto-building a JVM truststore for self-signed Gradle mirror TLS.
  HESABIX_ANDROID_SDK_MIRROR_BASE
                     پایهٔ URL آرشیوهای ZIP آینهٔ اندروید SDK/NDK (پیش‌فرض: Myket).
  HESABIX_SKIP_NDK_MIRROR     اگر 1 باشد، نصب خودکار NDK از آینه غیرفعال می‌شود.
  HESABIX_NDK_REVISION        اجبار نسخهٔ NDK (مثلاً 28.2.13676358)؛ در غیر این صورت از Flutter خوانده می‌شود.
  HESABIX_ANDROID_SDK_REPO_MIRROR
                     پایهٔ ایندکس رسمی مخزن (باید با / تمام شود؛ مثلاً …/android/repository/). روی فرایند Gradle به‌صورت SDK_TEST_BASE_URL اعمال می‌شود.
  HESABIX_SKIP_ANDROID_REPO_MIRROR  اگر 1 باشد، جایگزینی dl.google.com برای ایندکس SDK غیرفعال می‌شود.
  HESABIX_SKIP_SDK_LICENSE_BOOTSTRAP  اگر 1 باشد، مرحلهٔ خودکار لایسنس/نصب sdkmanager اجرا نمی‌شود.
  HESABIX_SKIP_SDKMANAGER_INSTALL     اگر 1 باشد، فقط لایسنس‌ها (فایل + --licenses)؛ نصب پکیج با sdkmanager رد می‌شود.
  HESABIX_SDKMANAGER_PACKAGES         فاصله‌جداشده؛ پیش‌فرض: platforms;android-36 build-tools;35.0.0
  HESABIX_SKIP_SDK_ZIP_MIRROR         اگر 1 باشد، نصب تکمیلی build-tools/platform از ZIP آینه غیرفعال است.
  HESABIX_BUILD_TOOLS_LINUX_ZIP       نام فایل ZIP build-tools روی آینه (پیش‌فرض: build-tools_r35_linux.zip).
  HESABIX_BUILD_TOOLS_LINUX_ZIP_SHA1  SHA1 اختیاری برای همان فایل (پیش‌فرض برای ZIP فعلی Myket).
  HESABIX_BUILD_TOOLS_REVISION        پوشهٔ نصب زیر build-tools/ (پیش‌فرض 35.0.0؛ باید با android.buildToolsVersion در gradle.properties یکی باشد).
  HESABIX_PLATFORM_ZIP                ZIP پلتفرم SDK روی آینه (پیش‌فرض: platform-36_r01.zip).
  HESABIX_PLATFORM_ZIP_SHA1           SHA1 اختیاری برای همان فایل.
  HESABIX_ANDROID_PLATFORM_API        سطح API پوشهٔ platforms/android-<api> (پیش‌فرض 36).
  HESABIX_SKIP_CMDLINE_TOOLS_MIRROR   اگر 1 باشد، نصب خودکار cmdline-tools از ZIP آینه غیرفعال است.
  HESABIX_CMDLINE_TOOLS_LINUX_ZIP     نام فایل ZIP (پیش‌فرض: commandlinetools-linux-11076708_latest.zip).
  HESABIX_CMDLINE_TOOLS_LINUX_ZIP_SHA1  SHA1 اختیاری؛ پیش‌فرض برای ZIP فعلی Myket.
  BUILD_ANDROID_VERBOSE       0=quiet, 1=flutter -v (default), 2=flutter -vv (حداکثر جزئیات).
  BUILD_ANDROID_SMART_RESOURCES 0=بدون تنظیم خودکار heap/workers برای Gradle، 1=فعال (پیش‌فرض).

Usage examples:
  ./build_android.sh
  ./scripts/fix_android_sdk_hesabix_mirror.sh
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

is_debian_like() {
  [ -f /etc/debian_version ]
}

ensure_flutter_command_available() {
  local flutter_bin=""
  if [ -x "/opt/flutter/bin/flutter" ]; then
    flutter_bin="/opt/flutter/bin/flutter"
  elif [ -n "${FLUTTER_SDK_INSTALL_DIR:-}" ] && [ -x "${FLUTTER_SDK_INSTALL_DIR}/bin/flutter" ]; then
    flutter_bin="${FLUTTER_SDK_INSTALL_DIR}/bin/flutter"
  elif [ -x "$REPO_ROOT/.flutter_sdk/bin/flutter" ]; then
    flutter_bin="$REPO_ROOT/.flutter_sdk/bin/flutter"
  fi

  [ -n "$flutter_bin" ] || return 0

  if cmd_exists flutter; then
    return 0
  fi

  if [ "$(id -u)" -eq 0 ] && [ -d "/usr/local/bin" ]; then
    ln -sf "$flutter_bin" /usr/local/bin/flutter 2>/dev/null || true
    if [ -x /usr/local/bin/flutter ]; then
      echo "✓ Flutter command linked globally: /usr/local/bin/flutter -> $flutter_bin"
      return 0
    fi
  fi

  warn "Flutter is installed at: $flutter_bin"
  warn "Command not globally available in your shell PATH."
  warn "Add this to your shell profile (~/.bashrc):"
  warn "  export PATH=\"$(dirname "$flutter_bin"):\$PATH\""
}

resolve_invoking_user() {
  if [ "$(id -u)" -ne 0 ]; then
    return 1
  fi
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    printf '%s' "$SUDO_USER"
    return 0
  fi
  local ln=""
  ln="$(logname 2>/dev/null || true)"
  if [ -n "$ln" ] && [ "$ln" != "root" ]; then
    printf '%s' "$ln"
    return 0
  fi
  return 1
}

resolve_user_home() {
  local u="$1"
  if [ -z "$u" ]; then
    return 1
  fi
  if cmd_exists getent; then
    local h=""
    h="$(getent passwd "$u" | cut -d: -f6 || true)"
    if [ -n "$h" ] && [ -d "$h" ]; then
      printf '%s' "$h"
      return 0
    fi
  fi
  return 1
}

resolve_flutter_bin() {
  local from_path=""
  from_path="$(command -v flutter 2>/dev/null || true)"
  if [ -n "$from_path" ]; then
    printf '%s' "$from_path"
    return 0
  fi
  if [ -x "/opt/flutter/bin/flutter" ]; then
    printf '%s' "/opt/flutter/bin/flutter"
    return 0
  fi
  if [ -n "${FLUTTER_SDK_INSTALL_DIR:-}" ] && [ -x "${FLUTTER_SDK_INSTALL_DIR}/bin/flutter" ]; then
    printf '%s' "${FLUTTER_SDK_INSTALL_DIR}/bin/flutter"
    return 0
  fi
  if [ -x "$REPO_ROOT/.flutter_sdk/bin/flutter" ]; then
    printf '%s' "$REPO_ROOT/.flutter_sdk/bin/flutter"
    return 0
  fi
  return 1
}

fix_flutter_sdk_permissions() {
  [ "$(id -u)" -eq 0 ] || return 0
  local invoke_user=""
  invoke_user="$(resolve_invoking_user 2>/dev/null || true)"
  [ -n "$invoke_user" ] || return 0

  local flutter_bin=""
  flutter_bin="$(resolve_flutter_bin 2>/dev/null || true)"
  [ -n "$flutter_bin" ] || return 0

  local flutter_root=""
  flutter_root="$(cd "$(dirname "$flutter_bin")/.." && pwd)"
  [ -d "$flutter_root" ] || return 0

  # Root-owned caches from previous sudo/root runs break non-root flutter execution.
  local repair_paths=(
    "$flutter_root/bin/cache"
    "$flutter_root/packages/flutter_tools/.dart_tool"
    "$flutter_root/.pub-cache"
  )
  local p
  for p in "${repair_paths[@]}"; do
    [ -e "$p" ] || continue
    chown -R "$invoke_user":"$invoke_user" "$p" 2>/dev/null || true
  done
}

setup_gradle_mirror_init() {
  write_gradle_init_file() {
    local target_home="$1"
    [ -n "$target_home" ] || return 0
    local gradle_home="$target_home/.gradle"
    local init_dir="$gradle_home/init.d"
    local init_file="$init_dir/hesabix-mirror.init.gradle"
    mkdir -p "$init_dir" 2>/dev/null || true
    cat >"$init_file" <<'EOF'
def base = (System.getenv("HESABIX_GRADLE_MIRROR") ?: "https://gradle.mirror.hesabix.ir").replaceAll('/+$','')
def mirrorRepos = { repoHandler ->
    repoHandler.maven { url = uri("${base}/android/maven2/") }
    repoHandler.maven { url = uri("${base}/maven2/") }
    repoHandler.maven { url = uri("${base}/gradle-plugins/") }
    repoHandler.gradlePluginPortal()
    repoHandler.google()
    repoHandler.mavenCentral()
}
settingsEvaluated { settings ->
    settings.pluginManagement { repositories { mirrorRepos(delegate) } }
    def sd = (settings.settingsDir ?: settings.rootDir).canonicalPath.replace('\\', '/')
    if (sd.contains('flutter_tools/gradle')) {
        settings.dependencyResolutionManagement.repositories.clear()
        mirrorRepos(settings.dependencyResolutionManagement.repositories)
    }
}
// Do NOT use allprojects { repositories { ... } } here — breaks Flutter (flutter/flutter#174035).
EOF
  }

  write_gradle_init_file "$HOME"
  local invoke_user=""
  invoke_user="$(resolve_invoking_user 2>/dev/null || true)"
  if [ -n "$invoke_user" ] && cmd_exists getent; then
    local user_home=""
    user_home="$(getent passwd "$invoke_user" | cut -d: -f6 || true)"
    write_gradle_init_file "$user_home"
  fi
  export HESABIX_GRADLE_MIRROR="${HESABIX_GRADLE_MIRROR:-https://gradle.mirror.hesabix.ir}"
}

# curl به آینهٔ hesabix: اول TLS با -k؛ در صورت شکست (مثلاً hairpin DNS) همان URL با --resolve به 127.0.0.1
hesabix_mirror_curl_ok() {
  local u="$1"
  if curl -kfsS --connect-timeout 5 --max-time 25 -o /dev/null "$u" 2>/dev/null; then
    return 0
  fi
  case "$u" in
    https://*hesabix.ir/*)
      local host="${u#https://}"
      host="${host%%/*}"
      local path="${u#https://${host}}"
      if curl -kfsS --connect-timeout 5 --max-time 25 --resolve "${host}:443:127.0.0.1" -o /dev/null "https://${host}${path}" 2>/dev/null; then
        return 0
      fi
      ;;
  esac
  return 1
}

check_gradle_mirror_health() {
  local base="${HESABIX_GRADLE_MIRROR:-https://gradle.mirror.hesabix.ir}"
  base="${base%/}"
  # نمونهٔ کوچک POM روی هر سه مسیر (پروکسی واقعی تا مایکت)
  local urls=(
    "$base/maven2/com/google/guava/guava/33.0.0-jre/guava-33.0.0-jre.pom"
    "$base/android/maven2/androidx/activity/activity/1.8.2/activity-1.8.2.pom"
    "$base/gradle-plugins/org/gradle/kotlin/gradle-kotlin-dsl-plugins/4.3.0/gradle-kotlin-dsl-plugins-4.3.0.pom"
  )
  local u
  for u in "${urls[@]}"; do
    if ! hesabix_mirror_curl_ok "$u"; then
      warn "Gradle mirror endpoint not reachable: $u"
    fi
  done
}

prepare_gradle_user_home() {
  local invoke_user=""
  invoke_user="$(resolve_invoking_user 2>/dev/null || true)"
  local user_home=""

  if [ -n "$invoke_user" ]; then
    user_home="$(resolve_user_home "$invoke_user" 2>/dev/null || true)"
  elif [ -n "${HOME:-}" ]; then
    user_home="$HOME"
  fi

  [ -n "$user_home" ] || return 0

  local gradle_home="${GRADLE_USER_HOME:-$user_home/.gradle}"
  mkdir -p "$gradle_home/wrapper/dists" "$gradle_home/caches" "$gradle_home/init.d" 2>/dev/null || true

  if [ "$(id -u)" -eq 0 ] && [ -n "$invoke_user" ]; then
    chown -R "$invoke_user":"$invoke_user" "$gradle_home" 2>/dev/null || true
  fi
}

# JDK cacerts (برای کپی و افزودن گواهی آینهٔ Gradle در صورت self-signed)
resolve_jdk_cacerts_path() {
  [ -n "${JAVA_HOME:-}" ] || return 1
  local p
  for p in "$JAVA_HOME/lib/security/cacerts" "$JAVA_HOME/jre/lib/security/cacerts"; do
    if [ -f "$p" ] && [ -r "$p" ]; then
      printf '%s' "$p"
      return 0
    fi
  done
  return 1
}

# اگر آینهٔ Gradle با TLS قابل اعتماد برای JVM نیست (مثلاً گواهی self-signed روی nginx)،
# یک truststore در GRADLE_USER_HOME می‌سازیم و JAVA_TOOL_OPTIONS را ست می‌کنیم.
ensure_jvm_trusts_hesabix_gradle_mirror() {
  [ "${HESABIX_SKIP_MIRROR_TRUSTSTORE:-}" = "1" ] && return 0
  [ -n "${JAVA_HOME:-}" ] || return 0

  local jdk_cacerts=""
  jdk_cacerts="$(resolve_jdk_cacerts_path 2>/dev/null || true)"
  [ -n "$jdk_cacerts" ] || return 0

  local base="${HESABIX_GRADLE_MIRROR:-https://gradle.mirror.hesabix.ir}"
  base="${base%/}"
  [ -n "$base" ] || return 0

  # TLS از دید curl سیستم OK است — معمولاً JVM هم بدون کار اضافه OK است.
  if curl -fsS --connect-timeout 5 --max-time 15 -o /dev/null "$base/maven2" 2>/dev/null; then
    return 0
  fi
  # آینه در دسترس نیست — truststore نمی‌سازیم
  if ! curl -kfsS --connect-timeout 5 --max-time 15 -o /dev/null "$base/maven2" 2>/dev/null; then
    return 0
  fi

  local mirror_host="${base#https://}"
  mirror_host="${mirror_host#http://}"
  mirror_host="${mirror_host%%/*}"
  [ -n "$mirror_host" ] || return 0
  case "$base" in
    http://*) return 0 ;;
  esac

  if ! cmd_exists openssl || ! cmd_exists keytool; then
    warn "TLS به آینهٔ Gradle برای curl نامعتبر است؛ برای ساخت truststore به openssl و keytool نیاز است."
    return 0
  fi

  local invoke_user=""
  invoke_user="$(resolve_invoking_user 2>/dev/null || true)"
  local ts_home="${HOME:-}"
  if [ "$(id -u)" -eq 0 ] && [ -n "$invoke_user" ]; then
    ts_home="$(resolve_user_home "$invoke_user" 2>/dev/null || echo "$ts_home")"
  fi
  local ts_dir="${GRADLE_USER_HOME:-$ts_home/.gradle}"
  mkdir -p "$ts_dir" 2>/dev/null || true

  local ts="$ts_dir/hesabix-gradle-mirror-truststore.jks"
  local pem
  pem="$(mktemp "${TMPDIR:-/tmp}/hesabix-mirror.XXXXXX.pem")"
  local ssl_out
  ssl_out="$(mktemp "${TMPDIR:-/tmp}/hesabix-sclient.XXXXXX.pem")"
  if cmd_exists timeout; then
    printf 'Q\n' | timeout 25 openssl s_client -connect "${mirror_host}:443" -servername "$mirror_host" \
      -showcerts 2>/dev/null >"$ssl_out" || true
  else
    printf 'Q\n' | openssl s_client -connect "${mirror_host}:443" -servername "$mirror_host" \
      -showcerts 2>/dev/null >"$ssl_out" || true
  fi
  if ! openssl x509 -in "$ssl_out" -outform PEM >"$pem" 2>/dev/null; then
    rm -f "$pem" "$ssl_out"
    warn "Could not fetch TLS certificate from $mirror_host (openssl)."
    return 0
  fi
  rm -f "$ssl_out"
  if ! grep -q "BEGIN CERTIFICATE" "$pem" 2>/dev/null; then
    rm -f "$pem"
    warn "OpenSSL did not yield a PEM certificate for $mirror_host."
    return 0
  fi

  if ! cp -f "$jdk_cacerts" "$ts" 2>/dev/null; then
    rm -f "$pem"
    warn "Could not copy JDK cacerts to $ts"
    return 0
  fi
  chmod u+w "$ts" 2>/dev/null || true

  keytool -delete -alias hesabix-gradle-mirror -keystore "$ts" -storepass changeit >/dev/null 2>&1 || true
  if ! keytool -importcert -noprompt -trustcacerts -alias hesabix-gradle-mirror \
      -file "$pem" -keystore "$ts" -storepass changeit >/dev/null 2>&1; then
    rm -f "$pem"
    warn "keytool could not import mirror certificate into $ts"
    return 0
  fi
  rm -f "$pem"

  if [ "$(id -u)" -eq 0 ] && [ -n "$invoke_user" ]; then
    chown "$invoke_user":"$invoke_user" "$ts" 2>/dev/null || true
  fi

  local add="-Djavax.net.ssl.trustStore=$ts -Djavax.net.ssl.trustStorePassword=changeit"
  if [ -n "${JAVA_TOOL_OPTIONS:-}" ]; then
    JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS} ${add}"
  else
    JAVA_TOOL_OPTIONS="$add"
  fi
  export JAVA_TOOL_OPTIONS
  echo "✓ JVM truststore for Gradle mirror: $ts (JAVA_TOOL_OPTIONS updated)"
}

set_flutter_mirror_env() {
  export PUB_HOSTED_URL="${PUB_HOSTED_URL:-$DEFAULT_PUB_HOSTED_URL}"
  export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-$DEFAULT_FLUTTER_STORAGE_BASE_URL}"
}

uses_non_google_flutter_storage() {
  case "${FLUTTER_STORAGE_BASE_URL:-}" in
    *storage.googleapis.com*) return 1 ;;
    *) return 0 ;;
  esac
}

flutter_sdk_install_dir() {
  if [ -n "${FLUTTER_SDK_INSTALL_DIR:-}" ]; then
    printf '%s' "$FLUTTER_SDK_INSTALL_DIR"
    return 0
  fi
  if [ "$(id -u)" -eq 0 ]; then
    printf '%s' "/opt/flutter"
    return 0
  fi
  printf '%s' "$REPO_ROOT/.flutter_sdk"
}

# Prefer Hesabix internal tarball then git mirrors (same order as deploy.sh); respects mirrors for pub/engine.
ensure_flutter_sdk() {
  local opt_flutter="/opt/flutter/bin"
  local install_parent install_target tarball_url use_mirror=0

  set_flutter_mirror_env

  if uses_non_google_flutter_storage; then
    use_mirror=1
  fi

  if [ "$use_mirror" -eq 1 ]; then
    if cmd_exists flutter; then
      return 0
    fi
    if [ -x "${opt_flutter}/flutter" ]; then
      export PATH="${opt_flutter}:$PATH"
      git config --global --add safe.directory /opt/flutter 2>/dev/null || true
      return 0
    fi
  else
    if cmd_exists flutter; then
      return 0
    fi
    if [ -x "${opt_flutter}/flutter" ]; then
      export PATH="${opt_flutter}:$PATH"
      git config --global --add safe.directory /opt/flutter 2>/dev/null || true
      return 0
    fi
    local SNAP_FLUTTER_BIN="$HOME/snap/flutter/common/flutter/bin"
    if [ -d "$SNAP_FLUTTER_BIN" ]; then
      export PATH="$PATH:$SNAP_FLUTTER_BIN"
    fi
    if [ -d "${HOME}/snap/flutter/current/flutter/bin" ] && [ -x "${HOME}/snap/flutter/current/flutter/bin/flutter" ]; then
      export PATH="${HOME}/snap/flutter/current/flutter/bin:$PATH"
    fi
    if cmd_exists flutter; then
      return 0
    fi
    local legacy="${FLUTTER_SDK_PATH:-/root/flutter}"
    if [ -d "${legacy}/bin" ]; then
      export PATH="$PATH:${legacy}/bin"
    fi
    if cmd_exists flutter; then
      return 0
    fi
  fi

  tarball_url="${FLUTTER_SDK_TARBALL_URL:-$DEFAULT_FLUTTER_SDK_TARBALL_URL}"
  install_target="$(flutter_sdk_install_dir)"
  install_parent="$(dirname "$install_target")"

  if [ ! -d "$install_target" ] || [ ! -x "$install_target/bin/flutter" ]; then
    warn "Flutter not found; trying internal SDK tarball: $tarball_url"
    mkdir -p "$install_parent" 2>/dev/null || true
    cmd_exists curl || die "curl is required to download Flutter SDK"
    local tmp_tar
    tmp_tar="$(mktemp "${TMPDIR:-/tmp}/flutter_sdk.tar.XXXXXX.xz")"
    if curl -sfL --connect-timeout 15 --max-time 600 -o "$tmp_tar" "$tarball_url"; then
      if tar -xJf "$tmp_tar" -C "$install_parent" 2>/dev/null; then
        rm -f "$tmp_tar"
        if [ ! -x "$install_target/bin/flutter" ]; then
          local single_dir
          single_dir=$(ls -1 "$install_parent" 2>/dev/null | grep -E '^flutter' | head -1 || true)
          if [ -n "$single_dir" ] && [ -d "$install_parent/$single_dir/bin" ] && [ -x "$install_parent/$single_dir/bin/flutter" ]; then
            rm -rf "$install_target" 2>/dev/null || true
            mv "$install_parent/$single_dir" "$install_target"
          fi
        fi
      else
        rm -f "$tmp_tar"
        warn "Failed to extract Flutter tarball"
      fi
    else
      rm -f "$tmp_tar"
      warn "Internal tarball not available from $tarball_url"
    fi
  fi

  if [ -x "$install_target/bin/flutter" ]; then
    export PATH="$install_target/bin:$PATH"
    git config --global --add safe.directory "$install_target" 2>/dev/null || true
    return 0
  fi

  if [ "$use_mirror" -eq 0 ] && cmd_exists snap && ! snap list flutter 2>/dev/null | grep -q flutter; then
    warn "Trying: snap install flutter --classic (may use Google storage)"
    if snap install flutter --classic 2>/dev/null; then
      export PATH="/snap/bin:$PATH"
      cmd_exists flutter && return 0
    fi
  fi

  warn "Installing Flutter SDK via git clone into $install_target ..."
  mkdir -p "$install_parent"
  cmd_exists git || die "git is required to clone Flutter SDK"
  rm -rf "$install_target" 2>/dev/null || true
  local cloned=0
  if git clone --depth 1 --branch stable "https://github.com/flutter/flutter.git" "$install_target" 2>/dev/null; then
    cloned=1
  else
    local repo_url
    for repo_url in "${FLUTTER_SDK_GIT_URL:-}" \
      "https://mirrors.tuna.tsinghua.edu.cn/git/flutter-sdk.git" \
      "https://gitee.com/mirrors/Flutter.git"; do
      [ -z "$repo_url" ] && continue
      if git clone --depth 1 --branch stable "$repo_url" "$install_target" 2>/dev/null; then
        cloned=1
        break
      fi
      rm -rf "$install_target" 2>/dev/null || true
    done
  fi
  [ "$cloned" -eq 1 ] || die "Flutter SDK install failed. Set FLUTTER_SDK_PATH or install Flutter manually."

  export PATH="$install_target/bin:$PATH"
  git config --global --add safe.directory "$install_target" 2>/dev/null || true
  cmd_exists flutter || die "Flutter binary missing after clone: $install_target/bin/flutter"
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
    --auto-setup-android)
      AUTO_SETUP_ANDROID=true; shift ;;
    --bootstrap-only)
      BOOTSTRAP_ONLY=true; shift ;;
    --quiet)
      BUILD_ANDROID_VERBOSE=0; shift ;;
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

set_flutter_mirror_env
ensure_flutter_sdk
ensure_flutter_command_available
fix_flutter_sdk_permissions

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

echo "Using Pub Hosted URL: $PUB_HOSTED_URL"
echo "Using Flutter Storage URL: $FLUTTER_STORAGE_BASE_URL"

# Configure Android SDK and Java environment
setup_android_env() {
  # Detect Android SDK from common Linux locations
  local android_sdk_path="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  local candidates=(
    "$android_sdk_path"
    "/opt/android-sdk"
    "/usr/lib/android-sdk"
    "$HOME/Android/Sdk"
    "$HOME/Android/sdk"
  )
  local p
  android_sdk_path=""
  for p in "${candidates[@]}"; do
    [ -n "$p" ] || continue
    if [ -d "$p" ]; then
      android_sdk_path="$p"
      break
    fi
  done

  if [ -d "$android_sdk_path" ]; then
    export ANDROID_SDK_ROOT="$android_sdk_path"
    export ANDROID_HOME="$android_sdk_path"
    export PATH="$PATH:$android_sdk_path/cmdline-tools/latest/bin:$android_sdk_path/platform-tools"
    echo "✓ Android SDK found: $ANDROID_SDK_ROOT"
    echo "  NDK در صورت نبود، از آینهٔ داخلی نصب می‌شود (پیش‌فرض: $HESABIX_ANDROID_SDK_MIRROR_BASE). غیرفعال: HESABIX_SKIP_NDK_MIRROR=1"
    hesabix_apply_android_sdk_repository_mirror
  else
    warn "Android SDK not found in common paths"
    warn "Please set ANDROID_SDK_ROOT or ANDROID_HOME environment variable"
  fi

  # Detect Java
  local java_home="${JAVA_HOME:-}"
  if [ -z "$java_home" ]; then
    # Try to find Java 17 or newer
    if [ -d "/usr/lib/jvm/java-21-openjdk-amd64" ]; then
      java_home="/usr/lib/jvm/java-21-openjdk-amd64"
    elif [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
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

# جلوگیری از dl.google.com/android/repository/ برای addons_list و repository2 (sdklib / AGP)
hesabix_apply_android_sdk_repository_mirror() {
  if [ "${HESABIX_SKIP_ANDROID_REPO_MIRROR:-0}" = "1" ]; then
    unset SDK_TEST_BASE_URL 2>/dev/null || true
    return 0
  fi
  local base="${HESABIX_ANDROID_SDK_REPO_MIRROR:-}"
  [ -n "$base" ] || return 0
  case "$base" in
    */) ;;
    *) base="${base}/" ;;
  esac
  export SDK_TEST_BASE_URL="$base"
  echo "✓ Android SDK repository index mirror (SDK_TEST_BASE_URL): $SDK_TEST_BASE_URL"
  echo "  اگر خطای 404 یا TLS بود، آدرس را با HESABIX_ANDROID_SDK_REPO_MIRROR اصلاح کنید (گاهی زیر android-sdk/ است نه android/repository/)."
}

hesabix_license_file_append_line_if_missing() {
  local file="$1"
  local line="$2"
  [ -n "$line" ] || return 0
  mkdir -p "$(dirname "$file")" 2>/dev/null || return 1
  if [ ! -f "$file" ]; then
    : >"$file" 2>/dev/null || return 1
  fi
  if grep -Fxq "$line" "$file" 2>/dev/null; then
    return 0
  fi
  printf '\n%s\n' "$line" >>"$file" 2>/dev/null || return 1
  return 0
}

# hashهای رایج android-sdk-license / preview برای CI و سرور بدون تعامل؛ در کنار sdkmanager --licenses
hesabix_seed_android_sdk_license_files() {
  local sdk="${1:-}"
  [ -n "$sdk" ] && [ -d "$sdk" ] || return 0
  local lic_dir="$sdk/licenses"
  if ! mkdir -p "$lic_dir" 2>/dev/null; then
    warn "نوشتن در $lic_dir ممکن نیست؛ برای پذیرش لایسنس root یا دسترسی نوشتن روی SDK لازم است."
    return 1
  fi
  local f_stable="$lic_dir/android-sdk-license"
  local f_preview="$lic_dir/android-sdk-preview-license"
  local h
  for h in \
    24333f8a63b6825ea9c5514f83c2829b004d1fee \
    8933bad161af4178b1185d1a37fbf41ea5269c55 \
    d56f5187479451eabf01fb78af6dfcb131a6481e \
    601085b94cd77f0b54ff86406957099ebe79c4d6 \
    33b6a2b64607f11b759f320ef9dff4ae5c47d97a \
    59dd11fc20c2cb68f389a776437dbcdbd9989783; do
    hesabix_license_file_append_line_if_missing "$f_stable" "$h" || true
  done
  hesabix_license_file_append_line_if_missing "$f_preview" "84831b9409646a918e30573bab4c9c91346d8abd" || true
  echo "✓ فایل‌های لایسنس SDK (در صورت امکان) به‌روز شدند: $lic_dir"
}

resolve_sdkmanager_bin() {
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  local sm=""
  for sm in \
    "${sdk:+$sdk/cmdline-tools/latest/bin/sdkmanager}" \
    "${sdk:+$sdk/cmdline-tools/bin/sdkmanager}"; do
    [ -n "$sm" ] && [ -x "$sm" ] && printf '%s' "$sm" && return 0
  done
  sm="$(command -v sdkmanager 2>/dev/null || true)"
  if [ -n "$sm" ] && [ -x "$sm" ]; then
    printf '%s' "$sm"
    return 0
  fi
  return 1
}

# نصب Android SDK Command-line Tools از ZIP آینه (مسیر استاندارد: cmdline-tools/latest/bin/sdkmanager)
hesabix_ensure_cmdline_tools_from_internal_mirror() {
  [ "${HESABIX_SKIP_CMDLINE_TOOLS_MIRROR:-0}" != "1" ] || return 0
  [ "$(uname -s 2>/dev/null || echo)" = "Linux" ] || return 0
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  [ -n "$sdk" ] && [ -d "$sdk" ] || return 0
  if resolve_sdkmanager_bin >/dev/null 2>&1; then
    echo "✓ sdkmanager از قبل در دسترس است."
    return 0
  fi
  if ! cmd_exists unzip; then
    warn "برای نصب cmdline-tools از ZIP، unzip لازم است."
    return 0
  fi
  if ! cmd_exists sha1sum; then
    warn "برای تأیید checksum cmdline-tools، sha1sum لازم است."
    return 0
  fi
  if ! cmd_exists curl && ! cmd_exists wget; then
    warn "برای دانلود cmdline-tools، curl یا wget لازم است."
    return 0
  fi

  local base="${HESABIX_ANDROID_SDK_MIRROR_BASE%/}"
  local zname="${HESABIX_CMDLINE_TOOLS_LINUX_ZIP:-commandlinetools-linux-11076708_latest.zip}"
  local zsha="${HESABIX_CMDLINE_TOOLS_LINUX_ZIP_SHA1:-}"
  local url="$base/$zname"
  local tmp=""
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/hesabix-clt.XXXXXX")"
  local zip_path="$tmp/$zname"

  echo "در حال نصب Android cmdline-tools از آینهٔ ZIP…"
  echo "  URL: $url"
  local ok=1
  if cmd_exists curl; then
    curl -fL --connect-timeout 30 --retry 3 --retry-delay 2 -o "$zip_path" "$url" || ok=0
  else
    wget -q --timeout=30 -O "$zip_path" "$url" || ok=0
  fi
  if [ "$ok" != "1" ]; then
    warn "دانلود cmdline-tools ZIP ناموفق بود."
    rm -rf "$tmp"
    return 0
  fi
  if [ -n "$zsha" ]; then
    local got=""
    got="$(sha1sum "$zip_path" | awk '{print $1}')"
    if [ "$got" != "$zsha" ]; then
      warn "SHA1 cmdline-tools ZIP با مقدار انتظار یکی نیست (انتظار: $zsha ، دریافت: $got)."
      rm -rf "$tmp"
      return 0
    fi
  fi
  mkdir -p "$tmp/ex"
  if ! unzip -q "$zip_path" -d "$tmp/ex"; then
    warn "باز کردن ZIP cmdline-tools ناموفق بود."
    rm -rf "$tmp"
    return 0
  fi
  if [ ! -d "$tmp/ex/cmdline-tools" ] || [ ! -x "$tmp/ex/cmdline-tools/bin/sdkmanager" ]; then
    warn "ساختار ZIP cmdline-tools نامعتبر بود."
    rm -rf "$tmp"
    return 0
  fi
  mkdir -p "$sdk/cmdline-tools"
  rm -rf "$sdk/cmdline-tools/latest"
  mv "$tmp/ex/cmdline-tools" "$sdk/cmdline-tools/latest"
  rm -rf "$tmp"
  if [ "$(id -u)" -eq 0 ]; then
    local iu=""
    iu="$(resolve_invoking_user 2>/dev/null || true)"
    [ -n "$iu" ] && chown -R "$iu:$iu" "$sdk/cmdline-tools/latest" 2>/dev/null || true
  fi
  export PATH="$PATH:$sdk/cmdline-tools/latest/bin:$sdk/platform-tools"
  echo "✓ cmdline-tools نصب شد: $sdk/cmdline-tools/latest"
}

# پذیرش لایسنس و نصب platform/build-tools قبل از Gradle (رفع خطای «licences have not been accepted»)
hesabix_bootstrap_android_sdk_licenses_and_packages() {
  [ "${HESABIX_SKIP_SDK_LICENSE_BOOTSTRAP:-0}" != "1" ] || return 0
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  [ -n "$sdk" ] && [ -d "$sdk" ] || return 0

  hesabix_seed_android_sdk_license_files "$sdk" || true

  local sm=""
  sm="$(resolve_sdkmanager_bin 2>/dev/null || true)"
  if [ -z "$sm" ]; then
    warn "sdkmanager پیدا نشد (معمولاً android-sdk-cmdline-tools). فقط hash لایسنس نوشته شد؛ اگر بیلد باز هم لایسنس خواست، cmdline-tools را نصب کنید یا yes | sdkmanager --licenses را دستی اجرا کنید."
    return 0
  fi

  echo "در حال پذیرش لایسنس‌های SDK با sdkmanager… ($sm)"
  if ! yes 2>/dev/null | "$sm" --licenses >/dev/null 2>&1; then
    warn "sdkmanager --licenses ناموفق بود (شاید آینهٔ repository موقتاً 503 بدهد). hashهای محلی همچنان اعمال شده‌اند."
  fi

  [ "${HESABIX_SKIP_SDKMANAGER_INSTALL:-0}" != "1" ] || return 0
  local pkg_line="${HESABIX_SDKMANAGER_PACKAGES:-}"
  [ -n "$pkg_line" ] || return 0
  local -a pkgs=()
  read -r -a pkgs <<<"$pkg_line"
  [ "${#pkgs[@]}" -gt 0 ] || return 0

  echo "در حال نصب پکیج‌های SDK (sdkmanager): ${pkgs[*]}"
  if ! yes 2>/dev/null | "$sm" "${pkgs[@]}"; then
    warn "نصب پکیج با sdkmanager ناموفق بود؛ Gradle ممکن است خودش دانلود کند اگر لایسنس‌ها پذیرفته شده باشند."
  fi
}

# تکمیل build-tools و platform از ZIP آینه (وقتی sdkmanager/گوگل در دسترس نیستند؛ نام صحیح روی Myket: *_linux.zip)
hesabix_ensure_sdk_components_from_internal_mirror() {
  [ "${HESABIX_SKIP_SDK_ZIP_MIRROR:-0}" != "1" ] || return 0
  [ "$(uname -s 2>/dev/null || echo)" = "Linux" ] || return 0
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  [ -n "$sdk" ] && [ -d "$sdk" ] || return 0

  if ! cmd_exists unzip; then
    warn "برای نصب build-tools/platform از ZIP، unzip لازم است."
    return 0
  fi
  if ! cmd_exists sha1sum; then
    warn "برای تأیید checksum ZIPهای SDK، sha1sum لازم است."
    return 0
  fi
  if ! cmd_exists curl && ! cmd_exists wget; then
    warn "برای دانلود ZIPهای SDK، curl یا wget لازم است."
    return 0
  fi

  local base="${HESABIX_ANDROID_SDK_MIRROR_BASE%/}"

  local bt_rev="${HESABIX_BUILD_TOOLS_REVISION:-35.0.0}"
  local bt_home="$sdk/build-tools/$bt_rev"
  if [ -x "$bt_home/aapt2" ] || [ -x "$bt_home/d8" ]; then
    echo "✓ Android SDK Build-Tools از قبل نصب است: $bt_home"
  else
    local tmp_bt=""
    tmp_bt="$(mktemp -d "${TMPDIR:-/tmp}/hesabix-btzip.XXXXXX")"
    local bt_zip="${HESABIX_BUILD_TOOLS_LINUX_ZIP:-build-tools_r35_linux.zip}"
    local bt_sha="${HESABIX_BUILD_TOOLS_LINUX_ZIP_SHA1:-}"
    local bt_url="$base/$bt_zip"
    local bt_path="$tmp_bt/$bt_zip"
    echo "در حال نصب Build-Tools $bt_rev از آینهٔ ZIP…"
    echo "  URL: $bt_url"
    local dl_ok=1
    if cmd_exists curl; then
      curl -fL --connect-timeout 30 --retry 3 --retry-delay 2 -o "$bt_path" "$bt_url" || dl_ok=0
    else
      wget -q --timeout=30 -O "$bt_path" "$bt_url" || dl_ok=0
    fi
    if [ "$dl_ok" != "1" ]; then
      warn "دانلود build-tools ZIP ناموفق بود؛ سراغ platform می‌رویم."
    else
      if [ -n "$bt_sha" ]; then
        local got=""
        got="$(sha1sum "$bt_path" | awk '{print $1}')"
        if [ "$got" != "$bt_sha" ]; then
          warn "SHA1 build-tools ZIP با مقدار انتظار یکی نیست (انتظار: $bt_sha ، دریافت: $got)."
          dl_ok=0
        fi
      fi
    fi
    if [ "$dl_ok" = "1" ]; then
      mkdir -p "$tmp_bt/bt-extract"
      if unzip -q "$bt_path" -d "$tmp_bt/bt-extract"; then
        local top=""
        top="$(find "$tmp_bt/bt-extract" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
        if [ -n "$top" ] && [ -f "$top/source.properties" ]; then
          local zip_rev=""
          zip_rev="$(grep -E '^Pkg.Revision=' "$top/source.properties" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '\r' | awk '{print $1}')"
          if [ -n "$zip_rev" ] && [ "$zip_rev" = "$bt_rev" ]; then
            mkdir -p "$sdk/build-tools"
            rm -rf "$bt_home"
            mv "$top" "$bt_home"
            if [ "$(id -u)" -eq 0 ]; then
              local _iu=""
              _iu="$(resolve_invoking_user 2>/dev/null || true)"
              [ -n "$_iu" ] && chown -R "$_iu:$_iu" "$bt_home" 2>/dev/null || true
            fi
            echo "✓ Build-Tools نصب شد: $bt_home"
          else
            warn "نسخهٔ داخل ZIP build-tools ($zip_rev) با HESABIX_BUILD_TOOLS_REVISION ($bt_rev) یکی نیست؛ نصب ZIP رد شد."
          fi
        else
          warn "ساختار ZIP build-tools نامعتبر بود (source.properties نیست)."
        fi
      else
        warn "باز کردن ZIP build-tools ناموفق بود."
      fi
    fi
    rm -rf "$tmp_bt"
  fi

  local api="${HESABIX_ANDROID_PLATFORM_API:-36}"
  local plat_home="$sdk/platforms/android-$api"
  if [ -f "$plat_home/android.jar" ]; then
    echo "✓ Android SDK Platform از قبل نصب است: $plat_home"
  else
    local tmp_pl=""
    tmp_pl="$(mktemp -d "${TMPDIR:-/tmp}/hesabix-plzip.XXXXXX")"
    local p_zip="${HESABIX_PLATFORM_ZIP:-platform-36_r01.zip}"
    local p_sha="${HESABIX_PLATFORM_ZIP_SHA1:-}"
    local p_url="$base/$p_zip"
    local p_path="$tmp_pl/$p_zip"
    echo "در حال نصب Platform android-$api از آینهٔ ZIP…"
    echo "  URL: $p_url"
    local pok=1
    if cmd_exists curl; then
      curl -fL --connect-timeout 30 --retry 3 --retry-delay 2 -o "$p_path" "$p_url" || pok=0
    else
      wget -q --timeout=30 -O "$p_path" "$p_url" || pok=0
    fi
    if [ "$pok" != "1" ]; then
      warn "دانلود platform ZIP ناموفق بود."
    else
      if [ -n "$p_sha" ]; then
        local pg=""
        pg="$(sha1sum "$p_path" | awk '{print $1}')"
        if [ "$pg" != "$p_sha" ]; then
          warn "SHA1 platform ZIP با مقدار انتظار یکی نیست (انتظار: $p_sha ، دریافت: $pg)."
          pok=0
        fi
      fi
    fi
    if [ "$pok" = "1" ]; then
      mkdir -p "$tmp_pl/pl-extract"
      if unzip -q "$p_path" -d "$tmp_pl/pl-extract"; then
        local ptop=""
        ptop="$(find "$tmp_pl/pl-extract" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
        if [ -n "$ptop" ] && [ -f "$ptop/android.jar" ]; then
          local zip_api=""
          zip_api="$(grep -E '^AndroidVersion.ApiLevel=' "$ptop/source.properties" 2>/dev/null | head -n 1 | cut -d= -f2 | tr -d '\r' | tr -d ' ')"
          if [ -z "$zip_api" ] || [ "$zip_api" = "$api" ]; then
            mkdir -p "$sdk/platforms"
            rm -rf "$plat_home"
            mv "$ptop" "$plat_home"
            if [ "$(id -u)" -eq 0 ]; then
              local _iu2=""
              _iu2="$(resolve_invoking_user 2>/dev/null || true)"
              [ -n "$_iu2" ] && chown -R "$_iu2:$_iu2" "$plat_home" 2>/dev/null || true
            fi
            echo "✓ Platform نصب شد: $plat_home"
          else
            warn "API داخل ZIP platform ($zip_api) با HESABIX_ANDROID_PLATFORM_API ($api) یکی نیست؛ نصب ZIP رد شد."
          fi
        else
          warn "ساختار ZIP platform نامعتبر بود."
        fi
      else
        warn "باز کردن ZIP platform ناموفق بود."
      fi
    fi
    rm -rf "$tmp_pl"
  fi
}

# نگاشت ndk;<revision> → فایل zip لینوکس Myket + sha1 (هم‌راستا با کاتالوگ maven.myket.ir/android-sdk)
hesabix_ndk_mirror_zip_sha1() {
  local rev="${1:-}"
  case "$rev" in
    30.0.14904198) echo "android-ndk-r30-beta1-linux.zip|26b746e5a1e7ac3371f2a862a2f52a7c0740aa8a" ;;
    29.0.14206865) echo "android-ndk-r29-linux.zip|87e2bb7e9be5d6a1c6cdf5ec40dd4e0c6d07c30b" ;;
    29.0.14033849) echo "android-ndk-r29-beta4-linux.zip|ecba553458e222a7c9b24945a3690e80a4730104" ;;
    29.0.13846066) echo "android-ndk-r29-beta3-linux.zip|277ccc0f9c56b05dd88e0af39446cd9402b13b0c" ;;
    29.0.13599879) echo "android-ndk-r29-beta2-linux.zip|06c29d6764526fb51407d08fcead41247ddd3b70" ;;
    29.0.13113456) echo "android-ndk-r29-beta1-linux.zip|ec2d8801e42009edf66be853c1bab9ba216378f9" ;;
    28.2.13676358) echo "android-ndk-r28c-linux.zip|a7b54a5de87fecd125a17d54f73c446199e72a64" ;;
    28.1.13356709) echo "android-ndk-r28b-linux.zip|f574d3165405bd59ffc5edaadac02689075a729f" ;;
    28.0.13004108) echo "android-ndk-r28-linux.zip|894f469c5192a116d21f412de27966140a530ebc" ;;
    28.0.12916984) echo "android-ndk-r28-beta3-linux.zip|69348e24577122339b3996d2ef1ac4e6f7f5d627" ;;
    28.0.12674087) echo "android-ndk-r28-beta2-linux.zip|4b901eeb50a76ba521e4eb1e611cb43658b54440" ;;
    28.0.12433566) echo "android-ndk-r28-beta1-linux.zip|92dd6d941340624c4fc702ebc7e7cbd6faeb703d" ;;
    27.3.13750724) echo "android-ndk-r27d-linux.zip|22105e410cf29afcf163760cc95522b9fb981121" ;;
    27.2.12479018) echo "android-ndk-r27c-linux.zip|090e8083a715fdb1a3e402d0763c388abb03fb4e" ;;
    27.1.12297006) echo "android-ndk-r27b-linux.zip|6fc476b2e57d7c01ac0c95817746b927035b9749" ;;
    27.0.12077973) echo "android-ndk-r27-linux.zip|5e5cd517bdb98d7e0faf2c494a3041291e71bdcc" ;;
    27.0.11902837) echo "android-ndk-r27-beta2-linux.zip|93103e182405b9d7757231a1d9dad58937a6374b" ;;
    27.0.11718014) echo "android-ndk-r27-beta1-linux.zip|35a78f7544ccc72d8438d8ea2feb7f252a062abe" ;;
    26.3.11579264) echo "android-ndk-r26d-linux.zip|fcdad75a765a46a9cf6560353f480db251d14765" ;;
    26.2.11394342) echo "android-ndk-r26c-linux.zip|7faebe2ebd3590518f326c82992603170f07c96e" ;;
    26.1.10909125) echo "android-ndk-r26b-linux.zip|fdf33d9f6c1b3f16e5459d53a82c7d2201edbcc4" ;;
    26.0.10792818) echo "android-ndk-r26-linux.zip|d3bef08e0e43acd9e7815538df31818692d548bb" ;;
    26.0.10636728) echo "android-ndk-r26-rc1-linux.zip|6ec8c08204409fea4853bf0317660caadabfc8b0" ;;
    26.0.10404224) echo "android-ndk-r26-beta1-linux.zip|fb5e34313766764d9654b04603e69af813b18799" ;;
    25.2.9519653) echo "android-ndk-r25c-linux.zip|53af80a1cce9144025b81c78c8cd556bff42bd0e" ;;
    25.1.8937393) echo "android-ndk-r25b-linux.zip|e27dcb9c8bcaa77b78ff68c3f23abcf6867959eb" ;;
    25.0.8775105) echo "android-ndk-r25-linux.zip|9fce956edb6abd5aca42acf6bbfb21a90a67f75b" ;;
    24.0.8215888) echo "android-ndk-r24-linux.zip|eceb18f147282eb93615eff1ad84a9d3962fbb31" ;;
    23.2.8568313) echo "android-ndk-r23c-linux.zip|e5053c126a47e84726d9f7173a04686a71f9a67a" ;;
    23.1.7779620) echo "android-ndk-r23b-linux.zip|f47ec4c4badd11e9f593a8450180884a927c330d" ;;
    23.0.7599858) echo "android-ndk-r23-linux.zip|9bad35f442caeda747780ba1dd92f2d98609d9cd" ;;
    *) echo "" ;;
  esac
}

detect_flutter_ndk_revision() {
  local flutter_bin=""
  flutter_bin="$(resolve_flutter_bin 2>/dev/null || true)"
  [ -n "$flutter_bin" ] || return 1
  local root=""
  root="$(cd "$(dirname "$flutter_bin")/.." && pwd)"
  local gu="$root/packages/flutter_tools/lib/src/android/gradle_utils.dart"
  if [ ! -f "$gu" ]; then
    return 1
  fi
  local line=""
  line="$(grep -E "^\s*const ndkVersion = '" "$gu" 2>/dev/null | head -n 1 || true)"
  if [ -z "$line" ]; then
    return 1
  fi
  printf '%s' "$line" | sed -n "s/.*const ndkVersion = '\\([^']*\\)'.*/\\1/p"
}

hesabix_ensure_ndk_from_internal_mirror() {
  [ "${HESABIX_SKIP_NDK_MIRROR:-0}" != "1" ] || return 0
  [ "$(uname -s 2>/dev/null || echo)" = "Linux" ] || return 0
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  [ -n "$sdk" ] && [ -d "$sdk" ] || return 0

  local rev=""
  if [ -n "${HESABIX_NDK_REVISION:-}" ]; then
    rev="$HESABIX_NDK_REVISION"
  else
    rev="$(detect_flutter_ndk_revision 2>/dev/null || true)"
  fi
  [ -n "$rev" ] || rev="28.2.13676358"

  local ndk_home="$sdk/ndk/$rev"
  if [ -f "$ndk_home/source.properties" ]; then
    echo "✓ NDK از قبل نصب است: $ndk_home"
    return 0
  fi

  local pair=""
  pair="$(hesabix_ndk_mirror_zip_sha1 "$rev")"
  if [ -z "$pair" ]; then
    warn "NDK $rev در جدول آینهٔ اسکریپت نیست؛ HESABIX_NDK_REVISION یا HESABIX_SKIP_NDK_MIRROR=1 را تنظیم کنید یا نسخه را به hesabix_ndk_mirror_zip_sha1 اضافه کنید."
    return 0
  fi
  local zip_name="${pair%%|*}"
  local want_sha="${pair#*|}"
  local base="${HESABIX_ANDROID_SDK_MIRROR_BASE%/}"
  local url="$base/$zip_name"

  if ! cmd_exists curl && ! cmd_exists wget; then
    warn "برای دانلود NDK از آینه، curl یا wget لازم است."
    return 0
  fi
  if ! cmd_exists unzip; then
    warn "برای نصب NDK، unzip لازم است (نصب: apt install unzip)."
    return 0
  fi
  if ! cmd_exists sha1sum; then
    warn "برای تأیید checksum، sha1sum لازم است."
    return 0
  fi

  echo "در حال نصب NDK $rev از آینهٔ داخلی (بدون گوگل)…"
  echo "  URL: $url"

  local tmp=""
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/hesabix-ndk.XXXXXX")"
  local zip_path="$tmp/$zip_name"

  if cmd_exists curl; then
    if ! curl -fL --connect-timeout 30 --retry 3 --retry-delay 2 -o "$zip_path" "$url"; then
      warn "دانلود NDK از آینه ناموفق بود."
      rm -rf "$tmp"
      return 0
    fi
  else
    if ! wget -q --timeout=30 -O "$zip_path" "$url"; then
      warn "دانلود NDK از آینه ناموفق بود."
      rm -rf "$tmp"
      return 0
    fi
  fi

  local got_sha=""
  got_sha="$(sha1sum "$zip_path" | awk '{print $1}')"
  if [ "$got_sha" != "$want_sha" ]; then
    warn "SHA1 فایل NDK با کاتالوگ آینه یکی نیست (انتظار: $want_sha ، دریافت: $got_sha). فایل حذف می‌شود."
    rm -rf "$tmp"
    return 0
  fi

  mkdir -p "$tmp/extract"
  if ! unzip -q "$zip_path" -d "$tmp/extract"; then
    warn "باز کردن ZIP ناموفق بود."
    rm -rf "$tmp"
    return 0
  fi
  local top=""
  top="$(find "$tmp/extract" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [ -z "$top" ] || [ ! -d "$top" ]; then
    warn "ساختار ZIP نامعتبر بود."
    rm -rf "$tmp"
    return 0
  fi

  mkdir -p "$sdk/ndk"
  rm -rf "$ndk_home"
  mv "$top" "$ndk_home"

  if [ "$(id -u)" -eq 0 ]; then
    local iu=""
    iu="$(resolve_invoking_user 2>/dev/null || true)"
    if [ -n "$iu" ]; then
      chown -R "$iu:$iu" "$ndk_home" 2>/dev/null || true
    fi
  fi

  rm -rf "$tmp"

  if [ -f "$ndk_home/source.properties" ]; then
    echo "✓ NDK نصب شد: $ndk_home"
  else
    warn "پوشهٔ NDK نصب شد اما source.properties پیدا نشد؛ بیلد را دوباره امتحان کنید."
  fi
}

auto_setup_android_toolchain() {
  [ "$AUTO_SETUP_ANDROID" = true ] || return 0
  echo "Auto setup requested: checking Android toolchain dependencies..."

  if ! is_debian_like; then
    warn "Auto setup currently supports Debian/Ubuntu only. Skipping."
    return 0
  fi

  if [ "$(id -u)" -ne 0 ]; then
    warn "Auto setup requires root privileges for apt install. Re-run with sudo or install manually."
    return 0
  fi

  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y || warn "apt-get update failed"

  if ! cmd_exists java; then
    echo "Installing Java 17..."
    apt-get install -y openjdk-17-jdk || warn "Failed to install openjdk-17-jdk"
  fi

  if [ ! -d "${ANDROID_SDK_ROOT:-}" ] && [ ! -d "${ANDROID_HOME:-}" ]; then
    echo "Installing Android SDK packages..."
    apt-get install -y android-sdk android-sdk-platform-tools-common adb || warn "Failed to install Android SDK packages"
  fi
}

flutter_run() {
  local flutter_bin=""
  flutter_bin="$(resolve_flutter_bin 2>/dev/null || true)"
  [ -n "$flutter_bin" ] || flutter_bin="flutter"

  local invoke_user=""
  invoke_user="$(resolve_invoking_user 2>/dev/null || true)"
  local target_home="${HOME:-}"
  if [ -n "$invoke_user" ]; then
    target_home="$(resolve_user_home "$invoke_user" 2>/dev/null || echo "$target_home")"
  fi
  local target_gradle_home="${GRADLE_USER_HOME:-$target_home/.gradle}"

  local flutter_args=()
  if [[ "${1:-}" == "build" ]] && [[ "${BUILD_ANDROID_VERBOSE:-1}" != "0" ]]; then
    if [[ "${BUILD_ANDROID_VERBOSE}" == "2" ]]; then
      flutter_args+=(-vv)
    else
      flutter_args+=(-v)
    fi
  fi
  flutter_args+=("$@")

  local mk="${MAKEFLAGS:-}"
  local cm="${CMAKE_BUILD_PARALLEL_LEVEL:-}"
  local sdk_repo="${SDK_TEST_BASE_URL:-}"

  if [ "$(id -u)" -eq 0 ] && [ -n "$invoke_user" ]; then
    if cmd_exists runuser; then
      runuser -u "$invoke_user" -- env HOME="$target_home" GRADLE_USER_HOME="$target_gradle_home" PATH="$PATH" PUB_HOSTED_URL="$PUB_HOSTED_URL" FLUTTER_STORAGE_BASE_URL="$FLUTTER_STORAGE_BASE_URL" ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-}" ANDROID_HOME="${ANDROID_HOME:-}" JAVA_HOME="${JAVA_HOME:-}" JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-}" SDK_TEST_BASE_URL="${sdk_repo}" MAKEFLAGS="$mk" CMAKE_BUILD_PARALLEL_LEVEL="$cm" "$flutter_bin" "${flutter_args[@]}"
    else
      sudo -u "$invoke_user" --preserve-env=PATH,PUB_HOSTED_URL,FLUTTER_STORAGE_BASE_URL,ANDROID_SDK_ROOT,ANDROID_HOME,JAVA_HOME,JAVA_TOOL_OPTIONS,HOME,GRADLE_USER_HOME,MAKEFLAGS,CMAKE_BUILD_PARALLEL_LEVEL,SDK_TEST_BASE_URL HOME="$target_home" GRADLE_USER_HOME="$target_gradle_home" MAKEFLAGS="$mk" CMAKE_BUILD_PARALLEL_LEVEL="$cm" SDK_TEST_BASE_URL="${sdk_repo}" "$flutter_bin" "${flutter_args[@]}"
    fi
  else
    HOME="$target_home" GRADLE_USER_HOME="$target_gradle_home" JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-}" SDK_TEST_BASE_URL="${sdk_repo}" MAKEFLAGS="$mk" CMAKE_BUILD_PARALLEL_LEVEL="$cm" "$flutter_bin" "${flutter_args[@]}"
  fi
}

ensure_android_prerequisites() {
  local missing=0
  if [ ! -d "${ANDROID_SDK_ROOT:-}" ] && [ ! -d "${ANDROID_HOME:-}" ]; then
    warn "Android SDK is missing."
    missing=1
  fi
  if [ -z "${JAVA_HOME:-}" ] && ! cmd_exists java; then
    warn "Java runtime is missing."
    missing=1
  fi
  return "$missing"
}

auto_setup_android_toolchain
setup_android_env
hesabix_ensure_cmdline_tools_from_internal_mirror
hesabix_bootstrap_android_sdk_licenses_and_packages
hesabix_ensure_sdk_components_from_internal_mirror
setup_gradle_mirror_init
check_gradle_mirror_health
prepare_gradle_user_home
ensure_jvm_trusts_hesabix_gradle_mirror
if ! ensure_android_prerequisites; then
  die "Android prerequisites not satisfied. Use --auto-setup-android or install SDK/Java manually."
fi

hesabix_ensure_ndk_from_internal_mirror

if [ "$BOOTSTRAP_ONLY" = true ]; then
  echo ""
  echo "=========================================="
  echo "✓ Bootstrap completed"
  echo "=========================================="
  echo "Flutter, Android SDK, and Java checks finished."
  echo "No dependency install or build steps were executed (--bootstrap-only)."
  exit 0
fi

# Install dependencies if requested
if [ "$INSTALL_DEPS" = true ]; then
  echo "Installing dependencies..."
  if ! flutter_run pub get; then
    die "Error downloading dependencies. Please check internet connection and DNS."
  fi
elif [ ! -d "$APP_DIR/.dart_tool" ] || [ ! -f "$APP_DIR/pubspec.lock" ]; then
  echo "Dependencies not installed. Installing..."
  if ! flutter_run pub get; then
    warn "Error downloading dependencies. Trying to continue without them..."
    warn "If build fails, please run: cd $APP_DIR && flutter pub get"
  fi
fi

# Clean build directory if requested
if [ "$CLEAN_BUILD" = true ]; then
  echo "Cleaning build directory..."
  flutter_run clean
fi

# تنظیم موازی‌سازی و حافظه بر اساس CPU و RAM (برای Gradle از طریق flutter --android-project-arg)
configure_build_resources() {
  AVAILABLE_CORES=$(nproc 2>/dev/null || echo 1)
  case "${AVAILABLE_CORES:-0}" in
    ''|*[!0-9]*) AVAILABLE_CORES=1 ;;
  esac
  [ "${AVAILABLE_CORES:-0}" -lt 1 ] && AVAILABLE_CORES=1

  local mem_kb=0
  if [[ -r /proc/meminfo ]]; then
    mem_kb=$(awk '/^MemAvailable:/{print $2; exit}' /proc/meminfo 2>/dev/null || echo 0)
    case "${mem_kb:-0}" in
      ''|*[!0-9]*) mem_kb=0 ;;
    esac
  fi
  MEM_AVAIL_MB=$((mem_kb / 1024))

  GRADLE_WORKERS=$AVAILABLE_CORES
  PARALLEL_COMPILE_JOBS=$AVAILABLE_CORES
  GRADLE_HEAP_MB=4096
  GRADLE_METASPACE_MB=512
  KOTLIN_DAEMON_HEAP_MB=1536

  if [[ "${BUILD_ANDROID_SMART_RESOURCES:-1}" == "1" ]]; then
    local mem_workers=1
    if [[ "${MEM_AVAIL_MB:-0}" -ge 2000 ]]; then
      mem_workers=$(( MEM_AVAIL_MB / 2000 ))
    fi
    [[ "$mem_workers" -lt 1 ]] && mem_workers=1
    if [[ "$mem_workers" -lt "$AVAILABLE_CORES" ]]; then
      GRADLE_WORKERS=$mem_workers
    else
      GRADLE_WORKERS=$AVAILABLE_CORES
    fi
    [[ "$GRADLE_WORKERS" -lt 1 ]] && GRADLE_WORKERS=1

    PARALLEL_COMPILE_JOBS=$GRADLE_WORKERS
    if [[ "${MEM_AVAIL_MB:-0}" -ge 1800 ]]; then
      local p=$(( MEM_AVAIL_MB / 1800 ))
      [[ "$p" -lt 1 ]] && p=1
      if [[ "$p" -lt "$PARALLEL_COMPILE_JOBS" ]]; then
        PARALLEL_COMPILE_JOBS=$p
      fi
    elif [[ "${MEM_AVAIL_MB:-0}" -gt 0 ]]; then
      PARALLEL_COMPILE_JOBS=1
    fi
    [[ "$PARALLEL_COMPILE_JOBS" -lt 1 ]] && PARALLEL_COMPILE_JOBS=1
    if [[ "$PARALLEL_COMPILE_JOBS" -gt "$AVAILABLE_CORES" ]]; then
      PARALLEL_COMPILE_JOBS=$AVAILABLE_CORES
    fi

    if [[ "${MEM_AVAIL_MB:-0}" -gt 0 ]]; then
      local max_heap=$(( MEM_AVAIL_MB * 45 / 100 ))
      GRADLE_HEAP_MB=$(( MEM_AVAIL_MB * 40 / 100 ))
      [[ "$GRADLE_HEAP_MB" -gt "$max_heap" ]] && GRADLE_HEAP_MB=$max_heap
      [[ "$GRADLE_HEAP_MB" -lt 512 ]] && GRADLE_HEAP_MB=512
      [[ "$GRADLE_HEAP_MB" -gt 24576 ]] && GRADLE_HEAP_MB=24576
    fi
    GRADLE_METASPACE_MB=$(( GRADLE_HEAP_MB / 10 ))
    [[ "$GRADLE_METASPACE_MB" -lt 384 ]] && GRADLE_METASPACE_MB=384
    [[ "$GRADLE_METASPACE_MB" -gt 1024 ]] && GRADLE_METASPACE_MB=1024

    KOTLIN_DAEMON_HEAP_MB=$(( GRADLE_HEAP_MB / 4 ))
    [[ "$KOTLIN_DAEMON_HEAP_MB" -lt 512 ]] && KOTLIN_DAEMON_HEAP_MB=512
    [[ "$KOTLIN_DAEMON_HEAP_MB" -gt 8192 ]] && KOTLIN_DAEMON_HEAP_MB=8192
  else
    GRADLE_WORKERS=$(( AVAILABLE_CORES * 80 / 100 ))
    [[ "$GRADLE_WORKERS" -lt 1 ]] && GRADLE_WORKERS=1
    [[ "$GRADLE_WORKERS" -gt "$AVAILABLE_CORES" ]] && GRADLE_WORKERS=$AVAILABLE_CORES
    PARALLEL_COMPILE_JOBS=$GRADLE_WORKERS
  fi

  export MAKEFLAGS="-j${PARALLEL_COMPILE_JOBS}"
  export CMAKE_BUILD_PARALLEL_LEVEL="${PARALLEL_COMPILE_JOBS}"
}

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

configure_build_resources

# Build flags
BUILD_FLAGS=("--$MODE")
BUILD_FLAGS+=("--android-skip-build-dependency-validation")
BUILD_FLAGS+=("--dart-define" "API_BASE_URL=$API_BASE_URL")

if [[ "${BUILD_ANDROID_SMART_RESOURCES:-1}" == "1" ]]; then
  BUILD_FLAGS+=(--android-project-arg "org.gradle.parallel=true")
  BUILD_FLAGS+=(--android-project-arg "org.gradle.caching=true")
  BUILD_FLAGS+=(--android-project-arg "org.gradle.workers.max=${GRADLE_WORKERS}")
  BUILD_FLAGS+=(--android-project-arg "org.gradle.jvmargs=-Xmx${GRADLE_HEAP_MB}m -XX:MaxMetaspaceSize=${GRADLE_METASPACE_MB}m -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError -Dfile.encoding=UTF-8")
  BUILD_FLAGS+=(--android-project-arg "kotlin.daemon.jvmargs=-Xmx${KOTLIN_DAEMON_HEAP_MB}m")
fi

echo ""
echo "Build Configuration:"
echo "  Mode: $MODE"
echo "  API Base URL: $API_BASE_URL"
echo "  Log detail: BUILD_ANDROID_VERBOSE=${BUILD_ANDROID_VERBOSE} (0=quiet, 1=-v, 2=-vv)"
echo "  Smart CPU/RAM: BUILD_ANDROID_SMART_RESOURCES=${BUILD_ANDROID_SMART_RESOURCES}"
echo "  CPU cores (nproc): ${AVAILABLE_CORES}"
if [[ -n "${MEM_AVAIL_MB:-}" ]] && [[ "${MEM_AVAIL_MB:-0}" -gt 0 ]]; then
  echo "  تقریبی MemAvailable: ${MEM_AVAIL_MB} MiB"
else
  echo "  MemAvailable: (نامشخص — خارج لینوکس یا /proc در دسترس نیست)"
fi
echo "  Gradle org.gradle.workers.max: ${GRADLE_WORKERS}"
echo "  موازی ساخت بومی (MAKEFLAGS/CMAKE): -j${PARALLEL_COMPILE_JOBS}"
if [[ "${BUILD_ANDROID_SMART_RESOURCES:-1}" == "1" ]]; then
  echo "  Gradle heap (-Xmx): ${GRADLE_HEAP_MB}m  |  Kotlin daemon: ${KOTLIN_DAEMON_HEAP_MB}m"
fi
echo ""

# Build Android App Bundle
if [ "$BUILD_AAB" = true ]; then
  echo "=========================================="
  echo "Building Android App Bundle (AAB)..."
  echo "=========================================="
  if flutter_run build appbundle "${BUILD_FLAGS[@]}"; then
    aab_path="$APP_DIR/build/app/outputs/bundle/${MODE}/app-${MODE}.aab"
    if [ -f "$aab_path" ]; then
      echo "✓ AAB built successfully: $aab_path"
      ls -lh "$aab_path" || true
    fi
  else
    warn "Failed to build AAB"
    BUILD_FAILED=true
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
    if flutter_run build apk "${BUILD_FLAGS[@]}"; then
      apk_path="$APP_DIR/build/app/outputs/flutter-apk/app-${MODE}.apk"
      if [ -f "$apk_path" ]; then
        echo "✓ Universal APK built successfully: $apk_path"
        ls -lh "$apk_path" || true
      fi
    else
      warn "Failed to build universal APK"
      BUILD_FAILED=true
    fi
    echo ""
  fi

  # Build split APKs
  if [ "$BUILD_SPLIT_APK" = true ]; then
    echo "=========================================="
    echo "Building Split APKs (per ABI)..."
    echo "=========================================="
    if flutter_run build apk "${BUILD_FLAGS[@]}" --split-per-abi; then
      apk_dir="$APP_DIR/build/app/outputs/flutter-apk"
      echo "✓ Split APKs built successfully:"
      ls -lh "$apk_dir"/*-${MODE}.apk 2>/dev/null | grep -v "app-${MODE}.apk" || true
    else
      warn "Failed to build split APKs"
      BUILD_FAILED=true
    fi
    echo ""
  fi
fi

# Summary
echo "=========================================="
if [ "$BUILD_FAILED" = true ]; then
  echo "✗ Build completed with errors"
else
  echo "✓ Build completed!"
fi
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

if [ "$BUILD_FAILED" = true ]; then
  exit 1
fi

