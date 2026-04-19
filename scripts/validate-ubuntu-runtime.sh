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

compiler_key() {
    case "$1" in
        GNU15) echo "gnu15" ;;
        Intel) echo "intel" ;;
        *) die "unknown compiler family: $1" ;;
    esac
}

mpi_key() {
    case "$1" in
        IMPI) echo "impi" ;;
        openmpi5|mpich|mvapich2) echo "$1" ;;
        *) die "unknown MPI family: $1" ;;
    esac
}

expected_mpi_prefix() {
    local compiler mpi
    compiler=$(compiler_key "$1")
    mpi=$(mpi_key "$2")

    case "$mpi" in
        openmpi5) echo "/opt/ohpc/pub/mpi/openmpi5-${compiler}/5.0.10" ;;
        mpich) echo "/opt/ohpc/pub/mpi/mpich-ofi-${compiler}-ohpc/5.0.0" ;;
        mvapich2) echo "/opt/ohpc/pub/mpi/mvapich2-${compiler}/2.3.7" ;;
        impi) echo "/opt/intel/oneapi/mpi" ;;
        *) die "unknown MPI family: $mpi" ;;
    esac
}

expected_imb_prefix() {
    printf '/opt/ohpc/pub/libs/%s/%s/imb/2021.10\n' \
        "$(compiler_key "$1")" "$(mpi_key "$2")"
}

require_path_prefix() {
    local label=$1 path=$2 prefix=$3

    case "$path" in
        "$prefix"|"$prefix"/*) ;;
        *) die "$label path $path is outside expected prefix $prefix" ;;
    esac
}

mpicc_show() {
    local output

    if output=$(mpicc --showme:command 2>/dev/null) && [ -n "$output" ]; then
        echo "$output"
        return
    fi
    if output=$(mpicc -show 2>/dev/null) && [ -n "$output" ]; then
        echo "$output"
        return
    fi
    if output=$(mpicc -showme 2>/dev/null) && [ -n "$output" ]; then
        echo "$output"
        return
    fi
    echo "unknown"
}

verify_compiler_wrapper() {
    local compiler_name=$1 show cc_path cc_version

    show=$(mpicc_show)
    printf 'mpicc: %s\n' "$(command -v mpicc)"
    printf 'mpicc wrapper: %s\n' "$show"

    case "$compiler_name" in
        GNU15)
            cc_path=$(command -v gcc)
            cc_version=$(gcc -dumpfullversion -dumpversion)
            require_path_prefix "gcc" "$cc_path" "/opt/ohpc/pub/compiler/gcc/15.2.0/bin"
            case "$cc_version" in
                15.2.0*) ;;
                *) die "GNU15 module selected gcc version $cc_version, expected 15.2.0" ;;
            esac
            if echo "$show" | grep -Eq '(^|[[:space:]/])(icx|icc|mpiicc)([[:space:]]|$)'; then
                die "GNU15 MPI wrapper appears to use an Intel compiler: $show"
            fi
            ;;
        Intel)
            cc_path=$(command -v icx)
            require_path_prefix "icx" "$cc_path" "/opt/intel/oneapi/compiler"
            if [ "$show" != "unknown" ] && \
                ! echo "$show" | grep -Eq '(^|[[:space:]/])(icx|icc|mpiicc)([[:space:]]|$)'; then
                die "Intel MPI wrapper does not appear to use an Intel compiler: $show"
            fi
            ;;
        *)
            die "unknown compiler family: $compiler_name"
            ;;
    esac
}

verify_mpi_environment() {
    local compiler_name=$1 mpi_name=$2 expected_prefix=$3 actual_mpi_dir mpicc_path

    actual_mpi_dir=${MPI_DIR:-}
    [ -n "$actual_mpi_dir" ] || die "MPI_DIR is not set after loading ${mpi_name}"
    require_path_prefix "MPI_DIR" "$actual_mpi_dir" "$expected_prefix"

    mpicc_path=$(command -v mpicc)
    require_path_prefix "mpicc" "$mpicc_path" "$actual_mpi_dir/bin"
    verify_compiler_wrapper "$compiler_name"
}

verify_ldd_prefix() {
    local label=$1 binary=$2 expected_prefix=$3 ldd_out mpi_lines wrong_mpi

    [ -x "$binary" ] || die "$label binary is not executable: $binary"
    ldd_out=$(ldd "$binary") || die "ldd failed for $label: $binary"
    mpi_lines=$(printf '%s\n' "$ldd_out" | grep -E 'lib(mpi|mpich|open-pal|open-rte)' || true)
    [ -n "$mpi_lines" ] || die "$label has no MPI-related dynamic linkage"

    printf 'ldd %s MPI lines:\n' "$label"
    printf '%s\n' "$mpi_lines"

    printf '%s\n' "$mpi_lines" | grep -F "$expected_prefix" >/dev/null || \
        die "$label is not linked against expected MPI prefix $expected_prefix"

    wrong_mpi=$(printf '%s\n' "$mpi_lines" | grep -E 'lib(mpi|mpich)' | grep -vF "$expected_prefix" || true)
    [ -z "$wrong_mpi" ] || die "$label also resolves MPI libraries outside $expected_prefix: $wrong_mpi"
}

verify_imb_binary() {
    local compiler_name=$1 mpi_name=$2 expected_mpi_prefix=$3 expected_imb_dir imb_path

    expected_imb_dir=$(expected_imb_prefix "$compiler_name" "$mpi_name")
    [ -n "${IMB_DIR:-}" ] || die "IMB_DIR is not set after loading imb/2021.10"
    require_path_prefix "IMB_DIR" "$IMB_DIR" "$expected_imb_dir"

    imb_path=$(command -v IMB-MPI1)
    require_path_prefix "IMB-MPI1" "$imb_path" "$expected_imb_dir/bin"
    verify_ldd_prefix "${compiler_name} ${mpi_name} IMB-MPI1" "$imb_path" "$expected_mpi_prefix"
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
    local mpi_prefix

    mpi_prefix=$(expected_mpi_prefix "$compiler_name" "$mpi_name")

    section "${label} hello"
    module purge
    module load "$compiler_module" "$mpi_module"
    verify_mpi_environment "$compiler_name" "$mpi_name" "$mpi_prefix"
    if [ "$mpi_name" = mvapich2 ]; then
        if module show "$mpi_module" 2>&1 | grep -q MV2_SMP_USE_CMA; then
            die "MVAPICH2 module still sets MV2_SMP_USE_CMA"
        fi
    fi
    mpicc "$workdir/mpi-hello.c" -o "$exe"
    verify_ldd_prefix "${label} hello" "$exe" "$mpi_prefix"
    if [ "$force_cma" = 1 ]; then
        MV2_SMP_USE_CMA=1 srun_node --mpi="$slurm_mpi" -N1 -n2 "$exe" | sort
    else
        srun_node --mpi="$slurm_mpi" -N1 -n2 "$exe" | sort
    fi

    section "${label} IMB PingPong"
    module load imb/2021.10
    verify_imb_binary "$compiler_name" "$mpi_name" "$mpi_prefix"
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
need_cmd ldd

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
