// The shell roof's light panels (Lights_Upper) with the roof's dither
// dissolve. It draws what their StandardMaterial3D (tp_lights.tres: unshaded,
// an albedo texture, white albedo colour) draws, so ShellView can swap it in
// for its own copy and fade the panels with the roof.
shader_type spatial;
render_mode unshaded;

#include "res://shaders/dissolve.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
// 0 draws the panels whole, 1 drops every pixel.
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	if (dissolve_drop(FRAGCOORD.xy, dissolve)) {
		discard;
	}
	ALBEDO = texture(albedo_texture, UV).rgb * albedo_color.rgb;
}
