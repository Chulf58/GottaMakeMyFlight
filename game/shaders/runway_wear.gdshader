// Stylized Toon touchdown rubber/tire skid wear decal overlay for the runway.
// UV.x runs along the touchdown zone (0..1), UV.y across the runway gear track (-1..1 mapped to 0..1).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled;

uniform vec3 rubber_color : source_color = vec3(0.08, 0.08, 0.09);
uniform float intensity = 0.56;
uniform sampler2D ramp_texture : filter_nearest, repeat_disable;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	return fract(p * (p + p));
}

void fragment() {
	float along = UV.x;
	float across = UV.y * 2.0 - 1.0;

	// Envelope: fades cleanly at front and back ends of the touchdown decal strip.
	float end_fade = smoothstep(0.0, 0.22, along) * (1.0 - smoothstep(0.68, 1.0, along));
	float center_bias = 1.0 - smoothstep(0.18, 0.95, abs(across));

	// Multiple longitudinal tire streak lanes along main gear and nose tracks.
	float lane = floor((across + 1.0) * 14.0);
	float lane_f = fract((across + 1.0) * 14.0);
	float r0 = hash11(lane * 1.73 + 5.1);
	float r1 = hash11(lane * 3.19 + 11.7);
	float start_u = 0.05 + r0 * 0.22;
	float stop_u = 0.48 + r1 * 0.45;
	float streak_len = smoothstep(start_u, start_u + 0.08, along) * (1.0 - smoothstep(stop_u - 0.10, stop_u, along));
	float streak_w = 1.0 - smoothstep(0.18, 0.46, abs(lane_f - 0.5));

	// Two main gear clusters (around |across| ~ 0.28..0.68) plus light nose gear center track.
	float main_track = exp(-pow((abs(across) - 0.42) * 3.2, 2.0));
	float nose_track = exp(-pow(across * 6.5, 2.0)) * 0.45;
	float density = (main_track + nose_track) * end_fade * center_bias * streak_len * streak_w;

	// Toon-stepped alpha bands for crisp stylized tire skids.
	float stepped = smoothstep(0.12, 0.18, density) * 0.5 + smoothstep(0.32, 0.40, density) * 0.5;
	ALBEDO = rubber_color;
	ALPHA = clamp(stepped * intensity, 0.0, 0.72);
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float half_lambert = dot(NORMAL, LIGHT) * 0.495 + 0.5;
	float lit = clamp(half_lambert * ATTENUATION, 0.0, 1.0);
	vec3 band = texture(ramp_texture, vec2(lit, 0.5)).rgb;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * band;
}
