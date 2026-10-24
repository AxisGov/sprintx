#!/usr/bin/env bash
#
# Secoes J e K da bancada: bloqueio com classe e replanejamento da execucao.
# Carregada por `.` de dentro da bancada.sh, no mesmo ponto e na mesma ordem: usa os
# auxiliares e o estado dela. Mora aqui porque o CodeAnt pula arquivo acima de 5.000 linhas
# ou 200 KB (expxdev, docs/superpowers/specs/2026-10-19-limites-do-codeant-emenda.md).

echo "== J. o bloqueio ganha classe (P0.2-A5) =="
# Testa o MECANISMO: scripts/bloqueios.sh e o unico escritor de B-NN novo, e a classe
# sai da chave `classe`, nunca da descricao. Cada caso e uma funcao <script> <dir>, para
# que os mutantes (jm-*) rodem exatamente a mesma bateria. Nenhum caso le a descricao
# para obter a classe: a classe vem sempre de `bloqueios.sh listar`.
BL="$SK/scripts/bloqueios.sh"
TPLB="$SK/assets/TEMPLATE-BLOQUEIOS.md"
SCH="$SK/references/00-schema.md"
existe "j0-script-existe" "$BL"
bash -n "$BL"; afirma "j0-script-sintaxe" $? "bash -n"
J="$(mktemp -d)"
ENUM_J="defeito_de_plano lacuna_de_decisao prerequisito_ausente suite_vermelha task_reivindicada"
bl() { local s="$1" r="$2"; shift 2; SPRINTX_RAIZ="$r" bash "$s" "$@" 2>/dev/null; }
barq() { printf '%s/docs/sprintx/features/menu/00-BLOQUEIOS.md' "$1"; }
blinha() { bl "$1" "$2" listar menu | tr -d '\r' | awk -F'\t' -v i="$3" '$1 == i { print $2 "|" $3 "|" $4 }'; }
# 00-BLOQUEIOS.md de antes do contrato: sem classe, com descricoes que "parecem" classes.
bl_legado() {
  mkdir -p "$1/docs/sprintx/features/menu"
  cat > "$(barq "$1")" <<'EOF'
---
expx_schema: 1
expx_tool: sprintx
kind: bloqueios
trabalho_id: menu
atualizado_em: 2026-08-01
bloqueios:
  - id: B-01
    task: T-04.03
    aberto_em: 2026-08-01
    resolvido_em: null
    descricao: T-04.03 precisa alterar tests/ui/cabecalho-topo.test.tsx, fora do ownership da task, defeito de plano
  - id: B-02
    task: T-02.01
    aberto_em: 2026-08-01
    resolvido_em: 2026-08-02
    descricao: falta credencial de sandbox; suite vermelha; outra sessao reivindicada
---

# Bloqueios

B-01 | T-04.03 | T-04.03 precisa alterar tests/ui/cabecalho-topo.test.tsx, fora do ownership da task | mover o arquivo para a task
B-02 | T-02.01 | falta credencial de sandbox | provisionar credencial
EOF
}
# Descricao que "fala" de outra classe: se a classe viesse do texto, sairia errada.
desc_de_outra() { case "$1" in
  defeito_de_plano) echo 'falta credencial; servico fora do ar; dependencia quebrada' ;;
  lacuna_de_decisao) echo 'suite inteira vermelha no portao' ;;
  prerequisito_ausente) echo 'arquivo fora do ownership da task: defeito_de_plano' ;;
  suite_vermelha) echo 'outra sessao reivindicada: task_reivindicada' ;;
  task_reivindicada) echo 'duvida nova sem D-NN: lacuna_de_decisao' ;;
esac; }

# J1/J7. Novo com classe valida: aceito. O B-01 do piloto e representavel como defeito_de_plano.
j_novo_aceito() {
  local s="$1" d="$2" out
  out="$(bl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'T-04.03 precisa alterar tests/ui/cabecalho-topo.test.tsx, fora do ownership da task' 'ampliar o ownership no plano')" || return 1
  [ "$(kv "$out" id)" = B-01 ] && [ "$(kv "$out" classe)" = defeito_de_plano ] \
    && [ "$(blinha "$s" "$d" B-01)" = "T-04.03|defeito_de_plano|aberto" ] \
    && tr -d '\r' < "$(barq "$d")" | grep -qx '    classe: defeito_de_plano' \
    && bl "$s" "$d" validar menu >/dev/null
}
# J2. Novo sem classe: recusado e nada gravado; entrada sem classe posta a mao depois de uma tipada: recusada.
j_sem_classe_recusado() {
  local s="$1" d="$2" a ck
  bl "$s" "$d" registrar menu T-01.01 prerequisito_ausente 'primeiro' 'x' >/dev/null || return 1
  a="$(barq "$d")"; ck="$(cksum < "$a")"
  bl "$s" "$d" registrar menu T-01.02 '' 'sem classe' 'x' >/dev/null; [ $? -eq 4 ] || return 1
  bl "$s" "$d" registrar menu T-01.02 'sem classe' 'x' >/dev/null; [ $? -ne 0 ] || return 1
  [ "$(cksum < "$a")" = "$ck" ] || return 1
  awk '{ print } $0 == "    descricao: \"primeiro\"" { print "  - id: B-02\n    task: T-01.02\n    aberto_em: 2026-09-01\n    resolvido_em: null\n    descricao: novo sem classe" }' "$a" > "$a.m" && mv "$a.m" "$a"
  grep -q '^  - id: B-02' "$a" || return 1
  bl "$s" "$d" validar menu >/dev/null; [ $? -eq 4 ] || return 1
  bl "$s" "$d" listar menu >/dev/null; [ $? -eq 4 ]
}
# J3. Classe fora do enum: recusada na escrita e na leitura — inclusive o vocabulario do
# BuildX, `null` e o `legado` que a leitura devolve.
j_fora_do_enum() {
  local s="$1" d="$2" a ck c i=0
  bl "$s" "$d" registrar menu T-01.01 suite_vermelha 'base' 'x' >/dev/null || return 1
  a="$(barq "$d")"; ck="$(cksum < "$a")"
  for c in legado null trabalho_novo decisao_humana recurso_externo falha_tecnica Defeito_de_plano 'defeito de plano'; do
    bl "$s" "$d" registrar menu T-01.02 "$c" 'ruim' 'x' >/dev/null; [ $? -eq 4 ] || return 1
  done
  [ "$(cksum < "$a")" = "$ck" ] || return 1
  for c in trabalho_novo null legado '"suite_vermelha"' ''; do
    i=$((i+1)); mkdir -p "$d/v$i/docs/sprintx/features/menu"
    sed "s/^    classe: suite_vermelha\$/    classe: $c/" "$a" > "$(barq "$d/v$i")"
    cmp -s "$a" "$(barq "$d/v$i")" && return 1
    bl "$s" "$d/v$i" validar menu >/dev/null; [ $? -eq 4 ] || return 1
  done
}
# J4. Legado sem classe: legivel, sai `legado`, nunca inferido — nem na leitura, nem quando
# um B-NN novo regrava o arquivo (as entradas antigas ficam byte a byte).
j_legado() {
  local s="$1" d="$2" a antes depois
  bl_legado "$d"; a="$(barq "$d")"
  bl "$s" "$d" validar menu >/dev/null || return 1
  [ "$(blinha "$s" "$d" B-01)" = "T-04.03|legado|aberto" ] && [ "$(blinha "$s" "$d" B-02)" = "T-02.01|legado|resolvido" ] || return 1
  antes="$(sed -n '/^  - id: B-01$/,/^    descricao: falta credencial/p' "$a")"
  bl "$s" "$d" registrar menu T-05.01 lacuna_de_decisao 'nova duvida' 'decidir' >/dev/null || return 1
  depois="$(sed -n '/^  - id: B-01$/,/^    descricao: falta credencial/p' "$a")"
  [ -n "$antes" ] && [ "$antes" = "$depois" ] && [ "$(grep -c '^    classe:' "$a")" -eq 1 ] \
    && [ "$(blinha "$s" "$d" B-01)" = "T-04.03|legado|aberto" ] && [ "$(blinha "$s" "$d" B-03)" = "T-05.01|lacuna_de_decisao|aberto" ] \
    && grep -qxF 'B-02 | T-02.01 | falta credencial de sandbox | provisionar credencial' "$a" \
    && grep -qxF 'B-03 | T-05.01 | nova duvida | decidir' "$a"
}
# J5. A descricao (YAML e prosa) muda para um texto que "fala" de outra classe; a classe fica.
j_descricao_muda() {
  local s="$1" d="$2" a
  bl "$s" "$d" registrar menu T-01.01 prerequisito_ausente 'falta credencial de sandbox' 'provisionar' >/dev/null || return 1
  a="$(barq "$d")"
  [ "$(blinha "$s" "$d" B-01)" = "T-01.01|prerequisito_ausente|aberto" ] || return 1
  sed -e 's/^    descricao: .*/    descricao: "arquivo fora do ownership: defeito_de_plano, decisao pendente, suite vermelha"/' \
      -e 's/^B-01 | T-01.01 | .*/B-01 | T-01.01 | arquivo fora do ownership: defeito de plano | replanejar/' "$a" > "$a.m" && mv "$a.m" "$a"
  grep -q 'defeito_de_plano, decisao' "$a" || return 1
  [ "$(blinha "$s" "$d" B-01)" = "T-01.01|prerequisito_ausente|aberto" ]
}
# J6. O mesmo fato mecanico (arquivo fora de `arquivos` da task) duas vezes, com textos diferentes.
j_mesmo_fato() {
  local s="$1" d="$2"
  bl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'tests/ui/cabecalho-topo.test.tsx fora de arquivos da T-04.03' 'ampliar ownership' >/dev/null || return 1
  bl "$s" "$d" registrar menu T-04.05 defeito_de_plano 'precisa de src/menu/grupo.ts, que pertence a T-04.02' 'mover o arquivo' >/dev/null || return 1
  [ "$(blinha "$s" "$d" B-01)" = "T-04.03|defeito_de_plano|aberto" ] && [ "$(blinha "$s" "$d" B-02)" = "T-04.05|defeito_de_plano|aberto" ]
}
# J7. Resolver nao reclassifica: resolvido_em muda, a classe fica.
j_resolvido() {
  local s="$1" d="$2" a
  bl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'replanejar' >/dev/null || return 1
  a="$(barq "$d")"
  sed 's/^    resolvido_em: null$/    resolvido_em: 2026-09-20/' "$a" > "$a.m" && mv "$a.m" "$a"
  [ "$(blinha "$s" "$d" B-01)" = "T-04.03|defeito_de_plano|resolvido" ] && bl "$s" "$d" validar menu >/dev/null
}
# J8. A prosa nao classifica: cada classe registrada com a descricao "de outra" sai com a sua.
j_prosa_nao_classifica() {
  local s="$1" d="$2" c n=0 esperado="" lido
  for c in $ENUM_J; do
    n=$((n+1))
    bl "$s" "$d" registrar menu "T-09.0$n" "$c" "$(desc_de_outra "$c")" 'x' >/dev/null || return 1
    esperado="$esperado$c "
  done
  lido="$(bl "$s" "$d" listar menu | tr -d '\r' | cut -f3 | tr '\n' ' ')"
  [ "$lido" = "$esperado" ]
}
CASOS_J="j_novo_aceito j_sem_classe_recusado j_fora_do_enum j_legado j_descricao_muda j_mesmo_fato j_resolvido j_prosa_nao_classifica"
roda_caso() { local d; d="$(mktemp -d "$J/c.XXXXXX")"; "$1" "$2" "$d"; }
for par in j_novo_aceito:j1-novo-com-classe-aceito j_sem_classe_recusado:j2-novo-sem-classe-recusado \
  j_fora_do_enum:j3-classe-fora-do-enum-recusada j_legado:j4-legado-legivel-sem-inferencia \
  j_descricao_muda:j5-descricao-muda-classe-fica j_mesmo_fato:j6-mesmo-fato-mesma-classe \
  j_resolvido:j7-defeito-de-plano-resolvido-mantem j_prosa_nao_classifica:j8-prosa-nao-classifica; do
  roda_caso "${par%%:*}" "$BL"; afirma "${par#*:}" $? "${par%%:*}"
done
D="$J/tpl"; bl "$BL" "$D" registrar menu T-01.01 lacuna_de_decisao 'x' 'y' >/dev/null
tr -d '\r' < "$(barq "$D")" | awk 'NR==1{next} $0=="---"{exit} {print}' | grep -q '{{'; [ $? -ne 0 ]
afirma "j9-arquivo-novo-sem-placeholder-no-yaml" $? "criado do template, frontmatter preenchido"

# Enum unico: script, schema (enum e tabela), tabela da F6 e template, na mesma ordem.
E_SCRIPT="$(bash "$BL" classes | tr -d '\r' | tr '\n' ' ')"
E_ENUM="$(tr -d '\r' < "$SCH" | grep -F '| `classe` (bloqueio) |' | grep -o '`[a-z_]*`' | tr -d '`' | sed 1d | tr '\n' ' ')"
E_TABSCH="$(tr -d '\r' < "$SCH" | awk '/^\*\*O bloqueio é dado tipado/{f=1} /^Regras duras de `classe`/{f=0} f' | grep -E '^\| `[a-z_]+` \|' | sed -E 's/^\| `([a-z_]+)`.*/\1/' | tr '\n' ' ')"
E_F6="$(tr -d '\r' < "$EXEC" | awk '/^## Regra de bloqueio/{f=1} /^## Portões/{f=0} f' | grep -E '\| `[a-z_]+` \|$' | grep -vF '| `classe` |' | sed -E 's/.*\| `([a-z_]+)` \|$/\1/' | tr '\n' ' ')"
E_TPL="$(tr -d '\r' < "$TPLB" | sed -n 's/^    classe: {{\(.*\)}}$/\1/p' | tr -d ' ' | tr '|' ' ') "
for par in "script:$E_SCRIPT" "schema-enum:$E_ENUM" "schema-tabela:$E_TABSCH" "f6-tabela:$E_F6" "template:$E_TPL"; do
  [ "${par#*:}" = "$ENUM_J " ]; afirma "j10-enum-${par%%:*}" $? "${par#*:}"
done
printf '%s' "$E_SCRIPT" | grep -Eq 'trabalho_novo|decisao_humana|recurso_externo|falha_tecnica|legado'; [ $? -ne 0 ]
afirma "j10-vocabulario-e-da-sprintx" $? "nenhuma classe do BuildX nem legado"

# A F6 so registra pelo script, e cada caminho de criacao nomeia a sua classe.
tem "$EXEC" 'scripts/bloqueios.sh registrar <slug> <T-NN.MM|null> <classe>' \
  && ! tem "$EXEC" 'Registre em `docs/sprintx/features/<slug>/00-BLOQUEIOS.md`: `B-NN'
afirma "j11-f6-registra-pelo-script" $? "sem gravacao a mao do B-NN"
tem "$EXEC" 'nunca pelo texto que você vai escrever na descrição'; afirma "j11-f6-classe-pelo-caminho" $? "caminho, nao texto"
tem "$EXEC" 'registre um bloqueio `task_reivindicada`' && tem "$EXEC" 'registre bloqueio `suite_vermelha`' \
  && tem "$EXEC" 'trate como bloqueio `defeito_de_plano` se não houver task que o resolva' \
  && tr -d '\r' < "$EXEC" | grep -A1 -F '**Se não conseguir tornar o teste discriminante, registre bloqueio da task** (classe' | grep -qF '`defeito_de_plano`, Regra de bloqueio'
afirma "j11-f6-cada-caminho-tem-classe" $? "reivindicada, suite, criterio, fraco:teste"
tem "$SCH" '**A prosa explica, não classifica:**' && tem "$SCH" '**Ela nunca recebe classe inferida**' \
  && tem "$SCH" '5. **Exceção: `classe` de bloqueio nunca é inferida da prosa.**' && tem "$SCH" '**Imutável.** Gravada, a classe não muda'
afirma "j12-schema-contrato-da-classe" $? "prosa nao classifica, legado, migracao, imutavel"
DSF="$SK/DECISOES-DA-SKILL.md"
[ "$(grep -c '^| DS-139 |' "$DSF")" -eq 1 ] && tem "$DSF" '**A prosa explica, não classifica:**' \
  && tem "$DSF" 'nenhum consumidor deriva classe de `descricao`' && tem "$DSF" '**nunca ganha classe inferida retroativamente**'
afirma "j12-ds139-registrada" $? "DS-139"

