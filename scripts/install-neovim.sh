#!/bin/sh
# Installs Neovim from the distribution package manager.
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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

# nvim-treesitter (and any other plugin that compiles its own parsers, e.g.
# via :TSInstall) invokes a C/C++ compiler at runtime, inside the container,
# long after the image is built -- so this must stay installed permanently,
# unlike the various install_build_deps/remove_build_deps pairs elsewhere in
# this project that are fine to strip after their one build step.
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

main() {
    echo "Installing Neovim..."
    update_pkg_index
    pkg_install neovim
    install_compiler_toolchain

    echo "Neovim installation complete."
    nvim --version | head -1 || true
    cc --version 2>&1 | head -1 || true
}

main
