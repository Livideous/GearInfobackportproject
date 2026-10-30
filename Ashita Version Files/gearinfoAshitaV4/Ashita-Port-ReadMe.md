# GearInfo — Ashita v4 port

Port of the Windower GearInfo addon (upstream baseline v1.7.2.10) so it runs as an Ashita v4 addon. The
gear/buff/calculation logic is the original code; everything Windower's core provided — the `windower`
namespace, `res.*` tables, the `action` event, `config`, `files`, the text/primitive UI and the addon's
single shared environment — is rebuilt in `lib/`.

This document sits next to `gearinfo.lua`, so where it says "this folder" it means the addon folder you
are reading it in.

## Install

Copy this folder to `<FFXI>\addons\gearinfo` so the entry file is
`<FFXI>\addons\gearinfo\gearinfo.lua`, then load it in game with `/addon load gearinfo` — add that line
to your Ashita startup script (`scripts\default.txt`) to load it every session.

Ashita loads an addon the moment it is enabled, in or out of game, so the port tolerates a cold start
with no player. First login creates `data\<PlayerName>_settings.lua`.

## Layout

| Port file | What it is |
| --- | --- |
| `gearinfo.lua` | Bootstrap: metadata, `lib/` wiring, the shared environment, loads the logic files in the original `require` order. |
| `logic\Statics.lua` | Original statics and defaults, plus `defaults.manual` (see *Manual data*). |
| `logic\Gear_Processing.lua` `Calculator.lua` `Action_Processing.lua` `Buff_Processing.lua` `Packet_parsing.lua` `Image_processing.lua` | Ported logic; bodies unchanged apart from the API calls listed below. |
| `logic\Entry.lua` | The original `GearInfo.lua` body — events, commands, overlay wiring. |
| `lib\game.lua` | `windower.*` / `windower.ffxi.*` over Ashita's memory managers, plus the Ashita→Windower event bridge. |
| `lib\packets.lua` | Packet byte access, per-id history ring, 0x0028 decode dispatch. |
| `lib\action_parser.lua` `lib\bitstream.lua` | The `action` event: bit-decodes inbound 0x0028 into Windower's action table. |
| `lib\resources.lua` | `res.items/spells/buffs/jobs/slots/skills/bags/item_descriptions` on `AshitaCore:GetResourceManager()`. |
| `lib\extdata.lua` `lib\augment_data.lua` | Vendored Windower extdata decoder — reads `item_t.Extra`. |
| `lib\ui.lua` | `windower.text`/`windower.prim` and the `mouse` event on Ashita's `fonts`/`primitives`. |
| `lib\config.lua` `lib\files.lua` | Windower's `config.load()`/`settings:save()` and `files.exists()`/`files.new()`. |
| `lib\compat.lua` | The table/string helpers, `L{}`/`S{}`/`P{}` and `notice()`/`log()` the ported code calls. |
| `lib\include.lua` | Loads the logic files into one shared environment, like Windower's addon lua state. |
| `lib\chars.lua` | The `chat/chars` glyph table, see *Chat glyphs*. |
| `res\` `textures\` | Original data tables and both texture themes (`default`, `custom1`), unmodified. |

## Event translation

`logic\Entry.lua` still registers the Windower event names. `lib\game.lua`'s bridge (`game.bind_events`)
turns Ashita's events into them:

| Windower event | Ashita source |
| --- | --- |
| `incoming chunk` / `outgoing chunk` | `packet_in` / `packet_out` |
| `action` | `packet_in` for 0x0028, decoded by `lib\action_parser.lua` |
| `incoming text` | `text_in` |
| `addon command` | `command` (`/gi …` or `/gearinfo …`) |
| `prerender` | `d3d_present` |
| `mouse` | `mouse`, with the WNDPROC message numbers mapped to 0 move / 1 press / 2 release |
| `load` / `unload` | `load` / `unload` |
| `login` / `logout` | synthesised: `d3d_present` watches `get_info().logged_in` and fires on change |

## Manual data

Ashita's memory manager has no merit rank table, reports job points as one spent total per job, and
exposes which blue magic spells are *learned* rather than which are *set* — three things GearInfo's
calculations read. They are entered by hand and persist in `settings.manual`:

```
//gi merit desperate_blows 5        // desperate_blows, ikishoten, store_tp_effect, aggressive_aim
//gi jp rdm composure_effect 3      // a single job point gift
//gi blu <spell name or id> [...]   // the set you actually have equipped; '_' for spaces
//gi blu clear                      // go back to "every learned spell"
//gi merit                          // show what is set
```

Only those four merit ranks are read anywhere in the addon, so the others are not asked for; anything you
do not enter counts as 0. `aggressive_aim` (the Warer "Aggressive Aim" cap rank) was added upstream in
v1.7.2.10 and feeds the Aggressor accuracy/AGI numbers.

JP totals (`jp_total`, `jp_spent`) and merit point totals come from Ashita and are real, so the gift
*tables* in `res\Gifts.lua` still drive the Store TP / Dual Wield bonuses automatically — only a gift
addressed by name needs entering. The addon reads exactly one, `//gi jp rdm composure_effect 3`, and an
empty merit or gift counts as 0 rather than faulting the calculation that uses it.

