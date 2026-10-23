local F = MONO.Fusion

local ART_W, ART_H = 71, 95
local STRIP = 3
local STRIPS = math.ceil(ART_W / STRIP)
local BAND = 0.2
local PARALLAX = 1.25 -- art px each way at full tilt

local GOLD = { 199 / 255, 178 / 255, 74 / 255 }
local DARK = { 79 / 255, 99 / 255, 103 / 255 }
local WHITE = { 1, 1, 1 }

local CLIP = {
	"...###.",
	"..###..",
	"..##...",
	".#####.",
	"...###.",
	"...##..",
	"..##...",
	"..#....",
}

-- only these get split between host and partner, stickers etc are drawn once on top
local ART_STEPS = {
	center = true,
	front = true,
	card_type_shader = true,
	edition = true,
	soul = true,
	floating_sprite = true,
}

local holo_shader = love.graphics.newShader(NFS.read(MONO.path .. "assets/shaders/fused_holo.fs"))
local blank = love.graphics.newImage(love.image.newImageData(1, 1, "rgba8", string.char(255, 255, 255, 255)))

local function hash(a, b)
	local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
	return x - math.floor(x)
end

-- the compiler strips uniforms the shader doesn't end up using, and send() errors on those
local function send(name, ...)
	if holo_shader:hasUniform(name) then holo_shader:send(name, ...) end
end

local function shown_partner(host)
	local n = #host.mono_partners
	if n == 1 then return host.mono_partners[1] end
	return host.mono_partners[math.floor(G.TIMERS.REAL / 4 + host.ID) % n + 1]
end

local function update_wave(host)
	local rel = 0
	local target
	if host.states.hover.is or host.states.drag.is then
		local unit = G.TILESIZE * G.TILESCALE
		local cx = (host.VT.x + host.VT.w / 2 + G.ROOM.T.x) * unit
		rel = (G.CONTROLLER.cursor_position.x - cx) / (host.VT.w / 2 * unit)
		rel = math.max(-1, math.min(1, rel))
		target = 0.5 - 0.42 * rel
	else
		target = 0.5 + 0.14 * math.sin(G.TIMERS.REAL * 0.8 + host.ID)
	end
	local k = math.min(1, G.real_dt * 7)
	host.mono_phase = (host.mono_phase or 0.5) + (target - (host.mono_phase or 0.5)) * k
	host.mono_tilt = (host.mono_tilt or 0) + (rel - (host.mono_tilt or 0)) * k
	host.mono_hover = (host.mono_hover or 0) + ((host.states.hover.is and 1 or 0) - (host.mono_hover or 0)) * k
	return host.mono_phase, host.mono_tilt
end

-- <= 0 shows the host. the random offsets make ridges flip out of order like a real lenticular print
local function ridge_flips(host, phase)
	local flips = {}
	for i = 0, STRIPS - 1 do
		local sx = (i * STRIP + STRIP / 2) / ART_W
		flips[i + 1] = (sx - phase) / BAND + (hash(i + 1, host.ID) - 0.5) * 1.2
	end
	return flips
end

local function host_mask(host, flips)
	local w, h = host.VT.w, host.VT.h
	local px = w / ART_W
	for i = 0, STRIPS - 1 do
		if flips[i + 1] <= 0 then
			local x0 = i == 0 and -w or i * STRIP * px
			local x1 = i == STRIPS - 1 and 2 * w or math.min(ART_W, (i + 1) * STRIP) * px
			love.graphics.rectangle("fill", x0, -h, x1 - x0, 3 * h)
		end
	end
end

local function run_art_steps(card, layer)
	for _, k in ipairs(SMODS.DrawStep.obj_buffer) do
		if ART_STEPS[k] then
			local step = SMODS.DrawSteps[k]
			if step:check_conditions(card, layer) then step.func(card, layer) end
		end
	end
end

local function draw_shifted(card, layer, dx)
	card.VT.x = card.VT.x + dx
	run_art_steps(card, layer)
	card.VT.x = card.VT.x - dx
end

-- the partner borrows the host's tilt so the shaders bend both halves the same way
local function sync_partner(host, p)
	p.VT.x = host.VT.x + (host.VT.w - p.VT.w) / 2
	p.VT.y = host.VT.y + (host.VT.h - p.VT.h) / 2
	p.VT.r = host.VT.r
	p.VT.scale = host.VT.scale
	p.hover_tilt = host.hover_tilt
	p.tilt_var = host.tilt_var
	p.ARGS.send_to_shader = host.ARGS.send_to_shader
	p.dissolve = host.dissolve
	p.dissolve_colours = host.dissolve_colours
end

