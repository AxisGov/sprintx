#!/usr/bin/env bash
# rastro.sh — o escritor publico dos eventos que a skill grava no rastro (DS-159).
#
# O agente diz O QUE aconteceu (evento, trabalho, task, detalhe); o mecanismo deriva o resto:
# instante, sessao, harness, arquivo de destino e a linha JSON inteira. Nenhum desses entra
# por argumento — a identidade que o `escopo-da-task` le e a mesma que este script grava
# porque as duas saem da mesma funcao (`rastro_identidade_em`, em `.claude/hooks/comum/rastro.sh`).
#
# Nao ha segunda implementacao aqui: identidade, destino (`rastro_grava_trabalho`, DS-155),
# rotacao e serializacao sao os da biblioteca dos hooks, carregada da raiz do projeto.
#
# Uso (a partir de qualquer diretorio do repositorio; SPRINTX_RAIZ sobrescreve a raiz):
#
#   rastro.sh task-iniciada  <slug> <T-NN.MM> [detalhe]
#   rastro.sh task-concluida <slug> <T-NN.MM> [detalhe] [arquivo ...]
#   rastro.sh task-bloqueada <slug> <T-NN.MM> [detalhe]
#   rastro.sh fase-iniciada  <slug> <f1..f6> [detalhe]
#   rastro.sh fase-concluida <slug> <f1..f6> [detalhe]
#   rastro.sh veredito-emitido <slug> <SIM|NAO> [detalhe]
#
# Os tres `task-*` sao lidos pelo enforcement (reivindicacao da sessao: escopo-da-task,
# task-reivindicada, arvore-limpa) e EXIGEM identidade: sem ela, nada e gravado. Os
# demais levam a identidade quando ela existe e nao dependem dela.
#
# Codigos de saida — em todo codigo diferente de 0, NENHUMA linha entrou no rastro do trabalho:
#   0  gravado
#   3  identidade da sessao indisponivel neste processo (evento task-*)
#   4  contrato: trabalho sem pasta, task fora do plano do trabalho, ou a sessao ja reivindica
#      outro trabalho (contexto_de_trabalho_divergente, registrado em sem-trabalho.jsonl)
#   5  ambiente: biblioteca do rastro nao encontrada (hooks da sprintx nao instalados) ou
#      falha de escrita
#   64 uso incorreto

set -uo pipefail

SK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

E_IDENTIDADE=3; E_CONTRATO=4; E_AMBIENTE=5; E_USO=64

falha() { local c="$1"; shift; printf 'rastro: %s\n' "$*" >&2; exit "$c"; }

uso() {
  falha "$E_USO" "uso: rastro.sh <task-iniciada|task-concluida|task-bloqueada> <slug> <T-NN.MM> [detalhe] [arquivo ...]
       rastro.sh <fase-iniciada|fase-concluida> <slug> <f1..f6> [detalhe]
       rastro.sh veredito-emitido <slug> <SIM|NAO> [detalhe]"
}

. "$SK/scripts/caminho-git.sh" || falha "$E_AMBIENTE" "scripts/caminho-git.sh ausente"

resolve_raiz() {
  if [ -n "${SPRINTX_RAIZ:-}" ]; then printf '%s' "$SPRINTX_RAIZ"; return; fi
  local t; t="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$t" ] && { caminho_git "$t"; return; }
  printf '%s' "$PWD"
}

[ $# -ge 3 ] || uso
CMD="$1" SLUG="$2" ALVO="$3"; shift 3
DETALHE="${1:-}"; [ $# -gt 0 ] && shift

case "$CMD" in
  task-iniciada|task-concluida|task-bloqueada|fase-iniciada|fase-concluida|veredito-emitido) ;;
  *) uso ;;
