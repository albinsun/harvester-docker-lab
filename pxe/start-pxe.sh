#!/bin/sh
set -e

# Start nginx in background
nginx

# Wait for nginx to be ready (retry up to 10 times, 1 second apart)
RETRIES=10
while [ "${RETRIES}" -gt 0 ]; do
    if pgrep nginx >/dev/null 2>&1; then
        break
    fi
    RETRIES=$((RETRIES - 1))
    sleep 1
done

if [ "${RETRIES}" -eq 0 ]; then
    echo "Error: nginx failed to start, aborting." >&2
    exit 1
fi

# Start dnsmasq in foreground (keeps container alive)
exec dnsmasq --no-daemon
