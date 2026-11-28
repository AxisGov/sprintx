#!/usr/bin/env bash
#
# Secao AP da bancada: suite vermelha so por ambiente e task sem arquivos (DS-238).
# Carregada por `.` de dentro da bancada.sh, ou rodada sozinha:
#   bash .claude/hooks/testes/bancada-suite-ambiente.sh
#
# O `task-so-fecha-verde` deixa a task ir para `concluida` com `suite: vermelha` somente
# quando `suite_falhas` lista os arquivos que falharam e TODOS estao em
# .expx/falhas-de-ambiente.tsv para a plataforma da maquina. Task com `cria: []` e
# `altera: []` fecha como qualquer outra.

SA_SOZINHA=""
if ! declare -F afirma >/dev/null 2>&1; then
  SA_SOZINHA=1
  set -uo pipefail
  H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  SK="$H/../skills/sprintx"
  ok=0; falhou=0
  afirma() { # afirma <nome> <condicao-ja-avaliada:0|1> <detalhe>
    if [ "$2" -eq 0 ]; then ok=$((ok+1)); printf '  ok   %-46s %s\n' "$1" "$3"
    else falhou=$((falhou+1)); printf '  FALHA %-45s %s\n' "$1" "$3"; fi
  }
fi

echo "== AP. suite vermelha so por ambiente e task sem arquivos (DS-238) =="
SA_T="$(mktemp -d)"
SA_H="$(cd "$H" && pwd)"
SA_W="$SA_T/fx com espaco"
SA_TASKS="$SA_W/docs/sprintx/features/fx/sprint-01/tasks.md"

sa_esc() { # JSON: barra, aspas, tab, CR e LF
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"; s="${s//$'\r'/\\r}"; s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}
sa_fx() { # sa_fx — fixture limpa, sem lista e em modo aviso
  rm -rf "$SA_W"
  mkdir -p "$SA_W/.git" "$SA_W/.expx" "$SA_W/docs/eventos" "$SA_W/docs/sprintx/features/fx/sprint-01"
}
sa_lista() { # sa_lista <conteudo, com \t e \n do printf>
  # shellcheck disable=SC2059
  printf "$1" > "$SA_W/.expx/falhas-de-ambiente.tsv"
}
sa_task() { # sa_task <suite> <linhas extras da task, ja indentadas> — o tasks.md que vai ser gravado
  printf -- '---\nkind: tasks\ntrabalho_id: fx\nsprint_id: sprint-01\ntasks:\n  - id: T-01.01\n    titulo: t\n    status: concluida\n    objetivo: o\n    arquivos:\n      cria: []\n      altera: []\n    teste_integracao: roda npm ci contra o lock\n    teste_funcional: dado o lock entao instala sem erro\n    criterio_aceite: c\n    depende_de: []\n    paralelizavel: false\n    concluida_em: 2026-11-27\n    suite: %s\n%b---\n' "$1" "$2"
}
sa_roda() { # sa_roda <conteudo> — "rc/avisa|silencio" do hook na fixture, em linux
  local json o r
  json="{\"session_id\":\"x\",\"cwd\":\"$(sa_esc "$SA_W")\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$(sa_esc "$SA_TASKS")\",\"content\":\"$(sa_esc "$1")\"}}"
  o="$(printf '%s' "$json" | (cd "$SA_W" && EXPX_PLATAFORMA="${SA_PLAT:-linux}" bash "$SA_H/sprintx/task-so-fecha-verde.sh") 2>&1)"; r=$?
  SA_SAIDA="$o"
  case "$o" in *"task nao pode ir para concluida"*) printf '%s/avisa' "$r" ;; "") printf '%s/silencio' "$r" ;; *) printf '%s/outro' "$r" ;; esac
}
sa_caso() { # sa_caso <nome> <esperado> <conteudo>
  local real; real="$(sa_roda "$3")"
  [ "$real" = "$2" ]; afirma "ap-$1" $? "esperado $2, real $real"
}

