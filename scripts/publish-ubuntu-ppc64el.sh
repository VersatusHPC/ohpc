#!/bin/bash
#
# publish-ubuntu-ppc64el.sh - Publish native Ubuntu 24.04 ppc64el OpenHPC packages
#
# This runs on the POWER builder after scripts/build-ubuntu-ppc64el.sh has
# produced a local APT repository. It fetches the current public Ubuntu repo,
# merges the ppc64el binaries and source artifacts, regenerates APT metadata,
# signs Release metadata, and syncs the complete Ubuntu_24.04 tree back to the
# mirror.
#
# Usage:
#   scripts/publish-ubuntu-ppc64el.sh [--dry-run] [--skip-fetch]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOCAL_USER="${LOCAL_USER:-builder}"
WORK_ROOT="${WORK_ROOT:-/home/${LOCAL_USER}/ohpc-ubuntu-ppc64el}"
PPC_REPO="${PPC_REPO:-${WORK_ROOT}/repo/Ubuntu_24.04}"
AMD64_REPO="${AMD64_REPO:-}"
STAGING_ROOT="${STAGING_ROOT:-/home/${LOCAL_USER}/staging/versatushpc-4-ubuntu-ppc64el}"
STAGING_REPO="${STAGING_ROOT}/Ubuntu_24.04"

IMAGE="${IMAGE:-ubuntu2404-ppc64el-ohpc-builder}"

GPG_KEY_NAME="${GPG_KEY_NAME:-VersatusHPC (Repository Signing Key) <support@versatushpc.com.br>}"
GPG_PUBLIC_KEY="${GPG_PUBLIC_KEY:-${REPO_ROOT}/RPM-GPG-KEY-VersatusHPC}"
APT_SOURCE_FILE="${APT_SOURCE_FILE:-${SCRIPT_DIR}/repo-files/Ubuntu_24.04/versatushpc-openhpc.list}"
LOCAL_REPO_SCRIPT="${LOCAL_REPO_SCRIPT:-${SCRIPT_DIR}/repo-files/Ubuntu_24.04/make_repo.sh}"

REMOTE_USER="${REMOTE_USER:-reposync}"
REMOTE_HOST="${REMOTE_HOST:-172.21.1.40}"
REMOTE_PATH="${REMOTE_PATH:-/mnt/pool1/repos/openhpc/versatushpc-4}"
SSH_KEY="${SSH_KEY:-/home/${LOCAL_USER}/.ssh/id_ed25519_openhpc}"

DRY_RUN=""
SKIP_FETCH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=yes; shift ;;
        --skip-fetch) SKIP_FETCH=yes; shift ;;
        --help|-h)
            sed -n '1,13p' "$0"
            exit 0
            ;;
        *)
            echo "Usage: $0 [--dry-run] [--skip-fetch]" >&2
            exit 2
            ;;
    esac
done


