# Predecessores verificáveis entre SprintX e MergeX — Plano de Implementação

> **Para quem executar:** use `superpowers:executing-plans` e siga as tasks em ordem. Use TDD em cada task, faça um commit por task e não publique nenhum repositório antes de todos os gates daquele repositório passarem.

**Objetivo:** permitir que a SprintX declare documentos Superpowers realmente consumidos antes do planejamento e que a MergeX os aceite na V9 somente com prova Git exata, incluindo uma retomada estreita da MP2.7b já encerrada em E8 bloqueado.

**Arquitetura:** a SprintX é dona do `00-PREDECESSORES.md` e de seu registrador. A MergeX lê o manifesto exclusivamente da árvore de um SHA, valida caminho, ancestralidade e blob, acrescenta somente entradas provadas à V9 e oferece dois checkpoints de método para recuperar um E8 bloqueado exclusivamente por esses predecessores. Superpowers não muda; ExpxDev só entra depois, para pin e certificação dos dois PRs já integrados.

**Tecnologia:** Bash 3.2 compatível, Git real em fixtures temporárias, frontmatter YAML escalar/lista, testes shell sem rede e sem dependência nova obrigatória.

**Especificação:** `docs/superpowers/specs/2026-10-13-predecessores-verificaveis-sprintx-mergex-design.md`

---

## Topologia de execução

1. Tasks 1–4 rodam na branch SprintX `fix/sprintx-predecessores-verificaveis`.
2. Depois do gate SprintX, criar uma worktree MergeX isolada a partir de `origin/p0.2/mergex-historico-yaml-escalar` no commit que contém o PR #6, em branch `fix/mergex-predecessores-sprintx`.
3. Tasks 5–10 rodam nessa worktree MergeX.
4. Cada repositório produz seu próprio PR. Não misturar arquivos das duas skills num mesmo commit ou branch.
5. Task 11 é o handoff: depois dos dois merges, ExpxDev atualiza pins e certifica a combinação; só então a MP2.7b usa a recuperação.

## Invariantes gerais

- Nunca aceitar `docs/superpowers/**` por prefixo.
- Nunca ler manifesto, predecessor ou `ENTREGA.md` sujo para decidir a V9.
- Nunca alterar task concluída, `ENTREGA.commits`, `seq`, base ou reconciliação na recuperação.
- Nenhum script desta rodada faz push, abre PR ou usa `--force`.
- Nenhum nome novo entra em `expx-eventos`; a observabilidade usa saída estruturada, artefatos e o evento existente `commit_criado` nos checkpoints.
- Repositório raso, objeto ausente, saída truncada, código inesperado ou parser inconclusivo falham fechados.

---

### Task 1: Criar a bancada Git dos predecessores na SprintX

**Arquivos:**

- Criar: `scripts/ci/test-predecessores.sh`
- Alterar: `.claude/hooks/testes/bancada.sh`

**Passo 1 — escrever a fixture e os primeiros testes vermelhos**

Criar uma bancada que monte um repositório Git real com esta história linear:

```text
B0 → S (spec) → P (plano) → F1 (adiciona 00-PLANEJAMENTO.md) → HEAD
```

A fixture deve exportar `FX_SPEC_COMMIT`, `FX_PLAN_COMMIT`, `FX_F1_COMMIT`, os dois caminhos e os dois blobs. Não reutilizar o checkout da própria SprintX como produto sob teste.

Começar com os casos:

```bash
caso_rc "registrador ainda ausente" 127 \
  bash "$S/predecessores.sh" --registrar ft-pre --origem superpowers \
    --papel especificacao --caminho "$SPEC"

caso_rc "validador ainda ausente" 127 \
  bash "$S/predecessores.sh" --validar ft-pre
```

**Passo 2 — rodar e confirmar o vermelho causal**

Executar:

```bash
bash scripts/ci/test-predecessores.sh registro
```

Esperado: falha porque `.claude/skills/sprintx/scripts/predecessores.sh` não existe, não por erro da fixture.

