#!/usr/bin/env bash
#
# Secoes L a T da bancada: escopo, portabilidade, rastro do trabalho e custo dos hooks.
# Carregada por `.` de dentro da bancada.sh, no mesmo ponto e na mesma ordem: usa os
# auxiliares e o estado dela. Mora aqui porque o CodeAnt pula arquivo acima de 5.000 linhas
# ou 200 KB (expxdev, docs/superpowers/specs/2026-10-19-limites-do-codeant-emenda.md).

echo "== L. escopo unitario bloqueia arquivo de task irma (P0.2-C2) =="
existe "l0-hook-existe" "$H/sprintx/escopo-da-task.sh"
bash -n "$H/sprintx/escopo-da-task.sh"; afirma "l0-hook-sintaxe" $? "bash -n"
bash -n "$H/comum/rastro.sh"; afirma "l0-rastro-sintaxe" $? "bash -n"

C2="$(mktemp -d)"
git -C "$C2" init -q -b main; git -C "$C2" config user.email t@t.local; git -C "$C2" config user.name teste
git -C "$C2" -c commit.gpgsign=false commit -q -m init --allow-empty
C2OC="$C2/docs/sprintx/features/c2-escopo-irma"
mkdir -p "$C2OC/sprint-03" "$C2OC/sprint-04" "$C2/tests/ui" "$C2/src/ui" "$C2/src/menu" "$C2/src/shared" "$C2/src/random"
C2RASTRO="$C2/docs/eventos/c2-escopo-irma.jsonl"; mkdir -p "$(dirname "$C2RASTRO")"

