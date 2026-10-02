---
expx_schema: 1
expx_tool: sprintx
kind: estimativa
trabalho_id: {{slug-da-feature}}
gerada_em: {{AAAA-MM-DD}}
atualizado_em: {{AAAA-MM-DD}}
unidade: h
esforco_total_min: {{numero}}
esforco_total_max: {{numero}}
caminho_critico_min: {{numero}}
caminho_critico_max: {{numero}}
confianca: {{alta | media | baixa}}
confianca_motivo: {{motivo derivado dos sinais, uma linha}}
fator_correcao_aplicado: {{numero ou null}}
metodo_agregacao: pert_quadratura
tasks_estimadas: {{numero}}
premissas: [{{premissa verificavel em uma linha}}]
invalidadores: [{{fato observavel que obriga a refazer a estimativa}}]
nao_incluido: [{{o que a faixa deliberadamente nao cobre}}]
tasks_a_quebrar: [{{T-NN.MM}}]
---

> Substitua TODOS os marcadores `{{...}}`. Roteiro operacional em `references/07-estimativa.md`.
> Frontmatter sem acento em chave nem em valor de enum; datas em `AAAA-MM-DD` obtidas com `date +%Y-%m-%d`.
> `min` e `max` são sempre diferentes: número único é proibido pelo método.

# Estimativa — {{título da feature}}

{{Se a confiança for BAIXA, esta é a PRIMEIRA linha do documento, antes de qualquer número:}}
{{**Confiança BAIXA. Para subir: <ação específica, verificável, curta, nomeando o artefato>.**}}

{{Se não existir `docs/sprintx/estimativas/HISTORICO.md`, esta linha vem em seguida:}}
{{**Não há base de calibração neste projeto:** `docs/sprintx/estimativas/HISTORICO.md` não existe. As faixas vêm de julgamento sobre o plano, sem desvio histórico para corrigi-las. Por isso a confiança não passa de MÉDIA.}}

## Faixa

| | Faixa | O que é |
|---|---|---|
| **Esforço total** | **{{min}}–{{max}} h** | todo o trabalho a ser feito, paralelo ou não — é o que se cobra |
| **Caminho crítico** | **{{min}}–{{max}} h** | a cadeia de dependências mais longa — é o que limita o calendário |

**Por que os dois números são diferentes:** {{uma frase nomeando o que roda em paralelo. Ex.: "T-02.03, T-02.04, T-03.01 e T-03.02 são paralelizáveis e somam no esforço total sem alongar a cadeia F-01.1 → F-02.1 → F-03.2, que é o caminho crítico."}}

> **Esforço não é prazo.** A conversão em data depende da disponibilidade do time, de feriado, férias, revisão e ida e volta com o cliente — variáveis que esta estimativa não conhece. A conversão é decisão de quem conhece a agenda.

Unidade: hora de trabalho focado. Método de agregação: PERT com variâncias somadas em quadratura (fórmulas na seção "Como a conta foi feita").

## Por sprint e fase

| Sprint / Fase | Tasks | Faixa | Sinais predominantes |
|---|---|---|---|
| sprint-{{NN}} | {{n}} | {{min}}–{{max}} h | {{sinais}} |
| — F-{{NN}}.{{M}} {{título}} | {{n}} | {{min}}–{{max}} h | {{sinais}} |
| — F-{{NN}}.{{M}} {{título}} | {{n}} | {{min}}–{{max}} h | {{sinais}} |

## Por task

| Task | Tipo | o | m | p | Média | Faixa | Sinais aplicados | Comparável no histórico |
|---|---|---|---|---|---|---|---|---|
| T-{{NN}}.{{MM}} | {{tipo_task}} | {{o}} | {{m}} | {{p}} | {{media}} | {{min}}–{{max}} h | {{sinal, sinal}} | {{trabalho/task ou "nenhum"}} |

## Tasks a quebrar — não estimadas

{{Toda task cuja faixa pessimista supera quatro vezes a otimista entra aqui e NÃO entra nos totais.}}

| Task | o | p | p/o | O que precisa ser esclarecido para quebrá-la |
|---|---|---|---|---|
| T-{{NN}}.{{MM}} | {{o}} | {{p}} | {{razao}}× | {{uma frase específica}} |

{{ou "Nenhuma: todas as tasks passaram no portão de compreensão (p ≤ 4 × o)."}}

Estas tasks não estão no esforço total nem no caminho crítico. A correção é na F3: quebrar a task, e reestimar depois.

## Itens fora das tasks

{{Só existe se algo da lista "Não incluído" for deliberadamente incluído. Cada item tem faixa própria e nunca é diluído dentro das tasks.}}

| Item | Faixa | Por que está incluído |
|---|---|---|
| {{ex.: homologação assistida com o cliente}} | {{min}}–{{max}} h | {{motivo}} |

{{ou "Nenhum: a faixa cobre apenas o trabalho descrito nas tasks."}}

## Premissas

O que foi assumido como verdadeiro. Se uma delas for falsa, a faixa muda.

- {{premissa verificável hoje, nomeando o artefato que a sustenta}}
- {{premissa verificável hoje, nomeando o artefato que a sustenta}}

## Invalidadores

O que, se acontecer, torna esta estimativa sem valor e obriga a refazê-la. Cada um é um fato **observável**.

- {{fato observável específico deste trabalho, nomeando o que ele contradiz — uma decisão D-NN, um arquivo da base, uma task}}
- {{fato observável específico deste trabalho}}

> Teste antes de gravar: se o invalidador puder ser colado em outro projeto sem trocar uma palavra, ele é genérico. Reescreva. "Mudança de escopo" não é invalidador; "o cliente pedir suporte a mais de um formato de arquivo" é.

## Não incluído

