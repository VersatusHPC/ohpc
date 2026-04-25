<!-- markdownlint-disable MD013 MD033 -->
# <img src="https://github.com/openhpc/ohpc/blob/master/docs/recipes/install/common/figures/ohpc_logo.png" width="170" valign="middle" hspace="5" alt="OpenHPC"/>
<!-- markdownlint-enable MD013 MD033 -->

## VersatusHPC Fork

This is the [VersatusHPC](https://versatushpc.com.br) fork of
[OpenHPC](https://github.com/openhpc/ohpc), extending the upstream project
with additional platform support:

| Platform | Architecture | Status |
|----------|-------------|--------|
| **EL10 (AlmaLinux/Rocky/RHEL)** | **ppc64le (IBM POWER)** | Available |
| **openEuler 24.03 LTS** | **ppc64le (IBM POWER)** | Available |
| **Ubuntu 24.04 LTS** | **x86_64** | Release candidate |
| **Ubuntu 24.04 LTS** | **ppc64el (IBM POWER)** | Release candidate |

### Ubuntu 24.04 Port

The `ubuntu-port` work adds Debian packaging for the OpenHPC 4.x package matrix
on Ubuntu 24.04 LTS. The x86_64 build is performed in OBS project
`VersatusHPC:OHPC:4`, repository `Ubuntu_24.04`; the ppc64el build is performed
natively on IBM POWER and merged into the same public APT repository.

As of 2026-04-19, the Ubuntu x86_64 OBS build is published with **296/296
packages succeeded**. The public repository also includes the architecture
portable ppc64el package set. Runtime validation covers a Warewulf/Slurm Ubuntu
24.04 head node and compute node, including GNU15 and Intel compiler coverage
on x86_64 across OpenMPI, MPICH, MVAPICH2, and Intel MPI, plus GNU15 OpenMPI,
MPICH, MVAPICH2, LIKWID, and linkage checks on ppc64el.

Pre-built Debian packages are available at:
<https://repos.versatushpc.com.br/openhpc/versatushpc-4/Ubuntu_24.04/>

To enable the Ubuntu repository:

```bash
sudo install -d -m 0755 /usr/share/keyrings /etc/apt/sources.list.d
OHPC_REPO_ROOT=https://repos.versatushpc.com.br/openhpc/versatushpc-4
curl -fsSL "${OHPC_REPO_ROOT}/versatushpc.gpg" \
  | sudo tee /usr/share/keyrings/versatushpc.gpg >/dev/null
curl -fsSL "${OHPC_REPO_ROOT}/Ubuntu_24.04/versatushpc-openhpc.list" \
  | sudo tee /etc/apt/sources.list.d/versatushpc-openhpc.list >/dev/null
sudo apt update
sudo apt install ohpc-release
```

For a full SMS/compute-node installation, follow the
[Ubuntu Warewulf/Slurm installation guide](docs/recipes/install/ubuntu24.04/x86_64/warewulf4/slurm/steps.pdf),
generated from the upstream LaTeX manual structure.

Operational validation is documented in `docs/ubuntu-port/VALIDATION.md` and
automated by `scripts/validate-ubuntu-runtime.sh`. The native POWER Debian build
path is documented in `docs/ubuntu-port/PPC64EL.md`; cross-distribution POWER
release checks are documented in `docs/POWER-VALIDATION.md`.

The port keeps the OpenHPC compiler/MPI package model, using Debian packaging
under `components/**/debian*`, shared build helpers under `devel/`, and local
OBS import/runtime tooling under `obs/`. Intel oneAPI dependencies are resolved
through OBS Debian Download-on-Demand against Intel's upstream APT repository.

### ppc64le Port

The `versatushpc/4.x` branch provides full OpenHPC 4.x support for **ppc64le**
(IBM POWER9+) on EL10 and openEuler 24.03. All 68 architecture-portable
components from the official OpenHPC component list are built and available,
including compilers (GCC 15), MPI stacks (OpenMPI 5, MPICH, MVAPICH2), SLURM,
OpenPBS, and the complete scientific library stack (PETSc, Trilinos, Boost,
HDF5, NetCDF, etc.).

Only components that are inherently architecture-locked are excluded:
Intel compilers/MPI, CUDA, ARM compilers, geopm, and msr-safe.

The spec file changes are minimal (~90 lines across 21 files) and fully
conditional (`%ifarch ppc64le`), preserving compatibility with upstream
x86_64 and aarch64 builds.

Pre-built RPMs are available at:
<https://repos.versatushpc.com.br/openhpc/versatushpc-4/>

All packages are signed with the VersatusHPC GPG key. To enable the repo:

```bash
# EL10
curl -o /etc/yum.repos.d/versatushpc-openhpc.repo \
  https://repos.versatushpc.com.br/openhpc/versatushpc-4/EL_10/versatushpc-openhpc.repo

# openEuler 24.03
curl -o /etc/yum.repos.d/versatushpc-openhpc.repo \
  https://repos.versatushpc.com.br/openhpc/versatushpc-4/openEuler_24.03/versatushpc-openhpc.repo
```

---

## Community building blocks for HPC systems

### Introduction

This stack provides a variety of common, pre-built ingredients required to
deploy and manage an HPC Linux cluster including provisioning tools, resource
management, I/O clients, runtimes, development tools, containers, and a variety of
scientific libraries.

There are currently three release series: the [2.x][2xbranch], the
[3.x][3xbranch] and the [4.x][4xbranch] which target different major Linux OS
distributions:

- The 2.x series targets EL8 and Leap15.
- The 3.x series targets EL9, Leap 15 and openEuler 22.03.
- The 4.x series targets EL10, openEuler 24.03, and Ubuntu 24.04 in this fork.

### Getting started

OpenHPC provides pre-built binaries via repositories for use with standard
Linux package manager tools (e.g. ```dnf``` or ```zypper```). To get started,
you can enable an OpenHPC repository locally through installation of an
```ohpc-release``` RPM which includes gpg keys for package signing and defines
the URL locations for [base] and [update] package repositories. Installation
guides tailored for each supported provisioning system and resource manager
with detailed example instructions for installing a cluster are also available.
Copies of the ```ohpc-release``` package and installation guides along with
more information is available on the relevant release series pages
([2.x][2xbranch], [3.x][3xbranch] or [4.x][4xbranch]).

---

### Questions, Comments, or Bug Reports?

Subscribe to the [users email list][userlist] or see the
<https://openhpc.community/> page for more pointers.

### Additional Software Requests?

If you would like to see new software included in OpenHPC, please
[open an issue](https://github.com/openhpc/ohpc/issues) with as much
detail as possible. Even better, consider opening a pull request directly.
A PR for a new component should typically include tests and documentation,
but we are happy to guide contributors through the process.

### Contributing to OpenHPC

Please see the steps described in [CONTRIBUTING.md](CONTRIBUTING.md).

### Register your system

If you are using elements of OpenHPC, please consider registering your system(s)
using the [System Registration Form][register].

[2xbranch]: https://github.com/openhpc/ohpc/wiki/2.x
[3xbranch]: https://github.com/openhpc/ohpc/wiki/3.x
[4xbranch]: https://github.com/openhpc/ohpc/wiki/4.x
[register]: https://drive.google.com/open?id=1KvFM5DONJigVhOlmDpafNTDDRNTYVdolaYYzfrHkOWI
[userlist]: https://groups.io/g/openhpc-users
