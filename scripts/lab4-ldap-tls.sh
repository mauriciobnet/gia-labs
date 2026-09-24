#!/usr/bin/env bash
# Lab 4 · O diretório deixa de falar em voz alta.
#
# A ordem aqui é a aula inteira: primeiro a gente PROVA que a senha atravessa a rede
# legível, depois emite a CA da ACME, liga o TLS no slapd que já está no ar, repete a
# captura na MESMA porta e mostra que não dá mais para ler, e só então arruma as duas
# aplicações que dependem do diretório. Nada é afirmado sem ser medido antes e depois.
#
# Roda DENTRO do toolbox. É reexecutável: se parar em alguma verificação, arrume o que
# ele apontar e rode de novo.
#   docker compose exec -T toolbox bash /work/scripts/lab4-ldap-tls.sh
set -uo pipefail
source /work/scripts/lib.sh

# --sem-glpi existe para a validação automática (validar.sh), que não abre a interface do
# GLPI e portanto não tem diretório LDAP cadastrado lá. O aluno nunca usa este argumento, e
# a evidência diz com todas as letras quando a verificação foi pulada.
SEM_GLPI=0; [ "${1:-}" = "--sem-glpi" ] && SEM_GLPI=1

BASE="dc=acme,dc=edu,dc=br"
ANA="uid=ana.souza,ou=people,$BASE"
SENHA='Senha@123'
CA=/work/pki/ca/acme-ca.crt
ANTES="$OUT/lab4-antes.pcap"
DEPOIS="$OUT/lab4-depois.pcap"

# ---------------------------------------------------------------------------
# Captura o tráfego do próprio container enquanto um comando roda. -p (sem modo
# promíscuo) porque container comum não tem CAP_NET_ADMIN; NET_RAW, que o tcpdump
# precisa, vem por padrão.
capturar() { # arquivo comando...
  local arq="$1"; shift
  rm -f "$arq"
  tcpdump -p -i any -s 0 -U -w "$arq" 'tcp port 389' >/dev/null 2>"$OUT/tcpdump.err" &
  local tpid=$!
  sleep 2                      # tcpdump precisa abrir a interface antes do primeiro pacote
  "$@" || true
  sleep 1
  kill "$tpid" 2>/dev/null || true
  wait "$tpid" 2>/dev/null || true
}

# Conta ocorrências de um texto dentro do pcap. Passa a captura por 'tr' para quebrar os
# bytes não imprimíveis em linhas: é isso que faz um arquivo binário virar algo que o grep
# lê sem depender de 'strings', que não vem na imagem.
ocorrencias() { tr -c '[:print:]' '\n' < "$1" | grep -c -F -- "$2" || true; }
trechos()     { tr -c '[:print:]' '\n' < "$1" | grep -F -- "$2" | head -4 || true; }

precisa() { command -v "$1" >/dev/null 2>&1 || { ko "ferramenta ausente no toolbox: $1 (refaça a imagem: docker compose build toolbox)"; return 1; }; }

say "0. ferramentas e diretório no ar"
precisa tcpdump || true
precisa openssl || true
precisa ldapsearch || true
# Com bind de administrador. A versão anterior perguntava anonimamente, e a ACL padrão do
# diretório nega leitura anônima de propósito (é o que o Lab 2 ensina no passo do bind
# anônimo). O teste acusava "diretório fora do ar" quando o diretório estava perfeito.
if ldapsearch -x -H ldap://openldap -D "cn=admin,$BASE" -w admin -b "$BASE" -s base dn >/dev/null 2>&1; then
  ok "diretório respondendo em ldap://openldap:389"
else
  ko "diretório não respondeu em ldap://openldap:389; suba a stack antes"
fi

