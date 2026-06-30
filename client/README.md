# Cliente SNTP (Python + uv)

Cliente SNTP unicast escrito do zero com a biblioteca padrão. Implementa a
RFC 4330: monta o pacote de 48 bytes, envia por UDP/123, decodifica todos os
campos do cabeçalho NTP e calcula *offset* e *delay*.

```bash
# Roda sem instalar nada (uv resolve o ambiente):
uv run sntp_client.py --server 127.0.0.1

# Mostra também os bytes crus do pacote:
uv run sntp_client.py --server 127.0.0.1 --raw
```

A pasta `keys/` guarda o par de chaves SSH do cliente, gerado por
`../scripts/gen_keys.sh`. Não versione as chaves privadas em repositório real.
