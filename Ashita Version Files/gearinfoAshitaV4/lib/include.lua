--[[
* GearInfo (Ashita v4 port) - lib/include.lua
*
* Windower addons `require` their sibling files for side effects: every helper, cache and setting is
* a global in the addon's own environment, so Statics.lua can declare `player` and Calculator.lua can
* read it. Ashita's `require` gives each module its own return value and shares `_G` with every other
* loaded addon, which would both break that pattern and leak GearInfo's names into the client.
*
* This loader reproduces the Windower behaviour: one environment table, chained to the real globals,
* that every logic file runs inside. The files see each other's names, and nothing escapes into the
* addons loaded alongside GearInfo.
--]]

local include = { };

---The shared environment handed to every logic file.
include.env = setmetatable({ }, { __index = _G, __newindex = function (self, key, value)
    rawset(self, key, value);
end });

---Root folder the logic files are read from, set once by the entry file.
include.root = nil;

---@param path string
---@return string joined
local function join(path)
    local root = include.root or '';
    if (root ~= '' and not root:match('[\\/]$')) then
        root = root .. '\\';
    end
    local joined = (root .. path):gsub('[\\/]+', '\\');
    return joined;
end

---Runs one logic file inside the shared environment.
---@param path string Path relative to the addon root, e.g. 'logic\\Calculator.lua'.
---@return any value Whatever the chunk returns (nil for GearInfo's logic files).
function include.load(path)
    local full = join(path);
    local chunk, err = loadfile(full);
    if (chunk == nil) then
        error(('gearinfo: could not load %s: %s'):fmt(full, tostring(err)), 2);
    end
    setfenv(chunk, include.env);
    local ok, value = pcall(chunk);
    if (not ok) then
        error(('gearinfo: error in %s: %s'):fmt(full, tostring(value)), 2);
    end
    return value;
end

---Runs several logic files in order.
---@param paths string[]
function include.all(paths)
    for _, path in ipairs(paths) do
        include.load(path);
    end
end

---Reads a data file the way Windower's `require` did, returning its value.
---@param path string
---@return any value
function include.read(path)
    local full = join(path);
    local chunk, err = loadfile(full);
    if (chunk == nil) then
        error(('gearinfo: could not read %s: %s'):fmt(full, tostring(err)), 2);
    end
    return chunk();
end

return include;