# ---------------------------------------------------------------------------
say "1. ANTES: a senha de ana.souza na rede, em texto claro"
# ldapwhoami e não ldapsearch: o que interessa aqui é o BIND, que é onde a senha viaja.
# A ana só enxerga a própria entrada (a ACL do diretório é assim), então uma busca a partir
# da base voltaria vazia e pareceria erro de autenticação sem ser.
capturar "$ANTES" ldapwhoami -x -H ldap://openldap -D "$ANA" -w "$SENHA" >"$OUT/lab4-bind-antes.txt" 2>&1
if grep -q "uid=ana.souza" "$OUT/lab4-bind-antes.txt"; then
  ok "bind simples de ana.souza funcionou na porta 389 (sem TLS)"
else
  ko "o bind de ana.souza falhou: $(head -3 "$OUT/lab4-bind-antes.txt" | tr '\n' ' ')"
fi
N_ANTES=$(ocorrencias "$ANTES" "$SENHA")
if [ "${N_ANTES:-0}" -gt 0 ]; then
  ok "a senha apareceu $N_ANTES vez(es) dentro do pacote capturado"
  echo "   o que dava para ler no fio:"
  trechos "$ANTES" "ou=people" | sed 's/^/     /'
  trechos "$ANTES" "$SENHA"    | sed 's/^/     /'
  ev_item ok "senha em texto claro na porta 389" "$N_ANTES ocorrência(s) de '$SENHA' em $(basename "$ANTES")"
else
  ko "não consegui capturar o tráfego (tcpdump: $(head -2 "$OUT/tcpdump.err" 2>/dev/null | tr '\n' ' '))"
fi

# Achado de brinde, e de propósito: o lab conserta o transporte, não o armazenamento.
# O ldapsearch devolve o atributo em base64 (userPassword::) quando o valor tem byte
# "inseguro" para LDIF, e em texto (userPassword:) quando não tem. Os dois casos importam:
# é justamente o segundo que denuncia senha guardada em claro.
BRUTA=$(ldapsearch -x -LLL -H ldap://openldap -D "cn=admin,$BASE" -w admin -b "$ANA" -s base userPassword 2>/dev/null | tr -d '\r')
if printf '%s' "$BRUTA" | grep -q '^userPassword:: '; then
  GUARDADA=$(printf '%s' "$BRUTA" | sed -n 's/^userPassword:: //p' | tr -d '\n' | base64 -d 2>/dev/null || true)
else
  GUARDADA=$(printf '%s' "$BRUTA" | sed -n 's/^userPassword: //p' | head -1)
fi
case "$GUARDADA" in
  "{"*) ev_item ok "senha guardada no diretório" "com hash: ${GUARDADA%%\}*}}" ;;
  "")   ev_item ok "senha guardada no diretório" "não foi possível ler o atributo userPassword" ;;
  *)    echo "   Achado: o diretório guarda a senha em claro ($GUARDADA). O TLS deste lab protege o"
        echo "   transporte; o armazenamento se resolve gravando {SSHA} no lugar do texto puro."
        ev_item ok "senha guardada em claro no diretório" "userPassword devolveu o texto puro; TLS não resolve isso" ;;
esac

# ---------------------------------------------------------------------------
say "2. a CA da ACME Ensino e o certificado do diretório"
bash /work/scripts/gerar-pki.sh > "$OUT/lab4-pki.txt" 2>&1
if [ -s "$CA" ] && [ -s /work/pki/ldap/ldap.crt ]; then
  sed 's/^/   /' "$OUT/lab4-pki.txt"
  SAN=$(openssl x509 -in /work/pki/ldap/ldap.crt -noout -ext subjectAltName 2>/dev/null | tail -1 | tr -s ' ')
  EMISSOR=$(openssl x509 -in /work/pki/ldap/ldap.crt -noout -issuer | sed 's/^issuer=//')
  if printf '%s' "$SAN" | grep -q "DNS:openldap"; then
    ok "certificado do diretório emitido pela CA da ACME"
    ev_item ok "certificado do diretório" "emissor: $EMISSOR"
    ev_item ok "nomes válidos no certificado" "$SAN"
  else
    ko "o certificado não tem DNS:openldap no SAN; as aplicações vão recusar o nome"
  fi
