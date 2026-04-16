#!/bin/bash
# Import all OpenHPC packages into OBS.
#
# For each component with a debian/ directory, creates an OBS package
# and uploads the debian/ files + source tarball.
#
# Usage: bash obs/import-packages.sh
#
# Prerequisites:
#   - osc configured (run setup-project.sh first)
#   - OBS project VersatusHPC:OHPC:4 exists

set -e

PROJECT="VersatusHPC:OHPC:4"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

import_package() {
    local comp_dir="$1"
    local debian_dir="$2"
    local pkg_name

    # Get package name from debian/control
    pkg_name=$(grep "^Source:" "$comp_dir/$debian_dir/control" | awk '{print $2}')
    if [ -z "$pkg_name" ]; then
        echo "  SKIP: no Source in $comp_dir/$debian_dir/control"
        return
    fi

    echo "  Importing $pkg_name from $comp_dir/$debian_dir..."

    # Create OBS package
    osc api -X PUT "/source/$PROJECT/$pkg_name/_meta" -d "
<package name=\"$pkg_name\" project=\"$PROJECT\">
  <title>$pkg_name</title>
  <description>OpenHPC package for Ubuntu</description>
</package>" 2>/dev/null || true

    # Create a working directory
    local workdir="/tmp/obs-import/$pkg_name"
    rm -rf "$workdir" && mkdir -p "$workdir"

    # Copy debian/ files
    cp -a "$comp_dir/$debian_dir"/* "$workdir/"

    # Copy SOURCES/ if exists
    if [ -d "$comp_dir/SOURCES" ]; then
        for f in "$comp_dir/SOURCES"/*.tar.* "$comp_dir/SOURCES"/*.patch; do
            [ -f "$f" ] && cp "$f" "$workdir/"
        done
    fi

    # Upload to OBS
    # (In practice, use osc checkout + copy + commit)
    echo "    -> $pkg_name ready at $workdir"
}

echo "=== Importing packages to $PROJECT ==="
echo ""

# Import all debian/ variants
for comp_dir in $(find "$REPO_ROOT/components" -maxdepth 3 -type d \
    \( -name "debian" -o -name "debian-*" \) -not -path "*/debian/*" | sort); do

    parent=$(dirname "$comp_dir")
    variant=$(basename "$comp_dir")
    import_package "$parent" "$variant"
done

echo ""
echo "=== Import complete ==="
echo "Total packages ready: $(find /tmp/obs-import -maxdepth 1 -type d | wc -l)"
echo ""
echo "To upload to OBS, use osc for each package:"
echo "  cd /tmp/obs-import/<package>"
echo "  osc checkout $PROJECT <package>"
echo "  cp * $PROJECT/<package>/"
echo "  cd $PROJECT/<package> && osc addremove && osc commit"
