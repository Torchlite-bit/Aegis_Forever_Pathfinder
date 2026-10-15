# Changelog

## 0.7.0 — the Cozy Sleeping Bag

- **New: a guide for the Cozy Sleeping Bag**, under Collections, one for the
  Alliance and one for the Horde. It takes you through the whole quest chain,
  from level 14: Westfall and the Barrens (the Horde does them the other way
  round), then Stonetalon Mountains, Loch Modan and Thoradin's Wall. It uses
  boats, zeppelins, flights and your hearthstone, and learns flight points on
  the way. On foot it takes about an hour and a half for the Alliance and two
  hours for the Horde.
- Each quest step ticks by itself as you pick up or hand in the quest. Every
  step says where it's dangerous: enemy towns, guards, strong monsters.
- **Already partway through the chain?** Open the guide: it starts where you are.
- Fixed: handing in a quest now also ticks the run or flight just before it.
  The guide no longer waits on a trip you've already made.
- Fixed: a flight point you already know, further on in a route, no longer
  skips the runs and flights before it when you open a flight master's map.
- **After updating, close the game and start it again.** A /reload is not
  enough this time: there is a new file.

---

## 0.6.0 — library books

- **New: routes for the library books**, under a new **Collections** category in
  the guide browser. Four guides: Eastern Kingdoms and Kalimdor, for the Alliance
  and for the Horde. Each picks up every book in the fastest order we found,
  learns flight points on the way, flies and uses your hearthstone, and ends at
  your librarian (Garion Wendell in Stormwind, Owen Thadd in Undercity).
- **Each book ticks by itself** once it's in your bags. Flight points tick once
  you've learned them (open a flight master's map once). Flights, runs and boats
  tick when you get there; any trip, your hearth too, ticks once you've done the
  step after it.
- Many books are in places far above level 30. Each step says where it's
  dangerous: enemy towns, strong monsters, guards.
- The Feralas book is left out until its new spot is known.
- `/apg flights` saves the game's flight masters and maps, for writing routes.
- **After updating, close the game and start it again.** A /reload is not
  enough this time: there is a new file.

---

## 0.5.0 — Pathfinder's arrow, and quests done together

- **New: Pathfinder's arrow**, like the Turtle WoW addon's. An arrow on your
  screen turns to point at the place of the step you're on. Under it: what to
  do there ("Head to the quest giver"), how many yards away it is, and about
  how long it takes to run there. Close by, it says "You're here".
- **Drag it anywhere.** It keeps its place. *Reset windows* puts it back.
  *Lock window* on the guide holds the arrow too, and lets clicks go through it.
- **Settings → Navigation** has a switch for it, its size, and "Put the arrow
  back". `/apg arrow` switches it on and off too. The game's own map pin keeps
  its own switch, and both can be on.
- It shows with the guide window, so it hides when the guide does (in combat
  or dungeons, if you chose that). Inside dungeons the game gives no position,
  so it has nothing to point at there.
- **Quests done together.** Where a guide does several things in one place,
  they show together. At Northshire's kobold camp: the kobolds, the book a
  kobold drops, and the wolves, each ticking itself.
- **Your progress, on the step.** A kill or collect step shows a bar for what
  the quest wants: "Kobold Vermin slain 3 / 10", "Tough Wolf Meat 0 / 8".
- **The guide stops pointing once you're there.** When you reach a kill area,
  the map pin and the arrow go away, so they don't pull you to one spot while
  you fight. If the next thing to do is further off, it points again.
