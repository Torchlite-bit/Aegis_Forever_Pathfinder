# Changelog

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
