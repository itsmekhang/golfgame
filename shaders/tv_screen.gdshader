// A TV's picture: a looped clip from a sheet of its frames (tools/blender/import_tv_clip.py), laid
// left to right, top to bottom and shown one after another by the clock -- or, `sheet` off, a
// picture as it is (a video playing into a viewport). Unshaded: a screen shows its picture whatever
// the light in the room.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D frames : source_color, filter_linear_mipmap, repeat_disable;
uniform bool sheet = true;
uniform int count = 152;
uniform int cols = 12;
uniform int rows = 13;
uniform float fps = 14.2857;
uniform float brightness = 0.92;

void vertex() {
	// drawn a hair toward the camera, more the further off it is (view space scaled about the
	// camera: the same place on screen, only nearer): in front of the set's dark face however its
	// mesh is simplified with distance, yet up close still inside the bezel's 2 cm recess
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view.xyz *= 0.998;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	vec2 uv = UV;
	if (sheet) {
		int f = int(TIME * fps) % count;
		vec2 cell = vec2(float(f % cols), float(f / cols));
		// a hair in from the frame's edges, so its neighbours in the sheet never bleed in
		uv = (cell + clamp(UV, vec2(0.004), vec2(0.996))) / vec2(float(cols), float(rows));
	}
	ALBEDO = texture(frames, uv).rgb * brightness;
}
