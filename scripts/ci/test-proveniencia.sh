#!/usr/bin/env bash
set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$raiz"

legada='((github[.]com[/:]|raw[.]githubusercontent[.]com/)bittencourtthulio/(runx|mergex|sprintx|buildx|expxdev)([.]git)?|bittencourtthulio[.]github[.]io/expxdev)'
allowlist='scripts/ci/proveniencia-allowlist.tsv'
separador=$'\x1f'
declare -A encontrados=()
declare -A esperados=()
declare -A descricoes=()

[ -f "$allowlist" ] || {
  printf 'allowlist de proveniencia ausente: %s\n' "$allowlist" >&2
  exit 1
}

registrar_ocorrencia() {
  local arquivo="$1"
  local ocorrencia="$2"
  local normalizada
  local chave

  [ -n "$ocorrencia" ] || return 0
  normalizada="$(printf '%s' "$ocorrencia" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  chave="$arquivo$separador$normalizada"
  encontrados["$chave"]=$((${encontrados["$chave"]:-0} + 1))
}

while IFS= read -r -d '' arquivo; do
  if [ -L "$arquivo" ]; then
    while IFS= read -r ocorrencia; do
      registrar_ocorrencia "$arquivo" "$ocorrencia"
    done < <(readlink -- "$arquivo" | LC_ALL=C grep -a -h -o -i -E -- "$legada" || true)
    continue
  fi
  [ -f "$arquivo" ] || continue

  # Classificacao deterministica por bytes: NUL significa binario.
  # Extensao e atributos Git nunca podem retirar um texto da varredura.
  if LC_ALL=C od -An -tx1 -v -- "$arquivo" | grep -qw '00'; then
    continue
  fi
  while IFS= read -r ocorrencia; do
    registrar_ocorrencia "$arquivo" "$ocorrencia"
  done < <(LC_ALL=C grep -a -h -o -i -E -- "$legada" "$arquivo" || true)
done < <(git ls-files -z)

numero_linha=0
while IFS=$'\t' read -r arquivo ocorrencia quantidade finalidade justificativa extra ||
  [ -n "$arquivo$ocorrencia$quantidade$finalidade$justificativa$extra" ]; do
  numero_linha=$((numero_linha + 1))
  [ -n "$arquivo$ocorrencia$quantidade$finalidade$justificativa$extra" ] || continue
  case "$arquivo" in
    \#*) continue ;;
  esac

  if [ -n "$extra" ] || [ -z "$arquivo" ] || [ -z "$ocorrencia" ] ||
    [ -z "$quantidade" ] || [ -z "$finalidade" ] || [ -z "$justificativa" ]; then
    printf 'allowlist invalida na linha %d: sao exigidos cinco campos TSV\n' "$numero_linha" >&2
    exit 1
  fi
  case "$arquivo" in
    */|*'*'*|*'?'*|*'['*|*']'*)
      printf 'allowlist exige arquivo exato, sem diretorio ou curinga: %s\n' "$arquivo" >&2
      exit 1
      ;;
  esac
  [[ "$quantidade" =~ ^[1-9][0-9]*$ ]] || {
    printf 'quantidade invalida na allowlist, linha %d: %s\n' "$numero_linha" "$quantidade" >&2
    exit 1
  }

  decodificada="${ocorrencia//%2E/.}"
  normalizada="$(printf '%s' "$decodificada" | LC_ALL=C tr '[:upper:]' '[:lower:]')"
  [ "$decodificada" = "$normalizada" ] || {
    printf 'ocorrencia da allowlist deve estar normalizada em lowercase, linha %d\n' "$numero_linha" >&2
    exit 1
  }
  printf '%s\n' "$normalizada" | grep -Eq "^$legada$" || {
    printf 'ocorrencia invalida na allowlist, linha %d: %s\n' "$numero_linha" "$ocorrencia" >&2
    exit 1
  }

  chave="$arquivo$separador$normalizada"
  [ -z "${esperados[$chave]+definido}" ] || {
    printf 'excecao duplicada na allowlist para %s: %s\n' "$arquivo" "$normalizada" >&2
    exit 1
  }
  esperados["$chave"]="$quantidade"
  descricoes["$chave"]="$finalidade  -  $justificativa"
done < "$allowlist"

violacoes=0
for chave in "${!encontrados[@]}"; do
  arquivo="${chave%%"$separador"*}"
  ocorrencia="${chave#*"$separador"}"
  quantidade="${encontrados[$chave]}"
  if [ -z "${esperados[$chave]+definido}" ]; then
    printf 'origem legada nao autorizada: %s | %s | ocorrencias=%s\n' \
      "$arquivo" "$ocorrencia" "$quantidade" >&2
    violacoes=1
  elif [ "$quantidade" -ne "${esperados[$chave]}" ]; then
    printf 'contagem divergente: %s | %s | esperado=%s encontrado=%s | %s\n' \
      "$arquivo" "$ocorrencia" "${esperados[$chave]}" "$quantidade" \
      "${descricoes[$chave]}" >&2
    violacoes=1
  fi
done
for chave in "${!esperados[@]}"; do
  if [ "${encontrados[$chave]:-0}" -ne "${esperados[$chave]}" ]; then
    arquivo="${chave%%"$separador"*}"
    ocorrencia="${chave#*"$separador"}"
    printf 'excecao ausente ou alterada: %s | %s | esperado=%s encontrado=%s | %s\n' \
      "$arquivo" "$ocorrencia" "${esperados[$chave]}" \
      "${encontrados[$chave]:-0}" "${descricoes[$chave]}" >&2
    violacoes=1
  fi
done
[ "$violacoes" -eq 0 ] || exit 1

if [ -f src/nucleo/catalogo.ts ]; then
  for repo in runx mergex sprintx buildx; do
    grep -q "https://github.com/AxisGov/$repo" src/nucleo/catalogo.ts || {
      printf 'catalogo sem origem canonica AxisGov/%s\n' "$repo" >&2
      exit 1
    }
  done
  grep -q 'https://github.com/AxisGov/expxdev' package.json
else
  for repo in runx mergex sprintx buildx expxdev; do
    grep -q "https://github.com/AxisGov/$repo" README.md || {
      printf 'README sem origem canonica AxisGov/%s\n' "$repo" >&2
      exit 1
    }
  done
fi

workflow='.github/workflows/proveniencia.yml'
if [ ! -f "$workflow" ]; then
  workflow='.github/workflows/ci.yml'
fi
grep -q '^  pull_request:$' "$workflow"
! grep -q '^[[:space:]]*paths:' "$workflow" || {
  printf 'workflow de proveniencia nao pode limitar caminhos de pull request\n' >&2
  exit 1
}

printf 'proveniencia AxisGov verificada\n'
