#!/usr/bin/env bash
# rastro-post — PostToolUse. Grava `arquivo_alterado` e `suite_executada`.
#
# Contrato, regra 7: "Sempre grava no rastro, inclusive quando permite."
# Este e o hook que cumpre isso para as duas acoes que o painel precisa ver.
#
# O par (arquivo_alterado, suite_executada) e o que da ao painel a linha do
# tempo do trabalho — e, junto com task_iniciada/task_concluida gravados pela
# skill, a duracao observada que entra no HISTORICO.md ao lado do real — fora da
# calibracao, que agrega o desvio sobre o real (references/08-rastro.md).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./rastro.sh
. "$DIR/rastro.sh"

ENTRADA="$(cat)"
CWD="$(rastro_json_get "$ENTRADA" cwd)"
[ -n "$CWD" ] || CWD="$PWD"
# Caminho do payload (no Windows, C:\dir com caixa de drive variavel) sempre pelo helper.
rastro_caminho_em CWD "$CWD"
RAIZ="$(rastro_raiz "$CWD")"

FERRAMENTA="$(rastro_json_get "$ENTRADA" tool_name)"

case "$FERRAMENTA" in
  Write|Edit|MultiEdit|NotebookEdit)
    ALVO="$(rastro_tool_input_get "$ENTRADA" file_path)"
    [ -n "$ALVO" ] || exit 0
    rastro_caminho_em ALVO "$ALVO"
    REL="${ALVO#"$RAIZ"/}"
    rastro_grava "$RAIZ" arquivo_alterado hook ok "$FERRAMENTA" "[\"$(rastro_json_escape "$REL")\"]"
    ;;
  Bash)
    CMD="$(rastro_tool_input_get "$ENTRADA" command)"
    [ -n "$CMD" ] || exit 0
    # So comandos que sao mesmo execucao de suite.
    case "$CMD" in
      *"npm test"*|*"npm run test"*|*"yarn test"*|*"pnpm test"*|\
      *pytest*|*"go test"*|*"cargo test"*|*jest*|*vitest*|*rspec*|*phpunit*|*"dotnet test"*|*"mvn test"*)
        # resultado da suite: o painel quer saber se passou.
        #
        # O texto sai pelo helper que aceita `tool_response` como string E como objeto (no Bash o
        # Claude Code entrega `{"stdout":...,"stderr":...}`), nas duas rotas de leitura; e a cor
        # do terminal e removida ANTES de classificar, porque Maven e Surefire colam a sequencia
        # ANSI nos dois lados de `[ERROR]` e de `BUILD FAILURE` e assim apagam a fronteira de
        # espaco em branco que os padroes abaixo procuram — suite vermelha gravada como `ok`.
        rastro_tool_response_em SAIDA "$ENTRADA"
        rastro_sem_ansi_em SAIDA "$SAIDA"
        RES="ok"
        # Cuidado com "0 failed", que e o caso VERDE e aparece em quase toda
        # saida de suite: o [1-9] no inicio do numero e o que separa os dois.
        if printf '%s' "$SAIDA" | grep -qE '(^|[^0-9])[1-9][0-9]* (failed|failing|error)'; then
          RES="falha"
        elif printf '%s' "$SAIDA" | grep -qE '(^|[[:space:]])(FAILED|FAIL)([[:space:]]|$)'; then
          RES="falha"
        elif printf '%s' "$SAIDA" | grep -qE '(^|[[:space:]])(\[ERROR\]|BUILD[[:space:]]+FAILURE)([[:space:]]|$)'; then
          RES="falha"
        fi
        # `detalhe` e uma linha pelo contrato. Normalize quebras antes de cortar em 120 BYTES,
        # sem partir caractere UTF-8 multibyte e sem depender da locale: `cut -c` faria o corte
        # depender da locale e o repetiria por linha (ver rastro_corta_utf8_em).
        DETALHE="${CMD//$'\r\n'/ }"
        DETALHE="${DETALHE//$'\r'/ }"
        DETALHE="${DETALHE//$'\n'/ }"
        rastro_corta_utf8_em DETALHE "$DETALHE" 120
        rastro_grava "$RAIZ" suite_executada hook "$RES" "$DETALHE" '[]'
        ;;
    esac
    ;;
esac

exit 0
