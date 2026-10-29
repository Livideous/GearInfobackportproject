# GearInfo: Windower to Ashita v4 porting reference

Notes marked **(verify)** are API details I'm not fully certain of. Check them against the Ashita v4 docs or an existing v4 addon (HXUI, tCrossBar, etc.) before relying on them.

---

## 1. Event handlers

| Windower (where used) | Ashita v4 equivalent | Notes |
|---|---|---|
| `_addon.name/author/version/commands` (GearInfo.lua) | `addon.name`, `addon.author`, `addon.version`, `addon.desc`, `addon.link` | `addon.commands` has no equivalent. Commands are matched manually in the `command` event. |
| `register_event('load')` | `ashita.events.register('load', 'gi_load', function() end)` | Loading mid-session is fine. Check for a logged-in player yourself. |
| `register_event('unload')` (empty) | `ashita.events.register('unload', ...)` | Destroy fonts, textures and ImGui state here. Save settings. |
| `register_event('login')` | **No event.** Use packet_in `0x0A` (zone-in), or poll `GetParty():GetMemberIsActive(0) == 1` / a non-empty `GetMemberName(0)` in `d3d_present`. | The Windower version just reloaded the addon on login. |
| `register_event('logout')` | **No event.** Detect it by polling the same way, or via packet_in `0x0B`. | Reset `player`, `manual_*` and `full_gear_table_from_file` when the name goes empty. |
| `register_event('addon command', function(command, ...))` | `ashita.events.register('command', 'gi_cmd', function(e) local args = e.command:args(); ... end)` | `args[1]` is `/gi` or `/gearinfo`. Return early if it isn't. Set `e.blocked = true` when handled. `args` comes from `require('common')`. |
| `register_event('prerender')` (frame_count % 2 / % 15) | `ashita.events.register('d3d_present', 'gi_present', function() end)` | Runs every frame. Keep your frame counters. All drawing (ImGui) must happen here. |
| `register_event('mouse')` (drag the background) | `ashita.events.register('mouse', ...)` with `e.message` (WM_ values), `e.x`, `e.y`, `e.delta`, `e.blocked` | **Not needed if you move to ImGui**, which handles window dragging itself. Otherwise `WM_MOUSEMOVE=0x200`, `WM_LBUTTONDOWN=0x201`, `WM_LBUTTONUP=0x202`. Set `e.blocked = true` to swallow. |
| `register_event('action', on_action)` | `packet_in`, id `0x28` | Ashita has no pre-parsed action event. Parse the bit-packed 0x28 yourself (actor id, category, param, targets and actions). The `windower.ffxi.get_info().logged_in` guard becomes a party-member-active check. |
| `register_event('incoming chunk')` / `parse.i[id]` | `ashita.events.register('packet_in', ...)`, `function(e) if e.id == 0x63 then ... end end` | Fields: `e.id`, `e.data` (string), `e.data_modified`, `e.size`, `e.injected`, `e.blocked`. Do not return a value. The dispatch table `parse.i[id]` can stay as is. |
| `register_event('outgoing chunk')` / `parse.o` | `ashita.events.register('packet_out', ...)` | Same shape. No outgoing parsers are actually defined. |
| `register_event('incoming text')` (hides COR roll text) | `ashita.events.register('text_in', ...)` with `e.message`, `e.message_modified`, `e.mode`, `e.mode_modified`, `e.blocked` | Suppress with `e.blocked = true`. To rewrite, set `e.message_modified`. The Windower return values `true` / `new, color` don't exist. Battlemod-style patterns still match on `e.message`. |
| *(commented out)* `register_event('job change')` | Packet_in `0x1B` (job info) or `0x61` (char stats) | Not currently active in the code. |

### Packet notes

- Packets in use: `0x0A`, `0x61`, `0x62`, `0x63` (type 9 buffs), `0x76` (party buffs) and `0xDD` (party member info).
- `packets.parse('incoming', data)` (used for `0xDD`) has no equivalent. Unpack manually with `struct.unpack`.
- Windower `data:unpack('H', 0x15)` becomes `struct.unpack('H', e.data, 0x15)`. Both are 1-based string offsets, so the offsets should carry over **(verify)**.
- `windower.packets.last_incoming(id)` (used in `initialize_packet_parsing`) has no equivalent. Ashita does not keep a "last packet" cache. For mid-session loads, read current state from the memory managers instead (see section 3).
- `0xDD` is not needed. Party jobs and levels come straight from the party manager (`GetMemberMainJob`, etc.).

---

