// Toon Series look, rebuilt for Godot from the Unity CustomToon shader.
// Colour comes from the shared palette atlas. Direct light is quantised by the
// vendor's 3-step ramp texture (0, 0.49, 1.0), looked up at the half-Lambert
// term times the shadow attenuation, so cast shadows fall into the dark band.
// Ambient light stays Godot's own and keeps shadowed sides from going black.
// No specular and no metallic: the look is flat colour blocks.
//
// The body shared by toon.gdshader and toon_dissolve.gdshader; the second
// defines DISSOLVE first and gets the shell roof's dither (dissolve.gdshaderinc).
// Only the dissolve variant has a discard, so every other toon material keeps
// the plain opaque path.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0);
// The ramp is a lookup table, not a colour, so it is sampled as linear data.
uniform sampler2D ramp_texture : filter_nearest, repeat_disable;
uniform float light_gain = 1.0;

#ifdef DISSOLVE
#include "res://shaders/dissolve.gdshaderinc"
// 0 draws the surface whole, 1 drops every pixel.
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
#endif

void fragment() {
#ifdef DISSOLVE
	if (dissolve_drop(FRAGCOORD.xy, dissolve)) {
		discard;
	}
#endif
	ALBEDO = texture(albedo_texture, UV).rgb * albedo_tint.rgb;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float half_lambert = dot(NORMAL, LIGHT) * 0.495 + 0.5;
	float lit = clamp(half_lambert * ATTENUATION, 0.0, 1.0);
	vec3 band = texture(ramp_texture, vec2(lit, 0.5)).rgb;
	// LIGHT_COLOR carries a factor of PI for physically based models; divide it out
	// so a fully lit face receives the light's colour times its energy.
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * band * light_gain;
}
