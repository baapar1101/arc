#!/usr/bin/env bash
# Shared PyPI / Flutter mirror presets and prompts for deploy.sh, update.sh, build_web.sh.
# Non-interactive: PIP_MIRROR=hesabix|official|tuna|aliyun|custom
#                 FLUTTER_MIRROR=hesabix|pub_azs|flutter_io_cn|tuna|sjtu|official|custom
# Direct URL override (advanced): PIP_INDEX_URL, PUB_HOSTED_URL, FLUTTER_STORAGE_BASE_URL

# shellcheck disable=SC2034
HESABIX_PIP_INDEX_URL="https://p.mirror.hesabix.ir/simple"
HESABIX_PIP_TRUSTED_HOST="p.mirror.hesabix.ir"
HESABIX_PUB_HOSTED_URL="https://f.mirror.hesabix.ir/pub"
HESABIX_FLUTTER_STORAGE_BASE_URL="https://f.mirror.hesabix.ir/gcs"

hesabix_mirror_log_info() {
  if declare -F log_info >/dev/null 2>&1; then
    log_info "$@"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  fi
}

hesabix_mirror_log_warning() {
  if declare -F log_warning >/dev/null 2>&1; then
    log_warning "$@"
  elif declare -F log_warn >/dev/null 2>&1; then
    log_warn "$@"
  else
    echo "WARNING: $*" >&2
  fi
}

# Normalize pip index URL (ensure /simple suffix for custom input).
hesabix_normalize_pip_index_url() {
  local url="${1%/}"
  case "${url}" in
    */simple) printf '%s' "${url}" ;;
    *) printf '%s/simple' "${url}" ;;
  esac
}

hesabix_pip_trusted_host_from_url() {
  local index_url="$1"
  if [[ "${index_url}" == *"pypi.org"* ]]; then
    return 0
  fi
  echo "${index_url}" | sed -n 's|https\?://\([^/]*\).*|\1|p'
}

hesabix_set_pip_mirror_for_url() {
  local index_url
  index_url="$(hesabix_normalize_pip_index_url "$1")"
  export PIP_INDEX_URL="${index_url}"
  if [[ "${index_url}" != *"pypi.org"* ]]; then
    export PIP_TRUSTED_HOST="$(hesabix_pip_trusted_host_from_url "${index_url}")"
  else
    unset PIP_TRUSTED_HOST
  fi
}

hesabix_resolve_pip_mirror_from_preset() {
  local preset="${1:-hesabix}"
  preset="${preset,,}"
  case "${preset}" in
    hesabix|default)
      hesabix_set_pip_mirror_for_url "${HESABIX_PIP_INDEX_URL}"
      ;;
    official|pypi)
      hesabix_set_pip_mirror_for_url "https://pypi.org/simple"
      ;;
    tuna|tsinghua)
      hesabix_set_pip_mirror_for_url "https://pypi.tuna.tsinghua.edu.cn/simple"
      ;;
    aliyun)
      hesabix_set_pip_mirror_for_url "https://mirrors.aliyun.com/pypi/simple"
      ;;
    custom)
      if [[ -z "${PIP_INDEX_URL:-}" ]]; then
        hesabix_mirror_log_warning "PIP_MIRROR=custom but PIP_INDEX_URL is empty; falling back to Hesabix."
        PIP_MIRROR=hesabix
        export PIP_MIRROR
        hesabix_set_pip_mirror_for_url "${HESABIX_PIP_INDEX_URL}"
        return 0
      fi
      hesabix_set_pip_mirror_for_url "${PIP_INDEX_URL}"
      ;;
    *)
      hesabix_mirror_log_warning "Unknown PIP_MIRROR='${preset}'; using Hesabix."
      PIP_MIRROR=hesabix
      export PIP_MIRROR
      hesabix_set_pip_mirror_for_url "${HESABIX_PIP_INDEX_URL}"
      ;;
  esac
}

