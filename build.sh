#!/bin/sh

# Unbound build with HTTP/2 and QUIC
# Target:
#   Comfast CF-WR632AX
#   OpenWrt 25.12.5
#   MediaTek Filogic
#   AArch64 / musl
#
# Components:
#   OpenSSL 3.5.7
#   nghttp2 1.70.0
#   nghttp3 1.11.0
#   ngtcp2 1.15.0
#   expat 2.8.2
#   Unbound 1.25.2
#
# Result:
#   Fully statically linked Unbound executable
#   HTTP/2 support
#   DNS-over-QUIC support
#
# OpenSSL 3.5 provides the QUIC TLS API used by ngtcp2.

set -e

###############################################################################
# Prerequisites
###############################################################################

apt update
apt install -y  build-essential wget pkg-config zstd

###############################################################################
# Configuration
###############################################################################

BUILD="/workspace/openwrt-build"
STATIC="/workspace/openwrt-static"

SDK_NAME="openwrt-sdk-25.12.5-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64"
SDK="$BUILD/$SDK_NAME"

export STAGING_DIR="$SDK/staging_dir"
export TOOLCHAIN="$STAGING_DIR/toolchain-aarch64_cortex-a53_gcc-14.3.0_musl"
export TARGET="$TOOLCHAIN/bin/aarch64-openwrt-linux-musl"

export OPENSSL_PREFIX="$STATIC"

export PKG_CONFIG_PATH="$STATIC/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$STATIC/lib/pkgconfig"
unset PKG_CONFIG_SYSROOT_DIR

###############################################################################
# Cross compiler
###############################################################################

export CC="$TARGET-gcc"
export CXX="$TARGET-g++"
export AR="$TARGET-ar"
export RANLIB="$TARGET-ranlib"
export STRIP="$TARGET-strip"

export PATH="$TOOLCHAIN/bin:$PATH"

###############################################################################
# Versions
###############################################################################

OPENSSL_VERSION="3.5.7"
NGHTTP2_VERSION="1.70.0"
NGHTTP3_VERSION="1.11.0"
NGTCP2_VERSION="1.15.0"
EXPAT_VERSION="2.8.2"
UNBOUND_VERSION="1.25.2"

###############################################################################
# Prepare build directory
###############################################################################

mkdir -p "$BUILD"
cd "$BUILD"

###############################################################################
# Verify SDK / toolchain
###############################################################################

echo
echo "============================================================"
echo " OpenWrt SDK"
echo "============================================================"

if [ ! -d "$SDK" ]; then

    if [ ! -f "$SDK_NAME.tar.zst" ]; then
        wget \
            "https://downloads.openwrt.org/releases/25.12.5/targets/mediatek/filogic/$SDK_NAME.tar.zst"
    fi

    tar --use-compress-program=unzstd \
        -xf "$SDK_NAME.tar.zst"
fi

test -x "$CC"
test -x "$CXX"
test -x "$AR"
test -x "$RANLIB"

echo
echo "Compiler:"
"$CC" --version | head -1

echo
echo "Target:"
"$CC" -dumpmachine

echo
echo "Sysroot:"
"$CC" -print-sysroot

echo
echo "libc:"
"$CC" -print-file-name=libc.a

###############################################################################
# Clean static prefix
###############################################################################

rm -rf "$STATIC"
mkdir -p "$STATIC"

###############################################################################
# OpenSSL 3.5.7
###############################################################################

echo
echo "============================================================"
echo " OpenSSL $OPENSSL_VERSION"
echo "============================================================"

cd "$BUILD"

if [ ! -f "openssl-$OPENSSL_VERSION.tar.gz" ]; then
    wget \
        "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz"
fi

rm -rf "openssl-$OPENSSL_VERSION"

tar xf "openssl-$OPENSSL_VERSION.tar.gz"

cd "openssl-$OPENSSL_VERSION"

###############################################################################
# IMPORTANT:
#
# OpenSSL's CROSS_COMPILE variable is a PREFIX only.
#
# Correct:
#
#   CROSS_COMPILE=aarch64-openwrt-linux-musl-
#
# Incorrect:
#
#   CROSS_COMPILE=aarch64-openwrt-linux-musl-/some/path
###############################################################################

