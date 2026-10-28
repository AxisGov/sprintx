#!/usr/bin/env bash
#
# Secao AN da bancada: o snapshot de modelo e esforco nos escritores proprios da skill (DS-186,
# DS-190). Carregada por `.` de dentro da bancada.sh: usa `afirma`, `$H` e o estado dela.

echo "== AN. model/effort sao so o executor observado, e a resolucao vem da projecao (DS-186, DS-190) =="
# O contrato expx-eventos admite `model` e `effort` depois das doze chaves. Os escritores da
# skill (scripts/rastro.sh, planejamento.sh, bloqueios.sh) gravam as duas chaves; `null` diz
# que o runtime nao informou. As regras, as mesmas do escritor comum do ExpxDev (H10):
#
#   1. EXPX_MODEL/EXPX_EFFORT descrevem o executor EXPX_AGENTE (sem ela, `principal`). Linha
#      atribuida a OUTRO agente nao herda esses valores — o veredito do `auditor-plano` e
#      gravado pelo principal, e o modelo do principal nao e o do auditor.
#   2. No contexto Claude, $CLAUDE_EFFORT e o esforco da sessao: so para linha do `principal`,
#      e so quando EXPX_EFFORT nao veio.
#   3. Nunca configuracao: o frontmatter de .claude/agents/<agente>.md nao completa nada.
#   4. A intencao vai em chaves separadas: com a projecao `.expx/orquestracao-rastro.tsv`
#      valida, a linha de um SUBAGENTE no Claude leva a resolucao dele; projecao ausente ou
#      fora do formato, nenhuma chave — nunca parte delas.
AN_T="$(mktemp -d)"
AN_SK="$(cd "$H/../skills/sprintx" && pwd)"

an_fx() { # an_fx — repo git com o trabalho fx e o auditor-plano instalado (opus/high)
  rm -rf "$AN_T/fx"; mkdir -p "$AN_T/fx/docs/sprintx/features/fx" "$AN_T/fx/.claude/agents"
  git init -q --template= "$AN_T/fx" >/dev/null 2>&1
  printf -- '---\nname: auditor-plano\nmodel: opus\neffort: high\n---\n' > "$AN_T/fx/.claude/agents/auditor-plano.md"
}
# an_w <env...> -- <args do rastro.sh> — sem nenhum sinal de harness herdado do executor
an_w() {
  local amb=()
  while [ "$1" != -- ]; do amb+=("$1"); shift; done; shift
  (cd "$AN_T/fx" && env -u EXPX_SESSAO -u EXPX_HARNESS -u EXPX_MODEL -u EXPX_EFFORT -u EXPX_AGENTE \
    -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_EFFORT "${amb[@]}" \
    bash "$AN_SK/scripts/rastro.sh" "$@" >/dev/null 2>&1)
}
# an_snap <arquivo> <evento> — "model|effort" da ultima linha do evento; "ausente" sem as chaves
an_snap() {
  python3 - "$1" "$2" <<'PY'
import json, os, sys
if not os.path.exists(sys.argv[1]): print("sem-arquivo"); sys.exit()
linhas = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
ev = [l for l in linhas if l["evento"] == sys.argv[2]]
if not ev: print("sem-linha"); sys.exit()
u = ev[-1]
if "model" not in u or "effort" not in u: print("ausente"); sys.exit()
print("%s|%s" % (u["model"], u["effort"]))
PY
}
an_caso() { # an_caso <nome> <esperado> <obtido>
  [ "$3" = "$2" ]; afirma "$1" $? "esperado $2, gravado $3"
}
AN_J="$AN_T/fx/docs/eventos/fx.jsonl"

# rastro.sh — principal
an_fx; an_w CLAUDECODE=1 -- fase-iniciada fx f3
an_caso an1-principal-claude-sem-runtime-grava-null "None|None" "$(an_snap "$AN_J" fase_iniciada)"
an_fx; an_w EXPX_HARNESS=opencode EXPX_MODEL=openai/gpt-5.4 EXPX_EFFORT=high -- fase-iniciada fx f3
an_caso an2-explicito-do-runtime-vence-em-qualquer-harness "openai/gpt-5.4|high" "$(an_snap "$AN_J" fase_iniciada)"
an_fx; an_w CLAUDECODE=1 EXPX_AGENTE=sprintx-investigador EXPX_MODEL=sonnet EXPX_EFFORT=low -- fase-iniciada fx f3
an_caso an3-explicito-de-outro-agente-nao-vai-para-o-principal "None|None" "$(an_snap "$AN_J" fase_iniciada)"

