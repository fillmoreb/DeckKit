#!/bin/bash
# Copy addons from addons/ onto the Steam Deck. Usage: ./deploy.sh WayPad MapDeck ...   (no args: all)
# Syntax-checks every .lua first. WoW needs a /reload afterwards.
set -euo pipefail
cd "$(dirname "$0")/addons"
# Machine-specific settings (DECK, ADDONS) live in deploy.local, which git ignores. See deploy.local.example.
CONF="$(cd .. && pwd)/deploy.local"
[ -f "$CONF" ] || { echo "missing deploy.local: copy deploy.local.example and fill it in" >&2; exit 1; }
. "$CONF"
: "${DECK:?set DECK in deploy.local}" "${ADDONS:?set ADDONS in deploy.local}"
[ $# -eq 0 ] && set -- */
names=()
for a in "$@"; do a=${a%/}; [ -d "$a" ] || { echo "no addon $a" >&2; exit 1; }; names+=("$a"); done
if command -v luac >/dev/null; then
  find "${names[@]}" -name '*.lua' -print0 | xargs -0 -n1 luac -p
fi
COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -cf - "${names[@]}" |
  ssh "$DECK" "cd /tmp && sudo -u deck bash -c 'cd \"$ADDONS\" && tar xf - && find . -maxdepth 3 -name \"._*\" -delete'"
echo "deployed: ${names[*]}  (/reload in WoW)"
