#!/bin/bash
# Validate VersatusHPC OpenHPC POWER RPM runtime packages from the public repo.
# Runs natively on a ppc64le host and uses disposable EL10/openEuler containers.

set -euo pipefail

TARGET="all"
EL10_IMAGE="${EL10_IMAGE:-almalinux:10}"
OE_IMAGE="${OE_IMAGE:-localhost/oe2403-ohpc-builder:latest}"
CONTAINER_PREFIX="${CONTAINER_PREFIX:-ohpc-rpm-ppc64le-validation}"
WORKDIR="${WORKDIR:-/tmp/ohpc-rpm-ppc64le-smoke}"
INSTALL_META=1
FULL_LDD=0

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --target el10|openeuler|all  Target repository to validate (default: ${TARGET})
  --el10-image IMAGE           EL10 container image (default: ${EL10_IMAGE})
  --openeuler-image IMAGE      openEuler container image (default: ${OE_IMAGE})
  --container-prefix NAME      Temporary container name prefix (default: ${CONTAINER_PREFIX})
  --workdir PATH               In-container test workdir (default: ${WORKDIR})
  --skip-meta                  Install only compiler/MPI packages, not OpenHPC meta packages
  --full-ldd                   Run ldd -r over selected installed /opt/ohpc ELF files
  -h, --help                   Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --el10-image) EL10_IMAGE="$2"; shift 2 ;;
        --openeuler-image) OE_IMAGE="$2"; shift 2 ;;
        --container-prefix) CONTAINER_PREFIX="$2"; shift 2 ;;
        --workdir) WORKDIR="$2"; shift 2 ;;
        --skip-meta) INSTALL_META=0; shift ;;
        --full-ldd) FULL_LDD=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ "$(uname -m)" != "ppc64le" ]]; then
    echo "Error: this validation must run on the native ppc64le builder" >&2
    exit 1
fi

command -v podman >/dev/null 2>&1 || { echo "Error: podman not found" >&2; exit 1; }

