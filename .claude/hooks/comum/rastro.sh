#!/usr/bin/env bash
# rastro.sh — biblioteca compartilhada dos hooks da sprintx.
#
# Implementa o contrato expx-eventos v1:
#   /Users/.../Expx/docs/contrato/CONTRATO-expx-eventos.md
#
# Nao e executavel por si so: os hooks fazem `source` deste arquivo.
#
# Regras do contrato que este arquivo materializa:
#   1. Rapido      — sem subshell desnecessario, sem rede, sem parser externo pesado.
#   3. Falha aberta — toda funcao aqui retorna 0 mesmo quando nao consegue gravar.
#   6. Sem estado proprio — tudo sai de arquivo que ja existe.
#   7. Sempre grava no rastro, inclusive quando permite.

# ---------------------------------------------------------------- util basica

# Raiz do repositorio: sobe ate achar .git. Sem .git em nenhum ancestral,
# usa o cwd. Mesma regra do SKILL.md ("Onde fica docs/sprintx/features/<slug>/").
#
# `[ -e ]`, nao `[ -d ]`: num `git worktree`, `.git` e ARQUIVO (contem
# "gitdir: <principal>/.git/worktrees/<nome>"), nao diretorio. `[ -d ]` sozinho
# faz a busca pular a raiz do worktree e continuar subindo — de um subdiretorio
# dele, isso devolve o subdiretorio errado em vez da raiz do worktree (regra 21,
# "Sessoes paralelas", D-06).
rastro_raiz() {
  local d="${1:-$PWD}"
  while [ "$d" != "/" ]; do
    [ -e "$d/.git" ] && { printf '%s' "$d"; return 0; }
    d="$(dirname "$d")"
  done
  printf '%s' "${1:-$PWD}"
}

# ------------------------------------------------------------- identidade

# Nome do harness: EXPX_HARNESS (a ponte OpenCode injeta isso) -> CLAUDECODE
# (o Claude Code exporta essa variavel) -> nome do processo avo -> "desconhecido".
# Nunca lanca excecao.
rastro_harness() {
  if [ -n "${EXPX_HARNESS:-}" ]; then printf '%s' "$EXPX_HARNESS"; return 0; fi
  if [ -n "${CLAUDECODE:-}" ]; then printf 'claude-code'; return 0; fi
  local nome
  nome="$(ps -o comm= -p "${PPID:-0}" 2>/dev/null | xargs -n1 basename 2>/dev/null)"
  case "$nome" in
    claude)   printf 'claude-code' ;;
    opencode) printf 'opencode' ;;
    mimo)     printf 'mimocode' ;;
    *)        printf 'desconhecido' ;;
  esac
}

# Identidade da sessao: <harness>@<id>. Ordem: EXPX_SESSAO (a ponte injeta) ->
# CLAUDE_CODE_SESSION_ID (com o harness na frente) -> <harness>@<ppid> ->
# <harness>@sem-id. Nunca lanca excecao (regra 3 do contrato).
rastro_sessao() {
  if [ -n "${EXPX_SESSAO:-}" ]; then printf '%s' "$EXPX_SESSAO"; return 0; fi
  local h; h="$(rastro_harness)"
  if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    printf '%s@%s' "$h" "$CLAUDE_CODE_SESSION_ID"; return 0
  fi
  if [ -n "${PPID:-}" ]; then printf '%s@%s' "$h" "$PPID"; return 0; fi
  printf '%s@sem-id' "$h"
}

# Escapa uma string para caber dentro de um JSON string literal.
# Ordem importa: a barra invertida primeiro, senao escapamos o que ja escapamos.
rastro_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//	/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

# Le uma chave de topo de um JSON simples vindo do stdin do hook.
# Usa jq quando existe (correto); sem jq, cai para um grep tolerante.
# Nunca falha: chave ausente devolve string vazia.
rastro_json_get() {
  local json="$1" chave="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r --arg k "$chave" '.[$k] // empty' 2>/dev/null
    return 0
  fi
  printf '%s' "$json" \
    | grep -o "\"$chave\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//'
}

# Le uma chave aninhada em tool_input (ex.: file_path).
rastro_tool_input_get() {
  local json="$1" chave="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$json" | jq -r --arg k "$chave" '.tool_input[$k] // empty' 2>/dev/null
    return 0
  fi
  printf '%s' "$json" \
    | grep -o "\"$chave\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//'
}

# ------------------------------------------------------------ trabalho_id

