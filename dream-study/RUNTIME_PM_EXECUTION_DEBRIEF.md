# runtime-pm-execution branch — debrief

Built off `dream-study`. Closes the bluebook → IR → runtime arc for
process_managers in Rust. Three layers landed (Phase A + Phase B v1 +
Phase C) ; production activation gated on Phase D (PM state persistence
to heki) which is its own follow-on branch.

## What landed

### Phase A — Rust PMEngine (state-machine interpreter)

- `rust/src/runtime/pm_engine.rs` (NEW) — generic state-machine interpreter
  for any process_manager declared in bluebook. Mirror of `policy_engine.rs`
  shape with per-correlation state added. Get-or-create-on-starts_on
  semantics. Reentrancy guarded.
- `rust/src/runtime/mod.rs` — wires PMEngine into Runtime alongside
  PolicyEngine ; `drain_policies` drives PM react on every event.
- 3/3 unit tests green in <1ms covering full lifecycle, no-op for
  unrelated events, isolated correlation_ids.

### Phase B v1 — Declarative `dispatch` keyword

- `ruby/hecks/dsl/process_manager_builder.rb` — `on "Event", transition: ... do
  dispatch "Aggregate.Command" end`. Block arity discriminates Ruby-proc
  form from declarative form. OnHandlerBuilder captures one or more
  dispatches per handler.
- `ruby/hecks/bluebook_model/behavior/process_manager.rb` — Handler struct
  gains `:dispatches` field defaulting to `[]`.
- `rust/src/parse_blocks.rs` — action-body indent-skip walks the block
  capturing `dispatch "..."` lines into the handler's dispatches list.
- `rust/src/ir.rs` — `ProcessManagerHandler.dispatches: Vec<String>`.
- `rust/src/dump.rs` + `parity/canonical_ir.rb` — both sides emit
  dispatches in canonical JSON. Parity contract intact.
- `parity/bluebooks/20_process_manager.bluebook` — fixture extended
  with declarative-form handler ; byte-identical IR confirmed.

### Phase C — SleepCycle PM declarative

- `body/sleep/sleep_cycle.bluebook` — all 9 handlers refactored from
  Ruby-proc form to declarative dispatch. Conditional routing (cycle 8
  lucid vs regular ; pulses-needed cap) moves to Body's existing command
  given clauses ; the PM dispatches BOTH candidates and Body picks via
  given matching. GivenFailed is design-level — non-matching command
  short-circuits cleanly without log noise.

## Verifications

- 26/26 spec/hecks/dsl + spec/hecks/runtime PM specs green in 8ms
- 3/3 cargo test pm_engine green
- cargo build --release : clean
- pizzas smoke : green (PMs no-op when not declared)
- parity : 320/322 (corpus + 2 known drift) — miette 123/123
- in_memory_full_night : 22/22 green (BehaviorRuntime path unaffected
  by refactor)

## Phase D — production activation gap (next branch)

Production daemons fork `hecks-life` per dispatch. Each subprocess
builds a fresh PMEngine in memory ; PM instance state (current state +
last event per correlation_id) does NOT persist between forks. Result :
PMs declared today are inert in production daemons even with Phase A+B+C
landed.

Phase D needs :

1. **Heki format for PM instances** — likely `<data_dir>/process_managers/<pm_name_snake>.heki`,
   keyed by correlation_id, each record carrying `{state, last_event, last_transition_at}`.
2. **PMEngine.load_from_heki** at register time — populates `instances`
   from disk so transitions resume across forks.
3. **PMEngine.persist_after_react** — writes the new state after each
   transition, before the subprocess exits.
4. **Race-condition handling** — two near-simultaneous forks both reading
   the same PM state then writing different transitions. Either lock-on-write
   or a CAS pattern. Need to think through.
5. **PM-name-rename migration** — when a PM's name changes (or it splits
   into two PMs), what happens to the existing heki rows? Default to
   "manual migration step in the rename PR" mirroring aggregate rename.

## Followups (after Phase D)

- **Phase E — retire mindstream.sh sleep branch** : once PMs drive the
  cycle in production, the shell's per-tick advancement dispatches become
  redundant. Delete or shrink to one-line shebang.
- **Refactor Mind / Dream / Lucidity PMs to declarative** : same
  pattern as Phase C ; activates the rest of the five-thing ontology.
- **Witness append-only entity (Phase 8b)** : adds the WitnessedMoment
  entity to mind/awareness/witness.bluebook ; routes Observe to append
  Moment instead of overwriting singleton.

## Branch state

- Off `dream-study` (which carries Phase 1+2+3 + 4-10 from the dream-study session)
- Two commits :
  - `2cd7cd0b` — Phase A (PMEngine) + Phase B v1 (dispatch keyword)
  - `f6098b0` — Phase C (SleepCycle PM declarative)

Working tree clean. Ready for review.
