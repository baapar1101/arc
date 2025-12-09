#!/bin/bash
# تست ایجاد تیکت از طریق API

# لطفاً یک API Key معتبر وارد کنید
API_KEY="ak_live_WWoTOqomFhvzdHLHArS7WSL3rHhim2zdNRizDawR7Hw"
API_URL="http://localhost:8000/api/v1/support/tickets"

echo "================================"
echo "تست ایجاد تیکت از طریق API"
echo "================================"
echo ""

# ایجاد تیکت تست
echo "درحال ارسال درخواست ایجاد تیکت..."
echo ""

RESPONSE=$(curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{
    "title": "تیکت تست نوتیفیکیشن",
    "description": "این یک تیکت تست برای بررسی نوتیفیکیشن تلگرام است. لطفا این پیام را در تلگرام دریافت کنید.",
    "category_id": 1,
    "priority_id": 1
  }' -s -w "\nHTTP_CODE:%{http_code}")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE" | cut -d':' -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE/d')

echo "HTTP Status Code: $HTTP_CODE"
echo ""
echo "Response Body:"
echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"

if [ "$HTTP_CODE" = "200" ]; then
    echo ""
    echo "✅ تیکت با موفقیت ایجاد شد!"
    echo ""
    echo "💡 حالا بررسی کنید:"
    echo "   1. آیا نوتیفیکیشن در تلگرام دریافت شده است؟"
    echo "   2. لاگ‌ها را بررسی کنید: journalctl -u hesabix-api -f"
else
    echo ""
    echo "❌ خطا در ایجاد تیکت!"
fi


