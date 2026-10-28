-- TBC PvP cooldowns.
-- cd     = base cooldown in seconds
-- adj    = common PvP talent reduction (applied when "talents" is on, the default),
--          so the bar never shows a spell as down when a specced enemy already has it back
-- ranks  = other spell IDs that trigger the same cooldown
-- talent = talent/faction spell, only shown once seen (never pre-filled as "ready")
-- race   = racial, pre-filled only for that race (englishRace from GetPlayerInfoByGUID)
-- pet    = cast by the pet; attributed to the owner in arena
-- IDs and durations cross-checked against OmniBar's TBC data (github.com/jordonwow/omnibar).
local _, ns = ...

-- Display order (left to right) and border colours.
ns.TYPES = {
    { key = "trinket",   color = { 1.00, 0.82, 0.00 } },
    { key = "racial",    color = { 0.85, 0.85, 0.85 } },
    { key = "interrupt", color = { 0.70, 0.30, 1.00 } },
    { key = "defensive", color = { 0.20, 0.90, 0.20 } },
    { key = "cc",        color = { 1.00, 0.20, 0.20 } },
    { key = "mobility",  color = { 0.20, 0.60, 1.00 } },
    { key = "offensive", color = { 1.00, 0.50, 0.00 } },
    { key = "utility",   color = { 0.50, 0.50, 0.50 } },
}

