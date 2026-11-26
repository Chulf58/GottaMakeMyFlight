class_name IntroDialogue
extends Control
## The intro dialogue a new game opens with while the clock is paused: the
## terminal manager's portrait at the left, overlapping a framed text box, a
## nameplate on the box's top-left and short instructions. Continue or Space
## (also Enter) closes it and emits `dismissed`; PassengerHud then starts the
## clock at 1x. While it is open it is modal: a dim backdrop takes every click
## and wheel event, and _input takes every key, so nothing behind it acts.
## PassengerHud opens it once per session (see should_show).
##
## The offer form (the major incident panel's) swaps Continue for Accept and
## Decline: choosing emits `chosen(accepted)` and then closes as Continue does.
## No key chooses for the player, so a stray Space cannot accept an offer.

signal dismissed
## The offer form only: the player picked Accept (true) or Decline (false).
signal chosen(accepted: bool)

## Who speaks from the portrait and nameplate (decision the-airline-s-opening-
## phone-call-shows-a-new-gotta-air-stati): the airport's terminal manager by
## default, or Gotta Air's station manager for airline calls.
enum Speaker { TERMINAL_MANAGER, GOTTA_AIR }

const PORTRAIT := preload("res://assets/ui/intro_manager_portrait.png")
const GOTTA_AIR_PORTRAIT := preload("res://assets/ui/station_manager_portrait.png")
const ICON_CHECKIN := preload("res://assets/ui/icons/check_in.svg")
const ICON_SECURITY := preload("res://assets/ui/icons/security.svg")
const ICON_STAFF := preload("res://assets/ui/icons/staff.svg")
## Typewriter reveal speed in characters per second.
const TYPEWRITER_CHARS_PER_SEC := 48.0
const CHIP_ICON_SIZE := 18.0
const BEAT_PILL_W := 68.0
## The Continue key's name, a placeholder in the button.
const CONTINUE_KEY := "Space"
## The speed keys' names, a placeholder in the intro text.
const SPEED_KEYS_TEXT := "Shift+1/2/3"
## Sizes at a 1920x1080 screen.
const BOX_SIZE := Vector2(1060.0, 300.0)
## The tallest the box grows to fit its text; a longer body scrolls inside it.
## At 1080p its top then sits 120 px below the screen top, so the nameplate
## above it stays clear of the edge.
const MAX_BOX_H := 640.0
## The least the group scales to on a small screen; the box height is capped so
## that, at this scale, the box and its nameplate still fit above the build bar.
const MIN_SCALE := 0.4
## Space kept above the nameplate and beside the group on a small screen.
const EDGE_GAP := 20.0
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
## How far the nameplate stands up out of the box's top edge.
const NAMEPLATE_RISE := NAMEPLATE_SIZE.y - 22.0
## The body's margins inside the box. Its bottom margin holds the button row
## with a gap, so the buttons always sit below the last line.
const BODY_TOP := 48.0
const BODY_RIGHT := 30.0
const BODY_BOTTOM := 72.0
const GROUP_W := PORTRAIT_SIZE - PORTRAIT_OVERLAP + BOX_SIZE.x
const DIM_COLOR := Color(0.03, 0.04, 0.06, 0.45)

## Set when PassengerHud opens the intro; it stays set for the rest of the
## process, so a reloaded scene does not show it again.
static var shown_this_session := false

var _done := false
var _title_text := ""
var _body_text := ""
var _beats: Array[String] = []
var _beat_index := 0
var _chips: Array[Dictionary] = []
var _footer_text := ""
var _action_label := ""
var _action_callback := Callable()
var _typewriter_enabled := false
var _revealing := false
var _reveal_progress := 0.0
var _bob_time := 0.0
var _entrance_tween: Tween
## The height the caller asked for: the box is never shorter.
var _box_height := BOX_SIZE.y
var _offer := false
var _speaker := Speaker.TERMINAL_MANAGER
## Holds the portrait, box and nameplate at their 1080p layout; _place moves it
## and scales it down on a smaller screen.
var _group := Control.new()
var _box := Panel.new()
var _nameplate := PanelContainer.new()
var _beat_pill_wrap := PanelContainer.new()
var _beat_pill := Label.new()
var _portrait := TextureRect.new()
var _body_scroll := ScrollContainer.new()
var _body := Label.new()
var _chips_row := HFlowContainer.new()
var _footer := Label.new()
var _continue := Button.new()
var _action_btn: Button
var _accept: Button
var _decline: Button