c2_evento() { # c2_evento <evento> <task> <sessao>
  python3 -c "
import sys, datetime
evento, task, sessao = sys.argv[1:4]
extras = ',\"sessao\":\"%s\",\"harness\":\"%s\"' % (sessao, sessao.split('@')[0])
linha = ('{\"ts\":\"%s\",\"expx_eventos\":1,\"trabalho_id\":\"c2-escopo-irma\",'
         '\"ferramenta\":\"sprintx\",\"origem\":\"skill\",\"evento\":\"%s\",\"fase\":\"f6\",'
         '\"task\":\"%s\",\"agente\":\"principal\",\"resultado\":\"ok\",\"detalhe\":null,'
         '\"arquivos\":[]%s}') % (datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'), evento, task, extras)
open(sys.argv[4], 'a').write(linha + '\n')
" "$1" "$2" "$3" "$C2RASTRO"
}
c2_tarefa() { # c2_tarefa <arquivo> <id> <status> <cria> <altera> [depende]
  printf '  - id: %s\n    titulo: Task %s original\n    status: %s\n    objetivo: obj\n    arquivos:\n      cria: [%s]\n      altera: [%s]\n    teste_integracao: t\n    teste_funcional: t\n    criterio_aceite: c\n    depende_de: [%s]\n    paralelizavel: false\n    concluida_em: null\n    suite: nao_executada\n' \
    "$2" "$2" "$3" "$4" "$5" "${6:-}" >> "$1"
}
c2_abre() { printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: tasks\ntrabalho_id: c2-escopo-irma\nsprint_id: sprint-%s\ntasks:\n' "$1" > "$2"; }
c2_fecha() { printf -- '---\n' >> "$1"; }
c2_w() { printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$C2" "$C2/$1"; }
C2_SAIDA=""
c2_hook() { # c2_hook <hook> <arquivo-relativo> <sessao> — exit code proprio; saida fica em C2_SAIDA
  C2_SAIDA=$(printf '%s' "$(c2_w "$2")" | (cd "$C2" && EXPX_SESSAO="$3" bash "$1") 2>&1)
}

# Reset completo e deterministico: T-03.01 concluida cria o par tsx+test;
# T-04.03 em_andamento (minha sessao) altera so o tsx. Cada caso parte daqui
# e aplica so o desvio que precisa — nenhum caso depende do anterior.
l_fixture() {
  c2_abre 03 "$C2OC/sprint-03/tasks.md"
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.01 concluida "src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx" ""
  c2_fecha "$C2OC/sprint-03/tasks.md"
  c2_abre 04 "$C2OC/sprint-04/tasks.md"
  c2_tarefa "$C2OC/sprint-04/tasks.md" T-04.03 em_andamento "" "src/ui/cabecalho-topo.tsx"
  c2_fecha "$C2OC/sprint-04/tasks.md"
  rm -rf "$C2OC/sprint-02"; rm -f "$C2/.expx/hooks.json"
  : > "$C2RASTRO"
  c2_evento task_iniciada T-04.03 "teste@eu"
}
l_a() { l_fixture; c2_hook "$1" "src/ui/cabecalho-topo.tsx" teste@eu; [ $? -eq 0 ]; }
l_b() {
  l_fixture
  c2_abre 04 "$C2OC/sprint-04/tasks.md"
  c2_tarefa "$C2OC/sprint-04/tasks.md" T-04.03 em_andamento "" "src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx"
  c2_fecha "$C2OC/sprint-04/tasks.md"
  c2_hook "$1" "tests/ui/cabecalho-topo.test.tsx" teste@eu; [ $? -eq 0 ]
}
l_c() {
  l_fixture
  c2_hook "$1" "tests/ui/cabecalho-topo.test.tsx" teste@eu
  [ $? -eq 2 ] && printf '%s' "$C2_SAIDA" | grep -qF "arquivo_de_task_irma" \
    && printf '%s' "$C2_SAIDA" | grep -qF "T-04.03" && printf '%s' "$C2_SAIDA" | grep -qF "T-03.01"
}
l_d() {
  l_fixture
  c2_abre 03 "$C2OC/sprint-03/tasks.md"
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.01 concluida "src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx" ""
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.02 concluida "" "src/shared/util.ts"
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.05 pendente "" "src/shared/util.ts"
  c2_fecha "$C2OC/sprint-03/tasks.md"
  c2_hook "$1" "src/shared/util.ts" teste@eu
  [ $? -eq 2 ] && printf '%s' "$C2_SAIDA" | grep -qF "T-03.02" && printf '%s' "$C2_SAIDA" | grep -qF "T-03.05"
}
l_e() {
  l_fixture
  c2_hook "$1" "src/random/nope.ts" teste@eu
  [ $? -eq 0 ] && ! printf '%s' "$C2_SAIDA" | grep -qF "defeito_de_plano"
}
l_f() {
  l_fixture
  c2_abre 03 "$C2OC/sprint-03/tasks.md"
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.01 concluida "src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx" ""
  sed 's/Task T-03.01 original/Cabecalho novo — reescrita total do topo/' "$C2OC/sprint-03/tasks.md" \
    > "$WORKDIR/l_f.sed" && cat "$WORKDIR/l_f.sed" > "$C2OC/sprint-03/tasks.md"   # sem `sed -i` (so GNU)
  c2_fecha "$C2OC/sprint-03/tasks.md"
  c2_hook "$1" "tests/ui/cabecalho-topo.test.tsx" teste@eu; [ $? -eq 2 ]
}
l_g() {
  l_fixture
  c2_abre 03 "$C2OC/sprint-03/tasks.md"
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.05 pendente "" "src/shared/util.ts"
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.01 concluida "src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx" ""
  c2_tarefa "$C2OC/sprint-03/tasks.md" T-03.02 concluida "" "src/shared/util.ts"
  c2_fecha "$C2OC/sprint-03/tasks.md"
  c2_hook "$1" "tests/ui/cabecalho-topo.test.tsx" teste@eu; [ $? -eq 2 ]
}
l_h() {
  l_fixture
  mkdir -p "$C2OC/sprint-02"
  c2_abre 02 "$C2OC/sprint-02/tasks.md"
  c2_tarefa "$C2OC/sprint-02/tasks.md" T-02.09 em_andamento "" "src/outro/coisa.ts"
  c2_fecha "$C2OC/sprint-02/tasks.md"
  c2_evento task_iniciada T-02.09 "outra@sessao"
  c2_hook "$1" "src/ui/cabecalho-topo.tsx" teste@eu; [ $? -eq 0 ]
}
l_i0() {
  l_fixture
  : > "$C2RASTRO"
  c2_hook "$1" "src/ui/cabecalho-topo.tsx" teste@eu
  [ $? -eq 2 ] && ! printf '%s' "$C2_SAIDA" | grep -qF "arquivo_de_task_irma"
}
l_i1() {
  l_fixture
  c2_abre 04 "$C2OC/sprint-04/tasks.md"
  c2_tarefa "$C2OC/sprint-04/tasks.md" T-04.03 em_andamento "" "src/ui/cabecalho-topo.tsx"
  c2_tarefa "$C2OC/sprint-04/tasks.md" T-04.05 em_andamento "" "src/menu/outra.ts"
  c2_fecha "$C2OC/sprint-04/tasks.md"
  c2_evento task_iniciada T-04.05 "teste@eu"
  c2_hook "$1" "src/ui/cabecalho-topo.tsx" teste@eu; [ $? -eq 2 ]
}
l_j() {
  l_fixture
  c2_abre 04 "$C2OC/sprint-04/tasks.md"
  c2_tarefa "$C2OC/sprint-04/tasks.md" T-04.03 bloqueada "" "src/ui/cabecalho-topo.tsx"
  c2_fecha "$C2OC/sprint-04/tasks.md"
  c2_hook "$1" "tests/ui/cabecalho-topo.test.tsx" teste@eu; [ $? -eq 0 ]
}
l_modo_aviso() {
  l_fixture
  mkdir -p "$C2/.expx"; echo '{"hooks":{"escopo-da-task":{"modo":"aviso"}}}' > "$C2/.expx/hooks.json"
  c2_hook "$1" "tests/ui/cabecalho-topo.test.tsx" teste@eu; [ $? -eq 2 ]
}
l_modo_desligado() {
  l_fixture
  mkdir -p "$C2/.expx"; echo '{"hooks":{"escopo-da-task":{"modo":"desligado"}}}' > "$C2/.expx/hooks.json"
  c2_hook "$1" "tests/ui/cabecalho-topo.test.tsx" teste@eu; [ $? -eq 0 ]
}

for par in l_a:la-arquivo-so-da-corrente-permitido l_b:lb-arquivo-corrente-e-irma-permitido \
  l_c:lc-arquivo-so-da-irma-bloqueado l_d:ld-arquivo-de-duas-irmas-bloqueado \
  l_e:le-arquivo-de-nenhuma-permitido-sem-defeito_de_plano l_f:lf-titulo-mudou-mesmo-resultado \
  l_g:lg-ordem-mudou-mesmo-resultado l_h:lh-sessao-acha-a-propria-task-nao-a-primeira \
  l_i0:li0-zero-correspondencias-fail-closed l_i1:li1-duas-correspondencias-fail-closed \
  l_j:lj-task-bloqueada-nao-repete-bloqueio l_modo_aviso:lmodo-irma-bloqueia-mesmo-em-aviso \
  l_modo_desligado:lmodo-desligado-desativa-tudo; do
  "${par%%:*}" "$H/sprintx/escopo-da-task.sh"; afirma "${par#*:}" $? "${par%%:*}"
done

# L-K. Ciclo real: irma -> bloqueio -> B-01 -> replanejamento -> plano ganha o
# arquivo -> aprovacao -> T-03.01 continua congelada -> edicao permitida.
grava_evento_menu() { # grava_evento_menu <dir> <evento> <task> <sessao>
  local arq="$1/docs/eventos/menu.jsonl"; mkdir -p "$(dirname "$arq")"
  python3 -c "
import sys, datetime
evento, task, sessao = sys.argv[1:4]
extras = ',\"sessao\":\"%s\",\"harness\":\"%s\"' % (sessao, sessao.split('@')[0])
linha = ('{\"ts\":\"%s\",\"expx_eventos\":1,\"trabalho_id\":\"menu\",'
         '\"ferramenta\":\"sprintx\",\"origem\":\"skill\",\"evento\":\"%s\",\"fase\":\"f6\",'
         '\"task\":\"%s\",\"agente\":\"principal\",\"resultado\":\"ok\",\"detalhe\":null,'
         '\"arquivos\":[]%s}') % (datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ'), evento, task, extras)
open(sys.argv[4], 'a').write(linha + '\n')
" "$2" "$3" "$4" "$arq"
}
roda_hook_menu() { # roda_hook_menu <dir> <hook> <arquivo-relativo> <sessao>
  printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$1" "$1/$3" | (cd "$1" && EXPX_SESSAO="$4" bash "$2") 2>&1
}
l_k() { # ciclo real completo — hook = $1
  local d f c0 saida1 rc1 out saida2 rc2 c1
  d="$K/c2ciclo.$$.$RANDOM"; mkdir -p "$d"
  k_fx "$d" 0 3 buildx 1 || return 1
  f="$(kf "$d")"; c0="$(cat "$f/sprint-03/tasks.md")"
  k_plano "$d" c em_andamento
  grava_evento_menu "$d" task_iniciada T-04.03 "teste@eu"
  saida1="$(roda_hook_menu "$d" "$1" tests/ui/cabecalho-topo.test.tsx teste@eu)"; rc1=$?
  [ "$rc1" -eq 2 ] && printf '%s' "$saida1" | grep -qF "arquivo_de_task_irma" || return 1
  kbl "$PL" "$d" registrar menu T-04.03 defeito_de_plano 'arquivo_de_task_irma: tests/ui/cabecalho-topo.test.tsx pertence a T-03.01' 'ampliar ownership de T-04.03' >/dev/null || return 1
  k_plano "$d" c bloqueada
  out="$(kpl "$PL" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = iniciado ] || return 1
  k_plano "$d" c bloqueada 'src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx'
  kpl "$PL" "$d" avanca menu f3 >/dev/null && kpl "$PL" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 4 SIM
  out="$(kpl "$PL" "$d" avanca menu f5)" || return 1
  [ "$(kv "$out" estado)" = aprovado ] && [ "$(kst "$d" T-04.03)" = pendente ] || return 1
  k_plano "$d" c em_andamento 'src/ui/cabecalho-topo.tsx, tests/ui/cabecalho-topo.test.tsx'
  grava_evento_menu "$d" task_iniciada T-04.03 "teste@eu"
  saida2="$(roda_hook_menu "$d" "$1" tests/ui/cabecalho-topo.test.tsx teste@eu)"; rc2=$?
  [ "$rc2" -eq 0 ] || return 1
  c1="$(cat "$f/sprint-03/tasks.md")"
  [ "$c0" = "$c1" ]
}
l_k "$H/sprintx/escopo-da-task.sh"; afirma "lk-ciclo-real-irma-bloqueio-replanejamento-permitido" $? "irma -> B-01 -> replanejar-execucao -> aprovado -> permitido, T-03.01 congelada"

# Mutantes minimos do C2. Copia do hook preserva sprintx/+comum/ irmaos (o
# hook faz `source ../comum/rastro.sh`); cada mutante tem de morrer pelo caso
# designado, e a copia sem mutacao tem de sobreviver a todos.
LM="$K/c2mut"; mkdir -p "$LM/sprintx" "$LM/comum"
cp "$H/comum/rastro.sh" "$LM/comum/rastro.sh"
cp "$H/sprintx/escopo-da-task.sh" "$LM/sprintx/controle.sh"
l_mutante() { # l_mutante <nome> <rc-geracao> <arquivo-mutante> <caso que TEM de matar>...
  local nome="$1" rc="$2" s="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do "$c" "$s" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]; afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
vivosl=""
for c in l_a l_b l_c l_d l_e l_f l_g l_h l_i0 l_i1 l_j l_modo_aviso l_modo_desligado; do
  "$c" "$LM/sprintx/controle.sh" || vivosl="$vivosl$c "
done
l_k "$LM/sprintx/controle.sh" || vivosl="${vivosl}l_k "
[ -z "$vivosl" ]; afirma "lm-controle-copia-intacta-sobrevive" $? "${vivosl:-nenhum caso designado reprova a copia sem mutacao}"

# Os literais seguem a reescrita de custo do hook (DS-157); a intencao de cada mutante e a de sempre.
muta_lit "$H/sprintx/escopo-da-task.sh" "$LM/sprintx/m1.sh" \
  'if [ "$DECL" = irma ]; then' 'if [ "$DECL" = irma ] && false; then'
l_mutante "lm-mutante-1-uniao-vence-escopo-unitario" $? "$LM/sprintx/m1.sh" l_c l_d

muta_lit "$H/sprintx/escopo-da-task.sh" "$LM/sprintx/m2.sh" \
  'rastro_bloqueia "$MSG_IRMA"' 'rastro_aviso_ao_modelo PreToolUse "$MSG_IRMA"'
l_mutante "lm-mutante-2-arquivo-de-irma-vira-so-aviso" $? "$LM/sprintx/m2.sh" l_c

muta_lit "$H/sprintx/escopo-da-task.sh" "$LM/sprintx/m3.sh" \
  'rastro_aviso_ao_modelo PreToolUse "$MSG"' 'rastro_bloqueia "$MSG"'
l_mutante "lm-mutante-3-arquivo-de-nenhuma-vira-defeito_de_plano" $? "$LM/sprintx/m3.sh" l_e

muta_lit "$H/sprintx/escopo-da-task.sh" "$LM/sprintx/m4.sh" \
  '    if (corrente) { print "D corrente"; exit }' '    if (corrente && 0) { print "D corrente"; exit }'
l_mutante "lm-mutante-4-atual-mais-irma-bloqueado-incorretamente" $? "$LM/sprintx/m4.sh" l_b
l_mutante "lm-mutante-7-depois-do-replanejamento-ainda-bloqueia" $? "$LM/sprintx/m4.sh" l_k

# Este mutante mora no helper, nao no hook: sem o filtro de sessao, o par
# TRABALHO+TASK volta a ser "o primeiro que o rastro mostrar". Copia propria de
# sprintx/+comum/, para nao contaminar os outros mutantes.
LM5="$K/c2mut5"; mkdir -p "$LM5/sprintx" "$LM5/comum"
cp "$H/sprintx/escopo-da-task.sh" "$LM5/sprintx/m5.sh"
muta_lit "$H/comum/rastro.sh" "$LM5/comum/rastro.sh" \
  'if (_rv_dono[k] == "" || _rv_dono[k] != ses) continue' 'if (_rv_dono[k] == "") continue'
l_mutante "lm-mutante-5-seleciona-a-primeira-nao-a-da-sessao" $? "$LM5/sprintx/m5.sh" l_h

muta_lit "$H/sprintx/escopo-da-task.sh" "$LM/sprintx/m6.sh" \
  '  PORT && index($0, "status: em_andamento") { G = 1 }' \
  '  PORT && (index($0, "status: em_andamento") || index($0, "status: bloqueada")) { G = 1 }'
l_mutante "lm-mutante-6-depois-do-bloqueio-continua-abrindo-task" $? "$LM/sprintx/m6.sh" l_j

muta_lit "$H/sprintx/escopo-da-task.sh" "$LM/sprintx/m8.sh" \
  'if [ "$G" != 1 ]; then' 'if false; then'
l_mutante "lm-mutante-8-cria-b-nn-duplicado-numa-repeticao" $? "$LM/sprintx/m8.sh" l_j

# Decisao registrada e hook documentado como excecao normativa mesmo em aviso.
DSF2="$SK/DECISOES-DA-SKILL.md"
[ "$(grep -c '^| DS-149 |' "$DSF2")" -eq 1 ] && [ "$(grep -c '^| DS-150 |' "$DSF2")" -eq 1 ] \
  && tem "$DSF2" 'arquivo_de_task_irma' && tem "$DSF2" 'rastro_sessao_dona'
afirma "l24-ds149-ds150-registradas" $? "DECISOES-DA-SKILL.md"
tem "$SKILLMD" 'arquivo_de_task_irma' && tem "$SKILLMD" 'bloqueia sempre, mesmo em modo'
afirma "l25-skillmd-documenta-excecao" $? "tabela de hooks"

: # $K e as fixtures F6 permanecem ate a matriz DS-175 ao fim da bancada

echo "== M. portabilidade Git Bash: scripts e contratos markdown LF, caminho devolvido pelo Git (P0.2-C7-B S1) =="
# Dois modos. Simulado: `git` e `cygpath` falsos no PATH fazem o Git devolver `Z:/...` e o
# cygpath traduzir, em qualquer SO — e o que mata os mutantes tanto em Linux quanto no Git
# Bash. Real: sem falsos; no Git Bash o Git for Windows devolve `C:/...` de verdade.
MS="$(mktemp -d)"
# Testes podem ser carregados da cópia .claude ou do marketplace instalado.
# Resolva a raiz pelo contrato da skill, não pela profundidade de $H.
RAIZ_SRC="$H"
while [ "$RAIZ_SRC" != "/" ] && [ ! -d "$RAIZ_SRC/.claude/hooks/sprintx" ]; do
  RAIZ_SRC="$(dirname "$RAIZ_SRC")"
done
[ -d "$RAIZ_SRC/.claude/hooks/sprintx" ] || { echo "bancada: raiz sprintx indisponivel" >&2; exit 1; }
MSIM="$MS/sim"; MBIN="$MS/bin"; mkdir -p "$MSIM/z" "$MBIN" "$MS/vazio" "$MS/real"
REALGIT="$(command -v git)"; BASHBIN="$(command -v bash)"
cat > "$MBIN/cygpath" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$M_CYGLOG"
[ "$1" = -u ] || exit 64; shift; [ "$1" = -- ] && shift
[ $# -eq 1 ] || exit 64
case "$1" in
  [A-Za-z]:/*) printf '%s/%s/%s\n' "$M_SIMT" "$(printf '%s' "${1%%:*}" | tr 'A-Z' 'a-z')" "${1#?:/}" ;;
  *) printf '%s\n' "$1" ;;
esac
EOF
cat > "$MBIN/git" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *' rev-parse --show-toplevel '*|*' rev-parse --git-path '*)
    t="$("$M_REALGIT" "$@")" || exit $?
    case "$t" in
      "$M_SIMT"/z/*) printf 'Z:/%s\n' "${t#"$M_SIMT"/z/}" ;;
      *) printf '%s\n' "$t" ;;
    esac
    exit 0
    ;;
esac
exec "$M_REALGIT" "$@"
EOF
chmod +x "$MBIN/cygpath" "$MBIN/git"
m_sim() { PATH="$MBIN:$PATH" M_SIMT="$MSIM" M_CYGLOG="$MS/cyg.log" M_REALGIT="$REALGIT" "$@"; }
m_real() { "$@"; }
m_cg() { "$BASHBIN" -c '. "$1" && caminho_git "$2"' _ "$@"; }   # m_cg <helper> <entrada>
m_nao_chamou() { [ ! -s "$MS/cyg.log" ]; }
m_sem_drive() { [ -z "$(find "$1" -name '?:*' 2>/dev/null | head -1)" ]; }
m_repo() { # m_repo <dir> — repositorio git real, um commit, com subdiretorio sub/
  rm -rf "$1" "$1--wt"; mkdir -p "$1/sub"
  git -C "$1" init -q -b main && git -C "$1" -c user.email=t@t.local -c user.name=teste -c commit.gpgsign=false commit -q --allow-empty -m init
}

# A–E: o helper, isolado. Cada caso recebe a raiz de uma copia da skill.
m_a() { : > "$MS/cyg.log"; [ "$(m_sim m_cg "$1/scripts/caminho-git.sh" 'C:/repo')" = "$MSIM/c/repo" ]; }
m_b() { : > "$MS/cyg.log"; [ "$(m_sim m_cg "$1/scripts/caminho-git.sh" 'D:/repo com espaço')" = "$MSIM/d/repo com espaço" ]; }
m_c() { : > "$MS/cyg.log"; [ "$(m_sim m_cg "$1/scripts/caminho-git.sh" '/home/user/repo')" = /home/user/repo ] && m_nao_chamou; }
m_d() {
  : > "$MS/cyg.log"
  [ "$(m_sim m_cg "$1/scripts/caminho-git.sh" 'docs/sprintx/features/x')" = docs/sprintx/features/x ] \
    && [ "$(m_sim m_cg "$1/scripts/caminho-git.sh" './rel com espaço')" = './rel com espaço' ] && m_nao_chamou
}
m_e() { # sem cygpath no PATH (Linux/macOS): no-op, inclusive para a forma C:/
  [ "$(PATH="$MS/vazio" m_cg "$1/scripts/caminho-git.sh" 'C:/repo')" = 'C:/repo' ] \
    && [ "$(PATH="$MS/vazio" m_cg "$1/scripts/caminho-git.sh" '/home/user/repo')" = /home/user/repo ]
}

# F–H: os scripts, rodados de um subdiretorio, com o Git devolvendo drive Windows.
m_f() { # m_f <m_sim|m_real> <skill> <base>
  local r="$3/repo com espaço"
  m_repo "$r" >/dev/null 2>&1 || return 1
  (cd "$r/sub" && "$1" bash "$2/scripts/planejamento.sh" criar s1-demo >/dev/null 2>&1) || return 1
  [ -f "$r/docs/sprintx/features/s1-demo/00-PLANEJAMENTO.md" ] && [ ! -e "$r/sub/docs" ] && m_sem_drive "$3"
}
m_g() {
  local r="$3/repo bloq" b="$2/scripts/bloqueios.sh" out
  m_repo "$r" >/dev/null 2>&1 || return 1
  (cd "$r/sub" && "$1" bash "$b" registrar s1-demo null lacuna_de_decisao 'duvida nova' 'decisao registrada' >/dev/null 2>&1) || return 1
  out="$(cd "$r/sub" && "$1" bash "$b" listar s1-demo 2>/dev/null)" || return 1
  printf '%s\n' "$out" | grep -q '^B-01	.*	lacuna_de_decisao	aberto$' || return 1
  (cd "$r/sub" && "$1" bash "$b" validar s1-demo >/dev/null 2>&1) || return 1
  (cd "$r/sub" && "$1" bash "$b" resolver s1-demo B-01 >/dev/null 2>&1) || return 1
  out="$(cd "$r/sub" && "$1" bash "$b" listar s1-demo 2>/dev/null)" || return 1
  printf '%s\n' "$out" | grep -q '^B-01	.*	resolvido$' \
    && [ -f "$r/docs/sprintx/features/s1-demo/00-BLOQUEIOS.md" ] && [ ! -e "$r/sub/docs" ] && m_sem_drive "$3"
}
m_h() { # worktree vinculada: .git e arquivo, o Git devolve a raiz do worktree
  local r="$3/repo wt" wt="$3/repo wt--wt"
  m_repo "$r" >/dev/null 2>&1 && git -C "$r" worktree add -q -b wt "$wt" main >/dev/null 2>&1 && mkdir -p "$wt/sub" || return 1
  [ -f "$wt/.git" ] || return 1
  (cd "$wt/sub" && "$1" bash "$2/scripts/planejamento.sh" criar s1-wt >/dev/null 2>&1) || return 1
  (cd "$wt/sub" && "$1" bash "$2/scripts/bloqueios.sh" registrar s1-wt null lacuna_de_decisao 'd' 'x' >/dev/null 2>&1) || return 1
  [ -f "$wt/docs/sprintx/features/s1-wt/00-PLANEJAMENTO.md" ] && [ -f "$wt/docs/sprintx/features/s1-wt/00-BLOQUEIOS.md" ] \
    && [ ! -e "$wt/sub/docs" ] && [ ! -e "$r/docs" ] && m_sem_drive "$3"
}
m_f_sim() { m_f m_sim "$1" "$MSIM/z"; }
m_g_sim() { m_g m_sim "$1" "$MSIM/z"; }
m_h_sim() { m_h m_sim "$1" "$MSIM/z"; }
m_i() { # trava isolada: checkout principal e worktree vinculada sob caminhos Git for Windows
  local r="$3/repo lock" wt="$3/repo lock--wt" lib="$2/scripts/lib/trava-autorizacao-f6.sh" a b
  m_repo "$r" >/dev/null 2>&1 && git -C "$r" worktree add -q -b lock-wt "$wt" main >/dev/null 2>&1 || return 1
  a="$(cd "$r" && "$1" bash -c '. "$1" || exit 1; adquire_trava_autorizacao_f6 "$2" menu || exit 1; printf "%s" "$TRAVA_AUT6_DIR"; libera_trava_autorizacao_f6' _ "$lib" "$r")" || return 1
  b="$(cd "$wt" && "$1" bash -c '. "$1" || exit 1; adquire_trava_autorizacao_f6 "$2" menu || exit 1; printf "%s" "$TRAVA_AUT6_DIR"; libera_trava_autorizacao_f6' _ "$lib" "$wt")" || return 1
  [ "$a" = "$r/.git/sprintx/travas/autorizacao-f6-menu.lock" ] \
    && case "$b" in "$r/.git/worktrees/"*/sprintx/travas/autorizacao-f6-menu.lock) true ;; *) false ;; esac \
    && [ ! -e "$a" ] && [ ! -e "$b" ] && m_sem_drive "$3"
}
m_i_sim() { m_i m_sim "$1" "$MSIM/z"; }

m_a "$SK"; afirma "ma-sim-c-vira-posix" $? "C:/repo -> cygpath -u"
m_b "$SK"; afirma "mb-sim-d-com-espaco" $? "D:/repo com espaço, argumento unico"
m_c "$SK"; afirma "mc-sim-posix-intacto-sem-cygpath" $? "/home/user/repo nao chega ao cygpath"
m_d "$SK"; afirma "md-sim-relativo-intacto-sem-cygpath" $? "relativo nao chega ao cygpath"
m_e "$SK"; afirma "me-sem-cygpath-no-op" $? "Linux/macOS: nada muda"
m_f_sim "$SK"; afirma "mf-sim-planejamento-criar-na-raiz" $? "Z:/... normalizado, nada criado como Z:"
m_g_sim "$SK"; afirma "mg-sim-bloqueios-registrar-listar-validar-resolver" $? "na raiz, do subdiretorio"
m_h_sim "$SK"; afirma "mh-sim-worktree-vinculada" $? "raiz do worktree, nao a do principal"
m_i_sim "$SK"; afirma "mi-sim-trava-normaliza-main-e-worktree" $? "Z:/... normalizado no gitdir correto"
if command -v cygpath >/dev/null 2>&1; then
  [ "$(m_cg "$SK/scripts/caminho-git.sh" 'C:/repo')" = /c/repo ]; afirma "ma-real-gitbash-c" $? "cygpath real"
  [ "$(m_cg "$SK/scripts/caminho-git.sh" 'D:/repo com espaço')" = '/d/repo com espaço' ]; afirma "mb-real-gitbash-d-com-espaco" $? "cygpath real"
  m_repo "$MS/real/sonda" >/dev/null 2>&1
  case "$(git -C "$MS/real/sonda" rev-parse --show-toplevel)" in [A-Za-z]:/*) true ;; *) false ;; esac
  afirma "m-real-gitbash-git-devolve-drive" $? "o Git for Windows devolve C:/..., a condicao do bug existe"
else
  m_e "$SK"; afirma "me-real-linux-sem-cygpath" $? "ambiente sem cygpath"
fi
m_f m_real "$SK" "$MS/real"; afirma "mf-real-planejamento-criar" $? "git real do ambiente"
m_g m_real "$SK" "$MS/real"; afirma "mg-real-bloqueios" $? "git real do ambiente"
m_h m_real "$SK" "$MS/real"; afirma "mh-real-worktree" $? "git real do ambiente"
for f in planejamento.sh bloqueios.sh; do
  [ "$(grep -c 'caminho_git "$t"' "$SK/scripts/$f")" -eq 1 ] || false
done && grep -q 'caminho_git' "$SK/scripts/lib/trava-autorizacao-f6.sh"
afirma "m-uma-regra-tres-consumidores" $? "planejamento.sh, bloqueios.sh e trava usam o helper"
[ "$(find "$SK/scripts" "$H" -name '*.sh' -not -path '*/testes/*' -exec grep -l 'cygpath' {} + | sed 's|.*/||' | sort -u)" = caminho-git.sh ]
afirma "m-cygpath-so-no-helper" $? "nenhuma copia da regra fora de caminho-git.sh"

# J–L: clone limpo com core.autocrlf=true, sem depender de configuracao global/sistema.
mgit() { GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$MS/gitconfig-vazio" git "$@"; }
: > "$MS/gitconfig-vazio"
MSRC_SH="$(git -C "$RAIZ_SRC" ls-files -co --exclude-standard -- '*.sh')"
# Os .md sao contrato lido mecanicamente (sed/grep ancorados em $): CRLF quebra a leitura no Linux.
MSRC_MD="$(git -C "$RAIZ_SRC" ls-files -co --exclude-standard -- '*.md')"
MSRC_TXT="$MSRC_SH
$MSRC_MD"
m_fixture() { # m_fixture <gitattributes|-> <destino> — origem com os .sh e .md do trabalho (blobs LF), clonada com autocrlf=true
  local o="$2.origem" f
  rm -rf "$o" "$2"; mkdir -p "$o"
  mgit init -q -b main "$o" || return 1
  [ "$1" = - ] || cp "$1" "$o/.gitattributes"
  for f in $MSRC_TXT; do mkdir -p "$o/$(dirname "$f")"; tr -d '\r' < "$RAIZ_SRC/$f" > "$o/$f"; done
  mgit -C "$o" -c core.autocrlf=false add -A \
    && mgit -C "$o" -c core.autocrlf=false -c user.email=t@t.local -c user.name=teste -c commit.gpgsign=false commit -q -m fx \
    && mgit clone -q -c core.autocrlf=true "$o" "$2" && [ "$(mgit -C "$2" config core.autocrlf)" = true ]
}
m_eol_indice() { # m_eol_indice <clone> [<glob> <lista>] — indice LF, worktree LF, atributo text eol=lf — e todos presentes
  local l g="${2:-*.sh}" n="${3-$MSRC_SH}"; l="$(git -C "$1" ls-files --eol -- "$g")"; [ -n "$l" ] || return 1
  printf '%s\n' "$l" | awk '!/^i\/lf +w\/lf +attr\/text eol=lf[ \t]/ { r = 1 } END { exit r }' || return 1
  [ "$(printf '%s\n' "$l" | wc -l)" -eq "$(printf '%s\n' $n | wc -l)" ]
}
m_eol_md() { m_eol_indice "$1" '*.md' "$MSRC_MD"; }
# Por bytes, nunca por grep/$(...): no Git Bash os dois descartam o CR e o scan ficaria cego.
m_eol_bytes() { # m_eol_bytes <clone> [<lista>] — scan de bytes: nenhum CR em nenhum .sh (ou da lista)
  local f; for f in ${2-$MSRC_SH}; do [ -f "$1/$f" ] && [ "$(tr -d '\r' < "$1/$f" | wc -c)" -eq "$(wc -c < "$1/$f")" ] || return 1; done
}
m_hex() { od -An -tx1 | tr -d ' \n'; }
SHEBANG_HEX="$(printf '#!/usr/bin/env bash\n' | m_hex)"
m_shebang() { local f; for f in $MSRC_SH; do [ "$(head -c 20 "$1/$f" | m_hex)" = "$SHEBANG_HEX" ] || return 1; done; }
m_eol_bytes_md() { m_eol_bytes "$1" "$MSRC_MD"; }
# O teste real (21-regras-inviolaveis) lendo o SKILL.md do clone.
M_SKILL=.claude/skills/sprintx/SKILL.md
m_skill_legivel() { [ -f "$1/$M_SKILL" ] && [ "$(conta_regras "$1/$M_SKILL")" -eq 21 ]; }
# O `sed` do Git Bash ignora o CR antes do `$` e conta 21 num SKILL.md CRLF;
# o do GNU/Linux nao. Isso e propriedade do LEITOR desta maquina, nao do dano:
# um oraculo que dependa dele fica cego em metade das plataformas, e foi por
# isso que este caso vivia com `skip` no Git Bash. O que prova o dano em
# qualquer plataforma e a MATERIALIZACAO do arquivo que o consumidor recebe —
# indice, arvore, atributo e bytes —, e e ela que passa a ser o oraculo.
m_skill_materializa_lf() { m_eol_indice "$1" "$M_SKILL" "$M_SKILL" && m_eol_bytes "$1" "$M_SKILL"; }
# Medido, nunca suposto nem deduzido de `cygpath`: o sed desta maquina tolera CR?
m_sed_tolera_cr() { [ -n "$(printf 'x\r\n' | sed -n '/^x$/p')" ]; }
# O oraculo do mutante 11. Clausula 1 — a materializacao — vale em qualquer
# plataforma e sozinha ja mata o mutante. Clausula 2 — o leitor real do
# contrato — entra onde o leitor sente o CR, como reforco: nunca substitui a
# primeira, e a ausencia dela nunca vira skip.
m_mutante11_morre() { # m_mutante11_morre <clone>
  ! m_skill_materializa_lf "$1" || return 1
  if ! m_sed_tolera_cr; then ! m_skill_legivel "$1" || return 1; fi
  return 0
}
M11_EXTRA=""; m_sed_tolera_cr || M11_EXTRA=" + o leitor real do contrato conta != 21"
m_reprova() { ! m_eol_indice "$1" && ! m_eol_bytes "$1" && ! m_shebang "$1" && ! m_eol_md "$1" && ! m_eol_bytes_md "$1" && ! m_skill_materializa_lf "$1"; }

[ "$(grep -v '^[[:space:]]*\(#\|$\)' "$RAIZ_SRC/.gitattributes" 2>/dev/null)" = '*.sh text eol=lf
*.md text eol=lf' ]
afirma "m-gitattributes-regra-minima" $? "so *.sh e *.md text eol=lf"
git -C "$RAIZ_SRC" ls-files --eol -- '*.sh' '*.md' | awk '!/^i\/lf +w\/[a-z]+ +attr\/text eol=lf[ \t]/ { r = 1 } END { exit r }'
afirma "m-repo-blobs-lf-com-atributo" $? "indice LF e atributo em todo .sh e .md versionado"
m_fixture "$RAIZ_SRC/.gitattributes" "$MS/clone-ok" >/dev/null 2>&1; afirma "mj-clone-autocrlf-true" $? "clone limpo"
m_eol_indice "$MS/clone-ok"; afirma "mj-ls-files-eol-todos-lf" $? "i/lf w/lf attr/text eol=lf"
m_eol_bytes "$MS/clone-ok"; afirma "mj-scan-bytes-sem-crlf" $? "nenhum CR"
m_shebang "$MS/clone-ok"; afirma "ml-shebang-preservado" $? "#!/usr/bin/env bash, sem CR"
m_eol_md "$MS/clone-ok"; afirma "mj-md-ls-files-eol-todos-lf" $? "todo .md: i/lf w/lf attr/text eol=lf"
m_eol_bytes_md "$MS/clone-ok"; afirma "mj-md-scan-bytes-sem-crlf" $? "nenhum CR em .md"
m_skill_legivel "$MS/clone-ok"; afirma "mj-skill-md-legivel-pelo-teste-real" $? "conta_regras do SKILL.md do clone = 21"
m_skill_materializa_lf "$MS/clone-ok"; afirma "mj-skill-md-materializa-lf" $? "SKILL.md: i/lf w/lf attr/text eol=lf e sem CR"
m_fixture - "$MS/clone-sem" >/dev/null 2>&1 && m_reprova "$MS/clone-sem"
afirma "mk-sem-gitattributes-prova-morre" $? "cada verificacao reprova o clone sem atributo"
printf '*.sh text\n' > "$MS/attr-text"; m_fixture "$MS/attr-text" "$MS/clone-text" >/dev/null 2>&1 && m_reprova "$MS/clone-text"
afirma "mm-mutante-2a-regra-sem-eol-morre" $? "*.sh text"
printf '* text=auto\n' > "$MS/attr-auto"; m_fixture "$MS/attr-auto" "$MS/clone-auto" >/dev/null 2>&1 && m_reprova "$MS/clone-auto"
afirma "mm-mutante-2b-text-auto-morre" $? "* text=auto"
# Mutante 11: a regra *.md some. Os .sh seguem LF; os .md saem CRLF e o teste real le o SKILL.md errado no Linux.
printf '*.sh text eol=lf\n' > "$MS/attr-sem-md"; m_fixture "$MS/attr-sem-md" "$MS/clone-sem-md" >/dev/null 2>&1 \
  && m_eol_indice "$MS/clone-sem-md" && ! m_eol_md "$MS/clone-sem-md" && ! m_eol_bytes_md "$MS/clone-sem-md" \
  && ! m_skill_materializa_lf "$MS/clone-sem-md"
afirma "mm-mutante-11-sem-regra-md-morre" $? "*.md sem eol=lf: indice/worktree, bytes e o SKILL.md do consumidor reprovam"
# O mesmo mutante, agora pelo oraculo do consumidor — sem `skip` em plataforma
# nenhuma: onde o sed tolera CR, a materializacao mata sozinha; onde nao
# tolera, a leitura real do contrato entra junto.
m_mutante11_morre "$MS/clone-sem-md"
afirma "mm-mutante-11-skill-md-nao-chega-lf" $? "a materializacao do SKILL.md reprova em qualquer plataforma$M11_EXTRA"
! m_mutante11_morre "$MS/clone-ok"
afirma "mm-controle-11-clone-com-a-regra-passa" $? "o clone com *.md text eol=lf nao e reprovado pelo oraculo"

# Mutante 10: o proprio teste passa a aceitar CRLF. Cada verificacao mutada, rodada contra o
# clone sem atributo, ACEITA — e isso que a afirmacao mk ja reprovaria.
m_muta_fn() { # m_muta_fn <funcao> <nova> <trecho> <troca>
  declare -f "$1" | sed "1s/^$1 /$2 /" > "$MS/fn.orig" && muta_lit "$MS/fn.orig" "$MS/fn.mut" "$3" "$4" && . "$MS/fn.mut"
}
m_muta_fn m_eol_indice m10a 'w\/lf +attr\/text eol=lf[ \t]' 'w\/[a-z]+ +attr\/[a-z =]*[ \t]' && m10a "$MS/clone-sem"
afirma "mm-mutante-10a-indice-aceita-crlf-morre" $? "a verificacao mutada aceitaria o clone CRLF"
m_muta_fn m_eol_bytes m10b "tr -d '\\r'" "tr -d '\\001'" && m10b "$MS/clone-sem"
afirma "mm-mutante-10b-scan-aceita-crlf-morre" $? "a verificacao mutada aceitaria o clone CRLF"
m_muta_fn m_shebang m10c 'head -c 20 "$1/$f"' 'head -n 1 "$1/$f" | tr -d "\r" | head -c 20' && m10c "$MS/clone-sem"
afirma "mm-mutante-10c-shebang-aceita-crlf-morre" $? "a verificacao mutada aceitaria o clone CRLF"
# 11a: o oraculo deixa de exigir a materializacao e passa a achar o clone CRLF verde.
m_muta_fn m_skill_materializa_lf m11a 'm_eol_indice "$1" "$M_SKILL" "$M_SKILL" && m_eol_bytes "$1" "$M_SKILL"' 'true' \
  && m11a "$MS/clone-sem-md"
afirma "mm-mutante-11a-oraculo-sem-materializacao-morre" $? "sem a materializacao, o oraculo aceitaria o SKILL.md CRLF"
# 11b: o oraculo volta a depender SO do leitor real. Nao precisa de Git Bash
# para provar que fica cego: basta dar a ele o que um leitor tolerante a CR
# enxerga do MESMO arquivo — e ele conta 21, sem ver dano nenhum.
mkdir -p "$MS/tolerante"; tr -d '\r' < "$MS/clone-sem-md/$M_SKILL" > "$MS/tolerante/SKILL.md"
[ "$(conta_regras "$MS/tolerante/SKILL.md")" -eq 21 ]
afirma "mm-mutante-11b-oraculo-so-sed-fica-cego" $? "leitor tolerante a CR conta 21 no SKILL.md CRLF: so o sed nao mata o mutante"

# Mutantes dos scripts e do helper, em copia da skill (scripts/ + assets/). O controle, copia
# sem mutacao, sobrevive a todos os casos; cada mutante morre pelos casos designados.
copia_skill_m() {
  local d="$MS/mut/$1"; rm -rf "$d"; mkdir -p "$d/scripts/lib" "$d/assets"
  cp "$SK/assets/TEMPLATE-PLANEJAMENTO.md" "$SK/assets/TEMPLATE-BLOQUEIOS.md" "$d/assets/"
  cp "$SK/scripts/planejamento.sh" "$SK/scripts/bloqueios.sh" "$SK/scripts/caminho-git.sh" "$d/scripts/"
  cp "$SK/scripts/lib/trava-autorizacao-f6.sh" "$d/scripts/lib/"
  printf '%s' "$d"
}
m_troca() { muta_lit "$1" "$1.m" "$2" "$3" && mv "$1.m" "$1"; }
mutante_m() { # mutante_m <nome> <rc geracao> <skill> <caso que TEM de matar>...
  local nome="$1" rc="$2" s="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do "$c" "$s" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]; afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
CASOS_M="m_a m_b m_c m_d m_e m_f_sim m_g_sim m_h_sim"
M="$(copia_skill_m controle)"; vivosm=""
for c in $CASOS_M; do "$c" "$M" || vivosm="$vivosm$c "; done
[ -z "$vivosm" ]; afirma "mm-controle-copia-intacta-sobrevive" $? "${vivosm:-nenhum caso reprova a copia sem mutacao}"
LINHA_CG='    [A-Za-z]:/*) if command -v cygpath >/dev/null 2>&1; then cygpath -u -- "$1" && return 0; fi ;;'
LINHA_RAIZ='  local t; t="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$t" ] && { caminho_git "$t"; return; }'
LINHA_DIR='  local d="$PWD"; while [ "$d" != / ]; do [ -d "$d/.git" ] && { printf '"'%s'"' "$d"; return; }; d="$(dirname "$d")"; done'
M="$(copia_skill_m m3)"; m_troca "$M/scripts/caminho-git.sh" "$LINHA_CG" '    [A-Za-z]:/*) : ;;'
mutante_m "mm-mutante-3-sem-cygpath" $? "$M" m_a m_f_sim
M="$(copia_skill_m m4)"; m_troca "$M/scripts/caminho-git.sh" "$LINHA_CG" '    *) cygpath -u -- "$1"; return ;;'
mutante_m "mm-mutante-4-cygpath-em-tudo-quebra-linux" $? "$M" m_c m_e
M="$(copia_skill_m m4b)"; m_troca "$M/scripts/caminho-git.sh" '    [A-Za-z]:/*) if command' '    *) if command'
mutante_m "mm-mutante-4b-cygpath-indiscriminado" $? "$M" m_c m_d
M="$(copia_skill_m m5)"; m_troca "$M/scripts/caminho-git.sh" '    [A-Za-z]:/*) if command' '    [Cc]:/*) if command'
mutante_m "mm-mutante-5-so-drive-c" $? "$M" m_b
M="$(copia_skill_m m6)"; m_troca "$M/scripts/planejamento.sh" '{ caminho_git "$t"; return; }' '{ printf '"'%s'"' "$t"; return; }'
mutante_m "mm-mutante-6-planejamento-ignora-helper" $? "$M" m_f_sim m_h_sim
M="$(copia_skill_m m7)"; m_troca "$M/scripts/bloqueios.sh" '{ caminho_git "$t"; return; }' '{ printf '"'%s'"' "$t"; return; }'
mutante_m "mm-mutante-7-bloqueios-ignora-helper" $? "$M" m_g_sim m_h_sim
M="$(copia_skill_m m8)"; m_troca "$M/scripts/planejamento.sh" "$LINHA_RAIZ" "$LINHA_DIR" \
  && m_troca "$M/scripts/bloqueios.sh" "$LINHA_RAIZ" "$LINHA_DIR"
mutante_m "mm-mutante-8-worktree-usa-git-como-diretorio" $? "$M" m_h_sim
M="$(copia_skill_m m9)"; m_troca "$M/scripts/caminho-git.sh" 'cygpath -u -- "$1"' 'cygpath -u -- $1'
mutante_m "mm-mutante-9-espaco-quebrado" $? "$M" m_b

DSF3="$SK/DECISOES-DA-SKILL.md"
[ "$(grep -c '^| DS-151 |' "$DSF3")" -eq 1 ] && [ "$(grep -c '^| DS-152 |' "$DSF3")" -eq 1 ] \
  && tem "$DSF3" 'eol=lf' && tem "$DSF3" 'caminho_git'
afirma "m-ds151-ds152-registradas" $? "DECISOES-DA-SKILL.md"

rm -rf "$MS"

echo "== N. escopo e ownership do TRABALHO corrente, nao do id da task (P0.2-C7-B S2) =="
# Features se acumulam no repositorio: `T-01.01` existe na feature de hoje e em
# toda feature antiga. O id sozinho nunca identifica o plano — a sessao resolve
# TRABALHO + TASK pelo rastro, e so o plano daquele trabalho participa (DS-153).
NF_DIR="$(mktemp -d)"
N_SEQ=0
N_SAIDA=""; N_RC=0

n_ev() { # n_ev <dir> <arquivo-de-rastro> <evento> <task> <sessao> [trabalho_id-do-campo]
  local d="$1" tr="$2" evt="$3" tk="$4" ses="$5" campo="${6:-$2}" arq
  arq="$d/docs/eventos/$tr.jsonl"; mkdir -p "$(dirname "$arq")"
  N_SEQ=$((N_SEQ + 1))
  printf '{"ts":"2026-09-22T10:%02d:00Z","expx_eventos":1,"trabalho_id":"%s","ferramenta":"sprintx","origem":"skill","evento":"%s","fase":"f6","task":"%s","agente":"principal","resultado":"ok","detalhe":null,"arquivos":[],"sessao":"%s","harness":"claude"}\n' \
    "$N_SEQ" "$campo" "$evt" "$tk" "$ses" >> "$arq"
}
n_task() { # n_task <id> <status> <altera> [titulo]
  printf '  - id: %s\n    titulo: %s\n    status: %s\n    objetivo: obj\n    arquivos:\n      cria: []\n      altera: [%s]\n    teste_integracao: t\n    teste_funcional: t\n    criterio_aceite: c\n    depende_de: []\n    paralelizavel: false\n    concluida_em: null\n    suite: nao_executada\n' \
    "$1" "${4:-Task $1 original}" "$2" "$3"
}
n_plano() { # n_plano <arquivo> <trabalho_id> <sprint-NN> — tasks vem do stdin
  mkdir -p "$(dirname "$1")"
  { printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: tasks\ntrabalho_id: %s\nsprint_id: sprint-%s\ntasks:\n' "$2" "$3"
    cat
    printf -- '---\n'; } > "$1"
}
n_hook() { # n_hook <dir> <hook> <arquivo-relativo> <sessao> — rc em N_RC, saida em N_SAIDA
  N_SAIDA="$(printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$1" "$1/$3" \
    | (cd "$1" && EXPX_SESSAO="$4" bash "$2") 2>&1)"; N_RC=$?
}
n_tem() { printf '%s' "$N_SAIDA" | grep -qF "$1"; }
n_silencio() { [ "$N_RC" -eq 0 ] && [ -z "$N_SAIDA" ]; }

# n_fx <dir> <slug-historico> <ordem: hist|corr>
# Duas features vivas no mesmo repo, ambas com T-01.01. <slug-historico> troca a
# ordem alfabetica; <ordem> troca a ordem de criacao e o mtime — a feature
# HISTORICA fica sempre como a mais recente no disco, para que nada que olhe
# mtime possa ser confundido com o trabalho da sessao.
# A branch tambem leva o nome da historica, para matar "trabalho pelo branch".
n_fx() {
  local d="$1" h="$2" ordem="$3" f
  rm -rf "$d"; mkdir -p "$d/src"
  # Repo sem commit: o hook so precisa da raiz (rastro_raiz acha o .git). A
  # branch leva o nome da HISTORICA, para matar "trabalho pelo nome da branch".
  git init -q --template= -b "feature/$h" "$d" >/dev/null 2>&1
  N_HIST="$h"; N_CORR=corrente
  n_corrente() { n_plano "$d/docs/sprintx/features/corrente/sprint-01/tasks.md" corrente 01; }
  n_historica() { n_plano "$d/docs/sprintx/features/$h/sprint-01/tasks.md" "$h" 01; }
  if [ "$ordem" = corr ]; then
    n_corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
EOF
    n_historica <<EOF
$(n_task T-01.01 concluida src/antigo.ts)
EOF
  else
    n_historica <<EOF
$(n_task T-01.01 concluida src/antigo.ts)
EOF
    n_corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
EOF
  fi
  # historica sempre a mais nova no disco
  touch "$d/docs/sprintx/features/$h/sprint-01/tasks.md" "$d/docs/sprintx/features/$h"
  n_ev "$d" corrente task_iniciada T-01.01 eu@sessao
}
# Reescreve o plano de um trabalho ja existente na fixture.
n_replano() { # n_replano <dir> <trabalho> — tasks do stdin
  n_plano "$1/docs/sprintx/features/$2/sprint-01/tasks.md" "$2" 01
}

# ---------------------------------------------------------------- os casos
# Cada caso monta a fixture do zero e roda o hook recebido em $1 — e assim que
# os mutantes sao julgados.
n_a() { # mesma task id nas duas features: a corrente usa so o proprio plano
  n_fx "$NF_DIR/a" alfa-antiga hist
  n_hook "$NF_DIR/a" "$1" src/novo.ts eu@sessao; n_silencio
}
n_b() { # historica primeiro no alfabeto: resultado identico
  n_fx "$NF_DIR/b" alfa-antiga hist
  n_hook "$NF_DIR/b" "$1" src/novo.ts eu@sessao; n_silencio
}
n_c() { # ordem invertida (nome, criacao, mtime): resultado identico
  n_fx "$NF_DIR/c" zeta-antiga corr
  n_hook "$NF_DIR/c" "$1" src/novo.ts eu@sessao || return 1
  n_silencio
}
n_d() { # arquivo so da task historica: nao planejado na corrente, NAO irma
  n_fx "$NF_DIR/d" alfa-antiga hist
  n_hook "$NF_DIR/d" "$1" src/antigo.ts eu@sessao
  [ "$N_RC" -eq 0 ] && n_tem "nao esta na lista" && ! n_tem "arquivo_de_task_irma" && ! n_tem "defeito_de_plano"
}
n_e() { # o mesmo arquivo tambem numa irma DA CORRENTE: irma-only, bloqueio duro
  n_fx "$NF_DIR/e" alfa-antiga hist
  n_replano "$NF_DIR/e" corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
$(n_task T-01.02 pendente src/antigo.ts)
EOF
  n_hook "$NF_DIR/e" "$1" src/antigo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem arquivo_de_task_irma && n_tem T-01.02
}
n_f() { # mesmo arquivo na task atual corrente e na historica: current vence
  n_fx "$NF_DIR/f" alfa-antiga hist
  n_replano "$NF_DIR/f" alfa-antiga <<EOF
$(n_task T-01.01 concluida src/novo.ts)
EOF
  n_hook "$NF_DIR/f" "$1" src/novo.ts eu@sessao; n_silencio
}
n_g() { # atual + irma corrente + historica: current vence
  n_fx "$NF_DIR/g" alfa-antiga hist
  n_replano "$NF_DIR/g" corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
$(n_task T-01.02 pendente src/novo.ts)
EOF
  n_replano "$NF_DIR/g" alfa-antiga <<EOF
$(n_task T-01.01 concluida src/novo.ts)
EOF
  n_hook "$NF_DIR/g" "$1" src/novo.ts eu@sessao; n_silencio
}
n_h() { # duas irmas correntes + uma historica: lista SO as correntes
  n_fx "$NF_DIR/h" alfa-antiga hist
  n_replano "$NF_DIR/h" corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
$(n_task T-01.02 pendente src/compartilhado.ts)
$(n_task T-01.03 pendente src/compartilhado.ts)
EOF
  n_replano "$NF_DIR/h" alfa-antiga <<EOF
$(n_task T-01.09 concluida src/compartilhado.ts)
EOF
  n_hook "$NF_DIR/h" "$1" src/compartilhado.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem T-01.02 && n_tem T-01.03 && ! n_tem T-01.09
}
n_i() { # a sessao resolve trabalho + task: o aviso cita a task e os arquivos DO plano corrente
  n_fx "$NF_DIR/i" alfa-antiga hist
  n_hook "$NF_DIR/i" "$1" src/nada.ts eu@sessao
  [ "$N_RC" -eq 0 ] && n_tem "a task T-01.01" && n_tem src/novo.ts && ! n_tem src/antigo.ts
}
n_j() { # zero sessao ativa: fail-closed
  n_fx "$NF_DIR/j" alfa-antiga hist
  : > "$NF_DIR/j/docs/eventos/corrente.jsonl"
  n_hook "$NF_DIR/j" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem sessao_ambigua
}
n_k() { # a mesma sessao reivindicando task em DOIS trabalhos: fail-closed
  n_fx "$NF_DIR/k" alfa-antiga hist
  n_replano "$NF_DIR/k" alfa-antiga <<EOF
$(n_task T-01.01 em_andamento src/antigo.ts)
EOF
  n_ev "$NF_DIR/k" alfa-antiga task_iniciada T-01.01 eu@sessao
  n_hook "$NF_DIR/k" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem sessao_ambigua
}
n_l() { # plano do trabalho corrente ausente: fail-closed, sem cair na historica
  n_fx "$NF_DIR/l" alfa-antiga hist
  n_replano "$NF_DIR/l" alfa-antiga <<EOF
$(n_task T-01.01 em_andamento src/antigo.ts)
EOF
  rm -rf "$NF_DIR/l/docs/sprintx/features/corrente"
  n_hook "$NF_DIR/l" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem plano_corrente_ausente
}
n_m() { # plano do trabalho corrente ilegivel: fail-closed
  n_fx "$NF_DIR/m" alfa-antiga hist
  printf 'isto nao e um plano\n' > "$NF_DIR/m/docs/sprintx/features/corrente/sprint-01/tasks.md"
  n_replano "$NF_DIR/m" alfa-antiga <<EOF
$(n_task T-01.01 em_andamento src/antigo.ts)
EOF
  n_hook "$NF_DIR/m" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem plano_corrente_ilegivel
}
n_n() { # layout legado DO trabalho corrente: funciona, com as mesmas regras
  n_fx "$NF_DIR/n" alfa-antiga hist
  rm -rf "$NF_DIR/n/docs/sprintx/features/corrente"
  n_plano "$NF_DIR/n/docs/corrente/sprint-01/tasks.md" corrente 01 <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
$(n_task T-01.02 pendente src/legado-irma.ts)
EOF
  n_hook "$NF_DIR/n" "$1" src/novo.ts eu@sessao; n_silencio || return 1
  n_hook "$NF_DIR/n" "$1" src/legado-irma.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem arquivo_de_task_irma && n_tem T-01.02
}
n_o() { # legado de OUTRO trabalho nunca vira fallback do corrente
  n_fx "$NF_DIR/o" alfa-antiga hist
  rm -rf "$NF_DIR/o/docs/sprintx/features/corrente"
  n_plano "$NF_DIR/o/docs/legado-de-outro/sprint-01/tasks.md" legado-de-outro 01 <<EOF
$(n_task T-01.01 em_andamento src/antigo.ts)
EOF
  n_hook "$NF_DIR/o" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem plano_corrente_ausente
}
n_p() { # titulos mudam: resultado identico ao n_e
  n_fx "$NF_DIR/p" alfa-antiga hist
  n_replano "$NF_DIR/p" corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts 'Reescrita total do topo — antigo.ts tambem')
$(n_task T-01.02 pendente src/antigo.ts 'Nome completamente diferente')
EOF
  n_replano "$NF_DIR/p" alfa-antiga <<EOF
$(n_task T-01.01 concluida src/antigo.ts 'Task historica renomeada')
EOF
  n_hook "$NF_DIR/p" "$1" src/antigo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem arquivo_de_task_irma && n_tem T-01.02
}
n_q() { # C2 preservado: irma-only bloqueia mesmo em modo aviso, com historica no repo
  n_fx "$NF_DIR/q" alfa-antiga hist
  n_replano "$NF_DIR/q" corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
$(n_task T-01.02 pendente src/antigo.ts)
EOF
  mkdir -p "$NF_DIR/q/.expx"
  printf '{"hooks":{"escopo-da-task":{"modo":"aviso"}}}\n' > "$NF_DIR/q/.expx/hooks.json"
  n_hook "$NF_DIR/q" "$1" src/antigo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem arquivo_de_task_irma
}
n_s() { # arquivo de task nenhuma: segue aviso, nunca defeito_de_plano
  n_fx "$NF_DIR/s" alfa-antiga hist
  n_hook "$NF_DIR/s" "$1" src/nada.ts eu@sessao
  [ "$N_RC" -eq 0 ] && ! n_tem defeito_de_plano && ! n_tem arquivo_de_task_irma
}
n_t() { # duas sessoes, dois trabalhos: cada uma no seu escopo
  n_fx "$NF_DIR/t" alfa-antiga hist
  n_replano "$NF_DIR/t" alfa-antiga <<EOF
$(n_task T-01.01 em_andamento src/antigo.ts)
$(n_task T-01.02 pendente src/so-da-antiga.ts)
EOF
  n_ev "$NF_DIR/t" alfa-antiga task_iniciada T-01.01 outra@sessao
  n_hook "$NF_DIR/t" "$1" src/novo.ts eu@sessao; n_silencio || return 1
  n_hook "$NF_DIR/t" "$1" src/antigo.ts outra@sessao; n_silencio || return 1
  # a irma da outra feature so existe para a sessao da outra feature
  n_hook "$NF_DIR/t" "$1" src/so-da-antiga.ts outra@sessao
  [ "$N_RC" -eq 2 ] && n_tem arquivo_de_task_irma || return 1
  n_hook "$NF_DIR/t" "$1" src/so-da-antiga.ts eu@sessao
  [ "$N_RC" -eq 0 ] && n_tem "nao esta na lista"
}
n_u() { # acumulo: uma TERCEIRA feature historica nao muda resposta nenhuma
  n_fx "$NF_DIR/u" alfa-antiga hist
  n_replano "$NF_DIR/u" corrente <<EOF
$(n_task T-01.01 em_andamento src/novo.ts)
$(n_task T-01.02 pendente src/antigo.ts)
EOF
  local antes depois rc_antes
  n_hook "$NF_DIR/u" "$1" src/antigo.ts eu@sessao; antes="$N_SAIDA"; rc_antes="$N_RC"
  n_plano "$NF_DIR/u/docs/sprintx/features/meio-antiga/sprint-01/tasks.md" meio-antiga 01 <<EOF
$(n_task T-01.01 concluida src/antigo.ts)
$(n_task T-01.02 concluida src/novo.ts)
$(n_task T-01.03 em_andamento src/terceiro.ts)
EOF
  n_ev "$NF_DIR/u" meio-antiga task_iniciada T-01.03 terceira@sessao
  n_hook "$NF_DIR/u" "$1" src/antigo.ts eu@sessao; depois="$N_SAIDA"
  [ "$rc_antes" -eq 2 ] && [ "$N_RC" -eq 2 ] && [ "$antes" = "$depois" ] || return 1
  n_hook "$NF_DIR/u" "$1" src/novo.ts eu@sessao; n_silencio
}
n_div() { # nome do arquivo de rastro x campo trabalho_id do evento: fail-closed
  n_fx "$NF_DIR/div" alfa-antiga hist
  : > "$NF_DIR/div/docs/eventos/corrente.jsonl"
  n_ev "$NF_DIR/div" corrente task_iniciada T-01.01 eu@sessao outro-trabalho
  n_hook "$NF_DIR/div" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem contexto_de_trabalho_divergente
}
n_amb() { # o mesmo trabalho nos dois layouts: nao da para amarrar plano a trabalho
  n_fx "$NF_DIR/amb" alfa-antiga hist
  n_plano "$NF_DIR/amb/docs/corrente/sprint-01/tasks.md" corrente 01 <<EOF
$(n_task T-01.01 em_andamento src/outro-novo.ts)
EOF
  n_hook "$NF_DIR/amb" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem plano_corrente_ambiguo
}
n_fora() { # task reivindicada que o plano do proprio trabalho nao declara
  n_fx "$NF_DIR/fora" alfa-antiga hist
  n_replano "$NF_DIR/fora" corrente <<EOF
$(n_task T-07.07 em_andamento src/novo.ts)
EOF
  n_hook "$NF_DIR/fora" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem task_fora_do_plano_corrente
}
n_lnk() { # todo plano e link: sem reivindicacao avisa que nao conferiu; com ela, fecha (DS-154)
  local d="$NF_DIR/lnk" p
  n_fx "$d" alfa-antiga hist
  mkdir -p "$d/fora"
  for p in corrente alfa-antiga; do
    mv "$d/docs/sprintx/features/$p/sprint-01/tasks.md" "$d/fora/$p.md"
    ln -s "$d/fora/$p.md" "$d/docs/sprintx/features/$p/sprint-01/tasks.md" || return 1
  done
  n_hook "$d" "$1" src/novo.ts outra@sessao
  [ "$N_RC" -eq 0 ] && n_tem "NAO foi conferida" && n_tem "(link)" || return 1
  n_hook "$d" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem plano_corrente_ilegivel && n_tem "(link)"
}
n_lnkdir() { # plano numa pasta por link: tambem nao le; avisa, ou fecha se a sessao reivindicou
  local d="$NF_DIR/lnkdir"
  n_fx "$d" alfa-antiga hist
  mkdir -p "$d/fora"
  mv "$d/docs/sprintx/features" "$d/fora/features"
  ln -s "$d/fora/features" "$d/docs/sprintx/features" || return 1
  n_hook "$d" "$1" src/novo.ts outra@sessao
  [ "$N_RC" -eq 0 ] && n_tem "NAO foi conferida" && n_tem "(pasta por link)" || return 1
  n_hook "$d" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem plano_corrente_ilegivel && n_tem "(pasta por link)"
}
. "$H/testes/bancada-escopo-links.sh"

NHOOK="$H/sprintx/escopo-da-task.sh"
bash -n "$NHOOK"; afirma "n0-hook-sintaxe" $? "bash -n"
for par in \
  n_a:na-duas-features-mesmo-id-usa-so-o-proprio-plano \
  n_b:nb-historica-primeiro-no-alfabeto-nao-muda \
  n_c:nc-ordem-de-criacao-e-mtime-invertidos-nao-mudam \
  n_d:nd-arquivo-so-da-historica-nao-e-irma \
  n_e:ne-arquivo-de-irma-corrente-bloqueia \
  n_f:nf-mesmo-arquivo-na-atual-e-na-historica-current-vence \
  n_g:ng-atual-mais-irma-mais-historica-current-vence \
  n_h:nh-lista-so-as-irmas-correntes \
  n_i:ni-sessao-resolve-trabalho-e-task \
  n_j:nj-zero-sessao-ativa-fail-closed \
  n_k:nk-sessao-em-dois-trabalhos-fail-closed \
  n_l:nl-plano-corrente-ausente-fail-closed \
  n_m:nm-plano-corrente-ilegivel-fail-closed \
  n_n:nn-legado-do-trabalho-corrente-funciona \
  n_o:no-legado-de-outro-trabalho-nunca-e-fallback \
  n_p:np-titulos-mudam-resultado-igual \
  n_q:nq-irma-bloqueia-mesmo-em-aviso \
  n_s:ns-arquivo-de-ninguem-segue-aviso \
  n_t:nt-duas-sessoes-dois-trabalhos \
  n_u:nu-terceira-feature-historica-nao-muda-nada \
  n_div:ndiv-trabalho-divergente-fail-closed \
  n_amb:namb-dois-layouts-do-mesmo-trabalho-fail-closed \
  n_fora:nfora-task-fora-do-plano-corrente-fail-closed \
  n_lnk:nlnk-plano-por-link-avisa-ou-fecha-pela-reivindicacao \
  n_lnkdir:nlnkdir-plano-em-pasta-por-link-avisa-ou-fecha-pela-reivindicacao \
  n_lnkhist:nlnkhist-so-o-plano-corrente-por-link-fecha-sem-porteiro \
  n_lnkirma:nlnkirma-sprint-corrente-por-link-fail-closed \
  n_lnkoutra:nlnkoutra-link-de-outra-feature-segue-aviso \
  n_lnkvazio:nlnkvazio-task-sem-arquivos-com-sprint-por-link-fecha \
  n_lnkfundo:nlnkfundo-link-fora-do-alcance-do-resolvedor-nao-fecha; do
  "${par%%:*}" "$NHOOK"; afirma "${par#*:}" $? "${par%%:*}"
done

# ------------------------------------------------------------------ mutantes
# Cada mutante mora num diretorio proprio com sprintx/ + comum/ (o hook faz
# `source ../comum/rastro.sh`), porque alguns mutam o helper, nao o hook.
NM="$NF_DIR/mut"
n_copia() { # n_copia <nome> — devolve o caminho do hook copiado
  local d="$NM/$1"; rm -rf "$d"; mkdir -p "$d/sprintx" "$d/comum"
  cp "$H/comum/rastro.sh" "$d/comum/rastro.sh"
  cp "$NHOOK" "$d/sprintx/escopo-da-task.sh"
  printf '%s' "$d/sprintx/escopo-da-task.sh"
}
n_muta() { # n_muta <arquivo> <trecho> <troca>
  muta_lit "$1" "$1.m" "$2" "$3" && mv "$1.m" "$1"
}
n_mutante() { # n_mutante <nome> <rc geracao> <hook mutante> <caso que TEM de matar>...
  local nome="$1" rc="$2" s="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do "$c" "$s" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]
  afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
CASOS_N="n_a n_c n_d n_e n_f n_g n_h n_i n_j n_k n_l n_m n_n n_o n_p n_q n_s n_t n_u n_div n_amb n_fora"

NMC="$(n_copia controle)"; vivosn=""
for c in $CASOS_N; do "$c" "$NMC" || vivosn="$vivosn$c "; done
[ -z "$vivosn" ]; afirma "nm-controle-copia-intacta-sobrevive" $? "${vivosn:-nenhum caso reprova a copia sem mutacao}"

# Os literais seguem a reescrita de custo do hook (DS-157): o plano do trabalho e escolhido
# no END do awk (do_trabalho/PTR). A intencao de cada mutante e a de sempre.
L_CANON='    if (index(f, CAN) == 1 && barras(substr(f, length(CAN) + 1)) <= 2) return 1'
L_LEGADO='    if (index(f, LEG) == 1 && barras(substr(f, length(LEG) + 1)) <= 2) return 2'
L_GLOBAL='    if (index(f, raiz "/docs/") == 1) return 1'

NMUT="$(n_copia m1)"; n_muta "$NMUT" "$L_CANON" "$L_GLOBAL"
n_mutante "nm-mutante-1-volta-ao-find-global" $? "$NMUT" n_d n_h

# So n_h: com a task homonima da historica tendo o MESMO id da corrente, quem
# vence em n_d depende da ordem que o find devolve — e ordem nao e prova. Em
# n_h a irma historica tem id proprio (T-01.09) e aparece na lista em qualquer
# filesystem.
NMUT="$(n_copia m2)"; n_muta "$NMUT" 'PTR[i] = do_trabalho(PARQ[i]); if (PTR[i]) npt++' 'PTR[i] = 1; if (PTR[i]) npt++'
n_mutante "nm-mutante-2-primeiro-plano-com-o-mesmo-id" $? "$NMUT" n_h

NMUT="$(n_copia m3)"; n_muta "$NMUT" '    if (!TEMCAN && !TEMLEG) { print "P ausente"; exit }' \
  '    if (!TEMCAN && !TEMLEG) { SEMPLANO = 1 }' \
  && n_muta "$NMUT" '    npt = 0; for (i = 1; i <= NP; i++) { PTR[i] = do_trabalho(PARQ[i]); if (PTR[i]) npt++ }' \
  '    npt = 0; for (i = 1; i <= NP; i++) { PTR[i] = SEMPLANO ? 1 : do_trabalho(PARQ[i]); if (PTR[i]) npt++ }'
n_mutante "nm-mutante-3-plano-historico-como-fallback" $? "$NMUT" n_l n_o

NMUT="$(n_copia m4)"; n_muta "$NMUT" 'if (PID[i] == ID && PTR[i] && (cur == ""' 'if (PID[i] == ID && (cur == ""'
n_mutante "nm-mutante-4-uniao-de-todas-as-features-como-others" $? "$NMUT" n_a n_i

NMUT="$(n_copia m5)"; n_muta "$NMUT" 'if (N == 1) { split(RV_L[1], p, "\t"); T = p[1]; ID = p[2]; COER = p[3] }' \
  'if (N == 1) { split(RV_L[1], p, "\t"); ID = p[2]; COER = p[3]; c = "git -C \"" raiz "\" symbolic-ref --short HEAD 2>/dev/null"; c | getline T; close(c); sub(/.*\//, "", T) }'
n_mutante "nm-mutante-5-trabalho-pelo-nome-da-branch" $? "$NMUT" n_a n_d

# A reivindicacao deixa de ser DA SESSAO: toda task aberta no rastro conta como desta sessao.
NMUT="$(n_copia m6)"; n_muta "$NMUT" '    _rv_fim(ses); N = RV_N' \
  '    for (k in _rv_dono) if (_rv_dono[k] != "") _rv_dono[k] = ses; _rv_fim(ses); N = RV_N'
n_mutante "nm-mutante-6-primeira-task-em-andamento" $? "$NMUT" n_t n_u

NMUT="$(n_copia m7)"; n_muta "$NMUT" 'if [ "$COERENCIA" != "ok" ]; then' 'if false; then'
n_mutante "nm-mutante-7-ignora-trabalho-divergente" $? "$NMUT" n_div

NMUT="$(n_copia m8)"; n_muta "$NMUT" 'if [ "$DECL" = irma ]; then' \
  'if [ "$DECL" = irma ] || grep -qsF -- "$REL" "$RAIZ"/docs/sprintx/features/*/sprint-*/tasks.md "$RAIZ"/docs/*/sprint-*/tasks.md >/dev/null 2>&1; then'
n_mutante "nm-mutante-8-irma-historica-vira-irma-da-corrente" $? "$NMUT" n_d

# Os arquivos da task corrente viram a uniao de TODA task com o mesmo id, de qualquer feature.
NMUT="$(n_copia m9)"; n_muta "$NMUT" '    k = cur SUBSEP ID; lista = ""; corrente = 0' \
  '    k = cur SUBSEP ID; lista = ""; corrente = 0; for (i = 1; i <= NP; i++) if (PID[i] == ID && PARQ[i] != cur) for (j = 1; j <= NAN[PARQ[i] SUBSEP ID]; j++) NA[k, ++NAN[k]] = NA[PARQ[i] SUBSEP ID, j]'
n_mutante "nm-mutante-9-task-homonima-historica-autoriza" $? "$NMUT" n_e n_p

NMUT="$(n_copia m10)"; n_muta "$NMUT" "$L_LEGADO" \
  '    if (index(f, raiz "/docs/") == 1 && barras(substr(f, length(raiz "/docs/") + 1)) <= 2) return 2'
n_mutante "nm-mutante-10-legado-de-outro-trabalho-como-fallback" $? "$NMUT" n_o

# Mutante do helper: sem o filtro de sessao, o par volta a ser "o primeiro que
# aparece no rastro" — a regressao que a DS-150 proibiu.
NMUT="$(n_copia m11)"; n_muta "$NM/m11/comum/rastro.sh" \
  'if (_rv_dono[k] == "" || _rv_dono[k] != ses) continue' 'if (_rv_dono[k] == "") continue'
n_mutante "nm-mutante-11-helper-ignora-a-sessao" $? "$NMUT" n_t n_u

DSF4="$SK/DECISOES-DA-SKILL.md"
[ "$(grep -c '^| DS-153 |' "$DSF4")" -eq 1 ] && [ "$(grep -c '^| DS-154 |' "$DSF4")" -eq 1 ] \
  && tem "$DSF4" 'rastro_reivindicacoes_da_sessao' && tem "$DSF4" 'plano_corrente_ausente'
afirma "n-ds153-ds154-registradas" $? "DECISOES-DA-SKILL.md"

rm -rf "$NF_DIR"

echo "== O. o rastro grava no TRABALHO corrente, nunca no mais recente por mtime (P0.2-C7-B S3) =="
# Duas features vivas, duas sessoes, e a feature ERRADA deixada de proposito
# como a mais recente no disco. O destino do evento sai do trabalho que o
# chamador declara, ou do trabalho corrente da sessao — mtime nunca participa
# (DS-155). Reusa n_plano/n_task da secao N: o plano e o mesmo artefato.
OF_DIR="$(mktemp -d)"
O_SEQ=0; O_SAIDA=""; O_RC=0

o_ev() { # o_ev <dir> <trabalho> <task> <sessao>
  local arq="$1/docs/eventos/$2.jsonl"; mkdir -p "$(dirname "$arq")"
  O_SEQ=$((O_SEQ + 1))
  printf '{"ts":"2026-09-23T09:%02d:00Z","expx_eventos":1,"trabalho_id":"%s","ferramenta":"sprintx","origem":"skill","evento":"task_iniciada","fase":"f6","task":"%s","agente":"principal","resultado":"ok","detalhe":null,"arquivos":[],"sessao":"%s","harness":"claude"}\n' \
    "$O_SEQ" "$2" "$3" "$4" >> "$arq"
}
o_ck() { cksum < "$1" 2>/dev/null; }                      # byte a byte
o_linhas() { grep -c '' "$1" 2>/dev/null || printf 0; }
# Deixa <trabalho> como o mais recente no disco — pasta, plano E arquivo de
# rastro. Nada disso pode mover o destino de uma linha de evento.
o_toca() { # o_toca <dir> <trabalho>
  touch "$1/docs/sprintx/features/$2/sprint-01/tasks.md" "$1/docs/sprintx/features/$2/sprint-01" \
        "$1/docs/sprintx/features/$2" "$1/docs/eventos/$2.jsonl" 2>/dev/null
}
o_fx() { # o_fx <dir> <trabalho mais recente no disco>
  local d="$1"
  # `.git` vazio basta: `rastro_raiz` so testa `[ -e ]`, e nenhum dos tres
  # hooks desta secao chama git. `git init` custa segundos por fixture.
  rm -rf "$d"; mkdir -p "$d/src" "$d/.git"
  n_plano "$d/docs/sprintx/features/feature-a/sprint-01/tasks.md" feature-a 01 <<EOF
$(n_task T-01.01 em_andamento src/a.ts)
$(n_task T-01.02 pendente src/irma-a.ts)
EOF
  n_plano "$d/docs/sprintx/features/feature-b/sprint-01/tasks.md" feature-b 01 <<EOF
$(n_task T-01.01 em_andamento src/b.ts)
$(n_task T-01.02 pendente src/irma-b.ts)
EOF
  o_ev "$d" feature-a T-01.01 sessao-a
  o_ev "$d" feature-b T-01.01 sessao-b
  o_toca "$d" "$2"
}
o_hook() { # o_hook <raiz-hooks> <dir> <hook-relativo> <arquivo-relativo> <sessao>
  O_SAIDA="$(printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$2" "$2/$4" \
    | (cd "$2" && EXPX_SESSAO="$5" bash "$1/$3") 2>&1)"; O_RC=$?
}
# Chama uma funcao da biblioteca copiada (possivelmente mutada), com a
# identidade de sessao do caso.
o_chama() { # o_chama <raiz-hooks> <dir> <sessao> <funcao> [args...]
  local hr="$1" d="$2" ses="$3"; shift 3
  (cd "$d" && EXPX_SESSAO="$ses" bash -c '. "$0/comum/rastro.sh"; f="$1"; shift; "$f" "$@"' "$hr" "$@") 2>/dev/null
}
o_json_write() { # o_json_write <cwd> <file_path> — conteudo do stdin
  python3 -c "
import json, sys
print(json.dumps({'cwd': sys.argv[1], 'tool_name': 'Write', 'tool_input': {'file_path': sys.argv[2], 'content': sys.stdin.read()}}))
" "$1" "$2"
}

# ---------------------------------------------------------------- os casos
o_a() { # sessao em feature-a, feature-b mais recente: so feature-a.jsonl muda
  local d="$OF_DIR/a" b
  o_fx "$d" feature-b
  b="$(o_ck "$d/docs/eventos/feature-b.jsonl")"
  o_hook "$1" "$d" sprintx/escopo-da-task.sh src/irma-a.ts sessao-a
  [ "$O_RC" -eq 2 ] || return 1
  grep -q '"trabalho_id":"feature-a".*"detalhe":"arquivo_de_task_irma"' "$d/docs/eventos/feature-a.jsonl" || return 1
  [ "$(o_linhas "$d/docs/eventos/feature-a.jsonl")" -eq 2 ] || return 1
  [ "$(o_ck "$d/docs/eventos/feature-b.jsonl")" = "$b" ] || return 1
  [ "$(o_linhas "$d/docs/eventos/sem-trabalho.jsonl")" -eq 0 ]
}
o_b() { # mtimes invertidos: resultado identico
  local d="$OF_DIR/b" b
  o_fx "$d" feature-a
  b="$(o_ck "$d/docs/eventos/feature-b.jsonl")"
  o_hook "$1" "$d" sprintx/escopo-da-task.sh src/irma-a.ts sessao-a
  [ "$O_RC" -eq 2 ] && [ "$(o_linhas "$d/docs/eventos/feature-a.jsonl")" -eq 2 ] \
    && [ "$(o_ck "$d/docs/eventos/feature-b.jsonl")" = "$b" ]
}
o_c() { # uma TERCEIRA feature, mais recente que as duas: resultado identico
  local d="$OF_DIR/c" b c
  o_fx "$d" feature-b
  n_plano "$d/docs/sprintx/features/feature-c/sprint-01/tasks.md" feature-c 01 <<EOF
$(n_task T-01.01 em_andamento src/c.ts)
EOF
  o_ev "$d" feature-c T-01.01 sessao-c
  o_toca "$d" feature-c
  b="$(o_ck "$d/docs/eventos/feature-b.jsonl")"; c="$(o_ck "$d/docs/eventos/feature-c.jsonl")"
  o_hook "$1" "$d" sprintx/escopo-da-task.sh src/irma-a.ts sessao-a
  [ "$O_RC" -eq 2 ] && [ "$(o_linhas "$d/docs/eventos/feature-a.jsonl")" -eq 2 ] \
    && [ "$(o_ck "$d/docs/eventos/feature-b.jsonl")" = "$b" ] \
    && [ "$(o_ck "$d/docs/eventos/feature-c.jsonl")" = "$c" ]
}
o_d() { # paralelismo: sessao A -> arquivo A, sessao B -> arquivo B, sem cruzamento
  local d="$OF_DIR/d"
  o_fx "$d" feature-b
  o_hook "$1" "$d" sprintx/escopo-da-task.sh src/irma-a.ts sessao-a; [ "$O_RC" -eq 2 ] || return 1
  o_hook "$1" "$d" sprintx/escopo-da-task.sh src/irma-b.ts sessao-b; [ "$O_RC" -eq 2 ] || return 1
  [ "$(o_linhas "$d/docs/eventos/feature-a.jsonl")" -eq 2 ] \
    && [ "$(o_linhas "$d/docs/eventos/feature-b.jsonl")" -eq 2 ] \
    && [ "$(grep -c '"trabalho_id":"feature-b"' "$d/docs/eventos/feature-a.jsonl")" -eq 0 ] \
    && [ "$(grep -c '"trabalho_id":"feature-a"' "$d/docs/eventos/feature-b.jsonl")" -eq 0 ] \
    && [ "$(o_linhas "$d/docs/eventos/sem-trabalho.jsonl")" -eq 0 ]
}
o_e() { # trabalho explicito x trabalho provado pela sessao: nao grava em A nem em B
  local d="$OF_DIR/e" a b
  o_fx "$d" feature-b
  a="$(o_ck "$d/docs/eventos/feature-a.jsonl")"; b="$(o_ck "$d/docs/eventos/feature-b.jsonl")"
  o_chama "$1" "$d" sessao-a rastro_grava_trabalho "$d" feature-b regra_violada hook aviso "evento cruzado" "[]"
  [ "$(o_ck "$d/docs/eventos/feature-a.jsonl")" = "$a" ] \
    && [ "$(o_ck "$d/docs/eventos/feature-b.jsonl")" = "$b" ] \
    && [ "$(grep -c 'contexto_de_trabalho_divergente' "$d/docs/eventos/sem-trabalho.jsonl")" -eq 1 ]
}
o_f() { # retomada: gravar nao teleporta a sessao para outro trabalho
  local d="$OF_DIR/f" antes depois esperado
  o_fx "$d" feature-b
  esperado="$(printf 'feature-a\tT-01.01\tok')"
  antes="$(o_chama "$1" "$d" sessao-a rastro_reivindicacoes_da_sessao "$d" sessao-a)"
  [ "$antes" = "$esperado" ] || return 1
  o_hook "$1" "$d" sprintx/escopo-da-task.sh src/irma-a.ts sessao-a; [ "$O_RC" -eq 2 ] || return 1
  o_chama "$1" "$d" sessao-a rastro_grava_trabalho "$d" - arquivo_alterado hook ok Write "[]"
  o_chama "$1" "$d" sessao-a rastro_grava_trabalho "$d" feature-b regra_violada hook aviso "tentativa cruzada" "[]"
  depois="$(o_chama "$1" "$d" sessao-a rastro_reivindicacoes_da_sessao "$d" sessao-a)"
  [ "$depois" = "$esperado" ] \
    && [ "$(o_chama "$1" "$d" sessao-a rastro_trabalho_da_sessao "$d")" = feature-a ] \
    && [ "$(o_linhas "$d/docs/eventos/feature-a.jsonl")" -eq 3 ]
}
o_g() { # sessao sem reivindicacao: sem-trabalho, e nenhuma feature e tocada
  local d="$OF_DIR/g" a b
  o_fx "$d" feature-b
  a="$(o_ck "$d/docs/eventos/feature-a.jsonl")"; b="$(o_ck "$d/docs/eventos/feature-b.jsonl")"
  o_chama "$1" "$d" sessao-x rastro_grava "$d" regra_violada hook aviso "sem trabalho" "[]"
  [ "$(o_ck "$d/docs/eventos/feature-a.jsonl")" = "$a" ] \
    && [ "$(o_ck "$d/docs/eventos/feature-b.jsonl")" = "$b" ] \
    && [ "$(grep -c '"trabalho_id":"sem-trabalho"' "$d/docs/eventos/sem-trabalho.jsonl")" -eq 1 ]
}
o_h() { # trabalho deterministico pelo CAMINHO (sem-placeholder-no-plano)
  local d="$OF_DIR/h" a alvo
  o_fx "$d" feature-a                       # feature-a e a mais recente no disco
  alvo="$d/docs/sprintx/features/feature-b/00-PLANEJAMENTO.md"
  printf -- '---\nkind: planejamento\ntrabalho_id: feature-b\n---\nobjetivo: {{marcador}}\n' > "$alvo"
  a="$(o_ck "$d/docs/eventos/feature-a.jsonl")"
  o_hook "$1" "$d" sprintx/sem-placeholder-no-plano.sh \
    docs/sprintx/features/feature-b/00-PLANEJAMENTO.md sessao-x
  [ "$(grep -c '"trabalho_id":"feature-b".*placeholder' "$d/docs/eventos/feature-b.jsonl")" -eq 1 ] \
    && [ "$(o_ck "$d/docs/eventos/feature-a.jsonl")" = "$a" ] \
    && [ "$(o_linhas "$d/docs/eventos/sem-trabalho.jsonl")" -eq 0 ]
}
o_i() { # trabalho deterministico pelo FRONTMATTER (task-reivindicada)
  local d="$OF_DIR/i" a j
  o_fx "$d" feature-a                       # feature-a e a mais recente no disco
  n_plano "$OF_DIR/i-novo.md" feature-b 01 <<EOF
$(n_task T-01.01 em_andamento src/b.ts)
EOF
  j="$(o_json_write "$d" "$d/docs/sprintx/features/feature-b/sprint-01/tasks.md" < "$OF_DIR/i-novo.md")"
  a="$(o_ck "$d/docs/eventos/feature-a.jsonl")"
  O_SAIDA="$(printf '%s' "$j" | (cd "$d" && EXPX_SESSAO=sessao-x bash "$1/sprintx/task-reivindicada.sh") 2>&1)"; O_RC=$?
  # T-01.01 de feature-b esta aberta por sessao-b: sessao-x e avisada, e o
  # evento vai para o rastro de feature-b — o trabalho_id do proprio tasks.md.
  [ "$O_RC" -eq 0 ] && printf '%s' "$O_SAIDA" | grep -qF 'sessao-b' \
    && [ "$(grep -c '"trabalho_id":"feature-b".*regra_violada' "$d/docs/eventos/feature-b.jsonl")" -eq 1 ] \
    && [ "$(o_ck "$d/docs/eventos/feature-a.jsonl")" = "$a" ]
}

o_j() { # arvore-limpa: o escopo comparado e o do trabalho da SESSAO
  local d="$OF_DIR/j" b
  o_fx "$d" feature-b
  # este hook roda `git status`, entao aqui a fixture precisa de repo de verdade
  rm -rf "$d/.git"; git init -q --template= -b main "$d" >/dev/null 2>&1
  : > "$d/src/a.ts"                 # declarado na T-01.01 de feature-a
  : > "$d/src/fora-do-plano.ts"     # de task nenhuma
  b="$(o_ck "$d/docs/eventos/feature-b.jsonl")"
  O_SAIDA="$(printf '{"cwd":"%s","tool_input":{"command":"npm test"}}' "$d" \
    | (cd "$d" && EXPX_SESSAO=sessao-a bash "$1/sprintx/arvore-limpa-antes-da-suite.sh") 2>&1)"; O_RC=$?
  [ "$O_RC" -eq 0 ] || return 1
  printf '%s' "$O_SAIDA" | grep -qF 'src/fora-do-plano.ts' || return 1
  printf '%s' "$O_SAIDA" | grep -qF ' src/a.ts' && return 1
  grep -q '"trabalho_id":"feature-a".*"detalhe":"arvore contaminada"' "$d/docs/eventos/feature-a.jsonl" || return 1
  [ "$(o_ck "$d/docs/eventos/feature-b.jsonl")" = "$b" ] || return 1
  # sessao sem reivindicacao: nao ha escopo a comparar, e o hook sai calado
  O_SAIDA="$(printf '{"cwd":"%s","tool_input":{"command":"npm test"}}' "$d" \
    | (cd "$d" && EXPX_SESSAO=sessao-x bash "$1/sprintx/arvore-limpa-antes-da-suite.sh") 2>&1)"; O_RC=$?
  [ "$O_RC" -eq 0 ] && [ -z "$O_SAIDA" ]
}

OHR="$H"
bash -n "$H/comum/rastro.sh"; afirma "o0-rastro-sintaxe" $? "bash -n"
for par in \
  o_a:oa-destino-e-o-trabalho-da-sessao-nao-o-mtime \
  o_b:ob-mtimes-invertidos-resultado-identico \
  o_c:oc-terceira-feature-recente-nao-muda-nada \
  o_d:od-duas-sessoes-dois-arquivos-sem-cruzamento \
  o_e:oe-divergencia-nao-grava-em-a-nem-em-b \
  o_f:of-retomada-evento-posterior-nao-teleporta \
  o_g:og-sem-reivindicacao-vai-para-sem-trabalho \
  o_h:oh-trabalho-pelo-caminho-do-plano \
  o_i:oi-trabalho-pelo-frontmatter-do-tasks-md \
  o_j:oj-arvore-limpa-compara-o-escopo-do-trabalho-da-sessao; do
  "${par%%:*}" "$OHR"; afirma "${par#*:}" $? "${par%%:*}"
done

# Nenhuma producao pode voltar a escolher destino por mtime.
[ "$(grep -rln 'rastro_trabalho_id' "$H/comum" "$H/sprintx" "$SK/scripts" 2>/dev/null | wc -l)" -eq 0 ]
afirma "o-sem-rastro-trabalho-id" $? "a funcao que escolhia por mtime nao existe mais"
[ "$(grep -rln -- '-nt ' "$H/comum" "$H/sprintx" 2>/dev/null | wc -l)" -eq 0 ]
afirma "o-sem-comparacao-de-mtime-nos-hooks" $? "nenhum hook compara data de arquivo"

# ------------------------------------------------------------------ mutantes
OM="$OF_DIR/mut"
o_copia() { # o_copia <nome> — devolve a raiz de hooks copiada
  local d="$OM/$1"; rm -rf "$d"; mkdir -p "$d/sprintx" "$d/comum"
  cp "$H/comum/rastro.sh" "$d/comum/rastro.sh"
  cp "$H/sprintx/escopo-da-task.sh" "$H/sprintx/task-reivindicada.sh" \
     "$H/sprintx/sem-placeholder-no-plano.sh" "$H/sprintx/arvore-limpa-antes-da-suite.sh" "$d/sprintx/"
  printf '%s' "$d"
}
o_muta() { muta_lit "$1" "$1.m" "$2" "$3" && mv "$1.m" "$1"; }
o_mutante() { # o_mutante <nome> <rc geracao> <raiz> <caso que TEM de matar>...
  local nome="$1" rc="$2" s="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do "$c" "$s" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]
  afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
CASOS_O="o_a o_b o_c o_d o_e o_f o_g o_h o_i o_j"

OMC="$(o_copia controle)"; vivoso=""
for c in $CASOS_O; do "$c" "$OMC" || vivoso="$vivoso$c "; done
[ -z "$vivoso" ]; afirma "om-controle-copia-intacta-sobrevive" $? "${vivoso:-nenhum caso reprova a copia sem mutacao}"

L_SESSAO='  local _raiz="$2" _ses="${3:-}" _tid _coer'
L_MTIME='  local _raiz="$2" _ses="${3:-}" _tid _coer; local f mais_novo=""; for f in "$_raiz"/docs/sprintx/features/*/; do [ -d "$f" ] || continue; if [ -z "$mais_novo" ] || [ "$f" -nt "$mais_novo" ]; then mais_novo="$f"; fi; done; mais_novo="${mais_novo%/}"; printf -v "$1" "%s" "${mais_novo##*/}"; return 0'
OMUT="$(o_copia m1)"; o_muta "$OM/m1/comum/rastro.sh" "$L_SESSAO" "$L_MTIME"
# O escopo-da-task entrega ao rastro.sh o trabalho que ja resolveu (DS-157): o helper decide o
# destino dos outros hooks (o_i, o_j); o mesmo defeito no escopo e o om-mutante-6.
o_mutante "om-mutante-1-destino-por-mtime" $? "$OMUT" o_i o_j

OMUT="$(o_copia m2)"; o_muta "$OM/m2/comum/rastro.sh" \
  '  local raiz="$1" pedido="$2" evento="$3"' '  local raiz="$1" pedido="-" evento="$3"'
o_mutante "om-mutante-2-ignora-trabalho-explicito" $? "$OMUT" o_h o_i

OMUT="$(o_copia m3)"; o_muta "$OM/m3/comum/rastro.sh" '      tid="$pedido"' \
  '      tid="$(cd "$dir" 2>/dev/null && ls -t *.jsonl 2>/dev/null | head -1)"; tid="${tid%.jsonl}"; [ -n "$tid" ] || tid="$pedido"'
o_mutante "om-mutante-3-grava-na-feature-mais-recente" $? "$OMUT" o_a o_i

OMUT="$(o_copia m4)"; o_muta "$OM/m4/comum/rastro.sh" \
  '    elif [ -n "$sessao_tid" ] && [ "$sessao_tid" != "$pedido" ]; then' '    elif false; then'
o_mutante "om-mutante-4-aceita-trabalho-divergente" $? "$OMUT" o_e

# Sem o filtro de sessao no helper, as duas sessoes passam a enxergar as duas
# reivindicacoes — e e assim que dois trabalhos cruzariam o mesmo arquivo.
OMUT="$(o_copia m5)"; o_muta "$OM/m5/comum/rastro.sh" \
  'if (_rv_dono[k] == "" || _rv_dono[k] != ses) continue' 'if (_rv_dono[k] == "") continue'
o_mutante "om-mutante-5-sessoes-cruzam-arquivos" $? "$OMUT" o_a o_d o_f o_j

# O trabalho que o escopo-da-task entrega ao rastro.sh volta a sair do mtime.
OMUT="$(o_copia m6)"; o_muta "$OM/m6/sprintx/escopo-da-task.sh" '  RASTRO_TRABALHO_DA_SESSAO="$TRABALHO"' \
  '  RASTRO_TRABALHO_DA_SESSAO="$(ls -t "$RAIZ/docs/sprintx/features" 2>/dev/null | head -1)"'
o_mutante "om-mutante-6-escopo-destino-por-mtime" $? "$OMUT" o_a o_d

DSF5="$SK/DECISOES-DA-SKILL.md"
[ "$(grep -c '^| DS-155 |' "$DSF5")" -eq 1 ] && tem "$DSF5" 'rastro_grava_trabalho' \
  && tem "$SK/references/08-rastro.md" 'Em qual arquivo o evento entra' \
  && tem "$SK/references/08-rastro.md" 'nunca seleciona o destino'
afirma "o-ds155-registrada" $? "DECISOES-DA-SKILL.md e 08-rastro.md"

rm -rf "$OF_DIR"

echo "== P. TDD-first: o replanejamento preserva o trabalho parcial seguro da task bloqueada (P0.2-C7-B S3-A) =="
# O diagnostico B1.5, literal: a task escreve o proprio teste (declarado nela), prova o
# vermelho, tenta o arquivo X que o plano da so a uma irma, o escopo barra, B-NN
# defeito_de_plano — e o replanejamento recusava a fronteira porque o teste estava sujo,
# contra a ordem TDD da propria F6. Agora o teste da task bloqueada e preservado (path, estado
# e hash no 00-PLANEJAMENTO.md commitado), o plano ganha X, a F5 aprova, a task volta, X e
# implementado, verde, e o E1 leva o teste. Cada caso e <planejamento.sh> <dir>, como na K,
# para os mutantes rodarem exatamente a mesma bateria.
P="$(mktemp -d)"
PH="$H/sprintx/escopo-da-task.sh"
PT=tests/menu/perfil.test.sh; PX=src/menu/visibilidade.sh; PI=src/menu/perfil.sh
p_plano() { # p_plano <dir> <status T-04.03> <altera T-04.03> [altera T-04.04] [cria T-04.03] [cria T-04.04]
  k_sprint "$(kf "$1")/sprint-04/tasks.md" 04 plano \
    "T-04.01|concluida|src/menu/organizacao.sh||" \
    "T-04.02|concluida|$PX, tests/menu/visibilidade.test.sh||T-04.01" \
    "T-04.03|$2|${5-$PI, $PT}|$3|T-04.02" \
    "T-04.04|pendente|${6:-src/menu/rotas.sh}|${4:-}|T-04.03" \
    "T-04.05|pendente|src/menu/icones.sh||"
}
# p_fx <dir> — o piloto aprovado, em F6: T-04.01 e T-04.02 concluidas com o produto
# commitado pelo E1 (X = src/menu/visibilidade.sh e so da T-04.02); T-04.03 em andamento pela
# sessao teste@eu. Arvore limpa.
p_fx() {
  local d="$1"
  k_fx "$d" 0 3 buildx 1 || return 1
  mkdir -p "$d/src/menu" "$d/tests/menu"
  printf 'organizacao() { :; }\n' > "$d/src/menu/organizacao.sh"
  printf 'visivel() { printf "menu-%%s" "$1"; }\n' > "$d/$PX"
  printf '#!/bin/sh\n. ./%s && [ "$(visivel admin)" = menu-admin ]\n' "$PX" > "$d/tests/menu/visibilidade.test.sh"
  p_plano "$d" em_andamento ""
  git -C "$d" add -A && git -C "$d" commit -q -m "feat(menu): T-04.01 e T-04.02 (E1)" || return 1
  grava_evento_menu "$d" task_iniciada T-04.03 teste@eu
  [ -z "$(git -C "$d" status --porcelain)" ]
}
P_RC=0; P_SAIDA=""; P_H0=""
p_hook() { P_SAIDA="$(roda_hook_menu "$1" "$PH" "$2" teste@eu)"; P_RC=$?; }
p_parc() { tr -d '\r' | awk 'NR==1{next} $0=="---"{exit} /^parciais_replanejamento_f6:/{if ($0 ~ /\[\]/) {print "[]"; exit} b=1; next} b&&/^[^ ]/{exit} b&&/^  - path: /{p=$3; gsub(/"/,"",p)} b&&/^    task: /{t=$2} b&&/^    estado: /{e=$2} b&&/^    hash: /{print p "|" t "|" e "|" $2}'; }
p_hash() { git -C "$1" hash-object --no-filters -- "$2" 2>/dev/null; }
# p_ate_bloqueio <script> <dir> — passos 1 a 6 do B1.5: teste permitido, vermelho, X barrado, B-01, bloqueada.
p_ate_bloqueio() {
  local s="$1" d="$2"
  p_hook "$d" "$PT"; [ "$P_RC" -eq 0 ] || return 1
  printf '#!/bin/sh\n. ./%s && . ./%s && [ "$(perfil_visivel admin)" = menu-admin-completo ]\n' "$PX" "$PI" > "$d/$PT"
  (cd "$d" && sh "$PT") >/dev/null 2>&1 && return 1
  p_hook "$d" "$PX"
  [ "$P_RC" -eq 2 ] && printf '%s' "$P_SAIDA" | grep -qF arquivo_de_task_irma || return 1
  kbl "$s" "$d" registrar menu T-04.03 defeito_de_plano "arquivo_de_task_irma: $PX e da T-04.02" "acrescentar $PX a T-04.03" >/dev/null || return 1
  p_plano "$d" bloqueada ""
  grava_evento_menu "$d" task_bloqueada T-04.03 teste@eu
  P_H0="$(p_hash "$d" "$PT")"; [ -n "$P_H0" ]
}
# p_so_metodo <dir> <base> — entre <base> e HEAD, nenhum commit tecnico parcial: so checkpoints da pasta da feature.
p_so_metodo() {
  local c p
  for c in $(git -C "$1" rev-list "$2..HEAD"); do
    for p in $(git -C "$1" show --name-only --format= "$c"); do case "$p" in docs/sprintx/features/menu/*) ;; *) return 1 ;; esac; done
  done
}
# P1. O cenario inteiro, sem decisao humana no meio.
p_central() {
  local s="$1" d="$2" f out base e1; f="$(kf "$d")"
  p_ate_bloqueio "$s" "$d" || return 1
  base="$(git -C "$d" rev-parse HEAD)"
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = iniciado ] && [ "$(kv "$out" estado)" = replanejar_execucao ] \
    && [ "$(kv "$out" parciais_replanejamento_f6)" = "$PT" ] \
    && [ "$(git -C "$d" show "HEAD:docs/sprintx/features/menu/00-PLANEJAMENTO.md" | p_parc)" = "$PT|T-04.03|novo|$P_H0" ] \
    && [ "$(p_hash "$d" "$PT")" = "$P_H0" ] && [ "$(git -C "$d" status --porcelain -- "$PT")" = "?? $PT" ] || return 1
  # Retomada com a arvore intacta: mesma rodada, nada consumido.
  out="$(kpl "$s" "$d" replanejar-execucao menu)" || return 1
  [ "$(kv "$out" replanejamento)" = retomada ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 1 ] || return 1
  # F3: X entra em `altera` da T-04.03; o parcial continua so dela.
  p_plano "$d" bloqueada "$PX"
  kpl "$s" "$d" avanca menu f3 >/dev/null && kpl "$s" "$d" avanca menu f4 >/dev/null || return 1
  k_aud "$d" 2 SIM; out="$(kpl "$s" "$d" avanca menu f5)" || return 1
  [ "$(kv "$out" estado)" = aprovado ] && [ "$(kv "$out" proxima)" = F6 ] && [ "$(kbloq "$d" B-01)" = "defeito_de_plano|resolvido" ] \
    && [ "$(kst "$d" T-04.03)" = pendente ] && [ "$(p_parc < "$f/00-PLANEJAMENTO.md")" = "[]" ] \
    && [ "$(p_hash "$d" "$PT")" = "$P_H0" ] && p_so_metodo "$d" "$base" && [ -z "$(git -C "$d" stash list)" ] || return 1
  # A F6 retoma a T-04.03: X agora e dela. Implementa; verde.
  p_plano "$d" em_andamento "$PX"; grava_evento_menu "$d" task_iniciada T-04.03 teste@eu
  p_hook "$d" "$PX"; [ "$P_RC" -eq 0 ] || return 1
  p_hook "$d" "$PI"; [ "$P_RC" -eq 0 ] || return 1
  printf 'perfil_visivel() { printf "%%s-completo" "$(visivel "$1")"; }\n' > "$d/$PI"
  printf 'visivel() { printf "menu-%%s" "$1"; }\nvisivel_de() { visivel "$1"; }\n' > "$d/$PX"
  (cd "$d" && sh "$PT") >/dev/null 2>&1 || return 1
  # E1, como a mergex o faz: os arquivos de produto declarados da task mais a pasta da feature.
  p_plano "$d" concluida "$PX"; grava_evento_menu "$d" task_concluida T-04.03 teste@eu
  git -C "$d" add -- "$PI" "$PT" "$PX" docs/sprintx/features/menu && git -C "$d" commit -q -m "feat(menu): T-04.03 (E1)" || return 1
  e1="$(git -C "$d" show --name-only --format= HEAD | grep -v '^docs/sprintx/features/menu/' | LC_ALL=C sort | tr '\n' ' ')"
  [ "$e1" = "$PI $PX $PT " ] && [ "$(git -C "$d" rev-parse "HEAD:$PT")" = "$P_H0" ] \
    && [ -z "$(git -C "$d" status --porcelain)" ] && [ "$(kv "$(kpl "$s" "$d" fase menu)" fase)" = F6 ] \
    && (cd "$d" && sh "$PT") >/dev/null 2>&1
}
# p_recusa <script> <dir> <item esperado em nao_preservaveis> [teste-preservavel:1|0] — codigo 2,
# fronteira_insegura, nada gravado, nada limpo; por padrao o teste da propria task nao aparece
# entre os nao preservaveis (a recusa e pelo OUTRO path).
p_recusa() {
  local s="$1" d="$2" f ck h st out rc np; f="$(kf "$d")"
  ck="$(cksum < "$f/00-PLANEJAMENTO.md")"; h="$(git -C "$d" rev-parse HEAD)"; st="$(git -C "$d" status --porcelain | cksum)"
  out="$(kpl "$s" "$d" replanejar-execucao menu)"; rc=$?
  np=",$(kv "$out" nao_preservaveis),"
  [ "$rc" -eq 2 ] && [ "$(kv "$out" motivo)" = fronteira_insegura ] \
    && case "$np" in *",$3,"*) true ;; *) false ;; esac && { [ "${4:-1}" = 0 ] || case "$np" in *",$PT("*) false ;; *) true ;; esac; } \
    && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] \
    && [ "$(git -C "$d" status --porcelain | cksum)" = "$st" ] && [ -z "$(git -C "$d" stash list)" ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = aprovado ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" replanejamentos_f6)" = 0 ] \
    && [ "$(p_hash "$d" "$PT")" = "$P_H0" ]
}
# P2. Dirty da propria task + dirty de irma.
p_irma() {
  p_ate_bloqueio "$1" "$2" || return 1
  printf 'rotas() { :; }\n' > "$2/src/menu/rotas.sh"
  p_recusa "$1" "$2" "src/menu/rotas.sh(task_irma:T-04.04)"
}
# P3. Dirty da propria task + stage (outro arquivo da propria task no indice).
p_stage() {
  p_ate_bloqueio "$1" "$2" || return 1
  printf 'perfil_visivel() { :; }\n' > "$2/$PI"; git -C "$2" add -- "$PI"
  p_recusa "$1" "$2" "$PI(staged)"
}
# P4. O mesmo teste declarado na corrente E numa irma: nao se atribui a uma task so.
p_compartilhado() {
  p_ate_bloqueio "$1" "$2" || return 1
  p_plano "$2" bloqueada "" "$PT"
  p_recusa "$1" "$2" "$PT(compartilhado:T-04.03,T-04.04)" 0 && [ "$(kst "$2" T-04.03)" = bloqueada ]
}
# P5. Arquivo de task concluida sujo na arvore.
p_concluida() {
  p_ate_bloqueio "$1" "$2" || return 1
  printf 'organizacao() { echo mexido; }\n' > "$2/src/menu/organizacao.sh"
  p_recusa "$1" "$2" "src/menu/organizacao.sh(task_concluida:T-04.01)"
}
# P6. O hash muda durante o replanejamento: todo portao para (codigo 2), nada gravado; com o
# conteudo de volta, byte a byte, a rodada segue — a prova e o hash, nao a data.
p_hash_muda() {
  local s="$1" d="$2" f ck h out rc orig; f="$(kf "$d")"
  p_ate_bloqueio "$s" "$d" || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  p_plano "$d" bloqueada "$PX"; orig="$(cat "$d/$PT")"
  printf '# ajuste feito durante o replanejamento\n' >> "$d/$PT"
  ck="$(cksum < "$f/00-PLANEJAMENTO.md")"; h="$(git -C "$d" rev-parse HEAD)"
  out="$(kpl "$s" "$d" avanca menu f3)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" motivo)" = parcial_divergente ] && [ "$(kv "$out" trabalho_parcial)" = divergente ] \
    && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] \
    && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = replanejar_execucao ] || return 1
  out="$(kpl "$s" "$d" replanejar-execucao menu)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" motivo)" = parcial_divergente ] || return 1
  out="$(kpl "$s" "$d" fase menu)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" fase)" = PARAR ] && [ "$(kv "$out" trabalho_parcial)" = divergente ] \
    && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(git -C "$d" rev-parse HEAD)" = "$h" ] || return 1
  printf '%s\n' "$orig" > "$d/$PT"; [ "$(p_hash "$d" "$PT")" = "$P_H0" ] || return 1
  kpl "$s" "$d" avanca menu f3 >/dev/null && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = aguardando_f4 ]
}
# P7. O plano novo tira o parcial da task bloqueada: move para irma, remove de todas, torna
# ambiguo, atribui a concluida. Codigo 4 em cada portao, nada registrado; o plano certo passa.
p_ownership() {
  local s="$1" d="$2" f ck rc m out; f="$(kf "$d")"
  p_ate_bloqueio "$s" "$d" || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  ck="$(cksum < "$f/00-PLANEJAMENTO.md")"
  for m in irma nenhuma ambiguo; do
    case "$m" in
      irma) p_plano "$d" bloqueada "$PX" "" "$PI" "src/menu/rotas.sh, $PT" ;;
      nenhuma) p_plano "$d" bloqueada "$PX" "" "$PI" ;;
      ambiguo) p_plano "$d" bloqueada "$PX" "$PT" ;;
    esac
    out="$(kpl "$s" "$d" avanca menu f3)"; rc=$?
    [ "$rc" -eq 4 ] && [ "$(printf '%s' "$out" | grep -cF 'trabalho parcial preservado')" -ge 1 ] \
      && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = replanejar_execucao ] || return 1
  done
  # Concluida: a T-04.02 congelada ganharia o teste — o congelamento ja barra (codigo 4).
  k_sprint "$f/sprint-04/tasks.md" 04 plano "T-04.01|concluida|src/menu/organizacao.sh||" \
    "T-04.02|concluida|$PX, tests/menu/visibilidade.test.sh, $PT||T-04.01" "T-04.03|bloqueada|$PI|$PX|T-04.02" \
    "T-04.04|pendente|src/menu/rotas.sh||T-04.03" "T-04.05|pendente|src/menu/icones.sh||"
  kpl "$s" "$d" avanca menu f3 >/dev/null; rc=$?
  [ "$rc" -eq 4 ] && [ "$(cksum < "$f/00-PLANEJAMENTO.md")" = "$ck" ] || return 1
  p_plano "$d" bloqueada "$PX"
  kpl "$s" "$d" avanca menu f3 >/dev/null && [ "$(fmv "$f/00-PLANEJAMENTO.md" estado)" = aguardando_f4 ]
}
# P8. Worktree perdida: um clone da branch tem o estado versionado, e nao o conteudo parcial.
# Nada e reconstruido: fase, retomada e portao param com `parcial_perdido`, sem gravar nada.
p_perdido() {
  local s="$1" d="$2" c out rc h ck
  p_ate_bloqueio "$s" "$d" || return 1
  kpl "$s" "$d" replanejar-execucao menu >/dev/null || return 1
  c="$(mktemp -d "$P/clone.XXXXXX")"; rm -rf "$c"
  git clone -q -c core.autocrlf=false -b feature/menu "$d" "$c" || return 1
  rm -rf "$d"; [ ! -e "$d" ] && [ ! -e "$c/$PT" ] || return 1
  h="$(git -C "$c" rev-parse HEAD)"; ck="$(cksum < "$(kf "$c")/00-PLANEJAMENTO.md")"
  [ "$(p_parc < "$(kf "$c")/00-PLANEJAMENTO.md")" = "$PT|T-04.03|novo|$P_H0" ] || return 1
  out="$(kpl "$s" "$c" fase menu)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" fase)" = PARAR ] && [ "$(kv "$out" trabalho_parcial)" = perdido ] || return 1
  out="$(kpl "$s" "$c" replanejar-execucao menu)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" motivo)" = parcial_perdido ] && [ "$(kv "$out" proxima)" = PARAR ] || return 1
  p_plano "$c" bloqueada "$PX"
  out="$(kpl "$s" "$c" avanca menu f3)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" motivo)" = parcial_perdido ] || return 1
  out="$(kpl "$s" "$c" fase menu)"; rc=$?
  [ "$rc" -eq 2 ] && [ "$(kv "$out" trabalho_parcial)" = perdido ] \
    && [ "$(git -C "$c" rev-parse HEAD)" = "$h" ] && [ "$(cksum < "$(kf "$c")/00-PLANEJAMENTO.md")" = "$ck" ] \
    && [ ! -e "$c/$PT" ] && [ -z "$(git -C "$c" status --porcelain -- src tests)" ] \
    && [ "$(fmv "$(kf "$c")/00-PLANEJAMENTO.md" estado)" = replanejar_execucao ]
}
# P9. O mesmo ciclo numa worktree vinculada (`.git` e arquivo), com a principal em outra branch.
p_central_worktree() {
  local s="$1" d="$2" w="$2--wt"
  git -C "$d" switch -q main 2>/dev/null || git -C "$d" checkout -q main || return 1
  git -C "$d" worktree add -q "$w" feature/menu || return 1
  [ -f "$w/.git" ] || return 1
  grava_evento_menu "$w" task_iniciada T-04.03 teste@eu
  p_central "$s" "$w"
}
FXPP="$P/fx"; p_fx "$FXPP"; afirma "p0-fixture-tdd-first" $? "F6 aprovada, T-04.02 concluida com X commitado, T-04.03 em andamento pela sessao"
pcopia() { local d; d="$(mktemp -d "$P/c.XXXXXX")"; rm -rf "$d"; cp -R "$FXPP" "$d"; printf '%s' "$d"; }
roda_p() { "$1" "$2" "$(pcopia)"; }
for par in p_central:p1-tdd-first-teste-preservado-ate-o-e1 p_irma:p2-propria-mais-irma-para \
  p_stage:p3-propria-mais-stage-para p_compartilhado:p4-compartilhado-current-irma-nao-preservavel \
  p_concluida:p5-task-concluida-suja-para p_hash_muda:p6-hash-muda-no-replanejamento-para \
  p_ownership:p7-plano-novo-tira-o-parcial-da-task-para p_perdido:p8-worktree-perdida-fail-closed \
  p_central_worktree:p9-tdd-first-em-worktree-vinculada; do
  roda_p "${par%%:*}" "$PL"; afirma "${par#*:}" $? "${par%%:*}"
done

# Contrato nos documentos e a lista de segredo sem deriva.
SCHP="$SK/references/00-schema.md"
tem "$SCHP" '`parciais_replanejamento_f6`' && tem "$SCHP" 'parcial_perdido' && tem "$EXEC" 'parciais_replanejamento_f6' \
  && tem "$EXEC" '`motivo=parcial_perdido`' && tem "$SK/references/03-plano.md" 'trabalho parcial preservado' \
  && tem "$SK/assets/TEMPLATE-PLANEJAMENTO.md" 'parciais_replanejamento_f6: []' \
  && [ "$(grep -c '^| DS-156 |' "$SK/DECISOES-DA-SKILL.md")" -eq 1 ]
afirma "p10-contrato-do-trabalho-parcial" $? "schema, 06-execucao, 03-plano, template e DS-156"
seg_hook="$(sed -n "/^PADROES_SEGREDO=\\|^done <<'PADROES'\$/,/^PADROES\$/p" "$H/comum/segredo.sh" | grep '|' | sed 's/^[^|]*|//')"
seg_pl="$(sed -n "/^SEGREDO_PADROES='/,/'\$/p" "$PL" | sed "s/^SEGREDO_PADROES='//; s/'\$//")"
[ -n "$seg_pl" ] && [ "$seg_hook" = "$seg_pl" ]
afirma "p11-segredo-mesma-lista-do-hook" $? "planejamento.sh e comum/segredo.sh"

# Mutantes do S3-A, em copia da skill (como na K). Cada um morre pelo caso designado; o
# controle, copia sem mutacao, sobrevive a todos.
MP="$P/mut"
copia_skill_p() { mkdir -p "$MP/$1/scripts/lib" "$MP/$1/assets"; cp "$SK/assets/TEMPLATE-PLANEJAMENTO.md" "$SK/assets/TEMPLATE-BLOQUEIOS.md" "$MP/$1/assets/"; cp "$BL" "$SK/scripts/caminho-git.sh" "$MP/$1/scripts/"; cp "$SK/scripts/lib/trava-autorizacao-f6.sh" "$MP/$1/scripts/lib/"; printf '%s/%s/scripts/planejamento.sh' "$MP" "$1"; }
mutante_p() { # mutante_p <nome> <rc da geracao> <script> <caso que TEM de matar>...
  local nome="$1" rc="$2" s="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do roda_p "$c" "$s" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]; afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
CTLP="$(copia_skill_p controle)"; cp "$PL" "$CTLP"; vivosp=""
for c in p_central p_irma p_stage p_compartilhado p_concluida p_hash_muda p_ownership p_perdido; do roda_p "$c" "$CTLP" || vivosp="$vivosp$c "; done
[ -z "$vivosp" ]; afirma "pm-controle-copia-intacta-sobrevive" $? "${vivosp:-nenhum caso designado reprova a copia sem mutacao}"
M="$(copia_skill_p a)"; muta_lit "$PL" "$M" '    cand="$cand$p$TAB$tasks$TAB$e$TAB$h' '    sujos="$sujos $p(sujo)"; continue; cand="$cand$p$TAB$tasks$TAB$e$TAB$h'
mutante_p "pm-mutante-1-todo-dirty-da-corrente-rejeitado" $? "$M" p_central
M="$(copia_skill_p b)"; muta_lit "$PL" "$M" '          elif ! em_lista "$tasks" "$BLOQ_TASKS"; then veredito="task_irma:$tasks"' '          elif false; then veredito="task_irma:$tasks"'
mutante_p "pm-mutante-2-dirty-de-irma-preservado" $? "$M" p_irma
M="$(copia_skill_p c)"; muta_lit "$PL" "$M" '          elif [ "$n" -gt 1 ]; then veredito="compartilhado:$tasks"' '          elif [ "$n" -gt 1 ]; then tasks="${tasks%%,*}"'
mutante_p "pm-mutante-3-dirty-compartilhado-preservado" $? "$M" p_compartilhado
M="$(copia_skill_p d)"; muta_lit "$PL" "$M" '  [ "$R_TSV" = "$esperado" ] && return 0' \
  '  [ "$(printf '"'"'%s\n'"'"' "$R_TSV" | cut -f1,2)" = "$(printf '"'"'%s\n'"'"' "$esperado" | cut -f1,2)" ] && return 0'
mutante_p "pm-mutante-4-hash-nao-verificado" $? "$M" p_hash_muda
M="$(copia_skill_p e)"; muta_lit "$PL" "$M" '    [ -z "$P_PARC" ] || { D_PARC=perdido; D_DET=" $(printf '"'"'%s\n'"'"' "$P_PARC" | cut -f1 | tr '"'"'\n'"'"' '"'"' '"'"')"; }' '    :'
mutante_p "pm-mutante-5-worktree-perdida-segue-integra" $? "$M" p_perdido
M="$(copia_skill_p f)"; muta_lit "$PL" "$M" '  [ -z "$ruins" ] && return 0' '  return 0'
mutante_p "pm-mutante-6-plano-novo-move-o-parcial" $? "$M" p_ownership
M="$(copia_skill_p g)"; muta_lit "$PL" "$M" '  f6_herda; W6_BLQ=""; W6_CONG=""; W6_ASS=null; W6_PARC=""' \
  '  printf '"'"'%s\n'"'"' "$P_PARC" | while IFS="$TAB" read -r p t e h; do [ -n "$p" ] && rm -f "$RAIZ/$p"; done; f6_herda; W6_BLQ=""; W6_CONG=""; W6_ASS=null; W6_PARC=""'
mutante_p "pm-mutante-7-e1-sem-o-teste-preservado" $? "$M" p_central

rm -rf "$P"

echo "== Q. custo dos hooks criticos: poucos processos, timeout como margem (P0.2-C7-B S3-B) =="
# O runner cancela o hook que estoura o timeout e deixa a ferramenta EXECUTAR: timeout e
# falha aberta. A garantia primaria e o hook nao criar processo (no Git Bash cada um custa de
# 0,5 a 2 s); o timeout maior dos tres criticos e so margem. Os processos externos sao
# contados por shims no PATH — o mesmo em Linux e no Git Bash; builtin do bash nao passa por eles.
Q="$(mktemp -d)"; mkdir -p "$Q/shim"
for c in awk jq grep sed cut tr wc sort head tail find cat date mkdir dirname basename xargs ps mv git ls uniq env python3 od; do
  r="$(command -v "$c" 2>/dev/null)"; case "$r" in */*) ;; *) continue ;; esac
  printf '#!/bin/sh\nprintf "%%s\\n" "%s" >> "$Q_LOG"\nexec "%s" "$@"\n' "$c" "$r" > "$Q/shim/$c"; chmod +x "$Q/shim/$c"
done
q_fx() { # q_fx <dir> — 4 sprints x 6 tasks no formato do template (frontmatter + prosa), rastro com a reivindicacao
  local d="$1" F s t st; rm -rf "$d"; mkdir -p "$d/.git" "$d/docs/eventos"; F="$d/docs/sprintx/features/menu"
  for s in 01 02 03 04; do
    mkdir -p "$F/sprint-$s"
    {
      printf -- '---\nexpx_schema: 1\nkind: tasks\ntrabalho_id: menu\nsprint_id: sprint-%s\ntasks:\n' "$s"
      for t in 01 02 03 04 05 06; do
        st=concluida; [ "$s" = 04 ] && st=pendente; [ "$s$t" = 0403 ] && st=em_andamento
        printf '  - id: T-%s.%s\n    status: %s\n    arquivos:\n      cria: [src/m%s/t%s.ts, tests/m%s/t%s.test.ts]\n      altera: []\n' "$s" "$t" "$st" "$s" "$t" "$s" "$t"
      done
      printf -- '---\n\n'
      for t in 01 02 03 04 05 06; do printf -- '```yaml\nid: T-%s.%s\narquivos:\n  cria: [src/m%s/t%s.ts]\n  altera: []\n```\n\n' "$s" "$t" "$s" "$t"; done
    } > "$F/sprint-$s/tasks.md"
  done
  printf '{"trabalho_id":"menu","evento":"task_iniciada","task":"T-04.03","sessao":"q@1"}\n' > "$d/docs/eventos/menu.jsonl"
  printf '{"trabalho_id":"historica","evento":"task_iniciada","task":"T-04.03","sessao":"q@9"}\n' > "$d/docs/eventos/historica.jsonl"
}
Q_N=0; Q_RC=0
q_roda() { # q_roda <raiz-hooks> <hook> <payload> — processos externos em Q_N, rc em Q_RC
  local d="$Q/r"; q_fx "$d"; : > "$Q/log"
  printf '%s' "$(printf '%s' "$3" | sed "s#@D@#$d#g")" | (cd "$d" && PATH="$Q/shim:$PATH" Q_LOG="$Q/log" EXPX_SESSAO=q@1 CLAUDECODE=1 bash "$1/$2") >/dev/null 2>&1
  Q_RC=$?; Q_N="$(grep -c '' "$Q/log")"
}
qw() { printf '{"cwd":"@D@","tool_name":"Write","tool_input":{"file_path":"@D@/%s","content":"%s"}}' "$1" "${2:-x = 1}"; }
qb() { printf '{"cwd":"@D@","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }
Q_AWS="AKIA""ABCDEFGHIJKLMNOP"; Q_GF="git push"" --force origin main"
# Sem `mapfile -d` (bash < 4.4, macOS) a leitura do payload custa um `cat`: um processo a mais permitido.
Q_FOLGA=0; { [ "${BASH_VERSINFO[0]}" -gt 4 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 4 ]; }; } || Q_FOLGA=1
# q_orcamento <raiz-hooks> <rotulo-git-perigoso> — cada cenario decide certo (rc) e cabe no orcamento:
# caminho comum ate 2 processos externos, bloqueio ate 3. Imprime o que custou cada um.
Q_CUSTO=""
q_orcamento() {
  local H2="$1" GP="$2" c nome hook pl rc max ruim=""
  Q_CUSTO=""
  while IFS='|' read -r nome hook rc max pl; do
    [ -n "$nome" ] || continue
    q_roda "$H2" "$hook" "$(eval "printf '%s' \"$pl\"")"
    Q_CUSTO="$Q_CUSTO $nome=$Q_N"
    [ "$Q_RC" -eq "$rc" ] && [ "$Q_N" -le $((max + Q_FOLGA)) ] || ruim="$ruim $nome(rc=$Q_RC,proc=$Q_N)"
  done <<EOF
escopo-corrente|sprintx/escopo-da-task.sh|0|2|\$(qw src/m04/t03.ts)
escopo-irma|sprintx/escopo-da-task.sh|2|3|\$(qw src/m04/t04.ts)
escopo-concluida|sprintx/escopo-da-task.sh|2|3|\$(qw src/m01/t01.ts)
escopo-fora|sprintx/escopo-da-task.sh|0|3|\$(qw src/outro.ts)
segredo-limpo|comum/segredo.sh|0|2|\$(qw src/a.ts)
segredo-achado|comum/segredo.sh|2|3|\$(qw src/a.ts \$Q_AWS)
git-inocuo|$GP|0|2|\$(qb 'git status')
git-perigoso|$GP|2|3|\$(qb "\$Q_GF")
EOF
  [ -z "$ruim" ] || { Q_CUSTO="$Q_CUSTO — FORA:$ruim"; return 1; }
}
# q_timeouts <settings.json> <plugin.ts> — os tres criticos com 30 s, todo o resto com 10 s, nos dois harnesses.
q_timeouts() {
  tr -d '\r' < "$1" | awk '
    /"command":/ { c = $0; next }
    /"timeout":/ { t = $0; gsub(/[^0-9]/, "", t); crit = (c ~ /escopo-da-task\.sh|segredo\.sh|git-perigoso\.sh/)
                   if (crit) { nc++; if (t != 30) ruim = 1 } else if (t != 10) ruim = 1 }
    END { exit (ruim || nc != 3) }' \
  && [ "$(tr -d '\r' < "$2" | grep -cF 'timeout: CRITICOS.has(caminhoRelativo) ? 30_000 : 10_000')" -eq 1 ] \
  && [ "$(tr -d '\r' < "$2" | grep -c 'const CRITICOS = new Set(\[.*"sprintx/escopo-da-task.sh".*"comum/segredo.sh".*git-perigoso.sh"\])')" -eq 1 ]
}
# q_criticos <raiz-hooks> <settings> <plugin> <git-perigoso> — a solucao inteira: timeout como margem E custo baixo.
q_criticos() { q_timeouts "$2" "$3" && q_orcamento "$1" "$4"; }
QGP=sprintx/git-perigoso.sh
q_orcamento "$H" "$QGP"; afirma "q1-orcamento-de-processos-dos-criticos" $? "externos por execucao:$Q_CUSTO"
q_timeouts "$RAIZ_SRC/.claude/settings.json" "$RAIZ_SRC/.opencode/plugin/sprintx.ts"; afirma "q2-timeout-30s-so-nos-tres-criticos" $? "settings.json e plugin do OpenCode"
tem "$SKILLMD" 'timeout do runner é falha aberta' && tem "$SKILLMD" 'primeira barreira' && tem "$SKILLMD" 'E1 da `mergex`' \
  && [ "$(grep -c '^| DS-157 |' "$SK/DECISOES-DA-SKILL.md")" -eq 1 ]
afirma "q3-contrato-fail-open-e-backstop" $? "SKILL.md e DS-157"

# L-prosa. A prosa repete o bloco ```yaml de cada task; a task corrente e a ULTIMA do
# frontmatter; o arquivo e so de uma irma. Tem de bloquear (lia-se a prosa como da ultima task).
l_prosa() {
  l_fixture
  c2_abre 04 "$C2OC/sprint-04/tasks.md"
  c2_tarefa "$C2OC/sprint-04/tasks.md" T-04.01 pendente "src/menu/irma.ts" ""
  c2_tarefa "$C2OC/sprint-04/tasks.md" T-04.03 em_andamento "" "src/ui/cabecalho-topo.tsx"
  c2_fecha "$C2OC/sprint-04/tasks.md"
  printf '\n```yaml\nid: T-04.01\narquivos:\n  cria: [src/menu/irma.ts]\n  altera: []\n```\n\n```yaml\nid: T-04.03\narquivos:\n  cria: []\n  altera: [src/ui/cabecalho-topo.tsx]\n```\n' >> "$C2OC/sprint-04/tasks.md"
  c2_hook "$1" "src/menu/irma.ts" teste@eu
  [ $? -eq 2 ] && printf '%s' "$C2_SAIDA" | grep -qF "arquivo_de_task_irma" && printf '%s' "$C2_SAIDA" | grep -qF "(T-04.01)"
}
C2="$(mktemp -d)"
git -C "$C2" init -q -b main; C2OC="$C2/docs/sprintx/features/c2-escopo-irma"
mkdir -p "$C2OC/sprint-03" "$C2OC/sprint-04"; C2RASTRO="$C2/docs/eventos/c2-escopo-irma.jsonl"; mkdir -p "$(dirname "$C2RASTRO")"
l_prosa "$H/sprintx/escopo-da-task.sh"; afirma "q4-prosa-nao-declara-ownership" $? "corrente e a ultima task do frontmatter; o arquivo da irma na prosa continua da irma"

# Mutantes do S3-B. Copia da arvore de hooks (sprintx/ + comum/), da configuracao e do plugin.
QM="$Q/mut"
q_copia() { # q_copia <nome> — devolve a raiz de hooks copiada, com settings.json e plugin ao lado
  local d="$QM/$1"; rm -rf "$d"; mkdir -p "$d/hooks" "$d/plugin"
  cp -R "$H/sprintx" "$H/comum" "$d/hooks/"; cp "$RAIZ_SRC/.claude/settings.json" "$d/settings.json"; cp "$RAIZ_SRC/.opencode/plugin/sprintx.ts" "$d/plugin/sprintx.ts"
  printf '%s' "$d"
}
q_mutante() { # q_mutante <nome> <rc geracao> <condicao que TEM de falhar...>
  local nome="$1" rc="$2"; shift 2
  if [ "$rc" -eq 0 ] && ! "$@"; then afirma "$nome" 0 "morto por: $1"; else afirma "$nome" 1 "SOBREVIVEU a: $1 (rc geracao=$rc)"; fi
}
q_controle() { # a copia sem mutacao passa em tudo que os mutantes precisam reprovar
  local c
  q_criticos "$1/hooks" "$1/settings.json" "$1/plugin/sprintx.ts" "$QGP" && l_prosa "$1/hooks/sprintx/escopo-da-task.sh" || return 1
  for c in l_a l_b l_c l_d l_e l_j; do "$c" "$1/hooks/sprintx/escopo-da-task.sh" || return 1; done
}
QC="$(q_copia controle)"; q_controle "$QC"
afirma "qm-controle-copia-intacta-sobrevive" $? "orcamento, timeouts, prosa e C2 na copia sem mutacao"
# 1. Volta ao desenho fork-heavy: find + grep por tasks.md + pipelines, como antes da DS-157.
QMU="$(q_copia m1)"; muta_lit "$QMU/hooks/sprintx/escopo-da-task.sh" "$QMU/e.m" 'rastro_raiz_em RAIZ "$CWD"' \
  'RAIZ="$(rastro_raiz "$CWD")"; for f in $(find "$RAIZ/docs" -maxdepth 5 -name tasks.md -type f 2>/dev/null); do grep -q "status: em_andamento" "$f" 2>/dev/null; done; N_X="$(printf "%s\n" x | awk NF | wc -l | tr -d " ")"' \
  && mv "$QMU/e.m" "$QMU/hooks/sprintx/escopo-da-task.sh"
q_mutante "qm-mutante-1-volta-ao-fork-heavy" $? q_orcamento "$QMU/hooks" "$QGP"
# 2. O timeout critico volta a 10 s.
QMU="$(q_copia m2)"; awk '/escopo-da-task\.sh/ { e = 1 } e && /"timeout": 30/ { sub(/30/, "10"); e = 0 } { print }' "$QMU/settings.json" > "$QMU/s.m" && ! cmp -s "$QMU/s.m" "$QMU/settings.json" && mv "$QMU/s.m" "$QMU/settings.json"
q_mutante "qm-mutante-2-timeout-critico-volta-a-10" $? q_timeouts "$QMU/settings.json" "$QMU/plugin/sprintx.ts"
# 3. Timeout aumentado SEM a otimizacao: o hook fork-heavy com 30 s nao e solucao suficiente.
QMU="$(q_copia m3)"; muta_lit "$QMU/hooks/comum/rastro.sh" "$QMU/r.m" 'rastro_le_entrada_em() {' \
  'rastro_le_entrada_em() { local _i; for _i in 1 2 3 4 5 6; do date >/dev/null; done; printf -v "$1" "%s" "$(cat)"; return 0' \
  && mv "$QMU/r.m" "$QMU/hooks/comum/rastro.sh"
q_mutante "qm-mutante-3-timeout-maior-sem-otimizacao" $? q_criticos "$QMU/hooks" "$QMU/settings.json" "$QMU/plugin/sprintx.ts" "$QGP"
# 4. O atalho do caminho comum muda a semantica C2: arquivo so de irma passa como da corrente.
QMU="$(q_copia m4)"; muta_lit "$QMU/hooks/sprintx/escopo-da-task.sh" "$QMU/e.m" '    case "$DECL" in corrente|vazio) exit 0 ;; esac' \
  '    case "$DECL" in corrente|vazio|irma) exit 0 ;; esac' && mv "$QMU/e.m" "$QMU/hooks/sprintx/escopo-da-task.sh"
q_mutante "qm-mutante-4-escopo-muda-semantica-irma-corrente" $? l_c "$QMU/hooks/sprintx/escopo-da-task.sh"
# 5. A prosa volta a declarar ownership (a leitura de antes).
QMU="$(q_copia m5)"; muta_lit "$QMU/hooks/sprintx/escopo-da-task.sh" "$QMU/e.m" '  FNR > 1 && FM && $0 == "---" { FORA = 1; AT = "" }' \
  '  FNR > 1 && FM && $0 == "---" { FORA = 0 }' && mv "$QMU/e.m" "$QMU/hooks/sprintx/escopo-da-task.sh"
q_mutante "qm-mutante-5-prosa-volta-a-declarar-ownership" $? l_prosa "$QMU/hooks/sprintx/escopo-da-task.sh"
rm -rf "$Q" "$C2"

echo "== R. git-perigoso com o namespace da skill, em qualquer ordem de instalacao (P0.2-C7-B S3-C) =="
# A mergex publica um git-perigoso proprio em comum/, com regras dela. O da sprintx mora em
# sprintx/, com o id sprintx/git-perigoso no .expx/hooks.json: nenhum sobrescreve o outro, e o
# modo de um nao liga nem desliga o outro. Cada caso recebe a raiz de uma arvore de fonte da
# sprintx (a do repositorio, ou a copia de um mutante).
R="$(mktemp -d)"
r_fonte() { # r_fonte <nome> — copia o que o install.sh publica
  local d="$R/fonte-$1"; rm -rf "$d"; mkdir -p "$d"
  cp -R "$RAIZ_SRC/.claude" "$RAIZ_SRC/.opencode" "$RAIZ_SRC/.expx" "$RAIZ_SRC/install.sh" "$d/"
  printf '%s' "$d"
}
# R1. O arquivo, o registro nos dois harnesses e o id do modo carregam o namespace.
r_caminhos() {
  local f="$1"
  [ -f "$f/.claude/hooks/sprintx/git-perigoso.sh" ] && [ ! -e "$f/.claude/hooks/comum/git-perigoso.sh" ] \
    && [ "$(grep -cF '/.claude/hooks/sprintx/git-perigoso.sh"' "$f/.claude/settings.json")" -eq 1 ] \
    && [ "$(grep -cF 'comum/git-perigoso' "$f/.claude/settings.json")" -eq 0 ] \
    && [ "$(grep -cF '"sprintx/git-perigoso.sh"' "$f/.opencode/plugin/sprintx.ts")" -eq 2 ] \
    && [ "$(grep -cF 'comum/git-perigoso' "$f/.opencode/plugin/sprintx.ts")" -eq 0 ] \
    && [ "$(grep -cF '"sprintx/git-perigoso": {' "$f/.expx/hooks.json")" -eq 1 ] \
    && [ "$(grep -cF '"git-perigoso":' "$f/.expx/hooks.json")" -eq 0 ] \
    && [ "$(grep -cF 'sprintx/git-perigoso' "$f/.claude/hooks/doctor.sh")" -ge 1 ]
}
# R2. O modo sai do id com namespace: o git-perigoso de outra skill desligado nao desliga este.
r_modo() {
  local f="$1" d="$R/modo" pl cmd="git push"" --force origin main"
  rm -rf "$d"; mkdir -p "$d/.git" "$d/.expx"
  pl="$(printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$d" "$cmd")"
  r_hook() { printf '%s' "$pl" | (cd "$d" && EXPX_SESSAO=r@1 bash "$f/.claude/hooks/sprintx/git-perigoso.sh") >/dev/null 2>&1; }
  printf '{"hooks":{"git-perigoso":{"modo":"desligado"}}}' > "$d/.expx/hooks.json"; r_hook; [ $? -eq 2 ] || return 1
  printf '{"hooks":{"sprintx/git-perigoso":{"modo":"desligado"}}}' > "$d/.expx/hooks.json"; r_hook; [ $? -eq 0 ] || return 1
  printf '{\n  "hooks": {\n    "sprintx/git-perigoso": { "modo": "bloqueio" }\n  }\n}\n' > "$d/.expx/hooks.json"; r_hook; [ $? -eq 2 ] || return 1
  rm -f "$d/.expx/hooks.json"; r_hook; [ $? -eq 2 ]
}
# R3. Instalacao nas duas ordens, e o legado: o hook da mergex nunca e apagado nem sobrescrito,
# o da sprintx sempre chega, e o comum/git-perigoso.sh antigo DA SPRINTX sai.
r_mergex() { # r_mergex <projeto> — uma instalacao sintetica da mergex (copia de arvore, como ela faz)
  mkdir -p "$1/.claude/hooks/comum" "$1/.claude/hooks/mergex"
  printf '#!/usr/bin/env bash\n# git-perigoso da mergex: outras regras\nexit 0\n' > "$1/.claude/hooks/comum/git-perigoso.sh"
  printf '#!/usr/bin/env bash\n# base da mergex\n' > "$1/.claude/hooks/comum/base.sh"
  printf '#!/usr/bin/env bash\n# commit por task\n' > "$1/.claude/hooks/mergex/commit-por-task.sh"
}
r_ck_mergex() { cat "$1/.claude/hooks/comum/git-perigoso.sh" "$1/.claude/hooks/comum/base.sh" "$1/.claude/hooks/mergex/commit-por-task.sh" 2>/dev/null | cksum; }
r_instala() {
  local f="$1" p ck
  # mergex primeiro, sprintx depois
  p="$R/p1"; rm -rf "$p"; mkdir -p "$p"; r_mergex "$p"; ck="$(r_ck_mergex "$p")"
  bash "$f/install.sh" --claude "$p" >/dev/null 2>&1 || return 1
  [ "$(r_ck_mergex "$p")" = "$ck" ] && cmp -s "$p/.claude/hooks/sprintx/git-perigoso.sh" "$f/.claude/hooks/sprintx/git-perigoso.sh" || return 1
  # sprintx primeiro, mergex depois
  p="$R/p2"; rm -rf "$p"; mkdir -p "$p"
  bash "$f/install.sh" --claude "$p" >/dev/null 2>&1 || return 1
  r_mergex "$p"
  cmp -s "$p/.claude/hooks/sprintx/git-perigoso.sh" "$f/.claude/hooks/sprintx/git-perigoso.sh" \
    && [ "$(grep -cF '/.claude/hooks/sprintx/git-perigoso.sh"' "$p/.claude/settings.json")" -eq 1 ] || return 1
  # reinstalar a sprintx por cima das duas nao muda nada da mergex
  ck="$(r_ck_mergex "$p")"; bash "$f/install.sh" --claude "$p" >/dev/null 2>&1 || return 1
  [ "$(r_ck_mergex "$p")" = "$ck" ] || return 1
  # so-OpenCode num projeto em que a mergex ja criou .claude/hooks/: os da sprintx chegam
  p="$R/p3"; rm -rf "$p"; mkdir -p "$p"; r_mergex "$p"; ck="$(r_ck_mergex "$p")"
  bash "$f/install.sh" --opencode "$p" >/dev/null 2>&1 || return 1
  [ -f "$p/.claude/hooks/sprintx/git-perigoso.sh" ] && [ -f "$p/.claude/hooks/sprintx/escopo-da-task.sh" ] && [ "$(r_ck_mergex "$p")" = "$ck" ] || return 1
  # legado: o comum/git-perigoso.sh que a propria sprintx instalava sai; o resto fica
  p="$R/p4"; rm -rf "$p"; mkdir -p "$p/.claude/hooks/comum"
  printf '#!/usr/bin/env bash\nrastro_bloqueia "sprintx/git-perigoso: comando barrado — x"\n' > "$p/.claude/hooks/comum/git-perigoso.sh"
  bash "$f/install.sh" --claude "$p" >/dev/null 2>&1 || return 1
  [ ! -e "$p/.claude/hooks/comum/git-perigoso.sh" ] && [ -f "$p/.claude/hooks/sprintx/git-perigoso.sh" ]
}
RF="$(r_fonte repo)"
r_caminhos "$RF"; afirma "r1-git-perigoso-com-namespace" $? "sprintx/git-perigoso.sh e id sprintx/git-perigoso em settings, plugin, doctor e .expx/hooks.json"
r_modo "$RF"; afirma "r2-modo-pelo-id-com-namespace" $? "git-perigoso da mergex desligado nao desliga o da sprintx"
r_instala "$RF"; afirma "r3-instalacao-sem-ordem-e-sem-apagar-a-mergex" $? "mergex antes, depois, reinstalacao, so-OpenCode e legado"
tem "$SKILLMD" '`sprintx/git-perigoso`' && [ "$(grep -c '^| DS-158 |' "$SK/DECISOES-DA-SKILL.md")" -eq 1 ]
afirma "r4-contrato-do-namespace" $? "SKILL.md e DS-158"

# Mutantes do S3-C, em copia da fonte. O controle, copia sem mutacao, passa nos tres casos.
RC="$(r_fonte controle)"; r_caminhos "$RC" && r_modo "$RC" && r_instala "$RC"
afirma "rm-controle-copia-intacta-sobrevive" $? "caminhos, modo e instalacao na copia sem mutacao"
r_mutante() { # r_mutante <nome> <rc geracao> <fonte> <caso que TEM de matar>...
  local nome="$1" rc="$2" f="$3" c vivos=""; shift 3
  if [ "$rc" -eq 0 ]; then for c in "$@"; do "$c" "$f" && vivos="$vivos$c "; done; fi
  [ "$rc" -eq 0 ] && [ -z "$vivos" ]; afirma "$nome" $? "morto por: $* ${vivos:+— SOBREVIVEU a: $vivos}(rc geracao=$rc)"
}
# 1. O caminho volta ao comum/ compartilhado com a mergex.
RM="$(r_fonte m1)"
mv "$RM/.claude/hooks/sprintx/git-perigoso.sh" "$RM/.claude/hooks/comum/git-perigoso.sh" \
  && muta_lit "$RM/.claude/hooks/comum/git-perigoso.sh" "$RM/g.m" '. "$DIR/../comum/rastro.sh"' '. "$DIR/rastro.sh"' && mv "$RM/g.m" "$RM/.claude/hooks/comum/git-perigoso.sh" \
  && muta_lit "$RM/.claude/settings.json" "$RM/s.m" '/.claude/hooks/sprintx/git-perigoso.sh"' '/.claude/hooks/comum/git-perigoso.sh"' && mv "$RM/s.m" "$RM/.claude/settings.json" \
  && muta_lit "$RM/.opencode/plugin/sprintx.ts" "$RM/p.m" '"sprintx/git-perigoso.sh"' '"comum/git-perigoso.sh"' && mv "$RM/p.m" "$RM/.opencode/plugin/sprintx.ts"
r_mutante "rm-mutante-1-caminho-volta-ao-comum" $? "$RM" r_caminhos r_instala
# 2. O manifesto e o hook voltam ao id sem namespace.
RM="$(r_fonte m2)"
muta_lit "$RM/.claude/hooks/sprintx/git-perigoso.sh" "$RM/g.m" 'rastro_modo_em MODO "$RAIZ" sprintx/git-perigoso seguranca' 'rastro_modo_em MODO "$RAIZ" git-perigoso seguranca' \
  && mv "$RM/g.m" "$RM/.claude/hooks/sprintx/git-perigoso.sh" \
  && muta_lit "$RM/.expx/hooks.json" "$RM/h.m" '"sprintx/git-perigoso": {' '"git-perigoso": {' && mv "$RM/h.m" "$RM/.expx/hooks.json"
r_mutante "rm-mutante-2-manifesto-com-id-sem-namespace" $? "$RM" r_caminhos r_modo
rm -rf "$R"

echo "== S. paths do tool input no Windows: C:\\ e C:/ decidem igual (P0.2-C7-B S3-D) =="
# O Claude Code no Windows entrega `cwd` e `tool_input.file_path` como C:\dir\arq (payload
# real capturado no runner). `${ALVO#"$RAIZ"/}` so tira prefixo com `/`: o caminho ficava
# absoluto, nao casava com `arquivos` e o hook falhava ABERTO — a irma so avisava. A semantica
# tem de ser a mesma em POSIX, C:\, C:/, misto e drive em outra caixa. Fora de MSYS/Cygwin a
# normalizacao e no-op: la C:\ nao e caminho, e nada muda.
S_WIN=0; case "${OSTYPE:-}" in msys*|cygwin*) S_WIN=1 ;; esac
S_DIR="$(mktemp -d)"
s_fx() { # s_fx <dir> — T-01.01 corrente, T-01.02 irma, uma compartilhada, nomes com espaco
  local d="$1" p="$1/docs/sprintx/features/feat/sprint-01/tasks.md"
  rm -rf "$d"; mkdir -p "$d/.git" "$d/src" "$d/docs/eventos" "${p%/*}"
  printf -- '---\nexpx_schema: 1\nexpx_tool: sprintx\nkind: tasks\ntrabalho_id: feat\nsprint_id: sprint-01\ntasks:\n' > "$p"
  printf '  - id: T-01.01\n    status: em_andamento\n    arquivos:\n      cria: ["src/com espaco/novo.ts"]\n      altera: [src/a.ts, src/shared.ts]\n' >> "$p"
  printf '  - id: T-01.02\n    status: pendente\n    arquivos:\n      cria: ["src/irma espaco/y.ts"]\n      altera: [src/shared.ts, src/irma.ts]\n---\n' >> "$p"
  printf '{"trabalho_id":"feat","evento":"task_iniciada","task":"T-01.01","sessao":"s3d@1"}\n' > "$d/docs/eventos/feat.jsonl"
}
s_json() { # s_json <cwd> <file_path> — JSON como o runner manda (barra invertida escapada)
  printf '{"session_id":"x","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":"%s","old_string":"a","new_string":"b"}}' \
    "${1//\\/\\\\}" "${2//\\/\\\\}"
}
s_decide() { # s_decide <hook> <dir-posix> <cwd> <file_path> — "rc/irma|aviso|silencio|outro"
  local o r
  o="$(s_json "$3" "$4" | (cd "$2" && EXPX_SESSAO=s3d@1 bash "$1") 2>&1)"; r=$?
  case "$o" in
    *arquivo_de_task_irma*) o=irma ;; *"nao esta na lista"*) o=aviso ;; "") o=silencio ;; *) o=outro ;;
  esac
  printf '%s/%s' "$r" "$o"
}
# Os casos A..E e o que cada um TEM de decidir, em qualquer formato.
S_CASOS="A|src/a.ts|0/silencio
B|src/shared.ts|0/silencio
C|src/irma.ts|2/irma
D|src/outro.ts|0/aviso
E1|src/com espaco/novo.ts|0/silencio
E2|src/irma espaco/y.ts|2/irma"
S_FALHA=""
S_TODOS="posix win misto cwdwin-arqmisto caixa-do-drive"
s_formatos() { # s_formatos <hook> <dir-posix> <formatos> <casos> — falhas em S_FALHA
  local h="$1" d="$2" w="" m="" wl="" n r esp rw fn fc fa got
  S_FALHA=""
  s_fx "$d"
  if [ "$S_WIN" = 1 ]; then
    w="$(cygpath -w "$d")"; m="$(cygpath -m "$d")"
    # A caixa do drive troca entre sessoes do runner (f:\ e F:\): cwd numa, arquivo na outra.
    case "$w" in [A-Z]*) wl="$(printf '%s' "${w:0:1}" | tr A-Z a-z)${w:1}" ;; *) wl="$(printf '%s' "${w:0:1}" | tr a-z A-Z)${w:1}" ;; esac
  fi
  while IFS='|' read -r n r esp; do
    case " $4 " in *" $n "*) ;; *) continue ;; esac
    rw="${r//\//\\}"
    for fn in $3; do
      case "$fn" in
        posix) fc="$d"; fa="$d/$r" ;;
        win) fc="$w"; fa="$w\\$rw" ;;
        misto) fc="$m"; fa="$m/$r" ;;
        cwdwin-arqmisto) fc="$w"; fa="$m/$r" ;;
        caixa-do-drive) fc="$wl"; fa="$w\\$rw" ;;
      esac
      [ -n "$fc" ] || continue
      # A reivindicacao volta ao estado inicial: o hook anexa eventos ao rastro a cada decisao.
      printf '{"trabalho_id":"feat","evento":"task_iniciada","task":"T-01.01","sessao":"s3d@1"}\n' > "$d/docs/eventos/feat.jsonl"
      got="$(s_decide "$h" "$d" "$fc" "$fa")"
      [ "$got" = "$esp" ] || S_FALHA="$S_FALHA $n:$fn=$got(esperado $esp)"
    done
  done <<EOF