# Mutantes do script, em copia temporaria da skill (scripts/ + assets/, porque o script acha
# o template pela propria pasta): a bateria acima tem de matar cada um. O controle e uma
# copia SEM mutacao na mesma estrutura: se ele morrer, a bancada e que esta quebrada.
MJ="$J/mut"
muta_lit() { # muta_lit <origem> <destino> <trecho> <troca> — troca literal; falha se o trecho nao existe
  ML_A="$3" ML_B="$4" awk '{ a = ENVIRON["ML_A"]; i = index($0, a); if (i) { $0 = substr($0, 1, i - 1) ENVIRON["ML_B"] substr($0, i + length(a)); n++ } print } END { exit n ? 0 : 1 }' "$1" > "$2"
}
copia_skill() { mkdir -p "$MJ/$1/scripts/lib" "$MJ/$1/assets"; cp "$TPLB" "$MJ/$1/assets/"; cp "$SK/scripts/caminho-git.sh" "$MJ/$1/scripts/"; cp "$SK/scripts/lib/execucao.sh" "$MJ/$1/scripts/lib/"; printf '%s/%s/scripts/bloqueios.sh' "$MJ" "$1"; }
mata() { local c; for c in $CASOS_J; do roda_caso "$c" "$1" || { printf '%s' "$c"; return; }; done; }
mutante() { # mutante <nome> <rc da geracao> <script> <caso que TEM de matar>... — nao vale morrer de carona
  local nome="$1" rc="$2" s="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do roda_caso "$c" "$s" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]; afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
CTL="$(copia_skill controle)"; cp "$BL" "$CTL"
K="$(mata "$CTL")"; [ -z "$K" ]; afirma "jm-controle-copia-intacta-sobrevive" $? "${K:-nenhum caso reprova a copia sem mutacao}"
DERIVA='c = ($0 ~ /arquivo|ownership|plano/) ? "defeito_de_plano" : ($0 ~ /credencial|servico|dependencia/) ? "prerequisito_ausente" : ($0 ~ /suite/) ? "suite_vermelha" : ($0 ~ /sessao|reivindicad/) ? "task_reivindicada" : "lacuna_de_decisao"; nc = 1'
LINHA_CHAVES='    /^    [a-z_]+:/      { next }'
M="$(copia_skill a)"; muta_lit "$BL" "$M.1" '    classe: %s\n' '' && muta_lit "$M.1" "$M" '"$task" "$classe" "$(hoje)"' '"$task" "$(hoje)"'
mutante "jm-mutante-a-escrita-remove-classe" $? "$M" j_novo_aceito j_mesmo_fato
M="$(copia_skill b)"; muta_lit "$BL" "$M" "$LINHA_CHAVES" "    /^    descricao:/ { $DERIVA; next }
$LINHA_CHAVES"
mutante "jm-mutante-b-classe-da-descricao" $? "$M" j_descricao_muda j_prosa_nao_classifica
M="$(copia_skill c)"; muta_lit "$BL" "$M" "$LINHA_CHAVES" "    /^    descricao:/ { if (!nc) { $DERIVA }; next }
$LINHA_CHAVES"
mutante "jm-mutante-c-legado-inferido-da-descricao" $? "$M" j_legado
M="$(copia_skill d)"; muta_lit "$BL" "$M" '[ -n "$tipada" ] && falha' 'false && falha'
mutante "jm-mutante-d-leitura-aceita-novo-sem-classe" $? "$M" j_sem_classe_recusado
M="$(copia_skill e)"; muta_lit "$BL" "$M" 'classe_valida "$classe" || falha "$E_CONTRATO" "$id com classe' 'true || falha "$E_CONTRATO" "$id com classe'
mutante "jm-mutante-e-leitura-aceita-fora-do-enum" $? "$M" j_fora_do_enum
rm -rf "$J"

echo "== K. replanejamento da execucao e preservacao das tasks concluidas (P0.2-B) =="
# Testa o MECANISMO contra repositorios git reais. A essencia do piloto: 14 de 18 tasks
# concluidas, T-04.03 bloqueada com defeito_de_plano (precisa alterar um arquivo que a
# T-03.01 concluida criou), orcamento da F5 ja parcialmente usado. Cada caso e uma funcao
# <planejamento.sh> <dir>, para que os mutantes (km-*) rodem exatamente a mesma bateria;
# as fixtures de base sao montadas uma vez, com o script real, e copiadas para cada caso.
# A classe vem sempre da chave, via bloqueios.sh: nenhum caso le a descricao.
K="$(mktemp -d)"
kpl() { local s="$1" d="$2"; shift 2; (cd "$d" && bash "$s" "$@") 2>&1; }
kbl() { local s="$1" d="$2"; shift 2; SPRINTX_RAIZ="$d" bash "$(dirname "$s")/bloqueios.sh" "$@" 2>&1; }
kf() { printf '%s/docs/sprintx/features/menu' "$1"; }
kst() { # kst <dir> <T-NN.MM> — status da task no frontmatter do tasks.md que a declara
  local f
  for f in "$(kf "$1")"/sprint-*/tasks.md; do
    tr -d '\r' < "$f" | awk -v t="$2" 'NR==1{next} $0=="---"{exit} /^tasks:/{b=1;next} b&&/^[^ ]/{b=0} b&&/^  - id:/{id=$3} b&&id==t&&/^    status:/{print $2; exit}'
  done
}
kbloq() { kbl "$PL" "$1" listar menu | tr -d '\r' | awk -F'\t' -v i="$2" '$1 == i { print $3 "|" $4 }'; }
# O congelado visto de fora do script: sprint-01..03 inteiros e, na sprint-04, o item do
# frontmatter e o bloco da prosa de T-04.01 e T-04.02.
kcong() {
  local f; f="$(kf "$1")"
  cat "$f/sprint-01/tasks.md" "$f/sprint-02/tasks.md" "$f/sprint-03/tasks.md"
  for t in T-04.01 T-04.02; do
    tr -d '\r' < "$f/sprint-04/tasks.md" | sed -n "/^  - id: $t\$/,/^    suite:/p; /^id: $t\$/,/^\`\`\`\$/p"
  done
}
k_item() { # k_item <id> <status> <cria> <altera> <depende>
  local conc=null suite=nao_executada
  if [ "$2" = concluida ]; then conc=2026-09-10; suite=parcial; fi
  printf '  - id: %s\n    titulo: Task %s\n    fase: F-%s.1\n    status: %s\n    objetivo: Entregar a parte %s\n    arquivos:\n      cria: [%s]\n      altera: [%s]\n    teste_integracao: Integra a parte %s contra o modulo real\n    teste_funcional: Dada a entrada de %s, devolve a saida declarada\n    criterio_aceite: O teste da parte %s passa\n    depende_de: [%s]\n    paralelizavel: false\n    concluida_em: %s\n    suite: %s\n' \
    "$1" "$1" "$(printf '%s' "$1" | cut -c3-4)" "$2" "$1" "$3" "$4" "$1" "$1" "$1" "$5" "$conc" "$suite"
}
k_prosa() {
  printf -- '---\n\n```yaml\nid: %s\ntitulo: Task %s\narquivos:\n  cria: [%s]\n  altera: [%s]\ndepende_de: [%s]\nstatus: %s\n```\n\n' "$1" "$1" "$3" "$4" "$5" "$2"
  if [ "$2" = concluida ]; then printf '2026-09-10 · suíte: 3 passed, 0 failed · real: 1 h\n\n'; fi
}
k_sprint() { # k_sprint <arquivo> <nn> <kind> <id|status|cria|altera|depende>...
  local arq="$1" nn="$2" kind="$3" sp id st cr al dp ids=""; shift 3
  for sp; do ids="$ids${ids:+, }${sp%%|*}"; done
  {
    printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: %s\ntrabalho_id: menu\nsprint_id: sprint-%s\natualizado_em: 2026-09-10\n' "$kind" "$nn"
    if [ "$kind" = plano ]; then
      printf 'sprint:\n  titulo: Menu por perfil\n  status: em_andamento\n  criterio_saida: A suite inteira roda com npm test e termina com 0 failed\n  riscos: []\n  fora_de_escopo: []\nfases:\n  - id: F-%s.1\n    titulo: Menu\n    status: em_andamento\n    criterio_saida: O menu mostra so os itens do perfil\n    paralelizavel: false\n    paralela_com: []\n    tasks: [%s]\n' "$nn" "$ids"
    fi
    printf 'tasks:\n'
    for sp; do IFS='|' read -r id st cr al dp <<EOF
$sp
EOF
      k_item "$id" "$st" "$cr" "$al" "$dp"; done
    printf -- '---\n\n# Tasks — Sprint %s\n\n' "$nn"
    for sp; do IFS='|' read -r id st cr al dp <<EOF
$sp
EOF
      k_prosa "$id" "$st" "$cr" "$al" "$dp"; done
  } > "$arq"
}
# k_plano <dir> <c|p> <T-04.03> [T-04.03 altera] [T-04.07?] — c: tasks 01..04.02 concluidas; p: tudo pendente.
k_plano() {
  local f s n st; f="$(kf "$1")"; st=pendente; [ "$2" = c ] && st=concluida
  for s in 01 02 03; do
    mkdir -p "$f/sprint-$s"
    if [ "$s" = 03 ]; then
      k_sprint "$f/sprint-03/tasks.md" 03 tasks "T-03.01|$st|src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx||" \
        "T-03.02|$st|src/ui/rodape.tsx||T-03.01" "T-03.03|$st|src/ui/lateral.tsx||" "T-03.04|$st|src/ui/busca.tsx||"
    else
      k_sprint "$f/sprint-$s/tasks.md" "$s" tasks "T-$s.01|$st|src/m$s/a.ts||" "T-$s.02|$st|src/m$s/b.ts||T-$s.01" \
        "T-$s.03|$st|src/m$s/c.ts||" "T-$s.04|$st|src/m$s/d.ts||"
    fi
  done
  mkdir -p "$f/sprint-04"
  set -- "$1" "$2" "$3" "${4:-src/ui/cabecalho-topo.tsx}" "${5:-}"
  n=""; [ -n "$5" ] && n="T-04.07|pendente|src/menu/atalhos.ts||T-04.03"
  k_sprint "$f/sprint-04/tasks.md" 04 plano "T-04.01|$st|src/menu/organizacao.ts, tests/menu/organizacao.test.ts||" \
    "T-04.02|$st|src/menu/visibilidade.ts, tests/menu/visibilidade.test.ts||T-04.01" \
    "T-04.03|$3|src/menu/perfil.ts, tests/menu/perfil.test.ts|$4|T-04.02" \
    "T-04.04|pendente|src/menu/rotas.ts||T-04.03" "T-04.05|pendente|src/menu/icones.ts||" "T-04.06|pendente|src/menu/ajuda.ts||" ${n:+"$n"}
}
k_aud() { auditoria "$1" menu "$2" "$3"; }
# k_fx <dir> <reprovacoes antes do SIM> <criar args...> — F1..F5 aprovada e F6 executada
# ate T-04.03 bloqueada (gravada, sem commit: task bloqueada nao gera E1). Sem B-NN.
k_fx() {
  local d="$1" n="$2" i f; shift 2; f="$(kf "$d")"
  nova_feature "$d" menu
  pl "$d" criar menu "$@" >/dev/null || return 1
  printf 'decisoes\n' > "$f/00-DECISOES.md"; pl "$d" avanca menu f2 >/dev/null || return 1
  k_plano "$d" p pendente; pl "$d" avanca menu f3 >/dev/null || return 1
  printf 'orquestrador\n' > "$f/ORQUESTRADOR.md"; pl "$d" avanca menu f4 >/dev/null || return 1
  i=0
  while [ "$i" -lt "$n" ]; do
    i=$((i + 1)); k_aud "$d" "$i" NAO; pl "$d" avanca menu f5 >/dev/null || return 1
    printf 'orquestrador v%s\n' "$i" > "$f/ORQUESTRADOR.md"; pl "$d" avanca menu f3 >/dev/null || return 1; pl "$d" avanca menu f4 >/dev/null || return 1
  done
  k_aud "$d" $((n + 1)) SIM; pl "$d" avanca menu f5 >/dev/null || return 1
  [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = aprovado ] || return 1
  # F6 (E1 simulado): 14 tasks concluidas e commitadas; depois T-04.03 bloqueia.
  k_plano "$d" c pendente; git -C "$d" add -A; git -C "$d" commit -q -m "feat(menu): 14 tasks concluidas (E1)"
  k_plano "$d" c bloqueada
}
kcopia() { local d; d="$(mktemp -d "$K/c.XXXXXX")"; rm -rf "$d"; cp -R "$1" "$d"; printf '%s' "$d"; }
FXP="$K/fx-piloto"; k_fx "$FXP" 2 3 buildx 1; afirma "k0-fixture-piloto" $? "2 de 3 reprovacoes, max_replanejamentos_f6 1, 14/18 concluidas, T-04.03 bloqueada"
# Variantes do piloto que so mudam um teto: o frontmatter do checkpoint e trocado e recommitado.
k_variante() { # k_variante <dir> <sed> — e o planejamento continua valido e em F6
  cp -R "$FXP" "$1"
  sed "$2" "$(kf "$1")/00-PLANEJAMENTO.md" > "$K/pl.tmp" && mv "$K/pl.tmp" "$(kf "$1")/00-PLANEJAMENTO.md"     && git -C "$1" commit -q -m variante -- docs/sprintx/features/menu/00-PLANEJAMENTO.md && [ "$(kv "$(pl "$1" fase menu)" fase)" = F6 ]
}
FX2="$K/fx-f6-2"; k_variante "$FX2" 's/^max_replanejamentos_f6: 1$/max_replanejamentos_f6: 2/'; afirma "k0-fixture-teto-f6-2" $? "max_replanejamentos_f6 2"
FX5="$K/fx-f5-5"; k_variante "$FX5" 's/^max_reprovacoes_f5: 3$/max_reprovacoes_f5: 5/'; afirma "k0-fixture-teto-f5-5" $? "2 de 5 reprovacoes"
FXN="$K/fx-f6-null"; k_variante "$FXN" 's/^max_replanejamentos_f6: 1$/max_replanejamentos_f6: null/'; afirma "k0-fixture-f6-nao-declarado" $? "max_replanejamentos_f6 null"
FXL="$K/fx-f6-legado"; cp -R "$FXP" "$FXL"
# Planejamento anterior a este contrato: exatamente as chaves que o P0.1 gravava.
sed -e '/^max_replanejamentos_f6:/d' -e '/^replanejamentos_f6:/d' -e '/^bloqueios_replanejamento_f6:/d' -e '/^tasks_congeladas:/d' \
  -e '/^assinatura_congeladas:/d' -e '/^parciais_replanejamento_f6:/d' -e 's/ · replanejamentos da execução (F6): [^·]*//' "$(kf "$FXL")/00-PLANEJAMENTO.md" > "$K/pl.tmp" \
  && mv "$K/pl.tmp" "$(kf "$FXL")/00-PLANEJAMENTO.md" && git -C "$FXL" commit -q -m legado -- docs/sprintx/features/menu/00-PLANEJAMENTO.md
[ "$(tr -d '\r' < "$(kf "$FXL")/00-PLANEJAMENTO.md" | awk 'NR==1{next} $0=="---"{exit} /^[a-z0-9_]+:/{sub(/:.*/,""); printf "%s ", $0}')" \
  = "expx_schema expx_tool kind trabalho_id max_reprovacoes_f5 orcamento_declarado_por estado reprovacoes atualizado_em historico " ] \
  && [ "$(kv "$(pl "$FXL" fase menu)" fase)" = F6 ]
afirma "k0-fixture-planejamento-legado" $? "forma P0.1, sem o eixo F6, valida e em F6"
# Feature anterior ao 00-PLANEJAMENTO.md: o estado sai do disco (auditoria SIM -> F6).
FXS="$K/fx-sem-planejamento"; cp -R "$FXP" "$FXS"
git -C "$FXS" rm -q docs/sprintx/features/menu/00-PLANEJAMENTO.md && git -C "$FXS" commit -q -m "legado sem planejamento" \
  && [ ! -f "$(kf "$FXS")/00-PLANEJAMENTO.md" ] && s="$(pl "$FXS" fase menu)" && [ "$(kv "$s" fase)" = F6 ] && [ "$(kv "$s" fonte)" = legado ]
afirma "k0-fixture-sem-planejamento" $? "sem 00-PLANEJAMENTO.md, auditoria SIM, fase F6 pela tabela antiga"

# K1. O piloto: entra em replanejar_execucao, consome 1/1, B-01 aberto, concluidas intactas, F5 intacto.
k_inicia() {
  local s="$1" d="$2" f out c0; f="$(kf "$d")"; c0="$(kcong "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'T-04.03 precisa alterar tests/ui/cabecalho-topo.test.tsx, criado pela T-03.01' 'acrescentar o arquivo a T-04.03' >/dev/null || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = iniciado ] && [ "$(kv "$out" estado)" = replanejar_execucao ] && [ "$(kv "$out" proxima)" = F3 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = replanejar_execucao ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" max_replanejamentos_f6)" = 1 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" reprovacoes)" = 2 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" max_reprovacoes_f5)" = 3 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" bloqueios_replanejamento_f6)" = "[B-01]" ] \
    && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|aberto" ] && [ "$(kst "$d" T-04.03)" = bloqueada ] \
    && [ "$(kcong "$d")" = "$c0" ] && [ "$(kv "$(kpl "$s" "$d" fase menu)" fase)" = F3 ] \
    && [ "$(trailer "$d" Estado)" = replanejar_execucao ] && [ "$(trailer "$d" Fase)" = f6 ] && [ "$(trailer "$d" Rodada)" = 1 ] \
    && git -C "$d" diff --quiet HEAD -- docs/sprintx/features/menu \
    && [ "$(tr -d '\r' < "$f/00-PLANEJAMENTO.md" | grep -c '^  - rodada:')" -eq 3 ] || return 1
  c="$(fmv "$f/00-PLANEJAMENTO.md" tasks_congeladas)"
  [ "$c" = "[T-01.01, T-01.02, T-01.03, T-01.04, T-02.01, T-02.02, T-02.03, T-02.04, T-03.01, T-03.02, T-03.03, T-03.04, T-04.01, T-04.02]" ]
}
# K2. Retomada da mesma rodada: nao consome orcamento de novo, em nenhum estado da rodada.
k_retomada() {
  local s="$1" d="$2" f out; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = retomada ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = retomada ] && [ "$(kv "$out" estado)" = aguardando_f4 ] && [ "$(kv "$out" proxima)" = F4 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" max_replanejamentos_f6)" = 2 ] \
    && grep -q '"evento":"replanejamento_execucao_retomado"' "$d/docs/eventos/menu.jsonl"
}
# K3. Antes da nova aprovacao o defeito_de_plano nao se resolve — nem com o plano ja editado.
k_resolver_antes() {
  local s="$1" d="$2" f a; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kbl "$s" "$d" resolver menu B-01 >/dev/null; [ $? -eq 5 ] || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  k_plano "$d" c bloqueada 'src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx'
  a="$(cksum < "$f/00-BLOQUEIOS.md")"
  kbl "$s" "$d" resolver menu B-01 >/dev/null; [ $? -eq 5 ] || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  kbl "$s" "$d" resolver menu B-01 >/dev/null; [ $? -eq 5 ] || return 1
  [ "$(cksum < "$f/00-BLOQUEIOS.md")" = "$a" ] && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|aberto" ] \
    && tr -d '\r' < "$f/00-BLOQUEIOS.md" | grep -qx '    resolvido_em: null'
}
# K4. O ciclo inteiro: plano parcial muda T-04.03 e o futuro; F5 aprova; B-01 resolvido pela
# chave; T-04.03 volta a pendente; concluidas intactas; F6 so com o que resta.
k_aprovacao() {
  local s="$1" d="$2" f c0 out rest; f="$(kf "$d")"; c0="$(kcong "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'T-04.03 precisa alterar tests/ui/cabecalho-topo.test.tsx' 'ampliar ownership' >/dev/null || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  # F3: o mesmo arquivo que a T-03.01 concluida criou entra em `altera` da T-04.03; nasce a T-04.07.
  k_plano "$d" c bloqueada 'src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx' nova
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 4 SIM
  out="$(kpl "$s" "$d" avanca menu f5)" || return 1
  [ "$(kv "$out" estado)" = aprovado ] && [ "$(kv "$out" proxima)" = F6 ] && [ "$(kv "$out" reprovacoes)" = 2 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" bloqueios_replanejamento_f6)" = "[]" ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" tasks_congeladas)" = "[]" ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" assinatura_congeladas)" = null ] \
    && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|resolvido" ] && tr -d '\r' < "$f/00-BLOQUEIOS.md" | grep -q '^B-01 | T-04.03 | .* · resolvido em ' \
    && [ "$(kst "$d" T-04.03)" = pendente ] && tr -d '\r' < "$f/sprint-04/tasks.md" | grep -qx 'status: pendente' \
    && [ "$(kcong "$d")" = "$c0" ] && [ "$(kv "$(kpl "$s" "$d" fase menu)" fase)" = F6 ] \
    && git -C "$d" diff --quiet HEAD -- docs/sprintx/features/menu && [ "$(trailer "$d" Estado)" = aprovado ] || return 1
  tr -d '\r' < "$f/sprint-04/tasks.md" | sed -n '/^  - id: T-04.03$/,/^    suite:/p' | grep -qx '      altera: \[src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx\]' \
    && tr -d '\r' < "$f/sprint-03/tasks.md" | sed -n '/^  - id: T-03.01$/,/^    suite:/p' | grep -qx '      cria: \[src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx\]' || return 1
  rest=""; for t in T-01.01 T-01.02 T-01.03 T-01.04 T-02.01 T-02.02 T-02.03 T-02.04 T-03.01 T-03.02 T-03.03 T-03.04 T-04.01 T-04.02 T-04.03 T-04.04 T-04.05 T-04.06 T-04.07; do
    [ "$(kst "$d" "$t")" = concluida ] || rest="$rest$t "
  done
  [ "$rest" = "T-04.03 T-04.04 T-04.05 T-04.06 T-04.07 " ] \
    && grep -q '"evento":"replanejamento_execucao_aprovado"' "$d/docs/eventos/menu.jsonl" \
    && grep -q '"evento":"bloqueio_resolvido".*"task":"T-04.03"' "$d/docs/eventos/menu.jsonl" \
    && grep -q '"evento":"task_reaberta".*"task":"T-04.03"' "$d/docs/eventos/menu.jsonl" \
    && grep -q '"evento":"replanejamento_execucao_iniciado"' "$d/docs/eventos/menu.jsonl"
}
# K5. Segundo defeito_de_plano com 1/1 consumido: nenhuma rodada nova; estado terminal proprio.
k_segundo_defeito() {
  local s="$1" d="$2" f out; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  k_plano "$d" c bloqueada 'src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx'
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 4 SIM; kpl "$s" "$d" avanca menu f5 >/dev/null || return 1
  # De volta a F6: T-04.04 descobre outro arquivo fora do ownership.
  awk '/^  - id: T-04.04$/{t=1} t && /^    status: pendente$/{print "    status: bloqueada"; t=0; next} {print}' "$f/sprint-04/tasks.md" > "$K/t.tmp" && mv "$K/t.tmp" "$f/sprint-04/tasks.md"
  kbl "$s" "$d" registrar menu T-04.04 defeito_de_plano 'T-04.04 precisa de src/menu/perfil.ts' 'mover o arquivo' >/dev/null || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = esgotado ] && [ "$(kv "$out" estado)" = replanejamento_execucao_esgotado ] && [ "$(kv "$out" proxima)" = PARAR ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = replanejamento_execucao_esgotado ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" reprovacoes)" = 2 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" bloqueios_replanejamento_f6)" = "[]" ] \
    && [ "$(kbloq "$d" B-02)" = "defeito_de_plano|aberto" ] && [ "$(kv "$(kpl "$s" "$d" fase menu)" fase)" = PARAR ] \
    && [ "$(trailer "$d" Estado)" = replanejamento_execucao_esgotado ] \
    && grep -q '"evento":"replanejamento_execucao_esgotado"' "$d/docs/eventos/menu.jsonl" || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null; [ $? -eq 5 ] || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = esgotado ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ]
}
# k_recusa <script> <dir> <motivo> — nada gravado, estado aprovado, contador intacto.
k_recusa() {
  local s="$1" d="$2" f ck h out rc; f="$(kf "$d")"; ck="$(cksum < "$f/00-PLANEJAMENTO.md")"; h="$(git -C "$d" rev-parse HEAD)"
  out="$(kpl "$s" "$d" replanejar-execucao menu)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" replanejamento)" = recusado ] && [ "$(kv "$out" motivo)" = "$3" ] \
    && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = aprovado ] && [ "$(kv "$(kpl "$s" "$d" fase menu)" fase)" = F6 ]
}
# k_recusa_duravel <script> <dir> <motivo> — recusa OPERACIONAL: o terminal
# replanejamento_execucao_recusado gravado com o motivo e persistido num checkpoint; nenhuma
# rodada, contador, task ou bloqueio mexido; um evento. Repetir devolve o mesmo terminal e o
# mesmo motivo sem gravar, commitar nem registrar nada.
k_recusa_duravel() {
  local s="$1" d="$2" f a h n6 st0 bl0 out rc ck ev; f="$(kf "$d")"; a="$f/00-PLANEJAMENTO.md"
  h="$(git -C "$d" rev-parse HEAD)"; n6=0; [ -f "$a" ] && n6="$(fmv "$a" replanejamentos_f6)"
  st0="$(kst "$d" T-04.03)"; bl0="$(kbl "$s" "$d" listar menu)"
  out="$(kpl "$s" "$d" replanejar-execucao menu)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" replanejamento)" = recusado ] && [ "$(kv "$out" motivo)" = "$3" ] \
    && [ "$(kv "$out" estado)" = replanejamento_execucao_recusado ] && [ "$(kv "$out" proxima)" = PARAR ] \
    && [ "$(kv "$out" recusa_replanejamento_f6)" = "$3" ] \
    && [ "$(fmv "$a" estado)" = replanejamento_execucao_recusado ] && [ "$(fmv "$a" recusa_replanejamento_f6)" = "$3" ] \
    && [ "$(fmv "$a" replanejamentos_f6)" = "$n6" ] && [ "$(tr -d '\r' < "$a" | grep -c '^bloqueios_replanejamento_f6: \[B')" -eq 0 ] \
    && [ "$(kst "$d" T-04.03)" = "$st0" ] && [ "$(kbl "$s" "$d" listar menu)" = "$bl0" ] \
    && [ "$(git -C "$d" rev-list --count "$h..HEAD")" -eq 1 ] && [ "$(trailer "$d" Estado)" = replanejamento_execucao_recusado ] \
    && [ "$(trailer "$d" Fase)" = f6 ] && git -C "$d" diff --quiet HEAD -- docs/sprintx/features/menu \
    && [ -z "$(git -C "$d" status --porcelain -- docs/sprintx/features/menu)" ] \
    && [ "$(grep -c "\"evento\":\"replanejamento_execucao_recusado\".*\"detalhe\":\"$3:" "$d/docs/eventos/menu.jsonl")" -eq 1 ] || return 1
  out="$(kpl "$s" "$d" fase menu)"
  [ "$(kv "$out" fase)" = PARAR ] && [ "$(kv "$out" estado)" = replanejamento_execucao_recusado ] \
    && [ "$(kv "$out" recusa_replanejamento_f6)" = "$3" ] && [ "$(kv "$out" persistencia)" = duravel ] || return 1
  h="$(git -C "$d" rev-parse HEAD)"; ck="$(cksum < "$a")"; ev="$(cksum < "$d/docs/eventos/menu.jsonl")"
  out="$(kpl "$s" "$d" replanejar-execucao menu)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" replanejamento)" = recusado ] && [ "$(kv "$out" motivo)" = "$3" ] \
    && [ "$(kv "$out" estado)" = replanejamento_execucao_recusado ] && [ "$(kv "$out" proxima)" = PARAR ] \
    && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ] && [ "$(cksum < "$d/docs/eventos/menu.jsonl")" = "$ev" ] \
    && [ "$(kst "$d" T-04.03)" = "$st0" ] && [ "$(kbl "$s" "$d" listar menu)" = "$bl0" ] || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null; [ $? -eq 5 ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ]
}
# K6-K8. Classes que nao iniciam replanejamento — com descricao que "fala" de defeito de plano.
k_lacuna() {
  kbl "$1" "$2" registrar menu T-04.03 lacuna_de_decisao 'arquivo fora do ownership da task: defeito de plano, replanejar' 'decidir' >/dev/null || return 1
  k_recusa "$1" "$2" sem_defeito_de_plano
}
k_prerequisito() {
  kbl "$1" "$2" registrar menu T-04.03 prerequisito_ausente 'o plano precisa mudar: arquivo fora do ownership' 'provisionar' >/dev/null || return 1
  k_recusa "$1" "$2" sem_defeito_de_plano
}
k_legado_bloqueio() {
  cat > "$(kf "$2")/00-BLOQUEIOS.md" <<'EOF'
---
expx_schema: 1
expx_tool: sprintx
kind: bloqueios
trabalho_id: menu
atualizado_em: 2026-09-12
bloqueios:
  - id: B-01
    task: T-04.03
    aberto_em: 2026-09-12
    resolvido_em: null
    descricao: T-04.03 precisa alterar tests/ui/cabecalho-topo.test.tsx, fora do ownership da task, defeito_de_plano
---

# Bloqueios

B-01 | T-04.03 | T-04.03 precisa alterar tests/ui/cabecalho-topo.test.tsx, fora do ownership da task | replanejar
EOF
  [ "$(kbloq "$2" B-01)" = "legado|aberto" ] && k_recusa "$1" "$2" sem_defeito_de_plano
}
# K9. Mistura de classes abertas: nenhuma precedencia inventada, nenhuma rodada; a recusa e o
# terminal duravel `classes_mistas`, e o motivo nao e reavaliado depois.
k_mistura() {
  local s="$1" d="$2" f h out rc; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kbl "$s" "$d" registrar menu null prerequisito_ausente 'o plano precisa mudar: servico de icones fora do ar' 'religar' >/dev/null || return 1
  k_recusa_duravel "$s" "$d" classes_mistas && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" max_replanejamentos_f6)" = 1 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" reprovacoes)" = 2 ] \
    && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|aberto" ] && [ "$(kbloq "$d" B-02)" = "prerequisito_ausente|aberto" ] \
    && [ "$(kst "$d" T-04.03)" = bloqueada ] || return 1
  # Resolvido o prerequisito, so defeito_de_plano fica aberto: o terminal nao muda.
  h="$(git -C "$d" rev-parse HEAD)"; kbl "$s" "$d" resolver menu B-02 >/dev/null || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" motivo)" = classes_mistas ] && [ "$(kv "$out" estado)" = replanejamento_execucao_recusado ] \
    && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" recusa_replanejamento_f6)" = classes_mistas ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" bloqueios_replanejamento_f6)" = "[]" ]
}
# K10. Varios defeito_de_plano abertos: uma rodada, lista em ordem de id (mesmo com o arquivo
# fora de ordem), B-NN sem task resolvido sem inventar task, e so os da rodada sao resolvidos.
k_varios() {
  local s="$1" d="$2" f out; f="$(kf "$d")"
  awk '/^  - id: T-04.05$/{t=1} t && /^    status: pendente$/{print "    status: bloqueada"; t=0; next} {print}' "$f/sprint-04/tasks.md" > "$K/v.tmp" && mv "$K/v.tmp" "$f/sprint-04/tasks.md"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kbl "$s" "$d" registrar menu null lacuna_de_decisao 'nenhuma D-NN cobre o icone' 'decidir' >/dev/null || return 1
  kbl "$s" "$d" resolver menu B-02 >/dev/null || return 1
  kbl "$s" "$d" registrar menu null defeito_de_plano 'criterio_saida da F-04.1 sem task que o cumpra' 'nova task' >/dev/null || return 1
  kbl "$s" "$d" registrar menu T-04.05 defeito_de_plano 'depende_de ausente' 'declarar dependencia' >/dev/null || return 1
  # Arquivo fora de ordem: B-04 antes de B-01 no frontmatter.
  awk '/^bloqueios:$/{print; b=1; next} b && /^  - id: B-01$/{g=1} b && /^  - id: B-02$/{g=0} g{h=h $0 "\n"; next} b && /^---$/{printf "%s", h; b=0} {print}' "$f/00-BLOQUEIOS.md" > "$K/b.tmp" && mv "$K/b.tmp" "$f/00-BLOQUEIOS.md"
  [ "$(kbl "$s" "$d" listar menu | tr -d '\r' | cut -f1 | tr '\n' ' ')" = "B-02 B-03 B-04 B-01 " ] || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" bloqueios_replanejamento_f6)" = "B-01,B-03,B-04" ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" bloqueios_replanejamento_f6)" = "[B-01, B-03, B-04]" ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] || return 1
  # Durante a rodada alguem registra B-05: nao pertence a rodada.
  kbl "$s" "$d" registrar menu null prerequisito_ausente 'servico de icones fora do ar' 'religar' >/dev/null || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 4 SIM; kpl "$s" "$d" avanca menu f5 >/dev/null || return 1
  [ "$(kbloq "$d" B-01)" = "defeito_de_plano|resolvido" ] && [ "$(kbloq "$d" B-03)" = "defeito_de_plano|resolvido" ] \
    && [ "$(kbloq "$d" B-04)" = "defeito_de_plano|resolvido" ] && [ "$(kbloq "$d" B-05)" = "prerequisito_ausente|aberto" ] \
    && [ "$(kbloq "$d" B-02)" = "lacuna_de_decisao|resolvido" ] \
    && [ "$(kst "$d" T-04.03)" = pendente ] && [ "$(kst "$d" T-04.05)" = pendente ] && [ "$(kst "$d" T-04.04)" = pendente ] \
    && [ "$(grep -c '"evento":"task_reaberta"' "$d/docs/eventos/menu.jsonl")" -eq 2 ]
}
# K11. Planejamento legado (sem o eixo F6): recusa duravel, e nenhum orcamento inventado, nem na
# leitura, nem na gravacao do terminal, nem numa retomada.
k_legado_orcamento() {
  local s="$1" d="$2" f; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  k_recusa_duravel "$s" "$d" orcamento_f6_legado || return 1
  [ "$(kv "$(kpl "$s" "$d" fase menu)" orcamento_f6)" = legado ] || return 1
  kpl "$s" "$d" criar menu 3 buildx 1 >/dev/null; [ $? -eq 4 ] || return 1
  kpl "$s" "$d" criar menu 3 buildx >/dev/null || return 1
  ! fm_tem_k "$f/00-PLANEJAMENTO.md" max_replanejamentos_f6 && ! fm_tem_k "$f/00-PLANEJAMENTO.md" replanejamentos_f6 \
    && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|aberto" ]
}
fm_tem_k() { tr -d '\r' < "$1" | awk -v k="$2" 'NR==1{next} $0=="---"{exit} index($0,k":")==1{a=1} END{exit !a}'; }
# K12. Orcamento da F6 nao declarado (criar sem o quarto argumento): nao abre; recusa duravel, sem 1 presumido.
k_sem_orcamento() {
  kbl "$1" "$2" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  [ "$(fmv "$(kf "$2")/00-PLANEJAMENTO.md" max_replanejamentos_f6)" = null ] && k_recusa_duravel "$1" "$2" orcamento_f6_nao_declarado \
    && [ "$(fmv "$(kf "$2")/00-PLANEJAMENTO.md" max_replanejamentos_f6)" = null ] && [ "$(fmv "$(kf "$2")/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ]
}
# K13. Produto da task bloqueada sujo na arvore: fronteira insegura, nada gravado, nada limpo.
k_fronteira() {
  local s="$1" d="$2" f ck h rc; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  mkdir -p "$d/src/menu"; printf 'export const perfil = 1\n' > "$d/src/menu/perfil.ts"
  printf 'export const x = 2\n' > "$d/src/app.ts"
  ck="$(cksum < "$f/00-PLANEJAMENTO.md")"; h="$(git -C "$d" rev-parse HEAD)"
  kpl "$s" "$d" replanejar-execucao menu >/dev/null; rc=$?
  [ "$rc" -eq 2 ] && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] \
    && [ "$(cat "$d/src/menu/perfil.ts")" = 'export const perfil = 1' ] && [ "$(cat "$d/src/app.ts")" = 'export const x = 2' ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ] && [ "$(git -C "$d" stash list | wc -l | tr -d ' ')" = 0 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = aprovado ] && ! fm_tem_k "$f/00-PLANEJAMENTO.md" recusa_replanejamento_f6 \
    && [ "$(kv "$(kpl "$s" "$d" fase menu)" fase)" = F6 ] && [ "$(grep -c '"detalhe":"fronteira insegura' "$d/docs/eventos/menu.jsonl")" -eq 1 ]
}
# K14. F5 reprova durante a rodada: o contador da F5 continua de onde estava (2 -> 3 de 5)...
k_f5_nao_continua() {
  local s="$1" d="$2" f out c0; f="$(kf "$d")"; c0="$(kcong "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 4 NAO; out="$(kpl "$s" "$d" avanca menu f5)" || return 1
  [ "$(kv "$out" estado)" = replanejar ] && [ "$(kv "$out" reprovacoes)" = 3 ] && [ "$(kv "$out" max_reprovacoes_f5)" = 5 ] \
    && [ "$(kv "$out" replanejamento_execucao)" = ativo ] && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|aberto" ] || return 1
  k_plano "$d" c bloqueada 'src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx'
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 5 SIM; out="$(kpl "$s" "$d" avanca menu f5)" || return 1
  [ "$(kv "$out" estado)" = aprovado ] && [ "$(kv "$out" reprovacoes)" = 3 ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] \
    && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|resolvido" ] && [ "$(kst "$d" T-04.03)" = pendente ] && [ "$(kcong "$d")" = "$c0" ] \
    && [ "$(tr -d '\r' < "$f/00-PLANEJAMENTO.md" | grep -c '^  - rodada:')" -eq 5 ]
}
# ...e, esgotado, cai no terminal que a F5 ja tinha (2 -> 3 de 3): sem segundo reset.
k_f5_nao_esgota() {
  local s="$1" d="$2" f out; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 4 NAO; out="$(kpl "$s" "$d" avanca menu f5)" || return 1
  [ "$(kv "$out" estado)" = orcamento_esgotado ] && [ "$(kv "$out" reprovacoes)" = 3 ] && [ "$(kv "$out" proxima)" = PARAR ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|aberto" ] \
    && [ "$(kst "$d" T-04.03)" = bloqueada ] || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null; [ $? -eq 5 ] || return 1
  kbl "$s" "$d" resolver menu B-01 >/dev/null; [ $? -eq 5 ]
}
# K15. Reescrever historia concluida durante a rodada: cada portao recusa (codigo 4) e nada registra.
k_concluidas_protegidas() {
  local s="$1" d="$2" f ck m rc o="$K/orig.$$"; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  mkdir -p "$o"; cp "$f/sprint-03/tasks.md" "$o/s3"; cp "$f/sprint-04/tasks.md" "$o/s4"; ck="$(cksum < "$f/00-PLANEJAMENTO.md")"
  # ampliar `arquivos`; reabrir; renumerar; concluir sem executar; reescrever a prosa; apagar.
  for m in     "sprint-03|/^  - id: T-03.01\$/,/^    suite:/s/^      altera: \[\]\$/      altera: [src\/x.ts]/"     "sprint-04|/^  - id: T-04.02\$/,/^    suite:/s/^    status: concluida\$/    status: pendente/"     "sprint-04|s/^  - id: T-04.01\$/  - id: T-04.11/"     "sprint-04|/^  - id: T-04.06\$/,/^    suite:/s/^    status: pendente\$/    status: concluida/"     "sprint-03|s/^2026-09-10 · suíte: 3 passed, 0 failed · real: 1 h\$/2026-09-10 · suíte: 9 passed, 0 failed · real: 1 h/"     "sprint-04|/^  - id: T-04.02\$/,/^    suite:/d"; do
    cp "$o/s3" "$f/sprint-03/tasks.md"; cp "$o/s4" "$f/sprint-04/tasks.md"
    sed "${m#*|}" "$f/${m%%|*}/tasks.md" > "$K/m.tmp" && mv "$K/m.tmp" "$f/${m%%|*}/tasks.md"
    if cmp -s "$o/s3" "$f/sprint-03/tasks.md" && cmp -s "$o/s4" "$f/sprint-04/tasks.md"; then return 1; fi
    kpl "$s" "$d" avanca menu f3 >/dev/null; rc=$?
    [ "$rc" -eq 4 ] && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = replanejar_execucao ] || return 1
  done
  cp "$o/s3" "$f/sprint-03/tasks.md"; cp "$o/s4" "$f/sprint-04/tasks.md"
  kpl "$s" "$d" avanca menu f3 >/dev/null
}
# K16. A task do B-NN tem de estar gravada como bloqueada antes da transicao.
k_task_nao_bloqueada() {
  local s="$1" d="$2" f ck rc; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.04 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  ck="$(cksum < "$f/00-PLANEJAMENTO.md")"
  kpl "$s" "$d" replanejar-execucao menu >/dev/null; rc=$?
  [ "$rc" -eq 4 ] && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ]
}
# K24. Feature sem 00-PLANEJAMENTO.md: recusa duravel `planejamento_legado`; o arquivo nasce pela
# migracao ja no terminal, sem orcamento nenhum inventado.
k_planejamento_legado() {
  local s="$1" d="$2" f; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  k_recusa_duravel "$s" "$d" planejamento_legado || return 1
  [ "$(fmv "$f/00-PLANEJAMENTO.md" max_replanejamentos_f6)" = null ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" max_reprovacoes_f5)" = null ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" orcamento_declarado_por)" = null ] \
    && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|aberto" ]
}
# K25. Sem worktree: a recusa e o motivo sobrevivem so no que foi commitado. A arvore da execucao
# e perdida; um clone da branch (sem rastro, sem sessao) reconhece o mesmo terminal.
k_sem_worktree() {
  local s="$1" d="$2" c out rc h
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kbl "$s" "$d" registrar menu null prerequisito_ausente 'servico de icones fora do ar' 'religar' >/dev/null || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null; [ $? -eq 5 ] || return 1
  c="$(mktemp -d "$K/clone.XXXXXX")"; rm -rf "$c"
  git clone -q -c core.autocrlf=false -b feature/menu "$d" "$c" || return 1
  rm -rf "$d"; [ ! -e "$d" ] && [ ! -e "$c/docs/eventos" ] || return 1
  out="$(kpl "$s" "$c" fase menu)"; rc=$?
  [ "$rc" -eq 0 ] && [ "$(kv "$out" fase)" = PARAR ] && [ "$(kv "$out" estado)" = replanejamento_execucao_recusado ] \
    && [ "$(kv "$out" recusa_replanejamento_f6)" = classes_mistas ] && [ "$(kv "$out" persistencia)" = duravel ] || return 1
  h="$(git -C "$c" rev-parse HEAD)"
  out="$(kpl "$s" "$c" replanejar-execucao menu)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" replanejamento)" = recusado ] && [ "$(kv "$out" motivo)" = classes_mistas ] \
    && [ "$(kv "$out" proxima)" = PARAR ] && [ "$(git -C "$c" rev-parse HEAD)" = "$h" ] \
    && [ -z "$(git -C "$c" status --porcelain)" ] && [ ! -e "$c/docs/eventos" ] \
    && [ "$(fmv "$(kf "$c")/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ]
}
# K26. Erros de contrato nao viram recusa gravada: sem bloqueio aberto, registro invalido.
k_sem_bloqueio() {
  k_recusa "$1" "$2" sem_bloqueio_aberto && ! fm_tem_k "$(kf "$2")/00-PLANEJAMENTO.md" recusa_replanejamento_f6
}
k_registro_invalido() {
  local s="$1" d="$2" f ck h rc; f="$(kf "$d")"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kbl "$s" "$d" registrar menu null prerequisito_ausente 'servico de icones fora do ar' 'religar' >/dev/null || return 1
  sed 's/^    classe: prerequisito_ausente$/    classe: prerequisito/' "$f/00-BLOQUEIOS.md" > "$K/r.tmp" && mv "$K/r.tmp" "$f/00-BLOQUEIOS.md"
  ck="$(cksum < "$f/00-PLANEJAMENTO.md")"; h="$(git -C "$d" rev-parse HEAD)"
  kpl "$s" "$d" replanejar-execucao menu >/dev/null; rc=$?
  [ "$rc" -eq 4 ] && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = aprovado ]
}
# K27. O terminal recusado no schema: chave se e somente se o estado, motivo do enum operacional,
# coerente com o eixo F6. O controle positivo le o terminal valido.
k_recusa_schema() {
  local s="$1" d="$2" a o="$K/sch.$$" rc m; a="$(kf "$d")/00-PLANEJAMENTO.md"; cp "$a" "$o"
  troca_estado() { E_R="$1" awk '$0 == "estado: aprovado" { print ENVIRON["E_R"]; next } { print }' "$o" > "$a"; }
  for m in "aprovado|classes_mistas" "replanejamento_execucao_recusado|" "replanejamento_execucao_recusado|orcamento_f6_legado" \
    "replanejamento_execucao_recusado|sem_defeito_de_plano" "replanejamento_execucao_recusado|fronteira_insegura"; do
    if [ -n "${m#*|}" ]; then troca_estado "estado: ${m%%|*}
recusa_replanejamento_f6: ${m#*|}"; else troca_estado "estado: ${m%%|*}"; fi
    cmp -s "$o" "$a" && return 1
    kpl "$s" "$d" fase menu >/dev/null; rc=$?; [ "$rc" -eq 4 ] || return 1
  done
  troca_estado "estado: replanejamento_execucao_recusado
recusa_replanejamento_f6: classes_mistas"
  git -C "$d" commit -q -m recusado -- docs/sprintx/features/menu/00-PLANEJAMENTO.md || return 1
  [ "$(kv "$(kpl "$s" "$d" fase menu)" fase)" = PARAR ]
}
# Contrato da autorizacao tardia do orcamento F6: o trio de auditoria e atomico,
# preservado pelos escritores e suficiente para autorizar o eixo F6 sem forjar o dono compartilhado.
k_aut_ativa() {
  local s="$1" d="$2"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  [ "$(fmv "$(kf "$d")/00-PLANEJAMENTO.md" estado)" = replanejar_execucao ]
}
k_aut_campos() {
  local a="$1" por="${2:-}" em="${3:-}" origem="${4:-}"
  K_AUT_POR="$por" K_AUT_EM="$em" K_AUT_ORIGEM="$origem" awk '
    /^orcamento_declarado_por:/ {
      print
      if (length(ENVIRON["K_AUT_POR"])) print "autorizacao_tardia_f6_por: " ENVIRON["K_AUT_POR"]
      if (length(ENVIRON["K_AUT_EM"])) print "autorizacao_tardia_f6_em: " ENVIRON["K_AUT_EM"]
      if (length(ENVIRON["K_AUT_ORIGEM"])) print "autorizacao_tardia_f6_origem: " ENVIRON["K_AUT_ORIGEM"]
      next
    }
    { print }
  ' "$a" > "$K/aut.tmp" && mv "$K/aut.tmp" "$a"
}
k_aut_trio() {
  k_aut_campos "$1" "${2:-usuario}" "${3:-2026-10-12}" "${4:-orcamento_f6_nao_declarado}"
}
k_aut_all_or_none() {
  local s="$1" d a rc
  d="$(kcopia "$FXP")"; k_aut_ativa "$s" "$d" || return 1; a="$(kf "$d")/00-PLANEJAMENTO.md"
  k_aut_campos "$a" usuario '' '' || return 1
  kpl "$s" "$d" fase menu >/dev/null; rc=$?; [ "$rc" -eq 4 ] || return 1
  d="$(kcopia "$FXP")"; k_aut_ativa "$s" "$d" || return 1; a="$(kf "$d")/00-PLANEJAMENTO.md"
  k_aut_campos "$a" usuario 2026-10-12 '' || return 1
  kpl "$s" "$d" fase menu >/dev/null; rc=$?; [ "$rc" -eq 4 ]
}
k_aut_preserva_dono() {
  local s="$1" d="$2" a; a="$(kf "$d")/00-PLANEJAMENTO.md"
  k_aut_ativa "$s" "$d" || return 1; k_aut_trio "$a" usuario || return 1
  git -C "$d" add -- "$a" && git -C "$d" commit -q -m 'audit late f6' -- "$a" || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null || return 1
  [ "$(fmv "$a" orcamento_declarado_por)" = buildx ] \
    && [ "$(fmv "$a" autorizacao_tardia_f6_por)" = usuario ] \
    && [ "$(fmv "$a" autorizacao_tardia_f6_em)" = 2026-10-12 ] \
    && [ "$(fmv "$a" autorizacao_tardia_f6_origem)" = orcamento_f6_nao_declarado ]
}
k_aut_dono_tardio() {
  local s="$1" d="$2" a rc; a="$(kf "$d")/00-PLANEJAMENTO.md"
  k_aut_ativa "$s" "$d" || return 1
  sed -e 's/^max_reprovacoes_f5: [0-9][0-9]*$/max_reprovacoes_f5: null/' -e 's/^orcamento_declarado_por: buildx$/orcamento_declarado_por: null/' "$a" > "$K/aut.tmp" && mv "$K/aut.tmp" "$a"
  k_aut_trio "$a" usuario || return 1
  git -C "$d" add -- "$a" && git -C "$d" commit -q -m 'late f6 owner' -- "$a" || return 1
  kpl "$s" "$d" fase menu >/dev/null || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null || return 1
  [ "$(fmv "$a" orcamento_declarado_por)" = null ] \
    && [ "$(fmv "$a" autorizacao_tardia_f6_por)" = usuario ] \
    && [ "$(fmv "$a" autorizacao_tardia_f6_origem)" = orcamento_f6_nao_declarado ] || return 1
  d="$(kcopia "$FXP")"; k_aut_ativa "$s" "$d" || return 1; a="$(kf "$d")/00-PLANEJAMENTO.md"
  sed -e 's/^max_reprovacoes_f5: [0-9][0-9]*$/max_reprovacoes_f5: null/' -e 's/^orcamento_declarado_por: buildx$/orcamento_declarado_por: null/' "$a" > "$K/aut.tmp" && mv "$K/aut.tmp" "$a"
  kpl "$s" "$d" fase menu >/dev/null; rc=$?
  [ "$rc" -eq 4 ]
}
k_aut_valida_origem_data_recusa() {
  local s="$1" d a rc caso
  for caso in origem data recusa; do
    d="$(kcopia "$FXP")"; k_aut_ativa "$s" "$d" || return 1; a="$(kf "$d")/00-PLANEJAMENTO.md"
    case "$caso" in
      origem) k_aut_trio "$a" usuario 2026-10-12 outra_origem ;;
      data) k_aut_trio "$a" usuario ontem orcamento_f6_nao_declarado ;;
      recusa)
        k_aut_trio "$a" usuario || return 1
        sed '/^estado: replanejar_execucao$/a recusa_replanejamento_f6: classes_mistas' "$a" > "$K/aut.tmp" && mv "$K/aut.tmp" "$a"
        ;;
    esac
    kpl "$s" "$d" fase menu >/dev/null; rc=$?; [ "$rc" -eq 4 ] || return 1
  done
}
k_aut_legado_valido() {
  local s="$1" d="$2" a out; a="$(kf "$d")/00-PLANEJAMENTO.md"
  out="$(kpl "$s" "$d" fase menu)" || return 1
  [ "$(kv "$out" fase)" = F6 ] && ! fm_tem_k "$a" autorizacao_tardia_f6_por \
    && ! fm_tem_k "$a" autorizacao_tardia_f6_em && ! fm_tem_k "$a" autorizacao_tardia_f6_origem
}
# L0. Caracterizacao do abridor compartilhado: congela o comportamento publico e
# a persistencia antes de extrair a mutacao comum de `replanejar-execucao`.
l_abridor_compartilhado() {
  local s="$1" d="$2" f a ev out antes_i antes_c depois_i depois_c soma head_soma paths congeladas
  f="$(kf "$d")"; a="$f/00-PLANEJAMENTO.md"; ev="$d/docs/eventos/menu.jsonl"
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  antes_i="$(grep -c '"evento":"replanejamento_execucao_iniciado"' "$ev" 2>/dev/null || true)"
  antes_c="$(grep -c '"evento":"checkpoint_planejamento"' "$ev" 2>/dev/null || true)"
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  depois_i="$(grep -c '"evento":"replanejamento_execucao_iniciado"' "$ev" 2>/dev/null || true)"
  depois_c="$(grep -c '"evento":"checkpoint_planejamento"' "$ev" 2>/dev/null || true)"
  soma="$(cksum < "$a")"
  head_soma="$(git -C "$d" show HEAD:docs/sprintx/features/menu/00-PLANEJAMENTO.md | cksum)"
  paths="$(git -C "$d" show --pretty= --name-only HEAD | sed '/^$/d')"
  congeladas='[T-01.01, T-01.02, T-01.03, T-01.04, T-02.01, T-02.02, T-02.03, T-02.04, T-03.01, T-03.02, T-03.03, T-03.04, T-04.01, T-04.02]'
  [ "$soma" = "$head_soma" ] && [ $((depois_i - antes_i)) -eq 1 ] && [ $((depois_c - antes_c)) -eq 1 ] \
    && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 17 ] \
    && [ "$(kv "$out" replanejamento)" = iniciado ] && [ "$(kv "$out" estado)" = replanejar_execucao ] \
    && [ "$(kv "$out" reprovacoes)" = 2 ] && [ "$(kv "$out" max_reprovacoes_f5)" = 3 ] \
    && [ "$(kv "$out" proxima)" = F3 ] && [ "$(kv "$out" replanejamentos_f6)" = 1 ] \
    && [ "$(kv "$out" max_replanejamentos_f6)" = 1 ] && [ "$(kv "$out" replanejamento_execucao)" = ativo ] \
    && [ "$(kv "$out" bloqueios_replanejamento_f6)" = B-01 ] \
    && [ "$(fmv "$a" tasks_congeladas)" = "$congeladas" ] \
    && [ "$(kv "$out" parciais_replanejamento_f6)" = '' ] \
    && [ "$(fmv "$a" replanejamentos_f6)" = 1 ] && [ "$(fmv "$a" bloqueios_replanejamento_f6)" = '[B-01]' ] \
    && [ "$(fmv "$a" parciais_replanejamento_f6)" = '[]' ] && [ "$(fmv "$a" assinatura_congeladas)" != null ] \
    && [ "$(trailer "$d" Fase)" = f6 ] && [ "$(trailer "$d" Rodada)" = 1 ] \
    && [ "$(trailer "$d" Estado)" = replanejar_execucao ] \
    && grep -q '"evento":"replanejamento_execucao_iniciado".*"detalhe":"replanejamento da execucao 1 de 1 aberto por \[B-01\]' "$ev" \
    && [ "$paths" = "docs/sprintx/features/menu/00-BLOQUEIOS.md
docs/sprintx/features/menu/00-PLANEJAMENTO.md
docs/sprintx/features/menu/sprint-04/tasks.md" ]
}

