#!/usr/bin/env bash
# test-predecessores.sh — contrato executavel do manifesto de predecessores.
# Usa somente Git real e arquivos temporarios; nunca usa o checkout da SprintX
# como produto sob teste.
set -uo pipefail

RAIZ_SUITE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="$RAIZ_SUITE/.claude/skills/sprintx/scripts"
PL="$S/planejamento.sh"
K="$(mktemp -d)"
trap 'rm -rf "$K"' EXIT HUP INT TERM

ok=0
falhou=0
fx_n=0

passa() { ok=$((ok + 1)); printf '  ok    %s\n' "$1"; }
reprova() { falhou=$((falhou + 1)); printf '  FALHA %s — %s\n' "$1" "$2"; }

caso_rc() { # caso_rc <nome> <rc> <comando>...
  local nome="$1" esperado="$2" saida real
  shift 2
  saida="$({ "$@"; } 2>&1)"; real=$?
  if [ "$real" -eq "$esperado" ]; then passa "$nome"
  else reprova "$nome" "esperado rc=$esperado, real=$real: $(printf '%s' "$saida" | head -2 | tr '\n' ' ')"; fi
}

caso_falha() { # caso_falha <nome> <comando>...
  local nome="$1" saida real
  shift
  saida="$({ "$@"; } 2>&1)"; real=$?
  if [ "$real" -ne 0 ]; then passa "$nome"
  else reprova "$nome" "aceitou entrada invalida: $(printf '%s' "$saida" | head -2 | tr '\n' ' ')"; fi
}

caso_falha_com() { # caso_falha_com <nome> <trecho> <comando>...
  local nome="$1" trecho="$2" saida real
  shift 2
  saida="$({ "$@"; } 2>&1)"; real=$?
  if [ "$real" -ne 0 ] && printf '%s' "$saida" | grep -qF "$trecho"; then passa "$nome"
  else reprova "$nome" "esperava falha contendo '$trecho'; rc=$real: $(printf '%s' "$saida" | head -2 | tr '\n' ' ')"; fi
}

afirma() { # afirma <nome> <0=verdadeiro> <detalhe>
  if [ "$2" -eq 0 ]; then passa "$1"; else reprova "$1" "$3"; fi
}

git_commit() {
  git -C "$FX" add -A >/dev/null 2>&1
  git -C "$FX" -c commit.gpgsign=false commit -q -m "$1"
}

nova_fixture() {
  fx_n=$((fx_n + 1))
  FX="$K/fx-$fx_n"
  if [ "${1:-sha1}" = sha256 ]; then
    git init -q --object-format=sha256 -b main "$FX"
  else
    git init -q -b main "$FX"
  fi
  git -C "$FX" config user.email teste@fixture.invalid
  git -C "$FX" config user.name teste
  git -C "$FX" config core.autocrlf false
  printf 'inicio\n' > "$FX/README.md"
  git_commit B0
  FX_B0="$(git -C "$FX" rev-parse HEAD)"

  SPEC='docs/superpowers/specs/ft-pre-design.md'
  PLAN='docs/superpowers/plans/ft-pre.md'
  PLANEJAMENTO='docs/sprintx/features/ft-pre/00-PLANEJAMENTO.md'
  mkdir -p "$FX/docs/superpowers/specs" "$FX/docs/superpowers/plans"
  mkdir -p "$FX/docs/sprintx/features/ft-pre" "$FX/docs/entregas/ft-pre"
  printf 'spec v1\n' > "$FX/$SPEC"
  printf 'glob literal\n' > "$FX/docs/superpowers/specs/glob*.md"
  printf 'glob literal\n' > "$FX/docs/superpowers/specs/glob?.md"
  printf 'glob literal\n' > "$FX/docs/superpowers/specs/glob[1].md"
  printf 'yaml inseguro\n' > "$FX/docs/superpowers/specs/a: b.md"
  CONTROLE_PATH="docs/superpowers/specs/controle$(printf '\001').md"
  TRAILING_PATH='docs/superpowers/specs/trailing '
  printf 'controle inseguro\n' > "$FX/$CONTROLE_PATH"
  printf 'espaco final inseguro\n' > "$FX/$TRAILING_PATH"
  mkdir -p "$FX/src"
  printf 'fora da origem\n' > "$FX/src/x.py"
  ln -s ft-pre-design.md "$FX/docs/superpowers/specs/ft-pre-link.md"
  printf 'evidencia interna\n' > "$FX/docs/sprintx/features/ft-pre/evidencia.md"
  printf 'entrega\n' > "$FX/docs/entregas/ft-pre/PR.md"
  git init -q --object-format="$(git -C "$FX" rev-parse --show-object-format)" -b main "$FX/docs/superpowers/gitlink"
  git -C "$FX/docs/superpowers/gitlink" config user.email teste@fixture.invalid
  git -C "$FX/docs/superpowers/gitlink" config user.name teste
  printf 'subrepositorio\n' > "$FX/docs/superpowers/gitlink/README.md"
  git -C "$FX/docs/superpowers/gitlink" add README.md
  git -C "$FX/docs/superpowers/gitlink" -c commit.gpgsign=false commit -q -m subrepositorio
  git_commit S
  FX_SPEC_COMMIT="$(git -C "$FX" rev-parse HEAD)"
  FX_SPEC_BLOB="$(git -C "$FX" rev-parse "$FX_SPEC_COMMIT:$SPEC")"

  printf 'plano v1\n' > "$FX/$PLAN"
  git_commit P
  FX_PLAN_COMMIT="$(git -C "$FX" rev-parse HEAD)"
  FX_PLAN_BLOB="$(git -C "$FX" rev-parse "$FX_PLAN_COMMIT:$PLAN")"

  printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: planejamento' \
    'trabalho_id: ft-pre' 'estado: null' '---' > "$FX/$PLANEJAMENTO"
  printf 'documento no mesmo commit do nascimento\n' > "$FX/docs/superpowers/specs/igual-f1.md"
  git_commit F1
  FX_F1_COMMIT="$(git -C "$FX" rev-parse HEAD)"

  printf 'head\n' >> "$FX/README.md"
  printf 'documento tardio\n' > "$FX/docs/superpowers/specs/tardio.md"
  git_commit HEAD
  FX_HEAD="$(git -C "$FX" rev-parse HEAD)"
  MANIFESTO="$FX/docs/sprintx/features/ft-pre/00-PREDECESSORES.md"
  export FX FX_SPEC_COMMIT FX_PLAN_COMMIT FX_F1_COMMIT FX_SPEC_BLOB FX_PLAN_BLOB
}

