#!/bin/bash
# mint_musing.sh — gathers prompt context and dispatches the
# MintMusing chain. The :mint_idea named :llm adapter (declared
# in mind/musing_mint/musing_mint.hecksagon) fires after
# MusingMint.MintMusing dispatches, calls Claude through the
# Phase 2 dispatcher, and chains the response back as
# MusingMint.MintMusing(idea: <response>) via response_into.
#
# i75 retirement — the `echo "$prompt" | claude -p` line is gone.
# Provider precedence (claude / local / off) is now : runtime's
# ClaudeProvider for "claude", :test fixture provider when
# HECKS_LLM_PROVIDER=test, "off" short-circuits below before
# any dispatch.
#
# [antibody-exempt: i37 Phase B sweep — replaces inline python3 -c with
#  native hecks-life heki subcommands per PR #272; retires when shell
#  wrapper ports to .bluebook shebang form (tracked in
#  terminal_capability_wiring plan).]

DIR="$(dirname "$0")"
HECKS="${HECKS_BIN:-$DIR/../rust/target/release/hecks-life}"
INFO="${HECKS_INFO:-$DIR/information}"
AGG="${HECKS_AGG:-$DIR/aggregates}"

# Read current provider; default to "claude" if unset
provider=$($HECKS heki latest-field "$INFO/claude_assist.heki" provider 2>/dev/null)
[ -z "$provider" ] && provider="claude"

[ "$provider" = "off" ] && exit 0

# Tell the status bar we're minting — it animates the lightbulb
# until this flag goes away. Cleared on exit no matter what.
MINTING_FLAG="/tmp/miette_minting"
touch "$MINTING_FLAG"
trap "rm -f $MINTING_FLAG" EXIT

# ── Gather context (same shape the retired prompt used) ────────────
# Each variable becomes the value of one MusingMint state field via
# the RecordContext dispatch below. The :mint_idea adapter's prompt
# template substitutes them via {{placeholders}}.

# Recent musings (avoid repetition). Last 10 by insertion order.
recent=$($HECKS heki list "$INFO/musing.heki" --format json 2>/dev/null \
  | jq -r '[.[] | (.idea // "") | sub("^\\s+"; "") | sub("\\s+$"; "") | select(. != "")]
           | .[-10:] | .[] | "  - " + .[0:120]')

# Recent commits (current focus)
commits=$(cd "$DIR/.." && git log --oneline -10 2>/dev/null | sed 's/^/  /')

# Nursery domains — random sample of 12.
nursery_sample=$(ls "$DIR/nursery" 2>/dev/null | shuf -n 12 2>/dev/null | sed 's/^/  - /' | sed 's/_/ /g')
[ -z "$nursery_sample" ] && nursery_sample=$(ls "$DIR/nursery" 2>/dev/null | sort -R | head -12 | sed 's/^/  - /' | sed 's/_/ /g')

# Conversations since last wake.
last_wake=$($HECKS heki latest-field "$INFO/consciousness.heki" last_wake_at 2>/dev/null)
conversations=$($HECKS heki list "$INFO/conversation.heki" --format json 2>/dev/null \
  | jq -r --arg wake "${last_wake:-}" '
      [ .[]
        | select((.type // "") == "turn")
        | select(($wake | length) == 0 or ((.updated_at // "") >= $wake))
      ]
      | sort_by(.updated_at // "")
      | .[-20:]
      | .[]
      | "  " + (.speaker // "") + ": " + ((.said // "") | gsub("\n"; " ") | .[0:140])')

# Body-state snapshot
hb_beats=$($HECKS heki latest-field "$INFO/heartbeat.heki" beats 2>/dev/null || true)
hb_fat=$($HECKS heki latest-field "$INFO/heartbeat.heki" fatigue_state 2>/dev/null || true)
mood=$($HECKS heki latest-field "$INFO/mood.heki" current_state 2>/dev/null || true)
co_state=$($HECKS heki latest-field "$INFO/consciousness.heki" state 2>/dev/null || true)
co_stage=$($HECKS heki latest-field "$INFO/consciousness.heki" sleep_stage 2>/dev/null || true)
last_obs=$($HECKS heki latest "$INFO/lucid_dream.heki" 2>/dev/null \
  | jq -r '(.observations // []) | if length == 0 then "" else .[-1] end' 2>/dev/null)

state_snapshot="  beats: ${hb_beats:0:60} (fatigue: ${hb_fat:0:60})
  mood: ${mood:0:60}
  consciousness: ${co_state:0:60} (stage: ${co_stage:0:60})"
if [ -n "$last_obs" ] && [ "$last_obs" != "null" ]; then
  state_snapshot="$state_snapshot
  last lucid observation: ${last_obs:0:80}"
fi

# Test hook: --dump-context echoes what would be stamped and exits.
if [ "$1" = "--dump-context" ]; then
  rm -f "$MINTING_FLAG"
  echo "=== recent_musings_summary ==="
  echo "${recent:-  (none)}"
  echo "=== recent_commits ==="
  echo "${commits:-  (none)}"
  echo "=== nursery_sample ==="
  echo "${nursery_sample:-  (empty)}"
  echo "=== conversations_summary ==="
  echo "${conversations:-  (none since last wake)}"
  echo "=== state_snapshot ==="
  echo "${state_snapshot:-  (unknown)}"
  exit 0
fi

# ── Dispatch RecordContext, then trigger the MintMusing chain ──────
# RecordContext stamps the five context fields onto the MusingMint
# singleton (name="musing_mint"). MintMusing is the chain trigger ;
# the :mint_idea adapter fires post-dispatch, substitutes the
# prompt template's {{placeholders}} from the just-stamped state,
# calls Claude, and chains MintMusing(idea: <response>) back via
# response_into.

$HECKS "$AGG" MusingMint.RecordContext name=musing_mint \
  recent_musings_summary="${recent:-  (none)}" \
  recent_commits="${commits:-  (none)}" \
  conversations_summary="${conversations:-  (none since last wake)}" \
  nursery_sample="${nursery_sample:-  (empty)}" \
  state_snapshot="${state_snapshot:-  (unknown)}" \
  >/dev/null 2>&1

# Top-level MintMusing dispatch fires the resolver. The cascade
# from :mint_idea lands the real idea via response_into.
$HECKS "$AGG" MusingMint.MintMusing name=musing_mint source="ClaudeAssist:$provider" 2>/dev/null

# Read back the minted idea (last_minted is the chain's resting
# place). Append to musing.heki only if a real idea landed —
# the LLM may have said "skip", in which case the chain still
# fired but the response was empty / "skip" literal and the
# musing pool stays clean.
idea=$($HECKS heki latest-field "$INFO/musing_mint.heki" last_minted 2>/dev/null)
idea=$(echo "$idea" | head -1 | sed 's/^["'\'']//;s/["'\'']$//' | cut -c1-200)

if [ -z "$idea" ] || [ "$idea" = "skip" ] || [ "$idea" = "Skip" ]; then
  exit 0
fi

# Append to musing.heki — surface_musing reads :conceived=false rows.
$HECKS heki append "$INFO/musing.heki" \
  --reason "mint_musing : record a fresh idea Claude curated from the awake corpus" \
  idea="$idea" \
  conceived=false \
  conceived_as=claude_minted \
  status=imagined \
  thinking_source="ClaudeAssist:$provider" \
  feeling_source=curated:awake >/dev/null 2>&1

echo "$(date -u +%FT%TZ) minted via $provider: $idea"
