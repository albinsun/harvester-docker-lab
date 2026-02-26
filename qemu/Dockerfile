FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        qemu-system-x86 \
        iproute2 \
        bridge-utils \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /data

COPY start-vm.sh /start-vm.sh
RUN chmod +x /start-vm.sh

# VNC display :0 → TCP 5900
EXPOSE 5900

CMD ["/start-vm.sh"]
