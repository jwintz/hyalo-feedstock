#!/bin/bash
# Build essential libraries for iOS Device (arm64)
# Minimal set needed for Emacs: libxml2, jansson, gnutls chain

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/ios-env.sh"

BUILD_DIR="${SCRIPT_DIR}/../build-device"
mkdir -p "${BUILD_DIR}"

# Library versions (same as simulator)
LIBXML2_VERSION="${LIBXML2_VERSION:-2.12.4}"
JANSSON_VERSION="${JANSSON_VERSION:-2.14}"
GMP_VERSION="${GMP_VERSION:-6.3.0}"
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

# ============= libxml2 =============
build_libxml2() {
    echo "=== Building libxml2 ${LIBXML2_VERSION} for iOS Device ==="
    cd "${BUILD_DIR}"
    download "https://download.gnome.org/sources/libxml2/2.12/libxml2-${LIBXML2_VERSION}.tar.xz" \
             "libxml2-${LIBXML2_VERSION}.tar.xz"
    rm -rf "libxml2-${LIBXML2_VERSION}"
    tar xf "libxml2-${LIBXML2_VERSION}.tar.xz"
    cd "libxml2-${LIBXML2_VERSION}"

    ./configure \
        --host=arm-apple-darwin \
        --prefix="${IOS_PREFIX}" \
        --disable-shared \
        --enable-static \
        --without-python \
        --without-lzma \
        --with-zlib=no \
        --with-iconv=no \
        CC="${CC}" \
        CFLAGS="${CFLAGS}" \
        LDFLAGS="${LDFLAGS}" \
        CPPFLAGS="${CPPFLAGS}"

    make -j$(sysctl -n hw.ncpu)
    make install
    echo "libxml2 installed"
}

# ============= jansson =============
build_jansson() {
    echo "=== Building jansson ${JANSSON_VERSION} for iOS Device ==="
    cd "${BUILD_DIR}"
    download "https://github.com/akheron/jansson/releases/download/v${JANSSON_VERSION}/jansson-${JANSSON_VERSION}.tar.gz" \
             "jansson-${JANSSON_VERSION}.tar.gz"
    rm -rf "jansson-${JANSSON_VERSION}"
    tar xf "jansson-${JANSSON_VERSION}.tar.gz"
    cd "jansson-${JANSSON_VERSION}"

    ./configure \
        --host=arm-apple-darwin \
        --prefix="${IOS_PREFIX}" \
        --disable-shared \
        --enable-static \
        CC="${CC}" \
        CFLAGS="${CFLAGS}" \
        LDFLAGS="${LDFLAGS}"

    make -j$(sysctl -n hw.ncpu)
    make install
    echo "jansson installed"
}

# ============= GMP (for GnuTLS) =============
build_gmp() {
    echo "=== Building GMP ${GMP_VERSION} for iOS Device ==="
    cd "${BUILD_DIR}"
    download "https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.xz" \
             "gmp-${GMP_VERSION}.tar.xz"
    rm -rf "gmp-${GMP_VERSION}"
    tar xf "gmp-${GMP_VERSION}.tar.xz"
    cd "gmp-${GMP_VERSION}"

    ./configure \
        --host=arm-apple-darwin \
        --prefix="${IOS_PREFIX}" \
        --disable-shared \
        --enable-static \
        --disable-assembly \
        CC="${CC}" \
        CFLAGS="${CFLAGS}" \
        LDFLAGS="${LDFLAGS}"

    make -j$(sysctl -n hw.ncpu)
    make install
    echo "GMP installed"
}

# ============= Nettle (for GnuTLS) =============
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
        CFLAGS="${CFLAGS}" \
        LDFLAGS="${LDFLAGS}" \
        CPPFLAGS="${CPPFLAGS} -I${IOS_PREFIX}/include" \
        LIBS="-L${IOS_PREFIX}/lib -lgmp"

    make -j$(sysctl -n hw.ncpu)
    make install
    echo "Nettle installed"
}

# ============= libtasn1 (for GnuTLS) =============
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
        CFLAGS="${CFLAGS}" \
        LDFLAGS="${LDFLAGS}"

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
        CFLAGS="${CFLAGS}" \
        LDFLAGS="${LDFLAGS}" \
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

# Build in order (dependencies first)
echo "======================================"
echo "Building iOS Device dependencies"
echo "======================================"

build_libxml2
build_jansson
build_gmp
build_nettle
build_libtasn1
build_gnutls

echo "======================================"
echo "All iOS Device dependencies built!"
echo "Libraries installed to: ${IOS_PREFIX}"
echo "======================================"

# Verify key libraries
echo ""
echo "Verification:"
for lib in libxml2.a libjansson.a libgmp.a libnettle.a libtasn1.a libgnutls.a; do
    if [ -f "${IOS_PREFIX}/lib/${lib}" ]; then
        echo "  OK ${lib}"
    else
        echo "  MISSING ${lib}"
    fi
done
