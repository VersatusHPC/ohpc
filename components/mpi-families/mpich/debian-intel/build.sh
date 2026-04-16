#!/bin/bash
# Helper script for building MPICH within debian/rules.
# Sets up Intel compiler environment, matching the EL RPM build.
set -e

COMPILER_FAMILY="${COMPILER_FAMILY:-intel}"

# Save positional parameters — Intel oneAPI vars.sh clobbers $@
_SAVED_ARGS=("$@")

export MODULEPATH=/opt/ohpc/pub/modulefiles
. /opt/ohpc/admin/lmod/lmod/init/bash
# Source Intel oneAPI environment
[ -f /opt/intel/oneapi/compiler/latest/env/vars.sh ] && . /opt/intel/oneapi/compiler/latest/env/vars.sh 2>/dev/null
[ -f /opt/intel/oneapi/mkl/latest/env/vars.sh ] && . /opt/intel/oneapi/mkl/latest/env/vars.sh 2>/dev/null
. /opt/ohpc/admin/ohpc/OHPC_setup_compiler "$COMPILER_FAMILY"

# Restore positional parameters
set -- "${_SAVED_ARGS[@]}"

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
