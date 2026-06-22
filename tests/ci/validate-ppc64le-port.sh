#!/bin/bash

set -euo pipefail

SCRIPT_NAME=$(basename "${0}")

BASE_REF=origin/4.x
BUILD_USER=ohpc
COMPILER_FAMILY=gnu15
CONTAINER_ENGINE=${CONTAINER_ENGINE:-podman}
DISTRO=almalinux
IMAGE=
INSIDE_CONTAINER=0
MPI_FAMILY=all
# This is an RPM build + install smoke test, not a host-tuning run. The mvapich2
# smoke pins UCX_TLS=self,sm,tcp (shared-memory + TCP loopback) precisely so it
# needs no RDMA device, elevated memlock, or host PID namespace. Default to an
# unprivileged container; --privileged is explicit opt-in for the rare local run
# that actually needs it.
PRIVILEGED=0
PROFILE=bootstrap
RUN_BUILD=1
RUN_RUNTIME=1
SPEC_LIST=

BOOTSTRAP_SPECS=(
	components/admin/lmod/SPECS/lmod.spec
	components/admin/ohpc-filesystem/SPECS/ohpc-filesystem.spec
	components/admin/prun/SPECS/prun.spec
	components/compiler-families/gnu-compilers/SPECS/gnu-compilers.spec
	components/dev-tools/hwloc/SPECS/hwloc.spec
	components/mpi-families/ucx/SPECS/ucx.spec
	components/rms/openpbs/SPECS/openpbs.spec
	components/mpi-families/openmpi/SPECS/openmpi.spec
	components/mpi-families/mpich/SPECS/mpich.spec
	components/mpi-families/mvapich2/SPECS/mvapich2.spec
	components/serial-libs/openblas/SPECS/openblas.spec
	components/serial-libs/gotcha/SPECS/gotcha.spec
	components/distro-packages/python-Cython/SPECS/python-Cython.spec
	components/dev-tools/numpy/SPECS/python-numpy.spec
	components/parallel-libs/fftw/SPECS/fftw.spec
	components/parallel-libs/boost/SPECS/boost.spec
	components/perf-tools/likwid/SPECS/likwid.spec
	components/perf-tools/pdtoolkit/SPECS/pdtoolkit.spec
	components/admin/meta-packages/SPECS/meta-packages.spec
)

usage() {
	cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Native ppc64le validation for the OpenHPC POWER RPM port. The host mode builds
the ppc64le validation container and then runs this script inside it as root.

Options:
  --base-ref REF          Git base ref for branch-relative checks (${BASE_REF})
  --build-user USER       Non-root RPM build user inside the container (${BUILD_USER})
  --compiler-family NAME  OpenHPC compiler family (${COMPILER_FAMILY})
  --container-engine CMD  Container engine for host mode (${CONTAINER_ENGINE})
  --distro NAME           almalinux or openeuler (${DISTRO})
  --image NAME            Container image tag to build/use
  --inside-container      Run validation directly in the current environment
  --mpi-family NAME       all, openmpi5, mpich, or mvapich2 (${MPI_FAMILY})
  --profile NAME          bootstrap, changed, or file (${PROFILE})
  --spec-list FILE        Spec list for --profile file
  --skip-build            Skip RPM builds and only run static/runtime checks
  --skip-runtime          Skip install/runtime smoke tests
  --privileged            Run the host-mode container with --privileged --pid=host
                          (off by default; the smoke test needs no RDMA/memlock)
  --no-privileged         Force the unprivileged default (kept for compatibility)
  -h, --help              Show this help

Examples:
  tests/ci/validate-ppc64le-port.sh --base-ref origin/4.x
  tests/ci/validate-ppc64le-port.sh --distro openeuler --mpi-family mpich
EOF
}

log() {
	printf '==> %s\n' "${*}"
}

die() {
	printf 'ERROR: %s\n' "${*}" >&2
	exit 1
}

repo_root() {
	git rev-parse --show-toplevel
}

require_ppc64le() {
	local arch
	arch=$(uname -m)
	[[ ${arch} == "ppc64le" ]] || die "ppc64le host required, got ${arch}"
}

