# F6 — EXECUÇÃO

Você está na F6. A partir de agora você implementa até o fim, sob as regras de autonomia. Você NÃO pergunta nada, NÃO pede autorização para nada e NÃO para no meio. Toda a ambiguidade já foi eliminada nas fases anteriores; se você sentir falta de uma decisão, isso é um bloqueio a registrar, nunca uma pergunta a fazer.

## Pré-requisitos verificáveis

- `docs/sprintx/features/<slug>/00-AUDITORIA.md` existe e contém `VEREDITO: SIM`.
- O estado do planejamento é `aprovado`: `scripts/planejamento.sh fase <slug>` responde `F6`.
- Se contém `VEREDITO: NÃO`, volte para a F3. Se não existe, falta a F5: diga qual fase falta e execute-a primeiro.
- Com o estado em `orcamento_esgotado` **não existe F6**: a F6 nunca começa, nem por pedido de retomada, nem com `ORQUESTRADOR.md` pronto.

## Passo 1 — Carregar o mapa

Leia `docs/sprintx/features/<slug>/ORQUESTRADOR.md` inteiro e siga a ordem de leitura que ele define. Ele é a fonte da rota, do paralelismo, do caminho crítico, das ferramentas e da definição de pronto. Em caso de conflito entre a sua memória da conversa e o ORQUESTRADOR, vale o ORQUESTRADOR.

Se está retomando uma sessão interrompida, siga a seção "Como retomar" do ORQUESTRADOR: status em cada `tasks.md` + `00-BLOQUEIOS.md` dizem onde você parou.

**O estado da barra.** Ao carregar o mapa, grave `fase: f6` em `.expx/estado.json`
(`references/09-estado.md`). Numa retomada, aproveite e reconcilie os contadores com o que o
disco diz de verdade — `tasks_total`, `tasks_concluidas` e `bloqueios` — porque a sessão
anterior pode ter morrido entre a gravação de `tasks.md` e a do estado. O disco é a verdade; o
`estado.json` é a cópia para exibição.

## Passo 1.1 — Abertura do trabalho no repositório

Se `.claude/skills/mergex/SKILL.md` existir, acione a **etapa E0 da `mergex`** agora: depois de
ler o `ORQUESTRADOR.md`, antes da primeira task. Sem a `mergex` instalada, siga direto para o
Passo 2 — a F6 roda exatamente como sempre rodou, e a ausência dela não gera aviso nenhum.

Num projeto OpenCode a skill pode estar em `.opencode/skills/mergex/SKILL.md` (é para lá que o
`install.sh` copia as skills de projeto nesse harness). **Qualquer um dos dois caminhos conta
como "a `mergex` instalada"**, e é assim que os dois harnesses enxergam a mesma integração;
daqui em diante este arquivo diz só "se a `mergex` existir".

A F1 já abriu `feature/<slug>` e o worktree da feature (regra 21). O E0 **adota** o que existe:
não troca de branch, não cria uma segunda, não renomeia a da F1, não remove worktree e **não
exige árvore limpa** para isso — os artefatos de F1 a F5 estão na árvore e, com Git, já nos
checkpoints de planejamento da `feature/<slug>` (`references/02-descoberta.md`), que é
exatamente onde deveriam estar. Ele registra a branch no `ORQUESTRADOR.md` e cria
`docs/entregas/<slug>/ENTREGA.md`.

Se **não** houver branch para este trabalho (execução sem git, "sem worktree" explícito, ou
fluxo que não passou pela F1), o E0 cria `feature/<slug>` a partir da base — e aí a árvore
precisa estar limpa. Se a `mergex` avisar que há alteração não commitada pendente nesse caso,
**pare a F6** e repasse o aviso: não se começa a executar por cima de trabalho não salvo de
outra pessoa.

Se a `mergex` avisar que a branch do trabalho está em **outro worktree**, pare a F6 e repasse o
caminho: o trabalho continua de dentro daquele diretório.

Você aciona e devolve o controle: **nenhum comando de versionamento entra na F6 por sua conta**.
A branch e o worktree continuam sendo da F1; o versionamento é da `mergex`.

