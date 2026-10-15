# Predecessores verificáveis entre Superpowers, SprintX e MergeX

**Data:** 2026-10-13
**Estado:** aprovada para planejamento
**Repositório dono do contrato:** SprintX
**Consumidor do contrato:** MergeX

## 1. Problema

A MP2.7b criou uma especificação e um plano com Superpowers antes de abrir o trabalho formal na SprintX. A SprintX leu e citou os dois documentos durante a F1, mas não tinha um artefato de método capaz de declarar que eles eram predecessores legítimos do planejamento.

Ao final da execução, a MergeX aplicou corretamente a V9: comparou o diff real com a união dos arquivos declarados nas tasks e com as isenções exatas de método. Como os dois documentos não pertenciam a nenhuma task nem a uma isenção reconhecida, o portão bloqueou a entrega apesar de o código e todas as suítes estarem verdes.

Os caminhos observados foram:

- `docs/superpowers/specs/2026-10-13-mp2-7b-consolidacao-main-design.md`;
- `docs/superpowers/plans/2026-10-13-mp2-7b-consolidacao-main.md`.

Não é seguro resolver isso isentando `docs/superpowers/**`: qualquer arquivo futuro poderia escapar da V9 apenas por estar nessa pasta. Também não é correto apagar os documentos, alterar retroativamente tasks concluídas ou inventar uma task que não executou trabalho sobre eles.

## 2. Objetivo

Criar um protocolo exato e verificável para a SprintX declarar documentos predecessores consumidos na F1 e para a MergeX aceitá-los na V9 somente quando a história Git provar que:

1. o arquivo já existia antes do primeiro checkpoint SprintX;
2. o caminho foi declarado literalmente, sem glob ou prefixo;
3. o conteúdo atual é o mesmo conteúdo consumido pela SprintX;
4. a declaração veio de um artefato versionado da própria SprintX;
5. uma entrega bloqueada apenas por essa lacuna pode ser retomada sem reabrir ou reescrever tasks concluídas.

## 3. Não objetivos

- Não isentar genericamente `docs/superpowers/`, `docs/` ou qualquer outro prefixo.
- Não alterar o formato das tasks para acomodar arquivos que nenhuma task criou ou modificou.
- Não mudar Superpowers nesta rodada. Ele continua sendo um produtor genérico de documentos.
- Não aceitar arquivo sujo, não rastreado, removido, renomeado ou com conteúdo diferente do registrado.
- Não reabrir automaticamente entregas bloqueadas por V1–V8, V10, V11 ou por V9 com outros desvios.
- Não transformar a SprintX em dona do conteúdo dos documentos predecessores; ela registra que os consumiu.
- Não permitir força, opção de ignorar prova ou edição manual do estado terminal.

## 4. Decisão de arquitetura

A SprintX passa a emitir `docs/sprintx/features/<slug>/00-PREDECESSORES.md`, um artefato de método com caminhos exatos e provas Git. A MergeX acrescenta esse manifesto como uma fonte estrita adicional da V9, depois das tasks e das isenções de método, sem substituir nenhuma verificação existente.

O protocolo tem duas partes coordenadas:

- **prevenção:** a F1 registra os predecessores antes do checkpoint da F2;
- **recuperação:** uma entrega já bloqueada exclusivamente por V9 pode acrescentar o manifesto, provar os mesmos fatos históricos e voltar a `estado: aberto` por uma transição executável e restrita.

O manifesto não é uma autorização humana livre. Ele é uma afirmação mecanicamente verificável sobre a história Git.

## 5. Artefato `00-PREDECESSORES.md`

### 5.1 Local e kind

O caminho canônico é:

```text
docs/sprintx/features/<slug>/00-PREDECESSORES.md
```

O novo kind é exclusivo da SprintX:

