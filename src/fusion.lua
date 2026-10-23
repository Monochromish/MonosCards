MONO.Fusion = {}
local F = MONO.Fusion

-- mates being copied by their own fusion's blueprint/brainstorm act alone
local solo = setmetatable({}, { __mode = "k" })

function F.is_host(card)
	return card and card.mono_partners and #card.mono_partners > 0
end

function F.members(host)
	local members = { host }
	for _, p in ipairs(host.mono_partners or {}) do
		members[#members + 1] = p
	end
	return members
end

function F.fusable_jokers()
	local pool = {}
	for _, j in ipairs(G.jokers.cards) do
		if not j.getting_sliced and not j.removed and not (j.edition and j.edition.type == "mp_phantom") then
			pool[#pool + 1] = j
		end
	end
	return pool
end

-- leftmost hosts, so the pair keeps acting left to right
function F.choose_host(a, b)
	local ia, ib
	for i, c in ipairs(G.jokers.cards) do
		if c == a then ia = i end
		if c == b then ib = i end
	end
	if ib < ia then return b, a end
	return a, b
end

-- lets position based jokers (blueprint, ceremonial dagger) see the fused card's neighbours
local function in_host_slot(host, partner, fn)
	local cards = G.jokers.cards
	local idx
	for i, c in ipairs(cards) do
		if c == host then
			idx = i
			break
		end
	end
	if not idx then return fn() end
	cards[idx] = partner
	local a, b = fn()
	cards[idx] = host
	return a, b
end

-- partners are hidden, so their popups and juice go on the host
local RETARGET_KEYS = { "card", "message_card", "juice_card", "focus" }
local function retarget(eff, partner, host)
	if type(eff) ~= "table" then return eff end
	local copy = {}
	for k, v in pairs(eff) do
		copy[k] = v
	end
	for _, k in ipairs(RETARGET_KEYS) do
		if copy[k] == partner then copy[k] = host end
	end
	if type(copy.extra) == "table" then copy.extra = retarget(copy.extra, partner, host) end
	return copy
end

local function copy_chain(eff)
	if type(eff) ~= "table" then return eff end
	local copy = {}
	for k, v in pairs(eff) do
		copy[k] = v
	end
	if type(copy.extra) == "table" then copy.extra = copy_chain(copy.extra) end
	return copy
end

local function merge(effs)
	if #effs == 0 then return nil end
	if #effs == 1 then return effs[1] end
	for i, e in ipairs(effs) do
		effs[i] = copy_chain(e)
	end
	return SMODS.merge_effects(effs)
end

function F.attach(host, partner)
	host.mono_partners = host.mono_partners or {}
	table.insert(host.mono_partners, partner)
	partner.mono_host = host
	partner.highlighted = false
	partner.states.collide.can = false
	partner.states.hover.can = false
	partner.states.click.can = false
	partner.states.drag.can = false
	partner.debuff = host.debuff
end

local function share_stickers(host, partner)
	if partner.pinned then host.pinned = true end
	local eternal = host.ability.eternal or partner.ability.eternal
	for key in pairs(SMODS.Stickers) do
		if partner.ability[key] and key ~= "pinned" then
			if key == "perishable" then
				if not eternal then
					local tally = partner.ability.perish_tally
					if not host.ability.perishable then host:add_sticker("perishable", true) end
					host.ability.perish_tally = math.min(host.ability.perish_tally or tally, tally)
				end
			elseif not host.ability[key] then
				host:add_sticker(key, true)
			end
			partner:remove_sticker(key)
		end
	end
	if eternal and host.ability.perishable then host:remove_sticker("perishable") end
end

function F.fuse(host, partner)
	local moving = { partner }
	for _, p in ipairs(partner.mono_partners or {}) do
		moving[#moving + 1] = p
	end
	partner.mono_partners = nil
	if partner.area then partner.area:remove_card(partner) end
	share_stickers(host, partner)
	for _, p in ipairs(moving) do
		F.attach(host, p)
	end
	host:set_cost()
	if host.ability.perishable and host.ability.perish_tally <= 0 then host:set_debuff() end
end

-- for a half destroying itself. a leaving host hands its slot and stickers to the next joker
function F.split_off(card)
	local host = card.mono_host
	if host then
		for i, p in ipairs(host.mono_partners) do
			if p == card then
				table.remove(host.mono_partners, i)
				break
			end
		end
		if #host.mono_partners == 0 then host.mono_partners = nil end
		card.mono_host = nil
		host:set_cost()
		return
	end
	if not F.is_host(card) then return end

	local heir = table.remove(card.mono_partners, 1)
	local rest = card.mono_partners
	card.mono_partners = nil
	heir.mono_host = nil
	heir.states.collide.can = true
	heir.states.hover.can = true
	heir.states.click.can = true
	heir.states.drag.can = true

	local area = card.area
	if area then
		for i, c in ipairs(area.cards) do
			if c == card then
				area.cards[i] = heir
				break
			end
		end
		card:remove_from_area()
		heir:set_card_area(area)
		area:set_ranks()
	end

	if card.pinned then heir.pinned = true end
	for key in pairs(SMODS.Stickers) do
		if card.ability[key] and key ~= "pinned" and not heir.ability[key] then
			heir:add_sticker(key, true)
			if key == "perishable" then heir.ability.perish_tally = card.ability.perish_tally end
		end
	end
	for _, p in ipairs(rest) do
		F.attach(heir, p)
	end
	heir:set_cost()
	card.mono_successor = heir
end

local calculate_joker_ref = Card.calculate_joker
function Card:calculate_joker(context, ...)
	local args = { ... }
	local was_host = F.is_host(self)

	local prev = F.current_member
	F.current_member = self
	local eff, triggered = calculate_joker_ref(self, context, ...)
	F.current_member = prev
	-- mr bones dissolves itself later, in an event
	if type(eff) == "table" and eff.saved then self.mono_self_destruct = true end

	if not was_host or solo[self] or self.debuff or context.other_joker == self then return eff, triggered end

	local effs = {}
	if eff then effs[1] = eff end
	if F.is_host(self) then
		for _, p in ipairs(F.members(self)) do
			if p ~= self and p.mono_host == self and (not context.blueprint or p.config.center.blueprint_compat) then
				local p_eff, p_trig = in_host_slot(self, p, function()
					return p:calculate_joker(context, unpack(args))
				end)
				if p_eff then effs[#effs + 1] = retarget(p_eff, p, self) end
				triggered = triggered or p_trig
			end
		end
	elseif self.mono_successor then
		-- host destroyed itself mid calc, the joker that took its slot still acts
		local s_eff, s_trig = self.mono_successor:calculate_joker(context, unpack(args))
		if s_eff then effs[#effs + 1] = s_eff end
		triggered = triggered or s_trig
	end
	return merge(effs), triggered
end

local blueprint_effect_ref = SMODS.blueprint_effect
local function copy_fusion_mates(copier, host, context)
	local effs = {}
	for _, m in ipairs(F.members(host)) do
		if m ~= copier and not m.debuff and m.config.center.blueprint_compat then
			solo[m] = true
			local eff = in_host_slot(host, m, function()
				return blueprint_effect_ref(copier, m, context)
			end)
			solo[m] = nil
			if eff then effs[#effs + 1] = eff end
		end
	end
	return merge(effs)
end

function SMODS.blueprint_effect(copier, copied_card, context)
	local own_fusion = copier and (copier.mono_host or (F.is_host(copier) and copier))
	-- e.g. brainstorm fused into the leftmost card would otherwise copy itself
	if copied_card and copied_card == copier and own_fusion and not context.no_blueprint then
		return copy_fusion_mates(copier, own_fusion, context)
	end
	if
		not F.is_host(copied_card)
		or copied_card.config.center.blueprint_compat
		or copied_card == copier
		or copied_card.debuff
		or context.no_blueprint
	then
		return blueprint_effect_ref(copier, copied_card, context)
	end
	local effs = {}
	for _, p in ipairs(copied_card.mono_partners) do
		local eff = in_host_slot(copied_card, p, function()
			return blueprint_effect_ref(copier, p, context)
		end)
		if eff then effs[#effs + 1] = eff end
	end
	return merge(effs)
end

local calculate_edition_ref = Card.calculate_edition
function Card:calculate_edition(context, ...)
	local eff = calculate_edition_ref(self, context, ...)
	if not F.is_host(self) then return eff end
	local effs = {}
	if eff then effs[1] = eff end
	for _, p in ipairs(self.mono_partners) do
		if p.edition then
			local p_eff = calculate_edition_ref(p, context, ...)
			if p_eff then effs[#effs + 1] = retarget(p_eff, p, self) end
		end
	end
	return merge(effs)
end

local calculate_dollar_bonus_ref = Card.calculate_dollar_bonus
function Card:calculate_dollar_bonus(...)
	local ret, opts = calculate_dollar_bonus_ref(self, ...)
	if F.is_host(self) and self:can_calculate() then
		for _, p in ipairs(self.mono_partners) do
			local p_ret = in_host_slot(self, p, function()
				return calculate_dollar_bonus_ref(p)
			end)
			if p_ret then ret = (ret or 0) + p_ret end
		end
	end
	return ret, opts
end

-- passives like four fingers and showman are found by name or key
local find_joker_ref = find_joker
function find_joker(name, non_debuff)
	local found = find_joker_ref(name, non_debuff)
	for _, host in ipairs(G.jokers and G.jokers.cards or {}) do
		if F.is_host(host) and (non_debuff or not host.debuff) then
			for _, p in ipairs(host.mono_partners) do
				if p.ability.name == name then found[#found + 1] = p end
			end
		end
	end
	return found
end

local find_card_ref = SMODS.find_card
function SMODS.find_card(key, count_debuffed)
	local found = find_card_ref(key, count_debuffed)
	for _, host in ipairs(G.jokers and G.jokers.cards or {}) do
		if F.is_host(host) and (count_debuffed or not host.debuff) then
			for _, p in ipairs(host.mono_partners) do
				if p.config.center.key == key then found[#found + 1] = p end
			end
		end
	end
	return found
end

-- negative partners still give their slot
local count_property_ref = CardArea.count_property
function CardArea:count_property(property)
	local value = count_property_ref(self, property)
	if self == G.jokers and (property == "card_limit" or property == "extra_slots_used") then
		for _, host in ipairs(self.cards) do
			for _, p in ipairs(host.mono_partners or {}) do
				value = value + p.ability[property]
			end
		end
	end
	return value
end

local add_to_deck_ref = Card.add_to_deck
function Card:add_to_deck(from_debuff)
	add_to_deck_ref(self, from_debuff)
	for _, p in ipairs(self.mono_partners or {}) do
		p:add_to_deck(from_debuff)
	end
end

local remove_from_deck_ref = Card.remove_from_deck
function Card:remove_from_deck(from_debuff)
	remove_from_deck_ref(self, from_debuff)
	for _, p in ipairs(self.mono_partners or {}) do
		p:remove_from_deck(from_debuff)
	end
end

local set_debuff_ref = Card.set_debuff
function Card:set_debuff(should_debuff)
	set_debuff_ref(self, should_debuff)
	for _, p in ipairs(self.mono_partners or {}) do
		p.debuff = self.debuff
	end
end

local set_cost_ref = Card.set_cost
function Card:set_cost()
	set_cost_ref(self)
	if F.is_host(self) then
		for _, p in ipairs(self.mono_partners) do
			self.sell_cost = self.sell_cost + p.sell_cost
		end
		self.sell_cost_label = self.facing == "back" and "?" or self.sell_cost
	elseif self.mono_host and not self.mono_host.removed then
		-- egg raising a partner's value
		self.mono_host:set_cost()
	end
end

local destroy_cards_ref = SMODS.destroy_cards
function SMODS.destroy_cards(cards, ...)
	local list = (type(cards) == "table" and cards[1]) and cards or { cards }
	for _, c in ipairs(list) do
		if type(c) == "table" and c == F.current_member and (c.mono_host or F.is_host(c)) then
			c.mono_self_destruct = true
		end
	end
	return destroy_cards_ref(cards, ...)
end

-- eternal protects the card, not a half killing itself (gros michel going extinct)
local is_eternal_ref = SMODS.is_eternal
function SMODS.is_eternal(card, ...)
	if card and card.mono_self_destruct then return false end
	return is_eternal_ref(card, ...)
end

-- partners only dissolve from their own effects. a host splits off only when it destroys itself,
-- otherwise (sold, madness, dagger) the whole card goes
local start_dissolve_ref = Card.start_dissolve
function Card:start_dissolve(...)
	if self.mono_host or (F.is_host(self) and (self.mono_self_destruct or F.current_member == self)) then
		F.split_off(self)
	end
	return start_dissolve_ref(self, ...)
end

-- eval_card only scores editions for cards that have one
local eval_card_ref = eval_card
function eval_card(card, context)
	local ret, post = eval_card_ref(card, context)
	if F.is_host(card) and not card.edition and type(ret) == "table" and not ret.edition then
		context = context or {}
		if card:can_calculate(context.ignore_debuff, context.remove_playing_cards or context.joker_type_destroyed) then
			ret.edition = card:calculate_edition(context)
		end
	end
	return ret, post
end

local remove_ref = Card.remove
function Card:remove()
	if self.mono_host then F.split_off(self) end
	local partners = self.mono_partners
	remove_ref(self)
	self.mono_partners = nil
	for _, p in ipairs(partners or {}) do
		p.mono_host = nil
		if not p.removed then p:remove() end
	end
end

local flip_ref = Card.flip
function Card:flip(...)
	flip_ref(self, ...)
	for _, p in ipairs(self.mono_partners or {}) do
		flip_ref(p, ...)
	end
end

local copy_card_ref = copy_card
function copy_card(other, new_card, card_scale, playing_card, strip_edition)
	local card = copy_card_ref(other, new_card, card_scale, playing_card, strip_edition)
	if F.is_host(other) and not playing_card then
		for _, p in ipairs(other.mono_partners) do
			F.attach(card, copy_card_ref(p, nil, card_scale, nil, strip_edition))
		end
		card:set_cost()
	end
	return card
end

local save_ref = Card.save
function Card:save()
	local t = save_ref(self)
	if F.is_host(self) then
		t.mono_partners = {}
		for _, p in ipairs(self.mono_partners) do
			t.mono_partners[#t.mono_partners + 1] = p:save()
		end
	end
	return t
end

local load_ref = Card.load
function Card:load(cardTable, other_card)
	load_ref(self, cardTable, other_card)
	for _, pt in ipairs(cardTable.mono_partners or {}) do
		loading = true
		local p = Card(self.T.x, self.T.y, G.CARD_W, G.CARD_H, G.P_CENTERS.j_joker, G.P_CENTERS.c_base)
		loading = nil
		p:load(pt)
		F.attach(self, p)
	end
end

local move_ref = Card.move
function Card:move(dt)
	local host = self.mono_host
	if host then
		self.T.x = host.T.x + (host.T.w - self.T.w) / 2
		self.T.y = host.T.y + (host.T.h - self.T.h) / 2
		self.T.r = host.T.r
		self.states.collide.can = false
		self.dissolve = host.dissolve
		self.dissolve_colours = host.dissolve_colours
	end
	return move_ref(self, dt)
end

local juice_up_ref = Card.juice_up
function Card:juice_up(...)
	if self.mono_host then return self.mono_host:juice_up(...) end
	return juice_up_ref(self, ...)
end

local card_eval_status_text_ref = card_eval_status_text
function card_eval_status_text(card, ...)
	if card and card.mono_host then card = card.mono_host end
	return card_eval_status_text_ref(card, ...)
end

local update_ref = Card.update
function Card:update(dt)
	update_ref(self, dt)
	if
		G.STAGE == G.STAGES.RUN
		and self.area == G.jokers
		and (self.ability.name == "Blueprint" or self.ability.name == "Brainstorm")
	then
		local other
		if self.ability.name == "Brainstorm" then
			other = G.jokers.cards[1]
		else
			for i, c in ipairs(G.jokers.cards) do
				if c == self then other = G.jokers.cards[i + 1] end
			end
		end
		if other and F.is_host(other) and (other == self or not other.config.center.blueprint_compat) then
			for _, p in ipairs(other.mono_partners) do
				if p.config.center.blueprint_compat then self.ability.blueprint_compat = "compatible" end
			end
		end
	end
end

local function partner_header(p)
	local name = localize({ type = "name_text", key = p.config.center.key, set = p.ability.set })
	local colour = G.C.RARITY[p.config.center.rarity] or G.C.JOKER_GREY
	return {
		{
			n = G.UIT.C,
			config = { align = "cm", colour = colour, r = 0.1, padding = 0.04, emboss = 0.04 },
			nodes = {
				{ n = G.UIT.T, config = { text = " " .. name .. " ", scale = 0.3, colour = G.C.WHITE, shadow = true } },
			},
		},
	}
end

local generate_UIBox_ability_table_ref = Card.generate_UIBox_ability_table
function Card:generate_UIBox_ability_table(vars_only, ...)
	local AUT = generate_UIBox_ability_table_ref(self, vars_only, ...)
	if vars_only or not F.is_host(self) then return AUT end

	AUT.main.main_box_flag = true
	AUT.multi_box = AUT.multi_box or {}

	local seen_badges, seen_info = {}, {}
	for _, b in ipairs(AUT.badges) do
		seen_badges[b] = true
	end
	for _, box in ipairs(AUT.info) do
		if box.name then seen_info[box.name] = true end
	end

	local fused_info = {}
	-- a non nil name makes generate_card_ui build a side tooltip
	generate_card_ui({ key = "mono_fused", set = "Other" }, { main = {}, info = fused_info, type = {}, name = true, badges = {} })
	for i = #fused_info, 1, -1 do
		table.insert(AUT.info, 1, fused_info[i])
	end
	AUT.badges[#AUT.badges + 1] = "mono_fused"

	for _, p in ipairs(self.mono_partners) do
		local pAUT = generate_UIBox_ability_table_ref(p)
		local box = { partner_header(p) }
		for _, row in ipairs(pAUT.main) do
			box[#box + 1] = row
		end
		AUT.multi_box[#AUT.multi_box + 1] = box
		for _, extra in ipairs(pAUT.multi_box or {}) do
			AUT.multi_box[#AUT.multi_box + 1] = extra
		end
		for _, b in ipairs(pAUT.badges) do
			if not seen_badges[b] then
				seen_badges[b] = true
				AUT.badges[#AUT.badges + 1] = b
			end
		end
		for _, info in ipairs(pAUT.info) do
			if not (info.name and seen_info[info.name]) then
				if info.name then seen_info[info.name] = true end
				AUT.info[#AUT.info + 1] = info
			end
		end
	end
	return AUT
end

local get_badge_colour_ref = get_badge_colour
function get_badge_colour(key)
	if key == "mono_fused" then return G.C.SECONDARY_SET.Spectral end
	return get_badge_colour_ref(key)
end
