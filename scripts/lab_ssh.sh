#!/usr/bin/env bash
# Laboratório SSH — o melhor laboratório de SSH do mundo.
# Passo a passo MANUAL: sobe o servidor, acessa por senha, acessa por chave,
# entra na máquina, envia arquivos, e explica cada detalhe do protocolo.
#
# Em modo interativo (padrão): mostra o comando, espera ENTER, executa.
# Em modo AUTO (AUTO=1): roda tudo sem parar (para make demo / capture).
cd "$(dirname "$0")/.."
source scripts/lib.sh

CFG="client/ssh_config"
KEY="client/keys/lab_ed25519"

# ---------------------------------------------------------------------------
banner "LABORATÓRIO SSH — Secure Shell, passo a passo"
explain "SSH (Secure Shell, RFC 4251-4254) foi criado em 1995 para substituir \
Telnet e rlogin, que mandavam tudo — login, senha, comandos — em TEXTO CLARO. \
Neste laboratório você vai: subir o servidor, acessar por senha, acessar por \
chave pública, explorar a máquina e enviar arquivos. Cada passo explica o que \
acontece embaixo dos panos."

# ---------------------------------------------------------------------------
step "Subindo o servidor SSH" "container Docker simulando uma máquina remota"
explain "Nosso 'servidor remoto' é um container Debian com OpenSSH rodando na \
porta 22. No host, publicamos como porta 2222 (para não colidir com sshd local). \
O servidor tem um usuário 'labuser' criado para o laboratório."
run "docker compose up -d ssh"
run "docker compose ps ssh"
run "docker compose port ssh 22"
kv "Dentro do container" "172.30.0.10:22"
kv "No seu terminal"     "127.0.0.1:2222"
note "Porta 22 é a porta WELL-KNOWN do SSH. Qualquer porta acima de 1024 seria \
possível; 22 é a padrão (RFC 4251). O mapeamento 22→2222 é NAT do Docker."
pause

# ---------------------------------------------------------------------------
step "Fingerprint do servidor: quem é essa máquina?" "proteção contra MITM"
explain "Antes de você se autenticar, o SERVIDOR prova quem ele é, com uma \
'chave de host'. O cliente salva a fingerprint (SHA256 da chave pública do \
servidor) em ~/.ssh/known_hosts. Se amanhã um IMPOSTOR se passar por este \
servidor, a fingerprint muda e o SSH BLOQUEIA a conexão com: \
'REMOTE HOST IDENTIFICATION HAS CHANGED'. Isso é proteção contra \
ataques man-in-the-middle (MITM)."
run "ssh-keygen -lf client/keys/host/ssh_host_ed25519_key.pub"
run "cat client/keys/known_hosts"
info "Essa fingerprint está salva no known_hosts deste laboratório. Em produção \
ela ficaria em ~/.ssh/known_hosts da sua máquina."
note "No laboratório usamos chaves de host FIXAS (não regeneradas a cada rebuild) \
para que o known_hosts continue válido. Reconstrói o container → mesma fingerprint."
pause

# ---------------------------------------------------------------------------
step "ACESSO 1: login com USUÁRIO + SENHA (labuser / labpass)" "o método mais simples"
explain "Vamos entrar como 'labuser' com a senha 'labpass'. \
A senha NÃO vai em texto claro — ela viaja dentro do canal já cifrado \
(diferente do Telnet). Mas o método tem fraquezas sérias: bots na Internet \
ficam 24h tentando senhas em servidores com porta 22 aberta (brute force). \
Você VAI ser solicitado a digitar a senha: labpass"
echo
info "Digite a senha quando aparecer o prompt:  labpass"
echo

if [ "$AUTO" = "1" ]; then
  warn "Modo AUTO: login por senha é interativo — execute 'make ssh' para este passo."
  warn "Comando seria: ssh -p 2222 labuser@127.0.0.1"
else
  run "ssh -p 2222 \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=client/keys/known_hosts \
    -o IdentitiesOnly=yes \
    -o PubkeyAuthentication=no \
    -o PreferredAuthentications=password \
    labuser@127.0.0.1 \
    'echo \"=== dentro do servidor ===\"; hostname; whoami; id; uname -r; uptime'"