```yaml
---
expx_schema: 1
expx_tool: sprintx
kind: predecessores
trabalho_id: mp2-7b-consolidacao-main
predecessores:
  - caminho: docs/superpowers/specs/2026-10-13-mp2-7b-consolidacao-main-design.md
    origem: superpowers
    papel: especificacao
    commit_sha: 85dff72f14e477bcd074050ac3b56a11911cfd60
    blob_oid: 7d3fe6903c1d43f685b2def2904b02e7e226213c
  - caminho: docs/superpowers/plans/2026-10-13-mp2-7b-consolidacao-main.md
    origem: superpowers
    papel: plano
    commit_sha: 4afd01a61c1ca51d14f58a59979606ae3047bae1
    blob_oid: aba5c1a22d90c22c022cc1e1549fd3c45e9fa993
criado_em: 2026-10-13
atualizado_em: 2026-10-13
---
```

A prosa abaixo do frontmatter repete os caminhos, a origem e o papel para leitura humana. A máquina usa apenas o frontmatter.

### 5.2 Campos

| Campo | Contrato |
|---|---|
| `trabalho_id` | Igual ao slug da pasta e ao trabalho que consumiu os documentos |
| `caminho` | Caminho relativo à raiz Git, literal, canônico, sob `docs/superpowers/` e seguro como scalar YAML sem aspas |
| `origem` | Nesta versão, somente `superpowers` |
| `papel` | `especificacao` ou `plano` |
| `commit_sha` | OID completo do último commit que tocou o caminho: 40 hexadecimais em SHA-1 ou 64 em SHA-256 |
| `blob_oid` | OID completo do blob regular em `<commit_sha>:<caminho>`, no mesmo formato de objetos |
| `criado_em`, `atualizado_em` | Datas ISO obtidas do sistema |

`predecessores` contém pelo menos um item. Arquivo presente com lista vazia não equivale a
manifesto ausente: é schema inválido e falha fechado.

### 5.3 Restrições de caminho

O registrador recusa:

- caminho absoluto;
- `..`, `.` ou segmento vazio;
- prefixo `./`;
- barra invertida;
- caractere de glob (`*`, `?`, `[` ou `]`);
- caminho fora de `docs/superpowers/`;
- sequência insegura em scalar YAML sem aspas (byte fora de ASCII imprimível, espaço final,
  `: `, `:` no fim, ` #` ou caractere de controle);
- caminho duplicado;
- symlink, submódulo, diretório ou arquivo especial;
- caminho dentro da própria pasta da feature ou de `docs/entregas/<slug>/`;
- arquivo não rastreado, staged, modificado ou removido;
- arquivo que não exista como blob regular no commit declarado.

## 6. Prova histórica

### 6.1 Nascimento do planejamento SprintX

A âncora do início formal é o primeiro commit da história de `HEAD` que adicionou:

```text
docs/sprintx/features/<slug>/00-PLANEJAMENTO.md
```

O verificador usa a história completa, sem seguir renomeações, e exige exatamente um commit de adição alcançável de `HEAD`. Ausência, múltiplas adições, repositório raso ou objeto ausente tornam a prova inconclusiva e falham fechados.

Na MP2.7b essa âncora é:

```text
934878cb7b5c7ad2e37f55b4342c1c88b2535268
```

### 6.2 Prova por predecessor

Para cada item, o verificador exige simultaneamente:

1. `commit_sha` resolve para um único commit alcançável de `HEAD`;
2. `commit_sha` é ancestral estrito do commit que adicionou `00-PLANEJAMENTO.md`;
3. `<commit_sha>:<caminho>` é blob regular e seu OID é `blob_oid`;
4. `HEAD:<caminho>` é blob regular e seu OID continua igual a `blob_oid`;
5. o caminho aparece literalmente uma vez no manifesto;
6. o manifesto lido é o blob de `HEAD`, nunca a cópia do disco.

Essa combinação prova precedência e imutabilidade. Alterar o documento e o manifesto no mesmo commit não funciona: o novo commit não é ancestral estrito do nascimento da SprintX, e o blob deixa de coincidir com o predecessor registrado.

### 6.3 Classificação das falhas

- Manifesto ausente: comportamento atual da V9, sem aviso novo.
- Manifesto válido, mas caminho não declarado: `v9` e `fora_do_plano`.
- Caminho declarado cujo blob atual diverge: `v9` e `fora_do_plano`.
- Manifesto malformado, história incompleta, commit ausente, âncora ambígua ou objeto ilegível: `v9_sem_prova`.
- Entrada válida que não aparece no diff: permitida, mas não altera o conjunto avaliado.

## 7. Emissão pela SprintX

