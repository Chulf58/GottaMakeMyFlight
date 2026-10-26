// Screen-door dissolve for the Toon shell's roof (Shell 3/4, decision
// toon-terminal-shell-design-extracted-shell-glb-authored-shel part 4): a 4x4
// ordered (Bayer) dither on the pixel grid. The surface, its outline hull and
// the light panels all call dissolve_drop() with the same pixel and the same
// level, so they lose the same pixels. Thresholds run from 0.5/16 to 15.5/16:
// level 0 drops nothing and level 1 drops every fragment.

const int DISSOLVE_BAYER[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};

bool dissolve_drop(vec2 fragcoord, float level) {
	ivec2 cell = ivec2(floor(fragcoord)) % 4;
	float threshold = (float(DISSOLVE_BAYER[cell.y * 4 + cell.x]) + 0.5) / 16.0;
	return threshold < level;
}