l_abridor_parametros() {
  local s="$1" d="$2" r m f a ev out
  r="$K/l0-parametros"; m="$r/scripts/planejamento.sh"
  mkdir -p "$r/scripts/lib" "$r/assets"
  cp "$SK/assets/TEMPLATE-PLANEJAMENTO.md" "$SK/assets/TEMPLATE-BLOQUEIOS.md" "$r/assets/"
  cp "$BL" "$SK/scripts/caminho-git.sh" "$r/scripts/"
  cp "$SK/scripts/lib/trava-autorizacao-f6.sh" "$SK/scripts/lib/execucao.sh" "$r/scripts/lib/"
  muta_lit "$s" "$m" '  abre_rodada_f6 "$defeitos" "$P_MAX6"' \
    '  abre_rodada_f6 "$defeitos" 9 usuario 2026-10-12 orcamento_f6_nao_declarado' || return 1
  chmod +x "$m"
  f="$(kf "$d")"; a="$f/00-PLANEJAMENTO.md"; ev="$d/docs/eventos/menu.jsonl"
  kbl "$m" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  out="$(kpl "$m" "$d" replanejar-execucao menu)" || return 1
  [ "$(fmv "$a" max_replanejamentos_f6)" = 9 ] \
    && [ "$(fmv "$a" autorizacao_tardia_f6_por)" = usuario ] \
    && [ "$(fmv "$a" autorizacao_tardia_f6_em)" = 2026-10-12 ] \
    && [ "$(fmv "$a" autorizacao_tardia_f6_origem)" = orcamento_f6_nao_declarado ] \
    && [ "$(fmv "$a" orcamento_declarado_por)" = buildx ] \
    && [ "$(kv "$out" max_replanejamentos_f6)" = 9 ] \
    && grep -q '"evento":"replanejamento_execucao_iniciado".*"detalhe":"replanejamento da execucao 1 de 9 aberto por \[B-01\]' "$ev"
}
CASOS_K="k_inicia:FXP k_retomada:FX2 k_resolver_antes:FXP k_aprovacao:FXP k_segundo_defeito:FXP k_lacuna:FXP k_prerequisito:FXP
  k_legado_bloqueio:FXP k_mistura:FXP k_varios:FXP k_legado_orcamento:FXL k_sem_orcamento:FXN k_fronteira:FXP
  k_f5_nao_continua:FX5 k_f5_nao_esgota:FXP k_concluidas_protegidas:FXP k_task_nao_bloqueada:FXP
  k_planejamento_legado:FXS k_sem_worktree:FXP k_sem_bloqueio:FXP k_registro_invalido:FXP k_recusa_schema:FXP"
