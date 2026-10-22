#!/usr/bin/env bash
set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
guard="$raiz/scripts/ci/test-proveniencia.sh"
temporario="$(mktemp -d)"
trap 'rm -rf "$temporario"' EXIT

github_host='github.com'
raw_host='raw.githubusercontent.com'
proprietario='bittencourtthulio'
base="$temporario/base"

mkdir -p "$base/scripts/ci" "$base/.github/workflows"
git -C "$base" init -q
cp "$guard" "$base/scripts/ci/test-proveniencia.sh"
printf '%s\n' \
  '# arquivo<TAB>ocorrencia normalizada (%2E representa ponto)<TAB>quantidade<TAB>finalidade<TAB>justificativa' \
  > "$base/scripts/ci/proveniencia-allowlist.tsv"
printf '%s\n' \
  "https://$github_host/AxisGov/runx" \
  "https://$github_host/AxisGov/mergex" \
  "https://$github_host/AxisGov/sprintx" \
  "https://$github_host/AxisGov/buildx" \
  "https://$github_host/AxisGov/expxdev" \
  > "$base/README.md"
printf '%s\n' \
  'name: fixture' \
  'on:' \
  '  pull_request:' \
  'jobs: {}' \
  > "$base/.github/workflows/proveniencia.yml"
git -C "$base" add .
git -C "$base" -c user.name=Fixture -c user.email=fixture@example.invalid \
  commit -qm 'fixture: guard sob teste'

nova_fixture() {
  local nome="$1"
  local destino="$temporario/$nome"
  git clone -q --no-hardlinks "$base" "$destino"
  printf '%s\n' "$destino"
}

rastrear_texto() {
  local repo="$1"
  local caminho="$2"
  local conteudo="$3"
  mkdir -p "$(dirname "$repo/$caminho")"
  printf '%s\n' "$conteudo" > "$repo/$caminho"
  git -C "$repo" add -- "$caminho"
  git -C "$repo" -c user.name=Fixture -c user.email=fixture@example.invalid \
    commit -qm "fixture: $caminho"
}

adicionar_excecao() {
  local repo="$1"
  local caminho="$2"
  local ocorrencia="$3"
  local finalidade="$4"
  local justificativa="$5"
  printf '%s\t%s\t1\t%s\t%s\n' \
    "$caminho" "$ocorrencia" "$finalidade" "$justificativa" \
    >> "$repo/scripts/ci/proveniencia-allowlist.tsv"
  git -C "$repo" add scripts/ci/proveniencia-allowlist.tsv
  git -C "$repo" -c user.name=Fixture -c user.email=fixture@example.invalid \
    commit -qm "fixture: autoriza $caminho"
}

esperar_falha() {
  local nome="$1"
  local repo="$2"
  if bash "$repo/scripts/ci/test-proveniencia.sh" >"$temporario/$nome.out" 2>&1; then
    printf 'FALHA: guard aceitou violacao %s\n' "$nome" >&2
    sed -n '1,80p' "$temporario/$nome.out" >&2
    exit 1
  fi
}

esperar_sucesso() {
  local nome="$1"
  local repo="$2"
  if ! bash "$repo/scripts/ci/test-proveniencia.sh" >"$temporario/$nome.out" 2>&1; then
    printf 'FALHA: guard rejeitou caso permitido %s\n' "$nome" >&2
    sed -n '1,120p' "$temporario/$nome.out" >&2
    exit 1
  fi
}

caso_bloqueado() {
  local nome="$1"
  local caminho="$2"
  local conteudo="$3"
  local repo
  repo="$(nova_fixture "$nome")"
  rastrear_texto "$repo" "$caminho" "$conteudo"
  esperar_falha "$nome" "$repo"
}

caso_bloqueado https_mixed bootstrap.sh \
  "https://$github_host/BittencourtThulio/RunX.git"
caso_bloqueado ssh_scp_like bootstrap.sh \
  "git@$github_host:BittencourtThulio/MergeX.git"
caso_bloqueado git_protocol bootstrap.sh \
  "git://$github_host/BITTENCOURTTHULIO/sprintx.git"
caso_bloqueado raw_mixed bootstrap.sh \
  "https://$raw_host/BittencourtThulio/buildx/main/SKILL.md"
caso_bloqueado http_without_dot_git bootstrap.sh \
  "http://$github_host/$proprietario/runx"
caso_bloqueado ssh_scheme bootstrap.sh \
  "ssh://git@$github_host/$proprietario/mergex.git"
caso_bloqueado bootstrap_tracked bootstrap.sh \
  "git clone https://$github_host/$proprietario/runx.git"
