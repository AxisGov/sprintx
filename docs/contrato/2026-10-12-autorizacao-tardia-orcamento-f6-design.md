# Autorização tardia do orçamento F6 — design

Data: 2026-10-12
Status: aprovado em conversa, aguardando aprovação formal desta especificação
Base: `796895a9e61739d94f6d970259a5c392044a2110` (`p0.2/sprintx-rastro-identidade`)

## 1. Problema

A SprintX exige que o orçamento de retorno da F6 ao planejamento seja declarado na criação do
trabalho. Quando `max_replanejamentos_f6` é `null` e a execução encontra um
`defeito_de_plano`, `planejamento.sh replanejar-execucao` grava e persiste o terminal
`replanejamento_execucao_recusado`, com
`recusa_replanejamento_f6: orcamento_f6_nao_declarado`.

Essa recusa é correta no instante em que acontece: a skill não pode inventar orçamento. O contrato,
porém, não oferece um ato posterior para a autoridade humana declarar o orçamento ausente. O único
caminho aparente seria editar `00-PLANEJAMENTO.md` à mão, o que falsificaria a origem do orçamento,
apagaria a recusa durável e contornaria as verificações de fronteira, congelamento e trabalho
parcial.

O caso real que revelou a lacuna é a MP2.7b. O planejamento chegou ao terminal exato acima com um
`defeito_de_plano` aberto, uma task bloqueada e trabalho parcial legítimo na árvore. O usuário
autorizou depois uma rodada F6. O framework precisa representar essa decisão sem reescrever o
passado nem ampliar a recuperação para outros terminais.

## 2. Objetivos

1. Permitir que uma autoridade externa declare tardiamente um orçamento F6 que antes era `null`.
2. Preservar, de forma verificável, que houve uma recusa anterior por orçamento não declarado.
3. Declarar o orçamento e abrir a rodada em uma única transição de estado.
4. Reusar integralmente as guardas atuais de bloqueio, task, fronteira, congelamento e parciais.
5. Manter idempotência, persistência por checkpoint local e retomada por outra sessão.
6. Falhar fechado para qualquer terminal, motivo ou fronteira diferente do caso autorizado.
7. Manter compatibilidade aditiva com planejamentos anteriores.

## 3. Fora de escopo

- Aumentar um orçamento F6 já declarado.
- Reabrir `replanejamento_execucao_esgotado`.
- Recuperar planejamento legado ou eixo F6 legado.
- Resolver `classes_mistas` por precedência implícita.
- Alterar o orçamento da F5 ou reiniciar suas reprovações.
- Reabrir task concluída, apagar bloqueio ou reescrever histórico da F5.
- Editar, descartar, guardar em stash ou commitar o trabalho parcial da task.
- Criar uma API genérica de reabertura de terminais.
- Alterar BuildX, MergeX, ExpxDev ou um produto nesta entrega da SprintX.

## 4. Alternativas avaliadas

### 4.1 Comando atômico e restrito — escolhido

Um comando novo valida o terminal específico, registra a autorização tardia, declara o teto e abre
a rodada F6 no mesmo estado gravado e no mesmo checkpoint. Não há janela em que o orçamento existe
mas a rodada não foi aberta; a causa anterior fica auditável; e a recuperação não se generaliza.

### 4.2 Reabrir o terminal e chamar `replanejar-execucao` depois — rejeitado

Entre as duas operações, outra sessão poderia executar F6 sobre um plano já conhecido como
defeituoso, o processo poderia morrer, ou o usuário poderia observar um estado que nunca deveria
existir. A recusa histórica também ficaria mais fácil de apagar.

### 4.3 Criar outro trabalho/planejamento — rejeitado para este caso

Duplicaria a história, perderia a ligação com o B-NN, as tasks concluídas e a árvore parcial, e
obrigaria a reconstruir contexto válido. Continua sendo saída humana para terminais realmente
irrecuperáveis, mas não é a cura deste defeito de contrato.

## 5. Decisão DS-175

