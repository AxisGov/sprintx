#!/usr/bin/env bash
# planejamento.sh — estado duravel do planejamento da sprintx.
#
# Dono de docs/sprintx/features/<slug>/00-PLANEJAMENTO.md (kind: planejamento):
# a maquina F3 <-> F5, o orcamento de reprovacoes da F5 declarado pelo caller,
# o estado terminal `orcamento_esgotado` e os checkpoints Git LOCAIS de metodo
# que tornam o planejamento duravel antes da F6.
#
# Tudo aqui e deterministico: nenhuma decisao depende do modelo lembrar de
# alguma coisa. Sem jq, sem python, sem rede. Bash 3.2 (macOS) compativel.
#
# Uso (a partir de qualquer diretorio do repositorio; SPRINTX_RAIZ sobrescreve a raiz):
#
#   planejamento.sh criar <slug> [max_reprovacoes_f5|null] [declarado_por|null]
#   planejamento.sh avanca <slug> f2|f3|f4|f5
#   planejamento.sh checkpoint <slug>
#   planejamento.sh fase <slug>
#   planejamento.sh valida-auditoria <slug>
#   planejamento.sh obrigacoes-f6 <slug>
#   planejamento.sh severidade ausente|criterio|teste
#   planejamento.sh revisor            (linhas do revisor-testes no stdin)
#
# Saida: linhas chave=valor no stdout; motivo de erro no stderr.
#
# Codigos de saida:
#   0  ok — inclusive no-op idempotente e checkpoint ignorado com aviso (sem Git,
#      branch que nao e feature/<slug>, pasta ignorada pelo versionador)
#   2  checkpoint recusado: ha path staged fora de docs/sprintx/features/<slug>/
#   3  persistencia_falhou: o commit do checkpoint foi rejeitado (hook do projeto)
#   4  contrato invalido (orcamento, arquivo, auditoria ou linha do revisor)
#   5  transicao invalida para o estado atual (inclui estado terminal)
#   64 uso incorreto

set -uo pipefail

SK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SK/assets/TEMPLATE-PLANEJAMENTO.md"

E_RECUSADO=2; E_PERSISTENCIA=3; E_CONTRATO=4; E_TRANSICAO=5; E_USO=64

falha() { local c="$1"; shift; printf 'planejamento: %s\n' "$*" >&2; exit "$c"; }

# ------------------------------------------------------------------ contexto

resolve_raiz() {
  if [ -n "${SPRINTX_RAIZ:-}" ]; then printf '%s' "$SPRINTX_RAIZ"; return; fi
  local t; t="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$t" ] && { printf '%s' "$t"; return; }
  printf '%s' "$PWD"
}

valida_slug() {
  printf '%s' "$1" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$' \
    || falha "$E_USO" "slug invalido: '$1' (a-z, 0-9 e hifen)"
}

contexto() { # contexto <slug>
  SLUG="$1"; valida_slug "$SLUG"
  RAIZ="$(resolve_raiz)"
  PREFIXO="docs/sprintx/features/$SLUG/"
  PASTA="$RAIZ/docs/sprintx/features/$SLUG"
  ARQ="$PASTA/00-PLANEJAMENTO.md"
  AUD="$PASTA/00-AUDITORIA.md"
}

hoje() { date +%Y-%m-%d; }

# ------------------------------------------------------------------ rastro

json_esc() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//	/\\t}"; s="${s//$'\r'/\\r}"; s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

# rastro <fase|-> <resultado> <detalhe> — contrato expx-eventos v1, append-only.
# Falha aberta: o rastro nunca derruba o planejamento.
rastro() {
  local fase="null" dir="$RAIZ/docs/eventos"
  [ "$1" != "-" ] && fase="\"$1\""
  {
    mkdir -p "$dir" || return 0
    printf '{"ts":"%s","expx_eventos":1,"trabalho_id":"%s","ferramenta":"sprintx","origem":"skill","evento":"checkpoint_planejamento","fase":%s,"task":null,"agente":"principal","resultado":"%s","detalhe":"%s","arquivos":["%s"]}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SLUG" "$fase" "$2" "$(json_esc "$3")" "${PREFIXO}00-PLANEJAMENTO.md" \
      >> "$dir/$SLUG.jsonl"
  } 2>/dev/null || true
  return 0
}

# ------------------------------------------------------------------ orcamento

