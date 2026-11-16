# Possible horizons

Ideas worth weighing, none of them committed to. Each entry says where the idea came from and why it
might fit DeckKit's controller-first goal. Remove an entry once it's built or turned down.

## From Forever++ (surveyed 2026-11-15)

[Forever++](https://www.curseforge.com/wow/addons/foreverplusplus) (by xIGBClutchIx) is a large
quality-of-life addon for Forever, with about 90 modules in 10 categories. The survey read its source
as installed on the Deck.

**Its licence rules out copying.** Forever++ ships with no licence file, so its code is all rights
reserved. Building the same idea in our own code is fine; copying its code into DeckKit is not.
(Compare Improved Forever and BagPad, which are MIT and credited in `LICENSE`.)

**Its state on the Deck.** It's installed but turned off on Lucien. Its saved error log has
"Interface action failed because of an AddOn" blocks raised in `Blizzard_GamepadSmartNavigation`
when its minimap button's context menu opened. That's the same kind of gamepad-bar taint CLAUDE.md
warns about. ForeverPlusPlusPad (`~/Projects/ForeverPlusPlusPad`) can switch its modules from the
controller, using `ForeverPlusPlusAPI.v1` and `/fpp toggle`.

Left out: modules that need a mouse (Movable Windows, the Target Markers ring at the cursor, double
right-click Fishing Cast, Chat Copy, Chat Arrow Keys, Macro Icon Search) and modules for other
classes (Druid Mana Bar).

### Fewer presses: automation with nothing new to learn

Each of these removes a step that costs more on a controller than with a mouse.

| Idea | What it does | Why on the Deck |
|---|---|---|
| **Auto Decline** | Declines duel requests as they arrive; party, guild and charter invites optionally | A popup takes the controller's focus away from what you were doing |
| **Auto Gossip** | When an NPC has only one service and no quests, picks it: the bank, shop, trainer or flight map opens straight away | Skips a menu step with the cursor at every NPC |
| **Auto Sell Junk** | Sells gray items at any merchant and says what they sold for; hold a key to skip | No moving the cursor through the merchant window. Check ImprovedForever doesn't already do it |
| **Auto Repair** | Repairs at merchants who repair; guild funds optional; a minimum cost; hold a key to skip | Same as above |
| **Auto Open Containers** | Opens clams, sacks and unlocked lockboxes from your bags; waits out combat, casting and open windows | No trip into the bags |
| **Fast Loot** | With auto loot on, takes everything at once | Fewer loot windows |
| **Auto Dismount** | Dismounts or stands up when an action fails for being mounted or sitting | No "You are mounted", then a second press |
| **Gathering Tracking** | Turns Find Herbs or Find Minerals back on after login, zoning or death | Set once and forget it |
| **Skip Cinematics** | Skips every cinematic, or only ones already seen | One less thing to press past |

Auto Decline and Auto Gossip would come first.

### Information to read at a glance

Passive, nothing to press, readable on the Deck's small screen.

- **Quest Nameplates:** a quest icon and your progress (for example 3/8) next to the health bar of
  mobs you need. Pairs with QuestPad.
- **Spell Ranks:** marks spells on the action bars when you know a higher rank, and names the best rank
  in the tooltip. Useful while levelling a priest, for anything HealPad's spellbook macros don't
  cover.
- **Buff Timers:** shows buff time as 1:23 instead of rounded minutes ("2 m"), and can sort buffs by
  time left. Helps keep Inner Fire and Fortitude up.
- **Quest Levels:** `[12]` before quest names at quest givers and in the quest details window.
- **Best Quest Reward:** a gold coin on the reward that sells to a vendor for the most. It doesn't
  choose for you.
- **Forever Quest Icons:** marks quests that are new in Forever and weren't in original Classic.
- **Flight Timer:** learns how long each flight takes, then shows a countdown bar while you fly and the
  time in the flight map tooltip. Could be a DeckHUD status-bar slot.
- **Gathering Skill Tooltips:** the skill a herb, ore or lockbox needs, colored by difficulty like
  recipes at a trainer.

### Ideas to build into DeckKit rather than enable

- **Whisper Window → ChatDeck tabs.** Forever++ keeps one conversation per person. It's the same idea
  as the saved TODO of LB/RB switching the chat peek between full log, whispers, group and combat log.
- **Zone Info → MapDeck.** A zone's level range, faction, dungeons, fishing skill, and herbs, ore and
  skinning, shown in a corner of the full-screen map.
- **Unexplored Areas → MapDeck.** Shows the parts of a zone's map you haven't explored yet.
- **Gathering Map → the shelved gathering route.** Forever++ remembers every node you gather, across
  characters, and moves a node's icon closer to its real spot each time you gather it again. That's the
  recording half of the shelved node route (memory: future-gathering-route). Reading its data would
  be a second third-party exception after Pawn, so the likelier route is our own recording.

### Already covered by DeckKit (keep these off if Forever++ is turned back on)

| Forever++ module | DeckKit equivalent |
|---|---|
| Square Minimap | DeckHUD |
| Waypoints, Compass Bar | DeckKit.Waypoints + WayPad, DeckHUD compass |
| Loot Rolls | DeckHUD's loot rolls |
| Chat History, Keep Chat Visible | ChatDeck's chat peek and history |
| XP Bar Text | DeckHUD's XP line |
| Auction Prices, Disenchant, Sell Price | MarketDeck tooltips |
| Upgrade Arrows | PackPad marks (via Pawn) |
| Points of Interest (flight masters, spirit healers) | MapDeck peek |

### How to try them

- **Quickest:** turn Forever++ back on, switch on only the wanted modules with ForeverPlusPlusPad
  (`/deckkit fpp`), and stay away from its minimap button.
- **Lasting:** build the chosen ones as DeckKit features (likely DeckSundries for the small automations),
  with settings in the DeckKit menu and our own code.

## Travel routing for the waypoints (2026-11-15)

Routing across trams, boats, zeppelins, portals and flight paths, so a waypoint on another continent
starts with "take the boat from Menethil". Terrain pathfinding was researched and shelved, because
addons get no player height (`nav/`). The travel data comes from an existing
addon, called through its API like Pawn (game-data libraries are an allowed exception, see CLAUDE.md):

- **MapzerothLib** (chosen, 2026-11-15): Mapzeroth's travel data and route planner, split into a
  library in Ben's fork (`~/Projects/Mapzeroth`), proposed upstream (tr0tsky0/Mapzeroth#29). Forever
  data measured in game: zeppelins, boats, borders, city gates, flight points the character has found.
  `MapzerothLib.v1.RouteTo(mapID, x, y, name)` returns steps with text, time and end point.
- **FarstriderLib** (tried, removed): GPLv3, Forever data built mostly from Blizzard's thin travel
  tables; it misses the Orgrimmar–Grom'gol zeppelin, so it sent a Durotar orc to Westfall by the
  Ratchet boat.

Still to build: DeckKit's core waypoints handing far-away legs to MapzerothLib when it's installed.
