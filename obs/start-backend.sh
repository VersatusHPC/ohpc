#!/bin/bash
# Start OBS backend services using installed binaries
set -e

# Create required directories as obsrun. The OBS data volume may live on NFS,
# where rootless containers cannot recursively chown files even when ownership
# is already correct.
obs_dirs=(
    /srv/obs/repos
    /srv/obs/srcrep
    /srv/obs/upload
    /srv/obs/trees
    /srv/obs/build
    /srv/obs/jobs
    /srv/obs/workers
    /srv/obs/run
    /srv/obs/log
)

run_as_obsrun() {
    runuser -u obsrun -- "$@"
}

mkdir -p "${obs_dirs[@]}"

# Fix ownership for tmpfs-mounted dirs (events, jobs, run) that are owned
# by root after mount. Also fix /srv/obs if NFS/volume changed ownership.
for dir in /srv/obs /srv/obs/events /srv/obs/jobs /srv/obs/run; do
    [ -d "$dir" ] && chown -R obsrun:obsrun "$dir" 2>/dev/null || true
done

# Copy BSConfig if mounted
if [ -f /etc/obs/BSConfig.pm.custom ]; then
    cp /etc/obs/BSConfig.pm.custom /usr/lib/obs/server/BSConfig.pm
fi

# Patch BSUtil.pm: NFS requires read-write fd for LOCK_EX (flock)
# The upstream code opens read-only '<' which fails on ZFS/NFS with EBADF
sed -i "498s/open(\$fg, '<'/open(\$fg, '+<'/" /usr/lib/obs/server/BSUtil.pm 2>/dev/null || true

echo "Starting OBS backend services..."

cd /usr/lib/obs/server

# Start source server
echo "Starting bs_srcserver on port 5352..."
run_as_obsrun ./bs_srcserver &

# Start repo server
echo "Starting bs_repserver on port 5252..."
run_as_obsrun ./bs_repserver &

# Start scheduler
echo "Starting bs_sched x86_64..."
run_as_obsrun ./bs_sched x86_64 &

# Start dispatcher
echo "Starting bs_dispatch..."
run_as_obsrun ./bs_dispatch &

# Start publisher
echo "Starting bs_publish..."
run_as_obsrun ./bs_publish &

# Start service daemon
echo "Starting bs_dodup..."
run_as_obsrun ./bs_dodup &

echo "Starting bs_service..."
run_as_obsrun ./bs_service &

echo "OBS backend services started."

# The OBS backend commands daemonize, so the wrapper process must remain alive
# to keep the container from being restarted by the runtime policy.
tail -f /dev/null
