#!/usr/bin/env bash
#
# Secao AP da bancada: o plano e o bloco `tasks:` do frontmatter (DS-195). Um `  - id:` em
# exemplo depois do frontmatter, ou sob outra chave, nao e task: o escritor do rastro nao o
# aceita, e os hooks de escopo e de reivindicacao nao o leem. Tasks.md sem frontmatter segue
# lido por inteiro, como legado. Carregada por `.` de dentro da bancada.sh.

[ -n "${SK:-}" ] && [ -f "$SK/SKILL.md" ] || {
  echo "bancada-plano-so-frontmatter: carregue pela bancada.sh (SK ausente ou sem SKILL.md)" >&2
  return 2 2>/dev/null || exit 2
}

echo "== AP. o plano e o bloco tasks: do frontmatter =="
AP="$(mktemp -d)"
git -C "$AP" init -q -b main; git -C "$AP" config user.email t@t.local; git -C "$AP" config user.name t
git -C "$AP" -c commit.gpgsign=false commit -q -m init --allow-empty
printf '.expx/\ndocs/eventos/\n' > "$AP/.gitignore"
APF="$AP/docs/sprintx/features/fp"; APT="$APF/sprint-01/tasks.md"; APR="$AP/docs/eventos/fp.jsonl"
mkdir -p "$APF/sprint-01" "$AP/docs/eventos" "$AP/.expx" "$AP/src"
printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: orquestrador\ntrabalho_id: fp\n---\n' > "$APF/ORQUESTRADOR.md"