unset CC CXX AR AS LD RANLIB RC STRIP CROSS_COMPILE

export PATH="$TOOLCHAIN/bin:$PATH"

export CROSS_COMPILE="aarch64-openwrt-linux-musl-"

echo
echo "OpenSSL compiler:"
command -v "${CROSS_COMPILE}gcc"

"${CROSS_COMPILE}gcc" --version | head -1

rm -rf "$OPENSSL_PREFIX"
mkdir -p "$OPENSSL_PREFIX"

make distclean 2>/dev/null || true

./Configure linux-aarch64 \
    --cross-compile-prefix="$CROSS_COMPILE" \
    --prefix="$OPENSSL_PREFIX" \
    --openssldir=/etc/ssl \
    no-shared \
    no-tests

echo
echo "OpenSSL configuration:"
grep -E '^(CROSS_COMPILE|CC|CXX|AR|RANLIB)=' Makefile || true

make -j"$(nproc)"

make install_sw

echo
echo "OpenSSL libraries:"

ls -lh \
    "$OPENSSL_PREFIX/lib/libssl.a" \
    "$OPENSSL_PREFIX/lib/libcrypto.a"

echo
echo "OpenSSL QUIC API:"
grep -R "SSL_set_quic" \
    "$OPENSSL_PREFIX/include/openssl" || true

###############################################################################
# Restore normal cross compiler variables for Autoconf projects
###############################################################################

export CC="$TARGET-gcc"
export CXX="$TARGET-g++"
export AR="$TARGET-ar"
export RANLIB="$TARGET-ranlib"
export STRIP="$TARGET-strip"

###############################################################################
# nghttp2 1.70.0
###############################################################################

echo
echo "============================================================"
echo " nghttp2 $NGHTTP2_VERSION"
echo "============================================================"

cd "$BUILD"

if [ ! -f "nghttp2-$NGHTTP2_VERSION.tar.gz" ]; then
    wget \
        "https://github.com/nghttp2/nghttp2/releases/download/v$NGHTTP2_VERSION/nghttp2-$NGHTTP2_VERSION.tar.gz"
fi

rm -rf "nghttp2-$NGHTTP2_VERSION"

tar xf "nghttp2-$NGHTTP2_VERSION.tar.gz"

cd "nghttp2-$NGHTTP2_VERSION"

./configure \
    --host=aarch64-openwrt-linux-musl \
    --prefix="$OPENSSL_PREFIX" \
    --disable-shared \
    --enable-static \
    --disable-python-bindings \
    --disable-app \
    --disable-examples \
    --without-libxml2 \
    --without-jemalloc \
    CC="$CC" \
    CXX="$CXX" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    CFLAGS="-O2 -I$OPENSSL_PREFIX/include" \
    CXXFLAGS="-O2 -std=c++23 -I$OPENSSL_PREFIX/include" \
    LDFLAGS="-L$OPENSSL_PREFIX/lib"

make -j"$(nproc)"

make install

echo
echo "nghttp2:"
ls -lh "$OPENSSL_PREFIX/lib/libnghttp2.a"

###############################################################################
# nghttp3 1.11.0
###############################################################################

echo
echo "============================================================"
echo " nghttp3 $NGHTTP3_VERSION"
echo "============================================================"

cd "$BUILD"

if [ ! -f "nghttp3-$NGHTTP3_VERSION.tar.gz" ]; then
    wget \
        "https://github.com/ngtcp2/nghttp3/releases/download/v$NGHTTP3_VERSION/nghttp3-$NGHTTP3_VERSION.tar.gz"
fi

rm -rf "nghttp3-$NGHTTP3_VERSION"

tar xf "nghttp3-$NGHTTP3_VERSION.tar.gz"

cd "nghttp3-$NGHTTP3_VERSION"

