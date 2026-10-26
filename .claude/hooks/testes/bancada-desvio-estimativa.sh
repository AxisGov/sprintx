#!/usr/bin/env bash
#
# Secoes AB a AF da bancada: desvio, calibracao persistida e estimativa por tipo_task.
# Carregada por `.` de dentro da bancada.sh, no mesmo ponto e na mesma ordem: usa os
# auxiliares e o estado dela. Mora aqui porque o CodeAnt pula arquivo acima de 5.000 linhas
# ou 200 KB (expxdev, docs/superpowers/specs/2026-10-19-limites-do-codeant-emenda.md).

echo "== AB. \`desvio_task\` nomeava duas grandezas incompativeis; os dois simbolos sao canonicos (D-11) =="
# A D-09 fixou o AGREGADOR do numero que calibra e a D-10 a sua PRECISAO. O NOME continuava
# ambiguo, e no MESMO arquivo: na 07-estimativa.md, `desvio_task` era
#   Passo 5  (linha 139 em f917fe0): (p - o) / 6                 — desvio-padrao PERT, em HORAS,
#                                                                  dispersao de uma estimativa;
#   Passo 10 (linha 295 em f917fe0): real / media_task_estimada  — razao de calibracao,
#                                                                  ADIMENSIONAL, quanto o real
#                                                                  excedeu o estimado.
# 06-execucao.md, TEMPLATE-HISTORICO.md, 00-schema.md e 08-rastro.md usavam o nome na segunda
# acepcao; TEMPLATE-ESTIMATIVA.md na primeira. A consequencia e em hora cobrada: quem le "o fator
# multiplica `media_task` e `desvio_task`" (Passo 1) e procura o simbolo encontra as duas
# definicoes, e somar em quadratura a razao de calibracao em vez do desvio-padrao publica 9-14 h
# onde o canonico publica 10-14 h.
# Canonico (DS-162): `desvio_padrao_task` SO para (p - o) / 6; `desvio_calibracao_task` SO para
# real / estimado_media. As chaves persistidas nao mudam: `desvio` e `desvio_medio` (D-10).
# O REGISTRO e append-only ("nada acima e revisto", declarado em cada secao D do arquivo): DS-37,
# DS-40, DS-160 e DS-161 seguem como nasceram — a DS-37 e a DS-160 com `desvio_task`, a DS-40 com
# `desvio` sem sufixo —, e e a DS-162 que declara o mapeamento para o par canonico. Por
# isso os casos de colisao varrem a arvore VIVA do contrato — referencias e assets —, nunca o
# registro; o registro responde pelos seus proprios casos.
AB_PERT_RE='\(p[[:space:]]*-[[:space:]]*o\)[[:space:]]*/[[:space:]]*6'
AB_CAL_RE='real[[:space:]]*/[[:space:]]*(estimado_media|media_task_estimada)'
# Pontos que LIGAM cada simbolo a sua formula, os que o NOMEIAM, e a arvore viva inteira.
AB_REL_PERT="references/07-estimativa.md assets/TEMPLATE-ESTIMATIVA.md"
AB_REL_CAL="references/07-estimativa.md references/06-execucao.md assets/TEMPLATE-HISTORICO.md"
AB_REL_NOMEIA_CAL="$AB_REL_CAL references/00-schema.md references/08-rastro.md"
AB_REL_VIVOS="references/00-schema.md references/06-execucao.md references/07-estimativa.md
references/08-rastro.md assets/TEMPLATE-ESTIMATIVA.md assets/TEMPLATE-HISTORICO.md"

# Os detectores leem o texto SEM marcacao: `**antes**` e `antes` sao a mesma regra (mesma
# disciplina da secao Z). E contam linhas (`-c`) em vez de abortar na primeira (`-q`): depois de
# um pipe, `grep -q` fecha a entrada no primeiro casamento, o `tr` a montante leva SIGPIPE e, com
# `pipefail` ligado (linha 9), o pipeline devolve status nao-zero mesmo tendo casado.
ab_txt() { tr -d '*`' < "$1"; }
ab_conta() { ab_txt "$1" | grep -ciE "$2"; }
ab_tem_re() { [ "$(ab_conta "$1" "$2")" -gt 0 ]; }

# ab_lig <arquivo> <regex-da-formula> -> os simbolos ligados AQUELA formula, um por linha.
# A ligacao e `<simbolo> = <...formula...>`, em bloco de codigo ou inline numa celula de tabela.
# `[^=|]{0,40}` aceita o prefixo `arredonda( ` e nao cruza outro `=` nem separador de celula, para
# nao colar o simbolo de uma ligacao na formula da ligacao seguinte da mesma linha.
ab_lig() {
  ab_txt "$1" \
    | grep -ohE "(desvio|media|variancia)[a-z_]*[[:space:]]*=[[:space:]]*[^=|]{0,40}($2)" \
    | sed 's/[[:space:]]*=.*//' | sort -u
}
ab_simbolos() { # ab_simbolos <dir> <regex> -> simbolos daquela formula na arvore viva inteira
  local d="$1" re="$2" f
  for f in $AB_REL_VIVOS; do [ -f "$d/$f" ] && ab_lig "$d/$f" "$re"; done | sort -u
}

# O caso e por ARVORE, nao por caminho fixo: a bateria real roda em "$SK" e cada mutante roda a
# MESMA bateria numa copia, sem nunca tocar as referencias reais.
ab_caso() { # ab_caso <caso> <dir> -> 0 se o caso PASSA naquela arvore
  local c="$1" d="$2" f sujo="" v
  case "$c" in
    # O simbolo colidente nao existe mais em ponto nenhum da arvore viva. E o detector direto da
    # D-11: enquanto `desvio_task` existir ali, as duas definicoes continuam alcancaveis pelo
    # mesmo nome. Busca literal — nem `desvio_padrao_task` nem `desvio_calibracao_task` o contem.
    ab_sem_simbolo_colidente)
      for f in $AB_REL_VIVOS; do
        [ -f "$d/$f" ] && grep -qF 'desvio_task' "$d/$f" && sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    # Nenhum simbolo esta ligado as DUAS formulas. E a colisao medida, e vale para QUALQUER nome:
    # trocar o par canonico por outro par disjunto nao reabre o defeito; usar um nome para as duas
    # grandezas reabre. Interseccao vazia e a regra. Cada lista ja vem unica, logo o que aparece
    # duas vezes na concatenacao e exatamente a interseccao.
    ab_sem_intersecao)
      v="$({ ab_simbolos "$d" "$AB_PERT_RE"; ab_simbolos "$d" "$AB_CAL_RE"; } \
            | sort | uniq -d | tr '\n' ' ')"
      [ -z "$v" ] ;;
    # Cada formula esta ligada a EXATAMENTE um simbolo, e e o canonico.
    ab_pert_canonica)
      for f in $AB_REL_PERT; do
        [ "$(ab_lig "$d/$f" "$AB_PERT_RE" | tr '\n' ' ' | sed 's/ $//')" = "desvio_padrao_task" ] \
          || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    ab_cal_canonica)
      for f in $AB_REL_CAL; do
        [ "$(ab_lig "$d/$f" "$AB_CAL_RE" | tr '\n' ' ' | sed 's/ $//')" = "desvio_calibracao_task" ] \
          || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    # Cada ponto de ENTRADA marca a fronteira contra a outra grandeza. Regra que existe so onde as
    # duas se encontram e regra que a sessao seguinte nao encontra: ela chega pelo arquivo da
    # calibracao, ou pelo da estimativa, e nunca le o outro.
    ab_fronteira_pert)
      for f in $AB_REL_PERT; do
        ab_tem_re "$d/$f" 'desvio_padrao_task' \
          && ab_tem_re "$d/$f" 'nunca o desvio_calibracao_task|n[ãa]o (é|e) o desvio_calibracao_task' \
          || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    ab_fronteira_cal)
      for f in $AB_REL_NOMEIA_CAL; do
        ab_tem_re "$d/$f" 'desvio_calibracao_task' \
          && ab_tem_re "$d/$f" 'nunca o desvio_padrao_task|n[ãa]o (é|e) o desvio_padrao_task' \
          || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    # As chaves PERSISTIDAS da calibracao nunca sao ligadas a formula PERT na arvore viva. A
    # interseccao nao pega este caso — `desvio` nao aparece ligado a razao com `=`, so em prosa —,
    # e e a forma que a DS-40 carregava: a chave do numero adimensional definida como dispersao
    # em horas. No registro ela fica como historia; aqui, nunca.
    ab_chave_fora_do_pert)
      v="$(ab_simbolos "$d" "$AB_PERT_RE" | grep -xE 'desvio|desvio_medio' | tr '\n' ' ')"
      [ -z "$v" ] ;;
    # Schema publico intacto: a correcao e de vocabulario matematico interno, nao de formato.
    ab_chaves_publicas)
      grep -qF 'desvio:' "$d/references/00-schema.md" \
        && grep -qF 'desvio_medio:' "$d/references/00-schema.md" \
        && grep -qF 'desvio:' "$d/assets/TEMPLATE-HISTORICO.md" \
        && grep -qF 'desvio_medio:' "$d/assets/TEMPLATE-HISTORICO.md" \
        && grep -qF 'fator_correcao_aplicado' "$d/references/00-schema.md" ;;
    # E o simbolo interno NAO vira chave: ele nomeia a grandeza no contrato matematico, nunca um
    # campo em disco. Chave nova seria quebra de schema disfarcada de clareza.
    ab_simbolo_interno_nao_persiste)
      v="$(grep -rnE '^[[:space:]]*(desvio_padrao_task|desvio_calibracao_task|desvio_padrao_medio|desvio_calibracao_medio):' \
        "$d/references/00-schema.md" "$d/assets/TEMPLATE-HISTORICO.md" "$d/assets/TEMPLATE-ESTIMATIVA.md" \
        2>/dev/null | tr '\n' ' ')"
      [ -z "$v" ] ;;
    # A incompatibilidade esta DECLARADA onde as duas grandezas se encontram (a 07-estimativa.md
    # define as duas). Sem a frase, o proximo leitor acha os dois nomes sinonimos e os funde de
    # volta — foi assim que o nome unico sobreviveu a D-09 e a D-10.
    ab_incompatibilidade)
      f=references/07-estimativa.md
      ab_tem_re "$d/$f" 'duas grandezas (diferentes|incompat[íi]veis)|grandezas incompat[íi]veis' \
        && ab_tem_re "$d/$f" 'desvio_padrao_task' \
        && ab_tem_re "$d/$f" 'desvio_calibracao_task' \
        && ab_tem_re "$d/$f" 'n[ãa]o s[ãa]o intercambi|nunca intercambi' \
        && ab_tem_re "$d/$f" 'adimensional' ;;
    # A decisao esta registrada: e onde a proxima sessao encontra o PORQUE do par de nomes. E ela
    # nomeia a notacao SUPERADA, que o registro append-only conserva nas decisoes antigas — sem
    # isso, quem le a DS-37 ou a DS-160 nao tem como saber qual das duas grandezas e aquela.
    ab_ds162)
      v="$(grep -F '| DS-162 |' "$d/DECISOES-DA-SKILL.md")"
      [ -n "$v" ] \
        && printf '%s' "$v" | grep -qF 'desvio_padrao_task' \
        && printf '%s' "$v" | grep -qF 'desvio_calibracao_task' \
        && printf '%s' "$v" | grep -qF 'desvio_medio' \
        && printf '%s' "$v" | grep -qF 'desvio_task' ;;
    # E o registro continua append-only: as decisoes que nasceram com a notacao antiga seguem
    # inteiras, inclusive a DS-161 da D-12. Reescrever o registro para "limpar" o vocabulario
    # apagaria a historia que explica por que o par de nomes existe.
    ab_registro_append_only)
      for f in DS-37 DS-40 DS-160 DS-161; do
        grep -qF "| $f |" "$d/DECISOES-DA-SKILL.md" || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    *) return 1 ;;
  esac
}
AB_CASOS="ab_sem_simbolo_colidente ab_sem_intersecao ab_pert_canonica ab_cal_canonica
ab_fronteira_pert ab_fronteira_cal ab_chave_fora_do_pert ab_chaves_publicas
ab_simbolo_interno_nao_persiste ab_incompatibilidade ab_ds162 ab_registro_append_only"