local function strength(host)
	local s = 1 - math.min(1, math.abs(host.dissolve or 0))
	if host.debuff then s = s * 0.35 end
	return s
end

local function draw_holo(host, flips, tilt, reveal)
	local spectral = G.C.SECONDARY_SET.Spectral
	love.graphics.setShader(holo_shader)
	send("time", G.TIMERS.REAL % 1000)
	send("flips", unpack(flips))
	send("hover", host.mono_hover)
	send("tilt", tilt)
	send("reveal", reveal)
	send("fade", strength(host))
	send("art", { ART_W, ART_H })
	send("strip_w", STRIP)
	send("charge", host.debuff and { 0.6, 0.6, 0.6 } or { spectral[1], spectral[2], spectral[3] })
	send("mouse_screen_pos", { host.tilt_var.mx * G.CANV_SCALE, host.tilt_var.my * G.CANV_SCALE })
	send("hovering", G.SETTINGS.reduced_motion and 0 or host.hover_tilt)
	send("screen_scale", G.TILESCALE * G.TILESIZE * (host.mouse_damping or 1) * G.CANV_SCALE)
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.draw(blank, 0, 0, 0, host.VT.w, host.VT.h)
	love.graphics.setShader()
end

local function bolt_cells(x0, y0, x1, y1, jitter, seed)
	local pts = { { x0, y0 }, { x1, y1 } }
	for level = 1, 3 do
		local nxt = { pts[1] }
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local off = (hash(seed + level * 7.1, i) - 0.5) * 2 * jitter
			nxt[#nxt + 1] = { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2 + off }
			nxt[#nxt + 1] = b
		end
		pts = nxt
		jitter = jitter * 0.55
	end
	local cells, seen = {}, {}
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local n = math.max(1, math.floor(math.max(math.abs(b[1] - a[1]), math.abs(b[2] - a[2])) + 0.5))
		for s = 0, n do
			local x = math.floor(a[1] + (b[1] - a[1]) * s / n + 0.5)
			local y = math.floor(a[2] + (b[2] - a[2]) * s / n + 0.5)
			local key = x * 1000 + y
			if not seen[key] then
				seen[key] = true
				cells[#cells + 1] = { x, y }
			end
		end
	end
	return cells
end

local function spawn_arc(host, seed)
	local phase = host.mono_phase
	local y0 = 8 + hash(seed, 1) * (ART_H - 16)
	local x0 = (phase - BAND * (0.4 + 0.6 * hash(seed, 2))) * ART_W
	local x1 = (phase + BAND * (0.4 + 0.6 * hash(seed, 3))) * ART_W
	local y1 = y0 + (hash(seed, 4) - 0.5) * 24
	local arc = { cells = bolt_cells(x0, y0, x1, y1, 5, seed), age = 0, life = 0.12 + 0.12 * hash(seed, 5) }
	if hash(seed, 6) < 0.6 then
		local root = arc.cells[math.max(1, math.floor(#arc.cells * (0.3 + 0.4 * hash(seed, 7))))]
		local bx = root[1] + (hash(seed, 8) - 0.5) * 14
		local by = root[2] + (hash(seed, 9) < 0.5 and -1 or 1) * (5 + 6 * hash(seed, 10))
		for _, c in ipairs(bolt_cells(root[1], root[2], bx, by, 2, seed + 0.5)) do
			arc.cells[#arc.cells + 1] = c
		end
	end
	host.mono_arcs[#host.mono_arcs + 1] = arc
end

local function draw_arcs(host, reveal)
	host.mono_arcs = host.mono_arcs or {}
	host.mono_arc_n = (host.mono_arc_n or 0) + 1
	local dt = G.real_dt
	local seed = host.mono_arc_n + host.ID * 0.37

	if reveal > 0 and not host.mono_reveal_burst then
		host.mono_reveal_burst = true
		for i = 1, 6 do
			spawn_arc(host, seed + i * 3.3)
		end
	end
	local rate = host.debuff and 0 or (1.6 + 4 * host.mono_hover)
	if hash(seed, 0.5) < rate * dt then spawn_arc(host, seed) end

	local px, py = host.VT.w / ART_W, host.VT.h / ART_H
	local glow = G.C.SECONDARY_SET.Spectral
	local s = strength(host)
	for i = #host.mono_arcs, 1, -1 do
		local arc = host.mono_arcs[i]
		arc.age = arc.age + dt
		if arc.age >= arc.life then
			table.remove(host.mono_arcs, i)
		else
			local a = s * (1 - arc.age / arc.life)
			love.graphics.setColor(glow[1], glow[2], glow[3], a * 0.45)
			for _, c in ipairs(arc.cells) do
				love.graphics.rectangle("fill", (c[1] - 1) * px, (c[2] - 1) * py, 3 * px, 3 * py)
			end
			love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], a)
			for _, c in ipairs(arc.cells) do
				love.graphics.rectangle("fill", c[1] * px, (c[2] + 1) * py, px, py)
			end
			love.graphics.setColor(1, 1, 1, a)
			for _, c in ipairs(arc.cells) do
				love.graphics.rectangle("fill", c[1] * px, c[2] * py, px, py)
			end
		end
	end
	love.graphics.setColor(1, 1, 1, 1)
end

local clip_fill, clip_outline = {}, {}
do
	local filled = {}
	for y, row in ipairs(CLIP) do
		for x = 1, #row do
			if row:sub(x, x) == "#" then
				filled[x * 100 + y] = true
				clip_fill[#clip_fill + 1] = { x, y, first = not filled[(x - 1) * 100 + y] }
			end
		end
	end
	for y = 0, #CLIP + 1 do
		for x = 0, #CLIP[1] + 1 do
			if not filled[x * 100 + y] then
				for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
					if filled[(x + d[1]) * 100 + y + d[2]] then
						clip_outline[#clip_outline + 1] = { x, y }
						break
					end
				end
			end
		end
	end
end

local function draw_clip(host)
	local px, py = host.VT.w / ART_W, host.VT.h / ART_H
	local ox, oy = math.floor(ART_W / 2 - #CLIP[1] / 2 - 0.5), -4
	local s = strength(host)
	local fill = host.debuff and { 0.6, 0.6, 0.6 } or GOLD
	local pulse = 0.35 + 0.25 * math.sin(G.TIMERS.REAL * 3 + host.ID)
	local glow = G.C.SECONDARY_SET.Spectral

	love.graphics.setColor(glow[1], glow[2], glow[3], s * pulse * (host.debuff and 0 or 1))
	for _, c in ipairs(clip_outline) do
		love.graphics.rectangle("fill", (ox + c[1] - 1) * px, (oy + c[2] - 1) * py, 3 * px, 3 * py)
	end
	love.graphics.setColor(DARK[1], DARK[2], DARK[3], s)
	for _, c in ipairs(clip_outline) do
		love.graphics.rectangle("fill", (ox + c[1]) * px, (oy + c[2]) * py, px, py)
	end
	for _, c in ipairs(clip_fill) do
		local col = c.first and WHITE or fill
		love.graphics.setColor(col[1], col[2], col[3], s)
		love.graphics.rectangle("fill", (ox + c[1]) * px, (oy + c[2]) * py, px, py)
	end
	love.graphics.setColor(1, 1, 1, 1)
end

local function draw_lenticular(host, layer)
	local partner = shown_partner(host)
	local phase, tilt = update_wave(host)
	local flips = ridge_flips(host, phase)
	local reveal = host.mono_reveal_t and math.max(0, 1 - (G.TIMERS.REAL - host.mono_reveal_t) / 0.8) or 0
	local shift = (G.SETTINGS.reduced_motion and 0 or tilt * PARALLAX) * host.VT.w / ART_W

	love.graphics.stencil(function()
		prep_draw(host, 1)
		host_mask(host, flips)
		love.graphics.pop()
	end, "replace", 1)

	love.graphics.setStencilTest("equal", 1)
	draw_shifted(host, layer, -shift)

	sync_partner(host, partner)
	love.graphics.setStencilTest("equal", 0)
	draw_shifted(partner, layer, shift)
	love.graphics.setStencilTest()

	prep_draw(host, 1)
	draw_holo(host, flips, tilt, reveal)
	draw_arcs(host, reveal)
	love.graphics.pop()
end

local function lenticular_ready(card)
	if not F.is_host(card) or card.sprite_facing ~= "front" then return false end
	for _, p in ipairs(card.mono_partners) do
		if p.mono_arriving then return false end
	end
	return true
end

local draw_ref = Card.draw
function Card:draw(layer)
	-- partners only draw themselves while flying in from a zap
	if self.mono_host then
		if self.mono_arriving then return draw_ref(self, layer) end
		return
	end
	layer = layer or "both"
	if layer == "shadow" or not self.states.visible or not lenticular_ready(self) then
		return draw_ref(self, layer)
	end

	self.hover_tilt = 1
	local art_drawn = false
	for _, k in ipairs(SMODS.DrawStep.obj_buffer) do
		if ART_STEPS[k] then
			if not art_drawn then
				art_drawn = true
				draw_lenticular(self, layer)
			end
		else
			local step = SMODS.DrawSteps[k]
			if step:check_conditions(self, layer) then step.func(self, layer) end
		end
	end

	prep_draw(self, 1)
	draw_clip(self)
	love.graphics.pop()
end
