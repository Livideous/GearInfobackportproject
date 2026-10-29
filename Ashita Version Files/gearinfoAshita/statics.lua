require('common')

-- static data tables (unchanged from the Windower version; Cor_Rolls/Bard_Songs/Geo_Spells are no longer needed)
DW_Gear              = require('res.DW_Gear')
Unity_rank           = require('res.Unity_Gear')
Martial_Arts_Gear    = require('res.Martial_Arts_Gear')
Set_bonus_by_Set_ID  = require('res.Set_bonus_by_Set_ID')
Set_bonus_by_item_id = require('res.Set_bonus_by_item_id')
Blu_spells           = require('res.Blue_Mage_Spells')
Gifts                = require('res.Gifts')

JOBS = { 'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD','RNG','SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN' }

-- FFXI skill id -> windower-style api name (used for the 0x062 skills packet)
SKILL_API = {
    [1]='hand_to_hand', [2]='dagger', [3]='sword', [4]='great_sword', [5]='axe', [6]='great_axe',
    [7]='scythe', [8]='polearm', [9]='katana', [10]='great_katana', [11]='club', [12]='staff',
    [25]='archery', [26]='marksmanship', [27]='throwing', [28]='guard', [29]='evasion',
    [30]='shield', [31]='parrying',
}
-- FFXI weapon skill id -> display name (matches the "<Name> skill" keys parsed from item descriptions)
SKILL_NAME = {
    [1]='Hand-to-Hand', [2]='Dagger', [3]='Sword', [4]='Great Sword', [5]='Axe', [6]='Great Axe',
    [7]='Scythe', [8]='Polearm', [9]='Katana', [10]='Great Katana', [11]='Club', [12]='Staff',
    [25]='Archery', [26]='Marksmanship', [27]='Throwing',
}
function skill_api(name)
    if not name or name == '' then return nil end
    return (name:lower():gsub('[ %-]', '_'))
end

-- Ashita equipment slot index -> name
EQUIP_SLOTS = { [0]='main','sub','range','ammo','head','neck','left_ear','right_ear','body','hands',
                'left_ring','right_ring','back','waist','legs','feet' }

function EMPTY_ITEM()
    return { id = 0, en = '', category = '', delay = 0 }
end

defaults = T{
    player = T{
        show_total_haste = true,
        show_tp_Stuff    = true,
        show_acc_Stuff   = false,
        show_dt_Stuff    = false,
        show_att_Stuff   = false,
        show_Evasion     = false,
        show_Defence     = false,
        show_STP         = false,
        show_DW_Stuff    = false,
        show_MA_Stuff    = false,
        rank             = 1,
        jp_spent         = 0,   -- manual override for job points spent on current main job (0 = try auto)
    },
    -- merits can't be read reliably, so they are manual: /gi merit <name> <n>
    merits = T{
        ikishoten        = 0,
        store_tp_effect  = 0,
        desperate_blows  = 0,
        aggressive_aim   = 0,
    },
    display = T{ pos = T{ x = 100, y = 100 } },
}

-- runtime state
cfg                 = nil
player              = { name='', id=0, index=0, main_job='NON', main_job_level=0, sub_job='NON', sub_job_level=0,
                        stats = { STR=0, DEX=0, VIT=0, AGI=0, INT=0, MND=0, CHR=0 },
                        skills = {}, buffs = {}, equipment = {} }
player_base_skills  = {}
player_was_logged_in = false
item_cache          = {}
Gear_info           = {}
Buffs_inform        = {}
Total_haste         = 0
blocks              = {}

manual_stp, manual_dw, manual_ghaste, manual_mhaste, manual_jahaste, manual_dw_needed = 0, 0, 0, 0, 0, 0
WSTP        = 0
samba_mode  = 'off'      -- 'off' | 'sub' | 'main'  (Haste Samba; was detected from action packets before)
debug_mode  = false

function reset_character_state()
    player.stats  = { STR=0, DEX=0, VIT=0, AGI=0, INT=0, MND=0, CHR=0 }
    player.skills = {}
    player_base_skills = {}
    manual_stp, manual_dw, manual_ghaste, manual_mhaste, manual_jahaste, manual_dw_needed = 0, 0, 0, 0, 0, 0
    WSTP = 0
    item_cache = {}
end

----------------------------------------------------------------------------------------------
-- small helpers
----------------------------------------------------------------------------------------------
function tcount(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

function is_logged_in()
    local party = AshitaCore:GetMemoryManager():GetParty()
    return party ~= nil and party:GetMemberIsActive(0) == 1 and party:GetMemberName(0) ~= ''
end

-- jobs points spent on current main job: manual override first, then try the API (verify the getter name on your build)
function get_jp_spent()
    if cfg.player.jp_spent and cfg.player.jp_spent > 0 then return cfg.player.jp_spent end
    local ok, v = pcall(function()
        return AshitaCore:GetMemoryManager():GetPlayer():GetJobPointsSpent(player.main_job_id)
    end)
    if ok and type(v) == 'number' then return v end
    return 0
end

-- Equipped blue magic spell ids. TODO: not implemented (needs the BLU set-spell data, e.g. packet 0x44 / memory).
-- While this returns {} the BLU trait / stat bonuses are simply 0.
function get_blu_spell_ids()
    return {}
end

function refresh_player()
    local m     = AshitaCore:GetMemoryManager()
    local party = m:GetParty()
    local pl    = m:GetPlayer()

    player.name    = party:GetMemberName(0)
    player.id      = party:GetMemberServerId(0)
    player.index   = party:GetMemberTargetIndex(0)
    player.zone    = party:GetMemberZone(0)

    player.main_job_id     = pl:GetMainJob()
    player.main_job        = JOBS[player.main_job_id] or 'NON'
    player.main_job_level  = pl:GetMainJobLevel()
    player.sub_job         = JOBS[pl:GetSubJob()] or 'NON'
    player.sub_job_level   = pl:GetSubJobLevel()

    local ids = {}
    local buffs = pl:GetBuffs()
    if buffs then
        for _, id in pairs(buffs) do
            if id and id > 0 and id ~= 255 and id ~= 0xFFFF then ids[#ids + 1] = id end
        end
    end
    player.buffs = ids
end

function refresh_all()
    refresh_player()
    local eq   = check_equipped()
    Gear_info  = get_equip_stats(eq)
    Total_haste = 0
    calculate_total_haste()
    Total_haste = get_total_haste()
    build_blocks()
end
