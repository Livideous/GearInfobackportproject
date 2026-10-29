--[[
    UI + command handling.
    Replaces windower.prim / windower.text (ImageBlock class, mouse drag handler, centre_all_text) with a
    single borderless ImGui window. ImGui handles dragging; the window position is saved to settings.
    PNG theme textures are NOT used: blocks are filled rectangles in the same colour names.
    (ImGui binding return shapes differ slightly between builds, hence the small xy()/text_width() helpers.)
]]--

local imgui = require('imgui')

local CELL_W, CELL_H, COLS = 57, 42, 4

local COLORS = {
    red = {0.55,0.10,0.10}, blue = {0.12,0.25,0.60}, green = {0.10,0.45,0.15}, ['dark-blue'] = {0.05,0.10,0.35},
    grey = {0.30,0.30,0.30}, ['light-green'] = {0.35,0.65,0.30}, orange = {0.75,0.40,0.08}, pink = {0.70,0.30,0.55},
    purple = {0.40,0.18,0.55}, yellow = {0.65,0.55,0.10},
}

local function xy(a, b)
    if type(a) == 'table' then return a[1] or a.x, a[2] or a.y end
    return a, b
end

local function text_width(s)
    local w = imgui.CalcTextSize(s)
    if type(w) == 'table' then return w[1] or w.x end
    return w
end

local last_pos = { x = nil, y = nil }
function ui_reset() last_pos = { x = nil, y = nil } end

