// The inverted-hull toon outline, the next_pass of every toon material. The
// body is in toon_outline_common.gdshaderinc, shared with
// toon_outline_dissolve.gdshader.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, fog_disabled;

#include "res://shaders/toon_outline_common.gdshaderinc"
