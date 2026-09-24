#!/usr/bin/env python3
"""Liga (ou desliga) o StartTLS na configuração LDAP do Grafana. Lab 4.

Mexe só em três chaves do bloco [[servers]] e não reescreve o arquivo inteiro, porque o
ldap.toml tem comentários que explicam a armadilha de ordem do TOML e perdê-los seria
perder a aula junto. Guarda uma cópia do estado do Lab 3 em ldap-sem-tls.toml na
primeira vez, para dar para voltar e repetir a captura.

Uso (dentro do toolbox):
    python3 /work/scripts/ligar-tls-grafana.py /work/grafana/ldap.toml
    python3 /work/scripts/ligar-tls-grafana.py /work/grafana/ldap.toml --desligar
"""
import os
import re
import sys

CA = "/etc/grafana/pki/acme-ca.crt"

# As três chaves têm que ficar ANTES do primeiro cabeçalho [servers.*], senão viram chave
# de outra tabela e o Grafana ignora em silêncio. É o mesmo erro que já custou caro aqui
# com as group_search_*, por isso o limite é calculado e respeitado em vez de suposto.
CHAVES = ("start_tls", "ssl_skip_verify", "root_ca_cert")


def limite_do_bloco(linhas):
    """Índice da primeira linha que abre uma tabela depois de [[servers]]."""
    inicio = None
    for i, l in enumerate(linhas):
        if l.strip() == "[[servers]]":
            inicio = i
            break
    if inicio is None:
        raise SystemExit("ldap.toml sem bloco [[servers]]: arquivo inesperado, nada foi mudado")
    for i in range(inicio + 1, len(linhas)):
        if re.match(r"\s*\[", linhas[i]):
            return inicio, i
    return inicio, len(linhas)


def ajustar(linhas, chave, valor, inicio, fim):
    """Troca a chave dentro do bloco, ou devolve a linha para ser inserida."""
    alvo = re.compile(r"^\s*%s\s*=" % re.escape(chave))
    for i in range(inicio, fim):
        if alvo.match(linhas[i]):
            linhas[i] = "%s = %s" % (chave, valor)
            return None
    return "%s = %s" % (chave, valor)


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    caminho = sys.argv[1]
    ligar = "--desligar" not in sys.argv[2:]
    with open(caminho, encoding="utf-8") as f:
        linhas = f.read().split("\n")

    copia = os.path.join(os.path.dirname(caminho) or ".", "ldap-sem-tls.toml")
    if ligar and not os.path.exists(copia):
        with open(copia, "w", encoding="utf-8") as f:
            f.write("\n".join(linhas))
        os.chmod(copia, 0o644)
        print("estado do Lab 3 guardado em %s" % copia)

    valores = {
        "start_tls": "true" if ligar else "false",
        "ssl_skip_verify": "false" if ligar else "true",
        "root_ca_cert": '"%s"' % CA if ligar else '""',
    }
    inicio, fim = limite_do_bloco(linhas)
    faltando = []
    for chave in CHAVES:
        nova = ajustar(linhas, chave, valores[chave], inicio, fim)
        if nova:
            faltando.append(nova)
    if faltando:
        linhas[fim:fim] = faltando + [""]

    with open(caminho, "w", encoding="utf-8") as f:
        f.write("\n".join(linhas))
    # O Grafana roda com uid 472 e não lê arquivo 600. Já quebrou este lab uma vez.
    os.chmod(caminho, 0o644)

    inicio, fim = limite_do_bloco(linhas)
    print("bloco [[servers]] depois da mudança:")
    for l in linhas[inicio:fim]:
        if l.strip() and not l.strip().startswith("#"):
            print("   " + l)
    return 0


if __name__ == "__main__":
    sys.exit(main())
