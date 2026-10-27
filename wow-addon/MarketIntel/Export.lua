-- Market Intel: CSV export. Shows the CSV text in a box, already selected,
-- so Ctrl+C copies it; paste it into a spreadsheet.
local _, ns = ...

local E = {}
ns.Export = E

local MAX_ROWS = 5000 -- a bigger text box gets slow in the game
local frame

local function Cell(v)
	if v == nil then return "" end
	if type(v) == "number" then
		if v % 1 == 0 then return tostring(v) end
		if math.abs(v) >= 100 then return tostring(math.floor(v + 0.5)) end -- copper amounts
		return string.format("%.4f", v) -- ratios and rates
	end
	v = tostring(v):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	if v:find('[,"\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
	return v
end

-- header = { "col", ... }; rows = { { v, v, ... }, ... }
function E.ToCSV(header, rows)
	local lines = {}
	local h = {}
	for i, v in ipairs(header) do h[i] = Cell(v) end
	lines[1] = table.concat(h, ",")
	for r = 1, math.min(#rows, MAX_ROWS) do
		local row, out = rows[r], {}
		for i = 1, #header do out[i] = Cell(row[i]) end
		lines[#lines + 1] = table.concat(out, ",")
	end
	return table.concat(lines, "\n"), #rows > MAX_ROWS
end

local function Create()
	frame = CreateFrame("Frame", "MarketIntelExportFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetSize(620, 420)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	end
	tinsert(UISpecialFrames, "MarketIntelExportFrame")
	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.title:SetPoint("TOP", 0, -16)
	frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.hint:SetPoint("BOTTOMLEFT", 20, 18)
	frame.hint:SetWidth(460)
	frame.hint:SetJustifyH("LEFT")
	local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	close:SetSize(90, 22)
	close:SetPoint("BOTTOMRIGHT", -18, 14)
	close:SetText(CLOSE or "Close")
	close:SetScript("OnClick", function() frame:Hide() end)

	local scroll = CreateFrame("ScrollFrame", "MarketIntelExportScroll", frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 20, -40)
	scroll:SetPoint("BOTTOMRIGHT", -38, 44)
	local edit = CreateFrame("EditBox", nil, scroll)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(550)
	edit:SetScript("OnEscapePressed", function() frame:Hide() end)
	-- keep the text read-only: typing puts the original back
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput and frame.text then
			self:SetText(frame.text)
			self:HighlightText()
		end
	end)
	scroll:SetScrollChild(edit)
	frame.edit = edit
end

function E.Show(title, header, rows)
	if not frame then Create() end
	local text, cut = E.ToCSV(header, rows)
	frame.text = text
	frame.title:SetText("Export: " .. title)
	frame.hint:SetText(string.format("%d rows%s. Press Ctrl+C to copy, then paste into a spreadsheet.",
		math.min(#rows, MAX_ROWS), cut and string.format(" (first %d of %d)", MAX_ROWS, #rows) or ""))
	frame.edit:SetText(text)
	frame:Show()
	frame.edit:SetFocus()
	frame.edit:HighlightText()
end

function E.GetFrame() return frame end
