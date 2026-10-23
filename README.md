# slips

A Storage Slip viewer addon for **Ashita v4** (Final Fantasy XI), styled after VanaCore (flat navy, periwinkle accent, Segoe UI).

## Install

1. Download this repository (green **Code** button → **Download ZIP**) and unzip it.
2. Copy the `slips` folder into your `Ashita/addons/` folder.
3. In game: `/addon load slips`, then `/slips` to open the window.

To load it automatically, add `/addon load slips` to your Ashita startup script. Nothing else is needed.

## Search

The search box at the top of the window searches every item on every Storage Slip at once. Results are grouped by slip, each with its icon and a tag: **STORED**, **NOT STORED** or **SLIP NOT OWNED**. The x clears the search.

## Tabs

- **SLIPS**: one card per slip, showing the slip's icon, which bag it's in, how many items are stored with a progress bar, and a **FULL** tag when every item is on it.
  - The stored items are shown as an icon grid. Hover an icon for the item's name and full in-game text.
  - Click a card's header to fold or unfold it.
  - **Owned only** hides the slips you don't have.
  - **Empty slots** also shows, dimmed, the items a slip can hold but doesn't yet.
- **READY TO STORE**: gear in any of your bags that can go on a slip, grouped by slip, so you know what to take to the porter moogle. Green means you own that slip, orange means you don't.

The header shows the character you're logged in as, how many slips you own and how many items are stored.

Item icons are read from the game's own item data (brightened and sharpened), so every item has its picture and nothing is downloaded.

Drag the window by any empty part of it. Resize it from its bottom-right corner. It remembers its size and can't be stretched past the game window. `/slips reset` re-centres it.

## Commands

```
/slips                        show / hide the window
/slips find <item>            print which slip an item goes on, and whether it's stored
/slips refresh                rescan your bags now
/slips reset                  re-centre the window
```

## Notes

- **Where slips are read from:** inventory, Mog Safe 1 and 2, Storage, Mog Locker, Satchel, Sack, Case and Wardrobes 1–8, so it doesn't matter where you keep your slips.
- **After storing:** the window rescans every second while it's open. If a slip still looks out of date after the porter moogle, zone or use `/slips refresh`.
- **Saved settings:** the addon writes `slips_settings.lua` (tab, switches, folded cards, window size) into its own folder. Delete it to reset.
- **Font:** uses Segoe UI from your Windows Fonts folder (nothing is bundled). If it can't be loaded, the game's ImGui font is used.

## Files

| file | what |
|---|---|
| `slips.lua` | main addon: window, tabs, search, commands, reading the slips |
| `sliptheme.lua` | drawing / colours (edit the `HUD` table to recolour) |
| `slipicons.lua` | item icons, read from the game's own item data (brightened and sharpened) |
| `slipdata.lua` | which items go on each of the 34 Storage Slips |

Author: Laudout
