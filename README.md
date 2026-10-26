# GSD-List
GSD List

## GSD List — WoW TBC Classic addon

A lightweight in-game notepad with an optional to-do list. It uses only the
game's own art, fonts and frame templates, so it looks like the stock UI.
It has no libraries or external files.

### Install

1. Download `release/GSDList-v1.2.0.zip`.
2. Extract it into your AddOns folder so that you end up with:

```
World of Warcraft/_anniversary_/Interface/AddOns/GSDList/GSDList.toc
World of Warcraft/_anniversary_/Interface/AddOns/GSDList/GSDList.lua
```

Use `_classic_` instead of `_anniversary_` if that's the folder your TBC client uses.
If the AddOns screen says "Out of date", tick **Load out of date AddOns**.

### Use

- **Minimap icon**: left-click toggles the notepad, right-click opens the to-do list, drag moves the icon around the minimap.
- **Notes**: type freely. Notes save when you click away, switch tabs, close the window, `/reload` or log out. Shift-click an item, spell or quest to paste its link.
- **To-Do**: type a task and press Enter or click **Add**. Tick a task to complete it; it disappears on its own a moment later (untick it quickly to keep it). **Drag** a task up or down to reorder it; a gold line shows where it will land, and the list scrolls if you drag past its edge. Click the X to delete a task. Hover over a long task to see its full text.
- Untick **Enable To-Do List** at the bottom to use the window as a notepad only.
- Drag the window by its border to move it. Drag the bottom-right corner to resize it. Press Escape to close it.

### Slash commands

| Command | Action |
| --- | --- |
| `/gsd` | Toggle the window |
| `/gsd todo` | Turn the to-do list on or off |
| `/gsd minimap` | Show or hide the minimap icon |
| `/gsd reset` | Reset the window and icon positions |
| `/gsd help` | List the commands |

Notes and tasks are shared by every character on the account (`SavedVariables: GSDListDB`).

### Performance

- At login it creates only the minimap button. The window is built the first time you open it.
- Nothing runs every frame. The notepad checks the cursor's scroll position only while you are typing, and the minimap button only while you drag it.
- Notes save at focus loss, close, `/reload` or logout, not on every keystroke.
- To-do rows are pooled and reused, and all rows share one set of handlers.
- Dragging a task runs a per-frame update only while the drag is in progress.

### Development

```
lua5.1 tests/run_tests.lua   # 32 functional tests against a mocked WoW API
luacheck GSDList tests       # lint (config in .luacheckrc)
```

The templates, functions and textures it uses were checked against Blizzard's 2.5.6 (TBC Anniversary) UI source.

### Changelog

- **1.2.0**
  - Ticked tasks now clear themselves after 0.6 seconds, so the **Clear Completed** button is gone.
  - Reorder tasks by dragging; the up/down arrows are gone.
  - The counter now shows the number of tasks.
  - Upgrading from 1.x removes tasks that were already ticked.
- **1.1.0**
  - The window is now built only when first opened.
  - Removed the per-frame update loop.
  - Notes now save when you stop editing instead of on every keystroke.
  - Fixed shift-click links on the 2.5.6 client (it now hooks `ChatFrameUtil.InsertLink`).
  - Corrupted saved data is now repaired instead of causing a crash.
  - Task text limit raised to 255 characters.
  - The tooltip now appears only for task text that doesn't fit.
- **1.0.0**: First release.
