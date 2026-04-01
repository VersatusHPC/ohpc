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

# Save positional parameters — Intel oneAPI vars.sh clobbers $@
_SAVED_ARGS=("$@")

export MODULEPATH=/opt/ohpc/pub/modulefiles
. /opt/ohpc/admin/lmod/lmod/init/bash

# For Intel compilers: source oneAPI environment first
if [ "$COMPILER_FAMILY" = "intel" ]; then
    [ -f /opt/intel/oneapi/compiler/latest/env/vars.sh ] && . /opt/intel/oneapi/compiler/latest/env/vars.sh 2>/dev/null
    [ -f /opt/intel/oneapi/mkl/latest/env/vars.sh ] && . /opt/intel/oneapi/mkl/latest/env/vars.sh 2>/dev/null
    # Ensure Intel Fortran runtime libs are findable by the linker
    INTEL_LIB="/opt/intel/oneapi/compiler/latest/lib"
    export LIBRARY_PATH="${INTEL_LIB}:${LIBRARY_PATH}"
    export LD_LIBRARY_PATH="${INTEL_LIB}:${LD_LIBRARY_PATH}"
fi

. /opt/ohpc/admin/ohpc/OHPC_setup_compiler "$COMPILER_FAMILY"

# Load MPI module (sets MPI_DIR, adds to PATH/LD_LIBRARY_PATH)
module load "$MPI_FAMILY"

# Ensure MPI library is findable at compile and link time
if [ -n "$MPI_DIR" ]; then
    export LIBRARY_PATH="${MPI_DIR}/lib:${LIBRARY_PATH}"
    export LD_LIBRARY_PATH="${MPI_DIR}/lib:${LD_LIBRARY_PATH}"
    export CPATH="${MPI_DIR}/include:${CPATH}"
    # Add MPI and its deps to compiler search paths (only if they exist)
    _OHPC_EXTRA_L="-L${MPI_DIR}/lib"
    for _d in /opt/ohpc/pub/mpi/ucx/1.20.0/lib /opt/ohpc/pub/libs/hwloc/lib /opt/ohpc/admin/pmix/lib; do
        [ -d "$_d" ] && _OHPC_EXTRA_L="$_OHPC_EXTRA_L -L$_d"
    done
    export LDFLAGS="${LDFLAGS} ${_OHPC_EXTRA_L}"
    export CPPFLAGS="${CPPFLAGS} -I${MPI_DIR}/include"
    # Also set CFLAGS/CXXFLAGS include path for configure header checks
    export CFLAGS="${CFLAGS} -I${MPI_DIR}/include"
    export CXXFLAGS="${CXXFLAGS} -I${MPI_DIR}/include"
    export MPICC=mpicc
    export MPICXX=mpicxx
    export MPIF90=mpif90
    export MPIFC=mpif90
else
    echo "WARNING: MPI_DIR not set after loading $MPI_FAMILY"
    echo "MODULEPATH=$MODULEPATH"
    module avail 2>&1 | head -5
fi

# For Intel MPI: source oneAPI environment and ensure paths are available
if [ "$MPI_FAMILY" = "impi" ]; then
    # Source Intel MPI environment (sets I_MPI_ROOT, fixes mpicc wrapper)
    if [ -f /opt/intel/oneapi/mpi/latest/env/vars.sh ]; then
        . /opt/intel/oneapi/mpi/latest/env/vars.sh 2>/dev/null
    fi
fi

# Restore positional parameters
set -- "${_SAVED_ARGS[@]}"
if [ "$MPI_FAMILY" = "impi" ] && [ -n "$MPI_DIR" ]; then
    export LD_LIBRARY_PATH="${MPI_DIR}/lib:${LD_LIBRARY_PATH}"
    export LIBRARY_PATH="${MPI_DIR}/lib:${LIBRARY_PATH}"
    export LDFLAGS="${LDFLAGS} -L${MPI_DIR}/lib"
    export CPPFLAGS="${CPPFLAGS} -I${MPI_DIR}/include"
    export MPI_HOME="${MPI_DIR}"
    export CMAKE_PREFIX_PATH="${MPI_DIR}:${CMAKE_PREFIX_PATH}"
    if [ "$COMPILER_FAMILY" = "intel" ]; then
        export I_MPI_CC=icx
        export I_MPI_CXX=icpx
        export I_MPI_F90=ifx
        export I_MPI_FC=ifx
    else
        export I_MPI_CC=gcc
        export I_MPI_CXX=g++
        export I_MPI_F90=gfortran
        export I_MPI_FC=gfortran
    fi
fi

# Load any additional modules requested
if [ -n "$OHPC_MODULES" ]; then
    for mod in $OHPC_MODULES; do
        module load "$mod"
    done
fi

exec "$@"
