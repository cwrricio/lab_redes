#!/usr/bin/env bash
# Prepara o material criptográfico do laboratório:
#   1) par de chaves DO CLIENTE (autentica o usuário no servidor);
#   2) chaves de host DO SERVIDOR (identificam o servidor — anti-MITM);
#   3) client/ssh_config pronto, com aliases "lab" (chave) e "lab-pass" (senha);
#   4) client/keys/known_hosts já com a fingerprint do servidor.
# Tudo idempotente: rodar de novo não regenera o que já existe.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

KEY_DIR="client/keys"
HOST_DIR="$KEY_DIR/host"
CLIENT_KEY="$KEY_DIR/lab_ed25519"
PORT=2222

mkdir -p "$HOST_DIR"

# 1) Chave do cliente -------------------------------------------------------
if [ ! -f "$CLIENT_KEY" ]; then
  ssh-keygen -t ed25519 -f "$CLIENT_KEY" -N "" -C "labuser@lab-redes" >/dev/null
  echo "[keys] Par de chaves do CLIENTE gerado: $CLIENT_KEY(.pub)"
else
  echo "[keys] Chave do cliente já existe: $CLIENT_KEY"
fi

# 2) Chaves de host do servidor --------------------------------------------
if [ ! -f "$HOST_DIR/ssh_host_ed25519_key" ]; then
  ssh-keygen -t ed25519 -f "$HOST_DIR/ssh_host_ed25519_key" -N "" -C "lab-ssh-host" >/dev/null
  ssh-keygen -t rsa -b 4096 -f "$HOST_DIR/ssh_host_rsa_key" -N "" -C "lab-ssh-host" >/dev/null
  echo "[keys] Chaves de HOST do servidor geradas em $HOST_DIR/"
else
  echo "[keys] Chaves de host já existem em $HOST_DIR/"
fi

# 3) known_hosts (fixa a identidade do servidor para o cliente) ------------
HOSTKEY="$(awk '{print $1, $2}' "$HOST_DIR/ssh_host_ed25519_key.pub")"
echo "[127.0.0.1]:$PORT $HOSTKEY" > "$KEY_DIR/known_hosts"

# 4) ssh_config -------------------------------------------------------------
cat > client/ssh_config <<EOF
# Gerado por scripts/gen_keys.sh — caminhos absolutos para este laboratório.
# Uso:  ssh -F client/ssh_config lab        (login por CHAVE)
#       ssh -F client/ssh_config lab-pass   (login por SENHA: labpass)

# --- Login por CHAVE PÚBLICA (recomendado) ---
Host lab
    HostName 127.0.0.1
    Port $PORT
    User labuser
    IdentityFile $ROOT/$CLIENT_KEY
    IdentitiesOnly yes
    UserKnownHostsFile $ROOT/$KEY_DIR/known_hosts
    StrictHostKeyChecking accept-new

# --- Login por SENHA (didático: senha 'labpass') ---
# Desliga a chave de propósito, para o servidor pedir a SENHA e evitar o erro
# "Too many authentication failures" causado pelo ssh-agent oferecer chaves.
Host lab-pass
    HostName 127.0.0.1
    Port $PORT
    User labuser
    PubkeyAuthentication no
    PreferredAuthentications password
    UserKnownHostsFile $ROOT/$KEY_DIR/known_hosts
    StrictHostKeyChecking accept-new
EOF
echo "[keys] client/ssh_config gerado (aliases: lab, lab-pass)."

echo
echo "[keys] Fingerprints:"
echo "  cliente : $(ssh-keygen -lf "$CLIENT_KEY.pub" | awk '{print $2}')"
echo "  host    : $(ssh-keygen -lf "$HOST_DIR/ssh_host_ed25519_key.pub" | awk '{print $2}')"
