# Ubuntu 24.04 Port Validation Runbook

This runbook defines the fast acceptance checks for the OpenHPC 4.x Ubuntu
24.04 port. It is intentionally smaller than full package validation: use it
before publishing a new repository snapshot, after fixing provisioning/runtime
packages, and after major OBS reimports.

## Scope

- Target project: `VersatusHPC:OHPC:4`
- Repository: `Ubuntu_24.04`
- Architecture: `x86_64`
- Provisioner path: Warewulf
- Scheduler path: Slurm
- Primary MPI launch path: Slurm `srun`

The checks below do not prove every scientific library is correct. They prove
that the repository can deploy a usable Ubuntu head/compute node pair and run
the key OpenHPC workflows that most downstream packages depend on.

## Sparse Runtime Coverage Line

For the Ubuntu port, the minimum post-publication runtime line is:

1. Public APT repository installs signed metadata and package candidates.
2. Warewulf boots one Ubuntu 24.04 compute image.
3. Slurm, MUNGE, PMIx, HWLOC, and `/opt` sharing work on the compute node.
4. Compute nodes apply the OpenHPC Yama policy, `kernel.yama.ptrace_scope=0`.
5. GNU15 compiles and runs an MPI hello program through Slurm for OpenMPI, MPICH, and MVAPICH2.
6. IMB `PingPong` runs through Slurm for the same three GNU15 MPI stacks.

This is the fast release gate. Broader library tests can expand from this line,
but a repository snapshot should not be treated as usable if any item here
fails.

## Release Gate

Do not publish a new public repository snapshot until these gates pass:

1. OBS status is fully green for `Ubuntu_24.04/x86_64`.
2. Critical packages install or upgrade from a staging repository.
3. Warewulf boots a diskless Ubuntu compute node.
4. Slurm sees the compute node as `idle`.
5. MUNGE works from a job running on the compute node.
6. PMIx and hwloc are visible to system daemons through `ldconfig`.
7. Compute nodes report `kernel.yama.ptrace_scope = 0`.
8. OpenMPI runs through Slurm/PMIx.
9. MPICH runs through Slurm/PMI2.
10. MVAPICH2 runs through Slurm/PMI2 with CMA available.
11. At least one MPI-dependent package runs through all three GNU15 MPI stacks.
12. On x86_64 release candidates, Intel oneAPI compatibility packages install,
    `intel`/`impi` modules load, and an Intel+IMPI hello program runs through
    Slurm.

## Automated Runtime Gate

The manual commands below remain useful for debugging, but the normal fast gate
is scripted in `scripts/validate-ubuntu-runtime.sh`. Run it from a repository
checkout by copying the script to the SMS/head node, then executing it there. Do
not run this script through SSH stdin; package-manager commands may consume
stdin.

```bash
scp scripts/validate-ubuntu-runtime.sh <sms-host>:/tmp/
ssh <sms-host> 'chmod +x /tmp/validate-ubuntu-runtime.sh && /tmp/validate-ubuntu-runtime.sh --skip-intel'
```

This default mode checks public APT candidates, Slurm, Warewulf compute-node
state, MUNGE, PMIx/HWLOC linker visibility, GNU15 OpenMPI, GNU15 MPICH, GNU15
MVAPICH2 with CMA, and IMB `PingPong` for the same three MPI stacks.

For the x86_64 Intel gate, install the Intel validation packages and run the
Intel module/compiler/IMPI smoke test:

```bash
scp scripts/validate-ubuntu-runtime.sh <sms-host>:/tmp/
ssh <sms-host> 'chmod +x /tmp/validate-ubuntu-runtime.sh && /tmp/validate-ubuntu-runtime.sh --install-intel'
```

Use `--with-intel` instead of `--install-intel` when the Intel packages are
already installed and Intel validation should be mandatory. Use `--upgrade-core`
when validating a repository upgrade path on an existing SMS.

## OBS Status Check

Run from the OBS host:

```bash
curl -fsS \
  'http://localhost:5352/build/VersatusHPC:OHPC:4/_result?repository=Ubuntu_24.04&arch=x86_64&view=status' \
  | python3 -c '
import sys
import xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
counts = {}
bad = []
for status in root.iter("status"):
    package = status.attrib["package"]
    code = status.attrib["code"]
    counts[code] = counts.get(code, 0) + 1
    if code != "succeeded":
        details = (status.findtext("details") or "").strip()
        bad.append((code, package, details))
print(counts)
for code, package, details in bad:
    print(f"{code:12} {package} {details}")
'
```

Expected result before publishing:

```text
{'succeeded': 296}
```

Any `failed`, `unresolvable`, `broken`, `blocked`, `scheduled`, or `building`
state means the repository is not ready for final publication. Scheduled and
building states can be normal immediately after a reimport; wait for the
cascade to settle before making a release decision.

