#!/usr/bin/env bash
set -Eeuo pipefail

compute_node=${COMPUTE_NODE:-c1}
run_intel=auto
install_intel=0
upgrade_core=0
workdir=${OHPC_VALIDATE_WORKDIR:-"$HOME/ohpc-smoke"}

usage() {
    cat <<'EOF'
Usage: validate-ubuntu-runtime.sh [options]

Run the small Ubuntu OpenHPC runtime gate from an installed SMS/head node.

Options:
  --compute-node NAME   Slurm compute node to target (default: c1)
  --with-intel         Require and run Intel/mixed compiler+MPI validation
  --skip-intel         Do not run Intel validation
  --install-intel      Install Intel validation packages before testing
  --upgrade-core       Upgrade selected core OpenHPC packages before testing
  -h, --help           Show this help

Environment:
  COMPUTE_NODE          Same as --compute-node
  OHPC_VALIDATE_WORKDIR Directory for generated smoke-test sources/binaries
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --compute-node)
            compute_node=$2
            shift 2
            ;;
        --with-intel)
            run_intel=1
            shift
            ;;
        --skip-intel)
            run_intel=0
            shift
            ;;
        --install-intel)
            install_intel=1
            run_intel=1
            shift
            ;;
        --upgrade-core)
            upgrade_core=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

