--[[
* GearInfo (Ashita v4 port) - gearinfo.lua
*
* Bootstrap for the port. Windower loaded every file of an addon into one shared global environment,
* so GearInfo's helpers, caches and settings were plain globals visible to all of them. Ashita gives
* each required module its own environment, so this file builds the shared one (lib/include.lua),
* fills in the values the original addon's `require` lines produced, then runs the logic files inside
* it - including logic/Entry.lua, which is the original GearInfo.lua body.
*
* The logic files are the upstream Windower addon at version 1.7.2.10; only lib/ holds port code, so
* re-basing onto a newer upstream release is a plain three-way merge of logic/ and leaves this alone.
*
* Nothing in here is GearInfo logic; each lib module owns one piece of the Windower api:
*   lib/game.lua       windower.ffxi / windower.add_to_chat / register_event + the Ashita event bridge
*   lib/packets.lua    packet history ring and the 0x0028 -> 'action' decoder
*   lib/resources.lua  the res.* tables on AshitaCore:GetResourceManager()
*   lib/extdata.lua    item extension data (augments) decoding
*   lib/ui.lua         windower.text / windower.prim / mouse on Ashita's fonts + primitives
*   lib/config.lua     windower's config.load()/settings:save()
*   lib/files.lua      windower's files.exists()/files.new()
*   lib/compat.lua     the table/string helpers the ported code still calls
--]]

require 'common';

local chat = require 'chat';

local compat    = require 'lib.compat';
local include   = require 'lib.include';
local game      = require 'lib.game';
local ui        = require 'lib.ui';
local config    = require 'lib.config';
local files     = require 'lib.files';
local extdata   = require 'lib.extdata';
local resources = require 'lib.resources';
local chars     = require 'lib.chars';

addon.name      = 'GearInfo';
addon.author    = 'Sebyg666';
addon.version   = '1.7.2.10';
addon.desc      = 'Displays the haste, TP, accuracy, attack, evasion, defence and damage taken your gear is worth.';
addon.link      = 'https://www.ashitaxi.com/';

compat.install();

-- windower.text/windower.prim keep the ids the ported overlay code uses.
local windower = _G.windower;
windower.text = ui.text;
windower.prim = ui.prim;

include.root = addon.path;

local env = include.env;

-- The original `_addon` descriptor. Windower pre-injected that table and GearInfo only filled in four
-- fields; nothing reads them, but the assignment is kept so the file still matches upstream's opening.
env._addon = T{
    name     = 'GearInfo',
    author   = 'Sebyg666',
    version  = addon.version,
    commands = T{ 'gi', 'gearinfo' },
};

env.res     = resources;
env.Extdata = extdata;
env.chat    = chat;
env.chars   = chars;
env.config  = config;
env.files   = files;
-- The logic files reach lib/game.lua's manual store (merits, job point gifts, blue magic set) through
-- this name; the '/gi merit', '/gi jp' and '/gi blu' commands write it.
env.game    = game;

-- Gear data tables, loaded as data (not through the shared environment) exactly like require() was.
env.DW_Gear             = include.read('res\\DW_Gear.lua');
env.Unity_rank          = include.read('res\\Unity_Gear.lua');
env.Martial_Arts_Gear   = include.read('res\\Martial_Arts_Gear.lua');
env.Set_bonus_by_Set_ID  = include.read('res\\Set_bonus_by_Set_ID.lua');
env.Set_bonus_by_item_id = include.read('res\\Set_bonus_by_item_id.lua');
env.Blu_spells          = include.read('res\\Blue_Mage_Spells.lua');
env.Gifts               = include.read('res\\Gifts.lua');
env.Cor_Rolls           = include.read('res\\Cor_Rolls.lua');
env.Bard_Songs          = include.read('res\\Bard_Songs.lua');
env.Geo_Spells          = include.read('res\\Geo_Spells.lua');

-- Windower's logger printed to the game chat log, so the shared environment keeps that behaviour.
-- notice()/log() come from lib/compat.lua and already route there.
env.print = function (...)
    local args = { ... };
    for i = 1, #args do args[i] = tostring(args[i]) end
    windower.add_to_chat(1, table.concat(args, ' '));
end;

-- Logic files first, in the order the original addon required them, with the entry body last.
include.all({
    'logic\\Statics.lua',
    'logic\\Gear_Processing.lua',
    'logic\\Calculator.lua',
    'logic\\Action_Processing.lua',
    'logic\\Buff_Processing.lua',
    'logic\\Packet_parsing.lua',
    'logic\\Image_processing.lua',
    'logic\\Entry.lua',
});

-- Registers the Ashita events that raise the Windower event names the ported handlers listen for.
ui.install('gearinfo');
game.bind_events('gearinfo');

--[[
* event: unload
* desc : Called when the addon is unloaded; releases every font and primitive the ui shim created.
--]]
ashita.events.register('unload', 'gearinfo_bootstrap_unload_cb', function ()
    ui.clear();
end);
