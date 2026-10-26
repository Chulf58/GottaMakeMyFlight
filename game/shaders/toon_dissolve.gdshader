// The toon surface with the shell roof's dither dissolve. Only ShellView's
// own material copies use it; see toon_common.gdshaderinc and
// dissolve.gdshaderinc.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#define DISSOLVE
#include "res://shaders/toon_common.gdshaderinc"
