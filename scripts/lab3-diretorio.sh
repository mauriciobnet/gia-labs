#!/usr/bin/env bash
# Lab 3 · O diretório visto pelas aplicações.
#
# O trabalho do aluno neste lab é na INTERFACE (LAM, GLPI, Grafana). Este script não
# faz o lab por ele: serve para conferir se o que ele fez na tela chegou mesmo no
# diretório, para o professor demonstrar o mesmo por LDIF, e para limpar entre turmas.
#
# Roda DENTRO do toolbox:
#   docker compose exec toolbox bash /work/scripts/lab3-diretorio.sh            # conferir
#   docker compose exec toolbox bash /work/scripts/lab3-diretorio.sh exemplo
#   docker compose exec toolbox bash /work/scripts/lab3-diretorio.sh limpar --confirmo
set -uo pipefail

BASE="dc=acme,dc=edu,dc=br"
PESSOAS="ou=people,$BASE"
GRUPOS="ou=groups,$BASE"
ADMIN="cn=admin,$BASE"
SENHA_ADMIN="admin"
H="ldap://openldap:389"
SEMENTE="ana.souza bruno.lima carla.dias"
SEMENTE_GRUPOS="ti professores"

G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; C=$'\e[36m'; N=$'\e[0m'

# Cada verificação também alimenta a evidência que o aluno entrega no Moodle. O que
# torna esse arquivo difícil de passar adiante entre colegas não é assinatura nenhuma:
# são os DNs que a própria pessoa criou, com o nome dela, que vão registrados aqui.
EV_ITENS="/tmp/gia-itens-$$.tsv"; : > "$EV_ITENS" 2>/dev/null || true
ev_item() { # estado o_que [observado]
  printf '%s\t%s\t%s\n' "$1" "$(printf '%s' "$2" | tr '\t\n' '  ')" \
    "$(printf '%s' "${3:-}" | tr '\t\n' '  ')" >> "$EV_ITENS" 2>/dev/null || true
}

ok(){ printf '%s[ OK ]%s %s\n' "$G" "$N" "$*"; ev_item ok "$*"; }
ko(){ printf '%s[FALHA]%s %s\n' "$R" "$N" "$*"; ev_item falha "$*"; FALHAS=$((FALHAS+1)); }
nota(){ printf '%s[ .. ]%s %s\n' "$Y" "$N" "$*"; ev_item ok "nota: $*"; }
titulo(){ printf '\n%s== %s ==%s\n' "$C" "$*" "$N"; }
FALHAS=0

busca(){ ldapsearch -x -LLL -H "$H" -D "$ADMIN" -w "$SENHA_ADMIN" "$@" 2>/dev/null; }

conferir() {
  titulo "A árvore da ACME"
  if ! busca -b "$BASE" -s base dn >/dev/null; then
    ko "não consegui ler $BASE (o OpenLDAP está de pé? veja o painel)"
    return 1
  fi
  ok "diretório respondendo em $H"

  titulo "Pessoas em $PESSOAS"
  local uids novos=0
  uids=$(busca -b "$PESSOAS" "(objectClass=inetOrgPerson)" uid | awk '/^uid: /{print $2}' | sort)
  [ -z "$uids" ] && { ko "nenhuma pessoa encontrada"; return 1; }
  while read -r u; do
    [ -z "$u" ] && continue
    local nome mail marca=""
    nome=$(busca -b "uid=$u,$PESSOAS" -s base cn | awk '/^cn: /{ $1=""; sub(/^ /,""); print }' | head -1)
    mail=$(busca -b "uid=$u,$PESSOAS" -s base mail | awk '/^mail: /{print $2}' | head -1)
    case " $SEMENTE " in *" $u "*) marca="(do seed)" ;; *) marca="${G}(criado na aula)${N}"; novos=$((novos+1)) ;; esac
    printf '  %-16s %-26s %-28s %s\n' "$u" "${nome:-sem cn}" "${mail:-sem mail}" "$marca"
  done <<< "$uids"
  ev_item ok "pessoas no diretório" "$(echo "$uids" | paste -sd', ' -)"
  [ "$novos" -gt 0 ] && ok "$novos pessoa(s) criada(s) além do seed" || nota "só as 3 pessoas do seed: ninguém criou usuário ainda"

  titulo "Grupos em $GRUPOS"
  local cns
  cns=$(busca -b "$GRUPOS" "(objectClass=groupOfNames)" cn | awk '/^cn: /{print $2}' | sort)
  [ -z "$cns" ] && nota "nenhum grupo groupOfNames encontrado"
  while read -r g; do
    [ -z "$g" ] && continue
    local membros marca=""
    membros=$(busca -b "cn=$g,$GRUPOS" -s base member | awk '/^member: /{print $2}' | sed "s/,${PESSOAS}//;s/uid=//" | paste -sd', ' -)
    case " $SEMENTE_GRUPOS " in *" $g "*) marca="(do seed)" ;; *) marca="${G}(criado na aula)${N}" ;; esac
    printf '  %-16s membros: %-40s %s\n' "$g" "${membros:-nenhum}" "$marca"
    ev_item ok "grupo $g" "membros: ${membros:-nenhum}"
  done <<< "$cns"

  titulo "O que cada aplicação vai ver"
  echo "  Grafana procura a pessoa com (uid=DIGITADO) em $PESSOAS"
  echo "  e depois pergunta ao grupo quem tem member=<DN da pessoa>."
  echo "  GLPI faz a mesma coisa com o filtro (&(objectClass=inetOrgPerson))."
  echo
  echo "  Regra que pega todo mundo: uma pessoa sem o atributo mail entra, mas"
  echo "  aparece sem e-mail nas duas aplicações, e o GLPI reclama ao importar."
  local sem_mail
  sem_mail=$(busca -b "$PESSOAS" "(&(objectClass=inetOrgPerson)(!(mail=*)))" uid | awk '/^uid: /{print $2}' | paste -sd', ' -)
  [ -n "$sem_mail" ] && ko "sem e-mail: $sem_mail" || ok "todas as pessoas têm e-mail"

  local sem_senha
  sem_senha=$(busca -b "$PESSOAS" "(&(objectClass=inetOrgPerson)(!(userPassword=*)))" uid | awk '/^uid: /{print $2}' | paste -sd', ' -)
  [ -n "$sem_senha" ] && ko "sem senha (não conseguem entrar em lugar nenhum): $sem_senha" || ok "todas as pessoas têm senha definida"

  titulo "Resumo"
  if [ "$FALHAS" -eq 0 ]; then
    carimbo ok "$(echo "$uids" | wc -l) pessoas, $(echo "$cns" | wc -l) grupos"
    printf '%sLAB3 OK%s\n' "$G" "$N"
  else
    carimbo falha "$FALHAS ponto(s) a corrigir no diretório"
    printf '%sLAB3 com %s ponto(s) a corrigir%s\n' "$R" "$FALHAS" "$N"
  fi
}

