#!/usr/bin/env bash
# git-perigoso — PreToolUse em Bash. NASCE EM BLOQUEIO.
#
# Caminho e id com o namespace da skill (DS-158): `.claude/hooks/sprintx/git-perigoso.sh`,
# modo em `.expx/hooks.json` sob `sprintx/git-perigoso`. A mergex publica um hook de mesmo
# nome, com regras proprias, em `comum/`: nenhum dos dois sobrescreve o outro, em qualquer
# ordem de instalacao, e o modo de um nunca desliga o outro.
#
# Barra operacao de versionamento destrutiva e irreversivel durante uma
# execucao autonoma. A F6 roda sem supervisao: um `push --force` ali apaga
# trabalho de outra pessoa sem ninguem ver acontecer.
#
# Hook de SEGURANCA: falha fechada.
#
# Custo (DS-157): o runner cancela o hook que estoura o timeout e deixa o comando
# RODAR — timeout e falha aberta. O caminho comum (comando inocuo) nao cria nenhum
# processo: o payload e lido e decodificado pelo bash. O hook e a primeira barreira;
# a posterior, fail-closed, e o E1 da mergex.
set -uo pipefail

case "${BASH_SOURCE[0]}" in */*) DIR="${BASH_SOURCE[0]%/*}" ;; *) DIR=. ;; esac
# shellcheck source=../comum/rastro.sh
. "$DIR/../comum/rastro.sh"

rastro_le_entrada_em ENTRADA
rastro_json_campo_em CWD "$ENTRADA" cwd
[ -n "$CWD" ] || CWD="$PWD"
rastro_raiz_em RAIZ "$CWD"

rastro_json_campo_em CMD "$ENTRADA" command
[ -n "$CMD" ] || exit 0

MOTIVO=""
case "$CMD" in
  *"git push"*"--force"*|*"git push"*" -f "*|*"git push --force-with-lease"*)
    MOTIVO="push forcado reescreve o historico remoto" ;;
  *"git reset --hard"*)
    MOTIVO="reset --hard descarta alteracoes nao commitadas, sem desfazer" ;;
  *"git clean -"*[fdx]*)
    MOTIVO="git clean apaga arquivos nao rastreados definitivamente" ;;
  *"git checkout ."*|*"git restore ."*)
    MOTIVO="descarta todas as alteracoes locais de uma vez" ;;
  *"git branch -D"*)
    MOTIVO="apaga branch sem verificar merge" ;;
  *"git rebase"*|*"git filter-branch"*|*"git reflog expire"*)
    MOTIVO="reescreve historico" ;;
esac

[ -n "$MOTIVO" ] || exit 0

# Hook de seguranca: o padrao e bloqueio e ausencia de configuracao NAO rebaixa.
# So um "desligado" explicito desliga.
rastro_modo_em MODO "$RAIZ" sprintx/git-perigoso seguranca
[ "$MODO" = "desligado" ] && exit 0

rastro_grava "$RAIZ" acao_bloqueada hook bloqueado "git perigoso: $MOTIVO" '[]'
rastro_bloqueia "sprintx/git-perigoso: comando barrado — $MOTIVO. Durante a execucao autonoma nenhuma operacao de versionamento irreversivel roda sem decisao humana. Se isso e mesmo necessario, pare, registre em 00-BLOQUEIOS.md e deixe para o usuario decidir."
