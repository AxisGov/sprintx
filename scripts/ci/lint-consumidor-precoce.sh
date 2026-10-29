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
# Sem allowlist: o padrao e simples de evitar, e excecao viraria o caminho de volta.
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
    # limpa(s, isolada): sem `isolada`, o estado das aspas atravessa as linhas (simples, dupla)
    function limpa(s, isolada,   r, i, j, c, d, ant, sq, dq, w) {
      r = ""; ant = " "
      sq = isolada ? 0 : simples; dq = isolada ? 0 : dupla
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (sq) { if (c == "\047") sq = 0; continue }
        # heredoc: `<<` fora de aspa e de `((...))`, que nao seja `<<<` nem o fim de um. So o
        # primeiro da linha. O delimitador e lido como o bash le a palavra: pedacos entre aspas e
        # barras se juntam (`<<\047FIM\047x` e `FIMx`), e qualquer aspa ou barra o torna literal.
        if (!isolada && !dq && fim_hd == "" && substr(s, i, 2) == "<<" && substr(s, i + 2, 1) != "<" && ant != "<" && r !~ /\(\([^)]*$/) {
          j = i + 2; hd_tab = 0; hd_literal = 0; w = ""
          if (substr(s, j, 1) == "-") { hd_tab = 1; j++ }
          while (substr(s, j, 1) ~ /[ \t]/) j++
          while (j <= length(s) && substr(s, j, 1) !~ /[ \t;&|()<>]/) {
            d = substr(s, j, 1)
            if (d == "\047" || d == "\"") {
              hd_literal = 1; j++
              while (j <= length(s) && substr(s, j, 1) != d) { w = w substr(s, j, 1); j++ }
              j++
            } else if (d == "\\") { hd_literal = 1; w = w substr(s, j + 1, 1); j += 2 }
            else { w = w d; j++ }
          }
          if (w ~ /^[0-9]+$/ && !hd_literal) w = ""   # $((1<<2)): deslocamento, nao heredoc
          if (w != "") { fim_hd = w; hd_linha = NR; r = r substr(s, i, j - i); i = j - 1; ant = "x"; continue }
        }
        if (c == "\\") { r = r c substr(s, i + 1, 1); i++; ant = "x"; continue }
        if (c == "\047" && !dq) { sq = 1; r = r "\047\047"; ant = c; continue }
        if (c == "\"") dq = !dq
        if (c == "#" && !dq && ant ~ /[ \t;&|(]/) break
        r = r c; ant = c
      }
      if (!isolada) { simples = sq; dupla = dq }
      return r
    }
    # dentro do corpo de um heredoc: so a linha que fecha encerra
    fim_hd != "" {
      t = $0; if (hd_tab) sub(/^\t+/, "", t)
      if (t == fim_hd) { fim_hd = ""; next }
      if (hd_literal) next
      l = limpa($0, 1)
      if (l ~ /(^|[^|])\|[ \t]*(grep[ \t][^|]*(-[A-Za-z]*q|--quiet)|head([ \t]|$))/) print NR ":" l
      next
    }
    {
      l = limpa($0, 0)
      if (cmd == "") ini = NR
      cont = 0
      if (l ~ /\\[ \t]*$/) { sub(/\\[ \t]*$/, " ", l); cont = 1 }
      else if (l ~ /(^|[^|])\|[ \t]*$/) cont = 1
      cmd = cmd l
      if (cont) next
      if (cmd ~ /(^|[^|])\|[ \t]*(grep[ \t][^|]*(-[A-Za-z]*q|--quiet)|head([ \t]|$))/) print ini ":" cmd
      cmd = ""
    }
    # Heredoc que nunca fecha esconderia o resto do arquivo: e achado, nao silencio.
    END { if (fim_hd != "") print hd_linha ":heredoc sem a linha de fechamento " fim_hd
      if (cmd != "" && cmd ~ /(^|[^|])\|[ \t]*(grep[ \t][^|]*(-[A-Za-z]*q|--quiet)|head([ \t]|$))/) print ini ":" cmd }
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
