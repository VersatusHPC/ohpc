#!/bin/bash
# Validate the native Ubuntu 24.04 ppc64el core MPI packages produced by
# scripts/build-ubuntu-ppc64el.sh. This runs on the POWER builder host and
# executes the smoke test in a disposable Ubuntu ppc64el container backed by
# the generated local APT repository.

set -euo pipefail

IMAGE="${IMAGE:-ubuntu2404-ppc64el-ohpc-builder}"
WORK_ROOT="${WORK_ROOT:-${HOME}/ohpc-ubuntu-ppc64el}"
REPO_DIR="${REPO_DIR:-${WORK_ROOT}/repo/Ubuntu_24.04}"
CONTAINER="${CONTAINER:-ubuntu2404-ppc64el-validation}"
WORKDIR="${WORKDIR:-/tmp/ohpc-ppc64el-smoke}"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --image NAME       Builder image to use (default: ${IMAGE})
  --repo-dir PATH    Local APT repository to mount (default: ${REPO_DIR})
  --container NAME   Temporary validation container name (default: ${CONTAINER})
  --workdir PATH     In-container smoke-test workdir (default: ${WORKDIR})
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --image) IMAGE="$2"; shift 2 ;;
        --repo-dir) REPO_DIR="$2"; shift 2 ;;
        --container) CONTAINER="$2"; shift 2 ;;
        --workdir) WORKDIR="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ "$(uname -m)" != "ppc64le" ]]; then
    echo "Error: this validation must run on the native ppc64le builder" >&2
    exit 1
fi

command -v podman >/dev/null 2>&1 || { echo "Error: podman not found" >&2; exit 1; }
podman image exists "${IMAGE}" || { echo "Error: image not found: ${IMAGE}" >&2; exit 1; }
[[ -d "${REPO_DIR}" ]] || { echo "Error: repo directory not found: ${REPO_DIR}" >&2; exit 1; }
find "${REPO_DIR}" -type f -name '*.deb' -print -quit | grep -q . || {
    echo "Error: no .deb packages found under ${REPO_DIR}" >&2
    exit 1
}

podman rm -f "${CONTAINER}" >/dev/null 2>&1 || true
podman run --rm -i --name "${CONTAINER}" \
    -e OHPC_SMOKE_WORKDIR="${WORKDIR}" \
    -v "${REPO_DIR}:/repo:z" \
    "${IMAGE}" bash -s <<'EOF'
set -euo pipefail

workdir="${OHPC_SMOKE_WORKDIR}"
mkdir -p "${workdir}"

section() {
    printf '\n== %s ==\n' "$*"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

require_prefix() {
    local label=$1 path=$2 prefix=$3
    case "${path}" in
        "${prefix}"|"${prefix}"/*) ;;
        *) die "${label} path ${path} is outside expected prefix ${prefix}" ;;
    esac
}

write_sources() {
    cat >"${workdir}/mpi-hello.c" <<'SRC'
#include <mpi.h>
#include <stdio.h>
int main(int argc, char **argv) {
    int rank, size;
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    printf("C hello from rank %d/%d\n", rank, size);
    MPI_Finalize();
    return 0;
}
SRC
    cat >"${workdir}/mpi-hello.f90" <<'SRC'
program hello
  use mpi
  implicit none
  integer :: ierr, rank, size
  call MPI_Init(ierr)
  call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
  call MPI_Comm_size(MPI_COMM_WORLD, size, ierr)
  print *, 'Fortran hello from rank', rank, '/', size
  call MPI_Finalize(ierr)
end program hello
SRC
}

verify_ldd_contains() {
    local label=$1 binary=$2 expected=$3
    local ldd_out
    ldd_out=$(ldd "${binary}") || die "ldd failed for ${label}"
    printf '%s\n' "${ldd_out}" | grep -F "${expected}" >/dev/null || {
        printf '%s\n' "${ldd_out}" >&2
        die "${label} is not linked against ${expected}"
    }
    printf 'ldd %s matched %s\n' "${label}" "${expected}"
}

mpicc_show() {
    mpicc --showme:command 2>/dev/null || mpicc -show 2>/dev/null || mpicc -showme 2>/dev/null || true
}

run_stack() {
    local name=$1 module_name=$2 expected_mpi=$3 run_env=${4:-}
    local c_exe="${workdir}/hello-c-${name}"
    local f_exe="${workdir}/hello-f-${name}"

    section "${name}"
    module purge
    module load gnu15/15.2.0 "${module_name}"

    require_prefix gcc "$(command -v gcc)" /opt/ohpc/pub/compiler/gcc/15.2.0/bin
    require_prefix gfortran "$(command -v gfortran)" /opt/ohpc/pub/compiler/gcc/15.2.0/bin
    require_prefix mpicc "$(command -v mpicc)" "${expected_mpi}/bin"
    require_prefix mpifort "$(command -v mpifort)" "${expected_mpi}/bin"
    require_prefix MPI_DIR "${MPI_DIR:-}" "${expected_mpi}"

    gcc -dumpfullversion -dumpversion | grep -E '^15\.2\.0' >/dev/null || die "GNU15 gcc version mismatch"
    printf 'mpicc wrapper: %s\n' "$(mpicc_show)"

    mpicc "${workdir}/mpi-hello.c" -o "${c_exe}"
    mpifort "${workdir}/mpi-hello.f90" -o "${f_exe}"
    verify_ldd_contains "${name} C" "${c_exe}" "${expected_mpi}"
    verify_ldd_contains "${name} Fortran MPI" "${f_exe}" "${expected_mpi}"
    verify_ldd_contains "${name} Fortran compiler" "${f_exe}" /opt/ohpc/pub/compiler/gcc/15.2.0

    if [[ -n "${run_env}" ]]; then
        env ${run_env} mpirun -np 2 "${c_exe}" </dev/null | sort
        env ${run_env} mpirun -np 2 "${f_exe}" </dev/null | sort
    else
        mpirun -np 2 "${c_exe}" </dev/null | sort
        mpirun -np 2 "${f_exe}" </dev/null | sort
    fi
}

section "Configure local repository"
echo "deb [trusted=yes] file:/repo ./" > /etc/apt/sources.list.d/openhpc-local.list
apt-get update -qq

section "Install packages"
apt-get install -y --no-install-recommends \
    lmod-ohpc \
    gnu15-compilers-ohpc \
    openblas-gnu15-ohpc \
    mpich-gnu15-ohpc \
    mvapich2-gnu15-ohpc \
    openmpi5-gnu15-ohpc

set +u
. /opt/ohpc/admin/lmod/lmod/init/bash
set -u
module use /opt/ohpc/pub/modulefiles
write_sources

run_stack mpich mpich/5.0.1 /opt/ohpc/pub/mpi/mpich-ofi-gnu15-ohpc/5.0.1 'HYDRA_LAUNCHER=fork FI_PROVIDER=tcp'
run_stack mvapich2 mvapich2/4.1 /opt/ohpc/pub/mpi/mvapich2-gnu15/4.1 'MV2_ENABLE_AFFINITY=0 MV2_SMP_USE_CMA=0'
run_stack openmpi5 openmpi5/5.0.10 /opt/ohpc/pub/mpi/openmpi5-gnu15/5.0.10 'OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1'

section "Result"
echo "Ubuntu ppc64el GNU15 MPI core validation passed."
EOF