caso_bloqueado gitmodules_tracked .gitmodules \
  "[submodule \"legado\"] path = legado url = git@$github_host:$proprietario/mergex.git"
caso_bloqueado workflow_new '.github/workflows/novo-legado.yml' \
  "# clone: https://$github_host/$proprietario/sprintx.git"
caso_bloqueado filename_spaces 'docs/instalador legado.md' \
  "git clone https://$github_host/$proprietario/buildx.git"
caso_bloqueado arbitrary_case bootstrap.sh \
  "https://$github_host/BiTtEnCoUrTtHuLiO/BuIlDx"

repo_atributo="$(nova_fixture atributo_binary)"
rastrear_texto "$repo_atributo" bootstrap.sh \
  "https://$github_host/$proprietario/runx.git"
rastrear_texto "$repo_atributo" .gitattributes 'bootstrap.sh binary'
esperar_falha atributo_binary "$repo_atributo"

repo_nul_operacional="$(nova_fixture nul_operacional)"
{
  printf '#!/usr/bin/env bash\n'
  printf '\000git clone https://%s/%s/runx.git\n' "$github_host" "$proprietario"
} > "$repo_nul_operacional/bootstrap.sh"
git -C "$repo_nul_operacional" add bootstrap.sh
git -C "$repo_nul_operacional" -c user.name=Fixture -c user.email=fixture@example.invalid \
  commit -qm 'fixture: script operacional com NUL'
esperar_falha nul_operacional "$repo_nul_operacional"

repo_nul_sem_shebang="$(nova_fixture nul_sem_shebang)"
{
  contador=0
  while [ "$contador" -lt 32 ]; do
    printf '\000\001\002\003\004\005\006\007'
    contador=$((contador + 1))
  done
  printf 'git clone https://%s/%s/runx.git\n' "$github_host" "$proprietario"
} > "$repo_nul_sem_shebang/bootstrap.sh"
git -C "$repo_nul_sem_shebang" add bootstrap.sh
git -C "$repo_nul_sem_shebang" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm 'fixture: texto operacional ofuscado por NUL'
esperar_falha nul_sem_shebang "$repo_nul_sem_shebang"

repo_extra="$(nova_fixture extra_allowlisted)"
rastrear_texto "$repo_extra" docs/historico-proveniencia.md \
  "https://$github_host/$proprietario/runx https://$github_host/$proprietario/runx"
adicionar_excecao "$repo_extra" docs/historico-proveniencia.md \
  'github%2Ecom/bittencourtthulio/runx' \
  'documentacao historica' \
  'preserva uma unica origem observada para auditoria de migracao'
esperar_falha extra_allowlisted "$repo_extra"

for tipo in migracao fixture historico; do
  repo_permitido="$(nova_fixture "permitido_$tipo")"
  case "$tipo" in
    migracao) caminho='migrations/origem-legada.txt' ;;
    fixture) caminho='fixtures/migracao/origem-legada.txt' ;;
    historico) caminho='docs/historico-proveniencia.md' ;;
  esac
  rastrear_texto "$repo_permitido" "$caminho" \
    "https://$github_host/$proprietario/runx"
  adicionar_excecao "$repo_permitido" "$caminho" \
    'github%2Ecom/bittencourtthulio/runx' \
    "$tipo de proveniencia" \
    'ocorrencia exata necessaria para provar reconhecimento e migracao'
  esperar_sucesso "permitido_$tipo" "$repo_permitido"
done

repo_axisgov="$(nova_fixture axisgov)"
rastrear_texto "$repo_axisgov" bootstrap.sh \
  "git clone https://$github_host/AxisGov/runx.git"
esperar_sucesso axisgov "$repo_axisgov"

repo_binario="$(nova_fixture binario)"
printf '\211PNG\r\n\032\n' > "$repo_binario/asset.bin"
contador=0
while [ "$contador" -lt 32 ]; do
  printf '\000\001\002\003\004\005\006\007' >> "$repo_binario/asset.bin"
  contador=$((contador + 1))
done
printf 'https://%s/AxisGov/runx.git\000' "$github_host" \
  >> "$repo_binario/asset.bin"
git -C "$repo_binario" add asset.bin
git -C "$repo_binario" -c user.name=Fixture -c user.email=fixture@example.invalid \
  commit -qm 'fixture: binario'
esperar_sucesso binario "$repo_binario"

repo_nao_rastreado="$(nova_fixture nao_rastreado)"
printf '%s\n' "https://$github_host/$proprietario/runx.git" \
  > "$repo_nao_rastreado/nao-rastreado.txt"
esperar_sucesso nao_rastreado "$repo_nao_rastreado"

printf 'contrato de proveniencia verificado\n'
