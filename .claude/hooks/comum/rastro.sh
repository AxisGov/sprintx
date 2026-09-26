#!/usr/bin/env bash
# rastro.sh — biblioteca compartilhada dos hooks da sprintx.
#
# Implementa o contrato expx-eventos v1:
#   /Users/.../Expx/docs/contrato/CONTRATO-expx-eventos.md
#
# Nao e executavel por si so: os hooks fazem `source` deste arquivo — e tambem o
# scripts/rastro.sh da skill, o escritor publico dos eventos que a skill grava (DS-159),
# para que identidade, destino e serializacao tenham uma implementacao so.
#
# Regras do contrato que este arquivo materializa:
#   1. Rapido      — sem subshell desnecessario, sem rede, sem parser externo pesado.
#   3. Falha aberta — toda funcao aqui retorna 0 mesmo quando nao consegue gravar.
#   6. Sem estado proprio — tudo sai de arquivo que ja existe.
#   7. Sempre grava no rastro, inclusive quando permite.
#
# Custo (DS-157): o runner do harness cancela o hook que passa do timeout e deixa a
# ferramenta EXECUTAR — timeout e falha aberta. No Git Bash cada processo novo custa de
# 0,5 a 2 s, e o que protege um hook critico e nao criar processo. As funcoes `*_em <var>`
# devolvem numa variavel, sem `$(...)`; as de sempre continuam, para quem as usa.

# ---------------------------------------------------------------- util basica

# Raiz do repositorio: sobe ate achar .git. Sem .git em nenhum ancestral,
# usa o cwd. Mesma regra do SKILL.md ("Onde fica docs/sprintx/features/<slug>/").
#
# `[ -e ]`, nao `[ -d ]`: num `git worktree`, `.git` e ARQUIVO (contem
# "gitdir: <principal>/.git/worktrees/<nome>"), nao diretorio. `[ -d ]` sozinho
# faz a busca pular a raiz do worktree e continuar subindo — de um subdiretorio
# dele, isso devolve o subdiretorio errado em vez da raiz do worktree (regra 21,
# "Sessoes paralelas", D-06).
#
# O pai sai por expansao de parametro, nao por `dirname`: um processo por nivel.
rastro_raiz_em() { # rastro_raiz_em <var> [dir]
  local d="${2:-$PWD}" p
  while [ "$d" != "/" ]; do
    [ -e "$d/.git" ] && { printf -v "$1" '%s' "$d"; return 0; }
    case "$d" in
      */) p="${d%/}" ;;
      */*) p="${d%/*}"; [ -n "$p" ] || p=/ ;;
      *) p=. ;;
    esac
    # Sem pai diferente (".", caminho sem barra): acabou a subida.
    [ "$p" = "$d" ] && break
    d="$p"
  done
  printf -v "$1" '%s' "${2:-$PWD}"
}
rastro_raiz() { local _r; rastro_raiz_em _r "$@"; printf '%s' "$_r"; }

# rastro_caminho_em <var> <caminho> — um caminho do payload do harness (cwd, file_path) na
# forma do shell. O Claude Code no Windows entrega C:\dir\arq, e a caixa do drive varia entre
# sessoes (f:\ e F:\): prefixo de raiz com `/` nao casa com isso. Em MSYS/Cygwin, drive
# absoluto vira /<letra>/... quando o drive esta montado ali (o padrao do Git Bash, o mesmo
# que o $PWD mostra); com outro prefixo de montagem, a forma canonica X:/... — maiuscula e
# com `/`, que o shell tambem abre. Nenhum processo: quem converte com processo e so o
# caminho-git.sh da skill (DS-152). Caminho POSIX fica intacto; relativo continua relativo,
# so com `/`. Fora do Windows: no-op.
#
# Contrato: todo hook que le um pathname do payload (`cwd`, `tool_input.file_path`) passa-o
# por aqui ANTES de achar a raiz, tirar o prefixo, casar com o plano, abrir o arquivo ou
# gravar no rastro — e nenhum hook normaliza por conta propria (bancada, secao T). Comando,
# conteudo, id e mensagem nao sao caminho: nao passam.
rastro_caminho_em() {
  local _c="$2" _d _i _u=ABCDEFGHIJKLMNOPQRSTUVWXYZ _m=abcdefghijklmnopqrstuvwxyz
  case "${OSTYPE:-}" in msys*|cygwin*) ;; *) printf -v "$1" '%s' "$_c"; return 0 ;; esac
  case "$_c" in
    [A-Za-z]:|[A-Za-z]:[\\/]*)
      _d="${_c:0:1}"; _i="${_u%%"$_d"*}"
      [ "${#_i}" -lt 26 ] || { _i="${_m%%"$_d"*}"; }
      _c="${_c:2}"; _c="${_c//\\//}"
      if [ -d "/${_m:${#_i}:1}" ]; then _d="${_m:${#_i}:1}"; _c="/$_d$_c"
      else _c="${_u:${#_i}:1}:${_c:-/}"; fi ;;
    *\\*) _c="${_c//\\//}" ;;
  esac
  printf -v "$1" '%s' "$_c"
}

# ------------------------------------------------------------- identidade

# Nome do harness: EXPX_HARNESS (a ponte OpenCode injeta isso) -> CLAUDECODE
# (o Claude Code exporta essa variavel) -> nome do processo avo -> "desconhecido".
# Nunca lanca excecao.
rastro_harness_em() { # rastro_harness_em <var>
  if [ -n "${EXPX_HARNESS:-}" ]; then printf -v "$1" '%s' "$EXPX_HARNESS"; return 0; fi
  if [ -n "${CLAUDECODE:-}" ]; then printf -v "$1" 'claude-code'; return 0; fi
  local nome
  nome="$(ps -o comm= -p "${PPID:-0}" 2>/dev/null)"; nome="${nome##*/}"
  case "$nome" in
    claude)   printf -v "$1" 'claude-code' ;;
    opencode) printf -v "$1" 'opencode' ;;
    mimo)     printf -v "$1" 'mimocode' ;;
    *)        printf -v "$1" 'desconhecido' ;;
  esac
}
rastro_harness() { local _h; rastro_harness_em _h; printf '%s' "$_h"; }

