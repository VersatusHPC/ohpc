# OpenHPC Ubuntu Port — RPM to Debian Dependency Mapping Reference

This document maps RPM package names used in OpenHPC spec files to their Ubuntu 24.04
equivalents. Used when writing `debian/control` Build-Depends.

---

## Build Tools

| RPM (BuildRequires) | Ubuntu (Build-Depends) |
|---------------------|------------------------|
| gcc | gcc |
| gcc-c++ | g++ |
| gcc-gfortran | gfortran |
| make | make |
| cmake | cmake |
| autoconf | autoconf |
| automake | automake |
| libtool | libtool |
| libtool-ltdl | libltdl-dev |
| pkgconfig / pkg-config | pkg-config |
| bison | bison |
| flex | flex |
| m4 | m4 |
| patch | patch |
| texinfo | texinfo |
| gettext | gettext |
| gettext-devel | gettext |
| fakeroot | fakeroot |

---

## Core Development Libraries

| RPM (BuildRequires) | Ubuntu (Build-Depends) |
|---------------------|------------------------|
| glibc-devel | libc6-dev |
| binutils-devel | binutils-dev |
| zlib-devel | zlib1g-dev |
| bzip2-devel | libbz2-dev |
| xz-devel | liblzma-dev |
| libxml2-devel | libxml2-dev |
| libffi-devel | libffi-dev |
| expat-devel | libexpat1-dev |
| sqlite-devel | libsqlite3-dev |

---

## Networking and Security

| RPM (BuildRequires) | Ubuntu (Build-Depends) |
|---------------------|------------------------|
| openssl-devel | libssl-dev |
| libcurl-devel | libcurl4-openssl-dev |
| pam-devel | libpam0g-dev |
| libssh2-devel | libssh2-1-dev |

---

## RDMA / InfiniBand / Fabric

| RPM (BuildRequires) | Ubuntu (Build-Depends) |
|---------------------|------------------------|
| libibverbs-devel | libibverbs-dev |
| librdmacm-devel | librdmacm-dev |
| libibumad-devel | libibumad-dev |
| libfabric-devel | libfabric-dev |
| rdma-core-devel | rdma-core / rdma-core-dev |

---

## Hardware / System

| RPM (BuildRequires) | Ubuntu (Build-Depends) |
|---------------------|------------------------|
| numactl-devel | libnuma-dev |
| hwloc-devel | libhwloc-dev (system) or hwloc-ohpc |
| pciutils-devel | libpci-dev |
| libsysfs-devel | libsysfs-dev |
| systemd-devel | libsystemd-dev |
| udev | udev |

---

## Scripting / Languages

| RPM (BuildRequires) | Ubuntu (Build-Depends) |
|---------------------|------------------------|
| lua-devel | liblua5.4-dev |
| lua-filesystem | lua-filesystem |
| lua-posix | lua-posix |
| tcl-devel | tcl-dev |
| python3-devel | python3-dev |
| python3-setuptools | python3-setuptools |
| python3-Cython | cython3 |
| python3-numpy | python3-numpy |
| perl | perl |
| perl-devel | libperl-dev |
| perl-ExtUtils-MakeMaker | perl (included) |
| swig | swig |

---

## Terminal / UI

| RPM (BuildRequires) | Ubuntu (Build-Depends) |
|---------------------|------------------------|
| ncurses-devel | libncurses-dev |
| readline-devel | libreadline-dev |
| cairo-devel | libcairo2-dev |
| libX11-devel | libx11-dev |
| gtk2-devel | libgtk2.0-dev |

---

## Database

| RPM (BuildRequires) | Ubuntu (Build-Depends) |
|---------------------|------------------------|
| mariadb-devel | libmariadb-dev |
| mysql-devel | libmysqlclient-dev |

---

## Math / Science Libraries (system)

| RPM (BuildRequires) | Ubuntu (Build-Depends) |
|---------------------|------------------------|
| libgfortran | libgfortran-13-dev (or matching gcc) |
| lapack-devel | liblapack-dev |
| blas-devel | libblas-dev |

---

## Event / Threading

| RPM (BuildRequires) | Ubuntu (Build-Depends) |
|---------------------|------------------------|
| libevent-devel | libevent-dev |
| libatomic | libatomic1 |

---

## OHPC Internal Dependencies

These keep the same names (installed from the local OHPC APT repo):

| OHPC Package | Notes |
|--------------|-------|
| ohpc-filesystem | Directory structure |
| ohpc-buildroot | Build setup scripts |
| lmod-ohpc | Module system |
| hwloc-ohpc | Hardware locality |
| ucx-ohpc | UCX communication |
| pmix-ohpc | Process management |
| munge-ohpc | Authentication |
| munge-devel-ohpc | Munge headers |
| slurm-ohpc | Workload manager |
| slurm-devel-ohpc | Slurm headers |
| gnu15-compilers-ohpc | GCC 15 compiler |
| openmpi5-gnu15-ohpc | OpenMPI 5 |
| mpich-gnu15-ohpc | MPICH |
| openblas-gnu15-ohpc | OpenBLAS |

---

## System Tools

| RPM | Ubuntu |
|-----|--------|
| procps-ng | procps |
| ipmitool | ipmitool |
| emacs-nox | emacs-nox |
| NetworkManager | network-manager |
| man-db | man-db |
| which | which (or debianutils) |
| hostname | hostname |

---

## Not Available / Skip

| RPM | Notes |
|-----|-------|
| fdupes | Not in Ubuntu repos; skip or use alternative |
| rpm-build | Not needed for Debian packaging |
| dnf-utils | Not applicable |
| epel-release | Not applicable |
| redhat-release | Not applicable |

---

## Notes

- Ubuntu uses `-dev` suffix instead of RPM's `-devel` suffix
- Ubuntu splits libraries into `lib{name}{soversion}` (runtime) and `lib{name}-dev` (headers)
- When in doubt, use `apt-cache search` in the Ubuntu container to find the correct package
- This mapping covers Ubuntu 24.04 (noble); some names may change in 26.04