parse_args() {
	while (($# > 0)); do
		case "${1}" in
			--base-ref)
				BASE_REF=${2:?}
				shift 2
				;;
			--build-user)
				BUILD_USER=${2:?}
				shift 2
				;;
			--compiler-family)
				COMPILER_FAMILY=${2:?}
				shift 2
				;;
			--container-engine)
				CONTAINER_ENGINE=${2:?}
				shift 2
				;;
			--distro)
				DISTRO=${2:?}
				shift 2
				;;
			--image)
				IMAGE=${2:?}
				shift 2
				;;
			--inside-container)
				INSIDE_CONTAINER=1
				shift
				;;
			--mpi-family)
				MPI_FAMILY=${2:?}
				shift 2
				;;
			--profile)
				PROFILE=${2:?}
				shift 2
				;;
			--spec-list)
				SPEC_LIST=${2:?}
				shift 2
				;;
			--skip-build)
				RUN_BUILD=0
				shift
				;;
			--skip-runtime)
				RUN_RUNTIME=0
				shift
				;;
			--privileged)
				PRIVILEGED=1
				shift
				;;
			--no-privileged)
				PRIVILEGED=0
				shift
				;;
			-h | --help)
				usage
				exit 0
				;;
			*)
				die "unknown option: ${1}"
				;;
		esac
	done
}

validate_args() {
	case "${DISTRO}" in
		almalinux | openeuler) ;;
		*) die "--distro must be almalinux or openeuler" ;;
	esac

	case "${MPI_FAMILY}" in
		all | openmpi5 | mpich | mvapich2) ;;
		*) die "--mpi-family must be all, openmpi5, mpich, or mvapich2" ;;
	esac

	case "${PROFILE}" in
		bootstrap | changed | file) ;;
		*) die "--profile must be bootstrap, changed, or file" ;;
	esac

	if [[ ${PROFILE} == "file" && -z ${SPEC_LIST} ]]; then
		die "--profile file requires --spec-list"
	fi
}

containerfile_for_distro() {
	case "${DISTRO}" in
		almalinux) printf '%s\n' tests/ci/Containerfile.ohpc-validate-almalinux-ppc64le ;;
		openeuler) printf '%s\n' tests/ci/Containerfile.ohpc-validate-openeuler-ppc64le ;;
	esac
}

default_image() {
	printf 'ohpc-validate-%s-ppc64le:local\n' "${DISTRO}"
}

run_host() {
	local containerfile
	local image
	local root
	local run_args=()
	local validation_args=()

	require_ppc64le
	root=$(repo_root)
	cd "${root}"

	containerfile=$(containerfile_for_distro)
	[[ -f ${containerfile} ]] || die "containerfile not found: ${containerfile}"

	image=${IMAGE:-$(default_image)}
	log "Building ${image} from ${containerfile}"
	"${CONTAINER_ENGINE}" build -f "${containerfile}" -t "${image}" .

	run_args=(
		run
		--rm
		--user root
		--workdir /workspace
		--volume "${root}:/workspace:z"
	)

	if [[ ${PRIVILEGED} -eq 1 ]]; then
		run_args+=(--privileged --pid=host)
	fi

	validation_args=(
		bash
		tests/ci/validate-ppc64le-port.sh
		--inside-container
		--base-ref "${BASE_REF}"
		--build-user "${BUILD_USER}"
		--compiler-family "${COMPILER_FAMILY}"
		--mpi-family "${MPI_FAMILY}"
		--profile "${PROFILE}"
	)
	if [[ -n ${SPEC_LIST} ]]; then
		validation_args+=(--spec-list "${SPEC_LIST}")
	fi
	if [[ ${RUN_BUILD} -eq 0 ]]; then
		validation_args+=(--skip-build)
	fi
	if [[ ${RUN_RUNTIME} -eq 0 ]]; then
		validation_args+=(--skip-runtime)
	fi

	log "Running ppc64le validation in ${image}"
	"${CONTAINER_ENGINE}" "${run_args[@]}" "${image}" "${validation_args[@]}"
}

ensure_git_safe_directory() {
	git config --global --add safe.directory "$(pwd)" >/dev/null 2>&1 || true
}

ensure_base_ref() {
	git rev-parse --verify "${BASE_REF}^{commit}" >/dev/null 2>&1 ||
		die "base ref ${BASE_REF} is not available; fetch it before running validation"
}

changed_specs() {
	git diff --name-only "${BASE_REF}"..HEAD -- 'components/**/SPECS/*.spec'
}

read_spec_list() {
	local list_file=${1}
	[[ -f ${list_file} ]] || die "spec list not found: ${list_file}"
	grep -E '^[^#[:space:]].*\.spec$' "${list_file}" || true
}

dedupe_specs() {
	local spec
	declare -A seen=()
	for spec in "$@"; do
		[[ -n ${spec} ]] || continue
		if [[ -z ${seen[${spec}]+x} ]]; then
			printf '%s\n' "${spec}"
			seen[${spec}]=1
		fi
	done
}

