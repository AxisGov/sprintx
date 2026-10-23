#!/usr/bin/env bash
#
# Secoes AG a AK da bancada: rastro serializado, dono da task, saida da suite e fator medido.
# Carregada por `.` de dentro da bancada.sh, no mesmo ponto e na mesma ordem: usa os
# auxiliares e o estado dela. Mora aqui porque o CodeAnt pula arquivo acima de 5.000 linhas
# ou 200 KB (expxdev, docs/superpowers/specs/2026-10-19-limites-do-codeant-emenda.md).

echo "== AG. suite_executada.detalhe corta em 120 BYTES sem partir UTF-8, com e sem jq (5533410/bb1378f) =="
# `cut -c1-120` nao serve para cortar o detalhe de `suite_executada`, por dois motivos
# independentes:
#
#   1. o comportamento de `-c` (byte ou caractere) depende da locale do processo que roda o
#      hook, que o hook nao controla. Sem locale UTF-8 o corte e por byte e deixa a sequencia
#      multibyte do limite INCOMPLETA: o byte-lider (0xC3, no defeito observado) fica pendurado
#      sem o byte de continuacao (0x80-0xBF) que ele anuncia, e o jsonl do trabalho deixa de ser
#      UTF-8 valido — o contrato expx-eventos exige UTF-8 valido, e o painel para de decodificar
#      o arquivo inteiro a partir dali (visto em docs/eventos/sem-trabalho.jsonl);
#   2. `cut` corta LINHA POR LINHA. Comando de suite multilinha passa inteiro, com cada linha
#      cortada em 120 — o detalhe estoura o limite em vez de respeita-lo.
#
# O corte certo e sempre por byte, com a sequencia incompleta do fim removida INTEIRA
# (`rastro_corta_utf8_em`). Cada caso monta um comando de suite com prefixo ASCII de (120-k)
# bytes e o caractere de <largura> bytes repetido, de forma que o limite de 120 caia exatamente
# depois de k bytes do primeiro desses caracteres:
#
#   k <  largura -> sequencia incompleta no fim: tem de sumir inteira
#   k == largura -> sequencia completa terminando NO byte 120: tem de ser preservada (guarda
#                   contra aparar demais, e o unico papel desses casos)
#
# O oraculo le o jsonl GRAVADO pelo hook real (nao a funcao isolada) como UTF-8 estrito e JSON
# estrito, e compara o `detalhe` com o valor exato esperado, medindo o limite em BYTES, que e a
# unidade do contrato. As duas rotas de leitura do payload sao exercidas: com jq (processo) e no
# fallback sem jq (builtin) — e por elas que o comando chega ao corte.
AG_T="$(mktemp -d)"
AG_H="$(cd "$H" && pwd)"
AG_JSONL="$AG_T/repo/docs/eventos/sem-trabalho.jsonl"

# Um PATH equivalente ao atual, sem nenhum `jq` executavel: mesma tecnica da secao W (espelho de
# symlinks dos diretorios que tem jq), com espelho proprio porque a secao W apaga o dela no fim.
ag_path_sem_jq() {
  local d f espelho novo="" i=0 IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    if [ -x "$d/jq" ]; then
      i=$((i+1)); espelho="$AG_T/bin$i"
      if [ ! -d "$espelho" ]; then
        mkdir -p "$espelho"
        for f in "$d"/*; do
          [ -e "$f" ] || continue
          [ "${f##*/}" = jq ] && continue
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
AG_SEMJQ="$(ag_path_sem_jq)"

# Fixture minima, como na secao Q: raiz com .git e docs/eventos. Sem reivindicacao de sessao no
# rastro, o destino do evento e docs/eventos/sem-trabalho.jsonl (DS-155) — o arquivo do defeito.
ag_roda() { # ag_roda <comando> <PATH do caso> [resposta da ferramenta]
  rm -rf "$AG_T/repo"; mkdir -p "$AG_T/repo/.git" "$AG_T/repo/docs/eventos"
  python3 -c "
import json, sys
print(json.dumps({'cwd': sys.argv[1], 'tool_name': 'Bash', 'tool_input': {'command': sys.argv[2]}, 'tool_response': sys.argv[3]}))
" "$AG_T/repo" "$1" "${3-}" > "$AG_T/payload.json"
  (cd "$AG_T/repo" && PATH="$2" bash "$AG_H/comum/rastro-post.sh") < "$AG_T/payload.json" >/dev/null 2>&1
}
ag_confere() { # ag_confere <detalhe esperado> — jsonl UTF-8 estrito, JSON estrito, detalhe exato
  AG_ESPERADO="$1" python3 - "$AG_JSONL" 2>"$AG_T/erro" <<'PY'
import json, os, sys
bruto = open(sys.argv[1], 'rb').read()
texto = bruto.decode('utf-8')  # UnicodeDecodeError se sobrou byte UTF-8 invalido
linhas = [l for l in texto.splitlines() if l.strip()]
assert len(linhas) == 1, 'esperava 1 linha no jsonl, veio %d' % len(linhas)
evento = json.loads(linhas[0])  # falha se a linha nao for JSON valido
assert evento['evento'] == 'suite_executada', 'evento gravado: %r' % evento['evento']
detalhe = evento['detalhe']
tam = len(detalhe.encode('utf-8'))
assert tam <= 120, 'detalhe com %d bytes, o limite e 120' % tam
esperado = os.environ['AG_ESPERADO']
assert detalhe == esperado, 'detalhe=%r (%d bytes) esperado=%r' % (detalhe, tam, esperado)
PY
}
ag_erro() { tr '\n' ' ' < "$AG_T/erro" | tail -c 180; }
ag_caso() { # ag_caso <nome> <char> <largura> <k> <rota> <PATH do caso>
  local nome="$1" ch="$2" largura="$3" k="$4" rota="$5" caminho="$6" enchimento prefixo esperado rc det
  # "npm test -- " tem 12 bytes, logo 108-k de enchimento fecham os 120-k do prefixo. A troca de
  # espaco por `x` e so no enchimento: em "npm test -- " ela desfaria o padrao de suite do hook.
  printf -v enchimento '%*s' "$((108 - k))" ''
  prefixo="npm test -- ${enchimento// /x}"
  if [ "$k" -eq "$largura" ]; then esperado="$prefixo$ch"; else esperado="$prefixo"; fi
  ag_roda "$prefixo$ch$ch$ch" "$caminho"
  ag_confere "$esperado"; rc=$?
  if [ "$rc" -eq 0 ]; then det="limite cai depois de $k de $largura bytes; jsonl utf-8, json valido, detalhe exato"
  else det="$(ag_erro)"; fi
  afirma "$nome-$rota" "$rc" "$det"
}
# Comando multilinha vira UMA linha de texto antes do corte, como exige o contrato de `detalhe`.
# Aqui o byte 120 cai no meio do 'a' acentuado da SEGUNDA linha ja normalizada — prova as duas
# coisas de uma vez: as quebras viram espaco e a sequencia incompleta do fim sai.
ag_multilinha() { # ag_multilinha <rota> <PATH do caso>
  local rota="$1" caminho="$2" enchimento l1 l2 l3 cmd esperado rc det
  printf -v enchimento '%*s' 48 ''; l1="npm test -- ${enchimento// /x}"  # 60 bytes
  printf -v l2 '%*s' 58 ''; l2="${l2// /y}"                              # bytes 62..119
  printf -v l3 '%*s' 30 ''; l3="${l3// /z}"                              # depois do limite
  cmd="$l1"$'\n'"$l2"'á'$'\n'"$l3"                                       # 'á' nos bytes 120 e 121
  esperado="$l1 $l2"
  ag_roda "$cmd" "$caminho"
  ag_confere "$esperado"; rc=$?
  if [ "$rc" -eq 0 ]; then det="3 linhas normalizadas em uma: 119 bytes, sem o 'a' acentuado partido"
  else det="$(ag_erro)"; fi
  afirma "ag11-multilinha-normalizado-em-uma-linha-$rota" "$rc" "$det"
}
# O espelho tem de esconder o jq E continuar servindo o resto: espelho vazio (ou apagado) faria
# todos os casos sem jq passarem sem rodar nada. Na maquina sem jq e no-op, e as duas rotas
# coincidem — como na secao W.
ag_sandbox_valida() {
  PATH="$AG_SEMJQ" command -v jq >/dev/null 2>&1 && return 1
  PATH="$AG_SEMJQ" command -v bash >/dev/null 2>&1 || return 1
  PATH="$AG_SEMJQ" command -v grep >/dev/null 2>&1 || return 1
  return 0
}
ag_sandbox_valida; AG_RC=$?
afirma "ag0-sandbox-esconde-jq-e-serve-o-resto" "$AG_RC" "PATH do caso sem jq, com bash e grep"

for AG_ROTA in com-jq sem-jq; do
  AG_PATH="$PATH"; [ "$AG_ROTA" = sem-jq ] && AG_PATH="$AG_SEMJQ"
  ag_caso "ag1-2b-parte-1-de-2"   'á'  2 1 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag2-2b-completo"       'á'  2 2 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag3-3b-parte-1-de-3"   '€'  3 1 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag4-3b-parte-2-de-3"   '€'  3 2 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag5-3b-completo"       '€'  3 3 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag6-4b-parte-1-de-4"   '🚀' 4 1 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag7-4b-parte-2-de-4"   '🚀' 4 2 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag8-4b-parte-3-de-4"   '🚀' 4 3 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag9-4b-completo"       '🚀' 4 4 "$AG_ROTA" "$AG_PATH"
  ag_caso "ag10-ascii-no-limite"  'Z'  1 1 "$AG_ROTA" "$AG_PATH"
  ag_multilinha "$AG_ROTA" "$AG_PATH"
done

# Maven e uma suite suportada. Saidas canonicas de falha nao usam necessariamente a palavra
# `FAIL` isolada: `[ERROR]` e `BUILD FAILURE` tambem precisam gravar resultado `falha`.
ag_roda "mvn test" "$PATH" $'[ERROR] Failed to execute goal\n[INFO] BUILD FAILURE'
python3 - "$AG_JSONL" 2>"$AG_T/erro" <<'PY'
import json, sys
evento = json.loads(open(sys.argv[1], encoding='utf-8').readline())
assert evento['resultado'] == 'falha', 'resultado Maven=%r, esperado falha' % evento['resultado']
PY
AG_RC=$?
afirma "ag12-maven-build-failure-e-falha" "$AG_RC" "[ERROR] e BUILD FAILURE classificam mvn test como falha"

# A correcao mora num lugar so: as duas rotas que EXECUTAM o hook — settings.json do Claude Code
# e o plugin do OpenCode — invocam o mesmo comum/rastro-post.sh, e nenhum hook volta a cortar
# texto com `cut -c` (que e byte ou caractere conforme a locale, e corta linha por linha).
ag_cut_em_codigo() { # usos de `cut -c` em CODIGO de hook (comentario que o cita nao conta)
  grep -rn 'cut -c' "$H/comum" "$H/sprintx" 2>/dev/null | sed 's/^[^:]*:[0-9]*://' | grep -v '^[[:space:]]*#'
}
AG_CUT="$(ag_cut_em_codigo)"; AG_CUT="${AG_CUT//$'\n'/ | }"
AG_ROTA_CC="$(conta "$H/../settings.json" 'comum/rastro-post.sh')"
AG_ROTA_OC="$(conta "$H/../../.opencode/plugin/sprintx.ts" 'comum/rastro-post.sh')"
[ -z "$AG_CUT" ] && [ "$AG_ROTA_CC" -eq 1 ] && [ "$AG_ROTA_OC" -eq 1 ]; AG_RC=$?
afirma "ag13-rotas-compartilham-o-mesmo-hook" "$AG_RC" "rotas para comum/rastro-post.sh: claude-code=$AG_ROTA_CC opencode=$AG_ROTA_OC; cut -c em codigo de hook: ${AG_CUT:-nenhum}"
rm -rf "$AG_T"

echo "== AH. serializacao do rastro: todo controle JSON escapado, marcador sem colisao, falha de escrita nao mascarada (PR#12) =="
# Tres defeitos independentes da serializacao, todos alcancaveis pelo mesmo payload — um comando
# de suite que leva caractere de controle (barra de progresso, cor de terminal, separador de
# registro). O JSON do harness os entrega escapados (U+0001 vira a sequencia de seis bytes que
# comeca em barra-u); o que o rastro fazia com eles e que estava errado:
#
#   1. COLISAO DE MARCADOR. `rastro_json_campo_em` escondia a barra escapada atras do byte 0x01
#      antes de decodificar as sequencias U+XXXX, e devolvia esse marcador a barra no fim. Um
#      U+0001 do proprio payload decodifica para o MESMO byte 0x01: na volta ele virava barra
#      invertida. "a<U+0001>b" saia "a\b" — valor corrompido, e divergente do que o jq entrega
#      na mesma leitura, quebrando a paridade que o contrato promete entre as duas rotas.
#   2. BYTE DE CONTROLE CRU NO JSONL. `rastro_json_escape_em` escapava so barra, aspa, TAB, CR e
#      LF. Todo o resto de U+0000..U+001F ia CRU para dentro da string JSON — e JSON proibe
#      controle cru dentro de string: a linha gravada deixava de ser JSON valido e o leitor do
#      rastro perde o arquivo a partir dali, o mesmo estrago do byte UTF-8 partido da secao AG.
#   3. CLASSIFICACAO DE ESCRITA MASCARADA. `rastro_grava_trabalho` punha `divergente`/`invalido`
#      em RASTRO_GRAVACAO DEPOIS de tentar gravar a linha de diagnostico — por cima do `falha`
#      que a propria tentativa acabara de deixar. Com a gravacao impossivel, o escritor publico
#      da skill anunciava "feche a task aberta do outro trabalho" (codigo 4, contrato) quando o
#      fato era que nada podia ser escrito (codigo 5, ambiente): diagnostico publico com a causa
#      errada, e o unico codigo que avisa o agente que o rastro parou de aceitar linha se perdia.
#
# Nenhum caso escreve a sequencia de escape a mao: os payloads saem de `json.dumps`, que escapa
# controle por obrigacao do proprio formato — e por isso o teste exerce o escape REAL do harness.
AH_T="$(mktemp -d)"
AH_H="$(cd "$H" && pwd)"
AH_SK="$(cd "$H/../skills/sprintx" && pwd)"

# PATH sem jq, mesma tecnica e mesma justificativa das secoes W e AG (espelho de symlinks dos
# diretorios que tem jq), com espelho proprio porque cada secao apaga o seu no fim.
ah_path_sem_jq() {
  local d f espelho novo="" i=0 IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    if [ -x "$d/jq" ]; then
      i=$((i+1)); espelho="$AH_T/bin$i"
      if [ ! -d "$espelho" ]; then
        mkdir -p "$espelho"
        for f in "$d"/*; do
          [ -e "$f" ] || continue
          [ "${f##*/}" = jq ] && continue
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
AH_SEMJQ="$(ah_path_sem_jq)"
if PATH="$AH_SEMJQ" command -v jq >/dev/null 2>&1; then AH_RC=1
else PATH="$AH_SEMJQ" command -v grep >/dev/null 2>&1; AH_RC=$?
fi
afirma "ah0-sandbox-esconde-jq-e-serve-o-resto" "$AH_RC" "PATH do caso sem jq, com grep"

# Os bytes 0x01..0x1F, todos, menos o NUL — que nao cabe numa variavel de shell e por isso nunca
# chega ao serializador. `printf -v` + `%b` constroem cada byte sem criar processo.
ah_todos_controles() {
  local i c
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31; do
    printf -v c '\\%03o' "$i"; printf '%b' "$c"
  done
}