esac
case "$CMD" in task-concluida) ;; *) [ $# -eq 0 ] || uso ;; esac

RAIZ="$(resolve_raiz)"

# A biblioteca dos hooks: a do projeto (a que o enforcement usa), senao a instalada ao lado
# desta skill (.claude/skills/sprintx -> .claude/hooks). Sem ela nao ha como derivar a
# identidade que o hook vai ler — e montar a linha por conta propria seria a segunda
# implementacao que esta DS proibe.
LIB=""
for c in "$RAIZ/.claude/hooks/comum/rastro.sh" "$SK/../../hooks/comum/rastro.sh"; do
  [ -f "$c" ] && { LIB="$c"; break; }
done
[ -n "$LIB" ] || falha "$E_AMBIENTE" "biblioteca do rastro ausente (.claude/hooks/comum/rastro.sh): os hooks da sprintx nao estao instalados neste projeto. Nada foi gravado; nao grave o evento a mao."
# shellcheck source=../../../hooks/comum/rastro.sh
. "$LIB" || falha "$E_AMBIENTE" "biblioteca do rastro ilegivel: $LIB"

rastro_trabalho_valido "$SLUG" || falha "$E_USO" "slug invalido: '$SLUG'"
if [ -d "$RAIZ/docs/sprintx/features/$SLUG" ]; then PASTA="$RAIZ/docs/sprintx/features/$SLUG"
elif [ -d "$RAIZ/docs/$SLUG" ]; then PASTA="$RAIZ/docs/$SLUG"
else falha "$E_CONTRATO" "trabalho '$SLUG' sem pasta (docs/sprintx/features/$SLUG/): nada foi gravado"
fi

# ------------------------------------------------------------ o que o agente declarou
RASTRO_AGENTE=principal
EXIGE_IDENTIDADE=0
ARQUIVOS='[]'
case "$CMD" in
  task-*)
    case "$ALVO" in T-[0-9]*.[0-9]*) ;; *) falha "$E_USO" "task invalida: '$ALVO' (T-NN.MM)" ;; esac
    case "$ALVO" in *[!A-Za-z0-9.-]*) falha "$E_USO" "task invalida: '$ALVO' (T-NN.MM)" ;; esac
    # A task precisa estar no plano DESTE trabalho: o id e local a feature (DS-153).
    achou=0; re="${ALVO//./[.]}"
    for f in "$PASTA"/sprint-*/tasks.md; do
      [ -f "$f" ] || continue
      if tr -d '\r' < "$f" | grep -Eq "^  - id:[[:space:]]*$re[[:space:]]*\$"; then achou=1; break; fi
    done
    [ "$achou" = 1 ] || falha "$E_CONTRATO" "task $ALVO nao esta no plano do trabalho '$SLUG': nada foi gravado"
    EVENTO="${CMD/-/_}"; RASTRO_FASE='"f6"'; RASTRO_TASK="\"$ALVO\""; EXIGE_IDENTIDADE=1
    case "$CMD" in
      task-iniciada)  RESULTADO=ok;        [ -n "$DETALHE" ] || DETALHE="$ALVO aberta" ;;
      task-concluida) RESULTADO=ok;        [ -n "$DETALHE" ] || DETALHE="$ALVO concluida" ;;
      task-bloqueada) RESULTADO=bloqueado; [ -n "$DETALHE" ] || DETALHE="$ALVO bloqueada" ;;
    esac
    if [ "$CMD" = task-concluida ] && [ $# -gt 0 ]; then
      ARQUIVOS=""
      for a in "$@"; do rastro_json_escape_em e "$a"; ARQUIVOS="$ARQUIVOS${ARQUIVOS:+,}\"$e\""; done
      ARQUIVOS="[$ARQUIVOS]"
    fi
    ;;
  fase-*)
    case "$ALVO" in f[1-6]) ;; *) falha "$E_USO" "fase invalida: '$ALVO' (f1..f6)" ;; esac
    EVENTO="${CMD/-/_}"; RASTRO_FASE="\"$ALVO\""; RASTRO_TASK=null; RESULTADO=ok
    [ -n "$DETALHE" ] || DETALHE="$ALVO"
    ;;
  veredito-emitido)
    case "$ALVO" in SIM|NAO) ;; *) falha "$E_USO" "veredito invalido: '$ALVO' (SIM|NAO)" ;; esac
    EVENTO=veredito_emitido; RASTRO_FASE='"f5"'; RASTRO_TASK=null; RESULTADO=ok
    RASTRO_AGENTE=auditor-plano
    DETALHE="VEREDITO: $ALVO${DETALHE:+ — $DETALHE}"
    ;;
esac

# ------------------------------------------------------------ o que o mecanismo deriva
if rastro_identidade_em SESSAO HARNESS; then
  rastro_json_escape_em SESSAO_E "$SESSAO"; rastro_json_escape_em HARNESS_E "$HARNESS"
  EXTRAS="\"sessao\":\"$SESSAO_E\",\"harness\":\"$HARNESS_E\""
elif [ "$EXIGE_IDENTIDADE" = 1 ]; then
  falha "$E_IDENTIDADE" "identidade da sessao indisponivel neste processo: o harness nao expos a sessao (EXPX_SESSAO ou CLAUDE_CODE_SESSION_ID). $EVENTO NAO foi gravado. Nao grave o evento a mao nem invente a sessao: registre um bloqueio prerequisito_ausente (scripts/bloqueios.sh registrar)."
else
  EXTRAS='"sessao":null,"harness":null'
fi

rastro_grava_trabalho "$RAIZ" "$SLUG" "$EVENTO" skill "$RESULTADO" "$DETALHE" "$ARQUIVOS" "$EXTRAS"
case "${RASTRO_GRAVACAO:-falha}" in
  gravado) ;;
  divergente) falha "$E_CONTRATO" "contexto_de_trabalho_divergente: esta sessao ja reivindica outro trabalho (task aberta sem fechamento). $EVENTO NAO foi gravado em '$SLUG'; feche a task aberta do outro trabalho antes." ;;
  invalido)   falha "$E_USO" "slug invalido: '$SLUG'" ;;
  *)          falha "$E_AMBIENTE" "falha de escrita em docs/eventos/$SLUG.jsonl: $EVENTO NAO foi gravado" ;;
esac

printf 'evento=%s\ntrabalho=%s\n' "$EVENTO" "$SLUG"
case "$CMD" in task-*) printf 'task=%s\n' "$ALVO" ;; esac
printf 'rastro=docs/eventos/%s.jsonl\nidentidade=%s\n' "$SLUG" "$([ -n "${SESSAO:-}" ] && echo derivada || echo ausente)"
