#!/usr/bin/env bash
#
# Secoes V a Z da bancada: HISTORICO.md, fallback sem jq e calibracao.
# Carregada por `.` de dentro da bancada.sh, no mesmo ponto e na mesma ordem: usa os
# auxiliares e o estado dela. Mora aqui porque o CodeAnt pula arquivo acima de 5.000 linhas
# ou 200 KB (expxdev, docs/superpowers/specs/2026-10-19-limites-do-codeant-emenda.md).

echo "== V. duracao_observada chega a todo contrato do HISTORICO.md (D-05) =="
# O rastro mede o tempo de parede de cada task (par task_iniciada/task_concluida) e
# 06-execucao.md / 08-rastro.md mandam persisti-lo no HISTORICO.md como duracao_observada
# (DS-37). O contrato do kind, o template e a lista de campos da estimativa precisam
# carregar o mesmo campo — senao a instrucao existe e nao tem onde pousar.
V_SCH="$SK/references/00-schema.md"
V_TPL="$SK/assets/TEMPLATE-HISTORICO.md"
V_EST="$SK/references/07-estimativa.md"
V_EXE="$SK/references/06-execucao.md"

# Regiao de uma entrada (entre 'entradas:' e 'calibracao:') e a regiao da calibracao,
# nos dois arquivos que carregam o frontmatter do kind.
v_entradas() { awk '/^entradas:/{f=1;next} /^calibracao:/{f=0} f' "$1"; }
v_calibracao() { awk '/^calibracao:/{f=1;next} f && /^---/{f=0} f' "$1"; }
v_colunas() { printf '%s' "$1" | awk -F'|' '{print NF}'; }

# 1. A instrucao que origina o campo continua de pe nas duas referencias que a mandam.
tem "$V_EXE" 'entra no `HISTORICO.md` como `duracao_observada`'; afirma "v1-execucao-manda-persistir" $? "06-execucao.md Passo 3"
tem "$SK/references/08-rastro.md" 'O valor entra como **`duracao_observada`**'; afirma "v1b-rastro-manda-persistir" $? "08-rastro.md"

# 2. O kind estimativa_historico carrega o campo na entrada do exemplo.
v_entradas "$V_SCH" | grep -qF 'duracao_observada:'; afirma "v2-schema-entrada-tem-campo" $? "00-schema.md, exemplo do kind"

# 3. Opcional/nullable: sem o par de eventos, nao ha valor — e legado sem a chave nao e recusado.
tem "$V_SCH" '`duracao_observada` é **opcional**'; afirma "v3-schema-opcional" $? "declarado opcional"
tem "$V_SCH" '`null` quando o par `task_iniciada`/`task_concluida` do rastro não existe'; afirma "v3b-schema-null-sem-par" $? "null sem par de eventos"
tem "$V_SCH" 'Entrada legada sem a chave é lida como `duracao_observada: null`, nunca recusada.'; afirma "v3c-schema-legado-aceito" $? "compatibilidade com historico antigo"

# 4. Distinto de real: tempo de parede nao e esforco, e nunca o substitui (DS-37).
tem "$V_SCH" '`duracao_observada` **não é `real`** e nunca o substitui'; afirma "v4-schema-distinto-de-real" $? "campo separado de real"

# 5. Fora do desvio e fora da calibracao: nao contamina o numero que calibra estimativa.
tem "$V_SCH" 'fica **fora do cálculo de `desvio`**'; afirma "v5-schema-fora-do-desvio" $? "desvio continua real/estimado_media"
tem "$V_SCH" 'e **fora da `calibracao`**'; afirma "v5b-schema-fora-da-calibracao" $? "desvio_medio e fator_ativo nao a leem"
v_calibracao "$V_SCH" | grep -qF 'duracao_observada'; [ $? -ne 0 ]; afirma "v5c-schema-calibracao-limpa" $? "bloco calibracao nao carrega o campo"
# A entrada coloca duracao_observada DEPOIS de desvio: a cadeia de calibracao termina em desvio.
V_LD=$(v_entradas "$V_SCH" | grep -nF 'desvio:' | head -1 | cut -d: -f1)
V_LO=$(v_entradas "$V_SCH" | grep -nF 'duracao_observada:' | head -1 | cut -d: -f1)
[ -n "$V_LD" ] && [ -n "$V_LO" ] && [ "$V_LO" -gt "$V_LD" ]; afirma "v5d-schema-campo-depois-do-desvio" $? "desvio=$V_LD < duracao_observada=$V_LO"

# 6. O template que gera o arquivo carrega o campo no YAML, opcional.
v_entradas "$V_TPL" | grep -qF 'duracao_observada: {{numero ou null}}'; afirma "v6-template-yaml-tem-campo" $? "TEMPLATE-HISTORICO.md, entradas"
v_calibracao "$V_TPL" | grep -qF 'duracao_observada'; [ $? -ne 0 ]; afirma "v6b-template-calibracao-limpa" $? "calibracao do template nao carrega o campo"

# 7. Regra universal 7: o YAML e a tabela humana dizem a mesma coisa.
tem "$V_TPL" 'Duração observada'; afirma "v7-template-tabela-tem-coluna" $? "coluna na tabela de Entradas"
V_H=$(grep -F '| Trabalho | Task | Tipo |' "$V_TPL" | head -1)
V_SEP=$(grep -nF '| Trabalho | Task | Tipo |' "$V_TPL" | head -1 | cut -d: -f1)
V_SEP=$(sed -n "$((V_SEP + 1))p" "$V_TPL")
V_LIN=$(grep -F '| {{slug}} |' "$V_TPL" | head -1)
[ "$(v_colunas "$V_H")" = "$(v_colunas "$V_SEP")" ] && [ "$(v_colunas "$V_H")" = "$(v_colunas "$V_LIN")" ]
afirma "v7b-template-tabela-coerente" $? "cabecalho=$(v_colunas "$V_H") separador=$(v_colunas "$V_SEP") linha=$(v_colunas "$V_LIN")"
# 7.1 Ausencia nao vira numero com unidade: `duracao_observada` e null de rotina
# (rastro desligado, sem par de eventos), e `null h` leria como "null horas", misturando
# ausencia com grandeza. A regra da celula vazia vale para a tabela inteira.
tem "$V_TPL" 'a célula correspondente da tabela leva `—`, nunca `null` e nunca `null h`'
afirma "v11-regra-da-celula-sem-valor" $? "a tabela diz como ausencia se escreve"
V_CEL="$(grep -F '| {{slug}} |' "$V_TPL" | head -1 | awk -F'|' '{print $(NF-1)}')"
printf '%s' "$V_CEL" | grep -qE '\}\}[[:space:]]*h[[:space:]]*$'; [ $? -ne 0 ]
afirma "v11b-duracao-sem-unidade-fora-do-marcador" $? "celula=[$V_CEL]"
V_SIM="$(printf '%s' "$V_CEL" | sed 's/{{[^}]*}}/null/g')"
printf '%s' "$V_SIM" | grep -qE 'null[[:space:]]+h'; [ $? -ne 0 ]
afirma "v11c-nulo-nao-renderiza-null-h" $? "render=[$V_SIM]"

# 8. A lista de campos da estimativa (F3.5, Passo 10) nomeia o campo.
tem "$V_EST" '`duracao_observada`'; afirma "v8-estimativa-lista-o-campo" $? "07-estimativa.md Passo 10"
# A lista do Passo 10 (F3.5) e a do Passo 3 (F6) descrevem a MESMA entrada do
# `estimativa_historico`: divergir em um campo faz a skill gravar coisas diferentes
# conforme a referencia que a sessao abriu.
v_campos() { # v_campos <arquivo> <ancora da linha> — campos `x` daquela lista, ordenados
  grep -F "$2" "$1" | head -1 \
    | sed 's/.*com: //; s/\. .*//; s/\.$//' \
    | grep -oE '`[a-z_]+`' | tr -d '`' | sort -u
}
V_C7="$(v_campos "$V_EST" 'recebe uma linha por task concluída')"
V_C6="$(v_campos "$V_EXE" 'Uma entrada por task **concluída**, com:')"
printf '%s' "$V_C7" | grep -qx 'estimado_media'; afirma "v10-estimativa-lista-estimado-media" $? "Passo 10 nomeia estimado_media"
[ "$V_C7" = "$V_C6" ]; afirma "v10b-listas-de-campos-coerentes" $? "F3.5 e F6 listam os mesmos campos${V_C7:+ ($(printf '%s' "$V_C7" | grep -c '') x $(printf '%s' "$V_C6" | grep -c ''))}"

# 9. A lista de campos da propria F6 nomeia o campo que a prosa dela manda gravar.
V_LISTA=$(grep -F 'Uma entrada por task **concluída**, com:' "$V_EXE" | head -1)
printf '%s' "$V_LISTA" | grep -qF 'duracao_observada'; afirma "v9-execucao-lista-o-campo" $? "lista do Passo 3 bate com a prosa do Passo 3"

echo "== W. fallback sem jq decodifica os escapes do payload (D-06) =="
# Sem jq, rastro_tool_input_get extraia o valor com grep -o + sed e NAO decodificava os
# escapes de JSON: `content` voltava numa linha so, com \n literais. O awk de
# task-reivindicada.sh (/^  - id:/) nao casava nada, IDS_EM_ANDAMENTO saia vazio e o hook
# falhava ABERTO (exit 0) onde devia bloquear (exit 2). O helper correto — sem processo,
# com aspa escapada e \n decodificados — ja existia no mesmo arquivo: rastro_json_campo_em.
W_DIR="$(mktemp -d)"
# Raiz dos hooks em forma absoluta: os casos abaixo rodam com `cd` na fixture.
W_H="$(cd "$H" && pwd)"

# Um PATH equivalente ao atual, sem nenhum `jq` executavel: so os diretorios que de fato
# tem jq viram espelho de symlinks sem ele. Funciona com jq em ~/.local/bin ou em /usr/bin,
# e e no-op na maquina que nao tem jq.
w_path_sem_jq() {
  local d f espelho novo="" i=0 IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    if [ -x "$d/jq" ] || [ -x "$d/jq.exe" ]; then
      i=$((i+1)); espelho="$W_DIR/bin$i"
      if [ ! -d "$espelho" ]; then
        mkdir -p "$espelho"
        for f in "$d"/*; do
          [ -e "$f" ] || continue
          case "${f##*/}" in jq|jq.exe) continue ;; esac  # Git Bash: jq.exe
          ln -sf "$f" "$espelho/${f##*/}" 2>/dev/null
        done
      fi
      novo="$novo:$espelho"
    else
      novo="$novo:$d"
    fi
  done
  printf '%s' "${novo#:}"
}
W_SEMJQ="$(w_path_sem_jq)"
PATH="$W_SEMJQ" command -v jq >/dev/null 2>&1; [ $? -ne 0 ]
afirma "w0-sandbox-esconde-jq" $? "o PATH do caso nao enxerga jq"

# Extrator isolado: le a chave pelo helper publico e grava o valor cru num arquivo, para
# que a comparacao nao dependa de substituicao de comando (que come newline do fim).
cat > "$W_DIR/extrai.sh" <<'SH'
. "$1/comum/rastro.sh"
J="$(cat "$2")"
V="$(rastro_tool_input_get "$J" "$3")"
printf '%s' "$V" > "$4"
SH

