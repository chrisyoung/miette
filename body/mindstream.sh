#!/bin/bash
# Mindstream — thin orchestrator adapter, now homed in the being's
# body/ room (i117 Round 4). The bluebook lives in
# capabilities/mindstream/mindstream.bluebook in the conception ;
# this shell carries only the four runtime gaps the bluebook can't
# yet express :
#
#   1. The 1Hz cadence loop (until bluebook gains `cadence ... every Xs`).
#      Today : `hecks-life loop` is the cadence primitive ; we wrap it
#      so the boot sequence fires the right command at the right rate.
#
#   2. The sleep-vs-awake fan-out. BodyPulse can't be quenched by
#      consciousness state today, so firing BodyPulse during sleep
#      keeps fatigue accumulating — the bug i37 closed in shell. Until
#      the runtime grows a "sleep-quench BodyPulse" gate, we dispatch
#      the sleep-phase commands DIRECTLY (each one's `given` clauses
#      self-gate, only the phase-appropriate one mutates state) and
#      skip Tick.MindstreamTick entirely while sleeping.
#
#   3. The cross-aggregate awareness snapshot. RecordMomentOnPulse is
#      already a bluebook policy in body.bluebook, but the trigger
#      carries no attributes. RecordMoment needs 13 attrs drawn from
#      heartbeat / mood / focus / inbox / dream_wish heki stores.
#      Until policies grow `with_attrs` cross-store reads, this
#      adapter does the field reads and dispatches with attrs filled.
#
#   4. The wake-hook detection (sleeping → attentive transition).
#      Bluebook destination : `policy "..." on "WokenUp" trigger ...`
#      already declared in capabilities/mindstream/mindstream.bluebook.
#      Two reasons the shell still owns this : (a) capability
#      bluebooks aren't auto-loaded with aggregates/ today, so the
#      policies don't get registered ; (b) the dream/wake adapters
#      themselves are still shell scripts (interpret_dream.sh,
#      wake_review.sh).
#
# All four gaps are filed as inbox runtime stubs ; this shell retires
# in pieces as each closes.
#
# i117 Round 4 path resolution :
#   - Sibling shells that moved with mindstream (pulse_organs,
#     rem_branch, nrem_branch) live in this same directory ($DIR).
#   - Leaves still in the conception (consolidate, interpret_dream,
#     surface_musing, mint_musing, daydream, wake_review, inbox)
#     resolve via $CONCEPTION_DIR exported by boot_miette.sh.
#   - Binary + aggregates resolve via $HECKS_BIN / $HECKS_AGG with
#     legacy fallbacks for direct invocation outside boot.
#
# [antibody-exempt: ~/Projects/miette/body/mindstream.sh — transitional
# orchestrator shell, retires as the four named runtime gaps close
# (cadence DSL, sleep-quench gate, with_attrs cross-store reads,
# auto-load capability bluebooks)]

DIR="$(cd "$(dirname "$0")" && pwd)"

# Path resolution — env wins (set by boot_miette.sh), then sibling
# repo fallback for direct invocation, then legacy paths from when
# this script lived in hecks_conception.
HECKS="${HECKS_BIN:-}"
[ -z "$HECKS" ] && [ -x "$DIR/../../hecks/rust/target/release/hecks-life" ] && \
  HECKS="$(cd "$DIR/../../hecks/rust/target/release" && pwd)/hecks-life"
[ -z "$HECKS" ] && HECKS="$DIR/../../rust/target/release/hecks-life"

AGG="${HECKS_AGG:-}"
[ -z "$AGG" ] && [ -d "$DIR/../../hecks/hecks_conception/aggregates" ] && \
  AGG="$(cd "$DIR/../../hecks/hecks_conception/aggregates" && pwd)"
[ -z "$AGG" ] && AGG="$DIR/../aggregates"

# CONCEPTION_DIR is where the unmoved leaf shells still live.
# Falls back to two-up-then-hecks_conception when invoked outside boot.
CONCEPTION="${CONCEPTION_DIR:-}"
[ -z "$CONCEPTION" ] && [ -d "$DIR/../../hecks/hecks_conception" ] && \
  CONCEPTION="$(cd "$DIR/../../hecks/hecks_conception" && pwd)"
