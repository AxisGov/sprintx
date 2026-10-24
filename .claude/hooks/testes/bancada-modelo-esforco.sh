#!/usr/bin/env bash
#
# Secao AN da bancada: o snapshot de modelo e esforco nos escritores proprios da skill (DS-186).
# Carregada por `.` de dentro da bancada.sh: usa `afirma`, `$H` e o estado dela.

echo "== AN. model/effort registram o executor efetivo, sem herdar configuracao Claude (DS-186) =="
# O contrato expx-eventos admite `model` e `effort` depois das doze chaves. Os escritores da
# skill (scripts/rastro.sh, planejamento.sh, bloqueios.sh) gravam as duas chaves; `null` diz
# que o runtime nao informou. As regras:
#
#   1. EXPX_MODEL/EXPX_EFFORT descrevem o executor EXPX_AGENTE (sem ela, `principal`). Linha
#      atribuida a OUTRO agente nao herda esses valores — o veredito do `auditor-plano` e
#      gravado pelo principal, e o modelo do principal nao e o do auditor.
#   2. O frontmatter de .claude/agents/<agente>.md so completa o snapshot de um SUBAGENTE, e so
#      no harness Claude (`claude`/`claude-code`). OpenCode, Codex ou runtime sem sinal: null.
#   3. `principal` nao tem arquivo: sem dado do runtime, null.
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
    -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID "${amb[@]}" \
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
an_caso an4-subagente-no-claude-usa-o-frontmatter "opus|high" "$(an_snap "$AN_J" veredito_emitido)"
an_fx; an_w CLAUDECODE=1 EXPX_MODEL=openai/gpt-5.4 EXPX_EFFORT=xhigh -- veredito-emitido fx SIM
an_caso an5-modelo-do-principal-nao-e-atribuido-ao-auditor "opus|high" "$(an_snap "$AN_J" veredito_emitido)"
an_fx; an_w CLAUDECODE=1 EXPX_AGENTE=auditor-plano EXPX_MODEL=google/gemini-3-pro -- veredito-emitido fx SIM
an_caso an6-explicito-do-proprio-auditor-vence-e-o-parcial-completa-no-claude "google/gemini-3-pro|high" "$(an_snap "$AN_J" veredito_emitido)"
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
(cd "$AN_T/fx" && env -u EXPX_AGENTE -u CLAUDECODE SPRINTX_RAIZ="$AN_T/fx" EXPX_MODEL=openai/gpt-5.4 EXPX_EFFORT=high \
  bash -c 'bash "$1" criar fx >/dev/null 2>&1; bash "$1" avanca fx f2 >/dev/null 2>&1' _ "$AN_SK/scripts/planejamento.sh")
an_caso an11-planejamento-grava-o-snapshot-do-principal "openai/gpt-5.4|high" "$(an_snap "$AN_J" checkpoint_planejamento)"
an_fx; rm -rf "$AN_T/fx/.git"
(cd "$AN_T/fx" && env -u EXPX_AGENTE -u EXPX_MODEL -u EXPX_EFFORT CLAUDECODE=1 SPRINTX_RAIZ="$AN_T/fx" \
  bash -c 'bash "$1" criar fx >/dev/null 2>&1; bash "$1" avanca fx f2 >/dev/null 2>&1' _ "$AN_SK/scripts/planejamento.sh")
an_caso an12-planejamento-sem-runtime-grava-null "None|None" "$(an_snap "$AN_J" checkpoint_planejamento)"

# bloqueios.sh — resolver grava bloqueio_resolvido
an_fx
(cd "$AN_T/fx" && env -u EXPX_AGENTE -u CLAUDECODE SPRINTX_RAIZ="$AN_T/fx" EXPX_HARNESS=opencode EXPX_MODEL=openai/gpt-5.4 \
  bash -c 'bash "$1" registrar fx null lacuna_de_decisao d x >/dev/null 2>&1; bash "$1" resolver fx B-01 >/dev/null 2>&1' _ "$AN_SK/scripts/bloqueios.sh")
an_caso an13-bloqueios-grava-o-snapshot-do-principal "openai/gpt-5.4|None" "$(an_snap "$AN_J" bloqueio_resolvido)"

# Legado continua valido: linha sem as chaves e "sem snapshot", nunca reescrita.
an_fx; mkdir -p "$AN_T/fx/docs/eventos"
printf '%s\n' '{"ts":"2026-09-26T10:23:54Z","expx_eventos":1,"trabalho_id":"fx","ferramenta":"sprintx","origem":"skill","evento":"fase_concluida","fase":"f2","task":null,"agente":"principal","resultado":"ok","detalhe":"legado","arquivos":[]}' > "$AN_J"
an_w CLAUDECODE=1 -- fase-iniciada fx f3
an_caso an14-linha-legada-segue-sem-snapshot "ausente" "$(an_snap "$AN_J" fase_concluida)"

rm -rf "$AN_T"
