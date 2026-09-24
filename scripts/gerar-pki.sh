#!/usr/bin/env bash
# Emite a CA raiz da ACME Ensino e o certificado do servidor de diretório.
# Roda DENTRO do toolbox e escreve em /work/pki, que é a pasta pki/ do host.
#
# Idempotente: se já existe certificado válido por mais de 30 dias e que confere com a CA,
# não emite nada. Use --forcar para emitir de novo (isso invalida o que o slapd está usando
# até o cn=config ser reaplicado).
set -euo pipefail
PKI=${PKI:-/work/pki}
FORCAR=0; [ "${1:-}" = "--forcar" ] && FORCAR=1

CA_DIR="$PKI/ca"; SRV_DIR="$PKI/ldap"
mkdir -p "$CA_DIR" "$SRV_DIR"
CA_KEY="$CA_DIR/acme-ca.key"; CA_CRT="$CA_DIR/acme-ca.crt"
SRV_KEY="$SRV_DIR/ldap.key";  SRV_CRT="$SRV_DIR/ldap.crt"

# 825 dias é o teto que clientes modernos aceitam para certificado de servidor. A CA pode
# durar mais porque quem a troca é o administrador, não o calendário do navegador.
DIAS_CA=${DIAS_CA:-3650}
DIAS_SRV=${DIAS_SRV:-825}
SUJ_CA="/C=BR/ST=Parana/L=Curitiba/O=ACME Ensino/OU=TI/CN=ACME Ensino Root CA"
SUJ_SRV="/C=BR/ST=Parana/L=Curitiba/O=ACME Ensino/OU=TI/CN=openldap"

# O SAN é o que os clientes realmente conferem; o CN virou decoração há anos. 'openldap' é
# o nome pelo qual GLPI, Grafana e toolbox chegam no diretório dentro da rede do Compose.
SAN="DNS:openldap,DNS:ldap.acme.edu.br,DNS:openldap.gia,DNS:localhost,IP:127.0.0.1"

ja_serve() {
  [ -s "$CA_CRT" ] && [ -s "$SRV_CRT" ] && [ -s "$SRV_KEY" ] || return 1
  openssl x509 -in "$SRV_CRT" -noout -checkend $((30*86400)) >/dev/null 2>&1 || return 1
  openssl verify -CAfile "$CA_CRT" "$SRV_CRT" >/dev/null 2>&1 || return 1
  # chave e certificado têm que ser do mesmo par, senão o slapd sobe e falha só no handshake
  [ "$(openssl x509 -in "$SRV_CRT" -noout -pubkey)" = "$(openssl pkey -in "$SRV_KEY" -pubout)" ] || return 1
}

if [ "$FORCAR" -eq 0 ] && ja_serve; then
  echo "PKI já existe e é válida; nada a fazer (use --forcar para reemitir)"
else
  echo "emitindo CA raiz da ACME Ensino ($DIAS_CA dias)"
  openssl req -x509 -newkey rsa:4096 -sha256 -days "$DIAS_CA" -nodes \
    -keyout "$CA_KEY" -out "$CA_CRT" -subj "$SUJ_CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -addext "subjectKeyIdentifier=hash" 2>/dev/null

  echo "emitindo certificado do servidor de diretório ($DIAS_SRV dias)"
  CSR=$(mktemp); EXT=$(mktemp)
  cat > "$EXT" <<EXTFIM
subjectAltName=$SAN
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EXTFIM
  openssl req -newkey rsa:2048 -nodes -keyout "$SRV_KEY" -out "$CSR" -subj "$SUJ_SRV" 2>/dev/null
  openssl x509 -req -in "$CSR" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
    -days "$DIAS_SRV" -sha256 -extfile "$EXT" -out "$SRV_CRT" 2>/dev/null
  rm -f "$CSR" "$EXT"
fi

# O slapd quer a CA no mesmo lugar que o resto; o /certs do container é só esta pasta.
cp -f "$CA_CRT" "$SRV_DIR/acme-ca.crt"

# 644 na chave privada: atalho de laboratório, explicado em pki/LEIA-ME.md. O slapd roda
# com outro usuário dentro do container e precisa ler o arquivo que veio do host.
chmod 644 "$CA_CRT" "$SRV_CRT" "$SRV_KEY" "$SRV_DIR/acme-ca.crt" 2>/dev/null || true
chmod 600 "$CA_KEY" 2>/dev/null || true

echo
openssl verify -CAfile "$CA_CRT" "$SRV_CRT"
openssl x509 -in "$SRV_CRT" -noout -subject -issuer -dates
openssl x509 -in "$SRV_CRT" -noout -ext subjectAltName
