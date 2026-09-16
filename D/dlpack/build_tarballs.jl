# Note that this script can accept some limited command-line arguments, run
# `julia build_tarballs.jl --help` to see a usage message.
using BinaryBuilder

name = "dlpack"
version = v"1.3.0"

# Collection of sources required to complete build
sources = [
    # Tag v1.3.  Upstream publishes no release artifacts, and GitHub's automatic
    # source archives have no stable checksum, so track the tagged commit.
    GitSource("https://github.com/dmlc/dlpack.git",
              "84d107bf416c6bab9ae68ad285876600d230490d"),
]

# Bash recipe for building across all platforms
script = raw"""
cd ${WORKSPACE}/srcdir/dlpack
# Upstream's `project(dlpack VERSION 0.6)` is stale, so the installed
# dlpackConfigVersion.cmake advertises 0.6.  The authoritative version is the
# DLPACK_MAJOR_VERSION/DLPACK_MINOR_VERSION pair in dlpack.h (1.3 here).
cmake -B build -G Ninja \
    -DCMAKE_INSTALL_PREFIX=${prefix} \
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN} \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_MOCK=OFF \
    -DBUILD_DOCS=OFF
cmake --build build --parallel ${nproc}
cmake --install build
# The C++ convenience wrapper is not covered by upstream's CMake install rules.
install -Dm644 contrib/dlpack/dlpackcpp.h "${includedir}/dlpack/dlpackcpp.h"
install_license LICENSE
"""

# These are the platforms we will build for by default, unless further
# platforms are passed in on the command line
platforms = [AnyPlatform()]

# The products that we will ensure are always built
products = Product[
    # This is a header-only library without any binary products
    FileProduct("include/dlpack/dlpack.h", :dlpack_h),
    FileProduct("include/dlpack/dlpackcpp.h", :dlpackcpp_h),
]

# Dependencies that must be installed before this package can be built
dependencies = Dependency[]

# Build the tarballs, and possibly a `build.jl` as well.
build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
    julia_compat="1.6")
