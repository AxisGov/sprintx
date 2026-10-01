---
expx_schema: 1
expx_tool: sprintx
kind: estimativa_historico
trabalho_id: null
atualizado_em: {{AAAA-MM-DD}}
unidade: h
entradas:
  - trabalho_id: {{slug-do-trabalho}}
    task_id: T-{{NN}}.{{MM}}
    tipo_task: {{config | client | dominio | persistencia | api | ui | integracao_externa | teste | infra | refatoracao}}
    area: {{area ou modulo tocado, uma linha}}
    sinais: [{{sem_cobertura, integracao_externa}}]
    estimado_min: {{numero ou null}}
    estimado_max: {{numero ou null}}
    estimado_media: {{numero ou null}}
    real: {{numero}}
    desvio: {{numero ou null}}
    duracao_observada: {{numero ou null}}
    registrado_em: {{AAAA-MM-DD}}
calibracao:
  - tipo_task: {{tipo}}
    entradas: {{numero}}
    desvio_medio: {{numero}}
    fator_ativo: {{true | false}}
---

> Substitua TODOS os marcadores `{{...}}`. Roteiro operacional em `references/07-estimativa.md`.
> Este arquivo é do PROJETO, não de um trabalho: vive em `docs/sprintx/estimativas/HISTORICO.md` e acumula entradas de todos os trabalhos. Por isso `trabalho_id` no cabeçalho é `null` — o `trabalho_id` de cada linha vive dentro de `entradas:`.
> Este é o único arquivo da skill que é APENDADO, nunca sobrescrito. Trabalho novo acrescenta entradas; entrada antiga não se apaga nem se reescreve.

# Histórico de esforço — calibração das estimativas

Uma linha por task concluída, com o esforço real medido. É a única base de calibração real do projeto: sem ele, toda estimativa fica com confiança no máximo MÉDIA.

Unidade: hora de trabalho focado. O real é o esforço efetivamente gasto na task — escrever os dois testes, implementar, rodar a suíte e verificar o critério de aceite. Não inclui reunião, revisão, deploy nem ida e volta com o cliente: esses são "não incluído" na estimativa e precisam continuar fora aqui, senão a calibração fica corrompida.

A **duração observada** é outra coisa: o tempo de parede entre `task_iniciada` e `task_concluida` no rastro, obtido sem ninguém anotar nada. Ela entra ao lado do real, nunca no lugar dele, e não entra no desvio nem na calibração — tempo de parede não é esforço, e uma task aberta por seis horas pode ter tido vinte minutos de trabalho e um almoço no meio.

## Entradas

| Trabalho | Task | Tipo | Área | Sinais | Estimado (min–max) | Média est. | Real | Desvio | Duração observada |
|---|---|---|---|---|---|---|---|---|---|
| {{slug}} | T-{{NN}}.{{MM}} | {{tipo_task}} | {{area}} | {{sinais}} | {{min}}–{{max}} h | {{media}} h | {{real}} h | {{desvio}} | {{duracao_observada em h, ou — quando null}} |

{{Trabalho que rodou sem a F3.5 entra assim: estimado_min, estimado_max, estimado_media e desvio em `null`, com o real preenchido. O real ainda alimenta a comparabilidade por tipo e área.}}

{{Sem o par `task_iniciada`/`task_concluida` no rastro, `duracao_observada` fica em `null` — o campo é opcional, e entrada antiga sem a chave continua válida. Entrada sem duração observada não perde nada: a calibração nunca a lê.}}

> **Célula sem valor.** Quando o campo é `null` no YAML, a célula correspondente da tabela leva `—`, nunca `null` e nunca `null h`: a unidade só acompanha número. É a regra universal 7 aplicada à ausência — o YAML diz `null`, a prosa mostra que não há valor, e as duas continuam dizendo a mesma coisa.

## Calibração por tipo de task

`desvio_medio` é a média dos desvios **persistidos** das entradas encerradas daquele tipo — a coluna `Desvio` da tabela acima, nunca a média das razões brutas. `1,00` é o alvo; `1,40` significa que aquele tipo de task leva, em média, 40% a mais que o estimado.

| Tipo de task | Entradas | Desvio médio | Fator ativo? |
|---|---|---|---|
| {{tipo_task}} | {{n}} | {{desvio}} | {{sim, aplicado como fator ×{{desvio}} | não — menos de 3 entradas}} |

