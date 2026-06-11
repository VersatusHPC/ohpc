# OpenHPC 4.x POWER Porting Notes

This note summarizes the ppc64le RPM work carried by the POWER port branch.
It is intended as a starting point for upstream discussion and review, not as a
release-channel report.

## Scope

The initial upstreamable scope is the little-endian POWER RPM target:

- EL10 on `ppc64le`.
- openEuler 24.03 LTS on `ppc64le`.
- GNU15 with OpenMPI, MPICH, and MVAPICH2 where those package variants are
  available on POWER.

The branch intentionally excludes release repository metadata, Ubuntu/Debian
`ppc64el` packaging, and package families that are inherently locked to another
architecture.

## Architecture-Locked Exclusions

These package families should not be advertised through POWER meta packages:

| Package family | Reason |
| --- | --- |
| Intel compilers | Intel proprietary toolchain is x86_64 only |
| Intel MPI | Intel MPI is x86_64 only |
| CUDA | NVIDIA CUDA packages in this tree are x86_64 only |
| ARM compiler family | Targets aarch64 |
| GEOPM | Depends on x86 RAPL/MSR interfaces |
| MSR-safe | Depends on x86 MSR registers |
| Lustre client | Kernel-module packaging needs a separate enablement path |

## Core Source Changes

The ppc64le source changes are mostly RPM spec and build-flag changes:

| Area | Change |
| --- | --- |
| `OHPC_setup_compiler` | Adds ppc64le compiler flags and avoids `-mtune=generic`, which GCC rejects on ppc64le |
| `openblas.spec` | Uses `TARGET=POWER9` for ppc64le |
| `fftw.spec` | Enables VSX on ppc64le |
| `boost.spec` | Sets Boost.Build architecture to `power` on ppc64le |
| `likwid.spec` | Uses LIKWID `GCCPOWER` with `perf_event` access and a POWER event-parser backport |
| `pdtoolkit.spec` | Creates the expected `ibm64linux/bin` layout before configure |
| `python-numpy.spec` | Applies the upstream NumPy VSX3 fix in `%prep` for a POWER9 baseline |
| `mpich.spec` | Adds the missing hwloc build, runtime, and module dependency |
| `ucx.spec` | Uses the real 1.20.0 release URL and disables unshipped Go bindings so native images with Go installed do not change the RPM build surface |
| `meta-packages.spec` | Removes unsupported architecture-locked dependencies from POWER meta packages |
| `gotcha.spec` | Skips the ppc64le-only failing unit test and avoids Sphinx where openEuler lacks it |

## Built RPM Surface

The POWER port exercised the architecture-portable OpenHPC stack on native
POWER builders before this upstream extraction. For upstream review, the branch
now carries a repository-neutral validation path that can reproduce the relevant
RPM build and runtime checks without OBS or site-specific repository URLs:

```bash
tests/ci/validate-ppc64le-port.sh --base-ref origin/4.x
```

That command must run on a native `ppc64le` host. It builds the POWER
validation container, runs branch-relative static checks, builds a bootstrap
package set plus the changed specs through `tests/ci/run_build.py`, creates a
local RPM repository from the resulting RPMs, installs the locally built
runtime set, and runs compiler/MPI/library smoke tests.

The expected evidence for upstream review is:

| Target | Result |
| --- | --- |
| EL10 ppc64le | Architecture-portable RPM stack built and installed |
| openEuler 24.03 ppc64le | Same source specs built after rebuilding missing openEuler OS support packages |
| GNU15 plus OpenMPI | C and Fortran MPI smoke tests passed on POWER |
| GNU15 plus MPICH | C and Fortran MPI smoke tests passed on POWER |
| GNU15 plus MVAPICH2 | C and Fortran MPI smoke tests passed on POWER |
| LIKWID | `likwid-topology` and `likwid-perfctr` start on POWER with `perf_event` |

The branch does not claim that every support rebuild belongs upstream.
openEuler 24.03 ppc64le has a thin OS repository; some missing OS `-devel`
packages must be rebuilt in the native builder image so OpenHPC specs can be
tested.

## Native Builder Images

The companion files under `tests/ci/` describe native ppc64le build
environments:

- `tests/ci/Containerfile.ohpc-validate-almalinux-ppc64le`
- `tests/ci/Containerfile.ohpc-validate-openeuler-ppc64le`

They are intentionally repository-neutral. They install OS build dependencies
and preserve the native POWER constraints without relying on site-specific
package repositories.

The openEuler validation image does not use `openeuler/openeuler` as a base
image because that image does not provide a ppc64le variant for 24.03 LTS. It
bootstraps an openEuler ppc64le root filesystem from the official 24.03 LTS
`OS/ppc64le` RPM repository instead.

## Deferred Follow-Ups

The following work should be reviewed separately:

- LLVM compiler-family restoration. Upstream `4.x` no longer carries the
  `llvm-compilers` spec, so this branch does not reintroduce it.
- Broad package-version and EL10/openEuler maintenance fixes that are not
  specifically POWER-scoped.
- Release repository checks and mirror cleanup.
- Ubuntu 24.04 `ppc64el` Debian packaging.
