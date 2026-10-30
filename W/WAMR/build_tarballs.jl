using BinaryBuilder, Pkg

name = "WAMR"
version = v"2.4.5"

sources = [
    GitSource("https://github.com/wasm-micro-runtime/wasm-micro-runtime.git",
              "25bd7eb63e828e4bd242cc9b38d260b4b31c6605"),  # WAMR-2.4.5
    DirectorySource("./bundled"),
]

script = raw"""
cd ${WORKSPACE}/srcdir/wasm-micro-runtime
install_license LICENSE

# Export the wasm-c-api (`wasm_*`) symbols: WAMR builds with `-fvisibility=hidden`
# and only marks the `wasm_runtime_*` API as visible.
atomic_patch -p1 ${WORKSPACE}/srcdir/patches/export-wasm-c-api-symbols.patch

# Map BinaryBuilder targets to WAMR's `WAMR_BUILD_PLATFORM` (the directory in
# core/shared/platform) and `WAMR_BUILD_TARGET` (selects the `invokeNative` assembly).
if [[ "${target}" == *-freebsd* ]]; then
    WAMR_PLATFORM=freebsd
elif [[ "${target}" == *-apple-darwin* ]]; then
    WAMR_PLATFORM=darwin
else
    WAMR_PLATFORM=linux
fi

case "${target}" in
    x86_64-*)  WAMR_TARGET=X86_64 ;;
    i686-*)    WAMR_TARGET=X86_32 ;;
    aarch64-*) WAMR_TARGET=AARCH64 ;;
    arm-*)     WAMR_TARGET=ARMV7_VFP ;;  # all our 32-bit ARM targets are hard-float
    riscv64-*) WAMR_TARGET=RISCV64 ;;
esac

# Only the interpreters (classic + fast) are built: no AOT loader, no LLVM JIT.
# The root CMakeLists.txt fetches SIMDe with `FetchContent` at configure time, which
# needs network access; point it to the headers from SIMDe_jll instead.
cmake -B build -S . \
    -DCMAKE_INSTALL_PREFIX=${prefix} \
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN} \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DWAMR_BUILD_PLATFORM=${WAMR_PLATFORM} \
    -DWAMR_BUILD_TARGET=${WAMR_TARGET} \
    -DWAMR_BUILD_INTERP=1 \
    -DWAMR_BUILD_FAST_INTERP=1 \
    -DWAMR_BUILD_AOT=0 \
    -DWAMR_BUILD_JIT=0 \
    -DWAMR_BUILD_FAST_JIT=0 \
    -DWAMR_BUILD_LIBC_BUILTIN=1 \
    -DWAMR_BUILD_LIBC_WASI=1 \
    -DWAMR_BUILD_LIB_PTHREAD=1 \
    -DWAMR_BUILD_SHARED_MEMORY=1 \
    -DWAMR_BUILD_SIMD=1 \
    -DFETCHCONTENT_FULLY_DISCONNECTED=ON \
    -DFETCHCONTENT_SOURCE_DIR_SIMDE=${includedir}
cmake --build build --parallel ${nproc}
cmake --install build

# The CMake config files reference the build-time options and are of no use to us
rm -rf ${libdir}/cmake
"""

# WAMR has `invokeNative` assembly (needed for host function calls) for these architectures.
# Not supported: powerpc64le (no `invokeNative` implementation), armv6l (untested upstream).
platforms = supported_platforms(; exclude=p -> !(arch(p) in ("x86_64", "i686", "aarch64", "armv7l", "riscv64")))

# Windows: the Windows platform layer only builds with MSVC (the sources `#include <PathCch.h>`
# with mixed case, which fails with MinGW, and `invokeNative_ia32.asm` is MASM-only).
filter!(!Sys.iswindows, platforms)

# NOTE: Headers (wasm_export.h, wasm_c_api.h, lib_export.h) get installed too, but we
# aren't explicitly listing them as `FileProduct`s
products = [
    LibraryProduct("libiwasm", :libiwasm),
]

dependencies = [
    # Header-only; provides `simde/wasm/simd128.h` for the fast interpreter's SIMD support
    BuildDependency(PackageSpec(name="SIMDe_jll", version=v"0.8.2")),
]

build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
               julia_compat="1.6")
