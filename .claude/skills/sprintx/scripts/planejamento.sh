#!/usr/bin/env bash
# planejamento.sh — estado duravel do planejamento da sprintx.
#
# Dono de docs/sprintx/features/<slug>/00-PLANEJAMENTO.md (kind: planejamento):
# a maquina F3 <-> F5, o orcamento de reprovacoes da F5 declarado pelo caller,
# o estado terminal `orcamento_esgotado`, o retorno da F6 ao planejamento
# (`replanejar_execucao`, com orcamento proprio e os estados terminais
# `replanejamento_execucao_esgotado` e `replanejamento_execucao_recusado`, este
# com o motivo operacional em `recusa_replanejamento_f6`), o congelamento das tasks concluidas
# durante esse retorno e os checkpoints Git LOCAIS de metodo que tornam o
# planejamento duravel.
#
# Tudo aqui e deterministico: nenhuma decisao depende do modelo lembrar de
# alguma coisa. Sem jq, sem python, sem rede. Bash 3.2 (macOS) compativel.
#
# Uso (a partir de qualquer diretorio do repositorio; SPRINTX_RAIZ sobrescreve a raiz):
#
#   planejamento.sh criar <slug> [max_reprovacoes_f5|null] [declarado_por|null] [max_replanejamentos_f6|null]
#   planejamento.sh avanca <slug> f2|f3|f4|f5
#   planejamento.sh replanejar-execucao <slug>
#   planejamento.sh checkpoint <slug>
#   planejamento.sh fase <slug>
#   planejamento.sh pode-resolver <slug> <B-NN>
#   planejamento.sh valida-auditoria <slug>
#   planejamento.sh obrigacoes-f6 <slug>
#   planejamento.sh severidade ausente|criterio|teste
#   planejamento.sh revisor            (linhas do revisor-testes no stdin)
#
# Saida: linhas chave=valor no stdout; motivo de erro no stderr.
#
# Codigos de saida:
#   0  ok — inclusive no-op idempotente, retomada da mesma rodada e checkpoint
#      ignorado com aviso (sem Git, branch que nao e feature/<slug>, pasta ignorada)
#   2  checkpoint recusado: ha path staged fora de docs/sprintx/features/<slug>/;
#      ou fronteira insegura: ao entrar em replanejar_execucao, sujeira na arvore que
#      nao se atribui inequivocamente a task bloqueada (DS-156);
#      ou trabalho parcial divergente/perdido: durante a rodada, a arvore ja nao e a
#      que o replanejamento preservou em parciais_replanejamento_f6
#   3  persistencia_falhou: o commit do checkpoint foi rejeitado (hook do projeto);
#      ou persistencia pendente: em feature/<slug>, o estado do disco ainda nao
#      esta no HEAD — `fase` responde CHECKPOINT e `avanca` recusa ate `checkpoint`;
#      ou fechamento pendente: rodada de replanejamento aprovada e ainda nao fechada
#   4  contrato invalido (orcamento, arquivo, auditoria, linha do revisor, task
#      concluida alterada durante o replanejamento da execucao, plano replanejado
#      que tira de sua task um path do trabalho parcial preservado)
#   5  transicao invalida para o estado atual (inclui estado terminal, replanejamento
#      recusado pela classe dos bloqueios ou pela falta de orcamento da F6, e
#      resolucao de defeito_de_plano fora de uma rodada aprovada). A recusa
#      OPERACIONAL (classes_mistas, orcamento_f6_legado, orcamento_f6_nao_declarado,
#      planejamento_legado) e gravada como o terminal replanejamento_execucao_recusado
#      e persistida pelo checkpoint; repeti-la devolve o mesmo terminal, sem gravar.
#   64 uso incorreto

set -uo pipefail

SK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SK/assets/TEMPLATE-PLANEJAMENTO.md"

E_RECUSADO=2; E_PERSISTENCIA=3; E_CONTRATO=4; E_TRANSICAO=5; E_USO=64

falha() { local c="$1"; shift; printf 'planejamento: %s\n' "$*" >&2; exit "$c"; }

. "$SK/scripts/caminho-git.sh" || falha "$E_USO" "scripts/caminho-git.sh ausente"

# ------------------------------------------------------------------ contexto

resolve_raiz() {
  if [ -n "${SPRINTX_RAIZ:-}" ]; then printf '%s' "$SPRINTX_RAIZ"; return; fi
  local t; t="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$t" ] && { caminho_git "$t"; return; }
  printf '%s' "$PWD"
}

valida_slug() {
  case "$1" in
    ""|-*|*-|*--*|*[!a-z0-9-]*) falha "$E_USO" "slug invalido: '$1' (a-z, 0-9 e hifen)" ;;
  esac
}

# Validacoes por padrao de shell, sem processo novo: no Windows cada fork custa caro.
inteiro() { case "$1" in 0) return 0 ;; ""|0*|*[!0-9]*) return 1 ;; esac; return 0; }
positivo() { case "$1" in ""|0*|*[!0-9]*) return 1 ;; esac; return 0; }
id_bloqueio() { case "$1" in B-[0-9][0-9]*) case "${1#B-}" in *[!0-9]*) return 1 ;; esac; return 0 ;; esac; return 1; }
id_task() {
  case "$1" in T-[0-9][0-9]*.[0-9][0-9]*) ;; *) return 1 ;; esac
  local a="${1#T-}"; local b="${a#*.}"; a="${a%%.*}"
  case "$a$b" in *[!0-9]*) return 1 ;; esac; return 0
}
data_iso() { case "$1" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) return 0 ;; esac; return 1; }

contexto() { # contexto <slug>
  SLUG="$1"; valida_slug "$SLUG"
  RAIZ="$(resolve_raiz)"
  PREFIXO="docs/sprintx/features/$SLUG/"
  PASTA="$RAIZ/docs/sprintx/features/$SLUG"
  ARQ="$PASTA/00-PLANEJAMENTO.md"
  AUD="$PASTA/00-AUDITORIA.md"
  # Sem 00-PLANEJAMENTO.md nao ha eixo F6: le_planejamento sobrescreve.
  P_F6=legado; P_MAX6=null; P_N6=0; P_BLQ=""; P_CONG=""; P_ASS=null; P_RECUSA=""; P_PARC=""; W6_PARC=""
}

hoje() { date +%Y-%m-%d; }

# ------------------------------------------------------------------ rastro

json_esc() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//	/\\t}"; s="${s//$'\r'/\\r}"; s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

# evento <evento> <fase|-> <task|-> <resultado> <detalhe> [arquivo] — contrato
# expx-eventos v1, append-only. Falha aberta: o rastro nunca derruba o planejamento.
evento() {
  local fase="null" task="null" dir="$RAIZ/docs/eventos" arq="${6:-${PREFIXO}00-PLANEJAMENTO.md}"
  [ "$2" != "-" ] && fase="\"$2\""
  [ "$3" != "-" ] && task="\"$3\""
  {
    mkdir -p "$dir" || return 0
    printf '{"ts":"%s","expx_eventos":1,"trabalho_id":"%s","ferramenta":"sprintx","origem":"skill","evento":"%s","fase":%s,"task":%s,"agente":"principal","resultado":"%s","detalhe":"%s","arquivos":["%s"]}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SLUG" "$1" "$fase" "$task" "$4" "$(json_esc "$5")" "$arq" \
      >> "$dir/$SLUG.jsonl"
  } 2>/dev/null || true
  return 0
}

# rastro <fase|-> <resultado> <detalhe> — o evento do checkpoint.
rastro() { evento checkpoint_planejamento "$1" - "$2" "$3"; }

# ------------------------------------------------------------------ orcamento

valida_orcamento() { # valida_orcamento <max> <declarado_por>
  local max="$1" por="$2"
  case "$max" in
    null) ;;
    *) positivo "$max" || falha "$E_CONTRATO" "max_reprovacoes_f5 invalido: '$max' (inteiro >= 1 ou null)" ;;
  esac
  case "$por" in
    null) ;;
    [a-z]*) case "$por" in *[!a-z0-9_-]*) falha "$E_CONTRATO" "orcamento_declarado_por invalido: '$por' (identificador minusculo ou null)" ;; esac ;;
    *) falha "$E_CONTRATO" "orcamento_declarado_por invalido: '$por' (identificador minusculo ou null)" ;;
  esac
  if [ "$max" = null ] && [ "${3:-null}" = null ] && [ "$por" != null ]; then
    falha "$E_CONTRATO" "orcamento_declarado_por sem max_reprovacoes_f5: quem declara orcamento declara o teto"
  fi
  if [ "$max" != null ] && [ "$por" = null ]; then
    falha "$E_CONTRATO" "max_reprovacoes_f5 sem orcamento_declarado_por: o teto precisa de dono"
  fi
}

# valida_orcamento_f6 <max6> <declarado_por> — mesmo dono do orcamento da F5.
# `null` e "nao declarado": sem orcamento, o replanejamento da execucao nao abre.
valida_orcamento_f6() {
  case "$1" in
    null) ;;
    *) positivo "$1" || falha "$E_CONTRATO" "max_replanejamentos_f6 invalido: '$1' (inteiro >= 1 ou null)"
       [ "$2" != null ] || falha "$E_CONTRATO" "max_replanejamentos_f6 sem orcamento_declarado_por: o teto precisa de dono" ;;
  esac
}

# ------------------------------------------------------------------ leitura

# fm_carrega <arquivo> — uma passada so pelo primeiro bloco YAML: FM_<chave> recebe o
# escalar de topo (primeira ocorrencia, sem espacos nas pontas) e FM_CHAVES lista as
# chaves presentes. fm_em <var> <chave> copia o valor; fm_presente <chave> diz se existe.
fm_carrega() {
  local linha k v
  for k in $FM_CHAVES; do unset "FM_$k"; done
  FM_CHAVES=" "
  while IFS= read -r linha; do
    k="${linha%%"$TAB"*}"; v="${linha#*"$TAB"}"
    case "$k" in ""|*[!a-z0-9_]*) continue ;; esac
    case "$FM_CHAVES" in *" $k "*) continue ;; esac
    FM_CHAVES="$FM_CHAVES$k "
    eval "FM_$k=\$v"
  done <<EOF
$(tr -d '\r' < "$1" | awk '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    /^[a-z_][a-z0-9_]*:/ { k = $0; sub(/:.*/, "", k); v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print k "\t" v }')
EOF
}
TAB="$(printf '\t')"; FM_CHAVES=""
fm_em() { eval "$1=\${FM_$2-}"; }   # fm_em <variavel> <chave> — sem subshell
fm_presente() { case "$FM_CHAVES" in *" $1 "*) return 0 ;; esac; return 1; }

hist_tsv() { # rodada TAB veredito TAB altas TAB medias TAB baixas TAB auditado_em
  tr -d '\r' < "$1" | awk '
    function sai() { if (r != "") print r "\t" v "\t" a "\t" m "\t" b "\t" d; r = "" }
    NR == 1 { next }
    $0 == "---" { exit }
    /^historico:/ { h = 1; next }
    h && /^[^ ]/ { h = 0 }
    !h { next }
    /^  - rodada:/     { sai(); r = $3; v = a = m = b = d = ""; next }
    /^    veredito:/   { v = $2; next }
    /^    altas:/      { a = $2; next }
    /^    medias:/     { m = $2; next }
    /^    baixas:/     { b = $2; next }
    /^    auditado_em:/ { d = $2; next }
    { print "LIXO\t" $0 }
    END { sai() }'
}

# lista_em <variavel> <valor> — "[a, b]" -> "a b"; "[]" -> "". Outra forma: LIXO.
lista_em() {
  local nome="$1" v r
  case "$2" in
    "[]") r="" ;;
    "["*"]") v="${2#[}"; v="${v%]}"; v="${v//,/ }"
             case "$v" in *[!A-Za-z0-9.\ -]*) r=LIXO ;; *) set -- $v; r="$*" ;; esac ;;
    *) r=LIXO ;;
  esac
  eval "$nome=\$r"
}

em_lista() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# As chaves do eixo F6, na ordem em que sao gravadas. Presentes todas, ou nenhuma
# (planejamento anterior a este contrato: legado — nunca ganha orcamento retroativo).
CHAVES_F6="max_replanejamentos_f6 replanejamentos_f6 bloqueios_replanejamento_f6 tasks_congeladas assinatura_congeladas"

