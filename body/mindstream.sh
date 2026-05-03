#!/bin/bash
# mindstream.sh — retired. The 1Hz body-cycle scheduler now lives in
# body/cycles/body_cycle.bluebook (a process_manager PM), driven by
# `hecks-life run-loop`. This wrapper survives only as the boot-time
# alias the daemon registry still calls ; it forwards to the Rust
# substrate that replaced the legacy 310-line while-true loop.
#
# [antibody-exempt: ~/Projects/miette/body/mindstream.sh — transitional
# alias preserving the boot daemon-registry path. The cadence + per-tick
# routing now live in body/cycles/body_cycle.bluebook (PM) and the Rust
# `hecks-life run-loop` driver. This shell retires entirely once the
# daemon registry in runtime/boot/boot.bluebook moves to spawning
# `hecks-life run-loop` directly without the alias.]
#
# The PM observes BodyPulse and dispatches per-state :
#   - attentive          → Tick.MindstreamTick
#   - sleeping_*         → Consciousness.ElapsePhase
# Sibling PMs (Pulse, Consolidation, Mind) subscribe to BodyPulse
# directly ; the legacy fan-out to pulse_organs.sh / nrem_branch.sh
# / rem_branch.sh / awareness-snapshot lives in their bluebooks.
#
# i75 closure : the four runtime gaps the legacy shell named
# (cadence, sleep-quench, with_attrs, capability autoload) are
# either closed (cadence via run-loop ; PM autoload via bluebook
# tree walk) or carried forward as inbox items on the relevant
# sibling PRs.

DIR="$(cd "$(dirname "$0")" && pwd)"
HECKS="${HECKS_BIN:-}"
[ -z "$HECKS" ] && [ -x "$DIR/../../hecks/rust/target/release/hecks-life" ] && \
  HECKS="$(cd "$DIR/../../hecks/rust/target/release" && pwd)/hecks-life"
[ -z "$HECKS" ] && HECKS="$DIR/../../rust/target/release/hecks-life"

REPO_ROOT="${HECKS_REPO_ROOT:-$DIR/..}"

exec "$HECKS" run-loop "$REPO_ROOT" \
  --every 1s \
  --emit BodyPulse:Consciousness:consciousness \
  --bootstrap-if Consciousness.state=attentive:WokenUp:Consciousness:consciousness
