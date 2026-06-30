#!/usr/bin/env python3
"""Cliente SNTP (Simple Network Time Protocol) didático — RFC 4330 / RFC 5905.

Implementa, do zero e usando só a biblioteca padrão, uma consulta SNTP unicast:
monta o pacote de 48 bytes, envia por UDP para a porta 123, recebe a resposta
do servidor e decodifica TODOS os campos do cabeçalho NTP. Além de mostrar a
hora, calcula o *offset* (defasagem do relógio local) e o *delay* (atraso de
ida e volta), exatamente como faz um cliente NTP real.

Uso:
    uv run sntp_client.py --server 127.0.0.1
    uv run sntp_client.py --server 127.0.0.1 --raw     # mostra bytes crus
"""
from __future__ import annotations

import argparse
import socket
import struct
import sys
import time
from dataclasses import dataclass

# O NTP conta segundos desde 1900-01-01; o Unix conta desde 1970-01-01.
# A diferença é de 70 anos = 2_208_988_800 segundos.
NTP_UNIX_DELTA = 2_208_988_800

# Mapa de "kiss codes" / IDs de referência mais comuns (stratum 0/1).
LEAP_INDICATOR = {
    0: "sem aviso",
    1: "ultimo minuto tem 61s",
    2: "ultimo minuto tem 59s",
    3: "NAO sincronizado (alarme)",
}
MODE = {
    0: "reservado", 1: "ativo simetrico", 2: "passivo simetrico",
    3: "cliente", 4: "servidor", 5: "broadcast", 6: "controle NTP", 7: "privado",
}


def ntp_to_unix(seconds: int, fraction: int) -> float:
    """Converte um timestamp NTP de 64 bits (32.32 ponto fixo) para Unix epoch."""
    return (seconds - NTP_UNIX_DELTA) + fraction / 2**32


def unix_to_ntp(ts: float) -> tuple[int, int]:
    """Converte um instante Unix (float) para timestamp NTP (segundos, fração)."""
    ntp = ts + NTP_UNIX_DELTA
    seconds = int(ntp)
    fraction = int((ntp - seconds) * 2**32)
    return seconds, fraction


@dataclass
class SntpResult:
    leap: int
    version: int
    mode: int
    stratum: int
    poll: int
    precision: int
    root_delay: float
    root_dispersion: float
    ref_id: bytes
    ref_time: float
    originate_time: float
    receive_time: float
    transmit_time: float
    destination_time: float  # t4: quando a resposta chegou no cliente

    @property
    def offset(self) -> float:
        """Defasagem do relógio local em relação ao servidor (segundos).
        offset = ((t2 - t1) + (t3 - t4)) / 2"""
        t1, t2, t3, t4 = (
            self.originate_time, self.receive_time,
            self.transmit_time, self.destination_time,
        )
        return ((t2 - t1) + (t3 - t4)) / 2

    @property
    def delay(self) -> float:
        """Atraso de ida e volta (round-trip), descontando o tempo de
        processamento no servidor. delay = (t4 - t1) - (t3 - t2)"""
        t1, t2, t3, t4 = (
            self.originate_time, self.receive_time,
            self.transmit_time, self.destination_time,
        )
        return (t4 - t1) - (t3 - t2)

    def ref_id_str(self) -> str:
        if self.stratum in (0, 1):
            # ASCII de 4 letras (ex.: "LOCL", "GPS", kiss-codes "RATE", "DENY").
            return self.ref_id.rstrip(b"\x00").decode("ascii", "replace")
        # stratum >= 2: é o IPv4 do servidor de referência.
        return ".".join(str(b) for b in self.ref_id)


def build_request() -> tuple[bytes, float]:
    """Monta o pacote de requisição SNTP (48 bytes) modo cliente."""
    # Primeiro byte: LI (2 bits) | VN (3 bits) | Mode (3 bits)
    # LI=0, VN=4, Mode=3 (cliente)  ->  0b00_100_011 = 0x23
    li_vn_mode = (0 << 6) | (4 << 3) | 3
    t1 = time.time()
    tx_sec, tx_frac = unix_to_ntp(t1)
    packet = struct.pack(
        "!B B b b 11I",
        li_vn_mode,  # byte 0
        0,           # stratum
        0,           # poll
        0,           # precision
        0, 0,        # root delay, root dispersion (32 bits cada)
        0,           # reference id
        0, 0,        # reference timestamp (64 bits)
        0, 0,        # originate timestamp
        0, 0,        # receive timestamp
        tx_sec, tx_frac,  # transmit timestamp = nosso t1
    )
    return packet, t1