## True when a new game should open with the intro: not shown yet this session,
## the HUD belongs to the running scene (a normal launch, not a probe or a test
## that builds the scene by hand), the PlaytestHook switches are off and this
## boot is not loading a save (GameBoot.load_path).
static func should_show(
	already_shown: bool, in_current_scene: bool, playtest_on: bool, boot_load := false
) -> bool:
	return not already_shown and in_current_scene and not playtest_on and not boot_load


## The first-day intro by default; UnlockGuide passes its own title, body and a
## taller box for a new tier's dialog, and `speaker` swaps the portrait and
## nameplate (GOTTA_AIR for the airline's opening call). The box grows upward
## from its fixed bottom edge: `box_height` is its least height, and a longer
## text grows it up to MAX_BOX_H, past which the text scrolls (board T9).
## `offer` swaps Continue for Accept and Decline. An empty title or body is the
## intro's own text, in the player's words.
func _init(
	title_text := "",
	body_text := "",
	box_height := BOX_SIZE.y,
	offer := false,
	speaker := Speaker.TERMINAL_MANAGER,
	options := {}
) -> void:
	var default_intro := title_text == "" and body_text == "" and options.is_empty()
	_title_text = title_text if title_text != "" else tr("Your first day at the airport")
	_box_height = box_height
	_offer = offer
	_speaker = speaker
	_init_content(default_intro, body_text, options)
	name = "IntroDialogue"
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = BuildMenu.HUD_THEME
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
	_portrait.texture = _speaker_portrait()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.position = Vector2.ZERO
	_portrait.size = Vector2.ONE * PORTRAIT_SIZE
	_portrait.pivot_offset = Vector2(PORTRAIT_SIZE * 0.5, PORTRAIT_SIZE)
	_group.add_child(_portrait)
	_nameplate.size = NAMEPLATE_SIZE
	_set_box_height(_box_height)
	_place()


func _ready() -> void:
	get_viewport().size_changed.connect(_refit)
	_fit_box()
	_place()
	_play_entrance_pop()


func _exit_tree() -> void:
	_kill_entrance_tween()
	_reset_portrait_pose()


func _process(delta: float) -> void:
	if _done or not visible or not _revealing:
		return
	var total := _body.get_total_character_count()
	if total <= 0:
		finish_reveal()
		return
	_reveal_progress += delta * TYPEWRITER_CHARS_PER_SEC
	var next_chars := mini(total, int(floor(_reveal_progress)))
	if next_chars > _body.visible_characters:
		_body.visible_characters = next_chars
		_play_voice_blip()
	_bob_time += delta
	var wave := sin(_bob_time * 16.0)
	_portrait.pivot_offset = Vector2(PORTRAIT_SIZE * 0.5, PORTRAIT_SIZE)
	_portrait.scale = Vector2(1.0 + 0.025 * wave, 1.0 - 0.03 * wave)
	_portrait.position.y = -absf(wave) * 5.0
	if next_chars >= total:
		finish_reveal()


func _gui_input(event: InputEvent) -> void:
	if _done or not visible:
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _box.get_global_rect().has_point(click.global_position):
		return
	accept_event()
	if _revealing:
		finish_reveal()
	elif not _offer:
		_advance_or_dismiss()


## Every key press is taken while the dialogue is open, except the bare quick
## save and quick load keys, which pass on to SaveGame (decision quicksave-f5-
## and-quickload-f8-work-while-a-dialog-is-open). Space (without Shift), Enter
## and keypad Enter skip reveal first, advance beats, then close it.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _done or not visible or key == null or not key.pressed:
		return
	if _is_quick_key(key):
		return
	get_viewport().set_input_as_handled()
	if key.echo:
		return
	var space := key.physical_keycode == KEY_SPACE and not key.shift_pressed
	if not (space or key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]):
		return
	if _revealing:
		finish_reveal()
	elif not _offer:
		_advance_or_dismiss()