T2=$'\t'
SA_LISTA_LINUX="tests/a.test.ts${T2}linux${T2}fuso da maquina${T2}2026-11-27\ntests/b c.test.ts${T2}linux${T2}utf8 do console${T2}2026-11-27\n"

# 1. Task sem arquivos (`cria: []` e `altera: []`) fecha com suite parcial: o hook nao a reprova.
sa_fx
sa_caso task-sem-arquivos-fecha 0/silencio "$(sa_task parcial '')"

# 2. Vermelha sem `suite_falhas`, ou com a lista vazia, continua barrada.
sa_fx; sa_lista "$SA_LISTA_LINUX"
sa_caso vermelha-sem-suite-falhas-avisa 0/avisa "$(sa_task vermelha '')"
sa_caso vermelha-com-suite-falhas-vazia-avisa 0/avisa "$(sa_task vermelha '    suite_falhas: []\n')"

# 3. Vermelha com todas as falhas na lista da plataforma fecha, em fluxo e em bloco.
sa_caso vermelha-toda-na-lista-em-fluxo-fecha 0/silencio "$(sa_task vermelha '    suite_falhas: [tests/a.test.ts, "tests/b c.test.ts"]\n')"
sa_caso vermelha-toda-na-lista-em-bloco-fecha 0/silencio "$(sa_task vermelha '    suite_falhas:\n      - tests/a.test.ts\n      - tests/b c.test.ts\n')"
sa_caso bloco-linha-em-branco-fora-avisa 0/avisa "$(sa_task vermelha '    suite_falhas:\n      - tests/a.test.ts\n\n      - tests/novo.test.ts\n')"
sa_caso bloco-comentario-fora-avisa 0/avisa "$(sa_task vermelha '    suite_falhas:\n      - tests/a.test.ts\n      # nota: |\n      - tests/novo.test.ts\n')"
sa_caso bloco-linha-em-branco-listados-fecha 0/silencio "$(sa_task vermelha '    suite_falhas:\n      - tests/a.test.ts\n\n      - tests/b c.test.ts\n')"
sa_caso bloco-chave-seguinte-lida 0/avisa "$(sa_task vermelha '    suite_falhas:\n      - tests/a.test.ts\n\n    suite: nao_executada\n')"

# 4. Uma falha fora da lista barra, e o aviso nomeia o arquivo.
sa_roda "$(sa_task vermelha '    suite_falhas: [tests/a.test.ts, tests/novo.test.ts]\n')" > "$SA_T/r"
[ "$(cat "$SA_T/r")" = 0/avisa ] && case "$SA_SAIDA" in *tests/novo.test.ts*) true ;; *) false ;; esac
afirma "ap-falha-fora-da-lista-avisa-e-nomeia" $? "real $(cat "$SA_T/r")"

# 5. A lista de outra plataforma nao vale aqui.
sa_fx; sa_lista "tests/a.test.ts${T2}win32${T2}fuso da maquina${T2}2026-11-27\n"
sa_caso lista-de-outra-plataforma-avisa 0/avisa "$(sa_task vermelha '    suite_falhas: [tests/a.test.ts]\n')"
SA_PLAT=win32 sa_caso mesma-lista-em-win32-fecha 0/silencio "$(sa_task vermelha '    suite_falhas: [tests/a.test.ts]\n')"

# 6. Linha com motivo vazio, ou comentada, nao vale.
sa_fx; sa_lista "tests/a.test.ts${T2}linux${T2}${T2}2026-11-27\n# tests/b.test.ts${T2}linux${T2}x${T2}2026-11-27\n"
sa_caso motivo-vazio-nao-vale 0/avisa "$(sa_task vermelha '    suite_falhas: [tests/a.test.ts]\n')"
sa_caso linha-comentada-nao-vale 0/avisa "$(sa_task vermelha '    suite_falhas: [tests/b.test.ts]\n')"
sa_fx; sa_lista "tests/a.test.ts${T2}linux${T2}   ${T2}2026-11-27\n"
sa_caso motivo-so-de-espacos-nao-vale 0/avisa "$(sa_task vermelha '    suite_falhas: [tests/a.test.ts]\n')"

