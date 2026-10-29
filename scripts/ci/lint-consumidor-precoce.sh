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
#   - tira o texto entre aspas simples (literal: mensagem, programa de awk) e o comentario
#     (`#` fora de aspa, no comeco ou depois de espaco). O texto entre aspas duplas fica: ali
#     dentro pode haver `$(... | grep -q)`;
#   - junta a linha que termina em `\` ou em `|` com a seguinte, porque o pipeline quebrado em
#     duas linhas e o mesmo pipeline. A linha informada e a primeira do comando.
# Um `|` so: o `||` nao e pipe.
varre() {
  awk '
    function limpa(s,   r, i, c, simples, dupla, ant) {
      r = ""; simples = 0; dupla = 0; ant = " "
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (simples) { if (c == "\047") simples = 0; continue }
        if (c == "\\" && !simples) { r = r c substr(s, i + 1, 1); i++; ant = "x"; continue }
        if (c == "\047" && !dupla) { simples = 1; r = r "\047\047"; ant = c; continue }
        if (c == "\"") dupla = !dupla
        if (c == "#" && !dupla && ant ~ /[ \t]/) break
        r = r c; ant = c
      }
      return r
    }
    {
      l = limpa($0)
      if (cmd == "") ini = NR
      cont = 0
      if (l ~ /\\[ \t]*$/) { sub(/\\[ \t]*$/, " ", l); cont = 1 }
      else if (l ~ /(^|[^|])\|[ \t]*$/) cont = 1
      cmd = cmd l
      if (cont) next
      if (cmd ~ /(^|[^|])\|[ \t]*(grep[ \t][^|]*(-[A-Za-z]*q|--quiet)|head([ \t]|$))/) print ini ":" cmd
      cmd = ""
    }
    END { if (cmd != "" && cmd ~ /(^|[^|])\|[ \t]*(grep[ \t][^|]*(-[A-Za-z]*q|--quiet)|head([ \t]|$))/) print ini ":" cmd }
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