# Extrator isolado, o mesmo molde da secao W: le a chave pelo helper publico e grava o valor CRU
# num arquivo, para a comparacao nao passar por substituicao de comando (que come byte do fim).
cat > "$AH_T/extrai.sh" <<'SH'
. "$1/comum/rastro.sh"
IFS= read -r -d '' J < "$2"
V="$(rastro_tool_input_get "$J" command)"
printf '%s' "$V" > "$3"
SH
# Serializador isolado: escapa o texto do arquivo e monta UMA string JSON com ele.
cat > "$AH_T/serializa.sh" <<'SH'
. "$1/comum/rastro.sh"
IFS= read -r -d '' TEXTO < "$2"
rastro_json_escape_em E "$TEXTO"
printf '{"detalhe":"%s"}' "$E" > "$3"
SH
# Gravador isolado: o desfecho publico de uma gravacao, como a skill o le (DS-159).
cat > "$AH_T/grava.sh" <<'SH'
. "$1/comum/rastro.sh"
rastro_grava_trabalho "$2" "$3" task_iniciada skill ok "evento de prova" '[]' '"sessao":"seg@1","harness":"seg"'
printf '%s' "${RASTRO_GRAVACAO:-vazio}"
SH

ah_payload() { # ah_payload <arquivo-com-o-comando> <cwd> <arquivo-de-saida>
  python3 -c '
import json, sys
texto = open(sys.argv[1], "rb").read().decode("utf-8")
linha = json.dumps({"cwd": sys.argv[2], "tool_name": "Bash", "tool_input": {"command": texto}})
open(sys.argv[3], "w", encoding="utf-8").write(linha + "\0")
' "$1" "$2" "$3"
}
ah_bytes() { od -An -c < "$1" | tr -s ' \n' ' '; }

# ---------------------------------------------------------------- 1. leitura do payload
ah_leitura() { # ah_leitura <nome> <texto> <detalhe do caso>
  local nome="$1" det="$3" rc
  printf '%s' "$2" > "$AH_T/fonte.txt"
  ah_payload "$AH_T/fonte.txt" /x "$AH_T/payload.json"
  PATH="$AH_SEMJQ" bash "$AH_T/extrai.sh" "$AH_H" "$AH_T/payload.json" "$AH_T/sem.txt"
  bash "$AH_T/extrai.sh" "$AH_H" "$AH_T/payload.json" "$AH_T/com.txt"
  cmp -s "$AH_T/sem.txt" "$AH_T/fonte.txt" && cmp -s "$AH_T/com.txt" "$AH_T/fonte.txt"; rc=$?
  [ "$rc" -eq 0 ] || det="sem-jq=[$(ah_bytes "$AH_T/sem.txt")] com-jq=[$(ah_bytes "$AH_T/com.txt")] esperado=[$(ah_bytes "$AH_T/fonte.txt")]"
  afirma "$nome" "$rc" "$det"
}
printf -v AH_CTRL 'a\001b\002c'
ah_leitura "ah1-controle-sobrevive-nas-duas-rotas" "$AH_CTRL" \
  "U+0001 e U+0002 do payload voltam como os proprios bytes, com jq e sem jq"
printf -v AH_MIX 'd:\\ e a\001b\002c'
ah_leitura "ah2-barra-escapada-e-controle-no-mesmo-valor" "$AH_MIX" \
  "barra invertida literal e controle convivem: nenhum dos dois vira o outro"
printf -v AH_BARRA 'x\\y'
ah_leitura "ah3-barra-escapada-sozinha-nao-regride" "$AH_BARRA" \
  "a barra escapada continua decodificada (guarda contra consertar 1 quebrando 2)"
printf -v AH_BSN 'p\\nq'
ah_leitura "ah4-barra-literal-seguida-de-n-nao-vira-quebra" "$AH_BSN" \
  "barra invertida seguida de 'n' e barra + n, nunca uma quebra de linha"
AH_TODOS="$(ah_todos_controles)"
ah_leitura "ah5-todo-controle-de-0x01-a-0x1f-sobrevive" "$AH_TODOS" \
  "os 31 bytes de controle do payload voltam identicos nas duas rotas"

# O gerador normal acima usa json.dumps. Estes dois casos escrevem o JSON de entrada a mao para
# fixar a fronteira que ele nao consegue distinguir: U+005C seguido de `n`, literal ou codificado
# como outro U+XXXX, tem de virar barra + n — nunca LF. A rota com jq e o fallback sem jq precisam
# devolver exatamente os mesmos dois bytes.
ah_json_manual() { # ah_json_manual <nome> <valor JSON sem aspas> <valor esperado>
  local nome="$1" codificado="$2" esperado="$3" rc det
  printf '{"cwd":"/x","tool_name":"Bash","tool_input":{"command":"%s"}}\0' \
    "$codificado" > "$AH_T/payload-manual.json"
  printf '%s' "$esperado" > "$AH_T/esperado-manual.txt"
  PATH="$AH_SEMJQ" bash "$AH_T/extrai.sh" "$AH_H" "$AH_T/payload-manual.json" "$AH_T/sem-manual.txt"
  bash "$AH_T/extrai.sh" "$AH_H" "$AH_T/payload-manual.json" "$AH_T/com-manual.txt"
  cmp -s "$AH_T/sem-manual.txt" "$AH_T/esperado-manual.txt" \
    && cmp -s "$AH_T/com-manual.txt" "$AH_T/esperado-manual.txt" \
    && cmp -s "$AH_T/sem-manual.txt" "$AH_T/com-manual.txt"; rc=$?
  [ "$rc" -eq 0 ] || det="sem-jq=[$(ah_bytes "$AH_T/sem-manual.txt")] com-jq=[$(ah_bytes "$AH_T/com-manual.txt")] esperado=[$(ah_bytes "$AH_T/esperado-manual.txt")]"
  afirma "$nome" "$rc" "${det:-barra + n literal, igual com jq e sem jq}"
}
ah_json_manual "ah5b-u005c-seguido-de-n-nao-vira-lf" '\u005cn' '\n'
ah_json_manual "ah5c-u005c-e-u006e-nao-viram-lf" '\u005c\u006e' '\n'

# ---------------------------------------------------------------- 2. escrita da string JSON
cat > "$AH_T/confere-json.py" <<'PY'
import json, sys
bruto = open(sys.argv[1], 'rb').read()
cru = sorted(set(b for b in bruto if b < 0x20))
assert not cru, 'byte(s) de controle CRU na string JSON: %r' % cru
valor = json.loads(bruto.decode('utf-8'))['detalhe']   # falha se nao for JSON valido
esperado = open(sys.argv[2], 'rb').read().decode('utf-8')
assert valor == esperado, 'detalhe=%r esperado=%r' % (valor, esperado)
PY
ah_serializa() { # ah_serializa <nome> <texto> <detalhe do caso>
  local nome="$1" det="$3" rc
  printf '%s\0' "$2" > "$AH_T/texto.bin"
  printf '%s' "$2" > "$AH_T/esperado.txt"
  bash "$AH_T/serializa.sh" "$AH_H" "$AH_T/texto.bin" "$AH_T/linha.json"
  python3 "$AH_T/confere-json.py" "$AH_T/linha.json" "$AH_T/esperado.txt" 2>"$AH_T/erro"; rc=$?
  [ "$rc" -eq 0 ] || det="$(tr '\n' ' ' < "$AH_T/erro" | tr -s ' ' | tail -c 200)"
  afirma "$nome" "$rc" "$det"
}
ah_serializa "ah6-serializa-controle-sem-byte-cru" "$AH_CTRL" \
  "U+0001 e U+0002 saem escapados; a string e JSON valido e volta identica"
ah_serializa "ah7-serializa-os-31-controles" "$AH_TODOS" \
  "0x01..0x1F todos escapados, nenhum byte cru, round-trip exato"
printf -v AH_ASPAS 'a"b\\c\011d\012e'
ah_serializa "ah8-aspa-barra-tab-e-quebra-nao-regridem" "$AH_ASPAS" \
  "aspa, barra, TAB e LF continuam escapados (guarda contra regressao do escape antigo)"

# ---------------------------------------------------------------- 3. ponta a ponta pelo hook
# O payload vai ao hook PostToolUse real; o oraculo le o jsonl GRAVADO como UTF-8 estrito e JSON
# estrito, e confere o `detalhe` byte a byte. A fixture nao tem reivindicacao, entao o destino e
# docs/eventos/sem-trabalho.jsonl (DS-155).
AH_JSONL="$AH_T/repo/docs/eventos/sem-trabalho.jsonl"
cat > "$AH_T/confere-jsonl.py" <<'PY'
import json, sys
bruto = open(sys.argv[1], 'rb').read()
assert bruto.endswith(b'\n'), 'a linha gravada nao termina em LF'
corpo = bruto[:-1]
cru = sorted(set(b for b in corpo if b < 0x20))
assert not cru, 'byte(s) de controle CRU no jsonl: %r' % cru
evento = json.loads(corpo.decode('utf-8'))             # UTF-8 e JSON estritos
assert evento['evento'] == 'suite_executada', 'evento gravado: %r' % evento['evento']
esperado = open(sys.argv[2], 'rb').read().decode('utf-8')
assert evento['detalhe'] == esperado, 'detalhe=%r esperado=%r' % (evento['detalhe'], esperado)
PY
ah_hook() { # ah_hook <nome> <comando> <rota> <PATH do caso>
  local nome="$1" cmd="$2" rota="$3" caminho="$4" rc det
  rm -rf "$AH_T/repo"; mkdir -p "$AH_T/repo/.git" "$AH_T/repo/docs/eventos"
  printf '%s' "$cmd" > "$AH_T/cmd.txt"
  printf '%s' "$cmd" > "$AH_T/esp-hook.txt"
  ah_payload "$AH_T/cmd.txt" "$AH_T/repo" "$AH_T/p-hook.json"
  (cd "$AH_T/repo" && PATH="$caminho" bash "$AH_H/comum/rastro-post.sh") < "$AH_T/p-hook.json" >/dev/null 2>&1
  python3 "$AH_T/confere-jsonl.py" "$AH_JSONL" "$AH_T/esp-hook.txt" 2>"$AH_T/erro"; rc=$?
  if [ "$rc" -eq 0 ]; then det="jsonl utf-8 e json estritos, sem controle cru, detalhe exato"
  else det="$(tr '\n' ' ' < "$AH_T/erro" | tr -s ' ' | tail -c 200)"; fi
  afirma "$nome-$rota" "$rc" "$det"
}
printf -v AH_SUITE 'npm test -- a\001b\002c\011d\033[0me\037f'
for AH_ROTA in com-jq sem-jq; do
  AH_PATH="$PATH"; [ "$AH_ROTA" = sem-jq ] && AH_PATH="$AH_SEMJQ"
  ah_hook "ah9-suite-executada-com-controle-no-comando" "$AH_SUITE" "$AH_ROTA" "$AH_PATH"
done

# ---------------------------------------------------------------- 4. classificacao da gravacao
# A fixture: a sessao `seg@1` reivindica o trabalho `outro`; pedir gravacao em `alvo` cai no ramo
# `divergente`, e pedir num slug torto cai no ramo `invalido`. Os dois tentam gravar a linha de
# diagnostico em docs/eventos/sem-trabalho.jsonl — e e essa tentativa que a fixture faz FALHAR,
# trocando o arquivo por um DIRETORIO de mesmo nome (sem mexer em permissao, que varia de
# plataforma): `printf >>` sobre diretorio nao escreve, e `[ -f ]` o mantem fora da varredura.
# Os dois casos "gravavel" sao o controle: sem eles, um conserto que sempre devolvesse `falha`
# passaria — e `divergente`/`invalido` sao exatamente a informacao que o codigo 4 publica.
ah_fixture() { # ah_fixture <sem-trabalho gravavel: sim|nao>
  rm -rf "$AH_T/g"; mkdir -p "$AH_T/g/.git" "$AH_T/g/docs/eventos"
  mkdir -p "$AH_T/g/docs/sprintx/features/alvo/sprint-01"
  printf '%s\n' '---' 'tasks:' '  - id: T-01.01' '---' \
    > "$AH_T/g/docs/sprintx/features/alvo/sprint-01/tasks.md"
  printf '%s\n' '{"ts":"2026-10-01T10:00:00Z","expx_eventos":1,"trabalho_id":"outro","ferramenta":"sprintx","origem":"skill","evento":"task_iniciada","fase":"f6","task":"T-09.09","agente":"principal","resultado":"ok","detalhe":null,"arquivos":[],"sessao":"seg@1","harness":"seg"}' \
    > "$AH_T/g/docs/eventos/outro.jsonl"
  if [ "$1" = sim ]; then : > "$AH_T/g/docs/eventos/sem-trabalho.jsonl"
  else mkdir -p "$AH_T/g/docs/eventos/sem-trabalho.jsonl"; fi
}
ah_classifica() { # ah_classifica <gravavel> <pedido> -> ecoa RASTRO_GRAVACAO
  ah_fixture "$1"
  (cd "$AH_T/g" && EXPX_SESSAO=seg@1 EXPX_HARNESS=seg \
    bash "$AH_T/grava.sh" "$AH_H" "$AH_T/g" "$2" 2>/dev/null)
}
AH_G="$(ah_classifica sim alvo)"
[ "$AH_G" = divergente ]
afirma "ah10-divergente-continua-divergente-quando-grava" $? "RASTRO_GRAVACAO=$AH_G (esperado divergente)"
AH_G="$(ah_classifica nao alvo)"
[ "$AH_G" = falha ]
afirma "ah11-divergente-sem-poder-gravar-e-falha" $? "RASTRO_GRAVACAO=$AH_G (esperado falha, nao divergente)"
AH_G="$(ah_classifica sim 'fora/do/lugar')"
[ "$AH_G" = invalido ]
afirma "ah12-invalido-continua-invalido-quando-grava" $? "RASTRO_GRAVACAO=$AH_G (esperado invalido)"
AH_G="$(ah_classifica nao 'fora/do/lugar')"
[ "$AH_G" = falha ]
afirma "ah13-invalido-sem-poder-gravar-e-falha" $? "RASTRO_GRAVACAO=$AH_G (esperado falha, nao invalido)"

# E o codigo PUBLICO que o agente le: 5 e "ambiente, nada pode ser escrito"; 4 e "contrato, feche
# a task do outro trabalho". Com a gravacao impossivel, o codigo publico tem de ser 5.
ah_publico() { # ah_publico <gravavel> -> ecoa o codigo de saida do escritor da skill
  local rc
  ah_fixture "$1"
  (cd "$AH_T/g" && SPRINTX_RAIZ="$AH_T/g" EXPX_SESSAO=seg@1 EXPX_HARNESS=seg \
    bash "$AH_SK/scripts/rastro.sh" task-iniciada alvo T-01.01 >/dev/null 2>&1)
  rc=$?; printf '%s' "$rc"
}
AH_RC_PUB="$(ah_publico sim)"
[ "$AH_RC_PUB" = 4 ]
afirma "ah14-escritor-da-skill-diz-4-na-divergencia" $? "exit=$AH_RC_PUB (esperado 4: contrato)"
AH_RC_PUB="$(ah_publico nao)"
[ "$AH_RC_PUB" = 5 ]
afirma "ah15-escritor-da-skill-diz-5-sem-poder-gravar" $? "exit=$AH_RC_PUB (esperado 5: ambiente, nunca 4)"

