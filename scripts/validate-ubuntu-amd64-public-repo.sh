#!/bin/bash
# Validate Ubuntu 24.04 amd64 packages from the public VersatusHPC APT repo.
# Runs on an amd64 host and uses a disposable Ubuntu container.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-https://repos.versatushpc.com.br/openhpc/versatushpc-4}"
REPO_CHANNEL="${REPO_CHANNEL:-updates}"
IMAGE="${IMAGE:-ubuntu:24.04}"
CONTAINER="${CONTAINER:-ubuntu2404-amd64-public-validation}"
WORKDIR="${WORKDIR:-/tmp/ohpc-amd64-public-smoke}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-}"
RUN_GNU=1
RUN_INTEL=auto
FULL_LDD=0

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --repo-root URL      Repository root (default: ${REPO_ROOT})
  --repo-channel NAME  Repository channel under the root (default: ${REPO_CHANNEL})
  --image NAME        Ubuntu container image (default: ${IMAGE})
  --container NAME    Temporary validation container name (default: ${CONTAINER})
  --workdir PATH      In-container smoke-test workdir (default: ${WORKDIR})
  --container-engine  docker or podman (default: auto-detect)
  --skip-gnu          Do not run GNU15 MPI validation
  --with-intel        Require and run oneAPI/Intel MPI validation
  --skip-intel        Do not run oneAPI/Intel MPI validation
  --full-ldd          Run a full missing-library audit over installed /opt/ohpc ELF files
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-root) REPO_ROOT="$2"; shift 2 ;;
        --repo-channel) REPO_CHANNEL="$2"; shift 2 ;;
        --image) IMAGE="$2"; shift 2 ;;
        --container) CONTAINER="$2"; shift 2 ;;
        --workdir) WORKDIR="$2"; shift 2 ;;
        --container-engine) CONTAINER_ENGINE="$2"; shift 2 ;;
        --skip-gnu) RUN_GNU=0; shift ;;
        --with-intel) RUN_INTEL=1; shift ;;
        --skip-intel) RUN_INTEL=0; shift ;;
        --full-ldd) FULL_LDD=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "Error: this validation must run on a native x86_64/amd64 host" >&2
    exit 1
fi

if [[ -z "${CONTAINER_ENGINE}" ]]; then
    if command -v docker >/dev/null 2>&1; then
        CONTAINER_ENGINE=docker
    elif command -v podman >/dev/null 2>&1; then
        CONTAINER_ENGINE=podman
    else
        echo "Error: neither docker nor podman found" >&2
        exit 1
    fi
fi

case "${CONTAINER_ENGINE}" in
    docker)
        docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
        docker run --rm -i --platform linux/amd64 --name "${CONTAINER}" \
            -e OHPC_REPO_ROOT="${REPO_ROOT}" \
            -e OHPC_REPO_CHANNEL="${REPO_CHANNEL}" \
            -e OHPC_SMOKE_WORKDIR="${WORKDIR}" \
            -e OHPC_RUN_GNU="${RUN_GNU}" \
            -e OHPC_RUN_INTEL="${RUN_INTEL}" \
            -e OHPC_FULL_LDD="${FULL_LDD}" \
            "${IMAGE}" bash -s
        ;;
    podman)
        podman rm -f "${CONTAINER}" >/dev/null 2>&1 || true
        podman run --rm -i --arch amd64 --name "${CONTAINER}" \
            -e OHPC_REPO_ROOT="${REPO_ROOT}" \
            -e OHPC_REPO_CHANNEL="${REPO_CHANNEL}" \
            -e OHPC_SMOKE_WORKDIR="${WORKDIR}" \
            -e OHPC_RUN_GNU="${RUN_GNU}" \
            -e OHPC_RUN_INTEL="${RUN_INTEL}" \
            -e OHPC_FULL_LDD="${FULL_LDD}" \
            "${IMAGE}" bash -s
        ;;
    *)
        echo "Error: unsupported container engine: ${CONTAINER_ENGINE}" >&2
        exit 2
        ;;
esac <<'EOF'
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
run_gnu="${OHPC_RUN_GNU}"
run_intel="${OHPC_RUN_INTEL}"
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

candidate() {
    apt-cache policy "$1" | awk '/Candidate:/ {print $2; exit}'
}