selected_specs() {
	local changed=()
	local from_file=()

	mapfile -t changed < <(changed_specs)

	case "${PROFILE}" in
		bootstrap)
			dedupe_specs "${BOOTSTRAP_SPECS[@]}" "${changed[@]}"
			;;
		changed)
			dedupe_specs "${changed[@]}"
			;;
		file)
			mapfile -t from_file < <(read_spec_list "${SPEC_LIST}")
			dedupe_specs "${from_file[@]}"
			;;
	esac
}

validate_spec_paths() {
	local spec
	for spec in "$@"; do
		[[ -f ${spec} ]] || die "selected spec does not exist: ${spec}"
	done
}

changed_branch_specs_or_selected() {
	local changed=()
	mapfile -t changed < <(changed_specs)
	if ((${#changed[@]} > 0)); then
		printf '%s\n' "${changed[@]}"
	else
		printf '%s\n' "$@"
	fi
}

run_static_checks() {
	local check_specs=()
	local downstream_patterns
	local spec

	log "Running git whitespace check against ${BASE_REF}"
	git diff --check "${BASE_REF}"..HEAD

	log "Checking branch diff for downstream-only repository strings"
	downstream_patterns='Versatus''HPC|repos\.versatus''hpc|pub''lish|pub''lic repo'
	if git diff "${BASE_REF}"..HEAD | grep -E -i "${downstream_patterns}"; then
		die "branch diff contains downstream-only wording"
	fi

	mapfile -t check_specs < <(changed_branch_specs_or_selected "$@")
	if ((${#check_specs[@]} == 0)); then
		log "No spec files selected for spec checks"
		return
	fi

	log "Running OpenHPC spec policy checks"
	python3 tests/ci/check_spec.py "${check_specs[@]}"

	log "Checking changed specs for malformed Release macros"
	if grep -n -E 'Release:[[:space:]]+%\{\?dist\}\.1' "${check_specs[@]}"; then
		die "malformed Release macro found"
	fi

	log "Parsing selected specs with rpmspec"
	for spec in "${check_specs[@]}"; do
		rpmspec --parse --define "_sourcedir $(pwd)/components" "${spec}" >/dev/null
	done
}

ensure_build_user() {
	local home_dir

	if ! id "${BUILD_USER}" >/dev/null 2>&1; then
		useradd -m "${BUILD_USER}"
	fi

	home_dir=$(getent passwd "${BUILD_USER}" | cut -d: -f6)
	[[ -n ${home_dir} ]] || die "cannot determine home for ${BUILD_USER}"

	mkdir -p "${home_dir}"/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
	cp components/OHPC_macros "${home_dir}/rpmbuild/SOURCES/OHPC_macros"
	chown -R "${BUILD_USER}:${BUILD_USER}" "${home_dir}/rpmbuild"
}

run_rpm_builds() {
	local specs=("$@")
	local command=()

	((${#specs[@]} > 0)) || die "no specs selected for build"

	ensure_build_user

	command=(tests/ci/run_build.py --fail-fast --compiler-family "${COMPILER_FAMILY}")
	if [[ ${MPI_FAMILY} != "all" ]]; then
		command+=(--mpi-family "${MPI_FAMILY}")
	fi
	command+=("${BUILD_USER}" "${specs[@]}")

	log "Building ${#specs[@]} spec files with ${COMPILER_FAMILY}/${MPI_FAMILY}"
	"${command[@]}"
}

repoquery_local_package() {
	local package=${1}
	[[ -n $(dnf -q repoquery \
		--disablerepo='*' \
		--enablerepo=local-ohpc-ppc64le-validation \
		"${package}") ]]
}

local_rpm_repo_dir() {
	local home_dir
	home_dir=$(getent passwd "${BUILD_USER}" | cut -d: -f6)
	printf '%s/rpmbuild/RPMS\n' "${home_dir}"
}

configure_local_rpm_repo() {
	local repo_dir

	repo_dir=$(local_rpm_repo_dir)
	[[ -d ${repo_dir} ]] || die "RPM output directory not found: ${repo_dir}"

	log "Refreshing local RPM repository at ${repo_dir}"
	createrepo_c "${repo_dir}" >/dev/null

	cat > /etc/yum.repos.d/local-ohpc-ppc64le-validation.repo <<EOF
[local-ohpc-ppc64le-validation]
name=Local OpenHPC ppc64le validation builds
baseurl=file://${repo_dir}
enabled=1
gpgcheck=0
EOF
}

mpi_modules() {
	case "${MPI_FAMILY}" in
		all)
			printf '%s\n' openmpi5 mpich mvapich2
			;;
		*)
			printf '%s\n' "${MPI_FAMILY}"
			;;
	esac
}

runtime_packages() {
	local mpi
	# Track the selected --compiler-family rather than hardcoding gnu15, so the
	# runtime repoquery matches the RPMs run_build.py actually produced for this
	# family (a non-gnu15 family otherwise dies on the repoquery after a build).
	local family=${COMPILER_FAMILY}
	local packages=(
		lmod-ohpc
		ohpc-filesystem
		"${family}-compilers-ohpc"
		hwloc-ohpc
		"openblas-${family}-ohpc"
		"gotcha-${family}-ohpc"
		"python3-numpy-${family}-ohpc"
		"likwid-${family}-ohpc"
		"pdtoolkit-${family}-ohpc"
	)

	while IFS= read -r mpi; do
		case "${mpi}" in
			openmpi5)
				packages+=(ucx-ohpc ucx-ib-ohpc "openmpi5-${family}-ohpc")
				;;
			mpich)
				packages+=("mpich-ofi-${family}-ohpc")
				;;
			mvapich2)
				packages+=("mvapich2-${family}-ohpc")
				;;
		esac
		packages+=("fftw-${family}-${mpi}-ohpc")
		packages+=("boost-${family}-${mpi}-ohpc")
	done < <(mpi_modules)

	printf '%s\n' "${packages[@]}"
}

install_runtime_packages() {
	local packages=()
	local missing=0
	local package

	configure_local_rpm_repo

	mapfile -t packages < <(runtime_packages)
	log "Verifying ${#packages[@]} runtime packages exist in the local build repo"
	for package in "${packages[@]}"; do
		if ! repoquery_local_package "${package}"; then
			printf 'missing local package: %s\n' "${package}" >&2
			missing=1
		fi
	done
	[[ ${missing} -eq 0 ]] || die "runtime package set is incomplete"

	log "Installing runtime package set from local RPM repository"
	dnf -y install "${packages[@]}"
}

write_runtime_smoke() {
	local smoke=${1}

	cat > "${smoke}" <<'EOF'
#!/bin/bash

set -euo pipefail

mpi_list=${1}
compiler_family=${2}
smoke_dir=${HOME}/ohpc-ppc64le-smoke

set +u
source /etc/profile.d/lmod.sh
set -u

mkdir -p "${smoke_dir}"
cd "${smoke_dir}"

checkpoint() {
	printf '== smoke: %s\n' "${*}"
}

require_env_dir() {
	local name=${1}
	local value=${!name:-}

	[[ -n ${value} ]] || {
		printf 'missing environment variable: %s\n' "${name}" >&2
		return 1
	}
	[[ -d ${value} ]] || {
		printf 'missing directory for %s: %s\n' "${name}" "${value}" >&2
		return 1
	}
	printf '%s=%s\n' "${name}" "${value}"
}

require_glob() {
	local pattern=${1}
	local match

	match=$(compgen -G "${pattern}" | head -n 1 || true)
	[[ -n ${match} ]] || {
		printf 'no files matched: %s\n' "${pattern}" >&2
		return 1
	}
	printf 'matched %s\n' "${match}"
}

require_help_output() {
	local cmd=${1}
	local pattern=${2}
	local output=${smoke_dir}/${cmd}.help
	local rc=0

	command -v "${cmd}"
	if "${cmd}" -h > "${output}" 2>&1; then
		printf '%s -h exited 0\n' "${cmd}"
	else
		rc=$?
		printf '%s -h exited %s; validating help output\n' "${cmd}" "${rc}"
	fi
	sed -n '1,20p' "${output}"
	grep -Eiq "${pattern}" "${output}" || {
		printf '%s help output did not match %s\n' "${cmd}" "${pattern}" >&2
		return 1
	}
}

cat > hello_mpi.c <<'CEOF'
#include <mpi.h>
#include <stdio.h>

int main(int argc, char **argv)
{
	int rank = -1;
	int size = 0;
	MPI_Init(&argc, &argv);
	MPI_Comm_rank(MPI_COMM_WORLD, &rank);
	MPI_Comm_size(MPI_COMM_WORLD, &size);
	printf("C MPI hello rank %d of %d\n", rank, size);
	MPI_Finalize();
	return 0;
}
CEOF

cat > hello_mpi.f90 <<'FEOF'
program hello
  use mpi
  implicit none
  integer :: ierr, rank, size
  call MPI_Init(ierr)
  call MPI_Comm_rank(MPI_COMM_WORLD, rank, ierr)
  call MPI_Comm_size(MPI_COMM_WORLD, size, ierr)
  print *, "Fortran MPI hello rank", rank, "of", size
  call MPI_Finalize(ierr)
end program hello
FEOF

cat > fftw_mpi_smoke.c <<'FCEOF'
#include <fftw3-mpi.h>

int main(int argc, char **argv)
{
	ptrdiff_t local_n0, local_0_start;
	MPI_Init(&argc, &argv);
	fftw_mpi_init();
	fftw_mpi_local_size_2d(16, 16, MPI_COMM_WORLD, &local_n0, &local_0_start);
	MPI_Finalize();
	return 0;
}
FCEOF

IFS=',' read -r -a mpis <<< "${mpi_list}"

module purge
checkpoint "compiler module ${compiler_family}"
module load "${compiler_family}"
gcc --version
gfortran --version

for mpi in "${mpis[@]}"; do
	module purge
	checkpoint "modules ${compiler_family}/${mpi}"
	module load "${compiler_family}"
	module load "${mpi}"
	module load fftw
	module load boost

	unset UCX_TLS
	if [[ ${mpi} == "openmpi5" ]]; then
		export OMPI_MCA_pml=ob1
	fi
	if [[ ${mpi} == "mvapich2" ]]; then
		# The smoke validates package wiring, not host RDMA/container memlock state.
		export UCX_TLS=self,sm,tcp
	fi

	checkpoint "compile ${mpi}"
	mpicc hello_mpi.c -o "hello-${mpi}-c"
	mpif90 hello_mpi.f90 -o "hello-${mpi}-f"
	mpicc fftw_mpi_smoke.c -I"${FFTW_INC}" -L"${FFTW_LIB}" -lfftw3_mpi -lfftw3 -o "fftw-${mpi}-c"

	checkpoint "run ${mpi}"
	mpirun -np 2 "./hello-${mpi}-c"
	mpirun -np 2 "./hello-${mpi}-f"
	mpirun -np 2 "./fftw-${mpi}-c"

	checkpoint "ldd ${mpi}"
	ldd "./hello-${mpi}-c" | grep -F /opt/ohpc
	ldd "./fftw-${mpi}-c" | grep -F /opt/ohpc
done

module purge
checkpoint "numpy openblas"
module load "${compiler_family}"
module load openblas
module load py3-numpy
python3 - <<'PYEOF'
import numpy as np
a = np.array([1.0, 2.0, 3.0])
assert np.dot(a, a) == 14.0
print(np.__version__)
PYEOF

module purge
checkpoint "likwid"
module load "${compiler_family}"
module load likwid
require_help_output likwid-topology 'likwid|topology'
require_help_output likwid-perfctr 'likwid|perfctr|performance'

module purge
checkpoint "pdtoolkit"
module load "${compiler_family}"
module load pdtoolkit
require_env_dir PDTOOLKIT_BIN
require_env_dir PDTOOLKIT_LIB
require_glob "${PDTOOLKIT_BIN}/*"

module purge
checkpoint "gotcha"
module load "${compiler_family}"
module load gotcha
require_env_dir GOTCHA_LIB
require_glob "${GOTCHA_LIB}/libgotcha.*"
EOF
	chmod 0755 "${smoke}"
}

run_runtime_smoke() {
	local mpi_csv
	local smoke

	install_runtime_packages

	mpi_csv=$(mpi_modules | paste -sd, -)
	smoke=/tmp/ohpc-ppc64le-runtime-smoke.sh
	write_runtime_smoke "${smoke}"

	log "Running runtime smoke tests for ${COMPILER_FAMILY}/${mpi_csv}"
	su - "${BUILD_USER}" -c "bash ${smoke} '${mpi_csv}' '${COMPILER_FAMILY}'"
}

run_inside_container() {
	local specs=()

	require_ppc64le
	[[ ${EUID} -eq 0 ]] || die "--inside-container must run as root"
	ensure_git_safe_directory
	ensure_base_ref

	mapfile -t specs < <(selected_specs)
	validate_spec_paths "${specs[@]}"

	log "Selected spec set:"
	printf '  %s\n' "${specs[@]}"

	run_static_checks "${specs[@]}"

	if [[ ${RUN_BUILD} -eq 1 ]]; then
		run_rpm_builds "${specs[@]}"
	else
		log "Skipping RPM builds by request"
	fi

	if [[ ${RUN_RUNTIME} -eq 1 ]]; then
		run_runtime_smoke
	else
		log "Skipping runtime smoke tests by request"
	fi
}

main() {
	parse_args "$@"
	validate_args

	if [[ ${INSIDE_CONTAINER} -eq 1 ]]; then
		run_inside_container
	else
		run_host
	fi
}

main "$@"