def parse_response(data: bytes, t1: float, t4: float) -> SntpResult:
    if len(data) < 48:
        raise ValueError(f"resposta curta demais: {len(data)} bytes")
    fields = struct.unpack("!B B b b 11I", data[:48])
    li_vn_mode = fields[0]
    leap = (li_vn_mode >> 6) & 0x3
    version = (li_vn_mode >> 3) & 0x7
    mode = li_vn_mode & 0x7
    stratum, poll, precision = fields[1], fields[2], fields[3]
    root_delay = fields[4] / 2**16
    root_dispersion = fields[5] / 2**16
    ref_id = struct.pack("!I", fields[6])
    ref_time = ntp_to_unix(fields[7], fields[8])
    originate = ntp_to_unix(fields[9], fields[10]) if fields[9] else t1
    receive = ntp_to_unix(fields[11], fields[12])
    transmit = ntp_to_unix(fields[13], fields[14])
    return SntpResult(
        leap, version, mode, stratum, poll, precision,
        root_delay, root_dispersion, ref_id, ref_time,
        originate, receive, transmit, t4,
    )


def query(server: str, port: int, timeout: float) -> tuple[SntpResult, bytes]:
    packet, t1 = build_request()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(timeout)
        sock.sendto(packet, (server, port))
        data, _ = sock.recvfrom(512)
        t4 = time.time()
    return parse_response(data, t1, t4), data


def fmt_time(ts: float) -> str:
    lt = time.localtime(ts)
    return time.strftime("%Y-%m-%d %H:%M:%S", lt) + f".{int((ts % 1) * 1e6):06d}"


def main() -> int:
    ap = argparse.ArgumentParser(description="Cliente SNTP didático (RFC 4330).")
    ap.add_argument("--server", "-s", default="127.0.0.1", help="endereço do servidor NTP")
    ap.add_argument("--port", "-p", type=int, default=123, help="porta UDP (padrão 123)")
    ap.add_argument("--timeout", "-t", type=float, default=5.0, help="timeout em segundos")
    ap.add_argument("--raw", action="store_true", help="mostra os 48 bytes crus em hexadecimal")
    args = ap.parse_args()

    print(f"\n  Consultando servidor SNTP {args.server}:{args.port} via UDP...\n")
    try:
        r, raw = query(args.server, args.port, args.timeout)
    except socket.timeout:
        print(f"  ERRO: timeout — servidor {args.server}:{args.port} nao respondeu.", file=sys.stderr)
        return 1
    except OSError as e:
        print(f"  ERRO de rede: {e}", file=sys.stderr)
        return 1

    if args.raw:
        print("  Pacote cru (48 bytes):")
        print("   ", raw[:48].hex(" "), "\n")

    print("  === Cabeçalho NTP decodificado ===")
    print(f"  Leap Indicator (LI) : {r.leap}  ({LEAP_INDICATOR.get(r.leap)})")
    print(f"  Versão (VN)         : {r.version}")
    print(f"  Modo                : {r.mode}  ({MODE.get(r.mode)})")
    print(f"  Stratum             : {r.stratum}  ({'fonte primaria' if r.stratum==1 else 'secundario' if r.stratum>=2 else 'kiss/invalido'})")
    print(f"  Poll interval       : 2^{r.poll} = {2**r.poll if r.poll>=0 else 0}s")
    print(f"  Precisão            : 2^{r.precision} s")
    print(f"  Root delay          : {r.root_delay*1000:.3f} ms")
    print(f"  Root dispersion     : {r.root_dispersion*1000:.3f} ms")
    print(f"  Reference ID        : {r.ref_id_str()}")
    print(f"  Reference timestamp : {fmt_time(r.ref_time)}")
    print()
    print("  === Os quatro carimbos de tempo (algoritmo NTP) ===")
    print(f"  t1 Originate (cliente envia)  : {fmt_time(r.originate_time)}")
    print(f"  t2 Receive   (servidor recebe): {fmt_time(r.receive_time)}")
    print(f"  t3 Transmit  (servidor envia) : {fmt_time(r.transmit_time)}")
    print(f"  t4 Destination (cliente recebe): {fmt_time(r.destination_time)}")
    print()
    print("  === Resultado ===")
    print(f"  Hora do servidor (t3) : {fmt_time(r.transmit_time)}")
    print(f"  Offset do relógio local: {r.offset*1000:+.3f} ms")
    print(f"  Round-trip delay       : {r.delay*1000:.3f} ms")
    veredito = "adiantado" if r.offset < 0 else "atrasado"
    print(f"  -> Seu relógio está {abs(r.offset*1000):.1f} ms {veredito} em relação ao servidor.\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
