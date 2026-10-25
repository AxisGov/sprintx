#!/usr/bin/env bash
#
# Caso da secao T da bancada (limite a esquerda do prefixo de chave), carregado por `.` de
# dentro da bancada.sh: usa os auxiliares dela (t_json, T_DIR).
# Fica fora dela pela regra de tamanho de arquivo: < 5.000 linhas e < 200 KB (emenda
# AxisGov/expxdev docs/superpowers/specs/2026-10-19-limites-do-codeant-emenda.md).
#
# O prefixo de chave (sk-, gh?_, xox?-, AIza) so vale no comeco da linha ou depois de
# caractere fora de [A-Za-z0-9_-]: dentro de um identificador ("ta" + "sk-...") nao e chave.
# AKIA (e ASIA, a chave temporaria da AWS) tem limite proprio, fora de [A-Za-z0-9_]: logo
# depois de hifen ("id-" + "AKIA...") e chave; dentro de identificador ("x" ou "_" + "AKIA...") nao e.
# A chave da AWS tem tamanho fixo: seguida de [A-Za-z0-9_] ("AKIA..." + "Q") e identificador.
# Cada caso roda no hook (comum/segredo.sh) e na copia da lista em planejamento.sh, casada
# por grep -E como la. As chaves sao sinteticas e montadas por concatenacao.
# Cada caso: nome|conteudo (printf %b)|rc esperado do hook.

t_seglimite() { # t_seglimite <raiz-hooks> <planejamento.sh> — falhas em T_FALHA
  local d="$T_DIR/seglimite/r" n c e r g pad padroes=()
  local sk="sk""-ABCDEFGHIJ0123456789abcd" ant="sk""-ant-ABCDEFGHIJ0123456789ab" akia="AKIA""ABCDEFGHIJKLMNOP" asia="ASIA""ABCDEFGHIJKLMNOP"
  local gh="ghp""_ABCDEFGHIJ0123456789abcdefghij12" xox="xox""b-1234567890ab" aiza="AIza""ABCDEFGHIJ0123456789abcdefghij12345"
  local proj="sk""-proj-AbCdEf_GhIjKl-0123456789MnOpQr"
  local fgh="github_pat""_ABCDEFGHIJ0123456789abcdefghij12"
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
hifen-akia|id-$akia|2
dentro-sublinhado-akia|_$akia|0
dentro-hifen-sk|chave-$sk|0
inicio-asia|$asia|2
hifen-asia|id-$asia|2
dentro-asia|x$asia|0
cauda-akia|${akia}Q|0
cauda-asia|${asia}9z|0
cauda-sublinhado-akia|${akia}_x|0
fim-espaco-akia|$akia fim|2
fim-aspas-simples-akia|k='$akia'|2
fim-virgula-akia|[$akia,1]|2
fim-aspas-duplas-asia|k="$asia"|2
inicio-sk|$sk|2
inicio-segunda-linha-akia|x = 1\n$akia|2
espaco-akia|Bearer $akia|2
igual-ghp|GH=$gh|2
aspas-simples-xox|k='$xox'|2
aspas-duplas-aiza|k="$aiza"|2
dois-pontos-ant|chave:$ant|2
igual-github-pat|GH=$fgh|2
virgula-aiza|$aiza,|2
cauda-aiza|${aiza}X|0
identificador-e-chave|ta$sk $sk|2
projeto-openai|OPENAI_API_KEY=$proj|2
dentro-projeto-openai|ta$proj|0
EOF
  [ -z "$T_FALHA" ]
}
