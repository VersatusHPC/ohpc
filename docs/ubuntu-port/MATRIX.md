# OpenHPC Ubuntu Port — Build Variant Matrix

This document tracks which compiler x MPI combinations have been built for each package.

## Compilers (matching upstream OHPC 4.x for EL10)

| Compiler | Version | Status |
|----------|---------|--------|
| gnu15 | GCC 15.2.0 | DONE |
| intel | oneAPI (wrapper) | - |

Note: Older GCC versions (gnu12/13/14) are not targeted for the Ubuntu port.
ARM and LLVM compilers may be added later if needed.

## MPI Stacks Available

| MPI | Version | gnu15 | intel |
|-----|---------|-------|-------|
| openmpi5 | 5.0.10 | DONE | - |
| mpich | 5.0.0 | DONE | - |
| mvapich2 | | - | - |
| impi | | N/A | - |
| mvapich2 | | - | - | - |
| impi | | - | - | - |

## Independent Packages (no compiler/MPI dependency)

| Package | Version | Status |
|---------|---------|--------|
| ohpc-filesystem | 4.1 | DONE |
| ohpc-buildroot | 4.1 | DONE |
| lmod-ohpc | 9.0.5 | DONE |
| ohpc-release | 4.1 | DONE |
| hwloc-ohpc | 2.13.0 | DONE |
| ucx-ohpc | 1.20.0 | DONE |
| pmix-ohpc | 4.2.9 | DONE |
| munge-ohpc | 0.5.13 | DONE |
| slurm-ohpc | 25.05.6 | DONE |

## Compiler-Dependent Packages (serial libraries)

| Package | Version | gnu15 | intel |
|---------|---------|-------|-------|
| openblas | 0.3.32 | DONE | - |
| gsl | 2.8 | DONE | - |
| metis | 5.1.0 | DONE | - |
| scotch | 7.0.10 | DONE | - |
| superlu | 7.0.1 | DONE | - |
| plasma | | - | - |
| R | | - | - |
| opari2 | | - | - |
| cubelib | | - | - |
| gotcha | | - | - |
| cubew | | - | - |
| otf2 | | - | - |

## Compiler+MPI-Dependent Packages (parallel libraries)

| Package | Version | gnu15+ompi5 | gnu15+mpich | gnu15+mvapich2 | intel+impi |
|---------|---------|-------------|-------------|----------------|------------|
| fftw | 3.3.10 | WIP | - | - | - |
| hdf5 | 2.1.0 | WIP | - | - | - |
| scalapack | 2.2.2 | WIP | - | - | - |
| boost | 1.90.0 | WIP | - | - | - |
| pnetcdf | | - | - | - | - |
| netcdf | | - | - | - | - |
| netcdf-fortran | | - | - | - | - |
| netcdf-cxx | | - | - | - | - |
| hypre | | - | - | - | - |
| mumps | | - | - | - | - |
| superlu_dist | | - | - | - | - |
| petsc | | - | - | - | - |
| slepc | | - | - | - | - |
| trilinos | | - | - | - | - |
| mfem | | - | - | - | - |
| opencoarrays | | - | - | - | - |
| adios2 | | - | - | - | - |
| sionlib | | - | - | - | - |

## Legend

| Symbol | Meaning |
|--------|---------|
| DONE | Built and in APT repo |
| WIP | In progress |
| - | Not started |
| N/A | Not applicable for this combination |
