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

echo
echo "  $ok ok, $falhou falhas, $pulado pulados"
[ "$falhou" -eq 0 ]
