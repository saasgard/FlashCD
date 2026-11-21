# FlashCD

![FlashCD icon](Media/icon.png)

A World of Warcraft addon for **WoW Forever (patch 1.60.1, Interface 16001)**. It flashes a spell's or item's icon in the middle of the screen when it comes off cooldown, then fades the icon out.

Author: Skeide

## Features

- Its own settings window (not squeezed into the game's Settings): resizable and movable, it can stay open while you play. A sidebar lists the pages and your groups; click a group to edit it, or drag a tracked spell onto it to move the spell there. Esc closes it. Two themes: Modern (flat and dark) and WoW Forever (the game's own dialog look), chosen on the Alerts & moving page; the window switches right away.

- Every spellbook spell with a cooldown is tracked automatically, and newly learned spells are added as you learn them. A spell you remove stays removed, even when you learn a new rank.
- Spells are tracked by name, so all ranks count as one spell.
- Items with a "Use:" effect (trinkets, potions) can be tracked too.
- Groups: up to 10 display groups, each with a colour of its own, each with its own position, size and look, for example big icons for important cooldowns and small ones for the rest. The sidebar lists them all; each group's page has its name, Move, Test, Copy and Delete. Pick a spell's group in its row, or move every spell the list shows to a group at once.
- Moving: click Move on a group's page to show just that group's box, or Unlock all (Alerts & moving) for every group. The settings window hides while you move groups, and a small bar at the top of the screen has a Done button that brings it back. Each box is as big as the group's full row of icons. Drag it (it snaps to a 25-pixel grid shown on screen, both can be turned off), or hover it and nudge it with the arrow keys (1 pixel, Shift: 10).
- Several icons show at once when more than one spell comes ready; the row can be centred or grow left, right, up or down.
- Appearance: size, opacity, fade time, animation (pop, zoom, bounce, slide in, plain), glow border and colour, a shine burst, the spell name and a "Ready!" label with font size and outline. A live preview in the options shows the result as you change it.
- Filters: only in combat, a minimum cooldown length, and skipping spells you can't cast in your current form.
- The spell list shows every spell (or item) in one place: tick to track it. Each row shows its cooldown, its group (in the group's colour) and markers for its own settings. Filter by spellbook tab, tracked status or group, and sort by name or cooldown.
- Click a spell to see its settings on the right: group, sound, mute and glow colour. Ctrl-click or Shift-click (or Select all) to change several spells at once.
- A minimap button (drag it around the edge) and an addon compartment entry: left-click opens the options, right-click shows a test flash.
- Settings are saved per character. A new character starts with the display settings of the last character you logged out on.

## Usage

| Command | What it does |
|---|---|
| `/flashcd` or `/fcd` | Open or close the FlashCD window (also from the minimap button, or Options → AddOns → FlashCD) |
| `/flashcd unlock` | Show a box per group that you can drag or nudge with the arrow keys; run it again to lock |
| `/flashcd test` | Show a test flash |
| `/flashcd minimap` | Show or hide the minimap button |
| `/flashcd spell <name>` | Show what FlashCD sees for a spell (IDs, cooldowns, tracked or not), to find out why it doesn't flash |
| `/flashcd reset` | Put all settings back to defaults (tracked spells are kept) |

## Files

| File | Contents |
|---|---|
| `FlashCD.toc` | Addon metadata and saved variables |
| `Core.lua` | Cooldown tracking, the flash display, saved settings and slash commands |
| `Options.lua` | The FlashCD settings window, plus the spellbook and item scanning |
| `Minimap.lua` | The minimap button and the addon compartment entry |
| `Media/Icon.tga` | The addon icon used in game (128×128, 32-bit uncompressed TGA) |
| `Media/icon.png` | The same icon as a PNG, used by this README |
| `tools/make_icon.py` | Script that draws the icon (needs Pillow) |

## Notes

- This client hides cooldown times in combat. FlashCD reads the `isActive` / `isOnGCD` flags instead, which stay readable, so spell flashes work in combat.
- Item cooldown times are hidden in combat too. An item used and recovered within one fight may not flash.
- Spells with charges flash only when every charge is back.
- Some spells (like Faerie Fire on WoW Forever) are replaced by a form version with a cooldown, for example in bear form. FlashCD checks for these when you log in, learn spells or shapeshift, remembers the form version and tracks it, also out of the form.
- Some spells have a cooldown the game doesn't report. FlashCD watches spells without a reported cooldown, and the first time one stays on cooldown for more than about 3 seconds it remembers the length and starts tracking the spell (unless you unticked it). From then on it shows in the list with that cooldown.
- Spells are looked up by their spellbook ID, so names with brackets, such as "Faerie Fire (Feral)", work.
- Short lockouts (the global cooldown, wand and ranged shots) are not flashed. A spell must stay on cooldown for at least half its base cooldown, or more than about 3 seconds when the base cooldown is unknown.
