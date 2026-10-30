--[[
* GearInfo (Ashita v4 port)
* Resource shim - translates Windower's 'res' tables onto AshitaCore:GetResourceManager().
*
* Differences handled here:
*   - Ashita has no query helpers ('res.items:with(...)'); they are rebuilt below.
*   - Ashita stores names/descriptions in per-language slots and the english slot index is not
*     stable across builds; it is probed once (see english_slot()) instead of being hard-coded.
*   - Ashita has no 'res.skills', 'res.slots', 'res.bags' or augment-text string tables, so the
*     small static tables the addon needs are vendored here.
*   - Ashita exposes slot/job restrictions as bitmasks; Windower exposes them as keyed tables.
*   - Ashita stores item descriptions on the item; Windower keeps a separate res.item_descriptions.
*
* Entries are built lazily and cached, so repeated lookups for the same id are cheap. The cached
* wrapper tables are the same object every time (Windower behaves the same way for res.* entries).
--]]

require 'common';

local resources = { };

local rmgr = function ()
    return AshitaCore:GetResourceManager();
end;

-- Ashita language index used with Get*ByName().
local LANG_EN = 2;

--[[
* Ashita stores every name/description in per-language slots. The english slot moved between
* builds - addons in the field read 'Name[1]', the current SDK samples assert 'Name[3]' - so the
* index is probed once against an item that exists in every retail dataset and then cached.
* Nothing is cached when the resource manager is not ready yet, so the probe simply re-runs.
--]]
local PROBE_ITEM_ID   = 13787; -- Dalmatica
local PROBE_ITEM_NAME = 'Dalmatica';
local en_slot;

local function english_slot()
    if (en_slot ~= nil) then return en_slot end

    local rm = rmgr();
    if (rm == nil) then return 1 end

    local ok, item = pcall(function () return rm:GetItemById(PROBE_ITEM_ID) end);
    if (not ok or item == nil or item.Name == nil) then return 1 end

    for i = 0, 7 do
        local valid, value = pcall(function () return item.Name[i] end);
        if (valid and value == PROBE_ITEM_NAME) then
            en_slot = i;
            return i;
        end
    end
    return 1;
end

--[[
* Returns the english string from a Name/Description slot table, falling back to any slot that
* holds text so callers never see nil for an entry that exists.
--]]
local function eng(tbl)
    if (tbl == nil) then return nil end

    local slot = english_slot();
    local ok, value = pcall(function () return tbl[slot] end);
    if (ok and value ~= nil and value ~= '') then return value end

    for i = 0, 7 do
        local valid, entry = pcall(function () return tbl[i] end);
        if (valid and entry ~= nil and entry ~= '') then return entry end
    end
    return nil;
end

--[[
* The japanese slot has no fixed index either; take the first non-empty slot that is not english.
* GearInfo never reads '.jp', so this is best effort.
--]]
local function jpn(tbl, english)
    if (tbl == nil) then return nil end
    for i = 0, 7 do
        local ok, value = pcall(function () return tbl[i] end);
        if (ok and value ~= nil and value ~= '' and value ~= english) then return value end
    end
    return nil;
end

-- Resource id ranges used by the linear scans.
local MAX_ITEM_ID = 0xFFFF;
local MAX_SPELL_ID = 1024;
local MAX_ABILITY_ID = 0x1FF;
local MAX_BUFF_ID = 1024;

--[[
* Combat skill ids, indexed the way Windower indexes res.skills.
* Ashita has no 'skills' string table, so this is vendored.
]]
resources.skill_names = {
    [0]  = '(N/A)',           [1]  = 'Hand-to-Hand',    [2]  = 'Dagger',         [3]  = 'Sword',
    [4]  = 'Great Sword',     [5]  = 'Axe',             [6]  = 'Great Axe',      [7]  = 'Scythe',
    [8]  = 'Polearm',         [9]  = 'Katana',          [10] = 'Great Katana',   [11] = 'Club',
    [12] = 'Staff',
    [23] = 'Automaton: Melee Skill', [24] = 'Automaton: Ranged Skill', [25] = 'Automaton: Magic Skill',
    [26] = 'Archery',         [27] = 'Marksmanship',    [28] = 'Throwing',       [29] = 'Guarding',
    [30] = 'Evasion',         [31] = 'Shield',          [32] = 'Parrying',       [33] = 'Divine Magic',
    [34] = 'Healing Magic',   [35] = 'Enhancing Magic', [36] = 'Enfeebling Magic',
    [37] = 'Elemental Magic', [38] = 'Dark Magic',      [39] = 'Summoning Magic', [40] = 'Ninjutsu',
    [41] = 'Singing',         [42] = 'Stringed Instrument', [43] = 'Wind Instrument',
    [44] = 'Blue Magic',      [45] = 'Geomancy',        [46] = 'Handbell',
};