fx_de() { local c; for c in $CASOS_K; do [ "${c%%:*}" = "$1" ] && { eval "printf '%s' \"\$${c#*:}\""; return; }; done; }
roda_k() { local d; d="$(kcopia "$(fx_de "$1")")"; "$1" "$2" "$d"; }
for par in k_inicia:k1-piloto-entra-em-replanejar-execucao k_retomada:k2-retomada-nao-consome-de-novo \
  k_resolver_antes:k3-resolver-antes-da-aprovacao-recusado k_aprovacao:k4-aprovacao-resolve-reabre-preserva \
  k_segundo_defeito:k5-segundo-defeito-apos-1-de-1-esgota k_lacuna:k6-lacuna-de-decisao-nao-replaneja \
  k_prerequisito:k7-prerequisito-ausente-nao-replaneja k_legado_bloqueio:k8-bloqueio-legado-nao-replaneja \
  k_mistura:k9-classes-mistas-nao-replaneja k_varios:k10-varios-defeitos-uma-rodada-ordenada \
  k_legado_orcamento:k11-planejamento-legado-sem-orcamento-inventado k_sem_orcamento:k12-orcamento-f6-nao-declarado-nao-abre \
  k_planejamento_legado:k24-sem-planejamento-recusa-duravel-sem-orcamento k_sem_worktree:k25-recusa-sobrevive-sem-worktree \
  k_sem_bloqueio:k26-sem-bloqueio-aberto-nao-grava k_registro_invalido:k26-registro-invalido-nao-grava \
  k_recusa_schema:k27-terminal-recusado-no-schema \
  k_fronteira:k13-produto-sujo-fronteira-insegura k_f5_nao_continua:k14-f5-nao-durante-rodada-continua \
  k_f5_nao_esgota:k15-f5-esgota-no-terminal-existente k_concluidas_protegidas:k16-concluidas-congeladas-nos-portoes \
  k_task_nao_bloqueada:k17-task-do-bloqueio-precisa-estar-bloqueada; do
  roda_k "${par%%:*}" "$PL"; afirma "${par#*:}" $? "${par%%:*}"
