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
# A fonte da sprintx (RAIZ_SRC), vazia quando a bancada esta instalada: os casos que leem
# artefatos que so existem no repositorio (agentes, espelho do OpenCode) viram dependencia externa.
. "$H/testes/fonte.sh"
EXEC="$SK/references/06-execucao.md"
SKILLMD="$SK/SKILL.md"

afirma() { # afirma <nome> <condicao-ja-avaliada:0|1> <detalhe>
  if [ "$2" -eq 0 ]; then ok=$((ok+1)); printf '  ok   %-46s %s\n' "$1" "$3"
  else falhou=$((falhou+1)); printf '  FALHA %-45s %s\n' "$1" "$3"; fi
}
# Dois contadores, deliberadamente separados — misturar os dois esconde o que
# importa. `pula` e SKIP INTERNO: caso que a logica da sprintx deixou de
# cobrir nesta plataforma. A base candidata fecha com zero, e o proprio
# script cobra isso no fim. `pula_externo` e dependencia externa ausente
# (outro repositorio, outro pacote): nao e buraco de cobertura da sprintx.
# Definidos junto do `afirma`: um caso de qualquer secao pode precisar deles.
pulado=0; pulado_externo=0
pula() { pulado=$((pulado+1)); printf '  pula %-46s SKIP INTERNO: %s\n' "$1" "$2"; }
pula_externo() { pulado_externo=$((pulado_externo+1)); printf '  dep  %-46s dependencia externa ausente: %s\n' "$1" "$2"; }
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
t_base_encadeada_assinando "$ING"; afirma "a-f1-base-com-assinatura-ligada" $? "commit.gpgsign=true e gpg.program=false no ambiente${BX_FALHA:+ — FORA:$BX_FALHA}"
# A base do caller nao entra no texto do bloco (por substituicao, uma quebra de linha seguida do
# delimitador fecharia o heredoc e o resto rodaria): o agente a grava num arquivo pela ferramenta
# de escrita, e o bloco a le como dado. O caso 11 de t_base_encadeada roda isso em git real.
tem "$ING" 'git-path expx-f1-base' && tem "$ING" 'pela ferramenta de escrita de arquivo'
afirma "a-f1-base-por-arquivo" $? "o item 2 da F1 nao manda gravar a base pela ferramenta de escrita"

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
tem "$AUD" 'nos dois formatos'; afirma "c16-f5-mesmo-rigor" $? "dez itens preservados"
tem "$AUD" 'Numa sprint condensada isso é sempre'; afirma "c16b-f5-achado-caminho-real" $? "achado aponta caminho real"
NAUD=$(sed -n '/^## Passo 3 — Verificar cada item desta lista/,/^## Passo 4/p' "$AUD" | grep -cE '^[0-9]+\. \*\*')
[ "$NAUD" -eq 10 ]; afirma "c16c-f5-dez-itens" $? "$NAUD itens de auditoria (esperado 10, o 10 e o fatiamento)"

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
if [ -n "$RAIZ_SRC" ]; then
  AGENTE=$(grep -lF 'kind: plano' "$H/../agents/auditor-plano.md" "$H/../../.opencode/agent/auditor-plano.md" 2>/dev/null | wc -l)
  [ "$AGENTE" -eq 2 ]; afirma "c-agente-nos-dois-harnesses" $? "$AGENTE/2 espelhos do auditor corrigidos"
else
  pula_externo "c-agente-nos-dois-harnesses" "$SEM_FONTE"
fi

