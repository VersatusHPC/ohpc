#!/bin/bash
# OpenHPC Debian package builder
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
# Usage: misc/build_deb.sh <component-path> [compiler_family] [mpi_family] [options]
#
# Examples:
#   misc/build_deb.sh components/admin/ohpc-filesystem
#   misc/build_deb.sh components/serial-libs/openblas gnu15
#   misc/build_deb.sh components/parallel-libs/fftw gnu15 openmpi5
#   misc/build_deb.sh components/admin/lmod --source-only
#
# Environment variables:
#   OHPC_REPO_DIR   - Path to local APT repo (default: devel/apt-repo)
#   OHPC_BUILD_DIR  - Working directory for builds (default: /tmp/ohpc-build)
#   OHPC_CONTAINER  - Container image to use (default: ohpc-build-ubuntu:noble)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source shared variables
source "${REPO_ROOT}/components/OHPC_vars.sh"

# Defaults
OHPC_REPO_DIR="${OHPC_REPO_DIR:-${REPO_ROOT}/devel/apt-repo}"
OHPC_BUILD_DIR="${OHPC_BUILD_DIR:-/tmp/ohpc-build}"
OHPC_CONTAINER="${OHPC_CONTAINER:-ohpc-build-ubuntu:noble}"

# Parse arguments
COMPONENT_DIR=""
SOURCE_ONLY=0
POSITIONAL=()

usage() {
    echo "Usage: $0 <component-path> [compiler_family] [mpi_family] [--source-only]"
    echo ""
    echo "Arguments:"
    echo "  component-path   Path to component (e.g., components/admin/lmod)"
    echo "  compiler_family  Compiler family (default: gnu15)"
    echo "  mpi_family       MPI family (default: openmpi5)"
    echo ""
    echo "Options:"
    echo "  --source-only    Build source package only (no binary)"
    echo "  --no-container   Build directly on host (not in container)"
    echo "  --help           Show this help"
    exit 1
}

NO_CONTAINER=0

for arg in "$@"; do
    case "$arg" in
        --source-only) SOURCE_ONLY=1 ;;
        --no-container) NO_CONTAINER=1 ;;
        --help|-h) usage ;;
        -*)
            echo "Unknown option: $arg"
            usage
            ;;
        *)
            POSITIONAL+=("$arg")
            ;;
    esac
done

if [ "${#POSITIONAL[@]}" -gt 3 ]; then
    echo "Error: too many positional arguments"
    usage
fi

COMPONENT_DIR="${POSITIONAL[0]:-}"
if [ "${#POSITIONAL[@]}" -ge 2 ]; then
    export COMPILER_FAMILY="${POSITIONAL[1]}"
fi
if [ "${#POSITIONAL[@]}" -ge 3 ]; then
    export MPI_FAMILY="${POSITIONAL[2]}"
fi

if [ -z "$COMPONENT_DIR" ]; then
    echo "Error: component path is required"
    usage
fi

# Resolve to absolute path
COMPONENT_DIR="$(cd "${REPO_ROOT}/${COMPONENT_DIR}" 2>/dev/null && pwd)" || {
    echo "Error: component directory not found: ${COMPONENT_DIR}"
    exit 1
}

# Check for debian/ directory
if [ ! -d "${COMPONENT_DIR}/debian" ]; then
    echo "Error: no debian/ directory in ${COMPONENT_DIR}"
    echo "Create the debian/ packaging directory first."
    exit 1
fi

# Get package info from debian/changelog
PKG_NAME=$(head -1 "${COMPONENT_DIR}/debian/changelog" | awk '{print $1}')
PKG_VERSION=$(head -1 "${COMPONENT_DIR}/debian/changelog" | sed 's/.*(\(.*\)).*/\1/')
echo "=== Building ${PKG_NAME} ${PKG_VERSION} ==="
echo "    Compiler: ${COMPILER_FAMILY}"
echo "    MPI:      ${MPI_FAMILY}"

# Process control.in template if it exists
if [ -f "${COMPONENT_DIR}/debian/control.in" ]; then
    echo "    Processing control.in template..."
    sed \
        -e "s/@COMPILER_FAMILY@/${COMPILER_FAMILY}/g" \
        -e "s/@MPI_FAMILY@/${MPI_FAMILY}/g" \
        -e "s/@PROJ_DELIM@/${PROJ_DELIM}/g" \
        -e "s/@COMPILER_DEP@/$(compiler_dep_pkg)/g" \
        -e "s/@MPI_DEP@/$(mpi_dep_pkg)/g" \
        "${COMPONENT_DIR}/debian/control.in" > "${COMPONENT_DIR}/debian/control"
fi

if [ "$NO_CONTAINER" = "1" ]; then
    # Build directly on host
    echo "    Building on host (no container)..."
    cd "${COMPONENT_DIR}"

    if [ "$SOURCE_ONLY" = "1" ]; then
        dpkg-buildpackage -S -nc -d -us -uc
    else
        dpkg-buildpackage -b -nc -d -us -uc
    fi

    echo "=== Build complete ==="
    echo "    Packages in: $(dirname "${COMPONENT_DIR}")"
    ls -la "$(dirname "${COMPONENT_DIR}")"/*.deb 2>/dev/null || true
else
    # Build inside container
    echo "    Building in container ${OHPC_CONTAINER}..."

    # Determine the relative path within the repo
    REL_PATH="${COMPONENT_DIR#${REPO_ROOT}/}"

    BUILD_CMD="cd /build/${REL_PATH}"

    # Add local repo if it exists
    if [ -d "${OHPC_REPO_DIR}/pool" ]; then
        BUILD_CMD="echo 'deb [trusted=yes] file:///opt/ohpc-repo noble main' > /etc/apt/sources.list.d/ohpc.list && apt-get update -qq && ${BUILD_CMD}"
    fi

    # Export compiler/MPI family
    BUILD_CMD="${BUILD_CMD} && export COMPILER_FAMILY=${COMPILER_FAMILY} && export MPI_FAMILY=${MPI_FAMILY}"

    if [ "$SOURCE_ONLY" = "1" ]; then
        BUILD_CMD="${BUILD_CMD} && dpkg-buildpackage -S -nc -d -us -uc"
    else
        BUILD_CMD="${BUILD_CMD} && dpkg-buildpackage -b -nc -d -us -uc"
    fi

    podman run --rm \
        -v "${REPO_ROOT}:/build:Z" \
        -v "${OHPC_REPO_DIR}:/opt/ohpc-repo:Z" \
        -e COMPILER_FAMILY="${COMPILER_FAMILY}" \
        -e MPI_FAMILY="${MPI_FAMILY}" \
        "${OHPC_CONTAINER}" \
        bash -c "${BUILD_CMD}" 2>&1

    echo ""
    echo "=== Build complete ==="
    # Show output .deb files
    PARENT_DIR="$(dirname "${REL_PATH}")"
    ls -la "${REPO_ROOT}/${PARENT_DIR}"/*.deb 2>/dev/null || echo "    (no .deb files found in ${PARENT_DIR})"
fi
