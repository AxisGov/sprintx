#!/usr/bin/env bash
#
# Secao AR da bancada: defeito_de_plano num plano legado, sem 00-PLANEJAMENTO.md (DS-224).
# O `bloqueios.sh resolver` diz que o plano e legado e da o comando da migracao; a migracao
# nao abre rodada de replanejamento nem consome o orcamento da F6; as rodadas da F5 que vem
# depois de uma migracao com VEREDITO: NÃO sao do laco F3 <-> F5, nunca da F6.
# Carregada por `.` de dentro da bancada.sh, ou sozinha por scripts/ci/test-plano-legado.sh.

[ -n "${SK:-}" ] && [ -f "$SK/SKILL.md" ] || {
  echo "bancada-plano-legado: carregue pela bancada.sh (SK ausente ou sem SKILL.md)" >&2
  return 2 2>/dev/null || exit 2
}

echo "== AR. defeito_de_plano num plano legado (DS-224) =="
AR="$(mktemp -d)"
AR_PL="$SK/scripts/planejamento.sh"
AR_BL="$SK/scripts/bloqueios.sh"
ar_kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }
ar_fm() { tr -d '\r' < "$1" | awk -v k="$2" 'NR==1{next} $0=="---"{exit} index($0,k": ")==1{print substr($0,length(k)+3); exit}'; }
ar_pl() { local d="$1"; shift; (cd "$d" && env -u SPRINTX_RAIZ bash "$AR_PL" "$@") 2>&1; }
ar_bl() { local d="$1"; shift; SPRINTX_RAIZ="$d" bash "$AR_BL" "$@" 2>&1; }
ar_tem() { grep -qF -- "$2" <<<"$1"; }

# ar_legado <dir> <SIM|NAO> — feature anterior ao 00-PLANEJAMENTO.md, ja na F6 (auditoria SIM)
# ou com a ultima linha VEREDITO: NÃO (o caso da onda 2 do conselhos): plano, orquestrador e
# auditoria commitados, T-01.01 bloqueada por um defeito_de_plano registrado pelo script.
ar_legado() {
  local d="$1" f="$1/docs/sprintx/features/menu"
  git init -q -b main "$d"; git -C "$d" config user.email t@t.local; git -C "$d" config user.name teste
  git -C "$d" config commit.gpgsign false; git -C "$d" config core.autocrlf false
  printf 'docs/eventos/\n' >> "$d/.git/info/exclude"
  mkdir -p "$d/src" "$f/base" "$f/sprint-01"; printf 'export const x = 1\n' > "$d/src/app.ts"
  git -C "$d" add -A; git -C "$d" commit -q -m init; git -C "$d" switch -q -c feature/menu
  printf 'indice\n' > "$f/base/00-INDICE.md"; printf 'decisoes\n' > "$f/00-DECISOES.md"
  printf 'orquestrador\n' > "$f/ORQUESTRADOR.md"
  printf -- '---\nkind: tasks\ntrabalho_id: menu\nsprint_id: sprint-01\ntasks:\n  - id: T-01.01\n    status: bloqueada\n    arquivos:\n      cria: [src/menu.ts]\n      altera: []\n---\n\n# Tasks\n' > "$f/sprint-01/tasks.md"
  if [ "$2" = SIM ]; then
    printf '# Auditoria\n\n| severidade | arquivo | problema | correção sugerida |\n|---|---|---|---|\n| BAIXA | sprint-01/tasks.md | [item 3] T-01.01 criterio com adjetivo | Reescrever |\n\nVEREDITO: SIM — o plano está pronto para execução autônoma.\n'
  else
    printf '# Auditoria\n\n| severidade | arquivo | problema | correção sugerida |\n|---|---|---|---|\n| ALTA | sprint-01/tasks.md | [item 9] T-01.01 escrita sem a assinatura lida | Ler a assinatura |\n\nVEREDITO: NÃO — o plano não está pronto.\n\n## Rodada 3\n\nVEREDITO FINAL DO PLANO: pronto ao resolver B-01.\n'
  fi > "$f/00-AUDITORIA.md"
  ar_bl "$d" registrar menu T-01.01 defeito_de_plano 'T-01.01 precisa de src/app.ts, fora do ownership' 'acrescentar o arquivo a T-01.01' >/dev/null || return 1
  git -C "$d" add -A; git -C "$d" commit -q -m "plano legado, sem 00-PLANEJAMENTO.md"
  [ ! -e "$f/00-PLANEJAMENTO.md" ] && [ "$(ar_kv "$(ar_pl "$d" fase menu)" fonte)" = legado ]
}