./configure \
    --host=aarch64-openwrt-linux-musl \
    --prefix="$OPENSSL_PREFIX" \
    --disable-shared \
    --enable-static \
    CC="$CC" \
    CXX="$CXX" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    CFLAGS="-O2 -I$OPENSSL_PREFIX/include" \
    CXXFLAGS="-O2 -std=c++23 -I$OPENSSL_PREFIX/include" \
    LDFLAGS="-L$OPENSSL_PREFIX/lib"

make -j"$(nproc)"

make install

echo
echo "nghttp3:"
ls -lh "$OPENSSL_PREFIX/lib/libnghttp3.a"

###############################################################################
# ngtcp2 1.15.0
###############################################################################

echo
echo "============================================================"
echo " ngtcp2 $NGTCP2_VERSION"
echo "============================================================"

cd "$BUILD"

if [ ! -f "ngtcp2-$NGTCP2_VERSION.tar.gz" ]; then
    wget \
        "https://github.com/ngtcp2/ngtcp2/releases/download/v$NGTCP2_VERSION/ngtcp2-$NGTCP2_VERSION.tar.gz"
fi

rm -rf "ngtcp2-$NGTCP2_VERSION"

tar xf "ngtcp2-$NGTCP2_VERSION.tar.gz"

cd "ngtcp2-$NGTCP2_VERSION"

test -f "$OPENSSL_PREFIX/include/openssl/ssl.h"
test -f "$OPENSSL_PREFIX/lib/libssl.a"
test -f "$OPENSSL_PREFIX/lib/libcrypto.a"
test -f "$OPENSSL_PREFIX/lib/libnghttp3.a"

./configure \
    --host=aarch64-openwrt-linux-musl \
    --prefix="$OPENSSL_PREFIX" \
    --disable-shared \
    --enable-static \
    --with-openssl \
    CC="$CC" \
    CXX="$CXX" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    CFLAGS="-O2 -I$OPENSSL_PREFIX/include" \
    CXXFLAGS="-O2 -std=c++23 -I$OPENSSL_PREFIX/include" \
    LDFLAGS="-L$OPENSSL_PREFIX/lib"

make -j"$(nproc)"

make install

echo
echo "ngtcp2 libraries:"

ls -lh "$OPENSSL_PREFIX/lib/"*ngtcp2*.a

echo
echo "ngtcp2 OpenSSL crypto symbols:"

nm -g "$OPENSSL_PREFIX/lib/libngtcp2_crypto_ossl.a" |
    grep -E \
    'ngtcp2_crypto_(get_path_challenge_data_cb|generate_regular_token|version_negotiation_cb|recv_client_initial_cb)' \
    || true

###############################################################################
# expat 2.8.2
###############################################################################

echo
echo "============================================================"
echo " expat $EXPAT_VERSION"
echo "============================================================"

cd "$BUILD"

if [ ! -f "expat-$EXPAT_VERSION.tar.gz" ]; then
    wget \
        "https://github.com/libexpat/libexpat/releases/download/R_2_8_2/expat-$EXPAT_VERSION.tar.gz"
fi

rm -rf "expat-$EXPAT_VERSION"

tar xf "expat-$EXPAT_VERSION.tar.gz"

cd "expat-$EXPAT_VERSION"

./configure \
    --host=aarch64-openwrt-linux-musl \
    --prefix="$OPENSSL_PREFIX" \
    --disable-shared \
    --enable-static \
    --without-xmlwf \
    CC="$CC" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    CFLAGS="-O2 -I$OPENSSL_PREFIX/include" \
    LDFLAGS="-L$OPENSSL_PREFIX/lib"

make -j"$(nproc)"

make install

echo
echo "expat:"
ls -lh "$OPENSSL_PREFIX/lib/libexpat.a"

###############################################################################
# Verify static libraries
###############################################################################

echo
echo "============================================================"
echo " Static libraries"
echo "============================================================"