pred() { (cd "$FX" && bash "$S/predecessores.sh" "$@"); }

registra() { # registra <papel> <caminho>
  pred --registrar ft-pre --origem superpowers --papel "$1" --caminho "$2"
}

hash_ou_ausente() {
  if [ -f "$MANIFESTO" ]; then cksum < "$MANIFESTO"; else printf 'ausente'; fi
}

manifesto_valido() {
  local caminho="$1" papel="$2" commit="$3" blob="$4"
  mkdir -p "$(dirname "$MANIFESTO")"
  {
    printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: predecessores' 'trabalho_id: ft-pre' 'predecessores:'
    printf '  - caminho: %s\n    origem: superpowers\n    papel: %s\n    commit_sha: %s\n    blob_oid: %s\n' "$caminho" "$papel" "$commit" "$blob"
    printf '%s\n' 'criado_em: 2026-10-13' 'atualizado_em: 2026-10-13' '---' '' "- $papel: $caminho (superpowers)"
  } > "$MANIFESTO"
}

grupo_registro() {
  echo '== registro =='
  nova_fixture
  caso_rc 'registra especificacao' 0 registra especificacao "$SPEC"
  local so_spec
  so_spec="$(pred --listar ft-pre 2>/dev/null)"
  [ "$so_spec" = "$(printf 'predecessor\t%s\t%s\t%s' "$SPEC" "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB")" ]
  afirma 'registro nao descobre predecessores por prefixo' $? "saida apos registrar somente spec: $so_spec"
  caso_rc 'registra plano' 0 registra plano "$PLAN"
  caso_rc 'valida manifesto' 0 pred --validar ft-pre

  local saida esperado before after
  saida="$(pred --listar ft-pre 2>/dev/null)"
  esperado="$(printf 'predecessor\t%s\t%s\t%s\npredecessor\t%s\t%s\t%s' \
    "$PLAN" "$FX_PLAN_COMMIT" "$FX_PLAN_BLOB" "$SPEC" "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB")"
  [ "$saida" = "$esperado" ]; afirma 'lista canonica ordenada pelo caminho' $? "saida: $saida"

  before="$(hash_ou_ausente)"; caso_rc 'registro repetido e no-op' 0 registra especificacao "$SPEC"; after="$(hash_ou_ausente)"
  [ "$before" = "$after" ]; afirma 'idempotencia preserva bytes' $? "$before != $after"
  grep -qF "$SPEC" "$MANIFESTO" && grep -qF 'especificacao' "$MANIFESTO" && grep -qF 'superpowers' "$MANIFESTO"
  afirma 'prosa repete caminho origem e papel' $? 'prosa incompleta'

  nova_fixture
  caso_rc 'recusa SHA informado pelo chamador' 64 pred --registrar ft-pre --origem superpowers \
    --papel especificacao --caminho "$SPEC" --commit-sha "$FX_SPEC_COMMIT"

  nova_fixture sha256
  caso_rc 'registra e valida OIDs SHA-256 completos' 0 registra especificacao "$SPEC"
  caso_rc 'valida manifesto em repositorio SHA-256' 0 pred --validar ft-pre
  [ "${#FX_SPEC_COMMIT}" -eq 64 ] && [ "${#FX_SPEC_BLOB}" -eq 64 ]
  afirma 'manifesto preserva OIDs SHA-256 de 64 caracteres' $? 'OID SHA-256 foi truncado ou recusado'

  nova_fixture
  caso_rc 'precondicao da trava de registro' 0 registra especificacao "$SPEC"
  local trava antes depois
  trava="$(git -C "$FX" rev-parse --absolute-git-dir)/sprintx/predecessores-ft-pre.lock"
  mkdir -p "$(dirname "$trava")"; mkdir "$trava"
  before="$(hash_ou_ausente)"
  caso_falha_com 'trava concorrente falha fechado' 'trava de registro ocupada' registra plano "$PLAN"
  depois="$(hash_ou_ausente)"
  [ "$before" = "$depois" ]; afirma 'trava concorrente preserva manifesto' $? "$before != $depois"
  rmdir "$trava"
  caso_rc 'registro pode ser repetido depois de liberar a trava' 0 registra plano "$PLAN"
  caso_rc 'manifesto conserva as duas entradas depois da contencao' 0 pred --validar ft-pre

  nova_fixture
  local fora="$K/fora-$fx_n"
  mkdir -p "$fora"
  rm -rf "$FX/docs/sprintx/features/ft-pre"
  ln -s "$fora" "$FX/docs/sprintx/features/ft-pre"
  caso_falha_com 'recusa diretorio da feature como symlink' 'diretorio do manifesto nao pode ser symlink' registra especificacao "$SPEC"
  [ ! -e "$fora/00-PREDECESSORES.md" ]
  afirma 'symlink do diretorio nao escreve fora do repositorio' $? 'manifesto escapou para o alvo do symlink'

  nova_fixture
  fora="$K/fora-corrida-$fx_n"
  local bin="$K/bin-corrida-$fx_n" real_mktemp
  mkdir -p "$fora" "$bin"
  real_mktemp="$(command -v mktemp)"
  cat > "$bin/mktemp" <<EOF
#!/bin/sh
case "\${1:-}" in
  .00-PREDECESSORES.md.tmp.*|*/.00-PREDECESSORES.md.tmp.*)
    mv "$FX/docs/sprintx/features/ft-pre" "$FX/docs/sprintx/features/ft-pre-original"
    ln -s "$fora" "$FX/docs/sprintx/features/ft-pre"
    ;;
