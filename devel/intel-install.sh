#!/bin/bash
# Shared helper to install Intel oneAPI arch:all packages that OBS DoD
# cannot resolve (only binary-amd64 is fetched by OBS download-on-demand).
#
# Usage: . /usr/src/packages/BUILD/devel/intel-install.sh
#        (after sourcing, Intel module should be available)

install_intel_arch_all() {
    if [ -f /opt/intel/oneapi/setvars.sh ]; then
        return 0
    fi
    local SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if ! ls "$SCRIPT_DIR"/intel-oneapi-*_all.deb 1>/dev/null 2>&1; then
        echo "WARNING: intel-oneapi-*_all.deb not found in $SCRIPT_DIR"
        return 1
    fi
    echo "Installing Intel oneAPI arch:all packages..."
    local _SAVED_PWD="$PWD"
    local _TMPEXT
    _TMPEXT=$(mktemp -d)
    local deb
    for deb in "$SCRIPT_DIR"/intel-oneapi-*_all.deb; do
        dpkg-deb -x "$deb" "$_TMPEXT" 2>/dev/null
    done
    if [ -d "$_TMPEXT/opt/intel" ]; then
        cp -a "$_TMPEXT"/opt/intel/oneapi/* /opt/intel/oneapi/ 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "cp failed, trying file-by-file..."
            local f rel
            find "$_TMPEXT/opt" -type f | while read f; do
                rel="${f#$_TMPEXT/}"
                mkdir -p "/$(dirname "$rel")" 2>/dev/null
                cp -f "$f" "/$rel" 2>/dev/null
            done
        fi
    fi
    rm -rf "$_TMPEXT"
    cd "$_SAVED_PWD"
    if [ -f /opt/intel/oneapi/setvars.sh ]; then
        echo "Intel arch:all install OK, generating modulefiles..."
        /opt/ohpc/admin/ohpc/bin/ohpc-update-modules-intel 2>&1 || true
        [ -x /opt/ohpc/admin/ohpc/bin/ohpc-update-modules-impi ] && \
            /opt/ohpc/admin/ohpc/bin/ohpc-update-modules-impi 2>&1 || true
        return 0
    fi
    echo "WARNING: Intel arch:all install failed - setvars.sh still missing"
    return 1
}

install_intel_arch_all
