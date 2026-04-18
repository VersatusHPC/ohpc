# Ubuntu 24.04 Release Candidate

This file records the tested release-candidate line for the VersatusHPC
OpenHPC 4.x Ubuntu 24.04 port. It complements the operational validation
runbook in `docs/ubuntu-port/VALIDATION.md`.

## RC1

- Tag: `versatushpc-4.0.0-ubuntu24.04-rc1`
- Date: 2026-04-18
- Target: Ubuntu 24.04 LTS, x86_64
- OBS project: `VersatusHPC:OHPC:4`
- OBS repository: `Ubuntu_24.04`
- Build result: 296/296 packages succeeded
- Public repository: `https://repos.versatushpc.com.br/openhpc/versatushpc-4/Ubuntu_24.04/`

## RC2

- Tag: `versatushpc-4.0.0-ubuntu24.04-rc2`
- Date: 2026-04-18
- Target: Ubuntu 24.04 LTS, x86_64
- OBS project: `VersatusHPC:OHPC:4`
- OBS repository: `Ubuntu_24.04`
- Build result: 296/296 packages succeeded
- Public repository: `https://repos.versatushpc.com.br/openhpc/versatushpc-4/Ubuntu_24.04/`
- Delta from RC1: package-owned Ubuntu setup fixes for `ohpc-release`,
  `munge-ohpc`, `slurm-ohpc`, `warewulf-ohpc`, and `docs-ohpc`; public
  mirror republished with 341 Debian artifacts.
- Runtime validation: upgraded an existing Ubuntu Warewulf/Slurm SMS and
  rebuilt/rebooted the `c1` compute image from the public mirror, then ran
  `scripts/validate-ubuntu-runtime.sh --with-intel` successfully.

## RC3

- Tag: `versatushpc-4.0.0-ubuntu24.04-rc3`
- Date: 2026-04-18
- Target: Ubuntu 24.04 LTS, x86_64
- OBS project: `VersatusHPC:OHPC:4`
- OBS repository: `Ubuntu_24.04`
- Build result: 296/296 packages succeeded
- Public repository: `https://repos.versatushpc.com.br/openhpc/versatushpc-4/Ubuntu_24.04/`
- Delta from RC2: `cuda-repo-ohpc` now installs NVIDIA CUDA and HPC SDK
  APT source files and scoped keyrings; the Ubuntu GPU recipe uses
  `cuda-drivers`; the public mirror includes `make_repo.sh`, a local mirror
  tarball, and `Packages.xz`/`Sources.xz` indexes.
- Validation: `cuda-devel-ohpc` built in a clean Ubuntu 24.04 container;
  installing `cuda-repo-ohpc` exposed `nvhpc-25-9` and `cuda-drivers` from
  NVIDIA APT repositories; public `InRelease` signature and `Packages.xz`
  checksum were verified after publication.

## RC4

- Tag: `versatushpc-4.0.0-ubuntu24.04-rc4`
- Date: 2026-04-18
- Target: Ubuntu 24.04 LTS, x86_64
- OBS project: `VersatusHPC:OHPC:4`
- OBS repository: `Ubuntu_24.04`
- Build result: 296/296 packages succeeded
- Public repository: `https://repos.versatushpc.com.br/openhpc/versatushpc-4/Ubuntu_24.04/`
- Delta from RC3: the public mirror publisher no longer advertises gzip APT
  indexes in `Release`, avoiding stale CDN `Packages.gz` cache hits after a
  repository refresh. The mirror still publishes uncompressed and xz indexes.
- Validation: a fresh Ubuntu 24.04 container enabled the public HTTPS APT
  repository and resolved the current `cuda-repo-ohpc`,
  `cuda-devel-ohpc`, and `docs-ohpc` package candidates from the live mirror.

## RC5

- Tag: `versatushpc-4.0.0-ubuntu24.04-rc5`
- Date: 2026-04-18
- Target: Ubuntu 24.04 LTS, x86_64
- OBS project: `VersatusHPC:OHPC:4`
- OBS repository: `Ubuntu_24.04`
- Build result: 296/296 packages succeeded
- Public repository: `https://repos.versatushpc.com.br/openhpc/versatushpc-4/Ubuntu_24.04/`
- Delta from RC4: CI now runs on `versatushpc/4.x` using VersatusHPC-owned
  GHCR container images; the public mirror keeps Ubuntu-specific local mirror
  artifacts under `Ubuntu_24.04/`; `docs-ohpc` was rebuilt as
  `4.0.0-1ohpc6~noble` with the corrected local mirror URL in the Ubuntu PDF.
- Validation: GitHub Actions Lint, Validate, Build Container, and downstream
  analysis passed on the RC5 commit; OBS rebuilt and published `docs-ohpc`;
  the public mirror exposes `docs-ohpc` `4.0.0-1ohpc6~noble`, returns 404 for
  root-level Ubuntu `make_repo.sh` and `dist/`, and returns 200 for the
  `Ubuntu_24.04/` copies.

## Runtime Gate Passed

The public repository was validated on an Ubuntu 24.04 Warewulf/Slurm SMS and
one diskless Ubuntu 24.04 compute node. The gate covered:

- signed APT repository enablement and package candidates;
- core package upgrade on the SMS and compute image;
- Warewulf compute boot and Slurm idle state;
- MUNGE, PMIx, HWLOC, and shared `/opt` runtime checks;
- OpenHPC compute Yama policy, `kernel.yama.ptrace_scope=0`;
- GNU15 with OpenMPI5, MPICH, MVAPICH2, and Intel MPI;
- Intel compiler with Intel MPI, OpenMPI5, MPICH, and MVAPICH2;
- MPI hello-world and IMB `PingPong` for each validated compiler/MPI pair.

## Known Limits

- Ubuntu support is currently validated for x86_64.
- The fast gate is intentionally sparse; it does not exhaustively run every
  scientific library test in the OpenHPC package matrix.
- Intel oneAPI packages depend on Intel's upstream APT repository through the
  `intel-oneapi-toolkit-release-ohpc` compatibility package.
- The OBS backend IP-access behavior discovered during the port is an OBS
  deployment issue; track it separately with upstream OBS.
