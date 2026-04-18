#!/bin/bash
# Configure APT to use a local VersatusHPC OpenHPC Ubuntu repository mirror.

set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    echo "Error: run this script as root, for example: sudo $0" >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${1:-${script_dir}}"

if [[ -d "${repo_root}/Ubuntu_24.04" ]]; then
    repo_dir="${repo_root}/Ubuntu_24.04"
else
    repo_dir="${repo_root}"
fi

repo_dir="$(cd "${repo_dir}" && pwd)"
repo_root="$(cd "${repo_root}" && pwd)"

if [[ ! -f "${repo_dir}/Release" || ! -f "${repo_dir}/Packages.gz" ]]; then
    echo "Error: ${repo_dir} does not look like an OpenHPC Ubuntu APT repository" >&2
    echo "Expected Release and Packages.gz metadata files." >&2
    exit 1
fi

install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d

if [[ -f "${repo_root}/versatushpc.gpg" ]]; then
    install -m 0644 "${repo_root}/versatushpc.gpg" /usr/share/keyrings/versatushpc.gpg
elif [[ -f "${repo_root}/RPM-GPG-KEY-VersatusHPC" ]]; then
    if ! command -v gpg >/dev/null 2>&1; then
        echo "Error: gpg is required to convert RPM-GPG-KEY-VersatusHPC" >&2
        exit 1
    fi
    gpg --dearmor --yes --output /usr/share/keyrings/versatushpc.gpg \
        "${repo_root}/RPM-GPG-KEY-VersatusHPC"
else
    echo "Error: repository signing key not found under ${repo_root}" >&2
    exit 1
fi

cat > /etc/apt/sources.list.d/versatushpc-openhpc.list <<EOF_LIST
# VersatusHPC OpenHPC 4.x for Ubuntu 24.04 LTS local mirror
deb [signed-by=/usr/share/keyrings/versatushpc.gpg] file://${repo_dir}/ ./
EOF_LIST

apt update

echo "Configured VersatusHPC OpenHPC repository: file://${repo_dir}/"