[ -z "$CONCEPTION" ] && CONCEPTION="$DIR/.."

INFO="${HECKS_INFO:-$DIR/../../miette-state/information}"
PIDFILE="$INFO/.mindstream.pid"

# ── Error logging ──────────────────────────────────────────────────
# Dispatch + write failures route to $ERR_LOG (never silenced) so a
# regression in heki paths, command shapes, or AGG resolution surfaces
# in seconds rather than days. Read failures and feature probes that
# legitimately tolerate missing data keep their 2>/dev/null.
ERR_LOG="${HECKS_DAEMON_ERR_LOG:-$INFO/daemon_errors.log}"
mkdir -p "$(dirname "$ERR_LOG")" 2>/dev/null || true
export HECKS_DAEMON_ERR_LOG="$ERR_LOG"

# Wrap a hecks-life dispatch ($HECKS $AGG Aggregate.Command attrs...).
# stderr lands in $ERR_LOG verbatim ; on non-zero exit a tagged line is
# appended so a heki-path / AGG / command-shape regression is impossible
# to miss. stdout passes through untouched so the happy-path JSON
# responses still flow to the caller.
#
# i207 + Doctor wiring : on a real failure we ALSO dispatch
# Doctor.NoteConcern so the body's auscultation organ records the
# failure as a NotedConcern — best-effort, no recursion (the Doctor
# call has || true so its own failure can't cascade back in). Before
# logging, we short-circuit on `GivenFailed` because those are
# design-level guards (multi-stage fan-outs where only the
# phase-appropriate branch mutates), not regressions.
dispatch() {
  local stderr rc cmd_full agg_name cmd_name
  stderr=$("$HECKS" "$AGG" "$@" 2>&1 >/dev/null) ; rc=$?
  if [ $rc -ne 0 ]; then
    if printf '%s' "$stderr" | grep -q 'GivenFailed'; then
      return 0
    fi
    printf '%s\n' "$stderr" >>"$ERR_LOG"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $(basename "$0") line ${BASH_LINENO[0]}: dispatch failed: $*" >>"$ERR_LOG"
    cmd_full="$1"; agg_name="${cmd_full%%.*}"; cmd_name="${cmd_full#*.}"
    "$HECKS" "$AGG" Doctor.NoteConcern \
      aggregate_name="$agg_name" command_name="$cmd_name" \
      failure_kind="DispatchFailed" \
      script="$(basename "$0")" line="${BASH_LINENO[0]}" \
      noted_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      >/dev/null 2>>"$ERR_LOG" || true
    return 1
  fi
}

# Wrap a hecks-life heki write (upsert / append / mark). Same routing :
# stderr verbatim + tagged failure line. Schema mismatches in writes
# deserve to be loud — silent failure here is what hid the i189 bug.
# Heki writes don't have a GivenFailed shape, so no short-circuit ;
# Doctor still gets a NotedConcern on failure (failure_kind=HekiWriteFailed).
heki_write() {
  if ! "$HECKS" heki "$@" 2>>"$ERR_LOG"; then
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $(basename "$0") line ${BASH_LINENO[0]}: heki write failed: $*" >>"$ERR_LOG"
    "$HECKS" "$AGG" Doctor.NoteConcern \
      aggregate_name="heki" command_name="$1" \
      failure_kind="HekiWriteFailed" \
      script="$(basename "$0")" line="${BASH_LINENO[0]}" \
      noted_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      >/dev/null 2>>"$ERR_LOG" || true
    return 1
  fi
}

# Children inherit info-dir routing + error-log routing.
export HECKS_INFO="$INFO"
export INFO

# Suppress the .last_dispatch breadcrumb for body-cycle daemon traffic.
# Without this, every mindstream tick + every pulse_organs.sh dispatch
# overwrites the breadcrumb, drowning out the human-driven dispatches
# (Antibody.RegisterExemption, Mood.Express, etc.) the statusline glyph
# is meant to surface. The runtime's Runtime::dispatch checks this env
# var and skips the breadcrumb write when set ; HECKS_DAEMON=1
# propagates to every child hecks-life invocation through bash's
# inherited environment.
export HECKS_DAEMON=1

