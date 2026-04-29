#!/bin/bash
# Validate Ubuntu 24.04 ppc64el packages from the public VersatusHPC APT repo.
# Runs natively on a ppc64le host and uses a disposable Ubuntu container.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-https://repos.versatushpc.com.br/openhpc/versatushpc-4}"
REPO_CHANNEL="${REPO_CHANNEL:-updates}"
IMAGE="${IMAGE:-ubuntu:24.04}"
CONTAINER="${CONTAINER:-ubuntu2404-ppc64el-public-validation}"
WORKDIR="${WORKDIR:-/tmp/ohpc-ppc64el-public-smoke}"
INSTALL_META=1
FULL_LDD=0

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --repo-root URL     Repository root (default: ${REPO_ROOT})
  --repo-channel NAME Repository channel under the root (default: ${REPO_CHANNEL})
  --image NAME       Ubuntu container image (default: ${IMAGE})
  --container NAME   Temporary validation container name (default: ${CONTAINER})
  --workdir PATH     In-container smoke-test workdir (default: ${WORKDIR})
  --skip-meta        Install only compiler/MPI packages, not OpenHPC meta packages
  --full-ldd         Run a full missing-library audit over installed /opt/ohpc ELF files
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-root) REPO_ROOT="$2"; shift 2 ;;
        --repo-channel) REPO_CHANNEL="$2"; shift 2 ;;
        --image) IMAGE="$2"; shift 2 ;;
        --container) CONTAINER="$2"; shift 2 ;;
        --workdir) WORKDIR="$2"; shift 2 ;;
        --skip-meta) INSTALL_META=0; shift ;;
        --full-ldd) FULL_LDD=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ "$(uname -m)" != "ppc64le" ]]; then
    echo "Error: this validation must run on a native ppc64le host" >&2
    exit 1
fi

command -v podman >/dev/null 2>&1 || { echo "Error: podman not found" >&2; exit 1; }

podman rm -f "${CONTAINER}" >/dev/null 2>&1 || true
podman run --rm -i --name "${CONTAINER}" \
    -e OHPC_REPO_ROOT="${REPO_ROOT}" \
    -e OHPC_REPO_CHANNEL="${REPO_CHANNEL}" \
    -e OHPC_SMOKE_WORKDIR="${WORKDIR}" \
    -e OHPC_INSTALL_META="${INSTALL_META}" \
    -e OHPC_FULL_LDD="${FULL_LDD}" \
    "${IMAGE}" bash -s <<'EOF'
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
repo_root="${OHPC_REPO_ROOT%/}"
repo_channel="${OHPC_REPO_CHANNEL#/}"
repo_channel="${repo_channel%/}"
repo_base="${repo_root}"
if [[ -n "${repo_channel}" ]]; then
    repo_base="${repo_root}/${repo_channel}"
fi
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

verify_no_missing_deps() {
    local label=$1 path=$2 out resolved
    resolved=$(readlink -f "${path}") || die "failed to resolve ${label}: ${path}"
    out=$(ldd "${resolved}" 2>&1 || true)
    if printf '%s\n' "${out}" | grep -q 'not found'; then
        printf '%s\n' "${out}" >&2
        die "${label} has unresolved shared libraries"
    fi
    echo "ldd ok: ${label} (${resolved})"
}

installed_version() {
    dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}

