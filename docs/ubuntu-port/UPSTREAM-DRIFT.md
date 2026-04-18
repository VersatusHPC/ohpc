# Ubuntu Port Upstream Delta Log

This file records intentional differences from upstream OpenHPC behavior or
packaging that matter for maintenance. It is not a list of every Debian control
file; it is the why/when trail for choices that future rebases should review.

## Active Deltas

| Date | Area | Delta | Why | Revisit when |
|------|------|-------|-----|--------------|
| 2026-04-17 | Compute node sysctl | `ohpc-base-compute` installs `/usr/lib/sysctl.d/90-ohpc-yama-scope.conf` with `kernel.yama.ptrace_scope = 0`. | Ubuntu 24.04 defaults to `ptrace_scope=1`, which blocks MVAPICH2 CMA (`process_vm_readv: Operation not permitted`). EL10 and openEuler 24.03 both ship `elfutils-default-yama-scope` with `ptrace_scope=0`, so this preserves OpenHPC runtime parity for MPI, profilers, and debuggers. | Upstream OpenHPC gains Debian/Ubuntu packaging, Ubuntu changes its default, or a safer upstream MVAPICH2 runtime fallback exists. |
| 2026-04-17 | MVAPICH2 modulefiles | Do not set `MV2_SMP_USE_CMA=0` in the Ubuntu modulefiles. | CMA should remain available on compute nodes, matching EL/openEuler behavior. The system-level Yama policy is the correct compatibility layer. | If a supported Ubuntu target cannot allow `ptrace_scope=0` on compute nodes. |
| 2026-04-17 | Warewulf Debian package | Debian package owns Ubuntu-specific service/default integration: dnsmasq-backed DHCP/TFTP defaults, package-owned `/srv/tftpboot`, Ubuntu iPXE source path, dnsmasq DNS disablement for systemd-resolved coexistence, and private overlay modes after `dh_fixperms`. | Upstream RPM packaging assumes EL service defaults and RPM file-mode preservation. These are Debian/Ubuntu packaging responsibilities, not manual install steps. | Upstream Warewulf/OpenHPC adds first-class Debian packaging, or Ubuntu changes service/package paths. |
| 2026-04-17 | Slurm Debian package split | Ubuntu packages split Slurm daemons, plugins, PAM, examples, and shared files into Debian packages. `slurm-ohpc` maintainer scripts create the `slurm` service account and state/log paths, mirroring upstream RPM `%pre/%post` behavior. | Debian packaging must express runtime paths, service users, and package relationships without RPM subpackage semantics. | Upstream OpenHPC provides native Debian Slurm packaging. |
| 2026-04-18 | MUNGE Debian package | `munge-ohpc` maintainer scripts create the `munge` service account, generate `/etc/munge/munge.key` when absent, and own `/etc/munge`, `/var/lib/munge`, `/var/log/munge`, and `/run/munge` modes. | These were previously manual guide steps but are package responsibilities and match upstream RPM scriptlet behavior. | Upstream OpenHPC provides native Debian MUNGE packaging. |
| 2026-04-18 | Release package | `ohpc-release` installs the VersatusHPC APT source list and dearmored repository key. | This restores release-package parity with the upstream RPM flow where installing `ohpc-release` enables repository metadata. | Upstream OpenHPC publishes an official Debian/Ubuntu release package. |
| 2026-04-17 | OBS backend access control | Local OBS rootful podman deployment allows podman bridge gateway addresses in `BSConfig.pm` `ipaccess`. | Rootful podman NATs backend upload requests through bridge gateway addresses, while stock config only allowed loopback/host IPs in this deployment. This is infrastructure drift, not package behavior. | OBS is deployed without podman NAT, or upstream OBS offers a documented container-network allowlist pattern. |

## Review Rule

When rebasing onto a new OpenHPC GA release, review every active delta above.
Remove a delta when upstream provides equivalent behavior, or keep it with an
updated note explaining why Ubuntu still needs it.
