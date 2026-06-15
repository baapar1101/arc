#!/usr/bin/env bash
# flutter pub get با آینهٔ داخلی Hesabix (همان deploy.sh).
# اختیاری: اگر تونل SSH/پروکسی Cursor روی localhost فعال است:
#   export HTTP_PROXY=http://127.0.0.1:PORT HTTPS_PROXY=http://127.0.0.1:PORT
#   bash scripts/flutter_pub_get_mirror.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI="${ROOT}/hesabixUI/hesabix_ui"

export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://f.mirror.hesabix.ir/pub}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://f.mirror.hesabix.ir/gcs}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -r "${SCRIPT_DIR}/mirror_config.sh" ]]; then
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/mirror_config.sh"
  hesabix_apply_flutter_mirror_env 2>/dev/null || true
fi

echo "PUB_HOSTED_URL=${PUB_HOSTED_URL}"
echo "FLUTTER_STORAGE_BASE_URL=${FLUTTER_STORAGE_BASE_URL}"
if [[ -n "${HTTP_PROXY:-}" || -n "${HTTPS_PROXY:-}" ]]; then
  echo "HTTP_PROXY=${HTTP_PROXY:-}"
  echo "HTTPS_PROXY=${HTTPS_PROXY:-}"
fi

cd "${UI}"
flutter pub get "$@"
