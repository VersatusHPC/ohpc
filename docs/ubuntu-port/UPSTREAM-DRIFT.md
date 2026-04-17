# Ubuntu Port Upstream Delta Log

This file records intentional differences from upstream OpenHPC behavior or
packaging that matter for maintenance. It is not a list of every Debian control
file; it is the why/when trail for choices that future rebases should review.

## Active Deltas

| Date | Area | Delta | Why | Revisit when |
|------|------|-------|-----|--------------|
| 2026-04-17 | Compute node sysctl | `ohpc-base-compute` installs `/usr/lib/sysctl.d/90-ohpc-yama-scope.conf` with `kernel.yama.ptrace_scope = 0`. | Ubuntu 24.04 defaults to `ptrace_scope=1`, which blocks MVAPICH2 CMA (`process_vm_readv: Operation not permitted`). EL10 and openEuler 24.03 both ship `elfutils-default-yama-scope` with `ptrace_scope=0`, so this preserves OpenHPC runtime parity for MPI, profilers, and debuggers. | Upstream OpenHPC gains Debian/Ubuntu packaging, Ubuntu changes its default, or a safer upstream MVAPICH2 runtime fallback exists. |
| 2026-04-17 | MVAPICH2 modulefiles | Do not set `MV2_SMP_USE_CMA=0` in the Ubuntu modulefiles. | CMA should remain available on compute nodes, matching EL/openEuler behavior. The system-level Yama policy is the correct compatibility layer. | If a supported Ubuntu target cannot allow `ptrace_scope=0` on compute nodes. |
| 2026-04-17 | Warewulf Debian package | Debian package owns Ubuntu-specific systemd/service and overlay permissions needed by Warewulf on Ubuntu. | Upstream RPM packaging assumes EL-style service paths, permissions, and RPM scriptlets. | Upstream Warewulf/OpenHPC adds first-class Debian packaging. |
| 2026-04-17 | Slurm Debian package split | Ubuntu packages split Slurm daemons, plugins, PAM, examples, and shared files into Debian packages. | Debian packaging must express runtime paths and package relationships without RPM subpackage semantics. | Upstream OpenHPC provides native Debian Slurm packaging. |
| 2026-04-17 | OBS backend access control | Local OBS rootful podman deployment allows podman bridge gateway addresses in `BSConfig.pm` `ipaccess`. | Rootful podman NATs backend upload requests through bridge gateway addresses, while stock config only allowed loopback/host IPs in this deployment. This is infrastructure drift, not package behavior. | OBS is deployed without podman NAT, or upstream OBS offers a documented container-network allowlist pattern. |

## Review Rule

When rebasing onto a new OpenHPC GA release, review every active delta above.
Remove a delta when upstream provides equivalent behavior, or keep it with an
updated note explaining why Ubuntu still needs it.