# le_f6 — P_F6 (presente|legado), P_MAX6, P_N6, P_BLQ, P_CONG, P_ASS, P_PARC.
le_f6() {
  local k tem=0 falta=0 x ant=0 n
  for k in $CHAVES_F6; do if fm_presente "$k"; then tem=$((tem + 1)); else falta=$((falta + 1)); fi; done
  if [ "$tem" -eq 0 ]; then
    P_F6=legado; P_MAX6=null; P_N6=0; P_BLQ=""; P_CONG=""; P_ASS=null; P_PARC=""
    fm_presente parciais_replanejamento_f6 && falha "$E_CONTRATO" "parciais_replanejamento_f6 sem o eixo F6"
    return 0
  fi
  [ "$falta" -eq 0 ] || falha "$E_CONTRATO" "eixo F6 incompleto: as chaves $CHAVES_F6 existem todas ou nenhuma"
  P_F6=presente
  fm_em P_MAX6 max_replanejamentos_f6; fm_em P_N6 replanejamentos_f6; fm_em P_ASS assinatura_congeladas
  local bruto
  fm_em bruto bloqueios_replanejamento_f6; lista_em P_BLQ "$bruto"
  fm_em bruto tasks_congeladas; lista_em P_CONG "$bruto"
  case "$P_MAX6" in
    null) ;;
    *) positivo "$P_MAX6" || falha "$E_CONTRATO" "max_replanejamentos_f6 invalido: '$P_MAX6'" ;;
  esac
  inteiro "$P_N6" || falha "$E_CONTRATO" "replanejamentos_f6 invalido: '$P_N6'"
  if [ "$P_MAX6" = null ]; then
    [ "$P_N6" -eq 0 ] || falha "$E_CONTRATO" "replanejamentos_f6=$P_N6 sem orcamento da F6 declarado"
  else
    [ "$P_N6" -le "$P_MAX6" ] || falha "$E_CONTRATO" "replanejamentos_f6=$P_N6 acima do teto $P_MAX6"
  fi
  [ "$P_BLQ" != LIXO ] || falha "$E_CONTRATO" "bloqueios_replanejamento_f6 fora da forma [B-NN, ...]"
  [ "$P_CONG" != LIXO ] || falha "$E_CONTRATO" "tasks_congeladas fora da forma [T-NN.MM, ...]"
  for x in $P_BLQ; do
    id_bloqueio "$x" || falha "$E_CONTRATO" "bloqueios_replanejamento_f6 com id invalido: '$x'"
    n="${x#B-}"; while [ "${n#0}" != "$n" ] && [ -n "${n#0}" ]; do n="${n#0}"; done; n=$((n + 0))
    [ "$n" -gt "$ant" ] || falha "$E_CONTRATO" "bloqueios_replanejamento_f6 fora da ordem crescente de id: $P_BLQ"
    ant="$n"
  done
  for x in $P_CONG; do
    id_task "$x" || falha "$E_CONTRATO" "tasks_congeladas com id invalido: '$x'"
  done
  if [ -n "$P_BLQ" ]; then
    [ "$P_N6" -ge 1 ] || falha "$E_CONTRATO" "rodada de replanejamento da execucao ativa com replanejamentos_f6=0"
    case "$P_ASS" in [0-9]*-[0-9]*) case "${P_ASS%%-*}${P_ASS#*-}" in *[!0-9]*) P_ASS=LIXO ;; esac ;; *) P_ASS=LIXO ;; esac
    [ "$P_ASS" != LIXO ] || falha "$E_CONTRATO" "rodada ativa sem assinatura_congeladas valida"
  else
    [ -z "$P_CONG" ] && [ "$P_ASS" = null ] || falha "$E_CONTRATO" "tasks_congeladas/assinatura_congeladas preenchidas sem rodada ativa"
  fi
  le_parciais
}

# le_parciais — P_PARC: o trabalho parcial preservado pela rodada ativa (DS-156), uma linha
# `path TAB task TAB estado TAB hash` por path, em ordem de byte do path. Chave aditiva do
# eixo F6: ausente (arquivo gravado antes dela) vale `[]`.
le_parciais() {
  local bruto p t e h
  P_PARC=""
  fm_presente parciais_replanejamento_f6 || return 0
  fm_em bruto parciais_replanejamento_f6
  case "$bruto" in
    "[]") return 0 ;;
    "") P_PARC="$(parciais_tsv "$ARQ")" ;;
    *) falha "$E_CONTRATO" "parciais_replanejamento_f6 fora da forma: [] ou lista de {path, task, estado, hash}" ;;
  esac
  [ -n "$P_PARC" ] || falha "$E_CONTRATO" "parciais_replanejamento_f6 em bloco sem item: use []"
  while IFS="$TAB" read -r p t e h; do
    [ "$p" != LIXO ] || falha "$E_CONTRATO" "parciais_replanejamento_f6 invalido: $t"
    id_task "$t" || falha "$E_CONTRATO" "parciais_replanejamento_f6: task invalida '$t' em $p"
    case "$e:$h" in
      removido:null) ;;
      novo:*|modificado:*) hash_git "$h" || falha "$E_CONTRATO" "parciais_replanejamento_f6: hash invalido '$h' em $p" ;;
      *) falha "$E_CONTRATO" "parciais_replanejamento_f6: estado/hash invalido '$e/$h' em $p" ;;
    esac
  done <<EOF
$P_PARC
EOF
  [ -n "$P_BLQ" ] || falha "$E_CONTRATO" "parciais_replanejamento_f6 preenchido sem rodada ativa"
}

# hash_git <h> — id de objeto do Git: 40 (sha1) ou 64 (sha256) hexadecimais minusculos.
hash_git() { case "$1" in *[!0-9a-f]*|"") return 1 ;; esac; [ "${#1}" -eq 40 ] || [ "${#1}" -eq 64 ]; }

# parciais_tsv <arquivo> — os itens do bloco parciais_replanejamento_f6, na forma gravada
# por `escreve`. Linha fora da forma, item incompleto ou path fora da ordem estrita: LIXO.
parciais_tsv() {
  tr -d '\r' < "$1" | LC_ALL=C awk '
    function sai() {
      if (n) {
        if (p == "" || t == "" || e == "" || h == "") print "LIXO\titem incompleto: " p
        else { if (ant != "" && !(p > ant)) print "LIXO\tfora da ordem de path: " p; print p "\t" t "\t" e "\t" h; ant = p }
      }
      n = 0; p = t = e = h = ""
    }
    NR == 1 { next }
    fim { next }
    $0 == "---" { fim = 1; next }
    /^parciais_replanejamento_f6:[ \t]*$/ { b = 1; next }
    b && /^[^ ]/ { sai(); b = 0 }
    !b { next }
    /^  - path: "[^"\t]+"$/ { sai(); n = 1; p = substr($0, 12, length($0) - 12); next }
    n && /^    task: [^ ]+$/ { t = substr($0, 11); next }
    n && /^    estado: [^ ]+$/ { e = substr($0, 13); next }
    n && /^    hash: [^ ]+$/ { h = substr($0, 11); next }
    { print "LIXO\t" $0 }
    END { sai() }'
}

# ------------------------------------------------------------------ tasks do plano

# arquivos_tasks — os sprint-NN/tasks.md da feature, em ordem, relativos a PASTA.
arquivos_tasks() {
  local f
  for f in "$PASTA"/sprint-*/tasks.md; do [ -f "$f" ] && printf '%s\n' "${f#"$PASTA/"}"; done | LC_ALL=C sort
}

# tasks_tsv <arquivo> — id TAB status de cada item da chave `tasks:` do frontmatter.
tasks_tsv() {
  tr -d '\r' < "$1" | awk '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    /^tasks:/ { t = 1; next }
    t && /^[^ ]/ { t = 0 }
    !t { next }
    /^  - id:/ { if (id != "") print id "\t" st; id = $3; st = ""; next }
    /^    status:/ { st = $2; next }
    END { if (id != "") print id "\t" st }'
}

# status_da_task <id> — arquivo TAB status, ou nada se a task nao existe no plano.
status_da_task() {
  local rel id st
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    while IFS="$(printf '\t')" read -r id st; do
      [ "$id" = "$1" ] && { printf '%s\t%s\n' "$rel" "$st"; return 0; }
    done <<EOF
$(tasks_tsv "$PASTA/$rel")
EOF
  done <<EOF
$(arquivos_tasks)
EOF
  return 0
}

# congeladas — o texto que congela as tasks concluidas: para cada sprint-NN/tasks.md,
# o item inteiro do frontmatter de cada task `concluida` e, na prosa, o bloco ```yaml
# com o mesmo id mais o que a F6 escreveu depois dele (data, suite, esforco real) ate
# o proximo `---`, bloco ou titulo — tudo precedido do caminho. Mover, renumerar,
# reabrir, apagar ou editar uma delas muda este texto; concluir outra task tambem.
congeladas() {
  local rel
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    tr -d '\r' < "$PASTA/$rel" | awk -v rel="$rel" '
      function fecha() { if (id != "" && st == "concluida") { ok[id] = 1; print "== " rel " " id; printf "%s", buf } id = ""; buf = ""; st = "" }
      function solta() { if (cauda && (pid in ok)) { print "-- " rel " " pid; printf "%s", pb } cauda = 0; pb = "" }
      NR == 1 { if ($0 == "---") fm = 1; next }
      fm && $0 == "---" { fecha(); fm = 0; corpo = 1; next }
      fm && /^tasks:/ { t = 1; next }
      fm && t && /^[^ ]/ { fecha(); t = 0 }
      fm && t && /^  - id:/ { fecha(); id = $3 }
      fm && t && id != "" { buf = buf $0 "\n"; if ($0 ~ /^    status:/) st = $2; next }
      !corpo { next }
      /^```yaml[ \t]*$/ { solta(); bl = 1; pb = $0 "\n"; pid = ""; next }
      bl && /^```[ \t]*$/ { pb = pb $0 "\n"; bl = 0; cauda = 1; next }
      bl { pb = pb $0 "\n"; if ($0 ~ /^id:[ \t]/) { pid = $2 }; next }
      cauda && ($0 == "---" || /^#/) { solta(); next }
      cauda { pb = pb $0 "\n" }
      END { solta() }'
  done <<EOF
$(arquivos_tasks)
EOF
}

# calcula_congeladas — C_IDS (ids das concluidas, em ordem) e C_ASS (cksum do texto).
calcula_congeladas() {
  local txt l ck
  txt="$(congeladas)"
  C_IDS=""
  while IFS= read -r l; do
    case "$l" in "== "*) l="${l#== }"; C_IDS="$C_IDS${C_IDS:+ }${l#* }" ;; esac
  done <<EOF
$txt
EOF
  ck="$(printf '%s\n' "$txt" | cksum)"; set -- $ck; C_ASS="$1-$2"
}

# confere_congeladas — durante a rodada, as concluidas continuam exatamente como estavam.
confere_congeladas() {
  local ids ass
  calcula_congeladas; ids="$C_IDS"; ass="$C_ASS"
  if [ "$ids" != "$P_CONG" ] || [ "$ass" != "$P_ASS" ]; then
    evento replanejamento_execucao_recusado "${1:-f3}" - bloqueado "task concluida alterada durante o replanejamento da execucao: congeladas [$P_CONG], agora [$ids]"
    falha "$E_CONTRATO" "task concluida alterada durante o replanejamento da execucao (congeladas: [$P_CONG]; agora: [$ids]; assinatura $P_ASS -> $ass). Tasks concluidas sao congeladas: nao apague, renumere, reabra nem reescreva. Nada foi registrado. PARE."
  fi
}

# reabre_task <id> — bloqueada -> pendente, no frontmatter e no bloco ```yaml da prosa.
# So toca o item com esse id e so a linha `status: bloqueada`.
reabre_task() {
  local linha rel st arq tmp
  linha="$(status_da_task "$1")"
  [ -n "$linha" ] || { evento task_reaberta f5 "$1" aviso "task $1 nao existe mais no plano replanejado: nada a reabrir"; return 0; }
  rel="$(printf '%s' "$linha" | cut -f1)"; st="$(printf '%s' "$linha" | cut -f2)"
  case "$st" in
    pendente) return 0 ;;
    bloqueada) ;;
    *) falha "$E_CONTRATO" "task $1 em $st: so uma task bloqueada volta a pendente" ;;
  esac
  arq="$PASTA/$rel"; tmp="$arq.tmp.$$"
  tr -d '\r' < "$arq" | awk -v alvo="$1" -v hoje="$(hoje)" '
    NR == 1 { if ($0 == "---") fm = 1; print; next }
    fm && $0 == "---" { fm = 0; corpo = 1; print; next }
    fm && /^atualizado_em:/ { print "atualizado_em: " hoje; next }
    fm && /^tasks:/ { t = 1; print; next }
    fm && t && /^[^ ]/ { t = 0 }
    fm && t && /^  - id:/ { id = $3 }
    fm && t && id == alvo && $0 == "    status: bloqueada" { print "    status: pendente"; next }
    corpo && /^```yaml[ \t]*$/ { bl = 1; pid = ""; print; next }
    corpo && bl && /^```[ \t]*$/ { bl = 0; print; next }
    corpo && bl && /^id:[ \t]/ { pid = $2 }
    corpo && bl && pid == alvo && $0 ~ /^status:[ \t]*bloqueada[ \t]*$/ { print "status: pendente"; next }
    { print }' > "$tmp" || { rm -f "$tmp"; falha "$E_CONTRATO" "falha ao reabrir $1 em $rel"; }
  mv -f "$tmp" "$arq"
  [ "$(status_da_task "$1" | cut -f2)" = pendente ] || falha "$E_CONTRATO" "reabertura de $1 nao gravou status: pendente em $rel"
  evento task_reaberta f5 "$1" ok "$1 bloqueada -> pendente: o replanejamento da execucao foi aprovado" "$PREFIXO$rel"
}

# ------------------------------------------------------------------ bloqueios

BLOQ_SH() { SPRINTX_RAIZ="$RAIZ" bash "$SK/scripts/bloqueios.sh" "$@"; }

# le_bloqueios — B_TSV: a saida de `bloqueios.sh listar` (id TAB task TAB classe|legado
# TAB aberto|resolvido). A classe e a CHAVE gravada; a descricao nunca e lida aqui.
le_bloqueios() {
  B_TSV=""
  [ -f "$PASTA/00-BLOQUEIOS.md" ] || return 0
  B_TSV="$(BLOQ_SH listar "$SLUG")" || falha "$E_CONTRATO" "00-BLOQUEIOS.md invalido (bloqueios.sh listar recusou)"
  B_TSV="$(printf '%s' "$B_TSV" | tr -d '\r')"
}

