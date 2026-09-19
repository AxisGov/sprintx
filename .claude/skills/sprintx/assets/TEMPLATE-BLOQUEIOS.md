---
expx_schema: 1
expx_tool: sprintx
kind: bloqueios
trabalho_id: {{slug-da-feature}}
atualizado_em: {{AAAA-MM-DD}}
bloqueios: []
---

# Bloqueios

> Criado vazio na F1 e preenchido na execução (F6). Um bloqueio nunca vira pergunta ao usuário: registre aqui, marque a task `bloqueada` e siga para a próxima paralelizável.
> Registre só por `scripts/bloqueios.sh registrar <slug> <task> <classe> <descrição> <o que destravaria>`: ele grava o item na lista `bloqueios:` do frontmatter, com a `classe` do caminho de criação, e a linha abaixo. A classe vem do caminho, nunca da descrição. Formato em `references/00-schema.md`.

Nenhum bloqueio registrado.

<!-- O script substitui a linha acima no primeiro registro. Formato da linha:

B-01 | {{T-NN.MM}} | {{descrição do bloqueio}} | {{o que destravaria}}

e o item equivalente no frontmatter:

  - id: B-01
    task: {{T-NN.MM}}
    classe: {{defeito_de_plano | lacuna_de_decisao | prerequisito_ausente | suite_vermelha | task_reivindicada}}
    aberto_em: {{AAAA-MM-DD}}
    resolvido_em: null
    descricao: {{descricao em uma linha}}
-->
