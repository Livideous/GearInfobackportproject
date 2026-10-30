--[[
* GearInfo (Ashita v4 port) - lib/game.lua
*
* The 'windower' namespace the original addon was written against, rebuilt on Ashita v4.
*
* What is translated here:
*   * windower.ffxi.get_info/get_player/get_party/get_items/get_mob_by_* are backed by
*     AshitaCore:GetMemoryManager() interfaces.
*   * windower.register_event() feeds a small dispatcher, which lib/packets.lua raises for
*     'incoming chunk', 'outgoing chunk' and the synthesised 'action' event.
*   * windower.packets.last_incoming/last_outcoming read lib/packets.lua's history ring
*     (Ashita's IPacketManager has no "last packet" API).
*   * windower.add_to_chat()/send_command() go through IChatManager:QueueCommand().
*   * game.bind_events() registers the Ashita events behind those names: 'load', 'unload',
*     'command' -> 'addon command', 'packet_in'/'packet_out' -> 'incoming/outgoing chunk',
*     'text_in' -> 'incoming text', 'd3d_present' -> 'prerender'. Ashita has no login or logout
*     event, so the frame handler polls the login state and raises them on a change.
*
* Conventions worth knowing:
*   * Container ids returned by res.bags and accepted/produced by get_items() use Ashita's
*     container numbering (0 = Inventory, 1 = Safe, ... 16 = Wardrobe 8). The addon only ever
*     round trips those ids through this module, so no Windower numbering is involved.
*   * Container item indices are 0 based, exactly like the server's, so an equipment Index's
*     low byte is the slot and the high byte is the container.
*   * entity.distance stays squared, like Windower's, so call sites keep needing a square root.
--]]

require 'common';

local resources = require 'lib.resources';
local bitstream = require 'lib.bitstream';
local packets   = require 'lib.packets';

bitstream.install();

local game = { };

---------------------------------------------------------------------------
-- Memory handles
---------------------------------------------------------------------------
local chat_mgr      = AshitaCore:GetChatManager();
local mem_mgr       = AshitaCore:GetMemoryManager();
local entity_mem    = mem_mgr:GetEntity();
local player_mem    = mem_mgr:GetPlayer();
local party_mem     = mem_mgr:GetParty();
local inventory_mem = mem_mgr:GetInventory();
local target_mem    = mem_mgr:GetTarget();

-- The client keeps 2304 entity slots; Ashita's own ffxi.targets library scans the same range.
local MAX_ENTITY_INDEX = 2303;

-- The Gil pseudo item, same id Windower reports in inventory slot 0.
local GIL_ITEM_ID = 65535;

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
game.events = { };

---Registers a Windower style event handler.
---@param name string
---@param fn function
function game.register_event(name, fn)
    if (type(name) ~= 'string' or type(fn) ~= 'function') then
        error('windower.register_event(name, fn) needs a string and a function.', 2);
    end
    local handlers = game.events[name];
    if (handlers == nil) then
        handlers = { };
        game.events[name] = handlers;
    end
    handlers[#handlers + 1] = fn;
end

---Raises an event and returns the first non nil handler result.
---'incoming text' uses that result to block or rewrite the message.
---@param name string
---@return any
function game.dispatch(name, ...)
    local handlers = game.events[name];
    if (handlers == nil) then return nil; end
    for i = 1, #handlers do
        local result = handlers[i](...);
        if (result ~= nil) then
            return result;
        end
    end
    return nil;
end

---Removes every handler registered through windower.register_event().
function game.clear_events()
    game.events = { };
end

---------------------------------------------------------------------------
-- Login state
---------------------------------------------------------------------------
---Ashita has no login/logout events, so the entry file polls this and emits them on a change.
---@return boolean
function game.is_logged_in()
    if (player_mem:GetLoginStatus() ~= 2) then
        return false;
    end
    return party_mem:GetMemberServerId(0) ~= 0;
end

---Returns the players target index, or 0 when nobody is in game.
---@return number
function game.player_index()
    return party_mem:GetMemberTargetIndex(0) or 0;
end

---------------------------------------------------------------------------
-- Manual data
-- Ashita exposes no merit ranks, job point gifts or the blue magic spell set, so those values
-- are held here and filled in by the '/gi merit', '/gi jp' and '/gi blu' commands.
---------------------------------------------------------------------------
game.manual = {
    merits      = { },
    job_points  = { },
    blue_spells = nil,
};

local DEFAULT_MERITS = {
    aggressive_aim    = 0,
    desperate_blows   = 0,
    ikishoten         = 0,
    store_tp_effect   = 0,
};

-- The job point gifts the addon addresses by name, as opposed to through the point totals. Ashita does
-- not expose them, so they would be nil and the arithmetic reading them would fault until '/gi jp' is
-- used; they default to zero instead, which is what an unspent gift is worth.
local DEFAULT_GIFTS = {
    rdm = { composure_effect = 0 },
};

---Returns the manual value for a merit, falling back to zero.
---@param name string
---@return number
function game.get_merit(name)
    local value = game.manual.merits[name];
    if (value == nil) then
        value = DEFAULT_MERITS[name];
    end
    return value or 0;
end

---------------------------------------------------------------------------
-- Skills
---------------------------------------------------------------------------
--[[
* Ashita's combat skill array matches Windower's res.skills ids for 1..12 (Hand-to-Hand to Staff) and
* is one denser from the automaton block upwards, because Ashita drops one of the reserved (N/A)
* slots: Ashita 22 is Automaton Melee where Windower ids it 23, and Ashita 43 is Blue Magic where
* Windower ids it 44.
--]]
local function windower_skill_id(ashita_index)
    if (ashita_index <= 12) then
        return ashita_index;
    end
    return ashita_index + 1;
end

---Returns the players current combat skills keyed the way Windower's 0x062 parser keys them
---('hand_to_hand', 'great_sword'), so memory values and packet values land on the same table.
---@return table
function game.get_skills()
    local skills = T{ };
    for index = 1, 45 do
        local entry = resources.skills[windower_skill_id(index)];
        if (entry ~= nil and entry.english ~= nil) then
            local skill = player_mem:GetCombatSkill(index);
            if (skill ~= nil) then
                local key = string.lower(string.gsub(entry.english, ' ', '_'));
                skills[key] = tonumber(skill:GetSkill()) or 0;
            end
        end
    end
    return skills;
end

---------------------------------------------------------------------------
-- Buffs
---------------------------------------------------------------------------
--[[
* GetBuffs() and GetStatusTimers() come back as a plain Lua table on some Ashita builds and as a
* userdata array on others, and the arrays are 0 or 1 based depending on the build. Both shapes are
* read by index and the whole access is protected, because a nil player pointer throws on some builds.
--]]
local function buff_slot(raw, slot)
    if (raw == nil) then
        return nil;
    end
    local ok, value = pcall(function () return raw[slot]; end);
    if (not ok) then
        return nil;
    end
    return tonumber(value);
end

---Returns the players buff ids paired with their remaining time in seconds.
---Both tables use the same order, so buffs[i] belongs to timers[i].
---@return table buffs, table timers
function game.get_buff_list()
    local buffs  = T{ };
    local timers = T{ };

    local raw_buffs  = player_mem:GetBuffs();
    local raw_timers = player_mem:GetStatusTimers();
    if (raw_buffs == nil) then
        return buffs, timers;
    end

    for slot = 0, 32 do
        local id = buff_slot(raw_buffs, slot);
        if (id ~= nil and id > 0 and id ~= 255) then
            buffs[#buffs + 1] = id;
            timers[#timers + 1] = buff_slot(raw_timers, slot) or 0;
        end
    end

    return buffs, timers;
end

---------------------------------------------------------------------------
-- Entities
---------------------------------------------------------------------------
local server_id_cache  = { };
local missed_server_id = { };

-- How long a failed id lookup stays cached. Entities appear a moment after the action that
-- references them, so the window is short but keeps the action stream from rescanning 2304 slots.
local NEGATIVE_CACHE_SECONDS = 2;

local function now()
    return tonumber(os and os.clock and os.clock()) or 0;
end

--[[
* Ashita has no per entity job field, so mob.type stays the raw entity type and the job is only
* resolved for the player through IPlayer. Distance is the squared value the client stores, exactly
* like Windower's, which is why the ported call sites still wrap it in math.sqrt().
--]]

---Returns the Windower style entity table for a target index.
---@param index number
---@return table|nil
function game.get_mob_by_index(index)
    index = tonumber(index);
    if (index == nil or index < 0 or index > MAX_ENTITY_INDEX) then
        return nil;
    end

    local ment = entity_mem:GetRawEntity(index);
    if (ment == nil or ment.Name == nil or ment.Name == '') then
        return nil;
    end

    local spawn       = bit.band(tonumber(entity_mem:GetSpawnFlags(index)) or 0, 0xFFFF);
    local claim       = bit.band(tonumber(entity_mem:GetClaimStatus(index)) or 0, 0xFFFF);
    local pet_index   = tonumber(entity_mem:GetPetTargetIndex(index)) or 0;
    local trust_owner = tonumber(entity_mem:GetTrustOwnerTargetIndex(index)) or 0;

    local mob = T{ };
    mob.index        = index;
    mob.id           = tonumber(ment.ServerId) or 0;
    mob.name         = ment.Name;
    mob.name_escaped = ment.Name;
    mob.nm           = false;
    mob.type         = tonumber(entity_mem:GetType(index)) or 0;
    mob.race         = tonumber(entity_mem:GetRace(index)) or 0;
    mob.zone         = tonumber(entity_mem:GetZoneId(index)) or 0;
    mob.status       = tonumber(entity_mem:GetStatus(index)) or 0;
    mob.hpp          = tonumber(entity_mem:GetHPPercent(index)) or 0;
    mob.distance     = tonumber(entity_mem:GetDistance(index)) or 0;
    mob.target_index = tonumber(entity_mem:GetTargetIndex(index)) or 0;
    mob.targetable   = tonumber(entity_mem:GetTargetedIndex(index)) or 0;
    mob.pet_index    = pet_index ~= 0 and pet_index or nil;
    mob.master_index = trust_owner ~= 0 and trust_owner or nil;
    mob.spawn_index  = mob.id;
    mob.mount        = tonumber(entity_mem:GetMountId(index)) or 0;

    -- Windower treats every non player entity as an npc, so players own both this bit and a claim.
    mob.is_npc  = bit.band(spawn, 0x0001) == 0;
    mob.in_list = false;
    mob.charmed = false;

    -- GearInfo reads mob.charmed to spot the players own trusts and pets acting on it.
    if (mob.is_npc) then
        local player_id   = tonumber(party_mem:GetMemberServerId(0)) or 0;
        local player_idx  = game.player_index();
        if ((claim ~= 0 and claim == player_id) or (trust_owner ~= 0 and trust_owner == player_idx)) then
            mob.charmed = true;
        end
    end

    mob.casting = false;
    mob.cast    = nil;
    mob.tp      = 0;

    local pos = ment.Movement and ment.Movement.LocalPosition;
    mob.x = tonumber(pos and pos.X) or 0;
    mob.y = tonumber(pos and pos.Z) or 0;
    mob.z = tonumber(pos and pos.Y) or 0;
    mob.pos = T{ x = mob.x, y = mob.y, z = mob.z };

    return mob;
end

---Resolves a server id to an entity index, scanning the entity table and caching the result.
---@param id number
---@return number|nil
function game.index_from_server_id(id)
    id = tonumber(id);
    if (id == nil or id == 0) then
        return nil;
    end

    local index = server_id_cache[id];
    if (index ~= nil) then
        if (tonumber(entity_mem:GetServerId(index)) == id) then
            return index;
        end
        server_id_cache[id] = nil;
    end

    local missed = missed_server_id[id];
    if (missed ~= nil and now() - missed < NEGATIVE_CACHE_SECONDS) then
        return nil;
    end

    for scan = 0, MAX_ENTITY_INDEX do
        if (tonumber(entity_mem:GetServerId(scan)) == id) then
            if (game.get_mob_by_index(scan) ~= nil) then
                server_id_cache[id] = scan;
                missed_server_id[id] = nil;
                return scan;
            end
        end
    end

    missed_server_id[id] = now();
    return nil;
end

---Returns the Windower style entity table for a server id.
---@param id number
---@return table|nil
function game.get_mob_by_id(id)
    local index = game.index_from_server_id(id);
    if (index == nil) then
        return nil;
    end
    return game.get_mob_by_index(index);
end

---Returns the Windower style entity table for a Windower target expression.
---@param target string 'me', 't', 'lt', 'st'
---@return table|nil
function game.get_mob_by_target(target)
    target = string.lower(tostring(target or 'me'));

    if (target == 'me') then
        return game.get_mob_by_index(game.player_index());
    end

    local index = 0;
    if (target == 't') then
        if (target_mem:GetIsSubTargetActive() == 0) then
            index = target_mem:GetTargetIndex(0);
        else
            index = target_mem:GetTargetIndex(1);
        end
    elseif (target == 'lt') then
        index = target_mem:GetTargetIndex(1);
    elseif (target == 'st') then
        if (target_mem:GetIsSubTargetActive() == 0) then
            return nil;
        end
        index = target_mem:GetTargetIndex(0);
    end

    if (index == nil or index == 0) then
        return nil;
    end
    return game.get_mob_by_index(index);
end

---Drops the server id caches - call on zone or login changes.
function game.clear_entity_caches()
    server_id_cache  = { };
    missed_server_id = { };
end

---------------------------------------------------------------------------
-- Player
---------------------------------------------------------------------------
---Returns the base and equipment modified main stats, the way Windower's 0x061 reports them.
---@return table
local function player_stats()
    local stats = T{ };
    local names = { 'STR', 'DEX', 'VIT', 'AGI', 'INT', 'MND', 'CHR' };
    for i = 0, 6 do
        local base  = tonumber(player_mem:GetStat(i)) or 0;
        local added = tonumber(player_mem:GetStatModifier(i)) or 0;
        stats[names[i + 1]] = base + added;
    end
    return stats;
end

---Windower's job points table, keyed by the lowercase job abbreviation.
---@return table
local function job_points()
    local ret = T{ };
    for id = 1, 22 do
        local job = resources.job_names[id];
        if (job ~= nil) then
            local key = string.lower(job.ens);
            local spent = tonumber(player_mem:GetJobPointsSpent(id)) or 0;
            local entry = T{
                jp_total = tonumber(player_mem:GetJobPoints(id)) or 0,
                jp_spent = spent,
            };
            local defaults = DEFAULT_GIFTS[key];
            if (defaults ~= nil) then
                for name, value in pairs(defaults) do
                    entry[name] = value;
                end
            end
            local manual = game.manual.job_points[key];
            if (manual ~= nil) then
                for name, value in pairs(manual) do
                    entry[name] = value;
                end
            end
            ret[key] = entry;
        end
    end
    return ret;
end

---Windower's merits table, limited to what the addon reads plus the manual overrides.
---@return table
local function merits()
    local ret = T{ };
    for name in pairs(DEFAULT_MERITS) do
        ret[name] = game.get_merit(name);
    end
    for name, value in pairs(game.manual.merits) do
        ret[name] = value;
    end
    ret.point_total = tonumber(player_mem:GetMeritPoints()) or 0;
    ret.points      = ret.point_total;
    ret.point_max   = tonumber(player_mem:GetMeritPointsMax()) or 0;
    return ret;
end

---Returns the Windower style player table.
---@return table|nil
function game.get_player()
    if (not game.is_logged_in()) then
        return nil;
    end

    local index = game.player_index();
    local mob   = game.get_mob_by_index(index);
    if (mob == nil) then
        return nil;
    end

    local main_job = tonumber(player_mem:GetMainJob()) or 0;
    local sub_job  = tonumber(player_mem:GetSubJob()) or 0;

    local player = T{ };
    player.id             = mob.id;
    player.index          = index;
    player.name           = mob.name;
    player.is_zoning      = player_mem:GetIsZoning() == 1;
    player.main_job       = (resources.job_names[main_job] or { ens = '' }).ens;
    player.main_job_id    = main_job;
    player.main_job_level = tonumber(player_mem:GetMainJobLevel()) or 0;
    player.sub_job        = sub_job ~= 0 and (resources.job_names[sub_job] or { ens = '' }).ens or nil;
    player.sub_job_id     = sub_job;
    player.sub_job_level  = tonumber(player_mem:GetSubJobLevel()) or 0;
    player.job            = player.main_job;
    player.job_abbr       = player.main_job;
    player.level          = player.main_job_level;
    player.nation         = tonumber(player_mem:GetNation()) or 0;
    player.rank           = tonumber(player_mem:GetRank()) or 0;
    player.rank_points    = tonumber(player_mem:GetRankPoints()) or 0;
    player.cp             = tonumber(player_mem:GetCapacityPoints(main_job)) or 0;
    player.status         = tonumber(entity_mem:GetStatus(index)) or 0;
    player.hpp            = mob.hpp;
    player.hp             = tonumber(party_mem:GetMemberHP(0)) or 0;
    player.max_hp         = tonumber(player_mem:GetHPMax()) or 0;
    player.mp             = tonumber(party_mem:GetMemberMP(0)) or 0;
    player.max_mp         = tonumber(player_mem:GetMPMax()) or 0;
    player.mpp            = tonumber(party_mem:GetMemberMPPercent(0)) or 0;
    player.tp             = tonumber(party_mem:GetMemberTP(0)) or 0;
    player.equipment      = T{ };
    player.merits         = merits();
    player.job_points     = job_points();
    player.stats          = player_stats();
    player.skills         = game.get_skills();

    local buffs, timers = game.get_buff_list();
    player.buffs        = buffs;
    player.buff_timers  = timers;

    return player;
end

---------------------------------------------------------------------------
-- Party
---------------------------------------------------------------------------
---Alliance slices, in Windower's key format ('p0', 'al0', 'a2_0').
local PARTY_GROUPS = {
    { format = '%s%d', prefix = 'p',  offset = 0,  count = function () return party_mem:GetAlliancePartyMemberCount1(); end },
    { format = '%s%d', prefix = 'al', offset = 6,  count = function () return party_mem:GetAlliancePartyMemberCount2(); end },
    { format = '%s_%d', prefix = 'a2', offset = 12, count = function () return party_mem:GetAlliancePartyMemberCount3(); end },
};

---Returns the Windower style party/alliance table.
---@return table
function game.get_party()
    local party = T{ };

    for _, group in ipairs(PARTY_GROUPS) do
        local count = tonumber(group.count()) or 0;
        if (count > 6) then count = 6; end
        for i = 0, count - 1 do
            local slot  = group.offset + i;
            local name  = party_mem:GetMemberName(slot);
            local index = tonumber(party_mem:GetMemberTargetIndex(slot)) or 0;

            if (name ~= nil and name ~= '') then
                local member = T{ };
                member.index = index;
                member.id    = tonumber(party_mem:GetMemberServerId(slot)) or 0;
                member.name  = name;
                member.hp    = tonumber(party_mem:GetMemberHP(slot)) or 0;
                member.hpp   = tonumber(party_mem:GetMemberHPPercent(slot)) or 0;
                member.mp    = tonumber(party_mem:GetMemberMP(slot)) or 0;
                member.mpp   = tonumber(party_mem:GetMemberMPPercent(slot)) or 0;
                member.tp    = tonumber(party_mem:GetMemberTP(slot)) or 0;
                member.zone  = tonumber(party_mem:GetMemberZone(slot)) or 0;
                -- A member outside the zone has no entity, and the addon relies on mob being nil.
                member.mob   = index ~= 0 and game.get_mob_by_index(index) or nil;

                local job = tonumber(party_mem:GetMemberMainJob(slot)) or 0;
                member.main_job = (resources.job_names[job] or { ens = '' }).ens;
                member.main_job_level = tonumber(party_mem:GetMemberMainJobLevel(slot)) or 0;
                local sub = tonumber(party_mem:GetMemberSubJob(slot)) or 0;
                member.sub_job = sub ~= 0 and (resources.job_names[sub] or { ens = '' }).ens or nil;
                member.sub_job_level = tonumber(party_mem:GetMemberSubJobLevel(slot)) or 0;

                party[group.format:fmt(group.prefix, i)] = member;
            end
        end
    end

    return party;
end

---------------------------------------------------------------------------
-- Inventory
---------------------------------------------------------------------------
---Wraps one container entry in Windower's item shape.
---Gil is the client's pseudo item 65535 in inventory slot 0; the addon has no use for it and
---res.items has no entry for it, so it is reported as an empty slot.
---@param container number
---@param slot number
---@return table|nil
local function make_item(container, slot)
    local cit = inventory_mem:GetContainerItem(container, slot);
    if (cit == nil) then
        return nil;
    end

    local id = tonumber(cit.Id) or 0;
    if (id == 0 or id == GIL_ITEM_ID) then
        return nil;
    end

    return T{
        id      = id,
        index   = slot,
        slot    = slot,
        bag     = container,
        count   = tonumber(cit.Count) or 0,
        status  = 0,
        bazaar  = 0,
        flags   = tonumber(cit.Flags) or 0,
        price   = tonumber(cit.Price) or 0,
        extdata = cit.Extra or '',
    };
end

---Returns every item in a container, keyed by its 0 based slot.
---@param container number
---@return table
local function get_container(container)
    local items = T{ };
    local max = tonumber(inventory_mem:GetContainerCountMax(container)) or 0;
    for slot = 0, max - 1 do
        local item = make_item(container, slot);
        if (item ~= nil) then
            items[slot] = item;
        end
    end
    return items;
end

---Windower's windower.ffxi.get_items().
---@param bag? number
---@param slot? number
---@return table
function game.get_items(bag, slot)
    bag  = tonumber(bag);
    slot = tonumber(slot);

    if (bag ~= nil and slot ~= nil) then
        return make_item(bag, slot);
    end
    if (bag ~= nil) then
        return get_container(bag);
    end

    local all = T{ };
    for _, entry in ipairs(resources.bag_list) do
        all[entry.en] = get_container(entry.id);
    end

    local equipment = T{ };
    for index = 0, 15 do
        local name   = resources.equip_slots[index + 1];
        local entry  = inventory_mem:GetEquippedItem(index);
        local packed = tonumber(entry and entry.Index) or 0;
        -- The packed index is (container << 8) | slot, so an empty slot reads back as 0.
        equipment[name]      = bit.band(packed, 0xFF);
        equipment[name .. '_bag'] = bit.band(bit.rshift(packed, 8), 0xFF);
    end
    all.equipment = equipment;
    all.current   = tonumber(inventory_mem:GetContainerCount(0)) or 0;
    all.temp      = get_container(3);
    all.key_items = T{ };

    return all;
end

---------------------------------------------------------------------------
-- Main job data
---------------------------------------------------------------------------
-- Cached 'known spells' fallback for the blue magic set, rebuilt when the main job changes.
local blue_fallback = nil;

---Windower's windower.ffxi.get_mjob_data().
---@return table
function game.get_mjob_data()
    local data = T{ };
    data.job   = tonumber(player_mem:GetMainJob()) or 0;
    data.level = tonumber(player_mem:GetMainJobLevel()) or 0;
    data.mjob  = data.job;

    local spells = game.manual.blue_spells;
    if (spells == nil) then
        -- Ashita exposes which blue spells are known, not which are set, so the known list is used
        -- as a fallback. It is built once per job change and '/gi blu' replaces it with the real set.
        if (blue_fallback == nil or blue_fallback.job ~= data.job) then
            local list = T{ };
            for id = 231, 1024 do
                if (player_mem:HasSpell(id) == 1) then
                    list[#list + 1] = id;
                end
            end
            blue_fallback = { job = data.job, spells = list };
        end
        spells = blue_fallback.spells;
    end
    data.spells = spells;

    data.merits     = merits();
    data.job_points = job_points();
    data.skills     = game.get_skills();

    return data;
end

---------------------------------------------------------------------------
-- windower namespace
---------------------------------------------------------------------------
local windower = T{ };

---Always carries the trailing separator, like Windower's windower.addon_path.
windower.addon_path = (addon.path .. '\\');

---Writes a line to the chat log. Windower selects a default color with 'mode'; GearInfo
---always embeds its own color escapes, so the text goes straight to the log.
---@param mode number
---@param msg string
function windower.add_to_chat(mode, msg)
    if (msg == nil) then return; end
    chat_mgr:QueueCommand(1, ('/echo %s'):fmt(tostring(msg)));
end

---Queues a command for the client, exactly like windower.send_command().
---Windower accepted a command with no leading slash and added it itself; Ashita's QueueCommand()
---would otherwise type the text into the chat input, so the slash is restored here.
---@param str string
function windower.send_command(str)
    if (str == nil) then return; end
    str = tostring(str);
    if (str:sub(1, 1) ~= '/' and str:sub(1, 1) ~= '\\') then
        str = '/' .. str;
    end
    chat_mgr:QueueCommand(1, str);
end

---@param path string
---@return boolean
function windower.dir_exists(path)
    return ashita.fs.exists(tostring(path));
end

---@return table
function windower.get_windower_settings()
    return T{
        xi_path      = AshitaCore:GetInstallPath(),
        lua_version  = string.format('%d.%d', math.floor(_VERSION:sub(5) * 10), (_VERSION:sub(5) * 10) % 10),
        version      = 'ashita-v4',
        ui_settings  = T{ x = 0, y = 0, wide = 0, tall = 0 },
    };
end

windower.register_event = game.register_event;

---Ashita's IPacketManager has no 'last packet' API, so reads come from lib/packets.lua's ring and
---only cover traffic observed since the addon loaded.
windower.packets = T{
    last_incoming = packets.last_incoming,
    last_outgoing = packets.last_outgoing,
};

---Returns the players current zone id, preferring the entity over the party entry.
---@return number
local function current_zone()
    local index = game.player_index();
    if (index ~= 0) then
        local zone = tonumber(entity_mem:GetZoneId(index)) or 0;
        if (zone ~= 0) then
            return zone;
        end
    end
    return tonumber(party_mem:GetMemberZone(0)) or 0;
end

windower.ffxi = T{
    get_info          = function ()
        local zone = current_zone();
        return T{
            logged_in = game.is_logged_in(),
            playing   = game.is_logged_in(),
            zone      = zone,
            zone_id   = zone,
        };
    end,
    get_player        = game.get_player,
    get_party         = game.get_party,
    get_items         = game.get_items,
    get_mjob_data     = game.get_mjob_data,
    get_mob_by_index  = game.get_mob_by_index,
    get_mob_by_id     = game.get_mob_by_id,
    get_mob_by_target = game.get_mob_by_target,
};

_G.windower = windower;

---------------------------------------------------------------------------
-- Packet plumbing
---------------------------------------------------------------------------
packets.set_dispatcher(game.dispatch);

---Forgets cached packets and entity lookups when the player logs out or changes zone.
function game.on_character_change()
    packets.clear();
    game.clear_entity_caches();
    blue_fallback = nil;
end

---------------------------------------------------------------------------
-- Ashita event bridge
---------------------------------------------------------------------------

---LuaJIT's global unpack; table.unpack only exists on 5.2+.
local unpack = unpack or table.unpack;

---Reports a handler error the way Windower did - in the chat log for player triggered events, with
---print() as the fallback while notice() is not installed yet.
---@param err any
local function report(err)
    if (type(notice) == 'function') then
        notice(tostring(err));
    else
        print(('[gearinfo] %s'):fmt(tostring(err)));
    end
end

game.bound = false;

---Registers the Ashita events that raise the Windower event names the ported code uses.
---
---'load', 'unload', 'addon command', 'prerender', 'incoming text', 'incoming chunk' and
---'outgoing chunk' all exist in Windower; Ashita names them 'load', 'unload', 'command',
---'d3d_present' and 'text_in' with different arguments, and has no login/logout events at all.
---The last two are polled from the frame handler, which is also where a character change is
---detected.
---@param prefix? string Alias prefix for the Ashita event registrations.
function game.bind_events(prefix)
    if (game.bound) then return end
    game.bound = true;
    prefix = prefix or 'gearinfo';

    local logged_in = game.is_logged_in();

    ashita.events.register('load', (prefix .. '_load_cb'), function ()
        logged_in = game.is_logged_in();
        game.dispatch('load');
    end);

    ashita.events.register('unload', (prefix .. '_unload_cb'), function ()
        game.dispatch('unload');
    end);

    ashita.events.register('packet_in', (prefix .. '_packet_in_cb'), function (e)
        packets.on_in(e);
    end);

    ashita.events.register('packet_out', (prefix .. '_packet_out_cb'), function (e)
        packets.on_out(e);
    end);

    -- Windower hands the 'addon command' handler (command, ...) with the command word removed.
    ashita.events.register('command', (prefix .. '_command_cb'), function (e)
        local handlers = game.events['addon command'];
        if (handlers == nil) then return end

        local args = tostring(e.command or ''):args();
        if (#args == 0) then return end
        local head = args[1]:lower();
        if (head ~= '/gi' and head ~= '/gearinfo') then return end

        e.blocked = true;

        local rest = { };
        for i = 2, #args do
            rest[i - 1] = args[i];
        end
        for i = 1, #handlers do
            local ok, err = pcall(handlers[i], rest[1], unpack(rest, 2));
            if (not ok) then
                report(err);
            end
        end
    end);

    -- 'incoming text' may block the line, rewrite it, or leave it alone, so both return values
    -- of every handler are kept rather than only the first one game.dispatch() would report.
    ashita.events.register('text_in', (prefix .. '_text_in_cb'), function (e)
        local handlers = game.events['incoming text'];
        if (handlers == nil or e.blocked) then return end

        local modified = e.message_modified;
        local mode     = tonumber(e.mode_modified) or 0;
        for i = 1, #handlers do
            local ok, first, second = pcall(handlers[i], e.message_original, modified, mode);
            if (not ok) then
                print(('[gearinfo] text_in handler failed: %s'):fmt(tostring(first)));
            elseif (first == true) then
                e.blocked = true;
                return;
            elseif (type(first) == 'string') then
                modified = first;
                mode     = tonumber(second) or mode;
            end
        end
        e.message_modified = modified;
        e.mode_modified    = mode;
    end);

    ashita.events.register('d3d_present', (prefix .. '_present_cb'), function ()
        -- Ashita has no login/logout events: the change is detected here and reported with the
        -- Windower names, and the caches are dropped the same way Windower dropped them on a switch.
        local now_logged_in = game.is_logged_in();
        if (now_logged_in ~= logged_in) then
            logged_in = now_logged_in;
            game.on_character_change();
            game.dispatch(logged_in and 'login' or 'logout');
            -- The transition frame is skipped: the addon state is about to be rebuilt, and the
            -- frame handlers still hold the previous characters caches.
            return;
        end

        local handlers = game.events['prerender'];
        if (handlers ~= nil) then
            for i = 1, #handlers do
                local ok, err = pcall(handlers[i]);
                if (not ok) then
                    print(('[gearinfo] prerender handler failed: %s'):fmt(tostring(err)));
                end
            end
        end
    end);
end

return game;
