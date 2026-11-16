#!/usr/bin/env bash
#
# test-comandos-com-caminho — todo comando de script da skill citado no 06-execucao.md sai com o
# caminho `<raiz-da-skill>/scripts/`: o script nao esta no PATH (DM-314), e um `planejamento.sh
# criar ...` solto nao executa (CodeAnt no login#95).
#
#   bash scripts/ci/test-comandos-com-caminho.sh [arquivo]
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ALVO="${1:-$R/.claude/skills/sprintx/references/06-execucao.md}"
scripts=""; for f in "$R"/.claude/skills/sprintx/scripts/*.sh; do b="${f##*/}"; scripts="$scripts${scripts:+|}${b%.sh}"; done
# comando para copiar: trecho de codigo inline (que pode quebrar linha) comecando pelo nome do
# script, sem o caminho antes, e com argumento (`<slug>` e afins); o nome sozinho
# (`bloqueios.sh resolver`) e citacao. O arquivo e lido inteiro, nao linha a linha (CodeAnt no sprintx#85)
soltos="$(SCRIPTS="$scripts" perl -0777 -ne '
  my $re = $ENV{SCRIPTS};
  while (/`((?:$re)\.sh [^`]*<[^`]*)`/g) {
    my $linha = 1 + (substr($_, 0, $-[0]) =~ tr/\n//);
    (my $t = $1) =~ s/\s+/ /g;
    print "$linha:`$t`\n";
  }' "$ALVO")"
if [ -z "$soltos" ]; then
  echo '  ok    nenhum comando de script solto no 06-execucao.md'
  exit 0
fi
echo '  FALHA comandos de script sem o caminho <raiz-da-skill>/scripts/ no 06-execucao.md:'
printf '%s\n' "$soltos" | sed 's/^/        /'
exit 1
