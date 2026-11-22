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
## The height the caller asked for: the box is never shorter.
var _box_height := BOX_SIZE.y
var _offer := false
var _speaker := Speaker.TERMINAL_MANAGER
## Holds the portrait, box and nameplate at their 1080p layout; _place moves it
## and scales it down on a smaller screen.
var _group := Control.new()
var _box := Panel.new()
var _nameplate := PanelContainer.new()
var _portrait := TextureRect.new()
var _body_scroll := ScrollContainer.new()
var _body := Label.new()
var _continue := Button.new()
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
	speaker := Speaker.TERMINAL_MANAGER
) -> void:
	_title_text = title_text if title_text != "" else tr("Your first day at the airport")
	_body_text = body_text if body_text != "" else _intro_body()
	_box_height = box_height
	_offer = offer
	_speaker = speaker
	name = "IntroDialogue"
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
	_group.add_child(_portrait)
	_nameplate.size = NAMEPLATE_SIZE
	_set_box_height(_box_height)
	_place()


func _ready() -> void:
	get_viewport().size_changed.connect(_refit)
	_fit_box()
	_place()


## Every key press is taken while the dialogue is open, except the bare quick
## save and quick load keys, which pass on to SaveGame (decision quicksave-f5-
## and-quickload-f8-work-while-a-dialog-is-open). Space (without Shift), Enter
## and keypad Enter close it. The key is marked handled before closing, so the
## HUD's Space pause toggle never sees the same press.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if _done or not visible or key == null or not key.pressed:
		return
	if _is_quick_key(key):
		return
	get_viewport().set_input_as_handled()
	if key.echo or _offer:
		return
	var space := key.physical_keycode == KEY_SPACE and not key.shift_pressed
	if space or key.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
		dismiss()


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
	# A long body scrolls inside the box once the box is at MAX_BOX_H.
	_body_scroll.name = "BodyScroll"
	_body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_scroll.focus_mode = Control.FOCUS_NONE
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
	_continue.name = "Continue"
	_continue.text = tr("Continue ({key})").format({"key": CONTINUE_KEY})
	_continue.focus_mode = Control.FOCUS_NONE
	_continue.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_continue.offset_left = -260.0
	_continue.offset_top = -62.0
	_continue.offset_right = -24.0
	_continue.offset_bottom = -20.0
	_continue.pressed.connect(dismiss)
	_box.add_child(_continue)
	if _offer:
		_continue.visible = false
		_accept = _corner_button("Accept", tr("Accept"), 0.0)
		_accept.pressed.connect(choose.bind(true))
		_decline = _corner_button("Decline", tr("Decline"), 270.0)
		_decline.pressed.connect(choose.bind(false))


## The first-day text, one msgid per paragraph, joined by line breaks. The
## speed keys are placeholders so a language can keep or move them.
func _intro_body() -> String:
	var welcome := tr(
		# gdlint:ignore = max-line-length
		"Welcome to your new airport! Passengers are on their way, and every one of them has a flight to catch."
	)
	var path := tr(
		# gdlint:ignore = max-line-length
		"Build them a path: entrance, then check-in, then security, then the gate exit. {pause} pauses, {speed} sets speed."
	)
	var clock := tr("The clock starts when you close this.")
	var keys := {"pause": CONTINUE_KEY, "speed": SPEED_KEYS_TEXT}
	return "\n".join(PackedStringArray([welcome, path.format(keys), clock]))


## Sizes the box to its body text: never below the caller's height, never above
## the cap from _max_box_height. Called once the dialogue is in the tree, where
## the body has its theme font and its text is translated.
func _fit_box() -> void:
	_body.size.x = BOX_SIZE.x - TEXT_LEFT - BODY_RIGHT
	var wanted := _body.get_minimum_size().y + BODY_TOP + BODY_BOTTOM
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


## Bottom-centre ringing-phone badge shared by New Airport intro and UnlockGuide
## calls (decisions phone-ring-pop-up-for-big-moments and
## phone-ring-sfx-and-new-airport-intro-ring-procedural-phone-r).
class PhoneRingCue:
	extends PanelContainer

	signal answered

	const RING_DURATION_S := 0.90
	const CUE_SIZE := 64.0
	const ICON_SIZE := 44.0
	const CUE_BOTTOM := BuildMenu.MARGIN + BuildMenu.BAR_H + HudLayout.GAP
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
		anchor_left = 0.5
		anchor_right = 0.5
		anchor_top = 1.0
		anchor_bottom = 1.0
		offset_left = -CUE_SIZE * 0.5
		offset_right = CUE_SIZE * 0.5
		offset_top = -CUE_BOTTOM - CUE_SIZE
		offset_bottom = -CUE_BOTTOM
		grow_horizontal = Control.GROW_DIRECTION_BOTH
		grow_vertical = Control.GROW_DIRECTION_BEGIN

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

	func _exit_tree() -> void:
		_kill_tween()

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

	## Starts the ringing animation and phone_ring SFX; auto-answers or auto-hides.
	func start_ring(auto_answer := true, answer_on_key := false) -> void:
		_kill_tween()
		_ringing = true
		_answer_on_key = answer_on_key
		visible = true
		_icon.rotation = 0.0
		_icon.scale = Vector2.ONE
		_play_ring_sfx()
		_tween = create_tween()
		_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_append_trill(_tween, 0.30)
		_tween.tween_interval(0.11)
		_append_trill(_tween, 0.33)
		_tween.tween_interval(maxf(0.01, RING_DURATION_S - 0.74))
		_tween.tween_callback(answer if auto_answer else stop_ring)

	## Answers the incoming call immediately once while ringing.
	func answer() -> void:
		if not _ringing:
			return
		stop_ring()
		answered.emit()

	## Stops the ring beat and hides the cue without emitting answered.
	func stop_ring() -> void:
		_ringing = false
		_answer_on_key = false
		_kill_tween()
		visible = false
		_icon.rotation = 0.0
		_icon.scale = Vector2.ONE

	func is_ringing() -> bool:
		return _ringing

	func phone_icon() -> TextureRect:
		return _icon

	func answer_button() -> Button:
		return _button

	func _append_trill(tween: Tween, span: float) -> void:
		var steps := 4
		var step_s := span / float(steps + 1)
		tween.tween_property(_icon, "scale", Vector2(1.12, 1.12), step_s * 0.5)
		for i in steps:
			var angle := 0.22 if i % 2 == 0 else -0.22
			tween.tween_property(_icon, "rotation", angle, step_s)
		tween.parallel().tween_property(_icon, "scale", Vector2.ONE, step_s)
		tween.tween_property(_icon, "rotation", 0.0, step_s * 0.5)

	func _play_ring_sfx() -> void:
		var tree := get_tree()
		if tree == null or tree.root == null:
			return
		var audio := tree.root.get_node_or_null("GameAudio")
		if audio != null and audio.has_method(&"play_sfx"):
			audio.play_sfx(&"phone_ring")

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