# Identidade da sessao: <harness>@<id>. Ordem: EXPX_SESSAO (a ponte injeta) ->
# CLAUDE_CODE_SESSION_ID (com o harness na frente) -> <harness>@<ppid> ->
# <harness>@sem-id. Nunca lanca excecao (regra 3 do contrato). A fonte usada fica em
# RASTRO_SESSAO_FONTE (expx | harness | ppid | sem-id): so as duas primeiras sao a mesma
# para o hook e para o processo do agente — o <ppid> de um nao e o do outro.
rastro_sessao_em() { # rastro_sessao_em <var>
  if [ -n "${EXPX_SESSAO:-}" ]; then RASTRO_SESSAO_FONTE=expx; printf -v "$1" '%s' "$EXPX_SESSAO"; return 0; fi
  local _h; rastro_harness_em _h
  if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    RASTRO_SESSAO_FONTE=harness; printf -v "$1" '%s@%s' "$_h" "$CLAUDE_CODE_SESSION_ID"; return 0
  fi
  if [ -n "${PPID:-}" ]; then RASTRO_SESSAO_FONTE=ppid; printf -v "$1" '%s@%s' "$_h" "$PPID"; return 0; fi
  RASTRO_SESSAO_FONTE=sem-id; printf -v "$1" '%s@sem-id' "$_h"
}
rastro_sessao() { local _s; rastro_sessao_em _s; printf '%s' "$_s"; }