## 2. Windower API calls

### 2a. Core and `windower.ffxi.*`

| Windower call | Ashita v4 equivalent |
|---|---|
| `windower.addon_path` | `addon.path` (string with trailing slash). Writable data: `AshitaCore:GetInstallPath() .. 'config\\addons\\gearinfo\\'`. |
| `windower.ffxi.get_player()` | No single table. Build one from `AshitaCore:GetMemoryManager():GetPlayer()` (`GetMainJob`, `GetMainJobLevel`, `GetSubJob`, `GetSubJobLevel`, `GetBuffs`, skills, merits, job points) and the party/entity managers. See section 3. |
| `windower.ffxi.get_player().status` (== 1) | `GetEntity():GetStatus(targetIndex)`, or `GetPlayer():GetStatus()` **(verify)**. |
| `windower.ffxi.get_info().logged_in` | Party member 0 is active: `GetParty():GetMemberIsActive(0) == 1`. |
| `windower.ffxi.get_info().zone` | `GetParty():GetMemberZone(0)`. |
| `windower.ffxi.get_party()` (`p0..p5`, `.mob`, `.name`) | Loop `i = 0..5` over `GetParty():GetMemberIsActive(i)`, `GetMemberName(i)`, `GetMemberServerId(i)`, `GetMemberTargetIndex(i)`, `GetMemberMainJob/SubJob(i)`, `GetMemberMainJobLevel/SubJobLevel(i)`. Mob info comes from `GetEntity()`, using the member's target index. |
| `windower.ffxi.get_mob_by_index(i)` | `GetEntity():GetName(i)`, `GetLocalPositionX/Y/Z(i)`, `GetPetTargetIndex(i)`, `GetDistance(i)`, `GetStatus(i)` |
| `windower.ffxi.get_mob_by_id(id)` | Ashita has no direct lookup by server id. Search `0..0x8FF` with `GetEntity():GetServerId(i)`, or cache an id-to-index map from the party manager. |
| `windower.ffxi.get_mob_by_target('t')` | `GetMemoryManager():GetTarget():GetTargetIndex(0)` (check `GetIsSubTargetActive()` first). Only appears in the commented-out test code. |
| `mob.distance:sqrt()` | `math.sqrt(GetEntity():GetDistance(idx))`. Ashita's distance is already squared **(verify)**. |
| `mob.charmed` / `mob.is_npc` | `GetEntity():GetSpawnFlags(idx)` bit tests (`0x0010` NPC, `0x0200` charmed) **(verify)**. Used for Trust detection and charmed members. |
| `mob.pet_index` | `GetEntity():GetPetTargetIndex(idx)` |
| `windower.ffxi.get_items()` (+ `.equipment`) | `GetMemoryManager():GetInventory():GetEquippedItem(slot)`. `.Index` encodes the container (`bit.rshift(Index, 8)`) and slot (`Index % 256`). Slot 0 means nothing equipped. |
| `windower.ffxi.get_items(bag_id, slot)` | `inventory:GetContainerItem(container, slot)`, returning `.Id`, `.Count`, `.Index`, `.Extra` (extdata). |
| `windower.ffxi.get_items(v.id)` (whole bag, in `parse_inventory`) | Loop `slot = 1..inventory:GetContainerItemCountMax(container)` and call `GetContainerItem`. |
| `windower.ffxi.get_mjob_data().spells` (BLU set spells) | `GetPlayer():GetBlueMagicSpells()` or similar **(verify)**. Otherwise parse the job-extra packet `0x44` (sub-type 0x10). |

### 2b. Chat, commands, files and time

| Windower | Ashita v4 |
|---|---|
| `windower.add_to_chat(mode, msg)` | `AshitaCore:GetChatManager():AddChatMessage(mode, false, msg)`, or `print(chat.header(addon.name):append(chat.message(msg)))` with `local chat = require('chat')`. |
| `windower.send_command('gi help')` (self) | Call your own function directly. |
| `windower.send_command('lua r gearinfo;')` | `AshitaCore:GetChatManager():QueueCommand(1, '/addon reload gearinfo')` |
| `windower.send_command('gs c gearinfo ...')` (GearSwap link) | No GearSwap in Ashita. If you use LuAshitaCast, use `/lac fwd gearinfo <args>`, which calls the profile's `HandleCommand` **(verify)**. Otherwise drop this feature or expose a shared global or IPC. |
| `windower.dir_exists(path)` | `ashita.fs.exists(path)` |
| `files.exists / files.new:create` | `ashita.fs.exists(path)`, `ashita.fs.create_dir(path)`, then `io.open` |
| `windower.get_windower_settings()` | `AshitaCore:GetProperties()` / D3D viewport size. Only used in a comment. |

