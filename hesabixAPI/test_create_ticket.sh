#!/bin/bash
# اسکریپت ایجاد تیکت تست و بررسی نوتیفیکیشن

echo "================================"
echo "ایجاد تیکت تست"
echo "================================"

# دریافت توکن احراز هویت (فرض می‌کنیم اطلاعات کاربری داریم)
# شما باید توکن معتبر خود را وارد کنید

TOKEN="your_auth_token_here"
API_URL="http://localhost:8000/api/v1/support/tickets"

# اگر توکن تنظیم نشده، از کاربر بخواهیم
if [ "$TOKEN" == "your_auth_token_here" ]; then
    echo "لطفاً توکن احراز هویت را وارد کنید:"
    echo "می‌توانید با دستور زیر لاگین کنید و توکن بگیرید:"
    echo "curl -X POST http://localhost:8000/api/v1/auth/login -H 'Content-Type: application/json' -d '{\"email\":\"your_email\",\"password\":\"your_password\"}'"
    echo ""
    read -p "توکن: " TOKEN
fi

# ایجاد تیکت
echo ""
echo "در حال ارسال درخواست ایجاد تیکت..."

RESPONSE=$(curl -s -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{
        "title": "تست نوتیفیکیشن تلگرام",
        "description": "این یک تیکت تست برای بررسی نوتیفیکیشن تلگرام به اپراتورها است. زمان: '"$(date '+%Y-%m-%d %H:%M:%S')"'",
        "category_id": 1,
        "priority_id": 1
    }')

echo "پاسخ سرور:"
echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"

# استخراج ticket_id
TICKET_ID=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('data', {}).get('id', ''))" 2>/dev/null)

if [ -n "$TICKET_ID" ] && [ "$TICKET_ID" != "" ]; then
    echo ""
    echo "✅ تیکت با شماره #$TICKET_ID ایجاد شد"
    echo ""
    echo "در حال بررسی نوتیفیکیشن‌ها..."
    sleep 2
    
    cd /var/www/ark/hesabixAPI
    source venv/bin/activate
    python3 check_notification_issue.py
else
    echo "❌ خطا در ایجاد تیکت"
fi



