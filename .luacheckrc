std = "lua51"
max_line_length = 120
ignore = { "432" } -- shadowing `self` in script handlers is idiomatic WoW code
files["tests/"] = { allow_defined_top = true, globals = { "_G" }, ignore = { "111", "112", "113", "121", "122", "212" } }
files["GSDList/"] = {
    globals = { "GSDListDB", "SLASH_GSDLIST1", "SLASH_GSDLIST2", "SlashCmdList", "StaticPopupDialogs", "UISpecialFrames" },
    read_globals = {
        "ACCEPT", "BackdropTemplateMixin", "C_Timer", "CANCEL", "ChatEdit_InsertLink", "ChatFontNormal", "ChatFontSmall",
        "ChatFrameUtil", "CreateFont", "CreateFrame", "GameFontDisableSmall", "GameFontHighlight",
        "GameFontHighlightSmall", "GameFontNormalSmall", "IsShiftKeyDown", "MenuResponse", "MenuUtil", "NO",
        "ScrollingEdit_SetCursorOffsets", "StaticPopup_Show", "YES",
        "DEFAULT_CHAT_FRAME", "GameTooltip", "GetCursorPosition", "GRAY_FONT_COLOR", "HIGHLIGHT_FONT_COLOR",
        "hooksecurefunc", "Minimap", "NORMAL_FONT_COLOR_CODE", "PlaySound", "ScrollingEdit_OnCursorChanged",
        "ScrollingEdit_OnTextChanged", "ScrollingEdit_OnUpdate", "SOUNDKIT", "strlower", "strtrim", "tinsert",
        "tremove", "UIParent",
    },
}
