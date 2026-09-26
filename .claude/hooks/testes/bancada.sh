#!/usr/bin/env bash
# bancada.sh — script de bancada minimo para os hooks de sessoes paralelas.
#
# Nao e uma suite completa (a sprintx nao tinha nenhuma antes desta feature —
# ver base/testes-e-mimocode.md). Monta uma fixture git real em /tmp, com um
# worktree derivado, e roda cada hook novo contra ela, conferindo exit code e,
# quando aplicavel, o conteudo de stderr (bloqueio) ou stdout (aviso).
set -uo pipefail

H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
W="$(mktemp -d)"
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
trap 'git -C "$W" worktree remove --force "$WT" >/dev/null 2>&1; rm -rf "$W" "$WT"' EXIT

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
REV=$(grep -rlF "mergex-""revisar" "$SK" "$H/.." 2>/dev/null | grep -v "/testes/bancada.sh$" | wc -l)
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
  # shellcheck disable=SC2086
  pl "$D" criar menu $ruim >/dev/null; rc=$?
  [ "$rc" -eq 4 ] && [ ! -f "$(fdir "$D" menu)/00-PLANEJAMENTO.md" ]
  afirma "ga7-orcamento-invalido-$(printf '%s' "$ruim" | tr ' .' '__')" $? "rc=$rc, nada gravado"
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
  pl "$D" avanca menu f2 >/dev/null; [ $? -eq 2 ]; afirma "gl3-recusa-$(printf '%s' "$prod" | tr '/.' '__')" $? "staged fora do prefixo"
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
  onde="$(grep -rlF -- "$CMD_PL ${inst%%:*}" "$SK" "$H/../commands" "$H/../../.opencode" 2>/dev/null)"
  [ "$(printf '%s\n' "$onde" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 1 ] && [ "$(basename "$onde")" = "${inst##*:}.md" ]
  afirma "gh-instrucao-unica-$(printf '%s' "${inst%%:*}" | tr -c 'a-z0-9' '_' | sed 's/_*$//')" $? "${onde:-nenhum arquivo}"
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
  printf '%s\n' "$ruim" | bash "$PL" revisor >/dev/null 2>&1; [ $? -eq 4 ]
  afirma "gw3-revisor-recusa-$(printf '%s' "$ruim" | tr -c 'a-z0-9' '_' | cut -c1-28)" $? "linha fora da forma"
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
  grep -qE '`?(\[item 2\]\[fraco:)?teste\]?`? \| MÉDIA' "$ag" && grep -qE '`?(\[item 2\]\[fraco:)?ausente\]?`? \| ALTA' "$ag" \
    && grep -qE '`?(\[item 2\]\[fraco:)?criterio\]?`? \| ALTA' "$ag"
  afirma "g-agente-tabela-$(basename "$ag" .md)" $? "mesma severidade no agente"
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

echo "== J. o bloqueio ganha classe (P0.2-A5) =="
# Testa o MECANISMO: scripts/bloqueios.sh e o unico escritor de B-NN novo, e a classe
# sai da chave `classe`, nunca da descricao. Cada caso e uma funcao <script> <dir>, para
# que os mutantes (jm-*) rodem exatamente a mesma bateria. Nenhum caso le a descricao
# para obter a classe: a classe vem sempre de `bloqueios.sh listar`.
BL="$SK/scripts/bloqueios.sh"
TPLB="$SK/assets/TEMPLATE-BLOQUEIOS.md"
SCH="$SK/references/00-schema.md"
existe "j0-script-existe" "$BL"
bash -n "$BL"; afirma "j0-script-sintaxe" $? "bash -n"
J="$(mktemp -d)"
ENUM_J="defeito_de_plano lacuna_de_decisao prerequisito_ausente suite_vermelha task_reivindicada"
bl() { local s="$1" r="$2"; shift 2; SPRINTX_RAIZ="$r" bash "$s" "$@" 2>/dev/null; }
barq() { printf '%s/docs/sprintx/features/menu/00-BLOQUEIOS.md' "$1"; }
blinha() { bl "$1" "$2" listar menu | tr -d '\r' | awk -F'\t' -v i="$3" '$1 == i { print $2 "|" $3 "|" $4 }'; }
# 00-BLOQUEIOS.md de antes do contrato: sem classe, com descricoes que "parecem" classes.
bl_legado() {
  mkdir -p "$1/docs/sprintx/features/menu"
  cat > "$(barq "$1")" <<'EOF'
---
expx_schema: 1
expx_tool: sprintx
kind: bloqueios
trabalho_id: menu
atualizado_em: 2026-08-01
bloqueios:
  - id: B-01
    task: T-04.03
    aberto_em: 2026-08-01
    resolvido_em: null
    descricao: T-04.03 precisa alterar tests/ui/cabecalho-topo.test.tsx, fora do ownership da task, defeito de plano
  - id: B-02
    task: T-02.01
    aberto_em: 2026-08-01
    resolvido_em: 2026-08-02
    descricao: falta credencial de sandbox; suite vermelha; outra sessao reivindicada
---

# Bloqueios

B-01 | T-04.03 | T-04.03 precisa alterar tests/ui/cabecalho-topo.test.tsx, fora do ownership da task | mover o arquivo para a task
B-02 | T-02.01 | falta credencial de sandbox | provisionar credencial
EOF
}
# Descricao que "fala" de outra classe: se a classe viesse do texto, sairia errada.
desc_de_outra() { case "$1" in
  defeito_de_plano) echo 'falta credencial; servico fora do ar; dependencia quebrada' ;;
  lacuna_de_decisao) echo 'suite inteira vermelha no portao' ;;
  prerequisito_ausente) echo 'arquivo fora do ownership da task: defeito_de_plano' ;;
  suite_vermelha) echo 'outra sessao reivindicada: task_reivindicada' ;;
  task_reivindicada) echo 'duvida nova sem D-NN: lacuna_de_decisao' ;;
esac; }

# J1/J7. Novo com classe valida: aceito. O B-01 do piloto e representavel como defeito_de_plano.
j_novo_aceito() {
  local s="$1" d="$2" out
  out="$(bl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'T-04.03 precisa alterar tests/ui/cabecalho-topo.test.tsx, fora do ownership da task' 'ampliar o ownership no plano')" || return 1
  [ "$(kv "$out" id)" = B-01 ] && [ "$(kv "$out" classe)" = defeito_de_plano ] \
    && [ "$(blinha "$s" "$d" B-01)" = "T-04.03|defeito_de_plano|aberto" ] \
    && tr -d '\r' < "$(barq "$d")" | grep -qx '    classe: defeito_de_plano' \
    && bl "$s" "$d" validar menu >/dev/null
}
# J2. Novo sem classe: recusado e nada gravado; entrada sem classe posta a mao depois de uma tipada: recusada.
j_sem_classe_recusado() {
  local s="$1" d="$2" a ck
  bl "$s" "$d" registrar menu T-01.01 prerequisito_ausente 'primeiro' 'x' >/dev/null || return 1
  a="$(barq "$d")"; ck="$(cksum < "$a")"
  bl "$s" "$d" registrar menu T-01.02 '' 'sem classe' 'x' >/dev/null; [ $? -eq 4 ] || return 1
  bl "$s" "$d" registrar menu T-01.02 'sem classe' 'x' >/dev/null; [ $? -ne 0 ] || return 1
  [ "$(cksum < "$a")" = "$ck" ] || return 1
  awk '{ print } $0 == "    descricao: \"primeiro\"" { print "  - id: B-02\n    task: T-01.02\n    aberto_em: 2026-09-01\n    resolvido_em: null\n    descricao: novo sem classe" }' "$a" > "$a.m" && mv "$a.m" "$a"
  grep -q '^  - id: B-02' "$a" || return 1
  bl "$s" "$d" validar menu >/dev/null; [ $? -eq 4 ] || return 1
  bl "$s" "$d" listar menu >/dev/null; [ $? -eq 4 ]
}
# J3. Classe fora do enum: recusada na escrita e na leitura — inclusive o vocabulario do
# BuildX, `null` e o `legado` que a leitura devolve.
j_fora_do_enum() {
  local s="$1" d="$2" a ck c i=0
  bl "$s" "$d" registrar menu T-01.01 suite_vermelha 'base' 'x' >/dev/null || return 1
  a="$(barq "$d")"; ck="$(cksum < "$a")"
  for c in legado null trabalho_novo decisao_humana recurso_externo falha_tecnica Defeito_de_plano 'defeito de plano'; do
    bl "$s" "$d" registrar menu T-01.02 "$c" 'ruim' 'x' >/dev/null; [ $? -eq 4 ] || return 1
  done
  [ "$(cksum < "$a")" = "$ck" ] || return 1
  for c in trabalho_novo null legado '"suite_vermelha"' ''; do
    i=$((i+1)); mkdir -p "$d/v$i/docs/sprintx/features/menu"
    sed "s/^    classe: suite_vermelha\$/    classe: $c/" "$a" > "$(barq "$d/v$i")"
    cmp -s "$a" "$(barq "$d/v$i")" && return 1
    bl "$s" "$d/v$i" validar menu >/dev/null; [ $? -eq 4 ] || return 1
  done
}
# J4. Legado sem classe: legivel, sai `legado`, nunca inferido — nem na leitura, nem quando
# um B-NN novo regrava o arquivo (as entradas antigas ficam byte a byte).
j_legado() {
  local s="$1" d="$2" a antes depois
  bl_legado "$d"; a="$(barq "$d")"
  bl "$s" "$d" validar menu >/dev/null || return 1
  [ "$(blinha "$s" "$d" B-01)" = "T-04.03|legado|aberto" ] && [ "$(blinha "$s" "$d" B-02)" = "T-02.01|legado|resolvido" ] || return 1
  antes="$(sed -n '/^  - id: B-01$/,/^    descricao: falta credencial/p' "$a")"
  bl "$s" "$d" registrar menu T-05.01 lacuna_de_decisao 'nova duvida' 'decidir' >/dev/null || return 1
  depois="$(sed -n '/^  - id: B-01$/,/^    descricao: falta credencial/p' "$a")"
  [ -n "$antes" ] && [ "$antes" = "$depois" ] && [ "$(grep -c '^    classe:' "$a")" -eq 1 ] \
    && [ "$(blinha "$s" "$d" B-01)" = "T-04.03|legado|aberto" ] && [ "$(blinha "$s" "$d" B-03)" = "T-05.01|lacuna_de_decisao|aberto" ] \
    && grep -qxF 'B-02 | T-02.01 | falta credencial de sandbox | provisionar credencial' "$a" \
    && grep -qxF 'B-03 | T-05.01 | nova duvida | decidir' "$a"
}
# J5. A descricao (YAML e prosa) muda para um texto que "fala" de outra classe; a classe fica.
j_descricao_muda() {
  local s="$1" d="$2" a
  bl "$s" "$d" registrar menu T-01.01 prerequisito_ausente 'falta credencial de sandbox' 'provisionar' >/dev/null || return 1
  a="$(barq "$d")"
  [ "$(blinha "$s" "$d" B-01)" = "T-01.01|prerequisito_ausente|aberto" ] || return 1
  sed -e 's/^    descricao: .*/    descricao: "arquivo fora do ownership: defeito_de_plano, decisao pendente, suite vermelha"/' \
      -e 's/^B-01 | T-01.01 | .*/B-01 | T-01.01 | arquivo fora do ownership: defeito de plano | replanejar/' "$a" > "$a.m" && mv "$a.m" "$a"
  grep -q 'defeito_de_plano, decisao' "$a" || return 1
  [ "$(blinha "$s" "$d" B-01)" = "T-01.01|prerequisito_ausente|aberto" ]
}
# J6. O mesmo fato mecanico (arquivo fora de `arquivos` da task) duas vezes, com textos diferentes.
j_mesmo_fato() {
  local s="$1" d="$2"
  bl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'tests/ui/cabecalho-topo.test.tsx fora de arquivos da T-04.03' 'ampliar ownership' >/dev/null || return 1
  bl "$s" "$d" registrar menu T-04.05 defeito_de_plano 'precisa de src/menu/grupo.ts, que pertence a T-04.02' 'mover o arquivo' >/dev/null || return 1
  [ "$(blinha "$s" "$d" B-01)" = "T-04.03|defeito_de_plano|aberto" ] && [ "$(blinha "$s" "$d" B-02)" = "T-04.05|defeito_de_plano|aberto" ]
}
# J7. Resolver nao reclassifica: resolvido_em muda, a classe fica.
j_resolvido() {
  local s="$1" d="$2" a
  bl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'replanejar' >/dev/null || return 1
  a="$(barq "$d")"
  sed 's/^    resolvido_em: null$/    resolvido_em: 2026-09-20/' "$a" > "$a.m" && mv "$a.m" "$a"
  [ "$(blinha "$s" "$d" B-01)" = "T-04.03|defeito_de_plano|resolvido" ] && bl "$s" "$d" validar menu >/dev/null
}
# J8. A prosa nao classifica: cada classe registrada com a descricao "de outra" sai com a sua.
j_prosa_nao_classifica() {
  local s="$1" d="$2" c n=0 esperado="" lido
  for c in $ENUM_J; do
    n=$((n+1))
    bl "$s" "$d" registrar menu "T-09.0$n" "$c" "$(desc_de_outra "$c")" 'x' >/dev/null || return 1
    esperado="$esperado$c "
  done
  lido="$(bl "$s" "$d" listar menu | tr -d '\r' | cut -f3 | tr '\n' ' ')"
  [ "$lido" = "$esperado" ]
}
CASOS_J="j_novo_aceito j_sem_classe_recusado j_fora_do_enum j_legado j_descricao_muda j_mesmo_fato j_resolvido j_prosa_nao_classifica"
roda_caso() { local d; d="$(mktemp -d "$J/c.XXXXXX")"; "$1" "$2" "$d"; }
for par in j_novo_aceito:j1-novo-com-classe-aceito j_sem_classe_recusado:j2-novo-sem-classe-recusado \
  j_fora_do_enum:j3-classe-fora-do-enum-recusada j_legado:j4-legado-legivel-sem-inferencia \
  j_descricao_muda:j5-descricao-muda-classe-fica j_mesmo_fato:j6-mesmo-fato-mesma-classe \
  j_resolvido:j7-defeito-de-plano-resolvido-mantem j_prosa_nao_classifica:j8-prosa-nao-classifica; do
  roda_caso "${par%%:*}" "$BL"; afirma "${par#*:}" $? "${par%%:*}"
done
D="$J/tpl"; bl "$BL" "$D" registrar menu T-01.01 lacuna_de_decisao 'x' 'y' >/dev/null
tr -d '\r' < "$(barq "$D")" | awk 'NR==1{next} $0=="---"{exit} {print}' | grep -q '{{'; [ $? -ne 0 ]
afirma "j9-arquivo-novo-sem-placeholder-no-yaml" $? "criado do template, frontmatter preenchido"

# Enum unico: script, schema (enum e tabela), tabela da F6 e template, na mesma ordem.
E_SCRIPT="$(bash "$BL" classes | tr -d '\r' | tr '\n' ' ')"
E_ENUM="$(tr -d '\r' < "$SCH" | grep -F '| `classe` (bloqueio) |' | grep -o '`[a-z_]*`' | tr -d '`' | sed 1d | tr '\n' ' ')"
E_TABSCH="$(tr -d '\r' < "$SCH" | awk '/^\*\*O bloqueio é dado tipado/{f=1} /^Regras duras de `classe`/{f=0} f' | grep -E '^\| `[a-z_]+` \|' | sed -E 's/^\| `([a-z_]+)`.*/\1/' | tr '\n' ' ')"
E_F6="$(tr -d '\r' < "$EXEC" | awk '/^## Regra de bloqueio/{f=1} /^## Portões/{f=0} f' | grep -E '\| `[a-z_]+` \|$' | grep -vF '| `classe` |' | sed -E 's/.*\| `([a-z_]+)` \|$/\1/' | tr '\n' ' ')"
E_TPL="$(tr -d '\r' < "$TPLB" | sed -n 's/^    classe: {{\(.*\)}}$/\1/p' | tr -d ' ' | tr '|' ' ') "
for par in "script:$E_SCRIPT" "schema-enum:$E_ENUM" "schema-tabela:$E_TABSCH" "f6-tabela:$E_F6" "template:$E_TPL"; do
  [ "${par#*:}" = "$ENUM_J " ]; afirma "j10-enum-${par%%:*}" $? "${par#*:}"
done
printf '%s' "$E_SCRIPT" | grep -Eq 'trabalho_novo|decisao_humana|recurso_externo|falha_tecnica|legado'; [ $? -ne 0 ]
afirma "j10-vocabulario-e-da-sprintx" $? "nenhuma classe do BuildX nem legado"

# A F6 so registra pelo script, e cada caminho de criacao nomeia a sua classe.
tem "$EXEC" 'scripts/bloqueios.sh registrar <slug> <T-NN.MM|null> <classe>' \
  && ! tem "$EXEC" 'Registre em `docs/sprintx/features/<slug>/00-BLOQUEIOS.md`: `B-NN'
afirma "j11-f6-registra-pelo-script" $? "sem gravacao a mao do B-NN"
tem "$EXEC" 'nunca pelo texto que você vai escrever na descrição'; afirma "j11-f6-classe-pelo-caminho" $? "caminho, nao texto"
tem "$EXEC" 'registre um bloqueio `task_reivindicada`' && tem "$EXEC" 'registre bloqueio `suite_vermelha`' \
  && tem "$EXEC" 'trate como bloqueio `defeito_de_plano` se não houver task que o resolva' \
  && tr -d '\r' < "$EXEC" | grep -A1 -F '**Se não conseguir tornar o teste discriminante, registre bloqueio da task** (classe' | grep -qF '`defeito_de_plano`, Regra de bloqueio'
afirma "j11-f6-cada-caminho-tem-classe" $? "reivindicada, suite, criterio, fraco:teste"
tem "$SCH" '**A prosa explica, não classifica:**' && tem "$SCH" '**Ela nunca recebe classe inferida**' \
  && tem "$SCH" '5. **Exceção: `classe` de bloqueio nunca é inferida da prosa.**' && tem "$SCH" '**Imutável.** Gravada, a classe não muda'
afirma "j12-schema-contrato-da-classe" $? "prosa nao classifica, legado, migracao, imutavel"
DSF="$SK/DECISOES-DA-SKILL.md"
[ "$(grep -c '^| DS-139 |' "$DSF")" -eq 1 ] && tem "$DSF" '**A prosa explica, não classifica:**' \
  && tem "$DSF" 'nenhum consumidor deriva classe de `descricao`' && tem "$DSF" '**nunca ganha classe inferida retroativamente**'
afirma "j12-ds139-registrada" $? "DS-139"

# Mutantes do script, em copia temporaria da skill (scripts/ + assets/, porque o script acha
# o template pela propria pasta): a bateria acima tem de matar cada um. O controle e uma
# copia SEM mutacao na mesma estrutura: se ele morrer, a bancada e que esta quebrada.
MJ="$J/mut"
muta_lit() { # muta_lit <origem> <destino> <trecho> <troca> — troca literal; falha se o trecho nao existe
  ML_A="$3" ML_B="$4" awk '{ a = ENVIRON["ML_A"]; i = index($0, a); if (i) { $0 = substr($0, 1, i - 1) ENVIRON["ML_B"] substr($0, i + length(a)); n++ } print } END { exit n ? 0 : 1 }' "$1" > "$2"
}
copia_skill() { mkdir -p "$MJ/$1/scripts" "$MJ/$1/assets"; cp "$TPLB" "$MJ/$1/assets/"; cp "$SK/scripts/caminho-git.sh" "$MJ/$1/scripts/"; printf '%s/%s/scripts/bloqueios.sh' "$MJ" "$1"; }
mata() { local c; for c in $CASOS_J; do roda_caso "$c" "$1" || { printf '%s' "$c"; return; }; done; }
mutante() { # mutante <nome> <rc da geracao> <script> <caso que TEM de matar>... — nao vale morrer de carona
  local nome="$1" rc="$2" s="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do roda_caso "$c" "$s" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]; afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
CTL="$(copia_skill controle)"; cp "$BL" "$CTL"
K="$(mata "$CTL")"; [ -z "$K" ]; afirma "jm-controle-copia-intacta-sobrevive" $? "${K:-nenhum caso reprova a copia sem mutacao}"
DERIVA='c = ($0 ~ /arquivo|ownership|plano/) ? "defeito_de_plano" : ($0 ~ /credencial|servico|dependencia/) ? "prerequisito_ausente" : ($0 ~ /suite/) ? "suite_vermelha" : ($0 ~ /sessao|reivindicad/) ? "task_reivindicada" : "lacuna_de_decisao"; nc = 1'
LINHA_CHAVES='    /^    [a-z_]+:/      { next }'
M="$(copia_skill a)"; muta_lit "$BL" "$M.1" '    classe: %s\n' '' && muta_lit "$M.1" "$M" '"$task" "$classe" "$(hoje)"' '"$task" "$(hoje)"'
mutante "jm-mutante-a-escrita-remove-classe" $? "$M" j_novo_aceito j_mesmo_fato
M="$(copia_skill b)"; muta_lit "$BL" "$M" "$LINHA_CHAVES" "    /^    descricao:/ { $DERIVA; next }
$LINHA_CHAVES"
mutante "jm-mutante-b-classe-da-descricao" $? "$M" j_descricao_muda j_prosa_nao_classifica
M="$(copia_skill c)"; muta_lit "$BL" "$M" "$LINHA_CHAVES" "    /^    descricao:/ { if (!nc) { $DERIVA }; next }
$LINHA_CHAVES"
mutante "jm-mutante-c-legado-inferido-da-descricao" $? "$M" j_legado
M="$(copia_skill d)"; muta_lit "$BL" "$M" '[ -n "$tipada" ] && falha' 'false && falha'
mutante "jm-mutante-d-leitura-aceita-novo-sem-classe" $? "$M" j_sem_classe_recusado
M="$(copia_skill e)"; muta_lit "$BL" "$M" 'classe_valida "$classe" || falha "$E_CONTRATO" "$id com classe' 'true || falha "$E_CONTRATO" "$id com classe'
mutante "jm-mutante-e-leitura-aceita-fora-do-enum" $? "$M" j_fora_do_enum
rm -rf "$J"

echo "== K. replanejamento da execucao e preservacao das tasks concluidas (P0.2-B) =="
# Testa o MECANISMO contra repositorios git reais. A essencia do piloto: 14 de 18 tasks
# concluidas, T-04.03 bloqueada com defeito_de_plano (precisa alterar um arquivo que a
# T-03.01 concluida criou), orcamento da F5 ja parcialmente usado. Cada caso e uma funcao
# <planejamento.sh> <dir>, para que os mutantes (km-*) rodem exatamente a mesma bateria;
# as fixtures de base sao montadas uma vez, com o script real, e copiadas para cada caso.
# A classe vem sempre da chave, via bloqueios.sh: nenhum caso le a descricao.
K="$(mktemp -d)"
kpl() { local s="$1" d="$2"; shift 2; (cd "$d" && bash "$s" "$@") 2>&1; }
kbl() { local s="$1" d="$2"; shift 2; SPRINTX_RAIZ="$d" bash "$(dirname "$s")/bloqueios.sh" "$@" 2>&1; }
kf() { printf '%s/docs/sprintx/features/menu' "$1"; }
kst() { # kst <dir> <T-NN.MM> — status da task no frontmatter do tasks.md que a declara
  local f
  for f in "$(kf "$1")"/sprint-*/tasks.md; do
    tr -d '\r' < "$f" | awk -v t="$2" 'NR==1{next} $0=="---"{exit} /^tasks:/{b=1;next} b&&/^[^ ]/{b=0} b&&/^  - id:/{id=$3} b&&id==t&&/^    status:/{print $2; exit}'
  done
}
kbloq() { kbl "$PL" "$1" listar menu | tr -d '\r' | awk -F'\t' -v i="$2" '$1 == i { print $3 "|" $4 }'; }
# O congelado visto de fora do script: sprint-01..03 inteiros e, na sprint-04, o item do
# frontmatter e o bloco da prosa de T-04.01 e T-04.02.
kcong() {
  local f; f="$(kf "$1")"
  cat "$f/sprint-01/tasks.md" "$f/sprint-02/tasks.md" "$f/sprint-03/tasks.md"
  for t in T-04.01 T-04.02; do
    tr -d '\r' < "$f/sprint-04/tasks.md" | sed -n "/^  - id: $t\$/,/^    suite:/p; /^id: $t\$/,/^\`\`\`\$/p"
  done
}
k_item() { # k_item <id> <status> <cria> <altera> <depende>
  local conc=null suite=nao_executada
  if [ "$2" = concluida ]; then conc=2026-09-10; suite=parcial; fi
  printf '  - id: %s\n    titulo: Task %s\n    fase: F-%s.1\n    status: %s\n    objetivo: Entregar a parte %s\n    arquivos:\n      cria: [%s]\n      altera: [%s]\n    teste_integracao: Integra a parte %s contra o modulo real\n    teste_funcional: Dada a entrada de %s, devolve a saida declarada\n    criterio_aceite: O teste da parte %s passa\n    depende_de: [%s]\n    paralelizavel: false\n    concluida_em: %s\n    suite: %s\n' \
    "$1" "$1" "$(printf '%s' "$1" | cut -c3-4)" "$2" "$1" "$3" "$4" "$1" "$1" "$1" "$5" "$conc" "$suite"
}
k_prosa() {
  printf -- '---\n\n```yaml\nid: %s\ntitulo: Task %s\narquivos:\n  cria: [%s]\n  altera: [%s]\ndepende_de: [%s]\nstatus: %s\n```\n\n' "$1" "$1" "$3" "$4" "$5" "$2"
  if [ "$2" = concluida ]; then printf '2026-09-10 · suíte: 3 passed, 0 failed · real: 1 h\n\n'; fi
}
k_sprint() { # k_sprint <arquivo> <nn> <kind> <id|status|cria|altera|depende>...
  local arq="$1" nn="$2" kind="$3" sp id st cr al dp ids=""; shift 3
  for sp; do ids="$ids${ids:+, }${sp%%|*}"; done
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: %s\ntrabalho_id: menu\nsprint_id: sprint-%s\natualizado_em: 2026-09-10\n' "$kind" "$nn"
    if [ "$kind" = plano ]; then
      printf 'sprint:\n  titulo: Menu por perfil\n  status: em_andamento\n  criterio_saida: A suite inteira roda com npm test e termina com 0 failed\n  riscos: []\n  fora_de_escopo: []\nfases:\n  - id: F-%s.1\n    titulo: Menu\n    status: em_andamento\n    criterio_saida: O menu mostra so os itens do perfil\n    paralelizavel: false\n    paralela_com: []\n    tasks: [%s]\n' "$nn" "$ids"
    fi
    printf 'tasks:\n'
    for sp; do IFS='|' read -r id st cr al dp <<EOF
$sp
EOF
      k_item "$id" "$st" "$cr" "$al" "$dp"; done
    printf -- '---\n\n# Tasks — Sprint %s\n\n' "$nn"
    for sp; do IFS='|' read -r id st cr al dp <<EOF
$sp
EOF
      k_prosa "$id" "$st" "$cr" "$al" "$dp"; done
  } > "$arq"
}
# k_plano <dir> <c|p> <T-04.03> [T-04.03 altera] [T-04.07?] — c: tasks 01..04.02 concluidas; p: tudo pendente.
k_plano() {
  local f s n st; f="$(kf "$1")"; st=pendente; [ "$2" = c ] && st=concluida
  for s in 01 02 03; do
    mkdir -p "$f/sprint-$s"
    if [ "$s" = 03 ]; then
      k_sprint "$f/sprint-03/tasks.md" 03 tasks "T-03.01|$st|src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx||" \
        "T-03.02|$st|src/ui/rodape.tsx||T-03.01" "T-03.03|$st|src/ui/lateral.tsx||" "T-03.04|$st|src/ui/busca.tsx||"
    else
      k_sprint "$f/sprint-$s/tasks.md" "$s" tasks "T-$s.01|$st|src/m$s/a.ts||" "T-$s.02|$st|src/m$s/b.ts||T-$s.01" \
        "T-$s.03|$st|src/m$s/c.ts||" "T-$s.04|$st|src/m$s/d.ts||"
    fi
  done
  mkdir -p "$f/sprint-04"
  set -- "$1" "$2" "$3" "${4:-src/ui/cabecalho-topo.tsx}" "${5:-}"
  n=""; [ -n "$5" ] && n="T-04.07|pendente|src/menu/atalhos.ts||T-04.03"
  k_sprint "$f/sprint-04/tasks.md" 04 plano "T-04.01|$st|src/menu/organizacao.ts, tests/menu/organizacao.test.ts||" \
    "T-04.02|$st|src/menu/visibilidade.ts, tests/menu/visibilidade.test.ts||T-04.01" \
    "T-04.03|$3|src/menu/perfil.ts, tests/menu/perfil.test.ts|$4|T-04.02" \
    "T-04.04|pendente|src/menu/rotas.ts||T-04.03" "T-04.05|pendente|src/menu/icones.ts||" "T-04.06|pendente|src/menu/ajuda.ts||" ${n:+"$n"}
}
k_aud() { auditoria "$1" menu "$2" "$3"; }
# k_fx <dir> <reprovacoes antes do SIM> <criar args...> — F1..F5 aprovada e F6 executada
# ate T-04.03 bloqueada (gravada, sem commit: task bloqueada nao gera E1). Sem B-NN.
k_fx() {
  local d="$1" n="$2" i f; shift 2; f="$(kf "$d")"
  nova_feature "$d" menu
  pl "$d" criar menu "$@" >/dev/null || return 1
  printf 'decisoes\n' > "$f/00-DECISOES.md"; pl "$d" avanca menu f2 >/dev/null || return 1
  k_plano "$d" p pendente; pl "$d" avanca menu f3 >/dev/null || return 1
  printf 'orquestrador\n' > "$f/ORQUESTRADOR.md"; pl "$d" avanca menu f4 >/dev/null || return 1
  i=0
  while [ "$i" -lt "$n" ]; do
    i=$((i + 1)); k_aud "$d" "$i" NAO; pl "$d" avanca menu f5 >/dev/null || return 1
    printf 'orquestrador v%s\n' "$i" > "$f/ORQUESTRADOR.md"; pl "$d" avanca menu f3 >/dev/null || return 1; pl "$d" avanca menu f4 >/dev/null || return 1
  done
  k_aud "$d" $((n + 1)) SIM; pl "$d" avanca menu f5 >/dev/null || return 1
  [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = aprovado ] || return 1
  # F6 (E1 simulado): 14 tasks concluidas e commitadas; depois T-04.03 bloqueia.
  k_plano "$d" c pendente; git -C "$d" add -A; git -C "$d" commit -q -m "feat(menu): 14 tasks concluidas (E1)"
  k_plano "$d" c bloqueada
}
kcopia() { local d; d="$(mktemp -d "$K/c.XXXXXX")"; rm -rf "$d"; cp -R "$1" "$d"; printf '%s' "$d"; }
FXP="$K/fx-piloto"; k_fx "$FXP" 2 3 buildx 1; afirma "k0-fixture-piloto" $? "2 de 3 reprovacoes, max_replanejamentos_f6 1, 14/18 concluidas, T-04.03 bloqueada"
# Variantes do piloto que so mudam um teto: o frontmatter do checkpoint e trocado e recommitado.
k_variante() { # k_variante <dir> <sed> — e o planejamento continua valido e em F6
  cp -R "$FXP" "$1"
  sed "$2" "$(kf "$1")/00-PLANEJAMENTO.md" > "$K/pl.tmp" && mv "$K/pl.tmp" "$(kf "$1")/00-PLANEJAMENTO.md"     && git -C "$1" commit -q -m variante -- docs/sprintx/features/menu/00-PLANEJAMENTO.md && [ "$(kv "$(pl "$1" fase menu)" fase)" = F6 ]
}
FX2="$K/fx-f6-2"; k_variante "$FX2" 's/^max_replanejamentos_f6: 1$/max_replanejamentos_f6: 2/'; afirma "k0-fixture-teto-f6-2" $? "max_replanejamentos_f6 2"
FX5="$K/fx-f5-5"; k_variante "$FX5" 's/^max_reprovacoes_f5: 3$/max_reprovacoes_f5: 5/'; afirma "k0-fixture-teto-f5-5" $? "2 de 5 reprovacoes"
FXN="$K/fx-f6-null"; k_variante "$FXN" 's/^max_replanejamentos_f6: 1$/max_replanejamentos_f6: null/'; afirma "k0-fixture-f6-nao-declarado" $? "max_replanejamentos_f6 null"
FXL="$K/fx-f6-legado"; cp -R "$FXP" "$FXL"
# Planejamento anterior a este contrato: exatamente as chaves que o P0.1 gravava.
sed -e '/^max_replanejamentos_f6:/d' -e '/^replanejamentos_f6:/d' -e '/^bloqueios_replanejamento_f6:/d' -e '/^tasks_congeladas:/d' \
  -e '/^assinatura_congeladas:/d' -e '/^parciais_replanejamento_f6:/d' -e 's/ · replanejamentos da execução (F6): [^·]*//' "$(kf "$FXL")/00-PLANEJAMENTO.md" > "$K/pl.tmp" \
  && mv "$K/pl.tmp" "$(kf "$FXL")/00-PLANEJAMENTO.md" && git -C "$FXL" commit -q -m legado -- docs/sprintx/features/menu/00-PLANEJAMENTO.md
