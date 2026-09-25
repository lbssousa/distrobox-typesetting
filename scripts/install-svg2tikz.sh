#!/bin/sh
# Installs svg2tikz into an isolated venv under /opt/svg2tikz (symlinked into
# /usr/local/bin, following the same /opt-prefix convention as TeX Live and
# LilyPond), and best-effort registers its Inkscape extension files so it is
# also usable from Inkscape's GUI "Extensions" menu.
#
# A dedicated venv (rather than pipx) is used deliberately: pipx installs into
# the invoking user's home directory by default, which during an image build
# means root's home -- inaccessible to the non-root user distrobox normally
# runs as. /opt/svg2tikz is world-readable and independent of who builds it.
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

SVG2TIKZ_PREFIX="/opt/svg2tikz"
_BUILD_PKGS_TO_REMOVE=()

install_python_prereqs() {
    update_pkg_index
    if is_debian_like; then
        pkg_install python3 python3-venv
    elif is_redhat_like; then
        pkg_install python3
    elif is_alpine; then
        pkg_install python3
    elif is_arch_like; then
        pkg_install python
    fi
}

# svg2tikz (via inkex/lxml/pygobject/pycairo/numpy) ships no musl (Alpine)
# wheels, and often none for the exact Python/arch combination in the
# container either, so pip falls back to building several of its
# dependencies from source:
#   - lxml needs the libxml2/libxslt development headers.
#   - pycairo (a pygobject dependency) needs the cairo development headers.
#   - pygobject itself needs the GObject-Introspection development headers
#     (girepository-1.0).
#   - numpy (an inkex dependency) needs a C++ compiler (g++), not just a C
#     one, for its Meson build.
# Install a C/C++ compiler, Python headers, and all of the above as
# build-only deps, and remove them again once the venv is populated.
install_native_build_deps() {
    if is_debian_like; then
        install_build_deps \
            gcc g++ python3-dev pkg-config \
            libxml2-dev libxslt1-dev \
            libcairo2-dev libgirepository1.0-dev
    elif is_redhat_like; then
        # cairo-gobject.h ships in its own subpackage on Fedora/RHEL, unlike
        # Debian/Alpine/Arch which bundle it into their main cairo dev
        # package; pygobject's build fails without it.
        install_build_deps \
            gcc gcc-c++ python3-devel pkgconf \
            libxml2-devel libxslt-devel \
            cairo-devel cairo-gobject-devel gobject-introspection-devel
    elif is_alpine; then
        install_build_deps \
            gcc g++ musl-dev python3-dev pkgconfig \
            libxml2-dev libxslt-dev \
            cairo-dev gobject-introspection-dev
    elif is_arch_like; then
        install_build_deps \
            base-devel pkgconf \
            libxml2 libxslt \
            cairo gobject-introspection
    fi
}

# Copy any bundled Inkscape .inx/.py extension files from the venv's
# site-packages into the system Inkscape extensions directory.
register_inkscape_extension() {
    local ext_src
    ext_src="$(find "${SVG2TIKZ_PREFIX}" -type d -iname 'inkscape' -path '*svg2tikz*' 2>/dev/null | head -1 || true)"

    if [ -z "${ext_src}" ]; then
        echo "NOTE: svg2tikz's pip package does not bundle Inkscape .inx extension" >&2
        echo "      files at a discoverable path; skipping GUI extension registration." >&2
        echo "      The 'svg2tikz' CLI command remains available." >&2
        return
    fi

    local ext_dir="/usr/share/inkscape/extensions"
    mkdir -p "${ext_dir}"
    echo "Registering svg2tikz as an Inkscape extension from ${ext_src}"
    cp -r "${ext_src}"/. "${ext_dir}/"
}

main() {
    echo "Installing svg2tikz..."
    install_python_prereqs
    install_native_build_deps

    python3 -m venv "${SVG2TIKZ_PREFIX}"
    "${SVG2TIKZ_PREFIX}/bin/pip" install --no-cache-dir --upgrade pip

    # svg2tikz/inkex pin lxml<6.0.0 and pygobject<=3.50.0. On a
    # current-enough distro (confirmed on Arch and Ubuntu 26.04, likely any
    # rolling/very recent release), building lxml<6 from source fails: its
    # libxml2 tightened a C API's constness in a way only lxml>=6 accounts
    # for, and lxml<6 ships no prebuilt wheel for such a recent Python
    # either. lxml>=6 is fully API-compatible with what inkex/svg2tikz
    # actually call, so always install it (and everything else) unpinned,
    # then install svg2tikz/inkex with --no-deps so pip never re-evaluates
    # their lxml/pygobject pins against it. Harmless on older distros too:
    # pip just picks whatever lxml/pygobject build already works there.
    "${SVG2TIKZ_PREFIX}/bin/pip" install --no-cache-dir \
        lxml "pygobject<=3.50.0" \
        "Pillow>=7.0.0" "cssselect>=1.2.0,<2.0.0" \
        "numpy>=1.21.2,<2.0.0" "packaging>=20.3" \
        "pySerial>=3.4,<4.0" "pyparsing>=3.0.9" \
        "scour>=0.37,<0.38" "tinycss2>=1.0.1,<2.0.0"
    "${SVG2TIKZ_PREFIX}/bin/pip" install --no-cache-dir --no-deps svg2tikz "inkex==1.4.0"

    remove_build_deps

    for bin in "${SVG2TIKZ_PREFIX}/bin"/svg2tikz "${SVG2TIKZ_PREFIX}/bin"/inkscape-tikz; do
        [ -e "${bin}" ] || continue
        ln -sf "${bin}" "/usr/local/bin/$(basename "${bin}")"
    done

    register_inkscape_extension

    echo "svg2tikz installation complete."
    svg2tikz --version 2>&1 | head -1 || true
}

main
