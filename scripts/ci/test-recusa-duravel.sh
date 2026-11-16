#!/usr/bin/env bash
#
# test-recusa-duravel — a recusa terminal do replanejar-execucao (classes_mistas e afins) so e
# gravada se a condicao continuar valendo: os bloqueios sao relidos sob a trava da F6, e um
# bloqueio resolvido entre a leitura e a gravacao nao deixa recusa desatualizada (CodeAnt no
# login#95).
#
#   bash scripts/ci/test-recusa-duravel.sh
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_PREFIX

RAIZ_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SK="$RAIZ_SRC/.claude/skills/sprintx"
PL="$SK/scripts/planejamento.sh"; BL="$SK/scripts/bloqueios.sh"
ok=0; falhou=0
afirma() { if [ "$2" -eq 0 ]; then ok=$((ok+1)); printf '  ok    %s\n' "$1"; else falhou=$((falhou+1)); printf '  FALHA %s  %s\n' "$1" "${3:-}"; fi; }
kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }
fm() { tr -d '\r' < "$1" | awk -v k="$2" 'NR==1{next} $0=="---"{exit} index($0,k": ")==1{print substr($0,length(k)+3); exit}'; }
pl() { local d="$1"; shift; (cd "$d" && env -u SPRINTX_RAIZ bash "$PL" "$@") 2>&1; }
bl() { local d="$1"; shift; SPRINTX_RAIZ="$d" bash "$BL" "$@" 2>&1; }
aux="$(mktemp -d)"; trap 'rm -rf "$aux"' EXIT

# fixture: plano com 00-PLANEJAMENTO.md na F6 (aprovado, teto 1), B-01 defeito_de_plano e
# B-02 lacuna_de_decisao abertos, tudo commitado
fixture() {
  local d="$1" f="$1/docs/sprintx/features/menu"
  git init -q -b main "$d"; git -C "$d" config user.email t@t.local; git -C "$d" config user.name teste
  git -C "$d" config commit.gpgsign false; git -C "$d" config core.autocrlf false
  printf 'docs/eventos/\n' >> "$d/.git/info/exclude"
  mkdir -p "$d/src" "$f/base" "$f/sprint-01"; printf 'export const x = 1\n' > "$d/src/app.ts"
  git -C "$d" add -A; git -C "$d" commit -q -m init; git -C "$d" switch -q -c feature/menu
  printf 'indice\n' > "$f/base/00-INDICE.md"; printf 'decisoes\n' > "$f/00-DECISOES.md"; printf 'orquestrador\n' > "$f/ORQUESTRADOR.md"
  printf -- '---\nkind: tasks\ntrabalho_id: menu\nsprint_id: sprint-01\ntasks:\n  - id: T-01.01\n    status: bloqueada\n    arquivos:\n      cria: [src/menu.ts]\n      altera: []\n---\n\n# Tasks\n' > "$f/sprint-01/tasks.md"
  printf '# Auditoria\n\n| severidade | arquivo | problema | correção sugerida |\n|---|---|---|---|\n\nVEREDITO: SIM — o plano está pronto para execução autônoma.\n' > "$f/00-AUDITORIA.md"
  git -C "$d" add -A; git -C "$d" commit -q -m plano
  pl "$d" criar menu null flavio 1 >/dev/null && pl "$d" checkpoint menu >/dev/null || return 1
  bl "$d" registrar menu T-01.01 defeito_de_plano 'T-01.01 precisa de src/app.ts' 'acrescentar o arquivo' >/dev/null || return 1
  bl "$d" registrar menu null lacuna_de_decisao 'falta decidir o rotulo' 'o dono decide' >/dev/null || return 1
  git -C "$d" add -A; git -C "$d" commit -q -m bloqueios
  [ "$(fm "$f/00-PLANEJAMENTO.md" estado)" = aprovado ]
}

A="$aux/a"; fixture "$A"; afirma 'fixture: aprovado, B-01 defeito_de_plano e B-02 lacuna_de_decisao abertos' $?

