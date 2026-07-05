# Servidor FTP didático baseado em vsftpd.
FROM debian:12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends vsftpd ftp \
    && rm -rf /var/lib/apt/lists/*

COPY vsftpd.conf /etc/vsftpd.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 21 = controle; 21100-21110 = canais de dados no modo passivo (PASV).
EXPOSE 21 21100-21110
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]