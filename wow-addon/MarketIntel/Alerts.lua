-- Market Intel: alerts. Chat lines and a sound for everything; for big finds
-- (strong alerts) also a raid-warning style message in the middle of the
-- screen and a flashing taskbar icon when the game is in the background.
local _, ns = ...

local AL = {}
ns.Alerts = AL

local lastSound, lastStrong = 0, 0
AL.unseen = 0 -- alerts since the window was last opened (shown on the minimap button)

AL.SOUNDS = {
	{ id = "raidwarning", label = "Raid warning", kit = 8959 },
	{ id = "readycheck", label = "Ready check", kit = 8960 },
	{ id = "auction", label = "Auction bell", kit = 5274 },
	{ id = "levelup", label = "Level up", kit = 888 },
}

local function SoundKit(id)
	for _, s in ipairs(AL.SOUNDS) do
		if s.id == id then return s.kit end
	end
	return 8959
end

-- kind: "deals", "snipe", ... (also the /mi command that lists them)
-- lines: chat lines; strong: true for big finds; headline: short text for the screen message
function AL.Notify(kind, lines, strong, headline)
	if #lines == 0 then return end
	local s = ns.settings
	if s.alertChat then
		for i, line in ipairs(lines) do
			if i > 5 then
				ns.Print("...and %d more. Type /mi %s to see them all.", #lines - 5, kind)
				break
			end
			ns.Print(line)
		end
	end
	local now = GetTime()
	if s.alertSound and now - lastSound > 3 then
		lastSound = now
		PlaySound(SoundKit(strong and s.strongSound or s.alertSoundChoice), "Master")
	end
	if strong and now - lastStrong > 5 then
		lastStrong = now
		if s.alertRaidWarning and RaidNotice_AddMessage and RaidWarningFrame then
			local color = ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.3, b = 0.1 }
			RaidNotice_AddMessage(RaidWarningFrame, "Market Intel: " .. (headline or lines[1]), color)
		end
		if s.alertFlash and FlashClientIcon then FlashClientIcon() end
	end
	if not (ns.UI and ns.UI.IsShown()) then AL.unseen = AL.unseen + #lines end
	ns.Fire("MI_ALERT", kind, #lines, strong)
end

function AL.ClearUnseen()
	AL.unseen = 0
	ns.Fire("MI_ALERT")
end
