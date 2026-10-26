// The toon outline with the shell roof's dither dissolve, the next_pass of a
// toon_dissolve material. Same pixels, same level as the surface; see
// toon_outline_common.gdshaderinc and dissolve.gdshaderinc.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, fog_disabled;

#define DISSOLVE
#include "res://shaders/toon_outline_common.gdshaderinc"
