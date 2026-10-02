# F3.5 — ESTIMATIVA (opcional)

Você está na F3.5. Seu objetivo é converter um plano pronto em uma **faixa de esforço** auditável, com premissas, invalidadores e nível de confiança declarados.

Esta fase é **opcional**. Ela não é pré-requisito da F4: se o usuário não pediu estimativa, siga direto para a F4 lendo `references/04-orquestrador.md`. Estimativa ausente nunca bloqueia nada.

Nesta fase você não escreve código de implementação, não altera o plano e não pergunta nada ao usuário.

## Princípio central

**Estimativa é declaração de incerteza, não promessa de prazo.**

Duas consequências duras, que valem em cada linha que você escrever nesta fase:

- **Número único é proibido.** Toda estimativa — de task, de fase, de sprint, do trabalho inteiro — sai como faixa `min–max`, sempre acompanhada das premissas que a sustentam e do que a invalidaria. Número único vira compromisso, e compromisso construído sobre incerteza é dívida.
- **A unidade é esforço, nunca prazo de calendário.** A unidade é a **hora de trabalho focado** (`h`). Converter esforço em data depende de disponibilidade do time, feriado, férias, revisão e ida e volta com o cliente — variáveis que esta skill não conhece e não vai fingir conhecer. A conversão em data é decisão de quem conhece a agenda do time, e a saída diz isso explicitamente.

Você nunca escreve "entrega em 12 dias", "duas semanas", "fica pronto na sexta" nem qualquer data de entrega. Você escreve "78–121 h de esforço" e deixa a conversão para o humano.

## Pré-requisitos verificáveis

- `docs/sprintx/features/<slug>/sprint-01/` existe com uma sprint válida em um dos dois formatos do contrato — condensado (`tasks.md` com `kind: plano`) ou três arquivos (`sprint.md`, `fases.md`, `tasks.md`), regra única em `references/00-schema.md` — a F3 aconteceu.
- Se não existe, o plano não existe: diga "Falta a F3 (plano). Não dá para estimar antes de existir task." e execute `references/03-plano.md` primeiro. Estimar antes de existir task é chute com aparência de método.
- `docs/sprintx/features/<slug>/base/` e `docs/sprintx/features/<slug>/00-DECISOES.md` existem (você vai ler as lacunas e as decisões para derivar sinais e confiança).

Leia, antes de estimar: o plano de cada sprint no formato que ela tiver (no condensado, sprint, fases e tasks saem do frontmatter do próprio `tasks.md`; nos três arquivos, de `tasks.md` e `fases.md`), `base/00-LACUNAS.md`, `00-DECISOES.md` e — se existir — `docs/sprintx/estimativas/HISTORICO.md`.

## Passo 1 — Consultar o histórico de calibração

Se `docs/sprintx/estimativas/HISTORICO.md` existe, leia-o **antes** de estimar qualquer task. Ele é a única fonte de calibração real do projeto.

Para cada task que você vai estimar, procure no histórico entradas comparáveis por, nesta ordem de prioridade:

1. **tipo de task** (ver a taxonomia do Passo 2);
2. **área do sistema** tocada (o mesmo módulo/pasta, ou a mesma área da base);
3. **sinais** aplicados (integração externa, migração de banco, ausência de cobertura...).

Uma entrada é comparável quando bate no tipo **e** em pelo menos um dos outros dois eixos. Registre, para cada task, quais entradas do histórico você usou como comparável — isso vai para a prosa da saída.

**Fator de correção.** O histórico traz, por tipo de task, o desvio médio entre estimado e real (ver Passo 8). Quando existir desvio calculado para um tipo com **3 ou mais** entradas elegíveis — as entradas daquele tipo com `desvio` numérico, não nulo (DS-164) —, aplique-o como fator multiplicativo à faixa das tasks daquele tipo, e **declare o fator na saída, task a task e no total**. Fator de correção nunca é aplicado em silêncio: um número corrigido sem o fator visível é indistinguível de um número inventado.

**O fator é o `desvio_medio` persistido**, lido do `HISTORICO.md` como está — duas casas decimais, half-up (DS-160) —, sem recalcular nada a partir das entradas e sem reduzir ou ampliar as casas. Ele entra na faixa da task daquele tipo **antes da agregação**: multiplica `media_task` e `desvio_padrao_task` de cada task do tipo, e só então o Passo 5 agrega. O arredondamento `floor(min)`/`ceil(max)` à hora inteira é o **último passo** da faixa agregada, nunca um estágio intermediário — arredondar antes do fator, ou arredondar o fator, publica outra faixa.

**Exemplo de impacto.** Duas tasks `integracao_externa` — `o=4 m=5 p=12` (média 6,00, desvio 1,33) e `o=3 m=4 p=5` (média 4,00, desvio 0,33) — com o fator canônico `1.16`: média agregada `11,60`, desvio agregado `1,59`, faixa `10,01–13,19`, publicada **10–14 h**. Com `1,15`, o número que sai de um arredondamento não canônico do mesmo histórico, a faixa publicada vira **9–14 h**. A casa decimal do fator não é detalhe de apresentação: ela muda a hora que se cobra.

