#!/usr/bin/env bash
# Captura o tráfego dos três serviços na interface de loopback e salva um
# .pcap para abrir no Wireshark. Roda tcpdump em background, executa as três
# demonstrações e encerra a captura.
#
# Requer: sudo (tcpdump precisa de privilégio para capturar).
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="captures/lab_$(date +%Y%m%d_%H%M%S).pcap"
IFACE="${IFACE:-lo}"   # loopback, porque acessamos tudo via 127.0.0.1
FILTER="port 21 or portrange 21100-21110 or port 2222 or port 123"

echo "==> Capturando em $IFACE -> $OUT"
echo "    Filtro: $FILTER"
sudo tcpdump -i "$IFACE" -w "$OUT" "$FILTER" &
TCPDUMP_PID=$!
sleep 2

cleanup() {
    echo "==> Encerrando captura..."
    sudo kill "$TCPDUMP_PID" 2>/dev/null || true
    wait "$TCPDUMP_PID" 2>/dev/null || true
    echo "==> Arquivo salvo: $OUT"
    echo "    Abra no Wireshark:  wireshark $OUT"
    echo "    Filtros úteis no Wireshark: ftp   |   ftp-data   |   ntp   |   tcp.port==2222"
}
trap cleanup EXIT

# AUTO=1 = roda os laboratórios sem pausas (não-interativo) para a captura.
echo; echo "############ SNTP ############"; AUTO=1 bash scripts/lab_sntp.sh || true
echo; echo "############ FTP  ############"; AUTO=1 bash scripts/lab_ftp.sh  || true
echo; echo "############ SSH  ############"; AUTO=1 bash scripts/lab_ssh.sh  || true
sleep 2
