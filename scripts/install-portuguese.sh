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
    elif is_arch_like; then
        # The official Arch Docker image's pacman.conf excludes non-English
        # locale sources (NoExtract) to keep the image small. Drop those
        # rules and force-reinstall glibc so pt_BR's source file actually
        # gets extracted; otherwise locale-gen fails with "cannot open
        # locale definition file `pt_BR'".
        if [ ! -e /usr/share/i18n/locales/pt_BR ]; then
            sed -i '/^NoExtract.*\(locale\|i18n\)/d' /etc/pacman.conf
            pacman -S --noconfirm --overwrite '*' glibc
        fi
        if ! grep -q '^pt_BR.UTF-8 ' /etc/locale.gen; then
            sed -i 's|^# *\(pt_BR.UTF-8 UTF-8\)|\1|' /etc/locale.gen || true
        fi
        if ! grep -q '^pt_BR.UTF-8 ' /etc/locale.gen; then
            echo 'pt_BR.UTF-8 UTF-8' >> /etc/locale.gen
        fi
        locale-gen
    else
        echo "Unsupported OS: ${OS_ID}" >&2
        exit 1
    fi

    echo "Portuguese language support complete."
}

main