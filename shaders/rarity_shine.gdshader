shader_type canvas_item;
// Rarity light for club thumbnails (hub_menu.gd _rarity_shine): a soft key light in the
// rarity colour pooled from the top-left, plus a glint that sweeps diagonally across every
// few seconds. Additive, so it lights the club art underneath instead of tinting it flat.
render_mode blend_add, unshaded;

uniform vec4 tint : source_color = vec4(0.9, 0.7, 0.3, 1.0);
uniform float strength = 0.6;   // overall light amount (common clubs get less)
uniform float speed = 0.22;     // glint passes per second
uniform float phase = 0.0;      // per-card offset so the shelf doesn't glint in unison

void fragment() {
	// key light: a broad pool from the upper-left plus a faint rim along the bottom
	float key = 1.0 - smoothstep(0.0, 1.05, distance(UV, vec2(0.18, 0.12)));
	float rim = smoothstep(0.7, 1.0, UV.y) * 0.25;
	// glint: a thin diagonal band crossing the card, then a pause before the next pass
	float t = fract(TIME * speed + phase);
	float pos = t * 2.6 - 0.8;
	float band = (UV.x * 0.8 + UV.y * 0.6) - pos;
	float glint = exp(-band * band * 260.0) * 1.2 + exp(-band * band * 30.0) * 0.18;
	vec3 light = tint.rgb * (key * 0.5 + rim) + mix(tint.rgb, vec3(1.0), 0.55) * glint;
	COLOR = vec4(light * strength, 1.0);
}
