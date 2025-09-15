#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_DIR="$PROJECT_ROOT/hesabixAPI"

cd "$API_DIR"

echo "Docker باید نصب باشد. این اسکریپت سرویس‌ها را بالا می‌آورد."
echo "برای توقف: docker compose down"

docker compose up -d

echo "برای اجرای مایگریشن داخل کانتینر:"
echo "  docker exec -it hesabix-api alembic upgrade head"
echo "برای مشاهده لاگ‌ها:"
echo "  docker compose logs -f"


