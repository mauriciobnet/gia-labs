# -*- coding: utf-8 -*-
"""Evidência de laboratório: o arquivo que o aluno entrega e que o painel lê.

Um arquivo por lab, gravado no volume de saída do toolbox. Ele serve a três leitores
diferentes, e é por isso que existe um módulo só para ele em vez de três printf
espalhados pelos scripts:

  o aluno      baixa pelo painel e sobe no Moodle;
  o painel     lê para colorir a trilha, e é a única memória que ele tem, porque as
               sondas dizem o que está NO AR, não o que já foi FEITO;
  o professor  corrige em lote, porque é JSON.

Sobre cópia entre colegas: o que dificulta não é assinatura nenhuma, é o conteúdo. O
arquivo carrega o nome e o RA de quem rodou, o identificador daquela instalação, os
horários, e principalmente os dados que a pessoa mesma criou, como o DN do usuário com
o nome dela. Dois arquivos iguais denunciam sozinhos. O campo "conferencia" é um
sha256 do conteúdo e serve para detectar edição acidental; NÃO é assinatura, porque o
script roda na máquina do aluno e qualquer um pode recalcular. Dizer o contrário seria
teatro de segurança, e esta é uma disciplina de segurança.

Uso (chamado pelo lib.sh, raramente à mão):
  python3 evidencia.py aluno   --nome "Fulano de Tal" --ra 2026001
  python3 evidencia.py gravar  --lab 3 --titulo "..." --itens /tmp/itens.tsv
  python3 evidencia.py mostrar --lab 3
"""
import argparse
import hashlib
import io
import json
import os
import socket
import sys
import time
import uuid

FORMATO = "gia-evidencia/1"
SAIDA = os.environ.get("GIA_SAIDA", "/work/out")


def _agora():
    return time.strftime("%Y-%m-%dT%H:%M:%S%z")


def caminho_evidencia(lab, saida=None):
    return os.path.join(saida or SAIDA, "evidencia-lab%s.json" % lab)


def _arquivo_aluno(saida=None):
    return os.path.join(saida or SAIDA, "aluno.json")


def instalacao(saida=None):
    """Identificador estável desta instalação, criado na primeira vez e reusado.

    Serve para o professor perceber quando dois trabalhos saíram da mesma máquina.
    """
    caminho = os.path.join(saida or SAIDA, "instalacao.txt")
    try:
        with open(caminho, encoding="utf-8") as f:
            valor = f.read().strip()
        if valor:
            return valor
    except OSError:
        pass
    valor = uuid.uuid4().hex[:12]
    try:
        os.makedirs(os.path.dirname(caminho), exist_ok=True)
        with open(caminho, "w", encoding="utf-8") as f:
            f.write(valor + "\n")
    except OSError:
        pass
    return valor


def ler_aluno(saida=None):
    try:
        with open(_arquivo_aluno(saida), encoding="utf-8") as f:
            d = json.load(f)
        if d.get("nome"):
            return d
    except (OSError, ValueError):
        pass
    return None


