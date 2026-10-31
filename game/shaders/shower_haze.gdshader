// The steam that fills a shower cubicle around a showering passenger
// (ShowerFoam's Haze): one box just inside the glass, drawn as soft
// translucent white wisps that drift sideways and rise slowly, so the glass
// reads as steamy. Its walls are drawn from both sides (the far walls show
// behind the body). A band at face height on every wall is kept almost clear,
// so the face and the washing hands stay readable; the icons draw over
// everything anyway. Unshaded alpha with no depth write or shadow, on a mesh,
// never a particle billboard. All the motion is here, on the GPU.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// How much steam is up (0 to 1), per foam: it comes with the lather and
// goes with the rinse.
instance uniform float amount = 0.0;
// The box mesh is centred on its origin; this lifts it into the foam's frame
// (feet at 0).
uniform float centre_y = 1.125;
uniform vec3 colour : source_color = vec3(0.95, 0.97, 1.0);
// The thickest the steam gets, and how fast its wisps rise (metres a second).
uniform float density = 0.8;
uniform float rise_speed = 0.1;
// The clear band at face height: its middle and its half height, and the
// half width it is clear across each wall.
uniform float face_y = 1.72;
uniform float face_half_y = 0.34;
uniform float face_half_across = 0.26;

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
	vec2 at = vec2(around * 3.0 + 0.4 * sin(TIME * 0.35), local.y * 2.2 - TIME * rise_speed * 2.2);
	float wisp = noise(at * 1.6) * 0.6 + noise(at * 3.7 + vec2(5.2, 1.3)) * 0.4;
	wisp = smoothstep(0.25, 0.85, wisp);
	// Thinner at the floor, thicker up where it gathers.
	float up = mix(0.45, 1.0, smoothstep(0.2, 1.4, local.y));
	float alpha = density * mix(0.4, 1.0, wisp) * up * amount;
	// Keep the face and the washing hands clear.
	vec2 off = vec2(abs(across) / face_half_across, abs(local.y - face_y) / face_half_y);
	float window = 1.0 - smoothstep(0.75, 1.0, max(off.x, off.y));
	alpha *= 1.0 - 0.9 * window;
	ALBEDO = colour;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
