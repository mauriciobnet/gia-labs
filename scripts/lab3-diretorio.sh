#!/usr/bin/env bash
# Lab 3 · O diretório visto pelas aplicações.
#
# O trabalho do aluno neste lab é na INTERFACE: cadastrar o diretório no GLPI, importar
# as pessoas e os grupos, escrever a regra que dá Super-Admin a quem está em ti e testar,
# na tela LDAP do Grafana, o papel que cada pessoa recebe. Este script não faz o lab por
# ele: serve para conferir se o que ele fez na tela ficou gravado (no diretório, no banco
# do GLPI e na resposta do Grafana), para o professor demonstrar por LDIF o que uma tela
# de cadastro como a do LAM escreve no diretório, e para limpar entre turmas.
#
# Nenhum modo mexe no GLPI nem no Grafana: o banco do GLPI é lido só com SELECT e o
# Grafana só com GET. Só os modos exemplo e limpar escrevem, e só no diretório.
#
# Roda DENTRO do toolbox:
#   docker compose exec toolbox bash /work/scripts/lab3-diretorio.sh            # conferir
#   docker compose exec toolbox bash /work/scripts/lab3-diretorio.sh exemplo
#   docker compose exec toolbox bash /work/scripts/lab3-diretorio.sh limpar --confirmo
#
# O modo conferir sai com código 0 quando tudo passou e 1 quando alguma verificação falhou.
set -uo pipefail

BASE="dc=acme,dc=edu,dc=br"
PESSOAS="ou=people,$BASE"
GRUPOS="ou=groups,$BASE"
ADMIN="cn=admin,$BASE"
SENHA_ADMIN="admin"
H="ldap://openldap:389"
SEMENTE="ana.souza bruno.lima carla.dias"
SEMENTE_GRUPOS="ti professores"

# GLPI e Grafana, do bloco do Lab 3. A conexão com o banco e a URL do Grafana são as mesmas
# do lab4-ldap-tls.sh. O u() é cópia do lib.sh; o lib.sh inteiro não é carregado aqui porque,
# ao ser carregado, ele já tenta falar com um serviço que este lab não usa, e porque define
# ok/ko com outro contador de falhas.
PORTA=${GIA_PORT:-18080}
u(){ printf 'http://%s.localhost:%s%s' "$1" "$PORTA" "${2:-}"; }
GRAFANA=$(u grafana)
GRAFANA_SENHA=${GRAFANA_ADMIN_SENHA:-admin}   # só se alguém trocou a senha do admin do Grafana
MYSQL=$(command -v mariadb || command -v mysql || true)
# Auth::LDAP no GLPI 10.0.26 (src/Auth.php): é o valor que glpi_users.authtype recebe
# quando a conta veio de um diretório LDAP.
AUTH_LDAP=3
SUBIR_LAB3="suba o bloco do Lab 3: docker compose --profile lab3 up -d"

G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; C=$'\e[36m'; N=$'\e[0m'

# Cada verificação também alimenta a evidência que o aluno entrega no Moodle. O que torna
# esse arquivo difícil de passar adiante entre colegas não é assinatura nenhuma, e também
# não são as pessoas do diretório: nos 21 passos ninguém cria pessoa, e as três do seed são
# iguais para a turma inteira. O que muda de uma instalação para outra é o que o GLPI gravou
# quando o aluno fez o lab: os ids e as datas de criação do diretório, dos grupos e da regra,
# e as datas em que a ana.souza foi importada e sincronizada. É isso que vai no campo
# "observado", junto com o nome, o e-mail e o identificador da instalação que o evidencia.py
# acrescenta. Nenhuma senha é lida nem registrada.
EV_ITENS="/tmp/gia-itens-$$.tsv"; : > "$EV_ITENS" 2>/dev/null || true
SQL_ERR="/tmp/gia-lab3-sql-$$.err"
trap 'rm -f "$EV_ITENS" "$SQL_ERR" 2>/dev/null' EXIT
ev_item() { # estado o_que [observado]
  printf '%s\t%s\t%s\n' "$1" "$(printf '%s' "$2" | tr '\t\n' '  ')" \
    "$(printf '%s' "${3:-}" | tr '\t\n' '  ')" >> "$EV_ITENS" 2>/dev/null || true
}