# ---------------------------------------------------------------- 5. mutantes dos tres contratos
# Copias temporarias do helper real provam que os casos acima nao sao decorativos. Cada mutante
# ressuscita exatamente um dos defeitos: reprocessar escapes curtos depois de U+XXXX, deixar os
# controles exoticos crus e mascarar uma falha de escrita com a classe de contrato.
AH_MUT="$AH_T/mutantes"
ah_copia_rastro() { # ah_copia_rastro <nome> -> ecoa a raiz da copia
  local d="$AH_MUT/$1"
  mkdir -p "$d/comum"
  cp "$AH_H/comum/rastro.sh" "$d/comum/rastro.sh"
  printf '%s' "$d"
}

# m1 — simula a ordem antiga: o resultado de U+XXXX volta a passar pelos escapes curtos.
AH_M1="$(ah_copia_rastro ordem-antiga)"
AH_OLD_ORDER='          _v="$_out" ;;'
IFS= read -r -d '' AH_NEW_ORDER <<'EOF' || true
          _v="${_out//\\n/$'\n'}" ;;
EOF
muta_lit "$AH_M1/comum/rastro.sh" "$AH_M1/comum/rastro.sh.m" "$AH_OLD_ORDER" "$AH_NEW_ORDER" \
  && mv "$AH_M1/comum/rastro.sh.m" "$AH_M1/comum/rastro.sh"
AH_MRC=$?
PATH="$AH_SEMJQ" bash "$AH_T/extrai.sh" "$AH_M1" "$AH_T/payload-manual.json" "$AH_T/m1.txt" 2>/dev/null
[ "$AH_MRC" -eq 0 ] && ! cmp -s "$AH_T/m1.txt" "$AH_T/esperado-manual.txt"; AH_RC=$?
afirma "ahm1-ordem-antiga-morre-no-u005c-u006e" "$AH_RC" \
  "a copia que reprocessa escapes curtos nao devolve barra + n"

# m2 — remove o escape generico que cobre os controles sem forma curta.
AH_M2="$(ah_copia_rastro sem-controle-generico)"
AH_OLD_CTRL='        s="${s//"$_b"/\\u00$_hex}"'
AH_NEW_CTRL='        : # mutante: controle exotico fica cru'
muta_lit "$AH_M2/comum/rastro.sh" "$AH_M2/comum/rastro.sh.m" "$AH_OLD_CTRL" "$AH_NEW_CTRL" \
  && mv "$AH_M2/comum/rastro.sh.m" "$AH_M2/comum/rastro.sh"
AH_MRC=$?
printf '%s\0' "$AH_CTRL" > "$AH_T/m2.bin"
printf '%s' "$AH_CTRL" > "$AH_T/m2-esperado.txt"
bash "$AH_T/serializa.sh" "$AH_M2" "$AH_T/m2.bin" "$AH_T/m2.json" 2>/dev/null
python3 "$AH_T/confere-json.py" "$AH_T/m2.json" "$AH_T/m2-esperado.txt" >/dev/null 2>&1
AH_BAD=$?
[ "$AH_MRC" -eq 0 ] && [ "$AH_BAD" -ne 0 ]; AH_RC=$?
afirma "ahm2-sem-escape-generico-morre-no-json-estrito" "$AH_RC" \
  "a copia deixa U+0001/U+0002 crus e o oraculo JSON estrito reprova"

# m3 — volta a atribuir a classe depois da tentativa de gravacao, apagando `falha`.
AH_M3="$(ah_copia_rastro mascara-falha)"
AH_OLD_FALHA='  [ "${RASTRO_GRAVACAO:-}" = falha ] || RASTRO_GRAVACAO="$1"'
AH_NEW_FALHA='  RASTRO_GRAVACAO="$1"'
muta_lit "$AH_M3/comum/rastro.sh" "$AH_M3/comum/rastro.sh.m" "$AH_OLD_FALHA" "$AH_NEW_FALHA" \
  && mv "$AH_M3/comum/rastro.sh.m" "$AH_M3/comum/rastro.sh"
AH_MRC=$?
ah_fixture nao
AH_MUT_G="$(cd "$AH_T/g" && EXPX_SESSAO=seg@1 EXPX_HARNESS=seg \
  bash "$AH_T/grava.sh" "$AH_M3" "$AH_T/g" alvo 2>/dev/null)"
[ "$AH_MRC" -eq 0 ] && [ "$AH_MUT_G" != falha ]; AH_RC=$?
afirma "ahm3-classe-que-mascara-falha-morre-na-precedencia" "$AH_RC" \
  "a copia devolve $AH_MUT_G em vez de falha, e ah11/ah13 a rejeitam"

rm -rf "$AH_T"

echo "== AI. fechar task e do DONO da reivindicacao; dona indeterminada nao e dona ausente (PR#12, PR#14) =="
# Dois defeitos de ownership no escritor oficial dos eventos de reivindicacao (DS-159):
#
#   1. `task-concluida` e `task-bloqueada` nao olhavam QUEM tem a task aberta. A reivindicacao e
#      o evento `task_iniciada` mais recente sem fechamento depois (DS-150/153) — e um fechamento
#      gravado por OUTRA sessao e, para toda leitura do rastro, o fechamento dela: a sessao dona
#      perdia a reivindicacao sem nunca ter fechado nada, e a primeira edicao seguinte dela era
#      barrada com `sessao_ambigua`. Pior, a task liberada ficava reivindicavel por quem fechou.
#      Agora o escritor falha fechado (codigo 4, nada gravado) quando o dono e outra sessao.
#   2. `08-rastro.md` se contradizia no codigo `5`. A tabela de respostas mandava "siga sem o
#      evento" — mas, com o `escopo-da-task` ativo, um `task_iniciada` que NAO foi gravado
#      significa que a task NAO esta reivindicada: seguir e editar o primeiro arquivo da task
#      para ser barrado com `sessao_ambigua`, exatamente o beco do piloto C7-C. O codigo `5` nos
#      tres `task_*` passa a falhar fechado como o `3`: nao abra a task, nao grave a mao,
#      registre bloqueio `prerequisito_ausente`. Para `fase-*`/`veredito-emitido`, que nenhum
#      hook le, "siga sem o evento" continua certo — e a tabela passa a dizer os dois casos.
#
# O que esta correcao NAO faz, deliberadamente: nao muda a LEITURA do rastro (`_RASTRO_AWK_REIV`,
# `_sessao_dona`) para ignorar um fechamento de outra sessao ja gravado. Linha de reivindicacao
# escrita a mao e proibida pelo contrato (DS-159) e reprovada pela auditoria de transcrito
# (`transcrito-agente.sh`, regra `rastro_manual`): fechar a porta no escritor fecha o caminho que
# existe, sem quatro implementacoes de leitura divergindo sobre o que libera uma reivindicacao.
AI_T="$(mktemp -d)"
AI_H="$(cd "$H" && pwd)"
AI_SK="$(cd "$H/../skills/sprintx" && pwd)"
AI_N=0
AI_RC=0; AI_OUT=""

# Arvore no layout instalado, como a da secao U — e assim que o controle e os mutantes sao julgados.
ai_arvore() { # ai_arvore <nome>
  local r="$AI_T/arv/$1"
  rm -rf "$r"; mkdir -p "$r/.claude/hooks/testes" "$r/.claude/skills"
  cp -R "$AI_H/comum" "$AI_H/sprintx" "$r/.claude/hooks/"
  cp "$AI_H/testes/transcrito-agente.sh" "$r/.claude/hooks/testes/"
  cp -R "$AI_SK" "$r/.claude/skills/sprintx"
  printf '%s' "$r"
}
ai_task() { # ai_task <id> <status> <arquivo em altera>
  printf '  - id: %s\n    titulo: Task %s\n    status: %s\n    objetivo: obj\n    arquivos:\n      cria: []\n      altera: [%s]\n    teste_integracao: t\n    teste_funcional: t\n    criterio_aceite: c\n    depende_de: []\n    paralelizavel: false\n    concluida_em: null\n    suite: nao_executada\n' \
    "$1" "$1" "$2" "$3"
}
ai_plano() { # ai_plano <dir> <slug> <status T-01.01> <status T-01.02>
  local f="$1/docs/sprintx/features/$2/sprint-01/tasks.md"
  mkdir -p "$(dirname "$f")"
  { printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: tasks\ntrabalho_id: %s\nsprint_id: sprint-01\ntasks:\n' "$2"
    ai_task T-01.01 "$3" src/a.ts
    ai_task T-01.02 "$4" src/b.ts
    printf -- '---\n'; } > "$f"
}
ai_fx() { # repo git novo com o trabalho fx (T-01.01 -> src/a.ts, T-01.02 -> src/b.ts)
  AI_N=$((AI_N + 1)); AI_FX="$AI_T/fx$AI_N"
  mkdir -p "$AI_FX/src"; git init -q --template= "$AI_FX" >/dev/null 2>&1
  ai_plano "$AI_FX" fx em_andamento em_andamento
}
# O escritor, com a identidade que o Claude Code exporta — a derivada e `claude-code@<sessao>`.
ai_w() { # ai_w <arv> <dir> <sessao> <args do escritor...>
  local a="$1" d="$2" s="$3"; shift 3
  AI_OUT="$(cd "$d" && env -u EXPX_SESSAO -u EXPX_HARNESS CLAUDECODE=1 CLAUDE_CODE_SESSION_ID="$s" \
    bash "$a/.claude/skills/sprintx/scripts/rastro.sh" "$@" 2>&1)"; AI_RC=$?
}
ai_h() { # ai_h <arv> <dir> <sessao> <arquivo-relativo> — o escopo-da-task da arvore
  local a="$1" d="$2" s="$3" rel="$4"
  AI_OUT="$(printf '{"cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$d" "$d/$rel" \
    | (cd "$d" && env -u EXPX_SESSAO -u EXPX_HARNESS CLAUDECODE=1 CLAUDE_CODE_SESSION_ID="$s" \
        bash "$a/.claude/hooks/sprintx/escopo-da-task.sh") 2>&1)"; AI_RC=$?
}
ai_ok() { [ "$AI_RC" -eq 0 ] && [ -z "$AI_OUT" ]; }
ai_barra() { [ "$AI_RC" -eq 2 ] && printf '%s' "$AI_OUT" | grep -qF "$1"; }
ai_linha() { # ai_linha <arquivo> <evento> <task> — a ultima linha daquele evento, vazia se nao ha
  [ -f "$1" ] || return 0
  grep -F "\"evento\":\"$2\"" "$1" 2>/dev/null | grep -F "\"task\":\"$3\"" | tail -1
}
AI_LEGADO='{"ts":"2026-09-26T10:23:54Z","expx_eventos":1,"trabalho_id":"fx","ferramenta":"sprintx","origem":"skill","evento":"task_iniciada","fase":"f6","task":"T-01.01","agente":"principal","resultado":"ok","detalhe":"legado","arquivos":[]}'

# PR#14 — o escritor com OUTRO PATH, para separar "nao ha dona" de "nao deu para saber quem e".
ai_w_path() { # ai_w_path <PATH> <arv> <dir> <sessao> <args do escritor...>
  local p="$1" a="$2" d="$3" s="$4"; shift 4
  AI_OUT="$(cd "$d" && env -u EXPX_SESSAO -u EXPX_HARNESS CLAUDECODE=1 CLAUDE_CODE_SESSION_ID="$s" \
    PATH="$p" bash "$a/.claude/skills/sprintx/scripts/rastro.sh" "$@" 2>&1)"; AI_RC=$?
}
# PATH espelhado por link, com UM buraco: `awk`. Mesmo recurso do `aj_path_sem_jq` da secao AJ —
# sem ele o caso nao distingue "sem awk" de "sem nada no PATH". O espelho e por diretorio REAL
# (`pwd -P`), para `/bin` e `/usr/bin` nao pagarem dois espelhos iguais.
ai_path_sem_awk() {
  local d f real espelho novo="" IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    if [ -x "$d/awk" ]; then
      real="$(cd "$d" 2>/dev/null && pwd -P)" || real="$d"
      espelho="$AI_T/semawk$(printf '%s' "$real" | tr -c 'A-Za-z0-9' '-')"
      if [ ! -d "$espelho" ]; then
        mkdir -p "$espelho"
        for f in "$d"/*; do
          [ -e "$f" ] || continue
          [ "${f##*/}" = awk ] && continue
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
AI_SEMAWK="$(ai_path_sem_awk)"
# `awk` que EXISTE e falha: o erro de leitura/execucao, deterministico em qualquer plataforma
# (inclusive Git Bash, onde brincar com permissao de arquivo nao e confiavel). Nenhum chmod,
# nada para restaurar no cleanup alem do proprio $AI_T.
AI_AWKRUIM="$AI_T/awk-ruim"
mkdir -p "$AI_AWKRUIM"
printf '#!/usr/bin/env bash\nprintf "awk: nao consegui ler o rastro\\n" >&2\nexit 2\n' > "$AI_AWKRUIM/awk"
chmod +x "$AI_AWKRUIM/awk"
if ( PATH="$AI_SEMAWK"; hash -r; command -v awk >/dev/null 2>&1 ); then AI_SB=1
else ( PATH="$AI_SEMAWK"; hash -r; command -v grep >/dev/null 2>&1 \
         && command -v git >/dev/null 2>&1 && command -v bash >/dev/null 2>&1 ); AI_SB=$?
fi
afirma "ai0-sandbox-esconde-awk-e-serve-o-resto" "$AI_SB" "PATH sem awk, com grep, git e bash"
if ( PATH="$AI_AWKRUIM:$AI_SEMAWK"; hash -r; command -v awk >/dev/null 2>&1 ) \
   && ! ( PATH="$AI_AWKRUIM:$AI_SEMAWK" "$AI_AWKRUIM/awk" 'END{}' </dev/null >/dev/null 2>&1 ); then AI_SB=0
else AI_SB=1
fi
afirma "ai0b-sandbox-tem-awk-que-existe-e-falha" "$AI_SB" "stub de awk visivel no PATH e com saida 2"