prune_stale_arch_all_packages() {
    local repo="$1"
    local removed=0
    local skipped=0
    local amd64_only=(
        cuda-devel-ohpc
        cuda-repo-ohpc
        intel-compilers-devel-ohpc
        intel-mpi-devel-ohpc
        intel-oneapi-toolkit-release-ohpc
    )
    local multiarch=(
        ohpc-gnu15-io-libs
        ohpc-gnu15-mpich-io-libs
        ohpc-gnu15-openmpi5-io-libs
        ohpc-gnu15-parallel-libs
        ohpc-gnu15-mpich-parallel-libs
        ohpc-gnu15-openmpi5-parallel-libs
        ohpc-gnu15-perf-tools
        ohpc-gnu15-mpich-perf-tools
        ohpc-gnu15-openmpi5-perf-tools
        ohpc-gnu15-python3-libs
        ohpc-gnu15-runtimes
        ohpc-gnu15-serial-libs
    )

    [[ -d "${repo}/all" ]] || return 0

    prune_one() {
        local package="$1"
        local mode="$2"
        local has_amd64=0
        local has_ppc64el=0
        local file

        find "${repo}/amd64" -maxdepth 1 -type f -name "${package}_*.deb" -print -quit 2>/dev/null | grep -q . && has_amd64=1
        find "${repo}/ppc64el" -maxdepth 1 -type f -name "${package}_*.deb" -print -quit 2>/dev/null | grep -q . && has_ppc64el=1

        if [[ "${mode}" == "amd64-only" && "${has_amd64}" != 1 ]]; then
            echo "    keeping stale all/${package}: no amd64 replacement present"
            skipped=$((skipped + 1))
            return 0
        fi
        if [[ "${mode}" == "multiarch" && ("${has_amd64}" != 1 || "${has_ppc64el}" != 1) ]]; then
            echo "    keeping stale all/${package}: amd64 and ppc64el replacements are not both present"
            skipped=$((skipped + 1))
            return 0
        fi

        while IFS= read -r file; do
            echo "    removing ${file#${repo}/}"
            rm -f "${file}"
            removed=$((removed + 1))
        done < <(find "${repo}/all" -maxdepth 1 -type f -name "${package}_*_all.deb" | sort)
    }

    echo "==> Pruning stale architecture-all packages superseded by arch-specific builds"
    for package in "${amd64_only[@]}"; do
        prune_one "${package}" amd64-only
    done
    for package in "${multiarch[@]}"; do
        prune_one "${package}" multiarch
    done
    echo "    removed stale architecture-all packages: ${removed}"
    echo "    skipped stale architecture-all packages: ${skipped}"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Error: required command not found: $1" >&2
        exit 1
    }
}

require_command podman
require_command lftp
require_command gpg
require_command ssh
require_command find
require_command rsync

if [[ "$(uname -m)" != "ppc64le" ]]; then
    echo "Error: this publisher is intended to run on the native POWER builder" >&2
    exit 1
fi

if [[ ! -d "${PPC_REPO}/ppc64el" ]] || ! find "${PPC_REPO}/ppc64el" -type f -name '*.deb' -print -quit | grep -q .; then
    echo "Error: no ppc64el packages found under ${PPC_REPO}/ppc64el" >&2
    exit 1
fi

for file in "${GPG_PUBLIC_KEY}" "${APT_SOURCE_FILE}" "${LOCAL_REPO_SCRIPT}" "${SSH_KEY}"; do
    if [[ ! -f "${file}" ]]; then
        echo "Error: required file not found: ${file}" >&2
        exit 1
    fi
done

if ! gpg --list-secret-keys "${GPG_KEY_NAME}" >/dev/null 2>&1; then
    echo "Error: GPG secret key not available: ${GPG_KEY_NAME}" >&2
    exit 1
fi

if ! podman image exists "${IMAGE}"; then
    echo "==> Building ${IMAGE}"
    podman build --arch ppc64le \
        -t "${IMAGE}" \
        -f "${SCRIPT_DIR}/Containerfile.ubuntu2404-ppc64el-builder" \
        "${REPO_ROOT}"
fi

if [[ -z "${SKIP_FETCH}" ]]; then
    echo "==> Fetching current public Ubuntu repository into ${STAGING_REPO}"
    rm -rf "${STAGING_REPO}"
    mkdir -p "${STAGING_ROOT}"
    lftp -e "
set cmd:fail-exit yes;
set sftp:connect-program 'ssh -l ${REMOTE_USER} -i ${SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes';
open sftp://${REMOTE_HOST};
mirror --verbose ${REMOTE_PATH}/Ubuntu_24.04/ ${STAGING_REPO}/;
bye;
"
else
    echo "==> Reusing staged repository: ${STAGING_REPO}"
fi

if [[ ! -d "${STAGING_REPO}" ]]; then
    echo "Error: staged repository missing: ${STAGING_REPO}" >&2
    exit 1
fi

echo "==> Merging native ppc64el packages"
mkdir -p "${STAGING_REPO}/ppc64el" "${STAGING_REPO}/source"
rsync -a --delete "${PPC_REPO}/ppc64el/" "${STAGING_REPO}/ppc64el/"
if [[ -d "${PPC_REPO}/source" ]]; then
    rsync -a "${PPC_REPO}/source/" "${STAGING_REPO}/source/"
fi