valida_orcamento() { # valida_orcamento <max> <declarado_por>
  local max="$1" por="$2"
  case "$max" in
    null) ;;
    *) printf '%s' "$max" | grep -Eq '^[1-9][0-9]*$' \
         || falha "$E_CONTRATO" "max_reprovacoes_f5 invalido: '$max' (inteiro >= 1 ou null)" ;;
  esac
  case "$por" in
    null) ;;
    *) printf '%s' "$por" | grep -Eq '^[a-z][a-z0-9_-]*$' \
         || falha "$E_CONTRATO" "orcamento_declarado_por invalido: '$por' (identificador minusculo ou null)" ;;
  esac
  if [ "$max" = null ] && [ "$por" != null ]; then
    falha "$E_CONTRATO" "orcamento_declarado_por sem max_reprovacoes_f5: quem declara orcamento declara o teto"
  fi
  if [ "$max" != null ] && [ "$por" = null ]; then
    falha "$E_CONTRATO" "max_reprovacoes_f5 sem orcamento_declarado_por: o teto precisa de dono"
  fi
}

# ------------------------------------------------------------------ leitura

fm_valor() { # fm_valor <arquivo> <chave> — escalar de topo do primeiro bloco YAML
  tr -d '\r' < "$1" | awk -v k="$2" '
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v); print v; exit }'
}

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

inteiro() { printf '%s' "$1" | grep -Eq '^(0|[1-9][0-9]*)$'; }

# le_planejamento — carrega e valida o arquivo inteiro. Arquivo que nao passa
# aqui e contrato invalido: nada e decidido em cima dele.
le_planejamento() {
  [ -f "$ARQ" ] || falha "$E_CONTRATO" "${PREFIXO}00-PLANEJAMENTO.md nao existe"
  [ "$(fm_valor "$ARQ" expx_schema)" = 1 ] || falha "$E_CONTRATO" "expx_schema deve ser 1"
  [ "$(fm_valor "$ARQ" expx_tool)" = sprintx ] || falha "$E_CONTRATO" "expx_tool deve ser sprintx"
  [ "$(fm_valor "$ARQ" kind)" = planejamento ] || falha "$E_CONTRATO" "kind deve ser planejamento"
  [ "$(fm_valor "$ARQ" trabalho_id)" = "$SLUG" ] || falha "$E_CONTRATO" "trabalho_id nao e $SLUG"

  P_MAX="$(fm_valor "$ARQ" max_reprovacoes_f5)"
  P_POR="$(fm_valor "$ARQ" orcamento_declarado_por)"
  P_ESTADO="$(fm_valor "$ARQ" estado)"
  P_REPROV="$(fm_valor "$ARQ" reprovacoes)"
  valida_orcamento "$P_MAX" "$P_POR"
  case "$P_ESTADO" in
    null|aguardando_f3|aguardando_f4|aguardando_f5|replanejar|aprovado|orcamento_esgotado) ;;
    *) falha "$E_CONTRATO" "estado fora do enum: '$P_ESTADO'" ;;
  esac
  inteiro "$P_REPROV" || falha "$E_CONTRATO" "reprovacoes invalido: '$P_REPROV'"

  P_HIST="$(hist_tsv "$ARQ")"
  P_RODADAS=0
  local nao=0 ultimo="" linha r v a m b d
  if [ -n "$P_HIST" ]; then
    while IFS="$(printf '\t')" read -r r v a m b d; do
      [ "$r" != LIXO ] || falha "$E_CONTRATO" "linha inesperada em historico: $v"
      P_RODADAS=$((P_RODADAS + 1))
      [ "$r" = "$P_RODADAS" ] || falha "$E_CONTRATO" "historico fora de sequencia: rodada $r na posicao $P_RODADAS"
      case "$v" in sim|nao) ;; *) falha "$E_CONTRATO" "veredito invalido na rodada $r: '$v'" ;; esac
      [ "$ultimo" != sim ] || falha "$E_CONTRATO" "rodada $r depois de um veredito sim"
      for linha in "$a" "$m" "$b"; do inteiro "$linha" || falha "$E_CONTRATO" "contagem invalida na rodada $r"; done
      printf '%s' "$d" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || falha "$E_CONTRATO" "auditado_em invalido na rodada $r"
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
  case "$ultimo:$P_ESTADO" in
    sim:aprovado) ;;
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

# ------------------------------------------------------------------ escrita

