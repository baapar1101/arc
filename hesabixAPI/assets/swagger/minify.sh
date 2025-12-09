#!/bin/bash
# اسکریپت Minify کردن فایل‌های CSS برای Swagger UI

echo "🔧 شروع Minify کردن فایل‌های CSS..."

# رنگ‌ها برای خروجی
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# دایرکتوری فعلی
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# بررسی وجود python3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python3 یافت نشد!${NC}"
    exit 1
fi

# Minify کردن custom.css
echo -e "${BLUE}📦 Minify کردن custom.css...${NC}"
python3 -c "
import re
with open('$DIR/custom.css', 'r', encoding='utf-8') as f:
    content = f.read()
# حذف کامنت‌ها
content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
# حذف فضاهای خالی اضافی
content = re.sub(r'\s+', ' ', content)
# حذف فضا قبل و بعد از { } : ; ,
content = re.sub(r'\s*([{}:;,])\s*', r'\1', content)
# نوشتن فایل minified
with open('$DIR/custom.min.css', 'w', encoding='utf-8') as f:
    f.write(content.strip())
"
echo -e "${GREEN}✓ custom.min.css ایجاد شد${NC}"

# Minify کردن swagger-rtl.css
echo -e "${BLUE}📦 Minify کردن swagger-rtl.css...${NC}"
python3 -c "
import re
with open('$DIR/swagger-rtl.css', 'r', encoding='utf-8') as f:
    content = f.read()
content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
content = re.sub(r'\s+', ' ', content)
content = re.sub(r'\s*([{}:;,])\s*', r'\1', content)
with open('$DIR/swagger-rtl.min.css', 'w', encoding='utf-8') as f:
    f.write(content.strip())
"
echo -e "${GREEN}✓ swagger-rtl.min.css ایجاد شد${NC}"

# Minify کردن dark-mode.css
echo -e "${BLUE}📦 Minify کردن dark-mode.css...${NC}"
python3 -c "
import re
with open('$DIR/dark-mode.css', 'r', encoding='utf-8') as f:
    content = f.read()
content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
content = re.sub(r'\s+', ' ', content)
content = re.sub(r'\s*([{}:;,])\s*', r'\1', content)
with open('$DIR/dark-mode.min.css', 'w', encoding='utf-8') as f:
    f.write(content.strip())
"
echo -e "${GREEN}✓ dark-mode.min.css ایجاد شد${NC}"

# نمایش اندازه فایل‌ها
echo ""
echo -e "${BLUE}📊 مقایسه اندازه فایل‌ها:${NC}"
echo ""

for file in custom swagger-rtl dark-mode; do
    if [ -f "$DIR/${file}.css" ]; then
        original_size=$(wc -c < "$DIR/${file}.css")
        minified_size=$(wc -c < "$DIR/${file}.min.css")
        reduction=$(( 100 - (minified_size * 100 / original_size) ))
        
        echo -e "${file}.css:"
        echo -e "  اصلی: ${original_size} bytes"
        echo -e "  Minified: ${minified_size} bytes"
        echo -e "  ${GREEN}کاهش: ${reduction}%${NC}"
        echo ""
    fi
done

echo -e "${GREEN}✅ تمام فایل‌های CSS با موفقیت Minify شدند!${NC}"
echo ""
echo -e "${BLUE}💡 نکته: برای استفاده در production از فایل‌های .min.css استفاده کنید${NC}"