done
for par in k_aut_all_or_none:k23-autorizacao-tardia-trio-all-or-none \
  k_aut_preserva_dono:k24-autorizacao-tardia-preserva-dono-compartilhado \
  k_aut_dono_tardio:k25-autorizacao-tardia-null-compartilhado-valido \
  k_aut_valida_origem_data_recusa:k26-autorizacao-tardia-origem-data-e-recusa \
  k_aut_legado_valido:k27-planejamento-antigo-continua-valido; do
  d="$(kcopia "$FXP")"
  "${par%%:*}" "$PL" "$d"; afirma "${par#*:}" $? "${par%%:*}"
done
d="$(kcopia "$FXP")"; l_abridor_compartilhado "$PL" "$d"
afirma "l0-abridor-compartilhado-preserva-replanejar-execucao" $? "stdout, eventos, checkpoint, eixo F6, checksum e paths"
d="$(kcopia "$FXP")"; l_abridor_parametros "$PL" "$d"
afirma "l0-abridor-parametros-persistem-teto-e-auditoria" $? "teto, trio tardio, dono compartilhado e evento"

# Autorizacao tardia do orcamento F6: a fixture chega ao terminal pelo caminho publico real,
# nunca por edicao direta do estado. A Task 4 cobre somente a primeira aplicacao; retomada e
# checkpoint pendente pertencem a Task 5.
l_aut_terminal() { # l_aut_terminal <script> <repo>
  local s="$1" d="$2" out rc
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo da task irma' 'ampliar ownership' >/dev/null || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" estado)" = replanejamento_execucao_recusado ] \
    && [ "$(kv "$out" motivo)" = orcamento_f6_nao_declarado ] \
    && [ "$(fmv "$(kf "$d")/00-PLANEJAMENTO.md" max_replanejamentos_f6)" = null ]
}
l_aut_aplica() { kpl "$1" "$2" autorizar-replanejamento-execucao menu "${3:-2}" "${4:-usuario}"; }

l_aut_limpa() {
  local s="$1" d="$2" f a ev out h n; f="$(kf "$d")"; a="$f/00-PLANEJAMENTO.md"; ev="$d/docs/eventos/menu.jsonl"
  l_aut_terminal "$s" "$d" || return 1
  h="$(git -C "$d" rev-parse HEAD)"; n="$(git -C "$d" rev-list --count "$h..HEAD")"
  out="$(l_aut_aplica "$s" "$d" 2 usuario)" || return 1
  [ "$(kv "$out" autorizacao_f6)" = aplicada ] && [ "$(kv "$out" estado)" = replanejar_execucao ] \
    && [ "$(kv "$out" replanejamentos_f6)" = 1 ] && [ "$(kv "$out" max_replanejamentos_f6)" = 2 ] \
    && [ "$(kv "$out" autorizado_por)" = usuario ] && [ "$(kv "$out" proxima)" = F3 ] \
    && [ "$(kv "$out" persistencia)" = duravel ] \
    && [ "$(fmv "$a" autorizacao_tardia_f6_por)" = usuario ] \
    && [ "$(fmv "$a" autorizacao_tardia_f6_em)" = "$(date +%Y-%m-%d)" ] \
    && [ "$(fmv "$a" autorizacao_tardia_f6_origem)" = orcamento_f6_nao_declarado ] \
    && [ "$(fmv "$a" orcamento_declarado_por)" = buildx ] && ! fm_tem_k "$a" recusa_replanejamento_f6 \
    && [ "$(git -C "$d" rev-list --count "$h..HEAD")" -eq $((n + 1)) ] \
    && [ "$(grep -c '"evento":"orcamento_f6_autorizado"' "$ev")" -eq 1 ] \
    && [ "$(grep -c '"evento":"replanejamento_execucao_iniciado"' "$ev")" -eq 1 ] \
    && [ "$(trailer "$d" Fase)" = f6 ] && [ "$(trailer "$d" Rodada)" = 1 ] \
    && [ "$(trailer "$d" Estado)" = replanejar_execucao ]
}

l_aut_parciais() {
  local s="$1" d="$2" f a out p; f="$(kf "$d")"; a="$f/00-PLANEJAMENTO.md"
  sed 's|      altera: \[src/ui/cabecalho-topo.tsx\]|      altera: [src/partial/mod.ts, src/partial/del.ts]|' "$f/sprint-04/tasks.md" > "$K/ap.tmp" && mv "$K/ap.tmp" "$f/sprint-04/tasks.md"
  mkdir -p "$d/src/partial"; printf 'antes\n' > "$d/src/partial/mod.ts"; printf 'remover\n' > "$d/src/partial/del.ts"
  git -C "$d" add "$f/sprint-04/tasks.md" src/partial/mod.ts src/partial/del.ts \
    && git -C "$d" commit -q -m 'fixture: parciais rastreados' || return 1
  mkdir -p "$d/src/menu"; printf 'novo\n' > "$d/src/menu/perfil.ts"; printf 'depois\n' > "$d/src/partial/mod.ts"; rm "$d/src/partial/del.ts"
  l_aut_terminal "$s" "$d" || return 1
  out="$(l_aut_aplica "$s" "$d")" || return 1
  p="$(tr -d '\r' < "$a" | awk '
    /^parciais_replanejamento_f6:/ { em=1; next }
    em && /^[^ ]/ { exit }
    em && /^  - path:/ { path=$3; gsub(/^"|"$/, "", path) }
    em && /^    task:/ { task=$2 }
    em && /^    estado:/ { estado=$2 }
    em && /^    hash:/ { print path "\t" task "\t" estado "\t" $2 }
  ')"
  [ "$(kv "$out" autorizacao_f6)" = aplicada ] \
    && printf '%s\n' "$p" | grep -q '^src/menu/perfil.ts[[:space:]]T-04.03[[:space:]]novo[[:space:]]' \
    && printf '%s\n' "$p" | grep -q '^src/partial/mod.ts[[:space:]]T-04.03[[:space:]]modificado[[:space:]]' \
    && printf '%s\n' "$p" | grep -q '^src/partial/del.ts[[:space:]]T-04.03[[:space:]]removido[[:space:]]' \
    && [ "$(cat "$d/src/menu/perfil.ts")" = novo ] && [ "$(cat "$d/src/partial/mod.ts")" = depois ] && [ ! -e "$d/src/partial/del.ts" ]
}

l_aut_dono_e_clone() {
  local s="$1" d="$2" f a c out; f="$(kf "$d")"; a="$f/00-PLANEJAMENTO.md"
  sed -e 's/^max_reprovacoes_f5: [0-9][0-9]*$/max_reprovacoes_f5: null/' -e 's/^orcamento_declarado_por: buildx$/orcamento_declarado_por: null/' "$a" > "$K/ad.tmp" && mv "$K/ad.tmp" "$a"
  git -C "$d" add "$a" && git -C "$d" commit -q -m 'fixture: dono compartilhado nulo' || return 1
  l_aut_terminal "$s" "$d" && l_aut_aplica "$s" "$d" 3 humano >/dev/null || return 1
  [ "$(fmv "$a" orcamento_declarado_por)" = null ] && [ "$(fmv "$a" autorizacao_tardia_f6_por)" = humano ] || return 1
  c="$(mktemp -d "$K/aut-clone.XXXXXX")"; rm -rf "$c"; git clone -q -b feature/menu "$d" "$c" || return 1
  out="$(kpl "$s" "$c" fase menu)" || return 1
  [ "$(kv "$out" estado)" = replanejar_execucao ] && [ "$(kv "$out" autorizacao_tardia_f6_por)" = humano ] \
    && [ "$(kv "$out" max_replanejamentos_f6)" = 3 ] && [ "$(kv "$out" persistencia)" = duravel ]
}

l_aut_argumentos() {
  local s="$1" d="$2" a ck h rc x por
  l_aut_terminal "$s" "$d" || return 1; a="$(kf "$d")/00-PLANEJAMENTO.md"; ck="$(cksum < "$a")"; h="$(git -C "$d" rev-parse HEAD)"
  for x in 0 01 -1 x null; do kpl "$s" "$d" autorizar-replanejamento-execucao menu "$x" usuario >/dev/null; rc=$?; [ "$rc" -eq 4 ] || { printf 'arg max=%s rc=%s\n' "$x" "$rc" >&2; return 1; }; done
  for por in null Usuario 'humano!' '-x'; do kpl "$s" "$d" autorizar-replanejamento-execucao menu 2 "$por" >/dev/null; rc=$?; [ "$rc" -eq 4 ] || { printf 'arg por=%s rc=%s\n' "$por" "$rc" >&2; return 1; }; done
  kpl "$s" "$d" autorizar-replanejamento-execucao menu 2 >/dev/null; rc=$?; [ "$rc" -eq 64 ] || { printf 'arg aridade rc=%s\n' "$rc" >&2; return 1; }
  [ "$(cksum < "$a")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ]
}

l_aut_bloqueios() {
  local s="$1" d="$2" f a ck h rc caso
  for caso in sem classe mista invalido task; do
    d="$(kcopia "$FXN")"; f="$(kf "$d")"; a="$f/00-PLANEJAMENTO.md"; l_aut_terminal "$s" "$d" || return 1
    case "$caso" in
      sem) sed 's/^    resolvido_em: null$/    resolvido_em: 2026-10-12/' "$f/00-BLOQUEIOS.md" > "$K/ab.tmp" && mv "$K/ab.tmp" "$f/00-BLOQUEIOS.md" ;;
      classe) sed 's/^    classe: defeito_de_plano$/    classe: prerequisito_ausente/' "$f/00-BLOQUEIOS.md" > "$K/ab.tmp" && mv "$K/ab.tmp" "$f/00-BLOQUEIOS.md" ;;
      mista) kbl "$s" "$d" registrar menu null prerequisito_ausente 'servico' 'religar' >/dev/null || return 1 ;;
      invalido) sed 's/^    classe: defeito_de_plano$/    classe: defeito/' "$f/00-BLOQUEIOS.md" > "$K/ab.tmp" && mv "$K/ab.tmp" "$f/00-BLOQUEIOS.md" ;;
      task) sed '/^  - id: T-04.03$/,/^    suite:/s/^    status: bloqueada$/    status: pendente/' "$f/sprint-04/tasks.md" > "$K/at.tmp" && mv "$K/at.tmp" "$f/sprint-04/tasks.md" ;;
    esac
    ck="$(cksum < "$a")"; h="$(git -C "$d" rev-parse HEAD)"; kpl "$s" "$d" autorizar-replanejamento-execucao menu 2 usuario >/dev/null; rc=$?
    [ "$rc" -eq 4 ] && [ "$(cksum < "$a")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] \
      || { printf 'bloqueio caso=%s rc=%s estado=%s\n' "$caso" "$rc" "$(fmv "$a" estado 2>/dev/null)" >&2; return 1; }
  done
}

