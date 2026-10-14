#!/usr/bin/env bash
# Trava local, por worktree e slug, para a transicao atomica da autorizacao F6.
# Nao ha recuperacao automatica: uma trava preexistente sempre falha fechada.

TRAVA_AUT6_DIR="${TRAVA_AUT6_DIR:-}"
TRAVA_AUT6_ADQUIRIDA="${TRAVA_AUT6_ADQUIRIDA:-nao}"
TRAVA_AUT6_MOTIVO="${TRAVA_AUT6_MOTIVO:-}"
TRAVA_AUT6_SINAL_PENDENTE=""
_TRAVA_AUT6_TRAP_HUP=""
_TRAVA_AUT6_TRAP_INT=""
_TRAVA_AUT6_TRAP_TERM=""

if ! command -v caminho_git >/dev/null 2>&1; then
  _TRAVA_AUT6_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || return 1
  . "$_TRAVA_AUT6_LIB_DIR/../caminho-git.sh" || return 1
  unset _TRAVA_AUT6_LIB_DIR
fi

libera_trava_autorizacao_f6() {
  [ "${TRAVA_AUT6_ADQUIRIDA:-nao}" = sim ] || return 0
  [ -n "${TRAVA_AUT6_DIR:-}" ] || return 1
  rmdir "$TRAVA_AUT6_DIR" 2>/dev/null || return 1
  TRAVA_AUT6_ADQUIRIDA=nao
  TRAVA_AUT6_DIR=""
  trap - EXIT
}

_trava_aut6_ao_sair() {
  local rc=$?
  libera_trava_autorizacao_f6 || true
  trap - EXIT
  exit "$rc"
}

_trava_aut6_restaura_sinais() {
  trap - HUP INT TERM
  [ -z "$_TRAVA_AUT6_TRAP_HUP" ] || eval "$_TRAVA_AUT6_TRAP_HUP"
  [ -z "$_TRAVA_AUT6_TRAP_INT" ] || eval "$_TRAVA_AUT6_TRAP_INT"
  [ -z "$_TRAVA_AUT6_TRAP_TERM" ] || eval "$_TRAVA_AUT6_TRAP_TERM"
  _TRAVA_AUT6_TRAP_HUP=""
  _TRAVA_AUT6_TRAP_INT=""
  _TRAVA_AUT6_TRAP_TERM=""
}

_trava_aut6_reemite_sinal() {
  local sinal="$TRAVA_AUT6_SINAL_PENDENTE" rc
  TRAVA_AUT6_SINAL_PENDENTE=""
  [ -n "$sinal" ] || return 0
  libera_trava_autorizacao_f6 || true
  kill -s "$sinal" "$$" 2>/dev/null || true
  case "$sinal" in
    HUP) rc=129 ;;
    INT) rc=130 ;;
    TERM) rc=143 ;;
    *) rc=1 ;;
  esac
  return "$rc"
}

_trava_aut6_adia_hup() { TRAVA_AUT6_SINAL_PENDENTE=HUP; }
_trava_aut6_adia_int() { TRAVA_AUT6_SINAL_PENDENTE=INT; }
_trava_aut6_adia_term() { TRAVA_AUT6_SINAL_PENDENTE=TERM; }

adquire_trava_autorizacao_f6() {
  [ $# -eq 2 ] || return 64
  TRAVA_AUT6_MOTIVO=""
  [ "${TRAVA_AUT6_ADQUIRIDA:-nao}" != sim ] || { TRAVA_AUT6_MOTIVO=existente; return 2; }
  local repo="$1" slug="$2" raiz caminho pai bruto mkdir_rc=0
  case "$slug" in ""|-*|*-|*--*|*[!a-z0-9-]*) return 64 ;; esac
  bruto="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || { TRAVA_AUT6_MOTIVO=ambiente; return 1; }
  raiz="$(caminho_git "$bruto")" || { TRAVA_AUT6_MOTIVO=ambiente; return 1; }
  bruto="$(git -C "$raiz" rev-parse --git-path "sprintx/travas/autorizacao-f6-$slug.lock" 2>/dev/null)" || { TRAVA_AUT6_MOTIVO=ambiente; return 1; }
  caminho="$(caminho_git "$bruto")" || { TRAVA_AUT6_MOTIVO=ambiente; return 1; }
  case "$caminho" in /*) ;; *) caminho="$raiz/$caminho" ;; esac
  pai="${caminho%/*}"
  mkdir -p "$pai" || { TRAVA_AUT6_MOTIVO=ambiente; return 1; }

  _TRAVA_AUT6_TRAP_HUP="$(trap -p HUP)"
  _TRAVA_AUT6_TRAP_INT="$(trap -p INT)"
  _TRAVA_AUT6_TRAP_TERM="$(trap -p TERM)"
  TRAVA_AUT6_SINAL_PENDENTE=""
  trap '_trava_aut6_adia_hup' HUP
  trap '_trava_aut6_adia_int' INT
  trap '_trava_aut6_adia_term' TERM

  mkdir "$caminho" 2>/dev/null || mkdir_rc=$?
  if [ "$mkdir_rc" -ne 0 ]; then
    _trava_aut6_restaura_sinais
    if [ -n "$TRAVA_AUT6_SINAL_PENDENTE" ]; then
      _trava_aut6_reemite_sinal
      return $?
    fi
    if [ -d "$caminho" ]; then TRAVA_AUT6_MOTIVO=existente; return 2; fi
    TRAVA_AUT6_MOTIVO=ambiente
    return 1
  fi
  TRAVA_AUT6_DIR="$caminho"
  TRAVA_AUT6_ADQUIRIDA=sim
  trap '_trava_aut6_ao_sair' EXIT
  _trava_aut6_restaura_sinais
  if [ -n "$TRAVA_AUT6_SINAL_PENDENTE" ]; then
    _trava_aut6_reemite_sinal
    return $?
  fi
}