----------------------------------------------------------------------------------------------
-- block list (replaces the big update() function)
----------------------------------------------------------------------------------------------
local function add(label, value, color, red)
    blocks[#blocks + 1] = { label = label, value = tostring(value), color = color, red = red or false }
end
local function nz(v) if v == 0 then return 0 end return v end

function build_blocks()
    blocks = {}
    local p, g, b = cfg.player, Gear_info, Buffs_inform

    if p.show_total_haste then
        local gear = g['Haste'] + b['g_haste']
        add('Gear.H',  gear, 'red', gear > 256)
        add('Magic.H', b['ma_haste'] + manual_mhaste, 'red', (b['ma_haste'] + manual_mhaste) > 448)
        add('JA.H',    b['ja_haste'] + manual_jahaste, 'red', (b['ja_haste'] + manual_jahaste) > 256)
        add('Total.H', Total_haste, 'red', Total_haste > 820)
    end

    if p.show_dt_Stuff then
        add('DT', nz(-g['DT']), 'purple', g['DT'] < -51)

        local pdt, pcap = g['PDT'] + g['DT'], -51
        if g['PDT2'] < 0 then pdt = pdt + g['PDT2']; pcap = math.max(-50 + g['PDT2'], -87.6) end
        add('PDT', nz(-pdt), 'purple', pdt < pcap)

        local mdt, mcap = g['MDT'] + g['DT'], -51
        if g['MDT2'] < 0 then mdt = mdt + g['MDT2']; mcap = math.max(-50 + g['MDT2'], -87.6) end
        add('MDT', nz(-mdt), 'purple', mdt < mcap)

        local bdt = g['BDT'] + g['DT']
        add('BDT', nz(-bdt), 'purple', bdt < -51)
    end

    if p.show_tp_Stuff then
        local tp = get_tp_per_hit()
        local function wsline(tph, prefix, color)
            if tph <= 0 then return end
            if WSTP > 0 then
                add(prefix .. 'for WS', WSTP, color)
                add(prefix .. 'aft WS', math.ceil((10000 - (WSTP * 10)) / tph) / 10, color)
            else
                add(prefix .. 'TP/h', tph, color)
                add(prefix .. 'to WS', math.ceil(10000 / tph) / 10, color)
            end
        end
        wsline(tp.tp_per_hit_melee, '', 'yellow')
        wsline(tp.tp_per_hit_range, 'R.', 'green')
    end

    if p.show_acc_Stuff then
        local a = get_player_acc(g)
        if a.sub > 0 then add('Acc.1', a.main, 'yellow'); add('Acc.2', a.sub, 'yellow')
        else add('Acc.', a.main, 'yellow') end
        if a.range > 0 then add('R.Acc.', a.range, 'green')
        elseif a.ammo > 0 then add('R.Acc.', a.ammo, 'green') end
    end

    if p.show_att_Stuff then
        local a = get_player_att(g)
        if a.sub > 0 then add('Att.1', a.main, 'yellow'); add('Att.2', a.sub, 'yellow')
        else add('Att.', a.main, 'yellow') end
        if a.range > 0 then add('R.Att.', a.range, 'green')
        elseif a.ammo > 0 then add('R.Att.', a.ammo, 'green') end
    end

    if p.show_Evasion then add('Eva.', get_player_evasion(g), 'yellow') end
    if p.show_Defence then add('Def.', get_player_defence(g), 'yellow') end

    if p.show_DW_Stuff then
        local sub = player.equipment.sub
        if sub.category == 'Weapon' and (sub.damage or 0) > 0 then
            local need = dual_wield_needed() + manual_dw_needed
            add('DW', g['Dual Wield'], 'blue')
            add('Needed', need, 'blue', need < 0)
        end
    end

    if p.show_MA_Stuff then
        local main = player.equipment.main
        if main.skill == 'Hand-to-Hand' or main.en == '' then
            local total, needed = martial_arts_needed()
            add('MA', total, 'pink')
            add('Needed', needed, 'pink', needed < 0)
        end
    end

    if p.show_STP then
        add('STP', g['Store TP'] + Buffs_inform['Store TP'], 'orange')
    end
end

----------------------------------------------------------------------------------------------
-- rendering (called every frame from d3d_present)
----------------------------------------------------------------------------------------------
function ui_render()
    if #blocks == 0 then return end

    imgui.SetNextWindowPos({ cfg.display.pos.x, cfg.display.pos.y }, ImGuiCond_FirstUseEver)
    local flags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_NoBackground,
                          ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoFocusOnAppearing,
                          ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoSavedSettings)

    if imgui.Begin('GearInfo##gi_window', true, flags) then
        local rows = math.ceil(#blocks / COLS)
        local ox, oy = xy(imgui.GetCursorScreenPos())
        local dl = imgui.GetWindowDrawList()

        local black = imgui.GetColorU32({ 0, 0, 0, 0.85 })
        dl:AddRectFilled({ ox, oy }, { ox + CELL_W * COLS, oy + CELL_H * rows }, black)

        local label_col = imgui.GetColorU32({ 150/255, 150/255, 235/255, 1 })
        local white     = imgui.GetColorU32({ 1, 1, 1, 1 })
        local redc      = imgui.GetColorU32({ 1, 0, 0, 1 })

        for i, blk in ipairs(blocks) do
            local col = (i - 1) % COLS
            local row = math.floor((i - 1) / COLS)
            local x, y = ox + col * CELL_W, oy + row * CELL_H
            local c = COLORS[blk.color] or COLORS.grey
            dl:AddRectFilled({ x + 1, y + 1 }, { x + CELL_W - 1, y + CELL_H - 1 }, imgui.GetColorU32({ c[1], c[2], c[3], 0.9 }))

            local lw = text_width(blk.label)
            local vw = text_width(blk.value)
            dl:AddText({ x + (CELL_W - lw) / 2, y + 4  }, label_col, blk.label)
            dl:AddText({ x + (CELL_W - vw) / 2, y + 22 }, blk.red and redc or white, blk.value)
        end

        imgui.Dummy({ CELL_W * COLS, CELL_H * rows })

        -- save position once dragging stops
        local wx, wy = xy(imgui.GetWindowPos())
        if wx ~= last_pos.x or wy ~= last_pos.y then
            last_pos.x, last_pos.y = wx, wy
        elseif not imgui.IsMouseDown(0) and (cfg.display.pos.x ~= wx or cfg.display.pos.y ~= wy) then
            cfg.display.pos.x, cfg.display.pos.y = wx, wy
            settings_lib.save()
        end
    end
    imgui.End()
end

----------------------------------------------------------------------------------------------
-- commands
----------------------------------------------------------------------------------------------
local show_keys = {
    haste = 'show_total_haste', tp = 'show_tp_Stuff', acc = 'show_acc_Stuff', eva = 'show_Evasion',
    def = 'show_Defence', att = 'show_att_Stuff', stp = 'show_STP', dw = 'show_DW_Stuff',
    ma = 'show_MA_Stuff', dt = 'show_dt_Stuff',
}

local function help()
    chat_print('GearInfo commands (/gi or /gearinfo):')
    chat_print('rank [n]            unity rank (1-11); clears the item cache')
    chat_print('stp|dw|ghaste|mhaste|jahaste|dwn <n>   manual adjustments')
    chat_print('save wstp / delete wstp               store / clear TP-after-WS')
    chat_print('samba <off|sub|main>                  Haste Samba (manual; applied while engaged)')
    chat_print('jp <n>                                job points spent on main job (0 = auto)')
    chat_print('merit <ikishoten|store_tp_effect|desperate_blows|aggressive_aim> <n>')
    chat_print('show <haste|tp|acc|eva|def|att|stp|dw|ma|dt|all>   toggle blocks')
    chat_print('hide                                  hide all blocks')
    chat_print('debug, reload, help')
end

function handle_command(args)
    local sub = args[2] and args[2]:lower() or 'help'
    local n   = tonumber(args[3])

    if sub == 'rank' then
        local r = tonumber(args[3])
        if r then
            cfg.player.rank = r; item_cache = {}
            chat_print('Unity rank set to ' .. r)
            settings_lib.save()
        else
            chat_print('Unity rank is ' .. cfg.player.rank)
        end
    elseif sub == 'stp' and n then manual_stp = n; chat_print('Manual Store TP = ' .. n)
    elseif sub == 'dw' and n then manual_dw = n; chat_print('Manual Dual Wield = ' .. n)
    elseif sub == 'ghaste' and n then manual_ghaste = n; chat_print('Manual gear haste = ' .. n)
    elseif sub == 'mhaste' and n then manual_mhaste = n; chat_print('Manual magic haste = ' .. n)
    elseif sub == 'jahaste' and n then manual_jahaste = n; chat_print('Manual JA haste = ' .. n)
    elseif sub == 'dwn' and n then manual_dw_needed = n; chat_print('Manual DW needed = ' .. n)
    elseif sub == 'save' or sub == 's' then
        if args[3] and args[3]:lower() == 'wstp' then WSTP = get_tp_per_hit().tp_per_hit_melee
        else chat_print('use: /gi save wstp') end
    elseif sub == 'delete' or sub == 'd' then
        if args[3] and args[3]:lower() == 'wstp' then WSTP = 0 else chat_print('use: /gi delete wstp') end
    elseif sub == 'samba' then
        local m = args[3] and args[3]:lower() or ''
        if m == 'off' or m == 'sub' or m == 'main' then
            samba_mode = m; chat_print('Haste Samba mode: ' .. m)
        else chat_print('use: /gi samba <off|sub|main>') end
    elseif sub == 'jp' and n then
        cfg.player.jp_spent = n; settings_lib.save(); chat_print('Job points spent override = ' .. n)
    elseif sub == 'merit' and args[3] and tonumber(args[4]) and cfg.merits[args[3]:lower()] ~= nil then
        cfg.merits[args[3]:lower()] = tonumber(args[4]); settings_lib.save()
        chat_print(args[3]:lower() .. ' merits = ' .. args[4])
    elseif sub == 'hide' then
        for _, k in pairs(show_keys) do cfg.player[k] = false end
        settings_lib.save(); chat_print('All blocks hidden.')
    elseif sub == 'show' then
        local what = args[3] and args[3]:lower() or ''
        if what == 'all' then
            for _, k in pairs(show_keys) do cfg.player[k] = true end
        elseif show_keys[what] then
            cfg.player[show_keys[what]] = not cfg.player[show_keys[what]]
            chat_print(what .. ' = ' .. tostring(cfg.player[show_keys[what]]))
        else
            chat_print('unknown block: ' .. what)
        end
        settings_lib.save()
    elseif sub == 'debug' then
        debug_mode = not debug_mode; chat_print('Debug = ' .. tostring(debug_mode))
    elseif sub == 'reload' or sub == 'r' then
        AshitaCore:GetChatManager():QueueCommand(1, '/addon reload gearinfo')
    else
        help()
    end
end