## A first press of F5 or F8 with no modifier: the keys SaveGame answers (it
## ignores a held key's echoes and a modified one).
static func _is_quick_key(key: InputEventKey) -> bool:
	if key.echo or key.ctrl_pressed or key.alt_pressed or key.shift_pressed or key.meta_pressed:
		return false
	return key.keycode in [SaveGame.QUICK_SAVE_KEY, SaveGame.QUICK_LOAD_KEY]


## Closes the dialogue once; later calls do nothing.
func dismiss() -> void:
	if _done:
		return
	_done = true
	_revealing = false
	_kill_entrance_tween()
	_reset_portrait_pose()
	visible = false
	dismissed.emit()


func is_dismissed() -> bool:
	return _done


## The offer form's answer: emits chosen(accepted), then closes. Does nothing
## once closed, or on a dialogue that is not an offer.
func choose(accepted: bool) -> void:
	if _done or not _offer:
		return
	chosen.emit(accepted)
	dismiss()


func body_text() -> String:
	return _body.text


func beats() -> Array[String]:
	return _beats.duplicate()


func beat_index() -> int:
	return _beat_index


func is_revealing() -> bool:
	return _revealing


func finish_reveal() -> void:
	_revealing = false
	_body.visible_characters = -1
	_reset_portrait_pose()


func speaker() -> Speaker:
	return _speaker


## True when the body text is taller than its area in the box, so it scrolls.
func scrolls() -> bool:
	return _body.size.y > _body_scroll.size.y + 0.5


## The on-screen rectangles of the box, nameplate, portrait and Continue button,
## for probes that check the layout. "body" is the visible body area and "text"
## the whole body text, which is taller than "body" when it scrolls.
func part_rects() -> Dictionary:
	return {
		"box": _box.get_global_rect(),
		"body": _body_scroll.get_global_rect(),
		"text": _body.get_global_rect(),
		"nameplate": _nameplate.get_global_rect(),
		"portrait": _portrait.get_global_rect(),
		"continue": _continue.get_global_rect(),
	}


func continue_button() -> Button:
	return _continue


## The offer form's buttons; null on the plain dialogue.
func accept_button() -> Button:
	return _accept


func decline_button() -> Button:
	return _decline


func action_button() -> Button:
	return _action_btn


func chips_row() -> Control:
	return _chips_row


func chip_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for child in _chips_row.get_children():
		var lbl := child.find_child("ChipLabel", true, false) as Label
		if lbl != null:
			out.append(lbl.text)
	return out


func beat_pill() -> Label:
	return _beat_pill


func footer_text() -> String:
	return _footer.text


func _init_content(default_intro: bool, body_text: String, options: Dictionary) -> void:
	if default_intro:
		_beats = _intro_beats()
		_chips = _intro_chips()
		_footer_text = tr("The clock starts when you close this.")
		_typewriter_enabled = true
	else:
		var opt_beats: Array = options.get("beats", [])
		if not opt_beats.is_empty():
			for entry: Variant in opt_beats:
				_beats.append(str(entry))
			_typewriter_enabled = bool(options.get("typewriter", true))
		else:
			_beats = [body_text if body_text != "" else _intro_body()]
			_typewriter_enabled = bool(options.get("typewriter", false))
		for chip_entry: Variant in options.get("chips", []):
			if chip_entry is Dictionary:
				_chips.append(chip_entry)
		_footer_text = str(options.get("footer", ""))
		_action_label = str(options.get("action_label", ""))
		var cb: Variant = options.get("action_callback", Callable())
		if cb is Callable:
			_action_callback = cb
	_body_text = _beats[0] if not _beats.is_empty() else ""