| # | Ambiguidade | Decisão tomada | Motivo |
|---|---|---|---|
| DS-175 | Como continuar quando a F6 gravou `replanejamento_execucao_recusado` exclusivamente porque `max_replanejamentos_f6` era `null`, e a autoridade humana declara o orçamento depois — sem editar o planejamento à mão, apagar a recusa ou reabrir outros terminais | Introduzir `planejamento.sh autorizar-replanejamento-execucao <slug> <max_replanejamentos_f6> <autorizado_por>`. O comando só aceita `estado: replanejamento_execucao_recusado`, `recusa_replanejamento_f6: orcamento_f6_nao_declarado`, eixo F6 presente, teto `null`, contador `0` e nenhuma rodada ativa. Ele registra a autorização tardia, declara o teto e abre a primeira rodada F6 em uma única transição, reutilizando as mesmas provas de bloqueios, task bloqueada, fronteira segura, congelamento e trabalho parcial de `replanejar-execucao`. A recusa deixa de ser a condição ativa, mas sua causa permanece em campos de auditoria, no rastro e no commit. Qualquer outro terminal ou motivo continua terminal | `null` significa ausência de decisão, não decisão de orçamento zero. Uma autorização humana posterior é um fato novo legítimo, mas voltar primeiro a `aprovado` criaria um estado intermediário inseguro, e uma reabertura genérica apagaria a diferença entre orçamento ausente, orçamento consumido, legado e classes misturadas. A transição atômica preserva a causalidade: recusa correta, autorização posterior, rodada aberta uma única vez |

Esta decisão amplia a DS-141 apenas quanto à proveniência tardia. A regra normal continua sendo
declarar os dois orçamentos no `criar`. Quando a autorização F6 chega depois, sua autoridade fica em
campos próprios e não reescreve silenciosamente a autoridade já gravada para a F5.

## 6. Interface pública

```text
planejamento.sh autorizar-replanejamento-execucao \
  <slug> <max_replanejamentos_f6> <autorizado_por>
```

- `slug`: contrato atual de slug.
- `max_replanejamentos_f6`: inteiro positivo, sem valor padrão.
- `autorizado_por`: identificador minúsculo no mesmo formato de
  `orcamento_declarado_por`, sem valor padrão.

O comando não presume `1`, não presume `usuario` e não lê autorização de texto livre, comentário,
rastro ou memória de sessão. Quem o invoca precisa fornecer os dois valores.

Saída de aplicação inicial:

```text
autorizacao_f6=aplicada
estado=replanejar_execucao
replanejamentos_f6=1
max_replanejamentos_f6=<max>
autorizado_por=<autorizado_por>
proxima=F3
persistencia=duravel|pendente
```

Se a mesma autorização já abriu a rodada e ela continua ativa, responde
`autorizacao_f6=retomada`, o estado/fase atuais e os mesmos teto e autoridade. Nenhum contador,
evento ou commit novo é criado.

Se o arquivo de planejamento já contém exatamente a autorização e a rodada pedidas, mas o
checkpoint ainda não tornou essa versão durável, a recuperação é reconhecida **antes** da
pré-condição de terminal e responde:

```text
autorizacao_f6=checkpoint_pendente
estado=replanejar_execucao
proxima=CHECKPOINT
persistencia=pendente
```

Essa resposta não escreve de novo, não incrementa a rodada e não duplica evento. O operador deve
executar `planejamento.sh checkpoint <slug>`; depois da persistência durável, a mesma chamada
responde `autorizacao_f6=retomada`.

Códigos:

- `0`: aplicada, ou retomada idempotente.
- `2`: fronteira insegura, parcial divergente ou parcial perdido.
- `3`: checkpoint/persistência pendente ou falhou, conforme o contrato atual.
- `4`: argumento, schema, auditoria ou invariante inválida; inclui repetição com argumentos
  diferentes.
- `5`: transição não autorizada para o estado ou motivo atual.
- `64`: uso incorreto.

## 7. Schema e auditoria

Três chaves escalares opcionais são adicionadas ao `kind: planejamento`:

```yaml
autorizacao_tardia_f6_por: usuario
autorizacao_tardia_f6_em: 2026-10-12
autorizacao_tardia_f6_origem: orcamento_f6_nao_declarado
```

Regras:

1. As três existem juntas ou nenhuma existe.
2. A origem aceita somente `orcamento_f6_nao_declarado` nesta decisão.
3. A data usa o mesmo formato das demais datas do planejamento.
4. As chaves são append-only: depois de gravadas, todos os escritores as preservam.
5. Nunca coexistem com `recusa_replanejamento_f6`, que descreve a condição terminal ativa.
6. Só são válidas com eixo F6 presente, teto positivo e `replanejamentos_f6 >= 1`.
7. Planejamentos sem as três chaves continuam válidos sem migração.