## Passo 2 — Executar task a task

Ordem: sprints em ordem numérica; dentro da sprint, a rota do ORQUESTRADOR. Só execute em paralelo o que o plano declarou paralelizável. Uma task só começa quando todas em `depende_de` estão `concluida`.

Para CADA task, nesta ordem:

**Antes de abrir**, quando há mais de uma sessão trabalhando na mesma feature (regra 21,
"Sessões paralelas" do `SKILL.md`): checagem de reivindicação — leia
`docs/eventos/<trabalho_id>.jsonl` e procure, para a task em questão, o `task_iniciada` mais
recente. Se ele foi gravado por outra sessão e não há `task_concluida`/`task_bloqueada` dela
depois, a task está reivindicada — não a abra. Pule para a próxima paralelizável cujas
dependências estão satisfeitas; sem nenhuma, registre um bloqueio.

1. Marque `status: em_andamento` em `tasks.md` e grave `task_iniciada` no rastro (`references/08-rastro.md`). Grave `task: T-NN.MM` em `.expx/estado.json` (`references/09-estado.md`).

   **Passo 2.0 — obrigação de `fraco:teste`, antes de qualquer código de produto.** Liste as
   obrigações que a última F5 deixou:

   ```bash
   bash <raiz-da-skill>/scripts/planejamento.sh obrigacoes-f6 <slug>
   ```

   Cada linha é `task`, `cláusula` e `implementação errada`, de um achado `[fraco:teste]` (MÉDIA).
   Para toda task que aparece ali, **antes de escrever qualquer código de produto**, e não no
   fechamento da task:

   1. localize a cláusula citada (`criterio_aceite`, `D-NN`, `base/<arquivo>` ou `origem:<ref>`);
   2. fortaleça o teste declarado, ou crie o que falta, para provar essa cláusula;
   3. demonstre que o teste **discrimina explicitamente** a implementação errada registrada — o
      teste precisa falhar contra ela;
   4. rode e obtenha **vermelho pelo motivo esperado**: a asserção da cláusula, não erro de
      compilação, import ou fixture;
   5. **somente então** implemente (passo 3).

   **Se não conseguir tornar o teste discriminante, registre bloqueio da task** (Regra de
   bloqueio, abaixo) e **não implemente**. É TDD sem atalho: teste discriminante primeiro, produto
   depois — um `fraco:teste` que chega à implementação sem ter sido endurecido deixa de ser MÉDIA
   e vira exatamente o teste verde e falso que a F5 existia para impedir.
2. **Escreva o teste de integração e o teste funcional ANTES de qualquer código de implementação**, exatamente como a task os descreve. Rode-os e confirme que falham (vermelho).
3. Implemente até os dois testes passarem (verde). **Rode o subconjunto de testes afetado pela task** — os que ela criou ou alterou, mais os que cobrem os arquivos em `arquivos.cria` e `arquivos.altera` — e grave `suite: parcial`.

   A suíte inteira roda **uma vez, ao fechar a sprint** (ver "Portões de fase e de sprint"). Rodá-la ao fim de cada task custa uma execução completa por task e não descobre nada que a execução do portão não descubra — só descobre mais cedo, ao preço de repetir tudo N vezes. Se o subconjunto ficar difícil de delimitar, rode a suíte inteira e grave `suite: verde`: o valor mais forte nunca é violação.

   O que não muda: **task com teste vermelho não fecha**, seja o subconjunto ou a suíte inteira. `parcial` significa "o que era desta task passou", nunca "passou mais ou menos".
4. Assuma os três papéis do ORQUESTRADOR, em sequência: implementador (passos 2–3), revisor de testes, auditor de aceite (o `criterio_aceite` é verdade agora? verifique de fato, não presuma).

   **O papel de revisor de testes é do agente `revisor-testes`, quando ele existir neste harness.** Acione-o sobre a task que está fechando: ele lê os testes e responde no formato determinístico (`T-NN.MM | solido`, ou `T-NN.MM | fraco | <tipo> | <cláusula> | <implementação errada>`). Passe a ele também as implementações erradas que a última F5 registrou como `[fraco:teste]` para esta task (`obrigacoes-f6`): além do julgamento normal, ele confere que **cada uma delas é discriminada** pelo teste escrito. **A task não conclui se alguma delas continuar passando.** Um `fraco` significa que o teste passaria com a implementação errada — e teste fraco é pior que teste ausente, porque produz suíte verde e falsa confiança. Task com teste `fraco` NÃO fecha: corrija o teste até ele discriminar, e só então siga. Sem o agente disponível, faça você mesma a pergunta, com o mesmo rigor.
