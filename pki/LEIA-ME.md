# PKI do laboratório (Lab 4)

Esta pasta começa vazia. O `scripts/lab4-ldap-tls.sh` a preenche com:

    pki/ca/acme-ca.crt     CA raiz da ACME Ensino (a que as aplicações passam a confiar)
    pki/ca/acme-ca.key     chave privada da CA
    pki/ldap/ldap.crt      certificado do servidor de diretório, assinado pela CA
    pki/ldap/ldap.key      chave privada do servidor
    pki/ldap/acme-ca.crt   cópia da CA, porque o slapd precisa dela no mesmo lugar

## Por que uma CA própria e não Let's Encrypt

A Let's Encrypt só emite certificado para nome de domínio público que ela consiga
validar. Os nomes desta stack (`openldap`, `*.localhost`, `ldap.acme.edu.br`) são
internos: não existem no DNS público e, no caso de `.localhost`, as regras do
CA/Browser Forum proíbem qualquer CA pública de emitir para eles. Para diretório
interno a resposta certa não é "arrumar um certificado público", é **ter uma CA
própria** e distribuir a raiz dela para quem precisa confiar. É o que uma ACME de
verdade faria, e é o que este lab faz.

O certificado autoassinado (sem CA) seria o caminho mais curto, e é justamente o que
o lab **não** faz: com ele cada aplicação teria que ser configurada para ignorar a
verificação (`ssl_skip_verify = true`, `TLS_REQCERT never`), o que devolve o problema
pela janela, porque um cliente que não verifica aceita qualquer servidor no meio do
caminho.

## Atenção às chaves privadas

Os arquivos `.key` aqui ficam legíveis por todo mundo (644) porque o slapd dentro do
container precisa lê-los e este é um laboratório descartável. Em produção a chave do
servidor é 600, pertence ao usuário do serviço, e a chave da CA nem fica na mesma
máquina. Se alguma dessas chaves vazar, quem a pegou emite certificado em nome do seu
diretório: apague a pasta e gere tudo de novo.