# 1. Dados literais que SEPARAM as duas grandezas na MESMA task. Sem isto, "dois nomes" seria
#    discussao de estilo: duas tasks `integracao_externa` (o=4 m=5 p=12 com real 6.8; o=3 m=4 p=5
#    com real 4.8) tem desvio-padrao PERT 1,33 h e 0,33 h — dispersao, em hora — e razao de
#    calibracao 1,13 e 1,20 — adimensional, e os `desvio` persistidos da D-10. Quatro numeros,
#    duas grandezas, um nome so no contrato da base.
ab_num() { # ab_num <o> <m> <p> <real> <grandeza:padrao|calibracao>
  awk -v o="$1" -v m="$2" -v p="$3" -v r="$4" -v g="$5" 'BEGIN {
    med = (o + 4*m + p) / 6
    x = (g == "padrao") ? (p - o) / 6 : r / med
    s = x * 100; i = int(s); if (s - i >= 0.5) i++      # duas casas, half-up (D-10)
    printf "%.2f", i / 100
  }'
}
AB_PA="$(ab_num 4 5 12 6.8 padrao)";     AB_CA="$(ab_num 4 5 12 6.8 calibracao)"
AB_PB="$(ab_num 3 4  5 4.8 padrao)";     AB_CB="$(ab_num 3 4  5 4.8 calibracao)"
[ "$AB_PA" = "1.33" ] && [ "$AB_CA" = "1.13" ] && [ "$AB_PB" = "0.33" ] && [ "$AB_CB" = "1.20" ] \
  && [ "$AB_PA" != "$AB_CA" ] && [ "$AB_PB" != "$AB_CB" ]; ab_rc=$?
afirma "ab1-grandezas-separadas-na-mesma-task" "$ab_rc" \
  "A: padrao=$AB_PA h razao=$AB_CA | B: padrao=$AB_PB h razao=$AB_CB"

# 1b. E a troca de uma pela outra e observavel em HORA PUBLICADA: somar em quadratura as razoes de
#     calibracao, em vez dos desvios-padrao, com o mesmo fator canonico 1,16 da D-10, publica
#     9-14 h onde o canonico publica 10-14 h. E a mesma divergencia que a D-10 mediu, agora pelo
#     nome e nao pelo arredondamento.
ab_faixa() { # ab_faixa <fator> <grandeza na quadratura:padrao|calibracao>
  awk -v f="$1" -v g="$2" 'BEGIN {
    mA = (4 + 4*5 + 12)/6; mB = (3 + 4*4 + 5)/6
    if (g == "padrao") { dA = (12 - 4)/6; dB = (5 - 3)/6 } else { dA = 1.13; dB = 1.20 }
    m = (mA + mB) * f; d = sqrt(dA*dA + dB*dB) * f
    mn = m - d; mx = m + d; piso = (4 + 3) * f
    if (mn < piso) mn = piso
    printf "%d-%d", int(mn), (mx == int(mx) ? mx : int(mx) + 1)
  }'
}
AB_FX_OK="$(ab_faixa 1.16 padrao)"; AB_FX_COL="$(ab_faixa 1.16 calibracao)"
[ "$AB_FX_OK" = "10-14" ] && [ "$AB_FX_COL" = "9-14" ] && [ "$AB_FX_OK" != "$AB_FX_COL" ]; ab_rc=$?
afirma "ab1b-colisao-muda-a-faixa-publicada" "$ab_rc" \
  "desvio_padrao_task -> $AB_FX_OK h; razao de calibracao na quadratura -> $AB_FX_COL h"

# 2 a 13. A bateria, lida das referencias reais. O nome do caso e derivado ANTES da condicao e o
#         status e capturado na linha seguinte: substituicao de comando antes do `$?` apagaria o
#         status da condicao (DS-161 / secao AA).
for ab_c in $AB_CASOS; do
  ab_nome="$(printf '%s' "$ab_c" | tr '_' '-')"
  ab_caso "$ab_c" "$SK"; ab_rc=$?
  afirma "$ab_nome" "$ab_rc" "lido da arvore do contrato em $SK"
done

# 14. Mutantes. Cada um nasce numa COPIA da skill — as referencias reais nunca sao tocadas — e tem
#     de morrer pelos casos nomeados, nao de carona: o caso nomeado e verificado um a um, e o
#     mutante so e considerado morto quando TODOS eles reprovam. `ab_muta` so devolve 0 quando o
#     arquivo REALMENTE mudou em relacao a arvore real.
ABW="$(mktemp -d)"
ab_copia() { rm -rf "$ABW/$1"; mkdir -p "$ABW/$1"; cp -R "$SK/." "$ABW/$1/"; printf '%s' "$ABW/$1"; }
ab_muta() { # ab_muta <dir> <arquivo-rel> <expressao sed>
  [ -f "$1/$2" ] || return 1
  sed "$3" "$1/$2" > "$ABW/.sed" && cat "$ABW/.sed" > "$1/$2" || return 1   # sem `sed -i` (so GNU)
  ! cmp -s "$SK/$2" "$1/$2"
}
ab_mata() { local c; for c in $AB_CASOS; do ab_caso "$c" "$1" || { printf '%s' "$c"; return; }; done; }
ab_mutante() { # ab_mutante <nome> <rc da geracao> <dir> <caso que TEM de matar>...
  local nome="$1" rcg="$2" d="$3" c vivos=""; shift 3
  if [ "$rcg" -eq 0 ]; then for c in "$@"; do ab_caso "$c" "$d" && vivos="$vivos$c "; done; fi
  [ "$rcg" -eq 0 ] && [ -z "$vivos" ]; local rc=$?
  afirma "$nome" "$rc" "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rcg)"
}
ab_equivalente() { # ab_equivalente <nome> <rc da geracao> <dir> — equivalente nao pode morrer
  local nome="$1" rcg="$2" d="$3" m=""
  [ "$rcg" -eq 0 ] && m="$(ab_mata "$d")"
  [ "$rcg" -eq 0 ] && [ -z "$m" ]; local rc=$?
  afirma "$nome" "$rc" "equivalente, nao conta como morto; reprovou=[${m:-nenhum}] (rc geracao=$rcg)"
}
AB_CTL="$(ab_copia controle)"
AB_K="$(ab_mata "$AB_CTL")"; [ -z "$AB_K" ]; ab_rc=$?
afirma "abm-controle-copia-intacta-sobrevive" "$ab_rc" "${AB_K:-nenhum caso reprova a copia sem mutacao}"

# m1 — a colisao da base, restaurada: um nome para as duas formulas no mesmo arquivo.
AB_M="$(ab_copia m1)"
ab_muta "$AB_M" references/07-estimativa.md 's/desvio_padrao_task/desvio_task/g; s/desvio_calibracao_task/desvio_task/g'
ab_mutante "abm-mutante-1-colisao-restaurada" $? "$AB_M" \
  ab_sem_simbolo_colidente ab_sem_intersecao ab_pert_canonica ab_cal_canonica

# m2 — so o lado PERT volta ao nome antigo. Nao ha interseccao (a calibracao mantem o seu nome),
#      e por isso este mutante prova que o caso do simbolo ausente e independente do da
#      interseccao: o nome ambiguo de volta e defeito mesmo sem as duas acepcoes no mesmo nome.
AB_M="$(ab_copia m2)"
ab_muta "$AB_M" assets/TEMPLATE-ESTIMATIVA.md 's/desvio_padrao_task/desvio_task/g'
ab_mutante "abm-mutante-2-so-o-lado-pert-reverte" $? "$AB_M" \
  ab_sem_simbolo_colidente ab_pert_canonica ab_fronteira_pert
ab_caso ab_sem_intersecao "$AB_M"; ab_rc=$?
afirma "abm-mutante-2-nao-produz-interseccao" "$ab_rc" "os dois casos sao independentes, como projetado"

# m3 — a forma da DS-40 trazida para a arvore viva: a chave PERSISTIDA da calibracao definida como
#      a dispersao PERT. A interseccao nao a ve; o caso da chave, sim.
AB_M="$(ab_copia m3)"
ab_muta "$AB_M" assets/TEMPLATE-ESTIMATIVA.md 's/^desvio_padrao_task = (p - o) \/ 6/desvio = (p - o) \/ 6/'
ab_mutante "abm-mutante-3-chave-persistida-vira-formula-pert" $? "$AB_M" \
  ab_chave_fora_do_pert ab_pert_canonica

# m4 — as formulas trocadas: o simbolo do desvio-padrao ligado a razao de calibracao. O defeito
#      sob os nomes NOVOS — a prova de que o oraculo e sobre as grandezas, nao sobre a grafia.
AB_M="$(ab_copia m4)"
ab_muta "$AB_M" references/06-execucao.md 's/^desvio_calibracao_task = arredonda/desvio_padrao_task = arredonda/'
ab_mutante "abm-mutante-4-formulas-trocadas-sob-os-nomes-novos" $? "$AB_M" \
  ab_sem_intersecao ab_cal_canonica

# m5 — a chave publica renomeada a pretexto de clareza. Schema quebrado, parser quebrado.
AB_M="$(ab_copia m5)"
ab_muta "$AB_M" references/00-schema.md 's/desvio_medio:/desvio_calibracao_medio:/g'
ab_mutante "abm-mutante-5-chave-publica-renomeada" $? "$AB_M" ab_chaves_publicas

# m6 — a declaracao da incompatibilidade removida: os dois nomes ficam, a razao de serem dois sai.
AB_M="$(ab_copia m6)"
ab_muta "$AB_M" references/07-estimativa.md '/^> \*\*Dois nomes, duas grandezas\.\*\*/d'
ab_mutante "abm-mutante-6-incompatibilidade-apagada" $? "$AB_M" ab_incompatibilidade ab_fronteira_pert

# m7 — o simbolo interno promovido a chave em disco, sem remover a antiga.
AB_M="$(ab_copia m7)"
ab_muta "$AB_M" assets/TEMPLATE-HISTORICO.md '/^    desvio: /a\    desvio_calibracao_task: 1.13'
ab_mutante "abm-mutante-7-simbolo-interno-vira-chave" $? "$AB_M" ab_simbolo_interno_nao_persiste

# m8 — a fronteira apagada de um ponto de entrada da calibracao: a 08-rastro.md deixa de dizer que
#      o que a calibracao agrega nao e o desvio-padrao. Quem chega por ela volta a poder confundir.
AB_M="$(ab_copia m8)"
ab_muta "$AB_M" references/08-rastro.md 's/, nunca o `desvio_padrao_task`//g'
ab_mutante "abm-mutante-8-fronteira-apagada-no-rastro" $? "$AB_M" ab_fronteira_cal

# m9 — a DS-162 apagada do registro: a regra fica nas referencias e perde o porque.
AB_M="$(ab_copia m9)"
ab_muta "$AB_M" DECISOES-DA-SKILL.md '/^| DS-162 |/d'
ab_mutante "abm-mutante-9-ds162-apagada" $? "$AB_M" ab_ds162

# m10 — o registro "limpo": a DS-161 da D-12 removida junto com a notacao antiga. E o oposto do
#       append-only, e o jeito mais facil de a correcao de vocabulario apagar historia alheia.
AB_M="$(ab_copia m10)"
ab_muta "$AB_M" DECISOES-DA-SKILL.md '/^| DS-161 |/d'
ab_mutante "abm-mutante-10-registro-reescrito" $? "$AB_M" ab_registro_append_only

# Equivalentes: mudam a forma e nao a regra, e por isso NAO podem morrer. Sem eles, um oraculo que
# casasse espaco em branco ou marcacao passaria por discriminante sem ser.
AB_M="$(ab_copia e1)"
ab_muta "$AB_M" assets/TEMPLATE-ESTIMATIVA.md 's/^desvio_padrao_task = (p - o) \/ 6/desvio_padrao_task   =  (p-o)\/6/'
ab_equivalente "abe-equivalente-1-espacamento-da-formula" $? "$AB_M"
AB_M="$(ab_copia e2)"
ab_muta "$AB_M" references/08-rastro.md 's/`desvio_calibracao_task`/**desvio_calibracao_task**/g'
ab_equivalente "abe-equivalente-2-marcacao-do-simbolo" $? "$AB_M"
rm -rf "$ABW"

# 15. E a vitrine e a SKILL.md tambem nao carregam o simbolo colidente: sao os lugares de onde a
#     proxima sessao reconstroi o vocabulario errado sem nunca abrir uma reference.
AB_VITRINE="$(grep -rlF 'desvio_task' ${RAIZ_SRC:+"$RAIZ_SRC/README.md"} "$SK/SKILL.md" 2>/dev/null | tr '\n' ' ')"
[ -z "$AB_VITRINE" ]; ab_rc=$?
afirma "ab-vitrine-sem-o-simbolo-colidente" "$ab_rc" "arquivos com o simbolo antigo=[${AB_VITRINE:-nenhum}]"

