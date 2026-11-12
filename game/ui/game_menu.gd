class_name GameMenu
extends Node
## The game menu (decision daily-incidents-technical-design-incidentdirector-
## shared-clo): Esc outside build mode opens it with the clock held. It holds
## two things and nothing else: Resume, and Settings, whose one switch turns the
## daily incidents on or off for this game (the flag is saved with the game, in
## IncidentDirector). Esc again, or Resume, closes it.
##
## Esc belongs to build mode first (decision build-mode-pauses-the-game-while-a-
## build-tray-is-open-closin): while a tray or the Staff card is open, a tool is
## picked, a template paste or room move is running, or the room panel is up,
## the menu leaves the key alone and BuildMode, which handles Esc later in the
## same input pass, closes the tray as before. The Offers sheet and the runway card
## sit later in the tree and take their own Esc ahead of this node.
##
## The menu takes the clock's exclusive turn (clock.holds.take_turn) like the
## Offers sheet and the major incident panel: it shows at once when nobody has
## the turn, and otherwise when the dialog ahead of it closes, the clock held
## meanwhile. A major incident that arrives while the menu is open waits behind
## it the same way. Its hold does not give way to the player.
##
## The same node asks the new-game question: ask_incidents() puts the terminal
## manager's offer dialogue (IntroDialogue in offer mode) up on its own turn,
## and Accept or Decline sets the flag. PassengerHud asks it as the intro
## welcome page closes.

## The menu or the question opened or closed. PassengerHud holds the camera
## still meanwhile.
signal dialog_changed(open: bool)

## With the intro and the other dialogs, over the HUD.
const LAYER := 10
const MENU_SIZE := Vector2(520.0, 0.0)
const QUESTION_TITLE := "Daily incidents"
const QUESTION_BODY := (
	"One more thing before the doors open. Some days bring trouble: a spill on "
	+ "the floor, an inspector, a holiday rush. Shall I send those your way?\n"
	+ "Accept turns daily incidents on, Decline leaves them off. You can change "
	+ "this any time: press Esc, then Settings.\n"
	+ "The clock stays paused until you choose."
)
const QUESTION_HEIGHT := 360.0
const INCIDENTS_TEXT := "Incidents"

@export var director: IncidentDirector
@export var clock: SimClock
@export var build_menu: BuildMenu
@export var build_mode: BuildMode
## Optional: a load ends an open menu or question.
@export var save_game: SaveGame

var _layer: CanvasLayer
var _question_layer: CanvasLayer
var _question: IntroDialogue
## The menu's hold on the clock, from asking for the turn until it closes.
var _hold := ClockHolds.NONE
var _question_hold := ClockHolds.NONE
var _shown := false
var _main_page: Control
var _settings_page: Control
var _incidents_switch: CheckButton


func _ready() -> void:
	name = "GameMenu"
	if save_game != null:
		save_game.loaded.connect(_on_loaded)


## A menu that leaves the tree while open must not leave the game paused (the
## holds also end a hold whose owner leaves).
func _exit_tree() -> void:
	_release(_hold)
	_hold = ClockHolds.NONE
	_release(_question_hold)
	_question_hold = ClockHolds.NONE


## Esc outside build mode opens the menu; Esc with the menu up closes it.
func _input(event: InputEvent) -> void:
	if not _shown:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("build_tool_none"):
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("build_tool_none"):
		return
	if _shown or _in_build_mode() or has_hold():
		return
	if open():
		get_viewport().set_input_as_handled()


## True while the menu is up or waiting for its turn.
func has_hold() -> bool:
	return is_instance_valid(clock) and clock.holds.has(_hold)


func is_open() -> bool:
	return _shown


## True while the new-game question is up.
func is_question_open() -> bool:
	return _question != null


## Asks the clock for the turn and shows the menu on it. False when it is
## already up or waiting, or there is no clock to hold.
func open() -> bool:
	if has_hold() or not is_instance_valid(clock):
		return false
	_hold = clock.holds.take_turn(self, _show)
	return _hold != ClockHolds.NONE


## Closes the menu, or drops its place in line, and gives the clock back.
func close() -> void:
	var was_shown := _shown
	_free_layer()
	_release(_hold)
	_hold = ClockHolds.NONE
	if was_shown:
		dialog_changed.emit(false)


## Resume: the same as Esc.
func press_resume() -> void:
	close()


func press_settings() -> void:
	if not _shown:
		return
	_main_page.visible = false
	_settings_page.visible = true


func press_back() -> void:
	if not _shown:
		return
	_settings_page.visible = false
	_main_page.visible = true


