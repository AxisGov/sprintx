#!/usr/bin/env bash
#
# test-hooks-fora-do-projeto — os hooks de aviso ignoram o que nao e do projeto: fora da raiz,
# ignorado pelo Git, worktree aninhado e pasta oculta de topo sem nada versionado (rascunho de
# ferramenta). No conselhos (2026-11-16), 85% dos avisos eram desses caminhos.
#
#   bash scripts/ci/test-hooks-fora-do-projeto.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX

RAIZ_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
H="$RAIZ_SRC/.claude/hooks"
ok=0; falhou=0
afirma() { if [ "$2" -eq 0 ]; then ok=$((ok+1)); printf '  ok    %s\n' "$1"; else falhou=$((falhou+1)); printf '  FALHA %s\n' "$1"; fi; }
g() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

aux="$(mktemp -d)"; trap 'rm -rf "$aux"' EXIT
R="$aux/proj"
git init -q -b main "$R"; git -C "$R" config core.autocrlf false
mkdir -p "$R/src" "$R/docs/stack" "$R/.github" "$R/.pylot-tmp/wt/src" "$R/.expxv/x/src" "$R/build" "$R/vendor/sub/src"
printf '# Convencoes\nTestes: `*.test.ts` ao lado do arquivo.\n' > "$R/docs/stack/CONVENCOES.md"
printf 'build/\n' > "$R/.gitignore"
printf 'on: push\n' > "$R/.github/ci.yml"
printf 'a\n' > "$R/src/a.ts"
g -C "$R" add -A; g -C "$R" commit -q -m base
git init -q "$R/.pylot-tmp/wt"            # worktree/copia aninhada de ferramenta
git init -q "$R/vendor/sub"               # repositorio aninhado fora de pasta oculta
mkdir -p "$aux/fora/src"
for f in src/b.ts .pylot-tmp/wt/src/b.ts .expxv/x/src/b.ts build/b.ts vendor/sub/src/b.ts .github/b.ts; do
  printf 'x\n' > "$R/$f"
done
printf 'x\n' > "$aux/fora/src/b.ts"

tdd() { # tdd <caminho absoluto> — 0 quando o hook avisou
  local p; p="$(printf '{"cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$R" "$1")"
  (cd "$R" && printf '%s' "$p" | bash "$H/sprintx/tdd-teste-antes.sh") 2>/dev/null | grep -q 'tdd-teste-antes'
}
tdd "$R/src/b.ts";                 afirma 'controle: implementacao do projeto sem teste avisa' $?
tdd "$R/.github/b.ts";             afirma 'pasta oculta versionada (.github) continua avisando' $?
! tdd "$R/.pylot-tmp/wt/src/b.ts"; afirma 'worktree aninhado em pasta oculta de ferramenta: silencio' $?
! tdd "$R/.expxv/x/src/b.ts";      afirma 'pasta oculta de topo sem nada versionado (.expxv): silencio' $?
! tdd "$R/build/b.ts";             afirma 'caminho ignorado pelo Git: silencio' $?
! tdd "$R/vendor/sub/src/b.ts";    afirma 'repositorio aninhado: silencio' $?
! tdd "$aux/fora/src/b.ts";        afirma 'fora da raiz do projeto (scratchpad, ~/.claude): silencio' $?

# shellcheck source=../../.claude/hooks/comum/rastro.sh
. "$H/comum/rastro.sh"
rastro_fora_do_projeto "$R" .pylot-tmp/wt/;  afirma 'git status: a pasta do repositorio aninhado (.pylot-tmp/wt/) e de fora' $?
! rastro_fora_do_projeto "$R" .env;          afirma '.env sujo no topo continua sendo do projeto' $?
! rastro_fora_do_projeto "$R" src/a.ts;      afirma 'arquivo versionado e do projeto' $?
rastro_fora_do_projeto "$R" vendor/sub;      afirma 'repositorio aninhado pela propria pasta, sem barra (vendor/sub)' $?
mkdir -p "$R/.unica"; printf 'x
' > "$R/.unica/so.yml"
g -C "$R" add .unica/so.yml; g -C "$R" commit -q -m unica; g -C "$R" rm -q .unica/so.yml
! rastro_fora_do_projeto "$R" .unica/so.yml; afirma 'git rm preparado do ultimo arquivo da pasta continua do projeto' $?
# a funcao nunca escreve no stderr: um teste quebrado que cai no `||` seguinte nao passa calado
err="$( { rastro_fora_do_projeto "$R" .expxv/x/src/b.ts; rastro_fora_do_projeto "$R" .github/b.ts; rastro_fora_do_projeto "$R" vendor/sub; } 2>&1 >/dev/null)"
[ -z "$err" ]; afirma 'rastro_fora_do_projeto nao escreve no stderr' $?

# caminho por link simbolico (CodeAnt no conselhos-municipais#346): a raiz por outro nome e um link
# de fora que aponta para dentro sao do projeto, com o caminho relativo resolvido
if ln -s "$R" "$aux/apelido" 2>/dev/null && ln -s "$R/src" "$aux/fora/link-src" 2>/dev/null \
  && [ -L "$aux/apelido" ]; then
  ! rastro_fora_do_projeto "$R" "$aux/apelido/src/b.ts" && [ "$RASTRO_REL" = src/b.ts ]
  afirma 'a raiz por um link simbolico continua do projeto (src/b.ts)' $?
  ! rastro_fora_do_projeto "$R" "$aux/fora/link-src/b.ts" && [ "$RASTRO_REL" = src/b.ts ]
  afirma 'link de fora da raiz que aponta para dentro nao escapa' $?
  tdd "$aux/apelido/src/b.ts"; afirma 'tdd-teste-antes avisa pelo caminho com link' $?
  rastro_fora_do_projeto "$R" "$aux/fora/src/b.ts"; afirma 'fora de verdade continua fora, mesmo com links ao lado' $?
else
  echo '  (sem links simbolicos neste ambiente: casos de link pulados)'
fi

echo
echo "  $ok ok, $falhou falhas"
[ "$falhou" -eq 0 ] && [ "$ok" -gt 0 ]