candidate_required() {
    local pkg=$1 value
    value=$(candidate "${pkg}")
    [[ -n "${value}" && "${value}" != "(none)" ]] || die "no APT candidate for ${pkg}"
    printf '%-34s %s\n' "${pkg}" "${value}"
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
    cat >"${workdir}/mpi-hello-mpifh.f90" <<'SRC'
program hello
  include 'mpif.h'
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

mpicc_show() {
    mpicc --showme:command 2>/dev/null || mpicc -show 2>/dev/null || mpicc -showme 2>/dev/null || true
}

mpi_fortran_wrapper() {
    local compiler=$1 mpi_stack=$2 name
    local wrappers=()

    if [[ "${mpi_stack}" == "impi" && "${compiler}" == "Intel" ]]; then
        wrappers=(mpiifort mpiifx mpifort mpif90 mpifc)
    elif [[ "${mpi_stack}" == "impi" ]]; then
        wrappers=(mpifort mpif90 mpifc mpigfortran mpiifort mpiifx)
    else
        wrappers=(mpifort mpif90 mpifc mpiifort mpiifx)
    fi

    for name in "${wrappers[@]}"; do
        if command -v "${name}" >/dev/null 2>&1; then
            command -v "${name}"
            return 0
        fi
    done

    return 1
}

verify_compiler() {
    local compiler=$1 wrapper
    wrapper=$(mpicc_show)
    printf 'mpicc wrapper: %s\n' "${wrapper}"

    case "${compiler}" in
        GNU15)
            require_prefix gcc "$(command -v gcc)" /opt/ohpc/pub/compiler/gcc/15.2.0/bin
            require_prefix gfortran "$(command -v gfortran)" /opt/ohpc/pub/compiler/gcc/15.2.0/bin
            gcc -dumpfullversion -dumpversion | grep -E '^15\.2\.0' >/dev/null || die "GNU15 gcc version mismatch"
            if printf '%s\n' "${wrapper}" | grep -Eq '(^|[[:space:]/])(icx|icc|mpiicc)([[:space:]]|$)'; then
                die "GNU15 MPI wrapper appears to use an Intel compiler: ${wrapper}"
            fi
            ;;
        Intel)
            require_prefix icx "$(command -v icx)" /opt/intel/oneapi/compiler
            require_prefix ifx "$(command -v ifx)" /opt/intel/oneapi/compiler
            if [[ -n "${wrapper}" ]] && ! printf '%s\n' "${wrapper}" | grep -Eq '(^|[[:space:]/])(icx|icc|mpiicc)([[:space:]]|$)'; then
                die "Intel MPI wrapper does not appear to use an Intel compiler: ${wrapper}"
            fi
            ;;
        GNU15-IMPI)
            require_prefix gcc "$(command -v gcc)" /opt/ohpc/pub/compiler/gcc/15.2.0/bin
            require_prefix gfortran "$(command -v gfortran)" /opt/ohpc/pub/compiler/gcc/15.2.0/bin
            ;;
        *)
            die "unknown compiler family: ${compiler}"
            ;;
    esac
}

