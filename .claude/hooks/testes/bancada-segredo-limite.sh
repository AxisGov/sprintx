#!/usr/bin/env bash
#
# Caso da secao T da bancada (limite a esquerda do prefixo de chave), carregado por `.` de
# dentro da bancada.sh: usa os auxiliares dela (t_json, T_DIR). Mora aqui porque a bancada.sh
# passa do limite de tamanho do expx-fatiamento (F4) e nao cresce.
#
# O prefixo de chave (sk-, AKIA, gh?_, xox?-, AIza) so vale no comeco da linha ou depois de
# caractere fora de [A-Za-z0-9_-]: dentro de um identificador ("ta" + "sk-...") nao e chave.
# Cada caso roda no hook (comum/segredo.sh) e na copia da lista em planejamento.sh, casada
# por grep -E como la. As chaves sao sinteticas e montadas por concatenacao.
# Cada caso: nome|conteudo (printf %b)|rc esperado do hook.

t_seglimite() { # t_seglimite <raiz-hooks> <planejamento.sh> — falhas em T_FALHA
  local d="$T_DIR/seglimite/r" n c e r g pad padroes=()
  local sk="sk""-ABCDEFGHIJ0123456789abcd" ant="sk""-ant-ABCDEFGHIJ0123456789ab" akia="AKIA""ABCDEFGHIJKLMNOP"
  local gh="ghp""_ABCDEFGHIJ0123456789abcdefghij12" xox="xox""b-1234567890ab" aiza="AIza""ABCDEFGHIJ0123456789abcdefghij12345"
  T_FALHA=""
  while IFS= read -r pad; do [ -n "$pad" ] && padroes+=(-e "$pad"); done <<EOF
$(sed -n "/^SEGREDO_PADROES='/,/'\$/p" "$2" | sed "s/^SEGREDO_PADROES='//; s/'\$//")
EOF
  [ "${#padroes[@]}" -gt 0 ] || { T_FALHA=" sem-lista-no-planejamento"; return 1; }
  rm -rf "$d"; mkdir -p "$d/src"
  while IFS='|' read -r n c e; do
    t_json PreToolUse Write "$d" "$d/src/a.ts" "$(printf '%b' "$c")" \
      | (cd "$d" && GIT_CEILING_DIRECTORIES="$T_DIR/seglimite" bash "$1/comum/segredo.sh") >/dev/null 2>&1; r=$?
    [ "$r" = "$e" ] || T_FALHA="$T_FALHA $n=$r(esperado $e)"
    printf '%b\n' "$c" | grep -qE "${padroes[@]}"; g=$?
    [ "$g" = "$([ "$e" = 2 ] && echo 0 || echo 1)" ] || T_FALHA="$T_FALHA planejamento-$n=$g"
  done <<EOF
dentro-sk|ta$sk|0
dentro-akia|x$akia|0
dentro-ghp|abc$gh|0
dentro-xox|my$xox|0
dentro-aiza|foo$aiza|0
dentro-sublinhado-sk|_$sk|0
dentro-hifen-akia|chave-$akia|0
inicio-sk|$sk|2
inicio-segunda-linha-akia|x = 1\n$akia|2
espaco-akia|Bearer $akia|2
igual-ghp|GH=$gh|2
aspas-simples-xox|k='$xox'|2
aspas-duplas-aiza|k="$aiza"|2
dois-pontos-ant|chave:$ant|2
identificador-e-chave|ta$sk $sk|2
EOF
  [ -z "$T_FALHA" ]
}
