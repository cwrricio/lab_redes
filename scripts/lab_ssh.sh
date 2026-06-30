#!/usr/bin/env bash
# Laboratório SSH — perspectiva dupla: sysadmin (dentro do servidor) + cliente (de fora).
# Cada passo mostra o que está acontecendo dos dois lados.
#
# Em modo interativo (padrão): mostra o comando, espera ENTER, executa.
# Em modo AUTO (AUTO=1): roda tudo sem parar (para make demo / capture).
cd "$(dirname "$0")/.."
source scripts/lib.sh

CFG="client/ssh_config"
KEY="client/keys/lab_ed25519"

# ---------------------------------------------------------------------------
banner "LABORATÓRIO SSH — Secure Shell, passo a passo"
explain "SSH (Secure Shell, RFC 4251-4254) — criado em 1995 para substituir
Telnet e rlogin, que mandavam login, senha e comandos em TEXTO CLARO pela rede.
Neste laboratório você vai subir um servidor, entrar nele por senha, entrar
por chave pública, explorar a máquina de dentro e transferir arquivos.
Perspectiva dupla: o que acontece do lado do SERVIDOR e do lado do CLIENTE."

# ---------------------------------------------------------------------------
step "O CENÁRIO" "que máquina é essa, onde está, como acessamos"

explain "Nosso 'servidor remoto' é um container Docker com Debian e OpenSSH.
Ele representa qualquer servidor Linux que você acessaria via SSH.

  Dentro do container:  endereço 172.30.0.10,  porta 22 (padrão SSH)
  Do seu terminal:      endereço 127.0.0.1,     porta 2222 (mapeada pelo Docker)

Estamos na MESMA MÁQUINA física (loopback 127.0.0.1). Em produção, esse
endereço seria o IP público do servidor — poderia estar em qualquer lugar do
mundo. O protocolo e os comandos seriam os mesmos; só o endereço muda."

run "docker compose up -d ssh"
run "docker compose ps ssh"
run "docker compose port ssh 22"
info "A porta 22 do container aparece mapeada como 2222 no seu host."
kv "Dentro do container"  "172.30.0.10:22"
kv "Do seu terminal"      "127.0.0.1:2222  (Docker NAT)"
kv "Em produção seria"    "203.0.113.42:22  (IP real do servidor)"
pause

# ---------------------------------------------------------------------------
step "LADO DO SERVIDOR — configuração antes do primeiro acesso" "visão do sysadmin"

explain "Antes de qualquer cliente se conectar, vamos entrar DIRETO no container
como se fôssemos o sysadmin que configurou o servidor. Isso mostra o estado
inicial da máquina: o daemon sshd rodando, a configuração, o usuário criado."

info "O sshd está escutando na porta 22 dentro do container:"
run "docker compose exec ssh ss -ltnp | grep sshd"

echo
info "Usuário 'labuser' que usaremos para o lab:"
run "docker compose exec ssh id labuser"
run "docker compose exec ssh ls -la /home/labuser/"

echo
info "Configurações principais do sshd (sem comentários):"
run "docker compose exec ssh grep -vE '^#|^$' /etc/ssh/sshd_config"
pause

# ---------------------------------------------------------------------------
step "IDENTIDADE DO SERVIDOR" "como o cliente sabe que está falando com a máquina certa"

explain "Quando você se conecta a um servidor SSH pela primeira vez, ele apresenta
a 'chave de host': um par de chaves RSA/ed25519 que IDENTIFICA AQUELE SERVIDOR.
O cliente salva a fingerprint (hash SHA256 da chave pública) no arquivo
~/.ssh/known_hosts. Se amanhã um impostor se passar por esse servidor, a
fingerprint será diferente e o SSH BLOQUEIA a conexão com o aviso:
'REMOTE HOST IDENTIFICATION HAS CHANGED'.
Isso protege contra ataques man-in-the-middle (MITM)."