ap_plano() { # ap_plano <status de T-01.01>
  cat <<YAML
---
expx_schema: 1
expx_tool: sprintx
kind: tasks
trabalho_id: fp
sprint_id: sprint-01
tasks:
  - id: T-01.01
    titulo: real
    status: $1
    arquivos:
      cria: [src/a.ts]
      altera: []
  - id: T-01.02
    titulo: da sessao
    status: em_andamento
    arquivos:
      cria: [src/b.ts]
      altera: []
riscos:
  - id: T-01.08
    status: em_andamento
---

# Como escrever uma task

\`\`\`yaml
tasks:
  - id: T-01.09
    status: em_andamento
    arquivos:
      cria: [src/exemplo.ts]
      altera: []
\`\`\`
YAML
}
ap_evento() { # ap_evento <evento> <task> <sessao>
  printf '{"ts":"2026-10-31T00:00:00Z","expx_eventos":1,"trabalho_id":"fp","ferramenta":"sprintx","origem":"skill","evento":"%s","fase":"f6","task":"%s","agente":"principal","resultado":"ok","detalhe":null,"arquivos":[],"sessao":"%s","harness":"%s"}\n' \
    "$1" "$2" "$3" "${3%%@*}" >> "$APR"
}
ap_rastro() { # ap_rastro <task> — rc do escritor, com identidade
  (cd "$AP" && env -u EXPX_SESSAO -u EXPX_HARNESS CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=ap-sessao \
    bash "$SK/scripts/rastro.sh" task-iniciada fp "$1" >/dev/null 2>&1)
}
ap_hook() { # ap_hook <hook> <json> — rc em AP_RC, saida em AP_SAIDA, como a sessao eu@ap
  AP_SAIDA="$(printf '%s' "$2" | (cd "$AP" && EXPX_SESSAO=eu@ap bash "$H/sprintx/$1") 2>&1)"; AP_RC=$?
}
ap_modo() { printf '{"hooks":{"%s":{"modo":"bloqueio"}}}\n' "$1" > "$AP/.expx/hooks.json"; }

# -- o escritor do rastro
ap_plano pendente > "$APT"
ap_rastro T-01.01; afirma "ap1-rastro-aceita-a-task-do-plano" $? "T-01.01 no bloco tasks:"
ap_rastro T-01.09; [ $? = 4 ]; afirma "ap2-rastro-recusa-id-do-exemplo" $? "T-01.09 so depois do frontmatter"
ap_rastro T-01.08; [ $? = 4 ]; afirma "ap3-rastro-recusa-id-de-outra-chave" $? "T-01.08 sob riscos:"
ap_plano pendente | sed 's/$/\r/' > "$APT"
ap_rastro T-01.01; afirma "ap4-rastro-com-crlf" $? "T-01.01 num tasks.md com CRLF"
printf 'tasks:\n  - id: T-01.05\n    status: pendente\n' > "$APT"
ap_rastro T-01.05; afirma "ap5-rastro-legado-sem-frontmatter" $? "arquivo sem frontmatter e lido por inteiro"

# Comentario YAML na coluna 0 nao fecha o bloco, e o da linha do id nao faz parte dele (CodeAnt no sprintx#60).
ap_comentado() { # ap_comentado <status>
  printf -- '---\nkind: tasks\ntrabalho_id: fp\ntasks:\n# as proximas\n  - id: T-01.03 # nota\n    status: %s\n    arquivos:\n      cria: [src/c.ts]\n      altera: []\n---\n' "$1"
}
ap_comentado pendente > "$APT"
ap_rastro T-01.03; afirma "ap5b-rastro-com-comentario-no-bloco" $? "comentario na coluna 0 e na linha do id"

# -- escopo-da-task: quem reivindicou um id do exemplo nao tem task no plano, e nada passa por "task sem arquivos"
rm -f "$AP/.expx/hooks.json"; ap_plano pendente > "$APT"
: > "$APR"; ap_evento task_iniciada T-01.09 eu@ap
ap_hook escopo-da-task.sh "{\"cwd\":\"$AP\",\"tool_input\":{\"file_path\":\"$AP/src/qualquer.ts\"}}"
[ "$AP_RC" = 2 ]; afirma "ap6-escopo-id-do-exemplo-nao-e-task" $? "rc=$AP_RC: $AP_SAIDA"
: > "$APR"; ap_evento task_iniciada T-01.08 eu@ap
ap_hook escopo-da-task.sh "{\"cwd\":\"$AP\",\"tool_input\":{\"file_path\":\"$AP/src/qualquer.ts\"}}"
[ "$AP_RC" = 2 ]; afirma "ap6b-escopo-id-de-outra-chave-nao-e-task" $? "rc=$AP_RC: $AP_SAIDA"
: > "$APR"; ap_evento task_iniciada T-01.02 eu@ap
ap_hook escopo-da-task.sh "{\"cwd\":\"$AP\",\"tool_input\":{\"file_path\":\"$AP/src/b.ts\"}}"
[ "$AP_RC" = 0 ]; afirma "ap7-escopo-aceita-o-arquivo-da-task" $? "rc=$AP_RC: $AP_SAIDA"

: > "$APR"; ap_comentado em_andamento > "$APT"; ap_evento task_iniciada T-01.03 eu@ap
ap_hook escopo-da-task.sh "{\"cwd\":\"$AP\",\"tool_input\":{\"file_path\":\"$AP/src/c.ts\"}}"
[ "$AP_RC" = 0 ]; afirma "ap7b-escopo-com-comentario-no-bloco" $? "rc=$AP_RC: $AP_SAIDA"
ap_plano pendente > "$APT"

# -- arvore-limpa: o exemplo nao declara escopo nem reivindicacao
ap_suite() { ap_hook arvore-limpa-antes-da-suite.sh "{\"cwd\":\"$AP\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm test\"}}"; }
ap_modo arvore-limpa-antes-da-suite
: > "$APR"; ap_evento task_iniciada T-01.02 eu@ap; ap_evento task_iniciada T-01.09 outra@ap
ap_suite
case "$AP_SAIDA" in *T-01.09*) false ;; *) true ;; esac
afirma "ap8-arvore-limpa-nao-le-a-task-do-exemplo" $? "rc=$AP_RC: $AP_SAIDA"
printf 'x\n' > "$AP/src/exemplo.ts"; ap_suite
case "$AP_SAIDA" in *src/exemplo.ts*) true ;; *) false ;; esac
afirma "ap8b-arquivo-do-exemplo-esta-fora-do-escopo" $? "rc=$AP_RC: $AP_SAIDA"
rm -f "$AP/src/exemplo.ts"
: > "$APR"; ap_plano em_andamento > "$APT"; ap_evento task_iniciada T-01.02 eu@ap; ap_evento task_iniciada T-01.01 outra@ap
ap_suite
case "$AP_SAIDA" in *T-01.01*) true ;; *) false ;; esac
afirma "ap9-arvore-limpa-ve-a-task-do-plano" $? "rc=$AP_RC: $AP_SAIDA"

# -- task-reivindicada: o exemplo do texto proposto nao e reivindicacao
ap_json() { python3 -c "import json,sys; print(json.dumps({'cwd':sys.argv[1],'tool_name':'Write','tool_input':{'file_path':sys.argv[2],'content':sys.stdin.read()}}))" "$AP" "$APT"; }
: > "$APR"; ap_evento task_iniciada T-01.09 outra@ap; ap_modo task-reivindicada
ap_hook task-reivindicada.sh "$(ap_plano pendente | ap_json)"
[ "$AP_RC" = 0 ]; afirma "ap10-reivindicada-nao-le-o-exemplo" $? "rc=$AP_RC: $AP_SAIDA"
: > "$APR"; ap_evento task_iniciada T-01.01 outra@ap
ap_hook task-reivindicada.sh "$(ap_plano em_andamento | ap_json)"
[ "$AP_RC" = 2 ]; afirma "ap11-reivindicada-ve-a-task-do-plano" $? "rc=$AP_RC: $AP_SAIDA"
: > "$APR"; ap_evento task_iniciada T-01.03 outra@ap
ap_hook task-reivindicada.sh "$(ap_comentado em_andamento | ap_json)"
[ "$AP_RC" = 2 ]; afirma "ap11b-reivindicada-com-comentario-no-bloco" $? "rc=$AP_RC: $AP_SAIDA"
: > "$APR"; ap_evento task_iniciada T-01.01 outra@ap
# Edit manda so o trecho, sem frontmatter: continua lido por inteiro.
ap_hook task-reivindicada.sh "$(printf '  - id: T-01.01\n    status: em_andamento\n' | ap_json)"
[ "$AP_RC" = 2 ]; afirma "ap12-reivindicada-le-o-trecho-do-edit" $? "rc=$AP_RC: $AP_SAIDA"

rm -rf "$AP"