AR_S="$AR/sim"; ar_legado "$AR_S" SIM; afirma "ar0-fixture-legado-na-f6" $? "sem 00-PLANEJAMENTO.md, auditoria SIM, B-01 defeito_de_plano"
AR_N="$AR/nao"; ar_legado "$AR_N" NAO; afirma "ar0-fixture-legado-veredito-nao" $? "sem 00-PLANEJAMENTO.md, ultima linha VEREDITO: NÃO"
AR_F="$AR_S/docs/sprintx/features/menu"

# AR1. resolver um defeito_de_plano num plano legado: codigo 5, nada gravado, e a mensagem diz
# que o plano e legado e da o comando da migracao, com o slug do trabalho e o orcamento
# deixado para quem o declara (nada inventado).
ar_ck="$(cksum < "$AR_F/00-BLOQUEIOS.md")"
ar_out="$(ar_bl "$AR_S" resolver menu B-01)"; ar_rc=$?
[ "$ar_rc" -eq 5 ] && [ "$(cksum < "$AR_F/00-BLOQUEIOS.md")" = "$ar_ck" ] && [ ! -e "$AR_F/00-PLANEJAMENTO.md" ] \
  && ar_tem "$ar_out" 'plano legado' && ar_tem "$ar_out" 'sem 00-PLANEJAMENTO.md' \
  && ar_tem "$ar_out" "/scripts/planejamento.sh criar menu null DECLARADO_POR MAX_REPLANEJAMENTOS_F6" \
  && ar_tem "$ar_out" "/scripts/planejamento.sh checkpoint menu" \
  && ar_tem "$ar_out" "/scripts/planejamento.sh replanejar-execucao menu" \
  && [ "$(grep -oF -- "SPRINTX_RAIZ=$AR_S bash " <<<"$ar_out" | wc -l)" -eq 4 ] \
  && ar_tem "$ar_out" 'planejamento_legado' && ar_tem "$ar_out" 'Nada foi gravado'
afirma "ar1-legado-diz-o-comando-da-migracao" $? "rc=$ar_rc: $(printf '%s' "$ar_out" | tr '\n' ' ' | cut -c1-160)"

# AR1b. chamado de dentro do repositorio, sem SPRINTX_RAIZ, o comando nao a inventa; com ela, o
# comando leva a mesma raiz que o resolver usou (CodeAnt no sprintx#83).
ar_out="$( (cd "$AR_S" && env -u SPRINTX_RAIZ bash "$AR_BL" resolver menu B-01) 2>&1)"; ar_rc=$?
[ "$ar_rc" -eq 5 ] && ar_tem "$ar_out" "— bash " && ar_tem "$ar_out" "/scripts/planejamento.sh criar menu null" && ! ar_tem "$ar_out" 'SPRINTX_RAIZ='
afirma "ar1b-sem-raiz-explicita-o-comando-nao-a-inventa" $? "rc=$ar_rc: $(printf '%s' "$ar_out" | tr '\n' ' ' | cut -c1-160)"

# AR2. o comando dado, com o orcamento declarado, migra: estado aprovado (o disco tem
# VEREDITO: SIM), nenhuma rodada aberta, nenhum replanejamento consumido.
ar_out="$(ar_pl "$AR_S" criar menu null flavio 1)"
[ "$(ar_kv "$ar_out" planejamento)" = migrado_legado ] && [ "$(ar_fm "$AR_F/00-PLANEJAMENTO.md" estado)" = aprovado ] \
  && [ "$(ar_fm "$AR_F/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ] && [ "$(ar_fm "$AR_F/00-PLANEJAMENTO.md" max_replanejamentos_f6)" = 1 ] \
  && [ "$(ar_fm "$AR_F/00-PLANEJAMENTO.md" bloqueios_replanejamento_f6)" = "[]" ] && [ "$(ar_fm "$AR_F/00-PLANEJAMENTO.md" reprovacoes)" = 0 ] \
  && [ "$(tr -d '\r' < "$AR_F/00-PLANEJAMENTO.md" | grep -c '^  - rodada:')" -eq 1 ]