-- Magic skill id -> Windower's spell type name (res.spells[x].type / :type('BlueMagic')).
resources.skill_to_spell_type = {
    [33] = 'WhiteMagic', [34] = 'WhiteMagic', [35] = 'WhiteMagic', [36] = 'WhiteMagic',
    [37] = 'BlackMagic', [38] = 'BlackMagic',
    [39] = 'Summoning',  [40] = 'Ninjutsu',   [41] = 'BardSong',
    [44] = 'BlueMagic',  [45] = 'Geomancy',
};

-- Item slot bits, in Windower's res.slots id order (0 = main .. 15 = back).
resources.slot_bits = {
    { id = 0,  bit = 0x0001, en = 'Main',      jp = 'Main' },
    { id = 1,  bit = 0x0002, en = 'Sub',       jp = 'Sub' },
    { id = 2,  bit = 0x0004, en = 'Ranged',    jp = 'Ranged' },
    { id = 3,  bit = 0x0008, en = 'Ammo',      jp = 'Ammo' },
    { id = 4,  bit = 0x0010, en = 'Head',      jp = 'Head' },
    { id = 5,  bit = 0x0020, en = 'Body',      jp = 'Body' },
    { id = 6,  bit = 0x0040, en = 'Hands',     jp = 'Hands' },
    { id = 7,  bit = 0x0080, en = 'Legs',      jp = 'Legs' },
    { id = 8,  bit = 0x0100, en = 'Feet',      jp = 'Feet' },
    { id = 9,  bit = 0x0200, en = 'Neck',      jp = 'Neck' },
    { id = 10, bit = 0x0400, en = 'Waist',     jp = 'Waist' },
    { id = 11, bit = 0x0800, en = 'Left Ear',  jp = 'Left Ear' },
    { id = 12, bit = 0x1000, en = 'Right Ear', jp = 'Right Ear' },
    { id = 13, bit = 0x2000, en = 'Left Ring', jp = 'Left Ring' },
    { id = 14, bit = 0x4000, en = 'Right Ring',jp = 'Right Ring' },
    { id = 15, bit = 0x8000, en = 'Back',      jp = 'Back' },
};

-- Equipment slot id -> the key windower.ffxi.get_items().equipment uses.
-- Note the ranged slot is 'range', not 'ranged'.
resources.equip_slots = {
    'main', 'sub', 'range', 'ammo', 'head', 'body', 'hands', 'legs', 'feet',
    'neck', 'waist', 'left_ear', 'right_ear', 'left_ring', 'right_ring', 'back',
};

-- Job id -> { en, ens }. Ashita has no verified jobs string table, so this is vendored.
-- Id 0 is 'no job': the party packet reports it for a member with no sub job, and the addon reads
-- res.jobs:with('id', 0).ens, so it needs an entry rather than a nil.
resources.job_names = {
    [0]  = { en = 'Non',          ens = 'NON' },
    [1]  = { en = 'Warrior',      ens = 'WAR' }, [2]  = { en = 'Monk',           ens = 'MNK' },
    [3]  = { en = 'White Mage',   ens = 'WHM' }, [4]  = { en = 'Black Mage',     ens = 'BLM' },
    [5]  = { en = 'Red Mage',     ens = 'RDM' }, [6]  = { en = 'Thief',          ens = 'THF' },
    [7]  = { en = 'Paladin',      ens = 'PLD' }, [8]  = { en = 'Dark Knight',    ens = 'DRK' },
    [9]  = { en = 'Beastmaster',  ens = 'BST' }, [10] = { en = 'Bard',           ens = 'BRD' },
    [11] = { en = 'Ranger',       ens = 'RNG' }, [12] = { en = 'Samurai',        ens = 'SAM' },
    [13] = { en = 'Ninja',        ens = 'NIN' }, [14] = { en = 'Dragoon',        ens = 'DRG' },
    [15] = { en = 'Summoner',     ens = 'SMN' }, [16] = { en = 'Blue Mage',      ens = 'BLU' },
    [17] = { en = 'Corsair',      ens = 'COR' }, [18] = { en = 'Puppetmaster',   ens = 'PUP' },
    [19] = { en = 'Dancer',       ens = 'DNC' }, [20] = { en = 'Rune Fencer',    ens = 'RUN' },
    [21] = { en = 'Geomancer',    ens = 'GEO' },
};

