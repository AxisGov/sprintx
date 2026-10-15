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
# Comandos em que o PRIMEIRO operando e origem e os demais, destino. `cp docs/eventos/x /tmp/`
# copia o rastro PARA FORA: e leitura. O que viola e docs/eventos como DESTINO — por isso a regra
# olha a posicao. Olhar so o ULTIMO token era o defeito: `cp origem docs/eventos/x 2>/dev/null`
# termina no redirecionamento, e `cp -t docs/eventos/ origem` nomeia o destino na OPCAO.
_TR_POR_DESTINO='cp|mv|install|rsync|ln'
# Comandos que escrevem no arquivo que nomeiam, em qualquer posicao. `dd` e a excecao: nomeia os
# dois lados, `if=` origem e `of=` destino — tratado a parte.
_TR_SO_ESCREVEM='tee|truncate|dd|shred'
# Tokens de redirecionamento (`>f`, `>>f`, `2>/dev/null`, `<f`, `<<P`): nao sao operandos, e
# confundi-los com operando esconde o destino real. O segundo padrao e o operador SOZINHO
# (`cp a b > /dev/null`), em que o nome do arquivo vem no token seguinte.
_TR_TOKEN_REDIR='^[0-9]*(>|<)'
_TR_TOKEN_REDIR_SO='^[0-9]*(>>?|<<?)$'
# Comandos de LEITURA conhecidos, que nao escrevem no arquivo que nomeiam. Existem para cortar o
# estado PEGAJOSO do interpretador: num comando de varios segmentos, `python3 -c "..."` ligava o
# estado de escrita e o segmento seguinte o herdava, entao `grep -c write docs/eventos/fx.jsonl`
# reprovava pela palavra `write` — que ali e o PADRAO do grep, nao primitiva nenhuma.
_TR_SO_LEEM='cat|tac|grep|egrep|fgrep|zgrep|rg|jq|yq|head|tail|wc|nl|od|xxd|cmp|md5sum|sha1sum|sha256sum|cut|sort|uniq|column|awk|sed|less|more'
# Interpretadores, e as primitivas de ESCRITA deles. Nenhuma casa uma leitura: `open(...).read()`,
# `json.load` e `print(...)` passam — conferir o rastro e permitido, escrever nele nao e.
_TR_INTERP='python[0-9.]*|perl|ruby|node'
_TR_INTERP_ESCREVE="write|writelines|write_text|write_bytes|writeFile|appendFile|copyfile|copytree|copy2|shutil|os\.rename|os\.replace|json\.dump|yaml\.dump|open\([^)]*['\"][awx][+bt]*['\"]"
# Wrappers TRANSPARENTES: executam OUTRO comando sem mudar o arquivo que ele escreve. `env cp ...`,
# `timeout 5 cp ...` e `sudo cp ...` escrevem exatamente o que `cp ...` escreve, e julgar o wrapper
# como se fosse o comando era nao achar escrita nenhuma — nome fora de toda lista, segmento
# ignorado. O basename da linha do `cab` ja resolve `/usr/bin/env`.
#
# LIMITE REGISTRADO, sem promessa de cobertura: wrapper que recebe o comando como SCRIPT numa string
# (`bash -c '...'`, `sh -c`, `cmd //c`, `powershell -Command`) NAO e atravessado aqui. O argumento
# ali e um programa inteiro, com citacao e expansao proprias; cobrir isso pede um parser de shell,
# nao um nome a mais nesta lista.
_TR_WRAPPER='env|command|exec|builtin|nohup|nice|ionice|stdbuf|setsid|winpty|sudo|doas|time|timeout|xargs'

# _tr_opcao_destino <opcao longa> — 0 quando a opcao e `--target-directory` ou uma ABREVIACAO dela
# (`--targ`, `--target-director`), que o getopt do GNU aceita igual a forma inteira.
# `--no-target-directory` nao e prefixo dela e nao casa.
_tr_opcao_destino() {
  local o="${1#--}"
  [ -n "$o" ] || return 1
  case target-directory in "$o"*) return 0 ;; esac
  return 1
}