afirma "ar2-migracao-nao-abre-rodada-nem-consome-f6" $? "$(printf '%s' "$ar_out" | tr '\n' ' ' | cut -c1-160)"

# AR3. depois do checkpoint da migracao, o replanejamento da execucao abre a rodada 1 de 1:
# o orcamento da F6 chega inteiro ao defeito_de_plano.
ar_pl "$AR_S" checkpoint menu >/dev/null
ar_out="$(ar_pl "$AR_S" replanejar-execucao menu)"
[ "$(ar_kv "$ar_out" replanejamento)" = iniciado ] && [ "$(ar_kv "$ar_out" replanejamentos_f6)" = 1 ] \
  && [ "$(ar_kv "$ar_out" max_replanejamentos_f6)" = 1 ] && [ "$(ar_fm "$AR_F/00-PLANEJAMENTO.md" bloqueios_replanejamento_f6)" = "[B-01]" ]
afirma "ar3-orcamento-f6-inteiro-para-o-defeito" $? "$(printf '%s' "$ar_out" | tr '\n' ' ' | cut -c1-160)"

# AR4. fora do legado, a recusa diz o motivo do pode-resolver (aqui, a rodada ainda nao aprovada).
ar_out="$(ar_bl "$AR_S" resolver menu B-01)"; ar_rc=$?
[ "$ar_rc" -eq 5 ] && ar_tem "$ar_out" 'motivo: rodada_nao_aprovada' && ! ar_tem "$ar_out" 'plano legado'
afirma "ar4-recusa-diz-o-motivo" $? "rc=$ar_rc: $(printf '%s' "$ar_out" | tr '\n' ' ' | cut -c1-160)"

# AR5. o caso da onda 2 do conselhos: o disco termina em VEREDITO: NÃO (a rodada seguinte nao
# usou a linha canonica). A migracao nasce em replanejar (DS-137): a proxima fase e a F3, as
# rodadas da F5 que vierem sao do laco F3 <-> F5, e o orcamento da F6 continua intacto. O
# checkpoint da migracao sai rotulado "f5 rodada 1": e a rodada legada, que ja tinha acontecido,
# nao uma passagem nova pela F5.
AR_FN="$AR_N/docs/sprintx/features/menu"
ar_out="$(ar_pl "$AR_N" criar menu null flavio 1)"
ar_ck="$(ar_pl "$AR_N" checkpoint menu)"
[ "$(ar_kv "$ar_out" estado)" = replanejar ] && [ "$(ar_fm "$AR_FN/00-PLANEJAMENTO.md" reprovacoes)" = 1 ] \
  && [ "$(ar_fm "$AR_FN/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ] && [ "$(ar_fm "$AR_FN/00-PLANEJAMENTO.md" bloqueios_replanejamento_f6)" = "[]" ] \
  && [ "$(ar_kv "$ar_ck" fase)" = f5 ] && [ "$(ar_kv "$ar_ck" rodada)" = 1 ] \
  && [ "$(ar_kv "$(ar_pl "$AR_N" fase menu)" fase)" = F3 ]
afirma "ar5-veredito-nao-volta-a-f3-sem-tocar-a-f6" $? "$(printf '%s' "$ar_out" | tr '\n' ' ' | cut -c1-160)"

# AR7. o replanejar-execucao num plano legado recusa SEM GRAVAR (DS-225): nenhum
# 00-PLANEJAMENTO.md, nenhum checkpoint, codigo 5, e o mesmo comando da migracao do resolver
# (com o SPRINTX_RAIZ que veio do ambiente). Repetir da o mesmo, e a migracao continua aberta.
AR_L="$AR/legado"; ar_legado "$AR_L" SIM
AR_FL="$AR_L/docs/sprintx/features/menu"; ar_h="$(git -C "$AR_L" rev-parse HEAD)"
ar_out="$(SPRINTX_RAIZ="$AR_L" bash "$AR_PL" replanejar-execucao menu 2>&1)"; ar_rc=$?
[ "$ar_rc" -eq 5 ] && [ ! -e "$AR_FL/00-PLANEJAMENTO.md" ] && [ "$(git -C "$AR_L" rev-parse HEAD)" = "$ar_h" ] \
  && [ -z "$(git -C "$AR_L" status --porcelain -- docs/sprintx)" ] \
  && [ "$(ar_kv "$ar_out" replanejamento)" = recusado ] && [ "$(ar_kv "$ar_out" motivo)" = planejamento_legado ] \
  && [ "$(ar_kv "$ar_out" persistencia)" = disco ] && ar_tem "$ar_out" 'plano legado' \
  && ar_tem "$ar_out" "/scripts/planejamento.sh criar menu null DECLARADO_POR MAX_REPLANEJAMENTOS_F6" \
  && ar_tem "$ar_out" "/scripts/planejamento.sh checkpoint menu" \
  && ar_tem "$ar_out" "/scripts/planejamento.sh replanejar-execucao menu" \
  && [ "$(grep -oF -- "SPRINTX_RAIZ=$AR_L bash " <<<"$ar_out" | wc -l)" -eq 4 ] \
  && ar_tem "$ar_out" 'Nada foi gravado'