def gravar_aluno(nome, ra, saida=None):
    nome = " ".join((nome or "").split())
    ra = (ra or "").strip()
    if not nome:
        raise SystemExit("erro: o nome não pode ficar vazio")
    d = {"nome": nome, "ra": ra, "instalacao": instalacao(saida), "desde": _agora()}
    os.makedirs(saida or SAIDA, exist_ok=True)
    with open(_arquivo_aluno(saida), "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2)
        f.write("\n")
    return d


def _conferencia(corpo):
    bruto = json.dumps(corpo, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return "sha256:" + hashlib.sha256(bruto.encode("utf-8")).hexdigest()


def gravar(lab, titulo, itens, saida=None):
    """itens: lista de (estado, o_que, observado). estado é 'ok' ou 'falha'."""
    saida = saida or SAIDA
    aluno = ler_aluno(saida) or {"nome": "", "ra": "", "instalacao": instalacao(saida)}
    verificacoes = [{"estado": e, "o_que": q, "observado": o} for e, q, o in itens]
    falhas = sum(1 for v in verificacoes if v["estado"] != "ok")
    corpo = {
        "formato": FORMATO,
        "lab": str(lab),
        "titulo": titulo,
        "aluno": aluno,
        "maquina": {"host": socket.gethostname(), "porta": int(os.environ.get("GIA_PORT", "18080"))},
        "quando": _agora(),
        "ok": falhas == 0,
        "resumo": "%d de %d verificações passaram" % (len(verificacoes) - falhas, len(verificacoes)),
        "verificacoes": verificacoes,
    }
    corpo["conferencia"] = _conferencia(corpo)
    os.makedirs(saida, exist_ok=True)
    destino = caminho_evidencia(lab, saida)
    with open(destino, "w", encoding="utf-8") as f:
        json.dump(corpo, f, ensure_ascii=False, indent=2)
        f.write("\n")
    return corpo, destino


def _itens_do_arquivo(caminho):
    itens = []
    if not caminho or not os.path.exists(caminho):
        return itens
    with io.open(caminho, encoding="utf-8") as f:
        for linha in f:
            linha = linha.rstrip("\n")
            if not linha.strip():
                continue
            partes = linha.split("\t")
            estado = partes[0].strip() if partes else "falha"
            o_que = partes[1] if len(partes) > 1 else ""
            observado = partes[2] if len(partes) > 2 else ""
            itens.append(("ok" if estado == "ok" else "falha", o_que, observado))
    return itens


def _cmd_aluno(a):
    d = gravar_aluno(a.nome, a.ra, a.saida)
    print("identificação gravada: %s%s · instalação %s"
          % (d["nome"], (" · RA " + d["ra"]) if d["ra"] else "", d["instalacao"]))


def _cmd_gravar(a):
    itens = _itens_do_arquivo(a.itens)
    if not itens:
        raise SystemExit("erro: nenhuma verificação para gravar (arquivo de itens vazio)")
    corpo, destino = gravar(a.lab, a.titulo, itens, a.saida)
    sem_aluno = not corpo["aluno"].get("nome")
    print()
    print("evidência do Lab %s: %s" % (corpo["lab"], corpo["resumo"]))
    print("  arquivo: %s" % destino)
    if sem_aluno:
        print("  ATENÇÃO: sem identificação. Rode antes:")
        print('    docker compose exec toolbox python3 /work/scripts/evidencia.py aluno --nome "Seu Nome" --ra 000000')
    else:
        print("  aluno:   %s%s" % (corpo["aluno"]["nome"],
                                   (" · RA " + corpo["aluno"]["ra"]) if corpo["aluno"].get("ra") else ""))
    print("  entregue este arquivo no Moodle. Ele também aparece para baixar no painel.")
    return 0 if corpo["ok"] else 1


def _cmd_mostrar(a):
    try:
        with open(caminho_evidencia(a.lab, a.saida), encoding="utf-8") as f:
            print(f.read(), end="")
    except OSError:
        raise SystemExit("ainda não existe evidência para o Lab %s" % a.lab)


def main(argv=None):
    p = argparse.ArgumentParser(description="evidência de laboratório do GIA")
    p.add_argument("--saida", default=None, help="diretório de saída (padrão: %s)" % SAIDA)
    sub = p.add_subparsers(dest="cmd", required=True)

    pa = sub.add_parser("aluno", help="grava nome e RA de quem está fazendo os labs")
    pa.add_argument("--nome", required=True)
    pa.add_argument("--ra", default="")
    pa.set_defaults(func=_cmd_aluno)

    pg = sub.add_parser("gravar", help="grava a evidência de um lab")
    pg.add_argument("--lab", required=True)
    pg.add_argument("--titulo", required=True)
    pg.add_argument("--itens", required=True, help="arquivo TSV: estado<TAB>o_que<TAB>observado")
    pg.set_defaults(func=_cmd_gravar)

    pm = sub.add_parser("mostrar", help="imprime a evidência de um lab")
    pm.add_argument("--lab", required=True)
    pm.set_defaults(func=_cmd_mostrar)

    a = p.parse_args(argv)
    return a.func(a) or 0


if __name__ == "__main__":
    sys.exit(main())
