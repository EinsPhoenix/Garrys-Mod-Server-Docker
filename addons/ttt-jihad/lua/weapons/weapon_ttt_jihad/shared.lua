-- TTT Phoenix Jihad Bomb. Self-contained traitor equipment using
-- built-in Source assets (no workshop dependency).

if SERVER then
    AddCSLuaFile("shared.lua")
end

SWEP.HoldType = "slam"

if CLIENT then
    SWEP.PrintName = "Jihad Bomb"
    SWEP.Slot      = 7
    SWEP.SlotPos   = 1

    SWEP.ViewModelFOV = 54

    SWEP.EquipMenuData = {
        type = "item_weapon",
        name = "Jihad Bomb",
        desc = "Press Left Mouse to start a 3 second countdown.\nDetonates a powerful explosion. You die. Everyone nearby dies."
    }

    SWEP.Icon = "vgui/ttt/icon_c4"
end

SWEP.Base = "weapon_tttbase"

SWEP.Kind         = WEAPON_EQUIP
SWEP.CanBuy       = { ROLE_TRAITOR }
SWEP.LimitedStock = true
SWEP.AllowDrop    = false
SWEP.WeaponID     = AMMO_C4

SWEP.ViewModel  = "models/weapons/v_c4.mdl"
SWEP.WorldModel = "models/weapons/w_c4.mdl"

SWEP.DrawCrosshair          = false
SWEP.ViewModelFlip          = false

SWEP.Primary.ClipSize       = -1
SWEP.Primary.DefaultClip    = -1
SWEP.Primary.Automatic      = false
SWEP.Primary.Ammo           = "none"
SWEP.Primary.Delay          = 5.0

SWEP.Secondary.ClipSize     = -1
SWEP.Secondary.DefaultClip  = -1
SWEP.Secondary.Automatic    = false
SWEP.Secondary.Ammo         = "none"

SWEP.NoSights = true

local DETONATION_TIME = 5
local EXPLOSION_MAGNITUDE = 250
-- ~50 m audible radius. Source uses SNDLVL_dB; 90 dB carries roughly that
-- far. Pitch 100 = unaltered. The sound is forced-downloaded to clients
-- via lua/autorun/ttt_jihad_resource.lua.
local WARNING_SOUND = "ttt_jihad/wth.mp3"
local WARNING_SNDLVL = 90

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:Reload() end
function SWEP:Think() end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + DETONATION_TIME + 1)

    if not IsValid(self.Owner) then return end

    self.BaseClass.ShootEffects(self)

    if SERVER then
        local owner = self.Owner
        -- Position-attached emit so every player within ~50 m hears it.
        owner:EmitSound(WARNING_SOUND, WARNING_SNDLVL, 100, 1, CHAN_VOICE)

        timer.Simple(DETONATION_TIME, function()
            if not IsValid(self) then return end
            if not IsValid(owner) then return end
            self:Detonate(owner)
        end)
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 1)
end

if SERVER then
    function SWEP:Detonate(owner)
        if not IsValid(owner) then return end

        local pos = owner:GetPos()
        local ent = ents.Create("env_explosion")
        if not IsValid(ent) then return end

        ent:SetPos(pos)
        ent:SetOwner(owner)
        ent:SetKeyValue("iMagnitude", tostring(EXPLOSION_MAGNITUDE))
        ent:Spawn()
        ent:Fire("Explode", 0, 0)
        ent:EmitSound("ambient/explosions/explode_4.wav", 500, 100)

        if IsValid(self) then
            self:Remove()
        end
    end
end
