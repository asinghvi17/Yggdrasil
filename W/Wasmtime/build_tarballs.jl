using BinaryBuilder

name = "Wasmtime"
version = v"50.0.1"

sources = [GitSource("https://github.com/bytecodealliance/wasmtime.git",
                     "c307ec81de02852d815e9849f7c89d955c03c30d")]

# Based on `wasmtime/ci/build-release-artifacts.sh
script = raw"""
cd ${WORKSPACE}/srcdir/wasmtime/

export CARGO_PROFILE_RELEASE_STRIP=debuginfo
export CARGO_PROFILE_RELEASE_PANIC=abort

if [[ "${target}" == armv* ]] || [[ "${target}" == aarch64-linux* ]]; then
    # The `ring` crate in the dependency tree requires this be set on ARM targets
    export CFLAGS="-D__ARM_ARCH"
fi

cargo build \
    --release \
    --target ${rust_target} \
    -p wasmtime-cli \
    --features all-arch,component-model \
    --features run
install -Dvm 0755 \
    "target/${rust_target}/release/wasmtime${exeext}" \
    "${bindir}/wasmtime${exeext}"

mkdir -p target/c-api-build
cd target/c-api-build
cmake ../../crates/c-api \
    -DCMAKE_BUILD_TYPE=Release \
    -DWASMTIME_TARGET=${rust_target} \
    -DCMAKE_INSTALL_PREFIX=${prefix} \
    -DCMAKE_INSTALL_LIBDIR=${libdir}
cmake --build . --target install

if [[ "${target}" == *-mingw* ]]; then
    mv "${libdir}/wasmtime.dll" "${libdir}/libwasmtime.dll"
fi

install_license ${WORKSPACE}/srcdir/wasmtime/LICENSE
"""

platforms = supported_platforms(; exclude=(p -> !(arch(p) in ("x86_64", "aarch64"))))

# Filter musl because Rust >= 1.84 (Wasmtime 50 requires >= 1.97) assumes musl 1.2.3
# and emits hard references to `getrandom` and `posix_spawn_file_actions_addchdir_np`,
# which our musl 1.1.19 does not provide.
# See https://github.com/rust-lang/rust/issues/141795
filter!(p -> libc(p) != "musl", platforms)

# NOTE: Headers get installed too but we aren't explicitly listing them as `FileProduct`s
products = [LibraryProduct("libwasmtime", :libwasmtime),
            ExecutableProduct("wasmtime", :wasmtime)]

dependencies = Dependency[]

build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
               compilers=[:c, :rust], julia_compat="1.6")
