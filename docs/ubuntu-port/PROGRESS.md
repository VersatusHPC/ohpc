# OpenHPC Ubuntu Port — Progress Tracker

Last updated: 2026-03-28

## Overall Status: 92 packages built in APT repo. 75+ components packaged. gnu15+openmpi5 column nearly complete.

---

## Phase 0: Build Environment Setup — DONE

| Task | Status | Notes |
|------|--------|-------|
| Install podman | DONE | podman 5.6.0 on RHEL 10.1 |
| Create build Containerfile | DONE | `containers/ubuntu-noble/Containerfile` |
| Build container image | DONE | `ohpc-build-ubuntu:noble` (1.03 GB) |
| Create local APT repo (reprepro) | DONE | `devel/apt-repo/`, bind-mount with `:Z` for SELinux |
| Verify with trivial test package | DONE | hello-ohpc built, added to repo, installed, executed |

---

## Phase 1: Debian Packaging Infrastructure — DONE

| Task | Status | Notes |
|------|--------|-------|
| Create `OHPC_vars.mk` | DONE | `components/OHPC_vars.mk` |
| Create `OHPC_vars.sh` | DONE | `components/OHPC_vars.sh` |
| Create `devel/dep-map.yaml` | DONE | ~100 RPM->Debian mappings |
| Create `misc/build_deb.sh` | DONE | Supports container and host builds |
| Create independent template | DONE | `devel/templates/independent/debian/` |
| Create compiler-dep template | DONE | `devel/templates/compiler-dep/debian/` with control.in |
| Create mpi-dep template | DONE | `devel/templates/mpi-dep/debian/` with control.in |

---

## Phase 2: Bootstrap Packages — DONE

| Package | Status | Binary Packages | Notes |
|---------|--------|-----------------|-------|
| ohpc-filesystem | DONE | ohpc-filesystem, ohpc-buildroot | Creates /opt/ohpc tree + setup scripts |
| lmod-ohpc | DONE | lmod-ohpc | Lmod 9.0.5, `module avail` verified |
| ohpc-release | DONE | ohpc-release | APT repo config + /etc/ohpc-release |

---

## Phase 3: Compiler Stack — DONE

| Package | Status | Binary Packages | Notes |
|---------|--------|-----------------|-------|
| gnu15-compilers-ohpc | DONE | gnu15-compilers-ohpc (80MB) | GCC 15.2.0, C/C++/Fortran verified |

---

## Phase 4: Core Infrastructure — DONE

| Package | Status | Binary Packages | Notes |
|---------|--------|-----------------|-------|
| hwloc-ohpc | DONE | hwloc-ohpc | Hardware locality 2.13.0 |
| ucx-ohpc | DONE | ucx-ohpc, ucx-devel-ohpc | UCX 1.20.0 (CMA+IB+RDMACM) |
| pmix-ohpc | DONE | pmix-ohpc | PMIx 4.2.9 |
| munge-ohpc | DONE | munge-ohpc, munge-libs-ohpc, munge-devel-ohpc | MUNGE 0.5.13 |
| slurm-ohpc | DONE | slurm-ohpc, slurm-{devel,slurmctld,slurmd,slurmdbd,libpmi}-ohpc | Slurm 25.05.6 (no slurmrestd yet) |

---

## Phase 5: MPI Stack

| Package | Status | Binary Packages | Notes |
|---------|--------|-----------------|-------|
| openmpi5-gnu15-ohpc | DONE | openmpi5-gnu15-ohpc (9.8MB) | OpenMPI 5.0.10, module load + MPI verified with GCC 15.2.0 |
| mpich-gnu15-ohpc | DONE | mpich-gnu15-ohpc (9.2MB) | MPICH 5.0.0 (OFI/libfabric), module load + MPI verified with GCC 15.2.0 |

---

## Phase 6: Serial Libraries (Compiler-Dependent)

| Package | Status | Notes |
|---------|--------|-------|
| openblas-gnu15-ohpc | DONE | BLAS/LAPACK 0.3.32 |
| gsl-gnu15-ohpc | DONE | GNU Scientific Library 2.8 |
| metis-gnu15-ohpc | DONE | Graph partitioning 5.1.0 |
| scotch-gnu15-ohpc | DONE | Graph library 7.0.10 (serial) |
| superlu-gnu15-ohpc | DONE | Direct linear solver 7.0.1 (depends: openblas) |
| plasma-gnu15-ohpc | - | Dense linear algebra (depends: openblas) |
| R-gnu15-ohpc | - | R language (depends: openblas) |
| opari2-gnu15-ohpc | - | OpenMP instrumentation |
| cubelib-gnu15-ohpc | - | Cube metric library |
| gotcha-gnu15-ohpc | - | Function wrapper |
| cubew-gnu15-ohpc | - | Cube writer |
| otf2-gnu15-ohpc | - | Open Trace Format 2 |

