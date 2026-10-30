--[[
* GearInfo (Ashita v4 port) - lib/bitstream.lua
*
* Provides the two low level reading primitives the Windower original relies on:
*
*   1. A non destructive, little endian, LSB first bit reader. This is used by the
*      action parser (packet 0x0028) and replaces Windower's `bit.unpack`.
*   2. A byte oriented unpacker installed as `string.unpack` / `struct.unpack` so
*      ported source can keep calling `data:unpack('H', 0x15)` verbatim.
*
* Byte offset convention: Windower's packet field tables document 0 based absolute
* offsets, and `data:unpack(fmt, N)` / `data:byte(N)` use 1 based indices where
* N = offset + 1. Ashita's packet event `data_raw` string carries the exact same
* bytes including the 4 byte header, so every index in the ported source transfers
* unchanged.
--]]

local bitstream = { };

if (bit == nil) then
    error('GearInfo requires the moonjit "bit" library, which ships with Ashita v4.');
end

local band   = bit.band;
local bor    = bit.bor;
local lshift = bit.lshift;
local rshift = bit.rshift;

-- Maximum field width handled by the reader. Fields wider than this are not used by
-- any of the packets this addon parses (the widest is a 32 bit id/recast value).
bitstream.max_field_bits = 32;

---Creates a new reader bound to a raw byte string.
---@param data string|table Raw packet bytes (or a table of byte values).
---@return table
function bitstream.new(data)
    local self = setmetatable({ }, { __index = bitstream });

    if (type(data) == 'table') then
        local bytes = { };
        for i = 1, #data do bytes[i] = data[i]; end
        self.nbytes = #bytes;
        self._at = function (_, idx) return bytes[idx]; end;
    else
        local text = data or '';
        self.nbytes = #text;
        self._at = function (_, idx) return text:byte(idx); end;
    end

    self.bit = 0;
    return self;
end

---Resets the sequential cursor back to bit 0.
function bitstream.seek(self, abs_bit)
    self.bit = abs_bit or 0;
end

---Returns the current absolute bit position of the sequential cursor.
function bitstream.tell(self)
    return self.bit;
end

---Reads `count` bits starting at the absolute bit position `abs_bit`.
---
---Bits are consumed least significant first inside each byte and bytes are read
---low address first, which is how both engines lay out FFXI packet bitfields.
---@param abs_bit number 0 based absolute bit offset.
---@param count number Number of bits (1..32).
---@return number|nil value nil when the request runs past the end of the buffer.
function bitstream.read_at(self, abs_bit, count)
    if (count == nil or count < 0 or count > bitstream.max_field_bits) then
        return nil;
    end

    local byte_index = math.floor(abs_bit / 8);          -- 0 based
    local bit_offset = abs_bit - byte_index * 8;         -- 0..7

    if (byte_index < 0 or count > (self.nbytes * 8) - abs_bit) then
        return nil;
    end

    -- Accumulate the covering bytes into a little endian integer, then shift/mask.
    -- Plain arithmetic (not bit ops) is used here because an unaligned read can span
    -- five bytes, and 40 bit intermediates overflow the 32 bit bit library primitives.
    local span  = math.ceil((bit_offset + count) / 8);
    local value = 0;
    for k = span - 1, 0, -1 do
        local b = self:_at(byte_index + k + 1);
        if (b == nil) then return nil; end
        value = value * 256 + b;
    end

    value = math.floor(value / 2^bit_offset);
    return value % 2^count;
end

---Reads `count` bits from the sequential cursor and advances it.
---@param count number
---@return number|nil
function bitstream.read(self, count)
    local value = bitstream.read_at(self, self.bit, count);
    if (value == nil) then return nil; end
    self.bit = self.bit + count;
    return value;
end

---Reads a single byte (1 based index) without moving the cursor.
function bitstream.byte(self, index)
    return self:_at(index);
end

---Reads an unsigned 16 bit little endian value (1 based index).
function bitstream.u16(self, index)
    local lo = self:_at(index);
    local hi = self:_at(index + 1);
    if (lo == nil or hi == nil) then return nil; end
    return bor(lshift(hi, 8), lo);
end

---Reads an unsigned 32 bit little endian value (1 based index).
function bitstream.u32(self, index)
    local b1 = self:_at(index);
    local b2 = self:_at(index + 1);
    local b3 = self:_at(index + 2);
    local b4 = self:_at(index + 3);
    if (b1 == nil or b2 == nil or b3 == nil or b4 == nil) then return nil; end
    return bor(lshift(b4, 24), lshift(b3, 16), lshift(b2, 8), b1);
end

----------------------------------------------------------------------------------------------------
--
-- Byte oriented unpacker
--
----------------------------------------------------------------------------------------------------

local format_sizes = {
    b = 1, B = 1,
    h = 2, H = 2,
    i = 4, I = 4,
};

local function as_signed(value, bits)
    if (value >= 2^(bits - 1)) then
        return value - 2^bits;
    end
    return value;
end

