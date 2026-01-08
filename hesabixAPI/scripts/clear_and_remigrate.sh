#!/bin/bash
# اسکریپت پاک کردن داده‌ها و migration مجدد

cd "$(dirname "$0")/.."
source .venv/bin/activate

echo "======================================================================"
echo "🧹 پاک کردن داده‌ها و Migration مجدد"
echo "======================================================================"
echo ""
echo "⚠️ این اسکریپت:"
echo "   1. همه داده‌های PostgreSQL را پاک می‌کند"
echo "   2. Checkpoint را پاک می‌کند"
echo "   3. Migration را از اول شروع می‌کند"
echo ""
read -p "آیا مطمئن هستید؟ (yes/no): " response

if [ "$response" != "yes" ]; then
    echo "❌ عملیات لغو شد"
    exit 1
fi

echo ""
echo "🧹 مرحله 1: پاک کردن داده‌ها..."
python scripts/clear_all_data.py <<< "yes"

echo ""
echo "🗑️ مرحله 2: پاک کردن checkpoint..."
rm -f migration_checkpoint.json migration_checkpoint.json.bak
echo "✅ Checkpoint پاک شد"

echo ""
echo "🚀 مرحله 3: شروع migration از اول..."
python scripts/migrate_mysql_to_postgresql.py --no-clear-seed

echo ""
echo "✅ تمام!"
