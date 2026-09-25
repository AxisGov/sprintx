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
#
# Custo (DS-157). O runner cancela o hook que estoura o timeout e deixa a
# escrita acontecer: timeout e falha ABERTA. Por isso a decisao inteira sai de
# UMA passada de awk sobre o rastro e os planos — nenhum find, grep, cut, sort,
# wc, dirname ou jq no caminho comum. O payload e lido sem processo; o jq so
# roda para o modo, e so quando a edicao nao e da task corrente. O hook e a
# primeira barreira; a posterior, fail-closed, e o E1 da mergex.
set -uo pipefail

case "${BASH_SOURCE[0]}" in */*) DIR="${BASH_SOURCE[0]%/*}" ;; *) DIR=. ;; esac
# shellcheck source=../comum/rastro.sh
. "$DIR/../comum/rastro.sh"

rastro_le_entrada_em ENTRADA
rastro_json_campo_em CWD "$ENTRADA" cwd
[ -n "$CWD" ] || CWD="$PWD"
# No Windows o runner manda C:\dir (e a caixa do drive varia): raiz e alvo na mesma forma,
# senao o prefixo nao sai, o caminho nao casa com `arquivos` e a irma so avisa.
rastro_caminho_em CWD "$CWD"
rastro_raiz_em RAIZ "$CWD"

rastro_json_campo_em ALVO "$ENTRADA" file_path
# Sem caminho no payload nao ha o que verificar (ex.: ferramenta sem file_path).
[ -n "$ALVO" ] || exit 0
rastro_caminho_em ALVO "$ALVO"

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
# arvore — algum tasks.md ate 5 niveis sob docs/ (o mesmo alcance de sempre)
# com `status: em_andamento`. Quem e dono de que sai do trabalho corrente,
# resolvido pelo awk abaixo — nenhum plano visto aqui decide escopo. Glob do
# proprio bash, sem `find`; nullglob porque um padrao sem match nao pode virar
# argumento (o hook morreria em projeto que ainda nao tem plano).
shopt -s nullglob
EVENTOS=("$RAIZ"/docs/eventos/*.jsonl)
shopt -s dotglob
PLANOS=()
for f in "$RAIZ"/docs/tasks.md "$RAIZ"/docs/*/tasks.md "$RAIZ"/docs/*/*/tasks.md \
         "$RAIZ"/docs/*/*/*/tasks.md "$RAIZ"/docs/*/*/*/*/tasks.md \
         "$RAIZ"/docs/sprintx/features/*/*/*/tasks.md; do
  [ -f "$f" ] && [ ! -L "$f" ] && PLANOS+=("$f")
done
shopt -u nullglob dotglob
[ "${#PLANOS[@]}" -gt 0 ] || exit 0

rastro_sessao_em MINHA_SESSAO

# ------------------------------------------------------------ a decisao, numa passada
# Entradas: primeiro os docs/eventos/*.jsonl (a reivindicacao da sessao, pelo miolo
# compartilhado de rastro.sh), depois os tasks.md. Saidas, uma por linha:
#   G 0|1                    — algum tasks.md do alcance do porteiro tem em_andamento
#   N <n>                    — reivindicacoes ativas desta sessao (trabalho + task)
#   S <trabalho> <task> <ok|divergente>   — a reivindicacao, quando N e 1
#   P ok|ambiguo|ausente|ilegivel|fora    — o plano SO do trabalho corrente
#   D vazio|corrente|irma|nenhuma         — onde o arquivo esta declarado
#   I <task> ...             — as irmas que o declaram (ordem de byte, sem repeticao)
#   L <arquivo> ...          — os arquivos declarados da task corrente
#   Z <arquivo> <bytes>      — tamanho de cada rastro lido (rotacao sem `wc`)
#
# `arquivos` sai do FRONTMATTER de cada tasks.md: a prosa repete o bloco ```yaml de
# cada task, e ler a prosa daria a ultima task do frontmatter os arquivos de todas.
# Raiz, caminho e sessao vao por ENVIRON: `awk -v` interpretaria barra invertida.
SAIDA="$(SX_SES="$MINHA_SESSAO" SX_RAIZ="$RAIZ" SX_REL="$REL" LC_ALL=C awk "$_RASTRO_AWK_REIV"'
  BEGIN { ses = ENVIRON["SX_SES"]; raiz = ENVIRON["SX_RAIZ"]; rel = ENVIRON["SX_REL"] }
  function barras(s,   n) { n = gsub(/\//, "/", s); return n }
  function item(c) {
    gsub(/^[ \t]+|[ \t]+$/, "", c); gsub(/^["'\'']|["'\'']$/, "", c)
    if (c != "") { NA[AT, ++NAN[AT]] = c }
  }
  function emitir(linha,   ini, fim, corpo, q, n, i) {
    while (match(linha, /\[[^]]*\]/)) {
      ini = RSTART; fim = RLENGTH
      corpo = substr(linha, ini + 1, fim - 2)
      n = split(corpo, q, ",")
      for (i = 1; i <= n; i++) item(q[i])
      linha = substr(linha, ini + fim)
    }
  }
  # Plano do trabalho corrente: ate 3 niveis sob a pasta dele, em cada layout (1 = canonico,
  # 2 = legado docs/<slug>/, 0 = de fora).
  function do_trabalho(f) {
    if (N != 1 || T == "") return 0
    if (index(f, CAN) == 1 && barras(substr(f, length(CAN) + 1)) <= 2) return 1
    if (index(f, LEG) == 1 && barras(substr(f, length(LEG) + 1)) <= 2) return 2
    return 0
  }
  # A reivindicacao da sessao, depois de ler o rastro inteiro.
  function resolve(   p) {
    _rv_fim(ses); N = RV_N
    if (N == 1) { split(RV_L[1], p, "\t"); T = p[1]; ID = p[2]; COER = p[3] }
    CAN = raiz "/docs/sprintx/features/" T "/"; LEG = raiz "/docs/" T "/"
  }
  FILENAME ~ /\.jsonl$/ { _rv_linha(); next }
  FNR == 1 {
    sub(/\r$/, "")
    # Porteiro: ate 5 niveis sob docs/ (o glob de 6 niveis so existe para o plano).
    PORT = (barras(substr(FILENAME, length(raiz "/docs/") + 1)) <= 4)
    # Frontmatter so quando o arquivo abre com ---; sem ele, o arquivo inteiro (legado).
    FM = ($0 == "---"); FORA = 0; AT = ""; EML = 0
  }
  { sub(/\r$/, "") }
  PORT && index($0, "status: em_andamento") { G = 1 }
  /^  - id:/ {
    id = $3; sub(/^[ \t]+/, "", id); EML = 0
    if (id == "") next
    AT = FILENAME SUBSEP id
    if (!(AT in VISTO)) { VISTO[AT] = 1; NP++; PID[NP] = id; PARQ[NP] = FILENAME }
    next
  }
  FNR > 1 && FM && $0 == "---" { FORA = 1; AT = "" }
  FORA || AT == "" { next }
  /cria:|altera:/ { emitir($0); next }
  /^[ \t]*arquivos:[ \t]*\[/ { emitir($0); EML = 0; next }
  /^[ \t]*arquivos:[ \t]*$/ { EML = 1; next }
  EML && /^[ \t]*-[ \t]+/ { l = $0; sub(/^[ \t]*-[ \t]+/, "", l); item(l); next }
  EML { EML = 0 }
  END {
    resolve()
    print "G " (G ? 1 : 0)
    print "N " N
    for (i = 1; i < ARGC; i++) if (ARGV[i] ~ /\.jsonl$/) print "Z " ARGV[i] "\t" (RV_TAM[ARGV[i]] + 0)
    if (N != 1) exit
    print "S " T "\t" ID "\t" COER
    for (i = 1; i < ARGC; i++) { if (ARGV[i] ~ /\.jsonl$/) continue; x = do_trabalho(ARGV[i]); if (x == 1) TEMCAN = 1; else if (x == 2) TEMLEG = 1 }
    if (TEMCAN && TEMLEG) { print "P ambiguo"; exit }
    if (!TEMCAN && !TEMLEG) { print "P ausente"; exit }
    # So as tasks do plano DESTE trabalho decidem: PTR marca de que layout veio cada uma.
    npt = 0; for (i = 1; i <= NP; i++) { PTR[i] = do_trabalho(PARQ[i]); if (PTR[i]) npt++ }
    if (!npt) { print "P ilegivel"; exit }
    # A task corrente: a do primeiro tasks.md do trabalho, em ordem de byte, que a declara.
    cur = ""
    for (i = 1; i <= NP; i++) if (PID[i] == ID && PTR[i] && (cur == "" || PARQ[i] < cur)) cur = PARQ[i]
    if (cur == "") { print "P fora"; exit }
    print "P ok"
    k = cur SUBSEP ID; lista = ""; corrente = 0
    for (j = 1; j <= NAN[k]; j++) { lista = lista (j > 1 ? " " : "") NA[k, j]; if (NA[k, j] == rel) corrente = 1 }
    print "L " lista
    if (NAN[k] + 0 == 0) { print "D vazio"; exit }
    if (corrente) { print "D corrente"; exit }
    ni = 0
    for (i = 1; i <= NP; i++) {
      if (PID[i] == ID || !PTR[i]) continue
      k = PARQ[i] SUBSEP PID[i]
      for (j = 1; j <= NAN[k]; j++) if (NA[k, j] == rel) { if (!(PID[i] in JA)) { JA[PID[i]] = 1; IR[++ni] = PID[i] } break }
    }
    for (i = 2; i <= ni; i++) { x = IR[i]; for (j = i - 1; j >= 1 && IR[j] > x; j--) IR[j + 1] = IR[j]; IR[j + 1] = x }
    irmas = ""; for (i = 1; i <= ni; i++) irmas = irmas (i > 1 ? " " : "") IR[i]
    if (ni) { print "D irma"; print "I " irmas } else print "D nenhuma"
  }' ${EVENTOS[@]+"${EVENTOS[@]}"} "${PLANOS[@]}" 2>/dev/null)"

G=0; N_MINHAS=0; TRABALHO=""; CURRENT_ID=""; COERENCIA=""; PLANO=""; DECL=""; IRMAS=""; LISTA=""
RASTRO_TAMANHOS=""
while IFS= read -r l; do
  case "$l" in
    "G "*) G="${l#G }" ;;
    "N "*) N_MINHAS="${l#N }" ;;
    "S "*) l="${l#S }"; TRABALHO="${l%%	*}"; l="${l#*	}"; CURRENT_ID="${l%%	*}"; COERENCIA="${l#*	}" ;;
    "P "*) PLANO="${l#P }" ;;
    "D "*) DECL="${l#D }" ;;
    "I "*) IRMAS="${l#I }" ;;
    "L "*) LISTA="${l#L }" ;;
    "Z "*) RASTRO_TAMANHOS="$RASTRO_TAMANHOS
${l#Z }" ;;
  esac
done <<EOF
$SAIDA
EOF

# Nenhuma task aberta em lugar nenhum da feature => a skill nao esta em
# execucao (F6). Fora de execucao, o hook preserva o comportamento antigo:
# nao opina.
[ "$G" = 1 ] || exit 0

# ---------------------------------------------------- caminho comum: task corrente
# A reivindicacao e unica e coerente, o plano do trabalho corrente declara a task, e o
# arquivo esta nela (CURRENT vence, mesmo que tambem esteja numa irma — regra de
# conjuntos) — ou a task nao tem `arquivos` legivel e nao da para julgar dono (falha
# aberta, como sempre). Permitido em qualquer modo, inclusive `desligado`: nada a ler.
if [ "$N_MINHAS" = 1 ] && [ "$COERENCIA" = ok ] && [ "$PLANO" = ok ]; then
  case "$DECL" in corrente|vazio) exit 0 ;; esac
fi

# Daqui para baixo a edicao nao e da task corrente: o modo decide.
rastro_modo_em MODO "$RAIZ" escopo-da-task metodo
# Desligado nao roda e nao registra: quem desligou nao quer nem o aviso —
# nem a excecao de arquivo_de_task_irma, nem o fail-closed de sessao ambigua.
[ "$MODO" = "desligado" ] && exit 0

# O trabalho da sessao ja esta resolvido: rastro_grava_trabalho nao varre de novo.
RASTRO_TRABALHO_DA_SESSAO=""
if [ "$N_MINHAS" = 1 ] && [ "$COERENCIA" = ok ] && rastro_trabalho_valido "$TRABALHO"; then
  RASTRO_TRABALHO_DA_SESSAO="$TRABALHO"
fi

# ------------------------------- trabalho e task DESTA sessao, como uma unidade
# Fonte mecanica normativa: o rastro (docs/eventos/<trabalho_id>.jsonl) — a
# mesma que task-reivindicada.sh usa para achar quem tem uma task aberta
# agora. A reivindicacao devolve o par TRABALHO + TASK junto: `T-01.01` e
# local a feature e se repete entre features, entao o id da task sozinho
# nunca identifica o plano (DS-153). "Existe uma task em_andamento" tambem nao
# decide o dono: pode haver mais de uma task em andamento (paralelismo). O
# payload do hook nao traz identificador de trabalho — so `cwd` e
# `tool_input` —, e mtime responde "que feature mexeu por ultimo no disco",
# nao "qual e a desta sessao": nenhum dos dois entra aqui, nem para decidir
# escopo nem para escolher onde gravar (DS-155).
#
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

rastro_json_escape_em TRABALHO_E "$TRABALHO"
rastro_json_escape_em CURRENT_E "$CURRENT_ID"
rastro_json_escape_em REL_E "$REL"

# Coerencia entre as fontes mecanicas do trabalho: o nome do arquivo de
# eventos (normativo) e o campo trabalho_id de dentro do evento. Divergir e
# contexto quebrado — nunca se escolhe uma das duas em silencio.
if [ "$COERENCIA" != "ok" ]; then
  MSG_DIV="sprintx/escopo-da-task: contexto_de_trabalho_divergente — a reivindicacao desta sessao esta em docs/eventos/$TRABALHO.jsonl mas o proprio evento declara outro trabalho_id. Por contrato a edicao fica bloqueada: o trabalho corrente precisa ser inequivoco antes de qualquer decisao de escopo."
  EXTRAS_DIV="\"condicao\":\"contexto_de_trabalho_divergente\",\"trabalho\":\"$TRABALHO_E\""
  rastro_grava_trabalho "$RAIZ" "$TRABALHO" acao_bloqueada hook bloqueado "contexto_de_trabalho_divergente" "[]" "$EXTRAS_DIV"
  rastro_bloqueia "$MSG_DIV"
fi

_para_por_contrato() { # _para_por_contrato <condicao> <mensagem>
  rastro_grava_trabalho "$RAIZ" "$TRABALHO" acao_bloqueada hook bloqueado "$1" "[\"$REL_E\"]" \
    "\"condicao\":\"$1\",\"trabalho\":\"$TRABALHO_E\",\"task_atual\":\"$CURRENT_E\""
  rastro_bloqueia "sprintx/escopo-da-task: $1 — $2"
}

# ------------------------------------------- plano SO do trabalho corrente
# Nada de procurar o id da task em todos os planos da arvore: o plano vem do
# trabalho ja resolvido. Dois layouts, os mesmos que a SKILL.md declara
# suportar — o canonico docs/sprintx/features/<slug>/ e o antigo docs/<slug>/
# —, e nos dois o arquivo continua sendo sprint-NN/tasks.md (00-schema.md),
# entao condensado e separado nao mudam o caminho. A ordem de byte dos
# caminhos, e nao a do filesystem, decide qual tasks.md declara a task.
case "$PLANO" in
  # Os dois layouts com o mesmo slug: nao da para amarrar plano a trabalho.
  ambiguo) _para_por_contrato plano_corrente_ambiguo "o trabalho $TRABALHO tem plano em docs/sprintx/features/$TRABALHO/ E em docs/$TRABALHO/. Deixe um so layout antes de executar; a maquina nao escolhe entre eles." ;;
  # Execucao e task-based: a sessao afirma trabalho + task. Sem o plano DESSE
  # trabalho nao ha escopo a verificar — e nenhum plano de outra feature serve
  # de substituto. Falha fechada, sem fallback global.
  ausente) _para_por_contrato plano_corrente_ausente "a sessao reivindicou $CURRENT_ID no trabalho $TRABALHO, mas nao ha sprint-NN/tasks.md em docs/sprintx/features/$TRABALHO/ nem em docs/$TRABALHO/. Nenhum plano de outra feature e usado no lugar." ;;
  # Plano do trabalho corrente existe mas nao entrega task nenhuma: ilegivel.
  ilegivel) _para_por_contrato plano_corrente_ilegivel "o plano do trabalho $TRABALHO existe mas nenhuma task pode ser lida dele. Corrija o plano; a maquina nao procura a task em outra feature." ;;
  # A task reivindicada nao esta no plano do proprio trabalho: contexto
  # quebrado. Antes isto permitia em silencio, e o id podia casar com a task
  # homonima de outra feature.
  fora) _para_por_contrato task_fora_do_plano_corrente "a sessao reivindicou $CURRENT_ID no trabalho $TRABALHO, mas o plano desse trabalho nao declara essa task. A mesma id em outra feature nao vale." ;;
esac

# ------------------------------------------------------- arquivo_de_task_irma?
# Nao esta em CURRENT. Esta em alguma OUTRA task da feature (OTHERS)? Se
# estiver, e inequivoco: pertence so a task irma. Se nao estiver em lugar
# nenhum (nem CURRENT, nem OTHERS), cai no caso antigo mais abaixo.
if [ "$DECL" = irma ]; then
  MSG_IRMA="sprintx/escopo-da-task: arquivo_de_task_irma — o arquivo $REL esta declarado so em task(s) irma(s) ($IRMAS), nao na task corrente $CURRENT_ID. Bloqueado por contrato mesmo em modo aviso: registre um bloqueio classe defeito_de_plano (scripts/bloqueios.sh registrar), marque $CURRENT_ID como bloqueada e rode scripts/planejamento.sh replanejar-execucao antes de editar este arquivo."
  IRMAS_JSON=""
  for t in $IRMAS; do IRMAS_JSON="$IRMAS_JSON${IRMAS_JSON:+,}\"$t\""; done
  EXTRAS="\"condicao\":\"arquivo_de_task_irma\",\"task_atual\":\"$CURRENT_E\",\"tasks_irmas\":[$IRMAS_JSON]"
  RASTRO_TASK="\"$CURRENT_ID\""
  rastro_grava_trabalho "$RAIZ" "$TRABALHO" acao_bloqueada hook bloqueado "arquivo_de_task_irma" "[\"$REL_E\"]" "$EXTRAS"
  rastro_bloqueia "$MSG_IRMA"
fi

# --------------------------------------------------------------- violacao
# Caso geral de sempre: arquivo fora do escopo da task corrente e fora de
# qualquer outra task da feature. Preserva o comportamento antigo — aviso
# (ou bloqueio, se o hook ja foi promovido). NUNCA vira defeito_de_plano: e o
# caso ambiguo (pode ser desvio legitimo), nao o inequivoco.
MSG="sprintx/escopo-da-task: a task $CURRENT_ID esta em andamento e declarou estes arquivos: $LISTA. O arquivo $REL nao esta na lista. O caminho certo e ampliar a task no plano (tasks.md), nao editar fora dela."

RASTRO_TASK="\"$CURRENT_ID\""

if [ "$MODO" = "bloqueio" ]; then
  rastro_grava_trabalho "$RAIZ" "$TRABALHO" acao_bloqueada hook bloqueado "fora do escopo da task $CURRENT_ID" "[\"$REL_E\"]"
  rastro_bloqueia "$MSG"
fi

rastro_grava_trabalho "$RAIZ" "$TRABALHO" regra_violada hook aviso "fora do escopo da task $CURRENT_ID" "[\"$REL_E\"]"
rastro_aviso_ao_modelo PreToolUse "$MSG"
