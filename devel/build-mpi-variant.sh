#!/bin/bash
# Build an MPI-dependent package for a specific MPI family.
# Temporarily modifies the debian/ dir, builds, then restores.
#
# Usage: devel/build-mpi-variant.sh <component-path> <mpi_family>
# Example: devel/build-mpi-variant.sh components/parallel-libs/fftw mpich
#
# Requires: the component must have a debian/ dir for openmpi5 already.
set -e

COMP_DIR="$1"
MPI_FAMILY="$2"
OLD_MPI="openmpi5"

if [ -z "$COMP_DIR" ] || [ -z "$MPI_FAMILY" ]; then
    echo "Usage: $0 <component-path> <mpi_family>"
    exit 1
fi

if [ ! -d "$COMP_DIR/debian" ]; then
    echo "Error: $COMP_DIR/debian not found"
    exit 1
fi

echo "=== Building $COMP_DIR with MPI_FAMILY=$MPI_FAMILY ==="

# Backup original debian/
cp -a "$COMP_DIR/debian" "$COMP_DIR/debian.bak"

# Replace openmpi5 with the target MPI family in all debian files
find "$COMP_DIR/debian" -type f | while read f; do
    sed -i "s/${OLD_MPI}/${MPI_FAMILY}/g" "$f"
done

# Build
cd "$COMP_DIR"
dpkg-buildpackage -b -nc -d -us -uc 2>&1 | tail -3

# Restore original debian/
rm -rf "$COMP_DIR/debian"
mv "$COMP_DIR/debian.bak" "$COMP_DIR/debian"

echo "=== Done ==="
