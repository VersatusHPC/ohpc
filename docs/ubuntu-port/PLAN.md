# OpenHPC Ubuntu Port — Implementation Plan

## Context

OpenHPC is an HPC software stack that produces ~92 RPM packages for Enterprise Linux.
VersatusHPC needs to port it to Ubuntu 24.04 LTS (noble) with a path to 26.04, producing
.deb packages for amd64 and arm64. The approach is native Debian packaging (`debian/`
directories coexisting with `SPECS/`), not spec-to-deb conversion, for long-term
maintainability.

The host is RHEL 10.1, 32 cores, 251GB RAM, x86_64 with sudo access. Libvirt is installed;
podman is available to install. We use podman containers for build/test environments.

---

## Phase 0: Build Environment Setup

**Goal:** Working Ubuntu 24.04 build container with Debian packaging tools and a local APT
repository.

1. Install podman: `sudo dnf install -y podman`
2. Create `containers/ubuntu-noble/Containerfile` — Ubuntu 24.04 image with `build-essential`,
   `dpkg-dev`, `debhelper`, `devscripts`, `reprepro`, `ccache`, `liblua5.4-dev`, `lua-posix`,
   `lua-filesystem`, `tcl-dev`, `python3-dev`, etc.
3. Create `devel/apt-repo/` — local APT repository using reprepro, bind-mounted into containers
4. Verify by building a trivial "hello" .deb package inside the container

**Key files:**
- `containers/ubuntu-noble/Containerfile` (new)
- `devel/apt-repo/conf/distributions` (new)

---

## Phase 1: Debian Packaging Infrastructure

**Goal:** The Debian equivalent of `OHPC_macros` + build scripts — the foundation everything
else depends on.

### 1.1 Shared variables (replaces `components/OHPC_macros`)

Create `components/OHPC_vars.mk` — makefile include with all OHPC path definitions,
compiler/MPI family defaults, and helper functions. Every `debian/rules` will include this.

Create `components/OHPC_vars.sh` — shell-sourceable version for scripts.

### 1.2 Package naming

Preserve the RPM convention: `{pname}-ohpc`, `{pname}-{compiler}-ohpc`,
`{pname}-{compiler}-{mpi}-ohpc`. These are valid Debian package names.

### 1.3 Dependency name mapping

Create `devel/dep-map.yaml` mapping RPM BuildRequires to Ubuntu Build-Depends
(e.g., `numactl-devel` -> `libnuma-dev`, `openssl-devel` -> `libssl-dev`).

### 1.4 Build script

Create `misc/build_deb.sh` — equivalent of `misc/build_srpm.sh`. Takes component path,
compiler family, MPI family as args. Runs `dpkg-buildpackage` or invokes sbuild.

### 1.5 Templates

Create `devel/templates/` with template `debian/` directories for three package types:
- **Independent** (no compiler/MPI dep)
- **Compiler-dependent** (uses `OHPC_setup_compiler`)
- **Compiler+MPI-dependent** (uses both setup scripts)

Each template includes: `control.in`, `rules`, `changelog`, `copyright`, `source/format`,
`source/lintian-overrides` (for `/opt/ohpc` paths), and `compat`.

### 1.6 Cross-cutting overrides needed in all debian/rules

```makefile
override_dh_usrlocal:     # allow files in /opt/ohpc
override_dh_shlibdeps:    # handle libs in /opt/ohpc
override_dh_strip:        # preserve /opt/ohpc debug info
```

**Key files:**
- `components/OHPC_vars.mk` (new)
- `components/OHPC_vars.sh` (new)
- `devel/dep-map.yaml` (new)
- `misc/build_deb.sh` (new)
- `devel/templates/{independent,compiler-dep,mpi-dep}/debian/` (new)

---

## Phase 2: Bootstrap Packages

**Goal:** The three foundation packages with zero OHPC dependencies, built and installable.

### 2.1 ohpc-filesystem
- Source: `components/admin/ohpc-filesystem/SPECS/ohpc-filesystem.spec`
- Creates `/opt/ohpc` directory tree + installs `OHPC_setup_compiler` and `OHPC_setup_mpi`
- Produces two binary packages: `ohpc-filesystem` (dirs) and `ohpc-buildroot` (setup scripts)
- Skip RPM-specific `ohpc-find-requires`/`ohpc-find-provides` (not needed for dpkg)

### 2.2 lmod-ohpc
- Source: `components/admin/lmod/SPECS/lmod.spec`
- Builds Lmod 9.0.5 from source, installs to `/opt/ohpc/admin/lmod/`
- Build-Depends: `liblua5.4-dev`, `lua-filesystem`, `lua-posix`, `tcl-dev`
- Installs profile.d scripts for shell integration

### 2.3 ohpc-release
- Source: `components/admin/ohpc-release/SPECS/release.spec`
- Creates `/etc/ohpc-release` and `/etc/apt/sources.list.d/ohpc.list` (instead of yum.repos.d)
- Installs GPG key to `/usr/share/keyrings/`