`max_replanejamentos_f6` passa de `null` para o valor autorizado. A fonte canônica e única da
autoridade tardia da F6 é sempre `autorizacao_tardia_f6_por`. Leitores, validadores, rastro e
mensagens nunca inferem essa autoridade de `orcamento_declarado_por`, e o comando tardio nunca
altera esse campo compartilhado. Se ele já tinha valor por causa de orçamento F5, permanece
intacto; se era `null`, continua `null`. Para validar um teto F6 positivo, o schema exige uma das
duas condições explícitas: **(a)** `orcamento_declarado_por` não é `null`, porque o dono foi
declarado no `criar`; ou **(b)** as três chaves tardias são válidas e
`autorizacao_tardia_f6_por` não é `null`. A condição (b) é exclusiva da autorização tardia e não
afrouxa a validação de planejamentos sem as três chaves.

O evento novo é `orcamento_f6_autorizado`; seu detalhe inclui teto, autoridade, origem terminal e
B-NN abertos. O evento existente `replanejamento_execucao_iniciado` continua registrando a rodada,
congeladas e parciais. Os dois são gravados uma vez; uma retomada não os duplica.

## 8. Transição atômica

Depois de adquirir a trava e reler o disco, o comando avalia primeiro a recuperação de uma
aplicação já escrita. A presença dos três campos tardios com rodada ativa seleciona esse caminho,
antes da guarda de terminal. A ordem fechada de decisão é:

1. compara `<max_replanejamentos_f6>` e `<autorizado_por>` pedidos com os valores já gravados;
   qualquer diferença retorna código `4`;
2. recalcula e confere congeladas, assinatura e parciais; perda ou divergência retorna código `2`;
3. se a versão ainda não é durável, relê `00-BLOQUEIOS.md` e as tasks: cada B-NN gravado na rodada
   ainda precisa estar aberto, ser `defeito_de_plano` e apontar uma task ainda `bloqueada`; qualquer
   desvio retorna código `4` e proíbe persistir a versão;
4. se a versão ainda não é durável e as provas do passo 3 passam, retorna
   `autorizacao_f6=checkpoint_pendente`, código `3`, sem escrever nem registrar evento; o único
   próximo passo é `planejamento.sh checkpoint <slug>`;
5. se a mesma versão já é durável, retorna `autorizacao_f6=retomada`, código `0`.

Essa ordem também vale quando mais de uma condição seria observável: argumentos divergentes têm
precedência sobre parcial divergente; numa versão pendente, as provas de bloqueio/task precedem a
persistência; somente depois vêm `checkpoint_pendente` ou `retomada`.

Somente na aplicação inicial, antes de qualquer escrita, o comando exige:

1. persistência atual durável e nenhum fechamento pendente;
2. estado e motivo terminais exatos;
3. eixo F6 presente, teto `null`, contador `0` e nenhuma rodada ativa;
4. pelo menos um B-NN aberto, todos `defeito_de_plano`;
5. toda task referenciada gravada como `bloqueada`;
6. fronteira segura segundo o contrato atual.

Depois:

1. calcula tasks concluídas e assinatura;
2. calcula o trabalho parcial da árvore pelos mesmos critérios atuais;
3. define teto e `replanejamentos_f6: 1`;
4. grava B-NN, congeladas, assinatura e parciais;
5. grava as três chaves de auditoria tardia;
6. remove a chave ativa `recusa_replanejamento_f6`;
7. grava `estado: replanejar_execucao` por substituição atômica do arquivo;
8. registra os dois eventos;
9. executa um único checkpoint F6, rodada 1.

Não se chama `replanejar-execucao` como segunda operação. A lógica comum de abertura deve ser
extraída e usada pelos dois comandos, para impedir deriva.

Os campos de orçamento, auditoria e rodada aparecem juntos numa única versão do arquivo. Falha
antes da substituição preserva o terminal. Se o arquivo for substituído, mas o hook rejeitar o
commit, vale a semântica atual: `CHECKPOINT` pendente, concluído apenas por
`planejamento.sh checkpoint <slug>`. A próxima invocação reconhece esse estado antes da guarda de
terminal, conforme o primeiro parágrafo desta seção. Não há rollback destrutivo nem segunda
rodada.

O próprio `checkpoint` reconhece uma autorização tardia ainda não durável, valida os valores já
gravados e executa as mesmas conferências de rodada dos passos 2 e 3 antes de commitar. Assim,
chamar `checkpoint` diretamente depois de o B-NN ser fechado ou a task deixar de estar bloqueada
também falha sem persistir o estado.

## 9. Concorrência e idempotência

O comando usa trava por worktree e slug, resolvida por `git rev-parse --git-path`, adquirida por
`mkdir` atômico e removida por `trap`. Trava existente falha fechada e não é removida
automaticamente. Depois de adquiri-la, o comando relê todas as pré-condições.

