#!/usr/bin/env bash
# sprintx — instalador para Claude Code e OpenCode
#
#   ./install.sh              instala nos dois harnesses, no projeto atual
#   ./install.sh --global     instala nos dois harnesses, para todos os projetos
#   ./install.sh --claude     só Claude Code
#   ./install.sh --opencode   só OpenCode
#   ./install.sh --dry-run    mostra o que faria, sem escrever nada
#   ./install.sh --sem-hooks  nao instala hooks nem agentes (so a skill e os commands)
#
# Idempotente: rodar de novo atualiza os arquivos no lugar.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_SRC="$SRC/.claude/skills/sprintx"
CMD_SRC="$SRC/.claude/commands"
HOOKS_SRC="$SRC/.claude/hooks"
AGENTS_SRC="$SRC/.claude/agents"
PLUGIN_SRC="$SRC/.opencode/plugin"
OCAGENT_SRC="$SRC/.opencode/agent"

SCOPE="project"; DO_CLAUDE=1; DO_OPENCODE=1; DRY=0; DEST=""; DO_HOOKS=1
while [ $# -gt 0 ]; do
  case "$1" in
    --global)   SCOPE="global" ;;
    --project)  SCOPE="project" ;;
    --claude)   DO_OPENCODE=0 ;;
    --opencode) DO_CLAUDE=0 ;;
    --dry-run)  DRY=1 ;;
    --sem-hooks) DO_HOOKS=0 ;;
    -h|--help)  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          DEST="$1" ;;
  esac
  shift
done

[ -d "$SKILL_SRC" ] || { echo "erro: skill nao encontrada em .claude/skills/sprintx" >&2; exit 1; }

say()  { printf '  %s\n' "$*"; }
run()  { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else eval "$@"; fi; }

# Copia a skill (SKILL.md + references/ + assets/) para <destino>/sprintx
copy_skill() {
  local dst="$1"
  run "mkdir -p '$dst'"
  run "rm -rf '$dst/sprintx'"
  run "cp -R '$SKILL_SRC' '$dst/sprintx'"
  say "skill    -> $dst/sprintx/"
}

# Copia os commands. $2 = 1 remove 'argument-hint:' (OpenCode nao suporta o campo)
copy_commands() {
  local dst="$1" strip="${2:-0}" f base n=0
  run "mkdir -p '$dst'"
  for f in "$CMD_SRC"/sprintx*.md; do
    n=$((n + 1))
    base="$(basename "$f")"
    if [ "$strip" = 1 ]; then
      run "grep -v '^argument-hint:' '$f' > '$dst/$base'"
    else
      run "cp '$f' '$dst/$base'"
    fi
  done
  say "commands -> $dst/ ($n arquivos)"
}

# Copia hooks + agentes do Claude Code e mescla os hooks no settings.json.
# A MESCLA e a parte delicada: settings.json e arquivo do usuario. Nunca
# sobrescrevemos — so acrescentamos o bloco "hooks" quando ele nao existe,
# e avisamos quando ja existe, para o usuario decidir.
#
# Os hooks vao arquivo por arquivo, sem apagar .claude/hooks/ inteiro: outras skills
# (a mergex) publicam hooks no mesmo lugar, inclusive em comum/, e a ordem de instalacao
# nao pode decidir quem sobrevive. So o namespace sprintx/ e recriado do zero (DS-158).
copy_hooks_tree() {
  local root="$1" rel
  run "mkdir -p '$root/.claude/hooks'"
  run "rm -rf '$root/.claude/hooks/sprintx'"
  while IFS= read -r rel; do
    rel="${rel#./}"
    run "mkdir -p '$root/.claude/hooks/$(dirname "$rel")'"
    run "cp '$HOOKS_SRC/$rel' '$root/.claude/hooks/$rel'"
    case "$rel" in *.sh) run "chmod +x '$root/.claude/hooks/$rel'" ;; esac
  done <<EOF
$(cd "$HOOKS_SRC" && find . -type f | LC_ALL=C sort)
EOF
  # Legado: ate a DS-158 a sprintx publicava comum/git-perigoso.sh. Sai so o arquivo DELA,
  # reconhecido pelo conteudo — o da mergex, no mesmo caminho, fica onde esta.
  if [ -f "$root/.claude/hooks/comum/git-perigoso.sh" ] \
     && grep -q 'sprintx/git-perigoso: comando barrado' "$root/.claude/hooks/comum/git-perigoso.sh"; then
    run "rm -f '$root/.claude/hooks/comum/git-perigoso.sh'"
  fi
}

