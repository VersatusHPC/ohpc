#!/bin/bash
# Helper script for building OpenMPI within debian/rules.
# Sets up compiler and loads dependency modules, matching the EL RPM build.
# Usage: debian/build.sh <command> [args...]
set -e

COMPILER_FAMILY="${COMPILER_FAMILY:-gnu15}"

export MODULEPATH=/opt/ohpc/pub/modulefiles
. /opt/ohpc/admin/lmod/lmod/init/bash
. /opt/ohpc/admin/ohpc/OHPC_setup_compiler "$COMPILER_FAMILY"

# Load dependency modules (sets HWLOC_DIR, UCX_DIR, PMIX_DIR, etc.)
module load hwloc
module load ucx
module load pmix

exec "$@"
