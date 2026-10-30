--[[
* GearInfo (Ashita v4 port) - lib/files.lua
*
* Windower's files library is a small wrapper over the addon's own folder. The addon only needs two
* of its calls, so this shim implements exactly those:
*
*     files.exists('data\\<name>_data.lua')      - relative to windower.addon_path
*     files.new('data\\<name>_data.lua', true)   - object with :create()
*
* Everything else the addon does with files already uses plain io.open(windower.addon_path .. ...),
* which works unchanged in Ashita's Lua state.
--]]

require 'common';

local files = { };

---Resolves a Windower relative path against the addon folder.
---@param path string
---@return string absolute
local function resolve(path)
    path = tostring(path or '');
    if (path:match('^%a:[\\/]') or path:match('^\\\\')) then
        return path;
    end
    return (windower.addon_path .. path);
end

---@param path string
---@return boolean exists
function files.exists(path)
    local full = resolve(path);
    if (full == '') then
        return false;
    end
    return ashita.fs.exists(full);
end

---@param path string
---@return string folder
local function parent_of(path)
    return path:match('^(.*)[\\/][^\\/]+$');
end

local object_mt = { };
object_mt.__index = object_mt;

---Creates the file (and its folder) when it does not exist yet, like Windower's files.create().
---@return boolean created
function object_mt:create()
    local full = resolve(self.path);
    if (ashita.fs.exists(full)) then
        return false;
    end

    local folder = parent_of(full);
    if (folder ~= nil and not ashita.fs.exists(folder)) then
        ashita.fs.create_dir(folder);
    end

    local f = io.open(full, 'w+');
    if (f == nil) then
        return false;
    end
    f:close();
    return true;
end

---@return boolean exists
function object_mt:exists()
    return files.exists(self.path);
end

---Windower's files.new(path, auto_create). The second argument only asks that the file be created
---when missing, which is what the caller does next with :create(), so it is not acted on here.
---@param path string
---@param auto_create? boolean
---@return table file
function files.new(path, auto_create)
    return setmetatable({ path = tostring(path or ''), auto_create = auto_create, }, object_mt);
end

return files;
