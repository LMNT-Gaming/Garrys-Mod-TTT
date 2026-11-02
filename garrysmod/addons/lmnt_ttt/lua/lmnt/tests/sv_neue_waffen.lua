-- LMNT Unit-Tests: neue LMNT-Waffen (Registry-Metadaten, TTT2-Kompatibilität, Kaufrollen, Boden-Spawn)
-- Liest nur (weapons.GetStored, LMNT.Weapons.Get/Check), verändert weder Waffen noch Einstellungen.
local T = LMNT.Test

if not (LMNT.Weapons and LMNT.Weapons.Check and LMNT.Weapons._registry) then
	T.Describe("Neue Waffen", function(t)
		t:It("Modul ttt.shop ist geladen", function(e)
			e:True(false, "LMNT.Weapons fehlt – Modul ttt.shop ist aus oder nicht gestartet (!modules)")
		end)
	end)
	return
end

local W = LMNT.Weapons

-- erwartete Kaufrolle je Klasse (nil = nicht kaufbar, Boden-Spawn)
local EXPECTED = {
	weapon_lmnt_naeherungsmine = { role = ROLE_TRAITOR, category = "Gerät" },
	weapon_lmnt_giftgas = { role = ROLE_TRAITOR, category = "Granate" },
	weapon_lmnt_wurfmesser = { role = ROLE_TRAITOR, category = "Nahkampf" },
	weapon_lmnt_schutzbarriere = { role = ROLE_DETECTIVE, category = "Gerät" },
	weapon_lmnt_bewegungsmelder = { role = ROLE_DETECTIVE, category = "Gerät" },
	weapon_lmnt_pumpgun = { role = nil, category = "Schrot" },
}

local CLASSES = table.GetKeys(EXPECTED)
table.sort(CLASSES)

local function roleName(index)
	local role = roles and roles.GetByIndex and roles.GetByIndex(index)
	return role and role.name or nil
end

T.Describe("Neue Waffen · Kompatibilität", function(t)
	for _, class in ipairs(CLASSES) do
		t:It(class .. " ist TTT2-tauglich", function(e)
			local status, checks = W.Check(class)
			local failed = {}
			for _, c in ipairs(checks) do
				if not c.ok then failed[#failed + 1] = c.name end
			end
			e:Equal(status, "ttt2", class .. " (fehlt: " .. table.concat(failed, ", ") .. ")")
		end)
	end
end)

T.Describe("Neue Waffen · Metadaten", function(t)
	for _, class in ipairs(CLASSES) do
		t:It(class .. " ist registriert", function(e)
			local meta = W._registry[class]
			e:True(meta, "Metadaten registriert")
			e:Equal(meta.sourceAddon, "lmnt_ttt", "sourceAddon")
			e:Equal(meta.category, EXPECTED[class].category, "Kategorie")
			e:True(meta.description ~= "", "Beschreibung vorhanden")
		end)
	end

	t:It("Näherungsmine hat eine Sperrzeit ab Rundenbeginn", function(e)
		local meta = W._registry.weapon_lmnt_naeherungsmine
		e:True(meta and meta.shopDefaults.lockSeconds > 0, "lockSeconds > 0")
		e:Equal(meta.shopDefaults.maxPerRound, 1, "maxPerRound")
	end)
end)

T.Describe("Neue Waffen · Kaufrollen", function(t)
	local traitor, detective = roleName(ROLE_TRAITOR), roleName(ROLE_DETECTIVE)

	t:It("TTT2-Rollen traitor und detective sind bekannt", function(e)
		e:True(traitor, "ROLE_TRAITOR")
		e:True(detective, "ROLE_DETECTIVE")
	end)

	for _, class in ipairs(CLASSES) do
		local expected = EXPECTED[class].role
		t:It(class .. " CanBuy: " .. (expected and tostring(roleName(expected)) or "nicht kaufbar"), function(e)
			local view = W.Get(class)
			e:True(view.ttt2, "TTT2-Werte gelesen")
			local set = {}
			for _, name in ipairs(view.ttt2.roles) do set[name] = true end

			if expected then
				local other = expected == ROLE_TRAITOR and ROLE_DETECTIVE or ROLE_TRAITOR
				local list = " (Rollen: " .. table.concat(view.ttt2.roles, ", ") .. ")"
				e:True(set[roleName(expected)], "kaufbar für " .. tostring(roleName(expected)) .. list)
				e:False(set[roleName(other)], "nicht kaufbar für " .. tostring(roleName(other)) .. list)
				local stored = weapons.GetStored(class)
				e:True(stored.LimitedStock == true, "LimitedStock")
				e:True(isnumber(stored.Kind) and stored.Kind == WEAPON_EQUIP, "Kind = Ausrüstung")
			else
				e:Equal(#view.ttt2.roles, 0, "keine Kaufrolle")
			end
		end)
	end

	t:It("Pumpgun spawnt am Boden mit vorhandener Munition", function(e)
		local stored = weapons.GetStored("weapon_lmnt_pumpgun")
		e:True(stored.AutoSpawnable == true, "AutoSpawnable")
		e:Equal(stored.Kind, WEAPON_HEAVY, "Kind")
		e:Equal(stored.AmmoEnt, "item_box_buckshot_ttt", "AmmoEnt")
		e:True(scripted_ents.GetStored(stored.AmmoEnt) ~= nil, "Munitions-Entity geladen")
		e:Equal(stored.Primary.Ammo, "Buckshot", "Munitionstyp")
		e:True(game.GetAmmoID("Buckshot") ~= -1, "Munitionstyp registriert")
	end)
end)

T.Describe("Neue Waffen · Entities", function(t)
	local ENTS = { "lmnt_naeherungsmine", "lmnt_giftgas_proj", "lmnt_wurfmesser_proj", "lmnt_schutzbarriere", "lmnt_bewegungsmelder" }
	for _, class in ipairs(ENTS) do
		t:It(class .. " ist geladen", function(e)
			e:True(scripted_ents.GetStored(class) ~= nil, class)
		end)
	end
end)