# O payload real do harness: content e o tasks.md inteiro, escapado como JSON.
W_TASKS="$W_DIR/tasks-fonte.md"
cat > "$W_TASKS" <<'YAML'
---
expx_schema: 1
expx_tool: sprintx
kind: tasks
trabalho_id: feat-w
sprint_id: sprint-01
tasks:
  - id: T-01.01
    status: em_andamento
    teste_integracao: Chama o endpoint de exportacao
    arquivos:
      cria: []
      altera: [src/a.ts]
---
YAML
W_FX="$W_DIR/repo"
mkdir -p "$W_FX/.git" "$W_FX/docs/sprintx/features/feat-w/sprint-01" "$W_FX/docs/eventos" "$W_FX/.expx"
cp "$W_TASKS" "$W_FX/docs/sprintx/features/feat-w/sprint-01/tasks.md"
W_PAY="$W_DIR/payload.json"
python3 -c "
import json, sys
print(json.dumps({'cwd': sys.argv[1], 'tool_name': 'Write',
  'tool_input': {'file_path': sys.argv[2], 'content': open(sys.argv[3], encoding='utf-8').read()}}))
" "$W_FX" "$W_FX/docs/sprintx/features/feat-w/sprint-01/tasks.md" "$W_TASKS" > "$W_PAY"

# 1. Sem jq, o content volta com linhas DE VERDADE — e o awk do hook acha o id.
PATH="$W_SEMJQ" bash "$W_DIR/extrai.sh" "$W_H" "$W_PAY" content "$W_DIR/sem.txt"
W_L=$(wc -l < "$W_DIR/sem.txt")
[ "$W_L" -ge 10 ]; afirma "w1-sem-jq-content-tem-linhas-reais" $? "$W_L linhas (esperado >= 10)"
grep -qF '\n' "$W_DIR/sem.txt"; [ $? -ne 0 ]; afirma "w1b-sem-jq-sem-barra-n-literal" $? "nenhum \\n literal sobrou"
W_IDS="$(awk '/^  - id:/ { id = $3; sub(/^[ \t]+/, "", id) } /status:[ \t]*em_andamento/ { if (id != "") print id }' "$W_DIR/sem.txt")"
[ "$W_IDS" = "T-01.01" ]; afirma "w1c-sem-jq-awk-do-hook-acha-o-id" $? "IDS_EM_ANDAMENTO=[$W_IDS]"

# 2. Paridade: com jq e sem jq entregam exatamente o mesmo valor.
bash "$W_DIR/extrai.sh" "$W_H" "$W_PAY" content "$W_DIR/com.txt"
cmp -s "$W_DIR/com.txt" "$W_DIR/sem.txt"; afirma "w2-paridade-com-jq-e-sem-jq" $? "content identico nos dois caminhos"
bash "$W_DIR/extrai.sh" "$W_H" "$W_PAY" file_path "$W_DIR/fc.txt"
PATH="$W_SEMJQ" bash "$W_DIR/extrai.sh" "$W_H" "$W_PAY" file_path "$W_DIR/fs.txt"
cmp -s "$W_DIR/fc.txt" "$W_DIR/fs.txt" && grep -qF 'sprint-01/tasks.md' "$W_DIR/fs.txt"
afirma "w2b-file-path-nao-regride" $? "file_path identico e correto sem jq"

# 3. Aspa escapada dentro do valor nao trunca (o `[^"]*` do fallback antigo parava nela).
python3 -c "
import json
print(json.dumps({'cwd': '/x', 'tool_input': {'content': 'a: \"entre aspas\"\nb: fim'}}))
" > "$W_DIR/aspas.json"
PATH="$W_SEMJQ" bash "$W_DIR/extrai.sh" "$W_H" "$W_DIR/aspas.json" content "$W_DIR/aspas.txt"
grep -qF 'b: fim' "$W_DIR/aspas.txt"; afirma "w3-sem-jq-aspa-escapada-nao-trunca" $? "valor inteiro preservado"

# 4. Ponta a ponta: o caso que reprovou. Modo bloqueio, task aberta por OUTRA sessao.
printf '%s\n' '{"ts":"2026-09-30T10:00:00Z","expx_eventos":1,"trabalho_id":"feat-w","ferramenta":"sprintx","origem":"skill","evento":"task_iniciada","fase":"f6","task":"T-01.01","agente":"principal","resultado":"ok","detalhe":null,"arquivos":[],"sessao":"opencode@outra","harness":"opencode"}' \
  > "$W_FX/docs/eventos/feat-w.jsonl"
echo '{"hooks":{"task-reivindicada":{"modo":"bloqueio"}}}' > "$W_FX/.expx/hooks.json"
w_hook() { # w_hook <PATH> -> ecoa o exit code do hook
  local rc
  (cd "$W_FX" && PATH="$1" EXPX_SESSAO=sessao-minha bash "$W_H/sprintx/task-reivindicada.sh" < "$W_PAY" >/dev/null 2>&1)
  rc=$?; printf '%s' "$rc"
}
W_RC_SEM="$(w_hook "$W_SEMJQ")"
[ "$W_RC_SEM" = 2 ]; afirma "w4-sem-jq-hook-bloqueia" $? "exit=$W_RC_SEM (esperado 2)"
W_RC_COM="$(w_hook "$PATH")"
[ "$W_RC_COM" = 2 ]; afirma "w4b-com-jq-hook-continua-bloqueando" $? "exit=$W_RC_COM (esperado 2)"

# 5. Guarda estrutural: nenhum leitor do payload volta ao grep tolerante que perdia escape.
grep -qF 'grep -o "\"$chave\"' "$W_H/comum/rastro.sh"; [ $? -ne 0 ]
afirma "w5-sem-grep-tolerante-no-rastro" $? "os fallbacks usam o helper que decodifica"

# 6. `\uXXXX` tambem e escape de JSON. Sem jq ele ficava literal e — pior — o ramo
# `*\u*` do case era o PRIMEIRO, entao engolia os outros escapes: um unico acento
# (`é` -> `é`) devolvia `content` numa linha so e ressuscitava o defeito do w4.
w_u() { # w_u <texto> <arquivo-saida> <PATH> — extrai `content` daquele texto
  python3 -c 'import json,sys; print(json.dumps({"cwd":"/x","tool_input":{"content":sys.argv[1]}}))' "$1" > "$W_DIR/u.json"
  PATH="$3" bash "$W_DIR/extrai.sh" "$W_H" "$W_DIR/u.json" content "$2"
}
W_BMP="a$(printf 'é')b"
w_u "$W_BMP" "$W_DIR/u-sem.txt" "$W_SEMJQ"; w_u "$W_BMP" "$W_DIR/u-com.txt" "$PATH"
cmp -s "$W_DIR/u-sem.txt" "$W_DIR/u-com.txt" && grep -qF "$W_BMP" "$W_DIR/u-sem.txt"
afirma "w6-sem-jq-decodifica-bmp" $? "\\u00e9 vira o mesmo byte que o jq entrega"
W_SUR="x$(printf '\U0001F600')y"
w_u "$W_SUR" "$W_DIR/u2-sem.txt" "$W_SEMJQ"; w_u "$W_SUR" "$W_DIR/u2-com.txt" "$PATH"
cmp -s "$W_DIR/u2-sem.txt" "$W_DIR/u2-com.txt" && grep -qF "$W_SUR" "$W_DIR/u2-sem.txt"
afirma "w6b-sem-jq-decodifica-par-substituto" $? "\\ud83d\\ude00 vira um caractere so, fora do BMP"
W_MIX="linha1
linha2 com acento a$(printf 'é')b"
w_u "$W_MIX" "$W_DIR/u3-sem.txt" "$W_SEMJQ"
W_UL=$(wc -l < "$W_DIR/u3-sem.txt")
[ "$W_UL" -ge 1 ]; afirma "w7-u-nao-engole-os-outros-escapes" $? "$W_UL linha(s) reais (esperado >= 1)"
W_TUDO="a$(printf 'é')b$(printf '\t')c$(printf '\U0001F600')d
fim"
w_u "$W_TUDO" "$W_DIR/u4-sem.txt" "$W_SEMJQ"; w_u "$W_TUDO" "$W_DIR/u4-com.txt" "$PATH"
cmp -s "$W_DIR/u4-sem.txt" "$W_DIR/u4-com.txt"
afirma "w7b-paridade-total-dos-escapes" $? "BMP + controle + par substituto + \\n: igual byte a byte"
rm -rf "$W_DIR"

echo "== X. calibracao vazia tem forma canonica na tabela do HISTORICO.md (D-08) =="
# `calibracao: []` e estado valido e inevitavel do `kind: estimativa_historico` — o primeiro
# trabalho do projeto, e todo trabalho que rodou sem a F3.5, fecham com desvio nenhum por tipo.
# O template tinha a linha de dados parametrizada da tabela de calibracao, mas nenhum ponto
# canonico dizia como a tabela humana fica com a lista vazia. A regra generica de celula ausente
# manda `—`, e a execucao produziu honestamente `| — | — | — | — |`: uma linha de dados anunciando
# um `tipo_task` fora do enum, que o leitor limitado recusa como tabela corrompida. A forma
# canonica e a tabela com cabecalho e separador e NENHUMA linha de dados.
X_TPL="$SK/assets/TEMPLATE-HISTORICO.md"
X_SCH="$SK/references/00-schema.md"
X_EXE="$SK/references/06-execucao.md"

# Bloco `calibracao:` do frontmatter, e a tabela de calibracao da prosa (do cabecalho ate a
# primeira linha que nao e de tabela). Helpers proprios: a secao se le sozinha.
x_calibracao() { awk '/^calibracao:/{f=1;next} f && /^---/{f=0} f' "$1"; }
x_tabela() { awk '/^\| Tipo de task \| Entradas \|/{f=1} f && !/^\|/{exit} f' "$1"; }
x_linhas_de_dados() { x_tabela "$1" | awk 'NR>2'; }

# 1. A tabela existe com cabecalho e separador — a forma que sobrevive a lista vazia.
X_CAB="$(x_tabela "$X_TPL" | sed -n 1p)"
X_SEP="$(x_tabela "$X_TPL" | sed -n 2p)"
[ -n "$X_CAB" ] && printf '%s' "$X_SEP" | grep -qE '^\|[-:| ]+\|$'
afirma "x1-tabela-tem-cabecalho-e-separador" $? "separador=[$X_SEP]"

# 2. Uma linha de dados por item de `calibracao`, nunca mais, nunca menos: linha de dados sem
#    item correspondente no frontmatter e linha fabricada, e e o que a tabela vazia dispensa.
X_ITENS=$(x_calibracao "$X_TPL" | grep -cE '^[[:space:]]*-[[:space:]]+tipo_task:')
X_DADOS=$(x_linhas_de_dados "$X_TPL" | grep -c '^|')
[ "$X_ITENS" = "$X_DADOS" ]
afirma "x2-uma-linha-de-dados-por-item" $? "itens em calibracao=$X_ITENS linhas de dados=$X_DADOS"

