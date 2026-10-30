--[[
* GearInfo (Ashita v4 port) - lib/packets.lua
*
* Packet plumbing for the Ashita port:
*
*   * resolves a Lua string of packet bytes out of Ashita's packet event object,
*   * caches the most recent packet per id (Windower's `windower.packets.last_incoming`
*     has no direct Ashita equivalent, so the cache is built from live traffic),
*   * re-emits the Windower event names the ported source registers for
*     ('incoming chunk', 'outgoing chunk') and
*   * decodes 0x0028 into a Windower shaped action table and emits 'action'.
*
* The handlers themselves stay in the ported Packet_parsing.lua / GearInfo.lua, so the
* per packet bit work is untouched from the original addon.
--]]

local action_parser = require 'lib.action_parser';

local packets = { };

packets.incoming_id = 0x0028;

---Most recent raw bytes seen per packet id, keyed by direction.
packets.last = {
    incoming = { },
    outgoing = { },
};

---Number of recent packets retained per id (FFXI uses few distinct ids, so a small
---ring is plenty and keeps memory bounded).
packets.history = 4;

local dispatcher;

---Installs the function used to raise Windower style events.
---@param fn fun(name: string, ...): any
function packets.set_dispatcher(fn)
    dispatcher = fn;
end

---Raises an event through the installed dispatcher (no-op before installation).
local function emit(name, ...)
    if (dispatcher == nil) then return; end
    return dispatcher(name, ...);
end

---Picks the packet bytes out of an Ashita packet event as a plain Lua string.
---
---Ashita exposes the same buffer through several fields and not all of them are Lua
---strings on every build, so the first usable one wins. `data_modified` is preferred
---because it always reflects the buffer state other handlers may have edited.
---@param e table Ashita packet event object.
---@return string|nil raw
local function resolve_bytes(e)
    local candidates = { 'data_modified', 'data_raw', 'data' };
    for _, key in ipairs(candidates) do
        local value = e[key];
        if (type(value) == 'string' and #value > 0) then
            return value;
        end
    end
    return nil;
end

---Records a packet in the per id history ring.
local function remember(direction, id, raw)
    local history = packets.last[direction];
    local entries = history[id];
    if (entries == nil) then
        entries = { };
        history[id] = entries;
    end
    entries[#entries + 1] = raw;
    while (#entries > packets.history) do
        table.remove(entries, 1);
    end
end

---Returns the most recently observed incoming packet for an id.
---@param id number
---@param offset? number 0 for the most recent, 1 for the one before that, etc.
---@return string|nil
function packets.last_incoming(id, offset)
    local entries = packets.last.incoming[id];
    if (entries == nil or #entries == 0) then return nil; end
    return entries[#entries - (offset or 0)];
end

---Returns the most recently observed outgoing packet for an id.
---@param id number
---@param offset? number
---@return string|nil
function packets.last_outgoing(id, offset)
    local entries = packets.last.outgoing[id];
    if (entries == nil or #entries == 0) then return nil; end
    return entries[#entries - (offset or 0)];
end

---Forgets all cached packets - used when the player logs out or zones out.
function packets.clear()
    packets.last.incoming = { };
    packets.last.outgoing = { };
end

---Handles one incoming Ashita packet event.
---@param e table
function packets.on_in(e)
    if (e == nil or e.id == nil) then return; end

    local id   = tonumber(e.id) or 0;
    local raw  = resolve_bytes(e);
    if (raw == nil) then return; end

    remember('incoming', id, raw);

    -- Windower hands the handlers a buffer that is exactly the packet, no chunk header.
    emit('incoming chunk', id, raw, raw, false, e.blocked == true);

    if (id == packets.incoming_id) then
        local action, err = action_parser.parse(raw);
        if (action ~= nil) then
            emit('action', action);
        elseif (packets.debug) then
            print('[gearinfo] ' .. tostring(err));
        end
    end
end

---Handles one outgoing Ashita packet event.
---@param e table
function packets.on_out(e)
    if (e == nil or e.id == nil) then return; end

    local id  = tonumber(e.id) or 0;
    local raw = resolve_bytes(e);
    if (raw == nil) then return; end

    remember('outgoing', id, raw);

    -- Windower's signature is (id, original, data, injected, blocked).
    emit('outgoing chunk', id, raw, raw, false, e.blocked == true);
end

return packets;