ns.SPELLS = {
    -- General. Medallion = 2 min, old level 60 Insignia = 5 min, same spell ID.
    -- 2 min is assumed (safer: you never think trinket is down when it is up); "/gcd trinket 300" to change.
    [42292] = { cd = 120, class = "GENERAL", type = "trinket" }, -- PvP Trinket

    -- Racials
    [7744]  = { cd = 120, class = "GENERAL", type = "racial", race = "Scourge" },  -- Will of the Forsaken
    [20589] = { cd = 105, class = "GENERAL", type = "racial", race = "Gnome" },    -- Escape Artist
    [20594] = { cd = 180, class = "GENERAL", type = "racial", race = "Dwarf" },    -- Stoneform
    [20549] = { cd = 120, class = "GENERAL", type = "racial", race = "Tauren" },   -- War Stomp
    [28730] = { cd = 120, class = "GENERAL", type = "racial", race = "BloodElf", ranks = { 25046 } }, -- Arcane Torrent
    [20600] = { cd = 180, class = "GENERAL", type = "racial", race = "Human" },    -- Perception
    [20554] = { cd = 180, class = "GENERAL", type = "racial", race = "Troll", ranks = { 26296, 26297 } }, -- Berserking
    [20572] = { cd = 120, class = "GENERAL", type = "racial", race = "Orc", ranks = { 33697, 33702 } },   -- Blood Fury
    [28880] = { cd = 180, class = "GENERAL", type = "racial", race = "Draenei" },  -- Gift of the Naaru

    -- Mage
    [2139]  = { cd = 24,  class = "MAGE", type = "interrupt" }, -- Counterspell
    [1953]  = { cd = 15,  class = "MAGE", type = "mobility", adj = -2 }, -- Blink
    [122]   = { cd = 25,  class = "MAGE", type = "cc", adj = -4, ranks = { 865, 6131, 10230, 27088 } }, -- Frost Nova
    [45438] = { cd = 300, class = "MAGE", type = "defensive", adj = -60, talent = true }, -- Ice Block
    [66]    = { cd = 300, class = "MAGE", type = "defensive" }, -- Invisibility
    [11426] = { cd = 30,  class = "MAGE", type = "defensive", adj = -6, talent = true, ranks = { 13031, 13032, 13033, 27134, 33405 } }, -- Ice Barrier
    [11958] = { cd = 480, class = "MAGE", type = "utility", adj = -96, talent = true }, -- Cold Snap
    [12472] = { cd = 180, class = "MAGE", type = "offensive", talent = true }, -- Icy Veins
    [31687] = { cd = 180, class = "MAGE", type = "offensive", talent = true }, -- Summon Water Elemental
    [12043] = { cd = 180, class = "MAGE", type = "offensive", talent = true }, -- Presence of Mind
    [12042] = { cd = 180, class = "MAGE", type = "offensive", talent = true }, -- Arcane Power
    [11129] = { cd = 180, class = "MAGE", type = "offensive", talent = true }, -- Combustion
    [31661] = { cd = 20,  class = "MAGE", type = "cc", talent = true, ranks = { 33041, 33042, 33043 } }, -- Dragon's Breath
    [11113] = { cd = 30,  class = "MAGE", type = "cc", talent = true, ranks = { 13018, 13019, 13020, 13021, 27133, 33933 } }, -- Blast Wave
    [12051] = { cd = 480, class = "MAGE", type = "utility" }, -- Evocation

    -- Rogue
    [1766]  = { cd = 10,  class = "ROGUE", type = "interrupt", ranks = { 1767, 1768, 1769, 38768 } }, -- Kick
    [1856]  = { cd = 300, class = "ROGUE", type = "defensive", adj = -90, ranks = { 1857, 26889 } }, -- Vanish
    [5277]  = { cd = 300, class = "ROGUE", type = "defensive", adj = -90, ranks = { 26669 } }, -- Evasion
    [31224] = { cd = 60,  class = "ROGUE", type = "defensive" }, -- Cloak of Shadows
    [2094]  = { cd = 180, class = "ROGUE", type = "cc", adj = -90 }, -- Blind
    [408]   = { cd = 20,  class = "ROGUE", type = "cc", ranks = { 8643 } }, -- Kidney Shot
    [1776]  = { cd = 10,  class = "ROGUE", type = "cc", adj = -1, ranks = { 1777, 8629, 11285, 11286, 38764 } }, -- Gouge
    [2983]  = { cd = 300, class = "ROGUE", type = "mobility", adj = -90, ranks = { 8696, 11305 } }, -- Sprint
    [36554] = { cd = 30,  class = "ROGUE", type = "mobility", talent = true }, -- Shadowstep
    [14185] = { cd = 600, class = "ROGUE", type = "utility", talent = true }, -- Preparation
    [14177] = { cd = 180, class = "ROGUE", type = "offensive", talent = true }, -- Cold Blood
    [13750] = { cd = 300, class = "ROGUE", type = "offensive", talent = true }, -- Adrenaline Rush
    [13877] = { cd = 120, class = "ROGUE", type = "offensive", talent = true }, -- Blade Flurry
    [14183] = { cd = 120, class = "ROGUE", type = "offensive", talent = true }, -- Premeditation

    -- Warrior
    [6552]  = { cd = 10,  class = "WARRIOR", type = "interrupt", ranks = { 6554 } }, -- Pummel
    [72]    = { cd = 12,  class = "WARRIOR", type = "interrupt", ranks = { 1671, 1672, 29704 } }, -- Shield Bash
    [23920] = { cd = 10,  class = "WARRIOR", type = "defensive" }, -- Spell Reflection
    [18499] = { cd = 30,  class = "WARRIOR", type = "defensive" }, -- Berserker Rage
    [871]   = { cd = 1800, class = "WARRIOR", type = "defensive", adj = -600 }, -- Shield Wall
    [20230] = { cd = 1800, class = "WARRIOR", type = "defensive", adj = -600 }, -- Retaliation
    [12975] = { cd = 480, class = "WARRIOR", type = "defensive", talent = true }, -- Last Stand
    [676]   = { cd = 60,  class = "WARRIOR", type = "cc" }, -- Disarm
    [5246]  = { cd = 180, class = "WARRIOR", type = "cc" }, -- Intimidating Shout
    [12809] = { cd = 45,  class = "WARRIOR", type = "cc", talent = true }, -- Concussion Blow
    [100]   = { cd = 15,  class = "WARRIOR", type = "mobility", ranks = { 6178, 11578 } }, -- Charge
    [20252] = { cd = 30,  class = "WARRIOR", type = "mobility", adj = -15, ranks = { 20616, 20617, 25272, 25275 } }, -- Intercept
    [3411]  = { cd = 30,  class = "WARRIOR", type = "mobility" }, -- Intervene
    [12292] = { cd = 180, class = "WARRIOR", type = "offensive", talent = true }, -- Death Wish
    [1719]  = { cd = 1800, class = "WARRIOR", type = "offensive", adj = -600 }, -- Recklessness
    [12328] = { cd = 30,  class = "WARRIOR", type = "offensive", talent = true }, -- Sweeping Strikes

    -- Paladin
    [642]   = { cd = 300, class = "PALADIN", type = "defensive", ranks = { 1020 } }, -- Divine Shield
    [498]   = { cd = 300, class = "PALADIN", type = "defensive", ranks = { 5573 } }, -- Divine Protection
    [1022]  = { cd = 300, class = "PALADIN", type = "defensive", adj = -120, ranks = { 5599, 10278 } }, -- Blessing of Protection
    [6940]  = { cd = 30,  class = "PALADIN", type = "defensive", ranks = { 20729, 27147, 27148 } }, -- Blessing of Sacrifice
    [633]   = { cd = 3600, class = "PALADIN", type = "defensive", adj = -1200, ranks = { 2800, 10310, 27154 } }, -- Lay on Hands
    [853]   = { cd = 60,  class = "PALADIN", type = "cc", adj = -15, ranks = { 5588, 5589, 10308 } }, -- Hammer of Justice
    [20066] = { cd = 60,  class = "PALADIN", type = "cc", talent = true }, -- Repentance
    [1044]  = { cd = 25,  class = "PALADIN", type = "mobility" }, -- Blessing of Freedom
    [31884] = { cd = 180, class = "PALADIN", type = "offensive" }, -- Avenging Wrath
    [20216] = { cd = 120, class = "PALADIN", type = "utility", talent = true }, -- Divine Favor
    [31842] = { cd = 180, class = "PALADIN", type = "utility", talent = true }, -- Divine Illumination

    -- Priest
    [15487] = { cd = 45,  class = "PRIEST", type = "interrupt", talent = true }, -- Silence
    [33206] = { cd = 120, class = "PRIEST", type = "defensive", talent = true }, -- Pain Suppression
    [6346]  = { cd = 180, class = "PRIEST", type = "defensive" }, -- Fear Ward
    [586]   = { cd = 30,  class = "PRIEST", type = "defensive", adj = -6, ranks = { 9578, 9579, 9592, 10941, 10942, 25429 } }, -- Fade
    [13908] = { cd = 600, class = "PRIEST", type = "defensive", talent = true, ranks = { 19236, 19238, 19240, 19241, 19242, 19243, 25437 } }, -- Desperate Prayer
    [8122]  = { cd = 30,  class = "PRIEST", type = "cc", adj = -3, ranks = { 8124, 10888, 10890 } }, -- Psychic Scream
    [44041] = { cd = 30,  class = "PRIEST", type = "cc", talent = true, ranks = { 44043, 44044, 44045, 44046, 44047 } }, -- Chastise
    [10060] = { cd = 180, class = "PRIEST", type = "offensive", talent = true }, -- Power Infusion
    [34433] = { cd = 300, class = "PRIEST", type = "offensive" }, -- Shadowfiend
    [14751] = { cd = 180, class = "PRIEST", type = "utility", talent = true }, -- Inner Focus

    -- Warlock
    [19244] = { cd = 24,  class = "WARLOCK", type = "interrupt", pet = true, talent = true, ranks = { 19647 } }, -- Spell Lock (Felhunter)
    [6229]  = { cd = 30,  class = "WARLOCK", type = "defensive", ranks = { 11739, 11740, 28610 } }, -- Shadow Ward
    [6789]  = { cd = 120, class = "WARLOCK", type = "cc", ranks = { 17925, 17926, 27223 } }, -- Death Coil
    [5484]  = { cd = 40,  class = "WARLOCK", type = "cc", ranks = { 17928 } }, -- Howl of Terror
    [30283] = { cd = 20,  class = "WARLOCK", type = "cc", talent = true, ranks = { 30413, 30414 } }, -- Shadowfury
    [18708] = { cd = 900, class = "WARLOCK", type = "utility", talent = true }, -- Fel Domination
    [18288] = { cd = 180, class = "WARLOCK", type = "offensive", talent = true }, -- Amplify Curse

    -- Shaman (Earth Shock ranks include Frost/Flame Shock: shared shock cooldown)
    [8042]  = { cd = 6,   class = "SHAMAN", type = "interrupt", adj = -1, ranks = { 8044, 8045, 8046, 10412, 10413, 10414, 25454, 8050, 8052, 8053, 10447, 10448, 29228, 25457, 8056, 8058, 10472, 10473, 25464 } }, -- Earth Shock
    [8177]  = { cd = 15,  class = "SHAMAN", type = "defensive", adj = -2 }, -- Grounding Totem
    [30823] = { cd = 120, class = "SHAMAN", type = "defensive", talent = true }, -- Shamanistic Rage
    [2484]  = { cd = 15,  class = "SHAMAN", type = "cc" }, -- Earthbind Totem
    [16188] = { cd = 180, class = "SHAMAN", type = "utility", talent = true }, -- Nature's Swiftness
    [16190] = { cd = 300, class = "SHAMAN", type = "utility", talent = true }, -- Mana Tide Totem
    [16166] = { cd = 180, class = "SHAMAN", type = "offensive", talent = true }, -- Elemental Mastery
    [2825]  = { cd = 600, class = "SHAMAN", type = "offensive", talent = true }, -- Bloodlust (Horde)
    [32182] = { cd = 600, class = "SHAMAN", type = "offensive", talent = true }, -- Heroism (Alliance)
    [2894]  = { cd = 1200, class = "SHAMAN", type = "offensive" }, -- Fire Elemental Totem

    -- Druid
    [16979] = { cd = 15,  class = "DRUID", type = "interrupt", talent = true }, -- Feral Charge
    [22812] = { cd = 60,  class = "DRUID", type = "defensive" }, -- Barkskin
    [22842] = { cd = 180, class = "DRUID", type = "defensive", ranks = { 22895, 22896, 26999 } }, -- Frenzied Regeneration
    [5211]  = { cd = 60,  class = "DRUID", type = "cc", ranks = { 6798, 8983 } }, -- Bash
    [16689] = { cd = 60,  class = "DRUID", type = "cc", talent = true, ranks = { 16810, 16811, 16812, 16813, 17329, 27009 } }, -- Nature's Grasp
    [1850]  = { cd = 300, class = "DRUID", type = "mobility", ranks = { 9821, 33357 } }, -- Dash
    [17116] = { cd = 180, class = "DRUID", type = "utility", talent = true }, -- Nature's Swiftness
    [29166] = { cd = 360, class = "DRUID", type = "utility" }, -- Innervate
    [33831] = { cd = 180, class = "DRUID", type = "offensive", talent = true }, -- Force of Nature

    -- Hunter (Frost Trap shares the Freezing Trap cooldown)
    [34490] = { cd = 20,  class = "HUNTER", type = "interrupt", talent = true }, -- Silencing Shot
    [19263] = { cd = 300, class = "HUNTER", type = "defensive", talent = true }, -- Deterrence
    [5384]  = { cd = 30,  class = "HUNTER", type = "defensive" }, -- Feign Death
    [19503] = { cd = 30,  class = "HUNTER", type = "cc", talent = true }, -- Scatter Shot
    [1499]  = { cd = 30,  class = "HUNTER", type = "cc", adj = -6, ranks = { 14310, 14311, 13809 } }, -- Freezing Trap
    [19386] = { cd = 120, class = "HUNTER", type = "cc", talent = true, ranks = { 24132, 24133, 27068 } }, -- Wyvern Sting
    [19577] = { cd = 60,  class = "HUNTER", type = "cc", talent = true }, -- Intimidation
    [19574] = { cd = 120, class = "HUNTER", type = "offensive", talent = true }, -- Bestial Wrath
    [3045]  = { cd = 300, class = "HUNTER", type = "offensive", adj = -120 }, -- Rapid Fire
    [23989] = { cd = 300, class = "HUNTER", type = "utility", talent = true }, -- Readiness
    [1543]  = { cd = 20,  class = "HUNTER", type = "utility" }, -- Flare
}

-- Casting the key spell finishes the listed cooldowns. "CLASS" = every spell of that class.
ns.RESETS = {
    [11958] = { 11426, 6143, 122, 45438, 12472, 31687 }, -- Cold Snap
    [14185] = { 5277, 2983, 1856, 14177, 36554, 14183 },  -- Preparation
    [23989] = "HUNTER",                                   -- Readiness
    [691]   = { 19244 },                                  -- Summon Felhunter resets Spell Lock
}