fi

warn "Funciona — mas qualquer um que descubra 'labpass' entra. E esses bots \
de brute force tentam milhares de senhas por hora."
pause

# ---------------------------------------------------------------------------
step "O par de chaves: como funciona a autenticação por chave" "criptografia assimétrica"
explain "Em vez de um segredo compartilhado (senha), usamos um PAR DE CHAVES \
assimétricas: a chave PRIVADA fica só com você, nunca sai da sua máquina. \
A chave PÚBLICA vai para o servidor (em ~/.ssh/authorized_keys). No login: \
o servidor manda um DESAFIO, você ASSINA com a privada, o servidor VERIFICA \
com a pública. Nenhum segredo trafega pela rede — imune a brute force e sniffing."
echo
run "ls -la $KEY $KEY.pub"
run "ssh-keygen -lf $KEY.pub"
info "Esta é a chave do laboratório. Algoritmo ed25519 (curva elíptica) — \
mais seguro e rápido que RSA para o mesmo nível de proteção."
echo
run "cat $KEY.pub"
info "Esta chave pública está instalada no servidor em ~/.ssh/authorized_keys:"
run "docker compose exec ssh cat /home/labuser/.ssh/authorized_keys"
pause

# ---------------------------------------------------------------------------
step "ACESSO 2: login com CHAVE PÚBLICA" "sem digitar senha"
explain "Agora vamos entrar usando o par de chaves. O ssh_config do laboratório \
(em client/ssh_config) já configura o alias 'lab' com: porta 2222, usuário \
labuser, a chave correta e IdentitiesOnly yes (não tenta outras chaves do agente)."
run "cat $CFG"
echo
run "ssh -F $CFG lab 'echo \"=== dentro do servidor com CHAVE ===\"; hostname; whoami; date'"
ok "Entrou SEM digitar senha! O servidor verificou a assinatura da chave."
pause

# ---------------------------------------------------------------------------
step "Explorando a máquina remotamente" "comandos dentro do servidor"
explain "Uma vez dentro, você pode rodar qualquer comando. Vamos explorar o \
servidor como faríamos em um acesso real de administração."
run "ssh -F $CFG lab 'hostname && echo && cat /etc/os-release | head -3'"
run "ssh -F $CFG lab 'ps aux | head -8'"
run "ssh -F $CFG lab 'ss -ltn'"
info "O 'ss -ltn' mostra que o sshd está escutando na porta 22 DENTRO do container."
run "ssh -F $CFG lab 'ls -la /home/labuser/'"
pause

# ---------------------------------------------------------------------------
step "PERMISSÕES: por que o SSH recusa chaves com permissão errada" "segurança em disco"
explain "O sshd é paranóico com permissões — e com razão. Se o diretório ~/.ssh \
ou o arquivo authorized_keys tiver permissão 'frouxas', qualquer outro usuário \
do sistema poderia editar sua lista de chaves autorizadas e entrar como você. \
Por isso o sshd RECUSA autenticar se as permissões estiverem erradas."
run "ssh -F $CFG lab 'stat -c \"%a  %U:%G  %n\" ~/.ssh ~/.ssh/authorized_keys'"
kv "700 = drwx------" "só o DONO pode entrar, ler e escrever no diretório"
kv "600 = -rw-------" "só o DONO pode ler e escrever o arquivo"
echo
info "A chave PRIVADA no seu computador também precisa ser 600:"
run "stat -c '%a  %n' $KEY"
note "Experimento: chmod 644 ~/.ssh e tente logar — o sshd bloqueia com \
'Permissions too open'. No container tentamos mostrar isso:"
run "ssh -F $CFG lab 'chmod 777 ~/.ssh/authorized_keys && ls -la ~/.ssh/'"
run "ssh -F $CFG lab 'chmod 600 ~/.ssh/authorized_keys && ls -la ~/.ssh/'"
pause

