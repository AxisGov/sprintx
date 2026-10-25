#!/usr/bin/env bash
#
# Secao AL da bancada: autorizacao tardia do orcamento F6, DS-175.
# Carregada por `.` de dentro da bancada.sh, no mesmo ponto e na mesma ordem: usa os
# auxiliares e o estado dela. Mora aqui porque o CodeAnt pula arquivo acima de 5.000 linhas
# ou 200 KB (expxdev, docs/superpowers/specs/2026-10-19-limites-do-codeant-emenda.md).

echo "== AL. DS-175: autorizacao tardia explicita do orcamento F6 =="
AL_SCHEMA="$SK/references/00-schema.md"
AL_PLANO="$SK/references/03-plano.md"
AL_EXEC="$SK/references/06-execucao.md"
AL_RASTRO="$SK/references/08-rastro.md"
AL_SKILL="$SK/SKILL.md"
AL_TPL="$SK/assets/TEMPLATE-PLANEJAMENTO.md"
AL_DSF="$SK/DECISOES-DA-SKILL.md"
al_tem() { grep -qF -- "$2" "$1"; }

al_tem "$AL_SCHEMA" 'As três chaves tardias existem juntas ou nenhuma existe' \
  && al_tem "$AL_SCHEMA" 'A autoridade canônica tardia é `autorizacao_tardia_f6_por`' \
  && al_tem "$AL_SCHEMA" '`orcamento_declarado_por` continua' \
  && al_tem "$AL_SCHEMA" 'pertencendo ao orçamento da F5' \
  && al_tem "$AL_SCHEMA" '`replanejamento_execucao_recusado` com motivo `orcamento_f6_nao_declarado` é o único terminal recuperável'
afirma "ds175-contrato-schema" $? "tupla all-or-none, autoridade separada e terminal exato"

al_schema_exemplo_valido() {
  local d f out rc
  d="$(mktemp -d "$K/schema-publico.XXXXXX")"
  nova_feature "$d" exportacao-csv-relatorios
  f="$d/docs/sprintx/features/exportacao-csv-relatorios/00-PLANEJAMENTO.md"
  awk '
    /^### `00-PLANEJAMENTO.md`/ { secao=1 }
    secao && /^```yaml$/ { bloco=1; next }
    bloco && /^```$/ { exit }
    bloco { print }
  ' "$AL_SCHEMA" > "$f"
  git -C "$d" add "$f" && git -C "$d" commit -q -m 'fixture: exemplo publico do planejamento' -- "$f" || return 1
  out="$(kpl "$PL" "$d" fase exportacao-csv-relatorios)"; rc=$?
  [ "$rc" -eq 0 ] && [ "$(kv "$out" fonte)" = planejamento ]
}
al_schema_exemplo_valido
afirma "ds175-schema-exemplo-executavel" $? "o YAML canonico publicado e aceito pelo leitor oficial"

al_tem "$AL_PLANO" '`replanejamento_execucao_recusado` continua terminal até uma chamada humana explícita' \
  && al_tem "$AL_PLANO" 'planejamento.sh autorizar-replanejamento-execucao <slug> <max_replanejamentos_f6> <autorizado_por>' \
  && al_tem "$AL_PLANO" 'A autorização tardia abre a rodada 1 e devolve o planejamento para F3'
afirma "ds175-contrato-plano" $? "terminal continua terminal; comando explicito retorna a F3"

al_tem "$AL_EXEC" '**Somente uma decisão humana explícita** pode autorizar o orçamento tardio da F6' \
  && al_tem "$AL_EXEC" 'autorizacao_f6=checkpoint_pendente' \
  && al_tem "$AL_EXEC" 'argumentos → congeladas/parciais → B-NN/task se pendente → persistência' \
  && al_tem "$AL_EXEC" 'checkpoint <slug>` repete as provas antes de preparar o índice' \
  && al_tem "$AL_EXEC" '`2` trava existente, fronteira ou parcial (com `motivo=` estruturado)' \
  && al_tem "$AL_EXEC" '`5` transição ou indisponibilidade da trava'
afirma "ds175-contrato-execucao" $? "humano, saidas/codigos, precedencia e recuperacao"

