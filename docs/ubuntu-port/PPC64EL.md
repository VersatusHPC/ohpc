# Ubuntu 24.04 ppc64el Port

## Scope

Ubuntu calls the little-endian POWER architecture `ppc64el`; the Linux kernel
and the existing EL/openEuler port call the same hardware `ppc64le`. This phase
adds native Ubuntu 24.04 Debian package builds for IBM POWER without OBS, because
our OBS deployment only builds the Ubuntu repository on x86_64.

The target is parity with the architecture-portable OpenHPC package set already
supported by the VersatusHPC ppc64le RPM port. Architecture-locked packages stay
excluded: Intel compilers/MPI, CUDA, ARM compilers, MSR/geopm, and Lustre kernel
client packaging.

## Build Model

The build runs natively on `power.local.versatushpc.com.br` as the `builder`
user. A persistent Ubuntu 24.04 ppc64el Podman container provides Debian
packaging tools, and `scripts/build-ubuntu-ppc64el.sh` builds packages in
dependency order into a flat local APT repository under:

```text
/home/builder/ohpc-ubuntu-ppc64el/repo/Ubuntu_24.04
```

The persistent builder container is started with Podman's init reaper so long
full builds do not accumulate orphaned compiler children.

The local repository layout intentionally matches the public Ubuntu repository
style used by the amd64 OBS output:

```text
Ubuntu_24.04/
  all/
  ppc64el/
  source/
  Packages
  Packages.gz
  Packages.xz
  Sources
  Sources.gz
  Sources.xz
  Release
```

## Build Commands

Smoke build one source entry:

```bash
cd /home/builder/ohpc-versatushpc-4.x
WORK_ROOT=/home/builder/ohpc-ubuntu-ppc64el-test \
  scripts/build-ubuntu-ppc64el.sh --only components/admin/lmod/debian
```

Build the full selected ppc64el package set, resuming completed entries:

```bash
cd /home/builder/ohpc-versatushpc-4.x
WORK_ROOT=/home/builder/ohpc-ubuntu-ppc64el \
  scripts/build-ubuntu-ppc64el.sh --resume --keep-going
```

List the selected build entries and exclusions:

```bash
scripts/list-ubuntu-ppc64el-builds.py
scripts/list-ubuntu-ppc64el-builds.py --show-excluded
```

Run the native core MPI smoke gate inside the ppc64el builder container:

```bash
scripts/validate-ubuntu-ppc64el-core.sh
```


## Publishing

After the ppc64el build set passes validation, publish from the POWER builder
with:

```bash
cd /home/builder/ohpc-versatushpc-4.x
WORK_ROOT=/home/builder/ohpc-ubuntu-ppc64el \
  scripts/publish-ubuntu-ppc64el.sh --dry-run
WORK_ROOT=/home/builder/ohpc-ubuntu-ppc64el \
  scripts/publish-ubuntu-ppc64el.sh
```

The publisher fetches the current public `Ubuntu_24.04` repository, merges only
the native `ppc64el` binaries plus source artifacts, regenerates `Packages` and
`Sources`, signs `Release`, and syncs the full `Ubuntu_24.04` tree back to the
mirror. This avoids OBS for POWER while preserving the existing amd64 public
repository content.

## Current Gate

Before publishing ppc64el `.deb` files, the minimum gate is:

1. Bootstrap packages build and install from the local ppc64el APT repo.
2. `gnu15-compilers-ohpc` builds natively and installs.
3. Core stack builds: `hwloc`, `ucx`, `pmix`, `munge`, `slurm`.
4. MPI stacks build: OpenMPI, MPICH, and MVAPICH2 for GNU15.
5. Serial math baseline builds: OpenBLAS, FFTW, Boost, HDF5, NetCDF.
6. Runtime smoke validates module load, compiler identity, and MPI hello-world
   on a ppc64el Ubuntu container or VM.

A full release candidate should then run `--resume --keep-going` for the whole
selected build list. The current selector emits 140 build entries and excludes
156 architecture-locked Intel, CUDA, Lustre, ARM, MSR/geopm, and derived MPI or
library variants.

## Porting Deltas

The Debian packaging changes are architecture-conditional where the package has
architecture-specific build flags:

- LLVM builds the `PowerPC` backend on ppc64el.
- OpenBLAS uses `TARGET=POWER9 NUM_THREADS=256`.
- FFTW uses VSX instead of x86 SIMD flags.
- Boost.Build uses `architecture=power`.
- LIKWID uses the upstream POWER compiler profile and `perf_event` access mode.
  The POWER `perf_event` path also carries a small upstream-style backport for
  missing event config files and an undefined uncore event variable in 5.5.1.
- PDToolkit uses the upstream `ibm64linux` platform directory. The fallback
  source download uses HTTP because the upstream HTTPS certificate chain fails
  from the POWER builder, while the payload checksum is unchanged.
- NumPy applies the same VSX fix used by the ppc64le RPM port.
- SciPy and NumPy avoid x86_64-only local wheel paths on ppc64el.
- `genders` and `mrsh` refresh old autotools `config.guess`/`config.sub` files
  after unpacking generated source trees, matching the Debian build layout where
  sources are extracted inside `override_dh_auto_configure`.
- `munge-ohpc`, `munge-libs-ohpc`, and `munge-devel-ohpc` provide/conflict
  with the matching Ubuntu distro packages (`munge`, `libmunge2`, and
  `libmunge-dev`). The OpenHPC packages install the same MUNGE service, library
  SONAME, and development paths, so dependent packages such as Slurm must be
  able to replace distro MUNGE cleanly during build dependency resolution.
- The native build script mirrors the OBS importer behavior for `docs-ohpc` by
  copying the upstream-style LaTeX recipe inputs into the package work tree.
- Debian `dh_shlibdeps` private-library search paths use the documented single
  colon-separated `-l` value. Passing repeated `-l` options made debhelper keep
  only the last path, while `|| true` hid missing-library errors and produced
  packages without `${shlibs:Depends}` metadata. Packages that link against
  private OpenHPC libraries now explicitly include those private library
  directories: R/OpenBLAS, NetCDF/HDF5, NetCDF-Fortran/NetCDF/HDF5,
  MUMPS/OpenBLAS/ScaLAPACK, SuperLU_DIST/OpenBLAS/METIS/PT-Scotch,
  SLEPc/PETSc, MFEM/PETSc/SuperLU_DIST/NetCDF/Hypre/Scotch, Trilinos TPLs,
  Dimemas/Boost, Paraver private kernel libraries, Charliecloud's sotest
  helper library, and TAU's PDToolkit/OTF2/PAPI/runtime library directories.
- `slurm-sview-ohpc` remains a doc-only compatibility package while Slurm is
  configured `--without-x11`; its Debian control metadata avoids
  `${shlibs:Depends}` because no ELF payload is shipped in that binary package.

These are equivalent in intent to the conditional `%ifarch ppc64le` RPM changes
used by the existing EL10/openEuler POWER port, plus native-builder glue for
packages that OBS previously prepared during source import.