echo "== AC. a calibracao conta so entradas com \`desvio\` numerico; \`desvio: null\` nao entra (B2) =="
# A D-09 fixou o AGREGADOR, a D-10 a PRECISAO e a D-11 o NOME. O CONJUNTO AGREGADO continuava
# indefinido. O mesmo schema diz as duas coisas:
#   - `estimado_min`, `estimado_max`, `estimado_media` e `desvio` sao `null` quando o trabalho
#     rodou sem a F3.5; `real` e sempre preenchido  (00-schema.md, kind estimativa_historico);
#   - `fator_ativo` so e `true` com 3 ou mais entradas ENCERRADAS daquele tipo (mesmo arquivo),
#     e `desvio_medio` e a media dos desvios persistidos das entradas ENCERRADAS daquele tipo
#     (06-execucao.md Passo 3, TEMPLATE-HISTORICO.md).
# Entrada sem F3.5 e entrada encerrada: ela tem `real`, nao tem `desvio`. Logo "entradas
# encerradas" alcanca entradas cujo `desvio` e `null`, e o contrato nao diz o que fazer com elas —
# nem no contador `entradas`, nem na media `desvio_medio`, nem no limiar do `fator_ativo`. Duas
# execucoes honestas do MESMO historico gravam `entradas: 2 / desvio_medio: 1.25 /
# fator_ativo: false` e `entradas: 4 / desvio_medio: 0.63 / fator_ativo: true`: contador, numero e
# chave booleana diferentes, e um fator de correcao LIGADO sobre dois desvios reais.
# Fica ambigua tambem a FORMA com 1 ou 2 entradas elegiveis: item presente com `fator_ativo:
# false`, ou nenhum item? A D-08 fixou so o extremo (`calibracao: []` e a tabela sem linha de
# dados), e apagar o item com poucas entradas perde o contador que o proximo fechamento incrementa.
# Canonico a fixar: `entradas`, `desvio_medio` e `fator_ativo` leem SO as entradas com `desvio`
# numerico (nao nulo); nulo nunca vale zero; item presente a partir de 1 elegivel; `calibracao: []`
# so sem nenhuma elegivel.
# Pontos que DEFINEM o conjunto agregado, os que definem o LIMIAR, e os que definem a FORMA.
AC_REL_DEFINEM="references/00-schema.md references/06-execucao.md assets/TEMPLATE-HISTORICO.md"
AC_REL_LIMIAR="references/00-schema.md references/06-execucao.md"
AC_REL_FORMA="references/00-schema.md assets/TEMPLATE-HISTORICO.md"

# Detectores sobre o texto SEM marcacao, contando linhas em vez de abortar na primeira: mesma
# disciplina das secoes Z e AB (`grep -q` depois de um pipe derruba o pipeline com `pipefail`).
ac_txt() { tr -d '*`' < "$1"; }
ac_conta() { ac_txt "$1" | grep -ciE "$2"; }
ac_tem_re() { [ -f "$1" ] && [ "$(ac_conta "$1" "$2")" -gt 0 ]; }

# As politicas que o contrato tem de fixar, LIDAS do texto — nunca assumidas pelo teste.
# `[^.]{0,N}` nao cruza ponto final: a regra tem de estar na MESMA frase, senao "entradas
# encerradas" num paragrafo e "desvio numerico" noutro passariam por definicao.
AC_RE_ELEG='(entradas|contador|contagem|contam|conta|elegív|elegiv)[^.]{0,160}desvio[^.]{0,80}(numéric|numeric|não nul|nao nul)|desvio[^.]{0,80}(numéric|numeric|não nul|nao nul)[^.]{0,160}(entradas|contador|contagem|contam)'
AC_RE_ENC='entradas encerradas|a partir de [0-9]+ entradas'
AC_RE_NULO_NAO_ZERO='(nunca|não|nao)[^.]{0,80}(como|igual a|vale) (zero|0)'
AC_RE_ZERO='(como|igual a|vale) (zero|0)[^.]{0,40}(na média|na media|no cálculo|no calculo)|conta como (zero|0)'
AC_RE_MEDIA_ELEG='(desvio_medio|média|media)[^.]{0,200}(elegív|elegiv|desvio numéric|desvio numeric|desvio não nul|desvio nao nul)|(elegív|elegiv|desvio numéric|desvio numeric)[^.]{0,200}(desvio_medio|média dos|media dos)'
AC_RE_LIM_ELEG='[0-9]+ ou mais entradas (elegíveis|elegiveis)|a partir de [0-9]+ entradas (elegíveis|elegiveis)'
AC_RE_LIM_ENC='[0-9]+ ou mais entradas encerradas|a partir de [0-9]+ entradas( |,|\.|$)'
AC_RE_FORMA='(1 ou 2|uma ou duas) entradas (elegíveis|elegiveis)[^.]{0,200}(item|linha)|(o item|a linha)[^.]{0,200}(1 ou 2|uma ou duas) entradas (elegíveis|elegiveis)'
AC_RE_VAZIA='calibracao: \[\][^.]{0,240}(nenhuma entrada elegív|nenhuma entrada elegiv|sem entrada elegív|zero entradas elegív)|(nenhuma entrada elegív|nenhuma entrada elegiv|sem entrada elegív|zero entradas elegív)[^.]{0,240}calibracao: \[\]'
AC_RE_NULO_FORA='desvio: null[^.]{0,200}(não cont|nao cont|fora d|nunca entra|ignorad|não é elegív|nao e elegiv)|(não cont|nao cont|fora d|nunca entra|ignorad)[^.]{0,200}desvio: null'

ac_pol_contador() { # -> numerico | encerradas | indefinido
  if   ac_tem_re "$1" "$AC_RE_ELEG"; then printf 'numerico'
  elif ac_tem_re "$1" "$AC_RE_ENC";  then printf 'encerradas'
  else printf 'indefinido'; fi
}
ac_pol_media() { # -> fora | zero | indefinido  (o que o nulo faz na media)
  if   ac_tem_re "$1" "$AC_RE_ZERO" && ! ac_tem_re "$1" "$AC_RE_NULO_NAO_ZERO"; then printf 'zero'
  elif ac_tem_re "$1" "$AC_RE_MEDIA_ELEG"; then printf 'fora'
  else printf 'indefinido'; fi
}
ac_pol_base() { # -> elegiveis | encerradas | indefinido  (o que o limiar conta)
  if   ac_tem_re "$1" "$AC_RE_LIM_ELEG"; then printf 'elegiveis'
  elif ac_tem_re "$1" "$AC_RE_LIM_ENC";  then printf 'encerradas'
  else printf 'indefinido'; fi
}
ac_pol_limiar() { # -> o numero de elegiveis que liga o fator, ou indefinido
  local v
  v="$(ac_txt "$1" | grep -oE "$AC_RE_LIM_ELEG" | grep -oE '[0-9]+' | sort -u | tr '\n' ' ' | sed 's/ *$//')"
  case "$v" in ''|*' '*) printf 'indefinido' ;; *) printf '%s' "$v" ;; esac
}
ac_pol_forma() { # -> por_contador | indefinido  (item presente decidido pelo contador)
  if ac_tem_re "$1" "$AC_RE_FORMA"; then printf 'por_contador'; else printf 'indefinido'; fi
}

# A politica da ARVORE: valor unico entre os pontos que o declaram. Ponto calado nao vota (os casos
# de texto cobram cada ponto um a um), mas DOIS pontos discordando da `indefinido` — contrato que se
# contradiz nao fixa numero nenhum, e e exatamente a forma do defeito B2.
ac_pol_arvore() { # ac_pol_arvore <dir> <contador|media|base|limiar|forma>
  local d="$1" dim="$2" f v vals="" u
  for f in $AC_REL_DEFINEM; do
    [ -f "$d/$f" ] || continue
    case "$dim" in
      contador) v="$(ac_pol_contador "$d/$f")" ;;
      media)    v="$(ac_pol_media "$d/$f")" ;;
      base)     v="$(ac_pol_base "$d/$f")" ;;
      limiar)   v="$(ac_pol_limiar "$d/$f")" ;;
      forma)    v="$(ac_pol_forma "$d/$f")" ;;
    esac
    [ "$v" = indefinido ] || vals="$vals $v"
  done
  u="$(printf '%s\n' $vals | sort -u | tr '\n' ' ' | sed 's/^ *//; s/ *$//')"
  case "$u" in ''|*' '*) printf 'indefinido' ;; *) printf '%s' "$u" ;; esac
}

# O ORACULO. Dada a lista de `desvio` de um tipo (`null` inclusive) e as politicas, devolve o que o
# HISTORICO.md grava: contador, `desvio_medio` (duas casas, half-up — D-10), `fator_ativo` e a forma
# do item. Politica indefinida produz `indefinido`, nunca um palpite: e assim que a ausencia de
# contrato aparece como numero errado, e nao como palavra faltando.
ac_num() { # ac_num <desvios> <contador> <media> <base> <limiar> <forma>
  awk -v lista="$1" -v pc="$2" -v pm="$3" -v pb="$4" -v lim="$5" -v pf="$6" '
    function arr(x,  s, i) { s = x * 100; i = int(s); if (s - i >= 0.5) i++; return sprintf("%.2f", i / 100) }
    BEGIN {
      n = split(lista, v, / +/)
      for (i = 1; i <= n; i++) {
        if (v[i] == "") continue
        nt++                                         # encerradas: toda entrada da lista
        if (v[i] != "null") { ne++; soma += v[i] }    # elegiveis: `desvio` numerico
      }
      # `ne + 0` e `nt + 0`: sem elegivel nenhuma, `ne` nunca foi atribuida e `%s` imprimiria a
      # string vazia no lugar do contador `0` — o cenario da `calibracao: []`.
      contador = (pc == "numerico") ? ne + 0 : ((pc == "encerradas") ? nt + 0 : "indefinido")
      if      (pm == "fora") media = (ne > 0) ? arr(soma / ne) : "sem"
      else if (pm == "zero") media = (nt > 0) ? arr(soma / nt) : "sem"
      else                   media = "indefinido"
      base = (pb == "elegiveis") ? ne : ((pb == "encerradas") ? nt : -1)
      fator = (base < 0 || lim == "indefinido") ? "indefinido" : ((base >= lim + 0) ? "true" : "false")
      if (pf != "por_contador" || contador == "indefinido") forma = "indefinido"
      else forma = (contador + 0 >= 1) ? "item" : "vazia"
      printf "%s %s %s %s", contador, media, fator, forma
    }'
}
# Os quatro cenarios do defeito, todos do mesmo `tipo_task`, com nulas sempre presentes.
AC_A='1.20 1.30 null null'        # 2 elegiveis + 2 nulas
AC_B='1.20 1.30 1.30 null null'   # 3 elegiveis + 2 nulas
AC_C='1.25 null'                  # 1 elegivel  + 1 nula
AC_D='null null'                  # nenhuma elegivel
AC_CANONICO='2 1.25 false item; 3 1.27 true item; 1 1.25 false item; 0 sem false vazia'
ac_quatro() { # ac_quatro <contador> <media> <base> <limiar> <forma> -> as quatro ternas, A a D
  printf '%s; %s; %s; %s' "$(ac_num "$AC_A" "$@")" "$(ac_num "$AC_B" "$@")" \
                          "$(ac_num "$AC_C" "$@")" "$(ac_num "$AC_D" "$@")"
}
ac_cenarios() { # ac_cenarios <dir> -> as quatro ternas sob a politica LIDA daquela arvore
  local d="$1"
  ac_quatro "$(ac_pol_arvore "$d" contador)" "$(ac_pol_arvore "$d" media)" \
            "$(ac_pol_arvore "$d" base)"     "$(ac_pol_arvore "$d" limiar)" \
            "$(ac_pol_arvore "$d" forma)"
}

# 1. Dados literais que SEPARAM as duas leituras. Sem isto, "contar ou nao contar as nulas" seria
#    discussao de vocabulario: nas MESMAS quatro entradas, a leitura elegivel grava
#    `entradas: 2 / 1.25 / false` e a leitura "encerradas, nulo como zero" grava
#    `entradas: 4 / 0.63 / true`. Contador, numero e chave booleana divergem, e o fator liga.
AC_SO_ELEG="$(ac_quatro numerico fora elegiveis 3 por_contador)"
AC_SO_ELEG_A="$(ac_num "$AC_A" numerico fora elegiveis 3 por_contador)"
AC_COM_NULOS_A="$(ac_num "$AC_A" encerradas zero encerradas 3 por_contador)"
[ "$AC_SO_ELEG_A" = '2 1.25 false item' ] && [ "$AC_COM_NULOS_A" = '4 0.63 true item' ] \
  && [ "$AC_SO_ELEG_A" != "$AC_COM_NULOS_A" ]; ac_rc=$?
afirma "ac1-nulos-mudam-contador-media-e-fator" "$ac_rc" \
  "elegiveis=[$AC_SO_ELEG_A] contando nulas=[$AC_COM_NULOS_A] sobre [$AC_A]"

# 1b. E o oraculo esta correto nos quatro cenarios, independentemente de qualquer texto: 2
#     elegiveis -> 1,25 e fator desligado; 3 -> 1,27 e fator ligado; 1 -> item presente com fator
#     desligado; nenhuma -> lista vazia. Este caso guarda a aritmetica; os seguintes, o contrato.
[ "$AC_SO_ELEG" = "$AC_CANONICO" ]; ac_rc=$?
afirma "ac1b-oraculo-dos-quatro-cenarios-correto" "$ac_rc" "calculado=[$AC_SO_ELEG]"