Com menos de 3 entradas elegíveis do tipo, o desvio é ruído: **não** aplique fator, e diga na saída que o histórico tem entradas insuficientes daquele tipo. Entrada daquele tipo com `desvio: null` não entra nessa conta — o item da `calibracao` pode existir com `fator_ativo: false`, e é o `fator_ativo` que manda.

**Conferência do bloco persistido, nunca confiança cega (DS-165).** Antes de aplicar o `desvio_medio` persistido, recompute o canônico daquele `tipo_task` a partir dos `desvio` já persistidos nas `entradas` — nunca de `real / estimado_media`, que é a razão bruta e não o que a calibração agrega: `entradas` = a contagem das elegíveis (DS-164), `desvio_medio` = a média delas pela precisão da DS-160, `fator_ativo` = `true` a partir de 3. Confira esse canônico contra o bloco `calibracao` gravado no `HISTORICO.md`.

- **Bate, com fator ativo no canônico:** aplique o `desvio_medio` persistido, como já descrito acima. A origem da calibração (DS-165) é `persistido`.
- **Diverge, com fator ativo no canônico:** nunca aplique o bloco stale. Recompute o fator a partir do canônico recém-calculado — e só dele — e aplique esse valor. Declare na saída, nesta task e no total, a divergência encontrada: o que estava gravado e o que o canônico manda, e que a origem da calibração é `recomputado`. Uma divergência detectada **reduz o teto de confiança a `media`** (Passo 7), mesmo com um fator canônico ativo sendo aplicado — a leitura está corrigindo ao vivo um histórico que não bate com o próprio contrato, e isso não é a mesma coisa que um histórico limpo e comparável.
- **Canônico sem fator ativo** (menos de 3 entradas elegíveis daquele tipo) **— bata ou divirja o bloco gravado:** não aplique fator nenhum, mesmo que o bloco stale dissesse `fator_ativo: true`. `fator_correcao_aplicado` é `null` (DS-46) e a origem da calibração declarada é `nenhum — canônico sem fator ativo`. Um bloco gravado divergente que mente sobre ter fator ativo não ganha um fator por isso: a elegibilidade é a da DS-164, não a do que está escrito.

**Exemplo de divergência com fator ativo.** Para `integracao_externa`, o bloco gravado traz `entradas: 5`, `desvio_medio: 0.93`, `fator_ativo: true` — herança de uma leitura que contava a entrada de `desvio: null` como zero (o defeito que a DS-164 fechou). As entradas persistidas do tipo trazem `desvio` `1.13`, `1.13`, `1.17`, `1.20` e uma quinta `null`. O canônico, recomputado só das quatro elegíveis, é `entradas: 4`, `desvio_medio: 1.16`, `fator_ativo: true` (o mesmo exemplo da DS-160, Passo 10). O fator efetivamente aplicado é `1,16`, com origem da calibração `recomputado`; a divergência `0,93 → 1,16` vai declarada na saída, e a confiança desta estimativa não passa de `media`. O fator **nunca** é `1,15` — a média das razões brutas `real / estimado_media`, sem passar pelos `desvio` persistidos — nem `0,93` — o valor stale que a conferência descartou.

**Exemplo de divergência sem fator ativo.** Para `api`, o bloco gravado traz `entradas: 4`, `desvio_medio: 0.63`, `fator_ativo: true` — a mesma herança da contagem de nulas como zero. As entradas persistidas do tipo trazem `desvio` `1.20`, `1.30` e duas `null`. O canônico, recomputado só das duas elegíveis, é `entradas: 2`, `desvio_medio: 1.25`, `fator_ativo: false` — menos de 3 entradas elegíveis, mesmo com o bloco stale dizendo o contrário. `fator_correcao_aplicado` é `null`, a origem da calibração declarada é `nenhum — canônico sem fator ativo`, a divergência `entradas: 4 → 2` vai declarada na saída, e a confiança não passa de `media`. Note a diferença para o exemplo anterior: ali a divergência corrige o NÚMERO do fator (de `0,93` para `1,16`, ambos ativos); aqui a divergência corrige se HÁ fator — e a resposta correta é que não há.

**A F3.5 nunca escreve nem migra o `HISTORICO.md`.** Ela só lê. Encontrar divergência não autoriza esta fase a corrigir o arquivo: a cura do bloco `calibracao` acontece só no próximo fechamento (F6, Passo 10), que recalcula e regrava esse bloco a partir das mesmas `entradas`. As `entradas` persistidas são append-only e não se alteram nem aqui nem lá; é o bloco `calibracao` — derivado e regravável — que a F6 substitui a cada fechamento.