# campo_bloqueio <B-NN> <2|3|4> — task, classe ou aberto|resolvido, de B_TSV.
campo_bloqueio() {
  local i t c e
  while IFS="$TAB" read -r i t c e; do
    [ "$i" = "$1" ] || continue
    case "$2" in 2) printf '%s' "$t" ;; 3) printf '%s' "$c" ;; 4) printf '%s' "$e" ;; esac
    return 0
  done <<EOF
$B_TSV
EOF
}

# abertos_tsv — id TAB task TAB classe dos B-NN abertos, em ordem crescente de id.
abertos_tsv() {
  local i t c e n
  le_bloqueios
  while IFS="$TAB" read -r i t c e; do
    [ "$e" = aberto ] || continue
    n="${i#B-}"; while [ "${n#0}" != "$n" ] && [ -n "${n#0}" ]; do n="${n#0}"; done
    printf '%s\t%s\t%s\t%s\n' "$n" "$i" "$t" "$c"
  done <<EOF
$B_TSV
EOF
}
abertos_ordenados() { abertos_tsv | sort -n -k1,1 | cut -f2-; }

estado_do_bloqueio() { le_bloqueios; campo_bloqueio "$1" 4; }
task_do_bloqueio() { le_bloqueios; campo_bloqueio "$1" 2; }

# ------------------------------------------------------------------ fronteira segura

# Os padroes de comum/segredo.sh, na mesma ordem — a bancada confere que as duas listas sao
# iguais. A skill roda sem os hooks instalados: a lista e copiada, nao importada.
SEGREDO_PADROES='-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----
AKIA[0-9A-Z]{16}
sk-[A-Za-z0-9]{20,}
sk-ant-[A-Za-z0-9_-]{20,}
gh[pousr]_[A-Za-z0-9]{30,}
xox[baprs]-[A-Za-z0-9-]{10,}
AIza[0-9A-Za-z_-]{35}
://[A-Za-z0-9_.-]+:[^@/[:space:]]{8,}@'

# sujos_produto — S_SUJOS: `XY TAB caminho` por path sujo (editado, novo ou staged) fora dos
# artefatos de metodo, com o caminho relativo a raiz da sprintx. Caminho que o porcelain
# precisa citar, ou fora da raiz, sai com XY `!?`: nao se identifica mecanicamente. O rastro
# (docs/eventos/) e telemetria de metodo, local por contrato (08-rastro.md), nunca produto: o
# proprio script grava nele, e num clone novo — sem o info/exclude da F1 — ele apareceria
# como sujeira a cada chamada.
sujos_produto() {
  local pre l xy p q
  S_SUJOS=""
  pre="$(git -C "$RAIZ" rev-parse --show-prefix 2>/dev/null)"
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    xy="${l%"${l#??}"}"; p="${l#???}"
    case "$p" in *" -> "*) p="${p##* -> }" ;; esac
    q="${p#\"}"; q="${q%\"}"
    case "$q" in
      "${pre}docs/sprintx/features/$SLUG/"*|"${pre}docs/sprintx/estimativas/HISTORICO.md"|"${pre}docs/entregas/$SLUG/"*) continue ;;
      "${pre}docs/eventos/"*) continue ;;
    esac
    case "$p" in
      \"*) xy='!?' ;;
      "$pre"*) p="${p#"$pre"}" ;;
      *) xy='!?' ;;
    esac
    S_SUJOS="$S_SUJOS$xy$TAB$p
"
  done <<EOF
$(git -C "$RAIZ" -c core.quotepath=false -c status.relativePaths=false status --porcelain --untracked-files=all 2>/dev/null)
EOF
}

# retrato — R_TSV: `path TAB estado TAB hash` de cada path de S_SUJOS, em ordem de byte do
# path. Estado mecanico e so um de tres: `novo` (??), `modificado` ( M) e `removido` ( D);
# staged, conflito, mudanca de tipo e caminho nao identificavel saem como `outro:XY`. O hash
# e o do conteudo exato em disco (`git hash-object --no-filters`), so de arquivo regular.
retrato() {
  local xy p e h lst="" hs="" out="" arqs=()
  R_TSV=""
  [ -n "$S_SUJOS" ] || return 0
  while IFS="$TAB" read -r xy p; do
    [ -n "$p" ] || continue
    case "$xy" in "??") e=novo ;; " M") e=modificado ;; " D") e=removido ;; *) e="outro:$xy" ;; esac
    case "$e" in
      novo|modificado) if [ -f "$RAIZ/$p" ] && [ ! -L "$RAIZ/$p" ]; then arqs+=("$p"); else e="outro:$xy"; fi ;;
    esac
    lst="$lst$p$TAB$e
"
  done <<EOF
$S_SUJOS
EOF
  if [ "${#arqs[@]}" -gt 0 ]; then
    hs="$(git -C "$RAIZ" hash-object --no-filters -- "${arqs[@]}" 2>/dev/null)" || hs=""
  fi
  while IFS="$TAB" read -r p e; do
    [ -n "$p" ] || continue
    h=null
    case "$e" in
      novo|modificado) IFS= read -r h <&3 || h=""; hash_git "$h" || h=- ;;
      outro:*) h=- ;;
    esac
    out="$out$p$TAB$e$TAB$h
"
  done <<EOF 3<<EOF3
$lst
EOF
$hs
EOF3
  R_TSV="$(printf '%s' "$out" | LC_ALL=C sort -t "$TAB" -k1,1)"
}

# donos_de — para cada path de SX_PATHS (no ambiente, um por linha, na ordem): `path TAB
# task:status[ task:status...]` com toda task que o declara em `arquivos` (cria/altera, mapa
# ou lista) no FRONTMATTER de um sprint-NN/tasks.md. A prosa repete os blocos ```yaml das
# tasks e nunca declara ownership.
donos_de() {
  local rel arqs=()
  while IFS= read -r rel; do [ -n "$rel" ] && arqs+=("$PASTA/$rel"); done <<EOF
$(arquivos_tasks)
EOF
  [ "${#arqs[@]}" -gt 0 ] || arqs=(/dev/null)
  LC_ALL=C awk '
    function item(c) { gsub(/^[ \t]+|[ \t]+$/, "", c); gsub(/^["'\'']|["'\'']$/, "", c); if (c != "") it[++ni] = c }
    function emitir(linha,   ini, fim, corpo, q, n, i) {
      while (match(linha, /\[[^]]*\]/)) {
        ini = RSTART; fim = RLENGTH
        corpo = substr(linha, ini + 1, fim - 2)
        n = split(corpo, q, ",")
        for (i = 1; i <= n; i++) item(q[i])
        linha = substr(linha, ini + fim)
      }
    }
    function fecha(   i, f) {
      if (id != "") for (i = 1; i <= ni; i++) {
        f = it[i]
        if ((f in quer) && !((f SUBSEP id) in visto)) { visto[f SUBSEP id] = 1; dono[f] = dono[f] (dono[f] == "" ? "" : " ") id ":" st }
      }
      id = ""; st = ""; ni = 0; em = 0
    }
    BEGIN { n = split(ENVIRON["SX_PATHS"], ps, "\n"); for (i = 1; i <= n; i++) if (ps[i] != "") { quer[ps[i]] = 1; ordem[++no] = ps[i] } }
    { sub(/\r$/, "") }
    FNR == 1 { fecha(); fm = ($0 == "---"); t = 0; next }
    !fm { next }
    $0 == "---" { fecha(); fm = 0; next }
    /^tasks:/ { t = 1; next }
    t && /^[^ ]/ { fecha(); t = 0 }
    !t { next }
    /^  - id:/ { fecha(); id = $3; next }
    id == "" { next }
    /^    status:/ { st = $2 }
    /cria:|altera:/ { emitir($0); em = 0; next }
    /^[ \t]*arquivos:[ \t]*\[/ { emitir($0); em = 0; next }
    /^[ \t]*arquivos:[ \t]*$/ { em = 1; next }
    em && /^[ \t]*-[ \t]+/ { l = $0; sub(/^[ \t]*-[ \t]+/, "", l); item(l); next }
    em { em = 0 }
    END { fecha(); for (i = 1; i <= no; i++) print ordem[i] "\t" dono[ordem[i]] }' "${arqs[@]}"
}

# fronteira_segura — ao entrar em replanejar_execucao (DS-145, ampliada pela DS-156): toda
# sujeira de produto na arvore tem de se atribuir inequivocamente a task bloqueada da rodada.
# Um path e preservavel so quando: esta declarado numa task de BLOQ_TASKS e em nenhuma outra
# task do plano (irma, concluida, compartilhado); nao esta staged; o estado e novo, modificado
# ou removido de arquivo regular; nao e .env nem casa com padrao de segredo. O conjunto sai em
# F_PARC (`path TAB task TAB estado TAB hash`), que a rodada grava. Qualquer path fora disso:
# recusa e lista, e nada e gravado. Nunca limpa, stasha nem descarta.
fronteira_segura() {
  F_PARC=""
  # Sem Git nao ha produto versionado a proteger: a fronteira nao e verificavel.
  git -C "$RAIZ" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  sujos_produto
  [ -n "$S_SUJOS" ] || return 0
  retrato
  local p e h dp donos d tasks n cand="" arqs=() sujos="" veredito xy pad padroes=() seg rc paths
  paths="$(printf '%s\n' "$R_TSV" | cut -f1)"
  while IFS="$TAB" read -r p e h && IFS="$TAB" read -r dp donos <&3; do
    [ -n "$p" ] || continue
    veredito=""; tasks=""
    if [ "$p" != "$dp" ]; then veredito=nao_identificavel
    else
      case "$e" in
        outro:*)
          xy="${e#outro:}"
          case "$xy" in '!?') veredito=nao_identificavel ;; [!\ ?]?) veredito=staged ;; *) veredito=estado_nao_mecanico ;; esac ;;
        *)
          n=0
          for d in $donos; do
            n=$((n + 1)); tasks="$tasks${tasks:+,}${d%%:*}"
            case "$d" in *:concluida) veredito=task_concluida ;; esac
          done
          if [ "$n" -eq 0 ]; then veredito=nao_declarado
          elif [ -n "$veredito" ]; then veredito="task_concluida:$tasks"
          elif [ "$n" -gt 1 ]; then veredito="compartilhado:$tasks"
          elif ! em_lista "$tasks" "$BLOQ_TASKS"; then veredito="task_irma:$tasks"
          else
            case "$p" in .env|.env.*|*/.env|*/.env.*) veredito=segredo ;; esac
          fi ;;
      esac
    fi
    if [ -n "$veredito" ]; then sujos="$sujos $p($veredito)"; continue; fi
    cand="$cand$p$TAB$tasks$TAB$e$TAB$h
"
    [ "$e" = removido ] || arqs+=("$RAIZ/$p")
  done <<EOF 3<<EOF3
$R_TSV
EOF
$(SX_PATHS="$paths" donos_de)
EOF3
  # Segredo no conteudo: os mesmos padroes do hook `segredo`, numa passada. Erro de leitura
  # (codigo 2) nao se decide: nenhum candidato e preservado.
  if [ -z "$sujos" ] && [ "${#arqs[@]}" -gt 0 ]; then
    while IFS= read -r pad; do [ -n "$pad" ] && padroes+=(-e "$pad"); done <<EOF
$SEGREDO_PADROES
EOF
    seg="$(grep -lE "${padroes[@]}" -- "${arqs[@]}" 2>/dev/null)"; rc=$?
    if [ "$rc" -gt 1 ]; then
      sujos=" $(printf '%s' "$cand" | awk -F'\t' 'NF { printf "%s%s(nao_identificavel)", (NR > 1 ? " " : ""), $1 }')"
    else
      while IFS= read -r p; do [ -n "$p" ] && sujos="$sujos ${p#"$RAIZ/"}(segredo)"; done <<EOF
$seg
EOF
    fi
  fi
  if [ -n "$sujos" ]; then
    printf 'replanejamento=recusado\nmotivo=fronteira_insegura\nestado=%s\nnao_preservaveis=%s\n' "$P_ESTADO" "$(printf '%s' "${sujos# }" | tr ' ' ',')"
    evento replanejamento_execucao_recusado f6 - bloqueado "fronteira insegura: produto sujo na arvore:$sujos"
    printf 'planejamento: replanejamento da execucao recusado — fronteira insegura, ha sujeira na arvore que nao se atribui inequivocamente a task bloqueada:%s. So o trabalho parcial da propria task bloqueada (declarado so nela, nao staged, de estado mecanico) e preservado. Nada foi limpo, stashado, descartado nem gravado. PARE.\n' "$sujos" >&2
    exit "$E_RECUSADO"
  fi
  F_PARC="$(printf '%s' "$cand" | LC_ALL=C sort -t "$TAB" -k1,1)"
}

