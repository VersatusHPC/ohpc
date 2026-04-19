#!/bin/bash
#
# Build the Ubuntu 24.04 ppc64el OpenHPC package set without OBS.
#
# This is intended to run on the native POWER builder host as the builder user.
# It keeps a flat local APT repository under $WORK_ROOT/repo and updates that
# repository after every successful package so later builds can install OpenHPC
# build dependencies from it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE="${IMAGE:-ubuntu2404-ppc64el-ohpc-builder}"
CONTAINER="${CONTAINER:-ubuntu2404-ppc64el-builder}"
WORK_ROOT="${WORK_ROOT:-${HOME}/ohpc-ubuntu-ppc64el}"
BUILD_ROOT="${WORK_ROOT}/build"
REPO_DIR="${WORK_ROOT}/repo/Ubuntu_24.04"
LOG_DIR="${WORK_ROOT}/logs"
STATE_DIR="${WORK_ROOT}/state"
BUILD_LIST="${BUILD_LIST:-}"
UBUNTU_MIRROR="${UBUNTU_MIRROR:-}"
KEEP_GOING=0
RESUME=0
REBUILD_IMAGE=0
ONLY=""
FROM_ENTRY=""

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --resume              Skip entries already recorded as built
  --keep-going          Continue after failures and report them at the end
  --only ENTRY          Build one entry, e.g. components/admin/lmod/debian
  --from ENTRY          Start at ENTRY in the generated build order
  --rebuild-image       Rebuild the Ubuntu ppc64el builder image
  --help                Show this help

Environment:
  WORK_ROOT             Build/repo root (default: ~/ohpc-ubuntu-ppc64el)
  IMAGE                 Builder image name (default: ubuntu2404-ppc64el-ohpc-builder)
  CONTAINER             Persistent container name
  UBUNTU_MIRROR         Optional Ubuntu ports mirror URL for image builds
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --resume) RESUME=1; shift ;;
        --keep-going) KEEP_GOING=1; shift ;;
        --only) ONLY="$2"; shift 2 ;;
        --from) FROM_ENTRY="$2"; shift 2 ;;
        --rebuild-image) REBUILD_IMAGE=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ "$(uname -m)" != "ppc64le" ]]; then
    echo "Error: this script must run on a native ppc64le host" >&2
    exit 1
fi

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Error: required command not found: $1" >&2
        exit 1
    }
}

require_command podman
require_command python3

mkdir -p "${BUILD_ROOT}" "${REPO_DIR}/all" "${REPO_DIR}/ppc64el" \
    "${REPO_DIR}/source" "${LOG_DIR}" "${STATE_DIR}"

build_image() {
    if [[ "${REBUILD_IMAGE}" == 1 ]] || ! podman image exists "${IMAGE}"; then
        echo "==> Building ${IMAGE}"
        podman build --arch ppc64le \
            --build-arg "UBUNTU_MIRROR=${UBUNTU_MIRROR}" \
            -f "${SCRIPT_DIR}/Containerfile.ubuntu2404-ppc64el-builder" \
            -t "${IMAGE}" "${REPO_ROOT}"
    fi
}

ensure_container() {
    if podman container exists "${CONTAINER}"; then
        if [[ "$(podman inspect -f '{{.State.Running}}' "${CONTAINER}")" != "true" ]]; then
            podman start "${CONTAINER}" >/dev/null
        fi
        return
    fi

    echo "==> Starting ${CONTAINER}"
    podman run -d --init --name "${CONTAINER}" \
        --hostname "${CONTAINER}" \
        -v "${REPO_ROOT}:/build:z" \
        -v "${WORK_ROOT}:/work:z" \
        -v "${REPO_DIR}:/repo:z" \
        "${IMAGE}" sleep infinity >/dev/null
}

refresh_repo() {
    podman exec "${CONTAINER}" bash -lc '
        set -euo pipefail
        cd /repo
        dpkg-scanpackages --multiversion . /dev/null > Packages
        gzip -n -c Packages > Packages.gz
        xz -c -9 Packages > Packages.xz
        if find source -maxdepth 1 -type f -name "*.dsc" -print -quit | grep -q .; then
            dpkg-scansources source /dev/null > Sources
            gzip -n -c Sources > Sources.gz
            xz -c -9 Sources > Sources.xz
        fi
        apt-ftparchive release . > Release
        apt-get update -qq
    '
}

prepare_apt() {
    podman exec "${CONTAINER}" bash -lc '
        set -euo pipefail
        echo "deb [trusted=yes] file:/repo ./" > /etc/apt/sources.list.d/openhpc-local.list
    '
}

read_build_entries() {
    if [[ -n "${BUILD_LIST}" ]]; then
        grep -Ev "^[[:space:]]*(#|$)" "${BUILD_LIST}"
    elif [[ -n "${ONLY}" ]]; then
        printf "%s\n" "${ONLY}"
    else
        "${REPO_ROOT}/scripts/list-ubuntu-ppc64el-builds.py"
    fi
}

entry_safe_name() {
    echo "$1" | tr '/:' '__'
}

