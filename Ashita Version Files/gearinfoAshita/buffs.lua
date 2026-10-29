--[[
    Buff effects, driven purely by the player's own buff ids (no caster attribution any more).

    Without the action parser the following are no longer tracked automatically - use the manual commands:
      * Songs (marches etc.)  -> /gi mhaste <n>          (magic haste, /1024 units)
      * Corsair rolls         -> not tracked
      * Geomancy / Indi / Geo -> not tracked
      * Haste Samba           -> /gi samba <off|sub|main>
      * Haste (buff 33)       -> assumed Haste I (150/1024); use /gi mhaste for Haste II (+157) etc.
      * Warcry / Aggressor AGI -> not tracked
]]--

local Ionis_zones = {}
for z = 256, 277 do Ionis_zones[z] = true end
for z = 281, 285 do Ionis_zones[z] = true end

local function new_buffs_table()
    return {
        ['delay']=0, ['damage']=0, ['HP']=0, ['MP']=0,
        ['STR']=0, ['DEX']=0, ['VIT']=0, ['AGI']=0, ['INT']=0, ['MND']=0, ['CHR']=0,
        ['Accuracy']=0, ['Ranged Accuracy']=0, ['Attack']=0, ['Attack perc']=0,
        ['Evasion']=0, ['DEF']=0, ['Defence perc']=0,
        ['Magic Accuracy']=0, ['Magic Atk. Bonus']=0, ['Magic Evasion']=0, ['Magic Def. Bonus']=0,
        ['g_haste']=0, ['ma_haste']=0, ['ja_haste']=0,
        ['PDT']=0, ['MDT']=0, ['BDT']=0, ['DT']=0, ['MDT2']=0, ['PDT2']=0,
        ['Store TP']=0, ['Dual Wield']=0, ['Fast Cast']=0, ['Martial Arts']=0,
        ['Double Attack']=0, ['Triple Attack']=0, ['Quadruple Attack']=0,
        ['Critical hit rate']=0, ['Critical hit damage']=0, ['Subtle Blow']=0,
    }
end

local body_aggressor = { [15087]=1, [14500]=1, [10670]=1, [26800]=1, [26801]=1, [23130]=1, [23465]=1 }
local conqueror = {
    [18991] = { 52, 52 }, [19060] = { 62, 72 }, [19080] = { 72, 93 },
    [19612] = { 82, 113 }, [19710] = { 82, 113 },
    [19819] = { 88, 144 }, [19948] = { 88, 144 }, [20837] = { 88, 144 }, [20838] = { 88, 144 }, [21757] = { 88, 144 },
}

-- effects table for one buff id
local function buff_effects(id)
    local e = {}
    local eq = player.equipment
    local ml, sl = player.main_job_level, player.sub_job_level

    if id == 1 then e.ma_haste = -1024                         -- weakness
    elseif id == 13 then e.ma_haste = -300                     -- slow
    elseif id == 565 then e.ma_haste = -204                    -- indi/geo-slow
    elseif id == 194 then e.ma_haste = -512                    -- elegy
    elseif id == 56 then                                       -- berserk
        e['Defence perc'] = -256
        local atk = 256
        if player.main_job == 'WAR' then
            if ml >= 90 then atk = 356 elseif ml >= 80 then atk = 336 elseif ml >= 70 then atk = 316
            elseif ml >= 60 then atk = 296 elseif ml >= 50 then atk = 276 end
        end
        local c = conqueror[eq.main.id]
        if c then
            atk = atk + c[1]; e['Defence perc'] = e['Defence perc'] - c[1]; e['Critical hit rate'] = c[2]
        end
        e['Attack perc'] = atk
    elseif id == 57 then                                       -- defender
        e['Attack perc'] = -256
        local d = 256
        if player.main_job == 'WAR' then
            if ml >= 90 then d = 356 elseif ml >= 80 then d = 336 elseif ml >= 70 then d = 316
            elseif ml >= 60 then d = 296 elseif ml >= 50 then d = 276 end
        end
        e['Defence perc'] = d
    elseif id == 58 then                                       -- aggressor
        e['Accuracy'] = 25
        e['Evasion'] = -25
        if player.main_job == 'WAR' then
            e['Ranged Accuracy'] = cfg.merits.aggressive_aim * 4
            if body_aggressor[eq.body.id] then e['Evasion'] = -15 end
        end
    elseif id == 460 then e['Critical hit rate'] = 205         -- blood rage
    elseif id == 419 then                                      -- composure
        e['Accuracy'] = math.floor(((24 * ml) + 74) / 49)
    elseif id == 512 and Ionis_zones[player.zone or 0] then    -- ionis
        e.g_haste = 30; e['Accuracy'] = 20; e['Ranged Accuracy'] = 20
    elseif id == 64 then                                       -- last resort
        if player.main_job == 'DRK' and ml == 99 then
            e.ja_haste = math.ceil(((cfg.merits.desperate_blows * 2) + 15) / 100 * 1024)
        elseif player.main_job == 'DRK' and ml > 75 then
            e.ja_haste = math.ceil(((cfg.merits.desperate_blows * 2) + 5) / 100 * 1024)
        elseif player.main_job == 'DRK' or player.sub_job == 'DRK' then
            e.ja_haste = 52
        end
    elseif id == 353 then                                      -- hasso
        e.ja_haste = 103
        e['Accuracy'] = 10
        local lvl = (player.main_job == 'SAM' and ml) or (player.sub_job == 'SAM' and sl) or nil
        if lvl then e['STR'] = math.min(math.floor(lvl / 7), 14) end
        local hands = eq.hands.en:lower()
        local legs  = eq.legs.en:lower()
        local feet  = eq.feet.en:lower()
        local hbonus = { ['wakido kote']=10, ['wakido kote +1']=20, ['wakido kote +2']=30, ['wakido kote +3']=40 }
        local lbonus = { ['unkai haidate +1']=15, ['unkai haidate +2']=25, ['kasuga haidate']=25, ['kasuga haidate +1']=30 }
        local fbonus = { ['wakido sune. +2']=10, ['wakido sune. +3']=20 }
        e.ja_haste = e.ja_haste + (hbonus[hands] or 0) + (lbonus[legs] or 0) + (fbonus[feet] or 0)
    elseif id == 604 then e.ma_haste = 150                     -- mighty guard
    elseif id == 228 then e.ma_haste = 260                     -- embrava
    elseif id == 33 then e.ma_haste = 150                      -- haste (assume Haste I; adjust with /gi mhaste)
    elseif id == 227 then e['Store TP'] = 10                   -- ninja spell (STP)
    end
    return e
end

function calculate_total_haste()
    Buffs_inform = new_buffs_table()

    -- Haste Samba (manual): applies while engaged
    if samba_mode ~= 'off' then
        local status = AshitaCore:GetMemoryManager():GetEntity():GetStatus(player.index)
        if status == 1 then
            Buffs_inform.ja_haste = Buffs_inform.ja_haste + ((samba_mode == 'main') and 101 or 51)
        end
    end

    for _, id in ipairs(player.buffs) do
        for key, value in pairs(buff_effects(id)) do
            if Buffs_inform[key] ~= nil then
                Buffs_inform[key] = Buffs_inform[key] + value
            end
        end
    end
    return Buffs_inform
end
