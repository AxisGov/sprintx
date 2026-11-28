#!/usr/bin/env bash
# task-so-fecha-verde — PreToolUse em escrita no tasks.md.
#
# `parcial` = rodou o subconjunto de testes afetado pela task e passou. E o
# estado normal de uma task fechada na F6: a suite inteira e cobrada uma vez, ao
# fechar a sprint. Barrar `parcial` aqui barraria toda conclusao de task — e hook
# que da falso positivo e desinstalado, levando junto os que funcionavam.
#
# A regra central do metodo: task so fecha verde. Hoje ela depende do modelo
# lembrar dela na hora de editar o proprio arquivo de estado.
#
# Barra a mudanca de status para `concluida` quando:
#   - `suite` nao for `verde` nem `parcial`, ou
#   - `suite` for `vermelha` e `suite_falhas` estiver ausente, vazia ou tiver um
#     arquivo fora de .expx/falhas-de-ambiente.tsv para a plataforma desta maquina
#     (DS-238: vermelha so por ambiente fecha a task; DS-239: item entre aspas guarda
#     a virgula, e aspa sem par invalida a lista), ou
#   - `teste_integracao` ou `teste_funcional` estiverem vazios, ou
#   - em `revisao_por_task.modo: obrigatoria`, faltar a evidencia da revisao por
#     task da task que ESTA escrita leva a `concluida` (DS-207).
#
# Modo: nasce em `aviso`.
#
# Mecanica: le o conteudo QUE VAI SER GRAVADO (tool_input.content para Write,
# new_string para Edit), nao o arquivo em disco — o objetivo e barrar ANTES.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../comum/rastro.sh
. "$DIR/../comum/rastro.sh"

ENTRADA="$(cat)"
CWD="$(rastro_json_get "$ENTRADA" cwd)"
[ -n "$CWD" ] || CWD="$PWD"
# Caminho do payload (no Windows, C:\dir com caixa de drive variavel) sempre pelo helper.
rastro_caminho_em CWD "$CWD"
RAIZ="$(rastro_raiz "$CWD")"

ALVO="$(rastro_tool_input_get "$ENTRADA" file_path)"
rastro_caminho_em ALVO "$ALVO"
case "$ALVO" in
  */tasks.md) ;;
  *) exit 0 ;;
esac

# O texto que esta sendo escrito. Write traz `content`; Edit traz `new_string`.
NOVO="$(rastro_tool_input_get "$ENTRADA" content)"
[ -n "$NOVO" ] || NOVO="$(rastro_tool_input_get "$ENTRADA" new_string)"
[ -n "$NOVO" ] || exit 0

# Nada virando `concluida` nesta gravacao => nada a verificar.
# Sem `printf | grep -q`: sob pipefail, o printf levava SIGPIPE e a regra
# era pulada. O espaco depois de `status:` e o mesmo que o awk abaixo aceita: com `status:  concluida`
# (dois espacos) a regra tambem era pulada (CodeAnt no sprintx#57).
# com ou sem aspas: `status: "concluida"` e YAML valido (conselhos#298)
RE_CONCLUIDA=$'status:[ \t]*["\']?concluida'
[[ $NOVO =~ $RE_CONCLUIDA ]] || exit 0

# ---------------------------------------- falhas so de ambiente (DS-238)
# Suite vermelha fecha a task quando `suite_falhas` lista os arquivos de teste que
# falharam e TODOS estao em .expx/falhas-de-ambiente.tsv para a plataforma desta
# maquina. Linha: `caminho<TAB>plataforma<TAB>motivo<TAB>desde`; `#` comenta, motivo
# vazio invalida a linha, o caminho casa exato. A plataforma e EXPX_PLATAFORMA, senao
# a do `uname -s`. E a mesma regra do portao-v2.sh da mergex; a conferencia de que
# nenhum desses arquivos esta no diff fica la (V2 e E1), nao aqui.
PLATAFORMA="${EXPX_PLATAFORMA:-}"
if [ -z "$PLATAFORMA" ]; then
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) PLATAFORMA=win32 ;;
    Linux) PLATAFORMA=linux ;;
    Darwin) PLATAFORMA=darwin ;;
  esac
