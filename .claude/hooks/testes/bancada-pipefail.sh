#!/usr/bin/env bash
#
# Secao AN da bancada: consumidor que sai cedo sob `pipefail`. Carregada por `.` de dentro da
# bancada.sh, depois da secao AL: usa os auxiliares e o estado dela.
#
# `produtor | grep -q`, `| head` e `| awk` com `exit` saem assim que decidem. Com a entrada acima
# do buffer do pipe (64 KB), o produtor ainda esta escrevendo, leva SIGPIPE (141), e com
# `pipefail` o pipeline inteiro sai diferente de zero. A decisao vira o contrario do que o
# consumidor achou, de forma intermitente (relato do Login na 0.12.7: o escritor do rastro
# recusou `task_concluida` com "task nao esta no plano", e o tasks.md tinha 76 KB).
#
# Cada caso usa entrada de ~1 MB com o casamento no COMECO e repete: com o defeito, quase toda
# repeticao falha.

[ -n "${SK:-}" ] && [ -f "$SK/SKILL.md" ] || {
  echo "bancada-pipefail: carregue pela bancada.sh (SK ausente ou sem SKILL.md)" >&2
  return 2 2>/dev/null || exit 2
}

echo "== AN. consumidor que sai cedo sob pipefail, com entrada acima de 64 KB =="
AN_T="$(mktemp -d)"
AN_H="$(cd "$H" && pwd)"
AN_N=20
# ~1 MB de linhas que nao casam com nenhum padrao dos casos
an_enchimento() { awk 'BEGIN { for (i = 1; i <= 25000; i++) printf "linha de registro %06d sem nada a dizer\n", i }'; }
an_enchimento > "$AN_T/enche.txt"

# 1. O escritor do rastro acha a task no plano grande (rastro.sh, `tr | grep -q`).
AN_FX="$AN_T/fx"; mkdir -p "$AN_FX/docs/sprintx/features/fx/sprint-01"; git init -q --template= "$AN_FX" >/dev/null 2>&1
{ printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: tasks\ntrabalho_id: fx\nsprint_id: sprint-01\ntasks:\n'
  for i in $(seq -w 1 "$AN_N"); do
    printf '  - id: T-01.%s\n    titulo: t\n    status: em_andamento\n    objetivo: o\n    arquivos:\n      cria: []\n      altera: [src/a%s.ts]\n    teste_integracao: t\n    teste_funcional: t\n    criterio_aceite: c\n    depende_de: []\n    paralelizavel: false\n    concluida_em: null\n    suite: nao_executada\n' "$i" "$i"
  done
  printf -- '---\n\n## Registro\n\n'; cat "$AN_T/enche.txt"; } > "$AN_FX/docs/sprintx/features/fx/sprint-01/tasks.md"
an_falhas=0
for i in $(seq -w 1 "$AN_N"); do
  (cd "$AN_FX" && env -u EXPX_SESSAO -u EXPX_HARNESS CLAUDECODE=1 CLAUDE_CODE_SESSION_ID="an$i" \
    bash "$SK/scripts/rastro.sh" task-iniciada fx "T-01.$i" >/dev/null 2>&1) || an_falhas=$((an_falhas + 1))
done
[ "$an_falhas" -eq 0 ]
afirma "an1-escritor-acha-a-task-no-plano-grande" $? "$AN_N task_iniciada num tasks.md de 1 MB: $an_falhas recusadas"

# 2. A suite vermelha com saida grande e gravada como falha (rastro-post.sh, `printf | grep -q`).
an_post() { # an_post <saida da ferramenta> — grava o resultado em $AN_RES
  rm -rf "$AN_T/repo"; mkdir -p "$AN_T/repo/.git" "$AN_T/repo/docs/eventos"
  python3 -c "
import json, sys
print(json.dumps({'cwd': sys.argv[1], 'tool_name': 'Bash', 'tool_input': {'command': 'npx jest'}, 'tool_response': open(sys.argv[2]).read()}))
" "$AN_T/repo" "$1" > "$AN_T/payload.json"
  (cd "$AN_T/repo" && bash "$AN_H/comum/rastro-post.sh") < "$AN_T/payload.json" >/dev/null 2>&1
  AN_RES="$(grep -o '"resultado":"[a-z]*"' "$AN_T/repo/docs/eventos/sem-trabalho.jsonl" 2>/dev/null | tail -1)"
}
{ printf 'FAIL src/a.test.ts\n'; cat "$AN_T/enche.txt"; } > "$AN_T/jest.txt"
{ printf '[ERROR] Tests run: 3, Failures: 1\n'; cat "$AN_T/enche.txt"; } > "$AN_T/mvn.txt"
an_falhas=0
for i in $(seq 1 "$AN_N"); do
  an_post "$AN_T/jest.txt"; [ "$AN_RES" = '"resultado":"falha"' ] || an_falhas=$((an_falhas + 1))
  an_post "$AN_T/mvn.txt";  [ "$AN_RES" = '"resultado":"falha"' ] || an_falhas=$((an_falhas + 1))