run_target() {
    local target=$1 image=$2 repo_url=$3
    local container="${CONTAINER_PREFIX}-${target}"

    echo "==> ${target}: validating ${repo_url} with image ${image}"
    podman rm -f "${container}" >/dev/null 2>&1 || true
    podman run --rm -i --name "${container}" --privileged \
        -e OHPC_TARGET="${target}" \
        -e OHPC_REPO_URL="${repo_url}" \
        -e OHPC_WORKDIR="${WORKDIR}" \
        -e OHPC_INSTALL_META="${INSTALL_META}" \
        -e OHPC_FULL_LDD="${FULL_LDD}" \
        "${image}" bash -s <<'EOF'
set -euo pipefail

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

write_repo_file() {
    install -d -m 0755 /etc/yum.repos.d
    cat >/etc/yum.repos.d/versatushpc-openhpc.repo <<REPO
[versatushpc-openhpc]
name=VersatusHPC OpenHPC 4.x POWER validation
baseurl=${OHPC_REPO_URL}
enabled=1
gpgcheck=1
gpgkey=https://repos.versatushpc.com.br/openhpc/versatushpc-4/RPM-GPG-KEY-VersatusHPC
REPO
    rpm --import https://repos.versatushpc.com.br/openhpc/versatushpc-4/RPM-GPG-KEY-VersatusHPC
}

prepare_os() {
    section "Prepare ${OHPC_TARGET} container"
    if [[ "${OHPC_TARGET}" == "el10" ]]; then
        dnf -y install dnf-plugins-core epel-release ca-certificates curl findutils which file hostname procps-ng
        dnf config-manager --set-enabled crb || true
    else
        if [[ -f /etc/yum.repos.d/openEuler.repo ]]; then
            sed -i 's@repo.openeuler.org@repo.huaweicloud.com/openeuler@g' /etc/yum.repos.d/openEuler.repo
        fi
        dnf -y install ca-certificates curl findutils which file hostname procps-ng
    fi
    update-ca-trust 2>/dev/null || true
    remove_preinstalled_openhpc
    write_repo_file
    dnf clean all
    dnf -y makecache
}

remove_preinstalled_openhpc() {
    section "Remove preinstalled OpenHPC packages"
    mapfile -t packages < <(rpm -qa --qf '%{NAME}\n' | sort -u | grep -E '(^ohpc-|-ohpc$)' || true)
    if ((${#packages[@]} == 0)); then
        echo "No preinstalled OpenHPC packages found."
        return 0
    fi
    printf 'Removing %d packages: %s\n' "${#packages[@]}" "${packages[*]}"
    dnf -y remove "${packages[@]}"
}

install_packages() {
    section "Install OpenHPC packages"
    local packages=(
        lmod-ohpc
        gnu15-compilers-ohpc
        openblas-gnu15-ohpc
        mpich-ofi-gnu15-ohpc
        mvapich2-gnu15-ohpc
        openmpi5-gnu15-ohpc
        likwid-gnu15-ohpc
    )

    if [[ "${OHPC_INSTALL_META}" == "1" ]]; then
        packages+=(
            ohpc-gnu15-serial-libs
            ohpc-gnu15-runtimes
            ohpc-gnu15-io-libs
            ohpc-gnu15-parallel-libs
            ohpc-gnu15-perf-tools
            ohpc-gnu15-openmpi5-io-libs
            ohpc-gnu15-openmpi5-parallel-libs
            ohpc-gnu15-openmpi5-perf-tools
        )
    fi

    dnf -y install "${packages[@]}"
    rpm -q "${packages[@]}" | sort
}

write_sources() {
    mkdir -p "${OHPC_WORKDIR}"
    cat >"${OHPC_WORKDIR}/mpi-hello.c" <<'SRC'
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
    cat >"${OHPC_WORKDIR}/mpi-hello.f90" <<'SRC'
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

verify_no_missing_deps() {
    local label=$1 path=$2 out resolved
    resolved=$(readlink -f "${path}") || die "failed to resolve ${label}: ${path}"
    if ! file "${resolved}" | grep -q 'ELF'; then
        echo "ldd skipped non-ELF: ${label} (${path})"
        return 0
    fi
    out=$(ldd "${resolved}" 2>&1 || true)
    if printf '%s
' "${out}" | grep -q 'not found'; then
        printf '%s
' "${out}" >&2
        die "${label} has unresolved shared libraries"
    fi
    echo "ldd ok: ${label} (${resolved})"
}

verify_likwid() {
    section "LIKWID smoke"
    module purge
    module load gnu15/15.2.0 likwid/5.5.1
    require_prefix likwid-topology "$(command -v likwid-topology)" /opt/ohpc/pub/libs/gnu15/likwid/5.5.1/bin
    require_prefix likwid-perfctr "$(command -v likwid-perfctr)" /opt/ohpc/pub/libs/gnu15/likwid/5.5.1/bin
    likwid-topology -h >/dev/null
    likwid-perfctr -h >/dev/null
    verify_no_missing_deps likwid-topology "$(command -v likwid-topology)"
    verify_no_missing_deps likwid-perfctr "$(command -v likwid-perfctr)"
}

run_stack() {
    local name=$1 module_name=$2 expected_mpi=$3 run_env=${4:-}
    local c_exe="${OHPC_WORKDIR}/hello-c-${name}"
    local f_exe="${OHPC_WORKDIR}/hello-f-${name}"

    section "${name}"
    module purge
    module load gnu15/15.2.0 "${module_name}"

    require_prefix gcc "$(command -v gcc)" /opt/ohpc/pub/compiler/gcc/15.2.0/bin
    require_prefix gfortran "$(command -v gfortran)" /opt/ohpc/pub/compiler/gcc/15.2.0/bin
    require_prefix mpicc "$(command -v mpicc)" "${expected_mpi}/bin"
    require_prefix mpifort "$(command -v mpifort)" "${expected_mpi}/bin"
    require_prefix MPI_DIR "${MPI_DIR:-}" "${expected_mpi}"

    gcc -dumpfullversion -dumpversion | grep -E '^15\.2\.0' >/dev/null || die "GNU15 gcc version mismatch"
    mpicc "${OHPC_WORKDIR}/mpi-hello.c" -o "${c_exe}"
    mpifort "${OHPC_WORKDIR}/mpi-hello.f90" -o "${f_exe}"

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

selected_ldd_audit() {
    section "Selected ldd audit"

    module purge
    module load gnu15/15.2.0
    local compiler_paths=(
        /opt/ohpc/pub/compiler/gcc/15.2.0/bin/gcc
        /opt/ohpc/pub/compiler/gcc/15.2.0/bin/gfortran
    )
    local path
    for path in "${compiler_paths[@]}"; do
        [[ -e "${path}" ]] || die "expected audit path missing: ${path}"
        verify_no_missing_deps "${path}" "${path}"
    done

    module purge
    module load gnu15/15.2.0 mpich/5.0.0-ofi
    local mpich_paths=(
        /opt/ohpc/pub/mpi/mpich-ofi-gnu15-ohpc/5.0.0/bin/mpicc
        /opt/ohpc/pub/mpi/mpich-ofi-gnu15-ohpc/5.0.0/lib/libmpi.so
    )
    for path in "${mpich_paths[@]}"; do
        [[ -e "${path}" ]] || die "expected audit path missing: ${path}"
        verify_no_missing_deps "${path}" "${path}"
    done

    module purge
    module load gnu15/15.2.0 mvapich2/2.3.7
    local mvapich2_paths=(
        /opt/ohpc/pub/mpi/mvapich2-gnu15/2.3.7/bin/mpicc
        /opt/ohpc/pub/mpi/mvapich2-gnu15/2.3.7/lib/libmpi.so
    )
    for path in "${mvapich2_paths[@]}"; do
        [[ -e "${path}" ]] || die "expected audit path missing: ${path}"
        verify_no_missing_deps "${path}" "${path}"
    done

    module purge
    module load gnu15/15.2.0 openmpi5/5.0.10
    local openmpi_paths=(
        /opt/ohpc/pub/mpi/openmpi5-gnu15/5.0.10/bin/mpicc
        /opt/ohpc/pub/mpi/openmpi5-gnu15/5.0.10/lib/libmpi.so
    )
    for path in "${openmpi_paths[@]}"; do
        [[ -e "${path}" ]] || die "expected audit path missing: ${path}"
        verify_no_missing_deps "${path}" "${path}"
    done

    module purge
    module load gnu15/15.2.0 openblas/0.3.32
    local openblas_paths=(
        /opt/ohpc/pub/libs/gnu15/openblas/0.3.32/lib/libopenblas.so
    )
    for path in "${openblas_paths[@]}"; do
        [[ -e "${path}" ]] || die "expected audit path missing: ${path}"
        verify_no_missing_deps "${path}" "${path}"
    done

    module purge
    module load gnu15/15.2.0 likwid/5.5.1
    local likwid_paths=(
        /opt/ohpc/pub/libs/gnu15/likwid/5.5.1/bin/likwid-topology
    )
    for path in "${likwid_paths[@]}"; do
        [[ -e "${path}" ]] || die "expected audit path missing: ${path}"
        verify_no_missing_deps "${path}" "${path}"
    done
}

full_ldd_audit() {
    section "Full /opt/ohpc ldd -r audit"
    local failed=0
    while IFS= read -r path; do
        if ! ldd -r "${path}" >/tmp/ldd.out 2>&1; then
            cat /tmp/ldd.out >&2
            echo "ldd -r failed: ${path}" >&2
            failed=1
            continue
        fi
        if grep -E 'not found|undefined symbol' /tmp/ldd.out >/dev/null; then
            cat /tmp/ldd.out >&2
            echo "unresolved dependency/symbol: ${path}" >&2
            failed=1
        fi
    done < <(find /opt/ohpc/pub -type f \( -perm /111 -o -name '*.so' -o -name '*.so.*' \) -print | while read -r item; do file "${item}" | grep -q 'ELF' && echo "${item}"; done)
    [[ "${failed}" == "0" ]] || die "full ldd audit failed"
}

prepare_os
install_packages

set +u
. /opt/ohpc/admin/lmod/lmod/init/bash
set -u
module use /opt/ohpc/pub/modulefiles
write_sources

run_stack mpich mpich/5.0.0-ofi /opt/ohpc/pub/mpi/mpich-ofi-gnu15-ohpc/5.0.0 'HYDRA_LAUNCHER=fork FI_PROVIDER=tcp'
run_stack mvapich2 mvapich2/2.3.7 /opt/ohpc/pub/mpi/mvapich2-gnu15/2.3.7 'MV2_ENABLE_AFFINITY=0 MV2_SMP_USE_CMA=0'
run_stack openmpi5 openmpi5/5.0.10 /opt/ohpc/pub/mpi/openmpi5-gnu15/5.0.10 'OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 OMPI_MCA_pml=ob1 OMPI_MCA_btl=self,tcp'
verify_likwid
selected_ldd_audit

if [[ "${OHPC_FULL_LDD}" == "1" ]]; then
    full_ldd_audit
fi

section "Result"
echo "${OHPC_TARGET} ppc64le GNU15 MPI, LIKWID, and linkage validation passed."
EOF
}

case "${TARGET}" in
    el10) run_target el10 "${EL10_IMAGE}" "https://repos.versatushpc.com.br/openhpc/versatushpc-4/EL_10/" ;;
    openeuler) run_target openeuler "${OE_IMAGE}" "https://repos.versatushpc.com.br/openhpc/versatushpc-4/openEuler_24.03/" ;;
    all)
        run_target el10 "${EL10_IMAGE}" "https://repos.versatushpc.com.br/openhpc/versatushpc-4/EL_10/"
        run_target openeuler "${OE_IMAGE}" "https://repos.versatushpc.com.br/openhpc/versatushpc-4/openEuler_24.03/"
        ;;
    *) echo "Unknown target: ${TARGET}" >&2; usage >&2; exit 2 ;;
esac
