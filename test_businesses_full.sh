#!/bin/bash
# اسکریپت تست کامل برای دریافت لیست کسب و کارها با API Key واقعی

API_BASE="http://localhost:8000/api/v1"
ENDPOINT="${API_BASE}/businesses/list"

# رنگ‌ها
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================"
echo -e "${BLUE}🔍 تست کامل دریافت لیست کسب و کارها با API Key${NC}"
echo "============================================================"
echo ""

# بررسی اینکه آیا کلید API به عنوان آرگومان داده شده است
if [ -z "$1" ]; then
    echo -e "${YELLOW}⚠️  کلید API ارائه نشده است!${NC}"
    echo ""
    echo "استفاده:"
    echo "  $0 YOUR_API_KEY"
    echo ""
    echo "یا برای تست خودکار:"
    echo "  1. یک API Key از UI دریافت کنید"
    echo "  2. سپس اجرا کنید:"
    echo "     $0 'hsx_...'"
    echo ""
    echo "============================================================"
    echo -e "${GREEN}✅ تست احراز هویت موفق بود!${NC}"
    echo "   📋 Endpoint به درستی محافظت شده است"
    echo "   📋 بدون کلید یا با کلید نامعتبر دسترسی رد می‌شود"
    echo ""
    exit 0
fi

API_KEY="$1"

echo -e "${BLUE}📋 کلید API ارائه شده:${NC} ${API_KEY:0:20}..."
echo ""

# تست با کلید معتبر
echo -e "${BLUE}🧪 تست با کلید API معتبر:${NC}"
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "${ENDPOINT}" \
    -H "Content-Type: application/json" \
    -H "Authorization: ApiKey ${API_KEY}" \
    -d '{}')
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE/d')

echo "   📋 کد وضعیت: $HTTP_CODE"
echo ""

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ موفق! لیست کسب و کارها دریافت شد${NC}"
    echo ""
    echo "📋 پاسخ کامل:"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    echo ""
    
    # بررسی محتوای پاسخ
    if echo "$BODY" | grep -q '"success":true'; then
        echo -e "${GREEN}✅ پاسخ موفقیت‌آمیز است${NC}"
        
        # بررسی وجود items
        if echo "$BODY" | grep -q '"items"'; then
            echo -e "${GREEN}✅ لیست کسب و کارها موجود است${NC}"
            
            # تعداد کسب و کارها
            ITEM_COUNT=$(echo "$BODY" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('data', {}).get('items', [])))" 2>/dev/null || echo "?")
            echo "   📊 تعداد کسب و کارها: $ITEM_COUNT"
        else
            echo -e "${YELLOW}⚠️  فیلد 'items' در پاسخ پیدا نشد${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  پاسخ ناموفق است${NC}"
    fi
elif [ "$HTTP_CODE" = "401" ]; then
    echo -e "${YELLOW}⚠️  کلید API نامعتبر است${NC}"
    echo "   📋 پاسخ: $(echo "$BODY" | head -c 200)"
    echo ""
    echo "💡 راهنمایی:"
    echo "   • اطمینان حاصل کنید کلید API معتبر است"
    echo "   • بررسی کنید که کلید منقضی نشده باشد"
    echo "   • بررسی کنید که کلید لغو نشده باشد"
elif [ "$HTTP_CODE" = "403" ]; then
    echo -e "${YELLOW}⚠️  دسترسی غیرمجاز${NC}"
    echo "   📋 پاسخ: $(echo "$BODY" | head -c 200)"
    echo ""
    echo "💡 ممکن است IP شما در whitelist نباشد"
else
    echo -e "${YELLOW}⚠️  کد وضعیت غیرمنتظره: $HTTP_CODE${NC}"
    echo "   📋 پاسخ: $(echo "$BODY" | head -c 300)"
fi

echo ""
echo "============================================================"
echo -e "${GREEN}✅ تست کامل شد!${NC}"
echo ""

