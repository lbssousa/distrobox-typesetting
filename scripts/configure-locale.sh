#!/bin/sh
# Installs the locale support libraries/data for the requested locale and makes
# it the container's default (LANG), so it matches the host's. Reads the
# locale from $LOCALE (e.g. pt_BR.UTF-8; default C.UTF-8, which needs no data).
#
#   Alpine (musl)   musl-locales (locale data + `locale` command); Alpine's
#                   default /etc/profile.d/20locale.sh is replaced because it
#                   forces LC_COLLATE=C on login shells.
#   Debian family   `locales` package + locale-gen + update-locale.
#   Red Hat family  glibc langpack (or localedef as a fallback) + /etc/locale.conf.
#   Arch family     glibc's own locale-gen (no separate locales package) +
#                   /etc/locale.conf.
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

LOCALE="${LOCALE:-C.UTF-8}"

# Split "pt_BR.UTF-8" into its parts: pt_BR / pt / UTF-8.
LOCALE_NAME="${LOCALE%%.*}"
LOCALE_LANG="${LOCALE_NAME%%_*}"
if [[ "${LOCALE}" == *.* ]]; then
    LOCALE_CODESET="${LOCALE#*.}"
else
    LOCALE_CODESET="UTF-8"
    LOCALE="${LOCALE}.UTF-8"
fi

# C/POSIX locales are built into libc: nothing to install or generate.
is_builtin_locale() {
    case "${LOCALE_NAME}" in
        C|POSIX) return 0 ;;
        *) return 1 ;;
    esac
}

configure_alpine() {
    update_pkg_index
    pkg_install musl-locales musl-locales-lang

    if [ ! -e "/usr/share/i18n/locales/musl/${LOCALE}" ]; then
        echo "WARNING: musl-locales has no data for ${LOCALE}; musl will fall back to" >&2
        echo "         its built-in behaviour (UTF-8 charset, untranslated messages)." >&2
    fi

    # Replaces alpine-baselayout's file, which exports LC_COLLATE=C. As a
    # modified /etc file it is kept (not overwritten) by `apk upgrade`.
    # MUSL_LOCPATH itself comes from musl-locales' /etc/profile.d/00locale.sh.
    cat > /etc/profile.d/20locale.sh <<EOF
export CHARSET=\${CHARSET:-${LOCALE_CODESET}}
export LANG=\${LANG:-${LOCALE}}
EOF
}

configure_debian() {
    update_pkg_index
    pkg_install locales

    # /etc/locale.gen lists every locale commented out as "# pt_BR.UTF-8 UTF-8".
    if ! sed -i "s|^# *\(${LOCALE} ${LOCALE_CODESET}\)|\1|" /etc/locale.gen \
        || ! grep -q "^${LOCALE} ${LOCALE_CODESET}" /etc/locale.gen; then
        echo "${LOCALE} ${LOCALE_CODESET}" >> /etc/locale.gen
    fi
    locale-gen
    update-locale LANG="${LOCALE}"
}

configure_arch() {
    update_pkg_index

    # The official Arch Docker image's pacman.conf excludes non-English
    # locale sources (NoExtract) to keep the image small. Drop those rules
    # and force-reinstall glibc so this locale's source file actually gets
    # extracted; otherwise locale-gen fails with "cannot open locale
    # definition file".
    if [ ! -e "/usr/share/i18n/locales/${LOCALE_NAME}" ]; then
        sed -i '/^NoExtract.*\(locale\|i18n\)/d' /etc/pacman.conf
        pacman -S --noconfirm --overwrite '*' glibc
    fi

    # /etc/locale.gen lists every locale commented out as "# pt_BR.UTF-8 UTF-8".
    if ! sed -i "s|^# *\(${LOCALE} ${LOCALE_CODESET}\)|\1|" /etc/locale.gen \
        || ! grep -q "^${LOCALE} ${LOCALE_CODESET}" /etc/locale.gen; then
        echo "${LOCALE} ${LOCALE_CODESET}" >> /etc/locale.gen
    fi
    locale-gen
    echo "LANG=${LOCALE}" > /etc/locale.conf
}

configure_redhat() {
    if ! pkg_install "glibc-langpack-${LOCALE_LANG}"; then
        echo "No glibc-langpack-${LOCALE_LANG}; generating ${LOCALE} with localedef."
        pkg_install glibc-locale-source glibc-common
        localedef -i "${LOCALE_NAME}" -f "${LOCALE_CODESET}" "${LOCALE}"
    fi
    echo "LANG=${LOCALE}" > /etc/locale.conf
}

main() {
    echo "Configuring locale ${LOCALE}..."

    if is_builtin_locale; then
        echo "${LOCALE} is provided by libc; no locale data to install."
    elif is_alpine; then
        configure_alpine
    elif is_debian_like; then
        configure_debian
    elif is_redhat_like; then
        configure_redhat
    elif is_arch_like; then
        configure_arch
    else
        echo "Unsupported OS: ${OS_ID}" >&2
        exit 1
    fi

    echo "Locale configuration complete."
}

main
