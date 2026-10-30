#!/usr/bin/env bash
#
# lint-consumidor-precoce — recusa `| grep -q` e `| head` nos scripts que a sprintx instala.
#
# Sob `pipefail`, o consumidor que decide cedo (`grep -q`, `head`) fecha o pipe enquanto o
# produtor ainda escreve; acima de 64 KB o produtor leva SIGPIPE (141) e o pipeline sai
# diferente de zero, ao contrario do que o consumidor achou. Foi o "task nao esta no plano" do
# Login na 0.12.7 (secao AN da bancada). A forma certa: here-string (`grep -q ... <<<"$x"`),
# `case`, a ferramenta lendo o arquivo direto, e `awk 'NR <= n'` no lugar de `head`.
#
#   bash scripts/ci/lint-consumidor-precoce.sh [raiz do .claude]
#
# Varre .claude/hooks e .claude/skills, menos hooks/testes: a bancada nao e instalada, e os
# casos do proprio lint moram nela. Sem allowlist: o padrao e simples de evitar, e excecao
# viraria o caminho de volta.
#
# Alcance (forma literal): `grep` com -q, --quiet, --silent, -m ou --max-count (e as abreviacoes
# GNU, como --qu; a opcao inclusive entre aspas inteiras), e `head`, atras de atribuicao,
# wrapper, caminho, `.exe` (Git Bash), `(`, barra ou aspas, em pipeline de uma ou varias linhas
# (com linha em branco ou comentario depois do `|`), fora de texto entre aspas simples, de
# comentario e de corpo de heredoc literal; no corpo de heredoc nao literal, linha a linha. E uma
# guarda por texto, nao um parser de shell. Fica de fora, e e da revisao: o nome ou a opcao
# montados em pedacos (`g\rep`, `-\047q\047`, `--qu"iet"`, `$'grep'`), a opcao vinda de expansao
# (`"$opt"`), o `$(...)` de varias linhas dentro de heredoc, o comando dinamico (`eval`,
# `bash -c`, `"$cmd"`), e os outros consumidores que saem cedo (`awk` com `exit`, `sed q`,
# `read` com `break`) — os desses que havia foram convertidos na DS-192.
set -uo pipefail

RAIZ="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.claude" && pwd)}"

