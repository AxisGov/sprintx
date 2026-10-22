#!/usr/bin/env bash
set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$raiz"

legada='((github\.com[/:]|raw\.githubusercontent\.com/)bittencourtthulio/(runx|mergex|sprintx|buildx|expxdev)(\.git)?|bittencourtthulio\.github\.io/expxdev)'
for exemplo in \
  'https://github.com/bittencourtthulio/runx.git' \
  'git@github.com:bittencourtthulio/mergex.git' \
  'ssh://git@github.com/bittencourtthulio/sprintx.git' \
  'git://github.com/bittencourtthulio/buildx.git' \
  'https://raw.githubusercontent.com/bittencourtthulio/runx/main/SKILL.md'
do
  printf '%s\n' "$exemplo" | grep -Eq "$legada" || {
    printf 'regex nao reconheceu origem legada: %s\n' "$exemplo" >&2
    exit 1
  }
done
alvos=(README.md AGENTS.md CLAUDE.md package.json .claude .opencode docs install.sh sincronizar-espelho.sh scripts .github)
achados="$(grep -RInE --exclude=test-proveniencia.sh "$legada" "${alvos[@]}" 2>/dev/null || true)"
[ -z "$achados" ] || {
  printf 'origem legada em caminho operacional:\n%s\n' "$achados" >&2
  exit 1
}

for repo in runx mergex sprintx buildx expxdev; do
  grep -q "https://github.com/AxisGov/$repo" README.md || {
    printf 'README sem origem canonica AxisGov/%s\n' "$repo" >&2
    exit 1
  }
done

grep -q '^  pull_request:$' .github/workflows/proveniencia.yml
! grep -q '^[[:space:]]*paths:' .github/workflows/proveniencia.yml || {
  printf 'workflow de proveniencia nao pode limitar caminhos de pull request\n' >&2
  exit 1
}

printf 'proveniencia AxisGov verificada\n'