copy_hooks_claude() {
  local root="$1" cfg="$1/.claude/settings.json"
  run "mkdir -p '$root/.claude'"
  run "rm -rf '$root/.claude/agents'"
  copy_hooks_tree "$root"
  run "cp -R '$AGENTS_SRC' '$root/.claude/agents'"
  say "hooks    -> $root/.claude/hooks/ (sprintx/ e os arquivos da sprintx em comum/)"
  say "agentes  -> $root/.claude/agents/"

  # .expx/hooks.json guarda o modo de cada hook. Nunca sobrescreve: o modo
  # de um hook ja promovido a bloqueio e decisao do usuario.
  if [ ! -f "$root/.expx/hooks.json" ]; then
    run "mkdir -p '$root/.expx'"
    run "cp '$SRC/.expx/hooks.json' '$root/.expx/hooks.json'"
    say "modos    -> $root/.expx/hooks.json (todos os de metodo em 'aviso')"
  else
    say "modos    -> $root/.expx/hooks.json ja existe, preservado"
  fi

  if [ ! -f "$cfg" ]; then
    run "cp '$SRC/.claude/settings.json' '$cfg'"
    say "settings -> $cfg (criado)"
  elif grep -q '"hooks"' "$cfg" 2>/dev/null; then
    say "settings -> $cfg JA TEM bloco 'hooks': nao foi tocado."
    say "            Para ativar, mescle a mao o bloco de:"
    say "            $SRC/.claude/settings.json"
    # Registro de antes da DS-158 (ou de outra skill): sem a linha do caminho novo, o
    # git-perigoso da sprintx nao roda — e o comum/git-perigoso.sh antigo dela ja saiu.
    if ! grep -q 'hooks/sprintx/git-perigoso.sh' "$cfg" 2>/dev/null; then
      say "ATENCAO:   $cfg nao registra .claude/hooks/sprintx/git-perigoso.sh."
      say "            O git-perigoso da sprintx mudou de comum/ para sprintx/ (DS-158):"
      say "            registre o caminho novo, ou ele nao roda."
    fi
  else
    say "settings -> $cfg existe sem bloco 'hooks'."
    say "            Para ativar, acrescente o bloco de:"
    say "            $SRC/.claude/settings.json"
  fi
}

copy_hooks_opencode() {
  local root="$1"
  run "mkdir -p '$root/.opencode/plugin' '$root/.opencode/agent'"
  run "cp '$PLUGIN_SRC'/sprintx.ts '$root/.opencode/plugin/sprintx.ts'"
  run "cp '$OCAGENT_SRC'/*.md '$root/.opencode/agent/'"
  say "plugin   -> $root/.opencode/plugin/sprintx.ts (auto-carregado)"
  say "agentes  -> $root/.opencode/agent/"
  # O plugin invoca os scripts de .claude/hooks/. Em instalacao so-OpenCode
  # eles precisam existir mesmo assim — inclusive quando outra skill ja criou a
  # pasta: a presenca de .claude/hooks/ nao diz que os da sprintx estao la.
  if [ ! -f "$root/.claude/hooks/sprintx/escopo-da-task.sh" ]; then
    run "mkdir -p '$root/.claude'"
    copy_hooks_tree "$root"
    say "hooks    -> $root/.claude/hooks/ (usados pelo plugin do OpenCode)"
  fi
}

echo
echo "sprintx — instalando (escopo: $SCOPE)"
echo

if [ "$SCOPE" = "global" ]; then
  # Global: o OpenCode AUTO-CARREGA skills de ~/.claude/skills/, entao a skill
  # e instalada uma unica vez e serve aos dois harnesses. So os commands sao espelhados.
  if [ "$DO_CLAUDE" = 1 ] || [ "$DO_OPENCODE" = 1 ]; then
    echo "Claude Code (~/.claude) — tambem lido pelo OpenCode como 'external skill'"
    copy_skill "$HOME/.claude/skills"
    [ "$DO_CLAUDE" = 1 ] && copy_commands "$HOME/.claude/commands" 0
    echo
  fi
  if [ "$DO_OPENCODE" = 1 ]; then
    echo "OpenCode (~/.config/opencode)"
    copy_commands "$HOME/.config/opencode/command" 1
    say "skill    -> auto-carregada de ~/.claude/skills/sprintx (nao duplicada)"
    echo
  fi
  if [ "$DO_HOOKS" = 1 ]; then
    echo "Agentes (globais)"
    [ "$DO_CLAUDE" = 1 ] && {
      run "mkdir -p '$HOME/.claude/agents'"
      run "cp '$AGENTS_SRC'/*.md '$HOME/.claude/agents/'"
      say "agentes  -> ~/.claude/agents/"
    }
    [ "$DO_OPENCODE" = 1 ] && {
      run "mkdir -p '$HOME/.config/opencode/agent'"
      run "cp '$OCAGENT_SRC'/*.md '$HOME/.config/opencode/agent/'"
      say "agentes  -> ~/.config/opencode/agent/"
    }
    echo
    say "Hooks NAO sao instalados no escopo global: eles leem o plano do"
    say "projeto (tasks.md) e gravam o rastro na raiz dele. Rode"
    say "./install.sh dentro de cada projeto que for usar os hooks."
    echo
  fi
else
  ROOT="${DEST:-$PWD}"
  [ -d "$ROOT" ] || { echo "erro: destino nao existe: $ROOT" >&2; exit 1; }
  if [ "$DO_CLAUDE" = 1 ]; then
    echo "Claude Code ($ROOT/.claude)"
    copy_skill "$ROOT/.claude/skills"
    copy_commands "$ROOT/.claude/commands" 0
    [ "$DO_HOOKS" = 1 ] && copy_hooks_claude "$ROOT"
    echo
  fi
  if [ "$DO_OPENCODE" = 1 ]; then
    # Projeto: nao ha ponte .claude -> .opencode, entao a skill e copiada de fato.
    echo "OpenCode ($ROOT/.opencode)"
    copy_skill "$ROOT/.opencode/skills"
    copy_commands "$ROOT/.opencode/command" 1
    [ "$DO_HOOKS" = 1 ] && copy_hooks_opencode "$ROOT"
    echo
  fi
fi

echo "Pronto. Descreva o que quer construir, ou use /sprintx <feature>."
echo
