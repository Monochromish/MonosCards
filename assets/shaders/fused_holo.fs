#if defined(VERTEX) || __VERSION__ > 100 || defined(GL_FRAGMENT_PRECISION_HIGH)
	#define MY_HIGHP_OR_MEDIUMP highp
#else
	#define MY_HIGHP_OR_MEDIUMP mediump
#endif

extern MY_HIGHP_OR_MEDIUMP float time;
extern MY_HIGHP_OR_MEDIUMP float hover;
extern MY_HIGHP_OR_MEDIUMP float tilt;
extern MY_HIGHP_OR_MEDIUMP float reveal;
extern MY_HIGHP_OR_MEDIUMP float fade;
extern MY_HIGHP_OR_MEDIUMP vec2 art;
extern MY_HIGHP_OR_MEDIUMP float strip_w;
extern MY_HIGHP_OR_MEDIUMP vec3 charge;
extern MY_HIGHP_OR_MEDIUMP float flips[24]; // <= 0 shows the host

#ifdef PIXEL
float hash(float n) { return fract(sin(n * 12.9898) * 43758.5453); }

vec3 rainbow(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

vec4 over(vec4 dst, vec3 rgb, float a) {
	a = clamp(a, 0.0, 1.0);
	return vec4(rgb * a + dst.rgb * (1.0 - a), a + dst.a * (1.0 - a));
}

vec4 effect(vec4 colour, Image texture, vec2 texture_coords, vec2 screen_coords)
{
	vec2 px = floor(texture_coords * art);
	vec2 c = px + 0.5;

	vec2 q = abs(c - art * 0.5) - (art * 0.5 - vec2(4.0));
	float sdf = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - 4.0;
	if (sdf > 0.0) discard;
	float inset = -sdf;

	float strip = floor(px.x / strip_w);
	float f = flips[int(min(strip, 23.0))];
	float turning = clamp(1.0 - abs(f), 0.0, 1.0);
	float in_strip = px.x - strip * strip_w;

	vec4 o = vec4(0.0);

	// ridges mid flip go dark with a lit edge
	o = over(o, vec3(0.0), turning * 0.38);
	if (in_strip < 0.5) o = over(o, vec3(1.0), turning * 0.55);
	if (in_strip > strip_w - 1.5) o = over(o, vec3(0.0), turning * 0.25);

	vec3 irid = rainbow(strip * 0.071 + c.y / art.y * 0.35 + time * 0.12 + tilt * 0.35);
	float shimmer = smoothstep(0.55, 1.0, sin(c.x * 0.16 + c.y * 0.09 - tilt * 3.0 + time * 0.7));
	o = over(o, irid, turning * (0.32 + 0.18 * hover) + shimmer * (0.06 + 0.06 * hover));

	if (inset < 2.0) {
		float perim = (abs(c.y - art.y * 0.5) < art.y * 0.5 - 4.0)
			? (c.x < art.x * 0.5 ? c.y : 2.0 * art.y + art.x - c.y)
			: (c.y < art.y * 0.5 ? art.y + c.x : 2.0 * art.y + 2.0 * art.x - c.x);
		float dash = step(0.72, fract(perim / 9.0 - time * (1.2 + 1.3 * hover) + hash(floor(perim / 9.0)) * 0.3));
		float flick = 0.65 + 0.35 * sin(time * 23.0 + perim);
		o = over(o, inset < 1.0 ? charge : vec3(1.0), dash * flick * (0.55 + 0.4 * hover));
	}

	o = over(o, vec3(1.0), reveal * 0.85);
	return vec4(o.rgb, o.a * fade);
}
#endif

extern MY_HIGHP_OR_MEDIUMP vec2 mouse_screen_pos;
extern MY_HIGHP_OR_MEDIUMP float hovering;
extern MY_HIGHP_OR_MEDIUMP float screen_scale;

#ifdef VERTEX
vec4 position( mat4 transform_projection, vec4 vertex_position )
{
	if (hovering <= 0.){
		return transform_projection * vertex_position;
	}
	float mid_dist = length(vertex_position.xy - 0.5*love_ScreenSize.xy)/length(love_ScreenSize.xy);
	vec2 mouse_offset = (vertex_position.xy - mouse_screen_pos.xy)/screen_scale;
	float scale = 0.2*(-0.03 - 0.3*max(0., 0.3-mid_dist))
				*hovering*(length(mouse_offset)*length(mouse_offset))/(2. -mid_dist);

	return transform_projection * vertex_position + vec4(0,0,0,scale);
}
#endif
