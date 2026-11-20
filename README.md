# FlashCD

![FlashCD icon](Media/icon.png)

A World of Warcraft addon for **WoW Forever (patch 1.60.1, Interface 16001)**. It flashes a spell's or item's icon in the middle of the screen when it comes off cooldown, then fades the icon out.

Author: Skeide

## Features

- Every spellbook spell with a cooldown is tracked automatically, and newly learned spells are added as you learn them. A spell you remove stays removed, even when you learn a new rank.
- Spells are tracked by name, so all ranks count as one spell.
- Items with a "Use:" effect (trinkets, potions) can be tracked too.
- Several icons show at once when more than one spell comes ready; the row can be centred or grow left, right, up or down.
- Appearance: size, opacity, fade time, animation (pop, zoom, bounce, slide in, plain), glow border and colour, a shine burst, the spell name and a "Ready!" label with font size and outline. A live preview in the options shows the result as you change it.
- Filters: only in combat, a minimum cooldown length, and skipping spells you can't cast in your current form.
- The spell list shows every spell (or item) in one place: tick to track it. Filter by spellbook tab or tracked status, sort by name or cooldown, and track or untrack everything shown at once.
- Each tracked spell can be muted, or have its own sound or glow colour, right in its row.
- A minimap button (drag it around the edge) and an addon compartment entry: left-click opens the options, right-click shows a test flash.
- Settings are saved per character. A new character starts with the display settings of the last character you logged out on.

## Usage

| Command | What it does |
|---|---|
| `/flashcd` or `/fcd` | Open the options (Options → AddOns → FlashCD) |
| `/flashcd unlock` | Show a box you can drag to move the flash; run it again to lock |
| `/flashcd test` | Show a test flash |
| `/flashcd minimap` | Show or hide the minimap button |
| `/flashcd reset` | Put all settings back to defaults (tracked spells are kept) |

## Files

| File | Contents |
|---|---|
| `FlashCD.toc` | Addon metadata and saved variables |
| `Core.lua` | Cooldown tracking, the flash display, saved settings and slash commands |
| `Options.lua` | The settings panel, plus the spellbook and item scanning |
| `Minimap.lua` | The minimap button and the addon compartment entry |
| `Media/Icon.tga` | The addon icon used in game (128×128, 32-bit uncompressed TGA) |
| `Media/icon.png` | The same icon as a PNG, used by this README |
| `tools/make_icon.py` | Script that draws the icon (needs Pillow) |

## Notes

- This client hides cooldown times in combat. FlashCD reads the `isActive` / `isOnGCD` flags instead, which stay readable, so spell flashes work in combat.
- Item cooldown times are hidden in combat too. An item used and recovered within one fight may not flash.
- Spells with charges flash only when every charge is back.
- Short lockouts (the global cooldown, wand and ranged shots) are not flashed. A spell must stay on cooldown for at least half its base cooldown, or more than about 3 seconds when the base cooldown is unknown.
