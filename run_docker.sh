#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_DIR="$PROJECT_ROOT/hesabixAPI"

cd "$API_DIR"

echo "Docker must be installed. This script brings up the services."
echo "To stop: docker compose down"

docker compose up -d

echo "To run migrations inside container:"
echo "  docker exec -it hesabix-api alembic upgrade head"
echo "To view logs:"
echo "  docker compose logs -f"


