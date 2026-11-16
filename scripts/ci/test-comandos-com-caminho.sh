#!/usr/bin/env bash
#
# test-comandos-com-caminho — todo comando de script da skill citado no 06-execucao.md sai com o
# caminho `<raiz-da-skill>/scripts/`: o script nao esta no PATH (DM-314), e um `planejamento.sh
# criar ...` solto nao executa (CodeAnt no login#95).
#
#   bash scripts/ci/test-comandos-com-caminho.sh
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ALVO="$R/.claude/skills/sprintx/references/06-execucao.md"
scripts="$(cd "$R/.claude/skills/sprintx/scripts" && ls -- *.sh | sed 's/\.sh$//' | paste -sd'|' -)"
# trecho de codigo inline que comeca pelo nome do script, sem o caminho antes
soltos="$(grep -noE "\`($scripts)\.sh [^\`]*\`" "$ALVO")"
if [ -z "$soltos" ]; then
  echo '  ok    nenhum comando de script solto no 06-execucao.md'
  exit 0
fi
echo '  FALHA comandos de script sem o caminho <raiz-da-skill>/scripts/ no 06-execucao.md:'
printf '%s\n' "$soltos" | sed 's/^/        /'
exit 1
