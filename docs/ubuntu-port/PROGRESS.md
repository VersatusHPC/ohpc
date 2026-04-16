# OpenHPC Ubuntu Port — Progress Tracker

Last updated: 2026-03-28

## Overall Status

- **94 .deb packages** built and in local APT repository
- **78 components** have debian/ packaging created
- **19 git commits** on the 4.x branch
- **Target:** 1:1 port of OpenHPC 4.x to Ubuntu 24.04 LTS (noble)
- **This is an ongoing effort** — will track upstream OpenHPC releases (4.1, etc.)

---

## Packages Built and in APT Repository (94)

### Bootstrap (4)
ohpc-filesystem, ohpc-buildroot, lmod-ohpc, ohpc-release

### Compilers (2)
gnu15-compilers-ohpc (GCC 15.2.0), intel-compilers-devel-ohpc (wrapper)

### Core Infrastructure (13)
hwloc-ohpc, ucx-ohpc, ucx-devel-ohpc, pmix-ohpc,
munge-ohpc, munge-libs-ohpc, munge-devel-ohpc,
slurm-ohpc, slurm-devel-ohpc, slurm-slurmctld-ohpc, slurm-slurmd-ohpc,
slurm-slurmdbd-ohpc, slurm-libpmi-ohpc

### MPI Stacks (2)
openmpi5-gnu15-ohpc, mpich-gnu15-ohpc

### Serial Libraries — gnu15 (7)
openblas, gsl, metis, scotch, superlu, plasma, r-gnu15-ohpc

### Parallel Libraries — gnu15+openmpi5 (15)
fftw, phdf5, scalapack, boost, pnetcdf, netcdf, netcdf-fortran, netcdf-cxx,
hypre, mumps, ptscotch, petsc, slepc, superlu-dist, trilinos

### IO Libraries — gnu15 / gnu15+openmpi5 (4)
cubew, sionlib, otf2, extrae

### Performance Tools (10)
papi, likwid, pdtoolkit, scorep, scalasca, imb, omb, dimemas, opari2, gotcha

### Python Tools (2)
python3-numpy-gnu15-ohpc, python3-mpi4py-gnu15-openmpi5-ohpc

### Standalone Admin/Dev Tools (15)
prun, nhc, pdsh, conman, mrsh, cmake, valgrind, losf, genders,
hpc-workspace, charliecloud, easybuild, spack, magpie, examples

### Meta-packages (20)
ohpc-base, ohpc-base-compute, ohpc-autotools, ohpc-slurm-client,
ohpc-slurm-server, ohpc-gnu15-serial-libs, ohpc-gnu15-io-libs,
ohpc-gnu15-parallel-libs, ohpc-gnu15-perf-tools, ohpc-gnu15-python3-libs,
ohpc-gnu15-runtimes, ohpc-gnu15-openmpi5-io-libs,
ohpc-gnu15-openmpi5-parallel-libs, ohpc-gnu15-openmpi5-perf-tools,
ohpc-gnu15-mpich-io-libs, ohpc-gnu15-mpich-parallel-libs,
ohpc-gnu15-mpich-perf-tools, lmod-defaults-gnu15-openmpi5-ohpc,
examples-ohpc, hello-ohpc

---

## Packaged but Builds Need Debugging (10)

| Package | Issue | Severity |
|---------|-------|----------|
| tau 2.35.1 | GCC 15 extern "C" + OpenMP linkage error | Needs upstream patch |
| opencoarrays 2.10.3 | Upstream blocks gfortran 15 + OpenMPI | Works with MPICH only |
| mfem 4.9 | Complex make config path issues | Debug make/install paths |
| adios2 2.11.0 | CMake path issues | Debug cmake paths |
| mvapich2 2.3.7 | InfiniBand configure issues | Debug IB/RDMA config |
| openpbs 23.06.06 | Complex deps (PostgreSQL etc.) | Debug autogen/configure |
| warewulf 4.6.5 | Golang build issue | Debug go module paths |
| scipy 1.5.4 | Too old for Python 3.12 | Needs version update |
| paraver 4.12.0 | wxWidgets build error | Debug GUI deps |
| docs 4.0.0 | Needs pandoc/texlive | Missing build deps |

---

## Deferred — Not Yet Packaged (18)

| Component | Reason |
|-----------|--------|
| llvm-compilers 10.0.1 | Large from-source bootstrap, old version |
| arm-compilers-devel | ARM HPC compiler wrapper |
| cuda-devel | NVIDIA CUDA wrapper |
| lustre-client | Kernel module build (needs DKMS) |
| impi-devel | Intel MPI wrapper |
| flex | Available in Ubuntu repos |
| python-Cython | Available in Ubuntu repos |
| python-rpm-macros | RPM-specific, not needed for Debian |
| sigar | System info library |
| msr-safe | Kernel module |
| mdtoc | Build tool only |
| ohpc-release-factory | Factory release config |
| ohpc-release-staging | Staging release config |
| test-suite | Testing infrastructure |
| example | Template package |

---

## Next Steps

1. **Debug remaining build failures** (tau, mfem, adios2, mvapich2, openpbs, warewulf)
2. **Add gnu15+mpich column** — rebuild all MPI-dep packages with MPI_FAMILY=mpich
3. **Add gnu15+mvapich2 column** — after mvapich2 builds
4. **Set up OBS** for automated multi-arch (amd64+arm64) builds
5. **GitHub Actions CI** for Ubuntu build validation
6. **Track upstream** — when OpenHPC 4.1 releases, update versions and rebuild