installed_version_required() {
    local pkg=$1 expected=$2 value
    value=$(installed_version "${pkg}")
    [[ -n "${value}" ]] || die "${pkg} is not installed"
    [[ "${value}" == "${expected}"* ]] || die "${pkg} installed version ${value} does not start with ${expected}"
    printf '%-34s %s\n' "${pkg}" "${value}"
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

selected_ldd_audit() {
    section "Selected ldd audit"

    module purge
    module load gnu15/15.2.0
    for path in \
        /opt/ohpc/pub/compiler/gcc/15.2.0/bin/gcc \
        /opt/ohpc/pub/compiler/gcc/15.2.0/bin/gfortran; do
        [[ -e "${path}" ]] || die "expected audit path missing: ${path}"
        verify_no_missing_deps "${path}" "${path}"
    done

    module purge
    module load gnu15/15.2.0 mpich/5.0.1
    for path in \
        /opt/ohpc/pub/mpi/mpich-ofi-gnu15-ohpc/5.0.1/bin/mpicc \
        /opt/ohpc/pub/mpi/mpich-ofi-gnu15-ohpc/5.0.1/lib/libmpi.so; do
        [[ -e "${path}" ]] || die "expected audit path missing: ${path}"
        verify_no_missing_deps "${path}" "${path}"
    done

    module purge
    module load gnu15/15.2.0 mvapich2/4.1
    for path in \
        /opt/ohpc/pub/mpi/mvapich2-gnu15/4.1/bin/mpicc \
        /opt/ohpc/pub/mpi/mvapich2-gnu15/4.1/lib/libmpi.so; do
        [[ -e "${path}" ]] || die "expected audit path missing: ${path}"
        verify_no_missing_deps "${path}" "${path}"
    done

    module purge
    module load gnu15/15.2.0 openmpi5/5.0.10
    for path in \
        /opt/ohpc/pub/mpi/openmpi5-gnu15/5.0.10/bin/mpicc \
        /opt/ohpc/pub/mpi/openmpi5-gnu15/5.0.10/lib/libmpi.so; do
        [[ -e "${path}" ]] || die "expected audit path missing: ${path}"
        verify_no_missing_deps "${path}" "${path}"
    done

    module purge
    module load gnu15/15.2.0 openblas/0.3.32
    verify_no_missing_deps openblas /opt/ohpc/pub/libs/gnu15/openblas/0.3.32/lib/libopenblas.so
}

ohpc_ld_library_path_for() {
    local item=$1 dir
    local -a dirs=()
    local -A seen=()

    add_dir() {
        [[ -d "$1" ]] || return 0
        [[ -z "${seen[$1]+x}" ]] || return 0
        dirs+=("$1")
        seen[$1]=1
    }

    dir=$(dirname "${item}")
    while [[ "${dir}" == /opt/ohpc/pub* && "${dir}" != /opt/ohpc/pub ]]; do
        if compgen -G "${dir}/*.so*" >/dev/null; then
            add_dir "${dir}"
        fi
        add_dir "${dir}/lib"
        add_dir "${dir}/lib64"
        dir=$(dirname "${dir}")
    done

    case "${item}" in
        *mpich-ofi-gnu15-ohpc/5.0.1*|*mpich*)
            add_dir /opt/ohpc/pub/mpi/mpich-ofi-gnu15-ohpc/5.0.1/lib
            while IFS= read -r dir; do add_dir "${dir}"; done < <(find /opt/ohpc/pub/libs/gnu15/mpich -type d \( -name lib -o -name lib64 \) -print 2>/dev/null | sort)
            ;;
    esac
    case "${item}" in
        *mvapich2-gnu15/4.1*|*mvapich2*)
            add_dir /opt/ohpc/pub/mpi/mvapich2-gnu15/4.1/lib
            while IFS= read -r dir; do add_dir "${dir}"; done < <(find /opt/ohpc/pub/libs/gnu15/mvapich2 -type d \( -name lib -o -name lib64 \) -print 2>/dev/null | sort)
            ;;
    esac
    case "${item}" in
        *openmpi5-gnu15/5.0.10*|*openmpi5*)
            add_dir /opt/ohpc/pub/mpi/openmpi5-gnu15/5.0.10/lib
            while IFS= read -r dir; do add_dir "${dir}"; done < <(find /opt/ohpc/pub/libs/gnu15/openmpi5 -type d \( -name lib -o -name lib64 \) -print 2>/dev/null | sort)
            ;;
    esac

    while IFS= read -r dir; do
        add_dir "${dir}"
    done < <(find /opt/ohpc/pub -type d \( -name lib -o -name lib64 \) -print 2>/dev/null | sort)

    if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
        IFS=: read -r -a current_dirs <<<"${LD_LIBRARY_PATH}"
        for dir in "${current_dirs[@]}"; do
            add_dir "${dir}"
        done
    fi

    local IFS=:
    printf '%s\n' "${dirs[*]}"
}

