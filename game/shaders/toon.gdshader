// The Toon Series surface shader used by every toon material. The body is in
// toon_common.gdshaderinc, shared with toon_dissolve.gdshader.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/toon_common.gdshaderinc"