# Um trabalho_id e o slug da feature: o mesmo nome do diretorio da feature e do
# arquivo de eventos. Barra, `..` e vazio nunca passam — um trabalho_id torto
# escolheria um destino fora de docs/eventos/.
rastro_trabalho_valido() {
  case "${1:-}" in
    ''|.|..)           return 1 ;;
    .*|-*)             return 1 ;;
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

# rastro_trabalho_da_sessao <raiz> [sessao]
#
# O trabalho CORRENTE desta sessao, pela identidade normativa da DS-153:
# trabalho + task formam uma unidade, e quem amarra a sessao a essa unidade e
# a reivindicacao ATIVA no rastro. Exatamente uma reivindicacao, coerente
# (`ok`), devolve o trabalho; zero, duas-ou-mais, ou divergente devolvem
# vazio — a sessao nao tem trabalho corrente inequivoco, e a maquina nunca
# escolhe um por conta propria.
#
# Nao ha mtime aqui, e e deliberado (DS-155): "que feature mexeu por ultimo no
# disco" e outra pergunta, e a resposta dela nunca escolhe destino de rastro.
rastro_trabalho_da_sessao() {
  local raiz="$1" ses="${2:-}"
  [ -n "$ses" ] || ses="$(rastro_sessao)"
  local linhas
  linhas="$(rastro_reivindicacoes_da_sessao "$raiz" "$ses" | awk 'NF')"
  [ -n "$linhas" ] || return 0
  [ "$(printf '%s\n' "$linhas" | wc -l | tr -d ' ')" -eq 1 ] || return 0
  local tid coer
  tid="$(printf '%s' "$linhas" | cut -f1)"
  coer="$(printf '%s' "$linhas" | cut -f3)"
  [ "$coer" = ok ] || return 0
  rastro_trabalho_valido "$tid" || return 0
  printf '%s' "$tid"
}

# rastro_trabalho_do_texto <texto>
#
# O `trabalho_id` declarado no frontmatter de um artefato da skill (tasks.md,
# 00-PLANEJAMENTO.md, ...). Deterministico: sai do proprio conteudo, nao do
# disco em volta. Vazio quando a chave nao esta la ou o valor nao e um slug.
rastro_trabalho_do_texto() {
  local tid
  tid="$(printf '%s' "$1" | tr -d '\r' | awk '
    NR == 1 && $0 != "---" { exit }
    NR == 1 { next }
    $0 == "---" { exit }
    /^trabalho_id:[ \t]*/ {
      sub(/^trabalho_id:[ \t]*/, ""); sub(/[ \t]+$/, "")
      gsub(/^"|"$/, ""); print; exit
    }')"
  rastro_trabalho_valido "$tid" || return 0
  printf '%s' "$tid"
}

# rastro_trabalho_do_arquivo <arquivo>
# O mesmo, lido do frontmatter de um artefato em disco.
rastro_trabalho_do_arquivo() {
  [ -f "$1" ] || return 0
  rastro_trabalho_do_texto "$(head -40 "$1" 2>/dev/null)"
}

# ------------------------------------------------------------------ modo

# Le o modo de um hook em .expx/hooks.json — "aviso", "bloqueio" ou "desligado".
# Contrato expx-eventos: "O modo vive em .expx/hooks.json, por hook".
#
# Os TRES modos sao obrigatorios. Reconhecer so dois e cair no padrao diante do
# terceiro faz o hook continuar rodando depois de alguem pedir para desliga-lo.
#
# O padrao, quando o arquivo falta ou nao tem a entrada, sai do `tipo`:
# hook de seguranca nasce em bloqueio e NUNCA e rebaixado por ausencia de
# configuracao; hook de metodo nasce em aviso. So um "desligado" explicito
# desliga um hook de seguranca.
#
# Uso: rastro_modo <raiz> <hook> [tipo]   — tipo: metodo (padrao) | seguranca
rastro_modo() {
  local raiz="$1" hook="$2" tipo="${3:-metodo}" cfg="$1/.expx/hooks.json"
  local padrao='aviso'
  [ "$tipo" = "seguranca" ] && padrao='bloqueio'

  [ -f "$cfg" ] || { printf '%s' "$padrao"; return 0; }
  local m=""
  if command -v jq >/dev/null 2>&1; then
    m="$(jq -r --arg h "$hook" '.hooks[$h].modo // empty' "$cfg" 2>/dev/null)"
  else
    m="$(grep -o "\"$hook\"[[:space:]]*:[[:space:]]*{[^}]*}" "$cfg" 2>/dev/null \
        | grep -o '"modo"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')"
  fi
  case "$m" in
    bloqueio|aviso|desligado) printf '%s' "$m" ;;
    *)                       printf '%s' "$padrao" ;;
  esac
}

