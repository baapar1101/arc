#!/usr/bin/env bash
# بعد از تغییر مخازن / pull: توقف دیمون Gradle و پاک‌سازی build اندروید (در صورت وجود gradlew)
#
#   bash scripts/android_gradle_refresh.sh
#
# مسیر پیش‌فرض: hesabixUI/hesabix_ui/android

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="${ANDROID_PROJECT_DIR:-${REPO_ROOT}/hesabixUI/hesabix_ui/android}"

if [[ ! -d "$ANDROID_DIR" ]]; then
  echo "مسیر نیست: $ANDROID_DIR" >&2
  exit 1
fi

cd "$ANDROID_DIR"

if [[ -x ./gradlew ]]; then
  echo ">> ./gradlew --stop"
  ./gradlew --stop || true
  echo ">> ./gradlew clean"
  ./gradlew clean || true
else
  echo "gradlew در $ANDROID_DIR نیست (مثلاً قبل از اولین flutter build)."
  echo "می‌توانید اجرا کنید: cd ${ANDROID_DIR}/../.. && flutter clean"
fi
