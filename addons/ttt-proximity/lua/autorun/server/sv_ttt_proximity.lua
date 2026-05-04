-- TTT Phoenix - Proximity Voice
-- Players only hear nearby living players. Spectators hear everyone.
-- Volume falls off linearly between PROX_FULL and PROX_MAX (in source units).
-- 1 metre ~= 39.37 source units. 50 m ~= 1968 units.

if not SERVER then return end

local PROX_FULL = 1200    -- ~30 m: full volume
local PROX_MAX  = 2400   -- ~60 m: silence
local DEAD_HEARS_DEAD = true

CreateConVar("ttt_proximity_voice", "1", { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Enable proximity-based voice chat (1/0)")
CreateConVar("ttt_proximity_full", tostring(PROX_FULL), { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Distance (units) at which voice is at full volume")
CreateConVar("ttt_proximity_max", tostring(PROX_MAX), { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Distance (units) at which voice fades to zero")

local function inRound()
    if not GetRoundState then return true end
    local s = GetRoundState()
    return s == ROUND_ACTIVE
end

hook.Add("PlayerCanHearPlayersVoice", "TTTPhoenix.Proximity",
    function(listener, talker)
        if not GetConVar("ttt_proximity_voice"):GetBool() then return end
        if not IsValid(listener) or not IsValid(talker) then return end
        if listener == talker then return true, false end

        -- Outside an active round: vanilla behaviour (TTT handles dead/alive separation).
        if not inRound() then return end

        local lAlive = listener:Alive() and not listener:IsSpec()
        local tAlive = talker:Alive()  and not talker:IsSpec()

        -- Spectators / dead always hear everyone (global, no falloff).
        if not lAlive then
            if tAlive then return true, false end
            return DEAD_HEARS_DEAD, false
        end

        -- Living listener can only hear living talker, with proximity falloff.
        if not tAlive then return false end

        local full = GetConVar("ttt_proximity_full"):GetFloat()
        local max  = GetConVar("ttt_proximity_max"):GetFloat()
        if max <= full then max = full + 1 end

        local d = listener:GetPos():Distance(talker:GetPos())
        if d >= max then return false end

        -- Use 3D positional voice; engine handles the actual falloff curve.
        return true, true
    end)