**Passo 3 — expandir a matriz de testes antes da implementação**

Adicionar grupos nomeados:

- `registro`: spec e plano, ordem canônica, idempotência e prosa coerente;
- `caminhos`: absoluto, `./`, `.`, `..`, segmento vazio, barra invertida e glob;
- `estado-git`: untracked, staged, modificado, removido, symlink, gitlink e arquivo especial;
- `historia`: commit posterior, commit igual a F1, duas adições do planejamento, raso e objeto ausente;
- `schema`: lista vazia, item duplicado, origem/papel fora do enum, chave repetida e scalar malformado;
- `checkpoint`: manifesto inválido impede `planejamento.sh avanca <slug> f2`; válido entra no checkpoint F2;
- `todos`: executa todos os grupos.

**Passo 4 — integrar a bancada ampla sem esconder a suíte dedicada**

No fim de `.claude/hooks/testes/bancada.sh`, chamar a nova suíte e converter seu código em uma asserção da bancada principal. A saída da suíte dedicada continua visível em caso de falha.

**Passo 5 — commit**

```bash
git add scripts/ci/test-predecessores.sh .claude/hooks/testes/bancada.sh
git commit -m "test(sprintx): cobre manifesto de predecessores"
```

---

### Task 2: Implementar o manifesto e o registrador SprintX

**Arquivos:**

- Criar: `.claude/skills/sprintx/assets/TEMPLATE-PREDECESSORES.md`
- Criar: `.claude/skills/sprintx/scripts/predecessores.sh`
- Alterar: `scripts/ci/test-predecessores.sh`

**Passo 1 — implementar apenas o caminho feliz**

Interfaces públicas exatas:

```bash
predecessores.sh --registrar <slug> --origem superpowers \
  --papel <especificacao|plano> --caminho <path>
predecessores.sh --validar <slug>
predecessores.sh --listar <slug>
```

O script deve localizar a raiz com Git, validar o slug e usar o caminho canônico:

```text
docs/sprintx/features/<slug>/00-PREDECESSORES.md
```

`--registrar` calcula internamente:

```bash
commit_sha=$(git log -1 --format=%H -- "$caminho")
blob_oid=$(git rev-parse "$commit_sha:$caminho")
```

Não aceitar SHA ou blob na linha de comando.

**Passo 2 — implementar a prova histórica**

Encontrar exatamente um commit de adição do planejamento:

```bash
git log --format=%H --diff-filter=A -- \
  "docs/sprintx/features/$slug/00-PLANEJAMENTO.md"
```

Exigir `git merge-base --is-ancestor "$commit_sha" "$nascimento"` e rejeitar igualdade. Conferir que os modos em `commit_sha` e `HEAD` são `100644` ou `100755`, que ambos são blobs e que o OID atual permanece igual ao declarado.

**Passo 3 — implementar o parser e a escrita atômica**

O parser aceita somente o schema da spec, recusa chaves duplicadas e não usa `eval`. A lista precisa ter ao menos um item. A escrita usa temporário no mesmo diretório, `chmod 644` e `mv` atômico; em falha, remove o temporário e preserva o manifesto anterior byte a byte.

`--registrar` preserva entradas existentes, ordena pelo caminho e é no-op quando a prova não mudou. `--listar` imprime:

```text
predecessor<TAB><caminho><TAB><commit_sha><TAB><blob_oid>
```

**Passo 4 — fechar todas as negativas da Task 1**

Rodar em ciclos curtos:

```bash
bash scripts/ci/test-predecessores.sh registro caminhos estado-git
bash scripts/ci/test-predecessores.sh historia schema
```

Esperado: todos verdes, sem modificar o repositório fixture após cada caso reprovado.

**Passo 5 — qualidade e portabilidade**

```bash
bash -n .claude/skills/sprintx/scripts/predecessores.sh
shellcheck .claude/skills/sprintx/scripts/predecessores.sh \
  scripts/ci/test-predecessores.sh
```