esac
exec "$real_mktemp" "\$@"
EOF
  chmod +x "$bin/mktemp"
  PATH="$bin:$PATH" caso_falha 'troca concorrente por symlink falha fechado' registra especificacao "$SPEC"
  [ ! -e "$fora/00-PREDECESSORES.md" ]
  afirma 'corrida nao escreve no alvo externo' $? 'manifesto escapou durante a corrida de symlink'
}

invalido_preserva() { # invalido_preserva <nome> <papel> <caminho>
  local nome="$1" papel="$2" caminho="$3" antes depois saida rc
  nova_fixture
  registra especificacao "$SPEC" >/dev/null 2>&1 || { reprova "$nome" 'precondicao de registro falhou'; return; }
  before="$(hash_ou_ausente)"
  saida="$(registra "$papel" "$caminho" 2>&1)"; rc=$?
  depois="$(hash_ou_ausente)"
  if [ "$rc" -ne 0 ] && [ "$before" = "$depois" ]; then passa "$nome"
  else reprova "$nome" "rc=$rc; manifesto foi alterado: $saida"; fi
}

grupo_caminhos() {
  echo '== caminhos =='
  invalido_preserva 'recusa caminho absoluto' plano '/tmp/ft-pre.md'
  invalido_preserva 'recusa prefixo ponto-barra' especificacao "./$SPEC"
  invalido_preserva 'recusa segmento ponto' especificacao 'docs/superpowers/./specs/ft-pre-design.md'
  invalido_preserva 'recusa segmento ponto-ponto' especificacao 'docs/superpowers/specs/../specs/ft-pre-design.md'
  invalido_preserva 'recusa segmento vazio' especificacao 'docs//superpowers/specs/ft-pre-design.md'
  invalido_preserva 'recusa barra invertida' especificacao 'docs\superpowers\specs\ft-pre-design.md'
  invalido_preserva 'recusa glob asterisco' especificacao 'docs/superpowers/specs/glob*.md'
  invalido_preserva 'recusa glob interrogacao' especificacao 'docs/superpowers/specs/glob?.md'
  invalido_preserva 'recusa glob colchete' especificacao 'docs/superpowers/specs/glob[1].md'
  nova_fixture
  printf 'nao rastreado com pathspec magic\n' > "$FX/:(top)README.md"
  caso_falha 'pathspec magic e recusada antes de chegar ao Git' registra especificacao ':(top)README.md'
  invalido_preserva 'recusa propria feature' especificacao 'docs/sprintx/features/ft-pre/evidencia.md'
  invalido_preserva 'recusa propria entrega' especificacao 'docs/entregas/ft-pre/PR.md'
  invalido_preserva 'recusa caminho fora de docs/superpowers' especificacao 'src/x.py'
  invalido_preserva 'recusa scalar YAML inseguro com dois-pontos e espaco' especificacao 'docs/superpowers/specs/a: b.md'
  invalido_preserva 'recusa byte de controle em scalar YAML' especificacao "$CONTROLE_PATH"
  invalido_preserva 'recusa espaco final normalizado por leitores YAML' especificacao "$TRAILING_PATH"
}

