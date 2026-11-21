shader_type canvas_item;
// Diagonal hazard stripes. The pattern runs on frame coordinates (`origin` is
// where this band sits in the frame), so neighbouring bands join seamlessly
// across the viewport edges without seams at the corners.
uniform float period = 22.0;
uniform vec2 origin = vec2(0.0);
uniform vec4 yellow : source_color = vec4(0.99, 0.8, 0.1, 1.0);
uniform vec4 dark : source_color = vec4(0.1, 0.1, 0.12, 1.0);
uniform vec2 band_size = vec2(100.0);

void fragment() {
	vec2 at = origin + UV * band_size;
	float phase = (at.x + at.y) / period;
	// Continuous triangle wave in [0, 0.5] so both yellow->dark and dark->yellow
	// boundaries sit symmetrically at 0.25 with no fract() wrap-around edge.
	float wave = abs(fract(phase - 0.25) - 0.5);
	float fw = max(length(vec2(dFdx(phase), dFdy(phase))), 1e-4);
	float aa = fw * 0.65;
	float stripe_mix = smoothstep(0.25 - aa, 0.25 + aa, wave);
	COLOR *= mix(dark, yellow, stripe_mix);
}
