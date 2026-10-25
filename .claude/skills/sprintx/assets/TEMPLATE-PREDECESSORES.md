---
expx_schema: 1
expx_tool: sprintx
kind: predecessores
trabalho_id: {{trabalho_id}}
predecessores: []
criado_em: {{data}}
atualizado_em: {{data}}
---

# Predecessores — {{trabalho_id}}

Documentos consumidos antes do planejamento SprintX. A máquina usa somente o frontmatter; esta prosa repete caminho, origem e papel para leitura humana.

`predecessores: []` declara ausência, não omissão. O verificador só aceita essa forma
quando o histórico Git prova que nenhum `docs/superpowers/**` elegível existiu em commit
estritamente anterior ao nascimento do planejamento; o V9 registra essa prova como N/A.
