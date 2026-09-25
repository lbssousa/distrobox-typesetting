#!/bin/bash
# Shared OS-detection and package-manager helpers, sourced by every
# install-*.sh script and by the container-bin/update-* helpers.
#
# Requires bash (uses arrays). Callers on Alpine's default /bin/sh (busybox
# ash) must bootstrap into bash before sourcing this file.

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------
detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "${ID:-linux}"
    elif [ -f /etc/alpine-release ]; then
        echo "alpine"
    else
        echo "linux"
    fi
}

OS_ID="$(detect_os)"

is_debian_like() {
    case "${OS_ID}" in
        debian|ubuntu|mint|pop|kali|raspbian) return 0 ;;
        *) return 1 ;;
    esac
}

is_redhat_like() {
    case "${OS_ID}" in
        rhel|centos|fedora|rocky|almalinux|ol) return 0 ;;
        *) return 1 ;;
    esac
}

is_alpine() {
    [ "${OS_ID}" = "alpine" ]
}

is_arch_like() {
    case "${OS_ID}" in
        arch|archarm|manjaro|manjaro-arm|endeavouros|garuda|arcolinux|cachyos) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Package manager helpers
# ---------------------------------------------------------------------------
pkg_install() {
    if is_debian_like; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y --no-install-recommends "$@"
    elif is_redhat_like; then
        if command -v dnf &>/dev/null; then
            dnf install -y "$@"
        else
            yum install -y "$@"
        fi
    elif is_alpine; then
        apk add --no-cache "$@"
    elif is_arch_like; then
        pacman -S --needed --noconfirm "$@"
    else
        echo "Unsupported OS: ${OS_ID}" >&2
        exit 1
    fi
}

pkg_remove() {
    if is_debian_like; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get purge -y "$@"
        apt-get autoremove -y
    elif is_redhat_like; then
        # pkgconf can never actually be removed on Fedora/RHEL container
        # images: it provides /usr/bin/pkg-config, which the base image's
        # kmod (required by the protected systemd-udev package) hard-depends
        # on. Filter it out rather than let the whole removal fail.
        local pkgs=()
        for pkg in "$@"; do
            [ "${pkg}" = "pkgconf" ] && continue
            pkgs+=("${pkg}")
        done
        if [ "${#pkgs[@]}" -eq 0 ]; then
            return
        fi
        # --setopt=clean_requirements_on_remove=False: dnf's default
        # cascading removal of now-unneeded dependencies can silently strip
        # a shared library (e.g. fontforge pulls in cairo) that a package
        # installed *later* in the same build still needs, since dnf never
        # re-verifies an already-installed package's deps on a later
        # install. Trades a bit of image size for not breaking later steps.
        if command -v dnf &>/dev/null; then
            dnf remove -y --setopt=clean_requirements_on_remove=False "${pkgs[@]}"
        else
            yum remove -y "${pkgs[@]}"
        fi
    elif is_alpine; then
        apk del "$@"
    elif is_arch_like; then
        # No-op by design. Unlike Debian/RHEL/Alpine, Arch doesn't split a
        # library from its headers (no "-dev"/"-devel" package), so there is
        # no way to remove "build-only" packages here without risking the
        # runtime library itself: pacman's own orphan-aware removal (-Rns)
        # cascades into whatever these pulled in transitively (e.g.
        # fontforge's cairo, needed later by zathura) and silently strips it
        # out, while a plain -Rn instead refuses outright once some other
        # already-installed package (pulled in the same way) still depends
        # on one of them. Leaving them installed trades image size for not
        # breaking later steps or the build itself.
        echo "Keeping build-only packages installed (Arch has no safe way to remove them): $*"
    fi
}

update_pkg_index() {
    if is_debian_like; then
        apt-get update -y
    elif is_redhat_like; then
        : # dnf/yum resolve on install
    elif is_alpine; then
        apk update
    elif is_arch_like; then
        # Arch never supports a partial upgrade (syncing the database without
        # also upgrading), so always pair -Sy with -u.
        pacman -Syu --noconfirm
    fi
}

upgrade_pkgs() {
    if is_debian_like; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get upgrade -y
    elif is_redhat_like; then
        if command -v dnf &>/dev/null; then
            dnf upgrade -y
        else
            yum update -y
        fi
    elif is_alpine; then
        apk update
        apk upgrade
    elif is_arch_like; then
        pacman -Syu --noconfirm
    else
        echo "Unsupported OS: ${OS_ID}" >&2
        exit 1
    fi
}

is_pkg_installed() {
    local pkg="$1"
    if is_debian_like; then
        dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "install ok installed"
    elif is_redhat_like; then
        rpm -q "${pkg}" &>/dev/null
    elif is_alpine; then
        apk info -e "${pkg}" &>/dev/null
    elif is_arch_like; then
        pacman -Q "${pkg}" &>/dev/null
    else
        return 1
    fi
}

# Install packages, recording only newly-installed ones (in the caller's
# _BUILD_PKGS_TO_REMOVE array) for removal after a build via remove_build_deps.
install_build_deps() {
    local to_install=()
    for pkg in "$@"; do
        if is_pkg_installed "${pkg}"; then
            echo "  (already present, will not remove later: ${pkg})"
        else
            _BUILD_PKGS_TO_REMOVE+=("${pkg}")
            to_install+=("${pkg}")
        fi
    done
    if [ "${#to_install[@]}" -gt 0 ]; then
        pkg_install "${to_install[@]}"
    fi
}

remove_build_deps() {
    if [ "${#_BUILD_PKGS_TO_REMOVE[@]}" -eq 0 ]; then
        return
    fi
    echo "Removing build-only packages: ${_BUILD_PKGS_TO_REMOVE[*]}"
    pkg_remove "${_BUILD_PKGS_TO_REMOVE[@]}"
    _BUILD_PKGS_TO_REMOVE=()
}
