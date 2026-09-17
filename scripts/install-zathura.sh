#!/bin/sh
# Installs Zathura plus a PDF backend plugin from the distribution package
# manager. Zathura ships with no PDF support at all until a backend plugin is
# installed alongside it.
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

# Prefer the poppler backend (available under this name on Alpine, Debian and
# Fedora); fall back to the mupdf backend where poppler isn't packaged.
install_pdf_backend() {
    if pkg_install zathura-pdf-poppler 2>/dev/null; then
        return
    fi
    echo "zathura-pdf-poppler unavailable, falling back to zathura-pdf-mupdf" >&2
    pkg_install zathura-pdf-mupdf
}

main() {
    echo "Installing Zathura..."
    update_pkg_index
    pkg_install zathura
    install_pdf_backend

    echo "Zathura installation complete."
    zathura --version | head -1 || true
}

main
