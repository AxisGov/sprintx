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
ar_pl() { local d="$1"; shift; (cd "$d" && bash "$AR_PL" "$@") 2>&1; }
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
  && ar_tem "$ar_out" "scripts/planejamento.sh\" criar menu null <declarado_por> <max_replanejamentos_f6>" \
  && ar_tem "$ar_out" 'planejamento.sh replanejar-execucao menu' \
  && ar_tem "$ar_out" 'planejamento_legado' && ar_tem "$ar_out" 'Nada foi gravado'
afirma "ar1-legado-diz-o-comando-da-migracao" $? "rc=$ar_rc: $(printf '%s' "$ar_out" | tr '\n' ' ' | cut -c1-160)"

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

# AR6. o contrato escrito: a DS-224 e a orientacao da F6.
ar_ds="$(cat "$SK/DECISOES-DA-SKILL.md")"; ar_ex="$(cat "$SK/references/06-execucao.md")"
ar_tem "$ar_ds" '| DS-224' && ar_tem "$ar_ex" 'Plano legado (sem `00-PLANEJAMENTO.md`)'
afirma "ar6-contrato-escrito" $? "DS-224 e 06-execucao"

rm -rf "$AR"