Se `shellcheck` não estiver instalado, registrar `SKIP externo` e manter `bash -n` obrigatório.

**Passo 6 — commit**

```bash
git add .claude/skills/sprintx/assets/TEMPLATE-PREDECESSORES.md \
  .claude/skills/sprintx/scripts/predecessores.sh \
  scripts/ci/test-predecessores.sh
git commit -m "feat(sprintx): registra predecessores verificaveis"
```

---

### Task 3: Integrar o manifesto à F1, ao schema e ao checkpoint F2

**Arquivos:**

- Alterar: `.claude/skills/sprintx/references/00-schema.md`
- Alterar: `.claude/skills/sprintx/references/01-ingestao.md`
- Alterar: `.claude/skills/sprintx/references/08-rastro.md`
- Alterar: `.claude/skills/sprintx/scripts/planejamento.sh`
- Alterar: `.claude/skills/sprintx/SKILL.md`
- Alterar: `.claude/commands/sprintx-base.md`
- Alterar: `.opencode/command/sprintx-base.md`
- Alterar: `scripts/ci/test-predecessores.sh`
- Alterar: `.claude/hooks/testes/bancada.sh`

**Passo 1 — escrever os testes de contrato vermelhos**

Adicionar asserções que exijam:

1. `kind: predecessores` no schema;
2. `00-PREDECESSORES.md` na estrutura fixa da skill;
3. a F1 chamando `--registrar` somente depois de ler o documento consumido;
4. `--validar` antes do encerramento da F1;
5. os dois entrypoints (`.claude` e `.opencode`) apontando para o mesmo reference;
6. `planejamento.sh avanca <slug> f2` recusando manifesto inválido antes de preparar o índice;
7. nenhuma ocorrência dos nomes de evento rejeitados pela spec.

Executar e observar o vermelho:

```bash
bash scripts/ci/test-predecessores.sh contrato checkpoint
```

**Passo 2 — documentar o schema e o fluxo F1**

Acrescentar o schema completo em `00-schema.md`, incluindo enums, lista não vazia, caminho literal e relação entre frontmatter e prosa. Em `01-ingestao.md`, registrar predecessor apenas quando o documento foi realmente lido e citado por um arquivo da base; não varrer diretórios automaticamente.

**Passo 3 — tornar o F2 a barreira durável**

Antes de `avanca f2` gravar estado ou preparar o índice, se o manifesto existir, chamar:

```bash
bash "$SK/scripts/predecessores.sh" --validar "$SLUG"
```

Falha: código de contrato, nenhuma mudança em `00-PLANEJAMENTO.md`, stage ou rastro. Sucesso: o checkpoint normal já inclui toda a pasta da feature, portanto nenhuma lógica especial de `git add` é criada.

**Passo 4 — manter o contrato de eventos**

Em `08-rastro.md`, documentar que o protocolo não cria evento novo. Registro/validação saem no stdout; commits de método continuam usando `commit_criado` pela MergeX.

**Passo 5 — rodar testes**

```bash
bash scripts/ci/test-predecessores.sh contrato checkpoint
bash .claude/hooks/testes/bancada.sh
```

**Passo 6 — commit**

```bash
git add .claude/skills/sprintx/references/00-schema.md \
  .claude/skills/sprintx/references/01-ingestao.md \
  .claude/skills/sprintx/references/08-rastro.md \
  .claude/skills/sprintx/scripts/planejamento.sh \
  .claude/skills/sprintx/SKILL.md \
  .claude/commands/sprintx-base.md \
  .opencode/command/sprintx-base.md \
  scripts/ci/test-predecessores.sh .claude/hooks/testes/bancada.sh
git commit -m "feat(sprintx): integra predecessores a ingestao"
```

---

### Task 4: Fechar decisões, mutantes e gate da SprintX

**Arquivos:**

- Alterar: `.claude/skills/sprintx/DECISOES-DA-SKILL.md`
- Criar: `scripts/ci/mutacao-predecessores.sh`
- Alterar: `scripts/ci/test-predecessores.sh`
- Alterar: `README.md`

