#!/usr/bin/env bash
# Ensure production API secrets exist in hesabixAPI/.env (idempotent).
# Called from deploy.sh and update.sh (hesabix -update).
set -euo pipefail

APP_ROOT="${APP_ROOT:-/opt/hesabix}"
API_DIR="${API_DIR:-${APP_ROOT}/app/hesabixAPI}"
ENV_FILE="${ENV_FILE:-${API_DIR}/.env}"

log() { echo "ensure_api_production_secrets: $*" >&2; }

if [[ ! -f "${ENV_FILE}" ]]; then
  log "no .env at ${ENV_FILE}; skip"
  exit 0
fi

export MERGE_ENV_PATH="${ENV_FILE}"
export MERGE_DB_PASSWORD_FILE="${APP_ROOT}/.db_password"

result="$(python3 <<'PY'
import os
import re
import secrets

path = os.environ["MERGE_ENV_PATH"]
INSECURE = frozenset(
    {
        "",
        "change_me",
        "change_me_captcha",
        "change_me_share_link",
        "default-secret-key-change-me",
    }
)

SECRET_KEYS = (
    "CAPTCHA_SECRET",
    "SHARE_LINK_SECRET",
    "ENCRYPTION_KEY",
    "WALLET_WEBHOOK_SECRET",
)


def fmt_val(v: str) -> str:
    if re.search(r'[\s#"\'\\]', v) or v.startswith("#"):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    return v


def parse_dotenv_value(raw: str) -> str:
    raw = raw.strip()
    if not raw:
        return ""
    if (raw.startswith('"') and raw.endswith('"')) or (raw.startswith("'") and raw.endswith("'")):
        return raw[1:-1]
    return raw


def read_lines(path: str) -> list[str]:
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.readlines()


def current_values(lines: list[str]) -> dict[str, str]:
    key_re = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
    out: dict[str, str] = {}
    for line in lines:
        m = key_re.match(line.strip())
        if m:
            out[m.group(1)] = parse_dotenv_value(m.group(2))
    return out


def gen_secret() -> str:
    return secrets.token_hex(32)


lines = read_lines(path)
current = current_values(lines)
updates: dict[str, str] = {}
generated: list[str] = []

for key in SECRET_KEYS:
    if current.get(key, "").strip() in INSECURE:
        updates[key] = gen_secret()
        generated.append(key)

db_pw_file = os.environ.get("MERGE_DB_PASSWORD_FILE", "")
if db_pw_file and os.path.isfile(db_pw_file):
    with open(db_pw_file, encoding="utf-8") as f:
        db_pw = f.read().strip()
    if db_pw and current.get("DB_PASSWORD", "").strip() in INSECURE:
        updates["DB_PASSWORD"] = db_pw
        generated.append("DB_PASSWORD")

if not updates:
    print("ok")
    raise SystemExit(0)

key_re = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=")
keys_done: set[str] = set()
out: list[str] = []
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

print("generated:" + ",".join(generated))
PY
)"

case "${result}" in
  ok)
    log ".env production secrets already present"
    ;;
  generated:*)
    keys="${result#generated:}"
    log "generated missing/insecure secrets: ${keys}"
    ;;
  *)
    log "unexpected result: ${result}"
    exit 1
    ;;
esac

if id -u www-data >/dev/null 2>&1; then
  chown www-data:www-data "${ENV_FILE}" 2>/dev/null || true
fi
chmod 600 "${ENV_FILE}" 2>/dev/null || true
