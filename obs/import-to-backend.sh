#!/bin/bash
# Import OpenHPC packages directly to OBS backend source server.
#
# Usage: bash obs/import-to-backend.sh [http://localhost:5352]
set -e

OBS_SRC="${1:-http://localhost:5352}"
PROJECT="VersatusHPC:OHPC:4"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COUNT=0
ERRORS=0

import_package() {
    local comp_dir="$1"
    local debian_dir="$2"
    local pkg_name

    # Get package name from debian/control
    pkg_name=$(grep "^Source:" "$comp_dir/$debian_dir/control" 2>/dev/null | awk '{print $2}')
    if [ -z "$pkg_name" ]; then
        return
    fi

    # Create OBS package
    curl -s -X PUT "$OBS_SRC/source/$PROJECT/$pkg_name/_meta" \
        -d "<package name=\"$pkg_name\" project=\"$PROJECT\"><title>$pkg_name</title></package>" \
        >/dev/null 2>&1

    # Upload each file in the debian directory
    for f in "$comp_dir/$debian_dir"/*; do
        [ -f "$f" ] || continue
        fname=$(basename "$f")
        curl -s -X PUT "$OBS_SRC/source/$PROJECT/$pkg_name/$fname" \
            --data-binary "@$f" >/dev/null 2>&1
    done

    # Upload source tarballs if they exist
    if [ -d "$comp_dir/SOURCES" ]; then
        for f in "$comp_dir/SOURCES"/*.tar.* "$comp_dir/SOURCES"/*.patch "$comp_dir/SOURCES"/*.zip; do
            [ -f "$f" ] || continue
            fname=$(basename "$f")
            curl -s -X PUT "$OBS_SRC/source/$PROJECT/$pkg_name/$fname" \
                --data-binary "@$f" >/dev/null 2>&1
        done
    fi

    COUNT=$((COUNT + 1))
    printf "  [%3d] %s\n" "$COUNT" "$pkg_name"
}

echo "=== Importing packages to $PROJECT ==="
echo "    Backend: $OBS_SRC"
echo ""

for debian_path in $(find "$REPO_ROOT/components" -maxdepth 3 -type d \
    \( -name "debian" -o -name "debian-*" \) -not -path "*/debian/*" \
    -not -path "*/open-build-service/*" | sort); do

    parent=$(dirname "$debian_path")
    variant=$(basename "$debian_path")
    import_package "$parent" "$variant" || ERRORS=$((ERRORS + 1))
done

echo ""
echo "=== Import complete: $COUNT packages imported ($ERRORS errors) ==="