# 3. Nenhuma linha de dados por sentinela: `—`, `n/a`, celula vazia ou `null` no primeiro campo
#    nao e linha de dados — e um `tipo_task` fora do enum.
x_sentinela() { # x_sentinela <arquivo> — linhas de dados cujo primeiro campo e sentinela
  x_linhas_de_dados "$1" | awk -F'|' '{ c=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", c)
    if (c == "" || c == "—" || c == "-" || c == "null" || tolower(c) == "n/a") print }'
}
X_SENT="$(x_sentinela "$X_TPL" | tr '\n' ' ')"
[ -z "$X_SENT" ]
afirma "x3-nenhuma-linha-sentinela-na-tabela" $? "linhas sentinela=[$X_SENT]"
# 3b. E em nenhum dos tres pontos canonicos existe linha de tabela comecando por sentinela:
#     `| — | — | — | — |` reintroduzido como forma permitida e o defeito que isto mata.
X_SENT_ALL="$(grep -nE '^\|[[:space:]]*(—|-|n/a|N/A|null)?[[:space:]]*\|' "$X_TPL" "$X_SCH" "$X_EXE" | tr '\n' ' ')"
[ -z "$X_SENT_ALL" ]
afirma "x3b-sentinela-nao-e-forma-permitida" $? "ocorrencias=[$X_SENT_ALL]"

# 4. A regra da calibracao vazia esta escrita nos tres pontos canonicos: o template que gera o
#    arquivo, o contrato do kind e o passo da F6 que recalcula a tabela. Regra em um ponto so e
#    regra que a sessao seguinte nao encontra.
for x_f in "$X_TPL" "$X_SCH" "$X_EXE"; do
  tem "$x_f" 'sem nenhuma linha de dados'; x_rc=$?
  afirma "x4-regra-da-calibracao-vazia-em-$(basename "$x_f")" "$x_rc" "a tabela vazia esta prescrita"
done
tem "$X_TPL" '`calibracao: []`'; afirma "x4b-template-nomeia-o-estado-do-yaml" $? 'a regra cita calibracao: []'
tem "$X_EXE" '`calibracao: []`'; afirma "x4c-execucao-nomeia-o-estado-do-yaml" $? 'o Passo 3 cita calibracao: []'
tem "$X_EXE" 'cabeçalho e separador'; afirma "x4d-checklist-da-f6-cobra-a-forma" $? "06-execucao.md descreve a forma vazia"

# 5. Linha fabricada e proibida explicitamente: sem isso, "nao ficar com tabela vazia" volta a
#    parecer uma licenca para inventar uma linha.
tem "$X_TPL" 'linha de dados sem item correspondente no frontmatter é proibida'
afirma "x5-template-proibe-linha-fabricada" $? "nunca fabricar linha para a tabela nao ficar vazia"

# 6. As sentinelas invalidas sao nomeadas uma a uma — `—`, `n/a`, celula vazia, e qualquer outra.
tem "$X_TPL" 'nunca use `—`, `n/a`, célula vazia ou qualquer outra sentinela como se fosse linha'
afirma "x6-template-nomeia-as-sentinelas" $? "as quatro formas invalidas estao escritas"

# 7. A regra da celula ausente continua de pe (v11), e continua sendo de CELULA: ela vale para
#    celula de linha real e nunca autoriza uma linha inteira de `—`. Confundir as duas e a causa.
tem "$X_TPL" 'a célula correspondente da tabela leva `—`, nunca `null` e nunca `null h`'
afirma "x7-regra-da-celula-ausente-preservada" $? 'o travessao continua valendo para celula de linha real'
tem "$X_TPL" 'vale para célula de uma linha real, nunca para a linha inteira'
afirma "x7b-celula-ausente-nao-vira-linha" $? "a regra de celula nao se estende a linha"

# 8. O vocabulario do enum nao e afrouxado para acomodar a sentinela: o primeiro campo de uma
#    linha de dados sai do enum `tipo_task`, e `—` nao esta nele.
X_ENUM="$(grep -F '| `tipo_task` |' "$X_SCH" | head -1)"
[ -n "$X_ENUM" ] && ! printf '%s' "$X_ENUM" | grep -qE '—|n/a|null'; x_rc=$?
afirma "x8-enum-tipo-task-sem-sentinela" "$x_rc" "enum=[$(printf '%s' "$X_ENUM" | cut -c1-60)...]"

echo "== Y. o agregador da calibracao do HISTORICO.md e canonico: media, nunca mediana (D-09) =="
# O contrato dizia as duas coisas sobre o MESMO numero. `desvio_medio` era definido como a media
# dos `desvio_task` — a notacao da epoca, que a D-11 desfez em `desvio_padrao_task` e
# `desvio_calibracao_task` (06-execucao.md Passo 3, TEMPLATE-HISTORICO.md, 07-estimativa.md
# Passo 10, e o proprio nome do campo persistido) —, e ao mesmo tempo duas frases mandavam a
# calibracao usar mediana (06-execucao.md, 08-rastro.md, DS-37, README.md). A justificativa da
# mediana e sobre tempo de parede com pausa — isto e, sobre `duracao_observada`, que o schema,
# o template e a 07-estimativa declaram FORA do desvio e FORA da calibracao. Logo a premissa da
# mediana nao alcanca o numero que calibra: o que a calibracao agrega e o
# `desvio_calibracao_task`, construido sobre o `real` anotado, que ja exclui pausa. Duas
# execucoes validas produziam 2,0 e 1,0 do mesmo historico. Canonico: MEDIA.
# `duracao_observada` nao escolhe o agregador porque nao o alimenta.
Y_EXE="$SK/references/06-execucao.md"
Y_RAS="$SK/references/08-rastro.md"
Y_TPL="$SK/assets/TEMPLATE-HISTORICO.md"
Y_SCH="$SK/references/00-schema.md"
Y_EST="$SK/references/07-estimativa.md"
Y_DS="$SK/DECISOES-DA-SKILL.md"
Y_RME="${RAIZ_SRC:+$RAIZ_SRC/README.md}"  # o README da vitrine nao e instalado com a skill

# Os pontos que DEFINEM o agregador, e o conjunto maior onde a regra oposta nao pode reaparecer.
Y_DEFINEM="$Y_EXE $Y_RAS $Y_TPL $Y_SCH $Y_EST"
Y_TODOS="$Y_DEFINEM $Y_DS $Y_RME"

# 1. Dados literais que SEPARAM os dois agregadores: sem isso, "media ou mediana" seria discussao
#    sem consequencia observavel. Desvios [1,0 1,0 4,0]: media 2,00 e mediana 1,00.
Y_DESVIOS='1.0 1.0 4.0'
y_media()   { printf '%s\n' $1 | awk '{s+=$1;n++} END{ if (n) printf "%.2f", s/n }'; }
y_mediana() { printf '%s\n' $1 | sort -g | awk '{v[NR]=$1} END{ if (NR%2) printf "%.2f", v[(NR+1)/2];
              else printf "%.2f", (v[NR/2]+v[NR/2+1])/2 }'; }
Y_MED="$(y_media "$Y_DESVIOS")"; Y_MDN="$(y_mediana "$Y_DESVIOS")"
[ "$Y_MED" = "2.00" ] && [ "$Y_MDN" = "1.00" ] && [ "$Y_MED" != "$Y_MDN" ]
afirma "y1-dados-separam-os-dois-agregadores" $? "desvios=[$Y_DESVIOS] media=$Y_MED mediana=$Y_MDN"

# 2. O agregador e LIDO da documentacao, nao assumido pelo teste: cada ponto canonico declara um
#    token, e o conjunto dos tokens tem de ser exatamente {media}. `ambos` e a contradicao D-09.
# O simbolo do insumo agregado e o `desvio_calibracao_task` (D-11/DS-162); `desvio_task` fica na
# alternancia porque o registro e append-only e a DS-37 do item 7 conserva a notacao da epoca. Os
# dois detectores aceitam exatamente o mesmo conjunto de nomes: afrouxar so o lado da media
# deixaria "mediana dos `desvio_calibracao_task`" passar sem ser vista.
y_diz_media()   { grep -qiE 'm[ée]dia(\*\*)? d(os|e) (`?desvio(_calibracao)?_task`?|desvios)' "$1"; }
y_diz_mediana() { grep -qiE 'mediana(\*\*)? d(os|e) (`?desvio(_calibracao)?_task`?|desvios)|calibra[çc][ãa]o usa (\*\*)?mediana|mediana(\*\*)?, n[ãa]o m[ée]dia' "$1"; }
y_agregador() { # y_agregador <arquivo> -> media | mediana | ambos | nenhum
  local m=1 d=1
  y_diz_media "$1" && m=0
  y_diz_mediana "$1" && d=0
  if   [ $m -eq 0 ] && [ $d -eq 0 ]; then printf 'ambos'
  elif [ $m -eq 0 ]; then printf 'media'
  elif [ $d -eq 0 ]; then printf 'mediana'
  else printf 'nenhum'; fi
}
# 2a. Nenhum arquivo do contrato prescreve mediana, em ponto nenhum: a regra oposta reintroduzida
#     em QUALQUER um deles mata este caso. E o detector da contradicao.
Y_SUJOS=""
for y_f in $Y_TODOS; do
  case "$(y_agregador "$y_f")" in mediana|ambos) Y_SUJOS="$Y_SUJOS $(basename "$y_f")" ;; esac
done
[ -z "$Y_SUJOS" ]
afirma "y2-nenhum-ponto-prescreve-mediana" $? "arquivos com mediana=[${Y_SUJOS:- nenhum}]"

# 2b. E cada ponto que define o agregador diz `media`, nao `nenhum`: regra que so existe por
#     ausencia da errada e regra que a sessao seguinte nao encontra.
Y_MUDOS=""
for y_f in $Y_DEFINEM; do
  [ "$(y_agregador "$y_f")" = "media" ] || Y_MUDOS="$Y_MUDOS $(basename "$y_f"):$(y_agregador "$y_f")"
done
[ -z "$Y_MUDOS" ]
afirma "y2b-todo-ponto-canonico-diz-media" $? "fora de media=[${Y_MUDOS:- nenhum}]"

# 3. O agregador lido da documentacao, APLICADO aos desvios literais, da um valor unico — e e
#    2,00. Trocar o calculo esperado para a mediana mata este caso.
Y_VALORES=""
for y_f in $Y_DEFINEM; do
  case "$(y_agregador "$y_f")" in
    media)   Y_VALORES="$Y_VALORES $(y_media "$Y_DESVIOS")" ;;
    mediana) Y_VALORES="$Y_VALORES $(y_mediana "$Y_DESVIOS")" ;;
    *)       Y_VALORES="$Y_VALORES indefinido" ;;
  esac
done
Y_UNICO="$(printf '%s\n' $Y_VALORES | sort -u | tr '\n' ' ' | sed 's/ $//')"
[ "$Y_UNICO" = "2.00" ]
afirma "y3-um-valor-canonico-sobre-os-mesmos-dados" $? "valores por ponto canonico=[$Y_UNICO] (esperado 2.00)"

