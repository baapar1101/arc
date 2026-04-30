#!/usr/bin/env bash
# یکجا: پچ flutter_tools/gradle + (در صورت وجود) gradlew --stop و clean
#
#   bash scripts/hesabix_android_mirror_setup.sh
#
# فقط پچ:
#   bash scripts/patch_flutter_tools_gradle_mirror.sh
#
# فقط refresh:
#   bash scripts/android_gradle_refresh.sh

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash "${ROOT}/scripts/patch_flutter_tools_gradle_mirror.sh"
bash "${ROOT}/scripts/android_gradle_refresh.sh"
