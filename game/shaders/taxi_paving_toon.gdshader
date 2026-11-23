// Upgraded Toon shader for TaxiPaving asphalt and painted taxiway markings.
// Keeps the exact uniform interface (albedo_texture, albedo_tint, ramp_texture,
// light_gain) expected by toon.gdshader tests while layering crisp Toon concrete/
// asphalt slab seams, subtle pour-bay tonal variation, and smoothed band edges
// that remove the harsh diagonal ridge crease at mitred T-junctions.
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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 tex_col = texture(albedo_texture, UV).rgb * albedo_tint.rgb;
	// Asphalt strips/pads sample column ASPHALT_U (~0.5047); markings sample MARKING_UV (~0.6083).
	bool is_asphalt = abs(UV.x - 0.5047) < 0.03;
	vec3 col = tex_col;
	if (is_asphalt) {
		// Smooth out the harsh pyramid-like center-to-edge ramp in the vendor swatch
		// while preserving subtle shoulder edge shading.
		vec3 flat_asphalt = texture(albedo_texture, vec2(UV.x, 0.028)).rgb * albedo_tint.rgb;
		col = mix(flat_asphalt, tex_col, 0.22);

		// Subtle 16 m concrete/asphalt pour-bay tonal variation.
		vec2 bay_id = floor(world_pos.xz / 16.0);
		float bay_tone = (hash21(bay_id) - 0.5) * 0.055;
		col *= (1.0 + bay_tone);

		// Anti-aliased 8 m expansion joint grid (fades smoothly at far zoom).
		float cam_dist = length(CAMERA_POSITION_WORLD.xz - world_pos.xz);
		float seam_fade = 1.0 - smoothstep(110.0, 260.0, cam_dist);
		vec2 grid = abs(fract(world_pos.xz / 8.0 - 0.5) - 0.5) * 8.0;
		vec2 fw = max(fwidth(world_pos.xz), vec2(0.02));
		float seam_x = 1.0 - smoothstep(0.04, 0.04 + fw.x * 1.4, grid.x);
		float seam_z = 1.0 - smoothstep(0.04, 0.04 + fw.y * 1.4, grid.y);
		float seam = max(seam_x, seam_z) * seam_fade;
		col *= mix(1.0, 0.87, seam);

		// Subtle wheel-track rubber wear centered along each 30 m taxiway band.
		float band_t = clamp((UV.y - 0.0010) / (0.0614 - 0.0010), 0.0, 1.0);
		float gear_l = exp(-pow((band_t - 0.42) * 14.0, 2.0));
		float gear_r = exp(-pow((band_t - 0.58) * 14.0, 2.0));
		float wear = clamp(gear_l + gear_r, 0.0, 1.0) * 0.11;
		col *= (1.0 - wear);
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