# ---------------------------------------------------------------- gravacao

# _rastro_linha <arquivo> <trabalho_id> <evento> <origem> <resultado> <detalhe> <arquivos_json> <extras_json>
#
# Uma linha JSON no formato exato do contrato, acrescentada ao arquivo dado.
# As chaves saem sempre todas, na ordem do contrato, e chave ausente vai como
# null — nunca omitida. Rotacao: acima de 5 MB o arquivo vira
# <trabalho_id>.1.jsonl (contrato), e a politica nao muda com o destino.
_rastro_linha() {
  local arq="$1" tid="$2" evento="$3" origem="$4" resultado="$5" detalhe="$6"
  local arquivos="$7" extras="$8"

  if [ -f "$arq" ]; then
    local tam
    tam=$(wc -c < "$arq" 2>/dev/null | tr -d ' ')
    if [ -n "$tam" ] && [ "$tam" -gt 5242880 ] 2>/dev/null; then
      mv -f "$arq" "${arq%.jsonl}.1.jsonl" 2>/dev/null || true
    fi
  fi

  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local linha
  linha="{\"ts\":\"$ts\""
  linha="$linha,\"expx_eventos\":1"
  linha="$linha,\"trabalho_id\":\"$(rastro_json_escape "$tid")\""
  linha="$linha,\"ferramenta\":\"sprintx\""
  linha="$linha,\"origem\":\"$origem\""
  linha="$linha,\"evento\":\"$evento\""
  linha="$linha,\"fase\":${RASTRO_FASE:-null}"
  linha="$linha,\"task\":${RASTRO_TASK:-null}"
  linha="$linha,\"agente\":\"${RASTRO_AGENTE:-principal}\""
  linha="$linha,\"resultado\":\"$resultado\""
  linha="$linha,\"detalhe\":\"$(rastro_json_escape "$detalhe")\""
  linha="$linha,\"arquivos\":$arquivos"
  [ -n "$extras" ] && linha="$linha,$extras"
  linha="$linha}"

  printf '%s\n' "$linha" >> "$arq" 2>/dev/null || true
}

# rastro_grava_trabalho <raiz> <trabalho_id|-> <evento> <origem> <resultado> <detalhe> [arquivos_json] [extras_json]
#
# Grava UMA linha JSON em docs/eventos/<trabalho_id>.jsonl — no rastro do
# trabalho DADO, nunca no da feature que por acaso mexeu por ultimo no disco.
#
# O segundo argumento e o trabalho corrente que o chamador ja conhece de forma
# deterministica: a reivindicacao da sessao, o `trabalho_id` do frontmatter do
# artefato, ou o slug do proprio caminho sendo escrito. `-` significa "este
# chamador nao tem contexto de trabalho": o destino sai entao do trabalho
# corrente da sessao (`rastro_trabalho_da_sessao`) e, sem ele, de
# `sem-trabalho`. mtime nao participa de nenhum dos dois caminhos (DS-155).
#
# Coerencia, fail-closed: trabalho explicito que contradiz o trabalho que o
# rastro prova para esta sessao e erro de CONTEXTO. Nada e gravado em nenhum
# dos dois — a maquina nunca escolhe entre A e B. A incoerencia sai em
# docs/eventos/sem-trabalho.jsonl, para o painel ver que o evento existiu e
# por que nao foi atribuido a trabalho nenhum.
#
# Falha aberta: qualquer erro aqui e engolido. Um hook nunca trava o trabalho
# por nao conseguir escrever o proprio rastro.
rastro_grava_trabalho() {
  local raiz="$1" pedido="$2" evento="$3" origem="$4" resultado="$5" detalhe="$6"
  local arquivos="${7:-[]}" extras="${8:-}"

  {
    local dir="$raiz/docs/eventos"
    mkdir -p "$dir" 2>/dev/null || return 0

    # O trabalho da sessao nao muda durante o processo do hook: resolve uma vez
    # (varre docs/eventos/*.jsonl) e reusa.
    local sessao_tid
    if [ -n "${RASTRO_TRABALHO_DA_SESSAO+x}" ]; then
      sessao_tid="$RASTRO_TRABALHO_DA_SESSAO"
    else
      sessao_tid="$(rastro_trabalho_da_sessao "$raiz")"
      RASTRO_TRABALHO_DA_SESSAO="$sessao_tid"
    fi

    local tid
    if [ -z "$pedido" ] || [ "$pedido" = "-" ]; then
      tid="$sessao_tid"
      [ -n "$tid" ] || tid="sem-trabalho"
    elif ! rastro_trabalho_valido "$pedido"; then
      _rastro_linha "$dir/sem-trabalho.jsonl" sem-trabalho acao_bloqueada "$origem" bloqueado \
        "trabalho_id_invalido: $evento pedido para '$pedido'" '[]' ''
      return 0
    elif [ -n "$sessao_tid" ] && [ "$sessao_tid" != "$pedido" ]; then
      _rastro_linha "$dir/sem-trabalho.jsonl" sem-trabalho acao_bloqueada "$origem" bloqueado \
        "contexto_de_trabalho_divergente: $evento pedido em '$pedido', a sessao reivindica '$sessao_tid'" '[]' ''
      return 0
    else
      tid="$pedido"
    fi

    _rastro_linha "$dir/$tid.jsonl" "$tid" "$evento" "$origem" "$resultado" "$detalhe" "$arquivos" "$extras"
  } 2>/dev/null || true
  return 0
}

