#!/usr/bin/env bash
# دانلود wheelهای وابستگی voice در hesabixAPI/vendor/voice_wheels/
# روی ماشین با دسترسی به PyPI اجرا کنید؛ سپس پوشه را به سرور production منتقل کنید.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/hesabixAPI/vendor/voice_wheels"
REQ="${ROOT}/scripts/pypi_voice_requirements.txt"
INDEX="${VOICE_WHEELS_INDEX_URL:-https://pypi.org/simple}"
PY_VER="${VOICE_WHEELS_PY:-312}"
PLATFORM="${VOICE_WHEELS_PLATFORM:-manylinux2014_x86_64}"

log() { echo "[populate-voice-wheels] $*"; }

if [[ ! -f "${REQ}" ]]; then
  echo "Missing ${REQ}" >&2
  exit 1
fi

mkdir -p "${OUT}"
log "Output: ${OUT}"
log "Index:  ${INDEX}"

common_args=(
  -d "${OUT}"
  -r "${REQ}"
  --python-version "${PY_VER}"
  --platform "${PLATFORM}"
  --implementation cp
  --abi cp"${PY_VER}"
  -i "${INDEX}"
)

if pip download "${common_args[@]}" --only-binary=:all:; then
  log "Binary wheels downloaded."
else
  log "Some packages lack wheels; downloading source/binary mix..."
  pip download "${common_args[@]}"
fi

log "Done. Wheel count: $(find "${OUT}" -maxdepth 1 -name '*.whl' | wc -l)"
log "Sync to server: rsync -av ${OUT}/ root@SERVER:/opt/hesabix/app/hesabixAPI/vendor/voice_wheels/"