ok(){ printf '%s[ OK ]%s %s\n' "$G" "$N" "$*"; ev_item ok "$*"; }
ko(){ printf '%s[FALHA]%s %s\n' "$R" "$N" "$*"; ev_item falha "$*"; FALHAS=$((FALHAS+1)); }
nota(){ printf '%s[ .. ]%s %s\n' "$Y" "$N" "$*"; ev_item ok "nota: $*"; }
titulo(){ printf '\n%s== %s ==%s\n' "$C" "$*" "$N"; }
# Iguais a ok/ko, mas com o que foi visto numa segunda linha e no campo "observado" da
# evidência. Um item só por verificação, em vez de um ok() seguido de um ev_item().
okv(){ # o_que observado
  printf '%s[ OK ]%s %s\n' "$G" "$N" "$1"
  [ -z "${2:-}" ] || printf '       %s\n' "$2"
  ev_item ok "$1" "${2:-}"
}
kov(){ # o_que observado
  printf '%s[FALHA]%s %s\n' "$R" "$N" "$1"
  [ -z "${2:-}" ] || printf '       visto: %s\n' "$2"
  ev_item falha "$1" "${2:-}"; FALHAS=$((FALHAS+1))
}
FALHAS=0

busca(){ ldapsearch -x -LLL -H "$H" -D "$ADMIN" -w "$SENHA_ADMIN" "$@" 2>/dev/null; }

# Consulta ao banco do GLPI, só leitura. -N -B: sem cabeçalho, colunas separadas por
# tabulação. Toda coluna que pode vir NULL passa por COALESCE, porque no modo -B o NULL
# vira a palavra "NULL". As colunas são separadas com cut, que não junta campos vazios.
sql(){ "$MYSQL" -h glpidb -u glpi -pglpi glpi -N -B --connect-timeout=5 -e "$1" 2>"$SQL_ERR"; }
# O cliente repete a consulta antes da mensagem de erro; interessa só a linha ERROR.
sql_erro(){ { grep -m1 '^ERROR' "$SQL_ERR" || head -1 "$SQL_ERR"; } 2>/dev/null | cut -c1-200; }
campo(){ printf '%s\n' "$1" | cut -f"$2"; }
simnao(){ [ "$1" = 1 ] && echo Sim || echo Não; }

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
  ev_item ok "pessoas no diretório" "$(echo "$uids" | paste -sd, - | sed 's/,/, /g')"
  [ "$novos" -gt 0 ] && ok "$novos pessoa(s) criada(s) além do seed" || nota "só as 3 pessoas do seed, que são as que o Lab 3 usa"

  titulo "Grupos em $GRUPOS"
  local cns
  cns=$(busca -b "$GRUPOS" "(objectClass=groupOfNames)" cn | awk '/^cn: /{print $2}' | sort)
  [ -z "$cns" ] && nota "nenhum grupo groupOfNames encontrado"
  while read -r g; do
    [ -z "$g" ] && continue
    local membros marca=""
    membros=$(busca -b "cn=$g,$GRUPOS" -s base member | awk '/^member: /{print $2}' | sed "s/,${PESSOAS}//;s/uid=//" | paste -sd, - | sed 's/,/, /g')
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
  sem_mail=$(busca -b "$PESSOAS" "(&(objectClass=inetOrgPerson)(!(mail=*)))" uid | awk '/^uid: /{print $2}' | paste -sd, - | sed 's/,/, /g')
  [ -n "$sem_mail" ] && ko "sem e-mail: $sem_mail" || ok "todas as pessoas têm e-mail"

  local sem_senha
  sem_senha=$(busca -b "$PESSOAS" "(&(objectClass=inetOrgPerson)(!(userPassword=*)))" uid | awk '/^uid: /{print $2}' | paste -sd, - | sed 's/,/, /g')
  [ -n "$sem_senha" ] && ko "sem senha (não conseguem entrar em lugar nenhum): $sem_senha" || ok "todas as pessoas têm senha definida"

  conferir_glpi
  conferir_grafana

  titulo "Resumo"
  if [ "$FALHAS" -eq 0 ]; then
    carimbo ok "$(echo "$uids" | wc -l) pessoas e $(echo "$cns" | wc -l) grupos no diretório; no GLPI, diretório, pessoas, grupos, regra e Super-Admin da ana.souza; no Grafana, Admin para a ana.souza e Editor para a carla.dias"
    printf '%sLAB3 OK%s\n' "$G" "$N"
  else
    carimbo falha "$FALHAS ponto(s) a corrigir"
    printf '%sLAB3 com %s ponto(s) a corrigir%s\n' "$R" "$FALHAS" "$N"
    echo "Cada [FALHA] acima diz qual passo do tutorial refazer. Refaça e rode este script de novo."
  fi
  [ "$FALHAS" -eq 0 ]
}