# diagnostica_parciais — D_PARC: integro | divergente | perdido, e D_DET, o que divergiu.
# `integro` e a arvore exatamente como a rodada a preservou: os mesmos paths sujos de
# produto, no mesmo estado e com o mesmo hash — nenhum a mais, nenhum a menos. `perdido` e
# nenhuma sujeira de produto onde a rodada preservou alguma: a arvore de execucao nao e esta
# (worktree perdida, clone novo). O resto e `divergente`.
diagnostica_parciais() {
  local p t e h esperado=""
  D_PARC=integro; D_DET=""
  if ! git -C "$RAIZ" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    [ -z "$P_PARC" ] || { D_PARC=perdido; D_DET=" (sem Git nesta arvore)"; }
    return 0
  fi
  sujos_produto
  if [ -z "$S_SUJOS" ]; then
    [ -z "$P_PARC" ] || { D_PARC=perdido; D_DET=" $(printf '%s\n' "$P_PARC" | cut -f1 | tr '\n' ' ')"; }
    return 0
  fi
  retrato
  while IFS="$TAB" read -r p t e h; do
    [ -n "$p" ] && esperado="$esperado$p$TAB$e$TAB$h
"
  done <<EOF
$P_PARC
EOF
  esperado="$(printf '%s' "$esperado")"
  [ "$R_TSV" = "$esperado" ] && return 0
  D_PARC=divergente
  D_DET="$(SX_A="$esperado" SX_B="$R_TSV" awk 'BEGIN {
    n = split(ENVIRON["SX_A"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") { split(a[i], c, "\t"); ea[c[1]] = c[2] "/" substr(c[3], 1, 12) }
    n = split(ENVIRON["SX_B"], b, "\n"); for (i = 1; i <= n; i++) if (b[i] != "") { split(b[i], c, "\t"); eb[c[1]] = c[2] "/" substr(c[3], 1, 12) }
    for (k in ea) if (!(k in eb)) printf " %s(preservado %s, agora limpo)", k, ea[k]; else if (ea[k] != eb[k]) printf " %s(preservado %s, agora %s)", k, ea[k], eb[k]
    for (k in eb) if (!(k in ea)) printf " %s(nao preservado, agora %s)", k, eb[k]
  }')"
}

# confere_parciais <fase> — rodada ativa, em todo portao (avanca f3/f4/f5, retomada e
# fechamento): (1) a arvore e a que a rodada preservou (diagnostica_parciais); (2) o plano de
# agora ainda da cada path preservado a mesma task, e so a ela. Arvore diferente: codigo 2,
# nada gravado — o conteudo parcial nao se reconstroi do estado versionado. Plano que tira o
# path da task: codigo 4, como tocar numa task congelada.
confere_parciais() {
  diagnostica_parciais
  case "$D_PARC" in
    perdido)
      printf 'trabalho_parcial=perdido\nmotivo=parcial_perdido\nestado=%s\nproxima=PARAR\n' "$P_ESTADO"
      evento replanejamento_execucao_recusado "$1" - bloqueado "trabalho parcial perdido: a arvore nao tem o que a rodada preservou:$D_DET"
      falha "$E_RECUSADO" "trabalho parcial perdido — a rodada preservou$D_DET e esta arvore nao tem nenhum deles (worktree perdida ou outro clone). O conteudo parcial nao e reconstruivel pelo estado versionado: nada foi reconstruido, limpo nem gravado. E perda de estado de execucao, nao decisao de produto. PARE e relate." ;;
    divergente)
      printf 'trabalho_parcial=divergente\nmotivo=parcial_divergente\nestado=%s\nproxima=PARAR\n' "$P_ESTADO"
      evento replanejamento_execucao_recusado "$1" - bloqueado "trabalho parcial divergente:$D_DET"
      falha "$E_RECUSADO" "trabalho parcial divergente — a arvore mudou desde que a rodada a preservou:$D_DET. Nada foi limpo, stashado, descartado nem gravado. PARE e relate." ;;
  esac
  [ -n "$P_PARC" ] || return 0
  local p t e h dp donos ruins="" paths=""
  while IFS="$TAB" read -r p t e h; do [ -n "$p" ] && paths="$paths$p
"; done <<EOF
$P_PARC
EOF
  while IFS="$TAB" read -r p t e h && IFS="$TAB" read -r dp donos <&3; do
    [ -n "$p" ] || continue
    case "$donos" in "$t:bloqueada"|"$t:pendente") [ "$p" = "$dp" ] && continue ;; esac
    ruins="$ruins $p($t -> ${donos:-nenhuma task})"
  done <<EOF 3<<EOF3
$P_PARC
EOF
$(SX_PATHS="$paths" donos_de)
EOF3
  [ -z "$ruins" ] && return 0
  evento replanejamento_execucao_recusado "$1" - bloqueado "plano replanejado tira da task o trabalho parcial preservado:$ruins"
  falha "$E_CONTRATO" "o plano replanejado nao da mais o trabalho parcial preservado a sua task, e so a ela:$ruins. O parcial fica com a task bloqueada que o escreveu: nao mova para irma, nao atribua a concluida, nao torne ambiguo. Nada foi registrado. PARE."
}

# le_planejamento — carrega e valida o arquivo inteiro. Arquivo que nao passa
# aqui e contrato invalido: nada e decidido em cima dele.
le_planejamento() {
  [ -f "$ARQ" ] || falha "$E_CONTRATO" "${PREFIXO}00-PLANEJAMENTO.md nao existe"
  fm_carrega "$ARQ"
  [ "${FM_expx_schema-}" = 1 ] || falha "$E_CONTRATO" "expx_schema deve ser 1"
  [ "${FM_expx_tool-}" = sprintx ] || falha "$E_CONTRATO" "expx_tool deve ser sprintx"
  [ "${FM_kind-}" = planejamento ] || falha "$E_CONTRATO" "kind deve ser planejamento"
  [ "${FM_trabalho_id-}" = "$SLUG" ] || falha "$E_CONTRATO" "trabalho_id nao e $SLUG"

  fm_em P_MAX max_reprovacoes_f5; fm_em P_POR orcamento_declarado_por
  fm_em P_ESTADO estado; fm_em P_REPROV reprovacoes; fm_em P_RECUSA recusa_replanejamento_f6
  le_f6
  valida_orcamento "$P_MAX" "$P_POR" "$P_MAX6"
  case "$P_ESTADO" in
    null|aguardando_f3|aguardando_f4|aguardando_f5|replanejar|aprovado|orcamento_esgotado) ;;
    replanejar_execucao|replanejamento_execucao_esgotado) ;;
    replanejamento_execucao_recusado) ;;
    *) falha "$E_CONTRATO" "estado fora do enum: '$P_ESTADO'" ;;
  esac
  valida_recusa
  inteiro "$P_REPROV" || falha "$E_CONTRATO" "reprovacoes invalido: '$P_REPROV'"

  P_HIST="$(hist_tsv "$ARQ")"
  P_RODADAS=0
  local nao=0 ultimo="" linha r v a m b d reabertas=0
  if [ -n "$P_HIST" ]; then
    while IFS="$(printf '\t')" read -r r v a m b d; do
      [ "$r" != LIXO ] || falha "$E_CONTRATO" "linha inesperada em historico: $v"
      P_RODADAS=$((P_RODADAS + 1))
      [ "$r" = "$P_RODADAS" ] || falha "$E_CONTRATO" "historico fora de sequencia: rodada $r na posicao $P_RODADAS"
      case "$v" in sim|nao) ;; *) falha "$E_CONTRATO" "veredito invalido na rodada $r: '$v'" ;; esac
      # Rodada depois de um SIM so existe quando a F6 devolveu o plano ao planejamento:
      # no maximo uma sequencia assim por replanejamento da execucao ja aceito.
      if [ "$ultimo" = sim ]; then
        reabertas=$((reabertas + 1))
        [ "$reabertas" -le "$P_N6" ] || falha "$E_CONTRATO" "rodada $r depois de um veredito sim sem replanejamento da execucao que a abrisse"
      fi
      for linha in "$a" "$m" "$b"; do inteiro "$linha" || falha "$E_CONTRATO" "contagem invalida na rodada $r"; done
      data_iso "$d" || falha "$E_CONTRATO" "auditado_em invalido na rodada $r"
      if [ "$v" = nao ]; then nao=$((nao + 1)); [ "$a" -gt 0 ] || falha "$E_CONTRATO" "rodada $r nao sem ALTA"
      else [ "$a" -eq 0 ] || falha "$E_CONTRATO" "rodada $r sim com ALTA"; fi
      ultimo="$v"
    done <<EOF
$P_HIST
EOF
  fi
  [ "$P_REPROV" -eq "$nao" ] || falha "$E_CONTRATO" "reprovacoes=$P_REPROV, mas o historico tem $nao veredito(s) nao"

  local esgotou=0
  [ "$P_MAX" != null ] && [ "$P_REPROV" -ge "$P_MAX" ] && esgotou=1
  # Rodada de replanejamento da execucao ativa: so nos estados do laco que ela percorre.
  if [ -n "$P_BLQ" ]; then
    case "$P_ESTADO" in
      replanejar_execucao|aguardando_f4|aguardando_f5|replanejar|orcamento_esgotado|aprovado) ;;
      *) falha "$E_CONTRATO" "bloqueios_replanejamento_f6 preenchido no estado $P_ESTADO" ;;
    esac
  fi
  case "$ultimo:$P_ESTADO" in
    sim:aprovado) ;;
    sim:replanejar_execucao|sim:aguardando_f4|sim:aguardando_f5)
      [ -n "$P_BLQ" ] || falha "$E_CONTRATO" "estado $P_ESTADO depois de um veredito sim sem rodada de replanejamento da execucao ativa" ;;
    sim:replanejamento_execucao_esgotado)
      [ -z "$P_BLQ" ] && [ "$P_MAX6" != null ] && [ "$P_N6" -ge "$P_MAX6" ] \
        || falha "$E_CONTRATO" "replanejamento_execucao_esgotado sem o orcamento da F6 consumido" ;;
    sim:replanejamento_execucao_recusado) ;;
    sim:*) falha "$E_CONTRATO" "ultima rodada sim exige estado aprovado" ;;
    *:aprovado) falha "$E_CONTRATO" "estado aprovado sem rodada sim no historico" ;;
    :null|:aguardando_f3|:aguardando_f4|:aguardando_f5) ;;
    :*) falha "$E_CONTRATO" "estado $P_ESTADO sem nenhuma rodada da F5" ;;
    nao:orcamento_esgotado) [ "$esgotou" = 1 ] || falha "$E_CONTRATO" "orcamento_esgotado com orcamento restante" ;;
    nao:replanejar|nao:aguardando_f4|nao:aguardando_f5)
      [ "$esgotou" = 0 ] || falha "$E_CONTRATO" "estado $P_ESTADO com orcamento esgotado" ;;
    nao:*) falha "$E_CONTRATO" "estado $P_ESTADO invalido depois de uma reprovacao" ;;
  esac
}

# valida_recusa — `recusa_replanejamento_f6` existe se e somente se o estado e o
# terminal replanejamento_execucao_recusado, com um motivo OPERACIONAL do enum e
# coerente com o eixo F6 gravado. Erro de contrato nunca vira recusa gravada.
valida_recusa() {
  if [ "$P_ESTADO" != replanejamento_execucao_recusado ]; then
    if fm_presente recusa_replanejamento_f6; then
      falha "$E_CONTRATO" "recusa_replanejamento_f6 so existe no estado replanejamento_execucao_recusado (estado: $P_ESTADO)"
    fi
    return 0
  fi
  case "$P_RECUSA" in
    classes_mistas) ;;
    orcamento_f6_legado)
      [ "$P_F6" = legado ] || falha "$E_CONTRATO" "recusa orcamento_f6_legado com o eixo F6 gravado" ;;
    orcamento_f6_nao_declarado|planejamento_legado)
      [ "$P_F6" = presente ] && [ "$P_MAX6" = null ] \
        || falha "$E_CONTRATO" "recusa $P_RECUSA exige max_replanejamentos_f6: null" ;;
    "") falha "$E_CONTRATO" "estado replanejamento_execucao_recusado sem recusa_replanejamento_f6" ;;
    *) falha "$E_CONTRATO" "recusa_replanejamento_f6 fora do enum: '$P_RECUSA'" ;;
  esac
}

# ------------------------------------------------------------------ escrita

# f6_herda — o eixo F6 a gravar (W6_*) comeca igual ao lido (P_*).
f6_herda() { W6="$P_F6"; W6_MAX="$P_MAX6"; W6_N="$P_N6"; W6_BLQ="$P_BLQ"; W6_CONG="$P_CONG"; W6_ASS="$P_ASS"; W6_PARC="$P_PARC"; W_RECUSA="$P_RECUSA"; }
f6_novo() { W6=presente; W6_MAX="$1"; W6_N=0; W6_BLQ=""; W6_CONG=""; W6_ASS=null; W6_PARC=""; W_RECUSA=""; }

# parciais_yaml — o bloco parciais_replanejamento_f6 de W6_PARC, na forma que parciais_tsv le.
parciais_yaml() {
  local p t e h
  if [ -z "$W6_PARC" ]; then printf 'parciais_replanejamento_f6: []\n'; return 0; fi
  printf 'parciais_replanejamento_f6:\n'
  while IFS="$TAB" read -r p t e h; do
    printf '  - path: "%s"\n    task: %s\n    estado: %s\n    hash: %s\n' "$p" "$t" "$e" "$h"
  done <<EOF
$W6_PARC
EOF
}
lista_yaml() { if [ -z "$1" ]; then printf '[]'; else printf '[%s]' "$(printf '%s' "$1" | sed 's/ /, /g')"; fi; }