ls -lh \
    "$OPENSSL_PREFIX/lib/libssl.a" \
    "$OPENSSL_PREFIX/lib/libcrypto.a" \
    "$OPENSSL_PREFIX/lib/libnghttp2.a" \
    "$OPENSSL_PREFIX/lib/libnghttp3.a" \
    "$OPENSSL_PREFIX/lib/libngtcp2.a" \
    "$OPENSSL_PREFIX/lib/libngtcp2_crypto_ossl.a" \
    "$OPENSSL_PREFIX/lib/libexpat.a"

###############################################################################
# pkg-config
###############################################################################

echo
echo "============================================================"
echo " pkg-config"
echo "============================================================"

export PKG_CONFIG_PATH="$OPENSSL_PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$OPENSSL_PREFIX/lib/pkgconfig"
unset PKG_CONFIG_SYSROOT_DIR

echo
echo "OpenSSL:"
pkg-config --modversion openssl
pkg-config --libs openssl

echo
echo "nghttp2:"
pkg-config --modversion libnghttp2
pkg-config --libs libnghttp2

echo
echo "nghttp3:"
pkg-config --modversion libnghttp3
pkg-config --libs libnghttp3

echo
echo "ngtcp2:"
pkg-config --modversion libngtcp2
pkg-config --libs libngtcp2

echo
echo "ngtcp2 OpenSSL:"
pkg-config --libs libngtcp2_crypto_ossl

###############################################################################
# Unbound 1.25.2
###############################################################################

echo
echo "============================================================"
echo " Unbound $UNBOUND_VERSION"
echo "============================================================"

cd "$BUILD"

if [ ! -f "unbound-$UNBOUND_VERSION.tar.gz" ]; then
    wget \
        "https://nlnetlabs.nl/downloads/unbound/unbound-$UNBOUND_VERSION.tar.gz"
fi

rm -rf "unbound-$UNBOUND_VERSION"

tar xf "unbound-$UNBOUND_VERSION.tar.gz"

cd "unbound-$UNBOUND_VERSION"

###############################################################################
# Configure Unbound
###############################################################################

./configure \
    --host=aarch64-openwrt-linux-musl \
    --prefix=/usr \
    --with-conf-file=/etc/unbound/unbound.conf \
    --with-run-dir=/etc/unbound \
    --with-pidfile=/etc/unbound/unbound.pid \
    --with-ssl="$OPENSSL_PREFIX" \
    --with-libexpat="$OPENSSL_PREFIX" \
    --with-libnghttp2="$OPENSSL_PREFIX" \
    --with-libngtcp2="$OPENSSL_PREFIX" \
    --disable-sha1 \
    --disable-rpath \
    --disable-flto \
    --disable-dsa \
    --enable-static \
    --disable-shared \
    CC="$CC" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    CFLAGS="-O2 -I$OPENSSL_PREFIX/include" \
    LDFLAGS="-static -static-libgcc -L$OPENSSL_PREFIX/lib" \
    LIBS="-lngtcp2_crypto_ossl -lngtcp2 -lnghttp3 -lnghttp2 -lssl -lcrypto -lexpat -lpthread"

###############################################################################
# Verify Unbound configuration
###############################################################################

echo
echo "============================================================"
echo " Unbound configuration"
echo "============================================================"

grep -E \
    '^(Configure line:|Linked libs:|Linked modules:)' \
    config.log || true

echo
echo "Makefile libraries:"
grep -nE '^(SSLLIB|LIBS|LDFLAGS)=' Makefile || true

###############################################################################
# OpenSSL 3.5 compatibility
#
# Unbound 1.25.2 contains:
#
#     SSL_set_quic_early_data_enabled(ssl, 1);
#
# OpenSSL 3.5 does not provide that old API.
#
# Unbound already uses:
#
#     SSL_set_quic_tls_early_data_enabled(ssl, 1);
#
# Remove ONLY the obsolete call.
#
# Do NOT remove the surrounding #ifdef/#else/#endif.
###############################################################################

if grep -q \
    'SSL_set_quic_early_data_enabled(ssl, 1);' \
    services/listen_dnsport.c; then

    echo
    echo "Removing obsolete OpenSSL QUIC early-data API..."

    sed -i \
        '/^[[:space:]]*SSL_set_quic_early_data_enabled(ssl, 1);[[:space:]]*$/d' \
        services/listen_dnsport.c