# 4. A razao pela qual `duracao_observada` NAO decide o agregador esta escrita, e nos dois pontos
#    que carregavam a frase errada: a justificativa da mediana era sobre tempo de parede, e tempo
#    de parede nao entra na conta. Sem isto escrito, a regra oposta volta com a mesma aparencia
#    de razao.
for y_f in "$Y_EXE" "$Y_RAS"; do
  tem "$y_f" 'não escolhe o agregador'; y_rc=$?
  afirma "y4-duracao-observada-nao-escolhe-o-agregador-em-$(basename "$y_f")" "$y_rc" \
    "a razao esta explicita onde estava a frase errada"
done

# 5. O que a calibracao agrega e nomeado: `desvio_calibracao_task`, vindo do `real` anotado —
#    nunca o tempo de parede. Permitir que `duracao_observada` alimente a calibracao mata este caso.
y_exclui() { # y_exclui <arquivo> — o arquivo tira `duracao_observada` da calibracao
  grep -qiE 'duração observada|`duracao_observada`' "$1" &&
  grep -qiE 'n[ãa]o (entra|participa)[^.]*calibra|fora da `calibracao`|calibra[çc][ãa]o nunca a l[êe]' "$1"
}
Y_VAZADOS=""
for y_f in $Y_DEFINEM; do
  y_exclui "$y_f" || Y_VAZADOS="$Y_VAZADOS $(basename "$y_f")"
done
[ -z "$Y_VAZADOS" ]
afirma "y5-duracao-observada-fora-da-calibracao-em-todo-ponto" $? "sem a exclusao=[${Y_VAZADOS:- nenhum}]"
tem "$Y_EXE" '`desvio_calibracao_task`'; afirma "y5b-execucao-nomeia-o-insumo-agregado" $? "o agregado e o desvio_calibracao_task"
tem "$Y_RAS" '`desvio_calibracao_task`'; afirma "y5c-rastro-nomeia-o-insumo-agregado" $? "o rastro aponta para o desvio_calibracao_task"

# 6. O campo persistido nao e renomeado: `desvio_medio` continua a chave do YAML no schema e no
#    template, e nenhuma variante `desvio_mediana` aparece. Compatibilidade de schema e parte do
#    contrato — a correcao e de prosa, nao de formato.
grep -qF 'desvio_medio:' "$Y_SCH" && grep -qF 'desvio_medio:' "$Y_TPL"
afirma "y6-chave-desvio-medio-preservada" $? "a chave do YAML continua desvio_medio"
Y_RENOMEIO="$(grep -rlE 'desvio_mediana|mediana_desvio' $Y_TODOS | tr '\n' ' ')"
[ -z "$Y_RENOMEIO" ]
afirma "y6b-nenhuma-chave-renomeada" $? "arquivos com chave renomeada=[${Y_RENOMEIO:- nenhum}]"

# 7. A decisao que originou a contradicao foi corrigida no proprio registro: DS-37 nasceu com a
#    frase da mediana (107dd95), e decisao nao corrigida e a contradicao esperando a proxima
#    sessao reinstala-la como se fosse a regra.
Y_DS37="$(grep -F '| DS-37 |' "$Y_DS")"
[ -n "$Y_DS37" ] && ! printf '%s' "$Y_DS37" | grep -qiE 'usa (\*\*)?mediana|mediana(\*\*)?, n[ãa]o m[ée]dia'; y_rc=$?
afirma "y7-ds37-sem-a-regra-oposta" "$y_rc" "DS-37 nao manda mais usar mediana"
printf '%s' "$Y_DS37" | grep -qiE 'm[ée]dia(\*\*)? d(os|e) (`?desvio_task`?|desvios)'; y_rc=$?
afirma "y7b-ds37-declara-o-agregador-canonico" "$y_rc" "DS-37 diz media dos desvio_task"

# 8. Nenhum ponto diz que a duracao do rastro ALIMENTA a calibracao. Essa frase e a premissa de
#    onde a mediana saiu: se o insumo fosse tempo de parede, trocar o agregador por causa da pausa
#    faria sentido. Ela sobrevivia na vitrine (README.md), na SKILL.md e no comentario do hook que
#    grava o evento — tres lugares onde a proxima sessao reconstroi a regra errada do zero.
# O sujeito tem de ser a duracao/tempo de parede: o `real` alimenta a calibracao de verdade, e
# dizer isso esta correto (Passo 2 da F6). `[^.|]` nao cruza ponto nem separador de celula — sem
# isso a regra certa, escrita como "nem alimenta a calibracao", seria lida como a premissa errada.
Y_ALIMENTA="$(grep -rnoE '(dura[çc][ãa]o|duracao_observada|tempo de parede)[^.|]*aliment(a|ando)[^.|]*calibra[çc][ãa]o' \
  $Y_TODOS "$SK/SKILL.md" "$H/comum/rastro-post.sh" \
  | grep -viE 'n[ãa]o aliment|nem aliment' | tr '\n' ' ')"
[ -z "$Y_ALIMENTA" ]
afirma "y8-duracao-nao-e-declarada-insumo-da-calibracao" $? "ocorrencias=[${Y_ALIMENTA:-nenhuma}]"

echo "== Z. precisao e desempate do desvio da calibracao sao canonicos (D-10) =="
# A D-09 tornou o AGREGADOR unico (media, nunca mediana). O numero continuava nao sendo unico:
# nenhum ponto do contrato fixava quantas casas decimais o `desvio` persistido carrega, o que
# fazer no empate exato, se a media e tirada dos `desvio` JA PERSISTIDOS ou das razoes brutas, nem
# se a forma gravada e `1.2` ou `1.20`. Cinco contextos frescos, lendo o contrato ao pe da letra,
# responderam "a documentacao nao fixa" (5/5) e dividiram a forma persistida entre `1.2` (3) e
# `1.20` (2) — a convergencia em half-up foi coincidencia declarada como escolha propria, e um
# deles mostrou que half-even daria `desvio_medio` 1,15 em vez de 1,16 sobre o mesmo historico.
# Decisao humana: half-up, duas casas fixas, sobre os `desvio` persistidos. O fator canonico entra
# na faixa da task/tipo ANTES da agregacao; floor(min)/ceil(max) a hora inteira continua o ultimo
# passo da faixa agregada.
Z_SCH="$SK/references/00-schema.md"
Z_TPL="$SK/assets/TEMPLATE-HISTORICO.md"
Z_EXE="$SK/references/06-execucao.md"
Z_EST="$SK/references/07-estimativa.md"
Z_TES="$SK/assets/TEMPLATE-ESTIMATIVA.md"
Z_DS="$SK/DECISOES-DA-SKILL.md"

# Os pontos que DEFINEM o numero persistido, e os que o CONSOMEM como fator.
Z_DEFINEM="$Z_SCH $Z_TPL $Z_EXE $Z_EST"
Z_CONSOMEM="$Z_EST $Z_TES"
Z_TODOS="$Z_DEFINEM $Z_TES $Z_DS"

# 1. Dados literais que SEPARAM as convencoes. As quatro entradas da amostra base
#    (real/estimado_media): 4.5/4.0, 4.5/4.0, 3.5/3.0 e 1.2/1.0 — razoes 1,125, 1,125, 1,1666... e
#    1,2. O empate exato em 1,125 e o que separa half-up de half-even; a terceira razao e o que
#    separa duas casas de uma; a quarta e o que separa `1.2` de `1.20`.
z_calc() { # z_calc <casas> <desempate:hup|hev> <operandos:persistidos|brutas> -> desvio_medio
  awk -v n="$1" -v d="$2" -v op="$3" '
    function rnd(x, nn, dd,   s, i, f) {
      s = x * (10 ^ nn); i = int(s); f = s - i
      if (dd == "hup") { if (f >= 0.5) i++ }
      else { if (f > 0.5) i++; else if (f == 0.5 && i % 2 != 0) i++ }
      return i / (10 ^ nn)
    }
    BEGIN {
      split("4.5 4.5 3.5 1.2", R, " "); split("4.0 4.0 3.0 1.0", E, " "); s = 0
      for (k = 1; k <= 4; k++) {
        r = R[k] / E[k]
        s += (op == "persistidos") ? rnd(r, n, d) : r
      }
      printf "%." n "f", rnd(s / 4, n, d)
    }'
}
Z_CANON="$(z_calc 2 hup persistidos)"      # a receita decidida
Z_HEV="$(z_calc 2 hev persistidos)"        # half-even
Z_BRUTAS="$(z_calc 2 hup brutas)"          # media das razoes brutas
Z_1CASA="$(z_calc 1 hup persistidos)"      # uma casa
Z_3CASAS="$(z_calc 3 hup persistidos)"     # tres casas
[ "$Z_CANON" = "1.16" ] && [ "$Z_HEV" = "1.15" ] && [ "$Z_BRUTAS" = "1.15" ] \
  && [ "$Z_1CASA" = "1.2" ] && [ "$Z_3CASAS" = "1.154" ] \
  && [ "$Z_CANON" != "$Z_HEV" ] && [ "$Z_CANON" != "$Z_BRUTAS" ] \
  && [ "$Z_CANON" != "$Z_1CASA" ] && [ "$Z_CANON" != "$Z_3CASAS" ]
afirma "z1-dados-separam-as-convencoes" $? \
  "canonico=$Z_CANON half-even=$Z_HEV brutas=$Z_BRUTAS 1casa=$Z_1CASA 3casas=$Z_3CASAS"

# 2. O desempate e LIDO da documentacao, nao assumido pelo teste: cada ponto que define o numero
#    declara um token, e o conjunto dos tokens tem de ser exatamente {hup}. `ambos` e contradicao.
# Os detectores de regra leem o texto SEM marcacao: `**antes**` e `antes` sao a mesma regra, e um
# caso que depende de onde cai o negrito testa formatacao, nao contrato.
z_txt() { tr -d '*`' < "$1"; }
# Todo casamento aqui CONTA linhas (`-c`) em vez de abortar na primeira (`-q`): depois de um pipe,
# `grep -q` fecha a entrada no primeiro casamento, o `tr` a montante leva SIGPIPE e, com
# `pipefail` ligado (linha 9), o status do pipeline fica nao-zero mesmo tendo casado. Isso faz o
# caso passar ou falhar por corrida de escalonamento — verde no foco, vermelho na suite inteira.
z_conta() { z_txt "$1" | grep -ciE "$2"; }
z_tem_re() { [ "$(z_conta "$1" "$2")" -gt 0 ]; }
z_diz_hup() { z_tem_re "$1" 'half-up|meio para cima'; }
# Nomear a convencao rejeitada nao e prescreve-la: a linha que traz o token tem de estar livre de
# marca de recusa. Sem isso, a frase que explica POR QUE nao e half-even se leria como a prescricao
# do half-even — o mesmo cuidado que a y8 (D-09) tomou com "nao alimenta a calibracao". Por isso a
# recusa mora na MESMA linha do token: o caso e por linha, nao por janela de caracteres.
Z_HEV_RE='half-even|banker|arredondamento para o par|meio para o par|meio para baixo'
Z_RECUSA_RE='nunca|em vez de|n[ãa]o aceita|n[ãa]o canonic|n[ãa]o can[õô]nic|seria|daria|correto em estat'
z_diz_hev() { # prescreve half-even sse alguma linha com o token NAO traz marca de recusa
  local tot rec
  tot="$(z_conta "$1" "$Z_HEV_RE")"
  rec="$(z_txt "$1" | grep -iE "$Z_HEV_RE" | grep -ciE "$Z_RECUSA_RE")"
  [ "$tot" -gt 0 ] && [ "$rec" -lt "$tot" ]
}
z_desempate() { # z_desempate <arquivo> -> hup | hev | ambos | nenhum
  local u=1 e=1
  z_diz_hup "$1" && u=0
  z_diz_hev "$1" && e=0
  if   [ $u -eq 0 ] && [ $e -eq 0 ]; then printf 'ambos'
  elif [ $u -eq 0 ]; then printf 'hup'
  elif [ $e -eq 0 ]; then printf 'hev'
  else printf 'nenhum'; fi
}
Z_SUJOS=""
for z_f in $Z_TODOS; do
  case "$(z_desempate "$z_f")" in hev|ambos) Z_SUJOS="$Z_SUJOS $(basename "$z_f")" ;; esac
