#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

version=1.0
tarball="amhello-${version}.tar.gz"
automake_version=1.14
automake_tarball="automake-${automake_version}.tar.xz"

if [[ -s "${tarball}" ]]; then
    exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

wget --timeout=60 --tries=3 -q \
    -O "${tmpdir}/${automake_tarball}" \
    "https://ftp.gnu.org/gnu/automake/${automake_tarball}"

tar -xOf "${tmpdir}/${automake_tarball}" \
    "automake-${automake_version}/doc/${tarball}" > "${tarball}"