fi

###############################################################################
# Verify compatibility fix
###############################################################################

echo
echo "============================================================"
echo " QUIC early-data calls"
echo "============================================================"

grep -n -E \
    'SSL_set_quic.*early_data' \
    services/listen_dnsport.c || true

###############################################################################
# Verify obsolete API is gone
###############################################################################

if grep -R -q \
    'SSL_set_quic_early_data_enabled' \
    services daemon testcode 2>/dev/null; then

    echo
    echo "WARNING: obsolete SSL_set_quic_early_data_enabled remains:"
    grep -R -n \
        'SSL_set_quic_early_data_enabled' \
        services daemon testcode 2>/dev/null || true
fi

###############################################################################
# Build Unbound
#
# Unbound's Makefile uses $(staticexe) in its LINK rule.
#
# Passing:
#
#     staticexe=--static
#
# forces libtool to perform the executable link statically.
###############################################################################

echo
echo "============================================================"
echo " Building Unbound"
echo "============================================================"

make clean

make -j"$(nproc)" staticexe="--static"

###############################################################################
# Verify binary
###############################################################################

echo
echo "============================================================"
echo " Binary verification"
echo "============================================================"

readelf -h unbound

###############################################################################
# Check ELF interpreter
###############################################################################

echo
echo "=== ELF interpreter ==="

if readelf -l unbound | grep -q INTERP; then

    echo "ERROR: dynamic ELF interpreter found:"
    readelf -l unbound | grep INTERP

    exit 1

else

    echo "OK: no ELF INTERP"

fi

###############################################################################
# Check DT_NEEDED
###############################################################################

echo
echo "=== Dynamic dependencies ==="

if readelf -d unbound | grep -q NEEDED; then

    echo "ERROR: dynamic dependencies found:"
    readelf -d unbound | grep NEEDED

    exit 1

else

    echo "OK: no DT_NEEDED entries"

fi

###############################################################################
# Check unresolved QUIC / HTTP symbols
###############################################################################

echo
echo "=== Undefined QUIC / HTTP symbols ==="

if nm -u unbound |
    grep -E 'ngtcp2|nghttp3|nghttp2'; then

    echo
    echo "ERROR: unresolved QUIC/HTTP symbols found"

    exit 1

else

    echo "OK: no unresolved ngtcp2/nghttp3/nghttp2 symbols"

fi

###############################################################################
# Check libc / startup objects
###############################################################################

echo
echo "============================================================"
echo " Cross compiler static objects"
echo "============================================================"

echo
echo "libc:"
"$TARGET-gcc" -print-file-name=libc.a

echo
echo "crt1:"
"$TARGET-gcc" -print-file-name=crt1.o

echo
echo "crti:"
"$TARGET-gcc" -print-file-name=crti.o

echo
echo "crtn:"
"$TARGET-gcc" -print-file-name=crtn.o

###############################################################################
# Final binary
###############################################################################

FINAL="$BUILD/unbound-$UNBOUND_VERSION-aarch64-static"

cp unbound "$FINAL"

mkdir -p /output
cp "$FINAL" "/output/unbound-$UNBOUND_VERSION-aarch64-static"

###############################################################################
# Final report
###############################################################################

echo
echo "============================================================"
echo " BUILD COMPLETE"
echo "============================================================"

echo
echo "Binary:"
echo "  $FINAL"

echo
echo "Architecture:"
readelf -h "$FINAL"

echo
echo "Dynamic dependencies:"
readelf -d "$FINAL" | grep NEEDED || echo "  NONE"

echo
echo "ELF interpreter:"
readelf -l "$FINAL" | grep INTERP || echo "  NONE"

echo
echo "QUIC / HTTP symbols:"
nm "$FINAL" |
    grep -E 'ngtcp2|nghttp3|nghttp2' |
    head -20 || true

echo
echo "Size:"
ls -lh "$FINAL"

echo
echo "============================================================"
echo " Static build successful"
echo "============================================================"