exemplo() {
  titulo "Criando dani.alves e o grupo secretaria por LDIF"
  echo "É exatamente o que a tela do LAM faz por baixo: escrever uma entrada no diretório."
  local ldif
  ldif=$(cat <<EOF
dn: uid=dani.alves,$PESSOAS
objectClass: inetOrgPerson
uid: dani.alves
cn: Dani Alves
givenName: Dani
sn: Alves
mail: dani.alves@acme.edu.br
userPassword: Senha@123

dn: cn=secretaria,$GRUPOS
objectClass: groupOfNames
cn: secretaria
member: uid=dani.alves,$PESSOAS
EOF
)
  printf '%s\n' "$ldif"
  echo
  if printf '%s\n' "$ldif" | ldapadd -x -H "$H" -D "$ADMIN" -w "$SENHA_ADMIN" >/dev/null 2>&1; then
    ok "dani.alves e secretaria criados"
  else
    nota "já existiam, ou houve erro; rodando de novo com a saída visível:"
    printf '%s\n' "$ldif" | ldapadd -x -H "$H" -D "$ADMIN" -w "$SENHA_ADMIN"
  fi
  echo
  echo "Teste do bind (é isto que a aplicação faz quando a pessoa digita a senha):"
  if ldapwhoami -x -H "$H" -D "uid=dani.alves,$PESSOAS" -w 'Senha@123' 2>/dev/null; then
    ok "dani.alves consegue autenticar"
  else
    ko "dani.alves não autenticou"
  fi
}

limpar() {
  if [ "${1:-}" != "--confirmo" ]; then
    echo "Isto apaga TODA pessoa e TODO grupo que não vieram do seed."
    echo "Repita com: bash /work/scripts/lab3-diretorio.sh limpar --confirmo"
    return 1
  fi
  titulo "Removendo o que foi criado além do seed"
  local u g
  for u in $(busca -b "$PESSOAS" "(objectClass=inetOrgPerson)" uid | awk '/^uid: /{print $2}'); do
    case " $SEMENTE " in *" $u "*) continue ;; esac
    ldapdelete -x -H "$H" -D "$ADMIN" -w "$SENHA_ADMIN" "uid=$u,$PESSOAS" 2>/dev/null && ok "removida a pessoa $u" || ko "não removi $u"
  done
  for g in $(busca -b "$GRUPOS" "(objectClass=groupOfNames)" cn | awk '/^cn: /{print $2}'); do
    case " $SEMENTE_GRUPOS " in *" $g "*) continue ;; esac
    ldapdelete -x -H "$H" -D "$ADMIN" -w "$SENHA_ADMIN" "cn=$g,$GRUPOS" 2>/dev/null && ok "removido o grupo $g" || ko "não removi $g"
  done
  echo
  nota "os grupos do seed continuam com os membros que estiverem lá; confira com 'conferir'"
}

carimbo() { # ok|falha detalhe
  ev_item "$1" "resumo do lab" "$2"
  [ -s "$EV_ITENS" ] || return 0
  python3 /work/scripts/evidencia.py gravar --lab 3 \
    --titulo "Lab 3: o diretório visto pelas aplicações" --itens "$EV_ITENS" || true
}

case "${1:-conferir}" in
  conferir) conferir ;;
  exemplo)  exemplo; conferir ;;
  limpar)   shift; limpar "$@" ;;
  *) echo "uso: $0 [conferir|exemplo|limpar --confirmo]"; exit 2 ;;
esac