### 2c. Drawing: `windower.prim.*` and `windower.text.*`

Ashita v4 has no direct primitive or text objects. The idiomatic replacement is **ImGui in `d3d_present`**.

| Windower | Ashita v4 (ImGui) |
|---|---|
| `prim.create` / `delete` | Nothing to create. Draw every frame. "Delete" means stop drawing the block. |
| `prim.set_texture` + `set_fit_to_texture` | Load the PNG as a D3D texture once (via ffi and `D3DXCreateTextureFromFileA`, or the textures helper in your Ashita build **(verify)**). Draw it with `imgui.Image(tex_ptr, {w, h})`. |
| `prim.set_color(a, r, g, b)` | The `tint_col` argument of `imgui.Image`, or `imgui.GetWindowDrawList():AddImage(..., col)`. |
| `prim.set_size(w, h)` | The size argument to `imgui.Image` / `imgui.SetNextWindowSize`. |
| `prim.set_position(x, y)` | `imgui.SetNextWindowPos({x, y})`, or `imgui.SetCursorScreenPos`. |
| `prim.set_visibility(b)` | `if visible then ... end`. |
| `text.create` / `delete` | Not needed, or `fonts.new(...)` if you use the `fonts` library. |
| `text.set_text` | Pass the string to `imgui.Text` / `TextColored`. |
| `text.set_color(a, r, g, b)` | `imgui.TextColored({r/255, g/255, b/255, a/255}, str)` |
| `text.set_font / set_font_size / set_bold` | `imgui.SetWindowFontScale(scale)` or the push-font API. Per-block font size and bold require ImGui font management. |
| `text.set_stroke_width / stroke_color` | No built-in stroke. Draw the text twice with an offset, using `AddText` on the draw list. |
| `text.set_location(x, y)` | `imgui.SetCursorScreenPos` or `drawlist:AddText({x, y}, color, str)` |
| `text.get_extents(name)` (`centre_all_text`) | `imgui.CalcTextSize(str)` |
| Mouse-drag handler on the background block | Remove it. Use one ImGui window containing the grid. ImGui handles dragging, and you save its position (`imgui.GetWindowPos()`) to settings. |

Windower's "ui scaling" comment (resolution divided by the UI scale) is not an issue under ImGui, which works in real pixels.

### 2d. Libraries

| Windower lib | Ashita v4 replacement |
|---|---|
| `require('config')` (XML settings, `config.load`, `settings:save('all')`) | `local settings = require('settings')`, then `settings.load(defaults)`, `settings.save()` and `settings.register('settings', 'gi_settings', cb)`. Files are Lua. The old XML format cannot be reused, so migrate or reset. |
| `require('lists')`, `require('tables')` (`L{}`, `S{}`, `T{}`, `table.length`, `table.containskey`, `table.copy`, `table.reassign`, `:contains`, `:filter`, `:map`, `table.vprint`) | Plain Lua tables plus `require('common')` helpers (`table.contains`, `table.count`, `table.append`, etc.). Write small local helpers for the rest (`containskey`, `copy`, `length`). Sets become `{[k] = true}`. |
| `require('strings')` (`:contains`, `:psplit`, `string.gsub`, `ucfirst`) | Lua string functions plus `require('common')` (`string.split`, `string.trim`, `string.starts`, ...). |
| `require('logger')` (`log`, `notice`, `error`) | `print(chat.header(addon.name):append(chat.message(msg)))`, `chat.error(...)`, `chat.warning(...)` |
| `require('pack')` (`data:unpack`) | `struct.unpack` / `struct.pack` (Ashita `common`) |
| `require('bit')` | LuaJIT `bit` is already available (`local bit = require('bit')`). |
| `require('chat')`, `require('chat.chars')` | `local chat = require('chat')`. `chat.controls.reset` becomes `chat.message`, `chat.color1(n, s)` or the `\30\n` / `\31\n` color codes. Replace the `chars.circleN` / `implies` glyphs with literal characters. |
| `require('packets')` (`packets.parse`) | Manual `struct.unpack` (see section 1). |
| `require('timeit')` | `os.clock()` (the `timer` variable is unused). |
| `require('extdata')` (`Extdata.decode`, used for augments in `find_all_values` and `check_equipped`) | **No equivalent.** Port Windower's `extdata.lua` to Ashita, or write your own augment decoder from `item.Extra`. This is the largest single piece of work. |
| `require('resources')` (`res.*`) | `AshitaCore:GetResourceManager()` (see below). |

