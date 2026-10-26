// Screen-door dissolve for the Toon shell's roof (Shell 3/4, decision
// toon-terminal-shell-design-extracted-shell-glb-authored-shel part 4): a 4x4
// ordered (Bayer) dither on the pixel grid. The surface, its outline hull and
// the light panels all call dissolve_drop() with the same pixel and the same
// level, so they lose the same pixels. Thresholds run from 0.5/16 to 15.5/16:
// level 0 drops nothing and level 1 drops every fragment.
//
// With DISSOLVE_HOLES defined it also declares up to 8 world-space hole boxes
// (the first hole_count are used; 0 by default, as uniform arrays take no
// default values) and dissolve_in_holes(): ShellView uses them to drop an
// open doorway's lintel from its door bay and the porch letter sign from Lot.
// Keep the array size equal to ShellView.HOLE_SLOTS.

const int DISSOLVE_BAYER[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};

#ifdef DISSOLVE_HOLES
uniform int hole_count = 0;
uniform vec3 hole_min[8];
uniform vec3 hole_max[8];

// Whether `p` lies in any used hole box (lo <= p <= hi on every axis).
bool dissolve_in_holes(vec3 p) {
	for (int i = 0; i < min(hole_count, 8); i++) {
		if (all(greaterThanEqual(p, hole_min[i])) && all(lessThanEqual(p, hole_max[i]))) {
			return true;
		}
	}
	return false;
}
#endif

bool dissolve_drop(vec2 fragcoord, float level) {
	ivec2 cell = ivec2(floor(fragcoord)) % 4;
	float threshold = (float(DISSOLVE_BAYER[cell.y * 4 + cell.x]) + 0.5) / 16.0;
	return threshold < level;
}
