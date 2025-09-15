#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_DIR="$PROJECT_ROOT/hesabixAPI"

cd "$API_DIR"

if [ ! -d .venv ]; then
  python3 -m venv .venv
fi

source .venv/bin/activate
python -m pip install --upgrade pip

# نصب با وابستگی‌های توسعه برای اجرای تست‌ها
pip install --no-input -e .[dev]

# ایجاد .env در صورت نبود
if [ ! -f .env ]; then
  cp -n env.example .env || true
fi

CMD="${1:-serve}"

case "$CMD" in
  migrate)
    alembic upgrade head
    ;;
  test)
    pytest -q
    ;;
  serve)
    uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
    ;;
  *)
    echo "Usage: $0 [serve|migrate|test]"
    exit 1
    ;;
esac