O que esta faixa deliberadamente não cobre:

- reunião, alinhamento e cerimônia
- revisão de código e ida e volta do pull request
- ida e volta com o cliente (dúvida, aprovação, homologação)
- deploy e acompanhamento de subida
- correção pós-entrega e garantia
- treinamento, documentação de usuário e passagem de conhecimento
- gestão do projeto
- {{acrescente o que mais for específico deste trabalho}}

## Confiança

**{{ALTA | MÉDIA | BAIXA}}** — {{motivo derivado dos sinais, citando quais}}.

{{Se BAIXA, repita aqui a ação para subir o nível e diga quanto ela custa aproximadamente. Quase sempre é uma investigação curta que vale mais que uma estimativa apressada.}}

## Calibração

- Histórico consultado: {{`docs/sprintx/estimativas/HISTORICO.md` (N entradas) | "não existe neste projeto"}}
- Fator de correção aplicado: {{ex.: "1,16× nas tasks de tipo `integracao_externa`, vindo de um desvio médio de 1,16 em 4 entradas elegíveis" | "nenhum"}}
- Origem da calibração (DS-165): {{persistido | recomputado | nenhum — canônico sem fator ativo}}
- Divergência encontrada (DS-165): {{"nenhuma — o bloco `calibracao` gravado confere com o canônico" | "o bloco `calibracao` gravado trazia <valor stale>; o canônico recomputado das entradas elegíveis é <valor canônico>" | "não se aplica — HISTORICO.md ausente"}}

O fator de correção é sempre visível. Fator embutido em silêncio é indistinguível de número inventado.

O fator é o `desvio_medio` do **canônico vigente** daquele tipo (DS-165, ver parágrafo seguinte) — persistido quando o bloco `calibracao` confere, recomputado quando diverge —, nunca o bloco gravado copiado às cegas: duas casas decimais, meio para cima (half-up) — `1,16`, `1,20`, nunca `1,2` nem `1,157` (DS-160). Ele entra na faixa de cada task daquele tipo **antes da agregação**; o arredondamento à hora inteira da faixa agregada vem depois, por último. `fator_correcao_aplicado` no frontmatter leva o mesmo número com ponto (`1.16`).

Antes de aplicar, a leitura **confere** o bloco `calibracao` gravado contra o canônico recomputado das `entradas` persistidas daquele tipo (DS-165). Com o canônico ativo, a origem da calibração é `persistido` quando bate, ou `recomputado` quando diverge — e, na divergência, o fator vem do canônico recomputado, nunca do bloco gravado às cegas, nunca da média das razões brutas `real / estimado_media`. Quando o canônico tem `fator_ativo: false` — menos de 3 entradas elegíveis, ou `HISTORICO.md` ausente —, não há fator nenhum para aplicar: a origem da calibração é `nenhum — canônico sem fator ativo` e `fator_correcao_aplicado` é `null`, **mesmo que o bloco gravado divergente dissesse `fator_ativo: true`** — o canônico decide se há fator, nunca o que o bloco stale afirma. Sem `HISTORICO.md`, não existe bloco `calibracao` nenhum para comparar: a `Divergência encontrada` não é "confere" nem "diverge", é `não se aplica — HISTORICO.md ausente`, e a origem da calibração é obrigatoriamente `nenhum — canônico sem fator ativo` — os dois campos consistentes, porque sem nada gravado não há o que divergir, e também não há fator. A divergência e a origem vêm declaradas acima, e a confiança desta estimativa não passa de `media`. A F3.5 nunca escreve nem migra o `HISTORICO.md`: a cura do bloco `calibracao` fica para o próximo fechamento (F6).

## Como a conta foi feita

Método: **PERT com variâncias somadas em quadratura**. Reproduzível à mão.

Por task estimada:

```
media_task         = (o + 4m + p) / 6
desvio_padrao_task = (p - o) / 6
```

> **`desvio_padrao_task` é dispersão, em horas.** É o desvio-padrão PERT da task, e é só ele que entra na quadratura abaixo — nunca o `desvio_calibracao_task`, que é a razão de calibração do `HISTORICO.md`, **adimensional**, e nunca entra em quadratura nenhuma. As duas grandezas não são intercambiáveis (DS-162).

Por conjunto (fase, sprint, trabalho, caminho crítico):

```
media_conjunto  = soma das media_task
desvio_conjunto = raiz_quadrada( soma dos (desvio_padrao_task)^2 )
piso_conjunto   = soma( o(t) * fator(t) )
fator(t) = 1                                # quando o tipo da task t nao tem fator ativo
min = media_conjunto - desvio_conjunto      # se min < piso_conjunto, entao min = piso_conjunto
max = media_conjunto + desvio_conjunto
```

O piso é a soma dos otimistas **já corrigidos pelo fator do tipo de cada task** — nunca a maior `o`, nunca um fator único do conjunto —, e o gatilho compara contra o mesmo `piso_conjunto` que atribui. O clamp acontece **antes** do arredondamento `floor(min)`/`ceil(max)` à hora inteira, que é o último passo (DS-163, que estende DS-41).

Somar variâncias em quadratura faz o intervalo crescer menos que a soma linear: os desvios se compensam entre tasks, e supor que tudo dá errado ao mesmo tempo superestimaria grosseiramente. Por construção, a faixa agregada é sempre mais estreita que `[ soma( o(t) * fator(t) ), soma( p(t) * fator(t) ) ]` — os limites corrigidos task a task, pelos mesmos fatores que entraram na agregação.

O **caminho crítico** usa as mesmas fórmulas, mas apenas sobre as tasks da cadeia de dependências mais longa: {{lista dos ids da cadeia}}. Tasks paralelizáveis somam no esforço total e não somam aqui.
