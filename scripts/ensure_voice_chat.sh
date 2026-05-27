#!/usr/bin/env bash
# نصب idempotent پیش‌نیازهای مکالمه صوتی AI (محلی — بدون API ابری).
# - بسته‌های سیستمی libav برای PyAV
# - pip install -e ".[voice]" (faster-whisper, webrtcvad, TTS, torch, av)
# - دایرکتوری ذخیره opt-in و تنظیمات .env
#
# Usage:
#   INSTALL_VOICE=Y bash scripts/ensure_voice_chat.sh
#   bash scripts/ensure_voice_chat.sh --update          # در update.sh؛ در صورت نبود deps از کاربر می‌پرسد
#   bash scripts/ensure_voice_chat.sh --non-interactive # فقط اگر INSTALL_VOICE=Y
set -euo pipefail

APP_ROOT="${APP_ROOT:-/opt/hesabix}"
API_DIR="${API_DIR:-${APP_ROOT}/app/hesabixAPI}"
VOICE_DATA_DIR="${VOICE_DATA_DIR:-/var/lib/hesabix/voice-data}"
FROM_UPDATE=0
NONINTERACTIVE=0

log_info() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
log_ok()   { echo "OK: $*"; }
log_warn() { echo "WARN: $*" >&2; }

usage() {
  cat <<'EOF'
Usage: ensure_voice_chat.sh [--update] [--non-interactive]

  INSTALL_VOICE     y/Y to install, n/N to skip (prompt if unset and not --non-interactive)
  APP_ROOT          default /opt/hesabix
  API_DIR           default ${APP_ROOT}/app/hesabixAPI
  PIP_INDEX_URL     Hesabix mirror (optional)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update) FROM_UPDATE=1; shift ;;
    --non-interactive) NONINTERACTIVE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log_warn "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

# Respect deploy-time choice on update (update.sh may not re-source full .deploy_env).
if [[ -z "${INSTALL_VOICE:-}" ]] && [[ -f "${APP_ROOT}/.deploy_env" ]]; then
  # shellcheck disable=SC1091
  set -a
  # shellcheck source=/dev/null
  source "${APP_ROOT}/.deploy_env"
  set +a
fi

voice_apt_packages() {
  echo "libavformat-dev libavcodec-dev libavutil-dev libswresample-dev libswscale-dev libavdevice-dev pkg-config"
}

ensure_voice_system_packages() {
  if ! command -v apt-get >/dev/null 2>&1; then
    log_warn "apt-get not found; install PyAV system libs manually (libavformat-dev, ...)."
    return 0
  fi
  export DEBIAN_FRONTEND=noninteractive
  local pkgs shell_pkgs
  pkgs=$(voice_apt_packages)
  # shellcheck disable=SC2086
  shell_pkgs=(${pkgs})
  local missing=()
  local p
  for p in "${shell_pkgs[@]}"; do
    if ! dpkg-query -W -f='${Status}' "${p}" 2>/dev/null | grep -q "install ok installed"; then
      missing+=("${p}")
    fi
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    log_ok "Voice system libraries already installed."
    return 0
  fi
  log_info "Installing voice system packages: ${missing[*]}"
  apt-get update -qq
  # shellcheck disable=SC2086
  apt-get install -y -qq ${pkgs} || {
    log_warn "Some voice system packages failed to install (PyAV/WebM may not work)."
    return 0
  }
  log_ok "Voice system packages installed."
}

ensure_voice_data_directory() {
  mkdir -p "${VOICE_DATA_DIR}"
  if id -u www-data >/dev/null 2>&1; then
    chown -R www-data:www-data "${VOICE_DATA_DIR}" 2>/dev/null || true
  fi
  chmod 750 "${VOICE_DATA_DIR}" 2>/dev/null || true
  log_ok "Voice data directory: ${VOICE_DATA_DIR}"
}

activate_venv() {
  if [[ ! -d "${API_DIR}/.venv" ]]; then
    log_warn "venv not found at ${API_DIR}/.venv"
    return 1
  fi
  # shellcheck disable=SC1091
  source "${API_DIR}/.venv/bin/activate"
  return 0
}

voice_python_ready() {
  activate_venv || return 1
  python3 - <<'PY' >/dev/null 2>&1
import webrtcvad  # noqa: F401
import numpy  # noqa: F401
import av  # noqa: F401
from faster_whisper import WhisperModel  # noqa: F401
print("ok")
PY
}

