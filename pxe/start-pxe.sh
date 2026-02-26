#!/bin/sh
set -e

# Start nginx in background
nginx

# Start dnsmasq in foreground (keeps container alive)
exec dnsmasq --no-daemon