grupo_estado_git() {
  echo '== estado-git =='
  nova_fixture; printf 'novo\n' > "$FX/docs/superpowers/specs/untracked.md"; caso_falha 'recusa untracked' registra especificacao 'docs/superpowers/specs/untracked.md'
  nova_fixture; printf 'mudou\n' >> "$FX/$SPEC"; git -C "$FX" add "$SPEC"; caso_falha 'recusa staged' registra especificacao "$SPEC"
  nova_fixture; printf 'mudou\n' >> "$FX/$SPEC"; caso_falha 'recusa modificado' registra especificacao "$SPEC"
  nova_fixture; rm "$FX/$SPEC"; caso_falha 'recusa removido' registra especificacao "$SPEC"
  nova_fixture; caso_rc 'precondicao valida-modificado' 0 registra especificacao "$SPEC"; printf 'mudou\n' >> "$FX/$SPEC"; caso_falha 'validar recusa predecessor modificado' pred --validar ft-pre
  nova_fixture; caso_rc 'precondicao valida-staged' 0 registra especificacao "$SPEC"; printf 'mudou\n' >> "$FX/$SPEC"; git -C "$FX" add "$SPEC"; caso_falha 'validar recusa predecessor staged' pred --validar ft-pre
  nova_fixture; caso_rc 'precondicao valida-removido' 0 registra especificacao "$SPEC"; rm "$FX/$SPEC"; caso_falha 'validar recusa predecessor removido' pred --validar ft-pre
  nova_fixture
  caso_rc 'precondicao assume-unchanged' 0 registra especificacao "$SPEC"
  git -C "$FX" update-index --assume-unchanged "$SPEC"
  printf 'mudou escondido pelo indice\n' > "$FX/$SPEC"
  caso_falha 'recusa modificado escondido por assume-unchanged' pred --validar ft-pre
  git -C "$FX" update-index --no-assume-unchanged "$SPEC"
  nova_fixture; caso_falha 'recusa symlink' registra especificacao 'docs/superpowers/specs/ft-pre-link.md'
  nova_fixture; caso_falha 'recusa gitlink' registra especificacao 'docs/superpowers/gitlink'
  nova_fixture; caso_falha 'recusa diretorio' registra especificacao 'docs/superpowers/specs'
  nova_fixture; mkfifo "$FX/docs/superpowers/specs/especial"; caso_falha 'recusa arquivo especial' registra especificacao 'docs/superpowers/specs/especial'
}