[ "$(tr -d '\r' < "$(kf "$FXL")/00-PLANEJAMENTO.md" | awk 'NR==1{next} $0=="---"{exit} /^[a-z0-9_]+:/{sub(/:.*/,""); printf "%s ", $0}')" \
  = "expx_schema expx_tool kind trabalho_id max_reprovacoes_f5 orcamento_declarado_por estado reprovacoes atualizado_em historico " ] \
  && [ "$(kv "$(pl "$FXL" fase menu)" fase)" = F6 ]
afirma "k0-fixture-planejamento-legado" $? "forma P0.1, sem o eixo F6, valida e em F6"
# Feature anterior ao 00-PLANEJAMENTO.md: o estado sai do disco (auditoria SIM -> F6).
FXS="$K/fx-sem-planejamento"; cp -R "$FXP" "$FXS"
git -C "$FXS" rm -q docs/sprintx/features/menu/00-PLANEJAMENTO.md && git -C "$FXS" commit -q -m "legado sem planejamento" \
  && [ ! -f "$(kf "$FXS")/00-PLANEJAMENTO.md" ] && s="$(pl "$FXS" fase menu)" && [ "$(kv "$s" fase)" = F6 ] && [ "$(kv "$s" fonte)" = legado ]
afirma "k0-fixture-sem-planejamento" $? "sem 00-PLANEJAMENTO.md, auditoria SIM, fase F6 pela tabela antiga"

