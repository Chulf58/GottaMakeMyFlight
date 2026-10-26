class_name IntroDialogue
extends Control
## The intro dialogue a new game opens with while the clock is paused: the
## terminal manager's portrait at the left, overlapping a framed text box, a
## nameplate on the box's top-left and short instructions. Continue or Space
## (also Enter) closes it and emits `dismissed`; PassengerHud then starts the
## clock at 1x. While it is open it is modal: a dim backdrop takes every click
## and wheel event, and _input takes every key, so nothing behind it acts.
## PassengerHud opens it once per session (see should_show).

signal dismissed

const PORTRAIT := preload("res://assets/ui/intro_manager_portrait.png")
const NAME_TEXT := "TERMINAL MANAGER"
const TITLE_TEXT := "Your first day at the airport"
const BODY_TEXT := (
	"Welcome to your new airport! Passengers are on their way, and every one of "
	+ "them has a flight to catch.\n"
	+ "Build them a path: entrance, then check-in, then security, then the gate exit. "
	+ "Number keys pick tools, Space pauses, Shift+1/2/3 sets speed.\n"
	+ "The clock starts when you close this."
)
const CONTINUE_TEXT := "Continue (Space)"
## Sizes at a 1920x1080 screen.
const BOX_SIZE := Vector2(1060.0, 300.0)
const PORTRAIT_SIZE := 520.0
## How much of the portrait's width lies over the box's left edge.
const PORTRAIT_OVERLAP := 210.0
## The box's bottom edge, up from the bottom of the screen: above the build
## bar, the item tray and its status line, so none of them shows under the box.
const BOX_BOTTOM := (
	BuildMenu.MARGIN
	+ BuildMenu.BAR_H
	+ BuildMenu.GAP
	+ BuildMenu.TRAY_H
	+ BuildMenu.STATUS_H
	+ BuildMenu.GAP
)
## Where the body text and the nameplate start, from the box's left edge: just
## right of the portrait figure (the PNG's right part is transparent).
const TEXT_LEFT := 128.0
const NAMEPLATE_SIZE := Vector2(380.0, 74.0)
const GROUP_W := PORTRAIT_SIZE - PORTRAIT_OVERLAP + BOX_SIZE.x
const DIM_COLOR := Color(0.03, 0.04, 0.06, 0.45)
const PAPER_COLOR := Color(0.96, 0.93, 0.86)
const INK_COLOR := Color(0.09, 0.1, 0.15)
const FRAME_COLOR := Color(0.07, 0.08, 0.11)
const GOLD_COLOR := Color(1.0, 0.8, 0.3)
const NAME_COLOR := Color(0.98, 0.95, 0.88)

## Set when PassengerHud opens the intro; it stays set for the rest of the
## process, so a reloaded scene does not show it again.
static var shown_this_session := false

var _done := false
## Holds the portrait, box and nameplate at their 1080p layout; _place moves it
## and scales it down on a smaller screen.
var _group := Control.new()
var _box := Panel.new()
var _nameplate := PanelContainer.new()
var _portrait := TextureRect.new()
var _body := Label.new()
var _continue := Button.new()


## True when a new game should open with the intro: not shown yet this session,
## the HUD belongs to the running scene (a normal launch, not a probe or a test
## that builds the scene by hand) and the PlaytestHook switches are off.
static func should_show(already_shown: bool, in_current_scene: bool, playtest_on: bool) -> bool:
	return not already_shown and in_current_scene and not playtest_on


func _init() -> void:
	name = "IntroDialogue"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events = false
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM_COLOR
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_group.name = "Group"
	_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_group.size = Vector2(GROUP_W, PORTRAIT_SIZE)
	add_child(_group)
	_build_box()
	_build_nameplate()
	# Added last, so it draws over the box's left edge.
	_portrait.name = "Portrait"
	_portrait.texture = PORTRAIT
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.position = Vector2.ZERO
	_portrait.size = Vector2.ONE * PORTRAIT_SIZE
	_group.add_child(_portrait)
	_box.position = Vector2(PORTRAIT_SIZE - PORTRAIT_OVERLAP, PORTRAIT_SIZE - BOX_SIZE.y)
	_box.size = BOX_SIZE
	_nameplate.position = _box.position + Vector2(TEXT_LEFT - 20.0, 22.0 - NAMEPLATE_SIZE.y)
	_nameplate.size = NAMEPLATE_SIZE
	_place()


func _ready() -> void:
	get_viewport().size_changed.connect(_place)
	_place()


