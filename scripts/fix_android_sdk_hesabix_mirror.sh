#!/usr/bin/env bash
# نصب/تکمیل Android SDK از آینهٔ Hesabix (Myket): cmdline-tools، لایسنس، build-tools، platform، NDK.
# اجرا روی سرور (ترجیحاً root): bash scripts/fix_android_sdk_hesabix_mirror.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT/build_android.sh" --bootstrap-only "$@"