# escreve <max> <por> <estado> <reprovacoes> <historico_tsv> — o arquivo inteiro,
# a partir do template, de forma atomica. O historico recebido ja inclui as
# rodadas anteriores intactas: e assim que ele continua append-only. O eixo F6
# vem de W6_* (f6_herda/f6_novo); legado continua sem as chaves — nunca ganha
# orcamento numa regravacao. W_RECUSA e o motivo do terminal recusado, e so dele.
escreve() {
  local max="$1" por="$2" estado="$3" reprov="$4" hist="$5" data tmp yaml prosa teto t6="" rodada6="" rec="" trec=""
  [ -f "$TEMPLATE" ] || falha "$E_CONTRATO" "template ausente: assets/TEMPLATE-PLANEJAMENTO.md"
  data="$(hoje)"
  if [ "$estado" = replanejamento_execucao_recusado ]; then
    [ -n "${W_RECUSA:-}" ] || falha "$E_CONTRATO" "replanejamento_execucao_recusado sem motivo a gravar"
    rec="recusa_replanejamento_f6: $W_RECUSA
"
    trec=" · replanejamento da execução recusado: \`$W_RECUSA\`"
  fi

  if [ -z "$hist" ]; then
    yaml="historico: []"
    prosa="Nenhuma rodada da F5 registrada."
  else
    yaml="historico:"
    prosa="| rodada | veredito | ALTA | MÉDIA | BAIXA | auditado em |
|---|---|---|---|---|---|"
    local r v a m b d rotulo
    while IFS="$(printf '\t')" read -r r v a m b d; do
      yaml="$yaml
  - rodada: $r
    veredito: $v
    altas: $a
    medias: $m
    baixas: $b
    auditado_em: $d"
      rotulo="SIM"; [ "$v" = nao ] && rotulo="NÃO"
      prosa="$prosa
| $r | $rotulo | $a | $m | $b | $d |"
    done <<EOF
$hist
EOF
  fi
  if [ "$max" = null ]; then teto="$reprov, sem teto"; else teto="$reprov de $max (teto declarado por \`$por\`)"; fi
  if [ "$W6" = presente ]; then
    if [ "$W6_MAX" = null ]; then t6=" · replanejamentos da execução (F6): $W6_N, sem orçamento declarado"
    else t6=" · replanejamentos da execução (F6): $W6_N de $W6_MAX (teto declarado por \`$por\`)"; fi
    [ -n "$W6_BLQ" ] && rodada6="

Rodada de replanejamento da execução ativa, aberta por: $(printf '%s' "$W6_BLQ" | sed 's/ /, /g'). Tasks concluídas congeladas: $(printf '%s' "$W6_CONG" | sed 's/ /, /g')."
    [ -n "$W6_PARC" ] && rodada6="$rodada6 Trabalho parcial preservado na árvore: $(printf '%s\n' "$W6_PARC" | awk -F'\t' '{ printf "%s`%s` (%s, %s)", (NR > 1 ? ", " : ""), $1, $2, $3 }')."
  fi

  mkdir -p "$PASTA" || falha "$E_CONTRATO" "nao foi possivel criar $PREFIXO"
  tmp="$ARQ.tmp.$$"
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: planejamento\ntrabalho_id: %s\n' "$SLUG"
    if [ "$W6" = presente ]; then
      printf 'max_reprovacoes_f5: %s\nmax_replanejamentos_f6: %s\norcamento_declarado_por: %s\nestado: %s\n%sreprovacoes: %s\n' \
        "$max" "$W6_MAX" "$por" "$estado" "$rec" "$reprov"
      printf 'replanejamentos_f6: %s\nbloqueios_replanejamento_f6: %s\ntasks_congeladas: %s\nassinatura_congeladas: %s\n' \
        "$W6_N" "$(lista_yaml "$W6_BLQ")" "$(lista_yaml "$W6_CONG")" "$W6_ASS"
      parciais_yaml
      printf 'atualizado_em: %s\n' "$data"
    else
      printf 'max_reprovacoes_f5: %s\norcamento_declarado_por: %s\nestado: %s\n%sreprovacoes: %s\natualizado_em: %s\n' \
        "$max" "$por" "$estado" "$rec" "$reprov" "$data"
    fi
    printf '%s\n---\n' "$yaml"
    # Texto com quebra de linha vai por ENVIRON, nunca por `awk -v`: o awk do
    # BSD recusa newline numa atribuicao -v.
    tr -d '\r' < "$TEMPLATE" | SX_SLUG="$SLUG" SX_BLOCO="Estado: \`$estado\` · reprovações da F5: $teto$t6$trec · atualizado em $data.$rodada6

$prosa" awk '
      NR == 1 { next }
      !corpo { if ($0 == "---") corpo = 1; next }
      /^<!-- sprintx:estado -->$/ { print; print ENVIRON["SX_BLOCO"]; pula = 1; next }
      /^<!-- \/sprintx:estado -->$/ { pula = 0; print; next }
      pula { next }
      # Consome a entrada ate o fim em vez de `exit`: sair cedo mata o `tr` do pipe com
      # SIGPIPE e, com pipefail, a gravacao inteira falha (awk/tr do busybox).
      /^<!--$/ { doc = 1 }
      doc { next }
      { gsub(/\{\{slug-da-feature\}\}/, ENVIRON["SX_SLUG"]); print }'
  } > "$tmp" || { rm -f "$tmp"; falha "$E_CONTRATO" "falha ao gravar ${PREFIXO}00-PLANEJAMENTO.md"; }
  # O comentario final do template e so documentacao da forma: fora do arquivo gerado.
  sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp" > "$tmp.2" && mv -f "$tmp.2" "$tmp"
  mv -f "$tmp" "$ARQ"
}

# ------------------------------------------------------------------ auditoria

# Clausula autoritativa citavel: criterio_aceite, uma decisao D-NN, um fato da
# base (base/<arquivo>) ou um contrato de origem ingerido (origem:<ref>).
# Fora desta gramatica nao ha clausula — e o tipo e `criterio`.
clausula_citavel() {
  printf '%s' "$1" | grep -Eq '^(criterio_aceite|D-[0-9]{2,}|base/[A-Za-z0-9._/#-]+|origem:[^[:space:]]+)$'
}

severidade_de() {
  case "$1" in
    ausente|criterio) printf 'ALTA' ;;
    teste) printf 'MÉDIA' ;;
    *) return 1 ;;
  esac
}

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

# linhas_da_tabela — severidade TAB problema, uma por achado de 00-AUDITORIA.md
linhas_da_tabela() {
  tr -d '\r' < "$AUD" | awk -F'|' '
    /^\|/ {
      s = $2; gsub(/^[ \t]+|[ \t]+$/, "", s)
      if (s == "severidade" || s ~ /^-+$/) next
      p = $4; gsub(/^[ \t]+|[ \t]+$/, "", p)
      print s "\t" p
    }'
}

# valida_auditoria — conta, confere o veredito e a severidade deterministica.
valida_auditoria() {
  [ -f "$AUD" ] || falha "$E_CONTRATO" "${PREFIXO}00-AUDITORIA.md nao existe"
  A_ALTAS=0; A_MEDIAS=0; A_BAIXAS=0
  local sev prob item tipo esperada resto task clausula impl
  local tabela; tabela="$(linhas_da_tabela)"
  if [ -n "$tabela" ]; then
    while IFS="$(printf '\t')" read -r sev prob; do
      case "$sev" in
        ALTA) A_ALTAS=$((A_ALTAS + 1)) ;;
        MÉDIA) A_MEDIAS=$((A_MEDIAS + 1)) ;;
        BAIXA) A_BAIXAS=$((A_BAIXAS + 1)) ;;
        *) falha "$E_CONTRATO" "severidade fora do enum: '$sev'" ;;
      esac
      item="$(printf '%s' "$prob" | sed -n 's/^\[item \([0-9][0-9]*\)\].*/\1/p')"
      [ -n "$item" ] && [ "$item" -ge 1 ] && [ "$item" -le 10 ] \
        || falha "$E_CONTRATO" "achado sem prefixo [item N]: $prob"
      tipo="$(printf '%s' "$prob" | sed -n 's/^\[item [0-9]*\]\[fraco:\([a-z]*\)\].*/\1/p')"
      if [ "$item" = 2 ]; then
        [ -n "$tipo" ] || falha "$E_CONTRATO" "achado do item 2 sem [fraco:<tipo>]: $prob"
        esperada="$(severidade_de "$tipo")" || falha "$E_CONTRATO" "tipo de fraco invalido: '$tipo'"
        [ "$sev" = "$esperada" ] || falha "$E_CONTRATO" "[fraco:$tipo] e $esperada, nunca $sev: $prob"
        resto="${prob#*] }"
        task="$(printf '%s' "$resto" | sed -n 's/^\(T-[0-9][0-9]*\.[0-9][0-9]*\) — cláusula: .* — passaria com: .*$/\1/p')"
        [ -n "$task" ] || falha "$E_CONTRATO" "achado fraco fora da forma 'T-NN.MM — cláusula: <c> — passaria com: <impl>': $prob"
        clausula="${resto#* — cláusula: }"; clausula="${clausula%% — passaria com: *}"
        impl="${resto#* — passaria com: }"
        [ -n "$(trim "$impl")" ] || falha "$E_CONTRATO" "achado fraco sem a implementacao errada: $prob"
        if [ "$tipo" = teste ] && ! clausula_citavel "$clausula"; then
          falha "$E_CONTRATO" "[fraco:teste] sem clausula citavel ('$clausula') e [fraco:criterio], ALTA: $prob"
        fi
      else
        case "$prob" in *"[fraco:"*) falha "$E_CONTRATO" "[fraco:...] so existe no item 2: $prob" ;; esac
      fi
    done <<EOF
$tabela
EOF
  fi
  local ver
  ver="$(tr -d '\r' < "$AUD" | grep -E '^VEREDITO: ' | tail -1)"
  case "$ver" in
    "VEREDITO: SIM"*) A_VEREDITO=sim ;;
    "VEREDITO: NÃO"*) A_VEREDITO=nao ;;
    *) falha "$E_CONTRATO" "00-AUDITORIA.md sem linha VEREDITO: SIM|NÃO" ;;
  esac
  if [ "$A_VEREDITO" = sim ] && [ "$A_ALTAS" -gt 0 ]; then falha "$E_CONTRATO" "VEREDITO: SIM com $A_ALTAS achado(s) ALTA"; fi
  if [ "$A_VEREDITO" = nao ] && [ "$A_ALTAS" -eq 0 ]; then falha "$E_CONTRATO" "VEREDITO: NÃO sem achado ALTA"; fi
}

# ultimo_veredito_legado — SIM | NAO | "" (sem arquivo ou sem linha)
ultimo_veredito() {
  [ -f "$AUD" ] || return 0
  case "$(tr -d '\r' < "$AUD" | grep -E '^VEREDITO: ' | tail -1)" in
    "VEREDITO: SIM"*) printf 'SIM' ;;
    "VEREDITO: NÃO"*) printf 'NAO' ;;
  esac
}

# ------------------------------------------------------------------ estado

# estado_efetivo — do 00-PLANEJAMENTO.md quando existe; senao, derivado do disco
# de uma feature legada. A tabela antiga, com UMA correcao: auditoria NAO nunca
# volta a apontar para a F5 sobre o mesmo plano — o estado derivado e replanejar.
estado_efetivo() {
  if [ -f "$ARQ" ]; then le_planejamento; E_ESTADO="$P_ESTADO"; E_FONTE=planejamento; return; fi
  E_FONTE=legado
  if [ ! -d "$PASTA/base" ] || [ ! -f "$PASTA/00-DECISOES.md" ]; then E_ESTADO=null
  elif [ ! -d "$PASTA/sprint-01" ]; then E_ESTADO=aguardando_f3
  elif [ ! -f "$PASTA/ORQUESTRADOR.md" ]; then E_ESTADO=aguardando_f4
  else
    case "$(ultimo_veredito)" in
      SIM) E_ESTADO=aprovado ;;
      NAO) E_ESTADO=replanejar ;;
      *)   E_ESTADO=aguardando_f5 ;;
    esac
  fi
}

# migra_legado — grava o 00-PLANEJAMENTO.md de uma feature anterior a este
# contrato. Sem teto: orcamento nunca e inventado. Quando o disco ja tem um
# veredito, ele vira a rodada 1, contada da tabela como esta. O veredito legado
# e preservado, nunca lavado: SIM com achado ALTA e contrato invalido.
migra_legado() { # migra_legado [max] [por] [max6] [estado recusa] — sem argumentos, sem teto e sem orcamento da F6
  local max="${1:-null}" por="${2:-null}" estado="$E_ESTADO" v altas medias baixas reprov=0 hist=""
  # O arquivo nasce agora: com o eixo F6, e so com o orcamento que alguem declarou.
  f6_novo "${3:-null}"
  # Recusa operacional de uma feature aprovada sem 00-PLANEJAMENTO.md: o arquivo
  # nasce ja no terminal, para que a recusa sobreviva a sessao e ao worktree.
  [ -n "${4:-}" ] && { estado="$4"; W_RECUSA="${5:-}"; }
  case "$E_ESTADO" in
    aprovado|replanejar)
      v=sim; [ "$E_ESTADO" = replanejar ] && { v=nao; reprov=1; }
      altas="$(conta_severidade ALTA)"; medias="$(conta_severidade 'MÉDIA')"; baixas="$(conta_severidade BAIXA)"
      if [ "$v" = sim ] && [ "$altas" -gt 0 ]; then
        falha "$E_CONTRATO" "auditoria legada diz VEREDITO: SIM com $altas achado(s) ALTA — o veredito nao e lavado"
      fi
      if [ "$v" = nao ] && [ "$altas" -eq 0 ]; then
        falha "$E_CONTRATO" "auditoria legada diz VEREDITO: NÃO sem achado ALTA"
      fi
      hist="$(printf '1\t%s\t%s\t%s\t%s\t%s' "$v" "$altas" "$medias" "$baixas" "$(hoje)")"
      if [ "$v" = nao ] && [ "$max" != null ] && [ "$reprov" -ge "$max" ]; then estado=orcamento_esgotado; fi ;;
  esac
  escreve "$max" "$por" "$estado" "$reprov" "$hist"
}

