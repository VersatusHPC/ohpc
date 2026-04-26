#!/bin/bash
#
# publish-rpms.sh — Publish the VersatusHPC OpenHPC ppc64le port RPMs
#
# Stages RPMs from the local EL10 build and the openEuler container,
# signs them with the VersatusHPC GPG key, generates repository metadata,
# and syncs to the repo server via SFTP (lftp).
#
# Usage: ./publish-rpms.sh [--dry-run] [--promote]
#

set -euo pipefail

# ── Local build server settings ──────────────────────────────────────
LOCAL_USER="${LOCAL_USER:-builder}"
OHPC_VERSION="${OHPC_VERSION:-4.1}"
RELEASE_DIR="${RELEASE_DIR:-update.${OHPC_VERSION}}"
UPDATE_ALIAS="${UPDATE_ALIAS:-updates}"
STAGING_ROOT="${STAGING_ROOT:-/home/${LOCAL_USER}/staging/versatushpc-4}"
STAGING_DIR="${STAGING_ROOT}/${RELEASE_DIR}"

# ── Container settings ──────────────────────────────────────────────
EL10_CONTAINER="${EL10_CONTAINER:-el10-builder}"
OE_CONTAINER="${OE_CONTAINER:-oe-builder}"
CONTAINER_RPMBUILD="${CONTAINER_RPMBUILD:-/root/rpmbuild}"

# ── GPG signing ──────────────────────────────────────────────────────
GPG_KEY_NAME="${GPG_KEY_NAME:-VersatusHPC (Repository Signing Key) <support@versatushpc.com.br>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GPG_PUBLIC_KEY="${GPG_PUBLIC_KEY:-${SCRIPT_DIR}/../RPM-GPG-KEY-VersatusHPC}"
PROMOTE_SCRIPT="${PROMOTE_SCRIPT:-${SCRIPT_DIR}/promote-update-release.sh}"

# ── Remote repo server settings ──────────────────────────────────────
REMOTE_USER="${REMOTE_USER:-reposync}"
REMOTE_HOST="${REMOTE_HOST:-172.21.1.40}"
REMOTE_PATH="${REMOTE_PATH:-/mnt/pool1/repos/openhpc/versatushpc-4}"
SSH_KEY="${SSH_KEY:-/home/${LOCAL_USER}/.ssh/id_ed25519_openhpc}"

# ── Dry run ──────────────────────────────────────────────────────────
DRY_RUN=""
LFTP_DRY_RUN=""
PROMOTE=""

usage() {
    echo "Usage: $0 [--dry-run] [--promote]" >&2
}