> **Calibração vazia.** `calibracao: []` no YAML — nenhum tipo com desvio calculável ainda, o caso normal do primeiro trabalho do projeto e de todo trabalho que rodou sem a F3.5 — renderiza esta tabela com cabeçalho e separador e **sem nenhuma linha de dados**. Há exatamente uma linha de dados por item de `calibracao`, e o primeiro campo dela é sempre um valor do enum `tipo_task`: linha de dados sem item correspondente no frontmatter é proibida. Nunca fabrique uma linha para a tabela não ficar vazia, e nunca use `—`, `n/a`, célula vazia ou qualquer outra sentinela como se fosse linha — a regra da **Célula sem valor** acima vale para célula de uma linha real, nunca para a linha inteira, e `| — | — | — | — |` anuncia um `tipo_task` que não existe no enum, o que se lê como tabela corrompida e não como ausência de calibração. Tabela só com cabeçalho e separador é a forma correta, e fiel ao YAML, de dizer que ainda não há calibração.

**Regra do fator.** O desvio de um tipo só vira fator de correção nas estimativas seguintes a partir de **3 entradas encerradas** daquele tipo — abaixo disso é ruído. Quando aplicado, o fator é **sempre declarado na saída da estimativa**, nunca embutido em silêncio.

## Como se calcula o desvio

```
desvio_calibracao_task  = arredonda( real / media_task_estimada )   # media_task = (o + 4m + p) / 6
desvio_medio_do_tipo    = arredonda( media dos desvio_calibracao_task PERSISTIDOS daquele tipo )
arredonda(x)            = duas casas decimais, meio para cima (half-up)
```

> **`desvio_calibracao_task` é razão, adimensional.** É quanto o `real` excedeu o `estimado_media` da task — nunca o `desvio_padrao_task` da `references/07-estimativa.md`, que é o desvio-padrão PERT de uma estimativa, medido em **horas**. As duas grandezas não são intercambiáveis, e nenhum dos dois símbolos vira chave em disco: o que se persiste aqui continua sendo `desvio` e `desvio_medio` (DS-162).

> **Precisão e desempate.** São **duas casas decimais**, com desempate **half-up**: terceira casa exatamente `5`, a segunda sobe. A razão `1,125` vira `1,13`, nunca `1,12`. As duas casas são **fixas**, não "até duas": a razão `1,2` grava-se `1.20` no YAML e escreve-se `1,20` na prosa. O YAML usa ponto, a prosa em pt-BR usa vírgula, e as duas carregam as mesmas duas casas (regra universal 7); só a sintaxe de fórmula do bloco acima fica fora disso. Número com uma casa, ou com três, é número fora do contrato (DS-160).
>
> **O arredondamento tem estágio.** Cada `desvio` é arredondado **antes** de ser persistido, e é o valor persistido que entra na média — a média das razões brutas é outro número. A média é então arredondada de novo pela mesma regra. Sem a ordem fixa, dois executores honestos gravam `1,16` e `1,15` do mesmo histórico.

**Exemplo completo.** Quatro entradas encerradas de `integracao_externa`:

| `estimado_media` | `real` | razão | `desvio` persistido |
|---|---|---|---|
| 4.0 | 4.5 | 1,125 | `1.13` — empate exato, half-up sobe |
| 4.0 | 4.5 | 1,125 | `1.13` |
| 3.0 | 3.5 | 1,1666… | `1.17` |
| 1.0 | 1.2 | 1,2 | `1.20` — duas casas fixas, nunca `1.2` |

A média dos quatro persistidos é `(1,13 + 1,13 + 1,17 + 1,20) / 4 = 1,1575`, que arredonda para **`desvio_medio: 1.16`**. Com `entradas: 4`, `fator_ativo: true`. Se a média saísse das razões brutas, ou se o empate descesse, o número gravado seria `1,15` — e as estimativas seguintes publicariam outra faixa.

## Como esta tabela é alimentada

Ao concluir cada task na F6, o esforço real daquela task é anotado. Ao fim do trabalho, a F6 acrescenta as entradas aqui e recalcula a tabela de calibração por tipo. Detalhe em `references/06-execucao.md`; o uso na estimativa, em `references/07-estimativa.md`.