hesabix_resolve_flutter_mirror_from_preset() {
  local preset="${1:-hesabix}"
  preset="${preset,,}"
  case "${preset}" in
    hesabix|default)
      export PUB_HOSTED_URL="${HESABIX_PUB_HOSTED_URL}"
      export FLUTTER_STORAGE_BASE_URL="${HESABIX_FLUTTER_STORAGE_BASE_URL}"
      ;;
    pub_azs|pub-azs|azs)
      export PUB_HOSTED_URL="https://pub-azs.ir"
      export FLUTTER_STORAGE_BASE_URL="https://pub-azs.ir"
      ;;
    flutter_io_cn|china|flutter-io)
      export PUB_HOSTED_URL="https://pub.flutter-io.cn"
      export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
      ;;
    tuna|tsinghua)
      export PUB_HOSTED_URL="https://mirrors.tuna.tsinghua.edu.cn/dart-pub"
      export FLUTTER_STORAGE_BASE_URL="https://mirrors.tuna.tsinghua.edu.cn/flutter"
      ;;
    sjtu)
      export PUB_HOSTED_URL="https://mirror.sjtu.edu.cn/dart-pub"
      export FLUTTER_STORAGE_BASE_URL="https://mirror.sjtu.edu.cn"
      ;;
    official|pubdev)
      export PUB_HOSTED_URL="https://pub.dev"
      export FLUTTER_STORAGE_BASE_URL="https://storage.googleapis.com"
      ;;
    custom)
      if [[ -z "${PUB_HOSTED_URL:-}" || -z "${FLUTTER_STORAGE_BASE_URL:-}" ]]; then
        hesabix_mirror_log_warning "FLUTTER_MIRROR=custom but PUB_HOSTED_URL/FLUTTER_STORAGE_BASE_URL missing; falling back to Hesabix."
        FLUTTER_MIRROR=hesabix
        export FLUTTER_MIRROR
        export PUB_HOSTED_URL="${HESABIX_PUB_HOSTED_URL}"
        export FLUTTER_STORAGE_BASE_URL="${HESABIX_FLUTTER_STORAGE_BASE_URL}"
        return 0
      fi
      export PUB_HOSTED_URL FLUTTER_STORAGE_BASE_URL
      ;;
    *)
      hesabix_mirror_log_warning "Unknown FLUTTER_MIRROR='${preset}'; using Hesabix."
      FLUTTER_MIRROR=hesabix
      export FLUTTER_MIRROR
      export PUB_HOSTED_URL="${HESABIX_PUB_HOSTED_URL}"
      export FLUTTER_STORAGE_BASE_URL="${HESABIX_FLUTTER_STORAGE_BASE_URL}"
      ;;
  esac
}

# Apply pip mirror: env PIP_INDEX_URL wins; else PIP_MIRROR preset; else Hesabix.
hesabix_apply_pip_mirror_env() {
  if [[ -n "${PIP_INDEX_URL:-}" ]]; then
    hesabix_mirror_log_info "Using PyPI index from environment: PIP_INDEX_URL=${PIP_INDEX_URL}"
    hesabix_set_pip_mirror_for_url "${PIP_INDEX_URL}"
    return 0
  fi
  PIP_MIRROR="${PIP_MIRROR:-hesabix}"
  export PIP_MIRROR
  hesabix_resolve_pip_mirror_from_preset "${PIP_MIRROR}"
  hesabix_mirror_log_info "Using PyPI mirror (${PIP_MIRROR}): ${PIP_INDEX_URL}"
}

# Apply Flutter mirror: explicit URLs win; else FLUTTER_MIRROR preset; else Hesabix.
hesabix_apply_flutter_mirror_env() {
  if [[ -n "${PUB_HOSTED_URL:-}" && -n "${FLUTTER_STORAGE_BASE_URL:-}" ]]; then
    export PUB_HOSTED_URL FLUTTER_STORAGE_BASE_URL
    hesabix_mirror_log_info "Using Flutter mirrors from environment: PUB_HOSTED_URL=${PUB_HOSTED_URL}"
    return 0
  fi
  FLUTTER_MIRROR="${FLUTTER_MIRROR:-hesabix}"
  export FLUTTER_MIRROR
  hesabix_resolve_flutter_mirror_from_preset "${FLUTTER_MIRROR}"
  hesabix_mirror_log_info "Flutter pub/storage (${FLUTTER_MIRROR}): PUB_HOSTED_URL=${PUB_HOSTED_URL}"
}