# K1. O piloto: entra em replanejar_execucao, consome 1/1, B-01 aberto, concluidas intactas, F5 intacto.
k_inicia() {
  local s="$1" d="$2" f out c0; f="$(kf "$d")"; c0="$(kcong "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'T-04.03 precisa alterar tests/ui/cabecalho-topo.test.tsx, criado pela T-03.01' 'acrescentar o arquivo a T-04.03' >/dev/null || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = iniciado ] && [ "$(kv "$out" estado)" = replanejar_execucao ] && [ "$(kv "$out" proxima)" = F3 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = replanejar_execucao ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" max_replanejamentos_f6)" = 1 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" reprovacoes)" = 2 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" max_reprovacoes_f5)" = 3 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" bloqueios_replanejamento_f6)" = "[B-01]" ] \
    && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|aberto" ] && [ "$(kst "$d" T-04.03)" = bloqueada ] \
    && [ "$(kcong "$d")" = "$c0" ] && [ "$(kv "$(kpl "$s" "$d" fase menu)" fase)" = F3 ] \
    && [ "$(trailer "$d" Estado)" = replanejar_execucao ] && [ "$(trailer "$d" Fase)" = f6 ] && [ "$(trailer "$d" Rodada)" = 1 ] \
    && git -C "$d" diff --quiet HEAD -- docs/sprintx/features/menu \
    && [ "$(tr -d '\r' < "$f/00-PLANEJAMENTO.md" | grep -c '^  - rodada:')" -eq 3 ] || return 1
  c="$(fmv "$f/00-PLANEJAMENTO.md" tasks_congeladas)"
  [ "$c" = "[T-01.01, T-01.02, T-01.03, T-01.04, T-02.01, T-02.02, T-02.03, T-02.04, T-03.01, T-03.02, T-03.03, T-03.04, T-04.01, T-04.02]" ]
}
# K2. Retomada da mesma rodada: nao consome orcamento de novo, em nenhum estado da rodada.
k_retomada() {
  local s="$1" d="$2" f out; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = retomada ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = retomada ] && [ "$(kv "$out" estado)" = aguardando_f4 ] && [ "$(kv "$out" proxima)" = F4 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" max_replanejamentos_f6)" = 2 ] \
    && grep -q '"evento":"replanejamento_execucao_retomado"' "$d/docs/eventos/menu.jsonl"
}
# K3. Antes da nova aprovacao o defeito_de_plano nao se resolve — nem com o plano ja editado.
k_resolver_antes() {
  local s="$1" d="$2" f a; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kbl "$s" "$d" resolver menu B-01 >/dev/null; [ $? -eq 5 ] || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  k_plano "$d" c bloqueada 'src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx'
  a="$(cksum < "$f/00-BLOQUEIOS.md")"
  kbl "$s" "$d" resolver menu B-01 >/dev/null; [ $? -eq 5 ] || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  kbl "$s" "$d" resolver menu B-01 >/dev/null; [ $? -eq 5 ] || return 1
  [ "$(cksum < "$f/00-BLOQUEIOS.md")" = "$a" ] && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|aberto" ] \
    && tr -d '\r' < "$f/00-BLOQUEIOS.md" | grep -qx '    resolvido_em: null'
}
# K4. O ciclo inteiro: plano parcial muda T-04.03 e o futuro; F5 aprova; B-01 resolvido pela
# chave; T-04.03 volta a pendente; concluidas intactas; F6 so com o que resta.
k_aprovacao() {
  local s="$1" d="$2" f c0 out rest; f="$(kf "$d")"; c0="$(kcong "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'T-04.03 precisa alterar tests/ui/cabecalho-topo.test.tsx' 'ampliar ownership' >/dev/null || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  # F3: o mesmo arquivo que a T-03.01 concluida criou entra em `altera` da T-04.03; nasce a T-04.07.
  k_plano "$d" c bloqueada 'src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx' nova
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 4 SIM
  out="$(kpl "$s" "$d" avanca menu f5)" || return 1
  [ "$(kv "$out" estado)" = aprovado ] && [ "$(kv "$out" proxima)" = F6 ] && [ "$(kv "$out" reprovacoes)" = 2 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" bloqueios_replanejamento_f6)" = "[]" ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" tasks_congeladas)" = "[]" ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" assinatura_congeladas)" = null ] \
    && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|resolvido" ] && tr -d '\r' < "$f/00-BLOQUEIOS.md" | grep -q '^B-01 | T-04.03 | .* · resolvido em ' \
    && [ "$(kst "$d" T-04.03)" = pendente ] && tr -d '\r' < "$f/sprint-04/tasks.md" | grep -qx 'status: pendente' \
    && [ "$(kcong "$d")" = "$c0" ] && [ "$(kv "$(kpl "$s" "$d" fase menu)" fase)" = F6 ] \
    && git -C "$d" diff --quiet HEAD -- docs/sprintx/features/menu && [ "$(trailer "$d" Estado)" = aprovado ] || return 1
  tr -d '\r' < "$f/sprint-04/tasks.md" | sed -n '/^  - id: T-04.03$/,/^    suite:/p' | grep -qx '      altera: \[src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx\]' \
    && tr -d '\r' < "$f/sprint-03/tasks.md" | sed -n '/^  - id: T-03.01$/,/^    suite:/p' | grep -qx '      cria: \[src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx\]' || return 1
  rest=""; for t in T-01.01 T-01.02 T-01.03 T-01.04 T-02.01 T-02.02 T-02.03 T-02.04 T-03.01 T-03.02 T-03.03 T-03.04 T-04.01 T-04.02 T-04.03 T-04.04 T-04.05 T-04.06 T-04.07; do
    [ "$(kst "$d" "$t")" = concluida ] || rest="$rest$t "
  done
  [ "$rest" = "T-04.03 T-04.04 T-04.05 T-04.06 T-04.07 " ] \
    && grep -q '"evento":"replanejamento_execucao_aprovado"' "$d/docs/eventos/menu.jsonl" \
    && grep -q '"evento":"bloqueio_resolvido".*"task":"T-04.03"' "$d/docs/eventos/menu.jsonl" \
    && grep -q '"evento":"task_reaberta".*"task":"T-04.03"' "$d/docs/eventos/menu.jsonl" \
    && grep -q '"evento":"replanejamento_execucao_iniciado"' "$d/docs/eventos/menu.jsonl"
}
# K5. Segundo defeito_de_plano com 1/1 consumido: nenhuma rodada nova; estado terminal proprio.
k_segundo_defeito() {
  local s="$1" d="$2" f out; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  k_plano "$d" c bloqueada 'src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx'
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 4 SIM; kpl "$s" "$d" avanca menu f5 >/dev/null || return 1
  # De volta a F6: T-04.04 descobre outro arquivo fora do ownership.
  awk '/^  - id: T-04.04$/{t=1} t && /^    status: pendente$/{print "    status: bloqueada"; t=0; next} {print}' "$f/sprint-04/tasks.md" > "$K/t.tmp" && mv "$K/t.tmp" "$f/sprint-04/tasks.md"
  kbl "$s" "$d" registrar menu T-04.04 defeito_de_plano 'T-04.04 precisa de src/menu/perfil.ts' 'mover o arquivo' >/dev/null || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = esgotado ] && [ "$(kv "$out" estado)" = replanejamento_execucao_esgotado ] && [ "$(kv "$out" proxima)" = PARAR ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = replanejamento_execucao_esgotado ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" reprovacoes)" = 2 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" bloqueios_replanejamento_f6)" = "[]" ] \
    && [ "$(kbloq "$d" B-02)" = "defeito_de_plano|aberto" ] && [ "$(kv "$(kpl "$s" "$d" fase menu)" fase)" = PARAR ] \
    && [ "$(trailer "$d" Estado)" = replanejamento_execucao_esgotado ] \
    && grep -q '"evento":"replanejamento_execucao_esgotado"' "$d/docs/eventos/menu.jsonl" || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null; [ $? -eq 5 ] || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = esgotado ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ]
}
# k_recusa <script> <dir> <motivo> — nada gravado, estado aprovado, contador intacto.
k_recusa() {
  local s="$1" d="$2" f ck h out rc; f="$(kf "$d")"; ck="$(cksum < "$f/00-PLANEJAMENTO.md")"; h="$(git -C "$d" rev-parse HEAD)"
  out="$(kpl "$s" "$d" replanejar-execucao menu)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" replanejamento)" = recusado ] && [ "$(kv "$out" motivo)" = "$3" ] \
    && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = aprovado ] && [ "$(kv "$(kpl "$s" "$d" fase menu)" fase)" = F6 ]
}
# k_recusa_duravel <script> <dir> <motivo> — recusa OPERACIONAL: o terminal
# replanejamento_execucao_recusado gravado com o motivo e persistido num checkpoint; nenhuma
# rodada, contador, task ou bloqueio mexido; um evento. Repetir devolve o mesmo terminal e o
# mesmo motivo sem gravar, commitar nem registrar nada.
k_recusa_duravel() {
  local s="$1" d="$2" f a h n6 st0 bl0 out rc ck ev; f="$(kf "$d")"; a="$f/00-PLANEJAMENTO.md"
  h="$(git -C "$d" rev-parse HEAD)"; n6=0; [ -f "$a" ] && n6="$(fmv "$a" replanejamentos_f6)"
  st0="$(kst "$d" T-04.03)"; bl0="$(kbl "$s" "$d" listar menu)"
  out="$(kpl "$s" "$d" replanejar-execucao menu)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" replanejamento)" = recusado ] && [ "$(kv "$out" motivo)" = "$3" ] \
    && [ "$(kv "$out" estado)" = replanejamento_execucao_recusado ] && [ "$(kv "$out" proxima)" = PARAR ] \
    && [ "$(kv "$out" recusa_replanejamento_f6)" = "$3" ] \
    && [ "$(fmv "$a" estado)" = replanejamento_execucao_recusado ] && [ "$(fmv "$a" recusa_replanejamento_f6)" = "$3" ] \
    && [ "$(fmv "$a" replanejamentos_f6)" = "$n6" ] && [ "$(tr -d '\r' < "$a" | grep -c '^bloqueios_replanejamento_f6: \[B')" -eq 0 ] \
    && [ "$(kst "$d" T-04.03)" = "$st0" ] && [ "$(kbl "$s" "$d" listar menu)" = "$bl0" ] \
    && [ "$(git -C "$d" rev-list --count "$h..HEAD")" -eq 1 ] && [ "$(trailer "$d" Estado)" = replanejamento_execucao_recusado ] \
    && [ "$(trailer "$d" Fase)" = f6 ] && git -C "$d" diff --quiet HEAD -- docs/sprintx/features/menu \
    && [ -z "$(git -C "$d" status --porcelain -- docs/sprintx/features/menu)" ] \
    && [ "$(grep -c "\"evento\":\"replanejamento_execucao_recusado\".*\"detalhe\":\"$3:" "$d/docs/eventos/menu.jsonl")" -eq 1 ] || return 1
  out="$(kpl "$s" "$d" fase menu)"
  [ "$(kv "$out" fase)" = PARAR ] && [ "$(kv "$out" estado)" = replanejamento_execucao_recusado ] \
    && [ "$(kv "$out" recusa_replanejamento_f6)" = "$3" ] && [ "$(kv "$out" persistencia)" = duravel ] || return 1
  h="$(git -C "$d" rev-parse HEAD)"; ck="$(cksum < "$a")"; ev="$(cksum < "$d/docs/eventos/menu.jsonl")"
  out="$(kpl "$s" "$d" replanejar-execucao menu)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" replanejamento)" = recusado ] && [ "$(kv "$out" motivo)" = "$3" ] \
    && [ "$(kv "$out" estado)" = replanejamento_execucao_recusado ] && [ "$(kv "$out" proxima)" = PARAR ] \
    && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ] && [ "$(cksum < "$d/docs/eventos/menu.jsonl")" = "$ev" ] \
    && [ "$(kst "$d" T-04.03)" = "$st0" ] && [ "$(kbl "$s" "$d" listar menu)" = "$bl0" ] || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null; [ $? -eq 5 ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ]
}
# K6-K8. Classes que nao iniciam replanejamento — com descricao que "fala" de defeito de plano.
k_lacuna() {
  kbl "$1" "$2" registrar menu T-04.03 lacuna_de_decisao 'arquivo fora do ownership da task: defeito de plano, replanejar' 'decidir' >/dev/null || return 1
  k_recusa "$1" "$2" sem_defeito_de_plano
}
k_prerequisito() {
  kbl "$1" "$2" registrar menu T-04.03 prerequisito_ausente 'o plano precisa mudar: arquivo fora do ownership' 'provisionar' >/dev/null || return 1
  k_recusa "$1" "$2" sem_defeito_de_plano
}
k_legado_bloqueio() {
  cat > "$(kf "$2")/00-BLOQUEIOS.md" <<'EOF'
---
expx_schema: 1
expx_tool: sprintx
kind: bloqueios
trabalho_id: menu
atualizado_em: 2026-09-12
bloqueios:
  - id: B-01
    task: T-04.03
    aberto_em: 2026-09-12
    resolvido_em: null
    descricao: T-04.03 precisa alterar tests/ui/cabecalho-topo.test.tsx, fora do ownership da task, defeito_de_plano
---

# Bloqueios

B-01 | T-04.03 | T-04.03 precisa alterar tests/ui/cabecalho-topo.test.tsx, fora do ownership da task | replanejar
EOF
  [ "$(kbloq "$2" B-01)" = "legado|aberto" ] && k_recusa "$1" "$2" sem_defeito_de_plano
}
# K9. Mistura de classes abertas: nenhuma precedencia inventada, nenhuma rodada; a recusa e o
# terminal duravel `classes_mistas`, e o motivo nao e reavaliado depois.
k_mistura() {
  local s="$1" d="$2" f h out rc; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kbl "$s" "$d" registrar menu null prerequisito_ausente 'o plano precisa mudar: servico de icones fora do ar' 'religar' >/dev/null || return 1
  k_recusa_duravel "$s" "$d" classes_mistas && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" max_replanejamentos_f6)" = 1 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" reprovacoes)" = 2 ] \
    && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|aberto" ] && [ "$(kbloq "$d" B-02)" = "prerequisito_ausente|aberto" ] \
    && [ "$(kst "$d" T-04.03)" = bloqueada ] || return 1
  # Resolvido o prerequisito, so defeito_de_plano fica aberto: o terminal nao muda.
  h="$(git -C "$d" rev-parse HEAD)"; kbl "$s" "$d" resolver menu B-02 >/dev/null || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" motivo)" = classes_mistas ] && [ "$(kv "$out" estado)" = replanejamento_execucao_recusado ] \
    && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" recusa_replanejamento_f6)" = classes_mistas ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" bloqueios_replanejamento_f6)" = "[]" ]
}
# K10. Varios defeito_de_plano abertos: uma rodada, lista em ordem de id (mesmo com o arquivo
# fora de ordem), B-NN sem task resolvido sem inventar task, e so os da rodada sao resolvidos.
k_varios() {
  local s="$1" d="$2" f out; f="$(kf "$d")"
  awk '/^  - id: T-04.05$/{t=1} t && /^    status: pendente$/{print "    status: bloqueada"; t=0; next} {print}' "$f/sprint-04/tasks.md" > "$K/v.tmp" && mv "$K/v.tmp" "$f/sprint-04/tasks.md"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kbl "$s" "$d" registrar menu null lacuna_de_decisao 'nenhuma D-NN cobre o icone' 'decidir' >/dev/null || return 1
  kbl "$s" "$d" resolver menu B-02 >/dev/null || return 1
  kbl "$s" "$d" registrar menu null defeito_de_plano 'criterio_saida da F-04.1 sem task que o cumpra' 'nova task' >/dev/null || return 1
  kbl "$s" "$d" registrar menu T-04.05 defeito_de_plano 'depende_de ausente' 'declarar dependencia' >/dev/null || return 1
  # Arquivo fora de ordem: B-04 antes de B-01 no frontmatter.
  awk '/^bloqueios:$/{print; b=1; next} b && /^  - id: B-01$/{g=1} b && /^  - id: B-02$/{g=0} g{h=h $0 "\n"; next} b && /^---$/{printf "%s", h; b=0} {print}' "$f/00-BLOQUEIOS.md" > "$K/b.tmp" && mv "$K/b.tmp" "$f/00-BLOQUEIOS.md"
  [ "$(kbl "$s" "$d" listar menu | tr -d '\r' | cut -f1 | tr '\n' ' ')" = "B-02 B-03 B-04 B-01 " ] || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" bloqueios_replanejamento_f6)" = "B-01,B-03,B-04" ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" bloqueios_replanejamento_f6)" = "[B-01, B-03, B-04]" ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] || return 1
  # Durante a rodada alguem registra B-05: nao pertence a rodada.
  kbl "$s" "$d" registrar menu null prerequisito_ausente 'servico de icones fora do ar' 'religar' >/dev/null || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 4 SIM; kpl "$s" "$d" avanca menu f5 >/dev/null || return 1
  [ "$(kbloq "$d" B-01)" = "defeito_de_plano|resolvido" ] && [ "$(kbloq "$d" B-03)" = "defeito_de_plano|resolvido" ] \
    && [ "$(kbloq "$d" B-04)" = "defeito_de_plano|resolvido" ] && [ "$(kbloq "$d" B-05)" = "prerequisito_ausente|aberto" ] \
    && [ "$(kbloq "$d" B-02)" = "lacuna_de_decisao|resolvido" ] \
    && [ "$(kst "$d" T-04.03)" = pendente ] && [ "$(kst "$d" T-04.05)" = pendente ] && [ "$(kst "$d" T-04.04)" = pendente ] \
    && [ "$(grep -c '"evento":"task_reaberta"' "$d/docs/eventos/menu.jsonl")" -eq 2 ]
}
# K11. Planejamento legado (sem o eixo F6): recusa duravel, e nenhum orcamento inventado, nem na
# leitura, nem na gravacao do terminal, nem numa retomada.
k_legado_orcamento() {
  local s="$1" d="$2" f; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  k_recusa_duravel "$s" "$d" orcamento_f6_legado || return 1
  [ "$(kv "$(kpl "$s" "$d" fase menu)" orcamento_f6)" = legado ] || return 1
  kpl "$s" "$d" criar menu 3 buildx 1 >/dev/null; [ $? -eq 4 ] || return 1
  kpl "$s" "$d" criar menu 3 buildx >/dev/null || return 1
  ! fm_tem_k "$f/00-PLANEJAMENTO.md" max_replanejamentos_f6 && ! fm_tem_k "$f/00-PLANEJAMENTO.md" replanejamentos_f6 \
    && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|aberto" ]
}
fm_tem_k() { tr -d '\r' < "$1" | awk -v k="$2" 'NR==1{next} $0=="---"{exit} index($0,k":")==1{a=1} END{exit !a}'; }
# K12. Orcamento da F6 nao declarado (criar sem o quarto argumento): nao abre; recusa duravel, sem 1 presumido.
k_sem_orcamento() {
  kbl "$1" "$2" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  [ "$(fmv "$(kf "$2")/00-PLANEJAMENTO.md" max_replanejamentos_f6)" = null ] && k_recusa_duravel "$1" "$2" orcamento_f6_nao_declarado \
    && [ "$(fmv "$(kf "$2")/00-PLANEJAMENTO.md" max_replanejamentos_f6)" = null ] && [ "$(fmv "$(kf "$2")/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ]
}
# K13. Produto da task bloqueada sujo na arvore: fronteira insegura, nada gravado, nada limpo.
k_fronteira() {
  local s="$1" d="$2" f ck h rc; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  mkdir -p "$d/src/menu"; printf 'export const perfil = 1\n' > "$d/src/menu/perfil.ts"
  printf 'export const x = 2\n' > "$d/src/app.ts"
  ck="$(cksum < "$f/00-PLANEJAMENTO.md")"; h="$(git -C "$d" rev-parse HEAD)"
  kpl "$s" "$d" replanejar-execucao menu >/dev/null; rc=$?
  [ "$rc" -eq 2 ] && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] \
    && [ "$(cat "$d/src/menu/perfil.ts")" = 'export const perfil = 1' ] && [ "$(cat "$d/src/app.ts")" = 'export const x = 2' ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ] && [ "$(git -C "$d" stash list | wc -l | tr -d ' ')" = 0 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = aprovado ] && ! fm_tem_k "$f/00-PLANEJAMENTO.md" recusa_replanejamento_f6 \
    && [ "$(kv "$(kpl "$s" "$d" fase menu)" fase)" = F6 ] && [ "$(grep -c '"detalhe":"fronteira insegura' "$d/docs/eventos/menu.jsonl")" -eq 1 ]
}
# K14. F5 reprova durante a rodada: o contador da F5 continua de onde estava (2 -> 3 de 5)...
k_f5_nao_continua() {
  local s="$1" d="$2" f out c0; f="$(kf "$d")"; c0="$(kcong "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 4 NAO; out="$(kpl "$s" "$d" avanca menu f5)" || return 1
  [ "$(kv "$out" estado)" = replanejar ] && [ "$(kv "$out" reprovacoes)" = 3 ] && [ "$(kv "$out" max_reprovacoes_f5)" = 5 ] \
    && [ "$(kv "$out" replanejamento_execucao)" = ativo ] && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|aberto" ] || return 1
  k_plano "$d" c bloqueada 'src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx'
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 5 SIM; out="$(kpl "$s" "$d" avanca menu f5)" || return 1
  [ "$(kv "$out" estado)" = aprovado ] && [ "$(kv "$out" reprovacoes)" = 3 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] \
    && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|resolvido" ] && [ "$(kst "$d" T-04.03)" = pendente ] && [ "$(kcong "$d")" = "$c0" ] \
    && [ "$(tr -d '\r' < "$f/00-PLANEJAMENTO.md" | grep -c '^  - rodada:')" -eq 5 ]
}
# ...e, esgotado, cai no terminal que a F5 ja tinha (2 -> 3 de 3): sem segundo reset.
k_f5_nao_esgota() {
  local s="$1" d="$2" f out; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 4 NAO; out="$(kpl "$s" "$d" avanca menu f5)" || return 1
  [ "$(kv "$out" estado)" = orcamento_esgotado ] && [ "$(kv "$out" reprovacoes)" = 3 ] && [ "$(kv "$out" proxima)" = PARAR ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|aberto" ] \
    && [ "$(kst "$d" T-04.03)" = bloqueada ] || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null; [ $? -eq 5 ] || return 1
  kbl "$s" "$d" resolver menu B-01 >/dev/null; [ $? -eq 5 ]
}
# K15. Reescrever historia concluida durante a rodada: cada portao recusa (codigo 4) e nada registra.
k_concluidas_protegidas() {
  local s="$1" d="$2" f ck m rc o="$K/orig.$$"; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  mkdir -p "$o"; cp "$f/sprint-03/tasks.md" "$o/s3"; cp "$f/sprint-04/tasks.md" "$o/s4"; ck="$(cksum < "$f/00-PLANEJAMENTO.md")"
  # ampliar `arquivos`; reabrir; renumerar; concluir sem executar; reescrever a prosa; apagar.
  for m in     "sprint-03|/^  - id: T-03.01\$/,/^    suite:/s/^      altera: \[\]\$/      altera: [src\/x.ts]/"     "sprint-04|/^  - id: T-04.02\$/,/^    suite:/s/^    status: concluida\$/    status: pendente/"     "sprint-04|s/^  - id: T-04.01\$/  - id: T-04.11/"     "sprint-04|/^  - id: T-04.06\$/,/^    suite:/s/^    status: pendente\$/    status: concluida/"     "sprint-03|s/^2026-09-10 · suíte: 3 passed, 0 failed · real: 1 h\$/2026-09-10 · suíte: 9 passed, 0 failed · real: 1 h/"     "sprint-04|/^  - id: T-04.02\$/,/^    suite:/d"; do
    cp "$o/s3" "$f/sprint-03/tasks.md"; cp "$o/s4" "$f/sprint-04/tasks.md"
    sed "${m#*|}" "$f/${m%%|*}/tasks.md" > "$K/m.tmp" && mv "$K/m.tmp" "$f/${m%%|*}/tasks.md"
    if cmp -s "$o/s3" "$f/sprint-03/tasks.md" && cmp -s "$o/s4" "$f/sprint-04/tasks.md"; then return 1; fi
    kpl "$s" "$d" avanca menu f3 >/dev/null; rc=$?
    [ "$rc" -eq 4 ] && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = replanejar_execucao ] || return 1
  done
  cp "$o/s3" "$f/sprint-03/tasks.md"; cp "$o/s4" "$f/sprint-04/tasks.md"
  kpl "$s" "$d" avanca menu f3 >/dev/null
}
# K16. A task do B-NN tem de estar gravada como bloqueada antes da transicao.
k_task_nao_bloqueada() {
  local s="$1" d="$2" f ck rc; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.04 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  ck="$(cksum < "$f/00-PLANEJAMENTO.md")"
  kpl "$s" "$d" replanejar-execucao menu >/dev/null; rc=$?
  [ "$rc" -eq 4 ] && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ]
}
# K24. Feature sem 00-PLANEJAMENTO.md: recusa duravel `planejamento_legado`; o arquivo nasce pela
# migracao ja no terminal, sem orcamento nenhum inventado.
k_planejamento_legado() {
  local s="$1" d="$2" f; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  k_recusa_duravel "$s" "$d" planejamento_legado || return 1
  [ "$(fmv "$f/00-PLANEJAMENTO.md" max_replanejamentos_f6)" = null ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" max_reprovacoes_f5)" = null ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" orcamento_declarado_por)" = null ] \
    && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|aberto" ]
}
# K25. Sem worktree: a recusa e o motivo sobrevivem so no que foi commitado. A arvore da execucao
# e perdida; um clone da branch (sem rastro, sem sessao) reconhece o mesmo terminal.
k_sem_worktree() {
  local s="$1" d="$2" c out rc h
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kbl "$s" "$d" registrar menu null prerequisito_ausente 'servico de icones fora do ar' 'religar' >/dev/null || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null; [ $? -eq 5 ] || return 1
  c="$(mktemp -d "$K/clone.XXXXXX")"; rm -rf "$c"
  git clone -q -c core.autocrlf=false -b feature/menu "$d" "$c" || return 1
  rm -rf "$d"; [ ! -e "$d" ] && [ ! -e "$c/docs/eventos" ] || return 1
  out="$(kpl "$s" "$c" fase menu)"; rc=$?
  [ "$rc" -eq 0 ] && [ "$(kv "$out" fase)" = PARAR ] && [ "$(kv "$out" estado)" = replanejamento_execucao_recusado ] \
    && [ "$(kv "$out" recusa_replanejamento_f6)" = classes_mistas ] && [ "$(kv "$out" persistencia)" = duravel ] || return 1
  h="$(git -C "$c" rev-parse HEAD)"
  out="$(kpl "$s" "$c" replanejar-execucao menu)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" replanejamento)" = recusado ] && [ "$(kv "$out" motivo)" = classes_mistas ] \
    && [ "$(kv "$out" proxima)" = PARAR ] && [ "$(git -C "$c" rev-parse HEAD)" = "$h" ] \
    && [ -z "$(git -C "$c" status --porcelain)" ] && [ ! -e "$c/docs/eventos" ] \
    && [ "$(fmv "$(kf "$c")/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ]
}
# K26. Erros de contrato nao viram recusa gravada: sem bloqueio aberto, registro invalido.
k_sem_bloqueio() {
  k_recusa "$1" "$2" sem_bloqueio_aberto && ! fm_tem_k "$(kf "$2")/00-PLANEJAMENTO.md" recusa_replanejamento_f6
}
k_registro_invalido() {
  local s="$1" d="$2" f ck h rc; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kbl "$s" "$d" registrar menu null prerequisito_ausente 'servico de icones fora do ar' 'religar' >/dev/null || return 1
  sed 's/^    classe: prerequisito_ausente$/    classe: prerequisito/' "$f/00-BLOQUEIOS.md" > "$K/r.tmp" && mv "$K/r.tmp" "$f/00-BLOQUEIOS.md"
  ck="$(cksum < "$f/00-PLANEJAMENTO.md")"; h="$(git -C "$d" rev-parse HEAD)"
  kpl "$s" "$d" replanejar-execucao menu >/dev/null; rc=$?
  [ "$rc" -eq 4 ] && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = aprovado ]
}
# K27. O terminal recusado no schema: chave se e somente se o estado, motivo do enum operacional,
# coerente com o eixo F6. O controle positivo le o terminal valido.
k_recusa_schema() {
  local s="$1" d="$2" a o="$K/sch.$$" rc m; a="$(kf "$d")/00-PLANEJAMENTO.md"; cp "$a" "$o"
  troca_estado() { E_R="$1" awk '$0 == "estado: aprovado" { print ENVIRON["E_R"]; next } { print }' "$o" > "$a"; }
  for m in "aprovado|classes_mistas" "replanejamento_execucao_recusado|" "replanejamento_execucao_recusado|orcamento_f6_legado" \
    "replanejamento_execucao_recusado|sem_defeito_de_plano" "replanejamento_execucao_recusado|fronteira_insegura"; do
    if [ -n "${m#*|}" ]; then troca_estado "estado: ${m%%|*}
recusa_replanejamento_f6: ${m#*|}"; else troca_estado "estado: ${m%%|*}"; fi
    cmp -s "$o" "$a" && return 1
    kpl "$s" "$d" fase menu >/dev/null; rc=$?; [ "$rc" -eq 4 ] || return 1
  done
  troca_estado "estado: replanejamento_execucao_recusado
recusa_replanejamento_f6: classes_mistas"
  git -C "$d" commit -q -m recusado -- docs/sprintx/features/menu/00-PLANEJAMENTO.md || return 1
  [ "$(kv "$(kpl "$s" "$d" fase menu)" fase)" = PARAR ]
}
CASOS_K="k_inicia:FXP k_retomada:FX2 k_resolver_antes:FXP k_aprovacao:FXP k_segundo_defeito:FXP k_lacuna:FXP k_prerequisito:FXP
  k_legado_bloqueio:FXP k_mistura:FXP k_varios:FXP k_legado_orcamento:FXL k_sem_orcamento:FXN k_fronteira:FXP
  k_f5_nao_continua:FX5 k_f5_nao_esgota:FXP k_concluidas_protegidas:FXP k_task_nao_bloqueada:FXP
  k_planejamento_legado:FXS k_sem_worktree:FXP k_sem_bloqueio:FXP k_registro_invalido:FXP k_recusa_schema:FXP"
fx_de() { local c; for c in $CASOS_K; do [ "${c%%:*}" = "$1" ] && { eval "printf '%s' \"\$${c#*:}\""; return; }; done; }
roda_k() { local d; d="$(kcopia "$(fx_de "$1")")"; "$1" "$2" "$d"; }
for par in k_inicia:k1-piloto-entra-em-replanejar-execucao k_retomada:k2-retomada-nao-consome-de-novo \
  k_resolver_antes:k3-resolver-antes-da-aprovacao-recusado k_aprovacao:k4-aprovacao-resolve-reabre-preserva \
  k_segundo_defeito:k5-segundo-defeito-apos-1-de-1-esgota k_lacuna:k6-lacuna-de-decisao-nao-replaneja \
  k_prerequisito:k7-prerequisito-ausente-nao-replaneja k_legado_bloqueio:k8-bloqueio-legado-nao-replaneja \
  k_mistura:k9-classes-mistas-nao-replaneja k_varios:k10-varios-defeitos-uma-rodada-ordenada \
  k_legado_orcamento:k11-planejamento-legado-sem-orcamento-inventado k_sem_orcamento:k12-orcamento-f6-nao-declarado-nao-abre \
  k_planejamento_legado:k24-sem-planejamento-recusa-duravel-sem-orcamento k_sem_worktree:k25-recusa-sobrevive-sem-worktree \
  k_sem_bloqueio:k26-sem-bloqueio-aberto-nao-grava k_registro_invalido:k26-registro-invalido-nao-grava \
  k_recusa_schema:k27-terminal-recusado-no-schema \
  k_fronteira:k13-produto-sujo-fronteira-insegura k_f5_nao_continua:k14-f5-nao-durante-rodada-continua \
  k_f5_nao_esgota:k15-f5-esgota-no-terminal-existente k_concluidas_protegidas:k16-concluidas-congeladas-nos-portoes \
  k_task_nao_bloqueada:k17-task-do-bloqueio-precisa-estar-bloqueada; do
  roda_k "${par%%:*}" "$PL"; afirma "${par#*:}" $? "${par%%:*}"
done

# Contrato nos documentos: estados, comando da F6, resolucao, congelamento e decisoes.
SCHK="$SK/references/00-schema.md"
for e in replanejar_execucao replanejamento_execucao_esgotado; do
  tr -d '\r' < "$SCHK" | grep -F '| `estado` (planejamento) |' | grep -qF "\`$e\`" && tem "$SKILLMD" "| \`$e\` |" \
    && [ "$(tr -d '\r' < "$PL" | grep -cxF '    replanejar_execucao|replanejamento_execucao_esgotado) ;;')" -eq 1 ]
  afirma "k18-estado-$e-no-enum" $? "schema, tabela do SKILL.md e script"
done
tem "$SKILLMD" '| `replanejamento_execucao_esgotado` | **terminal**' && tem "$SKILLMD" '| `replanejar_execucao` | F3 —'
afirma "k18-skill-f6-volta-pela-f3" $? "replanejar_execucao -> F3; esgotado terminal"
tr -d '\r' < "$SCHK" | grep -F '| `estado` (planejamento) |' | grep -qF '`replanejamento_execucao_recusado`' \
  && tem "$SKILLMD" '| `replanejamento_execucao_recusado` | **terminal**' \
  && [ "$(tr -d '\r' < "$PL" | grep -cxF '    replanejamento_execucao_recusado) ;;')" -eq 1 ] \
  && tr -d '\r' < "$SCHK" | grep -F '| `recusa_replanejamento_f6` (planejamento) |' | grep -qF '`classes_mistas` \| `orcamento_f6_legado` \| `orcamento_f6_nao_declarado` \| `planejamento_legado`' \
  && tem "$SCHK" '**Erro de contrato nunca vira esta recusa**' && tem "$EXEC" 'recusa **operacional**, gravada e persistida'
afirma "k18-estado-replanejamento_execucao_recusado-no-enum" $? "schema, SKILL.md, 06-execucao e script"
KCMD="$CMD_PL replanejar-execucao <slug>"
onde="$(grep -rlF -- "$KCMD" "$SK" "$H/../commands" "$H/../../.opencode" 2>/dev/null)"
[ "$(printf '%s\n' "$onde" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 1 ] && [ "$(basename "$onde")" = 06-execucao.md ] && [ "$(conta "$EXEC" "$KCMD")" -eq 1 ]
afirma "k19-instrucao-unica-replanejar-execucao" $? "${onde:-nenhum arquivo}"
L_REG=$(linha_de "$EXEC" 'bash <raiz-da-skill>/scripts/bloqueios.sh registrar <slug>'); L_RPL=$(linha_de "$EXEC" "$KCMD")
L_PORT=$(linha_de "$EXEC" '## Portões de fase e de sprint')
[ -n "$L_REG" ] && [ -n "$L_RPL" ] && [ "$L_REG" -lt "$L_RPL" ] && [ "$L_RPL" -lt "$L_PORT" ] \
  && tem "$EXEC" '3. **Classe `defeito_de_plano`: devolva o plano ao planejamento agora**' \
  && tem "$EXEC" 'Nunca `stash`, nunca limpe, nunca descarte' && tem "$EXEC" '**Não abra task nova**'
afirma "k19-f6-devolve-o-plano-depois-de-registrar" $? "registrar=$L_REG < replanejar=$L_RPL < portoes=$L_PORT"
tem "$EXEC" 'bash <raiz-da-skill>/scripts/bloqueios.sh resolver <slug> <B-NN>' && tem "$EXEC" '**`defeito_de_plano` não**: editar o plano não resolve um defeito de plano' \
  && tem "$SCHK" '**Resolução.** Só por `scripts/bloqueios.sh resolver <slug> <B-NN>`, nunca editando'
afirma "k20-resolucao-so-pelo-script" $? "06-execucao e schema"
tem "$SK/references/03-plano.md" '### Retorno da F6 — replanejamento da execução' && tem "$SK/references/03-plano.md" '**Tasks `concluida` estão congeladas**' \
  && tem "$SK/references/03-plano.md" 'Não volte à F1 nem à F2' \
  && tr -d '\r' < "$SK/references/05-auditoria.md" | tr '\n' ' ' | grep -qF '**o orçamento da F5 continua de onde estava**'
afirma "k21-f3-e-f5-no-retorno-da-f6" $? "congeladas, sem F1/F2, orcamento da F5 continua"
for ev in replanejamento_execucao_iniciado replanejamento_execucao_retomado replanejamento_execucao_aprovado replanejamento_execucao_esgotado \
  replanejamento_execucao_recusado task_reaberta bloqueio_resolvido; do
  tem "$SK/references/08-rastro.md" "\`$ev\`" && [ "$(cat "$PL" "$BL" | grep -cF "$ev")" -gt 0 ]
  afirma "k22-rastro-$ev" $? "08-rastro e script"
done
DSF="$SK/DECISOES-DA-SKILL.md"; n=0
for ds in 140 141 142 143 144 145 146; do [ "$(grep -c "^| DS-$ds |" "$DSF")" -eq 1 ] && n=$((n + 1)); done
for ds in 147 148; do [ "$(grep -c "^| DS-$ds |" "$DSF")" -eq 1 ] || n=0; done
[ "$n" -eq 7 ] && tem "$DSF" '**Estado próprio `replanejar_execucao`**' \
  && tem "$DSF" '**A F1 repassa os três tetos do pedido' && tem "$DSF" '**Recusa operacional é estado terminal durável' && tem "$DSF" '**Tasks concluídas são congeladas, e o congelamento é mecânico.**' \
  && tem "$DSF" '**Legado sem orçamento retroativo.**' && tem "$DSF" '**O gatilho é a chave `classe` dos B-NN abertos**'
afirma "k23-ds140-a-ds148-registradas" $? "$n de 7, mais DS-147 e DS-148"

# Mutantes do mecanismo, em copia temporaria da skill (scripts/ + assets/: os dois scripts
# se chamam pela propria pasta e acham o template por ela). Cada mutante tem de morrer pelos
# casos designados; o controle, copia SEM mutacao na mesma estrutura, tem de sobreviver a
# todos eles — se morrer, e a bancada que esta quebrada.
MK="$K/mut"
copia_skill_k() { mkdir -p "$MK/$1/scripts" "$MK/$1/assets"; cp "$SK/assets/TEMPLATE-PLANEJAMENTO.md" "$SK/assets/TEMPLATE-BLOQUEIOS.md" "$MK/$1/assets/"; cp "$BL" "$SK/scripts/caminho-git.sh" "$MK/$1/scripts/"; printf '%s/%s/scripts/planejamento.sh' "$MK" "$1"; }
mutante_k() { # mutante_k <nome> <rc da geracao> <script> <caso que TEM de matar>...
  local nome="$1" rc="$2" s="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do roda_k "$c" "$s" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]; afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
DESIGNADOS_K="k_inicia k_retomada k_resolver_antes k_aprovacao k_segundo_defeito k_lacuna k_legado_bloqueio k_mistura k_legado_orcamento
  k_sem_orcamento k_planejamento_legado k_sem_worktree k_fronteira k_registro_invalido"
CTLK="$(copia_skill_k controle)"; cp "$PL" "$CTLK"; vivosk=""
for c in $DESIGNADOS_K; do roda_k "$c" "$CTLK" || vivosk="$vivosk$c "; done
[ -z "$vivosk" ]; afirma "km-controle-copia-intacta-sobrevive" $? "${vivosk:-nenhum caso designado reprova a copia sem mutacao}"
M="$(copia_skill_k a)"; muta_lit "$PL" "$M" '  escreve "$P_MAX" "$P_POR" replanejar_execucao "$P_REPROV" "$P_HIST"' \
  '  escreve "$P_MAX" "$P_POR" replanejar_execucao 0 "$(printf '"'"'%s\n'"'"' "$P_HIST" | awk -F"$TAB" '"'"'$2 == "sim"'"'"' | tail -1 | sed '"'"'s/^[0-9]*/1/'"'"')"'
mutante_k "km-mutante-1-reinicia-reprovacoes-f5" $? "$M" k_inicia
M="$(copia_skill_k b)"; muta_lit "$PL" "$M" '    fm && t && id == alvo && $0 == "    status: bloqueada" { print "    status: pendente"; next }' \
  '    fm && t && $0 ~ /^    status: (bloqueada|concluida)$/ { print "    status: pendente"; next }'
mutante_k "km-mutante-2-reabre-task-concluida" $? "$M" k_aprovacao
M="$(copia_skill_k c)"; muta_lit "$PL" "$M" '  if [ "$P_N6" -ge "$P_MAX6" ]; then' '  if [ "$P_N6" -gt "$P_MAX6" ]; then'
mutante_k "km-mutante-3-segunda-rodada-apos-1-de-1" $? "$M" k_segundo_defeito
M="$(copia_skill_k d)"; muta_lit "$PL" "$M" '    evento replanejamento_execucao_retomado f6 - ok' \
  '    f6_herda; W6_N=$((P_N6 + 1)); escreve "$P_MAX" "$P_POR" "$P_ESTADO" "$P_REPROV" "$P_HIST"; evento replanejamento_execucao_retomado f6 - ok'
mutante_k "km-mutante-4-retomada-consome-de-novo" $? "$M" k_retomada
M="$(copia_skill_k e)"; muta_lit "$PL" "$M" '    elif [ "$P_ESTADO" != aprovado ]; then motivo=rodada_nao_aprovada' '    elif false; then motivo=rodada_nao_aprovada'
mutante_k "km-mutante-5-resolve-antes-da-aprovacao" $? "$M" k_resolver_antes
M="$(copia_skill_k f)"; muta_lit "$PL" "$M" '  abertos="$(abertos_ordenados)"' \
  '  abertos="$(abertos_ordenados | while IFS="$TAB" read -r b t c; do d="$(grep -A6 "^  - id: $b\$" "$PASTA/00-BLOQUEIOS.md" | grep "^    descricao:")"; case "$d" in *ownership*|*plano*|*arquivo*) c=defeito_de_plano ;; *) c=lacuna_de_decisao ;; esac; printf "%s\t%s\t%s\n" "$b" "$t" "$c"; done)"'
mutante_k "km-mutante-6-classe-pela-descricao" $? "$M" k_lacuna k_legado_bloqueio
M="$(copia_skill_k g)"; muta_lit "$PL" "$M" '  if [ -n "$outros" ]; then motivo=classes_mistas' '  if false; then motivo=classes_mistas'
mutante_k "km-mutante-7-replaneja-com-classes-mistas" $? "$M" k_mistura
M="$(copia_skill_k h)"; muta_lit "$PL" "$M" '    P_F6=legado; P_MAX6=null; P_N6=0' '    P_F6=presente; P_MAX6=1; P_N6=0'
mutante_k "km-mutante-8-inventa-orcamento-no-legado" $? "$M" k_legado_orcamento
# A recusa operacional como era antes: so no stdout, nada gravado.
M="$(copia_skill_k i)"; muta_lit "$PL" "$M" '  local motivo="$1" abertos="$2"' \
  '  local motivo="$1" abertos="$2"; printf '"'"'replanejamento=recusado\nmotivo=%s\nestado=%s\n'"'"' "$motivo" "$P_ESTADO"; falha "$E_TRANSICAO" recusado'
mutante_k "km-mutante-9-recusa-so-no-stdout" $? "$M" k_mistura k_sem_orcamento k_legado_orcamento k_planejamento_legado k_sem_worktree
# Grava o terminal, mas nao faz o checkpoint: some com o worktree.
M="$(copia_skill_k j)"; muta_lit "$PL" "$M" '; estado terminal replanejamento_execucao_recusado gravado"' \
  '; estado terminal replanejamento_execucao_recusado gravado"; checkpoint() { printf '"'"'checkpoint=ignorado\n'"'"'; }'
mutante_k "km-mutante-10-recusa-sem-checkpoint" $? "$M" k_mistura k_sem_worktree
# A repeticao reavalia em vez de reconhecer o terminal (motivo trocado por `estado`).
M="$(copia_skill_k k)"; muta_lit "$PL" "$M" '  if [ "$P_ESTADO" = replanejamento_execucao_recusado ]; then' '  if false; then'
mutante_k "km-mutante-11-repeticao-reavalia" $? "$M" k_mistura k_sem_worktree
# A repeticao registra o evento de novo.
M="$(copia_skill_k l)"; muta_lit "$PL" "$M" '    falha "$E_TRANSICAO" "replanejamento da execucao ja recusado' \
  '    evento replanejamento_execucao_recusado f6 - bloqueado "$P_RECUSA: repetido"; falha "$E_TRANSICAO" "replanejamento da execucao ja recusado'
mutante_k "km-mutante-12-repeticao-duplica-evento" $? "$M" k_mistura k_sem_orcamento
# Erro de contrato gravado como recusa.
M="$(copia_skill_k m)"; muta_lit "$PL" "$M" '    evento replanejamento_execucao_recusado f6 - bloqueado "$motivo: abertos [$outros]; estado $P_ESTADO mantido"' \
  '    E_FONTE=planejamento; recusa_duravel classes_mistas "$outros"'
mutante_k "km-mutante-13-contrato-vira-recusa-gravada" $? "$M" k_lacuna k_legado_bloqueio
M="$(copia_skill_k n)"; muta_lit "$PL" "$M" '    evento replanejamento_execucao_recusado f6 - bloqueado "fronteira insegura: produto sujo na arvore:$sujos"' \
  '    recusa_duravel classes_mistas "$sujos"'
mutante_k "km-mutante-14-fronteira-vira-recusa-gravada" $? "$M" k_fronteira
# Sem 00-PLANEJAMENTO.md, a recusa inventa o teto da F6 do BuildX.
M="$(copia_skill_k o)"; muta_lit "$PL" "$M" '    migra_legado null null null replanejamento_execucao_recusado "$motivo"' \
  '    migra_legado 3 buildx 1 replanejamento_execucao_recusado orcamento_f6_nao_declarado'
mutante_k "km-mutante-15-legado-inventa-orcamento-na-recusa" $? "$M" k_planejamento_legado
# Registro invalido lido so dentro do subshell: vira "nenhum bloqueio aberto" em vez de contrato.
M="$(copia_skill_k p)"; muta_lit "$PL" "$M" '  le_bloqueios || falha "$E_CONTRATO" "00-BLOQUEIOS.md invalido"' '  :'
mutante_k "km-mutante-16-registro-invalido-vira-sem-bloqueio" $? "$M" k_registro_invalido

echo "== L. escopo unitario bloqueia arquivo de task irma (P0.2-C2) =="
existe "l0-hook-existe" "$H/sprintx/escopo-da-task.sh"
bash -n "$H/sprintx/escopo-da-task.sh"; afirma "l0-hook-sintaxe" $? "bash -n"
bash -n "$H/comum/rastro.sh"; afirma "l0-rastro-sintaxe" $? "bash -n"

C2="$(mktemp -d)"
git -C "$C2" init -q -b main; git -C "$C2" config user.email t@t.local; git -C "$C2" config user.name teste
git -C "$C2" -c commit.gpgsign=false commit -q -m init --allow-empty
C2OC="$C2/docs/sprintx/features/c2-escopo-irma"
mkdir -p "$C2OC/sprint-03" "$C2OC/sprint-04" "$C2/tests/ui" "$C2/src/ui" "$C2/src/menu" "$C2/src/shared" "$C2/src/random"
C2RASTRO="$C2/docs/eventos/c2-escopo-irma.jsonl"; mkdir -p "$(dirname "$C2RASTRO")"

c2_evento() { # c2_evento <evento> <task> <sessao>
  python3 -c "
import sys, datetime
evento, task, sessao = sys.argv[1:4]
extras = ',\"sessao\":\"%s\",\"harness\":\"%s\"' % (sessao, sessao.split('@')[0])
linha = ('{\"ts\":\"%s\",\"expx_eventos\":1,\"trabalho_id\":\"c2-escopo-irma\",'
         '\"ferramenta\":\"sprintx\",\"origem\":\"skill\",\"evento\":\"%s\",\"fase\":\"f6\",'
         '\"task\":\"%s\",\"agente\":\"principal\",\"resultado\":\"ok\",\"detalhe\":null,'
         '\"arquivos\":[]%s}') % (datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'), evento, task, extras)
open(sys.argv[4], 'a').write(linha + '\n')
" "$1" "$2" "$3" "$C2RASTRO"
}
c2_tarefa() { # c2_tarefa <arquivo> <id> <status> <cria> <altera> [depende]
  printf '  - id: %s\n    titulo: Task %s original\n    status: %s\n    objetivo: obj\n    arquivos:\n      cria: [%s]\n      altera: [%s]\n    teste_integracao: t\n    teste_funcional: t\n    criterio_aceite: c\n    depende_de: [%s]\n    paralelizavel: false\n    concluida_em: null\n    suite: nao_executada\n' \
    "$2" "$2" "$3" "$4" "$5" "${6:-}" >> "$1"
}
c2_abre() { printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: tasks\ntrabalho_id: c2-escopo-irma\nsprint_id: sprint-%s\ntasks:\n' "$1" > "$2"; }
c2_fecha() { printf -- '---\n' >> "$1"; }
c2_w() { printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$C2" "$C2/$1"; }
C2_SAIDA=""
c2_hook() { # c2_hook <hook> <arquivo-relativo> <sessao> — exit code proprio; saida fica em C2_SAIDA
  C2_SAIDA=$(printf '%s' "$(c2_w "$2")" | (cd "$C2" && EXPX_SESSAO="$3" bash "$1") 2>&1)
}

# Reset completo e deterministico: T-03.01 concluida cria o par tsx+test;
# T-04.03 em_andamento (minha sessao) altera so o tsx. Cada caso parte daqui
# e aplica so o desvio que precisa — nenhum caso depende do anterior.
l_fixture() {
  c2_abre 03 "$C2OC/sprint-03/tasks.md"
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.01 concluida "src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx" ""
  c2_fecha "$C2OC/sprint-03/tasks.md"
  c2_abre 04 "$C2OC/sprint-04/tasks.md"
  c2_tarefa "$C2OC/sprint-04/tasks.md" T-04.03 em_andamento "" "src/ui/cabecalho-topo.tsx"
  c2_fecha "$C2OC/sprint-04/tasks.md"
  rm -rf "$C2OC/sprint-02"; rm -f "$C2/.expx/hooks.json"
  : > "$C2RASTRO"
  c2_evento task_iniciada T-04.03 "teste@eu"
}
l_a() { l_fixture; c2_hook "$1" "src/ui/cabecalho-topo.tsx" teste@eu; [ $? -eq 0 ]; }
l_b() {
  l_fixture
  c2_abre 04 "$C2OC/sprint-04/tasks.md"
  c2_tarefa "$C2OC/sprint-04/tasks.md" T-04.03 em_andamento "" "src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx"
  c2_fecha "$C2OC/sprint-04/tasks.md"
  c2_hook "$1" "tests/ui/cabecalho-topo.test.tsx" teste@eu; [ $? -eq 0 ]
}
l_c() {
  l_fixture
  c2_hook "$1" "tests/ui/cabecalho-topo.test.tsx" teste@eu
  [ $? -eq 2 ] && printf '%s' "$C2_SAIDA" | grep -qF "arquivo_de_task_irma" \
    && printf '%s' "$C2_SAIDA" | grep -qF "T-04.03" && printf '%s' "$C2_SAIDA" | grep -qF "T-03.01"
}
l_d() {
  l_fixture
  c2_abre 03 "$C2OC/sprint-03/tasks.md"
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.01 concluida "src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx" ""
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.02 concluida "" "src/shared/util.ts"
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.05 pendente "" "src/shared/util.ts"
  c2_fecha "$C2OC/sprint-03/tasks.md"
  c2_hook "$1" "src/shared/util.ts" teste@eu
  [ $? -eq 2 ] && printf '%s' "$C2_SAIDA" | grep -qF "T-03.02" && printf '%s' "$C2_SAIDA" | grep -qF "T-03.05"
}
l_e() {
  l_fixture
  c2_hook "$1" "src/random/nope.ts" teste@eu
  [ $? -eq 0 ] && ! printf '%s' "$C2_SAIDA" | grep -qF "defeito_de_plano"
}
l_f() {
  l_fixture
  c2_abre 03 "$C2OC/sprint-03/tasks.md"
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.01 concluida "src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx" ""
  sed -i 's/Task T-03.01 original/Cabecalho novo — reescrita total do topo/' "$C2OC/sprint-03/tasks.md"
  c2_fecha "$C2OC/sprint-03/tasks.md"
  c2_hook "$1" "tests/ui/cabecalho-topo.test.tsx" teste@eu; [ $? -eq 2 ]
}
l_g() {
  l_fixture
  c2_abre 03 "$C2OC/sprint-03/tasks.md"
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.05 pendente "" "src/shared/util.ts"
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.01 concluida "src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx" ""
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.02 concluida "" "src/shared/util.ts"
  c2_fecha "$C2OC/sprint-03/tasks.md"
  c2_hook "$1" "tests/ui/cabecalho-topo.test.tsx" teste@eu; [ $? -eq 2 ]
}
l_h() {
  l_fixture
  mkdir -p "$C2OC/sprint-02"
  c2_abre 02 "$C2OC/sprint-02/tasks.md"
  c2_tarefa "$C2OC/sprint-02/tasks.md" T-02.09 em_andamento "" "src/outro/coisa.ts"
  c2_fecha "$C2OC/sprint-02/tasks.md"
  c2_evento task_iniciada T-02.09 "outra@sessao"
  c2_hook "$1" "src/ui/cabecalho-topo.tsx" teste@eu; [ $? -eq 0 ]
}
l_i0() {
  l_fixture
  : > "$C2RASTRO"
  c2_hook "$1" "src/ui/cabecalho-topo.tsx" teste@eu
  [ $? -eq 2 ] && ! printf '%s' "$C2_SAIDA" | grep -qF "arquivo_de_task_irma"
}
l_i1() {
  l_fixture
  c2_abre 04 "$C2OC/sprint-04/tasks.md"
  c2_tarefa "$C2OC/sprint-04/tasks.md" T-04.03 em_andamento "" "src/ui/cabecalho-topo.tsx"
  c2_tarefa "$C2OC/sprint-04/tasks.md" T-04.05 em_andamento "" "src/menu/outra.ts"
  c2_fecha "$C2OC/sprint-04/tasks.md"
  c2_evento task_iniciada T-04.05 "teste@eu"
  c2_hook "$1" "src/ui/cabecalho-topo.tsx" teste@eu; [ $? -eq 2 ]
}
l_j() {
  l_fixture
  c2_abre 04 "$C2OC/sprint-04/tasks.md"
  c2_tarefa "$C2OC/sprint-04/tasks.md" T-04.03 bloqueada "" "src/ui/cabecalho-topo.tsx"
  c2_fecha "$C2OC/sprint-04/tasks.md"
  c2_hook "$1" "tests/ui/cabecalho-topo.test.tsx" teste@eu; [ $? -eq 0 ]
}
l_modo_aviso() {
  l_fixture
  mkdir -p "$C2/.expx"; echo '{"hooks":{"escopo-da-task":{"modo":"aviso"}}}' > "$C2/.expx/hooks.json"
  c2_hook "$1" "tests/ui/cabecalho-topo.test.tsx" teste@eu; [ $? -eq 2 ]
}
l_modo_desligado() {
  l_fixture
  mkdir -p "$C2/.expx"; echo '{"hooks":{"escopo-da-task":{"modo":"desligado"}}}' > "$C2/.expx/hooks.json"
  c2_hook "$1" "tests/ui/cabecalho-topo.test.tsx" teste@eu; [ $? -eq 0 ]
}

for par in l_a:la-arquivo-so-da-corrente-permitido l_b:lb-arquivo-corrente-e-irma-permitido \
  l_c:lc-arquivo-so-da-irma-bloqueado l_d:ld-arquivo-de-duas-irmas-bloqueado \
  l_e:le-arquivo-de-nenhuma-permitido-sem-defeito_de_plano l_f:lf-titulo-mudou-mesmo-resultado \
  l_g:lg-ordem-mudou-mesmo-resultado l_h:lh-sessao-acha-a-propria-task-nao-a-primeira \
  l_i0:li0-zero-correspondencias-fail-closed l_i1:li1-duas-correspondencias-fail-closed \
  l_j:lj-task-bloqueada-nao-repete-bloqueio l_modo_aviso:lmodo-irma-bloqueia-mesmo-em-aviso \
  l_modo_desligado:lmodo-desligado-desativa-tudo; do
  "${par%%:*}" "$H/sprintx/escopo-da-task.sh"; afirma "${par#*:}" $? "${par%%:*}"
done

# L-K. Ciclo real: irma -> bloqueio -> B-01 -> replanejamento -> plano ganha o
# arquivo -> aprovacao -> T-03.01 continua congelada -> edicao permitida.
grava_evento_menu() { # grava_evento_menu <dir> <evento> <task> <sessao>
  local arq="$1/docs/eventos/menu.jsonl"; mkdir -p "$(dirname "$arq")"
  python3 -c "
import sys, datetime
evento, task, sessao = sys.argv[1:4]
extras = ',\"sessao\":\"%s\",\"harness\":\"%s\"' % (sessao, sessao.split('@')[0])
linha = ('{\"ts\":\"%s\",\"expx_eventos\":1,\"trabalho_id\":\"menu\",'
         '\"ferramenta\":\"sprintx\",\"origem\":\"skill\",\"evento\":\"%s\",\"fase\":\"f6\",'
         '\"task\":\"%s\",\"agente\":\"principal\",\"resultado\":\"ok\",\"detalhe\":null,'
         '\"arquivos\":[]%s}') % (datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'), evento, task, extras)
open(sys.argv[4], 'a').write(linha + '\n')
" "$2" "$3" "$4" "$arq"
}
roda_hook_menu() { # roda_hook_menu <dir> <hook> <arquivo-relativo> <sessao>
  printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$1" "$1/$3" | (cd "$1" && EXPX_SESSAO="$4" bash "$2") 2>&1
}
l_k() { # ciclo real completo — hook = $1
  local d f c0 saida1 rc1 out saida2 rc2 c1
  d="$K/c2ciclo.$$.$RANDOM"; mkdir -p "$d"
  k_fx "$d" 0 3 buildx 1 || return 1
  f="$(kf "$d")"; c0="$(cat "$f/sprint-03/tasks.md")"
  k_plano "$d" c em_andamento
  grava_evento_menu "$d" task_iniciada T-04.03 "teste@eu"
  saida1="$(roda_hook_menu "$d" "$1" tests/ui/cabecalho-topo.test.tsx teste@eu)"; rc1=$?
  [ "$rc1" -eq 2 ] && printf '%s' "$saida1" | grep -qF "arquivo_de_task_irma" || return 1
  kbl "$PL" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo_de_task_irma: tests/ui/cabecalho-topo.test.tsx pertence a T-03.01' 'ampliar ownership de T-04.03' >/dev/null || return 1
  k_plano "$d" c bloqueada
  out="$(kpl "$PL" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = iniciado ] || return 1
  k_plano "$d" c bloqueada 'src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx'
  kpl "$PL" "$d" avanca menu f3 >/dev/null && kpl "$PL" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 4 SIM
  out="$(kpl "$PL" "$d" avanca menu f5)" || return 1
  [ "$(kv "$out" estado)" = aprovado ] && [ "$(kst "$d" T-04.03)" = pendente ] || return 1
  k_plano "$d" c em_andamento 'src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx'
  grava_evento_menu "$d" task_iniciada T-04.03 "teste@eu"
  saida2="$(roda_hook_menu "$d" "$1" tests/ui/cabecalho-topo.test.tsx teste@eu)"; rc2=$?
  [ "$rc2" -eq 0 ] || return 1
  c1="$(cat "$f/sprint-03/tasks.md")"
  [ "$c0" = "$c1" ]
}
l_k "$H/sprintx/escopo-da-task.sh"; afirma "lk-ciclo-real-irma-bloqueio-replanejamento-permitido" $? "irma -> B-01 -> replanejar-execucao -> aprovado -> permitido, T-03.01 congelada"

# Mutantes minimos do C2. Copia do hook preserva sprintx/+comum/ irmaos (o
# hook faz `source ../comum/rastro.sh`); cada mutante tem de morrer pelo caso
# designado, e a copia sem mutacao tem de sobreviver a todos.
LM="$K/c2mut"; mkdir -p "$LM/sprintx" "$LM/comum"
cp "$H/comum/rastro.sh" "$LM/comum/rastro.sh"
cp "$H/sprintx/escopo-da-task.sh" "$LM/sprintx/controle.sh"
l_mutante() { # l_mutante <nome> <rc-geracao> <arquivo-mutante> <caso que TEM de matar>...
  local nome="$1" rc="$2" s="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do "$c" "$s" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]; afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
vivosl=""
for c in l_a l_b l_c l_d l_e l_f l_g l_h l_i0 l_i1 l_j l_modo_aviso l_modo_desligado; do
  "$c" "$LM/sprintx/controle.sh" || vivosl="$vivosl$c "
done
l_k "$LM/sprintx/controle.sh" || vivosl="${vivosl}l_k "
[ -z "$vivosl" ]; afirma "lm-controle-copia-intacta-sobrevive" $? "${vivosl:-nenhum caso designado reprova a copia sem mutacao}"

# Os literais seguem a reescrita de custo do hook (DS-157); a intencao de cada mutante e a de sempre.
muta_lit "$H/sprintx/escopo-da-task.sh" "$LM/sprintx/m1.sh" \
  'if [ "$DECL" = irma ]; then' 'if [ "$DECL" = irma ] && false; then'
l_mutante "lm-mutante-1-uniao-vence-escopo-unitario" $? "$LM/sprintx/m1.sh" l_c l_d

muta_lit "$H/sprintx/escopo-da-task.sh" "$LM/sprintx/m2.sh" \
  'rastro_bloqueia "$MSG_IRMA"' 'rastro_aviso_ao_modelo PreToolUse "$MSG_IRMA"'
l_mutante "lm-mutante-2-arquivo-de-irma-vira-so-aviso" $? "$LM/sprintx/m2.sh" l_c

muta_lit "$H/sprintx/escopo-da-task.sh" "$LM/sprintx/m3.sh" \
  'rastro_aviso_ao_modelo PreToolUse "$MSG"' 'rastro_bloqueia "$MSG"'
l_mutante "lm-mutante-3-arquivo-de-nenhuma-vira-defeito_de_plano" $? "$LM/sprintx/m3.sh" l_e

muta_lit "$H/sprintx/escopo-da-task.sh" "$LM/sprintx/m4.sh" \
  '    if (corrente) { print "D corrente"; exit }' '    if (corrente && 0) { print "D corrente"; exit }'
l_mutante "lm-mutante-4-atual-mais-irma-bloqueado-incorretamente" $? "$LM/sprintx/m4.sh" l_b
l_mutante "lm-mutante-7-depois-do-replanejamento-ainda-bloqueia" $? "$LM/sprintx/m4.sh" l_k

# Este mutante mora no helper, nao no hook: sem o filtro de sessao, o par
# TRABALHO+TASK volta a ser "o primeiro que o rastro mostrar". Copia propria de
# sprintx/+comum/, para nao contaminar os outros mutantes.
LM5="$K/c2mut5"; mkdir -p "$LM5/sprintx" "$LM5/comum"
cp "$H/sprintx/escopo-da-task.sh" "$LM5/sprintx/m5.sh"
muta_lit "$H/comum/rastro.sh" "$LM5/comum/rastro.sh" \
  'if (_rv_dono[k] == "" || _rv_dono[k] != ses) continue' 'if (_rv_dono[k] == "") continue'
l_mutante "lm-mutante-5-seleciona-a-primeira-nao-a-da-sessao" $? "$LM5/sprintx/m5.sh" l_h

muta_lit "$H/sprintx/escopo-da-task.sh" "$LM/sprintx/m6.sh" \
  '  PORT && index($0, "status: em_andamento") { G = 1 }' \
  '  PORT && (index($0, "status: em_andamento") || index($0, "status: bloqueada")) { G = 1 }'
l_mutante "lm-mutante-6-depois-do-bloqueio-continua-abrindo-task" $? "$LM/sprintx/m6.sh" l_j

muta_lit "$H/sprintx/escopo-da-task.sh" "$LM/sprintx/m8.sh" \
  '[ "$G" = 1 ] || exit 0' '[ "$G" = 1 ] || true'
l_mutante "lm-mutante-8-cria-b-nn-duplicado-numa-repeticao" $? "$LM/sprintx/m8.sh" l_j

# Decisao registrada e hook documentado como excecao normativa mesmo em aviso.
DSF2="$SK/DECISOES-DA-SKILL.md"
[ "$(grep -c '^| DS-149 |' "$DSF2")" -eq 1 ] && [ "$(grep -c '^| DS-150 |' "$DSF2")" -eq 1 ] \
  && tem "$DSF2" 'arquivo_de_task_irma' && tem "$DSF2" 'rastro_sessao_dona'
afirma "l24-ds149-ds150-registradas" $? "DECISOES-DA-SKILL.md"
tem "$SKILLMD" 'arquivo_de_task_irma' && tem "$SKILLMD" 'bloqueia sempre, mesmo em modo'
afirma "l25-skillmd-documenta-excecao" $? "tabela de hooks"

rm -rf "$K"

echo "== M. portabilidade Git Bash: scripts e contratos markdown LF, caminho devolvido pelo Git (P0.2-C7-B S1) =="
# Dois modos. Simulado: `git` e `cygpath` falsos no PATH fazem o Git devolver `Z:/...` e o
# cygpath traduzir, em qualquer SO — e o que mata os mutantes tanto em Linux quanto no Git
# Bash. Real: sem falsos; no Git Bash o Git for Windows devolve `C:/...` de verdade.
MS="$(mktemp -d)"
RAIZ_SRC="$(cd "$H/../.." && pwd)"
MSIM="$MS/sim"; MBIN="$MS/bin"; mkdir -p "$MSIM/z" "$MBIN" "$MS/vazio" "$MS/real"
REALGIT="$(command -v git)"; BASHBIN="$(command -v bash)"
cat > "$MBIN/cygpath" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$M_CYGLOG"
[ "$1" = -u ] || exit 64; shift; [ "$1" = -- ] && shift
[ $# -eq 1 ] || exit 64
case "$1" in
  [A-Za-z]:/*) printf '%s/%s/%s\n' "$M_SIMT" "$(printf '%s' "${1%%:*}" | tr 'A-Z' 'a-z')" "${1#?:/}" ;;
  *) printf '%s\n' "$1" ;;
esac
EOF
cat > "$MBIN/git" <<'EOF'
#!/usr/bin/env bash
if [ "$#" -eq 2 ] && [ "$1" = rev-parse ] && [ "$2" = --show-toplevel ]; then
  t="$("$M_REALGIT" rev-parse --show-toplevel)" || exit $?
  printf 'Z:/%s\n' "${t##*/}"; exit 0
fi
exec "$M_REALGIT" "$@"
EOF
chmod +x "$MBIN/cygpath" "$MBIN/git"
m_sim() { PATH="$MBIN:$PATH" M_SIMT="$MSIM" M_CYGLOG="$MS/cyg.log" M_REALGIT="$REALGIT" "$@"; }
m_real() { "$@"; }
m_cg() { "$BASHBIN" -c '. "$1" && caminho_git "$2"' _ "$@"; }   # m_cg <helper> <entrada>
m_nao_chamou() { [ ! -s "$MS/cyg.log" ]; }
m_sem_drive() { [ -z "$(find "$1" -name '?:*' 2>/dev/null | head -1)" ]; }
m_repo() { # m_repo <dir> — repositorio git real, um commit, com subdiretorio sub/
  rm -rf "$1" "$1--wt"; mkdir -p "$1/sub"
  git -C "$1" init -q -b main && git -C "$1" -c user.email=t@t.local -c user.name=teste -c commit.gpgsign=false commit -q --allow-empty -m init
}

# A–E: o helper, isolado. Cada caso recebe a raiz de uma copia da skill.
m_a() { : > "$MS/cyg.log"; [ "$(m_sim m_cg "$1/scripts/caminho-git.sh" 'C:/repo')" = "$MSIM/c/repo" ]; }
m_b() { : > "$MS/cyg.log"; [ "$(m_sim m_cg "$1/scripts/caminho-git.sh" 'D:/repo com espaço')" = "$MSIM/d/repo com espaço" ]; }
m_c() { : > "$MS/cyg.log"; [ "$(m_sim m_cg "$1/scripts/caminho-git.sh" '/home/user/repo')" = /home/user/repo ] && m_nao_chamou; }
m_d() {
  : > "$MS/cyg.log"
  [ "$(m_sim m_cg "$1/scripts/caminho-git.sh" 'docs/sprintx/features/x')" = docs/sprintx/features/x ] \
    && [ "$(m_sim m_cg "$1/scripts/caminho-git.sh" './rel com espaço')" = './rel com espaço' ] && m_nao_chamou
}
m_e() { # sem cygpath no PATH (Linux/macOS): no-op, inclusive para a forma C:/
  [ "$(PATH="$MS/vazio" m_cg "$1/scripts/caminho-git.sh" 'C:/repo')" = 'C:/repo' ] \
    && [ "$(PATH="$MS/vazio" m_cg "$1/scripts/caminho-git.sh" '/home/user/repo')" = /home/user/repo ]
}

# F–H: os scripts, rodados de um subdiretorio, com o Git devolvendo drive Windows.
m_f() { # m_f <m_sim|m_real> <skill> <base>
  local r="$3/repo com espaço"
  m_repo "$r" >/dev/null 2>&1 || return 1
  (cd "$r/sub" && "$1" bash "$2/scripts/planejamento.sh" criar s1-demo >/dev/null 2>&1) || return 1
  [ -f "$r/docs/sprintx/features/s1-demo/00-PLANEJAMENTO.md" ] && [ ! -e "$r/sub/docs" ] && m_sem_drive "$3"
}
m_g() {
  local r="$3/repo bloq" b="$2/scripts/bloqueios.sh" out
  m_repo "$r" >/dev/null 2>&1 || return 1
  (cd "$r/sub" && "$1" bash "$b" registrar s1-demo null lacuna_de_decisao 'duvida nova' 'decisao registrada' >/dev/null 2>&1) || return 1
  out="$(cd "$r/sub" && "$1" bash "$b" listar s1-demo 2>/dev/null)" || return 1
  printf '%s\n' "$out" | grep -q '^B-01	.*	lacuna_de_decisao	aberto$' || return 1
  (cd "$r/sub" && "$1" bash "$b" validar s1-demo >/dev/null 2>&1) || return 1
  (cd "$r/sub" && "$1" bash "$b" resolver s1-demo B-01 >/dev/null 2>&1) || return 1
  out="$(cd "$r/sub" && "$1" bash "$b" listar s1-demo 2>/dev/null)" || return 1
  printf '%s\n' "$out" | grep -q '^B-01	.*	resolvido$' \
    && [ -f "$r/docs/sprintx/features/s1-demo/00-BLOQUEIOS.md" ] && [ ! -e "$r/sub/docs" ] && m_sem_drive "$3"
}
m_h() { # worktree vinculada: .git e arquivo, o Git devolve a raiz do worktree
  local r="$3/repo wt" wt="$3/repo wt--wt"
  m_repo "$r" >/dev/null 2>&1 && git -C "$r" worktree add -q -b wt "$wt" main >/dev/null 2>&1 && mkdir -p "$wt/sub" || return 1
  [ -f "$wt/.git" ] || return 1
  (cd "$wt/sub" && "$1" bash "$2/scripts/planejamento.sh" criar s1-wt >/dev/null 2>&1) || return 1
  (cd "$wt/sub" && "$1" bash "$2/scripts/bloqueios.sh" registrar s1-wt null lacuna_de_decisao 'd' 'x' >/dev/null 2>&1) || return 1
  [ -f "$wt/docs/sprintx/features/s1-wt/00-PLANEJAMENTO.md" ] && [ -f "$wt/docs/sprintx/features/s1-wt/00-BLOQUEIOS.md" ] \
    && [ ! -e "$wt/sub/docs" ] && [ ! -e "$r/docs" ] && m_sem_drive "$3"
}
m_f_sim() { m_f m_sim "$1" "$MSIM/z"; }
m_g_sim() { m_g m_sim "$1" "$MSIM/z"; }
m_h_sim() { m_h m_sim "$1" "$MSIM/z"; }

m_a "$SK"; afirma "ma-sim-c-vira-posix" $? "C:/repo -> cygpath -u"
m_b "$SK"; afirma "mb-sim-d-com-espaco" $? "D:/repo com espaço, argumento unico"
m_c "$SK"; afirma "mc-sim-posix-intacto-sem-cygpath" $? "/home/user/repo nao chega ao cygpath"
m_d "$SK"; afirma "md-sim-relativo-intacto-sem-cygpath" $? "relativo nao chega ao cygpath"
m_e "$SK"; afirma "me-sem-cygpath-no-op" $? "Linux/macOS: nada muda"
m_f_sim "$SK"; afirma "mf-sim-planejamento-criar-na-raiz" $? "Z:/... normalizado, nada criado como Z:"
m_g_sim "$SK"; afirma "mg-sim-bloqueios-registrar-listar-validar-resolver" $? "na raiz, do subdiretorio"
m_h_sim "$SK"; afirma "mh-sim-worktree-vinculada" $? "raiz do worktree, nao a do principal"
if command -v cygpath >/dev/null 2>&1; then
  [ "$(m_cg "$SK/scripts/caminho-git.sh" 'C:/repo')" = /c/repo ]; afirma "ma-real-gitbash-c" $? "cygpath real"
  [ "$(m_cg "$SK/scripts/caminho-git.sh" 'D:/repo com espaço')" = '/d/repo com espaço' ]; afirma "mb-real-gitbash-d-com-espaco" $? "cygpath real"
  m_repo "$MS/real/sonda" >/dev/null 2>&1
  case "$(git -C "$MS/real/sonda" rev-parse --show-toplevel)" in [A-Za-z]:/*) true ;; *) false ;; esac
  afirma "m-real-gitbash-git-devolve-drive" $? "o Git for Windows devolve C:/..., a condicao do bug existe"
else
  m_e "$SK"; afirma "me-real-linux-sem-cygpath" $? "ambiente sem cygpath"
fi
m_f m_real "$SK" "$MS/real"; afirma "mf-real-planejamento-criar" $? "git real do ambiente"
m_g m_real "$SK" "$MS/real"; afirma "mg-real-bloqueios" $? "git real do ambiente"
m_h m_real "$SK" "$MS/real"; afirma "mh-real-worktree" $? "git real do ambiente"
for f in planejamento.sh bloqueios.sh; do
  [ "$(grep -c 'caminho_git "$t"' "$SK/scripts/$f")" -eq 1 ] || false
done; afirma "m-uma-regra-dois-consumidores" $? "planejamento.sh e bloqueios.sh usam o helper"
[ "$(find "$SK/scripts" "$H" -name '*.sh' -not -path '*/testes/*' -exec grep -l 'cygpath' {} + | sed 's|.*/||' | sort -u)" = caminho-git.sh ]
afirma "m-cygpath-so-no-helper" $? "nenhuma copia da regra fora de caminho-git.sh"

# J–L: clone limpo com core.autocrlf=true, sem depender de configuracao global/sistema.
mgit() { GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$MS/gitconfig-vazio" git "$@"; }
: > "$MS/gitconfig-vazio"
MSRC_SH="$(git -C "$RAIZ_SRC" ls-files -co --exclude-standard -- '*.sh')"
# Os .md sao contrato lido mecanicamente (sed/grep ancorados em $): CRLF quebra a leitura no Linux.
MSRC_MD="$(git -C "$RAIZ_SRC" ls-files -co --exclude-standard -- '*.md')"
MSRC_TXT="$MSRC_SH
$MSRC_MD"
m_fixture() { # m_fixture <gitattributes|-> <destino> — origem com os .sh e .md do trabalho (blobs LF), clonada com autocrlf=true
  local o="$2.origem" f
  rm -rf "$o" "$2"; mkdir -p "$o"
  mgit init -q -b main "$o" || return 1
  [ "$1" = - ] || cp "$1" "$o/.gitattributes"
  for f in $MSRC_TXT; do mkdir -p "$o/$(dirname "$f")"; tr -d '\r' < "$RAIZ_SRC/$f" > "$o/$f"; done
  mgit -C "$o" -c core.autocrlf=false add -A \
    && mgit -C "$o" -c core.autocrlf=false -c user.email=t@t.local -c user.name=teste -c commit.gpgsign=false commit -q -m fx \
    && mgit clone -q -c core.autocrlf=true "$o" "$2" && [ "$(mgit -C "$2" config core.autocrlf)" = true ]
}
m_eol_indice() { # m_eol_indice <clone> [<glob> <lista>] — indice LF, worktree LF, atributo text eol=lf — e todos presentes
  local l g="${2:-*.sh}" n="${3-$MSRC_SH}"; l="$(git -C "$1" ls-files --eol -- "$g")"; [ -n "$l" ] || return 1
  printf '%s\n' "$l" | awk '!/^i\/lf +w\/lf +attr\/text eol=lf[ \t]/ { r = 1 } END { exit r }' || return 1
  [ "$(printf '%s\n' "$l" | wc -l)" -eq "$(printf '%s\n' $n | wc -l)" ]
}
m_eol_md() { m_eol_indice "$1" '*.md' "$MSRC_MD"; }
# Por bytes, nunca por grep/$(...): no Git Bash os dois descartam o CR e o scan ficaria cego.
m_eol_bytes() { # m_eol_bytes <clone> [<lista>] — scan de bytes: nenhum CR em nenhum .sh (ou da lista)
  local f; for f in ${2-$MSRC_SH}; do [ -f "$1/$f" ] && [ "$(tr -d '\r' < "$1/$f" | wc -c)" -eq "$(wc -c < "$1/$f")" ] || return 1; done
}
m_hex() { od -An -tx1 | tr -d ' \n'; }
SHEBANG_HEX="$(printf '#!/usr/bin/env bash\n' | m_hex)"
m_shebang() { local f; for f in $MSRC_SH; do [ "$(head -c 20 "$1/$f" | m_hex)" = "$SHEBANG_HEX" ] || return 1; done; }
m_eol_bytes_md() { m_eol_bytes "$1" "$MSRC_MD"; }
# O teste real (21-regras-inviolaveis) lendo o SKILL.md do clone.
M_SKILL=.claude/skills/sprintx/SKILL.md
m_skill_legivel() { [ -f "$1/$M_SKILL" ] && [ "$(conta_regras "$1/$M_SKILL")" -eq 21 ]; }
# O `sed` do Git Bash ignora o CR antes do `$` e conta 21 num SKILL.md CRLF;
# o do GNU/Linux nao. Isso e propriedade do LEITOR desta maquina, nao do dano:
# um oraculo que dependa dele fica cego em metade das plataformas, e foi por
# isso que este caso vivia com `skip` no Git Bash. O que prova o dano em
# qualquer plataforma e a MATERIALIZACAO do arquivo que o consumidor recebe —
# indice, arvore, atributo e bytes —, e e ela que passa a ser o oraculo.
m_skill_materializa_lf() { m_eol_indice "$1" "$M_SKILL" "$M_SKILL" && m_eol_bytes "$1" "$M_SKILL"; }
# Medido, nunca suposto nem deduzido de `cygpath`: o sed desta maquina tolera CR?
m_sed_tolera_cr() { [ -n "$(printf 'x\r\n' | sed -n '/^x$/p')" ]; }
# O oraculo do mutante 11. Clausula 1 — a materializacao — vale em qualquer
# plataforma e sozinha ja mata o mutante. Clausula 2 — o leitor real do
# contrato — entra onde o leitor sente o CR, como reforco: nunca substitui a
# primeira, e a ausencia dela nunca vira skip.
m_mutante11_morre() { # m_mutante11_morre <clone>
  ! m_skill_materializa_lf "$1" || return 1
  if ! m_sed_tolera_cr; then ! m_skill_legivel "$1" || return 1; fi
  return 0
}
M11_EXTRA=""; m_sed_tolera_cr || M11_EXTRA=" + o leitor real do contrato conta != 21"
m_reprova() { ! m_eol_indice "$1" && ! m_eol_bytes "$1" && ! m_shebang "$1" && ! m_eol_md "$1" && ! m_eol_bytes_md "$1" && ! m_skill_materializa_lf "$1"; }

[ "$(grep -v '^[[:space:]]*\(#\|$\)' "$RAIZ_SRC/.gitattributes" 2>/dev/null)" = '*.sh text eol=lf
*.md text eol=lf' ]
afirma "m-gitattributes-regra-minima" $? "so *.sh e *.md text eol=lf"
git -C "$RAIZ_SRC" ls-files --eol -- '*.sh' '*.md' | awk '!/^i\/lf +w\/[a-z]+ +attr\/text eol=lf[ \t]/ { r = 1 } END { exit r }'
afirma "m-repo-blobs-lf-com-atributo" $? "indice LF e atributo em todo .sh e .md versionado"
m_fixture "$RAIZ_SRC/.gitattributes" "$MS/clone-ok" >/dev/null 2>&1; afirma "mj-clone-autocrlf-true" $? "clone limpo"
m_eol_indice "$MS/clone-ok"; afirma "mj-ls-files-eol-todos-lf" $? "i/lf w/lf attr/text eol=lf"
m_eol_bytes "$MS/clone-ok"; afirma "mj-scan-bytes-sem-crlf" $? "nenhum CR"
m_shebang "$MS/clone-ok"; afirma "ml-shebang-preservado" $? "#!/usr/bin/env bash, sem CR"
m_eol_md "$MS/clone-ok"; afirma "mj-md-ls-files-eol-todos-lf" $? "todo .md: i/lf w/lf attr/text eol=lf"
m_eol_bytes_md "$MS/clone-ok"; afirma "mj-md-scan-bytes-sem-crlf" $? "nenhum CR em .md"
m_skill_legivel "$MS/clone-ok"; afirma "mj-skill-md-legivel-pelo-teste-real" $? "conta_regras do SKILL.md do clone = 21"
m_skill_materializa_lf "$MS/clone-ok"; afirma "mj-skill-md-materializa-lf" $? "SKILL.md: i/lf w/lf attr/text eol=lf e sem CR"
m_fixture - "$MS/clone-sem" >/dev/null 2>&1 && m_reprova "$MS/clone-sem"
afirma "mk-sem-gitattributes-prova-morre" $? "cada verificacao reprova o clone sem atributo"
printf '*.sh text\n' > "$MS/attr-text"; m_fixture "$MS/attr-text" "$MS/clone-text" >/dev/null 2>&1 && m_reprova "$MS/clone-text"
afirma "mm-mutante-2a-regra-sem-eol-morre" $? "*.sh text"
printf '* text=auto\n' > "$MS/attr-auto"; m_fixture "$MS/attr-auto" "$MS/clone-auto" >/dev/null 2>&1 && m_reprova "$MS/clone-auto"
afirma "mm-mutante-2b-text-auto-morre" $? "* text=auto"
# Mutante 11: a regra *.md some. Os .sh seguem LF; os .md saem CRLF e o teste real le o SKILL.md errado no Linux.
printf '*.sh text eol=lf\n' > "$MS/attr-sem-md"; m_fixture "$MS/attr-sem-md" "$MS/clone-sem-md" >/dev/null 2>&1 \
  && m_eol_indice "$MS/clone-sem-md" && ! m_eol_md "$MS/clone-sem-md" && ! m_eol_bytes_md "$MS/clone-sem-md" \
  && ! m_skill_materializa_lf "$MS/clone-sem-md"
afirma "mm-mutante-11-sem-regra-md-morre" $? "*.md sem eol=lf: indice/worktree, bytes e o SKILL.md do consumidor reprovam"
# O mesmo mutante, agora pelo oraculo do consumidor — sem `skip` em plataforma
# nenhuma: onde o sed tolera CR, a materializacao mata sozinha; onde nao
# tolera, a leitura real do contrato entra junto.
m_mutante11_morre "$MS/clone-sem-md"
afirma "mm-mutante-11-skill-md-nao-chega-lf" $? "a materializacao do SKILL.md reprova em qualquer plataforma$M11_EXTRA"
! m_mutante11_morre "$MS/clone-ok"
afirma "mm-controle-11-clone-com-a-regra-passa" $? "o clone com *.md text eol=lf nao e reprovado pelo oraculo"

# Mutante 10: o proprio teste passa a aceitar CRLF. Cada verificacao mutada, rodada contra o
# clone sem atributo, ACEITA — e isso que a afirmacao mk ja reprovaria.
m_muta_fn() { # m_muta_fn <funcao> <nova> <trecho> <troca>
  declare -f "$1" | sed "1s/^$1 /$2 /" > "$MS/fn.orig" && muta_lit "$MS/fn.orig" "$MS/fn.mut" "$3" "$4" && . "$MS/fn.mut"
}
m_muta_fn m_eol_indice m10a 'w\/lf +attr\/text eol=lf[ \t]' 'w\/[a-z]+ +attr\/[a-z =]*[ \t]' && m10a "$MS/clone-sem"
afirma "mm-mutante-10a-indice-aceita-crlf-morre" $? "a verificacao mutada aceitaria o clone CRLF"
m_muta_fn m_eol_bytes m10b "tr -d '\\r'" "tr -d '\\001'" && m10b "$MS/clone-sem"
afirma "mm-mutante-10b-scan-aceita-crlf-morre" $? "a verificacao mutada aceitaria o clone CRLF"
m_muta_fn m_shebang m10c 'head -c 20 "$1/$f"' 'head -n 1 "$1/$f" | tr -d "\r" | head -c 20' && m10c "$MS/clone-sem"
afirma "mm-mutante-10c-shebang-aceita-crlf-morre" $? "a verificacao mutada aceitaria o clone CRLF"
# 11a: o oraculo deixa de exigir a materializacao e passa a achar o clone CRLF verde.
m_muta_fn m_skill_materializa_lf m11a 'm_eol_indice "$1" "$M_SKILL" "$M_SKILL" && m_eol_bytes "$1" "$M_SKILL"' 'true' \
  && m11a "$MS/clone-sem-md"
afirma "mm-mutante-11a-oraculo-sem-materializacao-morre" $? "sem a materializacao, o oraculo aceitaria o SKILL.md CRLF"
# 11b: o oraculo volta a depender SO do leitor real. Nao precisa de Git Bash
# para provar que fica cego: basta dar a ele o que um leitor tolerante a CR
# enxerga do MESMO arquivo — e ele conta 21, sem ver dano nenhum.
mkdir -p "$MS/tolerante"; tr -d '\r' < "$MS/clone-sem-md/$M_SKILL" > "$MS/tolerante/SKILL.md"
[ "$(conta_regras "$MS/tolerante/SKILL.md")" -eq 21 ]
afirma "mm-mutante-11b-oraculo-so-sed-fica-cego" $? "leitor tolerante a CR conta 21 no SKILL.md CRLF: so o sed nao mata o mutante"

# Mutantes dos scripts e do helper, em copia da skill (scripts/ + assets/). O controle, copia
# sem mutacao, sobrevive a todos os casos; cada mutante morre pelos casos designados.
copia_skill_m() {
  local d="$MS/mut/$1"; rm -rf "$d"; mkdir -p "$d/scripts" "$d/assets"
  cp "$SK/assets/TEMPLATE-PLANEJAMENTO.md" "$SK/assets/TEMPLATE-BLOQUEIOS.md" "$d/assets/"
  cp "$SK/scripts/planejamento.sh" "$SK/scripts/bloqueios.sh" "$SK/scripts/caminho-git.sh" "$d/scripts/"
  printf '%s' "$d"
}
m_troca() { muta_lit "$1" "$1.m" "$2" "$3" && mv "$1.m" "$1"; }
mutante_m() { # mutante_m <nome> <rc geracao> <skill> <caso que TEM de matar>...
  local nome="$1" rc="$2" s="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do "$c" "$s" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]; afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
CASOS_M="m_a m_b m_c m_d m_e m_f_sim m_g_sim m_h_sim"
M="$(copia_skill_m controle)"; vivosm=""
for c in $CASOS_M; do "$c" "$M" || vivosm="$vivosm$c "; done
[ -z "$vivosm" ]; afirma "mm-controle-copia-intacta-sobrevive" $? "${vivosm:-nenhum caso reprova a copia sem mutacao}"
LINHA_CG='    [A-Za-z]:/*) if command -v cygpath >/dev/null 2>&1; then cygpath -u -- "$1" && return 0; fi ;;'
LINHA_RAIZ='  local t; t="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$t" ] && { caminho_git "$t"; return; }'
LINHA_DIR='  local d="$PWD"; while [ "$d" != / ]; do [ -d "$d/.git" ] && { printf '"'%s'"' "$d"; return; }; d="$(dirname "$d")"; done'
M="$(copia_skill_m m3)"; m_troca "$M/scripts/caminho-git.sh" "$LINHA_CG" '    [A-Za-z]:/*) : ;;'
mutante_m "mm-mutante-3-sem-cygpath" $? "$M" m_a m_f_sim
M="$(copia_skill_m m4)"; m_troca "$M/scripts/caminho-git.sh" "$LINHA_CG" '    *) cygpath -u -- "$1"; return ;;'
mutante_m "mm-mutante-4-cygpath-em-tudo-quebra-linux" $? "$M" m_c m_e
M="$(copia_skill_m m4b)"; m_troca "$M/scripts/caminho-git.sh" '    [A-Za-z]:/*) if command' '    *) if command'
mutante_m "mm-mutante-4b-cygpath-indiscriminado" $? "$M" m_c m_d
M="$(copia_skill_m m5)"; m_troca "$M/scripts/caminho-git.sh" '    [A-Za-z]:/*) if command' '    [Cc]:/*) if command'
mutante_m "mm-mutante-5-so-drive-c" $? "$M" m_b
M="$(copia_skill_m m6)"; m_troca "$M/scripts/planejamento.sh" '{ caminho_git "$t"; return; }' '{ printf '"'%s'"' "$t"; return; }'
mutante_m "mm-mutante-6-planejamento-ignora-helper" $? "$M" m_f_sim m_h_sim
M="$(copia_skill_m m7)"; m_troca "$M/scripts/bloqueios.sh" '{ caminho_git "$t"; return; }' '{ printf '"'%s'"' "$t"; return; }'
mutante_m "mm-mutante-7-bloqueios-ignora-helper" $? "$M" m_g_sim m_h_sim
M="$(copia_skill_m m8)"; m_troca "$M/scripts/planejamento.sh" "$LINHA_RAIZ" "$LINHA_DIR" \
  && m_troca "$M/scripts/bloqueios.sh" "$LINHA_RAIZ" "$LINHA_DIR"
mutante_m "mm-mutante-8-worktree-usa-git-como-diretorio" $? "$M" m_h_sim
M="$(copia_skill_m m9)"; m_troca "$M/scripts/caminho-git.sh" 'cygpath -u -- "$1"' 'cygpath -u -- $1'
mutante_m "mm-mutante-9-espaco-quebrado" $? "$M" m_b

DSF3="$SK/DECISOES-DA-SKILL.md"
[ "$(grep -c '^| DS-151 |' "$DSF3")" -eq 1 ] && [ "$(grep -c '^| DS-152 |' "$DSF3")" -eq 1 ] \
  && tem "$DSF3" 'eol=lf' && tem "$DSF3" 'caminho_git'
afirma "m-ds151-ds152-registradas" $? "DECISOES-DA-SKILL.md"

rm -rf "$MS"

echo "== N. escopo e ownership do TRABALHO corrente, nao do id da task (P0.2-C7-B S2) =="
# Features se acumulam no repositorio: `T-01.01` existe na feature de hoje e em
# toda feature antiga. O id sozinho nunca identifica o plano — a sessao resolve
# TRABALHO + TASK pelo rastro, e so o plano daquele trabalho participa (DS-153).
NF_DIR="$(mktemp -d)"
N_SEQ=0
N_SAIDA=""; N_RC=0

n_ev() { # n_ev <dir> <arquivo-de-rastro> <evento> <task> <sessao> [trabalho_id-do-campo]
  local d="$1" tr="$2" evt="$3" tk="$4" ses="$5" campo="${6:-$2}" arq
  arq="$d/docs/eventos/$tr.jsonl"; mkdir -p "$(dirname "$arq")"
  N_SEQ=$((N_SEQ + 1))
  printf '{"ts":"2026-09-22T10:%02d:00Z","expx_eventos":1,"trabalho_id":"%s","ferramenta":"sprintx","origem":"skill","evento":"%s","fase":"f6","task":"%s","agente":"principal","resultado":"ok","detalhe":null,"arquivos":[],"sessao":"%s","harness":"claude"}\n' \
    "$N_SEQ" "$campo" "$evt" "$tk" "$ses" >> "$arq"
}
n_task() { # n_task <id> <status> <altera> [titulo]
  printf '  - id: %s\n    titulo: %s\n    status: %s\n    objetivo: obj\n    arquivos:\n      cria: []\n      altera: [%s]\n    teste_integracao: t\n    teste_funcional: t\n    criterio_aceite: c\n    depende_de: []\n    paralelizavel: false\n    concluida_em: null\n    suite: nao_executada\n' \
    "$1" "${4:-Task $1 original}" "$2" "$3"
}
n_plano() { # n_plano <arquivo> <trabalho_id> <sprint-NN> — tasks vem do stdin
  mkdir -p "$(dirname "$1")"
  { printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: tasks\ntrabalho_id: %s\nsprint_id: sprint-%s\ntasks:\n' "$2" "$3"
    cat
    printf -- '---\n'; } > "$1"
}
n_hook() { # n_hook <dir> <hook> <arquivo-relativo> <sessao> — rc em N_RC, saida em N_SAIDA
  N_SAIDA="$(printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$1" "$1/$3" \
    | (cd "$1" && EXPX_SESSAO="$4" bash "$2") 2>&1)"; N_RC=$?
}
n_tem() { printf '%s' "$N_SAIDA" | grep -qF "$1"; }
n_silencio() { [ "$N_RC" -eq 0 ] && [ -z "$N_SAIDA" ]; }

# n_fx <dir> <slug-historico> <ordem: hist|corr>
# Duas features vivas no mesmo repo, ambas com T-01.01. <slug-historico> troca a
# ordem alfabetica; <ordem> troca a ordem de criacao e o mtime — a feature
# HISTORICA fica sempre como a mais recente no disco, para que nada que olhe
# mtime possa ser confundido com o trabalho da sessao.
# A branch tambem leva o nome da historica, para matar "trabalho pelo branch".
n_fx() {
  local d="$1" h="$2" ordem="$3" f
  rm -rf "$d"; mkdir -p "$d/src"
  # Repo sem commit: o hook so precisa da raiz (rastro_raiz acha o .git). A
  # branch leva o nome da HISTORICA, para matar "trabalho pelo nome da branch".
  git init -q --template= -b "feature/$h" "$d" >/dev/null 2>&1
  N_HIST="$h"; N_CORR=corrente
  n_corrente() { n_plano "$d/docs/sprintx/features/corrente/sprint-01/tasks.md" corrente 01; }
  n_historica() { n_plano "$d/docs/sprintx/features/$h/sprint-01/tasks.md" "$h" 01; }
  if [ "$ordem" = corr ]; then
    n_corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
EOF
    n_historica <<EOF
$(n_task T-01.01 concluida src/antigo.ts)
EOF
  else
    n_historica <<EOF
$(n_task T-01.01 concluida src/antigo.ts)
EOF
    n_corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
EOF
  fi
  # historica sempre a mais nova no disco
  touch "$d/docs/sprintx/features/$h/sprint-01/tasks.md" "$d/docs/sprintx/features/$h"
  n_ev "$d" corrente task_iniciada T-01.01 eu@sessao
}
# Reescreve o plano de um trabalho ja existente na fixture.
n_replano() { # n_replano <dir> <trabalho> — tasks do stdin
  n_plano "$1/docs/sprintx/features/$2/sprint-01/tasks.md" "$2" 01
}

# ---------------------------------------------------------------- os casos
# Cada caso monta a fixture do zero e roda o hook recebido em $1 — e assim que
# os mutantes sao julgados.
n_a() { # mesma task id nas duas features: a corrente usa so o proprio plano
  n_fx "$NF_DIR/a" alfa-antiga hist
  n_hook "$NF_DIR/a" "$1" src/novo.ts eu@sessao; n_silencio
}
n_b() { # historica primeiro no alfabeto: resultado identico
  n_fx "$NF_DIR/b" alfa-antiga hist
  n_hook "$NF_DIR/b" "$1" src/novo.ts eu@sessao; n_silencio
}
n_c() { # ordem invertida (nome, criacao, mtime): resultado identico
  n_fx "$NF_DIR/c" zeta-antiga corr
  n_hook "$NF_DIR/c" "$1" src/novo.ts eu@sessao || return 1
  n_silencio
}
n_d() { # arquivo so da task historica: nao planejado na corrente, NAO irma
  n_fx "$NF_DIR/d" alfa-antiga hist
  n_hook "$NF_DIR/d" "$1" src/antigo.ts eu@sessao
  [ "$N_RC" -eq 0 ] && n_tem "nao esta na lista" && ! n_tem "arquivo_de_task_irma" && ! n_tem "defeito_de_plano"
}
n_e() { # o mesmo arquivo tambem numa irma DA CORRENTE: irma-only, bloqueio duro
  n_fx "$NF_DIR/e" alfa-antiga hist
  n_replano "$NF_DIR/e" corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
$(n_task T-01.02 pendente src/antigo.ts)
EOF
  n_hook "$NF_DIR/e" "$1" src/antigo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem arquivo_de_task_irma && n_tem T-01.02
}
n_f() { # mesmo arquivo na task atual corrente e na historica: current vence
  n_fx "$NF_DIR/f" alfa-antiga hist
  n_replano "$NF_DIR/f" alfa-antiga <<EOF
$(n_task T-01.01 concluida src/novo.ts)
EOF
  n_hook "$NF_DIR/f" "$1" src/novo.ts eu@sessao; n_silencio
}
n_g() { # atual + irma corrente + historica: current vence
  n_fx "$NF_DIR/g" alfa-antiga hist
  n_replano "$NF_DIR/g" corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
$(n_task T-01.02 pendente src/novo.ts)
EOF
  n_replano "$NF_DIR/g" alfa-antiga <<EOF
$(n_task T-01.01 concluida src/novo.ts)
EOF
  n_hook "$NF_DIR/g" "$1" src/novo.ts eu@sessao; n_silencio
}
n_h() { # duas irmas correntes + uma historica: lista SO as correntes
  n_fx "$NF_DIR/h" alfa-antiga hist
  n_replano "$NF_DIR/h" corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
$(n_task T-01.02 pendente src/compartilhado.ts)
$(n_task T-01.03 pendente src/compartilhado.ts)
EOF
  n_replano "$NF_DIR/h" alfa-antiga <<EOF
$(n_task T-01.09 concluida src/compartilhado.ts)
EOF
  n_hook "$NF_DIR/h" "$1" src/compartilhado.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem T-01.02 && n_tem T-01.03 && ! n_tem T-01.09
}
n_i() { # a sessao resolve trabalho + task: o aviso cita a task e os arquivos DO plano corrente
  n_fx "$NF_DIR/i" alfa-antiga hist
  n_hook "$NF_DIR/i" "$1" src/nada.ts eu@sessao
  [ "$N_RC" -eq 0 ] && n_tem "a task T-01.01" && n_tem src/novo.ts && ! n_tem src/antigo.ts
}
n_j() { # zero sessao ativa: fail-closed
  n_fx "$NF_DIR/j" alfa-antiga hist
  : > "$NF_DIR/j/docs/eventos/corrente.jsonl"
  n_hook "$NF_DIR/j" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem sessao_ambigua
}
n_k() { # a mesma sessao reivindicando task em DOIS trabalhos: fail-closed
  n_fx "$NF_DIR/k" alfa-antiga hist
  n_replano "$NF_DIR/k" alfa-antiga <<EOF
$(n_task T-01.01 em_andamento src/antigo.ts)
EOF
  n_ev "$NF_DIR/k" alfa-antiga task_iniciada T-01.01 eu@sessao
  n_hook "$NF_DIR/k" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem sessao_ambigua
}
n_l() { # plano do trabalho corrente ausente: fail-closed, sem cair na historica
  n_fx "$NF_DIR/l" alfa-antiga hist
  n_replano "$NF_DIR/l" alfa-antiga <<EOF
$(n_task T-01.01 em_andamento src/antigo.ts)
EOF
  rm -rf "$NF_DIR/l/docs/sprintx/features/corrente"
  n_hook "$NF_DIR/l" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem plano_corrente_ausente
}
n_m() { # plano do trabalho corrente ilegivel: fail-closed
  n_fx "$NF_DIR/m" alfa-antiga hist
  printf 'isto nao e um plano\n' > "$NF_DIR/m/docs/sprintx/features/corrente/sprint-01/tasks.md"
  n_replano "$NF_DIR/m" alfa-antiga <<EOF
$(n_task T-01.01 em_andamento src/antigo.ts)
EOF
  n_hook "$NF_DIR/m" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem plano_corrente_ilegivel
}
n_n() { # layout legado DO trabalho corrente: funciona, com as mesmas regras
  n_fx "$NF_DIR/n" alfa-antiga hist
  rm -rf "$NF_DIR/n/docs/sprintx/features/corrente"
  n_plano "$NF_DIR/n/docs/corrente/sprint-01/tasks.md" corrente 01 <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
$(n_task T-01.02 pendente src/legado-irma.ts)
EOF
  n_hook "$NF_DIR/n" "$1" src/novo.ts eu@sessao; n_silencio || return 1
  n_hook "$NF_DIR/n" "$1" src/legado-irma.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem arquivo_de_task_irma && n_tem T-01.02
}
n_o() { # legado de OUTRO trabalho nunca vira fallback do corrente
  n_fx "$NF_DIR/o" alfa-antiga hist
  rm -rf "$NF_DIR/o/docs/sprintx/features/corrente"
  n_plano "$NF_DIR/o/docs/legado-de-outro/sprint-01/tasks.md" legado-de-outro 01 <<EOF
$(n_task T-01.01 em_andamento src/antigo.ts)
EOF
  n_hook "$NF_DIR/o" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem plano_corrente_ausente
}
n_p() { # titulos mudam: resultado identico ao n_e
  n_fx "$NF_DIR/p" alfa-antiga hist
  n_replano "$NF_DIR/p" corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts 'Reescrita total do topo — antigo.ts tambem')
$(n_task T-01.02 pendente src/antigo.ts 'Nome completamente diferente')
EOF
  n_replano "$NF_DIR/p" alfa-antiga <<EOF
$(n_task T-01.01 concluida src/antigo.ts 'Task historica renomeada')
EOF
  n_hook "$NF_DIR/p" "$1" src/antigo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem arquivo_de_task_irma && n_tem T-01.02
}
n_q() { # C2 preservado: irma-only bloqueia mesmo em modo aviso, com historica no repo
  n_fx "$NF_DIR/q" alfa-antiga hist
  n_replano "$NF_DIR/q" corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
$(n_task T-01.02 pendente src/antigo.ts)
EOF
  mkdir -p "$NF_DIR/q/.expx"
  printf '{"hooks":{"escopo-da-task":{"modo":"aviso"}}}\n' > "$NF_DIR/q/.expx/hooks.json"
  n_hook "$NF_DIR/q" "$1" src/antigo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem arquivo_de_task_irma
}
n_s() { # arquivo de task nenhuma: segue aviso, nunca defeito_de_plano
  n_fx "$NF_DIR/s" alfa-antiga hist
  n_hook "$NF_DIR/s" "$1" src/nada.ts eu@sessao
  [ "$N_RC" -eq 0 ] && ! n_tem defeito_de_plano && ! n_tem arquivo_de_task_irma
}
n_t() { # duas sessoes, dois trabalhos: cada uma no seu escopo
  n_fx "$NF_DIR/t" alfa-antiga hist
  n_replano "$NF_DIR/t" alfa-antiga <<EOF
$(n_task T-01.01 em_andamento src/antigo.ts)
$(n_task T-01.02 pendente src/so-da-antiga.ts)
EOF
  n_ev "$NF_DIR/t" alfa-antiga task_iniciada T-01.01 outra@sessao
  n_hook "$NF_DIR/t" "$1" src/novo.ts eu@sessao; n_silencio || return 1
  n_hook "$NF_DIR/t" "$1" src/antigo.ts outra@sessao; n_silencio || return 1
  # a irma da outra feature so existe para a sessao da outra feature
  n_hook "$NF_DIR/t" "$1" src/so-da-antiga.ts outra@sessao
  [ "$N_RC" -eq 2 ] && n_tem arquivo_de_task_irma || return 1
  n_hook "$NF_DIR/t" "$1" src/so-da-antiga.ts eu@sessao
  [ "$N_RC" -eq 0 ] && n_tem "nao esta na lista"
}
n_u() { # acumulo: uma TERCEIRA feature historica nao muda resposta nenhuma
  n_fx "$NF_DIR/u" alfa-antiga hist
  n_replano "$NF_DIR/u" corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
$(n_task T-01.02 pendente src/antigo.ts)
EOF
  local antes depois rc_antes
  n_hook "$NF_DIR/u" "$1" src/antigo.ts eu@sessao; antes="$N_SAIDA"; rc_antes="$N_RC"
  n_plano "$NF_DIR/u/docs/sprintx/features/meio-antiga/sprint-01/tasks.md" meio-antiga 01 <<EOF
$(n_task T-01.01 concluida src/antigo.ts)
$(n_task T-01.02 concluida src/novo.ts)
$(n_task T-01.03 em_andamento src/terceiro.ts)
EOF
  n_ev "$NF_DIR/u" meio-antiga task_iniciada T-01.03 terceira@sessao
  n_hook "$NF_DIR/u" "$1" src/antigo.ts eu@sessao; depois="$N_SAIDA"
  [ "$rc_antes" -eq 2 ] && [ "$N_RC" -eq 2 ] && [ "$antes" = "$depois" ] || return 1
  n_hook "$NF_DIR/u" "$1" src/novo.ts eu@sessao; n_silencio
}
n_div() { # nome do arquivo de rastro x campo trabalho_id do evento: fail-closed
  n_fx "$NF_DIR/div" alfa-antiga hist
  : > "$NF_DIR/div/docs/eventos/corrente.jsonl"
  n_ev "$NF_DIR/div" corrente task_iniciada T-01.01 eu@sessao outro-trabalho
  n_hook "$NF_DIR/div" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem contexto_de_trabalho_divergente
}
n_amb() { # o mesmo trabalho nos dois layouts: nao da para amarrar plano a trabalho
  n_fx "$NF_DIR/amb" alfa-antiga hist
  n_plano "$NF_DIR/amb/docs/corrente/sprint-01/tasks.md" corrente 01 <<EOF
$(n_task T-01.01 em_andamento src/outro-novo.ts)
EOF
  n_hook "$NF_DIR/amb" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem plano_corrente_ambiguo
}
n_fora() { # task reivindicada que o plano do proprio trabalho nao declara
  n_fx "$NF_DIR/fora" alfa-antiga hist
  n_replano "$NF_DIR/fora" corrente <<EOF
$(n_task T-07.07 em_andamento src/novo.ts)
EOF
  n_hook "$NF_DIR/fora" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem task_fora_do_plano_corrente
}

NHOOK="$H/sprintx/escopo-da-task.sh"
bash -n "$NHOOK"; afirma "n0-hook-sintaxe" $? "bash -n"
for par in \
  n_a:na-duas-features-mesmo-id-usa-so-o-proprio-plano \
  n_b:nb-historica-primeiro-no-alfabeto-nao-muda \
  n_c:nc-ordem-de-criacao-e-mtime-invertidos-nao-mudam \
  n_d:nd-arquivo-so-da-historica-nao-e-irma \
  n_e:ne-arquivo-de-irma-corrente-bloqueia \
  n_f:nf-mesmo-arquivo-na-atual-e-na-historica-current-vence \
  n_g:ng-atual-mais-irma-mais-historica-current-vence \
  n_h:nh-lista-so-as-irmas-correntes \
  n_i:ni-sessao-resolve-trabalho-e-task \
  n_j:nj-zero-sessao-ativa-fail-closed \
  n_k:nk-sessao-em-dois-trabalhos-fail-closed \
  n_l:nl-plano-corrente-ausente-fail-closed \
  n_m:nm-plano-corrente-ilegivel-fail-closed \
  n_n:nn-legado-do-trabalho-corrente-funciona \
  n_o:no-legado-de-outro-trabalho-nunca-e-fallback \
  n_p:np-titulos-mudam-resultado-igual \
  n_q:nq-irma-bloqueia-mesmo-em-aviso \
  n_s:ns-arquivo-de-ninguem-segue-aviso \
  n_t:nt-duas-sessoes-dois-trabalhos \
  n_u:nu-terceira-feature-historica-nao-muda-nada \
  n_div:ndiv-trabalho-divergente-fail-closed \
  n_amb:namb-dois-layouts-do-mesmo-trabalho-fail-closed \
  n_fora:nfora-task-fora-do-plano-corrente-fail-closed; do
  "${par%%:*}" "$NHOOK"; afirma "${par#*:}" $? "${par%%:*}"
done

# ------------------------------------------------------------------ mutantes
# Cada mutante mora num diretorio proprio com sprintx/ + comum/ (o hook faz
# `source ../comum/rastro.sh`), porque alguns mutam o helper, nao o hook.
NM="$NF_DIR/mut"
n_copia() { # n_copia <nome> — devolve o caminho do hook copiado
  local d="$NM/$1"; rm -rf "$d"; mkdir -p "$d/sprintx" "$d/comum"
  cp "$H/comum/rastro.sh" "$d/comum/rastro.sh"
  cp "$NHOOK" "$d/sprintx/escopo-da-task.sh"
  printf '%s' "$d/sprintx/escopo-da-task.sh"
}
n_muta() { # n_muta <arquivo> <trecho> <troca>
  muta_lit "$1" "$1.m" "$2" "$3" && mv "$1.m" "$1"
}
n_mutante() { # n_mutante <nome> <rc geracao> <hook mutante> <caso que TEM de matar>...
  local nome="$1" rc="$2" s="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do "$c" "$s" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]
  afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
CASOS_N="n_a n_c n_d n_e n_f n_g n_h n_i n_j n_k n_l n_m n_n n_o n_p n_q n_s n_t n_u n_div n_amb n_fora"

NMC="$(n_copia controle)"; vivosn=""
for c in $CASOS_N; do "$c" "$NMC" || vivosn="$vivosn$c "; done
[ -z "$vivosn" ]; afirma "nm-controle-copia-intacta-sobrevive" $? "${vivosn:-nenhum caso reprova a copia sem mutacao}"

# Os literais seguem a reescrita de custo do hook (DS-157): o plano do trabalho e escolhido
# no END do awk (do_trabalho/PTR). A intencao de cada mutante e a de sempre.
L_CANON='    if (index(f, CAN) == 1 && barras(substr(f, length(CAN) + 1)) <= 2) return 1'
L_LEGADO='    if (index(f, LEG) == 1 && barras(substr(f, length(LEG) + 1)) <= 2) return 2'
L_GLOBAL='    if (index(f, raiz "/docs/") == 1) return 1'

NMUT="$(n_copia m1)"; n_muta "$NMUT" "$L_CANON" "$L_GLOBAL"
n_mutante "nm-mutante-1-volta-ao-find-global" $? "$NMUT" n_d n_h

# So n_h: com a task homonima da historica tendo o MESMO id da corrente, quem
# vence em n_d depende da ordem que o find devolve — e ordem nao e prova. Em
# n_h a irma historica tem id proprio (T-01.09) e aparece na lista em qualquer
# filesystem.
NMUT="$(n_copia m2)"; n_muta "$NMUT" 'PTR[i] = do_trabalho(PARQ[i]); if (PTR[i]) npt++' 'PTR[i] = 1; if (PTR[i]) npt++'
n_mutante "nm-mutante-2-primeiro-plano-com-o-mesmo-id" $? "$NMUT" n_h

NMUT="$(n_copia m3)"; n_muta "$NMUT" '    if (!TEMCAN && !TEMLEG) { print "P ausente"; exit }' \
  '    if (!TEMCAN && !TEMLEG) { SEMPLANO = 1 }' \
  && n_muta "$NMUT" '    npt = 0; for (i = 1; i <= NP; i++) { PTR[i] = do_trabalho(PARQ[i]); if (PTR[i]) npt++ }' \
  '    npt = 0; for (i = 1; i <= NP; i++) { PTR[i] = SEMPLANO ? 1 : do_trabalho(PARQ[i]); if (PTR[i]) npt++ }'
n_mutante "nm-mutante-3-plano-historico-como-fallback" $? "$NMUT" n_l n_o

NMUT="$(n_copia m4)"; n_muta "$NMUT" 'if (PID[i] == ID && PTR[i] && (cur == ""' 'if (PID[i] == ID && (cur == ""'
n_mutante "nm-mutante-4-uniao-de-todas-as-features-como-others" $? "$NMUT" n_a n_i

NMUT="$(n_copia m5)"; n_muta "$NMUT" 'if (N == 1) { split(RV_L[1], p, "\t"); T = p[1]; ID = p[2]; COER = p[3] }' \
  'if (N == 1) { split(RV_L[1], p, "\t"); ID = p[2]; COER = p[3]; c = "git -C \"" raiz "\" symbolic-ref --short HEAD 2>/dev/null"; c | getline T; close(c); sub(/.*\//, "", T) }'
n_mutante "nm-mutante-5-trabalho-pelo-nome-da-branch" $? "$NMUT" n_a n_d

# A reivindicacao deixa de ser DA SESSAO: toda task aberta no rastro conta como desta sessao.
NMUT="$(n_copia m6)"; n_muta "$NMUT" '    _rv_fim(ses); N = RV_N' \
  '    for (k in _rv_dono) if (_rv_dono[k] != "") _rv_dono[k] = ses; _rv_fim(ses); N = RV_N'
n_mutante "nm-mutante-6-primeira-task-em-andamento" $? "$NMUT" n_t n_u

NMUT="$(n_copia m7)"; n_muta "$NMUT" 'if [ "$COERENCIA" != "ok" ]; then' 'if false; then'
n_mutante "nm-mutante-7-ignora-trabalho-divergente" $? "$NMUT" n_div

NMUT="$(n_copia m8)"; n_muta "$NMUT" 'if [ "$DECL" = irma ]; then' \
  'if [ "$DECL" = irma ] || grep -qsF -- "$REL" "$RAIZ"/docs/sprintx/features/*/sprint-*/tasks.md "$RAIZ"/docs/*/sprint-*/tasks.md >/dev/null 2>&1; then'
n_mutante "nm-mutante-8-irma-historica-vira-irma-da-corrente" $? "$NMUT" n_d

# Os arquivos da task corrente viram a uniao de TODA task com o mesmo id, de qualquer feature.
NMUT="$(n_copia m9)"; n_muta "$NMUT" '    k = cur SUBSEP ID; lista = ""; corrente = 0' \
  '    k = cur SUBSEP ID; lista = ""; corrente = 0; for (i = 1; i <= NP; i++) if (PID[i] == ID && PARQ[i] != cur) for (j = 1; j <= NAN[PARQ[i] SUBSEP ID]; j++) NA[k, ++NAN[k]] = NA[PARQ[i] SUBSEP ID, j]'
n_mutante "nm-mutante-9-task-homonima-historica-autoriza" $? "$NMUT" n_e n_p

NMUT="$(n_copia m10)"; n_muta "$NMUT" "$L_LEGADO" \
  '    if (index(f, raiz "/docs/") == 1 && barras(substr(f, length(raiz "/docs/") + 1)) <= 2) return 2'
n_mutante "nm-mutante-10-legado-de-outro-trabalho-como-fallback" $? "$NMUT" n_o

# Mutante do helper: sem o filtro de sessao, o par volta a ser "o primeiro que
# aparece no rastro" — a regressao que a DS-150 proibiu.
NMUT="$(n_copia m11)"; n_muta "$NM/m11/comum/rastro.sh" \
  'if (_rv_dono[k] == "" || _rv_dono[k] != ses) continue' 'if (_rv_dono[k] == "") continue'
n_mutante "nm-mutante-11-helper-ignora-a-sessao" $? "$NMUT" n_t n_u

DSF4="$SK/DECISOES-DA-SKILL.md"
[ "$(grep -c '^| DS-153 |' "$DSF4")" -eq 1 ] && [ "$(grep -c '^| DS-154 |' "$DSF4")" -eq 1 ] \
  && tem "$DSF4" 'rastro_reivindicacoes_da_sessao' && tem "$DSF4" 'plano_corrente_ausente'
afirma "n-ds153-ds154-registradas" $? "DECISOES-DA-SKILL.md"

rm -rf "$NF_DIR"

echo "== O. o rastro grava no TRABALHO corrente, nunca no mais recente por mtime (P0.2-C7-B S3) =="
# Duas features vivas, duas sessoes, e a feature ERRADA deixada de proposito
# como a mais recente no disco. O destino do evento sai do trabalho que o
# chamador declara, ou do trabalho corrente da sessao — mtime nunca participa
# (DS-155). Reusa n_plano/n_task da secao N: o plano e o mesmo artefato.
OF_DIR="$(mktemp -d)"
O_SEQ=0; O_SAIDA=""; O_RC=0

o_ev() { # o_ev <dir> <trabalho> <task> <sessao>
  local arq="$1/docs/eventos/$2.jsonl"; mkdir -p "$(dirname "$arq")"
  O_SEQ=$((O_SEQ + 1))
  printf '{"ts":"2026-09-23T09:%02d:00Z","expx_eventos":1,"trabalho_id":"%s","ferramenta":"sprintx","origem":"skill","evento":"task_iniciada","fase":"f6","task":"%s","agente":"principal","resultado":"ok","detalhe":null,"arquivos":[],"sessao":"%s","harness":"claude"}\n' \
    "$O_SEQ" "$2" "$3" "$4" >> "$arq"
}
o_ck() { cksum < "$1" 2>/dev/null; }                      # byte a byte
o_linhas() { grep -c '' "$1" 2>/dev/null || printf 0; }
# Deixa <trabalho> como o mais recente no disco — pasta, plano E arquivo de
# rastro. Nada disso pode mover o destino de uma linha de evento.
o_toca() { # o_toca <dir> <trabalho>
  touch "$1/docs/sprintx/features/$2/sprint-01/tasks.md" "$1/docs/sprintx/features/$2/sprint-01" \
        "$1/docs/sprintx/features/$2" "$1/docs/eventos/$2.jsonl" 2>/dev/null
}
o_fx() { # o_fx <dir> <trabalho mais recente no disco>
  local d="$1"
  # `.git` vazio basta: `rastro_raiz` so testa `[ -e ]`, e nenhum dos tres
  # hooks desta secao chama git. `git init` custa segundos por fixture.
  rm -rf "$d"; mkdir -p "$d/src" "$d/.git"
  n_plano "$d/docs/sprintx/features/feature-a/sprint-01/tasks.md" feature-a 01 <<EOF
$(n_task T-01.01 em_andamento src/a.ts)
$(n_task T-01.02 pendente src/irma-a.ts)
EOF
  n_plano "$d/docs/sprintx/features/feature-b/sprint-01/tasks.md" feature-b 01 <<EOF
$(n_task T-01.01 em_andamento src/b.ts)
$(n_task T-01.02 pendente src/irma-b.ts)
EOF
  o_ev "$d" feature-a T-01.01 sessao-a
  o_ev "$d" feature-b T-01.01 sessao-b
  o_toca "$d" "$2"
}
o_hook() { # o_hook <raiz-hooks> <dir> <hook-relativo> <arquivo-relativo> <sessao>
  O_SAIDA="$(printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$2" "$2/$4" \
    | (cd "$2" && EXPX_SESSAO="$5" bash "$1/$3") 2>&1)"; O_RC=$?
}
# Chama uma funcao da biblioteca copiada (possivelmente mutada), com a
# identidade de sessao do caso.
o_chama() { # o_chama <raiz-hooks> <dir> <sessao> <funcao> [args...]
  local hr="$1" d="$2" ses="$3"; shift 3
  (cd "$d" && EXPX_SESSAO="$ses" bash -c '. "$0/comum/rastro.sh"; f="$1"; shift; "$f" "$@"' "$hr" "$@") 2>/dev/null
}
o_json_write() { # o_json_write <cwd> <file_path> — conteudo do stdin
  python3 -c "
import json, sys
print(json.dumps({'cwd': sys.argv[1], 'tool_name': 'Write', 'tool_input': {'file_path': sys.argv[2], 'content': sys.stdin.read()}}))
" "$1" "$2"
}

# ---------------------------------------------------------------- os casos
o_a() { # sessao em feature-a, feature-b mais recente: so feature-a.jsonl muda
  local d="$OF_DIR/a" b
  o_fx "$d" feature-b
  b="$(o_ck "$d/docs/eventos/feature-b.jsonl")"
  o_hook "$1" "$d" sprintx/escopo-da-task.sh src/irma-a.ts sessao-a
  [ "$O_RC" -eq 2 ] || return 1
  grep -q '"trabalho_id":"feature-a".*"detalhe":"arquivo_de_task_irma"' "$d/docs/eventos/feature-a.jsonl" || return 1
  [ "$(o_linhas "$d/docs/eventos/feature-a.jsonl")" -eq 2 ] || return 1
  [ "$(o_ck "$d/docs/eventos/feature-b.jsonl")" = "$b" ] || return 1
  [ "$(o_linhas "$d/docs/eventos/sem-trabalho.jsonl")" -eq 0 ]
}
o_b() { # mtimes invertidos: resultado identico
  local d="$OF_DIR/b" b
  o_fx "$d" feature-a
  b="$(o_ck "$d/docs/eventos/feature-b.jsonl")"
  o_hook "$1" "$d" sprintx/escopo-da-task.sh src/irma-a.ts sessao-a
  [ "$O_RC" -eq 2 ] && [ "$(o_linhas "$d/docs/eventos/feature-a.jsonl")" -eq 2 ] \
    && [ "$(o_ck "$d/docs/eventos/feature-b.jsonl")" = "$b" ]
}
o_c() { # uma TERCEIRA feature, mais recente que as duas: resultado identico
  local d="$OF_DIR/c" b c
  o_fx "$d" feature-b
  n_plano "$d/docs/sprintx/features/feature-c/sprint-01/tasks.md" feature-c 01 <<EOF
$(n_task T-01.01 em_andamento src/c.ts)
EOF
  o_ev "$d" feature-c T-01.01 sessao-c
  o_toca "$d" feature-c
  b="$(o_ck "$d/docs/eventos/feature-b.jsonl")"; c="$(o_ck "$d/docs/eventos/feature-c.jsonl")"
  o_hook "$1" "$d" sprintx/escopo-da-task.sh src/irma-a.ts sessao-a
  [ "$O_RC" -eq 2 ] && [ "$(o_linhas "$d/docs/eventos/feature-a.jsonl")" -eq 2 ] \
    && [ "$(o_ck "$d/docs/eventos/feature-b.jsonl")" = "$b" ] \
    && [ "$(o_ck "$d/docs/eventos/feature-c.jsonl")" = "$c" ]
}
o_d() { # paralelismo: sessao A -> arquivo A, sessao B -> arquivo B, sem cruzamento
  local d="$OF_DIR/d"
  o_fx "$d" feature-b
  o_hook "$1" "$d" sprintx/escopo-da-task.sh src/irma-a.ts sessao-a; [ "$O_RC" -eq 2 ] || return 1
  o_hook "$1" "$d" sprintx/escopo-da-task.sh src/irma-b.ts sessao-b; [ "$O_RC" -eq 2 ] || return 1
  [ "$(o_linhas "$d/docs/eventos/feature-a.jsonl")" -eq 2 ] \
    && [ "$(o_linhas "$d/docs/eventos/feature-b.jsonl")" -eq 2 ] \
    && [ "$(grep -c '"trabalho_id":"feature-b"' "$d/docs/eventos/feature-a.jsonl")" -eq 0 ] \
    && [ "$(grep -c '"trabalho_id":"feature-a"' "$d/docs/eventos/feature-b.jsonl")" -eq 0 ] \
    && [ "$(o_linhas "$d/docs/eventos/sem-trabalho.jsonl")" -eq 0 ]
}
o_e() { # trabalho explicito x trabalho provado pela sessao: nao grava em A nem em B
  local d="$OF_DIR/e" a b
  o_fx "$d" feature-b
  a="$(o_ck "$d/docs/eventos/feature-a.jsonl")"; b="$(o_ck "$d/docs/eventos/feature-b.jsonl")"
  o_chama "$1" "$d" sessao-a rastro_grava_trabalho "$d" feature-b regra_violada hook aviso "evento cruzado" "[]"
  [ "$(o_ck "$d/docs/eventos/feature-a.jsonl")" = "$a" ] \
    && [ "$(o_ck "$d/docs/eventos/feature-b.jsonl")" = "$b" ] \
    && [ "$(grep -c 'contexto_de_trabalho_divergente' "$d/docs/eventos/sem-trabalho.jsonl")" -eq 1 ]
}
o_f() { # retomada: gravar nao teleporta a sessao para outro trabalho
  local d="$OF_DIR/f" antes depois esperado
  o_fx "$d" feature-b
  esperado="$(printf 'feature-a\tT-01.01\tok')"
  antes="$(o_chama "$1" "$d" sessao-a rastro_reivindicacoes_da_sessao "$d" sessao-a)"
  [ "$antes" = "$esperado" ] || return 1
  o_hook "$1" "$d" sprintx/escopo-da-task.sh src/irma-a.ts sessao-a; [ "$O_RC" -eq 2 ] || return 1
  o_chama "$1" "$d" sessao-a rastro_grava_trabalho "$d" - arquivo_alterado hook ok Write "[]"
  o_chama "$1" "$d" sessao-a rastro_grava_trabalho "$d" feature-b regra_violada hook aviso "tentativa cruzada" "[]"
  depois="$(o_chama "$1" "$d" sessao-a rastro_reivindicacoes_da_sessao "$d" sessao-a)"
  [ "$depois" = "$esperado" ] \
    && [ "$(o_chama "$1" "$d" sessao-a rastro_trabalho_da_sessao "$d")" = feature-a ] \
    && [ "$(o_linhas "$d/docs/eventos/feature-a.jsonl")" -eq 3 ]
}
o_g() { # sessao sem reivindicacao: sem-trabalho, e nenhuma feature e tocada
  local d="$OF_DIR/g" a b
  o_fx "$d" feature-b
  a="$(o_ck "$d/docs/eventos/feature-a.jsonl")"; b="$(o_ck "$d/docs/eventos/feature-b.jsonl")"
  o_chama "$1" "$d" sessao-x rastro_grava "$d" regra_violada hook aviso "sem trabalho" "[]"
  [ "$(o_ck "$d/docs/eventos/feature-a.jsonl")" = "$a" ] \
    && [ "$(o_ck "$d/docs/eventos/feature-b.jsonl")" = "$b" ] \
    && [ "$(grep -c '"trabalho_id":"sem-trabalho"' "$d/docs/eventos/sem-trabalho.jsonl")" -eq 1 ]
}
o_h() { # trabalho deterministico pelo CAMINHO (sem-placeholder-no-plano)
  local d="$OF_DIR/h" a alvo
  o_fx "$d" feature-a                       # feature-a e a mais recente no disco
  alvo="$d/docs/sprintx/features/feature-b/00-PLANEJAMENTO.md"
  printf -- '---\nkind: planejamento\ntrabalho_id: feature-b\n---\nobjetivo: {{marcador}}\n' > "$alvo"
  a="$(o_ck "$d/docs/eventos/feature-a.jsonl")"
  o_hook "$1" "$d" sprintx/sem-placeholder-no-plano.sh \
    docs/sprintx/features/feature-b/00-PLANEJAMENTO.md sessao-x
  [ "$(grep -c '"trabalho_id":"feature-b".*placeholder' "$d/docs/eventos/feature-b.jsonl")" -eq 1 ] \
    && [ "$(o_ck "$d/docs/eventos/feature-a.jsonl")" = "$a" ] \
    && [ "$(o_linhas "$d/docs/eventos/sem-trabalho.jsonl")" -eq 0 ]
}
o_i() { # trabalho deterministico pelo FRONTMATTER (task-reivindicada)
  local d="$OF_DIR/i" a j
  o_fx "$d" feature-a                       # feature-a e a mais recente no disco
  n_plano "$OF_DIR/i-novo.md" feature-b 01 <<EOF
$(n_task T-01.01 em_andamento src/b.ts)
EOF
  j="$(o_json_write "$d" "$d/docs/sprintx/features/feature-b/sprint-01/tasks.md" < "$OF_DIR/i-novo.md")"
  a="$(o_ck "$d/docs/eventos/feature-a.jsonl")"
  O_SAIDA="$(printf '%s' "$j" | (cd "$d" && EXPX_SESSAO=sessao-x bash "$1/sprintx/task-reivindicada.sh") 2>&1)"; O_RC=$?
  # T-01.01 de feature-b esta aberta por sessao-b: sessao-x e avisada, e o
  # evento vai para o rastro de feature-b — o trabalho_id do proprio tasks.md.
  [ "$O_RC" -eq 0 ] && printf '%s' "$O_SAIDA" | grep -qF 'sessao-b' \
    && [ "$(grep -c '"trabalho_id":"feature-b".*regra_violada' "$d/docs/eventos/feature-b.jsonl")" -eq 1 ] \
    && [ "$(o_ck "$d/docs/eventos/feature-a.jsonl")" = "$a" ]
}

o_j() { # arvore-limpa: o escopo comparado e o do trabalho da SESSAO
  local d="$OF_DIR/j" b
  o_fx "$d" feature-b
  # este hook roda `git status`, entao aqui a fixture precisa de repo de verdade
  rm -rf "$d/.git"; git init -q --template= -b main "$d" >/dev/null 2>&1
  : > "$d/src/a.ts"                 # declarado na T-01.01 de feature-a
  : > "$d/src/fora-do-plano.ts"     # de task nenhuma
  b="$(o_ck "$d/docs/eventos/feature-b.jsonl")"
  O_SAIDA="$(printf '{"cwd":"%s","tool_input":{"command":"npm test"}}' "$d" \
    | (cd "$d" && EXPX_SESSAO=sessao-a bash "$1/sprintx/arvore-limpa-antes-da-suite.sh") 2>&1)"; O_RC=$?
  [ "$O_RC" -eq 0 ] || return 1
  printf '%s' "$O_SAIDA" | grep -qF 'src/fora-do-plano.ts' || return 1
  printf '%s' "$O_SAIDA" | grep -qF ' src/a.ts' && return 1
  grep -q '"trabalho_id":"feature-a".*"detalhe":"arvore contaminada"' "$d/docs/eventos/feature-a.jsonl" || return 1
  [ "$(o_ck "$d/docs/eventos/feature-b.jsonl")" = "$b" ] || return 1
  # sessao sem reivindicacao: nao ha escopo a comparar, e o hook sai calado
  O_SAIDA="$(printf '{"cwd":"%s","tool_input":{"command":"npm test"}}' "$d" \
    | (cd "$d" && EXPX_SESSAO=sessao-x bash "$1/sprintx/arvore-limpa-antes-da-suite.sh") 2>&1)"; O_RC=$?
  [ "$O_RC" -eq 0 ] && [ -z "$O_SAIDA" ]
}

OHR="$H"
bash -n "$H/comum/rastro.sh"; afirma "o0-rastro-sintaxe" $? "bash -n"
for par in \
  o_a:oa-destino-e-o-trabalho-da-sessao-nao-o-mtime \
  o_b:ob-mtimes-invertidos-resultado-identico \
  o_c:oc-terceira-feature-recente-nao-muda-nada \
  o_d:od-duas-sessoes-dois-arquivos-sem-cruzamento \
  o_e:oe-divergencia-nao-grava-em-a-nem-em-b \
  o_f:of-retomada-evento-posterior-nao-teleporta \
  o_g:og-sem-reivindicacao-vai-para-sem-trabalho \
  o_h:oh-trabalho-pelo-caminho-do-plano \
  o_i:oi-trabalho-pelo-frontmatter-do-tasks-md \
  o_j:oj-arvore-limpa-compara-o-escopo-do-trabalho-da-sessao; do
  "${par%%:*}" "$OHR"; afirma "${par#*:}" $? "${par%%:*}"
done

# Nenhuma producao pode voltar a escolher destino por mtime.
[ "$(grep -rln 'rastro_trabalho_id' "$H/comum" "$H/sprintx" "$SK/scripts" 2>/dev/null | wc -l)" -eq 0 ]
afirma "o-sem-rastro-trabalho-id" $? "a funcao que escolhia por mtime nao existe mais"
[ "$(grep -rln -- '-nt ' "$H/comum" "$H/sprintx" 2>/dev/null | wc -l)" -eq 0 ]
afirma "o-sem-comparacao-de-mtime-nos-hooks" $? "nenhum hook compara data de arquivo"

# ------------------------------------------------------------------ mutantes
OM="$OF_DIR/mut"
o_copia() { # o_copia <nome> — devolve a raiz de hooks copiada
  local d="$OM/$1"; rm -rf "$d"; mkdir -p "$d/sprintx" "$d/comum"
  cp "$H/comum/rastro.sh" "$d/comum/rastro.sh"
  cp "$H/sprintx/escopo-da-task.sh" "$H/sprintx/task-reivindicada.sh" \
     "$H/sprintx/sem-placeholder-no-plano.sh" "$H/sprintx/arvore-limpa-antes-da-suite.sh" "$d/sprintx/"
  printf '%s' "$d"
}
o_muta() { muta_lit "$1" "$1.m" "$2" "$3" && mv "$1.m" "$1"; }
o_mutante() { # o_mutante <nome> <rc geracao> <raiz> <caso que TEM de matar>...
  local nome="$1" rc="$2" s="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do "$c" "$s" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]
  afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
CASOS_O="o_a o_b o_c o_d o_e o_f o_g o_h o_i o_j"

OMC="$(o_copia controle)"; vivoso=""
for c in $CASOS_O; do "$c" "$OMC" || vivoso="$vivoso$c "; done
[ -z "$vivoso" ]; afirma "om-controle-copia-intacta-sobrevive" $? "${vivoso:-nenhum caso reprova a copia sem mutacao}"

L_SESSAO='  local _raiz="$2" _ses="${3:-}" _tid _coer'
L_MTIME='  local _raiz="$2" _ses="${3:-}" _tid _coer; local f mais_novo=""; for f in "$_raiz"/docs/sprintx/features/*/; do [ -d "$f" ] || continue; if [ -z "$mais_novo" ] || [ "$f" -nt "$mais_novo" ]; then mais_novo="$f"; fi; done; mais_novo="${mais_novo%/}"; printf -v "$1" "%s" "${mais_novo##*/}"; return 0'
OMUT="$(o_copia m1)"; o_muta "$OM/m1/comum/rastro.sh" "$L_SESSAO" "$L_MTIME"
# O escopo-da-task entrega ao rastro.sh o trabalho que ja resolveu (DS-157): o helper decide o
# destino dos outros hooks (o_i, o_j); o mesmo defeito no escopo e o om-mutante-6.
o_mutante "om-mutante-1-destino-por-mtime" $? "$OMUT" o_i o_j

OMUT="$(o_copia m2)"; o_muta "$OM/m2/comum/rastro.sh" \
  '  local raiz="$1" pedido="$2" evento="$3"' '  local raiz="$1" pedido="-" evento="$3"'
o_mutante "om-mutante-2-ignora-trabalho-explicito" $? "$OMUT" o_h o_i

OMUT="$(o_copia m3)"; o_muta "$OM/m3/comum/rastro.sh" '      tid="$pedido"' \
  '      tid="$(cd "$dir" 2>/dev/null && ls -t *.jsonl 2>/dev/null | head -1)"; tid="${tid%.jsonl}"; [ -n "$tid" ] || tid="$pedido"'
o_mutante "om-mutante-3-grava-na-feature-mais-recente" $? "$OMUT" o_a o_i

OMUT="$(o_copia m4)"; o_muta "$OM/m4/comum/rastro.sh" \
  '    elif [ -n "$sessao_tid" ] && [ "$sessao_tid" != "$pedido" ]; then' '    elif false; then'
o_mutante "om-mutante-4-aceita-trabalho-divergente" $? "$OMUT" o_e

# Sem o filtro de sessao no helper, as duas sessoes passam a enxergar as duas
# reivindicacoes — e e assim que dois trabalhos cruzariam o mesmo arquivo.
OMUT="$(o_copia m5)"; o_muta "$OM/m5/comum/rastro.sh" \
  'if (_rv_dono[k] == "" || _rv_dono[k] != ses) continue' 'if (_rv_dono[k] == "") continue'
o_mutante "om-mutante-5-sessoes-cruzam-arquivos" $? "$OMUT" o_a o_d o_f o_j

# O trabalho que o escopo-da-task entrega ao rastro.sh volta a sair do mtime.
OMUT="$(o_copia m6)"; o_muta "$OM/m6/sprintx/escopo-da-task.sh" '  RASTRO_TRABALHO_DA_SESSAO="$TRABALHO"' \
  '  RASTRO_TRABALHO_DA_SESSAO="$(ls -t "$RAIZ/docs/sprintx/features" 2>/dev/null | head -1)"'
o_mutante "om-mutante-6-escopo-destino-por-mtime" $? "$OMUT" o_a o_d

DSF5="$SK/DECISOES-DA-SKILL.md"
[ "$(grep -c '^| DS-155 |' "$DSF5")" -eq 1 ] && tem "$DSF5" 'rastro_grava_trabalho' \
  && tem "$SK/references/08-rastro.md" 'Em qual arquivo o evento entra' \
  && tem "$SK/references/08-rastro.md" 'nunca seleciona o destino'
afirma "o-ds155-registrada" $? "DECISOES-DA-SKILL.md e 08-rastro.md"

rm -rf "$OF_DIR"

echo "== P. TDD-first: o replanejamento preserva o trabalho parcial seguro da task bloqueada (P0.2-C7-B S3-A) =="
# O diagnostico B1.5, literal: a task escreve o proprio teste (declarado nela), prova o
# vermelho, tenta o arquivo X que o plano da so a uma irma, o escopo barra, B-NN
# defeito_de_plano — e o replanejamento recusava a fronteira porque o teste estava sujo,
# contra a ordem TDD da propria F6. Agora o teste da task bloqueada e preservado (path, estado
# e hash no 00-PLANEJAMENTO.md commitado), o plano ganha X, a F5 aprova, a task volta, X e
# implementado, verde, e o E1 leva o teste. Cada caso e <planejamento.sh> <dir>, como na K,
# para os mutantes rodarem exatamente a mesma bateria.
P="$(mktemp -d)"
PH="$H/sprintx/escopo-da-task.sh"
PT=tests/menu/perfil.test.sh; PX=src/menu/visibilidade.sh; PI=src/menu/perfil.sh
p_plano() { # p_plano <dir> <status T-04.03> <altera T-04.03> [altera T-04.04] [cria T-04.03] [cria T-04.04]
  k_sprint "$(kf "$1")/sprint-04/tasks.md" 04 plano \
    "T-04.01|concluida|src/menu/organizacao.sh||" \
    "T-04.02|concluida|$PX, tests/menu/visibilidade.test.sh||T-04.01" \
    "T-04.03|$2|${5-$PI, $PT}|$3|T-04.02" \
    "T-04.04|pendente|${6:-src/menu/rotas.sh}|${4:-}|T-04.03" \
    "T-04.05|pendente|src/menu/icones.sh||"
}
# p_fx <dir> — o piloto aprovado, em F6: T-04.01 e T-04.02 concluidas com o produto
# commitado pelo E1 (X = src/menu/visibilidade.sh e so da T-04.02); T-04.03 em andamento pela
# sessao teste@eu. Arvore limpa.
p_fx() {
  local d="$1"
  k_fx "$d" 0 3 buildx 1 || return 1
  mkdir -p "$d/src/menu" "$d/tests/menu"
  printf 'organizacao() { :; }\n' > "$d/src/menu/organizacao.sh"
  printf 'visivel() { printf "menu-%%s" "$1"; }\n' > "$d/$PX"
  printf '#!/bin/sh\n. ./%s && [ "$(visivel admin)" = menu-admin ]\n' "$PX" > "$d/tests/menu/visibilidade.test.sh"
  p_plano "$d" em_andamento ""
  git -C "$d" add -A && git -C "$d" commit -q -m "feat(menu): T-04.01 e T-04.02 (E1)" || return 1
  grava_evento_menu "$d" task_iniciada T-04.03 teste@eu
  [ -z "$(git -C "$d" status --porcelain)" ]
}
P_RC=0; P_SAIDA=""; P_H0=""
p_hook() { P_SAIDA="$(roda_hook_menu "$1" "$PH" "$2" teste@eu)"; P_RC=$?; }
p_parc() { tr -d '\r' | awk 'NR==1{next} $0=="---"{exit} /^parciais_replanejamento_f6:/{if ($0 ~ /\[\]/) {print "[]"; exit} b=1; next} b&&/^[^ ]/{exit} b&&/^  - path: /{p=$3; gsub(/"/,"",p)} b&&/^    task: /{t=$2} b&&/^    estado: /{e=$2} b&&/^    hash: /{print p "|" t "|" e "|" $2}'; }
p_hash() { git -C "$1" hash-object --no-filters -- "$2" 2>/dev/null; }
# p_ate_bloqueio <script> <dir> — passos 1 a 6 do B1.5: teste permitido, vermelho, X barrado, B-01, bloqueada.
p_ate_bloqueio() {
  local s="$1" d="$2"
  p_hook "$d" "$PT"; [ "$P_RC" -eq 0 ] || return 1
  printf '#!/bin/sh\n. ./%s && . ./%s && [ "$(perfil_visivel admin)" = menu-admin-completo ]\n' "$PX" "$PI" > "$d/$PT"
  (cd "$d" && sh "$PT") >/dev/null 2>&1 && return 1
  p_hook "$d" "$PX"
  [ "$P_RC" -eq 2 ] && printf '%s' "$P_SAIDA" | grep -qF arquivo_de_task_irma || return 1
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano "arquivo_de_task_irma: $PX e da T-04.02" "acrescentar $PX a T-04.03" >/dev/null || return 1
  p_plano "$d" bloqueada ""
  grava_evento_menu "$d" task_bloqueada T-04.03 teste@eu
  P_H0="$(p_hash "$d" "$PT")"; [ -n "$P_H0" ]
}
# p_so_metodo <dir> <base> — entre <base> e HEAD, nenhum commit tecnico parcial: so checkpoints da pasta da feature.
p_so_metodo() {
  local c p
  for c in $(git -C "$1" rev-list "$2..HEAD"); do
    for p in $(git -C "$1" show --name-only --format= "$c"); do case "$p" in docs/sprintx/features/menu/*) ;; *) return 1 ;; esac; done
  done
}
# P1. O cenario inteiro, sem decisao humana no meio.
p_central() {
  local s="$1" d="$2" f out base e1; f="$(kf "$d")"
  p_ate_bloqueio "$s" "$d" || return 1
  base="$(git -C "$d" rev-parse HEAD)"
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = iniciado ] && [ "$(kv "$out" estado)" = replanejar_execucao ] \
    && [ "$(kv "$out" parciais_replanejamento_f6)" = "$PT" ] \
    && [ "$(git -C "$d" show "HEAD:docs/sprintx/features/menu/00-PLANEJAMENTO.md" | p_parc)" = "$PT|T-04.03|novo|$P_H0" ] \
    && [ "$(p_hash "$d" "$PT")" = "$P_H0" ] && [ "$(git -C "$d" status --porcelain -- "$PT")" = "?? $PT" ] || return 1
  # Retomada com a arvore intacta: mesma rodada, nada consumido.
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = retomada ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] || return 1
  # F3: X entra em `altera` da T-04.03; o parcial continua so dela.
  p_plano "$d" bloqueada "$PX"
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 2 SIM; out="$(kpl "$s" "$d" avanca menu f5)" || return 1
  [ "$(kv "$out" estado)" = aprovado ] && [ "$(kv "$out" proxima)" = F6 ] && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|resolvido" ] \
    && [ "$(kst "$d" T-04.03)" = pendente ] && [ "$(p_parc < "$f/00-PLANEJAMENTO.md")" = "[]" ] \
    && [ "$(p_hash "$d" "$PT")" = "$P_H0" ] && p_so_metodo "$d" "$base" && [ -z "$(git -C "$d" stash list)" ] || return 1
  # A F6 retoma a T-04.03: X agora e dela. Implementa; verde.
  p_plano "$d" em_andamento "$PX"; grava_evento_menu "$d" task_iniciada T-04.03 teste@eu
  p_hook "$d" "$PX"; [ "$P_RC" -eq 0 ] || return 1
  p_hook "$d" "$PI"; [ "$P_RC" -eq 0 ] || return 1
  printf 'perfil_visivel() { printf "%%s-completo" "$(visivel "$1")"; }\n' > "$d/$PI"
  printf 'visivel() { printf "menu-%%s" "$1"; }\nvisivel_de() { visivel "$1"; }\n' > "$d/$PX"
  (cd "$d" && sh "$PT") >/dev/null 2>&1 || return 1
  # E1, como a mergex o faz: os arquivos de produto declarados da task mais a pasta da feature.
  p_plano "$d" concluida "$PX"; grava_evento_menu "$d" task_concluida T-04.03 teste@eu
  git -C "$d" add -- "$PI" "$PT" "$PX" docs/sprintx/features/menu && git -C "$d" commit -q -m "feat(menu): T-04.03 (E1)" || return 1
  e1="$(git -C "$d" show --name-only --format= HEAD | grep -v '^docs/sprintx/features/menu/' | LC_ALL=C sort | tr '\n' ' ')"
  [ "$e1" = "$PI $PX $PT " ] && [ "$(git -C "$d" rev-parse "HEAD:$PT")" = "$P_H0" ] \
    && [ -z "$(git -C "$d" status --porcelain)" ] && [ "$(kv "$(kpl "$s" "$d" fase menu)" fase)" = F6 ] \
    && (cd "$d" && sh "$PT") >/dev/null 2>&1
}
# p_recusa <script> <dir> <item esperado em nao_preservaveis> [teste-preservavel:1|0] — codigo 2,
# fronteira_insegura, nada gravado, nada limpo; por padrao o teste da propria task nao aparece
# entre os nao preservaveis (a recusa e pelo OUTRO path).
p_recusa() {
  local s="$1" d="$2" f ck h st out rc np; f="$(kf "$d")"
  ck="$(cksum < "$f/00-PLANEJAMENTO.md")"; h="$(git -C "$d" rev-parse HEAD)"; st="$(git -C "$d" status --porcelain | cksum)"
  out="$(kpl "$s" "$d" replanejar-execucao menu)"; rc=$?
  np=",$(kv "$out" nao_preservaveis),"
  [ "$rc" -eq 2 ] && [ "$(kv "$out" motivo)" = fronteira_insegura ] \
    && case "$np" in *",$3,"*) true ;; *) false ;; esac && { [ "${4:-1}" = 0 ] || case "$np" in *",$PT("*) false ;; *) true ;; esac; } \
    && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] \
    && [ "$(git -C "$d" status --porcelain | cksum)" = "$st" ] && [ -z "$(git -C "$d" stash list)" ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = aprovado ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ] \
    && [ "$(p_hash "$d" "$PT")" = "$P_H0" ]
}
# P2. Dirty da propria task + dirty de irma.
p_irma() {
  p_ate_bloqueio "$1" "$2" || return 1
  printf 'rotas() { :; }\n' > "$2/src/menu/rotas.sh"
  p_recusa "$1" "$2" "src/menu/rotas.sh(task_irma:T-04.04)"
}
# P3. Dirty da propria task + stage (outro arquivo da propria task no indice).
p_stage() {
  p_ate_bloqueio "$1" "$2" || return 1
  printf 'perfil_visivel() { :; }\n' > "$2/$PI"; git -C "$2" add -- "$PI"
  p_recusa "$1" "$2" "$PI(staged)"
}
# P4. O mesmo teste declarado na corrente E numa irma: nao se atribui a uma task so.
p_compartilhado() {
  p_ate_bloqueio "$1" "$2" || return 1
  p_plano "$2" bloqueada "" "$PT"
  p_recusa "$1" "$2" "$PT(compartilhado:T-04.03,T-04.04)" 0 && [ "$(kst "$2" T-04.03)" = bloqueada ]
}
# P5. Arquivo de task concluida sujo na arvore.
p_concluida() {
  p_ate_bloqueio "$1" "$2" || return 1
  printf 'organizacao() { echo mexido; }\n' > "$2/src/menu/organizacao.sh"
  p_recusa "$1" "$2" "src/menu/organizacao.sh(task_concluida:T-04.01)"
}
# P6. O hash muda durante o replanejamento: todo portao para (codigo 2), nada gravado; com o
# conteudo de volta, byte a byte, a rodada segue — a prova e o hash, nao a data.
p_hash_muda() {
  local s="$1" d="$2" f ck h out rc orig; f="$(kf "$d")"
  p_ate_bloqueio "$s" "$d" || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  p_plano "$d" bloqueada "$PX"; orig="$(cat "$d/$PT")"
  printf '# ajuste feito durante o replanejamento\n' >> "$d/$PT"
  ck="$(cksum < "$f/00-PLANEJAMENTO.md")"; h="$(git -C "$d" rev-parse HEAD)"
  out="$(kpl "$s" "$d" avanca menu f3)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" motivo)" = parcial_divergente ] && [ "$(kv "$out" trabalho_parcial)" = divergente ] \
    && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = replanejar_execucao ] || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" motivo)" = parcial_divergente ] || return 1
  out="$(kpl "$s" "$d" fase menu)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" fase)" = PARAR ] && [ "$(kv "$out" trabalho_parcial)" = divergente ] \
    && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] || return 1
  printf '%s\n' "$orig" > "$d/$PT"; [ "$(p_hash "$d" "$PT")" = "$P_H0" ] || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = aguardando_f4 ]
}
# P7. O plano novo tira o parcial da task bloqueada: move para irma, remove de todas, torna
# ambiguo, atribui a concluida. Codigo 4 em cada portao, nada registrado; o plano certo passa.
p_ownership() {
  local s="$1" d="$2" f ck rc m out; f="$(kf "$d")"
  p_ate_bloqueio "$s" "$d" || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  ck="$(cksum < "$f/00-PLANEJAMENTO.md")"
  for m in irma nenhuma ambiguo; do
    case "$m" in
      irma) p_plano "$d" bloqueada "$PX" "" "$PI" "src/menu/rotas.sh, $PT" ;;
      nenhuma) p_plano "$d" bloqueada "$PX" "" "$PI" ;;
      ambiguo) p_plano "$d" bloqueada "$PX" "$PT" ;;
    esac
    out="$(kpl "$s" "$d" avanca menu f3)"; rc=$?
    [ "$rc" -eq 4 ] && [ "$(printf '%s' "$out" | grep -cF 'trabalho parcial preservado')" -ge 1 ] \
      && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = replanejar_execucao ] || return 1
  done
  # Concluida: a T-04.02 congelada ganharia o teste — o congelamento ja barra (codigo 4).
  k_sprint "$f/sprint-04/tasks.md" 04 plano "T-04.01|concluida|src/menu/organizacao.sh||" \
    "T-04.02|concluida|$PX, tests/menu/visibilidade.test.sh, $PT||T-04.01" "T-04.03|bloqueada|$PI|$PX|T-04.02" \
    "T-04.04|pendente|src/menu/rotas.sh||T-04.03" "T-04.05|pendente|src/menu/icones.sh||"
  kpl "$s" "$d" avanca menu f3 >/dev/null; rc=$?
  [ "$rc" -eq 4 ] && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] || return 1
  p_plano "$d" bloqueada "$PX"
  kpl "$s" "$d" avanca menu f3 >/dev/null && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = aguardando_f4 ]
}
# P8. Worktree perdida: um clone da branch tem o estado versionado, e nao o conteudo parcial.
# Nada e reconstruido: fase, retomada e portao param com `parcial_perdido`, sem gravar nada.
p_perdido() {
  local s="$1" d="$2" c out rc h ck
  p_ate_bloqueio "$s" "$d" || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  c="$(mktemp -d "$P/clone.XXXXXX")"; rm -rf "$c"
  git clone -q -c core.autocrlf=false -b feature/menu "$d" "$c" || return 1
  rm -rf "$d"; [ ! -e "$d" ] && [ ! -e "$c/$PT" ] || return 1
  h="$(git -C "$c" rev-parse HEAD)"; ck="$(cksum < "$(kf "$c")/00-PLANEJAMENTO.md")"
  [ "$(p_parc < "$(kf "$c")/00-PLANEJAMENTO.md")" = "$PT|T-04.03|novo|$P_H0" ] || return 1
  out="$(kpl "$s" "$c" fase menu)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" fase)" = PARAR ] && [ "$(kv "$out" trabalho_parcial)" = perdido ] || return 1
  out="$(kpl "$s" "$c" replanejar-execucao menu)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" motivo)" = parcial_perdido ] && [ "$(kv "$out" proxima)" = PARAR ] || return 1
  p_plano "$c" bloqueada "$PX"
  out="$(kpl "$s" "$c" avanca menu f3)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" motivo)" = parcial_perdido ] || return 1
  out="$(kpl "$s" "$c" fase menu)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" trabalho_parcial)" = perdido ] \
    && [ "$(git -C "$c" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$(kf "$c")/00-PLANEJAMENTO.md")" = "$ck" ] \
    && [ ! -e "$c/$PT" ] && [ -z "$(git -C "$c" status --porcelain -- src tests)" ] \
    && [ "$(fmv "$(kf "$c")/00-PLANEJAMENTO.md" estado)" = replanejar_execucao ]
}
# P9. O mesmo ciclo numa worktree vinculada (`.git` e arquivo), com a principal em outra branch.
p_central_worktree() {
  local s="$1" d="$2" w="$2--wt"
  git -C "$d" switch -q main 2>/dev/null || git -C "$d" checkout -q main || return 1
  git -C "$d" worktree add -q "$w" feature/menu || return 1
  [ -f "$w/.git" ] || return 1
  grava_evento_menu "$w" task_iniciada T-04.03 teste@eu
  p_central "$s" "$w"
}
FXPP="$P/fx"; p_fx "$FXPP"; afirma "p0-fixture-tdd-first" $? "F6 aprovada, T-04.02 concluida com X commitado, T-04.03 em andamento pela sessao"
pcopia() { local d; d="$(mktemp -d "$P/c.XXXXXX")"; rm -rf "$d"; cp -R "$FXPP" "$d"; printf '%s' "$d"; }
roda_p() { "$1" "$2" "$(pcopia)"; }
for par in p_central:p1-tdd-first-teste-preservado-ate-o-e1 p_irma:p2-propria-mais-irma-para \
  p_stage:p3-propria-mais-stage-para p_compartilhado:p4-compartilhado-current-irma-nao-preservavel \
  p_concluida:p5-task-concluida-suja-para p_hash_muda:p6-hash-muda-no-replanejamento-para \
  p_ownership:p7-plano-novo-tira-o-parcial-da-task-para p_perdido:p8-worktree-perdida-fail-closed \
  p_central_worktree:p9-tdd-first-em-worktree-vinculada; do
  roda_p "${par%%:*}" "$PL"; afirma "${par#*:}" $? "${par%%:*}"
done

# Contrato nos documentos e a lista de segredo sem deriva.
SCHP="$SK/references/00-schema.md"
tem "$SCHP" '`parciais_replanejamento_f6`' && tem "$SCHP" 'parcial_perdido' && tem "$EXEC" 'parciais_replanejamento_f6' \
  && tem "$EXEC" '`motivo=parcial_perdido`' && tem "$SK/references/03-plano.md" 'trabalho parcial preservado' \
  && tem "$SK/assets/TEMPLATE-PLANEJAMENTO.md" 'parciais_replanejamento_f6: []' \
  && [ "$(grep -c '^| DS-156 |' "$SK/DECISOES-DA-SKILL.md")" -eq 1 ]
afirma "p10-contrato-do-trabalho-parcial" $? "schema, 06-execucao, 03-plano, template e DS-156"
seg_hook="$(sed -n "/^PADROES_SEGREDO=\\|^done <<'PADROES'\$/,/^PADROES\$/p" "$H/comum/segredo.sh" | grep '|' | sed 's/^[^|]*|//')"
seg_pl="$(sed -n "/^SEGREDO_PADROES='/,/'\$/p" "$PL" | sed "s/^SEGREDO_PADROES='//; s/'\$//")"
[ -n "$seg_pl" ] && [ "$seg_hook" = "$seg_pl" ]
afirma "p11-segredo-mesma-lista-do-hook" $? "planejamento.sh e comum/segredo.sh"

# Mutantes do S3-A, em copia da skill (como na K). Cada um morre pelo caso designado; o
# controle, copia sem mutacao, sobrevive a todos.
MP="$P/mut"
copia_skill_p() { mkdir -p "$MP/$1/scripts" "$MP/$1/assets"; cp "$SK/assets/TEMPLATE-PLANEJAMENTO.md" "$SK/assets/TEMPLATE-BLOQUEIOS.md" "$MP/$1/assets/"; cp "$BL" "$SK/scripts/caminho-git.sh" "$MP/$1/scripts/"; printf '%s/%s/scripts/planejamento.sh' "$MP" "$1"; }
mutante_p() { # mutante_p <nome> <rc da geracao> <script> <caso que TEM de matar>...
  local nome="$1" rc="$2" s="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do roda_p "$c" "$s" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]; afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
CTLP="$(copia_skill_p controle)"; cp "$PL" "$CTLP"; vivosp=""
for c in p_central p_irma p_stage p_compartilhado p_concluida p_hash_muda p_ownership p_perdido; do roda_p "$c" "$CTLP" || vivosp="$vivosp$c "; done
[ -z "$vivosp" ]; afirma "pm-controle-copia-intacta-sobrevive" $? "${vivosp:-nenhum caso designado reprova a copia sem mutacao}"
M="$(copia_skill_p a)"; muta_lit "$PL" "$M" '    cand="$cand$p$TAB$tasks$TAB$e$TAB$h' '    sujos="$sujos $p(sujo)"; continue; cand="$cand$p$TAB$tasks$TAB$e$TAB$h'
mutante_p "pm-mutante-1-todo-dirty-da-corrente-rejeitado" $? "$M" p_central
M="$(copia_skill_p b)"; muta_lit "$PL" "$M" '          elif ! em_lista "$tasks" "$BLOQ_TASKS"; then veredito="task_irma:$tasks"' '          elif false; then veredito="task_irma:$tasks"'
mutante_p "pm-mutante-2-dirty-de-irma-preservado" $? "$M" p_irma
M="$(copia_skill_p c)"; muta_lit "$PL" "$M" '          elif [ "$n" -gt 1 ]; then veredito="compartilhado:$tasks"' '          elif [ "$n" -gt 1 ]; then tasks="${tasks%%,*}"'
mutante_p "pm-mutante-3-dirty-compartilhado-preservado" $? "$M" p_compartilhado
M="$(copia_skill_p d)"; muta_lit "$PL" "$M" '  [ "$R_TSV" = "$esperado" ] && return 0' \
  '  [ "$(printf '"'"'%s\n'"'"' "$R_TSV" | cut -f1,2)" = "$(printf '"'"'%s\n'"'"' "$esperado" | cut -f1,2)" ] && return 0'
mutante_p "pm-mutante-4-hash-nao-verificado" $? "$M" p_hash_muda
M="$(copia_skill_p e)"; muta_lit "$PL" "$M" '    [ -z "$P_PARC" ] || { D_PARC=perdido; D_DET=" $(printf '"'"'%s\n'"'"' "$P_PARC" | cut -f1 | tr '"'"'\n'"'"' '"'"' '"'"')"; }' '    :'
mutante_p "pm-mutante-5-worktree-perdida-segue-integra" $? "$M" p_perdido
M="$(copia_skill_p f)"; muta_lit "$PL" "$M" '  [ -z "$ruins" ] && return 0' '  return 0'
mutante_p "pm-mutante-6-plano-novo-move-o-parcial" $? "$M" p_ownership
M="$(copia_skill_p g)"; muta_lit "$PL" "$M" '  f6_herda; W6_BLQ=""; W6_CONG=""; W6_ASS=null; W6_PARC=""' \
  '  printf '"'"'%s\n'"'"' "$P_PARC" | while IFS="$TAB" read -r p t e h; do [ -n "$p" ] && rm -f "$RAIZ/$p"; done; f6_herda; W6_BLQ=""; W6_CONG=""; W6_ASS=null; W6_PARC=""'
mutante_p "pm-mutante-7-e1-sem-o-teste-preservado" $? "$M" p_central

rm -rf "$P"

echo "== Q. custo dos hooks criticos: poucos processos, timeout como margem (P0.2-C7-B S3-B) =="
# O runner cancela o hook que estoura o timeout e deixa a ferramenta EXECUTAR: timeout e
# falha aberta. A garantia primaria e o hook nao criar processo (no Git Bash cada um custa de
# 0,5 a 2 s); o timeout maior dos tres criticos e so margem. Os processos externos sao
# contados por shims no PATH — o mesmo em Linux e no Git Bash; builtin do bash nao passa por eles.
Q="$(mktemp -d)"; mkdir -p "$Q/shim"
for c in awk jq grep sed cut tr wc sort head tail find cat date mkdir dirname basename xargs ps mv git ls uniq env python3 od; do
  r="$(command -v "$c" 2>/dev/null)"; case "$r" in */*) ;; *) continue ;; esac
  printf '#!/bin/sh\nprintf "%%s\\n" "%s" >> "$Q_LOG"\nexec "%s" "$@"\n' "$c" "$r" > "$Q/shim/$c"; chmod +x "$Q/shim/$c"
done
q_fx() { # q_fx <dir> — 4 sprints x 6 tasks no formato do template (frontmatter + prosa), rastro com a reivindicacao
  local d="$1" F s t st; rm -rf "$d"; mkdir -p "$d/.git" "$d/docs/eventos"; F="$d/docs/sprintx/features/menu"
  for s in 01 02 03 04; do
    mkdir -p "$F/sprint-$s"
    {
      printf -- '---\nexpx_schema: 1\nkind: tasks\ntrabalho_id: menu\nsprint_id: sprint-%s\ntasks:\n' "$s"
      for t in 01 02 03 04 05 06; do
        st=concluida; [ "$s" = 04 ] && st=pendente; [ "$s$t" = 0403 ] && st=em_andamento
        printf '  - id: T-%s.%s\n    status: %s\n    arquivos:\n      cria: [src/m%s/t%s.ts, tests/m%s/t%s.test.ts]\n      altera: []\n' "$s" "$t" "$st" "$s" "$t" "$s" "$t"
      done
      printf -- '---\n\n'
      for t in 01 02 03 04 05 06; do printf -- '```yaml\nid: T-%s.%s\narquivos:\n  cria: [src/m%s/t%s.ts]\n  altera: []\n```\n\n' "$s" "$t" "$s" "$t"; done
    } > "$F/sprint-$s/tasks.md"
  done
  printf '{"trabalho_id":"menu","evento":"task_iniciada","task":"T-04.03","sessao":"q@1"}\n' > "$d/docs/eventos/menu.jsonl"
  printf '{"trabalho_id":"historica","evento":"task_iniciada","task":"T-04.03","sessao":"q@9"}\n' > "$d/docs/eventos/historica.jsonl"
}
Q_N=0; Q_RC=0
q_roda() { # q_roda <raiz-hooks> <hook> <payload> — processos externos em Q_N, rc em Q_RC
  local d="$Q/r"; q_fx "$d"; : > "$Q/log"
  printf '%s' "$(printf '%s' "$3" | sed "s#@D@#$d#g")" | (cd "$d" && PATH="$Q/shim:$PATH" Q_LOG="$Q/log" EXPX_SESSAO=q@1 CLAUDECODE=1 bash "$1/$2") >/dev/null 2>&1
  Q_RC=$?; Q_N="$(grep -c '' "$Q/log")"
}
qw() { printf '{"cwd":"@D@","tool_name":"Write","tool_input":{"file_path":"@D@/%s","content":"%s"}}' "$1" "${2:-x = 1}"; }
qb() { printf '{"cwd":"@D@","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
Q_AWS="AKIA""ABCDEFGHIJKLMNOP"; Q_GF="git push"" --force origin main"
# Sem `mapfile -d` (bash < 4.4, macOS) a leitura do payload custa um `cat`: um processo a mais permitido.
Q_FOLGA=0; { [ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 4 ]; }; } || Q_FOLGA=1
# q_orcamento <raiz-hooks> <rotulo-git-perigoso> — cada cenario decide certo (rc) e cabe no orcamento:
# caminho comum ate 2 processos externos, bloqueio ate 3. Imprime o que custou cada um.
Q_CUSTO=""
q_orcamento() {
  local H2="$1" GP="$2" c nome hook pl rc max ruim=""
  Q_CUSTO=""
  while IFS='|' read -r nome hook rc max pl; do
    [ -n "$nome" ] || continue
    q_roda "$H2" "$hook" "$(eval "printf '%s' \"$pl\"")"
    Q_CUSTO="$Q_CUSTO $nome=$Q_N"
    [ "$Q_RC" -eq "$rc" ] && [ "$Q_N" -le $((max + Q_FOLGA)) ] || ruim="$ruim $nome(rc=$Q_RC,proc=$Q_N)"
  done <<EOF
escopo-corrente|sprintx/escopo-da-task.sh|0|2|\$(qw src/m04/t03.ts)
escopo-irma|sprintx/escopo-da-task.sh|2|3|\$(qw src/m04/t04.ts)
escopo-concluida|sprintx/escopo-da-task.sh|2|3|\$(qw src/m01/t01.ts)
escopo-fora|sprintx/escopo-da-task.sh|0|3|\$(qw src/outro.ts)
segredo-limpo|comum/segredo.sh|0|2|\$(qw src/a.ts)
segredo-achado|comum/segredo.sh|2|3|\$(qw src/a.ts \$Q_AWS)
git-inocuo|$GP|0|2|\$(qb 'git status')
git-perigoso|$GP|2|3|\$(qb "\$Q_GF")
EOF
  [ -z "$ruim" ] || { Q_CUSTO="$Q_CUSTO — FORA:$ruim"; return 1; }
}
# q_timeouts <settings.json> <plugin.ts> — os tres criticos com 30 s, todo o resto com 10 s, nos dois harnesses.
q_timeouts() {
  tr -d '\r' < "$1" | awk '
    /"command":/ { c = $0; next }
    /"timeout":/ { t = $0; gsub(/[^0-9]/, "", t); crit = (c ~ /escopo-da-task\.sh|segredo\.sh|git-perigoso\.sh/)
                   if (crit) { nc++; if (t != 30) ruim = 1 } else if (t != 10) ruim = 1 }
    END { exit (ruim || nc != 3) }' \
  && [ "$(tr -d '\r' < "$2" | grep -cF 'timeout: CRITICOS.has(caminhoRelativo) ? 30_000 : 10_000')" -eq 1 ] \
  && [ "$(tr -d '\r' < "$2" | grep -c 'const CRITICOS = new Set(\[.*"sprintx/escopo-da-task.sh".*"comum/segredo.sh".*git-perigoso.sh"\])')" -eq 1 ]
}
# q_criticos <raiz-hooks> <settings> <plugin> <git-perigoso> — a solucao inteira: timeout como margem E custo baixo.
q_criticos() { q_timeouts "$2" "$3" && q_orcamento "$1" "$4"; }
QGP=sprintx/git-perigoso.sh
q_orcamento "$H" "$QGP"; afirma "q1-orcamento-de-processos-dos-criticos" $? "externos por execucao:$Q_CUSTO"
q_timeouts "$H/../settings.json" "$H/../../.opencode/plugin/sprintx.ts"; afirma "q2-timeout-30s-so-nos-tres-criticos" $? "settings.json e plugin do OpenCode"
tem "$SKILLMD" 'timeout do runner é falha aberta' && tem "$SKILLMD" 'primeira barreira' && tem "$SKILLMD" 'E1 da `mergex`' \
  && [ "$(grep -c '^| DS-157 |' "$SK/DECISOES-DA-SKILL.md")" -eq 1 ]
afirma "q3-contrato-fail-open-e-backstop" $? "SKILL.md e DS-157"

# L-prosa. A prosa repete o bloco ```yaml de cada task; a task corrente e a ULTIMA do
# frontmatter; o arquivo e so de uma irma. Tem de bloquear (lia-se a prosa como da ultima task).
l_prosa() {
  l_fixture
  c2_abre 04 "$C2OC/sprint-04/tasks.md"
  c2_tarefa "$C2OC/sprint-04/tasks.md" T-04.01 pendente "src/menu/irma.ts" ""
  c2_tarefa "$C2OC/sprint-04/tasks.md" T-04.03 em_andamento "" "src/ui/cabecalho-topo.tsx"
  c2_fecha "$C2OC/sprint-04/tasks.md"
  printf '\n```yaml\nid: T-04.01\narquivos:\n  cria: [src/menu/irma.ts]\n  altera: []\n```\n\n```yaml\nid: T-04.03\narquivos:\n  cria: []\n  altera: [src/ui/cabecalho-topo.tsx]\n```\n' >> "$C2OC/sprint-04/tasks.md"
  c2_hook "$1" "src/menu/irma.ts" teste@eu
  [ $? -eq 2 ] && printf '%s' "$C2_SAIDA" | grep -qF "arquivo_de_task_irma" && printf '%s' "$C2_SAIDA" | grep -qF "(T-04.01)"
}
C2="$(mktemp -d)"
git -C "$C2" init -q -b main; C2OC="$C2/docs/sprintx/features/c2-escopo-irma"
mkdir -p "$C2OC/sprint-03" "$C2OC/sprint-04"; C2RASTRO="$C2/docs/eventos/c2-escopo-irma.jsonl"; mkdir -p "$(dirname "$C2RASTRO")"
l_prosa "$H/sprintx/escopo-da-task.sh"; afirma "q4-prosa-nao-declara-ownership" $? "corrente e a ultima task do frontmatter; o arquivo da irma na prosa continua da irma"

# Mutantes do S3-B. Copia da arvore de hooks (sprintx/ + comum/), da configuracao e do plugin.
QM="$Q/mut"
q_copia() { # q_copia <nome> — devolve a raiz de hooks copiada, com settings.json e plugin ao lado
  local d="$QM/$1"; rm -rf "$d"; mkdir -p "$d/hooks" "$d/plugin"
  cp -R "$H/sprintx" "$H/comum" "$d/hooks/"; cp "$H/../settings.json" "$d/settings.json"; cp "$H/../../.opencode/plugin/sprintx.ts" "$d/plugin/sprintx.ts"
  printf '%s' "$d"
}
q_mutante() { # q_mutante <nome> <rc geracao> <condicao que TEM de falhar...>
  local nome="$1" rc="$2"; shift 2
  if [ "$rc" -eq 0 ] && ! "$@"; then afirma "$nome" 0 "morto por: $1"; else afirma "$nome" 1 "SOBREVIVEU a: $1 (rc geracao=$rc)"; fi
}
q_controle() { # a copia sem mutacao passa em tudo que os mutantes precisam reprovar
  local c
  q_criticos "$1/hooks" "$1/settings.json" "$1/plugin/sprintx.ts" "$QGP" && l_prosa "$1/hooks/sprintx/escopo-da-task.sh" || return 1
  for c in l_a l_b l_c l_d l_e l_j; do "$c" "$1/hooks/sprintx/escopo-da-task.sh" || return 1; done
}
QC="$(q_copia controle)"; q_controle "$QC"
afirma "qm-controle-copia-intacta-sobrevive" $? "orcamento, timeouts, prosa e C2 na copia sem mutacao"
# 1. Volta ao desenho fork-heavy: find + grep por tasks.md + pipelines, como antes da DS-157.
QMU="$(q_copia m1)"; muta_lit "$QMU/hooks/sprintx/escopo-da-task.sh" "$QMU/e.m" 'rastro_raiz_em RAIZ "$CWD"' \
  'RAIZ="$(rastro_raiz "$CWD")"; for f in $(find "$RAIZ/docs" -maxdepth 5 -name tasks.md -type f 2>/dev/null); do grep -q "status: em_andamento" "$f" 2>/dev/null; done; N_X="$(printf "%s\n" x | awk NF | wc -l | tr -d " ")"' \
  && mv "$QMU/e.m" "$QMU/hooks/sprintx/escopo-da-task.sh"
q_mutante "qm-mutante-1-volta-ao-fork-heavy" $? q_orcamento "$QMU/hooks" "$QGP"
# 2. O timeout critico volta a 10 s.
QMU="$(q_copia m2)"; awk '/escopo-da-task\.sh/ { e = 1 } e && /"timeout": 30/ { sub(/30/, "10"); e = 0 } { print }' "$QMU/settings.json" > "$QMU/s.m" && ! cmp -s "$QMU/s.m" "$QMU/settings.json" && mv "$QMU/s.m" "$QMU/settings.json"
q_mutante "qm-mutante-2-timeout-critico-volta-a-10" $? q_timeouts "$QMU/settings.json" "$QMU/plugin/sprintx.ts"
# 3. Timeout aumentado SEM a otimizacao: o hook fork-heavy com 30 s nao e solucao suficiente.
QMU="$(q_copia m3)"; muta_lit "$QMU/hooks/comum/rastro.sh" "$QMU/r.m" 'rastro_le_entrada_em() {' \
  'rastro_le_entrada_em() { local _i; for _i in 1 2 3 4 5 6; do date >/dev/null; done; printf -v "$1" "%s" "$(cat)"; return 0' \
  && mv "$QMU/r.m" "$QMU/hooks/comum/rastro.sh"
q_mutante "qm-mutante-3-timeout-maior-sem-otimizacao" $? q_criticos "$QMU/hooks" "$QMU/settings.json" "$QMU/plugin/sprintx.ts" "$QGP"
# 4. O atalho do caminho comum muda a semantica C2: arquivo so de irma passa como da corrente.
QMU="$(q_copia m4)"; muta_lit "$QMU/hooks/sprintx/escopo-da-task.sh" "$QMU/e.m" '  case "$DECL" in corrente|vazio) exit 0 ;; esac' \
  '  case "$DECL" in corrente|vazio|irma) exit 0 ;; esac' && mv "$QMU/e.m" "$QMU/hooks/sprintx/escopo-da-task.sh"
q_mutante "qm-mutante-4-escopo-muda-semantica-irma-corrente" $? l_c "$QMU/hooks/sprintx/escopo-da-task.sh"
# 5. A prosa volta a declarar ownership (a leitura de antes).
QMU="$(q_copia m5)"; muta_lit "$QMU/hooks/sprintx/escopo-da-task.sh" "$QMU/e.m" '  FNR > 1 && FM && $0 == "---" { FORA = 1; AT = "" }' \
  '  FNR > 1 && FM && $0 == "---" { FORA = 0 }' && mv "$QMU/e.m" "$QMU/hooks/sprintx/escopo-da-task.sh"
q_mutante "qm-mutante-5-prosa-volta-a-declarar-ownership" $? l_prosa "$QMU/hooks/sprintx/escopo-da-task.sh"
rm -rf "$Q" "$C2"

echo "== R. git-perigoso com o namespace da skill, em qualquer ordem de instalacao (P0.2-C7-B S3-C) =="
# A mergex publica um git-perigoso proprio em comum/, com regras dela. O da sprintx mora em
# sprintx/, com o id sprintx/git-perigoso no .expx/hooks.json: nenhum sobrescreve o outro, e o
# modo de um nao liga nem desliga o outro. Cada caso recebe a raiz de uma arvore de fonte da
# sprintx (a do repositorio, ou a copia de um mutante).
R="$(mktemp -d)"
r_fonte() { # r_fonte <nome> — copia o que o install.sh publica
  local d="$R/fonte-$1"; rm -rf "$d"; mkdir -p "$d"
  cp -R "$RAIZ_SRC/.claude" "$RAIZ_SRC/.opencode" "$RAIZ_SRC/.expx" "$RAIZ_SRC/install.sh" "$d/"
  printf '%s' "$d"
}
# R1. O arquivo, o registro nos dois harnesses e o id do modo carregam o namespace.
r_caminhos() {
  local f="$1"
  [ -f "$f/.claude/hooks/sprintx/git-perigoso.sh" ] && [ ! -e "$f/.claude/hooks/comum/git-perigoso.sh" ] \
    && [ "$(grep -cF '/.claude/hooks/sprintx/git-perigoso.sh"' "$f/.claude/settings.json")" -eq 1 ] \
    && [ "$(grep -cF 'comum/git-perigoso' "$f/.claude/settings.json")" -eq 0 ] \
    && [ "$(grep -cF '"sprintx/git-perigoso.sh"' "$f/.opencode/plugin/sprintx.ts")" -eq 2 ] \
    && [ "$(grep -cF 'comum/git-perigoso' "$f/.opencode/plugin/sprintx.ts")" -eq 0 ] \
    && [ "$(grep -cF '"sprintx/git-perigoso": {' "$f/.expx/hooks.json")" -eq 1 ] \
    && [ "$(grep -cF '"git-perigoso":' "$f/.expx/hooks.json")" -eq 0 ] \
    && [ "$(grep -cF 'sprintx/git-perigoso' "$f/.claude/hooks/doctor.sh")" -ge 1 ]
}
# R2. O modo sai do id com namespace: o git-perigoso de outra skill desligado nao desliga este.
r_modo() {
  local f="$1" d="$R/modo" pl cmd="git push"" --force origin main"
  rm -rf "$d"; mkdir -p "$d/.git" "$d/.expx"
  pl="$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$d" "$cmd")"
  r_hook() { printf '%s' "$pl" | (cd "$d" && EXPX_SESSAO=r@1 bash "$f/.claude/hooks/sprintx/git-perigoso.sh") >/dev/null 2>&1; }
  printf '{"hooks":{"git-perigoso":{"modo":"desligado"}}}' > "$d/.expx/hooks.json"; r_hook; [ $? -eq 2 ] || return 1
  printf '{"hooks":{"sprintx/git-perigoso":{"modo":"desligado"}}}' > "$d/.expx/hooks.json"; r_hook; [ $? -eq 0 ] || return 1
  printf '{\n  "hooks": {\n    "sprintx/git-perigoso": { "modo": "bloqueio" }\n  }\n}\n' > "$d/.expx/hooks.json"; r_hook; [ $? -eq 2 ] || return 1
  rm -f "$d/.expx/hooks.json"; r_hook; [ $? -eq 2 ]
}
# R3. Instalacao nas duas ordens, e o legado: o hook da mergex nunca e apagado nem sobrescrito,
# o da sprintx sempre chega, e o comum/git-perigoso.sh antigo DA SPRINTX sai.
r_mergex() { # r_mergex <projeto> — uma instalacao sintetica da mergex (copia de arvore, como ela faz)
  mkdir -p "$1/.claude/hooks/comum" "$1/.claude/hooks/mergex"
  printf '#!/usr/bin/env bash\n# git-perigoso da mergex: outras regras\nexit 0\n' > "$1/.claude/hooks/comum/git-perigoso.sh"
  printf '#!/usr/bin/env bash\n# base da mergex\n' > "$1/.claude/hooks/comum/base.sh"
  printf '#!/usr/bin/env bash\n# commit por task\n' > "$1/.claude/hooks/mergex/commit-por-task.sh"
}
r_ck_mergex() { cat "$1/.claude/hooks/comum/git-perigoso.sh" "$1/.claude/hooks/comum/base.sh" "$1/.claude/hooks/mergex/commit-por-task.sh" 2>/dev/null | cksum; }
r_instala() {
  local f="$1" p ck
  # mergex primeiro, sprintx depois
  p="$R/p1"; rm -rf "$p"; mkdir -p "$p"; r_mergex "$p"; ck="$(r_ck_mergex "$p")"
  bash "$f/install.sh" --claude "$p" >/dev/null 2>&1 || return 1
  [ "$(r_ck_mergex "$p")" = "$ck" ] && cmp -s "$p/.claude/hooks/sprintx/git-perigoso.sh" "$f/.claude/hooks/sprintx/git-perigoso.sh" || return 1
  # sprintx primeiro, mergex depois
  p="$R/p2"; rm -rf "$p"; mkdir -p "$p"
  bash "$f/install.sh" --claude "$p" >/dev/null 2>&1 || return 1
  r_mergex "$p"
  cmp -s "$p/.claude/hooks/sprintx/git-perigoso.sh" "$f/.claude/hooks/sprintx/git-perigoso.sh" \
    && [ "$(grep -cF '/.claude/hooks/sprintx/git-perigoso.sh"' "$p/.claude/settings.json")" -eq 1 ] || return 1
  # reinstalar a sprintx por cima das duas nao muda nada da mergex
  ck="$(r_ck_mergex "$p")"; bash "$f/install.sh" --claude "$p" >/dev/null 2>&1 || return 1
  [ "$(r_ck_mergex "$p")" = "$ck" ] || return 1
  # so-OpenCode num projeto em que a mergex ja criou .claude/hooks/: os da sprintx chegam
  p="$R/p3"; rm -rf "$p"; mkdir -p "$p"; r_mergex "$p"; ck="$(r_ck_mergex "$p")"
  bash "$f/install.sh" --opencode "$p" >/dev/null 2>&1 || return 1
  [ -f "$p/.claude/hooks/sprintx/git-perigoso.sh" ] && [ -f "$p/.claude/hooks/sprintx/escopo-da-task.sh" ] && [ "$(r_ck_mergex "$p")" = "$ck" ] || return 1
  # legado: o comum/git-perigoso.sh que a propria sprintx instalava sai; o resto fica
  p="$R/p4"; rm -rf "$p"; mkdir -p "$p/.claude/hooks/comum"
  printf '#!/usr/bin/env bash\nrastro_bloqueia "sprintx/git-perigoso: comando barrado — x"\n' > "$p/.claude/hooks/comum/git-perigoso.sh"
  bash "$f/install.sh" --claude "$p" >/dev/null 2>&1 || return 1
  [ ! -e "$p/.claude/hooks/comum/git-perigoso.sh" ] && [ -f "$p/.claude/hooks/sprintx/git-perigoso.sh" ]
}
RF="$(r_fonte repo)"
r_caminhos "$RF"; afirma "r1-git-perigoso-com-namespace" $? "sprintx/git-perigoso.sh e id sprintx/git-perigoso em settings, plugin, doctor e .expx/hooks.json"
r_modo "$RF"; afirma "r2-modo-pelo-id-com-namespace" $? "git-perigoso da mergex desligado nao desliga o da sprintx"
r_instala "$RF"; afirma "r3-instalacao-sem-ordem-e-sem-apagar-a-mergex" $? "mergex antes, depois, reinstalacao, so-OpenCode e legado"
tem "$SKILLMD" '`sprintx/git-perigoso`' && [ "$(grep -c '^| DS-158 |' "$SK/DECISOES-DA-SKILL.md")" -eq 1 ]
afirma "r4-contrato-do-namespace" $? "SKILL.md e DS-158"

# Mutantes do S3-C, em copia da fonte. O controle, copia sem mutacao, passa nos tres casos.
RC="$(r_fonte controle)"; r_caminhos "$RC" && r_modo "$RC" && r_instala "$RC"
afirma "rm-controle-copia-intacta-sobrevive" $? "caminhos, modo e instalacao na copia sem mutacao"
r_mutante() { # r_mutante <nome> <rc geracao> <fonte> <caso que TEM de matar>...
  local nome="$1" rc="$2" f="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do "$c" "$f" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]; afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
# 1. O caminho volta ao comum/ compartilhado com a mergex.
RM="$(r_fonte m1)"
mv "$RM/.claude/hooks/sprintx/git-perigoso.sh" "$RM/.claude/hooks/comum/git-perigoso.sh" \
  && muta_lit "$RM/.claude/hooks/comum/git-perigoso.sh" "$RM/g.m" '. "$DIR/../comum/rastro.sh"' '. "$DIR/rastro.sh"' && mv "$RM/g.m" "$RM/.claude/hooks/comum/git-perigoso.sh" \
  && muta_lit "$RM/.claude/settings.json" "$RM/s.m" '/.claude/hooks/sprintx/git-perigoso.sh"' '/.claude/hooks/comum/git-perigoso.sh"' && mv "$RM/s.m" "$RM/.claude/settings.json" \
  && muta_lit "$RM/.opencode/plugin/sprintx.ts" "$RM/p.m" '"sprintx/git-perigoso.sh"' '"comum/git-perigoso.sh"' && mv "$RM/p.m" "$RM/.opencode/plugin/sprintx.ts"
r_mutante "rm-mutante-1-caminho-volta-ao-comum" $? "$RM" r_caminhos r_instala
# 2. O manifesto e o hook voltam ao id sem namespace.
RM="$(r_fonte m2)"
muta_lit "$RM/.claude/hooks/sprintx/git-perigoso.sh" "$RM/g.m" 'rastro_modo_em MODO "$RAIZ" sprintx/git-perigoso seguranca' 'rastro_modo_em MODO "$RAIZ" git-perigoso seguranca' \
  && mv "$RM/g.m" "$RM/.claude/hooks/sprintx/git-perigoso.sh" \
  && muta_lit "$RM/.expx/hooks.json" "$RM/h.m" '"sprintx/git-perigoso": {' '"git-perigoso": {' && mv "$RM/h.m" "$RM/.expx/hooks.json"
r_mutante "rm-mutante-2-manifesto-com-id-sem-namespace" $? "$RM" r_caminhos r_modo
rm -rf "$R"

echo "== S. paths do tool input no Windows: C:\\ e C:/ decidem igual (P0.2-C7-B S3-D) =="
# O Claude Code no Windows entrega `cwd` e `tool_input.file_path` como C:\dir\arq (payload
# real capturado no runner). `${ALVO#"$RAIZ"/}` so tira prefixo com `/`: o caminho ficava
# absoluto, nao casava com `arquivos` e o hook falhava ABERTO — a irma so avisava. A semantica
# tem de ser a mesma em POSIX, C:\, C:/, misto e drive em outra caixa. Fora de MSYS/Cygwin a
# normalizacao e no-op: la C:\ nao e caminho, e nada muda.
S_WIN=0; case "${OSTYPE:-}" in msys*|cygwin*) S_WIN=1 ;; esac
S_DIR="$(mktemp -d)"
s_fx() { # s_fx <dir> — T-01.01 corrente, T-01.02 irma, uma compartilhada, nomes com espaco
  local d="$1" p="$1/docs/sprintx/features/feat/sprint-01/tasks.md"
  rm -rf "$d"; mkdir -p "$d/.git" "$d/src" "$d/docs/eventos" "${p%/*}"
  printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: tasks\ntrabalho_id: feat\nsprint_id: sprint-01\ntasks:\n' > "$p"
  printf '  - id: T-01.01\n    status: em_andamento\n    arquivos:\n      cria: ["src/com espaco/novo.ts"]\n      altera: [src/a.ts, src/shared.ts]\n' >> "$p"
  printf '  - id: T-01.02\n    status: pendente\n    arquivos:\n      cria: ["src/irma espaco/y.ts"]\n      altera: [src/shared.ts, src/irma.ts]\n---\n' >> "$p"
  printf '{"trabalho_id":"feat","evento":"task_iniciada","task":"T-01.01","sessao":"s3d@1"}\n' > "$d/docs/eventos/feat.jsonl"
}
s_json() { # s_json <cwd> <file_path> — JSON como o runner manda (barra invertida escapada)
  printf '{"session_id":"x","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' \
    "${1//\\/\\\\}" "${2//\\/\\\\}"
}
s_decide() { # s_decide <hook> <dir-posix> <cwd> <file_path> — "rc/irma|aviso|silencio|outro"
  local o r
  o="$(s_json "$3" "$4" | (cd "$2" && EXPX_SESSAO=s3d@1 bash "$1") 2>&1)"; r=$?
  case "$o" in
    *arquivo_de_task_irma*) o=irma ;; *"nao esta na lista"*) o=aviso ;; "") o=silencio ;; *) o=outro ;;
  esac
  printf '%s/%s' "$r" "$o"
}
# Os casos A..E e o que cada um TEM de decidir, em qualquer formato.
S_CASOS="A|src/a.ts|0/silencio
B|src/shared.ts|0/silencio
C|src/irma.ts|2/irma
D|src/outro.ts|0/aviso
E1|src/com espaco/novo.ts|0/silencio
E2|src/irma espaco/y.ts|2/irma"
S_FALHA=""
S_TODOS="posix win misto cwdwin-arqmisto caixa-do-drive"
s_formatos() { # s_formatos <hook> <dir-posix> <formatos> <casos> — falhas em S_FALHA
  local h="$1" d="$2" w="" m="" wl="" n r esp rw fn fc fa got
  S_FALHA=""
  s_fx "$d"
  if [ "$S_WIN" = 1 ]; then
    w="$(cygpath -w "$d")"; m="$(cygpath -m "$d")"
    # A caixa do drive troca entre sessoes do runner (f:\ e F:\): cwd numa, arquivo na outra.
    case "$w" in [A-Z]*) wl="$(printf '%s' "${w:0:1}" | tr A-Z a-z)${w:1}" ;; *) wl="$(printf '%s' "${w:0:1}" | tr a-z A-Z)${w:1}" ;; esac
  fi
  while IFS='|' read -r n r esp; do
    case " $4 " in *" $n "*) ;; *) continue ;; esac
    rw="${r//\//\\}"
    for fn in $3; do
      case "$fn" in
        posix) fc="$d"; fa="$d/$r" ;;
        win) fc="$w"; fa="$w\\$rw" ;;
        misto) fc="$m"; fa="$m/$r" ;;
        cwdwin-arqmisto) fc="$w"; fa="$m/$r" ;;
        caixa-do-drive) fc="$wl"; fa="$w\\$rw" ;;
      esac
      [ -n "$fc" ] || continue
      # A reivindicacao volta ao estado inicial: o hook anexa eventos ao rastro a cada decisao.
      printf '{"trabalho_id":"feat","evento":"task_iniciada","task":"T-01.01","sessao":"s3d@1"}\n' > "$d/docs/eventos/feat.jsonl"
      got="$(s_decide "$h" "$d" "$fc" "$fa")"
      [ "$got" = "$esp" ] || S_FALHA="$S_FALHA $n:$fn=$got(esperado $esp)"
    done
  done <<EOF
