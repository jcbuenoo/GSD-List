# Runs Range Ring under real Lua 5.1 against the strict client mock shared with the GuardAggroWatch tests.
import sys, os, json
HERE = os.path.dirname(os.path.abspath(__file__))
SHARED = os.path.join(HERE, '..', 'guardaggrowatch')
from lupa import lua51
api = json.load(open(os.path.join(SHARED, 'api.json')))
L = lua51.LuaRuntime(unpack_returned_tuples=True)
G = L.globals()
real = L.table(); [real.__setitem__(m, True) for m in api['widget']]
G.REAL_METHODS = real
L.execute(open(os.path.join(SHARED, 'strict_mock.lua')).read())
L.execute(open(os.path.join(HERE, 'mock_extra.lua')).read())
addon = os.path.join(HERE, '..', '..', 'RangeRing')
LOADER = '''
return function(files, dir)
  ENV = setmetatable({}, {
    __index = function(_, k) ACCESSED[k] = true; local v = W[k]
      if v == nil and k ~= "RangeRingDB" then error("UNDEFINED GLOBAL READ: " .. tostring(k), 2) end
      return v end,
    __newindex = function(_, k, v) CREATED[k] = true; W[k] = v end })
  for _, f in ipairs(files) do
    local fh = assert(io.open(dir .. "/" .. f)); local src = fh:read("*a"); fh:close()
    local chunk = assert(loadstring(src, f)); setfenv(chunk, ENV); chunk("RangeRing", {})
  end
end'''
toc = [l.strip() for l in open(os.path.join(addon, 'RangeRing.toc')) if l.strip() and not l.startswith('#')]
for f in ['ring1.tga', 'ring2.tga', 'ring3.tga', 'ring4.tga', 'disc.tga', 'guide.tga']:
    assert os.path.exists(os.path.join(addon, 'media', f)), f
L.execute(LOADER)(L.table(*toc), addon)
L.execute(open(os.path.join(HERE, 'tests.lua')).read())
verified = set(api['globals']) | set(api['ns']) | {'UIParent','DEFAULT_CHAT_FRAME','SlashCmdList','math','string','table','pairs','ipairs','type','tonumber','tostring','select','error','pcall','RangeRingDB'}
acc = sorted(L.globals().ACCESSED.keys())
created = sorted(L.globals().CREATED.keys())
print('Globals created:', created)
unver = [k for k in acc if k not in verified and k not in created]
print('Globals read that are NOT found in Blizzard source/docs:', unver)
if (L.globals().TEST_FAILURES or 0) > 0 or unver:
    sys.exit(1)