# controle: com as duas classes abertas, a recusa classes_mistas e gravada como terminal
out="$(pl "$A" replanejar-execucao menu)"; rc=$?
[ "$rc" -eq 5 ] && [ "$(kv "$out" motivo)" = classes_mistas ] \
  && [ "$(fm "$A/docs/sprintx/features/menu/00-PLANEJAMENTO.md" estado)" = replanejamento_execucao_recusado ]
afirma 'controle: classes_mistas gravada como terminal' $? "rc=$rc $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-200)"

# o B-02 e resolvido entre a leitura e a gravacao: nada e gravado, o estado continua aprovado
B="$aux/b"; fixture "$B" >/dev/null
( cd "$B" && env -u SPRINTX_RAIZ SPRINTX_TESTE_PAUSA_ANTES_DA_RECUSA=6 bash "$PL" replanejar-execucao menu > "$aux/b.out" 2>&1; echo $? > "$aux/b.rc" ) &
# espera o processo chegar a pausa (depois da primeira leitura), nunca um atraso fixo (CodeAnt no sprintx#85)
for _ in $(seq 1 60); do [ -e "$B/.git/sprintx-teste-pausa" ] && break; sleep 0.5; done
bl "$B" resolver menu B-02 > "$aux/b-res.out"; rres=$?
wait
rc="$(cat "$aux/b.rc")"; out="$(cat "$aux/b.out")"
[ "$rres" -eq 0 ] && [ "$rc" -eq 5 ] && [ "$(kv "$out" motivo)" = bloqueios_mudaram ] \
  && [ "$(fm "$B/docs/sprintx/features/menu/00-PLANEJAMENTO.md" estado)" = aprovado ] \
  && ! grep -q '^recusa_replanejamento_f6:' "$B/docs/sprintx/features/menu/00-PLANEJAMENTO.md"
afirma 'bloqueio resolvido entre a leitura e a gravacao: nenhuma recusa terminal, estado aprovado' $? "rres=$rres rc=$rc $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-240)"

# a costura so aceita segundos inteiros: outro valor e ignorado, nunca executado
C="$aux/c"; fixture "$C" >/dev/null
out="$( (cd "$C" && env -u SPRINTX_RAIZ SPRINTX_TESTE_PAUSA_ANTES_DA_RECUSA='1; touch PWNED' bash "$PL" replanejar-execucao menu) 2>&1)"; rc=$?
[ "$rc" -eq 5 ] && [ "$(kv "$out" motivo)" = classes_mistas ] && [ ! -e "$C/PWNED" ]
afirma 'a costura de teste ignora valor que nao e numero' $?

# a costura tem teto: valor acima de 30 s e ignorado (nenhuma recusa dorme horas)
D="$aux/d"; fixture "$D" >/dev/null
ini=$(date +%s); out="$( (cd "$D" && env -u SPRINTX_RAIZ SPRINTX_TESTE_PAUSA_ANTES_DA_RECUSA=99999 bash "$PL" replanejar-execucao menu) 2>&1)"; rc=$?; dur=$(( $(date +%s) - ini ))
[ "$rc" -eq 5 ] && [ "$(kv "$out" motivo)" = classes_mistas ] && [ "$dur" -lt 20 ] && [ ! -e "$D/.git/sprintx-teste-pausa" ]
afirma 'a costura de teste ignora valor acima de 30 s' $? "rc=$rc dur=${dur}s"

# o resolver respeita a trava da F6: com ela ocupada, nao grava e diz que esta ocupada
E="$aux/e"; fixture "$E" >/dev/null
mkdir -p "$(git -C "$E" rev-parse --absolute-git-dir)/sprintx/travas/autorizacao-f6-menu.lock"
ck="$(cksum < "$E/docs/sprintx/features/menu/00-BLOQUEIOS.md")"
out="$(bl "$E" resolver menu B-02)"; rc=$?
[ "$rc" -eq 5 ] && grep -q 'trava da F6' <<<"$out" && [ "$(cksum < "$E/docs/sprintx/features/menu/00-BLOQUEIOS.md")" = "$ck" ]
afirma 'bloqueios.sh resolver com a trava da F6 ocupada: nao grava' $? "rc=$rc"

echo
echo "  $ok ok, $falhou falhas"
[ "$falhou" -eq 0 ] && [ "$ok" -gt 0 ]