**Um trabalho mistura tipos de task — o fator é sempre calculado por tipo (DS-166).** Repita a conferência da DS-165 **para cada `tipo_task` presente** no trabalho, nunca uma vez só para o trabalho inteiro: cada tipo tem seu próprio canônico, sua própria origem e sua própria divergência. Grave o resultado por tipo em `calibracao_por_tipo` (Passo 8). O escalar legado `fator_correcao_aplicado` é **derivado** dessa coleção, nunca calculado em paralelo a ela: é o número quando todos os tipos presentes concordam no mesmo fator ativo, é `null` quando nenhum tipo presente tem fator ativo, e é o literal `por_tipo` em qualquer mistura — fator ativo e inativo, ou fatores ativos diferentes entre os tipos presentes. Um consumidor que só lê `fator_correcao_aplicado` e não conhece `calibracao_por_tipo`, ao encontrar `por_tipo`, declara a estimativa indisponível e não a usa — nunca coerção, média ou escolha arbitrária.

**Sem `HISTORICO.md`:** estime mesmo assim. Duas obrigações:

- a confiança fica **no máximo `media`** (nunca `alta`), qualquer que seja o resto dos sinais;
- a saída diz explicitamente, em uma linha própria: "Não há base de calibração neste projeto: `docs/sprintx/estimativas/HISTORICO.md` não existe. As faixas vêm de julgamento sobre o plano, sem desvio histórico para corrigi-las."
- `fator_correcao_aplicado: null` no frontmatter, com origem da calibração `nenhum — canônico sem fator ativo` (DS-165) — o mesmo rótulo do canônico sem entradas elegíveis suficientes, porque o efeito é o mesmo: não há fator nenhum para aplicar;
- a `Divergência encontrada` (DS-165) é `não se aplica — HISTORICO.md ausente`: sem o arquivo não existe bloco `calibracao` nenhum para comparar — não é "confere" (não há com o que bater) nem "diverge" (não há o que divergir), é um terceiro estado, de ausência. Os dois campos ficam consistentes: sem `HISTORICO.md` não há como haver divergência, porque não há nada gravado, e também não há fator.

## Passo 2 — Classificar cada task por tipo

O tipo é o que torna uma task comparável a outra, no histórico e entre projetos. Use exatamente esta taxonomia (valores do enum `tipo_task`, minúsculos e sem acento):

| `tipo_task` | O que é |
|---|---|
| `config` | configuração, variáveis de ambiente, scaffolding, harness de teste, fixtures |
| `client` | cliente/adaptador de API ou serviço, wrapper de SDK, camada de acesso |
| `dominio` | regra de negócio, cálculo, validação, máquina de estados |
| `persistencia` | schema, repositório, query, migração de banco |
| `api` | endpoint, contrato de entrada/saída, serialização |
| `ui` | tela, componente, formulário, layout |
| `integracao_externa` | fala com sistema de terceiro sobre o qual não temos controle |
| `teste` | teste que é a entrega em si (harness, caracterização, suíte de contrato) |
| `infra` | build, deploy, pipeline, observabilidade |
| `refatoracao` | muda estrutura sem mudar comportamento |

Uma task tem **um** tipo — o predominante. Se você hesitar entre dois, é sinal de task grande demais; veja o Passo 4.

## Passo 3 — Levantar os sinais de cada task

Sinais são fatos verificáveis no plano e na base, não impressões. Cada sinal aplicado é **declarado na saída**, junto da task — sinal invisível é sinal que ninguém pode contestar, e estimativa que ninguém pode contestar não é auditável.

### Sinais que empurram a estimativa PARA CIMA

| Sinal | Como você o detecta |
|---|---|
| `sem_cobertura` | os arquivos em `arquivos.altera` da task não têm teste correspondente hoje (não existe `*.test.*`/`*_test.*`/equivalente do projeto para eles) |
| `integracao_externa` | a task fala com sistema de terceiro (a base o descreve como externo, ou o tipo é `integracao_externa`) |
| `migracao_banco` | a task cria ou altera schema, ou move dado existente |
| `muitas_dependencias` | `depende_de` da task tem 3 ou mais ids |
| `area_com_lacuna` | a área que a task toca está registrada em `base/00-LACUNAS.md` |
| `raio_medio_alto` | trabalho em modo legado com raio de impacto MEDIO ou ALTO |
| `teste_caracterizacao` | modo legado: é preciso escrever teste de caracterização antes de tocar o comportamento |
| `sem_historico_comparavel` | não há entrada no `HISTORICO.md` que bata no tipo desta task |

### Sinais que puxam PARA BAIXO

| Sinal | Como você o detecta |
|---|---|
| `area_coberta` | os arquivos que a task toca já têm teste e a suíte é verde na área |
| `padrao_repetido` | a task é o mesmo padrão de uma task já executada neste projeto (o histórico a registra) |
| `arquivo_novo_isolado` | `arquivos.altera` é `[]` e o que ela cria não é importado por nada ainda |

Nenhum sinal é um multiplicador fixo obrigatório. Sinal para cima **alarga a faixa e sobe o pessimista**; sinal para baixo **estreita a faixa**. O que a skill exige é que cada sinal aplicado apareça na saída ao lado da task, para que qualquer pessoa possa discordar do peso que você deu.

## Passo 4 — Estimar cada task: três pontos

Para cada task, dê três números em horas de trabalho focado:

- **`o` (otimista)** — tudo o que a task pressupõe está no lugar, o padrão é conhecido, nada surpreende. Não é o melhor caso imaginável; é o caso bom plausível.
- **`m` (provável)** — o caso que você apostaria, com o atrito normal do projeto.
- **`p` (pessimista)** — o caso ruim plausível: o teste não passa de primeira, o formato do dado é diferente do documentado, o ambiente precisa de ajuste. Não é catástrofe; é o mau dia normal.

Os três pontos incluem: escrever os dois testes da task (TDD é obrigatório no método), implementar, rodar a suíte e verificar o critério de aceite. Não incluem nada da lista "Não incluído" do Passo 6.

### O portão de compreensão — task que não se estima

> **Se `p > 4 × o`, a task está mal compreendida. Não a estime.**

Uma faixa em que o pior caso plausível é mais de quatro vezes o caso bom não é incerteza sobre esforço: é falta de entendimento sobre o que a task é. Estimar isso produz um número que só serve para dar falsa segurança.

Quando isso acontecer:

1. **Não** produza `o`, `m`, `p`, faixa nem PERT para essa task.
2. Registre a task em `tasks_a_quebrar`, no frontmatter e na prosa, com **o que precisa ser esclarecido** para que ela vire duas ou mais tasks estimáveis (uma frase, específica).
3. Não a inclua no esforço total nem no caminho crítico. Some, em separado, a linha "N task(s) fora da faixa" — o total declarado cobre apenas as tasks estimadas, e a saída diz isso.
4. Se **mais de um terço** das tasks do trabalho caírem aqui, a confiança do trabalho inteiro é `baixa` (Passo 7).

O caminho para resolver isso é voltar à F3 e quebrar a task — não afrouxar o portão.

## Passo 5 — Agregar: o ponto onde a maioria erra

> **A faixa da fase não é a soma dos otimistas nem a soma dos pessimistas.**

Somar pessimistas superestima grosseiramente, porque supõe que **tudo** dá errado ao mesmo tempo. Somar otimistas subestima pela razão espelhada. Na prática os desvios se compensam: algumas tasks vão mal, outras vão melhor que o esperado.

O método abaixo é o método oficial da skill. Ele é aritmética simples, reproduzível à mão, e é obrigatório documentá-lo na saída para que qualquer pessoa possa refazer a conta.

### Método de agregação — PERT com variâncias somadas em quadratura

Para cada task estimada:

```
media_task         = (o + 4m + p) / 6     # PERT: favorece o provável
desvio_padrao_task = (p - o) / 6          # desvio-padrão PERT da task, em HORAS
```

> **Dois nomes, duas grandezas.** O `desvio_padrao_task = (p - o) / 6` acima é a **dispersão de uma estimativa, medida em horas**, e é só ele que entra na quadratura — nunca o `desvio_calibracao_task`. O `desvio_calibracao_task = real / estimado_media` do Passo 10 é a **razão de calibração**, **adimensional**, e diz quanto o real excedeu o estimado — nunca o `desvio_padrao_task`. São **duas grandezas incompatíveis** e **não são intercambiáveis**: somar em quadratura a razão de calibração, em vez do desvio-padrão, publica 9–14 h onde o canônico publica 10–14 h. A notação antiga chamava as duas pelo mesmo símbolo (DS-162).

Para um conjunto de N tasks (uma fase, uma sprint, o trabalho inteiro):

```
media_conjunto  = soma de ( media_task(t) * fator(t) )
desvio_conjunto = raiz_quadrada( soma de ( desvio_padrao_task(t) * fator(t) )^2 )     # quadratura
```

**A agregação soma e quadratura já corrigidos, nunca os valores crus (DS-167).** `media_task(t)`
e `desvio_padrao_task(t)` são os valores crus do Passo 4, sem fator nenhum — o `fator(t)` entra
aqui, na soma e na quadratura, e não depois: `media_conjunto` e `desvio_conjunto` já saem
corrigidos, e por isso `min` e `max`, calculados a partir deles, também saem corrigidos — os
dois, não só o `min` pelo piso. Corrigir só o piso e agregar os valores crus no resto deixaria
o `max` sem fator nenhum, publicando uma faixa com o fator aplicado apenas parcialmente — o
defeito que esta regra fecha. `fator(t)` é o mesmo da DS-166: `1` quando o tipo da task `t` não
tem fator ativo, e o canônico daquele tipo quando tem — nunca um fator único do conjunto, nem
mesmo quando todas as tasks do conjunto são do mesmo tipo.

E a faixa publicada do conjunto:

```
min = media_conjunto - desvio_conjunto
max = media_conjunto + desvio_conjunto
```

Arredonde `min` para baixo e `max` para cima, à hora inteira.

**O piso do conjunto.** Nenhuma faixa agregada pode prometer menos do que o melhor caso somado, e o melhor caso somado já vem corrigido pelo fator da própria task:

```
piso_conjunto = soma( o(t) * fator(t) )
fator(t) = 1                              # quando o tipo da task t nao tem fator ativo
```

