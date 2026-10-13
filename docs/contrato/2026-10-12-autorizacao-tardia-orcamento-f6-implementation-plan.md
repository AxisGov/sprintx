# SprintX Late F6 Budget Authorization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one audited, atomic command that lets a human authorize the previously undeclared F6 replan budget and resume only the exact `orcamento_f6_nao_declarado` terminal.

**Architecture:** Extend the existing `planejamento.sh` state machine instead of adding a second writer. The command records a three-field late-authorization audit tuple, reuses the current F6 frontier/frozen/partial proofs, and opens round 1 atomically under a worktree-local lock. Recovery is driven only by committed or pending planning state, with an explicit arguments → partials → pending-invariants → persistence precedence.

**Tech Stack:** POSIX-oriented Bash 3.2, Git, Markdown/YAML frontmatter, the existing shell test harness in `.claude/hooks/testes/bancada.sh`.

**Spec:** `docs/contrato/2026-10-12-autorizacao-tardia-orcamento-f6-design.md`

## Global Constraints

- Support Bash 3.2: no arrays, `local -n`, `mapfile`, associative maps, `flock`, Python, jq, network, or GNU-only parsing.
- `planejamento.sh` remains the only writer of `00-PLANEJAMENTO.md`; writes use the current atomic temporary-file replacement.
- The new command is exactly `planejamento.sh autorizar-replanejamento-execucao <slug> <max_replanejamentos_f6> <autorizado_por>`.
- Initial recovery is allowed only from `replanejamento_execucao_recusado` plus `recusa_replanejamento_f6: orcamento_f6_nao_declarado`, with F6 present, max `null`, count `0`, and no active round.
- `orcamento_declarado_por` is never changed by late authorization; `autorizacao_tardia_f6_por` is the only canonical late-F6 authority.
- The audit tuple is all-or-none and append-only: `autorizacao_tardia_f6_por`, `autorizacao_tardia_f6_em`, `autorizacao_tardia_f6_origem`.
- Repeated-call precedence is arguments (`4`) → frozen/partials (`2`) → pending B-NN/task invariants (`4`) → persistence (`3` pending, `0` durable).
- All other terminals and refusal reasons remain terminal; no generic reopen, no reset to `aprovado`, no task creation, no automatic migration.
- Checkpoints remain local commits limited to `docs/sprintx/features/<slug>/**`; this work never pushes.
- Each task follows red → green → focused review → commit; no task starts before the previous task is green.

## Review Focus

- A rejected checkpoint followed by a second invocation must not be rejected by the old terminal guard or consume round 2; Task 5 pins pending → checkpoint → resumed.
- A pending authorization whose B-NN closes, changes class, or whose task becomes unblocked must not be persisted by either entrypoint; Task 5 tests both the authorization command and direct `checkpoint`.
- `orcamento_declarado_por: null` with a valid late audit tuple must be valid, while the same positive F6 max without the tuple must remain invalid; Task 1 pins both sides.
- A call with different arguments and a divergent partial at the same time must return argument error `4`, while matching arguments plus divergent partial returns `2`; Task 5 pins precedence.
- `aprovado` plus a nonempty F6 block list is closing-pending, not a normal resume, while an emptied list is closed and returns `5`; Task 5 pins the boundary.

---

### Task 1: Persist and validate the late-authorization audit tuple

**Files:**
- Modify: `.claude/skills/sprintx/scripts/planejamento.sh:90-297, 764-968`
- Modify: `.claude/hooks/testes/bancada.sh:1487-2055`

**Interfaces:**
- Consumes: existing `fm_carrega`, `fm_em`, `fm_presente`, `data_iso`, `valida_orcamento`, `le_f6`, `f6_herda`, `f6_novo`, and `escreve`.
- Produces: `le_autorizacao_tardia_f6` setting `P_AUT6_POR`, `P_AUT6_EM`, `P_AUT6_ORIGEM`, and `P_AUT6=presente|ausente`; writer variables `W_AUT6_POR`, `W_AUT6_EM`, `W_AUT6_ORIGEM`; `valida_dono_f6 <max6> <orcamento_declarado_por> <autorizacao_tardia_f6_por>`.

- [ ] **Step 1: Add failing schema and writer tests to section K of the harness**

Add cases named `k23-autorizacao-tardia-trio-all-or-none`, `k24-autorizacao-tardia-preserva-dono-compartilhado`, `k25-autorizacao-tardia-null-compartilhado-valido`, `k26-autorizacao-tardia-origem-data-e-recusa`, and `k27-planejamento-antigo-continua-valido`. Assert:

```text
one/two audit keys => rc 4
all three + positive max/count + active round => schema accepted
shared owner buildx remains buildx
shared owner null remains null when the valid tuple owns F6
positive max + shared owner null + no tuple => rc 4
invalid date/origin or tuple plus active refusal => rc 4
existing fixtures without the tuple remain green
```

- [ ] **Step 2: Run the harness and verify the new cases fail**

Run: `bash .claude/hooks/testes/bancada.sh`

Expected: nonzero, with at least `k23`–`k26` failing because the tuple is not parsed or emitted and the old owner rule rejects the canonical late-owner case.

- [ ] **Step 3: Implement tuple parsing and validation**

In `planejamento.sh`:

```text
le_autorizacao_tardia_f6() -> P_AUT6, P_AUT6_POR, P_AUT6_EM, P_AUT6_ORIGEM
valida_dono_f6(max6, shared_owner, late_owner) -> 0 or E_CONTRATO
```

Require all three keys or none; validate lowercase authority, ISO date, origin exactly `orcamento_f6_nao_declarado`, positive max and count ≥ 1, and absence of `recusa_replanejamento_f6`. Preserve old files. Change the positive-F6 ownership rule to the explicit disjunction from the spec without weakening `criar`.

- [ ] **Step 4: Extend the single writer without changing legacy output**

Make `f6_herda` copy the tuple, `f6_novo` initialize it absent, and `escreve` emit all three keys only when the writer tuple is present. Keep `orcamento_declarado_por` byte-for-byte unchanged during a late write. Update the planning prose to name the late authority from `W_AUT6_POR`, never the shared owner.

- [ ] **Step 5: Run syntax and focused/full harness checks**

Run:

```bash
bash -n .claude/skills/sprintx/scripts/planejamento.sh
bash -n .claude/hooks/testes/bancada.sh
bash .claude/hooks/testes/bancada.sh
```

Expected: all tests green; no existing serialized planning fixture changes unless it contains the new tuple.

- [ ] **Step 6: Commit Task 1**

```bash
git add .claude/skills/sprintx/scripts/planejamento.sh .claude/hooks/testes/bancada.sh
git commit -m "feat(sprintx): valida autoria tardia do orcamento f6"
```

### Task 2: Extract one behavior-preserving F6 round opener

**Files:**
- Modify: `.claude/skills/sprintx/scripts/planejamento.sh:1384-1551`
- Modify: `.claude/hooks/testes/bancada.sh:1608-1705`

**Interfaces:**
- Consumes: existing `calcula_congeladas`, writer variables `W6_*`, `escreve`, `evento`, and `checkpoint`.
- Produces: `abre_rodada_f6 <ordered-B-NN-list> <max6> [<aut_por> <aut_em> <aut_origem>]`; it opens and checkpoints one already-validated round, writes the optional audit tuple atomically, increments the F6 round exactly once, and leaves caller-specific stdout to the caller.


- [ ] **Step 1: Add a refactor characterization test**

Add `l0-abridor-compartilhado-preserva-replanejar-execucao`. Run the normal `replanejar-execucao` happy path and capture: planning file checksum, stdout keys, event types/counts, checkpoint trailers, F6 count/list/frozen/signature/partials, and commit path list.

- [ ] **Step 2: Run the characterization test on the current implementation**

Run: `bash .claude/hooks/testes/bancada.sh`

Expected: PASS. This is a refactor safety baseline, not a new-behavior red test.

- [ ] **Step 3: Extract `abre_rodada_f6`**

Move only the common mutation sequence out of `cmd_replanejar_execucao`: compute frozen/signature/partials, increment exactly once, set active B-NNs, write state, emit `replanejamento_execucao_iniciado`, and checkpoint. Keep validation, refusal paths, and stdout in the original command. The extracted function receives the ordered list and budget; it does not discover B-NNs or choose a terminal.

- [ ] **Step 4: Prove byte/behavior equivalence**

Run:

```bash
bash -n .claude/skills/sprintx/scripts/planejamento.sh
bash .claude/hooks/testes/bancada.sh
git diff --check
```

Expected: all existing tests and the characterization test green; no public output changes.

- [ ] **Step 5: Commit Task 2**

```bash
git add .claude/skills/sprintx/scripts/planejamento.sh .claude/hooks/testes/bancada.sh
git commit -m "refactor(sprintx): extrai abertura da rodada f6"
```

### Task 3: Add the worktree-local authorization lock

