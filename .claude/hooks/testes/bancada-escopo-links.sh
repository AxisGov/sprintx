#!/usr/bin/env bash
#
# Casos da secao N da bancada (escopo-da-task) para plano por link, carregados por
# `.` de dentro da bancada.sh: usam os auxiliares dela (n_fx, n_plano, n_task, n_hook,
# n_tem, n_silencio, NF_DIR).
# Ficam fora dela pela regra de tamanho de arquivo: < 5.000 linhas e < 200 KB (emenda
# AxisGov/expxdev docs/superpowers/specs/2026-10-19-limites-do-codeant-emenda.md).

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
n_lnkhist() { # so o plano corrente por link, a historica legivel e sem em_andamento: fecha
  local d="$NF_DIR/lnkhist"
  n_fx "$d" alfa-antiga hist
  mkdir -p "$d/fora"
  mv "$d/docs/sprintx/features/corrente/sprint-01/tasks.md" "$d/fora/c.md"
  ln -s "$d/fora/c.md" "$d/docs/sprintx/features/corrente/sprint-01/tasks.md" || return 1
  n_hook "$d" "$1" src/novo.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem plano_corrente_ilegivel && ! n_tem plano_corrente_ausente || return 1
  n_hook "$d" "$1" src/novo.ts outra@sessao
  [ "$N_RC" -eq 0 ] && n_tem "NAO foi conferida"
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
n_lnkvazio() { # task corrente sem `arquivos` e sprint do trabalho por link: fecha; sem o link, segue
  local d="$NF_DIR/lnkvazio"
  n_fx "$d" alfa-antiga hist
  n_replano "$d" corrente <<EOF
$(n_task T-01.01 em_andamento "")
EOF
  n_plano "$d/fora/s2.md" corrente 02 <<EOF
$(n_task T-02.01 pendente src/da-irma.ts)
EOF
  mkdir -p "$d/docs/sprintx/features/corrente/sprint-02"
  ln -s "$d/fora/s2.md" "$d/docs/sprintx/features/corrente/sprint-02/tasks.md" || return 1
  n_hook "$d" "$1" src/da-irma.ts eu@sessao
  [ "$N_RC" -eq 2 ] && n_tem plano_corrente_ilegivel && n_tem "(link)" || return 1
  rm "$d/docs/sprintx/features/corrente/sprint-02/tasks.md"
  n_hook "$d" "$1" src/da-irma.ts eu@sessao; n_silencio
}
