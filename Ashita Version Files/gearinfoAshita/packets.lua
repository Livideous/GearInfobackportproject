--[[
    Only two incoming packets are still needed:
      0x061  character stats (base STR..CHR)
      0x062  skills
    Offsets are the same 1-based offsets the Windower version passed to data:unpack().
    Note: stats/skills arrive when the server sends them (zone, equip change, etc.). There is no
    "last packet" cache in Ashita, so after loading mid-session change gear (or zone) once to populate them.
]]--

parse_in = {}

parse_in[0x061] = function(e)
    local d = e.data
    player.stats = {
        STR = struct.unpack('H', d, 0x15),
        DEX = struct.unpack('H', d, 0x17),
        VIT = struct.unpack('H', d, 0x19),
        AGI = struct.unpack('H', d, 0x1B),
        INT = struct.unpack('H', d, 0x1D),
        MND = struct.unpack('H', d, 0x1F),
        CHR = struct.unpack('H', d, 0x21),
    }
end

parse_in[0x062] = function(e)
    local d = e.data
    for i = 1, 0x71, 2 do
        local skill = struct.unpack('H', d, i + 0x82) % 32768
        local api = SKILL_API[math.floor(i / 2) + 1]
        if api then player.skills[api] = skill end
    end
    check_equipped()
    compute_base_skills()
end