# rastro_grava <raiz> <evento> <origem> <resultado> <detalhe> [arquivos_json] [extras_json]
#
# Forma curta para o chamador que NAO conhece o trabalho: o destino e o
# trabalho corrente da sessao. Quem conhece o trabalho chama
# `rastro_grava_trabalho` e o declara.
rastro_grava() {
  local raiz="$1"; shift
  rastro_grava_trabalho "$raiz" - "$@"
}

# ------------------------------------------------------------------ saida

# Fala com o modelo SEM bloquear (modo aviso).
#
# ATENCAO — mecanica verificada na documentacao oficial, divergente do
# contrato v1: no PostToolUse o `exit 2` NAO bloqueia e o stderr NAO volta
# ao modelo. O unico canal que chega ao modelo e o JSON no stdout, via
# hookSpecificOutput.additionalContext. Ver DS-31 em DECISOES-DA-SKILL.md.
rastro_aviso_ao_modelo() {
  local evento_hook="$1" msg="$2"
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' \
    "$evento_hook" "$(rastro_json_escape "$msg")"
  exit 0
}

# Barra a chamada (modo bloqueio). So vale em PreToolUse.
# exit 2 + stderr e o caminho documentado para bloquear.
rastro_bloqueia() {
  printf '%s\n' "$1" >&2
  exit 2
}

# ------------------------------------------------------------- ownership