5. Só então marque `status: concluida` em `tasks.md` e grave `task_concluida` no rastro, acrescentando na linha da task: data (obtenha com `date +%Y-%m-%d` do sistema) e resultado da suíte (ex.: `2026-08-26 · suíte: 42 passed, 0 failed`). Em seguida grave em `.expx/estado.json` (`references/09-estado.md`) o novo `tasks_concluidas` e o campo `task`: o id da próxima task que você vai abrir, ou `null` se não houver próxima.
6. **Registre o esforço real da task**, em horas de trabalho focado, na mesma linha (ex.: `2026-08-26 · suíte: 42 passed, 0 failed · real: 3,5 h`). O real cobre o que a task de fato custou — escrever os dois testes, implementar, rodar a suíte e verificar o critério de aceite — e NÃO inclui reunião, revisão de código, deploy nem ida e volta com o cliente. Isso alimenta a calibração das estimativas futuras (ver "Passo 4"); anote no momento de concluir, não reconstrua de memória no fim do trabalho.
7. Critério de aceite não atendido ou teste não passando: a task NÃO é concluída. Não existe "concluído com ressalva".
8. **Atualize a cor daquele nó no diagrama**, quando a sprint tiver diagrama. **Sprint condensada (`tasks.md` com `kind: plano`) não tem `fases.md` e não tem diagrama** — a F3 só gera o bloco Mermaid quando grava `fases.md`. Nesse caso pule este passo inteiro, **sem registrar aviso**: não há diagrama ausente, há um formato que não usa diagrama. Tendo `fases.md`: troque a classe na linha `class` do nó da task, e nada mais (`concluida`, `em_andamento` ou `bloqueada`, conforme `references/09-diagrama.md`). Não recalcule o caminho crítico, não reordene, não reescreva o bloco — durante a execução a estrutura do grafo não muda, só a cor. Se a atualização falhar, ou se `fases.md` não tiver bloco Mermaid (plano de uma versão anterior da skill), registre no rastro com `resultado: aviso` e siga: o diagrama é derivado e **nunca** impede uma task de fechar.

9. **O commit da task.** Se `.claude/skills/mergex/SKILL.md` existir, acione a **etapa E1 da `mergex`** para esta task. Ela commita os arquivos de produto declarados em `arquivos`, mais os artefatos de método deste trabalho que estiverem sujos (a pasta `docs/sprintx/features/<slug>/`, a começar pelo `tasks.md` que você acabou de atualizar), com a mensagem que traz o objetivo e os testes da task, depois de varrer o diff em busca de segredo, credencial e dado real de cliente.

   **A ordem é obrigatória e é esta:** teste → implementação → suíte afetada → revisão de testes → aceite → `status: concluida` → `tasks.md` atualizado (data, resultado da suíte e esforço real dos passos 5 e 6) → E1. O commit registra a task **já marcada** como concluída, e é o `tasks.md` atualizado que dá à mensagem o objetivo e os testes.

   **`suite: parcial` fecha task e sustenta commit** — é o registro normal da F6, e a suíte inteira continua sendo cobrada no fechamento da sprint. O E1 barra apenas `suite: vermelha` e `suite: nao_executada`.

   Se a `mergex` abortar o commit por suspeita de segredo, **não contorne**: a task fica sem commit, o aviso vai para o relatório final, e o portão de prontidão vai barrá-la depois.

   **Task marcada `bloqueada` não gera commit** — a regra de bloqueio abaixo segue para a próxima task sem passar por aqui. Sem a `mergex` instalada, a task fecha no passo 8, como sempre fechou.

