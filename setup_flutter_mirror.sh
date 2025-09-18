#!/bin/bash

# Flutter Mirror Setup Script
# Based on https://docs.flutter.dev/community/china

echo "Setting up Flutter mirror for better package access..."

# Set environment variables for current session
export PUB_HOSTED_URL="https://pub.flutter-io.cn"
export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"

echo "Environment variables set for current session:"
echo "PUB_HOSTED_URL=$PUB_HOSTED_URL"
echo "FLUTTER_STORAGE_BASE_URL=$FLUTTER_STORAGE_BASE_URL"

# Add to shell profile for permanent setup
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
    echo "# Flutter Mirror Configuration" >> "$SHELL_RC"
    echo "export PUB_HOSTED_URL=\"https://pub.flutter-io.cn\"" >> "$SHELL_RC"
    echo "export FLUTTER_STORAGE_BASE_URL=\"https://storage.flutter-io.cn\"" >> "$SHELL_RC"
    echo "Added Flutter mirror configuration to $SHELL_RC"
else
    echo "Warning: Could not find shell profile file to add permanent configuration"
fi

echo ""
echo "Setup complete! You can now run:"
echo "  flutter pub get"
echo "  flutter pub upgrade"
echo "  flutter pub add <package_name>"
echo ""
echo "Note: You may need to restart your terminal or run 'source $SHELL_RC' for permanent changes to take effect."
