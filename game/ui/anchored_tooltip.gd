class_name AnchoredTooltip
extends PanelContainer
## One cream HUD card (decision hud-look-warm-cozy-cream-cards-with-a-dark-outline-
## toon-pale: the theme's PanelContainer card, dark navy text) that HoverTarget
## shows beside the hovered or pinned target's screen rect. place() puts it right
## of the rect, else left, below or above, inside the screen by HudLayout.MARGIN
## and clear of the rects it is told to avoid (the HUD rails and cards); with no
## free side it is kept inside the screen. The card ignores the mouse, so it never
## blocks the hover or a click under it.

const HUD_THEME := preload("res://ui/hud_theme.tres")
## The card's widest; longer text wraps.
const MAX_W := 320.0

var _label: Label


func _init() -> void:
	name = "AnchoredTooltip"
	theme = HUD_THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override(&"font_size", HudLayout.BODY)
	add_child(_label)


func text() -> String:
	return _label.text


## Shows `words` beside `anchor` (screen px), off every rect in `avoid`.
func show_at(words: String, anchor: Rect2, avoid: Array[Rect2]) -> void:
	_apply_words(words)
	var screen := get_viewport_rect() if is_inside_tree() else Rect2(Vector2.ZERO, size)
	position = place(anchor, size, screen, avoid)
	visible = true


## Shows `words` in the lower-right corner of the viewport, clearing BottomDocks
## (CategoryBar, BuildTray, and visible RIGHT_FLOOR_GROUP inspect cards).
func show_bottom_right(
	words: String, bar_width := 0.0, tray_open := false, stack_top := 0.0, ignore: Control = null
) -> void:
	_apply_words(words)
	var screen := get_viewport_rect() if is_inside_tree() else Rect2(Vector2.ZERO, size)
	position = BottomDocks.right_corner_position(
		get_tree(), screen.size, size, bar_width, tray_open, stack_top, ignore
	)
	visible = true


func _apply_words(words: String) -> void:
	if _label.text != words:
		_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_label.custom_minimum_size = Vector2.ZERO
		_label.text = words
		if _label.get_minimum_size().x > MAX_W:
			var style := get_theme_stylebox(&"panel")
			var pad := style.get_minimum_size() if style != null else Vector2.ZERO
			size = Vector2(MAX_W + pad.x, 0.0)
			_label.custom_minimum_size = Vector2(MAX_W, 0.0)
			_label.size = Vector2(MAX_W, 0.0)
			_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	size = get_combined_minimum_size()


func hide_tip() -> void:
	visible = false


## Where a card of `card` size goes in the lower-right corner of `screen`,
## `bottom_offset` px above the bottom edge and clamped inside `screen`.
static func place_bottom_right(
	card: Vector2, screen: Rect2, bottom_offset := float(HudLayout.MARGIN)
) -> Vector2:
	var max_x := maxf(screen.end.x - card.x, screen.position.x)
	var min_x := minf(screen.position.x + float(HudLayout.MARGIN), max_x)
	var x := clampf(screen.end.x - float(HudLayout.MARGIN) - card.x, min_x, max_x)
	var max_y := maxf(screen.end.y - card.y, screen.position.y)
	var min_y := minf(screen.position.y + float(HudLayout.MARGIN), max_y)
	var y := clampf(screen.end.y - bottom_offset - card.y, min_y, max_y)
	return Vector2(x, y)


## Where a card of `card` size goes beside `anchor`: the first side (right, left,
## below, above) that fits inside `screen` less HudLayout.MARGIN and meets no
## rect in `avoid`; else the first side that fits the screen; else the right side
## clamped into the screen.
static func place(anchor: Rect2, card: Vector2, screen: Rect2, avoid: Array[Rect2]) -> Vector2:
	var room := screen.grow(-HudLayout.MARGIN)
	var mid := anchor.get_center()
	var gap := float(HudLayout.GAP)
	var sides: Array[Vector2] = [
		Vector2(anchor.end.x + gap, mid.y - card.y / 2.0),
		Vector2(anchor.position.x - gap - card.x, mid.y - card.y / 2.0),
		Vector2(mid.x - card.x / 2.0, anchor.end.y + gap),
		Vector2(mid.x - card.x / 2.0, anchor.position.y - gap - card.y),
	]
	var fitting: Array[Vector2] = []
	for at in sides:
		if room.encloses(Rect2(at, card)):
			fitting.append(at)
	for at in fitting:
		if not _meets(Rect2(at, card), avoid):
			return at
	if not fitting.is_empty():
		return fitting[0]
	var low := room.position
	var high := (room.end - card).max(low)
	return sides[0].clamp(low, high)


static func _meets(card: Rect2, avoid: Array[Rect2]) -> bool:
	for rect in avoid:
		if card.intersects(rect):
			return true
	return false