**Frontmatter (obrigatório) — o YAML e a prosa andam juntos.** Cada arquivo de estado que
você tocar na F6 é gravado com o frontmatter do contrato expx-schema v1
(`references/00-schema.md`, leitura obrigatória antes da primeira gravação). Ao atualizar o
status de uma task, atualize TANTO o frontmatter QUANTO a prosa do bloco — nunca só um dos
dois. A cada gravação de `tasks.md`:

- `status` da task na lista `tasks:` do frontmatter recebe o mesmo valor que a prosa
  (`pendente` → `em_andamento` → `concluida`, ou `bloqueada`).
- `atualizado_em` do arquivo é reescrito com a data do sistema (`date +%Y-%m-%d`).
- `concluida_em` recebe a data quando a task passa a `concluida`; permanece `null` em
  qualquer outro status.
- `suite` recebe `parcial` quando o subconjunto afetado pela task terminou com 0 failed,
  `verde` quando foi a suíte inteira que rodou sem falha, `vermelha` quando houve falha, e
  permanece `nao_executada` enquanto nada rodou para aquela task.

**Onde gravar, nos dois formatos.** A lista `tasks:` acima é a mesma chave nos dois formatos —
`kind: tasks` e `kind: plano` carregam tasks idênticas —, então fechar uma task funciona igual
em ambos. O que muda é onde ficam a fase e a sprint (regra única em `references/00-schema.md`):

- **Condensado** (`tasks.md` com `kind: plano`): tudo vive no mesmo frontmatter, num único
  bloco YAML. Fechar fase atualiza o item correspondente em `fases`; fechar sprint atualiza
  `sprint.status`. Você reescreve um arquivo só.
- **Três arquivos**: fechar fase atualiza `fases.md`; fechar sprint atualiza `sprint.md`.

Em qualquer dos dois, `atualizado_em` do arquivo tocado é reescrito, e o YAML e a prosa daquele
arquivo continuam dizendo a mesma coisa.

Deixar o frontmatter desatualizado em relação à prosa equivale a não ter gravado a task: o
painel de operação lê o YAML, não a prosa.

## Regra de bloqueio — nunca parar

Surgiu dúvida nova, decisão não coberta pelo plano, pré-requisito faltando (segredo inexistente, serviço fora do ar, dependência quebrada):

1. Registre em `docs/sprintx/features/<slug>/00-BLOQUEIOS.md`: `B-NN | task | descrição do bloqueio | o que destravaria`.
2. Marque a task como `status: bloqueada` em `tasks.md` e grave `task_bloqueada` no rastro, e grave `bloqueios` em `.expx/estado.json` com a nova contagem de bloqueios **abertos** (`references/09-estado.md`). Um bloqueio resolvido depois diminui essa contagem, na mesma gravação em que `resolvido_em` deixa de ser `null`.
   Ao registrar o bloqueio, grave também o frontmatter `kind: bloqueios` de `00-BLOQUEIOS.md` (novo item em `bloqueios:` com `id`, `task`, `aberto_em` com a data do sistema, `resolvido_em: null` e `descricao` em uma linha) e reescreva `atualizado_em`. Formato em `references/00-schema.md`. A task muda para `bloqueada` no frontmatter e na prosa de `tasks.md`.
3. Pule para a próxima task paralelizável cujas dependências estão satisfeitas.
4. NUNCA pare para esperar resposta humana. Se não resta nenhuma task executável, encerre com o relatório final — os bloqueios são a pauta do usuário, não uma conversa sua.

## Portões de fase e de sprint

- Fase só é dada como concluída quando seu `criterio_saida` é verdade.
- Sprint só é dada como concluída quando seu `criterio_saida` é verdade.
- **Onde esses critérios moram depende do formato da sprint** (regra única em `references/00-schema.md`, "Como resolver o formato de uma sprint"): nos três arquivos, em `fases.md` e `sprint.md`; no condensado (`tasks.md` com `kind: plano`), em `fases[].criterio_saida` e `sprint.criterio_saida` do frontmatter do próprio `tasks.md`. **Nenhuma condição afrouxa por causa do formato** — só muda onde você lê e onde você grava.
- Critério não atendido = não avança para a próxima fase/sprint; trate como bloqueio se não houver task que o resolva.

