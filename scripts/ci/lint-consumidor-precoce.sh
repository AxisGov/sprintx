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
achados=0
while IFS= read -r -d '' f; do
  case "$f" in */hooks/testes/*) continue ;; esac
  # Um `|` so (o `||` nao e pipe), fora de linha de comentario.
  while IFS= read -r linha; do
    printf 'consumidor precoce: %s:%s\n' "${f#"$RAIZ"/}" "$linha"
    achados=$((achados + 1))
  done < <(grep -nE '(^|[^|])\|[[:space:]]*(grep[[:space:]][^|]*(-[A-Za-z]*q|--quiet)|head([[:space:]]|$))' "$f" 2>/dev/null \
             | grep -vE '^[0-9]+:[[:space:]]*#')
done < <(find "$RAIZ/hooks" "$RAIZ/skills" -type f -name '*.sh' -print0 2>/dev/null)

if [ "$achados" -gt 0 ]; then
  printf '%s ocorrencia(s): troque por here-string, case, leitura direta do arquivo ou awk NR <= n\n' "$achados" >&2
  exit 1
fi
echo "ok: nenhum | grep -q nem | head nos scripts instalados"
