#!/usr/bin/env bash
# Laboratório guiado de FTP — transferência de arquivos, passo a passo.
# Mostra os DOIS canais (controle + dados), o modo passivo e suas portas, as
# permissões/chroot do usuário, e o ponto crítico: tudo trafega em TEXTO CLARO.
cd "$(dirname "$0")/.."
source scripts/lib.sh

HOST=127.0.0.1; USER=ftpuser; PASS=ftppass
WORK=/tmp/lab_ftp; mkdir -p "$WORK"

banner "LABORATÓRIO FTP — transferência de arquivos (porta 21 + dados)"
explain "FTP (File Transfer Protocol, RFC 959, de 1985) é um dos protocolos mais \
antigos da Internet. Sua marca registrada é usar DOIS canais TCP separados: um de \
CONTROLE (comandos) e um de DADOS (o arquivo). E, no FTP puro, tudo vai em texto claro."

# ---------------------------------------------------------------------------
step "O servidor e as PORTAS" "controle 21 + faixa passiva 21100-21110"
explain "Porta 21 = canal de CONTROLE (well-known). O canal de DADOS usa outra porta. \
No modo PASSIVO, o servidor abre uma porta de dados numa faixa que fixamos \
(21100-21110) para conseguir mapear no Docker e atravessar NAT/firewall."
run "docker compose ps ftp"
run "docker compose port ftp 21"
note "Por que fixar a faixa? Sem isso o servidor sortearia qualquer porta alta, e o \
Docker/NAT não saberia encaminhá-la."
pause

# ---------------------------------------------------------------------------
step "Controle x Dados, e os modos ATIVO vs PASSIVO"
explain "ATIVO: o SERVIDOR conecta de volta ao cliente (comando PORT) — quebra com \
NAT/firewall do lado do cliente. PASSIVO (comando PASV): o CLIENTE conecta ao \
servidor numa porta que ele anuncia — é o que funciona hoje. Por isso usamos PASV."
kv "Canal de controle" "porta 21 — USER, PASS, LIST, RETR, STOR, PASV..."
kv "Canal de dados"    "porta da faixa 21100-21110 — o conteúdo do arquivo"
pause

# ---------------------------------------------------------------------------
step "CONECTAR e AUTENTICAR (usuário + senha)"
explain "Vamos usar o curl com -v para VER o diálogo do protocolo: cada linha '>' é \
um comando nosso e cada '<' é uma resposta do servidor (com código numérico: 220 \
pronto, 331 peça senha, 230 logado, 227 entrando em passivo...)."
echo "arquivo de UPLOAD criado em $(date)" > "$WORK/upload.txt"
run "curl -v --ftp-pasv --disable-epsv -u $USER:$PASS ftp://$HOST/ 2>&1 | sed -n '1,40p'"
warn "Repare: 'USER ftpuser' e 'PASS ftppass' aparecem aqui — e na rede vão em CLARO."
pause

# ---------------------------------------------------------------------------
step "UPLOAD de um arquivo (comando STOR no canal de dados)"
run "curl -sS --ftp-pasv -T $WORK/upload.txt ftp://$USER:$PASS@$HOST/upload.txt && echo OK"
info "Listando o diretório remoto para confirmar:"
run "curl -sS --ftp-pasv ftp://$USER:$PASS@$HOST/"
pause

# ---------------------------------------------------------------------------
step "DOWNLOAD de um arquivo (comando RETR)"
run "curl -sS --ftp-pasv ftp://$USER:$PASS@$HOST/exemplo.txt -o $WORK/baixado.txt"
run "cat $WORK/baixado.txt"
pause

# ---------------------------------------------------------------------------
step "PERMISSÕES e ISOLAMENTO (chroot, umask, dono dos arquivos)"
explain "O vsftpd prende o usuário no próprio home (chroot_local_user): ele NÃO \
enxerga o resto do sistema de arquivos do servidor — uma jaula. O local_umask=022 \
define a permissão dos arquivos enviados. Veja os arquivos como o servidor os criou:"
run "docker compose exec ftp ls -la /home/ftpuser"
run "docker compose exec ftp sh -c 'id ftpuser; grep -E \"chroot|umask|write_enable\" /etc/vsftpd.conf'"
note "chroot = confinamento (se a conta for comprometida, o estrago fica no home). \
umask 022 → arquivos 644 (dono escreve, outros só leem)."
pause

# ---------------------------------------------------------------------------
step "O PROBLEMA DE SEGURANÇA — FTP é texto claro"
explain "Tudo o que vimos (usuário, senha e o conteúdo dos arquivos) trafega SEM \
criptografia. Qualquer um na rede captura com Wireshark. É o motivo de o FTP puro \
estar obsoleto. Veja as opções modernas:"
kv "FTPS" "FTP + TLS (ssl_enable=YES + certificado no vsftpd) — cifra os dois canais"
kv "SFTP" "NÃO é FTP: é transferência dentro do SSH (porta 22) — vide o lab de SSH"
note "Mantemos FTP em claro DE PROPÓSITO para capturar a senha no Wireshark e ver o risco."
pause

done_banner "Lab FTP concluído — 2 canais, passivo, chroot/permissões e o risco do texto claro."
echo
info "No Wireshark, capture e filtre:"
kv "  ftp"      "comandos do controle — dá para LER 'PASS ftppass'"
kv "  ftp-data" "o conteúdo do arquivo transferido, também em claro"
kv "  FileZilla" "Host $HOST  Porta 21  Usuário $USER  Senha $PASS  (modo passivo)"