conta_severidade() { linhas_da_tabela | awk -F'\t' -v s="$1" '$1 == s { n++ } END { print n + 0 }'; }

fase_do_estado() {
  case "$1" in
    null) if [ -d "$PASTA/base" ]; then printf 'F2'; else printf 'F1'; fi ;;
    aguardando_f3|replanejar) printf 'F3' ;;
    aguardando_f4) printf 'F4' ;;
    aguardando_f5) printf 'F5' ;;
    aprovado) printf 'F6' ;;
    replanejar_execucao) printf 'F3' ;;
    orcamento_esgotado|replanejamento_execucao_esgotado|replanejamento_execucao_recusado) printf 'PARAR' ;;
  esac
}

# fase e rodada do ultimo marco, derivados so do arquivo: e o que vai no commit.
marco() {
  case "$P_ESTADO" in
    aguardando_f3) M_FASE=f2; M_RODADA=0 ;;
    aguardando_f4) M_FASE=f3; M_RODADA=0 ;;
    aguardando_f5) M_FASE=f4; M_RODADA=0 ;;
    replanejar|aprovado|orcamento_esgotado) M_FASE=f5; M_RODADA="$P_RODADAS" ;;
    # O retorno da F6: a rodada e o numero do replanejamento da execucao.
    replanejar_execucao|replanejamento_execucao_esgotado|replanejamento_execucao_recusado) M_FASE=f6; M_RODADA="$P_N6" ;;
    *) M_FASE=""; M_RODADA=0 ;;
  esac
}

# ------------------------------------------------------------------ persistencia

# modo_git — G_MODO: canonico | sem_git | raiz | branch | pasta_ignorada.
# `canonico` e o unico modo com HEAD duravel: Git, raiz do repositorio, branch
# exatamente feature/<slug> e pasta da feature versionavel.
modo_git() {
  G_BRANCH=""
  if ! git -C "$RAIZ" rev-parse --is-inside-work-tree >/dev/null 2>&1; then G_MODO=sem_git; return; fi
  if [ -n "$(git -C "$RAIZ" rev-parse --show-prefix 2>/dev/null)" ]; then G_MODO=raiz; return; fi
  G_BRANCH="$(git -C "$RAIZ" symbolic-ref --short -q HEAD 2>/dev/null)" || G_BRANCH=""
  if [ "$G_BRANCH" != "feature/$SLUG" ]; then G_MODO=branch; return; fi
  if git -C "$RAIZ" check-ignore -q "${PREFIXO}00-PLANEJAMENTO.md" 2>/dev/null; then G_MODO=pasta_ignorada; return; fi
  G_MODO=canonico
}

# persistencia — PERSIST: duravel | pendente | disco | sem_marco. Exige o
# planejamento ja lido (estado_efetivo).
#
# Checkpoint pendente e condicao OPERACIONAL, derivada do Git, nunca um valor de
# `estado`: no modo canonico, com um estado que exige checkpoint, o
# 00-PLANEJAMENTO.md do working tree ou do indice difere do HEAD (ou nem esta
# nele). So o script escreve esse arquivo, e so numa transicao, imediatamente
# antes do checkpoint: diferenca nele e exatamente uma transicao gravada e nao
# persistida. O resto da pasta pode divergir do HEAD por trabalho em curso da
# fase seguinte — e isso nao e pendencia; quando ha pendencia, o `checkpoint`
# persiste a pasta inteira. Sem Git, fora de feature/<slug>, raiz diferente ou
# pasta ignorada: `disco`, o estado do disco governa como sempre governou.
persistencia() {
  PERSIST=disco
  [ -f "$ARQ" ] || return 0
  marco
  [ -n "$M_FASE" ] || { PERSIST=sem_marco; return 0; }
  modo_git
  [ "$G_MODO" = canonico ] || return 0
  local rel="${PREFIXO}00-PLANEJAMENTO.md"
  if git -C "$RAIZ" cat-file -e "HEAD:$rel" 2>/dev/null \
    && git -C "$RAIZ" diff --quiet HEAD -- "$rel" 2>/dev/null \
    && git -C "$RAIZ" diff --cached --quiet HEAD -- "$rel" 2>/dev/null; then
    PERSIST=duravel
  else
    PERSIST=pendente
  fi
}

pendente_msg() {
  printf 'checkpoint pendente: o estado %s esta gravado no disco, mas nao no HEAD de feature/%s — execute `planejamento.sh checkpoint %s` antes de continuar' \
    "$P_ESTADO" "$SLUG" "$SLUG"
}

# ------------------------------------------------------------------ checkpoint

# checkpoint — commit LOCAL, na branch feature/<slug>, so da pasta da feature.
# Nunca push, nunca --no-verify, nunca limpa, descarta ou stasha nada.
checkpoint() {
  le_planejamento
  # Rodada de replanejamento da execucao aprovada e ainda nao fechada: fechar e
  # parte de persistir a aprovacao (idempotente — retomavel depois de uma queda).
  if [ "$P_ESTADO" = aprovado ] && [ -n "$P_BLQ" ]; then fecha_rodada; le_planejamento; fi
  marco
  [ -n "$M_FASE" ] || falha "$E_TRANSICAO" "estado $P_ESTADO ainda nao tem marco de checkpoint (a F2 nao terminou)"

  modo_git
  case "$G_MODO" in
    sem_git)
      printf 'checkpoint=ignorado_sem_git\n'
      rastro "$M_FASE" aviso "checkpoint ignorado: sem Git; estado $P_ESTADO so no disco"
      return 0 ;;
    raiz)
      printf 'checkpoint=ignorado_raiz\n'
      rastro "$M_FASE" aviso "checkpoint ignorado: raiz da sprintx nao e a raiz do repositorio"
      return 0 ;;
    branch)
      printf 'checkpoint=ignorado_branch\nbranch=%s\n' "${G_BRANCH:-HEAD destacado}"
      rastro "$M_FASE" aviso "checkpoint ignorado: branch '${G_BRANCH:-HEAD destacado}' nao e feature/$SLUG; estado $P_ESTADO so no disco"
      return 0 ;;
    pasta_ignorada)
      printf 'checkpoint=ignorado_pasta_ignorada\n'
      rastro "$M_FASE" aviso "checkpoint ignorado: $PREFIXO e ignorada pelo versionador do projeto"
      return 0 ;;
  esac

  guarda_staged "antes de preparar"
  git -C "$RAIZ" add -A -- "$PREFIXO" 2>/dev/null \
    || { printf 'checkpoint=persistencia_falhou\n'; rastro "$M_FASE" falha "persistencia_falhou: git add da pasta da feature falhou"; exit "$E_PERSISTENCIA"; }
  guarda_staged "depois de preparar"

  if git -C "$RAIZ" diff --cached --quiet 2>/dev/null; then
    printf 'checkpoint=sem_mudanca\nfase=%s\nrodada=%s\nestado=%s\npersistencia=duravel\n' "$M_FASE" "$M_RODADA" "$P_ESTADO"
    rastro "$M_FASE" ok "sem_mudanca: HEAD ja representa o estado $P_ESTADO"
    return 0
  fi

  local rotulo="$M_FASE" saida
  [ "$M_FASE" = f5 ] && rotulo="f5 rodada $M_RODADA"
  [ "$M_FASE" = f6 ] && rotulo="f6 replanejamento $M_RODADA"
  if ! saida="$(git -C "$RAIZ" commit -q \
        -m "chore(sprintx): checkpoint de planejamento $SLUG — $rotulo" \
        -m "Planejamento: checkpoint
Trabalho: $SLUG
Fase: $M_FASE
Rodada: $M_RODADA
Estado: $P_ESTADO" 2>&1)"; then
    printf 'checkpoint=persistencia_falhou\npersistencia=pendente\n'
    rastro "$M_FASE" falha "persistencia_falhou: o commit do checkpoint foi rejeitado — $(printf '%s' "$saida" | tr '\n' ' ' | cut -c1-200)"
    printf 'planejamento: persistencia_falhou — commit rejeitado; nada foi limpo nem descartado. O estado %s fica pendente: resolva a causa e rode `planejamento.sh checkpoint %s`. PARE.\n%s\n' "$P_ESTADO" "$SLUG" "$saida" >&2
    exit "$E_PERSISTENCIA"
  fi
  printf 'checkpoint=commitado\npersistencia=duravel\ncommit=%s\nfase=%s\nrodada=%s\nestado=%s\n' \
    "$(git -C "$RAIZ" rev-parse --short HEAD)" "$M_FASE" "$M_RODADA" "$P_ESTADO"
  rastro "$M_FASE" ok "commitado: checkpoint $rotulo, estado $P_ESTADO"
}

guarda_staged() { # prova que todo path staged comeca exatamente por PREFIXO
  local fora p
  fora=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in "$PREFIXO"*) ;; *) fora="$fora $p" ;; esac
  done <<EOF
$(git -C "$RAIZ" -c core.quotepath=false diff --cached --name-only 2>/dev/null)
EOF
  if [ -n "$fora" ]; then
    printf 'checkpoint=recusado_paths\n'
    rastro "$M_FASE" bloqueado "checkpoint recusado ($1): path staged fora de $PREFIXO:$fora"
    printf 'planejamento: checkpoint recusado — path staged fora de %s:%s. Nada foi limpo, descartado ou stashado. PARE.\n' "$PREFIXO" "$fora" >&2
    exit "$E_RECUSADO"
  fi
}

# ------------------------------------------------------------------ comandos

cmd_criar() {
  [ $# -ge 1 ] && [ $# -le 4 ] || falha "$E_USO" "uso: criar <slug> [max_reprovacoes_f5|null] [declarado_por|null] [max_replanejamentos_f6|null]"
  contexto "$1"
  local max="${2:-null}" por="${3:-null}" max6="${4:-null}"
  valida_orcamento "$max" "$por" "$max6"
  valida_orcamento_f6 "$max6" "$por"
  if [ -f "$ARQ" ]; then
    le_planejamento
    if [ "$P_MAX" != "$max" ] || [ "$P_POR" != "$por" ]; then
      falha "$E_CONTRATO" "00-PLANEJAMENTO.md ja registra orcamento $P_MAX/$P_POR; o pedido traz $max/$por — orcamento nao muda em silencio"
    fi
    # Planejamento legado nao tem o eixo F6: continua sem ele. Declarar agora um
    # teto que o arquivo nao tem seria acrescentar orcamento em silencio.
    if [ "$P_F6" = legado ] && [ "$max6" != null ]; then
      falha "$E_CONTRATO" "00-PLANEJAMENTO.md e anterior ao orcamento da F6 (legado); o pedido traz max_replanejamentos_f6=$max6 — orcamento nao e acrescentado numa retomada"
    fi
    if [ "$P_F6" = presente ] && [ "$P_MAX6" != "$max6" ]; then
      falha "$E_CONTRATO" "00-PLANEJAMENTO.md ja registra max_replanejamentos_f6=$P_MAX6; o pedido traz $max6 — orcamento nao muda em silencio"
    fi
    printf 'planejamento=ja_existe\nestado=%s\n' "$P_ESTADO"
    return 0
  fi
  estado_efetivo
  if [ "$E_ESTADO" != null ]; then
    # Feature legada ja adiantada: nasce com o estado que o disco mostra, e com
    # o orcamento que o caller declarou agora.
    migra_legado "$max" "$por" "$max6"
    le_planejamento
    printf 'planejamento=migrado_legado\nmax_reprovacoes_f5=%s\norcamento_declarado_por=%s\nmax_replanejamentos_f6=%s\nestado=%s\n' "$max" "$por" "$max6" "$P_ESTADO"
    return 0
  fi
  f6_novo "$max6"
  escreve "$max" "$por" null 0 ""
  printf 'planejamento=criado\nmax_reprovacoes_f5=%s\norcamento_declarado_por=%s\nmax_replanejamentos_f6=%s\nestado=null\n' "$max" "$por" "$max6"
}

cmd_avanca() {
  [ $# -eq 2 ] || falha "$E_USO" "uso: avanca <slug> f2|f3|f4|f5"
  contexto "$1"
  local alvo="$2" novo
  case "$alvo" in f2|f3|f4|f5) ;; *) falha "$E_USO" "fase invalida: '$alvo' (f2|f3|f4|f5)" ;; esac
  estado_efetivo
  # Transicao anterior gravada e nao persistida: nenhuma nova transicao governa
  # em cima dela. Nada e reescrito; a unica saida e completar o checkpoint.
  persistencia
  if [ "$PERSIST" = pendente ]; then
    printf 'estado=%s\nproxima=CHECKPOINT\npersistencia=pendente\n' "$E_ESTADO"
    rastro "$M_FASE" bloqueado "avanca $alvo recusado: $(pendente_msg)"
    falha "$E_PERSISTENCIA" "avanca $alvo recusado — $(pendente_msg)"
  fi
  fechamento_pendente "avanca $alvo"
  case "$alvo:$E_ESTADO" in
    f2:null|f2:aguardando_f3) novo=aguardando_f3 ;;
    # O retorno da F6 entra pela revisao do plano (F3) — nunca pela F1/F2.
    f3:aguardando_f3|f3:replanejar|f3:aguardando_f4|f3:aguardando_f5|f3:replanejar_execucao) novo=aguardando_f4 ;;
    f4:aguardando_f4|f4:aguardando_f5) novo=aguardando_f5 ;;
    f5:aguardando_f5) novo="" ;;
    f2:*|f3:*|f4:*|f5:*)
      printf 'estado=%s\nproxima=%s\n' "$E_ESTADO" "$(fase_do_estado "$E_ESTADO")"
      falha "$E_TRANSICAO" "transicao $alvo invalida no estado $E_ESTADO" ;;
    *) falha "$E_USO" "fase invalida: '$alvo' (f2|f3|f4|f5)" ;;
  esac
  if [ "$E_FONTE" = legado ]; then
    # Feature anterior a este contrato, numa transicao valida: o arquivo nasce
    # agora, sem teto (a sprintx sozinha nao inventa orcamento) e com o estado
    # que o disco mostra.
    migra_legado
    printf 'planejamento=migrado_legado\n'
    le_planejamento
  fi
  f6_herda
  # Rodada de replanejamento da execucao ativa: cada portao confere que as tasks
  # concluidas continuam congeladas e que o trabalho parcial preservado continua na
  # arvore e na sua task, antes de gravar qualquer coisa.
  if [ -n "$P_BLQ" ]; then confere_congeladas "$alvo"; confere_parciais "$alvo"; fi

  if [ "$alvo" = f5 ]; then
    valida_auditoria
    local rodada=$((P_RODADAS + 1)) reprov="$P_REPROV" hist
    if [ "$A_VEREDITO" = sim ]; then
      novo=aprovado
      # A aprovacao fecha a rodada: confira antes o que o fechamento vai tocar.
      if [ -n "$P_BLQ" ]; then valida_rodada; fi
    else
      reprov=$((reprov + 1))
      if [ "$P_MAX" != null ] && [ "$reprov" -ge "$P_MAX" ]; then novo=orcamento_esgotado; else novo=replanejar; fi
    fi
    hist="$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$rodada" "$A_VEREDITO" "$A_ALTAS" "$A_MEDIAS" "$A_BAIXAS" "$(hoje)")"
    [ -n "$P_HIST" ] && hist="$P_HIST