al_tem "$AL_RASTRO" '`orcamento_f6_autorizado`' \
  && al_tem "$AL_RASTRO" 'exatamente uma vez junto de `replanejamento_execucao_iniciado`' \
  && al_tem "$AL_RASTRO" 'Retomada e checkpoint pendente não duplicam nenhum dos dois eventos'
afirma "ds175-contrato-rastro" $? "dois eventos uma vez, repeticao silenciosa"

al_tem "$AL_SKILL" 'scripts/planejamento.sh autorizar-replanejamento-execucao <slug> <max_replanejamentos_f6> <autorizado_por>' \
  && al_tem "$AL_SKILL" 'Somente `orcamento_f6_nao_declarado` é recuperável por autorização tardia' \
  && al_tem "$AL_SKILL" '`classes_mistas`, legados e orçamentos esgotados continuam terminais'
afirma "ds175-contrato-skill" $? "comando e fronteira exata entre terminais"

al_tem "$AL_TPL" '# opcionais e inseparáveis: autorização humana tardia da F6 (DS-175)' \
  && al_tem "$AL_TPL" 'autorizacao_tardia_f6_por:' \
  && al_tem "$AL_TPL" '# autoridade canônica da F6 tardia; não reutilizar orcamento_declarado_por'
afirma "ds175-contrato-template" $? "tupla opcional e autoridade canonica comentadas"

[ "$(grep -c '^| DS-175 |' "$AL_DSF")" -eq 1 ] \
  && al_tem "$AL_DSF" 'autorizar-replanejamento-execucao' \
  && al_tem "$AL_DSF" 'orcamento_f6_nao_declarado' \
  && al_tem "$AL_DSF" 'autorizacao_tardia_f6_por'
afirma "ds175-decisao-append-only" $? "uma linha DS-175 fiel a spec e decisoes anteriores intactas"

# --------------------------------------------------------- mutantes DS-175
# Cada copia leva planejamento + bloqueios + helper de caminho + trava. O controle
# intacto percorre todos os oraculos usados pelos 21 mutantes; cada mutante muda
# uma unica regra semantica e precisa morrer no caso que a nomeia.
al_copia() { # al_copia <nome> -> planejamento.sh isolado
  local s; s="$(copia_skill_k "al-$1")" || return 1
  cp "$PL" "$s" || return 1
  printf '%s' "$s"
}
al_muta() { # al_muta <arquivo> <trecho> <troca>
  muta_lit "$1" "$1.m" "$2" "$3" && mv "$1.m" "$1"
}
al_roda() { # al_roda <caso> <planejamento-mutante>
  local c="$1" s="$2" d
  d="$(kcopia "$FXN")" || return 1
  "$c" "$s" "$d"
}
al_hash_divergente() { # a mudanca preserva path/estado, mas troca o hash
  local s="$1" d="$2" f a ev h ck evck rc out
  f="$(kf "$d")"; a="$f/00-PLANEJAMENTO.md"; ev="$d/docs/eventos/menu.jsonl"
  sed 's|      altera: \[src/ui/cabecalho-topo.tsx\]|      altera: [src/menu/perfil.ts]|' \
    "$f/sprint-04/tasks.md" > "$K/al-hash.tmp" && mv "$K/al-hash.tmp" "$f/sprint-04/tasks.md"
  mkdir -p "$d/src/menu"; printf 'antes\n' > "$d/src/menu/perfil.ts"
  git -C "$d" add "$f/sprint-04/tasks.md" src/menu/perfil.ts \
    && git -C "$d" commit -q -m 'fixture: hash parcial tardio' || return 1
  printf 'depois\n' > "$d/src/menu/perfil.ts"
  l_aut_terminal "$s" "$d" && l_aut_aplica "$s" "$d" 2 usuario >/dev/null || return 1
  printf 'terceiro\n' > "$d/src/menu/perfil.ts"
  h="$(git -C "$d" rev-parse HEAD)"; ck="$(cksum < "$a")"; evck="$(cksum < "$ev")"
  out="$(l_aut_aplica "$s" "$d" 2 usuario)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" motivo)" = parcial_divergente ] \
    && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ] \
    && [ "$(cksum < "$ev")" = "$evck" ]
}
al_mutante() { # al_mutante <nome> <rc-geracao> <script> <caso>...
  local nome="$1" rcg="$2" s="$3" c vivos=""; shift 3
  if [ "$rcg" -eq 0 ]; then
    for c in "$@"; do al_roda "$c" "$s" && vivos="$vivos$c "; done
  fi
  [ "$rcg" -eq 0 ] && [ -z "$vivos" ]; local rc=$?
  afirma "$nome" "$rc" "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rcg)"
}

