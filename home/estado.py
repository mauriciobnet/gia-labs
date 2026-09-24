# -*- coding: utf-8 -*-
"""Sondagem do estado dos serviços da stack GIA.

Só biblioteca padrão: o container do painel é a mesma imagem do toolbox
(alpine + python3), então nada extra é baixado.

Não usa o socket do Docker de propósito. Ver o daemon daria controle total dele a
quem alcançasse o painel, o que seria um contraexemplo ruim numa disciplina de
segurança. O estado é deduzido de três sinais, nesta ordem:

  1. o nome do serviço resolve no DNS da rede do Compose?  não -> container não existe
  2. a porta interna aceita conexão?                       não -> ainda subindo
  3. a rota do Traefik responde o código esperado?          não -> serviço de pé, rota não

É o suficiente para separar "perfil não ativado" de "ainda subindo" de "quebrou",
que são as três situações que o aluno encontra na prática.
"""
import json
import os
import socket
import threading
import time
import urllib.error
import urllib.request

PORTA = int(os.environ.get("GIA_PORT", "18080"))
TRAEFIK_HOST = "traefik"
INTERVALO = 4.0          # segundos entre sondagens
TIMEOUT_TCP = 1.5
TIMEOUT_HTTP = 3.0

SENHA = "Senha@123"

# host, porta: endereço INTERNO do container (para saber se o serviço está de pé)
# publico: nome usado no navegador (None = não passa pelo Traefik)
SERVICOS = [
    dict(id="traefik", nome="Traefik", grupo="base", perfil=None,
         host="traefik", porta=PORTA, tipo="http", publico="traefik",
         caminho="/dashboard/", codigos=[200, 301, 302],
         resumo="porta de entrada: recebe a porta %d e roteia por nome de host" % PORTA,
         gui="painel de rotas e serviços", lab="infraestrutura",
         cred=[], dica="se isto está fora, a porta %d do host provavelmente está ocupada" % PORTA),
    dict(id="whoami", nome="whoami", grupo="base", perfil=None,
         host="whoami", porta=80, tipo="http", publico="whoami",
         caminho="/", codigos=[200],
         resumo="eco dos cabeçalhos da requisição: mostra o que chega na aplicação",
         gui="página de texto puro", lab="Lab 1",
         cred=[], dica=None),
    dict(id="openldap", nome="OpenLDAP", grupo="base", perfil=None,
         host="openldap", porta=389, tipo="tcp", publico=None,
         resumo="diretório da ACME: dc=acme,dc=edu,dc=br com pessoas e grupos",
         gui="sem interface web, use o LAM ou o ldapsearch do toolbox", lab="Lab 2",
         cred=[("bind de administrador", "cn=admin,dc=acme,dc=edu,dc=br", "admin"),
               ("usuária de teste", "ana.souza", SENHA)],
         dica="no primeiro up o seed do diretório leva cerca de 30 s para ser aplicado"),
    dict(id="lam", nome="LDAP Account Manager", grupo="base", perfil=None,
         host="lam", porta=80, tipo="http", publico="lam",
         caminho="/", codigos=[200, 302],
         resumo="interface web para ler e editar o diretório",
         gui="administração do LDAP", lab="Lab 2",
         cred=[("login do LAM", "admin", "admin")],
         dica="o container leva cerca de 40 s para ficar saudável, e o Traefik só roteia depois disso"),
    dict(id="keycloak", nome="Keycloak", grupo="base", perfil=None,
         host="keycloak", porta=8080, tipo="http", publico="keycloak",
         caminho="/realms/master/.well-known/openid-configuration", codigos=[200],
         resumo="provedor de identidade: realms, federação com o LDAP, MFA e papéis",
         gui="console de administração em /admin", lab="Lab 5",
         cred=[("console de administração", "admin", "admin"),
               ("usuários do realm acme", "ana.souza, bruno.lima, carla.dias", SENHA)],
         dica="o primeiro start leva de 30 a 90 s; acompanhe com docker compose logs -f keycloak"),
    dict(id="glpidb", nome="MariaDB do GLPI", grupo="lab3", perfil="lab3",
         host="glpidb", porta=3306, tipo="tcp", publico=None,
         resumo="banco do GLPI; a imagem instala o GLPI sozinha assim que ele fica pronto",
         gui="sem interface", lab="Lab 3",
         cred=[("root", "root", "root"), ("aplicação", "glpi", "glpi")],
         dica="o primeiro start cria as tabelas e leva cerca de 1 min"),
    dict(id="glpi", nome="GLPI", grupo="lab3", perfil="lab3",
         host="glpi", porta=80, tipo="http", publico="glpi",
         caminho="/", codigos=[200, 302],
         resumo="central de serviços: é nela que o aluno configura a autenticação LDAP na mão",
         gui="interface web, entra com glpi/glpi", lab="Lab 3",
         cred=[("administrador", "glpi", "glpi"), ("técnico", "tech", "tech"),
               ("depois do LDAP", "ana.souza e os que a turma criar", SENHA)],
         dica="ele só responde depois que o MariaDB fica saudável e a instalação automática termina"),
    dict(id="grafana", nome="Grafana", grupo="lab3", perfil="lab3",
         host="grafana", porta=3000, tipo="http", publico="grafana",
         caminho="/login", codigos=[200, 302],
         resumo="a mesma aplicação nos dois modelos: LDAP direto no Lab 3, OIDC no Lab 6",
         gui="formulário de usuário e senha (LDAP) e, no Lab 6, o botão Keycloak ACME",
         lab="Labs 3 e 6",
         cred=[("login local de emergência", "admin", "admin"),
               ("pelo diretório ou pelo Keycloak", "ana.souza (grupo ti vira Admin)", SENHA)],
         dica=None),
]