$hist"
    escreve "$P_MAX" "$P_POR" "$novo" "$reprov" "$hist"
  elif [ "$novo" != "$P_ESTADO" ]; then
    escreve "$P_MAX" "$P_POR" "$novo" "$P_REPROV" "$P_HIST"
  fi

  checkpoint
  le_planejamento
  printf 'estado=%s\nreprovacoes=%s\nmax_reprovacoes_f5=%s\nproxima=%s\n' \
    "$P_ESTADO" "$P_REPROV" "$P_MAX" "$(fase_do_estado "$P_ESTADO")"
  saida_f6
}

# saida_f6 — o eixo F6 no stdout de fase/avanca/replanejar-execucao.
saida_f6() {
  [ "${P_ESTADO-}" = replanejamento_execucao_recusado ] && printf 'recusa_replanejamento_f6=%s\n' "$P_RECUSA"
  if [ "$P_F6" = legado ]; then printf 'orcamento_f6=legado\n'; return 0; fi
  printf 'replanejamentos_f6=%s\nmax_replanejamentos_f6=%s\n' "$P_N6" "$P_MAX6"
  if [ -n "$P_BLQ" ]; then
    printf 'replanejamento_execucao=ativo\nbloqueios_replanejamento_f6=%s\ntasks_congeladas=%s\nparciais_replanejamento_f6=%s\n' \
      "$(printf '%s' "$P_BLQ" | tr ' ' ',')" "$(printf '%s' "$P_CONG" | tr ' ' ',')" \
      "$(printf '%s\n' "$P_PARC" | awk -F'\t' 'NF { printf "%s%s", (n++ ? "," : ""), $1 }')"
  fi
  return 0
}

# fechamento_pendente <acao> — aprovado com a lista da rodada ainda preenchida e
# uma aprovacao gravada cujo fechamento nao terminou: so `checkpoint` completa.
fechamento_pendente() {
  [ "$E_ESTADO" = aprovado ] && [ -n "$P_BLQ" ] || return 0
  printf 'estado=aprovado\nproxima=CHECKPOINT\nfechamento=pendente\n'
  falha "$E_PERSISTENCIA" "$1 recusado — o replanejamento da execucao foi aprovado e o fechamento da rodada ($P_BLQ) nao terminou: execute \`planejamento.sh checkpoint $SLUG\`"
}

# valida_rodada — os B-NN da rodada existem, sao defeito_de_plano, e a task de
# cada um esta bloqueada, pendente ou saiu do plano replanejado.
valida_rodada() {
  local b t c st
  le_bloqueios
  for b in $P_BLQ; do
    c="$(campo_bloqueio "$b" 3)"; t="$(campo_bloqueio "$b" 2)"
    [ -n "$c" ] || falha "$E_CONTRATO" "$b da rodada de replanejamento nao existe em 00-BLOQUEIOS.md"
    [ "$c" = defeito_de_plano ] || falha "$E_CONTRATO" "$b da rodada tem classe $c: so defeito_de_plano abre replanejamento da execucao"
    case "$t" in null|-) continue ;; esac
    st="$(status_da_task "$t" | cut -f2)"
    case "$st" in
      ""|bloqueada|pendente) ;;
      *) falha "$E_CONTRATO" "task $t de $b esta $st: o replanejamento so devolve a pendente uma task bloqueada" ;;
    esac
  done
}

# fecha_rodada — com o estado ja em `aprovado`: resolve os B-NN que abriram a
# rodada (e so eles), reabre a task bloqueada de cada um, esvazia a rodada.
# Task concluida nunca e tocada. Idempotente: B-NN ja resolvido e task ja pendente
# sao pulados.
fecha_rodada() {
  local b t blq="$P_BLQ" parc
  confere_congeladas f5
  confere_parciais f5
  parc="$(printf '%s\n' "$P_PARC" | awk -F'\t' 'NF { printf "%s%s", (n++ ? "," : ""), $1 }')"
  valida_rodada
  for b in $blq; do
    if [ "$(estado_do_bloqueio "$b")" = aberto ]; then
      BLOQ_SH resolver "$SLUG" "$b" >/dev/null \
        || falha "$E_CONTRATO" "bloqueios.sh resolver $b recusou no fechamento da rodada; nada mais foi alterado. Rode \`planejamento.sh checkpoint $SLUG\` depois de corrigir"
    fi
  done
  for b in $blq; do
    t="$(task_do_bloqueio "$b")"
    case "$t" in null|-|"") ;; *) reabre_task "$t" ;; esac
  done
  # O trabalho parcial preservado nao e tocado: fica na arvore, com a task reaberta, e vai
  # no E1 dela. A lista so descreve a rodada — fechada a rodada, ela se esvazia.
  f6_herda; W6_BLQ=""; W6_CONG=""; W6_ASS=null; W6_PARC=""
  escreve "$P_MAX" "$P_POR" "$P_ESTADO" "$P_REPROV" "$P_HIST"
  evento replanejamento_execucao_aprovado f5 - ok "replanejamento da execucao $P_N6 aprovado na F5 rodada $P_RODADAS: $(printf '%s' "$blq" | tr ' ' ',') resolvido(s); tasks concluidas intactas${parc:+; trabalho parcial preservado na arvore: $parc}"
}

# replanejar-execucao — a F6 registrou defeito_de_plano: volta ao planejamento
# pela revisao do plano (F3), congelando o que ja foi concluido.
cmd_replanejar_execucao() {
  [ $# -eq 1 ] || falha "$E_USO" "uso: replanejar-execucao <slug>"
  contexto "$1"
  estado_efetivo
  if [ "$E_FONTE" = legado ]; then
    # Feature sem 00-PLANEJAMENTO.md: o estado sai do disco. So a F6 (aprovado)
    # devolve o plano; fora dela e erro de contrato, e nada e gravado.
    P_ESTADO="$E_ESTADO"
    if [ "$E_ESTADO" != aprovado ]; then
      printf 'replanejamento=recusado\nmotivo=estado\nestado=%s\nproxima=%s\n' "$E_ESTADO" "$(fase_do_estado "$E_ESTADO")"
      falha "$E_TRANSICAO" "replanejar-execucao so parte da F6 (estado aprovado); o estado derivado do disco e $E_ESTADO"
    fi
  fi
  persistencia
  if [ "$PERSIST" = pendente ]; then
    printf 'estado=%s\nproxima=CHECKPOINT\npersistencia=pendente\n' "$E_ESTADO"
    falha "$E_PERSISTENCIA" "replanejar-execucao recusado — $(pendente_msg)"
  fi
  fechamento_pendente replanejar-execucao

  # Mesma rodada: retomar nunca consome orcamento de novo. A arvore tem de ser a que a
  # rodada preservou: o trabalho parcial nao se reconstroi do estado versionado.
  if [ -n "$P_BLQ" ]; then
    confere_parciais f6
    printf 'replanejamento=retomada\nestado=%s\nreprovacoes=%s\nmax_reprovacoes_f5=%s\nproxima=%s\n' \
      "$P_ESTADO" "$P_REPROV" "$P_MAX" "$(fase_do_estado "$P_ESTADO")"
    saida_f6
    evento replanejamento_execucao_retomado f6 - ok "retomada da rodada $P_N6 ($P_BLQ) no estado $P_ESTADO: orcamento da F6 nao consumido de novo"
    return 0
  fi
  if [ "$P_ESTADO" = replanejamento_execucao_esgotado ]; then
    printf 'replanejamento=esgotado\nestado=%s\nproxima=PARAR\n' "$P_ESTADO"
    saida_f6
    return 0
  fi
  # Recusa operacional ja gravada: o mesmo terminal, com o mesmo motivo. Nada e
  # reavaliado, gravado, commitado nem registrado de novo.
  if [ "$P_ESTADO" = replanejamento_execucao_recusado ]; then
    printf 'replanejamento=recusado\nmotivo=%s\nestado=%s\nreprovacoes=%s\nmax_reprovacoes_f5=%s\nproxima=PARAR\npersistencia=%s\n' \
      "$P_RECUSA" "$P_ESTADO" "$P_REPROV" "$P_MAX" "$PERSIST"
    saida_f6
    falha "$E_TRANSICAO" "replanejamento da execucao ja recusado ($P_RECUSA): estado terminal $P_ESTADO. Nada foi gravado de novo. PARE e relate."
  fi
  if [ "$P_ESTADO" != aprovado ]; then
    printf 'replanejamento=recusado\nmotivo=estado\nestado=%s\nproxima=%s\n' "$P_ESTADO" "$(fase_do_estado "$P_ESTADO")"
    falha "$E_TRANSICAO" "replanejar-execucao so parte da F6 (estado aprovado); o estado e $P_ESTADO"
  fi

  # O gatilho e a CHAVE classe dos B-NN abertos — nunca a descricao.
  local abertos b t c defeitos="" outros="" motivo
  # Registro invalido e erro de contrato: validado aqui, fora do subshell abaixo,
  # para que nunca seja lido como "nenhum bloqueio aberto".
  le_bloqueios || falha "$E_CONTRATO" "00-BLOQUEIOS.md invalido"
  abertos="$(abertos_ordenados)"
  while IFS="$(printf '\t')" read -r b t c; do
    [ -n "$b" ] || continue
    if [ "$c" = defeito_de_plano ]; then defeitos="$defeitos $b"; else outros="$outros $b:$c"; fi
  done <<EOF
$abertos
EOF
  defeitos="${defeitos# }"; outros="${outros# }"
  # Sem defeito_de_plano aberto nao ha o que replanejar: erro de quem chamou, nunca
  # estado de negocio — nada e gravado e o estado continua aprovado.
  motivo=""
  if [ -z "$defeitos" ] && [ -z "$outros" ]; then motivo=sem_bloqueio_aberto
  elif [ -z "$defeitos" ]; then motivo=sem_defeito_de_plano
  fi
  if [ -n "$motivo" ]; then
    printf 'replanejamento=recusado\nmotivo=%s\nestado=%s\nabertos=%s\n' "$motivo" "$P_ESTADO" "$(printf '%s' "$outros" | tr ' ' ',')"
    saida_f6
    evento replanejamento_execucao_recusado f6 - bloqueado "$motivo: abertos [$outros]; estado $P_ESTADO mantido"
    falha "$E_TRANSICAO" "replanejamento da execucao recusado ($motivo): nada foi gravado; o estado continua $P_ESTADO. PARE e relate os bloqueios abertos."
  fi
  # Ha defeito_de_plano aberto e a rodada nao pode abrir: recusa OPERACIONAL,
  # gravada como terminal e persistida.
  if [ -n "$outros" ]; then motivo=classes_mistas
  elif [ "$E_FONTE" = legado ]; then motivo=planejamento_legado
  elif [ "$P_F6" = legado ]; then motivo=orcamento_f6_legado
  elif [ "$P_MAX6" = null ]; then motivo=orcamento_f6_nao_declarado
  fi
  if [ -n "$motivo" ]; then recusa_duravel "$motivo" "$defeitos${outros:+ }$outros"; fi

  f6_herda
  if [ "$P_N6" -ge "$P_MAX6" ]; then
    # Orcamento da F6 consumido: nenhuma rodada nova. Estado terminal proprio,
    # distinto de orcamento_esgotado (F5).
    escreve "$P_MAX" "$P_POR" replanejamento_execucao_esgotado "$P_REPROV" "$P_HIST"
    evento replanejamento_execucao_esgotado f6 - bloqueado "orcamento da F6 consumido ($P_N6 de $P_MAX6): defeito_de_plano [$defeitos] nao abre rodada nova"
    checkpoint
    le_planejamento
    printf 'replanejamento=esgotado\nestado=%s\nreprovacoes=%s\nmax_reprovacoes_f5=%s\nproxima=PARAR\nabertos=%s\n' \
      "$P_ESTADO" "$P_REPROV" "$P_MAX" "$(printf '%s' "$defeitos" | tr ' ' ',')"
    saida_f6
    return 0
  fi

  # A task de cada bloqueio ja tem de estar gravada como bloqueada.
  local st
  BLOQ_TASKS=""
  for b in $defeitos; do
    t="$(task_do_bloqueio "$b")"
    case "$t" in null|-|"") continue ;; esac
    st="$(status_da_task "$t" | cut -f2)"
    [ "$st" = bloqueada ] || falha "$E_CONTRATO" "$b aponta $t, que esta '${st:-fora do plano}' em tasks.md: grave a task como bloqueada antes de replanejar"
    BLOQ_TASKS="$BLOQ_TASKS $t"
  done
  fronteira_segura

  calcula_congeladas
  W6_N=$((P_N6 + 1)); W6_BLQ="$defeitos"; W6_CONG="$C_IDS"; W6_ASS="$C_ASS"; W6_PARC="$F_PARC"
  escreve "$P_MAX" "$P_POR" replanejar_execucao "$P_REPROV" "$P_HIST"
  evento replanejamento_execucao_iniciado f6 - ok "replanejamento da execucao $W6_N de $P_MAX6 aberto por [$defeitos]; reprovacoes da F5 continuam em $P_REPROV; congeladas [$W6_CONG]; trabalho parcial preservado [$(printf '%s\n' "$F_PARC" | awk -F'\t' 'NF { printf "%s%s", (n++ ? "," : ""), $1 }')]"
  checkpoint
  le_planejamento
  printf 'replanejamento=iniciado\nestado=%s\nreprovacoes=%s\nmax_reprovacoes_f5=%s\nproxima=%s\n' \
    "$P_ESTADO" "$P_REPROV" "$P_MAX" "$(fase_do_estado "$P_ESTADO")"
  saida_f6
}

