--- @ignore
--[[
	LMNT-HUD – Mini-Scoreboard-Leiste (Typ tttminiscoreboard), Kind von lmnt_roundinfo, rechts daneben

	Logik übernommen aus pure_skin_miniscoreboard (eigene Spielerliste nötig, die dortige ist dateilokal):
	alle Spieler mit WasActiveInRound(), zwei Reihen, bestätigte zuerst, Neusortierung bei
	ttt2net-Änderungen an body_found/role_found/t_first_found/t_last_found, Liste alle 0,1 s geprüft.
	Muss neben lmnt_roundinfo existieren (siehe lmnt_teamindicator).

	Sichtbarkeit (wie pure_skin): Rollenfarbe nur, wenn die Leiche gefunden wurde (OnceFound) und die
	Rolle bekannt ist (HasRole), sonst "indirekt bestätigt" oder neutral. Der TTT2-Hook
	TTT2ModifyMiniscoreboardColor(ply, farbe) wird weiterhin gefragt.
]]

local base = "pure_skin_element"

DEFINE_BASECLASS(base)

HUDELEMENT.Base = base

HUDELEMENT.togglable = true
HUDELEMENT.disabledUnlessForced = true

if not CLIENT then return end

local D -- Zeichner (lmnt_element)

local MARGIN = 8
local ELEMENT_MARGIN = 4
local ROWS = 2

local icon_in_conf = Material("vgui/ttt/indirect_confirmed")
local icon_revived = Material("vgui/ttt/revived")

-- TTT2-Bedeutung "indirekt bestätigt" (pure_skin: 215, 215, 215)
local color_indirconfirm = Color(215, 215, 215, 200)

local const_defaults = {
	basepos = { x = 0, y = 0 },
	size = { w = 72, h = 72 },
	minsize = { w = 0, h = 0 },
}

local plysList = {}
local sortRegistered = false

-- Kopie je Rollenfarbe mit eigenem Alpha, damit nicht pro Frame Color() entsteht.
-- Schwache Schlüssel: verschwindet eine Rollenfarbe, verschwindet auch die Kopie.
local roleColorCache = setmetatable({}, { __mode = "k" })

local function wasActive(ply)
	return ply:WasActiveInRound()
end

-- wie pure_skin_miniscoreboard: bestätigte Spieler zuerst, in der Reihenfolge der Bestätigung
local function sortFunc(a, b)
	if not IsValid(a) or not a:OnceFound() then
		return false
	end

	if IsValid(b) and b:OnceFound() and a:GetFirstFound() >= b:GetFirstFound() then
		return false
	end

	return true
end

local refreshPaths = {
	["t_first_found"] = true,
	["t_last_found"] = true,
	["role_found"] = true,
	["body_found"] = true,
}

function HUDELEMENT:PreInitialize()
	hudelements.RegisterChildRelation(self.id, "lmnt_roundinfo", false)

	-- PreInitialize läuft bei jedem hudelements.OnLoaded (auch nach Auto-Refresh), Callback nur einmal
	if sortRegistered then return end
	sortRegistered = true

	ttt2net.OnUpdate("players", function(_, _, reversePath)
		if not refreshPaths[reversePath[2]] then return end

		table.sort(plysList, sortFunc)
	end)
end

function HUDELEMENT:Initialize()
	self.parentInstance = hudelements.GetStored(self.parent)
	self.scale = 1.0
	self.basecolor = self:GetHUDBasecolor()
	self.margin = MARGIN
	self.element_margin = ELEMENT_MARGIN
	self.ply_ind_size = 0
	self.column_count = 0

	plysList = util.GetFilteredPlayers(wasActive)
	self.curPlayerCount = #plysList

	table.sort(plysList, sortFunc)

	self.lastUpdate = CurTime()

	BaseClass.Initialize(self)
end

-- wie pure_skin_miniscoreboard
function HUDELEMENT:ShouldDraw()
	return gameloop.GetRoundState() == ROUND_ACTIVE
end

function HUDELEMENT:InheritParentBorder()
	return true
end

function HUDELEMENT:GetDefaults()
	return const_defaults
end

---
-- Position und Größe folgen dem Elternelement (rechts daneben, gleiche Höhe)
-- @realm client
function HUDELEMENT:PerformLayout()
	local parent_pos = self.parentInstance:GetPos()
	local parent_size = self.parentInstance:GetSize()
	local parent_defaults = self.parentInstance:GetDefaults()
	local h = parent_size.h

	self.basecolor = self:GetHUDBasecolor()
	self.scale = h / parent_defaults.size.h
	self.margin = MARGIN * self.scale
	self.element_margin = ELEMENT_MARGIN * self.scale
	self.ply_ind_size = math.Round((h - self.element_margin - self.margin * 2) * 0.5)
	self.column_count = math.Round(self.curPlayerCount * 0.5)

	local w = self.element_margin * (self.column_count - 1) + self.ply_ind_size * self.column_count + 2 * self.margin

	self:SetPos(parent_pos.x + parent_size.w, parent_pos.y)
	self:SetSize(w, h)

	BaseClass.PerformLayout(self)
end

local function colorFor(ply, C)
	local color = C.raised -- noch nicht gefunden

	if ply:OnceFound() then
		if ply:HasRole() then
			local rc = ply:GetRoleColor()

			color = roleColorCache[rc]
			if not color then
				color = Color(rc.r, rc.g, rc.b, 230)
				roleColorCache[rc] = color
			end
		else
			color = color_indirconfirm
		end
	end

	---
	-- @realm client
	return hook.Run("TTT2ModifyMiniscoreboardColor", ply, color) or color
end

function HUDELEMENT:Draw()
	D = D or hudelements.GetStored("lmnt_element")

	local C = D:Colors()

	-- Spielerliste nur alle 0,1 s prüfen (wie pure_skin)
	if self.lastUpdate + 0.1 < CurTime() then
		local plys = util.GetFilteredPlayers(wasActive)

		if #plys ~= self.curPlayerCount then
			plysList = plys
			self.curPlayerCount = #plys

			self:PerformLayout()

			table.sort(plysList, sortFunc)
		end

		self.lastUpdate = CurTime()
	end

	local x, y = self.pos.x, self.pos.y

	D:Panel(x, y, self.size.w, self.size.h, self.basecolor)

	local size = self.ply_ind_size
	local step = self.element_margin + size

	for i = 1, self.curPlayerCount do
		local ply = plysList[i]
		local px = x + self.margin + step * math.floor((i - 1) / ROWS)
		local py = y + self.margin + step * ((i - 1) % ROWS)

		if IsValid(ply) then
			D:Rect(px, py, size, size, colorFor(ply, C))

			if ply:WasRevivedAndConfirmed() then
				draw.FilteredTexture(px + 3, py + 3, size - 6, size - 6, icon_revived, 180, COLOR_BLACK)
			elseif ply:OnceFound() and not ply:RoleKnown() then
				draw.FilteredTexture(px + 3, py + 3, size - 6, size - 6, icon_in_conf, 120, COLOR_BLACK)
			end
		else
			D:Rect(px, py, size, size, C.raised)
		end

		D:Outline(px, py, size, size)
	end
end
