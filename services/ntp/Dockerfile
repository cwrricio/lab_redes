# Servidor NTP/SNTP didático baseado em chrony.
FROM debian:12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends chrony \
    && rm -rf /var/lib/apt/lists/*

COPY chrony.conf /etc/chrony/chrony.conf

EXPOSE 123/udp
# -d = foreground/debug, -x = NÃO controla o relógio do sistema (só serve a
# hora). Isso evita exigir privilégios de ajuste de relógio no host.
ENTRYPOINT ["chronyd", "-d", "-x"]