validate_remote_name() {
    local label="$1"
    local value="$2"

    if [[ ! "${value}" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "Error: ${label} must match ^[A-Za-z0-9._-]+$: ${value}" >&2
        exit 2
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN="yes"
            LFTP_DRY_RUN="--dry-run"
            shift
            ;;
        --promote)
            PROMOTE="yes"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

if [[ -n "${DRY_RUN}" ]]; then
    echo "*** DRY RUN - no files will be transferred ***"
fi

validate_remote_name "RELEASE_DIR" "${RELEASE_DIR}"
validate_remote_name "UPDATE_ALIAS" "${UPDATE_ALIAS}"

if [[ ! -f "${GPG_PUBLIC_KEY}" ]]; then
    echo "Error: public repository key not found: ${GPG_PUBLIC_KEY}" >&2
    exit 1
fi

if [[ ! -x "${PROMOTE_SCRIPT}" ]]; then
    echo "Error: promotion helper is not executable: ${PROMOTE_SCRIPT}" >&2
    exit 1
fi

stage_container_rpms() {
    local container="$1"
    local source_dir="$2"
    local target_dir="$3"
    local pattern="$4"

    if ! podman exec "${container}" test -d "${source_dir}"; then
        return 0
    fi

    if ! podman exec "${container}" bash -lc \
        "compgen -G '${source_dir}/${pattern}' >/dev/null"; then
        return 0
    fi

    podman exec "${container}" bash -lc \
        "cd '${source_dir}' && tar -cf - ${pattern}" | tar -C "${target_dir}" -xf -
}

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

    # ── Stage EL10 RPMs (extract from container) ───────────────────
    echo "==> Staging EL10 RPMs from container '${EL10_CONTAINER}'"
    stage_container_rpms "${EL10_CONTAINER}" "${CONTAINER_RPMBUILD}/RPMS/ppc64le" "${STAGING_DIR}/EL_10/ppc64le" "*ohpc*.rpm"
    stage_container_rpms "${EL10_CONTAINER}" "${CONTAINER_RPMBUILD}/RPMS/noarch"  "${STAGING_DIR}/EL_10/noarch"  "*ohpc*.rpm"
    stage_container_rpms "${EL10_CONTAINER}" "${CONTAINER_RPMBUILD}/SRPMS"        "${STAGING_DIR}/EL_10/src"     "*ohpc*.src.rpm"

    # ── Stage openEuler RPMs (extract from container) ────────────────
    echo "==> Staging openEuler RPMs from container '${OE_CONTAINER}'"
    stage_container_rpms "${OE_CONTAINER}" "${CONTAINER_RPMBUILD}/RPMS/ppc64le" "${STAGING_DIR}/openEuler_24.03/ppc64le" "*ohpc*.rpm"
    stage_container_rpms "${OE_CONTAINER}" "${CONTAINER_RPMBUILD}/RPMS/noarch"  "${STAGING_DIR}/openEuler_24.03/noarch"  "*ohpc*.rpm"
    stage_container_rpms "${OE_CONTAINER}" "${CONTAINER_RPMBUILD}/SRPMS"        "${STAGING_DIR}/openEuler_24.03/src"     "*ohpc*.src.rpm"

    # ── Sign RPMs ────────────────────────────────────────────────────
    echo "==> Signing RPMs with GPG key: ${GPG_KEY_NAME}"
    find "${STAGING_DIR}" -name "*.rpm" -exec \
        rpm --addsign --define "%_gpg_name ${GPG_KEY_NAME}" {} +

    # ── Generate repo metadata ───────────────────────────────────────
    echo "==> Running createrepo_c"
    createrepo_c "${STAGING_DIR}/EL_10/"
    createrepo_c "${STAGING_DIR}/openEuler_24.03/"

    # ── Copy GPG public key and .repo files to staging ───────────────
    cp "${GPG_PUBLIC_KEY}" "${STAGING_DIR}/RPM-GPG-KEY-VersatusHPC"
    cp "${SCRIPT_DIR}/repo-files/EL_10/versatushpc-openhpc.repo" "${STAGING_DIR}/EL_10/"
    cp "${SCRIPT_DIR}/repo-files/openEuler_24.03/versatushpc-openhpc.repo" "${STAGING_DIR}/openEuler_24.03/"
fi

# ── Sync to repo server via SFTP (lftp) ─────────────────────────────
REMOTE_RELEASE_PATH="${REMOTE_PATH}/${RELEASE_DIR}"
LFTP_KEY_UPLOADS="
put -O ${REMOTE_PATH} ${GPG_PUBLIC_KEY};
put -O ${REMOTE_RELEASE_PATH} ${STAGING_DIR}/RPM-GPG-KEY-VersatusHPC;
"
if [[ -n "${DRY_RUN}" ]]; then
    LFTP_KEY_UPLOADS="
cls -la ${REMOTE_PATH};
cls -la ${REMOTE_RELEASE_PATH};
"
fi

echo "==> Syncing to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_RELEASE_PATH} via SFTP"
lftp -e "
set cmd:fail-exit yes;
set sftp:connect-program 'ssh -l ${REMOTE_USER} -i ${SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes';
open sftp://${REMOTE_HOST};
mkdir -p ${REMOTE_PATH};
mkdir -p ${REMOTE_RELEASE_PATH};
mkdir -p ${REMOTE_RELEASE_PATH}/EL_10;
mkdir -p ${REMOTE_RELEASE_PATH}/openEuler_24.03;
mirror --reverse --delete --verbose ${LFTP_DRY_RUN} \
    ${STAGING_DIR}/EL_10/ ${REMOTE_RELEASE_PATH}/EL_10/;
mirror --reverse --delete --verbose ${LFTP_DRY_RUN} \
    ${STAGING_DIR}/openEuler_24.03/ ${REMOTE_RELEASE_PATH}/openEuler_24.03/;
${LFTP_KEY_UPLOADS}
bye;
"

if [[ -n "${PROMOTE}" ]]; then
    promote_args=()
    if [[ -n "${DRY_RUN}" ]]; then
        promote_args+=(--dry-run)
    fi
    OHPC_VERSION="${OHPC_VERSION}" \
    RELEASE_DIR="${RELEASE_DIR}" \
    UPDATE_ALIAS="${UPDATE_ALIAS}" \
    REMOTE_USER="${REMOTE_USER}" \
    REMOTE_HOST="${REMOTE_HOST}" \
    REMOTE_PATH="${REMOTE_PATH}" \
    SSH_KEY="${SSH_KEY}" \
        "${PROMOTE_SCRIPT}" "${promote_args[@]}"
fi

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
echo "    Release tree: sftp://${REMOTE_USER}@${REMOTE_HOST}${REMOTE_RELEASE_PATH}"
echo "    Updates alias: ${UPDATE_ALIAS} -> ${RELEASE_DIR} (run with --promote after the full matrix is present)"
echo ""
echo "    Users enable the repo with:"
echo "      EL10:      curl -o /etc/yum.repos.d/versatushpc-openhpc.repo https://repos.versatushpc.com.br/openhpc/versatushpc-4/${UPDATE_ALIAS}/EL_10/versatushpc-openhpc.repo"
echo "      openEuler: curl -o /etc/yum.repos.d/versatushpc-openhpc.repo https://repos.versatushpc.com.br/openhpc/versatushpc-4/${UPDATE_ALIAS}/openEuler_24.03/versatushpc-openhpc.repo"