AL_CASOS="l_aut_limpa l_aut_parciais l_aut_dono_e_clone l_aut_bloqueios l_aut_fronteira
l_aut_concorrente l_aut_terminais l_aut_trava l_aut_sem_planejamento_e_sem_marco l_aut_trava_ambiente k_aut_valida_origem_data_recusa
l5_checkpoint_e_retomada l5_pendente_invalido al_hash_divergente
l5_retomada_duravel_recusa_parcial_perdido l5_fechamento_pendente_e_fechado"
AL_CTL="$(al_copia controle)"; AL_VIVOS=""
for al_c in $AL_CASOS; do al_roda "$al_c" "$AL_CTL" || AL_VIVOS="$AL_VIVOS$al_c "; done
[ -z "$AL_VIVOS" ]; afirma "ds175-mutante-controle-intacto" $? "${AL_VIVOS:-todos os oraculos sobrevivem na copia intacta}"

# 01 — qualquer motivo do terminal recusado passaria pela guarda inicial.
AL_M="$(al_copia m01)"
al_muta "$AL_M" '      || [ "$P_RECUSA" != orcamento_f6_nao_declarado ]; then' '      || false; then'
al_mutante "ds175-mutante-01" $? "$AL_M" l_aut_terminais

# 02 — classes misturadas deixam de barrar a abertura.
AL_M="$(al_copia m02)"
al_muta "$AL_M" '  [ -z "$outros" ] || falha "$E_CONTRATO" "autorizacao tardia exige somente defeito_de_plano aberto: $outros"' '  : # mutante aceita classes_mistas'
al_mutante "ds175-mutante-02" $? "$AL_M" l_aut_bloqueios

# 03 — o teto e gravado, mas a rodada continua zero.
AL_M="$(al_copia m03)"
al_muta "$AL_M" '  W6_N=$((P_N6 + 1)); W6_BLQ="$defeitos"; W6_CONG="$C_IDS"; W6_ASS="$C_ASS"; W6_PARC="$F_PARC"' '  W6_N="$P_N6"; W6_BLQ="$defeitos"; W6_CONG="$C_IDS"; W6_ASS="$C_ASS"; W6_PARC="$F_PARC"'
al_mutante "ds175-mutante-03" $? "$AL_M" l_aut_limpa

# 04 — a rodada incrementa sem materializar a tupla tardia.
AL_M="$(al_copia m04)"
al_muta "$AL_M" '    W_AUT6=presente; W_AUT6_POR="$aut_por"; W_AUT6_EM="$aut_em"; W_AUT6_ORIGEM="$aut_origem"; W_RECUSA=""' '    W_AUT6=ausente; W_AUT6_POR=""; W_AUT6_EM=""; W_AUT6_ORIGEM=""; W_RECUSA=""'
al_mutante "ds175-mutante-04" $? "$AL_M" l_aut_limpa

# 05 — a origem terminal deixa de ser preservada na auditoria.
AL_M="$(al_copia m05)"
al_muta "$AL_M" 'W_AUT6_ORIGEM="$aut_origem"' 'W_AUT6_ORIGEM=""'
al_mutante "ds175-mutante-05" $? "$AL_M" l_aut_limpa

# 06 — a task do B-NN nao precisa mais estar bloqueada.
AL_M="$(al_copia m06)"
al_muta "$AL_M" '    [ "$st" = bloqueada ] || falha "$E_CONTRATO" "$b aponta $t, que esta '\''${st:-fora do plano}'\'': a task precisa estar bloqueada"' '    : # mutante ignora task nao bloqueada'
al_mutante "ds175-mutante-06" $? "$AL_M" l_aut_bloqueios

