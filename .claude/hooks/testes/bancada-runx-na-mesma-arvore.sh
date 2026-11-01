#!/usr/bin/env bash
#
# Secao AQ da bancada: o plano da ocorrencia e da runx (DS-196). `docs/manutencao/OC-*` fica
# fora do porteiro do escopo-da-task, e a linha de rastro da runx nao e reivindicacao da
# SprintX, com qualquer forma de JSON. O que protege a feature continua valendo. Carregada
# por `.` de dentro da bancada.sh.

[ -n "${SK:-}" ] && [ -f "$SK/SKILL.md" ] || {
  echo "bancada-runx-na-mesma-arvore: carregue pela bancada.sh (SK ausente ou sem SKILL.md)" >&2
  return 2 2>/dev/null || exit 2
}

echo "== AQ. o plano da ocorrencia e da runx =="
AQ="$(mktemp -d)"
git -C "$AQ" init -q -b main; git -C "$AQ" config user.email t@t.local; git -C "$AQ" config user.name t
git -C "$AQ" -c commit.gpgsign=false commit -q -m init --allow-empty
printf '.expx/\ndocs/eventos/\n' > "$AQ/.gitignore"
AQO="$AQ/docs/manutencao/OC-9999-sonda/sprint-01"; AQT="$AQO/tasks.md"
AQF="$AQ/docs/sprintx/features/fq"; AQE="$AQ/docs/eventos"
mkdir -p "$AQO" "$AQF/sprint-01" "$AQE" "$AQ/.expx" "$AQ/infra" "$AQ/src"
printf -- '---\nocorrencia: OC-9999\nstatus: em_andamento\ntasks:\n  - id: T-01.01\n    status: em_andamento\n    arquivos:\n      cria: []\n      altera: [infra/a.sh]\n---\n' > "$AQT"
printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: orquestrador\ntrabalho_id: fq\n---\n' > "$AQF/ORQUESTRADOR.md"
aq_feature() { # aq_feature <pasta da feature> <trabalho>
  mkdir -p "$1/sprint-01"
  printf -- '---\nkind: tasks\ntrabalho_id: %s\nsprint_id: sprint-01\ntasks:\n  - id: T-01.01\n    status: em_andamento\n    arquivos:\n      cria: [src/f.ts]\n      altera: []\n---\n' "$2" > "$1/sprint-01/tasks.md"
}
aq_hook() { # aq_hook <arquivo relativo> — rc em AQ_RC, saida em AQ_SAIDA, como a sessao eu@aq
  AQ_SAIDA="$(printf '{"cwd":"%s","tool_input":{"file_path":"%s/%s"}}' "$AQ" "$AQ" "$1" \
    | (cd "$AQ" && EXPX_SESSAO=eu@aq bash "$H/sprintx/escopo-da-task.sh") 2>&1)"; AQ_RC=$?
}
aq_modo() { printf '{"hooks":{"escopo-da-task":{"modo":"%s"}}}\n' "$1" > "$AQ/.expx/hooks.json"; }
aq_limpa() { rm -f "$AQE"/*.jsonl "$AQ/.expx/hooks.json"; rm -f "$AQF/sprint-01/tasks.md"; }
aq_mostra() { printf 'rc=%s: %.150s' "$AQ_RC" "$AQ_SAIDA"; }

# -- so a ocorrencia aberta: a runx nao fica presa, nem com o hook em bloqueio
aq_limpa
aq_hook infra/a.sh; [ "$AQ_RC" = 0 ] && [ -z "$AQ_SAIDA" ]; afirma "aq1-ocorrencia-edita-o-arquivo-da-task" $? "$(aq_mostra)"
aq_hook docs/manutencao/OC-9999-sonda/sprint-01/tasks.md; [ "$AQ_RC" = 0 ]; afirma "aq2-ocorrencia-edita-o-proprio-plano" $? "$(aq_mostra)"
aq_modo bloqueio
aq_hook infra/a.sh; [ "$AQ_RC" = 0 ]; afirma "aq3-ocorrencia-com-o-hook-em-bloqueio" $? "$(aq_mostra)"
aq_limpa
mkdir -p "$AQ/docs/manutencao/OC-8888-fase/fase-1/sprint-01"
cp "$AQT" "$AQ/docs/manutencao/OC-8888-fase/fase-1/sprint-01/tasks.md"
aq_hook infra/a.sh; [ "$AQ_RC" = 0 ]; afirma "aq4-plano-mais-fundo-na-ocorrencia" $? "$(aq_mostra)"
rm -rf "$AQ/docs/manutencao/OC-8888-fase"
mv "$AQT" "$AQ/fora.md"; ln -s "$AQ/fora.md" "$AQT"
aq_hook infra/a.sh; [ "$AQ_RC" = 0 ] && [ -z "$AQ_SAIDA" ]; afirma "aq5-plano-da-ocorrencia-por-link-nao-e-da-sprintx" $? "$(aq_mostra)"
rm -f "$AQT"; mv "$AQ/fora.md" "$AQT"

# -- a feature aberta continua protegida
aq_limpa; aq_feature "$AQF" fq
aq_hook infra/a.sh
[ "$AQ_RC" = 2 ] && case "$AQ_SAIDA" in *sessao_ambigua*) true ;; *) false ;; esac
afirma "aq6-feature-aberta-e-sessao-sem-reivindicacao" $? "$(aq_mostra)"
printf '{"ts":"2026-11-01T00:00:00Z","expx_eventos":1,"trabalho_id":"fq","ferramenta":"sprintx","origem":"skill","evento":"task_iniciada","fase":"f6","task":"T-01.01","agente":"principal","sessao":"eu@aq"}\n' > "$AQE/fq.jsonl"
aq_hook src/f.ts; [ "$AQ_RC" = 0 ]; afirma "aq7-a-task-da-feature-segue-editando" $? "$(aq_mostra)"
aq_modo bloqueio
aq_hook infra/a.sh; [ "$AQ_RC" = 2 ]; afirma "aq8-feature-nao-edita-arquivo-da-ocorrencia" $? "$(aq_mostra)"
aq_hook docs/manutencao/OC-9999-sonda/sprint-01/tasks.md; [ "$AQ_RC" = 2 ]; afirma "aq9-feature-nao-edita-plano-da-ocorrencia" $? "$(aq_mostra)"

# -- a linha da runx nao e reivindicacao, na forma que ela grava e na compacta
aq_limpa; aq_feature "$AQF" fq
printf '{"ts": "2026-11-01T00:00:00Z", "expx_eventos": 1, "trabalho_id": "OC-9999", "ferramenta": "runx", "origem": "hook", "evento": "task_iniciada", "fase": "e3", "task": "T-01.01", "agente": null, "sessao": "eu@aq"}\n' > "$AQE/OC-9999.jsonl"
aq_hook infra/a.sh
[ "$AQ_RC" = 2 ] && case "$AQ_SAIDA" in *sessao_ambigua*) true ;; *) false ;; esac
afirma "aq10-linha-da-runx-como-ela-grava" $? "$(aq_mostra)"
printf '{"ts":"2026-11-01T00:00:00Z","expx_eventos":1,"trabalho_id":"OC-9999","ferramenta":"runx","origem":"hook","evento":"task_iniciada","fase":"e3","task":"T-01.01","agente":null,"sessao":"eu@aq"}\n' > "$AQE/OC-9999.jsonl"
aq_hook infra/a.sh
[ "$AQ_RC" = 2 ] && case "$AQ_SAIDA" in *sessao_ambigua*) true ;; *) false ;; esac
afirma "aq11-linha-compacta-da-runx" $? "$(aq_mostra)"
printf '{"ts":"2026-11-01T00:00:00Z","expx_eventos":1,"trabalho_id":"OC-9999","ferramenta" : "runx","origem":"hook","evento":"task_iniciada","fase":"e3","task":"T-01.01","agente":null,"sessao":"eu@aq"}\n' > "$AQE/OC-9999.jsonl"
aq_hook infra/a.sh
[ "$AQ_RC" = 2 ] && case "$AQ_SAIDA" in *sessao_ambigua*) true ;; *) false ;; esac
afirma "aq12-linha-compacta-com-espaco-no-campo" $? "$(aq_mostra)"

# -- o filtro so tira a linha da runx: a SprintX sem o campo conta, e os outros leitores concordam
aq_limpa; aq_feature "$AQF" fq
printf '{"ts":"2026-11-01T00:00:00Z","expx_eventos":1,"trabalho_id":"fq","origem":"skill","evento":"task_iniciada","fase":"f6","task":"T-01.01","agente":"principal","sessao":"eu@aq"}\n' > "$AQE/fq.jsonl"
aq_hook src/f.ts; [ "$AQ_RC" = 0 ]; afirma "aq16-linha-legada-sem-ferramenta-conta" $? "$(aq_mostra)"
printf '{"ts":"2026-11-01T00:00:00Z","expx_eventos":1,"trabalho_id":"fq","ferramenta":"runx","origem":"hook","evento":"task_iniciada","fase":"e3","task":"T-01.01","agente":null,"sessao":"outra@aq"}\n' >> "$AQE/fq.jsonl"
AQ_LEITORES="$(cd "$AQ" && EXPX_SESSAO=eu@aq bash -c '
  . "$1/comum/rastro.sh"
  rastro_dona_da_task_em d "$PWD" fq T-01.01; printf "dona=%s\n" "$d"
  printf "reiv=%s\n" "$(rastro_reivindicacoes_da_sessao "$PWD" eu@aq | tr "\t\n" "  ")"
  LC_ALL=C awk "$_RASTRO_AWK_REIV"'"'"'{ _rv_linha() } END { print "tam=" RV_TAM[FILENAME] }'"'"' docs/eventos/fq.jsonl
' _ "$H" 2>&1)"
case "$AQ_LEITORES" in *dona=eu@aq*) true ;; *) false ;; esac
afirma "aq17-dona-da-task-ignora-a-linha-da-runx" $? "$AQ_LEITORES"
case "$AQ_LEITORES" in *"reiv=fq T-01.01"*) true ;; *) false ;; esac
afirma "aq18-reivindicacoes-ignoram-a-linha-da-runx" $? "$AQ_LEITORES"
AQ_BYTES="$(wc -c < "$AQE/fq.jsonl" | tr -d ' ')"
case "$AQ_LEITORES" in *"tam=$AQ_BYTES"*) true ;; *) false ;; esac
afirma "aq19-rotacao-conta-os-bytes-da-linha-da-runx" $? "$AQ_LEITORES bytes=$AQ_BYTES"

# -- o recorte e estreito: slug de feature que parece ocorrencia, e o layout legado
aq_limpa
AQS="$AQ/docs/sprintx/features/OC-feature"; aq_feature "$AQS" OC-feature
printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: orquestrador\ntrabalho_id: OC-feature\n---\n' > "$AQS/ORQUESTRADOR.md"
aq_hook infra/a.sh; [ "$AQ_RC" = 2 ]; afirma "aq13-feature-canonica-com-slug-oc" $? "$(aq_mostra)"
printf '{"ts":"2026-11-01T00:00:00Z","expx_eventos":1,"trabalho_id":"OC-feature","ferramenta":"sprintx","origem":"skill","evento":"task_iniciada","fase":"f6","task":"T-01.01","agente":"principal","sessao":"eu@aq"}\n' > "$AQE/OC-feature.jsonl"
aq_hook src/f.ts; [ "$AQ_RC" = 0 ]; afirma "aq14-reivindicacao-da-sprintx-com-slug-oc-vale" $? "$(aq_mostra)"
rm -rf "$AQS"; aq_limpa
aq_feature "$AQ/docs/manutencao" manutencao
aq_hook infra/a.sh; [ "$AQ_RC" = 2 ]; afirma "aq15-feature-legada-com-slug-manutencao" $? "$(aq_mostra)"

# -- o comando da F1 nao faz a branch rastrear a base remota (DS-197)
AQW="$(mktemp -d)"
AQW_CMD="$(grep -o 'git worktree add -b feature/<slug> --no-track [^`]*<base>' "$SK/references/01-ingestao.md" | head -1)"
aq_cria() { # aq_cria <de onde> <slug> — o comando como esta escrito
  local c="${AQW_CMD//feature\/<slug>/feature/$2}"; c="${c//<repo>--<slug>/r--$2}"; c="${c//<base>/origin/main}"
  ( cd "$1" && eval "$c" >/dev/null 2>&1 )
}
git init -q --bare "$AQW/o.git"; git clone -q "$AQW/o.git" "$AQW/r" 2>/dev/null
git -C "$AQW/r" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m i
git -C "$AQW/r" push -q origin HEAD:refs/heads/main; git -C "$AQW/r" fetch -q
mkdir -p "$AQW/r/sub/dir" "$AQW/longe"
aq_cria "$AQW/r/sub/dir" a; AQW_RC=$?
[ "$AQW_RC" = 0 ] && [ -d "$AQW/r--a" ] && ! git -C "$AQW/r--a" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1
afirma "aq20-f1-de-subpasta-nasce-irma-e-sem-upstream" $? "rc=$AQW_RC cmd=$AQW_CMD (DS-197 e DS-198)"
git -C "$AQW/r" worktree add -q -b y --no-track "$AQW/longe/z" origin/main
aq_cria "$AQW/longe/z" b; AQW_RC=$?
[ "$AQW_RC" = 0 ] && [ -d "$AQW/r--b" ] && [ ! -e "$AQW/longe/r--b" ]
afirma "aq20b-f1-de-outro-worktree-nasce-irma-do-principal" $? "rc=$AQW_RC (DS-198)"
rm -rf "$AQW"
grep -Fq '`git worktree remove <caminho>` tira só esse registro' "$SK/references/01-ingestao.md"
afirma "aq21-f1-tira-so-o-registro-sem-pasta-antes-de-retomar" $? "01-ingestao.md (DS-198)"

rm -rf "$AQ"
