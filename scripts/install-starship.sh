#!/bin/sh
# Installs the Starship shell prompt from the distribution package manager,
# and wires it up for bash/zsh via /etc/profile.d.
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

# /etc/profile.d is only read by login shells. `distrobox enter` normally
# starts an interactive, non-login shell, so this activates Starship
# out of the box for login shells (e.g. terminal emulators that start one)
# but not for every entry path. Documented as a known limitation in
# README.md; users whose shell doesn't pick this up can add the same
# `eval "$(starship init ...)"` line to their own ~/.bashrc / ~/.zshrc.
# Fallback for distros without a packaged Starship (e.g. Fedora, which has
# no official/COPR package): install the official static binary release.
install_from_official() {
    local arch
    case "$(uname -m)" in
        x86_64) arch="x86_64-unknown-linux-musl" ;;
        aarch64) arch="aarch64-unknown-linux-musl" ;;
        *)
            echo "ERROR: no official Starship static binary for arch $(uname -m)" >&2
            exit 1
            ;;
    esac

    local url="https://github.com/starship/starship/releases/latest/download/starship-${arch}.tar.gz"
    echo "No distro package available; installing Starship from the official static binary (${arch})."

    local download_dir
    download_dir="$(mktemp -d)"

    curl -sSfL "${url}" -o "${download_dir}/starship.tar.gz"
    tar -xzf "${download_dir}/starship.tar.gz" -C "${download_dir}"
    install -m 755 "${download_dir}/starship" /usr/local/bin/starship

    rm -rf "${download_dir}"
}

configure_shell_init() {
    mkdir -p /etc/profile.d
    cat > /etc/profile.d/starship.sh <<'EOF'
if [ -n "${BASH_VERSION:-}" ]; then
    eval "$(starship init bash)"
elif [ -n "${ZSH_VERSION:-}" ]; then
    eval "$(starship init zsh)"
fi
EOF
}

main() {
    echo "Installing Starship..."
    update_pkg_index
    if ! pkg_install starship; then
        install_from_official
    fi

    configure_shell_init

    echo "Starship installation complete."
    starship --version | head -1 || true
}

main
