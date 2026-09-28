#!/bin/bash
# Hermetic, user-space toolchain bootstrap. No sudo, no system changes.
#
# Installs version-pinned Zig, LLVM (clang/LLD/llvm-mca/llvm-bolt/libFuzzer)
# and optionally ISPC into $TOOLCHAIN_ROOT. Idempotent and checksum-verified.
#
# usage: scripts/bootstrap_toolchain.sh [llvm|zig|ispc|all]
#   TOOLCHAIN_ROOT  install dir (default: ${XDG_DATA_HOME:-$HOME/.local/share}/stb-image-opt/toolchain)
#   NO_CHECKSUM=1   skip sha256 verification (NOT recommended)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TOOLCHAIN_ROOT=${TOOLCHAIN_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/stb-image-opt/toolchain}
DL="$TOOLCHAIN_ROOT/downloads"
mkdir -p "$DL"

ZIG_VER=0.16.0
ZIG_URL="https://ziglang.org/download/$ZIG_VER/zig-x86_64-linux-$ZIG_VER.tar.xz"
ZIG_SHA=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00

LLVM_VER=23.1.2
LLVM_TAG="llvmorg-$LLVM_VER"
LLVM_URL="https://github.com/llvm/llvm-project/releases/download/$LLVM_TAG/LLVM-$LLVM_VER-Linux-X64.tar.zst"
LLVM_SHA=6382de1c1a210ce5a5cc49d18bc8444d137742e7cbf9b19f4ae602bb1ab52534

ISPC_VER=1.31.0
ISPC_URL="https://github.com/ispc/ispc/releases/download/v$ISPC_VER/ispc-v$ISPC_VER-linux.tar.gz"
ISPC_SHA=d74089c835e10fd7e2c4b9225ced38b87d1fb53d35c7ceabd48cdf035da11b11

# ld.lld from the LLVM tarball links against ICU 70 (see install_lld_icu).
ICU_URL="http://archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu70_70.1-2_amd64.deb"
ICU_SHA=58a154f6307289813da2276f900498ef536ae7c0522d2cf31a3c3c5cf62dfd9a

log() { printf '[bootstrap] %s\n' "$*" >&2; }

fetch() { # fetch <url> <dest>
    local url=$1 dest=$2
    if [ -s "$dest" ]; then
        log "cached: $(basename "$dest")"
    else
        log "download: $url"
        curl -fL --retry 3 --retry-delay 2 -o "$dest.part" "$url"
        mv "$dest.part" "$dest"
    fi
}

verify() { # verify <file> <sha256>
    [ "${NO_CHECKSUM:-0}" = "1" ] && { log "checksum skipped (NO_CHECKSUM=1)"; return 0; }
    local got
    got=$(sha256sum "$1" | cut -d' ' -f1)
    if [ "$got" != "$2" ]; then
        log "CHECKSUM MISMATCH for $1"
        log "  expected $2"
        log "  got      $got"
        return 1
    fi
    log "checksum ok: $(basename "$1")"
}

install_zig() {
    local dst="$TOOLCHAIN_ROOT/zig-$ZIG_VER"
    if [ -x "$dst/zig" ]; then log "zig $ZIG_VER already installed"; return; fi
    fetch "$ZIG_URL" "$DL/zig-$ZIG_VER.tar.xz"
    verify "$DL/zig-$ZIG_VER.tar.xz" "$ZIG_SHA"
    rm -rf "$dst"
    mkdir -p "$dst"
    tar -xJf "$DL/zig-$ZIG_VER.tar.xz" -C "$dst" --strip-components=1
    log "installed: $("$dst/zig" version) -> $dst"
}

install_llvm() {
    local dst="$TOOLCHAIN_ROOT/llvm-$LLVM_VER"
    if [ -x "$dst/bin/clang" ]; then log "llvm $LLVM_VER already installed"; else
        fetch "$LLVM_URL" "$DL/LLVM-$LLVM_VER-Linux-X64.tar.zst"
        verify "$DL/LLVM-$LLVM_VER-Linux-X64.tar.zst" "$LLVM_SHA"
        mkdir -p "$dst"
        log "extracting LLVM (this takes a minute)"
        tar --use-compress-program='zstd -d --long=30' -xf "$DL/LLVM-$LLVM_VER-Linux-X64.tar.zst" -C "$dst" --strip-components=1
        log "installed: $("$dst/bin/clang" --version | head -1) -> $dst"
    fi
    install_lld_icu "$dst"
}

# ld.lld in the official Linux tarball links against ICU 70, which is absent on
# newer distros and cannot be apt-installed without sudo. Vendor the shared libs
# from the Ubuntu jammy .deb into the toolchain (no sudo); env.sh sets the path.
install_lld_icu() {
    local dst=$1 icudir="$1/icu70"
    if [ -e "$icudir/libicuuc.so.70" ]; then return; fi
    local deb="$DL/libicu70_70.1-2_amd64.deb"
    log "vendoring ICU 70 for ld.lld"
    fetch "$ICU_URL" "$deb"
    verify "$deb" "$ICU_SHA"
    mkdir -p "$icudir"
    dpkg-deb -x "$deb" "$icudir"
}

ensure_lld_path() { :; }

install_ispc() {
    local dst="$TOOLCHAIN_ROOT/ispc-$ISPC_VER"
    if [ -x "$dst/bin/ispc" ]; then log "ispc $ISPC_VER already installed"; return; fi
    fetch "$ISPC_URL" "$DL/ispc-v$ISPC_VER-linux.tar.gz"
    verify "$DL/ispc-v$ISPC_VER-linux.tar.gz" "$ISPC_SHA"
    rm -rf "$dst"
    mkdir -p "$dst"
    tar -xzf "$DL/ispc-v$ISPC_VER-linux.tar.gz" -C "$dst" --strip-components=1
    log "installed: $("$dst/bin/ispc" --version | head -1) -> $dst"
}

what=${1:-all}
case "$what" in
    zig)  install_zig ;;
    llvm) install_llvm ;;
    ispc) install_ispc ;;
    all)  install_zig; install_llvm; install_ispc ;;
    *) echo "unknown target: $what" >&2; exit 2 ;;
esac
log "done. source scripts/env.sh to use."
