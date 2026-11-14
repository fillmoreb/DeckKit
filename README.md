<p align="center"><img src="media/deckkit-logo-400.png" width="200" alt="DeckKit logo"></p>

# DeckKit

Controller-first addons for **WoW: Forever** on the Steam Deck, plus the Deck-side setup that goes with them.

**Installing:** [INSTALL.md](INSTALL.md) walks through everything, from the addons to the Steam controller
layout for the grips and speech to text.

> **Built with AI.** DeckKit is largely developed with an AI coding assistant
> ([Claude Code](https://claude.com/claude-code)). Most of the Lua here was written by Claude
> from my descriptions, then reviewed and tested in-game by me on a Steam Deck. Expect the kind of
> rough edges that come with that, and please report anything broken. Notes for the assistant
> live in [`CLAUDE.md`](CLAUDE.md), and you're welcome to use them if you work on DeckKit with AI too.

> **Early days.** DeckKit isn't ready for prime time yet: it grows out of actually playing on the
> Deck, and features get added and polished whenever I run into something I need. You're welcome
> to try it while it's in development; expect rough edges, settings that move around between
> versions, and the occasional (inevitable) bug. Constructive feedback and suggestions are always welcome in the
> [issues](https://github.com/fillmoreb/DeckKit/issues).

## Addons (`addons/`)

| Addon | What it does |
|---|---|
| **DeckKit** | The shared core: controller input, windows, shared button overrides (X is shared by wand shoot and fishing), the **DeckKit menu** with every module's settings by topic (double-tap ☰ Menu, or `/deckkit`), **grip chords** (the back grips alone or together, pressed or held: 30 slots for any action, spells included, see below) |
| **HealPad** | Healing on a controller: the d-pad moves a cursor over party/raid frames and sets your focus; makes focus heal macros from your spellbook (buffs folded into one-button sequences); practice party and raid frames laid out like your real ones (`/deckkit healpad`) |
| **QuestPad** | A big button for the quest item you need: the quest whose real area you're in, or your target's quest (`/deckkit questpad`) |
| **WayPad** | Waypoints dialed in with the d-pad, floating arrow, map + minimap pins, `/way`. With a TomTom-compatible waypoint addon installed, it hands waypoints to that instead (one system at a time) |
| **DisenchantDeck** | List of disenchantable bag items, opened when you pick Disenchant: A disenchants, Y hides, LB/RB shows hidden (`/dd`) |
| **ChatDeck** | Hold a grip slot to read chat full-screen; you can keep moving while it's up |
| **MapDeck** | Hold a grip slot for a full-screen map (works in combat), and you can keep moving while it's up; shows party/raid, quest markers, waypoints, flight masters, a guard's directions and your spirit healer |
| **DeckAngler** | Controller fishing: with a pole equipped X casts; per-session catch tally, missed-catch chime, idle reminder (`/deckkit fish`) |
| **DeckHUD** | Interface tweaks: a status bar across the top (clock, FPS, latency, gold, bags, durability, an XP line in place of Blizzard's; the Deck's battery, temperature, power and fan with DeckKitAfterDark's DeckTelemetry; slots picked in Screen › Status bar), square minimap in the top-right corner (zone name on top, a choice of borders), thin chat frame tucked into the bottom-left; Edit Mode layouts with backups: suggested layout, party frames lined up under your frame and the target's, raid frames in the top-left corner (`/deckkit layout`) |
| **DeckSundries** | Small extras. Wand shoot: Square fires your wand at an enemy instead of swinging (`/deckkit wandshoot`). Friends reply: Y on a friend in the friends list makes them your reply target, so `/r` (or dictating "reply ...") whispers them |
| **MenuReload** | Reload UI button in the game menu, under AddOns |

Everything except MenuReload needs **DeckKit** installed too. Keep SavedVariables and binding names unchanged when refactoring so existing data and binds carry over.

Deploy to the Deck: copy `deploy.local.example` to `deploy.local` and fill in your Deck's SSH target and AddOns path,
then `./deploy.sh WayPad MapDeck` (or no arguments for all). Deploying uses `deckctl` from the
AddonTools dev suite (~/Projects/AddonTools, or set `ADDONTOOLS`), which reloads the game and checks
that every addon loaded without errors.

## Grip chords: Steam setup

Grip chords need your WoW: Forever controller layout to make each back grip send two plain keys
(L4 F1/F5, R4 F2/F6, L5 F3/F7, R5 F4/F8: one while held, one after 0.4 s; see [Keys](#keys)). Everything else
(which grip or chord does what) is set in the game, in the DeckKit menu under **Controls › Grips**.
Your existing grip bindings become the first slots.

A script on the Deck sets that up (`deck-setup/make-chord-layout.py --install --stop-steam`): the steps
are in [INSTALL.md, step 4](INSTALL.md#4-grip-chords-the-steam-controller-layout).

**Upgrading from DeckKit 1.1 or earlier:** the grips moved from F8-F11 / F1-F4 to F1-F4 / F5-F8. Run
the script again (it rewrites the four grips in place), or the grips won't work.

**Cheat sheet:** a small list on screen of what your grips do (each chord's glyph and its action).
Turn it on and pick its spot in **Controls › Cheat sheet**, and untick any slot you don't need
reminding of. It can also go on a chord slot ("Cheat sheet"), or `/deckkit sheet`.

## Speech to text with Decktation (optional)

DeckKit doesn't turn speech into text itself. For that there's
[Decktation](https://github.com/silverfoxy/decktation), a separate plugin for
[Decky Loader](https://decky.xyz): hold a button combination, talk, and it types what you said into
chat. DeckKit works alongside it:

1. Install Decky Loader, then Decktation (see its page). Version 0.3.24 or later.
2. In Decktation, set the binding to **L4 + R4**, and turn on **Advanced settings › Sending › Exact
   binding only**. Without that, every bigger chord that includes L4 + R4 starts dictation too.
3. While you dictate, DeckKit shows a small box in the middle of the screen, so you know where things
   stand without watching chat:
   - **Listening** (a microphone) while you hold L4 + R4 and talk;
   - **Transcribing** (a speech bubble) once you let go, until your message appears in chat.

   Turn it off or make it more see-through in **Chat › Dictation**.

**DeckKit can only guess.** It can't see Decktation: it knows you're holding L4 + R4, and it sees your
message turn up in chat. If Decktation didn't hear anything, or failed, DeckKit can't tell. It keeps
showing Transcribing until it gives up after 12 seconds.

**For the real thing, add DeckKitAfterDark.** Its **DeckDictation** addon uses Decktation's status
hook to pass along exactly what Decktation is doing, the moment it happens. Listening appears when
recording really starts, Transcribing when Decktation starts working on it, **Failed** when it heard
nothing or something went wrong, and the box closes as soon as your text is typed.
[DeckKitAfterDark](https://github.com/fillmoreb/DeckKitAfterDark) is our companion suite of addons that
exchange data with programs running on the Deck. It's a separate project only because that's a gray area
under Blizzard's terms, and you should choose it knowingly. Its
[INSTALL.md](https://github.com/fillmoreb/DeckKitAfterDark/blob/main/INSTALL.md) has the steps.

For addon authors: anything that knows Decktation's state can drive the box with
`DeckKit.Dictation.SetState("recording" | "transcribing" | "done" | "error")`. That's all DeckDictation does.

## Keys

The keys DeckKit's setup uses. Keyboard players: these are taken while DeckKit is loaded.

| Key | Sent by | Does |
|---|---|---|
| F1 / F2 / F3 / F4 | the Steam layout, while grip L4 / R4 / L5 / R5 is held | grip chords (`DeckKit/Core.lua` `ns.GRIPS`) |
| F5 / F6 / F7 / F8 | the Steam layout, once L4 / R4 / L5 / R5 has been held 0.4 s | grip chord holds |
| F9-F12 | | not used by DeckKit, free for other addons |

Nothing else: Decktation's own push-to-talk reads the controller directly.

F1-F5 lose their default bindings (target yourself / party members 1-4) while DeckKit is loaded;
on a pad those come from the gamepad UI anyway. Reload UI (`DECKKIT_RELOAD`) has no key; put it on a
grip slot or bind it in Key Bindings.

## Suggested WoW settings

These suit playing on the Deck. Each is a toggle on the **Suggested settings** page of the DeckKit menu
(double-tap ☰); switching one off restores what you had. **Apply everything suggested** sets them all in one go
and applies the suggested Edit Mode layout (unit, party, focus and raid frames, buffs, the compact crossbar),
backing up your layout first (Undo the last layout change puts it back), then reloads.

| Setting | Suggested | Why |
|---|---|---|
| Chat style | Classic | Enter sends a message *and* closes the input box, including dictated messages |
| Auto loot | On | Opening a corpse takes everything; no picking items one by one on a controller |
| Controller button legend | Hidden | The always-on list of what each button does, once you know them |
| UI scale | The game's own | The suggested layout's positions are measured at it |
| Key bindings on F1-F8 | Cleared | The grips send those keys; by default F1-F5 target you and your party |

The suggested layout includes the crossbar's *Compact* option (only the bar you're using shows). DeckHUD
can also move the crossbar on its own: `/deckkit layout crossbar <px from bottom>`.

## Deck setup (`deck-setup/`)

- `wowforever.bat` – lives at `C:\wowforever.bat` in the Lutris Battle.net prefix; starts Battle.net, waits 8 s,
  then sends `launch WoWF` every 2 s until Wow.exe runs (Battle.net ignores it until it has logged in).
- `addshortcut.py` + `wowforever-art/` – the "WoW Forever" Steam shortcut and its artwork (cover, capsule, hero,
  logo, icon; setting it by hand on any shortcut: INSTALL.md step 7).
- `make-chord-layout.py` – the grip chord layout (above); `test_make_chord_layout.py` tests it.
- `make-chord-glyphs.py` / `make-minimap-masks.py` – generate DeckKit's chord glyphs and DeckHUD's minimap masks.

## License

MIT, see [`LICENSE`](LICENSE). DeckKit's controller input is adapted from BagPad (MIT, © 2026 Chris), and the shared button overrides and
wand shoot from Improved Forever (MIT, © 2026 markg).
The Steam art in `deck-setup/wowforever-art/` and the logo in `media/` are AI-generated and not covered by the MIT License;
the Steam art's terms are in [its README](deck-setup/wowforever-art/README.md).
DeckKit is an unofficial fan project, not affiliated with Blizzard Entertainment. World of Warcraft,
Hearthstone and related marks belong to Blizzard.
