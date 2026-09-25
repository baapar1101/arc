#!/usr/bin/env bash
# Hesabix anonymous/semi-anonymous install telemetry (opt-out: HESABIX_TELEMETRY=0).
# Sourced by deploy.sh (after clone) and update.sh. Never aborts the caller on failure.
#
# Sends JSON POST to https://hesabix.ir/wp-json/hesabix-stats/v1/event
# Override: HESABIX_STATS_URL, HESABIX_STATS_TOKEN
#
# shellcheck shell=bash

# Endpoint and soft ingest token (must match WP option his_ingest_token on hesabix.ir).
HESABIX_STATS_URL_DEFAULT="https://hesabix.ir/wp-json/hesabix-stats/v1/event"
HESABIX_STATS_TOKEN_DEFAULT="hesabix-stats-ingest-v1"

hesabix_telemetry_enabled() {
  case "${HESABIX_TELEMETRY:-1}" in
    0|false|FALSE|no|NO|n|N|off|OFF) return 1 ;;
    *) return 0 ;;
  esac
}

# Ensure INSTALL_ID exists (UUID). Prefer existing value from env / .deploy_env.
hesabix_ensure_install_id() {
  local env_file="${APP_ROOT:-/opt/hesabix}/.deploy_env"
  local candidate="${INSTALL_ID:-}"

  if [[ -z "${candidate}" ]] && [[ -f "${env_file}" ]]; then
    candidate="$(grep -E '^INSTALL_ID=' "${env_file}" 2>/dev/null | head -n1 | cut -d= -f2- | tr -d '\r' || true)"
  fi

  if [[ -n "${candidate}" ]] && [[ "${candidate}" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$ ]]; then
    INSTALL_ID="$(printf '%s' "${candidate}" | tr '[:upper:]' '[:lower:]')"
    export INSTALL_ID
    return 0
  fi

  if command -v uuidgen >/dev/null 2>&1; then
    INSTALL_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  elif [[ -r /proc/sys/kernel/random/uuid ]]; then
    INSTALL_ID="$(tr '[:upper:]' '[:lower:]' < /proc/sys/kernel/random/uuid)"
  elif command -v python3 >/dev/null 2>&1; then
    INSTALL_ID="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  else
    # Last resort: not a real UUID v4 but unique enough; WP will reject — skip send later.
    INSTALL_ID=""
    return 1
  fi
  export INSTALL_ID
  return 0
}

# Persist INSTALL_ID into .deploy_env without wiping other keys (append or replace line).
hesabix_persist_install_id() {
  local env_file="${APP_ROOT:-/opt/hesabix}/.deploy_env"
  hesabix_ensure_install_id || return 0
  mkdir -p "$(dirname "${env_file}")"
  if [[ -f "${env_file}" ]]; then
    if grep -qE '^INSTALL_ID=' "${env_file}" 2>/dev/null; then
      # portable in-place replace
      local tmp
      tmp="$(mktemp)"
      awk -v id="${INSTALL_ID}" 'BEGIN{done=0} /^INSTALL_ID=/{print "INSTALL_ID=" id; done=1; next} {print} END{if(!done) print "INSTALL_ID=" id}' "${env_file}" > "${tmp}" \
        && mv -f "${tmp}" "${env_file}"
    else
      printf '\nINSTALL_ID=%s\n' "${INSTALL_ID}" >> "${env_file}"
    fi
    chmod 600 "${env_file}" 2>/dev/null || true
  fi
}

hesabix_telemetry_json_escape() {
  # Escape a string for JSON (no surrounding quotes).
  local s="${1-}"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.dumps(sys.argv[1])[1:-1])' "${s}" 2>/dev/null && return 0
  fi
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "${s}"
}

