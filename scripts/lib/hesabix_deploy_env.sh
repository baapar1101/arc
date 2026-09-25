#!/usr/bin/env bash
# Read/write Hesabix deployment env files (.deploy_env, .deploy_saved_vars).

APP_ROOT="${APP_ROOT:-/opt/hesabix}"
HESABIX_DEPLOY_ENV="${APP_ROOT}/.deploy_env"
HESABIX_DEPLOY_SAVED_VARS="${APP_ROOT}/.deploy_saved_vars"

hesabix_require_deploy_env() {
  if [[ ! -f "${HESABIX_DEPLOY_ENV}" ]]; then
    echo "Hesabix not deployed yet (${HESABIX_DEPLOY_ENV} missing). Run deploy.sh first." >&2
    return 1
  fi
}

hesabix_load_deploy_env() {
  hesabix_require_deploy_env || return 1
  set -a
  # shellcheck source=/dev/null
  source "${HESABIX_DEPLOY_ENV}"
  set +a
  if [[ -f "${HESABIX_DEPLOY_SAVED_VARS}" ]]; then
    local line key val
    while IFS= read -r line; do
      [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      if [[ -z "${!key:-}" ]]; then
        export "${key}=${val}"
      fi
    done < "${HESABIX_DEPLOY_SAVED_VARS}"
  fi
}

# Usage: hesabix_patch_env_file /path/to/file KEY=val KEY2=val2 ...
hesabix_patch_env_file() {
  local file="$1"
  shift
  [[ $# -gt 0 ]] || return 0
  python3 - "$file" "$@" <<'PY'
import os
import re
import sys

path = sys.argv[1]
updates = {}
for item in sys.argv[2:]:
    key, _, val = item.partition("=")
    if key:
        updates[key] = val

lines = []
if os.path.isfile(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = f.readlines()

key_re = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=")
out = []
done = set()
for line in lines:
    m = key_re.match(line)
    if m and m.group(1) in updates:
        k = m.group(1)
        out.append(f"{k}={updates[k]}\n")
        done.add(k)
    else:
        out.append(line)
for k, v in updates.items():
    if k not in done:
        out.append(f"{k}={v}\n")

os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
with open(path, "w", encoding="utf-8") as f:
    f.writelines(out)
PY
  chmod 600 "${file}" 2>/dev/null || true
}

hesabix_validate_domain() {
  local domain="$1"
  if [[ ! "${domain}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
    echo "Invalid domain format: ${domain}" >&2
    return 1
  fi
  return 0
}