## Every key press is taken while the dialogue is open; Space (without Shift),
## Enter and keypad Enter close it. The key is marked handled before closing, so
## the HUD's Space pause toggle never sees the same press.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _done or not visible or key == null or not key.pressed:
		return
	get_viewport().set_input_as_handled()
	if key.echo:
		return
	var space := key.physical_keycode == KEY_SPACE and not key.shift_pressed
	if space or key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
		dismiss()


## Closes the dialogue once; later calls do nothing.
func dismiss() -> void:
	if _done:
		return
	_done = true
	visible = false
	dismissed.emit()


func is_dismissed() -> bool:
	return _done


func body_text() -> String:
	return _body.text


## The on-screen rectangles of the box, nameplate, portrait and Continue button,
## for probes that check the layout.
func part_rects() -> Dictionary:
	return {
		"box": _box.get_global_rect(),
		"nameplate": _nameplate.get_global_rect(),
		"portrait": _portrait.get_global_rect(),
		"continue": _continue.get_global_rect(),
	}


func continue_button() -> Button:
	return _continue


func _build_box() -> void:
	_box.name = "Box"
	_box.add_theme_stylebox_override("panel", _frame_style())
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_group.add_child(_box)
	var inner := Panel.new()
	inner.name = "GoldLine"
	inner.add_theme_stylebox_override("panel", _gold_line_style())
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 10.0
	inner.offset_top = 10.0
	inner.offset_right = -10.0
	inner.offset_bottom = -10.0
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(inner)
	_body.name = "Body"
	_body.text = BODY_TEXT
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_override("font", _bold_font())
	_body.add_theme_font_size_override("font_size", 25)
	_body.add_theme_color_override("font_color", INK_COLOR)
	_body.add_theme_constant_override("line_spacing", 2)
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The portrait covers the box's left edge, so the text starts past it.
	_body.offset_left = TEXT_LEFT
	_body.offset_top = 48.0
	_body.offset_right = -30.0
	_body.offset_bottom = -58.0
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_body)
	_continue.name = "Continue"
	_continue.text = CONTINUE_TEXT
	_continue.focus_mode = Control.FOCUS_NONE
	BuildMenu.style_button(_continue)
	_continue.add_theme_font_size_override("font_size", 18)
	_continue.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_continue.offset_left = -220.0
	_continue.offset_top = -62.0
	_continue.offset_right = -24.0
	_continue.offset_bottom = -20.0
	_continue.pressed.connect(dismiss)
	_box.add_child(_continue)


func _build_nameplate() -> void:
	_nameplate.name = "Nameplate"
	var style := StyleBoxFlat.new()
	style.bg_color = FRAME_COLOR
	style.set_border_width_all(3)
	style.border_color = GOLD_COLOR
	style.set_corner_radius_all(4)
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_nameplate.add_theme_stylebox_override("panel", style)
	_nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_group.add_child(_nameplate)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_nameplate.add_child(column)
	var title := Label.new()
	title.name = "Name"
	title.text = NAME_TEXT
	title.add_theme_font_override("font", _bold_font())
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", NAME_COLOR)
	column.add_child(title)
	var role := Label.new()
	role.name = "Title"
	role.text = TITLE_TEXT
	role.add_theme_font_size_override("font_size", 16)
	role.add_theme_color_override("font_color", GOLD_COLOR)
	column.add_child(role)


## Centres the portrait-plus-box group horizontally, with the box's bottom
## BOX_BOTTOM above the screen bottom (the portrait stands on the same line).
## On a screen narrower or shorter than the 1080p layout the group scales down;
## BOX_BOTTOM stays in screen pixels, because BuildMenu does not scale.
func _place() -> void:
	var screen := get_viewport_rect().size if is_inside_tree() else Vector2(1920.0, 1080.0)
	var fit := minf((screen.x - 32.0) / GROUP_W, (screen.y - BOX_BOTTOM - 20.0) / PORTRAIT_SIZE)
	var group_scale := clampf(fit, 0.4, 1.0)
	_group.scale = Vector2.ONE * group_scale
	_group.position = Vector2(
		roundf((screen.x - GROUP_W * group_scale) / 2.0),
		roundf(screen.y - BOX_BOTTOM - PORTRAIT_SIZE * group_scale)
	)


func _frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER_COLOR
	style.set_border_width_all(8)
	style.border_color = FRAME_COLOR
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.35)
	style.shadow_size = 10
	return style


func _gold_line_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.set_border_width_all(2)
	style.border_color = GOLD_COLOR
	style.set_corner_radius_all(3)
	return style


func _bold_font() -> FontVariation:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 0.7
	return font
