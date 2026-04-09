#!/bin/bash
#
# publish-rpms.sh — Publish the VersatusHPC OpenHPC ppc64le port RPMs
#
# Stages RPMs from the local EL10 build and the openEuler container,
# signs them with the VersatusHPC GPG key, generates repository metadata,
# and syncs to the repo server via SFTP (lftp).
#
# Usage: ./publish-rpms.sh [--dry-run]
#

set -euo pipefail

# ── Local build server settings ──────────────────────────────────────
LOCAL_USER="ferrao"
LOCAL_RPMBUILD="/home/${LOCAL_USER}/rpmbuild"
STAGING_DIR="/home/${LOCAL_USER}/staging/versatushpc-4"

# ── openEuler container settings ─────────────────────────────────────
CONTAINER_NAME="oe-builder"
CONTAINER_RPMBUILD="/root/rpmbuild"

# ── GPG signing ──────────────────────────────────────────────────────
GPG_KEY_NAME="VersatusHPC (Repository Signing Key) <support@versatushpc.com.br>"
GPG_PUBLIC_KEY="/home/${LOCAL_USER}/ohpc/RPM-GPG-KEY-VersatusHPC"

# ── Remote repo server settings ──────────────────────────────────────
REMOTE_USER="reposync"
REMOTE_HOST="172.21.1.40"
REMOTE_PATH="/mnt/pool1/repos/openhpc/versatushpc-4"
SSH_KEY="/home/${LOCAL_USER}/.ssh/id_ed25519_openhpc"

# ── Dry run ──────────────────────────────────────────────────────────
DRY_RUN=""
LFTP_DRY_RUN=""
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN="yes"
    LFTP_DRY_RUN="--dry-run"
    echo "*** DRY RUN — no files will be transferred ***"
fi

# ── Skip staging if dry-run and staging already exists ───────────────
if [[ -n "${DRY_RUN}" && -d "${STAGING_DIR}" ]]; then
    echo "==> Dry run: reusing existing staging directory"
else
    echo "==> Preparing staging directory: ${STAGING_DIR}"
    rm -rf "${STAGING_DIR}"
    mkdir -p "${STAGING_DIR}/EL_10/ppc64le" \
             "${STAGING_DIR}/EL_10/noarch" \
             "${STAGING_DIR}/EL_10/src" \
             "${STAGING_DIR}/openEuler_24.03/ppc64le" \
             "${STAGING_DIR}/openEuler_24.03/noarch" \
             "${STAGING_DIR}/openEuler_24.03/src"

    # ── Stage EL10 RPMs ─────────────────────────────────────────────
    echo "==> Staging EL10 RPMs from ${LOCAL_RPMBUILD}"
    cp -v "${LOCAL_RPMBUILD}"/RPMS/ppc64le/*.rpm "${STAGING_DIR}/EL_10/ppc64le/"
    cp -v "${LOCAL_RPMBUILD}"/RPMS/noarch/*.rpm  "${STAGING_DIR}/EL_10/noarch/"
    cp -v "${LOCAL_RPMBUILD}"/SRPMS/*.rpm        "${STAGING_DIR}/EL_10/src/"

    # ── Stage openEuler RPMs (extract from container) ────────────────
    echo "==> Staging openEuler RPMs from container '${CONTAINER_NAME}'"
    podman cp "${CONTAINER_NAME}:${CONTAINER_RPMBUILD}/RPMS/ppc64le/." "${STAGING_DIR}/openEuler_24.03/ppc64le/"
    podman cp "${CONTAINER_NAME}:${CONTAINER_RPMBUILD}/RPMS/noarch/."  "${STAGING_DIR}/openEuler_24.03/noarch/"
    podman cp "${CONTAINER_NAME}:${CONTAINER_RPMBUILD}/SRPMS/."        "${STAGING_DIR}/openEuler_24.03/src/"

    # ── Sign RPMs ────────────────────────────────────────────────────
    echo "==> Signing RPMs with GPG key: ${GPG_KEY_NAME}"
    find "${STAGING_DIR}" -name "*.rpm" -exec \
        rpm --addsign --define "%_gpg_name ${GPG_KEY_NAME}" {} +

    # ── Generate repo metadata ───────────────────────────────────────
    echo "==> Running createrepo_c"
    createrepo_c "${STAGING_DIR}/EL_10/"
    createrepo_c "${STAGING_DIR}/openEuler_24.03/"

    # ── Copy GPG public key and .repo files to staging ───────────────
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    cp "${GPG_PUBLIC_KEY}" "${STAGING_DIR}/RPM-GPG-KEY-VersatusHPC"
    cp "${SCRIPT_DIR}/repo-files/EL_10/versatushpc-openhpc.repo" "${STAGING_DIR}/EL_10/"
    cp "${SCRIPT_DIR}/repo-files/openEuler_24.03/versatushpc-openhpc.repo" "${STAGING_DIR}/openEuler_24.03/"
fi

# ── Sync to repo server via SFTP (lftp) ─────────────────────────────
echo "==> Syncing to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH} via SFTP"
lftp -e "
set sftp:connect-program 'ssh -l ${REMOTE_USER} -i ${SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes';
open sftp://${REMOTE_HOST};
mkdir -p ${REMOTE_PATH};
mirror --reverse --delete --verbose ${LFTP_DRY_RUN} \
    ${STAGING_DIR}/ ${REMOTE_PATH}/;
bye;
"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "==> Done. RPM counts:"
echo "    EL_10/ppc64le:        $(find "${STAGING_DIR}/EL_10/ppc64le" -name '*.rpm' | wc -l)"
echo "    EL_10/noarch:         $(find "${STAGING_DIR}/EL_10/noarch" -name '*.rpm' | wc -l)"
echo "    EL_10/src:            $(find "${STAGING_DIR}/EL_10/src" -name '*.rpm' | wc -l)"
echo "    openEuler/ppc64le:    $(find "${STAGING_DIR}/openEuler_24.03/ppc64le" -name '*.rpm' | wc -l)"
echo "    openEuler/noarch:     $(find "${STAGING_DIR}/openEuler_24.03/noarch" -name '*.rpm' | wc -l)"
echo "    openEuler/src:        $(find "${STAGING_DIR}/openEuler_24.03/src" -name '*.rpm' | wc -l)"
echo ""
echo "    All RPMs signed with: ${GPG_KEY_NAME}"
echo "    Repository: sftp://${REMOTE_USER}@${REMOTE_HOST}${REMOTE_PATH}"
echo ""
echo "    Users enable the repo with:"
echo "      EL10:      curl -o /etc/yum.repos.d/versatushpc-openhpc.repo https://repos.versatushpc.com.br/openhpc/versatushpc-4/EL_10/versatushpc-openhpc.repo"
echo "      openEuler: curl -o /etc/yum.repos.d/versatushpc-openhpc.repo https://repos.versatushpc.com.br/openhpc/versatushpc-4/openEuler_24.03/versatushpc-openhpc.repo"
