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

if [[ ! -f "${SSH_KEY}" ]]; then
    echo "Error: SSH key not found: ${SSH_KEY}" >&2
    exit 1
fi

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

ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o BatchMode=yes \
    "${REMOTE_USER}@${REMOTE_HOST}" \
    bash -s -- "${REMOTE_PATH}" "${RELEASE_DIR}" "${UPDATE_ALIAS}" "${DRY_RUN}" "${required_paths[@]}" <<'REMOTE'
set -euo pipefail

remote_path="$1"
release_dir="$2"
update_alias="$3"
dry_run="$4"
shift 4

cd "${remote_path}"

if [[ ! -d "${release_dir}" ]]; then
    echo "Error: release directory does not exist: ${remote_path}/${release_dir}" >&2
    exit 1
fi

missing=0
for required_path in "$@"; do
    if [[ "${required_path}" == *[\*\?[]* ]]; then
        if compgen -G "${release_dir}/${required_path}" >/dev/null; then
            continue
        fi
    elif [[ -e "${release_dir}/${required_path}" ]]; then
        continue
    fi

    echo "Missing required path: ${release_dir}/${required_path}" >&2
    missing=1
done
if [[ "${missing}" != "0" ]]; then
    echo "Error: release tree is incomplete; refusing to move ${update_alias}" >&2
    exit 1
fi

if [[ -n "${dry_run}" ]]; then
    if [[ -L "${update_alias}" ]]; then
        current="$(readlink "${update_alias}")"
        echo "Current ${update_alias} target: ${current}"
    elif [[ -e "${update_alias}" ]]; then
        echo "Current ${update_alias} exists but is not a symlink"
    else
        echo "Current ${update_alias} does not exist"
    fi
    echo "Would set ${update_alias} -> ${release_dir}"
    exit 0
fi

if [[ -e "${update_alias}" && ! -L "${update_alias}" ]]; then
    backup="${update_alias}.backup.$(date +%Y%m%d%H%M%S)"
    echo "Existing ${update_alias} is not a symlink; moving it to ${backup}"
    mv "${update_alias}" "${backup}"
fi

tmp_link="${update_alias}.tmp.$$"
rm -f "${tmp_link}"
ln -s "${release_dir}" "${tmp_link}"
mv -Tf "${tmp_link}" "${update_alias}"
echo "Promoted ${update_alias} -> ${release_dir}"
REMOTE
