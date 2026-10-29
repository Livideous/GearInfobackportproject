-- TP / haste / DW / MA / job-trait calculations. Tables below preserve the level thresholds of the original.

local function step(level, tiers)
    local v = 0
    for _, t in ipairs(tiers) do if level >= t[1] then v = t[2] end end
    return v
end

local function gift_sum(name)
    local job = Gifts[player.main_job]
    if not job then return 0 end
    local jp, total = get_jp_spent(), 0
    for threshold, effects in pairs(job['Gifts']) do
        if threshold <= jp and effects[name] then total = total + effects[name] end
    end
    return total
end

-- BLU trait lookup: equipped spell points / 8 (+ job point boost) -> trait value
local BLU_VALUES = {
    ['Dual Wield']   = { 0, 10, 15, 25, 30, 35, 40 },
    ['Store TP']     = { 0, 10, 15, 20, 25, 30 },
    ['Accuracy']     = { 0, 10, 22, 35, 48, 60, 73 },
    ['Evasion']      = { 0, 10, 22, 35, 48, 60 },
    ['Attack']       = { 0, 10, 22, 35, 48, 60, 72 },
    ['Defense Bonus']= { 0, 10, 22, 35, 48, 60, 72 },
}
local function blu_value(trait)
    local points = 0
    for _, id in pairs(get_blu_spell_ids()) do
        local s = Blu_spells[id]
        if s and s.trait == trait then points = points + s.points end
    end
    local v = math.floor(points / 8)
    if v > 0 then
        local jp = get_jp_spent()
        v = v + ((jp >= 1200) and 2 or (jp >= 100) and 1 or 0)
    end
    local tbl = BLU_VALUES[trait]
    return tbl[math.min(v + 1, #tbl)] or 0
end

local JOB_TABLES = {
    acc = { gift = 'Physical Accuracy Bonus', blu = 'Accuracy',
        main = { RNG = {{10,10},{30,22},{50,35},{70,48},{86,60},{96,73}},
                 DRG = {{30,10},{60,22},{76,35}}, DNC = {{30,10},{60,22},{76,35}},
                 RUN = {{50,10},{70,22},{90,35}} },
        sub  = { RNG = {{10,10},{30,22}}, DRG = {{30,10}}, DNC = {{30,10}} } },
    eva = { gift = 'Physical Evasion Bonus', blu = 'Evasion',
        main = { THF = {{10,10},{30,22},{50,35},{70,48},{76,60},{88,72}},
                 DNC = {{15,10},{45,22},{75,35},{86,48}},
                 PUP = {{20,10},{40,22},{77,35}} },   -- original left lvl 60-76 at 0 (looked like a bug)
        sub  = { THF = {{10,10},{30,22}}, DNC = {{15,10},{45,22}}, PUP = {{20,10},{40,22}} } },
    att = { gift = 'Physical Attack Bonus', blu = 'Attack',
        main = { DRK = {{10,10},{30,22},{50,35},{70,48},{76,60},{83,72},{91,84},{99,96}},
                 DRG = {{10,10},{91,22}}, WAR = {{30,10},{65,22},{90,35}} },
        sub  = { DRK = {{10,10},{30,22}}, DRG = {{10,10}}, WAR = {{30,10}} } },
    def = { gift = 'Physical Defense Bonus', blu = 'Defense Bonus',
        main = { PLD = {{10,10},{30,22},{50,35},{70,48},{76,60},{91,72}}, WAR = {{10,10},{45,22},{86,35}} },
        sub  = { PLD = {{10,10},{30,22}}, WAR = {{10,10},{45,22}} } },
}

function job_bonus(kind)
    local t = JOB_TABLES[kind]
    local sub, main = 0, 0
    if t.sub[player.sub_job] then sub = step(player.sub_job_level, t.sub[player.sub_job]) end
    if player.main_job == 'BLU' then
        main = blu_value(t.blu)
    elseif t.main[player.main_job] then
        main = step(player.main_job_level, t.main[player.main_job])
    end
    return math.max(sub, main) + gift_sum(t.gift)
end

----------------------------------------------------------------------------------------------
function determine_stp()
    local sub, main = 0, 0
    if player.sub_job == 'SAM' then sub = step(player.sub_job_level, {{10,10},{30,15}}) end
    if player.main_job == 'BLU' then
        main = blu_value('Store TP')
    elseif player.main_job == 'SAM' then
        main = step(player.main_job_level, {{10,10},{30,15},{50,20},{70,25},{90,30}})
    end
    return math.max(sub, main)
end

function determine_DW()
    local sub = 0
    if player.sub_job == 'DNC' then sub = 15 elseif player.sub_job == 'NIN' then sub = 25 end

    local main = 0
    if player.main_job == 'BLU' then
        main = blu_value('Dual Wield')
    elseif player.main_job == 'NIN' then
        main = step(player.main_job_level, {{10,10},{25,15},{45,25},{65,30},{85,35}})
    elseif player.main_job == 'DNC' then
        main = step(player.main_job_level, {{20,10},{40,15},{60,25},{80,30}})
    elseif player.main_job == 'THF' then
        main = step(player.main_job_level, {{83,10},{90,15},{98,25}})
    end
    main = main + gift_sum('Dual Wield Effect')
    return math.max(sub, main)
end

function determine_Weapon_Delay()
    local eq = player.equipment
    local wd = { melee_delay = 480, gear_MA = 0, job_MA = 0, sub = false, ranged_delay = 0 }
    local main = eq.main

    if main.skill == 'Hand-to-Hand' or main.en == '' then
        local mainj, subj = 480, 480
        if player.main_job == 'MNK' then
            mainj = step(player.main_job_level, {{1,400},{2,380},{31,360},{46,340},{61,320},{75,300},{82,280}})
            if mainj == 0 then mainj = 480 end
        elseif player.main_job == 'PUP' then
            local v = step(player.main_job_level, {{25,400},{50,380},{75,360},{87,340},{97,320}})
            if v > 0 then mainj = v end
        end
        if player.sub_job == 'MNK' then
            local v = step(player.sub_job_level, {{1,400},{2,380},{31,360},{46,340}})
            if v > 0 then subj = v end
        elseif player.sub_job == 'PUP' and player.sub_job_level > 24 then
            subj = 400
        end
        mainj = mainj - gift_sum('Martial Arts Effect')

        local base = math.min(mainj, subj)
        wd.job_MA = 480 - base

        for _, item in pairs(eq) do
            if item.id == 13660 and player.sub_job == 'MNK' then base = base - 10 end
            local ma = Martial_Arts_Gear[item.id]
            if ma then base = base - ma.delay; wd.gear_MA = wd.gear_MA + ma.delay end
        end

        local total = base + (main.delay or 0)
        wd.melee_delay = (total <= 96) and 96 or total
    else
        wd.melee_delay = main.delay or 0
    end

    if eq.sub.category == 'Weapon' and (eq.sub.damage or 0) > 0 then
        wd.melee_delay = wd.melee_delay + (eq.sub.delay or 0)
        wd.sub = true
    end
    if (eq.range.damage or 0) > 0 then wd.ranged_delay = wd.ranged_delay + (eq.range.delay or 0) end
    if (eq.ammo.damage or 0) > 0  then wd.ranged_delay = wd.ranged_delay + (eq.ammo.delay or 0) end
    return wd
end

function determine_Base_tp_hit()
    local weapons = determine_Weapon_Delay()
    local total_dw = Gear_info['Dual Wield'] + determine_DW()

    local delay = { melee = weapons.melee_delay, range = weapons.ranged_delay }
    if weapons.sub then
        delay.melee = math.floor((weapons.melee_delay * (1 - (total_dw / 100))) / 2)
    end

    local tp = { melee = 0, range = 0 }
    for k, d in pairs(delay) do
        local v = 0
        if d > 0 and d < 181 then v = 61 + ((d - 180) * 63 / 360)
        elseif d > 180 and d < 541 then v = 61 + ((d - 180) * 88 / 360)
        elseif d > 540 and d < 631 then v = 149 + ((d - 540) * 20 / 360)
        elseif d > 630 and d < 721 then v = 154 + ((d - 630) * 28 / 360)
        elseif d > 720 and d < 901 then v = 161 + ((d - 720) * 24 / 360)
        elseif d > 900 then v = 173 + ((d - 900) * 28 / 360) end
        tp[k] = math.floor(v)
    end
    return tp
end

function get_tp_per_hit()
    local tp       = determine_Base_tp_hit()
    local job_stp  = determine_stp()
    local buff     = Buffs_inform['Store TP']
    local jp_bonus = gift_sum('Store TP Effect')
    local gear     = Gear_info['Store TP']
    local zanshin  = 0
    local merit_stp = 0

    if player.main_job == 'SAM' then
        merit_stp = cfg.merits.store_tp_effect * 2
        local z = tp.melee + (3 * cfg.merits.ikishoten)
        zanshin = math.floor(z * (100 + gear + job_stp + merit_stp + jp_bonus + buff) / 100)
    end

    local mult = (100 + gear + merit_stp + jp_bonus + job_stp + buff) / 100
    return {
        tp_per_hit_melee   = math.floor(tp.melee * mult),
        tp_per_hit_zanshin = zanshin,
        tp_per_hit_range   = math.floor(tp.range * mult),
    }
end

function get_total_haste()
    local gear  = math.min(Gear_info['Haste'] + Buffs_inform['g_haste'] + manual_ghaste, 256)
    local magic = math.min(Buffs_inform['ma_haste'] + manual_mhaste, 448)
    local ja    = math.min(Buffs_inform['ja_haste'] + manual_jahaste, 256)
    return gear + magic + ja
end

function dual_wield_needed()
    local wd = determine_Weapon_Delay()
    local haste = math.min(get_total_haste(), 819)
    if (player.equipment.main.delay or 0) > 0 and wd.sub then
        return math.ceil((1 - (0.2 / ((1024 - haste) / 1024))) * 100 - determine_DW())
    end
    return 0
end

function martial_arts_needed()
    local wd = determine_Weapon_Delay()
    local haste = math.min(get_total_haste(), 819)
    local total_ma = (wd.job_MA or 0) + (wd.gear_MA or 0)
    local needed = 0
    local main = player.equipment.main
    if main.skill == 'Hand-to-Hand' or main.en == '' then
        local delay = 480 + (main.delay or 0)
        needed = math.ceil(delay - ((delay * 20) / (((1024 - haste) / 1024 * 100)))) - total_ma
    end
    return wd.gear_MA or 0, needed
end
