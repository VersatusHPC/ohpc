#!/bin/bash
# Helper script for building OpenMPI within debian/rules.
# Sets up compiler and loads dependency modules, matching the EL RPM build.
# Usage: debian/build.sh <command> [args...]
set -e

COMPILER_FAMILY="${COMPILER_FAMILY:-intel}"

# Save positional parameters — Intel oneAPI vars.sh clobbers $@
_SAVED_ARGS=("$@")

export MODULEPATH=/opt/ohpc/pub/modulefiles
# Install Intel oneAPI arch:all packages if missing
set +e
. /usr/src/packages/BUILD/devel/intel-install.sh 2>&1
set -e
. /opt/ohpc/admin/lmod/lmod/init/bash
# Source Intel oneAPI environment
[ -f /opt/intel/oneapi/compiler/latest/env/vars.sh ] && . /opt/intel/oneapi/compiler/latest/env/vars.sh 2>/dev/null
[ -f /opt/intel/oneapi/mkl/latest/env/vars.sh ] && . /opt/intel/oneapi/mkl/latest/env/vars.sh 2>/dev/null
. /opt/ohpc/admin/ohpc/OHPC_setup_compiler "$COMPILER_FAMILY"

# Restore positional parameters
set -- "${_SAVED_ARGS[@]}"

# Load dependency modules (sets HWLOC_DIR, UCX_DIR, PMIX_DIR, etc.)
module load hwloc
module load ucx
module load pmix

exec "$@"
