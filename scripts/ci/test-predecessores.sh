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
  git init -q -b main "$FX"
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
  ln -s ft-pre-design.md "$FX/docs/superpowers/specs/ft-pre-link.md"
  printf 'evidencia interna\n' > "$FX/docs/sprintx/features/ft-pre/evidencia.md"
  printf 'entrega\n' > "$FX/docs/entregas/ft-pre/PR.md"
  git init -q -b main "$FX/docs/superpowers/gitlink"
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
  invalido_preserva 'recusa glob asterisco' especificacao 'docs/superpowers/specs/*.md'
  invalido_preserva 'recusa glob interrogacao' especificacao 'docs/superpowers/specs/ft-pre?.md'
  invalido_preserva 'recusa glob colchete' especificacao 'docs/superpowers/specs/[f]t-pre.md'
  invalido_preserva 'recusa propria feature' especificacao 'docs/sprintx/features/ft-pre/evidencia.md'
  invalido_preserva 'recusa propria entrega' especificacao 'docs/entregas/ft-pre/PR.md'
}

grupo_estado_git() {
  echo '== estado-git =='
  nova_fixture; printf 'novo\n' > "$FX/docs/superpowers/specs/untracked.md"; caso_falha 'recusa untracked' registra especificacao 'docs/superpowers/specs/untracked.md'
  nova_fixture; printf 'mudou\n' >> "$FX/$SPEC"; git -C "$FX" add "$SPEC"; caso_falha 'recusa staged' registra especificacao "$SPEC"
  nova_fixture; printf 'mudou\n' >> "$FX/$SPEC"; caso_falha 'recusa modificado' registra especificacao "$SPEC"
  nova_fixture; rm "$FX/$SPEC"; caso_falha 'recusa removido' registra especificacao "$SPEC"
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
}

schema_invalido() { # schema_invalido <nome> <tipo>
  local nome="$1" tipo="$2" corpo
  nova_fixture
  case "$tipo" in
    lista-vazia) corpo='predecessores: []' ;;
    origem) corpo="predecessores:\n  - caminho: $SPEC\n    origem: outra\n    papel: especificacao\n    commit_sha: $FX_SPEC_COMMIT\n    blob_oid: $FX_SPEC_BLOB" ;;
    papel) corpo="predecessores:\n  - caminho: $SPEC\n    origem: superpowers\n    papel: desenho\n    commit_sha: $FX_SPEC_COMMIT\n    blob_oid: $FX_SPEC_BLOB" ;;
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

  nova_fixture; manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  sed -i "/trabalho_id:/a trabalho_id: ft-pre" "$MANIFESTO"
  caso_falha 'recusa chave repetida' pred --validar ft-pre

  nova_fixture; manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  sed -i "/blob_oid:/a\\    caminho: $SPEC\n    origem: superpowers\n    papel: especificacao\n    commit_sha: $FX_SPEC_COMMIT\n    blob_oid: $FX_SPEC_BLOB" "$MANIFESTO"
  caso_falha 'recusa caminho duplicado' pred --validar ft-pre

  schema_invalido 'recusa scalar malformado' scalar
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
  feature_para_checkpoint
  manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  sed -i 's/origem: superpowers/origem: invalida/' "$MANIFESTO"
  caso_falha 'manifesto invalido impede avanca f2' env SPRINTX_RAIZ="$FX" bash "$PL" avanca ft-pre f2

  feature_para_checkpoint
  manifesto_valido "$SPEC" especificacao "$FX_SPEC_COMMIT" "$FX_SPEC_BLOB"
  caso_rc 'manifesto valido entra no checkpoint f2' 0 env SPRINTX_RAIZ="$FX" bash "$PL" avanca ft-pre f2
  git -C "$FX" cat-file -e HEAD:docs/sprintx/features/ft-pre/00-PREDECESSORES.md 2>/dev/null
  afirma 'checkpoint contem manifesto' $? '00-PREDECESSORES.md ausente do HEAD'
}

GRUPOS='registro caminhos estado-git historia schema checkpoint'
[ "$#" -gt 0 ] || set -- todos
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
      checkpoint) grupo_checkpoint ;;
    esac
  fi
done

echo
printf '  %s ok, %s falhas\n' "$ok" "$falhou"
[ "$falhou" -eq 0 ]
