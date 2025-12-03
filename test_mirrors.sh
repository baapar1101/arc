#!/usr/bin/env bash
# Script to test and display available Flutter mirrors

set -euo pipefail

echo "=========================================="
echo "Checking Flutter Mirror Accessibility"
echo "=========================================="
echo ""

# Function to check accessibility of a URL
check_mirror() {
  local name="$1"
  local pub_url="$2"
  local storage_url="$3"
  
  echo -n "🔍 Checking $name..."
  
  # Test PUB URL
  if timeout 10 curl -k -s --connect-timeout 5 -I "$pub_url" >/dev/null 2>&1; then
    echo " ✓ Available"
    echo "   PUB: $pub_url"
    echo "   Storage: $storage_url"
    echo ""
    return 0
  else
    echo " ✗ Not available"
    echo ""
    return 1
  fi
}

# List of all mirrors
declare -a available_mirrors=()

echo "Checking mirrors..."
echo ""

# Mirror 1: TUNA (Tsinghua University)
if check_mirror "TUNA Mirror (Tsinghua)" \
  "https://mirrors.tuna.tsinghua.edu.cn/dart-pub" \
  "https://mirrors.tuna.tsinghua.edu.cn/flutter"; then
  available_mirrors+=("https://mirrors.tuna.tsinghua.edu.cn/dart-pub|https://mirrors.tuna.tsinghua.edu.cn/flutter")
fi

# Mirror 2: SJTU (Shanghai Jiao Tong University)
if check_mirror "SJTU Mirror (Shanghai)" \
  "https://mirror.sjtu.edu.cn/dart-pub" \
  "https://mirror.sjtu.edu.cn"; then
  available_mirrors+=("https://mirror.sjtu.edu.cn/dart-pub|https://mirror.sjtu.edu.cn")
fi

# Mirror 3: Flutter IO CN
if check_mirror "Flutter IO CN" \
  "https://pub.flutter-io.cn" \
  "https://storage.flutter-io.cn"; then
  available_mirrors+=("https://pub.flutter-io.cn|https://storage.flutter-io.cn")
fi

# Mirror 4: Official Pub.dev
if check_mirror "Pub.dev (Official)" \
  "https://pub.dev" \
  "https://storage.googleapis.com"; then
  available_mirrors+=("https://pub.dev|https://storage.googleapis.com")
fi

# Mirror 5: Tencent Cloud
if check_mirror "Tencent Cloud Mirror" \
  "https://mirrors.cloud.tencent.com/dart-pub" \
  "https://mirrors.cloud.tencent.com/flutter"; then
  available_mirrors+=("https://mirrors.cloud.tencent.com/dart-pub|https://mirrors.cloud.tencent.com/flutter")
fi

echo "=========================================="
echo "Result:"
echo "=========================================="

if [ ${#available_mirrors[@]} -eq 0 ]; then
  echo "❌ No accessible mirror found!"
  echo ""
  echo "Possible issues:"
  echo "  1. Internet connection is not available"
  echo "  2. DNS problem exists"
  echo "  3. Firewall is blocking access"
  echo ""
  echo "Solutions:"
  echo "  - Check connection: ping 8.8.8.8"
  echo "  - Configure DNS: cd /var/www/ark && ./fix_dns.sh"
  echo "  - Check firewall"
  exit 1
else
  echo "✅ ${#available_mirrors[@]} accessible mirror(s) found:"
  echo ""
  
  for i in "${!available_mirrors[@]}"; do
    IFS='|' read -r pub_url storage_url <<< "${available_mirrors[$i]}"
    echo "$((i+1)). PUB: $pub_url"
    echo "   Storage: $storage_url"
    echo ""
  done
  
  # Suggest first available mirror
  IFS='|' read -r pub_url storage_url <<< "${available_mirrors[0]}"
  echo "=========================================="
  echo "Using first available mirror:"
  echo "=========================================="
  echo ""
  echo "export PUB_HOSTED_URL=\"$pub_url\""
  echo "export FLUTTER_STORAGE_BASE_URL=\"$storage_url\""
  echo ""
  echo "Or for permanent use, add to ~/.bashrc:"
  echo ""
  echo "echo 'export PUB_HOSTED_URL=\"$pub_url\"' >> ~/.bashrc"
  echo "echo 'export FLUTTER_STORAGE_BASE_URL=\"$storage_url\"' >> ~/.bashrc"
  echo ""
fi

