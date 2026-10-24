#!/usr/bin/env bash
# execucao.sh — o snapshot de modelo e esforco do executor de uma linha do rastro (DS-186).
#
# Nao e executavel: scripts/rastro.sh, planejamento.sh e bloqueios.sh fazem `source`.
# Registra o executor efetivo; nao escolhe modelo, harness nem esforco.
#
# Regras, iguais para qualquer harness:
#   1. EXPX_MODEL e EXPX_EFFORT descrevem o executor EXPX_AGENTE (sem ela, `principal`). Linha
#      atribuida a OUTRO agente nao herda esses valores: o veredito do auditor-plano e gravado
#      pelo principal, e o modelo do principal nao e o do auditor.
#   2. O frontmatter de .claude/agents/<agente>.md so completa o snapshot de um subagente, e so
#      no harness Claude (`claude` ou `claude-code`). OpenCode, Codex ou runtime sem sinal nunca
#      recebem uma configuracao Claude que podem nao ter usado.
#   3. `principal` nao tem arquivo: sem dado do runtime, fica null em vez de inventar.
#
# Bash 3.2 (macOS) compativel. Sem processo novo.

# _execucao_frontmatter_em <var> <arquivo> <campo> — valor simples do frontmatter, ou vazio.
# YAML mais complexo que `campo: valor` falha aberto: vazio, nunca evidencia parcial.
_execucao_frontmatter_em() {
  local _l _c _v _dentro=0
  printf -v "$1" '%s' ""
  [ -f "$2" ] || return 0
  while IFS= read -r _l || [ -n "$_l" ]; do
    _l="${_l%$'\r'}"
    if [ "$_l" = "---" ]; then
      if [ "$_dentro" -eq 0 ]; then _dentro=1; continue; fi
      break
    fi
    [ "$_dentro" -eq 1 ] || continue
    case "$_l" in *:*) ;; *) continue ;; esac
    _c="${_l%%:*}"; _c="${_c//[[:space:]]/}"; _c="${_c//\"/}"; _c="${_c//\'/}"
    [ "$_c" = "$3" ] || continue
    _v="${_l#*:}"
    _v="${_v#"${_v%%[![:space:]]*}"}"
    _v="${_v%"${_v##*[![:space:]]}"}"
    case "$_v" in
      \"*\") _v="${_v#\"}"; _v="${_v%\"}" ;;
      \'*\') _v="${_v#\'}"; _v="${_v%\'}" ;;
    esac
    # IDs de qualquer provedor usam, alem do alfanumerico, . _ : / -.
    case "$_v" in ""|*[!A-Za-z0-9._:/-]*) return 0 ;; esac
    printf -v "$1" '%s' "$_v"
    return 0
  done < "$2"
}

# _execucao_json_em <var> <valor> — string JSON, ou null quando vazio.
_execucao_json_em() {
  local _v="$2"
  if [ -z "$_v" ]; then printf -v "$1" '%s' null; return 0; fi
  _v="${_v//\\/\\\\}"; _v="${_v//\"/\\\"}"
  printf -v "$1" '"%s"' "$_v"
}

# execucao_extras_em <var> <raiz> <agente> <harness>
#
# Devolve `"model":...,"effort":...`, para ir depois das doze chaves. <harness> e o que o
# chamador ja derivou; vazio quando a linha e sempre do principal, que nao tem fallback.
execucao_extras_em() {
  local _agente="${3:-principal}" _harness="${4:-}" _m="" _e="" _arq _mj _ej
  if [ "$_agente" = "${EXPX_AGENTE:-principal}" ]; then
    _m="${EXPX_MODEL:-}"; _e="${EXPX_EFFORT:-}"
  fi
  # Caractere de controle nao e identificador de modelo: o valor nao vira evidencia.
  case "$_m" in *[[:cntrl:]]*) _m="" ;; esac
  case "$_e" in *[[:cntrl:]]*) _e="" ;; esac
  case "$_harness" in
    claude|claude-code)
      case "$_agente" in
        ""|principal|*..*|*[!A-Za-z0-9._-]*) ;;
        *)
          _arq="$2/.claude/agents/$_agente.md"
          [ -n "$_m" ] || _execucao_frontmatter_em _m "$_arq" model
          [ -n "$_e" ] || _execucao_frontmatter_em _e "$_arq" effort
          ;;
      esac
      ;;
  esac
  _execucao_json_em _mj "$_m"; _execucao_json_em _ej "$_e"
  printf -v "$1" '"model":%s,"effort":%s' "$_mj" "$_ej"
}
