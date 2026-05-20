#!/usr/bin/env bash
# پچ repositories در SDK فلاتر: packages/flutter_tools/gradle/settings.gradle.kts
# (همان سه مخزن آینهٔ Hesabix — upstream از طریق nginx، مثلاً Maven مایکت)
#
# اجرا از روت مخزن:
#   bash scripts/patch_flutter_tools_gradle_mirror.sh
#
# مسیر اندروید پیش‌فرض: hesabixUI/hesabix_ui/android
# متغیر اختیاری: ANDROID_PROJECT_DIR، HESABIX_GRADLE_MIRROR (نادیده گرفتن gradle.properties)
#
# بازگردانی نسخهٔ قبل از آخرین پچ (پشتیبان همان لحظه قبل از اعمال):
#   bash scripts/patch_flutter_tools_gradle_mirror.sh --restore

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_DIR="${ANDROID_PROJECT_DIR:-${REPO_ROOT}/hesabixUI/hesabix_ui/android}"
RESTORE=0
[[ "${1:-}" == "--restore" ]] && RESTORE=1

LOCAL_PROPS="${ANDROID_DIR}/local.properties"
GRADLE_PROPS="${ANDROID_DIR}/gradle.properties"

if [[ ! -f "$LOCAL_PROPS" ]]; then
  echo "یافت نشد: $LOCAL_PROPS (flutter.sdk لازم است)" >&2
  exit 1
fi

flutter_sdk="$(grep '^flutter\.sdk=' "$LOCAL_PROPS" | head -1 | cut -d= -f2- | tr -d '\r')"
flutter_sdk="${flutter_sdk/#\~/${HOME}}"
if [[ -z "$flutter_sdk" || ! -d "$flutter_sdk" ]]; then
  echo "flutter.sdk در local.properties معتبر نیست: ${flutter_sdk:-خالی}" >&2
  exit 1
fi

TARGET="${flutter_sdk}/packages/flutter_tools/gradle/settings.gradle.kts"
BACKUP="${TARGET}.before_hesabix_mirror"

if [[ ! -f "$TARGET" ]]; then
  echo "فایل flutter_tools یافت نشد: $TARGET — نسخهٔ Flutter را بررسی کنید." >&2
  exit 1
fi

if [[ "$RESTORE" -ne 1 ]] && grep -qF 'gradle.mirror.hesabix.ir' "$TARGET"; then
  echo "پچ از قبل اعمال شده: $TARGET"
  exit 0
fi

if [[ "$RESTORE" -ne 1 ]]; then
  cp -a "$TARGET" "$BACKUP"
  echo "پشتیبان: $BACKUP"
fi

if [[ "$RESTORE" -eq 1 ]]; then
  if [[ ! -f "$BACKUP" ]]; then
    echo "پشتیبان نیست: $BACKUP" >&2
    exit 1
  fi
  cp -a "$BACKUP" "$TARGET"
  echo "بازگردانی شد: $TARGET"
  exit 0
fi

mirror="${HESABIX_GRADLE_MIRROR:-}"
if [[ -z "$mirror" && -f "$GRADLE_PROPS" ]]; then
  mirror="$(grep '^hesabix\.gradle\.mirror=' "$GRADLE_PROPS" | head -1 | cut -d= -f2- | tr -d '\r' | tr -d ' ')"
fi
if [[ -z "$mirror" ]]; then
  mirror="https://gradle.mirror.hesabix.ir"
fi
mirror="${mirror%/}"

export HESABIX_MIRROR_BASE="$mirror"
export HESABIX_TARGET_FILE="$TARGET"

python3 << 'PY'
import os, re, sys
from pathlib import Path

base = os.environ["HESABIX_MIRROR_BASE"].rstrip("/")
path = Path(os.environ["HESABIX_TARGET_FILE"])
text = path.read_text(encoding="utf-8")

if "gradle.mirror.hesabix.ir" in text:
    print("پچ از قبل اعمال شده (gradle.mirror.hesabix.ir در فایل هست).")
    sys.exit(0)

pat = re.compile(
    r"([ \t]*)repositories\s*\{\s*google\(\)\s*mavenCentral\(\)\s*\}", re.DOTALL
)


def repl(m):
    ind = m.group(1)
    inner = ind + "    "
    return (
        f"{ind}repositories {{\n"
        f'{inner}maven {{ url = uri("{base}/android/maven2/") }}\n'
        f'{inner}maven {{ url = uri("{base}/maven2/") }}\n'
        f'{inner}maven {{ url = uri("{base}/gradle-plugins/") }}\n'
        f"{ind}}}"
    )


if not pat.search(text):
    print(
        "الگوی google()/mavenCentral() پیدا نشد؛ نسخهٔ Flutter عوض شده یا قبلاً ویرایش شده.",
        file=sys.stderr,
    )
    sys.exit(1)

path.write_text(pat.sub(repl, text, count=1), encoding="utf-8")
print(f"پچ شد: {path}")
PY