$S_CASOS
EOF
  [ -z "$S_FALHA" ]
}
# Os drives da maquina que a bancada alcanca: o do temporario com todos os formatos e, se
# diferente, o do checkout com os formatos que o runner entrega (C:\ e a caixa do drive trocada).
S_SHOOK="$H/sprintx/escopo-da-task.sh"
bash -n "$S_SHOOK"; afirma "s0-hook-sintaxe" $? "bash -n"
S_ROT=posix; S_FMT=posix; [ "$S_WIN" = 1 ] && { S_ROT="$(cygpath -m "$S_DIR" | cut -c1-2)"; S_FMT="$S_TODOS"; }
s_formatos "$S_SHOOK" "$S_DIR/fx c3d" "$S_TODOS" "A B C D E1 E2"
afirma "s1-mesma-decisao-em-todo-formato-$S_ROT" $? "A..E x $S_FMT${S_FALHA:+ — FORA:$S_FALHA}"
if [ "$S_WIN" = 1 ]; then
  S_REPO_PAI="$(cd "$H/../../.." && pwd)"; S_ROT2="$(cygpath -m "$S_REPO_PAI" | cut -c1-2)"
  if [ "$(printf '%s' "$S_ROT2" | tr a-z A-Z)" != "$(printf '%s' "$S_ROT" | tr a-z A-Z)" ] \
    && S_DIR2="$(mktemp -d -p "$S_REPO_PAI" .sx-s3d.XXXXXX 2>/dev/null)"; then
    s_formatos "$S_SHOOK" "$S_DIR2/fx c3d" "posix win caixa-do-drive" "A B C D E1 E2"
    afirma "s1-mesma-decisao-em-todo-formato-$S_ROT2" $? "A..E x posix win caixa-do-drive${S_FALHA:+ — FORA:$S_FALHA}"
  fi
