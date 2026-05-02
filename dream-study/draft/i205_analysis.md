# i205 — heki audit noise drowning the daemon error log

**Status** : analysis + three options for Chris's decision. No code change yet ;
this draft surfaces the finding cleanly so the choice is visible.

**Surfaced** : 2026-05-02 (dream-study branch, autonomous overnight run).

## What's happening

Every out-of-band write to a `.heki` file (i.e. via `heki append/upsert/mark`
with `--reason "..."`) emits a stderr line of the form :

```
[heki:append] out-of-band:rem_branch : authentic French dream image, corpus record for wake interpretation → /Users/christopheryoung/Projects/miette/body/../../miette-state/information/dream_state.heki
```

Source : `rust/src/heki.rs:82-88` `audit_write` :

```rust
fn audit_write(ctx: &WriteContext, path: &str, op: &str) {
    let always = matches!(ctx, WriteContext::OutOfBand { .. });
    let verbose = std::env::var("HECKS_HEKI_AUDIT").ok().as_deref() == Some("1");
    if always || verbose {
        eprintln!("[heki:{}] {} → {}", op, ctx.audit_tag(), path);
    }
}
```

The `always` flag makes out-of-band writes log unconditionally. Dispatch
writes are quiet unless `HECKS_HEKI_AUDIT=1`.

## Why it's a problem

The shell wrappers (mindstream / pulse_organs / rem_branch / nrem_branch /
consolidate) route their stderr to `$ERR_LOG = $INFO/daemon_errors.log` for the
exact reason : the dispatch wrapper distinguishes real failures from
informational chatter and writes the former to the log + a Doctor.NoteConcern.

But `audit_write`'s eprintln goes to the SAME stderr stream the wrapper
captures — so every legitimate `heki append` from a shell's content step
(rem_branch's dream image append, nrem_branch's consolidation overlay,
consolidate's signal-to-memory promote) produces a line that lands in
daemon_errors.log indistinguishable in destination from real failures.

After one overnight cycle, daemon_errors.log was 647KB of pure i205 chatter
with **zero real failures hiding under it** (verified : `grep -v
"heki:append\|heki:upsert" daemon_errors.log | wc -l` → 0).

The discipline gap is visible — too visible. The signal/noise ratio makes the
log unusable as the canary the dispatch wrapper was designed for.

## Why the design is what it is

The header on `audit_write` says : *"out-of-band writes always log so the
discipline gap stays visible."* This is a real concern : out-of-band writes
are a hatch around the dispatch pipeline, and their volume IS data about how
many runtime gaps the shells are bridging. Silencing them entirely loses that
signal.

But the current routing — stderr — conflates the audit channel with the
failure channel. The daemon error log was supposed to be the failure channel ;
it's now also the audit channel, which neither needs.

## Three options

### Option A — Route audit to its own file (recommended)

`HECKS_HEKI_AUDIT_LOG` env var (defaulting to `information/.heki_audit.log`)
captures the eprintlns that today go to stderr. Stderr stays free for real
errors. The audit signal is preserved ; daemon_errors.log gets clean.

**Cost** : ~15 LOC Rust change in `audit_write`. New env var to thread. The
existing `HECKS_HEKI_AUDIT=1` flag gates verbose dispatch logging — that
behavior stays unchanged.

**Why recommended** : preserves the discipline-gap-visible intent while
fixing the conflation. Out-of-band writes are still loud, just on their own
channel.

### Option B — Default quiet for out-of-band

Drop the `always` short-circuit ; out-of-band writes only log when
`HECKS_HEKI_AUDIT=1` is set. Daemon scripts run quiet by default ; an
operator can flip the env var when investigating.

**Cost** : 1-line Rust change.

**Risk** : the discipline gap becomes invisible by default. Anyone running
the daemons with default env never sees how many out-of-band writes their
shells are doing.

### Option C — Severity tag for stderr filtering

Keep the writes on stderr but prefix them with `[AUDIT]` (vs implicit
[ERROR] for failures). Daemon wrappers then `grep -v '\[AUDIT\]'` before
appending to `daemon_errors.log` so the audit doesn't pollute the failure
log.

**Cost** : 1-line Rust change + 5 shell wrappers updated to filter.

**Risk** : couples the shell wrappers to the Rust audit format. Drift between
them is silent. The 5-shell duplication (already inbox-i215) gets one more
feature to drift on.

## Decision needed

A vs B vs C is a domain call. Recommendation : **Option A**. Preserves the
audit intent, fixes the conflation, doesn't widen the shell-wrapper coupling.

If A : I can draft the Rust change as `dream-study/draft/heki_audit_log.rs.draft`
in a future iteration. The change is contained to `heki.rs` ; antibody
exemption needed (it's runtime kernel-floor code).

## Adjacent observations

- The 5-shell wrapper duplication (i215) means the daemon log routing is
  also duplicated. A future :shell hecksagon adapter retiring all five
  shells naturally consolidates the audit-vs-error filtering decision into
  the adapter layer — Option C might land there for free if the adapter
  declares its log routing.

- `dream_state.heki` accumulates one row per dream pulse with a 200-char
  text body. After the overnight run, dream_state.heki has 70+ rows. A
  future `DreamCorpus` aggregate (Phase 6 PM's note 3) would window /
  archive these ; the audit chatter just makes the volume visible.
