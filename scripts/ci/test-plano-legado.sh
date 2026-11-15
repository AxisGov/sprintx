#!/usr/bin/env bash
#
# test-plano-legado — roda so a secao AR da bancada (defeito_de_plano num plano legado, DS-224),
# com os auxiliares minimos dela, para o CI cobrar a mensagem do `bloqueios.sh resolver` e a
# migracao sem a bancada inteira.
#
#   bash scripts/ci/test-plano-legado.sh
set -uo pipefail

RAIZ_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
H="$RAIZ_SRC/.claude/hooks"
SK="$H/../skills/sprintx"
ok=0; falhou=0
afirma() { # afirma <nome> <condicao-ja-avaliada:0|1> <detalhe>
  if [ "$2" -eq 0 ]; then ok=$((ok+1)); printf '  ok   %-46s %s\n' "$1" "$3"
  else falhou=$((falhou+1)); printf '  FALHA %-45s %s\n' "$1" "$3"; fi
}

# shellcheck source=../../.claude/hooks/testes/bancada-plano-legado.sh
. "$H/testes/bancada-plano-legado.sh"

echo
echo "  $ok ok, $falhou falhas"
[ "$falhou" -eq 0 ] && [ "$ok" -gt 0 ]
