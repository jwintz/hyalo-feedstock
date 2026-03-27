#!/bin/bash
set -euo pipefail

# Apply patches
patch -p1 < "${RECIPE_DIR}/../patches/system-appearance.patch"
patch -p1 < "${RECIPE_DIR}/../patches/frame-transparency.patch"
patch -p1 < "${RECIPE_DIR}/../patches/unidata-gen-incf.patch"
patch -p1 < "${RECIPE_DIR}/../patches/loaddefs-gen-fix.patch"
patch -p1 < "${RECIPE_DIR}/../patches/derived-fix.patch"

# Copy custom icon
cp "${RECIPE_DIR}/../icons/Emacs.icns" nextstep/Cocoa/Emacs.base/Contents/Resources/Emacs.icns

# Generate configure script
./autogen.sh

# Configure with NS (Cocoa) support and all features
./configure \
  --prefix="${PREFIX}" \
  --with-ns \
  --with-gnutls \
  --with-xml2 \
  --with-rsvg \
  --with-modules \
  --with-tree-sitter \
  --with-native-compilation=aot \
  --without-x \
  --without-dbus \
  CC=clang \
  OBJC=clang \
  CFLAGS="-O2 -g -I${PREFIX}/include" \
  LDFLAGS="-Wl,-rpath,${PREFIX}/lib -L${PREFIX}/lib" \
  PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
  RSVG_CFLAGS="-I${PREFIX}/include/librsvg-2.0 -I${PREFIX}/include/gdk-pixbuf-2.0 -I${PREFIX}/include/cairo -I${PREFIX}/include/glib-2.0 -I${PREFIX}/lib/glib-2.0/include" \
  RSVG_LIBS="-L${PREFIX}/lib -lrsvg-2 -lm -lgdk_pixbuf-2.0 -lcairo -lgio-2.0 -lgobject-2.0 -lglib-2.0"

# Build
make -j"${CPU_COUNT}"

# Install (creates nextstep/Emacs.app)
make install

# Relocate non-Mach-O files out of Contents/MacOS/ so that codesign
# does not reject them as unsigned subcomponents when rattler re-signs
# the main executable after prefix replacement.
APP=./nextstep/Emacs.app
mkdir -p "${APP}/Contents/Resources/libexec"
for f in "${APP}/Contents/MacOS/libexec/"*; do
  case "$(file -b "$f")" in
    Mach-O*) ;;  # leave Mach-O binaries in place
    *)
      name="$(basename "$f")"
      mv "$f" "${APP}/Contents/Resources/libexec/${name}"
      ln -s "../../Resources/libexec/${name}" "$f"
      ;;
  esac
done

# Sign the app bundle (ad-hoc; rattler-build re-signs after binary modification)
codesign --force --deep --sign - "${APP}"

# Copy Emacs.app to prefix
mkdir -p "${PREFIX}/Applications"
cp -R ./nextstep/Emacs.app "${PREFIX}/Applications/Emacs.app"

echo "Emacs.app installed to ${PREFIX}/Applications/"