# escreve <max> <por> <estado> <reprovacoes> <historico_tsv> — o arquivo inteiro,
# a partir do template, de forma atomica. O historico recebido ja inclui as
# rodadas anteriores intactas: e assim que ele continua append-only.
escreve() {
  local max="$1" por="$2" estado="$3" reprov="$4" hist="$5" data tmp yaml prosa teto
  [ -f "$TEMPLATE" ] || falha "$E_CONTRATO" "template ausente: assets/TEMPLATE-PLANEJAMENTO.md"
  data="$(hoje)"

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

  mkdir -p "$PASTA" || falha "$E_CONTRATO" "nao foi possivel criar $PREFIXO"
  tmp="$ARQ.tmp.$$"
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: planejamento\ntrabalho_id: %s\n' "$SLUG"
    printf 'max_reprovacoes_f5: %s\norcamento_declarado_por: %s\nestado: %s\nreprovacoes: %s\natualizado_em: %s\n' \
      "$max" "$por" "$estado" "$reprov" "$data"
    printf '%s\n---\n' "$yaml"
    # Texto com quebra de linha vai por ENVIRON, nunca por `awk -v`: o awk do
    # BSD recusa newline numa atribuicao -v.
    tr -d '\r' < "$TEMPLATE" | SX_SLUG="$SLUG" SX_BLOCO="Estado: \`$estado\` · reprovações da F5: $teto · atualizado em $data.

$prosa" awk '
      NR == 1 { next }
      !corpo { if ($0 == "---") corpo = 1; next }
      /^<!-- sprintx:estado -->$/ { print; print ENVIRON["SX_BLOCO"]; pula = 1; next }
      /^<!-- \/sprintx:estado -->$/ { pula = 0; print; next }
      pula { next }
      /^<!--$/ { exit }
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
migra_legado() { # migra_legado [max] [por] — sem argumentos, sem teto
  local max="${1:-null}" por="${2:-null}" estado="$E_ESTADO" v altas medias baixas reprov=0 hist=""
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
    orcamento_esgotado) printf 'PARAR' ;;
  esac
}

# fase e rodada do ultimo marco, derivados so do arquivo: e o que vai no commit.
marco() {
  case "$P_ESTADO" in
    aguardando_f3) M_FASE=f2; M_RODADA=0 ;;
    aguardando_f4) M_FASE=f3; M_RODADA=0 ;;
    aguardando_f5) M_FASE=f4; M_RODADA=0 ;;
    replanejar|aprovado|orcamento_esgotado) M_FASE=f5; M_RODADA="$P_RODADAS" ;;
    *) M_FASE=""; M_RODADA=0 ;;
  esac
}

# ------------------------------------------------------------------ checkpoint