# 07 — a aplicacao ignora toda a fronteira segura.
AL_M="$(al_copia m07)"
al_muta "$AL_M" '  fronteira_segura' '  : # mutante sem fronteira_segura'
al_mutante "ds175-mutante-07" $? "$AL_M" l_aut_fronteira

# 08 — o retrato parcial compara so path/estado e ignora o hash.
AL_M="$(al_copia m08)"
al_muta "$AL_M" '  [ "$R_TSV" = "$esperado" ] && return 0' '  [ "$(printf '\''%s\n'\'' "$R_TSV" | cut -f1,2)" = "$(printf '\''%s\n'\'' "$esperado" | cut -f1,2)" ] && return 0'
al_mutante "ds175-mutante-08" $? "$AL_M" al_hash_divergente

# 09 — uma retomada idempotente incrementa a rodada de novo.
AL_M="$(al_copia m09)"
al_muta "$AL_M" '      retomada)' '      retomada)
        f6_herda; W6_N=$((P_N6 + 1)); escreve "$P_MAX" "$P_POR" "$P_ESTADO" "$P_REPROV" "$P_HIST"'
al_mutante "ds175-mutante-09" $? "$AL_M" l5_checkpoint_e_retomada

# 10 — repeticao com argumentos diferentes e aceita.
#      As duas trocas formam UM mutante, e o status delas sai antes do cksum da assinatura: lido
#      depois, seria o do cksum (sempre 0), e um mutante aplicado so em parte chegaria como gerado.
al_gera_m10() { # al_gera_m10 <arquivo> <segundo-trecho> — status das duas trocas; assinatura em AL_SIG10
  al_muta "$1" '  [ "$max6" = "$P_MAX6" ] \' '  true \' \
    && al_muta "$1" "$2" '  true \'
  local rc=$?
  AL_SIG10="$(cksum < "$1")"
  return "$rc"
}
# 10c — controle da geracao: com a segunda troca inexistente, o mutante nao passa por gerado.
#       Vem antes do 10, que e quem deixa a assinatura em AL_SIG10 para a matriz do 18.
#       A primeira troca precisa ter sido aplicada: sem ela, o rc diferente de 0 nao prova nada.
AL_M="$(al_copia m10c)" || AL_M=""
al_gera_m10 "$AL_M" '  trecho que nao existe no planejamento.sh \'
AL_RC10C=$?
[ -n "$AL_M" ] && ! cmp -s "$AL_M" "$PL" && [ "$AL_RC10C" -ne 0 ]
afirma "ds175-mutante-10-geracao-parcial-acusada" $? "primeira troca aplicada, segunda inexistente (rc geracao=$AL_RC10C)"
AL_M="$(al_copia m10)"
al_gera_m10 "$AL_M" '  [ "$por" = "$P_AUT6_POR" ] \'
AL_RC10=$?
al_mutante "ds175-mutante-10" "$AL_RC10" "$AL_M" l5_checkpoint_e_retomada

# 11 — a autorizacao tardia reatribui o dono ja existente da F5.
AL_M="$(al_copia m11)"
al_muta "$AL_M" '  escreve "$P_MAX" "$P_POR" replanejar_execucao "$P_REPROV" "$P_HIST"' '  escreve "$P_MAX" "$aut_por" replanejar_execucao "$P_REPROV" "$P_HIST"'
al_mutante "ds175-mutante-11" $? "$AL_M" l_aut_limpa

