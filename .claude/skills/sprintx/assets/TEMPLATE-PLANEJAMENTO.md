---
expx_schema: 1
expx_tool: sprintx
kind: planejamento
trabalho_id: {{slug-da-feature}}
max_reprovacoes_f5: {{inteiro-positivo-ou-null}}
max_replanejamentos_f6: {{inteiro-positivo-ou-null}}
orcamento_declarado_por: {{identificador-ou-null}}
estado: {{estado-ou-null}}
reprovacoes: {{inteiro-maior-ou-igual-a-zero}}
replanejamentos_f6: {{inteiro-maior-ou-igual-a-zero}}
bloqueios_replanejamento_f6: []
tasks_congeladas: []
assinatura_congeladas: null
parciais_replanejamento_f6: []
atualizado_em: {{AAAA-MM-DD}}
historico: []
---

# Planejamento — {{slug-da-feature}}

> Artefato de **método** da `sprintx`: o estado durável do laço F3 ↔ F5 e do retorno da F6 ao
> planejamento (`replanejar_execucao`). Não é task, não é
> produto, não é entrega e não é desvio. Nasce na F1 e é reescrito **somente** por
> `scripts/planejamento.sh` (caminho relativo à raiz da skill) — nunca à mão. Contrato em
> `references/00-schema.md`, `kind: planejamento`.

<!-- sprintx:estado -->
Estado: `{{estado-ou-null}}` · reprovações da F5: {{n}} · atualizado em {{AAAA-MM-DD}}.

Nenhuma rodada da F5 registrada.
<!-- /sprintx:estado -->

<!--
Forma de cada rodada no frontmatter, acrescentada pelo script a cada veredito da F5
(append-only: rodada anterior nunca é reescrita nem removida):

historico:
  - rodada: 1
    veredito: nao
    altas: 6
    medias: 2
    baixas: 5
    auditado_em: {{AAAA-MM-DD}}

Durante uma rodada de replanejamento da execução (retorno da F6), o script preenche
`bloqueios_replanejamento_f6` com os B-NN `defeito_de_plano` que a abriram, em ordem de id,
e congela as tasks concluídas em `tasks_congeladas` + `assinatura_congeladas`. O trabalho
parcial da task bloqueada que ficou na árvore vai para `parciais_replanejamento_f6`, um item
por caminho, em ordem de byte do caminho:

parciais_replanejamento_f6:
  - path: "tests/menu/perfil.test.ts"
    task: T-04.03
    estado: novo
    hash: {{id-do-blob-git}}

Ao fechar a rodada as quatro voltam a `[]`, `[]`, `null` e `[]` — o trabalho parcial continua
na árvore, com a task reaberta.

Quando o retorno da F6 é recusado por motivo operacional, o script grava o estado terminal
`replanejamento_execucao_recusado` e, logo depois de `estado`, a chave
`recusa_replanejamento_f6: <classes_mistas|orcamento_f6_legado|orcamento_f6_nao_declarado|planejamento_legado>`,
que só existe nesse estado.
-->