# 1c. O limiar e lido, nao embutido: com limiar 2 o cenario A ligaria o fator. E o que o mutante 4
#     faz, e a razao de o oraculo receber o numero em vez de o conhecer.
AC_LIM2_A="$(ac_num "$AC_A" numerico fora elegiveis 2 por_contador)"
[ "$AC_LIM2_A" = '2 1.25 true item' ] && [ "$AC_LIM2_A" != "$AC_SO_ELEG_A" ]; ac_rc=$?
afirma "ac1c-limiar-e-parametro-do-oraculo" "$ac_rc" "limiar 2 no cenario A=[$AC_LIM2_A]"

# A bateria, por ARVORE: a real roda em "$SK" e cada mutante roda a MESMA bateria numa copia.
ac_caso() { # ac_caso <caso> <dir> -> 0 se o caso PASSA naquela arvore
  local c="$1" d="$2" f sujo="" v
  case "$c" in
    # `entradas` conta SO as entradas com `desvio` numerico — a amarracao que o HEAD nao tem.
    ac_entradas_so_desvio_numerico)
      for f in $AC_REL_DEFINEM; do
        v="$(ac_pol_contador "$d/$f")"; [ "$v" = numerico ] || sujo="$sujo $f:$v"
      done
      [ -z "$sujo" ] ;;
    # `desvio_medio` e a media SO sobre essas entradas: o divisor e o numero de elegiveis.
    ac_media_so_desvio_numerico)
      for f in $AC_REL_DEFINEM; do
        v="$(ac_pol_media "$d/$f")"; [ "$v" = fora ] || sujo="$sujo $f:$v"
      done
      [ -z "$sujo" ] ;;
    # E `desvio: null` nunca vale zero: contar como zero e a leitura que produz 0,63 em vez de 1,25
    # sem contrariar frase nenhuma do HEAD.
    ac_nulo_nunca_vale_zero)
      for f in $AC_REL_DEFINEM; do
        ac_tem_re "$d/$f" "$AC_RE_NULO_NAO_ZERO" || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    # O estado nulo e nomeado como tal e posto fora da contagem. Regra escrita so pelo positivo
    # ("conta as numericas") deixa o leitor da entrada sem F3.5 sem resposta: e ela que ele tem.
    ac_nulo_fora_da_contagem)
      for f in $AC_REL_DEFINEM; do
        ac_tem_re "$d/$f" "$AC_RE_NULO_FORA" || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    # O limiar do `fator_ativo` conta elegiveis, nao encerradas...
    ac_limiar_sobre_elegiveis)
      for f in $AC_REL_LIMIAR; do
        v="$(ac_pol_base "$d/$f")"; [ "$v" = elegiveis ] || sujo="$sujo $f:$v"
      done
      [ -z "$sujo" ] ;;
    # ...e continua sendo 3: a regra do fator ja fixou o numero, e a B2 muda a BASE da contagem,
    # nunca o numero.
    ac_limiar_e_tres)
      for f in $AC_REL_LIMIAR; do
        v="$(ac_pol_limiar "$d/$f")"; [ "$v" = 3 ] || sujo="$sujo $f:$v"
      done
      [ -z "$sujo" ] ;;
    # Item PRESENTE com 1 ou 2 elegiveis, com `fator_ativo: false`: a lista vazia e outro estado.
    ac_item_presente_com_poucas_elegiveis)
      for f in $AC_REL_FORMA; do
        [ "$(ac_pol_forma "$d/$f")" = por_contador ] \
          && ac_tem_re "$d/$f" 'fator_ativo: false|fator_ativo (fica|é|e) false' || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    # E `calibracao: []` so sem NENHUMA elegivel. A D-08 fixou a FORMA da lista vazia; aqui se fixa
    # QUANDO ela ocorre — sem isso, "poucas entradas" e "nenhuma entrada" voltam a ser o mesmo caso.
    ac_lista_vazia_so_sem_elegiveis)
      for f in $AC_REL_FORMA; do
        ac_tem_re "$d/$f" "$AC_RE_VAZIA" || sujo="$sujo $f"
      done
      [ -z "$sujo" ] ;;
    # O caso semantico: a politica LIDA da arvore, aplicada aos quatro cenarios, produz exatamente
    # o que o canonico grava. Contrato calado ou contraditorio devolve `indefinido`.
    ac_oraculo_numerico)
      v="$(ac_cenarios "$d")"; [ "$v" = "$AC_CANONICO" ] ;;
    # Schema publico intacto: a B2 e correcao de contrato, nao de formato.
    ac_chaves_publicas)
      grep -qF 'entradas:' "$d/references/00-schema.md" \
        && grep -qF 'desvio_medio:' "$d/references/00-schema.md" \
        && grep -qF 'fator_ativo:' "$d/references/00-schema.md" \
        && grep -qF 'entradas:' "$d/assets/TEMPLATE-HISTORICO.md" \
        && grep -qF 'fator_ativo:' "$d/assets/TEMPLATE-HISTORICO.md" ;;
    # E a decisao fica registrada: e onde a proxima sessao encontra o PORQUE de o conjunto agregado
    # ser menor que o conjunto das entradas encerradas.
    # O id e o proximo livre do registro append-only: a DS-163 ja e o piso da faixa agregada
    # (secao Z / D-13), e a decisao da elegibilidade entrou como DS-164.
    ac_ds164)
      v="$(grep -F '| DS-164 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
      [ -n "$v" ] \
        && printf '%s' "$v" | grep -qiE 'elegív|elegiv' \
        && printf '%s' "$v" | grep -qF 'desvio' ;;
    *) return 1 ;;
  esac
}
AC_CASOS="ac_entradas_so_desvio_numerico ac_media_so_desvio_numerico ac_nulo_nunca_vale_zero
ac_nulo_fora_da_contagem ac_limiar_sobre_elegiveis ac_limiar_e_tres
ac_item_presente_com_poucas_elegiveis ac_lista_vazia_so_sem_elegiveis ac_oraculo_numerico
ac_chaves_publicas ac_ds164"

# 2 a 12. A bateria lida das referencias reais. Nome derivado ANTES da condicao e status capturado
#         na linha seguinte (DS-161 / secao AA).
for ac_c in $AC_CASOS; do
  ac_nome="$(printf '%s' "$ac_c" | tr '_' '-')"
  ac_caso "$ac_c" "$SK"; ac_rc=$?
  ac_det="lido da arvore do contrato em $SK"
  [ "$ac_c" = ac_oraculo_numerico ] && ac_det="politica lida=[$(ac_cenarios "$SK")] canonico=[$AC_CANONICO]"
  afirma "$ac_nome" "$ac_rc" "$ac_det"
done

# 13. Mutantes. Mesma mecanica da secao AB: cada um nasce numa COPIA da skill — as referencias reais
#     nunca sao tocadas — e so conta como morto quando TODOS os casos nomeados reprovam. `ac_muta`
#     devolve 0 so quando o arquivo REALMENTE mudou: mutante que nao nasceu nao e mutante morto, e o
#     caso falha dizendo isso.
ACW="$(mktemp -d)"
ac_copia() { rm -rf "$ACW/$1"; mkdir -p "$ACW/$1"; cp -R "$SK/." "$ACW/$1/"; printf '%s' "$ACW/$1"; }
ac_muta() { # ac_muta <dir> <arquivo-rel> <expressao sed>
  [ -f "$1/$2" ] || return 1
  sed "$3" "$1/$2" > "$ACW/.sed" && cat "$ACW/.sed" > "$1/$2" || return 1   # sem `sed -i` (so GNU)
  ! cmp -s "$SK/$2" "$1/$2"
}
ac_mata() { local c; for c in $AC_CASOS; do ac_caso "$c" "$1" || { printf '%s' "$c"; return; }; done; }
ac_mutante() { # ac_mutante <nome> <rc da geracao> <dir> <caso que TEM de matar>...
  local nome="$1" rcg="$2" d="$3" c vivos=""; shift 3
  if [ "$rcg" -eq 0 ]; then for c in "$@"; do ac_caso "$c" "$d" && vivos="$vivos$c "; done; fi
  [ "$rcg" -eq 0 ] && [ -z "$vivos" ]; local rc=$?
  afirma "$nome" "$rc" "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rcg)"
}
ac_equivalente() { # ac_equivalente <nome> <rc da geracao> <dir> — equivalente nao pode morrer
  local nome="$1" rcg="$2" d="$3" m=""
  [ "$rcg" -eq 0 ] && m="$(ac_mata "$d")"
  [ "$rcg" -eq 0 ] && [ -z "$m" ]; local rc=$?
  afirma "$nome" "$rc" "equivalente, nao conta como morto; reprovou=[${m:-nenhum}] (rc geracao=$rcg)"
}
AC_CTL="$(ac_copia controle)"
AC_K="$(ac_mata "$AC_CTL")"; [ -z "$AC_K" ]; ac_rc=$?
afirma "acm-controle-copia-intacta-sobrevive" "$ac_rc" "${AC_K:-nenhum caso reprova a copia sem mutacao}"

# m1 — contar nulos no limiar: a base do `fator_ativo` volta a ser "entradas encerradas". E o
#      defeito do HEAD isolado no limiar: com 2 elegiveis e 2 nulas, o fator LIGA.
AC_M="$(ac_copia m1)"
ac_muta "$AC_M" references/00-schema.md 's/ou mais entradas elegíveis/ou mais entradas encerradas/g'
ac_mutante "acm-mutante-1-limiar-conta-nulos" $? "$AC_M" \
  ac_limiar_sobre_elegiveis ac_limiar_e_tres ac_oraculo_numerico

# m2 — nulo tratado como zero na media: o contador pode ate ficar certo, e `desvio_medio` cai de
#      1,25 para 0,63. E a leitura que o HEAD permite sem contrariar frase nenhuma.
AC_M="$(ac_copia m2)"
ac_muta "$AC_M" references/06-execucao.md 's/nunca como zero/conta como zero/g'
ac_mutante "acm-mutante-2-nulo-como-zero-na-media" $? "$AC_M" \
  ac_media_so_desvio_numerico ac_nulo_nunca_vale_zero ac_oraculo_numerico

# m3 — o item com 1 ou 2 elegiveis apagado: a forma do item presente desaparece do template e
#      "poucas entradas" volta a se confundir com `calibracao: []`.
AC_M="$(ac_copia m3)"
ac_muta "$AC_M" assets/TEMPLATE-HISTORICO.md '/1 ou 2 entradas elegíveis/d'
ac_mutante "acm-mutante-3-item-com-poucas-apagado" $? "$AC_M" \
  ac_item_presente_com_poucas_elegiveis

# m4 — fator ativo com 2 elegiveis: a base continua certa, o numero desce. Dois desvios reais
#      passam a ligar o fator de correcao de um tipo inteiro.
AC_M="$(ac_copia m4)"
ac_muta "$AC_M" references/00-schema.md 's/3 ou mais entradas elegíveis/2 ou mais entradas elegíveis/g'
ac_mutante "acm-mutante-4-fator-com-duas-elegiveis" $? "$AC_M" \
  ac_limiar_e_tres ac_oraculo_numerico

# Equivalentes: mudam a marcacao e nao a regra, e por isso NAO podem morrer — um oraculo que
# dependesse da grafia de uma palavra passaria por discriminante sem ser.
AC_M="$(ac_copia e1)"
ac_muta "$AC_M" assets/TEMPLATE-HISTORICO.md 's/`desvio` numérico/**`desvio` numérico**/g'
ac_equivalente "ace-equivalente-1-marcacao-do-desvio-numerico" $? "$AC_M"
AC_M="$(ac_copia e2)"
ac_muta "$AC_M" references/00-schema.md 's/entradas elegíveis/entradas **elegíveis**/g'
ac_equivalente "ace-equivalente-2-marcacao-do-elegivel" $? "$AC_M"
rm -rf "$ACW"

