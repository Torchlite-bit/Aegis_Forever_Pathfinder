# Feature inventory: Turtle WoW Pathfinder → WoW: Forever

Every feature, window, setting, command and saved variable of
[Aegis: Pathfinder](https://github.com/Torchlite-bit/Aegis_Pathfinder) v0.24.0
(the 1.12 / Turtle WoW addon), and what this port does with it.

The Forever port is a **shell**: the same windows and look, rebuilt on the
Forever client's API, with one short **test guide** so far (Northshire
Valley, 1-6, from 0.4.0). Beside it, a **data collector** records quests and
levels so the guides can be written from real data.

**Status key**

| Status | Meaning |
|---|---|
| **Ported** | Works in the Forever port as it did on 1.12 |
| **Adapted** | Works, changed to fit the Forever client (noted) |
| **Shell** | The window or engine is there and works, waiting for guides to have something to show |
| **Waits for guides** | Only configures or reads the guides, so it comes back with them |
| **Not ported** | Depends on Turtle WoW data or 1.12 addons that don't apply on Forever (reason given) |
| **New** | Forever only |

## Windows

| 1.12 window | 1.12 file | Status in the Forever port |
|---|---|---|
| Guide window: header ☰ / ⤢ / ✕, tab bar, nav row, progress rule, steps, footer, resize grip | `ObjectivesFrame.lua` | **Shell.** Same geometry: 396 px wide, 30/26/26/4 px chrome, 44 px rows, 24 px footer, focus and overview modes, the grip that sets the width and height cap. With no guide, the body shows an empty state with **Start collecting data**. A new ● chip lights while collecting. |
| The ≡ menu: Guide menu, Setup wizard, Lock window, Transparency, Reset window, Reload, Settings | `ObjectivesFrame.lua` | **Adapted.** *Setup wizard* is replaced by *Data collection* (the wizard picks guides and dungeons). Everything else is the same. |
| Guide browser: Home / Current / Recent, search, categories, list, picture pane | `GuideListFrame.lua`, `GuideBrowser.lua`, `GuidePictures.lua` | **Shell.** Same layout. Categories: Leveling, Dungeons, Class Quests, Professions, Collections (new: the library-book routes, 0.6.0), Favorites. An empty list links to data collection. Home shows **XP to level, as collected** in place of the 1.12 level tracker. Pictures (Turtle loading screens, explored-map overlays) are not ported. |
| Options window: category list, scrolling pages, subhead naming the page | `OptionsFrame.lua` | **Adapted.** Same 150 + 396 px layout and widgets. Pages: Data Collection (new), Appearance, Navigation, Automation, Extras, Maintenance, About. The width/height grip is not ported (fixed 546×560). |
| Minimap button: click guide, right-click options, drag round the edge | `MinimapButton.lua` | **Ported**, plus shift-click for data collection. The Blizzard skin gives it the standard gold tracking ring. |
| Tooltips: the theme's own hint card, opened beside the guide | `Theme.lua` | **Ported.** The Blizzard skin uses `GameTooltip`. |
| Data collection window | — | **New.** Start/Stop, **Automatically run**, counts, recent activity, Submit data, Clear. The guide window's empty state has Start collecting and **Automatically run** too. |
| Submit data window | — | **New.** The share code (compressed, one line) or the text, **Credit me as**, the GitHub form and Discord links to copy, the file route with a /reload button, contributors. |
| Setup wizard (first login: guide, features, dungeons) | `SetupFrame.lua` | **Waits for guides** |
| "Where next?" between guides | `NextGuideFrame.lua` | **Waits for guides** |
| Active Items / Active Targets / Macros windows | `ActiveFrames.lua` | **Waits for guides** (they act on the step's items and targets) |
| Shopping list, crafting route window | `MaterialsFrame.lua`, `CraftRouteFrame.lua`, `CraftPlanner.lua` | **Not ported.** Built on Turtle WoW recipe and price data (CraftRoute, CMaNGOS). |
| Gear Advisor, Gear Finder tab, Item Score page | `GearAdvisor.lua`, `GearFinder*.lua`, `GearFrame.lua`, `ItemScore*.lua`, `GearData.lua` | **Not ported.** Built on CMaNGOS loot tables and Turtle stat weights. Forever's items differ, so this needs Forever data. |
| Talent Advisor and its marks on the talent window | `TalentAdvisor.lua`, `TalentWindow.lua`, `TalentModern.lua`, `TalentBuilds.lua` | **Not ported.** Turtle WoW talent trees. Forever uses its own talent UI (`Blizzard_SharedTalentOverrides` for camelot). |
| Navigation callout (the floating arrow) | `NavCallout.lua`, `Navigation.lua` | **Ported (0.5.0)** as `UI/NavArrow.lua`: the same arrow art, phrases, yards and ETA, shadowed, draggable, ticking ten times a second; the bearing from `C_Map.GetPlayerMapPosition`, `C_Map.GetMapWorldSize` and `GetPlayerFacing`, turned with `Texture:SetRotation`, so Astrolabe isn't needed. Beside it, the client's own map pin and super-tracked arrow (`C_Map.SetUserWaypoint`, `C_SuperTrack`), each with its own switch. No TomTom/pfQuest providers. |
| Map reveal, step markers, ant trail, rares | `Maps.lua`, `MapOverlays.lua`, `Rares.lua` | **Not ported.** Turtle map overlays and pfQuest-turtle rare spawns. |
| Party sync / share a guide | `PartySync.lua` | **Waits for guides** |
| Credits window, error log | `Credits.lua`, `Core.lua` | **Adapted.** Credits are on the About page. The client's own error display replaces the error log. |

## Look

| 1.12 | Status |
|---|---|
| Design tokens (`Theme.color`), Rajdhani + Inter fonts, nine-sliced rounded panels, drop-shadow ring, cap strips, chips, pills, tabs, badges, bands, switches, check boxes, sliders, dropdowns, scrollbar, window stacking, window scale, position saving | **Ported** unchanged (`Core/Theme.lua`), with the same generated `media/` art |
| Themes: Day, Night, Turtle WoW (green), OctoWoW, RavenCraft, Capybara Paradise, Aegis | **Ported**, named Pathfinder Day, Night, Green, Purple, Grey, Tan and Red. Green ("Turtle WoW" there) is still the one a new install starts with; a saved `turtle` is read as `pathfinder`. The saved keys are unchanged. |
| Switch colours (theme / red-green) | **Ported** |
| **Blizzard skin** | **New.** The **Default** theme: a theme that swaps the art for today's client art, like the game's Options window: the metal nine-slice frame on a solid dark fill, the red close button, `UIPanelButtonTemplate`, the slim check boxes, sliders, scroll bars and drop-downs, the Options list highlight, category bar and section rules, Friz Quadrata, gold labels, `GameTooltip`. Older dialog art where the client lacks it. Switching to or from it reloads the UI. |
| Turtle loading screens and custom-zone maps (`media/loadscreens`, `media/maps`) | **Not ported** (Turtle WoW content) |

## Settings

| 1.12 page / setting | Status |
|---|---|
| Route: race, route pack, route preview | **Waits for guides** |
| Dungeons: dungeon chips, Turtle dungeons, along the way, middle of levels, boss notes role | **Waits for guides** |
| Filters: solo/group, Auction House steps, Solo Self-Found | **Waits for guides** |
| Appearance: theme, switch colours, window scale | **Ported** (+ the Blizzard skin) |
| Appearance: lock window, transparency, guide opacity, browser opacity, step text size, progress bar | **Ported** |
| Appearance: grow upward | **Not ported yet** (minor; the guide pins by its top-left) |
| Appearance: hide in dungeons/raids, show again after, hide in combat | **Ported**. *Hide action buttons in combat* waits for the action buttons. |
| Appearance: minimap button | **Ported** |
| Step Display: steps in focus mode, skip hearth/flight paths, follow-ups, custom zones, class quests, party sync | **Waits for guides** |
| Automation: accept and turn in quests | **Adapted.** With no guide to say which quests are "its", it covers all quests. Never takes a grey quest or chooses a reward, and keeps two log slots free. Hold Shift to suspend. |
| Automation: pick the quest from an NPC's list | **Ported** (`C_GossipInfo` and the quest greeting) |
| Automation: take the step's flight, buy the step's items | **Waits for guides** |
| Automation: Sell greys button, sell greys automatically | **Ported** (`C_Container`) |
| Automation: repair automatically | **Adapted.** Adds *Guild money first*, since Forever has guild bank repairs. |
| Action Buttons page | **Waits for guides** |
| Navigation: waypoint provider, arrows (Pathfinder/TomTom/pfQuest) | **Adapted** into two switches: the game's own pin and arrow, and Pathfinder's arrow (with its size and "Put the arrow back") |
| Maps page | **Not ported** (see Maps above) |
| Gear, Item Score pages | **Not ported** (see Gear above) |
| Extras: Pathfinder chat messages, detailed reputation gains, level-up announcements (emote/party/guild) | **Ported** (`C_Reputation`, `C_ChatInfo.SendChatMessage`). Level time comes from the collector's level clock. |
| Extras: Talent Advisor | **Not ported** |
| Maintenance: rescan progress, error log, run setup | **Adapted:** Reset windows, Show the guide, Rescan quest log |
| About: version, credits | **Ported** |
| **Data Collection page** | **New** |
| Blizzard Options → AddOns entry | **New:** a page that opens the Pathfinder settings window |

## Slash commands

| 1.12 | Forever |
|---|---|
| `/apg`, `/pathfinder` | **Ported**: toggle the guide window |
| `/apg next`, `/apg prev` | **Ported** |
| `/apg resetpanels`, `/apg minimapbutton` | **Ported** |
| `/apg goto`, `/apg reset`, `/apg setup`, `/apg ssf`, `/apg share`, `/apg target`, `/apg useitem` | **Wait for guides** |
| `/apg materials`, `/apg craft`, `/apg exchange`, `/apg gear`, `/apg finder`, `/apg talents` | **Not ported** (see above) |
| — | **New:** `/apg collect`, `/apg start`, `/apg stop`, `/apg submit` (or `/apg export`), `/apg status`, `/apg config`, `/apg browser`, `/apg help`, `/apg arrow` (0.5.0) |

Key bindings (**New**): *Show or hide the guide* and *Data collection window*,
under AddOns in the game's key bindings.

## Saved variables

| 1.12 | Forever |
|---|---|
| `AegisPathfinderDB` (AceDB-2.0: `profile`, `char`, `account`) and the legacy `TurtleGuideDB` | `AegisPathfinderDB` (account-wide): `profile` (look and windows, same key names as 1.12) and `collect` (the collector's data, see [data-schema.md](data-schema.md)) |
| — | `AegisPathfinderCharDB` (per character): the 1.12 `char` switches, plus `collecting`, `collectauto`, `levelclock`, `currentguide`, `progress`, `recentguides` |

AceDB-2.0, AceConsole-2.0 and the rest of Ace2 aren't used. They're 1.12
libraries, and the port uses plain saved variables and `SlashCmdList`.

## Engine

| 1.12 | Status |
|---|---|
| Guide DSL parser (TourGuide format), QuestShell+ parser, route packs, tabs/branches, auto-advance from ClassicAPI events | **Shell.** A smaller engine replaces it (`Core/Guides.lua`): guides register as Lua tables (see [guide-api.md](guide-api.md)), ACCEPT / COMPLETE / TURNIN steps tick themselves from `QUEST_ACCEPTED`, `QUEST_LOG_UPDATE` and `QUEST_TURNED_IN`, and the step's place goes on the map. The TourGuide text DSL parser can be ported when guide authors want it. |
| ClassicAPI DLL requirement | **Gone.** Forever's client has `C_QuestLog`, `QUEST_ACCEPTED`, `QUEST_TURNED_IN` natively. |
| pfQuest / TomTom / MetaMap integration | **Not ported** (1.12 addons) |
