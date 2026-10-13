#!/usr/bin/env bash
# mutacao-predecessores.sh — certifica o contrato matando mutantes obrigatórios.
set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
K="$(mktemp -d)"
trap 'rm -rf "$K"' EXIT HUP INT TERM

mortos=0
falhou=0

passa() {
  [ "$1" = CONTROLE ] || mortos=$((mortos + 1))
  printf '  ok    %-10s %s: %s\n' "$1" "$( [ "$1" = CONTROLE ] && printf verde || printf 'morto por' )" "$2"
}
reprova() { falhou=$((falhou + 1)); printf '  FALHA %-10s sobreviveu: %s\n' "$1" "$2"; }

prepara() { # prepara <nome>
  CASO="$K/$1"
  mkdir -p "$CASO"
  cp -R "$RAIZ/.claude" "$CASO/.claude"
  cp -R "$RAIZ/.opencode" "$CASO/.opencode"
  cp -R "$RAIZ/scripts" "$CASO/scripts"
  cp "$RAIZ/README.md" "$CASO/README.md"
}

substitui() { # substitui <arquivo> <antigo> <novo>
  python3 - "$1" "$2" "$3" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
old, new = sys.argv[2], sys.argv[3]
text = p.read_text(encoding="utf-8")
if old not in text:
    raise SystemExit(f"mutacao nao aplicada em {p}: {old!r}")
p.write_text(text.replace(old, new), encoding="utf-8", newline="")
PY
}

mata() { # mata <nome> <grupo>
  local nome="$1" grupo="$2" saida rc
  saida="$(cd "$CASO" && bash scripts/ci/test-predecessores.sh "$grupo" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then passa "$nome" "$grupo"
  else reprova "$nome" "$grupo terminou verde"; fi
}

echo '== controle =='
controle="$(bash "$RAIZ/scripts/ci/test-predecessores.sh" todos 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  passa CONTROLE "$(printf '%s\n' "$controle" | tail -1)"
else
  reprova CONTROLE "suite original vermelha: $(printf '%s\n' "$controle" | tail -3 | tr '\n' ' ')"
fi

echo '== mutantes =='

prepara PREFIXO
substitui "$CASO/.claude/skills/sprintx/references/01-ingestao.md" \
  'não faça varredura automática' 'faça varredura automática'
mata PREFIXO contrato

prepara GLOB
substitui "$CASO/.claude/skills/sprintx/scripts/predecessores.sh" \
  '|*\**|*\?*|*\[*|*\]*)' ')'
mata GLOB caminhos

prepara DISCO
substitui "$CASO/.claude/skills/sprintx/scripts/predecessores.sh" \
  'b="$(modo_blob HEAD "$caminho")"' 'b="$a"'
mata DISCO contrato

prepara HEADBLOB
substitui "$CASO/.claude/skills/sprintx/scripts/predecessores.sh" \
  '[ "$oid_head" = "$blob" ] || falha "$E_PROVA" "blob atual diverge do predecessor: $caminho"' \
  ': # mutante HEADBLOB ignora o blob atual'
mata HEADBLOB historia

prepara POSTERIOR
substitui "$CASO/.claude/skills/sprintx/scripts/predecessores.sh" \
  'git -C "$RAIZ" merge-base --is-ancestor "$commit" "$nascimento" >/dev/null 2>&1' \
  'git -C "$RAIZ" merge-base --is-ancestor "$nascimento" HEAD >/dev/null 2>&1'
mata POSTERIOR historia

prepara IGUAL
substitui "$CASO/.claude/skills/sprintx/scripts/predecessores.sh" \
  '[ "$commit" != "$nascimento" ] || falha "$E_PROVA" '\''predecessor nasceu junto com o planejamento'\''' \
  ': # mutante IGUAL aceita o commit de nascimento'
mata IGUAL historia

prepara PARCIAL
substitui "$CASO/.claude/skills/sprintx/scripts/predecessores.sh" \
  '    prova_item "$caminho" "$origem" "$papel" "$commit" "$blob"' \
  '    ( prova_item "$caminho" "$origem" "$papel" "$commit" "$blob" ) || true'
mata PARCIAL schema

prepara AUSENCIA
substitui "$CASO/.claude/skills/sprintx/scripts/planejamento.sh" \
  '      || falha "$E_CONTRATO" '\''00-PREDECESSORES.md invalido; F2 nao alterou estado, stage ou rastro'\''' \
  '      || true # mutante AUSENCIA trata manifesto invalido como ausente'
mata AUSENCIA checkpoint

prepara SUJO
substitui "$CASO/.claude/skills/sprintx/scripts/predecessores.sh" \
  'git -C "$RAIZ" diff --quiet -- "$caminho"' 'true'
substitui "$CASO/.claude/skills/sprintx/scripts/predecessores.sh" \
  'git -C "$RAIZ" diff --cached --quiet -- "$caminho"' 'true'
mata SUJO estado-git

prepara SHAINPUT
substitui "$CASO/.claude/skills/sprintx/scripts/predecessores.sh" \
  '[ "$#" -eq 6 ] || uso' '[ "$#" -ge 6 ] || uso'
mata SHAINPUT registro

prepara EVENTO
printf '\nEvento proibido de mutacao: predecessor_registrado\n' >> "$CASO/.claude/skills/sprintx/references/08-rastro.md"
mata EVENTO contrato

printf '\n  %s mutantes mortos, %s sobreviventes\n' "$mortos" "$falhou"
[ "$falhou" -eq 0 ]
