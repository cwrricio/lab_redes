# Laboratório de Serviços de Aplicação: FTP, SSH e SNTP

Trabalho 2 — Redes de Computadores.

Mini-laboratório, todo em containers, que sobe três serviços de aplicação
clássicos e demonstra, na prática, **transferência de arquivos (FTP)**,
**acesso remoto seguro (SSH)** e **consulta/sincronização de horário (SNTP)** —
incluindo captura e análise do tráfego no Wireshark.

```
                       Host (sua máquina)
   ┌───────────────────────────────────────────────────────────┐
   │  clientes: curl/FileZilla · ssh/scp · cliente SNTP (Python)│
   │        │ :21 + :21100-21110   │ :2222        │ :123/udp    │
   └────────┼──────────────────────┼──────────────┼─────────────┘
            │                      │              │
   ╔════════▼═════╗      ╔═════════▼════╗   ╔══════▼═══════╗   rede docker
   ║  lab-ftp     ║      ║   lab-ssh    ║   ║   lab-ntp    ║   "labnet"
   ║  vsftpd      ║      ║  OpenSSH     ║   ║   chrony     ║   172.30.0.0/24
   ║ 172.30.0.20  ║      ║ 172.30.0.10  ║   ║ 172.30.0.30  ║
   ╚══════════════╝      ╚══════════════╝   ╚══════════════╝
```

---

## 1. Pré-requisitos

| Ferramenta | Para quê | Observação |
|---|---|---|
| **Docker** + **Docker Compose** | subir os três servidores | `docker --version` |
| **uv** | rodar o cliente SNTP em Python | https://docs.astral.sh/uv/ |
| `ssh`, `scp` | demo SSH | já vêm no Linux/macOS |
| `curl` | demo FTP | já vem na maioria dos sistemas |
| `tcpdump` ou **Wireshark** | captura de tráfego | `sudo apt install tcpdump wireshark` |
| `sshpass` *(opcional)* | demo de login SSH por senha | `sudo apt install sshpass` |
| `lftp` / FileZilla *(opcional)* | clientes FTP alternativos | |

> Não é preciso instalar vsftpd, OpenSSH-server nem chrony no host: tudo roda
> dentro dos containers.

---

## 2. Subindo o laboratório (poucos comandos)

```bash
make up        # gera as chaves SSH, faz build e sobe os 3 containers
make demo      # roda as 3 demonstrações (SNTP, FTP, SSH) em sequência
make down      # derruba tudo
```

`make` sozinho lista todos os alvos disponíveis. Sem `make`? Os equivalentes:

```bash
bash scripts/gen_keys.sh            # chaves + ssh_config
docker compose up -d --build        # sobe os serviços
bash scripts/lab_sntp.sh            # laboratórios guiados (interativos)
bash scripts/lab_ftp.sh
bash scripts/lab_ssh.sh
docker compose down
```

Depois de `make up`, os serviços ficam acessíveis assim:

| Serviço | Endereço | Credenciais |
|---|---|---|
| **SSH**  | `ssh lab` | chave `client/keys/lab_ed25519` (ou `ssh lab-pass` → senha `labpass`) |
| **FTP**  | `127.0.0.1:21` (modo passivo) | usuário `ftpuser` / senha `ftppass` |
| **SNTP** | `127.0.0.1:123/udp` | — |

> **Por que só `ssh lab`?** O `gen_keys.sh` gera `client/ssh_config` (com porta,
> usuário, caminho da chave, `IdentitiesOnly yes` e o `known_hosts` do lab) e
> adiciona uma linha `Include` ao seu `~/.ssh/config`. Assim os apelidos `lab` e
> `lab-pass` funcionam de **qualquer pasta**, sem `-F`, `-p` nem `-o`. Some ao
> apagar essa linha do `~/.ssh/config` (backup em `~/.ssh/config.bak.lab`).

---

## 3. Os três laboratórios guiados (passo a passo)

Cada laboratório é **interativo**: mostra o comando, espera você apertar ENTER,
executa na frente da turma e explica o resultado. É a forma recomendada de
apresentar. Para uma passada rápida sem pausas, use `AUTO=1 make demo`.

### 3.1 SNTP — consulta de horário (`make sntp`)