# rastro.sh — veredito do auditor-plano, gravado pelo principal
an_fx; an_w CLAUDECODE=1 -- veredito-emitido fx SIM
an_caso an4-subagente-no-claude-nao-usa-o-frontmatter "None|None" "$(an_snap "$AN_J" veredito_emitido)"
an_fx; an_w CLAUDECODE=1 EXPX_MODEL=openai/gpt-5.4 EXPX_EFFORT=xhigh -- veredito-emitido fx SIM
an_caso an5-modelo-do-principal-nao-e-atribuido-ao-auditor "None|None" "$(an_snap "$AN_J" veredito_emitido)"
an_fx; an_w CLAUDECODE=1 EXPX_AGENTE=auditor-plano EXPX_MODEL=google/gemini-3-pro -- veredito-emitido fx SIM
an_caso an6-so-o-modelo-observado-o-esforco-nao-e-completado "google/gemini-3-pro|None" "$(an_snap "$AN_J" veredito_emitido)"
an_fx; an_w CLAUDECODE=1 EXPX_AGENTE=auditor-plano EXPX_EFFORT=high -- veredito-emitido fx SIM
an_caso an6b-so-o-esforco-observado-o-modelo-nao-e-completado "None|high" "$(an_snap "$AN_J" veredito_emitido)"
an_fx; an_w EXPX_HARNESS=opencode -- veredito-emitido fx SIM
an_caso an7-opencode-nao-herda-configuracao-claude "None|None" "$(an_snap "$AN_J" veredito_emitido)"
an_fx; an_w EXPX_HARNESS=codex EXPX_AGENTE=auditor-plano EXPX_MODEL=openai/gpt-5.4-codex -- veredito-emitido fx SIM
an_caso an8-parcial-fora-do-claude-nao-e-completado "openai/gpt-5.4-codex|None" "$(an_snap "$AN_J" veredito_emitido)"
an_fx; an_w -- veredito-emitido fx SIM
an_caso an9-runtime-sem-sinal-de-harness-grava-null "None|None" "$(an_snap "$AN_J" veredito_emitido)"
an_fx; an_w CLAUDECODE=1 EXPX_MODEL='x"y\z' -- fase-iniciada fx f3
an_caso an10-valor-explicito-sai-escapado-em-json-valido 'x"y\z|None' "$(an_snap "$AN_J" fase_iniciada)"

# planejamento.sh — checkpoint sem Git grava o aviso pelo escritor proprio
an_fx; rm -rf "$AN_T/fx/.git"
(cd "$AN_T/fx" && env -u EXPX_AGENTE -u EXPX_HARNESS -u EXPX_MODEL -u EXPX_EFFORT -u CLAUDECODE -u CLAUDE_EFFORT SPRINTX_RAIZ="$AN_T/fx" EXPX_MODEL=openai/gpt-5.4 EXPX_EFFORT=high \
  bash -c 'bash "$1" criar fx >/dev/null 2>&1; bash "$1" avanca fx f2 >/dev/null 2>&1' _ "$AN_SK/scripts/planejamento.sh")
an_caso an11-planejamento-grava-o-snapshot-do-principal "openai/gpt-5.4|high" "$(an_snap "$AN_J" checkpoint_planejamento)"
an_fx; rm -rf "$AN_T/fx/.git"
(cd "$AN_T/fx" && env -u EXPX_AGENTE -u EXPX_HARNESS -u EXPX_MODEL -u EXPX_EFFORT -u CLAUDE_EFFORT CLAUDECODE=1 SPRINTX_RAIZ="$AN_T/fx" \
  bash -c 'bash "$1" criar fx >/dev/null 2>&1; bash "$1" avanca fx f2 >/dev/null 2>&1' _ "$AN_SK/scripts/planejamento.sh")
an_caso an12-planejamento-sem-runtime-grava-null "None|None" "$(an_snap "$AN_J" checkpoint_planejamento)"

# bloqueios.sh — resolver grava bloqueio_resolvido
an_fx
(cd "$AN_T/fx" && env -u EXPX_AGENTE -u EXPX_HARNESS -u EXPX_MODEL -u EXPX_EFFORT -u CLAUDECODE -u CLAUDE_EFFORT SPRINTX_RAIZ="$AN_T/fx" EXPX_HARNESS=opencode EXPX_MODEL=openai/gpt-5.4 \
  bash -c 'bash "$1" registrar fx null lacuna_de_decisao d x >/dev/null 2>&1; bash "$1" resolver fx B-01 >/dev/null 2>&1' _ "$AN_SK/scripts/bloqueios.sh")
