// Upgraded seamless Toon shader for Runway, TaxiPaving asphalt, OperationsApron concrete,
// and painted taxiway markings. Keeps the exact uniform interface (albedo_texture,
// albedo_tint, ramp_texture, light_gain) expected by toon shader tests while applying
// smooth world-space multi-octave grain without rectangular grid lines or pour-bay tiles.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform sampler2D ramp_texture : filter_nearest, repeat_disable;
uniform float light_gain = 1.0;

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 tex_col = texture(albedo_texture, UV).rgb * albedo_tint.rgb;
	// Asphalt strips/pads/runway sample column ASPHALT_U (~0.5047); markings sample MARKING_UV (~0.6083).
	bool is_asphalt = abs(UV.x - 0.5047) < 0.03;
	bool is_concrete = length(UV - vec2(0.078125, 0.95625)) < 0.015;
	vec3 col = tex_col;
	if (is_asphalt) {
		// Smooth out the harsh pyramid-like center-to-edge ramp in the vendor swatch
		// while preserving subtle shoulder edge shading.
		vec3 flat_asphalt = texture(albedo_texture, vec2(UV.x, 0.028)).rgb * albedo_tint.rgb;
		col = mix(flat_asphalt, tex_col, 0.22);

		// Smooth low-contrast world-space multi-octave asphalt grain (<= 2.5%, zero grid seams).
		float n_broad = value_noise(world_pos.xz * 0.035 + vec2(3.1, 7.4));
		float n_fine = value_noise(world_pos.xz * 0.19 + vec2(11.7, 2.9));
		float grain = (n_broad * 0.65 + n_fine * 0.35 - 0.5) * 0.05;
		col *= (1.0 + grain);

		// Subtle wheel-track rubber wear centered along each taxiway/runway band.
		float band_t = clamp((UV.y - 0.0010) / (0.0614 - 0.0010), 0.0, 1.0);
		float gear_l = exp(-pow((band_t - 0.42) * 14.0, 2.0));
		float gear_r = exp(-pow((band_t - 0.58) * 14.0, 2.0));
		float wear = clamp(gear_l + gear_r, 0.0, 1.0) * 0.11;
		col *= (1.0 - wear);
	} else if (is_concrete) {
		float cn_broad = value_noise(world_pos.xz * 0.04 + vec2(8.3, 4.1));
		float cn_fine = value_noise(world_pos.xz * 0.22 + vec2(1.9, 13.5));
		float c_grain = (cn_broad * 0.65 + cn_fine * 0.35 - 0.5) * 0.045;
		col *= (1.0 + c_grain);
	}
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
