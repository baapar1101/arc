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

# Install with development dependencies for running tests
pip install --no-input -e .[dev]

# Create .env if not present
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
  serve-workers)
    # Run uvicorn with multiple workers (without reload)
    WORKERS=${WORKERS:-4}
    uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers "$WORKERS"
    ;;
  *)
    echo "Usage: $0 [serve|serve-workers|migrate|test]"
    exit 1
    ;;
esac


