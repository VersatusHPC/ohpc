#!/bin/bash
# Common helper for compiler-dependent OHPC package builds.
# Sources OHPC_setup_compiler to activate the OHPC GCC and set
# CC, CXX, FC, CFLAGS, CXXFLAGS, FCFLAGS.
#
# Usage in debian/rules:
#   ENV := bash /build/devel/build-comp.sh
#   override_dh_auto_configure:
#       cd $(SRCDIR) && $(ENV) ./configure ...
#
# Optional: load additional modules by setting OHPC_MODULES env var
#   ENV := OHPC_MODULES="openblas ucx" bash /build/devel/build-comp.sh
set -e

COMPILER_FAMILY="${COMPILER_FAMILY:-gnu15}"

# Save positional parameters — Intel oneAPI vars.sh clobbers $@
_SAVED_ARGS=("$@")

export MODULEPATH=/opt/ohpc/pub/modulefiles
. /opt/ohpc/admin/lmod/lmod/init/bash

# For Intel compilers: install arch:all packages if missing, then source oneAPI
if [ "$COMPILER_FAMILY" = "intel" ]; then
    if [ ! -f /opt/intel/oneapi/setvars.sh ]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if ls "$SCRIPT_DIR"/intel-oneapi-*_all.deb 1>/dev/null 2>&1; then
            echo "Installing Intel oneAPI arch:all packages..."
            dpkg -i "$SCRIPT_DIR"/intel-oneapi-*_all.deb 2>/dev/null || true
        fi
    fi
    [ -f /opt/intel/oneapi/compiler/latest/env/vars.sh ] && . /opt/intel/oneapi/compiler/latest/env/vars.sh 2>/dev/null
    [ -f /opt/intel/oneapi/mkl/latest/env/vars.sh ] && . /opt/intel/oneapi/mkl/latest/env/vars.sh 2>/dev/null
fi

. /opt/ohpc/admin/ohpc/OHPC_setup_compiler "$COMPILER_FAMILY"

# Restore positional parameters
set -- "${_SAVED_ARGS[@]}"

# Load any additional modules requested
if [ -n "$OHPC_MODULES" ]; then
    for mod in $OHPC_MODULES; do
        module load "$mod"
    done
fi

exec "$@"
