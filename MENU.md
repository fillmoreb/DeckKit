# The DeckKit menu

Everything in the DeckKit menu, tab by tab, as it stands on 2026-11-17, after the reorganization. It was read from the game on Sneaky, so "Now" is Sneaky's setting (or the account's, for shared ones).

**Opening it:** double-tap **Menu**, or type `/deckkit`. **LB / RB** change tabs, the **d-pad** moves, **A** activates (toggles, opens a list, runs an action), and **B** goes back or closes. Each row's explanation also shows in the panel on the right while it's focused.

**Marks after a label:**
- a **lilac people icon**: kept for this character only; your other characters keep their own
- the **reload arrow**: takes effect after a `/reload`
- a **red !**: can't be undone from here

Beside the list, each setting also says whether it's shared by all your characters, kept for this character, or only lasts until the next reload.

The tabs: **Setup · Controls · Screen · Quests · Chat · Party · Trade · Advanced**.


---

## Setup

### Welcome
*From DeckKit*

| Option | Now | What it does |
|---|---|---|
| Setup steps | (action) | Opens the welcome window: the handful of one-time setup steps, and whether each one is done. Also `/deckkit setup`. |


### Suggested game settings
*From DeckHUD*

Game settings that suit the Deck. Turning one off puts back what you had before, except the grip keys.

| Option | Now | What it does |
|---|---|---|
| Classic chat style | On | Enter sends a chat message and closes the input box, dictated messages included. Works well with Decktation. |
| Auto loot | On | Opening a corpse takes everything at once, no picking items one by one. |
| Hide the controller button legend | On | Hides the game's always-on list of what each button does. |
| Game's own UI scale | On | No custom UI scale. The suggested layout's positions are measured at the game's own scale. |
| Free the grip keys (F1-F8) **!** | On | Clears the game's own bindings on the keys the grips send (by default F1–F5 target you and your party). Can't be undone from here: rebind them in Key Bindings. |


### Layout
*From DeckHUD*

Every action that changes your Edit Mode layout, in one place. Each one backs up the layout first and then reloads; they share one backup, so **Undo** puts back the layout from before the last one.

| Option | Now | What it does |
|---|---|---|
| Apply everything suggested | (action) | Turns on every suggested game setting above, frees the grip keys, and applies the suggested layout: your frame and the target's, party frames in a row between them, the focus frame centered, raid frames top-left, buffs under the status bar, the compact crossbar near the bottom. On a new character, a game preset layout is first copied to a layout called "DeckKit". |
| Buffs in rows of 4 | (action) | Your buffs four to a row, the fifth starting a new row below. |
| Buffs under the bar | (action) | Moves your buffs down to just under the status bar. |
| Line up party frames | (action) | Raid-style party frames in a row, filling the gap between your frame and the target frame, just under them. |
| Center the focus frame | (action) | The focus frame in the middle of that gap, at their height (with "Name and health", it also turns on Use Larger Frame, which the focus's buffs need). |
| Line up raid frames | (action) | Raid frames in the top-left corner, just off the screen edge and under the XP bar. |
| Undo the last layout change | (action) | Puts back your Edit Mode layout from before DeckKit's last change, then reloads. |


---

## Controls


### Grips
*From DeckKit*

The back grips (L4, R4, L5, R5), alone or together, pressed or held, are slots for actions. This needs
DeckKit's Steam controller layout.

| Option | Now | What it does |
|---|---|---|
| Grip chords | On | Turns the grip chord system on. |
| Slot changes apply to (per character) | All characters | **All characters:** changes go to the slots every character shares. **This character:** changes are kept for this character only, on top of the shared ones (for class spells, say). Those show in lilac. |
| Clear this character's slots | (action) | Drops this character's own slot changes, so it goes back to the shared slots. |

Then come the slot tables: one row per chord, with a **Press** and a **Hold** column. Press **X** on a slot
to pick an action (DeckKit actions, spells, items, macros), and **Y** to put it on the cheat sheet or take it
off; a check in the slot shows it's there. The tables are split into three sections: **Grips** (single
grips), **Grips: two together** and **Grips: three or four together**.

The slots as they are now:

| Chord | Press | Hold |
|---|---|---|
| L4 | Hide left side | Chat peek |
| R4 | Hide right side | Map peek |
| L5 | Add waypoint | — |
| R5 | Quest item | Bag peek |
| L4+R4 | Dictation | — |
| R4+L5 | Debug strip | — |
| L5+R5 | Decky (voice assistant) | — |
| Every other chord | — | — |

