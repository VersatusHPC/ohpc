#!/bin/bash
#
# promote-update-release.sh - Point the public updates alias at a versioned tree.
#
# Usage:
#   scripts/promote-update-release.sh [--dry-run] [--skip-matrix-check] [RELEASE_DIR]
#

set -euo pipefail

LOCAL_USER="${LOCAL_USER:-builder}"
OHPC_VERSION="${OHPC_VERSION:-4.1}"
RELEASE_DIR="${RELEASE_DIR:-update.${OHPC_VERSION}}"
UPDATE_ALIAS="${UPDATE_ALIAS:-updates}"

REMOTE_USER="${REMOTE_USER:-reposync}"
REMOTE_HOST="${REMOTE_HOST:-172.21.1.40}"
REMOTE_PATH="${REMOTE_PATH:-/mnt/pool1/repos/openhpc/versatushpc-4}"
SSH_KEY="${SSH_KEY:-/home/${LOCAL_USER}/.ssh/id_ed25519_openhpc}"

DEFAULT_REQUIRED_PATHS=(
    "EL_10/ppc64le/*.rpm"
    "EL_10/noarch/*.rpm"
    "EL_10/src/*.rpm"
    "EL_10/repodata/repomd.xml"
    "openEuler_24.03/ppc64le/*.rpm"
    "openEuler_24.03/noarch/*.rpm"
    "openEuler_24.03/src/*.rpm"
    "openEuler_24.03/repodata/repomd.xml"
    "Ubuntu_24.04/amd64/*.deb"
    "Ubuntu_24.04/all/*.deb"
    "Ubuntu_24.04/ppc64el/*.deb"
    "Ubuntu_24.04/source/*.dsc"
    "Ubuntu_24.04/Packages.xz"
    "Ubuntu_24.04/Release"
    "Ubuntu_24.04/InRelease"
)

DRY_RUN=""
SKIP_MATRIX_CHECK=""

usage() {
    sed -n '1,7p' "$0" >&2
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
            shift
            ;;
        --skip-matrix-check)
            SKIP_MATRIX_CHECK="yes"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --*)
            echo "Unknown option: $1" >&2
            usage
            exit 2
            ;;
        *)
            RELEASE_DIR="$1"
            shift
            if [[ $# -gt 0 ]]; then
                echo "Error: only one RELEASE_DIR argument is supported" >&2
                usage
                exit 2
            fi
            ;;
    esac
done

validate_remote_name "RELEASE_DIR" "${RELEASE_DIR}"
validate_remote_name "UPDATE_ALIAS" "${UPDATE_ALIAS}"

command -v ssh >/dev/null 2>&1 || {
    echo "Error: required command not found: ssh" >&2
    exit 1
}
command -v lftp >/dev/null 2>&1 || {
    echo "Error: required command not found: lftp" >&2
    exit 1
}

if [[ ! -f "${SSH_KEY}" ]]; then
    echo "Error: SSH key not found: ${SSH_KEY}" >&2
    exit 1
fi

lftp_cmd() {
    local commands="$1"

    lftp -e "
set cmd:fail-exit yes;
set sftp:connect-program 'ssh -l ${REMOTE_USER} -i ${SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes';
open sftp://${REMOTE_HOST};
${commands}
bye;
"
}

remote_path_exists() {
    local path="$1"
    lftp_cmd "cls -d ${path};" >/dev/null 2>&1
}

remote_glob_exists() {
    local path="$1"
    local output

    if ! output="$(lftp_cmd "cls -1 ${path};" 2>/dev/null)"; then
        return 1
    fi
    [[ -n "${output}" ]]
}

required_paths=()
if [[ -z "${SKIP_MATRIX_CHECK}" ]]; then
    required_paths=("${DEFAULT_REQUIRED_PATHS[@]}")
fi

if [[ -n "${DRY_RUN}" ]]; then
    echo "*** DRY RUN - no remote links will be changed ***"
fi

echo "==> Promoting ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/${UPDATE_ALIAS} -> ${RELEASE_DIR}"
if ((${#required_paths[@]} > 0)); then
    echo "==> Checking required release paths before promotion"
fi

if ! remote_path_exists "${REMOTE_PATH}/${RELEASE_DIR}"; then
    echo "Error: release directory does not exist: ${REMOTE_PATH}/${RELEASE_DIR}" >&2
    exit 1
fi

missing=0
for required_path in "${required_paths[@]}"; do
    if remote_glob_exists "${REMOTE_PATH}/${RELEASE_DIR}/${required_path}"; then
        continue
    fi

    echo "Missing required path: ${RELEASE_DIR}/${required_path}" >&2
    missing=1
done
if [[ "${missing}" != "0" ]]; then
    echo "Error: release tree is incomplete; refusing to move ${UPDATE_ALIAS}" >&2
    exit 1
fi

current_alias=""
if current_alias="$(lftp_cmd "cls -ld ${REMOTE_PATH}/${UPDATE_ALIAS};" 2>/dev/null)"; then
    echo "Current ${UPDATE_ALIAS}: ${current_alias}"
else
    echo "Current ${UPDATE_ALIAS} does not exist"
fi

if [[ -n "${DRY_RUN}" ]]; then
    echo "Would set ${UPDATE_ALIAS} -> ${RELEASE_DIR}"
    exit 0
fi

if [[ -n "${current_alias}" ]]; then
    first_char="${current_alias:0:1}"
    if [[ "${first_char}" == "d" ]]; then
        backup_alias="${UPDATE_ALIAS}.pre-${RELEASE_DIR}-$(date -u +%Y%m%d%H%M%S)"
        echo "Current ${UPDATE_ALIAS} is a directory; moving it to ${backup_alias}"
        lftp_cmd "mv ${REMOTE_PATH}/${UPDATE_ALIAS} ${REMOTE_PATH}/${backup_alias};" >/dev/null
    else
        lftp_cmd "rm ${REMOTE_PATH}/${UPDATE_ALIAS};" >/dev/null
    fi
fi

lftp_cmd "ln -s ${RELEASE_DIR} ${REMOTE_PATH}/${UPDATE_ALIAS};" >/dev/null
echo "Promoted ${UPDATE_ALIAS} -> ${RELEASE_DIR}"
