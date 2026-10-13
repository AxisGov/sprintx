#!/usr/bin/env bash
# predecessores.sh — registra e prova documentos consumidos antes da SprintX.
# Bash 3.2; sem jq, python ou eval.
set -uo pipefail
export GIT_LITERAL_PATHSPECS=1

E_PROVA=3
E_CONTRATO=4
E_USO=64
TMP_ATOMICO=""
trap '[ -z "$TMP_ATOMICO" ] || rm -f "$TMP_ATOMICO"' EXIT HUP INT TERM

falha() { local rc="$1"; shift; printf 'predecessores: %s\n' "$*" >&2; exit "$rc"; }

uso() {
  falha "$E_USO" 'uso: --registrar <slug> --origem superpowers --papel <especificacao|plano> --caminho <path> | --validar <slug> | --listar <slug>'
}

valida_slug() {
  case "$1" in ""|-*|*-|*--*|*[!a-z0-9-]*) falha "$E_USO" "slug invalido: $1" ;; esac
}

resolve_raiz() {
  local raiz
  if [ -n "${SPRINTX_RAIZ:-}" ]; then
    git -C "$SPRINTX_RAIZ" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
      || falha "$E_PROVA" 'SPRINTX_RAIZ nao aponta para repositorio Git'
    printf '%s' "$SPRINTX_RAIZ"
    return 0
  fi
  raiz="$(git rev-parse --show-toplevel 2>/dev/null)" || falha "$E_PROVA" 'fora de um repositorio Git'
  printf '%s' "$raiz"
}

tem_palavra() { case " $1 " in *" $2 "*) return 0 ;; esac; return 1; }