func _build_box() -> void:
	_box.name = "Box"
	_box.theme_type_variation = &"IntroBox"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_group.add_child(_box)
	var inner := Panel.new()
	inner.name = "GoldLine"
	inner.theme_type_variation = &"IntroGoldLine"
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 10.0
	inner.offset_top = 10.0
	inner.offset_right = -10.0
	inner.offset_bottom = -10.0
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(inner)
	_build_beat_pill()
	# A long body scrolls inside the box once the box is at MAX_BOX_H.
	_body_scroll.name = "BodyScroll"
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.focus_mode = Control.FOCUS_NONE
	_body_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_body_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The portrait covers the box's left edge, so the text starts past it.
	_body_scroll.offset_left = TEXT_LEFT
	_body_scroll.offset_top = BODY_TOP
	_body_scroll.offset_right = -BODY_RIGHT
	_body_scroll.offset_bottom = -BODY_BOTTOM
	_box.add_child(_body_scroll)
	_body.name = "Body"
	_body.text = _body_text
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.theme_type_variation = &"IntroBody"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body_scroll.add_child(_body)
	_build_chips_row()
	_build_footer()
	_continue.name = "Continue"
	_continue.text = tr("Continue ({key})").format({"key": CONTINUE_KEY})
	_continue.focus_mode = Control.FOCUS_NONE
	_continue.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_continue.offset_left = -260.0
	_continue.offset_top = -62.0
	_continue.offset_right = -24.0
	_continue.offset_bottom = -20.0
	_continue.pressed.connect(_on_continue_pressed)
	_box.add_child(_continue)
	if _offer:
		_continue.visible = false
		_accept = _corner_button("Accept", tr("Accept"), 0.0)
		_accept.theme_type_variation = &"HudButtonGreen"
		_accept.pressed.connect(choose.bind(true))
		_decline = _corner_button("Decline", tr("Decline"), 270.0)
		_decline.theme_type_variation = &"HudButtonCoral"
		_decline.pressed.connect(choose.bind(false))
	elif _action_label != "":
		_action_btn = _corner_button("Action", _action_label, 270.0)
		_action_btn.theme_type_variation = &"HudButtonTeal"
		_action_btn.pressed.connect(_trigger_action)
	_start_beat(0)


func _build_beat_pill() -> void:
	_beat_pill_wrap.name = "BeatPill"
	_beat_pill_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_beat_pill_wrap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_beat_pill_wrap.offset_left = -24.0 - BEAT_PILL_W
	_beat_pill_wrap.offset_top = 14.0
	_beat_pill_wrap.offset_right = -24.0
	_beat_pill_wrap.offset_bottom = 40.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.13, 0.26, 0.92)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	_beat_pill_wrap.add_theme_stylebox_override("panel", style)
	_beat_pill.name = "BeatLabel"
	_beat_pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_beat_pill.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_beat_pill.theme_type_variation = &"HudSmall"
	_beat_pill.add_theme_color_override("font_color", Color(0.99, 0.97, 0.92, 1.0))
	_beat_pill_wrap.add_child(_beat_pill)
	_box.add_child(_beat_pill_wrap)


func _build_chips_row() -> void:
	_chips_row.name = "ChipsRow"
	_chips_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips_row.add_theme_constant_override("h_separation", 8)
	_chips_row.add_theme_constant_override("v_separation", 6)
	_chips_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_chips_row.offset_left = TEXT_LEFT
	_chips_row.offset_right = -BODY_RIGHT
	_chips_row.offset_bottom = -BODY_BOTTOM - 4.0
	_chips_row.offset_top = -BODY_BOTTOM - 4.0
	_box.add_child(_chips_row)
	for entry in _chips:
		_chips_row.add_child(_make_chip(entry))
	_chips_row.visible = not _chips.is_empty()


