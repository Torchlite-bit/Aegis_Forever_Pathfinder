# Changelog

## 0.2.3 — no more blank labels

- **Fixed:** after switching from Default to a Pathfinder theme, some text
  could be missing (in the guide's ≡ menu, "Lock window" and "Reload") until
  the next reload. The text is now drawn again once the fonts have loaded, and
  each time the menu opens.
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
