#!/usr/bin/env bash
# segredo — PreToolUse em ferramentas de escrita. NASCE EM BLOQUEIO.
#
# "Segredo commitado nao tem volta, e o falso positivo ali e raro."
#
# Este e um hook de SEGURANCA: falha FECHADA. Se ele nao consegue decidir,
# ele barra. E o oposto dos hooks de metodo.
#
# Custo (DS-157): o runner cancela o hook que estoura o timeout e deixa a escrita
# acontecer — timeout e falha ABERTA. O caminho comum e um processo so: o jq le o
# payload direto do stdin e entrega cwd, caminho e conteudo; os padroes sao casados
# pelo proprio bash. O hook e a primeira barreira; a posterior, fail-closed, e o E1
# da mergex.
set -uo pipefail

case "${BASH_SOURCE[0]}" in */*) DIR="${BASH_SOURCE[0]%/*}" ;; *) DIR=. ;; esac
# shellcheck source=./rastro.sh
. "$DIR/rastro.sh"

# cwd, file_path e o conteudo (content, ou new_string quando content e vazio), separados
# por NUL. O conteudo pode ter centenas de KB: quem o decodifica e o jq, nunca uma regex
# do bash, e o NUL de dentro dele cai (como caia no `$(...)` de antes).
CAMPOS=()
if command -v jq >/dev/null 2>&1 && { [ "${BASH_VERSINFO[0]:-0}" -gt 4 ] || { [ "${BASH_VERSINFO[0]:-0}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -ge 4 ]; }; }; then
  mapfile -d '' CAMPOS < <(jq -j '
    (.cwd // "" | tostring), "\u0000",
    (.tool_input.file_path // "" | tostring), "\u0000",
    ((if ((.tool_input.content // "") | tostring) != "" then .tool_input.content else (.tool_input.new_string // "") end)
      | tostring | gsub("\u0000"; "")), "\u0000"' 2>/dev/null)
  CWD="${CAMPOS[0]-}"; ALVO="${CAMPOS[1]-}"; CONTEUDO="${CAMPOS[2]-}"
else
  rastro_le_entrada_em ENTRADA
  rastro_json_campo_em CWD "$ENTRADA" cwd
  rastro_json_campo_em ALVO "$ENTRADA" file_path
  rastro_json_campo_em CONTEUDO "$ENTRADA" content
  [ -n "$CONTEUDO" ] || rastro_json_campo_em CONTEUDO "$ENTRADA" new_string
fi
[ -n "$CWD" ] || CWD="$PWD"
rastro_raiz_em RAIZ "$CWD"
[ -n "$CONTEUDO" ] || exit 0

REL="${ALVO#"$RAIZ"/}"

# Arquivos que EXISTEM para guardar segredo local nao entram — mas so quando
# ja estao ignorados pelo versionador.
case "$REL" in
  .env|.env.*|*/.env|*/.env.*)
    if [ -f "$RAIZ/.gitignore" ]; then
      while IFS= read -r l || [ -n "$l" ]; do
        case "$l" in .env*) exit 0 ;; esac
      done < "$RAIZ/.gitignore"
    fi
    ;;
esac

# Padroes de segredo com forma reconheciveis. Deliberadamente conservador:
# prefixos de provedor e chave privada, que quase nao dao falso positivo.
# Casados pelo bash (ERE, como o grep -E de antes), na ordem: o primeiro nomeia o achado.
# Nenhuma classe atravessa quebra de linha, entao casar o texto inteiro e casar linha a linha.
ACHADO=""
while IFS='|' read -r nome padrao; do
  [ -n "$padrao" ] || continue
  if [[ $CONTEUDO =~ $padrao ]]; then ACHADO="$nome"; break; fi
done <<'PADROES'
chave privada PEM|-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----
token da AWS|AKIA[0-9A-Z]{16}
chave da OpenAI|sk-[A-Za-z0-9]{20,}
chave da Anthropic|sk-ant-[A-Za-z0-9_-]{20,}
token do GitHub|gh[pousr]_[A-Za-z0-9]{30,}
token do Slack|xox[baprs]-[A-Za-z0-9-]{10,}
chave do Google|AIza[0-9A-Za-z_-]{35}
credencial em URL|://[A-Za-z0-9_.-]+:[^@/[:space:]]{8,}@
PADROES

[ -n "$ACHADO" ] || exit 0

# Hook de seguranca: o padrao e bloqueio e ausencia de configuracao NAO rebaixa.
# So um "desligado" explicito desliga.
rastro_modo_em MODO "$RAIZ" segredo seguranca
[ "$MODO" = "desligado" ] && exit 0

rastro_json_escape_em REL_E "$REL"
rastro_grava "$RAIZ" acao_bloqueada hook bloqueado "segredo detectado ($ACHADO) em $REL" "[\"$REL_E\"]"
rastro_bloqueia "sprintx/segredo: isso parece $ACHADO sendo gravado em $REL. Segredo em arquivo versionado nao tem volta. Use variavel de ambiente e referencie por nome, ou grave em um .env ja ignorado pelo versionador. Se for um exemplo/fixture, use um valor claramente falso que nao case com o formato real."