valida_caminho() {
  local p="$1"
  case "$p" in
    ""|/*|[A-Za-z]:/*|./*|*/./*|*/.|../*|*/../*|*/..|*//*|*\\*|*\**|*\?*|*\[*|*\]*)
      falha "$E_CONTRATO" "caminho nao canonico: $p" ;;
  esac
  case "$p" in
    docs/sprintx/features/"$SLUG"/*|docs/entregas/"$SLUG"/*)
      falha "$E_CONTRATO" "predecessor dentro do proprio trabalho: $p" ;;
  esac
}

modo_blob() { # modo_blob <rev> <path>; imprime modo TAB oid
  local linha modo tipo oid
  linha="$(git -C "$RAIZ" ls-tree "$1" -- "$2" 2>/dev/null)" || return 1
  [ -n "$linha" ] || return 1
  modo="${linha%% *}"; linha="${linha#* }"; tipo="${linha%% *}"; linha="${linha#* }"; oid="${linha%%[[:space:]]*}"
  [ "$tipo" = blob ] || return 1
  case "$modo" in 100644|100755) ;; *) return 1 ;; esac
  printf '%s\t%s\n' "$modo" "$oid"
}

estado_pre_nascimento() {
  [ -f "$RAIZ/$PLANEJAMENTO_REL" ] || return 1
  git -C "$RAIZ" ls-files --error-unmatch -- "$PLANEJAMENTO_REL" >/dev/null 2>&1 && return 1
  if [ -e "$MANIFESTO" ]; then
    git -C "$RAIZ" ls-files --error-unmatch -- "$MANIFESTO_REL" >/dev/null 2>&1 && return 1
  fi
  return 0
}

prova_nascimento() { # prova_nascimento <commit>
  local commit="$1" nascimentos n nascimento
  nascimentos="$(git -C "$RAIZ" log --format=%H --diff-filter=A -- "$PLANEJAMENTO_REL" 2>/dev/null)" \
    || falha "$E_PROVA" 'nao foi possivel ler a historia do planejamento'
  n="$(printf '%s\n' "$nascimentos" | sed '/^$/d' | wc -l | tr -d ' ')"
  case "$n" in
    0)
      estado_pre_nascimento || falha "$E_PROVA" 'nascimento do planejamento ausente fora do estado pre-checkpoint'
      git -C "$RAIZ" merge-base --is-ancestor "$commit" HEAD >/dev/null 2>&1 \
        || falha "$E_PROVA" 'predecessor nao e ancestral de HEAD no estado pre-checkpoint'
      ;;
    1)
      nascimento="$(printf '%s\n' "$nascimentos" | sed -n '1p')"
      [ "$commit" != "$nascimento" ] || falha "$E_PROVA" 'predecessor nasceu junto com o planejamento'
      git -C "$RAIZ" merge-base --is-ancestor "$commit" "$nascimento" >/dev/null 2>&1 \
        || falha "$E_PROVA" 'predecessor nao antecede estritamente o planejamento'
      ;;
    *) falha "$E_PROVA" 'mais de um commit adiciona 00-PLANEJAMENTO.md' ;;
  esac
}

prova_item() { # prova_item <path> <origem> <papel> <commit> <blob>
  local caminho="$1" origem="$2" papel="$3" commit="$4" blob="$5" a b oid_commit oid_head oid_disco
  valida_caminho "$caminho"
  [ "$origem" = superpowers ] || falha "$E_CONTRATO" "origem fora do enum: $origem"
  case "$papel" in especificacao|plano) ;; *) falha "$E_CONTRATO" "papel fora do enum: $papel" ;; esac
  [ "${#commit}" -eq 40 ] && case "$commit" in *[!0-9a-f]*) false ;; *) true ;; esac \
    || falha "$E_CONTRATO" "commit_sha invalido para $caminho"
  [ "${#blob}" -eq 40 ] && case "$blob" in *[!0-9a-f]*) false ;; *) true ;; esac \
    || falha "$E_CONTRATO" "blob_oid invalido para $caminho"

  [ "$(git -C "$RAIZ" rev-parse --is-shallow-repository 2>/dev/null)" = false ] \
    || falha "$E_PROVA" 'repositorio raso nao prova predecessores'
  git -C "$RAIZ" cat-file -e "$commit^{commit}" 2>/dev/null \
    || falha "$E_PROVA" "commit predecessor ausente: $commit"
  git -C "$RAIZ" merge-base --is-ancestor "$commit" HEAD >/dev/null 2>&1 \
    || falha "$E_PROVA" "commit predecessor nao alcancavel de HEAD: $commit"
  prova_nascimento "$commit"

  [ -f "$RAIZ/$caminho" ] && [ ! -L "$RAIZ/$caminho" ] \
    || falha "$E_CONTRATO" "predecessor ausente ou nao regular no disco: $caminho"
  git -C "$RAIZ" ls-files --error-unmatch -- "$caminho" >/dev/null 2>&1 \
    || falha "$E_CONTRATO" "predecessor nao rastreado: $caminho"
  git -C "$RAIZ" diff --quiet -- "$caminho" \
    || falha "$E_CONTRATO" "predecessor modificado: $caminho"
  git -C "$RAIZ" diff --cached --quiet -- "$caminho" \
    || falha "$E_CONTRATO" "predecessor staged: $caminho"

  a="$(modo_blob "$commit" "$caminho")" || falha "$E_PROVA" "predecessor nao e blob regular: $caminho"
  b="$(modo_blob HEAD "$caminho")" || falha "$E_PROVA" "HEAD nao contem blob regular: $caminho"
  oid_commit="${a#*	}"; oid_head="${b#*	}"
  oid_disco="$(git -C "$RAIZ" hash-object --path="$caminho" -- "$RAIZ/$caminho" 2>/dev/null)" \
    || falha "$E_CONTRATO" "nao foi possivel provar o arquivo no disco: $caminho"
  [ "$oid_disco" = "$oid_head" ] || falha "$E_CONTRATO" "predecessor modificado: $caminho"
  [ "$oid_commit" = "$blob" ] || falha "$E_PROVA" "blob declarado diverge do predecessor: $caminho"
  [ "$oid_head" = "$blob" ] || falha "$E_PROVA" "blob atual diverge do predecessor: $caminho"
}

zera_item() { I_CAM=""; I_ORI=""; I_PAP=""; I_COM=""; I_BLO=""; I_SEEN=""; I_OPEN=0; }

campo_item() { # campo_item <key> <value>
  local k="$1" v="$2"
  [ "$I_OPEN" -eq 1 ] || falha "$E_CONTRATO" "campo de predecessor fora de item: $k"
  tem_palavra "$I_SEEN" "$k" && falha "$E_CONTRATO" "chave repetida no predecessor: $k"
  I_SEEN="$I_SEEN $k"
  case "$k" in
    caminho) I_CAM="$v" ;;
    origem) I_ORI="$v" ;;
    papel) I_PAP="$v" ;;
    commit_sha) I_COM="$v" ;;
    blob_oid) I_BLO="$v" ;;
    *) falha "$E_CONTRATO" "chave desconhecida no predecessor: $k" ;;
  esac
}

fecha_item() {
  [ "$I_OPEN" -eq 1 ] || return 0
  for k in caminho origem papel commit_sha blob_oid; do
    tem_palavra "$I_SEEN" "$k" || falha "$E_CONTRATO" "predecessor sem chave: $k"
  done
  valida_caminho "$I_CAM"
  grep -Fqx "${I_CAM}	" "$P_PATHS" 2>/dev/null && falha "$E_CONTRATO" "caminho duplicado: $I_CAM"
  printf '%s\t\n' "$I_CAM" >> "$P_PATHS"
  printf '%s\t%s\t%s\t%s\t%s\n' "$I_CAM" "$I_ORI" "$I_PAP" "$I_COM" "$I_BLO" >> "$P_TSV"
  P_N=$((P_N + 1))
  zera_item
}

campo_topo() { # campo_topo <key> <value>
  local k="$1" v="$2"
  tem_palavra "$P_TOP_SEEN" "$k" && falha "$E_CONTRATO" "chave repetida no frontmatter: $k"
  P_TOP_SEEN="$P_TOP_SEEN $k"
  case "$k" in
    expx_schema) P_SCHEMA="$v" ;;
    expx_tool) P_TOOL="$v" ;;
    kind) P_KIND="$v" ;;
    trabalho_id) P_TRAB="$v" ;;
    predecessores) [ "$v" = __LISTA__ ] || falha "$E_CONTRATO" 'predecessores precisa ser lista' ;;
    criado_em) P_CRIADO="$v" ;;
    atualizado_em) P_ATUAL="$v" ;;
    *) falha "$E_CONTRATO" "chave desconhecida no frontmatter: $k" ;;
  esac
}

abre_lista() { # abre_lista <marcador>
  [ "$P_LIST_STATE" = antes ] || falha "$E_CONTRATO" 'secao predecessores repetida ou reaberta'
  campo_topo predecessores "$1"
  P_LIST_STATE=lista
}

fecha_lista_para_topo() {
  if [ "$P_LIST_STATE" = lista ]; then
    fecha_item
    P_LIST_STATE=depois
  fi
}

parse_manifesto() { # parse_manifesto <file> <tsv>
  local arq="$1" out="$2" linha n=0 fechado=0 k v
  [ -f "$arq" ] || falha "$E_CONTRATO" '00-PREDECESSORES.md ausente'
  P_TSV="$out"; P_PATHS="$out.paths"; : > "$P_TSV"; : > "$P_PATHS"
  P_TOP_SEEN=""; P_SCHEMA=""; P_TOOL=""; P_KIND=""; P_TRAB=""; P_CRIADO=""; P_ATUAL=""; P_N=0; P_LIST_STATE=antes; zera_item
  while IFS= read -r linha || [ -n "$linha" ]; do
    n=$((n + 1)); linha="${linha%$'\r'}"
    if [ "$n" -eq 1 ]; then [ "$linha" = '---' ] || falha "$E_CONTRATO" 'frontmatter precisa iniciar na primeira linha'; continue; fi
    if [ "$linha" = '---' ]; then fecha_item; fechado=1; break; fi
    case "$linha" in
      '  - caminho: '*)
        [ "$P_LIST_STATE" = lista ] || falha "$E_CONTRATO" 'item fora da secao predecessores'
        fecha_item; zera_item; I_OPEN=1; campo_item caminho "${linha#  - caminho: }" ;;
      '    origem: '*) campo_item origem "${linha#    origem: }" ;;
      '    papel: '*) campo_item papel "${linha#    papel: }" ;;
      '    commit_sha: '*) campo_item commit_sha "${linha#    commit_sha: }" ;;
      '    blob_oid: '*) campo_item blob_oid "${linha#    blob_oid: }" ;;
      predecessores:) abre_lista __LISTA__ ;;
      predecessores:\ \[\]) abre_lista __VAZIA__ ;;
      [a-z_]*': '*)
        fecha_lista_para_topo; k="${linha%%:*}"; v="${linha#*: }"; campo_topo "$k" "$v" ;;
      '') falha "$E_CONTRATO" 'linha vazia dentro do frontmatter' ;;
      *) falha "$E_CONTRATO" "linha malformada no frontmatter: $linha" ;;
    esac
  done < "$arq"
  [ "$fechado" -eq 1 ] || falha "$E_CONTRATO" 'frontmatter sem fechamento'
  for k in expx_schema expx_tool kind trabalho_id predecessores criado_em atualizado_em; do
    tem_palavra "$P_TOP_SEEN" "$k" || falha "$E_CONTRATO" "frontmatter sem chave: $k"
  done
  [ "$P_SCHEMA" = 1 ] || falha "$E_CONTRATO" 'expx_schema precisa ser 1'
  [ "$P_TOOL" = sprintx ] || falha "$E_CONTRATO" 'expx_tool precisa ser sprintx'
  [ "$P_KIND" = predecessores ] || falha "$E_CONTRATO" 'kind precisa ser predecessores'
  [ "$P_TRAB" = "$SLUG" ] || falha "$E_CONTRATO" 'trabalho_id diverge do slug'
  [ "$P_N" -gt 0 ] || falha "$E_CONTRATO" 'predecessores precisa ter ao menos um item'
  case "$P_CRIADO" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) falha "$E_CONTRATO" 'criado_em invalido' ;; esac
  case "$P_ATUAL" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) falha "$E_CONTRATO" 'atualizado_em invalido' ;; esac
  rm -f "$P_PATHS"
}

valida_tsv() {
  local caminho origem papel commit blob
  while IFS="	" read -r caminho origem papel commit blob; do
    [ -n "$caminho" ] || continue
    prova_item "$caminho" "$origem" "$papel" "$commit" "$blob"
  done < "$1"
}

valida_manifesto() {
  local t="$TMP_BASE/manifesto.tsv"
  parse_manifesto "$MANIFESTO" "$t"
  valida_tsv "$t"
  P_TSV_FINAL="$t"
}

renderiza() { # renderiza <tsv> <destino> <criado>
  local tsv="$1" dest="$2" criado="$3" caminho origem papel commit blob hoje
  hoje="$(date +%Y-%m-%d)"
  {
    printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: predecessores'
    printf 'trabalho_id: %s\npredecessores:\n' "$SLUG"
    while IFS="	" read -r caminho origem papel commit blob; do
      [ -n "$caminho" ] || continue
      printf '  - caminho: %s\n    origem: %s\n    papel: %s\n    commit_sha: %s\n    blob_oid: %s\n' "$caminho" "$origem" "$papel" "$commit" "$blob"
    done < "$tsv"
    printf 'criado_em: %s\natualizado_em: %s\n---\n\n# Predecessores — %s\n\n' "$criado" "$hoje" "$SLUG"
    printf 'Documentos consumidos antes do planejamento SprintX:\n\n'
    while IFS="	" read -r caminho origem papel commit blob; do
      [ -n "$caminho" ] || continue
      printf -- '- %s: `%s` (%s)\n' "$papel" "$caminho" "$origem"
    done < "$tsv"
  } > "$dest"
}

cmd_registrar() {
  [ "$#" -eq 6 ] || uso
  [ "$1" = --origem ] && [ "$2" = superpowers ] && [ "$3" = --papel ] && [ "$5" = --caminho ] || uso
  local origem="$2" papel="$4" caminho="$6" commit blob meta t novo criado existente=0
  valida_caminho "$caminho"
  case "$papel" in especificacao|plano) ;; *) falha "$E_CONTRATO" "papel fora do enum: $papel" ;; esac
  [ -f "$RAIZ/$caminho" ] && [ ! -L "$RAIZ/$caminho" ] || falha "$E_CONTRATO" "caminho nao e arquivo regular: $caminho"
  git -C "$RAIZ" ls-files --error-unmatch -- "$caminho" >/dev/null 2>&1 || falha "$E_CONTRATO" "arquivo nao rastreado: $caminho"
  git -C "$RAIZ" diff --quiet -- "$caminho" || falha "$E_CONTRATO" "arquivo modificado: $caminho"
  git -C "$RAIZ" diff --cached --quiet -- "$caminho" || falha "$E_CONTRATO" "arquivo staged: $caminho"
  commit="$(git -C "$RAIZ" log -1 --format=%H -- "$caminho")"; [ -n "$commit" ] || falha "$E_PROVA" "sem commit para $caminho"
  meta="$(modo_blob "$commit" "$caminho")" || falha "$E_PROVA" "predecessor nao e blob regular: $caminho"
  blob="${meta#*	}"
  prova_item "$caminho" "$origem" "$papel" "$commit" "$blob"

  t="$TMP_BASE/atuais.tsv"; : > "$t"; criado="$(date +%Y-%m-%d)"
  if [ -f "$MANIFESTO" ]; then
    valida_manifesto
    cp "$P_TSV_FINAL" "$t"
    criado="$P_CRIADO"
  fi
  while IFS="	" read -r I_CAM I_ORI I_PAP I_COM I_BLO; do
    [ "$I_CAM" = "$caminho" ] || continue
    existente=1
    [ "$I_ORI" = "$origem" ] && [ "$I_PAP" = "$papel" ] && [ "$I_COM" = "$commit" ] && [ "$I_BLO" = "$blob" ] \
      || falha "$E_CONTRATO" "caminho duplicado com prova diferente: $caminho"
  done < "$t"
  [ "$existente" -eq 0 ] || return 0

  printf '%s\t%s\t%s\t%s\t%s\n' "$caminho" "$origem" "$papel" "$commit" "$blob" >> "$t"
  novo="$TMP_BASE/novo.tsv"; LC_ALL=C sort -t "	" -k1,1 "$t" > "$novo"
  mkdir -p "$(dirname "$MANIFESTO")"
  TMP_ATOMICO="$(mktemp "$(dirname "$MANIFESTO")/.00-PREDECESSORES.md.tmp.XXXXXX")" || falha "$E_CONTRATO" 'nao consegui criar temporario'
  renderiza "$novo" "$TMP_ATOMICO" "$criado" || falha "$E_CONTRATO" 'nao consegui renderizar manifesto'
  parse_manifesto "$TMP_ATOMICO" "$TMP_BASE/confere.tsv"
  valida_tsv "$TMP_BASE/confere.tsv"
  chmod 0644 "$TMP_ATOMICO" || falha "$E_CONTRATO" 'nao consegui aplicar modo 0644'
  mv "$TMP_ATOMICO" "$MANIFESTO" || falha "$E_CONTRATO" 'nao consegui instalar manifesto'
  TMP_ATOMICO=""
  printf 'manifesto=%s\n' "$MANIFESTO_REL"
}

[ "$#" -ge 1 ] || uso
CMD="$1"; shift
case "$CMD" in
  --registrar)
    [ "$#" -ge 1 ] || uso; SLUG="$1"; shift; valida_slug "$SLUG" ;;
  --validar|--listar)
    [ "$#" -eq 1 ] || uso; SLUG="$1"; shift; valida_slug "$SLUG" ;;
  *) uso ;;
esac
RAIZ="$(resolve_raiz)"
MANIFESTO_REL="docs/sprintx/features/$SLUG/00-PREDECESSORES.md"
MANIFESTO="$RAIZ/$MANIFESTO_REL"
PLANEJAMENTO_REL="docs/sprintx/features/$SLUG/00-PLANEJAMENTO.md"
TMP_BASE="$(mktemp -d)" || falha "$E_CONTRATO" 'nao consegui criar temporario de leitura'
limpa() {
  local rc=$?
  trap - EXIT HUP INT TERM
  [ -z "$TMP_ATOMICO" ] || rm -f "$TMP_ATOMICO"
  rm -rf "$TMP_BASE"
  exit "$rc"
}
trap limpa EXIT HUP INT TERM

case "$CMD" in
  --registrar) cmd_registrar "$@" ;;
  --validar) valida_manifesto; printf 'resultado=ok\n' ;;
  --listar)
    valida_manifesto
    while IFS="	" read -r caminho origem papel commit blob; do
      [ -n "$caminho" ] && printf 'predecessor\t%s\t%s\t%s\n' "$caminho" "$commit" "$blob"
    done < "$P_TSV_FINAL"
    ;;
esac
