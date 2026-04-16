#!/bin/bash
# OpenHPC shared variables for shell scripts (Debian packaging)
#
#-----------------------------------------------------------------------
# Licensed under the Apache License, Version 2.0 (the "License"); you
# may not use this file except in compliance with the License. You may
# obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied. See the License for the specific language governing
# permissions and limitations under the License.
#-----------------------------------------------------------------------
#
# This file is the shell equivalent of OHPC_vars.mk. Source it in
# build scripts:
#
#   source components/OHPC_vars.sh

# Top-level OpenHPC installation paths
export PROJ_NAME="ohpc"
export OHPC_HOME="/opt/${PROJ_NAME}"
export OHPC_ADMIN="${OHPC_HOME}/admin"
export OHPC_PUB="${OHPC_HOME}/pub"
export OHPC_APPS="${OHPC_PUB}/apps"
export OHPC_BIN="${OHPC_PUB}/bin"
export OHPC_COMPILERS="${OHPC_PUB}/compiler"
export OHPC_LIBS="${OHPC_PUB}/libs"
export OHPC_MODULES="${OHPC_PUB}/modulefiles"
export OHPC_MODULEDEPS="${OHPC_PUB}/moduledeps"
export OHPC_MPI_STACKS="${OHPC_PUB}/mpi"
export OHPC_UTILS="${OHPC_PUB}/utils"
export OHPC_DOCS="${OHPC_PUB}/doc/contrib"

# Package naming
export PROJ_DELIM="-ohpc"

# Default compiler/MPI/Python families (overridable via environment)
export COMPILER_FAMILY="${COMPILER_FAMILY:-gnu15}"
export MPI_FAMILY="${MPI_FAMILY:-openmpi5}"
export PYTHON_FAMILY="${PYTHON_FAMILY:-python3}"

# Lua version for Ubuntu 24.04
export LUAVER="5.4"

# Python settings
export PYTHON_PREFIX="python3"
export PYTHON_BIN="/usr/bin/python3"

# Compiler dependency resolution
compiler_dep_pkg() {
    local family="${1:-$COMPILER_FAMILY}"
    case "$family" in
        gnu15)  echo "gnu15-compilers${PROJ_DELIM}" ;;
        gnu14)  echo "gnu14-compilers${PROJ_DELIM}" ;;
        gnu13)  echo "gnu13-compilers${PROJ_DELIM}" ;;
        gnu12)  echo "gnu12-compilers${PROJ_DELIM}" ;;
        gnu9)   echo "gnu9-compilers${PROJ_DELIM}" ;;
        intel)  echo "intel-compilers-devel${PROJ_DELIM}" ;;
        arm1)   echo "arm1-compilers-devel${PROJ_DELIM}" ;;
        llvm)   echo "llvm-compilers${PROJ_DELIM}" ;;
        *)      echo "unknown-compiler-${family}" ;;
    esac
}

# MPI dependency resolution
mpi_dep_pkg() {
    local mpi="${1:-$MPI_FAMILY}"
    local compiler="${2:-$COMPILER_FAMILY}"
    case "$mpi" in
        impi)      echo "intel-mpi-devel${PROJ_DELIM}" ;;
        mpich)     echo "mpich-${compiler}${PROJ_DELIM}" ;;
        mvapich2)  echo "mvapich2-${compiler}${PROJ_DELIM}" ;;
        openmpi3)  echo "openmpi3-${compiler}${PROJ_DELIM}" ;;
        openmpi4)  echo "openmpi4-${compiler}${PROJ_DELIM}" ;;
        openmpi5)  echo "openmpi5-${compiler}${PROJ_DELIM}" ;;
        *)         echo "unknown-mpi-${mpi}" ;;
    esac
}

# Install path helpers
install_path_indep() {
    echo "${OHPC_LIBS}/${1}"
}

install_path_comp() {
    local compiler="${1}" pname="${2}" version="${3}"
    echo "${OHPC_LIBS}/${compiler}/${pname}/${version}"
}

install_path_mpi() {
    local compiler="${1}" mpi="${2}" pname="${3}" version="${4}"
    echo "${OHPC_LIBS}/${compiler}/${mpi}/${pname}/${version}"
}

# Module path helpers
module_path_indep() {
    echo "${OHPC_MODULES}/${1}"
}

module_path_comp() {
    local compiler="${1}" pname="${2}"
    echo "${OHPC_MODULEDEPS}/${compiler}/${pname}"
}

module_path_mpi() {
    local compiler="${1}" mpi="${2}" pname="${3}"
    echo "${OHPC_MODULEDEPS}/${compiler}-${mpi}/${pname}"
}

# Setup compiler environment
ohpc_setup_compiler() {
    local family="${1:-$COMPILER_FAMILY}"
    . "${OHPC_ADMIN}/ohpc/OHPC_setup_compiler" "$family"
}

# Setup MPI environment
ohpc_setup_mpi() {
    local family="${1:-$MPI_FAMILY}"
    . "${OHPC_ADMIN}/ohpc/OHPC_setup_mpi" "$family"
}

# Setup both compiler and MPI
ohpc_setup_compiler_mpi() {
    ohpc_setup_compiler "${1:-$COMPILER_FAMILY}"
    ohpc_setup_mpi "${2:-$MPI_FAMILY}"
}