grupo_historia() {
  echo '== historia =='
  nova_fixture; caso_falha 'recusa commit posterior ao nascimento' registra especificacao 'docs/superpowers/specs/tardio.md'
  nova_fixture; caso_falha 'recusa commit igual ao nascimento' registra especificacao 'docs/superpowers/specs/igual-f1.md'

  nova_fixture
  rm "$FX/$PLANEJAMENTO"; git_commit 'remove planejamento'
  printf '%s\n' '---' 'kind: planejamento' '---' > "$FX/$PLANEJAMENTO"; git_commit 'readiciona planejamento'
  caso_falha 'recusa duas adicoes do planejamento' registra especificacao "$SPEC"

  nova_fixture
  caso_rc 'precondicao para clone raso' 0 registra especificacao "$SPEC"
  git_commit 'grava manifesto'
  local raso="$K/raso-$fx_n"
  git clone -q --depth 1 "file://$FX" "$raso"
  FX="$raso"; MANIFESTO="$FX/docs/sprintx/features/ft-pre/00-PREDECESSORES.md"
  caso_falha 'recusa clone raso' pred --validar ft-pre

  nova_fixture
  caso_rc 'precondicao para objeto ausente' 0 registra especificacao "$SPEC"
  git_commit 'grava manifesto'
  rm -f "$FX/.git/objects/${FX_SPEC_COMMIT%${FX_SPEC_COMMIT#??}}/${FX_SPEC_COMMIT#??}"
  caso_falha 'recusa objeto predecessor ausente' pred --validar ft-pre

  nova_fixture
  caso_rc 'precondicao para blob divergente' 0 registra especificacao "$SPEC"
  printf 'spec v2\n' > "$FX/$SPEC"; git_commit 'muda spec depois do planejamento'
  caso_falha 'recusa blob atual divergente' pred --validar ft-pre

  nova_fixture
  caso_rc 'precondicao para prova por HEAD e nao disco' 0 registra especificacao "$SPEC"
  printf 'spec v2\n' > "$FX/$SPEC"; git_commit 'muda spec depois do planejamento'
  git -C "$FX" update-index --assume-unchanged "$SPEC"
  printf 'spec v1\n' > "$FX/$SPEC"
  caso_falha 'recusa HEAD divergente mesmo quando disco repete predecessor' pred --validar ft-pre
  git -C "$FX" update-index --no-assume-unchanged "$SPEC"
}

schema_invalido() { # schema_invalido <nome> <tipo>
  local nome="$1" tipo="$2" corpo
  nova_fixture
  case "$tipo" in
    lista-vazia) corpo='predecessores: []' ;;
    origem) corpo="predecessores:\n  - caminho: $SPEC\n    origem: outra\n    papel: especificacao\n    commit_sha: $FX_SPEC_COMMIT\n    blob_oid: $FX_SPEC_BLOB" ;;
    papel) corpo="predecessores:\n  - caminho: $SPEC\n    origem: superpowers\n    papel: desenho\n    commit_sha: $FX_SPEC_COMMIT\n    blob_oid: $FX_SPEC_BLOB" ;;
    item-antes-lista) corpo="  - caminho: $SPEC\n    origem: superpowers\n    papel: especificacao\n    commit_sha: $FX_SPEC_COMMIT\n    blob_oid: $FX_SPEC_BLOB\npredecessores:" ;;
    scalar) corpo="predecessores:\n  - caminho: [$SPEC\n    origem: superpowers\n    papel: especificacao\n    commit_sha: $FX_SPEC_COMMIT\n    blob_oid: $FX_SPEC_BLOB" ;;
  esac
  mkdir -p "$(dirname "$MANIFESTO")"
  printf '%s\n' '---' 'expx_schema: 1' 'expx_tool: sprintx' 'kind: predecessores' 'trabalho_id: ft-pre' > "$MANIFESTO"
  printf '%b\n' "$corpo" >> "$MANIFESTO"
  printf '%s\n' 'criado_em: 2026-10-13' 'atualizado_em: 2026-10-13' '---' >> "$MANIFESTO"
  caso_falha "$nome" pred --validar ft-pre
}