run_stack() {
    local compiler=$1 compiler_module=$2 name=$3 module_name=$4 expected_mpi=$5 run_env=${6:-}
    local label="${compiler} ${name}"
    local c_exe="${workdir}/hello-c-${compiler}-${name}"
    local f_exe="${workdir}/hello-f-${compiler}-${name}"
    local f_src="${workdir}/mpi-hello.f90"
    local mpifort_wrapper

    section "${label}"
    module purge
    module load "${compiler_module}" "${module_name}"

    verify_compiler "${compiler}"
    require_prefix mpicc "$(command -v mpicc)" "${expected_mpi}/bin"
    mpifort_wrapper=$(mpi_fortran_wrapper "${compiler}" "${name}") || die "no MPI Fortran wrapper found for ${label}"
    echo "MPI Fortran wrapper: ${mpifort_wrapper}"
    require_prefix "MPI Fortran wrapper" "${mpifort_wrapper}" "${expected_mpi}/bin"
    require_prefix MPI_DIR "${MPI_DIR:-}" "${expected_mpi}"

    mpicc "${workdir}/mpi-hello.c" -o "${c_exe}"
    if [[ "${compiler}" == "GNU15-IMPI" ]]; then
        f_src="${workdir}/mpi-hello-mpifh.f90"
    fi
    "${mpifort_wrapper}" "${f_src}" -o "${f_exe}"
    verify_ldd_contains "${label} C" "${c_exe}" "${expected_mpi}"
    verify_ldd_contains "${label} Fortran MPI" "${f_exe}" "${expected_mpi}"
    case "${compiler}" in
        GNU15|GNU15-IMPI) verify_ldd_contains "${label} Fortran compiler" "${f_exe}" /opt/ohpc/pub/compiler/gcc/15.2.0 ;;
        Intel) verify_ldd_contains "${label} Fortran compiler" "${f_exe}" /opt/intel/oneapi/compiler ;;
    esac

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

    if [[ "${run_gnu}" == "1" ]]; then
        module purge
        module load gnu15/15.2.0
        for path in \
            /opt/ohpc/pub/compiler/gcc/15.2.0/bin/gcc \
            /opt/ohpc/pub/compiler/gcc/15.2.0/bin/gfortran; do
            [[ -e "${path}" ]] || die "expected audit path missing: ${path}"
            verify_no_missing_deps "${path}" "${path}"
        done
    fi

    if [[ "${run_intel}" == "1" ]]; then
        module purge
        module load intel/2025.0.4
        for path in "$(command -v icx)" "$(command -v ifx)"; do
            verify_no_missing_deps "${path}" "${path}"
        done
    fi
}

