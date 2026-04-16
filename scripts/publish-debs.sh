#!/bin/bash
#
# publish-debs.sh - Publish the VersatusHPC OpenHPC Ubuntu repository
#
# Stages the OBS-published Debian repository, signs APT metadata, copies the
# public key and source-list helper, and syncs the result to the mirror server.
#
# Usage:
#   scripts/publish-debs.sh [--dry-run] [--skip-stage]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Local staging settings.
LOCAL_USER="${LOCAL_USER:-${SUDO_USER:-${USER:-builder}}}"
STAGING_ROOT="${STAGING_ROOT:-/home/${LOCAL_USER}/staging/versatushpc-4}"
STAGING_REPO="${STAGING_ROOT}/Ubuntu_24.04"

# OBS settings. The repository is read through the backend container so this
# works even when the OBS volume path differs across hosts.
OBS_CONTAINER="${OBS_CONTAINER:-obs-backend}"
OBS_REPO_PARENT="${OBS_REPO_PARENT:-/srv/obs/repos/VersatusHPC:/OHPC:/4}"
OBS_REPO_NAME="${OBS_REPO_NAME:-Ubuntu_24.04}"
OBS_REPO_PATH="${OBS_REPO_PARENT}/${OBS_REPO_NAME}"

# Repository signing settings.
GPG_KEY_NAME="${GPG_KEY_NAME:-VersatusHPC (Repository Signing Key) <support@versatushpc.com.br>}"
GPG_PUBLIC_KEY="${GPG_PUBLIC_KEY:-${REPO_ROOT}/RPM-GPG-KEY-VersatusHPC}"
APT_SOURCE_FILE="${APT_SOURCE_FILE:-${SCRIPT_DIR}/repo-files/Ubuntu_24.04/versatushpc-openhpc.list}"

# Remote mirror settings.
REMOTE_USER="${REMOTE_USER:-reposync}"
REMOTE_HOST="${REMOTE_HOST:-mirror.local.versatushpc.com.br}"
REMOTE_PATH="${REMOTE_PATH:-/mnt/pool1/repos/openhpc/versatushpc-4}"
SSH_KEY="${SSH_KEY:-/home/${LOCAL_USER}/.ssh/id_ed25519_openhpc}"

DRY_RUN=""
SKIP_STAGE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN="yes"
            shift
            ;;
        --skip-stage)
            SKIP_STAGE="yes"
            shift
            ;;
        *)
            echo "Usage: $0 [--dry-run] [--skip-stage]" >&2
            exit 2
            ;;
    esac
done

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Error: required command not found: $1" >&2
        exit 1
    }
}

require_command sudo
require_command podman
require_command tar
require_command gpg
require_command ssh
require_command rsync

if [[ ! -f "${GPG_PUBLIC_KEY}" ]]; then
    echo "Error: public repository key not found: ${GPG_PUBLIC_KEY}" >&2
    exit 1
fi

if [[ ! -f "${APT_SOURCE_FILE}" ]]; then
    echo "Error: APT source file not found: ${APT_SOURCE_FILE}" >&2
    exit 1
fi

if [[ ! -f "${SSH_KEY}" ]]; then
    echo "Error: SSH key not found: ${SSH_KEY}" >&2
    echo "Set SSH_KEY=/path/to/reposync_key or install the mirror publish key." >&2
    exit 1
fi

if ! gpg --list-secret-keys "${GPG_KEY_NAME}" >/dev/null 2>&1; then
    echo "Error: GPG secret key not available: ${GPG_KEY_NAME}" >&2
    echo "Import the VersatusHPC repository signing secret key before publishing." >&2
    exit 1
fi

if [[ -z "${SKIP_STAGE}" ]]; then
    echo "==> Staging OBS Debian repository from ${OBS_CONTAINER}:${OBS_REPO_PATH}"
    rm -rf "${STAGING_REPO}"
    mkdir -p "${STAGING_ROOT}"

    sudo podman exec "${OBS_CONTAINER}" test -f "${OBS_REPO_PATH}/Release"
    sudo podman exec "${OBS_CONTAINER}" test -f "${OBS_REPO_PATH}/Packages.gz"
    sudo podman exec "${OBS_CONTAINER}" bash -lc \
        "find '${OBS_REPO_PATH}' -type f -name '*.deb' | grep -q ."

    sudo podman exec "${OBS_CONTAINER}" tar -C "${OBS_REPO_PARENT}" -cf - "${OBS_REPO_NAME}" \
        | tar -C "${STAGING_ROOT}" -xf -
else
    echo "==> Reusing existing staged repository: ${STAGING_REPO}"
fi

if [[ ! -f "${STAGING_REPO}/Release" ]]; then
    echo "Error: staged repository does not contain Release: ${STAGING_REPO}" >&2
    exit 1
fi

echo "==> Installing public key and APT source helper into staging"
cp "${GPG_PUBLIC_KEY}" "${STAGING_ROOT}/RPM-GPG-KEY-VersatusHPC"
gpg --dearmor --yes --output "${STAGING_ROOT}/versatushpc-ohpc.gpg" "${GPG_PUBLIC_KEY}"
cp "${APT_SOURCE_FILE}" "${STAGING_REPO}/versatushpc-openhpc.list"

echo "==> Signing APT Release metadata with: ${GPG_KEY_NAME}"
(
    cd "${STAGING_REPO}"
    rm -f InRelease Release.gpg
    gpg --batch --yes --local-user "${GPG_KEY_NAME}" \
        --digest-algo SHA256 --clearsign --output InRelease Release
    gpg --batch --yes --local-user "${GPG_KEY_NAME}" \
        --digest-algo SHA256 --armor --detach-sign --output Release.gpg Release
)

RSYNC_DRY_RUN=()
if [[ -n "${DRY_RUN}" ]]; then
    RSYNC_DRY_RUN=(--dry-run)
    echo "*** DRY RUN - no files will be transferred ***"
fi

echo "==> Syncing to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}"
SSH_OPTS=(-i "${SSH_KEY}" -o StrictHostKeyChecking=no -o BatchMode=yes)
ssh "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p '${REMOTE_PATH}'"
rsync -a --delete --info=stats2,progress2 "${RSYNC_DRY_RUN[@]}" \
    -e "ssh -i ${SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes" \
    "${STAGING_ROOT}/" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/"

echo ""
echo "==> Done. Debian repository summary:"
echo "    Staged repository: ${STAGING_REPO}"
echo "    Total size:        $(du -sh "${STAGING_REPO}" | awk '{print $1}')"
echo "    .deb packages:     $(find "${STAGING_REPO}" -type f -name '*.deb' | wc -l)"
echo "    amd64 packages:    $(find "${STAGING_REPO}/amd64" -type f -name '*.deb' 2>/dev/null | wc -l)"
echo "    all packages:      $(find "${STAGING_REPO}/all" -type f -name '*.deb' 2>/dev/null | wc -l)"
echo "    Metadata:          Release InRelease Release.gpg Packages.gz"
echo ""
echo "    Users enable the repo with:"
echo "      curl -fsSL https://repos.versatushpc.com.br/openhpc/versatushpc-4/versatushpc-ohpc.gpg | sudo tee /usr/share/keyrings/versatushpc-ohpc.gpg >/dev/null"
echo "      curl -fsSL https://repos.versatushpc.com.br/openhpc/versatushpc-4/Ubuntu_24.04/versatushpc-openhpc.list | sudo tee /etc/apt/sources.list.d/versatushpc-openhpc.list >/dev/null"
echo "      sudo apt update"