- **Books that start a quest open by themselves**, with quest automation on (it
  is unless you switched it off). Loot one (like the kobold's chewed book) and
  its quest comes up and is taken, once you're out of combat and away from a
  vendor, the bank and the mail.
  The guide ticks the book as soon as it's in your bags.
- **Level-ups tell your party and guild by themselves**, if you ticked them
  under *Settings → Extras*. The game doesn't let an addon do an emote without
  a click, so the emote stays a button on the level-up card (and so does
  anything else the game won't send by itself).
- `/apg chattest` also says which of the game's restrictions were on.
- **After updating, close the game and start it again.** A /reload is not
  enough this time: there is a new file.

---

## 0.4.1 — two quests handed in at once

- **Fixed, in the collected data:** when you hand in two quests less than a
  second apart, the first one was saved as dropped (abandoned). Quest
  automation does this at any NPC that takes more than one quest. Both now
  count as handed in.
- **Fixed, in the collected data:** the first of those two quests also lost its
  XP check, and the next quest the NPC offered was linked to the wrong one.
  The XP is now checked for both. A quest offered after two or more were
  handed in to the same NPC is no longer linked to any of them, since it can't
  be told which one it follows.

---

## 0.4.0 — a first test guide: Northshire

- **New: Northshire Valley (1-6), a short test guide** for Alliance
  characters. The human starting area, from Deputy Willem to Goldshire. It was
  written from the quest data players sent in. Open it from the guide browser:
  click **+** on the guide window. Each step ticks itself as you accept, finish and hand in quests, and
  the game's own pin and arrow point at the next place.
- **Class quests show only for your class.** A Warlock sees the Warlock's
  letter and tome, a Warrior the Warrior's letter, and so on. The steps, the
  count and the arrows all skip the other classes' steps.
- **Who and where, on screen.** On a quest pick-up or hand-in step, the note
  saying who to talk to and where now shows under the step.
- **The guide window** says "Pick a guide" when none is open, and "Guide done"
  at the end of one. Opening a guide from the browser shows the guide window.
- **The map pin** is set once for each step, so a quest you track yourself
  keeps the arrow. Pathfinder takes its own pin away at the end of a guide.
- **After updating, close the game and start it again.** A /reload is not
  enough this time: there is a new file.
- This is a test. Please tell us in the Discord where it goes wrong, and keep
  data collection on: it is how the next guides get written.

---

## 0.3.4 — on CurseForge

- **Pathfinder is on CurseForge:** <https://www.curseforge.com/wow/addons/aegis-pathfinder>. The CurseForge
  app installs it and keeps it up to date. The README and each release's notes
  now say so. Nothing changes in the game.

---

## 0.3.3 — quests accepted with DialogueUI

- **Fixed: quests weren't accepted by themselves** when an addon such as
  DialogueUI shows its own quest window. The addon looked for the game's quest
  window, which those addons keep shut, and gave up. It now follows the quest
  itself, from when it's offered to when it closes. Handing quests in already
  worked.

---

## 0.3.2 — greys sold again, tidier settings

- **Fixed: grey items weren't sold** at a vendor, even with *Sell greys* switched
  on under *Settings → Automation*. WoW: Forever opens the vendor's window a
  moment after it tells addons, and the addon gave up when the window wasn't
  there yet. It now waits for it. Repairs already worked.
- **Fixed, in Default:** the theme's description on *Settings → Appearance* ran
  into "Switches" below it, and a dark strip sat above "Pathfinder" in the
  settings list. The description has room for its longest text, and the strip is gone.
- **Fixed, in Default:** the level-up card's "Level 6!" hung off the bottom of
  its top bar. It now sits in the bar, like the names of the game's own windows.

---

## 0.3.1 — Forever blue

- **The logo is blue** for WoW: Forever: the minimap button, the guide's first page
  and the guide browser show the Aegis: Pathfinder logo with a blue rune ring and
  lettering, to tell it apart from the Turtle WoW addon's red one.

---
## 0.3.0 — Default first

- **New installs start in Default**, the game's own look. If you already use
  the addon, you keep the theme you have. The Pathfinder themes are under
  *Settings → Appearance → Theme*.

---

## 0.2.4 — your name stays with you

- **Fixed: your character's name could go out with your data.** Some quests
  greet you by name ("You there! Genesys, right?"), and the addon saved that
  text as it was. Now it writes `<name>` in its place. Data you saved before is
  cleaned when you log in, and again before you send it. So your name only goes
  out as your credit name, if you choose it.

---

## 0.2.3 — no more blank labels, a close button that closes

- **Fixed:** after switching from Default to a Pathfinder theme, some text
  could be missing (in the guide's ≡ menu, "Lock window" and "Reload") until
  the next reload. The text is now drawn again once the fonts have loaded, and
  each time the menu opens.
- **Fixed:** in Default, the X on the Data collection window took a click on
  only a few pixels. Clicking a window could put its title bar level with its
  X, and the title bar got the click. Every part of a window now stays above
  the part that holds it.
- **New: `/apg mouse`.** Rest the mouse on a button that doesn't take your
  click. Three seconds later, chat says what has the mouse there. It helps us
  find what's in the way.

---

## 0.2.2 — a clearer Reload question

- **Fixed:** the first Reload question after logging in was blank. It now
  says why it asks.
- **Fixed:** the Reload question and "Clear collected data?" open in the same
  place, and one could hide the other. Now the newest one closes the other.
- **Fixed:** picking Default, then a Pathfinder theme again, left the Reload
  question open, and it came back after every fight. Going back now drops it.

---

## 0.2.1 — Reload that reloads

- **Fixed: Reload did nothing.** Switching skins, the guide menu's Reload and
  *Save it now* only said to type /reload. Only the game's own code may reload,
  and 0.2.0 laid an invisible secure /reload button over our own buttons: this
  client gave our button the mouse even with the secure one shown on top of it.
  Every Reload now asks through one small dialog whose Reload button *is* the
  secure button. In combat that dialog can't be shown: Reload says to type
  /reload, and the dialog opens when the fight is over.
- The Reload check and `/apg reloaddebug` from 0.2.0 are gone with the overlay.

---

## 0.2.0 — sending it in

- **New: Submit data.** Replaces Export. It packs everything collected into a
  **share code**: one line (`APF1:` + Base64 of zlib-compressed JSON, made by
  the client's `C_EncodingUtil`) that pastes whole into a GitHub issue,
  several times smaller than the text. The window also has the links to copy
  (the GitHub form and the Discord), **Credit me as**, the file route for big
  collections with a *Save it now (/reload)* button, **As text** to see
  what goes out, and how much is new since your last send. `/apg submit`.
- **New: automatic intake on GitHub.** The *Submit collected data* issue form
  and an Action read the code, a pasted export or an attached saved variables
  file (renamed `.txt` or zipped). They add it to `data/` on the
  `data-submissions` branch, open a pull request, credit the player, and
  answer on the issue. Uploaded Lua is parsed as data, never run. The same
  collection sent again replaces its older copy. Maintainers add files from
  Discord with `python Tools/ingest.py`.
- **New: contributors.** Everyone who sends data is listed in the Submit
  window, on the About page and in `CONTRIBUTORS.md`, all generated from what
  was sent.
- **The Blizzard skin, rebuilt.** It now uses today's art instead of the old
  dialog box: the smooth metal frame over a solid dark background (it was
  see-through), the red close button, the Options window's list highlight,
  category bar and section rules, slim check boxes, sliders, scroll bars,
  drop-downs and search boxes. It falls back to the older art on a client
  without it.
- **Automatically run on the guide window**, next to Start collecting, while
  there is no guide.
- **Fixed: errors on Escape** ("ADDON FORBIDDEN … SpellStopCasting()",
  "SpellStopTargeting()", "UNKNOWN()" from `ToggleGameMenu`). 0.1.0
  reassigned `StaticPopupDialogs` to register its confirmations, which
  tainted it. Blizzard's calendar reads it when it loads and then registers
  its Escape handler, so the game's whole Escape handler list became tainted.
  The confirmations are the addon's own dialog now, and nothing of
  Blizzard's popup system is touched.
- Export format 2: the envelope above, with the collection's id and the
  contributor. The tools still read format 1.
- **Quest automation is on by default**, as in the Turtle addon: quests are
  accepted and turned in by themselves (hold Shift to skip one). Characters
  that had it saved as off get it turned on once, with a chat line saying
  where to turn it off.
- **Selling greys uses the game's own Sell All Junk**, and the *Sell greys*
  button shows only on a vendor without one. Errors in quest and vendor
  automation are reported now, not swallowed.
- **Fixed: "ADDON BLOCKED: UNKNOWN()" on level-up.** This client lets addons
  post in chat only from a click, so the level-up announcement is now a card
  with a button for each place ticked (Emote, Party, Guild).
- **Fixed: "ADDON BLOCKED: Reload()".** This client lets only its own code
  reload the interface. The Reload buttons (the skin change, the guide menu,
  Save it now) now reload through a secure /reload button that sits over
  them while the mouse is on them. In combat they say to type /reload.
- **Fixed: data dropped from exports.** A table with gaps in its numbers (levels
  5 and 6, say) could be written as a short or empty list, losing what came
  after the gap. Such tables are now written whole.
- **Fixed: Reload did nothing when switching skins**, and only said to type
  /reload. The secure /reload button now lies over each Reload button for as
  long as it's shown, instead of being put there as the mouse arrived, which
  could hand the click back to the button underneath.
- **Reload check.** A Reload click that misses the secure button outside combat
  says so in chat with what it saw (keeping the skin dialog open), and
  `/apg reloaddebug` tints the secure buttons red to show where they are.
- **Themes renamed:** Default (Blizzard's own look), and Pathfinder Day,
  Night, Green, Purple, Grey, Tan and Red. Your saved choice carries over.
- **Fixed: a shared quest recorded who shared it.** When a party member
  shared a quest, the collector wrote down their character name as the quest
  giver. Such a pickup is now `shared`, with no name, and the GitHub intake
  strips the name from data sent by earlier builds.
- The repository is now **Aegis_Pathfinder_Forever** on GitHub, and the
  Submit window's GitHub form link points there (the old address still
  redirects). The addon's folder keeps its name, `Aegis_Forever_Pathfinder`.

## 0.1.0 — the Forever port

The Turtle WoW addon (Aegis: Pathfinder 0.24.0) rebuilt for WoW: Forever
(client 1.60.1, interface 16001), with no guides yet.

- **The Pathfinder look, ported:** the guide window (☰ menu, focus and
  overview, tab bar, nav row, progress, footer, resize grip), the guide
  browser, the options window and the minimap button, with the same theme
  code, art and fonts. The Turtle WoW green is now the **Pathfinder** theme.
- **New: the Blizzard skin.** One more theme that draws every window with the
  client's own frames, buttons, check boxes, fonts and tooltip.
- **New: the data collector.** XP per level and time per level; every quest's
  text, level, objectives, pickup and turn-in (who and where), where its
  objectives moved on, the client's own map pins, chains, and rewards (XP by
  player level, money, items, choices, spells, currencies, reputation). Merged
  by quest, stamped by build and race/class/faction, exportable as JSON.
- **New: the data collection window**: Start/Stop, **Automatically run**,
  counts, recent activity, Export, Clear. Also a Data Collection page in the
  settings and `/apg collect`, `/apg start`, `/apg stop`, `/apg export`,
  `/apg status`.
- **Ported:** quest automation (now for all quests, with no guide to limit
  it), selling greys, repairing (now with guild money too), detailed
  reputation gains, level-up announcements, window lock, transparency,
  opacity, scale and hiding.
- **Guides:** a registration API (`AegisPathfinder:RegisterGuide`) and a
  small engine that ticks ACCEPT / COMPLETE / TURNIN steps from the quest
  events and puts the step on the map with the game's own pin and arrow.
- No ClassicAPI, TomTom, pfQuest or Ace2: Forever's client has what they
  provided.