# ---------------------------------------------------------------------------
# GLPI. O que a tela mostra pode ter ficado só no formulário; o banco diz o que foi salvo.
# Tabelas e colunas conferidas no esquema do GLPI 10.0.26 (install/mysql/glpi-empty.sql) e
# no código de AuthLDAP, User, Group e RuleRight da mesma versão.
DIR_ID=""; DIR_NOME=""

conferir_glpi() {
  titulo "GLPI (banco glpi em glpidb, só leitura)"
  if [ -z "$MYSQL" ]; then
    ko "sem cliente mariadb no toolbox (refaça a imagem: docker compose build toolbox)"
    return 0
  fi
  if ! sql "SELECT 1" >/dev/null; then
    ko "o banco do GLPI não respondeu: $SUBIR_LAB3 (erro: $(sql_erro))"
    return 0
  fi
  if ! sql "SELECT COUNT(*) FROM glpi_authldaps" >/dev/null; then
    ko "o banco respondeu, mas o GLPI ainda não terminou de se instalar. Espere um minuto, confira no painel se o GLPI está verde e rode de novo (erro: $(sql_erro))"
    return 0
  fi
  glpi_diretorio
  glpi_pessoas
  glpi_filtro_grupos
  glpi_grupos
  glpi_regra
  glpi_perfis
}

