#!/usr/bin/env bash
#
# Casos da secao N da bancada (escopo-da-task) para plano por link, carregados por
# `.` de dentro da bancada.sh: usam os auxiliares dela (n_fx, n_plano, n_task, n_hook,
# n_tem, n_silencio, NF_DIR). Moram aqui porque a bancada.sh passa do limite de
# tamanho do expx-fatiamento (F4) e nao cresce.

n_lnkirma() { # sprint do trabalho corrente por link, com irma dona do arquivo: fail-closed
  local d="$NF_DIR/lnkirma"
  n_fx "$d" alfa-antiga hist
  n_plano "$d/fora/s2.md" corrente 02 <<EOF
$(n_task T-02.01 pendente src/da-irma.ts)
EOF
  mkdir -p "$d/docs/sprintx/features/corrente/sprint-02"
  ln -s "$d/fora/s2.md" "$d/docs/sprintx/features/corrente/sprint-02/tasks.md" || return 1
  n_hook "$d" "$1" src/da-irma.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem plano_corrente_ilegivel && n_tem "(link)" || return 1
  n_hook "$d" "$1" src/novo.ts eu@sessao; n_silencio
}
n_lnkoutra() { # plano por link de OUTRA feature nao muda o caso geral: segue aviso
  local d="$NF_DIR/lnkoutra"
  n_fx "$d" alfa-antiga hist
  n_plano "$d/fora/s2.md" alfa-antiga 02 <<EOF
$(n_task T-02.01 pendente src/da-outra.ts)
EOF
  mkdir -p "$d/docs/sprintx/features/alfa-antiga/sprint-02"
  ln -s "$d/fora/s2.md" "$d/docs/sprintx/features/alfa-antiga/sprint-02/tasks.md" || return 1
  n_hook "$d" "$1" src/da-outra.ts eu@sessao
  [ "$N_RC" -eq 0 ] && n_tem "nao esta na lista" && ! n_tem plano_corrente_ilegivel
}
n_lnkfundo() { # link fundo demais para o resolvedor (3 niveis sob o trabalho): nao fecha
  local d="$NF_DIR/lnkfundo"
  n_fx "$d" alfa-antiga hist
  n_plano "$d/fora/s2.md" corrente 02 <<EOF
$(n_task T-02.01 pendente src/da-irma.ts)
EOF
  mkdir -p "$d/docs/sprintx/features/corrente/arquivo/velho/sprint-02"
  ln -s "$d/fora/s2.md" "$d/docs/sprintx/features/corrente/arquivo/velho/sprint-02/tasks.md" || return 1
  n_hook "$d" "$1" src/da-irma.ts eu@sessao
  [ "$N_RC" -eq 0 ] && ! n_tem plano_corrente_ilegivel
}