### 7.1 Script proprietário

A SprintX cria:

```text
.claude/skills/sprintx/scripts/predecessores.sh
```

Interfaces públicas:

```bash
predecessores.sh --registrar <slug> --origem superpowers --papel <especificacao|plano> --caminho <path>
predecessores.sh --validar <slug>
predecessores.sh --listar <slug>
```

`--registrar` calcula `commit_sha` e `blob_oid`; nunca aceita esses valores informados pelo agente. A gravação é atômica, preserva entradas anteriores, ordena pelo caminho e é idempotente quando a prova não mudou. O registrador recusa o diretório da feature ou qualquer pai simbólico antes de criar o temporário, impedindo que a escrita escape do repositório. Antes de ler o manifesto, adquire uma trava exclusiva por worktree e slug; contenda falha fechada e a trava só é removida por quem a adquiriu. O script não faz commit.

`--validar` é somente leitura e aplica todas as regras de schema, caminho, história e blob que pertencem à SprintX.

`--listar` imprime uma linha tabulada por predecessor, destinada à integração e aos testes.

### 7.2 Fluxo F1

Durante a F1, depois de decidir que um documento Superpowers será insumo da base:

1. o agente lê o documento;
2. chama `predecessores.sh --registrar` com caminho, origem e papel exatos;
3. cita o documento no arquivo da base que usa a evidência;
4. roda `predecessores.sh --validar` antes de encerrar a F1.

Não há busca automática por toda a pasta `docs/superpowers`. Só entra o documento efetivamente consumido e explicitamente registrado. O `00-PREDECESSORES.md` segue com os demais artefatos da feature no checkpoint da F2.

### 7.3 Catálogo e schema

A SprintX passa a reconhecer `00-PREDECESSORES.md` como artefato de método, documenta o kind em `references/00-schema.md`, inclui o arquivo na estrutura em disco e exige a validação na saída da F1 quando ele existir.

O catálogo da MergeX também reconhece o caminho como método da SprintX. Isso autoriza persistir o manifesto; não autoriza os predecessores. A autorização de cada predecessor continua sendo a prova específica da V9.

## 8. Consumo pela MergeX

### 8.1 Verificador isolado

A MergeX cria um verificador somente leitura:

```text
.claude/skills/mergex/scripts/predecessores-sprintx.sh
```

Interface:

```bash
predecessores-sprintx.sh --verificar --rev <sha> --trabalho <slug>
```

Saída quando o manifesto não existe:

```text
resultado=ausente
```

Saída quando todas as entradas são válidas:

```text
resultado=ok
predecessor<TAB><caminho><TAB><commit_sha><TAB><blob_oid>
```

Saída quando o manifesto é estruturalmente válido, mas o blob atual de uma ou mais entradas
diverge do blob predecessor:

```text
resultado=v9
predecessor<TAB><caminho-válido><TAB><commit_sha><TAB><blob_oid>
fora_do_plano<TAB><caminho-divergente><TAB>blob_divergente
```

As linhas `predecessor` das outras entradas continuam utilizáveis; cada caminho divergente
permanece fora do plano. Essa saída não transforma divergência conhecida em ausência de prova.

Saída inconclusiva:

```text
resultado=v9_sem_prova
motivo<TAB><texto>
```

Os códigos são `0` para `ausente` ou `ok`, `1` para `v9`, `3` para `v9_sem_prova` e `64` para
uso inválido. Se qualquer entrada tiver schema, caminho, commit, ancestralidade ou objeto
inconclusivo, o conjunto inteiro sai como `v9_sem_prova`; não há aceitação parcial nesse caso.

O consumidor nunca infere o resultado apenas pelo código de saída. Ele exige exatamente uma
linha `resultado=`, valida o enum, a forma das linhas seguintes e a combinação exata entre
resultado e código: `ausente|ok` com `0`, `v9` com `1`, `v9_sem_prova` com `3` e uso com `64`.
`ok` exige ao menos uma linha `predecessor`; `v9` exige ao menos uma linha `fora_do_plano`;
`v9_sem_prova` exige ao menos uma linha `motivo`. Saída vazia, truncada, duplicada, com linha
desconhecida, código divergente, código fora do contrato ou término por sinal é convertida pelo
`portao-v9.sh` em `v9_sem_prova` com motivo `saida_inconclusiva`. Nenhum desses casos autoriza
caminho parcial.

