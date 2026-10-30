using BinaryBuilder

name = "Wasmi"
version = v"2.0.0"

sources = [GitSource("https://github.com/wasmi-labs/wasmi.git",
                     "2970aa871cc1001b57b267ccecdcd1e42306199e";
                     tag="v$(version)"),
           DirectorySource("./bundled")]

# Builds the C API (`crates/c_api`) through its CMake frontend, same approach as Wasmtime.
script = raw"""
cd ${WORKSPACE}/srcdir/wasmi/

# Fixes for bugs in the v2.0.0 C API (missing `wasmi_error_message`, swapped values in
# `enum wasmi_compilation_mode_enum`, stale `WASMI_VERSION*`). These should go upstream.
for f in ${WORKSPACE}/srcdir/patches/*.patch; do
    atomic_patch -p1 "${f}"
done

mkdir -p target/c-api-build
cd target/c-api-build

# * The CMake frontend always calls cargo with `--no-default-features`, so the upstream default
#   features (`std`, `memory64`, `auto-dispatch`) have to be passed back explicitly.
# * The `WASMI_USER_CARGO_BUILD_OPTIONS` is a CMake list (hence the `;`), so it expands to
#   separate cargo arguments.
# * `CMAKE_INSTALL_LIBDIR` has to be relative to the prefix: upstream's macOS install rules
#   prepend `CMAKE_INSTALL_PREFIX` to it again.
# * `prefix-symbols` is deliberately NOT enabled: it renames the exported `wasm_*` functions to
#   `wasmi_wasm_*`, but the installed `wasm.h` does not remap them, so the headers would no
#   longer match the library.
# * CMake unconditionally requires `clang-format` (for the `format` targets) which we don't
#   need, so point it to a dummy program.
cmake ../../crates/c_api \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DWASMI_TARGET=${rust_target} \
    -DWASMI_USER_CARGO_BUILD_OPTIONS="--locked;--features=std,memory64,auto-dispatch" \
    -DCLANG_FORMAT=/bin/true \
    -DCMAKE_INSTALL_PREFIX=${prefix} \
    -DCMAKE_INSTALL_LIBDIR=${libdir#${prefix}/}
cmake --build . --target install

cd ${WORKSPACE}/srcdir/wasmi/
install_license LICENSE-APACHE LICENSE-MIT
"""

# Wasmi itself is portable, but upstream only builds and tests the C API on
# {x86_64, aarch64} x {Linux, macOS, Windows}, so we limit ourselves to the 64-bit platforms
platforms = supported_platforms(; exclude=(p -> !(arch(p) in ("x86_64", "aarch64"))))

# Filter musl because Rust's `std` (>= 1.84) assumes musl 1.2.3 and emits hard references to
# `getrandom`, which our musl 1.1.19 does not provide.
# See https://github.com/rust-lang/rust/issues/141795 and the comment in Wasmtime
filter!(p -> libc(p) != "musl", platforms)

# NOTE: Headers get installed too but we aren't explicitly listing them as `FileProduct`s
# On Windows the DLL is called `wasmi.dll`, which is also the name recorded in the import library
products = [LibraryProduct(["libwasmi", "wasmi"], :libwasmi)]

dependencies = Dependency[]

build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
               compilers=[:c, :rust], julia_compat="1.6")
