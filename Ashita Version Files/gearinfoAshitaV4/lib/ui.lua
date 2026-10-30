--[[
* GearInfo (Ashita v4 port)
* Windower text/primitive UI translated onto Ashita's 'fonts' and 'primitives' libraries.
*
* Image_processing.lua drives its overlay through Windower's id keyed api:
*
*     windower.text.create(id)  windower.prim.create(id)
*     windower.text.set_* (id, ...)  windower.prim.set_* (id, ...)
*     windower.text.get_extents(id)
*
* Everything here keeps that shape, so the ported UI code is unchanged. Each id maps to one Ashita
* font or primitive object created from the addon's own library instance.
*
* Mapping notes:
*   * Windower passes colours as four 0-255 components, Ashita takes one packed 0xAARRGGBB value.
*     The pack is done with arithmetic, not bit ops, because bit.lshift() returns a signed 32 bit
*     value and SetColor() wants the unsigned form.
*   * set_stroke_width()/set_stroke_color() map onto Ashita's outline draw flag plus its padding
*     scale; GearInfo only ever sets a width of 0, so text stays unoutlined as it was.
*   * set_fit_to_texture() has no Ashita equivalent. GearInfo always follows it with an explicit
*     set_size(), so the request is recorded and otherwise inert.
*   * Windower's mouse event numbers (0 move, 1 left press, 2 left release) are translated from the
*     WNDPROC messages Ashita reports.
--]]

require 'common';

local fonts      = require 'fonts';
local primitives = require 'primitives';

local game = require 'lib.game';

local ui = { };

ui.text_registry = { };
ui.prim_registry = { };
ui.mouse_handlers = 0;

local OUTLINE_PADDING = 0.25;

--[[
* Windower hands 'visible' flags straight to lua_toboolean, so anything but nil/false means show.
* ImageBlock.new() passes the ImageBlock.visible *method* here (its data field is shadowed by that
* method), which Windower has always read as true, so the same truthiness is needed to keep the
* overlay on screen.
--]]
local function truthy(value)
    return (value ~= nil and value ~= false);
end

---Packs Windower's four colour components into Ashita's 0xAARRGGBB value.
---@param a number
---@param r number
---@param g number
---@param b number
---@return number
local function argb(a, r, g, b)
    return (math.floor(a or 255) * 0x1000000) +
           (math.floor(r or 255) * 0x10000) +
           (math.floor(g or 255) * 0x100) +
            math.floor(b or 255);
end

---------------------------------------------------------------------------
-- windower.text
---------------------------------------------------------------------------

local text = { };

function text.create(id)
    id = tostring(id);
    local entry = ui.text_registry[id];
    if (entry ~= nil) then
        return entry;
    end

    entry = { };
    entry.object   = fonts.new({ visible = false, auto_resize = true });
    entry.stroke   = 0;
    ui.text_registry[id] = entry;
    return entry;
end

function text.delete(id)
    local entry = ui.text_registry[tostring(id)];
    if (entry == nil) then return end
    if (entry.object.destroy ~= nil) then
        entry.object:destroy();
    end
    ui.text_registry[tostring(id)] = nil;
end

---Returns the entry, creating it on demand. Windower tolerates set_* calls on a fresh id and
---GearInfo's block text is written before some objects are created, so silently creating matches.
---@param id string
---@return table
local function need_text(id)
    return ui.text_registry[tostring(id)] or text.create(id);
end

function text.set_text(id, value)
    need_text(id).object.text = tostring(value);
end

function text.set_color(id, alpha, red, green, blue)
    need_text(id).object.color = argb(alpha, red, green, blue);
end

function text.set_location(id, x, y)
    local object = need_text(id).object;
    object.position_x = math.floor(x or 0);
    object.position_y = math.floor(y or 0);
end

function text.set_font(id, font, flags)
    local object = need_text(id).object;
    if (type(font) == 'string' and font ~= '') then
        object.font_family = font;
    end
    if (type(flags) == 'string') then
        object.bold = (flags:lower() == 'bold');
    end
end

function text.set_font_size(id, size)
    need_text(id).object.font_height = math.floor(tonumber(size) or 10);
end

function text.set_bold(id, bold)
    need_text(id).object.bold = (bold == true or bold == 1);
end

function text.set_visibility(id, visible)
    need_text(id).object.visible = truthy(visible);
end