# rastro_identidade_em <var_sessao> <var_harness> — a identidade que um evento de
# reivindicacao precisa levar, derivada pela MESMA regra que os hooks usam para ler
# (rastro_sessao_em). Retorna 1, com as duas variaveis vazias, quando a identidade nao e
# estavel entre o hook e quem grava: fonte <ppid> ou sem-id, harness desconhecido, id vazio,
# ou caractere que a leitura do rastro nao casa (`"sessao":"[^"]*"`). Nunca fabrica: quem
# chama e que falha fechado (scripts/rastro.sh da skill, DS-159).
rastro_identidade_em() {
  local _s _h
  printf -v "$1" '%s' ""; printf -v "$2" '%s' ""
  rastro_sessao_em _s
  case "$RASTRO_SESSAO_FONTE" in expx|harness) ;; *) return 1 ;; esac
  case "$_s" in
    ''|@*|*@|*@sem-id|desconhecido@*|*[!A-Za-z0-9@._:+_-]*) return 1 ;;
    *@*) ;;
    *) return 1 ;;
  esac
  rastro_harness_em _h
  case "$_h" in ''|desconhecido|*[!A-Za-z0-9._-]*) return 1 ;; esac
  printf -v "$1" '%s' "$_s"; printf -v "$2" '%s' "$_h"
}

# Escapa uma string para caber dentro de um JSON string literal.
# Ordem importa: a barra invertida primeiro, senao escapamos o que ja escapamos.
rastro_json_escape_em() { # rastro_json_escape_em <var> <texto>
  local s="$2"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//	/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf -v "$1" '%s' "$s"
}
rastro_json_escape() { local _e; rastro_json_escape_em _e "$1"; printf '%s' "$_e"; }

