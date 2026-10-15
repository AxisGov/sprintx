---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: {{slug-da-feature}}
sprint_id: sprint-{{NN}}
atualizado_em: {{AAAA-MM-DD}}
sprint:
  titulo: {{titulo da sprint, uma linha}}
  status: {{nao_iniciado | em_andamento | bloqueado | concluido}}
  criterio_saida: {{condicao verificavel, uma linha}}
  riscos: [{{risco, uma linha}}]
  fora_de_escopo: [{{o que foi percebido e NAO sera tocado}}]
fases:
  - id: F-{{NN}}.1
    titulo: {{titulo da fase}}
    status: {{nao_iniciado | em_andamento | bloqueado | concluido}}
    criterio_saida: {{condicao verificavel, binaria, uma linha}}
    paralelizavel: false
    paralela_com: []
    tasks: [T-{{NN}}.01, T-{{NN}}.02]
tasks:
  - id: T-{{NN}}.01
    titulo: {{titulo curto, sem acento, uma linha}}
    fase: F-{{NN}}.1
    status: pendente
    objetivo: {{uma frase}}
    arquivos:
      cria: [{{caminho/relativo/novo.ext}}]
      altera: []
    teste_integracao: {{o que valida, contra o que - uma frase, OBRIGATORIO}}
    teste_funcional: {{o que valida, com qual entrada e saida - uma frase, OBRIGATORIO}}
    criterio_aceite: {{condicao verificavel, binaria, sem adjetivo}}
    depende_de: []
    paralelizavel: false
    concluida_em: null
    suite: nao_executada
  - id: T-{{NN}}.02
    titulo: {{titulo curto, sem acento, uma linha}}
    fase: F-{{NN}}.1
    status: pendente
    objetivo: {{uma frase}}
    arquivos:
      cria: []
      altera: [{{caminho/relativo/existente.ext}}]
    teste_integracao: {{o que valida, contra o que - uma frase, OBRIGATORIO}}
    teste_funcional: {{o que valida, com qual entrada e saida - uma frase, OBRIGATORIO}}
    criterio_aceite: {{condicao verificavel, binaria, sem adjetivo}}
    depende_de: [T-{{NN}}.01]
    paralelizavel: false
    concluida_em: null
    suite: nao_executada
---

> Frontmatter obrigatorio (expx-schema v1). Formato completo em `references/00-schema.md`.
> Substitua TODOS os marcadores; NUNCA omita uma chave — ausente e `null`, lista vazia e `[]`.
>
> **Um unico bloco YAML.** Os leitores de frontmatter param no primeiro `---` de fechamento:
> um segundo bloco neste arquivo seria invisivel para os hooks de metodo.
>
> **Este arquivo se chama `sprint-NN/tasks.md`.** O nome nao muda — e o caminho que os hooks
> procuram. Use este template apenas quando a sprint tem UMA fase; com duas ou mais, use
> `TEMPLATE-sprint.md`, `TEMPLATE-fases.md` e `TEMPLATE-tasks.md`, os tres arquivos de sempre.
>
> A escolha e por SPRINT, nao pelo trabalho inteiro: num plano de tres sprints, cada uma vai
> no formato que couber.
>
> **Sem diagrama.** O grafo visual de tasks so existe no formato de tres arquivos, dentro de
> `fases.md`. Aqui a estrutura vive inteira no frontmatter (`fases`, `tasks`, `depende_de`,
> `paralelizavel`) — a ausencia de grafo neste arquivo e o formato, nao uma lacuna.

# Plano — Sprint {{NN}} — {{título da sprint}}

## Objetivo da sprint

{{O que esta sprint entrega, em uma ou duas frases.}}

## Critério de saída da sprint

{{Condição verificável, binária, sem adjetivo. Inclua a suíte inteira verde: é neste portão
que ela é cobrada. Ex.: "a suíte roda com `<comando>` e termina com 0 failed".}}

## Riscos conhecidos

- {{risco vindo da base ou das decisões, com referência ao arquivo que o registra}}
- {{ou "Nenhum risco registrado."}}

## Fora de escopo

- {{o que não será tocado}} — {{por quê}}

## Fase F-{{NN}}.1 — {{título da fase}}

**Objetivo:** {{o que esta fase entrega}}

**Tasks:** T-{{NN}}.01, T-{{NN}}.02

**Critério de saída:** {{condição verificável e binária}}

**Roda em paralelo com:** nenhuma.

## Tasks

---

```yaml
id: T-{{NN}}.01
titulo: {{título curto da task}}
objetivo: {{uma frase}}
arquivos:
  cria: [{{caminho/relativo/novo.ext}}]
  altera: []
teste_integracao: {{o que valida, contra o quê — em uma frase}}
teste_funcional: {{o que valida, com qual entrada e qual saída — em uma frase}}
criterio_aceite: {{condição verificável, binária, sem adjetivo}}
depende_de: []
paralelizavel: false
status: pendente
```

---

```yaml
id: T-{{NN}}.02
titulo: {{título curto da task}}
objetivo: {{uma frase}}
arquivos:
  cria: []
  altera: [{{caminho/relativo/existente.ext}}]
teste_integracao: {{o que valida, contra o quê — em uma frase}}
teste_funcional: {{o que valida, com qual entrada e qual saída — em uma frase}}
criterio_aceite: {{condição verificável, binária, sem adjetivo}}
depende_de: [T-{{NN}}.01]
paralelizavel: false
status: pendente
```
