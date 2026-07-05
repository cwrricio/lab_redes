# Roteiro de Apresentação — Laboratório SSH

> **Objetivo:** demonstrar SSH do zero ao vivo: subir o servidor, acessar por
> senha, acessar por chave pública, explorar a máquina, transferir arquivos e
> analisar o tráfego no Wireshark.
>
> **Duração estimada:** 15-20 minutos de demonstração ao vivo.
> **O que você vai usar:** dois terminais + Wireshark aberto.

---

## ANTES DE COMEÇAR (preparação, 2 min antes)

**Terminal 1 — onde você vai rodar os comandos:**
```bash
cd ~/Documents/lab_trab2_redes
make up          # sobe o servidor SSH (e os outros)
docker compose ps   # confirmar: lab-ssh "Up"
```

**Terminal 2 — logs do servidor em tempo real:**
```bash
docker logs -f lab-ssh
```
> Deixe este terminal visível no canto: a plateia verá o servidor registrando
> cada conexão enquanto você acessa.

**Wireshark — aberto e pronto:**
- Abra o Wireshark
- Interface: **Loopback** (ou `lo`)
- Filtro de captura: `port 2222`
- **NÃO inicie ainda** — você vai iniciar durante a apresentação

---

## PASSO 0 — Abertura (fale, não mexa no terminal ainda)

> *"SSH, Secure Shell, é o protocolo que substituiu o Telnet nos anos 90. O
> Telnet mandava tudo em texto claro — login, senha, comandos — qualquer um
> na rede lia. O SSH cifra o canal inteiro. Vou mostrar isso funcionando ao
> vivo: vou subir um servidor, entrar nele de dois jeitos diferentes, explorar
> o que tem dentro, mandar um arquivo, e no Wireshark vocês vão ver que, ao
> contrário do FTP que mostrei antes, o SSH não deixa ler nada."*

---

## PASSO 1 — O servidor subindo (Terminal 1)

**Execute:**
```bash
docker compose up -d ssh
```

**Mostre:**
```bash
docker compose ps ssh
```

Saída esperada:
```
NAME      SERVICE   STATUS    PORTS
lab-ssh   ssh       running   0.0.0.0:2222->22/tcp
```

**Fale:**
> *"O servidor SSH está rodando dentro de um container Debian. Porta 22 é a
> porta padrão do SSH — well-known, reservada pelo IANA. No host eu mapeio
> como 2222 para não conflitar com meu próprio SSH. É o mesmo que você faria
> num servidor real com firewall."*

**Mostre os logs (Terminal 2):**
```
Server listening on 0.0.0.0 port 22.
```

---

## PASSO 2 — A identidade do servidor (quem é essa máquina?)

**Execute:**
```bash
ssh-keygen -lf client/keys/host/ssh_host_ed25519_key.pub
```

**Fale:**
> *"Antes de eu provar quem sou, o SERVIDOR prova quem ele é. Ele tem um par
> de chaves — as 'chaves de host'. Essa fingerprint aqui é o SHA256 da chave
> pública dele. Quando você conecta pela primeira vez aparece a pergunta
> 'Are you sure you want to continue connecting?' — você está sendo perguntado:
> você confia nessa fingerprint? O cliente grava a resposta em
> ~/.ssh/known_hosts. Se amanhã um impostor se passar por este servidor com
> outra chave, o SSH bloqueia com 'REMOTE HOST IDENTIFICATION HAS CHANGED'.
> Isso é proteção contra man-in-the-middle."*

**Mostre:**
```bash
cat client/keys/known_hosts
```

---

## PASSO 3 — Iniciar captura no Wireshark

**No Wireshark:**
1. Selecione a interface **Loopback** (lo)
2. Filtro de captura: `tcp port 2222`
3. Clique em **Start**

**Fale:**
> *"Vou iniciar a captura para mostrar o que trafega durante a conexão SSH."*

---

## PASSO 4 — ACESSO POR SENHA: `labuser@127.0.0.1`

**Execute (e espere a senha ser pedida — DIGITE: `labpass`):**
```bash
ssh -p 2222 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=client/keys/known_hosts \
  -o IdentitiesOnly=yes \
  -o PubkeyAuthentication=no \
  -o PreferredAuthentications=password \
  labuser@127.0.0.1
```

**Dentro do servidor, execute estes comandos um a um:**
```bash
hostname
whoami
id
uname -a
cat /etc/os-release | head -4
ps aux | grep sshd
ls -la ~/.ssh/
exit
```

**Enquanto executa, fale:**
> *"Estou dentro do servidor. O hostname é 'ssh-server', o usuário é
> 'labuser'. Veja o sshd rodando, veja o ~/.ssh com as chaves autorizadas.
> A senha que digitei — 'labpass' — foi pedida, mas NÃO viajou em texto
> claro: ela foi transmitida dentro do canal já cifrado. Diferente do FTP,
> onde a senha aparece em claro no Wireshark."*

