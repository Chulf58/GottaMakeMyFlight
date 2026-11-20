class_name PaTicker
extends PanelContainer
## Single-line unobtrusive PA subtitle card anchored bottom-centre above
## BuildMenu (decisions calm-cozy-default-view and demo-audio-pa-announcer-
## and-sound-jokes-e612caf3-procedural). Click-through, never stacks, fades
## in/holds/fades out cleanly, and clears immediately when modals open or on load.

const FADE_IN_S := 0.20
const HOLD_S := 4.0
const FADE_OUT_S := 0.45
const MAX_WIDTH := float(HudLayout.SHEET_W)
const EDGE_MARGIN := float(HudLayout.MARGIN * 2)
const DEFAULT_BOTTOM := BuildMenu.MARGIN + BuildMenu.BAR_H + HudLayout.GAP
const FALLBACK_PAD_X := 24.0

## Optional callable returning bottom offset in px above viewport bottom.
var bottom_provider := Callable()
## Optional callable returning true while a modal covers or suppresses the ticker.
var modal_check := Callable()

var _label := Label.new()
var _tween: Tween


func _init() -> void:
	name = "PaTicker"
	theme = BuildMenu.HUD_THEME
	theme_type_variation = &"HudTopCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	modulate.a = 0.0
	_label.name = "PAText"
	_label.theme_type_variation = &"HudCardName"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func _ready() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(place):
		vp.size_changed.connect(place)
	_connect_audio()
	place()


func _exit_tree() -> void:
	_kill_tween()
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(place):
		vp.size_changed.disconnect(place)
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_signal(&"pa_announced"):
		if audio.pa_announced.is_connected(show_announcement):
			audio.pa_announced.disconnect(show_announcement)


## Shows `text` with fade-in, hold and fade-out unless suppressed by a modal.
func show_announcement(text: String) -> void:
	if text == "" or (modal_check.is_valid() and bool(modal_check.call())):
		return
	_kill_tween()
	_label.text = text
	visible = true
	modulate.a = 0.0
	place()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "modulate:a", 1.0, FADE_IN_S)
	_tween.tween_interval(HOLD_S)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_S)
	_tween.tween_callback(_finish_fade)


## Immediately stops any tween and hides the ticker.
func clear_now() -> void:
	_kill_tween()
	visible = false
	modulate.a = 0.0
	_label.text = ""


## Updates the bottom-centre anchors and clamped width.
func place() -> void:
	var vp := get_viewport()
	var view_w := vp.get_visible_rect().size.x if vp != null else 1536.0
	var max_w := maxf(120.0, minf(MAX_WIDTH, view_w - EDGE_MARGIN))
	var width := max_w
	if _label.text != "":
		var font := _label.get_theme_font("font")
		var font_size := _label.get_theme_font_size("font_size")
		if font != null and font_size > 0:
			var text_w := (
				font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			)
			width = clampf(ceilf(text_w + _panel_pad_x() + 12.0), 120.0, max_w)
	var bottom := DEFAULT_BOTTOM
	if bottom_provider.is_valid():
		bottom = float(bottom_provider.call())
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -width * 0.5
	offset_right = width * 0.5
	offset_top = -bottom
	offset_bottom = -bottom
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN


## Returns the label's current text, for tests.
func text_shown() -> String:
	return _label.text


func _connect_audio() -> void:
	var audio := get_node_or_null("/root/GameAudio")
	if audio != null and audio.has_signal(&"pa_announced"):
		if not audio.pa_announced.is_connected(show_announcement):
			audio.pa_announced.connect(show_announcement)


func _panel_pad_x() -> float:
	var box := get_theme_stylebox("panel")
	if box == null:
		return FALLBACK_PAD_X
	return box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT)


func _kill_tween() -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	_tween = null


func _finish_fade() -> void:
	_tween = null
	visible = false
	_label.text = ""
