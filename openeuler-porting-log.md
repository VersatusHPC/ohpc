# OpenHPC openEuler 24.03 ppc64le Porting Log

## Prototype Status: FEASIBLE but COMPLEX

### What Works
- openEuler 24.03 LTS has ppc64le ISOs and an OS package repo (~2362 packages)
- Container bootstrapped via `dnf --installroot` from Huawei mirror
- **ohpc-filesystem** + **ohpc-buildroot**: builds and installs cleanly
- **lmod**: builds after rebuilding `lua-devel` + `lua-filesystem` from SRPMs
- Podman-based build workflow validated

### Key Challenge: Incomplete ppc64le Package Repo

openEuler 24.03 ppc64le ships the `OS` repo with **217 -devel packages** —
most of what OpenHPC needs. The `everything` repo (openEuler's equivalent
of EL's CRB/CodeReady Builder) **does not exist for ppc64le**.

| Repo | x86_64 | aarch64 | ppc64le |
|------|--------|---------|---------|
| OS | ~2540 pkgs | ~2500 pkgs | ~2362 pkgs |
| everything (CRB equiv) | ~30k pkgs | ~30k pkgs | **NOT AVAILABLE** |
| EPOL | available | available | **NOT AVAILABLE** |
| update | available | available | **NOT AVAILABLE** |

**Note:** SP1 and SP2 dropped ppc64le entirely — only the base 24.03 LTS has it.

### Available vs Missing -devel Packages

Most critical -devel packages **ARE available** in the ppc64le OS repo:
openssl-devel, ncurses-devel, readline-devel, libxml2-devel, zlib-devel,
bzip2-devel, xz-devel, tcl-devel, binutils-devel, numactl-devel,
libevent-devel, pam-devel, expat-devel, libcurl-devel, rdma-core-devel
(provides libibverbs-devel + librdmacm-devel).

**Only 6 packages need SRPM rebuild:**

| Package | Status | Notes |
|---------|--------|-------|
| lua-devel | Built in prototype | From lua SRPM |
| lua-filesystem | Built in prototype | From lua-filesystem SRPM |
| jsoncpp-devel | Need to build | For cmake |
| json-c-devel | Need to build | For slurm |
| libfabric-devel | Need to build | For MPI stacks |
| freeipmi-devel | Need to build | For conman/slurm (optional) |

Additionally, OpenHPC builds its own hwloc and munge, so hwloc-devel
and munge-devel are self-provided and not blocking.

### SRPM Rebuild Process

For each missing package:
1. Download SRPM from `source/Packages/` on the openEuler mirror
2. `rpmbuild --rebuild --nodeps <package>.src.rpm`
3. Install the resulting -devel RPM

This works — SRPMs exist and compile on ppc64le.

### Container Images

| Image | Description |
|-------|-------------|
| `openeuler-24.03-ppc64le` | Base rootfs (341 MB) |
| `openeuler-24.03-ppc64le-ohpc-builder` | With build tools + OHPC bootstrap (1.85 GB) |

### Packages Built in Prototype

- ohpc-filesystem-4.1-3.noarch
- ohpc-buildroot-4.1-3.noarch
- lmod-ohpc-9.0.5-1.ppc64le
- lua-5.4.6-1.ppc64le (from SRPM)
- lua-devel-5.4.6-1.ppc64le (from SRPM)
- lua-filesystem-1.8.0-1.ppc64le (from SRPM)

### Effort Estimate

Building the full OpenHPC stack on openEuler 24.03 ppc64le requires:
1. **Pre-work**: Rebuild ~20-30 missing -devel packages from SRPMs
2. **OpenHPC builds**: Same spec files as EL10 (openEuler conditionals already exist)
3. **OHPC_setup_compiler**: Same ppc64le changes apply (already in versatushpc/4.x)

Estimated additional effort vs EL10 port: ~half a day for the 6 SRPM rebuilds,
then the same build process. Much less work than initially estimated.

### Mirror

- Huawei mirror (fast): `https://mirrors.huaweicloud.com/openeuler/openEuler-24.03-LTS/`
- Official (slow from outside China): `https://repo.openeuler.org/openEuler-24.03-LTS/`
