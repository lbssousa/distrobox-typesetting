#!/bin/sh
# Installs the OS-level packages needed for Portuguese-language support
# (pt_BR.UTF-8 locale data and message catalogs) on the container's base
# distribution, independently of the configured LOCALE.
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

main() {
    echo "Ensuring Portuguese language support packages..."
    update_pkg_index

    if is_alpine; then
        pkg_install musl-locales musl-locales-lang
    elif is_debian_like; then
        pkg_install locales
        if ! grep -q '^pt_BR.UTF-8 ' /etc/locale.gen; then
            sed -i 's|^# *\(pt_BR.UTF-8 UTF-8\)|\1|' /etc/locale.gen || true
        fi
        if ! grep -q '^pt_BR.UTF-8 ' /etc/locale.gen; then
            echo 'pt_BR.UTF-8 UTF-8' >> /etc/locale.gen
        fi
        locale-gen
    elif is_redhat_like; then
        pkg_install glibc-langpack-pt
    else
        echo "Unsupported OS: ${OS_ID}" >&2
        exit 1
    fi

    echo "Portuguese language support complete."
}

main