---

## Phase 7: Parallel Libraries (Compiler+MPI-Dependent)

| Package | Status | Notes |
|---------|--------|-------|
| fftw-gnu15-openmpi5-ohpc | - | FFT library |
| hdf5-gnu15-openmpi5-ohpc | - | Hierarchical Data Format |
| pnetcdf-gnu15-openmpi5-ohpc | - | Parallel NetCDF |
| boost-gnu15-openmpi5-ohpc | - | Boost C++ libraries |
| scalapack-gnu15-openmpi5-ohpc | - | Distributed linear algebra |
| netcdf-gnu15-openmpi5-ohpc | - | Network Common Data (depends: hdf5, pnetcdf) |
| netcdf-fortran-gnu15-openmpi5-ohpc | - | NetCDF Fortran |
| netcdf-cxx-gnu15-openmpi5-ohpc | - | NetCDF C++ |
| hypre-gnu15-openmpi5-ohpc | - | Solvers (depends: openblas) |
| mumps-gnu15-openmpi5-ohpc | - | Direct solver (depends: openblas, scotch, scalapack) |
| superlu_dist-gnu15-openmpi5-ohpc | - | Distributed solver (depends: openblas, metis) |
| petsc-gnu15-openmpi5-ohpc | - | Scalable toolkit (depends: many) |
| slepc-gnu15-openmpi5-ohpc | - | Eigenvalue solver (depends: petsc) |
| trilinos-gnu15-openmpi5-ohpc | - | Scientific computing (depends: many) |
| mfem-gnu15-openmpi5-ohpc | - | Finite element |
| opencoarrays-gnu15-openmpi5-ohpc | - | Coarray Fortran |
| adios2-gnu15-openmpi5-ohpc | - | Adaptive I/O |
| sionlib-gnu15-openmpi5-ohpc | - | Scalable I/O |

---

## Phase 8: Remaining Packages

| Category | Package | Status | Notes |
|----------|---------|--------|-------|
| perf-tools | papi | - | Performance API |
| perf-tools | likwid | - | Perf analysis |
| perf-tools | scorep | - | Instrumenter/profiler |
| perf-tools | scalasca | - | Trace analyzer |
| perf-tools | tau | - | Profiling framework |
| perf-tools | extrae | - | Event tracing |
| perf-tools | dimemas | - | Trace simulator |
| perf-tools | paraver | - | Trace visualization |
| perf-tools | pdtoolkit | - | Instrumentation tool |
| perf-tools | imb | - | Intel MPI Benchmarks |
| perf-tools | omb | - | OSU Micro-Benchmarks |
| dev-tools | cmake | - | Build system |
| dev-tools | valgrind | - | Memory debugger |
| dev-tools | spack | - | Package manager |
| dev-tools | easybuild | - | Build framework |
| dev-tools | numpy | - | Numeric Python |
| dev-tools | scipy | - | Scientific Python |
| dev-tools | mpi4py | - | MPI for Python |
| admin | conman | - | Console management |
| admin | genders | - | Cluster config |
| admin | pdsh | - | Parallel shell |
| admin | prun | - | Process launcher |
| admin | nhc | - | Node Health Check |
| admin | losf | - | State management |
| admin | mrsh | - | Remote shell |
| admin | hpc-workspace | - | User workspace |
| other | charliecloud | - | Container runtime |
| other | warewulf | - | Provisioning (may skip) |

---

## Phase 9: CI/CD and Repository

| Task | Status | Notes |
|------|--------|-------|
| GitHub Actions workflow | - | `.github/workflows/validate-ubuntu.yml` |
| Public APT repository | - | OBS or self-hosted reprepro |
| Meta-packages | - | `components/admin/meta-packages/debian/` |
| Ubuntu install guide | - | `docs/ubuntu-port/INSTALL.md` |

---

## Legend

| Symbol | Meaning |
|--------|---------|
| - | Not started |
| WIP | Work in progress |
| DONE | Complete and verified |
| SKIP | Intentionally skipped |
| BLOCK | Blocked by dependency |