grupo_schema() {
  echo '== schema =='
  schema_invalido 'recusa lista vazia' lista-vazia
  schema_invalido 'recusa origem fora do enum' origem
  schema_invalido 'recusa papel fora do enum' papel
  schema_invalido 'recusa item antes da lista predecessores' item-antes-lista

  nova_fixture; manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  sed -i '/predecessores:/a\    origem: superpowers' "$MANIFESTO"
  caso_falha 'recusa campo de item fora de item aberto' pred --validar ft-pre

  nova_fixture; manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  sed -i "/criado_em:/a\\  - caminho: $PLAN\n    origem: superpowers\n    papel: plano\n    commit_sha: $FX_PLAN_COMMIT\n    blob_oid: $FX_PLAN_BLOB" "$MANIFESTO"
  caso_falha 'recusa reabrir itens depois de campo top-level' pred --validar ft-pre

  nova_fixture; manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  sed -i "/trabalho_id:/a trabalho_id: ft-pre" "$MANIFESTO"
  caso_falha 'recusa chave repetida' pred --validar ft-pre

  nova_fixture; manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  sed -i "/blob_oid:/a\\    caminho: $SPEC\n    origem: superpowers\n    papel: especificacao\n    commit_sha: $FX_SPEC_COMMIT\n    blob_oid: $FX_SPEC_BLOB" "$MANIFESTO"
  caso_falha 'recusa caminho duplicado' pred --validar ft-pre

  nova_fixture; manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  sed -i "/criado_em:/i\\  - caminho: $PLAN\n    origem: invalida\n    papel: plano\n    commit_sha: $FX_PLAN_COMMIT\n    blob_oid: $FX_PLAN_BLOB" "$MANIFESTO"
  caso_falha 'um item invalido reprova o conjunto inteiro' pred --validar ft-pre

  schema_invalido 'recusa scalar malformado' scalar

  nova_fixture; manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  mv "$MANIFESTO" "$MANIFESTO.real"; ln -s "$(basename "$MANIFESTO.real")" "$MANIFESTO"
  caso_falha 'recusa manifesto como symlink valido' pred --validar ft-pre

  nova_fixture; manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  mv "$MANIFESTO" "$MANIFESTO.real"; ln -s "$MANIFESTO.real" "$MANIFESTO"
  caso_falha 'recusa manifesto como symlink absoluto valido' pred --validar ft-pre

  nova_fixture; mkdir -p "$(dirname "$MANIFESTO")"; ln -s ausente.md "$MANIFESTO"
  caso_falha 'recusa manifesto como symlink quebrado' pred --validar ft-pre

  nova_fixture; manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  local fora_pai="$K/fora-validar-$fx_n"
  mv "$FX/docs/sprintx/features/ft-pre" "$fora_pai"
  ln -s "$fora_pai" "$FX/docs/sprintx/features/ft-pre"
  caso_falha_com 'validar recusa diretorio pai do manifesto como symlink' \
    'diretorio do manifesto nao pode ser symlink' pred --validar ft-pre

  nova_fixture; manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  local fora_corrida="$K/fora-validar-corrida-$fx_n"
  local original_corrida="$K/original-validar-corrida-$fx_n"
  local bin_corrida="$K/bin-validar-corrida-$fx_n" real_cp
  mkdir -p "$fora_corrida" "$bin_corrida"
  cp "$MANIFESTO" "$fora_corrida/00-PREDECESSORES.md"
  sed -i 's/^kind: predecessores/kind: externo/' "$fora_corrida/00-PREDECESSORES.md"
  real_cp="$(command -v cp)"
  cat > "$bin_corrida/cp" <<EOF
#!/bin/sh
if { [ "\${1:-}" = '-P' ] && [ "\${2:-}" = '00-PREDECESSORES.md' ]; } \
  || [ "\${1:-}" = "$MANIFESTO" ]; then
  mv "$FX/docs/sprintx/features/ft-pre" "$original_corrida"
  ln -s "$fora_corrida" "$FX/docs/sprintx/features/ft-pre"
  "$real_cp" "\$@"
  rc=\$?
  rm "$FX/docs/sprintx/features/ft-pre"
  mv "$original_corrida" "$FX/docs/sprintx/features/ft-pre"
  exit "\$rc"
fi
exec "$real_cp" "\$@"
EOF
  chmod +x "$bin_corrida/cp"
  PATH="$bin_corrida:$PATH" caso_rc \
    'validar ancora leitura apesar da troca concorrente do diretorio' \
    0 pred --validar ft-pre
}

tem() { grep -qF "$2" "$1"; }
linha_de() { grep -nF "$2" "$1" | head -1 | cut -d: -f1; }

