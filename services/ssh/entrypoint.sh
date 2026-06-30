#!/bin/sh
set -e

# Chaves de host: usa as FIXAS montadas em /hostkeys (geradas no host por
# gen_keys.sh); se não houver, gera efêmeras no primeiro boot.
if ls /hostkeys/ssh_host_* >/dev/null 2>&1; then
    cp /hostkeys/ssh_host_* /etc/ssh/
    chmod 600 /etc/ssh/ssh_host_*_key
    chmod 644 /etc/ssh/ssh_host_*_key.pub
    echo "[ssh] Chaves de host FIXAS carregadas de /hostkeys."
else
    [ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" >/dev/null
    [ -f /etc/ssh/ssh_host_rsa_key ]     || ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" >/dev/null
    echo "[ssh] Chaves de host efêmeras geradas (nenhuma montada)."
fi

# Instala a chave pública do cliente (autenticação por chave), se montada.
if [ -f /keys/authorized_key.pub ]; then
    install -d -m 700 -o labuser -g labuser /home/labuser/.ssh
    cp /keys/authorized_key.pub /home/labuser/.ssh/authorized_keys
    chown labuser:labuser /home/labuser/.ssh/authorized_keys
    chmod 600 /home/labuser/.ssh/authorized_keys
    echo "[ssh] Chave pública do cliente instalada para labuser."
else
    echo "[ssh] AVISO: nenhuma chave pública montada — só autenticação por senha."
fi

echo "[ssh] Fingerprints das chaves de host:"
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key
ssh-keygen -lf /etc/ssh/ssh_host_rsa_key

# -D = foreground, -e = log para stderr (aparece no docker logs)
exec /usr/sbin/sshd -D -e
