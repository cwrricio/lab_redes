# Servidor OpenSSH didático.
# Base enxuta + openssh-server. Criamos um usuário "labuser" e habilitamos
# tanto senha quanto chave pública para podermos demonstrar os dois fluxos.
FROM debian:12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-server \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd

# Usuário do laboratório (senha simples, só para demonstração!)
RUN useradd -m -s /bin/bash labuser \
    && echo 'labuser:labpass' | chpasswd

COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