echo
info "LADO DO SERVIDOR — a chave de host que ele vai apresentar:"
run "docker compose exec ssh ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub"

echo
info "LADO DO CLIENTE — o arquivo known_hosts do laboratório:"
run "cat client/keys/known_hosts"
note "No lab usamos chaves de host FIXAS (não regeneradas a cada rebuild),
para que o known_hosts continue válido mesmo após 'make clean && make up'."
pause

# ---------------------------------------------------------------------------
step "O ARQUIVO ssh_config" "como evitar digitar -p, -i, -o na linha de comando"

explain "O arquivo ~/.ssh/config (ou qualquer arquivo passado com -F) define
APELIDOS para conexões SSH. Em vez de lembrar o endereço, porta e opções de
cada servidor, você escreve uma vez no config e depois digita só 'ssh servidor'.

No laboratório geramos um config em client/ssh_config com dois apelidos:
  lab       — conecta por CHAVE PÚBLICA (sem digitar senha)
  lab-pass  — conecta por SENHA (desativa a chave de propósito)"

run "cat $CFG"

echo
info "Com esse config, substituímos comandos longos por apelidos curtos:"
kv "ssh -F $CFG lab"       "login por chave pública"
kv "ssh -F $CFG lab-pass"  "login por senha"
kv "scp -F $CFG"           "cópia segura usando o mesmo config"
note "Em produção você colocaria esse conteúdo em ~/.ssh/config e poderia
digitar apenas 'ssh lab' sem o -F."
pause

# ---------------------------------------------------------------------------
step "ACESSO 1 — login com USUÁRIO + SENHA" "método mais simples, menos seguro"

explain "Primeiro acesso: entramos como 'labuser' com a senha 'labpass'.
A senha NÃO vai em texto claro — ela trafega dentro do canal já cifrado
(diferente do que acontecia com Telnet). Mesmo assim, o método tem fraquezas:
bots na Internet ficam 24h tentando senhas em servidores com porta 22 aberta."

echo
info "Vamos usar o apelido 'lab-pass' do ssh_config:"
echo
info "Digite a senha quando aparecer o prompt:  labpass"
echo

if [ "$AUTO" = "1" ]; then
  warn "Modo AUTO: login por senha é interativo — execute 'make ssh' para este passo."
else
  run "ssh -F $CFG lab-pass 'echo; echo \"=== DENTRO DO SERVIDOR ===\"; hostname; whoami; id; uptime; echo'"
fi

echo
warn "Funciona — mas qualquer um que descubra 'labpass' entra. Bots de brute
force tentam milhares de senhas por hora. Em produção, desative completamente
a autenticação por senha (PasswordAuthentication no no sshd_config)."
pause

# ---------------------------------------------------------------------------
step "LADO DO SERVIDOR — o que o sshd registrou desse acesso" "perspectiva do servidor"

explain "Enquanto você estava conectado, o sshd registrou tudo em log.
Vamos ver do lado do servidor o que foi gravado para aquele acesso por senha."

run "docker compose logs ssh --tail=20"
note "Nas linhas de log você vê: o IP de origem, o usuário, o método de
autenticação usado (password), a fingerprint da chave de host apresentada."
pause

# ---------------------------------------------------------------------------
step "O PAR DE CHAVES" "criptografia assimétrica — o método certo"

explain "Em vez de um segredo compartilhado (senha), usamos um PAR DE CHAVES:
  CHAVE PRIVADA — fica só com você, nunca sai da sua máquina
  CHAVE PÚBLICA — vai para o servidor (em ~/.ssh/authorized_keys)

No momento do login:
  1. O servidor manda um DESAFIO aleatório
  2. Você ASSINA o desafio com a chave privada
  3. O servidor VERIFICA a assinatura com a chave pública
  4. Nenhum segredo trafega pela rede — imune a brute force e sniffing"

echo
info "LADO DO CLIENTE — as chaves geradas para o laboratório:"
run "ls -la $KEY $KEY.pub"
run "cat $KEY.pub"

