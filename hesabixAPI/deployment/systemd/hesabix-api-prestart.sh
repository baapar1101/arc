#!/usr/bin/env bash
# اجرا با دسترسی root (ExecStartPre=! در hesabix-api.service)
# ۱) systemctl daemon-reload — بعد از تغییر یونیت‌ها یا اسکریپت‌هایی مثل build_web
# ۲) در صورت نبودن/خرابی وابستگی‌های Python، نصب از آینه‌ها مطابق deploy.sh

set -euo pipefail
# systemd ممکن است PATH کوتاه بدهد؛ runuser در /usr/sbin است
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
VENV_PY="${API_DIR}/.venv/bin/python"
PIP="${API_DIR}/.venv/bin/pip"

log() { echo "hesabix-api-prestart: $*" >&2; }

if ! command -v systemctl >/dev/null 2>&1; then
  log "systemctl not found; skipping daemon-reload"
else
  systemctl daemon-reload
fi

if [[ ! -x "$VENV_PY" || ! -x "$PIP" ]]; then
  log "venv not ready (missing $VENV_PY or $PIP)"
  exit 1
fi

run_as_www() {
  if id -u www-data >/dev/null 2>&1; then
    if command -v runuser >/dev/null 2>&1; then
      runuser -u www-data -- "$@"
    elif command -v sudo >/dev/null 2>&1; then
      sudo -u www-data -- "$@"
    else
      log "نه runuser و نه sudo؛ اجرا با کاربر فعلی (root)"
      "$@"
    fi
  else
    log "www-data user missing; running as current user"
    "$@"
  fi
}

# همان مسیر import واقعی workerها
if run_as_www env PYTHONPATH="${API_DIR}" "$VENV_PY" -c "import app.main" 2>/dev/null; then
  exit 0
fi

log "import app.main failed; attempting pip install -e . from mirrors (deploy.sh order)..."

set_pip_env_for_url() {
  local index_url="$1"
  export PIP_INDEX_URL="${index_url}"
  if [[ "${index_url}" != *"pypi.org"* ]]; then
    local host
    host=$(echo "${index_url}" | sed -n 's|https\?://\([^/]*\).*|\1|p')
    export PIP_TRUSTED_HOST="${host}"
  else
    unset PIP_TRUSTED_HOST || true
  fi
}

# get_pip_mirrors_list در deploy.sh
MIRRORS=()
if [[ -n "${PIP_INDEX_URL:-}" ]]; then
  MIRRORS+=("${PIP_INDEX_URL}")
fi
MIRRORS+=(
  "https://mirror-pypi.runflare.com/simple"
  "https://pypi.org/simple"
  "https://pypi.tuna.tsinghua.edu.cn/simple"
  "https://mirrors.aliyun.com/pypi/simple/"
  "https://mirrors.cloud.tencent.com/pypi/simple"
)

for url in "${MIRRORS[@]}"; do
  [[ -z "$url" ]] && continue
  log "trying PyPI: $url"
  set_pip_env_for_url "$url"
  if [[ -n "${PIP_TRUSTED_HOST:-}" ]]; then
    if ! run_as_www env PIP_INDEX_URL="${PIP_INDEX_URL}" PIP_TRUSTED_HOST="${PIP_TRUSTED_HOST}" \
        "$PIP" install --upgrade pip setuptools wheel \
        && run_as_www env PIP_INDEX_URL="${PIP_INDEX_URL}" PIP_TRUSTED_HOST="${PIP_TRUSTED_HOST}" \
        "$PIP" install -e "${API_DIR}"; then
      continue
    fi
  else
    if ! run_as_www env PIP_INDEX_URL="${PIP_INDEX_URL}" \
        "$PIP" install --upgrade pip setuptools wheel \
        && run_as_www env PIP_INDEX_URL="${PIP_INDEX_URL}" \
        "$PIP" install -e "${API_DIR}"; then
      continue
    fi
  fi
  if run_as_www env PYTHONPATH="${API_DIR}" "$VENV_PY" -c "import app.main"; then
    log "OK after install from $url"
    exit 0
  fi
done

log "could not fix Python dependencies or app.main still does not import"
exit 1
