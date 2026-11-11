#!/bin/bash
# Deploy addons from addons/ onto the Steam Deck with deckctl (from ~/Projects/AddonTools): syntax
# check, apicheck, swap each addon folder in whole, reload, and verify.
# Usage: ./deploy.sh [--no-reload] WayPad MapDeck ...   (no names: all)
#
# A good deploy ends "addons loaded N/N, 0 Lua errors, 0 blocked". Anything else exits 1: look at it
# (deckctl errors / deckctl blocked). DeckDev itself is deployed from AddonTools (./deploy.sh there).
set -euo pipefail
cd "$(dirname "$0")"
DECKCTL="${ADDONTOOLS:-$HOME/Projects/AddonTools}/deck/deckctl"
[ -x "$DECKCTL" ] || { echo "deckctl not found at $DECKCTL (set ADDONTOOLS)" >&2; exit 1; }
# Machine-specific settings (DECK, ADDONS) in deploy.local, which git ignores; see deploy.local.example.
[ -f deploy.local ] && export DECKCTL_CONF="$PWD/deploy.local"
args=(); names=()
for a in "$@"; do
  case "$a" in
    --*) args+=("$a") ;;
    *) a=${a%/}; a=${a#addons/}; [ -d "addons/$a" ] || { echo "no addon $a" >&2; exit 1; }; names+=("addons/$a") ;;
  esac
done
[ ${#names[@]} -gt 0 ] || names=(addons/*/)
exec "$DECKCTL" deploy ${args[@]+"${args[@]}"} "${names[@]%/}"
