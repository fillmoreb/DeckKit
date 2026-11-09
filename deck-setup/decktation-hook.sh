#!/bin/sh
# Decktation status hook -> DeckKit (WoW: Forever on the Steam Deck).
# Decktation (with patches/decktation/status-hooks.patch) runs this as root with DECKTATION_EVENT
# set; it presses the matching DeckKit signal key in the game, which runs on Xwayland :1:
#   record_start -> Insert   record_stop -> Home   transcription_done -> End   error -> Delete
# DeckKit binds those keys to its dictation indicator (Key Bindings > DeckKit).
# Install: copy to /home/deck/.local/bin/deckkit-decktation-hook, chmod +x, and set Decktation's
# "statusHookCommand" to that path.
case "$DECKTATION_EVENT" in
    record_start) key=Insert ;;
    record_stop) key=Home ;;
    transcription_done) key=End ;;
    error) key=Delete ;;
    *) exit 0 ;;
esac
exec runuser -u deck -- env DISPLAY=:1 xdotool key "$key"
