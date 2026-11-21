// The soap bubbles of a showering passenger's lather (ShowerFoam): toon-lit
// white soap, each bubble swelling and drifting a little on its own slow loop
// so the lather looks alive. The motion is all here, on the GPU, so it costs
// nothing per frame on the CPU. A bubble's surface moves at most
// (swell + drift * sqrt(1.25)) of its own radius from where it rests
// (ShowerFoam.motion_reach_m mirrors this bound for the tests).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 albedo : source_color = vec3(0.96, 0.98, 1.0);
uniform vec3 shadow_tint : source_color = vec3(0.78, 0.87, 0.97);
uniform vec3 edge_tint : source_color = vec3(0.70, 0.82, 0.96);
uniform vec3 outline_tint : source_color = vec3(0.46, 0.60, 0.78);
uniform sampler2D ramp_texture : filter_nearest, repeat_disable;
uniform float light_gain = 1.0;
uniform float rim = 0.32;
// How much a bubble swells and drifts, as shares of its own radius.
uniform float swell = 0.15;
uniform float drift = 0.35;
// Radians a second of the slowest and the fastest bubble's loop.
uniform float speed_min = 0.8;
uniform float speed_max = 1.5;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	float id = float(INSTANCE_ID);
	float t = TIME * mix(speed_min, speed_max, hash(id)) + hash(id + 17.0) * TAU;
	// The mesh is a unit sphere scaled by the instance transform, so these are
	// shares of the bubble's radius.
	// A slow circle across the ground plane and a smaller bob: at most
	// sqrt(1.25) long.
	vec3 wander = vec3(sin(t), 0.5 * sin(t * 0.7 + 1.9), cos(t));
	VERTEX = VERTEX * (1.0 + swell * sin(t * 1.7 + 2.3)) + drift * wander;
}

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.2);
	float cel_rim = smoothstep(0.55, 0.72, fresnel);
	vec3 col = mix(albedo, edge_tint, fresnel * rim);
	ALBEDO = mix(col, outline_tint, cel_rim * 0.65);
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float half_lambert = dot(NORMAL, LIGHT) * 0.495 + 0.5;
	float lit = clamp(half_lambert * ATTENUATION, 0.0, 1.0);
	float band = texture(ramp_texture, vec2(lit, 0.5)).r;
	// Quantized cel shading tinted toward soft cool soap blue in shadow so bubbles
	// match the Toon Series ramp without going stark grey.
	vec3 ramp_col = mix(shadow_tint, vec3(1.0), band);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * ramp_col * light_gain;
}
