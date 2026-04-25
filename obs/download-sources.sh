#!/bin/bash
# Pre-download all source tarballs for OBS builds.
# OBS chroots have no network access, so tarballs must be included in packages.
#
# Usage: bash obs/download-sources.sh
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COUNT=0
SKIP=0
FAIL=0

process_rules() {
    local rules="$1"
    local comp_dir
    comp_dir="$(cd "$(dirname "$rules")/.."; pwd)"

    # Extract simple variable assignments from rules file
    # Handle both `:=` and `=` styles, strip `export` prefix
    declare -A V
    while IFS= read -r line; do
        local name val
        name=$(echo "$line" | sed 's/^\s*export\s*//; s/\s*[:?]*=.*//')
        val=$(echo "$line" | sed 's/[^=]*=\s*//')
        V["$name"]="$val"
    done < <(grep -E '^\s*(export\s+)?[A-Z_]+\s*[:?]*=\s*[a-zA-Z0-9_./-]+\s*$' "$rules" 2>/dev/null)

    # Find all wget lines in the file, join continuation lines
    local content
    content=$(sed ':a;/\\$/N;s/\\\n//;ta' "$rules" 2>/dev/null)

    while IFS= read -r wgetline; do
        [ -z "$wgetline" ] && continue

        # Extract output file (-O target)
        local outfile
        outfile=$(echo "$wgetline" | grep -oP -- '-O\s+\K\S+')
        [ -z "$outfile" ] && continue

        # Extract URL
        local url
        url=$(echo "$wgetline" | grep -oP 'https?://\S+' | tail -1)
        [ -z "$url" ] && continue

        # Substitute variables in both outfile and url
        for var in "${!V[@]}"; do
            outfile="${outfile//\$($var)/${V[$var]}}"
            outfile="${outfile//\$\{$var\}/${V[$var]}}"
            url="${url//\$($var)/${V[$var]}}"
            url="${url//\$\{$var\}/${V[$var]}}"
        done

        # Skip if still has unresolved variables
        if [[ "$outfile" == *'$'* ]] || [[ "$url" == *'$'* ]]; then
            continue
        fi

        local target="$comp_dir/$outfile"

        # Skip if already exists and non-empty
        if [ -s "$target" ]; then
            SKIP=$((SKIP + 1))
            continue
        fi

        mkdir -p "$(dirname "$target")"
        printf "  [%3d] %-55s " "$((COUNT+1))" "$(basename "$target")"
        if timeout 1800 wget -q --timeout=60 --tries=2 -O "$target" "$url" 2>/dev/null; then
            local size
            size=$(stat -c %s "$target" 2>/dev/null || echo 0)
            if [ "$size" -gt 100 ]; then
                COUNT=$((COUNT + 1))
                echo "OK ($(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B"))"
            else
                rm -f "$target"
                FAIL=$((FAIL + 1))
                echo "FAIL (empty/tiny)"
            fi
        else
            rm -f "$target"
            FAIL=$((FAIL + 1))
            echo "FAIL"
        fi
    done < <(echo "$content" | grep 'wget')
}

echo "=== Downloading source tarballs for OBS builds ==="
echo ""

# Process only the first (primary) debian/rules for each component
# Variants share the same SOURCES/ directory
declare -A seen_components
for rules in $(find "$REPO_ROOT/components" -maxdepth 4 -path "*/debian/rules" -o -path "*/debian-*/rules" 2>/dev/null | sort); do
    comp_dir="$(cd "$(dirname "$rules")/.."; pwd)"
    # Skip if we've already processed this component
    [ -n "${seen_components[$comp_dir]}" ] && continue
    seen_components["$comp_dir"]=1

    process_rules "$rules"
done

echo ""
echo "=== Complete: $COUNT downloaded, $SKIP already present, $FAIL failed ==="
