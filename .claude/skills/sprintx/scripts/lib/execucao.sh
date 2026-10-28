#!/usr/bin/env bash
# execucao.sh — o executor observado e a resolucao de uma linha do rastro (DS-186, DS-190).
#
# Nao e executavel: scripts/rastro.sh, planejamento.sh e bloqueios.sh fazem `source`.
# Registra o executor efetivo; nao escolhe modelo, harness nem esforco. As regras sao as do
# escritor comum do ExpxDev (CONTRATO-expx-orquestracao, H10), para qualquer harness:
#
#   1. EXPX_MODEL e EXPX_EFFORT descrevem o executor EXPX_AGENTE (sem ela, `principal`). Linha
#      atribuida a OUTRO agente nao herda esses valores: o veredito do auditor-plano e gravado
#      pelo principal, e o modelo do principal nao e o do auditor.
#   2. No contexto Claude, $CLAUDE_EFFORT e o esforco da SESSAO: observacao do principal, e so
#      dele, e so quando EXPX_EFFORT nao veio.
#   3. Nunca configuracao: frontmatter de .claude/agents/, resolucao ou alternativa nao entram
#      em `model`/`effort`. Sem observacao, null. Ate a DS-190, o frontmatter completava o
#      subagente no Claude, o que gravava configuracao como execucao.
#   4. A intencao vai em chaves SEPARADAS: com a projecao `.expx/orquestracao-rastro.tsv`
#      (gravada pelo `expx init` com a politica de orquestracao ativa), a linha de um subagente
#      no Claude leva a resolucao dele. Sem o ExpxDev, ou sem politica, nao ha projecao, e nada
#      muda. Falha aberta: projecao fora do formato nao grava chave nenhuma, nunca parte delas.
#
# O contexto Claude e EXPX_HARNESS igual a `claude`/`claude-code` ou, sem EXPX_HARNESS, a
# CLAUDECODE que o Claude Code exporta — a mesma regra do escritor comum.
#
# Bash 3.2 (macOS) compativel. Sem processo novo.

# _execucao_resolucao_em <var> <raiz> <agente> — as chaves da resolucao do agente na projecao
# (CONTRATO-expx-orquestracao §11.2), ou vazio. Cabecalho, linha sem exatamente oito TABs,
# campo vazio ou fora do alfabeto, `resolucao_id` fora do formato, agente repetido ou
# `materializado` fora da excecao do agentes.json v1: vazio. Os campos so aceitam o que dispensa
# escape em JSON, entao entram literais.
_execucao_resolucao_em() {
  local _arq="$2/.expx/orquestracao-rastro.tsv" _agente="$3" _cab="" _linha _tabs _v _out="" _achadas=0
  local _ag _id _cd _oc _cr _alt _oa _mm _me
  printf -v "$1" '%s' ""
  [ -f "$_arq" ] || return 0
  IFS= read -r _cab < "$_arq" || true
  [ "${_cab%$'\r'}" = "# expx-orquestracao-rastro 1" ] || return 0
  case "$_agente" in ""|*[!A-Za-z0-9._-]*) return 0 ;; esac
  while IFS= read -r _linha || [ -n "$_linha" ]; do
    _linha="${_linha%$'\r'}"
    case "$_linha" in "$_agente"$'\t'*) ;; *) continue ;; esac
    # agente repetido: so se sabe no fim do arquivo — conta e segue; a decisao vem depois
    _achadas=$((_achadas + 1))
    [ "$_achadas" -eq 1 ] || continue
    # exatamente oito TABs, contados na linha crua: o `read` com IFS de TAB juntaria coluna vazia
    _tabs="${_linha//[!$'\t']/}"
    [ "${#_tabs}" -eq 8 ] || return 0
    IFS=$'\t' read -r _ag _id _cd _oc _cr _alt _oa _mm _me <<EXECUCAO_PROJECAO
$_linha
EXECUCAO_PROJECAO
    case "$_id" in ""|*[!0-9a-f]*) return 0 ;; esac
    [ "${#_id}" -eq 64 ] || return 0
    for _v in "$_ag" "$_cd" "$_oc" "$_cr" "$_alt" "$_oa" "$_mm" "$_me"; do
      case "$_v" in ""|*[!A-Za-z0-9._:/-]*) return 0 ;; esac
    done
    # `-` so e ausencia nas duas colunas do materializado, que so existe na excecao v1, com model
    for _v in "$_cd" "$_oc" "$_cr" "$_alt" "$_oa"; do [ "$_v" != - ] || return 0; done
    [ "$_mm" != - ] || [ "$_me" = - ] || return 0
    [ "$_mm" = - ] || [ "$_oa" = agentes-json-v1 ] || return 0
    _out="\"resolucao_id\":\"$_id\",\"classe_declarada\":\"$_cd\",\"classe_resolvida\":\"$_cr\""
    _out="$_out,\"origem_classe\":\"$_oc\",\"alternativa\":\"$_alt\",\"origem_alternativa\":\"$_oa\""
    if [ "$_mm" != - ]; then
      if [ "$_me" != - ]; then _out="$_out,\"materializado\":{\"model\":\"$_mm\",\"effort\":\"$_me\"}"
      else _out="$_out,\"materializado\":{\"model\":\"$_mm\"}"
      fi
    fi
  done < "$_arq"
  [ "$_achadas" -eq 1 ] || return 0
  printf -v "$1" '%s' "$_out"
}

# _execucao_json_em <var> <valor> — string JSON, ou null quando vazio.
_execucao_json_em() {
  local _v="$2"
  if [ -z "$_v" ]; then printf -v "$1" '%s' null; return 0; fi
  _v="${_v//\\/\\\\}"; _v="${_v//\"/\\\"}"
  printf -v "$1" '"%s"' "$_v"
}

# execucao_extras_em <var> <raiz> <agente> [harness]
#
# Devolve `"model":...,"effort":...` e, para subagente no Claude com projecao valida, as chaves
# da resolucao — para ir depois das doze chaves. [harness] e o que o chamador ja derivou (a
# identidade do rastro.sh); vazio, o helper detecta pela regra do escritor comum.
execucao_extras_em() {
  local _agente="${3:-principal}" _harness="${4:-}" _m="" _e="" _mj _ej _res
  if [ -z "$_harness" ]; then
    _harness="${EXPX_HARNESS:-}"
    [ -z "$_harness" ] && [ -n "${CLAUDECODE:-}" ] && _harness=claude-code
  fi
  if [ "$_agente" = "${EXPX_AGENTE:-principal}" ]; then
    _m="${EXPX_MODEL:-}"; _e="${EXPX_EFFORT:-}"
  fi
  case "$_harness" in
    claude|claude-code)
      [ -z "$_e" ] && [ "$_agente" = principal ] && _e="${CLAUDE_EFFORT:-}"
      ;;
  esac
  # Caractere de controle nao e identificador de modelo: o valor nao vira evidencia.
  case "$_m" in *[[:cntrl:]]*) _m="" ;; esac
  case "$_e" in *[[:cntrl:]]*) _e="" ;; esac
  _execucao_json_em _mj "$_m"; _execucao_json_em _ej "$_e"
  _res=""
  case "$_harness" in
    claude|claude-code)
      [ "$_agente" = principal ] || _execucao_resolucao_em _res "$2" "$_agente"
      ;;
  esac
  printf -v "$1" '"model":%s,"effort":%s%s' "$_mj" "$_ej" "${_res:+,$_res}"
  return 0
}
