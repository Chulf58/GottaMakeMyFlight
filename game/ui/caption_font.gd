class_name CaptionFont
extends RefCounted
## The font every in-world Label3D caption draws with: the HUD theme's own
## Nunito (ui/hud_theme.tres, its default_font FontVariation), so the world
## captions match the HUD (decision hud-theme-file-game-ui-hud-theme-tres-
## nunito-font-set-on-eac, board item L2). The same resource the theme holds,
## never a second copy of the font file.
##
## Layout code that measures a caption's text (declutter, label cards) measures
## it in font(), the font the caption draws with.

const HUD_THEME := "res://ui/hud_theme.tres"

static var _font: Font


## The HUD theme's default font. Loud when the theme or its font is missing:
## the error names the theme and the engine fallback font is used instead.
static func font() -> Font:
	if _font == null:
		var theme := load(HUD_THEME) as Theme
		if theme != null:
			_font = theme.default_font
		if _font == null:
			push_error("CaptionFont: %s has no default_font; captions use the fallback" % HUD_THEME)
			_font = ThemeDB.fallback_font
	return _font


## Sets `label` to draw in font(), and returns it.
static func apply(label: Label3D) -> Label3D:
	label.font = font()
	return label