**Passo 1 — publicar decisões append-only**

Acrescentar DS-176 a DS-180 exatamente como na spec: manifesto exato, prova por ancestralidade+blob, retomada terminal estreita, Superpowers desacoplado e ausência de evento inventado.

**Passo 2 — escrever a matriz de mutantes**

O script precisa matar ao menos:

- `PREFIXO`: aceita todo `docs/superpowers/**`;
- `GLOB`: compara por prefixo;
- `DISCO`: lê manifesto da working tree;
- `HEADBLOB`: deixa de comparar o blob atual;
- `POSTERIOR`: aceita commit posterior ao nascimento;
- `IGUAL`: aceita commit igual ao nascimento;
- `PARCIAL`: ignora item inválido entre válidos;
- `AUSENCIA`: trata manifesto inválido como ausente;
- `SUJO`: registra arquivo sujo;
- `SHAINPUT`: aceita SHA informado pelo chamador;
- `EVENTO`: introduz nome fora de `expx-eventos`.

**Passo 3 — gate SprintX completo**

```bash
bash scripts/ci/test-predecessores.sh todos
bash scripts/ci/mutacao-predecessores.sh
bash .claude/hooks/testes/bancada.sh
git diff --check
```

Esperado: todos os mutantes mortos, bancada inteira verde e árvore limpa após o commit.

**Passo 4 — commit**

```bash
git add .claude/skills/sprintx/DECISOES-DA-SKILL.md \
  scripts/ci/mutacao-predecessores.sh scripts/ci/test-predecessores.sh README.md
git commit -m "test(sprintx): certifica predecessores verificaveis"
```

**Passo 5 — revisão antes do PR SprintX**

Rodar `superpowers:requesting-code-review` sobre a spec, o plano e os commits 1–4. Corrigir achados no escopo antes de push. Só então abrir o PR SprintX; não atualizar ExpxDev ainda.

---

### Task 5: Criar a fixture e o contrato do verificador MergeX

**Pré-condição:** executar na worktree MergeX isolada, nunca no checkout com alterações locais do usuário.

**Arquivos:**

- Criar: `scripts/ci/lib/fixture-predecessores.sh`
- Criar: `scripts/ci/test-r3-predecessores-sprintx.sh`

**Passo 1 — montar uma história equivalente à MP2.7b**

A fixture cria base, spec, plano, nascimento SprintX, seis commits E1, `pre-e2`, E2 bloqueado e E8 bloqueado. O `ENTREGA.md` final precisa ter:

```yaml
estado: bloqueado
portao: bloqueado
falhas_portao: [v9]
causa: arquivo_fora_do_plano
push_feito: false
pr_url: null
pr_estado: null
desvios:
  - docs/superpowers/specs/exemplo-design.md
  - docs/superpowers/plans/exemplo.md
```

**Passo 2 — escrever os grupos vermelhos**

Grupos:

- `verificador`: ausência, sucesso, divergência e sem prova;
- `protocolo`: correspondência exata de `resultado` e código;
- `v9`: integração com as fontes já existentes;
- `checkpoint`: enums e catálogos dos dois commits de método;
- `retomada`: estados aceitos/recusados;
- `mp27b`: caminho feliz completo;
- `todos`.

Começar exigindo o script ausente:

```bash
rc_igual "verificador ainda ausente" 127 \
  bash "$S/predecessores-sprintx.sh" --verificar --rev HEAD --trabalho ft-pre
```

**Passo 3 — observar o vermelho causal**

```bash
bash scripts/ci/test-r3-predecessores-sprintx.sh verificador protocolo
```

**Passo 4 — commit**

```bash
git add scripts/ci/lib/fixture-predecessores.sh \
  scripts/ci/test-r3-predecessores-sprintx.sh
git commit -m "test(mergex): reproduz predecessores fora da v9"
```

---

### Task 6: Implementar o verificador por SHA e integrar a V9

**Arquivos:**

