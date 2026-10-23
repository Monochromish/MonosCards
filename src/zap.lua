SMODS.Atlas({
	key = "spectrals",
	path = "mono_spectral.png",
	px = 71,
	py = 95,
})

-- same odds as the soul
SMODS.Consumable({
	key = "zap",
	set = "Spectral",
	atlas = "spectrals",
	pos = { x = 0, y = 0 },
	soul_pos = { x = 1, y = 0 },
	hidden = true,
	soul_set = "Tarot",
	soul_rate = 0.003,
	cost = 4,
	loc_vars = function(self, info_queue, card)
		info_queue[#info_queue + 1] = { key = "mono_fused", set = "Other" }
		return { vars = {} }
	end,
	can_use = function(self, card)
		return #MONO.Fusion.fusable_jokers() >= 2
	end,
	use = function(self, card, area, copier)
		local F = MONO.Fusion
		local pool = F.fusable_jokers()
		local first, first_idx = pseudorandom_element(pool, pseudoseed("mono_zap"))
		table.remove(pool, first_idx)
		local second = pseudorandom_element(pool, pseudoseed("mono_zap"))
		local host, partner = F.choose_host(first, second)

		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.4,
			func = function()
				play_sound("tarot1")
				card:juice_up(0.3, 0.5)
				return true
			end,
		}))
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.2,
			func = function()
				host:juice_up(0.3, 0.4)
				partner:juice_up(0.3, 0.4)
				play_sound("explosion_buildup1", 1.6, 0.35)
				return true
			end,
		}))
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.5,
			func = function()
				partner.mono_arriving = true
				F.fuse(host, partner)
				play_sound("whoosh2", 1.2, 0.6)
				return true
			end,
		}))
		G.E_MANAGER:add_event(Event({
			trigger = "after",
			delay = 0.35,
			func = function()
				partner.mono_arriving = nil
				host.mono_reveal_t = G.TIMERS.REAL
				play_sound("explosion_release1", 1.5, 0.5)
				play_sound("foil2", 1.3, 0.4)
				host:juice_up(0.8, 0.5)
				G.ROOM.jiggle = G.ROOM.jiggle + 0.7
				attention_text({
					text = localize("k_mono_fused_ex"),
					scale = 0.7,
					hold = 1.2,
					backdrop_colour = G.C.SECONDARY_SET.Spectral,
					align = "bm",
					major = host,
					offset = { x = 0, y = 0.05 * host.T.h },
				})
				return true
			end,
		}))
		delay(0.6)
	end,
})
