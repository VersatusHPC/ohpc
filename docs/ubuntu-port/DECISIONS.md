# OpenHPC Ubuntu Port — Architecture Decisions

This document records key design decisions for the Ubuntu port. Each decision includes
context, the choice made, and rationale.

---

## ADR-001: Native Debian Packaging over Spec-to-Deb Conversion

**Date:** 2026-03-27

**Context:** OpenHPC has ~92 RPM spec files. We need .deb packages for Ubuntu. Two approaches
exist: (A) convert spec files to debs automatically using tools like alien or a custom
converter, or (B) create native `debian/` directories for each package.

**Decision:** Native Debian packaging with `debian/` directories coexisting alongside `SPECS/`.

**Rationale:** Long-term maintainability. Spec-to-deb converters produce fragile output that
breaks on non-trivial packages. Native packaging gives full control over dependencies, install
paths, and Ubuntu-specific behavior. The upfront cost is higher but the ongoing maintenance
cost is much lower.

---

## ADR-002: Podman Containers for Build/Test Environment

**Date:** 2026-03-27

**Context:** The host is RHEL 10.1. We need Ubuntu 24.04 for building and testing .deb
packages. Options: (A) libvirt/KVM VMs, (B) podman containers.

**Decision:** Podman containers as the primary build/test environment.

**Rationale:** Faster iteration (seconds vs minutes to spin up). The existing upstream CI
already uses containers. sbuild supports unshare mode for rootless builds. /opt/ohpc is a
self-contained prefix that works fine in containers. libvirt is available as fallback for
integration testing if needed (e.g., systemd service testing).

---

## ADR-003: /opt/ohpc Path Preservation

**Date:** 2026-03-27

**Context:** All OpenHPC packages install under `/opt/ohpc/`. Debian policy prefers `/usr/`.
The Lmod module system, compiler/MPI setup scripts, and all modulefiles depend on the
`/opt/ohpc` hierarchy.

**Decision:** Preserve `/opt/ohpc` paths exactly as they are in the RPM packages.

**Rationale:** Changing paths would require rewriting every modulefile, every setup script,
and every package's configure flags. The /opt/ directory is explicitly designated by FHS for
"add-on application software packages", which is exactly what OHPC is. We override
`dh_usrlocal` and suppress lintian warnings for `/opt/` paths.

---

## ADR-004: Package Naming Convention

**Date:** 2026-03-27

**Context:** RPM packages use names like `openblas-gnu15-ohpc`. Debian has stricter naming
conventions (lowercase, hyphens).

**Decision:** Preserve the existing naming convention. Names like `openblas-gnu15-ohpc` and
`fftw-gnu15-openmpi5-ohpc` are valid Debian package names (all lowercase with hyphens).

**Rationale:** Consistency with RPM names makes documentation, scripts, and user expectations
portable across distros. The `-ohpc` suffix clearly identifies OpenHPC packages.

---

## ADR-005: OHPC_vars.mk as Central Include (Replaces OHPC_macros)

**Date:** 2026-03-27

**Context:** RPM uses `OHPC_macros` (254 lines of RPM macro definitions) included by every
spec file. Debian has no equivalent macro language in `debian/rules`.

**Decision:** Create `OHPC_vars.mk` (makefile include) and `OHPC_vars.sh` (shell-sourceable).
Every `debian/rules` includes `OHPC_vars.mk`. Build scripts source `OHPC_vars.sh`.

**Rationale:** `debian/rules` is a Makefile, so a makefile include is the natural equivalent.
The shell version covers scripts that aren't Makefiles. This keeps all path definitions and
defaults in one place, mirroring the RPM approach.

---

## ADR-006: reprepro for Local APT Repository

**Date:** 2026-03-27

**Context:** Need a local APT repository to host built packages during development and for
the build dependency chain. Options: (A) reprepro, (B) aptly, (C) OBS.

**Decision:** reprepro for local development, with OBS as the production target.

**Rationale:** reprepro is simple, requires no daemon, and is sufficient for development
builds of a single distribution. OBS handles multi-arch and multi-distro production builds
and is what upstream already uses.

---

## ADR-007: Target Ubuntu 24.04 LTS (noble) First

**Date:** 2026-03-27

**Context:** Ubuntu 26.04 LTS is upcoming but not yet released. Ubuntu 24.04 LTS is the
current stable release.

**Decision:** Build and test on Ubuntu 24.04 (noble). Use versioning convention
(`~noble` suffix) that allows clean upgrades to 26.04 when it releases.

**Rationale:** We need a working system to develop against now. The `~noble` version suffix
sorts lower than `~plucky` (26.04), enabling seamless upgrades. Most build dependencies and
library versions will be similar between 24.04 and 26.04.

---

## ADR-008: Single Source Package with Parameterized Builds

**Date:** 2026-03-27

**Context:** Compiler-dependent packages (e.g., openblas) need to be built once per compiler
family (gnu15, gnu14, etc.). MPI-dependent packages need builds per compiler+MPI combination.

**Decision:** Single `debian/` source directory per component. The build script
(`misc/build_deb.sh`) passes `COMPILER_FAMILY` and `MPI_FAMILY` as environment variables.
`debian/control.in` is templated to produce the correct package name at build time.

**Rationale:** Avoids duplicating `debian/` directories for each variant. Mirrors how the RPM
build system works (single spec, built with different `--define` flags). The templating step
is a simple `sed` substitution.