Esta decisão usa a definição já executada pelo contrato de `replanejar-execucao`: a rodada está
ativa quando `bloqueios_replanejamento_f6` é não vazia e o estado pertence a
`replanejar_execucao`, `aguardando_f4`, `aguardando_f5`, `replanejar`, `orcamento_esgotado` ou
`aprovado`. O caso `aprovado` com a lista não vazia é fechamento pendente: esta operação retorna
código `3`, `proxima=CHECKPOINT`, em vez de `retomada`. A rodada fecha somente quando
`fecha_rodada` esvazia `bloqueios_replanejamento_f6`; depois disso, esta operação retorna código
`5` e a autorização fica apenas como histórico.

Nos demais estados da rodada ativa, uma repetição segue exatamente a ordem da seção 8:
argumentos, provas da rodada e só então durabilidade. Portanto, chamada divergente retorna código
`4`; parcial perdido ou divergente retorna código `2`; chamada idêntica pendente retorna
`checkpoint_pendente`, código `3`; e chamada idêntica durável retorna `retomada`, código `0`.
Nenhuma repetição muda arquivo, evento, contador ou HEAD, nem volta a executar a transição inicial.

## 10. Terminais irrecuperáveis por este comando

O comando recusa, sem alteração:

- `classes_mistas`;
- `orcamento_f6_legado`;
- `planejamento_legado`;
- `replanejamento_execucao_esgotado`;
- `orcamento_esgotado`;
- orçamento F6 já positivo;
- rodada consumida sem a auditoria tardia correspondente;
- terminal, motivo ou schema desconhecido;
- recusas de contrato que nunca foram duráveis, como `sem_bloqueio_aberto` ou
  `fronteira_insegura`.

## 11. Trabalho parcial

No terminal atual não existe parcial preenchido: a falta de orçamento é detectada antes de
`fronteira_segura`. A autorização tardia calcula os parciais da worktree atual e os grava na mesma
transição. Outra árvore não reconstrói conteúdo que existia na árvore original.

As regras atuais continuam: ownership exclusivo pela task bloqueada, path declarado, arquivo
regular, estado Git mecânico, nada staged, nenhum segredo e hash de blob sem filtros.

## 12. Compatibilidade

- Arquivos existentes não são migrados na leitura.
- O comando só opera sobre eixo F6 presente; os legados permanecem terminais.
- As interfaces atuais permanecem iguais.
- `fase` expõe a auditoria tardia quando ela existir, sem remover linhas atuais.
- Bash 3.2, sem `jq`, Python, rede ou dependência nova.

## 13. Documentação e código afetados

A implementação futura deve atualizar, no mínimo:

- `.claude/skills/sprintx/scripts/planejamento.sh`;
- `.claude/skills/sprintx/references/00-schema.md`;
- `.claude/skills/sprintx/references/03-plano.md`;
- `.claude/skills/sprintx/references/06-execucao.md`;
- `.claude/skills/sprintx/references/08-rastro.md`;
- `.claude/skills/sprintx/DECISOES-DA-SKILL.md` com a DS-175;
- `.claude/skills/sprintx/SKILL.md`;
- `.claude/skills/sprintx/assets/TEMPLATE-PLANEJAMENTO.md`;
- `.claude/hooks/testes/bancada.sh`.

Wrappers OpenCode/Claude só mudam se a busca e os testes provarem que expõem uso ou enum atingido.

## 14. Testes obrigatórios

1. Caminho feliz com árvore limpa.
2. Caminho feliz com parcial novo, modificado e removido da task bloqueada.
3. `orcamento_declarado_por` nunca é alterado pelo comando tardio: dono F5 existente não é
   reatribuído e `null` continua `null`; autoridade F6 tardia fica separada e todos os leitores a
   obtêm exclusivamente de `autorizacao_tardia_f6_por`.
4. Sessão nova lê rodada e autorização só do estado commitado.
5. Cada terminal/motivo da seção 10 é recusado sem diff, evento ou commit.
6. Valores e autoridade inválidos são recusados.
7. Sem B-NN, classe errada, classes mistas e registro inválido são recusados.
8. Task não bloqueada é recusada.
9. Cada forma de fronteira insegura é recusada sem tocar na árvore.
10. Segunda chamada idêntica não incrementa, não commita nem duplica evento.
11. Segunda chamada com argumentos diferentes é recusada.
12. Checkpoint rejeitado deixa a autorização escrita e pendente; a repetição reconhece esse caso
    antes da guarda de terminal, retorna `checkpoint_pendente` com código 3 e não abre rodada 2;
    `planejamento.sh checkpoint <slug>` persiste exatamente essa versão; a repetição seguinte
    retorna `retomada` sem novo evento, contador ou commit.