afirma "ar7-legado-recusa-sem-gravar-o-terminal" $? "rc=$ar_rc: $(printf '%s' "$ar_out" | tr '\n' ' ' | cut -c1-200)"
ar_out="$(ar_pl "$AR_L" replanejar-execucao menu)"; ar_rc=$?
[ "$ar_rc" -eq 5 ] && [ ! -e "$AR_FL/00-PLANEJAMENTO.md" ] && [ "$(git -C "$AR_L" rev-parse HEAD)" = "$ar_h" ] \
  && [ "$(ar_kv "$ar_out" motivo)" = planejamento_legado ] && ! ar_tem "$ar_out" 'SPRINTX_RAIZ=' \
  && ar_tem "$ar_out" "/scripts/planejamento.sh criar menu null DECLARADO_POR MAX_REPLANEJAMENTOS_F6" \
  && [ "$(ar_kv "$(ar_pl "$AR_L" criar menu null flavio 1)" planejamento)" = migrado_legado ] \
  && ar_pl "$AR_L" checkpoint menu >/dev/null \
  && [ "$(ar_kv "$(ar_pl "$AR_L" replanejar-execucao menu)" replanejamento)" = iniciado ]
afirma "ar7b-repetir-recusa-igual-e-a-migracao-continua-aberta" $? "rc=$ar_rc: $(printf '%s' "$ar_out" | tr '\n' ' ' | cut -c1-200)"

# AR8. quem ja ficou preso: um 00-PLANEJAMENTO.md que uma versao anterior gravou no terminal
# planejamento_legado continua como esta. Nenhum comando da sprintx sai dele (o criar nao muda o
# teto, a autorizacao tardia so parte de orcamento_f6_nao_declarado), e a recusa diz isso.
AR_P="$AR/preso"; ar_legado "$AR_P" SIM; AR_FP="$AR_P/docs/sprintx/features/menu"
ar_pl "$AR_P" criar menu >/dev/null
awk '$0 == "estado: aprovado" { print "estado: replanejamento_execucao_recusado"; print "recusa_replanejamento_f6: planejamento_legado"; next } { print }' \
  "$AR_FP/00-PLANEJAMENTO.md" > "$AR/p.tmp" && mv "$AR/p.tmp" "$AR_FP/00-PLANEJAMENTO.md"
git -C "$AR_P" add -A && git -C "$AR_P" commit -q -m "terminal planejamento_legado de uma versao anterior"
ar_h="$(git -C "$AR_P" rev-parse HEAD)"; ar_ck="$(cksum < "$AR_FP/00-PLANEJAMENTO.md")"
ar_out="$(ar_pl "$AR_P" replanejar-execucao menu)"; ar_rc=$?
ar_pl "$AR_P" criar menu null flavio 1 >/dev/null; ar_rc_criar=$?
ar_pl "$AR_P" autorizar-replanejamento-execucao menu 1 flavio >/dev/null; ar_rc_aut=$?
[ "$ar_rc" -eq 5 ] && [ "$(ar_kv "$ar_out" motivo)" = planejamento_legado ] && [ "$(ar_kv "$ar_out" estado)" = replanejamento_execucao_recusado ] \
  && ar_tem "$ar_out" 'versao anterior' && ar_tem "$ar_out" 'Nenhum comando da sprintx sai deste terminal' && ar_tem "$ar_out" 'decisao humana' \
  && [ "$ar_rc_criar" -eq 4 ] && [ "$ar_rc_aut" -eq 5 ] \
  && [ "$(git -C "$AR_P" rev-parse HEAD)" = "$ar_h" ] && [ "$(cksum < "$AR_FP/00-PLANEJAMENTO.md")" = "$ar_ck" ]
