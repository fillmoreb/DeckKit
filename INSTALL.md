# Installing DeckKit

Everything from a fresh Steam Deck with WoW: Forever on it to DeckKit set up. The game side takes a few
minutes; the grip chords need one trip to Desktop Mode. Speech to text and the Deck readings are optional.

## 1. Before you start

- **WoW: Forever on the Deck**, running through Battle.net (Lutris or Steam with Proton both work). How
  I launch it is in [the appendix](#appendix-my-launch-setup).
- **The game's Gamepad UI:** in the game, Options › **Gamepad (Beta)** › **Enable Gamepad UI (Beta)**.
  DeckKit is built around it (the crossbar, its windows, the loot rolls).

## 2. The addons

**CurseForge:** install **DeckKit** with the CurseForge app (pick the WoW: Forever flavor). It installs
every DeckKit addon.

**By hand:** download the latest zip from CurseForge or from
[GitHub releases](https://github.com/fillmoreb/DeckKit/releases), and unzip it into WoW: Forever's
`_forever_/Interface/AddOns` folder. You should end up with `AddOns/DeckKit`, `AddOns/DeckHUD`,
`AddOns/HealPad` and so on, one folder each.

Finding that folder on the Deck (Desktop Mode):
- **Ask Battle.net:** on WoW: Forever's page, the gear next to Play › **Show in Explorer** opens the game
  folder (`World of Warcraft`); `_forever_` is inside it. That's a Windows path inside Wine, so note
  where it lives (often `C:\Program Files (x86)\World of Warcraft`).
- **Then in Dolphin** (the file manager): Wine's `C:` drive is the `drive_c` folder of Battle.net's
  prefix. Press **Ctrl+H** to show hidden folders (the prefix often starts with a dot). Typical places:
  - Lutris: `~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_`
  - Steam (Battle.net added as a non-Steam game, run with Proton):
    `~/.local/share/Steam/steamapps/compatdata/<a number>/pfx/drive_c/Program Files (x86)/World of Warcraft/_forever_`
  - Installed to an SD card: the card is under `/run/media/deck/`.
- No `Interface/AddOns` inside `_forever_` yet? Create both folders.

Every addon is optional except **DeckKit** itself (the core): delete the folders of any you don't want.

## 3. First login: the welcome window

Start the game. The **Welcome to DeckKit** window opens by itself and lists what's left to set up; each
step turns **Done** by itself.

1. **Suggested settings and layout:** press `Ⓐ` on **Apply everything suggested**. It sets a few game
   settings for the Deck (classic chat, auto loot, no button legend, the game's own UI scale), clears the
   game's bindings on F1-F8 (the grips' keys), and places every frame for the small screen. Your Edit Mode
   layout is backed up first (**Screen › Suggested settings › Undo the last layout change** puts it back),
   then the UI reloads and the window comes back.
   If your Edit Mode layout is one of the game's presets, the step says so: copy it to a layout of your
   own in Edit Mode first.
2. **Steam controller layout for the grips:** see [step 4](#4-grip-chords-the-steam-controller-layout).
   It turns Done the first time you hold a grip after that.
3. **Healing macros** (healing classes only): press `Ⓐ` to make the d-pad macros and pick your heal
   macros. To put them on the crossbar: game menu › Macros, pick one, `Ⓧ` Bind to Action Bar.

`Ⓑ` closes the window; double-tap `☰` › Controls › Setup (or `/deckkit setup`) brings it back. Every
setting is in the DeckKit menu: **double-tap `☰`**, or `/deckkit`.

## 4. Grip chords: the Steam controller layout

The back grips (L4 R4 L5 R5) become 30 slots for any action, but only once your WoW: Forever controller
layout makes each grip send two plain keys (one while held, one after 0.4 s). A script does that:

1. In Game Mode, open WoW: Forever's controller settings once (Steam button › Controller settings), so
   Steam has a layout for it. Note the name of the Steam shortcut you start the game from.
2. Switch to **Desktop Mode** (Steam button › Power › Switch to Desktop) and open **Konsole**. Steam's
   on-screen keyboard is **STEAM + X**.
3. Type this, and press Enter:
   ```
   curl -LO https://raw.githubusercontent.com/fillmoreb/DeckKit/main/deck-setup/make-chord-layout.py && python3 make-chord-layout.py --install --stop-steam
   ```
   `--stop-steam` closes Steam for you once you've pressed Enter (Steam rewrites layouts as it exits, so it
   has to be closed; and the on-screen keyboard goes with it, which is why it waits until then). The
   script finds your Forever layout, keeps a backup next to it (`.bak-before-chords`) and changes only
   the four back grips.
   - **"No WoW: Forever controller layout found"**: it looks for a shortcut with "forever" in its name.
     It then lists the layout folders it did find; run it again naming yours, in quotes, e.g.
     `python3 make-chord-layout.py --install --stop-steam --game "battle.net"`.
   - More than one match: it lists them; pick one with `--layout "<path>"`.
   - `--hold-ms 300` makes holds quicker (default 400).
4. Back to Game Mode (the **Return to Gaming Mode** icon on the desktop), start the game, hold a grip
   (the welcome window's step 2 turns Done), and set up slots in **Controls › Grips**.

**Upgrading from DeckKit 1.1 or earlier:** the grips' keys moved; run step 3 again or the grips stop
working. Your slots are kept.

## 5. Speech to text (optional)

[Decktation](https://github.com/silverfoxy/decktation), a plugin for [Decky Loader](https://decky.xyz),
turns what you say into chat. Hold a button combination, talk, and it types it in.

1. Install Decky Loader (its site has the installer), then Decktation from Decky's store or its GitHub
   page. Version 0.3.24 or later.
2. In Decktation, set the binding to **L4 + R4**, and turn on **Advanced settings › Sending › Exact
   binding only**. Without that, every bigger chord that includes L4 + R4 starts dictation too.
3. While you dictate, DeckKit shows a small box mid-screen: **Listening** while you hold L4 + R4 and
   talk, then **Transcribing** until your message appears in chat (**Chat › Dictation** turns it off or
   sets its opacity). DeckKit judges that from your grips and from chat alone, so it can't tell when
   Decktation heard nothing or failed. DeckKitAfterDark's DeckDictation fixes that (step 6).

## 6. DeckKitAfterDark: the Deck's own readings, and dictation you can trust (optional)

[DeckKitAfterDark](https://github.com/fillmoreb/DeckKitAfterDark) is DeckKit's companion suite. Its addons
exchange data with programs running on the Deck. It's a separate project only because that's a gray area
under Blizzard's terms, and you should choose it knowingly. Nothing in it plays for you. What it adds:

- **DeckTelemetry:** the Deck's battery, charging, power, temperatures, fan and load, shown on DeckHUD's
  status bar (Screen › Status bar).
- **DeckDictation:** Decktation tells the game exactly what it's doing. The box shows Listening when
  recording really starts, Transcribing while it works, **Failed** when it heard nothing or went wrong,
  and closes the moment your text is typed.

Its [INSTALL.md](https://github.com/fillmoreb/DeckKitAfterDark/blob/main/INSTALL.md) has the steps.

## Appendix: my launch setup

Not needed to use DeckKit: this is how I run WoW: Forever on my own Deck, in case it helps.

- Battle.net runs in a **Lutris** Wine prefix. `deck-setup/wowforever.bat` lives at `C:\wowforever.bat`
  in that prefix: it starts Battle.net, waits 8 s, then sends `launch WoWF` every 2 s until `Wow.exe`
  runs (Battle.net ignores it until it has logged in). A Lutris game runs it with
  `cmd.exe /c C:\\wowforever.bat`.
- `deck-setup/addshortcut.py` adds a **WoW Forever** Steam shortcut for that Lutris game, with the art in
  `deck-setup/wowforever-art/`. Run it on the Deck as `deck`, with Steam closed (Steam rewrites
  `shortcuts.vdf` when it exits).
