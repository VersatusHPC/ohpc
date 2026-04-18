# OpenHPC Ubuntu Port — Build Fixes and Known Issues

This document records build issues encountered during the Ubuntu port and their
fixes. Essential reference for OBS migration and future maintenance.

## Common Issues

### 1. dpkg hardening flags interfere with OHPC builds

**Affects:** GCC, Slurm, METIS, ScaLAPACK, all compiler/MPI-dependent packages
**Symptom:** `-Werror` failures, LTO issues, linker flag conflicts
**Fix:** Add to top of every `debian/rules`:
```makefile
export DEB_BUILD_MAINT_OPTIONS = hardening=-all
export CFLAGS =
export CXXFLAGS =
export LDFLAGS =
```
The OHPC `OHPC_setup_compiler` script sets its own optimized flags.

### 2. Module environment not available in Makefile recipes

**Affects:** All compiler-dependent and MPI-dependent packages
**Symptom:** `module: command not found`, empty CC/CXX/FC variables
**Fix:** Use `build-comp.sh` or `build-mpi.sh` helpers that source lmod init and
`OHPC_setup_compiler` before executing the build command:
```makefile
ENV := bash /build/devel/build-comp.sh
# or for MPI packages:
ENV := OHPC_MODULES="openblas" bash /build/devel/build-mpi.sh
```

### 3. Environment variables as command arguments

**Affects:** pnetcdf, IMB, OMB, and any package using `CC=mpicc` before configure
**Symptom:** `Error 127` (command not found) — `CC=mpicc` is passed as an arg to bash
**Fix:** Wrap in `sh -c`:
```makefile
# WRONG:
cd $(SRCDIR) && $(ENV) CC=mpicc ./configure ...
# RIGHT:
cd $(SRCDIR) && $(ENV) sh -c 'CC=mpicc ./configure ...'
```

### 4. MAKEFLAGS leak from dpkg into submakes

**Affects:** METIS, any package using cmake via a wrapper Makefile
**Symptom:** `No rule to make target 'w'` — the `-w` flag is interpreted as a target
**Fix:** Either use cmake directly (bypassing the wrapper Makefile) or clear MAKEFLAGS:
```makefile
# Use cmake directly:
cd $(SRCDIR) && $(ENV) cmake -S . -B build ... && cmake --build build
```

### 5. tar ownership errors in containers

**Affects:** PAPI, any tarball with non-standard UIDs
**Symptom:** `Cannot change ownership to uid ...: Invalid argument` and tar returns error
**Fix:** Use `--no-same-owner`:
```makefile
tar --no-same-owner -xf SOURCES/foo.tar.gz
```

### 6. libfabric pkg-config advertises unavailable PSM libraries

**Affects:** MPICH (and any package linking libfabric statically)
**Symptom:** `cannot find -lpsm_infinipath`, `cannot find -lpsm2`
**Fix:** Strip PSM libs from libfabric.pc before configure:
```bash
sed -i 's/-lpsm_infinipath//g; s/-lpsm2//g; s/-lefa//g' \
    /usr/lib/$(DEB_HOST_MULTIARCH)/pkgconfig/libfabric.pc
```

### 7. lib vs lib64 paths

**Affects:** scotch/ptscotch, trilinos, and packages referencing lib64
**Symptom:** Libraries not found at expected path
**Fix:** Ubuntu uses `lib/` not `lib64/`. Modulefiles must set `_LIB` to `lib/` path.
When CMake installs to `lib64`, either pass `-DCMAKE_INSTALL_LIBDIR=lib` or fix
the modulefile to point to `lib/`.

### 8. GCC 15 strict warnings as errors

**Affects:** ScaLAPACK, older C code with implicit declarations
**Symptom:** `error: implicit declaration of function`
**Fix:** Add `-Wno-implicit-function-declaration -Wno-implicit-int -std=gnu89` to CFLAGS.
For Fortran: add `-fallow-argument-mismatch`.

### 9. Shared library creation from static archives needs -fPIC

**Affects:** ScaLAPACK, HYPRE
**Symptom:** `relocation R_X86_64_32 cannot be used when making a shared object`
**Fix:** Add `-fPIC` to both CCFLAGS and FCFLAGS before compilation.

### 10. SLEPc double /tmp prefix

**Affects:** SLEPc
**Symptom:** Files installed to `/tmp/tmp/opt/ohpc/...`
**Fix:** Use `DESTDIR=$(PKG)` (not `$(PKG)/tmp`) since SLEPc's configure already
uses `--prefix=/tmp$(INSTALL_PATH)`.

### 11. SELinux and podman bind mounts

**Affects:** All container builds on RHEL hosts
**Fix:** Set permanent SELinux context:
```bash
sudo semanage fcontext -a -t svirt_sandbox_file_t "/home/ferrao/ohpc(/.*)?"
sudo restorecon -RFv /home/ferrao/ohpc
```
Then use `:z` (shared) mount label. Do NOT use `:Z` (private) for parallel builds.

## Package-Specific Issues

| Package | Issue | Status |
|---------|-------|--------|
| papi | tar ownership in container | Fixed with --no-same-owner |
| likwid | install dir path mismatch | Needs INSTALL_PREFIX fix |
| omb | CC=mpicc arg passing | Fixed with sh -c wrapper |
| superlu_dist | ptscotch lib64 vs lib | Fixed ptscotch modulefile |
| trilinos | Complex cmake, many deps | Packaging done, build needs debugging |
| opencoarrays | GCC 15 Fortran compat | Deferred — upstream may need patches |
| mrsh | autogen.sh issues | Needs investigation |

## OBS Migration Notes

When moving to OBS:
1. OBS handles build dependencies automatically — no need for manual apt install
2. OBS uses its own chroot/container — SELinux issues go away
3. The `build-comp.sh` / `build-mpi.sh` pattern needs to work inside OBS's build env
4. dpkg-buildpackage flags are controlled by OBS — may need project-level config
5. The lib vs lib64 issue may differ if OBS uses different dpkg-architecture settings
6. Module loading during builds requires lmod-ohpc to be a BuildRequires

## Intel oneAPI vars.sh clobbers positional parameters ($@)

**Symptom:** Intel packages build "successfully" but contain zero binaries (empty packages).

**Root cause:** Sourcing Intel oneAPI `vars.sh` scripts (`compiler/latest/env/vars.sh`, `mkl/latest/env/vars.sh`, `mpi/latest/env/vars.sh`) wipes `$@` in the calling shell. Build helper scripts that end with `exec "$@"` then execute `exec` with no arguments, silently doing nothing.

**Fix:** Save and restore positional parameters around the sourcing:
```bash
_SAVED_ARGS=("$@")
. /opt/intel/oneapi/compiler/latest/env/vars.sh 2>/dev/null
set -- "${_SAVED_ARGS[@]}"
```

**Affected files:** `devel/build-comp.sh`, `devel/build-mpi.sh`, all per-package `debian-intel*/build.sh`

## numpy dh_prep wipes PKG directory

**Symptom:** numpy packages contain only modulefile, no Python files.

**Root cause:** `pip install --root=$(PKG)` was in `override_dh_auto_build`. Between build and install steps, `dh_prep` wipes `debian/<pkg>/`. So all pip-installed files are deleted before packaging.

**Fix:** Move pip install to `override_dh_auto_install`. Keep `pip wheel` in build step, `pip install` from wheel in install step.
