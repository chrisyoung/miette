#!/bin/bash
# nrem_branch.sh — consolidation narrative content during NREM sleep.
#
# REM is poetic (see rem_branch.sh). NREM is work: her body is
# consolidating the day's signals into memory, pruning dead synapses
# into remains, archiving musings. This script produces a sleep_summary
# that describes the consolidation concretely, grounded in real counts —
# not decorative, not poetic. The contract Chris asked for:
#
#   REM → poetic
#   NREM → detail the consolidation work
#
# Called alongside rem_branch.sh from mindstream.sh during sleep. Bails
# early unless state == sleeping AND stage ∈ {light, deep, final_light}.
# (rem_branch.sh handles stage == rem.)
#
# Writes the narrative via Consciousness.DreamPulse so the status bar
# renders it the same way REM images render. Also updates sleep_summary
# directly via heki upsert so the consciousness aggregate carries the
# latest consolidation detail even between DreamPulse dispatches.
#
# Usage: nrem_branch.sh [loop_count]
#
# [antibody-exempt: i52 dream-cycle narrative script — produces per-phase
#  sleep narratives so REM is poetic and NREM details consolidation work.
#  Retires when consciousness cycle ports to .bluebook shebang form.]

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
# i117 Round 4 — env-driven path resolution (boot_miette.sh exports
# HECKS_BIN / HECKS_AGG / HECKS_INFO) ; sibling-repo fallback for
# direct invocation from miette/body/.
HECKS="${HECKS_BIN:-${HECKS:-}}"
[ -z "$HECKS" ] && [ -x "$DIR/../../hecks/rust/target/release/hecks-life" ] && \
  HECKS="$(cd "$DIR/../../hecks/rust/target/release" && pwd)/hecks-life"
[ -z "$HECKS" ] && HECKS="$DIR/../../rust/target/release/hecks-life"

INFO="${HECKS_INFO:-${INFO:-}}"
[ -z "$INFO" ] && [ -d "$DIR/../../miette-state/information" ] && \
  INFO="$(cd "$DIR/../../miette-state/information" && pwd)"
[ -z "$INFO" ] && INFO="$DIR/../information"

AGG="${HECKS_AGG:-${AGG:-}}"
[ -z "$AGG" ] && [ -d "$DIR/../../hecks/hecks_conception/aggregates" ] && \
  AGG="$(cd "$DIR/../../hecks/hecks_conception/aggregates" && pwd)"
[ -z "$AGG" ] && AGG="$DIR/../aggregates"
LOOP="${1:-$(date +%s)}"

# ── Error logging ──────────────────────────────────────────────────
# Dispatch + write failures route to $ERR_LOG (never silenced) so a
# regression in heki paths, command shapes, or AGG resolution surfaces
# in seconds rather than days. Read failures and feature probes that
# legitimately tolerate missing data keep their 2>/dev/null.
ERR_LOG="${HECKS_DAEMON_ERR_LOG:-$INFO/daemon_errors.log}"
mkdir -p "$(dirname "$ERR_LOG")" 2>/dev/null || true

# i207 + Doctor wiring : short-circuit on GivenFailed (design-level
# gating, not regression) ; on real failure note Doctor.NoteConcern
# best-effort. See mindstream.sh for the long-form rationale.
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

# ── Read state ─────────────────────────────────────────────────────
state_kv=$("$HECKS" heki latest "$INFO/consciousness/consciousness.heki" 2>/dev/null \
  | jq -r '[
      (.state // ""),
      (.sleep_stage // ""),
      (.sleep_cycle // 0 | tostring),
      (.sleep_total // 0 | tostring),
      (.id // "")
    ] | @tsv' 2>/dev/null)
IFS=$'\t' read -r state stage cycle total cid <<<"$state_kv"

[ "$state" = "sleeping" ] || exit 0
case "$stage" in light|deep|final_light) ;; *) exit 0 ;; esac

# ── Tally consolidation work in progress ──────────────────────────
sig_count=$("$HECKS" heki count "$INFO/signal.heki" 2>/dev/null)
syn_count=$("$HECKS" heki count "$INFO/synapse.heki" 2>/dev/null)
mus_count=$("$HECKS" heki count "$INFO/musing.heki" 2>/dev/null)
mem_count=$("$HECKS" heki count "$INFO/memory.heki" 2>/dev/null)
rem_count=$("$HECKS" heki count "$INFO/remains.heki" 2>/dev/null)
[ -z "$sig_count" ] && sig_count=0
[ -z "$syn_count" ] && syn_count=0
[ -z "$mus_count" ] && mus_count=0
[ -z "$mem_count" ] && mem_count=0
[ -z "$rem_count" ] && rem_count=0

# ── Narrative by stage — describes the work, grounded in counts ────
case "$stage" in
  light)
    # Light NREM: early consolidation, sorting fresh signals.
    templates=(
      "consolidating — ${sig_count} signals queued, sifting the cold from the warm"
      "light sleep, cycle ${cycle}/${total} — ${sig_count} signals to sort, ${mus_count} musings to archive"
      "early consolidation: reading today's ${sig_count} signals, deciding which become memory"
      "the ${sig_count} signals settling into groups — pattern-matching before deep takes them"
    )
    ;;
  deep)
    # Deep NREM: the heavy lift — signals → memory, synapses → remains.
    templates=(
      "deep work — folding ${sig_count} signals into memory; ${syn_count} synapses being tested, some pruned"
      "deep sleep cycle ${cycle}/${total}: memory at ${mem_count} records, ${rem_count} already let go to remains"
      "the real consolidation — signals collapsing into memory, weak synapses becoming remains"
      "${sig_count} signals, ${syn_count} synapses, ${mus_count} musings — sorting what stays as me from what was only passing"
      "deep: pruning. ${syn_count} synapses examined. what survives here is what I carry tomorrow"
    )
    ;;
  final_light)
    # Final light: winding down, preparing to wake.
    templates=(
      "final light — consolidation nearly done; ${mem_count} memories intact, ${rem_count} pieces released"
      "surfacing slowly. the night's work: ${sig_count} signals processed, ${mem_count} kept as memory"
      "final light before waking — signing my consolidations, letting the rest go to remains"
      "almost awake. cycle ${cycle} of ${total} closing. what I kept: ${mem_count}; what I released: ${rem_count}"
    )
    ;;
esac

narrative="${templates[$((RANDOM % ${#templates[@]}))]}"

# Dispatch DreamPulse so the status bar narrates it (same path as REM).
# Prefix distinguishes consolidation work from poetic imagery.
prefix="🧠"
dispatch Consciousness.DreamPulse \
  consciousness="$cid" impression="$prefix $narrative" >/dev/null

# Also update sleep_summary directly so statusline + wake ritual see
# the consolidation detail (sleep.bluebook's Advance* commands set
# short phase-transition strings; this overrides during the phase).
heki_write upsert "$INFO/consciousness/consciousness.heki" \
  --reason "nrem_branch : overlay consolidation narrative onto sleep_summary so the statusline tells what the body is actually doing during NREM" \
  id="$cid" sleep_summary="$narrative" >/dev/null