if [[ -n "${AMD64_REPO}" ]]; then
    if [[ ! -d "${AMD64_REPO}/amd64" ]]; then
        echo "Error: AMD64_REPO does not contain an amd64 directory: ${AMD64_REPO}" >&2
        exit 1
    fi
    echo "==> Merging amd64 repository fixes from ${AMD64_REPO}"
    mkdir -p "${STAGING_REPO}/amd64"
    rsync -a "${AMD64_REPO}/amd64/" "${STAGING_REPO}/amd64/"
    if [[ -d "${AMD64_REPO}/source" ]]; then
        rsync -a "${AMD64_REPO}/source/" "${STAGING_REPO}/source/"
    fi
fi

prune_stale_arch_all_packages "${STAGING_REPO}"

echo "==> Installing public key, APT source helper, and local repo helper"
cp "${GPG_PUBLIC_KEY}" "${STAGING_REPO}/RPM-GPG-KEY-VersatusHPC"
gpg --dearmor --yes --output "${STAGING_REPO}/versatushpc.gpg" "${GPG_PUBLIC_KEY}"
cp "${APT_SOURCE_FILE}" "${STAGING_REPO}/versatushpc-openhpc.list"
cp "${LOCAL_REPO_SCRIPT}" "${STAGING_REPO}/make_repo.sh"
chmod 0755 "${STAGING_REPO}/make_repo.sh"

echo "==> Regenerating APT metadata"
podman run --rm -v "${STAGING_REPO}:/repo:z" "${IMAGE}" bash -lc '
    set -euo pipefail
    cd /repo
    rm -f Packages Packages.gz Packages.xz Sources Sources.gz Sources.xz Release InRelease Release.gpg
    dpkg-scanpackages --multiversion . /dev/null > Packages
    gzip -n -c Packages > Packages.gz
    xz -c -9 Packages > Packages.xz
    if find source -maxdepth 1 -type f -name "*.dsc" -print -quit | grep -q .; then
        dpkg-scansources source /dev/null > Sources
        gzip -n -c Sources > Sources.gz
        xz -c -9 Sources > Sources.xz
    fi
    apt-ftparchive release . > Release
'

echo "==> Signing APT Release metadata with: ${GPG_KEY_NAME}"
(
    cd "${STAGING_REPO}"
    gpg --batch --yes --local-user "${GPG_KEY_NAME}" \
        --digest-algo SHA256 --clearsign --output InRelease Release
    gpg --batch --yes --local-user "${GPG_KEY_NAME}" \
        --digest-algo SHA256 --armor --detach-sign --output Release.gpg Release
)

LFTP_DRY_RUN=""
if [[ -n "${DRY_RUN}" ]]; then
    LFTP_DRY_RUN="--dry-run"
    echo "*** DRY RUN - no files will be transferred ***"
fi

echo "==> Syncing merged Ubuntu repository to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
lftp -e "
set cmd:fail-exit yes;
set sftp:connect-program 'ssh -l ${REMOTE_USER} -i ${SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes';
open sftp://${REMOTE_HOST};
mkdir -pf ${REMOTE_PATH}/Ubuntu_24.04;
mirror --reverse --delete --verbose ${LFTP_DRY_RUN} ${STAGING_REPO}/ ${REMOTE_PATH}/Ubuntu_24.04/;
bye;
"

echo ""
echo "==> Done. Ubuntu repository summary:"
echo "    Staged repository: ${STAGING_REPO}"
echo "    ppc64el packages:  $(find "${STAGING_REPO}/ppc64el" -type f -name '*.deb' | wc -l)"
echo "    amd64 packages:    $(find "${STAGING_REPO}/amd64" -type f -name '*.deb' 2>/dev/null | wc -l)"
echo "    all packages:      $(find "${STAGING_REPO}/all" -type f -name '*.deb' 2>/dev/null | wc -l)"
echo "    source packages:   $(grep -c '^Package: ' "${STAGING_REPO}/Sources" 2>/dev/null || echo 0)"
echo "    Metadata:          Release InRelease Release.gpg Packages Packages.gz Packages.xz Sources Sources.gz Sources.xz"