# ---------------------------------------------------------------- os casos
ai_dono() { # A: outra sessao nao fecha nem relibera a reivindicacao; o dono fecha
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  # s2 tenta fechar a task de s1, pelos dois eventos de fechamento
  ai_w "$a" "$AI_FX" s2 task-concluida fx T-01.01 "fecho eu" src/a.ts; [ "$AI_RC" -eq 4 ] || return 1
  printf '%s' "$AI_OUT" | grep -qF 'claude-code@s1' || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ] || return 1
  ai_w "$a" "$AI_FX" s2 task-bloqueada fx T-01.01 B-01; [ "$AI_RC" -eq 4 ] || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_bloqueada T-01.01)" ] || return 1
  # a reivindicacao de s1 continua ATIVA, e a task continua dela: nao foi reliberada
  ai_h "$a" "$AI_FX" s1 src/a.ts; ai_ok || return 1
  ai_h "$a" "$AI_FX" s2 src/a.ts; ai_barra sessao_ambigua || return 1
  # e o DONO fecha normalmente (controle: o portao nao quebra o caminho de sempre)
  ai_w "$a" "$AI_FX" s1 task-concluida fx T-01.01 "suite parcial verde" src/a.ts; [ "$AI_RC" -eq 0 ] || return 1
  [ -n "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ] || return 1
  ai_h "$a" "$AI_FX" s1 src/a.ts; ai_barra sessao_ambigua
}
ai_dono_bloqueada() { # B: o dono tambem bloqueia; e depois de fechada qualquer sessao reivindica
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_w "$a" "$AI_FX" s1 task-bloqueada fx T-01.01 B-01; [ "$AI_RC" -eq 0 ] || return 1
  # sem dono aberto, a task volta a ser reivindicavel — inclusive por outra sessao
  ai_w "$a" "$AI_FX" s2 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_h "$a" "$AI_FX" s2 src/a.ts; ai_ok || return 1
  # e agora e s1 quem nao pode fechar
  ai_w "$a" "$AI_FX" s1 task-concluida fx T-01.01 ok src/a.ts; [ "$AI_RC" -eq 4 ] || return 1
  printf '%s' "$AI_OUT" | grep -qF 'claude-code@s2'
}
ai_legado() { # C: evento legado sem `sessao` nao reivindica (DS-150) e continua FECHAVEL
  local a="$1"; ai_fx; mkdir -p "$AI_FX/docs/eventos"
  printf '%s\n' "$AI_LEGADO" >> "$AI_FX/docs/eventos/fx.jsonl"
  # nao reivindica: a primeira edicao continua barrada, como sempre
  ai_h "$a" "$AI_FX" s1 src/a.ts; ai_barra sessao_ambigua || return 1
  # e, porque nao reivindica, nao ha dono para proteger: o fechamento compativel segue valendo
  ai_w "$a" "$AI_FX" s1 task-concluida fx T-01.01 "fechamento do legado"; [ "$AI_RC" -eq 0 ] || return 1
  [ -n "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ] || return 1
  # o caminho contratado para seguir: reivindicar pelo escritor e ai sim editar
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_h "$a" "$AI_FX" s1 src/a.ts; ai_ok
}
ai_rotacao() { # D: a reivindicacao no arquivo ROTACIONADO continua protegendo o dono
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  mv "$AI_FX/docs/eventos/fx.jsonl" "$AI_FX/docs/eventos/fx.1.jsonl" || return 1
  : > "$AI_FX/docs/eventos/fx.jsonl"
  ai_w "$a" "$AI_FX" s2 task-concluida fx T-01.01 ok src/a.ts; [ "$AI_RC" -eq 4 ] || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ]
}
ai_iniciada_fora_do_portao() { # F: o portao e sobre FECHAR; abrir continua territorio do hook
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  # Reivindicar por cima continua aceito pelo escritor: quem avisa/barra isso e o hook
  # `task-reivindicada`, em aviso ou bloqueio. Este caso fixa a fronteira — a correcao e sobre
  # FECHAR a task de outra sessao, nao sobre abrir.
  ai_w "$a" "$AI_FX" s2 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_h "$a" "$AI_FX" s2 src/a.ts; ai_ok
}
ai_outra_task() { # E: o portao e por (trabalho, task): a task irma de outra sessao nao e afetada
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_w "$a" "$AI_FX" s2 task-iniciada fx T-01.02; [ "$AI_RC" -eq 0 ] || return 1
  ai_w "$a" "$AI_FX" s2 task-concluida fx T-01.02 ok src/b.ts; [ "$AI_RC" -eq 0 ] || return 1
  ai_w "$a" "$AI_FX" s1 task-concluida fx T-01.01 ok src/a.ts; [ "$AI_RC" -eq 0 ] || return 1
  return 0
}
# PR#14 — dona INDETERMINADA nao e dona ausente.
#
# `rastro_dona_da_task_em` tinha UM resultado para dois fatos: "ninguem tem esta task" e "nao deu
# para saber quem tem". Sem `awk` no PATH, ou com erro de leitura em `docs/eventos/`, ela devolvia
# vazio com retorno 0 — e o portao do dono lia isso como task livre. Resultado: o fechamento de
# outra sessao passava justamente no ambiente em que a prova de ownership esta ilegivel, que e o
# pior momento possivel para presumir ausencia. Agora a ausencia CONCLUSIVA (sem pasta, sem
# arquivo do trabalho, ou nenhum evento daquela task nos arquivos lidos) continua vazia com
# retorno 0, e o inconclusivo sai por retorno NAO-ZERO; o escritor o traduz em codigo 5 de
# ambiente e nao grava o fechamento.
#
# `task-iniciada` fica fora: o portao e so dos dois fechamentos, e abrir task continua sem
# dependencia nova de `awk` — a varredura de contexto da biblioteca segue falhando aberta.
ai_sem_awk_outra_sessao() { # sem `awk`, a reivindicacao e ILEGIVEL, nao e inexistente
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_w_path "$AI_SEMAWK" "$a" "$AI_FX" s2 task-concluida fx T-01.01 "fecho eu" src/a.ts
  [ "$AI_RC" -eq 5 ] || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ] || return 1
  ai_w_path "$AI_SEMAWK" "$a" "$AI_FX" s2 task-bloqueada fx T-01.01 B-01
  [ "$AI_RC" -eq 5 ] || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_bloqueada T-01.01)" ] || return 1
  # com `awk` de volta, a reivindicacao de s1 esta intacta: o codigo 4 de sempre, e o dono fecha
  ai_w "$a" "$AI_FX" s2 task-concluida fx T-01.01 ok src/a.ts; [ "$AI_RC" -eq 4 ] || return 1
  ai_w "$a" "$AI_FX" s1 task-concluida fx T-01.01 ok src/a.ts; [ "$AI_RC" -eq 0 ]
}
ai_sem_awk_a_propria_dona() { # nem a dona fecha: o portao nao SABE que ela e a dona
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_w_path "$AI_SEMAWK" "$a" "$AI_FX" s1 task-concluida fx T-01.01 ok src/a.ts
  [ "$AI_RC" -eq 5 ] || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ] || return 1
  printf '%s' "$AI_OUT" | grep -qF 'prerequisito_ausente' || return 1
  # e nada foi reliberado: a task continua dela
  ai_h "$a" "$AI_FX" s1 src/a.ts; ai_ok || return 1
  ai_h "$a" "$AI_FX" s2 src/a.ts; ai_barra sessao_ambigua
}
ai_awk_com_erro() { # `awk` que existe e falha e inconclusivo, nos dois fechamentos
  local a="$1"; ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.01; [ "$AI_RC" -eq 0 ] || return 1
  ai_w_path "$AI_AWKRUIM:$PATH" "$a" "$AI_FX" s2 task-concluida fx T-01.01 ok src/a.ts
  [ "$AI_RC" -eq 5 ] || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ] || return 1
  ai_w_path "$AI_AWKRUIM:$PATH" "$a" "$AI_FX" s1 task-bloqueada fx T-01.01 B-01
  [ "$AI_RC" -eq 5 ] || return 1
  [ -z "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_bloqueada T-01.01)" ]
}
ai_ausencia_conclusiva() { # ausencia REAL continua conclusiva e nao vira erro
  local a="$1"; ai_fx
  # (i) Sem pasta docs/eventos nenhuma: conclusivo ANTES de precisar de `awk`. Este trecho e
  # tambem o controle do sandbox — se o PATH espelhado quebrasse o escritor, aqui nao sairia 0.
  [ ! -e "$AI_FX/docs/eventos" ] || return 1
  ai_w_path "$AI_SEMAWK" "$a" "$AI_FX" s1 task-concluida fx T-01.01 "sem dona" src/a.ts
  [ "$AI_RC" -eq 0 ] || return 1
  [ -n "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_concluida T-01.01)" ] || return 1
  # (ii) Pasta existente e nenhum arquivo DAQUELE trabalho: tambem conclusivo antes do `awk`.
  ai_fx; mkdir -p "$AI_FX/docs/eventos" || return 1
  ai_w_path "$AI_SEMAWK" "$a" "$AI_FX" s1 task-bloqueada fx T-01.01 B-01
  [ "$AI_RC" -eq 0 ] || return 1
  [ -n "$(ai_linha "$AI_FX/docs/eventos/fx.jsonl" task_bloqueada T-01.01)" ] || return 1
  # (iii) Arquivo do trabalho ja existe, mas nenhum evento da T-01.02: conclusivo pelo `awk`.
  ai_w "$a" "$AI_FX" s1 task-concluida fx T-01.02 ok src/b.ts; [ "$AI_RC" -eq 0 ] || return 1
  # (iv) Mas arquivo candidato COM `awk` ausente nao e ausencia: e inconclusivo, mesmo que a
  # task pedida nao tenha dono nenhum ali dentro.
  ai_fx
  ai_w "$a" "$AI_FX" s1 task-iniciada fx T-01.02; [ "$AI_RC" -eq 0 ] || return 1
  ai_w_path "$AI_SEMAWK" "$a" "$AI_FX" s1 task-concluida fx T-01.01 ok src/a.ts
  [ "$AI_RC" -eq 5 ]
}
# O contrato publico: a tabela de respostas de 08-rastro.md e o passo 1 da 06-execucao.md.
AI_LIT_C5='nos três `task_*`, **falha fechado como o código `3`**'
AI_LIT_C5_PORQUE='sem `task_iniciada` não há reivindicação, e o `escopo-da-task` barra a primeira edição da task'
AI_LIT_C5_INFO='Nos demais eventos (`fase-*`, `veredito-emitido`), que nenhum hook lê, siga sem o evento'
AI_LIT_C4='a task está reivindicada por outra sessão'
AI_LIT_EXEC='nada foi gravado e a task **não** está reivindicada'
AI_LIT_DONO='Fechar a task é do dono da reivindicação'
# A contradicao exata que havia: a linha do codigo 5 mandando seguir, sem distinguir os task_*.
AI_LIT_PROIBE_C5_ANTIGO='!ou a escrita falhou — **nada foi gravado** | siga sem o evento; não grave à mão'
# PR#14 — o codigo 5 passa a nomear a terceira causa, e o limite arquitetural fica escrito.
AI_LIT_C5_LEITURA='a **reivindicação não pôde ser lida**'
AI_LIT_INDET='Dona indeterminada não é dona ausente'
AI_LIT_TOCTOU='check-then-append'
ai_doc() { # F: o contrato diz o fail-closed, e a contradicao antiga nao sobrevive
  local d="$1/.claude/skills/sprintx"
  ad_lit "$d/references/08-rastro.md" "$AI_LIT_C5" \
         "$d/references/08-rastro.md" "$AI_LIT_C5_PORQUE" \
         "$d/references/08-rastro.md" "$AI_LIT_C5_INFO" \
         "$d/references/08-rastro.md" "$AI_LIT_C4" \
         "$d/references/08-rastro.md" "$AI_LIT_DONO" \
         "$d/references/08-rastro.md" "$AI_LIT_PROIBE_C5_ANTIGO" \
         "$d/references/06-execucao.md" "$AI_LIT_EXEC"
}
ai_doc_inconclusivo() { # H: o codigo 5 nomeia a reivindicacao ilegivel, e o limite esta escrito
  local d="$1/.claude/skills/sprintx"
  ad_lit "$d/references/08-rastro.md" "$AI_LIT_C5_LEITURA" \
         "$d/references/08-rastro.md" "$AI_LIT_INDET" \
         "$d/references/08-rastro.md" "$AI_LIT_TOCTOU"
}
ai_ds174() { # I: DS-174 registrada, append-only, e a DS-171 anterior intacta
  local v d="$1/.claude/skills/sprintx"
  v="$(grep -F '| DS-174 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
  [ -n "$v" ] || return 1
  printf '%s' "$v" | grep -qiF 'indeterminada' || return 1
  printf '%s' "$v" | grep -qiF 'check-then-append' || return 1
  printf '%s' "$v" | grep -qiF 'task-iniciada' || return 1
  grep -qF '| DS-171 |' "$d/DECISOES-DA-SKILL.md"
}
ai_ds() { # G: DS-171 registrada, append-only, e a DS-159 anterior intacta
  local v d="$1/.claude/skills/sprintx"
  v="$(grep -F '| DS-171 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
  [ -n "$v" ] || return 1
  printf '%s' "$v" | grep -qiF 'reivindica' || return 1
  printf '%s' "$v" | grep -qiF 'fecha' || return 1
  grep -qF '| DS-159 |' "$d/DECISOES-DA-SKILL.md"
}

AI_CASOS="ai_dono ai_dono_bloqueada ai_legado ai_rotacao ai_iniciada_fora_do_portao
ai_outra_task ai_doc ai_ds ai_sem_awk_outra_sessao ai_sem_awk_a_propria_dona ai_awk_com_erro
ai_ausencia_conclusiva ai_doc_inconclusivo ai_ds174"
ai_nome() {
  case "$1" in
    ai_dono)           echo "ai1-outra-sessao-nao-fecha-nem-relibera" ;;
    ai_dono_bloqueada) echo "ai2-dono-bloqueia-e-a-task-volta-a-ser-reivindicavel" ;;
    ai_legado)         echo "ai3-legado-sem-sessao-nao-reivindica-e-continua-fechavel" ;;
    ai_rotacao)        echo "ai4-reivindicacao-no-rotacionado-protege-o-dono" ;;
    ai_iniciada_fora_do_portao) echo "ai5-portao-e-sobre-fechar-nao-sobre-abrir" ;;
    ai_outra_task)     echo "ai6-portao-e-por-trabalho-e-task-nao-por-sessao-global" ;;
    ai_doc)            echo "ai7-contrato-do-codigo-5-falha-fechado-sem-contradicao" ;;
    ai_ds)             echo "ai8-ds171-registrada-append-only" ;;
    ai_sem_awk_outra_sessao)   echo "ai9-sem-awk-outra-sessao-nao-fecha-nem-grava" ;;
    ai_sem_awk_a_propria_dona) echo "ai10-sem-awk-nem-a-dona-fecha-e-nada-e-gravado" ;;
    ai_awk_com_erro)   echo "ai11-erro-do-awk-e-inconclusivo-nao-e-ausencia" ;;
    ai_ausencia_conclusiva)    echo "ai12-ausencia-real-continua-conclusiva-e-da-zero" ;;
    ai_doc_inconclusivo)       echo "ai13-codigo-5-nomeia-reivindicacao-ilegivel" ;;
    ai_ds174)          echo "ai14-ds174-registrada-append-only" ;;
  esac
}
AI_REAL="$(cd "$H/../.." && pwd)"
for ai_c in $AI_CASOS; do
  ai_nm="$(ai_nome "$ai_c")"; "$ai_c" "$AI_REAL" >/dev/null 2>&1; ai_rc=$?
  afirma "$ai_nm" "$ai_rc" "arvore do repositorio"
done

# ---------------------------------------------------------------- mutantes
# Copia do layout instalado; o controle e a copia sem mutacao. Cada mutante tem de morrer pelos
# casos que o nomeiam — nao vale morrer de carona.
ai_mutante() { # ai_mutante <nome> <rc da geracao> <arvore> <casos que TEM de matar>
  local nome="$1" rc="$2" r="$3" c vivos=""
  if [ "$rc" -eq 0 ]; then for c in $4; do "$c" "$r" >/dev/null 2>&1 && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]; afirma "$nome" $? "morto por: $4 ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
