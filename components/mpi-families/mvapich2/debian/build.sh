#!/bin/bash
# Helper script for building MVAPICH2 within debian/rules.
# Sets up compiler environment, matching the EL RPM build.
# Usage: debian/build.sh <command> [args...]
set -e

COMPILER_FAMILY="${COMPILER_FAMILY:-gnu15}"

export MODULEPATH=/opt/ohpc/pub/modulefiles
. /opt/ohpc/admin/lmod/lmod/init/bash
. /opt/ohpc/admin/ohpc/OHPC_setup_compiler "$COMPILER_FAMILY"

# Load dependency modules
module load hwloc

exec "$@"
