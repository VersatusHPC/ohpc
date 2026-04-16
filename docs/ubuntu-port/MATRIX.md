# OpenHPC Ubuntu Port — Build Variant Matrix

Last updated: 2026-03-28

## Compilers

| Compiler | Version | Status |
|----------|---------|--------|
| gnu15 | GCC 15.2.0 | DONE |
| intel | oneAPI 2025.0 (wrapper) | DONE (modulefile only) |
| llvm | 10.0.1 | Deferred (large bootstrap) |
| arm1 | ARM HPC | Deferred |

## MPI Stacks

| MPI | Version | gnu15 | intel |
|-----|---------|-------|-------|
| openmpi5 | 5.0.10 | DONE | deferred |
| mpich | 5.0.0 | DONE | deferred |
| mvapich2 | 2.3.7 | DONE | deferred |
| impi | | N/A | deferred |

## MPI-Dependent Packages (gnu15 row)

| Package | Version | openmpi5 | mpich | mvapich2 |
|---------|---------|----------|-------|----------|
| fftw | 3.3.10 | DONE | DONE | DONE |
| phdf5 | 2.1.0 | DONE | DONE | DONE |
| pnetcdf | 1.14.1 | DONE | DONE | DONE |
| boost | 1.90.0 | DONE | DONE | DONE |
| scalapack | 2.2.2 | DONE | DONE | DONE |
| sionlib | 1.7.7 | DONE | DONE | DONE |
| ptscotch | 7.0.10 | DONE | DONE | DONE |
| netcdf | 4.10.0 | DONE | DONE | DONE |
| netcdf-fortran | 4.6.2 | DONE | DONE | DONE |
| netcdf-cxx | 4.3.1 | DONE | DONE | DONE |
| hypre | 3.1.0 | DONE | DONE | DONE |
| mumps | 5.8.2 | DONE | DONE | DONE |
| otf2 | 3.1.1 | DONE | DONE | DONE |
| petsc | 3.24.4 | DONE | DONE | DONE |
| slepc | 3.24.3 | DONE | DONE | DONE |
| superlu_dist | 9.2.1 | DONE | - | - |
| trilinos | 17.0.0 | DONE | WIP | WIP |
| mfem | 4.9 | DONE | WIP | WIP |
| adios2 | 2.11.0 | DONE | WIP | WIP |
| scorep | 9.4 | DONE | DONE | DONE |
| scalasca | 2.6.2 | DONE | DONE | WIP |
| imb | 2021.10 | DONE | DONE | DONE |
| omb | 7.5.2 | DONE | DONE | DONE |
| dimemas | 5.5.0 | DONE | DONE | DONE |
| extrae | 5.0.3 | DONE | DONE | DONE |
| mpi4py | 4.1.1 | DONE | DONE | DONE |
| opencoarrays | 2.10.3 | BLOCKED | WIP | - |
| tau | 2.35.1 | BLOCKED | - | - |

## Compiler-Dependent Packages (no MPI)

| Package | Version | gnu15 | intel |
|---------|---------|-------|-------|
| openblas | 0.3.32 | DONE | - |
| gsl | 2.8 | DONE | - |
| metis | 5.1.0 | DONE | - |
| scotch | 7.0.10 | DONE | - |
| superlu | 7.0.1 | DONE | - |
| plasma | 25.5.27 | DONE | - |
| R | 4.5.3 | DONE | - |
| opari2 | 2.0.9 | DONE | - |
| cubelib | 4.9.1 | DONE | - |
| cubew | 4.9.1 | DONE | - |
| gotcha | 1.0.8 | DONE | - |
| likwid | 5.5.1 | DONE | - |
| pdtoolkit | 3.25.1 | DONE | - |
| numpy | 2.4.3 | DONE | - |

## Legend

| Symbol | Meaning |
|--------|---------|
| DONE | Built and in APT repo |
| WIP | Building now |
| BLOCKED | Upstream compatibility issue |
| - | Not yet attempted |