- Criar: `.claude/skills/mergex/scripts/predecessores-sprintx.sh`
- Alterar: `.claude/skills/mergex/scripts/portao-v9.sh`
- Alterar: `.claude/skills/mergex/scripts/catalogo-de-metodo.sh`
- Alterar: `scripts/ci/test-r3-predecessores-sprintx.sh`

**Passo 1 — implementar leitura exclusiva da árvore**

Interface:

```bash
predecessores-sprintx.sh --verificar --rev <sha> --trabalho <slug>
```

Materializar manifesto, planejamento e predecessores com `git cat-file`/`git show` para temporários fora do repositório. Nunca consultar o conteúdo do disco. Recusar raso antes de procurar a âncora.

**Passo 2 — implementar a gramática de saída fechada**

Resultados e códigos:

```text
resultado=ausente                                      # rc 0
resultado=ok + >=1 predecessor                         # rc 0
resultado=v9 + >=1 fora_do_plano                       # rc 1
resultado=v9_sem_prova + >=1 motivo                    # rc 3
uso                                                     # rc 64
```

Se qualquer entrada for inconclusiva, não imprimir predecessores parciais. `resultado=v9` é reservado a blob atual conhecido e divergente.

**Passo 3 — integrar ao `portao-v9.sh` sem inferir pelo rc**

O consumidor valida uma única linha `resultado=`, o formato das linhas seguintes e a combinação resultado/código. Saída vazia, truncada, duplicada, sinal, linha desconhecida ou combinação divergente vira:

```text
resultado=v9_sem_prova
motivo<TAB>predecessores-sprintx: saida_inconclusiva
```

Adicionar somente linhas `predecessor` de `ok` ou `v9` ao conjunto aceito. Manter `fora_do_plano` de `v9`. Ausência preserva o comportamento atual.

**Passo 4 — catálogo do manifesto**

Reconhecer exatamente `docs/sprintx/features/<slug>/00-PREDECESSORES.md` como método. Não reconhecer os caminhos declarados no manifesto pelo catálogo; eles só entram via verificador.

**Passo 5 — testes**

```bash
bash scripts/ci/test-r3-predecessores-sprintx.sh verificador protocolo v9
bash scripts/ci/test-r1-reconciliacao-base.sh v9 invariantes
```

**Passo 6 — commit**

```bash
git add .claude/skills/mergex/scripts/predecessores-sprintx.sh \
  .claude/skills/mergex/scripts/portao-v9.sh \
  .claude/skills/mergex/scripts/catalogo-de-metodo.sh \
  scripts/ci/test-r3-predecessores-sprintx.sh
git commit -m "feat(mergex): valida predecessores sprintx na v9"
```

---

### Task 7: Acrescentar os checkpoints de método da recuperação

**Arquivos:**

- Alterar: `.claude/skills/mergex/scripts/contrato-de-commit.sh`
- Alterar: `.claude/skills/mergex/scripts/catalogo-de-metodo.sh`
- Alterar: `.claude/skills/mergex/scripts/persistir-metodo.sh`
- Alterar: `.claude/skills/mergex/references/01-commits.md`
- Alterar: `scripts/ci/test-r3-predecessores-sprintx.sh`

**Passo 1 — testes vermelhos dos enums e escopos**

Exigir:

- `predecessores`: somente o manifesto;
- `retomar-v9-predecessores`: somente `ENTREGA.md`;
- ambos com `Trabalho:` + `Metodo:`, sem `Task:`;
- nenhum entra em `ENTREGA.commits` nem consome `seq`;
- stage preexistente ou path extra recusa sem limpar nada.

**Passo 2 — ampliar enums em um único commit**

Novo enum completo:

```text
pre-e2 | reconciliacao-base | predecessores |
retomar-v9-predecessores | pre-e6 | e8
```

Atualizar uso, validação, catálogo cumulativo e documentação na mesma task para evitar um checkpoint reconhecido por apenas um dos três scripts.

**Passo 3 — testes de regressão**