-- Job name bit order used to decode IItem.Jobs; entry i carries job id i.
resources.job_bits = {
    'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG','SAM','NIN','DRG','SMN','BLU',
    'COR','PUP','DNC','RUN','GEO',
};

--[[
* Client containers, numbered the way Ashita's IInventory indexes them. Windower's res.bags uses a
* different numbering, but GearInfo only ever round trips these ids through
* windower.ffxi.get_items(), so the port standardises on Ashita's throughout.
]]
resources.bag_list = {
    { id = 0,  en = 'inventory' },   { id = 1,  en = 'safe' },        { id = 2,  en = 'storage' },
    { id = 3,  en = 'temp' },        { id = 4,  en = 'locker' },      { id = 5,  en = 'satchel' },
    { id = 6,  en = 'sack' },        { id = 7,  en = 'case' },        { id = 8,  en = 'wardrobe' },
    { id = 9,  en = 'safe2' },       { id = 10, en = 'wardrobe2' },   { id = 11, en = 'wardrobe3' },
    { id = 12, en = 'wardrobe4' },   { id = 13, en = 'wardrobe5' },   { id = 14, en = 'wardrobe6' },
    { id = 15, en = 'wardrobe7' },   { id = 16, en = 'wardrobe8' },   { id = 17, en = 'recycle' },
};

--[[
* Ashita's item type -> Windower's category string.
]]
local function item_category(ritem)
    local slots = ritem.Slots or 0;
    if (bit.band(slots, 0x000F) ~= 0) then
        return 'Weapon';
    elseif (slots ~= 0) then
        return 'Armor';
    end
    return 'Normal';
end

--[[
* Ashita's item flag bitmask -> Windower's flag name list.
]]
local function item_flags(ritem)
    local flags = T{ };
    local f = ritem.Flags or 0;
    if (bit.band(f, 0x0001) ~= 0) then flags:append('NoTrade');   end
    if (bit.band(f, 0x0002) ~= 0) then flags:append('NoDeequip'); end
    if (bit.band(f, 0x0004) ~= 0) then flags:append('Rare');      end
    if (bit.band(f, 0x0008) ~= 0) then flags:append('Ex');        end
    if (bit.band(f, 0x0010) ~= 0) then flags:append('Crystal');   end
    if (bit.band(f, 0x0020) ~= 0) then flags:append('Stackable'); end
    if (bit.band(f, 0x0040) ~= 0) then flags:append('Print');     end
    if (bit.band(f, 0x0080) ~= 0) then flags:append('Linkable');  end
    if (bit.band(f, 0x0100) ~= 0) then flags:append('NoRMT');     end
    if (bit.band(f, 0x0200) ~= 0) then flags:append('Scannable'); end
    if (bit.band(f, 0x0400) ~= 0) then flags:append('NoHQ');      end
    if (bit.band(f, 0x0800) ~= 0) then flags:append('RareEX');    end
    if (bit.band(f, 0x2000) ~= 0) then flags:append('Usable');    end
    if (bit.band(f, 0x4000) ~= 0) then flags:append('NPCOnly');   end
    -- Windower reports everything wearable as equippable.
    if ((ritem.Slots or 0) ~= 0) then flags:append('Equippable'); end
    return flags;
end

--[[
* Ashita's slot bitmask -> Windower's res.items[x].slots (keyed by slot id).
]]
local function item_slots(ritem)
    local ret = T{ };
    for _, s in ipairs(resources.slot_bits) do
        if (bit.band(ritem.Slots or 0, s.bit) ~= 0) then
            ret[s.id] = s.en;
        end
    end
    return ret;
end