full_ldd_audit() {
    section "Full /opt/ohpc ldd audit"
    local failed=0
    local path audit_path out
    while IFS= read -r path; do
        audit_path=$(ohpc_ld_library_path_for "${path}")
        case "${path}" in
            *.so|*.so.*|*.cpython-*.so)
                out=$(LD_LIBRARY_PATH="${audit_path}" ldd "${path}" 2>&1 || true)
                ;;
            *)
                out=$(LD_LIBRARY_PATH="${audit_path}" ldd -r "${path}" 2>&1 || true)
                ;;
        esac
        if printf '%s\n' "${out}" | grep -E 'not found|undefined symbol' >/dev/null; then
            printf '%s\n' "${out}" >&2
            echo "unresolved dependency/symbol: ${path}" >&2
            failed=1
        fi
    done < <(find /opt/ohpc/pub -type f \( -perm /111 -o -name '*.so' -o -name '*.so.*' \) -print | while read -r item; do file "${item}" | grep -q 'ELF' && echo "${item}"; done)
    [[ "${failed}" == "0" ]] || die "full ldd audit failed"
}

section "Configure public repository"
apt-get update -qq
apt-get install -y --no-install-recommends ca-certificates curl file gpg
install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d
cat >/etc/apt/apt.conf.d/99versatushpc-validation-cache <<'APT'
Acquire::http::No-Cache "true";
Acquire::https::No-Cache "true";
Acquire::http::No-Store "true";
Acquire::https::No-Store "true";
Acquire::CompressionTypes::Order { "xz"; "gz"; };
APT
curl -fsSL "${repo_root}/versatushpc.gpg" -o /usr/share/keyrings/versatushpc.gpg
sources_file=/etc/apt/sources.list.d/versatushpc-openhpc.list
cat >"${sources_file}" <<SRC
# VersatusHPC OpenHPC 4.x for Ubuntu 24.04 LTS
deb [signed-by=/usr/share/keyrings/versatushpc.gpg] ${repo_root}/Ubuntu_24.04/ ./
SRC
if [[ -n "${repo_channel}" ]]; then
    cat >>"${sources_file}" <<SRC
deb [signed-by=/usr/share/keyrings/versatushpc.gpg] ${repo_base}/Ubuntu_24.04/ ./
SRC
fi
cat "${sources_file}"
apt-get update -qq

section "Install packages"
packages=(
    lmod-ohpc
    gnu15-compilers-ohpc
    openblas-gnu15-ohpc
    mpich-gnu15-ohpc
    mvapich2-gnu15-ohpc
    openmpi5-gnu15-ohpc
    likwid-gnu15-ohpc
)
if [[ "${OHPC_INSTALL_META}" == "1" ]]; then
    packages+=(
        ohpc-gnu15-serial-libs
        ohpc-gnu15-runtimes
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
    )
fi
apt-get install -y --no-install-recommends "${packages[@]}"
dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' "${packages[@]}" | sort

section "Installed repaired library versions"
for stack in mpich mvapich2 openmpi5; do
    installed_version_required "mfem-gnu15-${stack}-ohpc" "4.9-1ohpc2"
    installed_version_required "mumps-gnu15-${stack}-ohpc" "5.8.2-1ohpc2"
done

set +u
. /opt/ohpc/admin/lmod/lmod/init/bash
set -u
module use /opt/ohpc/pub/modulefiles
write_sources

run_stack mpich mpich/5.0.1 /opt/ohpc/pub/mpi/mpich-ofi-gnu15-ohpc/5.0.1 'HYDRA_LAUNCHER=fork FI_PROVIDER=tcp'
run_stack mvapich2 mvapich2/4.1 /opt/ohpc/pub/mpi/mvapich2-gnu15/4.1 'MV2_ENABLE_AFFINITY=0 MV2_SMP_USE_CMA=0'
run_stack openmpi5 openmpi5/5.0.10 /opt/ohpc/pub/mpi/openmpi5-gnu15/5.0.10 'OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 OMPI_MCA_pml=ob1 OMPI_MCA_btl=self,tcp'
verify_likwid
selected_ldd_audit

if [[ "${OHPC_FULL_LDD}" == "1" ]]; then
    full_ldd_audit
fi

section "Result"
echo "Ubuntu ppc64el public repository GNU15 MPI, LIKWID, and linkage validation passed."
EOF