**Olhe os logs (Terminal 2):**
```
Accepted password for labuser from 172.30.0.1 port XXXXX ssh2
```

---

## PASSO 5 — Analisar o Wireshark (sessão de senha)

**No Wireshark, pause a captura e mostre:**

### 5.1 — O handshake TCP (pacotes 1, 2, 3)
```
SYN →
← SYN-ACK
ACK →
```
> *"Primeiro o TCP de sempre: three-way handshake abrindo a conexão."*

### 5.2 — O banner SSH (visível em claro!)
Procure o pacote com `Protocol: SSHv2`. Clique nele.
```
SSH Protocol: SSH-2.0-OpenSSH_9.2p1 Debian-2+deb12u5
```
> *"Aqui a informação vaza: a versão do servidor e do cliente são visíveis.
> Um atacante saberia exatamente qual OpenSSH está rodando — daí a importância
> de manter o servidor atualizado."*

### 5.3 — Negociação de algoritmos (Key Exchange Init)
Expanda o pacote `Key Exchange Init` no Wireshark:
```
SSH: Protocol: Key Exchange Init
  kex_algorithms: curve25519-sha256,...
  server_host_key_algorithms: ssh-ed25519,...
  encryption_algorithms: chacha20-poly1305,...
  mac_algorithms: hmac-sha2-512-etm,...
```
> *"Esses pacotes de negociação de algoritmos também são visíveis — é antes
> do canal ser cifrado. O cliente e o servidor concordam em curve25519 para
> troca de chaves e ChaCha20-Poly1305 para cifrar."*

### 5.4 — Depois da negociação: tudo cifrado
Pacotes seguintes mostram apenas `Encrypted Packet`:
```
SSH: Encrypted Packet (len=xxx)
```
> *"A partir daqui: ruído. Você vê o tamanho dos pacotes e o timing, mas
> nada do conteúdo. A senha, os comandos, as respostas — tudo cifrado.
> Compara com o FTP onde você lê USER e PASS em texto claro."*

**Filtro útil no Wireshark para focar nos dados:**
```
tcp.port==2222 && ssh
```

---

## PASSO 6 — O par de chaves: teoria antes de praticar

**Execute (sem conectar ainda — só mostre as chaves):**
```bash
ls -la client/keys/lab_ed25519 client/keys/lab_ed25519.pub
```

**Fale enquanto mostra:**
> *"Autenticação por senha depende de um segredo que você envia. Chave pública
> funciona diferente: você tem um PAR. A chave privada fica só na sua máquina
> — nunca sai daqui. A pública vai para o servidor."*

```bash
cat client/keys/lab_ed25519.pub
```

> *"Essa é a pública — você pode distribuir à vontade. No login, o servidor
> manda um DESAFIO aleatório, você ASSINA com a privada, o servidor VERIFICA
> com a pública. Se bater, você entrou. Nenhum segredo viajou pela rede."*

**Mostre onde a pública está no servidor:**
```bash
docker compose exec ssh cat /home/labuser/.ssh/authorized_keys
```

---

## PASSO 7 — ACESSO POR CHAVE PÚBLICA (reinicie a captura no Wireshark)

**No Wireshark: Capture → Restart**

**Execute:**
```bash
ssh -F client/ssh_config lab
```

**Você entra SEM digitar senha. Dentro do servidor:**
```bash
hostname
whoami
echo "entrei com chave publica, sem senha"
exit
```

**Olhe os logs (Terminal 2):**
```
Accepted publickey for labuser from 172.30.0.1 port XXXXX ssh2: ED25519 SHA256:xxx
```

**Fale:**
> *"Entrei sem digitar senha. O log do servidor confirma: 'Accepted publickey'.
> Veja a fingerprint da chave que foi aceita — é a mesma que geramos."*

---

## PASSO 8 — Permissões: por que o SSH é exigente

**Execute:**
```bash
ssh -F client/ssh_config lab \
  'stat -c "%a  %U:%G  %n" ~/.ssh ~/.ssh/authorized_keys'
```

Saída:
```
700  labuser:labuser  /home/labuser/.ssh
600  labuser:labuser  /home/labuser/.ssh/authorized_keys
```

**Fale:**
> *"700 no diretório: só o dono entra. 600 no arquivo: só o dono lê e escreve.
> Se eu botar 777, o sshd RECUSA a chave — para que nenhum outro usuário
> do sistema consiga editar quem pode entrar como você."*

**Demonstre quebrando e consertando:**
```bash
ssh -F client/ssh_config lab \
  'chmod 777 ~/.ssh/authorized_keys && ls -la ~/.ssh/'
```

Tente conectar — vai falhar com chave (cai para senha):
```bash
ssh -F client/ssh_config lab 'echo teste'
```

