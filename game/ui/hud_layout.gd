class_name HudLayout
extends RefCounted
## The HUD's one spacing grid, size family and type scale, in layout px
## (1536x864: a 1920x1080 window at the canvas_items stretch of 1.25). Every
## HUD window places itself from these numbers (decision
## hud-grid-and-rails-one-spacing-grid-centred-top-row-right-ra, part 1); the
## corner radius and border widths live in ui/hud_theme.tres. Constants, and the
## one rule that fits a text to a fixed slot (wrap, then one size step down).

## The grid step: every margin, gap, height and width is a multiple of it.
const UNIT := 8
## Distance from every screen edge to the nearest window.
const MARGIN := 16
## Space between windows inside one group.
const GAP := 8
## Space between two groups of windows.
const GROUP_GAP := 16

## Heights.
const CHIP_H := 32
const BUTTON_H := 40
const BAR_H := 52
const TRAY_H := 150

## Widths, by role.
## A toggle button: the top row's Build mode sign, Runway and Offers, and the
## top-left column's Mood, Departures and Hints.
const TOGGLE_W := 176
const MONEY_W := 224
## A list that opens under the top-left column, such as Departures.
const LIST_W := 304
## The right rail: the clock panel and the alert and result cards under it.
const RAIL_W := 440
const SHEET_W := 560
const TRAY_W := 640

## The type scale, in px.
const CAPTION := 14
const BODY := 16
const TITLE := 18
const PANEL_TITLE := 22
const FIGURE := 24
const TYPE_SCALE: Array[int] = [CAPTION, BODY, TITLE, PANEL_TITLE, FIGURE]

## One step under CAPTION. Never a theme size: only the fit rule below gives it,
## to text already at CAPTION that must fit a fixed slot (decision
## build-menu-card-names-wrap-to-two-lines-then-shrink-a-font-s).
const FIT_STEP := 12


## The size one step under `size`: the type scale's next size down, or FIT_STEP
## under CAPTION.
static func step_down(size: int) -> int:
	for i in range(TYPE_SCALE.size() - 1, -1, -1):
		if TYPE_SCALE[i] < size:
			return TYPE_SCALE[i]
	return FIT_STEP


## How many lines `text` takes in `font` at `size` when it wraps at word bounds
## within `width`, as a Label with AUTOWRAP_WORD_SMART breaks it.
static func line_count(text: String, font: Font, size: int, width: float) -> int:
	var paragraph := TextParagraph.new()
	paragraph.break_flags = (
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	)
	paragraph.width = width
	paragraph.add_string(text, font, size)
	return paragraph.get_line_count()


## The size for `text` in a slot `width` wide that holds `lines` lines: `base`
## when it fits there with no word broken in two, otherwise one step down (the
## wrap-then-shrink rule).
static func fit_size(text: String, font: Font, base: int, width: float, lines: int) -> int:
	if line_count(text, font, base, width) <= lines and widest_word(text, font, base) <= width:
		return base
	return step_down(base)


## The width of the widest word of `text` in `font` at `size`.
static func widest_word(text: String, font: Font, size: int) -> float:
	var widest := 0.0
	for word in text.split(" ", false):
		widest = maxf(widest, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	return widest