grupo_contrato() {
  echo '== contrato =='
  local sk="$RAIZ_SUITE/.claude/skills/sprintx" schema="$RAIZ_SUITE/.claude/skills/sprintx/references/00-schema.md"
  local ingestao="$RAIZ_SUITE/.claude/skills/sprintx/references/01-ingestao.md" rastro="$RAIZ_SUITE/.claude/skills/sprintx/references/08-rastro.md"
  local skill="$RAIZ_SUITE/.claude/skills/sprintx/SKILL.md" cmd="$RAIZ_SUITE/.claude/commands/sprintx-base.md" oc="$RAIZ_SUITE/.opencode/command/sprintx-base.md"
  local decisoes="$RAIZ_SUITE/.claude/skills/sprintx/DECISOES-DA-SKILL.md" readme="$RAIZ_SUITE/README.md"
  local l_leu l_reg l_val l_fim ruim

  tem "$schema" '### `00-PREDECESSORES.md` → `kind: predecessores`'
  afirma 'schema documenta kind predecessores' $? 'kind ausente do schema'
  tem "$schema" 'origem: superpowers' && tem "$schema" 'papel: especificacao' && tem "$schema" 'papel: plano'
  afirma 'schema documenta enums do predecessor' $? 'origem ou papel ausente'
  tem "$skill" '00-PREDECESSORES.md'
  afirma 'estrutura fixa inclui 00-PREDECESSORES.md' $? 'arquivo ausente da arvore da skill'

  l_leu="$(linha_de "$ingestao" 'Leia esses arquivos de verdade')"
  l_reg="$(linha_de "$ingestao" 'predecessores.sh --registrar')"
  l_val="$(linha_de "$ingestao" 'predecessores.sh --validar')"
  l_fim="$(linha_de "$ingestao" '## Ao terminar')"
  [ -n "$l_leu" ] && [ -n "$l_reg" ] && [ "$l_reg" -gt "$l_leu" ]
  afirma 'F1 registra somente depois de ler' $? "leu=$l_leu registra=$l_reg"
  [ -n "$l_val" ] && [ -n "$l_fim" ] && [ "$l_val" -lt "$l_fim" ]
  afirma 'F1 valida antes de encerrar' $? "valida=$l_val fim=$l_fim"
  tem "$ingestao" 'não faça varredura automática' || tem "$ingestao" 'não varra diretórios automaticamente'
  afirma 'F1 proibe descoberta automatica de predecessores' $? 'proibicao ausente'

  tem "$cmd" 'references/01-ingestao.md' && tem "$oc" 'references/01-ingestao.md'
  afirma 'entrypoints apontam para a mesma ingestao' $? 'entrypoint divergente'
  tem "$rastro" 'não cria evento novo' && tem "$rastro" '`commit_criado`'
  afirma 'rastro preserva vocabulario e commit_criado' $? 'contrato do rastro ausente'
  tem "$sk/scripts/predecessores.sh" 'b="$(modo_blob HEAD "$caminho")"'
  afirma 'prova le o blob atual de HEAD' $? 'prova passou a confiar no disco ou no commit declarado'

  ruim=0
  for nome in predecessor_registrado predecessor_validado predecessores_validados retomada_iniciada retomada_concluida; do
    grep -RqsF "$nome" "$sk" "$RAIZ_SUITE/.claude/commands" "$RAIZ_SUITE/.opencode/command" && ruim=1
  done
  [ "$ruim" -eq 0 ]; afirma 'nenhum evento inventado no contrato' $? 'evento fora do enum encontrado'

  ruim=0
  for ds in DS-176 DS-177 DS-178 DS-179 DS-180; do
    tem "$decisoes" "| $ds |" || ruim=1
  done
  [ "$ruim" -eq 0 ]; afirma 'decisoes DS-176 a DS-180 publicadas' $? 'decisao append-only ausente'
  tem "$readme" '00-PREDECESSORES.md' && tem "$readme" 'mutacao-predecessores.sh' \
    && tem "$readme" 'somente no repositório-fonte; não fazem parte do pacote instalado'
  afirma 'README distingue a arvore fonte do pacote instalado' $? \
    'README sugere que os scripts de CI existem no pacote instalado'
}

feature_para_checkpoint() {
  FX="$K/checkpoint-$fx_n"; fx_n=$((fx_n + 1))
  git init -q -b main "$FX"; git -C "$FX" config user.email teste@fixture.invalid; git -C "$FX" config user.name teste; git -C "$FX" config commit.gpgsign false
  mkdir -p "$FX/docs/superpowers/specs" "$FX/docs/sprintx/features/ft-pre/base"
  SPEC='docs/superpowers/specs/ft-pre-design.md'; printf 'spec\n' > "$FX/$SPEC"; git_commit 'predecessor'
  FX_SPEC_COMMIT="$(git -C "$FX" rev-parse HEAD)"; FX_SPEC_BLOB="$(git -C "$FX" rev-parse HEAD:"$SPEC")"
  git -C "$FX" switch -q -c feature/ft-pre
  MANIFESTO="$FX/docs/sprintx/features/ft-pre/00-PREDECESSORES.md"
  (cd "$FX" && bash "$PL" criar ft-pre >/dev/null)
  printf 'decisoes\n' > "$FX/docs/sprintx/features/ft-pre/00-DECISOES.md"
}

