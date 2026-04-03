#!/bin/bash
# OpenHPC ppc64le Auto-Build System
# Detects upstream changes, rebuilds affected packages, updates RPM repo
#
# Usage: ./ppc64le-autobuild.sh [--dry-run] [--force-all] [--package PKG]
#
# Run via cron: 0 */6 * * * /home/ferrao/ohpc-ppc64le-support/misc/ppc64le-autobuild.sh >> /var/log/ohpc-autobuild.log 2>&1

set -euo pipefail

# Configuration
WORKTREE="/home/ferrao/ohpc-ppc64le-support"
REPO_DIR="/home/ferrao/ohpc-repo/EL10/ppc64le"
LOG_DIR="/var/log/ohpc-autobuild"
UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="4.x"
LOCAL_BRANCH="ppc64le-support"
COMPILER_FAMILY="gnu15"
MPI_FAMILY="openmpi5"
BUILD_SCRIPT="/tmp/build_ohpc_bb.sh"

# Packages to skip (architecture-locked or known broken)
SKIP_PACKAGES="intel-compilers-devel impi-devel cuda-devel arm-compilers-devel msr-safe lustre-client"

# Initialize
DRY_RUN=false
FORCE_ALL=false
SINGLE_PKG=""
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run) DRY_RUN=true; shift ;;
        --force-all) FORCE_ALL=true; shift ;;
        --package) SINGLE_PKG="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_DIR/build-$TIMESTAMP.log") 2>&1

echo "=========================================="
echo "OpenHPC ppc64le Auto-Build — $TIMESTAMP"
echo "=========================================="

cd "$WORKTREE"

# Step 1: Set up upstream remote if not exists
if ! git remote get-url "$UPSTREAM_REMOTE" &>/dev/null; then
    echo "Adding upstream remote..."
    git remote add "$UPSTREAM_REMOTE" https://github.com/openhpc/ohpc.git
fi

# Step 2: Fetch upstream changes
echo "Fetching upstream..."
git fetch "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH" 2>&1

# Step 3: Detect changed spec files
if $FORCE_ALL; then
    echo "Force-all: rebuilding all packages"
    CHANGED_SPECS=$(find components -name "*.spec" -type f | sort)
elif [ -n "$SINGLE_PKG" ]; then
    CHANGED_SPECS=$(find components -path "*/$SINGLE_PKG/SPECS/*.spec" -type f)
    echo "Single package: $CHANGED_SPECS"
else
    # Find specs changed between our branch and upstream
    CHANGED_SPECS=$(git diff --name-only "$LOCAL_BRANCH...$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" -- 'components/*/SPECS/*.spec' 'components/*/*/SPECS/*.spec' 2>/dev/null || true)

    if [ -z "$CHANGED_SPECS" ]; then
        echo "No spec file changes detected from upstream."
        echo "Checking for local uncommitted changes..."
        CHANGED_SPECS=$(git diff --name-only -- 'components/*/SPECS/*.spec' 'components/*/*/SPECS/*.spec' 2>/dev/null || true)
    fi

    if [ -z "$CHANGED_SPECS" ]; then
        echo "Nothing to build. Exiting."
        exit 0
    fi
fi

echo ""
echo "=== Specs to process ==="
echo "$CHANGED_SPECS"
echo ""

# Step 4: Merge upstream changes (if any)
if ! $DRY_RUN && ! $FORCE_ALL && [ -z "$SINGLE_PKG" ]; then
    echo "Merging upstream changes..."
    git merge "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" --no-edit 2>&1 || {
        echo "WARNING: Merge conflict detected. Manual resolution needed."
        git merge --abort 2>/dev/null
    }
fi

# Step 5: Set up build environment
export MODULEPATH=/opt/ohpc/pub/modulefiles:/opt/ohpc/admin/modulefiles
export BASH_ENV=/opt/ohpc/admin/lmod/lmod/init/bash
source /opt/ohpc/admin/lmod/lmod/init/bash 2>/dev/null || true

# Step 6: Build each changed package
BUILT=0
FAILED=0
SKIPPED=0

for spec in $CHANGED_SPECS; do
    [ -f "$spec" ] || continue

    pkg_name=$(basename "$spec" .spec)
    pkg_dir=$(dirname "$spec" | sed 's|/SPECS||')

    # Check skip list
    skip=false
    for s in $SKIP_PACKAGES; do
        if echo "$pkg_dir" | grep -q "$s"; then
            echo "SKIP: $pkg_name (in skip list)"
            ((SKIPPED++))
            skip=true
            break
        fi
    done
    $skip && continue

    # Check architecture restrictions
    buildarch=$(grep '^BuildArch:' "$spec" 2>/dev/null | head -1 | awk '{print $2}')
    if [ "$buildarch" = "x86_64" ] || [ "$buildarch" = "aarch64" ]; then
        echo "SKIP: $pkg_name (BuildArch: $buildarch)"
        ((SKIPPED++))
        continue
    fi

    # Determine compiler/MPI family
    is_comp=$(grep -c 'ohpc_compiler_dependent.*1' "$spec" 2>/dev/null || true)
    is_mpi=$(grep -c 'ohpc_mpi_dependent.*1' "$spec" 2>/dev/null || true)

    comp="$COMPILER_FAMILY"
    mpi="$MPI_FAMILY"

    echo ""
    echo "--- Building: $pkg_name (comp=$is_comp, mpi=$is_mpi) ---"

    if $DRY_RUN; then
        echo "DRY-RUN: would build $spec"
        continue
    fi

    # Ensure sources exist
    source_dir="$pkg_dir/SOURCES"
    if [ ! -d "$source_dir" ]; then
        mkdir -p "$source_dir"
    fi
    if [ ! -e "$source_dir/OHPC_macros" ]; then
        ln -sf "$WORKTREE/components/OHPC_macros" "$source_dir/OHPC_macros" 2>/dev/null
    fi

    # Build the package
    if $BUILD_SCRIPT "$spec" "$comp" "$mpi" 2>&1 | tee "$LOG_DIR/pkg-$pkg_name-$TIMESTAMP.log" | tail -3; then
        echo "SUCCESS: $pkg_name"
        ((BUILT++))
    else
        echo "FAILED: $pkg_name (see $LOG_DIR/pkg-$pkg_name-$TIMESTAMP.log)"
        ((FAILED++))
    fi
done

# Step 7: Update RPM repository
echo ""
echo "=== Updating RPM repository ==="
cp ~/rpmbuild/RPMS/ppc64le/*.rpm "$REPO_DIR/" 2>/dev/null
cp ~/rpmbuild/RPMS/noarch/*.rpm "$REPO_DIR/" 2>/dev/null

# Remove bad-named RPMs (-.elN pattern)
rm -f "$REPO_DIR"/*-.el*

createrepo_c --update "$REPO_DIR" 2>&1

# Step 8: Summary
echo ""
echo "=========================================="
echo "  Build Summary — $TIMESTAMP"
echo "=========================================="
echo "  Built:   $BUILT"
echo "  Failed:  $FAILED"
echo "  Skipped: $SKIPPED"
echo "  Total RPMs: $(ls $REPO_DIR/*.rpm 2>/dev/null | wc -l)"
echo "=========================================="
