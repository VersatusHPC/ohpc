#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

for wheel in \
    beniget-0.4.2.post1-py3-none-any.whl \
    gast-0.6.0-py3-none-any.whl \
    meson-1.10.2-py3-none-any.whl \
    meson_python-0.19.0-py3-none-any.whl \
    packaging-26.0-py3-none-any.whl \
    ply-3.11-py2.py3-none-any.whl \
    pybind11-3.0.3-py3-none-any.whl \
    pyproject_metadata-0.11.0-py3-none-any.whl \
    pythran-0.18.1-py3-none-any.whl \
    setuptools-82.0.1-py3-none-any.whl
do
    if [[ ! -e "${wheel}" ]]; then
        ln -s "pip-wheels/${wheel}" "${wheel}"
    fi
done