AI_CTL="$(ai_arvore controle)"; AI_VIVO=""
for ai_c in $AI_CASOS; do "$ai_c" "$AI_CTL" >/dev/null 2>&1 || AI_VIVO="$AI_VIVO $ai_c"; done
[ -z "$AI_VIVO" ]; afirma "aim-controle-copia-intacta-sobrevive" $? "${AI_VIVO:+reprovada por:$AI_VIVO}"
AI_W=".claude/skills/sprintx/scripts/rastro.sh"
AI_L=".claude/hooks/comum/rastro.sh"
AI_R=".claude/skills/sprintx/references"
ai_m() { # ai_m <nome> <arquivo-relativo> <trecho> <troca> — arvore nova com UMA troca literal
  local r; r="$(ai_arvore "$1")"
  muta_lit "$r/$2" "$r/$2.m" "$3" "$4" && mv "$r/$2.m" "$r/$2" && printf '%s' "$r"
}
# m1 — o portao do dono desaparece: qualquer sessao volta a fechar a task de qualquer outra.
AIM="$(ai_m m1 "$AI_W" 'if [ -n "$DONA" ] && [ "$DONA" != "${SESSAO:-}" ]; then' 'if false; then')"
ai_mutante "aim-mutante-1-sem-portao-do-dono" $? "$AIM" "ai_dono ai_dono_bloqueada ai_rotacao"
# m2 — o portao passa a valer para task-iniciada tambem: reivindicar depois de fechada reprova,
#      e o legado deixa de ser fechavel pelo caminho compativel.
AIM="$(ai_m m2 "$AI_W" '  task-concluida|task-bloqueada)' '  task-concluida|task-bloqueada|task-iniciada)')"
ai_mutante "aim-mutante-2-portao-alcanca-task-iniciada" $? "$AIM" "ai_iniciada_fora_do_portao"
# m3 — o dono sai de um arquivo so, sem o rotacionado: a reivindicacao rotacionada fica invisivel.
AIM="$(ai_m m3 "$AI_L" 'for _f in "$_dir/$_t".jsonl "$_dir/$_t".[0-9]*.jsonl; do' 'for _f in "$_dir/$_t".jsonl; do')"
ai_mutante "aim-mutante-3-dono-ignora-arquivo-rotacionado" $? "$AIM" "ai_rotacao"
# m4 — o portao compara com a sessao errada (a do evento, nao a desta): o dono nao se reconhece.
AIM="$(ai_m m4 "$AI_W" '[ "$DONA" != "${SESSAO:-}" ]' '[ "$DONA" = "${SESSAO:-}" ]')"
ai_mutante "aim-mutante-4-portao-compara-invertido" $? "$AIM" "ai_dono ai_dono_bloqueada"
# m5 — a tabela de respostas volta a mandar seguir sem o evento no codigo 5.
AIM="$(ai_m m5 "$AI_R/08-rastro.md" "$AI_LIT_C5" 'siga sem o evento')"
ai_mutante "aim-mutante-5-codigo-5-volta-a-mandar-seguir" $? "$AIM" "ai_doc"
# m6 — a 06-execucao.md perde a frase que diz que a task NAO esta reivindicada.
AIM="$(ai_m m6 "$AI_R/06-execucao.md" "$AI_LIT_EXEC" 'nada foi gravado')"
ai_mutante "aim-mutante-6-execucao-sem-o-aviso-de-nao-reivindicada" $? "$AIM" "ai_doc"
# m7 — DS-171 apagada do registro.
AIM="$(ai_arvore m7)" && muta_lit "$AIM/.claude/skills/sprintx/DECISOES-DA-SKILL.md" "$AIM/ds.m" '| DS-171 |' '| DS-171-apagada |' \
  && mv "$AIM/ds.m" "$AIM/.claude/skills/sprintx/DECISOES-DA-SKILL.md"
ai_mutante "aim-mutante-7-ds171-apagada" $? "$AIM" "ai_ds"
# m8 — PR#14: o retorno inconclusivo da leitura da dona volta a ser 0. A funcao continua devolvendo
#      a variavel vazia; o que morre e a distincao entre "nao tem dona" e "nao deu para saber".
AIM="$(ai_m m8 "$AI_L" '  [ "$_rc" -eq 0 ] || return "$_rc"' '  [ "$_rc" -eq 0 ] || return 0')"
ai_mutante "aim-mutante-8-inconclusivo-vira-ausencia" $? "$AIM" \
  "ai_sem_awk_outra_sessao ai_sem_awk_a_propria_dona ai_awk_com_erro"
# m9 — o escritor volta a ignorar o retorno da leitura e compara DONA mesmo sem ter lido nada.
AIM="$(ai_m m9 "$AI_W" '    if ! rastro_dona_da_task_em DONA "$RAIZ" "$SLUG" "$ALVO"; then' \
  '    rastro_dona_da_task_em DONA "$RAIZ" "$SLUG" "$ALVO" || true; if false; then')"
ai_mutante "aim-mutante-9-escritor-ignora-leitura-inconclusiva" $? "$AIM" \
  "ai_sem_awk_outra_sessao ai_sem_awk_a_propria_dona ai_awk_com_erro"
