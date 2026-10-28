# Builds the list of real widget methods and global API names for the anniversary client
import re, os, json, glob
import sys
root = sys.argv[1] if len(sys.argv) > 1 else 'wow-ui-source/Interface/AddOns'
docs = glob.glob(root + '/Blizzard_APIDocumentationGenerated/*.lua')
widget, globals_, ns = set(), set(), set()
for f in docs:
    src = open(f, encoding='utf-8', errors='ignore').read()
    m = re.search(r'Namespace\s*=\s*"([^"]+)"', src)
    base = os.path.basename(f)
    is_widget = base.startswith(('Simple', 'FrameAPI', 'SharedScriptObject', 'MinimapFrameAPI')) or re.search(r'Type\s*=\s*"ScriptObject"', src)
    names = re.findall(r'Name\s*=\s*"(\w+)",\s*\n\s*Type\s*=\s*"Function"', src)
    if is_widget:
        widget.update(names)
    elif m:
        ns.add(m.group(1).split('.')[0])
    else:
        globals_.update(names)
# globals called anywhere in Blizzard's own Lua (proves they exist on this client)
used = set()
for f in glob.glob(root + '/**/*.lua', recursive=True):
    if 'Documentation' in f: continue
    used.update(re.findall(r'(?<![\w.:])([A-Za-z_]\w*)\s*\(', open(f, encoding='utf-8', errors='ignore').read()))
json.dump({'widget': sorted(widget), 'globals': sorted(globals_ | used), 'ns': sorted(ns)}, open('api.json', 'w'))
print(len(widget), 'widget methods;', len(globals_ | used), 'global funcs;', len(ns), 'namespaces')
for n in ['SetClipsChildren','SetRotation','SetColorTexture','HookScript','RegisterUnitEvent','SetBlendMode','GetZoom','SetZoom','StartMoving','SetClampedToScreen','RegisterForDrag','SetFrameStrata','SetVertexColor','GetEffectiveScale']:
    print(n, n in widget)
