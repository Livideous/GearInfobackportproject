--[[
* GearInfo (Ashita v4 port) - lib/config.lua
*
* Windower's config library stored each characters settings as XML next to the addon. Ashita has no
* XML settings helper, so this shim keeps the same call shape and writes plain Lua tables instead:
*
*     settings = config.load('data\\<name>_settings.xml', defaults)
*     settings.player.rank = 5
*     settings:save('all')
*
* Notes on the translation:
*   * The '.xml' extension is rewritten to '.lua' - the format changed, and telling the two apart on
*     disk avoids loading a file this shim cannot parse. Nothing in the addon reads the old XML.
*   * Values loaded from disk are merged over the defaults recursively, so a settings file written by
*     an older version keeps its values and still gains any new key.
*   * Only save()/reset() are implemented; the port never used the rest of Windower's config object.
--]]

require 'common';

local compat = require 'lib.compat';

local config = { };

local methods = { };

---Returns a shallow copy without the bookkeeping keys the metatable object carries.
---@param t table
---@return table stripped
local function strip(t)
    local ret = { };
    for k, v in pairs(t) do
        if (type(k) ~= 'string' or k:sub(1, 2) ~= '__') then
            ret[k] = v;
        end
    end
    return ret;
end

---Writes the settings table back to disk. The argument is accepted and ignored: Windower used it to
---select which top level keys to store, GearInfo only ever passed 'all'.
---@param self table
---@return boolean saved
function methods.save(self)
    local file = rawget(self, '__file');
    if (file == nil) then
        return false;
    end
    local parent = file:match('^(.*)[\\/][^\\/]+$');
    if (parent ~= nil and not ashita.fs.exists(parent)) then
        ashita.fs.create_dir(parent);
    end

    local f = io.open(file, 'w+');
    if (f == nil) then
        return false;
    end
    f:write('return ' .. compat.serialize(strip(self)) .. '\n');
    f:close();
    return true;
end

---Restores the default values without touching anything else about the table's identity.
---@param self table
---@return boolean
function methods.reset(self)
    local defaults = rawget(self, '__defaults');
    for k in pairs(self) do
        if (type(k) ~= 'string' or k:sub(1, 2) ~= '__') then
            rawset(self, k, nil);
        end
    end
    for k, v in pairs(compat.table_copy(defaults, true)) do
        rawset(self, k, v);
    end
    return methods.save(self);
end

local instance_mt = {
    __index = function (self, key)
        return methods[key];
    end,
};

---Deep copies a table so the caller never writes through to the defaults.
---@param t table
---@return table copy
local function copy(t)
    local ret = { };
    for k, v in pairs(t) do
        ret[k] = (type(v) == 'table') and copy(v) or v;
    end
    return ret;
end

---Overwrites the values of 'a' with the matching entries of 'b', recursing into tables.
---@param a table
---@param b table
local function merge(a, b)
    for k, v in pairs(b) do
        if (type(v) == 'table' and type(a[k]) == 'table') then
            merge(a[k], v);
        else
            a[k] = v;
        end
    end
end

---Turns a Windower relative or absolute path into one this process can open, with '.lua' settings.
---@param path string
---@return string file
local function resolve(path)
    path = tostring(path or 'settings.xml'):gsub('/', '\\');
    if (not path:match('^%a:\\')) then
        path = (windower.addon_path):gsub('/', '\\') .. path;
    end
    return (path:gsub('%.xml$', '.lua'));
end

---Loads (or creates) a settings table, Windower style.
---@param path string
---@param defaults table
---@return table settings
function config.load(path, defaults)
    local file = resolve(path);

    local settings = copy(defaults or { });
    if (ashita.fs.exists(file)) then
        local chunk, err = loadfile(file);
        if (chunk ~= nil) then
            local ok, stored = pcall(chunk);
            if (ok and type(stored) == 'table') then
                merge(settings, stored);
            end
        else
            print(('[gearinfo] could not read settings (%s), using defaults.'):fmt(tostring(err)));
        end
    end

    rawset(settings, '__file', file);
    rawset(settings, '__defaults', defaults or { });
    setmetatable(settings, instance_mt);
    methods.save(settings);

    return settings;
end

return config;
