--[[
    GearInfo - Ashita v4 port (original Windower addon by Sebyg666)

    Removed in this port: GearSwap integration, the 0x28 action parser (and everything that
    depended on it: COR/BRD/GEO caster tracking, Warcry/Aggressor values), extdata/augment
    decoding, and the Windower-style `res` field emulation (Ashita resource fields are used
    directly, see gear.lua).
]]--

addon.name    = 'gearinfo'
addon.author  = 'Sebyg666 (Ashita v4 port)'
addon.version = '2.0.0'
addon.desc    = 'Displays haste, TP/hit, DW/MA needed, accuracy, attack, defence, DT etc. from gear and buffs.'
addon.link    = 'https://github.com/sebyg666/GearInfo'

require('common')
local chat         = require('chat')
settings_lib       = require('settings')

require('statics')
require('gear')
require('calculator')
require('buffs')
require('packets')
require('ui')

function chat_print(msg)
    print(chat.header(addon.name):append(chat.message(tostring(msg))))
end

local frame_count = 0

----------------------------------------------------------------------------------------------
-- load / unload
----------------------------------------------------------------------------------------------
ashita.events.register('load', 'gi_load', function()
    cfg = settings_lib.load(defaults)
    settings_lib.register('settings', 'gi_settings_update', function(s)
        if s ~= nil then cfg = s end
        settings_lib.save()
    end)
    item_cache = {}
    ui_reset()
end)

ashita.events.register('unload', 'gi_unload', function()
    if cfg then settings_lib.save() end
end)

----------------------------------------------------------------------------------------------
-- per-frame (replaces windower 'prerender'); all drawing happens here
----------------------------------------------------------------------------------------------
ashita.events.register('d3d_present', 'gi_present', function()
    if not cfg or not is_logged_in() then
        player_was_logged_in = false
        return
    end

    if not player_was_logged_in then
        -- covers 'login': reset per-character state
        player_was_logged_in = true
        reset_character_state()
        frame_count = 0
    end

    if frame_count % 15 == 0 then
        refresh_all()
    end
    frame_count = frame_count + 1

    ui_render()
end)

----------------------------------------------------------------------------------------------
-- packets (replaces 'incoming chunk' / 'outgoing chunk')
----------------------------------------------------------------------------------------------
ashita.events.register('packet_in', 'gi_packet_in', function(e)
    local handler = parse_in[e.id]
    if handler then handler(e) end
end)

----------------------------------------------------------------------------------------------
-- commands (replaces 'addon command')
----------------------------------------------------------------------------------------------
ashita.events.register('command', 'gi_command', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    local cmd = args[1]:lower()
    if cmd ~= '/gi' and cmd ~= '/gearinfo' then return end
    e.blocked = true
    handle_command(args)
end)
