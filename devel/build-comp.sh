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

export MODULEPATH=/opt/ohpc/pub/modulefiles
. /opt/ohpc/admin/lmod/lmod/init/bash
. /opt/ohpc/admin/ohpc/OHPC_setup_compiler "$COMPILER_FAMILY"

# Load any additional modules requested
if [ -n "$OHPC_MODULES" ]; then
    for mod in $OHPC_MODULES; do
        module load "$mod"
    done
fi

exec "$@"
