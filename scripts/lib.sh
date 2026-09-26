#!/usr/bin/env bash
# Funções comuns aos scripts de lab (rodam DENTRO do toolbox).
# Porta publicada pela stack (.env: GIA_PORT). Os containers usam a MESMA URL do
# navegador, porta inclusive, senão o issuer e os redirect_uri do Keycloak não batem.
PORTA=${GIA_PORT:-18080}
SUF=":$PORTA"
u(){ printf 'http://%s.localhost:%s%s' "$1" "$PORTA" "${2:-}"; }

KC=${KC:-$(u keycloak)}
REALM=${REALM:-acme}
OUT=/work/out; mkdir -p "$OUT" 2>/dev/null || OUT=/tmp

# Token de admin do Keycloak, com paciência. Depois de um "docker compose restart keycloak"
# o realm já responde a descoberta OIDC enquanto a API de administração ainda está subindo.
# Sem a espera, o token vinha vazio e a próxima chamada morria com um "curl: (22)" pelado,
# sem status e sem motivo, que foi exatamente o que aconteceu no passo 81-persist.
kc_admin_token() {
  local i resp tok
  for i in $(seq 1 10); do
    resp=$(curl -fsS -m 10 -X POST "$KC/realms/master/protocol/openid-connect/token" \
      -d grant_type=password -d client_id=admin-cli -d username=admin -d password=admin 2>/dev/null) || resp=""
    tok=$(printf '%s' "$resp" | jq -r '.access_token // empty' 2>/dev/null || true)
    if [ -n "$tok" ]; then printf '%s' "$tok"; return 0; fi
    sleep 2
  done
  echo "lib.sh: Keycloak não emitiu token de admin em $KC após 10 tentativas" >&2
  return 1
}
# Sem '|| ADMIN_TOKEN=""' o set -e derrubaria, ainda no source, labs que nem precisam do
# Keycloak, como os do diretório. Quem precisa do token falha adiante, com mensagem própria.
ADMIN_TOKEN=$(kc_admin_token) || ADMIN_TOKEN=""
auth=(-H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json")

kc_get()  { curl -fsS "${auth[@]}" "$KC/admin/realms/$REALM$1"; }
kc_post() { curl -fsS -X POST "${auth[@]}" "$KC/admin/realms/$REALM$1" -d "$2"; }
kc_put()  { curl -fsS -X PUT  "${auth[@]}" "$KC/admin/realms/$REALM$1" -d "$2"; }

# id de um client pelo clientId (vazio se não existe)
kc_client_id() { kc_get "/clients?clientId=$1" | jq -r '.[0].id // empty'; }

# cria client se não existir; $1 = JSON completo (deve conter clientId)
kc_ensure_client() {
  local cid; cid=$(echo "$1" | jq -r .clientId)
  local id; id=$(kc_client_id "$cid")
  if [ -z "$id" ]; then kc_post "/clients" "$1" >/dev/null; id=$(kc_client_id "$cid"); echo "client $cid criado ($id)" >&2
  else echo "client $cid já existe ($id)" >&2; fi
  echo "$id"
}

# token de usuário via password grant em um client (público ou confidencial)
kc_user_token() { # user pass client [secret]
  local args=(-d grant_type=password -d client_id="$3" -d username="$1" -d "password=$2" -d scope=openid)
  [ -n "${4:-}" ] && args+=(-d client_secret="$4")
  curl -fsS -X POST "$KC/realms/$REALM/protocol/openid-connect/token" "${args[@]}"
}

group_id() { kc_get "/groups?search=$1&exact=true" | jq -r '.[0].id // empty'; }

# ---------------------------------------------------------------------------
# Evidência do lab: o arquivo que o aluno entrega no Moodle e que o painel lê.
#
# O truque aqui é que ok() e ko() já são chamados em todo lugar pelos labs. Em vez de
# instrumentar cada script, eles passam a alimentar a lista de verificações, e o
# carimbar() do fim só manda gravar. Nenhum lab precisou mudar por causa disto.
EV_ITENS="${EV_ITENS:-/tmp/gia-itens-$$.tsv}"
: > "$EV_ITENS" 2>/dev/null || true

# Acrescenta uma verificação. Tabulação e quebra de linha viram espaço porque o
# arquivo intermediário é TSV e uma mensagem com tab corromperia a coluna seguinte.
ev_item() { # estado o_que [observado]
  local e q o
  e="$1"
  q=$(printf '%s' "$2" | tr '\t\n' '  ')
  o=$(printf '%s' "${3:-}" | tr '\t\n' '  ')
  printf '%s\t%s\t%s\n' "$e" "$q" "$o" >> "$EV_ITENS" 2>/dev/null || true
}

# Grava a evidência. Mantém o nome antigo e a assinatura antiga de propósito: os labs
# 3 a 6 chamam carimbar(numero, nome, detalhe, ok|falha) e continuam funcionando.
carimbar() { # numero "titulo" "detalhe" [ok|falha]
  [ -n "${3:-}" ] && ev_item "${4:-ok}" "resumo do lab" "$3"
  [ -s "$EV_ITENS" ] || return 0
  python3 /work/scripts/evidencia.py gravar --lab "$1" --titulo "$2" --itens "$EV_ITENS" || true
  EV_GRAVADA=1
}

# Rede de segurança: evidência de lab que morreu no meio.
#
# Todo lab roda com set -e. Um curl que falha, um jq que não casa, um serviço fora do ar, e o
# script morre ANTES do carimbar. Sem isto, o arquivo de evidência não nasce, e o painel pinta
# a etapa como "pode começar", que é mentira: ela começou e quebrou. Pior, o aluno não tem o
# que entregar e não sabe por quê. O trap grava o que chegou a ser verificado e diz, dentro do
# próprio arquivo, que o lab foi interrompido.
#
# O número do lab sai do nome do script (lab2-leitura.sh -> 2, lab4-ldap-tls.sh -> 4) para que
# nenhum lab precise ser alterado. Script que não é lab não casa com o padrão e não grava nada.
EV_GRAVADA=0
LAB_NUM=$(printf '%s' "${0##*/}" | sed -n 's/^lab\([0-9][a-z]*\)-.*/\1/p')

_ev_saida() {
  local rc=$?
  if [ "${EV_GRAVADA:-0}" = 0 ] && [ -n "${LAB_NUM:-}" ] && [ -s "$EV_ITENS" ]; then
    ev_item falha "o laboratório foi interrompido" "o script parou no meio (código $rc); as verificações registradas são só as que chegaram a rodar"
    python3 /work/scripts/evidencia.py gravar --lab "$LAB_NUM" --titulo "Lab $LAB_NUM (interrompido)" --itens "$EV_ITENS" >/dev/null 2>&1 || true
    printf '\n\e[31m[INTERROMPIDO]\e[0m o lab parou no meio (código %s). A evidência foi gravada assim mesmo,\n               marcada como interrompida, para o painel não dizer que a etapa nem começou.\n' "$rc" >&2
  fi
  rm -f "$EV_ITENS" 2>/dev/null || true
}
trap _ev_saida EXIT

say() { printf '\n== %s ==\n' "$*"; }
ok()  { printf '\e[32m[ OK ]\e[0m %s\n' "$*"; ev_item ok "$*"; }
ko()  { printf '\e[31m[FALHA]\e[0m %s\n' "$*"; ev_item falha "$*"; FAILS=$((FAILS+1)); }
FAILS=0
