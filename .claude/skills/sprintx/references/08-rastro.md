# O rastro de eventos — contrato `expx-eventos` v1

Leitura obrigatória quando a skill grava uma transição (F1–F6) ou quando a F3.5 vai calibrar estimativa com esforço real.

O rastro é um arquivo **append-only**, uma linha JSON por evento:

```
docs/eventos/<trabalho_id>.jsonl
```

Escrito pelos hooks, pelos scripts da skill e **pela própria skill nas transições de fase e de task — sempre pelo escritor `scripts/rastro.sh`** (seção "Como gravar"). Lido pelo painel de operação e pelos hooks. **Ninguém edita à mão.**

`<trabalho_id>` é o `<slug-da-feature>` — o mesmo da pasta `docs/sprintx/features/<slug>/` e do frontmatter.

## O que a skill grava (e o que os hooks gravam)

| Evento | Quem grava |
|---|---|
| `fase_iniciada` · `fase_concluida` | **a skill**, ao entrar e sair de cada fase, por `scripts/rastro.sh fase-iniciada` / `fase-concluida` |
| `task_iniciada` · `task_concluida` · `task_bloqueada` | **a skill**, na F6, **só** por `scripts/rastro.sh task-iniciada` / `task-concluida` / `task-bloqueada` — são a reivindicação da task que os hooks leem |
| `veredito_emitido` | **a skill/agente**, na F5 (auditor), por `scripts/rastro.sh veredito-emitido` |
| `checkpoint_planejamento` | **`scripts/planejamento.sh`**, ao fim da F2, F3, F4, a cada veredito da F5 e ao entrar em `replanejar_execucao`, `replanejamento_execucao_esgotado` ou `replanejamento_execucao_recusado`. `resultado`: `ok` (`commitado`, `sem_mudanca`), `aviso` (checkpoint ignorado: sem Git, outra branch, pasta ignorada), `bloqueado` (path staged fora da pasta da feature) ou `falha` (`persistencia_falhou`: o commit foi rejeitado). `avanca` recusado por checkpoint pendente também grava `bloqueado`. O `detalhe` começa pelo resultado do checkpoint |
| `replanejamento_execucao_iniciado` · `replanejamento_execucao_retomado` · `replanejamento_execucao_aprovado` · `replanejamento_execucao_esgotado` · `replanejamento_execucao_recusado` | **`scripts/planejamento.sh`**: rodada nova aceita (`fase: f6`, `ok`, com os B-NN que a abriram e as reprovações da F5 em curso); `replanejar-execucao` chamado de novo na mesma rodada (`ok`, orçamento não consumido); F5 aprovou o plano replanejado e a rodada fechou (`fase: f5`, `ok`); orçamento da F6 consumido e o estado terminal gravado (`bloqueado`); transição recusada (`bloqueado`, o motivo no começo do `detalhe`): a recusa **operacional** — `classes_mistas`, `orcamento_f6_legado`, `orcamento_f6_nao_declarado`, `planejamento_legado` — é registrada uma vez, quando o terminal `replanejamento_execucao_recusado` é gravado (a repetição não registra de novo); a de contrato — nenhum bloqueio aberto, nenhum `defeito_de_plano`, fronteira insegura, task concluída alterada — a cada tentativa, sem estado gravado. O evento é rastro, não fonte: a retomada lê o motivo de `00-PLANEJAMENTO.md` |
| `task_reaberta` | **`scripts/planejamento.sh`**, no fechamento da rodada: a task do B-NN volta de `bloqueada` a `pendente` (`fase: f5`, `task` preenchida). Task concluída nunca gera este evento |
| `bloqueio_resolvido` | **`scripts/bloqueios.sh resolver`**, ao gravar `resolvido_em` (`fase: null`, `task` do B-NN; a classe, inalterada, vai no `detalhe`) |
| `agente_concluido` | hook `SubagentStop` |
| `agente_iniciado` | reservado no contrato; nenhum passo do método o grava hoje |
| `suite_executada` · `arquivo_alterado` | hook `PostToolUse` |
| `regra_violada` | hook, em modo aviso |
| `acao_bloqueada` | hook, em modo bloqueio |

Você não grava o que o hook já grava. Gravar duas vezes o mesmo fato faz o painel contar em dobro.

## Em qual arquivo o evento entra

O destino é `docs/eventos/<trabalho_id>.jsonl` do **trabalho corrente** — e "corrente" tem uma definição mecânica, não uma heurística de disco:

