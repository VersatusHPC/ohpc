# POWER Validation Plan

This document tracks the cross-distribution checks used for the VersatusHPC
OpenHPC 4.x POWER ports. Ubuntu names the architecture `ppc64el`; EL and
openEuler name the same little-endian POWER target `ppc64le`.

## Scope

The POWER release gate covers the architecture-portable OpenHPC stack, not the
x86-only Intel, CUDA, ARM, Lustre, GEOPM, or MSR-safe package families. Those
families may remain available on x86 repositories, but they must not be
advertised to POWER clients.

## Checks

1. Compare public repository coverage across EL10, openEuler 24.03, and Ubuntu
   24.04 POWER:

   ```bash
   scripts/compare-power-package-coverage.py --fail-on-issues
   ```

   The expected EL10/openEuler difference is only rebuilt openEuler support
   libraries needed because the openEuler 24.03 ppc64le OS repository is thin:
   `flex`, `freeipmi`, `gpgme`, `libassuan`, `libedit`, `libfabric`,
   `libical`, `libsysfs`, `libtirpc`, `libtool-ltdl`, `libyaml`, `lua`,
   `lua-filesystem`, `meson`, `ninja-build`, `opensm`, `patchelf`,
   `postgresql`, `python3-meson-python`, `swig`, `sysfsutils`, `texinfo`,
   `yaml-cpp`, and `zstd`. Any OpenHPC package delta is release-blocking.
   Architecture-locked package families are also release-blocking in the EL10
   `ppc64le/noarch`, openEuler `ppc64le/noarch`, and Ubuntu `ppc64el/all`
   package views.

2. Validate RPM runtime behavior and meta-package closure from the public RPM
   repositories on native POWER:

   ```bash
   scripts/validate-rpm-ppc64le-core.sh --target el10
   scripts/validate-rpm-ppc64le-core.sh --target openeuler
   ```

   This installs the public repository in disposable containers, removes any
   preinstalled OpenHPC packages from reused local builder images, installs the
   GNU15 core compiler/MPI packages plus the supported GNU15 meta-package set,
   compiles C and Fortran MPI hello-world programs with MPICH, MVAPICH2, and
   OpenMPI, runs each program locally, and verifies `ldd` links to `/opt/ohpc`
   compiler and MPI paths. Use `--skip-meta` only when isolating a compiler/MPI
   smoke failure from repository metadata closure.

3. Validate Ubuntu ppc64el runtime behavior from the native Debian repository:

   ```bash
   scripts/validate-ubuntu-ppc64el-core.sh
   scripts/validate-ubuntu-ppc64el-public-repo.sh
   ```

   The first command validates the local native builder repository before
   publication. The second command validates the signed public APT repository
   from a fresh Ubuntu 24.04 ppc64el container. GitHub Actions runs the public
   repository gate on the `power-ohpc` self-hosted POWER runner through
   `.github/workflows/power-public-repo-validation.yml`.

4. Audit dependency closure:

   ```bash
   scripts/compare-power-package-coverage.py --fail-on-issues
   scripts/validate-rpm-ppc64le-core.sh --target all --full-ldd
   ```

   The metadata checker catches missing OpenHPC package dependencies directly
   from `repodata` and Debian `Packages` metadata. The runtime validator performs
   selected `ldd` checks on compilers, MPI libraries, OpenBLAS, and LIKWID by
   default; `--full-ldd` walks ELF files under `/opt/ohpc/pub`, fails on missing
   shared libraries everywhere, and applies `ldd -r` only to executable programs.
   This keeps the extended gate useful without treating plugin or Python-extension
   symbols as package failures.

5. Document whether each issue is shared source drift or Debian-only packaging
   drift:

   - Shared source drift: fixes that affect RPM and Debian packaging, such as
     LIKWID POWER `perf_event` support and the `GCCPOWER` compiler profile.
   - Debian-only drift: APT repository layout, `Architecture` metadata, Debian
     source/binary publishing, and Ubuntu-specific package manager behavior.
   - Distribution support drift: openEuler-only support library rebuilds caused
     by missing ppc64le OS repository packages.