## Staging Repository Upgrade Check

Before publishing to `repos.versatushpc.com.br`, publish OBS output to a
staging repository and point the validation VM at that staging URL.

On the head node:

```bash
sudo apt update
apt-cache policy warewulf-ohpc slurm-ohpc slurm-slurmd-ohpc \
  pmix-ohpc hwloc-ohpc ohpc-base-compute ohpc-release
sudo apt-get -y install --only-upgrade \
  warewulf-ohpc slurm-ohpc slurm-slurmctld-ohpc slurm-slurmd-ohpc \
  pmix-ohpc hwloc-ohpc ohpc-base-compute ohpc-release
```

Inside the Warewulf image, repeat the compute-node package upgrade and rebuild
the image. Use `wwctl image exec` rather than direct `chroot` for APT commands;
Warewulf mounts `/dev`, `/proc`, `/sys`, and `/run` for the image execution
environment. A direct chroot can corrupt a minimal OCI rootfs by creating
`/dev/null` as a regular file when commands redirect to `>/dev/null` before a
real device node exists.

```bash
sudo wwctl image exec --build=false ubuntu-24.04 -- /bin/bash -ex <<'EOF'
apt-get update
apt-get -y install --only-upgrade \
  slurm-slurmd-ohpc pmix-ohpc hwloc-ohpc ohpc-base-compute openssh-server
EOF
sudo wwctl image build ubuntu-24.04
sudo wwctl overlay build
```

If APT in an image reports that it cannot write to `/dev/null`, repair the image
rootfs before retrying:

```bash
CHROOT=$(sudo wwctl image show ubuntu-24.04)
sudo rm -f "$CHROOT/dev/null"
sudo mknod -m 666 "$CHROOT/dev/null" c 1 3
```

Reboot the compute VM/node after rebuilding the image.

## Head Node Checks

```bash
hostname
uptime
dpkg -l ohpc-release warewulf-ohpc munge-ohpc slurm-ohpc \
  slurm-slurmctld-ohpc pmix-ohpc hwloc-ohpc

for svc in warewulfd dnsmasq munge slurmctld ssh; do
  printf '%s ' "$svc"
  systemctl is-active "$svc"
done

ip -br addr
sudo wwctl node list -a
sudo wwctl profile list -a
```

Expected:

- Warewulf, `dnsmasq`, MUNGE, Slurm controller, and SSH are active.
- Head node has the external/admin interface and the provisioning interface.
- Compute node is listed with the expected static provisioning IP.

## Warewulf Overlay Checks

```bash
sudo wwctl overlay list -al NetworkManager
sudo wwctl overlay list -al ssh.host_keys
```

Expected private modes:

```text
-rw-------  NetworkManager  etc/NetworkManager/system-connections/ww4-managed.ww
-rw-------  ssh.host_keys   etc/ssh/ssh_host_*_key.ww
-rw-r--r--  ssh.host_keys   etc/ssh/ssh_host_*_key.pub.ww
```

These permissions are required because Ubuntu NetworkManager and OpenSSH ignore
private system connection and host-key files when they are group/world readable.

## Slurm and Compute Node Checks

```bash
sinfo -Nel
scontrol show node c1
srun --input=none -N1 -n1 hostname
srun --input=none -N1 -n1 bash -lc '
  id
  hostname
  mount | grep -E " /opt|/opt/ohpc"
  systemctl is-active munge slurmd ssh || true
'
```

Expected:

- `c1` is `idle`.
- `srun` returns `c1`.
- `/opt` is mounted from the head node through Warewulf/NFS.
- MUNGE and `slurmd` are active on the compute node.

## MUNGE and Linker Checks

```bash
srun --input=none -N1 -n1 bash -lc \
  'munge -n | unmunge | sed -n "1,8p"'

srun --input=none -N1 -n1 bash -lc \
  'ldconfig -p | grep -E "libpmix|libhwloc"'

srun --input=none -N1 -n1 bash -lc \
  'cat /etc/ld.so.conf.d/ohpc-pmix.conf /etc/ld.so.conf.d/ohpc-hwloc.conf'
```

Expected:

- `unmunge` reports `STATUS: Success`.
- `libpmix` resolves from `/opt/ohpc/admin/pmix/lib`.
- `libhwloc` resolves from `/opt/ohpc/pub/libs/hwloc/lib`.

## MPI Smoke Test

Create a shared test program under the user's home directory, because `/tmp`
on the head node is not shared with the compute node:

```bash
mkdir -p ~/ohpc-smoke
cat > ~/ohpc-smoke/mpi-hello.c <<'EOF'
#include <mpi.h>
#include <stdio.h>
int main(int argc, char **argv) {
    int rank, size;
    char name[MPI_MAX_PROCESSOR_NAME];
    int len = 0;
    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Get_processor_name(name, &len);
    printf("hello from rank %d/%d on %s\n", rank, size, name);
    MPI_Finalize();
    return 0;
}
EOF
```

