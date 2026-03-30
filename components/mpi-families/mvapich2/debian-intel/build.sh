#!/bin/bash
# Helper script for building MVAPICH2 within debian/rules.
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

# Load dependency modules
module load hwloc

exec "$@"