GRUPOS = [
    ("base", "Base", "sempre no ar: Labs 1 e 2"),
    ("lab3", "Lab 3", "o diretório visto pelas aplicações"),
]

CARIMBOS = os.environ.get("GIA_CARIMBOS", "/carimbos")

# A trilha. Cada etapa tem um pré-requisito, o que dá ao painel o direito de dizer
# "ainda não" em vez de só "não feito": são coisas diferentes para quem está perdido.
LABS = [
    dict(id="1", rotulo="Lab 1", titulo="Preparar o ambiente", depende=None, perfil=None,
         tutorial="lab1", comando="docker compose --profile tools run --rm check"),
    dict(id="2", rotulo="Lab 2", titulo="Ler o diretório", depende="1", perfil=None,
         tutorial="lab2", comando="docker compose exec toolbox bash /work/scripts/lab2-leitura.sh"),
    dict(id="3", rotulo="Lab 3", titulo="O diretório visto pelas aplicações", depende="2", perfil="lab3",
         tutorial="lab3", comando="docker compose exec toolbox bash /work/scripts/lab3-diretorio.sh"),
    dict(id="4", rotulo="Lab 4", titulo="O diretório para de falar em voz alta", depende="3", perfil="lab3",
         tutorial="lab4", comando="docker compose exec toolbox bash /work/scripts/lab4-ldap-tls.sh"),
]

_estado = {"servicos": [], "labs": [], "aluno": None, "carregando": True,
           "porta": PORTA, "atualizado": 0}
_trava = threading.Lock()


def _resolve(host):
    try:
        socket.getaddrinfo(host, None)
        return True
    except OSError:
        return False


def _tcp(host, porta):
    try:
        with socket.create_connection((host, porta), TIMEOUT_TCP):
            return True
    except OSError:
        return False