done
[ "$an_falhas" -eq 0 ]
afirma "an2-suite-vermelha-grande-gravada-como-falha" $? "FAIL e [ERROR] no comeco de 1 MB: $an_falhas gravadas como ok"
# controle: a mesma saida sem o padrao continua ok
an_post "$AN_T/enche.txt"; [ "$AN_RES" = '"resultado":"ok"' ]
afirma "an2b-saida-grande-sem-falha-continua-ok" $? "1 MB sem padrao de falha: $AN_RES"

# 3. task-so-fecha-verde avisa no Write grande que conclui sem suite (`printf | grep -q`).
AN_W="$AN_T/w"; mkdir -p "$AN_W/.git" "$AN_W/docs/eventos" "$AN_W/docs/sprintx/features/fx/sprint-01"
{ printf -- '---\nkind: tasks\ntrabalho_id: fx\ntasks:\n  - id: T-01.01\n    status: concluida\n    teste_integracao: t\n    teste_funcional: t\n    suite: nao_executada\n---\n\n'
  cat "$AN_T/enche.txt"; } > "$AN_T/tasks-novo.md"
python3 -c "
import json, sys
print(json.dumps({'cwd': sys.argv[1], 'tool_name': 'Write', 'tool_input': {'file_path': sys.argv[1] + '/docs/sprintx/features/fx/sprint-01/tasks.md', 'content': open(sys.argv[2]).read()}}))
" "$AN_W" "$AN_T/tasks-novo.md" > "$AN_T/write.json"
an_falhas=0
for i in $(seq 1 "$AN_N"); do
  (cd "$AN_W" && bash "$AN_H/sprintx/task-so-fecha-verde.sh") < "$AN_T/write.json" > "$AN_T/saida" 2>&1
  grep -qF 'task nao pode ir para concluida' "$AN_T/saida" || an_falhas=$((an_falhas + 1))
done
[ "$an_falhas" -eq 0 ]
afirma "an3-fecha-verde-avisa-no-write-grande" $? "$AN_N Writes de 1 MB concluindo sem suite: $an_falhas sem aviso"

# 3b. O mesmo aviso com mais de um espaco depois de `status:` (CodeAnt no sprintx#57).
sed 's/    status: concluida/    status:   concluida/' "$AN_T/tasks-novo.md" > "$AN_T/tasks-espaco.md"
python3 -c "
import json, sys
print(json.dumps({'cwd': sys.argv[1], 'tool_name': 'Write', 'tool_input': {'file_path': sys.argv[1] + '/docs/sprintx/features/fx/sprint-01/tasks.md', 'content': open(sys.argv[2]).read()}}))
" "$AN_W" "$AN_T/tasks-espaco.md" > "$AN_T/write-espaco.json"
(cd "$AN_W" && bash "$AN_H/sprintx/task-so-fecha-verde.sh") < "$AN_T/write-espaco.json" > "$AN_T/saida" 2>&1
grep -qF 'task nao pode ir para concluida' "$AN_T/saida"
afirma "an3b-fecha-verde-avisa-com-mais-de-um-espaco" $? "status:   concluida sem suite"

# 4. O escritor de bloqueios le o frontmatter de um 00-BLOQUEIOS.md grande (`tr | awk` com exit).
AN_B="$AN_T/b"; mkdir -p "$AN_B/docs/sprintx/features/fb"; git init -q --template= "$AN_B" >/dev/null 2>&1
{ printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: bloqueios\ntrabalho_id: fb\nbloqueios: []\n---\n\n# Bloqueios\n\n'
  cat "$AN_T/enche.txt"; } > "$AN_B/docs/sprintx/features/fb/00-BLOQUEIOS.md"
an_falhas=0
for i in $(seq 1 "$AN_N"); do
  (cd "$AN_B" && bash "$SK/scripts/bloqueios.sh" validar fb >/dev/null 2>&1) || an_falhas=$((an_falhas + 1))
done
[ "$an_falhas" -eq 0 ]
afirma "an4-bloqueios-le-o-frontmatter-do-arquivo-grande" $? "$AN_N validar com 00-BLOQUEIOS.md de 1 MB: $an_falhas recusados"

# 5. O padrao nao volta: nenhum `| grep -q` nem `| head` nos scripts instalados.
AN_LINT="$H/../../scripts/ci/lint-consumidor-precoce.sh"
if [ -f "$AN_LINT" ]; then
  bash "$AN_LINT" "$H/.." >/dev/null 2>&1
  afirma "an5-lint-sem-consumidor-precoce" $? "scripts/ci/lint-consumidor-precoce.sh"
elif [ -z "$RAIZ_SRC" ]; then
  pula_externo "an5-lint-sem-consumidor-precoce" "$SEM_FONTE"
else
  afirma "an5-lint-sem-consumidor-precoce" 1 "lint ausente: $AN_LINT"
fi

# 6. O proprio lint: acusa o pipeline em qualquer forma, e nao o texto que so parece um.
if [ -f "$AN_LINT" ]; then
  mkdir -p "$AN_T/lint/hooks/x" "$AN_T/lint/skills"
  cat > "$AN_T/lint/hooks/x/casos.sh" <<'AN_CASOS'