### A suíte inteira é cobrada aqui

**Confira antes que a árvore não tem trabalho de outra sessão** (regra 21): arquivo sujo
(`git status --porcelain --untracked-files=all`) fora do `arquivos` de qualquer task da
feature, ou task `em_andamento` reivindicada por outra sessão. Achando qualquer um dos dois,
**não rode a suíte e não feche a sprint** — anuncie o que está contaminando a árvore e
aguarde; isso não é falha da sprint, é árvore ainda não pronta.

**Antes de dar qualquer sprint como concluída, rode a suíte INTEIRA e exija 0 failed.**

Durante a sprint cada task roda o subconjunto que lhe cabe e grava `suite: parcial`. É neste
portão que a garantia de que nada mais quebrou é efetivamente cobrada — a sprintx não tem um
estágio de QA depois da execução, então o fim da sprint é o último ponto em que uma quebra
colateral ainda é barata de achar.

- Suíte inteira vermelha: a sprint **não fecha**. Corrija, ou registre bloqueio em
  `00-BLOQUEIOS.md` e trate como qualquer outro critério de saída não atendido.
- Suíte inteira verde: cole a saída no relatório da sprint e siga. As tasks daquela sprint
  **permanecem com `suite: parcial`** — o valor descreve o que rodou para aquela task, e
  reescrevê-lo em massa apagaria justamente essa informação.
- Escreva a suíte inteira no `criterio_saida` da sprint desde a F3, para que o portão seja
  verificável e não dependa de alguém lembrar dele aqui.

## Passo 3 — Atualizar o histórico de esforço

Ao fim do trabalho (tudo concluído, ou nada mais executável), atualize `docs/sprintx/estimativas/HISTORICO.md` a partir de `assets/TEMPLATE-HISTORICO.md` (`kind: estimativa_historico`, contrato em `references/00-schema.md`). Este é o único arquivo da skill que é **apendado**, nunca sobrescrito: entrada de trabalho anterior não se apaga nem se reescreve. Se o arquivo não existir, crie-o a partir do template.

**Quem é dono deste arquivo.** `docs/sprintx/estimativas/HISTORICO.md` é o **artefato global de
método da `sprintx`**. Ele não é arquivo de produto, não pertence a nenhuma task e **não é
feature-local**: mora fora de `features/` porque a calibração atravessa trabalhos, é lida por
features futuras e precisa sobreviver a máquina, sessão e worktree. Por isso ele é
**deliberadamente versionado** — ao contrário do rastro e do `.expx/estado.json`, que são
estado local e ficam fora do versionador (`references/01-ingestao.md`).

Com a `mergex` instalada, a `sprintx` **escreve** e a `mergex` **versiona**: o `HISTORICO.md`
entra no commit de artefatos de método que antecede o push (E6), junto com os artefatos da
feature, e **não deve aparecer como desvio** na classificação de atenção humana — ele é
artefato de método declarado, não arquivo fora do plano. Continua sujeito à varredura de
segredo como qualquer outro arquivo do commit.

Sem a `mergex`, a `sprintx` grava o arquivo do mesmo jeito e **não commita**: versionamento
nunca é trabalho desta skill na F6 — a única exceção são os checkpoints de planejamento, que
terminam antes dela (`references/02-descoberta.md`). Um `HISTORICO.md` não rastreado ao fim de uma execução standalone
é o resultado esperado, não uma pendência.

Uma entrada por task **concluída**, com: `trabalho_id`, `task_id`, `tipo_task`, `area`, `sinais`, `estimado_min`, `estimado_max`, `estimado_media`, `real` e `desvio`. Task `bloqueada` não entra — ela não tem real completo a registrar.

**O desvio.** Se `docs/sprintx/features/<slug>/00-ESTIMATIVA.md` existe, cada entrada traz o estimado daquela task e o desvio entre estimado e real:

```
desvio_task = real / estimado_media          # estimado_media = (o + 4m + p) / 6
```