echo
info "LADO DO SERVIDOR — a mesma chave pública instalada em authorized_keys:"
run "docker compose exec ssh cat /home/labuser/.ssh/authorized_keys"
note "São idênticas. O servidor autoriza quem tiver a chave privada correspondente."
pause

# ---------------------------------------------------------------------------
step "ACESSO 2 — login com CHAVE PÚBLICA" "sem digitar senha"

explain "Agora vamos entrar usando o par de chaves. O apelido 'lab' no ssh_config
já aponta para a chave privada correta. Nenhuma senha será pedida."

run "ssh -F $CFG lab 'echo; echo \"=== DENTRO DO SERVIDOR ===\"; hostname; whoami; id; date; echo'"
ok "Entrou sem digitar senha! O servidor verificou a assinatura criptográfica."

echo
info "LADO DO SERVIDOR — veja a diferença no log (método publickey vs password):"
run "docker compose logs ssh --tail=10"
pause

# ---------------------------------------------------------------------------
step "EXPLORANDO A MÁQUINA" "comandos de administração remota"

explain "Uma vez autenticado, você pode rodar qualquer comando no servidor.
A sessão SSH é um terminal normal, só que na máquina remota. Vamos explorar
como um sysadmin faria em um acesso real de administração."

info "Sistema operacional e hostname:"
run "ssh -F $CFG lab 'hostname && cat /etc/os-release | grep -E \"^(NAME|VERSION)=\"'"

echo
info "Processos rodando no servidor:"
run "ssh -F $CFG lab 'ps aux | head -10'"

echo
info "Portas em escuta (o sshd na porta 22):"
run "ssh -F $CFG lab 'ss -ltnp'"

echo
info "Diretório home do labuser no servidor:"
run "ssh -F $CFG lab 'ls -la /home/labuser/'"
pause

# ---------------------------------------------------------------------------
step "PERMISSÕES" "por que o SSH recusa chaves com permissão errada"

explain "O sshd é rígido com permissões de arquivo. Se ~/.ssh ou authorized_keys
tiver permissão aberta demais (outros usuários podem ler/escrever), o sshd
RECUSA autenticar — qualquer outro usuário no servidor poderia adicionar
a própria chave ao seu authorized_keys e entrar como você."

echo
info "LADO DO SERVIDOR — permissões corretas (700 e 600):"
run "ssh -F $CFG lab 'stat -c \"%a  %U:%G  %n\" ~/.ssh ~/.ssh/authorized_keys'"
kv "700 = drwx------" "só o dono entra no diretório"
kv "600 = -rw-------" "só o dono lê e escreve o arquivo"

echo
info "LADO DO CLIENTE — a chave privada também precisa ser 600:"
run "stat -c '%a  %n' $KEY"

echo
info "Experimento: abrindo demais e restaurando:"
run "ssh -F $CFG lab 'chmod 777 ~/.ssh/authorized_keys && stat -c \"%a %n\" ~/.ssh/authorized_keys'"
warn "Com 777, o sshd bloquearia a autenticação por chave."
run "ssh -F $CFG lab 'chmod 600 ~/.ssh/authorized_keys && stat -c \"%a %n\" ~/.ssh/authorized_keys'"
ok "Restaurado para 600 — autenticação por chave volta a funcionar."
pause

# ---------------------------------------------------------------------------
step "TRANSFERÊNCIA DE ARQUIVO — SCP (Secure Copy)" "arquivo dentro do canal SSH"

explain "SCP e SFTP rodam DENTRO do canal SSH: mesma porta 22, mesma criptografia.
Não é o FTP (que vemos trafegar em claro mais tarde). Você transfere arquivos
com segurança sem abrir nova porta no firewall.

Usamos 'scp -F client/ssh_config', que aproveita o mesmo config e o apelido 'lab'."

