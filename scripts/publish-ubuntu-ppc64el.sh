#!/bin/bash
#
# publish-ubuntu-ppc64el.sh - Publish native Ubuntu 24.04 ppc64el OpenHPC packages
#
# This runs on the POWER builder after scripts/build-ubuntu-ppc64el.sh has
# produced a local APT repository. It fetches the current public Ubuntu repo,
# merges the ppc64el binaries and source artifacts into the versioned release
# tree, regenerates APT metadata, signs Release metadata, and syncs the complete
# Ubuntu_24.04 tree back to the mirror.
#
# Usage:
#   scripts/publish-ubuntu-ppc64el.sh [--dry-run] [--skip-fetch] [--promote]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOCAL_USER="${LOCAL_USER:-builder}"
OHPC_VERSION="${OHPC_VERSION:-4.1}"
RELEASE_DIR="${RELEASE_DIR:-update.${OHPC_VERSION}}"
UPDATE_ALIAS="${UPDATE_ALIAS:-updates}"
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
PROMOTE_SCRIPT="${PROMOTE_SCRIPT:-${SCRIPT_DIR}/promote-update-release.sh}"
MIN_PPC64EL_DEB_COUNT="${MIN_PPC64EL_DEB_COUNT:-120}"
MIN_AMD64_DEB_COUNT="${MIN_AMD64_DEB_COUNT:-290}"
MIN_ALL_DEB_COUNT="${MIN_ALL_DEB_COUNT:-21}"

REMOTE_USER="${REMOTE_USER:-reposync}"
REMOTE_HOST="${REMOTE_HOST:-172.21.1.40}"
REMOTE_PATH="${REMOTE_PATH:-/mnt/pool1/repos/openhpc/versatushpc-4}"
SSH_KEY="${SSH_KEY:-/home/${LOCAL_USER}/.ssh/id_ed25519_openhpc}"

DRY_RUN=""
SKIP_FETCH=""
PROMOTE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=yes; shift ;;
        --skip-fetch) SKIP_FETCH=yes; shift ;;
        --promote) PROMOTE=yes; shift ;;
        --help|-h)
            sed -n '1,13p' "$0"
            exit 0
            ;;
        *)
            echo "Usage: $0 [--dry-run] [--skip-fetch] [--promote]" >&2
            exit 2
            ;;
    esac
done

validate_remote_name() {
    local label="$1"
    local value="$2"

    if [[ ! "${value}" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "Error: ${label} must match ^[A-Za-z0-9._-]+$: ${value}" >&2
        exit 2
    fi
}

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
            echo "    removing ${file#"${repo}"/}"
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

require_deb_count() {
    local label="$1"
    local directory="$2"
    local minimum="$3"
    local count

    if [[ ! -d "${directory}" ]]; then
        echo "Error: ${label} directory missing: ${directory}" >&2
        return 1
    fi

    count="$(find "${directory}" -maxdepth 1 -name '*.deb' | wc -l)"
    if (( count < minimum )); then
        echo "Error: ${label} contains ${count} .deb files; expected at least ${minimum}" >&2
        return 1
    fi
}

require_deb_package_version() {
    local packages_file="$1"
    local package="$2"
    local arch="$3"
    local version_prefix="$4"

    if ! awk -v want_package="${package}" -v want_arch="${arch}" -v want_version="${version_prefix}" '
        BEGIN { RS=""; FS="\n"; found=0 }
        {
            package=""; arch=""; version="";
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^Package: /) package=substr($i, 10);
                if ($i ~ /^Architecture: /) arch=substr($i, 15);
                if ($i ~ /^Version: /) version=substr($i, 10);
            }
            if (package == want_package && arch == want_arch && index(version, want_version) == 1) {
                found=1;
            }
        }
        END { exit(found ? 0 : 1) }
    ' "${packages_file}"; then
        echo "Error: ${package}:${arch} version ${version_prefix}* not found in ${packages_file}" >&2
        return 1
    fi
}

