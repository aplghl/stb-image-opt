# Source this to put the hermetic toolchain on PATH.
#   source scripts/env.sh
TOOLCHAIN_ROOT=${TOOLCHAIN_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/stb-image-opt/toolchain}
ZIG_VER=${ZIG_VER:-0.16.0}
LLVM_VER=${LLVM_VER:-23.1.2}
ISPC_VER=${ISPC_VER:-1.31.0}

for d in \
    "$TOOLCHAIN_ROOT/llvm-$LLVM_VER/bin" \
    "$TOOLCHAIN_ROOT/zig-$ZIG_VER" \
    "$TOOLCHAIN_ROOT/ispc-$ISPC_VER/bin" \
; do
    [ -d "$d" ] && PATH="$d:$PATH"
done
export PATH

# Vendored ICU 70 required by ld.lld from the official LLVM tarball.
ICU70_LIB="$TOOLCHAIN_ROOT/llvm-$LLVM_VER/icu70/usr/lib/x86_64-linux-gnu"
if [ -d "$ICU70_LIB" ]; then
    LD_LIBRARY_PATH="$ICU70_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export LD_LIBRARY_PATH
fi

command -v clang    >/dev/null && export CLANG=$(command -v clang)
command -v zig      >/dev/null && export ZIG=$(command -v zig)
command -v llvm-bolt >/dev/null && export LLVM_BOLT=$(command -v llvm-bolt)
