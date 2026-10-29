shader_type canvas_item;
// Diagonal hazard stripes. The pattern runs on frame coordinates (`origin` is
// where this band sits in the frame), so neighbouring bands join up.
uniform float period = 22.0;
uniform vec2 origin = vec2(0.0);
uniform vec4 yellow : source_color = vec4(0.99, 0.8, 0.1, 1.0);
uniform vec4 dark : source_color = vec4(0.1, 0.1, 0.12, 1.0);
uniform vec2 band_size = vec2(100.0);

void fragment() {
	vec2 at = origin + UV * band_size;
	float stripe = fract((at.x + at.y) / period);
	COLOR = stripe < 0.5 ? yellow : dark;
}
