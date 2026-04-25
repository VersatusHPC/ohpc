#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

version=2017.12.07.9d4e9eb
commit=9d4e9eb53116a902a80c8babccbc13d3d1fda9ff
tarball="python-rpm-macros-${version}.tar.bz2"

if [[ -s "${tarball}" ]]; then
    exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

git clone --quiet https://github.com/openSUSE/python-rpm-macros.git "${tmpdir}/python-rpm-macros"
git -C "${tmpdir}/python-rpm-macros" archive \
    --format=tar \
    --prefix="python-rpm-macros-${version}/" \
    "${commit}" \
    | bzip2 -c > "${tarball}"