Conserte:
```bash
ssh -p 2222 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=client/keys/known_hosts \
  -o IdentitiesOnly=yes \
  -o PubkeyAuthentication=no \
  -o PreferredAuthentications=password \
  labuser@127.0.0.1 'chmod 600 ~/.ssh/authorized_keys && echo "permissao restaurada"'
```

---

## PASSO 9 — TRANSFERÊNCIA DE ARQUIVO: SCP

**Crie o arquivo para enviar:**
```bash
cat > /tmp/relatorio.txt << 'EOF'
Relatório de Laboratório SSH
=============================
Protocolo : SSH (Secure Shell)
RFC       : 4251, 4252, 4253, 4254
Porta     : 22 (well-known)
Gerado em : $(date)

Autenticações demonstradas:
  1. Senha (password) — funcional, vulnerável a brute force
  2. Chave pública (publickey) — sem senha na rede, recomendada

Criptografia negociada:
  KEX    : curve25519-sha256
  Cifra  : chacha20-poly1305@openssh.com
  MAC    : hmac-sha2-512-etm@openssh.com
EOF
cat /tmp/relatorio.txt
```

**Envie para o servidor (LOCAL → REMOTO):**
```bash
scp -P 2222 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=client/keys/known_hosts \
  -o IdentitiesOnly=yes \
  -i client/keys/lab_ed25519 \
  /tmp/relatorio.txt labuser@127.0.0.1:/home/labuser/relatorio.txt
```

**Confirme que chegou:**
```bash
ssh -F client/ssh_config lab 'ls -lh ~/relatorio.txt && cat ~/relatorio.txt'
```

**Baixe do servidor (REMOTO → LOCAL):**
```bash
scp -P 2222 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=client/keys/known_hosts \
  -o IdentitiesOnly=yes \
  -i client/keys/lab_ed25519 \
  labuser@127.0.0.1:/home/labuser/relatorio.txt /tmp/relatorio_baixado.txt

cat /tmp/relatorio_baixado.txt
```

**Fale:**
> *"SCP roda dentro do SSH — mesma porta 22, mesma criptografia. Não preciso
> abrir nova porta no firewall. Compara: FTP precisa de 21 + uma faixa passiva
> (21100-21110 no nosso lab). SSH resolve tudo na 22."*

---

## PASSO 10 — Wireshark: compare SCP com FTP

**No Wireshark, pare a captura. Mostre:**

1. **Todos pacotes SSH:** `tcp.port==2222`
   - Selecione um `Encrypted Packet` durante o SCP
   - `SSH Protocol: Encrypted Packet (len=1412)` — conteúdo: ruído

2. **Abra uma captura de FTP se tiver** (ou descreva):
   - FTP: você vê `RETR relatorio.txt`, vê os bytes do arquivo em claro
   - SSH/SCP: você vê apenas tamanho e timing

**Fale:**
> *"A mesma operação de transferência de arquivo. No FTP o Wireshark lê o nome
> do arquivo, o conteúdo, a senha — tudo. No SCP você vê pacotes chegando,
> vê que houve transferência pelo tamanho, mas não consegue ler nada."*

---

## PASSO 11 — Sessão interativa SFTP (bônus se tiver tempo)

```bash
sftp -F client/ssh_config lab
```

Dentro do SFTP:
```
sftp> pwd
sftp> ls -la
sftp> put /tmp/relatorio.txt outro_arquivo.txt
sftp> ls -la
sftp> get outro_arquivo.txt /tmp/sftp_download.txt
sftp> bye
```

**Fale:**
> *"SFTP é uma interface tipo FTP, mas que roda 100% dentro do SSH. Mesma
> porta 22. Muita gente confunde SFTP com FTPS: FTPS é o FTP antigo
> embrulhado em TLS, com dois canais, mais complexo. SFTP é subsistema do
> SSH, um canal só."*

---

## PASSO 12 — Encerramento

**Execute:**
```bash
docker compose logs lab-ssh | grep -E "Accepted|Failed|Connection" | tail -20
```

**Fale:**
> *"Olha o log do servidor: cada conexão registrada, qual método de
> autenticação foi aceito, qual chave. Em produção você monitora esse log
> com fail2ban — se um IP tenta 5 vezes e erra, é banido automaticamente.
> Resumo: o SSH resolve o acesso remoto com criptografia do canal (ninguém
> lê), autenticação por chave (sem segredo na rede), e controle fino
> por permissões de arquivo. É o protocolo certo para administração remota."*

---

## REFERÊNCIA RÁPIDA — Comandos do laboratório

