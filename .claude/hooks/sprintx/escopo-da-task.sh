#!/usr/bin/env bash
# escopo-da-task — PreToolUse em ferramentas de escrita.
#
# "Nao toque no que nao esta na task" — a regra que se dissolve na task 14 de
# uma execucao autonoma. Aqui ela vira mecanica.
#
# Resolve, pelo rastro, o par TRABALHO + TASK desta sessao; le o plano SO
# desse trabalho e compara o arquivo sendo editado com o campo `arquivos` da
# task corrente. Fora da lista -> aviso (e, depois de promovido, bloqueio).
#
# Ids de task (T-01.01) sao locais a feature e se repetem entre features:
# nenhuma busca global por id decide escopo. Plano de outra feature nunca
# participa, nem como fallback. Ver DS-153/DS-154.
#
# Excecao normativa: arquivo_de_task_irma. Se o arquivo nao esta na task
# corrente mas esta em outra task da mesma feature, o dono e inequivoco —
# bloqueia sempre, mesmo com o hook em modo aviso. Ver DS-149 em
# DECISOES-DA-SKILL.md.
#
# Modo: nasce em `aviso`. Promova em .expx/hooks.json so depois de semanas
# sem falso positivo — a excecao acima nao depende dessa promocao.
#
# Contrato: falha aberta, com excecoes. Duvida sobre o ESTADO DO PLANO
# (arquivo nao declarado em task nenhuma do trabalho corrente) => permite,
# como sempre. Duvida sobre O CONTEXTO — a sessao dona (rastro nao resolve
# esta sessao a uma unica task), o trabalho (fontes divergentes) ou o plano
# do trabalho corrente (ausente, ambiguo, ilegivel, sem a task
# reivindicada) => bloqueia por contrato; nunca escolhe a primeira nem cai
# no plano de outra feature.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../comum/rastro.sh
. "$DIR/../comum/rastro.sh"

ENTRADA="$(cat)"
CWD="$(rastro_json_get "$ENTRADA" cwd)"
[ -n "$CWD" ] || CWD="$PWD"
RAIZ="$(rastro_raiz "$CWD")"

ALVO="$(rastro_tool_input_get "$ENTRADA" file_path)"
# Sem caminho no payload nao ha o que verificar (ex.: ferramenta sem file_path).
[ -n "$ALVO" ] || exit 0

# Caminho relativo a raiz do repo — e assim que o plano declara `arquivos`.
REL="${ALVO#"$RAIZ"/}"

