#!/bin/bash
# Common helper for compiler+MPI-dependent OHPC package builds.
# Sources OHPC_setup_compiler, loads the MPI module, and optionally
# loads additional dependency modules.
#
# Usage in debian/rules:
#   ENV := bash /build/devel/build-mpi.sh
#   ENV := OHPC_MODULES="openblas" bash /build/devel/build-mpi.sh
set -e

COMPILER_FAMILY="${COMPILER_FAMILY:-gnu15}"
MPI_FAMILY="${MPI_FAMILY:-openmpi5}"

export MODULEPATH=/opt/ohpc/pub/modulefiles
. /opt/ohpc/admin/lmod/lmod/init/bash
. /opt/ohpc/admin/ohpc/OHPC_setup_compiler "$COMPILER_FAMILY"

# Load MPI module (sets MPI_DIR, adds to PATH/LD_LIBRARY_PATH)
module load "$MPI_FAMILY"

# Load any additional modules requested
if [ -n "$OHPC_MODULES" ]; then
    for mod in $OHPC_MODULES; do
        module load "$mod"
    done
fi

exec "$@"