| Quem grava | De onde sai o `<trabalho_id>` |
|---|---|
| a skill (F1–F6), `planejamento.sh`, `bloqueios.sh` | o slug da feature que a fase está tratando — a skill sempre o conhece |
| hook que conhece o trabalho | ele o **declara**: `rastro_grava_trabalho <raiz> <trabalho_id> <evento> ...` |
| hook sem contexto de trabalho | `rastro_grava <raiz> <evento> ...`, e o destino é o **trabalho corrente da sessão**: a reivindicação ativa dela no rastro (`task_iniciada` sem fechamento posterior), exatamente uma e coerente |
| nada disso resolve | `docs/eventos/sem-trabalho.jsonl` |

**`mtime` nunca seleciona o destino** (DS-155). "Qual feature mexeu por último no disco" é outra pergunta, e a resposta dela não pertence a esta: num repositório com features acumuladas, ou com duas sessões em trabalhos diferentes, ela manda o evento para o rastro errado sem ninguém perceber.

**Trabalho declarado que contradiz o trabalho provado pelo rastro da sessão é erro de contexto, e falha fechado**: a linha não entra nem num arquivo nem no outro. A incoerência é registrada em `sem-trabalho.jsonl` como `acao_bloqueada` com `contexto_de_trabalho_divergente` no `detalhe`, para o painel ver que o evento existiu e por que não foi atribuído.

## Formato da linha

Chaves em `snake_case` sem acento, enums minúsculos sem acento, datas ISO, e **chave nunca omitida** — ausente é `null`. As mesmas regras do `expx-schema` (`references/00-schema.md`). O formato é o contrato de quem **lê** o rastro; quem grava os eventos da skill é o escritor (seção "Como gravar"), que monta a linha inteira.

```json
{"ts":"2026-08-29T14:32:10Z","expx_eventos":1,"trabalho_id":"exportacao-csv","ferramenta":"sprintx","origem":"hook","evento":"arquivo_alterado","fase":null,"task":null,"agente":"principal","resultado":"ok","detalhe":"Edit","arquivos":["src/frete/calculo.ts"]}
```

| Campo | Conteúdo |
|---|---|
| `ts` | instante UTC ISO. Obtenha do sistema (`date -u +%Y-%m-%dT%H:%M:%SZ`), nunca de memória |
| `expx_eventos` | sempre `1` (versão do contrato) |
| `trabalho_id` | o slug da feature |
| `ferramenta` | `sprintx` |
| `origem` | `skill` \| `hook` |
| `evento` | um dos da tabela acima |
| `fase` | `f1`..`f6`, ou `null` |
| `task` | `T-NN.MM`, ou `null` |
| `agente` | `principal` \| `auditor-plano` \| `revisor-testes` \| `qa` \| `investigador` \| `cartografo` |
| `resultado` | `ok` \| `falha` \| `aviso` \| `bloqueado` |
| `detalhe` | uma linha de texto |
| `arquivos` | lista de caminhos relativos, ou `[]` |
| `sessao` · `harness` | identidade da sessão (`<harness>@<id>`), **derivada** pelo escritor `scripts/rastro.sh` — obrigatória em `task_iniciada`/`task_concluida`/`task_bloqueada`, `null` quando não existe num evento que não depende dela. Nunca é preenchida por quem chama |

## Como gravar

Pelo escritor da skill — o caminho é relativo à raiz desta skill, como o de `scripts/planejamento.sh`:

```bash
bash <raiz-da-skill>/scripts/rastro.sh task-iniciada  <slug> <T-NN.MM> ["<detalhe>"]
bash <raiz-da-skill>/scripts/rastro.sh task-concluida <slug> <T-NN.MM> ["<detalhe>"] [<arquivo> ...]
bash <raiz-da-skill>/scripts/rastro.sh task-bloqueada <slug> <T-NN.MM> ["<detalhe>"]
bash <raiz-da-skill>/scripts/rastro.sh fase-iniciada  <slug> <f1..f6> ["<detalhe>"]
bash <raiz-da-skill>/scripts/rastro.sh fase-concluida <slug> <f1..f6> ["<detalhe>"]
bash <raiz-da-skill>/scripts/rastro.sh veredito-emitido <slug> <SIM|NAO> ["<detalhe>"]
```

Exemplo, ao abrir e ao fechar a task `T-01.02` da feature `exportacao-csv`:

```bash
bash <raiz-da-skill>/scripts/rastro.sh task-iniciada exportacao-csv T-01.02
bash <raiz-da-skill>/scripts/rastro.sh task-concluida exportacao-csv T-01.02 "suite parcial verde, 14 testes" src/frete/calculo.ts test/frete/calculo.test.ts
```