**`fator(t)` vem do item de `calibracao_por_tipo` cujo `tipo_task` é o de `t` (DS-166)** —
nunca de um fator único do conjunto. Um conjunto com tasks de dois tipos, um com fator ativo e
outro sem, soma o piso com `fator(t)=1` nas tasks do tipo sem fator e `fator(t)` = o canônico
daquele tipo nas outras; é exatamente por isso que o escalar `fator_correcao_aplicado` não
basta para a conta — a conta sempre lê por tipo, com ou sem mistura.

Se `min < piso_conjunto`, então `min = piso_conjunto`. O operando comparado e o operando atribuído são o **mesmo** `piso_conjunto` (DS-163, que estende DS-41): nunca a maior `o` do conjunto no gatilho e a soma dos `o` na atribuição, que são grandezas diferentes e deixam o piso sem definição. `fator(t) = 1` é identidade aritmética do piso, não fator declarado — `fator_correcao_aplicado` continua `null` quando nenhum tipo tem fator ativo.

O clamp acontece **antes** do arredondamento à hora inteira: `floor(min)`/`ceil(max)` recebe o `min` já pisado.

Pisar depois de arredondar publica um `min` fracionário — `3,20 h` no exemplo abaixo —, e a faixa publicada é em hora inteira. É por isso que o estágio está escrito: a ordem entre o piso e o arredondamento é observável na faixa que sai.

Esse arredondamento à hora inteira é o **último passo** da faixa agregada. Quando há fator de correção (Passo 1), ele já entrou antes da agregação, na faixa de cada task do tipo — e o piso também vem corrigido task a task, pelo fator do tipo de cada uma, nunca por um fator único do conjunto. Arredondar à hora antes de aplicar o fator, ou arredondar o próprio fator, é estágio errado e publica outra faixa. As duas casas do `desvio` e do `desvio_medio` (DS-160) são do histórico; a hora inteira é da faixa publicada, e os dois arredondamentos não se misturam.

**Exemplo com fator abaixo de 1.** Uma task `api` `o=4 m=5 p=12` cujo tipo tem fator `0,80`: média corrigida `4,80`, desvio corrigido `1,0667`, `min` cru `3,7333`, `max` `5,8667`. O piso é `4 × 0,80 = 3,20`, e `3,7333` não fica abaixo dele: a faixa publicada é **3–6 h**. Com o piso bruto — a soma dos `o` sem fator, `4` — o `min` seria pisado em `4` e a faixa publicada viraria **4–6 h**: uma hora na base da faixa que o método não calculou. Fator abaixo de 1 é permitido e alcançável — é o tipo cujo histórico mostra que o projeto estima para cima.

**Por que a quadratura.** Somar desvios em quadratura (raiz da soma dos quadrados) é o que faz o intervalo crescer **menos** que a soma linear: dez tasks com desvio 1 h cada dão desvio agregado de `√10 ≈ 3,2 h`, não 10 h. É exatamente o efeito de compensação descrito acima, e é a razão de a faixa da fase ser mais estreita, em proporção, que a faixa de uma task isolada.

**Verificação obrigatória de sanidade:** a faixa agregada de qualquer conjunto tem de ser **mais estreita** que `[ soma( o(t) * fator(t) ), soma( p(t) * fator(t) ) ]` — os limites corrigidos task a task, pelos mesmos fatores que entraram na agregação. Se não for, você errou a conta — refaça. Comparar com o intervalo bruto reprova conta certa sempre que algum fator é abaixo de 1: no exemplo acima, `min` `3,7333` fica fora de `[4, 12]` e dentro de `[3,20, 9,60]`.

### Esforço total × caminho crítico

O paralelismo declarado no plano é respeitado na agregação. A saída separa duas grandezas, sempre as duas, sempre com a diferença explicada:

- **Esforço total** — agrega **todas** as tasks estimadas, paralelizáveis ou não. É o trabalho que alguém precisa fazer, e portanto **é o que se cobra**.
- **Caminho crítico** — agrega **apenas** as tasks da cadeia mais longa de dependências. É o que limita o calendário: nenhuma quantidade de gente encurta abaixo dele.

Como achar o caminho crítico, a partir de `depende_de` e do `caminho_critico` que a F4 declara (se a F4 já rodou; se não, derive dos `depende_de`):

1. Monte o grafo das tasks estimadas: aresta de A para B quando B declara A em `depende_de`.
2. Para cada task, `caminho(t) = media_task(t) + máximo dos caminho(anteriores)`, ou `media_task(t)` se `depende_de` é `[]`.
3. O caminho crítico é a cadeia que produz o maior `caminho(t)`. Guarde a lista de ids dessa cadeia.
4. Agregue essa cadeia — e **só** ela — pelo mesmo método PERT + quadratura.

Duas tasks paralelizáveis somam no esforço total e **não** somam no caminho crítico. Por isso os dois números são diferentes, e a saída explica a diferença em uma frase, nomeando o que roda em paralelo.

Task mandada quebrar (Passo 4) não entra em nenhum dos dois. Se uma delas estiver na cadeia de dependências, diga que o caminho crítico está subestimado por isso.

## Passo 6 — Premissas, invalidadores e não incluído