## Current Findings

- Last public repository correctness gate: 2026-04-28.
- Repository package counts after the public repair:
  - `EL_10`: 266 packages (`noarch=10`, `ppc64le=178`, `src=78`).
  - `openEuler_24.03`: 375 packages (`noarch=27`, `ppc64le=268`, `src=80`).
  - `Ubuntu_24.04`: 513 packages (`all=21`, `amd64=325`, `ppc64el=167`).
- `scripts/compare-power-package-coverage.py --fail-on-issues` exits cleanly.
  EL10, openEuler, and Ubuntu all have the expected POWER core packages,
  OpenHPC dependencies resolve inside each public repository view, and the EL10,
  openEuler, and Ubuntu POWER package views do not include the known
  x86/ARM-locked package families.
- The repository correctness failures were stale public repository artifacts and
  overly broad POWER meta-packages, not compiler/runtime failures. Ubuntu still
  published old `Architecture: all` Intel, CUDA, and GNU meta `.deb` packages
  after their source metadata changed. EL10 and openEuler still published
  `4.0-1` RPM meta packages that depended on OpenHPC MPICH/scotch/paraver
  package variants not present in the POWER repositories.
- The Ubuntu public repository has been repaired. The publisher now can merge
  an amd64 repository update while publishing ppc64el, then safely prunes stale
  `Architecture: all` packages only when replacement arch-specific binaries are
  present. The public Ubuntu POWER view now excludes Intel oneAPI, Intel MPI,
  CUDA, ARM, Lustre, GEOPM, and MSR-safe package names.
- The RPM public repositories have been repaired. `meta-packages` was rebuilt
  and published as `4.0-2` for EL10 and openEuler POWER. Unsupported POWER
  MPICH meta subpackages are no longer published, generic GNU meta packages now
  depend only on package variants that exist in the POWER repositories, and
  `ohpc-warewulf` depends on the monolithic POWER Warewulf package.
- EL10 and openEuler ppc64le GNU15 runtime validation passes from the public RPM
  repositories with the corrected meta-package set installed. The smoke gate
  compiles and runs C and Fortran MPI hello-world binaries with MPICH,
  MVAPICH2, and OpenMPI, confirms compiler/MPI linkage through `/opt/ohpc`,
  verifies LIKWID command startup, and checks selected ELF dependencies in the
  relevant module context.
- Ubuntu ppc64el GNU15 core runtime validation passes for OpenMPI, MPICH, and
  MVAPICH2. The smoke gate compiles and runs C and Fortran MPI hello-world
  binaries and confirms compiler/MPI linkage through `/opt/ohpc`. A scheduled
  and manually dispatched GitHub Actions workflow runs the same public-repo
  smoke gate on the `power-ohpc` self-hosted POWER runner.
- LIKWID POWER support is shared source drift. The RPM spec now matches the
  Debian ppc64el build by using LIKWID `GCCPOWER`, `perf_event`, and the POWER
  event parser backport. EL10 and openEuler POWER RPM rebuilds were validated
  with `likwid-topology`, `likwid-perfctr`, and selected `ldd` checks.
- MPICH on EL10 POWER exposed a shared RPM metadata issue: `libmpi.so` links to
  `hwloc`, but the generated modulefile did not load `hwloc`. The RPM spec now
  adds the missing build, runtime, and module dependencies so MPI wrapper links
  resolve cleanly in a fresh public-repo install. The refreshed EL10 and
  openEuler MPICH RPM/SRPM artifacts have been published to the public mirror.
- The EL10 lower package count is expected. openEuler publishes additional
  support RPMs only because those libraries are missing from openEuler POWER OS
  repositories; the OpenHPC package set is not larger on openEuler.
- Ubuntu Intel oneAPI and CUDA compatibility packages are Debian-only metadata
  drift. Their upstream APT source files explicitly target `amd64`, so the
  OpenHPC wrapper packages are `Architecture: amd64` and do not appear in the
  ppc64el/all package view.