echo "== AD. o leitor da F3.5 confere o bloco \`calibracao\` persistido contra o canonico, nunca aplica as cegas (PR#10 c.4161807476) =="
# A DS-164 (secao AC) fixou QUAIS entradas a calibracao agrega. Ficou aberto o que o leitor da F3.5
# faz quando o bloco `calibracao` GRAVADO nao e o que essa regra produziria — por exemplo, uma linha
# gravada por uma sessao anterior a DS-164, que contava `desvio: null` como zero. O Passo 1 da
# 07-estimativa.md mandava aplicar "o desvio_medio persistido... sem recalcular nada a partir das
# entradas": um bloco stale era aplicado com a MESMA confianca de um bloco correto, e nada na saida
# avisava a diferenca. A DS-165 fecha isso: o leitor CONFERE o bloco gravado contra o canonico
# (recomputado so dos `desvio` persistidos, nunca de `real / estimado_media`); bate, aplica o
# persistido; diverge, aplica o canonico recomputado, declara a divergencia na saida, marca a
# origem do fator efetivamente aplicado, e o teto de confianca desce a `media`. A F3.5 nunca
# escreve nem migra o HISTORICO.md — so a F6 regrava `calibracao` no fechamento.
# Detector por MARCADOR LITERAL — nunca regex de linguagem natural. Cada regra da DS-165 e uma
# string EXATA, copiada do proprio texto do contrato: se a frase que a carrega for reescrita, o
# marcador tem de ser atualizado junto (o que e o comportamento certo), e se for apagada ou trocada
# por um mutante, a string some e o caso reprova — sem janela de proximidade, sem classe de
# caractere acentuada (que num `grep` baseado em ugrep estoura "complexity limits" e devolve falso
# negativo silencioso), sem depender de a frase caber numa unica linha fisica do markdown.
ad_lit() { # ad_lit <arquivo1> <marcador1> [<arquivo2> <marcador2> ...] -> 0 se TODOS os pares batem
  # Marcador prefixado com "!" inverte o sentido: o caso so passa se essa string NAO estiver no
  # arquivo — usado para proibir a regressao a uma frase antiga que um paragrafo vizinho corrigido
  # deixaria sobreviver sem isso (ex.: "fator e sempre o persistido" ao lado de uma conferencia
  # que já existe, mas antes do fix, em outro paragrafo do MESMO arquivo).
  python3 - "$@" <<'PYEOF'
import sys

args = sys.argv[1:]
pares = list(zip(args[0::2], args[1::2]))

cache = {}
def normalizado(caminho):
    if caminho not in cache:
        try:
            with open(caminho, encoding="utf-8") as fh:
                # so colapsa espaco em branco (quebra de linha fisica inclusive) para uma frase
                # que o markdown fisicamente quebrou em duas linhas continuar casando como uma —
                # nao e regex, e concatenacao: o marcador em si tambem usa espaco simples.
                cache[caminho] = " ".join(fh.read().split())
        except OSError:
            cache[caminho] = None
    return cache[caminho]

def falhou(caminho, marcador):
    t = normalizado(caminho)
    if marcador.startswith("!"):
        proibido = marcador[1:]
        return t is None or proibido in t
    return t is None or marcador not in t

faltando = [(f, m) for f, m in pares if falhou(f, m)]
if faltando:
    print("marcador ausente/proibido-presente:", faltando, file=sys.stderr)
sys.exit(0 if not faltando else 1)
PYEOF
}

# Os marcadores, um por regra da decisao do comentario 4161807476 — exatamente como aparecem no
# arquivo (espaco simples entre palavras; ad_lit normaliza quebras de linha fisicas do mesmo jeito
# antes de procurar).
AD_LIT_CONFERE_07='Confira esse canônico contra o bloco `calibracao` gravado no `HISTORICO.md`.'
AD_LIT_CONFERE_00='O leitor da F3.5 (Passo 1) sempre **confere** o bloco `calibracao` gravado contra esse canônico antes de usar'
AD_LIT_DIVERGE_07='Declare na saída, nesta task e no total, a divergência encontrada'
AD_LIT_DIVERGE_00='e declara a divergência na saída'
AD_LIT_PROIBE_07='**A F3.5 nunca escreve nem migra o `HISTORICO.md`.**'
AD_LIT_PROIBE_00='A F3.5 **nunca** escreve nem migra o `HISTORICO.md`'
AD_LIT_PROIBE_HIST='A F3.5 (`references/07-estimativa.md`) nunca escreve nem migra o `HISTORICO.md`'
AD_LIT_CALIBRACAO_07A='A origem da calibração (DS-165) é `persistido`.'
AD_LIT_CALIBRACAO_07B='a origem da calibração é `recomputado`'
AD_LIT_CALIBRACAO_00A='**persistido** quando o leitor confere e bate contra o bloco `calibracao` gravado'
AD_LIT_CALIBRACAO_00B='**recomputado** quando diverge'
AD_LIT_CALIBRACAO_TMPL='Origem da calibração (DS-165): {{persistido | recomputado | nenhum — canônico sem fator ativo}}'
# O rotulo do campo de prosa e "Origem da calibração" — nunca "Origem do fator": um dos tres
# estados (`nenhum — canônico sem fator ativo`) nao e origem de fator nenhum, entao o nome do
# campo nao pode pressupor que sempre existe um fator. Marcador negativo: proibe a regressao.
AD_LIT_ROTULO_ANTIGO_TMPL='!Origem do fator (DS-165)'
# Os TRES estados do campo "Divergência encontrada" — o terceiro (`HISTORICO.md` ausente) nao e
# nem "confere" nem "diverge": sem o arquivo nao ha bloco `calibracao` nenhum para comparar.
AD_LIT_DIVERGE_AUSENTE_TMPL='não se aplica — HISTORICO.md ausente'
AD_LIT_DIVERGE_AUSENTE_07='não se aplica — HISTORICO.md ausente'
AD_LIT_DIVERGE_AUSENTE_00='não se aplica — HISTORICO.md ausente'
AD_LIT_CONFIANCA_07='Uma divergência detectada **reduz o teto de confiança a `media`**'
AD_LIT_CONFIANCA_00='também limita `confianca` a `media`'
AD_LIT_RAZAO_07='nunca de `real / estimado_media`, que é a razão bruta e não o que a calibração agrega'
AD_LIT_RAZAO_00='nunca a média das razões brutas `real / estimado_media`'
AD_LIT_LIMIAR_00='3 ou mais entradas elegíveis'
# O TEMPLATE-ESTIMATIVA.md tinha dois paragrafos contraditorios: um dizia "o fator e o
# desvio_medio persistido... copiado como esta" (sem condicao nenhuma), o seguinte ja descrevia a
# conferencia (DS-165). "canônico vigente" e o MESMO marcador que 07-estimativa.md e 00-schema.md
# ja usam para "o fator e condicional, persistido OU recomputado" — reaproveitado aqui em vez de
# um quarto texto, para a mesma ideia ter uma unica frase-ancora nos tres documentos.
AD_LIT_CANONICO_VIGENTE_TMPL='canônico vigente'
AD_LIT_SEMPRE_PERSISTIDO_TMPL='!persistido do tipo, copiado do `HISTORICO.md` como está'
# O TERCEIRO ESTADO da origem: nem `persistido` nem `recomputado` cobrem "o canonico nao tem
# fator ativo" (menos de 3 entradas elegiveis, ou sem HISTORICO.md) — e forcar um dos dois ali e
# inventar uma origem para um fator que nao existe (`fator_correcao_aplicado: null` com origem
# `persistido`/`recomputado` e contradicao direta). O rotulo e o MESMO marcador nos 3 documentos.
AD_LIT_SEM_FATOR_07='nenhum — canônico sem fator ativo'
AD_LIT_SEM_FATOR_00='nenhum — canônico sem fator ativo'
AD_LIT_SEM_FATOR_TMPL='nenhum — canônico sem fator ativo'
# E o rotulo se aplica mesmo quando o bloco STALE divergente MENTE que tem fator ativo — a
# fixture `api` (2 elegiveis, canonico desliga, stale divergente dizia `fator_ativo: true` com 4
# entradas) e exatamente esse cenario: divergencia presente, mas sem fator a aplicar.
AD_LIT_SEM_FATOR_MESMO_SE_STALE_MENTE='mesmo que o bloco gravado divergente dissesse `fator_ativo: true`'

# O ORACULO da divergencia. Dado o conjunto de `desvio` persistidos de um tipo e o bloco STALE
# gravado (entradas, desvio_medio, fator_ativo), devolve o canonico (DS-164: so elegiveis, media
# half-up, fator a partir de 3), se diverge do stale, o fator EFETIVAMENTE aplicado e a origem.
ad_num() { # ad_num <desvios> <stale_entradas> <stale_media> <stale_fator_ativo>
  awk -v lista="$1" -v se="$2" -v sm="$3" -v sf="$4" '
    function arr(x,  s, i) { s = x * 100; i = int(s); if (s - i >= 0.5) i++; return sprintf("%.2f", i / 100) }
    BEGIN {
      n = split(lista, v, / +/)
      for (i = 1; i <= n; i++) { if (v[i] == "") continue; if (v[i] != "null") { ne++; soma += v[i] } }
      ce = ne + 0
      cm = (ne > 0) ? arr(soma / ne) : "sem"
      cf = (ne >= 3) ? "true" : "false"
      dv = (se != ce || sm != cm || sf != cf) ? "true" : "false"
      # A origem depende do CANONICO (cf), nunca da divergencia isolada: com `fator_ativo: false`
      # nao ha fator nenhum para ter sido persistido OU recomputado — e o terceiro estado da
      # DS-165, independente de bater ou divergir do bloco stale.
      if (cf == "true") { fv = cm; org = (dv == "true") ? "recomputado" : "persistido" }
      else              { fv = "null"; org = "nenhum — canônico sem fator ativo" }
      printf "%s %s %s %s %s %s", ce, cm, cf, dv, fv, org
    }'
}
# As duas fixtures do PR#10 c.4161807476, ambas do mesmo `tipo_task`, com a quinta/quarta nula.
AD_API='1.20 1.30 null null'                  # canonico: 2 elegiveis, stale conta as nulas como zero
AD_INTEG='1.13 1.13 1.17 1.20 null'           # canonico: 4 elegiveis (DS-160); stale conta 5
AD_CTRL='1.20 1.30 1.30'                      # 3 elegiveis, stale JA bate com o canonico

# 1. O oraculo distingue as quatro grandezas do caso: `0.93` (stale, descartado), `1.16`
#    (canonico, efetivamente aplicado), `1.15` (razao bruta — NUNCA pode aparecer como aplicado) e
#    a recusa indevida de todo fator (NAO pode sair `null` com o canonico `fator_ativo: true`).
AD_INTEG_CALC="$(ad_num "$AD_INTEG" 5 0.93 true)"
[ "$AD_INTEG_CALC" = '4 1.16 true true 1.16 recomputado' ]; ad_rc=$?
afirma "ad1-oraculo-distingue-stale-canonico-e-razao-bruta" "$ad_rc" \
  "calculado=[$AD_INTEG_CALC] — 0,93 descartado, 1,16 aplicado (nunca 1,15), fator nao recusado"

# 1b. O outro cenario do PR#10: stale conta nulas como zero e LIGA o fator (2 elegiveis < 3); o
#     canonico desliga. Sem conferencia, o fator errado ficaria ligado sobre 2 desvios reais.
AD_API_CALC="$(ad_num "$AD_API" 4 0.63 true)"
[ "$AD_API_CALC" = '2 1.25 false true null nenhum — canônico sem fator ativo' ]; ad_rc=$?
afirma "ad1b-oraculo-desliga-fator-quando-canonico-tem-menos-de-3" "$ad_rc" "calculado=[$AD_API_CALC]"

# 1c. E quando o bloco gravado JA bate com o canonico, nao ha divergencia nenhuma: a origem e
#     `persistido`, sem qualquer recomputo — a conferencia nao inventa divergencia onde nao ha.
AD_CTRL_CALC="$(ad_num "$AD_CTRL" 3 1.27 true)"
[ "$AD_CTRL_CALC" = '3 1.27 true false 1.27 persistido' ]; ad_rc=$?
afirma "ad1c-sem-divergencia-origem-e-persistido" "$ad_rc" "calculado=[$AD_CTRL_CALC]"

