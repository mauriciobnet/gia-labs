# GIA: laboratórios da disciplina

Gerenciamento de Identidade e Acesso (GIA), Pós-Graduação EAD em Segurança Cibernética, CESC/UTFPR.
Prof. Maurício Barfknecht.

Este repositório traz a stack de laboratório da disciplina, com os **laboratórios 1 a 4**, que são
os do **Encontro 1**. A cada encontro o repositório cresce: você atualiza com `git pull` e os
laboratórios novos aparecem no painel, sem precisar apagar nada nem refazer o que já fez.

Tudo roda na sua máquina, em containers, com ferramentas open source. Nada é enviado para lugar
nenhum: as evidências que você entrega no Moodle são arquivos gerados aqui dentro.

## O que você precisa

> **Primeira vez?** O passo a passo da instalação, por sistema operacional, está em
> **[INSTALACAO.md](INSTALACAO.md)**. Faça antes da aula: o primeiro download passa de dois gigabytes.

- **Docker** com o plugin Compose v2 (Docker Desktop no Windows com WSL 2 ou no macOS; Docker Engine
  no Linux). Confira com `docker compose version`.
- **8 GB de RAM** na máquina, com pelo menos **4 GB alocados ao Docker**, e alguns GB de disco livre.
- Chrome ou Firefox (o Safari não abre os endereços `*.localhost` do laboratório).
- Nada mais. Não instale OpenLDAP, Keycloak nem nada disso no seu sistema: tudo vive nos containers.

## Começando

```bash
git clone https://github.com/mauriciobnet/gia-labs.git
cd gia-labs

docker compose up -d --build --wait     # primeira vez: baixa as imagens, leva alguns minutos
docker compose run --rm check           # verificação do ambiente (é o Lab 1)
```

Depois abra o **painel** em <http://localhost:18080>. Ele mostra o estado de cada serviço, em que
etapa você está, o comando de cada laboratório e o botão que baixa a evidência para entregar.

Antes de começar os laboratórios, registre seu nome e seu e-mail uma vez. Eles vão dentro de cada
evidência, e o e-mail tem que ser **o mesmo do seu cadastro no Moodle**, porque é por ele que a
entrega é conferida:

```bash
docker compose exec -T toolbox python3 /work/scripts/evidencia.py aluno --nome "Seu Nome" --email "seu.email@example.com"
```

## Os laboratórios deste pacote

Cada laboratório tem um **roteiro ilustrado** em `tutorial/`, com a captura de cada tela da execução
de referência. Abra pelo painel ou direto no arquivo: são páginas que funcionam sozinhas, sem rede.

### Lab 1: Preparar o ambiente

```bash
docker compose --profile tools run --rm check
```

Roteiro: [`tutorial/lab1/index.html`](tutorial/lab1/index.html)

### Lab 2: Ler o diretório

```bash
docker compose exec toolbox bash /work/scripts/lab2-leitura.sh
```

Roteiro: [`tutorial/lab2/index.html`](tutorial/lab2/index.html)

### Lab 3: O diretório visto pelas aplicações

```bash
docker compose --profile lab3 up -d --wait
docker compose exec toolbox bash /work/scripts/lab3-diretorio.sh
```

Roteiro: [`tutorial/lab3/index.html`](tutorial/lab3/index.html)

### Lab 4: O diretório para de falar em voz alta

```bash
docker compose --profile lab3 up -d --wait
docker compose exec toolbox bash /work/scripts/lab4-ldap-tls.sh
```

Roteiro: [`tutorial/lab4/index.html`](tutorial/lab4/index.html)

O roteiro é o guia de bancada. A teoria que explica cada passo está na apostila do encontro, no
Moodle.

## Entregando no Moodle

Todo laboratório termina gravando um arquivo `evidencia-labN.json` com o que foi verificado **na sua
máquina**: seu nome, seu e-mail, o identificador da sua instalação, os horários e o que cada teste
observou. Baixe pelo botão "evidência" da etapa no painel e suba na tarefa correspondente.

Dois arquivos iguais se denunciam sozinhos, então não adianta pedir o do colega. E se um laboratório
parar no meio, a evidência é gravada mesmo assim, marcada como interrompida: entregue assim e diga
onde travou, que é melhor do que não entregar.

## A cada encontro

```bash
git pull
docker compose up -d --build --wait
```

Os laboratórios novos aparecem no painel. O que você já fez continua feito: as evidências ficam num
volume do Docker, não no repositório.

## Quando alguma coisa dá errado

**A porta 18080 já está ocupada.** Copie `env-exemplo.txt` para `.env` e troque o `GIA_PORT`. Suba de
novo com `docker compose down && docker compose up -d`. Use a mesma porta nas URLs.

**`curl: could not resolve host` no seu terminal.** Normal. Os nomes `*.localhost` são resolvidos
pelo **navegador**, não pelo resolvedor do sistema no Windows e no macOS. Por isso todo comando dos
roteiros roda dentro do container `toolbox`:

```bash
docker compose exec toolbox bash
```

**O painel diz que um serviço não responde logo depois do `up`.** Alguns levam tempo para ficar
prontos: o Keycloak de 30 a 90 segundos na primeira subida, o LAM uns 40, o GLPI cerca de um minuto
enquanto se instala sozinho. Espere e recarregue.

**Quero recomeçar do zero.** `docker compose --profile lab3 down -v` apaga tudo, inclusive o
diretório e o banco do GLPI. Você perde o que fez nos laboratórios, e as evidências junto.

## Credenciais do cenário

São credenciais de laboratório, propositalmente fracas e públicas. Parte do exercício é reconhecer
tudo o que está errado nelas.

| Onde | Usuário | Senha |
|---|---|---|
| Pessoas da ACME | `ana.souza`, `bruno.lima` (grupo `ti`), `carla.dias` (grupo `professores`) | `Senha@123` |
| LDAP (administrador) | `cn=admin,dc=acme,dc=edu,dc=br` | `admin` |
| LDAP (configuração do servidor) | `cn=admin,cn=config` | `config` |
| LDAP Account Manager | `cn=admin` | `admin` |
| Keycloak | `admin` | `admin` |
| GLPI | `glpi` | `glpi` |
| Grafana | `admin` | `admin` |

## O que não está aqui

Os laboratórios dos encontros seguintes, que chegam pelo `git pull`. As apostilas e os slides ficam
no Moodle. E as ferramentas de manutenção da stack, que são do professor.
