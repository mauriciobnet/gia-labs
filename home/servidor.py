# -*- coding: utf-8 -*-
"""Painel do laboratório GIA.

Serve três coisas na porta 8000 (o Traefik publica isto na raiz do host):
  /              a página do painel
  /api/estado    o JSON com o estado de cada serviço
  /tutorial/...  o tutorial visual, quando a pasta está montada

Só biblioteca padrão. Nenhuma fonte ou script externo: a página tem que abrir
com a máquina do aluno sem internet.
"""
import json
import mimetypes
import os
import posixpath
import sys
import threading
import time
import unicodedata
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import estado  # noqa: E402

RAIZ = os.path.dirname(os.path.abspath(__file__))
TUTORIAL = os.environ.get("GIA_TUTORIAL", "/tutorial")
PORTA_HTTP = 8000

ICONE = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">'
    '<rect width="32" height="32" rx="7" fill="#FFD342"/>'
    '<path d="M16 7a5 5 0 0 1 5 5v2h1.5a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 22.5 25h-13A1.5 1.5 0 0 1 8 23.5v-8A1.5 1.5 0 0 1 9.5 14H11v-2a5 5 0 0 1 5-5zm0 3a2 2 0 0 0-2 2v2h4v-2a2 2 0 0 0-2-2z" fill="#1E1E1E"/>'
    "</svg>"
)


class Painel(BaseHTTPRequestHandler):
    server_version = "painel-gia"

    def log_message(self, formato, *args):  # silencia o log de acesso
        pass

    def _envia(self, corpo, tipo="text/html; charset=utf-8", codigo=200, cache=False):
        if isinstance(corpo, str):
            corpo = corpo.encode("utf-8")
        self.send_response(codigo)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(corpo)))
        self.send_header("Cache-Control", "max-age=3600" if cache else "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(corpo)

    def _arquivo(self, caminho, cache=True):
        tipo = mimetypes.guess_type(caminho)[0] or "application/octet-stream"
        if tipo.startswith("text/") or tipo in ("application/javascript", "application/json"):
            tipo += "; charset=utf-8"
        try:
            with open(caminho, "rb") as f:
                self._envia(f.read(), tipo, cache=cache)
        except OSError:
            self._envia("não encontrado", "text/plain; charset=utf-8", 404)

    def _evidencia(self, ident):
        """Entrega o arquivo de evidência de um lab, pronto para subir no Moodle.

        O nome do arquivo já sai com o nome do aluno porque é isso que salva o
        professor na hora de corrigir trinta entregas chamadas evidencia-lab3.json.
        """
        if not ident or not all(c.isalnum() for c in ident):
            return self._envia("identificador inválido", "text/plain; charset=utf-8", 400)
        caminho = os.path.join(estado.CARIMBOS, "evidencia-lab%s.json" % ident)
        try:
            with open(caminho, "rb") as f:
                corpo = f.read()
        except OSError:
            return self._envia("esta etapa ainda não gerou evidência", "text/plain; charset=utf-8", 404)

        nome = "evidencia-lab%s" % ident
        aluno = estado._aluno()
        if aluno and aluno.get("nome"):
            # Cabeçalho HTTP não carrega acento: "Maurício" viraria byte inválido e o
            # navegador salvaria o arquivo com nome quebrado. Dobramos para ASCII.
            simples = unicodedata.normalize("NFKD", aluno["nome"]).encode("ascii", "ignore").decode()
            pedaco = "".join(c if c.isalnum() else "-" for c in simples.lower())
            pedaco = "-".join(p for p in pedaco.split("-") if p)
            if pedaco:
                nome += "-" + pedaco
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(corpo)))
        self.send_header("Content-Disposition", 'attachment; filename="%s.json"' % nome)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(corpo)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        rota = self.path.split("?", 1)[0]

        if rota in ("/", "/index.html"):
            return self._arquivo(os.path.join(RAIZ, "pagina.html"), cache=False)

        if rota == "/api/estado":
            return self._envia(json.dumps(estado.instantaneo(), ensure_ascii=False),
                               "application/json; charset=utf-8")

        if rota == "/favicon.svg":
            return self._envia(ICONE, "image/svg+xml", cache=True)

        if rota.startswith("/evidencia/"):
            return self._evidencia(rota[len("/evidencia/"):])

        if rota.startswith("/tutorial"):
            relativo = posixpath.normpath(rota[len("/tutorial"):]).lstrip("/")
            destino = os.path.normpath(os.path.join(TUTORIAL, relativo))
            if destino != TUTORIAL and not destino.startswith(TUTORIAL + os.sep):  # barra travessia de diretório
                return self._envia("caminho inválido", "text/plain; charset=utf-8", 403)
            if os.path.isdir(destino):
                destino = os.path.join(destino, "index.html")
            if not os.path.exists(destino):
                return self._envia(
                    "O tutorial visual não está nesta pasta. Gere com tests/tutorial.js "
                    "ou abra os PDFs em stack/tutorial/.",
                    "text/plain; charset=utf-8", 404)
            return self._arquivo(destino)

        # qualquer outra coisa volta para o painel (o Traefik manda hosts sem rota para cá)
        self.send_response(302)
        self.send_header("Location", "/")
        self.end_headers()


def vigia_codigo():
    """Sai do processo quando estado.py ou servidor.py mudam no disco.

    O Python importa o módulo uma vez e guarda em memória, então editar estado.py
    não muda nada até reiniciar. Como o serviço tem restart automático no compose,
    sair é a forma mais simples e previsível de recarregar: o container volta em
    um segundo já com o código novo. A página em si é lida a cada requisição e não
    precisa disto.
    """
    alvos = [os.path.join(RAIZ, n) for n in ("estado.py", "servidor.py")]
    marcas = {a: os.path.getmtime(a) for a in alvos if os.path.exists(a)}
    while True:
        time.sleep(2)
        for a, antes in list(marcas.items()):
            try:
                agora = os.path.getmtime(a)
            except OSError:
                continue
            if agora != antes:
                print("%s mudou: reiniciando o painel" % os.path.basename(a), flush=True)
                os._exit(0)


def main():
    threading.Thread(target=vigia_codigo, daemon=True).start()
    estado.comecar()
    servidor = ThreadingHTTPServer(("0.0.0.0", PORTA_HTTP), Painel)
    print("painel do laboratório GIA em http://localhost:%d (porta interna %d)"
          % (estado.PORTA, PORTA_HTTP), flush=True)
    servidor.serve_forever()


if __name__ == "__main__":
    main()