echo "== C2. fatiamento v3 (contrato expx-fatiamento, emenda de 2026-10-19) =="
# O plano e o auditor cobravam a regra v2 (400 linhas por PR, 300 por task, F4 com
# tolerancia), que o contrato v3 removeu: nao ha teto de linhas, so L1/L2/L3. Um plano
# real dividiu trabalho por "400 linhas" sem precisar (katosmv/login, PR #31). DS-189.
fat_v3() { # fat_v3 <arquivo> -> 0 se cita L1/L2/L3 com os numeros do contrato e nada da v2
  local f="$1" t
  for t in 'L1' '40 arquivos revisáveis' 'L2' '5.000 linhas' '204.800 bytes' 'L3' '100 arquivos alterados' 'todos contados'; do
    grep -qF -- "$t" "$f" || return 1
  done
  for t in '300 linhas' '400 linhas' '20 arquivos' '4.000 linhas' '150 KB' '2 KB' 'FATIA_EXCECAO'; do
    grep -qF -- "$t" "$f" && return 1
  done
  return 0
}
PLANO="$SK/references/03-plano.md"
fat_v3 "$PLANO"; afirma "c-fatiamento-v3-plano" $? "03-plano: L1/L2/L3 do contrato, nada da v2"
tem "$PLANO" 'Não há limite de linhas'; afirma "c-fatiamento-v3-sem-teto" $? "03-plano: sem teto de linhas por task, commit ou PR"
tem "$PLANO" 'contam em L3'; afirma "c-fatiamento-v3-metodo-em-l3" $? "03-plano: artefatos de metodo contam em L3"
DS189="$(grep -E '^\| DS-189 ' "$SK/DECISOES-DA-SKILL.md")"
[ "$(printf '%s' "$DS189" | grep -c .)" = 1 ] && printf '%s' "$DS189" | grep -qF 'DS-182' && printf '%s' "$DS189" | grep -qF 'DS-184'
afirma "c-fatiamento-v3-ds189" $? "uma DS-189, refinando DS-182 e DS-184"
tem "$PLANO" '`docs/eventos/` é rastro local' && ! grep -qF 'que o E1 também commita' "$PLANO"
afirma "c-fatiamento-v3-eventos-fora" $? "03-plano: docs/eventos e local, nao entra no PR; o E1 nao commita metodo"
# Quem audita conta L3 igual a quem planeja: docs/eventos/ fica fora nos tres.
EVF=0
for f in "$AUD" ${RAIZ_SRC:+"$H/../agents/auditor-plano.md" "$H/../../.opencode/agent/auditor-plano.md"}; do
  grep -qF '`docs/eventos/` é rastro local' "$f" || EVF=1
done
[ "$EVF" -eq 0 ]; afirma "c-fatiamento-v3-eventos-fora-auditoria" $? "05-auditoria e auditores: docs/eventos fora de L3"
# Sem o agente, a F5 audita pela lista do 05-auditoria: o item 10 e a severidade valem la tambem.
lim_alta() { # lim_alta <arquivo> -> 0 se as tres linhas [limite:Ln] estao como ALTA
  local n; for n in 1 2 3; do grep -qE -- "^\| \`\[item 10\]\[limite:L$n\]\` \| (\*\*)?ALTA(\*\*)? \|" "$1" || return 1; done
}
fat_v3 "$AUD" && lim_alta "$AUD"
afirma "c-fatiamento-v3-f5-manual" $? "05-auditoria: item 10 com L1/L2/L3 e severidade ALTA fixa"
if [ -n "$RAIZ_SRC" ]; then
  fat_v3 "$H/../agents/auditor-plano.md" && fat_v3 "$H/../../.opencode/agent/auditor-plano.md"
  afirma "c-fatiamento-v3-auditor" $? "item 10 dos dois auditores: L1/L2/L3, nada da v2"
  lim_alta "$H/../agents/auditor-plano.md" && lim_alta "$H/../../.opencode/agent/auditor-plano.md"
  afirma "c-fatiamento-v3-auditor-alta" $? "dois auditores: [limite:L1/L2/L3] sempre ALTA"
else
  pula_externo "c-fatiamento-v3-auditor" "$SEM_FONTE"
  pula_externo "c-fatiamento-v3-auditor-alta" "$SEM_FONTE"
fi

echo "== D. frontmatter dos agentes carrega =="
# O E2E achou o sprintx-revisor-testes invisivel ao Claude Code: `description:` sem aspas
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
# o OpenCode tira o nome do arquivo e so exige `description`. Os agentes sao os da fonte.
if [ -z "$RAIZ_SRC" ]; then
  pula_externo "d1-agentes-da-fonte" "$SEM_FONTE"