grupo_checkpoint() {
  echo '== checkpoint =='
  local plano before_plano before_stage before_rastro saida rc depois_plano depois_stage depois_rastro
  feature_para_checkpoint
  manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  sed -i 's/origem: superpowers/origem: invalida/' "$MANIFESTO"
  plano="$FX/docs/sprintx/features/ft-pre/00-PLANEJAMENTO.md"
  before_plano="$(cksum < "$plano")"; before_stage="$(git -C "$FX" diff --cached --name-status)"
  if [ -f "$FX/docs/eventos/ft-pre.jsonl" ]; then before_rastro="$(cksum < "$FX/docs/eventos/ft-pre.jsonl")"; else before_rastro=ausente; fi
  saida="$(env SPRINTX_RAIZ="$FX" bash "$PL" avanca ft-pre f2 2>&1)"; rc=$?
  depois_plano="$(cksum < "$plano")"; depois_stage="$(git -C "$FX" diff --cached --name-status)"
  if [ -f "$FX/docs/eventos/ft-pre.jsonl" ]; then depois_rastro="$(cksum < "$FX/docs/eventos/ft-pre.jsonl")"; else depois_rastro=ausente; fi
  [ "$rc" -ne 0 ] && [ "$before_plano" = "$depois_plano" ] && [ "$before_stage" = "$depois_stage" ] && [ "$before_rastro" = "$depois_rastro" ]
  afirma 'manifesto invalido impede avanca f2 sem efeitos' $? "rc=$rc saida=$saida"

  feature_para_checkpoint
  manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  caso_rc 'manifesto valido entra no checkpoint f2' 0 env SPRINTX_RAIZ="$FX" bash "$PL" avanca ft-pre f2
  git -C "$FX" cat-file -e HEAD:docs/sprintx/features/ft-pre/00-PREDECESSORES.md 2>/dev/null
  afirma 'checkpoint contem manifesto' $? '00-PREDECESSORES.md ausente do HEAD'

  feature_para_checkpoint
  manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  mv "$MANIFESTO" "$MANIFESTO.real"; ln -s "$(basename "$MANIFESTO.real")" "$MANIFESTO"
  plano="$FX/docs/sprintx/features/ft-pre/00-PLANEJAMENTO.md"
  before_plano="$(cksum < "$plano")"; before_stage="$(git -C "$FX" diff --cached --name-status)"
  if [ -f "$FX/docs/eventos/ft-pre.jsonl" ]; then before_rastro="$(cksum < "$FX/docs/eventos/ft-pre.jsonl")"; else before_rastro=ausente; fi
  saida="$(env SPRINTX_RAIZ="$FX" bash "$PL" avanca ft-pre f2 2>&1)"; rc=$?
  depois_plano="$(cksum < "$plano")"; depois_stage="$(git -C "$FX" diff --cached --name-status)"
  if [ -f "$FX/docs/eventos/ft-pre.jsonl" ]; then depois_rastro="$(cksum < "$FX/docs/eventos/ft-pre.jsonl")"; else depois_rastro=ausente; fi
  [ "$rc" -ne 0 ] && [ "$before_plano" = "$depois_plano" ] && [ "$before_stage" = "$depois_stage" ] && [ "$before_rastro" = "$depois_rastro" ]
  afirma 'manifesto symlink impede avanca f2 sem efeitos' $? "rc=$rc saida=$saida"
}

grupo_dispatcher() {
  echo '== dispatcher =='
  caso_rc 'grupo desconhecido devolve erro de uso' 64 bash "$0" grupo-inexistente
}

GRUPOS='registro caminhos estado-git historia schema contrato checkpoint dispatcher'
[ "$#" -gt 0 ] || set -- todos
for pedido in "$@"; do
  [ "$pedido" = todos ] && continue
  case " $GRUPOS " in *" $pedido "*) ;; *) uso=1; printf 'grupo desconhecido: %s\n' "$pedido" >&2; exit 64 ;; esac
done
selecionado() {
  local pedido="$1" x
  shift
  for x in "$@"; do [ "$x" = todos ] || [ "$x" = "$pedido" ] && return 0; done
  return 1
}

for grupo in $GRUPOS; do
  if selecionado "$grupo" "$@"; then
    case "$grupo" in
      registro) grupo_registro ;;
      caminhos) grupo_caminhos ;;
      estado-git) grupo_estado_git ;;
      historia) grupo_historia ;;
      schema) grupo_schema ;;
      contrato) grupo_contrato ;;
      checkpoint) grupo_checkpoint ;;
      dispatcher) grupo_dispatcher ;;
    esac
  fi
done

echo
printf '  %s ok, %s falhas\n' "$ok" "$falhou"
[ "$falhou" -eq 0 ]
