#!/usr/bin/env bash
# transcrito-agente.sh — o que um agente NOVO nao pode ter precisado fazer para abrir e fechar
# uma task da sprintx (DS-159). Nao e executavel por si so: bancada.sh (secao U, sobre
# transcritos sinteticos) e agente-real-rastro.sh (sobre o transcrito do `claude -p`) fazem
# `source` deste arquivo.
#
# Entrada: o transcrito `--output-format stream-json` do Claude Code (uma mensagem JSON por
# linha). Cada `tool_use` do agente e julgado; qualquer violacao reprova a certificacao:
#
#   leu_hook              leu/buscou/listou .claude/hooks/** — foi descobrir protocolo privado
#   rastro_manual         escreveu em docs/eventos/ por conta propria em vez do escritor
#                         scripts/rastro.sh — redirecao, tee, sed -i, Write/Edit, cp/mv PARA o
#                         rastro, ou interpretador abrindo o rastro em modo de escrita
#   identidade_fabricada  tocou a identidade da sessao: `claude-code@`, o id da sessao, as
#                         variaveis EXPX_SESSAO/EXPX_HARNESS/CLAUDE_CODE_SESSION_ID ou uma
#                         chave "sessao"/"harness" montada a mao
#   sem_escritor_inicio   nao reivindicou a task pelo escritor (rastro.sh task-iniciada)
#   sem_escritor_fim      nao fechou a task pelo escritor (rastro.sh task-concluida)
#
# Exige jq.
#
# Alem do transcrito, este arquivo carrega a outra prova da certificacao que NAO depende do agente
# pago: `rastro_edicao_depois_do_claim`, a ordem real no rastro. As duas moram juntas para que a
# bancada julgue exatamente o codigo que a certificacao executa, sem segunda copia.

# transcrito_usos <transcrito> — uma linha por tool_use: <ferramenta> TAB <input JSON compacto>,
# com `\` trocada por `/` (caminho Windows e POSIX julgados igual).
transcrito_usos() {
  jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use")
         | .name + "\t" + (.input | walk(if type == "string" then gsub("\\\\"; "/") | gsub("[\t\n\r]"; " ") else . end) | tojson)' \
    "$1" 2>/dev/null | tr -d $'\r'
}

_TR_REDIR='(>|tee([[:space:]]+-a)?)[[:space:]]*[^[:space:]|;&]*docs/eventos'
_TR_SED='sed[[:space:]]+-i[^|;&]*docs/eventos'
# Comandos cujo destino e o ULTIMO operando. `cp docs/eventos/x /tmp/` copia o rastro PARA FORA:
# e leitura. O que viola e docs/eventos como DESTINO — por isso a regra olha a posicao.
_TR_POR_DESTINO='cp|mv|install|rsync|ln'
# Comandos que escrevem no arquivo que nomeiam, em qualquer posicao.
_TR_SO_ESCREVEM='tee|truncate|dd|shred'
# Interpretadores, e as primitivas de ESCRITA deles. Nenhuma casa uma leitura: `open(...).read()`,
# `json.load` e `print(...)` passam — conferir o rastro e permitido, escrever nele nao e.
_TR_INTERP='python[0-9.]*|perl|ruby|node'
_TR_INTERP_ESCREVE="write|writelines|write_text|write_bytes|writeFile|appendFile|copyfile|copytree|copy2|shutil|os\.rename|os\.replace|json\.dump|yaml\.dump|open\([^)]*['\"][awx][+bt]*['\"]"

# _tr_escreve_no_rastro <comando> — 0 quando o comando ESCREVE em docs/eventos.
#
# Nao e blacklist de mencao, e e deliberado: reprovar toda aparicao de `docs/eventos` reprovaria
# `cat`, `grep`, `jq`, `tail` e `wc` — a LEITURA do rastro, que o contrato permite e que o agente
# usa para conferir o que gravou. A regra olha o PAPEL do caminho em cada segmento do comando:
# destino de redirecao/tee/sed -i, ultimo operando de cp/mv/install/rsync/ln, arquivo nomeado por
# um comando que so escreve, ou argumento de interpretador junto de uma primitiva de escrita.
#
# Os segmentos saem de `|`, `;` e `&` virando quebra de linha — aproximacao deliberada: separador
# dentro de aspas separa um segmento a mais, o que no maximo torna a auditoria mais rigorosa, e
# rigor a mais numa certificacao e barato. Falso NEGATIVO e que seria caro.
_tr_escreve_no_rastro() {
  local c="$1" seg cab ult n interp=0
  [[ $c =~ $_TR_REDIR ]] && return 0
  [[ $c =~ $_TR_SED ]] && return 0
  case "$c" in *docs/eventos*) ;; *) return 1 ;; esac
  while IFS= read -r seg; do
    local tk=()
    read -r -a tk <<< "$seg"
    n=0
    while [ "$n" -lt "${#tk[@]}" ]; do
      case "${tk[$n]}" in *=*) n=$((n + 1)) ;; *) break ;; esac   # `VAR=valor cmd ...`
    done
    [ "$n" -lt "${#tk[@]}" ] || continue
    cab="${tk[$n]##*/}"; cab="${cab%.exe}"
    ult="${tk[$((${#tk[@]} - 1))]}"
    if [[ $cab =~ ^($_TR_POR_DESTINO)$ ]]; then
      case "$ult" in *docs/eventos*) return 0 ;; esac
    elif [[ $cab =~ ^($_TR_SO_ESCREVEM)$ ]]; then
      case "$seg" in *docs/eventos*) return 0 ;; esac
    fi
    [[ $cab =~ ^($_TR_INTERP)$ ]] && interp=1
    if [ "$interp" = 1 ]; then
      case "$seg" in
        *docs/eventos*) [[ $seg =~ $_TR_INTERP_ESCREVE ]] && return 0 ;;
      esac
    fi
  done <<EOF