## Differences you will see

* **Settings are Lua, not XML.** `config.load('data\<name>_settings.xml', …)` writes
  `data\<name>_settings.lua`. Old Windower XML is not read; a fresh file is created. `settings:save('all')`,
  `settings:reset()` and every field access work as before.
* **Chat output goes through `/echo`.** `windower.add_to_chat(mode, msg)` ignores `mode` (GearInfo always
  embeds its own `string.char(0x1F, n)` control codes, which the client renders the same way) and queues
  `/echo <msg>`. Very long output, e.g. `//gi help`, is subject to the client's echo limits.
* **`windower.send_command()` prepends the missing `/`**, as Windower did, so `gs c gearinfo …` and
  `gi help` still behave.
* **`windower.packets.last_incoming()/last_outgoing()`** read a 4-entry-per-id ring built by this addon,
  so they only see traffic observed since load, and Ashita has no packet schema files — the reads are the
  raw bytes with Windower's offsets.
* **`entity.distance` stays squared**, like Windower's, so callers still take the square root
  (`:sqrt()` does not exist in Ashita's sugar; `math.sqrt()` is used).
* **Containers use Ashita's ids** (0 Inventory … 16 Wardrobe 8, 17 Recycle) and 0-based slot indices;
  GearInfo only round-trips them through `windower.ffxi.get_items()`.
* **Combat skills are re-indexed**: Ashita's array is one denser than Windower's `res.skills` from the
  automaton block up, mapped in `lib\game.lua`'s `windower_skill_id()`.
* **Resource names are language-slot probed**, not hard-coded: the english slot moved between Ashita
  builds, so it is found once against a known item.
* **`item.augments` is always an array.** Windower's resource items carry the four augment lines even on
  a piece with none, and v1.7.2.10 indexes `player.equipment.body.augments[3]` after only testing the
  item id; the vendored extdata decoder returns nothing for an unaugmented item, so the port stores an
  empty table and that read yields nil instead of faulting the action handler.
* **Text and images** are Ashita font/primitive objects keyed by the same ids the original overlay code
  uses. Colour is packed to one 0xAARRGGBB value; `set_fit_to_texture()` is recorded but inert (the code
  always sets an explicit size after it); draw order follows creation order, and `options_load()` creates
  the background block first, so nothing paints under it by accident.
* **Reloading** uses `/addon reload gearinfo` instead of `lua r gearinfo` — that includes the `/gi reload`
  command, which saves party and buff state to `data\<name>_temp_*.lua` first, exactly as before.
* **Chat glyphs**: Windower's `chat/chars` table is built from its own chat font, which Ashita has no
  equivalent of. Corsair roll circles print as `(1)`…`(6)` and `chars.implies` as `->` rather than nil,
  because a nil there would abort the action handler.

## GearSwap

The overlay half is self-contained, but the `//gi updategs` / auto-update path still broadcasts
`gs c gearinfo <dw> <haste> <moving> <ma>` on the client command line, unchanged from the original.
Ashita has no GearSwap, so nothing receives it unless you run an Ashita addon that handles `gs c`
messages; `//gi ugs false` (or leaving `settings.player.update_gs` false) keeps the addon quiet.

## Load-order caveat

Because Ashita enables addons outside the game, a session that starts with the addon enabled *while
already in zone* can catch the client mid-transition: `logged_in` is already true, so no `login` event
fires and `options_load()` is skipped. `//addon reload gearinfo` (or `//gi reload`) fixes it; the display
itself refreshes on its own once a player entity exists.

## Validation

No Lua runtime or game client was available for this port, so it is checked statically with the three
scripts in `tools\` at the repository root. `<repo>` and `<addon>` below stand for those two paths; run
them from anywhere and expect exactly this output:

```
python <repo>/tools/luacheck.py <addon>/gearinfo.lua <addon>/lib/*.lua <addon>/logic/*.lua <addon>/res/*.lua
python <repo>/tools/undefscan.py <addon>/gearinfo.lua <addon>/lib/*.lua <addon>/logic/*.lua
python <repo>/tools/test_action_parser.py
```

* lexical/parenthesis balance over all 32 lua files (22 addon files plus the 10 data tables in `res\`);
* an unresolved-identifier scan over the whole addon — the only reports are five known table-key false
  positives (`h_spikes`, `melee`, `tp_per_hit_melee`, `main`, `image`), all of which are constructors,
  not globals;
* every memory-manager call cross-checked against the Ashita v4 SDK annotations;
* the 0x0028 bit layout round-trip test in `tools\test_action_parser.py`.

Expect to find UI-positioning and in-game-behaviour issues that static checks cannot see; the overlay
placement and the buff/party packet paths are the places to look first.
