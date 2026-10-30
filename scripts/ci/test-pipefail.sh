#!/usr/bin/env bash
#
# test-pipefail — roda so a secao AN da bancada (consumidor que sai cedo sob pipefail), com os
# auxiliares minimos dela, para o CI cobrar as quatro conversoes da DS-192 sem a bancada inteira.
#
#   bash scripts/ci/test-pipefail.sh
set -uo pipefail

RAIZ_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
H="$RAIZ_SRC/.claude/hooks"
SK="$H/../skills/sprintx"
SEM_FONTE="bancada instalada, sem o repositorio da sprintx"
ok=0; falhou=0; pulado_externo=0
afirma() { # afirma <nome> <condicao-ja-avaliada:0|1> <detalhe>
  if [ "$2" -eq 0 ]; then ok=$((ok+1)); printf '  ok   %-46s %s\n' "$1" "$3"
  else falhou=$((falhou+1)); printf '  FALHA %-45s %s\n' "$1" "$3"; fi
}
pula_externo() { pulado_externo=$((pulado_externo+1)); printf '  dep  %-46s dependencia externa ausente: %s\n' "$1" "$2"; }

# shellcheck source=../../.claude/hooks/testes/bancada-pipefail.sh
. "$H/testes/bancada-pipefail.sh"

echo
echo "  $ok ok, $falhou falhas, $pulado_externo por dependencia externa ausente"
[ "$falhou" -eq 0 ] && [ "$pulado_externo" -eq 0 ]
