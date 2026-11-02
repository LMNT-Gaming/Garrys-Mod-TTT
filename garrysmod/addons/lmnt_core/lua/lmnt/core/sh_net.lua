--[[
	LMNT Framework – Chat-Nachrichten und Bildschirm-Ankündigungen

	Server:
	  LMNT.Notify(ziel, ...)     farbige Chatnachricht (ziel = nil -> alle, Spieler oder Tabelle)
	  LMNT.Reply(caller, ...)    an Spieler oder – bei der Konsole – in die Serverkonsole
	  LMNT.Announce(text, farbe, sekunden)   große Einblendung bei allen
]]

local TYPE_STRING, TYPE_COLOR, TYPE_PLAYER = 0, 1, 2

if SERVER then
	util.AddNetworkString("lmnt_chat")
	util.AddNetworkString("lmnt_announce")

	local function printConsole(args)
		local out = { LMNT.Config.Colors.primary, "[" .. LMNT.Config.Prefix .. "] ", color_white }

		for _, v in ipairs(args) do
			if IsColor(v) then
				out[#out + 1] = v
			elseif isentity(v) and IsValid(v) and v:IsPlayer() then
				out[#out + 1] = v:Nick()
			else
				out[#out + 1] = tostring(v)
			end
		end

		out[#out + 1] = "\n"
		MsgC(unpack(out))
	end

	function LMNT.Notify(targets, ...)
		local args = { ... }

		if targets ~= nil and not istable(targets) and not IsValid(targets) then
			printConsole(args)
			return
		end

		net.Start("lmnt_chat")
		net.WriteUInt(#args, 8)

		for _, v in ipairs(args) do
			if IsColor(v) then
				net.WriteUInt(TYPE_COLOR, 2)
				net.WriteColor(v)
			elseif isentity(v) and IsValid(v) and v:IsPlayer() then
				net.WriteUInt(TYPE_PLAYER, 2)
				net.WriteEntity(v)
			else
				net.WriteUInt(TYPE_STRING, 2)
				net.WriteString(tostring(v))
			end
		end

		if targets == nil then
			net.Broadcast()
		else
			net.Send(targets)
		end
	end

	function LMNT.Reply(caller, ...)
		LMNT.Notify(IsValid(caller) and caller or NULL, ...)
	end

	function LMNT.Announce(text, color, seconds)
		net.Start("lmnt_announce")
		net.WriteString(text)
		net.WriteColor(color or LMNT.Config.Colors.primary)
		net.WriteFloat(seconds or 6)
		net.Broadcast()
	end
else
	net.Receive("lmnt_chat", function()
		local out = { LMNT.Config.Colors.primary, "[" .. LMNT.Config.Prefix .. "] ", color_white }

		for _ = 1, net.ReadUInt(8) do
			local kind = net.ReadUInt(2)

			if kind == TYPE_COLOR then
				out[#out + 1] = net.ReadColor()
			elseif kind == TYPE_PLAYER then
				local ply = net.ReadEntity()
				local rank = IsValid(ply) and LMNT.GetRank and LMNT.GetRank(ply:GetUserGroup())

				out[#out + 1] = rank and rank.color or color_white
				out[#out + 1] = IsValid(ply) and ply:Nick() or "Unbekannt"
				out[#out + 1] = color_white
			else
				out[#out + 1] = net.ReadString()
			end
		end

		chat.AddText(unpack(out))
	end)
end