# recusa_duravel <motivo> <abertos> — grava o terminal replanejamento_execucao_recusado
# com o motivo, faz o checkpoint (a mesma disciplina do esgotado) e sai com o codigo
# da recusa. Sem 00-PLANEJAMENTO.md o arquivo nasce pela migracao, sem orcamento
# inventado. Nenhuma rodada, nenhum contador, nenhuma task: so o terminal.
recusa_duravel() {
  local motivo="$1" abertos="$2"
  if [ "$E_FONTE" = legado ]; then
    migra_legado null null null replanejamento_execucao_recusado "$motivo"
  else
    f6_herda; W_RECUSA="$motivo"
    escreve "$P_MAX" "$P_POR" replanejamento_execucao_recusado "$P_REPROV" "$P_HIST"
  fi
  evento replanejamento_execucao_recusado f6 - bloqueado "$motivo: abertos [$abertos]; estado terminal replanejamento_execucao_recusado gravado"
  checkpoint
  le_planejamento
  printf 'replanejamento=recusado\nmotivo=%s\nestado=%s\nreprovacoes=%s\nmax_reprovacoes_f5=%s\nproxima=PARAR\nabertos=%s\n' \
    "$P_RECUSA" "$P_ESTADO" "$P_REPROV" "$P_MAX" "$(printf '%s' "$abertos" | tr ' ' ',')"
  saida_f6
  falha "$E_TRANSICAO" "replanejamento da execucao recusado ($motivo): estado terminal $P_ESTADO gravado; nenhuma rodada aberta, nenhum orcamento consumido. PARE e relate os bloqueios abertos."
}

# pode-resolver — um defeito_de_plano so e resolvido quando pertence a rodada de
# replanejamento da execucao e essa rodada ja voltou a `aprovado` pela F5.
cmd_pode_resolver() {
  [ $# -eq 2 ] || falha "$E_USO" "uso: pode-resolver <slug> <B-NN>"
  contexto "$1"
  local b="$2" motivo=""
  if [ ! -f "$ARQ" ]; then motivo=sem_planejamento
  else
    le_planejamento
    if ! em_lista "$b" "$P_BLQ"; then motivo=fora_da_rodada
    elif [ "$P_ESTADO" != aprovado ]; then motivo=rodada_nao_aprovada
    fi
  fi
  if [ -n "$motivo" ]; then
    printf 'pode_resolver=nao\nmotivo=%s\n' "$motivo"
    falha "$E_TRANSICAO" "$b nao pode ser resolvido agora ($motivo): defeito_de_plano so e resolvido quando o plano replanejado volta a aprovado"
  fi
  printf 'pode_resolver=sim\n'
}

cmd_checkpoint() {
  [ $# -eq 1 ] || falha "$E_USO" "uso: checkpoint <slug>"
  contexto "$1"
  checkpoint
}

cmd_fase() {
  [ $# -eq 1 ] || falha "$E_USO" "uso: fase <slug>"
  contexto "$1"
  estado_efetivo
  if [ "$E_ESTADO" = aprovado ] && [ "$(ultimo_veredito)" != SIM ]; then
    printf 'fase=INCONSISTENTE\nestado=aprovado\nfonte=%s\n' "$E_FONTE"
    falha "$E_TRANSICAO" "estado aprovado, mas 00-AUDITORIA.md nao termina em VEREDITO: SIM"
  fi
  persistencia
  if [ "$PERSIST" = pendente ]; then
    printf 'fase=CHECKPOINT\nestado=%s\nfonte=%s\npersistencia=pendente\n' "$E_ESTADO" "$E_FONTE"
    falha "$E_PERSISTENCIA" "$(pendente_msg)"
  fi
  if [ "$E_ESTADO" = aprovado ] && [ -n "$P_BLQ" ]; then
    printf 'fase=CHECKPOINT\nestado=aprovado\nfonte=%s\nfechamento=pendente\n' "$E_FONTE"
    falha "$E_PERSISTENCIA" "o replanejamento da execucao foi aprovado e o fechamento da rodada nao terminou: execute \`planejamento.sh checkpoint $SLUG\`"
  fi
  # Rodada ativa: a sessao que retoma descobre ja aqui se a arvore ainda e a que a rodada
  # preservou. So diagnostica — `fase` nunca grava.
  if [ -n "$P_BLQ" ]; then
    diagnostica_parciais
    if [ "$D_PARC" != integro ]; then
      printf 'fase=PARAR\nestado=%s\nfonte=%s\ntrabalho_parcial=%s\nmotivo=parcial_%s\n' "$E_ESTADO" "$E_FONTE" "$D_PARC" "$D_PARC"
      falha "$E_RECUSADO" "trabalho parcial $D_PARC:$D_DET. A rodada de replanejamento preservou trabalho parcial da task bloqueada que esta arvore nao tem como estava; o conteudo nao se reconstroi do estado versionado. PARE e relate."
    fi
  fi
  printf 'fase=%s\nestado=%s\nfonte=%s\npersistencia=%s\n' "$(fase_do_estado "$E_ESTADO")" "$E_ESTADO" "$E_FONTE" "$PERSIST"
  saida_f6
}

cmd_valida_auditoria() {
  [ $# -eq 1 ] || falha "$E_USO" "uso: valida-auditoria <slug>"
  contexto "$1"
  valida_auditoria
  printf 'veredito=%s\naltas=%s\nmedias=%s\nbaixas=%s\n' "$A_VEREDITO" "$A_ALTAS" "$A_MEDIAS" "$A_BAIXAS"
}

# obrigacoes-f6 — toda task que chega da ultima F5 com [fraco:teste]:
# task TAB clausula TAB implementacao errada. A F6 endurece o teste de cada uma
# ANTES de escrever codigo de produto.
cmd_obrigacoes_f6() {
  [ $# -eq 1 ] || falha "$E_USO" "uso: obrigacoes-f6 <slug>"
  contexto "$1"
  valida_auditoria
  local sev prob resto task clausula impl tabela
  tabela="$(linhas_da_tabela)"
  [ -n "$tabela" ] || return 0
  while IFS="$(printf '\t')" read -r sev prob; do
    case "$prob" in "[item 2][fraco:teste] "*) ;; *) continue ;; esac
    resto="${prob#*] }"
    task="${resto%% — cláusula: *}"
    clausula="${resto#* — cláusula: }"; clausula="${clausula%% — passaria com: *}"
    impl="${resto#* — passaria com: }"
    printf '%s\t%s\t%s\n' "$task" "$clausula" "$impl"
  done <<EOF
$tabela
EOF
}

cmd_severidade() {
  [ $# -eq 1 ] || falha "$E_USO" "uso: severidade ausente|criterio|teste"
  severidade_de "$1" || falha "$E_CONTRATO" "tipo de fraco invalido: '$1'"
  printf '\n'
}

# revisor — normaliza a saida do revisor-testes. Entrada, uma por task:
#   T-NN.MM | solido
#   T-NN.MM | fraco | <ausente|criterio|teste> | <clausula-ou-> | <implementacao-errada>
# Saida: T-NN.MM TAB solido
#    ou: T-NN.MM TAB fraco TAB <tipo efetivo> TAB <severidade> TAB <clausula> TAB <impl> TAB <problema para 00-AUDITORIA.md>
# `teste` sem clausula citavel vira `criterio` (ALTA): sem clausula, nao ha o
# que o teste deixe de provar — falta a regra.
cmd_revisor() {
  local linha n=0 task juizo tipo clausula impl resto sev
  while IFS= read -r linha || [ -n "$linha" ]; do
    linha="$(printf '%s' "$linha" | tr -d '\r')"
    [ -n "$(trim "$linha")" ] || continue
    n=$((n + 1))
    task="$(trim "${linha%%|*}")"
    printf '%s' "$task" | grep -Eq '^T-[0-9]{2,}\.[0-9]{2,}$' || falha "$E_CONTRATO" "linha $n: id de task invalido: $linha"
    resto="${linha#*|}"
    case "$resto" in
      *"|"*) juizo="$(trim "${resto%%|*}")"; resto="${resto#*|}" ;;
      *) juizo="$(trim "$resto")"; resto="" ;;
    esac
    case "$juizo" in
      solido)
        [ -z "$(trim "$resto")" ] || falha "$E_CONTRATO" "linha $n: solido nao leva motivo: $linha"
        printf '%s\tsolido\n' "$task"; continue ;;
      fraco) ;;
      *) falha "$E_CONTRATO" "linha $n: juizo deve ser solido ou fraco: $linha" ;;
    esac
    case "$resto" in *"|"*"|"*) ;; *) falha "$E_CONTRATO" "linha $n: fraco exige tipo, clausula e implementacao errada: $linha" ;; esac
    tipo="$(trim "${resto%%|*}")"; resto="${resto#*|}"
    clausula="$(trim "${resto%%|*}")"; impl="$(trim "${resto#*|}")"
    severidade_de "$tipo" >/dev/null || falha "$E_CONTRATO" "linha $n: tipo de fraco invalido '$tipo': $linha"
    [ -n "$clausula" ] || falha "$E_CONTRATO" "linha $n: clausula vazia (use -): $linha"
    [ -n "$impl" ] && [ "$impl" != "-" ] || falha "$E_CONTRATO" "linha $n: fraco sem implementacao errada: $linha"
    if [ "$tipo" = teste ] && ! clausula_citavel "$clausula"; then tipo=criterio; fi
    sev="$(severidade_de "$tipo")"
    printf '%s\tfraco\t%s\t%s\t%s\t%s\t[item 2][fraco:%s] %s — cláusula: %s — passaria com: %s\n' \
      "$task" "$tipo" "$sev" "$clausula" "$impl" "$tipo" "$task" "$clausula" "$impl"
  done
}

# ------------------------------------------------------------------ entrada

[ $# -ge 1 ] || { sed -n '17,29p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "$E_USO"; }
CMD="$1"; shift
case "$CMD" in
  criar)            cmd_criar "$@" ;;
  avanca)           cmd_avanca "$@" ;;
  replanejar-execucao) cmd_replanejar_execucao "$@" ;;
  pode-resolver)    cmd_pode_resolver "$@" ;;
  checkpoint)       cmd_checkpoint "$@" ;;
  fase)             cmd_fase "$@" ;;
  valida-auditoria) cmd_valida_auditoria "$@" ;;
  obrigacoes-f6)    cmd_obrigacoes_f6 "$@" ;;
  severidade)       cmd_severidade "$@" ;;
  revisor)          cmd_revisor "$@" ;;
  *) falha "$E_USO" "comando desconhecido: $CMD" ;;
esac