# Passos 5 e 6: um diretório ativo apontando para o OpenLDAP da ACME. Se houver mais de um
# cadastrado, fica o que aponta para o lugar certo e, entre esses, o ativo e o padrão.
glpi_diretorio() {
  local linha nome host porta base ativo padrao criado aponta visto
  linha=$(sql "SELECT id, COALESCE(name,''), COALESCE(host,''), port, COALESCE(basedn,''),
                      is_active, is_default, COALESCE(date_creation,''),
                      COALESCE(LOWER(TRIM(host)) IN ('openldap','ldap://openldap','ldap://openldap:389')
                               AND LOWER(REPLACE(basedn,' ','')) = '$BASE', 0) AS aponta
               FROM glpi_authldaps
               ORDER BY aponta DESC, is_active DESC, is_default DESC, id
               LIMIT 1") || { ko "não consegui ler glpi_authldaps: $(sql_erro)"; return; }
  if [ -z "$linha" ]; then
    kov "refaça os passos 3 a 6: o GLPI não tem nenhum diretório LDAP. Em Configuração > Autenticação > Diretórios LDAP > + Adicionar, use a pré-configuração OpenLDAP, Servidor openldap, Porta 389, BaseDN $BASE e Ativo e Servidor padrão em Sim" \
        "nenhum diretório cadastrado"
    return
  fi
  DIR_ID=$(campo "$linha" 1); nome=$(campo "$linha" 2); host=$(campo "$linha" 3)
  porta=$(campo "$linha" 4); base=$(campo "$linha" 5); ativo=$(campo "$linha" 6)
  padrao=$(campo "$linha" 7); criado=$(campo "$linha" 8); aponta=$(campo "$linha" 9)
  DIR_NOME=$nome
  visto="diretório '$nome' (id $DIR_ID) em $host:$porta, BaseDN $base, Ativo $(simnao "$ativo"), Servidor padrão $(simnao "$padrao"), criado em ${criado:-data não registrada}"
  if [ "$aponta" != 1 ]; then
    kov "refaça o passo 5: o diretório cadastrado no GLPI não aponta para o OpenLDAP da ACME. Use Servidor openldap e BaseDN $BASE" "$visto"
  elif [ "$ativo" != 1 ]; then
    kov "refaça o passo 5: o diretório '$nome' está com Ativo em Não, e o GLPI ignora diretório inativo no login. Troque para Sim e salve" "$visto"
  else
    okv "o GLPI tem um diretório LDAP ativo apontando para o OpenLDAP (passos 5 e 6)" "$visto"
    [ "$padrao" = 1 ] || nota "o diretório '$nome' não está como Servidor padrão. Não impede a conferência, mas o passo 5 pede Sim"
  fi
}

# Passo 10: as três pessoas do seed importadas desse diretório. Importar grava
# authtype = Auth::LDAP e auths_id = id do diretório (AuthLDAP::ldapImportUserByServerId);
# uma conta criada à mão no GLPI fica com authtype 1 (Auth::DB_GLPI).
glpi_pessoas() {
  local linhas linha p tipo dir criada sinc faltam="" erradas="" vistos=""
  linhas=$(sql "SELECT name, authtype, auths_id, COALESCE(date_creation,''), COALESCE(date_sync,'')
                FROM glpi_users
                WHERE name IN ('ana.souza','bruno.lima','carla.dias') AND is_deleted = 0
                ORDER BY name, (authtype = $AUTH_LDAP AND auths_id = ${DIR_ID:-0}) DESC, id") \
    || { ko "não consegui ler glpi_users: $(sql_erro)"; return; }
  for p in $SEMENTE; do
    linha=$(printf '%s\n' "$linhas" | awk -v p="$p" 'BEGIN{FS="\t"} $1 == p' | head -1)
    if [ -z "$linha" ]; then faltam="${faltam:+$faltam, }$p"; continue; fi
    tipo=$(campo "$linha" 2); dir=$(campo "$linha" 3)
    criada=$(campo "$linha" 4); sinc=$(campo "$linha" 5)
    if [ "$tipo" != "$AUTH_LDAP" ]; then
      erradas="${erradas:+$erradas; }a conta $p foi criada à mão no GLPI, não importada do diretório"
    elif [ "$dir" != "${DIR_ID:-}" ]; then
      erradas="${erradas:+$erradas; }a conta $p veio de outro diretório (id $dir)"
    else
      vistos="${vistos:+$vistos; }$p importada em ${criada:-data não registrada}, sincronizada em ${sinc:-data não registrada}"
    fi
  done
  if [ -n "$faltam" ] || [ -n "$erradas" ]; then
    kov "refaça os passos 8 a 10: ${faltam:+não encontrei no GLPI: $faltam. }${erradas:+$erradas. }Em Administração > Usuários > ... De uma fonte externa > Importar novos usuários, pesquise com os campos em branco e importe todo mundo${erradas:+ (apague antes a conta que não veio do diretório)}" \
        "${vistos:-nenhuma das três pessoas importada de um diretório}"
  else
    okv "ana.souza, bruno.lima e carla.dias existem no GLPI, importadas do diretório '$DIR_NOME' (passo 10)" "$vistos"
  fi
}

# Passo 17: o filtro de grupos. A pré-configuração OpenLDAP do GLPI 10.0.26 grava ali o
# filtro de pessoas, (objectClass=inetOrgPerson) (AuthLDAP::preconfig, caso 'OpenLDAP').
glpi_filtro_grupos() {
  local filtro
  if [ -z "$DIR_ID" ]; then
    ko "refaça o passo 17 depois de criar o diretório (passos 3 a 6): sem diretório não há filtro de grupos para conferir"
    return
  fi
  filtro=$(sql "SELECT COALESCE(group_condition,'') FROM glpi_authldaps WHERE id = $DIR_ID") \
    || { ko "não consegui ler o filtro de grupos: $(sql_erro)"; return; }
  case "$(printf '%s' "$filtro" | tr '[:upper:]' '[:lower:]')" in
    *objectclass=groupofnames*)
      okv "o filtro de grupos do diretório '$DIR_NOME' procura groupOfNames (passo 17)" "Filtrar para pesquisar em grupos: $filtro" ;;
    *)
      kov "refaça o passo 17: no diretório '$DIR_NOME', aba Grupos, troque Filtrar para pesquisar em grupos por (objectClass=groupOfNames) e salve" \
          "Filtrar para pesquisar em grupos: ${filtro:-vazio}" ;;
  esac
}

