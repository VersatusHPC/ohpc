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
MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null)
if [ -f "/usr/lib/${MULTIARCH}/pkgconfig/libfabric.pc" ]; then
    sed -i 's/-lpsm_infinipath//g; s/-lpsm2//g; s/-lefa//g' \
        "/usr/lib/${MULTIARCH}/pkgconfig/libfabric.pc"
fi

exec "$@"
