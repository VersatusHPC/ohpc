# OpenHPC Ubuntu Port — OBS Setup Guide

## Overview

The Open Build Service (OBS) is used to build and publish the OpenHPC Ubuntu
packages. This setup uses containerized OBS for development, with the option
to migrate to a production OBS instance later.

## Architecture

```
                    ┌─────────────────┐
                    │   OBS Web UI    │
                    │  localhost:3000  │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
    ┌─────────▼──┐  ┌───────▼───┐  ┌───────▼───┐
    │  Frontend  │  │  Backend   │  │  Workers   │
    │  (Rails)   │  │ (src+repo) │  │  (build)   │
    └─────────┬──┘  └───────────┘  └───────────┘
              │
    ┌─────────▼──┐  ┌───────────┐
    │  MariaDB   │  │ Memcached │
    └────────────┘  └───────────┘
```

## Quick Start

### 1. Install podman-compose

```bash
sudo dnf install -y podman-compose
# or
pip3 install podman-compose
```

### 2. Start OBS

```bash
cd obs/
podman-compose up -d
```

Wait 2-3 minutes for services to initialize.

### 3. Login

Open http://localhost:3000 in a browser. Default credentials: `admin` / `opensuse`.

### 4. Create Project

```bash
# Install osc (OBS command line)
sudo dnf install -y osc
# or
pip3 install osc

# Setup the project
bash obs/setup-project.sh
```

### 5. Import Packages

```bash
bash obs/import-packages.sh
```

## Project Structure

```
VersatusHPC:OHPC:4/
├── ohpc-filesystem          (bootstrap)
├── lmod-ohpc                (bootstrap)
├── gnu15-compilers-ohpc     (compiler)
├── hwloc-ohpc               (core infra)
├── openmpi5-gnu15-ohpc      (MPI stack)
├── fftw-gnu15-openmpi5-ohpc (parallel lib)
├── fftw-gnu15-mpich-ohpc    (mpich variant)
├── fftw-gnu15-mvapich2-ohpc (mvapich2 variant)
├── fftw-gnu15-impi-ohpc     (impi variant)
└── ...                      (195+ packages)
```

Each OBS package contains:
- `debian/control` — package metadata and dependencies
- `debian/rules` — build recipe
- `debian/changelog` — version history
- `debian/modulefile` — Lmod module (if applicable)
- Source tarballs (downloaded during build or pre-cached)

## Build Configuration

### Key OBS project settings:

1. **Repository**: Ubuntu_24.04 with x86_64 architecture
2. **Build flags**: dpkg hardening disabled (OHPC_setup_compiler sets own flags)
3. **Build order**: OBS resolves automatically from Build-Depends
4. **Module loading**: `ohpc-buildroot` pulls in `lmod-ohpc`; `build-comp.sh` and
   `build-mpi.sh` handle module environment setup during builds

### Special handling for Intel MPI:

Packages built with Intel MPI need the Intel oneAPI MPI installed in the
build worker. Options:
1. Use a custom OBS worker image with Intel oneAPI pre-installed
2. Add Intel oneAPI repo as a download-on-demand source
3. Build Intel MPI packages on a dedicated worker

The `build-mpi.sh` helper sources `/opt/intel/oneapi/mpi/latest/env/vars.sh`
automatically when `MPI_FAMILY=impi`.

## MPI Variant Builds

Each MPI-dependent package has multiple debian/ directories:
- `debian/` — openmpi5 (default)
- `debian-mpich/` — mpich
- `debian-mvapich2/` — mvapich2
- `debian-impi/` — Intel MPI

In OBS, each variant is a separate package:
- `fftw-gnu15-openmpi5-ohpc` uses `debian/`
- `fftw-gnu15-mpich-ohpc` uses `debian-mpich/`
- etc.

## Repository Publishing

OBS automatically publishes built packages to an APT repository.
Configure the publish path in the project meta:

```xml
<repository name="Ubuntu_24.04">
  <path project="Ubuntu:24.04" repository="universe"/>
  <arch>x86_64</arch>
</repository>
```

Users add the repo:
```bash
curl -fsSL https://repos.versatushpc.com.br/openhpc/versatushpc-4/versatushpc.gpg \
  | sudo tee /usr/share/keyrings/versatushpc.gpg >/dev/null
curl -fsSL https://repos.versatushpc.com.br/openhpc/versatushpc-4/Ubuntu_24.04/versatushpc-openhpc.list \
  | sudo tee /etc/apt/sources.list.d/versatushpc-openhpc.list >/dev/null
sudo apt update
```

## Monitoring

- Web UI: http://localhost:3000
- Build status: http://localhost:3000/project/show/VersatusHPC:OHPC:4
- API: `osc results VersatusHPC:OHPC:4`

## Production Migration

For production:
1. Deploy OBS on dedicated hardware or VM
2. Enable GPG signing (set `$sign` in BSConfig.pm)
3. Configure SSL for the API
4. Set up proper user authentication
5. Add download-on-demand for Ubuntu mirror
6. Configure webhook for GitHub integration