**Deliverable:** All three installed in container, `module avail` works.

---

## Phase 3: Compiler Stack

### 3.1 gnu15-compilers-ohpc
- Source: `components/compiler-families/gnu-compilers/SPECS/gnu-compilers.spec`
- Builds GCC 15.2.0 from source with bundled GMP/MPC/MPFR
- Installs to `/opt/ohpc/pub/compiler/gcc/15.2.0`
- Creates Lua modulefile at `/opt/ohpc/pub/modulefiles/gnu15/15.2.0.lua`
- Start with gnu15 only; add gnu12/13/14 later

**Deliverable:** `module load gnu15` activates GCC 15.2.0 in the container.

---

## Phase 4: Core Infrastructure (Independent Packages)

Build order (respecting inter-dependencies):
1. **hwloc-ohpc** — `components/dev-tools/hwloc/` -> `/opt/ohpc/pub/libs/hwloc`
2. **ucx-ohpc** — `components/mpi-families/ucx/` -> `/opt/ohpc/pub/libs/ucx` (multiple binary pkgs)
3. **pmix-ohpc** — `components/rms/pmix/` -> `/opt/ohpc/admin/pmix` (depends on hwloc)
4. **munge-ohpc** — `components/rms/munge/` (+ systemd service)
5. **slurm-ohpc** — `components/rms/slurm/` (~15 binary packages, depends on pmix, hwloc, munge)

---

## Phase 5: MPI Stack (Compiler-Dependent)

1. **openmpi5-gnu15-ohpc** — `components/mpi-families/openmpi/` -> `/opt/ohpc/pub/mpi/openmpi5-gnu15/5.0.10`
2. **mpich-gnu15-ohpc** — `components/mpi-families/mpich/`

Depends on: Phases 3 + 4 (gnu15, hwloc, ucx, pmix).

**Deliverable:** `module load gnu15 openmpi5` + simple MPI hello-world compiles and runs.

---

## Phase 6: Serial Libraries (Compiler-Dependent)

All install to `/opt/ohpc/pub/libs/{compiler}/{pname}/{version}`. Build order:

1. openblas, gsl, metis, scotch, superlu (no inter-deps)
2. plasma (depends on openblas)
3. R (depends on openblas)
4. opari2, cubelib, gotcha, cubew, otf2 (perf tool foundations)

---

## Phase 7: Parallel Libraries (Compiler+MPI-Dependent)

All install to `/opt/ohpc/pub/libs/{compiler}/{mpi}/{pname}/{version}`. Build order:

1. fftw, hdf5, pnetcdf, boost, scalapack (no OHPC lib inter-deps)
2. netcdf (depends on hdf5, pnetcdf)
3. netcdf-fortran, netcdf-cxx (depend on netcdf)
4. hypre, mumps, superlu_dist (depend on openblas, metis, scotch)
5. petsc (depends on many above)
6. slepc (depends on petsc)
7. trilinos (depends on many — build last)
8. mfem, opencoarrays, adios2, sionlib

---

## Phase 8: Remaining Packages

- **Perf tools:** papi, likwid, scorep, scalasca, tau, extrae, dimemas, paraver, pdtoolkit, imb, omb
- **Dev tools:** cmake, valgrind, spack, easybuild, numpy, scipy, mpi4py
- **Admin:** conman, genders, pdsh, prun, nhc, losf, mrsh, hpc-workspace
- **Other:** charliecloud, warewulf (may skip provisioning initially)

---

## Phase 9: CI/CD and Repository

1. Create `.github/workflows/validate-ubuntu.yml` — build all packages in Ubuntu container
2. Set up public APT repository (OBS with Ubuntu_24.04 target, or self-hosted with reprepro)
3. Create `components/admin/meta-packages/debian/` — group install packages
4. Documentation: Ubuntu install guide

---

## Versioning Convention

Debian format: `{upstream_version}-{ohpc_revision}ohpc1~noble`
- Example: OpenBLAS 0.3.32 -> `0.3.32-1ohpc1~noble`
- The `~noble` suffix allows clean upgrades to future Ubuntu releases

---

## Verification Strategy

After each phase:
1. Build packages inside the Ubuntu 24.04 container using `dpkg-buildpackage`
2. Install into a clean Ubuntu 24.04 container via the local APT repo
3. Run `lintian` for packaging quality
4. Verify `module load` / `module avail` for packages that install modules
5. For compiler/MPI packages: compile and run a trivial test program
6. For slurm: verify daemons start with `systemctl`

---

## Execution Order

Start with **Phase 0 -> 1 -> 2** as one unit (environment + infrastructure + bootstrap).
This establishes the patterns everything else follows. Then Phase 3 (compilers), then
Phases 4-5 in parallel where possible. Phases 6-8 are the bulk of the work but follow
established templates. Phase 9 runs in parallel with Phases 6-8.
