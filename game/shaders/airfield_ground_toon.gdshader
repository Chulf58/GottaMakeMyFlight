// Stylized Toon airfield ground shader for the 2400x2400 m ground plane.
// Keeps the exact 3-step Toon lighting ramp of toon_common.gdshaderinc so
// cast shadows from planes, terminal, hangars and tower match the Toon Series
// look, while breaking up the flat green plane with mowed-grass airfield bands,
// graded turf shoulders around the runway/operations apron, and soft meadow
// tonal patches at medium/far distance.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D ramp_texture : filter_nearest, repeat_disable;
uniform float light_gain = 1.0;
uniform float runway_half_length = 192.0;

uniform vec3 grass_light : source_color = vec3(0.38, 0.56, 0.30);
uniform vec3 grass_dark : source_color = vec3(0.33, 0.50, 0.26);
uniform vec3 meadow_olive : source_color = vec3(0.36, 0.49, 0.25);
uniform vec3 meadow_deep : source_color = vec3(0.28, 0.44, 0.23);
uniform vec3 shoulder_turf : source_color = vec3(0.41, 0.48, 0.27);
uniform vec3 border_earth : source_color = vec3(0.36, 0.37, 0.24);

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float rect_sdf(vec2 p, vec2 bmin, vec2 bmax) {
	vec2 center = 0.5 * (bmin + bmax);
	vec2 half_ext = 0.5 * (bmax - bmin);
	vec2 d = abs(p - center) - half_ext;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 xz = world_pos.xz;
	float cam_dist = length(CAMERA_POSITION_WORLD.xz - xz);
	float detail_fade = 1.0 - smoothstep(260.0, 620.0, cam_dist);

	// Broad rolling meadow patches across the whole 2400 m ground.
	float n_broad = value_noise(xz * 0.0085 + vec2(3.7, 9.1));
	float n_mid = value_noise(xz * 0.028 + vec2(17.2, 4.3));
	float patch_val = n_broad * 0.68 + n_mid * 0.32;
	float patch_band = smoothstep(0.40, 0.48, patch_val) * 0.55 + smoothstep(0.62, 0.70, patch_val) * 0.45;
	vec3 col = mix(meadow_deep, grass_dark, patch_band);
	col = mix(col, meadow_olive, smoothstep(0.64, 0.76, n_broad) * 0.45);

	// Crisp mowed-grass airfield bands across the active airfield & terminal grounds.
	float fence_x = max(240.0, runway_half_length + 46.0);
	float airfield_mask = 1.0 - smoothstep(0.0, 22.0, rect_sdf(xz, vec2(-fence_x, -468.0), vec2(fence_x, -30.0)));
	float stripe_wave = abs(fract(xz.y / 24.0) * 2.0 - 1.0);
	float mow_step = smoothstep(0.45, 0.55, stripe_wave);
	vec3 mowed = mix(grass_dark, grass_light, mow_step);
	col = mix(col, mowed, airfield_mask * (0.65 + 0.35 * detail_fade));

	// Subtle north-south mowing cross-cut in the terminal & apron infield.
	float infield_mask = 1.0 - smoothstep(0.0, 14.0, rect_sdf(xz, vec2(-225.0, -300.0), vec2(225.0, -60.0)));
	float cross_wave = abs(fract(xz.x / 20.0) * 2.0 - 1.0);
	float cross_step = smoothstep(0.45, 0.55, cross_wave);
	col = mix(col, mix(col, grass_light, 0.30), infield_mask * cross_step * 0.45 * detail_fade);

	// Graded turf shoulder hugging the active runway length and north operations apron.
	float rwy_d = rect_sdf(xz, vec2(-runway_half_length - 10.0, -372.0), vec2(runway_half_length + 10.0, -304.0));
	float rwy_shoulder = (1.0 - smoothstep(4.0, 14.0, rwy_d)) * airfield_mask;
	float rwy_trim = 1.0 - smoothstep(0.5, 4.0, rwy_d);
	col = mix(col, shoulder_turf, rwy_shoulder * 0.72);
	col = mix(col, border_earth, rwy_trim * 0.50);

	float ops_d = rect_sdf(xz, vec2(-148.0, -460.0), vec2(148.0, -382.0));
	float ops_shoulder = 1.0 - smoothstep(2.0, 10.0, ops_d);
	col = mix(col, shoulder_turf, ops_shoulder * 0.65);

	// Compacted earth/gravel patrol trim grounding the perimeter fences.
	float fl_w = rect_sdf(xz, vec2(-236.2, -296.0), vec2(-233.8, -61.0));
	float fl_e = rect_sdf(xz, vec2(233.8, -296.0), vec2(236.2, -61.0));
	float fn_w = rect_sdf(xz, vec2(-236.0, -381.2), vec2(-144.0, -378.8));
	float fn_e = rect_sdf(xz, vec2(144.0, -381.2), vec2(236.0, -378.8));
	float fence_d = min(min(fl_w, fl_e), min(fn_w, fn_e));
	float fence_trim = 1.0 - smoothstep(0.4, 1.8, fence_d);
	col = mix(col, border_earth, fence_trim * 0.60);

	ALBEDO = col;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float half_lambert = dot(NORMAL, LIGHT) * 0.495 + 0.5;
	float lit = clamp(half_lambert * ATTENUATION, 0.0, 1.0);
	vec3 band = texture(ramp_texture, vec2(lit, 0.5)).rgb;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * band * light_gain;
}
