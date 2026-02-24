#!/bin/bash
# Script to fix ios-font-driver.patch by removing malformed hunks

cd ~/Syntropment/hyalo-feedstock-unified

# Create backup
cp patches/ios-font-driver.patch patches/ios-font-driver.patch.bak

# The problematic hunks are those with incorrect line numbers
# Let's extract only the valid hunks (1-18) and skip the problematic ones

# Lines 1-372 contain the first 17 hunks which should be valid
head -372 patches/ios-font-driver.patch.bak > patches/ios-font-driver.patch

# Now we need to add the final newline for a clean patch
echo "" >> patches/ios-font-driver.patch

echo "Created fixed patch with first 17 hunks"
echo "Original patch has $(wc -l < patches/ios-font-driver.patch.bak) lines"
echo "Fixed patch has $(wc -l < patches/ios-font-driver.patch) lines"

# Test the fixed patch
cd emacs-build-ios-sim
patch -p1 --dry-run < ../patches/ios-font-driver.patch 2>&1 | tail -5
