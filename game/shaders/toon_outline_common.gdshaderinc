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
//
// The body shared by toon_outline.gdshader and toon_outline_dissolve.gdshader;
// the second defines DISSOLVE first, so the hull loses the same pixels as the
// surface it outlines (dissolve.gdshaderinc), on top of its own width fade.

uniform vec4 outline_color : source_color = vec4(0.1, 0.1, 0.12, 1.0);
uniform float outline_px = 1.5;
// View depths in metres; requires 0 < fade_start < fade_end.
uniform float fade_start = 60.0;
uniform float fade_end = 240.0;
// Hull fragments thinner than this are discarded, so a zero-width hull does
// not show where it lies on the surface.
uniform float min_px = 0.05;
// View-space back bias (metres at camera, gently scaled with depth) to prevent
// flush or stacked strips (such as Canopy fascia and 10 cm roof ribs) from
// z-fighting into dashes or bleeding through overlying surfaces.
uniform float depth_bias_m = 0.003;

#ifdef DISSOLVE
#define DISSOLVE_HOLES
#include "res://shaders/dissolve.gdshaderinc"
// 0 draws the hull whole, 1 drops every pixel.
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
// World position of the hull vertex before it is pushed out, so the hole
// boxes cut the hull where they cut its surface.
varying vec3 dissolve_world;
#endif

varying float view_depth;

float width_at(float depth) {
	float d = max(depth, fade_start);
	float t = clamp(log(d / fade_start) / log(fade_end / fade_start), 0.0, 1.0);
	return outline_px * (1.0 - smoothstep(0.0, 1.0, t));
}

void vertex() {
#ifdef DISSOLVE
	dissolve_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#endif
	// Hybrid smooth-normal slot: static meshes carrying welded corner normals in
	// CUSTOM0 (a >= 0.5 sentinel; [0.6..1.0] maps miter scale 1.0..1.5) close
	// hard-edged corners while meshes without CUSTOM0 fall back to NORMAL.
	vec3 outline_normal = NORMAL;
	float miter_scale = 1.0;
	if (CUSTOM0.a > 0.5) {
		vec3 decoded = CUSTOM0.xyz * 2.0 - 1.0;
		if (dot(decoded, decoded) > 1e-4) {
			outline_normal = normalize(decoded);
			miter_scale = mix(1.0, 1.5, clamp((CUSTOM0.a - 0.6) / 0.4, 0.0, 1.0));
		}
	}

	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view_depth = -view.z;
	vec4 biased_view = view;
	biased_view.z -= depth_bias_m * (1.0 + max(view_depth, 0.0) * 0.02);
	vec4 clip = PROJECTION_MATRIX * biased_view;

	vec3 view_normal = normalize(MODELVIEW_NORMAL_MATRIX * outline_normal);
	// Exact directional derivative of ndc.xy = clip.xy / clip.w along
	// view_normal (valid for both perspective and orthogonal cameras).
	vec4 dclip = PROJECTION_MATRIX * vec4(view_normal, 0.0);
	float inv_w = 1.0 / max(abs(clip.w), 1e-5);
	vec2 ndc = clip.xy * inv_w;
	vec2 dir_px = (dclip.xy - ndc * dclip.w) * inv_w * VIEWPORT_SIZE;
	float len_px = length(dir_px);

	// Smoothly attenuate normals nearly parallel to the view ray so grazing back
	// faces cannot turn floating-point noise into full-width spikes.
	vec3 ray_dir = (abs(PROJECTION_MATRIX[3][3]) > 0.5)
		? vec3(0.0, 0.0, -1.0)
		: normalize(view.xyz);
	float sin_ray = length(view_normal - ray_dir * dot(view_normal, ray_dir));
	float edge_weight = smoothstep(0.005, 0.03, sin_ray);

	if (len_px > 1e-6 && edge_weight > 0.0) {
		float w_px = width_at(view_depth) * miter_scale * edge_weight;
		vec2 offset_ndc = dir_px / len_px * w_px * 2.0 / VIEWPORT_SIZE;
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
#ifdef DISSOLVE
	if (dissolve_drop(FRAGCOORD.xy, dissolve) || dissolve_in_holes(dissolve_world)) {
		discard;
	}
#endif
	ALBEDO = outline_color.rgb;
}
