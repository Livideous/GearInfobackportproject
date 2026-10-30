--[[
* GearInfo (Ashita v4 port)
*
* Item extra-data (extdata) decoder. The logic and lookup tables are vendored from the
* Windower "extdata" library so that augmented gear produces exactly the same human
* readable augment strings that the original addon parses.
*
* Ashita exposes an item's raw extra data on item_t.Extra, which uses the same byte
* layout as Windower's item.extdata field, so the decoders below are unchanged.
--]]

require 'common';

local augment_data  = require 'lib.augment_data';

local sp_390_augments = augment_data.sp_390_augments;
local augment_values  = augment_data.augment_values;

local extdata = {};
local decode  = {};
local tools   = { aug = { } };

--[[
* Unpacks a single augment pair into its lookup id and potency index.
]]
function tools.aug.unpack_augment(sys, short)
    if (sys == 1) then
        return short:byte(1) + short:byte(2) % 8 * 256, math.floor(short:byte(2) / 8);
    elseif (sys == 2) then
        return short:byte(1), short:byte(2);
    elseif (sys == 3) then
        return short:byte(1) + short:byte(2) % 8 * 256, math.floor(short:byte(2) % 128 / 8);
    elseif (sys == 4) then
        return short:byte(1), short:byte(2);
    end
end

--[[
* Builds the readable text for the given augment id/potency pair.
]]
function tools.aug.string_augment(sys, id, val)
    local augment;
    local augment_table = augment_values[sys] and augment_values[sys][id];
    if (augment_table and augment_table.Secondary_Handling) then
        augment_table = sp_390_augments[(id - 0x390) * 16 + 545 + val];
    end

    if (augment_table) then
        if (sys == 3) then
            augment = augment_table[1].stat;
            local pot = augment_table[1].potency[val];
            if (pot > 0) then
                augment = augment .. '+';
            end
            augment = augment .. pot;
        else
            for i, v in pairs(augment_table) do
                if (i > 1) then
                    augment = augment .. ' ';
                end
                augment = (augment or '') .. v.stat;
                local potency = ((val + v.offset) * (v.multiplier or 1));
                if (potency > 0) then
                    augment = augment .. '+' .. potency;
                elseif (potency < 0) then
                    augment = augment .. potency;
                end
                if (v.percent) then
                    augment = augment .. '%';
                end
            end
        end
    else
        augment = ('System: %d ID: %d Val: %d'):fmt(sys, id, val);
    end

    return augment;
end

