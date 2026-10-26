// Inverted-hull outline for the Toon Series look, used as the next_pass of a
// toon material. Unity's CustomToonOutline extrudes by a fixed object-space width
// (0.5 to 2.5 mm), which is below one pixel at the tycoon camera's 12 to 120 m,
// so this version extrudes by a constant number of PIXELS in clip space instead.
// Works for perspective and orthogonal cameras alike.
//
// The width thins with view depth and reaches zero at fade_end (decision
// toon-outline-thins-with-camera-distance-and-fades-out-at-ful). A constant
// 1.5 px is about 0.43 m at 300 m, and the hull broke into notched and dashed
// lines on thin roof strips there. The fade runs on the log of the depth, as
// the camera zooms by a factor per wheel notch. fade_start (60 m) is 10x the
// camera's 6 m closest zoom, so the home view at 80 m keeps about 1.33 px.
// fade_end (240 m) is the nearest ground depth in view at the 300 m farthest
// zoom (height 300 sin 65 deg, bottom frame edge 27.5 deg below the view
// axis), so at full zoom-out nothing near the ground keeps an outline.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, fog_disabled;

uniform vec4 outline_color : source_color = vec4(0.08, 0.08, 0.1, 1.0);
uniform float outline_px = 1.5;
// View depths in metres; requires 0 < fade_start < fade_end.
uniform float fade_start = 60.0;
uniform float fade_end = 240.0;
// Hull fragments thinner than this are discarded, so a zero-width hull does
// not show where it lies on the surface.
uniform float min_px = 0.05;

varying float view_depth;

float width_at(float depth) {
	float d = max(depth, fade_start);
	float t = clamp(log(d / fade_start) / log(fade_end / fade_start), 0.0, 1.0);
	return outline_px * (1.0 - smoothstep(0.0, 1.0, t));
}

void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view_depth = -view.z;
	vec4 clip = PROJECTION_MATRIX * view;
	vec3 view_normal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	// Direction of the normal on screen, measured in pixels so a non-square
	// viewport still gets the same thickness horizontally and vertically.
	vec2 dir_px = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy * VIEWPORT_SIZE;
	float len_px = length(dir_px);
	if (len_px > 1e-6) {
		vec2 offset_ndc = dir_px / len_px * width_at(view_depth) * 2.0 / VIEWPORT_SIZE;
		clip.xy += offset_ndc * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	// The width is checked again at the fragment's own depth: a triangle with
	// a near and a far vertex would otherwise interpolate a width that
	// survives past fade_end.
	if (width_at(view_depth) < min_px) {
		discard;
	}
	ALBEDO = outline_color.rgb;
}
