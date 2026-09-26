# Instalação do ambiente

Este guia leva você do computador em branco até a stack do laboratório rodando. Ele é para ser feito
**antes da aula**: o primeiro download passa de dois gigabytes, e ninguém quer gastar a manhã de
sábado esperando barra de progresso.

Você vai instalar **uma coisa só**: o Docker. Nada de OpenLDAP, Keycloak, GLPI ou Grafana no seu
sistema. Tudo isso vive dentro de containers, sobe com um comando e some com outro, sem deixar nada
para trás na sua máquina.

Se travar em qualquer passo, leve o erro para o fórum do Moodle com o texto da mensagem e o seu
sistema operacional. Metade dos problemas de instalação se resolve em dois minutos quando alguém vê
a mensagem inteira.

## O que a máquina precisa ter

- **8 GB de RAM**, com pelo menos **4 GB disponíveis para o Docker**.
- Uns **5 GB de disco livre** para as imagens.
- Chrome ou Firefox. O Safari não serve: ele não abre os endereços `*.localhost` do laboratório.
- Conexão para o primeiro download. Depois disso, os laboratórios rodam offline.

---

## Windows 10 e 11

No Windows, o Docker roda em cima do **WSL 2**, que é o subsistema Linux da Microsoft. São dois
passos: ligar o WSL 2 e instalar o Docker Desktop.

### 1. Conferir a versão do Windows

A documentação do Docker Desktop pede **Windows 10 versão 22H2** (build 19045) ou **Windows 11
versão 23H2** (build 22631) ou superior, nas edições Enterprise, Pro ou Education. Para ver a sua,
aperte a tecla Windows, digite `winver` e dê Enter.

Se a sua edição for **Home**, a instalação costuma funcionar do mesmo jeito, mas não é o que a
documentação oficial garante. Avise no fórum antes da aula, para não descobrir isso no sábado.

Ainda é preciso que a **virtualização esteja habilitada na BIOS ou UEFI**. Para conferir: abra o
Gerenciador de Tarefas, aba Desempenho, CPU, e procure por "Virtualização: Habilitado". Se estiver
desabilitada, é preciso ligar na BIOS, e aí vale pedir ajuda a quem cuida da sua máquina.

### 2. Instalar o WSL 2

Abra o **PowerShell como administrador** (botão direito no menu Iniciar, "Terminal (Administrador)")
e rode:

```powershell
wsl --install
```

O comando liga os recursos do Windows necessários e instala o **Ubuntu** por padrão. Depois dele,
**reinicie o computador**: a documentação da Microsoft pede isso explicitamente.

Se o comando responder mostrando a ajuda em vez de instalar, o WSL já está instalado na sua máquina.
Nesse caso, confira a versão com `wsl --version` (o Docker Desktop pede WSL 2.1.5 ou posterior) e
atualize com `wsl --update`.

Depois de reiniciar, abra o Ubuntu pelo menu Iniciar. Na primeira vez ele pede um nome de usuário e
uma senha para o Linux. Essa senha é só do Ubuntu, não tem nada a ver com a sua senha do Windows, e
você vai precisar dela: anote.

### 3. Instalar o Docker Desktop

Baixe em <https://www.docker.com/products/docker-desktop/> e instale. Na instalação, deixe marcada a
opção de usar o **WSL 2**. Ao abrir pela primeira vez, ele pode pedir para você aceitar os termos.

### 4. Dar memória ao Docker (a pegadinha do Windows)

No Windows com WSL 2, **memória e CPU não se ajustam nas telas do Docker Desktop**. Os campos que
existem em Settings, Resources valem para macOS, Linux e para o backend Hyper-V, e não para o WSL 2.
Se você procurar por um controle deslizante de memória ali, não vai achar, e não é defeito.

O ajuste é feito num arquivo de texto. Abra o PowerShell e rode `notepad "$env:UserProfile\.wslconfig"`
(ele pergunta se quer criar o arquivo; diga que sim), escreva isto e salve:

```ini
[wsl2]
memory=4GB
processors=2
```

Depois, ainda no PowerShell, aplique com:

```powershell
wsl --shutdown
```