--[[
* Decodes a packed augment string into a list of readable augment strings.
]]
function tools.aug.augments_to_table(sys, str)
    local augments = { };
    for i = 1, #str, 2 do
        local id, val = tools.aug.unpack_augment(sys, str:sub(i, i + 1));
        augments[#augments + 1] = tools.aug.string_augment(sys, id, val);
    end
    return augments;
end

function decode.Unknown(str)
    return { type = 'Unknown', data = str };
end

function decode.General(str)
    return { type = 'General' };
end

function decode.Enchanted(str)
    return {
        type              = 'Enchanted Equipment',
        charges_remaining = str:byte(2),
        usable            = str:byte(4) % 128 / 64 >= 1,
        next_use_time     = struct.unpack('I4', str, 5),
        activation_time   = struct.unpack('I4', str, 9),
    };
end

function decode.Augmented(str)
    local flag_2  = str:byte(2);
    local rettab  = { type = 'Augmented Equipment' };

    if (flag_2 % 128 / 64 >= 1) then
        rettab.trial_number   = (str:byte(12) % 128) * 256 + str:byte(11);
        rettab.trial_complete = str:byte(12) / 128 >= 1;
    end

    if (flag_2 % 16 / 8 >= 1) then
        -- Crafting shields
        rettab.objective  = str:byte(6);
        local units       = { 30, 50, 100, 100 };
        rettab.stage      = math.max(1, math.min(4, str:byte(0x9)));
        rettab.completion = struct.unpack('H2', str, 7) / units[rettab.stage];
    elseif (flag_2 % 64 / 32 >= 1) then
        -- Pathed (JSE) equipment
        rettab.augment_system = 2;
        local path_map  = { [0] = 'A', [1] = 'B', [2] = 'C', [3] = 'D' };
        local points_map = { [1] = 50, [2] = 80, [3] = 120, [4] = 170, [5] = 220, [6] = 280, [7] = 340,
                             [8] = 410, [9] = 480, [10] = 560, [11] = 650, [12] = 750, [13] = 960, [14] = 980 };
        rettab.path  = path_map[str:byte(3) % 4];
        rettab.rank  = math.floor(str:byte(3) % 128 / 4);
        rettab.RP    = math.max((points_map[rettab.rank] or 0) - str:byte(6) * 256 - str:byte(5), 0);
        rettab.augments = tools.aug.augments_to_table(rettab.augment_system, str:sub(7, 12));
    elseif (flag_2 == 131) then
        rettab.augment_system = 4;
        local path_map = { [0] = 'A', [1] = 'B', [2] = 'C', [3] = 'D' };
        rettab.path  = path_map[math.floor(str:byte(5) % 4)];
        rettab.rank  = math.floor(str:byte(7) % 128 / 4);
        rettab.augments = { 'Path: ' .. rettab.path };
    elseif (flag_2 / 128 >= 1) then
        -- Evolith gear
        rettab.augment_system = 3;
        rettab.augments = tools.aug.augments_to_table(rettab.augment_system, str:sub(3, 8));
    else
        rettab.augment_system = 1;
        if (rettab.trial_number) then
            rettab.augments = tools.aug.augments_to_table(rettab.augment_system, str:sub(3, 10));
        else
            rettab.augments = tools.aug.augments_to_table(rettab.augment_system, str:sub(3, 12));
        end
    end

    return rettab;
end

function decode.Equipment(str)
    local flag_1 = str:byte(1);
    local flag_1_mapping = {
        [1] = decode.Enchanted,
        [2] = decode.Augmented,
        [3] = decode.Augmented,
    };

    local rettab;
    if (flag_1_mapping[flag_1]) then
        rettab = flag_1_mapping[flag_1](str:sub(1, 12));
    else
        rettab = decode.Unknown(str:sub(1, 12));
        rettab.type = 'Equipment';
    end

    return rettab;
end

-- Item type -> decoder. Matches the numeric "Type" field of the item resources.
local typ_mapping = {
    [1]  = decode.General,     -- General
    [2]  = decode.General,     -- Fight Entry Items
    [3]  = decode.General,     -- Fish
    [4]  = decode.Equipment,   -- Weapons
    [5]  = decode.Equipment,   -- Armor
    [6]  = decode.General,     -- Linkshells
    [7]  = decode.General,     -- Usable Items
    [8]  = decode.General,     -- Crystals
    [10] = decode.General,     -- Furniture
    [11] = decode.General,     -- Seeds
    [12] = decode.General,     -- Flowerpots
    [14] = decode.General,     -- Mannequins
    [15] = decode.General,     -- Ballista Books
    [18] = decode.General,     -- Soul Plates
    [19] = decode.General,     -- Soul Reflectors
    [21] = decode.General,     -- Mog Bonanza Marbles
    [28] = decode.General,     -- Legion Pass
};

--[[
* Decodes the extra data of the given item.
*
* @param {table} tab - Table holding { id = <item id>, extdata = <raw extra data string> }.
* @return {table} The decoded extra data, including the readable "augments" list when present.
--]]
function extdata.decode(tab)
    if (tab == nil) then
        error('extdata.decode was passed a nil value');
    end

    local id = tab.id or tab.Id;
    local ex = tab.extdata or tab.Extra;

    if (id == nil or id == 0 or ex == nil or type(ex) ~= 'string' or #ex < 12) then
        return { type = 'Unknown' };
    end

    local ritem = AshitaCore:GetResourceManager():GetItemById(id);
    if (ritem == nil) then
        return { type = 'Unknown' };
    end

    local func = typ_mapping[ritem.Type] or decode.Unknown;
    local decoded = func(ex);
    decoded.__raw = ex;
    return decoded;
end

--[[
* Returns true when every augment in goal is present in current.
]]
function extdata.compare_augments(goal_augs, current)
    if (not current) then return false end

    local fn = function (str)
        return type(str) == 'string' and str ~= 'none';
    end

    local cur = T{ };
    for _, v in pairs(T(current):filter(fn)) do
        cur:append(v);
    end

    local goal = T{ };
    for _, v in pairs(T(goal_augs):filter(fn)) do
        goal:append(v);
    end

    local aug_strip = function (str)
        return str:lower():gsub('[^%-%w,]', '');
    end

    local num_augments = 0;
    for i, augment in pairs(cur) do
        if (augment == 'none') then
            cur[i] = nil;
        else
            num_augments = num_augments + 1;
        end
    end

    if (num_augments < #goal) then
        return false;
    end

    local count = 0;
    for _, goal_aug in pairs(goal) do
        local bool;
        for cur_ind, cur_aug in pairs(cur) do
            if (aug_strip(goal_aug) == aug_strip(cur_aug)) then
                bool = true;
                count = count + 1;
                cur[cur_ind] = nil;
                break;
            end
        end
        if (not bool) then
            return false;
        end
    end

    return count == #goal;
end

return extdata;