# ------------------------------------------------------------------ isencoes
# Os proprios artefatos da skill nunca sao "fora de escopo": a F6 escreve em
# tasks.md e 00-BLOQUEIOS.md o tempo todo, por desenho. docs/entregas/ e a
# area de artefatos da mergex, que a F6 aciona nos mesmos moldes.
case "$REL" in
  docs/sprintx/*|docs/eventos/*|docs/entregas/*|.expx/*) exit 0 ;;
esac

# ------------------------------------------------ a skill esta executando?
# Porteiro, nao ownership: so decide se a F6 esta rodando em algum lugar da
# arvore. Quem e dono de que sai do trabalho corrente, resolvido mais abaixo
# — nenhum plano encontrado aqui participa da decisao de escopo.
# `find` em vez de glob: no zsh um padrao sem match aborta o script (nomatch),
# e o hook morreria em projeto que ainda nao tem plano.
TASKS_MD="$(find "$RAIZ/docs" -maxdepth 5 -name tasks.md -type f 2>/dev/null)"
[ -n "$TASKS_MD" ] || exit 0

# Nenhuma task aberta em lugar nenhum da feature => a skill nao esta em
# execucao (F6). Fora de execucao, o hook preserva o comportamento antigo:
# nao opina.
ANY_EM_ANDAMENTO=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  grep -q 'status: em_andamento' "$f" 2>/dev/null && ANY_EM_ANDAMENTO=1
done <<EOF
$TASKS_MD
EOF
[ -n "$ANY_EM_ANDAMENTO" ] || exit 0

MODO="$(rastro_modo "$RAIZ" escopo-da-task metodo)"
# Desligado nao roda e nao registra: quem desligou nao quer nem o aviso —
# nem a excecao de arquivo_de_task_irma, nem o fail-closed de sessao ambigua.
[ "$MODO" = "desligado" ] && exit 0

# ------------------------------- trabalho e task DESTA sessao, como uma unidade
# Fonte mecanica normativa: o rastro (docs/eventos/<trabalho_id>.jsonl) — a
# mesma que task-reivindicada.sh usa para achar quem tem uma task aberta
# agora. `rastro_reivindicacoes_da_sessao` devolve o par TRABALHO + TASK
# junto: `T-01.01` e local a feature e se repete entre features, entao o id
# da task sozinho nunca identifica o plano (DS-153). "Existe uma task
# em_andamento" tambem nao decide o dono: pode haver mais de uma task em
# andamento (paralelismo). O payload do hook nao traz identificador de
# trabalho — so `cwd` e `tool_input` —, e mtime responde "que feature mexeu
# por ultimo no disco", nao "qual e a desta sessao": nenhum dos dois entra
# aqui, nem para decidir escopo nem para escolher onde gravar (DS-155).
MINHA_SESSAO="$(rastro_sessao)"
MINHAS="$(rastro_reivindicacoes_da_sessao "$RAIZ" "$MINHA_SESSAO")"
N_MINHAS="$(printf '%s\n' "$MINHAS" | awk 'NF' | wc -l | tr -d ' ')"

# A sessao precisa resolver para EXATAMENTE uma task aberta. Zero (o rastro
# nao reconhece esta sessao como dona de nada) ou duas-ou-mais (estado
# inconsistente) sao ambiguos — aqui a falha NAO e aberta: para por
# contrato, nunca escolhe a primeira task em_andamento que encontrar.
if [ "$N_MINHAS" -ne 1 ]; then
  MSG_AMB="sprintx/escopo-da-task: sessao_ambigua — esta sessao nao foi associada de forma inequivoca a uma task em andamento pelo rastro ($N_MINHAS correspondencia(s) para a sessao $MINHA_SESSAO em $RAIZ/docs/eventos/*.jsonl). Por contrato a edicao fica bloqueada; a maquina nunca escolhe a primeira task em_andamento que encontra. Reivindique a task (evento task_iniciada no rastro) antes de editar."
  EXTRAS_AMB="\"condicao\":\"sessao_ambigua\",\"tasks_candidatas\":$N_MINHAS"
  # Sem trabalho corrente inequivoco nao ha rastro de trabalho onde gravar: a
  # forma curta manda para `sem-trabalho`, que e exatamente o que aconteceu.
  rastro_grava "$RAIZ" acao_bloqueada hook bloqueado "sessao_ambigua" "[]" "$EXTRAS_AMB"
  rastro_bloqueia "$MSG_AMB"
fi

PAR_SESSAO="$(printf '%s\n' "$MINHAS" | awk 'NF' | head -1)"
TRABALHO="$(printf '%s' "$PAR_SESSAO" | cut -f1)"
CURRENT_ID="$(printf '%s' "$PAR_SESSAO" | cut -f2)"
COERENCIA="$(printf '%s' "$PAR_SESSAO" | cut -f3)"

# Coerencia entre as fontes mecanicas do trabalho: o nome do arquivo de
# eventos (normativo) e o campo trabalho_id de dentro do evento. Divergir e
# contexto quebrado — nunca se escolhe uma das duas em silencio.
if [ "$COERENCIA" != "ok" ]; then
  MSG_DIV="sprintx/escopo-da-task: contexto_de_trabalho_divergente — a reivindicacao desta sessao esta em docs/eventos/$TRABALHO.jsonl mas o proprio evento declara outro trabalho_id. Por contrato a edicao fica bloqueada: o trabalho corrente precisa ser inequivoco antes de qualquer decisao de escopo."
  EXTRAS_DIV="\"condicao\":\"contexto_de_trabalho_divergente\",\"trabalho\":\"$(rastro_json_escape "$TRABALHO")\""
  rastro_grava_trabalho "$RAIZ" "$TRABALHO" acao_bloqueada hook bloqueado "contexto_de_trabalho_divergente" "[]" "$EXTRAS_DIV"
  rastro_bloqueia "$MSG_DIV"
fi

# ------------------------------------------- plano SO do trabalho corrente
# Nada de procurar o id da task em todos os planos da arvore: o plano vem do
# trabalho ja resolvido. Dois layouts, os mesmos que a SKILL.md declara
# suportar — o canonico docs/sprintx/features/<slug>/ e o antigo docs/<slug>/
# —, e nos dois o arquivo continua sendo sprint-NN/tasks.md (00-schema.md),
# entao condensado e separado nao mudam o caminho. `sort` porque a ordem que
# o filesystem devolve nao pode decidir nada.
TASKS_CANON="$(find "$RAIZ/docs/sprintx/features/$TRABALHO" -maxdepth 3 -name tasks.md -type f 2>/dev/null | LC_ALL=C sort)"
TASKS_LEGADO="$(find "$RAIZ/docs/$TRABALHO" -maxdepth 3 -name tasks.md -type f 2>/dev/null | LC_ALL=C sort)"

_para_por_contrato() { # _para_por_contrato <condicao> <mensagem>
  rastro_grava_trabalho "$RAIZ" "$TRABALHO" acao_bloqueada hook bloqueado "$1" "[\"$(rastro_json_escape "$REL")\"]" \
    "\"condicao\":\"$1\",\"trabalho\":\"$(rastro_json_escape "$TRABALHO")\",\"task_atual\":\"$(rastro_json_escape "$CURRENT_ID")\""
  rastro_bloqueia "sprintx/escopo-da-task: $1 — $2"
}

# Os dois layouts com o mesmo slug: nao da para amarrar plano a trabalho.
if [ -n "$TASKS_CANON" ] && [ -n "$TASKS_LEGADO" ]; then
  _para_por_contrato plano_corrente_ambiguo "o trabalho $TRABALHO tem plano em docs/sprintx/features/$TRABALHO/ E em docs/$TRABALHO/. Deixe um so layout antes de executar; a maquina nao escolhe entre eles."
fi

TASKS_TRABALHO="$TASKS_CANON"
[ -n "$TASKS_TRABALHO" ] || TASKS_TRABALHO="$TASKS_LEGADO"

# Execucao e task-based: a sessao afirma trabalho + task. Sem o plano DESSE
# trabalho nao ha escopo a verificar — e nenhum plano de outra feature serve
# de substituto. Falha fechada, sem fallback global.
if [ -z "$TASKS_TRABALHO" ]; then
  _para_por_contrato plano_corrente_ausente "a sessao reivindicou $CURRENT_ID no trabalho $TRABALHO, mas nao ha sprint-NN/tasks.md em docs/sprintx/features/$TRABALHO/ nem em docs/$TRABALHO/. Nenhum plano de outra feature e usado no lugar."
fi

# Pares <task_id> TAB <tasks_md-que-a-declara>, um por linha — so as tasks do
# trabalho corrente, para montar CURRENT/OTHERS mais abaixo.
PARES=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    PARES="$PARES$id	$f
"
  done <<EOF2
$(awk '/^  - id:/ { id=$3; sub(/^[ \t]+/, "", id); if (id != "") print id }' "$f" 2>/dev/null)
EOF2
done <<EOF
$TASKS_TRABALHO
EOF

IDS_UNICOS="$(printf '%s\n' "$PARES" | awk -F'\t' 'NF{print $1}' | LC_ALL=C sort -u)"

# Plano do trabalho corrente existe mas nao entrega task nenhuma: ilegivel.
if [ -z "$IDS_UNICOS" ]; then
  _para_por_contrato plano_corrente_ilegivel "o plano do trabalho $TRABALHO existe mas nenhuma task pode ser lida dele. Corrija o plano; a maquina nao procura a task em outra feature."
fi

CURRENT_TASKS_MD="$(printf '%s\n' "$PARES" | awk -F'\t' -v id="$CURRENT_ID" '$1 == id { print $2; exit }')"

# A task reivindicada nao esta no plano do proprio trabalho: contexto
# quebrado. Antes isto permitia em silencio, e o id podia casar com a task
# homonima de outra feature.
if [ -z "$CURRENT_TASKS_MD" ]; then
  _para_por_contrato task_fora_do_plano_corrente "a sessao reivindicou $CURRENT_ID no trabalho $TRABALHO, mas o plano desse trabalho nao declara essa task. A mesma id em outra feature nao vale."
fi

# -------------------------------------------------------- arquivos declarados
# Extrai `arquivos:` (mapa {cria, altera} ou lista plana — as duas formas em
# uso) de UMA task especifica em UM tasks.md.
_arquivos_da_task() { # _arquivos_da_task <task_id> <tasks_md>
  awk -v alvo="$1" '
    # Emite todo caminho dentro de colchetes na linha. Percorre grupo a grupo:
    # `{cria: [a], altera: [b]}` tem DOIS grupos, e um gsub guloso de `.*\[`
    # descartaria o primeiro em silencio.
    function emitir(linha,   ini, fim, corpo, p, n, i) {
      while (match(linha, /\[[^]]*\]/)) {
        ini = RSTART; fim = RLENGTH
        corpo = substr(linha, ini + 1, fim - 2)
        n = split(corpo, p, ",")
        for (i = 1; i <= n; i++) {
          gsub(/^[ \t]+|[ \t]+$/, "", p[i])
          gsub(/^["'\'']|["'\'']$/, "", p[i])
          if (p[i] != "") print p[i]
        }
        linha = substr(linha, ini + fim)
      }
    }
    $0 ~ /^  - id:/ { atual = $3; sub(/^[ \t]+/, "", atual); emlista = 0 }
    atual != alvo { next }
    # mapa: arquivos: {cria: [...], altera: [...]}, em uma linha ou em duas
    /cria:|altera:/ { emitir($0); next }
    # lista plana na mesma linha: arquivos: [a.ts, b.ts]
    /^[ \t]*arquivos:[ \t]*\[/ { emitir($0); emlista = 0; next }
    # lista plana em bloco: arquivos: seguido de "- caminho"
    /^[ \t]*arquivos:[ \t]*$/ { emlista = 1; next }
    emlista && /^[ \t]*-[ \t]+/ {
      linha = $0
      sub(/^[ \t]*-[ \t]+/, "", linha)
      gsub(/^[ \t]+|[ \t]+$/, "", linha)
      gsub(/^["'\'']|["'\'']$/, "", linha)
      if (linha != "") print linha
      next
    }
    emlista { emlista = 0 }
  ' "$2" 2>/dev/null
}

CURRENT_DECLARADOS="$(_arquivos_da_task "$CURRENT_ID" "$CURRENT_TASKS_MD")"

# Task corrente sem `arquivos` legivel => nao da pra julgar quem e dono de
# que. Permite (falha aberta), como sempre.
[ -n "$CURRENT_DECLARADOS" ] || exit 0

# CURRENT vence: mesmo que o arquivo tambem esteja numa task irma (regra de
# conjuntos — interseccao com a task corrente sempre permite).
if printf '%s\n' "$CURRENT_DECLARADOS" | grep -qxF "$REL"; then
  exit 0
fi

# ------------------------------------------------------- arquivo_de_task_irma?
# Nao esta em CURRENT. Esta em alguma OUTRA task da feature (OTHERS)? Se
# estiver, e inequivoco: pertence so a task irma. Se nao estiver em lugar
# nenhum (nem CURRENT, nem OTHERS), cai no caso antigo mais abaixo.
TASKS_IRMAS=""
while IFS= read -r par; do
  [ -n "$par" ] || continue
  id="${par%%	*}"
  f="${par#*	}"
  [ "$id" != "$CURRENT_ID" ] || continue
  decl="$(_arquivos_da_task "$id" "$f")"
  if printf '%s\n' "$decl" | grep -qxF "$REL"; then
    TASKS_IRMAS="$TASKS_IRMAS$id
"
  fi
done <<EOF
$PARES
EOF
TASKS_IRMAS="$(printf '%s\n' "$TASKS_IRMAS" | awk 'NF' | sort -u)"

if [ -n "$TASKS_IRMAS" ]; then
  LISTA_IRMAS="$(printf '%s' "$TASKS_IRMAS" | tr '\n' ' ')"
  MSG_IRMA="sprintx/escopo-da-task: arquivo_de_task_irma — o arquivo $REL esta declarado so em task(s) irma(s) ($LISTA_IRMAS), nao na task corrente $CURRENT_ID. Bloqueado por contrato mesmo em modo aviso: registre um bloqueio classe defeito_de_plano (scripts/bloqueios.sh registrar), marque $CURRENT_ID como bloqueada e rode scripts/planejamento.sh replanejar-execucao antes de editar este arquivo."

  IRMAS_JSON="$(printf '%s\n' "$TASKS_IRMAS" | awk 'NF{printf "%s\"%s\"", (NR>1?",":""), $0}')"
  EXTRAS="\"condicao\":\"arquivo_de_task_irma\",\"task_atual\":\"$(rastro_json_escape "$CURRENT_ID")\",\"tasks_irmas\":[$IRMAS_JSON]"

  RASTRO_TASK="\"$CURRENT_ID\""
  rastro_grava_trabalho "$RAIZ" "$TRABALHO" acao_bloqueada hook bloqueado "arquivo_de_task_irma" "[\"$(rastro_json_escape "$REL")\"]" "$EXTRAS"
  rastro_bloqueia "$MSG_IRMA"
fi

# --------------------------------------------------------------- violacao
# Caso geral de sempre: arquivo fora do escopo da task corrente e fora de
# qualquer outra task da feature. Preserva o comportamento antigo — aviso
# (ou bloqueio, se o hook ja foi promovido). NUNCA vira defeito_de_plano: e o
# caso ambiguo (pode ser desvio legitimo), nao o inequivoco.
LISTA="$(printf '%s' "$CURRENT_DECLARADOS" | tr '\n' ' ')"
MSG="sprintx/escopo-da-task: a task $CURRENT_ID esta em andamento e declarou estes arquivos: $LISTA. O arquivo $REL nao esta na lista. O caminho certo e ampliar a task no plano (tasks.md), nao editar fora dela."

RASTRO_TASK="\"$CURRENT_ID\""

if [ "$MODO" = "bloqueio" ]; then
  rastro_grava_trabalho "$RAIZ" "$TRABALHO" acao_bloqueada hook bloqueado "fora do escopo da task $CURRENT_ID" "[\"$(rastro_json_escape "$REL")\"]"
  rastro_bloqueia "$MSG"
fi

rastro_grava_trabalho "$RAIZ" "$TRABALHO" regra_violada hook aviso "fora do escopo da task $CURRENT_ID" "[\"$(rastro_json_escape "$REL")\"]"
rastro_aviso_ao_modelo PreToolUse "$MSG"