# A bateria, por ARVORE: a real roda em "$SK" e cada mutante roda a MESMA bateria numa copia.
ad_caso() { # ad_caso <caso> <dir> -> 0 se o caso PASSA naquela arvore
  local c="$1" d="$2"
  case "$c" in
    # O leitor confere o bloco persistido contra o canonico antes de aplicar — nao aplica as cegas.
    ad_conferencia_contra_canonico)
      ad_lit "$d/references/07-estimativa.md" "$AD_LIT_CONFERE_07" \
             "$d/references/00-schema.md"     "$AD_LIT_CONFERE_00" ;;
    # A divergencia, quando existe, vai declarada na saida — nunca escondida pelo recomputo.
    ad_divergencia_declarada_na_saida)
      ad_lit "$d/references/07-estimativa.md" "$AD_LIT_DIVERGE_07" \
             "$d/references/00-schema.md"     "$AD_LIT_DIVERGE_00" ;;
    # A F3.5 so le; a cura do bloco calibracao fica para o fechamento (F6).
    ad_f35_nunca_escreve_historico)
      ad_lit "$d/references/07-estimativa.md"     "$AD_LIT_PROIBE_07" \
             "$d/references/00-schema.md"         "$AD_LIT_PROIBE_00" \
             "$d/assets/TEMPLATE-HISTORICO.md"    "$AD_LIT_PROIBE_HIST" ;;
    # `fator_correcao_aplicado`/a saida marcam a ORIGEM do fator efetivamente aplicado — as duas
    # palavras, persistido e recomputado, tem de aparecer: apagar uma delas quebra o par.
    ad_origem_do_fator_declarada)
      ad_lit "$d/references/07-estimativa.md" "$AD_LIT_CALIBRACAO_07A" \
             "$d/references/07-estimativa.md" "$AD_LIT_CALIBRACAO_07B" \
             "$d/references/00-schema.md"     "$AD_LIT_CALIBRACAO_00A" \
             "$d/references/00-schema.md"     "$AD_LIT_CALIBRACAO_00B" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AD_LIT_CALIBRACAO_TMPL" ;;
    # O rotulo do campo de prosa e "Origem da calibração", nunca "Origem do fator" — um dos tres
    # estados nao e origem de fator nenhum.
    ad_rotulo_origem_da_calibracao)
      ad_lit "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AD_LIT_CALIBRACAO_TMPL" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AD_LIT_ROTULO_ANTIGO_TMPL" ;;
    # Os TRES estados de "Divergência encontrada": confere, diverge com valores, e o terceiro —
    # HISTORICO.md ausente, sem bloco `calibracao` nenhum para comparar.
    ad_tres_estados_divergencia)
      ad_lit "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AD_LIT_DIVERGE_AUSENTE_TMPL" \
             "$d/references/07-estimativa.md"   "$AD_LIT_DIVERGE_AUSENTE_07" \
             "$d/references/00-schema.md"       "$AD_LIT_DIVERGE_AUSENTE_00" ;;
    # Divergencia detectada reduz o teto de confianca a `media`, mesmo com fator canonico ativo.
    ad_divergencia_reduz_confianca)
      ad_lit "$d/references/07-estimativa.md" "$AD_LIT_CONFIANCA_07" \
             "$d/references/00-schema.md"     "$AD_LIT_CONFIANCA_00" ;;
    # O recomputo da divergencia nunca parte da razao bruta `real / estimado_media` — so dos
    # `desvio` ja persistidos (a mesma fronteira da DS-162, aplicada ao caso da divergencia).
    ad_nunca_razao_bruta_na_divergencia)
      ad_lit "$d/references/07-estimativa.md" "$AD_LIT_RAZAO_07" \
             "$d/references/00-schema.md"     "$AD_LIT_RAZAO_00" ;;
    # O limiar do canonico recomputado continua 3 (DS-162/DS-164) — a divergencia corrige o
    # CONJUNTO lido, nunca o numero do limiar.
    ad_limiar_tres_no_canonico)
      ad_lit "$d/references/00-schema.md" "$AD_LIT_LIMIAR_00" ;;
    # A DS-165 fica registrada, append-only, citando divergencia, canonico e recomputo.
    ad_ds165_registrada)
      local v; v="$(grep -F '| DS-165 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
      [ -n "$v" ] && printf '%s' "$v" | grep -qiF 'diverg' \
        && printf '%s' "$v" | grep -qiF 'canônic' \
        && printf '%s' "$v" | grep -qiF 'recomputad' ;;
    # O TEMPLATE-ESTIMATIVA.md NAO pode voltar a dizer que o fator e sempre o persistido copiado
    # as cegas — a frase que contradizia a conferencia da DS-165 no paragrafo vizinho.
    ad_fator_nao_e_sempre_persistido)
      ad_lit "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AD_LIT_CANONICO_VIGENTE_TMPL" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AD_LIT_SEMPRE_PERSISTIDO_TMPL" ;;
    # O contrato define os TRES estados da origem — persistido, recomputado, e `nenhum — canonico
    # sem fator ativo` —, e o terceiro vale mesmo quando o bloco STALE divergente MENTE que tem
    # fator ativo (a fixture `api`: canonico desliga, stale divergente dizia `fator_ativo: true`).
    # So dois estados, ou o terceiro sem essa ressalva, obriga a inventar uma origem para um fator
    # que nao existe.
    ad_terceiro_estado_sem_fator_ativo)
      ad_lit "$d/references/07-estimativa.md"     "$AD_LIT_SEM_FATOR_07" \
             "$d/references/00-schema.md"         "$AD_LIT_SEM_FATOR_00" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md"   "$AD_LIT_SEM_FATOR_TMPL" \
             "$d/references/07-estimativa.md"     "$AD_LIT_SEM_FATOR_MESMO_SE_STALE_MENTE" ;;
    *) return 1 ;;
  esac
}
AD_CASOS="ad_conferencia_contra_canonico ad_divergencia_declarada_na_saida
ad_f35_nunca_escreve_historico ad_origem_do_fator_declarada ad_divergencia_reduz_confianca
ad_nunca_razao_bruta_na_divergencia ad_limiar_tres_no_canonico ad_ds165_registrada
ad_fator_nao_e_sempre_persistido ad_terceiro_estado_sem_fator_ativo
ad_rotulo_origem_da_calibracao ad_tres_estados_divergencia"

# 2 a 9. A bateria lida das referencias reais.
for ad_c in $AD_CASOS; do
  ad_nome="$(printf '%s' "$ad_c" | tr '_' '-')"
  ad_caso "$ad_c" "$SK"; ad_rc=$?
  afirma "$ad_nome" "$ad_rc" "lido da arvore do contrato em $SK"
done

# 10. Mutantes. Mesma mecanica das secoes AB/AC: cada um nasce numa COPIA da skill, e so conta como
#     morto quando TODOS os casos nomeados reprovam.
ADW="$(mktemp -d)"
ad_copia() { rm -rf "$ADW/$1"; mkdir -p "$ADW/$1"; cp -R "$SK/." "$ADW/$1/"; printf '%s' "$ADW/$1"; }
ad_muta() { # ad_muta <dir> <arquivo-rel> <expressao sed>
  [ -f "$1/$2" ] || return 1
  sed "$3" "$1/$2" > "$ADW/.sed" && cat "$ADW/.sed" > "$1/$2" || return 1   # sem `sed -i` (so GNU)
  ! cmp -s "$SK/$2" "$1/$2"
}
ad_mata() { local c; for c in $AD_CASOS; do ad_caso "$c" "$1" || { printf '%s' "$c"; return; }; done; }
ad_mutante() { # ad_mutante <nome> <rc da geracao> <dir> <caso que TEM de matar>...
  local nome="$1" rcg="$2" d="$3" c vivos=""; shift 3
  if [ "$rcg" -eq 0 ]; then for c in "$@"; do ad_caso "$c" "$d" && vivos="$vivos$c "; done; fi
  [ "$rcg" -eq 0 ] && [ -z "$vivos" ]; local rc=$?
  afirma "$nome" "$rc" "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rcg)"
}
ad_equivalente() { # ad_equivalente <nome> <rc da geracao> <dir> — equivalente nao pode morrer
  local nome="$1" rcg="$2" d="$3" m=""
  [ "$rcg" -eq 0 ] && m="$(ad_mata "$d")"
  [ "$rcg" -eq 0 ] && [ -z "$m" ]; local rc=$?
  afirma "$nome" "$rc" "equivalente, nao conta como morto; reprovou=[${m:-nenhum}] (rc geracao=$rcg)"
}
AD_CTL="$(ad_copia controle)"
AD_K="$(ad_mata "$AD_CTL")"; [ -z "$AD_K" ]; ad_rc=$?
afirma "adm-controle-copia-intacta-sobrevive" "$ad_rc" "${AD_K:-nenhum caso reprova a copia sem mutacao}"

# m1 — aplicar o bloco stale sem conferir: apaga o marcador da CONFERENCIA no Passo 1, voltando
#      a ler "como esta, sem recalcular nada" — exatamente o HEAD que o PR#10 reportou.
AD_M="$(ad_copia m1)"
ad_muta "$AD_M" references/07-estimativa.md \
  's/Confira esse canônico contra o bloco `calibracao` gravado no `HISTORICO\.md`\.//'
ad_mutante "adm-mutante-1-aplica-stale-sem-conferir" $? "$AD_M" \
  ad_conferencia_contra_canonico

# m2 — recomputar sempre e ocultar a divergencia: apaga so o marcador que obriga DECLARAR na saida.
AD_M="$(ad_copia m2)"
ad_muta "$AD_M" references/07-estimativa.md \
  's/Declare na saída, nesta task e no total, a divergência encontrada/Resolva a divergência em silêncio/'
ad_mutante "adm-mutante-2-oculta-divergencia" $? "$AD_M" \
  ad_divergencia_declarada_na_saida

# m3 — recusar todo fator na divergencia: apaga o marcador que nomeia `recomputado` como origem
#      possivel, como se divergencia so pudesse zerar o fator (nunca recompute-lo).
AD_M="$(ad_copia m3)"
ad_muta "$AD_M" references/07-estimativa.md \
  's/a origem da calibração é `recomputado`/o fator fica `null`/'
ad_mutante "adm-mutante-3-recusa-fator-na-divergencia" $? "$AD_M" \
  ad_origem_do_fator_declarada

# m4 — recomputar a partir da razao bruta: apaga o marcador que proibe `real / estimado_media`
#      no recomputo da divergencia.
AD_M="$(ad_copia m4)"
ad_muta "$AD_M" references/07-estimativa.md \
  's/ — nunca de `real \/ estimado_media`, que é a razão bruta e não o que a calibração agrega//'
ad_mutante "adm-mutante-4-recomputa-de-razao-bruta" $? "$AD_M" \
  ad_nunca_razao_bruta_na_divergencia

# m5 — a F3.5 escreve/migra o HISTORICO.md: apaga o marcador da proibicao, confundindo fase de
#      leitura com fase de fechamento.
AD_M="$(ad_copia m5)"
ad_muta "$AD_M" references/07-estimativa.md \
  's/\*\*A F3\.5 nunca escreve nem migra o `HISTORICO\.md`\.\*\* //'
ad_mutante "adm-mutante-5-f35-escreve-historico" $? "$AD_M" \
  ad_f35_nunca_escreve_historico

# m6 — limiar 2 no canonico recomputado: apaga o marcador "3 ou mais entradas elegíveis" do
#      schema — o mesmo defeito da AC, agora sobre o numero que a divergencia tem de respeitar.
AD_M="$(ad_copia m6)"
ad_muta "$AD_M" references/00-schema.md 's/3 ou mais entradas elegíveis/2 ou mais entradas elegíveis/g'
ad_mutante "adm-mutante-6-limiar-dois-no-recomputo" $? "$AD_M" \
  ad_limiar_tres_no_canonico

# m7 — a DS-165 apagada do registro: a regra fica nas referencias e perde o porque, exatamente
#      como a m9 da AC fez com a DS-162.
AD_M="$(ad_copia m7)"
ad_muta "$AD_M" DECISOES-DA-SKILL.md '/^| DS-165 |/d'
ad_mutante "adm-mutante-7-ds165-apagada" $? "$AD_M" \
  ad_ds165_registrada

# m8 — regressao ao "sempre persistido": o TEMPLATE-ESTIMATIVA.md volta a afirmar, sem condicao
#      nenhuma, que o fator e o persistido copiado como esta — a contradicao que a auditoria achou
#      entre o paragrafo do fator e o paragrafo vizinho da conferencia (DS-165).
AD_M="$(ad_copia m8)"
ad_muta "$AD_M" assets/TEMPLATE-ESTIMATIVA.md \
  's/O fator é o `desvio_medio` do \*\*canônico vigente\*\* daquele tipo (DS-165, ver parágrafo seguinte) — persistido quando o bloco `calibracao` confere, recomputado quando diverge —, nunca o bloco gravado copiado às cegas/O fator é o `desvio_medio` persistido do tipo, copiado do `HISTORICO.md` como está/'
ad_mutante "adm-mutante-8-template-volta-a-sempre-persistido" $? "$AD_M" \
  ad_fator_nao_e_sempre_persistido

# m9 — colapsa o terceiro estado: a origem `nenhum — canônico sem fator ativo` vira
#      `recomputado` em 07-estimativa.md, como se o canonico sem fator ativo tivesse que forcar
#      uma das duas origens antigas — a exata contradicao que a fixture `api` expos (fator
#      `null` com origem `recomputado` nao faz sentido nenhum).
AD_M="$(ad_copia m9)"
ad_muta "$AD_M" references/07-estimativa.md \
  's/nenhum — canônico sem fator ativo/recomputado/g'
ad_mutante "adm-mutante-9-colapsa-terceiro-estado" $? "$AD_M" \
  ad_terceiro_estado_sem_fator_ativo

# m10 — reverte o rotulo do campo de prosa para "Origem do fator": presume que todo estado e
#       origem de um fator que existe, o que e falso para o terceiro estado.
AD_M="$(ad_copia m10)"
ad_muta "$AD_M" assets/TEMPLATE-ESTIMATIVA.md \
  's/Origem da calibração (DS-165)/Origem do fator (DS-165)/'
ad_mutante "adm-mutante-10-reverte-rotulo-origem-do-fator" $? "$AD_M" \
  ad_rotulo_origem_da_calibracao

# m11 — colapsa o terceiro estado de "Divergência encontrada": sem HISTORICO.md volta a nao ter
#       um marcador proprio, como se a ausencia do arquivo fosse so mais um caso de "confere".
AD_M="$(ad_copia m11)"
ad_muta "$AD_M" assets/TEMPLATE-ESTIMATIVA.md \
  's/não se aplica — HISTORICO\.md ausente/nenhuma — o bloco `calibracao` gravado confere com o canônico/'
ad_mutante "adm-mutante-11-colapsa-tres-estados-divergencia" $? "$AD_M" \
  ad_tres_estados_divergencia

