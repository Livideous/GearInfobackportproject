--[[
* GearInfo (Ashita v4 port) - lib/action_parser.lua
*
* Ashita has no 'action' event. The game only delivers packet 0x0028, so this module
* bit-decodes it and hands the consumer the exact table shape Windower's core used to
* build before firing 'action'.
*
* Field layout (absolute bit offsets, verified against Windower's packet field table
* and three independent Ashita 0x0028 parsers):
*
*   base     : Actor 32 @40, Target Count 10 @72, Category 4 @82, Param 16 @86,
*              _unknown1 16 @102, Recast 32 @118                     -> ends @150
*   target   : ID 32, Action Count 4
*   action   : Reaction 5, Animation 12, Effect 4, Stagger 3, Knockback 3, Param 17,
*              Message 10, _unknown 31                               -> 85 bits
*              Has Added Effect 1 -> [Animation 6, Effect 4, Param 17, Message 10]
*              Has Spike Effect 1 -> [Animation 6, Effect 4, Param 14, Message 10]
*
* Fields belonging to an absent group stay nil, exactly like Windower, so guards such
* as `if m.has_spike_effect then` keep working.
--]]

local bitstream = require 'lib.bitstream';

local action_parser = { };

action_parser.packet_id = 0x0028;
action_parser.base_bit  = 40; -- the 40 leading bits are the packet header + size byte

---Human readable category names, kept for the debug command and the readme.
action_parser.categories = {
    [0]  = 'Idle',
    [1]  = 'Attack',
    [2]  = 'Ranged Attack (finish)',
    [3]  = 'Weapon Skill (finish)',
    [4]  = 'Magic (finish)',
    [5]  = 'Item (finish)',
    [6]  = 'Job Ability',
    [7]  = 'Weapon Skill / Monster Skill (start)',
    [8]  = 'Magic (start)',
    [9]  = 'Item (start)',
    [10] = 'Job Ability (start)',
    [11] = 'Monster Skill (finish)',
    [12] = 'Ranged Attack (start)',
    [13] = 'Avatar TP (finish)',
    [14] = 'Dancer',
    [15] = 'Rune Fencer',
};

---Parses the raw bytes of a 0x0028 packet into a Windower shaped action table.
---@param raw string Raw packet bytes, including the 4 byte header (Ashita's `e.data_raw`).
---@return table|nil action, string|nil err
function action_parser.parse(raw)
    if (type(raw) ~= 'string' or #raw < 8) then
        return nil, 'action_parser: packet too small';
    end

    local reader = bitstream.new(raw);
    reader:seek(action_parser.base_bit);

    local function take(bits)
        local value = reader:read(bits);
        if (value == nil) then error('buffer overrun', 0); end
        return value;
    end

    local ok, action = pcall(function ()
        local parsed = { };

        parsed.actor_id     = take(32);
        parsed.target_count = take(10);
        parsed.category     = take(4);
        parsed.param        = take(16);
        parsed._unknown1    = take(16);
        parsed.recast       = take(32);

        parsed.targets = { };
        for _ = 1, parsed.target_count do
            local target = { };
            target.id = take(32);
            target.action_count = take(4);
            target.actions = { };

            for _ = 1, target.action_count do
                local entry = { };
                entry.reaction  = take(5);
                entry.animation = take(12);
                entry.effect    = take(4);
                entry.stagger   = take(3);
                entry.knockback = take(3);
                entry.param     = take(17);
                entry.message   = take(10);
                entry._unknown  = take(31);

                if (take(1) ~= 0) then
                    entry.has_add_effect      = true;
                    entry.add_effect_animation = take(6);
                    entry.add_effect_effect    = take(4);
                    entry.add_effect_param     = take(17);
                    entry.add_effect_message   = take(10);
                else
                    entry.has_add_effect = false;
                end

                if (take(1) ~= 0) then
                    entry.has_spike_effect      = true;
                    entry.spike_effect_animation = take(6);
                    entry.spike_effect_effect    = take(4);
                    entry.spike_effect_param     = take(14);
                    entry.spike_effect_message   = take(10);
                else
                    entry.has_spike_effect = false;
                end

                target.actions[#target.actions + 1] = entry;
            end

            parsed.targets[#parsed.targets + 1] = target;
        end

        return parsed;
    end);

    if (not ok) then
        return nil, 'action_parser: ' .. tostring(action);
    end
    return action;
end

---Returns the readable name of an action category.
---@param category number
---@return string
function action_parser.category_name(category)
    return action_parser.categories[category] or string.format('%d:Unknown', category or -1);
end

return action_parser;
