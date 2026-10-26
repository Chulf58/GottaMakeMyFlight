// Inverted-hull outline for the Toon Series look, used as the next_pass of a
// toon material. Unity's CustomToonOutline extrudes by a fixed object-space width
// (0.5 to 2.5 mm), which is below one pixel at the tycoon camera's 12 to 120 m,
// so this version extrudes by a constant number of PIXELS in clip space instead.
// Works for perspective and orthogonal cameras alike.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, fog_disabled;

uniform vec4 outline_color : source_color = vec4(0.08, 0.08, 0.1, 1.0);
uniform float outline_px = 1.5;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 view_normal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	// Direction of the normal on screen, measured in pixels so a non-square
	// viewport still gets the same thickness horizontally and vertically.
	vec2 dir_px = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy * VIEWPORT_SIZE;
	float len_px = length(dir_px);
	if (len_px > 1e-6) {
		vec2 offset_ndc = dir_px / len_px * outline_px * 2.0 / VIEWPORT_SIZE;
		clip.xy += offset_ndc * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
}