**Files:**
- Create: `.claude/skills/sprintx/scripts/lib/trava-autorizacao-f6.sh`
- Modify: `.claude/skills/sprintx/scripts/planejamento.sh:1-16`
- Modify: `.claude/hooks/testes/bancada.sh:1487-2055`

**Interfaces:**
- Consumes: Git `rev-parse --git-path`, repository root, slug, atomic `mkdir`, and shell `trap`.
- Produces: `adquire_trava_autorizacao_f6 <repo-root> <slug>` setting `TRAVA_AUT6_DIR` and `TRAVA_AUT6_ADQUIRIDA=sim`; `libera_trava_autorizacao_f6` removing only a lock acquired by this process.

- [ ] **Step 1: Add failing focused lock tests**

Source the new library from an isolated test shell. Add `l-lock-1-caminho-por-worktree-e-slug`, `l-lock-2-concorrente-recusada`, `l-lock-3-trap-remove-so-a-propria`, and `l-lock-4-existente-nao-e-removida`. Assert two worktrees or two slugs resolve distinct paths, simultaneous acquisition yields one success, normal/abnormal exit releases only the acquired directory, and a preexisting directory fails closed and remains.

- [ ] **Step 2: Run the harness and verify the library is missing**

Run: `bash .claude/hooks/testes/bancada.sh`

Expected: nonzero because `scripts/lib/trava-autorizacao-f6.sh` does not exist.

- [ ] **Step 3: Implement the lock library and source it**

Keep the library free of command dispatch. Resolve the lock inside the worktree's Git path, include the validated slug, acquire with `mkdir`, record ownership only after success, and make cleanup conditional on `TRAVA_AUT6_ADQUIRIDA=sim`. Do not reclaim stale locks by PID or age.

- [ ] **Step 4: Run lock and regression checks**

Run:

```bash
bash -n .claude/skills/sprintx/scripts/lib/trava-autorizacao-f6.sh
bash -n .claude/skills/sprintx/scripts/planejamento.sh
bash .claude/hooks/testes/bancada.sh
```

Expected: four lock tests and all existing tests green.

- [ ] **Step 5: Commit Task 3**

```bash
git add .claude/skills/sprintx/scripts/lib/trava-autorizacao-f6.sh \
  .claude/skills/sprintx/scripts/planejamento.sh \
  .claude/hooks/testes/bancada.sh
git commit -m "feat(sprintx): adiciona trava da autorizacao tardia f6"
```

### Task 4: Open the first late-authorized F6 round from the exact terminal

**Files:**
- Modify: `.claude/skills/sprintx/scripts/planejamento.sh:16-29, 392-763, 1361-1569, 1688-1712`
- Modify: `.claude/hooks/testes/bancada.sh:1487-2055`

**Interfaces:**
- Consumes: Task 1 tuple reader/writer, Task 2 `abre_rodada_f6`, Task 3 lock, and current blocking/frontier helpers.
- Produces: `cmd_autorizar_replanejamento_execucao <slug> <max6> <por>` and public help/dispatch entry.

- [ ] **Step 1: Add failing initial-transition tests**

Create the terminal fixture through the real `replanejar-execucao` path with max F6 `null`. Add cases covering spec tests 1–9 and 14–19: clean/partial happy paths; exact origin/audit/events/trailers; invalid values; every other terminal/reason; missing or mixed B-NNs; unblocked task; every unsafe frontier; simultaneous commands; preexisting lock. Use exact expected codes: unauthorized known state/reason `5`, invalid arguments/schema `4`, unsafe frontier/partial `2`.

- [ ] **Step 2: Run the harness and verify command-not-found failure**

Run: `bash .claude/hooks/testes/bancada.sh`

Expected: nonzero; first happy path reports unknown command.

- [ ] **Step 3: Implement only the initial command path**

Acquire the Task 3 lock, reread after acquisition, validate exactly three arguments and the exact terminal/schema/B-NN/task/frontier preconditions, and pass the max plus the complete audit tuple to Task 2's opener. The opener clears the active refusal, writes the tuple, and increments the F6 count exactly once. Then print the spec's `autorizacao_f6=aplicada` block. Do not implement pending/durable repeat handling yet.

- [ ] **Step 4: Add public usage/dispatch and verify**

Run:

```bash
bash -n .claude/skills/sprintx/scripts/planejamento.sh
bash .claude/hooks/testes/bancada.sh
git diff --check
```

Expected: all initial-transition tests green, one round/commit, exactly one authorization event and one start event.

- [ ] **Step 5: Commit Task 4**