done
[ -z "$Z_SUJOS" ]
afirma "z2-nenhum-ponto-prescreve-outro-desempate" $? "arquivos com desempate nao canonico=[${Z_SUJOS:- nenhum}]"

Z_MUDOS=""
for z_f in $Z_DEFINEM; do
  [ "$(z_desempate "$z_f")" = "hup" ] || Z_MUDOS="$Z_MUDOS $(basename "$z_f"):$(z_desempate "$z_f")"
done
[ -z "$Z_MUDOS" ]
afirma "z2b-todo-ponto-que-define-o-numero-diz-half-up" $? "fora de half-up=[${Z_MUDOS:- nenhum}]"

# 3. As casas tambem sao LIDAS, e sao DUAS em todo ponto que define o numero. Regra que existe so
#    por ausencia da errada e regra que a sessao seguinte nao encontra.
z_casas() { # z_casas <arquivo> -> 2 | 1 | 3 | ambiguo | nenhum
  local c=""
  z_tem_re "$1" 'duas casas decimais' && c="$c 2"
  z_tem_re "$1" 'uma casa decimal' && c="$c 1"
  z_tem_re "$1" 'tr[êe]s casas decimais' && c="$c 3"
  case "$(printf '%s' "$c" | tr -d ' ')" in
    2) printf '2' ;; 1) printf '1' ;; 3) printf '3' ;; '') printf 'nenhum' ;; *) printf 'ambiguo' ;;
  esac
}
Z_CASAS_FORA=""
for z_f in $Z_DEFINEM; do
  [ "$(z_casas "$z_f")" = "2" ] || Z_CASAS_FORA="$Z_CASAS_FORA $(basename "$z_f"):$(z_casas "$z_f")"
done
[ -z "$Z_CASAS_FORA" ]
afirma "z3-duas-casas-em-todo-ponto-que-define-o-numero" $? "fora de 2 casas=[${Z_CASAS_FORA:- nenhum}]"

# 4. O ESTAGIO esta escrito: cada `desvio` e arredondado ANTES de ser persistido, e a media sai dos
#    `desvio` persistidos — nunca das razoes brutas —, arredondada de novo pela mesma regra.
z_diz_persistidos() { # nomeia o operando certo E recusa o errado
  z_tem_re "$1" 'persistid[oa]s?' &&
  z_tem_re "$1" 'nunca (a m[ée]dia )?d(as|a) raz([õo]es|[ãa]o) brutas?|n[ãa]o (é|e) a m[ée]dia das raz[õo]es'
}
Z_SEM_OPERANDO=""
for z_f in $Z_DEFINEM; do
  z_diz_persistidos "$z_f" || Z_SEM_OPERANDO="$Z_SEM_OPERANDO $(basename "$z_f")"
done
[ -z "$Z_SEM_OPERANDO" ]
afirma "z4-operandos-sao-os-desvios-persistidos" $? "sem os operandos=[${Z_SEM_OPERANDO:- nenhum}]"

z_diz_estagio() { z_tem_re "$1" 'arredondado antes|antes de ser persistido|antes de entrar na m[ée]dia'; }
Z_SEM_ESTAGIO=""
for z_f in $Z_DEFINEM; do
  z_diz_estagio "$z_f" || Z_SEM_ESTAGIO="$Z_SEM_ESTAGIO $(basename "$z_f")"
done
[ -z "$Z_SEM_ESTAGIO" ]
afirma "z4b-estagio-do-arredondamento-esta-escrito" $? "sem o estagio=[${Z_SEM_ESTAGIO:- nenhum}]"

z_tem_re "$Z_SCH" 'arredondad[ao] de novo' && z_tem_re "$Z_SCH" 'pela mesma regra'
afirma "z4c-media-e-arredondada-de-novo" $? "o desvio_medio passa pela mesma regra"

# 5. A receita LIDA do contrato, APLICADA a amostra base, da um valor unico — e e 1,16. Trocar
#    casas, desempate ou operandos na documentacao muda este valor e mata o caso.
Z_VALORES=""
for z_f in $Z_DEFINEM; do
  z_c="$(z_casas "$z_f")"; z_d="$(z_desempate "$z_f")"
  z_o=persistidos; z_diz_persistidos "$z_f" || z_o=brutas
  case "$z_c:$z_d" in
    2:hup|1:hup|3:hup|2:hev|1:hev|3:hev) Z_VALORES="$Z_VALORES $(z_calc "$z_c" "$z_d" "$z_o")" ;;
    *) Z_VALORES="$Z_VALORES indefinido" ;;
  esac
done
Z_UNICO="$(printf '%s\n' $Z_VALORES | sort -u | tr '\n' ' ' | sed 's/ $//')"
[ "$Z_UNICO" = "1.16" ]
afirma "z5-um-numero-canonico-sobre-a-mesma-amostra" $? "valores por ponto=[$Z_UNICO] (esperado 1.16)"

# 6. O exemplo canonico do empate esta escrito, com o resultado certo e o errado nomeado: sem o
#    caso trabalhado, "half-up" e uma palavra que cada leitor resolve de um jeito.
Z_SEM_EXEMPLO=""
for z_f in $Z_DEFINEM; do
  grep -qF '1,125' "$z_f" && grep -qF '1,13' "$z_f" || Z_SEM_EXEMPLO="$Z_SEM_EXEMPLO $(basename "$z_f")"
done
[ -z "$Z_SEM_EXEMPLO" ]
afirma "z6-exemplo-canonico-do-empate-presente" $? "sem 1,125 -> 1,13=[${Z_SEM_EXEMPLO:- nenhum}]"
grep -qF '1,12' "$Z_SCH"
afirma "z6b-a-resposta-errada-do-empate-e-nomeada" $? "o schema nomeia 1,12 como o que nao se grava"

# 7. REPRESENTACAO. As duas casas sao FIXAS, nao "ate duas": `1,2` grava-se `1.20` no YAML e
#    escreve-se `1,20` na prosa. Sem isso, o mesmo numero tem duas formas em disco — foi a divisao
#    medida nas amostras (3 escreveram `1.2`, 2 escreveram `1.20`).
Z_SEM_FIXAS=""
for z_f in $Z_DEFINEM; do
  grep -qF '1.20' "$z_f" && grep -qF '1,20' "$z_f" || Z_SEM_FIXAS="$Z_SEM_FIXAS $(basename "$z_f")"
done
[ -z "$Z_SEM_FIXAS" ]
afirma "z7-par-yaml-prosa-do-mesmo-numero-presente" $? "sem o par 1.20/1,20=[${Z_SEM_FIXAS:- nenhum}]"

# 7b. E nenhum valor das chaves da calibracao aparece em disco com uma casa ou com tres: o contrato
#     nao modela a forma que ele proibe. Varre as linhas YAML dos pontos canonicos.
Z_FORA_FORMA="$(grep -rnE '^[[:space:]]*(desvio|desvio_medio|fator_correcao_aplicado):[[:space:]]*[0-9]+(\.[0-9]+)?[[:space:]]*$' \
  $Z_DEFINEM "$Z_TES" | grep -vE ':[[:space:]]*[0-9]+\.[0-9][0-9][[:space:]]*$' | tr '\n' ' ')"
[ -z "$Z_FORA_FORMA" ]
afirma "z7b-nenhum-valor-yaml-fora-de-duas-casas" $? "linhas fora da forma=[${Z_FORA_FORMA:-nenhuma}]"

# 7c. A prosa dos pontos canonicos tambem: o alvo e `1,00` e o exemplo de 40% e `1,40`. `1,0` e
#     o alvo` e a forma de uma casa reaparecendo exatamente onde o leitor aprende o numero. A
#     RAZAO bruta pode ter qualquer numero de casas — ela nao e valor persistido —, e nomear a
#     forma proibida ("nunca `1.2`") e a propria regra; por isso o caso acusa so a prosa que
#     ENSINA o numero, nao toda aparicao de um decimal curto.
Z_PROSA_1CASA="$(grep -rnE '`1[.,][04]`[^`]*(é o alvo|significa que)' $Z_DEFINEM "$Z_TES" | tr '\n' ' ')"
[ -z "$Z_PROSA_1CASA" ]
afirma "z7c-alvo-nunca-ensinado-com-uma-casa" $? "ocorrencias=[${Z_PROSA_1CASA:-nenhuma}]"

# 7e. E a proibicao do fator neutro (DS-46) passa a citar a forma canonica: `1.00`, nao `1.0`.
#     Um contrato que proibe `1.0` modela, na propria proibicao, o valor de uma casa que ele acabou
#     de banir — e e dessa modelagem que a forma errada volta.
Z_NEUTRO_1CASA="$(grep -rnE 'nunca `1\.0`|Nunca `1\.0`' $Z_DEFINEM "$Z_TES" | tr '\n' ' ')"
[ -z "$Z_NEUTRO_1CASA" ]
afirma "z7e-proibicao-do-neutro-na-forma-canonica" $? "ocorrencias=[${Z_NEUTRO_1CASA:-nenhuma}]"
Z_SEM_NEUTRO=""
for z_f in "$Z_SCH" "$Z_EST"; do
  grep -qF 'nunca `1.00`' "$z_f" || grep -qF 'Nunca `1.00`' "$z_f" || Z_SEM_NEUTRO="$Z_SEM_NEUTRO $(basename "$z_f")"
done
[ -z "$Z_SEM_NEUTRO" ]
afirma "z7f-neutro-proibido-com-duas-casas" $? "sem a proibicao em 1.00=[${Z_SEM_NEUTRO:- nenhum}]"
Z_SEM_ALVO=""
for z_f in "$Z_TPL" "$Z_EXE" "$Z_EST"; do
  grep -qF '`1,00`' "$z_f" && grep -qF '`1,40`' "$z_f" || Z_SEM_ALVO="$Z_SEM_ALVO $(basename "$z_f")"
done
[ -z "$Z_SEM_ALVO" ]
afirma "z7d-alvo-e-exemplo-na-forma-canonica" $? "sem 1,00/1,40=[${Z_SEM_ALVO:- nenhum}]"