# m10 — a ausencia CONCLUSIVA por falta de arquivo do trabalho passa a ser erro: fechar task que
#       nunca foi aberta, com a pasta de eventos ja existindo, deixa de valer.
AIM="$(ai_m m10 "$AI_L" '  [ "${#_arqs[@]}" -gt 0 ] || return 0' '  [ "${#_arqs[@]}" -gt 0 ] || return 3')"
ai_mutante "aim-mutante-10-sem-arquivo-do-trabalho-vira-erro" $? "$AIM" "ai_ausencia_conclusiva"
# m13 — e a ausencia CONCLUSIVA por falta da propria pasta docs/eventos tambem.
AIM="$(ai_m m13 "$AI_L" '  [ -d "$_dir" ] || return 0' '  [ -d "$_dir" ] || return 3')"
ai_mutante "aim-mutante-13-pasta-de-eventos-ausente-vira-erro" $? "$AIM" "ai_ausencia_conclusiva"
# m11 — a tabela do codigo 5 perde a reivindicacao ilegivel e volta a listar duas causas so.
AIM="$(ai_m m11 "$AI_R/08-rastro.md" "$AI_LIT_C5_LEITURA" 'a escrita falhou')"
ai_mutante "aim-mutante-11-codigo-5-sem-a-reivindicacao-ilegivel" $? "$AIM" "ai_doc_inconclusivo"
# m12 — DS-174 apagada do registro.
AIM="$(ai_arvore m12)" && muta_lit "$AIM/.claude/skills/sprintx/DECISOES-DA-SKILL.md" "$AIM/ds.m" '| DS-174 |' '| DS-174-apagada |' \
  && mv "$AIM/ds.m" "$AIM/.claude/skills/sprintx/DECISOES-DA-SKILL.md"
ai_mutante "aim-mutante-12-ds174-apagada" $? "$AIM" "ai_ds174"

rm -rf "$AI_T"

echo "== AJ. deteccao da saida da suite e certificacao da ORDEM real (PR#12) =="
# Tres defeitos na forma como a maquina LE o que o agente fez:
#
#   1. CLASSIFICACAO DA SUITE. `rastro-post` decidia `falha` por fronteira de espaco em branco
#      ao redor de `[ERROR]` e `BUILD FAILURE`. Maven e Surefire saem COLORIDOS: a sequencia
#      ANSI cola um `m` antes do token e outro depois, nenhuma fronteira de espaco existe, e
#      uma suite vermelha era gravada como `ok` — o painel passava a mostrar verde onde o
#      build quebrou. Agora a saida tem as sequencias ANSI removidas ANTES de classificar, e
#      so quando ha ESC no texto (o caminho de sempre nao paga processo nenhum).
#   2. FORMA DO `tool_response`. O hook lia `tool_response` como string. No Bash, o Claude Code
#      entrega um OBJETO (`{"stdout":...,"stderr":...}`): com jq, `.tool_response` de um objeto
#      vira o JSON impresso, onde as quebras aparecem ESCAPADAS e o token perde a fronteira de
#      espaco; sem jq, a leitura de string nao casa objeto nenhum e a saida vinha VAZIA — nenhuma
#      suite era classificada como falha nessa rota. Agora o texto sai das strings de dentro da
#      resposta, qualquer que seja a forma, nas duas rotas.
#   3. ORDEM NO RASTRO. A certificacao do agente real exigia "uma edicao da task depois do
#      claim" — mas marcava a primeira edicao so a partir do instante em que o claim aparecia.
#      Com a PRIMEIRA edicao ANTES da reivindicacao (o defeito que a prova existe para pegar) e
#      uma segunda edicao legitima depois, a prova passava. Agora a primeira edicao e marcada
#      sempre, e a prova exige que ELA venha depois do claim.
#
# E a auditoria de transcrito reprovava escrita manual em docs/eventos so por redirecao, `tee` e
# `sed -i`. `cp`, `mv` e um interpretador com `open(..., 'a')` escrevem o mesmo arquivo e
# passavam — inclusive num transcrito que TAMBEM chama o escritor oficial, que era a forma mais
# facil de parecer conforme. A regra nova olha o PAPEL do caminho, nao a mencao: copiar ou mover
# PARA docs/eventos viola; `cat`, `grep`, `jq`, `tail`, `wc`, `print(open(...).read())` e copiar
# o rastro PARA FORA continuam sendo leitura, que o contrato permite.
AJ_T="$(mktemp -d)"
AJ_H="$(cd "$H" && pwd)"
AJ_JSONL="$AJ_T/repo/docs/eventos/sem-trabalho.jsonl"

aj_path_sem_jq() {
  local d f espelho novo="" i=0 IFS=:
  for d in $PATH; do
    [ -n "$d" ] || continue
    if [ -x "$d/jq" ]; then
      i=$((i+1)); espelho="$AJ_T/bin$i"
      if [ ! -d "$espelho" ]; then
        mkdir -p "$espelho"
        for f in "$d"/*; do
          [ -e "$f" ] || continue
          [ "${f##*/}" = jq ] && continue
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
AJ_SEMJQ="$(aj_path_sem_jq)"
if PATH="$AJ_SEMJQ" command -v jq >/dev/null 2>&1; then AJ_RC=1
else PATH="$AJ_SEMJQ" command -v grep >/dev/null 2>&1; AJ_RC=$?
fi
afirma "aj0-sandbox-esconde-jq-e-serve-o-resto" "$AJ_RC" "PATH do caso sem jq, com grep"

# ------------------------------------------------- 1 e 2. classificacao da saida da suite
cat > "$AJ_T/payload.py" <<'PY'
import json, sys
forma, arq_saida, cwd = sys.argv[1], sys.argv[2], sys.argv[3]
texto = open(arq_saida, encoding='utf-8').read()
if forma == 'string':
    resp = texto
elif forma == 'objeto':
    resp = {'stdout': texto, 'stderr': '', 'interrupted': False, 'isImage': False}
else:
    resp = {'stdout': '', 'stderr': texto, 'interrupted': False, 'isImage': False}
print(json.dumps({'cwd': cwd, 'tool_name': 'Bash',
                  'tool_input': {'command': 'mvn test'}, 'tool_response': resp}))
PY
aj_roda() { # aj_roda <forma> <texto da saida> <PATH do caso>
  rm -rf "$AJ_T/repo"; mkdir -p "$AJ_T/repo/.git" "$AJ_T/repo/docs/eventos"
  printf '%s' "$2" > "$AJ_T/saida.txt"
  python3 "$AJ_T/payload.py" "$1" "$AJ_T/saida.txt" "$AJ_T/repo" > "$AJ_T/payload.json"
  (cd "$AJ_T/repo" && PATH="$3" bash "$AJ_H/comum/rastro-post.sh") < "$AJ_T/payload.json" >/dev/null 2>&1
}
aj_resultado() { # ecoa o `resultado` gravado, ou um diagnostico
  [ -s "$AJ_JSONL" ] || { printf 'sem-linha'; return 0; }
  python3 -c 'import json,sys; print(json.loads(open(sys.argv[1],encoding="utf-8").readline())["resultado"])' \
    "$AJ_JSONL" 2>/dev/null || printf 'ilegivel'
}
aj_caso() { # aj_caso <nome> <esperado> <texto> — as 3 formas x as 2 rotas
  local nome="$1" esp="$2" texto="$3" forma rota caminho real ruim=""
  for rota in com-jq sem-jq; do
    caminho="$PATH"; [ "$rota" = sem-jq ] && caminho="$AJ_SEMJQ"
    for forma in string objeto objeto-stderr; do
      aj_roda "$forma" "$texto" "$caminho"
      real="$(aj_resultado)"
      [ "$real" = "$esp" ] || ruim="$ruim $rota/$forma=$real"
    done
  done
  [ -z "$ruim" ]
  afirma "$nome" $? "esperado=$esp${ruim:+ — FORA DO ESPERADO:$ruim}"
}
# Maven/Surefire colorido: a sequencia ANSI cola um `m` antes do token e outro depois.
printf -v AJ_ERR_ANSI '\033[1;31m[ERROR]\033[0m Failed to execute goal on project app'
printf -v AJ_BF_ANSI  '\033[1m[INFO] \033[1;31mBUILD FAILURE\033[0m\n\033[1m[INFO] \033[0mTotal time: 3.1 s'
printf -v AJ_VERDE    '[INFO] Tests run: 12, Failures: 0, Errors: 0, Skipped: 0\n[INFO] BUILD SUCCESS'
printf -v AJ_VERDE_ANSI '\033[1;32m[INFO]\033[0m Tests run: 12, Failures: 0, Errors: 0\n\033[1;32m[INFO] BUILD SUCCESS\033[0m'
AJ_ERR_CRU='[ERROR] Failed to execute goal on project app'
aj_caso "aj1-error-com-ansi-ao-redor-e-falha"      falha "$AJ_ERR_ANSI"
aj_caso "aj2-build-failure-com-ansi-ao-redor-e-falha" falha "$AJ_BF_ANSI"
aj_caso "aj3-error-cru-nao-regride"                falha "$AJ_ERR_CRU"
aj_caso "aj4-surefire-com-falhas-contadas-e-falha" falha '[INFO] Tests run: 12, Failures: 3, Errors: 0
Results: 3 failed, 9 passed'
# Controles: verde e verde colorido NAO viram falha — a remocao de ANSI nao inventa defeito.
aj_caso "aj5-verde-continua-ok"                    ok "$AJ_VERDE"
aj_caso "aj6-verde-colorido-continua-ok"           ok "$AJ_VERDE_ANSI"

# ------------------------------------------------- 3. auditoria de transcrito: escrita x leitura
AJ_TR_OK=1
if ! command -v jq >/dev/null 2>&1; then
  pula_externo "aj-auditoria-de-transcrito" "jq"; AJ_TR_OK=0
fi
aj_ev() { # aj_ev <ferramenta> <input-json> — uma linha stream-json com um tool_use
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t","name":"%s","input":%s}]}}\n' "$1" "$2"
}
# O transcrito CONFORME: so o escritor oficial abre e fecha, e o agente LE o rastro para conferir.
aj_bom() {
  aj_ev Bash '{"command":"bash .claude/skills/sprintx/scripts/rastro.sh task-iniciada fx T-01.01"}'
  aj_ev Edit '{"file_path":"/p/src/a.ts","old_string":"a","new_string":"b"}'
  aj_ev Bash '{"command":"bash .claude/skills/sprintx/scripts/rastro.sh task-concluida fx T-01.01 ok src/a.ts"}'
}
aj_verifica() { # aj_verifica <arquivo de transcrito> — ecoa as violacoes (vazio = aprovado)
  ( . "$AJ_H/testes/transcrito-agente.sh"; transcrito_verifica "$1" 1111-2222 fx T-01.01 || : )
}
# Cada comando abaixo e acrescentado a um transcrito que TAMBEM chama o escritor oficial: e essa
# a forma de burlar que a regra antiga nao pegava.
aj_tr_viola() { # aj_tr_viola <nome> <comando> <detalhe>
  local nome="$1" cmd="$2" det="$3" v
  [ "$AJ_TR_OK" = 1 ] || return 0
  { aj_bom; aj_ev Bash "$(python3 -c 'import json,sys; print(json.dumps({"command":sys.argv[1]}))' "$cmd")"; } > "$AJ_T/tr"
  v="$(aj_verifica "$AJ_T/tr")"
  printf '%s' "$v" | grep -q '^rastro_manual:'
  afirma "$nome" $? "${det}${v:+ — violacoes=[$(printf '%s' "$v" | tr '\n' ' ' | cut -c1-90)]}"
}
aj_tr_viola "aj7-cp-para-docs-eventos-e-escrita-manual" \
  'cp /tmp/forjado.jsonl docs/eventos/fx.jsonl' "cp com docs/eventos como DESTINO"
aj_tr_viola "aj8-mv-para-docs-eventos-e-escrita-manual" \
  'mv /tmp/forjado.jsonl docs/eventos/fx.jsonl' "mv com docs/eventos como DESTINO"
aj_tr_viola "aj9-python-append-e-escrita-manual" \
  "python3 -c \"open('docs/eventos/fx.jsonl','a').write('{}')\"" "open em modo de escrita"
aj_tr_viola "aj10-python-dump-e-escrita-manual" \
  "python3 - <<'P'
import json; json.dump({}, open('docs/eventos/fx.jsonl','w'))
P" "json.dump no rastro"
aj_tr_viola "aj11-tee-sem-redirecao-tambem" \
  'printf "{}" | tee docs/eventos/fx.jsonl' "tee com o rastro como destino"
# E a LEITURA continua permitida: nenhuma destas pode virar violacao.
aj_tr_le() { # aj_tr_le <nome> <comando> <detalhe>
  local nome="$1" cmd="$2" det="$3" v
  [ "$AJ_TR_OK" = 1 ] || return 0
  { aj_bom; aj_ev Bash "$(python3 -c 'import json,sys; print(json.dumps({"command":sys.argv[1]}))' "$cmd")"; } > "$AJ_T/tr"
  v="$(aj_verifica "$AJ_T/tr")"
  [ -z "$v" ]
  afirma "$nome" $? "${det}${v:+ — REPROVOU leitura: [$(printf '%s' "$v" | tr '\n' ' ' | cut -c1-90)]}"
}
aj_tr_le "aj12-cat-do-rastro-e-leitura"  'cat docs/eventos/fx.jsonl' "cat"
aj_tr_le "aj13-grep-e-tail-sao-leitura"  'grep -c task_iniciada docs/eventos/fx.jsonl | tail -1' "grep + tail"
aj_tr_le "aj14-jq-e-wc-sao-leitura"      'jq -r .evento docs/eventos/fx.jsonl 2>/dev/null | wc -l' "jq + wc"
aj_tr_le "aj15-python-read-e-leitura"    "python3 -c \"print(open('docs/eventos/fx.jsonl').read())\"" "print(open(...).read())"
aj_tr_le "aj16-copiar-o-rastro-para-fora-e-leitura" 'cp docs/eventos/fx.jsonl /tmp/copia.jsonl' "cp com docs/eventos como ORIGEM"
# PR#12 (achado A): a decisao de destino de `cp`/`mv` olhava SO o ultimo token do segmento. Com
# `2>/dev/null` ou `>/dev/null` no fim, o ultimo token era o REDIRECIONAMENTO e o destino real
# ficava invisivel; e `cp -t docs/eventos/ origem` nomeia o destino na OPCAO, nunca no fim.
aj_tr_viola "aj23-cp-com-stderr-redirecionado-ainda-e-escrita" \
  'cp /tmp/forjado.jsonl docs/eventos/fx.jsonl 2>/dev/null' "2>/dev/null nao e o destino"
aj_tr_viola "aj24-cp-com-stdout-redirecionado-ainda-e-escrita" \
  'cp -v /tmp/f.jsonl docs/eventos/fx.jsonl >/dev/null' ">/dev/null nao e o destino"
aj_tr_viola "aj25-cp-com-target-directory-e-escrita" \
  'cp -t docs/eventos/ /tmp/f.jsonl' "-t nomeia o destino"
aj_tr_viola "aj26-dd-escrevendo-no-rastro-e-escrita" \
  'dd if=/tmp/f.jsonl of=docs/eventos/fx.jsonl' "dd com o rastro em of="
# E as leituras seguem permitidas: redirecionar stderr nao transforma origem em destino, e `dd`
# nomeia os dois lados — `if=` e ORIGEM.
aj_tr_le "aj27-copiar-para-fora-com-redirecao-e-leitura" \
  'cp docs/eventos/fx.jsonl /tmp/copia.jsonl 2>/dev/null' "cp com docs/eventos como ORIGEM"
aj_tr_le "aj28-dd-lendo-o-rastro-e-leitura" \
  'dd if=docs/eventos/fx.jsonl of=/tmp/copia.jsonl' "dd com docs/eventos em if="
# PR#12 (achado B): o estado "um interpretador apareceu" era PEGAJOSO entre segmentos. Depois de
# `python3 -c "..."`, o segmento seguinte herdava o estado de escrita, e `grep -c write` reprovava
# porque a palavra `write` estava ali como PADRAO do grep, nao como primitiva de escrita.
AJ_CMD_LE_B="python3 -c \"import json; print(json.load(open('/tmp/a.json')))\" ; grep -c write docs/eventos/fx.jsonl"
aj_tr_le "aj29-leitura-depois-de-interpretador-nao-herda-escrita" "$AJ_CMD_LE_B" \
  "o segmento que toca o rastro e leitura"
# E o que a herencia entre segmentos existe para pegar continua pego: heredoc de um interpretador
# que REALMENTE escreve no rastro, com a primitiva de escrita numa linha depois da chamada.
aj_tr_viola "aj30-heredoc-de-interpretador-que-escreve-continua-violando" \
  "python3 - <<'P'
import json
d = {}
json.dump(d, open('docs/eventos/fx.jsonl','w'))
P" "interpretador multissegmento que escreve"
# PR#14 (achado 2): o destino de `-t`/`--target-directory` pode vir ANEXADO a opcao. A regra olhava
# so a forma canonica (`-t dir`, `--target-directory=dir`), entao bastava colar o destino na opcao
# (`cp -tdocs/eventos/ origem`) ou abreviar a opcao longa, como o getopt do GNU aceita, para a
# escrita no rastro ficar invisivel.
aj_tr_viola "aj31-cp-com-destino-anexado-em-bloco-curto-e-escrita" \
  'cp -atdocs/eventos/ /tmp/f.jsonl' "-at com o destino colado na opcao"
aj_tr_viola "aj32-cp-com-destino-anexado-a-t-e-escrita" \
  'cp -tdocs/eventos/ /tmp/f.jsonl' "-t com o destino colado"
aj_tr_viola "aj33-mv-com-destino-anexado-a-t-e-escrita" \
  'mv -tdocs/eventos/ /tmp/f.jsonl' "mv -t colado"
aj_tr_viola "aj34-install-com-destino-anexado-em-bloco-curto-e-escrita" \
  'install -Dtdocs/eventos/ /tmp/f.jsonl' "install -Dt colado"
aj_tr_viola "aj35-cp-com-opcao-longa-abreviada-e-escrita" \
  'cp --targ=docs/eventos/ /tmp/f.jsonl' "--targ e abreviacao de --target-directory"
aj_tr_viola "aj36-cp-com-opcao-longa-quase-inteira-e-escrita" \
  'cp --target-director=docs/eventos/ /tmp/f.jsonl' "--target-director tambem e prefixo valido"
aj_tr_viola "aj37-cp-com-opcao-longa-inteira-nao-regride" \
  'cp --target-directory=docs/eventos/ /tmp/f.jsonl' "a forma canonica continua pega"
# `rsync -t` e preservar TEMPO, nao destino: ali o destino continua POSICIONAL, nas duas direcoes.
aj_tr_viola "aj38-rsync-t-tem-destino-posicional-e-escreve" \
  'rsync -t /tmp/f.jsonl docs/eventos/fx.jsonl' "-t do rsync e tempo; o destino e o 2o operando"
aj_tr_le "aj39-rsync-t-lendo-o-rastro-e-leitura" \
  'rsync -t docs/eventos/fx.jsonl /tmp/copia.jsonl' "-t do rsync nao transforma origem em destino"
# E o destino na opcao, anexado ou nao, apontando PARA FORA continua sendo leitura do rastro.
aj_tr_le "aj40-destino-anexado-fora-do-rastro-e-leitura" \
  'cp -t/tmp/ docs/eventos/fx.jsonl' "-t/tmp/ com o rastro como ORIGEM"
aj_tr_le "aj41-destino-separado-fora-do-rastro-e-leitura" \
  'cp -at /tmp/ docs/eventos/fx.jsonl' "-at /tmp/ com o rastro como ORIGEM"
aj_tr_le "aj42-no-target-directory-nao-e-abreviacao-de-target-directory" \
  'cp --no-target-directory docs/eventos/fx.jsonl /tmp/copia.jsonl' "--no-... nao e prefixo de --target-directory"

# PR#14 (achado 3): wrappers TRANSPARENTES. `env cp ...` escreve o mesmo arquivo que `cp ...`, mas a
# regra julgava o `env` como se fosse o comando — nome fora de toda lista, segmento ignorado,
# escrita invisivel. Agora o classificador atravessa o wrapper, e as opcoes dele, ate o comando real.
aj_tr_viola "aj43-env-com-interpretador-que-escreve-e-escrita" \
  "env python3 -c \"open('docs/eventos/fx.jsonl','a').write('{}')\"" "env nao esconde o python3"
aj_tr_viola "aj44-env-com-cp-para-o-rastro-e-escrita" \
  'env cp /tmp/f.jsonl docs/eventos/fx.jsonl' "env nao esconde o cp"
aj_tr_viola "aj45-timeout-com-duracao-posicional-e-escrita" \
  'timeout 5 cp /tmp/f.jsonl docs/eventos/fx.jsonl' "a duracao 5 nao e o comando real"
aj_tr_viola "aj46-sudo-com-u-e-usuario-e-escrita" \
  'sudo -u deploy cp /tmp/f.jsonl docs/eventos/fx.jsonl' "-u consome o usuario; o comando real e o cp"
aj_tr_viola "aj47-xargs-com-i-e-marcador-e-escrita" \
  'xargs -I F cp F docs/eventos/fx.jsonl' "-I consome o marcador F"
aj_tr_viola "aj48-env-com-atribuicao-de-variavel-e-escrita" \
  'env LC_ALL=C cp /tmp/f.jsonl docs/eventos/fx.jsonl' "VAR=valor depois do env nao e o comando"
aj_tr_viola "aj49-env-por-caminho-absoluto-e-escrita" \
  '/usr/bin/env cp /tmp/f.jsonl docs/eventos/fx.jsonl' "/usr/bin/env e o mesmo wrapper"
aj_tr_viola "aj50-wrapper-com-destino-anexado-e-escrita" \
  'env cp -tdocs/eventos/ /tmp/f.jsonl' "os dois achados juntos: wrapper + destino anexado"
# Cada wrapper da lista, um por um: atras de todos o comando real e o mesmo `cp` que a regra
# reprova sem wrapper nenhum.
aj_tr_viola "aj51-wrapper-command-e-atravessado" \
  'command cp /tmp/f.jsonl docs/eventos/fx.jsonl' "command"
aj_tr_viola "aj52-wrapper-exec-e-atravessado" \
  'exec cp /tmp/f.jsonl docs/eventos/fx.jsonl' "exec"
# `builtin` so executa builtin do shell: `builtin cp` falha (rc=1) e nao grava nada. O que escreve
# atras dele e um builtin que executa outro comando, como `command`. O aj53b roda o mesmo comando
# num diretorio descartavel e prova que ele grava mesmo.
AJ53_CMD='builtin command cp f.jsonl docs/eventos/fx.jsonl'
aj_tr_viola "aj53-wrapper-builtin-e-atravessado" "$AJ53_CMD" "builtin command"
mkdir -p "$AJ_T/aj53/docs/eventos" && printf '{}\n' > "$AJ_T/aj53/f.jsonl"
(cd "$AJ_T/aj53" && bash -c "$AJ53_CMD") >/dev/null 2>&1 && [ -s "$AJ_T/aj53/docs/eventos/fx.jsonl" ]
afirma "aj53b-o-comando-do-aj53-grava-de-verdade" $? "$AJ53_CMD, num diretorio descartavel, cria docs/eventos/fx.jsonl"
aj_tr_viola "aj54-wrapper-nohup-e-atravessado" \
  'nohup cp /tmp/f.jsonl docs/eventos/fx.jsonl' "nohup"
aj_tr_viola "aj55-wrapper-nice-e-atravessado" \
  'nice cp /tmp/f.jsonl docs/eventos/fx.jsonl' "nice"
aj_tr_viola "aj56-wrapper-nice-com-n-e-valor-e-atravessado" \
  'nice -n 5 cp /tmp/f.jsonl docs/eventos/fx.jsonl' "nice -n 5 (opcao com valor separado)"
aj_tr_viola "aj57-wrapper-ionice-com-c-e-valor-e-atravessado" \
  'ionice -c 2 cp /tmp/f.jsonl docs/eventos/fx.jsonl' "ionice -c 2 (opcao com valor separado)"
aj_tr_viola "aj58-wrapper-stdbuf-com-valor-anexado-e-atravessado" \
  'stdbuf -o0 cp /tmp/f.jsonl docs/eventos/fx.jsonl' "stdbuf -o0 (valor anexado, um token so)"
aj_tr_viola "aj59-wrapper-setsid-e-atravessado" \
  'setsid cp /tmp/f.jsonl docs/eventos/fx.jsonl' "setsid"
aj_tr_viola "aj60-wrapper-winpty-e-atravessado" \
  'winpty cp /tmp/f.jsonl docs/eventos/fx.jsonl' "winpty"
aj_tr_viola "aj61-wrapper-sudo-e-atravessado" \
  'sudo cp /tmp/f.jsonl docs/eventos/fx.jsonl' "sudo"
aj_tr_viola "aj62-wrapper-doas-e-atravessado" \
  'doas cp /tmp/f.jsonl docs/eventos/fx.jsonl' "doas"
aj_tr_viola "aj63-wrapper-time-e-atravessado" \
  'time cp /tmp/f.jsonl docs/eventos/fx.jsonl' "time"
aj_tr_viola "aj64-wrapper-timeout-com-opcao-longa-e-duracao-e-atravessado" \
  'timeout --signal=KILL 5 cp /tmp/f.jsonl docs/eventos/fx.jsonl' "timeout com opcao longa antes da duracao"
aj_tr_viola "aj65-wrappers-encadeados-sao-atravessados" \
  'nohup nice sudo cp /tmp/f.jsonl docs/eventos/fx.jsonl' "tres wrappers em fila"
# E os controles de LEITURA atras de wrapper: atravessar o wrapper nao pode inventar escrita.
aj_tr_le "aj66-env-com-cat-e-leitura" 'env cat docs/eventos/fx.jsonl' "env cat"
aj_tr_le "aj67-timeout-com-grep-e-leitura" \
  'timeout 5 grep write docs/eventos/fx.jsonl' 'timeout 5 grep, com write como PADRAO do grep'
aj_tr_le "aj68-env-copiando-o-rastro-para-fora-e-leitura" \
  'env cp docs/eventos/fx.jsonl /tmp/copia.jsonl' "env cp com o rastro como ORIGEM"
aj_tr_le "aj69-env-com-interpretador-que-so-le-e-leitura" \
  "env python3 -c \"print(open('docs/eventos/fx.jsonl').read())\"" "env python3 apenas lendo"
aj_tr_le "aj70-sudo-com-u-e-usuario-lendo-e-leitura" \
  'sudo -u deploy cat docs/eventos/fx.jsonl' "-u consumido, e o comando real e cat"
if [ "$AJ_TR_OK" = 1 ]; then
  aj_bom > "$AJ_T/tr-bom"; AJ_V="$(aj_verifica "$AJ_T/tr-bom")"
  [ -z "$AJ_V" ]
  afirma "aj17-transcrito-conforme-continua-aprovando" $? "${AJ_V:-escritor no inicio e no fim, nenhuma violacao}"
fi

# ------------------------------------------------- 4. a ORDEM real: primeira edicao depois do claim
aj_rastro() { # aj_rastro <arquivo> <evento:detalhe> ... — monta um rastro na ordem dada
  local arq="$1" e ev det n=0; shift
  : > "$arq"
  for e in "$@"; do
    n=$((n + 1)); ev="${e%%:*}"; det="${e#*:}"
    printf '{"ts":"2026-10-01T10:%02d:00Z","expx_eventos":1,"trabalho_id":"dc","ferramenta":"sprintx","origem":"skill","evento":"%s","fase":"f6","task":"%s","agente":"principal","resultado":"ok","detalhe":null,"arquivos":["%s"],"sessao":"c@1","harness":"c"}\n' \
      "$n" "$ev" "$([ "$ev" = arquivo_alterado ] && printf 'null' || printf 'T-01.01')" "$det" >> "$arq"
  done
}
AJ_RE='src/contador\.sh|test/dobro\.test\.sh'
aj_ordem() { # aj_ordem <nome> <esperado: 0|1> <detalhe> <eventos...>
  local nome="$1" esp="$2" det="$3"; shift 3
  aj_rastro "$AJ_T/ordem.jsonl" "$@"
  ( . "$AJ_H/testes/transcrito-agente.sh"
    rastro_edicao_depois_do_claim "$AJ_T/ordem.jsonl" T-01.01 "$AJ_RE" )
  [ "$?" -eq "$esp" ]
  afirma "$nome" $? "$det"
}
aj_ordem "aj18-primeira-edicao-depois-do-claim-aprova" 0 "claim, depois a primeira edicao da task" \
  task_iniciada:- arquivo_alterado:src/contador.sh arquivo_alterado:test/dobro.test.sh
# O DEFEITO: a primeira edicao veio ANTES do claim, e uma segunda, legitima, veio depois.
aj_ordem "aj19-primeira-edicao-antes-do-claim-reprova" 1 "edicao antes do claim nao e salva por uma edicao legitima depois" \
  arquivo_alterado:src/contador.sh task_iniciada:- arquivo_alterado:test/dobro.test.sh
aj_ordem "aj20-sem-claim-reprova" 1 "edicao sem reivindicacao nenhuma" \
  arquivo_alterado:src/contador.sh arquivo_alterado:test/dobro.test.sh
aj_ordem "aj21-sem-edicao-reprova" 1 "claim sem nenhuma edicao da task" \
  task_iniciada:- arquivo_alterado:src/outro.ts
# Guarda estrutural: a certificacao paga usa o MESMO helper, nao uma segunda copia do awk.
AJ_AR="$AJ_H/testes/agente-real-rastro.sh"
grep -qF 'rastro_edicao_depois_do_claim' "$AJ_AR" && ! grep -qF 'a > i' "$AJ_AR"; AJ_RC=$?
afirma "aj22-certificacao-paga-usa-o-helper-local" "$AJ_RC" "agente-real-rastro.sh chama o helper testavel, sem awk proprio"

# ------------------------------------------------- mutantes
AJ_M="$AJ_T/mut"
aj_copia() { # aj_copia <nome> — copia de .claude/hooks
  local r="$AJ_M/$1"; rm -rf "$r"; mkdir -p "$r"
  cp -R "$AJ_H/comum" "$AJ_H/sprintx" "$AJ_H/testes" "$r/"
  printf '%s' "$r"
}
# aj_def_cmd <tipo> — o comando-sonda de cada defeito de classificacao de comando. Um por tipo,
# para que cada mutante seja julgado por UM comando, e so por ele.
aj_def_cmd() {
  case "$1" in
    anexada)   printf 'cp -tdocs/eventos/ /tmp/f.jsonl' ;;
    abreviada) printf 'cp --targ=docs/eventos/ /tmp/f.jsonl' ;;
    longa)     printf 'cp --target-directory=docs/eventos/ /tmp/f.jsonl' ;;
    opcao)     printf 'cp -t docs/eventos/ /tmp/f.jsonl' ;;
    wrapper)   printf 'env cp /tmp/f.jsonl docs/eventos/fx.jsonl' ;;
    wrapopt)   printf 'sudo -u deploy cp /tmp/f.jsonl docs/eventos/fx.jsonl' ;;
    duracao)   printf 'timeout 5 cp /tmp/f.jsonl docs/eventos/fx.jsonl' ;;
  esac
}
aj_defeito() { # aj_defeito <raiz-hooks> <tipo> — 0 quando AQUELA arvore exibe o defeito do tipo
  local r="$1" tipo="$2" rc=1 guarda="$AJ_H"
  AJ_H="$r"
  case "$tipo" in
    saida)   aj_roda objeto "$AJ_ERR_ANSI" "$PATH"; [ "$(aj_resultado)" = ok ] && rc=0 ;;
    saida-sj) aj_roda objeto "$AJ_ERR_ANSI" "$AJ_SEMJQ"; [ "$(aj_resultado)" != falha ] && rc=0 ;;
    ordem)   aj_rastro "$AJ_T/o.jsonl" arquivo_alterado:src/contador.sh task_iniciada:- arquivo_alterado:test/dobro.test.sh
             ( . "$r/testes/transcrito-agente.sh"
               rastro_edicao_depois_do_claim "$AJ_T/o.jsonl" T-01.01 "$AJ_RE" ) && rc=0 ;;
    manual)  { aj_bom; aj_ev Bash '{"command":"cp /tmp/f.jsonl docs/eventos/fx.jsonl"}'; } > "$AJ_T/trm"
             ( . "$r/testes/transcrito-agente.sh"; transcrito_verifica "$AJ_T/trm" 1111-2222 fx T-01.01 || : ) \
               | grep -q '^rastro_manual:' || rc=0 ;;
    leitura) { aj_bom; aj_ev Bash '{"command":"cat docs/eventos/fx.jsonl"}'; } > "$AJ_T/trl"
             [ -n "$( . "$r/testes/transcrito-agente.sh"; transcrito_verifica "$AJ_T/trl" 1111-2222 fx T-01.01 || : )" ] && rc=0 ;;
    destino) { aj_bom; aj_ev Bash '{"command":"cp /tmp/forjado.jsonl docs/eventos/fx.jsonl 2>/dev/null"}'; } > "$AJ_T/trd"
             ( . "$r/testes/transcrito-agente.sh"; transcrito_verifica "$AJ_T/trd" 1111-2222 fx T-01.01 || : ) \
               | grep -q '^rastro_manual:' || rc=0 ;;
    pegajoso) { aj_bom
               aj_ev Bash "$(python3 -c 'import json,sys; print(json.dumps({"command":sys.argv[1]}))' "$AJ_CMD_LE_B")"
             } > "$AJ_T/trp"
             [ -n "$( . "$r/testes/transcrito-agente.sh"; transcrito_verifica "$AJ_T/trp" 1111-2222 fx T-01.01 || : )" ] && rc=0 ;;
    # Os defeitos de PR#14: cada um tem o seu comando-sonda, e o defeito e a sonda passar por
    # leitura quando ela escreve no rastro.
    anexada|abreviada|longa|opcao|wrapper|wrapopt|duracao)
             { aj_bom
               aj_ev Bash "$(python3 -c 'import json,sys; print(json.dumps({"command":sys.argv[1]}))' "$(aj_def_cmd "$tipo")")"
             } > "$AJ_T/trw"
             ( . "$r/testes/transcrito-agente.sh"; transcrito_verifica "$AJ_T/trw" 1111-2222 fx T-01.01 || : ) \
               | grep -q '^rastro_manual:' || rc=0 ;;
  esac
  AJ_H="$guarda"
  return "$rc"
}
aj_mutante() { # aj_mutante <nome> <rc da geracao> <raiz-hooks> <tipo que TEM de reverter> [tipos que NAO podem reverter...]
  local nome="$1" rcg="$2" r="$3" tipo="$4" rc=1 carona="" c; shift 4
  if [ "$rcg" -eq 0 ]; then
    aj_defeito "$r" "$tipo" && rc=0
    # Nao vale morrer de carona: o que o mutante NAO mexeu tem de continuar classificado certo.
    for c in "$@"; do aj_defeito "$r" "$c" && carona="$carona$c "; done
  fi
  [ "$rcg" -eq 0 ] && [ "$rc" -eq 0 ] && [ -z "$carona" ]
  afirma "$nome" $? "o mutante volta ao defeito de '$tipo' (rc geracao=$rcg)${carona:+ — MORTE DE CARONA em: $carona}"
}
# m1 — a remocao de ANSI desaparece: a saida colorida volta a ser classificada como ok.
AJR="$(aj_copia m1)" && muta_lit "$AJ_H/comum/rastro.sh" "$AJR/comum/rastro.sh" \
  '    *"$RASTRO_ESC"*)' '    *naoexisteESC*)'