```bash
git add .claude/skills/sprintx/scripts/planejamento.sh .claude/hooks/testes/bancada.sh
git commit -m "feat(sprintx): autoriza rodada f6 a partir da recusa"
```

### Task 5: Make pending checkpoint recovery deterministic and idempotent

**Files:**
- Modify: `.claude/skills/sprintx/scripts/planejamento.sh:695-763, 1133-1244, 1361-1603`
- Modify: `.claude/hooks/testes/bancada.sh:1487-2055`

**Interfaces:**
- Consumes: Task 4 command, Task 2 opener, Task 3 lock, and existing `persistencia`, `confere_congeladas`, `confere_parciais`, `fecha_rodada`, `checkpoint`.
- Produces: `classifica_autorizacao_tardia_f6 <requested_max> <requested_owner>` setting `AUT6_ACAO=checkpoint_pendente|retomada|fechamento_pendente|fechada`; `confere_pendente_autorizacao_f6` shared by the command and `checkpoint`.

- [ ] **Step 1: Add failing recovery and precedence tests**

Use the existing rejecting pre-commit fixture. Add cases `m1`–`m10` covering spec tests 10–13 and 20–23:

```text
failed checkpoint leaves state/audit/round on disk and old terminal in HEAD
same call => checkpoint_pendente, rc 3, no new event/count/write
direct checkpoint => one commit of exact pending bytes; same call then => retomada rc 0
different max or owner while pending => rc 4 before pending result
matching args plus lost/divergent partial => rc 2 before pending/resume
pending B-NN closed/class changed/task unblocked => command rc 4 and checkpoint rc 4, no commit
same durable call => resumed with no event/count/commit duplication
approved + nonempty active list => closing pending rc 3
list emptied by real fecha_rodada => rc 5, audit tuple remains historical
different args after durable open => rc 4; after close => rc 5
```

- [ ] **Step 2: Run the harness and observe the wrong terminal behavior**

Run: `bash .claude/hooks/testes/bancada.sh`

Expected: nonzero; the repeat after rejected checkpoint reaches the old terminal/state guard or fails to emit `checkpoint_pendente`.

- [ ] **Step 3: Implement the ordered recovery classifier**

When the audit tuple and active list are present, branch before the initial terminal guard. Implement this exact order:

```text
requested max/owner mismatch -> E_CONTRATO (4)
frozen/signature/partials mismatch -> E_RECUSADO (2)
if pending: open/class/task invariants mismatch -> E_CONTRATO (4)
if pending and valid -> checkpoint_pendente (3)
if approved + active list -> fechamento_pendente (3)
if durable active -> retomada (0)
if active list empty but audit remains -> transition refused (5)
```

Do not emit a resume event for a pending response; preserve the existing normal F6 resume event behavior unless the tests prove duplication.

- [ ] **Step 4: Guard direct checkpoint persistence**

At the start of `checkpoint`, after loading the plan and before `git add`, detect a non-durable late authorization. Validate the stored tuple, frozen/signature/partials, open B-NN classes, and blocked tasks. On any failure, leave index, working tree, HEAD, events, and counters unchanged. Only then allow the existing checkpoint implementation to stage and commit.

- [ ] **Step 5: Run syntax, full harness, and repository integrity checks**

Run:

```bash
bash -n .claude/skills/sprintx/scripts/planejamento.sh
bash -n .claude/hooks/testes/bancada.sh
bash .claude/hooks/testes/bancada.sh
git diff --check
```

Expected: every precedence/idempotency test green, existing checkpoint/F6 tests unchanged, zero internal skips.

- [ ] **Step 6: Commit Task 5**

```bash
git add .claude/skills/sprintx/scripts/planejamento.sh .claude/hooks/testes/bancada.sh
git commit -m "fix(sprintx): torna retomada tardia f6 idempotente"
```

### Task 6: Publish DS-175, documentation, contract tests, and mutants

**Files:**
- Modify: `.claude/skills/sprintx/references/00-schema.md:66-67, 783-921`
- Modify: `.claude/skills/sprintx/references/03-plano.md:7-13, 230-268`
- Modify: `.claude/skills/sprintx/references/06-execucao.md:8-11, 175-189`
- Modify: `.claude/skills/sprintx/references/08-rastro.md:19-25`
- Modify: `.claude/skills/sprintx/DECISOES-DA-SKILL.md` (append DS-175 only)
- Modify: `.claude/skills/sprintx/SKILL.md:24-64, 250-258`
- Modify: `.claude/skills/sprintx/assets/TEMPLATE-PLANEJAMENTO.md:5-64`
- Modify: `.claude/hooks/testes/bancada.sh` (contract assertions and 21 mutants)

