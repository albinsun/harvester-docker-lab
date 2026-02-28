FROM alpine:3.19

RUN apk add --no-cache dnsmasq nginx

# Remove the default nginx server block that ships with Alpine to avoid a
# "duplicate default_server" conflict with our harvester.conf
RUN rm -f /etc/nginx/http.d/default.conf

RUN mkdir -p /tftpboot /var/www/harvester /run/nginx /var/log/nginx

COPY dnsmasq.conf /etc/dnsmasq.conf
COPY nginx.conf /etc/nginx/http.d/harvester.conf
COPY start-pxe.sh /start-pxe.sh

RUN chmod +x /start-pxe.sh

# DHCP, TFTP, HTTP
EXPOSE 67/udp 69/udp 80

CMD ["/start-pxe.sh"]