echo "Relatorio do laboratorio de SSH" > /tmp/lab_relatorio.txt
echo "Aluno: labuser"                 >> /tmp/lab_relatorio.txt
echo "Data: $(date)"                  >> /tmp/lab_relatorio.txt
echo "Protocolo: SSH (RFC 4251-4254)" >> /tmp/lab_relatorio.txt

info "Arquivo criado localmente:"
run "cat /tmp/lab_relatorio.txt"

echo
info "ENVIANDO: local para o servidor:"
run "scp -F $CFG /tmp/lab_relatorio.txt lab:/home/labuser/relatorio.txt"

echo
info "LADO DO SERVIDOR — verificando que o arquivo chegou:"
run "ssh -F $CFG lab 'ls -lh ~/relatorio.txt && echo && cat ~/relatorio.txt'"
pause

# ---------------------------------------------------------------------------
step "BAIXAR ARQUIVO DO SERVIDOR" "SCP no sentido inverso"

info "LADO DO SERVIDOR — criando um arquivo no servidor:"
run "ssh -F $CFG lab 'echo \"gerado em \$(hostname) em \$(date)\" > ~/gerado_no_servidor.txt'"

echo
info "BAIXANDO: servidor para o local:"
run "scp -F $CFG lab:/home/labuser/gerado_no_servidor.txt /tmp/gerado_do_lab.txt"

run "cat /tmp/gerado_do_lab.txt"
ok "Arquivo baixado do servidor. Sem FTP, sem porta extra, tudo dentro do SSH."

echo
note "Alternativa interativa: sftp -F $CFG lab
Dentro do sftp: put arquivo.txt, get arquivo.txt, ls, rm — interface igual ao FTP,
mas todo o tráfego vai cifrado dentro do SSH."
pause

# ---------------------------------------------------------------------------
step "O HANDSHAKE DO SSH" "o que é negociado em milissegundos"

explain "Antes de qualquer dado, SSH negocia três camadas em milissegundos:"
kv "1. Troca de chaves (KEX)"  "curve25519 — Diffie-Hellman elíptico: cliente e
servidor chegam ao mesmo segredo compartilhado SEM transmiti-lo"
kv "2. Cifra simétrica"        "ChaCha20-Poly1305 — CONFIDENCIALIDADE: tudo cifrado"
kv "3. MAC / AEAD"             "integridade: detecta se um byte foi alterado no meio"

echo
info "Algoritmos configurados no servidor (sshd_config):"
run "docker compose exec ssh grep -E 'KexAlgorithms|Ciphers|MACs|LogLevel' /etc/ssh/sshd_config | grep -v '^#'"
pause

# ---------------------------------------------------------------------------
step "HARDENING — SSH em produção" "além do laboratório"

explain "O lab mantém PasswordAuthentication yes para demonstrar os dois métodos.
Em produção, o servidor deve ser endurecido:"

kv "PasswordAuthentication no"  "só chave pública; senha desativada"
kv "PermitRootLogin no"         "nunca root diretamente; use sudo"
kv "MaxAuthTries 3"             "bloqueia brute force (padrão lab: 6 para a demo)"
kv "AllowUsers labuser"         "whitelist: só usuários listados podem logar"
kv "Port 2222"                  "muda a porta padrão: reduz scans automatizados"
kv "fail2ban"                   "bane IPs após N tentativas falhas"
kv "Firewall (ufw/iptables)"    "só a porta SSH aberta; preferencialmente por IP fixo"
kv "Chave com passphrase"       "se a chave privada for roubada, ainda está protegida"

# ---------------------------------------------------------------------------
done_banner "Laboratório SSH concluído."
echo
info "Para continuar explorando:"
kv "Sessão interativa (chave):"      "ssh -F $CFG lab"
kv "Sessão interativa (senha):"      "ssh -F $CFG lab-pass     # senha: labpass"
kv "SFTP interativo:"                "sftp -F $CFG lab"
kv "Logs do servidor em tempo real:" "docker logs -f lab-ssh"
kv "Wireshark SSH:"                  "tcp.port==2222  (veja roteiro.md para análise)"
