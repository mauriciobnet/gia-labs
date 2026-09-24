#!/usr/bin/env bash
# Faz com que os hostnames *.localhost funcionem DENTRO do container.
#
# Por quê: curl (>= 7.77), navegadores e várias libs implementam a RFC 6761 e
# resolvem "localhost" e "*.localhost" SEMPRE para 127.0.0.1, sem consultar o DNS.
# Por isso os aliases de rede do Traefik (keycloak.localhost, lam.localhost, ...)
# eram ignorados e todo curl dentro do container falhava com código 000.
#
# Solução: publicar um encaminhador local 127.0.0.1:$GIA_PORT -> traefik:$GIA_PORT.
# O cabeçalho Host é preservado, então o roteamento do Traefik continua funcionando
# e os containers usam exatamente a MESMA URL que o navegador, porta inclusive
# (issuer e redirect_uri do Keycloak dependem dessa igualdade).
set -u
PORTA="${GIA_PORT:-18080}"

if ! (exec 3<>/dev/tcp/127.0.0.1/"$PORTA") 2>/dev/null; then
  socat TCP-LISTEN:"$PORTA",fork,reuseaddr TCP:traefik:"$PORTA" >/dev/null 2>&1 &
  for _ in $(seq 1 20); do
    (exec 3<>/dev/tcp/127.0.0.1/"$PORTA") 2>/dev/null && break
    sleep 0.1
  done
fi

exec "$@"
