#!/bin/bash
# Helper script for building MPICH within debian/rules.
# Sets up compiler environment, matching the EL RPM build.
set -e

COMPILER_FAMILY="${COMPILER_FAMILY:-gnu15}"

export MODULEPATH=/opt/ohpc/pub/modulefiles
. /opt/ohpc/admin/lmod/lmod/init/bash
. /opt/ohpc/admin/ohpc/OHPC_setup_compiler "$COMPILER_FAMILY"

# Fix Ubuntu's libfabric.pc: remove PSM/EFA libs that aren't installed
# (Ubuntu advertises PSM providers in static libs but doesn't ship them)
MULTIARCH=$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null)
if [ -f "/usr/lib/${MULTIARCH}/pkgconfig/libfabric.pc" ]; then
    sed -i 's/-lpsm_infinipath//g; s/-lpsm2//g; s/-lefa//g' \
        "/usr/lib/${MULTIARCH}/pkgconfig/libfabric.pc"
fi

exec "$@"