`1,0` é o alvo; `1,4` significa que levou 40% a mais que o previsto.

**A duração observada, vinda do rastro.** O rastro registra o instante de `task_iniciada` e de `task_concluida`, o que dá a duração de cada task **sem ninguém anotar nada** (`references/08-rastro.md`). Use-a para conferir o `real` que você anotou no Passo 2 — mas **não a confunda com esforço**:

> Tempo de parede não é esforço. Uma task "aberta" por seis horas pode ter tido vinte minutos de trabalho e um almoço no meio.

Por isso a duração vinda do rastro entra no `HISTORICO.md` como `duracao_observada`, um campo distinto de `real`, e **nunca a substitui**. Quando as duas divergirem muito, vale o `real` — e a divergência é, ela própria, um sinal de que a task teve interrupção.

Pela mesma razão, a calibração usa **mediana**, não média: um único intervalo com pausa no meio distorce uma média e quase não move uma mediana.

Se a F3.5 não rodou (não existe `00-ESTIMATIVA.md`), registre o real mesmo assim, com `estimado_min`, `estimado_max`, `estimado_media` e `desvio` em `null`: o real continua alimentando a comparabilidade por tipo e área nas estimativas futuras.

**Recalcule a tabela de calibração por tipo** ao acrescentar as entradas: para cada `tipo_task`, `desvio_medio` é a média dos `desvio_task` de todas as entradas encerradas daquele tipo, e `fator_ativo` é `true` a partir de 3 entradas. Esse desvio é o que vira fator de correção nas estimativas seguintes — e ele é sempre declarado na saída da estimativa, nunca embutido em silêncio (`references/07-estimativa.md`).

Se houve estimativa, inclua no relatório final (Passo 4) uma linha por sprint com estimado × real e o desvio, para que a divergência fique visível junto com as demais.

## Passo 3.1 — Fechar o trabalho: agregar e gravar o `FECHAMENTO.md`

Ao fechar a **última task** (tudo concluído, ou nada mais executável), o trabalho ainda não
acabou: falta torná-lo encontrável. Este passo é o que coloca a feature no índice.

**Primeiro, agregue no `ORQUESTRADOR.md`.** Percorra todos os `sprint-NN/tasks.md` do trabalho
e monte a união dos campos `arquivos` (`cria` + `altera`) de **todas as tasks `concluida`**:

- Task `bloqueada` ou `pendente` **não entra** — ela não alterou arquivo nenhum.
- **Sem repetição.** O mesmo arquivo tocado por seis tasks aparece UMA vez. Um arquivo que uma
  task `cria` e outra `altera` também aparece uma vez só: a lista é de arquivos, não de
  eventos.
- Caminhos relativos à raiz do repositório, na mesma forma em que aparecem nas tasks. Ordene
  como preferir; a ordem não é contrato, a ausência de duplicata é.

Grave o resultado em `arquivos_alterados` no frontmatter do `ORQUESTRADOR.md`, e confira que
`modulo_afetado` continua verdadeiro: se a execução tocou um módulo que o plano não previa
(uma divergência do Passo 4, seção 4), acrescente-o agora — o campo descreve o que foi feito,
não o que se pretendia fazer. Reescreva `atualizado_em`, e também `estagio`, `status` e
`concluido_em`, como o critério de saída desta fase já exige.

**Depois, grave `docs/sprintx/features/<slug>/FECHAMENTO.md`**, a partir de
`assets/TEMPLATE-FECHAMENTO.md` (`kind: fechamento`, contrato em `references/00-schema.md`). Os três campos de indexação são cópia fiel do que o
`ORQUESTRADOR.md` acabou de receber. Os quatro campos de conteúdo saem do trabalho que você
acabou de executar:

- `resumo` — uma linha sobre o que a feature entregou. O que o sistema faz agora que não fazia
  antes, não o que você fez.
- `decisao_principal` — a decisão de maior impacto, uma linha. Normalmente uma das linhas
  `D-NN` de `00-DECISOES.md`; quando for, use a mesma redação. Quando a decisão de maior
  impacto tiver surgido na execução, é ela que entra.
