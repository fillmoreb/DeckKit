#!/bin/sh
# Decktation status hook -> DeckKit (WoW: Forever on the Steam Deck).
# Decktation runs this with DECKTATION_EVENT set (0.3.24+: as the desktop user; the older
# patches/decktation/status-hooks.patch: as root). It presses the matching DeckKit signal key in the
# game, which runs on Xwayland :1:
#   record_start -> Insert   record_stop -> Home   transcription_done / record_abort -> End
#   error -> Delete
# DeckKit binds those keys to its dictation indicator (Key Bindings > DeckKit).
# Install: copy to /home/deck/.local/bin/deckkit-decktation-hook, chmod +x, and set Decktation's
# "statusHookCommand" to that path.
case "$DECKTATION_EVENT" in
    record_start) key=Insert ;;
    record_stop) key=Home ;;
    transcription_done|record_abort) key=End ;;
    error) key=Delete ;;
    *) exit 0 ;;
esac
if [ "$(id -u)" = 0 ]; then
    exec runuser -u deck -- env DISPLAY=:1 xdotool key "$key"
fi
exec env DISPLAY=:1 xdotool key "$key"