Os três blocos são **obrigatórios**. Uma faixa sem eles é um número solto, e número solto é a coisa que esta fase existe para não produzir.

### Premissas — o que foi assumido como verdadeiro

O que precisa estar de pé para a faixa valer: ambiente disponível, acesso concedido, decisão já tomada, dependência externa funcionando, ausência de retrabalho por mudança de escopo. Cada premissa é uma afirmação verificável hoje — alguém consegue olhar e dizer "isso é verdade" ou "isso é falso".

Boas:

- "As credenciais de sandbox do gateway estão emitidas e válidas antes do início da sprint-02 (D-04 as declara emitidas)."
- "O schema da tabela `pedidos` é o que `base/pedidos.md` documenta, com as 14 colunas listadas."
- "A suíte atual do projeto roda verde com `npm test` na máquina de quem for executar."

### Invalidadores — o que torna a estimativa sem valor

O que, se acontecer, obriga a **refazer** a estimativa. Este é o campo que mais sai genérico. O teste é simples:

> **Um invalidador tem de ser observável: alguém tem de conseguir dizer, olhando para um fato do mundo, se ele aconteceu ou não.**

Se a frase não nomeia um fato observável, não é invalidador — é desconforto.

| Ruim (genérico, não observável) | Bom (observável, nomeia o fato) |
|---|---|
| "Mudança de escopo" | "O cliente pedir suporte a mais de um formato de arquivo na exportação (hoje a estimativa cobre só CSV)" |
| "Requisitos mal entendidos" | "A planilha de exemplo do cliente vier com colunas que `base/relatorios.md` não lista" |
| "Problemas técnicos" | "O endpoint `/v2/invoices` do gateway responder com paginação por cursor em vez do `offset` que a base documenta" |
| "Atraso de terceiros" | "O acesso ao ambiente de homologação do ERP não estar liberado até o início da sprint-02" |
| "Complexidade maior que a prevista" | "A tabela `pedidos` em produção passar de 5 milhões de linhas, tornando a migração online obrigatória" |
| "Time indisponível" | "Quem executar não tiver permissão de escrita no schema do banco de homologação" |
| "Falta de clareza nos requisitos" | "O cliente exigir que o relatório inclua os pedidos cancelados, que D-07 excluiu do escopo" |
| "Riscos de integração" | "O provedor de e-mail impor limite abaixo de 500 envios/hora, invalidando o disparo em lote de T-03.04" |

Note o padrão das boas: cada uma nomeia **um fato específico** e, quase sempre, **o artefato que ela contradiz** (uma decisão D-NN, um arquivo da base, uma task). Um invalidador que não consegue nomear o que contradiz costuma ser genérico disfarçado.

Regra prática: se você conseguiria colar o mesmo invalidador em qualquer outro projeto sem trocar uma palavra, ele é genérico — reescreva até que só faça sentido neste trabalho.

### Não incluído — o que a faixa deliberadamente não cobre

Sempre declarado, mesmo quando óbvio. O default do método é que a estimativa cobre **apenas** o trabalho descrito nas tasks. Ficam de fora, salvo declaração em contrário:

- reunião, alinhamento e cerimônia;
- revisão de código e ida e volta do pull request;
- ida e volta com o cliente (resposta a dúvida, aprovação, homologação);
- deploy e acompanhamento de subida;
- correção pós-entrega e garantia;
- treinamento, documentação de usuário e passagem de conhecimento;
- gestão do projeto.

Se algum desses **for** para ser incluído, ele entra como **item próprio**, com faixa própria, na seção "Itens fora das tasks" — nunca diluído dentro das tasks. Diluir esconde o custo e corrompe a calibração: o histórico passa a registrar como "esforço de task" algo que era reunião.

## Passo 7 — Derivar a confiança

A confiança é **derivada de sinais**, nunca de sensação. Avalie na ordem: a primeira regra que casar decide.

| Nível | Quando |
|---|---|
| `baixa` | há lacuna **bloqueante** em `base/00-LACUNAS.md` que afeta tasks estimadas; **ou** integração externa não documentada na base; **ou** raio de impacto ALTO; **ou** mais de um terço das tasks foram mandadas quebrar |
| `media` | há lacuna não bloqueante; **ou** não existe histórico comparável (inclusive: `HISTORICO.md` não existe); **ou** o bloco `calibracao` persistido divergiu do canônico recomputado (DS-165) |
| `alta` | plano sem lacuna bloqueante, área com cobertura de teste, e histórico comparável existente no projeto |

Teto duro: **sem `HISTORICO.md`, a confiança nunca é `alta`** — no máximo `media`.

### Obrigação da confiança `baixa`

Quando a confiança for `baixa`, a **primeira linha da saída** — antes de qualquer número — diz **o que precisaria ser resolvido para subir o nível**, no formato:

> **Confiança BAIXA. Para subir: <ação específica, verificável, curta>.**