# Equivalentes: mudam a forma e nao a regra (texto FORA de todo marcador), e por isso NAO podem
# morrer — um discriminador por marcador que dependesse de frase vizinha passaria por sensivel
# sem ser.
AD_M="$(ad_copia e1)"
ad_muta "$AD_M" references/07-estimativa.md \
  's/herança de uma leitura que contava a entrada/herança de uma leitura antiga que contava a entrada/'
ad_equivalente "ade-equivalente-1-reformulacao-do-exemplo" $? "$AD_M"
AD_M="$(ad_copia e2)"
ad_muta "$AD_M" assets/TEMPLATE-ESTIMATIVA.md \
  's/o canônico recomputado das entradas elegíveis é <valor canônico>/o canônico vigente das entradas elegíveis é <valor canônico>/'
ad_equivalente "ade-equivalente-2-reformulacao-do-placeholder" $? "$AD_M"
rm -rf "$ADW"

echo "== AE. a estimativa declara o fator por tipo_task, nunca um fator unico sobre mistura (PR#10 r4161807465) =="
# O TEMPLATE-ESTIMATIVA.md so tinha `fator_correcao_aplicado` (DS-46/DS-165): um UNICO numero ou
# null para o trabalho inteiro. Um trabalho com tasks de dois tipos — um com fator ativo, outro
# sem, ou dois tipos com fatores ativos DIFERENTES — nao tem como representar isso num escalar
# sem inventar (media, maior, ultimo tipo lido...). A DS-166 acrescenta `calibracao_por_tipo`:
# uma linha por `tipo_task` PRESENTE no trabalho, em ordem lexical, cada uma com seu fator (ou
# null), origem e divergencia (DS-165, agora por tipo). O escalar legado so sobrevive puro
# (numero ou null) quando todos os tipos presentes concordam; qualquer mistura grava o literal
# `por_tipo`, e um consumidor que nao conhece a colecao nova falha fechado — nunca aproxima.
AE_SK="$SK"
AE_SCH="$AE_SK/references/00-schema.md"
AE_EST="$AE_SK/references/07-estimativa.md"
AE_TPL="$AE_SK/assets/TEMPLATE-ESTIMATIVA.md"

# O ORACULO do escalar: dado o conjunto de fatores (um por tipo PRESENTE, "null" quando o tipo
# nao tem fator ativo), devolve o que `fator_correcao_aplicado` tem de gravar.
ae_escalar() { # ae_escalar <fator1> [<fator2> ...]
  awk -v lista="$*" '
    BEGIN {
      n = split(lista, v, / +/)
      ativos = 0; distintos = 0; primeiro = ""
      for (i = 1; i <= n; i++) {
        if (v[i] == "null") { nulos++; continue }
        ativos++
        if (primeiro == "") primeiro = v[i]
        else if (v[i] != primeiro) distintos = 1
      }
      if (ativos == 0) { print "null"; exit }
      if (ativos == n && distintos == 0) { print primeiro; exit }
      print "por_tipo"
    }'
}
[ "$(ae_escalar 1.16 null)" = "por_tipo" ]; afirma "ae1-oraculo-ativo-e-inativo-e-por-tipo" $? \
  "fator presente + tipo sem fator -> mistura"
[ "$(ae_escalar 1.16 1.25)" = "por_tipo" ]; afirma "ae2-oraculo-dois-ativos-distintos-e-por-tipo" $? \
  "dois fatores ativos diferentes -> mistura"
[ "$(ae_escalar 1.16 1.16)" = "1.16" ]; afirma "ae3-oraculo-mesmo-ativo-em-todos-e-escalar" $? \
  "todos os tipos com o mesmo fator ativo -> escalar numerico igual ao fator"
[ "$(ae_escalar null null)" = "null" ]; afirma "ae4-oraculo-nenhum-ativo-e-null" $? \
  "nenhum tipo com fator ativo -> escalar null"
[ "$(ae_escalar 1.16)" = "1.16" ]; afirma "ae5-oraculo-um-unico-tipo-ativo-e-o-proprio-fator" $? \
  "um unico tipo presente, ativo -> escalar e o fator dele, nao e mistura"

# Detector por marcador literal, mesma tecnica e mesma justificativa da secao AD (ad_lit): string
# exata do contrato, nunca regex de linguagem natural, para nao ter falso negativo acentuado.
AE_LIT_SCH_CAMPO='`calibracao_por_tipo`'
AE_LIT_SCH_UMALINHA='exatamente uma linha por `tipo_task` presente, em ordem lexical'
AE_LIT_SCH_ESCALAR_NUM='escalar numérico somente quando TODOS os tipos presentes recebem o MESMO fator ativo'
AE_LIT_SCH_ESCALAR_NULL='escalar `null` somente quando NENHUM tipo presente recebe fator ativo'
AE_LIT_SCH_POR_TIPO='qualquer mistura — fator ativo e inativo, ou fatores ativos diferentes — grava `fator_correcao_aplicado: por_tipo`'
# A DS-172 trocou o SENTIDO desta regra: o proibido e `1.00` NO LUGAR DE `null` (o disfarce da
# DS-46), nunca o valor `1.00` em si — que, medido, e fator legitimo e obrigatorio. O marcador
# acompanha: a secao AK e que julga as duas metades da regra nova.
AE_LIT_SCH_NUNCA_100='Nenhum item de `calibracao_por_tipo` usa `1.00` no lugar de `null`'
AE_LIT_SCH_FAILCLOSED='declara a estimativa indisponível e não a usa — nunca coerção, média ou escolha arbitrária'
AE_LIT_TPL_CAMPO='calibracao_por_tipo:'
AE_LIT_TPL_TABELA='Calibração por tipo de task'
AE_LIT_TPL_PORTASK_COLUNA='Fator aplicado'
AE_LIT_EST_PISO_POR_TIPO='`fator(t)` vem do item de `calibracao_por_tipo` cujo `tipo_task` é o de `t`'
AE_LIT_EST_FAILCLOSED='declara a estimativa indisponível e não a usa — nunca coerção, média ou escolha arbitrária'
# Os valores de `origem`/`divergencia` em `calibracao_por_tipo` sao os MESMOS estados da DS-165
# (canonico, acentuados) — nunca uma forma ASCII sem acento inventada so para este campo novo.
# Marcador POSITIVO e a linha exata do YAML (exemplo real e template), e NEGATIVO proibe a forma
# sem acento aparecer em lugar nenhum dos dois arquivos (auditoria Codex, incompatibilidade de
# enum achada entre o exemplo e a regra canonica DS-165/DS-166).
AE_LIT_SCH_ORIGEM_FRONT='origem: nenhum — canônico sem fator ativo'
AE_LIT_SCH_DIVERG_FRONT='divergencia: não se aplica — HISTORICO.md ausente'
AE_LIT_TPL_ORIGEM_FRONT='origem: {{persistido | recomputado | nenhum — canônico sem fator ativo}}'
AE_LIT_TPL_DIVERG_FRONT='divergencia: {{confere | diverge com valores | não se aplica — HISTORICO.md ausente}}'
AE_LIT_PROIBE_CANONICO_SEM_ACENTO='!nenhum — canonico sem fator ativo'
AE_LIT_PROIBE_DIVERGE_SEM_ACENTO='!nao se aplica — HISTORICO.md ausente'

ae_caso() { # ae_caso <caso> <dir> -> 0 se o caso PASSA naquela arvore
  local c="$1" d="$2"
  case "$c" in
    # A colecao canonica existe no contrato e na saida, uma linha por tipo, ordem lexical.
    ae_colecao_por_tipo_no_contrato)
      ad_lit "$d/references/00-schema.md" "$AE_LIT_SCH_CAMPO" \
             "$d/references/00-schema.md" "$AE_LIT_SCH_UMALINHA" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AE_LIT_TPL_CAMPO" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AE_LIT_TPL_TABELA" ;;
    # A regra dos tres estados do escalar legado esta escrita no schema.
    ae_regra_do_escalar_legado)
      ad_lit "$d/references/00-schema.md" "$AE_LIT_SCH_ESCALAR_NUM" \
             "$d/references/00-schema.md" "$AE_LIT_SCH_ESCALAR_NULL" \
             "$d/references/00-schema.md" "$AE_LIT_SCH_POR_TIPO" ;;
    # `1.00` nunca substitui `null`, nem no escalar nem por tipo (DS-46, com o sentido que a
    # DS-172 fixou: o disfarce e que e proibido, nao o numero).
    ae_nunca_100_por_tipo)
      ad_lit "$d/references/00-schema.md" "$AE_LIT_SCH_NUNCA_100" ;;
    # Consumidor legado que nao reconhece calibracao_por_tipo falha fechado.
    ae_fail_closed_consumidor_legado)
      ad_lit "$d/references/00-schema.md" "$AE_LIT_SCH_FAILCLOSED" \
             "$d/references/07-estimativa.md" "$AE_LIT_EST_FAILCLOSED" ;;
    # A tabela "Por task" identifica o fator/estado aplicado a cada task, nao so o tipo.
    ae_tabela_por_task_identifica_fator)
      ad_lit "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AE_LIT_TPL_PORTASK_COLUNA" ;;
    # O piso aditivo (DS-163) usa o fator do TIPO de cada task, lido da colecao por tipo.
    ae_piso_aditivo_por_tipo)
      ad_lit "$d/references/07-estimativa.md" "$AE_LIT_EST_PISO_POR_TIPO" ;;
    # origem/divergencia de calibracao_por_tipo usam as formas CANONICAS acentuadas da DS-165,
    # no exemplo do schema e no template, e a forma sem acento nunca aparece em nenhum dos dois.
    ae_formas_acentuadas_no_frontmatter)
      ad_lit "$d/references/00-schema.md"       "$AE_LIT_SCH_ORIGEM_FRONT" \
             "$d/references/00-schema.md"       "$AE_LIT_SCH_DIVERG_FRONT" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AE_LIT_TPL_ORIGEM_FRONT" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AE_LIT_TPL_DIVERG_FRONT" \
             "$d/references/00-schema.md"       "$AE_LIT_PROIBE_CANONICO_SEM_ACENTO" \
             "$d/references/00-schema.md"       "$AE_LIT_PROIBE_DIVERGE_SEM_ACENTO" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AE_LIT_PROIBE_CANONICO_SEM_ACENTO" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AE_LIT_PROIBE_DIVERGE_SEM_ACENTO" ;;
    # A DS-166 fica registrada, append-only, citando a mistura e o literal por_tipo.
    ae_ds166_registrada)
      local v; v="$(grep -F '| DS-166 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
      [ -n "$v" ] && printf '%s' "$v" | grep -qiF 'por_tipo' \
        && printf '%s' "$v" | grep -qiF 'mistura' ;;
    *) return 1 ;;
  esac
}
AE_CASOS="ae_colecao_por_tipo_no_contrato ae_regra_do_escalar_legado ae_nunca_100_por_tipo
ae_fail_closed_consumidor_legado ae_tabela_por_task_identifica_fator ae_piso_aditivo_por_tipo
ae_ds166_registrada ae_formas_acentuadas_no_frontmatter"

for ae_c in $AE_CASOS; do
  ae_nome="$(printf '%s' "$ae_c" | tr '_' '-')"
  ae_caso "$ae_c" "$AE_SK"; ae_rc=$?
  afirma "$ae_nome" "$ae_rc" "lido da arvore do contrato em $AE_SK"
done

# DS-166 registrada, append-only (nao reescreve DS-165): nao reafirma pela ae_caso de novo (ja
# roda no loop acima), so confere a DS-165 anterior continua intacta.
grep -qF '| DS-165 |' "$AE_SK/DECISOES-DA-SKILL.md"
afirma "ae-ds165-preservada-append-only" $? "DS-165 continua no arquivo, intacta"

# Mutantes: a mesma mecanica de AD/AC, numa copia da arvore.
AEW="$(mktemp -d)"
ae_copia() { rm -rf "$AEW/$1"; mkdir -p "$AEW/$1"; cp -R "$AE_SK/." "$AEW/$1/"; printf '%s' "$AEW/$1"; }
ae_muta() { # sem `sed -i` (so GNU): arquivo temporario e `cat` por cima, que mantem o modo
  [ -f "$1/$2" ] || return 1
  sed "$3" "$1/$2" > "$AEW/.sed" && cat "$AEW/.sed" > "$1/$2" || return 1
  ! cmp -s "$AE_SK/$2" "$1/$2"
}
ae_mata() { local c; for c in $AE_CASOS; do ae_caso "$c" "$1" || { printf '%s' "$c"; return; }; done; }
ae_mutante() { # ae_mutante <nome> <rc da geracao> <dir> <caso que TEM de matar>...
  local nome="$1" rcg="$2" d="$3" c vivos=""; shift 3
  if [ "$rcg" -eq 0 ]; then for c in "$@"; do ae_caso "$c" "$d" && vivos="$vivos$c "; done; fi
  [ "$rcg" -eq 0 ] && [ -z "$vivos" ]; local rc=$?
  afirma "$nome" "$rc" "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rcg)"
}
AE_CTL="$(ae_copia controle)"
AE_K="$(ae_mata "$AE_CTL")"; [ -z "$AE_K" ]; ae_rc=$?
afirma "aem-controle-copia-intacta-sobrevive" "$ae_rc" "${AE_K:-nenhum caso reprova a copia sem mutacao}"