section() {
    printf '\n== %s ==\n' "$*"
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

sudo_n() {
    sudo -n "$@"
}

apt_get_install() {
    sudo_n apt-get -y \
        -o Dpkg::Options::=--force-confdef \
        -o Dpkg::Options::=--force-confold \
        install "$@"
}

load_lmod() {
    # Ubuntu's lmod profile may inspect Slurm variables that are unset outside
    # allocations, so source it with nounset disabled.
    set +u
    # shellcheck source=/dev/null
    . /etc/profile.d/lmod.sh
    set -u
}

candidate_required() {
    local pkg=$1 candidate
    candidate=$(apt-cache policy "$pkg" | awk '/Candidate:/ {candidate=$2} END {print candidate}')
    [ -n "$candidate" ] && [ "$candidate" != "(none)" ] || die "no APT candidate for $pkg"
    printf '%-32s %s\n' "$pkg" "$candidate"
}

require_module() {
    local mod=$1
    module -t avail "$mod" 2>&1 | grep -q "^${mod}" || die "module not available: $mod"
}

srun_node() {
    timeout 120 srun --input=none -w "$compute_node" "$@"
}

write_hello() {
    mkdir -p "$workdir"
    cat >"$workdir/mpi-hello.c" <<'EOF'
#include <mpi.h>
#include <stdio.h>
int main(int argc, char **argv) {
    int rank, size;
    char name[MPI_MAX_PROCESSOR_NAME];
    int len = 0;
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Get_processor_name(name, &len);
    printf("hello from rank %d/%d on %s\n", rank, size, name);
    MPI_Finalize();
    return 0;
}
EOF
}

run_mpi_stack() {
    local compiler_name=$1 compiler_module=$2 mpi_name=$3 mpi_module=$4 slurm_mpi=$5 force_cma=${6:-0}
    local label="${compiler_name} ${mpi_name}"
    local exe="$workdir/mpi-hello-${compiler_name}-${mpi_name}"

    section "${label} hello"
    module purge
    module load "$compiler_module" "$mpi_module"
    if [ "$mpi_name" = mvapich2 ]; then
        if module show "$mpi_module" 2>&1 | grep -q MV2_SMP_USE_CMA; then
            die "MVAPICH2 module still sets MV2_SMP_USE_CMA"
        fi
    fi
    mpicc "$workdir/mpi-hello.c" -o "$exe"
    if [ "$force_cma" = 1 ]; then
        MV2_SMP_USE_CMA=1 srun_node --mpi="$slurm_mpi" -N1 -n2 "$exe" | sort
    else
        srun_node --mpi="$slurm_mpi" -N1 -n2 "$exe" | sort
    fi

    section "${label} IMB PingPong"
    module load imb/2021.10
    if [ "$force_cma" = 1 ]; then
        MV2_SMP_USE_CMA=1 srun_node --mpi="$slurm_mpi" -N1 -n2 IMB-MPI1 PingPong -msglog 0:3 \
            | awk '/bytes|^[[:space:]]+[0-9]+[[:space:]]/{print}'
    else
        srun_node --mpi="$slurm_mpi" -N1 -n2 IMB-MPI1 PingPong -msglog 0:3 \
            | awk '/bytes|^[[:space:]]+[0-9]+[[:space:]]/{print}'
    fi
}

run_intel_stack() {
    section "Intel module and compiler"
    require_module "intel"
    require_module "impi"
    module purge
    module load intel impi
    icx --version | sed -n '1,3p'
    mpicc -show 2>/dev/null || true

    run_mpi_stack Intel intel/2025.0.4 IMPI impi/2021.14 pmi2
    run_mpi_stack GNU15 gnu15/15.2.0 IMPI impi/2021.14 pmi2
    run_mpi_stack Intel intel/2025.0.4 openmpi5 openmpi5/5.0.10 pmix
    run_mpi_stack Intel intel/2025.0.4 mpich mpich/5.0.0-ofi pmi2
    run_mpi_stack Intel intel/2025.0.4 mvapich2 mvapich2/2.3.7 pmi2 1
}

need_cmd apt-cache
need_cmd apt-get
need_cmd dpkg-query
need_cmd sinfo
need_cmd srun
need_cmd scontrol
need_cmd timeout

section "APT repository candidates"
sudo_n apt-get update
candidate_required ohpc-base
candidate_required ohpc-base-compute
candidate_required ohpc-slurm-client
candidate_required ohpc-slurm-server
candidate_required gnu15-compilers-ohpc
candidate_required openmpi5-gnu15-ohpc
candidate_required mpich-gnu15-ohpc
candidate_required mvapich2-gnu15-ohpc
candidate_required imb-gnu15-openmpi5-ohpc
candidate_required imb-gnu15-mpich-ohpc
candidate_required imb-gnu15-mvapich2-ohpc
candidate_required imb-gnu15-impi-ohpc
candidate_required intel-oneapi-toolkit-release-ohpc
candidate_required intel-compilers-devel-ohpc
candidate_required intel-mpi-devel-ohpc
candidate_required openmpi5-intel-ohpc
candidate_required mpich-intel-ohpc
candidate_required mvapich2-intel-ohpc
candidate_required imb-intel-impi-ohpc
candidate_required imb-intel-openmpi5-ohpc
candidate_required imb-intel-mpich-ohpc
candidate_required imb-intel-mvapich2-ohpc

if [ "$upgrade_core" = 1 ]; then
    section "Core package upgrade"
    apt_get_install --only-upgrade \
        ohpc-base ohpc-slurm-server \
        openmpi5-gnu15-ohpc mpich-gnu15-ohpc mvapich2-gnu15-ohpc \
        imb-gnu15-openmpi5-ohpc imb-gnu15-mpich-ohpc imb-gnu15-mvapich2-ohpc
fi

if [ "$install_intel" = 1 ]; then
    section "Install Intel validation packages"
    apt_get_install intel-oneapi-toolkit-release-ohpc
    sudo_n apt-get update
    apt_get_install \
        intel-compilers-devel-ohpc intel-mpi-devel-ohpc \
        openmpi5-intel-ohpc mpich-intel-ohpc mvapich2-intel-ohpc \
        imb-intel-impi-ohpc imb-gnu15-impi-ohpc \
        imb-intel-openmpi5-ohpc imb-intel-mpich-ohpc imb-intel-mvapich2-ohpc
fi

load_lmod
write_hello

section "Slurm compute node"
sudo_n scontrol update NodeName="$compute_node" State=RESUME >/dev/null 2>&1 || true
sinfo -Nel
srun_node -N1 -n1 hostname

section "Compute node base services"
srun_node -N1 -n1 bash -lc '
set -e
hostname
dpkg-query -W ohpc-base-compute ohpc-slurm-client
sysctl kernel.yama.ptrace_scope
mount | grep -E " /opt|/opt/ohpc"
systemctl is-active munge slurmd ssh
'

section "MUNGE and linker"
srun_node -N1 -n1 bash -lc 'munge -n | unmunge | grep "STATUS: *Success"'
srun_node -N1 -n1 bash -lc 'ldconfig -p | grep -E "libpmix|libhwloc"'

run_mpi_stack GNU15 gnu15/15.2.0 openmpi5 openmpi5/5.0.10 pmix
run_mpi_stack GNU15 gnu15/15.2.0 mpich mpich/5.0.0-ofi pmi2
run_mpi_stack GNU15 gnu15/15.2.0 mvapich2 mvapich2/2.3.7 pmi2 1

if [ "$run_intel" = auto ]; then
    if module -t avail intel 2>&1 | grep -q '^intel' && module -t avail impi 2>&1 | grep -q '^impi'; then
        run_intel=1
    else
        run_intel=0
        section "Intel validation"
        echo "SKIP: Intel modules are not installed. Use --install-intel or --with-intel to require them."
    fi
fi

if [ "$run_intel" = 1 ]; then
    run_intel_stack
fi

section "Result"
echo "Ubuntu OpenHPC runtime validation passed for compute node ${compute_node}."