hesabix_configure_pip_mirror() {
  if ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi
  hesabix_apply_pip_mirror_env
  python3 -m pip config --user set global.index "${PIP_INDEX_URL}" 2>/dev/null || true
  python3 -m pip config --user set global.index-url "${PIP_INDEX_URL}" 2>/dev/null || true
  if [[ -n "${PIP_TRUSTED_HOST:-}" ]]; then
    python3 -m pip config --user set global.trusted-host "${PIP_TRUSTED_HOST}" 2>/dev/null || true
  fi
  hesabix_mirror_log_info "pip user config: ${PIP_INDEX_URL}"
}

hesabix_prompt_pip_mirror() {
  if [[ -n "${PIP_INDEX_URL:-}" ]]; then
    return 0
  fi
  PIP_MIRROR="${PIP_MIRROR:-}"
  PIP_MIRROR="${PIP_MIRROR,,}"
  if [[ -n "${PIP_MIRROR}" ]]; then
    return 0
  fi
  echo
  echo "مخزن پایتون (pip / PyPI) — برای نصب وابستگی‌های بک‌اند:"
  echo "  [1] Hesabix — p.mirror.hesabix.ir (پیش‌فرض؛ مناسب ایران)"
  echo "  [2] رسمی — pypi.org"
  echo "  [3] آینه تسینگ‌هوا (چین) — pypi.tuna.tsinghua.edu.cn"
  echo "  [4] آینه علی‌بابا (چین) — mirrors.aliyun.com/pypi"
  echo "  [5] آدرس سفارشی (خودتان وارد کنید)"
  read -rp "انتخاب [1-5] (پیش‌فرض 1): " _pip_choice
  _pip_choice=${_pip_choice:-1}
  case "${_pip_choice}" in
    2) PIP_MIRROR=official ;;
    3) PIP_MIRROR=tuna ;;
    4) PIP_MIRROR=aliyun ;;
    5)
      PIP_MIRROR=custom
      read -rp "آدرس index (مثال https://my.mirror/simple): " _pip_custom
      if [[ -n "${_pip_custom}" ]]; then
        PIP_INDEX_URL="$(hesabix_normalize_pip_index_url "${_pip_custom}")"
        export PIP_INDEX_URL
      fi
      ;;
    *) PIP_MIRROR=hesabix ;;
  esac
  export PIP_MIRROR
}

hesabix_prompt_flutter_mirror() {
  if [[ -n "${PUB_HOSTED_URL:-}" && -n "${FLUTTER_STORAGE_BASE_URL:-}" ]]; then
    return 0
  fi
  FLUTTER_MIRROR="${FLUTTER_MIRROR:-}"
  FLUTTER_MIRROR="${FLUTTER_MIRROR,,}"
  if [[ -n "${FLUTTER_MIRROR}" ]]; then
    return 0
  fi
  echo
  echo "مخزن Flutter/Dart (pub get و engine) — برای بیلد رابط کاربری:"
  echo "  [1] Hesabix — f.mirror.hesabix.ir (پیش‌فرض؛ مناسب ایران)"
  echo "  [2] pub-azs.ir — مستقیم (ایران)"
  echo "  [3] چین — pub.flutter-io.cn / storage.flutter-io.cn"
  echo "  [4] آینه تسینگ‌هوا (چین)"
  echo "  [5] آینه شانگهای SJTU (چین)"
  echo "  [6] رسمی — pub.dev / storage.googleapis.com"
  echo "  [7] آدرس سفارشی"
  read -rp "انتخاب [1-7] (پیش‌فرض 1): " _flutter_choice
  _flutter_choice=${_flutter_choice:-1}
  case "${_flutter_choice}" in
    2) FLUTTER_MIRROR=pub_azs ;;
    3) FLUTTER_MIRROR=flutter_io_cn ;;
    4) FLUTTER_MIRROR=tuna ;;
    5) FLUTTER_MIRROR=sjtu ;;
    6) FLUTTER_MIRROR=official ;;
    7)
      FLUTTER_MIRROR=custom
      read -rp "PUB_HOSTED_URL (مثال https://pub.example): " _pub_url
      read -rp "FLUTTER_STORAGE_BASE_URL (مثال https://storage.example): " _storage_url
      if [[ -n "${_pub_url}" && -n "${_storage_url}" ]]; then
        export PUB_HOSTED_URL="${_pub_url%/}"
        export FLUTTER_STORAGE_BASE_URL="${_storage_url%/}"
      fi
      ;;
    *) FLUTTER_MIRROR=hesabix ;;
  esac
  export FLUTTER_MIRROR
}

