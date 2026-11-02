-- LMNT-Skin für die TTT2-Menüs (F1-Menü, Shop-Editor, Einstellungen …)
-- Format wie lua/terrortown/vskin/dark.lua aus TTT2 0.14.6b; Farben = LMNT-Marken-Tokens.
vskin.RegisterVSkin("lmnt_ttt2", {
	colors = {
		background  = Color(17, 16, 24, 255),   -- ink-soft
		accent      = Color(255, 49, 49, 255),  -- acid
		accent_dark = Color(168, 0, 22, 255),   -- violet (Dunkelrot)
		scroll      = Color(28, 26, 37, 255),
		shadow      = Color(0, 0, 0, 140),
		screen      = Color(8, 7, 12, 215),     -- ink
		title_text  = Color(255, 253, 248, 255),
	},
	params = {
		shadow_size = 4,
		header_height = 45,
		collapsable_height = 30,
		border_size = 3,
		corner_radius = 6,
	},
})