--[[
* Ashita's job bitmask -> Windower's res.items[x].jobs (keyed by job id).
]]
local function item_jobs(ritem)
    local ret = T{ };
    local jobs = ritem.Jobs or 0;
    for i = 1, #resources.job_bits do
        if (bit.band(jobs, bit.lshift(1, i - 1)) ~= 0) then
            ret[i] = resources.job_bits[i];
        end
    end
    return ret;
end

--[[
* Ashita's race bitmask -> Windower's res.items[x].races (keyed by race id).
]]
local item_races = { 'Hume Male','Hume Female','Elvaan Male','Elvaan Female','Tarutaru Male',
                     'Tarutaru Female','Galka','Mithra' };

local function item_race_names(ritem)
    local ret = T{ };
    local races = ritem.Races or 0;
    for i = 1, #item_races do
        if (bit.band(races, bit.lshift(1, i - 1)) ~= 0) then
            ret[i] = item_races[i];
        end
    end
    return ret;
end

---------------------------------------------------------------------------
-- Entry builders (cached)
---------------------------------------------------------------------------

local cache = { item = { }, spell = { }, ability = { }, buff = { }, desc = { }, job = { } };

local function get_item(id)
    id = math.floor(tonumber(id) or 0);
    if (id < 1 or id > MAX_ITEM_ID) then return nil end
    local hit = cache.item[id];
    if (hit ~= nil) then return hit == false and nil or hit end

    local ritem = rmgr():GetItemById(id);
    if (ritem == nil or ritem.Id == nil) then
        cache.item[id] = false;
        return nil;
    end

    local name = eng(ritem.Name);
    if (name == nil or name == '') then
        cache.item[id] = false;
        return nil;
    end

    local item = T{ };
    item.id           = ritem.Id;
    item.index        = ritem.Id;
    item.en           = name;
    item.ens          = name;
    item.name         = name;
    item.jp           = jpn(ritem.Name, name);
    -- Ashita's item resource has no SortKey; ResourceId is the closest monotonic ordering value.
    item.sortkey      = ritem.ResourceId;
    item.category     = item_category(ritem);
    item.flags        = item_flags(ritem);
    item.slots        = item_slots(ritem);
    item.jobs         = item_jobs(ritem);
    item.races        = item_race_names(ritem);
    item.delay        = ritem.Delay;
    item.damage       = ritem.Damage;
    item.dps          = ritem.DPS;
    item.skill        = ritem.Skill;
    item.item_level   = ritem.ItemLevel;
    item.level        = ritem.Level;
    item.superior     = ritem.SuperiorLevel;
    item.stack_size   = ritem.StackSize;
    item.storage      = ritem.Storage;
    item.type         = ritem.Type;
    item.shield_size  = ritem.ShieldSize;
    item.element      = ritem.Element;
    item.targets      = ritem.Targets;
    item.base_id      = ritem.BaseItemId;
    item.max_charges  = ritem.MaxCharges;
    item.cast_time    = ritem.CastTime;
    item.recast       = ritem.RecastDelay;
    item.article      = ritem.Article;
    item.description  = eng(ritem.Description);
    item.note         = item.description;

    cache.item[id] = item;
    return item;
end

local function get_spell(id)
    id = math.floor(tonumber(id) or 0);
    if (id < 0 or id > MAX_SPELL_ID) then return nil end
    local hit = cache.spell[id];
    if (hit ~= nil) then return hit == false and nil or hit end

    local rspell = rmgr():GetSpellById(id);
    if (rspell == nil) then
        cache.spell[id] = false;
        return nil;
    end
    local name = eng(rspell.Name);
    if (name == nil or name == '') then
        cache.spell[id] = false;
        return nil;
    end

    local spell = T{ };
    spell.id          = rspell.Id;
    spell.index       = rspell.Index;
    spell.en          = name;
    spell.ens         = name;
    spell.name        = name;
    spell.jp          = jpn(rspell.Name, name);
    spell.skill       = rspell.Skill;
    spell.type        = resources.skill_to_spell_type[rspell.Skill] or 'Other';
    spell.element     = rspell.Element;
    spell.mana_cost   = rspell.ManaCost;
    spell.cast_time   = rspell.CastTime;
    spell.recast      = rspell.RecastDelay;
    spell.targets     = rspell.Targets;
    spell.range       = rspell.Range;
    spell.area_range  = rspell.AreaRange;
    spell.levels      = rspell.LevelRequired;
    spell.description = eng(rspell.Description);

    cache.spell[id] = spell;
    return spell;
