#!/usr/bin/env bash
# fonte.sh — onde esta a fonte da sprintx para as partes da bancada. Carregado por `.`.
#
# A fonte so existe no repositorio da sprintx. Instalada — no marketplace do expx
# (.expx/marketplace/plugins/expx/hooks/testes) ou em .claude/hooks/testes de um
# projeto —, a bancada roda o que nao depende dela e registra o resto como
# dependencia externa ausente: nunca aborta, e nunca le o repositorio do projeto
# como se fosse o da sprintx. A propria localizacao deste arquivo identifica a
# fonte; $H identifica apenas o host executor.

m_raiz_fonte() { # m_raiz_fonte <diretorio-dos-testes> — a raiz do repositorio da sprintx, ou vazio
  local r; r="$(cd "$1/../../.." 2>/dev/null && pwd)" || return 0
  [ -d "$r/.claude/hooks/sprintx" ] && [ -f "$r/install.sh" ] && [ -f "$r/scripts/ci/test-predecessores.sh" ] \
    && printf '%s' "$r"
  return 0
}
RAIZ_SRC="$(m_raiz_fonte "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
SEM_FONTE="bancada instalada, sem o repositorio da sprintx"
