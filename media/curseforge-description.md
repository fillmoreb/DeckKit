# DeckKit

DeckKit is a suite of addons for playing **WoW: Forever** with a controller, built on and for the **Steam Deck**. Everything works from the gamepad alone, and every setting lives in one controller-driven menu.

**Requires:** WoW: Forever. Made for the Steam Deck with the game's Gamepad UI. Other controllers should work too, but the Deck is what it's tested on. **Optional:** Decktation (a Decky Loader plugin) for voice chat.

## Early days: try it while I build it

DeckKit isn't ready for prime time yet. It's what I play with every day on my own Deck, and it changes as I go: features get added and polished whenever I run into something I need. You're welcome to try it while it's in development. Expect rough edges, settings that move around between versions, and the occasional (inevitable) bug. I'm always glad to hear constructive feedback and suggestions, in the comments here or as an issue on GitHub.

## The DeckKit menu

Press **`☰` Menu twice quickly**, or type `/deckkit`, to open one settings window for everything. It's organized by topic: **Controls, Screen, Map & travel, Healing, Tools** (`L1` / `R1`). `✚` moves, `Ⓐ` toggles or runs, `Ⓑ` closes, and the footer always shows what each button does. Button prompts use the game's own controller icons.

## Grip chords

The Deck's four back grip buttons (`L4` `R4` `L5` `R5`) become **30 slots**: each grip alone, any two, three or all four together, each **pressed** or **held**. Put anything in a slot from **Controls › Grips**: a peek, a waypoint, your quest item, any spell or action bar button. Slots run in secure code, so **spells cast in combat**. Pictures of the grips show which slot is which.

Chords need DeckKit's Steam controller layout for WoW: Forever, which makes each grip send two plain keys (one while held, one after a short hold). Setup instructions are on GitHub (link below).

## What's included

**HealPad** – Healing with a controller. The d-pad (`✚`) moves a yellow cursor over your party or raid frames and makes that player your **focus**; your heal macros cast on them. HealPad makes those macros from your spellbook (heals, cures, resurrection on a dead focus, and your buffs folded into one-button sequences). **Practice party** and **practice raid** frames, laid out exactly like your real ones, let you try it solo.

**QuestPad** – A big button for the quest item you need right now: the quest whose **actual area** you're standing in, or the quest your target belongs to. Motivate those lazy peons with ease.

**MapDeck** – Hold its grip slot to see the map full-screen, even in combat, and keep running while you look. It shows you, your party or raid (in class colors), quest markers, waypoints, flight masters, the spot a guard pointed you to, and your spirit healer when you're dead.

**ChatDeck** – Hold its grip slot to read chat full-screen in a large font, and keep running while you read.

**WayPad** – Waypoints without a keyboard. Dial in coordinates with the d-pad (`✚`), then follow a floating arrow. Waypoints show on the map and minimap, and a list lets you pick, edit or remove them. Supports `/way 45.2 62.8`. With a TomTom-compatible waypoint addon installed, WayPad can hand waypoints to it instead.

**DisenchantDeck** – A controller list of everything in your bags you can disenchant. It opens by itself when you pick Disenchant. `Ⓐ` disenchants, `Ⓨ` hides items you want to keep.

**DeckAngler** – Laid-back controller fishing, built so you don't even have to watch the screen. With a pole equipped, `Ⓧ` **casts**; when you hear the splash, `Ⓧ` reels it in. Everything else is by ear, too: a **chime** tells you when a fish got away, and a gentle **sound reminder** nudges you when you haven't cast in a while (you pick the timing and the sound). A tally keeps count of what you've caught this session.

**DeckHUD** – Interface tweaks for a handheld screen, each one switchable in the menu:
- a **status bar** across the top of the screen: clock, FPS, latency, gold, bag space, durability and XP (with an XP line in place of Blizzard's bar), and with the optional **DeckTelemetry** from DeckKitAfterDark, the Steam Deck's battery, temperature, power and fan. You pick what goes where
- a **square minimap** in the top-right corner, with the zone name on top and a choice of borders
- a **thin chat frame** tucked into the bottom-left corner
- one-press Edit Mode layouts that back up your layout first: a suggested layout, **party frames lined up** under your frame and your target's, **raid frames** tucked into the top-left corner

**DeckSundries** – Small extras. **Wand shoot:** with a wand equipped and an enemy targeted, `Ⓧ` fires your wand. **Friends reply:** in the Social window's friends list, `Ⓨ` on a friend makes them your reply target, so your next `/r` (or a dictated "reply …") whispers them.

**MenuReload** – Adds a Reload UI button to the game menu.

**DeckKit** (the core) – Shared controller input, windows and menu for all of the above, and the grip chords.

## Voice chat with Decktation (optional)

DeckKit doesn't turn speech into text itself. For voice chat, install **Decktation** (0.3.24 or later), a separate plugin for **Decky Loader**: hold a button combination, talk, and it types what you said into chat. Set its binding to `L4` + `R4` and turn on its **Exact binding only** setting, so your bigger grip chords stay free. DeckKit then shows **Listening** and **Transcribing** on screen while you dictate. Setup steps are on GitHub (link below).

## Setup

Install, then open the menu (`☰` twice). Controls › Grips shows which grip does what; your existing grip bindings become the first slots. For healing, see Healing › HealPad.

## Artificial Intelligence?

AI did the typing. I did the Stack Overflow searching. Old habits. Seriously, of course AI helped. A lot. I still got to do all the testing on a flesh and blood Steam Deck, though.

## Credits and license

MIT License. Controller input is adapted from **BagPad** (MIT, © 2026 Chris); the shared button overrides, wand shoot and the controller icon list are adapted from **Improved Forever** (MIT, © 2026 markg).

---

Source, issues, setup and changelog: https://github.com/fillmoreb/DeckKit