install_voice_pip_extras() {
  activate_venv || return 1
  configure_pip() {
    if command -v python3 >/dev/null 2>&1; then
      python3 -m pip config --user set global.index-url "${PIP_INDEX_URL:-https://p.mirror.hesabix.ir/simple}" 2>/dev/null || true
      python3 -m pip config --user set global.trusted-host "${PIP_TRUSTED_HOST:-p.mirror.hesabix.ir}" 2>/dev/null || true
    fi
  }
  configure_pip
  export PIP_INDEX_URL="${PIP_INDEX_URL:-https://p.mirror.hesabix.ir/simple}"
  export PIP_TRUSTED_HOST="${PIP_TRUSTED_HOST:-p.mirror.hesabix.ir}"
  cd "${API_DIR}"
  log_info "Installing Python voice extras (pip install -e \".[voice]\") — may take several minutes..."
  pip install --upgrade pip setuptools wheel -q
  if pip install -e ".[voice]"; then
    log_ok "Voice Python dependencies installed."
    return 0
  fi
  log_warn "pip install -e \".[voice]\" failed."
  return 1
}

merge_voice_env_file() {
  local env_file="${API_DIR}/.env"
  [[ -f "${env_file}" ]] || env_file="${API_DIR}/env.example"
  [[ -f "${env_file}" ]] || return 0
  export MERGE_VOICE_ENV_PATH="${env_file}"
  export VOICE_DATA_DIR
  python3 <<'PY'
import os, re
path = os.environ["MERGE_VOICE_ENV_PATH"]

def fmt_val(v: str) -> str:
    if re.search(r'[\s#"\'\\]', v) or v.startswith("#"):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return v

updates = {
    "VOICE_ENABLED": "true",
    "VOICE_TTS_ENGINE": "coqui",
    "VOICE_TTS_COQUI_MODEL_FA": "tts_models/fa/cv/vits/glow-tts",
    "VOICE_DATA_COLLECTION_DIR": os.environ.get("VOICE_DATA_DIR", "/var/lib/hesabix/voice-data"),
    "VOICE_DATA_COLLECTION_ENABLED": "false",
}
key_re = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=")
lines = []
if os.path.isfile(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
keys_done = set()
out = []
for line in lines:
    m = key_re.match(line)
    if m and m.group(1) in updates:
        k = m.group(1)
        out.append(f"{k}={fmt_val(updates[k])}\n")
        keys_done.add(k)
    else:
        out.append(line)
for k, v in updates.items():
    if k not in keys_done:
        out.append(f"{k}={fmt_val(v)}\n")
with open(path, "w", encoding="utf-8") as f:
    f.writelines(out)
print("merged")
PY
  log_ok "Voice settings written to ${env_file}"
}

warn_voice_resources() {
  local mem_kb avail_mb
  mem_kb=$(grep -E '^MemAvailable:' /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
  avail_mb=$((mem_kb / 1024))
  if [[ "${avail_mb}" -lt 4096 ]]; then
    log_warn "Available RAM ~${avail_mb}MB — voice (Whisper+TTS) needs ~4GB+ for stable use."
  fi
}

should_install_voice() {
  : "${INSTALL_VOICE:=}"
  if [[ "${INSTALL_VOICE}" =~ ^[Yy]$ ]]; then
    return 0
  fi
  if [[ "${INSTALL_VOICE}" =~ ^[Nn]$ ]]; then
    return 1
  fi
  if [[ "${NONINTERACTIVE}" -eq 1 ]]; then
    return 1
  fi
  if [[ "${FROM_UPDATE}" -eq 1 ]] && voice_python_ready 2>/dev/null; then
    log_ok "Voice Python deps already present; skip (set INSTALL_VOICE=Y to reinstall)."
    return 1
  fi
  echo
  echo "مکالمه صوتی AI (پردازش محلی — Whisper + Coqui، بدون سرویس ابری):"
  echo "  • نیاز به RAM/CPU و چند گیگابایت فضای دیسک (torch و مدل‌ها)"
  echo "  • کتابخانه‌های سیستمی libav + pip optional [voice]"
  warn_voice_resources
  local ans
  read -rp "Install AI voice chat dependencies? (y/N): " ans
  ans=${ans:-N}
  [[ "${ans}" =~ ^[Yy]$ ]]
}

main() {
  if ! should_install_voice; then
    log_info "Voice chat dependencies skipped."
    exit 0
  fi

  ensure_voice_system_packages
  ensure_voice_data_directory

  if voice_python_ready 2>/dev/null; then
    log_ok "Voice Python stack already importable."
  else
    install_voice_pip_extras || exit 1
    if ! voice_python_ready 2>/dev/null; then
      log_warn "Voice imports still failing after pip install."
      exit 1
    fi
  fi

  merge_voice_env_file
  log_ok "AI voice chat prerequisites ready (local STT/TTS)."
}

main "$@"