func _make_chip(entry: Dictionary) -> PanelContainer:
	var tint: Color = entry.get("tint", Color(0.20, 0.42, 0.64, 1.0))
	var pill := PanelContainer.new()
	pill.name = "Chip"
	pill.mouse_filter = Control.MOUSE_FILTER_PASS
	pill.tooltip_text = str(entry.get("tooltip", ""))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(tint.r, tint.g, tint.b, 0.14)
	style.border_color = Color(tint.r, tint.g, tint.b, 0.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 10.0
	style.content_margin_right = 12.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	pill.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(row)
	var icon_val: Variant = entry.get("icon", null)
	var icon_tex: Texture2D = null
	if icon_val is Texture2D:
		icon_tex = icon_val
	elif icon_val is String and String(icon_val) != "":
		icon_tex = load(String(icon_val)) as Texture2D
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.custom_minimum_size = Vector2(CHIP_ICON_SIZE, CHIP_ICON_SIZE)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	var text := str(entry.get("label", ""))
	var lbl := Label.new()
	lbl.name = "ChipLabel"
	lbl.text = text
	lbl.theme_type_variation = &"HudSmall"
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var max_w := BOX_SIZE.x - TEXT_LEFT - BODY_RIGHT - 56.0
	var font := BuildMenu.HUD_THEME.get_font(&"font", &"HudSmall")
	var fsize := BuildMenu.HUD_THEME.get_font_size(&"font_size", &"HudSmall")
	if font != null and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > max_w:
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size.x = max_w
	row.add_child(lbl)
	return pill


func _build_footer() -> void:
	_footer.name = "Footer"
	_footer.theme_type_variation = &"HudHint"
	_footer.text = _footer_text
	_footer.visible = _footer_text != ""
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_footer.offset_left = TEXT_LEFT
	_footer.offset_right = -544.0
	_footer.offset_top = -62.0
	_footer.offset_bottom = -20.0
	_box.add_child(_footer)


func _start_beat(idx: int) -> void:
	_beat_index = clampi(idx, 0, maxi(0, _beats.size() - 1))
	_body_text = _beats[_beat_index] if not _beats.is_empty() else ""
	_body.text = _body_text
	_reveal_progress = 0.0
	_bob_time = 0.0
	_reset_portrait_pose()
	if _typewriter_enabled and _body_text != "":
		_revealing = true
		_body.visible_characters = 0
	else:
		_revealing = false
		_body.visible_characters = -1
	_sync_beat_chrome()


func _sync_beat_chrome() -> void:
	var multi := _beats.size() > 1
	_beat_pill_wrap.visible = multi
	if multi:
		_beat_pill.text = "%d / %d" % [_beat_index + 1, _beats.size()]
	var has_next := _beat_index < _beats.size() - 1
	if has_next:
		_continue.text = tr("Next ({key})").format({"key": CONTINUE_KEY})
	else:
		_continue.text = tr("Continue ({key})").format({"key": CONTINUE_KEY})


func _on_continue_pressed() -> void:
	if _revealing:
		finish_reveal()
		return
	_advance_or_dismiss()


func _advance_or_dismiss() -> void:
	if _done:
		return
	if _beat_index < _beats.size() - 1:
		_start_beat(_beat_index + 1)
		_fit_box()
		_place()
	else:
		dismiss()


func _trigger_action() -> void:
	if _done:
		return
	var cb := _action_callback
	dismiss()
	if cb.is_valid():
		cb.call()


func _play_entrance_pop() -> void:
	_kill_entrance_tween()
	if not _typewriter_enabled:
		return
	_box.pivot_offset = _box.size * 0.5
	_box.scale = Vector2(0.94, 0.94)
	_box.modulate.a = 0.0
	_nameplate.modulate.a = 0.0
	_entrance_tween = create_tween()
	_entrance_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_entrance_tween.set_parallel(true)
	(
		_entrance_tween
		. tween_property(_box, "scale", Vector2.ONE, 0.22)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_entrance_tween.tween_property(_box, "modulate:a", 1.0, 0.16)
	_entrance_tween.tween_property(_nameplate, "modulate:a", 1.0, 0.16)


func _kill_entrance_tween() -> void:
	if is_instance_valid(_entrance_tween):
		_entrance_tween.kill()
	_entrance_tween = null


func _reset_portrait_pose() -> void:
	_portrait.scale = Vector2.ONE
	_portrait.position = Vector2.ZERO


func _play_voice_blip() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var audio := tree.root.get_node_or_null("GameAudio")
	if audio != null and audio.has_method(&"play_voice_blip"):
		var who := &"airline" if _speaker == Speaker.GOTTA_AIR else &"manager"
		audio.play_voice_blip(who)


func _intro_beats() -> Array[String]:
	var beat1 := tr("Welcome aboard! Build a check-in desk, scanner, and gate from Operations.")
	var beat2 := tr("Hire staff to open the terminal. {pause} pauses, {speed} sets speed.").format(
		{"pause": CONTINUE_KEY, "speed": SPEED_KEYS_TEXT}
	)
	return [beat1, beat2]


func _intro_chips() -> Array[Dictionary]:
	return [
		{
			"icon": ICON_CHECKIN,
			"label": tr("Check-in"),
			"tint": Color(0.24, 0.56, 0.72, 1.0),
		},
		{
			"icon": ICON_SECURITY,
			"label": tr("Security"),
			"tint": Color(0.84, 0.52, 0.22, 1.0),
		},
		{
			"icon": ICON_STAFF,
			"label": tr("Staff"),
			"tint": Color(0.22, 0.58, 0.36, 1.0),
		},
	]


## Legacy fallback when an explicit single-string caller asks for the intro text.
func _intro_body() -> String:
	return "\n".join(_intro_beats())


## Sizes the box to its body text and optional chips row: never below the
## caller's height, never above the cap from _max_box_height.
func _fit_box() -> void:
	var chips_h := 0.0
	if not _chips.is_empty():
		var chip_area_w := BOX_SIZE.x - TEXT_LEFT - BODY_RIGHT
		_chips_row.custom_minimum_size.x = chip_area_w
		var min_h := maxf(30.0, _chips_row.get_combined_minimum_size().y)
		chips_h = min_h + 12.0
		_chips_row.offset_bottom = -BODY_BOTTOM - 4.0
		_chips_row.offset_top = -BODY_BOTTOM - 4.0 - min_h
	_body_scroll.offset_bottom = -(BODY_BOTTOM + chips_h)
	_body.size.x = BOX_SIZE.x - TEXT_LEFT - BODY_RIGHT
	var wanted := _body.get_minimum_size().y + BODY_TOP + BODY_BOTTOM + chips_h
	var cap := _max_box_height()
	_set_box_height(clampf(wanted, minf(_box_height, cap), cap))


## The tallest the box may be: MAX_BOX_H, or less where the viewport is short.
## The room above the build bar, less EDGE_GAP, must hold the box and its
## nameplate at MIN_SCALE, or _place would push the nameplate off the top.
func _max_box_height() -> float:
	var screen_h := get_viewport_rect().size.y if is_inside_tree() else 1080.0
	var room := (screen_h - BOX_BOTTOM - EDGE_GAP) / MIN_SCALE - NAMEPLATE_RISE
	return clampf(room, BODY_TOP + BODY_BOTTOM + 60.0, MAX_BOX_H)


## A resized viewport changes the cap, so the box is fitted again, then placed.
func _refit() -> void:
	_fit_box()
	_place()


## The box grows upward from its fixed bottom edge; the nameplate rides on its
## top edge.
func _set_box_height(height: float) -> void:
	_box.position = Vector2(PORTRAIT_SIZE - PORTRAIT_OVERLAP, PORTRAIT_SIZE - height)
	_box.size = Vector2(BOX_SIZE.x, height)
	_nameplate.position = _box.position + Vector2(TEXT_LEFT - 20.0, -NAMEPLATE_RISE)


## A button in the box's bottom-right corner, `shift` pixels left of where
## Continue stands.
func _corner_button(button_name: String, text: String, shift: float) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	button.offset_left = _continue.offset_left - shift
	button.offset_top = _continue.offset_top
	button.offset_right = _continue.offset_right - shift
	button.offset_bottom = _continue.offset_bottom
	_box.add_child(button)
	return button


func _build_nameplate() -> void:
	_nameplate.name = "Nameplate"
	_nameplate.theme_type_variation = &"IntroNameplate"
	_nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_group.add_child(_nameplate)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	_nameplate.add_child(column)
	var title := Label.new()
	title.name = "Name"
	title.text = _speaker_name()
	title.theme_type_variation = &"IntroName"
	column.add_child(title)
	var role := Label.new()
	role.name = "Title"
	role.text = _title_text
	role.theme_type_variation = &"IntroRole"
	column.add_child(role)


func _speaker_portrait() -> Texture2D:
	return GOTTA_AIR_PORTRAIT if _speaker == Speaker.GOTTA_AIR else PORTRAIT


func _speaker_name() -> String:
	return tr("GOTTA AIR") if _speaker == Speaker.GOTTA_AIR else tr("TERMINAL MANAGER")


## Centres the portrait-plus-box group horizontally, with the box's bottom
## BOX_BOTTOM above the screen bottom (the portrait stands on the same line).
## On a screen narrower or shorter than the 1080p layout the group scales down;
## BOX_BOTTOM stays in screen pixels, because BuildMenu does not scale. A box
## grown above the portrait counts with the nameplate on its top edge.
func _place() -> void:
	var screen := get_viewport_rect().size if is_inside_tree() else Vector2(1920.0, 1080.0)
	var tall := maxf(PORTRAIT_SIZE, _box.size.y + NAMEPLATE_RISE)
	var fit := minf((screen.x - 32.0) / GROUP_W, (screen.y - BOX_BOTTOM - EDGE_GAP) / tall)
	var group_scale := clampf(fit, MIN_SCALE, 1.0)
	_group.scale = Vector2.ONE * group_scale
	_group.position = Vector2(
		roundf((screen.x - GROUP_W * group_scale) / 2.0),
		roundf(screen.y - BOX_BOTTOM - PORTRAIT_SIZE * group_scale)
	)


## Top-centre ringing-phone badge beside Offers shared by New Airport intro and
## UnlockGuide calls (decisions phone-ring-pop-up-for-big-moments and
## hud-4-zone-enforcement-alertstack-toasts-bottom-right-inspect-staffpanel-cleanup).
class PhoneRingCue:
	extends PanelContainer

	signal answered

	const RING_DURATION_S := 2.05
	const CUE_SIZE := float(HudLayout.BUTTON_H)
	const ICON_SIZE := 28.0
	const PHONE_SVG := (
		'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">'
		+ '<path d="M18 14c-4 0-7 3-7 8 0 17 14 31 31 31 5 0 8-3 8-7l-2-8-10-3-4 5'
		+ 'c-5-2-9-6-11-11l5-4-3-11z" fill="#FFCC4D" stroke="#1A2142" stroke-width="4" '
		+ 'stroke-linejoin="round" stroke-linecap="round"/>'
		+ '<path d="M40 14c6 2 10 6 12 12" fill="none" stroke="#8CCECE" stroke-width="4" '
		+ 'stroke-linecap="round"/>'
		+ '<path d="M42 7c9 3 14 8 17 17" fill="none" stroke="#1A2142" stroke-width="3.5" '
		+ 'stroke-linecap="round"/>'
		+ "</svg>"
	)

	static var _cached_texture: Texture2D

	var _button := Button.new()
	var _icon := TextureRect.new()
	var _ringing := false
	var _answer_on_key := false
	var _tween: Tween

	func _init() -> void:
		name = "PhoneRingCue"
		theme = BuildMenu.HUD_THEME
		theme_type_variation = &"HudTopCard"
		process_mode = Node.PROCESS_MODE_ALWAYS
		visible = false
		custom_minimum_size = Vector2(CUE_SIZE, CUE_SIZE)
		pivot_offset = Vector2(CUE_SIZE * 0.5, CUE_SIZE * 0.5)

		_button.name = "AnswerButton"
		_button.flat = true
		_button.focus_mode = Control.FOCUS_NONE
		_button.set_anchors_preset(Control.PRESET_FULL_RECT)
		_button.pressed.connect(answer)
		add_child(_button)

		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(center)

		_icon.name = "PhoneIcon"
		_icon.texture = _phone_texture()
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		_icon.size = Vector2(ICON_SIZE, ICON_SIZE)
		_icon.pivot_offset = Vector2(ICON_SIZE * 0.5, ICON_SIZE * 0.5)
		center.add_child(_icon)

	func _ready() -> void:
		var vp := get_viewport()
		if vp != null and not vp.size_changed.is_connected(_place):
			vp.size_changed.connect(_place)
		_place()

	func _exit_tree() -> void:
		var vp := get_viewport()
		if vp != null and vp.size_changed.is_connected(_place):
			vp.size_changed.disconnect(_place)
		if _ringing:
			_stop_ring_sfx()
		_ringing = false
		_kill_tween()

	func _place() -> void:
		if is_inside_tree() and get_viewport() != null:
			TopRow.place_ring_cue(self, self, CUE_SIZE)

	func _input(event: InputEvent) -> void:
		if not _ringing or not _answer_on_key or not visible:
			return
		var key := event as InputEventKey
		if key == null or not key.pressed:
			return
		if IntroDialogue._is_quick_key(key):
			return
		get_viewport().set_input_as_handled()
		if key.echo:
			return
		var space := key.physical_keycode == KEY_SPACE and not key.shift_pressed
		if space or key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
			answer()

	## Starts the ringing animation and phone_ring SFX after an optional settle
	## delay; auto-answers or auto-hides.
	func start_ring(auto_answer := true, answer_on_key := false, delay_s := 0.0) -> void:
		stop_ring()
		if delay_s <= 0.0:
			_begin_ring(auto_answer, answer_on_key)
			return
		_tween = create_tween()
		_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_tween.tween_interval(delay_s)
		_tween.tween_callback(_begin_ring.bind(auto_answer, answer_on_key))

	func _begin_ring(auto_answer: bool, answer_on_key: bool) -> void:
		_kill_tween()
		_place()
		_ringing = true
		_answer_on_key = answer_on_key
		visible = true
		scale = Vector2.ONE
		_icon.rotation = 0.0
		_icon.scale = Vector2.ONE
		_play_ring_sfx()
		_tween = create_tween()
		_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_append_double_ring(_tween)
		_tween.tween_interval(0.43)
		_append_double_ring(_tween)
		_tween.tween_interval(maxf(0.01, RING_DURATION_S - 1.87))
		_tween.tween_callback(answer if auto_answer else stop_ring)

	## Answers the incoming call immediately once while ringing.
	func answer() -> void:
		if not _ringing:
			return
		stop_ring()
		answered.emit()

	## Stops the ring beat and hides the cue without emitting answered.
	func stop_ring() -> void:
		if _ringing:
			_stop_ring_sfx()
		_ringing = false
		_answer_on_key = false
		_kill_tween()
		visible = false
		scale = Vector2.ONE
		_icon.rotation = 0.0
		_icon.scale = Vector2.ONE

	func is_ringing() -> bool:
		return _ringing

	func phone_icon() -> TextureRect:
		return _icon

	func answer_button() -> Button:
		return _button

	func _append_double_ring(tween: Tween) -> void:
		_append_trill(tween, 0.28)
		tween.tween_interval(0.10)
		_append_trill(tween, 0.34)

	func _append_trill(tween: Tween, span: float) -> void:
		var steps := 6
		var step_s := span / float(steps + 1)
		tween.tween_property(_icon, "scale", Vector2(1.18, 1.18), step_s * 0.5)
		tween.parallel().tween_property(self, "scale", Vector2(1.08, 1.08), step_s * 0.5)
		for i in steps:
			var angle := 0.26 if i % 2 == 0 else -0.26
			tween.tween_property(_icon, "rotation", angle, step_s)
		tween.parallel().tween_property(_icon, "scale", Vector2.ONE, step_s)
		tween.parallel().tween_property(self, "scale", Vector2.ONE, step_s)
		tween.tween_property(_icon, "rotation", 0.0, step_s * 0.5)

	func _play_ring_sfx() -> void:
		var tree := get_tree()
		if tree == null or tree.root == null:
			return
		var audio := tree.root.get_node_or_null("GameAudio")
		if audio != null and audio.has_method(&"play_sfx"):
			audio.play_sfx(&"phone_ring")

	func _stop_ring_sfx() -> void:
		var tree := get_tree()
		if tree == null or tree.root == null:
			return
		var audio := tree.root.get_node_or_null("GameAudio")
		if audio != null and audio.has_method(&"stop_sfx"):
			audio.stop_sfx(&"phone_ring")

	func _kill_tween() -> void:
		if is_instance_valid(_tween):
			_tween.kill()
		_tween = null

	static func _phone_texture() -> Texture2D:
		if _cached_texture != null:
			return _cached_texture
		var img := Image.new()
		if img.load_svg_from_string(PHONE_SVG, 2.0) == OK:
			_cached_texture = ImageTexture.create_from_image(img)
		return _cached_texture
