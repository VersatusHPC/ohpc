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

# For Intel compilers: source oneAPI environment
# (Intel oneAPI is installed via apt by intel-compilers-devel-ohpc postinst
# which uses /etc/apt/sources.list.d/oneAPI.list pointing to Intel's APT repo.)
if [ "$COMPILER_FAMILY" = "intel" ]; then
    [ -f /opt/intel/oneapi/compiler/latest/env/vars.sh ] && . /opt/intel/oneapi/compiler/latest/env/vars.sh 2>/dev/null
    [ -f /opt/intel/oneapi/mkl/latest/env/vars.sh ] && . /opt/intel/oneapi/mkl/latest/env/vars.sh 2>/dev/null
fi

. /opt/ohpc/admin/ohpc/OHPC_setup_compiler "$COMPILER_FAMILY"

setup_debian_multiarch_paths() {
    local multiarch dir
    multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || true)"
    [ -n "$multiarch" ] || return 0

    for dir in "/usr/lib/${multiarch}" "/lib/${multiarch}"; do
        [ -d "$dir" ] || continue
        export LIBRARY_PATH="${dir}${LIBRARY_PATH:+:${LIBRARY_PATH}}"
        export LD_LIBRARY_PATH="${dir}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
        export LDFLAGS="-L${dir} ${LDFLAGS:-}"
    done

    if [ -d "/usr/include/${multiarch}" ]; then
        export CPATH="/usr/include/${multiarch}${CPATH:+:${CPATH}}"
        export CPPFLAGS="-I/usr/include/${multiarch} ${CPPFLAGS:-}"
    fi
    if [ -d "/usr/lib/${multiarch}/pkgconfig" ]; then
        export PKG_CONFIG_PATH="/usr/lib/${multiarch}/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
    fi
}

setup_debian_multiarch_paths

# Restore positional parameters
set -- "${_SAVED_ARGS[@]}"

# Load any additional modules requested
if [ -n "$OHPC_MODULES" ]; then
    for mod in $OHPC_MODULES; do
        module load "$mod"
    done
fi

exec "$@"
