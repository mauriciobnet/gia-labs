FROM alpine:3.21
# tcpdump: Lab 1C captura o próprio tráfego para mostrar a senha em claro na porta 389.
# mariadb-client: o Lab 1C confere no banco do GLPI se o "Usar TLS" foi mesmo salvo.
RUN apk add --no-cache bash curl jq openldap-clients openssl bind-tools python3 coreutils socat postgresql16-client mariadb-client tcpdump tzdata
COPY check.sh /check.sh
COPY jwt-decode.sh /usr/local/bin/jwt-decode
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /check.sh /usr/local/bin/jwt-decode /entrypoint.sh
WORKDIR /work
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