---Unpacks a raw byte string using a Lua 5.4 style format string.
---
---Supported: optional '<' endian marker (the only one we need - FFXI packets are
---little endian), then any number of 'b' 'B' 'h' 'H' 'i' 'I' fields,
---'c<N>' byte blobs and 'z' nul terminated strings.
---@param data string
---@param fmt string
---@param index? number 1 based byte index (defaults to 1).
---@return any ... , number next_index
function bitstream.unpack(data, fmt, index)
    local size = #data;
    local pos  = index or 1;
    if (type(pos) ~= 'number') then pos = 1; end

    local results = { };
    local cursor  = pos;
    local flip    = false;

    local i = 1;
    local len = #fmt;
    while (i <= len) do
        local c = fmt:sub(i, i);

        if (c == '=') or (c == '!') then
            i = i + 1;
        elseif (c == '<') then
            flip = false;
            i = i + 1;
        elseif (c == '>') then
            flip = true;
            i = i + 1;
        elseif (c == ' ') then
            i = i + 1;
        elseif (c == 'c' or c == 'z' or c == 's') then
            if (c == 'c') then
                local j = i + 1;
                while (j <= len and fmt:sub(j, j):match('%d')) do j = j + 1; end
                local count = tonumber(fmt:sub(i + 1, j - 1)) or 1;
                results[#results + 1] = data:sub(cursor, cursor + count - 1);
                cursor = cursor + count;
                i = j;
            elseif (c == 'z') then
                local nul = data:find('\0', cursor, true);
                if (nul == nil) then nul = size + 1; end
                results[#results + 1] = data:sub(cursor, nul - 1);
                cursor = nul + 1;
                i = i + 1;
            else
                local j = i + 1;
                while (j <= len and fmt:sub(j, j):match('%d')) do j = j + 1; end
                local count = tonumber(fmt:sub(i + 1, j - 1)) or 4;
                local bytes = data:sub(cursor, cursor + count - 1);
                results[#results + 1] = (bytes:gsub('%z.*$', ''));
                cursor = cursor + count;
                i = j;
            end
        else
            local field_size = format_sizes[c];
            if (field_size == nil) then
                return nil, string.format('bitstream: unsupported format character "%s"', c);
            end
            if (cursor + field_size - 1 > size) then
                return nil, string.format('bitstream: buffer overrun unpacking "%s" at %d (size %d)', fmt, cursor, size);
            end

            local value = 0;
            for k = field_size - 1, 0, -1 do
                local b = data:byte(cursor + k);
                if (flip) then b = data:byte(cursor + (field_size - 1 - k)); end
                value = bor(lshift(value, 8), b);
            end

            local bits = field_size * 8;
            if (c == 'B') then
                results[#results + 1] = band(value, 0xFF);
            elseif (c == 'b') then
                results[#results + 1] = as_signed(band(value, 0xFF), 8);
            elseif (c == 'H') then
                results[#results + 1] = band(value, 0xFFFF);
            elseif (c == 'h') then
                results[#results + 1] = as_signed(band(value, 0xFFFF), 16);
            elseif (c == 'I') then
                results[#results + 1] = value;
            elseif (c == 'i') then
                results[#results + 1] = as_signed(value, bits);
            end

            cursor = cursor + field_size;
            i = i + 1;
        end
    end

    results[#results + 1] = cursor;
    return unpack(results);
end

---Unpacks a bitfield using Windower's `bit.unpack` convention.
---
---The bit index is 1 based, so a field documented at absolute bit offset 40 is read
---with `bitstream.unpack_bits(data, 'B32', 41)`.
---@param fmt string 'b<N>' for signed, 'B<N>' for unsigned.
---@param data string
---@param bit_index number 1 based absolute bit position.
---@return number|nil
function bitstream.unpack_bits(fmt, data, bit_index)
    local sign   = fmt:sub(1, 1);
    local count  = tonumber(fmt:match('^%D(%d+)$'));
    if (count == nil or count > bitstream.max_field_bits) then
        return nil;
    end

    local reader = bitstream.new(data);
    local value  = reader:read_at((bit_index or 1) - 1, count);
    if (value == nil) then return nil; end
    if (sign == 'b') then
        return as_signed(value, count);
    end
    return value;
end

----------------------------------------------------------------------------------------------------
--
-- Installation
--
----------------------------------------------------------------------------------------------------

---Installs the unpack primitives onto the global namespaces the ported source uses.
---
---Sugar overrides the string metatable's `__index` but its `string_mt` table does not
---define `unpack`, so adding it here stays reachable through `data:unpack(...)`.
function bitstream.install()
    -- String methods (1 based byte index, matches Windower).
    if (string.unpack == nil) then
        string.unpack = function (data, fmt, index)
            return bitstream.unpack(data, fmt, index);
        end;
    end

    -- A few places in the original tree call windower.struct / struct directly.
    if (rawget(_G, 'struct') == nil) then
        _G.struct = {
            unpack  = function (fmt, data, index) return bitstream.unpack(data, fmt, index); end,
            pack    = function () error('struct.pack is not required by GearInfo.') end,
            sizes   = format_sizes,
        };
    end

    -- Bit oriented unpack, matching Windower's bit.unpack argument order.
    if (bit ~= nil and bit.unpack == nil) then
        bit.unpack = bitstream.unpack_bits;
    end
end

return bitstream;