# rastro_le_entrada_em <var> — o stdin inteiro do hook (o payload JSON). `mapfile -d ''`
# (bash >= 4.4) le em blocos e sem processo; `read -d ''` leria um byte por chamada num
# pipe, e `$(cat)` custa um processo. Bash mais antigo (macOS): `cat`, como sempre.
rastro_le_entrada_em() {
  if [ "${BASH_VERSINFO[0]:-0}" -gt 4 ] || { [ "${BASH_VERSINFO[0]:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -ge 4 ]; }; then
    local _a=()
    mapfile -d '' _a
    printf -v "$1" '%s' "${_a[0]-}"
  else
    printf -v "$1" '%s' "$(cat)"
  fi
}

# rastro_json_campo_em <var> <json> <chave>
#
# O valor string de "<chave>" no payload do hook, SEM processo: a primeira ocorrencia de
# `"chave": "valor"` no texto — a mesma regra do fallback sem jq, que ja era contrato —, com
# o valor inteiro (aspas escapadas incluidas) e os escapes de JSON decodificados como o jq
# os decodifica. Dentro de uma string JSON toda aspa e `\"`, entao `"chave"` so casa com uma
# chave de verdade. `\uXXXX` (so aparece para caractere de controle: o harness manda UTF-8
# cru) vai para o jq quando ha jq. Chave ausente: vazio.
rastro_json_campo_em() {
  local _v="" _re
  _re="\"$3\""'[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
  [[ $2 =~ $_re ]] && _v="${BASH_REMATCH[1]}"
  case "$_v" in
    *\\u*)
      if command -v jq >/dev/null 2>&1; then
        _v="$(printf '"%s"' "$_v" | jq -r . 2>/dev/null)"
      fi ;;
    *\\*)
      _v="${_v//\\\\/$'\001'}"
      _v="${_v//\\\"/\"}"; _v="${_v//\\\//\/}"
      _v="${_v//\\n/$'\n'}"; _v="${_v//\\t/	}"; _v="${_v//\\r/$'\r'}"
      _v="${_v//\\b/$'\b'}"; _v="${_v//\\f/$'\f'}"
      _v="${_v//$'\001'/\\}" ;;
  esac
  printf -v "$1" '%s' "$_v"
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
rastro_trabalho_da_sessao_em() { # rastro_trabalho_da_sessao_em <var> <raiz> [sessao]
  local _raiz="$2" _ses="${3:-}" _tid _coer
  printf -v "$1" '%s' ""
  [ -n "$_ses" ] || rastro_sessao_em _ses
  _rastro_varre "$_raiz" "$_ses"
  case "$RASTRO_REIV" in ""|*"
"*) return 0 ;; esac
  _tid="${RASTRO_REIV%%	*}"; _coer="${RASTRO_REIV##*	}"
  [ "$_coer" = ok ] || return 0
  rastro_trabalho_valido "$_tid" || return 0
  printf -v "$1" '%s' "$_tid"
}
rastro_trabalho_da_sessao() { local _t; rastro_trabalho_da_sessao_em _t "$@"; printf '%s' "$_t"; }

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
#      rastro_modo_em <var> <raiz> <hook> [tipo] — o mesmo, numa variavel, sem subshell
#
# Com jq, o modo sai do JSON de verdade (um processo); sem jq, o texto do arquivo e lido
# pelo proprio bash e casado com a mesma regra do fallback de sempre — nenhum processo.
rastro_modo_em() {
  local _raiz="$2" _hook="$3" _tipo="${4:-metodo}" _cfg="$2/.expx/hooks.json"
  local _padrao='aviso' _m="" _txt="" _re
  [ "$_tipo" = "seguranca" ] && _padrao='bloqueio'

  if [ -f "$_cfg" ]; then
    if command -v jq >/dev/null 2>&1; then
      _m="$(jq -r --arg h "$_hook" '.hooks[$h].modo // empty' "$_cfg" 2>/dev/null)"
    else
      IFS= read -r -d '' _txt < "$_cfg"
      _re="\"$_hook\""'[[:space:]]*:[[:space:]]*\{[^}]*\}'
      if [[ $_txt =~ $_re ]]; then
        _txt="${BASH_REMATCH[0]}"
        _re='"modo"[[:space:]]*:[[:space:]]*"([^"]*)"'
        [[ $_txt =~ $_re ]] && _m="${BASH_REMATCH[1]}"
      fi
    fi
  fi
  case "$_m" in
    bloqueio|aviso|desligado) printf -v "$1" '%s' "$_m" ;;
    *)                       printf -v "$1" '%s' "$_padrao" ;;
  esac
}
rastro_modo() { local _mo; rastro_modo_em _mo "$@"; printf '%s' "$_mo"; }

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
    # O tamanho ja lido pela varredura do rastro (RASTRO_TAMANHOS) evita um `wc`.
    local tam
    case "${RASTRO_TAMANHOS:-}" in
      *"