fi
AMBIENTE=""
LISTA_AMBIENTE="$RAIZ/.expx/falhas-de-ambiente.tsv"
if [ -n "$PLATAFORMA" ] && [ -f "$LISTA_AMBIENTE" ]; then
  TAB=$'\t'
  # `IFS=$'\t' read` juntaria dois tabs seguidos e o motivo vazio pularia de coluna:
  # as colunas saem por expansao. A ultima linha sem quebra final tambem conta.
  while IFS= read -r l || [ -n "$l" ]; do
    l="${l%$'\r'}"
    case "$l" in ''|'#'*) continue ;; esac
    c="${l%%"$TAB"*}"; r="${l#*"$TAB"}"; [ "$r" != "$l" ] || continue
    p="${r%%"$TAB"*}"; m="${r#*"$TAB"}"; [ "$m" != "$r" ] || continue
    m="${m%%"$TAB"*}"
    # Motivo so de espacos e motivo vazio: a V2 e o nucleo tambem os recusam.
    [ -n "$c" ] && [ "$p" = "$PLATAFORMA" ] && [ -n "${m//[[:space:]]/}" ] || continue
    AMBIENTE="$AMBIENTE$c
"
  done < "$LISTA_AMBIENTE"
fi

# ------------------------------------------------------ achar as violacoes
# Percorre os blocos de task do texto novo; para cada um que esta `concluida`,
# confere suite verde e os dois testes preenchidos.
PROBLEMAS="$(printf '%s' "$NOVO" | SX_AMB="$AMBIENTE" awk '
  # escalar em bloco (`chave: |` ou `>`): as linhas mais indentadas que a chave sao texto,
  # nunca chaves (DS-212; o `_parse` da runx faz o mesmo, DR-112)
  BEGIN { bs = -1; sfb = -1 }
  # os arquivos que a lista de ambiente aceita nesta plataforma (DS-238)
  BEGIN { na = split(ENVIRON["SX_AMB"], aa, "\n"); for (i = 1; i <= na; i++) if (aa[i] != "") AMB[aa[i]] = 1 }
  # CRLF sai, e o tab indenta 4, como no `_parse` da runx (conselhos#298)
  { sub(/\r$/, ""); gsub(/\t/, "    ") }
  { ind0 = match($0, /[^ \t]/) - 1 }
  bs >= 0 && ($0 ~ /^[ \t]*$/ || ind0 > bs) { next }
  { bs = -1 }
  # item sem aspas: aspa no meio e literal, mas aspa solta no fim e par sem abertura e invalida a lista
  function falha(c) { gsub(/^[ \t]+|[ \t]+$/, "", c); if (c ~ /["\047]$/) { sfi = 1; return }; if (c != "") FL[++nf] = c }
  # item entre aspas, duplas ou simples (DS-239): o texto vai ate a aspa igual seguinte, com a virgula
  # e o `#` de dentro, e as aspas saem. Sem a aspa de fechamento, ou com texto colado depois dela, a
  # lista e invalida (sfi). Devolve a posicao logo depois da aspa de fechamento, ou 0. So POSIX (mawk).
  function aspas(v, i,   ch, j, it) {
    ch = substr(v, i, 1); j = index(substr(v, i + 1), ch)
    if (!j) { sfi = 1; return 0 }
    it = substr(v, i + 1, j - 1)
    # escape dentro das aspas duplas nao e lido: a lista fica invalida em vez de ser lida pela metade
    if (ch == "\"" && it ~ /\\$/) { sfi = 1; return 0 }
    if (it != "") FL[++nf] = it
    return i + j + 1
  }
  # `suite_falhas: [a, "b,c", \047d\047]`: v e o texto depois do `[`. Fora das aspas, a virgula separa,
  # o `]` fecha e o `#` depois de espaco comenta o resto da linha
  function fluxo(v,   n, i, k, ch, it) {
    n = length(v); i = 1
    while (i <= n) {
      while (i <= n && substr(v, i, 1) ~ /[ \t]/) i++
      ch = substr(v, i, 1)
      if (ch == "\"" || ch == "\047") {
        if (!(i = aspas(v, i))) return
        k = i; while (i <= n && substr(v, i, 1) ~ /[ \t]/) i++
        ch = substr(v, i, 1)
        if (i <= n && ch != "," && ch != "]" && !(ch == "#" && i > k)) { sfi = 1; return }
      } else {
        it = ""
        while (i <= n && (ch = substr(v, i, 1)) != "," && ch != "]") {
          if (ch == "#" && it ~ /[ \t]$/) break
          it = it ch; i++
        }
        falha(it)
      }
      # so o `]` fecha a lista; sem ele, a lista e invalida
      if (i > n || ch != ",") { if (i > n || ch != "]") sfi = 1; return }
      i++
    }
    sfi = 1
  }
  # item da lista em bloco: entre aspas sai como no fluxo, e depois da aspa so cabe espaco e comentario
  function bloco(v,   i, ch) {
    ch = substr(v, 1, 1)
    if (ch == "\"" || ch == "\047") {
      if ((i = aspas(v, 1)) && substr(v, i) !~ /^([ \t]+(#.*)?)?$/) sfi = 1
    } else { sub(/[ \t]+#.*$/, "", v); falha(v) }
  }
  function fecha(  msg, i, fora) {
    if (id != "" && concluida) {
      msg = ""
      if (suite == "vermelha") {
        if (sfi) msg = msg " suite=vermelha com suite_falhas invalida (aspas sem par ou texto depois da aspa)"
        else if (nf == 0) msg = msg " suite=vermelha sem suite_falhas"
        else {
          fora = ""
          for (i = 1; i <= nf; i++) if (!(FL[i] in AMB)) fora = fora (fora == "" ? "" : ",") FL[i]
          if (fora != "") msg = msg " suite=vermelha com falha fora da lista de ambiente (" fora ")"
        }
      } else if (suite != "verde" && suite != "parcial") msg = msg " suite=" (suite == "" ? "ausente" : suite)
      if (ti == 0)            msg = msg " teste_integracao vazio"
      if (tf == 0)            msg = msg " teste_funcional vazio"
      if (msg != "") print id ":" msg
    }
    id=""; concluida=0; suite=""; ti=0; tf=0; nf=0; sfb=-1; sfi=0
  }
  # item da lista em bloco de `suite_falhas` (`- tests/a.test.ts`); item de mapa (`- id:`) a encerra
  sfb >= 0 && ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*#/) { next }
  sfb >= 0 && ind0 >= sfb && /^[ \t]*-[ \t]+/ && !/^[ \t]*-[ \t]*[A-Za-z_][A-Za-z0-9_]*:/ { v = $0; sub(/^[ \t]*-[ \t]+/, "", v); bloco(v); next }
  { sfb = -1 }
  /^[ \t]*-[ \t]*id:/ { fecha(); id=$3; sub(/^[ \t]+/,"",id) }
  /^[ \t]*(-[ \t]+)?status:[ \t]*(concluida|"concluida"|\047concluida\047)[ \t]*(#.*)?$/ { concluida=1 }
  /suite:/                      { s=$0; sub(/.*suite:[ \t]*/,"",s); sub(/[ \t]+$/,"",s); suite=s }
  # `suite_falhas: [a, b]` em fluxo, ou `suite_falhas:` com a lista em bloco nas linhas seguintes
  # (no fluxo, o comentario sai dentro do `fluxo`, que sabe o que esta entre aspas: DS-239)
  /^[ \t]*suite_falhas:/ { v = $0; sub(/^[ \t]*suite_falhas:[ \t]*/, "", v)
    if (v ~ /^\[/) fluxo(substr(v, 2))
    else { sub(/[ \t]+#.*$/, "", v); if (v == "") sfb = ind0 } }
  /teste_integracao:/           { v=$0; sub(/.*teste_integracao:[ \t]*/,"",v); gsub(/[ \t"'"'"']/,"",v); if (v != "" && v != "null") ti=1 }
  /teste_funcional:/            { v=$0; sub(/.*teste_funcional:[ \t]*/,"",v);  gsub(/[ \t"'"'"']/,"",v); if (v != "" && v != "null") tf=1 }
  # comentario nunca abre escalar: nem a linha inteira (`# nota: |`, regressao da DS-212; conselhos#298)
  # nem o fim de uma linha de chave (`tasks: # nota: |`; login#77): o indicador vem antes do comentario,
  # e o texto entre aspas sai antes (o `#` e o `|` dentro dele nao contam; a dupla com `\"` escapado inteira)
  $0 !~ /^[ \t]*#/ { sc = $0; gsub(/"([^"\\]|\\.)*"/, "\"\"", sc); gsub(/\047[^\047]*\047/, "\047\047", sc); sub(/[ \t]#.*$/, "", sc)
    if (sc ~ /:[ \t]*[|>][+-]?[1-9]?[+-]?[ \t]*$/) bs = ($0 ~ /^[ \t]*-[ \t]/) ? ind0 + 2 : ind0 }
  END { fecha() }
')"

# ------------------------------------- a evidencia da revisao por task (DS-207)
# Desenho de 2026-10-18, 4.2: em `obrigatoria`, a task que ESTA escrita leva a
# `concluida` precisa de docs/entregas/<slug>/revisao/<T>.json, arquivo comum.
# So a transicao: o antes e o `old_string` do Edit, ou o tasks.md do disco no
# Write. O modo vem do leitor do nucleo; sem ele, sem node, com ele falhando ou
# com a linha fora da forma, o modo e desconhecido e nada e exigido (a F6 ja
# bloqueia com `prerequisito_ausente`, e o aviso seria falso).
# Um item `- <chave>:` no nivel de um `- id:` ja visto e outra task, sem id: ela vira `?`,
# que nao e id, e avisa em obrigatoria, em vez de se fundir a task de cima.
concluidas() { awk '
  function fecha() { if (id != "" && c) print id; id=""; c=0 }
  # escalar em bloco (`chave: |` ou `>`): as linhas mais indentadas que a chave sao texto,
  # nunca chaves (DS-212; o `_parse` da runx faz o mesmo, DR-112)
  BEGIN { bs = -1 }
  # CRLF sai, e o tab indenta 4, como no `_parse` da runx (conselhos#298)
  { sub(/\r$/, ""); gsub(/\t/, "    ") }
  { ind0 = match($0, /[^ \t]/) - 1 }
  bs >= 0 && ($0 ~ /^[ \t]*$/ || ind0 > bs) { next }
  { bs = -1 }
  # o id como o YAML o le: sem as aspas de um par das pontas e sem o comentario; vazio vira `?`
  /^[ \t]*-[ \t]*id:/ { fecha(); v = $0; sub(/^[ \t]*-[ \t]*id:[ \t]*/, "", v)
    if (v ~ /^"/) { v = substr(v, 2); q = index(v, "\""); id = q ? substr(v, 1, q - 1) : "" }
    else if (v ~ /^\047/) { v = substr(v, 2); q = index(v, "\047"); id = q ? substr(v, 1, q - 1) : "" }
    else { id = v; sub(/[ \t].*/, "", id); if (id ~ /^#/) id = "" }
    if (id == "") id = "?"
    ind = match($0, /-/) }
  ind && /^[ \t]*-[ \t]+[A-Za-z_][A-Za-z0-9_]*:/ && !/^[ \t]*-[ \t]*id:/ && match($0, /-/) == ind { fecha(); id = "?" }
  # so a chave `status`, nunca o texto de outro campo (uma nota) que a cite (conselhos#296)
  /^[ \t]*(-[ \t]+)?status:[ \t]*(concluida|"concluida"|\047concluida\047)[ \t]*(#.*)?$/ { c=1 }
  # comentario nunca abre escalar: nem a linha inteira (`# nota: |`, regressao da DS-212; conselhos#298)
  # nem o fim de uma linha de chave (`tasks: # nota: |`; login#77): o indicador vem antes do comentario,
  # e o texto entre aspas sai antes (o `#` e o `|` dentro dele nao contam; a dupla com `\"` escapado inteira)
  $0 !~ /^[ \t]*#/ { sc = $0; gsub(/"([^"\\]|\\.)*"/, "\"\"", sc); gsub(/\047[^\047]*\047/, "\047\047", sc); sub(/[ \t]#.*$/, "", sc)
    if (sc ~ /:[ \t]*[|>][+-]?[1-9]?[+-]?[ \t]*$/) bs = ($0 ~ /^[ \t]*-[ \t]/) ? ind0 + 2 : ind0 }
  END { fecha() }'; }
SEM_EVIDENCIA=""
REL_TASKS="${ALVO#"$RAIZ"/}"
case "$REL_TASKS" in
  docs/sprintx/features/*/sprint-*/tasks.md) SLUG="${REL_TASKS#docs/sprintx/features/}"; SLUG="${SLUG%%/*}" ;;
  *) SLUG="" ;;
esac
NOVAS=""; FORA_DA_FORMA=""
if [ -n "$SLUG" ]; then
  if [ -n "$(rastro_tool_input_get "$ENTRADA" content)" ]; then
    ANTES="$( { [ -f "$RAIZ/$REL_TASKS" ] && concluidas < "$RAIZ/$REL_TASKS"; } 2>/dev/null)"
  else
    ANTES="$(rastro_tool_input_get "$ENTRADA" old_string | concluidas)"
  fi
  RE_ID='^T-([0-9]+|[0-9]{2}\.[0-9]{2})$'
  while IFS= read -r t; do
    # `?` (sem id) nunca e "ja concluida": duas tasks sem id teriam o mesmo marcador (CodeAnt no sprintx#73)
    if [ "$t" != "?" ]; then case $'\n'"$ANTES"$'\n' in *$'\n'"$t"$'\n'*) continue ;; esac; fi
    # id fora da forma nao vira caminho, e a evidencia nao pode ser conferida: avisa em obrigatoria
    if [[ $t =~ $RE_ID ]]; then NOVAS="$NOVAS $t"; else FORA_DA_FORMA="$FORA_DA_FORMA $t"; fi
  done <<EOF
$(printf '%s\n' "$NOVO" | concluidas)
EOF
fi
LEITOR="$RAIZ/.expx/marketplace/plugins/expx/nucleo/scripts/expx-fatiamento.mjs"
if [ -n "$NOVAS$FORA_DA_FORMA" ] && [ -f "$LEITOR" ] && command -v node >/dev/null 2>&1; then
  MODO_REVISAO=""
  if SAIDA_LEITOR="$(node "$LEITOR" --formato env --raiz "$RAIZ" 2>/dev/null)"; then
    while IFS= read -r l; do
      case "$l" in EXPX_REVISAO_POR_TASK=*) MODO_REVISAO="${l#EXPX_REVISAO_POR_TASK=}" ;; esac
    done <<EOF
$SAIDA_LEITOR
EOF
  fi
  if [ "$MODO_REVISAO" = obrigatoria ]; then
    for t in $FORA_DA_FORMA; do
      SEM_EVIDENCIA=1
      PROBLEMAS="${PROBLEMAS:+$PROBLEMAS
}$t: id fora da forma T-NN.MM, a evidencia da revisao por task nao pode ser conferida"
    done
    # link em qualquer ponto do caminho nao vale: a pasta `revisao` linkada para fora da worktree (conselhos#296)
    LINK_NO_CAMINHO=""
    for p in docs docs/entregas "docs/entregas/$SLUG" "docs/entregas/$SLUG/revisao"; do
      [ ! -L "$RAIZ/$p" ] || LINK_NO_CAMINHO=1
    done
    for t in $NOVAS; do
      EV="$RAIZ/docs/entregas/$SLUG/revisao/$t.json"
      if [ -n "$LINK_NO_CAMINHO" ] || [ ! -f "$EV" ] || [ -L "$EV" ]; then
        SEM_EVIDENCIA=1
        PROBLEMAS="${PROBLEMAS:+$PROBLEMAS
}$t: sem evidencia da revisao por task (docs/entregas/$SLUG/revisao/$t.json) em modo obrigatoria"
      fi
    done
  fi
fi

[ -n "$PROBLEMAS" ] || exit 0

RESUMO="$(printf '%s' "$PROBLEMAS" | tr '\n' ';')"
MSG="sprintx/task-so-fecha-verde: task nao pode ir para concluida assim -> $RESUMO. A regra do metodo e: task so e concluida quando o teste de integracao E o teste funcional passam. Nao existe concluido com ressalva. Rode os testes ate passarem — o subconjunto afetado pela task basta, e grava suite: parcial — ou marque a task como bloqueada e registre em 00-BLOQUEIOS.md."
[ -z "$SEM_EVIDENCIA" ] || MSG="$MSG Sem a evidencia da revisao por task, rode o passo de revisao da F6 (references/06-execucao.md) antes de concluir: em obrigatoria, a task nao fecha sem ela."
case "$PROBLEMAS" in
  *suite=vermelha*) MSG="$MSG Suite vermelha so por ambiente fecha a task (DS-238): grave em suite_falhas os arquivos de teste que falharam, e cada um precisa estar em .expx/falhas-de-ambiente.tsv para a plataforma ${PLATAFORMA:-desconhecida}. Timeout por maquina carregada nao entra na lista: rode o arquivo sozinho e grave a execucao verde (suite: parcial)." ;;
esac

MODO="$(rastro_modo "$RAIZ" task-so-fecha-verde metodo)"
REL="${ALVO#"$RAIZ"/}"

# Desligado nao roda e nao registra: quem desligou nao quer nem o aviso.
[ "$MODO" = "desligado" ] && exit 0

if [ "$MODO" = "bloqueio" ]; then
  rastro_grava "$RAIZ" acao_bloqueada hook bloqueado "fechamento invalido: $RESUMO" "[\"$(rastro_json_escape "$REL")\"]"
  rastro_bloqueia "$MSG"
fi

rastro_grava "$RAIZ" regra_violada hook aviso "fechamento invalido: $RESUMO" "[\"$(rastro_json_escape "$REL")\"]"
rastro_aviso_ao_modelo PreToolUse "$MSG"
