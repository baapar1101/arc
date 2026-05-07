#!/bin/bash

# Build Release Package for Hesabix V2 WooCommerce Plugin
# Usage: ./BUILD_RELEASE.sh

VERSION="2.0.0"
PLUGIN_NAME="arcwoc"
RELEASE_DIR="releases"
RELEASE_FILE="${PLUGIN_NAME}-${VERSION}.zip"

echo "🚀 Building ArcWOC (Hesabix V2) Release Package..."
echo "Version: ${VERSION}"
echo ""

# Create releases directory
mkdir -p "${RELEASE_DIR}"

# Remove old release if exists
if [ -f "${RELEASE_DIR}/${RELEASE_FILE}" ]; then
    echo "🗑️  Removing old release..."
    rm "${RELEASE_DIR}/${RELEASE_FILE}"
fi

# Create ZIP package
echo "📦 Creating ZIP package..."
zip -r "${RELEASE_DIR}/${RELEASE_FILE}" . \
    -x "*.git*" \
    -x "*node_modules*" \
    -x "*.DS_Store" \
    -x "*Thumbs.db" \
    -x "*.swp" \
    -x "*.swo" \
    -x "*~" \
    -x "BUILD_RELEASE.sh" \
    -x "releases/*" \
    -x "*.md" \
    -x "composer.json" \
    -x ".gitignore"

# Check if successful
if [ $? -eq 0 ]; then
    SIZE=$(du -h "${RELEASE_DIR}/${RELEASE_FILE}" | cut -f1)
    echo ""
    echo "✅ Release package created successfully!"
    echo "📁 Location: ${RELEASE_DIR}/${RELEASE_FILE}"
    echo "📊 Size: ${SIZE}"
    echo ""
    echo "📋 Next steps:"
    echo "   1. Test the plugin in a staging environment"
    echo "   2. Upload to WordPress plugins directory"
    echo "   3. Or manually install via WordPress admin"
    echo ""
else
    echo "❌ Error creating release package"
    exit 1
fi

