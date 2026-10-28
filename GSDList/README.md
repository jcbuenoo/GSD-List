# GSD List

**A lightweight notepad and to-do list for World of Warcraft: TBC Classic Anniversary.**

GSD List gives you somewhere in game to write things down: raid strats, gold-making
plans, attunement steps, shopping lists. It has nested note pages, search across every
note, and an optional to-do list. It's built entirely from the game's own art, fonts,
buttons, menus and popups, so it looks like part of the default UI. It has no libraries
and no extra files.

- **Game version:** TBC Classic Anniversary 2.5.5 and 2.5.6
- **Version:** 2.1.0
- **Saved data:** shared by every character on your account

---

## Installation

1. Close the game, or plan to `/reload` afterwards.
2. Copy the `GSDList` folder into your AddOns folder:
   ```
   World of Warcraft/_anniversary_/Interface/AddOns/GSDList/
   ```
   The folder must contain `GSDList.toc` and `GSDList.lua`.
   Use `_classic_` instead of `_anniversary_` if that's where your TBC client lives.
3. Start the game. If the AddOns screen says **Out of date**, tick **Load out of date AddOns**.

**Updating:** replace the whole `GSDList` folder. Your notes and tasks are kept.

---

## Core Features

### 📝 Notepad
- A scrolling text area for as much as you want to write.
- **Saves automatically** when you click away, switch pages or tabs, close the window, `/reload` or log out.
- **Shift-click** an item, spell or quest to paste its link into your notes.
- An empty page shows a short hint so you know where to start.

### 📚 Nested Note Pages
- Make as many pages as you like, and **nest sub-notes under them** up to 4 levels deep.
  ```
  Raid
    Karazhan
      Attunement
        The Master's Key
  Gold Farming
  ```
- **◀ ▶ arrows** step through every page in order, sub-notes included. They sit in the
  page-title row, so they don't make the window bigger.
- The title shows where you are, e.g. `Raid / Karazhan / Attunement`.
- **Click the page title** to open the page menu, where you can:
  - Jump to any page
  - Add a **New page** or a **New sub-note**
  - **Rename** the page
  - **Move up / Move down**
  - **Delete** it. This asks first, and Undo brings it back with everything nested under it.

### 🔍 Search
- Click the **magnifier** to search every page at once. It doesn't matter if you type in capitals.
- It jumps to the first match as you type and shows a counter like `2/5`.
- **Enter** goes to the next match and **Shift+Enter** to the previous one, across pages.
- **Escape** closes search and leaves your cursor on the match.
- It ignores the hidden codes inside item links, so it only matches text you can see.

### ✅ To-Do List (optional)
- Type a task and press **Enter** or click **Add**.
- The tab shows how many tasks you have, e.g. `To-Do (3)`.
- **Tick a task to complete it.** A Yes/No popup asks you to confirm first. You can turn
  that off in settings, and then ticked tasks clear themselves after a moment (untick
  quickly to keep one).
- **Drag tasks** to reorder them. A gold line shows where the task will land, and the
  list scrolls when you drag past its edge.
- Click the **X** to delete a task.
- Hover over a long task to see its full text.
- Don't need it? Turn it off in settings and GSD List is just a notepad.

### ↩️ Undo
- The gold arrow undoes your last change: deleting, completing, adding or moving a task,
  and deleting a page.
- It keeps the last 20 changes, for the current session.
- Hover over it to see exactly what it will undo.

### 🔒 Lock
- Click the **padlock** to stop the window being moved or resized. It lights up while locked.

### ⚙️ Settings (gear icon)
- Enable or disable the to-do list
- Confirm completing tasks
- Lock window
- Show the minimap button
- Text size: Small, Medium or Large
- Reset position

### 🗺️ Minimap Button
- **Left-click:** open or close the notepad
- **Right-click:** open the to-do list
- **Drag:** move the button around the minimap

### 🪟 Window
- Drag the border to move it. Drag the bottom-right corner to resize it, from **200 × 150** up to 900 × 900.
- **Escape** closes it. Its size and position are remembered.

### ⚡ Lightweight
- At login it creates only the minimap button. The window is built the first time you open it.
- **Nothing runs in the background** while you're not typing or dragging.

---

## Commands

You can use `/gsd` or `/gsdlist`.

| Command | What it does |
|---|---|
| `/gsd` | Open or close the window |
| `/gsd add <task>` | Add a to-do task from chat. Shift-clicked item links work too. |
| `/gsd note <text>` | Add a line to the note page you're on |
| `/gsd search <text>` | Open the window and search all notes |
| `/gsd undo` | Undo the last change |
| `/gsd lock` | Lock or unlock the window |
| `/gsd todo` | Turn the to-do list on or off |
| `/gsd minimap` | Show or hide the minimap button |
| `/gsd reset` | Reset the window size and position, and the minimap button position |
| `/gsd help` | List all commands in chat |

**Examples**
```
/gsd add Buy 20 [Netherweave Cloth]
/gsd note Kara: pull Attumen to the stairs
/gsd search attunement
```

---

## Good to Know

- **Account-wide:** notes and tasks are shared by all your characters, but not between
  separate WoW accounts (WoW1, WoW2) or other game versions.
- **Saving:** WoW writes addon data when you log out or `/reload`. If you play two
  characters at once, the one that logs out last wins.
- **Undo** covers tasks and pages, not text you type inside a note.
- **Upgrading from 1.x:** your old notes move into a page called "Notes".

---

*GSD List: Get Stuff Done.*
