#!/usr/bin/env bash
# Trava local, por worktree e slug, para a transicao atomica da autorizacao F6.
# Nao ha recuperacao automatica: uma trava preexistente sempre falha fechada.

TRAVA_AUT6_DIR="${TRAVA_AUT6_DIR:-}"
TRAVA_AUT6_ADQUIRIDA="${TRAVA_AUT6_ADQUIRIDA:-nao}"

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

adquire_trava_autorizacao_f6() {
  [ $# -eq 2 ] || return 64
  [ "${TRAVA_AUT6_ADQUIRIDA:-nao}" != sim ] || return 1
  local repo="$1" slug="$2" raiz caminho pai bruto
  case "$slug" in ""|-*|*-|*--*|*[!a-z0-9-]*) return 64 ;; esac
  bruto="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || return 1
  raiz="$(caminho_git "$bruto")" || return 1
  bruto="$(git -C "$raiz" rev-parse --git-path "sprintx/travas/autorizacao-f6-$slug.lock" 2>/dev/null)" || return 1
  caminho="$(caminho_git "$bruto")" || return 1
  case "$caminho" in /*) ;; *) caminho="$raiz/$caminho" ;; esac
  pai="${caminho%/*}"
  mkdir -p "$pai" || return 1
  mkdir "$caminho" 2>/dev/null || return 1
  TRAVA_AUT6_DIR="$caminho"
  TRAVA_AUT6_ADQUIRIDA=sim
  trap '_trava_aut6_ao_sair' EXIT
}