```bash
# ── Subir / parar ─────────────────────────────────────────────────────────
make up                         # sobe tudo
make down                       # para tudo
docker logs -f lab-ssh          # logs em tempo real

# ── Conectar (com o ssh_config do laboratório) ────────────────────────────
ssh -F client/ssh_config lab              # login por CHAVE
sftp -F client/ssh_config lab             # SFTP por chave

# ── Conectar (modo "manual" sem ssh_config) ───────────────────────────────
ssh -p 2222 \
  -o IdentitiesOnly=yes \
  -o PubkeyAuthentication=no \
  -o PreferredAuthentications=password \
  labuser@127.0.0.1                       # pede a senha: labpass

ssh -p 2222 -i client/keys/lab_ed25519 \
  -o IdentitiesOnly=yes \
  labuser@127.0.0.1                       # login por chave, sem config

# ── SCP ───────────────────────────────────────────────────────────────────
# Local → Remoto
scp -P 2222 -i client/keys/lab_ed25519 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=client/keys/known_hosts \
  -o IdentitiesOnly=yes \
  /arquivo/local labuser@127.0.0.1:/destino/remoto/

# Remoto → Local
scp -P 2222 -i client/keys/lab_ed25519 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=client/keys/known_hosts \
  -o IdentitiesOnly=yes \
  labuser@127.0.0.1:/arquivo/remoto /destino/local/

# ── Wireshark ─────────────────────────────────────────────────────────────
# Interface: Loopback (lo)
# Filtro de captura: tcp port 2222
# Filtro de exibição: tcp.port==2222 && ssh
# Para ver só os Encrypted Packets: tcp.port==2222 && ssh.direction==client-to-server
```

---

## GUIA WIRESHARK — O que procurar

| Pacote | O que contém | Visível? |
|---|---|---|
| TCP SYN/SYN-ACK/ACK | three-way handshake | ✅ Sim |
| SSH Banner | versão do cliente e servidor | ✅ **Sim** (vaza!) |
| Key Exchange Init | lista de algoritmos suportados | ✅ **Sim** (vaza!) |
| Key Exchange Reply | chave pública do servidor (Diffie-Hellman) | ✅ Sim |
| New Keys | sinal de que a cifra começa agora | ✅ Sim |
| `Encrypted Packet` | autenticação, comandos, arquivos | ❌ **Não — cifrado** |

### O que o atacante consegue saber pelo Wireshark:
- Que você está usando SSH
- A versão do servidor e do cliente (banner)
- Quais algoritmos foram negociados
- O tamanho e timing dos pacotes (análise de tráfego)

### O que o atacante NÃO consegue saber:
- A senha digitada
- A chave usada para autenticar
- Os comandos executados
- O conteúdo dos arquivos transferidos

### Filtros úteis:
```
tcp.port==2222                        # todo tráfego SSH do lab
tcp.port==2222 && ssh                 # só pacotes SSH (ignora ACKs)
tcp.port==2222 && tcp.flags.syn==1    # ver o handshake TCP
frame contains "SSH-2.0"              # o banner do servidor
```

---

## PERGUNTAS PROVÁVEIS DA BANCA

**"A senha no SSH vai em claro?"**
> Não. A senha viaja DENTRO do canal já cifrado (diferente do Telnet). Mas o
> método é fraco por ser um segredo compartilhado sujeito a força bruta.

**"O que acontece se a chave de host mudar?"**
> O SSH bloqueia a conexão com "REMOTE HOST IDENTIFICATION HAS CHANGED" e
> mostra onde está a linha conflitante no known_hosts. Você tem que verificar
> se é uma mudança legítima (reinstalou o servidor) ou um ataque MITM.

**"Como o login por chave funciona sem senha ir pela rede?"**
> Desafio-resposta assimétrico: o servidor gera um número aleatório, o cliente
> assina com a chave privada, o servidor verifica com a pública. Se bater, a
> identidade está provada sem o segredo ter viajado.

**"Qual a diferença de ed25519 e RSA?"**
> ed25519 usa curva elíptica — chave menor (256 bits ≈ RSA 3072 bits em
> segurança), mais rápido para gerar e verificar assinaturas, resistente a
> algumas falhas de implementação do RSA. Recomendado para novos sistemas.

**"O que é ssh-agent?"**
> Processo que guarda a chave privada decifrada em memória para você não
> precisar digitar a passphrase a cada conexão. Potencialmente perigoso em
> servidores compartilhados (outro root poderia usar o socket do agente).

**"Qual a diferença de SFTP e FTPS?"**
> SFTP é um subsistema do SSH — um protocolo completamente diferente do FTP,
> porta 22, um único canal cifrado. FTPS é o FTP tradicional (porta 21 + canal
> de dados) embrulhado em TLS. Nomes parecidos, arquiteturas diferentes.

**"Por que PermitRootLogin no é importante?"**
> Bots de brute force sempre tentam root — é o usuário mais poderoso. Bloqueando
> root, o atacante primeiro precisa descobrir o nome de um usuário válido.