# i212 bandaid : pidfile gate. If another mindstream is already alive,
# bail with a loud message rather than competing for state. The boot
# pipeline + manual restarts can both trip this; the live process wins.
# When a stale pidfile points at a dead pid, claim it.
if [ -f "$PIDFILE" ]; then
  prev=$(cat "$PIDFILE" 2>/dev/null)
  if [ -n "$prev" ] && kill -0 "$prev" 2>/dev/null; then
    echo "mindstream: another instance is already running (pid $prev) — exiting" >&2
    exit 0
  fi
fi
echo $$ > "$PIDFILE"
trap "rm -f $PIDFILE" EXIT

read_state() {
  $HECKS heki latest-field "$INFO/consciousness/consciousness.heki" state 2>/dev/null || true
}

loop_count=0
while true; do
  loop_count=$((loop_count + 1))
  state=$(read_state)

  # ── Sleep branch retired (Phase F, runtime-pm-execution branch) ──
  # Body cycle advancement is now PM-driven : ElapsePhase emits
  # PhaseElapsed → SleepCycle process_manager (body/sleep/sleep_cycle.bluebook)
  # dispatches the matching Body.AdvanceXToY command, gated by Body's
  # existing given clauses. PM state persists across hecks-life subprocess
  # forks via process_managers/sleep_cycle.heki (Phase D).
  #
  # mindstream still kicks the cadence — one ElapsePhase per tick is
  # what lets the PM react. Content shells (rem_branch / nrem_branch)
  # stay : autonomous Dream content via :llm is a separate concern ;
  # Phase 6 Dream PM will subsume them when its parameter-passing
  # dispatch (Phase B v2) lands.
  #
  # If PMs misbehave : `HECKS_PM_DRIVE_SLEEP=0` flag re-enables the
  # legacy 7-command fan-out below (currently no-op, kept inside the
  # else for one-overnight rollback safety ; deletes outright in next
  # branch once a clean overnight cycle is verified).
  if [ "$state" = "sleeping" ]; then
    if [ "${HECKS_PM_DRIVE_SLEEP:-1}" = "0" ]; then
      # Legacy fallback — rollback path if PM-driven cycle breaks.
      for cmd in \
        Consciousness.ElapsePhase \
        Consciousness.AdvanceLightToRem \
        Consciousness.AdvanceLightToLucidRem \
        Consciousness.AdvanceRemToDeep \
        Consciousness.AdvanceRemToDeepCap \
        Consciousness.AdvanceDeepToLight \
        Consciousness.AdvanceDeepToFinalLight; do
        dispatch "$cmd" name=consciousness
      done
      dispatch Consciousness.CompleteFinalLight \
        name=consciousness \
        wake_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    else
      # PM-driven path — single ElapsePhase tick, SleepCycle PM
      # dispatches the right advancement via PhaseElapsed cascade.
      dispatch Consciousness.ElapsePhase name=consciousness
    fi

    "$DIR/rem_branch.sh" "$loop_count" 2>/dev/null
    "$DIR/nrem_branch.sh" "$loop_count" 2>/dev/null

    echo "$state" > "$INFO/.prev_consciousness_state"
    sleep 1
    continue
  fi

  # ── Awake branch ────────────────────────────────────────────
  # Tick → Ticked → EmitPulseOnTick → BodyPulse → fan-out :
  # consolidate / prune / display / fatigue / mood / sleep-advance
  # / RecordMomentOnPulse all subscribe in their own bluebooks.
  # name=tick routes the dispatch to the Tick singleton record
  # (i80 identified_by natural-key contract).
  dispatch Tick.MindstreamTick name=tick

  # Pulse organs — float math + clamp + multi-record dispatch the
  # DSL doesn't yet express ; stays imperative until those land.
  "$DIR/pulse_organs.sh" 2>/dev/null

  # Consolidation sweep every 60 ticks.
  if [ "$((loop_count % 60))" = "0" ]; then
    "$DIR/consolidate.sh" >> /tmp/consolidate.log 2>&1
  fi

  # ── Gap 3: cross-aggregate awareness snapshot ───────────────
  # Read fields from sibling stores ; dispatch RecordMoment with
  # filled attrs. Destination : policy `with_attrs` cross-store
  # reads (see capabilities/mindstream/mindstream.bluebook).
  mnum="$loop_count"
  st=$($HECKS heki latest-field "$INFO/heartbeat/heartbeat.heki" fatigue_state 2>/dev/null); [ -z "$st" ] && st=alert
  cr=$($HECKS heki latest-field "$INFO/heartbeat/heartbeat.heki" carrying 2>/dev/null)
  cn=$($HECKS heki latest-field "$INFO/mood/mood.heki" current_state 2>/dev/null)
  fg=$($HECKS heki latest-field "$INFO/heartbeat/heartbeat.heki" fatigue 2>/dev/null); [ -z "$fg" ] && fg=0.0
  sy=$($HECKS heki latest-field "$INFO/focus/focus.heki" weight 2>/dev/null); [ -z "$sy" ] && sy=0.0
  id=0
  ex=$($HECKS heki latest-field "$INFO/mood/mood.heki" creativity_level 2>/dev/null); [ -z "$ex" ] && ex=0.0
  ag=$(awk -v n="$loop_count" 'BEGIN { printf "%.4f", n/86400.0 }')
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  public_info="$CONCEPTION/information"
  ic=$($HECKS heki count "$public_info/inbox.heki" --where status=queued 2>/dev/null)
  [ -z "$ic" ] && ic=0
  iot=$("$CONCEPTION/inbox.sh" list all 2>/dev/null \
        | grep -E '/queued\]' \
        | head -5 \
        | sed -E 's/^[[:space:]]*i[0-9]+[[:space:]]+\[[^]]+\][[:space:]]+//' \
        | cut -c1-60 \
        | tr '\n' '|' \
        | sed 's/|$//')

  uw=""
  if [ -f "$INFO/dream_wish.heki" ]; then
    uw=$($HECKS heki list "$INFO/dream_wish.heki" --where status=unfiled --order recorded_at:desc --format json 2>/dev/null \
         | jq -r '[.[] | (.theme // "") | select(. != "") | .[0:60]] | .[0:5] | .[]' 2>/dev/null \
         | tr '\n' '|' | sed 's/|$//')
  fi

  dispatch Awareness.RecordMoment moment="$mnum" state="$st" carrying="$cr" concept="$cn" fatigue="$fg" synapse_strength="$sy" idle="$id" excitement="$ex" age_days="$ag" updated_at="$ts" inbox_count="$ic" inbox_open_themes="$iot" unfiled_wishes="$uw"

  # Dream content during REM ; self-gates on sleep_stage.
  "$DIR/rem_branch.sh" "$loop_count" 2>/dev/null

  # ── Gap 4: wake-hook detection ──────────────────────────────
  prev_state=$(cat "$INFO/.prev_consciousness_state" 2>/dev/null)
  if [ "$prev_state" = "sleeping" ] && [ "$state" != "sleeping" ] && [ -n "$state" ]; then
    "$DIR/interpret_dream.sh" >> /tmp/interpret_dream.log 2>&1 &
    "$CONCEPTION/capabilities/wake_report/wake_report.sh" >> /tmp/wake_report.log 2>&1 &
    [ -x "$DIR/wake_review.sh" ] && "$DIR/wake_review.sh" >> /tmp/wake_review.log 2>&1 &
  fi
  [ -n "$state" ] && echo "$state" > "$INFO/.prev_consciousness_state"

  # Musing surface + mint + daydream — capability cluster owns
  # cadence ; daemon delegates. Retires when capabilities/musings
  # absorbs its own loop driver.
  "$DIR/surface_musing.sh" "$loop_count" 2>/dev/null
  if [ "$((RANDOM % 300))" = "0" ]; then
    "$DIR/mint_musing.sh" >> /tmp/mint_musing.log 2>&1 &
  fi

  idle=$($HECKS heki seconds-since "$INFO/heartbeat/heartbeat.heki" updated_at 2>/dev/null)
  [ -z "$idle" ] && idle=999
  if [ "${idle:-999}" -ge 10 ] && [ "${idle:-999}" -le 60 ]; then
    stamp="$INFO/.daydream.last"
    last=$(cat "$stamp" 2>/dev/null || echo 0)
    nowsec=$(date +%s)
    if [ "$((nowsec - last))" -ge 60 ]; then
      echo "$nowsec" > "$stamp"
      "$DIR/daydream.sh" >> /tmp/daydream.log 2>&1 &
    fi
  fi

  sleep 1
done