e abra o Ubuntu de novo. Se a sua máquina tem bastante memória, pode subir para `6GB` ou `8GB`, e o
laboratório fica mais confortável.

### 5. Onde guardar os arquivos do curso

**Dentro do Linux, não em `C:`.** Quando você abrir o Ubuntu, já estará na pasta certa (`~`, que é a
sua pasta pessoal no Linux). É ali que você vai clonar o repositório.

A razão não é preciosismo. A documentação do Docker diz que os containers Linux só recebem eventos
de alteração de arquivo quando eles estão no sistema de arquivos do Linux, e que o desempenho de
arquivos montados a partir de `/mnt/c` é muito pior. A Microsoft dá a mesma orientação: guarde os
arquivos no mesmo sistema operacional das ferramentas que vão usá-los.

Na prática: **todos os comandos do curso são digitados no terminal do Ubuntu**, não no PowerShell nem
no Prompt de Comando.

Para ter o git dentro do Ubuntu, rode lá:

```bash
sudo apt update && sudo apt install -y git
```

---

## macOS

### 1. Conferir a versão

O Docker Desktop tem suporte na versão atual do macOS e nas **duas versões principais anteriores**.
A documentação não fixa um número, então a regra é essa: se o seu macOS está três versões atrás,
atualize antes. Menu Apple, "Sobre este Mac", mostra a sua.

São necessários pelo menos 4 GB de RAM, e para este curso a recomendação continua sendo 8 GB.

### 2. Instalar

Baixe em <https://www.docker.com/products/docker-desktop/>, escolhendo a versão certa:
**Apple Silicon** (Macs com chip M1, M2, M3 e seguintes) ou **Intel**. Arraste para Aplicativos e
abra.

Em Macs Apple Silicon, o Docker recomenda instalar o **Rosetta 2**, que não é mais estritamente
obrigatório, mas ainda é exigido por algumas ferramentas de linha de comando. Se quiser instalar
antes e evitar surpresa:

```bash
softwareupdate --install-rosetta
```

### 3. Dar memória ao Docker

No macOS os controles existem na interface: **Settings, Resources, Advanced**, onde ficam o limite de
CPU, o de memória (por padrão, metade da memória do seu Mac), o swap e o limite de disco. Confira se
a memória está em 4 GB ou mais.

---

## Linux

No Linux **não é preciso instalar o Docker Desktop**. O caminho é o Docker Engine com o plugin do
Compose, que é o que o curso usa.

### 1. Instalar pelo repositório oficial

A documentação recomenda instalar pelo repositório da própria Docker, e não pelo pacote da
distribuição. Se você já tem o pacote `docker.io` ou similar instalado, desinstale antes: a
documentação avisa que ele conflita com os pacotes oficiais.

Siga a página da sua distribuição, que traz os comandos exatos e atualizados:

- Ubuntu: <https://docs.docker.com/engine/install/ubuntu/>
- Debian: <https://docs.docker.com/engine/install/debian/>
- Fedora: <https://docs.docker.com/engine/install/fedora/>

Em todas elas, os pacotes a instalar são os mesmos:

```
docker-ce  docker-ce-cli  containerd.io  docker-buildx-plugin  docker-compose-plugin
```

O último é o que dá o comando `docker compose`. Sem ele, nada do curso funciona.

### 2. Usar o Docker sem sudo

```bash
sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker
```

Saia da sessão e entre de novo para a mudança valer em todos os terminais. Em máquina virtual, pode
ser preciso reiniciar.

Vale saber o que você está fazendo: a documentação do Docker é explícita em dizer que **o grupo
`docker` concede privilégios equivalentes a root**. Numa máquina de laboratório isso é aceitável; num
servidor de produção, é uma decisão que se toma com cuidado. Como o curso é de segurança, fica o
registro.

---

## Conferindo que deu certo

Abra o terminal (no Windows, o do **Ubuntu**) e rode os três:

```bash
docker version
docker compose version
docker run --rm hello-world
```

O primeiro mostra cliente e servidor. O segundo tem que responder com uma versão: é o plugin do
Compose. O terceiro baixa uma imagem de teste, roda e imprime uma mensagem dizendo que a instalação
está funcionando.