function text.set_stroke_width(id, width)
    local entry = need_text(id);
    entry.stroke = tonumber(width) or 0;
    local flags = tonumber(entry.object.draw_flags) or 0;
    if (entry.stroke > 0) then
        entry.object.draw_flags = bit.bor(flags, FontDrawFlags.Outlined);
        entry.object.padding = entry.stroke * OUTLINE_PADDING;
    else
        entry.object.draw_flags = bit.band(flags, bit.bnot(FontDrawFlags.Outlined));
    end
end

function text.set_stroke_color(id, alpha, red, green, blue)
    need_text(id).object.color_outline = argb(alpha, red, green, blue);
end

---Windower returns the rendered width and height of the current text.
---@param id string
---@return number width
---@return number height
function text.get_extents(id)
    local entry = ui.text_registry[tostring(id)];
    if (entry == nil) then
        return 0, 0;
    end
    local width, height = entry.object:get_text_size();
    return tonumber(width) or 0, tonumber(height) or 0;
end

---Windower's text objects also answer to windower.text.get(id); only the presence is needed here.
function text.get(id)
    return ui.text_registry[tostring(id)];
end

ui.text = text;

---------------------------------------------------------------------------
-- windower.prim
---------------------------------------------------------------------------

local prim = { };

function prim.create(id)
    id = tostring(id);
    local entry = ui.prim_registry[id];
    if (entry ~= nil) then
        return entry;
    end

    entry = { };
    entry.object  = primitives.new({ visible = false });
    entry.fit     = false;
    ui.prim_registry[id] = entry;
    return entry;
end

function prim.delete(id)
    local entry = ui.prim_registry[tostring(id)];
    if (entry == nil) then return end
    if (entry.object.destroy ~= nil) then
        entry.object:destroy();
    end
    ui.prim_registry[tostring(id)] = nil;
end

local function need_prim(id)
    return ui.prim_registry[tostring(id)] or prim.create(id);
end

function prim.set_color(id, alpha, red, green, blue)
    need_prim(id).object.color = argb(alpha, red, green, blue);
end

function prim.set_texture(id, path)
    path = tostring(path or '');
    if (path == '') then
        return;
    end
    need_prim(id).object.texture = path;
end

function prim.set_fit_to_texture(id, fit)
    need_prim(id).fit = (fit == true or (tonumber(fit) or 0) ~= 0);
end

function prim.set_size(id, width, height)
    local object = need_prim(id).object;
    object.width = math.floor(tonumber(width) or 0);
    object.height = math.floor(tonumber(height) or 0);
end

function prim.set_position(id, x, y)
    local object = need_prim(id).object;
    object.position_x = math.floor(x or 0);
    object.position_y = math.floor(y or 0);
end

function prim.set_visibility(id, visible)
    need_prim(id).object.visible = truthy(visible);
end

function prim.set_alpha(id, alpha)
    local object = need_prim(id).object;
    local color = tonumber(object.color) or 0xFFFFFFFF;
    object.color = (math.floor(tonumber(alpha) or 255) * 0x1000000) + (color % 0x1000000);
end

function prim.get(id)
    return ui.prim_registry[tostring(id)];
end

ui.prim = prim;

---------------------------------------------------------------------------
-- Mouse input
---------------------------------------------------------------------------

--[[
* Windower reports type 0 (move), 1 (left press), 2 (left release), 3 (right press), 4 (right
* release), 5 (wheel) and hands the handler (type, x, y, delta, blocked). Returning true from the
* handler blocks the game, which Ashita does through the event's blocked flag.
--]]
local mouse_messages = {
    [0x200] = 0,
    [0x201] = 1,
    [0x202] = 2,
    [0x204] = 3,
    [0x205] = 4,
    [0x20A] = 5,
};

---Installs the Ashita event sources that feed the shim above.
---@param name string the Ashita event alias
function ui.install(name)
    if (ui.mouse_handlers > 0) then
        return;
    end
    ui.mouse_handlers = 1;

    ashita.events.register('mouse', (name or 'gearinfo') .. '_ui_mouse', function (e)
        local type = mouse_messages[tonumber(e.message) or 0];
        if (type == nil) then
            return;
        end

        local blocked = (e.blocked == true);
        -- GearInfo's handler only uses the move/press/release types, so the wheel delta is not read
        -- from the Ashita event.
        local result = game.dispatch('mouse', type, tonumber(e.x) or 0, tonumber(e.y) or 0, 0, blocked);
        if (result == true and not blocked) then
            e.blocked = true;
        end
    end);
end

---Removes every object the shim created, used when the addon unloads.
function ui.clear()
    for id in pairs(ui.text_registry) do
        text.delete(id);
    end
    for id in pairs(ui.prim_registry) do
        prim.delete(id);
    end
end

return ui;
