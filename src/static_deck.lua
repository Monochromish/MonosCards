SMODS.Atlas({
	key = "backs",
	path = "mono_backs.png",
	px = 71,
	py = 95,
})

SMODS.Back({
	key = "static",
	atlas = "backs",
	pos = { x = 0, y = 0 },
	config = { consumables = { "c_mono_zap" } },
	loc_vars = function(self, info_queue, back)
		return { vars = {} }
	end,
})