produtor |
  grep -Eq 'a'
produtor | \
  grep -q a
x="$(printf '%s' "$y" | grep -q z)"
cat f | head -1
msg='use | grep -q aqui'
echo ok # nao use | grep -q
:;# produtor | grep -q x
mensagem='inicio
produtor | grep -q x
fim'
[ -n "$a" ] || grep -q x f
grep -q x <<<"$y"
cat <<'FIM'
don't | grep -q isto e texto
FIM
cat <<FIM
$(produtor | grep -q y)
it's texto
FIM
echo $((1<<2)) | grep -q 4
echo "<<FIM"
produtor | grep -q depois-de-aspas
cat <<'FIM-1'
texto | grep -q de heredoc com hifen
FIM-1
produtor | grep -q depois-do-hifen
echo $((a<<b)) | grep -q deslocamento
cat <<'FIM'x
texto | grep -q de heredoc com delimitador colado
FIMx
produtor | grep -q depois-do-delimitador-colado
cat <<\FIM
$x | grep -q texto de heredoc com barra
FIM
produtor | LC_ALL=C grep -q com-atribuicao
produtor | env A=1 head -1
produtor | /usr/bin/egrep -q com-caminho
produtor | /usr/bin/env A=1 grep -q env-com-caminho
produtor | builtin command grep -q wrappers-encadeados
produtor | LC_ALL=C sort -u | awk 'NR <= 5'
produtor | head; proximo
cat <<'FIM' \
  | grep -q depois-da-barra
conteudo
FIM
cat <<FIM |
  grep -q depois-do-pipe
conteudo
FIM
produtor | \grep -q com-barra
produtor | \head -n 1
produtor | "grep" -q entre-aspas-duplas
produtor | 'head' -1
produtor | grep -m1 x
produtor | grep --max-count=1 x
produtor | grep --silent x
produtor | (grep -q x)
produtor | grep>/dev/null -q x
produtor | grep -c x
produtor | grep.exe -q x
produtor | /usr/bin/head.exe -1
produtor | grep "-q" x
produtor | grep '--quiet' x
produtor | grep "-m1" x
produtor |
# comentario no meio do pipe

  grep -q depois-do-comentario
produtor | grep --qu x
produtor | grep --max-c=1 x
produtor | grep --s x
produtor | grep -qE x
produtor | grep -iqE x
AN_CASOS
  an_linhas="$(bash "$AN_LINT" "$AN_T/lint" 2>/dev/null | sed -n 's/^consumidor precoce: hooks\/x\/casos\.sh:\([0-9]*\):.*/\1/p' | tr '\n' ' ')"
  [ "$an_linhas" = "1 3 5 6 19 22 24 28 29 33 37 38 39 40 41 43 44 48 52 53 54 55 56 57 58 59 60 62 63 64 65 66 67 71 72 73 74 75 " ]
  afirma "an6-lint-acusa-o-pipeline-e-nao-o-texto" $? "linhas acusadas: ${an_linhas:-nenhuma} (esperado 1 3 5 6 19 22 24 28 29 33 37 38 39 40 41 43 44 48 52 53 54 55 56 57 58 59 60 62 63 64 65 66 67 71 72 73 74 75)"
  # Heredoc que nunca fecha esconderia o resto do arquivo: o lint falha, nao silencia.
  rm -f "$AN_T/lint/hooks/x/casos.sh"
  printf 'cat <<FIM\nsem a linha de fechamento\nprodutor | grep -q escondido\n' > "$AN_T/lint/hooks/x/aberto.sh"
  # A saida vai para a variavel antes: o lint sai 1 quando acha, e sob pipefail `lint | grep`
  # sairia 1 mesmo com o grep casando.
  an_saida="$(bash "$AN_LINT" "$AN_T/lint" 2>/dev/null)"
  grep -qF 'aberto.sh:1:heredoc sem a linha de fechamento FIM' <<<"$an_saida"
  afirma "an6b-lint-falha-no-heredoc-sem-fechamento" $? "heredoc aberto ate o fim do arquivo vira achado"
  # Dois heredocs na mesma linha: o corpo do segundo vem depois do primeiro, e o que parece
  # abrir um terceiro dentro dele e texto (rodada 5 do Codex).
  rm -f "$AN_T/lint/hooks/x/aberto.sh"
  printf '%s\n' 'cat <<A <<'"'"'B'"'"'' 'corpo-A' 'A' 'cat <<'"'"'C'"'"'' 'B' 'produtor | grep -q x' 'C' > "$AN_T/lint/hooks/x/dois.sh"
  an_saida="$(bash "$AN_LINT" "$AN_T/lint" 2>/dev/null)"
  grep -qF 'dois.sh:6:produtor | grep -q x' <<<"$an_saida"
  afirma "an6c-lint-segue-a-fila-de-heredocs-da-linha" $? "o pipeline depois do segundo heredoc e acusado"
fi
rm -rf "$AN_T"
