local _, AP = ...

--[[
	The words on screen. English only for now: a key with no entry is shown as
	itself, so a missing line reads as its key instead of raising an error.
]]
local L = setmetatable({}, { __index = function(_, key) return key end })
AP.L = L

L.TITLE = "Aegis: Pathfinder"
L.SHORT = "Pathfinder"

L.LOADED = "%s v%s loaded -- /apg"
L.SLASH_HELP = "/apg -- the guide window. /apg collect -- data collection. /apg config -- settings. "
	.. "/apg browser -- the guide browser. /apg export -- copy what was collected. /apg resetpanels -- "
	.. "put the windows back. /apg minimapbutton -- show or hide the minimap button."

-- The guide window with no guide in it.
L.NO_GUIDES_TITLE = "No guides yet"
L.NO_GUIDES_BODY = "WoW: Forever is new, so Pathfinder has no guides for it yet. Help write them: "
	.. "switch on data collection and play as you normally would. Pathfinder writes down every quest "
	.. "you pick up, finish and hand in, and what it gave you."
L.START_COLLECTING = "Start collecting data"
L.STOP_COLLECTING = "Stop collecting data"
L.OPEN_COLLECTOR = "Data collection"

-- The data collection window.
L.COLLECTOR_TITLE = "Data collection"
L.COLLECTOR_ON = "Collecting"
L.COLLECTOR_OFF = "Not collecting"
L.COLLECTOR_AUTO = "Automatically run"
L.COLLECTOR_AUTO_NOTE = "Starts collecting by itself every time this character logs in."
L.COLLECTOR_EXPORT = "Export"
L.COLLECTOR_CLEAR = "Clear data"
L.COLLECTOR_CLEAR_CONFIRM = "Delete everything Pathfinder has collected, on every character? This cannot be undone."
L.COLLECTOR_EXPORT_HINT = "Ctrl+A, then Ctrl+C to copy. Paste it in the Discord or a GitHub issue."
L.COLLECTOR_STATS = "%s, %d turned in, %s"
L.COLLECTOR_STARTED = "Data collection started."
L.COLLECTOR_STOPPED = "Data collection stopped."
L.COLLECTOR_CLEARED = "Collected data cleared."
L.COLLECTOR_LOG_EMPTY = "Nothing yet. Pick up a quest."
L.LOG_QUEST_OFFERED = "Offered: %s"
L.LOG_QUEST_ACCEPTED = "Accepted: %s"
L.LOG_QUEST_PROGRESS = "Progress: %s"
L.LOG_QUEST_TURNED_IN = "Turned in: %s (%s XP)"
L.LOG_LEVEL = "Level %d: %s XP to the next"
L.LOG_REPUTATION = "%s +%d (%s)"

L.RELOAD_FOR_SKIN = "The Blizzard skin is drawn when the windows are built. Reload the interface now?"
L.RELOAD = "Reload"
L.LATER = "Later"
