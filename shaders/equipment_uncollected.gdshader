shader_type canvas_item;
render_mode unshaded;

void fragment() {
	// Flat, dark cutout by alpha only -- discards all real color, shading and finish
	// detail, so an undiscovered item reads as a hidden mystery shape rather than a
	// plain grey product photo. That distinction matters here: most club families
	// (driver, wood, hybrid, iron, wedge) share one base mesh and differ only by
	// texture, so a desaturated-but-still-shaded render of any of them is visually
	// identical to the plain starter club -- there's no mystery left to see. Matches
	// ClubSilhouette's own ghost fill color/opacity for a consistent look everywhere.
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(0.098, 0.231, 0.196, a * 0.22);
}