else
for f in "$H"/../agents/*.md; do
  motivo="$(valida_frontmatter "$f" 1)"; rc=$?; afirma "d1-claude-$(basename "$f" .md)" "$rc" "${motivo:-frontmatter valido}"
done
for f in "$H"/../../.opencode/agent/*.md; do
  motivo="$(valida_frontmatter "$f" 0)"; rc=$?; afirma "d1-opencode-$(basename "$f" .md)" "$rc" "${motivo:-frontmatter valido}"
done
NAG=$(ls "$H"/../agents/*.md 2>/dev/null | wc -l); NOA=$(ls "$H"/../../.opencode/agent/*.md 2>/dev/null | wc -l)
[ "$NAG" -eq 3 ] && [ "$NOA" -eq 3 ]; afirma "d1-nenhum-agente-sumiu" $? "$NAG claude, $NOA opencode (esperado 3 e 3)"
tem "$H/../agents/sprintx-revisor-testes.md" 'tools: Read, Glob, Grep'; afirma "d1-revisor-so-leitura" $? "tools de leitura preservadas"
fi

# D2. a guarda reconhece cada forma de cabecalho quebrado — inclusive o bug do E2E.
AG="$W/agentes-ruins"; mkdir -p "$AG"
printf 'name: x\ndescription: y\n---\n' > "$AG/sem-inicio.md"
printf '%s\n' '---' 'name: x' 'description: y' > "$AG/sem-fim.md"
printf '%s\n' '---' 'description: y' '---' > "$AG/sem-name.md"
printf '%s\n' '---' 'name: x' 'tools: Read' '---' > "$AG/sem-description.md"
printf '%s\n' '---' 'name: sprintx-revisor-testes' 'description: Responde sobre os testes de uma task: esse teste passaria?' '---' > "$AG/dois-pontos.md"
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
  if [ -n "$RAIZ_SRC" ]; then
    for f in "$H"/../agents/*.md "$H"/../../.opencode/agent/*.md; do
      yaml_ok "$f"; rc=$?; afirma "d3-yaml-$(basename "$(dirname "$f")")-$(basename "$f" .md)" "$rc" "PyYAML ($PYY) carrega"
    done
  else
    pula_externo "d3-yaml-agentes-da-fonte" "$SEM_FONTE"
  fi
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
| ALTA | sprint-02/tasks.md | sprintx-revisor-testes `fraco`: passaria com item no grupo errado | Caso por grupo |
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
# Linha fora das quatro colunas nao some da contagem: um SIM legado com ela nao migra (katosmv/login#34).
D="$G/s4"; nova_feature "$D" velha; legado "$D" '| severidade | arquivo | problema | correção sugerida |
|---|---|---|---|
| ALTA | sprint-01/tasks.md | [item 10][limite:L1] T-01.01 tem 41 arquivos | dividir

VEREDITO: SIM — o plano está pronto para execução autônoma.'
pl "$D" criar velha 3 buildx >/dev/null; rc=$?
[ "$rc" -eq 4 ] && [ ! -f "$(fdir "$D" velha)/00-PLANEJAMENTO.md" ]; afirma "gs4-legado-com-linha-malformada-nao-migra" $? "rc=$rc, nada gravado"

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
  onde="$(grep -rlF -- "$CMD_PL ${inst%%:*}" "$SK" "$H/../commands" ${RAIZ_SRC:+"$RAIZ_SRC/.opencode"} 2>/dev/null)"
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
# Item 10: violacao de L1/L2/L3 carrega [limite:Ln] e e ALTA, sem julgamento (DS-189).
sev_caso g-limite-l1-como-media-recusado 4 '| MÉDIA | s/tasks.md | [item 10][limite:L1] T-01.01 declara 41 arquivos revisáveis | y |' 'SIM — x'
sev_caso g-limite-l2-como-baixa-recusado 4 '| BAIXA | s/tasks.md | [item 10][limite:L2] T-01.01 leva src/a.ts a 5.200 linhas | y |' 'SIM — x'
sev_caso g-limite-l3-como-media-recusado 4 '| MÉDIA | s/tasks.md | [item 10][limite:L3] o trabalho altera 120 arquivos | y |' 'SIM — x'
sev_caso g-limite-l3-alta-aceito 0 '| ALTA | s/tasks.md | [item 10][limite:L3] o trabalho altera 120 arquivos | y |' 'NÃO — x'
sev_caso g-limite-sem-marcador-recusado 4 '| MÉDIA | s/tasks.md | [item 10] T-01.01 passa de L1 com 41 arquivos | y |' 'SIM — x'
sev_caso g-limite-fora-do-item10-recusado 4 '| ALTA | s/tasks.md | [item 9][limite:L2] base/x.md | y |' 'NÃO — x'
sev_caso g-limite-invalido-recusado 4 '| ALTA | s/tasks.md | [item 10][limite:L4] T-01.01 | y |' 'NÃO — x'
sev_caso g-limite-marcador-extra-invalido-recusado 4 '| ALTA | s/tasks.md | [item 10][limite:L1] T-01.01 declara 41 arquivos [limite:L4] | y |' 'NÃO — x'
sev_caso g-limite-marcador-extra-valido-recusado 4 '| ALTA | s/tasks.md | [item 10][limite:L1] T-01.01 declara 41 arquivos [limite:L2] | y |' 'NÃO — x'
sev_caso g-limite-pipe-escapado-recusado 4 '| ALTA | s/tasks.md | [item 10][limite:L1] T-01.01 41 arquivos \| [limite:L4] | y |' 'NÃO — x'
sev_caso g-pipe-escapado-na-celula-aceito 0 '| BAIXA | s/tasks.md | [item 3] T-01.01 a \| b | y |' 'SIM — x'
sev_caso g-limite-coluna-extra-recusado 4 '| ALTA | s/tasks.md | [item 10][limite:L1] T-01.01 41 arquivos | [limite:L4] | y |' 'NÃO — x'
sev_caso g-tabela-coluna-a-menos-recusado 4 '| ALTA | s/tasks.md | [item 1] T-01.01 sem teste |' 'NÃO — x'
sev_caso g-item10-granularidade-media-aceito 0 '| MÉDIA | s/tasks.md | [item 10] T-01.01 os testes não cabem em uma frase | y |' 'SIM — x'
# Limite descrito so pelo numero, sem L1-L3, tambem e achado de limite: sem [limite:Ln], recusado (katosmv/login#34).
sev_caso g-item10-limite-so-numerico-recusado 4 '| MÉDIA | s/tasks.md | [item 10] T-01.01 tem 101 arquivos alterados; máximo: 100 | y |' 'SIM — x'
sev_caso g-item10-limite-em-linhas-recusado 4 '| MÉDIA | s/tasks.md | [item 10] src/a.ts fica com 5.200 linhas | y |' 'SIM — x'
sev_caso g-item10-limite-em-bytes-recusado 4 '| MÉDIA | s/tasks.md | [item 10] src/a.ts passa de 204.800 bytes | y |' 'SIM — x'
# Duas barras antes do pipe: barra literal seguida do delimitador, nao pipe escapado (katosmv/login#34).
sev_caso g-duas-barras-antes-do-delimitador-aceito 0 '| BAIXA | s/tasks.md | [item 3] termina com duas barras \\| y |' 'SIM — x'
sev_caso g-tres-barras-pipe-escapado-aceito 0 '| BAIXA | s/tasks.md | [item 3] a \\\| b | y |' 'SIM — x'
sev_caso gv5-teste-com-clausula-media-aceito 0 '| MÉDIA | s/tasks.md | [item 2][fraco:teste] T-01.01 — cláusula: D-13 — passaria com: x | y |' 'SIM — x'
aud_linha '| MÉDIA | s/tasks.md | [item 2][fraco:teste] T-01.01 — cláusula: D-13 — passaria com: x | y |' 'MAIS OU MENOS'
pl "$D" avanca menu f5 >/dev/null; rc=$?
[ "$rc" -eq 4 ] && [ "$(fmv "$F/00-PLANEJAMENTO.md" estado)" = aguardando_f5 ]; afirma "g-auditoria-invalida-nao-registra-rodada" $? "rc=$rc, estado aguardando_f5"
AUDF="$SK/references/05-auditoria.md"
[ -z "$(grep -rlF 'a severidade é sua' "$SK" ${RAIZ_SRC:+"$H/../agents" "$H/../../.opencode/agent"} | grep -vF 'DECISOES-DA-SKILL.md')" ]; afirma "g-frase-severidade-e-sua-removida" $? "nenhuma sessao escolhe"
tem "$AUDF" '| `fraco:teste` | **MÉDIA** |' && tem "$AUDF" '| `fraco:ausente` | **ALTA** |' && tem "$AUDF" '| `fraco:criterio` | **ALTA** |'
afirma "g-f5-tabela-deterministica" $? "05-auditoria.md"
# Redacao (katosmv/login#34): a soma de linhas nao tem teto, mas o L2 por arquivo vale; "sao ALTAS".
for f in "$AUDF" ${RAIZ_SRC:+"$H/../agents/auditor-plano.md"}; do
  i_nome="g-redacao-l2-e-altas-$(basename "$f" .md)"
  tem "$f" 'soma de linhas' && tem "$f" 'O L2, por arquivo, continua valendo' && tem "$f" 'acima são ALTAS porque' \
    && ! grep -qF 'não aponte tamanho em linhas' "$f"; i_rc=$?
  afirma "$i_nome" "$i_rc" "soma sem teto, L2 por arquivo, concordancia"
done
[ -n "$RAIZ_SRC" ] || pula_externo "g-agente-tabela-da-fonte" "$SEM_FONTE"
for ag in ${RAIZ_SRC:+"$H/../agents/auditor-plano.md" "$H/../agents/sprintx-revisor-testes.md"}; do
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
tem "$EXEC" '**A task não conclui se alguma delas continuar passando.**'; afirma "gy2-revisor-f6-confere-registradas" $? "sprintx-revisor-testes na F6"
if [ -n "$RAIZ_SRC" ]; then
  tem "$H/../agents/sprintx-revisor-testes.md" 'confira, lendo o teste de verdade, que **cada uma delas é discriminada**'; afirma "gy3-agente-f6-confere" $? "sprintx-revisor-testes.md"
else
  pula_externo "gy3-agente-f6-confere" "$SEM_FONTE"
fi

# Z. Espelho Claude/OpenCode: mesmo corpo em todos os agentes.
corpo_agente() { tr -d '\r' < "$1" | awk 'f && (n || $0 != "") { n = 1; print } /^---$/ { c++; if (c == 2) f = 1 }'; }
[ -n "$RAIZ_SRC" ] || pula_externo "gz-espelho-e-exemplos-dos-agentes" "$SEM_FONTE"
for ag in ${RAIZ_SRC:+auditor-plano sprintx-revisor-testes sprintx-investigador}; do
  [ "$(corpo_agente "$H/../agents/$ag.md")" = "$(corpo_agente "$H/../../.opencode/agent/$ag.md")" ]
  afirma "gz-espelho-$ag" $? "corpo identico nos dois harnesses"
done
if [ -n "$RAIZ_SRC" ]; then
  EXREV="$(tr -d '\r' < "$H/../agents/sprintx-revisor-testes.md" | sed -n '/^T-01.02 | solido$/,/^```$/p' | grep '^T-')"
  printf '%s\n' "$EXREV" | bash "$PL" revisor >/dev/null 2>&1; afirma "gz2-exemplos-do-agente-validos" $? "$(printf '%s\n' "$EXREV" | wc -l | tr -d ' ') linha(s) aceitas pelo script"
fi

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
# Sem a fonte, a arvore "real" e o layout instalado materializado de $H e $SK.
[ -n "$RAIZ_SRC" ] || U_REAL="$(u_arvore instalada)"
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

. "$H/testes/bancada-historico-calibracao.sh"
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

# 2. O harness inteiro esta livre da forma — nao so as seis familias conhecidas. "Inteiro" e a
#    bancada.sh e toda parte bancada-*.sh que ela carrega por `.`: as secoes movidas para as partes
#    continuam sendo harness. Cada ocorrencia sai como "<arquivo>:<linha>:<texto>". Guarda que
#    falha (leitura, awk) reprova: sob pipefail o status do pipe e o do aa_vulneraveis.
AA_VUL=""; aa_n=0
for aa_arq in "$H"/testes/bancada*.sh; do
  [ -r "$aa_arq" ] || { AA_VUL="$AA_VUL ${aa_arq##*/}:ilegivel"; continue; }
  aa_n=$((aa_n + 1))
  aa_o="$(aa_vulneraveis "$aa_arq" | awk -v f="${aa_arq##*/}" '{ printf " %s:%s", f, $0 }')" \
    || aa_o="$aa_o ${aa_arq##*/}:guarda-falhou"
  AA_VUL="$AA_VUL$aa_o"
done
AA_VUL="${AA_VUL# }"
[ -z "$AA_VUL" ]; aa_rc=$?
afirma "aa2-nenhuma-chamada-vulneravel-no-harness" "$aa_rc" "${AA_VUL:-nenhuma leitura de \$? depois de substituicao em $aa_n arquivos bancada*.sh}"

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

. "$H/testes/bancada-desvio-estimativa.sh"
. "$H/testes/bancada-rastro-suite.sh"
. "$H/testes/bancada-autorizacao-f6.sh"
. "$H/testes/bancada-modelo-esforco.sh"
echo "== AM. predecessores verificaveis =="
PRE_SUITE="$H/../../scripts/ci/test-predecessores.sh"
if [ -f "$PRE_SUITE" ]; then
  bash "$PRE_SUITE" todos
  afirma "predecessores-suite-dedicada" $? "scripts/ci/test-predecessores.sh todos"
elif [ -z "$RAIZ_SRC" ]; then
  # a suite dedicada mora em scripts/ci/ do repositorio, fora do que a skill instala
  pula_externo "predecessores-suite-dedicada" "$SEM_FONTE"
else
  afirma "predecessores-suite-dedicada" 1 "suite ausente: $PRE_SUITE"
fi

echo
echo "  $ok ok, $falhou falhas, $pulado skip(s) interno(s), $pulado_externo por dependencia externa ausente"
[ "$pulado" -eq 0 ] || echo "  ATENCAO: skip interno e buraco de cobertura da sprintx nesta plataforma, nao dependencia externa."
[ "$falhou" -eq 0 ] && [ "$pulado" -eq 0 ]