$S_CASOS
EOF
  [ -z "$S_FALHA" ]
}
# Os drives da maquina que a bancada alcanca: o do temporario com todos os formatos e, se
# diferente, o do checkout com os formatos que o runner entrega (C:\ e a caixa do drive trocada).
S_SHOOK="$H/sprintx/escopo-da-task.sh"
bash -n "$S_SHOOK"; afirma "s0-hook-sintaxe" $? "bash -n"
S_ROT=posix; S_FMT=posix; [ "$S_WIN" = 1 ] && { S_ROT="$(cygpath -m "$S_DIR" | cut -c1-2)"; S_FMT="$S_TODOS"; }
s_formatos "$S_SHOOK" "$S_DIR/fx c3d" "$S_TODOS" "A B C D E1 E2"
afirma "s1-mesma-decisao-em-todo-formato-$S_ROT" $? "A..E x $S_FMT${S_FALHA:+ — FORA:$S_FALHA}"
if [ "$S_WIN" = 1 ]; then
  S_REPO_PAI="$(cd "$RAIZ_SRC/.." && pwd)"; S_ROT2="$(cygpath -m "$S_REPO_PAI" | cut -c1-2)"
  if [ "$(printf '%s' "$S_ROT2" | tr a-z A-Z)" != "$(printf '%s' "$S_ROT" | tr a-z A-Z)" ] \
    && S_DIR2="$(mktemp -d -p "$S_REPO_PAI" .sx-s3d.XXXXXX 2>/dev/null)"; then
    s_formatos "$S_SHOOK" "$S_DIR2/fx c3d" "posix win caixa-do-drive" "A B C D E1 E2"
    afirma "s1-mesma-decisao-em-todo-formato-$S_ROT2" $? "A..E x posix win caixa-do-drive${S_FALHA:+ — FORA:$S_FALHA}"
  fi