aj_mutante "ajm-mutante-1-sem-remocao-de-ansi" $? "$AJR" saida
# m2 — a leitura do tool_response volta a aceitar so string: no objeto, sem jq, nada e classificado.
AJR="$(aj_copia m2)" && muta_lit "$AJ_H/comum/rastro-post.sh" "$AJR/comum/rastro-post.sh" \
  'rastro_tool_response_em SAIDA "$ENTRADA"' 'SAIDA="$(rastro_json_get "$ENTRADA" tool_response)"'
aj_mutante "ajm-mutante-2-tool-response-so-como-string" $? "$AJR" saida-sj
# m3 — a prova da ordem volta a so marcar a edicao DEPOIS do claim.
AJR="$(aj_copia m3)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  '$0 ~ re && !a { a = NR }' '$0 ~ re && i && !a { a = NR }'
aj_mutante "ajm-mutante-3-ordem-ignora-edicao-antes-do-claim" $? "$AJR" ordem
# m4 — a auditoria volta a olhar so redirecao/tee/sed -i: cp e mv passam.
AJR="$(aj_copia m4)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  'if _tr_escreve_no_rastro "$cmd"; then' 'if [[ $cmd =~ $_TR_REDIR ]] || [[ $cmd =~ $_TR_SED ]]; then'
aj_mutante "ajm-mutante-4-auditoria-sem-cp-e-mv" $? "$AJR" manual
# m5 — a auditoria vira blacklist de mencao: `cat docs/eventos/...` passa a reprovar.
AJR="$(aj_copia m5)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  '  case "$c" in *docs/eventos*) ;; *) return 1 ;; esac' '  case "$c" in *docs/eventos*) return 0 ;; *) return 1 ;; esac'
aj_mutante "ajm-mutante-5-blacklist-reprova-leitura" $? "$AJR" leitura
# m6 — a decisao de destino volta a olhar so o ULTIMO token do segmento: com `2>/dev/null` no fim,
# o destino real fica invisivel e `cp origem docs/eventos/x 2>/dev/null` passa.
AJR="$(aj_copia m6)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  '        # Forma posicional: o primeiro operando e ORIGEM, qualquer outro e destino.' \
  '        op=("${tk[$((${#tk[@]} - 1))]}")'
aj_mutante "ajm-mutante-6-destino-volta-a-ser-o-ultimo-token" $? "$AJR" destino
# m7 — o estado do interpretador volta a ser PEGAJOSO entre segmentos: o `grep -c write` do
# segmento seguinte herda a escrita e a leitura do rastro reprova.
AJR="$(aj_copia m7)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  '    if [[ $cab =~ ^($_TR_SO_LEEM)$ ]] && [[ $seg != *'"'"'('"'"'* ]]; then' '    if false; then'
aj_mutante "ajm-mutante-7-interpretador-pegajoso-entre-segmentos" $? "$AJR" pegajoso
# PR#14 — os tres pedacos novos da regra, um mutante cada, e cada um julgado pelo seu comando-sonda
# com os outros listados como controle de NAO-carona.
#
# m8 — o destino ANEXADO a opcao curta deixa de ser lido: `-tdocs/eventos/` volta a pegar o token
# seguinte como destino, e a escrita fica invisivel. A forma separada (`-t dir`) nao e tocada.
AJR="$(aj_copia m8)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  'destino="${t#*t}"' 'destino=""'
aj_mutante "ajm-mutante-8-opcao-curta-sem-o-destino-anexado" $? "$AJR" anexada opcao abreviada longa wrapper wrapopt duracao manual leitura
# m9 — a opcao longa volta a exigir o nome INTEIRO: `--targ=` deixa de ser abreviacao valida.
AJR="$(aj_copia m9)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  'case target-directory in "$o"*) return 0 ;; esac' 'case target-directory in "$o") return 0 ;; esac'
aj_mutante "ajm-mutante-9-opcao-longa-sem-abreviacao" $? "$AJR" abreviada longa anexada opcao wrapper wrapopt duracao manual leitura
# m10 — a lista de wrappers transparentes desaparece: `env cp ...` volta a ser julgado como `env`,
# nome fora de toda lista, segmento ignorado.
AJR="$(aj_copia m10)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  "_TR_WRAPPER='env|" "_TR_WRAPPER='naoexisteWRAPPER|"
aj_mutante "ajm-mutante-10-sem-os-wrappers-transparentes" $? "$AJR" wrapper anexada opcao abreviada longa manual leitura
# m11 — o consumo da opcao com valor em token SEPARADO desaparece: `sudo -u deploy cp ...` acha
# `deploy` no lugar do `cp`. O wrapper sem opcao (`env cp`) e a duracao do `timeout` nao sao tocados.
AJR="$(aj_copia m11)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  'if [ -n "$oparg" ] && [[ $t =~ ^($oparg)$ ]]; then n=$((n + 2)); else n=$((n + 1)); fi' 'n=$((n + 1))'
aj_mutante "ajm-mutante-11-sem-o-consumo-das-opcoes-do-wrapper" $? "$AJR" wrapopt wrapper duracao anexada opcao abreviada longa manual leitura
# m12 — a duracao POSICIONAL do `timeout` deixa de ser consumida: o `5` passa por comando real.
AJR="$(aj_copia m12)" && muta_lit "$AJ_H/testes/transcrito-agente.sh" "$AJR/testes/transcrito-agente.sh" \
  'if [ "$cab" = timeout ] && [ "$n" -lt "${#tk[@]}" ]; then' 'if [ "$cab" = naotimeout ] && [ "$n" -lt "${#tk[@]}" ]; then'
aj_mutante "ajm-mutante-12-sem-a-duracao-posicional-do-timeout" $? "$AJR" duracao wrapper wrapopt anexada opcao abreviada longa manual leitura
# Controle da propria bateria: a copia SEM mutacao nenhuma nao exibe defeito nenhum.
AJR="$(aj_copia controle)"; AJ_RC=0
for aj_d in anexada abreviada longa opcao wrapper wrapopt duracao manual leitura destino pegajoso saida saida-sj ordem; do
  aj_defeito "$AJR" "$aj_d" && { AJ_RC=1; AJ_VIVO="${AJ_VIVO-}$aj_d "; }
done
afirma "ajm-controle-copia-intacta-nao-exibe-defeito" "$AJ_RC" "${AJ_VIVO-nenhum defeito na copia sem mutacao}"

rm -rf "$AJ_T"

echo "== AK. 1.00 MEDIDO e fator legitimo, e o caminho critico se escolhe pela duracao corrigida (PR#12) =="
# Dois defeitos de contrato na estimativa:
#
#   1. A proibicao do neutro (DS-46) virou proibicao do VALOR. Ela existe para que ausencia de
#      fator nao se disfarce de fator — e ausencia se diz com `null`. Mas um tipo com 3 ou mais
#      entradas elegiveis cuja media de desvios da exatamente `1.00` tem um fator MEDIDO, e ele
#      diz algo: "este tipo tem historico suficiente e o projeto acerta a estimativa dele".
#      Proibir `1.00` indiscriminadamente obrigava a gravar `null` ali — ou seja, obrigava a
#      mentir "nao ha historico" exatamente no tipo melhor calibrado do projeto, e a apagar a
#      distincao que a propria DS-46 queria preservar. O que continua proibido e `1.00` NO LUGAR
#      de `null`: sem historico, com menos de 3 elegiveis ou com `fator_ativo: false`.
#   2. A selecao do caminho critico usava a media CRUA. O `fator(t)` entra na soma e na quadratura
#      (DS-167), mas a regra de ACHAR a cadeia mais longa somava `media_task(t)` sem fator — e com
#      fatores diferentes entre os tipos o ramo mais longo em media crua nao e o mais longo de
#      verdade. A saida publicava a cadeia errada e um `caminho_critico` menor que o real.
#
# Os dois casos tem oraculo executavel aqui, nao so marcador de texto: o numero que a regra manda
# gravar e o ramo que a regra manda escolher sao calculados, e e contra esse calculo que o
# contrato escrito e conferido.
AK_SK="$SK"

# --------------------------------------------------------- oraculo 1: o fator que se grava
# Dado os `desvio` persistidos de um tipo ("null" para a entrada sem desvio), o que o item de
# `calibracao_por_tipo` tem de gravar em `fator`: `null` com menos de 3 elegiveis, ou a media das
# elegiveis com duas casas half-up (DS-160/DS-164) — INCLUSIVE quando essa media e `1.00`.
# `Decimal` evita que uma fronteira como 1.005 caia abaixo do meio por representação binária.
ak_fator() { # ak_fator <desvio|null> ...
  python3 - "$@" <<'PY'
from decimal import Decimal, ROUND_HALF_UP
import sys
valores = [Decimal(v) for v in sys.argv[1:] if v != "null"]
if len(valores) < 3:
    print("null")                                            # fator_ativo: false (DS-164)
else:
    media = sum(valores, Decimal()) / Decimal(len(valores))
    print(media.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))
PY
}
[ "$(ak_fator 1.005 1.005 1.005)" = "1.01" ]
afirma "ak0-oraculo-fronteira-decimal-half-up" $? "1.005 exato -> 1.01, sem erro de ponto flutuante binário"
[ "$(ak_fator 1.00 1.00 1.00)" = "1.00" ]
afirma "ak1-oraculo-media-exata-de-1-e-fator-1.00" $? "3 elegiveis, todas 1.00 -> fator medido 1.00, nunca null"
[ "$(ak_fator 0.90 1.00 1.10)" = "1.00" ]
afirma "ak2-oraculo-desvios-que-se-compensam-dao-1.00" $? "0,90 + 1,00 + 1,10 -> media exatamente 1.00"
[ "$(ak_fator 0.98 1.00 1.03)" = "1.00" ]
afirma "ak3-oraculo-media-que-arredonda-para-1.00" $? "1,00333... -> 1.00 pelas duas casas half-up"
[ "$(ak_fator 1.00 1.00)" = "null" ]
afirma "ak4-oraculo-duas-elegiveis-e-null-nao-1.00" $? "menos de 3 elegiveis -> null, e e a proibicao da DS-46 que continua"
[ "$(ak_fator null null null)" = "null" ]
afirma "ak5-oraculo-sem-desvio-elegivel-e-null" $? "nenhuma entrada elegivel -> null, nunca 1.00"
[ "$(ak_fator 1.13 1.13 1.17 1.20)" = "1.16" ]
afirma "ak6-oraculo-exemplo-canonico-nao-regride" $? "o 1.16 da DS-160 continua saindo igual"

# --------------------------------------------------------- oraculo 2: qual ramo e o critico
# Cada ramo e uma cadeia; a duracao dela e a soma de media_task(t) * fator(t). Com fatores
# diferentes entre os tipos, o ramo mais longo em media CRUA pode nao ser o mais longo corrigido.
ak_critico() { # ak_critico <modo: cru|corrigido> <ramo:media:fator> ...
  local modo="$1"; shift
  awk -v modo="$modo" -v lista="$*" '
    BEGIN {
      n = split(lista, r, / +/)
      for (i = 1; i <= n; i++) {
        split(r[i], c, ":")
        D[c[1]] += c[2] * (modo == "corrigido" ? c[3] : 1)
      }
      melhor = ""; maior = -1
      for (k in D) if (D[k] > maior) { maior = D[k]; melhor = k }
      printf "%s=%.2f\n", melhor, maior
    }'
}
AK_RAMOS="A:10:0.80 B:9:1.20"
[ "$(ak_critico cru $AK_RAMOS)" = "A=10.00" ]
afirma "ak7-oraculo-pela-media-crua-o-ramo-a-parece-critico" $? "10,00 > 9,00 — a conta ERRADA, registrada para o caso ter contraste"
[ "$(ak_critico corrigido $AK_RAMOS)" = "B=10.80" ]
afirma "ak8-oraculo-corrigido-pelo-fator-o-critico-e-o-ramo-b" $? "10,00*0,80=8,00 contra 9,00*1,20=10,80 — o fator TROCA o ramo critico"
# Controle: com o mesmo fator nos dois ramos, a correcao nao muda a escolha.
[ "$(ak_critico corrigido A:10:1.20 B:9:1.20)" = "A=12.00" ]
afirma "ak9-oraculo-fator-igual-nos-dois-nao-troca-o-ramo" $? "fator igual: a ordem dos ramos e a mesma da media crua"

# --------------------------------------------------------- o contrato escrito
AK_LIT_SCH_100='`1.00` medido é um fator legítimo, e é obrigatório gravá-lo (DS-172)'
AK_LIT_SCH_100_QUANDO='o canônico daquele tipo tem `fator_ativo: true` e a média dos `desvio` elegíveis é exatamente `1.00`'
AK_LIT_SCH_100_PROIBIDO='O que a DS-46 proíbe é `1.00` **no lugar de** `null`'
AK_LIT_SCH_POR_TIPO='Nenhum item de `calibracao_por_tipo` usa `1.00` no lugar de `null`'
AK_LIT_EST_100='`1.00` **medido** é fator legítimo e vai gravado como `1.00`, nunca convertido em `null` (DS-172)'
AK_LIT_TPL_100='`1.00` medido vai gravado como `1.00`'
# A proibicao preservada: a frase da DS-46 continua nos dois arquivos que a bancada ja exigia.
AK_LIT_SCH_DISFARCE='Nunca `1.00` para disfarçar ausência de fator (DS-46)'
AK_LIT_EST_DISFARCE='Nunca `1.00` disfarçando ausência de fator (DS-46)'
# E a frase antiga, que proibia o VALOR sem distinguir o disfarce, nao sobrevive.
AK_LIT_PROIBE_ANTIGA='!Nenhum item de `calibracao_por_tipo` grava `1.00` como fator ativo'
# Caminho critico: a selecao usa a duracao corrigida, e o exemplo do ramo que troca existe.
AK_LIT_EST_SEL='`caminho(t) = media_task(t) * fator(t) + máximo dos caminho(anteriores)`'
AK_LIT_EST_SEL_REGRA='A duração que seleciona o caminho é a já corrigida pelo `fator(t)` do tipo daquela task, nunca a média crua (DS-173)'
AK_LIT_EST_EXEMPLO='Exemplo em que o fator troca o ramo crítico'
AK_LIT_EST_EXEMPLO_NUM='as durações corrigidas são `8,00` e `10,80`, e o ramo crítico é o de `T-02.01`'
AK_LIT_TPL_SEL='A cadeia é **selecionada** pela duração já corrigida — `media_task(t) * fator(t)` —, nunca pela média crua'

ak_caso() { # ak_caso <caso> <dir> -> 0 se o caso PASSA naquela arvore
  local c="$1" d="$2"
  case "$c" in
    # O 1.00 medido e fator legitimo, e o contrato diz QUANDO.
    ak_100_legitimo)
      ad_lit "$d/references/00-schema.md" "$AK_LIT_SCH_100" \
             "$d/references/00-schema.md" "$AK_LIT_SCH_100_QUANDO" \
             "$d/references/07-estimativa.md" "$AK_LIT_EST_100" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AK_LIT_TPL_100" ;;
    # A proibicao da DS-46 continua, agora nomeando o que ela proibe: 1.00 no lugar de null.
    ak_100_no_lugar_de_null_proibido)
      ad_lit "$d/references/00-schema.md" "$AK_LIT_SCH_100_PROIBIDO" \
             "$d/references/00-schema.md" "$AK_LIT_SCH_DISFARCE" \
             "$d/references/07-estimativa.md" "$AK_LIT_EST_DISFARCE" ;;
    # A regra por tipo passou a proibir o disfarce, nao o valor — e a forma antiga nao sobrevive.
    ak_por_tipo_proibe_o_disfarce)
      ad_lit "$d/references/00-schema.md" "$AK_LIT_SCH_POR_TIPO" \
             "$d/references/00-schema.md" "$AK_LIT_PROIBE_ANTIGA" ;;
    # A selecao do caminho critico usa a duracao corrigida, nos dois arquivos que a publicam.
    ak_selecao_corrigida_pelo_fator)
      ad_lit "$d/references/07-estimativa.md" "$AK_LIT_EST_SEL" \
             "$d/references/07-estimativa.md" "$AK_LIT_EST_SEL_REGRA" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AK_LIT_TPL_SEL" ;;
    # E o caso em que fatores diferentes trocam o ramo critico esta escrito, com os numeros.
    ak_exemplo_troca_o_ramo)
      ad_lit "$d/references/07-estimativa.md" "$AK_LIT_EST_EXEMPLO" \
             "$d/references/07-estimativa.md" "$AK_LIT_EST_EXEMPLO_NUM" ;;
    # DS-172 e DS-173 registradas, append-only, e as anteriores intactas.
    ak_ds_registradas)
      local v172 v173
      v172="$(grep -F '| DS-172 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
      v173="$(grep -F '| DS-173 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
      [ -n "$v172" ] && [ -n "$v173" ] \
        && printf '%s' "$v172" | grep -qF 'DS-46' \
        && printf '%s' "$v172" | grep -qF 'substitui a parte incompatível da DS-46' \
        && printf '%s' "$v173" | grep -qiF 'caminho crítico' \
        && grep -qF '| DS-46 |' "$d/DECISOES-DA-SKILL.md" \
        && grep -qF '| DS-160 |' "$d/DECISOES-DA-SKILL.md" \
        && grep -qF '| DS-165 |' "$d/DECISOES-DA-SKILL.md" \
        && grep -qF '| DS-166 |' "$d/DECISOES-DA-SKILL.md" \
        && grep -qF '| DS-167 |' "$d/DECISOES-DA-SKILL.md" ;;
    *) return 1 ;;
  esac
}
AK_CASOS="ak_100_legitimo ak_100_no_lugar_de_null_proibido ak_por_tipo_proibe_o_disfarce
ak_selecao_corrigida_pelo_fator ak_exemplo_troca_o_ramo ak_ds_registradas"
ak_nome() { printf '%s' "$1" | tr '_' '-'; }
for ak_c in $AK_CASOS; do
  ak_caso "$ak_c" "$AK_SK"; ak_rc=$?
  afirma "$(ak_nome "$ak_c")" "$ak_rc" "lido da arvore do contrato em $AK_SK"