# 7. CRLF e ultima linha sem quebra final: a lista continua valendo.
sa_fx; sa_lista "tests/a.test.ts${T2}linux${T2}fuso${T2}2026-11-27\r\ntests/b c.test.ts${T2}linux${T2}utf8${T2}2026-11-27"
sa_caso crlf-e-sem-quebra-final-fecha 0/silencio "$(sa_task vermelha '    suite_falhas: [tests/a.test.ts, tests/b c.test.ts]\n')"

# 8. O casamento e exato: prefixo do caminho nao vale.
sa_caso caminho-parecido-nao-vale 0/avisa "$(sa_task vermelha '    suite_falhas: [tests/a.test]\n')"

# 9. Em `bloqueio`, a vermelha fora da lista sai 2; a que esta toda na lista continua passando.
printf '{"hooks":{"task-so-fecha-verde":{"modo":"bloqueio"}}}' > "$SA_W/.expx/hooks.json"
sa_caso modo-bloqueio-barra-fora-da-lista 2/avisa "$(sa_task vermelha '    suite_falhas: [tests/novo.test.ts]\n')"
sa_caso modo-bloqueio-deixa-a-da-lista 0/silencio "$(sa_task vermelha '    suite_falhas: [tests/a.test.ts]\n')"

# 10. Controles: o que ja era regra nao mudou.
sa_fx
sa_caso nao-executada-continua-barrada 0/avisa "$(sa_task nao_executada '')"
sa_caso verde-continua-fechando 0/silencio "$(sa_task verde '    suite_falhas: []\n')"
# a lista de uma task nao vale para a seguinte
sa_lista "$SA_LISTA_LINUX"
SA_DUAS="$(sa_task vermelha '    suite_falhas:\n      - tests/a.test.ts\n  - id: T-01.02\n    status: concluida\n    teste_integracao: t\n    teste_funcional: t\n    suite: vermelha\n')"
sa_roda "$SA_DUAS" > "$SA_T/r"
[ "$(cat "$SA_T/r")" = 0/avisa ] && case "$SA_SAIDA" in *"T-01.02: suite=vermelha sem suite_falhas"*) true ;; *) false ;; esac
afirma "ap-lista-nao-vaza-para-a-task-seguinte" $? "real $(cat "$SA_T/r")"

