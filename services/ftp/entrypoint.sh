#!/bin/sh
set -e

FTP_USER="${FTP_USER:-ftpuser}"
FTP_PASS="${FTP_PASS:-ftppass}"
PASV_ADDRESS="${PASV_ADDRESS:-127.0.0.1}"

# Cria o usuário de FTP se ainda não existir.
if ! id "$FTP_USER" >/dev/null 2>&1; then
    useradd -m -d "/home/$FTP_USER" -s /usr/sbin/nologin "$FTP_USER"
fi
echo "${FTP_USER}:${FTP_PASS}" | chpasswd

# vsftpd recusa shells que não estejam em /etc/shells.
grep -qx /usr/sbin/nologin /etc/shells 2>/dev/null || echo /usr/sbin/nologin >> /etc/shells

# Garante um arquivo de exemplo para baixar na demonstração.
if [ ! -f "/home/$FTP_USER/exemplo.txt" ]; then
    echo "Arquivo de exemplo servido via FTP - laboratorio de Redes." > "/home/$FTP_USER/exemplo.txt"
fi
chown -R "$FTP_USER:$FTP_USER" "/home/$FTP_USER"

# Diretório exigido pelo vsftpd quando há chroot.
mkdir -p /var/run/vsftpd/empty

echo "[ftp] Usuário: $FTP_USER | PASV anunciado em: $PASV_ADDRESS"

exec /usr/sbin/vsftpd /etc/vsftpd.conf \
    -opasv_address="$PASV_ADDRESS" \
    -obackground=NO
