using BinaryBuilder

const YGGDRASIL_DIR = "../.."
include(joinpath(YGGDRASIL_DIR, "platforms", "macos_sdks.jl"))

name = "Wasmtime"
version = v"50.0.1"

sources = [GitSource("https://github.com/bytecodealliance/wasmtime.git",
                     "c307ec81de02852d815e9849f7c89d955c03c30d";
                     tag="v$(version)")]

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
    --locked \
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
    -DCMAKE_INSTALL_LIBDIR=${libdir} \
    -DWASMTIME_USER_CARGO_BUILD_OPTIONS=--locked
cmake --build . --target install

install_license ${WORKSPACE}/srcdir/wasmtime/LICENSE
"""

# `helpers.c` references `__unw_add_dynamic_fde`, which the default x86_64 macOS SDK (10.12)
# does not export from libSystem; the SDK used on aarch64 (11.1) does. Use a newer SDK, but
# keep the deployment target low so the minimum macOS version does not change.
sources, script = require_macos_sdk("11.1", sources, script; deployment_target="10.12")

platforms = supported_platforms(; exclude=(p -> !(arch(p) in ("x86_64", "aarch64"))))

# Filter musl because Rust >= 1.84 (Wasmtime 50 requires >= 1.97) assumes musl 1.2.3
# and emits hard references to `getrandom` and `posix_spawn_file_actions_addchdir_np`,
# which our musl 1.1.19 does not provide.
# See https://github.com/rust-lang/rust/issues/141795
filter!(p -> libc(p) != "musl", platforms)

# NOTE: Headers get installed too but we aren't explicitly listing them as `FileProduct`s
# On Windows the DLL keeps its upstream name `wasmtime.dll`, which is what `libwasmtime.dll.a` imports
products = [LibraryProduct(["libwasmtime", "wasmtime"], :libwasmtime),
            ExecutableProduct("wasmtime", :wasmtime)]

dependencies = Dependency[]

build_tarballs(ARGS, name, version, sources, script, platforms, products, dependencies;
               compilers=[:c, :rust], julia_compat="1.6")