13. Parcial perdido/divergente impede retomada.
14. Duas chamadas concorrentes produzem uma aplicação e uma recusa pela trava.
15. Trava obsoleta falha fechado.
16. As três chaves existem todas ou nenhuma.
17. Origem/data inválida ou coexistência com recusa ativa reprova.
18. Autorização sem teto positivo ou rodada consumida reprova.
19. Arquivos antigos continuam válidos.
20. Com checkpoint pendente e argumentos diferentes, retorna código 4 antes de considerar a
    persistência, sem alterar estado nem permitir o checkpoint divergente.
21. Com argumentos idênticos e parcial perdido ou divergente, retorna código 2 antes de
    `checkpoint_pendente` ou `retomada`.
22. Entre a escrita e o checkpoint, fechar o B-NN, mudar sua classe ou tirar a task de `bloqueada`
    faz tanto a repetição quanto `planejamento.sh checkpoint <slug>` recusarem a persistência.
23. `bloqueios_replanejamento_f6` não vazio identifica rodada ativa nos estados permitidos;
    `aprovado` com a lista preenchida retorna fechamento pendente; lista esvaziada por
    `fecha_rodada` faz a autorização retornar código 5.

## 15. Mutantes mínimos

1. Aceitar qualquer terminal recusado.
2. Aceitar `classes_mistas`.
3. Declarar teto sem incrementar a rodada.
4. Incrementar sem auditoria tardia.
5. Apagar a recusa sem preservar origem.
6. Abrir sem task bloqueada.
7. Abrir sem `fronteira_segura`.
8. Não gravar/conferir hash do parcial.
9. Segunda chamada consumir outra rodada.
10. Segunda chamada aceitar argumentos diferentes.
11. Reatribuir dono F5 existente.
12. Permitir recusa ativa e autorização tardia juntas.
13. Remover a trava de concorrência.
14. Considerar trava existente como sucesso.
15. Migrar automaticamente planejamento legado.
16. Aplicar a guarda de terminal antes de reconhecer a recuperação do checkpoint pendente.
17. Ler a autoridade tardia da F6 de `orcamento_declarado_por`, ou alterar esse campo durante a
    autorização tardia, em vez de preservar o valor e usar `autorizacao_tardia_f6_por`.
18. Retornar `checkpoint_pendente` antes de rejeitar argumentos divergentes.
19. Retornar `checkpoint_pendente` ou `retomada` antes de conferir perda/divergência dos parciais.
20. Persistir autorização pendente depois de B-NN fechado, classe alterada ou task desbloqueada.
21. Tratar `aprovado` com bloqueios preenchidos como retomada normal, ou tratar lista esvaziada
    como rodada ainda ativa.

Todos precisam ser mortos. A bancada atual do eixo F6 permanece verde sem enfraquecer os terminais.

## 16. Rollout e MP2.7b

1. Implementar e certificar a DS-175 na SprintX.
2. Integrar a correção na linhagem usada pelo produto.
3. Atualizar o pin e instalar a SprintX pelo fluxo normal do ExpxDev.
4. Na worktree original da MP2.7b, conferir terminal, B-NN, task e parciais.
5. Executar explicitamente:

   ```text
   planejamento.sh autorizar-replanejamento-execucao mp2-7b-recorte-listas 1 usuario
   ```

6. Conferir checkpoint, parciais e `fase=F3` antes de replanejar.

Nada nesta especificação autoriza editar a MP2.7b antes de a correção certificada estar instalada.
O produto preservado é evidência do caso, não bancada da SprintX.

## 17. Critérios de aceite da entrega futura

- Só o terminal e motivo definidos aceitam autorização tardia.
- A transição abre uma rodada válida sem estado intermediário.
- Recusa anterior e autoridade nova são auditáveis no arquivo, rastro e Git.
- Tasks concluídas e histórico F5 ficam intactos.
- Parcial legítimo é preservado; sujeira ambígua falha fechado.
- Repetição e concorrência não duplicam rodada, evento nem commit.
- Nenhum terminal legado, misto ou esgotado é reaberto.
- Testes e mutantes das seções 14 e 15 passam.
- A bancada completa fica verde nos ambientes suportados.
- A documentação nunca manda editar `00-PLANEJAMENTO.md` manualmente.