hesabix_telemetry_collect_ints() {
  # Sets: _HIS_RAM_MB _HIS_CPU _HIS_DISK_GB
  _HIS_RAM_MB=0
  _HIS_CPU=0
  _HIS_DISK_GB=0
  if [[ -r /proc/meminfo ]]; then
    _HIS_RAM_MB="$(awk '/^MemTotal:/ {print int($2/1024); exit}' /proc/meminfo 2>/dev/null || echo 0)"
  fi
  if command -v nproc >/dev/null 2>&1; then
    _HIS_CPU="$(nproc 2>/dev/null || echo 0)"
  elif [[ -r /proc/cpuinfo ]]; then
    _HIS_CPU="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 0)"
  fi
  if command -v df >/dev/null 2>&1; then
    _HIS_DISK_GB="$(df -BG / 2>/dev/null | awk 'NR==2 {gsub(/G/,"",$4); print int($4); exit}' || echo 0)"
  fi
}

hesabix_telemetry_os_fields() {
  _HIS_OS_ID=""
  _HIS_OS_VERSION=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    _HIS_OS_ID="${ID:-}"
    _HIS_OS_VERSION="${VERSION_ID:-}"
  fi
}

hesabix_telemetry_git_commit() {
  local app_dir="${APP_ROOT:-/opt/hesabix}/app"
  _HIS_GIT_COMMIT=""
  if [[ -d "${app_dir}/.git" ]] && command -v git >/dev/null 2>&1; then
    _HIS_GIT_COMMIT="$(git -C "${app_dir}" rev-parse --short=12 HEAD 2>/dev/null || true)"
  fi
}

hesabix_telemetry_app_version() {
  _HIS_APP_VERSION=""
  local candidates=(
    "${APP_ROOT:-/opt/hesabix}/app/hesabixAPI/VERSION"
    "${APP_ROOT:-/opt/hesabix}/app/VERSION"
  )
  local f
  for f in "${candidates[@]}"; do
    if [[ -f "${f}" ]]; then
      _HIS_APP_VERSION="$(head -n1 "${f}" | tr -d '\r' | head -c 64)"
      break
    fi
  done
}

hesabix_telemetry_ssl_flags() {
  _HIS_SSL_API=0
  _HIS_SSL_UI=0
  local api="${API_DOMAIN:-}"
  local ui="${UI_DOMAIN:-}"
  if [[ -n "${api}" ]] && [[ -d "/etc/letsencrypt/live/${api}" ]]; then
    _HIS_SSL_API=1
  fi
  if [[ -n "${ui}" ]] && [[ -d "/etc/letsencrypt/live/${ui}" ]]; then
    _HIS_SSL_UI=1
  fi
}

hesabix_telemetry_bool_yn() {
  case "${1:-}" in
    [Yy]|[Yy][Ee][Ss]|1|true|TRUE|on|ON) echo 1 ;;
    *) echo 0 ;;
  esac
}

