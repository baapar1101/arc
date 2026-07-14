#!/usr/bin/env bash
# Resolve and ensure Python >= 3.11 for hesabix-api (pyproject.toml requires-python).
# Used by deploy.sh and update.sh.

: "${HESABIX_MIN_PYTHON_MAJOR:=3}"
: "${HESABIX_MIN_PYTHON_MINOR:=11}"

if ! declare -F hesabix_python_version_ge >/dev/null 2>&1; then
  hesabix_python_version_ge() {
    local ver="${1#Python }"
    ver="${ver%% *}"
    local req_major="$2" req_minor="$3"
    local major minor
    IFS=. read -r major minor _ <<< "${ver}"
    major=${major:-0}
    minor=${minor:-0}
    if [[ "${major}" -gt "${req_major}" ]]; then
      return 0
    fi
    if [[ "${major}" -lt "${req_major}" ]]; then
      return 1
    fi
    [[ "${minor}" -ge "${req_minor}" ]]
  }
fi

if ! declare -F hesabix_python_cmd_version >/dev/null 2>&1; then
  hesabix_python_cmd_version() {
    local cmd="$1"
    "$cmd" --version 2>&1 | awk '{print $2}'
  }
fi

if ! declare -F hesabix_python_cmd_meets_minimum >/dev/null 2>&1; then
  hesabix_python_cmd_meets_minimum() {
    local cmd="$1" ver
    command -v "${cmd}" >/dev/null 2>&1 || return 1
    ver=$(hesabix_python_cmd_version "${cmd}")
    hesabix_python_version_ge "${ver}" "${HESABIX_MIN_PYTHON_MAJOR}" "${HESABIX_MIN_PYTHON_MINOR}"
  }
fi

if ! declare -F hesabix_resolve_backend_python >/dev/null 2>&1; then
  # Prints absolute path to a Python >= 3.11 interpreter.
  # Honors HESABIX_PYTHON when it already meets the minimum.
  hesabix_resolve_backend_python() {
    local cmd ver path
    if [[ -n "${HESABIX_PYTHON:-}" ]]; then
      if [[ -x "${HESABIX_PYTHON}" ]] && hesabix_python_cmd_meets_minimum "${HESABIX_PYTHON}"; then
        printf '%s' "${HESABIX_PYTHON}"
        return 0
      fi
      return 1
    fi
    for cmd in python3.13 python3.12 python3.11 python3; do
      if hesabix_python_cmd_meets_minimum "${cmd}"; then
        path=$(command -v "${cmd}")
        HESABIX_PYTHON="${path}"
        printf '%s' "${path}"
        return 0
      fi
    done
    return 1
  }
fi

if ! declare -F hesabix_install_backend_python_packages >/dev/null 2>&1; then
  # Ubuntu 22.04 ships python3=3.10; install python3.11 from official repos.
  hesabix_install_backend_python_packages() {
    if hesabix_resolve_backend_python >/dev/null 2>&1; then
      return 0
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
      return 1
    fi
    export DEBIAN_FRONTEND=noninteractive
    local minor pkgs=()
    for minor in 12 11; do
      pkgs=("python3.${minor}" "python3.${minor}-venv" "python3.${minor}-dev")
      if apt-get install -y "${pkgs[@]}"; then
        if command -v "python3.${minor}" >/dev/null 2>&1; then
          return 0
        fi
      fi
    done
    return 1
  }
fi

if ! declare -F hesabix_ensure_backend_python >/dev/null 2>&1; then
  hesabix_ensure_backend_python() {
    if hesabix_resolve_backend_python >/dev/null 2>&1; then
      return 0
    fi
    hesabix_install_backend_python_packages || return 1
    hesabix_resolve_backend_python >/dev/null 2>&1
  }
fi

if ! declare -F hesabix_ensure_backend_venv >/dev/null 2>&1; then
  # Create api_dir/.venv with the given interpreter; recreate if Python < minimum.
  # Returns: 0 = ok, 1 = error. Sets HESABIX_VENV_RECREATED=1 when venv was rebuilt.
  hesabix_ensure_backend_venv() {
    local api_dir="$1" python_bin="$2"
    local venv_dir="${api_dir}/.venv"
    local venv_py="${venv_dir}/bin/python"
    HESABIX_VENV_RECREATED=0

    if [[ ! -x "${python_bin}" ]]; then
      return 1
    fi
    if ! hesabix_python_cmd_meets_minimum "${python_bin}"; then
      return 1
    fi

    if [[ -d "${venv_dir}" ]] && [[ -x "${venv_py}" ]]; then
      local venv_ver
      venv_ver=$(hesabix_python_cmd_version "${venv_py}")
      if ! hesabix_python_version_ge "${venv_ver}" "${HESABIX_MIN_PYTHON_MAJOR}" "${HESABIX_MIN_PYTHON_MINOR}"; then
        rm -rf "${venv_dir}"
        HESABIX_VENV_RECREATED=1
      fi
    fi

    if [[ ! -d "${venv_dir}" ]]; then
      "${python_bin}" -m venv "${venv_dir}" || return 1
      HESABIX_VENV_RECREATED=1
    fi
    [[ -x "${venv_py}" ]]
  }
fi
