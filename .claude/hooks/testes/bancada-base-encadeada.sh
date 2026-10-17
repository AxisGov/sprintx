#!/usr/bin/env bash
#
# Caso da secao A da bancada (F1, base informada pelo caller), carregado por `.` de dentro
# da bancada.sh: usa os auxiliares dela (afirma, WORKDIR). Mora aqui porque a bancada.sh
# passa do limite de tamanho do expx-fatiamento (F4) e nao cresce.
#
# Roda, num repositorio real, o bloco `sh` que o item 2 de references/01-ingestao.md manda
# a F1 executar para gravar a base (o unico bloco do arquivo que cita expxBaseNascimento).
# A pergunta e se a branch nasceu da linha da base, nao se contem a ponta atual dela.

bx_bloco() { # bloco do contrato, sem a indentacao da lista
  awk '/^ *```sh$/ { b = ""; dentro = 1; next }
       /^ *```$/ && dentro { if (b ~ /expxBaseNascimento/) { printf "%s", b; achou = 1 } dentro = 0; next }
       dentro { sub(/^   /, ""); b = b $0 "\n" }
       END { exit achou ? 0 : 1 }' "$1"
}
bx_f1() { # bx_f1 <repo> <slug> <base> — o bloco com os marcadores trocados; rc do bloco
  local s
  s="$(BX_S="$2" BX_B="$3" awk '{ gsub(/<slug>/, ENVIRON["BX_S"]); gsub(/<base>/, ENVIRON["BX_B"]); print }' <<<"$BX_BLOCO")"
  (cd "$1" && bash -c "$s") >/dev/null 2>&1
}
bx_git() { git -C "$BX_R" -c user.email=bancada@sprintx -c user.name=bancada "$@" >/dev/null 2>&1; }
bx_commit() { bx_git checkout -q "$1" && bx_git commit -q --allow-empty -m "$2"; }

t_base_encadeada() { # t_base_encadeada <01-ingestao.md> — falhas em BX_FALHA
  BX_FALHA=""
  BX_BLOCO="$(bx_bloco "$1")" || { BX_FALHA=" sem-bloco-sh-com-expxBaseNascimento"; return 1; }
  BX_R="$WORKDIR/base-encadeada"; rm -rf "$BX_R"; mkdir -p "$BX_R"
  bx_git init -q -b main && bx_git commit -q --allow-empty -m m0 \
    && bx_git checkout -q -b feature/pred && bx_git commit -q --allow-empty -m p1 || { BX_FALHA=" fixture"; return 1; }
  # Nascidas na F1 (criacao): o bloco grava a base e o nascimento.
  local f
  for f in avanca update reescrita; do
    bx_git branch "feature/$f" feature/pred && bx_f1 "$BX_R" "$f" feature/pred || BX_FALHA="$BX_FALHA criacao-$f"
  done
  # 1. A base avancou depois do nascimento: aceita.
  bx_commit feature/pred p2
  bx_f1 "$BX_R" avanca feature/pred || BX_FALHA="$BX_FALHA base-avancou-recusada"
  # 2. A predecessora recebeu "update branch" (merge da main): aceita.
  bx_commit main m1 && bx_git checkout -q feature/pred && bx_git merge -q --no-ff -m upd main
  bx_f1 "$BX_R" update feature/pred || BX_FALHA="$BX_FALHA update-branch-recusado"
  # 3. Nasceu da main e o caller informa a predecessora: para, sem gravar a chave.
  bx_git branch feature/outra main~1
  bx_f1 "$BX_R" outra feature/pred && BX_FALHA="$BX_FALHA outra-base-aceita"
  [ -z "$(git -C "$BX_R" config branch.feature/outra.expxBase)" ] || BX_FALHA="$BX_FALHA outra-base-gravou-chave"
  # 4. Nascimento gravado para OUTRA base (main) nao vale para a predecessora: para.
  bx_git branch feature/trocada main && bx_f1 "$BX_R" trocada main || BX_FALHA="$BX_FALHA criacao-trocada"
  bx_f1 "$BX_R" trocada feature/pred && BX_FALHA="$BX_FALHA nascimento-de-outra-base-aceito"
  # 5. A predecessora foi reescrita (sem o nascimento na historia): para.
  bx_git checkout -q main && bx_git branch -f feature/pred main && bx_commit feature/pred p1-novo
  bx_f1 "$BX_R" reescrita feature/pred && BX_FALHA="$BX_FALHA base-reescrita-aceita"
  [ -z "$BX_FALHA" ]
}
