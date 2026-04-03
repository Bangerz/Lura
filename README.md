# L'ura

<img width="538" height="206" alt="image" src="https://github.com/user-attachments/assets/62c4ae33-215b-4101-bef7-008c8b7f9471" />

World of Warcraft **retail** add-on: a **leader bar** of five buttons that send **`/raid`** lines with a short label plus Blizzard’s raid-marker tokens (e.g. `Circle {circle}`, `T {star}`). Buttons use **custom rune art**; chat text still uses the normal markers so the game shows standard raid icons in chat.

A separate **order strip** shows the **sequence** of markers as raid leader or assistants use the bar—synced over the **addon channel** for everyone in the raid who runs L’ura.

## Features

- **Secure action buttons** — `/raid` works in combat (no tainted chat injection).
- **Leader bar** — Only shown when you are **solo**, or **party/raid leader**, or **raid assistant**. Other group members still see the **order strip** when it is active.
- **Order strip** — Icons only (mirrored order). Updates from **leader/assist** `/raid` lines that match L’ura’s messages. Clears **30 seconds** after the last icon, or when you leave the raid.
- **Two frames** — Leader bar and order strip have **separate positions** (each has a drag grip when unlocked). **Scale** applies to both.
- **Placeholders** — With the strip **unlocked** and **empty**, dim placeholder runes appear so you can position the strip.
- **Visibility** — **`/lura`** (no args) **toggles** UI on/off for **both** frames. **`/lura help`** lists commands. Options: **Show L’ura** checkbox.

## Install

Copy the `lura` folder into:

`_retail_\Interface\AddOns\`

Enable **L'ura** in the AddOns list. **`/reload`** if you change files on disk.

## Usage

| | |
|---|---|
| **Options** | Esc → Options → AddOns → **L'ura** |
| **Slash** | `/lura`, `/lura help`, `/lura show` / `hide` / `on` / `off` / `toggle`, layout (`scale`, `x`, `y`, `anchor`, `lock`, `unlock`, `reset`, `config`) |
| **Keybinds** | Esc → Options → Key Bindings → AddOns → **L'ura** (per-button clicks; unbound by default) |

Textures live under `Interface\AddOns\lura\Icons\` (`rune_*.png`, 48×48).

## Requirements

- **Retail** WoW with an `## Interface:` build supported by `lura.toc`.
- **Raid** for order sync (addon messages on `RAID`). **`LoadAfter: Blizzard_Channels`** is not required by the `.toc`; the add-on waits for the channels UI when needed.

## Author

Bangerz-DarkIron

## License

See [LICENSE](LICENSE) in this repository.