hesabix_mirror_summary_pip() {
  hesabix_apply_pip_mirror_env >/dev/null 2>&1 || true
  if [[ "${PIP_MIRROR:-}" == "custom" ]]; then
    echo "  • PyPI (pip):     custom — ${PIP_INDEX_URL:-}"
  else
    echo "  • PyPI (pip):     ${PIP_MIRROR:-hesabix} — ${PIP_INDEX_URL:-}"
  fi
}

hesabix_mirror_summary_flutter() {
  hesabix_apply_flutter_mirror_env >/dev/null 2>&1 || true
  if [[ "${FLUTTER_MIRROR:-}" == "custom" ]]; then
    echo "  • Flutter pub:    custom — ${PUB_HOSTED_URL:-}"
    echo "  • Flutter storage: ${FLUTTER_STORAGE_BASE_URL:-}"
  else
    echo "  • Flutter pub:    ${FLUTTER_MIRROR:-hesabix} — ${PUB_HOSTED_URL:-}"
    echo "  • Flutter storage: ${FLUTTER_STORAGE_BASE_URL:-}"
  fi
}

# Write mirror vars into .deploy_env (append/update keys).
hesabix_persist_mirror_to_deploy_env() {
  local env_file="${1:-/opt/hesabix/.deploy_env}"
  [[ -f "${env_file}" ]] || return 0
  hesabix_apply_pip_mirror_env
  hesabix_apply_flutter_mirror_env
  local tmp
  tmp=$(mktemp)
  grep -vE '^(PIP_MIRROR|FLUTTER_MIRROR|PIP_INDEX_URL|PIP_TRUSTED_HOST|PUB_HOSTED_URL|FLUTTER_STORAGE_BASE_URL)=' "${env_file}" > "${tmp}" 2>/dev/null || true
  {
    cat "${tmp}"
    echo "PIP_MIRROR=${PIP_MIRROR:-hesabix}"
    echo "FLUTTER_MIRROR=${FLUTTER_MIRROR:-hesabix}"
    echo "PIP_INDEX_URL=${PIP_INDEX_URL:-}"
    echo "PIP_TRUSTED_HOST=${PIP_TRUSTED_HOST:-}"
    echo "PUB_HOSTED_URL=${PUB_HOSTED_URL:-}"
    echo "FLUTTER_STORAGE_BASE_URL=${FLUTTER_STORAGE_BASE_URL:-}"
  } > "${env_file}.new"
  mv "${env_file}.new" "${env_file}"
  chmod 600 "${env_file}" 2>/dev/null || true
  rm -f "${tmp}"
}

# Backward-compatible aliases used by deploy.sh
configure_pip_hesabix_mirror() { hesabix_configure_pip_mirror "$@"; }
set_pip_mirror_env() { hesabix_apply_pip_mirror_env "$@"; }
set_flutter_mirror_env() { hesabix_apply_flutter_mirror_env "$@"; }
