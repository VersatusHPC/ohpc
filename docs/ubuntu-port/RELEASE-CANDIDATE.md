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
