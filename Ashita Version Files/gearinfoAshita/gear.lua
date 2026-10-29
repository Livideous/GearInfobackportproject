--[[
    Gear processing. Items are read straight from Ashita's resource manager:
      item.Name[1] / item.Description[1] (English), item.Type, item.Delay, item.Damage, item.Skill, item.Slots
    Stats are parsed out of the description text exactly like the Windower version did.
    No augment decoding (extdata) - augment stats are NOT included.
    (Field names/indices below are the ones I expect on Ashita v4; if something is nil, check them first.)
]]--

local bit = require('bit')

local function cut(s, marker)
    local a = s:find(marker, 1, true)
    if a then return s:sub(1, a - 1) end
    return s
end

local pre_replace = {
    { 'Ranged Accuracy%s?', 'Ranged_accuracy' }, { 'Rng.%s?Acc.%s?', 'Ranged_accuracy' },
    { 'Ranged Attack%s?', 'Ranged_attack' },     { 'Rng.%s?Atk.%s?', 'Ranged_attack' },
    { 'Magic Accuracy%s?', 'Magic_accuracy' },   { 'Mag.%s?Acc.%s?', 'Magic_accuracy' },
    { 'Magic Acc.%s?', 'Magic_accuracy' },
    { '"Magic Atk. Bonus"', 'Magic Atk. Bonus' }, { '"Mag.%s?Atk.%s?Bns."', 'Magic Atk. Bonus' },
    { 'Magic Evasion', 'Magic_evasion' },        { '"Magic Def. Bonus"', 'Magic Def. Bonus' },
    { 'Crit. hit damage', 'Critical hit damage' }, { 'Crit. hit rate', 'Critical hit rate' },
    { 'Physical damage taken II', 'PDT_2' }, { 'Physical damage taken', 'PDT' },
    { 'Breath damage taken', 'BDT' },        { 'Breath dmg. taken', 'BDT' },
    { 'Magic damage taken II', 'MDT_2' },    { 'Magic damage taken', 'MDT' },
    { 'Phys. dmg. taken', 'PDT' },           { 'Magic dmg. taken', 'MDT' },
    { 'Damage taken', 'D_T' },
    { 'Weapon skill DEX', 'WS_dex' },
    { 'Great Axe skill', 'Great axe skill' }, { 'Great Katana skill', 'Great katana skill' },
    { 'Great Sword skill', 'Great sword skill' },
}

local valid_strings = {
    'Delay','DEF','HP','MP','STR','DEX','VIT','AGI','INT','MND','CHR',
    'Accuracy','Acc.','Attack','Atk.',
    'Ranged_accuracy','Ranged_attack','Magic_accuracy','Magic Atk. Bonus',
    'Haste','"Slow"','"Store TP"','"Dual Wield"','"Fast Cast"','"Martial Arts"',
    'DMG','PDT','MDT','BDT','D_T','MDT_2','PDT_2',
    'Evasion','Critical hit damage','Critical hit rate',
    'Hand%-to%-Hand skill','Dagger skill','Sword skill','Great sword skill','Axe skill','Great axe skill',
    'Scythe skill','Polearm skill','Katana skill','Great katana skill','Club skill','Staff skill',
    'Archery skill','Marksmanship skill','Throwing skill','Guarding skill','Evasion skill','Shield skill','Parrying skill',
    'Divine Magic skill','Healing Magic skill','Enhancing Magic skill','Enfeebling Magic skill',
    'Elemental Magic skill','Dark Magic skill','Summoning Magic skill','Ninjutsu skill','Singing skill',
    'Stringed Instrument skill','Wind Instrument skill','Blue Magic skill','Geomancy skill','Handbell skill',
    'Phalanx','All magic skills','All skills','Combat skills','Magic skills',
}

local temp_key = {
    ['Delay'] = 'delay', ['Acc.'] = 'Accuracy', ['Atk.'] = 'Attack',
    ['"Slow"'] = 'Slow', ['"Store TP"'] = 'Store TP', ['"Dual Wield"'] = 'Dual Wield', ['"Fast Cast"'] = 'Fast Cast',
    ['Magic_accuracy'] = 'Magic Accuracy', ['Ranged_accuracy'] = 'Ranged Accuracy', ['Ranged_attack'] = 'Ranged Attack',
    ['Magic_evasion'] = 'Magic Evasion',
    ['Great axe skill'] = 'Great Axe skill', ['Great katana skill'] = 'Great Katana skill', ['Great sword skill'] = 'Great Sword skill',
    ['DMG'] = 'damage', ['D_T'] = 'DT', ['MDT_2'] = 'MDT2', ['PDT_2'] = 'PDT2',
    ['"Martial Arts"'] = 'Martial Arts', ['WS_dex'] = 'Weapon skill DEX',
}