O script não lê a working tree, não grava arquivo, recusa repositório raso e usa ambiente Git fixo como os demais verificadores da reconciliação.

### 8.2 Integração na V9

`portao-v9.sh` acrescenta as linhas `predecessor` devolvidas com `resultado=ok` ou
`resultado=v9` à lista aceita, mantém cada linha `fora_do_plano` no resultado e propaga
`resultado=v9_sem_prova` sem mudar as fontes existentes:

1. união de `arquivos.cria` e `arquivos.altera` das tasks;
2. artefatos exatos de método;
3. predecessores SprintX com prova válida;
4. caminhos cobertos por reconciliação de base válida.

O manifesto é materializado de `HEAD` junto com os demais artefatos SprintX. A V9 nunca lê uma versão suja do disco.

Um manifesto inválido produz `v9_sem_prova`, porque não é seguro ignorar uma declaração quebrada e continuar como se ela não existisse.

## 9. Recuperação após E8 bloqueado

### 9.1 Condição de entrada

A recuperação só existe quando todas as condições forem verdadeiras no `ENTREGA.md` commitado:

- `estado: bloqueado`;
- `portao: bloqueado`;
- `falhas_portao: [v9]` exatamente;
- `causa: arquivo_fora_do_plano`;
- `push_feito: false`;
- `pr_url: null` e `pr_estado: null`;
- árvore e stage limpos antes de iniciar;
- nenhuma reconciliação ou mudança de base pendente.

Qualquer outra combinação permanece terminal e exige outro fluxo.

### 9.2 Dois checkpoints, sem task

A recuperação não cria task e não altera task concluída.

**Checkpoint 1 — manifesto:**

1. a pessoa ou agente chama `predecessores.sh --registrar` para os caminhos apontados pela V9;
2. a SprintX valida o manifesto;
3. a MergeX persiste somente `00-PREDECESSORES.md` num commit de método `predecessores`, sem `Task:` e sem consumir `seq`;
4. se a persistência falhar, a entrega continua bloqueada.

**Checkpoint 2 — reabertura:**

1. a MergeX roda novamente a V9 no novo `HEAD`;
2. exige `resultado=ok` e confere que os desvios anteriores são exatamente os caminhos cobertos pelo manifesto;
3. grava `estado: aberto`, `portao: null`, `portao_sha: null`, `falhas_portao: []`, `causa: null` e `desvios: []`;
4. preserva base, reconciliações, `commits`, `arquivos_alterados`, datas históricas e todo o restante;
5. persiste um commit de método `retomar-v9-predecessores`, sem `Task:` e sem consumir `seq`.

Depois da reabertura, o E2 inteiro roda novamente sobre o novo `HEAD`. Não basta repetir apenas a V9. E3–E7 continuam proibidos até o novo E2 emitir `PRONTO`.

### 9.3 Interface da MergeX

A MergeX cria:

```bash
retomar-v9-predecessores.sh --verificar --entrega <ENTREGA.md> --origem sprintx --trabalho <slug>
retomar-v9-predecessores.sh --aplicar --entrega <ENTREGA.md> --origem sprintx --trabalho <slug>
```

`--verificar` é somente leitura. `--aplicar` usa a trava da MergeX, exige stage vazio, repete todas as provas, grava de forma atômica e chama o checkpoint oficial. Não existe `--force`.

## 10. Recuperação concreta da MP2.7b

Depois que SprintX e MergeX com este contrato estiverem instaladas e certificadas no produto:

1. continuar na branch `feature/mp2-7b-consolidacao-main`, cujo E8 bloqueado está em `eb46a7e`;
2. registrar a especificação com commit `85dff72f14e477bcd074050ac3b56a11911cfd60` e blob `7d3fe6903c1d43f685b2def2904b02e7e226213c`;
3. registrar o plano com commit `4afd01a61c1ca51d14f58a59979606ae3047bae1` e blob `aba5c1a22d90c22c022cc1e1549fd3c45e9fa993`;
4. validar que os dois commits antecedem `934878cb7b5c7ad2e37f55b4342c1c88b2535268`, o nascimento do planejamento SprintX;
5. criar o checkpoint `predecessores`;
6. executar `retomar-v9-predecessores.sh --verificar` e depois `--aplicar`;
7. executar novamente E2 completo;
8. somente com `PRONTO`, continuar E3–E8 e publicar conforme o fluxo normal.