Porta **123/UDP**. Percorre: por que UDP e não TCP; a hierarquia de **stratum**
(visível com `chronyc tracking`/`sources` dentro do servidor); o **pacote de 48
bytes** decodificado campo a campo pelo nosso cliente (`client/sntp_client.py`,
escrito do zero, só stdlib); os **quatro timestamps** e o cálculo de
**offset**/**delay**; e a **falta de autenticação** do protocolo (NTP spoofing).

- `offset = ((t2−t1) + (t3−t4)) / 2` — defasagem do relógio local
- `delay  = (t4−t1) − (t3−t2)` — atraso de ida e volta

onde t1=cliente envia, t2=servidor recebe, t3=servidor responde, t4=cliente
recebe. Esse algoritmo cancela o atraso da rede e dá precisão de milissegundos.

### 3.2 FTP — transferência de arquivos (`make ftp`)

Porta de **controle 21** + faixa de **dados 21100-21110**. Percorre: os **dois
canais** TCP e os modos **ativo vs passivo**; o diálogo do protocolo visto com
`curl -v` (códigos `220/331/230/227`…); **upload** (STOR), **listagem** e
**download** (RETR); **permissões e chroot** (o usuário fica preso no home,
`local_umask=022`); e o ponto crítico: **tudo em texto claro** (daí FTPS/SFTP).

Pelo FileZilla: `Host 127.0.0.1`, `Porta 21`, `ftpuser`/`ftppass`, modo passivo.

### 3.3 SSH — acesso remoto seguro (`make ssh`)

Porta **22 → 2222**. É o cenário pedido, passo a passo:
1. servidor e **porta** (port mapping do Docker);
2. **chave de host** e fingerprint (proteção contra *man-in-the-middle*);
3. **Cenário 1:** login por **usuário + senha** (`labpass`) — funciona, mas fraco;
4. **Cenário 2:** login por **chave pública** — por que é mais segura;
5. **permissões** exigidas pelo SSH (`~/.ssh` 700, `authorized_keys` 600);
6. **enviar um arquivo** para a máquina via **SCP** (e menção a SFTP);
7. a **criptografia** negociada no handshake (KEX, cifra, MAC) e *hardening*.

O login por senha é automatizado se houver `sshpass`; caso contrário, o lab
pede que você digite `labpass` (mais "manual" ainda, e ótimo para a aula).

---

## 4. Portas e permissões (referência rápida)

**Portas usadas no laboratório:**

| Serviço | Porta no container | Publicada no host | Transporte | Papel |
|---|---|---|---|---|
| SSH | 22 | **2222** | TCP | sessão + SCP/SFTP (canal único cifrado) |
| FTP (controle) | 21 | 21 | TCP | comandos `USER`/`PASS`/`RETR`/`STOR`… |
| FTP (dados) | 21100-21110 | 21100-21110 | TCP | conteúdo dos arquivos (modo passivo) |
| SNTP/NTP | 123 | 123 | **UDP** | consulta de horário |

21, 22 e 123 são **portas well-known** (0-1023), reservadas a serviços padrão.
Mapeamos 22→2222 no host só para não colidir com um `sshd` local — exemplo
concreto de *port mapping*. Veja ao vivo com `docker compose port ssh 22`.

**Permissões que aparecem nos labs:**

| Onde | Permissão | Por quê |
|---|---|---|
| `~/.ssh` (servidor) | `700` | só o dono entra; o sshd **recusa** se estiver frouxo |
| `~/.ssh/authorized_keys` | `600` | só o dono lê/escreve a lista de chaves confiáveis |
| chave privada (cliente) | `600` | o `ssh` se recusa a usar uma chave "exposta" |
| arquivos enviados por FTP | `644` | efeito do `local_umask=022` no vsftpd |
| home do FTP | **chroot** | o usuário fica preso ao próprio diretório (jaula) |

---

## 5. Captura e análise de tráfego (Wireshark)

```bash
make capture     # roda os 3 labs (AUTO) capturando em captures/lab_<data>.pcap
```

O script usa `tcpdump` na interface de loopback (`lo`, porque acessamos tudo
via `127.0.0.1`) e exige `sudo`. Depois, abra no Wireshark:

```bash
wireshark captures/lab_*.pcap
```

Filtros e o que observar:

| Filtro no Wireshark | O que você vê |
|---|---|
| `ntp` | pacote SNTP de 48 bytes; o Wireshark decodifica LI/VN/Mode, stratum e os timestamps |
| `ftp` | comandos em **texto claro** — dá para ler `USER ftpuser` e **`PASS ftppass`** |
| `ftp-data` | o conteúdo do arquivo transferido, também em claro |
| `tcp.port==2222` | o tráfego SSH: só o handshake é legível; o resto é **cifrado** |

Esse contraste é o ponto central da análise: **FTP e SNTP trafegam em claro;
SSH é cifrado**. (Veja "Conceitos" e "Limitações".)

> Sem `tcpdump`/`sudo`? Capture pela GUI do Wireshark na interface *Loopback*
> com o filtro de captura `port 21 or portrange 21100-21110 or port 2222 or port 123`.

---

## 6. Conceitos (teoria conectada à prática)

**Protocolo de aplicação.** Cada serviço fala um protocolo da camada de
aplicação sobre a camada de transporte: FTP e SSH sobre **TCP** (precisam de
entrega confiável e ordenada); SNTP sobre **UDP** (uma troca pergunta/resposta
curta, em que retransmitir seria pior que repetir a consulta).

**Servidor e porta.** Um servidor é um processo que *escuta* numa **porta
well-known**: FTP em **21**, SSH em **22**, NTP em **123**. A porta multiplexa
vários serviços num mesmo IP. No lab, mapeamos 22→**2222** no host só para não
colidir com um eventual `sshd` local — exemplo concreto de *port mapping*.

**Autenticação.** O lab mostra três formas:
- **FTP** — usuário+senha em **texto claro** (frágil; capturável no Wireshark).
- **SSH por senha** — a senha não vai em claro porque o **canal já está
  cifrado**, mas ainda é vulnerável a força bruta e *phishing*.
- **SSH por chave pública** — o cliente prova posse da **chave privada** sem
  enviá-la; o servidor confere contra a chave pública em `authorized_keys`.
  Mais forte e a base de automações sem senha.

**Chaves SSH (par assimétrico).** Há *dois* pares envolvidos, não confundir:
- **chave de host** (do servidor): identifica o servidor e protege contra
  *man-in-the-middle*. O cliente guarda a *fingerprint* em `~/.ssh/known_hosts`
  e reclama se ela mudar. No lab ela é **fixa** (gerada por `gen_keys.sh` e
  montada no container), então a fingerprint não muda a cada rebuild.
- **chave do usuário** (do cliente): autentica *você* no servidor.

**Segurança do canal SSH.** O handshake negocia: **troca de chaves**
(curve25519 — Diffie-Hellman de curva elíptica) para combinar um segredo sem
transmiti-lo; **cifra simétrica** (ChaCha20-Poly1305 / AES-GCM) para
**confidencialidade**; e **MAC**/AEAD para **integridade**. Tudo isso está
explicitado e comentado em `services/ssh/sshd_config`, junto de medidas de
*hardening* (`PermitRootLogin no`, `MaxAuthTries`, `LoginGraceTime`).

