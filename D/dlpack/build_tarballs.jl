using BinaryBuilder

name = "dlpack"
version = v"1.3.0"

sources = [
    # Tag v1.3; upstream publishes no release tarballs.
    GitSource("https://github.com/dmlc/dlpack.git",
              "84d107bf416c6bab9ae68ad285876600d230490d"),
]

script = raw"""
cd ${WORKSPACE}/srcdir/dlpack
cmake -B build -G Ninja \
    -DCMAKE_INSTALL_PREFIX=${prefix} \
    -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TARGET_TOOLCHAIN} \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_MOCK=OFF \
    -DBUILD_DOCS=OFF
cmake --build build --parallel ${nproc}
cmake --install build
# Not covered by upstream's install rules.
install -Dm644 contrib/dlpack/dlpackcpp.h "${includedir}/dlpack/dlpackcpp.h"
install_license LICENSE
"""

platforms = [AnyPlatform()]

products = Product[
    FileProduct("include/dlpack/dlpack.h", :dlpack_h),
    FileProduct("include/dlpack/dlpackcpp.h", :dlpackcpp_h),
]

dependencies = Dependency[]

build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
    julia_compat="1.6")
