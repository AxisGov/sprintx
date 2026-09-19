# O rastro de eventos — contrato `expx-eventos` v1

Leitura obrigatória quando a skill grava uma transição (F1–F6) ou quando a F3.5 vai calibrar estimativa com esforço real.

O rastro é um arquivo **append-only**, uma linha JSON por evento:

```
docs/eventos/<trabalho_id>.jsonl
```

Escrito pelos hooks e **pela própria skill nas transições de fase e de task**. Lido pelo painel de operação. **Ninguém edita à mão.**

`<trabalho_id>` é o `<slug-da-feature>` — o mesmo da pasta `docs/sprintx/features/<slug>/` e do frontmatter.

## O que a skill grava (e o que os hooks gravam)

| Evento | Quem grava |
|---|---|
| `fase_iniciada` · `fase_concluida` | **a skill**, ao entrar e sair de cada fase |
| `task_iniciada` · `task_concluida` · `task_bloqueada` | **a skill**, na F6 |
| `veredito_emitido` | **a skill/agente**, na F5 (auditor) |
| `checkpoint_planejamento` | **`scripts/planejamento.sh`**, ao fim da F2, F3, F4, a cada veredito da F5 e ao entrar em `replanejar_execucao`, `replanejamento_execucao_esgotado` ou `replanejamento_execucao_recusado`. `resultado`: `ok` (`commitado`, `sem_mudanca`), `aviso` (checkpoint ignorado: sem Git, outra branch, pasta ignorada), `bloqueado` (path staged fora da pasta da feature) ou `falha` (`persistencia_falhou`: o commit foi rejeitado). `avanca` recusado por checkpoint pendente também grava `bloqueado`. O `detalhe` começa pelo resultado do checkpoint |
| `replanejamento_execucao_iniciado` · `replanejamento_execucao_retomado` · `replanejamento_execucao_aprovado` · `replanejamento_execucao_esgotado` · `replanejamento_execucao_recusado` | **`scripts/planejamento.sh`**: rodada nova aceita (`fase: f6`, `ok`, com os B-NN que a abriram e as reprovações da F5 em curso); `replanejar-execucao` chamado de novo na mesma rodada (`ok`, orçamento não consumido); F5 aprovou o plano replanejado e a rodada fechou (`fase: f5`, `ok`); orçamento da F6 consumido e o estado terminal gravado (`bloqueado`); transição recusada (`bloqueado`, o motivo no começo do `detalhe`): a recusa **operacional** — `classes_mistas`, `orcamento_f6_legado`, `orcamento_f6_nao_declarado`, `planejamento_legado` — é registrada uma vez, quando o terminal `replanejamento_execucao_recusado` é gravado (a repetição não registra de novo); a de contrato — nenhum bloqueio aberto, nenhum `defeito_de_plano`, fronteira insegura, task concluída alterada — a cada tentativa, sem estado gravado. O evento é rastro, não fonte: a retomada lê o motivo de `00-PLANEJAMENTO.md` |
| `task_reaberta` | **`scripts/planejamento.sh`**, no fechamento da rodada: a task do B-NN volta de `bloqueada` a `pendente` (`fase: f5`, `task` preenchida). Task concluída nunca gera este evento |
| `bloqueio_resolvido` | **`scripts/bloqueios.sh resolver`**, ao gravar `resolvido_em` (`fase: null`, `task` do B-NN; a classe, inalterada, vai no `detalhe`) |
| `agente_iniciado` · `agente_concluido` | hook `SubagentStop` e a skill |
| `suite_executada` · `arquivo_alterado` | hook `PostToolUse` |
| `regra_violada` | hook, em modo aviso |
| `acao_bloqueada` | hook, em modo bloqueio |

Você não grava o que o hook já grava. Gravar duas vezes o mesmo fato faz o painel contar em dobro.

## Formato da linha

Chaves em `snake_case` sem acento, enums minúsculos sem acento, datas ISO, e **chave nunca omitida** — ausente é `null`. As mesmas regras do `expx-schema` (`references/00-schema.md`).

```json
{"ts":"2026-08-29T14:32:10Z","expx_eventos":1,"trabalho_id":"exportacao-csv","ferramenta":"sprintx","origem":"skill","evento":"task_concluida","fase":"f6","task":"T-01.02","agente":"principal","resultado":"ok","detalhe":"suite verde, 14 testes","arquivos":["src/frete/calculo.ts"]}
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

## Como gravar

Acrescente **uma linha** ao arquivo, sem reescrever nada do que já está lá:

```bash
mkdir -p docs/eventos
printf '%s\n' '{"ts":"...","expx_eventos":1,...}' >> docs/eventos/<trabalho_id>.jsonl
```

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