# _tr_escreve_no_rastro <comando> — 0 quando o comando ESCREVE em docs/eventos.
#
# Nao e blacklist de mencao, e e deliberado: reprovar toda aparicao de `docs/eventos` reprovaria
# `cat`, `grep`, `jq`, `tail` e `wc` — a LEITURA do rastro, que o contrato permite e que o agente
# usa para conferir o que gravou. A regra olha o PAPEL do caminho em cada segmento do comando:
# destino de redirecao/tee/sed -i, destino (nao a origem) de cp/mv/install/rsync/ln, `of=` do dd,
# arquivo nomeado por um comando que so escreve, ou argumento de interpretador junto de uma
# primitiva de escrita. Tokens de redirecionamento saem antes da conta das posicoes, e um segmento
# encabecado por comando de leitura conhecido nao herda escrita do segmento anterior.
#
# Os segmentos saem de `|`, `;` e `&` virando quebra de linha — aproximacao deliberada: separador
# dentro de aspas separa um segmento a mais, o que no maximo torna a auditoria mais rigorosa, e
# rigor a mais numa certificacao e barato. Falso NEGATIVO e que seria caro.
_tr_escreve_no_rastro() {
  local c="$1" seg cab t n i oparg interp=0
  [[ $c =~ $_TR_REDIR ]] && return 0
  [[ $c =~ $_TR_SED ]] && return 0
  case "$c" in *docs/eventos*) ;; *) return 1 ;; esac
  while IFS= read -r seg; do
    local tk=() op=() pula=0 destino="" origem=""
    read -r -a tk <<< "$seg"
    n=0
    # Atravessa os wrappers transparentes ate o comando REAL. Cada volta come um wrapper, as
    # opcoes dele — levando o valor junto quando a opcao recebe o valor em token SEPARADO, sem o
    # que `sudo -u deploy cp ...` acharia `deploy` no lugar de `cp` — e a duracao posicional do
    # `timeout`.
    while :; do
      while [ "$n" -lt "${#tk[@]}" ]; do
        case "${tk[$n]}" in *=*) n=$((n + 1)) ;; *) break ;; esac   # `VAR=valor cmd ...`
      done
      [ "$n" -lt "${#tk[@]}" ] || break
      cab="${tk[$n]##*/}"; cab="${cab%.exe}"
      [[ $cab =~ ^($_TR_WRAPPER)$ ]] || break
      case "$cab" in
        sudo|doas) oparg='-[ugUChprtT]|--(user|group|host|prompt|role|type|chdir|other-user)' ;;
        xargs)     oparg='-[IiLnPsdEae]|--(replace|max-lines|max-args|max-procs|max-chars|delimiter|eof|arg-file|process-slot-var)' ;;
        env)       oparg='-[uSC]|--(unset|split-string|chdir)' ;;
        timeout)   oparg='-[sk]|--(signal|kill-after)' ;;
        nice)      oparg='-n|--adjustment' ;;
        ionice)    oparg='-[cnpPu]|--(class|classdata|pid|pgid|uid)' ;;
        stdbuf)    oparg='-[ioe]|--(input|output|error)' ;;
        time)      oparg='-[fo]|--(format|output)' ;;
        exec)      oparg='-a' ;;
        *)         oparg='' ;;
      esac
      n=$((n + 1))
      while [ "$n" -lt "${#tk[@]}" ]; do
        t="${tk[$n]}"
        case "$t" in -?*) ;; *) break ;; esac   # `-` sozinho e operando, nao opcao
        if [ -n "$oparg" ] && [[ $t =~ ^($oparg)$ ]]; then n=$((n + 2)); else n=$((n + 1)); fi
      done
      # `timeout 5 cp ...`: a duracao e POSICIONAL. Sem comer esse token, o `5` passaria por
      # comando real e a escrita atras dele ficaria invisivel.
      if [ "$cab" = timeout ] && [ "$n" -lt "${#tk[@]}" ]; then n=$((n + 1)); fi
    done
    [ "$n" -lt "${#tk[@]}" ] || continue
    # Os OPERANDOS do segmento, sem os tokens de redirecionamento: e entre eles, e so entre eles,
    # que origem e destino tem posicao.
    for ((i = n + 1; i < ${#tk[@]}; i++)); do
      t="${tk[$i]}"
      if [ "$pula" = 1 ]; then pula=0; continue; fi
      if [[ $t =~ $_TR_TOKEN_REDIR ]]; then
        [[ $t =~ $_TR_TOKEN_REDIR_SO ]] && pula=1
        continue
      fi
      op+=("$t")
    done
    # Um leitor conhecido nao escreve, e nao herda estado de escrita de segmento anterior. O `(`
    # desqualifica a linha: `cut = open('docs/eventos/x','w')` dentro de um heredoc de python tem
    # nome de comando de leitura no inicio e nao e leitura nenhuma.
    if [[ $cab =~ ^($_TR_SO_LEEM)$ ]] && [[ $seg != *'('* ]]; then
      interp=0
      continue
    fi
    if [[ $cab =~ ^($_TR_POR_DESTINO)$ ]]; then
      # `-t dir` / `--target-directory=dir`: o destino esta na OPCAO, e pode vir ANEXADO a ela —
      # `-tdocs/eventos/`, `-atdocs/eventos/`, `--targ=docs/eventos/`. Aceitar so a forma canonica
      # era o defeito: bastava colar o destino na opcao, ou abreviar a opcao longa, para a escrita
      # ficar invisivel. `rsync` fica fora porque ali `-t` e preservar data, e o destino continua
      # posicional.
      for ((i = 0; i < ${#op[@]}; i++)); do
        t="${op[$i]}"
        case "$t" in
          --*=*) _tr_opcao_destino "${t%%=*}" && destino="${t#*=}" ;;
          --*)   _tr_opcao_destino "$t" && destino="${op[$((i + 1))]-}" ;;
          -*t*)  if [ "$cab" != rsync ]; then
                   # No bloco curto o `t` exige valor, entao o resto do token DEPOIS dele e o
                   # valor; bloco terminado em `t` (`-t`, `-at`) pega o token seguinte. Em
                   # cp/mv/install/ln o `t` minusculo so significa diretorio-alvo.
                   destino="${t#*t}"
                   [ -n "$destino" ] || destino="${op[$((i + 1))]-}"
                 fi ;;
        esac
      done
      if [ -n "$destino" ]; then
        case "$destino" in *docs/eventos*) return 0 ;; esac
      else
        # Forma posicional: o primeiro operando e ORIGEM, qualquer outro e destino.
        for ((i = 0; i < ${#op[@]}; i++)); do
          case "${op[$i]}" in -*) continue ;; esac
          if [ -z "$origem" ]; then origem="${op[$i]}"; continue; fi
          case "${op[$i]}" in *docs/eventos*) return 0 ;; esac
        done
      fi
    elif [[ $cab =~ ^($_TR_SO_ESCREVEM)$ ]]; then
      if [ "$cab" = dd ]; then
        # `dd` nomeia os DOIS lados por opcao: so `of=` e destino. `if=docs/eventos/x` despeja o
        # rastro na saida padrao, e e leitura — se a saida for redirecionada PARA o rastro, quem
        # pega e a regra de redirecao, la em cima.
        for ((i = 0; i < ${#op[@]}; i++)); do
          case "${op[$i]}" in of=*) destino="${op[$i]#of=}" ;; if=*) origem="${op[$i]#if=}" ;; esac
        done
        if [ -n "$destino" ]; then
          case "$destino" in *docs/eventos*) return 0 ;; esac
        elif [ -z "$origem" ]; then
          case "$seg" in *docs/eventos*) return 0 ;; esac
        fi
      else
        case "$seg" in *docs/eventos*) return 0 ;; esac
      fi
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