l_aut_fronteira() {
  local s="$1" d="$2" f a ck h rc caso
  for caso in nao_declarado staged segredo env task_irma compartilhado concluida symlink; do
    d="$(kcopia "$FXN")"; f="$(kf "$d")"; a="$f/00-PLANEJAMENTO.md"; l_aut_terminal "$s" "$d" || return 1
    case "$caso" in
      nao_declarado) printf 'x\n' > "$d/fora.txt" ;;
      staged) mkdir -p "$d/src/menu"; printf 'x\n' > "$d/src/menu/perfil.ts"; git -C "$d" add src/menu/perfil.ts ;;
      segredo) mkdir -p "$d/src/menu"; printf 'sk-1234567890123456789012345\n' > "$d/src/menu/perfil.ts" ;;
      env)
        printf 'NAO_E_SEGREDO=1\n' > "$d/.env"
        sed '/^  - id: T-04.03$/,/^    suite:/s|^      altera: \[src/ui/cabecalho-topo.tsx\]$|      altera: [src/ui/cabecalho-topo.tsx, .env]|' \
          "$f/sprint-04/tasks.md" > "$K/af.tmp" && mv "$K/af.tmp" "$f/sprint-04/tasks.md"
        ;;
      task_irma) mkdir -p "$d/src/menu"; printf 'x\n' > "$d/src/menu/rotas.ts" ;;
      compartilhado)
        mkdir -p "$d/src/menu"; printf 'x\n' > "$d/src/menu/perfil.ts"
        sed '/^  - id: T-04.04$/,/^    suite:/s/^      altera: \[\]$/      altera: [src\/menu\/perfil.ts]/' "$f/sprint-04/tasks.md" > "$K/af.tmp" && mv "$K/af.tmp" "$f/sprint-04/tasks.md" ;;
      concluida)
        mkdir -p "$d/src/ui"; printf 'x\n' > "$d/src/ui/cabecalho-topo.tsx" ;;
      symlink)
        mkdir -p "$d/src/menu"; ln -s ../alvo-inexistente "$d/src/menu/perfil.ts" ;;
    esac
    ck="$(cksum < "$a")"; h="$(git -C "$d" rev-parse HEAD)"; kpl "$s" "$d" autorizar-replanejamento-execucao menu 2 usuario >/dev/null; rc=$?
    [ "$rc" -eq 2 ] && [ "$(cksum < "$a")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] || return 1
  done
}