an_caso an13-bloqueios-grava-o-snapshot-do-principal "openai/gpt-5.4|None" "$(an_snap "$AN_J" bloqueio_resolvido)"

# $CLAUDE_EFFORT: o esforco da sessao, so para o principal no Claude (regra 2)
an_fx; an_w CLAUDECODE=1 CLAUDE_EFFORT=high -- fase-iniciada fx f3
an_caso an15-principal-no-claude-usa-o-claude-effort "None|high" "$(an_snap "$AN_J" fase_iniciada)"
an_fx; an_w CLAUDECODE=1 CLAUDE_EFFORT=high EXPX_EFFORT=low -- fase-iniciada fx f3
an_caso an16-expx-effort-vence-o-claude-effort "None|low" "$(an_snap "$AN_J" fase_iniciada)"
an_fx; an_w CLAUDECODE=1 CLAUDE_EFFORT=high -- veredito-emitido fx SIM
an_caso an17-claude-effort-da-sessao-nao-vai-para-o-auditor "None|None" "$(an_snap "$AN_J" veredito_emitido)"
an_fx; an_w EXPX_HARNESS=opencode CLAUDECODE=1 CLAUDE_EFFORT=high -- fase-iniciada fx f3
an_caso an18-harness-declarado-fora-do-claude-ignora-o-claude-effort "None|None" "$(an_snap "$AN_J" fase_iniciada)"
(cd "$AN_T/fx" && env -u EXPX_AGENTE -u EXPX_HARNESS -u EXPX_MODEL -u EXPX_EFFORT -u CLAUDE_EFFORT CLAUDECODE=1 CLAUDE_EFFORT=high SPRINTX_RAIZ="$AN_T/fx" \
  bash -c 'rm -rf .git; bash "$1" criar fx >/dev/null 2>&1; bash "$1" avanca fx f2 >/dev/null 2>&1' _ "$AN_SK/scripts/planejamento.sh")
an_caso an19-planejamento-usa-o-claude-effort-do-principal "None|high" "$(an_snap "$AN_J" checkpoint_planejamento)"
an_fx
(cd "$AN_T/fx" && env -u EXPX_AGENTE -u EXPX_HARNESS -u EXPX_MODEL -u EXPX_EFFORT -u CLAUDE_EFFORT CLAUDECODE=1 CLAUDE_EFFORT=medium SPRINTX_RAIZ="$AN_T/fx" \
  bash -c 'bash "$1" registrar fx null lacuna_de_decisao d x >/dev/null 2>&1; bash "$1" resolver fx B-01 >/dev/null 2>&1' _ "$AN_SK/scripts/bloqueios.sh")
an_caso an20-bloqueios-usa-o-claude-effort-do-principal "None|medium" "$(an_snap "$AN_J" bloqueio_resolvido)"

# A resolucao (regra 4), da projecao que o `expx init` grava com a politica ativa
AN_ID="$(printf 'a%.0s' $(seq 1 64))"
an_proj() { # an_proj <linhas...> — a projecao, com o cabecalho, cada argumento uma linha
  mkdir -p "$AN_T/fx/.expx"
  { printf '# expx-orquestracao-rastro 1\n'; printf '%s\n' "$@"; } > "$AN_T/fx/.expx/orquestracao-rastro.tsv"
}
an_linha() { # an_linha <agente> [id] [mm] [me] [oa] — uma linha valida com nove campos
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$1" "${2:-$AN_ID}" raciocinio_normal declarada profundo_excepcional \
    claude-opus-high "${5:-projeto}" "${3:--}" "${4:--}"
}
# an_res <arquivo> <evento> — as chaves da resolucao da ultima linha do evento, ou "nenhuma"
an_res() {
  python3 - "$1" "$2" <<'PY'
import json, sys
ks = ["resolucao_id", "classe_declarada", "classe_resolvida", "origem_classe", "alternativa", "origem_alternativa", "materializado"]
linhas = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
u = [l for l in linhas if l["evento"] == sys.argv[2]][-1]
r = {k: u[k] for k in ks if k in u}
print(json.dumps(r, sort_keys=True, separators=(",", ":")) if r else "nenhuma")
PY
}
AN_RES_OK="{\"alternativa\":\"claude-opus-high\",\"classe_declarada\":\"raciocinio_normal\",\"classe_resolvida\":\"profundo_excepcional\",\"origem_alternativa\":\"projeto\",\"origem_classe\":\"declarada\",\"resolucao_id\":\"$AN_ID\"}"
an_fx; an_proj "$(an_linha auditor-plano)"; an_w CLAUDECODE=1 -- veredito-emitido fx SIM
an_caso an21-subagente-no-claude-leva-a-resolucao-da-projecao "$AN_RES_OK" "$(an_res "$AN_J" veredito_emitido)"
an_caso an21b-a-resolucao-nao-vira-model-effort "None|None" "$(an_snap "$AN_J" veredito_emitido)"
an_fx; an_proj "$(an_linha auditor-plano "$AN_ID" opus high agentes-json-v1)"; an_w CLAUDECODE=1 -- veredito-emitido fx SIM
an_caso an22-materializado-com-esforco "{\"effort\":\"high\",\"model\":\"opus\"}" \
  "$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1]).get("materializado"),separators=(",",":")))' "$(an_res "$AN_J" veredito_emitido)")"