```bash
bash scripts/ci/test-r3-predecessores-sprintx.sh checkpoint
bash scripts/ci/test-r1-reconciliacao-base.sh contrato invariantes
bash scripts/ci/test-sequencia-commits.sh
```

**Passo 4 — commit**

```bash
git add .claude/skills/mergex/scripts/contrato-de-commit.sh \
  .claude/skills/mergex/scripts/catalogo-de-metodo.sh \
  .claude/skills/mergex/scripts/persistir-metodo.sh \
  .claude/skills/mergex/references/01-commits.md \
  scripts/ci/test-r3-predecessores-sprintx.sh
git commit -m "feat(mergex): adiciona checkpoints de predecessores"
```

---

### Task 8: Implementar a retomada terminal estreita

**Arquivos:**

- Criar: `.claude/skills/mergex/scripts/retomar-v9-predecessores.sh`
- Alterar: `.claude/skills/mergex/references/00-schema.md`
- Alterar: `.claude/skills/mergex/references/02-prontidao.md`
- Alterar: `.claude/skills/mergex/references/08-registro.md`
- Criar: `.claude/skills/mergex/references/13-predecessores-sprintx.md`
- Criar: `.claude/commands/mergex-retomar-v9.md`
- Criar: `.opencode/commands/mergex-retomar-v9.md`
- Alterar: `scripts/ci/test-r3-predecessores-sprintx.sh`

**Passo 1 — escrever todas as recusas antes do caminho feliz**

Testar recusa para:

- estado ou portão diferente de `bloqueado`;
- falhas vazias ou diferentes de `[v9]`;
- causa diferente de `arquivo_fora_do_plano`;
- `push_feito: true`, PR presente ou estado remoto;
- árvore/stage sujos;
- reconciliação pendente;
- `ENTREGA.md` do disco diferente de `HEAD`;
- `desvios` com path não coberto pelo manifesto;
- V9 ainda em `v9` ou `v9_sem_prova`;
- repetição depois de reaberto.

**Passo 2 — implementar `--verificar` somente leitura**

Ler o `ENTREGA.md` commitado, validar a combinação exata e chamar `portao-v9.sh` no `HEAD`. Exigir que os antigos `desvios` sejam exatamente os predecessores agora provados e que não reste outro `fora_do_plano`.

**Passo 3 — implementar `--aplicar` atômico**

Repetir todas as provas sob a trava MergeX, então alterar somente:

```yaml
estado: aberto
portao: null
portao_sha: null
falhas_portao: []
causa: null
desvios: []
```

Preservar o restante byte a byte sempre que possível. Persistir pelo checkpoint `retomar-v9-predecessores`; se o commit falhar, deixar a alteração pendente e relatar, sem reset/stash/descarte.

**Passo 4 — provar que o E2 completo é obrigatório**

O script não chama E3 nem marca `pronto`. `02-prontidao.md` e o novo reference mandam reiniciar pela barreira `pre-e2` e executar V1–V11. O comando de retomada termina informando `proxima=E2`.

**Passo 5 — testes**

```bash
bash scripts/ci/test-r3-predecessores-sprintx.sh retomada
bash scripts/ci/test-causa-portao.sh
bash scripts/ci/test-r1-reconciliacao-base.sh invariantes
```

**Passo 6 — commit**

```bash
git add .claude/skills/mergex/scripts/retomar-v9-predecessores.sh \
  .claude/skills/mergex/references/00-schema.md \
  .claude/skills/mergex/references/02-prontidao.md \
  .claude/skills/mergex/references/08-registro.md \
  .claude/skills/mergex/references/13-predecessores-sprintx.md \
  .claude/commands/mergex-retomar-v9.md \
  .opencode/commands/mergex-retomar-v9.md \
  scripts/ci/test-r3-predecessores-sprintx.sh
git commit -m "feat(mergex): retoma e8 bloqueado por predecessores"
```

---

### Task 9: Fechar o contrato MergeX, decisões e integração SprintX

**Arquivos:**