A ação é concreta e nomeia o artefato: "ler a documentação de webhooks do gateway e registrar `base/gateway-webhooks.md`", "confirmar com o cliente o formato do arquivo de retorno e fechar a PENDENTE-02", "medir o volume atual da tabela `pedidos` em produção". Quase sempre é uma investigação curta — algumas horas — que vale muito mais que uma estimativa apressada, e a saída diz isso.

Nunca escreva "para subir, é preciso mais informação". Isso não é uma ação.

## Passo 8 — Gravar a estimativa

Grave em `docs/sprintx/features/<slug>/00-ESTIMATIVA.md`, a partir de `assets/TEMPLATE-ESTIMATIVA.md`.

É um arquivo de estado: leva frontmatter `kind: estimativa` do contrato **expx-schema v1**. Leia `references/00-schema.md` antes de gravar e siga-o para os campos e enums. Pontos que esta fase costuma errar:

- `esforco_total_min` / `esforco_total_max` e `caminho_critico_min` / `caminho_critico_max` são **números** (horas), nunca strings com unidade. A unidade está em `unidade: h`.
- Os quatro nunca são iguais dois a dois de forma a produzir número único: `min < max` sempre. Se `min == max`, você produziu número único — refaça.
- `fator_correcao_aplicado` é o fator **efetivamente aplicado** (DS-165), e a **origem da calibração** tem três estados possíveis: `null`, origem `nenhum — canônico sem fator ativo`, quando o canônico tem `fator_ativo: false` (menos de 3 entradas elegíveis, ou `HISTORICO.md` ausente) — **mesmo que o bloco gravado divergente dissesse `fator_ativo: true`**; ou, com o canônico ativo, o `desvio_medio` dele — origem `persistido` quando a conferência bate contra o bloco `calibracao` gravado, `recomputado` quando diverge —, copiado com as mesmas duas casas (`1.16`, `1.20`). Nunca `1.00` disfarçando ausência de fator (DS-46).
- `calibracao_por_tipo` (DS-166) leva uma linha por `tipo_task` presente, em ordem lexical, com
  `fator`, `origem` e `divergencia` conforme a conferência da DS-165 aplicada a cada tipo.
  `fator_correcao_aplicado` é derivado dela (ver Passo 1): número quando todos os tipos
  presentes concordam, `null` quando nenhum tem fator ativo, `por_tipo` em qualquer mistura.
- `tasks_a_quebrar` é `[]` quando nenhuma task passou do portão do Passo 4.
- `premissas`, `invalidadores` e `nao_incluido` são listas de strings de uma linha, nunca vazias por preguiça — `nao_incluido` em particular sempre tem conteúdo.

**Reexecução:** rodar a F3.5 de novo sobrescreve `00-ESTIMATIVA.md`. O histórico de versões fica a cargo do versionamento do repositório.

**A F3.5 não altera nenhum arquivo do plano.** Se estimar revelar que uma task precisa ser quebrada, isso vai para `tasks_a_quebrar` e a correção acontece na F3 — não aqui.

## Passo 9 — O formato exato da saída ao usuário

A saída na conversa espelha o arquivo. Nesta ordem:

1. **Se a confiança for `baixa`:** a linha `**Confiança BAIXA. Para subir: <ação>.**` vem primeiro, antes de qualquer número.
2. **Se não houver `HISTORICO.md`:** a linha declarando a ausência de base de calibração.
3. **Esforço total** — `min–max h`, com o método nomeado ("PERT com variâncias em quadratura").
4. **Caminho crítico** — `min–max h`, com **uma frase explicando a diferença** para o total, nomeando o que roda em paralelo.
5. **A frase de conversão**, sempre, literal em espírito: "Esforço não é prazo. A conversão em data depende da disponibilidade do time, e é decisão de quem conhece a agenda."
6. **Tabela por sprint/fase** — faixa de cada uma.
7. **Tasks a quebrar**, se houver — com o que esclarecer em cada uma.
8. **Premissas**, **Invalidadores**, **Não incluído**.
9. **Confiança** e o motivo derivado dos sinais.
10. **Fator de correção aplicado**, por `tipo_task` presente — para cada um, o desvio histórico que o originou, a origem da calibração (`persistido` | `recomputado` | `nenhum — canônico sem fator ativo`) e a divergência encontrada (confere | diverge com valores | `não se aplica — HISTORICO.md ausente`) (DS-165). Com um único tipo presente, repita também o escalar `fator_correcao_aplicado`, a origem e a divergência como valores do trabalho inteiro — eles coincidem com os do tipo único. Com mais de um tipo presente, não há origem nem divergência agregada do trabalho (DS-168): a saída não anuncia uma delas; cada tipo leva a sua, e nenhuma linha extra finge um resumo que não existe.

## Passo 10 — Registrar o real e calibrar (ao fim do trabalho)

Isto acontece quando a F6 termina, não agora — mas o roteiro mora aqui, porque é a F3.5 que dá sentido ao dado.

Ao fim de um trabalho, `docs/sprintx/estimativas/HISTORICO.md` recebe uma linha por task concluída, a partir de `assets/TEMPLATE-HISTORICO.md` (`kind: estimativa_historico`), com: `trabalho_id`, `task_id`, `tipo_task`, `area`, `sinais`, `estimado_min`, `estimado_max`, `estimado_media`, `real`, `desvio` e `duracao_observada`.

