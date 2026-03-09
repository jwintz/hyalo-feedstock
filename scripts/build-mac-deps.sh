#!/bin/bash
# Build all static dependencies for macOS native (arm64) Hyalo build.
# Mirrors build-sim-deps.sh but targets macOS arm64 (no cross-compilation).
# Output: mac-deps/ (static .a files only)
# Tarballs are shared with build-sim/ cache to avoid re-downloading.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="${SCRIPT_DIR}/.."
PREFIX="${REPO_DIR}/mac-deps"
BUILD_DIR="${REPO_DIR}/build-mac"
CACHE_DIR="${REPO_DIR}/build-sim"   # share tarball cache with iOS sim build

NCURSES_VERSION="${NCURSES_VERSION:-6.4}"
LIBXML2_VERSION="${LIBXML2_VERSION:-2.12.4}"
JANSSON_VERSION="${JANSSON_VERSION:-2.14}"
SQLITE_VERSION="${SQLITE_VERSION:-3510200}"   # 3.51.2
SQLITE_YEAR="${SQLITE_YEAR:-2026}"
GMP_VERSION="${GMP_VERSION:-6.3.0}"
NETTLE_VERSION="${NETTLE_VERSION:-3.9.1}"
LIBTASN1_VERSION="${LIBTASN1_VERSION:-4.19.0}"
GNUTLS_VERSION="${GNUTLS_VERSION:-3.8.3}"
TREE_SITTER_VERSION="${TREE_SITTER_VERSION:-0.24.4}"

ARCH="arm64"
MACOS_MIN="${MACOS_MIN:-13.0}"
CC="clang"
CFLAGS="-arch ${ARCH} -mmacosx-version-min=${MACOS_MIN} -O2"
LDFLAGS="-arch ${ARCH} -mmacosx-version-min=${MACOS_MIN}"
CPPFLAGS="-I${PREFIX}/include"
JOBS=$(sysctl -n hw.ncpu)

export CC CFLAGS LDFLAGS CPPFLAGS

mkdir -p "${BUILD_DIR}" "${CACHE_DIR}" "${PREFIX}/lib" "${PREFIX}/include"

download() {
    local url="$1"
    local filename="$(basename "$url")"
    local dest="${CACHE_DIR}/${filename}"
    if [ ! -f "${dest}" ]; then
        echo "  Downloading ${filename}..." >&2
        curl -L --silent --show-error -o "${dest}" "${url}"
    else
        echo "  Cached: ${filename}" >&2
    fi
    echo "${dest}"
}

skip_if_built() {
    local lib="${PREFIX}/lib/${1}"
    if [ -f "${lib}" ] && [ "${FORCE:-0}" != "1" ]; then
        echo "  Already built: ${1} (pass FORCE=1 to rebuild)" >&2
        return 0
    fi
    return 1
}

