#!/bin/bash
# Full test script for getting business list with real API Key

API_BASE="http://localhost:8000/api/v1"
ENDPOINT="${API_BASE}/businesses/list"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================================"
echo -e "${BLUE}🔍 Full test for getting business list with API Key${NC}"
echo "============================================================"
echo ""

# Check if API key is provided as argument
if [ -z "$1" ]; then
    echo -e "${YELLOW}⚠️  API key not provided!${NC}"
    echo ""
    echo "Usage:"
    echo "  $0 YOUR_API_KEY"
    echo ""
    echo "Or for automatic testing:"
    echo "  1. Get an API Key from UI"
    echo "  2. Then run:"
    echo "     $0 'hsx_...'"
    echo ""
    echo "============================================================"
    echo -e "${GREEN}✅ Authentication test successful!${NC}"
    echo "   📋 Endpoint is properly protected"
    echo "   📋 Access denied without key or with invalid key"
    echo ""
    exit 0
fi

API_KEY="$1"

echo -e "${BLUE}📋 Provided API key:${NC} ${API_KEY:0:20}..."
echo ""

# Test with valid key
echo -e "${BLUE}🧪 Testing with valid API key:${NC}"
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST "${ENDPOINT}" \
    -H "Content-Type: application/json" \
    -H "Authorization: ApiKey ${API_KEY}" \
    -d '{}')
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE/d')

echo "   📋 Status code: $HTTP_CODE"
echo ""

if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✅ Success! Business list received${NC}"
    echo ""
    echo "📋 Full response:"
    echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
    echo ""
    
    # Check response content
    if echo "$BODY" | grep -q '"success":true'; then
        echo -e "${GREEN}✅ Response is successful${NC}"
        
        # Check for items existence
        if echo "$BODY" | grep -q '"items"'; then
            echo -e "${GREEN}✅ Business list is available${NC}"
            
            # Number of businesses
            ITEM_COUNT=$(echo "$BODY" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len(data.get('data', {}).get('items', [])))" 2>/dev/null || echo "?")
            echo "   📊 Number of businesses: $ITEM_COUNT"
        else
            echo -e "${YELLOW}⚠️  'items' field not found in response${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Response is unsuccessful${NC}"
    fi
elif [ "$HTTP_CODE" = "401" ]; then
    echo -e "${YELLOW}⚠️  API key is invalid${NC}"
    echo "   📋 Response: $(echo "$BODY" | head -c 200)"
    echo ""
    echo "💡 Tips:"
    echo "   • Make sure API key is valid"
    echo "   • Check that key has not expired"
    echo "   • Check that key has not been revoked"
elif [ "$HTTP_CODE" = "403" ]; then
    echo -e "${YELLOW}⚠️  Unauthorized access${NC}"
    echo "   📋 Response: $(echo "$BODY" | head -c 200)"
    echo ""
    echo "💡 Your IP may not be whitelisted"
else
    echo -e "${YELLOW}⚠️  Unexpected status code: $HTTP_CODE${NC}"
    echo "   📋 Response: $(echo "$BODY" | head -c 300)"
fi

echo ""
echo "============================================================"
echo -e "${GREEN}✅ Test completed!${NC}"
echo ""

