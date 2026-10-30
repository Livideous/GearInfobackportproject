--[[
* GearInfo (Ashita v4 port)
* Compatibility layer.
*
* The original addon was written against Windower's "tables", "lists" and "strings" libraries.
* Ashita ships an equivalent (but not identical) sugar library, so this module fills in the few
* helpers the port still relies on. Everything here is namespaced under the returned table, and
* the handful of global table/string helpers are only installed on the addon's own state.
--]]

require 'common';

local compat = T{ };

--[[
* Returns the number of entries in the given table (hash part included).
]]
function compat.table_length(t)
    if (t == nil) then return 0 end
    if (type(t.length) == 'function') then return t:length() end
    local n = 0;
    for _ in pairs(t) do n = n + 1 end
    return n;
end

--[[
* Returns true when the given value is stored anywhere in the table.
]]
function compat.table_contains(t, value)
    if (t == nil) then return false end
    if (type(t.contains) == 'function') then return t:contains(value) end
    for _, v in pairs(t) do
        if (v == value) then return true end
    end
    return false;
end

--[[
* Returns true when the given key exists in the table.
]]
function compat.table_containskey(t, key)
    if (t == nil or key == nil) then return false end
    if (type(t.containskey) == 'function') then return t:containskey(key) end
    for k in pairs(t) do
        if (k == key) then return true end
    end
    return false;
end

--[[
* Deep/shallow copies the given table.
]]
function compat.table_copy(t, deep)
    if (t == nil) then return t end
    if (type(t.copy) == 'function') then return t:copy(deep) end
    local ret = { };
    for k, v in pairs(t) do
        ret[k] = (type(v) == 'table') and compat.table_copy(v, deep) or v;
    end
    return ret;
end

--[[
* Replaces the contents of 'a' with the contents of 'b', keeping 'a's identity.
]]
function compat.table_reassign(a, b)
    for k in pairs(a) do
        a[k] = nil;
    end
    for k, v in pairs(b or { }) do
        a[k] = v;
    end
    return a;
end

--[[
* Shifts every numeric key down so the table starts at 1 (Windower's table.rekey).
]]
function compat.table_rekey(t)
    local vals = { };
    for _, v in pairs(t) do
        vals[#vals + 1] = v;
    end
    for k in pairs(t) do
        t[k] = nil;
    end
    for i, v in ipairs(vals) do
        t[i] = v;
    end
    return t;
end

--[[
* Debug dump used throughout the original source.
]]
function compat.table_vprint(tbl, indent)
    if (tbl == nil) then return end
    indent = indent or 0;
    local pre = string.rep('  ', indent);
    for k, v in pairs(tbl) do
        if (type(v) == 'table') then
            print(('%s[%s] = {'):fmt(pre, tostring(k)));
            compat.table_vprint(v, indent + 1);
            print(('%s}'):fmt(pre));
        else
            print(('%s[%s] = %s'):fmt(pre, tostring(k), tostring(v)));
        end
    end
end

--[[
* Serialises a table back to loadable lua source. Used by the data files the addon writes.
]]
local function serialize(v, indent, seen)
    local pre = string.rep('    ', indent);
    if (type(v) ~= 'table') then
        if (type(v) == 'string') then return ('%q'):format(v) end
        if (type(v) == 'number') then return ('%.17g'):format(v) end
        return tostring(v);
    end

    seen = seen or { };
    if (seen[v]) then return '{}' end
    seen[v] = true;

    -- Keep array parts ordered, then the hash part sorted for stable output.
    local keys, out = { }, { };
    for k in pairs(v) do
        keys[#keys + 1] = k;
    end
    table.sort(keys, function (a, b)
        if (type(a) == type(b)) then return tostring(a) < tostring(b) end
        return type(a) < type(b)
    end);

    for _, k in ipairs(keys) do
        local key;
        if (type(k) == 'number') then
            key = ('[%d]'):format(k);
        else
            key = ('[%q]'):format(tostring(k));
        end
        out[#out + 1] = ('%s%s = %s,'):format(pre .. '    ', key, serialize(v[k], indent + 1, seen));
    end

    return ('{\n%s\n%s}'):format(table.concat(out, '\n'), pre);
end

function compat.serialize(t)
    return serialize(t, 0, { });
end

--[[
* Installs the Windower style helper functions onto the base libraries.
* These are only visible to this addons lua state, so there is no cross addon pollution.
--]]
function compat.install()
    -- Table helpers..
    if (table.length == nil) then table.length      = compat.table_length;      end
    if (table.contains == nil) then table.contains  = compat.table_contains;    end
    if (table.containskey == nil) then table.containskey = compat.table_containskey; end
    if (table.reassign == nil) then table.reassign  = compat.table_reassign;    end
    if (table.rekey == nil) then table.rekey        = compat.table_rekey;       end
    if (table.vprint == nil) then table.vprint      = compat.table_vprint;      end
    if (table.copy == nil) then table.copy          = compat.table_copy;        end

    -- String helpers. Ashita's sugar library installs its methods on the 'string' table as well as
    -- on string values, so anything defined on the metatable chain below is reachable both ways.
    --
    -- Windower's TSI serialiser ('t:tovstring()') has no Ashita equivalent. The port only uses it to
    -- write lua data files, so a plain serialisable dump is the correct replacement. It is installed
    -- on 'table' because sugar resolves T-table lookups through 'table'.
    if (table.tovstring == nil) then
        ---@param self table
        ---@return string
        table.tovstring = function (self)
            return compat.serialize(self);
        end;
    end

    -- Windower's L{} / S{} constructors. Sugar's T{} already provides :contains/:append/:filter/:map,
    -- which is all the ported code uses from L{} and S{}.
    if (L == nil) then L = function (t) return T(t or { }); end end
    if (S == nil) then S = function (t) return T(t or { }); end end
    if (P == nil) then P = function (t) return T(t or { }); end end

    -- Windower's notice()/log() chat helpers. Windower's logger wrote straight to the game chat log,
    -- so Ashita's console bound print() is not the right sink here.
    local chat = require 'chat';
    local function to_chat(kind, args)
        local text = table.concat(args, ' ');
        windower.add_to_chat(1, tostring(chat.header(addon.name):append(kind(text))));
    end
    if (notice == nil) then
        notice = function (...)
            local args = { ... };
            for i = 1, #args do args[i] = tostring(args[i]) end
            to_chat(chat.message, args);
        end;
    end
    if (log == nil) then
        log = function (...)
            local args = { ... };
            for i = 1, #args do args[i] = tostring(args[i]) end
            to_chat(chat.success, args);
        end;
    end
end

return compat;
