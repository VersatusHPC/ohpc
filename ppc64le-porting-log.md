# OpenHPC ppc64le Porting Log

## Summary

- **78 RPMs** built for ppc64le on EL10 (AlmaLinux 10)
- **Repository**: `/home/ferrao/ohpc-repo/EL10/ppc64le/`
- **Branch**: `ppc64le-support` on VersatusHPC/ohpc

## Successfully Built Packages (78 RPMs)

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

## Packages NOT Ported (architecture limitations)

| Package | Reason |
|---------|--------|
| intel-compilers-devel | BuildArch: x86_64 (Intel proprietary) |
| impi-devel | BuildArch: x86_64 (Intel MPI) |
| cuda-devel | BuildArch: x86_64 (NVIDIA) |
| arm-compilers-devel | BuildArch: aarch64 (ARM) |
| msr-safe | x86 MSR registers only |
| lustre-client | Kernel module (separate effort) |
| pdtoolkit | Pre-built parser binaries (x86_64/arm64 only) |
| tau | Depends on pdtoolkit |

## Packages With Build Issues (need further work)

| Package | Issue | Potential Fix |
|---------|-------|---------------|
| numpy | VSX builtin flags not propagating to meson-python | Need meson cross-compile config or upstream fix |
| adios2 | Depends on numpy module | Build after numpy is fixed |
| charliecloud | Source hosted on GitLab package registry with dynamic URL | Manual download needed |
| opencoarrays | Source download from GitHub failed | Retry download |

## Spec File Changes Made for ppc64le

1. `components/OHPC_setup_compiler` — Add ppc64le detection with `-mcpu=power9 -mtune=power9`; skip `-mtune=generic` on ppc64le
2. `components/serial-libs/openblas/SPECS/openblas.spec` — Add `TARGET=POWER9 NUM_THREADS=256`
3. `components/parallel-libs/fftw/SPECS/fftw.spec` — Add `--enable-vsx` for VSX SIMD
4. `components/parallel-libs/boost/SPECS/boost.spec` — Add `architecture="power"` for Boost.Build
5. `components/compiler-families/llvm-compilers/SPECS/llvm-compilers.spec` — Add ppc64le triple `powerpc64le-linux-gnu` and `PowerPC` target
6. `components/compiler-families/gnu-compilers/SPECS/gnu-compilers.spec` — Make whatis description arch-generic
7. `components/admin/meta-packages/SPECS/meta-packages.spec` — Add ppc64le to exclusion lists (mvapich2, Intel, etc.)
8. `components/perf-tools/likwid/SPECS/likwid.spec` — Add ppc64le with perf_event access
9. `components/perf-tools/pdtoolkit/SPECS/pdtoolkit.spec` — Add ppc64le arch_dir, exclude x86-only binaries
10. `components/rms/munge/SPECS/munge.spec` — Remove .la file reference (EL10 brp-remove-la-files)
11. `components/rms/slurm/SPECS/slurm.spec` — Remove deprecated sview subpackage (SLURM 25.x)
12. `components/dev-tools/numpy/SPECS/python-numpy.spec` — Add `-mcpu=power9 -mvsx` for ppc64le via meson args

## Build Infrastructure Notes

### ~/.rpmmacros required settings
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

### Key findings
- `-mtune=generic` is NOT valid on ppc64le GCC — must be skipped
- Lmod must be explicitly sourced in rpmbuild scripts (not available by default)
- rpmbuild must use `/bin/bash` (not `/bin/sh`) for module function to work
- OHPC packages install under `/opt/ohpc/` which triggers rpath checks — disable with `%__brp_check_rpaths %{nil}`
- Source tarballs must be in the worktree SOURCES directories, not the main repo