# varre <arquivo> — "linha:comando" de cada ocorrencia. Antes de procurar, o awk:
#   - tira o texto entre aspas simples (literal: mensagem, programa de awk), inclusive o que
#     atravessa linhas, e o comentario (`#` fora de aspa, no comeco ou depois de espaco, `;`,
#     `&`, `|` ou `(`). O texto entre aspas duplas fica: ali dentro pode haver `$(... | grep -q)`;
#   - nao conta aspa dentro do corpo de heredoc, que e texto: o corpo de `<<'FIM'` sai inteiro;
#     o de `<<FIM` e varrido linha a linha, porque ali `$(...)` ainda roda;
#   - junta a linha que termina em `\` ou em `|` com a seguinte, porque o pipeline quebrado em
#     duas linhas e o mesmo pipeline. A linha informada e a primeira do comando.
# Um `|` so: o `||` nao e pipe.
varre() {
  awk '
    # O consumidor em qualquer palavra do trecho depois de um `|` so: atras de atribuicao,
    # `env`, `command`, caminho ou qualquer cadeia deles (`| /usr/bin/env A=1 grep -q`), e o
    # `head` colado a operador (`| head;`), e o nome escapado ou entre aspas (`\\grep`, `"head"`,
    # `\047grep\047`), que o shell executa igual, inclusive dentro de `(...)` e com redirecao
    # colada (`grep>/dev/null -q`). Mais largo que o shell exige: um falso positivo
    # falha fechado, e o autor reescreve.
    BEGIN {
      Q = "[\\\\\"\047]*"
      P = "(^|[^|])[|]([^|]*[ \t/(])?" Q "([ef]?grep([.][Ee][Xx][Ee])?" Q "([^A-Za-z0-9_.-][^|]*)?[ \t]" Q "(-[A-Za-z]*[qm][A-Za-z0-9]*|--(q(u(i(e(t)?)?)?)?|s(i(l(e(n(t)?)?)?)?)?|m(a(x(-(c(o(u(n(t)?)?)?)?)?)?)?)?)([^A-Za-z-]|$))|head([.][Ee][Xx][Ee])?" Q "([^A-Za-z0-9_.-]|$))"
    }
    # limpa(s, isolada): sem `isolada`, o estado das aspas atravessa as linhas (simples, dupla)
    function limpa(s, isolada,   r, i, j, c, d, ant, sq, dq, w, lit, tab) {
      r = ""; ant = " "
      sq = isolada ? 0 : simples; dq = isolada ? 0 : dupla
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (sq) { if (c == "\047") sq = 0; continue }
        # heredoc: `<<` fora de aspa e de `((...))`, que nao seja `<<<` nem o fim de um. Uma
        # linha pode abrir varios: os corpos vem na ordem, numa fila. O delimitador e lido como o bash le a palavra: pedacos entre aspas e
        # barras se juntam (`<<\047FIM\047x` e `FIMx`), e qualquer aspa ou barra o torna literal.
        if (!isolada && !dq && substr(s, i, 2) == "<<" && substr(s, i + 2, 1) != "<" && ant != "<" && r !~ /\(\([^)]*$/) {
          j = i + 2; tab = 0; lit = 0; w = ""
          if (substr(s, j, 1) == "-") { tab = 1; j++ }
          while (substr(s, j, 1) ~ /[ \t]/) j++
          while (j <= length(s) && substr(s, j, 1) !~ /[ \t;&|()<>]/) {
            d = substr(s, j, 1)
            if (d == "\047" || d == "\"") {
              lit = 1; j++
              while (j <= length(s) && substr(s, j, 1) != d) { w = w substr(s, j, 1); j++ }
              j++
            } else if (d == "\\") { lit = 1; w = w substr(s, j + 1, 1); j += 2 }
            else { w = w d; j++ }
          }
          if (w ~ /^[0-9]+$/ && !lit) w = ""   # $((1<<2)): deslocamento, nao heredoc
          if (w != "") {
            hd_n++; hd_w[hd_n] = w; hd_lit[hd_n] = lit; hd_tab[hd_n] = tab; hd_lin[hd_n] = NR
            r = r substr(s, i, j - i); i = j - 1; ant = "x"; continue
          }
        }
        if (c == "\\") { r = r c substr(s, i + 1, 1); i++; ant = "x"; continue }
        # palavra simples entre aspas simples (`\047grep\047`) fica: pode ser o nome de um comando
        if (c == "\047" && !dq && (j = index(substr(s, i + 1), "\047")) > 1 \
            && substr(s, i + 1, j - 1) ~ /^[A-Za-z0-9_.\/-]+$/) {
          r = r substr(s, i, j + 1); i += j; ant = "\047"; continue
        }
        if (c == "\047" && !dq) { sq = 1; r = r "\047\047"; ant = c; continue }
        if (c == "\"") dq = !dq
        if (c == "#" && !dq && ant ~ /[ \t;&|(]/) break
        r = r c; ant = c
      }
      if (!isolada) { simples = sq; dupla = dq }
      return r
    }
    # dentro do corpo de um heredoc da fila: so a linha que fecha passa ao proximo
    hd_i <= hd_n && hd_n > 0 && corpo {
      t = $0; if (hd_tab[hd_i]) sub(/^\t+/, "", t)
      if (t == hd_w[hd_i]) { hd_i++; if (hd_i > hd_n) { hd_n = 0; hd_i = 1; corpo = 0 }; next }
      if (hd_lit[hd_i]) next
      l = limpa($0, 1)
      if (l ~ P) print NR ":" l
      next
    }
    {
      l = limpa($0, 0)
      # Depois de um `|` no fim da linha, o Bash aceita linha em branco e comentario antes do
      # consumidor: o pipeline segue pendente.
      if (cmd ~ /(^|[^|])\|[ \t]*$/ && l ~ /^[ \t]*$/) next
      if (cmd == "") ini = NR
      cont = 0
      if (l ~ /\\[ \t]*$/) { sub(/\\[ \t]*$/, " ", l); cont = 1 }
      else if (l ~ /(^|[^|])\|[ \t]*$/) cont = 1
      # O corpo do heredoc comeca depois do comando completo: a linha que termina em `\` ou em
      # `|` ainda e o comando, e so a que o fecha abre o corpo.
      if (hd_n > 0 && !cont) { hd_i = 1; corpo = 1 }
      cmd = cmd l
      if (cont) next
      if (cmd ~ P) print ini ":" cmd
      cmd = ""
    }
    # Heredoc que nunca fecha esconderia o resto do arquivo: e achado, nao silencio.
    END { if (hd_n > 0 && corpo) print hd_lin[hd_i] ":heredoc sem a linha de fechamento " hd_w[hd_i]
      if (cmd != "" && cmd ~ P) print ini ":" cmd }
  ' "$1"
}

achados=0
while IFS= read -r -d '' f; do
  case "$f" in */hooks/testes/*) continue ;; esac
  while IFS= read -r linha; do
    printf 'consumidor precoce: %s:%s\n' "${f#"$RAIZ"/}" "$linha"
    achados=$((achados + 1))
  done < <(varre "$f")
done < <(find "$RAIZ/hooks" "$RAIZ/skills" -type f -name '*.sh' -print0 2>/dev/null)

if [ "$achados" -gt 0 ]; then
  printf '%s ocorrencia(s): troque por here-string, case, leitura direta do arquivo ou awk NR <= n\n' "$achados" >&2
  exit 1
fi
echo "ok: nenhum | grep -q nem | head nos scripts instalados"