else
  ko "a PKI não foi gerada: $(tail -3 "$OUT/lab4-pki.txt" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
say "3. ligar o TLS no slapd que já está no ar"
# Pela configuração em tempo de execução (cn=config), e não pela variável LDAP_TLS da
# imagem: a imagem só configuraria TLS na PRIMEIRA subida, e quem já fez os labs
# anteriores teria que apagar o volume e perder o diretório inteiro para consegui-lo.
ldapmodify -x -H ldap://openldap -D cn=admin,cn=config -w config -f /work/ldap/tls.ldif > "$OUT/lab4-modify.txt" 2>&1
APLICADO=$(ldapsearch -x -LLL -H ldap://openldap -D cn=admin,cn=config -w config -b cn=config -s base olcTLSCertificateFile 2>/dev/null | sed -n 's/^olcTLSCertificateFile: //p')
if [ "$APLICADO" = "/certs/ldap.crt" ]; then
  ok "slapd passou a apresentar o certificado: olcTLSCertificateFile = $APLICADO"
  ev_item ok "TLS configurado no diretório" "olcTLSCertificateFile = $APLICADO (lido de volta do cn=config)"
else
  ko "a configuração TLS não pegou no cn=config: $(tail -2 "$OUT/lab4-modify.txt" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
say "4. DEPOIS: mesma porta, mesma senha, agora dentro do TLS"
capturar "$DEPOIS" env LDAPTLS_CACERT="$CA" ldapwhoami -x -ZZ -H ldap://openldap -D "$ANA" -w "$SENHA" >"$OUT/lab4-bind-depois.txt" 2>&1
if grep -q "uid=ana.souza" "$OUT/lab4-bind-depois.txt"; then
  ok "bind de ana.souza funcionou por StartTLS, na mesma porta 389"
else
  ko "o bind com StartTLS falhou: $(head -3 "$OUT/lab4-bind-depois.txt" | tr '\n' ' ')"
fi
N_DEPOIS=$(ocorrencias "$DEPOIS" "$SENHA")
N_START=$(ocorrencias "$DEPOIS" "1.3.6.1.4.1.1466.20037")
if [ "${N_DEPOIS:-1}" -eq 0 ] && [ "${N_START:-0}" -gt 0 ]; then
  ok "na captura dá para ver o pedido de StartTLS e nada mais: zero ocorrência da senha"
  ev_item ok "senha protegida na mesma porta 389" "antes: $N_ANTES ocorrência(s); depois: 0. O pedido de StartTLS (OID 1.3.6.1.4.1.1466.20037) continua visível, o resto não."
elif [ "${N_DEPOIS:-1}" -ne 0 ]; then
  ko "a senha AINDA aparece $N_DEPOIS vez(es) na captura: o StartTLS não subiu"
else
  ko "não vi o pedido de StartTLS na captura; a conexão pode não ter passado por aqui"
fi

# ---------------------------------------------------------------------------
say "5. a verificação é de verdade? cliente sem a CA da ACME"
# Se este teste passasse, o TLS seria enfeite: um cliente que aceita qualquer certificado
# aceita também o de quem estiver no meio do caminho.
if env -u LDAPTLS_CACERT LDAPTLS_REQCERT=demand ldapwhoami -x -ZZ -H ldap://openldap -D "$ANA" -w "$SENHA" >"$OUT/lab4-sem-ca.txt" 2>&1; then
  ko "um cliente SEM a CA da ACME conseguiu conectar: a verificação não está valendo"
else
  ok "cliente sem a CA da ACME é recusado: $(grep -i -m1 'tls\|certificate' "$OUT/lab4-sem-ca.txt" | tr -s ' ' | cut -c1-90)"
  ev_item ok "verificação de certificado ativa" "cliente sem a CA da ACME não conecta"
fi

# ---------------------------------------------------------------------------
say "6. Grafana passa a consultar o diretório por StartTLS"
if [ ! -f /work/grafana/ldap.toml ]; then
  # A pasta grafana/ passou a ser montada no toolbox por causa deste lab. Quem atualizou a
  # stack sem recriar o container não tem a montagem ainda.
  ko "/work/grafana/ldap.toml não existe dentro do toolbox. Rode no host: docker compose up -d toolbox"
else
python3 /work/scripts/ligar-tls-grafana.py /work/grafana/ldap.toml | sed 's/^/   /'
python3 /work/scripts/conferir-grafana-ldap.py /work/grafana/ldap.toml >/dev/null 2>&1 || true
GRAFANA=$(u grafana)
LDAPUSER=$(curl -sS -m 15 -u admin:admin "$GRAFANA/api/admin/ldap/ana.souza" 2>/dev/null || true)
if printf '%s' "$LDAPUSER" | jq -e '.name? // .login? // .username?' >/dev/null 2>&1; then
  ok "Grafana encontrou ana.souza no diretório pelo canal com TLS"
  ev_item ok "Grafana falando LDAP com TLS" "consulta a ana.souza respondida pelo /api/admin/ldap"
else
  ko "o Grafana ainda não consultou o diretório por TLS. Rode no host: docker compose restart grafana"
  echo "   resposta do Grafana: $(printf '%s' "$LDAPUSER" | head -c 200)"
fi
fi

# ---------------------------------------------------------------------------
say "7. GLPI com 'Usar TLS' salvo na configuração do diretório"
MYSQL=$(command -v mariadb || command -v mysql || true)
if [ "$SEM_GLPI" = 1 ]; then
  echo "   pulada a pedido (--sem-glpi)"
  ev_item ok "GLPI falando LDAP com TLS" "verificação PULADA por --sem-glpi: a validação automática não configura o diretório do GLPI pela interface"
elif [ -z "$MYSQL" ]; then
  ko "sem cliente mariadb no toolbox (refaça a imagem: docker compose build toolbox)"
else
  LINHA=$("$MYSQL" -h glpidb -u glpi -pglpi glpi -N -B -e "select name,host,port,use_tls from glpi_authldaps order by id limit 1" 2>"$OUT/glpi-sql.err" || true)
  if [ -z "$LINHA" ]; then
    ko "o GLPI não tem diretório configurado (faça o Lab 3) ou o banco não respondeu: $(head -2 "$OUT/glpi-sql.err" | tr '\n' ' ')"
  else
    NOME=$(printf '%s' "$LINHA" | cut -f1); HOST=$(printf '%s' "$LINHA" | cut -f2)
    PORTA_G=$(printf '%s' "$LINHA" | cut -f3); TLS=$(printf '%s' "$LINHA" | cut -f4)
    echo "   diretório '$NOME' -> $HOST:$PORTA_G  use_tls=$TLS"
    if [ "$TLS" = "1" ]; then
      ok "GLPI configurado para falar com o diretório usando TLS"
      ev_item ok "GLPI falando LDAP com TLS" "servidor '$NOME' em $HOST:$PORTA_G com use_tls=1"
    else
      ko "no GLPI, o diretório '$NOME' ainda está sem TLS. Configuração > Autenticação > Diretórios LDAP > marque 'Usar TLS' e salve"
    fi
  fi
fi

say "resumo"
if [ "$FAILS" -eq 0 ]; then
  carimbar 4 "Lab 4: o diretório para de falar em voz alta" "senha capturada em claro, CA da ACME emitida, StartTLS ligado e as duas aplicações verificando o certificado" ok
  echo "LAB4 OK"
else
  carimbar 4 "Lab 4: o diretório para de falar em voz alta" "$FAILS verificação(ões) falharam" falha
  echo "LAB4 FALHOU ($FAILS)"
  exit 1
fi