# rastro_sessao_dona <rastro_arq> <task_id>
#
# Sessao que tem a task ABERTA agora: le o rastro de tras para frente e olha
# o evento mais recente daquele task_id entre task_iniciada/task_concluida/
# task_bloqueada. So devolve algo se o mais recente for task_iniciada — task
# fechada (concluida ou bloqueada) nao tem dona aberta. Mesma logica de
# _sessao_dona() em task-reivindicada.sh, compartilhada aqui porque
# escopo-da-task.sh precisa da mesma resolucao (regra 6: sem estado proprio,
# tudo sai do rastro que ja existe).
#
# Falha aberta: sem rastro ou sem jq/awk utilizavel, devolve vazio.
rastro_sessao_dona() {
  local arq="$1" tid="$2"
  [ -f "$arq" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -rc --arg t "$tid" '
      select(.task == $t) | select(.evento == "task_iniciada" or .evento == "task_concluida" or .evento == "task_bloqueada")
    ' "$arq" 2>/dev/null | tail -1 | jq -r '
      if .evento == "task_iniciada" then (.sessao // "") else "" end
    ' 2>/dev/null
    return 0
  fi
  awk -v tid="$tid" '
    index($0, "\"task\":\"" tid "\"") == 0 { next }
    { linhas[NR] = $0 }
    END {
      for (i = NR; i >= 1; i--) {
        l = linhas[i]
        if (index(l, "\"task\":\"" tid "\"") == 0) continue
        if (index(l, "\"evento\":\"task_concluida\"") || index(l, "\"evento\":\"task_bloqueada\"")) { exit }
        if (index(l, "\"evento\":\"task_iniciada\"")) {
          match(l, /"sessao":"[^"]*"/)
          if (RSTART > 0) {
            s = substr(l, RSTART + 10, RLENGTH - 11)
            print s
          }
          exit
        }
      }
    }
  ' "$arq" 2>/dev/null
}

# rastro_reivindicacoes_da_sessao <raiz> <sessao>
#
# Identidade composta da sessao: TRABALHO + TASK, numa unidade. Emite uma
# linha `<trabalho_id>\t<task_id>\t<ok|divergente>` por reivindicacao ATIVA
# da sessao, em ordem deterministica (sort), varrendo todo
# `docs/eventos/<trabalho_id>.jsonl`.
#
# Por que o trabalho vem daqui e nao do id da task: `T-01.01` e local a
# feature e se repete entre features. So o rastro amarra sessao -> trabalho
# -> task de forma inequivoca (DS-153). Nenhum mtime responde isso: "qual
# feature mexeu por ultimo no disco" e outra pergunta, e ela nao escolhe nem
# dono de sessao nem destino de gravacao (DS-155).
#
# Fonte normativa do trabalho: o NOME do arquivo de eventos, que o contrato
# define como `docs/eventos/<trabalho_id>.jsonl` (o sufixo de rotacao `.N` e
# descartado, e o arquivo rotacionado e lido ANTES do corrente). O campo
# `trabalho_id` de dentro do evento e usado so como consistencia: divergir do
# nome marca a linha como `divergente`, e quem chama decide (fail-closed).
#
# Reivindicacao ativa e a mesma semantica de rastro_sessao_dona, por
# (trabalho, task): vale o evento mais recente entre task_iniciada,
# task_concluida e task_bloqueada; so task_iniciada deixa dono aberto.
rastro_reivindicacoes_da_sessao() {
  local raiz="$1" ses="$2"
  # Declaracao separada: no bash 5.3 uma variavel do MESMO `local` ainda nao
  # esta visivel para as seguintes, e `set -u` mataria o hook aqui.
  local dir="$raiz/docs/eventos"
  [ -d "$dir" ] || return 0

  local f base tid rank lista=""
  for f in "$dir"/*.jsonl; do
    [ -f "$f" ] || continue
    base="${f##*/}"; tid="${base%.jsonl}"; rank=0
    case "${tid##*.}" in
      ''|*[!0-9]*) ;;
      *) case "$tid" in *.*) rank="${tid##*.}"; tid="${tid%.*}" ;; esac ;;
    esac
    lista="$lista$tid	$rank	$f
"
  done
  [ -n "$lista" ] || return 0

  # Rotacionado (rank maior) antes do corrente: o awk decide pelo evento mais
  # recente, e "mais recente" e a ordem de leitura.
  local arqs=() linha
  while IFS= read -r linha; do
    [ -n "$linha" ] || continue
    arqs+=("${linha#*	*	}")
  done <<EOF
$(printf '%s' "$lista" | awk 'NF' | LC_ALL=C sort -t'	' -k1,1 -k2,2nr)
EOF
  [ "${#arqs[@]}" -gt 0 ] || return 0

  awk -v ses="$ses" '
    function tid_do_arquivo(p,   b) {
      b = p; sub(/.*\//, "", b); sub(/\.jsonl$/, "", b); sub(/\.[0-9]+$/, "", b); return b
    }
    {
      if (!match($0, /"task":"[^"]*"/)) next
      task = substr($0, RSTART + 8, RLENGTH - 9)
      k = tid_do_arquivo(FILENAME) SUBSEP task
      if (index($0, "\"evento\":\"task_iniciada\"")) {
        s = ""; if (match($0, /"sessao":"[^"]*"/)) s = substr($0, RSTART + 10, RLENGTH - 11)
        d = ""; if (match($0, /"trabalho_id":"[^"]*"/)) d = substr($0, RSTART + 15, RLENGTH - 16)
        dono[k] = s; campo[k] = d
      } else if (index($0, "\"evento\":\"task_concluida\"") || index($0, "\"evento\":\"task_bloqueada\"")) {
        dono[k] = ""
      }
    }
    END {
      for (k in dono) {
        if (dono[k] == "" || dono[k] != ses) continue
        split(k, p, SUBSEP)
        print p[1] "\t" p[2] "\t" ((campo[k] == "" || campo[k] == p[1]) ? "ok" : "divergente")
      }
    }
  ' "${arqs[@]}" 2>/dev/null | LC_ALL=C sort
}
