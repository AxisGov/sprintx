#!/usr/bin/env bash
# bancada.sh — script de bancada minimo para os hooks de sessoes paralelas.
#
# Nao e uma suite completa (a sprintx nao tinha nenhuma antes desta feature —
# ver base/testes-e-mimocode.md). Monta uma fixture git real em disco, com um
# worktree derivado, e roda cada hook novo contra ela, conferindo exit code e,
# quando aplicavel, o conteudo de stderr (bloqueio) ou stdout (aviso).
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BANCADA_CACHE="${XDG_CACHE_HOME:-${HOME:?HOME ausente}/.cache}/sprintx-bancada"
mkdir -p "$BANCADA_CACHE" || { printf 'bancada: cache indisponivel: %s\n' "$BANCADA_CACHE" >&2; exit 1; }
[ ! -L "$BANCADA_CACHE" ] || { printf 'bancada: cache nao pode ser symlink: %s\n' "$BANCADA_CACHE" >&2; exit 1; }

# Só remove workdirs que esta própria bancada marcou, com mais de uma hora e
# cujo PID já não existe. Diretórios genéricos de /tmp e caches de terceiros
# nunca entram nesta limpeza.
find "$BANCADA_CACHE" -mindepth 1 -maxdepth 1 -type d -name 'bancada.*' -mmin +60 -print0 2>/dev/null \
  | while IFS= read -r -d '' antigo; do
      [ -f "$antigo/.sprintx-bancada" ] || continue
      pid_antigo="$(sed -n 's/^pid=//p' "$antigo/.sprintx-bancada" | sed -n 1p)"
      case "$pid_antigo" in ''|*[!0-9]*) continue ;; esac
      kill -0 "$pid_antigo" 2>/dev/null && continue
      if command -v lsof >/dev/null 2>&1; then
        lsof +D "$antigo" >/dev/null 2>&1 && continue
      elif command -v fuser >/dev/null 2>&1; then
        fuser -v "$antigo" >/dev/null 2>&1 && continue
      else
        # Sem uma segunda prova de desuso, preservar é mais seguro que apagar.
        continue
      fi
      rm -rf -- "$antigo"
    done

WORKDIR="$(mktemp -d "$BANCADA_CACHE/bancada.XXXXXX")" \
  || { printf 'bancada: nao foi possivel criar workdir em disco\n' >&2; exit 1; }
printf 'pid=%s\nscript=%s\ncriado_em=%s\n' "$$" "$0" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  > "$WORKDIR/.sprintx-bancada"
mkdir -p "$WORKDIR/tmp" "$BANCADA_CACHE/node-compile-cache" \
  "$BANCADA_CACHE/npm-cache" "$BANCADA_CACHE/playwright"
export TMPDIR="$WORKDIR/tmp"
export NODE_COMPILE_CACHE="$BANCADA_CACHE/node-compile-cache"
export NPM_CONFIG_CACHE="$BANCADA_CACHE/npm-cache"
export PLAYWRIGHT_BROWSERS_PATH="$BANCADA_CACHE/playwright"

W=""; WT=""
limpa_workdir() {
  local rc="$?"
  trap - EXIT HUP INT TERM
  [ -z "$W" ] || [ -z "$WT" ] || git -C "$W" worktree remove --force "$WT" >/dev/null 2>&1
  rm -rf -- "$WORKDIR"
  exit "$rc"
}
trap limpa_workdir EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

TMP_USO_KB="$(du -sk /tmp 2>/dev/null | awk '{ print $1 }')"
if [ "${TMP_USO_KB:-0}" -gt 1048576 ]; then
  printf 'bancada: aviso: /tmp usa mais de 1 GiB (%s KiB); a bancada atual usa %s\n' \
    "$TMP_USO_KB" "$WORKDIR" >&2
fi

W="$(mktemp -d "$TMPDIR/fixture.XXXXXX")"
# $W e um repositorio git real (nao so um .git vazio): os hooks novos precisam
# de raiz_repo() e de git status funcionando de verdade. WT e um worktree
# derivado, usado pelo caso que prova o comportamento em worktree.
git -C "$W" init -q -b main
git -C "$W" config user.email "t@t.local"; git -C "$W" config user.name "teste"
printf '.expx/\ndocs/eventos/\n' > "$W/.gitignore"
git -C "$W" add -A -- .gitignore >/dev/null 2>&1 || true
git -C "$W" -c commit.gpgsign=false commit -q -m init --allow-empty >/dev/null 2>&1
WT="${W}--worktree"
git -C "$W" worktree add -q -b feature/exportacao-csv "$WT" main >/dev/null 2>&1

OC="$W/docs/sprintx/features/exportacao-csv"
mkdir -p "$OC/sprint-01" "$OC/base" "$W/src/frete" "$W/src/pedido"
mkdir -p "$WT/src"

ok=0; falhou=0
caso() { # caso <nome> <esperado> <hook> <json>
  local nome="$1" esperado="$2" hook="$3" json="$4" saida real
  if [ ! -f "$hook" ]; then
    falhou=$((falhou+1)); printf '  FALHA %-45s hook nao existe: %s\n' "$nome" "$hook"
    return
  fi
  saida=$(printf '%s' "$json" | (cd "$W" && bash "$hook") 2>&1); real=$?
  if [ "$real" -eq "$esperado" ]; then
    ok=$((ok+1)); printf '  ok   %-46s exit=%s\n' "$nome" "$real"
  else
    falhou=$((falhou+1)); printf '  FALHA %-45s esperado=%s real=%s\n     %s\n' \
      "$nome" "$esperado" "$real" "$(printf '%s' "$saida" | head -3)"
  fi
}
existe() { # existe <nome> <caminho>
  if [ -f "$2" ]; then ok=$((ok+1)); printf '  ok   %-46s existe\n' "$1"
  else falhou=$((falhou+1)); printf '  FALHA %-45s nao existe: %s\n' "$1" "$2"; fi
}
w() { printf '{"cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s","content":%s}}' "$W" "$W/$1" "$2"; }
bash_ev() { printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$W" "$1"; }

escreve_tasks() { cat > "$OC/sprint-01/tasks.md" <<EOF
---
expx_schema: 1
expx_tool: sprintx
kind: tasks
trabalho_id: exportacao-csv
sprint_id: sprint-01
tasks:
  - id: T-01.01
    status: $1
    teste_integracao: Chama o endpoint de exportacao
    teste_funcional: Dado 60 registros, gera csv com 60 linhas
    suite: nao_executada
    arquivos:
      cria: []
      altera: [src/frete/calculo.ts]
  - id: T-01.02
    status: pendente
    teste_integracao: Valida encoding
    teste_funcional: UTF-8 com BOM
    suite: nao_executada
    arquivos:
      cria: []
      altera: [src/pedido/exportador.ts]
---
EOF
}
escreve_tasks pendente

echo "== capacidade de testar (T-01.01) =="
existe "task-reivindicada-existe" "$H/sprintx/task-reivindicada.sh"
existe "arvore-limpa-existe" "$H/sprintx/arvore-limpa-antes-da-suite.sh"

echo "== task-reivindicada.sh =="
RASTRO="$W/docs/eventos/exportacao-csv.jsonl"
mkdir -p "$(dirname "$RASTRO")"
grava_evento() { # grava_evento <evento> <sessao|->
  python3 -c "
import json, sys, datetime
extras = '' if sys.argv[2] == '-' else ',\"sessao\":\"%s\",\"harness\":\"%s\"' % (sys.argv[2], sys.argv[2].split('@')[0])
linha = ('{\"ts\":\"%s\",\"expx_eventos\":1,\"trabalho_id\":\"exportacao-csv\",'
         '\"ferramenta\":\"sprintx\",\"origem\":\"skill\",\"evento\":\"%s\",\"fase\":\"f6\",'
         '\"task\":\"T-01.01\",\"agente\":\"principal\",\"resultado\":\"ok\",\"detalhe\":null,'
         '\"arquivos\":[]%s}') % (datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'), sys.argv[1], extras)
open(sys.argv[3], 'a').write(linha + '\n')
" "$1" "$2" "$RASTRO"
}
mk_em_andamento() { # gera o JSON do write que poe T-01.01 em em_andamento
  cat <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: tasks
trabalho_id: exportacao-csv
sprint_id: sprint-01
tasks:
  - id: T-01.01
    status: em_andamento
    teste_integracao: Chama o endpoint de exportacao
    teste_funcional: Dado 60 registros, gera csv com 60 linhas
    suite: nao_executada
    arquivos:
      cria: []
      altera: [src/frete/calculo.ts]
---
YAML
}
J_EM_ANDAMENTO="$(python3 -c "
import json, sys
conteudo = sys.stdin.read()
print(json.dumps({'cwd': sys.argv[1], 'tool_name': 'Write', 'tool_input': {'file_path': sys.argv[2], 'content': conteudo}}))
" "$W" "$OC/sprint-01/tasks.md" <<< "$(mk_em_andamento)")"

: > "$RASTRO"
caso "task-reivindicada-sem-rastro-passa" 0 "$H/sprintx/task-reivindicada.sh" "$J_EM_ANDAMENTO"

: > "$RASTRO"; grava_evento task_iniciada "opencode@abc"
caso "task-reivindicada-reivindicada-avisa" 0 "$H/sprintx/task-reivindicada.sh" "$J_EM_ANDAMENTO"

: > "$RASTRO"; grava_evento task_iniciada "opencode@abc"; grava_evento task_concluida "opencode@abc"
caso "task-reivindicada-fechada-passa" 0 "$H/sprintx/task-reivindicada.sh" "$J_EM_ANDAMENTO"

: > "$RASTRO"
mkdir -p "$W/.expx"; echo '{"hooks":{"task-reivindicada":{"modo":"bloqueio"}}}' > "$W/.expx/hooks.json"
grava_evento task_iniciada "opencode@abc"
caso "task-reivindicada-bloqueio-barra" 2 "$H/sprintx/task-reivindicada.sh" "$J_EM_ANDAMENTO"
rm -f "$W/.expx/hooks.json"
: > "$RASTRO"

echo "== arvore-limpa-antes-da-suite.sh =="
escreve_tasks pendente
git -C "$W" -c commit.gpgsign=false commit -q -am "cria fixture" --allow-empty >/dev/null 2>&1 || true
rm -f "$W/src/frete/calculo.ts" "$W/src/pedido/exportador.ts"
limpa_sujeira() { rm -f "$W/src/frete/calculo.ts" "$W/src/pedido/outro.ts"; }

limpa_sujeira
touch "$W/src/frete/calculo.ts"  # no escopo (arquivos.altera da T-01.01)
caso "arvore-limpa-sujo-no-escopo-passa" 0 "$H/sprintx/arvore-limpa-antes-da-suite.sh" "$(bash_ev 'npm test')"

limpa_sujeira
touch "$W/src/pedido/outro.ts"  # fora do escopo
caso "arvore-limpa-sujo-fora-escopo-avisa" 0 "$H/sprintx/arvore-limpa-antes-da-suite.sh" "$(bash_ev 'npm test')"

limpa_sujeira
caso "arvore-limpa-comando-comum-nao-dispara" 0 "$H/sprintx/arvore-limpa-antes-da-suite.sh" "$(bash_ev 'ls -la')"

limpa_sujeira
SEMGIT="$(mktemp -d)"
saida=$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"npm test"}}' "$SEMGIT" \
  | (cd "$SEMGIT" && bash "$H/sprintx/arvore-limpa-antes-da-suite.sh" 2>&1)); real=$?
if [ "$real" -eq 0 ]; then ok=$((ok+1)); printf '  ok   %-46s exit=%s\n' "arvore-limpa-sem-git-passa" "$real"
else falhou=$((falhou+1)); printf '  FALHA %-45s esperado=0 real=%s\n     %s\n' "arvore-limpa-sem-git-passa" "$real" "$saida"; fi
rm -rf "$SEMGIT"

echo "== raiz em worktree (D-06) =="
real_raiz=$(cd "$WT/src" && bash -c "
. '$H/comum/rastro.sh'
rastro_raiz \"\$PWD\"
")
esperado_raiz="$(cd "$WT" && pwd)"
if [ "$real_raiz" = "$esperado_raiz" ]; then
  ok=$((ok+1)); printf '  ok   %-46s => %s\n' "raiz-em-worktree" "$real_raiz"
else
  falhou=$((falhou+1)); printf '  FALHA %-45s esperado=%s real=%s\n' "raiz-em-worktree" "$esperado_raiz" "$real_raiz"
fi

echo "== identidade de sessao (D-09) =="
sessao_por_env=$(cd "$W" && env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID EXPX_SESSAO="opencode@xyz" bash -c "
. '$H/comum/rastro.sh'
rastro_sessao
")
if [ "$sessao_por_env" = "opencode@xyz" ]; then
  ok=$((ok+1)); printf '  ok   %-46s => %s\n' "sessao-por-env" "$sessao_por_env"
else
  falhou=$((falhou+1)); printf '  FALHA %-45s esperado=opencode@xyz real=%s\n' "sessao-por-env" "$sessao_por_env"
fi

sessao_por_claude=$(cd "$W" && env -u EXPX_SESSAO -u EXPX_HARNESS CLAUDECODE=1 CLAUDE_CODE_SESSION_ID="abc-123" bash -c "
. '$H/comum/rastro.sh'
rastro_sessao
")
if [ "$sessao_por_claude" = "claude-code@abc-123" ]; then
  ok=$((ok+1)); printf '  ok   %-46s => %s\n' "sessao-por-claude-code-env" "$sessao_por_claude"
else
  falhou=$((falhou+1)); printf '  FALHA %-45s esperado=claude-code@abc-123 real=%s\n' "sessao-por-claude-code-env" "$sessao_por_claude"
fi

echo "== contrato sprintx x mergex (F6) =="
# Asserts textuais sobre o contrato de integracao. Sem python3 e sem rede: so
# leitura dos arquivos da skill, para que o caso rode em qualquer maquina.
SK="$H/../skills/sprintx"
EXEC="$SK/references/06-execucao.md"
SKILLMD="$SK/SKILL.md"

afirma() { # afirma <nome> <condicao-ja-avaliada:0|1> <detalhe>
  if [ "$2" -eq 0 ]; then ok=$((ok+1)); printf '  ok   %-46s %s\n' "$1" "$3"
  else falhou=$((falhou+1)); printf '  FALHA %-45s %s\n' "$1" "$3"; fi
}
tem() { grep -qF "$2" "$1"; }          # substring literal
conta() { grep -cF "$2" "$1"; }
linha_de() { grep -nF "$2" "$1" | head -1 | cut -d: -f1; }

# 1. Os tres acionamentos existem e estao condicionados a presenca da mergex.
tem "$EXEC" 'etapa E0 da `mergex`'; afirma "e0-existe" $? "F6 aciona E0"
tem "$EXEC" 'etapa E1 da `mergex`'; afirma "e1-existe" $? "F6 aciona E1"
tem "$EXEC" 'etapas E2 a E8 da `mergex`'; afirma "e2-e8-existe" $? "F6 aciona E2-E8"

# Toda mencao a acionamento vem guardada pela existencia do SKILL.md da mergex.
GUARDA=$(conta "$EXEC" '.claude/skills/mergex/SKILL.md')
[ "$GUARDA" -ge 3 ]; afirma "acionamento-condicional" $? "$GUARDA guardas de presenca"

# 2. A ordem no arquivo: E0 antes da primeira task; FECHAMENTO.md antes de E2.
L_E0=$(linha_de "$EXEC" 'etapa E0 da `mergex`')
L_TASK=$(linha_de "$EXEC" '## Passo 2 — Executar task a task')
[ "$L_E0" -lt "$L_TASK" ]; afirma "e0-antes-da-primeira-task" $? "E0=$L_E0 < Passo2=$L_TASK"

L_FECH=$(linha_de "$EXEC" 'grave `docs/sprintx/features/<slug>/FECHAMENTO.md`')
L_E2=$(linha_de "$EXEC" 'etapas E2 a E8 da `mergex`')
[ "$L_FECH" -lt "$L_E2" ]; afirma "fechamento-antes-de-e2" $? "FECHAMENTO=$L_FECH < E2=$L_E2"

L_CONCLUIDA=$(linha_de "$EXEC" 'Só então marque `status: concluida`')
L_E1=$(linha_de "$EXEC" 'etapa E1 da `mergex`')
[ "$L_CONCLUIDA" -lt "$L_E1" ]; afirma "e1-depois-de-status-concluida" $? "concluida=$L_CONCLUIDA < E1=$L_E1"

# 3. suite: parcial sustenta commit; task bloqueada nao gera commit.
tem "$EXEC" '**`suite: parcial` fecha task e sustenta commit**'; afirma "parcial-permite-e1" $? "parcial sustenta E1"
tem "$EXEC" '**Task marcada `bloqueada` não gera commit**'; afirma "bloqueada-sem-e1" $? "bloqueada nao commita"

# 4. A integracao para no E8: nenhum arquivo da skill encadeia a revisao.
# O contrato é da skill SprintX. Limitar a busca a ela evita que uma cópia de
# teste com H corrompido transforme a asserção numa varredura da raiz inteira.
REV=$(grep -rlF "mergex-""revisar" "$SK" 2>/dev/null | wc -l)
[ "$REV" -eq 0 ]; afirma "sem-mergex-revisar" $? "$REV arquivo(s) citam o comando de revisao"
E910=$(grep -rnE '\bE(9|10)\b' "$SK" 2>/dev/null | grep -i mergex | wc -l)
[ "$E910" -eq 0 ]; afirma "sem-e9-e10" $? "$E910 mencao(oes) a E9/E10 da mergex"

# 5. Sem mergex, a F6 nao muda e nao avisa.
tem "$EXEC" 'siga direto para o'; afirma "sem-mergex-segue-direto" $? "caminho sem mergex explicito"

# 6. Nenhum caminho absoluto entrou no contrato (regra inviolavel 16).
ABS=$(grep -nE '(^|[^a-zA-Z0-9_])(/(home|Users|tmp|var|opt)/|[A-Za-z]:\\)' "$EXEC" "$SKILLMD" | wc -l)
[ "$ABS" -eq 0 ]; afirma "sem-caminho-absoluto" $? "$ABS ocorrencia(s)"

# 7. O contrato da task nao ganhou campo novo: os 10 campos da tabela do SKILL.md.
CAMPOS=$(sed -n '/### Contrato da Task/,/### Contrato da Fase/p' "$SKILLMD" | grep -cE '^\| `')
[ "$CAMPOS" -eq 10 ]; afirma "contrato-task-intacto" $? "$CAMPOS campos (esperado 10)"

# 8. Regra 21 e a posse da branch/worktree seguem com a F1.
tem "$SKILLMD" '21. Uma feature aberta por árvore de trabalho. Com git, ela nasce em worktree próprio na F1'; afirma "regra-21-intacta" $? "regra 21 literal"
conta_regras() { sed -n '/^## Regras invioláveis$/,/^## Sessões paralelas$/p' "$1" | grep -cE '^[0-9]+\. '; }
REGRAS=$(conta_regras "$SKILLMD")
[ "$REGRAS" -eq 21 ]; afirma "21-regras-inviolaveis" $? "$REGRAS regras (esperado 21)"

# 9. A mergex nao virou fase da maquina de estados.
FASES=$(sed -n '/^| Estado do disco | Fase atual |$/,/^$/p' "$SKILLMD" | grep -ci mergex)
[ "$FASES" -eq 0 ]; afirma "mergex-fora-da-maquina" $? "$FASES linha(s) na tabela de fase"

# 10. Os dois harnesses enxergam a mesma integracao (Claude Code e OpenCode).
tem "$EXEC" '.opencode/skills/mergex/SKILL.md'; afirma "deteccao-nos-dois-harnesses" $? "caminho OpenCode previsto"

echo "== A. ignore local: rastro e estado fora do versionador =="
ING="$SK/references/01-ingestao.md"

# A1. contrato: a F1 nao manda mais editar o .gitignore versionado.
tem "$ING" 'nunca modifica o `.gitignore` por conta própria'; afirma "a1-f1-nao-edita-gitignore" $? "ownership removido"
if grep -qF 'Garanta a linha `docs/eventos/` no `.gitignore`' "$ING"; then false; else true; fi
afirma "a1b-mandato-antigo-sumiu" $? "mandato antigo removido"

# A2..A5, A8: o MECANISMO, contra um repositorio git real e um worktree ligado.
# Nao testa o texto: testa que os comandos que o contrato manda usar de fato se
# comportam como ele afirma. Padrao proprio, para nao colidir com a fixture.
PAT="zz-teste-exclude/"

# A2. padrao ja ignorado pela configuracao existente -> no-op.
git -C "$W" check-ignore -q "docs/eventos/" 2>/dev/null
afirma "a2-ja-ignorado-e-noop" $? "check-ignore acusa docs/eventos/ da fixture"

# A3. padrao nao ignorado -> entra no arquivo devolvido pelo git.
git -C "$W" check-ignore -q "$PAT" 2>/dev/null; [ $? -ne 0 ]
afirma "a3a-ainda-nao-ignorado" $? "comeca nao ignorado"
EXC="$(cd "$W" && git rev-parse --git-path info/exclude)"
EXC_ABS="$(cd "$W" && cd "$(dirname "$EXC")" && pwd)/$(basename "$EXC")"
mkdir -p "$(dirname "$EXC_ABS")"; printf '%s\n' "$PAT" >> "$EXC_ABS"
git -C "$W" check-ignore -q "$PAT" 2>/dev/null
afirma "a3b-entra-no-git-path-exclude" $? "passou a ser ignorado via info/exclude"

# A4. segunda execucao nao duplica: o contrato manda acrescentar idempotentemente.
if ! grep -qxF "$PAT" "$EXC_ABS"; then printf '%s\n' "$PAT" >> "$EXC_ABS"; fi
N=$(grep -cxF "$PAT" "$EXC_ABS")
[ "$N" -eq 1 ]; afirma "a4-idempotente" $? "$N ocorrencia(s) apos segunda passada"

# A5. linked worktree: o caminho resolvido pelo git NAO e <worktree>/.git/info/exclude.
# Num worktree ligado o .git e um ARQUIVO, entao o caminho hardcoded nao existe.
[ -f "$WT/.git" ]; afirma "a5a-worktree-git-e-arquivo" $? "hardcode seria caminho invalido"
EXC_WT="$(cd "$WT" && git rev-parse --git-path info/exclude)"
case "$EXC_WT" in "$WT"/*) false ;; *) true ;; esac
afirma "a5b-git-path-sai-do-worktree" $? "resolvido no repo principal"
PAT_WT="zz-teste-worktree/"
EXC_WT_ABS="$(cd "$WT" && cd "$(dirname "$EXC_WT")" && pwd)/$(basename "$EXC_WT")"
printf '%s\n' "$PAT_WT" >> "$EXC_WT_ABS"
git -C "$WT" check-ignore -q "$PAT_WT" 2>/dev/null
afirma "a5c-caminho-resolvido-funciona" $? "padrao ignorado dentro do worktree"

# A8. o ignore local nao suja a arvore: nada disso aparece em git status.
SUJO_WT="$(git -C "$WT" status --porcelain --untracked-files=all 2>/dev/null | wc -l)"
[ "$SUJO_WT" -eq 0 ]; afirma "a8-worktree-nao-suja" $? "$SUJO_WT linha(s) em git status"

# A6/A7. contrato: sem .expx nao cria regra; sem git segue sem erro.
tem "$ING" 'não crie nada e não acrescente a regra do'; afirma "a6-sem-expx-sem-regra" $? "condicao explicita"
tem "$ING" 'Sem Git** não existe `info/exclude`'; afirma "a7-sem-git-nao-falha" $? "caminho sem git explicito"
tem "$ING" 'git rev-parse --git-path info/exclude'; afirma "a-contrato-usa-git-path" $? "caminho resolvido pelo git"
tem "$ING" 'git check-ignore'; afirma "a-contrato-checa-antes" $? "check-ignore antes de escrever"
. "$H/testes/bancada-base-encadeada.sh"
t_base_encadeada "$ING"; afirma "a-f1-base-pela-linha-da-base" $? "bloco do item 2 em git real${BX_FALHA:+ — FORA:$BX_FALHA}"

echo "== B. HISTORICO.md: artefato global de metodo, versionado =="
# 9. a F6 continua exigindo o arquivo.
tem "$EXEC" 'recebeu uma entrada por task concluída'; afirma "b9-f6-ainda-exige" $? "criterio de saida intacto"
# 10. o contrato o nomeia artefato global de metodo.
tem "$EXEC" 'artefato global de'; afirma "b10-nomeado-global-exec" $? "declarado em 06-execucao.md"
tem "$SKILLMD" 'artefato global de método'; afirma "b10b-nomeado-global-skill" $? "declarado no SKILL.md"
# 11. com mergex, o commit e ownership dela.
tem "$EXEC" 'escreve** e a `mergex` **versiona'; afirma "b11-ownership-mergex" $? "ownership declarado"
# 12. a sprintx nao commita por conta propria.
if grep -qE '^[[:space:]]*git (commit|add|push)' "$EXEC"; then false; else true; fi
afirma "b12-sem-git-commit-na-skill" $? "nenhum comando de commit na F6"
grep -qF 'docs/sprintx/*' "$H/sprintx/arvore-limpa-antes-da-suite.sh"
afirma "b-portao-isenta-artefato-metodo" $? "docs/sprintx/* isento no gate da suite"

echo "== C. plano condensado e tres arquivos =="
SCHEMA="$SK/references/00-schema.md"
ORQ="$SK/references/04-orquestrador.md"
AUD="$SK/references/05-auditoria.md"
EST="$SK/references/07-estimativa.md"
DIAG="$SK/references/09-diagrama.md"

# A regra de resolucao existe UMA vez, e num lugar so.
tem "$SCHEMA" 'Como resolver o formato de uma sprint'; afirma "c-regra-unica-existe" $? "descrita em 00-schema.md"
NREGRA=$(grep -rlF '### Como resolver o formato de uma sprint' "$SK" | wc -l)
[ "$NREGRA" -eq 1 ]; afirma "c-regra-nao-duplicada" $? "$NREGRA arquivo(s) com a descricao"

# 13/14. F4 aceita os dois formatos e nao contradiz a F3.
tem "$ORQ" 'ou três arquivos'; afirma "c13-f4-aceita-condensado" $? "pre-requisito dos dois formatos"
tem "$ORQ" 'Como resolver o formato de uma sprint'; afirma "c14-f4-referencia-regra" $? "F4 aponta a regra unica"
if grep -qF 'existe com `sprint.md`, `fases.md` e `tasks.md`.' "$ORQ"; then false; else true; fi
afirma "c13b-f4-sem-exigencia-literal" $? "exigencia dos tres arquivos removida"

# 15/16. F5 audita os dois formatos, sem perder rigor.
tem "$AUD" 'Resolva o formato de cada sprint'; afirma "c15-f5-resolve-formato" $? "F5 resolve por sprint"
tem "$AUD" 'nos dois formatos'; afirma "c16-f5-mesmo-rigor" $? "nove itens preservados"
tem "$AUD" 'Numa sprint condensada isso é sempre'; afirma "c16b-f5-achado-caminho-real" $? "achado aponta caminho real"
NAUD=$(sed -n '/^## Passo 3 — Verificar cada item desta lista/,/^## Passo 4/p' "$AUD" | grep -cE '^[0-9]+\. \*\*')
[ "$NAUD" -eq 9 ]; afirma "c16c-f5-nove-itens" $? "$NAUD itens de auditoria (esperado 9)"

# 17/18/19. F6 grava nos dois formatos.
tem "$EXEC" 'Fechar fase atualiza o item correspondente em `fases`'; afirma "c17-19-f6-grava-condensado" $? "fase e sprint no condensado"
tem "$EXEC" 'a mesma chave nos dois formatos'; afirma "c17-f6-task-igual" $? "task fecha igual nos dois"

# 20/21. portoes nao afrouxam no condensado.
tem "$EXEC" 'Nenhuma condição afrouxa por causa do formato'; afirma "c20-f6-portao-nao-afrouxa" $? "criterio_saida cobrado igual"
tem "$EXEC" 'rode a suíte INTEIRA e exija 0 failed'; afirma "c21-f6-suite-inteira" $? "suite inteira continua exigida"

# 22. ausencia de fases.md no condensado nao gera aviso.
tem "$EXEC" 'sem registrar aviso'; afirma "c22-f6-sem-aviso-diagrama" $? "F6 pula diagrama em silencio"
tem "$DIAG" 'Sprint condensada não tem diagrama'; afirma "c22b-diagrama-documenta" $? "09-diagrama.md explica"

# 23. o formato de tres arquivos continua valido, sem regressao.
tem "$SCHEMA" 'continuam válidos e não são descontinuados'; afirma "c23-tres-arquivos-vivos" $? "nenhum formato descontinuado"
tem "$EXEC" 'fechar sprint atualiza `sprint.md`'; afirma "c23b-f6-tres-arquivos" $? "caminho dos tres arquivos preservado"
tem "$EST" 'ou três arquivos'; afirma "c-f35-aceita-os-dois" $? "F3.5 tambem resolve"
AGENTE=$(grep -lF 'kind: plano' "$H/../agents/auditor-plano.md" "$H/../../.opencode/agent/auditor-plano.md" 2>/dev/null | wc -l)
[ "$AGENTE" -eq 2 ]; afirma "c-agente-nos-dois-harnesses" $? "$AGENTE/2 espelhos do auditor corrigidos"

# Dois contadores, deliberadamente separados — misturar os dois esconde o que
# importa. `pula` e SKIP INTERNO: caso que a logica da sprintx deixou de
# cobrir nesta plataforma. A base candidata fecha com zero, e o proprio
# script cobra isso no fim. `pula_externo` e dependencia externa ausente
# (outro repositorio, outro pacote): nao e buraco de cobertura da sprintx.
pulado=0; pulado_externo=0
pula() { pulado=$((pulado+1)); printf '  pula %-46s SKIP INTERNO: %s\n' "$1" "$2"; }
pula_externo() { pulado_externo=$((pulado_externo+1)); printf '  dep  %-46s dependencia externa ausente: %s\n' "$1" "$2"; }

echo "== D. frontmatter dos agentes carrega =="
# O E2E achou o revisor-testes invisivel ao Claude Code: `description:` sem aspas
# com ": " no meio e YAML invalido, e o agente some sem erro nenhum. Guarda
# ESTRUTURAL e conservadora (awk, roda em qualquer maquina); nao e um parser YAML
# completo. Quando ha um parser real (PyYAML), ele confere tambem, logo abaixo.
valida_frontmatter() { # valida_frontmatter <arquivo> <exige_name:1|0> -> motivo em stdout
  tr -d '\r' < "$1" | awk -v exige_name="$2" '
    function simples_invalido(v) {
      if (v == "") return 0
      c = substr(v, 1, 1)
      if (c == "\"") return (v !~ /"[ \t]*$/)
      if (c == "'\''" || c == "|" || c == ">" || c == "[" || c == "{") return 0
      return (index(v, ": ") > 0 || v ~ /:$/ || index(v, " #") > 0)
    }
    function falha(m) { print m; erro = 1; exit 1 }
    NR == 1 { if ($0 != "---") falha("sem delimitador inicial na linha 1"); next }
    $0 == "---" { fechou = 1; exit }
    /^[ \t]*$/ || /^[ \t]*#/ { next }
    { linhas++ }
    /^[A-Za-z_][A-Za-z0-9_-]*:/ || /^[ \t]+[A-Za-z_][A-Za-z0-9_-]*:/ {
      chave = $0; sub(/^[ \t]*/, "", chave); sub(/:.*/, "", chave)
      valor = $0; sub(/^[ \t]*[A-Za-z_][A-Za-z0-9_-]*:[ \t]*/, "", valor); sub(/[ \t]+$/, "", valor)
      if (simples_invalido(valor)) falha("valor simples invalido em " chave " (\": \" ou \" #\" sem aspas)")
      if ($0 !~ /^[ \t]/) { visto[chave] = 1; val[chave] = valor }
      next
    }
    /^[ \t]+-/ { next }
    { falha("linha que nao e chave YAML: " $0) }
    END {
      if (erro) exit 1
      if (NR == 0) { print "arquivo vazio"; exit 1 }
      if (!fechou) { print "sem delimitador final"; exit 1 }
      if (!linhas) { print "frontmatter vazio"; exit 1 }
      if (exige_name == 1 && (!visto["name"] || val["name"] == "")) { print "name ausente"; exit 1 }
      if (!visto["description"] || val["description"] == "") { print "description ausente"; exit 1 }
    }'
}

# D1. todo agente real dos dois harnesses passa. Claude Code exige `name`;
# o OpenCode tira o nome do arquivo e so exige `description`.
for f in "$H"/../agents/*.md; do
  motivo="$(valida_frontmatter "$f" 1)"; rc=$?; afirma "d1-claude-$(basename "$f" .md)" "$rc" "${motivo:-frontmatter valido}"
done
for f in "$H"/../../.opencode/agent/*.md; do
  motivo="$(valida_frontmatter "$f" 0)"; rc=$?; afirma "d1-opencode-$(basename "$f" .md)" "$rc" "${motivo:-frontmatter valido}"
done
NAG=$(ls "$H"/../agents/*.md 2>/dev/null | wc -l); NOA=$(ls "$H"/../../.opencode/agent/*.md 2>/dev/null | wc -l)
[ "$NAG" -eq 3 ] && [ "$NOA" -eq 3 ]; afirma "d1-nenhum-agente-sumiu" $? "$NAG claude, $NOA opencode (esperado 3 e 3)"
tem "$H/../agents/revisor-testes.md" 'tools: Read, Glob, Grep'; afirma "d1-revisor-so-leitura" $? "tools de leitura preservadas"

# D2. a guarda reconhece cada forma de cabecalho quebrado — inclusive o bug do E2E.
AG="$W/agentes-ruins"; mkdir -p "$AG"
printf 'name: x\ndescription: y\n---\n' > "$AG/sem-inicio.md"
printf '%s\n' '---' 'name: x' 'description: y' > "$AG/sem-fim.md"
printf '%s\n' '---' 'description: y' '---' > "$AG/sem-name.md"
printf '%s\n' '---' 'name: x' 'tools: Read' '---' > "$AG/sem-description.md"
printf '%s\n' '---' 'name: revisor-testes' 'description: Responde sobre os testes de uma task: esse teste passaria?' '---' > "$AG/dois-pontos.md"
printf '%s\n' '---' '---' 'corpo' > "$AG/vazio.md"
printf '\n---\nname: x\ndescription: y\n---\n' > "$AG/linha-antes.md"
printf '\357\273\277---\nname: x\ndescription: y\n---\n' > "$AG/bom-antes.md"
printf '%s\n' '---' 'name: x' 'description: y # comentario come o resto' '---' > "$AG/cerquilha.md"
for caso_ruim in sem-inicio sem-fim sem-name sem-description dois-pontos vazio linha-antes bom-antes cerquilha; do
  motivo="$(valida_frontmatter "$AG/$caso_ruim.md" 1)"
  [ $? -ne 0 ]; afirma "d2-rejeita-$caso_ruim" $? "${motivo:-NAO rejeitou}"
done
printf '%s\n' '---' 'name: x' 'description: "Pergunta: passaria? # sim"' '---' > "$AG/citado.md"
motivo="$(valida_frontmatter "$AG/citado.md" 1)"; afirma "d2-aceita-citado" $? "${motivo:-aspas protegem \": \" e \" #\"}"

# D3. parser YAML real, quando existir. `python3` do Windows pode ser o stub da
# loja, por isso a deteccao exige `import yaml` funcionando de fato.
PYY=""
for py in python3 python; do
  command -v "$py" >/dev/null 2>&1 && "$py" -c 'import yaml' >/dev/null 2>&1 && { PYY="$py"; break; }
done
if [ -n "$PYY" ]; then
  yaml_ok() { "$PYY" - "$1" 2>/dev/null <<'PY'
import sys, yaml
t = open(sys.argv[1], encoding='utf-8').read().replace('\r\n', '\n')
if not t.startswith('---\n'): sys.exit(1)
d = yaml.safe_load(t[4:].split('\n---', 1)[0])
sys.exit(0 if isinstance(d, dict) and d.get('description') else 1)
PY
  }
  for f in "$H"/../agents/*.md "$H"/../../.opencode/agent/*.md; do
    yaml_ok "$f"; rc=$?; afirma "d3-yaml-$(basename "$(dirname "$f")")-$(basename "$f" .md)" "$rc" "PyYAML ($PYY) carrega"
  done
  yaml_ok "$AG/dois-pontos.md"; [ $? -ne 0 ]; afirma "d3-yaml-confirma-bug-e2e" $? "PyYAML tambem rejeita o caso do E2E"
else
  pula_externo "d3-yaml-real" "PyYAML (python3); so a guarda estrutural rodou"
fi

echo "== E. CONVENCOES.md: caminho canonico e precedencia =="
SCH="$SK/references/00-schema.md"
TDD="$H/sprintx/tdd-teste-antes.sh"
CV="$(mktemp -d)"
git -C "$CV" init -q -b main
mkdir -p "$CV/src" "$CV/docs/stack" "$CV/docs/stackx" "$CV/.expx"
printf 'export const x = 1\n' > "$CV/src/calculo.ts"
ev_cv() { printf '{"cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$CV" "$CV/src/calculo.ts"; }
conv() { printf '# Convencoes (%s)\nTestes: `*.test.ts` ao lado do arquivo.\n' "$1" > "$CV/$1"; }
limpa_conv() { rm -f "$CV/CONVENCOES.md" "$CV/docs/stack/CONVENCOES.md" "$CV/docs/stackx/CONVENCOES.md" "$CV/.expx/CONVENCOES.md"; }
lido_de() { # imprime o CONVENCOES.md que o hook usou, ou "inativo"
  local s; s="$(ev_cv | (cd "$CV" && bash "$TDD") 2>/dev/null)"
  case "$s" in *"convencoes lidas de "*) s="${s#*convencoes lidas de }"; printf '%s' "${s%%)*}" ;; *) printf 'inativo' ;; esac
}
espera_conv() { # espera_conv <nome> <esperado>
  local r; r="$(lido_de)"; [ "$r" = "$2" ]; afirma "$1" $? "lido: $r (esperado $2)"
}

# A. so o caminho canonico.
limpa_conv; conv docs/stack/CONVENCOES.md
espera_conv "ea-so-docs-stack-encontrado" docs/stack/CONVENCOES.md
# B. raiz e docs/stack: a raiz e override explicito.
limpa_conv; conv CONVENCOES.md; conv docs/stack/CONVENCOES.md
espera_conv "eb-raiz-vence-docs-stack" CONVENCOES.md
# C. canonico vence o legado.
limpa_conv; conv docs/stack/CONVENCOES.md; conv docs/stackx/CONVENCOES.md
espera_conv "ec-canonico-vence-stackx" docs/stack/CONVENCOES.md
# D. so o legado docs/stackx continua funcionando.
limpa_conv; conv docs/stackx/CONVENCOES.md
espera_conv "ed-stackx-legado-funciona" docs/stackx/CONVENCOES.md
limpa_conv; conv .expx/CONVENCOES.md; conv docs/stackx/CONVENCOES.md
espera_conv "ed2-stackx-vence-expx" docs/stackx/CONVENCOES.md
# Determinismo: o mais novo NAO vence (a raiz e mais velha e continua valendo).
limpa_conv; conv CONVENCOES.md; touch -d '2001-01-01' "$CV/CONVENCOES.md" 2>/dev/null; conv docs/stack/CONVENCOES.md
espera_conv "e-mtime-nao-decide" CONVENCOES.md
# E. nenhum: o hook segue inativo (fallback atual).
limpa_conv
espera_conv "ee-nenhum-hook-inativo" inativo
tem "$SK/references/03-plano.md" '2. **Sem `CONVENCOES.md`**: use a **estrutura de pastas**'; afirma "ee2-fallback-por-pastas-intacto" $? "modulo_afetado sem convencoes"

# H. rodar o hook nao escreve nenhum CONVENCOES.md.
limpa_conv; conv docs/stack/CONVENCOES.md; conv docs/stackx/CONVENCOES.md
ANTES="$(cat "$CV/docs/stack/CONVENCOES.md" "$CV/docs/stackx/CONVENCOES.md" | cksum)"
lido_de >/dev/null
DEPOIS="$(cat "$CV/docs/stack/CONVENCOES.md" "$CV/docs/stackx/CONVENCOES.md" | cksum)"
NOVOS=$(find "$CV" -name CONVENCOES.md -not -path '*/.git/*' | wc -l)
[ "$ANTES" = "$DEPOIS" ] && [ "$NOVOS" -eq 2 ]; afirma "eh-hook-nao-escreve-convencoes" $? "conteudo intacto, $NOVOS arquivo(s)"
ESCREVE=$(grep -rniE '(grav|cri|edit|reescrev|atualiz)[a-z]* (o |um )?`?CONVENCOES\.md' "$SK" 2>/dev/null | grep -viE 'nunca|não' | wc -l)
[ "$ESCREVE" -eq 0 ]; afirma "eh2-skill-nao-manda-escrever" $? "$ESCREVE instrucao(oes) de escrita"
rm -rf "$CV"

# Regra unica: descrita uma vez, na ordem certa, e o hook segue a mesma ordem.
NREG=$(grep -rlF '## Como localizar o `CONVENCOES.md`' "$SK" | wc -l)
[ "$NREG" -eq 1 ]; afirma "e-regra-unica" $? "$NREG arquivo(s) com a regra"
L1=$(linha_de "$SCH" '1. `CONVENCOES.md` — na raiz'); L2=$(linha_de "$SCH" '2. `docs/stack/CONVENCOES.md`')
L3=$(linha_de "$SCH" '3. `docs/stackx/CONVENCOES.md`'); L4=$(linha_de "$SCH" '4. `.expx/CONVENCOES.md`')
[ -n "$L1" ] && [ "$L1" -lt "$L2" ] && [ "$L2" -lt "$L3" ] && [ "$L3" -lt "$L4" ]; afirma "e-precedencia-documentada" $? "linhas $L1<$L2<$L3<$L4"
tem "$TDD" '"$RAIZ/CONVENCOES.md" "$RAIZ/docs/stack/CONVENCOES.md" "$RAIZ/docs/stackx/CONVENCOES.md" "$RAIZ/.expx/CONVENCOES.md"'
afirma "e-hook-mesma-ordem" $? "tdd-teste-antes segue a regra"
tem "$SCH" 'Nunca mescle'; afirma "e-sem-merge" $? "nunca mesclar"
tem "$SCH" 'nunca cria, edita nem reescreve `CONVENCOES.md`'; afirma "e-sprintx-nao-escreve" $? "declarado na regra"
# Lista antiga, sem docs/stack, nao sobrevive em lugar nenhum.
VELHA=$(grep -rnF 'docs/stackx/CONVENCOES.md' "$SK" "$H/sprintx" | grep -vF 'docs/stack/CONVENCOES.md' | grep -vF 'DECISOES-DA-SKILL.md' | grep -vF 'references/00-schema.md:' | wc -l)
[ "$VELHA" -eq 0 ]; afirma "e-sem-lista-antiga" $? "$VELHA lookup(s) sem o canonico"
# F/G. consumidores apontam para a regra.
tem "$SK/references/03-plano.md" 'Como localizar o `CONVENCOES.md`'; afirma "ef-modulo-afetado-usa-regra" $? "F3 Passo 2.1"
tem "$SK/references/03-plano.md" '`docs/stack/CONVENCOES.md`'; afirma "ef2-modulo-afetado-canonico" $? "caminho canonico citado"
tem "$SK/references/04-orquestrador.md" '`references/00-schema.md`; estrutura de pastas'; afirma "ef3-f4-usa-regra" $? "F4 deriva pelo mesmo criterio"
tem "$SK/references/01-ingestao.md" 'Como localizar o `CONVENCOES.md`'; afirma "eg-f1-branch-base-usa-regra" $? "F1 branch base e instalacao"
L_REG=$(linha_de "$SK/references/01-ingestao.md" 'Como localizar o `CONVENCOES.md`')
L_BASE=$(linha_de "$SK/references/01-ingestao.md" '1. **Nome da branch e base**')
[ "$L_REG" -lt "$L_BASE" ]; afirma "eg2-regra-antes-da-branch-base" $? "regra=$L_REG < base=$L_BASE"
tem "$SK/references/02-descoberta.md" 'Como localizar o `CONVENCOES.md`'; afirma "e-f2-usa-regra" $? "F2 pesquisa pela regra"

echo "== F. plano condensado sem diagrama; tres arquivos com diagrama =="
TPC="$SK/assets/TEMPLATE-plano-condensado.md"
TPF="$SK/assets/TEMPLATE-fases.md"
tem "$TPC" 'kind: plano'; afirma "f1-condensado-kind-plano" $? "kind: plano"
grep -q '^sprint:' "$TPC" && grep -q '^fases:' "$TPC" && grep -q '^tasks:' "$TPC"
afirma "f2-condensado-sprint-fases-tasks" $? "tres chaves no frontmatter"
tem "$TPC" 'depende_de:' && tem "$TPC" 'paralelizavel:' && tem "$TPC" 'criterio_saida:'
afirma "f2b-condensado-estrutura-logica" $? "depende_de, paralelizavel, criterio_saida"
NMER=$(grep -ci 'mermaid' "$TPC")
[ "$NMER" -eq 0 ]; afirma "f3-condensado-sem-bloco-diagrama" $? "$NMER mencao(oes) a mermaid"
if grep -qiE 'Grafo de tasks|classDef|flowchart|09-diagrama' "$TPC"; then false; else true; fi
afirma "f4-condensado-sem-instrucao-de-grafo" $? "sem secao, classes ou regra de diagrama"
tem "$SK/references/03-plano.md" '`fases.md` — de `assets/TEMPLATE-fases.md`'; afirma "f5-tres-arquivos-usa-template-fases" $? "F3 usa TEMPLATE-fases.md"
tem "$TPF" '```mermaid' && tem "$TPF" 'references/09-diagrama.md'; afirma "f6-template-fases-tem-diagrama" $? "diagrama preservado em fases.md"
tem "$SK/references/03-plano.md" 'uma sprint condensada não tem diagrama nem precisa de um'; afirma "f7-f3-condensado-sem-diagrama" $? "F3 declara"
if grep -qiE 'cada sprint tem (um )?diagrama' "$SK/references/03-plano.md"; then false; else true; fi
afirma "f7b-f3-sem-diagrama-universal" $? "nenhuma exigencia sem ressalva"
tem "$ORQ" 'ou três arquivos'; afirma "f8-f4-aceita-sem-fases" $? "F4 pelos dois formatos"
tem "$SK/assets/TEMPLATE-ORQUESTRADOR.md" 'ou só `tasks.md` quando a sprint é condensada'; afirma "f8b-orquestrador-mapa-condensado" $? "mapa de leitura nao pressupoe tres arquivos"
tem "$AUD" 'Como resolver o formato de uma sprint' && tem "$SCHEMA" '**não exija `fases.md`**'
afirma "f9-f5-aceita-sem-fases" $? "F5 resolve pela regra unica"
tem "$EXEC" 'Sprint condensada (`tasks.md` com `kind: plano`) não tem `fases.md` e não tem diagrama'; afirma "f10-f6-aceita-sem-fases" $? "F6 distingue"
tem "$EXEC" 'pule este passo inteiro, **sem registrar aviso**'; afirma "f11-f6-sem-aviso-no-condensado" $? "sem warning"
tem "$EXEC" 'troque a classe na linha `class` do nó da task'; afirma "f12-tres-arquivos-atualiza-diagrama" $? "tres arquivos como antes"
tem "$DIAG" '# O diagrama do grafo de tasks — bloco Mermaid em `fases.md`'; afirma "f12b-09-diagrama-preservado" $? "reference intacto"

echo "== G. planejamento duravel, checkpoint e orcamento da F5 (P0.1) =="
# Testa o MECANISMO contra repositorios git reais: scripts/planejamento.sh e o
# unico escritor de 00-PLANEJAMENTO.md e o unico autor de checkpoint.
PL="$SK/scripts/planejamento.sh"
TPL="$SK/assets/TEMPLATE-PLANEJAMENTO.md"
existe "g0-script-existe" "$PL"
existe "g0-template-existe" "$TPL"
bash -n "$PL"; afirma "g0-script-sintaxe" $? "bash -n"
G="$(mktemp -d)"
CMD_PL='bash <raiz-da-skill>/scripts/planejamento.sh'
kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }
pl() { local d="$1"; shift; (cd "$d" && bash "$PL" "$@") 2>&1; }
fmv() { tr -d '\r' < "$1" | awk -v k="$2" 'NR==1{next} $0=="---"{exit} index($0,k": ")==1{print substr($0,length(k)+3); exit}'; }
trailer() { git -C "$1" log -1 --format="%(trailers:key=$2,valueonly)" | tr -d '\r' | sed '/^$/d'; }
ncommits() { git -C "$1" rev-list --count HEAD; }
nova_feature() { # nova_feature <dir> <slug> [branch]
  local d="$1" s="$2" b="${3:-feature/$2}"
  git init -q -b main "$d"; git -C "$d" config user.email t@t.local; git -C "$d" config user.name teste
  git -C "$d" config commit.gpgsign false; git -C "$d" config core.autocrlf false
  printf 'docs/eventos/\n' >> "$d/.git/info/exclude"
  mkdir -p "$d/src"; printf 'export const x = 1\n' > "$d/src/app.ts"
  git -C "$d" add -A; git -C "$d" commit -q -m init
  [ "$b" = main ] || git -C "$d" switch -q -c "$b"
  mkdir -p "$d/docs/sprintx/features/$s/base"; printf 'indice\n' > "$d/docs/sprintx/features/$s/base/00-INDICE.md"
}
fdir() { printf '%s/docs/sprintx/features/%s' "$1" "$2"; }
auditoria() { # auditoria <dir> <slug> <rodada> <SIM|NAO>
  if [ "$4" = NAO ]; then
    printf '# Auditoria — %s\n\nRodada %s\n\n| severidade | arquivo | problema | correção sugerida |\n|---|---|---|---|\n| ALTA | sprint-02/tasks.md | [item 2][fraco:criterio] T-02.01 — cláusula: - — passaria com: item no grupo errado na rodada %s | Matriz item x grupo |\n| MÉDIA | sprint-03/tasks.md | [item 2][fraco:teste] T-03.01 — cláusula: D-13 — passaria com: contadores trocados entre itens | Afirmar cada contador |\n| BAIXA | sprint-04/tasks.md | [item 3] T-04.01 criterio com adjetivo | Reescrever |\n\nVEREDITO: NÃO — o plano não está pronto para execução autônoma.\n' "$2" "$3" "$3"
  else
    printf '# Auditoria — %s\n\nRodada %s\n\n| severidade | arquivo | problema | correção sugerida |\n|---|---|---|---|\n| MÉDIA | sprint-03/tasks.md | [item 2][fraco:teste] T-03.01 — cláusula: D-13 — passaria com: contadores trocados entre itens | Afirmar cada contador |\n\nVEREDITO: SIM — o plano está pronto para execução autônoma.\n' "$2" "$3"
  fi > "$(fdir "$1" "$2")/00-AUDITORIA.md"
}
ate_f5() { # ate_f5 <dir> <slug> [max por] — F1..F4 com checkpoints
  local f; f="$(fdir "$1" "$2")"
  if [ $# -ge 4 ]; then pl "$1" criar "$2" "$3" "$4" >/dev/null; else pl "$1" criar "$2" >/dev/null; fi
  printf 'decisoes\n' > "$f/00-DECISOES.md"; pl "$1" avanca "$2" f2 >/dev/null
  mkdir -p "$f/sprint-01"; printf 'plano\n' > "$f/sprint-01/tasks.md"; pl "$1" avanca "$2" f3 >/dev/null
  printf 'orquestrador\n' > "$f/ORQUESTRADOR.md"; pl "$1" avanca "$2" f4 >/dev/null
}
replaneja() { # replaneja <dir> <slug> <n> — a F3 muda o plano e a F4 roda de novo
  local f; f="$(fdir "$1" "$2")"
  printf 'plano v%s\n' "$3" > "$f/sprint-01/tasks.md"; pl "$1" avanca "$2" f3 >/dev/null
  printf 'orquestrador v%s\n' "$3" > "$f/ORQUESTRADOR.md"; pl "$1" avanca "$2" f4 >/dev/null
}

# A. F1 cria 00-PLANEJAMENTO; orcamento validado; template e script concordam.
D="$G/a"; nova_feature "$D" menu
s="$(pl "$D" criar menu)"; rc=$?; A_ARQ="$(fdir "$D" menu)/00-PLANEJAMENTO.md"
[ "$rc" -eq 0 ] && [ -f "$A_ARQ" ] && [ "$(fmv "$A_ARQ" kind)" = planejamento ] && [ "$(fmv "$A_ARQ" estado)" = null ] \
  && [ "$(fmv "$A_ARQ" max_reprovacoes_f5)" = null ] && [ "$(fmv "$A_ARQ" orcamento_declarado_por)" = null ] \
  && [ "$(fmv "$A_ARQ" reprovacoes)" = 0 ] && [ "$(fmv "$A_ARQ" trabalho_id)" = menu ]
afirma "ga-f1-cria-planejamento-sem-teto" $? "kind planejamento, estado null, null/null"
grep -q '{{' "$A_ARQ"; [ $? -ne 0 ]; afirma "ga2-sem-placeholder" $? "nenhum {{marcador}} no gerado"
CHAVES_T="$(tr -d '\r' < "$TPL" | awk 'NR==1{next} $0=="---"{exit} /^[a-z_]+:/{sub(/:.*/,""); print}' | tr '\n' ' ')"
CHAVES_G="$(tr -d '\r' < "$A_ARQ" | awk 'NR==1{next} $0=="---"{exit} /^[a-z_]+:/{sub(/:.*/,""); print}' | tr '\n' ' ')"
[ "$CHAVES_T" = "$CHAVES_G" ]; afirma "ga3-template-e-script-concordam" $? "$CHAVES_G"
D="$G/a2"; nova_feature "$D" menu
s="$(pl "$D" criar menu 3 buildx)"; rc=$?; A_ARQ="$(fdir "$D" menu)/00-PLANEJAMENTO.md"
[ "$rc" -eq 0 ] && [ "$(fmv "$A_ARQ" max_reprovacoes_f5)" = 3 ] && [ "$(fmv "$A_ARQ" orcamento_declarado_por)" = buildx ]
afirma "ga4-caller-declara-orcamento" $? "max 3 declarado por buildx"
pl "$D" criar menu 3 buildx >/dev/null; afirma "ga5-criar-de-novo-e-noop" $? "mesmo orcamento: no-op"
pl "$D" criar menu 5 buildx >/dev/null; [ $? -eq 4 ]; afirma "ga6-orcamento-nao-muda-em-silencio" $? "outro teto: erro de contrato"
for ruim in "0 buildx" "-1 buildx" "tres buildx" "2.5 buildx" "3 null" "null buildx" "3 BuildX"; do
  D="$G/a-ruim"; rm -rf "$D"; nova_feature "$D" menu
  g_nome="ga7-orcamento-invalido-$(printf '%s' "$ruim" | tr ' .' '__')"
  # shellcheck disable=SC2086
  pl "$D" criar menu $ruim >/dev/null; rc=$?
  [ "$rc" -eq 4 ] && [ ! -f "$(fdir "$D" menu)/00-PLANEJAMENTO.md" ]; g_rc=$?
  afirma "$g_nome" "$g_rc" "rc=$rc, nada gravado"
done

# B/C/D. Fim da F2, F3 e F4: estado + checkpoint com trailers.
D="$G/b"; nova_feature "$D" menu; F="$(fdir "$D" menu)"
pl "$D" criar menu >/dev/null; N0="$(ncommits "$D")"
printf 'decisoes\n' > "$F/00-DECISOES.md"
s="$(pl "$D" avanca menu f2)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" checkpoint)" = commitado ] && [ "$(fmv "$F/00-PLANEJAMENTO.md" estado)" = aguardando_f3 ] \
  && [ "$(ncommits "$D")" -eq $((N0 + 1)) ] && [ "$(trailer "$D" Fase)" = f2 ] && [ "$(trailer "$D" Estado)" = aguardando_f3 ] \
  && [ "$(trailer "$D" Planejamento)" = checkpoint ] && [ "$(trailer "$D" Trabalho)" = menu ] && [ "$(trailer "$D" Rodada)" = 0 ]
afirma "gb-fim-f2-checkpoint-aguardando-f3" $? "commit $(kv "$s" commit), trailers f2/aguardando_f3"
git -C "$D" log -1 --format=%s | grep -qxF 'chore(sprintx): checkpoint de planejamento menu — f2'
afirma "gb2-mensagem-canonica" $? "$(git -C "$D" log -1 --format=%s)"
git -C "$D" log -1 --format=%B | grep -q '^Task:'; [ $? -ne 0 ]; afirma "gb3-sem-trailer-task" $? "nao e commit E1"
git -C "$D" cat-file -e HEAD:docs/sprintx/features/menu/00-DECISOES.md 2>/dev/null; afirma "gb4-decisoes-no-historico" $? "00-DECISOES.md no HEAD"
mkdir -p "$F/sprint-01"; printf 'plano\n' > "$F/sprint-01/tasks.md"
s="$(pl "$D" avanca menu f3)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" checkpoint)" = commitado ] && [ "$(fmv "$F/00-PLANEJAMENTO.md" estado)" = aguardando_f4 ] \
  && [ "$(trailer "$D" Fase)" = f3 ] && [ "$(trailer "$D" Estado)" = aguardando_f4 ] \
  && git -C "$D" cat-file -e HEAD:docs/sprintx/features/menu/sprint-01/tasks.md 2>/dev/null
afirma "gc-fim-f3-checkpoint-aguardando-f4" $? "plano no HEAD, trailers f3/aguardando_f4"
printf 'orquestrador\n' > "$F/ORQUESTRADOR.md"
s="$(pl "$D" avanca menu f4)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" checkpoint)" = commitado ] && [ "$(fmv "$F/00-PLANEJAMENTO.md" estado)" = aguardando_f5 ] \
  && [ "$(trailer "$D" Fase)" = f4 ] && [ "$(trailer "$D" Estado)" = aguardando_f5 ] \
  && git -C "$D" cat-file -e HEAD:docs/sprintx/features/menu/ORQUESTRADOR.md 2>/dev/null
afirma "gd-fim-f4-checkpoint-aguardando-f5" $? "orquestrador no HEAD, trailers f4/aguardando_f5"
[ "$(kv "$(pl "$D" fase menu)" fase)" = F5 ]; afirma "gd2-aguardando-f5-e-f5" $? "fase F5"

# Q. Idempotencia: mesmo estado, nada a commitar -> no-op, HEAD e arquivo intactos.
H0="$(git -C "$D" rev-parse HEAD)"; CK0="$(cksum < "$F/00-PLANEJAMENTO.md")"
s="$(pl "$D" checkpoint menu)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" checkpoint)" = sem_mudanca ] && [ "$(git -C "$D" rev-parse HEAD)" = "$H0" ]
afirma "gq-checkpoint-repetido-e-noop" $? "$(kv "$s" checkpoint)"
s="$(pl "$D" avanca menu f4)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" checkpoint)" = sem_mudanca ] && [ "$(git -C "$D" rev-parse HEAD)" = "$H0" ] \
  && [ "$(cksum < "$F/00-PLANEJAMENTO.md")" = "$CK0" ]
afirma "gq2-avanca-repetido-e-noop" $? "HEAD e 00-PLANEJAMENTO.md intactos"

# E. F5 SIM: aprovado + checkpoint + F6.
cp -R "$D" "$G/e"; D="$G/e"; F="$(fdir "$D" menu)"
auditoria "$D" menu 1 SIM
s="$(pl "$D" avanca menu f5)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" estado)" = aprovado ] && [ "$(kv "$s" proxima)" = F6 ] && [ "$(kv "$s" checkpoint)" = commitado ] \
  && [ "$(trailer "$D" Fase)" = f5 ] && [ "$(trailer "$D" Rodada)" = 1 ] && [ "$(trailer "$D" Estado)" = aprovado ] \
  && [ "$(kv "$(pl "$D" fase menu)" fase)" = F6 ]
afirma "ge-f5-sim-aprovado-checkpoint-f6" $? "aprovado, rodada 1, fase F6"
[ "$(fmv "$F/00-PLANEJAMENTO.md" reprovacoes)" = 0 ] && tr -d '\r' < "$F/00-PLANEJAMENTO.md" | grep -qx '    veredito: sim'
afirma "ge2-sim-nao-consome-orcamento" $? "reprovacoes 0, historico sim"
pl "$D" avanca menu f5 >/dev/null; [ $? -eq 5 ]; afirma "ge3-aprovado-nao-reaudita" $? "nova F5 recusada"

# F. F5 NAO sem teto: replanejar + checkpoint + F3.
D="$G/f"; nova_feature "$D" menu; ate_f5 "$D" menu; F="$(fdir "$D" menu)"
auditoria "$D" menu 1 NAO
s="$(pl "$D" avanca menu f5)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" estado)" = replanejar ] && [ "$(kv "$s" proxima)" = F3 ] && [ "$(kv "$s" checkpoint)" = commitado ] \
  && [ "$(trailer "$D" Estado)" = replanejar ] && [ "$(fmv "$F/00-PLANEJAMENTO.md" reprovacoes)" = 1 ]
afirma "gf-f5-nao-null-replanejar-f3" $? "replanejar, reprovacoes 1, checkpoint"

# I. replanejar nunca vai direto para a F5.
[ "$(kv "$(pl "$D" fase menu)" fase)" = F3 ]; afirma "gi-replanejar-e-f3" $? "fase F3"
CK0="$(cksum < "$F/00-PLANEJAMENTO.md")"; pl "$D" avanca menu f5 >/dev/null; rc=$?
[ "$rc" -eq 5 ] && [ "$(cksum < "$F/00-PLANEJAMENTO.md")" = "$CK0" ]
afirma "gi2-replanejar-recusa-f5" $? "rc=$rc, nenhuma rodada nova"
for r in 2 3 4; do replaneja "$D" menu "$r"; auditoria "$D" menu "$r" NAO; pl "$D" avanca menu f5 >/dev/null; done
[ "$(fmv "$F/00-PLANEJAMENTO.md" estado)" = replanejar ] && [ "$(fmv "$F/00-PLANEJAMENTO.md" reprovacoes)" = 4 ]
afirma "gf2-null-nunca-esgota" $? "4 reprovacoes sem teto: replanejar"

# G/H/J/K. Teto 3: o piloto. Terceiro NAO -> orcamento_esgotado; historico no Git.
D="$G/g"; nova_feature "$D" menu; git init -q --bare "$G/remoto.git"; git -C "$D" remote add origin "$G/remoto.git"
ate_f5 "$D" menu 3 buildx; F="$(fdir "$D" menu)"
printf 'export const y = 2\n' >> "$D/src/app.ts"; printf 'novo\n' > "$D/src/novo.ts"   # produto sujo, fora do indice
auditoria "$D" menu 1 NAO; s1="$(pl "$D" avanca menu f5)"
replaneja "$D" menu 2; auditoria "$D" menu 2 NAO; s2="$(pl "$D" avanca menu f5)"
replaneja "$D" menu 3; auditoria "$D" menu 3 NAO; s3="$(pl "$D" avanca menu f5)"; rc3=$?
[ "$(kv "$s1" estado)" = replanejar ] && [ "$(kv "$s1" reprovacoes)" = 1 ] && [ "$(kv "$s2" estado)" = replanejar ] \
  && [ "$(kv "$s2" reprovacoes)" = 2 ] && [ "$rc3" -eq 0 ] && [ "$(kv "$s3" estado)" = orcamento_esgotado ] \
  && [ "$(kv "$s3" reprovacoes)" = 3 ] && [ "$(kv "$s3" checkpoint)" = commitado ] && [ "$(trailer "$D" Estado)" = orcamento_esgotado ]
afirma "gg-max3-terceiro-nao-esgota" $? "1 replanejar, 2 replanejar, 3 orcamento_esgotado"
[ "$(kv "$s3" proxima)" = PARAR ] && [ "$(kv "$(pl "$D" fase menu)" fase)" = PARAR ]; afirma "gh-esgotado-e-terminal" $? "fase PARAR"
H0="$(git -C "$D" rev-parse HEAD)"; bad=0
for fz in f2 f3 f4 f5; do pl "$D" avanca menu "$fz" >/dev/null; [ $? -eq 5 ] || bad=1; done
[ "$bad" -eq 0 ] && [ "$(git -C "$D" rev-parse HEAD)" = "$H0" ] && [ "$(fmv "$F/00-PLANEJAMENTO.md" estado)" = orcamento_esgotado ]
afirma "gh2-esgotado-nunca-f6-nem-f5-nem-f3" $? "toda transicao recusada, estado preservado"
case "$(pl "$D" fase menu)" in *F6*) false ;; *) true ;; esac; afirma "gh3-esgotado-nunca-f6" $? "fase nunca F6"
NAUDH="$(git -C "$D" log --format=%H -- docs/sprintx/features/menu/00-AUDITORIA.md | wc -l | tr -d ' ')"
LOGP="$(git -C "$D" log -p -- docs/sprintx/features/menu/00-AUDITORIA.md)"
[ "$NAUDH" -eq 3 ] && printf '%s' "$LOGP" | grep -q '^+Rodada 1$' && printf '%s' "$LOGP" | grep -q '^+Rodada 2$' \
  && printf '%s' "$LOGP" | grep -q '^+Rodada 3$'
afirma "gj-tres-auditorias-no-git-log" $? "$NAUDH versao(oes) de 00-AUDITORIA.md recuperaveis"
ls "$F" | grep -qE '^AUDITORIA-[0-9]'; [ $? -ne 0 ]; afirma "gj2-sem-auditoria-numerada" $? "uma fonte viva"
R1="$(git -C "$D" log --format=%H -- docs/sprintx/features/menu/00-AUDITORIA.md | tail -1)"
H1="$(git -C "$D" show "$R1:docs/sprintx/features/menu/00-PLANEJAMENTO.md" | tr -d '\r' | sed -n '/^  - rodada: 1$/,/auditado_em/p')"
HN="$(tr -d '\r' < "$F/00-PLANEJAMENTO.md" | sed -n '/^  - rodada: 1$/,/auditado_em/p')"
[ -n "$H1" ] && [ "$H1" = "$HN" ] && [ "$(tr -d '\r' < "$F/00-PLANEJAMENTO.md" | grep -c '^  - rodada: ')" -eq 3 ]
afirma "gj3-historico-append-only" $? "rodada 1 identica depois de 3 rodadas"
fora=0
for c in $(git -C "$D" log --format=%H --grep='^Planejamento: checkpoint$'); do
  for p in $(git -C "$D" show --name-only --format= "$c"); do
    case "$p" in docs/sprintx/features/menu/*) ;; *) fora=1 ;; esac
  done
done
NCP="$(git -C "$D" log --format=%H --grep='^Planejamento: checkpoint$' | wc -l | tr -d ' ')"
[ "$fora" -eq 0 ] && [ "$NCP" -eq 10 ]; afirma "gk-checkpoint-so-pasta-da-feature" $? "$NCP checkpoints, nenhum path fora do prefixo"
git -C "$D" status --porcelain --untracked-files=all -- src | grep -q ' src/app.ts' \
  && git -C "$D" status --porcelain --untracked-files=all -- src | grep -q '?? src/novo.ts'
afirma "gk2-produto-sujo-intocado" $? "src/app.ts e src/novo.ts continuam sujos, fora dos commits"

# P. Nenhum push feito pelo checkpoint.
[ -z "$(git -C "$G/remoto.git" for-each-ref)" ] && [ -z "$(git -C "$D" for-each-ref refs/remotes)" ]
afirma "gp-nenhum-push" $? "remoto sem nenhuma ref depois de $NCP checkpoints"
grep -vE '^[[:space:]]*#' "$PL" | grep -qE 'git[^|;]*[[:space:]]push'; [ $? -ne 0 ]; afirma "gp2-script-sem-push" $? "nenhum git push no codigo"
grep -vE '^[[:space:]]*#' "$PL" | grep -qF -- '--no-verify'; [ $? -ne 0 ]; afirma "go2-script-sem-no-verify" $? "nunca --no-verify"

# L. Arquivo de produto staged: checkpoint recusa, sem limpar nada.
D="$G/l"; nova_feature "$D" menu; pl "$D" criar menu >/dev/null; F="$(fdir "$D" menu)"
printf 'decisoes\n' > "$F/00-DECISOES.md"
printf 'export const z = 3\n' >> "$D/src/app.ts"; git -C "$D" add src/app.ts
H0="$(git -C "$D" rev-parse HEAD)"
s="$(pl "$D" avanca menu f2)"; rc=$?
[ "$rc" -eq 2 ] && [ "$(kv "$s" checkpoint)" = recusado_paths ] && [ "$(git -C "$D" rev-parse HEAD)" = "$H0" ] \
  && git -C "$D" diff --cached --name-only | grep -qx 'src/app.ts'
afirma "gl-produto-staged-recusa" $? "rc=$rc, HEAD intacto, src/app.ts continua staged"
grep -q '"resultado":"bloqueado"' "$D/docs/eventos/menu.jsonl" 2>/dev/null; afirma "gl2-recusa-no-rastro" $? "checkpoint_planejamento bloqueado"
for prod in package.json docs/projeto/PROJETO.md docs/stack/CONVENCOES.md docs/entregas/menu/ENTREGA.md tests/a.test.ts docs/sprintx/features/menu-outra/x.md; do
  D="$G/l2"; rm -rf "$D"; nova_feature "$D" menu; pl "$D" criar menu >/dev/null; F="$(fdir "$D" menu)"
  printf 'decisoes\n' > "$F/00-DECISOES.md"; mkdir -p "$D/$(dirname "$prod")"; printf 'x\n' > "$D/$prod"; git -C "$D" add -f "$prod"
  g_nome="gl3-recusa-$(printf '%s' "$prod" | tr '/.' '__')"
  pl "$D" avanca menu f2 >/dev/null; [ $? -eq 2 ]; g_rc=$?
  afirma "$g_nome" "$g_rc" "staged fora do prefixo"
done

# M. Branch principal: estado gravado, nenhum commit.
D="$G/m"; nova_feature "$D" menu main; pl "$D" criar menu >/dev/null; F="$(fdir "$D" menu)"
printf 'decisoes\n' > "$F/00-DECISOES.md"; N0="$(ncommits "$D")"
s="$(pl "$D" avanca menu f2)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" checkpoint)" = ignorado_branch ] && [ "$(ncommits "$D")" -eq "$N0" ] \
  && [ "$(fmv "$F/00-PLANEJAMENTO.md" estado)" = aguardando_f3 ] && grep -q '"resultado":"aviso"' "$D/docs/eventos/menu.jsonl"
afirma "gm-main-nao-commita" $? "ignorado_branch, estado no disco, aviso no rastro"
s="$(pl "$D" fase menu)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" fase)" = F3 ] && [ "$(kv "$s" persistencia)" = disco ]
afirma "gm3-main-estado-do-disco-governa" $? "sem worktree: fase $(kv "$s" fase), persistencia $(kv "$s" persistencia)"
D="$G/m2"; nova_feature "$D" menu feature/outra; pl "$D" criar menu >/dev/null; printf 'd\n' > "$(fdir "$D" menu)/00-DECISOES.md"
N0="$(ncommits "$D")"; s="$(pl "$D" avanca menu f2)"
[ "$(kv "$s" checkpoint)" = ignorado_branch ] && [ "$(ncommits "$D")" -eq "$N0" ]; afirma "gm2-outra-feature-nao-commita" $? "branch exatamente feature/<slug>"

# N. Sem Git: degradacao graciosa.
D="$G/semgit/n"; mkdir -p "$D/docs/sprintx/features/menu/base"; F="$(fdir "$D" menu)"
s="$(cd "$D" && GIT_CEILING_DIRECTORIES="$G/semgit" bash "$PL" criar menu 2>&1)"; rc1=$?
printf 'decisoes\n' > "$F/00-DECISOES.md"
s="$(cd "$D" && GIT_CEILING_DIRECTORIES="$G/semgit" bash "$PL" avanca menu f2 2>&1)"; rc=$?
[ "$rc1" -eq 0 ] && [ "$rc" -eq 0 ] && [ "$(kv "$s" checkpoint)" = ignorado_sem_git ] \
  && [ "$(fmv "$F/00-PLANEJAMENTO.md" estado)" = aguardando_f3 ] && grep -q 'sem Git' "$D/docs/eventos/menu.jsonl"
afirma "gn-sem-git-degrada" $? "ignorado_sem_git, estado gravado, aviso no rastro"
s="$(cd "$D" && GIT_CEILING_DIRECTORIES="$G/semgit" bash "$PL" fase menu 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" fase)" = F3 ] && [ "$(kv "$s" persistencia)" = disco ]
afirma "gn2-sem-git-estado-do-disco-governa" $? "fase $(kv "$s" fase), persistencia $(kv "$s" persistencia)"

# O. Hook do projeto rejeita o commit: persistencia_falhou, nada limpo.
D="$G/o"; nova_feature "$D" menu; pl "$D" criar menu >/dev/null; F="$(fdir "$D" menu)"
printf '#!/bin/sh\necho "hook do projeto recusou" >&2\nexit 1\n' > "$D/.git/hooks/pre-commit"; chmod +x "$D/.git/hooks/pre-commit"
printf 'decisoes\n' > "$F/00-DECISOES.md"; H0="$(git -C "$D" rev-parse HEAD)"
s="$(pl "$D" avanca menu f2)"; rc=$?
[ "$rc" -eq 3 ] && [ "$(kv "$s" checkpoint)" = persistencia_falhou ] && [ "$(git -C "$D" rev-parse HEAD)" = "$H0" ] \
  && grep -q 'persistencia_falhou' "$D/docs/eventos/menu.jsonl" && [ -f "$F/00-DECISOES.md" ]
afirma "go-hook-rejeita-persistencia-falhou" $? "rc=$rc, HEAD intacto, rastro registra"
rm -f "$D/.git/hooks/pre-commit"; s="$(pl "$D" checkpoint menu)"
[ "$(kv "$s" checkpoint)" = commitado ] && [ "$(trailer "$D" Estado)" = aguardando_f3 ]; afirma "go3-checkpoint-refeito" $? "retry pelo comando checkpoint"

# CP. Checkpoint pendente: estado gravado e nao persistido no HEAD nao governa.
# O hook sintetico recusa enquanto existir .git/REJEITAR — "retirar a causa" e apagar o marcador.
rejeitador() {
  printf '#!/bin/sh\n[ -f "$(git rev-parse --git-dir)/REJEITAR" ] || exit 0\necho "hook sintetico recusou" >&2\nexit 1\n' > "$1/.git/hooks/pre-commit"
  chmod +x "$1/.git/hooks/pre-commit"; : > "$1/.git/REJEITAR"
}
head_fmv() { git -C "$1" show "HEAD:docs/sprintx/features/$2/00-PLANEJAMENTO.md" > "$G/.head" 2>/dev/null || : > "$G/.head"; fmv "$G/.head" "$3"; }
rodadas() { tr -d '\r' | grep -c '^  - rodada: '; }
n_fase() { git -C "$1" log --format=%H --grep="^Fase: $2\$" | wc -l | tr -d ' '; }
so_prefixo() { # todo commit de checkpoint toca so a pasta da feature
  local c p; for c in $(git -C "$1" log --format=%H --grep='^Planejamento: checkpoint$'); do
    for p in $(git -C "$1" show --name-only --format= "$c"); do case "$p" in docs/sprintx/features/"$2"/*) ;; *) return 1 ;; esac; done
  done
}

# Teste principal: F3 termina, hook recusa, sessao morre, nova sessao retoma.
D="$G/cp"; nova_feature "$D" menu; F="$(fdir "$D" menu)"
pl "$D" criar menu >/dev/null; printf 'decisoes\n' > "$F/00-DECISOES.md"; pl "$D" avanca menu f2 >/dev/null
printf 'export const y = 2\n' >> "$D/src/app.ts"                                     # produto sujo, fora do indice
rejeitador "$D"; H0="$(git -C "$D" rev-parse HEAD)"; N0="$(ncommits "$D")"; NF3="$(n_fase "$D" f3)"
mkdir -p "$F/sprint-01"; printf 'plano\n' > "$F/sprint-01/tasks.md"
s="$(pl "$D" avanca menu f3)"; rc=$?
[ "$rc" -eq 3 ] && [ "$(kv "$s" checkpoint)" = persistencia_falhou ] && [ "$(kv "$s" persistencia)" = pendente ]
afirma "gcp1-hook-recusa-persistencia-falhou" $? "rc=$rc, $(kv "$s" checkpoint)"
[ -f "$F/sprint-01/tasks.md" ] && [ "$(fmv "$F/00-PLANEJAMENTO.md" estado)" = aguardando_f4 ]
afirma "gcp2-working-tree-mantem-evidencia" $? "plano e estado aguardando_f4 no disco"
[ "$(git -C "$D" rev-parse HEAD)" = "$H0" ] && [ "$(head_fmv "$D" menu estado)" = aguardando_f3 ]
afirma "gcp3-head-no-checkpoint-anterior" $? "HEAD ainda em aguardando_f3"
s="$(pl "$D" fase menu)"; rc=$?
[ "$rc" -eq 3 ] && [ "$(kv "$s" fase)" = CHECKPOINT ] && [ "$(kv "$s" estado)" = aguardando_f4 ] && [ "$(kv "$s" persistencia)" = pendente ] \
  && printf '%s' "$s" | grep -qF "planejamento.sh checkpoint menu"
afirma "gcp4-fase-pede-checkpoint" $? "rc=$rc fase=$(kv "$s" fase) persistencia=$(kv "$s" persistencia)"
case "$s" in *fase=F4*) false ;; *) true ;; esac; afirma "gcp5-fase-nao-devolve-proxima" $? "nunca F4 com checkpoint pendente"
CK0="$(cksum < "$F/00-PLANEJAMENTO.md")"
s="$(pl "$D" avanca menu f4)"; rc=$?
[ "$rc" -eq 3 ] && [ "$(kv "$s" proxima)" = CHECKPOINT ] && [ "$(cksum < "$F/00-PLANEJAMENTO.md")" = "$CK0" ] \
  && [ "$(fmv "$F/00-PLANEJAMENTO.md" estado)" = aguardando_f4 ] && [ "$(git -C "$D" rev-parse HEAD)" = "$H0" ]
afirma "gcp6-avanca-recusado-com-pendente" $? "rc=$rc, estado e HEAD intactos"
bad=0; for fz in f2 f3 f5; do pl "$D" avanca menu "$fz" >/dev/null; [ $? -eq 3 ] || bad=1; done
[ "$bad" -eq 0 ] && [ "$(cksum < "$F/00-PLANEJAMENTO.md")" = "$CK0" ]; afirma "gcp7-nenhuma-transicao-com-pendente" $? "f2, f3 e f5 recusadas, arquivo intacto"
grep -q '"resultado":"bloqueado".*avanca f4 recusado' "$D/docs/eventos/menu.jsonl"; afirma "gcp8-recusa-no-rastro" $? "bloqueado"
s="$(pl "$D" checkpoint menu)"; rc=$?
[ "$rc" -eq 3 ] && [ "$(cksum < "$F/00-PLANEJAMENTO.md")" = "$CK0" ] && [ "$(git -C "$D" rev-parse HEAD)" = "$H0" ]
afirma "gcp9-retry-com-causa-ainda-falha-sem-mudar" $? "rc=$rc, estado intacto"
rm -f "$D/.git/REJEITAR"
s="$(pl "$D" checkpoint menu)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" checkpoint)" = commitado ] && [ "$(ncommits "$D")" -eq $((N0 + 1)) ] \
  && [ "$(head_fmv "$D" menu estado)" = aguardando_f4 ] && [ "$(trailer "$D" Fase)" = f3 ] && [ "$(trailer "$D" Estado)" = aguardando_f4 ] \
  && git -C "$D" cat-file -e HEAD:docs/sprintx/features/menu/sprint-01/tasks.md 2>/dev/null && [ "$(cksum < "$F/00-PLANEJAMENTO.md")" = "$CK0" ]
afirma "gcp10-checkpoint-persiste-o-mesmo-estado" $? "um commit, HEAD em aguardando_f4, arquivo byte a byte igual"
s="$(pl "$D" fase menu)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" fase)" = F4 ] && [ "$(kv "$s" persistencia)" = duravel ]; afirma "gcp11-fase-normal-depois-do-commit" $? "fase $(kv "$s" fase), $(kv "$s" persistencia)"
[ "$(n_fase "$D" f3)" -eq $((NF3 + 1)) ] && [ "$(fmv "$F/00-PLANEJAMENTO.md" reprovacoes)" = 0 ] && [ "$(rodadas < "$F/00-PLANEJAMENTO.md")" -eq 0 ]
afirma "gcp12-historico-sem-duplicata" $? "um checkpoint f3, nenhuma rodada"
so_prefixo "$D" menu && git -C "$D" status --porcelain -- src | grep -q ' src/app.ts'; afirma "gcp13-produto-intocado" $? "src/app.ts sujo e fora dos checkpoints"
pl "$D" checkpoint menu >/dev/null && [ "$(ncommits "$D")" -eq $((N0 + 1)) ]; afirma "gcp14-checkpoint-idempotente" $? "sem_mudanca depois do verde"
printf 'orquestrador\n' > "$F/ORQUESTRADOR.md"; s="$(pl "$D" avanca menu f4)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" estado)" = aguardando_f5 ]; afirma "gcp15-fluxo-retoma" $? "avanca f4 depois do checkpoint"
# Trabalho da fase seguinte em curso nao e pendencia: so o estado nao persistido e.
printf 'plano v2 em edicao\n' > "$F/sprint-01/tasks.md"
s="$(pl "$D" fase menu)"; [ $? -eq 0 ] && [ "$(kv "$s" fase)" = F5 ]; afirma "gcp16-trabalho-em-curso-nao-e-pendencia" $? "pasta suja, estado no HEAD: F5"
git -C "$D" checkout -q -- "$F/sprint-01/tasks.md"
# Estado staged e nao commitado tambem e pendencia (indice conta).
cp "$F/00-PLANEJAMENTO.md" "$G/cp-plan"; sed 's/^estado: aguardando_f5$/estado: aguardando_f4/' "$G/cp-plan" > "$F/00-PLANEJAMENTO.md"
git -C "$D" add "$F/00-PLANEJAMENTO.md"; cp "$G/cp-plan" "$F/00-PLANEJAMENTO.md"
s="$(pl "$D" fase menu)"; [ $? -eq 3 ] && [ "$(kv "$s" fase)" = CHECKPOINT ]; afirma "gcp17-indice-conta" $? "working tree igual ao HEAD, indice diferente: pendente"
git -C "$D" reset -q -- "$F/00-PLANEJAMENTO.md"

# F5 NAO -> replanejar, checkpoint recusado.
D="$G/cpn"; nova_feature "$D" menu; ate_f5 "$D" menu; F="$(fdir "$D" menu)"
rejeitador "$D"; H0="$(git -C "$D" rev-parse HEAD)"; auditoria "$D" menu 1 NAO
s="$(pl "$D" avanca menu f5)"; rc=$?
[ "$rc" -eq 3 ] && [ "$(fmv "$F/00-PLANEJAMENTO.md" estado)" = replanejar ] && [ "$(fmv "$F/00-PLANEJAMENTO.md" reprovacoes)" = 1 ] \
  && [ "$(rodadas < "$F/00-PLANEJAMENTO.md")" -eq 1 ]
afirma "gcn1-f5-nao-no-disco" $? "rc=$rc, replanejar, reprovacoes 1, uma rodada"
[ "$(git -C "$D" rev-parse HEAD)" = "$H0" ] && [ "$(head_fmv "$D" menu estado)" = aguardando_f5 ]
afirma "gcn2-head-ainda-aguardando-f5" $? "checkpoint anterior"
s="$(pl "$D" fase menu)"; rc=$?
[ "$rc" -eq 3 ] && [ "$(kv "$s" fase)" = CHECKPOINT ] && [ "$(kv "$s" estado)" = replanejar ]; afirma "gcn3-retomada-pede-checkpoint" $? "fase $(kv "$s" fase), nunca F3"
CK0="$(cksum < "$F/00-PLANEJAMENTO.md")"
pl "$D" avanca menu f3 >/dev/null; rc=$?
[ "$rc" -eq 3 ] && [ "$(cksum < "$F/00-PLANEJAMENTO.md")" = "$CK0" ]; afirma "gcn4-nao-executa-f3-ainda" $? "avanca f3 recusado (rc=$rc)"
pl "$D" avanca menu f5 >/dev/null; rc=$?
[ "$rc" -eq 3 ] && [ "$(fmv "$F/00-PLANEJAMENTO.md" reprovacoes)" = 1 ] && [ "$(rodadas < "$F/00-PLANEJAMENTO.md")" -eq 1 ]
afirma "gcn5-nao-reaudita-nem-soma-reprovacao" $? "rc=$rc, reprovacoes 1"
pl "$D" checkpoint menu >/dev/null; pl "$D" checkpoint menu >/dev/null   # dois retries ainda recusados
[ "$(rodadas < "$F/00-PLANEJAMENTO.md")" -eq 1 ] && [ "$(cksum < "$F/00-PLANEJAMENTO.md")" = "$CK0" ]; afirma "gcn6-retry-recusado-nao-cria-rodada" $? "uma rodada"
rm -f "$D/.git/REJEITAR"; s="$(pl "$D" checkpoint menu)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" checkpoint)" = commitado ] && [ "$(trailer "$D" Rodada)" = 1 ] && [ "$(trailer "$D" Estado)" = replanejar ] \
  && [ "$(git -C "$D" show HEAD:docs/sprintx/features/menu/00-PLANEJAMENTO.md | rodadas)" -eq 1 ] && [ "$(head_fmv "$D" menu reprovacoes)" = 1 ]
afirma "gcn7-retry-verde-sem-rodada-2" $? "HEAD: rodada 1, reprovacoes 1"
s="$(pl "$D" fase menu)"; [ $? -eq 0 ] && [ "$(kv "$s" fase)" = F3 ]; afirma "gcn8-fase-f3-depois-do-commit" $? "fase $(kv "$s" fase)"

# Terceiro NAO -> orcamento_esgotado, checkpoint recusado.
D="$G/cpe"; nova_feature "$D" menu; ate_f5 "$D" menu 3 buildx; F="$(fdir "$D" menu)"
auditoria "$D" menu 1 NAO; pl "$D" avanca menu f5 >/dev/null
replaneja "$D" menu 2; auditoria "$D" menu 2 NAO; pl "$D" avanca menu f5 >/dev/null
replaneja "$D" menu 3; rejeitador "$D"; auditoria "$D" menu 3 NAO
s="$(pl "$D" avanca menu f5)"; rc=$?
[ "$rc" -eq 3 ] && [ "$(fmv "$F/00-PLANEJAMENTO.md" estado)" = orcamento_esgotado ] && [ "$(head_fmv "$D" menu estado)" = aguardando_f5 ]
afirma "gce1-esgotado-so-no-disco" $? "rc=$rc, HEAD em aguardando_f5"
s="$(pl "$D" fase menu)"; rc=$?
[ "$rc" -eq 3 ] && [ "$(kv "$s" fase)" = CHECKPOINT ] && [ "$(kv "$s" estado)" = orcamento_esgotado ]
afirma "gce2-esgotado-nao-persistido-nao-e-parar" $? "fase $(kv "$s" fase), rc=$rc"
rm -f "$D/.git/REJEITAR"; pl "$D" checkpoint menu >/dev/null
s="$(pl "$D" fase menu)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" fase)" = PARAR ] && [ "$(head_fmv "$D" menu estado)" = orcamento_esgotado ] \
  && [ "$(head_fmv "$D" menu reprovacoes)" = 3 ] && [ "$(git -C "$D" show HEAD:docs/sprintx/features/menu/00-PLANEJAMENTO.md | rodadas)" -eq 3 ]
afirma "gce3-parar-depois-do-checkpoint" $? "fase $(kv "$s" fase), 3 rodadas no HEAD"

# F5 SIM -> aprovado, checkpoint recusado: nunca F6 com aprovacao so no working tree.
D="$G/cpa"; nova_feature "$D" menu; ate_f5 "$D" menu; F="$(fdir "$D" menu)"
rejeitador "$D"; auditoria "$D" menu 1 SIM
s="$(pl "$D" avanca menu f5)"; rc=$?
[ "$rc" -eq 3 ] && [ "$(fmv "$F/00-PLANEJAMENTO.md" estado)" = aprovado ] && [ "$(head_fmv "$D" menu estado)" = aguardando_f5 ]
afirma "gca1-aprovado-so-no-disco" $? "rc=$rc"
s="$(pl "$D" fase menu)"; rc=$?
[ "$rc" -eq 3 ] && [ "$(kv "$s" fase)" = CHECKPOINT ]; afirma "gca2-aprovado-nao-persistido-nao-e-f6" $? "fase $(kv "$s" fase), rc=$rc"
rm -f "$D/.git/REJEITAR"; pl "$D" checkpoint menu >/dev/null
s="$(pl "$D" fase menu)"; [ $? -eq 0 ] && [ "$(kv "$s" fase)" = F6 ] && [ "$(head_fmv "$D" menu estado)" = aprovado ]
afirma "gca3-f6-depois-do-checkpoint" $? "fase $(kv "$s" fase)"

# R/S. Feature legada, sem 00-PLANEJAMENTO.md.
# A F1 seguindo o contrato: cada linha da tabela "pedido -> comando" de 01-ingestao.md e
# executada de verdade (o comando sai do documento, nao do teste) e o arquivo gravado tem de
# ter exatamente os tetos que o pedido declarou — `null` no que ele nao declarou, nunca um 1
# presumido. f1_orcamento <01-ingestao.md> — imprime o motivo da primeira falha.
f1_orcamento() {
  local doc="$1" linhas n=0 f6=0 sem6=0 ped cmd args k esp v d a
  linhas="$(tr -d '\r' < "$doc" | awk '/^\| O pedido declara \| Comando \|$/{t=1; next} t && /^\|---/{next} t && /^\|/{print; next} t{exit}')"
  [ -n "$linhas" ] || { printf 'tabela pedido -> comando ausente'; return 1; }
  while IFS= read -r l; do
    ped="$(printf '%s' "$l" | cut -d'|' -f2)"; cmd="$(printf '%s' "$l" | cut -d'|' -f3 | sed 's/^ *`//; s/` *$//')"
    case "$cmd" in "criar <slug>"|"criar <slug> "*) ;; *) printf 'comando fora da forma: %s' "$cmd"; return 1 ;; esac
    n=$((n + 1)); args="${cmd#criar <slug>}"
    d="$G/f1-$n"; rm -rf "$d"; nova_feature "$d" menu
    # shellcheck disable=SC2086
    pl "$d" criar menu $args >/dev/null || { printf 'linha %s: criar menu%s falhou' "$n" "$args"; return 1; }
    a="$(fdir "$d" menu)/00-PLANEJAMENTO.md"
    for k in max_reprovacoes_f5 orcamento_declarado_por max_replanejamentos_f6; do
      esp="$(printf '%s' "$ped" | tr ',' '\n' | sed -n "s/^ *\`$k: \([^\`]*\)\` *\$/\1/p")"; [ -n "$esp" ] || esp=null
      v="$(fmv "$a" "$k")"
      [ "$v" = "$esp" ] || { printf 'linha %s (%s): %s=%s, o pedido declara %s' "$n" "$cmd" "$k" "$v" "$esp"; return 1; }
      if [ "$k" = max_replanejamentos_f6 ]; then if [ "$esp" = null ]; then sem6=$((sem6 + 1)); else f6=$((f6 + 1)); fi; fi
    done
    [ "$(fmv "$a" replanejamentos_f6)" = 0 ] || { printf 'linha %s: replanejamentos_f6 nao nasce 0' "$n"; return 1; }
  done <<EOF
$linhas
EOF
  [ "$f6" -ge 1 ] && [ "$sem6" -ge 1 ] || { printf '%s linha(s) com teto da F6, %s sem' "$f6" "$sem6"; return 1; }
  printf 'ok'
}
m="$(f1_orcamento "$SK/references/01-ingestao.md")"; [ "$m" = ok ]; afirma "ga8-f1-repassa-os-tres-tetos-do-pedido" $? "$m"
D="$G/f1-buildx"; nova_feature "$D" menu; A_ARQ="$(fdir "$D" menu)/00-PLANEJAMENTO.md"
tem "$SK/references/01-ingestao.md" '| `max_reprovacoes_f5: 3`, `orcamento_declarado_por: buildx`, `max_replanejamentos_f6: 1` | `criar <slug> 3 buildx 1` |' \
  && tem "$SK/references/01-ingestao.md" "$CMD_PL criar <slug> [max_reprovacoes_f5] [orcamento_declarado_por] [max_replanejamentos_f6]" \
  && pl "$D" criar menu 3 buildx 1 >/dev/null && [ "$(fmv "$A_ARQ" max_replanejamentos_f6)" = 1 ] && [ "$(fmv "$A_ARQ" replanejamentos_f6)" = 0 ]
afirma "ga9-f1-briefing-buildx-grava-1-de-0" $? "max_replanejamentos_f6: 1, replanejamentos_f6: 0"
D="$G/f1-sem"; nova_feature "$D" menu; A_ARQ="$(fdir "$D" menu)/00-PLANEJAMENTO.md"
pl "$D" criar menu >/dev/null && [ "$(fmv "$A_ARQ" max_replanejamentos_f6)" = null ] && [ "$(fmv "$A_ARQ" replanejamentos_f6)" = 0 ] \
  && D="$G/f1-so-f5" && nova_feature "$D" menu && pl "$D" criar menu 3 buildx >/dev/null \
  && [ "$(fmv "$(fdir "$D" menu)/00-PLANEJAMENTO.md" max_replanejamentos_f6)" = null ]
afirma "ga10-f1-sem-orcamento-nao-ganha-1" $? "sem pedido e so com a F5: max_replanejamentos_f6 null"
# Auto-teste: a tabela com o contrato antigo (F6 do BuildX sem o quarto argumento) e com um 1
# presumido para quem nao declarou tem de reprovar.
ING="$SK/references/01-ingestao.md"
muta_ing() { ML_A="$2" ML_B="$3" awk '{ a = ENVIRON["ML_A"]; i = index($0, a); if (i) { $0 = substr($0, 1, i - 1) ENVIRON["ML_B"] substr($0, i + length(a)); n++ } print } END { exit n ? 0 : 1 }' "$ING" > "$1"; }
muta_ing "$G/ing-a.md" '`max_replanejamentos_f6: 1` | `criar <slug> 3 buildx 1` |' '`max_replanejamentos_f6: 1` | `criar <slug> 3 buildx` |'; rc=$?
m="$(f1_orcamento "$G/ing-a.md")"; [ "$rc" -eq 0 ] && [ "$m" != ok ]; afirma "ga11-mutante-f1-contrato-antigo" $? "morto: $m"
muta_ing "$G/ing-b.md" '`orcamento_declarado_por: buildx` | `criar <slug> 3 buildx` |' '`orcamento_declarado_por: buildx` | `criar <slug> 3 buildx 1` |'; rc=$?
m="$(f1_orcamento "$G/ing-b.md")"; [ "$rc" -eq 0 ] && [ "$m" != ok ]; afirma "ga11-mutante-f1-presume-1" $? "morto: $m"

legado() { # legado <dir> <conteudo-da-auditoria|->
  mkdir -p "$1/docs/sprintx/features/velha/base" "$1/docs/sprintx/features/velha/sprint-01"
  printf 'i\n' > "$1/docs/sprintx/features/velha/base/00-INDICE.md"; printf 'd\n' > "$1/docs/sprintx/features/velha/00-DECISOES.md"
  printf 't\n' > "$1/docs/sprintx/features/velha/sprint-01/tasks.md"; printf 'o\n' > "$1/docs/sprintx/features/velha/ORQUESTRADOR.md"
  [ "$2" = - ] || printf '%s\n' "$2" > "$1/docs/sprintx/features/velha/00-AUDITORIA.md"
}
AUD_NAO_LEGADA='# Auditoria — velha

| severidade | arquivo | problema | correção sugerida |
|---|---|---|---|
| ALTA | sprint-02/tasks.md | revisor-testes `fraco`: passaria com item no grupo errado | Caso por grupo |
| BAIXA | sprint-02/tasks.md | contagem errada | Reescrever |

VEREDITO: NÃO — o plano não está pronto para execução autônoma.'
D="$G/r"; nova_feature "$D" velha; legado "$D" "$AUD_NAO_LEGADA"
s="$(pl "$D" fase velha)"; [ "$(kv "$s" fase)" = F3 ] && [ "$(kv "$s" fonte)" = legado ]; afirma "gr-legado-nao-retoma-f3" $? "fase $(kv "$s" fase), fonte legado"
pl "$D" avanca velha f5 >/dev/null; rc=$?
[ "$rc" -eq 5 ] && [ ! -f "$(fdir "$D" velha)/00-PLANEJAMENTO.md" ]
afirma "gr2-legado-nao-nunca-reaudita" $? "avanca f5 recusado (rc=$rc)"
printf 't v2\n' > "$(fdir "$D" velha)/sprint-01/tasks.md"; s="$(pl "$D" avanca velha f3)"; rc=$?
[ "$rc" -eq 0 ] && [ "$(kv "$s" estado)" = aguardando_f4 ] && [ "$(fmv "$(fdir "$D" velha)/00-PLANEJAMENTO.md" reprovacoes)" = 1 ]
afirma "gr3-legado-migra-na-transicao" $? "rodada legada preservada, aguardando_f4"
D="$G/r2"; nova_feature "$D" velha; legado "$D" -
[ "$(kv "$(pl "$D" fase velha)" fase)" = F5 ]; afirma "gr4-legado-sem-auditoria-tabela-antiga" $? "ORQUESTRADOR sem auditoria: F5"
D="$G/s"; nova_feature "$D" velha; legado "$D" '# Auditoria

Nenhum achado.

VEREDITO: SIM — o plano está pronto para execução autônoma.'
[ "$(kv "$(pl "$D" fase velha)" fase)" = F6 ]; afirma "gs-legado-sim-f6" $? "veredito SIM preservado"
D="$G/s2"; nova_feature "$D" velha; legado "$D" 'Historico: rodada 1 dizia
VEREDITO: SIM — o plano está pronto para execução autônoma.

| severidade | arquivo | problema | correção sugerida |
|---|---|---|---|
| ALTA | sprint-01/tasks.md | contradicao | corrigir |

VEREDITO: NÃO — o plano não está pronto para execução autônoma.'
[ "$(kv "$(pl "$D" fase velha)" fase)" = F3 ]; afirma "gs2-ultimo-veredito-decide" $? "SIM antigo nao lava o NAO final"
D="$G/s3"; nova_feature "$D" velha; legado "$D" '| severidade | arquivo | problema | correção sugerida |
|---|---|---|---|
| ALTA | sprint-01/tasks.md | teste fraco | corrigir |

VEREDITO: SIM — o plano está pronto para execução autônoma.'
pl "$D" criar velha 3 buildx >/dev/null; rc=$?
[ "$rc" -eq 4 ] && [ ! -f "$(fdir "$D" velha)/00-PLANEJAMENTO.md" ]; afirma "gs3-sim-com-alta-nao-e-lavado" $? "rc=$rc, nada gravado"

# Contrato: kind planejamento, dono sprintx, sem expxdev, nao e produto.
tem "$SCHEMA" '### `00-PLANEJAMENTO.md` → `kind: planejamento`' && tem "$SCHEMA" '**Kind exclusivo da `sprintx`**'
afirma "g-kind-planejamento-no-contrato" $? "00-schema.md"
tem "$SCHEMA" '`00-PLANEJAMENTO.md` não é task, não é produto, não é' ; afirma "g-planejamento-nao-e-produto" $? "artefato de metodo"
tem "$SCHEMA" 'O painel do `expxdev` pode ignorar este kind' && tem "$SCHEMA" 'nenhuma lógica da skill depende de o'
afirma "g-expxdev-pode-ignorar" $? "documentado"
grep -qi expxdev "$PL"; [ $? -ne 0 ]; afirma "g-script-nao-depende-de-expxdev" $? "nenhuma referencia"
[ ! -e "$G/b/.expx" ] && [ ! -e "$G/g/.expx" ] && ! command -v expxdev >/dev/null 2>&1
afirma "g-ciclo-completo-sem-expxdev" $? "F1..F5 e orcamento_esgotado sem .expx e sem expxdev"
# MergeX somente leitura: aceita 00-PLANEJAMENTO.md como artefato de metodo, sem mudanca nela.
MX="${MERGEX_DIR:-$H/../../../mergex}"
MXH="$MX/.claude/hooks/mergex/arquivo-fora-do-plano.sh"
if [ -f "$MXH" ] && command -v jq >/dev/null 2>&1; then
  D="$G/mx"; nova_feature "$D" menu; pl "$D" criar menu >/dev/null; F="$(fdir "$D" menu)"
  mkdir -p "$F/sprint-01" "$D/docs/entregas/menu"
  printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: tasks\ntrabalho_id: menu\ntasks:\n  - id: T-01.01\n    status: pendente\n    arquivos:\n      cria: [src/menu.ts]\n      altera: []\n---\n' > "$F/sprint-01/tasks.md"
  printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: entrega\ntrabalho_id: menu\nbranch: feature/menu\n---\n' > "$D/docs/entregas/menu/ENTREGA.md"
  mx_ev() { printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"git commit -m checkpoint"}}' "$D"; }
  git -C "$D" add "$F/00-PLANEJAMENTO.md"
  : > "$G/marco-mergex"; sleep 1
  s="$(mx_ev | (cd "$D" && bash "$MXH") 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] && case "$s" in *"nenhuma task declarou"*) false ;; *) true ;; esac
  afirma "g-mergex-aceita-planejamento" $? "arquivo-fora-do-plano isenta a pasta da feature (rc=$rc)"
  printf 'x\n' > "$D/src/intruso.ts"; git -C "$D" add src/intruso.ts
  s="$(mx_ev | (cd "$D" && bash "$MXH") 2>&1)"
  case "$s" in *"nenhuma task declarou"*) true ;; *) false ;; esac; afirma "g-mergex-controle-acusa-produto" $? "o hook esta ativo de verdade"
  [ -z "$(find "$MX" -newer "$G/marco-mergex" -not -path '*/.git/*' 2>/dev/null | head -1)" ]; afirma "g-mergex-intocada" $? "nenhum arquivo da mergex escrito pelo teste"
else
  pula_externo "g-mergex-aceita-planejamento" "mergex em \$MERGEX_DIR/../mergex, ou jq"
fi
rm -rf "$G"

echo "== H. contrato do planejamento nas fases (P0.1) =="
L_PRIM=$(linha_de "$SKILLMD" '| `replanejar` | F3 — **nunca** F5 direto')
L_ESG=$(linha_de "$SKILLMD" '| `orcamento_esgotado` | **terminal**')
[ -n "$L_PRIM" ] && [ -n "$L_ESG" ] && tem "$SKILLMD" 'Nunca infira F5 só porque `ORQUESTRADOR.md` existe.' \
  && tem "$SKILLMD" '| Última linha `VEREDITO:` de `00-AUDITORIA.md` é `VEREDITO: NÃO` | F3 |'
afirma "g-skill-deteccao-documentada" $? "tabela primaria e legado corrigido"
tem "$SK/references/02-descoberta.md" '## Checkpoint do planejamento — regra única'
NCHK=$(grep -rlF '## Checkpoint do planejamento — regra única' "$SK" | wc -l)
[ "$NCHK" -eq 1 ]; afirma "g-regra-checkpoint-unica" $? "$NCHK arquivo(s)"
for ref in 02-descoberta:f2 03-plano:f3 04-orquestrador:f4 05-auditoria:f5; do
  tem "$SK/references/${ref%%:*}.md" "scripts/planejamento.sh avanca <slug> ${ref##*:}"; afirma "g-fase-${ref##*:}-avanca" $? "${ref%%:*}.md"
done
tem "$SK/references/01-ingestao.md" 'scripts/planejamento.sh criar <slug>'; afirma "g-f1-cria" $? "01-ingestao.md"

# Guarda ESTRUTURAL: presenca nao basta (0d32214 achou blocos de estado no lugar errado com a
# bancada verde). Para cada instrucao de planejamento.sh: na fase dona, depois do trabalho da
# fase, antes do handoff, dentro do fluxo, exatamente uma vez. Ancoras literais, ordem de linhas.
# ordem <arquivo> <ancora>... — ancora com "=" na frente e a instrucao canonica (exatamente uma
# ocorrencia no arquivo); as demais valem pela primeira ocorrencia. Todas estritamente em ordem.
ordem() {
  local arq="$1" ant=0 ant_txt="(inicio)" a unica n l; shift
  for a in "$@"; do
    unica=0; case "$a" in =*) unica=1; a="${a#=}" ;; esac
    n=$(tr -d '\r' < "$arq" | grep -cF -- "$a")
    [ "$n" -ge 1 ] || { printf 'ausente: %s' "$a"; return 1; }
    [ "$unica" -eq 0 ] || [ "$n" -eq 1 ] || { printf 'duplicada (%sx): %s' "$n" "$a"; return 1; }
    l=$(tr -d '\r' < "$arq" | grep -nF -- "$a" | head -1 | cut -d: -f1)
    [ "$l" -gt "$ant" ] || { printf 'fora de ordem: "%s" (l.%s) antes de "%s" (l.%s)' "$a" "$l" "$ant_txt" "$ant"; return 1; }
    ant=$l; ant_txt=$a
  done
  printf 'ok'
}
CMD_PL='bash <raiz-da-skill>/scripts/planejamento.sh'
est_f1() { ordem "$1" '## Passo 1 — Scaffold' '00-BLOQUEIOS.md      apenas o título' "=$CMD_PL criar <slug>" \
  'O arquivo nasce com `estado: null`' '## Passo 1.1 —' '## Critério de saída da fase' '## Ao terminar' \
  'entre na F2 lendo `references/02-descoberta.md`'; }
est_f2() { ordem "$1" '## Passo 3 — Registrar as decisões' '## Critério de saída da fase' '## Ao terminar' \
  "=$CMD_PL avanca <slug> f2" 'siga para a F3 lendo `references/03-plano.md`' \
  '## Checkpoint do planejamento — regra única' '**Checkpoint pendente —' "=$CMD_PL checkpoint <slug>"; }
est_f3() { ordem "$1" '## Passo 3 — Verificação própria antes de encerrar' '## Critério de saída da fase' '## Ao terminar' \
  "=$CMD_PL avanca <slug> f3" 'Siga para a F4 lendo `references/04-orquestrador.md`' \
  'rode antes a F3.5 lendo `references/07-estimativa.md`'; }
est_f4() { ordem "$1" '## Passo único — Gerar ORQUESTRADOR.md' '## Critério de saída da fase' '## Ao terminar' \
  "=$CMD_PL avanca <slug> f4" 'Siga para a F5 lendo `references/05-auditoria.md`'; }
est_f5() { ordem "$1" '## Passo 1 — Delegar ao agente `auditor-plano`' '## Passo 1.1 — O teste fraco tipado' "=$CMD_PL revisor" \
  '## Passo 4 — Escrever o relatório' 'Regra do veredito: existe achado ALTA' '## Passo 5 — Registrar a rodada e fazer o checkpoint' \
  "=$CMD_PL avanca <slug> f5" '## Critério de saída da fase' '## Quando o veredito é NÃO e o estado é `replanejar`' \
  'volte para a F3 (`references/03-plano.md`)' '## Quando o estado é `orcamento_esgotado`' '## Ao terminar com VEREDITO: SIM' \
  'Siga para a F6 lendo `references/06-execucao.md`'; }
est_f6() { ordem "$1" '## Pré-requisitos verificáveis' '`scripts/planejamento.sh fase <slug>` responde `F6`' '## Passo 1 — Carregar o mapa' \
  '## Passo 2 — Executar task a task' '1. Marque `status: em_andamento`' "=$CMD_PL obrigacoes-f6 <slug>" \
  '2. **Escreva o teste de integração e o teste funcional ANTES' '## Critério de saída da fase'; }
REFS="1:01-ingestao 2:02-descoberta 3:03-plano 4:04-orquestrador 5:05-auditoria 6:06-execucao"
for par in $REFS; do
  m="$(est_f${par%%:*} 2>/dev/null "$SK/references/${par##*:}.md")"; [ "$m" = ok ]; afirma "gh-estrutura-${par##*:}" $? "$m"
done
# Uma instrucao canonica por transicao na skill inteira, e so no arquivo da fase dona.
for inst in "criar <slug>:01-ingestao" "avanca <slug> f2:02-descoberta" "avanca <slug> f3:03-plano" "avanca <slug> f4:04-orquestrador" \
  "avanca <slug> f5:05-auditoria" "checkpoint <slug>:02-descoberta" "obrigacoes-f6 <slug>:06-execucao"; do
  h_nome="gh-instrucao-unica-$(printf '%s' "${inst%%:*}" | tr -c 'a-z0-9' '_' | sed 's/_*$//')"
  onde="$(grep -rlF -- "$CMD_PL ${inst%%:*}" "$SK" "$H/../commands" "$H/../../.opencode" 2>/dev/null)"
  [ "$(printf '%s\n' "$onde" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 1 ] && [ "$(basename "$onde")" = "${inst##*:}.md" ]; h_rc=$?
  afirma "$h_nome" "$h_rc" "${onde:-nenhum arquivo}"
done
# Auto-teste da guarda: mutantes em copia temporaria, nunca nas referencias reais.
MU="$(mktemp -d)"
muta_move() { # muta_move <arq> <instrucao> <ancora|FIM> <antes|depois> — move o bloco ```bash da instrucao
  tr -d '\r' < "$1" | awk -v c="$2" -v a="$3" -v p="$4" '
    { l[NR] = $0 } !i && index($0, c) { i = NR }
    END {
      for (n = 1; n <= NR; n++) {
        if (n >= i - 1 && n <= i + 1) continue
        if (a != "FIM" && !feito && index(l[n], a)) {
          if (p == "depois") print l[n]
          print l[i-1]; print l[i]; print l[i+1]; feito = 1
          if (p == "antes") print l[n]
          continue
        }
        print l[n]
      }
      if (a == "FIM") { print ""; print l[i-1]; print l[i]; print l[i+1] }
    }'
}
muta_move "$SK/references/03-plano.md" "$CMD_PL avanca <slug> f3" FIM depois > "$MU/a.md"
tem "$MU/a.md" "$CMD_PL avanca <slug> f3" && ! est_f3 "$MU/a.md" >/dev/null
afirma "gh-mutante-a-f3-depois-do-encerramento" $? "$(est_f3 "$MU/a.md")"
muta_move "$SK/references/05-auditoria.md" "$CMD_PL avanca <slug> f5" '## Ao terminar com VEREDITO: SIM' depois > "$MU/b.md"
tem "$MU/b.md" "$CMD_PL avanca <slug> f5" && ! est_f5 "$MU/b.md" >/dev/null
afirma "gh-mutante-b-f5-depois-do-sim" $? "$(est_f5 "$MU/b.md")"
muta_move "$SK/references/04-orquestrador.md" "$CMD_PL avanca <slug> f4" '## Passo único — Gerar ORQUESTRADOR.md' antes > "$MU/c.md"
tem "$MU/c.md" "$CMD_PL avanca <slug> f4" && ! est_f4 "$MU/c.md" >/dev/null
afirma "gh-mutante-c-f4-antes-do-orquestrador" $? "$(est_f4 "$MU/c.md")"
tr -d '\r' < "$SK/references/02-descoberta.md" | awk -v c="$CMD_PL avanca <slug> f2" '{ print } index($0, c) { print }' > "$MU/d.md"
[ "$(conta "$MU/d.md" "$CMD_PL avanca <slug> f2")" -eq 2 ] && ! est_f2 "$MU/d.md" >/dev/null
afirma "gh-mutante-d-instrucao-duplicada" $? "$(est_f2 "$MU/d.md")"
tr -d '\r' < "$SK/references/02-descoberta.md" | awk -v c="$CMD_PL checkpoint <slug>" '{ print } index($0, c) { print }' > "$MU/d2.md"
! est_f2 "$MU/d2.md" >/dev/null; afirma "gh-mutante-d2-checkpoint-duplicado" $? "$(est_f2 "$MU/d2.md")"
tr -d '\r' < "$SK/references/06-execucao.md" | grep -vF "$CMD_PL obrigacoes-f6 <slug>" > "$MU/e.md"
! est_f6 "$MU/e.md" >/dev/null; afirma "gh-mutante-e-instrucao-removida" $? "$(est_f6 "$MU/e.md")"
muta_move "$SK/references/02-descoberta.md" "$CMD_PL avanca <slug> f2" 'siga para a F3 lendo `references/03-plano.md`' depois > "$MU/f.md"
! est_f2 "$MU/f.md" >/dev/null; afirma "gh-mutante-f-f2-depois-do-handoff" $? "$(est_f2 "$MU/f.md")"
rm -rf "$MU"


echo "== I. teste fraco tipado e severidade deterministica (P0.1) =="
G="$(mktemp -d)"
# T/U/V/W. Taxonomia do fraco e severidade deterministica.
[ "$(bash "$PL" severidade ausente)" = ALTA ]; afirma "gt-ausente-alta" $? "ausente -> ALTA"
[ "$(bash "$PL" severidade criterio)" = ALTA ]; afirma "gu-criterio-alta" $? "criterio -> ALTA"
[ "$(bash "$PL" severidade teste)" = "MÉDIA" ]; afirma "gv-teste-media" $? "teste -> MÉDIA"
REV="$(printf '%s\n' 'T-01.01 | solido' \
  'T-02.01 | fraco | teste | D-13 | contadores trocados entre itens' \
  'T-02.02 | fraco | teste | - | item no grupo errado' \
  'T-02.03 | fraco | teste | a regra do menu | item no grupo errado' \
  'T-02.04 | fraco | criterio | - | Configuracoes lendo manage_users' \
  'T-02.05 | fraco | ausente | - | qualquer implementacao passa' \
  'T-02.06 | fraco | teste | criterio_aceite | aria-current fixo' \
  'T-02.07 | fraco | teste | base/menu.md | grid-cols-5 fixo' \
  'T-02.08 | fraco | teste | origem:contrato-api#L10 | campo omitido' | bash "$PL" revisor)"; rc=$?
linha_rev() { printf '%s\n' "$REV" | awk -F'\t' -v t="$1" '$1 == t { print $3 "|" $4 }'; }
[ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$REV" | awk -F'\t' '$1=="T-01.01"{print $2}')" = solido ]; afirma "gt2-revisor-solido" $? "solido sem motivo"
[ "$(linha_rev T-02.01)" = "teste|MÉDIA" ] && [ "$(linha_rev T-02.06)" = "teste|MÉDIA" ] && [ "$(linha_rev T-02.07)" = "teste|MÉDIA" ] \
  && [ "$(linha_rev T-02.08)" = "teste|MÉDIA" ]
afirma "gv2-teste-com-clausula-media" $? "D-NN, criterio_aceite, base/, origem: -> MÉDIA"
[ "$(linha_rev T-02.02)" = "criterio|ALTA" ] && [ "$(linha_rev T-02.03)" = "criterio|ALTA" ]
afirma "gw-sem-clausula-vira-criterio-alta" $? "'-' e texto livre -> criterio ALTA"
[ "$(linha_rev T-02.04)" = "criterio|ALTA" ] && [ "$(linha_rev T-02.05)" = "ausente|ALTA" ]; afirma "gtu-revisor-alta" $? "criterio e ausente -> ALTA"
printf '%s\n' "$REV" | awk -F'\t' '$1=="T-02.01"{print $7}' | grep -qxF '[item 2][fraco:teste] T-02.01 — cláusula: D-13 — passaria com: contadores trocados entre itens'
afirma "gw2-revisor-gera-linha-da-auditoria" $? "prefixo [item 2][fraco:teste]"
for ruim in 'T-01.01 | fraco' 'T-01.01 | fraco | teste | D-13' 'T-01.01 | fraco | fragil | - | x' 'T-01.01 | solido | motivo' 'T1 | solido' 'T-01.01 | fraco | teste | D-13 | -'; do
  i_nome="gw3-revisor-recusa-$(printf '%s' "$ruim" | tr -c 'a-z0-9' '_' | cut -c1-28)"
  printf '%s\n' "$ruim" | bash "$PL" revisor >/dev/null 2>&1; [ $? -eq 4 ]; i_rc=$?
  afirma "$i_nome" "$i_rc" "linha fora da forma"
done
# A auditoria so e registrada com severidade deterministica.
D="$G/sev"; nova_feature "$D" menu; ate_f5 "$D" menu; F="$(fdir "$D" menu)"
aud_linha() { printf '| severidade | arquivo | problema | correção sugerida |\n|---|---|---|---|\n%s\n\nVEREDITO: %s\n' "$1" "$2" > "$F/00-AUDITORIA.md"; }
sev_caso() { # sev_caso <nome> <esperado_rc> <linha> <veredito>
  aud_linha "$3" "$4"; local ck; ck="$(cksum < "$F/00-PLANEJAMENTO.md")"
  pl "$D" valida-auditoria menu >/dev/null; local rc=$?
  [ "$rc" -eq "$2" ] && [ "$(cksum < "$F/00-PLANEJAMENTO.md")" = "$ck" ]; afirma "$1" $? "rc=$rc (esperado $2)"
}
sev_caso gv3-teste-como-alta-recusado 4 '| ALTA | s/tasks.md | [item 2][fraco:teste] T-01.01 — cláusula: D-13 — passaria com: x | y |' 'NÃO — x'
sev_caso gv4-teste-como-baixa-recusado 4 '| BAIXA | s/tasks.md | [item 2][fraco:teste] T-01.01 — cláusula: D-13 — passaria com: x | y |' 'SIM — x'
sev_caso gt3-ausente-como-media-recusado 4 '| MÉDIA | s/tasks.md | [item 2][fraco:ausente] T-01.01 — cláusula: - — passaria com: x | y |' 'SIM — x'
sev_caso gu3-criterio-como-media-recusado 4 '| MÉDIA | s/tasks.md | [item 2][fraco:criterio] T-01.01 — cláusula: - — passaria com: x | y |' 'SIM — x'
sev_caso gw4-teste-sem-clausula-recusado 4 '| MÉDIA | s/tasks.md | [item 2][fraco:teste] T-01.01 — cláusula: - — passaria com: x | y |' 'SIM — x'
sev_caso g-achado-sem-item-recusado 4 '| BAIXA | s/tasks.md | contagem errada | y |' 'SIM — x'
sev_caso g-item2-sem-tipo-recusado 4 '| ALTA | s/tasks.md | [item 2] T-01.01 teste fraco | y |' 'NÃO — x'
sev_caso g-sim-com-alta-recusado 4 '| ALTA | s/tasks.md | [item 1] T-01.01 sem teste | y |' 'SIM — x'
sev_caso g-nao-sem-alta-recusado 4 '| BAIXA | s/tasks.md | [item 3] T-01.01 adjetivo | y |' 'NÃO — x'
sev_caso gv5-teste-com-clausula-media-aceito 0 '| MÉDIA | s/tasks.md | [item 2][fraco:teste] T-01.01 — cláusula: D-13 — passaria com: x | y |' 'SIM — x'
aud_linha '| MÉDIA | s/tasks.md | [item 2][fraco:teste] T-01.01 — cláusula: D-13 — passaria com: x | y |' 'MAIS OU MENOS'
pl "$D" avanca menu f5 >/dev/null; rc=$?
[ "$rc" -eq 4 ] && [ "$(fmv "$F/00-PLANEJAMENTO.md" estado)" = aguardando_f5 ]; afirma "g-auditoria-invalida-nao-registra-rodada" $? "rc=$rc, estado aguardando_f5"
AUDF="$SK/references/05-auditoria.md"
[ -z "$(grep -rlF 'a severidade é sua' "$SK" "$H/../agents" "$H/../../.opencode/agent" | grep -vF 'DECISOES-DA-SKILL.md')" ]; afirma "g-frase-severidade-e-sua-removida" $? "nenhuma sessao escolhe"
tem "$AUDF" '| `fraco:teste` | **MÉDIA** |' && tem "$AUDF" '| `fraco:ausente` | **ALTA** |' && tem "$AUDF" '| `fraco:criterio` | **ALTA** |'
afirma "g-f5-tabela-deterministica" $? "05-auditoria.md"
for ag in "$H/../agents/auditor-plano.md" "$H/../agents/revisor-testes.md"; do
  i_nome="g-agente-tabela-$(basename "$ag" .md)"
  grep -qE '`?(\[item 2\]\[fraco:)?teste\]?`? \| MÉDIA' "$ag" && grep -qE '`?(\[item 2\]\[fraco:)?ausente\]?`? \| ALTA' "$ag" \
    && grep -qE '`?(\[item 2\]\[fraco:)?criterio\]?`? \| ALTA' "$ag"; i_rc=$?
  afirma "$i_nome" "$i_rc" "mesma severidade no agente"
done
tem "$SK/references/03-plano.md" 'Corrija a **classe** do defeito' && tem "$SK/references/03-plano.md" '**Não invente generalização além da cláusula.**' \
  && tem "$SK/references/03-plano.md" 'tabela/matriz'
afirma "g-f3-replaneja-por-classe" $? "classe, matriz, sem generalizar"

# X/Y. F6: fraco:teste endurecido ANTES de tocar produto; nao discriminou -> bloqueio.
D="$G/x"; nova_feature "$D" menu; ate_f5 "$D" menu; auditoria "$D" menu 1 SIM; pl "$D" avanca menu f5 >/dev/null
OB="$(pl "$D" obrigacoes-f6 menu)"
[ "$(printf '%s\n' "$OB" | wc -l | tr -d ' ')" -eq 1 ] && [ "$(printf '%s\n' "$OB" | cut -f1)" = T-03.01 ] \
  && [ "$(printf '%s\n' "$OB" | cut -f2)" = D-13 ] && [ "$(printf '%s\n' "$OB" | cut -f3)" = 'contadores trocados entre itens' ]
afirma "gx-obrigacoes-f6-extraidas" $? "task, clausula e implementacao errada"
L_OBR=$(linha_de "$EXEC" '**Passo 2.0 — obrigação de `fraco:teste`, antes de qualquer código de produto.**')
L_ESCR=$(linha_de "$EXEC" '2. **Escreva o teste de integração e o teste funcional ANTES')
L_IMPL=$(linha_de "$EXEC" '3. Implemente até os dois testes passarem')
L_VERM=$(linha_de "$EXEC" 'vermelho pelo motivo esperado')
L_SOENT=$(linha_de "$EXEC" '5. **somente então** implemente')
L_BLOQ=$(linha_de "$EXEC" '**Se não conseguir tornar o teste discriminante, registre bloqueio da task**')
[ -n "$L_OBR" ] && [ -n "$L_VERM" ] && [ -n "$L_SOENT" ] && [ "$L_OBR" -lt "$L_VERM" ] && [ "$L_VERM" -lt "$L_SOENT" ] \
  && [ "$L_SOENT" -lt "$L_ESCR" ] && [ "$L_ESCR" -lt "$L_IMPL" ]
afirma "gx2-f6-endurece-antes-de-implementar" $? "obrigacao=$L_OBR < vermelho=$L_VERM < so-entao=$L_SOENT < impl=$L_IMPL"
tem "$EXEC" 'demonstre que o teste **discrimina explicitamente** a implementação errada registrada'; afirma "gx3-f6-discrimina-impl-registrada" $? "prova explicita"
[ -n "$L_BLOQ" ] && [ "$L_BLOQ" -lt "$L_IMPL" ] && tem "$EXEC" 'e **não implemente**'
afirma "gy-nao-discriminou-bloqueia-antes" $? "bloqueio=$L_BLOQ < impl=$L_IMPL, sem implementar"
tem "$EXEC" '**A task não conclui se alguma delas continuar passando.**'; afirma "gy2-revisor-f6-confere-registradas" $? "revisor-testes na F6"
tem "$H/../agents/revisor-testes.md" 'confira, lendo o teste de verdade, que **cada uma delas é discriminada**'; afirma "gy3-agente-f6-confere" $? "revisor-testes.md"

# Z. Espelho Claude/OpenCode: mesmo corpo em todos os agentes.
corpo_agente() { tr -d '\r' < "$1" | awk 'f && (n || $0 != "") { n = 1; print } /^---$/ { c++; if (c == 2) f = 1 }'; }
for ag in auditor-plano revisor-testes investigador; do
  [ "$(corpo_agente "$H/../agents/$ag.md")" = "$(corpo_agente "$H/../../.opencode/agent/$ag.md")" ]
  afirma "gz-espelho-$ag" $? "corpo identico nos dois harnesses"
done
EXREV="$(tr -d '\r' < "$H/../agents/revisor-testes.md" | sed -n '/^T-01.02 | solido$/,/^```$/p' | grep '^T-')"
printf '%s\n' "$EXREV" | bash "$PL" revisor >/dev/null 2>&1; afirma "gz2-exemplos-do-agente-validos" $? "$(printf '%s\n' "$EXREV" | wc -l | tr -d ' ') linha(s) aceitas pelo script"

rm -rf "$G"

. "$H/testes/bancada-bloqueio-replanejamento.sh"
. "$H/testes/bancada-escopo-e-hooks.sh"
echo "== U. o rastro da skill tem escritor oficial: identidade derivada, nunca montada pelo agente (P0.2 / D-01) =="
# O piloto real C7-C seguiu 08-rastro.md: `printf >> docs/eventos/...` sem `sessao`, primeiro Edit
# barrado com sessao_ambigua, o agente abriu o hook e forjou `claude-code@<id>`. O contrato agora
# e: task_iniciada/task_concluida/task_bloqueada so saem de scripts/rastro.sh, que deriva a
# identidade pela mesma funcao com que o escopo-da-task a le, e falha fechado sem ela (DS-159).
#
# Cada caso recebe uma ARVORE no layout instalado (<arv>/.claude/hooks + <arv>/.claude/skills/
# sprintx) e monta a fixture do zero: e assim que o controle e os mutantes sao julgados.
U_DIR="$(mktemp -d)"
U_N=0
U_RC=0; U_OUT=""
U_REAL="$(cd "$H/../.." && pwd)"
# As formas do caminho que o runner manda: POSIX sempre; no Windows tambem C:\, c:\ e C:/.
U_MF="posix"; [ "$T_WIN" = 1 ] && U_MF="posix win minuscula caixa-do-drive"

u_arvore() { # u_arvore <nome> — copia do layout instalado: hooks comum/ sprintx/ testes/ + a skill
  local r="$U_DIR/arv/$1"
  rm -rf "$r"; mkdir -p "$r/.claude/hooks/testes" "$r/.claude/skills"
  cp -R "$H/comum" "$H/sprintx" "$r/.claude/hooks/"
  cp "$H/testes/transcrito-agente.sh" "$r/.claude/hooks/testes/"
  cp -R "$SK" "$r/.claude/skills/sprintx"
  printf '%s' "$r"
}
u_plano() { # u_plano <dir> <slug> <status T-01.01> <arquivo T-01.01> <status T-01.02> <arquivo T-01.02>
  n_plano "$1/docs/sprintx/features/$2/sprint-01/tasks.md" "$2" 01 <<EOF
$(n_task T-01.01 "$3" "$4")
$(n_task T-01.02 "$5" "$6")
EOF
}
u_fx() { # u_fx — repo git novo com dois trabalhos que repetem os ids: fx (a.ts | b.ts) e fy (c.ts | d.ts)
  U_N=$((U_N + 1)); U_FX="$U_DIR/fx$U_N"
  mkdir -p "$U_FX/src"; git init -q --template= "$U_FX" >/dev/null 2>&1
  u_plano "$U_FX" fx em_andamento src/a.ts pendente src/b.ts
  u_plano "$U_FX" fy pendente src/c.ts pendente src/d.ts
}
# u_w <arv> <dir> <sessao|-> <args...> — o escritor, com a identidade que o Claude Code exporta
# (CLAUDECODE + CLAUDE_CODE_SESSION_ID) ou, com `-`, sem identidade nenhuma.
u_w() {
  local a="$1" d="$2" s="$3"; shift 3
  if [ "$s" = - ]; then
    U_OUT="$(cd "$d" && env -u EXPX_SESSAO -u EXPX_HARNESS -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE \
      bash "$a/.claude/skills/sprintx/scripts/rastro.sh" "$@" 2>&1)"; U_RC=$?
  else
    U_OUT="$(cd "$d" && env -u EXPX_SESSAO -u EXPX_HARNESS CLAUDECODE=1 CLAUDE_CODE_SESSION_ID="$s" \
      bash "$a/.claude/skills/sprintx/scripts/rastro.sh" "$@" 2>&1)"; U_RC=$?
  fi
}
u_wenv() { # u_wenv <arv> <dir> <env...> -- <args...> — o escritor com um ambiente dado
  local a="$1" d="$2" e=(); shift 2
  while [ $# -gt 0 ] && [ "$1" != -- ]; do e+=("$1"); shift; done; shift
  U_OUT="$(cd "$d" && env -u EXPX_SESSAO -u EXPX_HARNESS -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE "${e[@]}" \
    bash "$a/.claude/skills/sprintx/scripts/rastro.sh" "$@" 2>&1)"; U_RC=$?
}
# u_h <arv> <dir> <sessao> <arquivo-relativo> [cwd-payload] [file_path-payload] — o escopo-da-task
# da arvore, com o payload do runner (cwd/file_path podem vir na forma Windows).
u_h() {
  local a="$1" d="$2" s="$3" rel="$4" c="${5:-$2}" f="${6:-$2/$4}"
  U_OUT="$(printf '{"cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$(t_esc "$c")" "$(t_esc "$f")" \
    | (cd "$d" && env -u EXPX_SESSAO -u EXPX_HARNESS CLAUDECODE=1 CLAUDE_CODE_SESSION_ID="$s" \
        bash "$a/.claude/hooks/sprintx/escopo-da-task.sh") 2>&1)"; U_RC=$?
}
u_ok() { [ "$U_RC" -eq 0 ] && [ -z "$U_OUT" ]; }           # permitido, em silencio
u_barra() { [ "$U_RC" -eq 2 ] && printf '%s' "$U_OUT" | grep -qF "$1"; }
u_linha() { # u_linha <arquivo> <evento> <task> — a linha do evento (a ultima), vazia se nao ha
  [ -f "$1" ] || return 0
  grep -F "\"evento\":\"$2\"" "$1" | grep -F "\"task\":\"$3\"" | tail -1
}
# O primeiro `"sessao":"..."` da linha e o que a leitura do rastro usa (_RASTRO_AWK_REIV).
u_campo() { printf '%s' "$1" | grep -o "\"$2\":\"[^\"]*\"" | head -1 | sed "s/^\"$2\":\"//; s/\"\$//"; }

# ---------------------------------------------------------------- os casos
u_a() { # A: escritor -> task_iniciada -> o escopo reconhece a task corrente
  local a="$1" l; u_fx
  u_w "$a" "$U_FX" s1 task-iniciada fx T-01.01; [ "$U_RC" -eq 0 ] || return 1
  l="$(u_linha "$U_FX/docs/eventos/fx.jsonl" task_iniciada T-01.01)"
  [ "$(u_campo "$l" sessao)" = claude-code@s1 ] && [ "$(u_campo "$l" harness)" = claude-code ] || return 1
  printf '%s' "$l" | grep -qF '"origem":"skill"' || return 1
  u_h "$a" "$U_FX" s1 src/a.ts; u_ok
}
u_b() { # B: escritor -> task_iniciada -> arquivo so da irma continua barrado
  local a="$1"; u_fx
  u_w "$a" "$U_FX" s1 task-iniciada fx T-01.01; [ "$U_RC" -eq 0 ] || return 1
  u_h "$a" "$U_FX" s1 src/b.ts; u_barra arquivo_de_task_irma
}
u_c() { # C: identidade indisponivel -> o escritor falha e nao grava nada, nem incompleto
  local a="$1" e; u_fx
  u_w "$a" "$U_FX" - task-iniciada fx T-01.01; [ "$U_RC" -eq 3 ] || return 1
  u_w "$a" "$U_FX" - task-concluida fx T-01.01; [ "$U_RC" -eq 3 ] || return 1
  u_w "$a" "$U_FX" - task-bloqueada fx T-01.01; [ "$U_RC" -eq 3 ] || return 1
  # So o id, sem o harness conhecido: o <harness>@ nao seria o mesmo no hook.
  u_wenv "$a" "$U_FX" CLAUDE_CODE_SESSION_ID=s1 -- task-iniciada fx T-01.01; [ "$U_RC" -eq 3 ] || return 1
  # So o harness, sem o id: o fallback <harness>@<ppid> e o processo de quem chama, nao a sessao.
  u_wenv "$a" "$U_FX" CLAUDECODE=1 -- task-iniciada fx T-01.01; [ "$U_RC" -eq 3 ] || return 1
  u_wenv "$a" "$U_FX" EXPX_HARNESS=opencode EXPX_SESSAO=opencode@sem-id -- task-iniciada fx T-01.01; [ "$U_RC" -eq 3 ] || return 1
  u_wenv "$a" "$U_FX" CLAUDECODE=1 'CLAUDE_CODE_SESSION_ID=s1","x' -- task-iniciada fx T-01.01; [ "$U_RC" -eq 3 ] || return 1
  for e in "$U_FX"/docs/eventos/*.jsonl; do
    [ -f "$e" ] || continue
    grep -qE '"evento":"task_(iniciada|concluida|bloqueada)"' "$e" && return 1
  done
  u_h "$a" "$U_FX" s1 src/a.ts; u_barra sessao_ambigua
}
u_d() { # D: caminhos Windows no payload e o escritor chamado de um subdiretorio
  local a="$1" f w; u_fx
  U_OUT="$(cd "$U_FX/src" && env -u EXPX_SESSAO -u EXPX_HARNESS CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=s1 \
    bash "$a/.claude/skills/sprintx/scripts/rastro.sh" task-iniciada fx T-01.01 2>&1)" || return 1
  [ -n "$(u_linha "$U_FX/docs/eventos/fx.jsonl" task_iniciada T-01.01)" ] || return 1
  [ ! -e "$U_FX/src/docs" ] || return 1
  for f in $U_MF; do
    case "$f" in
      posix) w="$U_FX" ;;
      win) w="$(cygpath -w "$U_FX")" ;;
      minuscula) w="$(cygpath -w "$U_FX")"; w="$(printf '%s' "${w:0:1}" | tr 'A-Z' 'a-z')${w:1}" ;;
      caixa-do-drive) w="$(cygpath -m "$U_FX")" ;;
    esac
    if [ "$f" = posix ] || [ "$f" = caixa-do-drive ]; then
      u_h "$a" "$U_FX" s1 src/a.ts "$w" "$w/src/a.ts"; u_ok || return 1
      u_h "$a" "$U_FX" s1 src/b.ts "$w" "$w/src/b.ts"; u_barra arquivo_de_task_irma || return 1
    else
      u_h "$a" "$U_FX" s1 src/a.ts "$w" "$w\\src\\a.ts"; u_ok || return 1
      u_h "$a" "$U_FX" s1 src/b.ts "$w" "$w\\src\\b.ts"; u_barra arquivo_de_task_irma || return 1
    fi
  done
}
u_e() { # E: sessoes diferentes — uma nunca reivindica pela outra
  local a="$1"; u_fx
  u_plano "$U_FX" fx em_andamento src/a.ts em_andamento src/b.ts
  u_w "$a" "$U_FX" s1 task-iniciada fx T-01.01; [ "$U_RC" -eq 0 ] || return 1
  u_w "$a" "$U_FX" s2 task-iniciada fx T-01.02; [ "$U_RC" -eq 0 ] || return 1
  u_h "$a" "$U_FX" s1 src/a.ts; u_ok || return 1
  u_h "$a" "$U_FX" s2 src/b.ts; u_ok || return 1
  u_h "$a" "$U_FX" s2 src/a.ts; u_barra arquivo_de_task_irma || return 1
  u_h "$a" "$U_FX" s3 src/a.ts; u_barra sessao_ambigua
}
u_f() { # F: worktrees diferentes — rastro e reivindicacao nao atravessam a arvore
  local a="$1" r wt; U_N=$((U_N + 1)); r="$U_DIR/wt$U_N"; wt="$r--fx"
  mkdir -p "$r/src"; git init -q --template= -b main "$r" >/dev/null 2>&1
  u_plano "$r" fx em_andamento src/a.ts pendente src/b.ts
  git -C "$r" add -A >/dev/null 2>&1
  git -C "$r" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -m p >/dev/null 2>&1 || return 1
  git -C "$r" worktree add -q -b feature/fx "$wt" main >/dev/null 2>&1 || return 1
  u_w "$a" "$wt" s1 task-iniciada fx T-01.01; [ "$U_RC" -eq 0 ] || return 1
  [ -n "$(u_linha "$wt/docs/eventos/fx.jsonl" task_iniciada T-01.01)" ] || return 1
  [ ! -e "$r/docs/eventos" ] || return 1
  u_h "$a" "$wt" s1 src/a.ts; u_ok || return 1
  u_h "$a" "$r" s1 src/a.ts; u_barra sessao_ambigua || return 1
  git -C "$r" worktree remove --force "$wt" >/dev/null 2>&1; return 0
}
u_g() { # G: evento legado sem identidade continua sem reivindicar nada (DS-150)
  local a="$1"; u_fx; mkdir -p "$U_FX/docs/eventos"
  printf '%s\n' '{"ts":"2026-09-26T10:23:54Z","expx_eventos":1,"trabalho_id":"fx","ferramenta":"sprintx","origem":"skill","evento":"task_iniciada","fase":"f6","task":"T-01.01","agente":"principal","resultado":"ok","detalhe":"legado","arquivos":[]}' \
    >> "$U_FX/docs/eventos/fx.jsonl"
  u_h "$a" "$U_FX" s1 src/a.ts; u_barra sessao_ambigua || return 1
  u_w "$a" "$U_FX" s1 task-iniciada fx T-01.01; [ "$U_RC" -eq 0 ] || return 1
  u_h "$a" "$U_FX" s1 src/a.ts; u_ok
}
u_hc() { # H: task_concluida e task_bloqueada pelo escritor fecham a reivindicacao, com identidade
  local a="$1" l; u_fx
  u_w "$a" "$U_FX" s1 task-iniciada fx T-01.01; [ "$U_RC" -eq 0 ] || return 1
  u_w "$a" "$U_FX" s1 task-concluida fx T-01.01 "suite parcial verde" src/a.ts; [ "$U_RC" -eq 0 ] || return 1
  l="$(u_linha "$U_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)"
  [ "$(u_campo "$l" sessao)" = claude-code@s1 ] || return 1
  printf '%s' "$l" | grep -qF '"arquivos":["src/a.ts"]' || return 1
  u_h "$a" "$U_FX" s1 src/a.ts; u_barra sessao_ambigua || return 1
  u_w "$a" "$U_FX" s1 task-iniciada fx T-01.01; [ "$U_RC" -eq 0 ] || return 1
  u_w "$a" "$U_FX" s1 task-bloqueada fx T-01.01 B-01; [ "$U_RC" -eq 0 ] || return 1
  l="$(u_linha "$U_FX/docs/eventos/fx.jsonl" task_bloqueada T-01.01)"
  [ "$(u_campo "$l" sessao)" = claude-code@s1 ] && printf '%s' "$l" | grep -qF '"resultado":"bloqueado"' || return 1
  u_h "$a" "$U_FX" s1 src/a.ts; u_barra sessao_ambigua
}
u_i() { # I: contexto que nao fecha nao grava no trabalho pedido
  local a="$1"; u_fx
  u_w "$a" "$U_FX" s1 task-iniciada fx T-01.01; [ "$U_RC" -eq 0 ] || return 1
  u_w "$a" "$U_FX" s1 task-iniciada fy T-01.01; [ "$U_RC" -eq 4 ] || return 1
  [ ! -e "$U_FX/docs/eventos/fy.jsonl" ] || return 1
  grep -qF contexto_de_trabalho_divergente "$U_FX/docs/eventos/sem-trabalho.jsonl" || return 1
  u_w "$a" "$U_FX" s1 task-iniciada nao-existe T-01.01; [ "$U_RC" -eq 4 ] || return 1
  u_w "$a" "$U_FX" s1 task-iniciada fx T-09.09; [ "$U_RC" -eq 4 ] || return 1
  [ ! -e "$U_FX/docs/eventos/nao-existe.jsonl" ] && [ "$(grep -c 'T-09.09' "$U_FX/docs/eventos/fx.jsonl")" -eq 0 ]
}
u_j() { # J: sessao e harness nunca vem de quem chama
  local a="$1" l; u_fx
  u_w "$a" "$U_FX" s1 task-iniciada fx T-01.01 d --sessao claude-code@forjada; [ "$U_RC" -eq 64 ] || return 1
  u_w "$a" "$U_FX" s1 task-iniciada fx T-01.01 d --harness forjado; [ "$U_RC" -eq 64 ] || return 1
  [ ! -e "$U_FX/docs/eventos/fx.jsonl" ] || return 1
  u_w "$a" "$U_FX" s1 task-iniciada fx T-01.01 'x","sessao":"claude-code@forjada","harness":"forjado'; [ "$U_RC" -eq 0 ] || return 1
  l="$(u_linha "$U_FX/docs/eventos/fx.jsonl" task_iniciada T-01.01)"
  [ "$(u_campo "$l" sessao)" = claude-code@s1 ] && [ "$(u_campo "$l" harness)" = claude-code ] || return 1
  u_h "$a" "$U_FX" forjada src/a.ts; u_barra sessao_ambigua || return 1
  u_h "$a" "$U_FX" s1 src/a.ts; u_ok
}
u_k() { # K: o evento vai para o rastro do trabalho DADO, mesmo com a task homonima em outro
  local a="$1"; u_fx
  u_plano "$U_FX" fy em_andamento src/c.ts pendente src/d.ts
  u_w "$a" "$U_FX" s1 task-iniciada fy T-01.01; [ "$U_RC" -eq 0 ] || return 1
  [ -n "$(u_linha "$U_FX/docs/eventos/fy.jsonl" task_iniciada T-01.01)" ] || return 1
  [ ! -e "$U_FX/docs/eventos/fx.jsonl" ] || return 1
  [ ! -e "$U_FX/docs/eventos/sem-trabalho.jsonl" ] || return 1
  u_h "$a" "$U_FX" s1 src/c.ts; u_ok
}
u_l() { # L: eventos informativos pelo mesmo escritor — identidade quando ha, null quando nao
  local a="$1" l; u_fx
  u_w "$a" "$U_FX" - fase-iniciada fx f6; [ "$U_RC" -eq 0 ] || return 1
  l="$(grep -F '"evento":"fase_iniciada"' "$U_FX/docs/eventos/fx.jsonl")"
  printf '%s' "$l" | grep -qF '"fase":"f6","task":null' && printf '%s' "$l" | grep -qF '"sessao":null,"harness":null' || return 1
  u_w "$a" "$U_FX" s1 veredito-emitido fx SIM "sem ALTA"; [ "$U_RC" -eq 0 ] || return 1
  l="$(grep -F '"evento":"veredito_emitido"' "$U_FX/docs/eventos/fx.jsonl")"
  printf '%s' "$l" | grep -qF '"agente":"auditor-plano"' && printf '%s' "$l" | grep -qF 'VEREDITO: SIM' || return 1
  [ "$(u_campo "$l" sessao)" = claude-code@s1 ] || return 1
  u_w "$a" "$U_FX" s1 fase-iniciada fx f9; [ "$U_RC" -eq 64 ]
}
# Guarda estrutural (R8): a referencia instalada nunca volta a ensinar a linha a mao para os tres
# eventos que o enforcement le, e o escritor e o caminho de cada passo que os grava. So o
# contrato conhecido — nao e uma regex universal para documentacao futura.
u_doc() {
  local a="$1" sk="$1/.claude/skills/sprintx" f r
  r="$sk/references"
  for f in "$sk/SKILL.md" "$r"/*.md "$sk"/assets/*.md; do
    [ -f "$f" ] || continue
    # linha a mao (printf/echo/tee/>>) com evento de reivindicacao, ou template JSON dele
    grep -nE '(printf|echo|tee|>>).*task_(iniciada|concluida|bloqueada)|task_(iniciada|concluida|bloqueada).*(>>|\| *tee)' "$f" && return 1
    grep -nE '"evento" *: *"task_(iniciada|concluida|bloqueada)"' "$f" && return 1
    # o escritor nunca recebe identidade por argumento
    grep -nE 'scripts/rastro\.sh.*(sessao|harness|--)' "$f" && return 1
  done
  # 08-rastro: nenhum exemplo de append a mao em docs/eventos
  grep -nE '(printf|echo).*>> *docs/eventos|>> *docs/eventos' "$r/08-rastro.md" && return 1
  grep -qF 'scripts/rastro.sh task-iniciada' "$r/08-rastro.md" || return 1
  grep -qF 'scripts/rastro.sh task-concluida' "$r/08-rastro.md" || return 1
  grep -qF 'scripts/rastro.sh task-bloqueada' "$r/08-rastro.md" || return 1
  # 06-execucao: cada passo que grava um dos tres chama o escritor na mesma linha/bloco
  awk '/^1\. Marque `status: em_andamento`/,/^   \*\*Passo 2\.0/' "$r/06-execucao.md" | grep -qF 'scripts/rastro.sh task-iniciada' || return 1
  grep -E '^5\. Só então marque `status: concluida`' "$r/06-execucao.md" | grep -qF 'scripts/rastro.sh task-concluida' || return 1
  grep -E '^2\. Marque a task como `status: bloqueada`' "$r/06-execucao.md" | grep -qF 'scripts/rastro.sh task-bloqueada' || return 1
  grep -E 'Grave no rastro o `veredito_emitido`' "$r/05-auditoria.md" | grep -qF 'scripts/rastro.sh veredito-emitido' || return 1
  grep -qF 'scripts/rastro.sh task-iniciada|task-concluida|task-bloqueada' "$sk/SKILL.md" || return 1
  [ -f "$sk/scripts/rastro.sh" ]
}
# O verificador de transcrito (o que reprova o agente real) julga transcritos sinteticos.
u_tr_ev() { # u_tr_ev <ferramenta> <input-json> — uma linha stream-json com um tool_use
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"%s","input":%s}]}}\n' "$1" "$2"
}
u_tr() {
  local a="$1" d t bom
  command -v jq >/dev/null 2>&1 || return 1
  U_N=$((U_N + 1)); d="$U_DIR/tr$U_N"; mkdir -p "$d"
  bom="$(u_tr_ev Read '{"file_path":"C:\\p\\.claude\\skills\\sprintx\\references\\08-rastro.md"}')
$(u_tr_ev Bash '{"command":"bash .claude/skills/sprintx/scripts/rastro.sh task-iniciada fx T-01.01"}')
$(u_tr_ev Bash '{"command":"cat docs/eventos/fx.jsonl 2>/dev/null | tail -3"}')
$(u_tr_ev Edit '{"file_path":"C:\\p\\src\\a.ts","old_string":"a","new_string":"b"}')
$(u_tr_ev Bash '{"command":"bash .claude/skills/sprintx/scripts/rastro.sh task-concluida fx T-01.01 ok src/a.ts"}')"
  printf '%s\n' "$bom" > "$d/bom"
  ( . "$a/.claude/hooks/testes/transcrito-agente.sh"; transcrito_verifica "$d/bom" 1111-2222 fx T-01.01 ) >/dev/null || return 1
  # cada uma destas reprova, pela regra certa
  for t in \
    'leu_hook|Read|{"file_path":"C:\\p\\.claude\\hooks\\comum\\rastro.sh"}' \
    'leu_hook|Grep|{"pattern":"sessao","path":".claude/hooks"}' \
    'leu_hook|Bash|{"command":"sed -n 1,80p .claude/hooks/sprintx/escopo-da-task.sh"}' \
    'rastro_manual|Bash|{"command":"printf %s x >> docs/eventos/fx.jsonl"}' \
    'rastro_manual|Write|{"file_path":"C:\\p\\docs\\eventos\\fx.jsonl","content":"x"}' \
    'identidade_fabricada|Bash|{"command":"echo $CLAUDE_CODE_SESSION_ID"}' \
    'identidade_fabricada|Bash|{"command":"EXPX_SESSAO=claude-code@1111-2222 bash x.sh"}' \
    'identidade_fabricada|Bash|{"command":"echo 1111-2222"}'; do
    printf '%s\n%s\n' "$bom" "$(u_tr_ev "$(printf '%s' "$t" | cut -d'|' -f2)" "$(printf '%s' "$t" | cut -d'|' -f3-)")" > "$d/ruim"
    # `|| :` — sob pipefail o codigo 1 do verificador (o esperado aqui) viraria o codigo do pipe
    ( . "$a/.claude/hooks/testes/transcrito-agente.sh"; transcrito_verifica "$d/ruim" 1111-2222 fx T-01.01 || : ) \
      | grep -q "^${t%%|*}:" || return 1
  done
  # sem o escritor: reprova mesmo sem nenhuma outra violacao
  u_tr_ev Edit '{"file_path":"src/a.ts"}' > "$d/sem"
  ( . "$a/.claude/hooks/testes/transcrito-agente.sh"; transcrito_verifica "$d/sem" 1111-2222 fx T-01.01 || : ) | grep -q '^sem_escritor_inicio:'
}

U_CASOS="u_a u_b u_c u_d u_e u_f u_g u_hc u_i u_j u_k u_l u_doc u_tr"
if ! command -v jq >/dev/null 2>&1; then
  pula_externo "u-verificador-de-transcrito" "jq"
  U_CASOS="${U_CASOS% u_tr}"
fi
u_nome() {
  case "$1" in
    u_a) echo "ua-escritor-task-iniciada-escopo-reconhece-corrente" ;;
    u_b) echo "ub-escritor-task-iniciada-irma-continua-barrada" ;;
    u_c) echo "uc-sem-identidade-escritor-falha-e-nao-grava" ;;
    u_d) echo "ud-paths-windows-e-subdiretorio" ;;
    u_e) echo "ue-sessoes-diferentes-nao-reivindicam-uma-pela-outra" ;;
    u_f) echo "uf-worktrees-diferentes-nao-se-confundem" ;;
    u_g) echo "ug-evento-legado-sem-sessao-continua-sem-reivindicar" ;;
    u_hc) echo "uh-task-concluida-e-bloqueada-pelo-escritor" ;;
    u_i) echo "ui-contexto-divergente-nao-grava-no-pedido" ;;
    u_j) echo "uj-sessao-e-harness-nunca-vem-de-quem-chama" ;;
    u_k) echo "uk-grava-no-trabalho-dado-nao-no-homonimo" ;;
    u_l) echo "ul-eventos-informativos-pelo-mesmo-escritor" ;;
    u_doc) echo "udoc-referencia-nao-ensina-linha-a-mao" ;;
    u_tr) echo "utr-verificador-de-transcrito-do-agente" ;;
  esac
}
for c in $U_CASOS; do u_nm="$(u_nome "$c")"; "$c" "$U_REAL" >/dev/null 2>&1; u_rc=$?
  afirma "$u_nm" "$u_rc" "arvore do repositorio"; done

# Mutantes: copia do layout instalado; o controle e a copia sem mutacao. Cada mutante tem de
# morrer pelos casos que o nomeiam — nao vale morrer de carona.
u_mutante() { # u_mutante <nome> <rc geracao> <arvore> <casos que TEM de matar>
  local nome="$1" rc="$2" r="$3" c vivos=""
  if [ "$rc" -eq 0 ]; then for c in $4; do "$c" "$r" >/dev/null 2>&1 && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]; afirma "$nome" $? "morto por: $4 ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
UMC="$(u_arvore controle)"; U_VIVO=""
for c in $U_CASOS; do "$c" "$UMC" >/dev/null 2>&1 || U_VIVO="$U_VIVO $c"; done
[ -z "$U_VIVO" ]; afirma "um-controle-copia-intacta-sobrevive" $? "${U_VIVO:+reprovada por:$U_VIVO}"
U_W=".claude/skills/sprintx/scripts/rastro.sh"; U_L=".claude/hooks/comum/rastro.sh"
U_R=".claude/skills/sprintx/references"
u_m() { # u_m <nome> <arquivo-relativo> <trecho> <troca> — arvore nova com UMA troca literal
  local r; r="$(u_arvore "$1")"
  muta_lit "$r/$2" "$r/$2.m" "$3" "$4" && mv "$r/$2.m" "$r/$2" && printf '%s' "$r"
}
# 1. task_iniciada volta a ser gravada sem identidade (o escritor nao a poe na linha).
UMU="$(u_m m1 "$U_W" 'EXTRAS="\"sessao\":\"$SESSAO_E\",\"harness\":\"$HARNESS_E\""' "EXTRAS='\"sessao\":null,\"harness\":null'")"
u_mutante "um-1-task-iniciada-sem-identidade" $? "$UMU" "u_a u_hc"
# 2. A referencia volta a ensinar printf manual em Como gravar.
UMU="$(u_m m2 "$U_R/08-rastro.md" 'Pelo escritor da skill' "Acrescente uma linha: printf '%s\\n' '{\"evento\":\"task_iniciada\",...}' >> docs/eventos/<slug>.jsonl. Pelo escritor da skill")"
u_mutante "um-2-referencia-volta-a-ensinar-printf" $? "$UMU" "u_doc"
# 3. O escritor aceita a ausencia de identidade (evento de reivindicacao nao a exige mais).
UMU="$(u_m m3 "$U_W" 'RASTRO_TASK="\"$ALVO\""; EXIGE_IDENTIDADE=1' 'RASTRO_TASK="\"$ALVO\""; EXIGE_IDENTIDADE=0')"
u_mutante "um-3-escritor-aceita-sem-identidade" $? "$UMU" "u_c"
# 3b. A identidade aceita o <ppid> do fallback (nao e o mesmo no hook).
UMU="$(u_m m3b "$U_L" 'case "$RASTRO_SESSAO_FONTE" in expx|harness) ;;' 'case "$RASTRO_SESSAO_FONTE" in expx|harness|ppid) ;;')"
u_mutante "um-3b-identidade-aceita-ppid" $? "$UMU" "u_c"
# 4. A sessao fornecida pelo agente substitui a derivada.
UMU="$(u_m m4 "$U_W" 'DETALHE="${1:-}"; [ $# -gt 0 ] && shift' 'DETALHE="${1:-}"; [ $# -gt 0 ] && shift; [ "${1:-}" = --sessao ] && { export EXPX_SESSAO="$2"; shift 2; }')"
u_mutante "um-4-sessao-do-agente-substitui-a-derivada" $? "$UMU" "u_j"
# 5. O harness fornecido pelo agente substitui o derivado.
UMU="$(u_m m5 "$U_W" 'DETALHE="${1:-}"; [ $# -gt 0 ] && shift' 'DETALHE="${1:-}"; [ $# -gt 0 ] && shift; [ "${1:-}" = --harness ] && { export EXPX_HARNESS="$2"; shift 2; }')"
u_mutante "um-5-harness-do-agente-substitui-o-derivado" $? "$UMU" "u_j"
# 6. O escopo nao reconhece o evento do escritor (a chave sai num formato que a leitura nao casa).
UMU="$(u_m m6 "$U_W" 'EXTRAS="\"sessao\":\"$SESSAO_E\"' 'EXTRAS="\"sessao\": \"$SESSAO_E\"')"
u_mutante "um-6-escopo-nao-reconhece-evento-do-escritor" $? "$UMU" "u_a u_b"
# 7. A sessao A usa a reivindicacao da sessao B (a leitura para de comparar a sessao).
UMU="$(u_m m7 "$U_L" 'if (_rv_dono[k] == "" || _rv_dono[k] != ses) continue' 'if (_rv_dono[k] == "") continue')"
u_mutante "um-7-sessao-a-usa-reivindicacao-da-b" $? "$UMU" "u_e"
# 8. O escritor grava no trabalho errado (destino pela sessao, nao pelo trabalho dado).
UMU="$(u_m m8 "$U_W" 'rastro_grava_trabalho "$RAIZ" "$SLUG"' 'rastro_grava_trabalho "$RAIZ" -')"
u_mutante "um-8-escritor-grava-no-trabalho-errado" $? "$UMU" "u_a u_k"
# 9. O agente passa so porque leu a implementacao do hook: o verificador deixa de olhar isso.
UMU="$(u_m m9 .claude/hooks/testes/transcrito-agente.sh '*.claude/hooks*) v=' '*.claude/hooks-nunca*) v=')"
u_mutante "um-9-agente-passa-lendo-o-hook" $? "$UMU" "u_tr"
# 10. task_concluida volta ao caminho manual: a referencia e o escritor.
UMU="$(u_m m10 "$U_R/06-execucao.md" 'grave `task_concluida` no rastro pelo escritor — `bash <raiz-da-skill>/scripts/rastro.sh task-concluida <slug> <T-NN.MM> "<resultado da suíte>" <arquivos da task>` —,' 'grave `task_concluida` no rastro,')"
u_mutante "um-10-task-concluida-volta-ao-manual-na-referencia" $? "$UMU" "u_doc"
UMU="$(u_m m10b "$U_W" 'RASTRO_TASK="\"$ALVO\""; EXIGE_IDENTIDADE=1' 'RASTRO_TASK="\"$ALVO\""; EXIGE_IDENTIDADE=$([ "$CMD" = task-iniciada ] && echo 1 || echo 0)')"
u_mutante "um-10b-task-concluida-sem-identidade-no-escritor" $? "$UMU" "u_c"
rm -rf "$U_DIR"

echo "== V. duracao_observada chega a todo contrato do HISTORICO.md (D-05) =="
# O rastro mede o tempo de parede de cada task (par task_iniciada/task_concluida) e
# 06-execucao.md / 08-rastro.md mandam persisti-lo no HISTORICO.md como duracao_observada
# (DS-37). O contrato do kind, o template e a lista de campos da estimativa precisam
# carregar o mesmo campo — senao a instrucao existe e nao tem onde pousar.
V_SCH="$SK/references/00-schema.md"
V_TPL="$SK/assets/TEMPLATE-HISTORICO.md"
V_EST="$SK/references/07-estimativa.md"
V_EXE="$SK/references/06-execucao.md"

# Regiao de uma entrada (entre 'entradas:' e 'calibracao:') e a regiao da calibracao,
# nos dois arquivos que carregam o frontmatter do kind.
v_entradas() { awk '/^entradas:/{f=1;next} /^calibracao:/{f=0} f' "$1"; }
v_calibracao() { awk '/^calibracao:/{f=1;next} f && /^---/{f=0} f' "$1"; }
v_colunas() { printf '%s' "$1" | awk -F'|' '{print NF}'; }

# 1. A instrucao que origina o campo continua de pe nas duas referencias que a mandam.
tem "$V_EXE" 'entra no `HISTORICO.md` como `duracao_observada`'; afirma "v1-execucao-manda-persistir" $? "06-execucao.md Passo 3"
tem "$SK/references/08-rastro.md" 'O valor entra como **`duracao_observada`**'; afirma "v1b-rastro-manda-persistir" $? "08-rastro.md"

# 2. O kind estimativa_historico carrega o campo na entrada do exemplo.
v_entradas "$V_SCH" | grep -qF 'duracao_observada:'; afirma "v2-schema-entrada-tem-campo" $? "00-schema.md, exemplo do kind"

# 3. Opcional/nullable: sem o par de eventos, nao ha valor — e legado sem a chave nao e recusado.
tem "$V_SCH" '`duracao_observada` é **opcional**'; afirma "v3-schema-opcional" $? "declarado opcional"
tem "$V_SCH" '`null` quando o par `task_iniciada`/`task_concluida` do rastro não existe'; afirma "v3b-schema-null-sem-par" $? "null sem par de eventos"
tem "$V_SCH" 'Entrada legada sem a chave é lida como `duracao_observada: null`, nunca recusada.'; afirma "v3c-schema-legado-aceito" $? "compatibilidade com historico antigo"

# 4. Distinto de real: tempo de parede nao e esforco, e nunca o substitui (DS-37).
tem "$V_SCH" '`duracao_observada` **não é `real`** e nunca o substitui'; afirma "v4-schema-distinto-de-real" $? "campo separado de real"

# 5. Fora do desvio e fora da calibracao: nao contamina o numero que calibra estimativa.
tem "$V_SCH" 'fica **fora do cálculo de `desvio`**'; afirma "v5-schema-fora-do-desvio" $? "desvio continua real/estimado_media"
tem "$V_SCH" 'e **fora da `calibracao`**'; afirma "v5b-schema-fora-da-calibracao" $? "desvio_medio e fator_ativo nao a leem"
v_calibracao "$V_SCH" | grep -qF 'duracao_observada'; [ $? -ne 0 ]; afirma "v5c-schema-calibracao-limpa" $? "bloco calibracao nao carrega o campo"
# A entrada coloca duracao_observada DEPOIS de desvio: a cadeia de calibracao termina em desvio.
V_LD=$(v_entradas "$V_SCH" | grep -nF 'desvio:' | head -1 | cut -d: -f1)
V_LO=$(v_entradas "$V_SCH" | grep -nF 'duracao_observada:' | head -1 | cut -d: -f1)
[ -n "$V_LD" ] && [ -n "$V_LO" ] && [ "$V_LO" -gt "$V_LD" ]; afirma "v5d-schema-campo-depois-do-desvio" $? "desvio=$V_LD < duracao_observada=$V_LO"

# 6. O template que gera o arquivo carrega o campo no YAML, opcional.
v_entradas "$V_TPL" | grep -qF 'duracao_observada: {{numero ou null}}'; afirma "v6-template-yaml-tem-campo" $? "TEMPLATE-HISTORICO.md, entradas"
v_calibracao "$V_TPL" | grep -qF 'duracao_observada'; [ $? -ne 0 ]; afirma "v6b-template-calibracao-limpa" $? "calibracao do template nao carrega o campo"

# 7. Regra universal 7: o YAML e a tabela humana dizem a mesma coisa.
tem "$V_TPL" 'Duração observada'; afirma "v7-template-tabela-tem-coluna" $? "coluna na tabela de Entradas"
V_H=$(grep -F '| Trabalho | Task | Tipo |' "$V_TPL" | head -1)
V_SEP=$(grep -nF '| Trabalho | Task | Tipo |' "$V_TPL" | head -1 | cut -d: -f1)
V_SEP=$(sed -n "$((V_SEP + 1))p" "$V_TPL")
V_LIN=$(grep -F '| {{slug}} |' "$V_TPL" | head -1)
[ "$(v_colunas "$V_H")" = "$(v_colunas "$V_SEP")" ] && [ "$(v_colunas "$V_H")" = "$(v_colunas "$V_LIN")" ]
afirma "v7b-template-tabela-coerente" $? "cabecalho=$(v_colunas "$V_H") separador=$(v_colunas "$V_SEP") linha=$(v_colunas "$V_LIN")"
# 7.1 Ausencia nao vira numero com unidade: `duracao_observada` e null de rotina
# (rastro desligado, sem par de eventos), e `null h` leria como "null horas", misturando
# ausencia com grandeza. A regra da celula vazia vale para a tabela inteira.
tem "$V_TPL" 'a célula correspondente da tabela leva `—`, nunca `null` e nunca `null h`'
afirma "v11-regra-da-celula-sem-valor" $? "a tabela diz como ausencia se escreve"
V_CEL="$(grep -F '| {{slug}} |' "$V_TPL" | head -1 | awk -F'|' '{print $(NF-1)}')"
printf '%s' "$V_CEL" | grep -qE '\}\}[[:space:]]*h[[:space:]]*$'; [ $? -ne 0 ]
afirma "v11b-duracao-sem-unidade-fora-do-marcador" $? "celula=[$V_CEL]"
V_SIM="$(printf '%s' "$V_CEL" | sed 's/{{[^}]*}}/null/g')"
printf '%s' "$V_SIM" | grep -qE 'null[[:space:]]+h'; [ $? -ne 0 ]
afirma "v11c-nulo-nao-renderiza-null-h" $? "render=[$V_SIM]"

# 8. A lista de campos da estimativa (F3.5, Passo 10) nomeia o campo.
tem "$V_EST" '`duracao_observada`'; afirma "v8-estimativa-lista-o-campo" $? "07-estimativa.md Passo 10"
# A lista do Passo 10 (F3.5) e a do Passo 3 (F6) descrevem a MESMA entrada do
# `estimativa_historico`: divergir em um campo faz a skill gravar coisas diferentes
# conforme a referencia que a sessao abriu.
v_campos() { # v_campos <arquivo> <ancora da linha> — campos `x` daquela lista, ordenados
  grep -F "$2" "$1" | head -1 \
    | sed 's/.*com: //; s/\. .*//; s/\.$//' \
    | grep -oE '`[a-z_]+`' | tr -d '`' | sort -u
}
V_C7="$(v_campos "$V_EST" 'recebe uma linha por task concluída')"
V_C6="$(v_campos "$V_EXE" 'Uma entrada por task **concluída**, com:')"
printf '%s' "$V_C7" | grep -qx 'estimado_media'; afirma "v10-estimativa-lista-estimado-media" $? "Passo 10 nomeia estimado_media"
[ "$V_C7" = "$V_C6" ]; afirma "v10b-listas-de-campos-coerentes" $? "F3.5 e F6 listam os mesmos campos${V_C7:+ ($(printf '%s' "$V_C7" | grep -c '') x $(printf '%s' "$V_C6" | grep -c ''))}"

# 9. A lista de campos da propria F6 nomeia o campo que a prosa dela manda gravar.
V_LISTA=$(grep -F 'Uma entrada por task **concluída**, com:' "$V_EXE" | head -1)
printf '%s' "$V_LISTA" | grep -qF 'duracao_observada'; afirma "v9-execucao-lista-o-campo" $? "lista do Passo 3 bate com a prosa do Passo 3"

echo "== W. fallback sem jq decodifica os escapes do payload (D-06) =="
# Sem jq, rastro_tool_input_get extraia o valor com grep -o + sed e NAO decodificava os
# escapes de JSON: `content` voltava numa linha so, com \n literais. O awk de
# task-reivindicada.sh (/^  - id:/) nao casava nada, IDS_EM_ANDAMENTO saia vazio e o hook
# falhava ABERTO (exit 0) onde devia bloquear (exit 2). O helper correto — sem processo,
# com aspa escapada e \n decodificados — ja existia no mesmo arquivo: rastro_json_campo_em.
W_DIR="$(mktemp -d)"
# Raiz dos hooks em forma absoluta: os casos abaixo rodam com `cd` na fixture.
W_H="$(cd "$H" && pwd)"

# Um PATH equivalente ao atual, sem nenhum `jq` executavel: so os diretorios que de fato
# tem jq viram espelho de symlinks sem ele. Funciona com jq em ~/.local/bin ou em /usr/bin,
# e e no-op na maquina que nao tem jq.
w_path_sem_jq() {
  local d f espelho novo="" i=0 IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    if [ -x "$d/jq" ]; then
      i=$((i+1)); espelho="$W_DIR/bin$i"
      if [ ! -d "$espelho" ]; then
        mkdir -p "$espelho"
        for f in "$d"/*; do
          [ -e "$f" ] || continue
          [ "${f##*/}" = jq ] && continue
          ln -sf "$f" "$espelho/${f##*/}" 2>/dev/null
        done
      fi
      novo="$novo:$espelho"
    else
      novo="$novo:$d"
    fi
  done
  printf '%s' "${novo#:}"
}
W_SEMJQ="$(w_path_sem_jq)"
PATH="$W_SEMJQ" command -v jq >/dev/null 2>&1; [ $? -ne 0 ]
afirma "w0-sandbox-esconde-jq" $? "o PATH do caso nao enxerga jq"

# Extrator isolado: le a chave pelo helper publico e grava o valor cru num arquivo, para
# que a comparacao nao dependa de substituicao de comando (que come newline do fim).
cat > "$W_DIR/extrai.sh" <<'SH'
. "$1/comum/rastro.sh"
J="$(cat "$2")"
V="$(rastro_tool_input_get "$J" "$3")"
printf '%s' "$V" > "$4"
SH

# O payload real do harness: content e o tasks.md inteiro, escapado como JSON.
W_TASKS="$W_DIR/tasks-fonte.md"
cat > "$W_TASKS" <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: tasks
trabalho_id: feat-w
sprint_id: sprint-01
tasks:
  - id: T-01.01
    status: em_andamento
    teste_integracao: Chama o endpoint de exportacao
    arquivos:
      cria: []
      altera: [src/a.ts]
---
YAML
W_FX="$W_DIR/repo"
mkdir -p "$W_FX/.git" "$W_FX/docs/sprintx/features/feat-w/sprint-01" "$W_FX/docs/eventos" "$W_FX/.expx"
cp "$W_TASKS" "$W_FX/docs/sprintx/features/feat-w/sprint-01/tasks.md"
W_PAY="$W_DIR/payload.json"
python3 -c "
import json, sys
print(json.dumps({'cwd': sys.argv[1], 'tool_name': 'Write',
  'tool_input': {'file_path': sys.argv[2], 'content': open(sys.argv[3], encoding='utf-8').read()}}))
" "$W_FX" "$W_FX/docs/sprintx/features/feat-w/sprint-01/tasks.md" "$W_TASKS" > "$W_PAY"

# 1. Sem jq, o content volta com linhas DE VERDADE — e o awk do hook acha o id.
PATH="$W_SEMJQ" bash "$W_DIR/extrai.sh" "$W_H" "$W_PAY" content "$W_DIR/sem.txt"
W_L=$(wc -l < "$W_DIR/sem.txt")
[ "$W_L" -ge 10 ]; afirma "w1-sem-jq-content-tem-linhas-reais" $? "$W_L linhas (esperado >= 10)"
grep -qF '\n' "$W_DIR/sem.txt"; [ $? -ne 0 ]; afirma "w1b-sem-jq-sem-barra-n-literal" $? "nenhum \\n literal sobrou"
W_IDS="$(awk '/^  - id:/ { id = $3; sub(/^[ \t]+/, "", id) } /status:[ \t]*em_andamento/ { if (id != "") print id }' "$W_DIR/sem.txt")"
[ "$W_IDS" = "T-01.01" ]; afirma "w1c-sem-jq-awk-do-hook-acha-o-id" $? "IDS_EM_ANDAMENTO=[$W_IDS]"

# 2. Paridade: com jq e sem jq entregam exatamente o mesmo valor.
bash "$W_DIR/extrai.sh" "$W_H" "$W_PAY" content "$W_DIR/com.txt"
cmp -s "$W_DIR/com.txt" "$W_DIR/sem.txt"; afirma "w2-paridade-com-jq-e-sem-jq" $? "content identico nos dois caminhos"
bash "$W_DIR/extrai.sh" "$W_H" "$W_PAY" file_path "$W_DIR/fc.txt"
PATH="$W_SEMJQ" bash "$W_DIR/extrai.sh" "$W_H" "$W_PAY" file_path "$W_DIR/fs.txt"
cmp -s "$W_DIR/fc.txt" "$W_DIR/fs.txt" && grep -qF 'sprint-01/tasks.md' "$W_DIR/fs.txt"
afirma "w2b-file-path-nao-regride" $? "file_path identico e correto sem jq"

# 3. Aspa escapada dentro do valor nao trunca (o `[^"]*` do fallback antigo parava nela).
python3 -c "
import json
print(json.dumps({'cwd': '/x', 'tool_input': {'content': 'a: \"entre aspas\"\nb: fim'}}))
" > "$W_DIR/aspas.json"
PATH="$W_SEMJQ" bash "$W_DIR/extrai.sh" "$W_H" "$W_DIR/aspas.json" content "$W_DIR/aspas.txt"
grep -qF 'b: fim' "$W_DIR/aspas.txt"; afirma "w3-sem-jq-aspa-escapada-nao-trunca" $? "valor inteiro preservado"

# 4. Ponta a ponta: o caso que reprovou. Modo bloqueio, task aberta por OUTRA sessao.
printf '%s\n' '{"ts":"2026-09-30T10:00:00Z","expx_eventos":1,"trabalho_id":"feat-w","ferramenta":"sprintx","origem":"skill","evento":"task_iniciada","fase":"f6","task":"T-01.01","agente":"principal","resultado":"ok","detalhe":null,"arquivos":[],"sessao":"opencode@outra","harness":"opencode"}' \
  > "$W_FX/docs/eventos/feat-w.jsonl"
echo '{"hooks":{"task-reivindicada":{"modo":"bloqueio"}}}' > "$W_FX/.expx/hooks.json"
w_hook() { # w_hook <PATH> -> ecoa o exit code do hook
  local rc
  (cd "$W_FX" && PATH="$1" EXPX_SESSAO=sessao-minha bash "$W_H/sprintx/task-reivindicada.sh" < "$W_PAY" >/dev/null 2>&1)
  rc=$?; printf '%s' "$rc"
}
W_RC_SEM="$(w_hook "$W_SEMJQ")"
[ "$W_RC_SEM" = 2 ]; afirma "w4-sem-jq-hook-bloqueia" $? "exit=$W_RC_SEM (esperado 2)"
W_RC_COM="$(w_hook "$PATH")"
[ "$W_RC_COM" = 2 ]; afirma "w4b-com-jq-hook-continua-bloqueando" $? "exit=$W_RC_COM (esperado 2)"

# 5. Guarda estrutural: nenhum leitor do payload volta ao grep tolerante que perdia escape.
grep -qF 'grep -o "\"$chave\"' "$W_H/comum/rastro.sh"; [ $? -ne 0 ]
afirma "w5-sem-grep-tolerante-no-rastro" $? "os fallbacks usam o helper que decodifica"

# 6. `\uXXXX` tambem e escape de JSON. Sem jq ele ficava literal e — pior — o ramo
# `*\u*` do case era o PRIMEIRO, entao engolia os outros escapes: um unico acento
# (`é` -> `é`) devolvia `content` numa linha so e ressuscitava o defeito do w4.
w_u() { # w_u <texto> <arquivo-saida> <PATH> — extrai `content` daquele texto
  python3 -c 'import json,sys; print(json.dumps({"cwd":"/x","tool_input":{"content":sys.argv[1]}}))' "$1" > "$W_DIR/u.json"
  PATH="$3" bash "$W_DIR/extrai.sh" "$W_H" "$W_DIR/u.json" content "$2"
}
W_BMP="a$(printf 'é')b"
w_u "$W_BMP" "$W_DIR/u-sem.txt" "$W_SEMJQ"; w_u "$W_BMP" "$W_DIR/u-com.txt" "$PATH"
cmp -s "$W_DIR/u-sem.txt" "$W_DIR/u-com.txt" && grep -qF "$W_BMP" "$W_DIR/u-sem.txt"
afirma "w6-sem-jq-decodifica-bmp" $? "\\u00e9 vira o mesmo byte que o jq entrega"
W_SUR="x$(printf '\U0001F600')y"
w_u "$W_SUR" "$W_DIR/u2-sem.txt" "$W_SEMJQ"; w_u "$W_SUR" "$W_DIR/u2-com.txt" "$PATH"
cmp -s "$W_DIR/u2-sem.txt" "$W_DIR/u2-com.txt" && grep -qF "$W_SUR" "$W_DIR/u2-sem.txt"
afirma "w6b-sem-jq-decodifica-par-substituto" $? "\\ud83d\\ude00 vira um caractere so, fora do BMP"
W_MIX="linha1
linha2 com acento a$(printf 'é')b"
w_u "$W_MIX" "$W_DIR/u3-sem.txt" "$W_SEMJQ"
W_UL=$(wc -l < "$W_DIR/u3-sem.txt")
[ "$W_UL" -ge 1 ]; afirma "w7-u-nao-engole-os-outros-escapes" $? "$W_UL linha(s) reais (esperado >= 1)"
W_TUDO="a$(printf 'é')b$(printf '\t')c$(printf '\U0001F600')d
fim"
w_u "$W_TUDO" "$W_DIR/u4-sem.txt" "$W_SEMJQ"; w_u "$W_TUDO" "$W_DIR/u4-com.txt" "$PATH"
cmp -s "$W_DIR/u4-sem.txt" "$W_DIR/u4-com.txt"
afirma "w7b-paridade-total-dos-escapes" $? "BMP + controle + par substituto + \\n: igual byte a byte"
rm -rf "$W_DIR"

echo "== X. calibracao vazia tem forma canonica na tabela do HISTORICO.md (D-08) =="
# `calibracao: []` e estado valido e inevitavel do `kind: estimativa_historico` — o primeiro
# trabalho do projeto, e todo trabalho que rodou sem a F3.5, fecham com desvio nenhum por tipo.
# O template tinha a linha de dados parametrizada da tabela de calibracao, mas nenhum ponto
# canonico dizia como a tabela humana fica com a lista vazia. A regra generica de celula ausente
# manda `—`, e a execucao produziu honestamente `| — | — | — | — |`: uma linha de dados anunciando
# um `tipo_task` fora do enum, que o leitor limitado recusa como tabela corrompida. A forma
# canonica e a tabela com cabecalho e separador e NENHUMA linha de dados.
X_TPL="$SK/assets/TEMPLATE-HISTORICO.md"
X_SCH="$SK/references/00-schema.md"
X_EXE="$SK/references/06-execucao.md"

# Bloco `calibracao:` do frontmatter, e a tabela de calibracao da prosa (do cabecalho ate a
# primeira linha que nao e de tabela). Helpers proprios: a secao se le sozinha.
x_calibracao() { awk '/^calibracao:/{f=1;next} f && /^---/{f=0} f' "$1"; }
x_tabela() { awk '/^\| Tipo de task \| Entradas \|/{f=1} f && !/^\|/{exit} f' "$1"; }
x_linhas_de_dados() { x_tabela "$1" | awk 'NR>2'; }

# 1. A tabela existe com cabecalho e separador — a forma que sobrevive a lista vazia.
X_CAB="$(x_tabela "$X_TPL" | sed -n 1p)"
X_SEP="$(x_tabela "$X_TPL" | sed -n 2p)"
[ -n "$X_CAB" ] && printf '%s' "$X_SEP" | grep -qE '^\|[-:| ]+\|$'
afirma "x1-tabela-tem-cabecalho-e-separador" $? "separador=[$X_SEP]"

# 2. Uma linha de dados por item de `calibracao`, nunca mais, nunca menos: linha de dados sem
#    item correspondente no frontmatter e linha fabricada, e e o que a tabela vazia dispensa.
X_ITENS=$(x_calibracao "$X_TPL" | grep -cE '^[[:space:]]*-[[:space:]]+tipo_task:')
X_DADOS=$(x_linhas_de_dados "$X_TPL" | grep -c '^|')
[ "$X_ITENS" = "$X_DADOS" ]
afirma "x2-uma-linha-de-dados-por-item" $? "itens em calibracao=$X_ITENS linhas de dados=$X_DADOS"

# 3. Nenhuma linha de dados por sentinela: `—`, `n/a`, celula vazia ou `null` no primeiro campo
#    nao e linha de dados — e um `tipo_task` fora do enum.
x_sentinela() { # x_sentinela <arquivo> — linhas de dados cujo primeiro campo e sentinela
  x_linhas_de_dados "$1" | awk -F'|' '{ c=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", c)
    if (c == "" || c == "—" || c == "-" || c == "null" || tolower(c) == "n/a") print }'
}
X_SENT="$(x_sentinela "$X_TPL" | tr '\n' ' ')"
[ -z "$X_SENT" ]
afirma "x3-nenhuma-linha-sentinela-na-tabela" $? "linhas sentinela=[$X_SENT]"
# 3b. E em nenhum dos tres pontos canonicos existe linha de tabela comecando por sentinela:
#     `| — | — | — | — |` reintroduzido como forma permitida e o defeito que isto mata.
X_SENT_ALL="$(grep -nE '^\|[[:space:]]*(—|-|n/a|N/A|null)?[[:space:]]*\|' "$X_TPL" "$X_SCH" "$X_EXE" | tr '\n' ' ')"
[ -z "$X_SENT_ALL" ]
afirma "x3b-sentinela-nao-e-forma-permitida" $? "ocorrencias=[$X_SENT_ALL]"

# 4. A regra da calibracao vazia esta escrita nos tres pontos canonicos: o template que gera o
#    arquivo, o contrato do kind e o passo da F6 que recalcula a tabela. Regra em um ponto so e
#    regra que a sessao seguinte nao encontra.
for x_f in "$X_TPL" "$X_SCH" "$X_EXE"; do
  tem "$x_f" 'sem nenhuma linha de dados'; x_rc=$?
  afirma "x4-regra-da-calibracao-vazia-em-$(basename "$x_f")" "$x_rc" "a tabela vazia esta prescrita"
done
tem "$X_TPL" '`calibracao: []`'; afirma "x4b-template-nomeia-o-estado-do-yaml" $? 'a regra cita calibracao: []'
tem "$X_EXE" '`calibracao: []`'; afirma "x4c-execucao-nomeia-o-estado-do-yaml" $? 'o Passo 3 cita calibracao: []'
tem "$X_EXE" 'cabeçalho e separador'; afirma "x4d-checklist-da-f6-cobra-a-forma" $? "06-execucao.md descreve a forma vazia"

# 5. Linha fabricada e proibida explicitamente: sem isso, "nao ficar com tabela vazia" volta a
#    parecer uma licenca para inventar uma linha.
tem "$X_TPL" 'linha de dados sem item correspondente no frontmatter é proibida'
afirma "x5-template-proibe-linha-fabricada" $? "nunca fabricar linha para a tabela nao ficar vazia"

# 6. As sentinelas invalidas sao nomeadas uma a uma — `—`, `n/a`, celula vazia, e qualquer outra.
tem "$X_TPL" 'nunca use `—`, `n/a`, célula vazia ou qualquer outra sentinela como se fosse linha'
afirma "x6-template-nomeia-as-sentinelas" $? "as quatro formas invalidas estao escritas"

# 7. A regra da celula ausente continua de pe (v11), e continua sendo de CELULA: ela vale para
#    celula de linha real e nunca autoriza uma linha inteira de `—`. Confundir as duas e a causa.
tem "$X_TPL" 'a célula correspondente da tabela leva `—`, nunca `null` e nunca `null h`'
afirma "x7-regra-da-celula-ausente-preservada" $? 'o travessao continua valendo para celula de linha real'
tem "$X_TPL" 'vale para célula de uma linha real, nunca para a linha inteira'
afirma "x7b-celula-ausente-nao-vira-linha" $? "a regra de celula nao se estende a linha"

# 8. O vocabulario do enum nao e afrouxado para acomodar a sentinela: o primeiro campo de uma
#    linha de dados sai do enum `tipo_task`, e `—` nao esta nele.
X_ENUM="$(grep -F '| `tipo_task` |' "$X_SCH" | head -1)"
[ -n "$X_ENUM" ] && ! printf '%s' "$X_ENUM" | grep -qE '—|n/a|null'; x_rc=$?
afirma "x8-enum-tipo-task-sem-sentinela" "$x_rc" "enum=[$(printf '%s' "$X_ENUM" | cut -c1-60)...]"

echo "== Y. o agregador da calibracao do HISTORICO.md e canonico: media, nunca mediana (D-09) =="
# O contrato dizia as duas coisas sobre o MESMO numero. `desvio_medio` era definido como a media
# dos `desvio_task` — a notacao da epoca, que a D-11 desfez em `desvio_padrao_task` e
# `desvio_calibracao_task` (06-execucao.md Passo 3, TEMPLATE-HISTORICO.md, 07-estimativa.md
# Passo 10, e o proprio nome do campo persistido) —, e ao mesmo tempo duas frases mandavam a
# calibracao usar mediana (06-execucao.md, 08-rastro.md, DS-37, README.md). A justificativa da
# mediana e sobre tempo de parede com pausa — isto e, sobre `duracao_observada`, que o schema,
# o template e a 07-estimativa declaram FORA do desvio e FORA da calibracao. Logo a premissa da
# mediana nao alcanca o numero que calibra: o que a calibracao agrega e o
# `desvio_calibracao_task`, construido sobre o `real` anotado, que ja exclui pausa. Duas
# execucoes validas produziam 2,0 e 1,0 do mesmo historico. Canonico: MEDIA.
# `duracao_observada` nao escolhe o agregador porque nao o alimenta.
Y_EXE="$SK/references/06-execucao.md"
Y_RAS="$SK/references/08-rastro.md"
Y_TPL="$SK/assets/TEMPLATE-HISTORICO.md"
Y_SCH="$SK/references/00-schema.md"
Y_EST="$SK/references/07-estimativa.md"
Y_DS="$SK/DECISOES-DA-SKILL.md"
Y_RME="$H/../../README.md"

# Os pontos que DEFINEM o agregador, e o conjunto maior onde a regra oposta nao pode reaparecer.
Y_DEFINEM="$Y_EXE $Y_RAS $Y_TPL $Y_SCH $Y_EST"
Y_TODOS="$Y_DEFINEM $Y_DS $Y_RME"

# 1. Dados literais que SEPARAM os dois agregadores: sem isso, "media ou mediana" seria discussao
#    sem consequencia observavel. Desvios [1,0 1,0 4,0]: media 2,00 e mediana 1,00.
Y_DESVIOS='1.0 1.0 4.0'
y_media()   { printf '%s\n' $1 | awk '{s+=$1;n++} END{ if (n) printf "%.2f", s/n }'; }
y_mediana() { printf '%s\n' $1 | sort -g | awk '{v[NR]=$1} END{ if (NR%2) printf "%.2f", v[(NR+1)/2];
              else printf "%.2f", (v[NR/2]+v[NR/2+1])/2 }'; }
Y_MED="$(y_media "$Y_DESVIOS")"; Y_MDN="$(y_mediana "$Y_DESVIOS")"
[ "$Y_MED" = "2.00" ] && [ "$Y_MDN" = "1.00" ] && [ "$Y_MED" != "$Y_MDN" ]
afirma "y1-dados-separam-os-dois-agregadores" $? "desvios=[$Y_DESVIOS] media=$Y_MED mediana=$Y_MDN"

# 2. O agregador e LIDO da documentacao, nao assumido pelo teste: cada ponto canonico declara um
#    token, e o conjunto dos tokens tem de ser exatamente {media}. `ambos` e a contradicao D-09.
# O simbolo do insumo agregado e o `desvio_calibracao_task` (D-11/DS-162); `desvio_task` fica na
# alternancia porque o registro e append-only e a DS-37 do item 7 conserva a notacao da epoca. Os
# dois detectores aceitam exatamente o mesmo conjunto de nomes: afrouxar so o lado da media
# deixaria "mediana dos `desvio_calibracao_task`" passar sem ser vista.
y_diz_media()   { grep -qiE 'm[ée]dia(\*\*)? d(os|e) (`?desvio(_calibracao)?_task`?|desvios)' "$1"; }
y_diz_mediana() { grep -qiE 'mediana(\*\*)? d(os|e) (`?desvio(_calibracao)?_task`?|desvios)|calibra[çc][ãa]o usa (\*\*)?mediana|mediana(\*\*)?, n[ãa]o m[ée]dia' "$1"; }
y_agregador() { # y_agregador <arquivo> -> media | mediana | ambos | nenhum
  local m=1 d=1
  y_diz_media "$1" && m=0
  y_diz_mediana "$1" && d=0
  if   [ $m -eq 0 ] && [ $d -eq 0 ]; then printf 'ambos'
  elif [ $m -eq 0 ]; then printf 'media'
  elif [ $d -eq 0 ]; then printf 'mediana'
  else printf 'nenhum'; fi
}
# 2a. Nenhum arquivo do contrato prescreve mediana, em ponto nenhum: a regra oposta reintroduzida
#     em QUALQUER um deles mata este caso. E o detector da contradicao.
Y_SUJOS=""
for y_f in $Y_TODOS; do
  case "$(y_agregador "$y_f")" in mediana|ambos) Y_SUJOS="$Y_SUJOS $(basename "$y_f")" ;; esac
done
[ -z "$Y_SUJOS" ]
afirma "y2-nenhum-ponto-prescreve-mediana" $? "arquivos com mediana=[${Y_SUJOS:- nenhum}]"

# 2b. E cada ponto que define o agregador diz `media`, nao `nenhum`: regra que so existe por
#     ausencia da errada e regra que a sessao seguinte nao encontra.
Y_MUDOS=""
for y_f in $Y_DEFINEM; do
  [ "$(y_agregador "$y_f")" = "media" ] || Y_MUDOS="$Y_MUDOS $(basename "$y_f"):$(y_agregador "$y_f")"
done
[ -z "$Y_MUDOS" ]
afirma "y2b-todo-ponto-canonico-diz-media" $? "fora de media=[${Y_MUDOS:- nenhum}]"

# 3. O agregador lido da documentacao, APLICADO aos desvios literais, da um valor unico — e e
#    2,00. Trocar o calculo esperado para a mediana mata este caso.
Y_VALORES=""
for y_f in $Y_DEFINEM; do
  case "$(y_agregador "$y_f")" in
    media)   Y_VALORES="$Y_VALORES $(y_media "$Y_DESVIOS")" ;;
    mediana) Y_VALORES="$Y_VALORES $(y_mediana "$Y_DESVIOS")" ;;
    *)       Y_VALORES="$Y_VALORES indefinido" ;;
  esac
done
Y_UNICO="$(printf '%s\n' $Y_VALORES | sort -u | tr '\n' ' ' | sed 's/ $//')"
[ "$Y_UNICO" = "2.00" ]
afirma "y3-um-valor-canonico-sobre-os-mesmos-dados" $? "valores por ponto canonico=[$Y_UNICO] (esperado 2.00)"

# 4. A razao pela qual `duracao_observada` NAO decide o agregador esta escrita, e nos dois pontos
#    que carregavam a frase errada: a justificativa da mediana era sobre tempo de parede, e tempo
#    de parede nao entra na conta. Sem isto escrito, a regra oposta volta com a mesma aparencia
#    de razao.
for y_f in "$Y_EXE" "$Y_RAS"; do
  tem "$y_f" 'não escolhe o agregador'; y_rc=$?
  afirma "y4-duracao-observada-nao-escolhe-o-agregador-em-$(basename "$y_f")" "$y_rc" \
    "a razao esta explicita onde estava a frase errada"
done

# 5. O que a calibracao agrega e nomeado: `desvio_calibracao_task`, vindo do `real` anotado —
#    nunca o tempo de parede. Permitir que `duracao_observada` alimente a calibracao mata este caso.
y_exclui() { # y_exclui <arquivo> — o arquivo tira `duracao_observada` da calibracao
  grep -qiE 'duração observada|`duracao_observada`' "$1" &&
  grep -qiE 'n[ãa]o (entra|participa)[^.]*calibra|fora da `calibracao`|calibra[çc][ãa]o nunca a l[êe]' "$1"
}
Y_VAZADOS=""
for y_f in $Y_DEFINEM; do
  y_exclui "$y_f" || Y_VAZADOS="$Y_VAZADOS $(basename "$y_f")"
done
[ -z "$Y_VAZADOS" ]
afirma "y5-duracao-observada-fora-da-calibracao-em-todo-ponto" $? "sem a exclusao=[${Y_VAZADOS:- nenhum}]"
tem "$Y_EXE" '`desvio_calibracao_task`'; afirma "y5b-execucao-nomeia-o-insumo-agregado" $? "o agregado e o desvio_calibracao_task"
tem "$Y_RAS" '`desvio_calibracao_task`'; afirma "y5c-rastro-nomeia-o-insumo-agregado" $? "o rastro aponta para o desvio_calibracao_task"

# 6. O campo persistido nao e renomeado: `desvio_medio` continua a chave do YAML no schema e no
#    template, e nenhuma variante `desvio_mediana` aparece. Compatibilidade de schema e parte do
#    contrato — a correcao e de prosa, nao de formato.
grep -qF 'desvio_medio:' "$Y_SCH" && grep -qF 'desvio_medio:' "$Y_TPL"
afirma "y6-chave-desvio-medio-preservada" $? "a chave do YAML continua desvio_medio"
Y_RENOMEIO="$(grep -rlE 'desvio_mediana|mediana_desvio' $Y_TODOS | tr '\n' ' ')"
[ -z "$Y_RENOMEIO" ]
afirma "y6b-nenhuma-chave-renomeada" $? "arquivos com chave renomeada=[${Y_RENOMEIO:- nenhum}]"

# 7. A decisao que originou a contradicao foi corrigida no proprio registro: DS-37 nasceu com a
#    frase da mediana (107dd95), e decisao nao corrigida e a contradicao esperando a proxima
#    sessao reinstala-la como se fosse a regra.
Y_DS37="$(grep -F '| DS-37 |' "$Y_DS")"
[ -n "$Y_DS37" ] && ! printf '%s' "$Y_DS37" | grep -qiE 'usa (\*\*)?mediana|mediana(\*\*)?, n[ãa]o m[ée]dia'; y_rc=$?
afirma "y7-ds37-sem-a-regra-oposta" "$y_rc" "DS-37 nao manda mais usar mediana"
printf '%s' "$Y_DS37" | grep -qiE 'm[ée]dia(\*\*)? d(os|e) (`?desvio_task`?|desvios)'; y_rc=$?
afirma "y7b-ds37-declara-o-agregador-canonico" "$y_rc" "DS-37 diz media dos desvio_task"

# 8. Nenhum ponto diz que a duracao do rastro ALIMENTA a calibracao. Essa frase e a premissa de
#    onde a mediana saiu: se o insumo fosse tempo de parede, trocar o agregador por causa da pausa
#    faria sentido. Ela sobrevivia na vitrine (README.md), na SKILL.md e no comentario do hook que
#    grava o evento — tres lugares onde a proxima sessao reconstroi a regra errada do zero.
# O sujeito tem de ser a duracao/tempo de parede: o `real` alimenta a calibracao de verdade, e
# dizer isso esta correto (Passo 2 da F6). `[^.|]` nao cruza ponto nem separador de celula — sem
# isso a regra certa, escrita como "nem alimenta a calibracao", seria lida como a premissa errada.
Y_ALIMENTA="$(grep -rnoE '(dura[çc][ãa]o|duracao_observada|tempo de parede)[^.|]*aliment(a|ando)[^.|]*calibra[çc][ãa]o' \
  $Y_TODOS "$SK/SKILL.md" "$H/comum/rastro-post.sh" \
  | grep -viE 'n[ãa]o aliment|nem aliment' | tr '\n' ' ')"
[ -z "$Y_ALIMENTA" ]
afirma "y8-duracao-nao-e-declarada-insumo-da-calibracao" $? "ocorrencias=[${Y_ALIMENTA:-nenhuma}]"

echo "== Z. precisao e desempate do desvio da calibracao sao canonicos (D-10) =="
# A D-09 tornou o AGREGADOR unico (media, nunca mediana). O numero continuava nao sendo unico:
# nenhum ponto do contrato fixava quantas casas decimais o `desvio` persistido carrega, o que
# fazer no empate exato, se a media e tirada dos `desvio` JA PERSISTIDOS ou das razoes brutas, nem
# se a forma gravada e `1.2` ou `1.20`. Cinco contextos frescos, lendo o contrato ao pe da letra,
# responderam "a documentacao nao fixa" (5/5) e dividiram a forma persistida entre `1.2` (3) e
# `1.20` (2) — a convergencia em half-up foi coincidencia declarada como escolha propria, e um
# deles mostrou que half-even daria `desvio_medio` 1,15 em vez de 1,16 sobre o mesmo historico.
# Decisao humana: half-up, duas casas fixas, sobre os `desvio` persistidos. O fator canonico entra
# na faixa da task/tipo ANTES da agregacao; floor(min)/ceil(max) a hora inteira continua o ultimo
# passo da faixa agregada.
Z_SCH="$SK/references/00-schema.md"
Z_TPL="$SK/assets/TEMPLATE-HISTORICO.md"
Z_EXE="$SK/references/06-execucao.md"
Z_EST="$SK/references/07-estimativa.md"
Z_TES="$SK/assets/TEMPLATE-ESTIMATIVA.md"
Z_DS="$SK/DECISOES-DA-SKILL.md"

# Os pontos que DEFINEM o numero persistido, e os que o CONSOMEM como fator.
Z_DEFINEM="$Z_SCH $Z_TPL $Z_EXE $Z_EST"
Z_CONSOMEM="$Z_EST $Z_TES"
Z_TODOS="$Z_DEFINEM $Z_TES $Z_DS"

# 1. Dados literais que SEPARAM as convencoes. As quatro entradas da amostra base
#    (real/estimado_media): 4.5/4.0, 4.5/4.0, 3.5/3.0 e 1.2/1.0 — razoes 1,125, 1,125, 1,1666... e
#    1,2. O empate exato em 1,125 e o que separa half-up de half-even; a terceira razao e o que
#    separa duas casas de uma; a quarta e o que separa `1.2` de `1.20`.
z_calc() { # z_calc <casas> <desempate:hup|hev> <operandos:persistidos|brutas> -> desvio_medio
  awk -v n="$1" -v d="$2" -v op="$3" '
    function rnd(x, nn, dd,   s, i, f) {
      s = x * (10 ^ nn); i = int(s); f = s - i
      if (dd == "hup") { if (f >= 0.5) i++ }
      else { if (f > 0.5) i++; else if (f == 0.5 && i % 2 != 0) i++ }
      return i / (10 ^ nn)
    }
    BEGIN {
      split("4.5 4.5 3.5 1.2", R, " "); split("4.0 4.0 3.0 1.0", E, " "); s = 0
      for (k = 1; k <= 4; k++) {
        r = R[k] / E[k]
        s += (op == "persistidos") ? rnd(r, n, d) : r
      }
      printf "%." n "f", rnd(s / 4, n, d)
    }'
}
Z_CANON="$(z_calc 2 hup persistidos)"      # a receita decidida
Z_HEV="$(z_calc 2 hev persistidos)"        # half-even
Z_BRUTAS="$(z_calc 2 hup brutas)"          # media das razoes brutas
Z_1CASA="$(z_calc 1 hup persistidos)"      # uma casa
Z_3CASAS="$(z_calc 3 hup persistidos)"     # tres casas
[ "$Z_CANON" = "1.16" ] && [ "$Z_HEV" = "1.15" ] && [ "$Z_BRUTAS" = "1.15" ] \
  && [ "$Z_1CASA" = "1.2" ] && [ "$Z_3CASAS" = "1.154" ] \
  && [ "$Z_CANON" != "$Z_HEV" ] && [ "$Z_CANON" != "$Z_BRUTAS" ] \
  && [ "$Z_CANON" != "$Z_1CASA" ] && [ "$Z_CANON" != "$Z_3CASAS" ]
afirma "z1-dados-separam-as-convencoes" $? \
  "canonico=$Z_CANON half-even=$Z_HEV brutas=$Z_BRUTAS 1casa=$Z_1CASA 3casas=$Z_3CASAS"

# 2. O desempate e LIDO da documentacao, nao assumido pelo teste: cada ponto que define o numero
#    declara um token, e o conjunto dos tokens tem de ser exatamente {hup}. `ambos` e contradicao.
# Os detectores de regra leem o texto SEM marcacao: `**antes**` e `antes` sao a mesma regra, e um
# caso que depende de onde cai o negrito testa formatacao, nao contrato.
z_txt() { tr -d '*`' < "$1"; }
# Todo casamento aqui CONTA linhas (`-c`) em vez de abortar na primeira (`-q`): depois de um pipe,
# `grep -q` fecha a entrada no primeiro casamento, o `tr` a montante leva SIGPIPE e, com
# `pipefail` ligado (linha 9), o status do pipeline fica nao-zero mesmo tendo casado. Isso faz o
# caso passar ou falhar por corrida de escalonamento — verde no foco, vermelho na suite inteira.
z_conta() { z_txt "$1" | grep -ciE "$2"; }
z_tem_re() { [ "$(z_conta "$1" "$2")" -gt 0 ]; }
z_diz_hup() { z_tem_re "$1" 'half-up|meio para cima'; }
# Nomear a convencao rejeitada nao e prescreve-la: a linha que traz o token tem de estar livre de
# marca de recusa. Sem isso, a frase que explica POR QUE nao e half-even se leria como a prescricao
# do half-even — o mesmo cuidado que a y8 (D-09) tomou com "nao alimenta a calibracao". Por isso a
# recusa mora na MESMA linha do token: o caso e por linha, nao por janela de caracteres.
Z_HEV_RE='half-even|banker|arredondamento para o par|meio para o par|meio para baixo'
Z_RECUSA_RE='nunca|em vez de|n[ãa]o aceita|n[ãa]o canonic|n[ãa]o can[õô]nic|seria|daria|correto em estat'
z_diz_hev() { # prescreve half-even sse alguma linha com o token NAO traz marca de recusa
  local tot rec
  tot="$(z_conta "$1" "$Z_HEV_RE")"
  rec="$(z_txt "$1" | grep -iE "$Z_HEV_RE" | grep -ciE "$Z_RECUSA_RE")"
  [ "$tot" -gt 0 ] && [ "$rec" -lt "$tot" ]
}
z_desempate() { # z_desempate <arquivo> -> hup | hev | ambos | nenhum
  local u=1 e=1
  z_diz_hup "$1" && u=0
  z_diz_hev "$1" && e=0
  if   [ $u -eq 0 ] && [ $e -eq 0 ]; then printf 'ambos'
  elif [ $u -eq 0 ]; then printf 'hup'
  elif [ $e -eq 0 ]; then printf 'hev'
  else printf 'nenhum'; fi
}
Z_SUJOS=""
for z_f in $Z_TODOS; do
  case "$(z_desempate "$z_f")" in hev|ambos) Z_SUJOS="$Z_SUJOS $(basename "$z_f")" ;; esac
done
[ -z "$Z_SUJOS" ]
afirma "z2-nenhum-ponto-prescreve-outro-desempate" $? "arquivos com desempate nao canonico=[${Z_SUJOS:- nenhum}]"

Z_MUDOS=""
for z_f in $Z_DEFINEM; do
  [ "$(z_desempate "$z_f")" = "hup" ] || Z_MUDOS="$Z_MUDOS $(basename "$z_f"):$(z_desempate "$z_f")"
done
[ -z "$Z_MUDOS" ]
afirma "z2b-todo-ponto-que-define-o-numero-diz-half-up" $? "fora de half-up=[${Z_MUDOS:- nenhum}]"

# 3. As casas tambem sao LIDAS, e sao DUAS em todo ponto que define o numero. Regra que existe so
#    por ausencia da errada e regra que a sessao seguinte nao encontra.
z_casas() { # z_casas <arquivo> -> 2 | 1 | 3 | ambiguo | nenhum
  local c=""
  z_tem_re "$1" 'duas casas decimais' && c="$c 2"
  z_tem_re "$1" 'uma casa decimal' && c="$c 1"
  z_tem_re "$1" 'tr[êe]s casas decimais' && c="$c 3"
  case "$(printf '%s' "$c" | tr -d ' ')" in
    2) printf '2' ;; 1) printf '1' ;; 3) printf '3' ;; '') printf 'nenhum' ;; *) printf 'ambiguo' ;;
  esac
}
Z_CASAS_FORA=""
for z_f in $Z_DEFINEM; do
  [ "$(z_casas "$z_f")" = "2" ] || Z_CASAS_FORA="$Z_CASAS_FORA $(basename "$z_f"):$(z_casas "$z_f")"
done
[ -z "$Z_CASAS_FORA" ]
afirma "z3-duas-casas-em-todo-ponto-que-define-o-numero" $? "fora de 2 casas=[${Z_CASAS_FORA:- nenhum}]"

# 4. O ESTAGIO esta escrito: cada `desvio` e arredondado ANTES de ser persistido, e a media sai dos
#    `desvio` persistidos — nunca das razoes brutas —, arredondada de novo pela mesma regra.
z_diz_persistidos() { # nomeia o operando certo E recusa o errado
  z_tem_re "$1" 'persistid[oa]s?' &&
  z_tem_re "$1" 'nunca (a m[ée]dia )?d(as|a) raz([õo]es|[ãa]o) brutas?|n[ãa]o (é|e) a m[ée]dia das raz[õo]es'
}
Z_SEM_OPERANDO=""
for z_f in $Z_DEFINEM; do
  z_diz_persistidos "$z_f" || Z_SEM_OPERANDO="$Z_SEM_OPERANDO $(basename "$z_f")"
done
[ -z "$Z_SEM_OPERANDO" ]
afirma "z4-operandos-sao-os-desvios-persistidos" $? "sem os operandos=[${Z_SEM_OPERANDO:- nenhum}]"

z_diz_estagio() { z_tem_re "$1" 'arredondado antes|antes de ser persistido|antes de entrar na m[ée]dia'; }
Z_SEM_ESTAGIO=""
for z_f in $Z_DEFINEM; do
  z_diz_estagio "$z_f" || Z_SEM_ESTAGIO="$Z_SEM_ESTAGIO $(basename "$z_f")"
done
[ -z "$Z_SEM_ESTAGIO" ]
afirma "z4b-estagio-do-arredondamento-esta-escrito" $? "sem o estagio=[${Z_SEM_ESTAGIO:- nenhum}]"

z_tem_re "$Z_SCH" 'arredondad[ao] de novo' && z_tem_re "$Z_SCH" 'pela mesma regra'
afirma "z4c-media-e-arredondada-de-novo" $? "o desvio_medio passa pela mesma regra"

# 5. A receita LIDA do contrato, APLICADA a amostra base, da um valor unico — e e 1,16. Trocar
#    casas, desempate ou operandos na documentacao muda este valor e mata o caso.
Z_VALORES=""
for z_f in $Z_DEFINEM; do
  z_c="$(z_casas "$z_f")"; z_d="$(z_desempate "$z_f")"
  z_o=persistidos; z_diz_persistidos "$z_f" || z_o=brutas
  case "$z_c:$z_d" in
    2:hup|1:hup|3:hup|2:hev|1:hev|3:hev) Z_VALORES="$Z_VALORES $(z_calc "$z_c" "$z_d" "$z_o")" ;;
    *) Z_VALORES="$Z_VALORES indefinido" ;;
  esac
done
Z_UNICO="$(printf '%s\n' $Z_VALORES | sort -u | tr '\n' ' ' | sed 's/ $//')"
[ "$Z_UNICO" = "1.16" ]
afirma "z5-um-numero-canonico-sobre-a-mesma-amostra" $? "valores por ponto=[$Z_UNICO] (esperado 1.16)"

# 6. O exemplo canonico do empate esta escrito, com o resultado certo e o errado nomeado: sem o
#    caso trabalhado, "half-up" e uma palavra que cada leitor resolve de um jeito.
Z_SEM_EXEMPLO=""
for z_f in $Z_DEFINEM; do
  grep -qF '1,125' "$z_f" && grep -qF '1,13' "$z_f" || Z_SEM_EXEMPLO="$Z_SEM_EXEMPLO $(basename "$z_f")"
done
[ -z "$Z_SEM_EXEMPLO" ]
afirma "z6-exemplo-canonico-do-empate-presente" $? "sem 1,125 -> 1,13=[${Z_SEM_EXEMPLO:- nenhum}]"
grep -qF '1,12' "$Z_SCH"
afirma "z6b-a-resposta-errada-do-empate-e-nomeada" $? "o schema nomeia 1,12 como o que nao se grava"

# 7. REPRESENTACAO. As duas casas sao FIXAS, nao "ate duas": `1,2` grava-se `1.20` no YAML e
#    escreve-se `1,20` na prosa. Sem isso, o mesmo numero tem duas formas em disco — foi a divisao
#    medida nas amostras (3 escreveram `1.2`, 2 escreveram `1.20`).
Z_SEM_FIXAS=""
for z_f in $Z_DEFINEM; do
  grep -qF '1.20' "$z_f" && grep -qF '1,20' "$z_f" || Z_SEM_FIXAS="$Z_SEM_FIXAS $(basename "$z_f")"
done
[ -z "$Z_SEM_FIXAS" ]
afirma "z7-par-yaml-prosa-do-mesmo-numero-presente" $? "sem o par 1.20/1,20=[${Z_SEM_FIXAS:- nenhum}]"

# 7b. E nenhum valor das chaves da calibracao aparece em disco com uma casa ou com tres: o contrato
#     nao modela a forma que ele proibe. Varre as linhas YAML dos pontos canonicos.
Z_FORA_FORMA="$(grep -rnE '^[[:space:]]*(desvio|desvio_medio|fator_correcao_aplicado):[[:space:]]*[0-9]+(\.[0-9]+)?[[:space:]]*$' \
  $Z_DEFINEM "$Z_TES" | grep -vE ':[[:space:]]*[0-9]+\.[0-9][0-9][[:space:]]*$' | tr '\n' ' ')"
[ -z "$Z_FORA_FORMA" ]
afirma "z7b-nenhum-valor-yaml-fora-de-duas-casas" $? "linhas fora da forma=[${Z_FORA_FORMA:-nenhuma}]"

# 7c. A prosa dos pontos canonicos tambem: o alvo e `1,00` e o exemplo de 40% e `1,40`. `1,0` e
#     o alvo` e a forma de uma casa reaparecendo exatamente onde o leitor aprende o numero. A
#     RAZAO bruta pode ter qualquer numero de casas — ela nao e valor persistido —, e nomear a
#     forma proibida ("nunca `1.2`") e a propria regra; por isso o caso acusa so a prosa que
#     ENSINA o numero, nao toda aparicao de um decimal curto.
Z_PROSA_1CASA="$(grep -rnE '`1[.,][04]`[^`]*(é o alvo|significa que)' $Z_DEFINEM "$Z_TES" | tr '\n' ' ')"
[ -z "$Z_PROSA_1CASA" ]
afirma "z7c-alvo-nunca-ensinado-com-uma-casa" $? "ocorrencias=[${Z_PROSA_1CASA:-nenhuma}]"

# 7e. E a proibicao do fator neutro (DS-46) passa a citar a forma canonica: `1.00`, nao `1.0`.
#     Um contrato que proibe `1.0` modela, na propria proibicao, o valor de uma casa que ele acabou
#     de banir — e e dessa modelagem que a forma errada volta.
Z_NEUTRO_1CASA="$(grep -rnE 'nunca `1\.0`|Nunca `1\.0`' $Z_DEFINEM "$Z_TES" | tr '\n' ' ')"
[ -z "$Z_NEUTRO_1CASA" ]
afirma "z7e-proibicao-do-neutro-na-forma-canonica" $? "ocorrencias=[${Z_NEUTRO_1CASA:-nenhuma}]"
Z_SEM_NEUTRO=""
for z_f in "$Z_SCH" "$Z_EST"; do
  grep -qF 'nunca `1.00`' "$z_f" || grep -qF 'Nunca `1.00`' "$z_f" || Z_SEM_NEUTRO="$Z_SEM_NEUTRO $(basename "$z_f")"
done
[ -z "$Z_SEM_NEUTRO" ]
afirma "z7f-neutro-proibido-com-duas-casas" $? "sem a proibicao em 1.00=[${Z_SEM_NEUTRO:- nenhum}]"
Z_SEM_ALVO=""
for z_f in "$Z_TPL" "$Z_EXE" "$Z_EST"; do
  grep -qF '`1,00`' "$z_f" && grep -qF '`1,40`' "$z_f" || Z_SEM_ALVO="$Z_SEM_ALVO $(basename "$z_f")"
done
[ -z "$Z_SEM_ALVO" ]
afirma "z7d-alvo-e-exemplo-na-forma-canonica" $? "sem 1,00/1,40=[${Z_SEM_ALVO:- nenhum}]"

# 8. CONSUMIDOR. O fator e o `desvio_medio` persistido, aplicado a faixa da task/tipo ANTES da
#    agregacao; floor(min)/ceil(max) a hora inteira continua o ULTIMO passo da faixa agregada.
#    Sem a ordem escrita, o consumidor arredonda em estagio proprio e a faixa publicada muda.
# As duas metades da regra tem de estar na MESMA linha — isto e, no mesmo paragrafo: qual numero e
# o fator, e em que momento ele entra. Conferir arquivo por arquivo nao basta, porque a Passo 5
# tambem fala de "antes da agregacao" para dizer que o fator ja entrou, e essa frase mascarava a
# retirada da regra de onde o consumidor age (o Passo 1). Mutante m8 passava por aqui.
z_diz_fator_antes() {
  [ "$(z_txt "$1" | grep -iE 'antes da agrega[çc][ãa]o|antes de agregar' \
        | grep -ciE 'desvio_medio persistido|fator (é|e) o desvio_medio')" -gt 0 ]
}
Z_SEM_ORDEM=""
for z_f in $Z_CONSOMEM; do
  z_diz_fator_antes "$z_f" || Z_SEM_ORDEM="$Z_SEM_ORDEM $(basename "$z_f")"
done
[ -z "$Z_SEM_ORDEM" ]
afirma "z8-consumidor-aplica-o-fator-antes-da-agregacao" $? "sem a ordem=[${Z_SEM_ORDEM:- nenhum}]"

# Tambem na mesma linha: e o arredondamento A HORA INTEIRA que e o ultimo passo. "ultimo passo"
# solto casaria com qualquer outra frase do arquivo que use a expressao.
[ "$(z_txt "$Z_EST" | grep -iE 'hora inteira' | grep -ciE '[úu]ltimo passo')" -gt 0 ]
afirma "z8b-hora-inteira-e-o-ultimo-passo" $? "floor/ceil a hora inteira e o ultimo passo da faixa"

# 8c. O efeito e observavel: duas tasks `integracao_externa` (o=4 m=5 p=12 e o=3 m=4 p=5) com o
#     fator canonico 1,16 publicam 10–14 h; com o half-even 1,15, 9–14 h. O piso dos `o` tambem
#     recebe o fator, porque o fator entra antes da agregacao.
z_faixa() { # z_faixa <fator> -> "min-max" em horas inteiras
  awk -v f="$1" 'BEGIN {
    mA = (4 + 4*5 + 12)/6; dA = (12 - 4)/6
    mB = (3 + 4*4 +  5)/6; dB = ( 5 - 3)/6
    m = (mA + mB) * f; d = sqrt(dA*dA + dB*dB) * f
    mn = m - d; mx = m + d; piso = (4 + 3) * f
    if (mn < piso) mn = piso
    printf "%d-%d", int(mn), (mx == int(mx) ? mx : int(mx) + 1)
  }'
}
Z_FX_CANON="$(z_faixa "$Z_CANON")"; Z_FX_HEV="$(z_faixa "$Z_HEV")"
[ "$Z_FX_CANON" = "10-14" ] && [ "$Z_FX_HEV" = "9-14" ] && [ "$Z_FX_CANON" != "$Z_FX_HEV" ]
afirma "z8c-fator-canonico-muda-a-faixa-publicada" $? \
  "fator $Z_CANON -> $Z_FX_CANON h; fator $Z_HEV -> $Z_FX_HEV h"

# 8d. O PISO da faixa agregada (DS-163, que estende a DS-41). A DS-41 fixou "min nunca abaixo do
#     melhor caso somado", e o Passo 5 a escrevia com DOIS operandos diferentes: comparava `min`
#     contra "a maior `o` do conjunto" e atribuia "a soma dos `o`". Sao grandezas distintas, e o
#     piso ficava sem definicao justamente onde ha fator de correcao abaixo de 1 — permitido e
#     alcancavel (tipo cujo historico mostra que o projeto estima para cima). A regra canonica tem
#     um operando so, corrigido task a task: piso_conjunto = soma( o(t) * fator(t) ), com
#     fator(t) = 1 quando o tipo da task nao tem fator ativo.
#
# Os detectores de formula leem o texto sem backtick, sem negrito e sem espaco em branco, mas
# PRESERVAM o `*`: aqui o operador de multiplicacao e contrato, nao marcacao. `**` sempre vem em
# par (negrito) e cai antes; `×` e `*` sao a mesma multiplicacao. Assim um mutante de espacamento
# ou de marcacao sobrevive, e um mutante de operando morre.
z_fml() { sed -e 's/\*\*//g' -e 's/`//g' -e 's/×/*/g' -e 's/[[:space:]]//g' "$1"; }
z_fml_tem() { [ "$(z_fml "$1" | grep -cF "$2")" -gt 0 ]; }

Z_PISO_FML='piso_conjunto=soma(o(t)*fator(t))'
Z_PISO_CRU_FML='piso_conjunto=soma(o(t))'
Z_SAN_FML='[soma(o(t)*fator(t)),soma(p(t)*fator(t))]'
Z_SAN_CRU_FML='[somadoso,somadosp]'
# A forma antiga, em prosa: gatilho na maior `o`, atribuicao na soma crua dos `o`.
Z_MAIOR_O_RE='maior .?o.? do conjunto|maior dos .?o.?|soma dos .?o.? como piso|piso: soma dos .?o.?'
# Nomear a forma recusada nao e prescreve-la (mesmo cuidado da z2 e da y8): a linha que traz o
# token tem de estar livre de marca de recusa para contar como prescricao.
Z_RECUSA_PISO_RE="$Z_RECUSA_RE|publica|fracion|reprova|viraria|deixam? o piso sem|grandezas diferentes"
z_prescreve_maior_o() {
  local tot rec
  tot="$(z_conta "$1" "$Z_MAIOR_O_RE")"
  rec="$(z_txt "$1" | grep -iE "$Z_MAIOR_O_RE" | grep -ciE "$Z_RECUSA_PISO_RE")"
  [ "$tot" -gt 0 ] && [ "$rec" -lt "$tot" ]
}
z_piso_lido() { # z_piso_lido <arquivo> -> corrigido | cru | contraditorio | indefinido
  local f=1 g=1 a=1 w=1
  z_fml_tem "$1" "$Z_PISO_FML" && f=0
  # O gatilho compara e atribui o MESMO operando, na mesma linha: `min < piso_conjunto` entao
  # `min = piso_conjunto`. Conferir so a formula nao basta — era exatamente o par comparacao/
  # atribuicao que divergia.
  [ "$(z_fml "$1" | grep -cE 'min<piso_conjunto.*min=piso_conjunto')" -gt 0 ] && g=0
  z_fml_tem "$1" "$Z_PISO_CRU_FML" && a=0
  z_prescreve_maior_o "$1" && w=0
  if   [ $w -eq 0 ];                   then printf 'contraditorio'
  elif [ $f -eq 0 ] && [ $g -eq 0 ];   then printf 'corrigido'
  elif [ $a -eq 0 ];                   then printf 'cru'
  else printf 'indefinido'; fi
}
Z_PISO_FORA=""
for z_f in $Z_CONSOMEM; do
  z_p="$(z_piso_lido "$z_f")"
  [ "$z_p" = corrigido ] || Z_PISO_FORA="$Z_PISO_FORA $(basename "$z_f"):$z_p"
done
[ -z "$Z_PISO_FORA" ]
afirma "z8d-piso-e-a-soma-dos-o-corrigidos-por-task" $? "fora do piso canonico=[${Z_PISO_FORA:- nenhum}]"

# 8e. Reference e template dizem a MESMA regra. O template e o que o executor copia; contrato que
#     mora so na reference vira faixa publicada por um arquivo e nao pelo outro.
Z_NEUTRO_FORA=""
for z_f in $Z_CONSOMEM; do
  z_tem_re "$z_f" 'fator\(t\) *= *1($|[^0-9.])' || Z_NEUTRO_FORA="$Z_NEUTRO_FORA $(basename "$z_f")"
done
[ -z "$Z_NEUTRO_FORA" ]
afirma "z8e-fator-neutro-por-task-declarado" $? "sem fator(t)=1=[${Z_NEUTRO_FORA:- nenhum}]"

# 8f. O CLAMP vem antes do arredondamento a hora inteira, e as duas metades na mesma linha: qual
#     estagio, e de que arredondamento se fala. Pisar depois de arredondar publica `min`
#     fracionario (3,20 h no caso vinculante), e a faixa publicada e em hora inteira.
z_clamp_antes() {
  [ "$(z_txt "$1" | grep -iE 'antes d(o|e) (floor|arredond)' | grep -ciE 'hora inteira|floor\(min\)')" -gt 0 ]
}
z_prescreve_clamp_depois() {
  local tot rec
  tot="$(z_conta "$1" 'depois d(o|e) (floor|arredond)')"
  rec="$(z_txt "$1" | grep -iE 'depois d(o|e) (floor|arredond)' | grep -ciE "$Z_RECUSA_PISO_RE")"
  [ "$tot" -gt 0 ] && [ "$rec" -lt "$tot" ]
}
Z_CLAMP_FORA=""
for z_f in $Z_CONSOMEM; do
  z_clamp_antes "$z_f" || Z_CLAMP_FORA="$Z_CLAMP_FORA $(basename "$z_f"):sem-antes"
  z_prescreve_clamp_depois "$z_f" && Z_CLAMP_FORA="$Z_CLAMP_FORA $(basename "$z_f"):prescreve-depois"
done
[ -z "$Z_CLAMP_FORA" ]
afirma "z8f-clamp-antes-do-arredondamento" $? "fora do estagio=[${Z_CLAMP_FORA:- nenhum}]"

# 8g. A SANIDADE do Passo 5 e do checklist usa os limites corrigidos task a task. Com fator abaixo
#     de 1, o intervalo bruto reprova conta certa: no caso vinculante, min=3,7333 fica FORA de
#     [4, 12] e dentro de [3,20, 9,60]. Verificacao que reprova o certo manda refazer o que estava
#     pronto, e quem refaz converge para o numero errado.
z_sanidade_lida() { # z_sanidade_lida <arquivo> -> corrigida | crua | ambas | nenhuma
  local c=1 b=1
  z_fml_tem "$1" "$Z_SAN_FML" && c=0
  z_fml_tem "$1" "$Z_SAN_CRU_FML" && b=0
  if   [ $c -eq 0 ] && [ $b -eq 0 ]; then printf 'ambas'
  elif [ $c -eq 0 ];                 then printf 'corrigida'
  elif [ $b -eq 0 ];                 then printf 'crua'
  else printf 'nenhuma'; fi
}
Z_SAN_FORA=""
for z_f in $Z_CONSOMEM; do
  z_s="$(z_sanidade_lida "$z_f")"
  [ "$z_s" = corrigida ] || Z_SAN_FORA="$Z_SAN_FORA $(basename "$z_f"):$z_s"
done
[ -z "$Z_SAN_FORA" ]
afirma "z8g-sanidade-usa-o-intervalo-corrigido" $? "fora do intervalo corrigido=[${Z_SAN_FORA:- nenhum}]"

# 8h. Dados literais que SEPARAM as leituras do piso, no caso vinculante: uma task `api`
#     o=4 m=5 p=12 com o fator 0,80 do seu tipo. Media corrigida 4,80, desvio corrigido 1,0667,
#     min cru 3,7333, max 5,8667. Piso corrigido 4 × 0,80 = 3,20, que 3,7333 nao fura: faixa
#     publicada 3–6 h. Com o piso bruto (soma dos `o` sem fator, 4) o min e pisado em 4 e a faixa
#     viraria 4–6 h — uma hora de esforco na base da faixa que o metodo nao calculou. Pisando
#     depois do arredondamento, o min publicado e 3,2: nem hora inteira.
z_faixa_t() { # z_faixa_t <piso:corrigido|cru|maior_o> <clamp:antes|depois> <fator_global|-> <o,m,p,fator>...
  local piso="$1" clamp="$2" fg="$3"; shift 3
  printf '%s\n' "$@" | awk -F, -v piso="$piso" -v clamp="$clamp" -v fg="$fg" '
    { o=$1; m=$2; p=$3; f=(fg == "-" ? $4 : fg)
      M += (o + 4*m + p)/6 * f; v = (p - o)/6 * f; V += v*v
      soc += o*f; so += o; if (o > mo) mo = o }
    END {
      d = sqrt(V); mn = M - d; mx = M + d
      ps = (piso == "corrigido" ? soc : (piso == "cru" ? so : mo))
      fmx = (mx == int(mx) ? mx : int(mx) + 1)
      if (clamp == "antes") { if (mn < ps) mn = ps; fmn = int(mn) }
      else { fmn = int(mn); if (fmn < ps) fmn = ps }
      printf "%g-%g", fmn, fmx
    }'
}
Z_CASO_API='4,5,12,0.80'
Z_FX_PISO_OK="$(z_faixa_t corrigido antes - $Z_CASO_API)"
Z_FX_PISO_CRU="$(z_faixa_t cru antes - $Z_CASO_API)"
Z_FX_PISO_TARDE="$(z_faixa_t corrigido depois - $Z_CASO_API)"
[ "$Z_FX_PISO_OK" = "3-6" ] && [ "$Z_FX_PISO_CRU" = "4-6" ] && [ "$Z_FX_PISO_TARDE" = "3.2-6" ] \
  && [ "$Z_FX_PISO_OK" != "$Z_FX_PISO_CRU" ] && [ "$Z_FX_PISO_OK" != "$Z_FX_PISO_TARDE" ]
afirma "z8h-dados-separam-as-leituras-do-piso" $? \
  "corrigido=$Z_FX_PISO_OK cru=$Z_FX_PISO_CRU pisado-depois=$Z_FX_PISO_TARDE"

# 8i. A receita e LIDA de cada ponto que consome o fator e aplicada ao caso vinculante: o conjunto
#     dos resultados tem de ser {3-6}. Era {indefinido} — o contrato nao respondia qual operando.
Z_FX_PISO=""
for z_f in $Z_CONSOMEM; do
  case "$(z_piso_lido "$z_f")" in
    corrigido) Z_FX_PISO="$Z_FX_PISO $(z_faixa_t corrigido antes - $Z_CASO_API)" ;;
    cru)       Z_FX_PISO="$Z_FX_PISO $(z_faixa_t cru antes - $Z_CASO_API)" ;;
    *)         Z_FX_PISO="$Z_FX_PISO indefinido" ;;
  esac
done
Z_FX_PISO_UNICO="$(printf '%s\n' $Z_FX_PISO | sort -u | tr '\n' ' ' | sed 's/ $//')"
[ "$Z_FX_PISO_UNICO" = "3-6" ]
afirma "z8i-faixa-canonica-do-caso-vinculante" $? "faixa por ponto=[$Z_FX_PISO_UNICO] (esperado 3-6)"

# 8j. CONJUNTO MISTO: o fator e por task, nunca um fator global do conjunto. `api` o=4 m=5 p=12
#     com fator 0,80 mais `ui` o=3 m=4 p=5 sem fator ativo (fator 1) publicam 7–10 h. Aplicar
#     0,80 ao conjunto inteiro publica 6–10 h; ignorar o fator publica 8–12 h. Tres faixas
#     diferentes do mesmo plano, e so uma sai da regra.
Z_CASO_MISTO="4,5,12,0.80 3,4,5,1"
Z_FX_MISTO_T="$(z_faixa_t corrigido antes - $Z_CASO_MISTO)"
Z_FX_MISTO_G="$(z_faixa_t corrigido antes 0.80 $Z_CASO_MISTO)"
Z_FX_MISTO_N="$(z_faixa_t corrigido antes 1 $Z_CASO_MISTO)"
[ "$Z_FX_MISTO_T" = "7-10" ] && [ "$Z_FX_MISTO_G" = "6-10" ] && [ "$Z_FX_MISTO_N" = "8-12" ] \
  && [ "$Z_FX_MISTO_T" != "$Z_FX_MISTO_G" ] && [ "$Z_FX_MISTO_T" != "$Z_FX_MISTO_N" ]
afirma "z8j-conjunto-misto-usa-o-fator-de-cada-task" $? \
  "por task=$Z_FX_MISTO_T global=$Z_FX_MISTO_G sem fator=$Z_FX_MISTO_N"

# 8k. E a sanidade do mesmo caso: o intervalo corrigido aprova a conta certa, o bruto a reprova.
z_sanidade_aplica() { # z_sanidade_aplica <corrigido|cru> <o,m,p,fator>... -> aprova | reprova
  local lim="$1"; shift
  printf '%s\n' "$@" | awk -F, -v lim="$lim" '
    { o=$1; m=$2; p=$3; f=$4
      M += (o + 4*m + p)/6 * f; v = (p - o)/6 * f; V += v*v
      soc += o*f; spc += p*f; so += o; sp += p }
    END {
      d = sqrt(V); lo = (lim == "corrigido" ? soc : so); hi = (lim == "corrigido" ? spc : sp)
      printf "%s", (M - d >= lo && M + d <= hi) ? "aprova" : "reprova"
    }'
}
Z_SAN_OK="$(z_sanidade_aplica corrigido $Z_CASO_API)"
Z_SAN_CRU="$(z_sanidade_aplica cru $Z_CASO_API)"
[ "$Z_SAN_OK" = aprova ] && [ "$Z_SAN_CRU" = reprova ]
afirma "z8k-intervalo-bruto-reprovaria-a-conta-certa" $? \
  "corrigido=$Z_SAN_OK bruto=$Z_SAN_CRU (min 3,7333 fora de [4, 12])"

# 8k2. DS-169: a sanidade e sobre o decimal do Passo 5 (pos-piso, pre-arredondamento), nunca
#      sobre a faixa PUBLICADA (ja arredondada a hora inteira por floor/ceil). floor/ceil
#      arredonda para FORA (alarga), entao a faixa publicada pode deixar de estar contida no
#      intervalo corrigido mesmo numa conta certa — no caso Z_CASO_API, publicada "3-6 h" contra
#      corrigido "[3,20, 9,60]": 3 nao fica acima de 3,20. O par abaixo mostra as duas leituras
#      do MESMO caso: so a decimal aprova; a publicada reprovaria, e e exatamente por isso que o
#      contrato tem de nomear qual das duas vale.
z_sanidade_publicada() { # z_sanidade_publicada <faixa "min-max"> <soc> <spc> -> aprova | reprova
  local fx="$1" soc="$2" spc="$3" fmn fmx
  fmn="${fx%-*}"; fmx="${fx#*-}"
  awk -v fmn="$fmn" -v fmx="$fmx" -v soc="$soc" -v spc="$spc" \
    'BEGIN { printf "%s", (fmn > soc && fmx < spc) ? "aprova" : "reprova" }'
}
Z_SAN_PUB="$(z_sanidade_publicada "$Z_FX_PISO_OK" 3.20 9.60)"
[ "$Z_SAN_OK" = aprova ] && [ "$Z_SAN_PUB" = reprova ]
afirma "z8k2a-decimal-aprova-publicada-reprovaria-o-mesmo-caso" $? \
  "decimal(Z_SAN_OK, de 8k)=$Z_SAN_OK publicada($Z_FX_PISO_OK)=$Z_SAN_PUB"

# O paragrafo da verificacao (07-estimativa.md) tem de nomear o estagio explicitamente: cita o
# Passo 5, o arredondamento/floor do Passo 6, e adverte contra comparar com a faixa publicada.
Z_SAN_TXT="$(grep -F 'Verificação obrigatória de sanidade' "$Z_EST")"
z_tem_822() { printf '%s' "$Z_SAN_TXT" | grep -qi "$1"; }
z_tem_822 'Passo 5'; Z_822_P5=$?
z_tem_822 'floor'; Z_822_FLOOR=$?
z_tem_822 'publicada'; Z_822_PUB=$?
[ -n "$Z_SAN_TXT" ] && [ "$Z_822_P5" -eq 0 ] && [ "$Z_822_FLOOR" -eq 0 ] && [ "$Z_822_PUB" -eq 0 ]
afirma "z8k2b-paragrafo-nomeia-o-estagio-decimal-vs-publicada" $? \
  "Passo5=$Z_822_P5 floor=$Z_822_FLOOR publicada=$Z_822_PUB (0=presente)"

# O item do checklist do Passo 5 repete a mesma regra, pelo mesmo motivo que a DS-160/DS-163 ja
# valem para dois pontos canonicos: quem le so o checklist nao pode reproduzir o erro antigo.
Z_CHK_LINHA="$(grep -F 'contido em' "$Z_EST")"
printf '%s' "$Z_CHK_LINHA" | grep -qi 'decimal'; Z_CHK_DEC=$?
printf '%s' "$Z_CHK_LINHA" | grep -qi 'publicada'; Z_CHK_PUB=$?
[ -n "$Z_CHK_LINHA" ] && [ "$Z_CHK_DEC" -eq 0 ] && [ "$Z_CHK_PUB" -eq 0 ]
afirma "z8k2c-checklist-nomeia-o-estagio-decimal-vs-publicada" $? \
  "linha=[$Z_CHK_LINHA]"

# A decisao esta registrada, append-only, e estende a DS-163 (mesmo piso, novo estagio de leitura).
Z_DS169="$(grep -F '| DS-169 |' "$Z_DS")"
[ -n "$Z_DS169" ]
afirma "z8k2d-ds169-registrada" $? "a decisao da sanidade decimal existe no registro"
printf '%s' "$Z_DS169" | grep -qF 'DS-163'; z_rc=$?
afirma "z8k2e-ds169-declara-que-estende-ds163" "$z_rc" "DS-169 nomeia a DS-163 que ela estende"

# 8k3. A celula do placeholder "Fator ativo?" tem um `|` literal dentro do texto condicional
#      ("...x{{desvio}} | nao..."). Markdown le qualquer `|` fora de code span como separador de
#      coluna — esse pipe tem de vir escapado (`\|`), senao a linha de dados renderiza com uma
#      coluna a mais e corrompe a tabela. Conta os pipes QUE SEPARAM coluna (a substituicao via
#      parametro do bash, nao sed, porque `\|` em BRE do GNU sed e alternancia, nao literal):
#      a linha Markdown tem pipe inicial e final alem dos separadores entre colunas: o cabecalho
#      de 4 colunas tem 5 pipes (NF=6 por awk -F'|'); a linha de dados, com o pipe interno
#      escapado, tem de dar o mesmo NF=6 depois de neutralizar o `\|` escapado.
Z_TPL_CABECALHO="$(grep -F 'Tipo de task' "$Z_TPL")"
Z_TPL_CAMPOS_CABECALHO="$(printf '%s' "$Z_TPL_CABECALHO" | awk -F'|' '{print NF}')"
Z_TPL_LINHA_DADOS="$(grep -F '{{tipo_task}} | {{n}}' "$Z_TPL")"
Z_TPL_SEM_ESCAPE="${Z_TPL_LINHA_DADOS//\\|/@PIPE_ESCAPADO@}"
Z_TPL_CAMPOS_DADOS="$(printf '%s' "$Z_TPL_SEM_ESCAPE" | awk -F'|' '{print NF}')"
[ "$Z_TPL_CAMPOS_DADOS" -eq "$Z_TPL_CAMPOS_CABECALHO" ]
afirma "z8k3-pipe-interno-da-celula-fator-ativo-esta-escapado" $? \
  "linha=[$Z_TPL_LINHA_DADOS] campos(pipes separadores, pipe interno neutralizado)=$Z_TPL_CAMPOS_DADOS cabecalho=$Z_TPL_CAMPOS_CABECALHO"
Z_DS170="$(grep -F '| DS-170 |' "$Z_DS")"
[ -n "$Z_DS170" ]
afirma "z8k3a-ds170-registrada" $? "a decisao do escape do pipe existe no registro"

# 8k4. Mutantes que RESTAURAM cada defeito corrigido nesta secao, numa COPIA da skill — a arvore
#      real nunca e tocada — e tem de morrer exatamente pelo caso nomeado.
ZM_A="$(mktemp -d)"; cp -R "$SK/." "$ZM_A/"
sed -i 's/×{{desvio}} \\| não/×{{desvio}} | não/' "$ZM_A/assets/TEMPLATE-HISTORICO.md"
! cmp -s "$Z_TPL" "$ZM_A/assets/TEMPLATE-HISTORICO.md"; Z_MA_GEROU=$?
ZM_A_LINHA="$(grep -F '{{tipo_task}} | {{n}}' "$ZM_A/assets/TEMPLATE-HISTORICO.md")"
ZM_A_SEM_ESCAPE="${ZM_A_LINHA//\\|/@PIPE_ESCAPADO@}"
ZM_A_CAMPOS="$(printf '%s' "$ZM_A_SEM_ESCAPE" | awk -F'|' '{print NF}')"
[ "$Z_MA_GEROU" -eq 0 ] && [ "$ZM_A_CAMPOS" -ne "$Z_TPL_CAMPOS_CABECALHO" ]
afirma "z8k4a-mutante-reintroduz-pipe-sem-escape-morto-por-z8k3" $? \
  "mutacao gerada=$Z_MA_GEROU campos apos mutacao=$ZM_A_CAMPOS (esperado != $Z_TPL_CAMPOS_CABECALHO)"

ZM_B="$(mktemp -d)"; cp -R "$SK/." "$ZM_B/"
python3 - "$ZM_B/references/07-estimativa.md" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
novo_par = ("**Verificação obrigatória de sanidade:** a checagem é sobre o `[min, max]` do Passo 5 "
    "— decimal, com o fator de cada task e o `piso_conjunto` já aplicados, mas **antes** do "
    "arredondamento à hora inteira do Passo 6 — e esse intervalo tem de estar **contido** em "
    "`[ soma( o(t) * fator(t) ), soma( p(t) * fator(t) ) ]`, os limites corrigidos task a task "
    "pelos mesmos fatores que entraram na agregação. Se não estiver, você errou a conta — refaça. "
    "Comparar com o intervalo bruto (sem fator) reprova conta certa sempre que algum fator é "
    "abaixo de 1: no exemplo acima, o `min` decimal e já pisado `3,7333` fica fora de `[4, 12]` e "
    "dentro de `[3,20, 9,60]`. Nunca compare essa sanidade contra a faixa **publicada** — já "
    "arredondada por `floor(min)`/`ceil(max)` à hora inteira: o arredondamento alarga a faixa para "
    "fora, nunca para dentro, então a publicada pode deixar de estar contida no intervalo "
    "corrigido mesmo numa conta certa — no mesmo exemplo ela é `3–6 h`, e `3` não fica acima de "
    "`3,20`. A sanidade é sempre sobre o decimal do Passo 5, nunca sobre o arredondado do Passo 6.")
velho_par = ("**Verificação obrigatória de sanidade:** a faixa agregada de qualquer conjunto tem "
    "de ser **mais estreita** que `[ soma( o(t) * fator(t) ), soma( p(t) * fator(t) ) ]` — os "
    "limites corrigidos task a task, pelos mesmos fatores que entraram na agregação. Se não for, "
    "você errou a conta — refaça. Comparar com o intervalo bruto reprova conta certa sempre que "
    "algum fator é abaixo de 1: no exemplo acima, `min` `3,7333` fica fora de `[4, 12]` e dentro "
    "de `[3,20, 9,60]`.")
assert novo_par in s, "paragrafo corrigido nao encontrado — ajuste o mutante"
s = s.replace(novo_par, velho_par)
novo_chk = ("- [ ] O `[min, max]` decimal do Passo 5 — já com o fator por task e o piso "
    "`piso_conjunto` aplicados, ainda antes do arredondamento à hora inteira do Passo 6 — está "
    "contido em `[ soma( o(t) * fator(t) ), soma( p(t) * fator(t) ) ]` (senão a quadratura foi "
    "feita errado). Nunca compare a faixa já publicada, em hora inteira, contra esse intervalo "
    "decimal — o arredondamento alarga a faixa e reprovaria conta certa.")
velho_chk = ("- [ ] A faixa agregada é mais estreita que `[ soma( o(t) * fator(t) ), soma( p(t) * "
    "fator(t) ) ]` (senão a quadratura foi feita errado), e o piso aplicado a `min` foi "
    "`piso_conjunto`, antes do arredondamento à hora inteira.")
assert novo_chk in s, "checklist corrigido nao encontrado — ajuste o mutante"
s = s.replace(novo_chk, velho_chk)
open(p, "w", encoding="utf-8").write(s)
PYEOF
Z_MB_RC=$?
! cmp -s "$Z_EST" "$ZM_B/references/07-estimativa.md"; Z_MB_GEROU=$?
ZM_B_SAN_TXT="$(grep -F 'Verificação obrigatória de sanidade' "$ZM_B/references/07-estimativa.md")"
printf '%s' "$ZM_B_SAN_TXT" | grep -qi 'publicada'; ZM_B_PAR_PUB=$?
ZM_B_CHK_LINHA="$(grep -F 'estreita' "$ZM_B/references/07-estimativa.md" | grep -F '- [ ]')"
printf '%s' "$ZM_B_CHK_LINHA" | grep -qi 'decimal'; ZM_B_CHK_DEC=$?
[ "$Z_MB_RC" -eq 0 ] && [ "$Z_MB_GEROU" -eq 0 ] && [ "$ZM_B_PAR_PUB" -ne 0 ] && [ "$ZM_B_CHK_DEC" -ne 0 ]
afirma "z8k4b-mutante-reverte-sanidade-para-faixa-publicada-morto-por-z8k2" $? \
  "geracao rc=$Z_MB_RC mudou=$Z_MB_GEROU paragrafo cita publicada=$ZM_B_PAR_PUB checklist cita decimal=$ZM_B_CHK_DEC"

# 8l. A decisao esta registrada e e APPEND-ONLY: DS-163 entra estendendo a DS-41, e a DS-41 fica
#     byte a byte como estava. Reescrever uma decisao antiga apaga o rastro de por que a nova
#     existe — e o registro e onde a proxima sessao encontra o porque.
Z_DS163="$(grep -F '| DS-163 |' "$Z_DS")"
[ -n "$Z_DS163" ]
afirma "z8l-ds163-registrada" $? "a decisao do piso existe no registro"
[ "$(printf '%s' "$Z_DS163" | grep -cF 'DS-41')" -gt 0 ]; z_rc=$?
afirma "z8m-ds163-declara-que-estende-ds41" "$z_rc" "DS-163 nomeia a DS-41 que ela estende"
Z_DS163_F="$W/.z-ds163"; printf '%s\n' "$Z_DS163" > "$Z_DS163_F"
z_fml_tem "$Z_DS163_F" "$Z_PISO_FML"
afirma "z8n-ds163-traz-a-formula-do-piso" $? "DS-163 escreve $Z_PISO_FML"

# A DS-41 intacta: conteudo e tamanho conferidos pelo cksum da propria linha (376 bytes, a linha
# com o \n do grep). Qualquer reescrita, ate de uma virgula, muda o par.
Z_DS41_CK_ESPERADO='2616782449 376'
Z_DS41_CK="$(grep -F '| DS-41 |' "$Z_DS" | cksum)"
[ "$(grep -cF '| DS-41 |' "$Z_DS")" -eq 1 ] && [ "$Z_DS41_CK" = "$Z_DS41_CK_ESPERADO" ]
afirma "z8o-ds41-permanece-byte-a-byte" $? "cksum=[$Z_DS41_CK] esperado=[$Z_DS41_CK_ESPERADO]"

# 9. A decisao esta registrada: DS-160 fixa a receita, e o registro e onde a proxima sessao
#    encontra o PORQUE — sem ele, a convencao volta a ser escolha de quem executa.
Z_DS160="$(grep -F '| DS-160 |' "$Z_DS")"
[ -n "$Z_DS160" ]
afirma "z9-ds160-registrada" $? "a decisao da precisao existe no registro"
[ "$(printf '%s' "$Z_DS160" | grep -ciE 'half-up|meio para cima')" -gt 0 ]; z_rc=$?
afirma "z9b-ds160-fixa-o-desempate" "$z_rc" "DS-160 diz half-up"
[ "$(printf '%s' "$Z_DS160" | grep -ciE 'duas casas')" -gt 0 ]; z_rc=$?
afirma "z9c-ds160-fixa-as-casas" "$z_rc" "DS-160 diz duas casas"

# 10. A chave e o schema nao mudam: a correcao e da precisao do valor, nao do formato. Nenhum
#     parser afetado, nenhuma chave nova, e `desvio`/`desvio_medio` continuam numeros no YAML
#     (nunca string com casas embutidas, que e como se fabrica "duas casas" a forca).
grep -qF 'desvio_medio:' "$Z_SCH" && grep -qF 'desvio_medio:' "$Z_TPL"
afirma "z10-chaves-preservadas" $? "desvio e desvio_medio continuam as chaves"
Z_STRINGS="$(grep -rnE '^[[:space:]]*(desvio|desvio_medio|fator_correcao_aplicado):[[:space:]]*["'"'"']' \
  $Z_DEFINEM "$Z_TES" | tr '\n' ' ')"
[ -z "$Z_STRINGS" ]
afirma "z10b-nenhum-valor-virou-string" $? "ocorrencias=[${Z_STRINGS:-nenhuma}]"

echo "== AA. o status da condicao chega inteiro a \`afirma\`, mesmo com nome dinamico (D-12) =="
# `afirma <nome> <status> <detalhe>` nao avalia condicao nenhuma: recebe o status JA avaliado.
# Numa chamada escrita como `condicao; afirma "nome-$(cmd)" $? "detalhe"` o shell expande as
# palavras da esquerda para a direita, entao a substituicao que monta o NOME roda ANTES de `$?`
# ser expandido — e `$?` passa a ser o status dessa substituicao, nao o da condicao. Como
# `printf`/`tr`/`basename` sempre terminam em 0, a assercao inteira vira "ok" incondicional:
# sete casos de orcamento invalido, seis de produto staged, sete de instrucao unica, seis de
# recusa do revisor, dois de tabela do agente e catorze do escritor do rastro (treze sem `jq`) —
# 42 assercoes que nao podiam reprovar. Nem aritmetica (`$((...))`) nem expansao de parametro (`${v//a/b}`) mexem
# no status; so substituicao de comando (`$(...)` ou crase), e so quando vem ANTES do `$?`.
# Forma canonica (DS-161): derive o nome ANTES, capture o status imediatamente depois da
# condicao, e passe por variavel — `nome=...; condicao; rc=$?; afirma "$nome" "$rc" ...`.
# Trocar a ordem sem capturar na hora nao resolve: qualquer comando entre a condicao e `rc=$?`
# (inclusive a propria derivacao do nome) rouba o status do mesmo jeito. Por isso esta secao tem
# DOIS oraculos independentes: um guarda estatico, que acha a forma vulneravel por aninhamento,
# e um replay em runtime, que recorta do proprio arquivo o grupo de comandos de cada familia,
# forca a condicao a falsa e confere o status que `afirma` recebeu de verdade.
AA_BANC="$H/testes/bancada.sh"
AA_T="$(mktemp -d)"

# --- oraculo 1: guarda estatico ----------------------------------------------
# Toda leitura de `$?` feita num comando simples que JA executou uma substituicao de comando.
# Caminha caractere a caractere porque a forma nao e reconhecivel por expressao regular: depende
# de aspas simples e duplas, de aninhamento equilibrado de `$( )` (que pode conter `;` e `)`),
# de crase, de comentario, de corpo de heredoc e de onde o comando simples comeca.
aa_vulneraveis() { # aa_vulneraveis <script> -> "<linha>:<texto>" por ocorrencia
  awk '
  BEGIN { Q = sprintf("%c", 39); BT = sprintf("%c", 96); ASPAS = "[\"" Q "]"
          CHAVE = "^(do|then|else|elif|in|while|until|if|case|esac|fi|done|function)([ \t;&|]|$)" }
  {
    if (hd != "") { t = $0; sub(/^[ \t]+/, "", t); if (t == hd) hd = ""; next }
    L = $0; n = length(L); i = 1
    while (i <= n) {
      c = substr(L, i, 1); c2 = substr(L, i, 2); c3 = substr(L, i, 3)
      if (pd > 0) {                                    # corpo de $( ): so procura o fim
        if (psq)              { if (c == Q) psq = 0; i++; continue }
        if (c == "\\")        { i += 2; continue }
        if (c == Q && !pdq)   { psq = 1; i++; continue }
        if (c == "\"")        { pdq = !pdq; i++; continue }
        if (!pdq && c == "(") { pd++; i++; continue }
        if (!pdq && c == ")") { pd--; i++; continue }
        i++; continue
      }
      if (bt)              { if (c == "\\") { i += 2; continue } if (c == BT) bt = 0; i++; continue }
      if (sq)              { if (c == Q) sq = 0; i++; continue }
      if (c == "\\")       { i += 2; continue }
      if (c == Q && !dq)   { sq = 1; i++; continue }
      if (c == "\"")       { dq = !dq; i++; continue }
      if (c3 == "$((")     { i = aa_par(L, i + 1, n); continue }   # aritmetica nao mexe no status
      if (c2 == "$(")      { subst = 1; pd = 1; psq = 0; pdq = 0; i += 2; continue }
      if (c == BT)         { subst = 1; bt = 1; i++; continue }
      if (c2 == "$?")      { if (subst) printf "%d:%s\n", FNR, $0; i += 2; continue }
      if (c2 == "${")      { bd++; i += 2; continue }              # `}` de expansao nao e separador
      if (c == "}" && bd)  { bd--; i++; continue }
      if (dq)              { i++; continue }
      if (c == "#" && (i == 1 || substr(L, i - 1, 1) ~ /[ \t;&|(){}]/)) break
      if (c2 == "<<") {
        r = substr(L, i + 2); sub(/^-/, "", r); sub(/^[ \t]+/, "", r)
        if (match(r, "^" ASPAS "[A-Za-z_][A-Za-z_0-9]*" ASPAS) || match(r, "^[A-Za-z_][A-Za-z_0-9]*")) {
          hd = substr(r, RSTART, RLENGTH); gsub(ASPAS, "", hd); subst = 0; next
        }
        i += 2; continue
      }
      if (c ~ /[;&|(){}]/) { subst = 0; i++; continue }
      if (c ~ /[A-Za-z_]/ && (i == 1 || substr(L, i - 1, 1) ~ /[ \t;&|(){}]/) && match(substr(L, i), CHAVE)) { subst = 0; i += RLENGTH; continue }
      i++
    }
    if (pd == 0 && !bt && !sq && L !~ /\\$/) { subst = 0; bd = 0 }  # fim de linha fecha o comando
  }
  function aa_par(s, j, m,   d, k) { d = 0
    while (j <= m) { k = substr(s, j, 1); if (k == "(") d++; else if (k == ")") { d--; if (d == 0) return j + 1 } j++ }
    return j }
  ' "$1"
}
aa_guarda_cega()  { :; }                       # mutante do oraculo: nunca acusa
aa_guarda_tudo()  { grep -nF '$?' "$1"; }      # mutante do oraculo: acusa qualquer `$?`

# --- oraculo 2: replay em runtime --------------------------------------------
# Recorta do PROPRIO arquivo o grupo de comandos da familia — da primeira linha que carrega a
# expressao do nome dinamico ate a linha do `afirma` que a consome — e roda esse trecho verbatim
# com a condicao forcada a falsa e um `afirma` que so captura o status recebido. Prova
# comportamento, nao texto: se o grupo voltar a perder o status (por substituicao antes do `$?`,
# por comando no meio, ou por `$?` lido depois do `rc=$?`), o status capturado vira 0.
aa_bloco() { # aa_bloco <script> <literal do nome dinamico> -> o grupo, verbatim
  awk -v lit="$2" 'index($0, lit) { achou = 1 }
                   achou { print; if (index($0, "afirma ")) exit }' "$1"
}
aa_replay() { # aa_replay <script> <literal do nome> <prelude> -> status que `afirma` recebeu
  local b
  b="$(aa_bloco "$1" "$2")"
  [ -n "$b" ] || { printf 'BLOCO-VAZIO'; return; }
  : > "$AA_T/cap"
  { printf 'afirma() { printf %%s "$2" > %s/cap; }\n' "$AA_T"
    printf '%s\nfalse\n%s\n' "$3" "$b"; } > "$AA_T/replay.sh"
  bash "$AA_T/replay.sh" >/dev/null 2>&1
  cat "$AA_T/cap"
}
aa_preserva() { # aa_preserva <status capturado> -> 0 se a condicao falsa chegou como nao-zero
  case "$1" in [1-9] | [1-9][0-9]*) return 0 ;; *) return 1 ;; esac
}

# 1. Runtime, antes de olhar o harness: a forma canonica entrega o status da condicao, e a forma
#    vulneravel realmente o perde. O segundo caso e o que impede o primeiro de passar de graca —
#    sem ele, nao estariamos testando problema nenhum.
#    A sonda vive num arquivo gerado, nunca aqui dentro: a forma vulneravel escrita no proprio
#    harness seria acusada pelo guarda do item 2 — e um guarda com excecao convida ao abuso.
cat > "$AA_T/sonda.sh" <<'AA_SONDA'
eco() { printf '%s' "$2"; }
canonica()   { local n r; n="aa-$(printf abc)"; false; r=$?; printf '%s' "$r"; }
vulneravel() { false; eco "aa-$(printf abc)" $?; }
printf '%s %s' "$(canonica)" "$(vulneravel)"
AA_SONDA
AA_SONDA="$(bash "$AA_T/sonda.sh")"
[ "${AA_SONDA% *}" = 1 ]; aa_rc=$?
afirma "aa1-condicao-falsa-chega-nao-zero-com-nome-dinamico" "$aa_rc" "nome derivado antes, status por variavel -> rc=${AA_SONDA% *}"
[ "${AA_SONDA#* }" = 0 ]; aa_rc=$?
afirma "aa1b-a-forma-vulneravel-realmente-perde-o-status" "$aa_rc" "substituicao no nome antes de \$? -> rc=${AA_SONDA#* }, a condicao do defeito existe"

# 2. O harness inteiro esta livre da forma — nao so as seis familias conhecidas.
AA_VUL="$(aa_vulneraveis "$AA_BANC" | tr '\n' ' ')"
[ -z "$AA_VUL" ]; aa_rc=$?
afirma "aa2-nenhuma-chamada-vulneravel-no-harness" "$aa_rc" "${AA_VUL:-nenhuma leitura de \$? depois de substituicao}"

# 3. Auto-teste do guarda: cada forma vulneravel tem de ser acusada e cada forma segura tem de
#    passar. Um guarda cego passaria no item 2 sem enxergar nada; um guarda que acusa todo `$?`
#    tambem "passaria" se a bancada nao cobrasse os negativos.
aa_caso() { printf '%s\n' "$2" > "$AA_T/$1.sh"; }
aa_caso p1 'false; f "n-$(printf x)" $? d'
aa_caso p2 'false; f "n-`printf x`" $? d'
aa_caso p3 'false; f "n-$(echo a; echo b)" $? d'
aa_caso p4 'for c in a b; do "$c" >/dev/null; f "n-$(basename "$c")" $? d; done'
aa_caso p5 'false; f "$(g)" $? d'
aa_caso p6 'false; f "n-${v:-$(printf x)}" $? d'
aa_caso n1 'false; f "n" $? "$(printf x)"'
aa_caso n2 'false; f "n-$((1 + 1))" $?'
aa_caso n3 'v=zz; false; f "n-${v//z/y}" $?'
aa_caso n4 '[ "$(printf a)" = a ]; f "n" $?'
aa_caso n5 'false; f '"'"'n-$(printf x)'"'"' $? d'
aa_caso n6 '# false; f "n-$(printf x)" $? d'
aa_caso n7 'm="$(printf x)"
false; f "n" $?'
printf 'cat <<EOF\nn-$(printf x) $?\nEOF\n' > "$AA_T/n8.sh"
AA_POS="p1 p2 p3 p4 p5 p6"; AA_NEG="n1 n2 n3 n4 n5 n6 n7 n8"
aa_bateria() { # aa_bateria <implementacao do guarda> -> o que ela classificou errado
  local g="$1" f erros=""
  for f in $AA_POS; do [ -n "$("$g" "$AA_T/$f.sh")" ] || erros="$erros $f(nao-acusou)"; done
  for f in $AA_NEG; do [ -z "$("$g" "$AA_T/$f.sh")" ] || erros="$erros $f(acusou)"; done
  printf '%s' "${erros# }"
}
AA_BAT="$(aa_bateria aa_vulneraveis)"
[ -z "$AA_BAT" ]; aa_rc=$?
afirma "aa3-guarda-classifica-vulneravel-e-seguro" "$aa_rc" "${AA_BAT:-6 vulneraveis acusadas, 8 seguras liberadas}"
AA_BAT="$(aa_bateria aa_guarda_cega)"
[ -n "$AA_BAT" ]; aa_rc=$?
afirma "aa3b-mutante-guarda-cega-morre" "$aa_rc" "${AA_BAT:-SOBREVIVEU: guarda que nunca acusa passou na bateria}"
AA_BAT="$(aa_bateria aa_guarda_tudo)"
[ -n "$AA_BAT" ]; aa_rc=$?
afirma "aa3c-mutante-guarda-que-acusa-tudo-morre" "$aa_rc" "${AA_BAT:-SOBREVIVEU: guarda sem discriminacao passou na bateria}"

# 4. As seis familias preexistentes, em runtime: com a condicao falsa, o status que `afirma`
#    recebe e nao-zero. Cada prelude so faz a condicao real reprovar (stub do comando sob teste,
#    arquivo vazio, script que sai 0) — a expressao do nome dinamico roda de verdade.
printf 'exit 0\n' > "$AA_T/pl-ok.sh"; : > "$AA_T/agente-vazio.md"
AA_LIT_GA7='ga7-orcamento-invalido-$(printf'
AA_PRE_GA7='pl() { return 0; }; fdir() { printf %s '"$AA_T"'/sem-plano; }; D='"$AA_T"'/d; G='"$AA_T"'; ruim="2.5 buildx"; rc=0'
for aa_f in \
  "ga7-orcamento-invalido|$AA_LIT_GA7|$AA_PRE_GA7" \
  "gl3-recusa-staged|gl3-recusa-\$(printf|pl() { return 0; }; D=$AA_T/d; prod=package.json" \
  "gh-instrucao-unica|gh-instrucao-unica-\$(printf|grep() { return 1; }; inst=\"criar <slug>:01-ingestao\"" \
  "gw3-revisor-recusa|gw3-revisor-recusa-\$(printf|PL=$AA_T/pl-ok.sh; ruim=\"T-01.01 | fraco\"" \
  "g-agente-tabela|g-agente-tabela-\$(basename|ag=$AA_T/agente-vazio.md" \
  "u-escritor-do-rastro|u_nome \"\$c\"|U_CASOS=u_x; u_nome() { printf ux-caso; }; u_x() { return 1; }; U_REAL=$AA_T/x" \
; do
  aa_nome="aa4-preserva-o-falso-${aa_f%%|*}"; aa_resto="${aa_f#*|}"
  aa_cap="$(aa_replay "$AA_BANC" "${aa_resto%%|*}" "${aa_resto#*|}")"
  aa_preserva "$aa_cap"; aa_rc=$?
  afirma "$aa_nome" "$aa_rc" "condicao falsa -> afirma recebeu [$aa_cap]"
done

# 5. Mutantes do sitio corrigido, em copia temporaria da bancada. Cada um tem de morrer pelo
#    oraculo que o nomeia, e nao de carona: o mutante 2 e exatamente a "troca de ordem" que o
#    guarda estatico NAO ve (o `rc=$?` fica num comando simples proprio, sem substituicao) e que
#    so o replay mata. Os equivalentes nao contam como mortos.
AA_M="$AA_T/mut"; mkdir -p "$AA_M"
AA_NOME_GA7='  g_nome="ga7-orcamento-invalido-$(printf '"'"'%s'"'"' "$ruim" | tr '"'"' .'"'"' '"'"'__'"'"')"'
AA_COND_GA7='00-PLANEJAMENTO.md" ]; g_rc=$?'
AA_AFIR_GA7='afirma "$g_nome" "$g_rc" "rc=$rc, nada gravado"'
aa_morte() { # aa_morte <bancada> -> quais oraculos matam o arquivo
  local m=""
  [ -n "$(aa_vulneraveis "$1")" ] && m="$m guarda"
  aa_preserva "$(aa_replay "$1" "$AA_LIT_GA7" "$AA_PRE_GA7")" || m="$m replay"
  printf '%s' "${m# }"
}
aa_mutante() { # aa_mutante <nome> <rc geracao> <bancada mutada> <morte esperada>
  local nome="$1" rcg="$2" arq="$3" esp="$4" m=""
  [ "$rcg" -eq 0 ] && m="$(aa_morte "$arq")"
  [ "$rcg" -eq 0 ] && [ "$m" = "$esp" ]; aa_rc=$?
  afirma "$nome" "$aa_rc" "morte=[${m:-nenhuma}] esperada=[$esp] (rc geracao=$rcg)"
}
aa_equivalente() { # aa_equivalente <nome> <rc geracao> <bancada mutada> — equivalente nao morre
  local nome="$1" rcg="$2" arq="$3" m=""
  [ "$rcg" -eq 0 ] && m="$(aa_morte "$arq")"
  [ "$rcg" -eq 0 ] && [ -z "$m" ]; aa_rc=$?
  afirma "$nome" "$aa_rc" "equivalente, nao conta como morto; morte=[${m:-nenhuma}] (rc geracao=$rcg)"
}
cp "$AA_BANC" "$AA_M/controle.sh"; AA_K="$(aa_morte "$AA_M/controle.sh")"
[ -z "$AA_K" ]; aa_rc=$?
afirma "aam-controle-copia-intacta-sobrevive" "$aa_rc" "oraculos que reprovam a copia sem mutacao: [${AA_K:-nenhum}]"
muta_lit "$AA_BANC" "$AA_M/m1.sh" "$AA_AFIR_GA7" 'afirma "$g_nome$(printf x)" $? "rc=$rc, nada gravado"'
aa_mutante "aam-mutante-1-nome-montado-na-chamada-com-dolar-interrogacao" $? "$AA_M/m1.sh" "guarda replay"
muta_lit "$AA_BANC" "$AA_M/m2a.sh" "$AA_NOME_GA7" '  :' \
  && muta_lit "$AA_M/m2a.sh" "$AA_M/m2.sh" "$AA_COND_GA7" "00-PLANEJAMENTO.md\" ];$AA_NOME_GA7; g_rc=\$?"
aa_mutante "aam-mutante-2-ordem-trocada-com-o-nome-entre-a-condicao-e-o-rc" $? "$AA_M/m2.sh" "replay"
muta_lit "$AA_BANC" "$AA_M/m3.sh" "$AA_AFIR_GA7" 'afirma "$g_nome" $? "rc=$rc, nada gravado"'
aa_mutante "aam-mutante-3-dolar-interrogacao-lido-depois-do-proprio-rc" $? "$AA_M/m3.sh" "replay"
muta_lit "$AA_BANC" "$AA_M/e1a.sh" "$AA_COND_GA7" '00-PLANEJAMENTO.md" ]; g_estado=$?' \
  && muta_lit "$AA_M/e1a.sh" "$AA_M/e1.sh" "$AA_AFIR_GA7" 'afirma "$g_nome" "$g_estado" "rc=$rc, nada gravado"'
aa_equivalente "aae-equivalente-1-outro-nome-para-a-variavel-do-status" $? "$AA_M/e1.sh"
muta_lit "$AA_BANC" "$AA_M/e2.sh" "$AA_AFIR_GA7" 'afirma "$g_nome" $g_rc "rc=$rc, nada gravado"'
aa_equivalente "aae-equivalente-2-status-passado-sem-aspas" $? "$AA_M/e2.sh"

# 6. A decisao esta registrada: sem DS-161, a forma canonica volta a ser escolha de quem escreve
#    a proxima assercao, e o defeito reaparece na primeira chamada com nome dinamico.
AA_DS="$SK/DECISOES-DA-SKILL.md"
[ "$(grep -c '^| DS-161 |' "$AA_DS")" -eq 1 ]; aa_rc=$?
afirma "aa5-ds161-registrada" "$aa_rc" "uma linha DS-161 no registro"
AA_L161="$(grep -F '| DS-161 |' "$AA_DS")"
[ "$(printf '%s' "$AA_L161" | grep -cF 'substitui')" -gt 0 ] && [ "$(printf '%s' "$AA_L161" | grep -cF '$?')" -gt 0 ]; aa_rc=$?
afirma "aa5b-ds161-nomeia-a-causa" "$aa_rc" "DS-161 diz que a substituicao de comando come o \$?"
[ "$(printf '%s' "$AA_L161" | grep -cE 'rc=\$\?|variavel')" -gt 0 ]; aa_rc=$?
afirma "aa5c-ds161-fixa-a-forma-canonica" "$aa_rc" "DS-161 diz capturar o status e passar por variavel"
rm -rf "$AA_T"

echo "== AB. \`desvio_task\` nomeava duas grandezas incompativeis; os dois simbolos sao canonicos (D-11) =="
# A D-09 fixou o AGREGADOR do numero que calibra e a D-10 a sua PRECISAO. O NOME continuava
# ambiguo, e no MESMO arquivo: na 07-estimativa.md, `desvio_task` era
#   Passo 5  (linha 139 em f917fe0): (p - o) / 6                 — desvio-padrao PERT, em HORAS,
#                                                                  dispersao de uma estimativa;
#   Passo 10 (linha 295 em f917fe0): real / media_task_estimada  — razao de calibracao,
#                                                                  ADIMENSIONAL, quanto o real
#                                                                  excedeu o estimado.
# 06-execucao.md, TEMPLATE-HISTORICO.md, 00-schema.md e 08-rastro.md usavam o nome na segunda
# acepcao; TEMPLATE-ESTIMATIVA.md na primeira. A consequencia e em hora cobrada: quem le "o fator
# multiplica `media_task` e `desvio_task`" (Passo 1) e procura o simbolo encontra as duas
# definicoes, e somar em quadratura a razao de calibracao em vez do desvio-padrao publica 9-14 h
# onde o canonico publica 10-14 h.
# Canonico (DS-162): `desvio_padrao_task` SO para (p - o) / 6; `desvio_calibracao_task` SO para
# real / estimado_media. As chaves persistidas nao mudam: `desvio` e `desvio_medio` (D-10).
# O REGISTRO e append-only ("nada acima e revisto", declarado em cada secao D do arquivo): DS-37,
# DS-40, DS-160 e DS-161 seguem como nasceram — a DS-37 e a DS-160 com `desvio_task`, a DS-40 com
# `desvio` sem sufixo —, e e a DS-162 que declara o mapeamento para o par canonico. Por
# isso os casos de colisao varrem a arvore VIVA do contrato — referencias e assets —, nunca o
# registro; o registro responde pelos seus proprios casos.
AB_PERT_RE='\(p[[:space:]]*-[[:space:]]*o\)[[:space:]]*/[[:space:]]*6'
AB_CAL_RE='real[[:space:]]*/[[:space:]]*(estimado_media|media_task_estimada)'
# Pontos que LIGAM cada simbolo a sua formula, os que o NOMEIAM, e a arvore viva inteira.
AB_REL_PERT="references/07-estimativa.md assets/TEMPLATE-ESTIMATIVA.md"
AB_REL_CAL="references/07-estimativa.md references/06-execucao.md assets/TEMPLATE-HISTORICO.md"
AB_REL_NOMEIA_CAL="$AB_REL_CAL references/00-schema.md references/08-rastro.md"
AB_REL_VIVOS="references/00-schema.md references/06-execucao.md references/07-estimativa.md
references/08-rastro.md assets/TEMPLATE-ESTIMATIVA.md assets/TEMPLATE-HISTORICO.md"

# Os detectores leem o texto SEM marcacao: `**antes**` e `antes` sao a mesma regra (mesma
# disciplina da secao Z). E contam linhas (`-c`) em vez de abortar na primeira (`-q`): depois de
# um pipe, `grep -q` fecha a entrada no primeiro casamento, o `tr` a montante leva SIGPIPE e, com
# `pipefail` ligado (linha 9), o pipeline devolve status nao-zero mesmo tendo casado.
ab_txt() { tr -d '*`' < "$1"; }
ab_conta() { ab_txt "$1" | grep -ciE "$2"; }
ab_tem_re() { [ "$(ab_conta "$1" "$2")" -gt 0 ]; }

# ab_lig <arquivo> <regex-da-formula> -> os simbolos ligados AQUELA formula, um por linha.
# A ligacao e `<simbolo> = <...formula...>`, em bloco de codigo ou inline numa celula de tabela.
# `[^=|]{0,40}` aceita o prefixo `arredonda( ` e nao cruza outro `=` nem separador de celula, para
# nao colar o simbolo de uma ligacao na formula da ligacao seguinte da mesma linha.
ab_lig() {
  ab_txt "$1" \
    | grep -ohE "(desvio|media|variancia)[a-z_]*[[:space:]]*=[[:space:]]*[^=|]{0,40}($2)" \
    | sed 's/[[:space:]]*=.*//' | sort -u
}
ab_simbolos() { # ab_simbolos <dir> <regex> -> simbolos daquela formula na arvore viva inteira
  local d="$1" re="$2" f
  for f in $AB_REL_VIVOS; do [ -f "$d/$f" ] && ab_lig "$d/$f" "$re"; done | sort -u
}

# O caso e por ARVORE, nao por caminho fixo: a bateria real roda em "$SK" e cada mutante roda a
# MESMA bateria numa copia, sem nunca tocar as referencias reais.
ab_caso() { # ab_caso <caso> <dir> -> 0 se o caso PASSA naquela arvore
  local c="$1" d="$2" f sujo="" v
  case "$c" in
    # O simbolo colidente nao existe mais em ponto nenhum da arvore viva. E o detector direto da
    # D-11: enquanto `desvio_task` existir ali, as duas definicoes continuam alcancaveis pelo
    # mesmo nome. Busca literal — nem `desvio_padrao_task` nem `desvio_calibracao_task` o contem.
    ab_sem_simbolo_colidente)
      for f in $AB_REL_VIVOS; do
        [ -f "$d/$f" ] && grep -qF 'desvio_task' "$d/$f" && sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    # Nenhum simbolo esta ligado as DUAS formulas. E a colisao medida, e vale para QUALQUER nome:
    # trocar o par canonico por outro par disjunto nao reabre o defeito; usar um nome para as duas
    # grandezas reabre. Interseccao vazia e a regra. Cada lista ja vem unica, logo o que aparece
    # duas vezes na concatenacao e exatamente a interseccao.
    ab_sem_intersecao)
      v="$({ ab_simbolos "$d" "$AB_PERT_RE"; ab_simbolos "$d" "$AB_CAL_RE"; } \
            | sort | uniq -d | tr '\n' ' ')"
      [ -z "$v" ] ;;
    # Cada formula esta ligada a EXATAMENTE um simbolo, e e o canonico.
    ab_pert_canonica)
      for f in $AB_REL_PERT; do
        [ "$(ab_lig "$d/$f" "$AB_PERT_RE" | tr '\n' ' ' | sed 's/ $//')" = "desvio_padrao_task" ] \
          || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    ab_cal_canonica)
      for f in $AB_REL_CAL; do
        [ "$(ab_lig "$d/$f" "$AB_CAL_RE" | tr '\n' ' ' | sed 's/ $//')" = "desvio_calibracao_task" ] \
          || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    # Cada ponto de ENTRADA marca a fronteira contra a outra grandeza. Regra que existe so onde as
    # duas se encontram e regra que a sessao seguinte nao encontra: ela chega pelo arquivo da
    # calibracao, ou pelo da estimativa, e nunca le o outro.
    ab_fronteira_pert)
      for f in $AB_REL_PERT; do
        ab_tem_re "$d/$f" 'desvio_padrao_task' \
          && ab_tem_re "$d/$f" 'nunca o desvio_calibracao_task|n[ãa]o (é|e) o desvio_calibracao_task' \
          || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    ab_fronteira_cal)
      for f in $AB_REL_NOMEIA_CAL; do
        ab_tem_re "$d/$f" 'desvio_calibracao_task' \
          && ab_tem_re "$d/$f" 'nunca o desvio_padrao_task|n[ãa]o (é|e) o desvio_padrao_task' \
          || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    # As chaves PERSISTIDAS da calibracao nunca sao ligadas a formula PERT na arvore viva. A
    # interseccao nao pega este caso — `desvio` nao aparece ligado a razao com `=`, so em prosa —,
    # e e a forma que a DS-40 carregava: a chave do numero adimensional definida como dispersao
    # em horas. No registro ela fica como historia; aqui, nunca.
    ab_chave_fora_do_pert)
      v="$(ab_simbolos "$d" "$AB_PERT_RE" | grep -xE 'desvio|desvio_medio' | tr '\n' ' ')"
      [ -z "$v" ] ;;
    # Schema publico intacto: a correcao e de vocabulario matematico interno, nao de formato.
    ab_chaves_publicas)
      grep -qF 'desvio:' "$d/references/00-schema.md" \
        && grep -qF 'desvio_medio:' "$d/references/00-schema.md" \
        && grep -qF 'desvio:' "$d/assets/TEMPLATE-HISTORICO.md" \
        && grep -qF 'desvio_medio:' "$d/assets/TEMPLATE-HISTORICO.md" \
        && grep -qF 'fator_correcao_aplicado' "$d/references/00-schema.md" ;;
    # E o simbolo interno NAO vira chave: ele nomeia a grandeza no contrato matematico, nunca um
    # campo em disco. Chave nova seria quebra de schema disfarcada de clareza.
    ab_simbolo_interno_nao_persiste)
      v="$(grep -rnE '^[[:space:]]*(desvio_padrao_task|desvio_calibracao_task|desvio_padrao_medio|desvio_calibracao_medio):' \
        "$d/references/00-schema.md" "$d/assets/TEMPLATE-HISTORICO.md" "$d/assets/TEMPLATE-ESTIMATIVA.md" \
        2>/dev/null | tr '\n' ' ')"
      [ -z "$v" ] ;;
    # A incompatibilidade esta DECLARADA onde as duas grandezas se encontram (a 07-estimativa.md
    # define as duas). Sem a frase, o proximo leitor acha os dois nomes sinonimos e os funde de
    # volta — foi assim que o nome unico sobreviveu a D-09 e a D-10.
    ab_incompatibilidade)
      f=references/07-estimativa.md
      ab_tem_re "$d/$f" 'duas grandezas (diferentes|incompat[íi]veis)|grandezas incompat[íi]veis' \
        && ab_tem_re "$d/$f" 'desvio_padrao_task' \
        && ab_tem_re "$d/$f" 'desvio_calibracao_task' \
        && ab_tem_re "$d/$f" 'n[ãa]o s[ãa]o intercambi|nunca intercambi' \
        && ab_tem_re "$d/$f" 'adimensional' ;;
    # A decisao esta registrada: e onde a proxima sessao encontra o PORQUE do par de nomes. E ela
    # nomeia a notacao SUPERADA, que o registro append-only conserva nas decisoes antigas — sem
    # isso, quem le a DS-37 ou a DS-160 nao tem como saber qual das duas grandezas e aquela.
    ab_ds162)
      v="$(grep -F '| DS-162 |' "$d/DECISOES-DA-SKILL.md")"
      [ -n "$v" ] \
        && printf '%s' "$v" | grep -qF 'desvio_padrao_task' \
        && printf '%s' "$v" | grep -qF 'desvio_calibracao_task' \
        && printf '%s' "$v" | grep -qF 'desvio_medio' \
        && printf '%s' "$v" | grep -qF 'desvio_task' ;;
    # E o registro continua append-only: as decisoes que nasceram com a notacao antiga seguem
    # inteiras, inclusive a DS-161 da D-12. Reescrever o registro para "limpar" o vocabulario
    # apagaria a historia que explica por que o par de nomes existe.
    ab_registro_append_only)
      for f in DS-37 DS-40 DS-160 DS-161; do
        grep -qF "| $f |" "$d/DECISOES-DA-SKILL.md" || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    *) return 1 ;;
  esac
}
AB_CASOS="ab_sem_simbolo_colidente ab_sem_intersecao ab_pert_canonica ab_cal_canonica
ab_fronteira_pert ab_fronteira_cal ab_chave_fora_do_pert ab_chaves_publicas
ab_simbolo_interno_nao_persiste ab_incompatibilidade ab_ds162 ab_registro_append_only"

# 1. Dados literais que SEPARAM as duas grandezas na MESMA task. Sem isto, "dois nomes" seria
#    discussao de estilo: duas tasks `integracao_externa` (o=4 m=5 p=12 com real 6.8; o=3 m=4 p=5
#    com real 4.8) tem desvio-padrao PERT 1,33 h e 0,33 h — dispersao, em hora — e razao de
#    calibracao 1,13 e 1,20 — adimensional, e os `desvio` persistidos da D-10. Quatro numeros,
#    duas grandezas, um nome so no contrato da base.
ab_num() { # ab_num <o> <m> <p> <real> <grandeza:padrao|calibracao>
  awk -v o="$1" -v m="$2" -v p="$3" -v r="$4" -v g="$5" 'BEGIN {
    med = (o + 4*m + p) / 6
    x = (g == "padrao") ? (p - o) / 6 : r / med
    s = x * 100; i = int(s); if (s - i >= 0.5) i++      # duas casas, half-up (D-10)
    printf "%.2f", i / 100
  }'
}
AB_PA="$(ab_num 4 5 12 6.8 padrao)";     AB_CA="$(ab_num 4 5 12 6.8 calibracao)"
AB_PB="$(ab_num 3 4  5 4.8 padrao)";     AB_CB="$(ab_num 3 4  5 4.8 calibracao)"
[ "$AB_PA" = "1.33" ] && [ "$AB_CA" = "1.13" ] && [ "$AB_PB" = "0.33" ] && [ "$AB_CB" = "1.20" ] \
  && [ "$AB_PA" != "$AB_CA" ] && [ "$AB_PB" != "$AB_CB" ]; ab_rc=$?
afirma "ab1-grandezas-separadas-na-mesma-task" "$ab_rc" \
  "A: padrao=$AB_PA h razao=$AB_CA | B: padrao=$AB_PB h razao=$AB_CB"

# 1b. E a troca de uma pela outra e observavel em HORA PUBLICADA: somar em quadratura as razoes de
#     calibracao, em vez dos desvios-padrao, com o mesmo fator canonico 1,16 da D-10, publica
#     9-14 h onde o canonico publica 10-14 h. E a mesma divergencia que a D-10 mediu, agora pelo
#     nome e nao pelo arredondamento.
ab_faixa() { # ab_faixa <fator> <grandeza na quadratura:padrao|calibracao>
  awk -v f="$1" -v g="$2" 'BEGIN {
    mA = (4 + 4*5 + 12)/6; mB = (3 + 4*4 + 5)/6
    if (g == "padrao") { dA = (12 - 4)/6; dB = (5 - 3)/6 } else { dA = 1.13; dB = 1.20 }
    m = (mA + mB) * f; d = sqrt(dA*dA + dB*dB) * f
    mn = m - d; mx = m + d; piso = (4 + 3) * f
    if (mn < piso) mn = piso
    printf "%d-%d", int(mn), (mx == int(mx) ? mx : int(mx) + 1)
  }'
}
AB_FX_OK="$(ab_faixa 1.16 padrao)"; AB_FX_COL="$(ab_faixa 1.16 calibracao)"
[ "$AB_FX_OK" = "10-14" ] && [ "$AB_FX_COL" = "9-14" ] && [ "$AB_FX_OK" != "$AB_FX_COL" ]; ab_rc=$?
afirma "ab1b-colisao-muda-a-faixa-publicada" "$ab_rc" \
  "desvio_padrao_task -> $AB_FX_OK h; razao de calibracao na quadratura -> $AB_FX_COL h"

# 2 a 13. A bateria, lida das referencias reais. O nome do caso e derivado ANTES da condicao e o
#         status e capturado na linha seguinte: substituicao de comando antes do `$?` apagaria o
#         status da condicao (DS-161 / secao AA).
for ab_c in $AB_CASOS; do
  ab_nome="$(printf '%s' "$ab_c" | tr '_' '-')"
  ab_caso "$ab_c" "$SK"; ab_rc=$?
  afirma "$ab_nome" "$ab_rc" "lido da arvore do contrato em $SK"
done

# 14. Mutantes. Cada um nasce numa COPIA da skill — as referencias reais nunca sao tocadas — e tem
#     de morrer pelos casos nomeados, nao de carona: o caso nomeado e verificado um a um, e o
#     mutante so e considerado morto quando TODOS eles reprovam. `ab_muta` so devolve 0 quando o
#     arquivo REALMENTE mudou em relacao a arvore real.
ABW="$(mktemp -d)"
ab_copia() { rm -rf "$ABW/$1"; mkdir -p "$ABW/$1"; cp -R "$SK/." "$ABW/$1/"; printf '%s' "$ABW/$1"; }
ab_muta() { # ab_muta <dir> <arquivo-rel> <expressao sed>
  [ -f "$1/$2" ] || return 1
  sed -i "$3" "$1/$2" || return 1
  ! cmp -s "$SK/$2" "$1/$2"
}
ab_mata() { local c; for c in $AB_CASOS; do ab_caso "$c" "$1" || { printf '%s' "$c"; return; }; done; }
ab_mutante() { # ab_mutante <nome> <rc da geracao> <dir> <caso que TEM de matar>...
  local nome="$1" rcg="$2" d="$3" c vivos=""; shift 3
  if [ "$rcg" -eq 0 ]; then for c in "$@"; do ab_caso "$c" "$d" && vivos="$vivos$c "; done; fi
  [ "$rcg" -eq 0 ] && [ -z "$vivos" ]; local rc=$?
  afirma "$nome" "$rc" "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rcg)"
}
ab_equivalente() { # ab_equivalente <nome> <rc da geracao> <dir> — equivalente nao pode morrer
  local nome="$1" rcg="$2" d="$3" m=""
  [ "$rcg" -eq 0 ] && m="$(ab_mata "$d")"
  [ "$rcg" -eq 0 ] && [ -z "$m" ]; local rc=$?
  afirma "$nome" "$rc" "equivalente, nao conta como morto; reprovou=[${m:-nenhum}] (rc geracao=$rcg)"
}
AB_CTL="$(ab_copia controle)"
AB_K="$(ab_mata "$AB_CTL")"; [ -z "$AB_K" ]; ab_rc=$?
afirma "abm-controle-copia-intacta-sobrevive" "$ab_rc" "${AB_K:-nenhum caso reprova a copia sem mutacao}"

# m1 — a colisao da base, restaurada: um nome para as duas formulas no mesmo arquivo.
AB_M="$(ab_copia m1)"
ab_muta "$AB_M" references/07-estimativa.md 's/desvio_padrao_task/desvio_task/g; s/desvio_calibracao_task/desvio_task/g'
ab_mutante "abm-mutante-1-colisao-restaurada" $? "$AB_M" \
  ab_sem_simbolo_colidente ab_sem_intersecao ab_pert_canonica ab_cal_canonica

# m2 — so o lado PERT volta ao nome antigo. Nao ha interseccao (a calibracao mantem o seu nome),
#      e por isso este mutante prova que o caso do simbolo ausente e independente do da
#      interseccao: o nome ambiguo de volta e defeito mesmo sem as duas acepcoes no mesmo nome.
AB_M="$(ab_copia m2)"
ab_muta "$AB_M" assets/TEMPLATE-ESTIMATIVA.md 's/desvio_padrao_task/desvio_task/g'
ab_mutante "abm-mutante-2-so-o-lado-pert-reverte" $? "$AB_M" \
  ab_sem_simbolo_colidente ab_pert_canonica ab_fronteira_pert
ab_caso ab_sem_intersecao "$AB_M"; ab_rc=$?
afirma "abm-mutante-2-nao-produz-interseccao" "$ab_rc" "os dois casos sao independentes, como projetado"

# m3 — a forma da DS-40 trazida para a arvore viva: a chave PERSISTIDA da calibracao definida como
#      a dispersao PERT. A interseccao nao a ve; o caso da chave, sim.
AB_M="$(ab_copia m3)"
ab_muta "$AB_M" assets/TEMPLATE-ESTIMATIVA.md 's/^desvio_padrao_task = (p - o) \/ 6/desvio = (p - o) \/ 6/'
ab_mutante "abm-mutante-3-chave-persistida-vira-formula-pert" $? "$AB_M" \
  ab_chave_fora_do_pert ab_pert_canonica

# m4 — as formulas trocadas: o simbolo do desvio-padrao ligado a razao de calibracao. O defeito
#      sob os nomes NOVOS — a prova de que o oraculo e sobre as grandezas, nao sobre a grafia.
AB_M="$(ab_copia m4)"
ab_muta "$AB_M" references/06-execucao.md 's/^desvio_calibracao_task = arredonda/desvio_padrao_task = arredonda/'
ab_mutante "abm-mutante-4-formulas-trocadas-sob-os-nomes-novos" $? "$AB_M" \
  ab_sem_intersecao ab_cal_canonica

# m5 — a chave publica renomeada a pretexto de clareza. Schema quebrado, parser quebrado.
AB_M="$(ab_copia m5)"
ab_muta "$AB_M" references/00-schema.md 's/desvio_medio:/desvio_calibracao_medio:/g'
ab_mutante "abm-mutante-5-chave-publica-renomeada" $? "$AB_M" ab_chaves_publicas

# m6 — a declaracao da incompatibilidade removida: os dois nomes ficam, a razao de serem dois sai.
AB_M="$(ab_copia m6)"
ab_muta "$AB_M" references/07-estimativa.md '/^> \*\*Dois nomes, duas grandezas\.\*\*/d'
ab_mutante "abm-mutante-6-incompatibilidade-apagada" $? "$AB_M" ab_incompatibilidade ab_fronteira_pert

# m7 — o simbolo interno promovido a chave em disco, sem remover a antiga.
AB_M="$(ab_copia m7)"
ab_muta "$AB_M" assets/TEMPLATE-HISTORICO.md '/^    desvio: /a\    desvio_calibracao_task: 1.13'
ab_mutante "abm-mutante-7-simbolo-interno-vira-chave" $? "$AB_M" ab_simbolo_interno_nao_persiste

# m8 — a fronteira apagada de um ponto de entrada da calibracao: a 08-rastro.md deixa de dizer que
#      o que a calibracao agrega nao e o desvio-padrao. Quem chega por ela volta a poder confundir.
AB_M="$(ab_copia m8)"
ab_muta "$AB_M" references/08-rastro.md 's/, nunca o `desvio_padrao_task`//g'
ab_mutante "abm-mutante-8-fronteira-apagada-no-rastro" $? "$AB_M" ab_fronteira_cal

# m9 — a DS-162 apagada do registro: a regra fica nas referencias e perde o porque.
AB_M="$(ab_copia m9)"
ab_muta "$AB_M" DECISOES-DA-SKILL.md '/^| DS-162 |/d'
ab_mutante "abm-mutante-9-ds162-apagada" $? "$AB_M" ab_ds162

# m10 — o registro "limpo": a DS-161 da D-12 removida junto com a notacao antiga. E o oposto do
#       append-only, e o jeito mais facil de a correcao de vocabulario apagar historia alheia.
AB_M="$(ab_copia m10)"
ab_muta "$AB_M" DECISOES-DA-SKILL.md '/^| DS-161 |/d'
ab_mutante "abm-mutante-10-registro-reescrito" $? "$AB_M" ab_registro_append_only

# Equivalentes: mudam a forma e nao a regra, e por isso NAO podem morrer. Sem eles, um oraculo que
# casasse espaco em branco ou marcacao passaria por discriminante sem ser.
AB_M="$(ab_copia e1)"
ab_muta "$AB_M" assets/TEMPLATE-ESTIMATIVA.md 's/^desvio_padrao_task = (p - o) \/ 6/desvio_padrao_task   =  (p-o)\/6/'
ab_equivalente "abe-equivalente-1-espacamento-da-formula" $? "$AB_M"
AB_M="$(ab_copia e2)"
ab_muta "$AB_M" references/08-rastro.md 's/`desvio_calibracao_task`/**desvio_calibracao_task**/g'
ab_equivalente "abe-equivalente-2-marcacao-do-simbolo" $? "$AB_M"
rm -rf "$ABW"

# 15. E a vitrine e a SKILL.md tambem nao carregam o simbolo colidente: sao os lugares de onde a
#     proxima sessao reconstroi o vocabulario errado sem nunca abrir uma reference.
AB_VITRINE="$(grep -rlF 'desvio_task' "$H/../../README.md" "$SK/SKILL.md" 2>/dev/null | tr '\n' ' ')"
[ -z "$AB_VITRINE" ]; ab_rc=$?
afirma "ab-vitrine-sem-o-simbolo-colidente" "$ab_rc" "arquivos com o simbolo antigo=[${AB_VITRINE:-nenhum}]"

echo "== AC. a calibracao conta so entradas com \`desvio\` numerico; \`desvio: null\` nao entra (B2) =="
# A D-09 fixou o AGREGADOR, a D-10 a PRECISAO e a D-11 o NOME. O CONJUNTO AGREGADO continuava
# indefinido. O mesmo schema diz as duas coisas:
#   - `estimado_min`, `estimado_max`, `estimado_media` e `desvio` sao `null` quando o trabalho
#     rodou sem a F3.5; `real` e sempre preenchido  (00-schema.md, kind estimativa_historico);
#   - `fator_ativo` so e `true` com 3 ou mais entradas ENCERRADAS daquele tipo (mesmo arquivo),
#     e `desvio_medio` e a media dos desvios persistidos das entradas ENCERRADAS daquele tipo
#     (06-execucao.md Passo 3, TEMPLATE-HISTORICO.md).
# Entrada sem F3.5 e entrada encerrada: ela tem `real`, nao tem `desvio`. Logo "entradas
# encerradas" alcanca entradas cujo `desvio` e `null`, e o contrato nao diz o que fazer com elas —
# nem no contador `entradas`, nem na media `desvio_medio`, nem no limiar do `fator_ativo`. Duas
# execucoes honestas do MESMO historico gravam `entradas: 2 / desvio_medio: 1.25 /
# fator_ativo: false` e `entradas: 4 / desvio_medio: 0.63 / fator_ativo: true`: contador, numero e
# chave booleana diferentes, e um fator de correcao LIGADO sobre dois desvios reais.
# Fica ambigua tambem a FORMA com 1 ou 2 entradas elegiveis: item presente com `fator_ativo:
# false`, ou nenhum item? A D-08 fixou so o extremo (`calibracao: []` e a tabela sem linha de
# dados), e apagar o item com poucas entradas perde o contador que o proximo fechamento incrementa.
# Canonico a fixar: `entradas`, `desvio_medio` e `fator_ativo` leem SO as entradas com `desvio`
# numerico (nao nulo); nulo nunca vale zero; item presente a partir de 1 elegivel; `calibracao: []`
# so sem nenhuma elegivel.
# Pontos que DEFINEM o conjunto agregado, os que definem o LIMIAR, e os que definem a FORMA.
AC_REL_DEFINEM="references/00-schema.md references/06-execucao.md assets/TEMPLATE-HISTORICO.md"
AC_REL_LIMIAR="references/00-schema.md references/06-execucao.md"
AC_REL_FORMA="references/00-schema.md assets/TEMPLATE-HISTORICO.md"

# Detectores sobre o texto SEM marcacao, contando linhas em vez de abortar na primeira: mesma
# disciplina das secoes Z e AB (`grep -q` depois de um pipe derruba o pipeline com `pipefail`).
ac_txt() { tr -d '*`' < "$1"; }
ac_conta() { ac_txt "$1" | grep -ciE "$2"; }
ac_tem_re() { [ -f "$1" ] && [ "$(ac_conta "$1" "$2")" -gt 0 ]; }

# As politicas que o contrato tem de fixar, LIDAS do texto — nunca assumidas pelo teste.
# `[^.]{0,N}` nao cruza ponto final: a regra tem de estar na MESMA frase, senao "entradas
# encerradas" num paragrafo e "desvio numerico" noutro passariam por definicao.
AC_RE_ELEG='(entradas|contador|contagem|contam|conta|elegív|elegiv)[^.]{0,160}desvio[^.]{0,80}(numéric|numeric|não nul|nao nul)|desvio[^.]{0,80}(numéric|numeric|não nul|nao nul)[^.]{0,160}(entradas|contador|contagem|contam)'
AC_RE_ENC='entradas encerradas|a partir de [0-9]+ entradas'
AC_RE_NULO_NAO_ZERO='(nunca|não|nao)[^.]{0,80}(como|igual a|vale) (zero|0)'
AC_RE_ZERO='(como|igual a|vale) (zero|0)[^.]{0,40}(na média|na media|no cálculo|no calculo)|conta como (zero|0)'
AC_RE_MEDIA_ELEG='(desvio_medio|média|media)[^.]{0,200}(elegív|elegiv|desvio numéric|desvio numeric|desvio não nul|desvio nao nul)|(elegív|elegiv|desvio numéric|desvio numeric)[^.]{0,200}(desvio_medio|média dos|media dos)'
AC_RE_LIM_ELEG='[0-9]+ ou mais entradas (elegíveis|elegiveis)|a partir de [0-9]+ entradas (elegíveis|elegiveis)'
AC_RE_LIM_ENC='[0-9]+ ou mais entradas encerradas|a partir de [0-9]+ entradas( |,|\.|$)'
AC_RE_FORMA='(1 ou 2|uma ou duas) entradas (elegíveis|elegiveis)[^.]{0,200}(item|linha)|(o item|a linha)[^.]{0,200}(1 ou 2|uma ou duas) entradas (elegíveis|elegiveis)'
AC_RE_VAZIA='calibracao: \[\][^.]{0,240}(nenhuma entrada elegív|nenhuma entrada elegiv|sem entrada elegív|zero entradas elegív)|(nenhuma entrada elegív|nenhuma entrada elegiv|sem entrada elegív|zero entradas elegív)[^.]{0,240}calibracao: \[\]'
AC_RE_NULO_FORA='desvio: null[^.]{0,200}(não cont|nao cont|fora d|nunca entra|ignorad|não é elegív|nao e elegiv)|(não cont|nao cont|fora d|nunca entra|ignorad)[^.]{0,200}desvio: null'

ac_pol_contador() { # -> numerico | encerradas | indefinido
  if   ac_tem_re "$1" "$AC_RE_ELEG"; then printf 'numerico'
  elif ac_tem_re "$1" "$AC_RE_ENC";  then printf 'encerradas'
  else printf 'indefinido'; fi
}
ac_pol_media() { # -> fora | zero | indefinido  (o que o nulo faz na media)
  if   ac_tem_re "$1" "$AC_RE_ZERO" && ! ac_tem_re "$1" "$AC_RE_NULO_NAO_ZERO"; then printf 'zero'
  elif ac_tem_re "$1" "$AC_RE_MEDIA_ELEG"; then printf 'fora'
  else printf 'indefinido'; fi
}
ac_pol_base() { # -> elegiveis | encerradas | indefinido  (o que o limiar conta)
  if   ac_tem_re "$1" "$AC_RE_LIM_ELEG"; then printf 'elegiveis'
  elif ac_tem_re "$1" "$AC_RE_LIM_ENC";  then printf 'encerradas'
  else printf 'indefinido'; fi
}
ac_pol_limiar() { # -> o numero de elegiveis que liga o fator, ou indefinido
  local v
  v="$(ac_txt "$1" | grep -oE "$AC_RE_LIM_ELEG" | grep -oE '[0-9]+' | sort -u | tr '\n' ' ' | sed 's/ *$//')"
  case "$v" in ''|*' '*) printf 'indefinido' ;; *) printf '%s' "$v" ;; esac
}
ac_pol_forma() { # -> por_contador | indefinido  (item presente decidido pelo contador)
  if ac_tem_re "$1" "$AC_RE_FORMA"; then printf 'por_contador'; else printf 'indefinido'; fi
}

# A politica da ARVORE: valor unico entre os pontos que o declaram. Ponto calado nao vota (os casos
# de texto cobram cada ponto um a um), mas DOIS pontos discordando da `indefinido` — contrato que se
# contradiz nao fixa numero nenhum, e e exatamente a forma do defeito B2.
ac_pol_arvore() { # ac_pol_arvore <dir> <contador|media|base|limiar|forma>
  local d="$1" dim="$2" f v vals="" u
  for f in $AC_REL_DEFINEM; do
    [ -f "$d/$f" ] || continue
    case "$dim" in
      contador) v="$(ac_pol_contador "$d/$f")" ;;
      media)    v="$(ac_pol_media "$d/$f")" ;;
      base)     v="$(ac_pol_base "$d/$f")" ;;
      limiar)   v="$(ac_pol_limiar "$d/$f")" ;;
      forma)    v="$(ac_pol_forma "$d/$f")" ;;
    esac
    [ "$v" = indefinido ] || vals="$vals $v"
  done
  u="$(printf '%s\n' $vals | sort -u | tr '\n' ' ' | sed 's/^ *//; s/ *$//')"
  case "$u" in ''|*' '*) printf 'indefinido' ;; *) printf '%s' "$u" ;; esac
}

# O ORACULO. Dada a lista de `desvio` de um tipo (`null` inclusive) e as politicas, devolve o que o
# HISTORICO.md grava: contador, `desvio_medio` (duas casas, half-up — D-10), `fator_ativo` e a forma
# do item. Politica indefinida produz `indefinido`, nunca um palpite: e assim que a ausencia de
# contrato aparece como numero errado, e nao como palavra faltando.
ac_num() { # ac_num <desvios> <contador> <media> <base> <limiar> <forma>
  awk -v lista="$1" -v pc="$2" -v pm="$3" -v pb="$4" -v lim="$5" -v pf="$6" '
    function arr(x,  s, i) { s = x * 100; i = int(s); if (s - i >= 0.5) i++; return sprintf("%.2f", i / 100) }
    BEGIN {
      n = split(lista, v, / +/)
      for (i = 1; i <= n; i++) {
        if (v[i] == "") continue
        nt++                                         # encerradas: toda entrada da lista
        if (v[i] != "null") { ne++; soma += v[i] }    # elegiveis: `desvio` numerico
      }
      # `ne + 0` e `nt + 0`: sem elegivel nenhuma, `ne` nunca foi atribuida e `%s` imprimiria a
      # string vazia no lugar do contador `0` — o cenario da `calibracao: []`.
      contador = (pc == "numerico") ? ne + 0 : ((pc == "encerradas") ? nt + 0 : "indefinido")
      if      (pm == "fora") media = (ne > 0) ? arr(soma / ne) : "sem"
      else if (pm == "zero") media = (nt > 0) ? arr(soma / nt) : "sem"
      else                   media = "indefinido"
      base = (pb == "elegiveis") ? ne : ((pb == "encerradas") ? nt : -1)
      fator = (base < 0 || lim == "indefinido") ? "indefinido" : ((base >= lim + 0) ? "true" : "false")
      if (pf != "por_contador" || contador == "indefinido") forma = "indefinido"
      else forma = (contador + 0 >= 1) ? "item" : "vazia"
      printf "%s %s %s %s", contador, media, fator, forma
    }'
}
# Os quatro cenarios do defeito, todos do mesmo `tipo_task`, com nulas sempre presentes.
AC_A='1.20 1.30 null null'        # 2 elegiveis + 2 nulas
AC_B='1.20 1.30 1.30 null null'   # 3 elegiveis + 2 nulas
AC_C='1.25 null'                  # 1 elegivel  + 1 nula
AC_D='null null'                  # nenhuma elegivel
AC_CANONICO='2 1.25 false item; 3 1.27 true item; 1 1.25 false item; 0 sem false vazia'
ac_quatro() { # ac_quatro <contador> <media> <base> <limiar> <forma> -> as quatro ternas, A a D
  printf '%s; %s; %s; %s' "$(ac_num "$AC_A" "$@")" "$(ac_num "$AC_B" "$@")" \
                          "$(ac_num "$AC_C" "$@")" "$(ac_num "$AC_D" "$@")"
}
ac_cenarios() { # ac_cenarios <dir> -> as quatro ternas sob a politica LIDA daquela arvore
  local d="$1"
  ac_quatro "$(ac_pol_arvore "$d" contador)" "$(ac_pol_arvore "$d" media)" \
            "$(ac_pol_arvore "$d" base)"     "$(ac_pol_arvore "$d" limiar)" \
            "$(ac_pol_arvore "$d" forma)"
}

# 1. Dados literais que SEPARAM as duas leituras. Sem isto, "contar ou nao contar as nulas" seria
#    discussao de vocabulario: nas MESMAS quatro entradas, a leitura elegivel grava
#    `entradas: 2 / 1.25 / false` e a leitura "encerradas, nulo como zero" grava
#    `entradas: 4 / 0.63 / true`. Contador, numero e chave booleana divergem, e o fator liga.
AC_SO_ELEG="$(ac_quatro numerico fora elegiveis 3 por_contador)"
AC_SO_ELEG_A="$(ac_num "$AC_A" numerico fora elegiveis 3 por_contador)"
AC_COM_NULOS_A="$(ac_num "$AC_A" encerradas zero encerradas 3 por_contador)"
[ "$AC_SO_ELEG_A" = '2 1.25 false item' ] && [ "$AC_COM_NULOS_A" = '4 0.63 true item' ] \
  && [ "$AC_SO_ELEG_A" != "$AC_COM_NULOS_A" ]; ac_rc=$?
afirma "ac1-nulos-mudam-contador-media-e-fator" "$ac_rc" \
  "elegiveis=[$AC_SO_ELEG_A] contando nulas=[$AC_COM_NULOS_A] sobre [$AC_A]"

# 1b. E o oraculo esta correto nos quatro cenarios, independentemente de qualquer texto: 2
#     elegiveis -> 1,25 e fator desligado; 3 -> 1,27 e fator ligado; 1 -> item presente com fator
#     desligado; nenhuma -> lista vazia. Este caso guarda a aritmetica; os seguintes, o contrato.
[ "$AC_SO_ELEG" = "$AC_CANONICO" ]; ac_rc=$?
afirma "ac1b-oraculo-dos-quatro-cenarios-correto" "$ac_rc" "calculado=[$AC_SO_ELEG]"

# 1c. O limiar e lido, nao embutido: com limiar 2 o cenario A ligaria o fator. E o que o mutante 4
#     faz, e a razao de o oraculo receber o numero em vez de o conhecer.
AC_LIM2_A="$(ac_num "$AC_A" numerico fora elegiveis 2 por_contador)"
[ "$AC_LIM2_A" = '2 1.25 true item' ] && [ "$AC_LIM2_A" != "$AC_SO_ELEG_A" ]; ac_rc=$?
afirma "ac1c-limiar-e-parametro-do-oraculo" "$ac_rc" "limiar 2 no cenario A=[$AC_LIM2_A]"

# A bateria, por ARVORE: a real roda em "$SK" e cada mutante roda a MESMA bateria numa copia.
ac_caso() { # ac_caso <caso> <dir> -> 0 se o caso PASSA naquela arvore
  local c="$1" d="$2" f sujo="" v
  case "$c" in
    # `entradas` conta SO as entradas com `desvio` numerico — a amarracao que o HEAD nao tem.
    ac_entradas_so_desvio_numerico)
      for f in $AC_REL_DEFINEM; do
        v="$(ac_pol_contador "$d/$f")"; [ "$v" = numerico ] || sujo="$sujo $f:$v"
      done
      [ -z "$sujo" ] ;;
    # `desvio_medio` e a media SO sobre essas entradas: o divisor e o numero de elegiveis.
    ac_media_so_desvio_numerico)
      for f in $AC_REL_DEFINEM; do
        v="$(ac_pol_media "$d/$f")"; [ "$v" = fora ] || sujo="$sujo $f:$v"
      done
      [ -z "$sujo" ] ;;
    # E `desvio: null` nunca vale zero: contar como zero e a leitura que produz 0,63 em vez de 1,25
    # sem contrariar frase nenhuma do HEAD.
    ac_nulo_nunca_vale_zero)
      for f in $AC_REL_DEFINEM; do
        ac_tem_re "$d/$f" "$AC_RE_NULO_NAO_ZERO" || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    # O estado nulo e nomeado como tal e posto fora da contagem. Regra escrita so pelo positivo
    # ("conta as numericas") deixa o leitor da entrada sem F3.5 sem resposta: e ela que ele tem.
    ac_nulo_fora_da_contagem)
      for f in $AC_REL_DEFINEM; do
        ac_tem_re "$d/$f" "$AC_RE_NULO_FORA" || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    # O limiar do `fator_ativo` conta elegiveis, nao encerradas...
    ac_limiar_sobre_elegiveis)
      for f in $AC_REL_LIMIAR; do
        v="$(ac_pol_base "$d/$f")"; [ "$v" = elegiveis ] || sujo="$sujo $f:$v"
      done
      [ -z "$sujo" ] ;;
    # ...e continua sendo 3: a regra do fator ja fixou o numero, e a B2 muda a BASE da contagem,
    # nunca o numero.
    ac_limiar_e_tres)
      for f in $AC_REL_LIMIAR; do
        v="$(ac_pol_limiar "$d/$f")"; [ "$v" = 3 ] || sujo="$sujo $f:$v"
      done
      [ -z "$sujo" ] ;;
    # Item PRESENTE com 1 ou 2 elegiveis, com `fator_ativo: false`: a lista vazia e outro estado.
    ac_item_presente_com_poucas_elegiveis)
      for f in $AC_REL_FORMA; do
        [ "$(ac_pol_forma "$d/$f")" = por_contador ] \
          && ac_tem_re "$d/$f" 'fator_ativo: false|fator_ativo (fica|é|e) false' || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    # E `calibracao: []` so sem NENHUMA elegivel. A D-08 fixou a FORMA da lista vazia; aqui se fixa
    # QUANDO ela ocorre — sem isso, "poucas entradas" e "nenhuma entrada" voltam a ser o mesmo caso.
    ac_lista_vazia_so_sem_elegiveis)
      for f in $AC_REL_FORMA; do
        ac_tem_re "$d/$f" "$AC_RE_VAZIA" || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    # O caso semantico: a politica LIDA da arvore, aplicada aos quatro cenarios, produz exatamente
    # o que o canonico grava. Contrato calado ou contraditorio devolve `indefinido`.
    ac_oraculo_numerico)
      v="$(ac_cenarios "$d")"; [ "$v" = "$AC_CANONICO" ] ;;
    # Schema publico intacto: a B2 e correcao de contrato, nao de formato.
    ac_chaves_publicas)
      grep -qF 'entradas:' "$d/references/00-schema.md" \
        && grep -qF 'desvio_medio:' "$d/references/00-schema.md" \
        && grep -qF 'fator_ativo:' "$d/references/00-schema.md" \
        && grep -qF 'entradas:' "$d/assets/TEMPLATE-HISTORICO.md" \
        && grep -qF 'fator_ativo:' "$d/assets/TEMPLATE-HISTORICO.md" ;;
    # E a decisao fica registrada: e onde a proxima sessao encontra o PORQUE de o conjunto agregado
    # ser menor que o conjunto das entradas encerradas.
    # O id e o proximo livre do registro append-only: a DS-163 ja e o piso da faixa agregada
    # (secao Z / D-13), e a decisao da elegibilidade entrou como DS-164.
    ac_ds164)
      v="$(grep -F '| DS-164 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
      [ -n "$v" ] \
        && printf '%s' "$v" | grep -qiE 'elegív|elegiv' \
        && printf '%s' "$v" | grep -qF 'desvio' ;;
    *) return 1 ;;
  esac
}
AC_CASOS="ac_entradas_so_desvio_numerico ac_media_so_desvio_numerico ac_nulo_nunca_vale_zero
ac_nulo_fora_da_contagem ac_limiar_sobre_elegiveis ac_limiar_e_tres
ac_item_presente_com_poucas_elegiveis ac_lista_vazia_so_sem_elegiveis ac_oraculo_numerico
ac_chaves_publicas ac_ds164"

# 2 a 12. A bateria lida das referencias reais. Nome derivado ANTES da condicao e status capturado
#         na linha seguinte (DS-161 / secao AA).
for ac_c in $AC_CASOS; do
  ac_nome="$(printf '%s' "$ac_c" | tr '_' '-')"
  ac_caso "$ac_c" "$SK"; ac_rc=$?
  ac_det="lido da arvore do contrato em $SK"
  [ "$ac_c" = ac_oraculo_numerico ] && ac_det="politica lida=[$(ac_cenarios "$SK")] canonico=[$AC_CANONICO]"
  afirma "$ac_nome" "$ac_rc" "$ac_det"
done

# 13. Mutantes. Mesma mecanica da secao AB: cada um nasce numa COPIA da skill — as referencias reais
#     nunca sao tocadas — e so conta como morto quando TODOS os casos nomeados reprovam. `ac_muta`
#     devolve 0 so quando o arquivo REALMENTE mudou: mutante que nao nasceu nao e mutante morto, e o
#     caso falha dizendo isso.
ACW="$(mktemp -d)"
ac_copia() { rm -rf "$ACW/$1"; mkdir -p "$ACW/$1"; cp -R "$SK/." "$ACW/$1/"; printf '%s' "$ACW/$1"; }
ac_muta() { # ac_muta <dir> <arquivo-rel> <expressao sed>
  [ -f "$1/$2" ] || return 1
  sed -i "$3" "$1/$2" || return 1
  ! cmp -s "$SK/$2" "$1/$2"
}
ac_mata() { local c; for c in $AC_CASOS; do ac_caso "$c" "$1" || { printf '%s' "$c"; return; }; done; }
ac_mutante() { # ac_mutante <nome> <rc da geracao> <dir> <caso que TEM de matar>...
  local nome="$1" rcg="$2" d="$3" c vivos=""; shift 3
  if [ "$rcg" -eq 0 ]; then for c in "$@"; do ac_caso "$c" "$d" && vivos="$vivos$c "; done; fi
  [ "$rcg" -eq 0 ] && [ -z "$vivos" ]; local rc=$?
  afirma "$nome" "$rc" "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rcg)"
}
ac_equivalente() { # ac_equivalente <nome> <rc da geracao> <dir> — equivalente nao pode morrer
  local nome="$1" rcg="$2" d="$3" m=""
  [ "$rcg" -eq 0 ] && m="$(ac_mata "$d")"
  [ "$rcg" -eq 0 ] && [ -z "$m" ]; local rc=$?
  afirma "$nome" "$rc" "equivalente, nao conta como morto; reprovou=[${m:-nenhum}] (rc geracao=$rcg)"
}
AC_CTL="$(ac_copia controle)"
AC_K="$(ac_mata "$AC_CTL")"; [ -z "$AC_K" ]; ac_rc=$?
afirma "acm-controle-copia-intacta-sobrevive" "$ac_rc" "${AC_K:-nenhum caso reprova a copia sem mutacao}"

# m1 — contar nulos no limiar: a base do `fator_ativo` volta a ser "entradas encerradas". E o
#      defeito do HEAD isolado no limiar: com 2 elegiveis e 2 nulas, o fator LIGA.
AC_M="$(ac_copia m1)"
ac_muta "$AC_M" references/00-schema.md 's/ou mais entradas elegíveis/ou mais entradas encerradas/g'
ac_mutante "acm-mutante-1-limiar-conta-nulos" $? "$AC_M" \
  ac_limiar_sobre_elegiveis ac_limiar_e_tres ac_oraculo_numerico

# m2 — nulo tratado como zero na media: o contador pode ate ficar certo, e `desvio_medio` cai de
#      1,25 para 0,63. E a leitura que o HEAD permite sem contrariar frase nenhuma.
AC_M="$(ac_copia m2)"
ac_muta "$AC_M" references/06-execucao.md 's/nunca como zero/conta como zero/g'
ac_mutante "acm-mutante-2-nulo-como-zero-na-media" $? "$AC_M" \
  ac_media_so_desvio_numerico ac_nulo_nunca_vale_zero ac_oraculo_numerico

# m3 — o item com 1 ou 2 elegiveis apagado: a forma do item presente desaparece do template e
#      "poucas entradas" volta a se confundir com `calibracao: []`.
AC_M="$(ac_copia m3)"
ac_muta "$AC_M" assets/TEMPLATE-HISTORICO.md '/1 ou 2 entradas elegíveis/d'
ac_mutante "acm-mutante-3-item-com-poucas-apagado" $? "$AC_M" \
  ac_item_presente_com_poucas_elegiveis

# m4 — fator ativo com 2 elegiveis: a base continua certa, o numero desce. Dois desvios reais
#      passam a ligar o fator de correcao de um tipo inteiro.
AC_M="$(ac_copia m4)"
ac_muta "$AC_M" references/00-schema.md 's/3 ou mais entradas elegíveis/2 ou mais entradas elegíveis/g'
ac_mutante "acm-mutante-4-fator-com-duas-elegiveis" $? "$AC_M" \
  ac_limiar_e_tres ac_oraculo_numerico

# Equivalentes: mudam a marcacao e nao a regra, e por isso NAO podem morrer — um oraculo que
# dependesse da grafia de uma palavra passaria por discriminante sem ser.
AC_M="$(ac_copia e1)"
ac_muta "$AC_M" assets/TEMPLATE-HISTORICO.md 's/`desvio` numérico/**`desvio` numérico**/g'
ac_equivalente "ace-equivalente-1-marcacao-do-desvio-numerico" $? "$AC_M"
AC_M="$(ac_copia e2)"
ac_muta "$AC_M" references/00-schema.md 's/entradas elegíveis/entradas **elegíveis**/g'
ac_equivalente "ace-equivalente-2-marcacao-do-elegivel" $? "$AC_M"
rm -rf "$ACW"

echo "== AD. o leitor da F3.5 confere o bloco \`calibracao\` persistido contra o canonico, nunca aplica as cegas (PR#10 c.4161807476) =="
# A DS-164 (secao AC) fixou QUAIS entradas a calibracao agrega. Ficou aberto o que o leitor da F3.5
# faz quando o bloco `calibracao` GRAVADO nao e o que essa regra produziria — por exemplo, uma linha
# gravada por uma sessao anterior a DS-164, que contava `desvio: null` como zero. O Passo 1 da
# 07-estimativa.md mandava aplicar "o desvio_medio persistido... sem recalcular nada a partir das
# entradas": um bloco stale era aplicado com a MESMA confianca de um bloco correto, e nada na saida
# avisava a diferenca. A DS-165 fecha isso: o leitor CONFERE o bloco gravado contra o canonico
# (recomputado so dos `desvio` persistidos, nunca de `real / estimado_media`); bate, aplica o
# persistido; diverge, aplica o canonico recomputado, declara a divergencia na saida, marca a
# origem do fator efetivamente aplicado, e o teto de confianca desce a `media`. A F3.5 nunca
# escreve nem migra o HISTORICO.md — so a F6 regrava `calibracao` no fechamento.
# Detector por MARCADOR LITERAL — nunca regex de linguagem natural. Cada regra da DS-165 e uma
# string EXATA, copiada do proprio texto do contrato: se a frase que a carrega for reescrita, o
# marcador tem de ser atualizado junto (o que e o comportamento certo), e se for apagada ou trocada
# por um mutante, a string some e o caso reprova — sem janela de proximidade, sem classe de
# caractere acentuada (que num `grep` baseado em ugrep estoura "complexity limits" e devolve falso
# negativo silencioso), sem depender de a frase caber numa unica linha fisica do markdown.
ad_lit() { # ad_lit <arquivo1> <marcador1> [<arquivo2> <marcador2> ...] -> 0 se TODOS os pares batem
  # Marcador prefixado com "!" inverte o sentido: o caso so passa se essa string NAO estiver no
  # arquivo — usado para proibir a regressao a uma frase antiga que um paragrafo vizinho corrigido
  # deixaria sobreviver sem isso (ex.: "fator e sempre o persistido" ao lado de uma conferencia
  # que já existe, mas antes do fix, em outro paragrafo do MESMO arquivo).
  python3 - "$@" <<'PYEOF'
import sys

args = sys.argv[1:]
pares = list(zip(args[0::2], args[1::2]))

cache = {}
def normalizado(caminho):
    if caminho not in cache:
        try:
            with open(caminho, encoding="utf-8") as fh:
                # so colapsa espaco em branco (quebra de linha fisica inclusive) para uma frase
                # que o markdown fisicamente quebrou em duas linhas continuar casando como uma —
                # nao e regex, e concatenacao: o marcador em si tambem usa espaco simples.
                cache[caminho] = " ".join(fh.read().split())
        except OSError:
            cache[caminho] = None
    return cache[caminho]

def falhou(caminho, marcador):
    t = normalizado(caminho)
    if marcador.startswith("!"):
        proibido = marcador[1:]
        return t is None or proibido in t
    return t is None or marcador not in t

faltando = [(f, m) for f, m in pares if falhou(f, m)]
if faltando:
    print("marcador ausente/proibido-presente:", faltando, file=sys.stderr)
sys.exit(0 if not faltando else 1)
PYEOF
}

# Os marcadores, um por regra da decisao do comentario 4161807476 — exatamente como aparecem no
# arquivo (espaco simples entre palavras; ad_lit normaliza quebras de linha fisicas do mesmo jeito
# antes de procurar).
AD_LIT_CONFERE_07='Confira esse canônico contra o bloco `calibracao` gravado no `HISTORICO.md`.'
AD_LIT_CONFERE_00='O leitor da F3.5 (Passo 1) sempre **confere** o bloco `calibracao` gravado contra esse canônico antes de usar'
AD_LIT_DIVERGE_07='Declare na saída, nesta task e no total, a divergência encontrada'
AD_LIT_DIVERGE_00='e declara a divergência na saída'
AD_LIT_PROIBE_07='**A F3.5 nunca escreve nem migra o `HISTORICO.md`.**'
AD_LIT_PROIBE_00='A F3.5 **nunca** escreve nem migra o `HISTORICO.md`'
AD_LIT_PROIBE_HIST='A F3.5 (`references/07-estimativa.md`) nunca escreve nem migra o `HISTORICO.md`'
AD_LIT_CALIBRACAO_07A='A origem da calibração (DS-165) é `persistido`.'
AD_LIT_CALIBRACAO_07B='a origem da calibração é `recomputado`'
AD_LIT_CALIBRACAO_00A='**persistido** quando o leitor confere e bate contra o bloco `calibracao` gravado'
AD_LIT_CALIBRACAO_00B='**recomputado** quando diverge'
AD_LIT_CALIBRACAO_TMPL='Origem da calibração (DS-165): {{persistido | recomputado | nenhum — canônico sem fator ativo}}'
# O rotulo do campo de prosa e "Origem da calibração" — nunca "Origem do fator": um dos tres
# estados (`nenhum — canônico sem fator ativo`) nao e origem de fator nenhum, entao o nome do
# campo nao pode pressupor que sempre existe um fator. Marcador negativo: proibe a regressao.
AD_LIT_ROTULO_ANTIGO_TMPL='!Origem do fator (DS-165)'
# Os TRES estados do campo "Divergência encontrada" — o terceiro (`HISTORICO.md` ausente) nao e
# nem "confere" nem "diverge": sem o arquivo nao ha bloco `calibracao` nenhum para comparar.
AD_LIT_DIVERGE_AUSENTE_TMPL='não se aplica — HISTORICO.md ausente'
AD_LIT_DIVERGE_AUSENTE_07='não se aplica — HISTORICO.md ausente'
AD_LIT_DIVERGE_AUSENTE_00='não se aplica — HISTORICO.md ausente'
AD_LIT_CONFIANCA_07='Uma divergência detectada **reduz o teto de confiança a `media`**'
AD_LIT_CONFIANCA_00='também limita `confianca` a `media`'
AD_LIT_RAZAO_07='nunca de `real / estimado_media`, que é a razão bruta e não o que a calibração agrega'
AD_LIT_RAZAO_00='nunca a média das razões brutas `real / estimado_media`'
AD_LIT_LIMIAR_00='3 ou mais entradas elegíveis'
# O TEMPLATE-ESTIMATIVA.md tinha dois paragrafos contraditorios: um dizia "o fator e o
# desvio_medio persistido... copiado como esta" (sem condicao nenhuma), o seguinte ja descrevia a
# conferencia (DS-165). "canônico vigente" e o MESMO marcador que 07-estimativa.md e 00-schema.md
# ja usam para "o fator e condicional, persistido OU recomputado" — reaproveitado aqui em vez de
# um quarto texto, para a mesma ideia ter uma unica frase-ancora nos tres documentos.
AD_LIT_CANONICO_VIGENTE_TMPL='canônico vigente'
AD_LIT_SEMPRE_PERSISTIDO_TMPL='!persistido do tipo, copiado do `HISTORICO.md` como está'
# O TERCEIRO ESTADO da origem: nem `persistido` nem `recomputado` cobrem "o canonico nao tem
# fator ativo" (menos de 3 entradas elegiveis, ou sem HISTORICO.md) — e forcar um dos dois ali e
# inventar uma origem para um fator que nao existe (`fator_correcao_aplicado: null` com origem
# `persistido`/`recomputado` e contradicao direta). O rotulo e o MESMO marcador nos 3 documentos.
AD_LIT_SEM_FATOR_07='nenhum — canônico sem fator ativo'
AD_LIT_SEM_FATOR_00='nenhum — canônico sem fator ativo'
AD_LIT_SEM_FATOR_TMPL='nenhum — canônico sem fator ativo'
# E o rotulo se aplica mesmo quando o bloco STALE divergente MENTE que tem fator ativo — a
# fixture `api` (2 elegiveis, canonico desliga, stale divergente dizia `fator_ativo: true` com 4
# entradas) e exatamente esse cenario: divergencia presente, mas sem fator a aplicar.
AD_LIT_SEM_FATOR_MESMO_SE_STALE_MENTE='mesmo que o bloco gravado divergente dissesse `fator_ativo: true`'

# O ORACULO da divergencia. Dado o conjunto de `desvio` persistidos de um tipo e o bloco STALE
# gravado (entradas, desvio_medio, fator_ativo), devolve o canonico (DS-164: so elegiveis, media
# half-up, fator a partir de 3), se diverge do stale, o fator EFETIVAMENTE aplicado e a origem.
ad_num() { # ad_num <desvios> <stale_entradas> <stale_media> <stale_fator_ativo>
  awk -v lista="$1" -v se="$2" -v sm="$3" -v sf="$4" '
    function arr(x,  s, i) { s = x * 100; i = int(s); if (s - i >= 0.5) i++; return sprintf("%.2f", i / 100) }
    BEGIN {
      n = split(lista, v, / +/)
      for (i = 1; i <= n; i++) { if (v[i] == "") continue; if (v[i] != "null") { ne++; soma += v[i] } }
      ce = ne + 0
      cm = (ne > 0) ? arr(soma / ne) : "sem"
      cf = (ne >= 3) ? "true" : "false"
      dv = (se != ce || sm != cm || sf != cf) ? "true" : "false"
      # A origem depende do CANONICO (cf), nunca da divergencia isolada: com `fator_ativo: false`
      # nao ha fator nenhum para ter sido persistido OU recomputado — e o terceiro estado da
      # DS-165, independente de bater ou divergir do bloco stale.
      if (cf == "true") { fv = cm; org = (dv == "true") ? "recomputado" : "persistido" }
      else              { fv = "null"; org = "nenhum — canônico sem fator ativo" }
      printf "%s %s %s %s %s %s", ce, cm, cf, dv, fv, org
    }'
}
# As duas fixtures do PR#10 c.4161807476, ambas do mesmo `tipo_task`, com a quinta/quarta nula.
AD_API='1.20 1.30 null null'                  # canonico: 2 elegiveis, stale conta as nulas como zero
AD_INTEG='1.13 1.13 1.17 1.20 null'           # canonico: 4 elegiveis (DS-160); stale conta 5
AD_CTRL='1.20 1.30 1.30'                      # 3 elegiveis, stale JA bate com o canonico

# 1. O oraculo distingue as quatro grandezas do caso: `0.93` (stale, descartado), `1.16`
#    (canonico, efetivamente aplicado), `1.15` (razao bruta — NUNCA pode aparecer como aplicado) e
#    a recusa indevida de todo fator (NAO pode sair `null` com o canonico `fator_ativo: true`).
AD_INTEG_CALC="$(ad_num "$AD_INTEG" 5 0.93 true)"
[ "$AD_INTEG_CALC" = '4 1.16 true true 1.16 recomputado' ]; ad_rc=$?
afirma "ad1-oraculo-distingue-stale-canonico-e-razao-bruta" "$ad_rc" \
  "calculado=[$AD_INTEG_CALC] — 0,93 descartado, 1,16 aplicado (nunca 1,15), fator nao recusado"

# 1b. O outro cenario do PR#10: stale conta nulas como zero e LIGA o fator (2 elegiveis < 3); o
#     canonico desliga. Sem conferencia, o fator errado ficaria ligado sobre 2 desvios reais.
AD_API_CALC="$(ad_num "$AD_API" 4 0.63 true)"
[ "$AD_API_CALC" = '2 1.25 false true null nenhum — canônico sem fator ativo' ]; ad_rc=$?
afirma "ad1b-oraculo-desliga-fator-quando-canonico-tem-menos-de-3" "$ad_rc" "calculado=[$AD_API_CALC]"

# 1c. E quando o bloco gravado JA bate com o canonico, nao ha divergencia nenhuma: a origem e
#     `persistido`, sem qualquer recomputo — a conferencia nao inventa divergencia onde nao ha.
AD_CTRL_CALC="$(ad_num "$AD_CTRL" 3 1.27 true)"
[ "$AD_CTRL_CALC" = '3 1.27 true false 1.27 persistido' ]; ad_rc=$?
afirma "ad1c-sem-divergencia-origem-e-persistido" "$ad_rc" "calculado=[$AD_CTRL_CALC]"

# A bateria, por ARVORE: a real roda em "$SK" e cada mutante roda a MESMA bateria numa copia.
ad_caso() { # ad_caso <caso> <dir> -> 0 se o caso PASSA naquela arvore
  local c="$1" d="$2"
  case "$c" in
    # O leitor confere o bloco persistido contra o canonico antes de aplicar — nao aplica as cegas.
    ad_conferencia_contra_canonico)
      ad_lit "$d/references/07-estimativa.md" "$AD_LIT_CONFERE_07" \
             "$d/references/00-schema.md"     "$AD_LIT_CONFERE_00" ;;
    # A divergencia, quando existe, vai declarada na saida — nunca escondida pelo recomputo.
    ad_divergencia_declarada_na_saida)
      ad_lit "$d/references/07-estimativa.md" "$AD_LIT_DIVERGE_07" \
             "$d/references/00-schema.md"     "$AD_LIT_DIVERGE_00" ;;
    # A F3.5 so le; a cura do bloco calibracao fica para o fechamento (F6).
    ad_f35_nunca_escreve_historico)
      ad_lit "$d/references/07-estimativa.md"     "$AD_LIT_PROIBE_07" \
             "$d/references/00-schema.md"         "$AD_LIT_PROIBE_00" \
             "$d/assets/TEMPLATE-HISTORICO.md"    "$AD_LIT_PROIBE_HIST" ;;
    # `fator_correcao_aplicado`/a saida marcam a ORIGEM do fator efetivamente aplicado — as duas
    # palavras, persistido e recomputado, tem de aparecer: apagar uma delas quebra o par.
    ad_origem_do_fator_declarada)
      ad_lit "$d/references/07-estimativa.md" "$AD_LIT_CALIBRACAO_07A" \
             "$d/references/07-estimativa.md" "$AD_LIT_CALIBRACAO_07B" \
             "$d/references/00-schema.md"     "$AD_LIT_CALIBRACAO_00A" \
             "$d/references/00-schema.md"     "$AD_LIT_CALIBRACAO_00B" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AD_LIT_CALIBRACAO_TMPL" ;;
    # O rotulo do campo de prosa e "Origem da calibração", nunca "Origem do fator" — um dos tres
    # estados nao e origem de fator nenhum.
    ad_rotulo_origem_da_calibracao)
      ad_lit "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AD_LIT_CALIBRACAO_TMPL" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AD_LIT_ROTULO_ANTIGO_TMPL" ;;
    # Os TRES estados de "Divergência encontrada": confere, diverge com valores, e o terceiro —
    # HISTORICO.md ausente, sem bloco `calibracao` nenhum para comparar.
    ad_tres_estados_divergencia)
      ad_lit "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AD_LIT_DIVERGE_AUSENTE_TMPL" \
             "$d/references/07-estimativa.md"   "$AD_LIT_DIVERGE_AUSENTE_07" \
             "$d/references/00-schema.md"       "$AD_LIT_DIVERGE_AUSENTE_00" ;;
    # Divergencia detectada reduz o teto de confianca a `media`, mesmo com fator canonico ativo.
    ad_divergencia_reduz_confianca)
      ad_lit "$d/references/07-estimativa.md" "$AD_LIT_CONFIANCA_07" \
             "$d/references/00-schema.md"     "$AD_LIT_CONFIANCA_00" ;;
    # O recomputo da divergencia nunca parte da razao bruta `real / estimado_media` — so dos
    # `desvio` ja persistidos (a mesma fronteira da DS-162, aplicada ao caso da divergencia).
    ad_nunca_razao_bruta_na_divergencia)
      ad_lit "$d/references/07-estimativa.md" "$AD_LIT_RAZAO_07" \
             "$d/references/00-schema.md"     "$AD_LIT_RAZAO_00" ;;
    # O limiar do canonico recomputado continua 3 (DS-162/DS-164) — a divergencia corrige o
    # CONJUNTO lido, nunca o numero do limiar.
    ad_limiar_tres_no_canonico)
      ad_lit "$d/references/00-schema.md" "$AD_LIT_LIMIAR_00" ;;
    # A DS-165 fica registrada, append-only, citando divergencia, canonico e recomputo.
    ad_ds165_registrada)
      local v; v="$(grep -F '| DS-165 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
      [ -n "$v" ] && printf '%s' "$v" | grep -qiF 'diverg' \
        && printf '%s' "$v" | grep -qiF 'canônic' \
        && printf '%s' "$v" | grep -qiF 'recomputad' ;;
    # O TEMPLATE-ESTIMATIVA.md NAO pode voltar a dizer que o fator e sempre o persistido copiado
    # as cegas — a frase que contradizia a conferencia da DS-165 no paragrafo vizinho.
    ad_fator_nao_e_sempre_persistido)
      ad_lit "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AD_LIT_CANONICO_VIGENTE_TMPL" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AD_LIT_SEMPRE_PERSISTIDO_TMPL" ;;
    # O contrato define os TRES estados da origem — persistido, recomputado, e `nenhum — canonico
    # sem fator ativo` —, e o terceiro vale mesmo quando o bloco STALE divergente MENTE que tem
    # fator ativo (a fixture `api`: canonico desliga, stale divergente dizia `fator_ativo: true`).
    # So dois estados, ou o terceiro sem essa ressalva, obriga a inventar uma origem para um fator
    # que nao existe.
    ad_terceiro_estado_sem_fator_ativo)
      ad_lit "$d/references/07-estimativa.md"     "$AD_LIT_SEM_FATOR_07" \
             "$d/references/00-schema.md"         "$AD_LIT_SEM_FATOR_00" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md"   "$AD_LIT_SEM_FATOR_TMPL" \
             "$d/references/07-estimativa.md"     "$AD_LIT_SEM_FATOR_MESMO_SE_STALE_MENTE" ;;
    *) return 1 ;;
  esac
}
AD_CASOS="ad_conferencia_contra_canonico ad_divergencia_declarada_na_saida
ad_f35_nunca_escreve_historico ad_origem_do_fator_declarada ad_divergencia_reduz_confianca
ad_nunca_razao_bruta_na_divergencia ad_limiar_tres_no_canonico ad_ds165_registrada
ad_fator_nao_e_sempre_persistido ad_terceiro_estado_sem_fator_ativo
ad_rotulo_origem_da_calibracao ad_tres_estados_divergencia"

# 2 a 9. A bateria lida das referencias reais.
for ad_c in $AD_CASOS; do
  ad_nome="$(printf '%s' "$ad_c" | tr '_' '-')"
  ad_caso "$ad_c" "$SK"; ad_rc=$?
  afirma "$ad_nome" "$ad_rc" "lido da arvore do contrato em $SK"
done

# 10. Mutantes. Mesma mecanica das secoes AB/AC: cada um nasce numa COPIA da skill, e so conta como
#     morto quando TODOS os casos nomeados reprovam.
ADW="$(mktemp -d)"
ad_copia() { rm -rf "$ADW/$1"; mkdir -p "$ADW/$1"; cp -R "$SK/." "$ADW/$1/"; printf '%s' "$ADW/$1"; }
ad_muta() { # ad_muta <dir> <arquivo-rel> <expressao sed>
  [ -f "$1/$2" ] || return 1
  sed -i "$3" "$1/$2" || return 1
  ! cmp -s "$SK/$2" "$1/$2"
}
ad_mata() { local c; for c in $AD_CASOS; do ad_caso "$c" "$1" || { printf '%s' "$c"; return; }; done; }
ad_mutante() { # ad_mutante <nome> <rc da geracao> <dir> <caso que TEM de matar>...
  local nome="$1" rcg="$2" d="$3" c vivos=""; shift 3
  if [ "$rcg" -eq 0 ]; then for c in "$@"; do ad_caso "$c" "$d" && vivos="$vivos$c "; done; fi
  [ "$rcg" -eq 0 ] && [ -z "$vivos" ]; local rc=$?
  afirma "$nome" "$rc" "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rcg)"
}
ad_equivalente() { # ad_equivalente <nome> <rc da geracao> <dir> — equivalente nao pode morrer
  local nome="$1" rcg="$2" d="$3" m=""
  [ "$rcg" -eq 0 ] && m="$(ad_mata "$d")"
  [ "$rcg" -eq 0 ] && [ -z "$m" ]; local rc=$?
  afirma "$nome" "$rc" "equivalente, nao conta como morto; reprovou=[${m:-nenhum}] (rc geracao=$rcg)"
}
AD_CTL="$(ad_copia controle)"
AD_K="$(ad_mata "$AD_CTL")"; [ -z "$AD_K" ]; ad_rc=$?
afirma "adm-controle-copia-intacta-sobrevive" "$ad_rc" "${AD_K:-nenhum caso reprova a copia sem mutacao}"

# m1 — aplicar o bloco stale sem conferir: apaga o marcador da CONFERENCIA no Passo 1, voltando
#      a ler "como esta, sem recalcular nada" — exatamente o HEAD que o PR#10 reportou.
AD_M="$(ad_copia m1)"
ad_muta "$AD_M" references/07-estimativa.md \
  's/Confira esse canônico contra o bloco `calibracao` gravado no `HISTORICO\.md`\.//'
ad_mutante "adm-mutante-1-aplica-stale-sem-conferir" $? "$AD_M" \
  ad_conferencia_contra_canonico

# m2 — recomputar sempre e ocultar a divergencia: apaga so o marcador que obriga DECLARAR na saida.
AD_M="$(ad_copia m2)"
ad_muta "$AD_M" references/07-estimativa.md \
  's/Declare na saída, nesta task e no total, a divergência encontrada/Resolva a divergência em silêncio/'
ad_mutante "adm-mutante-2-oculta-divergencia" $? "$AD_M" \
  ad_divergencia_declarada_na_saida

# m3 — recusar todo fator na divergencia: apaga o marcador que nomeia `recomputado` como origem
#      possivel, como se divergencia so pudesse zerar o fator (nunca recompute-lo).
AD_M="$(ad_copia m3)"
ad_muta "$AD_M" references/07-estimativa.md \
  's/a origem da calibração é `recomputado`/o fator fica `null`/'
ad_mutante "adm-mutante-3-recusa-fator-na-divergencia" $? "$AD_M" \
  ad_origem_do_fator_declarada

# m4 — recomputar a partir da razao bruta: apaga o marcador que proibe `real / estimado_media`
#      no recomputo da divergencia.
AD_M="$(ad_copia m4)"
ad_muta "$AD_M" references/07-estimativa.md \
  's/ — nunca de `real \/ estimado_media`, que é a razão bruta e não o que a calibração agrega//'
ad_mutante "adm-mutante-4-recomputa-de-razao-bruta" $? "$AD_M" \
  ad_nunca_razao_bruta_na_divergencia

# m5 — a F3.5 escreve/migra o HISTORICO.md: apaga o marcador da proibicao, confundindo fase de
#      leitura com fase de fechamento.
AD_M="$(ad_copia m5)"
ad_muta "$AD_M" references/07-estimativa.md \
  's/\*\*A F3\.5 nunca escreve nem migra o `HISTORICO\.md`\.\*\* //'
ad_mutante "adm-mutante-5-f35-escreve-historico" $? "$AD_M" \
  ad_f35_nunca_escreve_historico

# m6 — limiar 2 no canonico recomputado: apaga o marcador "3 ou mais entradas elegíveis" do
#      schema — o mesmo defeito da AC, agora sobre o numero que a divergencia tem de respeitar.
AD_M="$(ad_copia m6)"
ad_muta "$AD_M" references/00-schema.md 's/3 ou mais entradas elegíveis/2 ou mais entradas elegíveis/g'
ad_mutante "adm-mutante-6-limiar-dois-no-recomputo" $? "$AD_M" \
  ad_limiar_tres_no_canonico

# m7 — a DS-165 apagada do registro: a regra fica nas referencias e perde o porque, exatamente
#      como a m9 da AC fez com a DS-162.
AD_M="$(ad_copia m7)"
ad_muta "$AD_M" DECISOES-DA-SKILL.md '/^| DS-165 |/d'
ad_mutante "adm-mutante-7-ds165-apagada" $? "$AD_M" \
  ad_ds165_registrada

# m8 — regressao ao "sempre persistido": o TEMPLATE-ESTIMATIVA.md volta a afirmar, sem condicao
#      nenhuma, que o fator e o persistido copiado como esta — a contradicao que a auditoria achou
#      entre o paragrafo do fator e o paragrafo vizinho da conferencia (DS-165).
AD_M="$(ad_copia m8)"
ad_muta "$AD_M" assets/TEMPLATE-ESTIMATIVA.md \
  's/O fator é o `desvio_medio` do \*\*canônico vigente\*\* daquele tipo (DS-165, ver parágrafo seguinte) — persistido quando o bloco `calibracao` confere, recomputado quando diverge —, nunca o bloco gravado copiado às cegas/O fator é o `desvio_medio` persistido do tipo, copiado do `HISTORICO.md` como está/'
ad_mutante "adm-mutante-8-template-volta-a-sempre-persistido" $? "$AD_M" \
  ad_fator_nao_e_sempre_persistido

# m9 — colapsa o terceiro estado: a origem `nenhum — canônico sem fator ativo` vira
#      `recomputado` em 07-estimativa.md, como se o canonico sem fator ativo tivesse que forcar
#      uma das duas origens antigas — a exata contradicao que a fixture `api` expos (fator
#      `null` com origem `recomputado` nao faz sentido nenhum).
AD_M="$(ad_copia m9)"
ad_muta "$AD_M" references/07-estimativa.md \
  's/nenhum — canônico sem fator ativo/recomputado/g'
ad_mutante "adm-mutante-9-colapsa-terceiro-estado" $? "$AD_M" \
  ad_terceiro_estado_sem_fator_ativo

# m10 — reverte o rotulo do campo de prosa para "Origem do fator": presume que todo estado e
#       origem de um fator que existe, o que e falso para o terceiro estado.
AD_M="$(ad_copia m10)"
ad_muta "$AD_M" assets/TEMPLATE-ESTIMATIVA.md \
  's/Origem da calibração (DS-165)/Origem do fator (DS-165)/'
ad_mutante "adm-mutante-10-reverte-rotulo-origem-do-fator" $? "$AD_M" \
  ad_rotulo_origem_da_calibracao

# m11 — colapsa o terceiro estado de "Divergência encontrada": sem HISTORICO.md volta a nao ter
#       um marcador proprio, como se a ausencia do arquivo fosse so mais um caso de "confere".
AD_M="$(ad_copia m11)"
ad_muta "$AD_M" assets/TEMPLATE-ESTIMATIVA.md \
  's/não se aplica — HISTORICO\.md ausente/nenhuma — o bloco `calibracao` gravado confere com o canônico/'
ad_mutante "adm-mutante-11-colapsa-tres-estados-divergencia" $? "$AD_M" \
  ad_tres_estados_divergencia

# Equivalentes: mudam a forma e nao a regra (texto FORA de todo marcador), e por isso NAO podem
# morrer — um discriminador por marcador que dependesse de frase vizinha passaria por sensivel
# sem ser.
AD_M="$(ad_copia e1)"
ad_muta "$AD_M" references/07-estimativa.md \
  's/herança de uma leitura que contava a entrada/herança de uma leitura antiga que contava a entrada/'
ad_equivalente "ade-equivalente-1-reformulacao-do-exemplo" $? "$AD_M"
AD_M="$(ad_copia e2)"
ad_muta "$AD_M" assets/TEMPLATE-ESTIMATIVA.md \
  's/o canônico recomputado das entradas elegíveis é <valor canônico>/o canônico vigente das entradas elegíveis é <valor canônico>/'
ad_equivalente "ade-equivalente-2-reformulacao-do-placeholder" $? "$AD_M"
rm -rf "$ADW"

echo "== AE. a estimativa declara o fator por tipo_task, nunca um fator unico sobre mistura (PR#10 r4161807465) =="
# O TEMPLATE-ESTIMATIVA.md so tinha `fator_correcao_aplicado` (DS-46/DS-165): um UNICO numero ou
# null para o trabalho inteiro. Um trabalho com tasks de dois tipos — um com fator ativo, outro
# sem, ou dois tipos com fatores ativos DIFERENTES — nao tem como representar isso num escalar
# sem inventar (media, maior, ultimo tipo lido...). A DS-166 acrescenta `calibracao_por_tipo`:
# uma linha por `tipo_task` PRESENTE no trabalho, em ordem lexical, cada uma com seu fator (ou
# null), origem e divergencia (DS-165, agora por tipo). O escalar legado so sobrevive puro
# (numero ou null) quando todos os tipos presentes concordam; qualquer mistura grava o literal
# `por_tipo`, e um consumidor que nao conhece a colecao nova falha fechado — nunca aproxima.
AE_SK="$SK"
AE_SCH="$AE_SK/references/00-schema.md"
AE_EST="$AE_SK/references/07-estimativa.md"
AE_TPL="$AE_SK/assets/TEMPLATE-ESTIMATIVA.md"

# O ORACULO do escalar: dado o conjunto de fatores (um por tipo PRESENTE, "null" quando o tipo
# nao tem fator ativo), devolve o que `fator_correcao_aplicado` tem de gravar.
ae_escalar() { # ae_escalar <fator1> [<fator2> ...]
  awk -v lista="$*" '
    BEGIN {
      n = split(lista, v, / +/)
      ativos = 0; distintos = 0; primeiro = ""
      for (i = 1; i <= n; i++) {
        if (v[i] == "null") { nulos++; continue }
        ativos++
        if (primeiro == "") primeiro = v[i]
        else if (v[i] != primeiro) distintos = 1
      }
      if (ativos == 0) { print "null"; exit }
      if (ativos == n && distintos == 0) { print primeiro; exit }
      print "por_tipo"
    }'
}
[ "$(ae_escalar 1.16 null)" = "por_tipo" ]; afirma "ae1-oraculo-ativo-e-inativo-e-por-tipo" $? \
  "fator presente + tipo sem fator -> mistura"
[ "$(ae_escalar 1.16 1.25)" = "por_tipo" ]; afirma "ae2-oraculo-dois-ativos-distintos-e-por-tipo" $? \
  "dois fatores ativos diferentes -> mistura"
[ "$(ae_escalar 1.16 1.16)" = "1.16" ]; afirma "ae3-oraculo-mesmo-ativo-em-todos-e-escalar" $? \
  "todos os tipos com o mesmo fator ativo -> escalar numerico igual ao fator"
[ "$(ae_escalar null null)" = "null" ]; afirma "ae4-oraculo-nenhum-ativo-e-null" $? \
  "nenhum tipo com fator ativo -> escalar null"
[ "$(ae_escalar 1.16)" = "1.16" ]; afirma "ae5-oraculo-um-unico-tipo-ativo-e-o-proprio-fator" $? \
  "um unico tipo presente, ativo -> escalar e o fator dele, nao e mistura"

# Detector por marcador literal, mesma tecnica e mesma justificativa da secao AD (ad_lit): string
# exata do contrato, nunca regex de linguagem natural, para nao ter falso negativo acentuado.
AE_LIT_SCH_CAMPO='`calibracao_por_tipo`'
AE_LIT_SCH_UMALINHA='exatamente uma linha por `tipo_task` presente, em ordem lexical'
AE_LIT_SCH_ESCALAR_NUM='escalar numérico somente quando TODOS os tipos presentes recebem o MESMO fator ativo'
AE_LIT_SCH_ESCALAR_NULL='escalar `null` somente quando NENHUM tipo presente recebe fator ativo'
AE_LIT_SCH_POR_TIPO='qualquer mistura — fator ativo e inativo, ou fatores ativos diferentes — grava `fator_correcao_aplicado: por_tipo`'
# A DS-172 trocou o SENTIDO desta regra: o proibido e `1.00` NO LUGAR DE `null` (o disfarce da
# DS-46), nunca o valor `1.00` em si — que, medido, e fator legitimo e obrigatorio. O marcador
# acompanha: a secao AK e que julga as duas metades da regra nova.
AE_LIT_SCH_NUNCA_100='Nenhum item de `calibracao_por_tipo` usa `1.00` no lugar de `null`'
AE_LIT_SCH_FAILCLOSED='declara a estimativa indisponível e não a usa — nunca coerção, média ou escolha arbitrária'
AE_LIT_TPL_CAMPO='calibracao_por_tipo:'
AE_LIT_TPL_TABELA='Calibração por tipo de task'
AE_LIT_TPL_PORTASK_COLUNA='Fator aplicado'
AE_LIT_EST_PISO_POR_TIPO='`fator(t)` vem do item de `calibracao_por_tipo` cujo `tipo_task` é o de `t`'
AE_LIT_EST_FAILCLOSED='declara a estimativa indisponível e não a usa — nunca coerção, média ou escolha arbitrária'
# Os valores de `origem`/`divergencia` em `calibracao_por_tipo` sao os MESMOS estados da DS-165
# (canonico, acentuados) — nunca uma forma ASCII sem acento inventada so para este campo novo.
# Marcador POSITIVO e a linha exata do YAML (exemplo real e template), e NEGATIVO proibe a forma
# sem acento aparecer em lugar nenhum dos dois arquivos (auditoria Codex, incompatibilidade de
# enum achada entre o exemplo e a regra canonica DS-165/DS-166).
AE_LIT_SCH_ORIGEM_FRONT='origem: nenhum — canônico sem fator ativo'
AE_LIT_SCH_DIVERG_FRONT='divergencia: não se aplica — HISTORICO.md ausente'
AE_LIT_TPL_ORIGEM_FRONT='origem: {{persistido | recomputado | nenhum — canônico sem fator ativo}}'
AE_LIT_TPL_DIVERG_FRONT='divergencia: {{confere | diverge com valores | não se aplica — HISTORICO.md ausente}}'
AE_LIT_PROIBE_CANONICO_SEM_ACENTO='!nenhum — canonico sem fator ativo'
AE_LIT_PROIBE_DIVERGE_SEM_ACENTO='!nao se aplica — HISTORICO.md ausente'

ae_caso() { # ae_caso <caso> <dir> -> 0 se o caso PASSA naquela arvore
  local c="$1" d="$2"
  case "$c" in
    # A colecao canonica existe no contrato e na saida, uma linha por tipo, ordem lexical.
    ae_colecao_por_tipo_no_contrato)
      ad_lit "$d/references/00-schema.md" "$AE_LIT_SCH_CAMPO" \
             "$d/references/00-schema.md" "$AE_LIT_SCH_UMALINHA" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AE_LIT_TPL_CAMPO" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AE_LIT_TPL_TABELA" ;;
    # A regra dos tres estados do escalar legado esta escrita no schema.
    ae_regra_do_escalar_legado)
      ad_lit "$d/references/00-schema.md" "$AE_LIT_SCH_ESCALAR_NUM" \
             "$d/references/00-schema.md" "$AE_LIT_SCH_ESCALAR_NULL" \
             "$d/references/00-schema.md" "$AE_LIT_SCH_POR_TIPO" ;;
    # `1.00` nunca substitui `null`, nem no escalar nem por tipo (DS-46, com o sentido que a
    # DS-172 fixou: o disfarce e que e proibido, nao o numero).
    ae_nunca_100_por_tipo)
      ad_lit "$d/references/00-schema.md" "$AE_LIT_SCH_NUNCA_100" ;;
    # Consumidor legado que nao reconhece calibracao_por_tipo falha fechado.
    ae_fail_closed_consumidor_legado)
      ad_lit "$d/references/00-schema.md" "$AE_LIT_SCH_FAILCLOSED" \
             "$d/references/07-estimativa.md" "$AE_LIT_EST_FAILCLOSED" ;;
    # A tabela "Por task" identifica o fator/estado aplicado a cada task, nao so o tipo.
    ae_tabela_por_task_identifica_fator)
      ad_lit "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AE_LIT_TPL_PORTASK_COLUNA" ;;
    # O piso aditivo (DS-163) usa o fator do TIPO de cada task, lido da colecao por tipo.
    ae_piso_aditivo_por_tipo)
      ad_lit "$d/references/07-estimativa.md" "$AE_LIT_EST_PISO_POR_TIPO" ;;
    # origem/divergencia de calibracao_por_tipo usam as formas CANONICAS acentuadas da DS-165,
    # no exemplo do schema e no template, e a forma sem acento nunca aparece em nenhum dos dois.
    ae_formas_acentuadas_no_frontmatter)
      ad_lit "$d/references/00-schema.md"       "$AE_LIT_SCH_ORIGEM_FRONT" \
             "$d/references/00-schema.md"       "$AE_LIT_SCH_DIVERG_FRONT" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AE_LIT_TPL_ORIGEM_FRONT" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AE_LIT_TPL_DIVERG_FRONT" \
             "$d/references/00-schema.md"       "$AE_LIT_PROIBE_CANONICO_SEM_ACENTO" \
             "$d/references/00-schema.md"       "$AE_LIT_PROIBE_DIVERGE_SEM_ACENTO" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AE_LIT_PROIBE_CANONICO_SEM_ACENTO" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AE_LIT_PROIBE_DIVERGE_SEM_ACENTO" ;;
    # A DS-166 fica registrada, append-only, citando a mistura e o literal por_tipo.
    ae_ds166_registrada)
      local v; v="$(grep -F '| DS-166 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
      [ -n "$v" ] && printf '%s' "$v" | grep -qiF 'por_tipo' \
        && printf '%s' "$v" | grep -qiF 'mistura' ;;
    *) return 1 ;;
  esac
}
AE_CASOS="ae_colecao_por_tipo_no_contrato ae_regra_do_escalar_legado ae_nunca_100_por_tipo
ae_fail_closed_consumidor_legado ae_tabela_por_task_identifica_fator ae_piso_aditivo_por_tipo
ae_ds166_registrada ae_formas_acentuadas_no_frontmatter"

for ae_c in $AE_CASOS; do
  ae_nome="$(printf '%s' "$ae_c" | tr '_' '-')"
  ae_caso "$ae_c" "$AE_SK"; ae_rc=$?
  afirma "$ae_nome" "$ae_rc" "lido da arvore do contrato em $AE_SK"
done

# DS-166 registrada, append-only (nao reescreve DS-165): nao reafirma pela ae_caso de novo (ja
# roda no loop acima), so confere a DS-165 anterior continua intacta.
grep -qF '| DS-165 |' "$AE_SK/DECISOES-DA-SKILL.md"
afirma "ae-ds165-preservada-append-only" $? "DS-165 continua no arquivo, intacta"

# Mutantes: a mesma mecanica de AD/AC, numa copia da arvore.
AEW="$(mktemp -d)"
ae_copia() { rm -rf "$AEW/$1"; mkdir -p "$AEW/$1"; cp -R "$AE_SK/." "$AEW/$1/"; printf '%s' "$AEW/$1"; }
ae_muta() { [ -f "$1/$2" ] || return 1; sed -i "$3" "$1/$2" || return 1; ! cmp -s "$AE_SK/$2" "$1/$2"; }
ae_mata() { local c; for c in $AE_CASOS; do ae_caso "$c" "$1" || { printf '%s' "$c"; return; }; done; }
ae_mutante() { # ae_mutante <nome> <rc da geracao> <dir> <caso que TEM de matar>...
  local nome="$1" rcg="$2" d="$3" c vivos=""; shift 3
  if [ "$rcg" -eq 0 ]; then for c in "$@"; do ae_caso "$c" "$d" && vivos="$vivos$c "; done; fi
  [ "$rcg" -eq 0 ] && [ -z "$vivos" ]; local rc=$?
  afirma "$nome" "$rc" "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rcg)"
}
AE_CTL="$(ae_copia controle)"
AE_K="$(ae_mata "$AE_CTL")"; [ -z "$AE_K" ]; ae_rc=$?
afirma "aem-controle-copia-intacta-sobrevive" "$ae_rc" "${AE_K:-nenhum caso reprova a copia sem mutacao}"

# m1 — remove a colecao canonica do schema: so o escalar legado sobra.
AE_M="$(ae_copia m1)"
ae_muta "$AE_M" references/00-schema.md "s/${AE_LIT_SCH_CAMPO}//"
ae_mutante "aem-mutante-1-remove-colecao-do-schema" $? "$AE_M" \
  ae_colecao_por_tipo_no_contrato

# m2 — remove a regra do escalar numerico (deixa so null/por_tipo descritos).
AE_M="$(ae_copia m2)"
ae_muta "$AE_M" references/00-schema.md "s/${AE_LIT_SCH_ESCALAR_NUM}//"
ae_mutante "aem-mutante-2-remove-regra-escalar-numerico" $? "$AE_M" \
  ae_regra_do_escalar_legado

# m3 — apaga a proibicao do disfarce por tipo: `1.00` voltaria a poder substituir `null`.
AE_M="$(ae_copia m3)"
ae_muta "$AE_M" references/00-schema.md "s/${AE_LIT_SCH_NUNCA_100}//"
ae_mutante "aem-mutante-3-permite-100-no-lugar-de-null-por-tipo" $? "$AE_M" \
  ae_nunca_100_por_tipo

# m4 — apaga a instrucao de falha fechada para consumidor legado (ex.: ele poderia tentar media).
AE_M="$(ae_copia m4)"
ae_muta "$AE_M" references/00-schema.md "s/${AE_LIT_SCH_FAILCLOSED}//"
ae_mutante "aem-mutante-4-remove-fail-closed" $? "$AE_M" \
  ae_fail_closed_consumidor_legado

# m5 — apaga a coluna de fator aplicado da tabela "Por task" (so sobra o tipo, sem o fator/estado).
AE_M="$(ae_copia m5)"
ae_muta "$AE_M" assets/TEMPLATE-ESTIMATIVA.md "s/${AE_LIT_TPL_PORTASK_COLUNA}//"
ae_mutante "aem-mutante-5-remove-coluna-fator-por-task" $? "$AE_M" \
  ae_tabela_por_task_identifica_fator

# m6 — colapsa o piso aditivo de volta a um fator unico do conjunto (apaga o vinculo por tipo).
AE_M="$(ae_copia m6)"
ae_muta "$AE_M" references/07-estimativa.md "s/${AE_LIT_EST_PISO_POR_TIPO}//"
ae_mutante "aem-mutante-6-piso-sem-vinculo-por-tipo" $? "$AE_M" \
  ae_piso_aditivo_por_tipo

# m7 — DS-166 apagada do registro.
AE_M="$(ae_copia m7)"
ae_muta "$AE_M" DECISOES-DA-SKILL.md '/^| DS-166 |/d'
ae_mutante "aem-mutante-7-ds166-apagada" $? "$AE_M" \
  ae_ds166_registrada

# m8 — corrompe a forma acentuada do exemplo no schema de volta para ASCII sem acento, a
# incompatibilidade de enum que a auditoria Codex achou entre o exemplo e a regra canonica.
AE_M="$(ae_copia m8)"
ae_muta "$AE_M" references/00-schema.md \
  's/origem: nenhum — canônico sem fator ativo/origem: nenhum — canonico sem fator ativo/'
ae_mutante "aem-mutante-8-origem-sem-acento-no-exemplo" $? "$AE_M" \
  ae_formas_acentuadas_no_frontmatter

rm -rf "$AEW"

echo "== AF. PR#11 r4164972140/r4164972143: agregacao corrigida pelo fator (DS-167) e escalar legado condicional (DS-168) =="
# r4164972143 (Logic error): a formula publicada de media_conjunto/desvio_conjunto somava os
# valores CRUS de media_task/desvio_padrao_task — so o piso_conjunto multiplicava por fator(t).
# `max`, que nao passa pelo piso, saia sem fator nenhum: fator aplicado so parcialmente. A DS-167
# corrige multiplicando por fator(t) DENTRO da soma/quadratura, nos dois arquivos que publicam a
# formula (07-estimativa.md e TEMPLATE-ESTIMATIVA.md) — sem renomear media_task/desvio_padrao_task
# (DS-162 continua intacta).
# r4164972140 (Api mismatch): o bloco "escalar legado" exigia Origem/Divergencia (DS-165) como
# UM valor do trabalho inteiro, mas com mais de um tipo_task (DS-166) nao ha agregado — cada tipo
# tem a sua. A DS-168 torna as duas linhas condicionais ao trabalho ter um unico tipo_task, e
# manda OMITI-LAS (nunca inventar "misto") quando ha mais de um.
AF_SK="$SK"
AF_LIT_AGREG_EST='media_conjunto = soma de ( media_task(t) * fator(t) )'
AF_LIT_AGREG_TPL='media_conjunto = soma de ( media_task(t) * fator(t) )'
AF_LIT_QUAD_EST='desvio_conjunto = raiz_quadrada( soma de ( desvio_padrao_task(t) * fator(t) )^2 )'
AF_LIT_DS167_EST='A agregação soma e quadratura já corrigidos, nunca os valores crus (DS-167)'
AF_LIT_DS167_TPL='A soma e a quadratura já corrigem pelo fator, nunca os valores crus (DS-167)'
AF_LIT_CONDICIONAL_UM='Com um único `tipo_task` presente neste trabalho, declare também'
AF_LIT_CONDICIONAL_MAIS='não existe origem nem divergência agregada para o trabalho inteiro'
AF_LIT_FAILCLOSED_ESCALAR='nunca escolha uma entre os tipos, nunca escreva "misto" ou "vários" no lugar de um valor do enum'
AF_LIT_PASSO9_DS168='não há origem nem divergência agregada do trabalho (DS-168)'

af_caso() { # af_caso <caso> <dir> -> 0 se o caso PASSA naquela arvore
  local c="$1" d="$2"
  case "$c" in
    # A soma e a quadratura multiplicam por fator(t) DENTRO da formula, nos dois arquivos.
    af_agregacao_corrigida_pelo_fator)
      ad_lit "$d/references/07-estimativa.md"   "$AF_LIT_AGREG_EST" \
             "$d/references/07-estimativa.md"   "$AF_LIT_QUAD_EST" \
             "$d/references/07-estimativa.md"   "$AF_LIT_DS167_EST" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AF_LIT_AGREG_TPL" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AF_LIT_DS167_TPL" ;;
    # media_task/desvio_padrao_task continuam os simbolos crus do Passo 4 (DS-162 intacta): a
    # formula crua NUNCA desaparece, so a formula do CONJUNTO passa a multiplicar por fator(t).
    af_simbolos_crus_preservados)
      ad_lit "$d/references/07-estimativa.md"   'media_task = (o + 4m + p) / 6' \
             "$d/references/07-estimativa.md"   'desvio_padrao_task = (p - o) / 6' \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" 'media_task = (o + 4m + p) / 6' \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" 'desvio_padrao_task = (p - o) / 6' ;;
    # O escalar legado so exige Origem/Divergencia quando ha um UNICO tipo_task; com mais de um,
    # manda OMITIR — nunca agregar.
    af_escalar_legado_condicional)
      ad_lit "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AF_LIT_CONDICIONAL_UM" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AF_LIT_CONDICIONAL_MAIS" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AF_LIT_FAILCLOSED_ESCALAR" \
             "$d/references/07-estimativa.md"   "$AF_LIT_PASSO9_DS168" ;;
    # DS-167 e DS-168 ficam registradas, append-only, sem reescrever a DS-166.
    af_ds167_ds168_registradas)
      local v167 v168
      v167="$(grep -F '| DS-167 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
      v168="$(grep -F '| DS-168 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
      [ -n "$v167" ] && [ -n "$v168" ] \
        && printf '%s' "$v167" | grep -qiF 'parcialmente' \
        && printf '%s' "$v168" | grep -qiF 'omitid' ;;
    *) return 1 ;;
  esac
}
AF_CASOS="af_agregacao_corrigida_pelo_fator af_simbolos_crus_preservados
af_escalar_legado_condicional af_ds167_ds168_registradas"

for af_c in $AF_CASOS; do
  af_nome="$(printf '%s' "$af_c" | tr '_' '-')"
  af_caso "$af_c" "$AF_SK"; af_rc=$?
  afirma "$af_nome" "$af_rc" "lido da arvore do contrato em $AF_SK"
done
grep -qF '| DS-166 |' "$AF_SK/DECISOES-DA-SKILL.md"
afirma "af-ds166-preservada-append-only" $? "DS-166 continua no arquivo, intacta"

AFW="$(mktemp -d)"
af_copia() { rm -rf "$AFW/$1"; mkdir -p "$AFW/$1"; cp -R "$AF_SK/." "$AFW/$1/"; printf '%s' "$AFW/$1"; }
af_muta() { [ -f "$1/$2" ] || return 1; sed -i "$3" "$1/$2" || return 1; ! cmp -s "$AF_SK/$2" "$1/$2"; }
af_mata() { local c; for c in $AF_CASOS; do af_caso "$c" "$1" || { printf '%s' "$c"; return; }; done; }
af_mutante() { # af_mutante <nome> <rc da geracao> <dir> <caso que TEM de matar>...
  local nome="$1" rcg="$2" d="$3" c vivos=""; shift 3
  if [ "$rcg" -eq 0 ]; then for c in "$@"; do af_caso "$c" "$d" && vivos="$vivos$c "; done; fi
  [ "$rcg" -eq 0 ] && [ -z "$vivos" ]; local rc=$?
  afirma "$nome" "$rc" "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rcg)"
}
AF_CTL="$(af_copia controle)"
AF_K="$(af_mata "$AF_CTL")"; [ -z "$AF_K" ]; af_rc=$?
afirma "afm-controle-copia-intacta-sobrevive" "$af_rc" "${AF_K:-nenhum caso reprova a copia sem mutacao}"

# m1 — volta a formula do conjunto a somar os valores CRUS (sem fator), o defeito original do
#      comentario r4164972143: max deixa de ser corrigido, so o piso continua corrigido.
AF_M="$(af_copia m1)"
af_muta "$AF_M" references/07-estimativa.md \
  's/media_conjunto  = soma de ( media_task(t) \* fator(t) )/media_conjunto  = soma das media_task/'
af_mutante "afm-mutante-1-agregacao-volta-a-somar-cru-no-07" $? "$AF_M" \
  af_agregacao_corrigida_pelo_fator

# m2 — mesma regressao, agora no TEMPLATE-ESTIMATIVA.md (o arquivo que a auditoria apontou).
AF_M="$(af_copia m2)"
af_muta "$AF_M" assets/TEMPLATE-ESTIMATIVA.md \
  's/media_conjunto  = soma de ( media_task(t) \* fator(t) )/media_conjunto  = soma das media_task/'
af_mutante "afm-mutante-2-agregacao-volta-a-somar-cru-no-template" $? "$AF_M" \
  af_agregacao_corrigida_pelo_fator

# m3 — apaga a condicao "unico tipo" do escalar legado: as duas linhas voltam a parecer sempre
#      obrigatorias, o defeito original do comentario r4164972140.
AF_M="$(af_copia m3)"
af_muta "$AF_M" assets/TEMPLATE-ESTIMATIVA.md \
  "s/${AF_LIT_CONDICIONAL_UM}/Declare sempre/"
af_mutante "afm-mutante-3-remove-condicao-unico-tipo" $? "$AF_M" \
  af_escalar_legado_condicional

# m4 — apaga a instrucao de OMITIR com mais de um tipo (o consumidor voltaria a esperar um
#      valor agregado que o contrato nao define).
AF_M="$(af_copia m4)"
af_muta "$AF_M" assets/TEMPLATE-ESTIMATIVA.md "s/${AF_LIT_CONDICIONAL_MAIS}//"
af_mutante "afm-mutante-4-remove-omissao-com-mais-de-um-tipo" $? "$AF_M" \
  af_escalar_legado_condicional

# m5 — DS-167/DS-168 apagadas do registro.
AF_M="$(af_copia m5)"
af_muta "$AF_M" DECISOES-DA-SKILL.md '/^| DS-167 |/d; /^| DS-168 |/d'
af_mutante "afm-mutante-5-ds167-ds168-apagadas" $? "$AF_M" \
  af_ds167_ds168_registradas

rm -rf "$AFW"

echo "== AG. suite_executada.detalhe corta em 120 BYTES sem partir UTF-8, com e sem jq (5533410/bb1378f) =="
# `cut -c1-120` nao serve para cortar o detalhe de `suite_executada`, por dois motivos
# independentes:
#
#   1. o comportamento de `-c` (byte ou caractere) depende da locale do processo que roda o
#      hook, que o hook nao controla. Sem locale UTF-8 o corte e por byte e deixa a sequencia
#      multibyte do limite INCOMPLETA: o byte-lider (0xC3, no defeito observado) fica pendurado
#      sem o byte de continuacao (0x80-0xBF) que ele anuncia, e o jsonl do trabalho deixa de ser
#      UTF-8 valido — o contrato expx-eventos exige UTF-8 valido, e o painel para de decodificar
#      o arquivo inteiro a partir dali (visto em docs/eventos/sem-trabalho.jsonl);
#   2. `cut` corta LINHA POR LINHA. Comando de suite multilinha passa inteiro, com cada linha
#      cortada em 120 — o detalhe estoura o limite em vez de respeita-lo.
#
# O corte certo e sempre por byte, com a sequencia incompleta do fim removida INTEIRA
# (`rastro_corta_utf8_em`). Cada caso monta um comando de suite com prefixo ASCII de (120-k)
# bytes e o caractere de <largura> bytes repetido, de forma que o limite de 120 caia exatamente
# depois de k bytes do primeiro desses caracteres:
#
#   k <  largura -> sequencia incompleta no fim: tem de sumir inteira
#   k == largura -> sequencia completa terminando NO byte 120: tem de ser preservada (guarda
#                   contra aparar demais, e o unico papel desses casos)
#
# O oraculo le o jsonl GRAVADO pelo hook real (nao a funcao isolada) como UTF-8 estrito e JSON
# estrito, e compara o `detalhe` com o valor exato esperado, medindo o limite em BYTES, que e a
# unidade do contrato. As duas rotas de leitura do payload sao exercidas: com jq (processo) e no
# fallback sem jq (builtin) — e por elas que o comando chega ao corte.
AG_T="$(mktemp -d)"
AG_H="$(cd "$H" && pwd)"
AG_JSONL="$AG_T/repo/docs/eventos/sem-trabalho.jsonl"

# Um PATH equivalente ao atual, sem nenhum `jq` executavel: mesma tecnica da secao W (espelho de
# symlinks dos diretorios que tem jq), com espelho proprio porque a secao W apaga o dela no fim.
ag_path_sem_jq() {
  local d f espelho novo="" i=0 IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    if [ -x "$d/jq" ]; then
      i=$((i+1)); espelho="$AG_T/bin$i"
      if [ ! -d "$espelho" ]; then
        mkdir -p "$espelho"
        for f in "$d"/*; do
          [ -e "$f" ] || continue
          [ "${f##*/}" = jq ] && continue
          ln -sf "$f" "$espelho/${f##*/}" 2>/dev/null
        done
      fi
      novo="$novo:$espelho"
    else
      novo="$novo:$d"
    fi
  done
  printf '%s' "${novo#:}"
}
AG_SEMJQ="$(ag_path_sem_jq)"

# Fixture minima, como na secao Q: raiz com .git e docs/eventos. Sem reivindicacao de sessao no
# rastro, o destino do evento e docs/eventos/sem-trabalho.jsonl (DS-155) — o arquivo do defeito.
ag_roda() { # ag_roda <comando> <PATH do caso> [resposta da ferramenta]
  rm -rf "$AG_T/repo"; mkdir -p "$AG_T/repo/.git" "$AG_T/repo/docs/eventos"
  python3 -c "
import json, sys
print(json.dumps({'cwd': sys.argv[1], 'tool_name': 'Bash', 'tool_input': {'command': sys.argv[2]}, 'tool_response': sys.argv[3]}))
" "$AG_T/repo" "$1" "${3-}" > "$AG_T/payload.json"
  (cd "$AG_T/repo" && PATH="$2" bash "$AG_H/comum/rastro-post.sh") < "$AG_T/payload.json" >/dev/null 2>&1
}
ag_confere() { # ag_confere <detalhe esperado> — jsonl UTF-8 estrito, JSON estrito, detalhe exato
  AG_ESPERADO="$1" python3 - "$AG_JSONL" 2>"$AG_T/erro" <<'PY'
import json, os, sys
bruto = open(sys.argv[1], 'rb').read()
texto = bruto.decode('utf-8')  # UnicodeDecodeError se sobrou byte UTF-8 invalido
linhas = [l for l in texto.splitlines() if l.strip()]
assert len(linhas) == 1, 'esperava 1 linha no jsonl, veio %d' % len(linhas)
evento = json.loads(linhas[0])  # falha se a linha nao for JSON valido
assert evento['evento'] == 'suite_executada', 'evento gravado: %r' % evento['evento']
detalhe = evento['detalhe']
tam = len(detalhe.encode('utf-8'))
assert tam <= 120, 'detalhe com %d bytes, o limite e 120' % tam
esperado = os.environ['AG_ESPERADO']
assert detalhe == esperado, 'detalhe=%r (%d bytes) esperado=%r' % (detalhe, tam, esperado)
PY
}
ag_erro() { tr '\n' ' ' < "$AG_T/erro" | tail -c 180; }
ag_caso() { # ag_caso <nome> <char> <largura> <k> <rota> <PATH do caso>
  local nome="$1" ch="$2" largura="$3" k="$4" rota="$5" caminho="$6" enchimento prefixo esperado rc det
  # "npm test -- " tem 12 bytes, logo 108-k de enchimento fecham os 120-k do prefixo. A troca de
  # espaco por `x` e so no enchimento: em "npm test -- " ela desfaria o padrao de suite do hook.
  printf -v enchimento '%*s' "$((108 - k))" ''
  prefixo="npm test -- ${enchimento// /x}"
  if [ "$k" -eq "$largura" ]; then esperado="$prefixo$ch"; else esperado="$prefixo"; fi
  ag_roda "$prefixo$ch$ch$ch" "$caminho"
  ag_confere "$esperado"; rc=$?
  if [ "$rc" -eq 0 ]; then det="limite cai depois de $k de $largura bytes; jsonl utf-8, json valido, detalhe exato"
  else det="$(ag_erro)"; fi
  afirma "$nome-$rota" "$rc" "$det"
}
# Comando multilinha vira UMA linha de texto antes do corte, como exige o contrato de `detalhe`.
# Aqui o byte 120 cai no meio do 'a' acentuado da SEGUNDA linha ja normalizada — prova as duas
# coisas de uma vez: as quebras viram espaco e a sequencia incompleta do fim sai.
ag_multilinha() { # ag_multilinha <rota> <PATH do caso>
  local rota="$1" caminho="$2" enchimento l1 l2 l3 cmd esperado rc det
  printf -v enchimento '%*s' 48 ''; l1="npm test -- ${enchimento// /x}"  # 60 bytes
  printf -v l2 '%*s' 58 ''; l2="${l2// /y}"                              # bytes 62..119
  printf -v l3 '%*s' 30 ''; l3="${l3// /z}"                              # depois do limite
  cmd="$l1"$'\n'"$l2"'á'$'\n'"$l3"                                       # 'á' nos bytes 120 e 121
  esperado="$l1 $l2"
  ag_roda "$cmd" "$caminho"
  ag_confere "$esperado"; rc=$?
  if [ "$rc" -eq 0 ]; then det="3 linhas normalizadas em uma: 119 bytes, sem o 'a' acentuado partido"
  else det="$(ag_erro)"; fi
  afirma "ag11-multilinha-normalizado-em-uma-linha-$rota" "$rc" "$det"
}
# O espelho tem de esconder o jq E continuar servindo o resto: espelho vazio (ou apagado) faria
# todos os casos sem jq passarem sem rodar nada. Na maquina sem jq e no-op, e as duas rotas
# coincidem — como na secao W.
ag_sandbox_valida() {
  PATH="$AG_SEMJQ" command -v jq >/dev/null 2>&1 && return 1
  PATH="$AG_SEMJQ" command -v bash >/dev/null 2>&1 || return 1
  PATH="$AG_SEMJQ" command -v grep >/dev/null 2>&1 || return 1
  return 0
}
ag_sandbox_valida; AG_RC=$?
afirma "ag0-sandbox-esconde-jq-e-serve-o-resto" "$AG_RC" "PATH do caso sem jq, com bash e grep"

for AG_ROTA in com-jq sem-jq; do
  AG_PATH="$PATH"; [ "$AG_ROTA" = sem-jq ] && AG_PATH="$AG_SEMJQ"
  ag_caso "ag1-2b-parte-1-de-2"   'á'  2 1 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag2-2b-completo"       'á'  2 2 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag3-3b-parte-1-de-3"   '€'  3 1 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag4-3b-parte-2-de-3"   '€'  3 2 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag5-3b-completo"       '€'  3 3 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag6-4b-parte-1-de-4"   '🚀' 4 1 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag7-4b-parte-2-de-4"   '🚀' 4 2 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag8-4b-parte-3-de-4"   '🚀' 4 3 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag9-4b-completo"       '🚀' 4 4 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag10-ascii-no-limite"  'Z'  1 1 "$AG_ROTA" "$AG_PATH"
  ag_multilinha "$AG_ROTA" "$AG_PATH"
done

# Maven e uma suite suportada. Saidas canonicas de falha nao usam necessariamente a palavra
# `FAIL` isolada: `[ERROR]` e `BUILD FAILURE` tambem precisam gravar resultado `falha`.
ag_roda "mvn test" "$PATH" $'[ERROR] Failed to execute goal\n[INFO] BUILD FAILURE'
python3 - "$AG_JSONL" 2>"$AG_T/erro" <<'PY'
import json, sys
evento = json.loads(open(sys.argv[1], encoding='utf-8').readline())
assert evento['resultado'] == 'falha', 'resultado Maven=%r, esperado falha' % evento['resultado']
PY
AG_RC=$?
afirma "ag12-maven-build-failure-e-falha" "$AG_RC" "[ERROR] e BUILD FAILURE classificam mvn test como falha"

# A correcao mora num lugar so: as duas rotas que EXECUTAM o hook — settings.json do Claude Code
# e o plugin do OpenCode — invocam o mesmo comum/rastro-post.sh, e nenhum hook volta a cortar
# texto com `cut -c` (que e byte ou caractere conforme a locale, e corta linha por linha).
ag_cut_em_codigo() { # usos de `cut -c` em CODIGO de hook (comentario que o cita nao conta)
  grep -rn 'cut -c' "$H/comum" "$H/sprintx" 2>/dev/null | sed 's/^[^:]*:[0-9]*://' | grep -v '^[[:space:]]*#'
}
AG_CUT="$(ag_cut_em_codigo)"; AG_CUT="${AG_CUT//$'\n'/ | }"
AG_ROTA_CC="$(conta "$H/../settings.json" 'comum/rastro-post.sh')"
AG_ROTA_OC="$(conta "$H/../../.opencode/plugin/sprintx.ts" 'comum/rastro-post.sh')"
[ -z "$AG_CUT" ] && [ "$AG_ROTA_CC" -eq 1 ] && [ "$AG_ROTA_OC" -eq 1 ]; AG_RC=$?
afirma "ag13-rotas-compartilham-o-mesmo-hook" "$AG_RC" "rotas para comum/rastro-post.sh: claude-code=$AG_ROTA_CC opencode=$AG_ROTA_OC; cut -c em codigo de hook: ${AG_CUT:-nenhum}"
rm -rf "$AG_T"

echo "== AH. serializacao do rastro: todo controle JSON escapado, marcador sem colisao, falha de escrita nao mascarada (PR#12) =="
# Tres defeitos independentes da serializacao, todos alcancaveis pelo mesmo payload — um comando
# de suite que leva caractere de controle (barra de progresso, cor de terminal, separador de
# registro). O JSON do harness os entrega escapados (U+0001 vira a sequencia de seis bytes que
# comeca em barra-u); o que o rastro fazia com eles e que estava errado:
#
#   1. COLISAO DE MARCADOR. `rastro_json_campo_em` escondia a barra escapada atras do byte 0x01
#      antes de decodificar as sequencias U+XXXX, e devolvia esse marcador a barra no fim. Um
#      U+0001 do proprio payload decodifica para o MESMO byte 0x01: na volta ele virava barra
#      invertida. "a<U+0001>b" saia "a\b" — valor corrompido, e divergente do que o jq entrega
#      na mesma leitura, quebrando a paridade que o contrato promete entre as duas rotas.
#   2. BYTE DE CONTROLE CRU NO JSONL. `rastro_json_escape_em` escapava so barra, aspa, TAB, CR e
#      LF. Todo o resto de U+0000..U+001F ia CRU para dentro da string JSON — e JSON proibe
#      controle cru dentro de string: a linha gravada deixava de ser JSON valido e o leitor do
#      rastro perde o arquivo a partir dali, o mesmo estrago do byte UTF-8 partido da secao AG.
#   3. CLASSIFICACAO DE ESCRITA MASCARADA. `rastro_grava_trabalho` punha `divergente`/`invalido`
#      em RASTRO_GRAVACAO DEPOIS de tentar gravar a linha de diagnostico — por cima do `falha`
#      que a propria tentativa acabara de deixar. Com a gravacao impossivel, o escritor publico
#      da skill anunciava "feche a task aberta do outro trabalho" (codigo 4, contrato) quando o
#      fato era que nada podia ser escrito (codigo 5, ambiente): diagnostico publico com a causa
#      errada, e o unico codigo que avisa o agente que o rastro parou de aceitar linha se perdia.
#
# Nenhum caso escreve a sequencia de escape a mao: os payloads saem de `json.dumps`, que escapa
# controle por obrigacao do proprio formato — e por isso o teste exerce o escape REAL do harness.
AH_T="$(mktemp -d)"
AH_H="$(cd "$H" && pwd)"
AH_SK="$(cd "$H/../skills/sprintx" && pwd)"

# PATH sem jq, mesma tecnica e mesma justificativa das secoes W e AG (espelho de symlinks dos
# diretorios que tem jq), com espelho proprio porque cada secao apaga o seu no fim.
ah_path_sem_jq() {
  local d f espelho novo="" i=0 IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    if [ -x "$d/jq" ]; then
      i=$((i+1)); espelho="$AH_T/bin$i"
      if [ ! -d "$espelho" ]; then
        mkdir -p "$espelho"
        for f in "$d"/*; do
          [ -e "$f" ] || continue
          [ "${f##*/}" = jq ] && continue
          ln -sf "$f" "$espelho/${f##*/}" 2>/dev/null
        done
      fi
      novo="$novo:$espelho"
    else
      novo="$novo:$d"
    fi
  done
  printf '%s' "${novo#:}"
}
AH_SEMJQ="$(ah_path_sem_jq)"
if PATH="$AH_SEMJQ" command -v jq >/dev/null 2>&1; then AH_RC=1
else PATH="$AH_SEMJQ" command -v grep >/dev/null 2>&1; AH_RC=$?
fi
afirma "ah0-sandbox-esconde-jq-e-serve-o-resto" "$AH_RC" "PATH do caso sem jq, com grep"

# Os bytes 0x01..0x1F, todos, menos o NUL — que nao cabe numa variavel de shell e por isso nunca
# chega ao serializador. `printf -v` + `%b` constroem cada byte sem criar processo.
ah_todos_controles() {
  local i c
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31; do
    printf -v c '\\%03o' "$i"; printf '%b' "$c"
  done
}

# Extrator isolado, o mesmo molde da secao W: le a chave pelo helper publico e grava o valor CRU
# num arquivo, para a comparacao nao passar por substituicao de comando (que come byte do fim).
cat > "$AH_T/extrai.sh" <<'SH'
. "$1/comum/rastro.sh"
IFS= read -r -d '' J < "$2"
V="$(rastro_tool_input_get "$J" command)"
printf '%s' "$V" > "$3"
SH
# Serializador isolado: escapa o texto do arquivo e monta UMA string JSON com ele.
cat > "$AH_T/serializa.sh" <<'SH'
. "$1/comum/rastro.sh"
IFS= read -r -d '' TEXTO < "$2"
rastro_json_escape_em E "$TEXTO"
printf '{"detalhe":"%s"}' "$E" > "$3"
SH
# Gravador isolado: o desfecho publico de uma gravacao, como a skill o le (DS-159).
cat > "$AH_T/grava.sh" <<'SH'
. "$1/comum/rastro.sh"
rastro_grava_trabalho "$2" "$3" task_iniciada skill ok "evento de prova" '[]' '"sessao":"seg@1","harness":"seg"'
printf '%s' "${RASTRO_GRAVACAO:-vazio}"
SH

ah_payload() { # ah_payload <arquivo-com-o-comando> <cwd> <arquivo-de-saida>
  python3 -c '
import json, sys
texto = open(sys.argv[1], "rb").read().decode("utf-8")
linha = json.dumps({"cwd": sys.argv[2], "tool_name": "Bash", "tool_input": {"command": texto}})
open(sys.argv[3], "w", encoding="utf-8").write(linha + "\0")
' "$1" "$2" "$3"
}
ah_bytes() { od -An -c < "$1" | tr -s ' \n' ' '; }

# ---------------------------------------------------------------- 1. leitura do payload
ah_leitura() { # ah_leitura <nome> <texto> <detalhe do caso>
  local nome="$1" det="$3" rc
  printf '%s' "$2" > "$AH_T/fonte.txt"
  ah_payload "$AH_T/fonte.txt" /x "$AH_T/payload.json"
  PATH="$AH_SEMJQ" bash "$AH_T/extrai.sh" "$AH_H" "$AH_T/payload.json" "$AH_T/sem.txt"
  bash "$AH_T/extrai.sh" "$AH_H" "$AH_T/payload.json" "$AH_T/com.txt"
  cmp -s "$AH_T/sem.txt" "$AH_T/fonte.txt" && cmp -s "$AH_T/com.txt" "$AH_T/fonte.txt"; rc=$?
  [ "$rc" -eq 0 ] || det="sem-jq=[$(ah_bytes "$AH_T/sem.txt")] com-jq=[$(ah_bytes "$AH_T/com.txt")] esperado=[$(ah_bytes "$AH_T/fonte.txt")]"
  afirma "$nome" "$rc" "$det"
}
printf -v AH_CTRL 'a\001b\002c'
ah_leitura "ah1-controle-sobrevive-nas-duas-rotas" "$AH_CTRL" \
  "U+0001 e U+0002 do payload voltam como os proprios bytes, com jq e sem jq"
printf -v AH_MIX 'd:\\ e a\001b\002c'
ah_leitura "ah2-barra-escapada-e-controle-no-mesmo-valor" "$AH_MIX" \
  "barra invertida literal e controle convivem: nenhum dos dois vira o outro"
printf -v AH_BARRA 'x\\y'
ah_leitura "ah3-barra-escapada-sozinha-nao-regride" "$AH_BARRA" \
  "a barra escapada continua decodificada (guarda contra consertar 1 quebrando 2)"
printf -v AH_BSN 'p\\nq'
ah_leitura "ah4-barra-literal-seguida-de-n-nao-vira-quebra" "$AH_BSN" \
  "barra invertida seguida de 'n' e barra + n, nunca uma quebra de linha"
AH_TODOS="$(ah_todos_controles)"
ah_leitura "ah5-todo-controle-de-0x01-a-0x1f-sobrevive" "$AH_TODOS" \
  "os 31 bytes de controle do payload voltam identicos nas duas rotas"

# O gerador normal acima usa json.dumps. Estes dois casos escrevem o JSON de entrada a mao para
# fixar a fronteira que ele nao consegue distinguir: U+005C seguido de `n`, literal ou codificado
# como outro U+XXXX, tem de virar barra + n — nunca LF. A rota com jq e o fallback sem jq precisam
# devolver exatamente os mesmos dois bytes.
ah_json_manual() { # ah_json_manual <nome> <valor JSON sem aspas> <valor esperado>
  local nome="$1" codificado="$2" esperado="$3" rc det
  printf '{"cwd":"/x","tool_name":"Bash","tool_input":{"command":"%s"}}\0' \
    "$codificado" > "$AH_T/payload-manual.json"
  printf '%s' "$esperado" > "$AH_T/esperado-manual.txt"
  PATH="$AH_SEMJQ" bash "$AH_T/extrai.sh" "$AH_H" "$AH_T/payload-manual.json" "$AH_T/sem-manual.txt"
  bash "$AH_T/extrai.sh" "$AH_H" "$AH_T/payload-manual.json" "$AH_T/com-manual.txt"
  cmp -s "$AH_T/sem-manual.txt" "$AH_T/esperado-manual.txt" \
    && cmp -s "$AH_T/com-manual.txt" "$AH_T/esperado-manual.txt" \
    && cmp -s "$AH_T/sem-manual.txt" "$AH_T/com-manual.txt"; rc=$?
  [ "$rc" -eq 0 ] || det="sem-jq=[$(ah_bytes "$AH_T/sem-manual.txt")] com-jq=[$(ah_bytes "$AH_T/com-manual.txt")] esperado=[$(ah_bytes "$AH_T/esperado-manual.txt")]"
  afirma "$nome" "$rc" "${det:-barra + n literal, igual com jq e sem jq}"
}
ah_json_manual "ah5b-u005c-seguido-de-n-nao-vira-lf" '\u005cn' '\n'
ah_json_manual "ah5c-u005c-e-u006e-nao-viram-lf" '\u005c\u006e' '\n'

# ---------------------------------------------------------------- 2. escrita da string JSON
cat > "$AH_T/confere-json.py" <<'PY'
import json, sys
bruto = open(sys.argv[1], 'rb').read()
cru = sorted(set(b for b in bruto if b < 0x20))
assert not cru, 'byte(s) de controle CRU na string JSON: %r' % cru
valor = json.loads(bruto.decode('utf-8'))['detalhe']   # falha se nao for JSON valido
esperado = open(sys.argv[2], 'rb').read().decode('utf-8')
assert valor == esperado, 'detalhe=%r esperado=%r' % (valor, esperado)
PY
ah_serializa() { # ah_serializa <nome> <texto> <detalhe do caso>
  local nome="$1" det="$3" rc
  printf '%s\0' "$2" > "$AH_T/texto.bin"
  printf '%s' "$2" > "$AH_T/esperado.txt"
  bash "$AH_T/serializa.sh" "$AH_H" "$AH_T/texto.bin" "$AH_T/linha.json"
  python3 "$AH_T/confere-json.py" "$AH_T/linha.json" "$AH_T/esperado.txt" 2>"$AH_T/erro"; rc=$?
  [ "$rc" -eq 0 ] || det="$(tr '\n' ' ' < "$AH_T/erro" | tr -s ' ' | tail -c 200)"
  afirma "$nome" "$rc" "$det"
}
ah_serializa "ah6-serializa-controle-sem-byte-cru" "$AH_CTRL" \
  "U+0001 e U+0002 saem escapados; a string e JSON valido e volta identica"
ah_serializa "ah7-serializa-os-31-controles" "$AH_TODOS" \
  "0x01..0x1F todos escapados, nenhum byte cru, round-trip exato"
printf -v AH_ASPAS 'a"b\\c\011d\012e'
ah_serializa "ah8-aspa-barra-tab-e-quebra-nao-regridem" "$AH_ASPAS" \
  "aspa, barra, TAB e LF continuam escapados (guarda contra regressao do escape antigo)"

# ---------------------------------------------------------------- 3. ponta a ponta pelo hook
# O payload vai ao hook PostToolUse real; o oraculo le o jsonl GRAVADO como UTF-8 estrito e JSON
# estrito, e confere o `detalhe` byte a byte. A fixture nao tem reivindicacao, entao o destino e
# docs/eventos/sem-trabalho.jsonl (DS-155).
AH_JSONL="$AH_T/repo/docs/eventos/sem-trabalho.jsonl"
cat > "$AH_T/confere-jsonl.py" <<'PY'
import json, sys
bruto = open(sys.argv[1], 'rb').read()
assert bruto.endswith(b'\n'), 'a linha gravada nao termina em LF'
corpo = bruto[:-1]
cru = sorted(set(b for b in corpo if b < 0x20))
assert not cru, 'byte(s) de controle CRU no jsonl: %r' % cru
evento = json.loads(corpo.decode('utf-8'))             # UTF-8 e JSON estritos
assert evento['evento'] == 'suite_executada', 'evento gravado: %r' % evento['evento']
esperado = open(sys.argv[2], 'rb').read().decode('utf-8')
assert evento['detalhe'] == esperado, 'detalhe=%r esperado=%r' % (evento['detalhe'], esperado)
PY
ah_hook() { # ah_hook <nome> <comando> <rota> <PATH do caso>
  local nome="$1" cmd="$2" rota="$3" caminho="$4" rc det
  rm -rf "$AH_T/repo"; mkdir -p "$AH_T/repo/.git" "$AH_T/repo/docs/eventos"
  printf '%s' "$cmd" > "$AH_T/cmd.txt"
  printf '%s' "$cmd" > "$AH_T/esp-hook.txt"
  ah_payload "$AH_T/cmd.txt" "$AH_T/repo" "$AH_T/p-hook.json"
  (cd "$AH_T/repo" && PATH="$caminho" bash "$AH_H/comum/rastro-post.sh") < "$AH_T/p-hook.json" >/dev/null 2>&1
  python3 "$AH_T/confere-jsonl.py" "$AH_JSONL" "$AH_T/esp-hook.txt" 2>"$AH_T/erro"; rc=$?
  if [ "$rc" -eq 0 ]; then det="jsonl utf-8 e json estritos, sem controle cru, detalhe exato"
  else det="$(tr '\n' ' ' < "$AH_T/erro" | tr -s ' ' | tail -c 200)"; fi
  afirma "$nome-$rota" "$rc" "$det"
}
printf -v AH_SUITE 'npm test -- a\001b\002c\011d\033[0me\037f'
for AH_ROTA in com-jq sem-jq; do
  AH_PATH="$PATH"; [ "$AH_ROTA" = sem-jq ] && AH_PATH="$AH_SEMJQ"
  ah_hook "ah9-suite-executada-com-controle-no-comando" "$AH_SUITE" "$AH_ROTA" "$AH_PATH"
done

# ---------------------------------------------------------------- 4. classificacao da gravacao
# A fixture: a sessao `seg@1` reivindica o trabalho `outro`; pedir gravacao em `alvo` cai no ramo
# `divergente`, e pedir num slug torto cai no ramo `invalido`. Os dois tentam gravar a linha de
# diagnostico em docs/eventos/sem-trabalho.jsonl — e e essa tentativa que a fixture faz FALHAR,
# trocando o arquivo por um DIRETORIO de mesmo nome (sem mexer em permissao, que varia de
# plataforma): `printf >>` sobre diretorio nao escreve, e `[ -f ]` o mantem fora da varredura.
# Os dois casos "gravavel" sao o controle: sem eles, um conserto que sempre devolvesse `falha`
# passaria — e `divergente`/`invalido` sao exatamente a informacao que o codigo 4 publica.
ah_fixture() { # ah_fixture <sem-trabalho gravavel: sim|nao>
  rm -rf "$AH_T/g"; mkdir -p "$AH_T/g/.git" "$AH_T/g/docs/eventos"
  mkdir -p "$AH_T/g/docs/sprintx/features/alvo/sprint-01"
  printf '%s\n' '---' 'tasks:' '  - id: T-01.01' '---' \
    > "$AH_T/g/docs/sprintx/features/alvo/sprint-01/tasks.md"
  printf '%s\n' '{"ts":"2026-10-01T10:00:00Z","expx_eventos":1,"trabalho_id":"outro","ferramenta":"sprintx","origem":"skill","evento":"task_iniciada","fase":"f6","task":"T-09.09","agente":"principal","resultado":"ok","detalhe":null,"arquivos":[],"sessao":"seg@1","harness":"seg"}' \
    > "$AH_T/g/docs/eventos/outro.jsonl"
  if [ "$1" = sim ]; then : > "$AH_T/g/docs/eventos/sem-trabalho.jsonl"
  else mkdir -p "$AH_T/g/docs/eventos/sem-trabalho.jsonl"; fi
}
ah_classifica() { # ah_classifica <gravavel> <pedido> -> ecoa RASTRO_GRAVACAO
  ah_fixture "$1"
  (cd "$AH_T/g" && EXPX_SESSAO=seg@1 EXPX_HARNESS=seg \
    bash "$AH_T/grava.sh" "$AH_H" "$AH_T/g" "$2" 2>/dev/null)
}
AH_G="$(ah_classifica sim alvo)"
[ "$AH_G" = divergente ]
afirma "ah10-divergente-continua-divergente-quando-grava" $? "RASTRO_GRAVACAO=$AH_G (esperado divergente)"
AH_G="$(ah_classifica nao alvo)"
[ "$AH_G" = falha ]
afirma "ah11-divergente-sem-poder-gravar-e-falha" $? "RASTRO_GRAVACAO=$AH_G (esperado falha, nao divergente)"
AH_G="$(ah_classifica sim 'fora/do/lugar')"
[ "$AH_G" = invalido ]
afirma "ah12-invalido-continua-invalido-quando-grava" $? "RASTRO_GRAVACAO=$AH_G (esperado invalido)"
AH_G="$(ah_classifica nao 'fora/do/lugar')"
[ "$AH_G" = falha ]
afirma "ah13-invalido-sem-poder-gravar-e-falha" $? "RASTRO_GRAVACAO=$AH_G (esperado falha, nao invalido)"

# E o codigo PUBLICO que o agente le: 5 e "ambiente, nada pode ser escrito"; 4 e "contrato, feche
# a task do outro trabalho". Com a gravacao impossivel, o codigo publico tem de ser 5.
ah_publico() { # ah_publico <gravavel> -> ecoa o codigo de saida do escritor da skill
  local rc
  ah_fixture "$1"
  (cd "$AH_T/g" && SPRINTX_RAIZ="$AH_T/g" EXPX_SESSAO=seg@1 EXPX_HARNESS=seg \
    bash "$AH_SK/scripts/rastro.sh" task-iniciada alvo T-01.01 >/dev/null 2>&1)
  rc=$?; printf '%s' "$rc"
}
AH_RC_PUB="$(ah_publico sim)"
[ "$AH_RC_PUB" = 4 ]
afirma "ah14-escritor-da-skill-diz-4-na-divergencia" $? "exit=$AH_RC_PUB (esperado 4: contrato)"
AH_RC_PUB="$(ah_publico nao)"
[ "$AH_RC_PUB" = 5 ]
afirma "ah15-escritor-da-skill-diz-5-sem-poder-gravar" $? "exit=$AH_RC_PUB (esperado 5: ambiente, nunca 4)"

# ---------------------------------------------------------------- 5. mutantes dos tres contratos
# Copias temporarias do helper real provam que os casos acima nao sao decorativos. Cada mutante
# ressuscita exatamente um dos defeitos: reprocessar escapes curtos depois de U+XXXX, deixar os
# controles exoticos crus e mascarar uma falha de escrita com a classe de contrato.
AH_MUT="$AH_T/mutantes"
ah_copia_rastro() { # ah_copia_rastro <nome> -> ecoa a raiz da copia
  local d="$AH_MUT/$1"
  mkdir -p "$d/comum"
  cp "$AH_H/comum/rastro.sh" "$d/comum/rastro.sh"
  printf '%s' "$d"
}

# m1 — simula a ordem antiga: o resultado de U+XXXX volta a passar pelos escapes curtos.
AH_M1="$(ah_copia_rastro ordem-antiga)"
AH_OLD_ORDER='          _v="$_out" ;;'
IFS= read -r -d '' AH_NEW_ORDER <<'EOF' || true
          _v="${_out//\\n/$'\n'}" ;;
EOF
muta_lit "$AH_M1/comum/rastro.sh" "$AH_M1/comum/rastro.sh.m" "$AH_OLD_ORDER" "$AH_NEW_ORDER" \
  && mv "$AH_M1/comum/rastro.sh.m" "$AH_M1/comum/rastro.sh"
AH_MRC=$?
PATH="$AH_SEMJQ" bash "$AH_T/extrai.sh" "$AH_M1" "$AH_T/payload-manual.json" "$AH_T/m1.txt" 2>/dev/null
[ "$AH_MRC" -eq 0 ] && ! cmp -s "$AH_T/m1.txt" "$AH_T/esperado-manual.txt"; AH_RC=$?
afirma "ahm1-ordem-antiga-morre-no-u005c-u006e" "$AH_RC" \
  "a copia que reprocessa escapes curtos nao devolve barra + n"

# m2 — remove o escape generico que cobre os controles sem forma curta.
AH_M2="$(ah_copia_rastro sem-controle-generico)"
AH_OLD_CTRL='        s="${s//"$_b"/\\u00$_hex}"'
AH_NEW_CTRL='        : # mutante: controle exotico fica cru'
muta_lit "$AH_M2/comum/rastro.sh" "$AH_M2/comum/rastro.sh.m" "$AH_OLD_CTRL" "$AH_NEW_CTRL" \
  && mv "$AH_M2/comum/rastro.sh.m" "$AH_M2/comum/rastro.sh"
AH_MRC=$?
printf '%s\0' "$AH_CTRL" > "$AH_T/m2.bin"
printf '%s' "$AH_CTRL" > "$AH_T/m2-esperado.txt"
bash "$AH_T/serializa.sh" "$AH_M2" "$AH_T/m2.bin" "$AH_T/m2.json" 2>/dev/null
python3 "$AH_T/confere-json.py" "$AH_T/m2.json" "$AH_T/m2-esperado.txt" >/dev/null 2>&1
AH_BAD=$?
[ "$AH_MRC" -eq 0 ] && [ "$AH_BAD" -ne 0 ]; AH_RC=$?
afirma "ahm2-sem-escape-generico-morre-no-json-estrito" "$AH_RC" \
  "a copia deixa U+0001/U+0002 crus e o oraculo JSON estrito reprova"

# m3 — volta a atribuir a classe depois da tentativa de gravacao, apagando `falha`.
AH_M3="$(ah_copia_rastro mascara-falha)"
AH_OLD_FALHA='  [ "${RASTRO_GRAVACAO:-}" = falha ] || RASTRO_GRAVACAO="$1"'
AH_NEW_FALHA='  RASTRO_GRAVACAO="$1"'
muta_lit "$AH_M3/comum/rastro.sh" "$AH_M3/comum/rastro.sh.m" "$AH_OLD_FALHA" "$AH_NEW_FALHA" \
  && mv "$AH_M3/comum/rastro.sh.m" "$AH_M3/comum/rastro.sh"
AH_MRC=$?
ah_fixture nao
AH_MUT_G="$(cd "$AH_T/g" && EXPX_SESSAO=seg@1 EXPX_HARNESS=seg \
  bash "$AH_T/grava.sh" "$AH_M3" "$AH_T/g" alvo 2>/dev/null)"
[ "$AH_MRC" -eq 0 ] && [ "$AH_MUT_G" != falha ]; AH_RC=$?
afirma "ahm3-classe-que-mascara-falha-morre-na-precedencia" "$AH_RC" \
  "a copia devolve $AH_MUT_G em vez de falha, e ah11/ah13 a rejeitam"

rm -rf "$AH_T"

echo "== AI. fechar task e do DONO da reivindicacao; dona indeterminada nao e dona ausente (PR#12, PR#14) =="
# Dois defeitos de ownership no escritor oficial dos eventos de reivindicacao (DS-159):
#
#   1. `task-concluida` e `task-bloqueada` nao olhavam QUEM tem a task aberta. A reivindicacao e
#      o evento `task_iniciada` mais recente sem fechamento depois (DS-150/153) — e um fechamento
#      gravado por OUTRA sessao e, para toda leitura do rastro, o fechamento dela: a sessao dona
#      perdia a reivindicacao sem nunca ter fechado nada, e a primeira edicao seguinte dela era
#      barrada com `sessao_ambigua`. Pior, a task liberada ficava reivindicavel por quem fechou.
#      Agora o escritor falha fechado (codigo 4, nada gravado) quando o dono e outra sessao.
#   2. `08-rastro.md` se contradizia no codigo `5`. A tabela de respostas mandava "siga sem o
#      evento" — mas, com o `escopo-da-task` ativo, um `task_iniciada` que NAO foi gravado
#      significa que a task NAO esta reivindicada: seguir e editar o primeiro arquivo da task
#      para ser barrado com `sessao_ambigua`, exatamente o beco do piloto C7-C. O codigo `5` nos
#      tres `task_*` passa a falhar fechado como o `3`: nao abra a task, nao grave a mao,
#      registre bloqueio `prerequisito_ausente`. Para `fase-*`/`veredito-emitido`, que nenhum
#      hook le, "siga sem o evento" continua certo — e a tabela passa a dizer os dois casos.
#
# O que esta correcao NAO faz, deliberadamente: nao muda a LEITURA do rastro (`_RASTRO_AWK_REIV`,
# `_sessao_dona`) para ignorar um fechamento de outra sessao ja gravado. Linha de reivindicacao
# escrita a mao e proibida pelo contrato (DS-159) e reprovada pela auditoria de transcrito
# (`transcrito-agente.sh`, regra `rastro_manual`): fechar a porta no escritor fecha o caminho que
# existe, sem quatro implementacoes de leitura divergindo sobre o que libera uma reivindicacao.
AI_T="$(mktemp -d)"
AI_H="$(cd "$H" && pwd)"
AI_SK="$(cd "$H/../skills/sprintx" && pwd)"
AI_N=0
AI_RC=0; AI_OUT=""

# Arvore no layout instalado, como a da secao U — e assim que o controle e os mutantes sao julgados.
ai_arvore() { # ai_arvore <nome>
  local r="$AI_T/arv/$1"
  rm -rf "$r"; mkdir -p "$r/.claude/hooks/testes" "$r/.claude/skills"
  cp -R "$AI_H/comum" "$AI_H/sprintx" "$r/.claude/hooks/"
  cp "$AI_H/testes/transcrito-agente.sh" "$r/.claude/hooks/testes/"
  cp -R "$AI_SK" "$r/.claude/skills/sprintx"
  printf '%s' "$r"
}
ai_task() { # ai_task <id> <status> <arquivo em altera>
  printf '  - id: %s\n    titulo: Task %s\n    status: %s\n    objetivo: obj\n    arquivos:\n      cria: []\n      altera: [%s]\n    teste_integracao: t\n    teste_funcional: t\n    criterio_aceite: c\n    depende_de: []\n    paralelizavel: false\n    concluida_em: null\n    suite: nao_executada\n' \
    "$1" "$1" "$2" "$3"
}
ai_plano() { # ai_plano <dir> <slug> <status T-01.01> <status T-01.02>
  local f="$1/docs/sprintx/features/$2/sprint-01/tasks.md"
  mkdir -p "$(dirname "$f")"
  { printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: tasks\ntrabalho_id: %s\nsprint_id: sprint-01\ntasks:\n' "$2"
    ai_task T-01.01 "$3" src/a.ts
    ai_task T-01.02 "$4" src/b.ts
    printf -- '---\n'; } > "$f"
}
ai_fx() { # repo git novo com o trabalho fx (T-01.01 -> src/a.ts, T-01.02 -> src/b.ts)
  AI_N=$((AI_N + 1)); AI_FX="$AI_T/fx$AI_N"
  mkdir -p "$AI_FX/src"; git init -q --template= "$AI_FX" >/dev/null 2>&1
  ai_plano "$AI_FX" fx em_andamento em_andamento
}
# O escritor, com a identidade que o Claude Code exporta — a derivada e `claude-code@<sessao>`.
ai_w() { # ai_w <arv> <dir> <sessao> <args do escritor...>
  local a="$1" d="$2" s="$3"; shift 3
  AI_OUT="$(cd "$d" && env -u EXPX_SESSAO -u EXPX_HARNESS CLAUDECODE=1 CLAUDE_CODE_SESSION_ID="$s" \
    bash "$a/.claude/skills/sprintx/scripts/rastro.sh" "$@" 2>&1)"; AI_RC=$?
}
ai_h() { # ai_h <arv> <dir> <sessao> <arquivo-relativo> — o escopo-da-task da arvore
  local a="$1" d="$2" s="$3" rel="$4"
  AI_OUT="$(printf '{"cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$d" "$d/$rel" \
    | (cd "$d" && env -u EXPX_SESSAO -u EXPX_HARNESS CLAUDECODE=1 CLAUDE_CODE_SESSION_ID="$s" \
        bash "$a/.claude/hooks/sprintx/escopo-da-task.sh") 2>&1)"; AI_RC=$?
}
ai_ok() { [ "$AI_RC" -eq 0 ] && [ -z "$AI_OUT" ]; }
ai_barra() { [ "$AI_RC" -eq 2 ] && printf '%s' "$AI_OUT" | grep -qF "$1"; }
ai_linha() { # ai_linha <arquivo> <evento> <task> — a ultima linha daquele evento, vazia se nao ha
  [ -f "$1" ] || return 0
  grep -F "\"evento\":\"$2\"" "$1" 2>/dev/null | grep -F "\"task\":\"$3\"" | tail -1
}
AI_LEGADO='{"ts":"2026-09-26T10:23:54Z","expx_eventos":1,"trabalho_id":"fx","ferramenta":"sprintx","origem":"skill","evento":"task_iniciada","fase":"f6","task":"T-01.01","agente":"principal","resultado":"ok","detalhe":"legado","arquivos":[]}'

# PR#14 — o escritor com OUTRO PATH, para separar "nao ha dona" de "nao deu para saber quem e".
ai_w_path() { # ai_w_path <PATH> <arv> <dir> <sessao> <args do escritor...>
  local p="$1" a="$2" d="$3" s="$4"; shift 4
  AI_OUT="$(cd "$d" && env -u EXPX_SESSAO -u EXPX_HARNESS CLAUDECODE=1 CLAUDE_CODE_SESSION_ID="$s" \
    PATH="$p" bash "$a/.claude/skills/sprintx/scripts/rastro.sh" "$@" 2>&1)"; AI_RC=$?
}
# PATH espelhado por link, com UM buraco: `awk`. Mesmo recurso do `aj_path_sem_jq` da secao AJ —
# sem ele o caso nao distingue "sem awk" de "sem nada no PATH". O espelho e por diretorio REAL
# (`pwd -P`), para `/bin` e `/usr/bin` nao pagarem dois espelhos iguais.
ai_path_sem_awk() {
  local d f real espelho novo="" IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    if [ -x "$d/awk" ]; then
      real="$(cd "$d" 2>/dev/null && pwd -P)" || real="$d"
      espelho="$AI_T/semawk$(printf '%s' "$real" | tr -c 'A-Za-z0-9' '-')"
      if [ ! -d "$espelho" ]; then
        mkdir -p "$espelho"
        for f in "$d"/*; do
          [ -e "$f" ] || continue
          [ "${f##*/}" = awk ] && continue
          ln -sf "$f" "$espelho/${f##*/}" 2>/dev/null
        done
      fi
      novo="$novo:$espelho"
    else
      novo="$novo:$d"
    fi
  done
  printf '%s' "${novo#:}"
}
AI_SEMAWK="$(ai_path_sem_awk)"
# `awk` que EXISTE e falha: o erro de leitura/execucao, deterministico em qualquer plataforma
# (inclusive Git Bash, onde brincar com permissao de arquivo nao e confiavel). Nenhum chmod,
# nada para restaurar no cleanup alem do proprio $AI_T.
AI_AWKRUIM="$AI_T/awk-ruim"
mkdir -p "$AI_AWKRUIM"
printf '#!/usr/bin/env bash\nprintf "awk: nao consegui ler o rastro\\n" >&2\nexit 2\n' > "$AI_AWKRUIM/awk"
chmod +x "$AI_AWKRUIM/awk"
if ( PATH="$AI_SEMAWK"; hash -r; command -v awk >/dev/null 2>&1 ); then AI_SB=1
else ( PATH="$AI_SEMAWK"; hash -r; command -v grep >/dev/null 2>&1 \
         && command -v git >/dev/null 2>&1 && command -v bash >/dev/null 2>&1 ); AI_SB=$?
fi
afirma "ai0-sandbox-esconde-awk-e-serve-o-resto" "$AI_SB" "PATH sem awk, com grep, git e bash"
if ( PATH="$AI_AWKRUIM:$AI_SEMAWK"; hash -r; command -v awk >/dev/null 2>&1 ) \
   && ! ( PATH="$AI_AWKRUIM:$AI_SEMAWK" "$AI_AWKRUIM/awk" 'END{}' </dev/null >/dev/null 2>&1 ); then AI_SB=0
else AI_SB=1
fi
afirma "ai0b-sandbox-tem-awk-que-existe-e-falha" "$AI_SB" "stub de awk visivel no PATH e com saida 2"

# ---------------------------------------------------------------- os casos
ai_dono() { # A: outra sessao nao fecha nem relibera a reivindicacao; o dono fecha
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  # s2 tenta fechar a task de s1, pelos dois eventos de fechamento
  ai_w "$a" "$AI_FX" s2 task-concluida fx T-01.01 "fecho eu" src/a.ts; [ "$AI_RC" -eq 4 ] || return 1
  printf '%s' "$AI_OUT" | grep -qF 'claude-code@s1' || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ] || return 1
  ai_w "$a" "$AI_FX" s2 task-bloqueada fx T-01.01 B-01; [ "$AI_RC" -eq 4 ] || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_bloqueada T-01.01)" ] || return 1
  # a reivindicacao de s1 continua ATIVA, e a task continua dela: nao foi reliberada
  ai_h "$a" "$AI_FX" s1 src/a.ts; ai_ok || return 1
  ai_h "$a" "$AI_FX" s2 src/a.ts; ai_barra sessao_ambigua || return 1
  # e o DONO fecha normalmente (controle: o portao nao quebra o caminho de sempre)
  ai_w "$a" "$AI_FX" s1 task-concluida fx T-01.01 "suite parcial verde" src/a.ts; [ "$AI_RC" -eq 0 ] || return 1
  [ -n "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ] || return 1
  ai_h "$a" "$AI_FX" s1 src/a.ts; ai_barra sessao_ambigua
}
ai_dono_bloqueada() { # B: o dono tambem bloqueia; e depois de fechada qualquer sessao reivindica
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_w "$a" "$AI_FX" s1 task-bloqueada fx T-01.01 B-01; [ "$AI_RC" -eq 0 ] || return 1
  # sem dono aberto, a task volta a ser reivindicavel — inclusive por outra sessao
  ai_w "$a" "$AI_FX" s2 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_h "$a" "$AI_FX" s2 src/a.ts; ai_ok || return 1
  # e agora e s1 quem nao pode fechar
  ai_w "$a" "$AI_FX" s1 task-concluida fx T-01.01 ok src/a.ts; [ "$AI_RC" -eq 4 ] || return 1
  printf '%s' "$AI_OUT" | grep -qF 'claude-code@s2'
}
ai_legado() { # C: evento legado sem `sessao` nao reivindica (DS-150) e continua FECHAVEL
  local a="$1"; ai_fx; mkdir -p "$AI_FX/docs/eventos"
  printf '%s\n' "$AI_LEGADO" >> "$AI_FX/docs/eventos/fx.jsonl"
  # nao reivindica: a primeira edicao continua barrada, como sempre
  ai_h "$a" "$AI_FX" s1 src/a.ts; ai_barra sessao_ambigua || return 1
  # e, porque nao reivindica, nao ha dono para proteger: o fechamento compativel segue valendo
  ai_w "$a" "$AI_FX" s1 task-concluida fx T-01.01 "fechamento do legado"; [ "$AI_RC" -eq 0 ] || return 1
  [ -n "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ] || return 1
  # o caminho contratado para seguir: reivindicar pelo escritor e ai sim editar
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_h "$a" "$AI_FX" s1 src/a.ts; ai_ok
}
ai_rotacao() { # D: a reivindicacao no arquivo ROTACIONADO continua protegendo o dono
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  mv "$AI_FX/docs/eventos/fx.jsonl" "$AI_FX/docs/eventos/fx.1.jsonl" || return 1
  : > "$AI_FX/docs/eventos/fx.jsonl"
  ai_w "$a" "$AI_FX" s2 task-concluida fx T-01.01 ok src/a.ts; [ "$AI_RC" -eq 4 ] || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ]
}
ai_iniciada_fora_do_portao() { # F: o portao e sobre FECHAR; abrir continua territorio do hook
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  # Reivindicar por cima continua aceito pelo escritor: quem avisa/barra isso e o hook
  # `task-reivindicada`, em aviso ou bloqueio. Este caso fixa a fronteira — a correcao e sobre
  # FECHAR a task de outra sessao, nao sobre abrir.
  ai_w "$a" "$AI_FX" s2 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_h "$a" "$AI_FX" s2 src/a.ts; ai_ok
}
ai_outra_task() { # E: o portao e por (trabalho, task): a task irma de outra sessao nao e afetada
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_w "$a" "$AI_FX" s2 task-iniciada fx T-01.02; [ "$AI_RC" -eq 0 ] || return 1
  ai_w "$a" "$AI_FX" s2 task-concluida fx T-01.02 ok src/b.ts; [ "$AI_RC" -eq 0 ] || return 1
  ai_w "$a" "$AI_FX" s1 task-concluida fx T-01.01 ok src/a.ts; [ "$AI_RC" -eq 0 ] || return 1
  return 0
}
# PR#14 — dona INDETERMINADA nao e dona ausente.
#
# `rastro_dona_da_task_em` tinha UM resultado para dois fatos: "ninguem tem esta task" e "nao deu
# para saber quem tem". Sem `awk` no PATH, ou com erro de leitura em `docs/eventos/`, ela devolvia
# vazio com retorno 0 — e o portao do dono lia isso como task livre. Resultado: o fechamento de
# outra sessao passava justamente no ambiente em que a prova de ownership esta ilegivel, que e o
# pior momento possivel para presumir ausencia. Agora a ausencia CONCLUSIVA (sem pasta, sem
# arquivo do trabalho, ou nenhum evento daquela task nos arquivos lidos) continua vazia com
# retorno 0, e o inconclusivo sai por retorno NAO-ZERO; o escritor o traduz em codigo 5 de
# ambiente e nao grava o fechamento.
#
# `task-iniciada` fica fora: o portao e so dos dois fechamentos, e abrir task continua sem
# dependencia nova de `awk` — a varredura de contexto da biblioteca segue falhando aberta.
ai_sem_awk_outra_sessao() { # sem `awk`, a reivindicacao e ILEGIVEL, nao e inexistente
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_w_path "$AI_SEMAWK" "$a" "$AI_FX" s2 task-concluida fx T-01.01 "fecho eu" src/a.ts
  [ "$AI_RC" -eq 5 ] || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ] || return 1
  ai_w_path "$AI_SEMAWK" "$a" "$AI_FX" s2 task-bloqueada fx T-01.01 B-01
  [ "$AI_RC" -eq 5 ] || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_bloqueada T-01.01)" ] || return 1
  # com `awk` de volta, a reivindicacao de s1 esta intacta: o codigo 4 de sempre, e o dono fecha
  ai_w "$a" "$AI_FX" s2 task-concluida fx T-01.01 ok src/a.ts; [ "$AI_RC" -eq 4 ] || return 1
  ai_w "$a" "$AI_FX" s1 task-concluida fx T-01.01 ok src/a.ts; [ "$AI_RC" -eq 0 ]
}
ai_sem_awk_a_propria_dona() { # nem a dona fecha: o portao nao SABE que ela e a dona
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_w_path "$AI_SEMAWK" "$a" "$AI_FX" s1 task-concluida fx T-01.01 ok src/a.ts
  [ "$AI_RC" -eq 5 ] || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ] || return 1
  printf '%s' "$AI_OUT" | grep -qF 'prerequisito_ausente' || return 1
  # e nada foi reliberado: a task continua dela
  ai_h "$a" "$AI_FX" s1 src/a.ts; ai_ok || return 1
  ai_h "$a" "$AI_FX" s2 src/a.ts; ai_barra sessao_ambigua
}
ai_awk_com_erro() { # `awk` que existe e falha e inconclusivo, nos dois fechamentos
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_w_path "$AI_AWKRUIM:$PATH" "$a" "$AI_FX" s2 task-concluida fx T-01.01 ok src/a.ts
  [ "$AI_RC" -eq 5 ] || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ] || return 1
  ai_w_path "$AI_AWKRUIM:$PATH" "$a" "$AI_FX" s1 task-bloqueada fx T-01.01 B-01
  [ "$AI_RC" -eq 5 ] || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_bloqueada T-01.01)" ]
}
ai_ausencia_conclusiva() { # ausencia REAL continua conclusiva e nao vira erro
  local a="$1"; ai_fx
  # (i) Sem pasta docs/eventos nenhuma: conclusivo ANTES de precisar de `awk`. Este trecho e
  # tambem o controle do sandbox — se o PATH espelhado quebrasse o escritor, aqui nao sairia 0.
  [ ! -e "$AI_FX/docs/eventos" ] || return 1
  ai_w_path "$AI_SEMAWK" "$a" "$AI_FX" s1 task-concluida fx T-01.01 "sem dona" src/a.ts
  [ "$AI_RC" -eq 0 ] || return 1
  [ -n "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ] || return 1
  # (ii) Pasta existente e nenhum arquivo DAQUELE trabalho: tambem conclusivo antes do `awk`.
  ai_fx; mkdir -p "$AI_FX/docs/eventos" || return 1
  ai_w_path "$AI_SEMAWK" "$a" "$AI_FX" s1 task-bloqueada fx T-01.01 B-01
  [ "$AI_RC" -eq 0 ] || return 1
  [ -n "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_bloqueada T-01.01)" ] || return 1
  # (iii) Arquivo do trabalho ja existe, mas nenhum evento da T-01.02: conclusivo pelo `awk`.
  ai_w "$a" "$AI_FX" s1 task-concluida fx T-01.02 ok src/b.ts; [ "$AI_RC" -eq 0 ] || return 1
  # (iv) Mas arquivo candidato COM `awk` ausente nao e ausencia: e inconclusivo, mesmo que a
  # task pedida nao tenha dono nenhum ali dentro.
  ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.02; [ "$AI_RC" -eq 0 ] || return 1
  ai_w_path "$AI_SEMAWK" "$a" "$AI_FX" s1 task-concluida fx T-01.01 ok src/a.ts
  [ "$AI_RC" -eq 5 ]
}
# O contrato publico: a tabela de respostas de 08-rastro.md e o passo 1 da 06-execucao.md.
AI_LIT_C5='nos três `task_*`, **falha fechado como o código `3`**'
AI_LIT_C5_PORQUE='sem `task_iniciada` não há reivindicação, e o `escopo-da-task` barra a primeira edição da task'
AI_LIT_C5_INFO='Nos demais eventos (`fase-*`, `veredito-emitido`), que nenhum hook lê, siga sem o evento'
AI_LIT_C4='a task está reivindicada por outra sessão'
AI_LIT_EXEC='nada foi gravado e a task **não** está reivindicada'
AI_LIT_DONO='Fechar a task é do dono da reivindicação'
# A contradicao exata que havia: a linha do codigo 5 mandando seguir, sem distinguir os task_*.
AI_LIT_PROIBE_C5_ANTIGO='!ou a escrita falhou — **nada foi gravado** | siga sem o evento; não grave à mão'
# PR#14 — o codigo 5 passa a nomear a terceira causa, e o limite arquitetural fica escrito.
AI_LIT_C5_LEITURA='a **reivindicação não pôde ser lida**'
AI_LIT_INDET='Dona indeterminada não é dona ausente'
AI_LIT_TOCTOU='check-then-append'
ai_doc() { # F: o contrato diz o fail-closed, e a contradicao antiga nao sobrevive
  local d="$1/.claude/skills/sprintx"
  ad_lit "$d/references/08-rastro.md" "$AI_LIT_C5" \
         "$d/references/08-rastro.md" "$AI_LIT_C5_PORQUE" \
         "$d/references/08-rastro.md" "$AI_LIT_C5_INFO" \
         "$d/references/08-rastro.md" "$AI_LIT_C4" \
         "$d/references/08-rastro.md" "$AI_LIT_DONO" \
         "$d/references/08-rastro.md" "$AI_LIT_PROIBE_C5_ANTIGO" \
         "$d/references/06-execucao.md" "$AI_LIT_EXEC"
}
ai_doc_inconclusivo() { # H: o codigo 5 nomeia a reivindicacao ilegivel, e o limite esta escrito
  local d="$1/.claude/skills/sprintx"
  ad_lit "$d/references/08-rastro.md" "$AI_LIT_C5_LEITURA" \
         "$d/references/08-rastro.md" "$AI_LIT_INDET" \
         "$d/references/08-rastro.md" "$AI_LIT_TOCTOU"
}
ai_ds174() { # I: DS-174 registrada, append-only, e a DS-171 anterior intacta
  local v d="$1/.claude/skills/sprintx"
  v="$(grep -F '| DS-174 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
  [ -n "$v" ] || return 1
  printf '%s' "$v" | grep -qiF 'indeterminada' || return 1
  printf '%s' "$v" | grep -qiF 'check-then-append' || return 1
  printf '%s' "$v" | grep -qiF 'task-iniciada' || return 1
  grep -qF '| DS-171 |' "$d/DECISOES-DA-SKILL.md"
}
ai_ds() { # G: DS-171 registrada, append-only, e a DS-159 anterior intacta
  local v d="$1/.claude/skills/sprintx"
  v="$(grep -F '| DS-171 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
  [ -n "$v" ] || return 1
  printf '%s' "$v" | grep -qiF 'reivindica' || return 1
  printf '%s' "$v" | grep -qiF 'fecha' || return 1
  grep -qF '| DS-159 |' "$d/DECISOES-DA-SKILL.md"
}

AI_CASOS="ai_dono ai_dono_bloqueada ai_legado ai_rotacao ai_iniciada_fora_do_portao
ai_outra_task ai_doc ai_ds ai_sem_awk_outra_sessao ai_sem_awk_a_propria_dona ai_awk_com_erro
ai_ausencia_conclusiva ai_doc_inconclusivo ai_ds174"
ai_nome() {
  case "$1" in
    ai_dono)           echo "ai1-outra-sessao-nao-fecha-nem-relibera" ;;
    ai_dono_bloqueada) echo "ai2-dono-bloqueia-e-a-task-volta-a-ser-reivindicavel" ;;
    ai_legado)         echo "ai3-legado-sem-sessao-nao-reivindica-e-continua-fechavel" ;;
    ai_rotacao)        echo "ai4-reivindicacao-no-rotacionado-protege-o-dono" ;;
    ai_iniciada_fora_do_portao) echo "ai5-portao-e-sobre-fechar-nao-sobre-abrir" ;;
    ai_outra_task)     echo "ai6-portao-e-por-trabalho-e-task-nao-por-sessao-global" ;;
    ai_doc)            echo "ai7-contrato-do-codigo-5-falha-fechado-sem-contradicao" ;;
    ai_ds)             echo "ai8-ds171-registrada-append-only" ;;
    ai_sem_awk_outra_sessao)   echo "ai9-sem-awk-outra-sessao-nao-fecha-nem-grava" ;;
    ai_sem_awk_a_propria_dona) echo "ai10-sem-awk-nem-a-dona-fecha-e-nada-e-gravado" ;;
    ai_awk_com_erro)   echo "ai11-erro-do-awk-e-inconclusivo-nao-e-ausencia" ;;
    ai_ausencia_conclusiva)    echo "ai12-ausencia-real-continua-conclusiva-e-da-zero" ;;
    ai_doc_inconclusivo)       echo "ai13-codigo-5-nomeia-reivindicacao-ilegivel" ;;
    ai_ds174)          echo "ai14-ds174-registrada-append-only" ;;
  esac
}
AI_REAL="$(cd "$H/../.." && pwd)"
for ai_c in $AI_CASOS; do
  ai_nm="$(ai_nome "$ai_c")"; "$ai_c" "$AI_REAL" >/dev/null 2>&1; ai_rc=$?
  afirma "$ai_nm" "$ai_rc" "arvore do repositorio"
done

# ---------------------------------------------------------------- mutantes
# Copia do layout instalado; o controle e a copia sem mutacao. Cada mutante tem de morrer pelos
# casos que o nomeiam — nao vale morrer de carona.
ai_mutante() { # ai_mutante <nome> <rc da geracao> <arvore> <casos que TEM de matar>
  local nome="$1" rc="$2" r="$3" c vivos=""
  if [ "$rc" -eq 0 ]; then for c in $4; do "$c" "$r" >/dev/null 2>&1 && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]; afirma "$nome" $? "morto por: $4 ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
AI_CTL="$(ai_arvore controle)"; AI_VIVO=""
for ai_c in $AI_CASOS; do "$ai_c" "$AI_CTL" >/dev/null 2>&1 || AI_VIVO="$AI_VIVO $ai_c"; done
[ -z "$AI_VIVO" ]; afirma "aim-controle-copia-intacta-sobrevive" $? "${AI_VIVO:+reprovada por:$AI_VIVO}"
AI_W=".claude/skills/sprintx/scripts/rastro.sh"
AI_L=".claude/hooks/comum/rastro.sh"
AI_R=".claude/skills/sprintx/references"
ai_m() { # ai_m <nome> <arquivo-relativo> <trecho> <troca> — arvore nova com UMA troca literal
  local r; r="$(ai_arvore "$1")"
  muta_lit "$r/$2" "$r/$2.m" "$3" "$4" && mv "$r/$2.m" "$r/$2" && printf '%s' "$r"
}
# m1 — o portao do dono desaparece: qualquer sessao volta a fechar a task de qualquer outra.
AIM="$(ai_m m1 "$AI_W" 'if [ -n "$DONA" ] && [ "$DONA" != "${SESSAO:-}" ]; then' 'if false; then')"
ai_mutante "aim-mutante-1-sem-portao-do-dono" $? "$AIM" "ai_dono ai_dono_bloqueada ai_rotacao"
# m2 — o portao passa a valer para task-iniciada tambem: reivindicar depois de fechada reprova,
#      e o legado deixa de ser fechavel pelo caminho compativel.
AIM="$(ai_m m2 "$AI_W" '  task-concluida|task-bloqueada)' '  task-concluida|task-bloqueada|task-iniciada)')"
ai_mutante "aim-mutante-2-portao-alcanca-task-iniciada" $? "$AIM" "ai_iniciada_fora_do_portao"
# m3 — o dono sai de um arquivo so, sem o rotacionado: a reivindicacao rotacionada fica invisivel.
AIM="$(ai_m m3 "$AI_L" 'for _f in "$_dir/$_t".jsonl "$_dir/$_t".[0-9]*.jsonl; do' 'for _f in "$_dir/$_t".jsonl; do')"
ai_mutante "aim-mutante-3-dono-ignora-arquivo-rotacionado" $? "$AIM" "ai_rotacao"
# m4 — o portao compara com a sessao errada (a do evento, nao a desta): o dono nao se reconhece.
AIM="$(ai_m m4 "$AI_W" '[ "$DONA" != "${SESSAO:-}" ]' '[ "$DONA" = "${SESSAO:-}" ]')"
ai_mutante "aim-mutante-4-portao-compara-invertido" $? "$AIM" "ai_dono ai_dono_bloqueada"
# m5 — a tabela de respostas volta a mandar seguir sem o evento no codigo 5.
AIM="$(ai_m m5 "$AI_R/08-rastro.md" "$AI_LIT_C5" 'siga sem o evento')"
ai_mutante "aim-mutante-5-codigo-5-volta-a-mandar-seguir" $? "$AIM" "ai_doc"
# m6 — a 06-execucao.md perde a frase que diz que a task NAO esta reivindicada.
AIM="$(ai_m m6 "$AI_R/06-execucao.md" "$AI_LIT_EXEC" 'nada foi gravado')"
ai_mutante "aim-mutante-6-execucao-sem-o-aviso-de-nao-reivindicada" $? "$AIM" "ai_doc"
# m7 — DS-171 apagada do registro.
AIM="$(ai_arvore m7)" && muta_lit "$AIM/.claude/skills/sprintx/DECISOES-DA-SKILL.md" "$AIM/ds.m" '| DS-171 |' '| DS-171-apagada |' \
  && mv "$AIM/ds.m" "$AIM/.claude/skills/sprintx/DECISOES-DA-SKILL.md"
ai_mutante "aim-mutante-7-ds171-apagada" $? "$AIM" "ai_ds"
# m8 — PR#14: o retorno inconclusivo da leitura da dona volta a ser 0. A funcao continua devolvendo
#      a variavel vazia; o que morre e a distincao entre "nao tem dona" e "nao deu para saber".
AIM="$(ai_m m8 "$AI_L" '  [ "$_rc" -eq 0 ] || return "$_rc"' '  [ "$_rc" -eq 0 ] || return 0')"
ai_mutante "aim-mutante-8-inconclusivo-vira-ausencia" $? "$AIM" \
  "ai_sem_awk_outra_sessao ai_sem_awk_a_propria_dona ai_awk_com_erro"
# m9 — o escritor volta a ignorar o retorno da leitura e compara DONA mesmo sem ter lido nada.
AIM="$(ai_m m9 "$AI_W" '    if ! rastro_dona_da_task_em DONA "$RAIZ" "$SLUG" "$ALVO"; then' \
  '    rastro_dona_da_task_em DONA "$RAIZ" "$SLUG" "$ALVO" || true; if false; then')"
ai_mutante "aim-mutante-9-escritor-ignora-leitura-inconclusiva" $? "$AIM" \
  "ai_sem_awk_outra_sessao ai_sem_awk_a_propria_dona ai_awk_com_erro"
# m10 — a ausencia CONCLUSIVA por falta de arquivo do trabalho passa a ser erro: fechar task que
#       nunca foi aberta, com a pasta de eventos ja existindo, deixa de valer.
AIM="$(ai_m m10 "$AI_L" '  [ "${#_arqs[@]}" -gt 0 ] || return 0' '  [ "${#_arqs[@]}" -gt 0 ] || return 3')"
ai_mutante "aim-mutante-10-sem-arquivo-do-trabalho-vira-erro" $? "$AIM" "ai_ausencia_conclusiva"
# m13 — e a ausencia CONCLUSIVA por falta da propria pasta docs/eventos tambem.
AIM="$(ai_m m13 "$AI_L" '  [ -d "$_dir" ] || return 0' '  [ -d "$_dir" ] || return 3')"
ai_mutante "aim-mutante-13-pasta-de-eventos-ausente-vira-erro" $? "$AIM" "ai_ausencia_conclusiva"
# m11 — a tabela do codigo 5 perde a reivindicacao ilegivel e volta a listar duas causas so.
AIM="$(ai_m m11 "$AI_R/08-rastro.md" "$AI_LIT_C5_LEITURA" 'a escrita falhou')"
ai_mutante "aim-mutante-11-codigo-5-sem-a-reivindicacao-ilegivel" $? "$AIM" "ai_doc_inconclusivo"
# m12 — DS-174 apagada do registro.
AIM="$(ai_arvore m12)" && muta_lit "$AIM/.claude/skills/sprintx/DECISOES-DA-SKILL.md" "$AIM/ds.m" '| DS-174 |' '| DS-174-apagada |' \
  && mv "$AIM/ds.m" "$AIM/.claude/skills/sprintx/DECISOES-DA-SKILL.md"
ai_mutante "aim-mutante-12-ds174-apagada" $? "$AIM" "ai_ds174"

rm -rf "$AI_T"

echo "== AJ. deteccao da saida da suite e certificacao da ORDEM real (PR#12) =="
# Tres defeitos na forma como a maquina LE o que o agente fez:
#
#   1. CLASSIFICACAO DA SUITE. `rastro-post` decidia `falha` por fronteira de espaco em branco
#      ao redor de `[ERROR]` e `BUILD FAILURE`. Maven e Surefire saem COLORIDOS: a sequencia
#      ANSI cola um `m` antes do token e outro depois, nenhuma fronteira de espaco existe, e
#      uma suite vermelha era gravada como `ok` — o painel passava a mostrar verde onde o
#      build quebrou. Agora a saida tem as sequencias ANSI removidas ANTES de classificar, e
#      so quando ha ESC no texto (o caminho de sempre nao paga processo nenhum).
#   2. FORMA DO `tool_response`. O hook lia `tool_response` como string. No Bash, o Claude Code
#      entrega um OBJETO (`{"stdout":...,"stderr":...}`): com jq, `.tool_response` de um objeto
#      vira o JSON impresso, onde as quebras aparecem ESCAPADAS e o token perde a fronteira de
#      espaco; sem jq, a leitura de string nao casa objeto nenhum e a saida vinha VAZIA — nenhuma
#      suite era classificada como falha nessa rota. Agora o texto sai das strings de dentro da
#      resposta, qualquer que seja a forma, nas duas rotas.
#   3. ORDEM NO RASTRO. A certificacao do agente real exigia "uma edicao da task depois do
#      claim" — mas marcava a primeira edicao so a partir do instante em que o claim aparecia.
#      Com a PRIMEIRA edicao ANTES da reivindicacao (o defeito que a prova existe para pegar) e
#      uma segunda edicao legitima depois, a prova passava. Agora a primeira edicao e marcada
#      sempre, e a prova exige que ELA venha depois do claim.
#
# E a auditoria de transcrito reprovava escrita manual em docs/eventos so por redirecao, `tee` e
# `sed -i`. `cp`, `mv` e um interpretador com `open(..., 'a')` escrevem o mesmo arquivo e
# passavam — inclusive num transcrito que TAMBEM chama o escritor oficial, que era a forma mais
# facil de parecer conforme. A regra nova olha o PAPEL do caminho, nao a mencao: copiar ou mover
# PARA docs/eventos viola; `cat`, `grep`, `jq`, `tail`, `wc`, `print(open(...).read())` e copiar
# o rastro PARA FORA continuam sendo leitura, que o contrato permite.
AJ_T="$(mktemp -d)"
AJ_H="$(cd "$H" && pwd)"
AJ_JSONL="$AJ_T/repo/docs/eventos/sem-trabalho.jsonl"

aj_path_sem_jq() {
  local d f espelho novo="" i=0 IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    if [ -x "$d/jq" ]; then
      i=$((i+1)); espelho="$AJ_T/bin$i"
      if [ ! -d "$espelho" ]; then
        mkdir -p "$espelho"
        for f in "$d"/*; do
          [ -e "$f" ] || continue
          [ "${f##*/}" = jq ] && continue
          ln -sf "$f" "$espelho/${f##*/}" 2>/dev/null
        done
      fi
      novo="$novo:$espelho"
    else
      novo="$novo:$d"
    fi
  done
  printf '%s' "${novo#:}"
}
AJ_SEMJQ="$(aj_path_sem_jq)"
if PATH="$AJ_SEMJQ" command -v jq >/dev/null 2>&1; then AJ_RC=1
else PATH="$AJ_SEMJQ" command -v grep >/dev/null 2>&1; AJ_RC=$?
fi
afirma "aj0-sandbox-esconde-jq-e-serve-o-resto" "$AJ_RC" "PATH do caso sem jq, com grep"

# ------------------------------------------------- 1 e 2. classificacao da saida da suite
cat > "$AJ_T/payload.py" <<'PY'
import json, sys
forma, arq_saida, cwd = sys.argv[1], sys.argv[2], sys.argv[3]
texto = open(arq_saida, encoding='utf-8').read()
if forma == 'string':
    resp = texto
elif forma == 'objeto':
    resp = {'stdout': texto, 'stderr': '', 'interrupted': False, 'isImage': False}
else:
    resp = {'stdout': '', 'stderr': texto, 'interrupted': False, 'isImage': False}
print(json.dumps({'cwd': cwd, 'tool_name': 'Bash',
                  'tool_input': {'command': 'mvn test'}, 'tool_response': resp}))
PY
aj_roda() { # aj_roda <forma> <texto da saida> <PATH do caso>
  rm -rf "$AJ_T/repo"; mkdir -p "$AJ_T/repo/.git" "$AJ_T/repo/docs/eventos"
  printf '%s' "$2" > "$AJ_T/saida.txt"
  python3 "$AJ_T/payload.py" "$1" "$AJ_T/saida.txt" "$AJ_T/repo" > "$AJ_T/payload.json"
  (cd "$AJ_T/repo" && PATH="$3" bash "$AJ_H/comum/rastro-post.sh") < "$AJ_T/payload.json" >/dev/null 2>&1
}
aj_resultado() { # ecoa o `resultado` gravado, ou um diagnostico
  [ -s "$AJ_JSONL" ] || { printf 'sem-linha'; return 0; }
  python3 -c 'import json,sys; print(json.loads(open(sys.argv[1],encoding="utf-8").readline())["resultado"])' \
    "$AJ_JSONL" 2>/dev/null || printf 'ilegivel'
}
aj_caso() { # aj_caso <nome> <esperado> <texto> — as 3 formas x as 2 rotas
  local nome="$1" esp="$2" texto="$3" forma rota caminho real ruim=""
  for rota in com-jq sem-jq; do
    caminho="$PATH"; [ "$rota" = sem-jq ] && caminho="$AJ_SEMJQ"
    for forma in string objeto objeto-stderr; do
      aj_roda "$forma" "$texto" "$caminho"
      real="$(aj_resultado)"
      [ "$real" = "$esp" ] || ruim="$ruim $rota/$forma=$real"
    done
  done
  [ -z "$ruim" ]
  afirma "$nome" $? "esperado=$esp${ruim:+ — FORA DO ESPERADO:$ruim}"
}
# Maven/Surefire colorido: a sequencia ANSI cola um `m` antes do token e outro depois.
printf -v AJ_ERR_ANSI '\033[1;31m[ERROR]\033[0m Failed to execute goal on project app'
printf -v AJ_BF_ANSI  '\033[1m[INFO] \033[1;31mBUILD FAILURE\033[0m\n\033[1m[INFO] \033[0mTotal time: 3.1 s'
printf -v AJ_VERDE    '[INFO] Tests run: 12, Failures: 0, Errors: 0, Skipped: 0\n[INFO] BUILD SUCCESS'
printf -v AJ_VERDE_ANSI '\033[1;32m[INFO]\033[0m Tests run: 12, Failures: 0, Errors: 0\n\033[1;32m[INFO] BUILD SUCCESS\033[0m'
AJ_ERR_CRU='[ERROR] Failed to execute goal on project app'
aj_caso "aj1-error-com-ansi-ao-redor-e-falha"      falha "$AJ_ERR_ANSI"
aj_caso "aj2-build-failure-com-ansi-ao-redor-e-falha" falha "$AJ_BF_ANSI"
aj_caso "aj3-error-cru-nao-regride"                falha "$AJ_ERR_CRU"
aj_caso "aj4-surefire-com-falhas-contadas-e-falha" falha '[INFO] Tests run: 12, Failures: 3, Errors: 0
Results: 3 failed, 9 passed'
# Controles: verde e verde colorido NAO viram falha — a remocao de ANSI nao inventa defeito.
aj_caso "aj5-verde-continua-ok"                    ok "$AJ_VERDE"
aj_caso "aj6-verde-colorido-continua-ok"           ok "$AJ_VERDE_ANSI"

# ------------------------------------------------- 3. auditoria de transcrito: escrita x leitura
AJ_TR_OK=1
if ! command -v jq >/dev/null 2>&1; then
  pula_externo "aj-auditoria-de-transcrito" "jq"; AJ_TR_OK=0
fi
aj_ev() { # aj_ev <ferramenta> <input-json> — uma linha stream-json com um tool_use
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"%s","input":%s}]}}\n' "$1" "$2"
}
# O transcrito CONFORME: so o escritor oficial abre e fecha, e o agente LE o rastro para conferir.
aj_bom() {
  aj_ev Bash '{"command":"bash .claude/skills/sprintx/scripts/rastro.sh task-iniciada fx T-01.01"}'
  aj_ev Edit '{"file_path":"/p/src/a.ts","old_string":"a","new_string":"b"}'
  aj_ev Bash '{"command":"bash .claude/skills/sprintx/scripts/rastro.sh task-concluida fx T-01.01 ok src/a.ts"}'
}
aj_verifica() { # aj_verifica <arquivo de transcrito> — ecoa as violacoes (vazio = aprovado)
  ( . "$AJ_H/testes/transcrito-agente.sh"; transcrito_verifica "$1" 1111-2222 fx T-01.01 || : )
}
# Cada comando abaixo e acrescentado a um transcrito que TAMBEM chama o escritor oficial: e essa
# a forma de burlar que a regra antiga nao pegava.
aj_tr_viola() { # aj_tr_viola <nome> <comando> <detalhe>
  local nome="$1" cmd="$2" det="$3" v
  [ "$AJ_TR_OK" = 1 ] || return 0
  { aj_bom; aj_ev Bash "$(python3 -c 'import json,sys; print(json.dumps({"command":sys.argv[1]}))' "$cmd")"; } > "$AJ_T/tr"
  v="$(aj_verifica "$AJ_T/tr")"
  printf '%s' "$v" | grep -q '^rastro_manual:'
  afirma "$nome" $? "${det}${v:+ — violacoes=[$(printf '%s' "$v" | tr '\n' ' ' | cut -c1-90)]}"
}
aj_tr_viola "aj7-cp-para-docs-eventos-e-escrita-manual" \
  'cp /tmp/forjado.jsonl docs/eventos/fx.jsonl' "cp com docs/eventos como DESTINO"
aj_tr_viola "aj8-mv-para-docs-eventos-e-escrita-manual" \
  'mv /tmp/forjado.jsonl docs/eventos/fx.jsonl' "mv com docs/eventos como DESTINO"
aj_tr_viola "aj9-python-append-e-escrita-manual" \
  "python3 -c \"open('docs/eventos/fx.jsonl','a').write('{}')\"" "open em modo de escrita"
aj_tr_viola "aj10-python-dump-e-escrita-manual" \
  "python3 - <<'P'
import json; json.dump({}, open('docs/eventos/fx.jsonl','w'))
P" "json.dump no rastro"
aj_tr_viola "aj11-tee-sem-redirecao-tambem" \
  'printf "{}" | tee docs/eventos/fx.jsonl' "tee com o rastro como destino"
# E a LEITURA continua permitida: nenhuma destas pode virar violacao.
aj_tr_le() { # aj_tr_le <nome> <comando> <detalhe>
  local nome="$1" cmd="$2" det="$3" v
  [ "$AJ_TR_OK" = 1 ] || return 0
  { aj_bom; aj_ev Bash "$(python3 -c 'import json,sys; print(json.dumps({"command":sys.argv[1]}))' "$cmd")"; } > "$AJ_T/tr"
  v="$(aj_verifica "$AJ_T/tr")"
  [ -z "$v" ]
  afirma "$nome" $? "${det}${v:+ — REPROVOU leitura: [$(printf '%s' "$v" | tr '\n' ' ' | cut -c1-90)]}"
}
aj_tr_le "aj12-cat-do-rastro-e-leitura"  'cat docs/eventos/fx.jsonl' "cat"
aj_tr_le "aj13-grep-e-tail-sao-leitura"  'grep -c task_iniciada docs/eventos/fx.jsonl | tail -1' "grep + tail"
aj_tr_le "aj14-jq-e-wc-sao-leitura"      'jq -r .evento docs/eventos/fx.jsonl 2>/dev/null | wc -l' "jq + wc"
aj_tr_le "aj15-python-read-e-leitura"    "python3 -c \"print(open('docs/eventos/fx.jsonl').read())\"" "print(open(...).read())"
aj_tr_le "aj16-copiar-o-rastro-para-fora-e-leitura" 'cp docs/eventos/fx.jsonl /tmp/copia.jsonl' "cp com docs/eventos como ORIGEM"
# PR#12 (achado A): a decisao de destino de `cp`/`mv` olhava SO o ultimo token do segmento. Com
# `2>/dev/null` ou `>/dev/null` no fim, o ultimo token era o REDIRECIONAMENTO e o destino real
# ficava invisivel; e `cp -t docs/eventos/ origem` nomeia o destino na OPCAO, nunca no fim.
aj_tr_viola "aj23-cp-com-stderr-redirecionado-ainda-e-escrita" \
  'cp /tmp/forjado.jsonl docs/eventos/fx.jsonl 2>/dev/null' "2>/dev/null nao e o destino"
aj_tr_viola "aj24-cp-com-stdout-redirecionado-ainda-e-escrita" \
  'cp -v /tmp/f.jsonl docs/eventos/fx.jsonl >/dev/null' ">/dev/null nao e o destino"
aj_tr_viola "aj25-cp-com-target-directory-e-escrita" \
  'cp -t docs/eventos/ /tmp/f.jsonl' "-t nomeia o destino"
aj_tr_viola "aj26-dd-escrevendo-no-rastro-e-escrita" \
  'dd if=/tmp/f.jsonl of=docs/eventos/fx.jsonl' "dd com o rastro em of="
# E as leituras seguem permitidas: redirecionar stderr nao transforma origem em destino, e `dd`
# nomeia os dois lados — `if=` e ORIGEM.
aj_tr_le "aj27-copiar-para-fora-com-redirecao-e-leitura" \
  'cp docs/eventos/fx.jsonl /tmp/copia.jsonl 2>/dev/null' "cp com docs/eventos como ORIGEM"
aj_tr_le "aj28-dd-lendo-o-rastro-e-leitura" \
  'dd if=docs/eventos/fx.jsonl of=/tmp/copia.jsonl' "dd com docs/eventos em if="
# PR#12 (achado B): o estado "um interpretador apareceu" era PEGAJOSO entre segmentos. Depois de
# `python3 -c "..."`, o segmento seguinte herdava o estado de escrita, e `grep -c write` reprovava
# porque a palavra `write` estava ali como PADRAO do grep, nao como primitiva de escrita.
AJ_CMD_LE_B="python3 -c \"import json; print(json.load(open('/tmp/a.json')))\" ; grep -c write docs/eventos/fx.jsonl"
aj_tr_le "aj29-leitura-depois-de-interpretador-nao-herda-escrita" "$AJ_CMD_LE_B" \
  "o segmento que toca o rastro e leitura"
# E o que a herencia entre segmentos existe para pegar continua pego: heredoc de um interpretador
# que REALMENTE escreve no rastro, com a primitiva de escrita numa linha depois da chamada.
aj_tr_viola "aj30-heredoc-de-interpretador-que-escreve-continua-violando" \
  "python3 - <<'P'
import json
d = {}
json.dump(d, open('docs/eventos/fx.jsonl','w'))
P" "interpretador multissegmento que escreve"
# PR#14 (achado 2): o destino de `-t`/`--target-directory` pode vir ANEXADO a opcao. A regra olhava
# so a forma canonica (`-t dir`, `--target-directory=dir`), entao bastava colar o destino na opcao
# (`cp -tdocs/eventos/ origem`) ou abreviar a opcao longa, como o getopt do GNU aceita, para a
# escrita no rastro ficar invisivel.
aj_tr_viola "aj31-cp-com-destino-anexado-em-bloco-curto-e-escrita" \
  'cp -atdocs/eventos/ /tmp/f.jsonl' "-at com o destino colado na opcao"
aj_tr_viola "aj32-cp-com-destino-anexado-a-t-e-escrita" \
  'cp -tdocs/eventos/ /tmp/f.jsonl' "-t com o destino colado"
aj_tr_viola "aj33-mv-com-destino-anexado-a-t-e-escrita" \
  'mv -tdocs/eventos/ /tmp/f.jsonl' "mv -t colado"
aj_tr_viola "aj34-install-com-destino-anexado-em-bloco-curto-e-escrita" \
  'install -Dtdocs/eventos/ /tmp/f.jsonl' "install -Dt colado"
aj_tr_viola "aj35-cp-com-opcao-longa-abreviada-e-escrita" \
  'cp --targ=docs/eventos/ /tmp/f.jsonl' "--targ e abreviacao de --target-directory"
aj_tr_viola "aj36-cp-com-opcao-longa-quase-inteira-e-escrita" \
  'cp --target-director=docs/eventos/ /tmp/f.jsonl' "--target-director tambem e prefixo valido"
aj_tr_viola "aj37-cp-com-opcao-longa-inteira-nao-regride" \
  'cp --target-directory=docs/eventos/ /tmp/f.jsonl' "a forma canonica continua pega"
# `rsync -t` e preservar TEMPO, nao destino: ali o destino continua POSICIONAL, nas duas direcoes.
aj_tr_viola "aj38-rsync-t-tem-destino-posicional-e-escreve" \
  'rsync -t /tmp/f.jsonl docs/eventos/fx.jsonl' "-t do rsync e tempo; o destino e o 2o operando"
aj_tr_le "aj39-rsync-t-lendo-o-rastro-e-leitura" \
  'rsync -t docs/eventos/fx.jsonl /tmp/copia.jsonl' "-t do rsync nao transforma origem em destino"
# E o destino na opcao, anexado ou nao, apontando PARA FORA continua sendo leitura do rastro.
aj_tr_le "aj40-destino-anexado-fora-do-rastro-e-leitura" \
  'cp -t/tmp/ docs/eventos/fx.jsonl' "-t/tmp/ com o rastro como ORIGEM"
aj_tr_le "aj41-destino-separado-fora-do-rastro-e-leitura" \
  'cp -at /tmp/ docs/eventos/fx.jsonl' "-at /tmp/ com o rastro como ORIGEM"
aj_tr_le "aj42-no-target-directory-nao-e-abreviacao-de-target-directory" \
  'cp --no-target-directory docs/eventos/fx.jsonl /tmp/copia.jsonl' "--no-... nao e prefixo de --target-directory"

# PR#14 (achado 3): wrappers TRANSPARENTES. `env cp ...` escreve o mesmo arquivo que `cp ...`, mas a
# regra julgava o `env` como se fosse o comando — nome fora de toda lista, segmento ignorado,
# escrita invisivel. Agora o classificador atravessa o wrapper, e as opcoes dele, ate o comando real.
aj_tr_viola "aj43-env-com-interpretador-que-escreve-e-escrita" \
  "env python3 -c \"open('docs/eventos/fx.jsonl','a').write('{}')\"" "env nao esconde o python3"
aj_tr_viola "aj44-env-com-cp-para-o-rastro-e-escrita" \
  'env cp /tmp/f.jsonl docs/eventos/fx.jsonl' "env nao esconde o cp"
aj_tr_viola "aj45-timeout-com-duracao-posicional-e-escrita" \
  'timeout 5 cp /tmp/f.jsonl docs/eventos/fx.jsonl' "a duracao 5 nao e o comando real"
aj_tr_viola "aj46-sudo-com-u-e-usuario-e-escrita" \
  'sudo -u deploy cp /tmp/f.jsonl docs/eventos/fx.jsonl' "-u consome o usuario; o comando real e o cp"
aj_tr_viola "aj47-xargs-com-i-e-marcador-e-escrita" \
  'xargs -I F cp F docs/eventos/fx.jsonl' "-I consome o marcador F"
aj_tr_viola "aj48-env-com-atribuicao-de-variavel-e-escrita" \
  'env LC_ALL=C cp /tmp/f.jsonl docs/eventos/fx.jsonl' "VAR=valor depois do env nao e o comando"
aj_tr_viola "aj49-env-por-caminho-absoluto-e-escrita" \
  '/usr/bin/env cp /tmp/f.jsonl docs/eventos/fx.jsonl' "/usr/bin/env e o mesmo wrapper"
aj_tr_viola "aj50-wrapper-com-destino-anexado-e-escrita" \
  'env cp -tdocs/eventos/ /tmp/f.jsonl' "os dois achados juntos: wrapper + destino anexado"
# Cada wrapper da lista, um por um: atras de todos o comando real e o mesmo `cp` que a regra
# reprova sem wrapper nenhum.
aj_tr_viola "aj51-wrapper-command-e-atravessado" \
  'command cp /tmp/f.jsonl docs/eventos/fx.jsonl' "command"
aj_tr_viola "aj52-wrapper-exec-e-atravessado" \
  'exec cp /tmp/f.jsonl docs/eventos/fx.jsonl' "exec"
aj_tr_viola "aj53-wrapper-builtin-e-atravessado" \
  'builtin cp /tmp/f.jsonl docs/eventos/fx.jsonl' "builtin"
aj_tr_viola "aj54-wrapper-nohup-e-atravessado" \
  'nohup cp /tmp/f.jsonl docs/eventos/fx.jsonl' "nohup"
aj_tr_viola "aj55-wrapper-nice-e-atravessado" \
  'nice cp /tmp/f.jsonl docs/eventos/fx.jsonl' "nice"
aj_tr_viola "aj56-wrapper-nice-com-n-e-valor-e-atravessado" \
  'nice -n 5 cp /tmp/f.jsonl docs/eventos/fx.jsonl' "nice -n 5 (opcao com valor separado)"
aj_tr_viola "aj57-wrapper-ionice-com-c-e-valor-e-atravessado" \
  'ionice -c 2 cp /tmp/f.jsonl docs/eventos/fx.jsonl' "ionice -c 2 (opcao com valor separado)"
aj_tr_viola "aj58-wrapper-stdbuf-com-valor-anexado-e-atravessado" \
  'stdbuf -o0 cp /tmp/f.jsonl docs/eventos/fx.jsonl' "stdbuf -o0 (valor anexado, um token so)"
aj_tr_viola "aj59-wrapper-setsid-e-atravessado" \
  'setsid cp /tmp/f.jsonl docs/eventos/fx.jsonl' "setsid"
aj_tr_viola "aj60-wrapper-winpty-e-atravessado" \
  'winpty cp /tmp/f.jsonl docs/eventos/fx.jsonl' "winpty"
aj_tr_viola "aj61-wrapper-sudo-e-atravessado" \
  'sudo cp /tmp/f.jsonl docs/eventos/fx.jsonl' "sudo"
aj_tr_viola "aj62-wrapper-doas-e-atravessado" \
  'doas cp /tmp/f.jsonl docs/eventos/fx.jsonl' "doas"
aj_tr_viola "aj63-wrapper-time-e-atravessado" \
  'time cp /tmp/f.jsonl docs/eventos/fx.jsonl' "time"
aj_tr_viola "aj64-wrapper-timeout-com-opcao-longa-e-duracao-e-atravessado" \
  'timeout --signal=KILL 5 cp /tmp/f.jsonl docs/eventos/fx.jsonl' "timeout com opcao longa antes da duracao"
aj_tr_viola "aj65-wrappers-encadeados-sao-atravessados" \
  'nohup nice sudo cp /tmp/f.jsonl docs/eventos/fx.jsonl' "tres wrappers em fila"
# E os controles de LEITURA atras de wrapper: atravessar o wrapper nao pode inventar escrita.
aj_tr_le "aj66-env-com-cat-e-leitura" 'env cat docs/eventos/fx.jsonl' "env cat"
aj_tr_le "aj67-timeout-com-grep-e-leitura" \
  'timeout 5 grep write docs/eventos/fx.jsonl' 'timeout 5 grep, com write como PADRAO do grep'
aj_tr_le "aj68-env-copiando-o-rastro-para-fora-e-leitura" \
  'env cp docs/eventos/fx.jsonl /tmp/copia.jsonl' "env cp com o rastro como ORIGEM"
aj_tr_le "aj69-env-com-interpretador-que-so-le-e-leitura" \
  "env python3 -c \"print(open('docs/eventos/fx.jsonl').read())\"" "env python3 apenas lendo"
aj_tr_le "aj70-sudo-com-u-e-usuario-lendo-e-leitura" \
  'sudo -u deploy cat docs/eventos/fx.jsonl' "-u consumido, e o comando real e cat"
if [ "$AJ_TR_OK" = 1 ]; then
  aj_bom > "$AJ_T/tr-bom"; AJ_V="$(aj_verifica "$AJ_T/tr-bom")"
  [ -z "$AJ_V" ]
  afirma "aj17-transcrito-conforme-continua-aprovando" $? "${AJ_V:-escritor no inicio e no fim, nenhuma violacao}"
fi

# ------------------------------------------------- 4. a ORDEM real: primeira edicao depois do claim
aj_rastro() { # aj_rastro <arquivo> <evento:detalhe> ... — monta um rastro na ordem dada
  local arq="$1" e ev det n=0; shift
  : > "$arq"
  for e in "$@"; do
    n=$((n + 1)); ev="${e%%:*}"; det="${e#*:}"
    printf '{"ts":"2026-10-01T10:%02d:00Z","expx_eventos":1,"trabalho_id":"dc","ferramenta":"sprintx","origem":"skill","evento":"%s","fase":"f6","task":"%s","agente":"principal","resultado":"ok","detalhe":null,"arquivos":["%s"],"sessao":"c@1","harness":"c"}\n' \
      "$n" "$ev" "$([ "$ev" = arquivo_alterado ] && printf 'null' || printf 'T-01.01')" "$det" >> "$arq"
  done
}
AJ_RE='src/contador\.sh|test/dobro\.test\.sh'
aj_ordem() { # aj_ordem <nome> <esperado: 0|1> <detalhe> <eventos...>
  local nome="$1" esp="$2" det="$3"; shift 3
  aj_rastro "$AJ_T/ordem.jsonl" "$@"
  ( . "$AJ_H/testes/transcrito-agente.sh"
    rastro_edicao_depois_do_claim "$AJ_T/ordem.jsonl" T-01.01 "$AJ_RE" )
  [ "$?" -eq "$esp" ]
  afirma "$nome" $? "$det"
}
aj_ordem "aj18-primeira-edicao-depois-do-claim-aprova" 0 "claim, depois a primeira edicao da task" \
  task_iniciada:- arquivo_alterado:src/contador.sh arquivo_alterado:test/dobro.test.sh
# O DEFEITO: a primeira edicao veio ANTES do claim, e uma segunda, legitima, veio depois.
aj_ordem "aj19-primeira-edicao-antes-do-claim-reprova" 1 "edicao antes do claim nao e salva por uma edicao legitima depois" \
  arquivo_alterado:src/contador.sh task_iniciada:- arquivo_alterado:test/dobro.test.sh
aj_ordem "aj20-sem-claim-reprova" 1 "edicao sem reivindicacao nenhuma" \
  arquivo_alterado:src/contador.sh arquivo_alterado:test/dobro.test.sh
aj_ordem "aj21-sem-edicao-reprova" 1 "claim sem nenhuma edicao da task" \
  task_iniciada:- arquivo_alterado:src/outro.ts
# Guarda estrutural: a certificacao paga usa o MESMO helper, nao uma segunda copia do awk.
AJ_AR="$AJ_H/testes/agente-real-rastro.sh"
grep -qF 'rastro_edicao_depois_do_claim' "$AJ_AR" && ! grep -qF 'a > i' "$AJ_AR"; AJ_RC=$?
afirma "aj22-certificacao-paga-usa-o-helper-local" "$AJ_RC" "agente-real-rastro.sh chama o helper testavel, sem awk proprio"

# ------------------------------------------------- mutantes
AJ_M="$AJ_T/mut"
aj_copia() { # aj_copia <nome> — copia de .claude/hooks
  local r="$AJ_M/$1"; rm -rf "$r"; mkdir -p "$r"
  cp -R "$AJ_H/comum" "$AJ_H/sprintx" "$AJ_H/testes" "$r/"
  printf '%s' "$r"
}
# aj_def_cmd <tipo> — o comando-sonda de cada defeito de classificacao de comando. Um por tipo,
# para que cada mutante seja julgado por UM comando, e so por ele.
aj_def_cmd() {
  case "$1" in
    anexada)   printf 'cp -tdocs/eventos/ /tmp/f.jsonl' ;;
    abreviada) printf 'cp --targ=docs/eventos/ /tmp/f.jsonl' ;;
    longa)     printf 'cp --target-directory=docs/eventos/ /tmp/f.jsonl' ;;
    opcao)     printf 'cp -t docs/eventos/ /tmp/f.jsonl' ;;
    wrapper)   printf 'env cp /tmp/f.jsonl docs/eventos/fx.jsonl' ;;
    wrapopt)   printf 'sudo -u deploy cp /tmp/f.jsonl docs/eventos/fx.jsonl' ;;
    duracao)   printf 'timeout 5 cp /tmp/f.jsonl docs/eventos/fx.jsonl' ;;
  esac
}
aj_defeito() { # aj_defeito <raiz-hooks> <tipo> — 0 quando AQUELA arvore exibe o defeito do tipo
  local r="$1" tipo="$2" rc=1 guarda="$AJ_H"
  AJ_H="$r"
  case "$tipo" in
    saida)   aj_roda objeto "$AJ_ERR_ANSI" "$PATH"; [ "$(aj_resultado)" = ok ] && rc=0 ;;
    saida-sj) aj_roda objeto "$AJ_ERR_ANSI" "$AJ_SEMJQ"; [ "$(aj_resultado)" != falha ] && rc=0 ;;
    ordem)   aj_rastro "$AJ_T/o.jsonl" arquivo_alterado:src/contador.sh task_iniciada:- arquivo_alterado:test/dobro.test.sh
             ( . "$r/testes/transcrito-agente.sh"
               rastro_edicao_depois_do_claim "$AJ_T/o.jsonl" T-01.01 "$AJ_RE" ) && rc=0 ;;
    manual)  { aj_bom; aj_ev Bash '{"command":"cp /tmp/f.jsonl docs/eventos/fx.jsonl"}'; } > "$AJ_T/trm"
             ( . "$r/testes/transcrito-agente.sh"; transcrito_verifica "$AJ_T/trm" 1111-2222 fx T-01.01 || : ) \
               | grep -q '^rastro_manual:' || rc=0 ;;
    leitura) { aj_bom; aj_ev Bash '{"command":"cat docs/eventos/fx.jsonl"}'; } > "$AJ_T/trl"
             [ -n "$( . "$r/testes/transcrito-agente.sh"; transcrito_verifica "$AJ_T/trl" 1111-2222 fx T-01.01 || : )" ] && rc=0 ;;
    destino) { aj_bom; aj_ev Bash '{"command":"cp /tmp/forjado.jsonl docs/eventos/fx.jsonl 2>/dev/null"}'; } > "$AJ_T/trd"
             ( . "$r/testes/transcrito-agente.sh"; transcrito_verifica "$AJ_T/trd" 1111-2222 fx T-01.01 || : ) \
               | grep -q '^rastro_manual:' || rc=0 ;;
    pegajoso) { aj_bom
               aj_ev Bash "$(python3 -c 'import json,sys; print(json.dumps({"command":sys.argv[1]}))' "$AJ_CMD_LE_B")"
             } > "$AJ_T/trp"
             [ -n "$( . "$r/testes/transcrito-agente.sh"; transcrito_verifica "$AJ_T/trp" 1111-2222 fx T-01.01 || : )" ] && rc=0 ;;
    # Os defeitos de PR#14: cada um tem o seu comando-sonda, e o defeito e a sonda passar por
    # leitura quando ela escreve no rastro.
    anexada|abreviada|longa|opcao|wrapper|wrapopt|duracao)
             { aj_bom
               aj_ev Bash "$(python3 -c 'import json,sys; print(json.dumps({"command":sys.argv[1]}))' "$(aj_def_cmd "$tipo")")"
             } > "$AJ_T/trw"
             ( . "$r/testes/transcrito-agente.sh"; transcrito_verifica "$AJ_T/trw" 1111-2222 fx T-01.01 || : ) \
               | grep -q '^rastro_manual:' || rc=0 ;;
  esac
  AJ_H="$guarda"
  return "$rc"
}
aj_mutante() { # aj_mutante <nome> <rc da geracao> <raiz-hooks> <tipo que TEM de reverter> [tipos que NAO podem reverter...]
  local nome="$1" rcg="$2" r="$3" tipo="$4" rc=1 carona="" c; shift 4
  if [ "$rcg" -eq 0 ]; then
    aj_defeito "$r" "$tipo" && rc=0
    # Nao vale morrer de carona: o que o mutante NAO mexeu tem de continuar classificado certo.
    for c in "$@"; do aj_defeito "$r" "$c" && carona="$carona$c "; done
  fi
  [ "$rcg" -eq 0 ] && [ "$rc" -eq 0 ] && [ -z "$carona" ]
  afirma "$nome" $? "o mutante volta ao defeito de '$tipo' (rc geracao=$rcg)${carona:+ — MORTE DE CARONA em: $carona}"
}
# m1 — a remocao de ANSI desaparece: a saida colorida volta a ser classificada como ok.
AJR="$(aj_copia m1)" && muta_lit "$AJ_H/comum/rastro.sh" "$AJR/comum/rastro.sh" \
  '    *"$RASTRO_ESC"*)' '    *naoexisteESC*)'
aj_mutante "ajm-mutante-1-sem-remocao-de-ansi" $? "$AJR" saida
# m2 — a leitura do tool_response volta a aceitar so string: no objeto, sem jq, nada e classificado.
AJR="$(aj_copia m2)" && muta_lit "$AJ_H/comum/rastro-post.sh" "$AJR/comum/rastro-post.sh" \
  'rastro_tool_response_em SAIDA "$ENTRADA"' 'SAIDA="$(rastro_json_get "$ENTRADA" tool_response)"'
aj_mutante "ajm-mutante-2-tool-response-so-como-string" $? "$AJR" saida-sj
# m3 — a prova da ordem volta a so marcar a edicao DEPOIS do claim.
AJR="$(aj_copia m3)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  '$0 ~ re && !a { a = NR }' '$0 ~ re && i && !a { a = NR }'
aj_mutante "ajm-mutante-3-ordem-ignora-edicao-antes-do-claim" $? "$AJR" ordem
# m4 — a auditoria volta a olhar so redirecao/tee/sed -i: cp e mv passam.
AJR="$(aj_copia m4)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  'if _tr_escreve_no_rastro "$cmd"; then' 'if [[ $cmd =~ $_TR_REDIR ]] || [[ $cmd =~ $_TR_SED ]]; then'
aj_mutante "ajm-mutante-4-auditoria-sem-cp-e-mv" $? "$AJR" manual
# m5 — a auditoria vira blacklist de mencao: `cat docs/eventos/...` passa a reprovar.
AJR="$(aj_copia m5)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  '  case "$c" in *docs/eventos*) ;; *) return 1 ;; esac' '  case "$c" in *docs/eventos*) return 0 ;; *) return 1 ;; esac'
aj_mutante "ajm-mutante-5-blacklist-reprova-leitura" $? "$AJR" leitura
# m6 — a decisao de destino volta a olhar so o ULTIMO token do segmento: com `2>/dev/null` no fim,
# o destino real fica invisivel e `cp origem docs/eventos/x 2>/dev/null` passa.
AJR="$(aj_copia m6)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  '        # Forma posicional: o primeiro operando e ORIGEM, qualquer outro e destino.' \
  '        op=("${tk[$((${#tk[@]} - 1))]}")'
aj_mutante "ajm-mutante-6-destino-volta-a-ser-o-ultimo-token" $? "$AJR" destino
# m7 — o estado do interpretador volta a ser PEGAJOSO entre segmentos: o `grep -c write` do
# segmento seguinte herda a escrita e a leitura do rastro reprova.
AJR="$(aj_copia m7)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  '    if [[ $cab =~ ^($_TR_SO_LEEM)$ ]] && [[ $seg != *'"'"'('"'"'* ]]; then' '    if false; then'
aj_mutante "ajm-mutante-7-interpretador-pegajoso-entre-segmentos" $? "$AJR" pegajoso
# PR#14 — os tres pedacos novos da regra, um mutante cada, e cada um julgado pelo seu comando-sonda
# com os outros listados como controle de NAO-carona.
#
# m8 — o destino ANEXADO a opcao curta deixa de ser lido: `-tdocs/eventos/` volta a pegar o token
# seguinte como destino, e a escrita fica invisivel. A forma separada (`-t dir`) nao e tocada.
AJR="$(aj_copia m8)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  'destino="${t#*t}"' 'destino=""'
aj_mutante "ajm-mutante-8-opcao-curta-sem-o-destino-anexado" $? "$AJR" anexada opcao abreviada longa wrapper wrapopt duracao manual leitura
# m9 — a opcao longa volta a exigir o nome INTEIRO: `--targ=` deixa de ser abreviacao valida.
AJR="$(aj_copia m9)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  'case target-directory in "$o"*) return 0 ;; esac' 'case target-directory in "$o") return 0 ;; esac'
aj_mutante "ajm-mutante-9-opcao-longa-sem-abreviacao" $? "$AJR" abreviada longa anexada opcao wrapper wrapopt duracao manual leitura
# m10 — a lista de wrappers transparentes desaparece: `env cp ...` volta a ser julgado como `env`,
# nome fora de toda lista, segmento ignorado.
AJR="$(aj_copia m10)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  "_TR_WRAPPER='env|" "_TR_WRAPPER='naoexisteWRAPPER|"
aj_mutante "ajm-mutante-10-sem-os-wrappers-transparentes" $? "$AJR" wrapper anexada opcao abreviada longa manual leitura
# m11 — o consumo da opcao com valor em token SEPARADO desaparece: `sudo -u deploy cp ...` acha
# `deploy` no lugar do `cp`. O wrapper sem opcao (`env cp`) e a duracao do `timeout` nao sao tocados.
AJR="$(aj_copia m11)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  'if [ -n "$oparg" ] && [[ $t =~ ^($oparg)$ ]]; then n=$((n + 2)); else n=$((n + 1)); fi' 'n=$((n + 1))'
aj_mutante "ajm-mutante-11-sem-o-consumo-das-opcoes-do-wrapper" $? "$AJR" wrapopt wrapper duracao anexada opcao abreviada longa manual leitura
# m12 — a duracao POSICIONAL do `timeout` deixa de ser consumida: o `5` passa por comando real.
AJR="$(aj_copia m12)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  'if [ "$cab" = timeout ] && [ "$n" -lt "${#tk[@]}" ]; then' 'if [ "$cab" = naotimeout ] && [ "$n" -lt "${#tk[@]}" ]; then'
aj_mutante "ajm-mutante-12-sem-a-duracao-posicional-do-timeout" $? "$AJR" duracao wrapper wrapopt anexada opcao abreviada longa manual leitura
# Controle da propria bateria: a copia SEM mutacao nenhuma nao exibe defeito nenhum.
AJR="$(aj_copia controle)"; AJ_RC=0
for aj_d in anexada abreviada longa opcao wrapper wrapopt duracao manual leitura destino pegajoso saida saida-sj ordem; do
  aj_defeito "$AJR" "$aj_d" && { AJ_RC=1; AJ_VIVO="${AJ_VIVO-}$aj_d "; }
done
afirma "ajm-controle-copia-intacta-nao-exibe-defeito" "$AJ_RC" "${AJ_VIVO-nenhum defeito na copia sem mutacao}"

rm -rf "$AJ_T"

echo "== AK. 1.00 MEDIDO e fator legitimo, e o caminho critico se escolhe pela duracao corrigida (PR#12) =="
# Dois defeitos de contrato na estimativa:
#
#   1. A proibicao do neutro (DS-46) virou proibicao do VALOR. Ela existe para que ausencia de
#      fator nao se disfarce de fator — e ausencia se diz com `null`. Mas um tipo com 3 ou mais
#      entradas elegiveis cuja media de desvios da exatamente `1.00` tem um fator MEDIDO, e ele
#      diz algo: "este tipo tem historico suficiente e o projeto acerta a estimativa dele".
#      Proibir `1.00` indiscriminadamente obrigava a gravar `null` ali — ou seja, obrigava a
#      mentir "nao ha historico" exatamente no tipo melhor calibrado do projeto, e a apagar a
#      distincao que a propria DS-46 queria preservar. O que continua proibido e `1.00` NO LUGAR
#      de `null`: sem historico, com menos de 3 elegiveis ou com `fator_ativo: false`.
#   2. A selecao do caminho critico usava a media CRUA. O `fator(t)` entra na soma e na quadratura
#      (DS-167), mas a regra de ACHAR a cadeia mais longa somava `media_task(t)` sem fator — e com
#      fatores diferentes entre os tipos o ramo mais longo em media crua nao e o mais longo de
#      verdade. A saida publicava a cadeia errada e um `caminho_critico` menor que o real.
#
# Os dois casos tem oraculo executavel aqui, nao so marcador de texto: o numero que a regra manda
# gravar e o ramo que a regra manda escolher sao calculados, e e contra esse calculo que o
# contrato escrito e conferido.
AK_SK="$SK"

# --------------------------------------------------------- oraculo 1: o fator que se grava
# Dado os `desvio` persistidos de um tipo ("null" para a entrada sem desvio), o que o item de
# `calibracao_por_tipo` tem de gravar em `fator`: `null` com menos de 3 elegiveis, ou a media das
# elegiveis com duas casas half-up (DS-160/DS-164) — INCLUSIVE quando essa media e `1.00`.
ak_fator() { # ak_fator <desvio|null> ...
  awk -v lista="$*" '
    BEGIN {
      n = split(lista, v, / +/); soma = 0; e = 0
      for (i = 1; i <= n; i++) { if (v[i] == "null") continue; e++; soma += v[i] + 0 }
      if (e < 3) { print "null"; exit }                      # fator_ativo: false (DS-164)
      m = soma / e
      printf "%.2f\n", int(m * 100 + 0.5) / 100              # duas casas, half-up (DS-160)
    }'
}
[ "$(ak_fator 1.00 1.00 1.00)" = "1.00" ]
afirma "ak1-oraculo-media-exata-de-1-e-fator-1.00" $? "3 elegiveis, todas 1.00 -> fator medido 1.00, nunca null"
[ "$(ak_fator 0.90 1.00 1.10)" = "1.00" ]
afirma "ak2-oraculo-desvios-que-se-compensam-dao-1.00" $? "0,90 + 1,00 + 1,10 -> media exatamente 1.00"
[ "$(ak_fator 0.98 1.00 1.03)" = "1.00" ]
afirma "ak3-oraculo-media-que-arredonda-para-1.00" $? "1,00333... -> 1.00 pelas duas casas half-up"
[ "$(ak_fator 1.00 1.00)" = "null" ]
afirma "ak4-oraculo-duas-elegiveis-e-null-nao-1.00" $? "menos de 3 elegiveis -> null, e e a proibicao da DS-46 que continua"
[ "$(ak_fator null null null)" = "null" ]
afirma "ak5-oraculo-sem-desvio-elegivel-e-null" $? "nenhuma entrada elegivel -> null, nunca 1.00"
[ "$(ak_fator 1.13 1.13 1.17 1.20)" = "1.16" ]
afirma "ak6-oraculo-exemplo-canonico-nao-regride" $? "o 1.16 da DS-160 continua saindo igual"

# --------------------------------------------------------- oraculo 2: qual ramo e o critico
# Cada ramo e uma cadeia; a duracao dela e a soma de media_task(t) * fator(t). Com fatores
# diferentes entre os tipos, o ramo mais longo em media CRUA pode nao ser o mais longo corrigido.
ak_critico() { # ak_critico <modo: cru|corrigido> <ramo:media:fator> ...
  local modo="$1"; shift
  awk -v modo="$modo" -v lista="$*" '
    BEGIN {
      n = split(lista, r, / +/)
      for (i = 1; i <= n; i++) {
        split(r[i], c, ":")
        D[c[1]] += c[2] * (modo == "corrigido" ? c[3] : 1)
      }
      melhor = ""; maior = -1
      for (k in D) if (D[k] > maior) { maior = D[k]; melhor = k }
      printf "%s=%.2f\n", melhor, maior
    }'
}
AK_RAMOS="A:10:0.80 B:9:1.20"
[ "$(ak_critico cru $AK_RAMOS)" = "A=10.00" ]
afirma "ak7-oraculo-pela-media-crua-o-ramo-a-parece-critico" $? "10,00 > 9,00 — a conta ERRADA, registrada para o caso ter contraste"
[ "$(ak_critico corrigido $AK_RAMOS)" = "B=10.80" ]
afirma "ak8-oraculo-corrigido-pelo-fator-o-critico-e-o-ramo-b" $? "10,00*0,80=8,00 contra 9,00*1,20=10,80 — o fator TROCA o ramo critico"
# Controle: com o mesmo fator nos dois ramos, a correcao nao muda a escolha.
[ "$(ak_critico corrigido A:10:1.20 B:9:1.20)" = "A=12.00" ]
afirma "ak9-oraculo-fator-igual-nos-dois-nao-troca-o-ramo" $? "fator igual: a ordem dos ramos e a mesma da media crua"

# --------------------------------------------------------- o contrato escrito
AK_LIT_SCH_100='`1.00` medido é um fator legítimo, e é obrigatório gravá-lo (DS-172)'
AK_LIT_SCH_100_QUANDO='o canônico daquele tipo tem `fator_ativo: true` e a média dos `desvio` elegíveis é exatamente `1.00`'
AK_LIT_SCH_100_PROIBIDO='O que a DS-46 proíbe é `1.00` **no lugar de** `null`'
AK_LIT_SCH_POR_TIPO='Nenhum item de `calibracao_por_tipo` usa `1.00` no lugar de `null`'
AK_LIT_EST_100='`1.00` **medido** é fator legítimo e vai gravado como `1.00`, nunca convertido em `null` (DS-172)'
AK_LIT_TPL_100='`1.00` medido vai gravado como `1.00`'
# A proibicao preservada: a frase da DS-46 continua nos dois arquivos que a bancada ja exigia.
AK_LIT_SCH_DISFARCE='Nunca `1.00` para disfarçar ausência de fator (DS-46)'
AK_LIT_EST_DISFARCE='Nunca `1.00` disfarçando ausência de fator (DS-46)'
# E a frase antiga, que proibia o VALOR sem distinguir o disfarce, nao sobrevive.
AK_LIT_PROIBE_ANTIGA='!Nenhum item de `calibracao_por_tipo` grava `1.00` como fator ativo'
# Caminho critico: a selecao usa a duracao corrigida, e o exemplo do ramo que troca existe.
AK_LIT_EST_SEL='`caminho(t) = media_task(t) * fator(t) + máximo dos caminho(anteriores)`'
AK_LIT_EST_SEL_REGRA='A duração que seleciona o caminho é a já corrigida pelo `fator(t)` do tipo daquela task, nunca a média crua (DS-173)'
AK_LIT_EST_EXEMPLO='Exemplo em que o fator troca o ramo crítico'
AK_LIT_EST_EXEMPLO_NUM='as durações corrigidas são `8,00` e `10,80`, e o ramo crítico é o de `T-02.01`'
AK_LIT_TPL_SEL='A cadeia é **selecionada** pela duração já corrigida — `media_task(t) * fator(t)` —, nunca pela média crua'

ak_caso() { # ak_caso <caso> <dir> -> 0 se o caso PASSA naquela arvore
  local c="$1" d="$2"
  case "$c" in
    # O 1.00 medido e fator legitimo, e o contrato diz QUANDO.
    ak_100_legitimo)
      ad_lit "$d/references/00-schema.md" "$AK_LIT_SCH_100" \
             "$d/references/00-schema.md" "$AK_LIT_SCH_100_QUANDO" \
             "$d/references/07-estimativa.md" "$AK_LIT_EST_100" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AK_LIT_TPL_100" ;;
    # A proibicao da DS-46 continua, agora nomeando o que ela proibe: 1.00 no lugar de null.
    ak_100_no_lugar_de_null_proibido)
      ad_lit "$d/references/00-schema.md" "$AK_LIT_SCH_100_PROIBIDO" \
             "$d/references/00-schema.md" "$AK_LIT_SCH_DISFARCE" \
             "$d/references/07-estimativa.md" "$AK_LIT_EST_DISFARCE" ;;
    # A regra por tipo passou a proibir o disfarce, nao o valor — e a forma antiga nao sobrevive.
    ak_por_tipo_proibe_o_disfarce)
      ad_lit "$d/references/00-schema.md" "$AK_LIT_SCH_POR_TIPO" \
             "$d/references/00-schema.md" "$AK_LIT_PROIBE_ANTIGA" ;;
    # A selecao do caminho critico usa a duracao corrigida, nos dois arquivos que a publicam.
    ak_selecao_corrigida_pelo_fator)
      ad_lit "$d/references/07-estimativa.md" "$AK_LIT_EST_SEL" \
             "$d/references/07-estimativa.md" "$AK_LIT_EST_SEL_REGRA" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AK_LIT_TPL_SEL" ;;
    # E o caso em que fatores diferentes trocam o ramo critico esta escrito, com os numeros.
    ak_exemplo_troca_o_ramo)
      ad_lit "$d/references/07-estimativa.md" "$AK_LIT_EST_EXEMPLO" \
             "$d/references/07-estimativa.md" "$AK_LIT_EST_EXEMPLO_NUM" ;;
    # DS-172 e DS-173 registradas, append-only, e as anteriores intactas.
    ak_ds_registradas)
      local v172 v173
      v172="$(grep -F '| DS-172 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
      v173="$(grep -F '| DS-173 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
      [ -n "$v172" ] && [ -n "$v173" ] \
        && printf '%s' "$v172" | grep -qF 'DS-46' \
        && printf '%s' "$v172" | grep -qF 'substitui a parte incompatível da DS-46' \
        && printf '%s' "$v173" | grep -qiF 'caminho crítico' \
        && grep -qF '| DS-46 |' "$d/DECISOES-DA-SKILL.md" \
        && grep -qF '| DS-160 |' "$d/DECISOES-DA-SKILL.md" \
        && grep -qF '| DS-165 |' "$d/DECISOES-DA-SKILL.md" \
        && grep -qF '| DS-166 |' "$d/DECISOES-DA-SKILL.md" \
        && grep -qF '| DS-167 |' "$d/DECISOES-DA-SKILL.md" ;;
    *) return 1 ;;
  esac
}
AK_CASOS="ak_100_legitimo ak_100_no_lugar_de_null_proibido ak_por_tipo_proibe_o_disfarce
ak_selecao_corrigida_pelo_fator ak_exemplo_troca_o_ramo ak_ds_registradas"
ak_nome() { printf '%s' "$1" | tr '_' '-'; }
for ak_c in $AK_CASOS; do
  ak_caso "$ak_c" "$AK_SK"; ak_rc=$?
  afirma "$(ak_nome "$ak_c")" "$ak_rc" "lido da arvore do contrato em $AK_SK"
done

# --------------------------------------------------------- mutantes
AKW="$(mktemp -d)"
ak_copia() { rm -rf "$AKW/$1"; mkdir -p "$AKW/$1"; cp -R "$AK_SK/." "$AKW/$1/"; printf '%s' "$AKW/$1"; }
ak_muta() { [ -f "$1/$2" ] || return 1; muta_lit "$1/$2" "$1/$2.m" "$3" "$4" && mv "$1/$2.m" "$1/$2"; }
ak_mata() { local c; for c in $AK_CASOS; do ak_caso "$c" "$1" || { printf '%s' "$c"; return; }; done; }
ak_mutante() { # ak_mutante <nome> <rc da geracao> <dir> <caso que TEM de matar>...
  local nome="$1" rcg="$2" d="$3" c vivos=""; shift 3
  if [ "$rcg" -eq 0 ]; then for c in "$@"; do ak_caso "$c" "$d" && vivos="$vivos$c "; done; fi
  [ "$rcg" -eq 0 ] && [ -z "$vivos" ]; local rc=$?
  afirma "$nome" "$rc" "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rcg)"
}
AK_CTL="$(ak_copia controle)"
AK_K="$(ak_mata "$AK_CTL")"; [ -z "$AK_K" ]; ak_rc=$?
afirma "akm-controle-copia-intacta-sobrevive" "$ak_rc" "${AK_K:-nenhum caso reprova a copia sem mutacao}"

# m1 — o 1.00 medido deixa de ser declarado legitimo no schema.
AK_M="$(ak_copia m1)"
ak_muta "$AK_M" references/00-schema.md "$AK_LIT_SCH_100" 'Nada a dizer sobre 1.00'
ak_mutante "akm-mutante-1-schema-sem-o-1.00-medido" $? "$AK_M" ak_100_legitimo
# m2 — a proibicao do DISFARCE desaparece: `1.00` passaria a poder substituir `null`.
AK_M="$(ak_copia m2)"
ak_muta "$AK_M" references/00-schema.md 'O que a DS-46 proíbe é `1.00` **no lugar de**' 'Qualquer valor serve'
ak_mutante "akm-mutante-2-schema-sem-a-proibicao-do-disfarce" $? "$AK_M" ak_100_no_lugar_de_null_proibido
# m3 — a regra por tipo volta a proibir o VALOR, nao o disfarce (a forma antiga ressuscita).
AK_M="$(ak_copia m3)"
ak_muta "$AK_M" references/00-schema.md "$AK_LIT_SCH_POR_TIPO" \
  'Nenhum item de `calibracao_por_tipo` grava `1.00` como fator ativo'
ak_mutante "akm-mutante-3-por-tipo-volta-a-proibir-o-valor" $? "$AK_M" ak_por_tipo_proibe_o_disfarce
# m4 — a selecao do caminho critico volta a somar a media CRUA.
AK_M="$(ak_copia m4)"
ak_muta "$AK_M" references/07-estimativa.md "$AK_LIT_EST_SEL" \
  '`caminho(t) = media_task(t) + máximo dos caminho(anteriores)`'
ak_mutante "akm-mutante-4-selecao-volta-a-media-crua" $? "$AK_M" ak_selecao_corrigida_pelo_fator
# m5 — o template perde a frase da selecao corrigida.
AK_M="$(ak_copia m5)"
ak_muta "$AK_M" assets/TEMPLATE-ESTIMATIVA.md "$AK_LIT_TPL_SEL" 'A cadeia e a mais longa.'
ak_mutante "akm-mutante-5-template-sem-a-selecao-corrigida" $? "$AK_M" ak_selecao_corrigida_pelo_fator
# m6 — o exemplo do ramo que troca e apagado: a regra fica sem o caso que a demonstra.
AK_M="$(ak_copia m6)"
ak_muta "$AK_M" references/07-estimativa.md "$AK_LIT_EST_EXEMPLO_NUM" 'os dois ramos empatam'
ak_mutante "akm-mutante-6-exemplo-sem-os-numeros-do-ramo" $? "$AK_M" ak_exemplo_troca_o_ramo
# m7 — DS-172/DS-173 apagadas do registro.
AK_M="$(ak_copia m7)"
ak_muta "$AK_M" DECISOES-DA-SKILL.md '| DS-172 |' '| DS-172-apagada |'
ak_mutante "akm-mutante-7-ds172-apagada" $? "$AK_M" ak_ds_registradas
# m8 — a DS-172 deixa de dizer QUAL parte das decisoes anteriores ela substitui.
AK_M="$(ak_copia m8)"
ak_muta "$AK_M" DECISOES-DA-SKILL.md 'substitui a parte incompatível da DS-46' 'ignora a DS-46'
ak_mutante "akm-mutante-8-ds172-sem-a-substituicao-explicita" $? "$AK_M" ak_ds_registradas

rm -rf "$AKW"

echo "== AL. DS-175: autorizacao tardia explicita do orcamento F6 =="
AL_SCHEMA="$SK/references/00-schema.md"
AL_PLANO="$SK/references/03-plano.md"
AL_EXEC="$SK/references/06-execucao.md"
AL_RASTRO="$SK/references/08-rastro.md"
AL_SKILL="$SK/SKILL.md"
AL_TPL="$SK/assets/TEMPLATE-PLANEJAMENTO.md"
AL_DSF="$SK/DECISOES-DA-SKILL.md"
al_tem() { grep -qF -- "$2" "$1"; }

al_tem "$AL_SCHEMA" 'As três chaves tardias existem juntas ou nenhuma existe' \
  && al_tem "$AL_SCHEMA" 'A autoridade canônica tardia é `autorizacao_tardia_f6_por`' \
  && al_tem "$AL_SCHEMA" '`orcamento_declarado_por` continua' \
  && al_tem "$AL_SCHEMA" 'pertencendo ao orçamento da F5' \
  && al_tem "$AL_SCHEMA" '`replanejamento_execucao_recusado` com motivo `orcamento_f6_nao_declarado` é o único terminal recuperável'
afirma "ds175-contrato-schema" $? "tupla all-or-none, autoridade separada e terminal exato"

al_schema_exemplo_valido() {
  local d f out rc
  d="$(mktemp -d "$K/schema-publico.XXXXXX")"
  nova_feature "$d" exportacao-csv-relatorios
  f="$d/docs/sprintx/features/exportacao-csv-relatorios/00-PLANEJAMENTO.md"
  awk '
    /^### `00-PLANEJAMENTO.md`/ { secao=1 }
    secao && /^```yaml$/ { bloco=1; next }
    bloco && /^```$/ { exit }
    bloco { print }
  ' "$AL_SCHEMA" > "$f"
  git -C "$d" add "$f" && git -C "$d" commit -q -m 'fixture: exemplo publico do planejamento' -- "$f" || return 1
  out="$(kpl "$PL" "$d" fase exportacao-csv-relatorios)"; rc=$?
  [ "$rc" -eq 0 ] && [ "$(kv "$out" fonte)" = planejamento ]
}
al_schema_exemplo_valido
afirma "ds175-schema-exemplo-executavel" $? "o YAML canonico publicado e aceito pelo leitor oficial"

al_tem "$AL_PLANO" '`replanejamento_execucao_recusado` continua terminal até uma chamada humana explícita' \
  && al_tem "$AL_PLANO" 'planejamento.sh autorizar-replanejamento-execucao <slug> <max_replanejamentos_f6> <autorizado_por>' \
  && al_tem "$AL_PLANO" 'A autorização tardia abre a rodada 1 e devolve o planejamento para F3'
afirma "ds175-contrato-plano" $? "terminal continua terminal; comando explicito retorna a F3"

al_tem "$AL_EXEC" '**Somente uma decisão humana explícita** pode autorizar o orçamento tardio da F6' \
  && al_tem "$AL_EXEC" 'autorizacao_f6=checkpoint_pendente' \
  && al_tem "$AL_EXEC" 'argumentos → congeladas/parciais → B-NN/task se pendente → persistência' \
  && al_tem "$AL_EXEC" 'checkpoint <slug>` repete as provas antes de preparar o índice' \
  && al_tem "$AL_EXEC" '`2` trava existente, fronteira ou parcial (com `motivo=` estruturado)' \
  && al_tem "$AL_EXEC" '`5` transição ou indisponibilidade da trava'
afirma "ds175-contrato-execucao" $? "humano, saidas/codigos, precedencia e recuperacao"

al_tem "$AL_RASTRO" '`orcamento_f6_autorizado`' \
  && al_tem "$AL_RASTRO" 'exatamente uma vez junto de `replanejamento_execucao_iniciado`' \
  && al_tem "$AL_RASTRO" 'Retomada e checkpoint pendente não duplicam nenhum dos dois eventos'
afirma "ds175-contrato-rastro" $? "dois eventos uma vez, repeticao silenciosa"

al_tem "$AL_SKILL" 'scripts/planejamento.sh autorizar-replanejamento-execucao <slug> <max_replanejamentos_f6> <autorizado_por>' \
  && al_tem "$AL_SKILL" 'Somente `orcamento_f6_nao_declarado` é recuperável por autorização tardia' \
  && al_tem "$AL_SKILL" '`classes_mistas`, legados e orçamentos esgotados continuam terminais'
afirma "ds175-contrato-skill" $? "comando e fronteira exata entre terminais"

al_tem "$AL_TPL" '# opcionais e inseparáveis: autorização humana tardia da F6 (DS-175)' \
  && al_tem "$AL_TPL" 'autorizacao_tardia_f6_por:' \
  && al_tem "$AL_TPL" '# autoridade canônica da F6 tardia; não reutilizar orcamento_declarado_por'
afirma "ds175-contrato-template" $? "tupla opcional e autoridade canonica comentadas"

[ "$(grep -c '^| DS-175 |' "$AL_DSF")" -eq 1 ] \
  && al_tem "$AL_DSF" 'autorizar-replanejamento-execucao' \
  && al_tem "$AL_DSF" 'orcamento_f6_nao_declarado' \
  && al_tem "$AL_DSF" 'autorizacao_tardia_f6_por'
afirma "ds175-decisao-append-only" $? "uma linha DS-175 fiel a spec e decisoes anteriores intactas"

# --------------------------------------------------------- mutantes DS-175
# Cada copia leva planejamento + bloqueios + helper de caminho + trava. O controle
# intacto percorre todos os oraculos usados pelos 21 mutantes; cada mutante muda
# uma unica regra semantica e precisa morrer no caso que a nomeia.
al_copia() { # al_copia <nome> -> planejamento.sh isolado
  local s; s="$(copia_skill_k "al-$1")" || return 1
  cp "$PL" "$s" || return 1
  printf '%s' "$s"
}
al_muta() { # al_muta <arquivo> <trecho> <troca>
  muta_lit "$1" "$1.m" "$2" "$3" && mv "$1.m" "$1"
}
al_roda() { # al_roda <caso> <planejamento-mutante>
  local c="$1" s="$2" d
  d="$(kcopia "$FXN")" || return 1
  "$c" "$s" "$d"
}
al_hash_divergente() { # a mudanca preserva path/estado, mas troca o hash
  local s="$1" d="$2" f a ev h ck evck rc out
  f="$(kf "$d")"; a="$f/00-PLANEJAMENTO.md"; ev="$d/docs/eventos/menu.jsonl"
  sed 's|      altera: \[src/ui/cabecalho-topo.tsx\]|      altera: [src/menu/perfil.ts]|' \
    "$f/sprint-04/tasks.md" > "$K/al-hash.tmp" && mv "$K/al-hash.tmp" "$f/sprint-04/tasks.md"
  mkdir -p "$d/src/menu"; printf 'antes\n' > "$d/src/menu/perfil.ts"
  git -C "$d" add "$f/sprint-04/tasks.md" src/menu/perfil.ts \
    && git -C "$d" commit -q -m 'fixture: hash parcial tardio' || return 1
  printf 'depois\n' > "$d/src/menu/perfil.ts"
  l_aut_terminal "$s" "$d" && l_aut_aplica "$s" "$d" 2 usuario >/dev/null || return 1
  printf 'terceiro\n' > "$d/src/menu/perfil.ts"
  h="$(git -C "$d" rev-parse HEAD)"; ck="$(cksum < "$a")"; evck="$(cksum < "$ev")"
  out="$(l_aut_aplica "$s" "$d" 2 usuario)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" motivo)" = parcial_divergente ] \
    && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ] \
    && [ "$(cksum < "$ev")" = "$evck" ]
}
al_mutante() { # al_mutante <nome> <rc-geracao> <script> <caso>...
  local nome="$1" rcg="$2" s="$3" c vivos=""; shift 3
  if [ "$rcg" -eq 0 ]; then
    for c in "$@"; do al_roda "$c" "$s" && vivos="$vivos$c "; done
  fi
  [ "$rcg" -eq 0 ] && [ -z "$vivos" ]; local rc=$?
  afirma "$nome" "$rc" "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rcg)"
}

AL_CASOS="l_aut_limpa l_aut_parciais l_aut_dono_e_clone l_aut_bloqueios l_aut_fronteira
l_aut_concorrente l_aut_terminais l_aut_trava l_aut_sem_planejamento_e_sem_marco l_aut_trava_ambiente k_aut_valida_origem_data_recusa
l5_checkpoint_e_retomada l5_pendente_invalido al_hash_divergente
l5_retomada_duravel_recusa_parcial_perdido l5_fechamento_pendente_e_fechado"
AL_CTL="$(al_copia controle)"; AL_VIVOS=""
for al_c in $AL_CASOS; do al_roda "$al_c" "$AL_CTL" || AL_VIVOS="$AL_VIVOS$al_c "; done
[ -z "$AL_VIVOS" ]; afirma "ds175-mutante-controle-intacto" $? "${AL_VIVOS:-todos os oraculos sobrevivem na copia intacta}"

# 01 — qualquer motivo do terminal recusado passaria pela guarda inicial.
AL_M="$(al_copia m01)"
al_muta "$AL_M" '      || [ "$P_RECUSA" != orcamento_f6_nao_declarado ]; then' '      || false; then'
al_mutante "ds175-mutante-01" $? "$AL_M" l_aut_terminais

# 02 — classes misturadas deixam de barrar a abertura.
AL_M="$(al_copia m02)"
al_muta "$AL_M" '  [ -z "$outros" ] || falha "$E_CONTRATO" "autorizacao tardia exige somente defeito_de_plano aberto: $outros"' '  : # mutante aceita classes_mistas'
al_mutante "ds175-mutante-02" $? "$AL_M" l_aut_bloqueios

# 03 — o teto e gravado, mas a rodada continua zero.
AL_M="$(al_copia m03)"
al_muta "$AL_M" '  W6_N=$((P_N6 + 1)); W6_BLQ="$defeitos"; W6_CONG="$C_IDS"; W6_ASS="$C_ASS"; W6_PARC="$F_PARC"' '  W6_N="$P_N6"; W6_BLQ="$defeitos"; W6_CONG="$C_IDS"; W6_ASS="$C_ASS"; W6_PARC="$F_PARC"'
al_mutante "ds175-mutante-03" $? "$AL_M" l_aut_limpa

# 04 — a rodada incrementa sem materializar a tupla tardia.
AL_M="$(al_copia m04)"
al_muta "$AL_M" '    W_AUT6=presente; W_AUT6_POR="$aut_por"; W_AUT6_EM="$aut_em"; W_AUT6_ORIGEM="$aut_origem"; W_RECUSA=""' '    W_AUT6=ausente; W_AUT6_POR=""; W_AUT6_EM=""; W_AUT6_ORIGEM=""; W_RECUSA=""'
al_mutante "ds175-mutante-04" $? "$AL_M" l_aut_limpa

# 05 — a origem terminal deixa de ser preservada na auditoria.
AL_M="$(al_copia m05)"
al_muta "$AL_M" 'W_AUT6_ORIGEM="$aut_origem"' 'W_AUT6_ORIGEM=""'
al_mutante "ds175-mutante-05" $? "$AL_M" l_aut_limpa

# 06 — a task do B-NN nao precisa mais estar bloqueada.
AL_M="$(al_copia m06)"
al_muta "$AL_M" '    [ "$st" = bloqueada ] || falha "$E_CONTRATO" "$b aponta $t, que esta '\''${st:-fora do plano}'\'': a task precisa estar bloqueada"' '    : # mutante ignora task nao bloqueada'
al_mutante "ds175-mutante-06" $? "$AL_M" l_aut_bloqueios

# 07 — a aplicacao ignora toda a fronteira segura.
AL_M="$(al_copia m07)"
al_muta "$AL_M" '  fronteira_segura' '  : # mutante sem fronteira_segura'
al_mutante "ds175-mutante-07" $? "$AL_M" l_aut_fronteira

# 08 — o retrato parcial compara so path/estado e ignora o hash.
AL_M="$(al_copia m08)"
al_muta "$AL_M" '  [ "$R_TSV" = "$esperado" ] && return 0' '  [ "$(printf '\''%s\n'\'' "$R_TSV" | cut -f1,2)" = "$(printf '\''%s\n'\'' "$esperado" | cut -f1,2)" ] && return 0'
al_mutante "ds175-mutante-08" $? "$AL_M" al_hash_divergente

# 09 — uma retomada idempotente incrementa a rodada de novo.
AL_M="$(al_copia m09)"
al_muta "$AL_M" '      retomada)' '      retomada)
        f6_herda; W6_N=$((P_N6 + 1)); escreve "$P_MAX" "$P_POR" "$P_ESTADO" "$P_REPROV" "$P_HIST"'
al_mutante "ds175-mutante-09" $? "$AL_M" l5_checkpoint_e_retomada

# 10 — repeticao com argumentos diferentes e aceita.
AL_M="$(al_copia m10)"
al_muta "$AL_M" '  [ "$max6" = "$P_MAX6" ] \' '  true \' \
  && al_muta "$AL_M" '  [ "$por" = "$P_AUT6_POR" ] \' '  true \'
AL_SIG10="$(cksum < "$AL_M")"
al_mutante "ds175-mutante-10" $? "$AL_M" l5_checkpoint_e_retomada

# 11 — a autorizacao tardia reatribui o dono ja existente da F5.
AL_M="$(al_copia m11)"
al_muta "$AL_M" '  escreve "$P_MAX" "$P_POR" replanejar_execucao "$P_REPROV" "$P_HIST"' '  escreve "$P_MAX" "$aut_por" replanejar_execucao "$P_REPROV" "$P_HIST"'
al_mutante "ds175-mutante-11" $? "$AL_M" l_aut_limpa

# 12 — recusa ativa e tupla tardia passam a coexistir.
AL_M="$(al_copia m12)"
al_muta "$AL_M" '  ! fm_presente recusa_replanejamento_f6 \' '  true \' \
  && al_muta "$AL_M" 'valida_recusa() {' 'valida_recusa() { return 0'
al_mutante "ds175-mutante-12" $? "$AL_M" k_aut_valida_origem_data_recusa

# 13 — a chamada deixa de adquirir a trava de concorrencia.
AL_M="$(al_copia m13)"
al_muta "$AL_M" '  adquire_trava_autorizacao_f6 "$RAIZ" "$slug"' '  true "$RAIZ" "$slug"'
al_mutante "ds175-mutante-13" $? "$AL_M" l_aut_concorrente

# 14 — lock preexistente e tratado como aquisicao bem sucedida e pode ser removido.
AL_M="$(al_copia m14)"; AL_LIB="${AL_M%/scripts/planejamento.sh}/scripts/lib/trava-autorizacao-f6.sh"
al_muta "$AL_LIB" 'mkdir "$caminho"' 'true # mutante aceita trava existente'
al_mutante "ds175-mutante-14" $? "$AL_M" l_aut_trava

# 15 — um eixo legado e promovido automaticamente ao eixo presente.
AL_M="$(al_copia m15)"
al_muta "$AL_M" '  if [ "$E_FONTE" != planejamento ] || [ "$P_ESTADO" != replanejamento_execucao_recusado ] \' '  if [ "$P_RECUSA" = orcamento_f6_legado ]; then P_F6=presente; P_MAX6=null; P_N6=0
  elif [ "$E_FONTE" != planejamento ] || [ "$P_ESTADO" != replanejamento_execucao_recusado ] \'
al_mutante "ds175-mutante-15" $? "$AL_M" l_aut_terminais

# 16 — a guarda terminal roda antes da recuperacao pendente.
AL_M="$(al_copia m16)"
al_muta "$AL_M" '  if [ "$P_AUT6" = presente ]; then' '  if false; then # mutante pula recuperacao antes do terminal'
al_mutante "ds175-mutante-16" $? "$AL_M" l5_checkpoint_e_retomada

# 17 — leitores publicam a autoridade tardia a partir do dono compartilhado.
AL_M="$(al_copia m17)"
al_muta "$AL_M" '      "$P_AUT6_POR" "$P_AUT6_EM" "$P_AUT6_ORIGEM"' '      "$P_POR" "$P_AUT6_EM" "$P_AUT6_ORIGEM"'
al_mutante "ds175-mutante-17" $? "$AL_M" l_aut_dono_e_clone

# 18 — uma versao pendente e classificada antes de rejeitar argumentos diferentes.
AL_M="$(al_copia m18)"
al_muta "$AL_M" '  [ "$max6" = "$P_MAX6" ] \' '  [ "$PERSIST" = pendente ] || [ "$max6" = "$P_MAX6" ] \' \
  && al_muta "$AL_M" '  [ "$por" = "$P_AUT6_POR" ] \' '  [ "$PERSIST" = pendente ] || [ "$por" = "$P_AUT6_POR" ] \'
[ "$(cksum < "$AL_M")" != "$AL_SIG10" ]
afirma "ds175-matriz-10-18-distinta" $? "argumentos ignorados sempre e so durante pendencia sao mutacoes diferentes"
al_mutante "ds175-mutante-18" $? "$AL_M" l5_checkpoint_e_retomada

# 19 — pending/retomada saem antes de provar congeladas e parciais.
AL_M="$(al_copia m19)"
al_muta "$AL_M" '  confere_pendente_autorizacao_f6' '  : # mutante responde antes das provas da rodada'
al_mutante "ds175-mutante-19" $? "$AL_M" l5_retomada_duravel_recusa_parcial_perdido

# 20 — o checkpoint pendente ignora fechamento/reclasse/unblock do B-NN.
AL_M="$(al_copia m20)"
al_muta "$AL_M" '  if [ "$PERSIST" = pendente ] && [ "$P_ESTADO" = replanejar_execucao ]; then' '  if false; then # mutante persiste sem validar B-NN/task'
al_mutante "ds175-mutante-20" $? "$AL_M" l5_pendente_invalido

# 21 — fechamento pendente e tratado como retomada normal.
AL_M="$(al_copia m21)"
al_muta "$AL_M" '  if [ "$P_ESTADO" = aprovado ]; then AUT6_ACAO=fechamento_pendente' '  if [ "$P_ESTADO" = aprovado ]; then AUT6_ACAO=retomada'
al_mutante "ds175-mutante-21" $? "$AL_M" l5_fechamento_pendente_e_fechado
rm -rf "$K"

echo "== AM. predecessores verificaveis =="
PRE_SUITE="$H/../../scripts/ci/test-predecessores.sh"
if [ -f "$PRE_SUITE" ]; then
  bash "$PRE_SUITE" todos
  afirma "predecessores-suite-dedicada" $? "scripts/ci/test-predecessores.sh todos"
else
  afirma "predecessores-suite-dedicada" 1 "suite ausente: $PRE_SUITE"
fi

echo
echo "  $ok ok, $falhou falhas, $pulado skip(s) interno(s), $pulado_externo por dependencia externa ausente"
[ "$pulado" -eq 0 ] || echo "  ATENCAO: skip interno e buraco de cobertura da sprintx nesta plataforma, nao dependencia externa."
[ "$falhou" -eq 0 ] && [ "$pulado" -eq 0 ]
