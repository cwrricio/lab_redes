#!/usr/bin/env bash
# =============================================================================
# lib.sh — biblioteca de saída para os laboratórios guiados.
# Cores, caixas, cabeçalhos de passo, tabelas chave/valor e a função run(),
# que MOSTRA o comando, espera o ENTER e só então executa. É isso que torna o
# laboratório "passo a passo": o apresentador explica, todos veem o comando, e
# o comando roda na frente da plateia.
#
# Variáveis de ambiente:
#   AUTO=1     -> não pausa (usado por `make demo`)
#   NO_COLOR=1 -> desliga cores
# =============================================================================

# --- Detecção de cores -------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && command -v tput >/dev/null 2>&1 \
   && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  C_RESET=$(tput sgr0);   C_BOLD=$(tput bold);    C_DIM=$(tput dim)
  C_RED=$(tput setaf 1);  C_GREEN=$(tput setaf 2); C_YELLOW=$(tput setaf 3)
  C_BLUE=$(tput setaf 4); C_MAGENTA=$(tput setaf 5); C_CYAN=$(tput setaf 6)
else
  C_RESET=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_MAGENTA=; C_CYAN=
fi

AUTO="${AUTO:-0}"
STEP_N=0

_width() { local w; w=$(tput cols 2>/dev/null || echo 80); [ "$w" -gt 92 ] && w=92; echo "$w"; }
# Repete um caractere N vezes. Faz por concatenação (não 'tr') para suportar
# caracteres multibyte UTF-8 como ─ e ═ sem corromper os bytes.
_rep()   { local n=$1 ch=$2 out= i; for ((i=0; i<n; i++)); do out+="$ch"; done; printf '%s' "$out"; }

hr() { printf "${C_DIM}"; _rep "$(_width)" '─'; printf "${C_RESET}\n"; }

# Banner grande de início de um laboratório.
banner() {
  local title="$1" w; w=$(_width)
  echo
  printf "${C_BOLD}${C_CYAN}╔"; _rep $((w-2)) '═'; printf "╗${C_RESET}\n"
  printf "${C_BOLD}${C_CYAN}║${C_RESET} ${C_BOLD}%-*s${C_RESET} ${C_BOLD}${C_CYAN}║${C_RESET}\n" $((w-4)) "$title"
  printf "${C_BOLD}${C_CYAN}╚"; _rep $((w-2)) '═'; printf "╝${C_RESET}\n"
}

# Cabeçalho de um passo numerado, com subtítulo opcional.
step() {
  STEP_N=$((STEP_N+1))
  echo
  printf "${C_BOLD}${C_BLUE}▌ Passo %02d ${C_RESET}${C_BOLD}%s${C_RESET}\n" "$STEP_N" "$1"
  [ -n "${2:-}" ] && printf "${C_DIM}%s${C_RESET}\n" "$2"
}

# Linhas com etiqueta.
info() { printf "  ${C_BLUE}ℹ${C_RESET}  %s\n" "$*"; }
ok()   { printf "  ${C_GREEN}✔${C_RESET}  %s\n" "$*"; }
warn() { printf "  ${C_YELLOW}▲${C_RESET}  %s\n" "$*"; }
err()  { printf "  ${C_RED}✘${C_RESET}  %s\n" "$*"; }
note() { printf "  ${C_MAGENTA}✱${C_RESET}  %s\n" "$*"; }

# Parágrafo explicativo (quebra de linha automática).
explain() { printf "${C_DIM}"; printf "%s\n" "$*" | fold -s -w "$(_width)"; printf "${C_RESET}"; }

# Linha de tabela chave/valor.
kv() { printf "  ${C_CYAN}%-24s${C_RESET} %s\n" "$1" "$2"; }

pause() {
  [ "$AUTO" = "1" ] && return 0
  printf "${C_DIM}   ⏎ ENTER para continuar...${C_RESET}"
  read -r _ < /dev/tty 2>/dev/null || true
  printf "\r\033[K"
}

# run "<comando>": mostra o comando, espera ENTER, executa, reporta o status.
run() {
  local cmd="$*"
  echo
  printf "  ${C_DIM}\$${C_RESET} ${C_BOLD}${C_YELLOW}%s${C_RESET}\n" "$cmd"
  if [ "$AUTO" != "1" ]; then
    printf "${C_DIM}   ⏎ ENTER para executar...${C_RESET}"
    read -r _ < /dev/tty 2>/dev/null || true
    printf "\r\033[K"
  fi
  hr
  eval "$cmd"
  local rc=$?
  hr
  if [ "$rc" -eq 0 ]; then ok "exit ${rc}"; else warn "exit ${rc}"; fi
  return "$rc"
}

# Encerramento do laboratório.
done_banner() {
  echo
  printf "${C_BOLD}${C_GREEN}"; _rep "$(_width)" '═'; printf "${C_RESET}\n"
  printf "  ${C_BOLD}${C_GREEN}✔ %s${C_RESET}\n" "${1:-Laboratório concluído.}"
  printf "${C_BOLD}${C_GREEN}"; _rep "$(_width)" '═'; printf "${C_RESET}\n"
}
