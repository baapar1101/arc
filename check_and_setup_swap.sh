#!/usr/bin/env bash

# Script to check and configure swap if needed
# This script helps resolve OOM (Out of Memory) issues in Flutter builds

set -euo pipefail

SWAP_SIZE_GB="${1:-4}"  # Default 4GB
SWAP_FILE="/swapfile"

echo "Checking swap status..."
if swapon --show | grep -q "$SWAP_FILE"; then
    echo "✓ Swap file is already active:"
    swapon --show
    exit 0
fi

if [ -f "$SWAP_FILE" ]; then
    echo "✓ Swap file exists but is not active. Activating..."
    sudo swapon "$SWAP_FILE"
    swapon --show
    exit 0
fi

echo "Swap file not found. Creating swap file of size ${SWAP_SIZE_GB}GB..."

# Check disk space
AVAILABLE_SPACE=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
if [ "$AVAILABLE_SPACE" -lt "$SWAP_SIZE_GB" ]; then
    echo "⚠ Warning: Insufficient disk space. Available: ${AVAILABLE_SPACE}GB, Required: ${SWAP_SIZE_GB}GB"
    echo "Creating swap file with size ${AVAILABLE_SPACE}GB..."
    SWAP_SIZE_GB="$AVAILABLE_SPACE"
fi

# Create swap file
echo "Creating swap file (this may take a few minutes)..."
sudo fallocate -l "${SWAP_SIZE_GB}G" "$SWAP_FILE" || {
    echo "fallocate not supported. Using dd..."
    sudo dd if=/dev/zero of="$SWAP_FILE" bs=1G count="$SWAP_SIZE_GB" status=progress
}

# Set permissions
sudo chmod 600 "$SWAP_FILE"

# Format as swap
sudo mkswap "$SWAP_FILE"

# Activate swap
sudo swapon "$SWAP_FILE"

# Add to /etc/fstab for activation after reboot
if ! grep -q "$SWAP_FILE" /etc/fstab 2>/dev/null; then
    echo "Adding swap to /etc/fstab..."
    echo "$SWAP_FILE none swap sw 0 0" | sudo tee -a /etc/fstab
fi

echo ""
echo "✓ Swap file successfully created and activated:"
swapon --show
echo ""
echo "Total system memory:"
free -h