end

local function get_ability(id)
    id = math.floor(tonumber(id) or 0);
    if (id < 0 or id > MAX_ABILITY_ID) then return nil end
    local hit = cache.ability[id];
    if (hit ~= nil) then return hit == false and nil or hit end

    local rability = rmgr():GetAbilityById(id);
    if (rability == nil) then
        cache.ability[id] = false;
        return nil;
    end
    local name = eng(rability.Name);
    if (name == nil or name == '') then
        cache.ability[id] = false;
        return nil;
    end

    local ability = T{ };
    ability.id          = rability.Id;
    ability.en          = name;
    ability.ens         = name;
    ability.name        = name;
    ability.jp          = jpn(rability.Name, name);
    ability.type        = rability.Type;
    ability.element     = rability.Element;
    ability.mana_cost   = rability.ManaCost;
    ability.tpid        = rability.TPCost;
    ability.tp_cost     = rability.TPCost;
    ability.recast_timer = rability.RecastTimerId;
    ability.targets     = rability.Targets;
    ability.range       = rability.Range;
    ability.area_range  = rability.AreaRange;
    ability.monster_level = rability.MonsterLevel;
    ability.description = eng(rability.Description);

    cache.ability[id] = ability;
    return ability;
end

local function get_buff(id)
    id = math.floor(tonumber(id) or 0);
    if (id < 1 or id > MAX_BUFF_ID) then return nil end
    local hit = cache.buff[id];
    if (hit ~= nil) then return hit == false and nil or hit end

    local name = rmgr():GetString('buffs.names', id);
    if (name == nil or name == '') then
        cache.buff[id] = false;
        return nil;
    end

    local buff = T{ };
    buff.id      = id;
    buff.index   = id;
    buff.en      = name;
    buff.english = name;
    buff.name    = name;
    buff.log     = rmgr():GetString('buffs.names_log', id) or name;

    local icon = rmgr():GetStatusIconById(id);
    if (icon ~= nil) then
        buff.jp           = jpn(icon.Name, name);
        buff.description  = eng(icon.Description);
        buff.can_cancel   = icon.CanCancel;
        buff.hide_timer   = icon.HideTimer;
    end

    cache.buff[id] = buff;
    return buff;
end

local function get_job(id)
    id = math.floor(tonumber(id) or 0);
    local entry = resources.job_names[id];
    if (entry == nil) then return nil end
    local hit = cache.job[id];
    if (hit ~= nil) then return hit end

    local job = T{ };
    job.id   = id;
    job.en   = entry.en;
    job.ens  = entry.ens;
    job.abbr = entry.ens;
    job.name = entry.en;
    job.jp   = entry.en;

    cache.job[id] = job;
    return job;
end

local function get_slot(id)
    id = math.floor(tonumber(id) or 0);
    for _, s in ipairs(resources.slot_bits) do
        if (s.id == id) then return s end
    end
    return nil;
end

--[[
* Windower's res.skills entries carry both a display name ('Hand-to-Hand') and a space separated
* 'english' field ('Hand to Hand'). GearInfo reads .en for item skills and .english to build the
* player.skills keys, so both are kept and they deliberately differ.
--]]
local function get_skill(id)
    id = math.floor(tonumber(id) or 0);
    local name = resources.skill_names[id];
    if (name == nil) then return nil end
    local english = string.gsub(name, '%-', ' ');
    return T{
        id             = id,
        en             = name,
        name           = name,
        english        = english,
        english_plural = english,
        ens            = string.upper(string.sub(name, 1, 3)),
    };
end

--[[
* Windower keeps descriptions in a separate table; Ashita stores them on the item.
]]
local function get_description(id)
    id = math.floor(tonumber(id) or 0);
    local hit = cache.desc[id];
    if (hit ~= nil) then return hit == false and nil or hit end

    local ritem = rmgr():GetItemById(id);
    local text = ritem and eng(ritem.Description);
    if (text == nil or text == '') then
        cache.desc[id] = false;
        return nil;
    end

    local desc = T{ id = id, en = text };
    cache.desc[id] = desc;
    return desc;
