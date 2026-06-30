#!/usr/bin/env bash
# Laboratório guiado de SNTP — consulta e sincronização de horário, passo a passo.
# Decodifica o pacote NTP de 48 bytes, explica stratum, os 4 timestamps,
# offset/delay, e a (falta de) segurança do protocolo.
cd "$(dirname "$0")/.."
source scripts/lib.sh

SERVER="${1:-127.0.0.1}"

banner "LABORATÓRIO SNTP — consulta de horário (porta 123/UDP)"
explain "NTP (Network Time Protocol, RFC 5905) mantém relógios sincronizados na \
Internet com precisão de milissegundos. SNTP (RFC 4330) é a versão SIMPLES: mesmo \
pacote, sem os algoritmos de disciplina do relógio — ideal para CONSULTAR a hora. \
Nosso cliente (client/sntp_client.py) foi escrito do zero só com a stdlib."

# ---------------------------------------------------------------------------
step "O servidor e a PORTA" "123/UDP — e por que UDP, não TCP"
explain "NTP usa a porta well-known 123 sobre UDP. Por que UDP? É uma troca curta \
pergunta/resposta; abrir conexão TCP (3-way handshake) adicionaria atraso e — pior — \
distorceria a medição de tempo. Se um pacote se perder, é mais barato perguntar de novo."
run "docker compose ps ntp"
run "docker compose port --protocol udp ntp 123"
pause

# ---------------------------------------------------------------------------
step "A hierarquia de STRATUM"
explain "O tempo desce em camadas (stratum): stratum 0 são as fontes de referência \
(relógios atômicos, GPS); stratum 1 são servidores ligados direto a elas; stratum 2 \
sincroniza com stratum 1, e assim por diante — quanto maior o número, mais longe da \
fonte. Nosso chrony busca o pool.ntp.org (stratum 1) e vira stratum N+1 da fonte que escolher (tipicamente 2 ou 3)."
run "docker compose exec ntp chronyc tracking"
info "Acima: a fonte de referência, o stratum atingido e o erro estimado do relógio."
run "docker compose exec ntp chronyc sources -v"
note "Cada linha é um servidor upstream; o '^*' marca a fonte selecionada como melhor."
pause

# ---------------------------------------------------------------------------
step "O PACOTE NTP de 48 bytes (nosso cliente decodifica campo a campo)"
explain "Vamos enviar uma requisição e decodificar a resposta. O cabeçalho tem 48 \
bytes: Leap Indicator, Versão, Modo, Stratum, intervalo de Poll, Precisão, Root \
delay/dispersion, Reference ID e quatro timestamps de 64 bits."
run "( cd client && uv run sntp_client.py --server $SERVER --raw )"
pause

# ---------------------------------------------------------------------------
step "OS QUATRO TIMESTAMPS e o cálculo de OFFSET e DELAY"
explain "O segredo da precisão do NTP são quatro carimbos de tempo:"
kv "t1 Originate" "quando o CLIENTE enviou a requisição"
kv "t2 Receive"   "quando o SERVIDOR recebeu"
kv "t3 Transmit"  "quando o SERVIDOR respondeu"
kv "t4 Destination" "quando o CLIENTE recebeu a resposta"
echo
explain "Com eles o cliente calcula, cancelando o atraso da rede:"
kv "offset" "((t2 − t1) + (t3 − t4)) / 2   → quanto seu relógio está adiantado/atrasado"
kv "delay"  "(t4 − t1) − (t3 − t2)         → atraso de ida e volta (round-trip)"
note "Assumindo o caminho de ida ≈ volta, o offset elimina a latência da rede. É por \
isso que dá para acertar o relógio com precisão de ms mesmo com a rede no meio."
pause

# ---------------------------------------------------------------------------
step "Comparando duas consultas" "consistência do offset/delay"
explain "Duas medições seguidas devem dar offset parecido (o relógio não pulou) e \
delay pequeno na rede local. É assim que um cliente real filtra ruído antes de ajustar."
run "( cd client && uv run sntp_client.py --server $SERVER ) | grep -E 'Offset|Round-trip|Hora do servidor'"
run "( cd client && uv run sntp_client.py --server $SERVER ) | grep -E 'Offset|Round-trip|Hora do servidor'"
pause

# ---------------------------------------------------------------------------
step "SEGURANÇA — o NTP básico não autentica"
explain "O SNTP/NTP clássico NÃO verifica a identidade do servidor. Um atacante na \
rede pode responder com hora falsa (NTP spoofing) — e mexer no relógio quebra \
certificados TLS (validade), logs, Kerberos, tokens TOTP, agendamentos..."
kv "Mitigação moderna" "NTS (Network Time Security, RFC 8915) — autentica via TLS"
kv "Antiga (frágil)"   "symmetric key / autokey"
note "Consulta vs. sincronização: nosso cliente CONSULTA e calcula o offset, mas NÃO \
ajusta o relógio do host (exigiria privilégio e poderia bagunçar a máquina). Ajustar \
é papel de um daemon como chronyd/ntpd rodando continuamente."
pause

done_banner "Lab SNTP concluído — UDP/123, stratum, 4 timestamps, offset/delay e segurança."
echo
info "No Wireshark, filtre por  ntp  para ver o pacote de 48 bytes decodificado."
