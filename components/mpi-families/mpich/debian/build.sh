#!/bin/bash
# Helper script for building MPICH within debian/rules.
# Sets up compiler environment, matching the EL RPM build.
set -e

COMPILER_FAMILY="${COMPILER_FAMILY:-gnu15}"

export MODULEPATH=/opt/ohpc/pub/modulefiles
. /opt/ohpc/admin/lmod/lmod/init/bash
. /opt/ohpc/admin/ohpc/OHPC_setup_compiler "$COMPILER_FAMILY"

setup_debian_multiarch_paths() {
    local multiarch dir
    multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
    [ -n "$multiarch" ] || return 0

    for dir in "/usr/lib/${multiarch}" "/lib/${multiarch}"; do
        [ -d "$dir" ] || continue
        export LIBRARY_PATH="${dir}${LIBRARY_PATH:+:${LIBRARY_PATH}}"
        export LD_LIBRARY_PATH="${dir}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
        export LDFLAGS="-L${dir} ${LDFLAGS:-}"
    done

    if [ -d "/usr/include/${multiarch}" ]; then
        export CPATH="/usr/include/${multiarch}${CPATH:+:${CPATH}}"
        export CPPFLAGS="-I/usr/include/${multiarch} ${CPPFLAGS:-}"
    fi
    if [ -d "/usr/lib/${multiarch}/pkgconfig" ]; then
        export PKG_CONFIG_PATH="/usr/lib/${multiarch}/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
    fi
}

setup_debian_multiarch_paths

# Fix Ubuntu's libfabric.pc: remove PSM/EFA libs that aren't installed
# (Ubuntu advertises PSM providers in static libs but doesn't ship them)
MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null)
_FABPC="/usr/lib/${MULTIARCH}/pkgconfig/libfabric.pc"
if [ -f "$_FABPC" ]; then
    # Copy to a writable location (OBS builds as non-root)
    mkdir -p /tmp/ohpc-pkgconfig
    cp "$_FABPC" /tmp/ohpc-pkgconfig/
    sed -i 's/-lpsm_infinipath//g; s/-lpsm2//g; s/-lefa//g' \
        /tmp/ohpc-pkgconfig/libfabric.pc
    export PKG_CONFIG_PATH="/tmp/ohpc-pkgconfig:${PKG_CONFIG_PATH}"
fi

exec "$@"