end

---------------------------------------------------------------------------
-- 'with' queries
---------------------------------------------------------------------------

--[[
* Resolves a name to an id using Ashita's Get*ByName(), then builds the entry.
* Windower matches names case-insensitively; do the same with a fallback scan.
]]
local function by_name(builder_get, rget_by_name, value)
    local r = rget_by_name(rmgr(), value, LANG_EN);
    if (r ~= nil) then
        local entry = builder_get(r.Id);
        if (entry ~= nil) then return entry end
    end
    return nil;
end

local function scan_by_field(builder_get, max_id, field, value)
    local want = string.lower(tostring(value));
    for i = 0, max_id do
        local entry = builder_get(i);
        if (entry ~= nil) then
            local v = entry[field];
            if (type(v) == 'string' and string.lower(v) == want) then
                return entry;
            end
        end
    end
    return nil;
end

local function make_query_table(builder_get, rget_by_name, max_id, extra, scan_limit)
    -- A plain table with its own metatable: numeric keys are served lazily by the builder,
    -- everything else is a normal field. Sugar methods are intentionally not needed here.
    local mt = { };
    mt.__index = function (self, key)
        if (type(key) == 'number') then
            return builder_get(key);
        end
        return nil;
    end;
    mt.__newindex = function (self, key, value)
        rawset(self, key, value);
    end;

    local tbl = setmetatable({ }, mt);
    tbl.count = max_id;
    local name_fields = { en = true, english = true, name = true, ens = true };

    function tbl:with(field, value)
        if (field == 'id' or field == 'index') then
            return builder_get(value);
        end

        if (name_fields[field] and rget_by_name ~= nil) then
            local entry = by_name(builder_get, rget_by_name, value);
            if (entry ~= nil) then return entry end
        end

        -- Name fields with no Get*ByName() equivalent, and everything else, need a bounded scan.
        local limit = scan_limit or max_id;
        if (limit <= 0) then return nil end
        return scan_by_field(builder_get, limit, field, value);
    end

    if (extra ~= nil) then
        extra(tbl);
    end
    return tbl;
end

---Items--------------------------------------------------------------------
-- The item range is too large to scan, so only id/name lookups are offered.
resources.items = make_query_table(get_item, function (m, n, l) return m:GetItemByName(n, l); end, MAX_ITEM_ID, nil, 0);

---Spells-------------------------------------------------------------------
resources.spells = make_query_table(get_spell, function (m, n, l) return m:GetSpellByName(n, l); end, MAX_SPELL_ID, function (tbl)
    ---Windower's res.spells:type('BlueMagic') returns the spells of that type keyed by id.
    function tbl:type(name)
        local ret = T{ };
        for i = 0, MAX_SPELL_ID do
            local spell = get_spell(i);
            if (spell ~= nil and spell.type == name) then
                ret[i] = spell;
            end
        end
        return ret;
    end
end);

---Job Abilities------------------------------------------------------------
resources.job_abilities = make_query_table(get_ability, function (m, n, l) return m:GetAbilityByName(n, l); end, MAX_ABILITY_ID);

---Buffs----------------------------------------------------------------------
resources.buffs = make_query_table(get_buff, nil, MAX_BUFF_ID);

---Jobs-----------------------------------------------------------------------
resources.jobs = make_query_table(get_job, nil, 21);

---Slots----------------------------------------------------------------------
resources.slots = make_query_table(get_slot, nil, 15);

---Skills---------------------------------------------------------------------
resources.skills = make_query_table(get_skill, nil, 46);

---Item descriptions----------------------------------------------------------
resources.item_descriptions = make_query_table(get_description, nil, MAX_ITEM_ID);

---Bags-----------------------------------------------------------------------
-- Keyed by container id only: parse_inventory() walks res.bags with pairs() and reads bag.id.
resources.bags = T{ };
for _, bag in ipairs(resources.bag_list) do
    resources.bags[bag.id] = bag;
end

--[[
* Helpers used elsewhere in the port that need a name -> id resolution.
]]
function resources.buff_id_by_name(name)
    local buff = resources.buffs:with('en', name);
    return buff and buff.id or nil;
end

function resources.spell_id_by_name(name)
    local spell = resources.spells:with('en', name);
    return spell and spell.id or nil;
end

return resources;
