# OpenHPC Ubuntu Port — Maintainer Guide

## How the Debian Packaging Works

Each OpenHPC component has a `debian/` directory alongside its existing `SPECS/` directory.
The `debian/` directory is self-contained — it downloads sources, applies patches, configures,
builds, and installs the package.

### Building a package

```bash
# Using the build script (runs in container):
misc/build_deb.sh components/admin/lmod

# For compiler-dependent packages:
misc/build_deb.sh components/serial-libs/openblas gnu15

# For MPI-dependent packages:
misc/build_deb.sh components/parallel-libs/fftw gnu15 openmpi5

# Or manually in a container:
podman run --rm \
  -v /path/to/ohpc:/build:Z \
  -v /path/to/apt-repo:/opt/ohpc-repo:Z \
  ohpc-build-ubuntu:noble \
  bash -c "
    echo 'deb [trusted=yes] file:///opt/ohpc-repo noble main' > /etc/apt/sources.list.d/ohpc.list
    apt-get update -qq
    apt-get install -y <build-dependencies>
    cd /build/components/<category>/<package>
    dpkg-buildpackage -b -nc -d -us -uc
  "
```

### Adding a package to the local repository

```bash
podman run --rm \
  -v /path/to/ohpc:/build:Z \
  -v /path/to/apt-repo:/opt/ohpc-repo:Z \
  ohpc-build-ubuntu:noble \
  reprepro -b /opt/ohpc-repo includedeb noble /build/components/<path>/<package>.deb
```

## Package Types

### 1. Bootstrap packages (no OHPC dependencies)
- ohpc-filesystem, lmod-ohpc, ohpc-release
- `debian/rules` is standalone, no OHPC_vars.mk include needed
- Built first, everything depends on these

### 2. Independent packages (depend on ohpc-filesystem only)
- hwloc, ucx, pmix, munge, slurm, cmake, etc.
- Install to fixed paths under `/opt/ohpc/` or system paths (`/usr`)
- Build with system compiler (Ubuntu's GCC)

### 3. Compiler-dependent packages
- OpenMPI, MPICH, OpenBLAS, GSL, etc.
- Must `module load gnu15` (or other compiler) before configure/build
- Install to `/opt/ohpc/pub/libs/<compiler>/<pname>/<version>`
  or `/opt/ohpc/pub/mpi/<pname>-<compiler>/<version>`
- In `debian/rules`, the compiler is activated via:
  ```makefile
  . /opt/ohpc/admin/lmod/lmod/init/bash && module load gnu15 && ./configure ...
  ```
- The gnu15-compilers-ohpc package must be installed in the build container

### 4. Compiler+MPI-dependent packages
- FFTW, HDF5, PETSc, Trilinos, etc.
- Must `module load gnu15 openmpi5` before configure/build
- Install to `/opt/ohpc/pub/libs/<compiler>/<mpi>/<pname>/<version>`

## Key Patterns

### Source download in debian/rules
Each package downloads its source tarball if not already present:
```makefile
test -s SOURCES/<tarball> || wget -q -O SOURCES/<tarball> <url>
```
The `-s` check ensures we don't use empty files from failed downloads.

### Disabling dpkg hardening flags
GCC and Slurm need hardening disabled to avoid build failures:
```makefile
export DEB_BUILD_MAINT_OPTIONS = hardening=-all
export CFLAGS =
export CXXFLAGS =
export LDFLAGS =
```

### dh_missing override
When splitting a package into multiple binary packages using `debian/tmp`:
```makefile
override_dh_missing:
    dh_missing --list-missing
```

### dh_usrlocal override
All packages that install to `/opt/ohpc` need:
```makefile
override_dh_usrlocal:
    # OpenHPC installs to /opt/ohpc
```

### dh_shlibdeps for /opt/ohpc libraries
```makefile
override_dh_shlibdeps:
    dh_shlibdeps -l<install_path>/lib -- --ignore-missing-info || true
```

### SELinux bind mounts
On RHEL hosts with SELinux, always use `:Z` (private relabel) on podman
bind mounts. Do NOT run multiple containers with `:Z` on the same path
simultaneously — use sequential builds instead.

## Build Order

Packages must be built in dependency order. The full chain:

```
Phase 2: ohpc-filesystem → lmod-ohpc → ohpc-release
Phase 3: gnu15-compilers-ohpc
Phase 4: hwloc-ohpc → ucx-ohpc → pmix-ohpc (needs hwloc)
          munge-ohpc (independent)
          slurm-ohpc (needs hwloc, pmix, munge)
Phase 5: openmpi5-gnu15-ohpc (needs gnu15, hwloc, ucx, pmix)
          mpich-gnu15-ohpc (needs gnu15)
Phase 6: serial libs (need gnu15)
Phase 7: parallel libs (need gnu15 + openmpi5)
```

## Updating a Package Version

1. Edit `debian/changelog` — add new entry with new version
2. Edit `debian/rules` — update `VERSION` variable
3. Update `debian/modulefile` if the package installs one
4. Update `debian/control` if dependencies changed
5. Remove old source tarball from `SOURCES/` if caching
6. Build and test

## Shared Infrastructure Files

| File | Purpose |
|------|---------|
| `components/OHPC_vars.mk` | Makefile include with OHPC paths and helpers |
| `components/OHPC_vars.sh` | Shell-sourceable version of the same |
| `components/OHPC_setup_compiler` | Compiler module loading script |
| `components/OHPC_setup_mpi` | MPI module loading script |
| `misc/build_deb.sh` | Convenience build script |
| `devel/dep-map.yaml` | RPM→Debian dependency name mapping |
| `devel/apt-repo/` | Local APT repository (reprepro) |
| `containers/ubuntu-noble/Containerfile` | Build container definition |

## Container Image

The build container (`ohpc-build-ubuntu:noble`) includes all common build
dependencies. Rebuild it when adding new system-level build dependencies:

```bash
podman build -t ohpc-build-ubuntu:noble -f containers/ubuntu-noble/Containerfile containers/ubuntu-noble/
```
