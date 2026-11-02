--[[
	LMNT TTT – Spezialrunden (Definitionen)

	Neue Runde hinzufügen:
	  LMNT.TTT.AddSpecial({
		id = "meinerunde", name = "Anzeigename", desc = "Kurzbeschreibung", color = Color(...),
		weight = 10,                    -- relative Häufigkeit
		start = function() end,         -- Server: Rundenstart
		stop  = function() end,         -- Server: Rundenende
		speed = 1.4,                    -- optional: Laufgeschwindigkeit
	  })
	Für Schaden & Co. eigene Hooks mit LMNT.TTT.IsSpecial("meinerunde") prüfen.
]]

LMNT.TTT.Specials = {}

function LMNT.TTT.AddSpecial(data)
	data.weight = data.weight or 10
	LMNT.TTT.Specials[data.id] = data
end

function LMNT.TTT.GetSpecial()
	local id = GetGlobalString("lmnt_special", "")
	return id ~= "" and LMNT.TTT.Specials[id] or nil
end

function LMNT.TTT.IsSpecial(id)
	return GetGlobalString("lmnt_special", "") == id
end

LMNT.Settings.Define("ttt.special.chance", {
	type = "number", default = 0.2, min = 0, max = 1, category = "Spezialrunden", applies = "nextround",
	desc = "Wahrscheinlichkeit pro Runde für eine Spezialrunde (0–1)",
})
LMNT.Settings.Define("ttt.special.min_players", {
	type = "int", default = 4, min = 1, max = 64, category = "Spezialrunden", applies = "nextround",
	desc = "Mindestspielerzahl für Spezialrunden",
})
LMNT.Settings.Define("ttt.special.min_gap", {
	type = "int", default = 2, min = 0, max = 20, category = "Spezialrunden", applies = "nextround",
	desc = "Mindestens so viele normale Runden zwischen zwei Spezialrunden",
})

LMNT.Admin.AddCommand("special", {
	perm = "special",
	help = "Legt die Spezialrunde für die nächste Runde fest (ohne Angabe: Liste)",
	args = { { type = "string", name = "id", optional = true } },
	run = function(caller, id)
		local col = LMNT.Config.Colors
		if not id or not LMNT.TTT.Specials[id] then
			LMNT.Reply(caller, col.primary, "Verfügbare Spezialrunden:")
			for sid, s in pairs(LMNT.TTT.Specials) do
				LMNT.Reply(caller, s.color, sid, color_white, " – " .. s.name .. ": " .. s.desc)
			end
			return
		end
		LMNT.TTT.ForceSpecial(id)
		LMNT.Admin.Broadcast(caller, "hat für die nächste Runde die Spezialrunde", LMNT.TTT.Specials[id].name, " angesetzt")
	end,
})

LMNT.TTT.AddSpeedModifier("specialround", function()
	local special = LMNT.TTT.GetSpecial()
	return special and special.speed or nil
end)

------------------------------------------------------------------------

local oldGravity

LMNT.TTT.AddSpecial({
	id = "mond", name = "Mondlandung", color = Color(130, 170, 255),
	desc = "Niedrige Schwerkraft – springt euch die Seele aus dem Leib!",
	start = function()
		oldGravity = GetConVar("sv_gravity"):GetString()
		RunConsoleCommand("sv_gravity", "220")
	end,
	stop = function()
		RunConsoleCommand("sv_gravity", oldGravity or "600")
	end,
})

LMNT.TTT.AddSpecial({
	id = "turbo", name = "Turbo-Runde", color = Color(255, 200, 60),
	desc = "Alle laufen 40 % schneller.",
	speed = 1.4,
})

LMNT.TTT.AddSpecial({
	id = "kopfjaeger", name = "Kopfjäger", color = Color(255, 90, 90),
	desc = "Kopftreffer machen 50 % mehr Schaden, alles andere nur 40 %.",
})

LMNT.TTT.AddSpecial({
	id = "vampir", name = "Vampirnacht", color = Color(180, 30, 60),
	desc = "30 % deines verursachten Schadens heilen dich.",
})

LMNT.TTT.AddSpecial({
	id = "schwarzmarkt", name = "Schwarzmarkt", color = Color(90, 210, 130),
	desc = "Traitor und Detektive erhalten 2 zusätzliche Credits.",
	start = function()
		for _, ply in ipairs(player.GetAll()) do
			if ply:Alive() and ply.AddCredits and (ply:IsTraitor() or ply:IsDetective()) then
				ply:AddCredits(2)
			end
		end
	end,
})

LMNT.TTT.AddSpecial({
	id = "kettenreaktion", name = "Kettenreaktion", color = Color(255, 130, 30),
	desc = "Leichen explodieren 3 Sekunden nach dem Tod!",
	weight = 6,
})

local function setHeads(scale)
	for _, ply in ipairs(player.GetAll()) do
		local bone = ply:LookupBone("ValveBiped.Bip01_Head1")
		if bone then ply:ManipulateBoneScale(bone, Vector(scale, scale, scale)) end
	end
end

LMNT.TTT.AddSpecial({
	id = "wackelkopf", name = "Wackelköpfe", color = Color(255, 80, 170),
	desc = "Riesige Köpfe für alle (nur optisch).",
	start = function() setHeads(2.2) end,
	stop = function() setHeads(1) end,
})

------------------------------------------------------------------------
-- Wirkungen, die Hooks brauchen (Server)
------------------------------------------------------------------------

if CLIENT then return end

hook.Add("ScalePlayerDamage", "LMNT.Special.Kopfjaeger", function(_, hitgroup, dmg)
	if not LMNT.TTT.IsSpecial("kopfjaeger") then return end
	dmg:ScaleDamage(hitgroup == HITGROUP_HEAD and 1.5 or 0.4)
end)

hook.Add("PostEntityTakeDamage", "LMNT.Special.Vampir", function(ent, dmg, took)
	if not took or not LMNT.TTT.IsSpecial("vampir") or not ent:IsPlayer() then return end

	local attacker = dmg:GetAttacker()
	if not IsValid(attacker) or not attacker:IsPlayer() or attacker == ent or not attacker:Alive() then return end

	local heal = math.floor(dmg:GetDamage() * 0.3)
	attacker:SetHealth(math.min(attacker:GetMaxHealth(), attacker:Health() + heal))
end)

hook.Add("PlayerDeath", "LMNT.Special.Kettenreaktion", function(victim)
	if not LMNT.TTT.IsSpecial("kettenreaktion") then return end

	local fallback = victim:GetPos()
	timer.Simple(0.1, function()
		local rag = IsValid(victim) and victim.server_ragdoll
		local tracked = IsValid(rag) and rag or nil

		timer.Simple(2.9, function()
			if not LMNT.TTT.IsSpecial("kettenreaktion") then return end
			local pos = IsValid(tracked) and tracked:GetPos() or fallback

			local ed = EffectData()
			ed:SetOrigin(pos)
			util.Effect("Explosion", ed)
			util.BlastDamage(game.GetWorld(), game.GetWorld(), pos, 220, 45)
		end)
	end)
end)

hook.Add("PlayerSpawn", "LMNT.Special.Wackelkopf", function(ply)
	if not LMNT.TTT.IsSpecial("wackelkopf") then return end

	timer.Simple(0.2, function()
		if not IsValid(ply) then return end
		local bone = ply:LookupBone("ValveBiped.Bip01_Head1")
		if bone then ply:ManipulateBoneScale(bone, Vector(2.2, 2.2, 2.2)) end
	end)
end)
