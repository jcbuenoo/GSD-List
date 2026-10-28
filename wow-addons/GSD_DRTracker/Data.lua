-- TBC diminishing returns data.
-- Spell IDs and categories are taken from DRList-1.0 (MIT, by Wardz), TBC section:
-- https://github.com/wardz/DRList-1.0
local _, ns = ...

-- Seconds after a CC fades before its DR category resets. TBC is 15-20s;
-- 20 is the safe assumption (DRList uses the same value).
ns.RESET_TIME = 20

-- Display order, short label (max 6 chars so labels fit under 24px+ icons), and what shares the category.
-- Rogue-relevant categories come first.
ns.CATEGORIES = {
    { key = "stun",         label = "Stun",       desc = "Cheap Shot, HoJ, Bash, Pounce, Intercept, Charge, Shadowfury, Concussion Blow, Intimidation, War Stomp" },
    { key = "kidney_shot",  label = "Kidney",     desc = "Kidney Shot only (separate from Cheap Shot in TBC)" },
    { key = "incapacitate", label = "Incap",      desc = "Sap, Gouge, Polymorph, Repentance, Freezing Trap, Wyvern Sting, Maim, Hibernate, Banish" },
    { key = "disorient",    label = "Blind",      desc = "Blind, Cyclone" },
    { key = "fear",         label = "Fear",       desc = "Fear, Psychic Scream, Howl of Terror, Seduction, Intimidating Shout, Scare Beast, Turn Evil" },
    { key = "random_stun",  label = "RStun",      desc = "Impact, Mace Spec, Blackout, Improved Concussive Shot, Seal of Justice, Stoneclaw" },
    { key = "root",         label = "Root",       desc = "Frost Nova, Entangling Roots, Nature's Grasp, Freeze (Water Elemental)" },
    { key = "random_root",  label = "RRoot",      desc = "Frostbite, Entrapment, Improved Hamstring, Improved Wing Clip" },
    { key = "scatter",      label = "Scat",       desc = "Scatter Shot, Dragon's Breath" },
    { key = "death_coil",   label = "Coil",       desc = "Death Coil only" },
    { key = "mind_control", label = "MC",         desc = "Mind Control" },
    { key = "disarm",       label = "Disarm",     desc = "Disarm, Riposte" },
    { key = "counterattack",label = "CAtk",       desc = "Counterattack only" },
    { key = "chastise",     label = "Chast",      desc = "Chastise only" },
    { key = "unstable_affliction", label = "UA",  desc = "Unstable Affliction silence" },
}

-- Preset for the "/gdr preset rogue" command.
ns.ROGUE_PRESET = { stun = true, kidney_shot = true, incapacitate = true, disorient = true }

-- [category] = spell IDs (all ranks), one line per spell
local SPELLS_BY_CATEGORY = {
    incapacitate = {
        2637, 18657, 18658,                     -- Hibernate
        22570,                                  -- Maim
        3355, 14308, 14309,                     -- Freezing Trap Effect
        19386, 24132, 24133, 27068,             -- Wyvern Sting
        118, 12824, 12825, 12826, 28271, 28272, -- Polymorph (incl. Turtle, Pig)
        20066,                                  -- Repentance
        6770, 2070, 11297,                      -- Sap
        1776, 1777, 8629, 11285, 11286, 38764,  -- Gouge
        710, 18647,                             -- Banish
        13327,                                  -- Reckless Charge (item)
        4064, 4065, 4066, 4067, 4068, 12421, 4069, 12562, 12543, 19769, 19784, 30216, 30461, 30217, -- Engineering bombs
    },
    disorient = {
        33786, -- Cyclone
        2094,  -- Blind
    },
    stun = {
        5211, 6798, 8983,                -- Bash
        9005, 9823, 9827, 27006,         -- Pounce
        24394,                           -- Intimidation
        853, 5588, 5589, 10308,          -- Hammer of Justice
        1833,                            -- Cheap Shot
        30283, 30413, 30414,             -- Shadowfury
        12809,                           -- Concussion Blow
        7922,                            -- Charge Stun
        20253, 20614, 20615, 25273, 25274, -- Intercept Stun
        20549,                           -- War Stomp
        13237, 835,                      -- Goblin Mortar, Tidal Charm (items)
    },
    random_stun = {
        16922, -- Celestial Focus (Starfire Stun)
        19410, -- Improved Concussive Shot
        12355, -- Impact
        20170, -- Seal of Justice Stun
        15269, -- Blackout
        18093, -- Pyroclasm
        39796, -- Stoneclaw Stun
        12798, -- Revenge Stun
        5530,  -- Mace Stun Effect
        15283, 56, 34510, -- Weapon procs (Stunning Blow, Stun, Stormherald/Deep Thunder)
    },
    fear = {
        1513, 14326, 14327,          -- Scare Beast
        10326,                       -- Turn Evil
        8122, 8124, 10888, 10890,    -- Psychic Scream
        5782, 6213, 6215,            -- Fear
        6358,                        -- Seduction
        5484, 17928,                 -- Howl of Terror
        5246,                        -- Intimidating Shout
        5134,                        -- Flash Bomb Fear (item)
    },
    root = {
        339, 1062, 5195, 5196, 9852, 9853, 26989,          -- Entangling Roots
        19975, 19974, 19973, 19972, 19971, 19970, 27010,   -- Nature's Grasp
        122, 865, 6131, 10230, 27088,                      -- Frost Nova
        33395,                                             -- Freeze (Water Elemental)
        39965,                                             -- Frost Grenade (item)
    },
    random_root = {
        19185, -- Entrapment
        19229, -- Improved Wing Clip
        12494, -- Frostbite
        23694, -- Improved Hamstring
    },
    mind_control = {
        605, 10911, 10912, -- Mind Control
        13181,             -- Gnomish Mind Control Cap (item)
    },
    disarm = {
        14251, 34097, -- Riposte (two IDs)
        676,          -- Disarm
    },
    scatter = {
        19503,                      -- Scatter Shot
        31661, 33041, 33042, 33043, -- Dragon's Breath
    },
    -- Spells that only DR with themselves
    counterattack       = { 19306, 20909, 20910, 27067 },               -- Counterattack
    chastise            = { 44041, 44043, 44044, 44045, 44046, 44047 }, -- Chastise
    kidney_shot         = { 408, 8643 },                                -- Kidney Shot
    unstable_affliction = { 43523, 31117 },                             -- Unstable Affliction silence
    death_coil          = { 6789, 17925, 17926, 27223 },                -- Death Coil
}

ns.SPELLS = {} -- [spellID] = category
for cat, ids in pairs(SPELLS_BY_CATEGORY) do
    for _, id in ipairs(ids) do ns.SPELLS[id] = cat end
end
