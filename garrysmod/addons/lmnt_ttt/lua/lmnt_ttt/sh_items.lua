--[[
	LMNT TTT – Wirkung der passiven Shop-Items
	Die Items selbst liegen unter lua/terrortown/entities/items/.
]]

-- Turbo-Schuhe: +25 % Laufgeschwindigkeit
LMNT.TTT.AddSpeedModifier("item_lmnt_turbo", function(ply)
	if ply.HasEquipmentItem and ply:HasEquipmentItem("item_lmnt_turbo") then return 1.25 end
end)

if CLIENT then return end

-- Fallschutz: kein Fallschaden
hook.Add("EntityTakeDamage", "LMNT.TTT.Fallschutz", function(ent, dmg)
	if ent:IsPlayer() and dmg:IsFallDamage() and ent:HasEquipmentItem("item_lmnt_fallschutz") then
		return true
	end
end)

-- Regeneration: +1 HP alle 2 Sekunden bis zum Maximum
timer.Create("LMNT.TTT.Regeneration", 2, 0, function()
	if GetRoundState() ~= ROUND_ACTIVE then return end

	for _, ply in ipairs(player.GetAll()) do
		if ply:Alive() and ply:HasEquipmentItem("item_lmnt_regeneration") and ply:Health() < ply:GetMaxHealth() then
			ply:SetHealth(ply:Health() + 1)
		end
	end
end)