build_entry() {
    local entry="$1"
    local safe log state_file
    safe="$(entry_safe_name "${entry}")"
    log="${LOG_DIR}/${safe}.log"
    state_file="${STATE_DIR}/${safe}.done"

    if [[ "${RESUME}" == 1 && -f "${state_file}" ]]; then
        echo "==> SKIP ${entry}"
        return 0
    fi

    echo "==> BUILD ${entry}"
    if podman exec \
        -e "BUILD_ENTRY=${entry}" \
        -e "SAFE_NAME=${safe}" \
        "${CONTAINER}" bash -lc '
            set -euo pipefail
            export DEBIAN_FRONTEND=noninteractive
            entry="${BUILD_ENTRY}"
            safe="${SAFE_NAME}"
            src="/build/${entry}"
            component="$(dirname "${src}")"
            debdir="$(basename "${src}")"
            work="/work/build/${safe}"
            out="/work/out/${safe}"

            rm -rf "${work}" "${out}"
            mkdir -p "${work}" "${out}"
            rsync -a --delete \
                --exclude ".git" \
                --exclude "*.deb" \
                --exclude "*.dsc" \
                --exclude "*.changes" \
                --exclude "*.buildinfo" \
                "${component}/" "${work}/"

            if [ "${debdir}" != "debian" ]; then
                rm -rf "${work}/debian"
                cp -a "${work}/${debdir}" "${work}/debian"
            fi
            if [ "${entry}" = "components/admin/ohpc-filesystem/debian" ]; then
                mkdir -p "${work}/SOURCES"
                rm -f "${work}/SOURCES/OHPC_setup_compiler" "${work}/SOURCES/OHPC_setup_mpi"
                cp -a \
                    /build/components/OHPC_setup_compiler \
                    /build/components/OHPC_setup_mpi \
                    "${work}/SOURCES/"
            fi
            if [ "${entry}" = "components/admin/docs/debian" ]; then
                mkdir -p "${work}/docs/recipes/install"
                cp -a \
                    /build/docs/recipes/install/common \
                    /build/docs/recipes/install/parse_doc.pl \
                    /build/docs/recipes/install/ubuntu24.04 \
                    "${work}/docs/recipes/install/"
                find "${work}/docs/recipes/install" -type f \
                    \( -name "steps.aux" -o -name "steps.fdb_latexmk" -o -name "steps.fls" \
                       -o -name "steps.log" -o -name "steps.out" -o -name "steps.pdf" \
                       -o -name "steps.toc" -o -name "vc.tex" -o -name "recipe.sh" \) -delete
                cp /build/docs/ChangeLog "${work}/docs/" 2>/dev/null || true
                cp /build/docs/Release_Notes.txt "${work}/docs/" 2>/dev/null || true
                git -C /build log -1 --pretty=format:%H > "${work}/docs/.ohpc-revision" 2>/dev/null || true
                git -C /build log -1 --pretty=format:%as > "${work}/docs/.ohpc-date" 2>/dev/null || true
            fi

            cd "${work}"
            apt-get update -qq
            dummy_pkg="$(dpkg-parsechangelog -S Source)-build-deps"
            apt-get -y purge "${dummy_pkg}" >/dev/null 2>&1 || true
            mk-build-deps --install --remove \
                --tool "apt-get -y --no-install-recommends" \
                debian/control
            dpkg-buildpackage -us -uc -sa
            find "$(dirname "${work}")" -maxdepth 1 -type f \
                \( -name "*.deb" -o -name "*.dsc" -o -name "*.tar.*" -o -name "*.changes" -o -name "*.buildinfo" \) \
                -exec mv -f {} "${out}/" \;

            shopt -s nullglob
            for deb in "${out}"/*.deb; do
                arch="$(dpkg-deb -f "${deb}" Architecture)"
                case "${arch}" in
                    all|ppc64el) install -D -m 0644 "${deb}" "/repo/${arch}/$(basename "${deb}")" ;;
                    *) echo "Unexpected package architecture ${arch}: ${deb}" >&2; exit 1 ;;
                esac
            done
            for srcfile in "${out}"/*.dsc "${out}"/*.tar.* "${out}"/*.changes "${out}"/*.buildinfo; do
                install -D -m 0644 "${srcfile}" "/repo/source/$(basename "${srcfile}")"
            done
        ' >"${log}" 2>&1; then
        refresh_repo >>"${log}" 2>&1
        date -u +%FT%TZ > "${state_file}"
        echo "==> OK ${entry}"
        return 0
    fi

    echo "==> FAIL ${entry} (log: ${log})" >&2
    return 1
}

main() {
    build_image
    ensure_container
    prepare_apt
    refresh_repo

    mapfile -t entries < <(read_build_entries)
    if [[ -n "${FROM_ENTRY}" ]]; then
        local filtered=()
        local seen=0
        for entry in "${entries[@]}"; do
            [[ "${entry}" == "${FROM_ENTRY}" ]] && seen=1
            [[ "${seen}" == 1 ]] && filtered+=("${entry}")
        done
        entries=("${filtered[@]}")
    fi

    local failures=()
    for entry in "${entries[@]}"; do
        if ! build_entry "${entry}"; then
            failures+=("${entry}")
            [[ "${KEEP_GOING}" == 1 ]] || break
        fi
    done

    echo ""
    echo "==> Repository: ${REPO_DIR}"
    echo "    ppc64el debs: $(find "${REPO_DIR}/ppc64el" -type f -name '*.deb' | wc -l)"
    echo "    all debs:     $(find "${REPO_DIR}/all" -type f -name '*.deb' | wc -l)"
    echo "    sources:      $(find "${REPO_DIR}/source" -maxdepth 1 -type f -name '*.dsc' | wc -l)"
    if [[ "${#failures[@]}" -gt 0 ]]; then
        echo "    failures:     ${#failures[@]}"
        printf "      %s\n" "${failures[@]}"
        return 1
    fi
}

main "$@"