validate_staged_repo() {
    local packages_file="${STAGING_REPO}/Packages"
    local stale_list

    if [[ ! -f "${packages_file}" ]]; then
        echo "Error: staged repository is missing Packages metadata: ${packages_file}" >&2
        exit 1
    fi

    stale_list="$(find "${STAGING_REPO}" -name '*.deb' \( \
        -name 'mvapich2-gnu15-ohpc_2.*.deb' -o \
        -name 'mpich-gnu15-ohpc_5.0.0-*.deb' -o \
        -name 'lmod-ohpc_9.0.5-*.deb' -o \
        -name 'ohpc-*_4.0-*.deb' \
    \) -print)"
    stale_list+="$(
        find "${STAGING_REPO}/source" -maxdepth 1 -type f \( \
            -name 'mvapich2-gnu15-ohpc_2.*' -o \
            -name 'mpich-gnu15-ohpc_5.0.0-*' -o \
            -name 'lmod-ohpc_9.0.5-*' -o \
            -name 'ohpc-meta-packages_4.0-*' \
        \) -print 2>/dev/null
    )"
    if [[ -n "${stale_list}" ]]; then
        echo "Error: stale Debian artifacts found in staging; refusing to publish release artifacts" >&2
        printf '%s\n' "${stale_list}" >&2
        exit 1
    fi
    scan_stale_deb_elf_needed_in_container "${STAGING_REPO}" || exit 1

    require_deb_count "ppc64el package directory" "${STAGING_REPO}/ppc64el" "${MIN_PPC64EL_DEB_COUNT}"
    require_deb_count "amd64 package directory" "${STAGING_REPO}/amd64" "${MIN_AMD64_DEB_COUNT}"
    require_deb_count "all package directory" "${STAGING_REPO}/all" "${MIN_ALL_DEB_COUNT}"

    for arch in amd64 ppc64el; do
        require_deb_package_version "${packages_file}" gnu15-compilers-ohpc "${arch}" "15.2.0"
        require_deb_package_version "${packages_file}" lmod-ohpc "${arch}" "9.2"
        require_deb_package_version "${packages_file}" mpich-gnu15-ohpc "${arch}" "5.0.1"
        require_deb_package_version "${packages_file}" mvapich2-gnu15-ohpc "${arch}" "${OHPC_VERSION}"
        require_deb_package_version "${packages_file}" openmpi5-gnu15-ohpc "${arch}" "5.0.10"
        require_deb_package_version "${packages_file}" ucx-ohpc "${arch}" "1.20.0"
        require_deb_package_version "${packages_file}" scalapack-gnu15-openmpi5-ohpc "${arch}" "2.2.3"
        require_deb_package_version "${packages_file}" petsc-gnu15-mpich-ohpc "${arch}" "3.25.0"
        require_deb_package_version "${packages_file}" petsc-gnu15-openmpi5-ohpc "${arch}" "3.25.0"
        require_deb_package_version "${packages_file}" slepc-gnu15-mpich-ohpc "${arch}" "3.25.0"
        require_deb_package_version "${packages_file}" slepc-gnu15-openmpi5-ohpc "${arch}" "3.25.0"
        require_deb_package_version "${packages_file}" mfem-gnu15-openmpi5-ohpc "${arch}" "4.9"
        for stack in mpich mvapich2 openmpi5; do
            require_deb_package_version "${packages_file}" "mfem-gnu15-${stack}-ohpc" "${arch}" "4.9-1ohpc2"
            require_deb_package_version "${packages_file}" "mumps-gnu15-${stack}-ohpc" "${arch}" "5.8.2-1ohpc2"
        done
        require_deb_package_version "${packages_file}" r-gnu15-ohpc "${arch}" "4.5.3"
    done

    for stack in impi; do
        require_deb_package_version "${packages_file}" "mfem-gnu15-${stack}-ohpc" amd64 "4.9-1ohpc2"
        require_deb_package_version "${packages_file}" "mumps-gnu15-${stack}-ohpc" amd64 "5.8.2-1ohpc2"
    done
    for stack in mpich mvapich2 openmpi5 impi; do
        require_deb_package_version "${packages_file}" "mfem-intel-${stack}-ohpc" amd64 "4.9-1ohpc2"
        require_deb_package_version "${packages_file}" "mumps-intel-${stack}-ohpc" amd64 "5.8.2-1ohpc2"
    done

    require_deb_package_version "${packages_file}" ohpc-release all "1:${OHPC_VERSION}"
    require_deb_package_version "${packages_file}" ohpc-filesystem all "${OHPC_VERSION}"
}