# 12. Item entre aspas na lista de fluxo (DS-239): a virgula e o `#` de dentro das aspas
#     ficam no caminho e as aspas saem; sem aspas, a virgula continua separando; aspa sem
#     fechamento invalida a lista inteira, e a vermelha nao fecha.
sa_fx; sa_lista "${SA_LISTA_LINUX}tests/a,b.test.ts${T2}linux${T2}locale${T2}2026-11-27\ntests/c #1.test.ts${T2}linux${T2}locale${T2}2026-11-27\n"
sa_caso virgula-entre-aspas-duplas-no-fluxo-fecha 0/silencio "$(sa_task vermelha '    suite_falhas: [tests/a.test.ts, "tests/a,b.test.ts"]\n')"
sa_caso virgula-entre-aspas-simples-no-fluxo-fecha 0/silencio "$(sa_task vermelha "    suite_falhas: ['tests/a,b.test.ts', tests/b c.test.ts]  # nota\n")"
sa_caso cerquilha-entre-aspas-no-fluxo-fecha 0/silencio "$(sa_task vermelha '    suite_falhas: ["tests/c #1.test.ts"]\n')"
sa_caso virgula-sem-aspas-continua-separando 0/avisa "$(sa_task vermelha '    suite_falhas: [tests/a,b.test.ts]\n')"
sa_roda "$(sa_task vermelha '    suite_falhas: ["tests/a.test.ts, tests/b c.test.ts]\n')" > "$SA_T/r"
[ "$(cat "$SA_T/r")" = 0/avisa ] && case "$SA_SAIDA" in *"suite_falhas invalida"*) true ;; *) false ;; esac
afirma "ap-aspas-duplas-desbalanceadas-no-fluxo-nao-fecha" $? "real $(cat "$SA_T/r")"
sa_caso aspas-simples-desbalanceadas-no-fluxo-nao-fecha 0/avisa "$(sa_task vermelha "    suite_falhas: [tests/a.test.ts, 'tests/b c.test.ts]\n")"
sa_caso texto-depois-da-aspa-no-fluxo-nao-fecha 0/avisa "$(sa_task vermelha '    suite_falhas: ["tests/a.test.ts"x]\n')"
sa_caso aspa-solta-no-fim-do-item-no-fluxo-nao-fecha 0/avisa "$(sa_task vermelha '    suite_falhas: [tests/a.test.ts"]\n')"
sa_caso aspa-solta-no-fim-do-item-em-bloco-nao-fecha 0/avisa "$(sa_task vermelha '    suite_falhas:\n      - tests/a.test.ts"\n')"
sa_caso fluxo-sem-colchete-de-fecho-nao-fecha 0/avisa "$(sa_task vermelha '    suite_falhas: [tests/a.test.ts\n')"
sa_caso fluxo-com-virgula-final-sem-fecho-nao-fecha 0/avisa "$(sa_task vermelha '    suite_falhas: [tests/a.test.ts,\n')"
sa_caso escape-dentro-das-aspas-nao-fecha 0/avisa "$(sa_task vermelha '    suite_falhas: ["tests/a.test.ts\\", tests/b c.test.ts"]\n')"
sa_caso fluxo-com-comentario-depois-do-fecho-fecha 0/silencio "$(sa_task vermelha '    suite_falhas: [tests/a.test.ts]  # nota\n')"
# na lista em bloco, o item entre aspas tambem perde as aspas, e a aspa sem fechamento invalida
sa_caso aspas-na-lista-em-bloco-fecha 0/silencio "$(sa_task vermelha "    suite_falhas:\n      - \"tests/a,b.test.ts\"\n      - 'tests/c #1.test.ts'  # nota\n")"
sa_caso aspas-desbalanceadas-na-lista-em-bloco-nao-fecha 0/avisa "$(sa_task vermelha '    suite_falhas:\n      - tests/a.test.ts\n      - "tests/b c.test.ts\n')"
# a lista invalida so pesa na vermelha: a verde fecha como antes
sa_caso verde-com-aspas-desbalanceadas-fecha 0/silencio "$(sa_task verde '    suite_falhas: ["tests/a.test.ts]\n')"

# 11. O contrato escrito: nenhum texto da skill diz que cria/altera vazios sao invalidos, e o
#     da suite vermelha por ambiente esta onde a F6 o le.
SA_EXEC="$SK/references/06-execucao.md"
grep -qF 'suite_falhas' "$SA_EXEC" && grep -qF '.expx/falhas-de-ambiente.tsv' "$SA_EXEC" \
  && grep -qF 'suite_falhas' "$SK/references/00-schema.md" && grep -qF '| DS-238' "$SK/DECISOES-DA-SKILL.md"
afirma "ap-contrato-escrito" $? "06-execucao, 00-schema e DS-238"
if grep -rniE '(cria|altera|arquivos)[^|]{0,40}(vazi[oa]s?|\[\])[^|]{0,40}(inv[aá]lid|proibid|n[aã]o pode)' "$SK" >/dev/null 2>&1; then false; else true; fi
afirma "ap-nenhum-texto-diz-vazio-invalido" $? "cria/altera vazios nunca aparecem como invalidos"

rm -rf "$SA_T"
if [ -n "$SA_SOZINHA" ]; then
  echo
  echo "  $ok ok, $falhou falhas"
  [ "$falhou" -eq 0 ]
fi
