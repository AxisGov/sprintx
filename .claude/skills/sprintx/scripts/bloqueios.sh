#!/usr/bin/env bash
# bloqueios.sh — o bloqueio da sprintx como dado tipado.
#
# Unico escritor de entradas NOVAS em docs/sprintx/features/<slug>/00-BLOQUEIOS.md
# (kind: bloqueios). Todo B-NN novo nasce com `classe` do enum abaixo, dada por
# quem registra a partir do caminho de criacao em references/06-execucao.md.
# A classe nunca sai da descricao: a prosa explica, nao classifica (DS-139).
#
# Leitura historica: entrada sem a chave `classe` e legado. Continua legivel e
# sai como `legado` — nunca ganha classe inferida. Legado so existe ANTES da
# primeira entrada tipada: entrada sem classe depois de uma tipada e bloqueio
# novo sem classe, e o arquivo e recusado.
#
# Sem jq, sem python, sem rede. Bash 3.2 (macOS) compativel.
#
# Uso (a partir de qualquer diretorio do repositorio; SPRINTX_RAIZ sobrescreve a raiz):
#
#   bloqueios.sh registrar <slug> <T-NN.MM|null> <classe> <descricao> <o que destravaria>
#   bloqueios.sh listar <slug>      id TAB task TAB classe|legado TAB aberto|resolvido
#   bloqueios.sh validar <slug>
#   bloqueios.sh classes            o enum, um valor por linha
#
# Codigos de saida:
#   0  ok
#   4  contrato invalido (classe ausente ou fora do enum, arquivo sem frontmatter,
#      entrada malformada, bloqueio novo sem classe)
#   64 uso incorreto

set -uo pipefail

SK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SK/assets/TEMPLATE-BLOQUEIOS.md"

E_CONTRATO=4; E_USO=64

# O enum `classe` (bloqueio) de references/00-schema.md. `legado` NAO e classe:
# e o que a leitura devolve para entrada sem a chave, e nunca e gravado.
CLASSES="defeito_de_plano lacuna_de_decisao prerequisito_ausente suite_vermelha task_reivindicada"

falha() { local c="$1"; shift; printf 'bloqueios: %s\n' "$*" >&2; exit "$c"; }

resolve_raiz() {
  if [ -n "${SPRINTX_RAIZ:-}" ]; then printf '%s' "$SPRINTX_RAIZ"; return; fi
  local t; t="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$t" ] && { printf '%s' "$t"; return; }
  printf '%s' "$PWD"
}

contexto() { # contexto <slug>
  SLUG="$1"
  printf '%s' "$SLUG" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' \
    || falha "$E_USO" "slug invalido: '$SLUG' (a-z, 0-9 e hifen)"
  PASTA="$(resolve_raiz)/docs/sprintx/features/$SLUG"
  ARQ="$PASTA/00-BLOQUEIOS.md"
}

hoje() { date +%Y-%m-%d; }

classe_valida() { case " $CLASSES " in *" $1 "*) [ -n "$1" ] ;; *) return 1 ;; esac; }

# ------------------------------------------------------------------ leitura

# entradas <arquivo> — uma linha por B-NN: id TAB task TAB classe TAB resolvido_em TAB n_classe.
# Le SO as chaves id, task, classe e resolvido_em; `descricao` nunca e aberta aqui.
# Valor vazio sai como "-" (o read junta tabs vazios); quem diz se a chave classe
# existe e n_classe, nunca o valor. Linha fora da forma sai como LIXO.
entradas() {
  tr -d '\r' < "$1" | awk '
    function v0(x) { return x == "" ? "-" : x }
    function sai() { if (id != "") print id "\t" v0(t) "\t" v0(c) "\t" v0(r) "\t" nc; id = "" }
    NR == 1 { next }
    $0 == "---" { exit }
    /^bloqueios:[ \t]*\[\][ \t]*$/ { exit }
    /^bloqueios:[ \t]*$/ { b = 1; next }
    b && /^[^ ]/ { b = 0 }
    !b { next }
    /^  - id:/           { sai(); id = $3; t = r = c = ""; nc = 0; next }
    id == "" { print "LIXO\t" $0; next }
    /^    task:/         { t = $2; next }
    /^    classe:/       { v = $0; sub(/^    classe:[ \t]*/, "", v); sub(/[ \t]+$/, "", v); c = v; nc++; next }
    /^    resolvido_em:/ { r = $2; next }
    /^    [a-z_]+:/      { next }
    { print "LIXO\t" $0 }
    END { sai() }'
}