fi

# O helper. No Windows: drive montado vira o que o `cygpath -u` devolve, sem chama-lo; drive fora
# da montagem vira X:/... canonico; POSIX fica intacto; relativo continua relativo. Fora do
# Windows: no-op, byte a byte.
s_cam() { # s_cam <ostype> <caminho> — o que rastro_caminho_em devolve
  OSTYPE="$1" bash -c '. "$0/comum/rastro.sh"; rastro_caminho_em v "$1"; printf "%s" "$v"' "$H" "$2"
}
S_RUIM=""
for c in 'C:\a b\c.ts' 'C:/a/c.ts' 'X:\y' '/c/a/b' 'src/a.ts' 'src\a.ts' '\\srv\share\x'; do
  [ "$(s_cam linux-gnu "$c")" = "$c" ] || S_RUIM="$S_RUIM linux:$c"
done
if [ "$S_WIN" = 1 ]; then
  for c in 'C:\a b\c.ts' 'c:\a\c.ts' 'C:/a/c.ts' 'F:\Projetos\x y\z.ts' 'C:\'; do
    [ "$(s_cam "$OSTYPE" "$c")" = "$(cygpath -u "$c")" ] || S_RUIM="$S_RUIM win:$c=$(s_cam "$OSTYPE" "$c")"
  done
  # Um drive sintetico, fora da montagem: a mesma forma canonica X:/..., venha em que caixa vier.
  S_SINT=""; for l in Q R S T U V W Y Z; do [ -e "$(cygpath -u "$l:/")" ] || { S_SINT="$l"; break; }; done
  S_SL="$(printf '%s' "$S_SINT" | tr A-Z a-z)"
  for c in "$S_SINT:\\nao existe\\z.ts" "$S_SL:/nao existe/z.ts"; do
    [ "$(s_cam "$OSTYPE" "$c")" = "$S_SINT:/nao existe/z.ts" ] || S_RUIM="$S_RUIM sint:$c=$(s_cam "$OSTYPE" "$c")"
  done
  [ "$(s_cam "$OSTYPE" '\\srv\share\x')" = //srv/share/x ] || S_RUIM="$S_RUIM unc"
  [ "$(s_cam "$OSTYPE" '/c/a/b')" = /c/a/b ] || S_RUIM="$S_RUIM posix-intacto"
  [ "$(s_cam "$OSTYPE" 'src/a.ts')" = src/a.ts ] && [ "$(s_cam "$OSTYPE" 'src\a.ts')" = src/a.ts ] || S_RUIM="$S_RUIM relativo"
  # Hook num drive sintetico: nada ali, nada a decidir — igual em C:\ e C:/, sem erro.
  [ "$(s_decide "$S_SHOOK" "$S_DIR" "$S_SINT:\\nao existe" "$S_SINT:\\nao existe\\src\\irma.ts")" = 0/silencio ] \
    && [ "$(s_decide "$S_SHOOK" "$S_DIR" "$S_SINT:/nao existe" "$S_SINT:/nao existe/src/irma.ts")" = 0/silencio ] \
    || S_RUIM="$S_RUIM drive-sintetico-$S_SINT"
fi
[ -z "$S_RUIM" ]; afirma "s2-helper-no-windows-e-no-op-fora" $? "drive montado = cygpath -u, sintetico X:/, UNC, relativo; byte a byte fora${S_RUIM:+ — FORA:$S_RUIM}"

# Custo (DS-157): o formato Windows nao pode custar processo a mais que o POSIX. Shims no PATH,
# como na secao Q, e o cygpath entra na conta.
S_SHIM="$S_DIR/shim"; mkdir -p "$S_SHIM"
for c in awk jq grep sed cut tr wc sort head tail find cat date mkdir dirname basename ps git cygpath python3; do
  r="$(command -v "$c" 2>/dev/null)"; case "$r" in */*) ;; *) continue ;; esac
  printf '#!/bin/sh\nprintf "%%s\\n" "%s" >> "$S_LOG"\nexec "%s" "$@"\n' "$c" "$r" > "$S_SHIM/$c"; chmod +x "$S_SHIM/$c"
done
s_custo() { # s_custo <hook> <dir> <cwd> <file_path> — processos externos
  s_fx "$2"; : > "$S_DIR/log"
  s_json "$3" "$4" | (cd "$2" && PATH="$S_SHIM:$PATH" S_LOG="$S_DIR/log" EXPX_SESSAO=s3d@1 bash "$1") >/dev/null 2>&1
  grep -c '' "$S_DIR/log"
}
S_CD="$S_DIR/custo"; s_fx "$S_CD"
S_CP="$(s_custo "$S_SHOOK" "$S_CD" "$S_CD" "$S_CD/src/a.ts")"; S_CPI="$(s_custo "$S_SHOOK" "$S_CD" "$S_CD" "$S_CD/src/irma.ts")"
S_CW="$S_CP"; S_CWI="$S_CPI"
if [ "$S_WIN" = 1 ]; then
  S_W="$(cygpath -w "$S_CD")"
  S_CW="$(s_custo "$S_SHOOK" "$S_CD" "$S_W" "$S_W\\src\\a.ts")"; S_CWI="$(s_custo "$S_SHOOK" "$S_CD" "$S_W" "$S_W\\src\\irma.ts")"
fi
[ "$S_CW" -le "$S_CP" ] && [ "$S_CWI" -le "$S_CPI" ] && [ "$S_CP" -le $((2 + Q_FOLGA)) ] && [ "$S_CPI" -le $((3 + Q_FOLGA)) ]
afirma "s3-formato-windows-nao-custa-processo" $? "corrente posix=$S_CP win=$S_CW; irma posix=$S_CPI win=$S_CWI"

# Mutantes, so onde o formato Windows existe: fora dele o caminho mutado nem roda.
if [ "$S_WIN" = 1 ]; then
  S_M="$S_DIR/mut"
  s_copia() { # s_copia <nome> — hook + helper copiados; devolve o hook
    rm -rf "$S_M/$1"; mkdir -p "$S_M/$1/sprintx" "$S_M/$1/comum"
    cp "$H/comum/rastro.sh" "$S_M/$1/comum/rastro.sh"; cp "$S_SHOOK" "$S_M/$1/sprintx/escopo-da-task.sh"
    printf '%s' "$S_M/$1/sprintx/escopo-da-task.sh"
  }
  S_MD="$S_DIR/fx c3d"; S_MF="win caixa-do-drive"
  SMC="$(s_copia controle)"; s_formatos "$SMC" "$S_MD" "$S_MF" "A C"
  afirma "sm-controle-copia-intacta-sobrevive" $? "${S_FALHA:-todos os formatos}"
  SMUT="$(s_copia m1)"; muta_lit "$SMUT" "$SMUT.m" 'rastro_caminho_em ALVO "$ALVO"' ':' && mv "$SMUT.m" "$SMUT"
  S_RC=$?; [ "$S_RC" -eq 0 ] && ! s_formatos "$SMUT" "$S_MD" "$S_MF" "A C"
  afirma "sm-mutante-1-file-path-sem-normalizar" $? "rc geracao=$S_RC"
  SMUT="$(s_copia m2)"; muta_lit "$S_M/m2/comum/rastro.sh" "$S_M/m2/r.m" '_d="${_m:${#_i}:1}"' ':' && mv "$S_M/m2/r.m" "$S_M/m2/comum/rastro.sh"
  S_RC=$?; [ "$S_RC" -eq 0 ] && ! s_formatos "$SMUT" "$S_MD" "$S_MF" "A C"
  afirma "sm-mutante-2-drive-sem-caixa-canonica" $? "rc geracao=$S_RC"
fi
rm -rf "$S_DIR" ${S_DIR2:+"$S_DIR2"}


echo "== T. todo caminho do payload passa pelo mesmo helper: C:\\, c:\\, C:/ e POSIX decidem igual (P0.2-C7-B S3-E) =="
# A S3-D corrigiu so o escopo-da-task. Os outros hooks que leem `cwd` ou `tool_input.file_path`
# tiravam a raiz com `/` e casavam `*/tasks.md` no caminho cru: com o payload real do Windows
# (C:\dir\arq, caixa do drive variavel) o segredo perdia a isencao do .env ignorado, os hooks
# de metodo ficavam mudos ou avisavam em falso, e o rastro gravava o caminho absoluto do
# Windows como identificador logico. Contrato: todo pathname do payload passa por
# rastro_caminho_em antes de qualquer uso, e nenhum hook normaliza por conta propria. A
# decisao (rc, aviso/bloqueio/silencio) e os eventos gravados (onde, qual, com que arquivos)
# tem de ser os mesmos em qualquer formato. Fora de MSYS/Cygwin so o formato POSIX existe.
T_WIN=0; case "${OSTYPE:-}" in msys*|cygwin*) T_WIN=1 ;; esac
T_DIR="$(mktemp -d)"
T_AWS="AKIA""ABCDEFGHIJKLMNOP"; T_GF="git push"" --force origin main"
T_FEAT="docs/sprintx/features/feat"
T_TASKS="$T_FEAT/sprint-01/tasks.md"
# O rastro de partida: T-01.01 e de outra sessao; T-01.02 e a desta (o trabalho corrente e feat).
T_BASE='{"trabalho_id":"feat","evento":"task_iniciada","task":"T-01.01","sessao":"outra@9"}
{"trabalho_id":"feat","evento":"task_iniciada","task":"T-01.02","sessao":"t3e@1"}'
t_fx() { # t_fx <dir> — repositorio git real (a arvore-limpa roda git status), nomes com espaco
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/src/com espaco" "$d/docs/eventos" "$d/$T_FEAT/sprint-01"
  git -C "$d" init -q -b main >/dev/null 2>&1
  printf '.env*\n' > "$d/.gitignore"
  printf '# Convencoes\n\nO teste mora ao lado do arquivo: `a.test.ts`.\n' > "$d/CONVENCOES.md"
  : > "$d/src/a.ts"; : > "$d/src/a.test.ts"; : > "$d/src/b.ts"
  : > "$d/src/com espaco/c.ts"; : > "$d/src/com espaco/c.test.ts"
  printf -- '---\nexpx_schema: 1\nkind: tasks\ntrabalho_id: feat\nsprint_id: sprint-01\ntasks:\n' > "$d/$T_TASKS"
  printf '  - id: T-01.01\n    status: em_andamento\n    arquivos:\n      cria: []\n      altera: [src/a.ts]\n' >> "$d/$T_TASKS"
  printf '  - id: T-01.02\n    status: em_andamento\n    arquivos:\n      cria: []\n      altera: [src/a.test.ts]\n---\n' >> "$d/$T_TASKS"
  printf '# Plano\n\nAinda com {{marcador}}.\n' > "$d/$T_FEAT/plano.md"
}
t_esc() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/\\n}"; printf '%s' "$s"; }
t_conteudo() { # t_conteudo <tipo>
  case "$1" in
    inocente) printf 'x = 1' ;;
    aws) printf 'chave = "%s"' "$T_AWS" ;;
    fecha-ruim) printf -- '---\ntrabalho_id: feat\ntasks:\n  - id: T-01.02\n    status: concluida\n    suite: nao_executada\n    teste_integracao:\n    teste_funcional:\n---\n' ;;
    fecha-ok) printf -- '---\ntrabalho_id: feat\ntasks:\n  - id: T-01.02\n    status: concluida\n    suite: verde\n    teste_integracao: chama a api\n    teste_funcional: dado x entao y\n---\n' ;;
    reivindica) printf -- '---\ntrabalho_id: feat\ntasks:\n  - id: T-01.01\n    status: em_andamento\n---\n' ;;
  esac
}
t_json() { # t_json <evento> <ferramenta> <cwd> <file_path> <conteudo> — como o runner manda
  local ti
  case "$2" in
    Bash) ti="{\"command\":\"$(t_esc "$5")\"}" ;;
    -) ti="" ;;
    *) ti="{\"file_path\":\"$(t_esc "$4")\",\"content\":\"$(t_esc "$5")\"}" ;;
  esac
  printf '{"session_id":"x","cwd":"%s","hook_event_name":"%s"' "$(t_esc "$3")" "$1"
  [ "$2" = - ] && { printf ',"agent_type":"qa"}'; return; }
  printf ',"tool_name":"%s","tool_input":%s,"tool_response":{}}' "$2" "$ti"
}
T_SAIDA=""
t_decide() { # t_decide <hook> <dir-posix> <sub> <evento> <ferramenta> <cwd> <file_path> <conteudo>
  # — "rc/classe/eventos": eventos novos em QUALQUER *.jsonl da fixture, como <arquivo>:<evento>:<arquivos>
  local o r cls ev="" f l e a
  rm -rf "$2/src/docs"; find "$2/docs/eventos" -name '*.jsonl' -exec rm -f {} + 2>/dev/null
  printf '%s\n' "$T_BASE" > "$2/docs/eventos/feat.jsonl"
  o="$(t_json "$4" "$5" "$6" "$7" "$8" | (cd "$2${3:+/$3}" && EXPX_SESSAO=t3e@1 CLAUDECODE=1 bash "$1") 2>&1)"; r=$?
  T_SAIDA="$o"
  case "$o" in
    "") cls=silencio ;;
    *sprintx/*) if [ "$r" -eq 2 ]; then cls=bloqueio; else cls=aviso; fi ;;
    *) cls=outro ;;
  esac
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    while IFS= read -r l; do
      case "$l" in *'"evento":"task_iniciada"'*|"") continue ;; esac
      e="${l#*\"evento\":\"}"; e="${e%%\"*}"
      a="${l#*\"arquivos\":}"; a="${a%%]*}]"
      ev="$ev ${f#"$2"/}:$e:$a"
    done < "$f"
  done <<EOF
$(find "$2" -name '*.jsonl' -path '*docs/eventos*' 2>/dev/null | sort)
EOF
  printf '%s/%s/%s' "$r" "$cls" "${ev# }"
}
# Os casos e o que cada um TEM de decidir. sub = subdiretorio do cwd (o processo roda la, como no
# runner). EF = docs/eventos/feat.jsonl, o rastro do trabalho corrente da sessao.
EF=docs/eventos/feat.jsonl
T_CASOS="seg-inocente|comum/segredo.sh||PreToolUse|Write|src/a.ts|inocente|0/silencio/
seg-aws|comum/segredo.sh||PreToolUse|Write|src/a.ts|aws|2/bloqueio/$EF:acao_bloqueada:[\"src/a.ts\"]
seg-aws-espaco|comum/segredo.sh||PreToolUse|Write|src/com espaco/c.ts|aws|2/bloqueio/$EF:acao_bloqueada:[\"src/com espaco/c.ts\"]
seg-env-ignorado|comum/segredo.sh||PreToolUse|Write|src/.env|aws|0/silencio/
seg-cwd-sub|comum/segredo.sh|src|PreToolUse|Write|src/a.ts|aws|2/bloqueio/$EF:acao_bloqueada:[\"src/a.ts\"]
tdd-com-teste|sprintx/tdd-teste-antes.sh||PostToolUse|Write|src/a.ts|inocente|0/silencio/
tdd-sem-teste|sprintx/tdd-teste-antes.sh||PostToolUse|Write|src/b.ts|inocente|0/aviso/$EF:regra_violada:[\"src/b.ts\"]
tdd-espaco-com-teste|sprintx/tdd-teste-antes.sh||PostToolUse|Write|src/com espaco/c.ts|inocente|0/silencio/
tdd-artefato-da-skill|sprintx/tdd-teste-antes.sh||PostToolUse|Write|$T_FEAT/plano.md|inocente|0/silencio/
verde-ruim|sprintx/task-so-fecha-verde.sh||PreToolUse|Write|$T_TASKS|fecha-ruim|0/aviso/$EF:regra_violada:[\"$T_TASKS\"]
verde-ok|sprintx/task-so-fecha-verde.sh||PreToolUse|Write|$T_TASKS|fecha-ok|0/silencio/
reivindicada|sprintx/task-reivindicada.sh||PreToolUse|Write|$T_TASKS|reivindica|0/aviso/$EF:regra_violada:[]
placeholder|sprintx/sem-placeholder-no-plano.sh||PostToolUse|Write|$T_FEAT/plano.md|inocente|0/aviso/$EF:regra_violada:[\"$T_FEAT/plano.md\"]
post-write|comum/rastro-post.sh||PostToolUse|Write|src/a.ts|inocente|0/silencio/$EF:arquivo_alterado:[\"src/a.ts\"]
post-espaco|comum/rastro-post.sh||PostToolUse|Write|src/com espaco/c.ts|inocente|0/silencio/$EF:arquivo_alterado:[\"src/com espaco/c.ts\"]
post-cwd-sub|comum/rastro-post.sh|src|PostToolUse|Write|src/a.ts|inocente|0/silencio/$EF:arquivo_alterado:[\"src/a.ts\"]
git-cwd-sub|sprintx/git-perigoso.sh|src|PreToolUse|Bash||git-forcado|2/bloqueio/$EF:acao_bloqueada:[]
arvore-cwd-sub|sprintx/arvore-limpa-antes-da-suite.sh|src|PreToolUse|Bash||npm test|0/aviso/$EF:regra_violada:[]
subagente-cwd-sub|comum/rastro-subagente.sh|src|SubagentStop|-|||0/silencio/$EF:agente_concluido:[]"
T_FALHA=""
T_TODOS="posix win minuscula misto caixa-do-drive"
# t_formatos <raiz-hooks> <dir-posix> <formatos> <casos> — falhas em T_FALHA
t_formatos() {
  local H2="$1" d="$2" w="" m="" wl="" n h sub ev fe r ct esp rw fn fc fa got cont sw
  T_FALHA=""
  [ -d "$d/.git" ] || t_fx "$d"
  if [ "$T_WIN" = 1 ]; then
    w="$(cygpath -w "$d")"; m="$(cygpath -m "$d")"
    case "$w" in [A-Z]*) wl="$(printf '%s' "${w:0:1}" | tr A-Z a-z)${w:1}" ;; *) wl="$(printf '%s' "${w:0:1}" | tr a-z A-Z)${w:1}" ;; esac
  fi
  while IFS='|' read -r n h sub ev fe r ct esp; do
    case " $4 " in *" $n "*|" todos ") ;; *) continue ;; esac
    case "$ct" in git-forcado) cont="$T_GF" ;; "npm test") cont="npm test" ;; *) cont="$(t_conteudo "$ct")" ;; esac
    rw="${r//\//\\}"; sw="${sub:+\\$sub}"
    for fn in $3; do
      fc=""
      case "$fn" in
        posix) fc="$d${sub:+/$sub}"; fa="$d/$r" ;;
        win) [ -n "$w" ] && fc="$w$sw"; fa="$w\\$rw" ;;
        minuscula) [ -n "$wl" ] && fc="$wl$sw"; fa="$wl\\$rw" ;;
        misto) [ -n "$m" ] && fc="$m${sub:+/$sub}"; fa="$m/$r" ;;
        caixa-do-drive) [ -n "$wl" ] && fc="$wl$sw"; fa="$w\\$rw" ;;
      esac
      [ -n "$fc" ] || continue
      [ -n "$r" ] || fa=""
      got="$(t_decide "$H2/$h" "$d" "$sub" "$ev" "$fe" "$fc" "$fa" "$cont")"
      [ "$got" = "$esp" ] || T_FALHA="$T_FALHA
    $n:$fn=$got (esperado $esp)"
    done
  done <<EOF
$T_CASOS
EOF
  [ -z "$T_FALHA" ]
}
T_FMT=posix; [ "$T_WIN" = 1 ] && T_FMT="$T_TODOS"
T_FX="$T_DIR/fx t 3e"
t_formatos "$H" "$T_FX" "$T_FMT" todos
afirma "t1-mesma-decisao-e-mesmo-rastro-em-todo-formato" $? "$(printf '%s\n' "$T_CASOS" | grep -c '') casos x $T_FMT${T_FALHA:+ — FORA:$T_FALHA}"

# Nenhum evento carrega caminho absoluto do Windows (nem C:\ nem C:/) como identificador.
T_ABS=""
if [ "$T_WIN" = 1 ]; then
  for c in post-write placeholder verde-ruim seg-aws tdd-sem-teste; do
    n="$(printf '%s\n' "$T_CASOS" | grep "^$c|")"; IFS='|' read -r _ h sub ev fe r ct _ <<EOF
$n
EOF
    w="$(cygpath -w "$T_FX")"
    t_decide "$H/$h" "$T_FX" "$sub" "$ev" "$fe" "$w" "$w\\${r//\//\\}" "$(t_conteudo "$ct")" >/dev/null
    grep -qE '[A-Za-z]:(\\\\|/)' "$T_FX/$EF" && T_ABS="$T_ABS $c"
  done
fi
[ -z "$T_ABS" ]; afirma "t2-rastro-sem-caminho-absoluto-do-windows" $? "arquivos relativos a raiz${T_ABS:+ — ABSOLUTO EM:$T_ABS}"

. "$H/testes/bancada-segredo-sem-git.sh"
t_semgit "$H"; afirma "t3-segredo-sem-git-casa-o-gitignore-como-o-git" $? "16 casos seg-semgit-*${T_FALHA:+ — FORA:$T_FALHA}"
. "$H/testes/bancada-segredo-limite.sh"
t_seglimite "$H" "$PL"; afirma "t3b-segredo-prefixo-de-chave-com-limite-a-esquerda" $? "hook e planejamento.sh${T_FALHA:+ — FORA:$T_FALHA}"

# Estrutural. A auditoria: estes sao os hooks que leem pathname do payload, e a variavel de cada
# um. Cada par passa por rastro_caminho_em ANTES de qualquer uso que nao seja a propria leitura
# ou o teste de vazio; nenhum hook fora da lista le `cwd`/`file_path`; e nenhum hook reimplementa
# a normalizacao (cygpath, troca de barra, letra de drive) — o helper e o contrato.
T_PARES="comum/segredo.sh:CWD comum/segredo.sh:ALVO comum/rastro-post.sh:CWD comum/rastro-post.sh:ALVO
comum/rastro-subagente.sh:CWD sprintx/escopo-da-task.sh:CWD sprintx/escopo-da-task.sh:ALVO
sprintx/git-perigoso.sh:CWD sprintx/arvore-limpa-antes-da-suite.sh:CWD
sprintx/sem-placeholder-no-plano.sh:CWD sprintx/sem-placeholder-no-plano.sh:ALVO
sprintx/task-so-fecha-verde.sh:CWD sprintx/task-so-fecha-verde.sh:ALVO
sprintx/task-reivindicada.sh:CWD sprintx/task-reivindicada.sh:ALVO
sprintx/tdd-teste-antes.sh:CWD sprintx/tdd-teste-antes.sh:ALVO"
# t_normaliza_antes <hook> <VAR> — a linha `rastro_caminho_em VAR "$VAR"` existe e toda linha
# anterior que toca VAR e leitura (atribuicao, rastro_json_campo_em VAR) ou teste de vazio.
t_normaliza_antes() {
  awk -v V="$2" '
    { sub(/^[ \t]+/, "") }
    /^#/ { next }
    $0 == "rastro_caminho_em " V " \"$" V "\"" { achou = 1; exit }
    index($0, "$" V) || index($0, "${" V) || index($0, V "=") || index($0, "rastro_json_campo_em " V " ") {
      l = $0
      gsub("\\[ -n \"\\$" V "\" \\] \\|\\| (exit 0|" V "=\"\\$PWD\")", "", l)
      gsub("rastro_json_campo_em " V " \"\\$ENTRADA\" [a-z_]+", "", l)
      gsub("(^|[; ])" V "=\"\\$\\((rastro_json_get|rastro_tool_input_get) \"\\$ENTRADA\" [a-z_]+\\)\"", "", l)
      gsub("(^|[; ])" V "=\"\\$\\{CAMPOS\\[[0-9]\\]-\\}\"", "", l)
      if (index(l, "$" V) || index(l, "${" V) || index(l, V "=")) { ruim = NR ": " $0; exit }
    }
    END { if (ruim != "") { print ruim; exit 1 } if (!achou) { print "sem rastro_caminho_em"; exit 1 } }
  ' "$1"
}
t_estrutura() { # t_estrutura <raiz-hooks> — falhas em T_FALHA
  local H2="$1" p f v out
  T_FALHA=""
  for p in $T_PARES; do
    f="${p%%:*}"; v="${p#*:}"
    out="$(t_normaliza_antes "$H2/$f" "$v")" || T_FALHA="$T_FALHA $f:$v($out)"
  done
  for f in "$H2"/comum/*.sh "$H2"/sprintx/*.sh; do
    case "$f" in */comum/rastro.sh) continue ;; esac
    # Le pathname do payload sem estar na auditoria?
    if grep -v '^[[:space:]]*#' "$f" | grep -qE '(rastro_json_get|rastro_tool_input_get|rastro_json_campo_em [A-Z_]+) "\$ENTRADA" (cwd|file_path)|\.(cwd|file_path) //'; then
      case " $(printf '%s' "$T_PARES" | tr '\n' ' ') " in *" ${f#"$H2"/}:"*) ;; *) T_FALHA="$T_FALHA ${f#"$H2"/}:le-caminho-fora-da-auditoria" ;; esac
    fi
    # Normalizacao propria: cygpath, troca de barra invertida, letra de drive.
    if grep -v '^[[:space:]]*#' "$f" | grep -qE 'cygpath|//\\\\+/|s[#/|,]\\\\\\\\|tr .\\\\\\\\|\[A-Za-z\]:|\[a-zA-Z\]:'; then
      T_FALHA="$T_FALHA ${f#"$H2"/}:normalizacao-propria"
    fi
  done
  [ -z "$T_FALHA" ]
}
t_estrutura "$H"; afirma "t3-todo-caminho-do-payload-pelo-helper" $? "$(printf '%s\n' "$T_PARES" | wc -w | tr -d ' ') pares hook:variavel; nenhuma normalizacao propria${T_FALHA:+ — FORA:$T_FALHA}"

# Custo (DS-157): normalizar e builtin. O formato Windows nao custa processo a mais que o POSIX,
# nos dois criticos e num PostToolUse. Shims no PATH, como nas secoes Q e S.
T_SHIM="$T_DIR/shim"; mkdir -p "$T_SHIM"
for c in awk jq grep sed cut tr wc sort head tail find cat date mkdir dirname basename ps git cygpath python3 xargs; do
  r="$(command -v "$c" 2>/dev/null)"; case "$r" in */*) ;; *) continue ;; esac
  printf '#!/bin/sh\nprintf "%%s\\n" "%s" >> "$T_LOG"\nexec "%s" "$@"\n' "$c" "$r" > "$T_SHIM/$c"; chmod +x "$T_SHIM/$c"
done
t_custo() { # t_custo <hook> <evento> <cwd> <file_path> <conteudo> — processos externos
  rm -rf "$T_FX/src/docs"; printf '%s\n' "$T_BASE" > "$T_FX/$EF"; : > "$T_DIR/log"
  t_json "$2" Write "$3" "$4" "$5" | (cd "$T_FX" && PATH="$T_SHIM:$PATH" T_LOG="$T_DIR/log" EXPX_SESSAO=t3e@1 CLAUDECODE=1 bash "$H/$1") >/dev/null 2>&1
  grep -c '' "$T_DIR/log"
}
T_CUSTO=""; T_CRUIM=""
T_W="$T_FX"; [ "$T_WIN" = 1 ] && T_W="$(cygpath -w "$T_FX")"
while IFS='|' read -r rot h ev ct; do
  cp_="$(t_custo "$h" "$ev" "$T_FX" "$T_FX/src/a.ts" "$(t_conteudo "$ct")")"
  cw_="$(t_custo "$h" "$ev" "$T_W" "$T_W\\src\\a.ts" "$(t_conteudo "$ct")")"
  T_CUSTO="$T_CUSTO $rot posix=$cp_ win=$cw_;"
  [ "$cw_" -le "$cp_" ] || T_CRUIM="$T_CRUIM $rot"
done <<EOF
segredo-limpo|comum/segredo.sh|PreToolUse|inocente
segredo-achado|comum/segredo.sh|PreToolUse|aws
escopo|sprintx/escopo-da-task.sh|PreToolUse|inocente
rastro-post|comum/rastro-post.sh|PostToolUse|inocente
EOF
[ -z "$T_CRUIM" ]; afirma "t4-formato-windows-nao-custa-processo" $? "${T_CUSTO% ;}${T_CRUIM:+ — MAIS CARO:$T_CRUIM}"

# Mutantes. Copia da arvore de hooks (comum/ + sprintx/); o controle e a copia sem mutacao.
T_M="$T_DIR/mut"
t_copia() { rm -rf "$T_M/$1"; mkdir -p "$T_M/$1"; cp -R "$H/comum" "$H/sprintx" "$T_M/$1/"; printf '%s' "$T_M/$1"; }
T_MF="posix"; [ "$T_WIN" = 1 ] && T_MF="win minuscula caixa-do-drive"
t_mutante() { # t_mutante <nome> <rc geracao> <raiz> <casos que TEM de matar> [estrutural]
  local nome="$1" rc="$2" r="$3" casos="$4" est="${5:-}" morto=""
  if [ "$rc" -eq 0 ]; then
    t_formatos "$r" "$T_FX" "$T_MF" "$casos" || morto="comportamento"
    if [ -n "$est" ]; then t_estrutura "$r" || morto="${morto:+$morto+}estrutura"; fi
  fi
  local msg="SOBREVIVEU"; [ -z "$morto" ] || msg="morto por: $morto"
  [ "$rc" -eq 0 ] && [ -n "$morto" ]; afirma "$nome" $? "$msg (rc geracao=$rc)"
}
TMC="$(t_copia controle)"; t_formatos "$TMC" "$T_FX" "$T_MF" todos && t_estrutura "$TMC"
afirma "tm-controle-copia-intacta-sobrevive" $? "$T_MF + estrutura${T_FALHA:+ — FORA:$T_FALHA}"
# 1. O segredo volta a usar cwd e file_path crus.
TMU="$(t_copia m1)"; muta_lit "$TMU/comum/segredo.sh" "$TMU/s.m" 'rastro_caminho_em ALVO "$ALVO"' ':' \
  && muta_lit "$TMU/s.m" "$TMU/comum/segredo.sh" 'rastro_caminho_em CWD "$CWD"' ':'
t_mutante "tm-mutante-1-segredo-sem-normalizar" $? "$TMU" "seg-env-ignorado seg-aws seg-cwd-sub" estrutura
# 2. Outro PreToolUse (task-so-fecha-verde) volta a casar `*/tasks.md` no caminho cru.
TMU="$(t_copia m2)"; muta_lit "$H/sprintx/task-so-fecha-verde.sh" "$TMU/sprintx/task-so-fecha-verde.sh" 'rastro_caminho_em ALVO "$ALVO"' ':'
t_mutante "tm-mutante-2-outro-pretooluse-sem-normalizar" $? "$TMU" "verde-ruim" estrutura
# 3. A caixa do drive deixa de ser canonica no helper (c:\ e C:\ viram raizes diferentes). So
# onde o formato Windows existe: fora dele o helper e no-op e o trecho mutado nem roda.
if [ "$T_WIN" = 1 ]; then
  TMU="$(t_copia m3)"; muta_lit "$H/comum/rastro.sh" "$TMU/comum/rastro.sh" '_d="${_m:${#_i}:1}"' ':'
  t_mutante "tm-mutante-3-caixa-do-drive-nao-normalizada" $? "$TMU" "seg-env-ignorado seg-aws tdd-com-teste verde-ruim reivindicada placeholder post-write"
fi
# 4. Caminho com espaco quebra: a variavel vai sem aspas para o helper.
TMU="$(t_copia m4)"; muta_lit "$H/comum/segredo.sh" "$TMU/comum/segredo.sh" 'rastro_caminho_em ALVO "$ALVO"' 'rastro_caminho_em ALVO $ALVO'
t_mutante "tm-mutante-4-caminho-com-espaco-quebra" $? "$TMU" "seg-aws-espaco" estrutura
# 5. O rastro-post grava o caminho Windows cru.
TMU="$(t_copia m5)"; muta_lit "$H/comum/rastro-post.sh" "$TMU/comum/rastro-post.sh" 'rastro_caminho_em ALVO "$ALVO"' ':'
t_mutante "tm-mutante-5-rastro-post-grava-caminho-cru" $? "$TMU" "post-write post-espaco" estrutura
# 6. Um hook volta a normalizar sozinho, so trocando a barra, e corta a raiz por `/`.
TMU="$(t_copia m6)"; muta_lit "$H/sprintx/tdd-teste-antes.sh" "$TMU/sprintx/tdd-teste-antes.sh" 'rastro_caminho_em ALVO "$ALVO"' 'ALVO="${ALVO//\\//}"'
t_mutante "tm-mutante-6-hook-volta-ao-corte-por-barra" $? "$TMU" "tdd-com-teste tdd-artefato-da-skill" estrutura
rm -rf "$T_DIR"

