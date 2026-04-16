#!/bin/bash
# Generate Intel compiler variant debian/ directories.
# For compiler-dep: debian-intel/
# For MPI-dep: debian-intel-{mpi}/
#
# Usage:
#   devel/gen-intel-variant.sh <component-path>             # compiler-dep only
#   devel/gen-intel-variant.sh <component-path> <mpi>       # MPI-dep
set -e

COMP_DIR="$1"
MPI="$2"  # empty for compiler-dep, or openmpi5/mpich/mvapich2/impi

if [ -z "$COMP_DIR" ]; then
    echo "Usage: $0 <component-path> [mpi_family]"
    exit 1
fi

if [ -z "$MPI" ]; then
    # Compiler-dep only
    TARGET="$COMP_DIR/debian-intel"
    SOURCE="$COMP_DIR/debian"
else
    # MPI-dep
    TARGET="$COMP_DIR/debian-intel-${MPI}"
    if [ -d "$COMP_DIR/debian-${MPI}" ]; then
        SOURCE="$COMP_DIR/debian-${MPI}"
    else
        SOURCE="$COMP_DIR/debian"
    fi
fi

if [ ! -d "$SOURCE" ]; then
    echo "Error: $SOURCE not found"
    exit 1
fi

if [ -d "$TARGET" ]; then
    echo "  Skip: $TARGET exists"
    exit 0
fi

echo "  Creating $TARGET from $SOURCE..."
cp -a "$SOURCE" "$TARGET"

# Replace gnu15 with intel in all files
find "$TARGET" -type f -exec sed -i \
    -e "s/gnu15/intel/g" \
    -e "s/GNU15/INTEL/g" \
    {} \;

# Fix the compiler dependency: intel-compilers needs different name
# gnu15-compilers-ohpc -> intel-compilers-devel-ohpc
find "$TARGET" -type f -exec sed -i \
    -e "s/intel-compilers-ohpc (>= 14.1.0)/intel-compilers-devel-ohpc/g" \
    -e "s/intel-compilers-ohpc/intel-compilers-devel-ohpc/g" \
    {} \;

# Fix MPI dep names for impi
if [ "$MPI" = "impi" ]; then
    find "$TARGET" -type f -exec sed -i \
        -e "s/impi-intel-ohpc/intel-mpi-devel-ohpc/g" \
        {} \;
fi

# Add export COMPILER_FAMILY if not there
if ! grep -q "^export COMPILER_FAMILY" "$TARGET/rules" 2>/dev/null; then
    sed -i "/^COMPILER_FAMILY/a export COMPILER_FAMILY" "$TARGET/rules" 2>/dev/null
fi

# build-comp.sh reads COMPILER_FAMILY from env
# build-mpi.sh reads both COMPILER_FAMILY and MPI_FAMILY