# 8. CONSUMIDOR. O fator e o `desvio_medio` persistido, aplicado a faixa da task/tipo ANTES da
#    agregacao; floor(min)/ceil(max) a hora inteira continua o ULTIMO passo da faixa agregada.
#    Sem a ordem escrita, o consumidor arredonda em estagio proprio e a faixa publicada muda.
# As duas metades da regra tem de estar na MESMA linha — isto e, no mesmo paragrafo: qual numero e
# o fator, e em que momento ele entra. Conferir arquivo por arquivo nao basta, porque a Passo 5
# tambem fala de "antes da agregacao" para dizer que o fator ja entrou, e essa frase mascarava a
# retirada da regra de onde o consumidor age (o Passo 1). Mutante m8 passava por aqui.
z_diz_fator_antes() {
  [ "$(z_txt "$1" | grep -iE 'antes da agrega[çc][ãa]o|antes de agregar' \
        | grep -ciE 'desvio_medio persistido|fator (é|e) o desvio_medio')" -gt 0 ]
}
Z_SEM_ORDEM=""
for z_f in $Z_CONSOMEM; do
  z_diz_fator_antes "$z_f" || Z_SEM_ORDEM="$Z_SEM_ORDEM $(basename "$z_f")"
done
[ -z "$Z_SEM_ORDEM" ]
afirma "z8-consumidor-aplica-o-fator-antes-da-agregacao" $? "sem a ordem=[${Z_SEM_ORDEM:- nenhum}]"

# Tambem na mesma linha: e o arredondamento A HORA INTEIRA que e o ultimo passo. "ultimo passo"
# solto casaria com qualquer outra frase do arquivo que use a expressao.
[ "$(z_txt "$Z_EST" | grep -iE 'hora inteira' | grep -ciE '[úu]ltimo passo')" -gt 0 ]
afirma "z8b-hora-inteira-e-o-ultimo-passo" $? "floor/ceil a hora inteira e o ultimo passo da faixa"

# 8c. O efeito e observavel: duas tasks `integracao_externa` (o=4 m=5 p=12 e o=3 m=4 p=5) com o
#     fator canonico 1,16 publicam 10–14 h; com o half-even 1,15, 9–14 h. O piso dos `o` tambem
#     recebe o fator, porque o fator entra antes da agregacao.
z_faixa() { # z_faixa <fator> -> "min-max" em horas inteiras
  awk -v f="$1" 'BEGIN {
    mA = (4 + 4*5 + 12)/6; dA = (12 - 4)/6
    mB = (3 + 4*4 +  5)/6; dB = ( 5 - 3)/6
    m = (mA + mB) * f; d = sqrt(dA*dA + dB*dB) * f
    mn = m - d; mx = m + d; piso = (4 + 3) * f
    if (mn < piso) mn = piso
    printf "%d-%d", int(mn), (mx == int(mx) ? mx : int(mx) + 1)
  }'
}
Z_FX_CANON="$(z_faixa "$Z_CANON")"; Z_FX_HEV="$(z_faixa "$Z_HEV")"
[ "$Z_FX_CANON" = "10-14" ] && [ "$Z_FX_HEV" = "9-14" ] && [ "$Z_FX_CANON" != "$Z_FX_HEV" ]
afirma "z8c-fator-canonico-muda-a-faixa-publicada" $? \
  "fator $Z_CANON -> $Z_FX_CANON h; fator $Z_HEV -> $Z_FX_HEV h"

# 8d. O PISO da faixa agregada (DS-163, que estende a DS-41). A DS-41 fixou "min nunca abaixo do
#     melhor caso somado", e o Passo 5 a escrevia com DOIS operandos diferentes: comparava `min`
#     contra "a maior `o` do conjunto" e atribuia "a soma dos `o`". Sao grandezas distintas, e o
#     piso ficava sem definicao justamente onde ha fator de correcao abaixo de 1 — permitido e
#     alcancavel (tipo cujo historico mostra que o projeto estima para cima). A regra canonica tem
#     um operando so, corrigido task a task: piso_conjunto = soma( o(t) * fator(t) ), com
#     fator(t) = 1 quando o tipo da task nao tem fator ativo.
#
# Os detectores de formula leem o texto sem backtick, sem negrito e sem espaco em branco, mas
# PRESERVAM o `*`: aqui o operador de multiplicacao e contrato, nao marcacao. `**` sempre vem em
# par (negrito) e cai antes; `×` e `*` sao a mesma multiplicacao. Assim um mutante de espacamento
# ou de marcacao sobrevive, e um mutante de operando morre.
z_fml() { sed -e 's/\*\*//g' -e 's/`//g' -e 's/×/*/g' -e 's/[[:space:]]//g' "$1"; }
z_fml_tem() { [ "$(z_fml "$1" | grep -cF "$2")" -gt 0 ]; }

Z_PISO_FML='piso_conjunto=soma(o(t)*fator(t))'
Z_PISO_CRU_FML='piso_conjunto=soma(o(t))'
Z_SAN_FML='[soma(o(t)*fator(t)),soma(p(t)*fator(t))]'
Z_SAN_CRU_FML='[somadoso,somadosp]'
# A forma antiga, em prosa: gatilho na maior `o`, atribuicao na soma crua dos `o`.
Z_MAIOR_O_RE='maior .?o.? do conjunto|maior dos .?o.?|soma dos .?o.? como piso|piso: soma dos .?o.?'
# Nomear a forma recusada nao e prescreve-la (mesmo cuidado da z2 e da y8): a linha que traz o
# token tem de estar livre de marca de recusa para contar como prescricao.
Z_RECUSA_PISO_RE="$Z_RECUSA_RE|publica|fracion|reprova|viraria|deixam? o piso sem|grandezas diferentes"
z_prescreve_maior_o() {
  local tot rec
  tot="$(z_conta "$1" "$Z_MAIOR_O_RE")"
  rec="$(z_txt "$1" | grep -iE "$Z_MAIOR_O_RE" | grep -ciE "$Z_RECUSA_PISO_RE")"
  [ "$tot" -gt 0 ] && [ "$rec" -lt "$tot" ]
}
z_piso_lido() { # z_piso_lido <arquivo> -> corrigido | cru | contraditorio | indefinido
  local f=1 g=1 a=1 w=1
  z_fml_tem "$1" "$Z_PISO_FML" && f=0
  # O gatilho compara e atribui o MESMO operando, na mesma linha: `min < piso_conjunto` entao
  # `min = piso_conjunto`. Conferir so a formula nao basta — era exatamente o par comparacao/
  # atribuicao que divergia.
  [ "$(z_fml "$1" | grep -cE 'min<piso_conjunto.*min=piso_conjunto')" -gt 0 ] && g=0
  z_fml_tem "$1" "$Z_PISO_CRU_FML" && a=0
  z_prescreve_maior_o "$1" && w=0
  if   [ $w -eq 0 ];                   then printf 'contraditorio'
  elif [ $f -eq 0 ] && [ $g -eq 0 ];   then printf 'corrigido'
  elif [ $a -eq 0 ];                   then printf 'cru'
  else printf 'indefinido'; fi
}
Z_PISO_FORA=""
for z_f in $Z_CONSOMEM; do
  z_p="$(z_piso_lido "$z_f")"
  [ "$z_p" = corrigido ] || Z_PISO_FORA="$Z_PISO_FORA $(basename "$z_f"):$z_p"
done
[ -z "$Z_PISO_FORA" ]
afirma "z8d-piso-e-a-soma-dos-o-corrigidos-por-task" $? "fora do piso canonico=[${Z_PISO_FORA:- nenhum}]"

# 8e. Reference e template dizem a MESMA regra. O template e o que o executor copia; contrato que
#     mora so na reference vira faixa publicada por um arquivo e nao pelo outro.
Z_NEUTRO_FORA=""
for z_f in $Z_CONSOMEM; do
  z_tem_re "$z_f" 'fator\(t\) *= *1($|[^0-9.])' || Z_NEUTRO_FORA="$Z_NEUTRO_FORA $(basename "$z_f")"
done
[ -z "$Z_NEUTRO_FORA" ]
afirma "z8e-fator-neutro-por-task-declarado" $? "sem fator(t)=1=[${Z_NEUTRO_FORA:- nenhum}]"

# 8f. O CLAMP vem antes do arredondamento a hora inteira, e as duas metades na mesma linha: qual
#     estagio, e de que arredondamento se fala. Pisar depois de arredondar publica `min`
#     fracionario (3,20 h no caso vinculante), e a faixa publicada e em hora inteira.
z_clamp_antes() {
  [ "$(z_txt "$1" | grep -iE 'antes d(o|e) (floor|arredond)' | grep -ciE 'hora inteira|floor\(min\)')" -gt 0 ]
}
z_prescreve_clamp_depois() {
  local tot rec
  tot="$(z_conta "$1" 'depois d(o|e) (floor|arredond)')"
  rec="$(z_txt "$1" | grep -iE 'depois d(o|e) (floor|arredond)' | grep -ciE "$Z_RECUSA_PISO_RE")"
  [ "$tot" -gt 0 ] && [ "$rec" -lt "$tot" ]
}
Z_CLAMP_FORA=""
for z_f in $Z_CONSOMEM; do
  z_clamp_antes "$z_f" || Z_CLAMP_FORA="$Z_CLAMP_FORA $(basename "$z_f"):sem-antes"
  z_prescreve_clamp_depois "$z_f" && Z_CLAMP_FORA="$Z_CLAMP_FORA $(basename "$z_f"):prescreve-depois"
done
[ -z "$Z_CLAMP_FORA" ]
afirma "z8f-clamp-antes-do-arredondamento" $? "fora do estagio=[${Z_CLAMP_FORA:- nenhum}]"

# 8g. A SANIDADE do Passo 5 e do checklist usa os limites corrigidos task a task. Com fator abaixo
#     de 1, o intervalo bruto reprova conta certa: no caso vinculante, min=3,7333 fica FORA de
#     [4, 12] e dentro de [3,20, 9,60]. Verificacao que reprova o certo manda refazer o que estava
#     pronto, e quem refaz converge para o numero errado.
z_sanidade_lida() { # z_sanidade_lida <arquivo> -> corrigida | crua | ambas | nenhuma
  local c=1 b=1
  z_fml_tem "$1" "$Z_SAN_FML" && c=0
  z_fml_tem "$1" "$Z_SAN_CRU_FML" && b=0
  if   [ $c -eq 0 ] && [ $b -eq 0 ]; then printf 'ambas'
  elif [ $c -eq 0 ];                 then printf 'corrigida'
  elif [ $b -eq 0 ];                 then printf 'crua'
  else printf 'nenhuma'; fi
}
Z_SAN_FORA=""
for z_f in $Z_CONSOMEM; do
  z_s="$(z_sanidade_lida "$z_f")"
  [ "$z_s" = corrigida ] || Z_SAN_FORA="$Z_SAN_FORA $(basename "$z_f"):$z_s"
done
[ -z "$Z_SAN_FORA" ]
afirma "z8g-sanidade-usa-o-intervalo-corrigido" $? "fora do intervalo corrigido=[${Z_SAN_FORA:- nenhum}]"