- `risco_residual` — o que ficou por observar: limite não testado, bloqueio aberto, caminho
  que a suíte não cobre. Nada ficou? Escreva a frase que diz isso — a chave nunca é `null`.
- `testes_adicionados` — quantos testes o trabalho criou (não o tamanho da suíte).

Abaixo do frontmatter, prosa curta com o **mesmo conteúdo**: resumo, decisão principal e risco
residual em texto corrido, como esta skill já escreve para humano. O YAML e a prosa dizem a
mesma coisa.

O `FECHAMENTO.md` é o equivalente, do lado Build, ao relatório técnico da runx.
**Sem ele, feature nova não entra no índice**: um `memox` instalado no projeto conheceria
apenas as ocorrências, e metade da história do sistema ficaria invisível para o próximo
trabalho — inclusive para o seu. Não deixe este passo para "depois do relatório": o relatório
é para o usuário desta sessão, o fechamento é para quem chegar daqui a seis meses.

Se o trabalho terminou com tasks bloqueadas (nada mais executável), o `FECHAMENTO.md` é
gravado do mesmo jeito, com o que de fato foi entregue: `arquivos_alterados` traz só as tasks
concluídas, e os bloqueios abertos são o `risco_residual`. Um fechamento parcial registrado
vale mais que um fechamento perfeito que nunca aconteceu.

**Por último, feche o trabalho no estado da barra.** Com o `FECHAMENTO.md` gravado, grave
`.expx/estado.json` com `trabalho: null`, `fase: null` e `task: null`
(`references/09-estado.md`). `tasks_concluidas` e `tasks_total` ficam como estão: são o placar
do que foi entregue, e a barra continua mostrando `4/9` depois do fim, o que é exatamente a
informação útil. `bloqueios` fica com a contagem dos que continuaram abertos. O arquivo
continua existindo — fechar trabalho não é apagar o estado.

Este é o último passo do trabalho, e é o mais dispensável de todos: se `.expx/` não existir, ou
se a gravação falhar, o trabalho está entregue do mesmo jeito. Registre no rastro e siga.

## Passo 3.2 — Entrega

Se `.claude/skills/mergex/SKILL.md` existir, acione as **etapas E2 a E8 da `mergex`**, nesta
ordem: portão de prontidão, classificação da atenção humana, descrição do pull request, pacote
de QA, push, abertura do PR e registro da entrega. Os artefatos de método deste
trabalho são a pasta `docs/sprintx/features/<slug>/` **e** o `docs/sprintx/estimativas/HISTORICO.md`
(Passo 3), que é global e entra no mesmo commit de artefatos, antes do push. Sem a `mergex` instalada, siga direto para o
Passo 4 — e não escreva nada sobre a ausência dela.

**A ordem é crítica, e este passo vem depois do Passo 3.1 inteiro.** Primeiro a execução
possível termina, depois os portões de sprint rodam, depois o `FECHAMENTO.md` é gravado — e
**só então** E2 a E8. O `FECHAMENTO.md` precisa já existir quando o E2 começa, porque ele entra
no commit de artefatos de método que a `mergex` faz antes do push; gravado depois, ficaria de
fora da entrega.

Se o portão devolver `BLOQUEADO`, **inclua no relatório final o que ele apontou** e não tente
contornar: a `mergex` barra e explica, nunca maquia. Achado de auditoria ALTA em aberto na F5
faz o portão barrar, e sprint fechada sem a suíte inteira registrada aparece como aviso do
portão.

**A integração para no E8.** Não sugira o merge, não encadeie a revisão e não mencione o
comando de revisão da `mergex` — nem no relatório, nem como próximo passo, nem como dica.
Integrar código é decisão humana: o desenvolvedor chama a revisão pelo nome, quando quiser.

## Passo 4 — Relatório final

Ao terminar (tudo concluído, ou nada mais executável), entregue ao usuário um relatório com exatamente estas seções — a 5ª existe apenas quando a `mergex` estiver instalada:

1. **Concluído por sprint** — por sprint: tasks concluídas / total, e o que ficou funcionando.
2. **Bloqueios** — o conteúdo de `00-BLOQUEIOS.md` (ou "nenhum").
3. **Saída da suíte** — o resultado da última execução completa da suíte de testes, colado, não resumido de memória.
4. **Divergências entre o plano e a realidade** — tudo que foi diferente do planejado (arquivo a mais, teste ajustado, limite da base que se comportou diferente), uma linha por divergência.
5. **Entrega** — **somente quando a `mergex` estiver instalada** (Passo 3.2), com o que estiver disponível: a branch, a quantidade de commits, o resultado do portão, a contagem das três faixas de atenção humana, e a URL do pull request (ou o caminho de `PR.md`, quando a ferramenta do serviço não estiver disponível). Se o portão devolveu `BLOQUEADO`, é aqui que o motivo aparece, dito com todas as letras. Sem a `mergex`, esta seção **não existe**: não a crie vazia e não avise que ela falta.

Ao entregar o relatório, informe também, em uma linha, que o `FECHAMENTO.md` foi gravado e
quais módulos ele declara — é assim que o usuário sabe que a feature entrou no índice.

## Critério de saída da fase

- [ ] Toda task está `concluida` ou `bloqueada` (nenhuma `pendente`/`em_andamento` executável restante).
- [ ] `tasks.md` atualizado com data e resultado de suíte em cada task concluída.
- [ ] Toda task concluída tem `suite: parcial` ou `suite: verde` — nenhuma com `vermelha` ou `nao_executada`.
- [ ] Toda sprint concluída teve a suíte INTEIRA executada e verde, com a saída colada no relatório.
- [ ] Em todo arquivo de estado tocado, o frontmatter está válido e coerente com a prosa: `status`, `concluida_em`, `suite` e `atualizado_em` refletem o estado real (`references/00-schema.md`).
- [ ] Se o trabalho inteiro foi entregue, `ORQUESTRADOR.md` teve `estagio`, `status`, `concluido_em` e `atualizado_em` reescritos; sprints e fases concluídas tiveram `status` atualizado onde o formato daquela sprint o guarda — `sprint.md` e `fases.md` nos três arquivos, `sprint.status` e `fases[].status` do `tasks.md` no condensado.
- [ ] Toda task concluída tem o esforço real registrado em `tasks.md`.
- [ ] Toda task que chegou da F5 com `[fraco:teste]` teve o teste endurecido e vermelho pelo motivo esperado antes do primeiro código de produto, e o `revisor-testes` confirmou que cada implementação errada registrada é discriminada — ou a task está `bloqueada` sem implementação.
- [ ] `docs/sprintx/estimativas/HISTORICO.md` recebeu uma entrada por task concluída, com o desvio calculado (ou `null` quando não houve estimativa), e a tabela de calibração por tipo foi recalculada.
- [ ] `ORQUESTRADOR.md` teve `arquivos_alterados` agregado (união sem repetição dos `arquivos` das tasks concluídas) e `modulo_afetado` conferido contra o que a execução de fato tocou.
- [ ] `FECHAMENTO.md` existe em `docs/sprintx/features/<slug>/` com frontmatter `kind: fechamento` válido e a prosa correspondente abaixo dele.
- [ ] Relatório final entregue com as 4 seções — 5 quando a `mergex` estiver instalada, com a seção **Entrega**.
- [ ] Com a `mergex` instalada: o E0 rodou depois do `ORQUESTRADOR.md` e antes da primeira task, o E1 rodou depois de cada task dada como `concluida`, e o E2 a E8 rodaram com o `FECHAMENTO.md` já gravado. Portão `BLOQUEADO` aparece no relatório e não foi contornado. Sem a `mergex`, nenhum desses passos aconteceu e nada nesta fase mudou por causa disso.
- [ ] `.expx/estado.json` fechou o trabalho (`trabalho`, `fase` e `task` em `null`), ou `.expx/` não existe no projeto, ou a falha de gravação está registrada no rastro. Este item **nunca impede** a fase de ser dada como concluída: o arquivo é de exibição, e sua ausência é inofensiva.