opt_elf_files() {
    local -a roots=()
    local root item
    for root in /opt/ohpc/pub /opt/ohpc/admin; do
        [[ -d "${root}" ]] && roots+=("${root}")
    done
    [[ "${#roots[@]}" -gt 0 ]] || return 0
    find "${roots[@]}" -type f \( -perm /111 -o -name '*.so' -o -name '*.so.*' \) -print 2>/dev/null | while read -r item; do
        file "${item}" | grep -q 'ELF' && echo "${item}"
    done
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

    add_tree_lib_dirs() {
        [[ -d "$1" ]] || return 0
        while IFS= read -r dir; do
            add_dir "${dir}"
        done < <(find "$1" -type d \( -name lib -o -name lib64 \) -print 2>/dev/null | sort)
    }

    add_oneapi_runtime_dirs() {
        add_dir /opt/intel/oneapi/compiler/latest/lib
        add_dir /opt/intel/oneapi/compiler/2025.0/lib
        add_dir /opt/intel/oneapi/mpi/latest/lib
        add_dir /opt/intel/oneapi/mpi/2021.14/lib
    }

    dir=$(dirname "${item}")
    while [[ "${dir}" == /opt/ohpc/* && "${dir}" != /opt/ohpc ]]; do
        if compgen -G "${dir}/*.so*" >/dev/null; then
            add_dir "${dir}"
        fi
        add_dir "${dir}/lib"
        add_dir "${dir}/lib64"
        dir=$(dirname "${dir}")
    done

    case "${item}" in
        *mpi/ucx/1.20.0*)
            add_dir /opt/ohpc/pub/mpi/ucx/1.20.0/lib
            ;;
    esac
    case "${item}" in
        *mpich-ofi-gnu15-ohpc/5.0.1*|*/libs/gnu15/mpich/*|*gnu15-mpich*)
            add_dir /opt/ohpc/pub/mpi/mpich-ofi-gnu15-ohpc/5.0.1/lib
            add_tree_lib_dirs /opt/ohpc/pub/libs/gnu15/mpich
            ;;
    esac
    case "${item}" in
        *mpich-ofi-intel-ohpc/5.0.1*|*/libs/intel/mpich/*|*intel-mpich*)
            add_dir /opt/ohpc/pub/mpi/mpich-ofi-intel-ohpc/5.0.1/lib
            add_tree_lib_dirs /opt/ohpc/pub/libs/intel/mpich
            add_oneapi_runtime_dirs
            ;;
    esac
    case "${item}" in
        *mvapich2-gnu15/4.1*|*/libs/gnu15/mvapich2/*|*gnu15-mvapich2*)
            add_dir /opt/ohpc/pub/mpi/mvapich2-gnu15/4.1/lib
            add_tree_lib_dirs /opt/ohpc/pub/libs/gnu15/mvapich2
            ;;
    esac
    case "${item}" in
        *mvapich2-intel/4.1*|*/libs/intel/mvapich2/*|*intel-mvapich2*)
            add_dir /opt/ohpc/pub/mpi/mvapich2-intel/4.1/lib
            add_tree_lib_dirs /opt/ohpc/pub/libs/intel/mvapich2
            add_oneapi_runtime_dirs
            ;;
    esac
    case "${item}" in
        *openmpi5-gnu15/5.0.10*|*/libs/gnu15/openmpi5/*|*gnu15-openmpi5*)
            add_dir /opt/ohpc/pub/mpi/openmpi5-gnu15/5.0.10/lib
            add_tree_lib_dirs /opt/ohpc/pub/libs/gnu15/openmpi5
            ;;
    esac
    case "${item}" in
        *openmpi5-intel/5.0.10*|*/libs/intel/openmpi5/*|*intel-openmpi5*)
            add_dir /opt/ohpc/pub/mpi/openmpi5-intel/5.0.10/lib
            add_tree_lib_dirs /opt/ohpc/pub/libs/intel/openmpi5
            add_oneapi_runtime_dirs
            ;;
    esac
    case "${item}" in
        */libs/gnu15/impi/*|*gnu15-impi*)
            add_dir /opt/intel/oneapi/mpi/2021.14/lib
            add_dir /opt/intel/oneapi/mpi/latest/lib
            add_tree_lib_dirs /opt/ohpc/pub/libs/gnu15/impi
            ;;
    esac
    case "${item}" in
        */libs/intel/impi/*|*intel-impi*)
            add_dir /opt/intel/oneapi/mpi/2021.14/lib
            add_dir /opt/intel/oneapi/mpi/latest/lib
            add_tree_lib_dirs /opt/ohpc/pub/libs/intel/impi
            add_oneapi_runtime_dirs
            ;;
    esac
    case "${item}" in
        */libs/intel/*)
            add_oneapi_runtime_dirs
            ;;
    esac

    add_tree_lib_dirs /opt/ohpc/pub
    add_tree_lib_dirs /opt/ohpc/admin

    if [[ -n "${LD_LIBRARY_PATH:-}" ]]; then
        IFS=: read -r -a current_dirs <<<"${LD_LIBRARY_PATH}"
        for dir in "${current_dirs[@]}"; do
            add_dir "${dir}"
        done
    fi

    local IFS=:
    printf '%s\n' "${dirs[*]}"
}

stale_dependency_audit() {
    section "Stale dependency audit"
    local failed=0
    local path needed
    while IFS= read -r path; do
        needed=$(readelf -d "${path}" 2>/dev/null | awk -F'[][]' '/NEEDED/ {print $2}' || true)
        if printf '%s\n' "${needed}" | grep -Fx 'libpetsc.so.3.24' >/dev/null; then
            echo "stale PETSc dependency: ${path}" >&2
            failed=1
        fi
        if printf '%s\n' "${needed}" | grep -Fx 'libscalapack.so.2' >/dev/null; then
            echo "stale ScaLAPACK dependency: ${path}" >&2
            failed=1
        fi
    done < <(opt_elf_files)
    [[ "${failed}" == "0" ]] || die "stale dependency audit failed"
    echo "No stale PETSc 3.24 or ScaLAPACK 2 dependencies found."
}

full_ldd_audit() {
    section "Full /opt/ohpc ldd audit"
    local failed=0
    local path audit_path out status
    while IFS= read -r path; do
        audit_path=$(ohpc_ld_library_path_for "${path}")
        set +e
        case "${path}" in
            *.so|*.so.*|*.cpython-*.so)
                out=$(LD_LIBRARY_PATH="${audit_path}" timeout 30s ldd "${path}" 2>&1)
                ;;
            *)
                out=$(LD_LIBRARY_PATH="${audit_path}" timeout 30s ldd -r "${path}" 2>&1)
                ;;
        esac
        status=$?
        set -e
        if [[ "${status}" == "124" ]]; then
            printf '%s\n' "${out}" >&2
            echo "ldd timed out: ${path}" >&2
            failed=1
            continue
        fi
        if printf '%s\n' "${out}" | grep -E 'not found|undefined symbol' >/dev/null; then
            printf '%s\n' "${out}" >&2
            echo "unresolved dependency/symbol: ${path}" >&2
            failed=1
        fi
    done < <(opt_elf_files)
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

section "APT repository candidates"
if [[ "${run_gnu}" == "1" ]]; then
    candidate_required lmod-ohpc
    candidate_required gnu15-compilers-ohpc
    candidate_required mpich-gnu15-ohpc
    candidate_required mvapich2-gnu15-ohpc
    candidate_required openmpi5-gnu15-ohpc
fi

intel_packages=(
    intel-oneapi-toolkit-release-ohpc
    intel-compilers-devel-ohpc
    intel-mpi-devel-ohpc
    openmpi5-intel-ohpc
    mpich-intel-ohpc
    mvapich2-intel-ohpc
)
if [[ "${run_intel}" == "auto" ]]; then
    run_intel=1
    for pkg in "${intel_packages[@]}"; do
        value=$(candidate "${pkg}")
        if [[ -z "${value}" || "${value}" == "(none)" ]]; then
            run_intel=0
            break
        fi
    done
fi
if [[ "${run_intel}" == "1" ]]; then
    candidate_required gnu15-compilers-ohpc
    for pkg in "${intel_packages[@]}"; do
        candidate_required "${pkg}"
    done
fi

section "Install packages"
packages=()
if [[ "${run_gnu}" == "1" ]]; then
    packages+=(
        lmod-ohpc
        gnu15-compilers-ohpc
        openblas-gnu15-ohpc
        mpich-gnu15-ohpc
        mvapich2-gnu15-ohpc
        openmpi5-gnu15-ohpc
        likwid-gnu15-ohpc
        ohpc-gnu15-serial-libs
        ohpc-gnu15-runtimes
        mfem-gnu15-mpich-ohpc
        mfem-gnu15-mvapich2-ohpc
        mfem-gnu15-openmpi5-ohpc
        mumps-gnu15-mpich-ohpc
        mumps-gnu15-mvapich2-ohpc
        mumps-gnu15-openmpi5-ohpc
        ohpc-gnu15-mpich-parallel-libs
        ohpc-gnu15-mvapich2-parallel-libs
        ohpc-gnu15-openmpi5-parallel-libs
    )
fi
if [[ "${run_intel}" == "1" ]]; then
    apt-get install -y --no-install-recommends intel-oneapi-toolkit-release-ohpc
    apt-get update -qq
    packages+=(
        gnu15-compilers-ohpc
        intel-compilers-devel-ohpc
        intel-mpi-devel-ohpc
        mfem-gnu15-impi-ohpc
        mumps-gnu15-impi-ohpc
        trilinos-gnu15-impi-ohpc
        mfem-intel-impi-ohpc
        mfem-intel-mpich-ohpc
        mfem-intel-mvapich2-ohpc
        mfem-intel-openmpi5-ohpc
        mumps-intel-impi-ohpc
        mumps-intel-mpich-ohpc
        mumps-intel-mvapich2-ohpc
        mumps-intel-openmpi5-ohpc
        trilinos-intel-impi-ohpc
        trilinos-intel-mpich-ohpc
        trilinos-intel-mvapich2-ohpc
        trilinos-intel-openmpi5-ohpc
        openmpi5-intel-ohpc
        mpich-intel-ohpc
        mvapich2-intel-ohpc
    )
fi
apt-get install -y --no-install-recommends "${packages[@]}"
dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' "${packages[@]}" | sort
if [[ "${run_gnu}" == "1" ]]; then
    section "Installed GNU package versions"
    installed_version_required lmod-ohpc 9.2
    installed_version_required gnu15-compilers-ohpc 15.2.0
    installed_version_required mpich-gnu15-ohpc 5.0.1
    installed_version_required mvapich2-gnu15-ohpc 4.1
    installed_version_required openmpi5-gnu15-ohpc 5.0.10-1ohpc2
    installed_version_required r-gnu15-ohpc 4.5.3-1ohpc2
    for stack in mpich mvapich2 openmpi5; do
        installed_version_required "mfem-gnu15-${stack}-ohpc" "4.9-1ohpc2"
        installed_version_required "mumps-gnu15-${stack}-ohpc" "5.8.2-1ohpc2"
    done
    for stack in mpich mvapich2; do
        installed_version_required "trilinos-gnu15-${stack}-ohpc" "17.0.0-1ohpc2"
        installed_version_required "pnetcdf-gnu15-${stack}-ohpc" "1.14.1"
    done
fi
if [[ "${run_intel}" == "1" ]]; then
    section "Installed Intel package versions"
    installed_version_required intel-compilers-devel-ohpc 2025.0
    installed_version_required intel-mpi-devel-ohpc 2025.0
    installed_version_required mpich-intel-ohpc 5.0.1
    installed_version_required mvapich2-intel-ohpc 4.1
    installed_version_required openmpi5-intel-ohpc 5.0.10-1ohpc2
    installed_version_required mfem-gnu15-impi-ohpc 4.9-1ohpc2
    installed_version_required mumps-gnu15-impi-ohpc 5.8.2-1ohpc2
    installed_version_required trilinos-gnu15-impi-ohpc 17.0.0-1ohpc2
    installed_version_required pnetcdf-gnu15-impi-ohpc 1.14.1
    for stack in impi mpich mvapich2 openmpi5; do
        installed_version_required "mfem-intel-${stack}-ohpc" "4.9-1ohpc2"
        installed_version_required "mumps-intel-${stack}-ohpc" "5.8.2-1ohpc2"
        installed_version_required "trilinos-intel-${stack}-ohpc" "17.0.0-1ohpc2"
        installed_version_required "pnetcdf-intel-${stack}-ohpc" "1.14.1"
    done
fi

set +u
. /opt/ohpc/admin/lmod/lmod/init/bash
set -u
module use /opt/ohpc/pub/modulefiles
write_sources

if [[ "${run_gnu}" == "1" ]]; then
    run_stack GNU15 gnu15/15.2.0 mpich mpich/5.0.1 /opt/ohpc/pub/mpi/mpich-ofi-gnu15-ohpc/5.0.1 'HYDRA_LAUNCHER=fork FI_PROVIDER=tcp'
    run_stack GNU15 gnu15/15.2.0 mvapich2 mvapich2/4.1 /opt/ohpc/pub/mpi/mvapich2-gnu15/4.1 'MV2_ENABLE_AFFINITY=0 MV2_SMP_USE_CMA=0'
    run_stack GNU15 gnu15/15.2.0 openmpi5 openmpi5/5.0.10 /opt/ohpc/pub/mpi/openmpi5-gnu15/5.0.10 'OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 OMPI_MCA_pml=ob1 OMPI_MCA_btl=self,tcp'
    verify_likwid
fi

if [[ "${run_intel}" == "1" ]]; then
    run_stack GNU15-IMPI gnu15/15.2.0 impi impi/2021.14 /opt/intel/oneapi/mpi/2021.14 'I_MPI_FABRICS=shm'
    run_stack Intel intel/2025.0.4 impi impi/2021.14 /opt/intel/oneapi/mpi/2021.14 'I_MPI_FABRICS=shm'
    run_stack Intel intel/2025.0.4 mpich mpich/5.0.1 /opt/ohpc/pub/mpi/mpich-ofi-intel-ohpc/5.0.1 'HYDRA_LAUNCHER=fork FI_PROVIDER=tcp'
    run_stack Intel intel/2025.0.4 mvapich2 mvapich2/4.1 /opt/ohpc/pub/mpi/mvapich2-intel/4.1 'MV2_ENABLE_AFFINITY=0 MV2_SMP_USE_CMA=0'
    run_stack Intel intel/2025.0.4 openmpi5 openmpi5/5.0.10 /opt/ohpc/pub/mpi/openmpi5-intel/5.0.10 'OMPI_ALLOW_RUN_AS_ROOT=1 OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 OMPI_MCA_pml=ob1 OMPI_MCA_btl=self,tcp'
fi

selected_ldd_audit

stale_dependency_audit

if [[ "${OHPC_FULL_LDD}" == "1" ]]; then
    full_ldd_audit
fi

section "Result"
echo "Ubuntu amd64 public repository runtime validation passed."
EOF