# 12 — recusa ativa e tupla tardia passam a coexistir.
AL_M="$(al_copia m12)"
al_muta "$AL_M" '  ! fm_presente recusa_replanejamento_f6 \' '  true \' \
  && al_muta "$AL_M" 'valida_recusa() {' 'valida_recusa() { return 0'
al_mutante "ds175-mutante-12" $? "$AL_M" k_aut_valida_origem_data_recusa

# 13 — a chamada deixa de adquirir a trava de concorrencia.
AL_M="$(al_copia m13)"
al_muta "$AL_M" '  adquire_trava_autorizacao_f6 "$RAIZ" "$slug"' '  true "$RAIZ" "$slug"'
al_mutante "ds175-mutante-13" $? "$AL_M" l_aut_concorrente

# 14 — lock preexistente e tratado como aquisicao bem sucedida e pode ser removido.
AL_M="$(al_copia m14)"; AL_LIB="${AL_M%/scripts/planejamento.sh}/scripts/lib/trava-autorizacao-f6.sh"
al_muta "$AL_LIB" 'mkdir "$caminho"' 'true # mutante aceita trava existente'
al_mutante "ds175-mutante-14" $? "$AL_M" l_aut_trava

# 15 — um eixo legado e promovido automaticamente ao eixo presente.
AL_M="$(al_copia m15)"
al_muta "$AL_M" '  if [ "$E_FONTE" != planejamento ] || [ "$P_ESTADO" != replanejamento_execucao_recusado ] \' '  if [ "$P_RECUSA" = orcamento_f6_legado ]; then P_F6=presente; P_MAX6=null; P_N6=0
  elif [ "$E_FONTE" != planejamento ] || [ "$P_ESTADO" != replanejamento_execucao_recusado ] \'
al_mutante "ds175-mutante-15" $? "$AL_M" l_aut_terminais

# 16 — a guarda terminal roda antes da recuperacao pendente.
AL_M="$(al_copia m16)"
al_muta "$AL_M" '  if [ "$P_AUT6" = presente ]; then' '  if false; then # mutante pula recuperacao antes do terminal'
al_mutante "ds175-mutante-16" $? "$AL_M" l5_checkpoint_e_retomada

# 17 — leitores publicam a autoridade tardia a partir do dono compartilhado.
AL_M="$(al_copia m17)"
al_muta "$AL_M" '      "$P_AUT6_POR" "$P_AUT6_EM" "$P_AUT6_ORIGEM"' '      "$P_POR" "$P_AUT6_EM" "$P_AUT6_ORIGEM"'
al_mutante "ds175-mutante-17" $? "$AL_M" l_aut_dono_e_clone

# 18 — uma versao pendente e classificada antes de rejeitar argumentos diferentes.
#      As duas trocas formam UM mutante: o status da geracao e capturado logo depois delas, antes
#      da conferencia da matriz, para que um mutante aplicado so em parte nao chegue como gerado.
AL_M="$(al_copia m18)"
al_muta "$AL_M" '  [ "$max6" = "$P_MAX6" ] \' '  [ "$PERSIST" = pendente ] || [ "$max6" = "$P_MAX6" ] \' \
  && al_muta "$AL_M" '  [ "$por" = "$P_AUT6_POR" ] \' '  [ "$PERSIST" = pendente ] || [ "$por" = "$P_AUT6_POR" ] \'
AL_RC18=$?
[ "$(cksum < "$AL_M")" != "$AL_SIG10" ]
afirma "ds175-matriz-10-18-distinta" $? "argumentos ignorados sempre e so durante pendencia sao mutacoes diferentes"
al_mutante "ds175-mutante-18" "$AL_RC18" "$AL_M" l5_checkpoint_e_retomada

# 19 — pending/retomada saem antes de provar congeladas e parciais.
AL_M="$(al_copia m19)"
al_muta "$AL_M" '  confere_pendente_autorizacao_f6' '  : # mutante responde antes das provas da rodada'
al_mutante "ds175-mutante-19" $? "$AL_M" l5_retomada_duravel_recusa_parcial_perdido

# 20 — o checkpoint pendente ignora fechamento/reclasse/unblock do B-NN.
AL_M="$(al_copia m20)"
al_muta "$AL_M" '  if [ "$PERSIST" = pendente ] && [ "$P_ESTADO" = replanejar_execucao ]; then' '  if false; then # mutante persiste sem validar B-NN/task'
al_mutante "ds175-mutante-20" $? "$AL_M" l5_pendente_invalido

# 21 — fechamento pendente e tratado como retomada normal.
AL_M="$(al_copia m21)"
al_muta "$AL_M" '  if [ "$P_ESTADO" = aprovado ]; then AUT6_ACAO=fechamento_pendente' '  if [ "$P_ESTADO" = aprovado ]; then AUT6_ACAO=retomada'
al_mutante "ds175-mutante-21" $? "$AL_M" l5_fechamento_pendente_e_fechado
rm -rf "$K"

