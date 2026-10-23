MONO = SMODS.current_mod

SMODS.Atlas({
	key = "modicon",
	path = "mono_icon.png",
	px = 34,
	py = 34,
})

assert(SMODS.load_file("src/fusion.lua"))()
assert(SMODS.load_file("src/fused_draw.lua"))()
assert(SMODS.load_file("src/zap.lua"))()
assert(SMODS.load_file("src/static_deck.lua"))()
