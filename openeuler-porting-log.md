# OpenHPC openEuler 24.03 ppc64le Porting Log

## Prototype Status: FEASIBLE but COMPLEX

### What Works
- openEuler 24.03 LTS has ppc64le ISOs and an OS package repo (~2362 packages)
- Container bootstrapped via `dnf --installroot` from Huawei mirror
- **ohpc-filesystem** + **ohpc-buildroot**: builds and installs cleanly
- **lmod**: builds after rebuilding `lua-devel` + `lua-filesystem` from SRPMs
- Podman-based build workflow validated

### Key Challenge: Incomplete ppc64le Package Repo

openEuler 24.03 ppc64le only ships the `OS` repo. The `everything` repo
(which contains -devel packages) **does not exist for ppc64le**.

| Repo | x86_64 | aarch64 | ppc64le |
|------|--------|---------|---------|
| OS | ~2540 pkgs | ~2500 pkgs | ~2362 pkgs |
| everything | ~30k pkgs | ~30k pkgs | **NOT AVAILABLE** |

This means many BuildRequires packages (lua-devel, curl-devel, jsoncpp-devel,
openssl-devel, etc.) must be **rebuilt from SRPMs** before OpenHPC packages
can be built. Each missing -devel package adds a step to the build chain.

### Workaround: SRPM Rebuild Pipeline

For each missing -devel package:
1. Download SRPM from `source/Packages/` on the openEuler mirror
2. `rpmbuild --rebuild --nodeps <package>.src.rpm`
3. Install the resulting -devel RPM

This is tedious but works. The SRPMs exist and compile on ppc64le.

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

Estimated additional effort vs EL10 port: 1-2 days for the -devel bootstrapping,
then the same build process.

### Mirror

- Huawei mirror (fast): `https://mirrors.huaweicloud.com/openeuler/openEuler-24.03-LTS/`
- Official (slow from outside China): `https://repo.openeuler.org/openEuler-24.03-LTS/`
