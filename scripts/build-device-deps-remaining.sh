#!/bin/bash
# Build remaining iOS Device dependencies: nettle, libtasn1, gnutls
# libxml2, jansson, gmp are already in ios-deps/lib/

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/ios-env.sh"

BUILD_DIR="${SCRIPT_DIR}/../build-device"
mkdir -p "${BUILD_DIR}"

NETTLE_VERSION="${NETTLE_VERSION:-3.9.1}"
LIBTASN1_VERSION="${LIBTASN1_VERSION:-4.19.0}"
GNUTLS_VERSION="${GNUTLS_VERSION:-3.8.3}"

# Helper to download if not exists
download() {
    local url="$1"
    local file="$2"
    if [ ! -f "$file" ]; then
        echo "Downloading $file..."
        curl -L -o "$file" "$url"
    fi
}

# ============= Nettle =============
build_nettle() {
    echo "=== Building Nettle ${NETTLE_VERSION} for iOS Device ==="
    cd "${BUILD_DIR}"
    download "https://ftp.gnu.org/gnu/nettle/nettle-${NETTLE_VERSION}.tar.gz" \
             "nettle-${NETTLE_VERSION}.tar.gz"

    rm -rf "nettle-${NETTLE_VERSION}"
    tar xf "nettle-${NETTLE_VERSION}.tar.gz"
    cd "nettle-${NETTLE_VERSION}"

    ./configure \
        --host=arm-apple-darwin \
        --prefix="${IOS_PREFIX}" \
        --disable-shared \
        --enable-static \
        --disable-assembler \
        --disable-openssl \
        --disable-documentation \
        CC="${CC}" \
        CC_FOR_BUILD="/usr/bin/clang" \
        CFLAGS="${CFLAGS}" \
        CFLAGS_FOR_BUILD="-O2" \
        LDFLAGS="${LDFLAGS}" \
        LDFLAGS_FOR_BUILD="" \
        CPPFLAGS="${CPPFLAGS} -I${IOS_PREFIX}/include" \
        LIBS="-L${IOS_PREFIX}/lib -lgmp"

    make -j$(sysctl -n hw.ncpu)
    make install
    echo "Nettle installed"
}

# ============= libtasn1 =============
build_libtasn1() {
    echo "=== Building libtasn1 ${LIBTASN1_VERSION} for iOS Device ==="
    cd "${BUILD_DIR}"
    download "https://ftp.gnu.org/gnu/libtasn1/libtasn1-${LIBTASN1_VERSION}.tar.gz" \
             "libtasn1-${LIBTASN1_VERSION}.tar.gz"

    rm -rf "libtasn1-${LIBTASN1_VERSION}"
    tar xf "libtasn1-${LIBTASN1_VERSION}.tar.gz"
    cd "libtasn1-${LIBTASN1_VERSION}"

    ./configure \
        --host=arm-apple-darwin \
        --prefix="${IOS_PREFIX}" \
        --disable-shared \
        --enable-static \
        --disable-doc \
        CC="${CC}" \
        CC_FOR_BUILD="/usr/bin/clang" \
        CFLAGS="${CFLAGS}" \
        CFLAGS_FOR_BUILD="-O2" \
        LDFLAGS="${LDFLAGS}" \
        LDFLAGS_FOR_BUILD=""

    make -j$(sysctl -n hw.ncpu)
    make install
    echo "libtasn1 installed"
}

# ============= GnuTLS =============
build_gnutls() {
    echo "=== Building GnuTLS ${GNUTLS_VERSION} for iOS Device ==="
    cd "${BUILD_DIR}"
    download "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-${GNUTLS_VERSION}.tar.xz" \
             "gnutls-${GNUTLS_VERSION}.tar.xz"

    rm -rf "gnutls-${GNUTLS_VERSION}"
    tar xf "gnutls-${GNUTLS_VERSION}.tar.xz"
    cd "gnutls-${GNUTLS_VERSION}"

    ./configure \
        --host=arm-apple-darwin \
        --prefix="${IOS_PREFIX}" \
        --disable-shared \
        --enable-static \
        --disable-doc \
        --disable-tools \
        --disable-tests \
        --disable-nls \
        --disable-cxx \
        --disable-hardware-acceleration \
        --with-included-unistring \
        --without-p11-kit \
        --without-idn \
        --without-zlib \
        --without-brotli \
        --without-zstd \
        CC="${CC}" \
        CC_FOR_BUILD="/usr/bin/clang" \
        CFLAGS="${CFLAGS}" \
        CFLAGS_FOR_BUILD="-O2" \
        LDFLAGS="${LDFLAGS}" \
        LDFLAGS_FOR_BUILD="" \
        CPPFLAGS="${CPPFLAGS}" \
        PKG_CONFIG_PATH="${IOS_PREFIX}/lib/pkgconfig" \
        GMP_CFLAGS="-I${IOS_PREFIX}/include" \
        GMP_LIBS="-L${IOS_PREFIX}/lib -lgmp" \
        NETTLE_CFLAGS="-I${IOS_PREFIX}/include" \
        NETTLE_LIBS="-L${IOS_PREFIX}/lib -lnettle" \
        HOGWEED_CFLAGS="-I${IOS_PREFIX}/include" \
        HOGWEED_LIBS="-L${IOS_PREFIX}/lib -lhogweed -lnettle -lgmp" \
        LIBTASN1_CFLAGS="-I${IOS_PREFIX}/include" \
        LIBTASN1_LIBS="-L${IOS_PREFIX}/lib -ltasn1"

    make -j$(sysctl -n hw.ncpu)
    make install
    echo "GnuTLS installed"
}

echo "======================================"
echo "Building remaining iOS Device deps"
echo "======================================"

build_nettle
build_libtasn1
build_gnutls

echo "======================================"
echo "Remaining iOS Device deps complete!"
echo "======================================"

echo ""
echo "Verification:"
for lib in libnettle.a libhogweed.a libtasn1.a libgnutls.a; do
    if [ -f "${IOS_PREFIX}/lib/${lib}" ]; then
        echo "  OK ${lib}"
    else
        echo "  MISSING ${lib}"
    fi
done
