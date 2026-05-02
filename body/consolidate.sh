#!/bin/bash
# consolidate.sh — periodic memory consolidation for Miette's organs.
#
# Runs every ~60 ticks (see mindstream.sh). Three passes:
#
#   1. SIGNAL → MEMORY
#      Cold signals (access_count <= 3 AND age > 60s) get promoted into
#      long-term memory (Memory.StoreMemory via heki append) and then
#      archived in place (Signal.ArchiveSignal). The short-term working
#      set thins, but nothing is lost.
#
#   2. SYNAPSE → REMAINS
#      Synapses whose strength fell below 0.1 are composted
#      (Synapse.Compost) and a Remains row is written
#      (Remains.RecordRemains via heki append) capturing last strength
#      and firing count so the body remembers what once mattered.
#
#   3. MUSING → MUSING_ARCHIVE
#      Live musings are grouped by concept (thinking_source first, then
#      feeling_source). If a concept has more than 3 live musings, the
#      oldest is archived via Entry.Archive — idea, source, concept,
#      reason ("duplicate_concept"), and timestamp — so the active pool
#      stays varied.
#
# Environment overrides (smoke tests):
#   HECKS_INFO  — alternate information directory (default: ./information)
#   HECKS_AGG   — alternate aggregates directory (default: ./aggregates)
#   HECKS_BIN   — alternate hecks-life binary
#
# Dispatch vs heki append — same pattern as pulse_organs.sh: commands
# with reference_to use dispatch with an id kwarg; "Create"-style
# commands without a reference (StoreMemory, RecordRemains, Archive)
# would singleton-upsert if dispatched, so we use `heki append` to
# preserve multi-record semantics.
#
# [antibody-exempt: i37 Phase B sweep — replaces inline python3 -c +
#  python3 heredocs with native hecks-life heki subcommands + jq per
#  PR #272; retires when shell wrapper ports to .bluebook shebang form
#  (tracked in terminal_capability_wiring plan).]

set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
INFO="${HECKS_INFO:-$DIR/information}"
AGG="${HECKS_AGG:-$DIR/aggregates}"
HECKS="${HECKS_BIN:-$DIR/../rust/target/release/hecks-life}"

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

now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

promoted_signals=0
composted_synapses=0
archived_musings=0

# ── 1. SIGNAL → MEMORY ───────────────────────────────────────────────
# Read signal.heki, pick rows with access_count <= 3 AND age > 60s AND
# kind != archived. For each: append to store.heki (Memory.StoreMemory
# schema), then dispatch Signal.ArchiveSignal.