# 8h. Dados literais que SEPARAM as leituras do piso, no caso vinculante: uma task `api`
#     o=4 m=5 p=12 com o fator 0,80 do seu tipo. Media corrigida 4,80, desvio corrigido 1,0667,
#     min cru 3,7333, max 5,8667. Piso corrigido 4 × 0,80 = 3,20, que 3,7333 nao fura: faixa
#     publicada 3–6 h. Com o piso bruto (soma dos `o` sem fator, 4) o min e pisado em 4 e a faixa
#     viraria 4–6 h — uma hora de esforco na base da faixa que o metodo nao calculou. Pisando
#     depois do arredondamento, o min publicado e 3,2: nem hora inteira.
z_faixa_t() { # z_faixa_t <piso:corrigido|cru|maior_o> <clamp:antes|depois> <fator_global|-> <o,m,p,fator>...
  local piso="$1" clamp="$2" fg="$3"; shift 3
  printf '%s\n' "$@" | awk -F, -v piso="$piso" -v clamp="$clamp" -v fg="$fg" '
    { o=$1; m=$2; p=$3; f=(fg == "-" ? $4 : fg)
      M += (o + 4*m + p)/6 * f; v = (p - o)/6 * f; V += v*v
      soc += o*f; so += o; if (o > mo) mo = o }
    END {
      d = sqrt(V); mn = M - d; mx = M + d
      ps = (piso == "corrigido" ? soc : (piso == "cru" ? so : mo))
      fmx = (mx == int(mx) ? mx : int(mx) + 1)
      if (clamp == "antes") { if (mn < ps) mn = ps; fmn = int(mn) }
      else { fmn = int(mn); if (fmn < ps) fmn = ps }
      printf "%g-%g", fmn, fmx
    }'
}
Z_CASO_API='4,5,12,0.80'
Z_FX_PISO_OK="$(z_faixa_t corrigido antes - $Z_CASO_API)"
Z_FX_PISO_CRU="$(z_faixa_t cru antes - $Z_CASO_API)"
Z_FX_PISO_TARDE="$(z_faixa_t corrigido depois - $Z_CASO_API)"
[ "$Z_FX_PISO_OK" = "3-6" ] && [ "$Z_FX_PISO_CRU" = "4-6" ] && [ "$Z_FX_PISO_TARDE" = "3.2-6" ] \
  && [ "$Z_FX_PISO_OK" != "$Z_FX_PISO_CRU" ] && [ "$Z_FX_PISO_OK" != "$Z_FX_PISO_TARDE" ]
afirma "z8h-dados-separam-as-leituras-do-piso" $? \
  "corrigido=$Z_FX_PISO_OK cru=$Z_FX_PISO_CRU pisado-depois=$Z_FX_PISO_TARDE"

# 8i. A receita e LIDA de cada ponto que consome o fator e aplicada ao caso vinculante: o conjunto
#     dos resultados tem de ser {3-6}. Era {indefinido} — o contrato nao respondia qual operando.
Z_FX_PISO=""
for z_f in $Z_CONSOMEM; do
  case "$(z_piso_lido "$z_f")" in
    corrigido) Z_FX_PISO="$Z_FX_PISO $(z_faixa_t corrigido antes - $Z_CASO_API)" ;;
    cru)       Z_FX_PISO="$Z_FX_PISO $(z_faixa_t cru antes - $Z_CASO_API)" ;;
    *)         Z_FX_PISO="$Z_FX_PISO indefinido" ;;
  esac
done
Z_FX_PISO_UNICO="$(printf '%s\n' $Z_FX_PISO | sort -u | tr '\n' ' ' | sed 's/ $//')"
[ "$Z_FX_PISO_UNICO" = "3-6" ]
afirma "z8i-faixa-canonica-do-caso-vinculante" $? "faixa por ponto=[$Z_FX_PISO_UNICO] (esperado 3-6)"

# 8j. CONJUNTO MISTO: o fator e por task, nunca um fator global do conjunto. `api` o=4 m=5 p=12
#     com fator 0,80 mais `ui` o=3 m=4 p=5 sem fator ativo (fator 1) publicam 7–10 h. Aplicar
#     0,80 ao conjunto inteiro publica 6–10 h; ignorar o fator publica 8–12 h. Tres faixas
#     diferentes do mesmo plano, e so uma sai da regra.
Z_CASO_MISTO="4,5,12,0.80 3,4,5,1"
Z_FX_MISTO_T="$(z_faixa_t corrigido antes - $Z_CASO_MISTO)"
Z_FX_MISTO_G="$(z_faixa_t corrigido antes 0.80 $Z_CASO_MISTO)"
Z_FX_MISTO_N="$(z_faixa_t corrigido antes 1 $Z_CASO_MISTO)"
[ "$Z_FX_MISTO_T" = "7-10" ] && [ "$Z_FX_MISTO_G" = "6-10" ] && [ "$Z_FX_MISTO_N" = "8-12" ] \
  && [ "$Z_FX_MISTO_T" != "$Z_FX_MISTO_G" ] && [ "$Z_FX_MISTO_T" != "$Z_FX_MISTO_N" ]
afirma "z8j-conjunto-misto-usa-o-fator-de-cada-task" $? \
  "por task=$Z_FX_MISTO_T global=$Z_FX_MISTO_G sem fator=$Z_FX_MISTO_N"

# 8k. E a sanidade do mesmo caso: o intervalo corrigido aprova a conta certa, o bruto a reprova.
z_sanidade_aplica() { # z_sanidade_aplica <corrigido|cru> <o,m,p,fator>... -> aprova | reprova
  local lim="$1"; shift
  printf '%s\n' "$@" | awk -F, -v lim="$lim" '
    { o=$1; m=$2; p=$3; f=$4
      M += (o + 4*m + p)/6 * f; v = (p - o)/6 * f; V += v*v
      soc += o*f; spc += p*f; so += o; sp += p }
    END {
      d = sqrt(V); lo = (lim == "corrigido" ? soc : so); hi = (lim == "corrigido" ? spc : sp)
      printf "%s", (M - d >= lo && M + d <= hi) ? "aprova" : "reprova"
    }'
}
Z_SAN_OK="$(z_sanidade_aplica corrigido $Z_CASO_API)"
Z_SAN_CRU="$(z_sanidade_aplica cru $Z_CASO_API)"
[ "$Z_SAN_OK" = aprova ] && [ "$Z_SAN_CRU" = reprova ]
afirma "z8k-intervalo-bruto-reprovaria-a-conta-certa" $? \
  "corrigido=$Z_SAN_OK bruto=$Z_SAN_CRU (min 3,7333 fora de [4, 12])"

# 8k2. DS-169: a sanidade e sobre o decimal do Passo 5 (pos-piso, pre-arredondamento), nunca
#      sobre a faixa PUBLICADA (ja arredondada a hora inteira por floor/ceil). floor/ceil
#      arredonda para FORA (alarga), entao a faixa publicada pode deixar de estar contida no
#      intervalo corrigido mesmo numa conta certa — no caso Z_CASO_API, publicada "3-6 h" contra
#      corrigido "[3,20, 9,60]": 3 nao fica acima de 3,20. O par abaixo mostra as duas leituras
#      do MESMO caso: so a decimal aprova; a publicada reprovaria, e e exatamente por isso que o
#      contrato tem de nomear qual das duas vale.
z_sanidade_publicada() { # z_sanidade_publicada <faixa "min-max"> <soc> <spc> -> aprova | reprova
  local fx="$1" soc="$2" spc="$3" fmn fmx
  fmn="${fx%-*}"; fmx="${fx#*-}"
  awk -v fmn="$fmn" -v fmx="$fmx" -v soc="$soc" -v spc="$spc" \
    'BEGIN { printf "%s", (fmn > soc && fmx < spc) ? "aprova" : "reprova" }'
}
Z_SAN_PUB="$(z_sanidade_publicada "$Z_FX_PISO_OK" 3.20 9.60)"
[ "$Z_SAN_OK" = aprova ] && [ "$Z_SAN_PUB" = reprova ]
afirma "z8k2a-decimal-aprova-publicada-reprovaria-o-mesmo-caso" $? \
  "decimal(Z_SAN_OK, de 8k)=$Z_SAN_OK publicada($Z_FX_PISO_OK)=$Z_SAN_PUB"

# O paragrafo da verificacao (07-estimativa.md) tem de nomear o estagio explicitamente: cita o
# Passo 5, o arredondamento/floor do Passo 6, e adverte contra comparar com a faixa publicada.
Z_SAN_TXT="$(grep -F 'Verificação obrigatória de sanidade' "$Z_EST")"
z_tem_822() { printf '%s' "$Z_SAN_TXT" | grep -qi "$1"; }
z_tem_822 'Passo 5'; Z_822_P5=$?
z_tem_822 'floor'; Z_822_FLOOR=$?
z_tem_822 'publicada'; Z_822_PUB=$?
[ -n "$Z_SAN_TXT" ] && [ "$Z_822_P5" -eq 0 ] && [ "$Z_822_FLOOR" -eq 0 ] && [ "$Z_822_PUB" -eq 0 ]
afirma "z8k2b-paragrafo-nomeia-o-estagio-decimal-vs-publicada" $? \
  "Passo5=$Z_822_P5 floor=$Z_822_FLOOR publicada=$Z_822_PUB (0=presente)"

# O item do checklist do Passo 5 repete a mesma regra, pelo mesmo motivo que a DS-160/DS-163 ja
# valem para dois pontos canonicos: quem le so o checklist nao pode reproduzir o erro antigo.
Z_CHK_LINHA="$(grep -F 'contido em' "$Z_EST")"
printf '%s' "$Z_CHK_LINHA" | grep -qi 'decimal'; Z_CHK_DEC=$?
printf '%s' "$Z_CHK_LINHA" | grep -qi 'publicada'; Z_CHK_PUB=$?
[ -n "$Z_CHK_LINHA" ] && [ "$Z_CHK_DEC" -eq 0 ] && [ "$Z_CHK_PUB" -eq 0 ]
afirma "z8k2c-checklist-nomeia-o-estagio-decimal-vs-publicada" $? \
  "linha=[$Z_CHK_LINHA]"

# A decisao esta registrada, append-only, e estende a DS-163 (mesmo piso, novo estagio de leitura).
Z_DS169="$(grep -F '| DS-169 |' "$Z_DS")"
[ -n "$Z_DS169" ]
afirma "z8k2d-ds169-registrada" $? "a decisao da sanidade decimal existe no registro"
printf '%s' "$Z_DS169" | grep -qF 'DS-163'; z_rc=$?
afirma "z8k2e-ds169-declara-que-estende-ds163" "$z_rc" "DS-169 nomeia a DS-163 que ela estende"