fi

# O helper. No Windows: drive montado vira o que o `cygpath -u` devolve, sem chama-lo; drive fora
# da montagem vira X:/... canonico; POSIX fica intacto; relativo continua relativo. Fora do
# Windows: no-op, byte a byte.
s_cam() { # s_cam <ostype> <caminho> — o que rastro_caminho_em devolve
  OSTYPE="$1" bash -c '. "$0/comum/rastro.sh"; rastro_caminho_em v "$1"; printf "%s" "$v"' "$H" "$2"
}
S_RUIM=""
for c in 'C:\a b\c.ts' 'C:/a/c.ts' 'X:\y' '/c/a/b' 'src/a.ts' 'src\a.ts' '\\srv\share\x'; do
  [ "$(s_cam linux-gnu "$c")" = "$c" ] || S_RUIM="$S_RUIM linux:$c"
done
if [ "$S_WIN" = 1 ]; then
  for c in 'C:\a b\c.ts' 'c:\a\c.ts' 'C:/a/c.ts' 'F:\Projetos\x y\z.ts' 'C:\'; do
    [ "$(s_cam "$OSTYPE" "$c")" = "$(cygpath -u "$c")" ] || S_RUIM="$S_RUIM win:$c=$(s_cam "$OSTYPE" "$c")"
  done
  # Um drive sintetico, fora da montagem: a mesma forma canonica X:/..., venha em que caixa vier.
  S_SINT=""; for l in Q R S T U V W Y Z; do [ -e "$(cygpath -u "$l:/")" ] || { S_SINT="$l"; break; }; done
  S_SL="$(printf '%s' "$S_SINT" | tr A-Z a-z)"
  for c in "$S_SINT:\\nao existe\\z.ts" "$S_SL:/nao existe/z.ts"; do
    [ "$(s_cam "$OSTYPE" "$c")" = "$S_SINT:/nao existe/z.ts" ] || S_RUIM="$S_RUIM sint:$c=$(s_cam "$OSTYPE" "$c")"
  done
  [ "$(s_cam "$OSTYPE" '\\srv\share\x')" = //srv/share/x ] || S_RUIM="$S_RUIM unc"
  [ "$(s_cam "$OSTYPE" '/c/a/b')" = /c/a/b ] || S_RUIM="$S_RUIM posix-intacto"
  [ "$(s_cam "$OSTYPE" 'src/a.ts')" = src/a.ts ] && [ "$(s_cam "$OSTYPE" 'src\a.ts')" = src/a.ts ] || S_RUIM="$S_RUIM relativo"
  # Hook num drive sintetico: nada ali, nada a decidir — igual em C:\ e C:/, sem erro.
  [ "$(s_decide "$S_SHOOK" "$S_DIR" "$S_SINT:\\nao existe" "$S_SINT:\\nao existe\\src\\irma.ts")" = 0/silencio ] \
    && [ "$(s_decide "$S_SHOOK" "$S_DIR" "$S_SINT:/nao existe" "$S_SINT:/nao existe/src/irma.ts")" = 0/silencio ] \
    || S_RUIM="$S_RUIM drive-sintetico-$S_SINT"
fi
[ -z "$S_RUIM" ]; afirma "s2-helper-no-windows-e-no-op-fora" $? "drive montado = cygpath -u, sintetico X:/, UNC, relativo; byte a byte fora${S_RUIM:+ — FORA:$S_RUIM}"

# Custo (DS-157): o formato Windows nao pode custar processo a mais que o POSIX. Shims no PATH,
# como na secao Q, e o cygpath entra na conta.
S_SHIM="$S_DIR/shim"; mkdir -p "$S_SHIM"
for c in awk jq grep sed cut tr wc sort head tail find cat date mkdir dirname basename ps git cygpath python3; do
  r="$(command -v "$c" 2>/dev/null)"; case "$r" in */*) ;; *) continue ;; esac
  printf '#!/bin/sh\nprintf "%%s\\n" "%s" >> "$S_LOG"\nexec "%s" "$@"\n' "$c" "$r" > "$S_SHIM/$c"; chmod +x "$S_SHIM/$c"
done
s_custo() { # s_custo <hook> <dir> <cwd> <file_path> — processos externos
  s_fx "$2"; : > "$S_DIR/log"
  s_json "$3" "$4" | (cd "$2" && PATH="$S_SHIM:$PATH" S_LOG="$S_DIR/log" EXPX_SESSAO=s3d@1 bash "$1") >/dev/null 2>&1
  grep -c '' "$S_DIR/log"
}
S_CD="$S_DIR/custo"; s_fx "$S_CD"
S_CP="$(s_custo "$S_SHOOK" "$S_CD" "$S_CD" "$S_CD/src/a.ts")"; S_CPI="$(s_custo "$S_SHOOK" "$S_CD" "$S_CD" "$S_CD/src/irma.ts")"
S_CW="$S_CP"; S_CWI="$S_CPI"
if [ "$S_WIN" = 1 ]; then
  S_W="$(cygpath -w "$S_CD")"
  S_CW="$(s_custo "$S_SHOOK" "$S_CD" "$S_W" "$S_W\\src\\a.ts")"; S_CWI="$(s_custo "$S_SHOOK" "$S_CD" "$S_W" "$S_W\\src\\irma.ts")"
fi
[ "$S_CW" -le "$S_CP" ] && [ "$S_CWI" -le "$S_CPI" ] && [ "$S_CP" -le $((2 + Q_FOLGA)) ] && [ "$S_CPI" -le $((3 + Q_FOLGA)) ]
afirma "s3-formato-windows-nao-custa-processo" $? "corrente posix=$S_CP win=$S_CW; irma posix=$S_CPI win=$S_CWI"

# Mutantes, so onde o formato Windows existe: fora dele o caminho mutado nem roda.
if [ "$S_WIN" = 1 ]; then
  S_M="$S_DIR/mut"
  s_copia() { # s_copia <nome> — hook + helper copiados; devolve o hook
    rm -rf "$S_M/$1"; mkdir -p "$S_M/$1/sprintx" "$S_M/$1/comum"
    cp "$H/comum/rastro.sh" "$S_M/$1/comum/rastro.sh"; cp "$S_SHOOK" "$S_M/$1/sprintx/escopo-da-task.sh"
    printf '%s' "$S_M/$1/sprintx/escopo-da-task.sh"
  }
  S_MD="$S_DIR/fx c3d"; S_MF="win caixa-do-drive"
  SMC="$(s_copia controle)"; s_formatos "$SMC" "$S_MD" "$S_MF" "A C"
  afirma "sm-controle-copia-intacta-sobrevive" $? "${S_FALHA:-todos os formatos}"
  SMUT="$(s_copia m1)"; muta_lit "$SMUT" "$SMUT.m" 'rastro_caminho_em ALVO "$ALVO"' ':' && mv "$SMUT.m" "$SMUT"
  S_RC=$?; [ "$S_RC" -eq 0 ] && ! s_formatos "$SMUT" "$S_MD" "$S_MF" "A C"
  afirma "sm-mutante-1-file-path-sem-normalizar" $? "rc geracao=$S_RC"
  SMUT="$(s_copia m2)"; muta_lit "$S_M/m2/comum/rastro.sh" "$S_M/m2/r.m" '_d="${_m:${#_i}:1}"' ':' && mv "$S_M/m2/r.m" "$S_M/m2/comum/rastro.sh"
  S_RC=$?; [ "$S_RC" -eq 0 ] && ! s_formatos "$SMUT" "$S_MD" "$S_MF" "A C"
  afirma "sm-mutante-2-drive-sem-caixa-canonica" $? "rc geracao=$S_RC"
fi
rm -rf "$S_DIR" ${S_DIR2:+"$S_DIR2"}


echo "== T. todo caminho do payload passa pelo mesmo helper: C:\\, c:\\, C:/ e POSIX decidem igual (P0.2-C7-B S3-E) =="
# A S3-D corrigiu so o escopo-da-task. Os outros hooks que leem `cwd` ou `tool_input.file_path`
# tiravam a raiz com `/` e casavam `*/tasks.md` no caminho cru: com o payload real do Windows
# (C:\dir\arq, caixa do drive variavel) o segredo perdia a isencao do .env ignorado, os hooks
# de metodo ficavam mudos ou avisavam em falso, e o rastro gravava o caminho absoluto do
# Windows como identificador logico. Contrato: todo pathname do payload passa por
# rastro_caminho_em antes de qualquer uso, e nenhum hook normaliza por conta propria. A
# decisao (rc, aviso/bloqueio/silencio) e os eventos gravados (onde, qual, com que arquivos)
# tem de ser os mesmos em qualquer formato. Fora de MSYS/Cygwin so o formato POSIX existe.
T_WIN=0; case "${OSTYPE:-}" in msys*|cygwin*) T_WIN=1 ;; esac
T_DIR="$(mktemp -d)"
T_AWS="AKIA""ABCDEFGHIJKLMNOP"; T_GF="git push"" --force origin main"
T_FEAT="docs/sprintx/features/feat"
T_TASKS="$T_FEAT/sprint-01/tasks.md"
# O rastro de partida: T-01.01 e de outra sessao; T-01.02 e a desta (o trabalho corrente e feat).
T_BASE='{"trabalho_id":"feat","evento":"task_iniciada","task":"T-01.01","sessao":"outra@9"}
{"trabalho_id":"feat","evento":"task_iniciada","task":"T-01.02","sessao":"t3e@1"}'
t_fx() { # t_fx <dir> — repositorio git real (a arvore-limpa roda git status), nomes com espaco
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/src/com espaco" "$d/docs/eventos" "$d/$T_FEAT/sprint-01"
  git -C "$d" init -q -b main >/dev/null 2>&1
  printf '.env*\n' > "$d/.gitignore"
  printf '# Convencoes\n\nO teste mora ao lado do arquivo: `a.test.ts`.\n' > "$d/CONVENCOES.md"
  : > "$d/src/a.ts"; : > "$d/src/a.test.ts"; : > "$d/src/b.ts"
  : > "$d/src/com espaco/c.ts"; : > "$d/src/com espaco/c.test.ts"
  printf -- '---\nexpx_schema: 1\nkind: tasks\ntrabalho_id: feat\nsprint_id: sprint-01\ntasks:\n' > "$d/$T_TASKS"
  printf '  - id: T-01.01\n    status: em_andamento\n    arquivos:\n      cria: []\n      altera: [src/a.ts]\n' >> "$d/$T_TASKS"
  printf '  - id: T-01.02\n    status: em_andamento\n    arquivos:\n      cria: []\n      altera: [src/a.test.ts]\n---\n' >> "$d/$T_TASKS"
  printf '# Plano\n\nAinda com {{marcador}}.\n' > "$d/$T_FEAT/plano.md"
}
t_esc() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; printf '%s' "$s"; }
t_conteudo() { # t_conteudo <tipo>
  case "$1" in
    inocente) printf 'x = 1' ;;
    aws) printf 'chave = "%s"' "$T_AWS" ;;
    fecha-ruim) printf -- '---\ntrabalho_id: feat\ntasks:\n  - id: T-01.02\n    status: concluida\n    suite: nao_executada\n    teste_integracao:\n    teste_funcional:\n---\n' ;;
    fecha-ok) printf -- '---\ntrabalho_id: feat\ntasks:\n  - id: T-01.02\n    status: concluida\n    suite: verde\n    teste_integracao: chama a api\n    teste_funcional: dado x entao y\n---\n' ;;
    reivindica) printf -- '---\ntrabalho_id: feat\ntasks:\n  - id: T-01.01\n    status: em_andamento\n---\n' ;;
  esac
}
t_json() { # t_json <evento> <ferramenta> <cwd> <file_path> <conteudo> — como o runner manda
  local ti
  case "$2" in
    Bash) ti="{\"command\":\"$(t_esc "$5")\"}" ;;
    -) ti="" ;;
    *) ti="{\"file_path\":\"$(t_esc "$4")\",\"content\":\"$(t_esc "$5")\"}" ;;
  esac
  printf '{"session_id":"x","cwd":"%s","hook_event_name":"%s"' "$(t_esc "$3")" "$1"
  [ "$2" = - ] && { printf ',"agent_type":"qa"}'; return; }
  printf ',"tool_name":"%s","tool_input":%s,"tool_response":{}}' "$2" "$ti"
}
T_SAIDA=""
t_decide() { # t_decide <hook> <dir-posix> <sub> <evento> <ferramenta> <cwd> <file_path> <conteudo>
  # — "rc/classe/eventos": eventos novos em QUALQUER *.jsonl da fixture, como <arquivo>:<evento>:<arquivos>
  local o r cls ev="" f l e a
  rm -rf "$2/src/docs"; find "$2/docs/eventos" -name '*.jsonl' -exec rm -f {} + 2>/dev/null
  printf '%s\n' "$T_BASE" > "$2/docs/eventos/feat.jsonl"
  o="$(t_json "$4" "$5" "$6" "$7" "$8" | (cd "$2${3:+/$3}" && EXPX_SESSAO=t3e@1 CLAUDECODE=1 bash "$1") 2>&1)"; r=$?
  T_SAIDA="$o"
  case "$o" in
    "") cls=silencio ;;
    *sprintx/*) if [ "$r" -eq 2 ]; then cls=bloqueio; else cls=aviso; fi ;;
    *) cls=outro ;;
  esac
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r l; do
      case "$l" in *'"evento":"task_iniciada"'*|"") continue ;; esac
      e="${l#*\"evento\":\"}"; e="${e%%\"*}"
      a="${l#*\"arquivos\":}"; a="${a%%]*}]"
      ev="$ev ${f#"$2"/}:$e:$a"
    done < "$f"
  done <<EOF
$(find "$2" -name '*.jsonl' -path '*docs/eventos*' 2>/dev/null | sort)
EOF
  printf '%s/%s/%s' "$r" "$cls" "${ev# }"
}
# Os casos e o que cada um TEM de decidir. sub = subdiretorio do cwd (o processo roda la, como no
# runner). EF = docs/eventos/feat.jsonl, o rastro do trabalho corrente da sessao.
EF=docs/eventos/feat.jsonl
T_CASOS="seg-inocente|comum/segredo.sh||PreToolUse|Write|src/a.ts|inocente|0/silencio/
seg-aws|comum/segredo.sh||PreToolUse|Write|src/a.ts|aws|2/bloqueio/$EF:acao_bloqueada:[\"src/a.ts\"]
seg-aws-espaco|comum/segredo.sh||PreToolUse|Write|src/com espaco/c.ts|aws|2/bloqueio/$EF:acao_bloqueada:[\"src/com espaco/c.ts\"]
seg-env-ignorado|comum/segredo.sh||PreToolUse|Write|src/.env|aws|0/silencio/
seg-cwd-sub|comum/segredo.sh|src|PreToolUse|Write|src/a.ts|aws|2/bloqueio/$EF:acao_bloqueada:[\"src/a.ts\"]
tdd-com-teste|sprintx/tdd-teste-antes.sh||PostToolUse|Write|src/a.ts|inocente|0/silencio/
tdd-sem-teste|sprintx/tdd-teste-antes.sh||PostToolUse|Write|src/b.ts|inocente|0/aviso/$EF:regra_violada:[\"src/b.ts\"]
tdd-espaco-com-teste|sprintx/tdd-teste-antes.sh||PostToolUse|Write|src/com espaco/c.ts|inocente|0/silencio/
tdd-artefato-da-skill|sprintx/tdd-teste-antes.sh||PostToolUse|Write|$T_FEAT/plano.md|inocente|0/silencio/
verde-ruim|sprintx/task-so-fecha-verde.sh||PreToolUse|Write|$T_TASKS|fecha-ruim|0/aviso/$EF:regra_violada:[\"$T_TASKS\"]
verde-ok|sprintx/task-so-fecha-verde.sh||PreToolUse|Write|$T_TASKS|fecha-ok|0/silencio/
reivindicada|sprintx/task-reivindicada.sh||PreToolUse|Write|$T_TASKS|reivindica|0/aviso/$EF:regra_violada:[]
placeholder|sprintx/sem-placeholder-no-plano.sh||PostToolUse|Write|$T_FEAT/plano.md|inocente|0/aviso/$EF:regra_violada:[\"$T_FEAT/plano.md\"]
post-write|comum/rastro-post.sh||PostToolUse|Write|src/a.ts|inocente|0/silencio/$EF:arquivo_alterado:[\"src/a.ts\"]
post-espaco|comum/rastro-post.sh||PostToolUse|Write|src/com espaco/c.ts|inocente|0/silencio/$EF:arquivo_alterado:[\"src/com espaco/c.ts\"]
post-cwd-sub|comum/rastro-post.sh|src|PostToolUse|Write|src/a.ts|inocente|0/silencio/$EF:arquivo_alterado:[\"src/a.ts\"]
git-cwd-sub|sprintx/git-perigoso.sh|src|PreToolUse|Bash||git-forcado|2/bloqueio/$EF:acao_bloqueada:[]
arvore-cwd-sub|sprintx/arvore-limpa-antes-da-suite.sh|src|PreToolUse|Bash||npm test|0/aviso/$EF:regra_violada:[]
subagente-cwd-sub|comum/rastro-subagente.sh|src|SubagentStop|-|||0/silencio/$EF:agente_concluido:[]"
T_FALHA=""
T_TODOS="posix win minuscula misto caixa-do-drive"
# t_formatos <raiz-hooks> <dir-posix> <formatos> <casos> — falhas em T_FALHA
t_formatos() {
  local H2="$1" d="$2" w="" m="" wl="" n h sub ev fe r ct esp rw fn fc fa got cont sw
  T_FALHA=""
  [ -d "$d/.git" ] || t_fx "$d"
  if [ "$T_WIN" = 1 ]; then
    w="$(cygpath -w "$d")"; m="$(cygpath -m "$d")"
    case "$w" in [A-Z]*) wl="$(printf '%s' "${w:0:1}" | tr A-Z a-z)${w:1}" ;; *) wl="$(printf '%s' "${w:0:1}" | tr a-z A-Z)${w:1}" ;; esac
  fi
  while IFS='|' read -r n h sub ev fe r ct esp; do
    case " $4 " in *" $n "*|" todos ") ;; *) continue ;; esac
    case "$ct" in git-forcado) cont="$T_GF" ;; "npm test") cont="npm test" ;; *) cont="$(t_conteudo "$ct")" ;; esac
    rw="${r//\//\\}"; sw="${sub:+\\$sub}"
    for fn in $3; do
      fc=""
      case "$fn" in
        posix) fc="$d${sub:+/$sub}"; fa="$d/$r" ;;
        win) [ -n "$w" ] && fc="$w$sw"; fa="$w\\$rw" ;;
        minuscula) [ -n "$wl" ] && fc="$wl$sw"; fa="$wl\\$rw" ;;
        misto) [ -n "$m" ] && fc="$m${sub:+/$sub}"; fa="$m/$r" ;;
        caixa-do-drive) [ -n "$wl" ] && fc="$wl$sw"; fa="$w\\$rw" ;;
      esac
      [ -n "$fc" ] || continue
      [ -n "$r" ] || fa=""
      got="$(t_decide "$H2/$h" "$d" "$sub" "$ev" "$fe" "$fc" "$fa" "$cont")"
      [ "$got" = "$esp" ] || T_FALHA="$T_FALHA
    $n:$fn=$got (esperado $esp)"
    done
  done <<EOF
$T_CASOS
EOF
  [ -z "$T_FALHA" ]
}
T_FMT=posix; [ "$T_WIN" = 1 ] && T_FMT="$T_TODOS"
T_FX="$T_DIR/fx t 3e"
t_formatos "$H" "$T_FX" "$T_FMT" todos
afirma "t1-mesma-decisao-e-mesmo-rastro-em-todo-formato" $? "$(printf '%s\n' "$T_CASOS" | grep -c '') casos x $T_FMT${T_FALHA:+ — FORA:$T_FALHA}"

# Nenhum evento carrega caminho absoluto do Windows (nem C:\ nem C:/) como identificador.
T_ABS=""
if [ "$T_WIN" = 1 ]; then
  for c in post-write placeholder verde-ruim seg-aws tdd-sem-teste; do
    n="$(printf '%s\n' "$T_CASOS" | grep "^$c|")"; IFS='|' read -r _ h sub ev fe r ct _ <<EOF
$n
EOF
    w="$(cygpath -w "$T_FX")"
    t_decide "$H/$h" "$T_FX" "$sub" "$ev" "$fe" "$w" "$w\\${r//\//\\}" "$(t_conteudo "$ct")" >/dev/null
    grep -qE '[A-Za-z]:(\\\\|/)' "$T_FX/$EF" && T_ABS="$T_ABS $c"
  done
fi
[ -z "$T_ABS" ]; afirma "t2-rastro-sem-caminho-absoluto-do-windows" $? "arquivos relativos a raiz${T_ABS:+ — ABSOLUTO EM:$T_ABS}"

# Estrutural. A auditoria: estes sao os hooks que leem pathname do payload, e a variavel de cada
# um. Cada par passa por rastro_caminho_em ANTES de qualquer uso que nao seja a propria leitura
# ou o teste de vazio; nenhum hook fora da lista le `cwd`/`file_path`; e nenhum hook reimplementa
# a normalizacao (cygpath, troca de barra, letra de drive) — o helper e o contrato.
T_PARES="comum/segredo.sh:CWD comum/segredo.sh:ALVO comum/rastro-post.sh:CWD comum/rastro-post.sh:ALVO
comum/rastro-subagente.sh:CWD sprintx/escopo-da-task.sh:CWD sprintx/escopo-da-task.sh:ALVO
sprintx/git-perigoso.sh:CWD sprintx/arvore-limpa-antes-da-suite.sh:CWD
sprintx/sem-placeholder-no-plano.sh:CWD sprintx/sem-placeholder-no-plano.sh:ALVO
sprintx/task-so-fecha-verde.sh:CWD sprintx/task-so-fecha-verde.sh:ALVO
sprintx/task-reivindicada.sh:CWD sprintx/task-reivindicada.sh:ALVO
sprintx/tdd-teste-antes.sh:CWD sprintx/tdd-teste-antes.sh:ALVO"
# t_normaliza_antes <hook> <VAR> — a linha `rastro_caminho_em VAR "$VAR"` existe e toda linha
# anterior que toca VAR e leitura (atribuicao, rastro_json_campo_em VAR) ou teste de vazio.
t_normaliza_antes() {
  awk -v V="$2" '
    { sub(/^[ \t]+/, "") }
    /^#/ { next }
    $0 == "rastro_caminho_em " V " \"$" V "\"" { achou = 1; exit }
    index($0, "$" V) || index($0, "${" V) || index($0, V "=") || index($0, "rastro_json_campo_em " V " ") {
      l = $0
      gsub("\\[ -n \"\\$" V "\" \\] \\|\\| (exit 0|" V "=\"\\$PWD\")", "", l)
      gsub("rastro_json_campo_em " V " \"\\$ENTRADA\" [a-z_]+", "", l)
      gsub("(^|[; ])" V "=\"\\$\\((rastro_json_get|rastro_tool_input_get) \"\\$ENTRADA\" [a-z_]+\\)\"", "", l)
      gsub("(^|[; ])" V "=\"\\$\\{CAMPOS\\[[0-9]\\]-\\}\"", "", l)
      if (index(l, "$" V) || index(l, "${" V) || index(l, V "=")) { ruim = NR ": " $0; exit }
    }
    END { if (ruim != "") { print ruim; exit 1 } if (!achou) { print "sem rastro_caminho_em"; exit 1 } }
  ' "$1"
}
t_estrutura() { # t_estrutura <raiz-hooks> — falhas em T_FALHA
  local H2="$1" p f v out
  T_FALHA=""
  for p in $T_PARES; do
    f="${p%%:*}"; v="${p#*:}"
    out="$(t_normaliza_antes "$H2/$f" "$v")" || T_FALHA="$T_FALHA $f:$v($out)"
  done
  for f in "$H2"/comum/*.sh "$H2"/sprintx/*.sh; do
    case "$f" in */comum/rastro.sh) continue ;; esac
    # Le pathname do payload sem estar na auditoria?
    if grep -v '^[[:space:]]*#' "$f" | grep -qE '(rastro_json_get|rastro_tool_input_get|rastro_json_campo_em [A-Z_]+) "\$ENTRADA" (cwd|file_path)|\.(cwd|file_path) //'; then
      case " $(printf '%s' "$T_PARES" | tr '\n' ' ') " in *" ${f#"$H2"/}:"*) ;; *) T_FALHA="$T_FALHA ${f#"$H2"/}:le-caminho-fora-da-auditoria" ;; esac
    fi
    # Normalizacao propria: cygpath, troca de barra invertida, letra de drive.
    if grep -v '^[[:space:]]*#' "$f" | grep -qE 'cygpath|//\\\\+/|s[#/|,]\\\\\\\\|tr .\\\\\\\\|\[A-Za-z\]:|\[a-zA-Z\]:'; then
      T_FALHA="$T_FALHA ${f#"$H2"/}:normalizacao-propria"
    fi
  done
  [ -z "$T_FALHA" ]
}
t_estrutura "$H"; afirma "t3-todo-caminho-do-payload-pelo-helper" $? "$(printf '%s\n' "$T_PARES" | wc -w | tr -d ' ') pares hook:variavel; nenhuma normalizacao propria${T_FALHA:+ — FORA:$T_FALHA}"

# Custo (DS-157): normalizar e builtin. O formato Windows nao custa processo a mais que o POSIX,
# nos dois criticos e num PostToolUse. Shims no PATH, como nas secoes Q e S.
T_SHIM="$T_DIR/shim"; mkdir -p "$T_SHIM"
for c in awk jq grep sed cut tr wc sort head tail find cat date mkdir dirname basename ps git cygpath python3 xargs; do
  r="$(command -v "$c" 2>/dev/null)"; case "$r" in */*) ;; *) continue ;; esac
  printf '#!/bin/sh\nprintf "%%s\\n" "%s" >> "$T_LOG"\nexec "%s" "$@"\n' "$c" "$r" > "$T_SHIM/$c"; chmod +x "$T_SHIM/$c"
done
t_custo() { # t_custo <hook> <evento> <cwd> <file_path> <conteudo> — processos externos
  rm -rf "$T_FX/src/docs"; printf '%s\n' "$T_BASE" > "$T_FX/$EF"; : > "$T_DIR/log"
  t_json "$2" Write "$3" "$4" "$5" | (cd "$T_FX" && PATH="$T_SHIM:$PATH" T_LOG="$T_DIR/log" EXPX_SESSAO=t3e@1 CLAUDECODE=1 bash "$H/$1") >/dev/null 2>&1
  grep -c '' "$T_DIR/log"
}
T_CUSTO=""; T_CRUIM=""
T_W="$T_FX"; [ "$T_WIN" = 1 ] && T_W="$(cygpath -w "$T_FX")"
while IFS='|' read -r rot h ev ct; do
  cp_="$(t_custo "$h" "$ev" "$T_FX" "$T_FX/src/a.ts" "$(t_conteudo "$ct")")"
  cw_="$(t_custo "$h" "$ev" "$T_W" "$T_W\\src\\a.ts" "$(t_conteudo "$ct")")"
  T_CUSTO="$T_CUSTO $rot posix=$cp_ win=$cw_;"
  [ "$cw_" -le "$cp_" ] || T_CRUIM="$T_CRUIM $rot"
done <<EOF
segredo-limpo|comum/segredo.sh|PreToolUse|inocente
segredo-achado|comum/segredo.sh|PreToolUse|aws
escopo|sprintx/escopo-da-task.sh|PreToolUse|inocente
rastro-post|comum/rastro-post.sh|PostToolUse|inocente
EOF
[ -z "$T_CRUIM" ]; afirma "t4-formato-windows-nao-custa-processo" $? "${T_CUSTO% ;}${T_CRUIM:+ — MAIS CARO:$T_CRUIM}"

# Mutantes. Copia da arvore de hooks (comum/ + sprintx/); o controle e a copia sem mutacao.
T_M="$T_DIR/mut"
t_copia() { rm -rf "$T_M/$1"; mkdir -p "$T_M/$1"; cp -R "$H/comum" "$H/sprintx" "$T_M/$1/"; printf '%s' "$T_M/$1"; }
T_MF="posix"; [ "$T_WIN" = 1 ] && T_MF="win minuscula caixa-do-drive"
t_mutante() { # t_mutante <nome> <rc geracao> <raiz> <casos que TEM de matar> [estrutural]
  local nome="$1" rc="$2" r="$3" casos="$4" est="${5:-}" morto=""
  if [ "$rc" -eq 0 ]; then
    t_formatos "$r" "$T_FX" "$T_MF" "$casos" || morto="comportamento"
    if [ -n "$est" ]; then t_estrutura "$r" || morto="${morto:+$morto+}estrutura"; fi
  fi
  local msg="SOBREVIVEU"; [ -z "$morto" ] || msg="morto por: $morto"
  [ "$rc" -eq 0 ] && [ -n "$morto" ]; afirma "$nome" $? "$msg (rc geracao=$rc)"
}
TMC="$(t_copia controle)"; t_formatos "$TMC" "$T_FX" "$T_MF" todos && t_estrutura "$TMC"
afirma "tm-controle-copia-intacta-sobrevive" $? "$T_MF + estrutura${T_FALHA:+ — FORA:$T_FALHA}"
# 1. O segredo volta a usar cwd e file_path crus.
TMU="$(t_copia m1)"; muta_lit "$TMU/comum/segredo.sh" "$TMU/s.m" 'rastro_caminho_em ALVO "$ALVO"' ':' \
  && muta_lit "$TMU/s.m" "$TMU/comum/segredo.sh" 'rastro_caminho_em CWD "$CWD"' ':'
t_mutante "tm-mutante-1-segredo-sem-normalizar" $? "$TMU" "seg-env-ignorado seg-aws seg-cwd-sub" estrutura
# 2. Outro PreToolUse (task-so-fecha-verde) volta a casar `*/tasks.md` no caminho cru.
TMU="$(t_copia m2)"; muta_lit "$H/sprintx/task-so-fecha-verde.sh" "$TMU/sprintx/task-so-fecha-verde.sh" 'rastro_caminho_em ALVO "$ALVO"' ':'
t_mutante "tm-mutante-2-outro-pretooluse-sem-normalizar" $? "$TMU" "verde-ruim" estrutura
# 3. A caixa do drive deixa de ser canonica no helper (c:\ e C:\ viram raizes diferentes). So
# onde o formato Windows existe: fora dele o helper e no-op e o trecho mutado nem roda.
if [ "$T_WIN" = 1 ]; then
  TMU="$(t_copia m3)"; muta_lit "$H/comum/rastro.sh" "$TMU/comum/rastro.sh" '_d="${_m:${#_i}:1}"' ':'
  t_mutante "tm-mutante-3-caixa-do-drive-nao-normalizada" $? "$TMU" "seg-env-ignorado seg-aws tdd-com-teste verde-ruim reivindicada placeholder post-write"
fi
# 4. Caminho com espaco quebra: a variavel vai sem aspas para o helper.
TMU="$(t_copia m4)"; muta_lit "$H/comum/segredo.sh" "$TMU/comum/segredo.sh" 'rastro_caminho_em ALVO "$ALVO"' 'rastro_caminho_em ALVO $ALVO'
t_mutante "tm-mutante-4-caminho-com-espaco-quebra" $? "$TMU" "seg-aws-espaco" estrutura
# 5. O rastro-post grava o caminho Windows cru.
TMU="$(t_copia m5)"; muta_lit "$H/comum/rastro-post.sh" "$TMU/comum/rastro-post.sh" 'rastro_caminho_em ALVO "$ALVO"' ':'
t_mutante "tm-mutante-5-rastro-post-grava-caminho-cru" $? "$TMU" "post-write post-espaco" estrutura
# 6. Um hook volta a normalizar sozinho, so trocando a barra, e corta a raiz por `/`.
TMU="$(t_copia m6)"; muta_lit "$H/sprintx/tdd-teste-antes.sh" "$TMU/sprintx/tdd-teste-antes.sh" 'rastro_caminho_em ALVO "$ALVO"' 'ALVO="${ALVO//\\//}"'
t_mutante "tm-mutante-6-hook-volta-ao-corte-por-barra" $? "$TMU" "tdd-com-teste tdd-artefato-da-skill" estrutura
rm -rf "$T_DIR"

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
for c in $U_CASOS; do "$c" "$U_REAL" >/dev/null 2>&1; afirma "$(u_nome "$c")" $? "arvore do repositorio"; done

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

echo
echo "  $ok ok, $falhou falhas, $pulado skip(s) interno(s), $pulado_externo por dependencia externa ausente"
[ "$pulado" -eq 0 ] || echo "  ATENCAO: skip interno e buraco de cobertura da sprintx nesta plataforma, nao dependencia externa."
[ "$falhou" -eq 0 ] && [ "$pulado" -eq 0 ]
