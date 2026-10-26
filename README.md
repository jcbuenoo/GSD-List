# GSD-List
GSD List

## GSD List — WoW TBC Classic addon

A lightweight in-game notepad with an optional to-do list. It uses only the
game's own art, fonts and frame templates, so it looks like the stock UI.
It has no libraries or external files.

### Install

Copy the `GSDList` folder into:

```
World of Warcraft/_anniversary_/Interface/AddOns/GSDList
```

(Use `_classic_` instead of `_anniversary_` if that's the folder your TBC client uses.)
After copying, the folder should hold `GSDList.toc` and `GSDList.lua`.

### Use

- **Minimap icon**: left-click toggles the notepad, right-click opens the to-do list, drag moves the icon around the minimap.
- **Notes**: type freely. Notes save automatically. Shift-click an item, spell or quest to paste its link.
- **To-Do**: type a task and press Enter or click **Add**. Tick a task to complete it, use the arrows to reorder, and click the X to delete. **Clear Completed** removes every ticked task.
- Untick **Enable To-Do List** at the bottom to use the window as a notepad only.
- Drag the window by its border to move it. Drag the bottom-right corner to resize it. Press Escape to close it.

### Slash commands

| Command | Action |
| --- | --- |
| `/gsd` | Toggle the window |
| `/gsd todo` | Turn the to-do list on or off |
| `/gsd minimap` | Show or hide the minimap icon |
| `/gsd reset` | Reset the window and icon positions |

Notes and tasks are shared by every character on the account (`SavedVariables: GSDListDB`).