## The Incidents switch, or null while the menu is closed.
func incidents_switch() -> CheckButton:
	return _incidents_switch


func resume_button() -> Button:
	return _main_page.get_node("Resume") if _main_page != null else null


func settings_button() -> Button:
	return _main_page.get_node("Settings") if _main_page != null else null


## The new-game question, on its own turn: when nobody has it, at once, and
## otherwise when the dialog ahead of it (the intro, taken first) closes. False
## when it is already asked or there is nothing to set.
func ask_incidents() -> bool:
	if _question_hold != ClockHolds.NONE or director == null or not is_instance_valid(clock):
		return false
	_question_hold = clock.holds.take_turn(self, _show_question)
	return _question_hold != ClockHolds.NONE


## The open question, or null.
func question() -> IntroDialogue:
	return _question


func _in_build_mode() -> bool:
	if build_menu != null:
		if (
			build_menu.is_tray_open()
			or build_menu.staff_open
			or build_menu.build_session.active
			or build_menu.room_panel().visible
		):
			return true
	return build_mode != null and BuiltSelection.clicks_taken(build_mode)


func _show() -> void:
	_shown = true
	_layer = CanvasLayer.new()
	_layer.name = "GameMenuLayer"
	_layer.layer = LAYER
	var root := Control.new()
	root.name = "Root"
	root.theme = BuildMenu.HUD_THEME
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(root)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = IntroDialogue.DIM_COLOR
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = MENU_SIZE
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	var pages := VBoxContainer.new()
	panel.add_child(pages)
	_main_page = _page("MainPage", "Game menu")
	pages.add_child(_main_page)
	_button(_main_page, "Resume", "Resume (Esc)", press_resume)
	_button(_main_page, "Settings", "Settings", press_settings)
	_settings_page = _page("SettingsPage", "Settings")
	_settings_page.visible = false
	pages.add_child(_settings_page)
	_incidents_switch = CheckButton.new()
	_incidents_switch.name = "Incidents"
	_incidents_switch.text = INCIDENTS_TEXT
	_incidents_switch.focus_mode = Control.FOCUS_NONE
	_incidents_switch.button_pressed = director != null and director.is_enabled()
	_incidents_switch.toggled.connect(_on_incidents_toggled)
	_settings_page.add_child(_incidents_switch)
	_button(_settings_page, "Back", "Back", press_back)
	add_child(_layer)
	dialog_changed.emit(true)


func _page(page_name: String, title: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = page_name
	var label := Label.new()
	label.name = "Title"
	label.text = title
	label.theme_type_variation = &"HudLarge"
	page.add_child(label)
	return page


func _button(page: Control, button_name: String, text: String, handler: Callable) -> void:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	page.add_child(button)


func _on_incidents_toggled(on: bool) -> void:
	if director != null:
		director.set_enabled(on)


func _free_layer() -> void:
	_shown = false
	var layer := _layer
	_layer = null
	_main_page = null
	_settings_page = null
	_incidents_switch = null
	if is_instance_valid(layer) and not layer.is_queued_for_deletion():
		layer.queue_free()


func _show_question() -> void:
	_question_layer = CanvasLayer.new()
	_question_layer.name = "IncidentQuestionLayer"
	_question_layer.layer = LAYER
	_question = IntroDialogue.new(QUESTION_TITLE, QUESTION_BODY, QUESTION_HEIGHT, true)
	_question_layer.add_child(_question)
	add_child(_question_layer)
	_question.chosen.connect(_on_chosen)
	var close_question := _close_question.bind(_question_layer)
	_question.dismissed.connect(close_question)
	_question.tree_exiting.connect(close_question)
	_question_layer.tree_exiting.connect(close_question)
	dialog_changed.emit(true)


func _on_chosen(accepted: bool) -> void:
	director.set_enabled(accepted)


func _close_question(layer: CanvasLayer) -> void:
	if _question == null or layer != _question_layer:
		return
	_free_question()
	var token := _question_hold
	_question_hold = ClockHolds.NONE
	_release(token)
	dialog_changed.emit(false)


func _free_question() -> void:
	var layer := _question_layer
	_question_layer = null
	_question = null
	if is_instance_valid(layer) and not layer.is_queued_for_deletion():
		layer.queue_free()


## A load replaced the world and dropped every hold: the menu and the question
## end without setting anything.
func _on_loaded(ok: bool) -> void:
	if not ok:
		return
	var had_question := _question != null
	_free_question()
	_question_hold = ClockHolds.NONE
	if had_question:
		dialog_changed.emit(false)
	close()


func _release(token: int) -> void:
	if is_instance_valid(clock):
		clock.holds.release(token)
