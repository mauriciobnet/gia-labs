#!/usr/bin/env bash
# GIA Lab 1: verificação do ambiente (roda DENTRO do container toolbox)
set -uo pipefail
PORTA="${GIA_PORT:-18080}"
u(){ printf "http://%s.localhost:%s%s" "$1" "$PORTA" "${2:-}"; }
G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; N=$'\e[0m'
ok=0; fail=0; warn=0

# Cada verificação também vira uma linha da evidência que o aluno entrega no Moodle.
# O arquivo intermediário é TSV, então tabulação e quebra de linha viram espaço.
EV_ITENS="/tmp/gia-itens-$$.tsv"; : > "$EV_ITENS" 2>/dev/null || true
ev_item() { printf '%s\t%s\t%s\n' "$1" "$(printf '%s' "$2" | tr '\t\n' '  ')" "${3:-}" >> "$EV_ITENS" 2>/dev/null || true; }

pass(){ echo "${G}[ OK ]${N} $*"; ok=$((ok+1)); ev_item ok "$*"; }
bad(){  echo "${R}[FALHA]${N} $*"; fail=$((fail+1)); ev_item falha "$*"; }
wrn(){  echo "${Y}[AVISO]${N} $*"; warn=$((warn+1)); ev_item ok "aviso: $*"; }

# http_wait <url> <timeout_s> <codigos aceitos...> -> imprime o último código HTTP
# Os serviços web sobem em tempos diferentes (o LAM leva ~40 s para ficar healthy e
# o Traefik só roteia containers saudáveis), então esperamos em vez de falhar direto.
http_wait() {
  local url="$1" timeout="$2"; shift 2
  local deadline=$(( $(date +%s) + timeout )) code=000 want
  while :; do
    code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' "$url" || true)
    for want in "$@"; do [ "$code" = "$want" ] && { echo "$code"; return 0; }; done
    [ "$(date +%s)" -ge "$deadline" ] && { echo "$code"; return 1; }
    sleep 3
  done
}

echo "=== GIA · Lab 1: verificação do ambiente ==="
echo

# 1. arquitetura e memória visível aos containers
arch=$(uname -m)
case "$arch" in
  x86_64|aarch64) pass "Arquitetura: $arch" ;;
  *) wrn "Arquitetura incomum: $arch (algumas imagens podem não existir)" ;;
esac
mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
mem_gb=$(awk -v k="$mem_kb" 'BEGIN{printf "%.1f", k/1024/1024}')
if [ "$mem_kb" -ge 3900000 ]; then pass "Memória disponível para containers: ${mem_gb} GB"
else bad "Memória para containers: ${mem_gb} GB (mínimo 4 GB, ajuste no Docker Desktop > Settings > Resources)"; fi

# 2. Traefik e roteamento por hostname (mesma URL que o navegador usa)
if curl -fsS -m 5 http://traefik:8080/api/overview >/dev/null 2>&1; then pass "Traefik respondendo"
else bad "Traefik não responde (porta 80 do host ocupada? veja 'docker compose logs traefik')"; fi
code=$(http_wait "$(u whoami /)" 60 200)
if [ "$code" = "200" ]; then pass "Roteamento por hostname (whoami.localhost:$PORTA) OK"
else bad "whoami.localhost:$PORTA retornou '$code' via Traefik (a porta $PORTA do host está livre? veja 'docker compose logs traefik')"; fi

# 3. LDAP: no primeiro 'up' o seed leva ~30 s para ser aplicado
ldap_ok=0
ldap_deadline=$(( $(date +%s) + 90 ))
while :; do
  if ldapsearch -x -H ldap://openldap:389 -b "dc=acme,dc=edu,dc=br" -D "cn=admin,dc=acme,dc=edu,dc=br" -w admin "(uid=ana.souza)" uid 2>/dev/null | grep -q "uid: ana.souza"; then
    ldap_ok=1; break
  fi
  [ "$(date +%s)" -ge "$ldap_deadline" ] && break
  sleep 3
done
if [ "$ldap_ok" = "1" ]; then
  pass "OpenLDAP respondendo e seed carregado (uid=ana.souza)"
else
  bad "OpenLDAP sem resposta ou sem seed (veja 'docker compose logs openldap')"
fi
code=$(http_wait "$(u lam /)" 90 200 302)
if [ "$code" = "200" ] || [ "$code" = "302" ]; then pass "LAM (lam.localhost:$PORTA) OK"
else bad "LAM retornou '$code' (o container leva ~40 s para ficar healthy)"; fi

# 4. Keycloak
http_wait "$(u keycloak /realms/master/.well-known/openid-configuration)" 120 200 >/dev/null
if curl -fsS -m 5 "$(u keycloak /realms/master/.well-known/openid-configuration)" >/tmp/oidc.json 2>/dev/null; then
  iss=$(jq -r .issuer /tmp/oidc.json)
  if [ "$iss" = "$(u keycloak /realms/master)" ]; then pass "Keycloak OK, issuer: $iss"
  else bad "Keycloak respondeu mas o issuer não bate com a porta em uso: $iss (esperado $(u keycloak /realms/master); confira GIA_PORT no .env)"; fi
else
  bad "Keycloak ainda não responde (primeiro start leva 30-90 s; veja 'docker compose logs -f keycloak')"
fi

# 5. saída para internet (para baixar imagens dos próximos labs)
if curl -fsS -m 8 -o /dev/null https://quay.io/v2/ 2>/dev/null || curl -s -m 8 -o /dev/null -w '%{http_code}' https://quay.io/v2/ | grep -qE '^(200|401)$'; then
  pass "Acesso ao registry quay.io"
else wrn "Sem acesso a quay.io (imagens dos próximos labs podem não baixar)"; fi

echo
echo "Resumo: ${G}$ok OK${N}, ${R}$fail falhas${N}, ${Y}$warn avisos${N}"
echo "Painel do laboratório: http://localhost:$PORTA"
echo "Teste final no NAVEGADOR: abra $(u whoami) e $(u keycloak)"
# A evidência substitui o carimbo antigo: mesmo papel para o painel, e agora também
# é o arquivo que o aluno entrega. O código curto continua existindo porque é o que a
# turma lê em voz alta quando o professor pergunta "quem já terminou?".
gravar_evidencia() {
  [ -s "$EV_ITENS" ] || return 0
  python3 /work/scripts/evidencia.py gravar --lab 1 --titulo "Lab 1: ambiente verificado" --itens "$EV_ITENS" || true
}

if [ "$fail" -eq 0 ]; then
  code=$(printf '%s-%s' "$(hostname)" "$(date +%Y%m%d)" | sha256sum | cut -c1-6)
  ev_item ok "código do ambiente" "$code"
  gravar_evidencia
  echo "${G}LAB1 OK · código: $code${N}"; exit 0
else
  gravar_evidencia
  echo "${R}LAB1 FALHOU · corrija os itens em vermelho${N}"; exit 1
fi
