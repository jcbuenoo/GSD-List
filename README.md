# GSD-List
GSD List

## GSD List — WoW TBC Classic addon

A lightweight in-game notepad with nested note pages, search, and an optional
to-do list. It uses only the game's own art, fonts, frame templates, menus and
popups, so it looks like the stock UI. It has no libraries or external files.

### Install

1. Download `release/GSDList-v2.0.0.zip`.
2. Extract it into your AddOns folder so that you end up with:

```
World of Warcraft/_anniversary_/Interface/AddOns/GSDList/GSDList.toc
World of Warcraft/_anniversary_/Interface/AddOns/GSDList/GSDList.lua
```

Use `_classic_` instead of `_anniversary_` if that's the folder your TBC client uses.
If the AddOns screen says "Out of date", tick **Load out of date AddOns**.
When updating, replace the whole `GSDList` folder. Your notes and tasks are kept.

### The window

```
 [gear]        [ GSD List ]       [lock][X]
 [Notes][To-Do (3)]                 [undo]
 [<]   Raid / Karazhan          [>] [search]
 +---------------------------------------+
 | your notes...                         |
 +---------------------------------------+
```

- **Gear**: settings menu.
  - Enable the to-do list
  - Confirm completing tasks
  - Lock the window
  - Show the minimap button
  - Text size (Small, Medium or Large)
  - Reset position
- **Lock**: stops the window being moved or resized. Click again to unlock.
- **Undo**: undoes the last change (up to 20 steps this session). Hover over it to see what it will undo.
- Resizes down to **200 x 150** from the bottom-right corner. Escape closes it.

### Note pages

- Click the **page title** for the page menu, where you can:
  - Jump to any page (sub-notes are indented)
  - Add a **New page**
  - Nest a **New sub-note** under the current page (up to 4 levels deep)
  - Rename the page
  - Move it up or down
  - Delete it (asks first, and Undo restores it with everything nested under it)
- **◀ ▶** step through every page in order, including sub-notes.
- The title shows where you are, e.g. `Raid / Karazhan / Attunement`.
- Notes save when you click away, switch pages or tabs, close the window, `/reload` or log out.
- Shift-click an item, spell or quest to paste its link.

### Search

- Click the magnifier to search every page; it doesn't matter if you type in capitals.
- The search bar takes the place of the page row, so the window doesn't grow.
- Typing jumps to the first match. **Enter** goes to the next match and **Shift+Enter** to the previous one. The counter shows e.g. `2/5`.
- **Escape** or the X closes search and puts your cursor on the match.

### To-Do list

- Type a task and press Enter or click **Add**. The tab shows how many tasks you have, e.g. `To-Do (3)`.
- Tick a task to complete it. By default the game's Yes/No popup asks you to confirm first.
- Turn confirmation off in settings and ticked tasks clear themselves after a moment. Untick quickly to keep one.
- **Drag** a task to reorder it. A gold line shows where it will land, and the list scrolls if you drag past its edge.
- Click the X to delete a task. Undo brings back deleted, completed and moved tasks.

### Quick add from chat

| Command | Action |
| --- | --- |
| `/gsd add <task>` | Add a to-do task (shift-click item links into the chat line too) |
| `/gsd note <text>` | Add a line to the current note page |
| `/gsd search <text>` | Open the window and search all notes |
| `/gsd undo` | Undo the last change |
| `/gsd lock` | Lock or unlock the window |
| `/gsd` | Toggle the window |
| `/gsd todo` | Turn the to-do list on or off |
| `/gsd minimap` | Show or hide the minimap icon |
| `/gsd reset` | Reset the window and icon positions |

Notes and tasks are shared by every character on the account (`SavedVariables: GSDListDB`).

### Performance

- At login it creates only the minimap button. The window is built the first time you open it.
- Nothing runs every frame while idle. Per-frame work happens only while you type in the notes, for a few frames after a search jump, or while you drag a task or the minimap button.
- To-do rows are pooled and reused, and the page list is cached until pages change.

### Development

```
lua5.1 tests/run_tests.lua   # 47 functional tests against a mocked WoW API
luacheck GSDList tests       # lint (config in .luacheckrc)
```

The templates, functions, menus, popups and textures it uses were checked against
Blizzard's 2.5.5 and 2.5.6 (TBC Anniversary) UI source.

### Changelog

- **2.0.0**
  - Added nested note pages with ◀ ▶ arrows and a page menu.
  - Added search across all notes.
  - Ticking a task now asks for confirmation (can be turned off).
  - Added a lock button and an undo button.
  - Added quick add from chat: `/gsd add`, `/gsd note`, `/gsd search`.
  - Added a text size setting.
  - Settings moved into a gear menu.
  - The window is more compact and shrinks to 200 x 150 (was 280 x 260). Default size is now 300 x 340.
  - Fixed a possible Lua error when typing in notes: Blizzard's scroll helper needed cursor offsets that were never set.
  - Your notes from 1.x move into a page named "Notes".
- **1.2.0**
  - Ticked tasks clear themselves; the **Clear Completed** button is gone.
  - Drag to reorder replaces the up/down arrows.
  - Upgrading from 1.0 or 1.1 removes tasks that were already ticked.
- **1.1.0**
  - The window is built only when first opened.
  - Removed the per-frame update loop.
  - Notes save when you stop editing instead of on every keystroke.
  - Fixed shift-click links on the 2.5.6 client.
  - Corrupted saved data is now repaired instead of causing a crash.
- **1.0.0**: First release.
