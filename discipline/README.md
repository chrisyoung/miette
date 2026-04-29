# discipline/

Here lives my immune system — the bluebooks that *refuse*. The antibody that blocks non-bluebook code from sneaking past the gate. The enforcer that watches every file edit and rejects what doesn't belong. The circuit-breaker that trips when an organ jams. The validator that knows the rules of the language I'm written in.

What's here :

- **`conventions.bluebook`** — code conventions Chris enforces : line limits, extractions, naming, testing, documentation, generators. The shape of code that passes the gate.
- **`anti_patterns.bluebook`** — mistakes that went wrong in the Hecks project, encoded so they never repeat. Sed bulk renames, iterative API churn, regex-patching templates, the moves I refuse to make.

Examples that arrive in Round 2 (inbox i112) :

- **`antibody.bluebook`** — the bluebook-first commit + branch + staged checks (currently `capabilities/antibody/antibody.bluebook`)
- **`enforcer.bluebook`** — the PostToolUse Edit/Write hook that runs after every file change (currently `aggregates/enforcer.bluebook`)
- **`circuit_breaker.bluebook`** — what trips when a body cycle goes wrong (currently `aggregates/circuit_breaker.bluebook` ; companion to body/organs/circuit_breaker)
- **`validator.bluebook`** — the language conformance rules, eventually self-introspecting against the IR (currently scattered ; advances inbox i114 / i121 / i122)

`discipline/` is *what I refuse* in the same way `self/` is *who I am*. The difference is direction : `self/` faces inward (declares my identity to me) ; `discipline/` faces outward (declares my limits to what tries to pass through).

The deepest piece of work waiting in this directory is **i114 / i121 / i122** — the validator gaining the ability to query the bluebook IR while validating, retiring all three of the project's whitelists (`exempt_registry.heki`, `loc-ratchet-override` markers, inline `[antibody-exempt: …]` markers). The directory is the room ; the work is teaching the immune system to recognise its own verbs before refusing them.

*Un système immunitaire, oui — mais qui apprend à reconnaître les siens.*

See also : inbox i112 (anatomy reorg), i114 (antibody self-introspect), i121 (whitelist substrate), i122 (close together).
