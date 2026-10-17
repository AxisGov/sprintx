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
# Caminho do payload (no Windows, C:\dir com caixa de drive variavel) sempre pelo helper.
rastro_caminho_em CWD "$CWD"
rastro_caminho_em ALVO "$ALVO"
rastro_raiz_em RAIZ "$CWD"
[ -n "$CONTEUDO" ] || exit 0

REL="${ALVO#"$RAIZ"/}"

# Arquivos que EXISTEM para guardar segredo local nao entram — mas so quando
# ja estao ignorados pelo versionador.
case "$REL" in
  .env|.env.*|*/.env|*/.env.*)
    # `git check-ignore` e a autoridade: uma linha `.env` no .gitignore NAO ignora
    # `.env.example`, que e versionado e precisa ser varrido.
    if git -C "$RAIZ" check-ignore -q -- "$REL" 2>/dev/null; then exit 0; fi
    # sem repositorio (ou sem git): a regra do .gitignore casa como no git — glob
    # (`.env.*` cobre `.env.local`), e, como no git, a ULTIMA regra que casa decide:
    # `!x` depois de `x` desfaz o ignore
    if ! git -C "$RAIZ" rev-parse --git-dir >/dev/null 2>&1 && [ -f "$RAIZ/.gitignore" ]; then
      IGN=0
      while IFS= read -r l || [ -n "$l" ]; do
        l="${l%$'\r'}"
        case "$l" in ''|'#'*) continue ;; esac
        neg=0; case "$l" in '!'*) neg=1; l="${l#!}" ;; esac
        # `/x` e ancorada na raiz: vale so para o caminho inteiro; `x` vale em qualquer pasta.
        # O glob do bash deixa `*` atravessar `/`, o do git nao: so casa com o mesmo numero
        # de `/` no padrao e no caminho (na duvida nao isenta, e o segredo e barrado).
        # `**` atravessa pastas no git, como o glob do bash: sem conferir barras, e `**/x`
        # casa tambem `x` na raiz. So quando todo `**` e um segmento inteiro (no git,
        # `x**` e um `*` comum) e o resto do padrao nao tem outro curinga — um `*` solto
        # ali atravessaria `/` e isentaria mais do que o git.
        casa=0; p="${l#/}"; bp="${p//[!\/]/}"; resto="${p//\*\*/}"; seg="/$p/"; seg="${seg//\/\*\*\//\/}"
        # O `$p` sem aspas a direita de `==` e deliberado: e o padrao do .gitignore, casado
        # como glob (com aspas viraria comparacao literal e nada seria isento).
        # shellcheck disable=SC2053
        if [[ $p == *'**'* && $resto != *[\*\?\[]* && $seg != *'**'* ]]; then
          # `seg` e o padrao com cada `**` valendo zero pastas: `a/**/b` casa `a/b`, `**/x` casa `x`.
          # O `**` no FIM nao vale zero: `a/**` e tudo DENTRO de `a`, nunca o proprio `a` —
          # contar zero ali isentaria `.env` por `.env/**`, e o segredo deixaria de ser varrido.
          if [[ $REL == $p ]] || { [[ $p != *'/**' ]] && [ "/$REL/" = "$seg" ]; }; then casa=1; fi
        elif [[ $REL == $p ]] && [ "${REL//[!\/]/}" = "$bp" ]; then casa=1
        elif [ "$p" = "$l" ] && [ -z "$bp" ] && [[ ${REL##*/} == $p ]]; then casa=1; fi
        [ "$casa" = 1 ] && IGN=$((1 - neg))
      done < "$RAIZ/.gitignore"
      [ "$IGN" = 1 ] && exit 0
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