an_fx; an_proj "$(an_linha auditor-plano "$AN_ID" opus - agentes-json-v1)"; an_w CLAUDECODE=1 -- veredito-emitido fx SIM
an_caso an23-materializado-sem-esforco "{\"model\":\"opus\"}" \
  "$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1]).get("materializado"),separators=(",",":")))' "$(an_res "$AN_J" veredito_emitido)")"
an_fx; an_proj "$(an_linha auditor-plano)"; an_w CLAUDECODE=1 -- fase-iniciada fx f3
an_caso an24-principal-nao-leva-resolucao "nenhuma" "$(an_res "$AN_J" fase_iniciada)"
an_fx; an_proj "$(an_linha auditor-plano)"; an_w EXPX_HARNESS=opencode -- veredito-emitido fx SIM
an_caso an25-fora-do-claude-nao-leva-resolucao "nenhuma" "$(an_res "$AN_J" veredito_emitido)"
an_fx; an_proj "$(an_linha sprintx-investigador)"; an_w CLAUDECODE=1 -- veredito-emitido fx SIM
an_caso an26-agente-fora-da-projecao-nao-leva-resolucao "nenhuma" "$(an_res "$AN_J" veredito_emitido)"
an_fx; an_w CLAUDECODE=1 -- veredito-emitido fx SIM
an_caso an27-sem-projecao-nao-leva-resolucao "nenhuma" "$(an_res "$AN_J" veredito_emitido)"
# projecao fora do formato: nenhuma chave, nunca parte delas
an_ruim() { # an_ruim <nome> — grava o veredito com a projecao ja montada e confere "nenhuma"
  an_w CLAUDECODE=1 -- veredito-emitido fx SIM
  an_caso "$1" "nenhuma" "$(an_res "$AN_J" veredito_emitido)"
}
an_fx; mkdir -p "$AN_T/fx/.expx"; { printf '# expx-orquestracao-rastro 2\n'; an_linha auditor-plano; printf '\n'; } > "$AN_T/fx/.expx/orquestracao-rastro.tsv"
an_ruim an28-cabecalho-de-outra-versao
an_fx; an_proj "$(an_linha auditor-plano | cut -f1-8)"; an_ruim an29-sete-tabs
an_fx; an_proj "$(an_linha auditor-plano)$(printf '\textra')"; an_ruim an30-nove-tabs
an_fx; an_proj "$(an_linha auditor-plano "$AN_ID" '-' '-' 'proj"eto')"; an_ruim an31-campo-fora-do-alfabeto
an_fx; an_proj "$(an_linha auditor-plano "abc")"; an_ruim an32-resolucao-id-fora-do-formato
an_fx; an_proj "$(an_linha auditor-plano)" "$(an_linha auditor-plano)"; an_ruim an33-agente-repetido
an_fx; an_proj "$(an_linha auditor-plano "$AN_ID" opus high projeto)"; an_ruim an34-materializado-fora-da-excecao-v1

# Legado continua valido: linha sem as chaves e "sem snapshot", nunca reescrita.
an_fx; mkdir -p "$AN_T/fx/docs/eventos"
printf '%s\n' '{"ts":"2026-09-26T10:23:54Z","expx_eventos":1,"trabalho_id":"fx","ferramenta":"sprintx","origem":"skill","evento":"fase_concluida","fase":"f2","task":null,"agente":"principal","resultado":"ok","detalhe":"legado","arquivos":[]}' > "$AN_J"
an_w CLAUDECODE=1 -- fase-iniciada fx f3
an_caso an14-linha-legada-segue-sem-snapshot "ausente" "$(an_snap "$AN_J" fase_concluida)"

rm -rf "$AN_T"