**Interfaces:**
- Consumes: final Task 1–5 behavior and exact public outputs.
- Produces: public DS-175 contract, operator recovery instructions, event definitions, template comments, contract assertions, and the complete mutation gate.

- [ ] **Step 1: Add failing contract assertions for every public surface**

Add harness assertions that require:

```text
00-schema: tuple/all-or-none, explicit ownership disjunction, recoverable exact terminal only
03-plano: terminal remains terminal until the explicit late-authorization command; then F3
06-execucao: human-only command, exact outputs/codes, pending checkpoint recovery
08-rastro: orcamento_f6_autorizado plus existing start event, each once
SKILL.md: command and exact boundary among recoverable/unrecoverable terminals
template: optional tuple and canonical authority comments
DECISOES: one append-only DS-175 row matching the approved spec
```

- [ ] **Step 2: Run the harness and verify contract assertions fail**

Run: `bash .claude/hooks/testes/bancada.sh`

Expected: nonzero on the first missing DS-175/public-contract assertion.

- [ ] **Step 3: Update references, template, skill, and decision ledger**

Copy the approved rules from the spec without introducing a second command or alternate owner. Keep prior decisions intact; append DS-175. Document `checkpoint_pendente`, the argument/partial/invariant precedence, round-active definition, direct checkpoint guard, and the rollout boundary.

- [ ] **Step 4: Add exactly these 21 mutation cases from the spec**

Use isolated copies of the skill, as the existing mutation sections do. Number every harness mutant `ds175-mutante-01` through `ds175-mutante-21`, one semantic change each:

1. accept any refused terminal;
2. accept `classes_mistas`;
3. set the max without incrementing the round;
4. increment without the late audit tuple;
5. remove the active refusal without preserving its origin;
6. open without a blocked task;
7. open without `fronteira_segura`;
8. skip storing/checking the partial hash;
9. let the second identical call consume another round;
10. accept different repeat arguments;
11. reassign an existing F5 owner;
12. allow active refusal and late tuple together;
13. remove the concurrency lock;
14. treat an existing lock as success;
15. auto-migrate a legacy plan;
16. evaluate the terminal guard before pending recovery;
17. read late authority from, or write it into, `orcamento_declarado_por`;
18. return pending before rejecting different arguments;
19. return pending/resumed before checking partial loss/divergence;
20. persist after B-NN closure/class change or task unblock;
21. treat closing-pending as normal resume or an emptied list as active.

Each mutant must be killed by a named case, and the intact control copy must survive all cases.

- [ ] **Step 5: Run the complete verification gate**

Run:

```bash
bash -n .claude/skills/sprintx/scripts/planejamento.sh
bash -n .claude/hooks/testes/bancada.sh
bash .claude/hooks/testes/bancada.sh
git diff --check
git status --short
```

Expected: harness exit `0`, `0 falhas`, `0 skip(s) interno(s)`, all 21 DS-175 mutants dead, and only declared Task 6 files modified.

- [ ] **Step 6: Review the complete branch against the spec**

Verify section-by-section coverage of the 23 mandatory tests, 21 mutants, all public outputs/codes, Bash 3.2 compatibility, exact terminal boundary, no network/push, and no unrelated reformatting. Record any issue before committing; do not waive surviving mutants.

- [ ] **Step 7: Commit Task 6**

```bash
git add .claude/skills/sprintx/references/00-schema.md \
  .claude/skills/sprintx/references/03-plano.md \
  .claude/skills/sprintx/references/06-execucao.md \
  .claude/skills/sprintx/references/08-rastro.md \
  .claude/skills/sprintx/DECISOES-DA-SKILL.md \
  .claude/skills/sprintx/SKILL.md \
  .claude/skills/sprintx/assets/TEMPLATE-PLANEJAMENTO.md \
  .claude/hooks/testes/bancada.sh
git commit -m "docs(sprintx): publica contrato de autorizacao tardia f6"
```

## Final Branch Gate

- [ ] Run `bash .claude/hooks/testes/bancada.sh` from a clean index.
- [ ] Run `git diff --check 796895a...HEAD`.
- [ ] Confirm every commit after the spec/plan is task-scoped and no remote branch or PR exists.
- [ ] Ask Claude for an independent read-only branch review; fix every material finding and rerun the full gate.
- [ ] Only after that review is green, prepare the handoff for SprintX integration, ExpxDev recertification, product installation, and the preserved MP2.7b recovery command.