# Passo 18: os grupos importados do diretório. Com a busca "Em grupos", o GLPI grava o DN do
# grupo LDAP em glpi_groups.ldap_group_dn (AuthLDAP::ldapImportGroup, tipo "groups").
glpi_grupos() {
  local linhas linha g faltam="" vistos="" a_mao
  linhas=$(sql "SELECT LOWER(ldap_group_dn), id, COALESCE(name,''), COALESCE(date_creation,'')
                FROM glpi_groups
                WHERE LOWER(ldap_group_dn) IN ('cn=ti,$GRUPOS', 'cn=professores,$GRUPOS')
                ORDER BY id") \
    || { ko "não consegui ler glpi_groups: $(sql_erro)"; return; }
  for g in $SEMENTE_GRUPOS; do
    linha=$(printf '%s\n' "$linhas" | awk -v dn="cn=$g,$GRUPOS" 'BEGIN{FS="\t"} $1 == dn' | head -1)
    if [ -z "$linha" ]; then faltam="${faltam:+$faltam e }$g"; continue; fi
    vistos="${vistos:+$vistos; }grupo '$(campo "$linha" 3)' (id $(campo "$linha" 2)) com DN cn=$g,$GRUPOS, criado em $(campo "$linha" 4)"
  done
  if [ -z "$faltam" ]; then
    okv "os grupos ti e professores existem no GLPI, importados do diretório (passo 18)" "$vistos"
    return
  fi
  # Engano comum: criar o grupo pelo + Adicionar, com o mesmo nome, em vez de importar.
  a_mao=$(sql "SELECT GROUP_CONCAT(name ORDER BY name SEPARATOR ', ') FROM glpi_groups
               WHERE name IN ('ti','professores') AND COALESCE(ldap_group_dn,'') = ''" 2>/dev/null || true)
  [ "$a_mao" = "NULL" ] && a_mao=""
  kov "refaça o passo 18: não encontrei no GLPI, com o DN do diretório, o grupo $faltam. Em Administração > Grupos > Link do diretório LDAP > Importação dos novos grupos, marque ti e professores e importe pelo menu Ações. Se a lista vier vazia, o filtro do passo 17 não foi salvo${a_mao:+. Existe grupo criado à mão, sem o DN do diretório ($a_mao): apague e importe}" \
      "${vistos:-nenhum grupo com DN do diretório}"
}

# Passo 19: a regra. Regra de autorização é glpi_rules.sub_type = 'RuleRight'. O critério
# Grupo é o _groups_id de RuleRight::getCriterias(), do tipo dropdown, e por isso o GLPI
# grava em glpi_rulecriterias.pattern o id do grupo, não o nome; a condição "é" é
# Rule::PATTERN_IS = 0. A ação Perfis, Atribuir é field = 'profiles_id' com action_type =
# 'assign' em glpi_ruleactions, e o value é o id do perfil. Os ids variam, então o grupo é
# achado pelo DN e o perfil pelo nome.
glpi_regra() {
  local linha id nome ativa criada mod crit visto
  linha=$(sql "SELECT r.id, COALESCE(r.name,''), r.is_active, COALESCE(r.date_creation,''), COALESCE(r.date_mod,''),
                      (SELECT COUNT(*) FROM glpi_rulecriterias c JOIN glpi_groups g ON g.id = c.pattern
                        WHERE c.rules_id = r.id AND c.criteria = '_groups_id' AND c.\`condition\` = 0
                          AND LOWER(g.ldap_group_dn) = 'cn=ti,$GRUPOS') AS criterio_ti
               FROM glpi_rules r
               WHERE r.sub_type = 'RuleRight'
                 AND EXISTS (SELECT 1 FROM glpi_ruleactions a JOIN glpi_profiles p ON p.id = a.value
                              WHERE a.rules_id = r.id AND a.action_type = 'assign'
                                AND a.field = 'profiles_id' AND p.name = 'Super-Admin')
               ORDER BY (r.is_active = 1 AND criterio_ti > 0) DESC, r.is_active DESC, criterio_ti DESC, r.id
               LIMIT 1") \
    || { ko "não consegui ler as regras (glpi_rules): $(sql_erro)"; return; }
  if [ -z "$linha" ]; then
    kov "refaça o passo 19: não existe regra de autorização que atribua o perfil Super-Admin. Em Administração > Regras > Regras para associar permissões a um usuário, crie a regra, e na aba Ações adicione Perfis, Atribuir, Super-Admin" \
        "nenhuma regra de autorização com a ação Perfis = Super-Admin"
    return
  fi
  id=$(campo "$linha" 1); nome=$(campo "$linha" 2); ativa=$(campo "$linha" 3)
  criada=$(campo "$linha" 4); mod=$(campo "$linha" 5); crit=$(campo "$linha" 6)
  visto="regra '$nome' (id $id), Ativo $(simnao "$ativa"), criada em ${criada:-data não registrada}, alterada em ${mod:-data não registrada}"
  if [ "$ativa" != 1 ]; then
    kov "refaça o passo 19: a regra '$nome' existe, mas está com Ativo em Não. Troque para Sim e salve" "$visto"
  elif [ "${crit:-0}" -lt 1 ]; then
    kov "refaça o passo 19: a regra '$nome' não tem o critério Grupo é ti. Na aba Critérios, adicione Grupo, é, ti (o grupo importado do diretório no passo 18)" "$visto"
  else
    okv "existe a regra ativa '$nome', que dá Super-Admin a quem está no grupo ti (passo 19)" "$visto"
  fi
}

# Passo 20: o efeito da regra. glpi_profiles_users.is_dynamic = 1 é o (D) da aba
# Autorizações: perfil dado por regra na sincronização (User::applyRightRules), e não à mão.
glpi_perfis() {
  local linhas linha perfis sa_din sa sinc
  linhas=$(sql "SELECT u.name,
                       COALESCE(GROUP_CONCAT(CONCAT(p.name, IF(pu.is_dynamic = 1, ' (D)', '')) ORDER BY p.name SEPARATOR ', '), ''),
                       COALESCE(MAX(p.name = 'Super-Admin' AND pu.is_dynamic = 1), 0),
                       COALESCE(MAX(p.name = 'Super-Admin'), 0),
                       COALESCE(u.date_sync,'')
                FROM glpi_users u
                LEFT JOIN glpi_profiles_users pu ON pu.users_id = u.id
                LEFT JOIN glpi_profiles p ON p.id = pu.profiles_id
                WHERE u.name IN ('ana.souza','carla.dias') AND u.is_deleted = 0
                  AND u.authtype = $AUTH_LDAP ${DIR_ID:+AND u.auths_id = $DIR_ID}
                GROUP BY u.id, u.name, u.date_sync
                ORDER BY u.name, u.id") \
    || { ko "não consegui ler os perfis (glpi_profiles_users): $(sql_erro)"; return; }

  linha=$(printf '%s\n' "$linhas" | awk 'BEGIN{FS="\t"} $1 == "ana.souza"' | head -1)
  if [ -z "$linha" ]; then
    ko "refaça o passo 20 depois do passo 10: a ana.souza não foi importada do diretório, então não há perfil dela para conferir"
  else
    perfis=$(campo "$linha" 2); sa_din=$(campo "$linha" 3); sa=$(campo "$linha" 4); sinc=$(campo "$linha" 5)
    if [ "$sa_din" = 1 ]; then
      okv "a ana.souza tem o perfil Super-Admin dinâmico, dado pela regra (passo 20)" "ana.souza: ${perfis}; última sincronização em ${sinc:-data não registrada}"
    elif [ "$sa" = 1 ]; then
      kov "a ana.souza tem Super-Admin sem o (D): foi atribuído à mão, não pela regra. Na aba Autorizações dela, apague a linha Super-Admin e refaça o passo 20" \
          "ana.souza: ${perfis}"
    else
      kov "refaça o passo 20: a ana.souza ainda não tem Super-Admin (D). Em Administração > Usuários > ... De uma fonte externa > Sincronização de usuários já importados, sincronize todos. Se continuar igual, confira os passos 17 a 19" \
          "ana.souza: ${perfis:-sem perfil}; última sincronização em ${sinc:-data não registrada}"
    fi
  fi

  linha=$(printf '%s\n' "$linhas" | awk 'BEGIN{FS="\t"} $1 == "carla.dias"' | head -1)
  if [ -z "$linha" ]; then
    ko "refaça o passo 10: a carla.dias não foi importada do diretório, então não há perfil dela para conferir"
  else
    perfis=$(campo "$linha" 2); sa=$(campo "$linha" 4)
    if [ "$sa" = 1 ]; then
      kov "a carla.dias tem Super-Admin, e não deveria: ela está em cn=professores, não em cn=ti. Confira no passo 19 se o critério da regra é Grupo é ti; se o Super-Admin dela está sem (D), foi dado à mão, então apague na aba Autorizações dela" \
          "carla.dias: ${perfis}"
    else
      okv "a carla.dias continua sem Super-Admin, porque não está no grupo ti (passo 20)" "carla.dias: ${perfis:-sem perfil}"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Grafana. /api/admin/ldap/<usuário> é a mesma consulta que a tela Administration >
# Authentication > LDAP faz no passo 16: procura a pessoa no diretório e diz que papel ela
# receberia, sem pedir a senha dela. Formato da resposta no Grafana v11.6.0
# (pkg/services/ldap/api/dtos.go): o papel vem em .roles[].orgRole e o grupo em
# .roles[].groupDN. Grupo da pessoa sem regra no ldap.toml também entra em .roles, com
# orgRole vazio, e por isso o filtro abaixo descarta papel vazio.
conferir_grafana() {
  titulo "Grafana ($GRAFANA, só leitura)"
  # Se o Grafana não responde ou recusa o admin, a segunda consulta daria a mesma falha.
  grafana_papel ana.souza Admin ti && grafana_papel carla.dias Editor professores
  return 0
}

grafana_papel() { # pessoa papel_esperado grupo. Devolve 1 só quando o Grafana inteiro falhou.
  local pessoa="$1" quer="$2" grupo="$3" resp codigo corpo login msg papel dn org visto
  resp=$(curl -sS -m 15 -u "admin:$GRAFANA_SENHA" -w '\n%{http_code}' "$GRAFANA/api/admin/ldap/$pessoa" 2>/dev/null || true)
  codigo=$(printf '%s\n' "$resp" | tail -n1)
  corpo=$(printf '%s\n' "$resp" | sed '$d')
  login=$(printf '%s' "$corpo" | jq -r '.login.ldapValue // empty' 2>/dev/null || true)
  # Erro do Grafana vem em JSON com "message". Sem isso, quem respondeu foi outro serviço:
  # com o Grafana fora do ar, o Traefik manda grafana.localhost para o painel.
  msg=$(printf '%s' "$corpo" | jq -r '.message // empty' 2>/dev/null || true)
  [ "$codigo" = 000 ] && codigo="sem resposta"
  case "$codigo" in
    200) [ -n "$login" ] || { ko "a resposta em $GRAFANA não veio do Grafana, então ele não está no ar: $SUBIR_LAB3"; return 1; } ;;
    401) ko "o Grafana recusou o login do admin na API (HTTP 401). Se você trocou a senha do admin do Grafana, rode de novo assim: GRAFANA_ADMIN_SENHA='a senha nova' bash /work/scripts/lab3-diretorio.sh"
         return 1 ;;
    404) if [ -n "$msg" ]; then
           ko "o Grafana não encontrou $pessoa no diretório (HTTP 404: $msg). Rode no host: docker compose restart grafana, e refaça o teste do passo 16"
           return 0
         fi
         ko "o Grafana não respondeu em $GRAFANA (HTTP 404): $SUBIR_LAB3"
         return 1 ;;
    500) # No Grafana 11.6, este 500 aparece quando ele não carregou o ldap.toml na subida: o
         # cliente LDAP fica vazio e a consulta quebra (service.go:266). O motivo fica no log.
         ko "o Grafana está no ar, mas não carregou a configuração LDAP (HTTP 500). Veja o motivo no host com: docker compose logs grafana | grep -i ldap. Se aparecer permission denied, rode no host: chmod 644 grafana/ldap.toml. Depois de corrigir, rode no host: docker compose restart grafana"
         return 1 ;;
    *) if [ -n "$msg" ]; then
         ko "o Grafana respondeu HTTP $codigo ao procurar $pessoa: $msg"
       else
         ko "o Grafana não respondeu em $GRAFANA (HTTP ${codigo:-sem resposta}): $SUBIR_LAB3"
       fi
       return 1 ;;
  esac
  papel=$(printf '%s' "$corpo" | jq -r '[.roles[]? | select((.orgRole // "") != "")][0].orgRole // empty' 2>/dev/null || true)
  dn=$(printf '%s' "$corpo" | jq -r '[.roles[]? | select((.orgRole // "") != "")][0].groupDN // empty' 2>/dev/null || true)
  org=$(printf '%s' "$corpo" | jq -r '[.roles[]? | select((.orgRole // "") != "")][0].orgName // empty' 2>/dev/null || true)
  visto="$login -> papel ${papel:-nenhum}${dn:+ pela regra do grupo $dn}${org:+, organização $org}"
  if [ "$papel" = "$quer" ]; then
    okv "no Grafana, $pessoa recebe o papel $quer pelo grupo $grupo (passo 16)" "$visto"
  else
    kov "no Grafana, $pessoa recebe o papel ${papel:-nenhum}, e o esperado é $quer pelo grupo cn=$grupo. Confira as regras do grafana/ldap.toml (passo 15) e se $pessoa continua no grupo $grupo do diretório; depois refaça o teste do passo 16" \
        "$visto"
  fi
  return 0
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
  conferir) conferir; exit $? ;;
  exemplo)  exemplo; conferir; exit $? ;;
  limpar)   shift; limpar "$@" ;;
  *) echo "uso: $0 [conferir|exemplo|limpar --confirmo]"; exit 2 ;;
esac
