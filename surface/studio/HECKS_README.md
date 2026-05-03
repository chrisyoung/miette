# Studio
Hecks Studio — the rich in-process interface where Chris and Miette work together. One server owns every cadence, exposes every command and query, renders every concept. Replaces the daemon-and-shell-script model with one persistent surface : robust sleep, a stable statusline, and the IDE for any new Hecks app we conceive together.
Generated from Bluebook on boot. Do not edit.

---

## Capabilities

- **:webapp** — 
- **:dev_tools** — 
- **:web_components** — 
- **:chat_agent** — 
- **:event_store** — Event-sourced persistence -- aggregates rebuilt from event history
- **:server_lifecycle** — 
- **:crud** — 
- **:ubiquitous_language** — 
- **:app_builder** — 

---

## Bluebook: Studio

| Aggregate | Commands | Attributes |
|-----------|----------|------------|
| Studio | 2 | 4 |
| TickedFeature | 3 | 4 |
| CommandInvocation | 1 | 6 |
| DocumentView | 3 | 3 |
| ChatTurn | 1 | 4 |
| MorningBrief | 1 | 2 |
| StatuslineSnapshot | 1 | 2 |

---

## Commands

### Studio

- `Boot(port: Integer, started_at: String)`
- `Stop`

### TickedFeature

- `Tick(last_tick_at: String)`
- `MarkLate`
- `MarkFailed`

### CommandInvocation

- `Record(aggregate_name: String, command: String, attrs_json: String, result: String, emitted_event_names: String, dispatched_at: String)`

### DocumentView

- `Open(path: String, kind: String, mode: String)`
- `Save`
- `Close`

### ChatTurn

- `Append(turn_index: Integer, role: String, content: String, created_at: String)`

### MorningBrief

- `Compose(composed_at: String, content: String)`

### StatuslineSnapshot

- `Update(payload_json: String, updated_at: String)`


---

## Command Routing

| Aggregate | Runs on |
|-----------|---------|
| Studio | server |
| TickedFeature | server |
| CommandInvocation | server |
| DocumentView | browser |
| ChatTurn | server |
| MorningBrief | server |
| StatuslineSnapshot | server |