done

# --------------------------------------------------------- mutantes
AKW="$(mktemp -d)"
ak_copia() { rm -rf "$AKW/$1"; mkdir -p "$AKW/$1"; cp -R "$AK_SK/." "$AKW/$1/"; printf '%s' "$AKW/$1"; }
ak_muta() { [ -f "$1/$2" ] || return 1; muta_lit "$1/$2" "$1/$2.m" "$3" "$4" && mv "$1/$2.m" "$1/$2"; }
ak_mata() { local c; for c in $AK_CASOS; do ak_caso "$c" "$1" || { printf '%s' "$c"; return; }; done; }
ak_mutante() { # ak_mutante <nome> <rc da geracao> <dir> <caso que TEM de matar>...
  local nome="$1" rcg="$2" d="$3" c vivos=""; shift 3
  if [ "$rcg" -eq 0 ]; then for c in "$@"; do ak_caso "$c" "$d" && vivos="$vivos$c "; done; fi
  [ "$rcg" -eq 0 ] && [ -z "$vivos" ]; local rc=$?
  afirma "$nome" "$rc" "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rcg)"
}
AK_CTL="$(ak_copia controle)"
AK_K="$(ak_mata "$AK_CTL")"; [ -z "$AK_K" ]; ak_rc=$?
afirma "akm-controle-copia-intacta-sobrevive" "$ak_rc" "${AK_K:-nenhum caso reprova a copia sem mutacao}"

# m1 — o 1.00 medido deixa de ser declarado legitimo no schema.
AK_M="$(ak_copia m1)"
ak_muta "$AK_M" references/00-schema.md "$AK_LIT_SCH_100" 'Nada a dizer sobre 1.00'
ak_mutante "akm-mutante-1-schema-sem-o-1.00-medido" $? "$AK_M" ak_100_legitimo
# m2 — a proibicao do DISFARCE desaparece: `1.00` passaria a poder substituir `null`.
AK_M="$(ak_copia m2)"
ak_muta "$AK_M" references/00-schema.md 'O que a DS-46 proíbe é `1.00` **no lugar de**' 'Qualquer valor serve'
ak_mutante "akm-mutante-2-schema-sem-a-proibicao-do-disfarce" $? "$AK_M" ak_100_no_lugar_de_null_proibido
# m3 — a regra por tipo volta a proibir o VALOR, nao o disfarce (a forma antiga ressuscita).
AK_M="$(ak_copia m3)"
ak_muta "$AK_M" references/00-schema.md "$AK_LIT_SCH_POR_TIPO" \
  'Nenhum item de `calibracao_por_tipo` grava `1.00` como fator ativo'
ak_mutante "akm-mutante-3-por-tipo-volta-a-proibir-o-valor" $? "$AK_M" ak_por_tipo_proibe_o_disfarce
# m4 — a selecao do caminho critico volta a somar a media CRUA.
AK_M="$(ak_copia m4)"
ak_muta "$AK_M" references/07-estimativa.md "$AK_LIT_EST_SEL" \
  '`caminho(t) = media_task(t) + máximo dos caminho(anteriores)`'
ak_mutante "akm-mutante-4-selecao-volta-a-media-crua" $? "$AK_M" ak_selecao_corrigida_pelo_fator
# m5 — o template perde a frase da selecao corrigida.
AK_M="$(ak_copia m5)"
ak_muta "$AK_M" assets/TEMPLATE-ESTIMATIVA.md "$AK_LIT_TPL_SEL" 'A cadeia e a mais longa.'
ak_mutante "akm-mutante-5-template-sem-a-selecao-corrigida" $? "$AK_M" ak_selecao_corrigida_pelo_fator
# m6 — o exemplo do ramo que troca e apagado: a regra fica sem o caso que a demonstra.
AK_M="$(ak_copia m6)"
ak_muta "$AK_M" references/07-estimativa.md "$AK_LIT_EST_EXEMPLO_NUM" 'os dois ramos empatam'
ak_mutante "akm-mutante-6-exemplo-sem-os-numeros-do-ramo" $? "$AK_M" ak_exemplo_troca_o_ramo
# m7 — DS-172/DS-173 apagadas do registro.
AK_M="$(ak_copia m7)"
ak_muta "$AK_M" DECISOES-DA-SKILL.md '| DS-172 |' '| DS-172-apagada |'
ak_mutante "akm-mutante-7-ds172-apagada" $? "$AK_M" ak_ds_registradas
# m8 — a DS-172 deixa de dizer QUAL parte das decisoes anteriores ela substitui.
AK_M="$(ak_copia m8)"
ak_muta "$AK_M" DECISOES-DA-SKILL.md 'substitui a parte incompatível da DS-46' 'ignora a DS-46'
ak_mutante "akm-mutante-8-ds172-sem-a-substituicao-explicita" $? "$AK_M" ak_ds_registradas

rm -rf "$AKW"