# 8k3. A celula do placeholder "Fator ativo?" tem um `|` literal dentro do texto condicional
#      ("...x{{desvio}} | nao..."). Markdown le qualquer `|` fora de code span como separador de
#      coluna — esse pipe tem de vir escapado (`\|`), senao a linha de dados renderiza com uma
#      coluna a mais e corrompe a tabela. Conta os pipes QUE SEPARAM coluna (a substituicao via
#      parametro do bash, nao sed, porque `\|` em BRE do GNU sed e alternancia, nao literal):
#      a linha Markdown tem pipe inicial e final alem dos separadores entre colunas: o cabecalho
#      de 4 colunas tem 5 pipes (NF=6 por awk -F'|'); a linha de dados, com o pipe interno
#      escapado, tem de dar o mesmo NF=6 depois de neutralizar o `\|` escapado.
Z_TPL_CABECALHO="$(grep -F 'Tipo de task' "$Z_TPL")"
Z_TPL_CAMPOS_CABECALHO="$(printf '%s' "$Z_TPL_CABECALHO" | awk -F'|' '{print NF}')"
Z_TPL_LINHA_DADOS="$(grep -F '{{tipo_task}} | {{n}}' "$Z_TPL")"
Z_TPL_SEM_ESCAPE="${Z_TPL_LINHA_DADOS//\\|/@PIPE_ESCAPADO@}"
Z_TPL_CAMPOS_DADOS="$(printf '%s' "$Z_TPL_SEM_ESCAPE" | awk -F'|' '{print NF}')"
[ "$Z_TPL_CAMPOS_DADOS" -eq "$Z_TPL_CAMPOS_CABECALHO" ]
afirma "z8k3-pipe-interno-da-celula-fator-ativo-esta-escapado" $? \
  "linha=[$Z_TPL_LINHA_DADOS] campos(pipes separadores, pipe interno neutralizado)=$Z_TPL_CAMPOS_DADOS cabecalho=$Z_TPL_CAMPOS_CABECALHO"
Z_DS170="$(grep -F '| DS-170 |' "$Z_DS")"
[ -n "$Z_DS170" ]
afirma "z8k3a-ds170-registrada" $? "a decisao do escape do pipe existe no registro"

# 8k4. Mutantes que RESTAURAM cada defeito corrigido nesta secao, numa COPIA da skill — a arvore
#      real nunca e tocada — e tem de morrer exatamente pelo caso nomeado.
ZM_A="$(mktemp -d)"; cp -R "$SK/." "$ZM_A/"
sed 's/×{{desvio}} \\| não/×{{desvio}} | não/' "$ZM_A/assets/TEMPLATE-HISTORICO.md" > "$ZM_A.sed" \
  && cat "$ZM_A.sed" > "$ZM_A/assets/TEMPLATE-HISTORICO.md"   # sem `sed -i` (so GNU)
! cmp -s "$Z_TPL" "$ZM_A/assets/TEMPLATE-HISTORICO.md"; Z_MA_GEROU=$?
ZM_A_LINHA="$(grep -F '{{tipo_task}} | {{n}}' "$ZM_A/assets/TEMPLATE-HISTORICO.md")"
ZM_A_SEM_ESCAPE="${ZM_A_LINHA//\\|/@PIPE_ESCAPADO@}"
ZM_A_CAMPOS="$(printf '%s' "$ZM_A_SEM_ESCAPE" | awk -F'|' '{print NF}')"
[ "$Z_MA_GEROU" -eq 0 ] && [ "$ZM_A_CAMPOS" -ne "$Z_TPL_CAMPOS_CABECALHO" ]
afirma "z8k4a-mutante-reintroduz-pipe-sem-escape-morto-por-z8k3" $? \
  "mutacao gerada=$Z_MA_GEROU campos apos mutacao=$ZM_A_CAMPOS (esperado != $Z_TPL_CAMPOS_CABECALHO)"

ZM_B="$(mktemp -d)"; cp -R "$SK/." "$ZM_B/"
python3 - "$ZM_B/references/07-estimativa.md" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
novo_par = ("**Verificação obrigatória de sanidade:** a checagem é sobre o `[min, max]` do Passo 5 "
    "— decimal, com o fator de cada task e o `piso_conjunto` já aplicados, mas **antes** do "
    "arredondamento à hora inteira do Passo 6 — e esse intervalo tem de estar **contido** em "
    "`[ soma( o(t) * fator(t) ), soma( p(t) * fator(t) ) ]`, os limites corrigidos task a task "
    "pelos mesmos fatores que entraram na agregação. Se não estiver, você errou a conta — refaça. "
    "Comparar com o intervalo bruto (sem fator) reprova conta certa sempre que algum fator é "
    "abaixo de 1: no exemplo acima, o `min` decimal e já pisado `3,7333` fica fora de `[4, 12]` e "
    "dentro de `[3,20, 9,60]`. Nunca compare essa sanidade contra a faixa **publicada** — já "
    "arredondada por `floor(min)`/`ceil(max)` à hora inteira: o arredondamento alarga a faixa para "
    "fora, nunca para dentro, então a publicada pode deixar de estar contida no intervalo "
    "corrigido mesmo numa conta certa — no mesmo exemplo ela é `3–6 h`, e `3` não fica acima de "
    "`3,20`. A sanidade é sempre sobre o decimal do Passo 5, nunca sobre o arredondado do Passo 6.")
velho_par = ("**Verificação obrigatória de sanidade:** a faixa agregada de qualquer conjunto tem "
    "de ser **mais estreita** que `[ soma( o(t) * fator(t) ), soma( p(t) * fator(t) ) ]` — os "
    "limites corrigidos task a task, pelos mesmos fatores que entraram na agregação. Se não for, "
    "você errou a conta — refaça. Comparar com o intervalo bruto reprova conta certa sempre que "
    "algum fator é abaixo de 1: no exemplo acima, `min` `3,7333` fica fora de `[4, 12]` e dentro "
    "de `[3,20, 9,60]`.")
assert novo_par in s, "paragrafo corrigido nao encontrado — ajuste o mutante"
s = s.replace(novo_par, velho_par)
novo_chk = ("- [ ] O `[min, max]` decimal do Passo 5 — já com o fator por task e o piso "
    "`piso_conjunto` aplicados, ainda antes do arredondamento à hora inteira do Passo 6 — está "
    "contido em `[ soma( o(t) * fator(t) ), soma( p(t) * fator(t) ) ]` (senão a quadratura foi "
    "feita errado). Nunca compare a faixa já publicada, em hora inteira, contra esse intervalo "
    "decimal — o arredondamento alarga a faixa e reprovaria conta certa.")
velho_chk = ("- [ ] A faixa agregada é mais estreita que `[ soma( o(t) * fator(t) ), soma( p(t) * "
    "fator(t) ) ]` (senão a quadratura foi feita errado), e o piso aplicado a `min` foi "
    "`piso_conjunto`, antes do arredondamento à hora inteira.")
assert novo_chk in s, "checklist corrigido nao encontrado — ajuste o mutante"
s = s.replace(novo_chk, velho_chk)
open(p, "w", encoding="utf-8").write(s)
PYEOF
Z_MB_RC=$?
! cmp -s "$Z_EST" "$ZM_B/references/07-estimativa.md"; Z_MB_GEROU=$?
ZM_B_SAN_TXT="$(grep -F 'Verificação obrigatória de sanidade' "$ZM_B/references/07-estimativa.md")"
printf '%s' "$ZM_B_SAN_TXT" | grep -qi 'publicada'; ZM_B_PAR_PUB=$?
ZM_B_CHK_LINHA="$(grep -F 'estreita' "$ZM_B/references/07-estimativa.md" | grep -F -- '- [ ]')"
printf '%s' "$ZM_B_CHK_LINHA" | grep -qi 'decimal'; ZM_B_CHK_DEC=$?
[ "$Z_MB_RC" -eq 0 ] && [ "$Z_MB_GEROU" -eq 0 ] && [ "$ZM_B_PAR_PUB" -ne 0 ] && [ "$ZM_B_CHK_DEC" -ne 0 ]
afirma "z8k4b-mutante-reverte-sanidade-para-faixa-publicada-morto-por-z8k2" $? \
  "geracao rc=$Z_MB_RC mudou=$Z_MB_GEROU paragrafo cita publicada=$ZM_B_PAR_PUB checklist cita decimal=$ZM_B_CHK_DEC"

# 8l. A decisao esta registrada e e APPEND-ONLY: DS-163 entra estendendo a DS-41, e a DS-41 fica
#     byte a byte como estava. Reescrever uma decisao antiga apaga o rastro de por que a nova
#     existe — e o registro e onde a proxima sessao encontra o porque.
Z_DS163="$(grep -F '| DS-163 |' "$Z_DS")"
[ -n "$Z_DS163" ]
afirma "z8l-ds163-registrada" $? "a decisao do piso existe no registro"
[ "$(printf '%s' "$Z_DS163" | grep -cF 'DS-41')" -gt 0 ]; z_rc=$?
afirma "z8m-ds163-declara-que-estende-ds41" "$z_rc" "DS-163 nomeia a DS-41 que ela estende"
Z_DS163_F="$W/.z-ds163"; printf '%s\n' "$Z_DS163" > "$Z_DS163_F"
z_fml_tem "$Z_DS163_F" "$Z_PISO_FML"
afirma "z8n-ds163-traz-a-formula-do-piso" $? "DS-163 escreve $Z_PISO_FML"

# A DS-41 intacta: conteudo e tamanho conferidos pelo cksum da propria linha (376 bytes, a linha
# com o \n do grep). Qualquer reescrita, ate de uma virgula, muda o par.
Z_DS41_CK_ESPERADO='2616782449 376'
Z_DS41_CK="$(grep -F '| DS-41 |' "$Z_DS" | cksum)"
[ "$(grep -cF '| DS-41 |' "$Z_DS")" -eq 1 ] && [ "$Z_DS41_CK" = "$Z_DS41_CK_ESPERADO" ]
afirma "z8o-ds41-permanece-byte-a-byte" $? "cksum=[$Z_DS41_CK] esperado=[$Z_DS41_CK_ESPERADO]"

# 9. A decisao esta registrada: DS-160 fixa a receita, e o registro e onde a proxima sessao
#    encontra o PORQUE — sem ele, a convencao volta a ser escolha de quem executa.
Z_DS160="$(grep -F '| DS-160 |' "$Z_DS")"
[ -n "$Z_DS160" ]
afirma "z9-ds160-registrada" $? "a decisao da precisao existe no registro"
[ "$(printf '%s' "$Z_DS160" | grep -ciE 'half-up|meio para cima')" -gt 0 ]; z_rc=$?
afirma "z9b-ds160-fixa-o-desempate" "$z_rc" "DS-160 diz half-up"
[ "$(printf '%s' "$Z_DS160" | grep -ciE 'duas casas')" -gt 0 ]; z_rc=$?
afirma "z9c-ds160-fixa-as-casas" "$z_rc" "DS-160 diz duas casas"

# 10. A chave e o schema nao mudam: a correcao e da precisao do valor, nao do formato. Nenhum
#     parser afetado, nenhuma chave nova, e `desvio`/`desvio_medio` continuam numeros no YAML
#     (nunca string com casas embutidas, que e como se fabrica "duas casas" a forca).
grep -qF 'desvio_medio:' "$Z_SCH" && grep -qF 'desvio_medio:' "$Z_TPL"
afirma "z10-chaves-preservadas" $? "desvio e desvio_medio continuam as chaves"
Z_STRINGS="$(grep -rnE '^[[:space:]]*(desvio|desvio_medio|fator_correcao_aplicado):[[:space:]]*["'"'"']' \
  $Z_DEFINEM "$Z_TES" | tr '\n' ' ')"
[ -z "$Z_STRINGS" ]
afirma "z10b-nenhum-valor-virou-string" $? "ocorrencias=[${Z_STRINGS:-nenhuma}]"

