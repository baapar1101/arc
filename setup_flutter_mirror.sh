#!/bin/bash
# فقط آینهٔ داخلی Hesabix (همان build_web.sh / deploy.sh)

echo "تنظیم آینه Flutter روی f.mirror.hesabix.ir..."

export PUB_HOSTED_URL="https://f.mirror.hesabix.ir/pub"
export FLUTTER_STORAGE_BASE_URL="https://f.mirror.hesabix.ir/gcs"

echo "PUB_HOSTED_URL=$PUB_HOSTED_URL"
echo "FLUTTER_STORAGE_BASE_URL=$FLUTTER_STORAGE_BASE_URL"

SHELL_RC=""
if [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"
elif [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.profile" ]; then
    SHELL_RC="$HOME/.profile"
fi

if [ -n "$SHELL_RC" ]; then
    echo "" >> "$SHELL_RC"
    echo "# Flutter mirror (Hesabix f.mirror)" >> "$SHELL_RC"
    echo "export PUB_HOSTED_URL=\"https://f.mirror.hesabix.ir/pub\"" >> "$SHELL_RC"
    echo "export FLUTTER_STORAGE_BASE_URL=\"https://f.mirror.hesabix.ir/gcs\"" >> "$SHELL_RC"
    echo "ثبت در $SHELL_RC"
else
    echo "پروفایل شل پیدا نشد؛ فقط برای این نشست فعال است."
fi
