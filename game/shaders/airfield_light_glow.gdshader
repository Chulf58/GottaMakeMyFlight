// Soft unshaded additive billboard glow halo for airfield edge/threshold/PAPI lights.
// Driven by MultiMesh per-instance COLOR so one draw call lights the whole airfield.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

void vertex() {
	// Camera-facing spherical billboard preserving local quad scale.
	vec3 right = vec3(MODEL_MATRIX[0][0], MODEL_MATRIX[0][1], MODEL_MATRIX[0][2]);
	vec3 up = vec3(MODEL_MATRIX[1][0], MODEL_MATRIX[1][1], MODEL_MATRIX[1][2]);
	float sx = length(right);
	float sy = length(up);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * sx, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * sy, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz, 0.0),
		MODEL_MATRIX[3]
	);
}

void fragment() {
	vec2 d = UV * 2.0 - vec2(1.0);
	float r2 = dot(d, d);
	float halo = exp(-r2 * 5.0) * smoothstep(1.0, 0.25, sqrt(r2));
	float core = exp(-r2 * 18.0);
	ALBEDO = COLOR.rgb * (core * 1.4 + halo * 0.65);
	ALPHA = clamp((halo * 0.52 + core * 0.85) * COLOR.a, 0.0, 1.0);
}
