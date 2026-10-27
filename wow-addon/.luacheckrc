std = "lua51"
max_line_length = false
exclude_files = { "tests/**" }
-- globals the addon defines
globals = { "MarketIntelDB", "SLASH_MARKETINTEL1", "SLASH_MARKETINTEL2", "SlashCmdList", "StaticPopupDialogs" }
-- WoW API / FrameXML used by the addon (TBC Classic)
read_globals = {
	"date", "time", "wipe", "tinsert", "hooksecurefunc", "geterrorhandler", "CreateFrame", "UIParent", "GetTime",
	"DEFAULT_CHAT_FRAME", "GetItemInfo", "GetItemIcon", "ITEM_QUALITY_COLORS", "UnitFactionGroup", "UnitName",
	"GetRealmName", "C_Map", "C_Container", "GetContainerNumSlots", "GetContainerItemLink", "StaticPopup_Show",
	"YES", "NO", "PlaySound", "SOUNDKIT", "Auctionator", "TSM_API", "CanSendAuctionQuery", "QueryAuctionItems",
	"AuctionFrameTab1", "AuctionFrameTab_OnClick", "BrowseName", "NUM_AUCTION_ITEMS_PER_PAGE",
	"GetAuctionItemInfo", "GetAuctionItemLink", "GetNumAuctionItems", "TooltipDataProcessor", "Enum",
	"GameTooltip", "ItemRefTooltip", "BackdropTemplateMixin", "AUCTIONATOR_PRICE_DATABASE", "ChatEdit_InsertLink", "FauxScrollFrame_OnVerticalScroll",
	"FauxScrollFrame_Update", "FauxScrollFrame_GetOffset", "IsShiftKeyDown", "UISpecialFrames", "AuctionFrame",
	"_G", "debugprofilestop", "RaidNotice_AddMessage", "RaidWarningFrame", "ChatTypeInfo", "FlashClientIcon",
	"GetItemInfoInstant", "AUCTION_SOLD_MAIL_SUBJECT", "AUCTION_WON_MAIL_SUBJECT", "AUCTION_EXPIRED_MAIL_SUBJECT",
	"AUCTION_REMOVED_MAIL_SUBJECT", "GetInboxNumItems", "GetInboxHeaderInfo", "GetInboxInvoiceInfo", "GetInboxItem",
	"GetNumTradeSkills", "GetTradeSkillLine", "GetTradeSkillInfo", "GetTradeSkillRecipeLink", "GetTradeSkillItemLink",
	"GetTradeSkillNumMade", "GetTradeSkillNumReagents", "GetTradeSkillReagentInfo", "GetTradeSkillReagentItemLink",
	"GetNumCrafts", "GetCraftDisplaySkillLine", "GetCraftInfo", "GetCraftItemLink", "GetCraftNumReagents",
	"GetCraftReagentInfo", "GetCraftReagentItemLink", "TradeSkillMasterDB", "Minimap", "GetCursorPosition",
	"ChatFontNormal", "CLOSE", "AUCTIONATOR_VENDOR_PRICE_CACHE",
}
self = false
