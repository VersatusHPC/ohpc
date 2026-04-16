#!/bin/bash
# Convert all OpenHPC packages to proper Debian source format (.dsc + .tar.gz)
# and upload them to the OBS backend.
#
# Usage: bash obs/convert-to-dsc.sh [http://localhost:5352] [path-substring-filter]
set -e

OBS_SRC="${1:-http://localhost:5352}"
PATH_FILTER="${2:-}"
PROJECT="VersatusHPC:OHPC:4"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="/tmp/obs-dsc-import"
COUNT=0
ERRORS=0

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

obs_request() {
    local description="$1"
    shift

    if ! curl -fsS "$@" >/dev/null; then
        echo ""
        echo "ERROR: $description" >&2
        return 1
    fi
}

convert_and_upload() {
    local comp_dir="$1"
    local debian_dir="$2"

    # Get package name and version from debian/control and debian/changelog
    local pkg_name
    pkg_name=$(grep "^Source:" "$comp_dir/$debian_dir/control" 2>/dev/null | awk '{print $2}')
    [ -z "$pkg_name" ] && return

    local version
    version=$(head -1 "$comp_dir/$debian_dir/changelog" 2>/dev/null | sed 's/.*(\(.*\)).*/\1/')
    [ -z "$version" ] && return

    local arch
    arch=$(grep "^Architecture:" "$comp_dir/$debian_dir/control" 2>/dev/null | head -1 | awk '{print $2}')
    [ -z "$arch" ] && arch="any"

    local build_deps
    # Parse multiline Build-Depends (continuation lines start with whitespace)
    build_deps=$(sed -n '/^Build-Depends:/,/^[^ ]/{ /^Build-Depends:/s/^Build-Depends: //p; /^ /p; }' \
        "$comp_dir/$debian_dir/control" 2>/dev/null | tr '\n' ' ' | sed 's/  */ /g; s/ $//')
    [ -z "$build_deps" ] && build_deps="debhelper-compat (= 13)"

    local maintainer
    maintainer=$(grep "^Maintainer:" "$comp_dir/$debian_dir/control" 2>/dev/null | sed 's/^Maintainer: //')
    [ -z "$maintainer" ] && maintainer="VersatusHPC <packages@versatushpc.org>"

    local pkgdir="$WORKDIR/$pkg_name"
    rm -rf "$pkgdir"
    mkdir -p "$pkgdir/${pkg_name}-${version}/debian"

    # Copy debian files
    cp -a "$comp_dir/$debian_dir"/* "$pkgdir/${pkg_name}-${version}/debian/"

    # Copy SOURCES if they exist (dereference symlinks with -L)
    if [ -d "$comp_dir/SOURCES" ]; then
        cp -aL "$comp_dir/SOURCES" "$pkgdir/${pkg_name}-${version}/"
    fi

    # Copy devel/ helper scripts and fix absolute /build/ paths in rules
    mkdir -p "$pkgdir/${pkg_name}-${version}/devel"
    cp "$REPO_ROOT/devel/build-comp.sh" "$pkgdir/${pkg_name}-${version}/devel/" 2>/dev/null || true
    cp "$REPO_ROOT/devel/build-mpi.sh" "$pkgdir/${pkg_name}-${version}/devel/" 2>/dev/null || true
    # OBS builds from /usr/src/packages/BUILD/ — use absolute path to devel/
    sed -i 's|/build/devel/|/usr/src/packages/BUILD/devel/|g' "$pkgdir/${pkg_name}-${version}/debian/rules" 2>/dev/null || true
    # Ensure COMPILER_FAMILY and MPI_FAMILY are exported to the environment
    # (OBS doesn't pass them as env vars like our container builds do)
    sed -i 's/^COMPILER_FAMILY\b/export COMPILER_FAMILY/' "$pkgdir/${pkg_name}-${version}/debian/rules" 2>/dev/null || true
    sed -i 's/^MPI_FAMILY\b/export MPI_FAMILY/' "$pkgdir/${pkg_name}-${version}/debian/rules" 2>/dev/null || true

    # Create the source tarball
    cd "$pkgdir"
    tar czf "${pkg_name}_${version}.tar.gz" "${pkg_name}-${version}/" 2>/dev/null

    # Create .dsc file
    local tarball_md5 tarball_size
    tarball_md5=$(md5sum "${pkg_name}_${version}.tar.gz" | awk '{print $1}')
    tarball_size=$(stat -c %s "${pkg_name}_${version}.tar.gz")

    cat > "${pkg_name}_${version}.dsc" << EOF
Format: 3.0 (native)
Source: $pkg_name
Binary: $pkg_name
Architecture: $arch
Version: $version
Maintainer: $maintainer
Build-Depends: $build_deps
Files:
 $tarball_md5 $tarball_size ${pkg_name}_${version}.tar.gz
EOF

    # Ensure OBS package exists
    obs_request "creating package metadata for $pkg_name" \
        -X PUT "$OBS_SRC/source/$PROJECT/$pkg_name/_meta" \
        -d "<package name=\"$pkg_name\" project=\"$PROJECT\"><title>$pkg_name</title></package>" || return 1

    # Delete old flat files
    local old_files
    old_files=$(curl -fsS "$OBS_SRC/source/$PROJECT/$pkg_name" | \
        grep 'entry name=' | sed 's/.*name="\([^"]*\)".*/\1/') || return 1
    for f in $old_files; do
        obs_request "deleting stale source file $pkg_name/$f" \
            -X DELETE "$OBS_SRC/source/$PROJECT/$pkg_name/$f" || return 1
    done

    # Upload .dsc and .tar.gz
    obs_request "uploading ${pkg_name}_${version}.dsc" \
        -X PUT "$OBS_SRC/source/$PROJECT/$pkg_name/${pkg_name}_${version}.dsc" \
        --data-binary "@${pkg_name}_${version}.dsc" || return 1

    obs_request "uploading ${pkg_name}_${version}.tar.gz" \
        -X PUT "$OBS_SRC/source/$PROJECT/$pkg_name/${pkg_name}_${version}.tar.gz" \
        --data-binary "@${pkg_name}_${version}.tar.gz" || return 1

    COUNT=$((COUNT + 1))
    printf "\r  [%3d] %-50s" "$COUNT" "$pkg_name"

    cd "$REPO_ROOT"
}

echo "=== Converting and uploading packages to $PROJECT ==="
echo "    Backend: $OBS_SRC"
if [ -n "$PATH_FILTER" ]; then
    echo "    Filter:  $PATH_FILTER"
fi
echo ""

for debian_path in $(find "$REPO_ROOT/components" -maxdepth 3 -type d \
    \( -name "debian" -o -name "debian-*" \) -not -path "*/debian/*" \
    -not -path "*/open-build-service/*" \
    -not -path "*/.debhelper/*" | sort); do

    if [ -n "$PATH_FILTER" ] && [[ "$debian_path" != *"$PATH_FILTER"* ]]; then
        continue
    fi

    parent=$(dirname "$debian_path")
    variant=$(basename "$debian_path")

    # Skip if no control file
    [ -f "$parent/$variant/control" ] || continue

    convert_and_upload "$parent" "$variant" || ERRORS=$((ERRORS + 1))
done

echo ""
echo ""
echo "=== Complete: $COUNT packages converted and uploaded ($ERRORS errors) ==="

# Cleanup
rm -rf "$WORKDIR"
