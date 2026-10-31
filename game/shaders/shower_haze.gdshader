// The steam that fills a shower cubicle around a showering passenger
// (ShowerFoam's Haze): one box just inside the glass, its walls drawn as
// distinct white wisps that rise and curl (a slow noise field warps the
// pattern, so the wisps bend and swirl as they climb), with clear air between
// them and a soft, faintly blue-grey edge that keeps them readable against
// the pale walls. Its walls are drawn from both sides, so wisps show in front
// of, beside and behind the lather column. A band at face height on every wall
// thins the steam to a light veil, so the eyes and the washing hands stay
// readable; the icons draw over everything anyway (user's pick 2026-10-31:
// "Thicker, visible wisps"). Unshaded alpha with no depth write or shadow, on
// a mesh, never a particle billboard. All the motion is here, on the GPU.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// How much steam is up (0 to 1), per foam: it comes with the lather and
// goes with the rinse.
instance uniform float amount = 0.0;
// The box mesh is centred on its origin; this lifts it into the foam's frame
// (feet at 0).
uniform float centre_y = 1.125;
uniform vec3 colour : source_color = vec3(0.97, 0.98, 1.0);
// The edge of a wisp, a touch darker so the wisps stand out on white walls.
uniform vec3 edge_colour : source_color = vec3(0.62, 0.69, 0.79);
// How opaque a wisp's core gets, and how fast the wisps rise (metres a second).
uniform float density = 0.92;
uniform float rise_speed = 0.16;
// How far (in pattern units) the slow field bends the wisps.
uniform float curl = 2.0;
// The thinned band at face height: its middle, its half height, the half
// width across each wall, and the share of the steam left there.
uniform float face_y = 1.72;
uniform float face_half_y = 0.34;
uniform float face_half_across = 0.26;
uniform float face_veil = 0.1;

varying vec3 local;

void vertex() {
	local = VERTEX + vec3(0.0, centre_y, 0.0);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	// Around the walls (x on the front and back, z on the sides) and up.
	bool side = abs(local.x) > abs(local.z) * 0.95;
	float across = side ? local.z : local.x;
	float around = across + (side ? 3.0 * sign(local.x) : 0.0) + (local.z < 0.0 ? 7.0 : 0.0);
	// Large shapes: about two wisps across a wall, rising.
	vec2 at = vec2(around * 1.7, (local.y - TIME * rise_speed) * 1.2);
	// The slow field that bends them, itself drifting, so they curl.
	vec2 bend = vec2(
		noise(at * 0.7 + vec2(0.0, -TIME * 0.11)), noise(at * 0.7 + vec2(4.7, TIME * 0.09))
	);
	at += (bend - 0.5) * 2.0 * curl;
	float n = noise(at * 1.5) * 0.7 + noise(at * 3.4 + vec2(5.2, 1.3)) * 0.3;
	// High contrast with a soft edge: clear air, then a wisp.
	float wisp = smoothstep(0.42, 0.66, n);
	float core = smoothstep(0.6, 0.86, n);
	// Thinner low down, fuller up where steam gathers.
	float up = mix(0.6, 1.0, smoothstep(0.2, 1.4, local.y));
	float alpha = density * wisp * up * amount;
	// A light veil only over the face and the washing hands.
	vec2 off = vec2(abs(across) / face_half_across, abs(local.y - face_y) / face_half_y);
	float window = 1.0 - smoothstep(0.75, 1.0, max(off.x, off.y));
	alpha *= mix(1.0, face_veil, window);
	ALBEDO = mix(edge_colour, colour, core);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
