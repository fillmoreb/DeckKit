#!/bin/bash
# DeckKit's offline scenarios (tests/test_*.lua), run in AddonTools' harness: the core's real files against a
# stand-in client. Each scenario gets a fresh client. ADDONTOOLS points at the AddonTools checkout (default: beside
# this repo). Pass scenario files to run only those.
#   tests/run.sh [tests/test_grip_slots.lua ...]
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
tools="${ADDONTOOLS:-$here/../AddonTools}"
[[ -x "$tools/harness/harness.sh" ]] || { echo "tests: no harness at $tools/harness (set ADDONTOOLS)" >&2; exit 2; }
if (($#)); then scenarios=("$@"); else scenarios=("$here"/tests/test_*.lua); fi
# The addons the scenarios load, in dependency order.
addons=(DeckKit PadTouchGrid AuctionPad MailPad)
args=()
for a in "${addons[@]}"; do args+=(--addon "$here/addons/$a"); done
exec "$tools/harness/harness.sh" "${args[@]}" "${scenarios[@]}"
