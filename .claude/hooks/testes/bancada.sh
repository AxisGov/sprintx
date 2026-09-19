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
REGRAS=$(sed -n '/^## Regras invioláveis$/,/^## Sessões paralelas$/p' "$SKILLMD" | grep -cE '^[0-9]+\. ')
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

pulado=0
pula() { pulado=$((pulado+1)); printf '  pula %-46s %s\n' "$1" "$2"; }

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
  pula "d3-yaml-real" "nenhum python com PyYAML; so a guarda estrutural rodou"
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
  pula "g-mergex-aceita-planejamento" "mergex nao encontrada em \$MERGEX_DIR/../mergex, ou sem jq"
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
copia_skill() { mkdir -p "$MJ/$1/scripts" "$MJ/$1/assets"; cp "$TPLB" "$MJ/$1/assets/"; printf '%s/%s/scripts/bloqueios.sh' "$MJ" "$1"; }
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
  -e '/^assinatura_congeladas:/d' -e 's/ · replanejamentos da execução (F6): [^·]*//' "$(kf "$FXL")/00-PLANEJAMENTO.md" > "$K/pl.tmp" \
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
copia_skill_k() { mkdir -p "$MK/$1/scripts" "$MK/$1/assets"; cp "$SK/assets/TEMPLATE-PLANEJAMENTO.md" "$SK/assets/TEMPLATE-BLOQUEIOS.md" "$MK/$1/assets/"; cp "$BL" "$MK/$1/scripts/"; printf '%s/%s/scripts/planejamento.sh' "$MK" "$1"; }
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
rm -rf "$K"

echo
echo "  $ok ok, $falhou falhas, $pulado pulados"
[ "$falhou" -eq 0 ]