New actions from today, offered but not assigned yet: **Guide: skip step**, **Guide: undo skip**,
**Guide: show / hide**, **Graphics: next preset**.


### Cheat sheet
*From DeckKit*

| Option | Now | What it does |
|---|---|---|
| Show cheat sheet | On | A small list on screen showing what your grips do. Which slots it shows is picked with **Y** in the grip tables above. Also a chord action ("Cheat sheet") and `/deckkit sheet`. |
| Where | Left, above chat | Where it sits: Bottom right, Left above chat, Top center, or Right under the quest tracker. It hides along with its side of the screen when you hide that side. |

On it now: Quest item (R5), Bag peek (R5 held), Dictation (L4+R4), Debug strip (R4+L5), Decky (L5+R5).


### Buttons
*From DeckSundries*

| Option | Now | What it does |
|---|---|---|
| Wand shoot | On | With a living enemy targeted, X fires your wand instead of a melee swing. |
| Y sets reply in the friends list | On | Y on a friend in the friends list makes them your reply target, so `/r` (or dictating "reply …") whispers them. |
| No target menu in combat | On | During a fight, Y on its own doesn't open your target's right-click menu. With a trigger held, Y works as usual. |


### Menu
*From DeckKit*

| Option | Now | What it does |
|---|---|---|
| Double-tap Menu opens this | On | Pressing the Menu button twice quickly opens the DeckKit menu. `/deckkit` always works either way. |


---

## Screen


### Graphics
*From DeckHUD (from DeckForever, by eliog)*

| Option | Now | What it does |
|---|---|---|
| Graphics preset | Balanced | Steam Deck presets for the game's graphics, picked from a list. Your own settings are saved before the first preset goes on. **Your own settings** puts those back.<br>**Battery:** 30 fps, longest play time (about 4.5 h questing, 4.2 h in cities).<br>**Balanced:** 45 fps, with shadows and shading (about 3.7 h / 3.2 h).<br>**Max FPS:** 60 fps at full power, cities about 50 (about 2.7 h / 2.3 h).<br>**Max Quality:** 30 fps, best picture; plugged in, not for cities (about 2.6 h / 2.3 h). |
| ↳ On the Deck | 45 FPS (90 Hz) · TDP 10 W | What to set in the Deck's own Performance menu (… › Performance, per-game profile) to match the preset. |
| (note) | | An addon can't change the Deck's Frame Limit or TDP: set them yourself. |

A grip chord action, **Graphics: next preset**, steps through the presets while you play, with a short notice.


### Status bar
*From DeckHUD*

| Option | Now | What it does |
|---|---|---|
| Status bar | On | A dark bar across the top of the screen, with readings and an XP line along it. |
| Hide Blizzard's XP bar | On | While the status bar shows, its XP line and XP reading replace Blizzard's bar. |
| XP line | On | Purple along the bottom of the bar, with rested XP beyond it in blue. |
| Opacity | 1 | How solid the bar is (0.2–1). |
| Left 1–5, Middle 1–3, Right 1–5 | see below | What each of the 13 reading slots shows. |

Readings to choose from: Nothing, Clock, Frames per second, Latency, Gold, Free bag slots, Durability
(lowest item), Experience, Coordinates, Battery, Battery draw, APU power, CPU load, GPU load, Memory,
APU temperature, Fan speed. While the compass is on (Quests › Compass), the middle readings show at the right side instead. The Steam Deck readings (battery, power, temperatures and so on) come from
DeckKitAfterDark's DeckTelemetry, and stay blank without it.

The slots now:

| Slot | Shows |
|---|---|
| Left 1 | Experience |
| Left 2 | Gold |
| Left 3 | Free bag slots |
| Left 4 | Durability |
| Middle 1 | Clock |
| Right 1 | Frames per second |
| Right 2 | Latency |
| Right 3 | Battery |
| Right 4 | APU temperature |
| The rest | Nothing |


### Minimap
*From DeckHUD*