OpenMPI through Slurm/PMIx:

```bash
source /etc/profile.d/lmod.sh
module purge
module load gnu15/15.2.0 openmpi5/5.0.10
mpicc ~/ohpc-smoke/mpi-hello.c -o ~/ohpc-smoke/mpi-hello-openmpi
srun --input=none --mpi=pmix -N1 -n2 ~/ohpc-smoke/mpi-hello-openmpi | sort
```

Expected:

```text
hello from rank 0/2 on c1
hello from rank 1/2 on c1
```

MPICH through Slurm/PMI2:

```bash
source /etc/profile.d/lmod.sh
module purge
module load gnu15/15.2.0 mpich/5.0.0-ofi
mpicc ~/ohpc-smoke/mpi-hello.c -o ~/ohpc-smoke/mpi-hello-mpich
srun --input=none --mpi=pmi2 -N1 -n2 ~/ohpc-smoke/mpi-hello-mpich | sort
```

Expected:

```text
hello from rank 0/2 on c1
hello from rank 1/2 on c1
```

MVAPICH2 through Slurm/PMI2:

```bash
source /etc/profile.d/lmod.sh
module purge
module load gnu15/15.2.0 mvapich2/2.3.7
srun --input=none -N1 -n1 sysctl kernel.yama.ptrace_scope
module show mvapich2/2.3.7 2>&1 | grep -q MV2_SMP_USE_CMA && exit 1
mpicc ~/ohpc-smoke/mpi-hello.c -o ~/ohpc-smoke/mpi-hello-mvapich2
MV2_SMP_USE_CMA=1 srun --input=none --mpi=pmi2 -N1 -n2 ~/ohpc-smoke/mpi-hello-mvapich2 | sort
```

Expected:

```text
kernel.yama.ptrace_scope = 0
hello from rank 0/2 on c1
hello from rank 1/2 on c1
```

Ubuntu defaults to `kernel.yama.ptrace_scope=1`, which blocks MVAPICH2's CMA
shared-memory path in this Slurm launch setup with `process_vm_readv: Operation
not permitted`. EL10 and openEuler 24.03 ship `elfutils-default-yama-scope`,
which sets `kernel.yama.ptrace_scope=0`; Ubuntu compute nodes match that
OpenHPC runtime policy through `ohpc-base-compute`. Missing that sysctl is a
release blocker because it silently removes MVAPICH2's expected intra-node CMA
fast path.

## MPI-Dependent Package Smoke Test

IMB is a useful fast canary because it validates MPI plus at least one
MPI-dependent OpenHPC package.

```bash
source /etc/profile.d/lmod.sh

module purge
module load gnu15/15.2.0 openmpi5/5.0.10 imb/2021.10
srun --input=none --mpi=pmix -N1 -n2 IMB-MPI1 PingPong -msglog 0:3

module purge
module load gnu15/15.2.0 mpich/5.0.0-ofi imb/2021.10
srun --input=none --mpi=pmi2 -N1 -n2 IMB-MPI1 PingPong -msglog 0:3

module purge
module load gnu15/15.2.0 mvapich2/2.3.7 imb/2021.10
srun --input=none --mpi=pmi2 -N1 -n2 IMB-MPI1 PingPong -msglog 0:3
```

Expected:

- All three runs complete and enter `MPI_Finalize`.
- Non-zero latency is reported for message sizes 0 through 8 bytes.

## Expected Non-Blocker: MPICH Hydra over SSH

The default guide validates MPI launch through Slurm. It does not configure
passwordless SSH, SSH host-based authentication, or per-user SSH keys for direct
launcher access to compute nodes.

Therefore this failure is expected and is not a release blocker:

```bash
module purge
module load gnu15/15.2.0 mpich/5.0.0-ofi
mpirun -np 2 -hosts c1 ~/ohpc-smoke/mpi-hello-mpich
```

Expected failure without additional SSH configuration:

```text
ferrao@c1: Permission denied (publickey,password).
Launch proxy failed.
```

If direct Hydra-over-SSH support is desired, document it as an optional site
customization rather than as part of the default OpenHPC/Warewulf/Slurm path.

## Final Public Repository Check

After publishing to the public mirror, run a clean install or upgrade test
using only:

```text
https://repos.versatushpc.com.br/openhpc/versatushpc-4/versatushpc.gpg
https://repos.versatushpc.com.br/openhpc/versatushpc-4/Ubuntu_24.04/versatushpc-openhpc.list
```

Then rerun the head, Warewulf, Slurm, MUNGE, linker, MPI, and IMB checks above.