# checkpoint — commit LOCAL, na branch feature/<slug>, so da pasta da feature.
# Nunca push, nunca --no-verify, nunca limpa, descarta ou stasha nada.
checkpoint() {
  le_planejamento; marco
  [ -n "$M_FASE" ] || falha "$E_TRANSICAO" "estado $P_ESTADO ainda nao tem marco de checkpoint (a F2 nao terminou)"

  if ! git -C "$RAIZ" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'checkpoint=ignorado_sem_git\n'
    rastro "$M_FASE" aviso "checkpoint ignorado: sem Git; estado $P_ESTADO so no disco"
    return 0
  fi
  if [ -n "$(git -C "$RAIZ" rev-parse --show-prefix 2>/dev/null)" ]; then
    printf 'checkpoint=ignorado_raiz\n'
    rastro "$M_FASE" aviso "checkpoint ignorado: raiz da sprintx nao e a raiz do repositorio"
    return 0
  fi
  local branch
  branch="$(git -C "$RAIZ" symbolic-ref --short -q HEAD 2>/dev/null)" || branch=""
  if [ "$branch" != "feature/$SLUG" ]; then
    printf 'checkpoint=ignorado_branch\nbranch=%s\n' "${branch:-HEAD destacado}"
    rastro "$M_FASE" aviso "checkpoint ignorado: branch '${branch:-HEAD destacado}' nao e feature/$SLUG; estado $P_ESTADO so no disco"
    return 0
  fi
  if git -C "$RAIZ" check-ignore -q "${PREFIXO}00-PLANEJAMENTO.md" 2>/dev/null; then
    printf 'checkpoint=ignorado_pasta_ignorada\n'
    rastro "$M_FASE" aviso "checkpoint ignorado: $PREFIXO e ignorada pelo versionador do projeto"
    return 0
  fi

  guarda_staged "antes de preparar"
  git -C "$RAIZ" add -A -- "$PREFIXO" 2>/dev/null \
    || { printf 'checkpoint=persistencia_falhou\n'; rastro "$M_FASE" falha "persistencia_falhou: git add da pasta da feature falhou"; exit "$E_PERSISTENCIA"; }
  guarda_staged "depois de preparar"

  if git -C "$RAIZ" diff --cached --quiet 2>/dev/null; then
    printf 'checkpoint=sem_mudanca\nfase=%s\nrodada=%s\nestado=%s\n' "$M_FASE" "$M_RODADA" "$P_ESTADO"
    rastro "$M_FASE" ok "sem_mudanca: HEAD ja representa o estado $P_ESTADO"
    return 0
  fi

  local rotulo="$M_FASE" saida
  [ "$M_FASE" = f5 ] && rotulo="f5 rodada $M_RODADA"
  if ! saida="$(git -C "$RAIZ" commit -q \
        -m "chore(sprintx): checkpoint de planejamento $SLUG — $rotulo" \
        -m "Planejamento: checkpoint
Trabalho: $SLUG
Fase: $M_FASE
Rodada: $M_RODADA
Estado: $P_ESTADO" 2>&1)"; then
    printf 'checkpoint=persistencia_falhou\n'
    rastro "$M_FASE" falha "persistencia_falhou: o commit do checkpoint foi rejeitado — $(printf '%s' "$saida" | tr '\n' ' ' | cut -c1-200)"
    printf 'planejamento: persistencia_falhou — commit rejeitado; nada foi limpo nem descartado. PARE.\n%s\n' "$saida" >&2
    exit "$E_PERSISTENCIA"
  fi
  printf 'checkpoint=commitado\ncommit=%s\nfase=%s\nrodada=%s\nestado=%s\n' \
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
  [ $# -ge 1 ] && [ $# -le 3 ] || falha "$E_USO" "uso: criar <slug> [max_reprovacoes_f5|null] [declarado_por|null]"
  contexto "$1"
  local max="${2:-null}" por="${3:-null}"
  valida_orcamento "$max" "$por"
  if [ -f "$ARQ" ]; then
    le_planejamento
    if [ "$P_MAX" != "$max" ] || [ "$P_POR" != "$por" ]; then
      falha "$E_CONTRATO" "00-PLANEJAMENTO.md ja registra orcamento $P_MAX/$P_POR; o pedido traz $max/$por — orcamento nao muda em silencio"
    fi
    printf 'planejamento=ja_existe\nestado=%s\n' "$P_ESTADO"
    return 0
  fi
  estado_efetivo
  if [ "$E_ESTADO" != null ]; then
    # Feature legada ja adiantada: nasce com o estado que o disco mostra, e com
    # o orcamento que o caller declarou agora.
    migra_legado "$max" "$por"
    le_planejamento
    printf 'planejamento=migrado_legado\nmax_reprovacoes_f5=%s\norcamento_declarado_por=%s\nestado=%s\n' "$max" "$por" "$P_ESTADO"
    return 0
  fi
  escreve "$max" "$por" null 0 ""
  printf 'planejamento=criado\nmax_reprovacoes_f5=%s\norcamento_declarado_por=%s\nestado=null\n' "$max" "$por"
}

cmd_avanca() {
  [ $# -eq 2 ] || falha "$E_USO" "uso: avanca <slug> f2|f3|f4|f5"
  contexto "$1"
  local alvo="$2" novo
  estado_efetivo
  case "$alvo:$E_ESTADO" in
    f2:null|f2:aguardando_f3) novo=aguardando_f3 ;;
    f3:aguardando_f3|f3:replanejar|f3:aguardando_f4|f3:aguardando_f5) novo=aguardando_f4 ;;
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

  if [ "$alvo" = f5 ]; then
    valida_auditoria
    local rodada=$((P_RODADAS + 1)) reprov="$P_REPROV" hist
    if [ "$A_VEREDITO" = sim ]; then novo=aprovado
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
  printf 'fase=%s\nestado=%s\nfonte=%s\n' "$(fase_do_estado "$E_ESTADO")" "$E_ESTADO" "$E_FONTE"
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

[ $# -ge 1 ] || { sed -n '14,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "$E_USO"; }
CMD="$1"; shift
case "$CMD" in
  criar)            cmd_criar "$@" ;;
  avanca)           cmd_avanca "$@" ;;
  checkpoint)       cmd_checkpoint "$@" ;;
  fase)             cmd_fase "$@" ;;
  valida-auditoria) cmd_valida_auditoria "$@" ;;
  obrigacoes-f6)    cmd_obrigacoes_f6 "$@" ;;
  severidade)       cmd_severidade "$@" ;;
  revisor)          cmd_revisor "$@" ;;
  *) falha "$E_USO" "comando desconhecido: $CMD" ;;
esac
