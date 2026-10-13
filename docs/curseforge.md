# CurseForge

How Pathfinder (Forever) gets onto CurseForge, and the text for its project
page. Releases work as the Instance Journal's do: every merge to `main`
publishes a GitHub release for the `.toc` version, and each new version is
uploaded to CurseForge once (`.github/workflows/release.yml`,
`Tools/package.py`, `Tools/curseforge_upload.py`).

## One-time setup

1. **Create the project** on the CurseForge authors site: World of Warcraft,
   Addon. Name it *Aegis: Pathfinder (Forever)*; category Quests & Leveling.
   Paste the description below (Markdown), and use `media/logo.tga` (as a
   PNG) for the avatar.
2. **Copy the project's ID** from its page (About this project → Project ID).
3. **Make an API token** on the authors site (your account's API tokens), named
   for this repository.
4. **On GitHub**, in the repository's *Settings → Secrets and variables →
   Actions*:
   - Secrets: `CF_API_KEY` = the token.
   - Variables: `CURSEFORGE_PROJECT_ID` = the ID. Optional:
     `CURSEFORGE_RELEASE_TYPE` = `beta` while it is in testing (the default is
     `release`), and `CURSEFORGE_GAME_VERSION_IDS` if the upload can't find
     the WoW: Forever game version by itself (its log says so).
5. **Upload the current version**: *Actions → Test and release → Run
   workflow*. After that, each merge to `main` with a new `## Version` (and a
   CHANGELOG entry) uploads once; merges that keep the version only refresh
   the GitHub release.

## Project description

```markdown
# Aegis: Pathfinder (Forever)

**The Pathfinder leveling guide, ported to WoW: Forever. Its guides are being written now, from the data players collect.**

> Built for **WoW: Forever** (client 1.60.1, Interface 16001). On Turtle WoW? Get *Aegis: Pathfinder* instead.

## What it does today

WoW: Forever is new, so there are no guides for it yet. Pathfinder brings everything else: the guide window, the guide browser, the settings, and a **data collector** that records what the guides will be written from.

**Turn it on, play, send it in.** Click **Start collecting data** (tick **Automatically run** and it starts at every login), play as you normally would, then press **Submit data**.

### What the collector records

- **The XP each level needs**, and how long each level took
- **Every quest** you're offered, accept and hand in: who gives it and where, its objectives and where they progress, who takes it back, and what it gives (XP at your level, money, item rewards and choices, spells, reputation)
- Quest chains, and the client's own map pins

Nothing is sent by itself. The data never names your realm, and characters are written as race, class and faction. The one name in it is the one you're credited under.

### Sending your data

**Submit data** (or `/apg submit`) packs everything into one line of text. Copy it and paste it in the **Submit collected data** form on GitHub, where a bot adds it and credits you, or in our Discord. Every contributor is listed in the game and on GitHub.

## Also in the box

- **Quest automation**: accepts and turns in quests and picks them from an NPC's list. Never a grey quest, never a reward choice. Hold Shift to skip one.
- **At the vendor**: sells greys and repairs, with your own money or the guild's
- **Reputation detail**: "Stormwind +25: Honored 4,350 / 12,000, 7,650 to Revered"
- **Level-ups**: tell your party, guild or everyone nearby with one click, with how long the level took
- **Two looks**: the Pathfinder themes (Day, Night, Pathfinder, OctoWoW, RavenCraft, Capybara Paradise, Aegis), or a **Blizzard skin** drawn with the game's own modern art
- Lock, transparency, opacity, text size, window scale, hiding in dungeons or combat

## Commands

| | |
|---|---|
| `/apg` | Show or hide the guide window |
| `/apg collect` | Data collection |
| `/apg submit` | Send your data |
| `/apg config` | Settings |
| `/apg resetpanels` | Put every window back |

The minimap button: click for the guide, shift-click for data collection, right-click for settings.

## Install

Use the CurseForge app, or unzip into `World of Warcraft/_classic_beta_/Interface/AddOns/` and keep the folder named `Aegis_Forever_Pathfinder`. Restart the game fully the first time.

## Help and feedback

Bugs, ideas and chat on our **[Discord](https://discord.gg/Hr66t25vE7)**. Source code and the data form on **[GitHub](https://github.com/Torchlite-bit/Aegis_Forever_Pathfinder)**.

## Credits

A port of **Aegis: Pathfinder**, which descends from TourGuide (Tekkub), VanillaGuide (isalcedo) and VanillaGuide-Plus (NostalgiaGeek, Brues). Fonts: Rajdhani and Inter (SIL Open Font License). Not made or endorsed by Blizzard Entertainment.
```

Summary line (the short one CurseForge asks for, 150 characters at most):

```
Leveling guide for WoW: Forever. Collects quest and XP data while you play, to write its guides from. Quest automation and a Blizzard skin included.
```