function desypher_description(desc)
    desc = desc:gsub('[\r\n]+', ' ')
    for _, r in ipairs(pre_replace) do desc = desc:gsub(r[1], r[2]) end

    for _, marker in ipairs({ 'Pet:', 'Wyvern:', 'Avatar:', 'Luopan:', 'Latent effect:', 'Unity Ranking:' }) do
        if desc:find(marker, 1, true) then desc = cut(desc, marker) break end
    end

    local out = {}
    for _, v in ipairs(valid_strings) do
        local pattern = '(' .. v .. '):?%s?([+-]?%d+)'
        for key, val in desc:gmatch(pattern) do
            out[temp_key[key] or key] = tonumber(val)
        end
    end
    return out
end

----------------------------------------------------------------------------------------------
-- Build (and cache) the stat table for an item id
----------------------------------------------------------------------------------------------
function get_item_stats(id)
    if item_cache[id] then return item_cache[id] end

    local it = AshitaCore:GetResourceManager():GetItemById(id)
    if it == nil or it.Slots == 0 then               -- not equippable
        item_cache[id] = EMPTY_ITEM()
        item_cache[id].id = id
        return item_cache[id]
    end

    local name = (it.Name and it.Name[1]) or ''
    local desc = (it.Description and it.Description[1]) or ''
    local item = { id = id, en = name, category = (it.Type == 4) and 'Weapon' or 'Armor', delay = 0 }

    for k, v in pairs(desypher_description(desc)) do item[k] = v end

    if item.category == 'Weapon' then
        item.delay  = it.Delay  or item.delay or 0
        item.damage = it.Damage or item.damage
        item.skill  = SKILL_NAME[it.Skill]
    end

    -- "Enhances Dual Wield" gear (value isn't in the description)
    if DW_Gear[id] then
        item['Dual Wield'] = (item['Dual Wield'] or 0) + DW_Gear[id]['Dual Wield']
    end

    -- Unity Ranking gear
    local u = Unity_rank[id]
    if u then
        local value = math.floor(((u.rank.max - u.rank.min) / 11) * (11 - (cfg.player.rank - 1))) + u.rank.min
        item[u['Unity Ranking']] = (item[u['Unity Ranking']] or 0) + value
    end

    -- set bonuses
    local sb = Set_bonus_by_item_id[id]
    if sb then item['Set Bonus'] = { ['set id'] = sb['set id'], bonus = sb.bonus } end

    item_cache[id] = item
    return item
end

----------------------------------------------------------------------------------------------
-- Currently equipped gear
----------------------------------------------------------------------------------------------
function check_equipped()
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local eq  = {}

    for slot = 0, 15 do
        local name = EQUIP_SLOTS[slot]
        local item = nil
        local e = inv:GetEquippedItem(slot)
        if e ~= nil and e.Index ~= 0 then
            local container = bit.rshift(bit.band(e.Index, 0xFF00), 8)
            local index     = bit.band(e.Index, 0x00FF)
            local ci = inv:GetContainerItem(container, index)
            if ci ~= nil and ci.Id ~= 0 and ci.Id ~= 65535 then
                item = get_item_stats(ci.Id)
            end
        end
        eq[name] = item or EMPTY_ITEM()
    end

    player.equipment = eq
    return eq
end

----------------------------------------------------------------------------------------------
-- Sum up equipment stats
----------------------------------------------------------------------------------------------
local melee_skills  = { ['Hand-to-Hand skill']=1, ['Dagger skill']=1, ['Sword skill']=1, ['Great Sword skill']=1, ['Axe skill']=1,
                        ['Great Axe skill']=1, ['Scythe skill']=1, ['Polearm skill']=1, ['Katana skill']=1,
                        ['Great Katana skill']=1, ['Club skill']=1, ['Staff skill']=1 }
local ranged_skills = { ['Archery skill']=1, ['Marksmanship skill']=1, ['Throwing skill']=1 }

local function add_stat(st, key, value)
    if key == 'Haste' then
        st['Haste'] = st['Haste'] + math.floor(value / 100 * 1024)
    elseif key == 'Slow' then
        st['Haste'] = st['Haste'] - math.floor(value / 100 * 1024)
    elseif key == 'Combat skills' then
        for _, s in ipairs({ 'main', 'sub', 'range', 'ammo' }) do st[s].value = st[s].value + value end
    else
        st[key] = st[key] + value
    end
end

function get_equip_stats(equipment)
    local st = {
        ['Haste']=0, ['Slow']=0, ['Dual Wield']=0, ['Store TP']=0, ['Accuracy']=0, ['Attack']=0,
        ['Ranged Accuracy']=0, ['Ranged Attack']=0, ['Evasion']=0,
        ['DT']=0, ['PDT']=0, ['PDT2']=0, ['MDT']=0, ['MDT2']=0, ['BDT']=0, ['DEF']=0,
        ['MND']=0, ['AGI']=0, ['DEX']=0, ['VIT']=0, ['STR']=0, ['INT']=0, ['CHR']=0,
        ['Hand-to-Hand skill']=0, ['Dagger skill']=0, ['Sword skill']=0, ['Great Sword skill']=0, ['Axe skill']=0,
        ['Great Axe skill']=0, ['Scythe skill']=0, ['Polearm skill']=0, ['Katana skill']=0, ['Great Katana skill']=0,
        ['Club skill']=0, ['Staff skill']=0, ['Archery skill']=0, ['Marksmanship skill']=0, ['Throwing skill']=0,
        ['Combat skills']=0, ['Evasion skill']=0,
        main = { skill = '', value = 0 }, sub = { skill = '', value = 0 },
        range = { skill = '', value = 0 }, ammo = { skill = '', value = 0 },
    }

    local set_bonus = {}

    for slot, item in pairs(equipment) do
        if slot == 'main' and item.en == '' then st.main.skill = 'Hand-to-Hand' end

        if item.category == 'Weapon' and item.skill and st[slot] and type(st[slot]) == 'table' then
            st[slot].skill = item.skill
            st[slot].value = item[item.skill .. ' skill'] or 0
        end

        for key, value in pairs(item) do
            if type(value) == 'number' and st[key] ~= nil and type(st[key]) == 'number' then
                if item.category == 'Weapon' then
                    if not melee_skills[key] and not ranged_skills[key] then
                        add_stat(st, key, value)
                    end
                else
                    add_stat(st, key, value)
                end
            end
            if key == 'Set Bonus' then
                local ids = value['set id']
                if type(ids) ~= 'table' then ids = { ids } end
                for _, sid in pairs(ids) do set_bonus[sid] = (set_bonus[sid] or 0) + 1 end
            end
        end
    end

    for sid, count in pairs(set_bonus) do
        local def = Set_bonus_by_Set_ID[sid]
        if def and count > 1 and count >= def['minimum peices'] and def.bonus[count] then
            for key, value in pairs(def.bonus[count]) do
                if st[key] ~= nil and type(st[key]) == 'number' then st[key] = st[key] + value end
            end
        end
    end

    st['Dual Wield'] = st['Dual Wield'] + manual_dw
    st['Store TP']   = st['Store TP']   + manual_stp

    return finalize_stats(st)
end

-- adds base skills, base stats and BLU spell stats once (previously done as a side effect inside get_player_acc)
function finalize_stats(st)
    for _, slot in ipairs({ 'main', 'sub', 'range', 'ammo' }) do
        local api = skill_api(st[slot].skill)
        if api and player_base_skills[api] then
            st[slot].value = st[slot].value + player_base_skills[api] + (st[st[slot].skill .. ' skill'] or 0)
        end
    end

    if player_base_skills['evasion'] then
        st['Evasion skill'] = st['Evasion skill'] + player_base_skills['evasion']
    end

    for stat, value in pairs(player.stats) do
        if st[stat] then st[stat] = st[stat] + value end
    end

    for _, id in pairs(get_blu_spell_ids()) do
        local spell = Blu_spells[id]
        if spell then
            for stat, value in pairs(spell) do
                if type(value) == 'number' and type(st[stat]) == 'number' and stat ~= 'id' then
                    st[stat] = st[stat] + value
                end
            end
        end
    end
    return st
end

-- base skills = skills packet value minus what equipped gear gives (packet includes gear)
function compute_base_skills()
    local base = {}
    for k, v in pairs(player.skills) do base[k] = v end

    for _, item in pairs(player.equipment) do
        for key, value in pairs(item) do
            if type(value) == 'number' then
                if key == 'Combat skills' then
                    for _, api in pairs(SKILL_API) do
                        if base[api] and api ~= 'evasion' then base[api] = base[api] - value end
                    end
                elseif key:sub(-6) == ' skill' then
                    local api = skill_api(key:sub(1, -7))
                    if api == 'guarding' then api = 'guard' end
                    if api and base[api] then base[api] = base[api] - value end
                end
            end
        end
    end
    player_base_skills = base
end

----------------------------------------------------------------------------------------------
-- skill -> accuracy/evasion curves
----------------------------------------------------------------------------------------------
function skill_curve(skill)
    if skill < 200 then return skill end
    if skill < 400 then return math.floor((skill - 200) * 0.9) + 200 end
    if skill < 600 then return math.floor((skill - 400) * 0.8) + 380 end
    return math.floor((skill - 600) * 0.9) + 540
end
acc_from_skill  = skill_curve
racc_from_skill = skill_curve
eva_from_skill  = skill_curve

function get_player_acc(st)
    local total = { main = 0, sub = 0, range = 0, ammo = 0 }
    local eq    = player.equipment
    local jobacc = job_bonus('acc')
    local dex   = math.floor((st['DEX'] + Buffs_inform['DEX']) * 0.75)
    local agi   = math.floor((st['AGI'] + Buffs_inform['AGI']) * 0.75)

    total.main = acc_from_skill(st.main.value) + dex + st['Accuracy'] + jobacc + Buffs_inform['Accuracy']

    if eq.sub.category == 'Weapon' and (eq.sub.damage or 0) > 0 then
        total.sub = acc_from_skill(st.sub.value) + dex + st['Accuracy'] + jobacc + Buffs_inform['Accuracy']
    end
    if eq.range.category == 'Weapon' and (eq.range.damage or 0) > 0 then
        total.range = racc_from_skill(st.range.value) + agi + st['Ranged Accuracy'] + jobacc + Buffs_inform['Ranged Accuracy']
    end
    if eq.ammo.category == 'Weapon' and (eq.ammo.damage or 0) > 0 then
        total.ammo = racc_from_skill(st.ammo.value) + agi + st['Ranged Accuracy'] + jobacc + Buffs_inform['Ranged Accuracy']
    end
    return total
end

local two_handers = { ['Great Sword']=1, ['Great Axe']=1, ['Scythe']=1, ['Polearm']=1, ['Great Katana']=1, ['Staff']=1 }

function get_smite()
    local function tiers(level, t) local v = 0 for _, x in ipairs(t) do if level >= x[1] then v = x[2] end end return v end
    local sub, main = 0, 0
    local sj, sl = player.sub_job, player.sub_job_level
    if sj == 'DRK' then sub = tiers(sl, { {15,0.097}, {35,0.15} })
    elseif sj == 'WAR' then sub = tiers(sl, { {35,0.097} })
    elseif sj == 'MNK' or sj == 'DRG' then sub = tiers(sl, { {40,0.097} }) end

    local mj, ml = player.main_job, player.main_job_level
    if mj == 'DRK' then main = tiers(ml, { {15,0.097}, {35,0.15}, {55,0.199}, {75,0.25}, {95,0.296} })
    elseif mj == 'WAR' then main = tiers(ml, { {35,0.097}, {65,0.15}, {95,0.199} })
    elseif mj == 'MNK' or mj == 'DRG' then main = tiers(ml, { {40,0.097}, {80,0.15} })
    elseif mj == 'PUP' then main = tiers(ml, { {60,0.097} }) end
    return math.max(sub, main)
end

function get_player_att(st)
    local total = { main = 0, sub = 0, range = 0, ammo = 0 }
    local eq    = player.equipment
    local jobatt = job_bonus('att')
    local multi  = Buffs_inform['Attack perc'] / 1024
    local str    = st['STR'] + Buffs_inform['STR']

    local base = 8 + st.main.value + str + st['Attack'] + jobatt + Buffs_inform['Attack']
    if two_handers[st.main.skill] then
        total.main = math.floor(base * (1 + get_smite() + multi))
    elseif st.main.skill == 'Hand-to-Hand' then
        total.main = math.floor(base * (1 + get_smite() + multi)) + Buffs_inform['Attack']
    else
        total.main = math.floor(base * (1 + multi))
    end

    if eq.sub.category == 'Weapon' and (eq.sub.damage or 0) > 0 then
        local b = 8 + st.sub.value + math.floor(str / 2) + st['Attack'] + jobatt + Buffs_inform['Attack']
        total.sub = math.floor(b * (1 + multi))
    end
    if eq.range.category == 'Weapon' and (eq.range.damage or 0) > 0 then
        local b = 8 + st.range.value + st['STR'] + st['Ranged Attack'] + jobatt + Buffs_inform['Attack']
        total.range = math.floor(b * (1 + multi))
    end
    if eq.range.id == 0 and eq.ammo.category == 'Weapon' and (eq.ammo.damage or 0) > 0 then
        local b = 8 + st.ammo.value + st['STR'] + st['Ranged Attack'] + jobatt + Buffs_inform['Attack']
        total.ammo = math.floor(b * (1 + multi))
    end
    return total
end

function get_player_evasion(st)
    return math.floor(st['AGI'] / 2) + eva_from_skill(st['Evasion skill']) + job_bonus('eva') + st['Evasion']
end

function get_player_defence(st)
    local lvl = player.main_job_level
    local vit = math.floor(3 * (st['VIT'] + Buffs_inform['VIT']) / 2)
    local d
    if lvl < 51 then d = vit + lvl + 8
    elseif lvl < 61 then d = vit + (2 * lvl) - 42
    elseif lvl < 90 then d = vit + lvl + 18
    else d = vit + lvl + 18 + math.floor((lvl - 89) / 2) end
    d = d + st['DEF'] + job_bonus('def') + Buffs_inform['DEF']
    return math.floor(d * (1 + Buffs_inform['Defence perc'] / 1024))
end