Os commits E1 das seis tasks e o E8 bloqueado permanecem no histórico. Nenhum amend, rebase, reset ou force push é necessário.

## 11. Compatibilidade e implantação

- MergeX nova sem manifesto mantém exatamente o comportamento anterior.
- SprintX nova com MergeX antiga cria um artefato de método inofensivo, mas os predecessores ainda não passam na V9; portanto a instalação coordenada é necessária para obter o benefício.
- A implantação recomendada é MergeX primeiro, SprintX depois, seguida de certificação conjunta pelo ExpxDev.
- O ExpxDev muda somente pins e candidatos de certificação nesta rodada; o protocolo pertence às duas skills.
- Nenhum cache ou instalação global é alterado durante a implementação das branches de origem.

## 12. Testes da SprintX

A suíte deve provar pelo menos:

1. registro de spec e plano limpos e rastreados;
2. idempotência da mesma entrada;
3. ordenação canônica e rejeição de duplicata;
4. rejeição de caminho absoluto, fora de `docs/superpowers/`, inseguro para YAML, `..`, glob e barra invertida;
5. rejeição de arquivo sujo, staged, não rastreado, removido, symlink e gitlink;
6. cálculo automático de commit e blob;
7. rejeição de origem e papel fora do enum;
8. schema e prosa coerentes;
9. manifesto incluído no checkpoint F2;
10. recuperação capaz de criar manifesto depois do E8 sem tocar tasks;
11. nenhum commit ou push feito pelo registrador;
12. espelhos de Claude Code e OpenCode com o mesmo contrato.
13. manifesto como symlink, inclusive quebrado, falha antes do checkpoint F2;
14. repositório SHA-256 preserva OIDs completos de 64 caracteres;
15. grupo de teste desconhecido devolve erro de uso;
16. trava concorrente preserva o manifesto e permite repetição depois de liberada;
17. diretório da feature ou pai simbólico falha antes de qualquer escrita no alvo externo.

## 13. Testes da MergeX

A suíte deve provar pelo menos:

1. predecessor declarado, anterior à SprintX e byte a byte igual passa;
2. caminho não declarado continua em `fora_do_plano`;
3. isenção por prefixo não existe;
4. blob atual divergente continua em `fora_do_plano`;
5. commit posterior ou igual ao nascimento da SprintX é inconclusivo;
6. manifesto lido do disco, em vez de `HEAD`, é morto por teste;
7. manifesto malformado, raso, commit ausente e âncora ambígua geram `v9_sem_prova`;
8. symlink e gitlink são recusados;
9. múltiplos predecessores válidos passam independentemente;
10. uma entrada inválida falha o conjunto inteiro;
11. estado bloqueado por qualquer falha além de V9 não reabre;
12. V9 com outro desvio não reabre;
13. recuperação preserva tasks, `ENTREGA.commits`, `seq`, base e reconciliações;
14. checkpoints de recuperação não recebem `Task:` nem entram em `commits`;
15. o E2 inteiro precisa rodar depois da reabertura;
16. repetição da recuperação é idempotente ou recusada sem nova gravação;
17. nenhum caminho remoto, push ou PR é tocado pela recuperação.

## 14. Mutantes obrigatórios

Os testes devem matar cópias que:

1. aceitam todo `docs/superpowers/**`;
2. usam prefixo em vez de caminho exato;
3. confiam no manifesto do disco;
4. não comparam o blob de `HEAD`;
5. aceitam predecessor criado depois da SprintX;
6. aceitam commit igual ao checkpoint de nascimento;
7. ignoram uma entrada inválida entre várias;
8. transformam manifesto inválido em ausência de manifesto;
9. reabrem entrega com falhas `[v9, v10]`;
10. reabrem sem limpar `portao_sha`;
11. reabrem alterando `ENTREGA.commits` ou `seq`;
12. criam uma task artificial para a recuperação;
13. aceitam arquivo sujo no registrador;
14. calculam o SHA a partir de input humano;
15. executam somente V9 depois da reabertura e pulam V1–V8/V10/V11.