- Alterar: `.claude/skills/mergex/DECISOES-DA-SKILL.md`
- Alterar: `.claude/skills/mergex/SKILL.md`
- Alterar: `.claude/skills/mergex/references/integracao/sprintx.md`
- Alterar: `.claude/commands/mergex-check.md`
- Alterar: `.claude/commands/mergex.md`
- Alterar: `.opencode/commands/mergex-check.md`
- Alterar: `.opencode/commands/mergex.md`
- Alterar: `README.md`
- Alterar: `scripts/ci/validate-mergex-contract.sh`
- Alterar: `scripts/ci/test-r3-predecessores-sprintx.sh`

**Passo 1 — testes de entrypoint e espelho**

O validador de contrato exige que os quatro entrypoints mencionem a nova fonte da V9, a recusa fail-closed e a retomada explícita. Claude Code e OpenCode devem apontar para o mesmo reference, sem duplicar a regra em versões divergentes.

**Passo 2 — decisões append-only**

Acrescentar, a partir de DM-187:

- manifesto exato como fonte adicional da V9;
- protocolo de saída validado por conteúdo+código, nunca só rc;
- recuperação pós-E8 restrita a `[v9]`/`arquivo_fora_do_plano` sem publicação;
- nenhuma alteração em task concluída ou sequência E1.

**Passo 3 — documentação operacional**

Documentar a ordem completa:

```text
registrar → validar → checkpoint predecessores → verificar retomada →
aplicar/checkpoint retomada → pre-e2 → E2 completo
```

Explicitar que MergeX antiga não entende os predecessores e que ExpxDev só pode instalar a combinação depois dos dois PRs integrados.

**Passo 4 — testes**

```bash
bash scripts/ci/validate-mergex-contract.sh
bash scripts/ci/test-r3-predecessores-sprintx.sh contrato
```

**Passo 5 — commit**

```bash
git add .claude/skills/mergex/DECISOES-DA-SKILL.md \
  .claude/skills/mergex/SKILL.md \
  .claude/skills/mergex/references/integracao/sprintx.md \
  .claude/commands/mergex-check.md .claude/commands/mergex.md \
  .opencode/commands/mergex-check.md .opencode/commands/mergex.md \
  README.md scripts/ci/validate-mergex-contract.sh \
  scripts/ci/test-r3-predecessores-sprintx.sh
git commit -m "docs(mergex): publica contrato de predecessores sprintx"
```

---

### Task 10: Certificar o fluxo MergeX com mutantes e fixture MP2.7b

**Arquivos:**

- Criar: `scripts/ci/mutacao-r3-predecessores-sprintx.sh`
- Alterar: `scripts/ci/test-r3-predecessores-sprintx.sh`
- Alterar: `scripts/ci/lib/fixture-predecessores.sh`

**Passo 1 — fechar a fixture ponta a ponta**

O grupo `mp27b` precisa executar realmente:

1. E8 bloqueado na fixture;
2. registro de spec e plano pelo script SprintX copiado para a fixture;
3. checkpoint `predecessores`;
4. V9 verde;
5. `retomar-v9-predecessores --verificar` e `--aplicar`;
6. checkpoint de retomada sem `Task:` e sem novo `seq`;
7. E2 V1–V11 novamente, com V9 verde;
8. confirmação de que tasks, commits E1, base e reconciliações não mudaram.

**Passo 2 — mutantes obrigatórios**

Matar os 15 mutantes da spec e ainda:

- `RC1VAZIO`: processo sai 1 sem `resultado=`;
- `RCDIVERGE`: texto diz `ok`, código é 1;
- `TRUNCADO`: `v9` sem `fora_do_plano`;
- `DUPRESULT`: duas linhas `resultado=`;
- `EVENTO`: inventa evento fora do enum;
- `TASKARTIFICIAL`: cria task para retomar;
- `SEQ`: acrescenta checkpoint em `ENTREGA.commits`;
- `E2PARCIAL`: pula V1–V8/V10/V11 após reabrir.

**Passo 3 — gate MergeX amplo**