scan_stale_deb_elf_needed_in_container() {
    local repo="$1"

    echo "==> Checking staged Debian ELF dependencies for stale PETSc/ScaLAPACK SONAMEs"
    podman run --rm -v "${repo}:/repo:ro,z" "${IMAGE}" bash -lc '
        set -euo pipefail
        tmp_root="$(mktemp -d)"
        trap "rm -rf \"${tmp_root}\"" EXIT
        failed=0

        while IFS= read -r deb; do
            work="$(mktemp -d "${tmp_root}/deb.XXXXXX")"
            dpkg-deb -x "${deb}" "${work}/root"

            while IFS= read -r elf; do
                needed="$(readelf -d "${elf}" 2>/dev/null || true)"
                if printf "%s\n" "${needed}" | grep -Eq "Shared library: \[(libpetsc\.so\.3\.24|libscalapack\.so\.2)\]"; then
                    echo "Error: stale ELF dependency in ${deb#/repo/}: ${elf#${work}/root/}" >&2
                    printf "%s\n" "${needed}" | grep -E "Shared library: \[(libpetsc\.so\.3\.24|libscalapack\.so\.2)\]" >&2
                    failed=1
                fi
            done < <(find "${work}/root/opt/ohpc" -type f \( -perm /111 -o -name "*.so" -o -name "*.so.*" \) -print 2>/dev/null)
            rm -rf "${work}"
        done < <(find /repo -type f -name "*.deb" | sort)

        if [[ "${failed}" != 0 ]]; then
            echo "Error: stale PETSc/ScaLAPACK ELF dependencies found; refusing to publish release artifacts" >&2
            exit 1
        fi
    '
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

if [[ ! -x "${PROMOTE_SCRIPT}" ]]; then
    echo "Error: promotion helper is not executable: ${PROMOTE_SCRIPT}" >&2
    exit 1
fi

validate_remote_name "RELEASE_DIR" "${RELEASE_DIR}"
validate_remote_name "UPDATE_ALIAS" "${UPDATE_ALIAS}"

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

REMOTE_RELEASE_PATH="${REMOTE_PATH}/${RELEASE_DIR}"

if [[ -z "${SKIP_FETCH}" ]]; then
    echo "==> Fetching versioned Ubuntu repository into ${STAGING_REPO}"
    rm -rf "${STAGING_REPO}"
    mkdir -p "${STAGING_ROOT}"
    lftp -e "
set cmd:fail-exit yes;
set sftp:connect-program 'ssh -l ${REMOTE_USER} -i ${SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes';
open sftp://${REMOTE_HOST};
mirror --verbose ${REMOTE_RELEASE_PATH}/Ubuntu_24.04/ ${STAGING_REPO}/;
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

validate_staged_repo

echo "==> Signing APT Release metadata with: ${GPG_KEY_NAME}"
(
    cd "${STAGING_REPO}"
    gpg --batch --yes --local-user "${GPG_KEY_NAME}" \
        --digest-algo SHA256 --clearsign --output InRelease Release
    gpg --batch --yes --local-user "${GPG_KEY_NAME}" \
        --digest-algo SHA256 --armor --detach-sign --output Release.gpg Release
)

if [[ -n "${DRY_RUN}" ]]; then
    LFTP_COMMANDS="
cls -la ${REMOTE_PATH};
"
    echo "*** DRY RUN - no files will be transferred ***"
else
    LFTP_COMMANDS="
cd ${REMOTE_PATH};
mkdir -pf ${RELEASE_DIR}/Ubuntu_24.04;
mirror --reverse --delete --verbose ${STAGING_REPO}/ ${RELEASE_DIR}/Ubuntu_24.04/;
rm -f versatushpc*.gpg;
put -O . ${GPG_PUBLIC_KEY};
put -O . ${STAGING_REPO}/versatushpc.gpg;
"
fi

echo "==> Syncing merged Ubuntu repository to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_RELEASE_PATH}"
lftp -e "
set cmd:fail-exit yes;
set sftp:connect-program 'ssh -l ${REMOTE_USER} -i ${SSH_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes';
open sftp://${REMOTE_HOST};
${LFTP_COMMANDS}
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

echo ""
echo "==> Done. Ubuntu repository summary:"
echo "    Staged repository: ${STAGING_REPO}"
echo "    Release tree:      sftp://${REMOTE_USER}@${REMOTE_HOST}${REMOTE_RELEASE_PATH}/Ubuntu_24.04/"
echo "    Updates alias:     ${UPDATE_ALIAS} -> ${RELEASE_DIR} (run with --promote after the full matrix is present)"
echo "    ppc64el packages:  $(find "${STAGING_REPO}/ppc64el" -type f -name '*.deb' | wc -l)"
echo "    amd64 packages:    $(find "${STAGING_REPO}/amd64" -type f -name '*.deb' 2>/dev/null | wc -l)"
echo "    all packages:      $(find "${STAGING_REPO}/all" -type f -name '*.deb' 2>/dev/null | wc -l)"
echo "    source packages:   $(grep -c '^Package: ' "${STAGING_REPO}/Sources" 2>/dev/null || echo 0)"
echo "    Metadata:          Release InRelease Release.gpg Packages Packages.gz Packages.xz Sources Sources.gz Sources.xz"