$(printf '%s' "$c" | tr '|;&' '\n')
EOF
  return 1
}

# rastro_edicao_depois_do_claim <rastro.jsonl> <task> <regex ERE dos arquivos da task>
#
# 0 so quando a PRIMEIRA edicao de arquivo da task, no rastro, veio DEPOIS do `task_iniciada`
# daquela task. "Alguma edicao depois do claim" nao serve e era o defeito: a prova marcava a
# primeira edicao so a partir do instante em que o claim aparecia, entao uma edicao ANTES da
# reivindicacao — exatamente o que ela existe para pegar — era ignorada, e qualquer edicao
# legitima posterior fazia a certificacao passar.
rastro_edicao_depois_do_claim() {
  [ -f "$1" ] || return 1
  awk -v t="$2" -v re="$3" '
    /"evento":"task_iniciada"/ && index($0, "\"task\":\"" t "\"") && !i { i = NR }
    /"evento":"arquivo_alterado"/ && $0 ~ re && !a { a = NR }
    END { exit (i && a && a > i) ? 0 : 1 }
  ' "$1" 2>/dev/null
}

# transcrito_verifica <transcrito> <id-da-sessao> <slug> <task> — imprime uma violacao por
# linha (`<regra>: <ferramenta> <trecho>`); retorna 0 so quando nao ha nenhuma.
transcrito_verifica() {
  local tr="$1" sid="$2" slug="$3" task="$4" usos l f inp cmd v="" ini=0 fim=0
  [ -s "$tr" ] || { printf 'transcrito_vazio: %s\n' "$tr"; return 1; }
  [ -n "$sid" ] || { printf 'sessao_nao_informada\n'; return 1; }
  usos="$(transcrito_usos "$tr")"
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    f="${l%%	*}"; inp="${l#*	}"
    case "$inp" in
      *.claude/hooks*) v="${v}leu_hook: $f ${inp:0:160}
" ;;
    esac
    case "$f" in
      Write|Edit|MultiEdit|NotebookEdit)
        case "$inp" in *docs/eventos*) v="${v}rastro_manual: $f ${inp:0:160}
" ;; esac ;;
      Bash)
        # O comando, nao o JSON em volta: sem o escape do JSON a posicao de cada operando e
        # legivel, e e a posicao que separa escrever no rastro de LER o rastro (cat, grep, jq,
        # tail, wc, 2>/dev/null) — leitura que o contrato permite.
        cmd="$(printf '%s' "$inp" | jq -r '.command // empty' 2>/dev/null)"
        [ -n "$cmd" ] || cmd="$inp"
        if _tr_escreve_no_rastro "$cmd"; then
          v="${v}rastro_manual: $f ${inp:0:160}
"
        fi ;;
    esac
    case "$inp" in
      *claude-code@*|*EXPX_SESSAO*|*EXPX_HARNESS*|*CLAUDE_CODE_SESSION_ID*|*'"sessao"'*|*'\"sessao\"'*|*'\"harness\"'*|*"$sid"*)
        v="${v}identidade_fabricada: $f ${inp:0:160}
" ;;
    esac
    if [ "$f" = Bash ]; then
      case "$inp" in *scripts/rastro.sh*task-iniciada*"$slug"*"$task"*) ini=1 ;; esac
      case "$inp" in *scripts/rastro.sh*task-concluida*"$slug"*"$task"*) fim=1 ;; esac
    fi
  done <<EOF
$usos
EOF
  [ "$ini" = 1 ] || v="${v}sem_escritor_inicio: nenhum rastro.sh task-iniciada $slug $task
"
  [ "$fim" = 1 ] || v="${v}sem_escritor_fim: nenhum rastro.sh task-concluida $slug $task
"
  printf '%s' "$v"
  [ -z "$v" ]
}
