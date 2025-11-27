#!/bin/bash

# Script to install Antigravity on deb-based Linux distributions
# This script requires sudo privileges

set -e  # Exit on error

echo "در حال نصب Antigravity..."

# Step 1: Add the repository to sources.list.d
echo "مرحله 1: اضافه کردن repository..."

# Create keyrings directory
sudo mkdir -p /etc/apt/keyrings

# Download and add the GPG key
echo "در حال دانلود کلید GPG..."
curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/antigravity-repo-key.gpg

# Add repository to sources.list.d
echo "اضافه کردن repository به sources.list.d..."
echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" | \
  sudo tee /etc/apt/sources.list.d/antigravity.list > /dev/null

# Step 2: Update the package cache
echo "مرحله 2: به‌روزرسانی package cache..."
sudo apt update

# Step 3: Install the package
echo "مرحله 3: نصب بسته Antigravity..."
sudo apt install -y antigravity

echo "✅ نصب Antigravity با موفقیت انجام شد!"