if [ -f "$INFO/signal/signal.heki" ]; then
  PROMOTE_PLAN=$("$HECKS" heki list "$INFO/signal/signal.heki" --format json 2>/dev/null \
    | jq -r --arg now "$now" '
        def iso_to_epoch:
          . as $s | ($s | fromdateiso8601);
        ($now | iso_to_epoch) as $n
        | .[]
        | select(.kind != "archived")
        | select((.access_count // 0) <= 3)
        | select((.created_at // "") | length > 0)
        | select(($n - (.created_at | iso_to_epoch)) > 60)
        | [.id,
           ((.kind // "") | gsub("\\|"; " ")),
           ((.payload // "") | gsub("\\|"; " ")),
           (.created_at // "")]
        | @tsv' 2>/dev/null \
    | awk -F'\t' '{ printf "%s|%s|%s|%s\n", $1, $2, $3, $4 }')

  while IFS='|' read -r sid kind payload created_at; do
    [ -z "$sid" ] && continue
    heki_write append "$INFO/store/store.heki" \
      --reason "consolidate : promote a hot signal into long-term memory" \
      kind="$kind" payload="$payload" source=signal \
      created_at="$created_at" >/dev/null
    dispatch Signal.ArchiveSignal signal="$sid" >/dev/null
    promoted_signals=$((promoted_signals + 1))
  done <<<"$PROMOTE_PLAN"
fi

# ── 2. SYNAPSE → REMAINS ─────────────────────────────────────────────
# Composting also happens in pulse_organs.sh on decay, but a periodic
# sweep catches any alive synapse that slipped below 0.1 without being
# caught (e.g. if decay was skipped).

if [ -f "$INFO/synapse/synapse.heki" ]; then
  COMPOST_PLAN=$("$HECKS" heki list "$INFO/synapse/synapse.heki" \
      --where state=alive --format json 2>/dev/null \
    | jq -r '.[]
             | select((.strength // 0) < 0.1)
             | [.id,
                (.strength // 0),
                (.firings // 0),
                ((.from // "") | gsub("\\|"; " "))]
             | @tsv' 2>/dev/null \
    | awk -F'\t' '{ printf "%s|%s|%s|%s\n", $1, $2, $3, $4 }')

  while IFS='|' read -r sid strength firings from_topic; do
    [ -z "$sid" ] && continue
    dispatch Synapse.Compost synapse="$sid" >/dev/null
    heki_write append "$INFO/remains/remains.heki" \
      --reason "consolidate : capture composted synapse's dying values for the remains corpus" \
      from_synapse="$from_topic" \
      strength_at_death="$strength" \
      firings="$firings" \
      died_at="$now" >/dev/null
    composted_synapses=$((composted_synapses + 1))
  done <<<"$COMPOST_PLAN"
fi

# ── 3. MUSING → MUSING_ARCHIVE ───────────────────────────────────────
# Group live musings (conceived != true AND status != archived) by
# concept (thinking_source, else feeling_source, else source). When a
# concept has more than 3 live musings, archive the oldest by
# created_at. Archive via heki append to musing_archive.heki; mark the
# original with `heki mark --where id=... --set status=archived`.

if [ -f "$INFO/musing/musing.heki" ]; then
  ARCHIVE_PLAN=$("$HECKS" heki list "$INFO/musing/musing.heki" --format json 2>/dev/null \
    | jq -r '
        # Pull concept from thinking_source → feeling_source → source.
        def concept_of:
          ((.thinking_source // .feeling_source // .source // "") | tostring
            | sub("^\\s+"; "") | sub("\\s+$"; ""));
        # Filter live (not conceived=true and not status=archived) and
        # having a concept.
        [ .[]
          | select(.conceived != true)
          | select((.status // "") != "archived")
          | . + {"_concept": concept_of}
          | select(._concept != "")
        ]
        # Group by concept, pick the oldest when bucket > 3.
        | group_by(._concept)
        | map(select(length > 3) | sort_by(.created_at // "") | .[0])
        | .[]
        | [.id,
           ((.idea // "") | gsub("\\|"; " ")),
           ((.source // "mindstream") | gsub("\\|"; " ")),
           (._concept | gsub("\\|"; " "))]
        | @tsv' 2>/dev/null \
    | awk -F'\t' '{ printf "%s|%s|%s|%s\n", $1, $2, $3, $4 }')

  while IFS='|' read -r mid idea source concept; do
    [ -z "$mid" ] && continue
    heki_write append "$INFO/musing_archive/musing_archive.heki" \
      --reason "consolidate : archive duplicate-concept musing — keep the older, retire the rest" \
      idea="$idea" source="$source" concept="$concept" \
      archived_reason="duplicate_concept" archived_at="$now" >/dev/null
    # Mark the original musing archived so it's not re-counted next sweep.
    heki_write mark "$INFO/musing/musing.heki" --where "id=$mid" \
      --set status=archived \
      --reason "consolidate : flag the original musing archived so duplicate-concept sweep doesn't re-count it" >/dev/null
    archived_musings=$((archived_musings + 1))
  done <<<"$ARCHIVE_PLAN"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo "consolidate: promoted=$promoted_signals composted=$composted_synapses archived=$archived_musings"
exit 0