Uma observação que evita confusão: o comando do curso é **`docker compose`**, com espaço. O antigo
`docker-compose`, com hífen, é a versão 1, escrita em Python, que foi substituída e não é mais
mantida. Se algum tutorial da internet mandar usar o hífen, é tutorial velho.

---

## Baixando o curso e subindo a stack

```bash
git clone https://github.com/mauriciobnet/gia-labs.git
cd gia-labs

docker compose up -d --build --wait
docker compose run --rm check
```

O `up` na primeira vez baixa as imagens e leva alguns minutos. O `check` é a verificação do ambiente,
e é o **Lab 1** do curso: ele confere arquitetura, memória, roteamento, LDAP e Keycloak, e termina
dizendo se está tudo de pé.

Depois, abra o painel em <http://localhost:18080>. Se ele aparecer com os serviços em verde, você
está pronto para o primeiro encontro.

---

## Quando alguma coisa dá errado

**O `up` reclama que a porta 18080 está em uso.** Alguma outra coisa na sua máquina já a ocupa. Copie
`env-exemplo.txt` para `.env`, troque o valor de `GIA_PORT`, e suba de novo com `docker compose down`
seguido de `docker compose up -d`. Lembre que as URLs passam a usar a porta nova.

**O `check` reclama de memória.** No Windows, é o `.wslconfig` do passo 4. No macOS, é Settings,
Resources, Advanced. No Linux, é a memória da própria máquina.

**No Windows, o Docker Desktop diz que o WSL 2 não está instalado ou está desatualizado.** Rode
`wsl --update` no PowerShell como administrador e reinicie.

**`docker: permission denied` no Linux.** Faltou o passo de adicionar seu usuário ao grupo `docker`,
ou falta sair e entrar de novo na sessão.

**Algum serviço demora para ficar pronto.** É normal: o Keycloak leva de 30 a 90 segundos na primeira
subida, o LAM uns 40 segundos, e o GLPI cerca de um minuto se instalando sozinho. Espere e recarregue
o painel.

**O painel abre, mas os links do LAM, do GLPI ou do Grafana não.** Veja qual navegador você está
usando. Chrome e Firefox resolvem sozinhos qualquer nome terminado em `.localhost`; o Safari, não.
No Mac, abra o painel no Chrome ou no Firefox.

**`curl: could not resolve host` ao rodar um comando do roteiro.** Os endereços `*.localhost` do
laboratório são resolvidos pelo **navegador**, e o terminal do Windows e do macOS não os resolve. Por
isso os comandos dos roteiros rodam dentro do container `toolbox`:

```bash
docker compose exec toolbox bash
```

**Quero recomeçar do zero.** `docker compose --profile lab3 --profile tools down -v` apaga tudo,
inclusive o diretório LDAP e o banco do GLPI, e você refaz os laboratórios do começo.

---

## Fontes

Este guia foi escrito a partir da documentação oficial, consultada em 24 de setembro de 2026:

- Docker Desktop no Windows: <https://docs.docker.com/desktop/setup/install/windows-install/>
- Docker Desktop no macOS: <https://docs.docker.com/desktop/setup/install/mac-install/>
- Docker Desktop e WSL 2, boas práticas: <https://docs.docker.com/desktop/features/wsl/best-practices/>
- Configurações do Docker Desktop: <https://docs.docker.com/desktop/settings-and-maintenance/settings/>
- Instalação do Docker Engine: <https://docs.docker.com/engine/install/>
- Passos pós-instalação no Linux: <https://docs.docker.com/engine/install/linux-postinstall/>
- Plugin Compose no Linux: <https://docs.docker.com/compose/install/linux/>
- História do Compose (v1 e v2): <https://docs.docker.com/compose/intro/history/>
- Instalação do WSL: <https://learn.microsoft.com/en-us/windows/wsl/install>
- Configuração do WSL (`.wslconfig`): <https://learn.microsoft.com/en-us/windows/wsl/wsl-config>
- Ambiente de desenvolvimento no WSL: <https://learn.microsoft.com/en-us/windows/wsl/setup/environment>
