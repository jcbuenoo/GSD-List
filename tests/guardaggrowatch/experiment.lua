fire("ADDON_LOADED", "GuardAggroWatch"); fire("PLAYER_LOGIN")
local GAW = W.GuardAggroWatch; local slash = W.SlashCmdList.GUARDAGGROWATCH
-- Lay out a gate: two stationary guards 30 yd apart, one level 72 guard further in, a blind spot between
local function at(a, b) P.a, P.b = a, b end
at(1000, 500); UNITS.target = {name="Stormwind City Guard", level=70, guid="g1"}; slash("guard")
at(1000, 470); slash("guard")
at(1040, 485); UNITS.target = {name="Stormwind Royal Guard", level=73, guid="g3"}; slash("guard"); UNITS.target = nil
at(970, 485); slash("safe behind the pillar")
at(985, 455); slash("edge")
FRAMES = {}
local function snap(label)
  CLOCK = CLOCK + 5; TICK()
  local r = W.GuardAggroWatchRadar
  local items = {}
  local function walk(f)
    for _, c in ipairs(f._children) do
      if c._kind == "Texture" and c._shown and rawget(c, "_tex") and c._points[1] then
        local p = c._points[1]
        items[#items+1] = {tex=c._tex, x=p[4], y=p[5], w=c._w, h=c._h, color=rawget(c, "_color") or {1,1,1,1}, rot=rawget(c, "_rot") or 0, layer=rawget(c, "_layer")}
      end
      walk(c)
    end
  end
  walk(r)
  local txt = {}
  for _, c in ipairs(r._children) do if c._kind == "FontString" and rawget(c, "_text") then txt[#txt+1] = c._text end end
  FRAMES[#FRAMES+1] = {label=label, items=items, text=txt, sounds=table.concat(SOUNDS, ","), flash=GAW.flash:IsShown()}
  SOUNDS = {}
end
-- walk the rogue in from the south toward the gap between the two gate guards
P.facing = 0; CLOCK = CLOCK + 10; TICK(); SOUNDS = {}
at(940, 485); snap("1. Approaching from the south (facing north)")
at(970.5, 485); snap("2. On the blind spot")
at(984, 485); snap("3. Creeping toward the gap")
at(992, 485); snap("4. Crossed into the overlap")
P.facing = math.pi / 2; at(970.5, 485); snap("5. Back on the blind spot, facing west (radar turns)")
