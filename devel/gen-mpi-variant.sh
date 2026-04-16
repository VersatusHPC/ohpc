#!/bin/bash
# Generate a proper debian-{mpi}/ directory for an MPI variant.
# Usage: devel/gen-mpi-variant.sh <component-path> <mpi_family>
# Example: devel/gen-mpi-variant.sh components/parallel-libs/fftw mpich
#
# Creates debian-{mpi}/ alongside the existing debian/ (openmpi5).
# The generated directory is a proper, committed, maintainable copy.

set -e

COMP_DIR="$1"
MPI="$2"

if [ -z "$COMP_DIR" ] || [ -z "$MPI" ]; then
    echo "Usage: $0 <component-path> <mpi_family>"
    exit 1
fi

if [ ! -d "$COMP_DIR/debian" ]; then
    echo "Error: $COMP_DIR/debian not found"
    exit 1
fi

TARGET="$COMP_DIR/debian-${MPI}"
if [ -d "$TARGET" ]; then
    echo "Warning: $TARGET already exists, skipping"
    exit 0
fi

echo "Generating $TARGET from $COMP_DIR/debian..."
cp -a "$COMP_DIR/debian" "$TARGET"

# Replace openmpi5 with target MPI in all files
find "$TARGET" -type f -exec sed -i "s/openmpi5/${MPI}/g" {} \;

# Add export MPI_FAMILY if not already there
if ! grep -q "^export MPI_FAMILY" "$TARGET/rules" 2>/dev/null; then
    sed -i "/^MPI_FAMILY/a export MPI_FAMILY" "$TARGET/rules" 2>/dev/null
fi

echo "  Created $TARGET"