Executar, sem omitir suíte existente:

```bash
bash scripts/ci/test-r3-predecessores-sprintx.sh todos
bash scripts/ci/mutacao-r3-predecessores-sprintx.sh
bash scripts/ci/test-r1-reconciliacao-base.sh todos
bash scripts/ci/test-r2-barreira-push.sh todos
bash scripts/ci/validate-mergex-contract.sh
for t in scripts/ci/test-*.sh; do bash "$t"; done
git diff --check
```

**Passo 4 — commit**

```bash
git add scripts/ci/mutacao-r3-predecessores-sprintx.sh \
  scripts/ci/test-r3-predecessores-sprintx.sh \
  scripts/ci/lib/fixture-predecessores.sh
git commit -m "test(mergex): certifica retomada por predecessores"
```

**Passo 5 — revisão antes do PR MergeX**

Rodar `superpowers:requesting-code-review` sobre todas as tasks MergeX. Conferir explicitamente segurança, parser, códigos de saída, Bash 3.2, limpeza de temporários, stage preexistente e ausência de escrita remota. Corrigir achados antes de push e abrir PR separado.

---

### Task 11: Certificação coordenada e recuperação real da MP2.7b

**Esta task só começa depois dos dois PRs anteriores estarem mergeados. Não pertence a nenhum dos dois PRs de origem.**

**Arquivos esperados em outro trabalho:**

- Alterar: pins/candidatos da SprintX e MergeX no ExpxDev
- Alterar: suíte de certificação cruzada do ExpxDev
- Criar na MP2.7b: `docs/sprintx/features/mp2-7b-consolidacao-main/00-PREDECESSORES.md`
- Alterar na MP2.7b: `docs/entregas/mp2-7b-consolidacao-main/ENTREGA.md` somente pelo script de retomada

**Passo 1 — certificar fontes, sem instalar globalmente**

Rodar a certificação ExpxDev sobre os SHAs mergeados. Ela deve provar que o marketplace contém as duas versões compatíveis e que as suítes SprintX e MergeX passam juntas.

**Passo 2 — instalar a combinação certificada no produto**

Usar o fluxo oficial do ExpxDev/marketplace, mantendo backup e conferindo lock, cache e hooks. Não usar branches ou SHAs não certificados.

**Passo 3 — recuperar a MP2.7b real**

Na branch `feature/mp2-7b-consolidacao-main`, registrar exatamente:

```text
spec commit: 85dff72f14e477bcd074050ac3b56a11911cfd60
spec blob:   7d3fe6903c1d43f685b2def2904b02e7e226213c
plan commit: 4afd01a61c1ca51d14f58a59979606ae3047bae1
plan blob:   aba5c1a22d90c22c022cc1e1549fd3c45e9fa993
nascimento:  934878cb7b5c7ad2e37f55b4342c1c88b2535268
E8 bloqueado: eb46a7e212a528687a4d1d590215d4b17b084c47
```

Criar o checkpoint `predecessores`, verificar/aplicar a retomada e executar E2 completo. Só prosseguir para E3–E8 se o novo E2 emitir `PRONTO`.

**Passo 4 — gate final do produto**

Repetir todos os gates do repositório Conselhos Municipais e conferir que as seis tasks originais, seus commits e sua sequência continuam iguais. Só então publicar/atualizar o PR da MP2.7b.

---

## Critério de conclusão do plano

O trabalho está concluído somente quando:

1. PR SprintX mergeado e sua suíte integral verde;
2. PR MergeX mergeado e sua suíte integral verde;
3. ExpxDev certificou os dois pins juntos;
4. a instalação no produto usa exatamente os SHAs certificados;
5. a MP2.7b saiu de E8 bloqueado pelos dois checkpoints de método;
6. o E2 inteiro da MP2.7b retornou `PRONTO`;
7. nenhum task, commit E1, `seq`, base ou reconciliação original foi reescrito;
8. nenhum prefixo amplo, bypass ou evento fora do contrato foi introduzido.