# Public: send one event. Args: event_name (install|update|heartbeat)
# Optional second arg: script label (deploy|update)
hesabix_telemetry_send() {
  local event="${1:-}"
  local script_label="${2:-unknown}"

  if ! hesabix_telemetry_enabled; then
    return 0
  fi
  if [[ "${event}" != "install" && "${event}" != "update" && "${event}" != "heartbeat" ]]; then
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    return 0
  fi

  hesabix_ensure_install_id || return 0
  hesabix_persist_install_id

  local api_domain="${API_DOMAIN:-}"
  local ui_domain="${UI_DOMAIN:-}"
  if [[ -z "${api_domain}" && -z "${ui_domain}" ]]; then
    return 0
  fi

  hesabix_telemetry_collect_ints
  hesabix_telemetry_os_fields
  hesabix_telemetry_git_commit
  hesabix_telemetry_app_version
  hesabix_telemetry_ssl_flags

  local arch hostname reported_ip branch
  arch="$(uname -m 2>/dev/null || true)"
  hostname="$(hostname -f 2>/dev/null || hostname 2>/dev/null || true)"
  branch="${BRANCH:-}"
  reported_ip=""
  # Best-effort public IP (non-fatal, short timeout).
  reported_ip="$(curl -fsS --connect-timeout 2 --max-time 3 https://api.ipify.org 2>/dev/null || true)"
  if [[ -n "${reported_ip}" ]] && ! [[ "${reported_ip}" =~ ^[0-9a-fA-F:.]+$ ]]; then
    reported_ip=""
  fi

  local workers="${UVICORN_WORKERS:-0}"
  if ! [[ "${workers}" =~ ^[0-9]+$ ]]; then
    workers=0
  fi
  # Force collected metrics to integers (empty/non-numeric → 0).
  [[ "${_HIS_RAM_MB}" =~ ^[0-9]+$ ]] || _HIS_RAM_MB=0
  [[ "${_HIS_CPU}" =~ ^[0-9]+$ ]] || _HIS_CPU=0
  [[ "${_HIS_DISK_GB}" =~ ^[0-9]+$ ]] || _HIS_DISK_GB=0

  local pgadmin voice pip_m flutter_m
  pgadmin="$(hesabix_telemetry_bool_yn "${INSTALL_PGADMIN4:-N}")"
  voice="$(hesabix_telemetry_bool_yn "${INSTALL_VOICE:-N}")"
  pip_m="${PIP_MIRROR:-}"
  flutter_m="${FLUTTER_MIRROR:-}"

  local url token
  url="${HESABIX_STATS_URL:-${HESABIX_STATS_URL_DEFAULT}}"
  token="${HESABIX_STATS_TOKEN:-${HESABIX_STATS_TOKEN_DEFAULT}}"

  local eid eapi eui earch eosid eosver ebranch ecommit eapp epip eflutter ehost eip escript
  eid="$(hesabix_telemetry_json_escape "${INSTALL_ID}")"
  eapi="$(hesabix_telemetry_json_escape "${api_domain}")"
  eui="$(hesabix_telemetry_json_escape "${ui_domain}")"
  earch="$(hesabix_telemetry_json_escape "${arch}")"
  eosid="$(hesabix_telemetry_json_escape "${_HIS_OS_ID}")"
  eosver="$(hesabix_telemetry_json_escape "${_HIS_OS_VERSION}")"
  ebranch="$(hesabix_telemetry_json_escape "${branch}")"
  ecommit="$(hesabix_telemetry_json_escape "${_HIS_GIT_COMMIT}")"
  eapp="$(hesabix_telemetry_json_escape "${_HIS_APP_VERSION}")"
  epip="$(hesabix_telemetry_json_escape "${pip_m}")"
  eflutter="$(hesabix_telemetry_json_escape "${flutter_m}")"
  ehost="$(hesabix_telemetry_json_escape "${hostname}")"
  eip="$(hesabix_telemetry_json_escape "${reported_ip}")"
  escript="$(hesabix_telemetry_json_escape "${script_label}")"

  local payload
  payload=$(cat <<EOF
{"schema_version":1,"install_id":"${eid}","event":"${event}","api_domain":"${eapi}","ui_domain":"${eui}","reported_ip":"${eip}","ram_mb":${_HIS_RAM_MB:-0},"cpu_cores":${_HIS_CPU:-0},"disk_free_gb":${_HIS_DISK_GB:-0},"arch":"${earch}","os_id":"${eosid}","os_version":"${eosver}","branch":"${ebranch}","git_commit":"${ecommit}","app_version":"${eapp}","uvicorn_workers":${workers:-0},"ssl_api":${_HIS_SSL_API},"ssl_ui":${_HIS_SSL_UI},"install_pgadmin":${pgadmin},"install_voice":${voice},"pip_mirror":"${epip}","flutter_mirror":"${eflutter}","script":"${escript}","hostname":"${ehost}"}
EOF
)

  # Never fail the installer: swallow curl errors.
  curl -fsS --http1.1 \
    --connect-timeout 5 \
    --max-time 12 \
    -X POST \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "X-Hesabix-Stats-Token: ${token}" \
    -H "User-Agent: HesabixTelemetry/1.0 (${script_label})" \
    --data-binary "${payload}" \
    "${url}" >/dev/null 2>&1 || true

  return 0
}