def _http(caminho, host_cabecalho, timeout=TIMEOUT_HTTP):
    """Faz a requisição pelo Traefik, com o mesmo cabeçalho Host que o navegador manda."""
    url = "http://%s:%d%s" % (TRAEFIK_HOST, PORTA, caminho)
    req = urllib.request.Request(url, headers={
        "Host": "%s:%d" % (host_cabecalho, PORTA),
        "User-Agent": "painel-gia",
        "Accept": "*/*",
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(65536)
    except urllib.error.HTTPError as e:
        return e.code, b""
    except Exception:
        return None, b""


def _sonda(s):
    r = dict(id=s["id"], nome=s["nome"], grupo=s["grupo"], perfil=s["perfil"],
             resumo=s["resumo"], gui=s["gui"], lab=s["lab"],
             cred=[c for c in s["cred"] if c[1]], extra=None, dica=None)
    r["url"] = "http://%s.localhost:%d" % (s["publico"], PORTA) if s["publico"] else None

    if not _resolve(s["host"]):
        r["estado"] = "parado"
        r["detalhe"] = ("perfil %s não ativado" % s["perfil"]) if s["perfil"] else "container não está de pé"
        return r

    if not _tcp(s["host"], s["porta"]):
        r["estado"] = "subindo"
        r["detalhe"] = "container existe, a porta %d ainda não aceita conexão" % s["porta"]
        r["dica"] = s["dica"]
        return r

    if s["tipo"] == "tcp" or not s["publico"]:
        r["estado"] = "ok"
        r["detalhe"] = "porta %d respondendo" % s["porta"]
        return r

    codigo, corpo = _http(s["caminho"], "%s.localhost" % s["publico"])
    if codigo in s["codigos"]:
        r["estado"] = "ok"
        r["detalhe"] = "HTTP %d pela rota do Traefik" % codigo
        r["extra"] = _extra(s["id"], corpo)
    elif codigo is None:
        r["estado"] = "rota"
        r["detalhe"] = "o serviço está de pé, mas a rota do Traefik não respondeu"
        r["dica"] = s["dica"] or "o Traefik só roteia container saudável; espere o healthcheck"
    else:
        r["estado"] = "rota"
        r["detalhe"] = "a rota respondeu HTTP %d, fora do esperado" % codigo
        r["dica"] = s["dica"]
    return r


def _extra(ident, corpo):
    """Uma informação a mais, específica de cada serviço."""
    try:
        if ident == "keycloak":
            iss = json.loads(corpo.decode("utf-8")).get("issuer", "")
            esperado = "http://keycloak.localhost:%d/realms/master" % PORTA
            if iss and iss != esperado:
                return {"texto": "issuer divergente: %s" % iss, "alerta": True}
            return {"texto": "issuer: %s" % iss, "alerta": False}
        if ident == "openbao":
            d = json.loads(corpo.decode("utf-8"))
            return {"texto": "selado: %s · iniciado: %s" % (
                "sim" if d.get("sealed") else "não", "sim" if d.get("initialized") else "não"),
                "alerta": bool(d.get("sealed"))}
        if ident == "traefik":
            codigo, c = _http("/api/overview", "traefik.localhost")
            if codigo == 200:
                d = json.loads(c.decode("utf-8"))
                return {"texto": "%s roteadores HTTP ativos" % d.get("http", {}).get("routers", {}).get("total", "?"),
                        "alerta": False}
    except Exception:
        pass
    return None


def _aluno():
    """Quem está fazendo os labs, gravado uma vez pelo evidencia.py.

    O painel mostra isso no topo por um motivo prático: sem identificação, o arquivo
    de entrega sai anônimo e não serve para o Moodle. É melhor o aluno descobrir isso
    na primeira tela do que na hora de entregar.
    """
    try:
        with open(os.path.join(CARIMBOS, "aluno.json"), encoding="utf-8") as f:
            d = json.load(f)
        # Sem e-mail conta como não identificado: é por ele que o professor acha a
        # pessoa no Moodle. Um aluno.json antigo, só com nome, cai aqui e o painel volta
        # a pedir a identificação, o que é o certo.
        if d.get("nome") and d.get("email"):
            return {"nome": d.get("nome", ""), "email": d.get("email", ""),
                    "instalacao": d.get("instalacao", "")}
    except Exception:
        pass
    return None


def _labs():
    """Estado de cada etapa da trilha, lido dos arquivos de evidência.

    São quatro estados, todos decididos por arquivo, nenhum por opinião:

      concluida   existe evidência e todas as verificações passaram
      problema    existe evidência e alguma verificação falhou
      disponivel  não existe evidência, mas o pré-requisito está concluído
      bloqueada   não existe evidência e o pré-requisito também não

    Repare no que NÃO existe aqui: "em andamento". O painel não tem como saber que
    alguém está no meio de um lab, porque a evidência só nasce no fim. Inventar esse
    estado seria mentir para o aluno, e um painel que mente deixa de ser consultado.
    """
    achados = {}
    for lab in LABS:
        caminho = os.path.join(CARIMBOS, "evidencia-lab%s.json" % lab["id"])
        try:
            with open(caminho, encoding="utf-8") as f:
                achados[lab["id"]] = json.load(f)
        except Exception:
            achados[lab["id"]] = None

    saida = []
    concluidos = set()
    for lab in LABS:
        d = achados.get(lab["id"])
        if d is not None:
            estado = "concluida" if d.get("ok") else "problema"
        elif lab["depende"] is None or lab["depende"] in concluidos:
            estado = "disponivel"
        else:
            estado = "bloqueada"
        if estado == "concluida":
            concluidos.add(lab["id"])

        item = {k: lab[k] for k in ("id", "rotulo", "titulo", "depende", "perfil", "tutorial", "comando")}
        item.update(estado=estado,
                    resumo=(d or {}).get("resumo", ""),
                    quando=(d or {}).get("quando", ""),
                    verificacoes=len((d or {}).get("verificacoes", [])),
                    falhas=sum(1 for v in (d or {}).get("verificacoes", []) if v.get("estado") != "ok"),
                    evidencia=bool(d))
        saida.append(item)
    return saida


def instantaneo():
    with _trava:
        return dict(_estado)


def _ciclo():
    while True:
        inicio = time.time()
        servicos = []
        for s in SERVICOS:
            try:
                servicos.append(_sonda(s))
            except Exception as e:  # nenhuma sonda pode derrubar o painel
                servicos.append(dict(id=s["id"], nome=s["nome"], grupo=s["grupo"], perfil=s["perfil"],
                                     resumo=s["resumo"], gui=s["gui"], lab=s["lab"], cred=[],
                                     url=None, estado="rota", detalhe="falha ao sondar: %s" % e,
                                     dica=None, extra=None))
        with _trava:
            _estado.update(servicos=servicos, labs=_labs(), aluno=_aluno(), carregando=False, porta=PORTA,
                           atualizado=time.time(), duracao=round(time.time() - inicio, 2))
        time.sleep(max(0.5, INTERVALO - (time.time() - inicio)))


def comecar():
    t = threading.Thread(target=_ciclo, daemon=True)
    t.start()
    return t
