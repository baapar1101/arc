#!/usr/bin/env bash
# نصب NDK نسخهٔ پین‌شده در android/gradle.properties (android.ndkVersion) از آینهٔ Myket
# مطابق کاتالوگ اکسل: ndk;26.1.10909125 → android-ndk-r26b-linux.zip
#
# استفاده:
#   bash scripts/install_ndk_myket.sh
# یا:
#   ANDROID_SDK_ROOT=/path/to/sdk bash scripts/install_ndk_myket.sh
#
# نیاز: curl، unzip، sha1sum؛ برای نوشتن زیر /usr/lib/android-sdk معمولاً sudo

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="${ANDROID_PROJECT_DIR:-${REPO_ROOT}/hesabixUI/hesabix_ui/android}"
GRADLE_PROPS="${ANDROID_DIR}/gradle.properties"
LOCAL_PROPS="${ANDROID_DIR}/local.properties"

# همان ردیف اکسل: ndk;26.1.10909125 (لینوکس)
MYKET_URL="https://maven.myket.ir/android-sdk/android-ndk-r26b-linux.zip"
EXPECTED_SHA1="fdf33d9f6c1b3f16e5459d53a82c7d2201edbcc4"
EXPECTED_SIZE="669320864"

if [[ -f "$LOCAL_PROPS" ]]; then
  SDK_DIR="$(grep '^sdk\.dir=' "$LOCAL_PROPS" | head -1 | cut -d= -f2- | tr -d '\r')"
  SDK_DIR="${SDK_DIR/#\~/${HOME}}"
fi
SDK_DIR="${ANDROID_SDK_ROOT:-${SDK_DIR:-}}"

if [[ -z "$SDK_DIR" || ! -d "$SDK_DIR" ]]; then
  echo "[error] مسیر SDK مشخص نیست. sdk.dir در $LOCAL_PROPS یا ANDROID_SDK_ROOT را بگذارید." >&2
  exit 1
fi

NDK_VER=""
if [[ -f "$GRADLE_PROPS" ]]; then
  NDK_VER="$(grep '^android\.ndkVersion=' "$GRADLE_PROPS" | head -1 | cut -d= -f2- | tr -d '\r' | tr -d ' ')"
fi
if [[ "$NDK_VER" != "26.1.10909125" ]]; then
  echo "[warn] android.ndkVersion=$NDK_VER — این اسکریپت فقط برای 26.1.10909125 (ر26b) از Myket تنظیم شده است." >&2
  echo "        در صورت تغییر نسخه، URL و SHA1 را در اسکریپت عوض کنید." >&2
fi

TARGET="${SDK_DIR}/ndk/26.1.10909125"
ZIP="$(mktemp "${TMPDIR:-/tmp}/android-ndk-r26b-linux.XXXXXX.zip")"

echo "SDK: $SDK_DIR"
echo "هدف: $TARGET"

if [[ -f "$TARGET/source.properties" ]]; then
  echo "از قبل نصب به نظر می‌رسد: $TARGET"
  head -5 "$TARGET/source.properties" || true
  exit 0
fi

echo "در حال دانلود از Myket (~638 MiB)..."
curl -fL --connect-timeout 30 --retry 5 --retry-delay 8 -o "$ZIP" "$MYKET_URL"

SIZE="$(stat -c%s "$ZIP" 2>/dev/null || stat -f%z "$ZIP")"
if [[ "$SIZE" != "$EXPECTED_SIZE" ]]; then
  echo "[error] اندازهٔ فایل نامعتبر: $SIZE (انتظار: $EXPECTED_SIZE)" >&2
  exit 1
fi

echo "بررسی SHA-1..."
ACTUAL="$(sha1sum "$ZIP" | awk '{print $1}')"
if [[ "$ACTUAL" != "$EXPECTED_SHA1" ]]; then
  echo "[error] SHA1 اشتباه: $ACTUAL (انتظار: $EXPECTED_SHA1)" >&2
  rm -f "$ZIP"
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$ZIP"' EXIT
unzip -q "$ZIP" -d "$STAGE"
TOP="$(find "$STAGE" -mindepth 1 -maxdepth 1 -type d | head -1)"
if [[ ! -f "$TOP/source.properties" ]]; then
  echo "[error] ساختار zip غیرمنتظره: $STAGE" >&2
  ls -la "$STAGE" >&2
  exit 1
fi

mkdir -p "${SDK_DIR}/ndk"
if [[ -e "$TARGET" ]]; then
  rm -rf "$TARGET"
fi
mv "$TOP" "$TARGET"
chmod -R a+rX "$TARGET" 2>/dev/null || true

echo "نصب شد: $TARGET"
head -8 "$TARGET/source.properties"