**Sincronização de tempo.** Relógios de computador derivam (*drift*). O NTP
corrige isso hierarquicamente por **stratum**: stratum 0 são as fontes de
referência (relógios atômicos, GPS); stratum 1 são os servidores ligados
diretamente a elas; e assim por diante. Nosso `chrony` se sincroniza com o
`pool.ntp.org` (vira stratum 2 ou 3, conforme a fonte) e *serve* a hora à rede
do lab. O **SNTP** é a
versão *simples* do NTP: mesmo formato de pacote, mas sem os algoritmos de
filtragem e disciplina do relógio — ótimo para *consultar* a hora, que é
exatamente o que nosso cliente faz.

---

## 7. Estrutura do projeto

```
.
├── docker-compose.yml         # orquestra os 3 serviços + rede labnet
├── Makefile                   # atalhos: up, ssh/ftp/sntp, demo, capture...
├── services/
│   ├── ssh/                   # Dockerfile + sshd_config + entrypoint
│   ├── ftp/                   # Dockerfile + vsftpd.conf + entrypoint + data/
│   └── ntp/                   # Dockerfile + chrony.conf
├── client/
│   ├── sntp_client.py         # cliente SNTP escrito do zero (RFC 4330)
│   ├── pyproject.toml         # projeto uv (sem dependências externas)
│   ├── ssh_config             # aliases 'lab' (chave) e 'lab-pass' (senha) [gerado]
│   └── keys/                  # chaves do cliente + host + known_hosts [gerado]
├── scripts/
│   ├── lib.sh                 # saída bonita (cores, caixas, run/step)
│   ├── gen_keys.sh            # chaves, host keys e ssh_config
│   ├── lab_{ssh,ftp,sntp}.sh  # laboratórios guiados interativos
│   └── capture.sh            # captura tcpdump das 3 demos
├── captures/                  # .pcap gerados (para o Wireshark)
└── roteiro.md                 # roteiro da APRESENTAÇÃO (1 seção por protocolo)
```

