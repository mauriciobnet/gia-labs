# -*- coding: utf-8 -*-
"""Confere se o grafana/ldap.toml está estruturado como o Grafana espera.

Este verificador existe por causa de um erro real, cometido na montagem deste
laboratório. As três chaves de busca de grupos tinham sido escritas depois do
cabeçalho [servers.attributes]. Em TOML isso não é erro de sintaxe: as chaves
simplesmente passam a pertencer à tabela attributes. O arquivo carrega, o Grafana
não reclama, a pessoa consegue entrar, e o papel dela vem errado. Nenhuma mensagem
em lugar nenhum aponta a causa.

É o tipo de falha que custa uma tarde, então vale trinta linhas de verificação.

Uso:  python3 scripts/conferir-grafana-ldap.py [caminho]
"""
import os
import sys

try:
    import tomllib
except ModuleNotFoundError:
    sys.exit("precisa de Python 3.11 ou mais novo (ou rode dentro do toolbox)")

NO_SERVIDOR = ["host", "port", "bind_dn", "bind_password",
               "search_filter", "search_base_dns",
               "group_search_base_dns", "group_search_filter",
               "group_search_filter_user_attribute"]

SO_EM_ATTRIBUTES = {"name", "surname", "username", "email", "member_of"}


def main(caminho):
    if not os.path.isfile(caminho):
        sys.exit("não encontrei %s" % caminho)
    with open(caminho, "rb") as f:
        try:
            dados = tomllib.load(f)
        except tomllib.TOMLDecodeError as e:
            sys.exit("TOML inválido: %s" % e)

    servidores = dados.get("servers") or []
    if not servidores:
        sys.exit("nenhum [[servers]] no arquivo")

    problemas = []
    for i, s in enumerate(servidores):
        etiqueta = "servers[%d]" % i
        atributos = s.get("attributes", {})

        # o erro clássico: chave de servidor que caiu dentro de [servers.attributes]
        for chave in atributos:
            if chave not in SO_EM_ATTRIBUTES:
                problemas.append(
                    "%s: a chave '%s' está dentro de [servers.attributes]. "
                    "Mova para antes desse cabeçalho." % (etiqueta, chave))

        for chave in NO_SERVIDOR:
            if chave not in s:
                problemas.append("%s: falta a chave '%s' no nível do servidor" % (etiqueta, chave))

        # se o filtro usa o DN, o Grafana precisa saber disso pela outra chave
        filtro = s.get("group_search_filter", "")
        atributo = s.get("group_search_filter_user_attribute", "")
        if "member=%s" in filtro.replace(" ", "") and atributo.lower() != "dn":
            problemas.append(
                "%s: o filtro procura por member=%%s, que compara DN completo, mas "
                "group_search_filter_user_attribute está como '%s'. Deveria ser 'dn'."
                % (etiqueta, atributo))

        mapeamentos = s.get("group_mappings") or []
        if not mapeamentos:
            problemas.append("%s: nenhum [[servers.group_mappings]]" % etiqueta)
        elif mapeamentos[-1].get("group_dn") != "*":
            problemas.append(
                "%s: o mapeamento curinga '*' não é o último. Como o Grafana usa o "
                "primeiro que casar, um '*' no meio engole os mapeamentos seguintes."
                % etiqueta)

    if problemas:
        print("%d problema(s) em %s:\n" % (len(problemas), caminho))
        for p in problemas:
            print("  x " + p)
        sys.exit(1)

    s = servidores[0]
    print("ok: %s" % caminho)
    print("  servidor ............. %s:%s" % (s["host"], s["port"]))
    print("  pessoas em ........... %s" % ", ".join(s["search_base_dns"]))
    print("  grupos em ............ %s" % ", ".join(s["group_search_base_dns"]))
    print("  filtro de grupos ..... %s" % s["group_search_filter"])
    print("  %%s vira ............. %s" % s["group_search_filter_user_attribute"])
    for m in s["group_mappings"]:
        print("  %-45s -> %s" % (m["group_dn"], m["org_role"]))


if __name__ == "__main__":
    raiz = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(raiz, "grafana", "ldap.toml"))