# ---------------------------------------------------------------------------
step "TRANSFERÊNCIA DE ARQUIVO: SCP (Secure Copy)" "arquivo viaja dentro do SSH"
explain "SCP e SFTP rodam DENTRO do canal SSH — mesma porta 22, mesma \
criptografia. NÃO é o FTP (que vemos trafegar em claro). Você usa o SSH \
para transferir arquivos de forma segura, sem abrir nova porta no firewall."
echo "Relatorio do laboratorio de SSH" > /tmp/lab_relatorio.txt
echo "Aluno: labuser"                 >> /tmp/lab_relatorio.txt
echo "Data: $(date)"                  >> /tmp/lab_relatorio.txt
echo "Protocolo: SSH (RFC 4251-4254)" >> /tmp/lab_relatorio.txt
run "cat /tmp/lab_relatorio.txt"
echo
run "scp -P 2222 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=client/keys/known_hosts \
  -o IdentitiesOnly=yes \
  -i $KEY \
  /tmp/lab_relatorio.txt labuser@127.0.0.1:/home/labuser/relatorio.txt"
echo
info "Verificando que o arquivo chegou no servidor:"
run "ssh -F $CFG lab 'ls -lh ~/relatorio.txt && echo && cat ~/relatorio.txt'"
note "Alternativa interativa: sftp -F client/ssh_config lab"
note "Depois: put arquivo, get arquivo, ls, rm — interface igual ao FTP, mas cifrada."
pause

# ---------------------------------------------------------------------------
step "BAIXAR UM ARQUIVO do servidor para o seu computador" "SCP no sentido inverso"
run "ssh -F $CFG lab 'echo \"arquivo gerado no servidor em \$(date)\" > /home/labuser/gerado_no_servidor.txt'"
run "scp -P 2222 \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=client/keys/known_hosts \
  -o IdentitiesOnly=yes \
  -i $KEY \
  labuser@127.0.0.1:/home/labuser/gerado_no_servidor.txt /tmp/"
run "cat /tmp/gerado_no_servidor.txt"
ok "Arquivo baixado do servidor com segurança, sem FTP, sem porta adicional."
pause

# ---------------------------------------------------------------------------
step "O que o SSH negocia no handshake" "criptografia do canal"
explain "No handshake (que leva milissegundos) o SSH negocia 3 coisas:"
kv "1. Troca de chaves (KEX)" "curve25519 — Diffie-Hellman de curva elíptica: as duas pontas chegam ao mesmo segredo SEM transmiti-lo"
kv "2. Cifra simétrica"       "ChaCha20-Poly1305 ou AES-GCM — garante CONFIDENCIALIDADE"
kv "3. MAC / AEAD"            "garante INTEGRIDADE — detecta se um byte foi alterado"
echo
run "grep -E 'KexAlgorithms|Ciphers|MACs|PermitRootLogin|PasswordAuthentication|MaxAuthTries|LoginGraceTime' services/ssh/sshd_config | grep -v '^#'"
echo
note "PermitRootLogin no  → nunca entra como root diretamente."
note "PasswordAuthentication yes  → mantemos para a demo; em produção: 'no'."
note "MaxAuthTries 6  → bloqueia força bruta (limita tentativas por conexão)."
pause

# ---------------------------------------------------------------------------
step "Hardening: como deixar o SSH seguro em produção" "além do laboratório"
kv "PasswordAuthentication no" "só chave pública; senha desativada"
kv "PermitRootLogin no"        "nunca root diretamente; use sudo"
kv "MaxAuthTries 3"            "bloqueia brute force rapidamente"
kv "AllowUsers labuser"        "whitelist: só esse usuário pode logar"
kv "Port 2222"                 "trocar a porta padrão reduz scan automático"
kv "fail2ban"                  "bane IPs após N tentativas falhas"
kv "Firewall (ufw/iptables)"   "só a porta do SSH aberta de IPs conhecidos"
kv "Chave com passphrase"      "se a chave privada for roubada, ainda está protegida"
pause

done_banner "Laboratório SSH concluído."
echo
info "Comandos para continuar explorando:"
kv "Sessão interativa (chave):" "ssh -F $CFG lab"
kv "Sessão interativa (senha):" "ssh -p 2222 labuser@127.0.0.1   # senha: labpass"
kv "SFTP interativo:"           "sftp -F $CFG lab"
kv "Logs do servidor em tempo real:" "docker logs -f lab-ssh"
kv "Wireshark SSH:"             "tcp.port==2222  (veja o roteiro para análise detalhada)"
