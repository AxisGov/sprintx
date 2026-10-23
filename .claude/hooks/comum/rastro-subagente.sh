#!/usr/bin/env bash
# rastro-subagente — SubagentStop. Grava `agente_concluido`.
#
# E o que permite ao painel responder "quem fez o que": filtro por agente,
# com o que cada um tocou e que veredito emitiu.
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

AGENTE="$(rastro_json_get "$ENTRADA" agent_type)"
case "$AGENTE" in
  principal|auditor-plano|sprintx-revisor-testes|sprintx-investigador|runx-revisor-testes|runx-investigador|qa|legadox-cartografo|avaliador-de-raio|stackx-cartografo|revisor-diff|analista-de-conflito|auditor-design|cartografo-visual) ;;
  *) AGENTE="principal" ;;
esac

RASTRO_AGENTE="$AGENTE"
rastro_grava "$RAIZ" agente_concluido hook ok "subagente $AGENTE encerrou" '[]'
exit 0
