// The soap bubbles of a showering passenger's lather (ShowerFoam): toon-lit
// white soap, each bubble swelling and drifting a little on its own slow loop
// so the lather looks alive. The motion is all here, on the GPU, so it costs
// nothing per frame on the CPU. A bubble's surface moves at most
// (swell + drift * sqrt(1.25)) of its own radius from where it rests
// (ShowerFoam.motion_reach_m mirrors this bound for the tests).
shader_type spatial;
render_mode diffuse_toon, specular_toon;

uniform vec3 albedo : source_color = vec3(0.97, 0.98, 1.0);
uniform float roughness = 0.3;
uniform float rim = 0.35;
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
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	RIM = rim;
	RIM_TINT = 0.5;
}