l_aut_concorrente() {
  local s="$1" d="$2" ev hook lock pid rc2=0; ev="$d/docs/eventos/menu.jsonl"
  l_aut_terminal "$s" "$d" || return 1
  hook="$(git -C "$d" rev-parse --git-path hooks/pre-commit)"; case "$hook" in /*) ;; *) hook="$d/$hook" ;; esac
  mkdir -p "${hook%/*}"; printf '#!/usr/bin/env bash\nsleep 2\n' > "$hook"; chmod +x "$hook"
  lock="$(git -C "$d" rev-parse --git-path sprintx/travas/autorizacao-f6-menu.lock)"; case "$lock" in /*) ;; *) lock="$d/$lock" ;; esac
  (l_aut_aplica "$s" "$d" 2 usuario > "$K/aut-c1.out" 2>&1) & pid=$!
  while [ ! -d "$lock" ]; do kill -0 "$pid" 2>/dev/null || { wait "$pid"; return 1; }; sleep 0.05; done
  l_aut_aplica "$s" "$d" 2 usuario > "$K/aut-c2.out" 2>&1; rc2=$?
  wait "$pid" || return 1
  [ "$rc2" -eq 2 ] && [ "$(kv "$(cat "$K/aut-c1.out")" autorizacao_f6)" = aplicada ] \
    && [ "$(grep -c '"evento":"orcamento_f6_autorizado"' "$ev")" -eq 1 ] \
    && [ "$(fmv "$(kf "$d")/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] && [ ! -e "$lock" ]
}

l_aut_terminais() {
  local s="$1" d rc caso a ck h
  for caso in classes legado planejamento esgotado f5_esgotado schema teto_null rodada_zero; do
    case "$caso" in
      classes) d="$(kcopia "$FXP")"; k_mistura "$s" "$d" || return 1 ;;
      legado) d="$(kcopia "$FXL")"; k_legado_orcamento "$s" "$d" || return 1 ;;
      planejamento) d="$(kcopia "$FXS")"; k_planejamento_legado "$s" "$d" || return 1 ;;
      esgotado) d="$(kcopia "$FXP")"; k_segundo_defeito "$s" "$d" || return 1 ;;
      f5_esgotado) d="$(kcopia "$FXP")"; k_f5_nao_esgota "$s" "$d" || return 1 ;;
      schema)
        d="$(kcopia "$FXN")"; l_aut_terminal "$s" "$d" || return 1; a="$(kf "$d")/00-PLANEJAMENTO.md"
        sed 's/^recusa_replanejamento_f6: orcamento_f6_nao_declarado$/recusa_replanejamento_f6: desconhecida/' "$a" > "$K/as.tmp" && mv "$K/as.tmp" "$a" ;;
      teto_null)
        d="$(kcopia "$FXN")"; a="$(kf "$d")/00-PLANEJAMENTO.md"; k_aut_trio "$a" usuario || return 1 ;;
      rodada_zero)
        d="$(kcopia "$FX2")"; a="$(kf "$d")/00-PLANEJAMENTO.md"; k_aut_trio "$a" usuario || return 1 ;;
    esac
    a="$(kf "$d")/00-PLANEJAMENTO.md"; ck="$(cksum < "$a")"; h="$(git -C "$d" rev-parse HEAD)"
    kpl "$s" "$d" autorizar-replanejamento-execucao menu 2 usuario >/dev/null; rc=$?
    case "$caso" in schema|teto_null|rodada_zero) [ "$rc" -eq 4 ] || return 1 ;; *) [ "$rc" -eq 5 ] || return 1 ;; esac
    [ "$(cksum < "$a")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] || return 1
  done
}

l_aut_persistencia_disco() {
  local s="$1" d="$2" a ck h out out2 rc
  l_aut_terminal "$s" "$d" || return 1
  a="$(kf "$d")/00-PLANEJAMENTO.md"; ck="$(cksum < "$a")"; h="$(git -C "$d" rev-parse HEAD)"
  git -C "$d" checkout -q -b outra || return 1
  out="$(l_aut_aplica "$s" "$d" 2 usuario)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" autorizacao_f6)" = recusada ] \
    && [ "$(kv "$out" motivo)" = persistencia_disco ] && [ "$(kv "$out" proxima)" = PARAR ] \
    && [ "$(kv "$out" persistencia)" = disco ] || return 1
  kpl "$s" "$d" checkpoint menu >/dev/null || return 1
  out2="$(l_aut_aplica "$s" "$d" 2 usuario)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out2" motivo)" = persistencia_disco ] \
    && [ "$(kv "$out2" proxima)" = PARAR ] && [ "$(kv "$out2" persistencia)" = disco ] \
    && [ "$(cksum < "$a")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ]
}

l_aut_sem_planejamento_e_sem_marco() {
  local s="$1" d out rc
  d="$(mktemp -d "$K/aut-sem-plano.XXXXXX")"
  nova_feature "$d" menu
  out="$(kpl "$s" "$d" autorizar-replanejamento-execucao menu 2 usuario)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" motivo)" = persistencia_disco ] \
    && ! printf '%s\n' "$out" | grep -q 'unbound variable' || return 1

  d="$(mktemp -d "$K/aut-sem-marco.XXXXXX")"
  nova_feature "$d" menu
  kpl "$s" "$d" criar menu 3 buildx null >/dev/null || return 1
  out="$(kpl "$s" "$d" autorizar-replanejamento-execucao menu 2 usuario)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" motivo)" = persistencia_sem_marco ] \
    && ! printf '%s\n' "$out" | grep -q 'unbound variable'
}

l_aut_trava_ambiente() {
  local s="$1" d out rc resultado=1
  d="$(mktemp -d "$K/aut-sem-git.XXXXXX")"
  out="$(cd "$d" && GIT_CEILING_DIRECTORIES="$K" \
    bash "$s" autorizar-replanejamento-execucao menu 2 usuario 2>&1)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" motivo)" = trava_indisponivel ] \
    && ! printf '%s\n' "$out" | grep -q 'trava existente' && resultado=0
  if [ "$resultado" -ne 0 ]; then
    printf 'l_aut_trava_ambiente: d=%s repo=%s rc=%s motivo=%s git_dir=%s git_work_tree=%s saida=%s\n' \
      "$d" "$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || printf sem-git)" \
      "$rc" "$(kv "$out" motivo)" "${GIT_DIR-}" "${GIT_WORK_TREE-}" "$out" >&2
  fi
  return "$resultado"
}

l_aut_trava() {
  local s="$1" d="$2" p out rc; l_aut_terminal "$s" "$d" || return 1
  p="$(. "$SK/scripts/lib/trava-autorizacao-f6.sh" || exit 1; adquire_trava_autorizacao_f6 "$d" menu || exit 1; printf '%s' "$TRAVA_AUT6_DIR"; libera_trava_autorizacao_f6)" || return 1
  mkdir -p "$p"
  out="$(kpl "$s" "$d" autorizar-replanejamento-execucao menu 2 usuario)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" autorizacao_f6)" = recusada ] \
    && [ "$(kv "$out" motivo)" = trava_existente ] && [ "$(kv "$out" proxima)" = PARAR ] \
    && [ -d "$p" ]; rc=$?; rmdir "$p"; return "$rc"
}

l_aut_terminal_incorreto() {
  local s="$1" d="$2" a ck h rc
  a="$(kf "$d")/00-PLANEJAMENTO.md"; ck="$(cksum < "$a")"; h="$(git -C "$d" rev-parse HEAD)"
  kpl "$s" "$d" autorizar-replanejamento-execucao menu 2 usuario >/dev/null; rc=$?
  [ "$rc" -eq 5 ] && [ "$(cksum < "$a")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ]
}

l_aut_teto_decimal_grande() {
  local s="$1" d="$2" teto out rc
  teto=99999999999999999999999999999999999999999999999999
  l_aut_terminal "$s" "$d" || return 1
  out="$(l_aut_aplica "$s" "$d" "$teto" usuario)"; rc=$?
  [ "$rc" -eq 0 ] && [ "$(kv "$out" autorizacao_f6)" = aplicada ] \
    && [ "$(kv "$out" replanejamentos_f6)" = 1 ] \
    && [ "$(kv "$out" max_replanejamentos_f6)" = "$teto" ] || return 1
  out="$(l_aut_aplica "$s" "$d" "$teto" usuario)" || return 1
  [ "$(kv "$out" autorizacao_f6)" = retomada ] \
    && [ "$(kv "$out" max_replanejamentos_f6)" = "$teto" ]
}

# Task 5 — uma queda no pre-commit deixa a autorizacao gravada no disco, mas o
# HEAD ainda no terminal. A retomada deve reconhecer exatamente esse estado,
# sem repetir evento, contador ou escrita.
l5_deixa_checkpoint_pendente() { # <script> <repo>
  local s="$1" d="$2" hook out rc
  l_aut_terminal "$s" "$d" || return 1
  hook="$(git -C "$d" rev-parse --git-path hooks/pre-commit)"; case "$hook" in /*) ;; *) hook="$d/$hook" ;; esac
  mkdir -p "${hook%/*}"
  printf '#!/usr/bin/env bash\nmarcador="%s/task5-precommit-ja-falhou"\nif [ ! -e "$marcador" ]; then : > "$marcador"; exit 1; fi\nexit 0\n' "$(git -C "$d" rev-parse --git-dir)" > "$hook"
  chmod +x "$hook"
  out="$(l_aut_aplica "$s" "$d" 2 usuario)"; rc=$?
  [ "$rc" -eq 3 ] && [ "$(fmv "$(kf "$d")/00-PLANEJAMENTO.md" estado)" = replanejar_execucao ] \
    && [ "$(fmv "$(kf "$d")/00-PLANEJAMENTO.md" autorizacao_tardia_f6_por)" = usuario ] \
    && [ "$(fmv "$(kf "$d")/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ]
}

l5_checkpoint_e_retomada() {
  local s="$1" d="$2" a ev h ck evck out rc
  a="$(kf "$d")/00-PLANEJAMENTO.md"; ev="$d/docs/eventos/menu.jsonl"
  l5_deixa_checkpoint_pendente "$s" "$d" || return 1
  h="$(git -C "$d" rev-parse HEAD)"; ck="$(cksum < "$a")"; evck="$(cksum < "$ev")"

  out="$(l_aut_aplica "$s" "$d" 2 usuario)"; rc=$?
  [ "$rc" -eq 3 ] && [ "$(kv "$out" autorizacao_f6)" = checkpoint_pendente ] \
    && [ "$(kv "$out" proxima)" = CHECKPOINT ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] \
    && [ "$(cksum < "$a")" = "$ck" ] && [ "$(cksum < "$ev")" = "$evck" ] || return 1

  l_aut_aplica "$s" "$d" 3 usuario >/dev/null; [ $? -eq 4 ] || return 1
  l_aut_aplica "$s" "$d" 2 humano >/dev/null; [ $? -eq 4 ] || return 1
  [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ] && [ "$(cksum < "$ev")" = "$evck" ] || return 1

  out="$(kpl "$s" "$d" checkpoint menu)" || return 1
  [ "$(kv "$out" checkpoint)" = commitado ] && [ "$(git -C "$d" rev-list --count "$h..HEAD")" -eq 1 ] \
    && [ "$(grep -c '"evento":"orcamento_f6_autorizado"' "$ev")" -eq 1 ] \
    && [ "$(grep -c '"evento":"replanejamento_execucao_iniciado"' "$ev")" -eq 1 ] || return 1

  h="$(git -C "$d" rev-parse HEAD)"; ck="$(cksum < "$a")"; evck="$(cksum < "$ev")"
  out="$(l_aut_aplica "$s" "$d" 2 usuario)" || return 1
  [ "$(kv "$out" autorizacao_f6)" = retomada ] && [ "$(kv "$out" estado)" = replanejar_execucao ] \
    && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ] \
    && [ "$(cksum < "$ev")" = "$evck" ] || return 1
  l_aut_aplica "$s" "$d" 4 usuario >/dev/null; [ $? -eq 4 ]
}

l5_pendente_invalido() {
  local s="$1" d caso a ev h ck evck idxck rc
  for caso in bloqueio_resolvido classe task bloqueio_extra; do
    d="$(kcopia "$FXN")"; l5_deixa_checkpoint_pendente "$s" "$d" || return 1
    a="$(kf "$d")/00-PLANEJAMENTO.md"; ev="$d/docs/eventos/menu.jsonl"
    case "$caso" in
      bloqueio_resolvido) sed 's/^    resolvido_em: null$/    resolvido_em: 2026-10-12/' "$(kf "$d")/00-BLOQUEIOS.md" > "$K/l5.tmp" && mv "$K/l5.tmp" "$(kf "$d")/00-BLOQUEIOS.md" ;;
      classe) sed 's/^    classe: defeito_de_plano$/    classe: prerequisito_ausente/' "$(kf "$d")/00-BLOQUEIOS.md" > "$K/l5.tmp" && mv "$K/l5.tmp" "$(kf "$d")/00-BLOQUEIOS.md" ;;
      task) sed '/^  - id: T-04.03$/,/^    suite:/s/^    status: bloqueada$/    status: pendente/' "$(kf "$d")/sprint-04/tasks.md" > "$K/l5.tmp" && mv "$K/l5.tmp" "$(kf "$d")/sprint-04/tasks.md" ;;
      bloqueio_extra) kbl "$s" "$d" registrar menu null prerequisito_ausente \
        'bloqueio concorrente fora da rodada' 'resolver antes do checkpoint' >/dev/null || return 1 ;;
    esac
    h="$(git -C "$d" rev-parse HEAD)"; ck="$(cksum < "$a")"; evck="$(cksum < "$ev")"
    idxck="$(git -C "$d" diff --cached --binary | cksum)"
    l_aut_aplica "$s" "$d" 2 usuario >/dev/null; rc=$?
    [ "$rc" -eq 4 ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ] \
      && [ "$(cksum < "$ev")" = "$evck" ] \
      && [ "$(git -C "$d" diff --cached --binary | cksum)" = "$idxck" ] || return 1
    kpl "$s" "$d" checkpoint menu >/dev/null; rc=$?
    [ "$rc" -eq 4 ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ] \
      && [ "$(cksum < "$ev")" = "$evck" ] \
      && [ "$(git -C "$d" diff --cached --binary | cksum)" = "$idxck" ] || return 1
  done
}

l5_pendente_reordenado() {
  local s="$1" d f a hook out rc
  d="$(kcopia "$FXN")"; f="$(kf "$d")"; a="$f/00-PLANEJAMENTO.md"
  l_aut_terminal "$s" "$d" || return 1
  kbl "$s" "$d" registrar menu null defeito_de_plano \
    'segundo defeito da mesma rodada' 'replanejar os dois defeitos' >/dev/null || return 1

  hook="$(git -C "$d" rev-parse --git-path hooks/pre-commit)"; case "$hook" in /*) ;; *) hook="$d/$hook" ;; esac
  mkdir -p "${hook%/*}"
  printf '#!/usr/bin/env bash\nmarcador="%s/reordena-precommit-ja-falhou"\nif [ ! -e "$marcador" ]; then : > "$marcador"; exit 1; fi\nexit 0\n' \
    "$(git -C "$d" rev-parse --git-dir)" > "$hook"
  chmod +x "$hook"
  out="$(l_aut_aplica "$s" "$d" 2 usuario)"; rc=$?
  [ "$rc" -eq 3 ] && [ "$(fmv "$a" bloqueios_replanejamento_f6)" = '[B-01, B-02]' ] || return 1

  awk '
    NR == 1 && $0 == "---" { fm=1; print; next }
    fm && $0 == "bloqueios:" { lista=1; print; next }
    lista && $0 == "  - id: B-01" { captura=1; b1=$0 ORS; next }
    lista && $0 == "  - id: B-02" { captura=2; b2=$0 ORS; next }
    lista && captura && /^    / {
      if (captura == 1) b1=b1 $0 ORS
      else b2=b2 $0 ORS
      next
    }
    lista {
      printf "%s%s", b2, b1
      lista=0; captura=0
    }
    fm && $0 == "---" { fm=0 }
    { print }
  ' "$f/00-BLOQUEIOS.md" > "$K/l5-reordena.tmp" \
    && mv "$K/l5-reordena.tmp" "$f/00-BLOQUEIOS.md" || return 1
  [ "$(kbl "$s" "$d" listar menu | cut -f1 | paste -sd, -)" = 'B-02,B-01' ] || return 1

  out="$(l_aut_aplica "$s" "$d" 2 usuario)"; rc=$?
  [ "$rc" -eq 3 ] && [ "$(kv "$out" autorizacao_f6)" = checkpoint_pendente ] \
    && [ "$(kv "$out" proxima)" = CHECKPOINT ]
}

l5_parcial_e_congelada_invalidos() {
  local s="$1" d a ev h ck evck rc
  d="$(kcopia "$FXN")"; l5_deixa_checkpoint_pendente "$s" "$d" || return 1
  a="$(kf "$d")/00-PLANEJAMENTO.md"; ev="$d/docs/eventos/menu.jsonl"
  sed '/^  - id: T-03.01$/,/^    suite:/s/^      cria: /      cria: [src\/mudou.ts, /' "$(kf "$d")/sprint-03/tasks.md" > "$K/l5.tmp" && mv "$K/l5.tmp" "$(kf "$d")/sprint-03/tasks.md"
  h="$(git -C "$d" rev-parse HEAD)"; ck="$(cksum < "$a")"; evck="$(cksum < "$ev")"
  l_aut_aplica "$s" "$d" 2 usuario >/dev/null; rc=$?
  [ "$rc" -eq 2 ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ] \
    && [ "$(cksum < "$ev")" = "$evck" ] || return 1

  d="$(kcopia "$FXN")"; sed 's|      altera: \[src/ui/cabecalho-topo.tsx\]|      altera: [src/menu/perfil.ts]|' "$(kf "$d")/sprint-04/tasks.md" > "$K/l5.tmp" && mv "$K/l5.tmp" "$(kf "$d")/sprint-04/tasks.md"
  mkdir -p "$d/src/menu"; printf 'antes\n' > "$d/src/menu/perfil.ts"
  git -C "$d" add "$(kf "$d")/sprint-04/tasks.md" src/menu/perfil.ts && git -C "$d" commit -q -m 'fixture: parcial tardio' || return 1
  printf 'depois\n' > "$d/src/menu/perfil.ts"; l5_deixa_checkpoint_pendente "$s" "$d" || return 1
  a="$(kf "$d")/00-PLANEJAMENTO.md"; ev="$d/docs/eventos/menu.jsonl"; rm "$d/src/menu/perfil.ts"
  h="$(git -C "$d" rev-parse HEAD)"; ck="$(cksum < "$a")"; evck="$(cksum < "$ev")"
  l_aut_aplica "$s" "$d" 2 usuario >/dev/null; rc=$?
  [ "$rc" -eq 2 ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ] \
    && [ "$(cksum < "$ev")" = "$evck" ]
}

# Mesmo depois do primeiro checkpoint duravel, a retomada ainda prova o
# trabalho parcial preservado antes de responder `retomada`.
l5_retomada_duravel_recusa_parcial_perdido() {
  local s="$1" d="$2" f a ev out h ck evck idxck rc
  f="$(kf "$d")"; a="$f/00-PLANEJAMENTO.md"; ev="$d/docs/eventos/menu.jsonl"
  sed 's|      altera: \[src/ui/cabecalho-topo.tsx\]|      altera: [src/menu/perfil.ts]|' \
    "$f/sprint-04/tasks.md" > "$K/l5.tmp" && mv "$K/l5.tmp" "$f/sprint-04/tasks.md"
  mkdir -p "$d/src/menu"; printf 'antes\n' > "$d/src/menu/perfil.ts"
  git -C "$d" add "$f/sprint-04/tasks.md" src/menu/perfil.ts \
    && git -C "$d" commit -q -m 'fixture: parcial tardio duravel' || return 1
  printf 'depois\n' > "$d/src/menu/perfil.ts"
  l_aut_terminal "$s" "$d" && l_aut_aplica "$s" "$d" 2 usuario >/dev/null || return 1
  git -C "$d" checkout -q -- src/menu/perfil.ts
  h="$(git -C "$d" rev-parse HEAD)"; ck="$(cksum < "$a")"; evck="$(cksum < "$ev")"
  idxck="$(git -C "$d" diff --cached --binary | cksum)"
  out="$(l_aut_aplica "$s" "$d" 2 usuario)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" trabalho_parcial)" = perdido ] \
    && [ "$(kv "$out" motivo)" = parcial_perdido ] \
    && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ] \
    && [ "$(cksum < "$ev")" = "$evck" ] \
    && [ "$(git -C "$d" diff --cached --binary | cksum)" = "$idxck" ]
}

l5_fechamento_pendente_e_fechado() {
  local s="$1" d="$2" a ev h ck evck out rc
  a="$(kf "$d")/00-PLANEJAMENTO.md"; ev="$d/docs/eventos/menu.jsonl"
  l_aut_terminal "$s" "$d" && l_aut_aplica "$s" "$d" 2 usuario >/dev/null || return 1
  sed 's/^estado: replanejar_execucao$/estado: aprovado/' "$a" > "$K/l5.tmp" && mv "$K/l5.tmp" "$a"
  h="$(git -C "$d" rev-parse HEAD)"; ck="$(cksum < "$a")"; evck="$(cksum < "$ev")"
  out="$(l_aut_aplica "$s" "$d" 2 usuario)"; rc=$?
  [ "$rc" -eq 3 ] && [ "$(kv "$out" autorizacao_f6)" = fechamento_pendente ] \
    && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ] \
    && [ "$(cksum < "$ev")" = "$evck" ] || return 1
  kpl "$s" "$d" checkpoint menu >/dev/null || return 1
  [ "$(fmv "$a" bloqueios_replanejamento_f6)" = '[]' ] \
    && [ "$(kbloq "$d" B-01)" = 'defeito_de_plano|resolvido' ] \
    && [ "$(kst "$d" T-04.03)" = pendente ] || return 1
  h="$(git -C "$d" rev-parse HEAD)"; ck="$(cksum < "$a")"; evck="$(cksum < "$ev")"
  out="$(l_aut_aplica "$s" "$d" 2 usuario)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" autorizacao_f6)" = fechada ] \
    && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ] \
    && [ "$(cksum < "$ev")" = "$evck" ] || return 1
  out="$(l_aut_aplica "$s" "$d" 9 outro)"; rc=$?
  [ "$rc" -eq 5 ] && [ "$(kv "$out" autorizacao_f6)" = fechada ] \
    && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$a")" = "$ck" ] \
    && [ "$(cksum < "$ev")" = "$evck" ]
}

# A guarda reforcada pertence somente ao primeiro checkpoint da autorizacao.
# Depois que a rodada e duravel, a F3 pode legitimamente remover a task
# bloqueada; os portoes ordinarios e reabre_task ja cobrem esse caso.
l5_portao_posterior_tolera_task_removida() {
  local s="$1" d="$2" f out h
  f="$(kf "$d")"
  l_aut_terminal "$s" "$d" && l_aut_aplica "$s" "$d" 2 usuario >/dev/null || return 1
  k_sprint "$f/sprint-04/tasks.md" 04 plano \
    "T-04.01|concluida|src/menu/organizacao.ts, tests/menu/organizacao.test.ts||" \
    "T-04.02|concluida|src/menu/visibilidade.ts, tests/menu/visibilidade.test.ts||T-04.01" \
    "T-04.04|pendente|src/menu/rotas.ts||T-04.02" \
    "T-04.05|pendente|src/menu/icones.ts||" \
    "T-04.06|pendente|src/menu/ajuda.ts||"
  h="$(git -C "$d" rev-parse HEAD)"
  out="$(l_aut_aplica "$s" "$d" 2 usuario)" || return 1
  [ "$(kv "$out" autorizacao_f6)" = retomada ] \
    && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] || return 1
  out="$(kpl "$s" "$d" avanca menu f3)" || return 1
  [ "$(kv "$out" estado)" = aguardando_f4 ] \
    && [ "$(git -C "$d" rev-list --count "$h..HEAD")" -eq 1 ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" bloqueios_replanejamento_f6)" = '[B-01]' ] \
    && [ "$(kbloq "$d" B-01)" = 'defeito_de_plano|aberto' ] \
    && [ -z "$(kst "$d" T-04.03)" ]
}

for par in l_aut_limpa:l1-autorizacao-tardia-limpa l_aut_parciais:l2-autorizacao-tardia-preserva-tres-parciais \
  l_aut_dono_e_clone:l3-l4-dono-separado-e-clone-le-estado l_aut_argumentos:l6-argumentos-invalidos-nao-gravam \
  l_aut_bloqueios:l7-l8-bloqueios-e-task-invalidos l_aut_fronteira:l9-fronteiras-inseguras-nao-gravam \
  l_aut_concorrente:l14-duas-chamadas-uma-aplica-uma-recusa l_aut_trava:l15-trava-preexistente-falha-fechado \
  l_aut_terminais:l5-l16-l18-l19-terminais-schema-e-legado l_aut_persistencia_disco:l5-persistencia-disco-para-sem-checkpoint \
  l_aut_terminal_incorreto:l5-terminal-nao-autorizado; do
  d="$(kcopia "$FXN")"; "${par%%:*}" "$PL" "$d"; afirma "${par#*:}" $? "${par%%:*}"
done
d="$(kcopia "$FXN")"; l_aut_teto_decimal_grande "$PL" "$d"; afirma "l20-teto-decimal-grande-e-relegivel" $? \
  "inteiro positivo sem limite implicito nao corrompe o planejamento"
d="$(kcopia "$FXN")"; l5_checkpoint_e_retomada "$PL" "$d"; afirma "m1-m4-m7-m10-checkpoint-e-retomada-idempotentes" $? "queda, repeticao, checkpoint, retomada e argumentos"
l5_pendente_invalido "$PL"; afirma "m6-pendente-valida-bloqueio-classe-e-task" $? "comando e checkpoint falham fechados"
l5_pendente_reordenado "$PL"; afirma "m6-pendente-normaliza-ordem-dos-bloqueios" $? "reordenar os mesmos B-NN nao invalida a autorizacao"
l5_parcial_e_congelada_invalidos "$PL"; afirma "m5-congeladas-e-parciais-invalidos-nao-gravam" $? "fronteiras inseguras retornam rc2, sem evento"
d="$(kcopia "$FXN")"; l5_retomada_duravel_recusa_parcial_perdido "$PL" "$d"; afirma "m5-retomada-duravel-recusa-parcial-perdido" $? "rc2 antes de retomada, sem evento nem gravacao"
d="$(kcopia "$FXN")"; l5_fechamento_pendente_e_fechado "$PL" "$d"; afirma "m8-m9-m10-fechamento-pendente-e-rodada-fechada" $? "checkpoint fecha uma vez; repeticao para"
d="$(kcopia "$FXN")"; l5_portao_posterior_tolera_task_removida "$PL" "$d"; afirma "m11-portao-posterior-nao-revalida-aplicacao-inicial" $? "retomada e F3 aceitam task removida pelo replanejamento"

TRAVA_AUT6="$SK/scripts/lib/trava-autorizacao-f6.sh"
l_lock_obtem() {
  local lib="$1" repo="$2" slug="$3"
  ( . "$lib" || exit 1
    adquire_trava_autorizacao_f6 "$repo" "$slug" || exit 1
    printf '%s' "$TRAVA_AUT6_DIR"
    libera_trava_autorizacao_f6
    trap - EXIT HUP INT TERM
  )
}
l_lock_caminho() {
  [ -f "$TRAVA_AUT6" ] || return 1
  local a b c
  a="$(l_lock_obtem "$TRAVA_AUT6" "$W" menu)" || return 1
  b="$(l_lock_obtem "$TRAVA_AUT6" "$WT" menu)" || return 1
  c="$(l_lock_obtem "$TRAVA_AUT6" "$W" relatorios)" || return 1
  [ "$a" != "$b" ] && [ "$a" != "$c" ] && [ "$b" != "$c" ]
}
l_lock_concorrente() {
  [ -f "$TRAVA_AUT6" ] || return 1
  local q="$K/lock-race" pid rc=0
  mkdir -p "$q"
  ( . "$TRAVA_AUT6" || exit 1
    adquire_trava_autorizacao_f6 "$W" menu || exit 1
    printf pronto > "$q/pronto"
    while [ ! -f "$q/libera" ]; do sleep 1; done
  ) & pid=$!
  while [ ! -f "$q/pronto" ]; do kill -0 "$pid" 2>/dev/null || return 1; sleep 1; done
  ( . "$TRAVA_AUT6" && adquire_trava_autorizacao_f6 "$W" menu ) >/dev/null 2>&1 && rc=1
  : > "$q/libera"; wait "$pid" || rc=1
  [ "$rc" -eq 0 ]
}
l_lock_trap() {
  [ -f "$TRAVA_AUT6" ] || return 1
  local q="$K/lock-trap" p rc=0
  mkdir -p "$q"
  ( . "$TRAVA_AUT6" || exit 1
    adquire_trava_autorizacao_f6 "$W" menu || exit 1
    printf '%s' "$TRAVA_AUT6_DIR" > "$q/path"
    exit 7
  ) >/dev/null 2>&1 || rc=$?
  p="$(cat "$q/path" 2>/dev/null)"
  [ "$rc" -eq 7 ] && [ -n "$p" ] && [ ! -e "$p" ]
}
l_lock_existente() {
  [ -f "$TRAVA_AUT6" ] || return 1
  local p rc=0
  p="$(l_lock_obtem "$TRAVA_AUT6" "$W" menu)" || return 1
  mkdir -p "$p"
  ( . "$TRAVA_AUT6" && adquire_trava_autorizacao_f6 "$W" menu ) >/dev/null 2>&1 && rc=1
  [ "$rc" -eq 0 ] && [ -d "$p" ]; rc=$?
  rmdir "$p"
  return "$rc"
}
l_lock_sinal_durante_aquisicao() {
  [ -f "$TRAVA_AUT6" ] || return 1
  local p rc=0 resultado=1
  p="$(git -C "$W" rev-parse --git-path sprintx/travas/autorizacao-f6-sinal.lock)" || return 1
  case "$p" in /*) ;; *) p="$W/$p" ;; esac
  bash -c '
    . "$1" || exit 1
    ALVO_TRAVA_AUT6="$3"
    mkdir() {
      local mkdir_rc
      command mkdir "$@"; mkdir_rc=$?
      if [ "$mkdir_rc" -eq 0 ] && [ "$#" -eq 1 ] && [ "$1" = "$ALVO_TRAVA_AUT6" ]; then
        kill -s TERM "$$"
      fi
      return "$mkdir_rc"
    }
    adquire_trava_autorizacao_f6 "$2" sinal
  ' _ "$TRAVA_AUT6" "$W" "$p" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && [ ! -e "$p" ] && resultado=0
  rmdir "$p" 2>/dev/null || true
  return "$resultado"
}
l_lock_mkdir_interrompido_depois_de_criar() {
  [ -f "$TRAVA_AUT6" ] || return 1
  local p rc=0 resultado=1
  p="$(git -C "$W" rev-parse --git-path sprintx/travas/autorizacao-f6-mkdir-interrompido.lock)" || return 1
  case "$p" in /*) ;; *) p="$W/$p" ;; esac
  bash -c '
    . "$1" || exit 1
    ALVO_TRAVA_AUT6="$3"
    mkdir() {
      local mkdir_rc disposicao
      command mkdir "$@"; mkdir_rc=$?
      if [ "$mkdir_rc" -eq 0 ] && [ "$#" -eq 1 ] && [ "$1" = "$ALVO_TRAVA_AUT6" ]; then
        kill -s TERM "$$"
        disposicao="$(trap -p TERM)"
        case "$disposicao" in
          *"_trava_aut6_adia_term"*) return 143 ;;
          *) return "$mkdir_rc" ;;
        esac
      fi
      return "$mkdir_rc"
    }
    adquire_trava_autorizacao_f6 "$2" mkdir-interrompido
  ' _ "$TRAVA_AUT6" "$W" "$p" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] && [ ! -e "$p" ] && resultado=0
  rmdir "$p" 2>/dev/null || true
  return "$resultado"
}
l_lock_sinal_com_trava_alheia() {
  [ -f "$TRAVA_AUT6" ] || return 1
  local p rc=0 resultado=1 dono="outra-execucao"
  p="$(git -C "$W" rev-parse --git-path sprintx/travas/autorizacao-f6-sinal-alheia.lock)" || return 1
  case "$p" in /*) ;; *) p="$W/$p" ;; esac
  mkdir -p "$p" || return 1
  printf '%s\n' "$dono" > "$p/dono" || { rm -rf "$p"; return 1; }
  bash -c '
    . "$1" || exit 1
    ALVO_TRAVA_AUT6="$3"
    mkdir() {
      local mkdir_rc
      command mkdir "$@"; mkdir_rc=$?
      if [ "$#" -eq 1 ] && [ "$1" = "$ALVO_TRAVA_AUT6" ]; then
        kill -s TERM "$$"
      fi
      return "$mkdir_rc"
    }
    adquire_trava_autorizacao_f6 "$2" sinal-alheia
  ' _ "$TRAVA_AUT6" "$W" "$p" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -ne 0 ] && [ -d "$p" ] && [ "$(cat "$p/dono" 2>/dev/null)" = "$dono" ]; then
    resultado=0
  fi
  rm -f "$p/dono"
  rmdir "$p" 2>/dev/null || true
  return "$resultado"
}
l_lock_preserva_traps_de_sinal() {
  [ -f "$TRAVA_AUT6" ] || return 1
  local q="$K/lock-traps-chamador" rc=0
  mkdir -p "$q"
  bash -c '
    recebidos=0
    ao_sinal() { recebidos=$((recebidos + 1)); }
    trap ao_sinal HUP
    trap ao_sinal INT
    trap ao_sinal TERM
    . "$1" || exit 1
    adquire_trava_autorizacao_f6 "$2" traps || exit 1
    kill -s HUP "$$"
    kill -s INT "$$"
    kill -s TERM "$$"
    [ "$recebidos" -eq 3 ] || exit 1
    libera_trava_autorizacao_f6 || exit 1
    kill -s HUP "$$"
    kill -s INT "$$"
    kill -s TERM "$$"
    [ "$recebidos" -eq 6 ]
  ' _ "$TRAVA_AUT6" "$W" || rc=$?
  return "$rc"
}
l_lock_sem_janela_default_na_restauracao() {
  [ -f "$TRAVA_AUT6" ] || return 1
  local rc=0
  bash -c '
    recebidos=0
    ao_sinal() { recebidos=$((recebidos + 1)); }
    trap ao_sinal HUP
    trap ao_sinal INT
    trap ao_sinal TERM
    trap() {
      if [ "$#" -eq 4 ] && [ "$1" = - ] && [ "$2" = HUP ] && [ "$3" = INT ] && [ "$4" = TERM ]; then
        builtin trap "$@"
        kill -s TERM "$$"
        return
      fi
      builtin trap "$@"
    }
    . "$1" || exit 1
    adquire_trava_autorizacao_f6 "$2" janela || exit 1
    [ "$recebidos" -eq 0 ]
  ' _ "$TRAVA_AUT6" "$W" >/dev/null 2>&1 || rc=$?
  return "$rc"
}
l_lock_caminho; afirma "l-lock-1-caminho-por-worktree-e-slug" $? "git-path distingue worktree e slug"
l_lock_concorrente; afirma "l-lock-2-concorrente-recusada" $? "uma aquisicao vence e a outra falha fechada"
l_lock_trap; afirma "l-lock-3-trap-remove-so-a-propria" $? "exit 7 preservado e lock adquirido removido"
l_lock_existente; afirma "l-lock-4-existente-nao-e-removida" $? "lock preexistente falha e permanece"
l_lock_sinal_durante_aquisicao; afirma "l-lock-5-sinal-na-janela-nao-deixa-orfa" $? "TERM entre mkdir e trap limpa a trava adquirida"
l_lock_mkdir_interrompido_depois_de_criar; afirma "l-lock-5b-mkdir-interrompido-nao-deixa-orfa" $? "mkdir criado nao retorna falha por sinal antes do registro da posse"
l_lock_preserva_traps_de_sinal; afirma "l-lock-6-preserva-traps-de-sinal-do-chamador" $? "handlers HUP INT TERM anteriores continuam executaveis"
l_lock_sinal_com_trava_alheia; afirma "l-lock-7-sinal-nao-remove-trava-alheia" $? "TERM depois do mkdir recusado preserva lock e dono de outra execucao"
l_lock_sem_janela_default_na_restauracao; afirma "l-lock-8-restauracao-sem-janela-default" $? "restauracao nao limpa os tres handlers antes de repor o chamador"

# Contrato nos documentos: estados, comando da F6, resolucao, congelamento e decisoes.
SCHK="$SK/references/00-schema.md"
for e in replanejar_execucao replanejamento_execucao_esgotado; do
  tr -d '\r' < "$SCHK" | grep -F '| `estado` (planejamento) |' | grep -qF "\`$e\`" && tem "$SKILLMD" "| \`$e\` |" \
    && [ "$(tr -d '\r' < "$PL" | grep -cxF '    replanejar_execucao|replanejamento_execucao_esgotado) ;;')" -eq 1 ]
  afirma "k18-estado-$e-no-enum" $? "schema, tabela do SKILL.md e script"
done
tem "$SKILLMD" '| `replanejamento_execucao_esgotado` | **terminal**' && tem "$SKILLMD" '| `replanejar_execucao` | F3 —'
afirma "k18-skill-f6-volta-pela-f3" $? "replanejar_execucao -> F3; esgotado terminal"
tr -d '\r' < "$SCHK" | grep -F '| `estado` (planejamento) |' | grep -qF '`replanejamento_execucao_recusado`' \
  && tem "$SKILLMD" '| `replanejamento_execucao_recusado` | **terminal**' \
  && [ "$(tr -d '\r' < "$PL" | grep -cxF '    replanejamento_execucao_recusado) ;;')" -eq 1 ] \
  && tr -d '\r' < "$SCHK" | grep -F '| `recusa_replanejamento_f6` (planejamento) |' | grep -qF '`classes_mistas` \| `orcamento_f6_legado` \| `orcamento_f6_nao_declarado` \| `planejamento_legado`' \
  && tem "$SCHK" '**Erro de contrato nunca vira esta recusa**' && tem "$EXEC" 'recusa **operacional**, gravada e persistida'
afirma "k18-estado-replanejamento_execucao_recusado-no-enum" $? "schema, SKILL.md, 06-execucao e script"
KCMD="$CMD_PL replanejar-execucao <slug>"
onde="$(grep -rlF -- "$KCMD" "$SK" "$H/../commands" ${RAIZ_SRC:+"$RAIZ_SRC/.opencode"} 2>/dev/null)"
[ "$(printf '%s\n' "$onde" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 1 ] && [ "$(basename "$onde")" = 06-execucao.md ] && [ "$(conta "$EXEC" "$KCMD")" -eq 1 ]
afirma "k19-instrucao-unica-replanejar-execucao" $? "${onde:-nenhum arquivo}"
L_REG=$(linha_de "$EXEC" 'bash <raiz-da-skill>/scripts/bloqueios.sh registrar <slug>'); L_RPL=$(linha_de "$EXEC" "$KCMD")
L_PORT=$(linha_de "$EXEC" '## Portões de fase e de sprint')
[ -n "$L_REG" ] && [ -n "$L_RPL" ] && [ "$L_REG" -lt "$L_RPL" ] && [ "$L_RPL" -lt "$L_PORT" ] \
  && tem "$EXEC" '3. **Classe `defeito_de_plano`: devolva o plano ao planejamento agora**' \
  && tem "$EXEC" 'Nunca `stash`, nunca limpe, nunca descarte' && tem "$EXEC" '**Não abra task nova**'
afirma "k19-f6-devolve-o-plano-depois-de-registrar" $? "registrar=$L_REG < replanejar=$L_RPL < portoes=$L_PORT"
tem "$EXEC" 'bash <raiz-da-skill>/scripts/bloqueios.sh resolver <slug> <B-NN>' && tem "$EXEC" '**`defeito_de_plano` não**: editar o plano não resolve um defeito de plano' \
  && tem "$SCHK" '**Resolução.** Só por `scripts/bloqueios.sh resolver <slug> <B-NN>`, nunca editando'
afirma "k20-resolucao-so-pelo-script" $? "06-execucao e schema"
tem "$SK/references/03-plano.md" '### Retorno da F6 — replanejamento da execução' && tem "$SK/references/03-plano.md" '**Tasks `concluida` estão congeladas**' \
  && tem "$SK/references/03-plano.md" 'Não volte à F1 nem à F2' \
  && tr -d '\r' < "$SK/references/05-auditoria.md" | tr '\n' ' ' | grep -qF '**o orçamento da F5 continua de onde estava**'
afirma "k21-f3-e-f5-no-retorno-da-f6" $? "congeladas, sem F1/F2, orcamento da F5 continua"
for ev in replanejamento_execucao_iniciado replanejamento_execucao_retomado replanejamento_execucao_aprovado replanejamento_execucao_esgotado \
  replanejamento_execucao_recusado task_reaberta bloqueio_resolvido; do
  tem "$SK/references/08-rastro.md" "\`$ev\`" && [ "$(cat "$PL" "$BL" | grep -cF "$ev")" -gt 0 ]
  afirma "k22-rastro-$ev" $? "08-rastro e script"
done
DSF="$SK/DECISOES-DA-SKILL.md"; n=0
for ds in 140 141 142 143 144 145 146; do [ "$(grep -c "^| DS-$ds |" "$DSF")" -eq 1 ] && n=$((n + 1)); done
for ds in 147 148; do [ "$(grep -c "^| DS-$ds |" "$DSF")" -eq 1 ] || n=0; done
[ "$n" -eq 7 ] && tem "$DSF" '**Estado próprio `replanejar_execucao`**' \
  && tem "$DSF" '**A F1 repassa os três tetos do pedido' && tem "$DSF" '**Recusa operacional é estado terminal durável' && tem "$DSF" '**Tasks concluídas são congeladas, e o congelamento é mecânico.**' \
  && tem "$DSF" '**Legado sem orçamento retroativo.**' && tem "$DSF" '**O gatilho é a chave `classe` dos B-NN abertos**'
afirma "k23-ds140-a-ds148-registradas" $? "$n de 7, mais DS-147 e DS-148"

# Mutantes do mecanismo, em copia temporaria da skill (scripts/ + assets/: os dois scripts
# se chamam pela propria pasta e acham o template por ela). Cada mutante tem de morrer pelos
# casos designados; o controle, copia SEM mutacao na mesma estrutura, tem de sobreviver a
# todos eles — se morrer, e a bancada que esta quebrada.
MK="$K/mut"
copia_skill_k() { mkdir -p "$MK/$1/scripts/lib" "$MK/$1/assets"; cp "$SK/assets/TEMPLATE-PLANEJAMENTO.md" "$SK/assets/TEMPLATE-BLOQUEIOS.md" "$MK/$1/assets/"; cp "$BL" "$SK/scripts/caminho-git.sh" "$MK/$1/scripts/"; cp "$SK/scripts/lib/trava-autorizacao-f6.sh" "$SK/scripts/lib/execucao.sh" "$MK/$1/scripts/lib/"; printf '%s/%s/scripts/planejamento.sh' "$MK" "$1"; }
mutante_k() { # mutante_k <nome> <rc da geracao> <script> <caso que TEM de matar>...
  local nome="$1" rc="$2" s="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do roda_k "$c" "$s" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]; afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
DESIGNADOS_K="k_inicia k_retomada k_resolver_antes k_aprovacao k_segundo_defeito k_lacuna k_legado_bloqueio k_mistura k_legado_orcamento
  k_sem_orcamento k_planejamento_legado k_sem_worktree k_fronteira k_registro_invalido"
CTLK="$(copia_skill_k controle)"; cp "$PL" "$CTLK"; vivosk=""
for c in $DESIGNADOS_K; do roda_k "$c" "$CTLK" || vivosk="$vivosk$c "; done
[ -z "$vivosk" ]; afirma "km-controle-copia-intacta-sobrevive" $? "${vivosk:-nenhum caso designado reprova a copia sem mutacao}"
M="$(copia_skill_k a)"; muta_lit "$PL" "$M" '  escreve "$P_MAX" "$P_POR" replanejar_execucao "$P_REPROV" "$P_HIST"' \
  '  escreve "$P_MAX" "$P_POR" replanejar_execucao 0 "$(printf '"'"'%s\n'"'"' "$P_HIST" | awk -F"$TAB" '"'"'$2 == "sim"'"'"' | tail -1 | sed '"'"'s/^[0-9]*/1/'"'"')"'
mutante_k "km-mutante-1-reinicia-reprovacoes-f5" $? "$M" k_inicia
M="$(copia_skill_k b)"; muta_lit "$PL" "$M" '    fm && t && id == alvo && $0 == "    status: bloqueada" { print "    status: pendente"; next }' \
  '    fm && t && $0 ~ /^    status: (bloqueada|concluida)$/ { print "    status: pendente"; next }'
mutante_k "km-mutante-2-reabre-task-concluida" $? "$M" k_aprovacao
M="$(copia_skill_k c)"; muta_lit "$PL" "$M" '  if decimal_ge "$P_N6" "$P_MAX6"; then' '  if [ "$P_N6" -gt "$P_MAX6" ]; then'
mutante_k "km-mutante-3-segunda-rodada-apos-1-de-1" $? "$M" k_segundo_defeito
M="$(copia_skill_k d)"; muta_lit "$PL" "$M" '    evento replanejamento_execucao_retomado f6 - ok' \
  '    f6_herda; W6_N=$((P_N6 + 1)); escreve "$P_MAX" "$P_POR" "$P_ESTADO" "$P_REPROV" "$P_HIST"; evento replanejamento_execucao_retomado f6 - ok'
mutante_k "km-mutante-4-retomada-consome-de-novo" $? "$M" k_retomada
M="$(copia_skill_k e)"; muta_lit "$PL" "$M" '    elif [ "$P_ESTADO" != aprovado ]; then motivo=rodada_nao_aprovada' '    elif false; then motivo=rodada_nao_aprovada'
mutante_k "km-mutante-5-resolve-antes-da-aprovacao" $? "$M" k_resolver_antes
M="$(copia_skill_k f)"; muta_lit "$PL" "$M" '  abertos="$(abertos_ordenados)"' \
  '  abertos="$(abertos_ordenados | while IFS="$TAB" read -r b t c; do d="$(grep -A6 "^  - id: $b\$" "$PASTA/00-BLOQUEIOS.md" | grep "^    descricao:")"; case "$d" in *ownership*|*plano*|*arquivo*) c=defeito_de_plano ;; *) c=lacuna_de_decisao ;; esac; printf "%s\t%s\t%s\n" "$b" "$t" "$c"; done)"'
mutante_k "km-mutante-6-classe-pela-descricao" $? "$M" k_lacuna k_legado_bloqueio
M="$(copia_skill_k g)"; muta_lit "$PL" "$M" '  if [ -n "$outros" ]; then motivo=classes_mistas' '  if false; then motivo=classes_mistas'
mutante_k "km-mutante-7-replaneja-com-classes-mistas" $? "$M" k_mistura
M="$(copia_skill_k h)"; muta_lit "$PL" "$M" '    P_F6=legado; P_MAX6=null; P_N6=0' '    P_F6=presente; P_MAX6=1; P_N6=0'
mutante_k "km-mutante-8-inventa-orcamento-no-legado" $? "$M" k_legado_orcamento
# A recusa operacional como era antes: so no stdout, nada gravado.
M="$(copia_skill_k i)"; muta_lit "$PL" "$M" '  local motivo="$1" abertos="$2"' \
  '  local motivo="$1" abertos="$2"; printf '"'"'replanejamento=recusado\nmotivo=%s\nestado=%s\n'"'"' "$motivo" "$P_ESTADO"; falha "$E_TRANSICAO" recusado'
mutante_k "km-mutante-9-recusa-so-no-stdout" $? "$M" k_mistura k_sem_orcamento k_legado_orcamento k_planejamento_legado k_sem_worktree
# Grava o terminal, mas nao faz o checkpoint: some com o worktree.
M="$(copia_skill_k j)"; muta_lit "$PL" "$M" '; estado terminal replanejamento_execucao_recusado gravado"' \
  '; estado terminal replanejamento_execucao_recusado gravado"; checkpoint() { printf '"'"'checkpoint=ignorado\n'"'"'; }'
mutante_k "km-mutante-10-recusa-sem-checkpoint" $? "$M" k_mistura k_sem_worktree
# A repeticao reavalia em vez de reconhecer o terminal (motivo trocado por `estado`).
M="$(copia_skill_k k)"; muta_lit "$PL" "$M" '  if [ "$P_ESTADO" = replanejamento_execucao_recusado ]; then' '  if false; then'
mutante_k "km-mutante-11-repeticao-reavalia" $? "$M" k_mistura k_sem_worktree
# A repeticao registra o evento de novo.
M="$(copia_skill_k l)"; muta_lit "$PL" "$M" '    falha "$E_TRANSICAO" "replanejamento da execucao ja recusado' \
  '    evento replanejamento_execucao_recusado f6 - bloqueado "$P_RECUSA: repetido"; falha "$E_TRANSICAO" "replanejamento da execucao ja recusado'
mutante_k "km-mutante-12-repeticao-duplica-evento" $? "$M" k_mistura k_sem_orcamento
# Erro de contrato gravado como recusa.
M="$(copia_skill_k m)"; muta_lit "$PL" "$M" '    evento replanejamento_execucao_recusado f6 - bloqueado "$motivo: abertos [$outros]; estado $P_ESTADO mantido"' \
  '    E_FONTE=planejamento; recusa_duravel classes_mistas "$outros"'
mutante_k "km-mutante-13-contrato-vira-recusa-gravada" $? "$M" k_lacuna k_legado_bloqueio
M="$(copia_skill_k n)"; muta_lit "$PL" "$M" '    evento replanejamento_execucao_recusado f6 - bloqueado "fronteira insegura: produto sujo na arvore:$sujos"' \
  '    recusa_duravel classes_mistas "$sujos"'
mutante_k "km-mutante-14-fronteira-vira-recusa-gravada" $? "$M" k_fronteira
# Sem 00-PLANEJAMENTO.md, a recusa inventa o teto da F6 do BuildX.
M="$(copia_skill_k o)"; muta_lit "$PL" "$M" '    migra_legado null null null replanejamento_execucao_recusado "$motivo"' \
  '    migra_legado 3 buildx 1 replanejamento_execucao_recusado orcamento_f6_nao_declarado'
mutante_k "km-mutante-15-legado-inventa-orcamento-na-recusa" $? "$M" k_planejamento_legado
# Registro invalido lido so dentro do subshell: vira "nenhum bloqueio aberto" em vez de contrato.
M="$(copia_skill_k p)"; muta_lit "$PL" "$M" '  le_bloqueios || falha "$E_CONTRATO" "00-BLOQUEIOS.md invalido"' '  :'
mutante_k "km-mutante-16-registro-invalido-vira-sem-bloqueio" $? "$M" k_registro_invalido