O **desvio** de uma task é calculado contra a média PERT que a originou:

```
desvio_calibracao_task = arredonda( real / media_task_estimada )
arredonda(x)           = duas casas decimais, meio para cima (half-up)
```

`1,00` é o alvo; `1,40` significa que levou 40% a mais que o previsto.

**Precisão e desempate (DS-160).** São **duas casas decimais**, com desempate **half-up**: terceira casa exatamente `5`, a segunda sobe. A razão `1,125` vira `1,13`, nunca `1,12`. As duas casas são **fixas**: a razão `1,2` grava-se `1.20` no YAML e escreve-se `1,20` na prosa. Cada `desvio` é arredondado **antes** de ser persistido — é o valor persistido que participa da calibração.

O **desvio por tipo** é a média dos `desvio_calibracao_task` **já persistidos** de todas as entradas elegíveis daquele tipo — nunca a média das razões brutas, e nunca o `desvio_padrao_task`, que é dispersão em horas e não razão —, arredondada de novo pela mesma regra. Ele é gravado na tabela de calibração do próprio `HISTORICO.md` e é o que vira **fator de correção** no Passo 1 — a partir de 3 entradas do tipo, e sempre declarado na saída, nunca embutido em silêncio.

**Exemplo completo.** Quatro entradas de `integracao_externa` com `estimado_media` 4.0, 4.0, 3.0 e 1.0 e `real` 4.5, 4.5, 3.5 e 1.2 dão razões `1,125`, `1,125`, `1,1666…` e `1,2`, persistidas como `desvio: 1.13`, `1.13`, `1.17` e `1.20`. A média dos quatro persistidos é `1,1575`, gravada como `desvio_medio: 1.16` com `fator_ativo: true`. Esse `1.16` é o fator que o Passo 1 aplica. Pelas convenções que o contrato **não** aceita, o mesmo histórico daria `1,15` — e a faixa publicada mudaria (ver o exemplo do Passo 1).

Se o trabalho não teve estimativa (a F3.5 não rodou), registre o real mesmo assim, com `estimado_min: null`, `estimado_max: null` e `desvio: null`: o real alimenta a comparabilidade por tipo e área nas estimativas futuras.

A **`duracao_observada`** vem do rastro (`references/08-rastro.md`), é opcional (`null` sem o par `task_iniciada`/`task_concluida`) e **não entra em conta nenhuma desta fase**: o desvio continua sendo `real / media_task_estimada`, e a calibração por tipo continua lendo só o desvio. Ela serve para conferir o real e para expor interrupção, nunca para corrigir a estimativa (DS-37).

## Verificação própria antes de encerrar

- [ ] Nenhum número único em lugar nenhum: toda grandeza de esforço saiu como faixa `min–max`, com `min < max`.
- [ ] Nenhuma conversão de esforço em data, prazo, dia útil, semana ou sprint de calendário.
- [ ] A frase "esforço não é prazo" está na saída e no arquivo.
- [ ] Esforço total e caminho crítico são números **diferentes**, e a diferença está explicada em uma frase que nomeia o que roda em paralelo.
- [ ] A faixa agregada é mais estreita que `[ soma( o(t) * fator(t) ), soma( p(t) * fator(t) ) ]` (senão a quadratura foi feita errado), e o piso aplicado a `min` foi `piso_conjunto`, antes do arredondamento à hora inteira.
- [ ] O método de agregação está documentado na saída, com as fórmulas.
- [ ] Toda task tem seus sinais declarados ao lado dela.
- [ ] Toda task com `p > 4 × o` está em `tasks_a_quebrar`, **não** foi estimada e **não** entrou nos totais.
- [ ] Premissas, invalidadores e não incluído estão preenchidos; nenhum invalidador é genérico (aplique o teste da tabela do Passo 6).
- [ ] A confiança foi derivada da tabela do Passo 7, e o motivo cita os sinais que a produziram.
- [ ] Se a confiança é `baixa`, a primeira linha da saída diz o que resolver para subir.
- [ ] Se não há `HISTORICO.md`, a confiança é no máximo `media` e a ausência de calibração está declarada.
- [ ] `00-ESTIMATIVA.md` tem frontmatter `kind: estimativa` válido conforme `references/00-schema.md`.
- [ ] Nenhum caminho absoluto em nenhum artefato.

## Critério de saída da fase

- [ ] `docs/sprintx/features/<slug>/00-ESTIMATIVA.md` existe, com frontmatter válido e as seções do template preenchidas.
- [ ] Checklist de verificação toda atendida.

## Ao terminar

Anuncie: "F3.5 concluída. Estimativa em `docs/sprintx/features/<slug>/00-ESTIMATIVA.md`: esforço total `min–max h`, caminho crítico `min–max h`, confiança `<nivel>`."

Grave `fase: f4` em `.expx/estado.json` (`references/09-estado.md`) e siga para a F4 lendo `references/04-orquestrador.md`.
