#!/bin/bash
# Start OBS build workers using the installed bs_worker binary.
# This replaces the development start_development_worker script.
set -e

HOST="${OBS_BACKEND_HOST:-backend}"
WORKER_N="${OBS_WORKER_COUNT:-2}"

trap 'echo "Stopping workers..."; killall bs_worker 2>/dev/null; exit 0' SIGHUP SIGINT SIGTERM

# Wait for backend to become available
echo "Waiting for backend at $HOST:5352..."
for i in $(seq 1 60); do
    if curl -s -o /dev/null "http://$HOST:5352/about" 2>/dev/null; then
        echo "Backend is ready."
        break
    fi
    [ "$i" -eq 60 ] && echo "WARNING: Backend not responding after 60s, starting workers anyway."
    sleep 1
done

w_count=1
while [ $w_count -le $WORKER_N ]; do
    mkdir -p /srv/obs/run/worker/$w_count
    mkdir -p /var/cache/obs/worker/root_$w_count
    chown -R obsrun:obsrun /srv/obs/run/ 2>/dev/null || true

    echo "Starting bs_worker number $w_count"
    /usr/lib/obs/server/bs_worker \
        --hardstatus \
        --root /var/cache/obs/worker/root_$w_count \
        --statedir /srv/obs/run/worker/$w_count \
        --id "$(hostname):$w_count" \
        --reposerver "http://$HOST:5252" \
        --hostlabel OBS_WORKER_SECURITY_LEVEL_ \
        --jobs 1 \
        --cachedir /var/cache/obs/worker/cache \
        --cachesize 3967 &

    w_count=$((w_count + 1))
done

echo "$((WORKER_N)) workers started."
wait
