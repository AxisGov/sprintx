# Contrato expx-schema v1 — frontmatter dos arquivos de estado

Leitura OBRIGATÓRIA em qualquer fase que grave arquivo de estado (F1, F2, F3, F4, F6).

Um painel de operação lê os arquivos gerados por esta skill para mostrar o andamento
dos trabalhos. Prosa não é contrato: a mesma informação pode ser escrita de dez formas
corretas para um humano e todas quebram um parser. O frontmatter resolve isso sem
prejudicar a leitura humana — a máquina lê o YAML, a pessoa lê a prosa abaixo dele.

O painel apenas LÊ. Esta skill continua sendo a única a escrever.

## Contrato irmão — a runx

O `expx-schema v1` é compartilhado com a [`runx`](https://github.com/bittencourtthulio/runx), a metade Run do
método Expx (ocorrências em produção, estágios E1–E5). Os kinds `orquestrador`, `sprint`, `fases`,
`tasks`, `bloqueios` e `base_indice` existem nas duas skills com os mesmos campos e os mesmos enums;
`expx_tool` (`sprintx` | `runx`) diz qual das duas gravou o arquivo, e é por isso que o enum tem os
dois valores. A runx acrescenta na task o campo `teste_regressao` (prova o comportamento errado antes
do fix) e tem kinds próprios do ciclo dela (`ocorrencia`, `causa_raiz`, `qa`, `relatorio_tecnico`,
`relatorio_uso`, `relatorios_indice`); a sprintx tem o `decisoes` e o `fechamento`.

O `fechamento` da sprintx e o `relatorio_tecnico` da runx cumprem o mesmo papel no índice — dizer
o que o trabalho entregou, em que módulo e em que arquivos —, mas são kinds distintos, cada um
com o vocabulário do seu ciclo. Os campos de indexação (`modulo_afetado`, `arquivos_alterados`,
`palavras_chave`) são os mesmos nos dois lados: é por eles que um índice único enxerga Build e
Run com a mesma consulta.

**Ao mudar qualquer kind compartilhado, a mudança vale para as duas skills** — um painel que lê as
duas não pode encontrar o mesmo `kind` com formatos diferentes. Kind exclusivo de uma delas pode
evoluir sozinho. **Pendência registrada:** a chave `classe` de `bloqueios` (DS-139) nasceu na
sprintx e ainda não foi adotada pela runx. Ela é aditiva — quem não a conhece a ignora — e todo
B-NN sem ela é lido como legado, nunca com classe inferida.

## Regras universais

Valem para todo arquivo que leva frontmatter:

1. O bloco YAML é a primeira coisa do arquivo, delimitado por `---` antes e depois.
2. Toda chave em `snake_case`, minúscula, sem acento.
3. Todo valor de enum em minúscula e sem acento: `concluida`, nunca `Concluída`.
4. Datas em ISO: `AAAA-MM-DD`. Obtenha a data com `date +%Y-%m-%d` do sistema, nunca de memória.
5. Booleanos: `true` / `false` (sem aspas).
6. Lista vazia é `[]`. Valor ausente é `null`. **NUNCA omita a chave** — o painel
   diferencia "não se aplica" de "esqueceram de escrever".
7. O frontmatter é a única fonte para o painel. A prosa abaixo dele é para humano e
   continua exatamente como esta skill já a produz.
8. Campos de texto no YAML são de UMA linha. Nada de duplicar prosa longa no YAML.
9. `atualizado_em` é reescrito a cada gravação do arquivo.

## Enums

| Enum | Valores |
|---|---|
| `expx_tool` | `sprintx` \| `runx` |
| `tipo_trabalho` | `feature` \| `ocorrencia` |
| `estagio` | `f1` `f2` `f3` `f4` `f5` `f6` |
| `status` (trabalho, sprint, fase) | `nao_iniciado` \| `em_andamento` \| `bloqueado` \| `concluido` |
| `status` (task) | `pendente` \| `em_andamento` \| `concluida` \| `bloqueada` |
| `suite` | `verde` \| `vermelha` \| `parcial` \| `nao_executada` |
| `severidade` | `alta` \| `media` \| `baixa` |
| `confianca` | `alta` \| `media` \| `baixa` |
| `tipo_task` | `config` \| `client` \| `dominio` \| `persistencia` \| `api` \| `ui` \| `integracao_externa` \| `teste` \| `infra` \| `refatoracao` |
| `metodo_agregacao` | `pert_quadratura` |
| `densidade` | `mvp` \| `padrao` \| `completo` \| `profundo` |
| `modo_construcao` | `entrevista` \| `autonomo` |
| `estado` (planejamento) | `aguardando_f3` \| `aguardando_f4` \| `aguardando_f5` \| `replanejar` \| `aprovado` \| `orcamento_esgotado` \| `replanejar_execucao` \| `replanejamento_execucao_esgotado` (ou `null` antes do fim da F2) |
| `veredito` (rodada da F5) | `sim` \| `nao` |
| `classe` (bloqueio) | `defeito_de_plano` \| `lacuna_de_decisao` \| `prerequisito_ausente` \| `suite_vermelha` \| `task_reivindicada` |

Atenção a duas distinções que o painel trata como coisas diferentes:

- `estagio` (`f1`..`f6`) é a fase da MÁQUINA DE ESTADOS do método — em minúscula, no frontmatter.
  Não confunda com o id de uma FASE do plano, que é `F-NN.M` (ex.: `F-01.1`) e vive nos
  campos `fases:`, `fase:` e `caminho_critico:`. São namespaces distintos.
- `status` de task usa o vocabulário feminino (`concluida`, `bloqueada`); `status` de
  trabalho, sprint e fase usa o masculino (`concluido`, `bloqueado`). Não troque um pelo outro.

## Cabeçalho comum

Todo arquivo com frontmatter começa com estas quatro chaves, nesta ordem:

```yaml
expx_schema: 1
expx_tool: sprintx
kind: <o kind do arquivo>
trabalho_id: <slug da feature>
```

`trabalho_id` é sempre o `<slug-da-feature>` — o mesmo nome da pasta `docs/sprintx/features/<slug>/`.

## Os kinds que a sprintx produz

### `ORQUESTRADOR.md` → `kind: orquestrador`

```yaml
---
expx_schema: 1
expx_tool: sprintx
kind: orquestrador
trabalho_id: exportacao-csv-relatorios
titulo: Exportacao de relatorios em CSV
tipo_trabalho: feature
tipo_ocorrencia: null
estagio: f3
status: em_andamento
criado_em: 2026-08-20
atualizado_em: 2026-08-29
concluido_em: null
sprints: [sprint-01, sprint-02]
caminho_critico: [F-01.1, F-01.3]
modulo_afetado: [relatorios, exportacao]
arquivos_alterados: []
palavras_chave: [csv, exportacao, relatorio, streaming]
worktree: null
---
```

- `tipo_ocorrencia` é `null` quando `tipo_trabalho: feature`.
- `caminho_critico` lista ids de fase (`F-NN.M`) e/ou de task (`T-NN.MM`), na ordem da
  cadeia, exatamente como a seção 3 do ORQUESTRADOR os declara.
- `concluido_em` permanece `null` até o trabalho inteiro estar entregue.
- `worktree` é o caminho relativo à raiz do checkout principal para o `git worktree` desta
  feature (regra 21, "Sessões paralelas" no `SKILL.md`). `null` quando não há git, ou quando
  o pedido foi explicitamente "sem worktree" — a chave existe sempre, mesmo quando não se
  aplica. Nunca um caminho absoluto. Gravado pela F1 ao abrir a área de trabalho
  (`references/01-ingestao.md`) e copiado ao `ORQUESTRADOR.md` pela F4.

Os três campos de indexação — `modulo_afetado`, `arquivos_alterados` e `palavras_chave` — são
listas e seguem a regra universal 6: **nunca omita a chave**; vazia é `[]`, jamais ausente.

- `modulo_afetado` lista os módulos que o trabalho toca, em minúscula e sem acento, um termo
  por módulo (`autenticacao`, não `Autenticação`; `relatorios`, não `Relatórios`). É derivado
  na F3 a partir dos arquivos declarados nas tasks — as camadas do `CONVENCOES.md` do projeto
  quando ele existe (localizado pela regra única "Como localizar o `CONVENCOES.md`", neste
  arquivo), a estrutura de pastas quando não (`references/03-plano.md`). É a única
  das três listas que a F3 já grava preenchida.
- `arquivos_alterados` é a união, **sem repetição**, dos campos `arquivos` (`cria` + `altera`)
  de todas as tasks **concluídas** do trabalho. Nasce `[]` na F3 e é preenchido pela F6 ao
  fechar a última task (`references/06-execucao.md`). Caminhos relativos à raiz do
  repositório, na mesma forma em que aparecem nas tasks.
- `palavras_chave` traz até 8 termos que descrevem o trabalho, em minúscula e sem acento.
  Mais que 8 deixa de discriminar: uma lista que casa com tudo não encontra nada.

Estes três campos existem para que os artefatos da skill sejam **indexáveis por arquivo e por
módulo** — a pergunta "quem já mexeu neste arquivo e por quê" só tem resposta se alguém tiver
registrado a resposta. Nenhum deles altera o Contrato da Task nem qualquer regra do método:
são campos do orquestrador, agregados a partir do que as tasks já declaravam.

### `sprint-NN/sprint.md` → `kind: sprint`

```yaml
---
expx_schema: 1
expx_tool: sprintx
kind: sprint
trabalho_id: exportacao-csv-relatorios
sprint_id: sprint-01
titulo: Fundacao
status: em_andamento
criterio_saida: Suite verde e client cobrindo os quatro endpoints
fases: [F-01.1, F-01.2]
riscos: [Rate limit nao documentado na fonte]
atualizado_em: 2026-08-29
---
```

`riscos` é uma lista de strings de uma linha; sem riscos registrados, `[]`.

### `sprint-NN/fases.md` → `kind: fases`

```yaml
---
expx_schema: 1
expx_tool: sprintx
kind: fases
trabalho_id: exportacao-csv-relatorios
sprint_id: sprint-01
atualizado_em: 2026-08-29
fases:
  - id: F-01.1
    titulo: Config e segredos
    status: concluido
    criterio_saida: Variaveis carregadas e validadas na subida
    paralelizavel: false
    paralela_com: []
    tasks: [T-01.01, T-01.02]
---
```

`paralela_com` lista os ids das fases que rodam em paralelo com esta; "nenhuma" na prosa
corresponde a `[]` no YAML, com `paralelizavel: false`.

### `sprint-NN/tasks.md` → `kind: tasks`

O arquivo mais importante. Cada task do plano vira um item da lista `tasks:`, com
EXATAMENTE os mesmos campos do Contrato da Task do `SKILL.md` — nenhum a mais, nenhum a
menos — acrescidos apenas dos três campos de execução (`concluida_em`, `suite`) e do
vínculo com a fase (`fase`).

```yaml
---
expx_schema: 1
expx_tool: sprintx
kind: tasks
trabalho_id: exportacao-csv-relatorios
sprint_id: sprint-01
atualizado_em: 2026-08-29
tasks:
  - id: T-01.01
    titulo: Carregar configuracao de ambiente
    fase: F-01.1
    status: concluida
    objetivo: Ler e validar as variaveis obrigatorias na subida
    arquivos:
      cria: [src/config/env.ts, src/config/env.test.ts]
      altera: []
    teste_integracao: Sobe a app sem variavel obrigatoria e espera falha
    teste_funcional: Dado env valido, retorna objeto tipado com defaults
    criterio_aceite: App nao sobe sem as quatro variaveis obrigatorias
    depende_de: []
    paralelizavel: true
    concluida_em: 2026-08-29
    suite: verde
---
```

Regras duras deste kind:

- `teste_integracao` e `teste_funcional` são strings OBRIGATÓRIAS e NÃO VAZIAS. O painel
  usa a ausência delas como violação do método. A skill jamais gera uma task sem elas
  preenchidas — inclusive na F3, quando a task ainda está `pendente`.
- `arquivos` mantém a forma do contrato do `SKILL.md`: um mapa com `cria` e `altera`,
  cada um uma lista de caminhos relativos à raiz do repositório (`[]` quando vazio).
- `concluida_em` é `null` enquanto a task não estiver `concluida`.
- `suite` é `nao_executada` até rodar algum teste para aquela task; depois `parcial`, `verde` ou `vermelha`. `parcial` é o estado normal de uma task concluída na F6: rodou o subconjunto de testes afetado por ela e passou, e a suíte inteira é cobrada uma vez, no fim da sprint. `verde` significa suíte inteira executada e sem falha — quem a rodar na task grava `verde`, que nunca é violação.
- Os campos do YAML são a mesma verdade da prosa do bloco correspondente. Os dois andam juntos.

### `sprint-NN/tasks.md` no formato condensado → `kind: plano`

**Compartilhado com a runx** — as duas skills gravam este kind com os mesmos campos.

Quando uma sprint tem **uma única fase**, os três arquivos dela viram um só. O arquivo
continua se chamando `sprint-NN/tasks.md`: é o caminho que os hooks de método procuram, e
mudá-lo os desligaria em silêncio, porque hook de método falha aberto.

O corte é **por sprint, não pelo trabalho inteiro**. Num plano de três sprints, cada uma é
gravada no formato que couber: a que tem uma fase vai condensada, a que tem três vai nos
três arquivos. A regra 13 (a sprint-01 entrega capacidade de testar) faz a maioria dos
trabalhos ter mais de uma sprint — o ganho está em cada sprint de fase única, não num
trabalho inteiro de fase única, que quase não existe.

O bloco YAML é **um só**. Os leitores de frontmatter param no primeiro `---` de fechamento;
um segundo bloco no mesmo arquivo seria invisível para eles.

```yaml
---
expx_schema: 1
expx_tool: sprintx
kind: plano
trabalho_id: exportacao-csv-relatorios
sprint_id: sprint-02
atualizado_em: 2026-08-29
sprint:
  titulo: Geracao do CSV
  status: em_andamento
  criterio_saida: Relatorio de 10 mil linhas exporta em CSV valido
  riscos: [Limite de memoria nao documentado na fonte]
  fora_de_escopo: [Exportacao em XLSX]
fases:
  - id: F-02.1
    titulo: Gerador de CSV
    status: em_andamento
    criterio_saida: Campo com virgula e aspas sai escapado
    paralelizavel: false
    paralela_com: []
    tasks: [T-02.01]
tasks:
  - id: T-02.01
    titulo: Escapar separador e aspas
    fase: F-02.1
    status: concluida
    objetivo: Gerar CSV valido quando o dado tem virgula ou aspas
    arquivos:
      cria: [src/csv/escapar.ts, src/csv/escapar.test.ts]
      altera: []
    teste_integracao: Gera o CSV de uma fixture com virgula e aspas e reabre com o parser
    teste_funcional: Dado o valor `a,"b`, retorna `"a,""b"`
    criterio_aceite: O CSV gerado reabre sem erro no parser de referencia
    depende_de: []
    paralelizavel: false
    concluida_em: 2026-08-29
    suite: parcial
---
```

Regras duras deste kind:

- **`tasks` tem exatamente o mesmo formato do `kind: tasks`** — mesmos campos, mesmos
  enums. Quem consome tasks lê a mesma chave nos dois formatos.
- `sprint` e `fases` carregam os campos dos kinds `sprint` e `fases` **menos** as chaves de
  cabeçalho (`expx_schema`, `expx_tool`, `trabalho_id`, `sprint_id`, `atualizado_em`), que
  já estão no topo. É essa repetição que o formato condensado corta.
- `sprint.fora_de_escopo` é uma lista de strings de uma linha (`[]` quando vazia).
- **Quando usar:** a sprint tem uma fase. Com duas ou mais fases, os três arquivos.
- Os kinds `sprint`, `fases` e `tasks` **continuam válidos e não são descontinuados**.
  Plano já escrito neles permanece como está e nunca é migrado retroativamente.

### Como resolver o formato de uma sprint — regra única

Uma sprint existe em **um dos dois formatos**, e nenhum deles é plano incompleto. Todo leitor
de plano — **F3.5, F4, F5 e F6** — resolve o formato assim, e esta é a única descrição da regra:

1. Leia `sprint-NN/tasks.md`. Ele existe **sempre**, nos dois formatos.
2. O frontmatter declara `kind: plano`? Então a sprint é **condensada**:
   - dados da sprint = chave `sprint`;
   - fases = chave `fases`;
   - tasks = chave `tasks`;
   - **não exija `sprint.md`**, **não exija `fases.md`** — a ausência dos dois é o formato
     funcionando, não arquivo faltando.
3. Qualquer outro kind (`tasks`): a sprint está nos **três arquivos**. Exija
   `sprint.md`, `fases.md` e `tasks.md`, e leia os três como sempre.

O que muda entre os formatos é **onde a informação mora**, nunca quais campos existem nem
quanto rigor se cobra:

| Informação | Condensado (`kind: plano`) | Três arquivos |
|---|---|---|
| Status da sprint | `tasks.md` → `sprint.status` | `sprint.md` |
| Critério de saída da sprint | `tasks.md` → `sprint.criterio_saida` | `sprint.md` |
| Fases e seus critérios | `tasks.md` → `fases[]` | `fases.md` |
| Tasks | `tasks.md` → `tasks[]` | `tasks.md` |
| Diagrama Mermaid | não existe (só a F3 o gera, e só em `fases.md`) | `fases.md` |

**Ao gravar no condensado**, tudo acontece no mesmo frontmatter: fechar uma task atualiza o
item em `tasks`, fechar uma fase atualiza o item em `fases`, fechar a sprint atualiza
`sprint.status`. Um único arquivo é reescrito, com um único bloco YAML.

Num plano com várias sprints, **cada uma resolve o seu próprio formato**: a de fase única vai
condensada, a de três fases vai nos três arquivos, e as duas convivem no mesmo trabalho. Nunca
migre um plano já escrito de um formato para o outro.

### `00-BLOQUEIOS.md` → `kind: bloqueios`

```yaml
---
expx_schema: 1
expx_tool: sprintx
kind: bloqueios
trabalho_id: exportacao-csv-relatorios
atualizado_em: 2026-08-29
bloqueios:
  - id: B-01
    task: T-01.03
    classe: prerequisito_ausente
    aberto_em: 2026-08-29
    resolvido_em: null
    descricao: "Falta credencial de sandbox para validar o webhook"
---
```

Sem bloqueios registrados, `bloqueios: []`.

**O bloqueio é dado tipado (DS-139).** Todo B-NN novo tem `classe`, do enum `classe` (bloqueio).
A classe diz **o que** bloqueou a execução; o que fazer com isso é decisão de quem consome — o
vocabulário do consumidor não entra aqui. **A prosa explica, não classifica:** `descricao` e a
linha `B-NN | …` são para humano; nenhum consumidor deriva classe delas, nem por palavra-chave,
nem por "leitura atenta".

| Classe | Caminho de criação na F6 (`references/06-execucao.md`) | Fato mecânico que a fixa |
|---|---|---|
| `defeito_de_plano` | cumprir a task exige mudar o plano aprovado: arquivo necessário fora de `arquivos` da task (de outra task ou de nenhuma); `depende_de` que o plano não declara; obrigação `fraco:teste` impossível de discriminar dentro da task; `criterio_saida` de fase/sprint sem task que o cumpra | dá para nomear o campo do plano aprovado que teria de mudar (`arquivos`, `depende_de`, teste declarado, tasks da fase) |
| `lacuna_de_decisao` | dúvida nova que nenhuma `D-NN` responde; operação barrada pelo `git-perigoso` | nenhuma `D-NN` cobre a escolha, ou o hook barrou a ação por exigir decisão humana |
| `prerequisito_ausente` | segredo inexistente, serviço fora do ar, dependência externa quebrada | um recurso fora do repositório não está disponível (variável ausente, serviço sem resposta, pacote que não instala) |
| `suite_vermelha` | portão da sprint: a suíte inteira terminou com falha que a execução não corrigiu | o comando da suíte inteira saiu com falha |
| `task_reivindicada` | não resta task executável porque as restantes estão reivindicadas por outra sessão | o rastro tem `task_iniciada` de outra sessão sem `task_concluida`/`task_bloqueada` depois |

Regras duras de `classe`:

- **Escritor.** Entrada nova só nasce por `scripts/bloqueios.sh registrar` (caminho relativo à
  raiz da skill), na F6, no mesmo instante em que a task vira `bloqueada`. Ele recusa com código
  `4` — e não grava nada — classe vazia, ausente ou fora do enum.
- **Imutável.** Gravada, a classe não muda: nem quando a descrição é reescrita, nem quando o
  bloqueio é resolvido (`resolvido_em` deixa de ser `null` e a classe fica). Classe errada não se
  edita; o bloqueio é resolvido e um B-NN novo é registrado com a classe certa.
- **Resolução.** Só por `scripts/bloqueios.sh resolver <slug> <B-NN>`, nunca editando
  `resolvido_em` à mão. Ele grava **somente** `resolvido_em` (data do sistema), `atualizado_em` e o
  sufixo ` · resolvido em AAAA-MM-DD` na linha `B-NN | …` da prosa; `id`, `task`, `classe`,
  `aberto_em` e `descricao` ficam byte a byte. B-NN já resolvido: nada muda (código `0`). Um
  `defeito_de_plano` só é resolvido quando `scripts/planejamento.sh pode-resolver` aceita — o B-NN
  abriu a rodada de replanejamento da execução (`bloqueios_replanejamento_f6`) e o plano
  replanejado já voltou a `aprovado` pela F5; fora disso, código `5` e nada gravado. Editar o plano
  não resolve um defeito de plano. As demais classes, e o legado, são resolvidas diretamente.
- **Legado.** Entrada sem a chave `classe` é anterior a este contrato: continua legível, e
  `scripts/bloqueios.sh listar` a devolve como `legado`. **Ela nunca recebe classe inferida** —
  nem na leitura, nem na migração, nem quando o arquivo é regravado com um B-NN novo (a entrada
  antiga fica como está). `legado` não é valor do enum e nunca é gravado.
- **Legado só antes do primeiro tipado.** Entrada sem `classe` depois de uma entrada com
  `classe` é bloqueio novo sem classe: `scripts/bloqueios.sh validar` recusa o arquivo (código `4`).
  `classe: null` também é recusado — ausência de classe só existe como chave ausente, no legado.
- **Kind compartilhado.** `bloqueios` é compartilhado com a runx: a chave é aditiva, e um leitor
  que não a conhece a ignora. Arquivo `expx_tool: runx` sem `classe` é lido como legado até a runx
  adotar o mesmo enum.

### `00-DECISOES.md` → `kind: decisoes`

```yaml
---
expx_schema: 1
expx_tool: sprintx
kind: decisoes
trabalho_id: exportacao-csv-relatorios
densidade: padrao
modo_construcao: entrevista
atualizado_em: 2026-08-29
decisoes:
  - id: D-00
    decisao: densidade padrao, construcao entrevista
    alternativa_descartada: null
    motivo: confirmado pelo usuario sem sugestao previa
    status: fechada
    bloqueante: false
  - id: D-01
    decisao: Envio assincrono via fila existente
    alternativa_descartada: Envio sincrono na request
    motivo: Nao segurar a resposta do usuario
    status: fechada
    bloqueante: false
---
```

- `status` de decisão usa seu próprio vocabulário: `fechada` \| `pendente`.
- Uma linha `PENDENTE-NN` da prosa entra na lista com `status: pendente`,
  `alternativa_descartada: null` e `motivo: null` enquanto não estiver resolvida.
- `bloqueante` reflete a regra da skill: todo PENDENTE é `true` por padrão; só é `false`
  com autorização explícita do usuário. Decisão já `fechada` é `bloqueante: false`.
- `densidade` (`mvp` \| `padrao` \| `completo` \| `profundo`) e `modo_construcao`
  (`entrevista` \| `autonomo`) são gravados na F2, Passo 0, e refletem a linha `D-00` —
  a primeira decisão de toda fase de descoberta. Quando a feature vem de um
  `BRIEFING.md` do prodx com `densidade_sugerida`/`modo_construcao_sugerido`,
  `D-00.alternativa_descartada` registra a sugestão original quando o usuário a ajusta;
  `null` quando ele apenas confirma.
- No modo `autonomo`, uma decisão fechada por pesquisa (sem resposta direta do usuário)
  tem seu `motivo` começando com `(HIPOTESE)`, seguido da evidência que a sustenta. Uma
  decisão sem esse marcador é lida como confirmada pelo usuário, em qualquer modo.

### `base/00-INDICE.md` → `kind: base_indice`

```yaml
---
expx_schema: 1
expx_tool: sprintx
kind: base_indice
trabalho_id: exportacao-csv-relatorios
atualizado_em: 2026-08-29
areas:
  - arquivo: send-email.md
    titulo: Send Email
    lacunas: 2
---
```

- `arquivo` é o nome do arquivo dentro de `base/`, sem diretório.
- `lacunas` é o número de lacunas daquela área registradas em `base/00-LACUNAS.md` (`0` se nenhuma).

### `00-ESTIMATIVA.md` → `kind: estimativa`

Gravado pela F3.5 (fase opcional). Um por trabalho; reexecutar a F3.5 sobrescreve o arquivo.

```yaml
---
expx_schema: 1
expx_tool: sprintx
kind: estimativa
trabalho_id: exportacao-csv-relatorios
gerada_em: 2026-08-29
atualizado_em: 2026-08-29
unidade: h
esforco_total_min: 78
esforco_total_max: 121
caminho_critico_min: 41
caminho_critico_max: 63
confianca: media
confianca_motivo: Sem historico comparavel no projeto e uma lacuna nao bloqueante na base
fator_correcao_aplicado: null
metodo_agregacao: pert_quadratura
tasks_estimadas: 11
premissas: [Credenciais de sandbox emitidas antes da sprint-02]
invalidadores: [O cliente pedir suporte a mais de um formato de arquivo alem de CSV]
nao_incluido: [Reuniao e alinhamento, Revisao de codigo, Deploy, Correcao pos-entrega]
tasks_a_quebrar: [T-03.04]
---
```

Regras duras deste kind:

- `unidade` é sempre `h` (hora de trabalho focado). A skill estima ESFORÇO, nunca prazo de
  calendário: não existe campo de data de entrega, e nenhum valor deste kind é um dia, uma
  semana ou uma sprint de calendário.
- **Número único é proibido.** `esforco_total_min < esforco_total_max` e
  `caminho_critico_min < caminho_critico_max`, sempre. Os quatro são números (horas), nunca
  strings com unidade embutida.
- `esforco_total_*` cobre TODAS as tasks estimadas (paralelas ou não); `caminho_critico_*`
  cobre apenas a cadeia de dependências mais longa. Os dois são normalmente diferentes — é o
  paralelismo declarado no plano que os separa.
- `fator_correcao_aplicado` é `null` quando não houve calibração; um número (ex.: `1.25`)
  quando um desvio histórico foi aplicado. Nunca `1.0` para disfarçar ausência de histórico.
- `confianca` segue o enum `confianca`; `confianca_motivo` é uma linha derivada dos sinais.
  Sem `docs/sprintx/estimativas/HISTORICO.md`, `confianca` nunca é `alta`.
- `premissas`, `invalidadores` e `nao_incluido` são listas de strings de uma linha e não são
  vazias. `tasks_a_quebrar` lista ids `T-NN.MM` de tasks que NÃO foram estimadas e NÃO entram
  nos totais; `[]` quando nenhuma.
- `tasks_estimadas` é a contagem de tasks que entraram nos totais — não inclui as de
  `tasks_a_quebrar`.

### `docs/sprintx/estimativas/HISTORICO.md` → `kind: estimativa_historico`

Arquivo do PROJETO, não de um trabalho: acumula entradas de todos os trabalhos e vive fora de
`docs/sprintx/features/<slug>/`. É o único arquivo da skill que é **apendado**, nunca sobrescrito.

```yaml
---
expx_schema: 1
expx_tool: sprintx
kind: estimativa_historico
trabalho_id: null
atualizado_em: 2026-08-29
unidade: h
entradas:
  - trabalho_id: exportacao-csv-relatorios
    task_id: T-01.01
    tipo_task: config
    area: configuracao de ambiente
    sinais: [arquivo_novo_isolado]
    estimado_min: 2
    estimado_max: 4
    estimado_media: 3
    real: 3.5
    desvio: 1.17
    registrado_em: 2026-08-29
calibracao:
  - tipo_task: config
    entradas: 4
    desvio_medio: 1.15
    fator_ativo: true
---
```

Regras duras deste kind:

- `trabalho_id` do cabeçalho comum é `null` — a chave existe (regra 6), mas o arquivo não
  pertence a um trabalho. O `trabalho_id` de cada linha vive dentro de `entradas:`.
- `tipo_task` segue o enum `tipo_task`; `sinais` é a lista dos sinais declarados na estimativa
  (`[]` se nenhum).
- `estimado_min`, `estimado_max`, `estimado_media` e `desvio` são `null` quando o trabalho
  rodou sem a F3.5; `real` é sempre preenchido.
- `desvio` é `real / estimado_media`. `fator_ativo` só é `true` com 3 ou mais entradas
  encerradas daquele tipo.
- `calibracao` é `[]` enquanto não houver entrada suficiente para calcular desvio por tipo.

### `FECHAMENTO.md` → `kind: fechamento`

Gravado pela F6 ao fechar a última task, em
`docs/sprintx/features/<slug>/FECHAMENTO.md`. Um por trabalho; reexecutar o fechamento
sobrescreve o arquivo.

É o equivalente, do lado Build, ao relatório técnico da runx: o registro do que a feature
entregou, com o módulo, os arquivos e os termos que a tornam encontrável depois. **Sem ele,
feature nova não entra no índice** — o trabalho continuaria existindo em disco e seria
invisível para quem perguntasse "quem já mexeu neste arquivo".

```yaml
---
expx_schema: 1
expx_tool: sprintx
kind: fechamento
trabalho_id: exportacao-csv-relatorios
titulo: Exportacao de relatorios em CSV
tipo_trabalho: feature
fechado_em: 2026-08-29
modulo_afetado: [relatorios, exportacao]
arquivos_alterados: [src/relatorios/exportador.ts, src/relatorios/exportador.test.ts, src/api/rotas/relatorios.ts]
palavras_chave: [csv, exportacao, relatorio, streaming]
resumo: Relatorios passam a ser exportados em CSV por streaming, sem carregar tudo em memoria
decisao_principal: Exportacao assincrona via fila existente, para nao segurar a resposta do usuario
risco_residual: Limite de linhas do CSV nao foi testado acima de 500 mil registros
testes_adicionados: 14
---
```

Abaixo do frontmatter vai prosa curta com o MESMO conteúdo — resumo, decisão principal e
risco residual em texto corrido, para quem lê sem parser. O YAML é para a máquina, a prosa é
para a pessoa, e as duas dizem a mesma coisa (regra universal 7).

Regras duras deste kind:

- `modulo_afetado`, `arquivos_alterados` e `palavras_chave` são **cópia fiel** do que o
  `ORQUESTRADOR.md` carrega no momento do fechamento. Se divergirem, o orquestrador é a
  fonte: corrija o fechamento, nunca o contrário.
- `resumo`, `decisao_principal` e `risco_residual` são strings de UMA linha (regra universal
  8). `risco_residual` é o que ficou por observar; quando nada ficou, escreva a frase que diz
  isso (`Nenhum risco residual identificado`), nunca `null` — a chave não é opcional e um
  fechamento sem análise de risco é um fechamento incompleto, não um fechamento sem risco.
- `decisao_principal` é a decisão de MAIOR IMPACTO do trabalho, uma só. Normalmente é uma das
  linhas `D-NN` de `00-DECISOES.md`; quando for, use a mesma redação.
- `testes_adicionados` é um número (inteiro), a contagem de testes criados pelo trabalho —
  não a contagem de testes da suíte inteira.
- `fechado_em` é a data do sistema (`date +%Y-%m-%d`) no dia do fechamento.
- Este kind não tem `atualizado_em`: o fechamento é um registro de um instante, não um
  arquivo de estado que evolui. `fechado_em` é a sua data.

### `00-PLANEJAMENTO.md` → `kind: planejamento`

**Kind exclusivo da `sprintx`** — a `sprintx` é a dona dele, e ele não é compartilhado com a
runx. É o **estado durável do planejamento**: em que ponto do laço F3 ↔ F5 a feature está,
quantas vezes a F5 reprovou o plano e qual é o teto de reprovações que o caller declarou.
Nasce na F1, a partir de `assets/TEMPLATE-PLANEJAMENTO.md`, e é gravado **só** por
`scripts/planejamento.sh` (caminho relativo à raiz da skill) — nunca à mão, em fase nenhuma.

```yaml
---
expx_schema: 1
expx_tool: sprintx
kind: planejamento
trabalho_id: exportacao-csv-relatorios
max_reprovacoes_f5: 3
max_replanejamentos_f6: 1
orcamento_declarado_por: buildx
estado: replanejar
reprovacoes: 2
replanejamentos_f6: 0
bloqueios_replanejamento_f6: []
tasks_congeladas: []
assinatura_congeladas: null
atualizado_em: 2026-08-29
historico:
  - rodada: 1
    veredito: nao
    altas: 6
    medias: 2
    baixas: 5
    auditado_em: 2026-08-28
  - rodada: 2
    veredito: nao
    altas: 3
    medias: 3
    baixas: 1
    auditado_em: 2026-08-29
---
```

**É artefato de método, e só isso.** `00-PLANEJAMENTO.md` não é task, não é produto, não é
entrega e não é desvio. Vive na pasta da feature, junto dos outros artefatos de método, e é
tratado como eles por quem versiona e classifica (`docs/sprintx/features/<slug>/`).

Regras duras deste kind:

- `max_reprovacoes_f5` é `null` (sem teto) ou um inteiro `>= 1`: a quantidade máxima de
  **vereditos NÃO** permitidos. Zero, negativo, texto ou qualquer outra forma é **erro de
  contrato**, e o script recusa.
- `orcamento_declarado_por` identifica quem declarou o teto (`buildx`, por exemplo). É `null`
  se e somente se `max_reprovacoes_f5` e `max_replanejamentos_f6` forem ambos `null`: teto sem
  dono, ou dono sem teto, é erro de contrato. A `sprintx` sozinha **nunca inventa orçamento** —
  ela grava `null`/`null`.
- `estado` segue o enum `estado` (planejamento). É `null` da F1 até o fim da F2; a partir daí,
  é sempre um dos oito valores. Nenhum outro estado existe.
- `reprovacoes` é um inteiro `>= 0` e é sempre igual à quantidade de rodadas `nao` do
  `historico`.
- `historico` é **append-only**: uma entrada por veredito da F5, na ordem, com `rodada`
  (1, 2, 3…), `veredito` (`sim` \| `nao`), as contagens `altas`, `medias` e `baixas` da tabela de
  `00-AUDITORIA.md` e `auditado_em`. Rodada anterior nunca é reescrita nem removida. Sem
  rodada, `historico: []`.
- `aprovado` só existe com a última rodada `sim`; `orcamento_esgotado` só existe com
  `reprovacoes >= max_reprovacoes_f5`. Arquivo que contradiz isso é contrato inválido e nada é
  decidido em cima dele.

**O eixo da F6 — replanejamento da execução.** Quando a F6 registra `defeito_de_plano`, o plano
volta ao planejamento por um estado próprio, `replanejar_execucao`, com orçamento próprio. Ele
não é o `replanejar` da F5 e não mexe no orçamento dela.

- `max_replanejamentos_f6` é `null` ou um inteiro `>= 1`: quantas rodadas de replanejamento da
  execução o caller permite. **Mesmo dono** do orçamento da F5 (`orcamento_declarado_por`), passado
  pelo mesmo caminho — o quarto argumento de `planejamento.sh criar`. `null` é "não declarado": a
  `sprintx` sozinha não inventa orçamento, e **sem orçamento o replanejamento da execução não abre**.
  Diferente do `null` da F5 (sem teto), mas pela mesma razão: nos dois eixos `null` preserva o
  comportamento de antes do contrato — laço até SIM na F5, nenhum caminho de volta na F6.
- `replanejamentos_f6` é um inteiro `>= 0`, nunca acima do teto, e `0` enquanto o teto for `null`.
  É consumido quando uma rodada **nova** é aceita; retomar a mesma rodada não consome de novo.
- `bloqueios_replanejamento_f6` lista, em ordem crescente de id, os B-NN `defeito_de_plano` abertos
  que abriram a rodada ativa. Lista preenchida = rodada ativa; `[]` = nenhuma. É o que torna a
  rodada retomável sem memória da sessão.
- `tasks_congeladas` e `assinatura_congeladas` congelam, durante a rodada, as tasks `concluida`:
  os ids e a assinatura (`cksum`) do item de cada uma no frontmatter do `tasks.md` e do seu bloco
  na prosa. `[]`/`null` sem rodada ativa. Todo portão da rodada (`avanca f3`, `f4`, `f5` e o
  fechamento) recalcula e recusa com código `4` qualquer diferença.
- `replanejar_execucao` só existe com rodada ativa e a última rodada da F5 `sim`; os estados do laço
  que a rodada percorre (`aguardando_f4`, `aguardando_f5`, `replanejar`, `orcamento_esgotado`)
  aceitam a lista preenchida. `replanejamento_execucao_esgotado` só existe sem rodada ativa e com
  `replanejamentos_f6 >= max_replanejamentos_f6`. `aprovado` com a lista ainda preenchida é um
  fechamento de rodada gravado e não terminado: `fase` responde `CHECKPOINT` e só `checkpoint`
  completa.
- No `historico`, uma rodada depois de um `sim` só existe quando um replanejamento da execução a
  abriu: no máximo uma sequência assim por unidade de `replanejamentos_f6`.
- **Legado.** `00-PLANEJAMENTO.md` gravado antes deste eixo não tem as cinco chaves: continua
  válido, é lido como `orcamento_f6=legado` e **nunca ganha orçamento** — nem na leitura, nem numa
  regravação, nem num `criar` de retomada (pedir teto da F6 a um arquivo legado é erro de contrato,
  código `4`). As cinco chaves existem todas ou nenhuma. Arquivo novo, inclusive o de migração da
  tabela antiga, nasce com as cinco.

**`kind: planejamento` e o painel.** O painel do `expxdev` pode ignorar este kind até ganhar
suporte a ele. Isso **não afeta** a execução da `sprintx`: nenhuma lógica da skill depende de o
painel reconhecer o kind — a máquina de estados lê o arquivo pelo script, localmente, sem
`expxdev` instalado.

### Arquivos SEM frontmatter

Não recebem frontmatter, porque o painel não os lê individualmente:

- os arquivos de recurso da base (um por recurso/área, de `TEMPLATE-base-recurso.md`);
- `base/00-LACUNAS.md`;
- `00-AUDITORIA.md`.

Não acrescente frontmatter a eles: um `kind` fora deste contrato é uma violação, não uma extensão.

## Como localizar o `CONVENCOES.md` — regra única

O `CONVENCOES.md` é insumo **externo**: quem o escreve é a `stackx` (ou a `buildx`, no B2). A
`sprintx` só lê. Todo ponto da skill que consulta convenções — a base da F1 (branch base e
comando de instalação), a F2, o `modulo_afetado` da F3 e da F4, a F6 e o hook
`tdd-teste-antes` — localiza o arquivo assim, e esta é a única descrição da regra.

Procure, a partir da raiz do repositório (a do worktree, quando houver), **nesta ordem**:

1. `CONVENCOES.md` — na raiz: override explícito do próprio projeto;
2. `docs/stack/CONVENCOES.md` — **caminho canônico** da `stackx` e da `buildx`;
3. `docs/stackx/CONVENCOES.md` — compatibilidade com o layout antigo;
4. `.expx/CONVENCOES.md` — fallback legado.

- **O primeiro que existir vence, e só ele é lido.** Dois ou mais presentes: os demais são
  ignorados. Nunca mescle o conteúdo, nunca escolha por data de modificação, por tamanho ou
  por "o mais novo" — a mesma árvore resolve sempre para o mesmo arquivo.
- **Nenhum existir** é o caso normal de projeto sem `stackx`, nunca erro: cada consumidor
  segue o seu próprio fallback (o `modulo_afetado` cai para a estrutura de pastas; o hook
  `tdd-teste-antes` fica inativo; a branch base e a instalação seguem a ordem de
  `references/01-ingestao.md`).
- **A `sprintx` nunca cria, edita nem reescreve `CONVENCOES.md`**, em nenhum dos quatro
  caminhos e em nenhuma fase. Convenção errada vira achado ou decisão registrada, não edição.

## Regra de migração — pastas que já existem

Ao abrir uma pasta de trabalho que já existe e cujos arquivos NÃO têm frontmatter:

1. A skill acrescenta o frontmatter na PRÓXIMA VEZ que gravar aquele arquivo, inferindo
   os valores a partir da prosa existente.
2. A skill NUNCA reescreve em massa nem sai migrando pastas ou arquivos que não vai tocar.
3. Se um valor não puder ser inferido da prosa com segurança, use `null` (ou `[]` para
   lista) e siga — nunca invente, nunca pergunte, nunca pare. A chave sempre existe.
4. Migrar o frontmatter NÃO autoriza reescrever a prosa: a prosa existente é preservada
   como está.
5. **Exceção: `classe` de bloqueio nunca é inferida da prosa.** Na migração, B-NN antigo fica
   sem a chave `classe` — legado, não `null` e não um valor adivinhado (DS-139).

## Verificação antes de gravar

Antes de dar por gravado qualquer arquivo de estado:

- [ ] O bloco `---` é a primeira coisa do arquivo e está fechado.
- [ ] O cabeçalho comum (`expx_schema`, `expx_tool`, `kind`, `trabalho_id`) está presente.
- [ ] Nenhuma chave do kind foi omitida — ausente é `null`/`[]`, nunca chave faltando.
- [ ] Nenhum acento em chave ou em valor de enum.
- [ ] Datas em `AAAA-MM-DD`; `atualizado_em` reescrito nesta gravação.
- [ ] Em `kind: tasks`, toda task tem `teste_integracao` e `teste_funcional` não vazios.
- [ ] Em `kind: decisoes`, `densidade` e `modo_construcao` estão preenchidos e a linha `D-00` existe. No modo `autonomo`, toda decisão sem resposta direta do usuário tem `(HIPOTESE)` no início do `motivo`.
- [ ] Em `kind: estimativa`, `min` e `max` sao diferentes (numero unico e proibido) e nenhum valor e data de calendario.
- [ ] Em `kind: orquestrador`, as tres chaves de indexacao (`modulo_afetado`, `arquivos_alterados`, `palavras_chave`) existem — vazias sao `[]`, nunca ausentes — e nao tem acento nem maiuscula.
- [ ] Em `kind: fechamento`, `arquivos_alterados` nao tem repeticao e bate com o `ORQUESTRADOR.md`.
- [ ] Em `kind: bloqueios`, todo B-NN novo tem `classe` do enum e `scripts/bloqueios.sh validar <slug>` responde `valido=sim`.
- [ ] Nenhum caminho absoluto em nenhum valor.
