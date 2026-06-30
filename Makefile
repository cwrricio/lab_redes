# Laboratório de Serviços de Aplicação: FTP, SSH e SNTP
# Atalhos para subir o ambiente e rodar os laboratórios guiados.

.DEFAULT_GOAL := help
.PHONY: help keys up down logs ps ssh ftp sntp demo capture clean

help:  ## Mostra esta ajuda
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

keys:  ## Gera chaves do cliente, chaves de host e o ssh_config
	@bash scripts/gen_keys.sh

up: keys  ## Sobe os três serviços (build + start)
	docker compose up -d --build
	@echo
	@echo "Serviços no ar. Rode os laboratórios guiados:"
	@echo "  make ssh    # acesso remoto: senha -> chave -> envio de arquivo"
	@echo "  make ftp    # transferência de arquivos (2 canais, passivo)"
	@echo "  make sntp   # consulta de horário (stratum, offset/delay)"

down:  ## Derruba os serviços
	docker compose down

ps:    ## Estado dos containers
	docker compose ps

logs:  ## Acompanha os logs dos serviços
	docker compose logs -f

ssh:   ## Laboratório guiado de SSH (interativo, passo a passo)
	@bash scripts/lab_ssh.sh

ftp:   ## Laboratório guiado de FTP (interativo, passo a passo)
	@bash scripts/lab_ftp.sh

sntp:  ## Laboratório guiado de SNTP (interativo, passo a passo)
	@bash scripts/lab_sntp.sh

demo:  ## Roda os 3 laboratórios SEM pausas (AUTO=1) — visão rápida
	@AUTO=1 bash scripts/lab_sntp.sh
	@AUTO=1 bash scripts/lab_ftp.sh
	@AUTO=1 bash scripts/lab_ssh.sh

capture:    ## Captura o tráfego das 3 demos em .pcap (requer sudo/tcpdump)
	@bash scripts/capture.sh

clean: down  ## Derruba tudo e remove imagens/volumes do laboratório
	docker compose down --rmi local --volumes --remove-orphans || true