## 15. Segurança e falha fechada

- Todos os leitores usam a árvore de um SHA, nunca o arquivo de trabalho, para decisões do portão.
- Toda escrita usa temporário no mesmo diretório e troca atômica.
- Stage preexistente, árvore suja fora do artefato esperado, trava ocupada ou segredo interrompem a persistência.
- Repositório raso e objeto ausente são ausência de prova, nunca autorização.
- Nenhum script oferece `--force`, `--yes` ou modo permissivo.
- O manifesto não contém caminho absoluto, credencial, dado pessoal nem conteúdo dos predecessores.

## 16. Observabilidade

Esta rodada não acrescenta nomes ao contrato `expx-eventos`, cujo vocabulário pertence ao
ExpxDev. SprintX e MergeX não gravam eventos inventados para registro, validação ou retomada.

A observabilidade imediata vem das saídas estruturadas dos scripts (`resultado`, `motivo`,
`predecessor`, `fora_do_plano`) e dos artefatos duráveis. Os dois checkpoints de método da
recuperação usam o evento existente `commit_criado` pelo mesmo caminho que já registra commits
de método; o detalhe identifica `Metodo: predecessores` ou `Metodo: retomar-v9-predecessores`.

Falha anterior ao commit permanece na saída do comando e não produz linha de rastro falsa. Se o
produto precisar consultar registro/validação/retomada como eventos próprios, o ExpxDev deverá
ampliar o enum e o contrato em uma rodada coordenada futura.

## 17. Documentação

As mudanças atualizam:

- schema e estrutura em disco da SprintX;
- F1 e critério de saída da F1;
- catálogo de método das duas skills;
- contrato da V9 na MergeX;
- contrato de E2/E8 e causa do portão;
- README/SKILL das duas skills;
- decisões append-only.

## 18. Decisões

- **DS-176 — Manifesto exato de predecessores.** A SprintX registra apenas documentos efetivamente consumidos, por caminho literal, commit e blob.
- **DS-177 — Proveniência por ancestralidade e conteúdo.** Um predecessor só vale quando antecede o nascimento do planejamento e o blob atual permanece idêntico.
- **DS-178 — Recuperação terminal estreita.** Uma entrega bloqueada exclusivamente pela V9 de predecessores pode reabrir sem alterar tasks, por dois checkpoints de método e nova execução integral do E2.
- **DS-179 — Superpowers permanece desacoplado.** Nenhuma mudança é exigida dele; a SprintX assume a declaração porque é quem sabe quais documentos consumiu.
- **DS-180 — Rastro sem vocabulário inventado.** O protocolo usa saída estruturada e o evento existente `commit_criado`; novos nomes de evento só entram por mudança coordenada do ExpxDev.

## 19. Critérios de aceite globais

O desenho está implementado quando:

1. SprintX emite e valida o manifesto com prova Git;
2. MergeX aceita somente predecessores exatos e imutáveis;
3. as suítes das duas skills passam com os mutantes obrigatórios mortos;
4. ausência de manifesto preserva o comportamento existente;
5. uma fixture equivalente à MP2.7b passa pela V9;
6. a MP2.7b real pode sair do E8 bloqueado, rerodar E2 e continuar sem tocar nas seis tasks concluídas;
7. as branches de origem têm PRs separados e revisáveis;
8. depois dos merges, o ExpxDev certifica os novos pins antes de qualquer instalação no produto;
9. nenhum push, PR ou instalação global acontece antes dos gates de cada repositório.

## 20. Riscos residuais

- Uma história Git reescrita externamente pode tornar a prova indisponível; a resposta correta é falhar fechado.
- Repositórios sem histórico completo precisam de `fetch --unshallow` antes da validação.
- O protocolo inicial reconhece apenas `superpowers`; novas origens exigem decisão de schema.
- A recuperação adiciona dois commits de método ao produto, preservando a evidência do bloqueio anterior.
- A instalação coordenada envolve SprintX, MergeX e ExpxDev; versões parciais não devem ser anunciadas como solução completa.