$arq	"*) tam="${RASTRO_TAMANHOS#*"
$arq	"}"; tam="${tam%%
*}" ;;
      *) tam=$(wc -c < "$arq" 2>/dev/null) ;;
    esac
    tam="${tam//[!0-9]/}"; [ -n "$tam" ] || tam=0
    if [ "$tam" -gt 5242880 ] 2>/dev/null; then
      mv -f "$arq" "${arq%.jsonl}.1.jsonl" 2>/dev/null || true
    fi
  fi

  # Bash >= 4.2 formata a hora sem processo; o TZ vai como atribuicao do proprio
  # comando (um `local TZ` nao reconfigura o fuso no Git Bash).
  local ts
  if [ "${BASH_VERSINFO[0]:-0}" -gt 4 ] || { [ "${BASH_VERSINFO[0]:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -ge 2 ]; }; then
    TZ=UTC0 printf -v ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1
  else
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fi
  local linha tid_e detalhe_e
  rastro_json_escape_em tid_e "$tid"; rastro_json_escape_em detalhe_e "$detalhe"
  linha="{\"ts\":\"$ts\""
  linha="$linha,\"expx_eventos\":1"
  linha="$linha,\"trabalho_id\":\"$tid_e\""
  linha="$linha,\"ferramenta\":\"sprintx\""
  linha="$linha,\"origem\":\"$origem\""
  linha="$linha,\"evento\":\"$evento\""
  linha="$linha,\"fase\":${RASTRO_FASE:-null}"
  linha="$linha,\"task\":${RASTRO_TASK:-null}"
  linha="$linha,\"agente\":\"${RASTRO_AGENTE:-principal}\""
  linha="$linha,\"resultado\":\"$resultado\""
  linha="$linha,\"detalhe\":\"$detalhe_e\""
  linha="$linha,\"arquivos\":$arquivos"
  [ -n "$extras" ] && linha="$linha,$extras"
  linha="$linha}"

  if printf '%s\n' "$linha" >> "$arq" 2>/dev/null; then RASTRO_GRAVACAO=gravado; else RASTRO_GRAVACAO=falha; fi
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
# por nao conseguir escrever o proprio rastro. O desfecho fica em RASTRO_GRAVACAO
# (gravado | divergente | invalido | falha), para quem NAO pode falhar aberto — o
# scripts/rastro.sh da skill (DS-159) — saber se a linha entrou onde pediu.
rastro_grava_trabalho() {
  local raiz="$1" pedido="$2" evento="$3" origem="$4" resultado="$5" detalhe="$6"
  local arquivos="${7:-[]}" extras="${8:-}"
  RASTRO_GRAVACAO=falha

  {
    local dir="$raiz/docs/eventos"
    [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || return 0

    # O trabalho da sessao nao muda durante o processo do hook: resolve uma vez
    # (varre docs/eventos/*.jsonl) e reusa. Sem subshell: a mesma varredura deixa
    # em RASTRO_TAMANHOS o tamanho de cada arquivo, para a rotacao.
    local sessao_tid
    if [ -n "${RASTRO_TRABALHO_DA_SESSAO+x}" ]; then
      sessao_tid="$RASTRO_TRABALHO_DA_SESSAO"
    else
      rastro_trabalho_da_sessao_em sessao_tid "$raiz"
      RASTRO_TRABALHO_DA_SESSAO="$sessao_tid"
    fi

    local tid
    if [ -z "$pedido" ] || [ "$pedido" = "-" ]; then
      tid="$sessao_tid"
      [ -n "$tid" ] || tid="sem-trabalho"
    elif ! rastro_trabalho_valido "$pedido"; then
      _rastro_linha "$dir/sem-trabalho.jsonl" sem-trabalho acao_bloqueada "$origem" bloqueado \
        "trabalho_id_invalido: $evento pedido para '$pedido'" '[]' ''
      RASTRO_GRAVACAO=invalido
      return 0
    elif [ -n "$sessao_tid" ] && [ "$sessao_tid" != "$pedido" ]; then
      _rastro_linha "$dir/sem-trabalho.jsonl" sem-trabalho acao_bloqueada "$origem" bloqueado \
        "contexto_de_trabalho_divergente: $evento pedido em '$pedido', a sessao reivindica '$sessao_tid'" '[]' ''
      RASTRO_GRAVACAO=divergente
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
  _rastro_varre "$1" "$2"
  [ -z "$RASTRO_REIV" ] || printf '%s\n' "$RASTRO_REIV"
}

# _RASTRO_AWK_REIV — o miolo de rastro_reivindicacoes_da_sessao, em awk, para ser incluido
# num programa maior (o escopo-da-task decide tudo numa passada so). Cada linha de um
# docs/eventos/*.jsonl passa por `_rv_linha()`, em QUALQUER ordem de arquivo: o evento
# mais recente de cada (trabalho, task) e o de menor sufixo de rotacao e, no mesmo arquivo,
# o de linha maior — exatamente a ordem "rotacionado antes do corrente" de sempre, sem
# ordenar os argumentos por fora. `_rv_fim(sessao)` deixa em RV_L[1..RV_N] as linhas
# `trabalho TAB task TAB ok|divergente` da sessao, em ordem de byte, e RV_TAM[arquivo] o
# tamanho em bytes lido (exige LC_ALL=C).
_RASTRO_AWK_REIV='
function _rv_tid(p,   b) {
  b = p; sub(/.*\//, "", b); sub(/\.jsonl$/, "", b); _rv_rank = 0
  if (match(b, /\.[0-9]+$/)) { _rv_rank = substr(b, RSTART + 1) + 0; b = substr(b, 1, RSTART - 1) }
  return b
}
function _rv_linha(   task, k, s, d) {
  if (FILENAME != _rv_arq) { _rv_arq = FILENAME; _rv_t = _rv_tid(FILENAME); _rv_r = _rv_rank }
  RV_TAM[FILENAME] += length($0) + 1
  if (!match($0, /"task":"[^"]*"/)) return
  task = substr($0, RSTART + 8, RLENGTH - 9)
  k = _rv_t SUBSEP task
  if (index($0, "\"evento\":\"task_iniciada\"")) {
    s = ""; if (match($0, /"sessao":"[^"]*"/)) s = substr($0, RSTART + 10, RLENGTH - 11)
    d = ""; if (match($0, /"trabalho_id":"[^"]*"/)) d = substr($0, RSTART + 15, RLENGTH - 16)
  } else if (index($0, "\"evento\":\"task_concluida\"") || index($0, "\"evento\":\"task_bloqueada\"")) {
    s = ""; d = ""
  } else return
  if ((k in _rv_ri) && (_rv_r > _rv_ri[k] || (_rv_r == _rv_ri[k] && FNR < _rv_fi[k]))) return
  _rv_ri[k] = _rv_r; _rv_fi[k] = FNR; _rv_dono[k] = s; _rv_campo[k] = d
}
function _rv_fim(ses,   k, p, i, j, x) {
  RV_N = 0
  for (k in _rv_dono) {
    if (_rv_dono[k] == "" || _rv_dono[k] != ses) continue
    split(k, p, SUBSEP)
    RV_L[++RV_N] = p[1] "\t" p[2] "\t" ((_rv_campo[k] == "" || _rv_campo[k] == p[1]) ? "ok" : "divergente")
  }
  for (i = 2; i <= RV_N; i++) { x = RV_L[i]; for (j = i - 1; j >= 1 && RV_L[j] > x; j--) RV_L[j + 1] = RV_L[j]; RV_L[j + 1] = x }
}
'

# _rastro_varre <raiz> <sessao> — UMA passada de awk por docs/eventos/*.jsonl: RASTRO_REIV
# recebe as reivindicacoes ativas da sessao (o formato de rastro_reivindicacoes_da_sessao,
# sem a quebra final) e RASTRO_TAMANHOS o tamanho de cada arquivo lido (`\n<arq>\t<bytes>`),
# que _rastro_linha reaproveita. Sem subshell no chamador: os dois ficam no processo do hook.
_rastro_varre() {
  local raiz="$1" ses="$2" dir f l saida arqs=()
  RASTRO_REIV=""; RASTRO_TAMANHOS=""
  dir="$raiz/docs/eventos"
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.jsonl; do [ -f "$f" ] && arqs+=("$f"); done
  [ "${#arqs[@]}" -gt 0 ] || return 0
  saida="$(LC_ALL=C awk -v ses="$ses" "$_RASTRO_AWK_REIV"'
    { _rv_linha() }
    END {
      _rv_fim(ses)
      for (i = 1; i <= RV_N; i++) print "R\t" RV_L[i]
      for (i = 1; i < ARGC; i++) print "T\t" ARGV[i] "\t" (RV_TAM[ARGV[i]] + 0)
    }' "${arqs[@]}" 2>/dev/null)"
  while IFS= read -r l; do
    case "$l" in
      "R	"*) RASTRO_REIV="$RASTRO_REIV${RASTRO_REIV:+
}${l#R	}" ;;
      "T	"*) RASTRO_TAMANHOS="$RASTRO_TAMANHOS
${l#T	}" ;;
    esac
  done <<EOF
$saida
EOF
}