# classe_lida <classe> <n_classe> — o que o consumidor recebe: a chave gravada, ou `legado` sem ela.
classe_lida() { if [ "$2" -eq 0 ]; then printf 'legado'; else printf '%s' "$1"; fi; }

tem_frontmatter() {
  [ "$(tr -d '\r' < "$1" | head -1)" = "---" ] \
    && tr -d '\r' < "$1" | awk 'NR == 1 { next } $0 == "---" { exit } $0 == "kind: bloqueios" { achou = 1 } END { exit !achou }'
}

# valida — o arquivo inteiro. Legado (sem classe) so antes da primeira entrada tipada.
valida() {
  [ -f "$ARQ" ] || falha "$E_CONTRATO" "$ARQ nao existe"
  tem_frontmatter "$ARQ" || falha "$E_CONTRATO" "00-BLOQUEIOS.md sem frontmatter kind: bloqueios (regra de migracao em references/00-schema.md)"
  local id task classe resolvido nc tipada="" vistos=" "
  while IFS=$'\t' read -r id task classe resolvido nc; do
    [ -n "$id" ] || continue
    [ "$id" = LIXO ] && falha "$E_CONTRATO" "linha fora da forma no frontmatter: $task"
    printf '%s' "$id" | grep -Eq '^B-[0-9]{2,}$' || falha "$E_CONTRATO" "id invalido: '$id' (B-NN)"
    case "$vistos" in *" $id "*) falha "$E_CONTRATO" "$id repetido" ;; esac
    vistos="$vistos$id "
    [ "$nc" -gt 1 ] && falha "$E_CONTRATO" "$id tem a chave classe $nc vezes"
    if [ "$nc" -eq 0 ]; then
      [ -n "$tipada" ] && falha "$E_CONTRATO" "$id sem classe depois de $tipada, que ja e tipado: bloqueio novo sem classe"
    else
      classe_valida "$classe" || falha "$E_CONTRATO" "$id com classe '$classe' fora do enum ($CLASSES)"
      tipada="$id"
    fi
  done <<EOF
$(entradas "$ARQ")
EOF
  return 0
}

# ------------------------------------------------------------------ comandos

cmd_listar() {
  valida
  local id task classe resolvido nc
  while IFS=$'\t' read -r id task classe resolvido nc; do
    [ -n "$id" ] || continue
    case "$resolvido" in null|-) resolvido=aberto ;; *) resolvido=resolvido ;; esac
    printf '%s\t%s\t%s\t%s\n' "$id" "$task" "$(classe_lida "$classe" "$nc")" "$resolvido"
  done <<EOF
$(entradas "$ARQ")
EOF
}

yaml_str() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '"%s"' "$s"; }

uma_linha() { # uma_linha <campo> <valor> — texto de uma linha, nao vazio, sem "|" (quebra a linha de prosa)
  case "$2" in
    "") falha "$E_CONTRATO" "$1 vazio" ;;
    *$'\n'*|*$'\r'*) falha "$E_CONTRATO" "$1 com mais de uma linha" ;;
    *"|"*) falha "$E_CONTRATO" "$1 com '|': a linha B-NN da prosa usa '|' como separador" ;;
  esac
}

