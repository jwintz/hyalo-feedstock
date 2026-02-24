#!/bin/bash
cd ~/Syntropment/hyalo-feedstock-unified/emacs-build-ios-sim

patches=(
  "system-appearance.patch"
  "frame-transparency.patch"
  "unidata-gen-incf.patch"
  "loaddefs-gen-fix.patch"
  "derived-fix.patch"
  "ios-build-system.patch"
  "ios-libs.patch"
  "ios-frame.patch"
  "ios-xfaces.patch"
  "ios-image.patch"
  "ios-font-driver.patch"
  "ios-font.patch"
  "ios-configure-full.patch"
  "ios-dispnew.patch"
  "ios-epaths.patch"
  "ios-emacs-entry.patch"
  "ios-compat.patch"
  "ios-macroexp.patch"
  "ios-terminal.patch"
  "ios-debug.patch"
  "ios-checkstring.patch"
  "ios-loadup.patch"
  "ios-bidi.patch"
  "ios-try-window.patch"
  "ios-character.patch"
  "ios-bootstrap-progress.patch"
  "ios-frame-lisp.patch"
  "ios-faces-lisp.patch"
  "ios-cus-edit-lisp.patch"
  "ios-single-dispatch.patch"
)

for patch in "${patches[@]}"; do
  if [ -f "../patches/$patch" ]; then
    echo "=== Testing $patch ==="
    result=$(patch -p1 --dry-run < "../patches/$patch" 2>&1)
    if echo "$result" | grep -q "malformed\|FAILED\|can't find"; then
      echo "FAILED: $result" | tail -3
    else
      echo "OK"
    fi
  else
    echo "=== $patch NOT FOUND ==="
  fi
done
