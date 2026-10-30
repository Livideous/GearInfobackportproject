--[[
* GearInfo (Ashita v4 port) - the little 'chars' table Windower exposed as chat/chars.lua.
*
* Windower builds that table from control sequences in the game's chat font. Ashita ships an
* equivalent, but much smaller, set (chat.symbols) and none of its entries cover the two glyphs
* GearInfo prints for Corsair rolls, so they are rendered as plain ASCII here. Substituting the
* bytes we cannot verify would print garbage in the log; ASCII stays readable on every client.
*
* Keys are built dynamically ('circle' .. rollNum), so unknown keys resolve to an empty string
* rather than nil - concatenating nil would abort the whole action handler.
--]]

local chars = {
    implies = '->',
};

setmetatable(chars, {
    __index = function (self, key)
        local n = tonumber(string.match(tostring(key), '^circle(%d+)$'));
        if (n ~= nil) then
            return '(' .. n .. ')';
        end
        return '';
    end,
});

return chars;
