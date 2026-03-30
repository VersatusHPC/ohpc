#!/bin/bash
# Start OBS backend services using installed binaries
set -e

# Create required directories
mkdir -p /srv/obs/{repos,srcrep,upload,trees,build,jobs,workers,run}
mkdir -p /srv/obs/log
chown -R obsrun:obsrun /srv/obs

# Copy BSConfig if mounted
if [ -f /etc/obs/BSConfig.pm.custom ]; then
    cp /etc/obs/BSConfig.pm.custom /usr/lib/obs/server/BSConfig.pm
fi

echo "Starting OBS backend services..."

cd /usr/lib/obs/server

# Start source server
echo "Starting bs_srcserver on port 5352..."
./bs_srcserver &

# Start repo server
echo "Starting bs_repserver on port 5252..."
./bs_repserver &

# Start scheduler
echo "Starting bs_sched x86_64..."
./bs_sched x86_64 &

# Start dispatcher
echo "Starting bs_dispatch..."
./bs_dispatch &

# Start publisher
echo "Starting bs_publish..."
./bs_publish &

# Start service daemon
echo "Starting bs_dodup..."
./bs_dodup &

echo "Starting bs_service..."
./bs_service &

echo "OBS backend services started."

# Wait for any process to exit
wait -n
echo "A backend process exited!"
wait