# m1 — remove a colecao canonica do schema: so o escalar legado sobra.
AE_M="$(ae_copia m1)"
ae_muta "$AE_M" references/00-schema.md "s/${AE_LIT_SCH_CAMPO}//"
ae_mutante "aem-mutante-1-remove-colecao-do-schema" $? "$AE_M" \
  ae_colecao_por_tipo_no_contrato

# m2 — remove a regra do escalar numerico (deixa so null/por_tipo descritos).
AE_M="$(ae_copia m2)"
ae_muta "$AE_M" references/00-schema.md "s/${AE_LIT_SCH_ESCALAR_NUM}//"
ae_mutante "aem-mutante-2-remove-regra-escalar-numerico" $? "$AE_M" \
  ae_regra_do_escalar_legado

# m3 — apaga a proibicao do disfarce por tipo: `1.00` voltaria a poder substituir `null`.
AE_M="$(ae_copia m3)"
ae_muta "$AE_M" references/00-schema.md "s/${AE_LIT_SCH_NUNCA_100}//"
ae_mutante "aem-mutante-3-permite-100-no-lugar-de-null-por-tipo" $? "$AE_M" \
  ae_nunca_100_por_tipo

# m4 — apaga a instrucao de falha fechada para consumidor legado (ex.: ele poderia tentar media).
AE_M="$(ae_copia m4)"
ae_muta "$AE_M" references/00-schema.md "s/${AE_LIT_SCH_FAILCLOSED}//"
ae_mutante "aem-mutante-4-remove-fail-closed" $? "$AE_M" \
  ae_fail_closed_consumidor_legado

# m5 — apaga a coluna de fator aplicado da tabela "Por task" (so sobra o tipo, sem o fator/estado).
AE_M="$(ae_copia m5)"
ae_muta "$AE_M" assets/TEMPLATE-ESTIMATIVA.md "s/${AE_LIT_TPL_PORTASK_COLUNA}//"
ae_mutante "aem-mutante-5-remove-coluna-fator-por-task" $? "$AE_M" \
  ae_tabela_por_task_identifica_fator

# m6 — colapsa o piso aditivo de volta a um fator unico do conjunto (apaga o vinculo por tipo).
AE_M="$(ae_copia m6)"
ae_muta "$AE_M" references/07-estimativa.md "s/${AE_LIT_EST_PISO_POR_TIPO}//"
ae_mutante "aem-mutante-6-piso-sem-vinculo-por-tipo" $? "$AE_M" \
  ae_piso_aditivo_por_tipo

# m7 — DS-166 apagada do registro.
AE_M="$(ae_copia m7)"
ae_muta "$AE_M" DECISOES-DA-SKILL.md '/^| DS-166 |/d'
ae_mutante "aem-mutante-7-ds166-apagada" $? "$AE_M" \
  ae_ds166_registrada

# m8 — corrompe a forma acentuada do exemplo no schema de volta para ASCII sem acento, a
# incompatibilidade de enum que a auditoria Codex achou entre o exemplo e a regra canonica.
AE_M="$(ae_copia m8)"
ae_muta "$AE_M" references/00-schema.md \
  's/origem: nenhum — canônico sem fator ativo/origem: nenhum — canonico sem fator ativo/'
ae_mutante "aem-mutante-8-origem-sem-acento-no-exemplo" $? "$AE_M" \
  ae_formas_acentuadas_no_frontmatter

rm -rf "$AEW"

echo "== AF. PR#11 r4164972140/r4164972143: agregacao corrigida pelo fator (DS-167) e escalar legado condicional (DS-168) =="
# r4164972143 (Logic error): a formula publicada de media_conjunto/desvio_conjunto somava os
# valores CRUS de media_task/desvio_padrao_task — so o piso_conjunto multiplicava por fator(t).
# `max`, que nao passa pelo piso, saia sem fator nenhum: fator aplicado so parcialmente. A DS-167
# corrige multiplicando por fator(t) DENTRO da soma/quadratura, nos dois arquivos que publicam a
# formula (07-estimativa.md e TEMPLATE-ESTIMATIVA.md) — sem renomear media_task/desvio_padrao_task
# (DS-162 continua intacta).
# r4164972140 (Api mismatch): o bloco "escalar legado" exigia Origem/Divergencia (DS-165) como
# UM valor do trabalho inteiro, mas com mais de um tipo_task (DS-166) nao ha agregado — cada tipo
# tem a sua. A DS-168 torna as duas linhas condicionais ao trabalho ter um unico tipo_task, e
# manda OMITI-LAS (nunca inventar "misto") quando ha mais de um.
AF_SK="$SK"
AF_LIT_AGREG_EST='media_conjunto = soma de ( media_task(t) * fator(t) )'
AF_LIT_AGREG_TPL='media_conjunto = soma de ( media_task(t) * fator(t) )'
AF_LIT_QUAD_EST='desvio_conjunto = raiz_quadrada( soma de ( desvio_padrao_task(t) * fator(t) )^2 )'
AF_LIT_QUAD_TPL='desvio_conjunto = raiz_quadrada( soma de ( desvio_padrao_task(t) * fator(t) )^2 )'
AF_LIT_DS167_EST='A agregação soma e quadratura já corrigidos, nunca os valores crus (DS-167)'
AF_LIT_DS167_TPL='A soma e a quadratura já corrigem pelo fator, nunca os valores crus (DS-167)'
AF_LIT_CONDICIONAL_UM='Com um único `tipo_task` presente neste trabalho, declare também'
AF_LIT_CONDICIONAL_MAIS='não existe origem nem divergência agregada para o trabalho inteiro'
AF_LIT_FAILCLOSED_ESCALAR='nunca escolha uma entre os tipos, nunca escreva "misto" ou "vários" no lugar de um valor do enum'
AF_LIT_PASSO9_DS168='não há origem nem divergência agregada do trabalho (DS-168)'

af_caso() { # af_caso <caso> <dir> -> 0 se o caso PASSA naquela arvore
  local c="$1" d="$2"
  case "$c" in
    # A soma e a quadratura multiplicam por fator(t) DENTRO da formula, nos dois arquivos.
    af_agregacao_corrigida_pelo_fator)
      ad_lit "$d/references/07-estimativa.md"   "$AF_LIT_AGREG_EST" \
             "$d/references/07-estimativa.md"   "$AF_LIT_QUAD_EST" \
             "$d/references/07-estimativa.md"   "$AF_LIT_DS167_EST" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AF_LIT_AGREG_TPL" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AF_LIT_QUAD_TPL" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AF_LIT_DS167_TPL" ;;
    # media_task/desvio_padrao_task continuam os simbolos crus do Passo 4 (DS-162 intacta): a
    # formula crua NUNCA desaparece, so a formula do CONJUNTO passa a multiplicar por fator(t).
    af_simbolos_crus_preservados)
      ad_lit "$d/references/07-estimativa.md"   'media_task = (o + 4m + p) / 6' \
             "$d/references/07-estimativa.md"   'desvio_padrao_task = (p - o) / 6' \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" 'media_task = (o + 4m + p) / 6' \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" 'desvio_padrao_task = (p - o) / 6' ;;
    # O escalar legado so exige Origem/Divergencia quando ha um UNICO tipo_task; com mais de um,
    # manda OMITIR — nunca agregar.
    af_escalar_legado_condicional)
      ad_lit "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AF_LIT_CONDICIONAL_UM" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AF_LIT_CONDICIONAL_MAIS" \
             "$d/assets/TEMPLATE-ESTIMATIVA.md" "$AF_LIT_FAILCLOSED_ESCALAR" \
             "$d/references/07-estimativa.md"   "$AF_LIT_PASSO9_DS168" ;;
    # DS-167 e DS-168 ficam registradas, append-only, sem reescrever a DS-166.
    af_ds167_ds168_registradas)
      local v167 v168
      v167="$(grep -F '| DS-167 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
      v168="$(grep -F '| DS-168 |' "$d/DECISOES-DA-SKILL.md" 2>/dev/null)"
      [ -n "$v167" ] && [ -n "$v168" ] \
        && printf '%s' "$v167" | grep -qiF 'parcialmente' \
        && printf '%s' "$v168" | grep -qiF 'omitid' ;;
    *) return 1 ;;
  esac
}
AF_CASOS="af_agregacao_corrigida_pelo_fator af_simbolos_crus_preservados
af_escalar_legado_condicional af_ds167_ds168_registradas"

for af_c in $AF_CASOS; do
  af_nome="$(printf '%s' "$af_c" | tr '_' '-')"
  af_caso "$af_c" "$AF_SK"; af_rc=$?
  afirma "$af_nome" "$af_rc" "lido da arvore do contrato em $AF_SK"
done
grep -qF '| DS-166 |' "$AF_SK/DECISOES-DA-SKILL.md"
afirma "af-ds166-preservada-append-only" $? "DS-166 continua no arquivo, intacta"

AFW="$(mktemp -d)"
af_copia() { rm -rf "$AFW/$1"; mkdir -p "$AFW/$1"; cp -R "$AF_SK/." "$AFW/$1/"; printf '%s' "$AFW/$1"; }
af_muta() { # sem `sed -i` (so GNU): arquivo temporario e `cat` por cima, que mantem o modo
  [ -f "$1/$2" ] || return 1
  sed "$3" "$1/$2" > "$AFW/.sed" && cat "$AFW/.sed" > "$1/$2" || return 1
  ! cmp -s "$AF_SK/$2" "$1/$2"
}
af_mata() { local c; for c in $AF_CASOS; do af_caso "$c" "$1" || { printf '%s' "$c"; return; }; done; }
af_mutante() { # af_mutante <nome> <rc da geracao> <dir> <caso que TEM de matar>...
  local nome="$1" rcg="$2" d="$3" c vivos=""; shift 3
  if [ "$rcg" -eq 0 ]; then for c in "$@"; do af_caso "$c" "$d" && vivos="$vivos$c "; done; fi
  [ "$rcg" -eq 0 ] && [ -z "$vivos" ]; local rc=$?
  afirma "$nome" "$rc" "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rcg)"
}
AF_CTL="$(af_copia controle)"
AF_K="$(af_mata "$AF_CTL")"; [ -z "$AF_K" ]; af_rc=$?
afirma "afm-controle-copia-intacta-sobrevive" "$af_rc" "${AF_K:-nenhum caso reprova a copia sem mutacao}"

# m1 — volta a formula do conjunto a somar os valores CRUS (sem fator), o defeito original do
#      comentario r4164972143: max deixa de ser corrigido, so o piso continua corrigido.
AF_M="$(af_copia m1)"
af_muta "$AF_M" references/07-estimativa.md \
  's/media_conjunto  = soma de ( media_task(t) \* fator(t) )/media_conjunto  = soma das media_task/'
af_mutante "afm-mutante-1-agregacao-volta-a-somar-cru-no-07" $? "$AF_M" \
  af_agregacao_corrigida_pelo_fator

# m2 — mesma regressao, agora no TEMPLATE-ESTIMATIVA.md (o arquivo que a auditoria apontou).
AF_M="$(af_copia m2)"
af_muta "$AF_M" assets/TEMPLATE-ESTIMATIVA.md \
  's/media_conjunto  = soma de ( media_task(t) \* fator(t) )/media_conjunto  = soma das media_task/'
af_mutante "afm-mutante-2-agregacao-volta-a-somar-cru-no-template" $? "$AF_M" \
  af_agregacao_corrigida_pelo_fator

# m3 — apaga a condicao "unico tipo" do escalar legado: as duas linhas voltam a parecer sempre
#      obrigatorias, o defeito original do comentario r4164972140.
AF_M="$(af_copia m3)"
af_muta "$AF_M" assets/TEMPLATE-ESTIMATIVA.md \
  "s/${AF_LIT_CONDICIONAL_UM}/Declare sempre/"
af_mutante "afm-mutante-3-remove-condicao-unico-tipo" $? "$AF_M" \
  af_escalar_legado_condicional

# m4 — apaga a instrucao de OMITIR com mais de um tipo (o consumidor voltaria a esperar um
#      valor agregado que o contrato nao define).
AF_M="$(af_copia m4)"
af_muta "$AF_M" assets/TEMPLATE-ESTIMATIVA.md "s/${AF_LIT_CONDICIONAL_MAIS}//"
af_mutante "afm-mutante-4-remove-omissao-com-mais-de-um-tipo" $? "$AF_M" \
  af_escalar_legado_condicional

# m5 — DS-167/DS-168 apagadas do registro.
AF_M="$(af_copia m5)"
af_muta "$AF_M" DECISOES-DA-SKILL.md '/^| DS-167 |/d; /^| DS-168 |/d'
af_mutante "afm-mutante-5-ds167-ds168-apagadas" $? "$AF_M" \
  af_ds167_ds168_registradas

rm -rf "$AFW"
