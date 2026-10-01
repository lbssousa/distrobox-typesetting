#!/bin/sh
# Builds and installs Neovim from source. Distro packages lag behind
# upstream, so this always builds a specific upstream release (default:
# whatever GitHub currently reports as "latest") rather than relying on the
# package manager.
#
# bash is needed for arrays (_BUILD_PKGS_TO_REMOVE, see common.sh).
VERSION="${VERSION:-latest}"

if [ -z "${BASH_VERSION:-}" ]; then
    if ! command -v bash >/dev/null 2>&1; then
        if command -v apk >/dev/null 2>&1; then
            echo "Installing bash (required for build)..."
            apk add --no-cache bash
        else
            echo "ERROR: bash is required but not found." >&2
            exit 1
        fi
    fi
    exec bash "$0" "$@"
fi

# ---- bash only below this line ----
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

BUILD_DIR="$(mktemp -d)"
_BUILD_PKGS_TO_REMOVE=()

cleanup() {
    rm -rf "${BUILD_DIR}"
}
trap cleanup EXIT

# nvim-treesitter (and any other plugin that compiles its own parsers, e.g.
# via :TSInstall) invokes a C/C++ compiler at runtime, inside the container,
# long after the image is built -- so this must stay installed permanently,
# unlike the various install_build_deps/remove_build_deps pairs below that
# are fine to strip after this script's own build. It also serves as this
# script's build toolchain.
install_compiler_toolchain() {
    if is_debian_like; then
        pkg_install build-essential
    elif is_redhat_like; then
        pkg_install gcc gcc-c++ make
    elif is_alpine; then
        pkg_install gcc g++ make musl-dev
    elif is_arch_like; then
        pkg_install gcc make
    fi
}

# musl (unlike glibc) doesn't implement gettext itself, so Neovim dynamically
# links against Alpine's separate libintl shim at runtime. It comes in as a
# transitive dependency of the build-only gettext-dev package below, so it
# must be (re-)installed here as a plain, non-build-only package, or it gets
# swept away as an orphan once gettext-dev is removed after the build.
install_runtime_deps() {
    if is_alpine; then
        pkg_install libintl
    fi
}

# Build-only dependencies on top of the compiler toolchain above: Neovim's
# CMake build fetches and builds its own bundled copies of libuv, msgpack,
# LuaJIT, tree-sitter and friends, so none of those need to be preinstalled.
install_build_deps_for_neovim() {
    if is_debian_like; then
        install_build_deps ninja-build gettext cmake unzip curl ca-certificates pkg-config
    elif is_redhat_like; then
        install_build_deps ninja-build cmake unzip gettext curl ca-certificates pkgconf glibc-static
    elif is_alpine; then
        # linux-headers: libuv's UDP code needs <linux/errqueue.h>, which
        # musl doesn't bundle (unlike glibc, which pulls it in transitively).
        install_build_deps cmake coreutils unzip gettext-dev curl ca-certificates linux-headers
    elif is_arch_like; then
        install_build_deps cmake unzip ninja curl ca-certificates pkgconf
    fi
}

resolve_latest_release() {
    curl -sSL "https://api.github.com/repos/neovim/neovim/releases/latest" \
        | grep '"tag_name"' | head -1 \
        | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

main() {
    echo "Installing Neovim build dependencies..."
    update_pkg_index
    install_compiler_toolchain
    install_runtime_deps
    install_build_deps_for_neovim

    local tag="${VERSION}"
    if [ "${tag}" = "latest" ]; then
        echo "Resolving latest Neovim release..."
        tag="$(resolve_latest_release)"
        if [ -z "${tag}" ]; then
            echo "ERROR: could not resolve the latest Neovim release." >&2
            exit 1
        fi
        echo "  -> ${tag}"
    fi

    local prefix="/opt/neovim/${tag#v}"
    local url="https://github.com/neovim/neovim/archive/refs/tags/${tag}.tar.gz"

    echo "Downloading Neovim ${tag}: ${url}"
    curl -sSfL -o "${BUILD_DIR}/neovim.tar.gz" "${url}"
    mkdir -p "${BUILD_DIR}/src"
    tar -xzf "${BUILD_DIR}/neovim.tar.gz" --strip-components=1 -C "${BUILD_DIR}/src"

    echo "Building Neovim ${tag} (this may take a while)..."
    (
        cd "${BUILD_DIR}/src"
        make CMAKE_BUILD_TYPE=RelWithDebInfo CMAKE_INSTALL_PREFIX="${prefix}"
        make install
    )

    for bin in "${prefix}/bin"/*; do
        [ -e "${bin}" ] || continue
        ln -sf "${bin}" "/usr/local/bin/$(basename "${bin}")"
    done

    echo "Removing Neovim build-only dependencies..."
    remove_build_deps

    echo "Neovim installation complete."
    nvim --version | head -1 || true
    cc --version 2>&1 | head -1 || true
}

main
