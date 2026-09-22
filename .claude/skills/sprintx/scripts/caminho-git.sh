#!/usr/bin/env bash
# caminho-git.sh — caminho absoluto devolvido pelo Git, pronto para o Bash (DS-152).
#
# Nao e executavel por si so: planejamento.sh e bloqueios.sh fazem `source` deste arquivo.
#
# O Git for Windows devolve `C:/...` mesmo dentro do Git Bash. So ali — onde existe
# cygpath — a forma `<drive>:/...` vira POSIX (`/c/...`). Caminho POSIX, relativo, ou
# qualquer ambiente sem cygpath (Linux, macOS) passa intacto. Bash 3.2 compativel.

caminho_git() { # caminho_git <caminho>
  case "$1" in
    [A-Za-z]:/*) if command -v cygpath >/dev/null 2>&1; then cygpath -u -- "$1" && return 0; fi ;;
  esac
  printf '%s' "$1"
}
