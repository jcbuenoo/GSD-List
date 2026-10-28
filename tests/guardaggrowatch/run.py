import sys, os, json
HERE = os.path.dirname(os.path.abspath(__file__))
from lupa import lua51
api = json.load(open(os.path.join(HERE, 'api.json')))
L = lua51.LuaRuntime(unpack_returned_tuples=True)
G = L.globals()
real = L.table(); [real.__setitem__(m, True) for m in api['widget'] + ['SetOwner','AddLine']]
G.REAL_METHODS = real
L.execute(open(os.path.join(HERE, 'strict_mock.lua')).read())
addon = os.path.join(HERE, '..', '..', 'GuardAggroWatch')
script = os.path.join(HERE, sys.argv[1] if len(sys.argv) > 1 else 'tests.lua')
LOADER = '''
return function(files, dir)
  ENV = setmetatable({}, {
    __index = function(_, k) ACCESSED[k] = true; local v = W[k]
      if v == nil and k ~= "GetMinimapShape" and k ~= "GuardAggroWatchDB" then error("UNDEFINED GLOBAL READ: " .. tostring(k), 2) end
      return v end,
    __newindex = function(_, k, v) CREATED[k] = true; W[k] = v end })
  NS = {}
  for _, f in ipairs(files) do
    local fh = assert(io.open(dir .. "/" .. f)); local src = fh:read("*a"); fh:close()
    local chunk = assert(loadstring(src, f)); setfenv(chunk, ENV); chunk("GuardAggroWatch", NS)
  end
end'''
L.execute(LOADER)(L.table('Core.lua','Radar.lua','Minimap.lua','WorldMap.lua'), addon)
G.ADDON_DIR = addon
L.execute(open(script).read())
# global audit
verified = set(api['globals']) | set(api['ns']) | {'UIParent','Minimap','WorldMapFrame','DEFAULT_CHAT_FRAME','SlashCmdList','StaticPopupDialogs','YES','NO','SOUNDKIT','GameTooltip','math','string','table','pairs','ipairs','type','tonumber','tostring','select','error','time','date','GuardAggroWatchDB','GetMinimapShape'}
acc = sorted(k for k in L.globals().ACCESSED.keys())
created = sorted(k for k in L.globals().CREATED.keys())
print('Globals created:', created)
unver = [k for k in acc if k not in verified and k not in created]
# Engine functions Blizzard's own Lua never calls; they're relied on by HereBeDragons/TomTom and guarded in the addon
ENGINE_ONLY = {'GetPlayerFacing', 'IsIndoors'}
def unver_bad(u): return [k for k in u if k not in ENGINE_ONLY]
print('Globals read that are NOT found in Blizzard source/docs:', unver)

if (L.globals().TEST_FAILURES or 0) > 0 or unver_bad(unver):
    sys.exit(1)