# ============= ncurses =============
build_ncurses() {
    skip_if_built "libncurses.a" && return
    echo "=== Building ncurses ${NCURSES_VERSION} for macOS ==="
    TARBALL="$(download "https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz")"
    cd "${BUILD_DIR}" && rm -rf "ncurses-${NCURSES_VERSION}" && tar xf "${TARBALL}"
    cd "ncurses-${NCURSES_VERSION}"
    ./configure \
        --prefix="${PREFIX}" \
        --without-debug \
        --without-shared \
        --enable-widec \
        --disable-stripping \
        --without-cxx-binding \
        --without-ada \
        --without-manpages \
        --without-progs \
        --without-tests \
        CC="${CC}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}"
    make -j${JOBS} && make install
    cd "${PREFIX}/lib"
    for lib in ncurses form panel menu; do
        [ -f "lib${lib}w.a" ] && ln -sf "lib${lib}w.a" "lib${lib}.a"
    done
    cd "${PREFIX}/include" && [ -d ncursesw ] && ln -sf ncursesw/* .
    echo "  ncurses installed"
}

# ============= libxml2 =============
build_libxml2() {
    skip_if_built "libxml2.a" && return
    echo "=== Building libxml2 ${LIBXML2_VERSION} for macOS ==="
    TARBALL="$(download "https://download.gnome.org/sources/libxml2/2.12/libxml2-${LIBXML2_VERSION}.tar.xz")"
    cd "${BUILD_DIR}" && rm -rf "libxml2-${LIBXML2_VERSION}" && tar xf "${TARBALL}"
    cd "libxml2-${LIBXML2_VERSION}"
    ./configure \
        --prefix="${PREFIX}" \
        --disable-shared \
        --enable-static \
        --without-python \
        --without-lzma \
        --with-zlib=no \
        --with-iconv=no \
        CC="${CC}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}" CPPFLAGS="${CPPFLAGS}"
    make -j${JOBS} && make install
    echo "  libxml2 installed"
}

# ============= jansson =============
build_jansson() {
    skip_if_built "libjansson.a" && return
    echo "=== Building jansson ${JANSSON_VERSION} for macOS ==="
    TARBALL="$(download "https://github.com/akheron/jansson/releases/download/v${JANSSON_VERSION}/jansson-${JANSSON_VERSION}.tar.gz")"
    cd "${BUILD_DIR}" && rm -rf "jansson-${JANSSON_VERSION}" && tar xf "${TARBALL}"
    cd "jansson-${JANSSON_VERSION}"
    ./configure \
        --prefix="${PREFIX}" \
        --disable-shared \
        --enable-static \
        CC="${CC}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}"
    make -j${JOBS} && make install
    echo "  jansson installed"
}

# ============= sqlite3 (with load_extension) =============
build_sqlite3() {
    skip_if_built "libsqlite3.a" && return
    echo "=== Building sqlite3 ${SQLITE_VERSION} for macOS ==="
    TARBALL="$(download "https://www.sqlite.org/${SQLITE_YEAR}/sqlite-autoconf-${SQLITE_VERSION}.tar.gz")"
    cd "${BUILD_DIR}" && rm -rf "sqlite-autoconf-${SQLITE_VERSION}" && tar xf "${TARBALL}"
    cd "sqlite-autoconf-${SQLITE_VERSION}"
    ./configure \
        --prefix="${PREFIX}" \
        --disable-shared \
        --enable-static \
        CC="${CC}" \
        CFLAGS="${CFLAGS} -DSQLITE_ENABLE_LOAD_EXTENSION=1" \
        LDFLAGS="${LDFLAGS}"
    make -j${JOBS} && make install
    echo "  sqlite3 installed"
}

# ============= GMP =============
build_gmp() {
    skip_if_built "libgmp.a" && return
    echo "=== Building GMP ${GMP_VERSION} for macOS ==="
    TARBALL="$(download "https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.xz")"
    cd "${BUILD_DIR}" && rm -rf "gmp-${GMP_VERSION}" && tar xf "${TARBALL}"
    cd "gmp-${GMP_VERSION}"
    ./configure \
        --prefix="${PREFIX}" \
        --disable-shared \
        --enable-static \
        --disable-assembly \
        CC="${CC}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}"
    make -j${JOBS} && make install
    echo "  GMP installed"
}

# ============= Nettle =============
build_nettle() {
    skip_if_built "libnettle.a" && return
    echo "=== Building Nettle ${NETTLE_VERSION} for macOS ==="
    TARBALL="$(download "https://ftp.gnu.org/gnu/nettle/nettle-${NETTLE_VERSION}.tar.gz")"
    cd "${BUILD_DIR}" && rm -rf "nettle-${NETTLE_VERSION}" && tar xf "${TARBALL}"
    cd "nettle-${NETTLE_VERSION}"
    ./configure \
        --prefix="${PREFIX}" \
        --disable-shared \
        --enable-static \
        --disable-assembler \
        --disable-openssl \
        --disable-documentation \
        CC="${CC}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}" \
        CPPFLAGS="${CPPFLAGS}" \
        LIBS="-L${PREFIX}/lib -lgmp"
    make -j${JOBS} && make install
    echo "  Nettle installed"
}

# ============= libtasn1 =============
build_libtasn1() {
    skip_if_built "libtasn1.a" && return
    echo "=== Building libtasn1 ${LIBTASN1_VERSION} for macOS ==="
    TARBALL="$(download "https://ftp.gnu.org/gnu/libtasn1/libtasn1-${LIBTASN1_VERSION}.tar.gz")"
    cd "${BUILD_DIR}" && rm -rf "libtasn1-${LIBTASN1_VERSION}" && tar xf "${TARBALL}"
    cd "libtasn1-${LIBTASN1_VERSION}"
    ./configure \
        --prefix="${PREFIX}" \
        --disable-shared \
        --enable-static \
        --disable-doc \
        CC="${CC}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}"
    make -j${JOBS} && make install
    echo "  libtasn1 installed"
}

# ============= GnuTLS =============
build_gnutls() {
    skip_if_built "libgnutls.a" && return
    echo "=== Building GnuTLS ${GNUTLS_VERSION} for macOS ==="
    TARBALL="$(download "https://www.gnupg.org/ftp/gcrypt/gnutls/v3.8/gnutls-${GNUTLS_VERSION}.tar.xz")"
    cd "${BUILD_DIR}" && rm -rf "gnutls-${GNUTLS_VERSION}" && tar xf "${TARBALL}"
    cd "gnutls-${GNUTLS_VERSION}"
    ./configure \
        --prefix="${PREFIX}" \
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
        CC="${CC}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}" CPPFLAGS="${CPPFLAGS}" \
        PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig" \
        GMP_CFLAGS="-I${PREFIX}/include" \
        GMP_LIBS="-L${PREFIX}/lib -lgmp" \
        NETTLE_CFLAGS="-I${PREFIX}/include" \
        NETTLE_LIBS="-L${PREFIX}/lib -lnettle" \
        HOGWEED_CFLAGS="-I${PREFIX}/include" \
        HOGWEED_LIBS="-L${PREFIX}/lib -lhogweed -lnettle -lgmp" \
        LIBTASN1_CFLAGS="-I${PREFIX}/include" \
        LIBTASN1_LIBS="-L${PREFIX}/lib -ltasn1"
    make -j${JOBS} && make install
    echo "  GnuTLS installed"
}

# ============= tree-sitter =============
build_tree_sitter() {
    skip_if_built "libtree-sitter.a" && return
    echo "=== Building tree-sitter ${TREE_SITTER_VERSION} for macOS ==="
    TARBALL="$(download "https://github.com/tree-sitter/tree-sitter/archive/refs/tags/v${TREE_SITTER_VERSION}.tar.gz" 2>/dev/null || download "https://github.com/tree-sitter/tree-sitter/archive/v${TREE_SITTER_VERSION}.tar.gz")"
    cd "${BUILD_DIR}" && rm -rf "tree-sitter-${TREE_SITTER_VERSION}" && tar xf "${TARBALL}"
    cd "tree-sitter-${TREE_SITTER_VERSION}"
    make \
        CC="${CC}" \
        CFLAGS="${CFLAGS}" \
        PREFIX="${PREFIX}" \
        -j${JOBS}
    # Install manually (no install target in older versions)
    cp libtree-sitter.a "${PREFIX}/lib/" 2>/dev/null || \
        (mkdir -p build && \
         ${CC} ${CFLAGS} -c lib/src/lib.c -I lib/include -o build/lib.o && \
         ar rcs "${PREFIX}/lib/libtree-sitter.a" build/lib.o)
    mkdir -p "${PREFIX}/include/tree_sitter"
    cp lib/include/tree_sitter/*.h "${PREFIX}/include/tree_sitter/"
    echo "  tree-sitter installed"
}

echo "======================================"
echo "Building macOS static dependencies"
echo "Prefix: ${PREFIX}"
echo "======================================"
echo ""

build_ncurses
build_libxml2
build_jansson
build_sqlite3
build_gmp
build_nettle
build_libtasn1
build_gnutls
build_tree_sitter

echo ""
echo "======================================"
echo "All macOS static dependencies built!"
echo "======================================"
echo ""
echo "Verification:"
for lib in libncurses.a libxml2.a libjansson.a libsqlite3.a libgmp.a libnettle.a libtasn1.a libgnutls.a libtree-sitter.a; do
    if [ -f "${PREFIX}/lib/${lib}" ]; then
        size=$(du -sh "${PREFIX}/lib/${lib}" | cut -f1)
        echo "  OK  ${lib} (${size})"
    else
        echo "  MISSING  ${lib}"
    fi
done