cmd_registrar() { # <task|null> <classe> <descricao> <destravaria>
  local task="$1" classe="$2" desc="$3" dest="$4"
  [ -n "$classe" ] || falha "$E_CONTRATO" "bloqueio novo sem classe: escolha pelo caminho de criacao ($CLASSES)"
  classe_valida "$classe" || falha "$E_CONTRATO" "classe '$classe' fora do enum ($CLASSES)"
  [ "$task" = null ] || printf '%s' "$task" | grep -Eq '^T-[0-9]{2}\.[0-9]{2}$' \
    || falha "$E_CONTRATO" "task invalida: '$task' (T-NN.MM ou null)"
  uma_linha descricao "$desc"; uma_linha "o que destravaria" "$dest"

  if [ ! -f "$ARQ" ]; then
    mkdir -p "$PASTA" || falha "$E_CONTRATO" "nao consegui criar $PASTA"
    sed -e "2,/^---/s/{{slug-da-feature}}/$SLUG/" -e "2,/^---/s/{{AAAA-MM-DD}}/$(hoje)/" "$TEMPLATE" > "$ARQ" \
      || falha "$E_CONTRATO" "nao consegui criar $ARQ"
  fi
  valida

  local n id
  n="$(entradas "$ARQ" | awk -F'\t' '{ sub(/^B-0*/, "", $1); if ($1 + 0 > m) m = $1 + 0 } END { print m + 0 }')"
  id="$(printf 'B-%02d' $((n + 1)))"

  local ent tmp="$ARQ.tmp.$$"
  ent="$(printf '  - id: %s\n    task: %s\n    classe: %s\n    aberto_em: %s\n    resolvido_em: null\n    descricao: %s' \
    "$id" "$task" "$classe" "$(hoje)" "$(yaml_str "$desc")")"
  # Valores pelo ambiente: awk -v interpretaria "\" da descricao.
  tr -d '\r' < "$ARQ" | BL_ENT="$ent" BL_HOJE="$(hoje)" BL_PROSA="$id | $task | $desc | $dest" awk '
    function poe() { if (!posto) { print ENVIRON["BL_ENT"]; posto = 1 } }
    { l[NR] = $0 }
    END {
      hoje = ENVIRON["BL_HOJE"]; prosa = ENVIRON["BL_PROSA"]
      # frontmatter: atualizado_em reescrito; a entrada fecha o bloco bloqueios:
      for (i = 2; i <= NR; i++) if (l[i] == "---") { fim = i; break }
      # prosa: a linha "Nenhum bloqueio registrado." ou depois da ultima B-NN fora de comentario
      for (i = fim + 1; i <= NR; i++) {
        if (index(l[i], "<!--")) com = 1
        if (!com && l[i] == "Nenhum bloqueio registrado.") nenhum = i
        if (!com && l[i] ~ /^B-[0-9]+ \|/) ultima = i
        if (index(l[i], "-->")) com = 0
      }
      alvo = nenhum ? nenhum : ultima
      for (i = 1; i <= NR; i++) {
        s = l[i]
        if (i > 1 && i < fim) {
          if (s ~ /^atualizado_em:/) s = "atualizado_em: " hoje
          if (s ~ /^bloqueios:[ \t]*\[\][ \t]*$/) { print "bloqueios:"; poe(); continue }
          if (s ~ /^bloqueios:[ \t]*$/) dentro = 1
          else if (dentro && s ~ /^[^ ]/) { poe(); dentro = 0 }
        }
        if (i == fim && dentro) { poe(); dentro = 0 }
        if (i == nenhum) { print prosa; continue }
        print s
        if (i == alvo) print prosa
      }
      if (!alvo) print prosa
      if (!posto) exit 3
    }' > "$tmp" || { rm -f "$tmp"; falha "$E_CONTRATO" "nao consegui gravar $ARQ (frontmatter sem a chave bloqueios:?)"; }
  ( ARQ="$tmp"; valida ) || { rm -f "$tmp"; exit "$E_CONTRATO"; }
  mv "$tmp" "$ARQ" || { rm -f "$tmp"; falha "$E_CONTRATO" "nao consegui gravar $ARQ"; }
  printf 'id=%s\ntask=%s\nclasse=%s\n' "$id" "$task" "$classe"
}

# ------------------------------------------------------------------ entrada

[ $# -ge 1 ] || falha "$E_USO" "uso: bloqueios.sh registrar|listar|validar|classes ..."
cmd="$1"; shift
case "$cmd" in
  registrar)
    [ $# -eq 5 ] || falha "$E_USO" "uso: bloqueios.sh registrar <slug> <T-NN.MM|null> <classe> <descricao> <o que destravaria>"
    contexto "$1"; shift; cmd_registrar "$@" ;;
  listar)  [ $# -eq 1 ] || falha "$E_USO" "uso: bloqueios.sh listar <slug>";  contexto "$1"; cmd_listar ;;
  validar) [ $# -eq 1 ] || falha "$E_USO" "uso: bloqueios.sh validar <slug>"; contexto "$1"; valida; printf 'valido=sim\n' ;;
  classes) [ $# -eq 0 ] || falha "$E_USO" "uso: bloqueios.sh classes"; printf '%s\n' $CLASSES ;;
  *) falha "$E_USO" "comando desconhecido: $cmd" ;;
esac
