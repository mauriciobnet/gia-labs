#!/usr/bin/env bash
# Lab 2 · Ler o diretório antes de escrever nele.
#
# Este é o único lab em que o aluno não muda nada: ele lê. Por isso a evidência não
# pode ser "o script confirmou que funcionou", que seria igual para a turma inteira.
# Aqui o script mostra o diretório, faz cinco perguntas e registra as RESPOSTAS junto
# com o que o diretório de fato tinha na hora. Duas entregas iguais denunciam sozinhas,
# e você corrige lendo o campo "observado" de cada resposta.
#
# Roda DENTRO do toolbox:
#   docker compose exec toolbox bash /work/scripts/lab2-leitura.sh
set -uo pipefail

BASE="dc=acme,dc=edu,dc=br"
PESSOAS="ou=people,$BASE"
GRUPOS="ou=groups,$BASE"
ADMIN="cn=admin,$BASE"
SENHA_ADMIN="admin"
H="ldap://openldap:389"

G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; C=$'\e[36m'; N=$'\e[0m'
FALHAS=0
titulo(){ printf '\n%s== %s ==%s\n' "$C" "$*" "$N"; }
ok(){ printf '%s[ OK ]%s %s\n' "$G" "$N" "$*"; }
ko(){ printf '%s[FALHA]%s %s\n' "$R" "$N" "$*"; FALHAS=$((FALHAS+1)); }
nota(){ printf '%s[ .. ]%s %s\n' "$Y" "$N" "$*"; }

EV_ITENS="/tmp/gia-itens-$$.tsv"; : > "$EV_ITENS" 2>/dev/null || true
ev_item() {
  printf '%s\t%s\t%s\n' "$1" "$(printf '%s' "$2" | tr '\t\n' '  ')" \
    "$(printf '%s' "${3:-}" | tr '\t\n' '  ')" >> "$EV_ITENS" 2>/dev/null || true
}

busca(){ ldapsearch -x -LLL -H "$H" -D "$ADMIN" -w "$SENHA_ADMIN" "$@" 2>/dev/null; }

# O gerador do tutorial roda este script sem terminal interativo e só para mostrar as
# telas. Nesse caso as perguntas são puladas de propósito: registrar "sem resposta"
# como falha faria o tutorial nascer com um passo vermelho que não é erro de ninguém.
SEM_PERGUNTAS=0
[ "${1:-}" = "--sem-perguntas" ] && SEM_PERGUNTAS=1

# Pergunta ao aluno e registra a resposta. Sem terminal interativo (por exemplo dentro
# de um pipe), não trava: registra que ficou sem resposta e segue.
RESPONDIDAS=0
pergunta() { # id "texto"
  local resposta=""
  printf '\n%s? %s%s\n' "$Y" "$2" "$N"
  if [ "$SEM_PERGUNTAS" = "1" ]; then
    printf '  %s(modo demonstração: responda esta pergunta ao rodar sem --sem-perguntas)%s\n' "$Y" "$N"
    ev_item ok "pergunta $1" "$2 >>> (não respondida: execução em modo demonstração)"
    return 0
  fi
  if [ -t 0 ]; then
    printf '  sua resposta: '
    IFS= read -r resposta || true
  fi
  resposta=$(printf '%s' "$resposta" | sed 's/^ *//;s/ *$//')
  if [ -z "$resposta" ]; then
    ev_item falha "pergunta $1" "sem resposta: $2"
    FALHAS=$((FALHAS+1))
  else
    ev_item ok "pergunta $1" "$2 >>> $resposta"
    RESPONDIDAS=$((RESPONDIDAS+1))
  fi
}

titulo "O diretório responde?"
if ! busca -b "$BASE" -s base dn >/dev/null; then
  ko "não consegui ler $BASE (o OpenLDAP está de pé? veja o painel)"
  python3 /work/scripts/evidencia.py gravar --lab 2 --titulo "Lab 2: ler o diretório" --itens "$EV_ITENS" || true
  exit 1
fi
ok "diretório respondendo em $H"
ev_item ok "diretório respondendo" "$H"

titulo "A árvore inteira, um DN por linha"
ARVORE=$(busca -b "$BASE" dn | awk '/^dn: /{ $1=""; sub(/^ /,""); print }' | sort)
echo "$ARVORE" | sed 's/^/  /'
ev_item ok "entradas na árvore" "$(echo "$ARVORE" | wc -l) DNs"

titulo "Uma pessoa por inteiro: todos os atributos da ana.souza"
ANA=$(busca -b "uid=ana.souza,$PESSOAS" -s base)
echo "$ANA" | sed 's/^/  /'
CLASSES=$(echo "$ANA" | awk '/^objectClass: /{print $2}' | paste -sd', ' -)
ev_item ok "objectClass de ana.souza" "$CLASSES"

titulo "Um grupo por inteiro: cn=ti"
TI=$(busca -b "cn=ti,$GRUPOS" -s base)
echo "$TI" | sed 's/^/  /'
MEMBROS_TI=$(echo "$TI" | awk '/^member: /{ $1=""; sub(/^ /,""); print }' | paste -sd' | ' -)
ev_item ok "membros de cn=ti" "$MEMBROS_TI"

titulo "A mesma pergunta, feita ao contrário"
echo "  Quem está em cn=ti? Uma leitura só:"
echo "    ldapsearch ... -b 'cn=ti,$GRUPOS' member"
echo
echo "  De quais grupos a Ana faz parte? Nenhuma leitura direta responde:"
echo "    ldapsearch ... -b '$GRUPOS' '(member=uid=ana.souza,$PESSOAS)' cn"
DE_QUAIS=$(busca -b "$GRUPOS" "(member=uid=ana.souza,$PESSOAS)" cn | awk '/^cn: /{print $2}' | paste -sd', ' -)
echo "    resposta: ${DE_QUAIS:-nenhum}"
ev_item ok "grupos que contêm ana.souza" "${DE_QUAIS:-nenhum}"

titulo "Cinco perguntas. Responda com suas palavras."
echo "  As respostas entram no arquivo de entrega. Não existe resposta de uma palavra só."
pergunta 1 "Escreva o DN completo da carla.dias e diga o que cada parte dele significa."
pergunta 2 "Por que o atributo member do grupo guarda o DN inteiro da pessoa, e não só o uid?"
pergunta 3 "A entrada da ana.souza NÃO diz a que grupos ela pertence. Que consequência isso tem para uma aplicação que precisa saber o papel dela ao fazer login?"
pergunta 4 "O objectClass da ana.souza tem mais de um valor. Escolha um deles e diga que atributos ele obriga ou permite."
pergunta 5 "Se a instituição mudar a Ana de departamento e o DN dela mudar, o que quebra no grupo cn=ti?"

titulo "Resumo"
if [ "$SEM_PERGUNTAS" = "1" ]; then
  nota "modo demonstração: as cinco perguntas não foram respondidas"
  nota "para entregar de verdade, rode sem --sem-perguntas e responda cada uma"
elif [ "$FALHAS" -eq 0 ]; then
  ok "$RESPONDIDAS de 5 perguntas respondidas"
  ev_item ok "resumo do lab" "leitura feita e 5 perguntas respondidas"
else
  ko "$FALHAS ponto(s) pendente(s): responda todas as perguntas antes de entregar"
fi
python3 /work/scripts/evidencia.py gravar --lab 2 --titulo "Lab 2: ler o diretório" --itens "$EV_ITENS" || true
[ "$FALHAS" -eq 0 ]