---

## 8. Limitações do experimento

Coisas que ficaram de fora **de propósito** ou por restrição de escopo — e que
valem como discussão:

1. **FTP em texto claro (sem FTPS).** Mantivemos FTP puro justamente para
   *capturar* a senha no Wireshark e mostrar o problema. Em produção usaria-se
   **FTPS** (`ssl_enable=YES` + certificado no vsftpd) ou, melhor ainda,
   **SFTP** — que não é FTP, e sim transferência sobre SSH (já disponível neste
   lab via `sftp lab`).
2. **Senhas fracas e fixas.** `labpass`/`ftppass` são didáticas. Real: senhas
   fortes, ou só chave, com `PasswordAuthentication no`.
3. **Sincronização vs. consulta de horário.** Nosso cliente SNTP **lê** a hora
   e calcula o offset, mas **não ajusta** o relógio do host (isso exigiria
   privilégio e poderia bagunçar a máquina). Ajuste real é função de um daemon
   como `chronyd`/`ntpd`. O próprio servidor roda com `-x` (não disciplina o
   relógio do container).
4. **Sem autenticação no NTP.** SNTP/NTP básico não autentica o servidor — daí
   ataques de *NTP spoofing*. Mitigações (NTS, `autokey`) ficaram fora.
5. **Tudo em loopback.** Acessamos os serviços por `127.0.0.1`, então a captura
   é em `lo` e o `pasv_address` é `127.0.0.1`. Para acesso de *outra* máquina,
   seria preciso ajustar `PASV_ADDRESS` para o IP real do host.
6. **Sem TLS/quotas/limites.** Não há *rate limiting*, *fail2ban*, quotas de
   disco no FTP nem *firewall* — itens de um deploy real, não de um lab mínimo.
7. **Dependência de internet para o stratum.** O `chrony` busca o
   `pool.ntp.org`. Offline, ele cai para `local stratum 10` (configurado), mas
   a hora servida é só a do relógio do container.
8. **Privilégios de container.** Demos `SYS_TIME` ao container NTP por
   completude conceitual, embora com `-x` ele não ajuste relógio nenhum.

---

## 9. Solução de problemas

| Sintoma | Causa provável / solução |
|---|---|
| `make up` falha em "port is already allocated" | já há algo na 21/123/2222. Pare o serviço local ou edite as portas no `docker-compose.yml`. |
| FTP conecta mas trava no `LIST`/download | modo ativo em vez de passivo, ou faixa `21100-21110` bloqueada. Use `curl --ftp-pasv` (já é o padrão do `lab_ftp.sh`). |
| SSH: `Too many authentication failures` | o `ssh-agent` ofereceu chaves demais. Use `ssh lab` (o config do lab já fixa `IdentitiesOnly yes`). |
| SSH: `REMOTE HOST IDENTIFICATION HAS CHANGED` | a chave de host mudou (recriou as chaves). Rode `bash scripts/gen_keys.sh` e `make up` de novo, ou apague a linha antiga do `client/keys/known_hosts`. |
| SNTP: `timeout` | o container `lab-ntp` ainda está sincronizando. Aguarde alguns segundos (`docker logs lab-ntp`) e repita. |
| `make capture` pede senha e nada acontece | `tcpdump` precisa de `sudo`. Rode num terminal interativo. |
