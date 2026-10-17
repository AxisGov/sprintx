#!/usr/bin/env bash
#
# Caso da secao A da bancada (F1, base informada pelo caller), carregado por `.` de dentro
# da bancada.sh: usa os auxiliares dela (afirma, WORKDIR). Mora aqui porque a bancada.sh
# passa do limite de tamanho do expx-fatiamento (F4) e nao cresce.
#
# Roda, num repositorio real, o bloco `sh` que o item 2 de references/01-ingestao.md manda
# a F1 executar para criar a branch e gravar a base (o unico bloco do arquivo que cita
# expxBaseNascimento). A pergunta e se a branch nasceu da linha da base, nao se contem a
# ponta atual dela.

bx_bloco() { # bloco do contrato, sem a indentacao da lista
  awk '/^ *```sh$/ { b = ""; dentro = 1; next }
       /^ *```$/ && dentro { if (b ~ /expxBaseNascimento/) { printf "%s", b; achou = 1 } dentro = 0; next }
       dentro { sub(/^   /, ""); b = b $0 "\n" }
       END { exit achou ? 0 : 1 }' "$1"
}
bx_f1() { # bx_f1 <slug> <base> — o bloco com os marcadores trocados, da raiz; rc do bloco
  local s
  s="$(BX_S="$1" BX_B="$2" awk '{ gsub(/<slug>/, ENVIRON["BX_S"]); gsub(/<base>/, ENVIRON["BX_B"]); gsub(/<repo>/, "r"); print }' <<<"$BX_BLOCO")"
  (cd "$BX_R" && bash -c "$s") >/dev/null 2>&1
}
bx_git() { git -C "$BX_R" -c user.email=bancada@sprintx -c user.name=bancada "$@" >/dev/null 2>&1; }
bx_commit() { bx_git checkout -q "$1" && bx_git commit -q --allow-empty -m "$2"; }
bx_nasceu() { # a chave de nascimento e o commit de onde a branch saiu (a ponta, sem commit proprio)
  [ "$(git -C "$BX_R" config "branch.feature/$1.expxBaseNascimento")" = "$(git -C "$BX_R" rev-parse "feature/$1")" ]
}

t_base_encadeada() { # t_base_encadeada <01-ingestao.md> — falhas em BX_FALHA
  BX_FALHA=""
  BX_BLOCO="$(bx_bloco "$1")" || { BX_FALHA=" sem-bloco-sh-com-expxBaseNascimento"; return 1; }
  rm -rf "$WORKDIR/base-encadeada"; BX_R="$WORKDIR/base-encadeada/r"; mkdir -p "$BX_R"
  bx_git init -q -b main && bx_git commit -q --allow-empty -m m0 \
    && bx_git checkout -q -b feature/pred && bx_git commit -q --allow-empty -m p1 || { BX_FALHA=" fixture"; return 1; }
  # Criacao pelo bloco: worktree novo, base e nascimento gravados.
  local f
  for f in avanca update reescrita; do
    bx_f1 "$f" feature/pred && bx_nasceu "$f" && [ -d "$WORKDIR/base-encadeada/r--$f" ] || BX_FALHA="$BX_FALHA criacao-$f"
  done
  # 0. A base avanca no meio da criacao (post-checkout do worktree add): o nascimento e o
  #    commit de onde a branch saiu, e a retomada seguinte aceita.
  printf '%s\n' '#!/bin/sh' '[ -f "$BX_CORRIDA" ] && exit 0; : > "$BX_CORRIDA"' \
    'c=$(git commit-tree "feature/pred^{tree}" -p feature/pred -m corrida) && git update-ref refs/heads/feature/pred "$c"' \
    > "$BX_R/.git/hooks/post-checkout"; chmod +x "$BX_R/.git/hooks/post-checkout"
  local p0; p0="$(git -C "$BX_R" rev-parse feature/pred)"
  BX_CORRIDA="$WORKDIR/base-encadeada/corrida" GIT_AUTHOR_NAME=b GIT_AUTHOR_EMAIL=b@b GIT_COMMITTER_NAME=b GIT_COMMITTER_EMAIL=b@b \
    bx_f1 corrida feature/pred && bx_nasceu corrida || BX_FALHA="$BX_FALHA corrida-na-criacao"
  rm -f "$BX_R/.git/hooks/post-checkout"
  [ "$(git -C "$BX_R" rev-parse feature/pred)" != "$p0" ] || BX_FALHA="$BX_FALHA corrida-nao-ocorreu"
  bx_f1 corrida feature/pred || BX_FALHA="$BX_FALHA corrida-retomada-recusada"
  # 1. A base avancou depois do nascimento: aceita.
  bx_commit feature/pred p2
  bx_f1 avanca feature/pred || BX_FALHA="$BX_FALHA base-avancou-recusada"
  # 2. A predecessora recebeu "update branch" (merge da main): aceita.
  bx_commit main m1 && bx_git checkout -q feature/pred && bx_git merge -q --no-ff -m upd main
  bx_f1 update feature/pred || BX_FALHA="$BX_FALHA update-branch-recusado"
  # 3. Nasceu da main e o caller informa a predecessora: para, sem gravar a chave.
  bx_git branch feature/outra main~1
  bx_f1 outra feature/pred && BX_FALHA="$BX_FALHA outra-base-aceita"
  [ -z "$(git -C "$BX_R" config branch.feature/outra.expxBase)" ] || BX_FALHA="$BX_FALHA outra-base-gravou-chave"
  # 4. Nascimento gravado para OUTRA base (main) nao vale para a predecessora: para.
  bx_f1 trocada main || BX_FALHA="$BX_FALHA criacao-trocada"
  bx_f1 trocada feature/pred && BX_FALHA="$BX_FALHA nascimento-de-outra-base-aceito"
  # 6. Sem nascimento, nasceu de X (derivada da base, com commit proprio) e contem a ponta
  #    atual da base: o PR levaria o commit de X. Para, sem gravar a chave.
  bx_git branch feature/x feature/pred && bx_commit feature/x x1 && bx_git branch feature/dex feature/x \
    && bx_commit feature/dex d1 || BX_FALHA="$BX_FALHA fixture-dex"
  bx_f1 dex feature/pred && BX_FALHA="$BX_FALHA derivada-de-outra-branch-aceita"
  [ -z "$(git -C "$BX_R" config branch.feature/dex.expxBase)" ] || BX_FALHA="$BX_FALHA derivada-gravou-chave"
  # 7. A feature recebeu "update branch" (merge da base): aceita, com e sem nascimento gravado;
  #    sem ele, o nascimento gravado e o ponto de onde a branch saiu, nao a ponta atual.
  bx_commit feature/pred p3 && git -C "$WORKDIR/base-encadeada/r--avanca" -c user.email=b@b -c user.name=b \
    merge -q --no-ff -m upd feature/pred >/dev/null 2>&1 || BX_FALHA="$BX_FALHA fixture-update-na-feature"
  bx_f1 avanca feature/pred || BX_FALHA="$BX_FALHA update-na-feature-recusado"
  bx_git branch feature/leg feature/pred && bx_commit feature/leg l1 && bx_commit feature/pred p4 \
    && bx_git checkout -q feature/leg && bx_git merge -q --no-ff -m upd feature/pred || BX_FALHA="$BX_FALHA fixture-leg"
  bx_f1 leg feature/pred || BX_FALHA="$BX_FALHA legado-com-update-recusado"
  [ "$(git -C "$BX_R" config branch.feature/leg.expxBaseNascimento)" = "$(git -C "$BX_R" rev-parse feature/pred~1)" ] \
    || BX_FALHA="$BX_FALHA legado-nascimento-nao-e-o-ponto-de-saida"
  # 5. A predecessora foi reescrita (sem o nascimento na historia): para.
  bx_git checkout -q main && bx_git branch -f feature/pred main && bx_commit feature/pred p1-novo
  bx_f1 reescrita feature/pred && BX_FALHA="$BX_FALHA base-reescrita-aceita"
  # 8. Tag com o mesmo nome da base (e da feature), fora da linha dela: a ref sem qualificar
  #    escolhe a tag. A branch nasce da ponta da branch base, e a retomada a aceita.
  local t; t="$(git -C "$BX_R" -c user.email=b@b -c user.name=b commit-tree "feature/pred^{tree}" -m tag)" \
    && bx_git tag feature/pred "$t" && bx_git tag feature/tag "$t" || BX_FALHA="$BX_FALHA fixture-tag"
  bx_f1 tag feature/pred || BX_FALHA="$BX_FALHA tag-criacao-recusada"
  [ "$(git -C "$BX_R" rev-parse refs/heads/feature/tag)" = "$(git -C "$BX_R" rev-parse refs/heads/feature/pred)" ] \
    && [ "$(git -C "$BX_R" config branch.feature/tag.expxBaseNascimento)" = "$(git -C "$BX_R" rev-parse refs/heads/feature/pred)" ] \
    || BX_FALHA="$BX_FALHA tag-escolhida-no-lugar-da-base"
  bx_f1 tag feature/pred || BX_FALHA="$BX_FALHA tag-retomada-recusada"
  [ -z "$BX_FALHA" ]
}