afirma "ar8-preso-no-terminal-antigo-fica-e-a-recusa-diz" $? "rc=$ar_rc criar=$ar_rc_criar aut=$ar_rc_aut: $(printf '%s' "$ar_out" | tr '\n' ' ' | cut -c1-200)"

# AR9. a raiz com aspa simples, espaco e $(...) sai citada nos comandos impressos pelo resolver e pelo
# replanejar-execucao: lida pela shell, volta inteira, e nada executa (CodeAnt no sprintx#83).
AR_Q="$AR/raiz 'a' "'$(mkdir PWNED)'
# Sem Git: o Git for Windows nao cria pasta com esse nome, e nem o resolver nem a recusa do legado
# precisam dele. A feature e a do AR_S, sem o 00-PLANEJAMENTO.md que o AR2 migrou.
mkdir -p "$AR_Q" && cp -R "$AR_S/docs" "$AR_Q/" && rm -f "$AR_Q/docs/sprintx/features/menu/00-PLANEJAMENTO.md"
ar_cita_ok() { # ar_cita_ok <saida> — o valor de SPRINTX_RAIZ e o caminho do script, relidos pela shell
  local q p
  q="${1#*SPRINTX_RAIZ=}"; q="${q%% bash *}"; p="${1#*SPRINTX_RAIZ=}"; p="${p#* bash }"; p="${p%% criar menu*}"
  ( cd "$AR" && eval "q=$q" && eval "p=$p" && [ "$q" = "$AR_Q" ] && [ -f "$p" ] ) && [ ! -e "$AR/PWNED" ]
}
ar_out="$(ar_bl "$AR_Q" resolver menu B-01)"; ar_rc=$?
[ "$ar_rc" -eq 5 ] && ar_cita_ok "$ar_out"
afirma "ar9-resolver-cita-a-raiz" $? "rc=$ar_rc: $(printf '%s' "$ar_out" | tr '\n' ' ' | cut -c1-200)"
ar_out="$(SPRINTX_RAIZ="$AR_Q" bash "$AR_PL" replanejar-execucao menu 2>&1)"; ar_rc=$?
[ "$ar_rc" -eq 5 ] && ar_cita_ok "$ar_out" && [ ! -e "$AR_Q/docs/sprintx/features/menu/00-PLANEJAMENTO.md" ]
afirma "ar9b-replanejar-cita-a-raiz" $? "rc=$ar_rc: $(printf '%s' "$ar_out" | tr '\n' ' ' | cut -c1-200)"

# AR10. o comando nao manda direto ao replanejar-execucao: a migracao pode voltar o plano a F3
# (ultima linha VEREDITO: NÃO), e a mensagem diz como saber, pelo `fase` (CodeAnt no sprintx#83).
ar_out_r="$(ar_bl "$AR_Q" resolver menu B-01)"; ar_out_p="$(SPRINTX_RAIZ="$AR_Q" bash "$AR_PL" replanejar-execucao menu 2>&1)"
ar_tem "$ar_out_r" "/scripts/planejamento.sh fase menu" && ar_tem "$ar_out_r" 'em F3' \
  && ar_tem "$ar_out_p" "/scripts/planejamento.sh fase menu" && ar_tem "$ar_out_p" 'em F3'
afirma "ar10-mensagem-confere-a-fase-antes-de-replanejar" $? "$(printf '%s' "$ar_out_p" | tr '\n' ' ' | cut -c1-200)"

# AR6. o contrato escrito: a DS-224 e a orientacao da F6.
ar_ds="$(cat "$SK/DECISOES-DA-SKILL.md")"; ar_ex="$(cat "$SK/references/06-execucao.md")"
ar_tem "$ar_ds" '| DS-224' && ar_tem "$ar_ds" '| DS-225' && ar_tem "$ar_ex" 'Plano legado (sem `00-PLANEJAMENTO.md`)' \
  && ar_tem "$ar_ex" 'Se o plano for legado (sem `00-PLANEJAMENTO.md`), migre antes'
afirma "ar6-contrato-escrito" $? "DS-224, DS-225 e 06-execucao"

rm -rf "$AR"