| Option | Now | What it does |
|---|---|---|
| Square minimap | On | A square map in the top-right corner instead of the round one. It's now always 256 × 253, the size measured on Lucien. |
| Zone name on the map | On | The zone or area across the top of the map, colored friendly, hostile or contested. |
| Border | Dialog | **Dialog:** the classic dialog box edge. **Thin metal:** the frame DeckKit's windows use. **Thin line:** a 1-pixel dark edge. **None.** |
| Hide buttons around the edge (reload) | On | Hides the zone text, tracking, calendar, mail, zoom and addon buttons. Turning it off needs a `/reload`. |
| Leave room for the battery overlay | On | Moves the map down so the Steam performance overlay's battery doesn't cover it. |
| Zoom | 3 | How far in the map is zoomed; 0 is the widest view. |
| (note) | | For Blizzard's own minimap, disable DeckHUD in the AddOns list. |


### Bags
*From PackPad (per character)*

| Option | Now | What it does |
|---|---|---|
| (note) | | Bag peek: hold its grip slot ("Bag peek", R5 held) to see everything you carry, full screen. Both sticks stay yours. |
| Clear item marks | (action) | Takes the stars off every marked item (Decky's flags, for one). |
| Bag slot size | 0.7 | Size of the item slots and bag icons, as a share of Blizzard's own (0.5–1). The window's title, search and gold stay the same size. |
| Bag columns | 10 | How many slots wide the grids are (6–20; Blizzard's own is 10). |
| Bag window height | 48 | How far above the bottom of the screen the bags sit (0–200; Blizzard's own spot is 85). |


### Loot rolls
*From DeckHUD*

| Option | Now | What it does |
|---|---|---|
| Loot rolls in the top-left corner | On | Need / Greed / Pass shows in the top-left corner under the XP bar, not over the chat. |
| Compact until you press View | On | Just the items' names in their quality colors and the time left. The View button brings up the game's window to roll. |
| ↳ Time left | Bar behind the name | How the time left shows: a thin bar, seconds, or a bar behind the name. |
| ↳ Opacity | 0.4 | How solid the compact list is (0.2–1). The game's roll window always shows at full. |


### Tooltips
*From DeckHUD*

| Option | Now | What it does |
|---|---|---|
| Mouseover tooltip | Top of the screen | Where the tooltip for players, NPCs and objects under the reticle shows: the top of the screen, or Blizzard's corner. Item and button tooltips keep their own places. |
| ↳ Opacity | 0.3 | How solid the tooltip at the top is (0.2–1). |

---


### Action bars
*From DeckHUD*

| Option | Now | What it does |
|---|---|---|
| Hide macro names | On | No macro name across buttons on the crossbar and action bars; the icon still shows. |


---

## Quests


### Leveling guide
*From GuidePad (per character)*

| Option | Now | What it does |
|---|---|---|
| Leveling guide | On | Shows the leveling guide where the quest tracker was, in its style: the step you're on, what's done, and your other quests below. The guides are Polestar's, by Fitz. |
| Guide | The best for my level | Which guide to follow. **The best for my level** picks one for your race, level and zone, and moves on to the next guide by itself when one is done. Or pick any leveling guide for your faction from the list (29 for Horde, Zephras Isle 1–15 through Felwood, Moonglade & Winterspring 59–60). |
| Waypoint to the next goal | On | Puts a waypoint on the step's next goal that has a place (who to talk to, where to go, where the mobs are), so the compass and the walk lead there. It stays behind your own waypoints: while you have one, yours leads. |
| Your other quests below it | On | Lists the quests you watch that the step doesn't already show, as the quest tracker would. |
| Skip this step | (action) | Passes the step you're on, for one you've done some other way or don't want. Also a grip chord action. |
| Undo the last skip | (action) | Brings back the last step you skipped. |
| (credit) | | The guides are Polestar's, by Fitz (github.com/fitzforge/polestar): every route, step and tip. |
| Now | Zephras Isle, step 7 of 79 | Which guide and step you're on. |


### Compass
*From DeckHUD*

| Option | Now | What it does |
|---|---|---|
| Compass | On | In the middle of the status bar: the way you're facing, with your active waypoint and its distance. It moves the bar's middle readings to the right side. |
| Width | 600 | How long the compass strip is (240–720). Very wide, it can run into the readings on either side. |
| View | 180° | How much of the horizon the strip covers (90–270°). Less: things move further as you turn, so they're easier to line up. More: a wider look around. |
| Blizzard's map pin | On | The pin you place on the world map shows as a dim gold pin. |
| Focused quest | On | The quest the game has focused (super-tracked) shows as its icon: dots while you work on it, a ? once it's ready to hand in. |
| Guard directions | On | The flag a city guard puts on your map when you ask for directions. |
| Your corpse | On | While you're dead, a tombstone shows which way your body is. |
| Party and raid | On | Your group as dots in their class colors. |
| Raid markers | On | A group member wearing a raid marker shows as that marker. (Markers on enemies can't be shown: the game only gives positions for your group.) |


### Waypoints
*From WayPad ("Waypoints go to" per character; the route rows shared)*

| Option | Now | What it does |
|---|---|---|
| Waypoints go to | DeckKit | **DeckKit:** its own compass, map pins, walks and arrival. **Waypoint addon:** hands them to a TomTom-compatible addon instead. |
| Plan routes | On | A far waypoint is reached in legs (walk to the zeppelin tower, take the zeppelin, walk on), and the compass shows each one. Uses ForeverNav. Off: the compass points straight at the waypoint. |
| Follow roads | On | The walk drawn on the minimap and peek map keeps to roads where that adds less than half again to the distance: safer while leveling. Off: the shortest line, cliffs and all. |
| Share ride times | On | Boats and zeppelins you ride tell other players on your shard when they leave, and theirs tell you, so route plans wait for the real departure. Sends only ride times, over a hidden addon channel. |
| Add a waypoint | (action) | Dial in map coordinates with the d-pad. Also on L5. |
| Manage waypoints | (action) | The list of waypoints: make one active, edit or remove them. |


### Quest items
*From QuestPad (per character)*

| Option | Now | What it does |
|---|---|---|
| Quest item button | On | A big button for the quest item you need now: the quest whose area you're in, or the one your target belongs to. Used with R5. |
| Use your target's quest | On | Targeting a mob for one of your quests puts that quest's item on the button, even outside the quest's area. |
| Height | −190 | Where the button sits, up or down from the middle of the screen. |
| Show the button for a moment | (action) | Shows it with a sample icon for a few seconds, so you can see where it sits. |


### Map
*From MapDeck*

| Option | Now | What it does |
|---|---|---|
| Show recorded streets on the map peek | Off | The streets you've recorded (the "Record streets" grip action, or `/deckkit streets start`), as green squares. They always show while you're recording. |
| (note) | | Hold the map peek's grip slot (R4 held) for the map. Both sticks stay yours. |

---


---

## Chat


### Chat window
*From DeckHUD*

| Option | Now | What it does |
|---|---|---|
| Thin frame (reload) | On | A thin dark edge instead of Blizzard's chat art. Turning it off needs a `/reload`. |
| Hide the button hints | On | No "A Send / X Chat Channels / Y Tab Settings" bar under the chat box. |
| Tuck into the corner (reload) | On | Chat sits bottom-left, close to the edges. Turning it off needs a `/reload`. |


### Chat peek
*From ChatDeck*

| Option | Now | What it does |
|---|---|---|
| Font size | 22 | Text size in the chat peek (12–40). |
| (note) | | Hold the chat peek's grip slot (L4 held) to read chat. Both sticks stay yours, so you can keep running while it's up. |


### Chat history
*From ChatDeck*

| Option | Now | What it does |
|---|---|---|
| Keep chat across reloads | On | The last 200 lines of each chat tab come back after a reload or login (and in the chat peek), under a grey line with the time they were saved. Kept per character. |
| Clear saved chat | (action) | Forgets the saved lines. What's in the chat window now stays. |


### Dictation
*From DeckKit*

| Option | Now | What it does |
|---|---|---|
| Dictation indicator | On | Shows "Listening" while the dictation chord is held, then "Transcribing". |
| Mute the game while dictating | On | The game goes quiet from the moment you press the dictation chord until you stop talking, so the Deck's mic doesn't pick up the speakers. |
| Indicator opacity | 1 | How solid the Listening / Transcribing box is (0.2–1). DeckKit's other short notices use the same spot and opacity. |

---


### Decky
*From DeckAgent (DeckKitAfterDark)*

| Option | Now | What it does |
|---|---|---|
| Preview agent chat before sending | On | Messages Decky sends for you wait in a small window first: A Send, B Cancel. Off: they go straight out. |
| Quiet: show answers instead of speaking them | Off | For voice chat or a quiet room: answers go on a card and in chat, and nothing is said out loud. |
| Model | Default (Sonnet) | Which Claude model answers: Haiku is quickest; Sonnet and Opus think harder but take a few seconds longer and use more of your plan. Takes effect on the next question. |
| Clear Decky's checklist | (action) | Takes down a checklist Decky put up (it also goes by itself a minute after it's all done). |


---

## Party


### Frames
*From DeckHUD*

| Option | Now | What it does |
|---|---|---|
| Focus frame (reload) | Name and health | **Blizzard's:** the normal frame. **No portrait:** a thin border round the focus's name and bars. **Name and health:** just a big first name in class color over a tall health bar, handy when the focus is who your heals go to. Going back to Blizzard's look takes a reload. |
| Focus auras | (action) | With the "Name and health" look: picks which buffs show under the focus frame, plus your own debuffs on them (a priest's Weakened Soul) and debuffs you can dispel. |
| Hide the LB prompt under party frames | On | Hides Forever's "LB" reminder under party and raid frames; LB still jumps to them. |


### HealPad
*From HealPad*

| Option | Now | What it does |
|---|---|---|
| Make the d-pad macros | (action) | Makes the macros HealPad Up / Down / Left / Right, for your healing page's d-pad (moving the selection between party or raid frames). |
| Make heal macros | (action) | One macro per helpful spell you know (and Resurrection), cast on your focus, for your healing page's face buttons. You pick which spells from a list. |
| (note) | | To put them on your crossbar: game menu › Macros, pick one, X Bind to Action Bar. |
| (note) | | Heal macros aim at the selection through `[@focus]`. |


### Practice frames
*From HealPad (only until the next reload)*

| Option | Now | What it does |
|---|---|---|
| Practice party | Off | Five frames where your party frames would be, all of them you, to see the layout and try the cursor while solo. |
| Practice raid | Off | The same for raid frames. |
| ↳ Raid size | 25 | 10, 25 or 40 practice raid frames. |


---

## Trade


### Fishing
*From DeckAngler (per character)*

| Option | Now | What it does |
|---|---|---|
| X casts Fishing | On | With a fishing pole equipped and out of combat, X casts Fishing. |
| Missed-catch chime | On | Plays when the bobber times out without a bite. |
| Idle reminder | 1 min | Reminds you when you have a pole equipped but haven't cast for this long: Off, 30 sec, 1, 2 or 5 min. |
| Reminder sound | Whisper double tap | The reminder's sound; each one plays as you pick it. |
| Show the last tally | (action) | Shows the catch tally from your last fishing session. |
| Reset the tally panel position | (action) | Puts the tally panel back in its default spot. |


### Disenchanting
*From DisenchantDeck (per character)*

| Option | Now | What it does |
|---|---|---|
| Open the disenchant list | (action) | A list of what you can disenchant, to go through with the controller. |
| Open it when you pick Disenchant | On | Choosing Disenchant from the spellbook, professions or an action button opens this list instead of the pick-an-item cursor. |
| Show hidden items again | (action) | Un-hides everything you hid from the list with Y. |


### Auction house
*From MarketDeck and AuctionPad*

| Option | Now | What it does |
|---|---|---|
| Scan when the auction house opens | On | Opening the auction house takes a snapshot of every auction, if the last one is over an hour old (Blizzard allows one every 15 minutes). Prices are kept per auction house, for all your characters. |
| Ring the bell when a snapshot is done | On | The boat-docked bell as the scan finishes. |
| Prices in item tooltips | On | Auction (lowest now, and the two-week market price), vendor and disenchant value in item tooltips. |
| Last snapshot | 4 h ago | When prices were last scanned. |
| (note) | | Talking to an auctioneer opens AuctionPad instead of Blizzard's window. LB/RB switch between Sell and My auctions. In **Sell**, pick an item on the left, set price, amount and length on the right, and A posts it. In **Buy**, open a category (or search), set the level, rarity and usable filters, A on an item shows its listings, and A buys. B goes back a step. |


---

## Advanced

### Help and testing
*From DeckKit*

| Option | Now | What it does |
|---|---|---|
| (note) | | Chat commands: `/deckkit help`. |
| Reload UI key | Not bound | A keyboard key that reloads the interface, for testing at a desk. |
| Design sample | (action) | Every DeckKit control in one window, to try with the controller. |
