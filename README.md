# FlashCD

![FlashCD icon](Media/icon.png)

FlashCD shows a spell's icon in the middle of your screen the moment its cooldown is ready. You don't have to watch your action bars to know when Barkskin or your trinket is back. The icon pops up, fades out after a second, and you get on with the fight.

Made for **WoW Forever (patch 1.60.1)** by Skeide.

## Getting started

Install it and log in. FlashCD finds every spell in your spellbook that has a cooldown and starts tracking it straight away, so it works without any setup.

The first time you log in, a small welcome window lets you:

- choose which spells should flash
- place the flash where you want it on screen
- try one of the ready-made looks (hover one to see it before you pick it)
- import settings a friend sent you

After that, `/fcd` or the minimap button opens the settings.

## Choosing spells

The spell list shows everything in your spellbook (or the usable items in your bags and gear). Tick a spell to track it, untick it to stop. A spell you untick stays that way, even when you learn a new rank.

Click a spell to change its own settings on the right: which group it flashes in, its own sound, its own glow colour, mute it, or make it flash only while you're in a form (bear, cat and so on). Ctrl-click or Shift-click to change several spells at once.

## Groups

You can have up to ten groups, each with its own place on screen and its own look. A common setup is big icons in the middle for your important cooldowns and a row of small ones underneath for the rest. Drag a spell from the list onto a group in the sidebar to move it there.

For each group you can set the icon size, opacity, how long it stays, the animation (pop, zoom, bounce, slide in or a plain fade), a glow border, a shine effect, the spell name, a "Ready!" label, and which way the icons line up when several come ready together.

## Placing a group

Click **Move** on a group's page. The settings window steps aside and a box shows where that group's flash appears. Then:

- drag the box (it snaps to a grid; both can be turned off)
- click the small arrows around it, or use the arrow keys while hovering it, to nudge it a pixel at a time (Shift: 10)
- scroll over it to make the icons bigger or smaller

Click **Done** when you're happy with it. The arrows and scrolling work in combat too, so you can fine-tune during a dummy pull.

## When it flashes

You can have it flash only in combat, ignore short cooldowns, skip spells your current form can't cast, and play a sound. There's also an optional early warning: a grey "Soon" flash a few seconds before a cooldown is ready.

If something didn't flash and you don't know why, the **Recent flashes** page tells you (muted, not in combat, wrong form and so on).

## Sharing settings

On **Profiles & sharing** you can:

- copy settings from another of your characters
- export your settings as a line of text and send it to someone, choosing what to include (just the positions, say, or everything)
- import a text someone sent you
- pick one of the presets, or start over with the defaults

Imported text is only read as settings, never run as code, so a bad paste can't do any harm.

## Commands

| Command | What it does |
|---|---|
| `/fcd` | Open or close the settings |
| `/fcd unlock` | Move all groups at once (run it again to lock) |
| `/fcd test` | Show a test flash |
| `/fcd welcome` | Show the welcome window again |
| `/fcd minimap` | Show or hide the minimap button |
| `/fcd spell <name>` | Show what FlashCD knows about a spell, if it isn't flashing the way you expect |
| `/fcd reset` | Put the settings back to default (your tracked spells are kept) |

`/flashcd` works for all of these too.

## Good to know

- This version of the game hides cooldown timers in combat. FlashCD works around that, so spells flash in combat as normal.
- Wand and ranged shots briefly lock your spells. FlashCD knows the difference and won't flash spells that were never really on cooldown.
- Some spells only have a cooldown in a form, or have one the game doesn't report (Faerie Fire in bear form is one). FlashCD notices the cooldown the first time you use the spell and tracks it from then on.
- Items used and ready again within the same fight may not flash, because the game hides their timers in combat.
- Spells with charges flash when the last charge is back.
- Settings are saved per character. A new character starts with the settings of the last one you played.
- There are two looks for the settings window: Modern (flat and dark) and WoW Forever (the game's own style).

## For developers

| Path | What's in it |
|---|---|
| `Core.lua` | Cooldown tracking, the flashes, saved settings, profiles, slash commands |
| `Widgets.lua` | The buttons, sliders and other controls the settings window is built from |
| `Scan.lua` | Reading the spellbook and bags |
| `Options.lua` | The settings window, its pages and the welcome window |
| `Minimap.lua` | The minimap button |
| `tests/` | Tests that run outside the game against a small fake of the WoW API: `python tests/run_tests.py` (needs the `lupa` package) |
| `tools/release.py` | Builds `dist/FlashCD-<version>.zip` with only the files the game needs |
| `tools/make_icon.py` | Draws the addon icon (needs Pillow) |