| Você fornece | O mecanismo deriva — nunca é argumento |
|---|---|
| o evento (o subcomando) | `ts`, `expx_eventos`, `ferramenta`, `origem`, `agente` |
| `<slug>` — o trabalho da fase | o arquivo de destino `docs/eventos/<slug>.jsonl` e a coerência dele com o trabalho que a sessão já reivindica |
| a task, a fase ou o veredito | `fase` e `resultado` de cada evento |
| `detalhe` (uma linha, opcional) e, no `task-concluida`, os arquivos da task | **a identidade da sessão: `sessao` e `harness`** |

A identidade é o que liga a task à sessão que a abriu: é por ela que o hook `escopo-da-task` sabe que a edição seguinte pertence à task corrente. Você **não** a descobre, não a copia de mensagem nenhuma e não a escreve: o escritor a deriva do próprio harness pela mesma regra que os hooks usam para lê-la.

Respostas:

| Código | Significado | O que fazer |
|---|---|---|
| `0` | gravado; a saída diz `evento=`, `trabalho=`, `task=` e `rastro=` | siga |
| `3` | a identidade da sessão não está disponível neste processo (`task-*`) — **nada foi gravado** | não grave à mão; registre bloqueio `prerequisito_ausente` (`scripts/bloqueios.sh registrar`) |
| `4` | contrato: o trabalho não tem pasta, a task não está no plano do trabalho, ou a sessão ainda reivindica task aberta de **outro** trabalho — **nada foi gravado** no rastro pedido | corrija o slug/task, ou feche a task aberta do outro trabalho |
| `5` | ambiente: a biblioteca do rastro (`.claude/hooks/comum/rastro.sh`) não está instalada, ou a escrita falhou — **nada foi gravado** | siga sem o evento; não grave à mão |
| `64` | uso incorreto | releia o uso acima |

**Por que não à mão.** `task_iniciada`, `task_concluida` e `task_bloqueada` são lidos pelo enforcement (`escopo-da-task`, `task-reivindicada`, `arvore-limpa-antes-da-suite`): uma linha montada à mão sem a identidade que o hook espera não reivindica nada, e a primeira edição da task é bloqueada com `sessao_ambigua`. O escritor falha fechado — sem identidade válida, a linha não é gravada, nem incompleta. Evento de outra ferramenta (a `mergex`, por exemplo) segue o contrato daquela ferramenta.

**Anotação informativa.** Quando uma referência pede "uma linha no rastro com `resultado: aviso`" (atualização do diagrama que falhou, gravação do `.expx/estado.json` que falhou), a linha é informativa: nenhum hook a lê. Ela pode ser acrescentada no formato acima, append-only, com `"task": null` e um `evento` que **nunca** é `task_iniciada`, `task_concluida` ou `task_bloqueada` — esses três só saem do escritor.

Nunca use uma ferramenta de edição que reescreva o arquivo inteiro: o rastro é append-only, e reescrevê-lo destrói o histórico que o painel usa.

## Versionamento

O rastro é **ignorado pelo versionador** por padrão: é local da máquina de quem executou, cresce rápido, e o painel roda local. A F1 garante isso **localmente**, pelo `info/exclude` do repositório (caminho resolvido com `git rev-parse --git-path info/exclude`), e só quando o padrão ainda não é ignorado — ela **não** mexe no `.gitignore` versionado, que é decisão do projeto, não do trabalho (`references/01-ingestao.md`).

Rotação: acima de 5 MB, o arquivo vira `<trabalho_id>.1.jsonl` e um novo começa (os hooks fazem isso sozinhos). O painel lê os dois.

## O ganho lateral: esforço real sem ninguém anotar

`task_iniciada` e `task_concluida` trazem o instante de cada ponta, e daí sai a **duração observada** de cada task — o insumo que falta ao `HISTORICO.md` da F3.5, obtido sem ninguém anotar nada.

Um cuidado que não é opcional:

> **Tempo de parede não é esforço.** Uma task "aberta" por seis horas pode ter tido vinte minutos de trabalho e um almoço no meio.

Por isso:

1. O valor entra como **`duracao_observada`**, nunca como `real`, e nunca substitui o `real` anotado por quem executou.
2. A calibração usa **mediana**, não média — um intervalo com pausa no meio distorce uma média e quase não move uma mediana.
3. Divergência grande entre `duracao_observada` e `real` é sinal de interrupção, e vale registrar como tal em vez de "corrigir" um dos dois.