### 2e. Resources (`res.*`)

| Windower | Ashita v4 |
|---|---|
| `res.items:with('id', id)` | `rm:GetItemById(id)`. Fields are PascalCase: `.Id`, `.Name[1]` (English), `.Description[1]`, `.Flags`, `.Slots`, `.Jobs`, `.Level`, `.ItemLevel`, `.Delay`, `.Damage`, `.Skill`. |
| `res.item_descriptions` | `item.Description[1]` |
| `item.flags:contains('Equippable')` | `item.Slots ~= 0` or a bit test on `.Flags` **(verify)**. |
| `res.slots`, `res.jobs`, `res.skills` | `rm:GetString('jobs.names_abbr', id)`, `rm:GetString('skills.names', id)`, etc. Slot bitmasks come from the item's `.Slots`. |
| `res.spells:with('id'/'en', ...)` | `rm:GetSpellById(id)` and `rm:GetSpellByName(name, 0)`. Name is `.Name[1]`. The type is `.Skill` (singing is skill 40). |
| `res.job_abilities:with('id', ...)` | `rm:GetAbilityById(id)`. Pet-ability id ranges differ, so check them. |
| `res.buffs[id]` | `rm:GetString('buffs.names', id)` |
| `res.bags` | Container ids: 0 inventory, 1 safe, 2 storage, 3 temp, 4 locker, 5 satchel, 6 sack, 7 case, 8 wardrobe, 9 safe2, 10 wardrobe2, 11 wardrobe3, 12 wardrobe4. These are the same as Windower's. |
| `res.spells:type('BlueMagic')` (unused `blu_spells`) | Delete. |

Many Windower resource fields (`english`, `ens`, `item_level`, `defined_job`) are not present as such. Consider dumping the needed resource data to your own Lua tables once.

---

## 3. Player state (replaces `windower.ffxi.get_player()`)

The addon expects fields like `player.main_job`, `main_job_level`, `sub_job`, `sub_job_level`, `merits`, `job_points[job].jp_spent`, `skills`, `buffs`, `id`, `name`, `index` and `equipment`. Build them each tick from the memory managers:

```lua
local mm      = AshitaCore:GetMemoryManager()
local party   = mm:GetParty()
local playerM = mm:GetPlayer()
local ents    = mm:GetEntity()

player.name           = party:GetMemberName(0)
player.id             = party:GetMemberServerId(0)
player.index          = party:GetMemberTargetIndex(0)
player.main_job       = jobAbbr(playerM:GetMainJob())          -- string, e.g. 'WAR'
player.main_job_level = playerM:GetMainJobLevel()
player.sub_job        = jobAbbr(playerM:GetSubJob())           -- nil if 0
player.sub_job_level  = playerM:GetSubJobLevel()
player.buffs          = playerM:GetBuffs()                     -- 0xFF / -1 = empty
```

Skills, merits and job points come from `IPlayer` getters. Exact names vary by Ashita build, so check them **(verify)**. Alternatively, keep the existing `0x62` (skills) parse, and add a `0x63` type 8/merit packet parse if needed.

---

## 4. Cautions for the port

1. **Game-state access.** The code assumes a Lua table snapshot. Wrap the memory-manager reads in one `get_player()` function so the rest of the code stays unchanged.
2. **0-based vs 1-based.** Ashita getters take 0-based indices (party 0..5, entity index). Windower tables used `p0..p5` keys and 1-based arrays.
3. **Buff duration.** Windower computed buff timers from packet `0x063` with a custom epoch. The same packet works in Ashita, but `GetPlayer():GetStatusTimers()` is simpler.
4. **Global leakage.** Many functions in the source assign to undeclared globals (`cap`, `str`, `value`, `rollMembers`). Ashita addons run in a shared Lua state per addon, so this is fine, but `local` them while you're in there.
5. **File I/O.** `windower.addon_path .. 'data/'` becomes the per-addon config folder. `tovstring()` (Windower table serializer) needs a replacement. Write a small Lua table serializer.
6. **Texture themes.** `textures/<theme>/<color>.png` can stay as is under `addon.path`. Only the draw path changes.
7. **Suggested order:** (a) event skeleton, (b) player/party/inventory shims, (c) resources and extdata, (d) packet parsers, (e) action (0x28) parser, (f) ImGui rendering, (g) settings and commands, (h) GearSwap link.
