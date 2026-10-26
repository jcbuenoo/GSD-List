"""Run a Lua test file against the WoW API mock under Lua 5.1.

Usage: python3 run.py <addons_dir> <test_file.lua>
"""
import os
import sys

import lupa.lua51 as lua51

lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.globals().ADDONS = sys.argv[1]
lua.execute('dofile(%r)' % os.path.join(os.path.dirname(sys.argv[2]), "mock.lua"))
lua.execute('dofile(%r)' % sys.argv[2])
