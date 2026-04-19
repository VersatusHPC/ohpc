# OpenHPC 4.x ppc64le Port — Porting Log

## Summary

| Platform | Components | Binary RPMs | Source RPMs |
|----------|-----------|-------------|-------------|
| EL10 (AlmaLinux/Rocky/RHEL) | 68/68 | 117 | 72 |
| openEuler 24.03 LTS | 68/68 | 150 | 73 |
| Ubuntu 24.04 LTS | active ppc64el port | native `.deb` build path | local APT repo |

**Repository**: <https://repos.versatushpc.com.br/openhpc/versatushpc-4/>

All 68 architecture-portable OpenHPC 4.x components build and install on
ppc64le (IBM POWER9+) for the RPM-based EL10/openEuler targets. Ubuntu 24.04
uses Debian architecture name `ppc64el` for the same hardware; that build path
is native Podman-based because OBS is not available for our POWER target. Only
components inherently locked to other architectures are excluded (Intel
compilers/MPI, CUDA, ARM compilers, geopm, msr-safe, and kernel-module-only
efforts such as Lustre client packaging).

## Built Components

| Package | Version | Category | Notes |
|---------|---------|----------|-------|
| ohpc-filesystem + ohpc-buildroot | 4.1 | NOARCH | Bootstrap |
| lmod | 9.0.5 | BOOTSTRAP | |
| gnu15-compilers | 15.2.0 | SYS_COMPILER | GCC compiled from source |
| cmake | 4.3.0 | SYS_COMPILER | |
| hwloc | 2.13.0 | SYS_COMPILER | |
| ucx (+ib,rdmacm,cma) | 1.20.0 | SYS_COMPILER | |
| pmix | 4.2.9 | SYS_COMPILER | |
| papi | 7.2.0 | SYS_COMPILER | |
| valgrind | 3.26.0 | SYS_COMPILER | |
| munge (+devel,libs) | 0.5.13 | SYS_COMPILER | |
| slurm (full stack) | 25.05.6 | SYS_COMPILER | |
| openpbs (server,exec,client,devel) | 23.06.06 | SYS_COMPILER | |
| conman | 0.3.1 | SYS_COMPILER | |
| pdsh (+mods) | 2.36 | SYS_COMPILER | |
| genders (+compat) | 1.32 | SYS_COMPILER | |
| flex | 2.6.4 | SYS_COMPILER | |
| openmpi5 | 5.0.10 | OHPC_COMP | |
| mpich | 5.0.0 | OHPC_COMP | ofi fabric |
| openblas | 0.3.32 | OHPC_COMP | TARGET=POWER9 |
| gsl | 2.8 | OHPC_COMP | |
| metis | 5.1.0 | OHPC_COMP | |
| superlu | 7.0.1 | OHPC_COMP | |
| gotcha | 1.0.8 | OHPC_COMP | |
| opari2 | 2.0.9 | OHPC_COMP | |
| cubelib | 4.9.1 | OHPC_COMP | |
| cubew | 4.9.1 | OHPC_COMP | |
| R | 4.5.3 | OHPC_COMP | |
| plasma | 25.5.27 | OHPC_COMP | |
| boost | 1.90.0 | OHPC_COMP+MPI | |
| fftw | 3.3.10 | OHPC_COMP+MPI | VSX SIMD |
| scalapack | 2.2.2 | OHPC_COMP+MPI | |
| hypre | 3.1.0 | OHPC_COMP+MPI | |
| hdf5 | 2.1.0 | OHPC_COMP | Serial |
| phdf5 | 2.1.0 | OHPC_COMP+MPI | Parallel |
| netcdf | 4.10.0 | OHPC_COMP+MPI | |
| netcdf-fortran | 4.6.2 | OHPC_COMP+MPI | |
| netcdf-cxx | 4.3.1 | OHPC_COMP+MPI | |
| pnetcdf | 1.14.1 | OHPC_COMP+MPI | |
| ptscotch | 7.0.10 | OHPC_COMP+MPI | |
| sionlib | 1.7.7 | OHPC_COMP+MPI | |
| mumps | 5.8.2 | OHPC_COMP+MPI | |
| superlu_dist | 9.2.1 | OHPC_COMP+MPI | |
| otf2 | 3.1.1 | OHPC_COMP+MPI | |
| petsc | 3.24.4 | OHPC_COMP+MPI | |
| slepc | 3.24.3 | OHPC_COMP+MPI | |
| trilinos | 17.0.0 | OHPC_COMP+MPI | |
| mfem | 4.9 | OHPC_COMP+MPI | |
| scorep | 9.4 | OHPC_COMP+MPI | |
| scalasca | 2.6.2 | OHPC_COMP+MPI | |
| extrae | 5.0.3 | OHPC_COMP+MPI | |
| dimemas | 5.5.0 | OHPC_COMP+MPI | |
| imb | 2021.10 | OHPC_COMP+MPI | |
| omb | 7.5.2 | OHPC_COMP+MPI | |
| mpi4py | 4.1.1 | OHPC_COMP+MPI | |
| numpy | 2.4.3 | OHPC_COMP | VSX3 fix (PR #29627) |
| adios2 | 2.11.0 | OHPC_COMP+MPI | |
| pdtoolkit | 3.25.1 | OHPC_COMP | ibm64linux platform |
| tau | 2.35.1 | OHPC_COMP+MPI | |
| charliecloud | 0.43 | SYS_COMPILER | |
| opencoarrays | 2.10.3 | OHPC_COMP+MPI | Built with MPICH (not OpenMPI) |
| warewulf | 4.6.5 | PROVISIONING | |
| EasyBuild | 5.2.1 | DEV_TOOLS | |
| spack | 1.1.1 | DEV_TOOLS | |
| losf | 0.56.0 | ADMIN | |
| nhc | 1.4.3 | ADMIN | |
| prun | 2.2 | ADMIN | |
| magpie | 4.0.2 | ADMIN | |
| examples | 2.6 | ADMIN | |
| Cython | 3.2.4 | DEV_TOOLS | |
| mvapich2 | 2.3.7 | OHPC_COMP | |

## Packages Initially Thought Unportable — Now Built

| Package | Initial Issue | Fix Applied |
|---------|--------------|-------------|
| pdtoolkit | `ibm64linux` dir missing | Create `ibm64linux/bin` before configure; guard rose-header-gen sed |
| tau | Blocked by pdtoolkit | Built after pdtoolkit fix |
| numpy | VSX3 intrinsics compiled for VSX2 targets | Apply upstream PR #29627 fixes via sed in `%prep` |
| adios2 | Missing numpy + mpi4py modules | Built after numpy + mpi4py installed |
| charliecloud | GitLab package registry URL | Manual wget from gitlab package_files |
| opencoarrays | OpenMPI incompatible with gfortran 15 coarray | Built with MPICH instead of OpenMPI |

## Packages NOT Ported (architecture-locked)

| Package | Reason |
|---------|--------|
| intel-compilers-devel | x86_64 only (Intel proprietary) |
| impi-devel | x86_64 only (Intel MPI) |
| cuda-devel | x86_64 only (NVIDIA) |
| arm-compilers-devel | aarch64 only (ARM) |
| geopm | x86_64 only (Intel RAPL/MSR) |
| msr-safe | x86 MSR registers only |
| lustre-client | Kernel module (separate effort) |

## Spec File Changes (21 files, +88 -41 lines)

All changes are minimal and conditional (`%ifarch ppc64le`), preserving
compatibility with upstream x86_64 and aarch64 builds.

| File | Change |
|------|--------|
| `OHPC_setup_compiler` | Add ppc64le detection with `-mcpu=power9 -mtune=power9`; skip `-mtune=generic` on ppc64le |
| `openblas.spec` | Add `TARGET=POWER9 NUM_THREADS=256` |
| `fftw.spec` | Add `--enable-vsx` for VSX SIMD |
| `boost.spec` | Add `architecture="power"` for Boost.Build |
| `llvm-compilers.spec` | Add ppc64le triple `powerpc64le-linux-gnu` and `PowerPC` target |
| `gnu-compilers.spec` | Make whatis description arch-generic |
| `meta-packages.spec` | Add ppc64le to exclusion lists (mvapich2, Intel, etc.) |
| `likwid.spec` | Add ppc64le with perf_event access |
| `pdtoolkit.spec` | Create `ibm64linux/bin` before configure; use `ibm64linux` as arch_dir; guard rose-header-gen sed |
| `munge.spec` | Remove .la file reference (EL10 brp-remove-la-files) |
| `slurm.spec` | Remove deprecated sview subpackage (SLURM 25.x) |
| `python-numpy.spec` | Apply NumPy PR #29627 VSX3 fix via sed |
| 9 other specs | Add `ppc64le` to `BuildArch` or `ExclusiveArch` |

## Build Infrastructure

### Required `~/.rpmmacros`

```
%__brp_check_rpaths %{nil}
%__spec_build_shell /bin/bash
%__spec_install_shell /bin/bash
%__spec_build_pre \
  export MODULEPATH=/opt/ohpc/pub/modulefiles:/opt/ohpc/admin/modulefiles\
  source /opt/ohpc/admin/lmod/lmod/init/bash\
  %{___build_pre}
%__spec_install_pre \
  export MODULEPATH=/opt/ohpc/pub/modulefiles:/opt/ohpc/admin/modulefiles\
  source /opt/ohpc/admin/lmod/lmod/init/bash\
  %{___build_pre}
```

### openEuler 24.03 Notes

openEuler 24.03 ppc64le ships only the `OS` repo (~2362 packages). The
`everything` and `EPOL` repos are not available for ppc64le, and SP1/SP2
dropped ppc64le entirely. Only 6 additional packages needed SRPM rebuilds
(lua, lua-filesystem, libfabric, freeipmi, libedit, yaml-cpp). All builds
run inside a Podman container (`oe-builder`) using the same spec files as EL10.

### Key Findings

- `-mtune=generic` is NOT valid on ppc64le GCC — must be skipped
- Lmod must be explicitly sourced in rpmbuild scripts (not available by default)
- rpmbuild must use `/bin/bash` (not `/bin/sh`) for module function to work
- OHPC packages install under `/opt/ohpc/` which triggers rpath checks — disable with `%__brp_check_rpaths %{nil}`
- Source tarballs must be in the component SOURCES directories
