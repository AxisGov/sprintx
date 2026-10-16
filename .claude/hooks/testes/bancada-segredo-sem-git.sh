#!/usr/bin/env bash
#
# Caso da secao T da bancada (segredo.sh sem repositorio), carregado por `.` de dentro
# da bancada.sh: usa os auxiliares dela (t_json, t_conteudo, T_DIR). Mora aqui porque a
# bancada.sh passa do limite de tamanho do expx-fatiamento (F4) e nao cresce.
#
# Sem repositorio, o segredo le o .gitignore como o git: glob (`.env.*` isenta `.env.local`),
# ancora (`/x` so na raiz), `*` sem atravessar `/`, e a ultima regra que casa decide.
# Cada caso: nome|alvo|linhas do .gitignore (\n)|rc esperado.

t_semgit() { # t_semgit <raiz-hooks> — falhas em T_FALHA
  local d="$T_DIR/semgit/r" n a g e r
  T_FALHA=""
  while IFS='|' read -r n a g e; do
    rm -rf "$d"; mkdir -p "$d/src"; printf "$g\n" > "$d/.gitignore"
    t_json PreToolUse Write "$d" "$d/$a" "$(t_conteudo aws)" \
      | (cd "$d" && GIT_CEILING_DIRECTORIES="$T_DIR/semgit" bash "$1/comum/segredo.sh") >/dev/null 2>&1; r=$?
    [ "$r" = "$e" ] || T_FALHA="$T_FALHA $n=$r(esperado $e)"
  done <<EOF
seg-semgit-glob-isenta|.env.local|.env.*|0
seg-semgit-glob-em-pasta|src/.env.local|.env.*|0
seg-semgit-literal|.env|.env|0
seg-semgit-example-varrido|.env.example|.env|2
seg-semgit-ancorada|src/.env|/.env|2
seg-semgit-glob-nao-cruza-barra|src/.env|/*.env|2
seg-semgit-negacao|.env.local|.env.*\n!.env.local|2
seg-semgit-duplo-aninhado|a/b/.env|**/.env|0
seg-semgit-duplo-na-raiz|.env|**/.env|0
seg-semgit-duplo-com-curinga-nao-isenta|a/b/x.env|**/*.env|2
seg-semgit-duplo-no-meio|config/a/b/.env|config/**/.env|0
seg-semgit-duplo-colado-nao-isenta|xa/b/.env|x**/.env|2
seg-semgit-duplo-zero-pastas|config/.env|config/**/.env|0
EOF
  [ -z "$T_FALHA" ]
}
