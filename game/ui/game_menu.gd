class_name GameMenu
extends Node
## The game menu (decision daily-incidents-technical-design-incidentdirector-
## shared-clo): Esc outside build mode opens it with the clock held. It holds
## Resume, Save, Load and Settings, whose one switch turns the daily incidents
## on or off for this game (the flag is saved with the game, in
## IncidentDirector). Esc again, or Resume, closes it. Save and Load came with
## the title screen (decision title-menu-with-continue-new-airport-load-and-
## quit-autosave): Save writes the manual save, the F5 file; Load opens a page
## listing the saves (SaveList) and loads the one picked through
## SaveGame.load_from_file. A load that goes through closes the menu (the load
## drops every hold); a refused one keeps it open with the reason in the status
## line under the pages, where Save also reports.
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
const QUESTION_HEIGHT := 360.0
## The menu key's name, a placeholder in the Resume button and the question.
const ESC_KEY := "Esc"

@export var director: IncidentDirector
@export var clock: SimClock
@export var build_menu: BuildMenu
@export var build_mode: BuildMode
## Optional: a load ends an open menu or question. Without one the menu has no
## Save or Load.
@export var save_game: SaveGame
## Optional: the quit log (decision quit-point-log-d7-opt-in-local-event-log-
## file-only-off-by-de). With one, the Settings page holds its switch and the
## Open log folder button; without one it holds neither.
@export var quit_log: QuitLogRecorder
## Opens a folder in the system's file browser; tests swap in a recorder.
var open_folder := Callable()
## Optional: called by an Esc the menu would open on; true means it closed a card
## (a selected built item or a followed passenger or vehicle) and took the key.
## PassengerHud sets it, so the first Esc closes the card and the next opens the menu.
var esc_closes: Callable
## The Audio controls card on the Settings view, or null while the menu is closed.
var audio_card: AudioSettingsCard

var _layer: CanvasLayer
var _question_layer: CanvasLayer
var _question: IntroDialogue
## The menu's hold on the clock, from asking for the turn until it closes.
var _hold := ClockHolds.NONE
var _question_hold := ClockHolds.NONE
var _shown := false
var _main_page: Control
var _settings_page: Control
var _load_page: Control
var _save_list: SaveList
var _status: Label
var _incidents_switch: CheckButton


func _ready() -> void:
	name = "GameMenu"
	if not open_folder.is_valid():
		open_folder = OS.shell_open
	if save_game != null:
		save_game.loaded.connect(_on_loaded)


## A menu that leaves the tree while open must not leave the game paused (the
## holds also end a hold whose owner leaves).
func _exit_tree() -> void:
	_release(_hold)
	_hold = ClockHolds.NONE
	_release(_question_hold)
	_question_hold = ClockHolds.NONE


## Esc outside build mode opens the menu, unless a card is open: then it closes
## the card first. Esc with the menu up closes it.
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
	if esc_closes.is_valid() and esc_closes.call():
		get_viewport().set_input_as_handled()
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
	audio_card.visible = true
	_settings_page.visible = true


func press_back() -> void:
	if not _shown:
		return
	audio_card.visible = false
	_settings_page.visible = false
	_load_page.visible = false
	_main_page.visible = true


## Save: the manual save (SaveGame.quick_save_path), now or after the next tick
## when a save must wait; the status line says which.
func press_save() -> void:
	if not _shown or save_game == null:
		return
	save_game.request_save(save_game.quick_save_path)
	_set_status(save_game.message_text())
	load_button().disabled = SaveSlots.existing(_save_paths()).is_empty()


## Load: the page listing the saves that exist.
func press_load() -> void:
	if not _shown or save_game == null:
		return
	_save_list.fill(_save_paths(), save_game.quick_save_path)
	_main_page.visible = false
	_load_page.visible = true


## The status line under the pages, "" when it is empty or the menu is closed.
func status_text() -> String:
	return _status.text if _status != null else ""


## The Incidents switch, or null while the menu is closed.
func incidents_switch() -> CheckButton:
	return _incidents_switch


## The version in Project Settings (application/config/version), "" when unset.
static func version_text() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## The corner version label, or null while the menu is closed.
func version_label() -> Label:
	return _layer.get_node_or_null("Root/Version") if _layer != null else null


func resume_button() -> Button:
	return _main_page.get_node("Resume") if _main_page != null else null


func settings_button() -> Button:
	return _main_page.get_node("Settings") if _main_page != null else null


func save_button() -> Button:
	return _main_page.get_node_or_null("Save") if _main_page != null else null


func load_button() -> Button:
	return _main_page.get_node_or_null("Load") if _main_page != null else null


## The Load page's list, or null while the menu is closed.
func save_list() -> SaveList:
	return _save_list


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
	root.add_child(_version_label())
	var pages := VBoxContainer.new()
	pages.add_theme_constant_override("separation", 12)
	panel.add_child(pages)
	_main_page = _page("MainPage", tr("Game menu"))
	pages.add_child(_main_page)
	_button(_main_page, "Resume", tr("Resume ({key})").format({"key": ESC_KEY}), press_resume)
	if save_game != null:
		_button(_main_page, "Save", tr("Save", "menu"), press_save)
		_button(_main_page, "Load", tr("Load", "menu"), press_load)
		load_button().disabled = SaveSlots.existing(_save_paths()).is_empty()
	_button(_main_page, "Settings", tr("Settings"), press_settings)
	audio_card = AudioSettingsCard.new()
	audio_card.name = "AudioSettings"
	audio_card.visible = false
	pages.add_child(audio_card)
	_settings_page = _page("SettingsPage", tr("Settings"))
	_settings_page.visible = false
	pages.add_child(_settings_page)
	_incidents_switch = CheckButton.new()
	_incidents_switch.name = "Incidents"
	_incidents_switch.text = tr("Incidents")
	_incidents_switch.focus_mode = Control.FOCUS_NONE
	_incidents_switch.button_pressed = director != null and director.is_enabled()
	_incidents_switch.toggled.connect(_on_incidents_toggled)
	_settings_page.add_child(_incidents_switch)
	if quit_log != null:
		_add_quit_log_controls()
	_button(_settings_page, "Back", tr("Back"), press_back)
	_load_page = _page("LoadPage", tr("Load", "menu"))
	_load_page.visible = false
	pages.add_child(_load_page)
	_save_list = SaveList.new()
	_save_list.name = "SaveList"
	_save_list.chosen.connect(_on_save_chosen)
	_load_page.add_child(_save_list)
	_button(_load_page, "Back", tr("Back"), press_back)
	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	pages.add_child(_status)
	add_child(_layer)
	QuitLog.note("game_menu_open")
	dialog_changed.emit(true)


## The quit log's switch, the one line saying what it records, and the button
## that opens its folder.
func _add_quit_log_controls() -> void:
	var switch := CheckButton.new()
	switch.name = "QuitLog"
	switch.text = tr("Quit log")
	switch.focus_mode = Control.FOCUS_NONE
	switch.button_pressed = quit_log.is_enabled()
	switch.toggled.connect(_on_quit_log_toggled)
	_settings_page.add_child(switch)
	var note := Label.new()
	note.name = "QuitLogNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(MENU_SIZE.x - 40.0, 0.0)
	note.text = tr(
		# gdlint:ignore = max-line-length
		"Records where you stop playing: the day, money, stars, builds, flights and alerts, never what you click or type. The file stays on this computer and nothing is sent."
	)
	_settings_page.add_child(note)
	_button(_settings_page, "OpenLogFolder", tr("Open log folder"), _on_open_log_folder)


func _on_quit_log_toggled(on: bool) -> void:
	if quit_log == null or quit_log.set_enabled(on):
		return
	# The file would not open: the switch goes back off and the line says why.
	var switch: CheckButton = _settings_page.get_node("QuitLog")
	switch.set_pressed_no_signal(false)
	_set_status(tr("Could not start the quit log in {path}").format({"path": quit_log.log_dir}))


## Opens the quit log folder in the system's file browser, making it first so a
## player who has never switched the log on still gets a folder.
func _on_open_log_folder() -> void:
	if quit_log == null:
		return
	var folder := QuitLog.folder(quit_log.log_dir)
	DirAccess.make_dir_recursive_absolute(folder)
	var err: Variant = open_folder.call(folder)
	if err is int and err != OK:
		_set_status(tr("Could not open the log folder: {path}").format({"path": folder}))


## The game's version in the bottom-right corner, small, read from the project
## setting the exported .exe and the quit log use too.
func _version_label() -> Label:
	var label := Label.new()
	label.name = "Version"
	label.text = tr("v{version}").format({"version": version_text()})
	label.theme_type_variation = &"HudHint"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(
		Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12
	)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	return label


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


## The manual save first, then the autosaves.
func _save_paths() -> Array[String]:
	var paths: Array[String] = [save_game.quick_save_path]
	paths.append_array(SaveSlots.autosave_paths())
	return paths


## A pick from the Load page. A load that goes through closes the menu through
## _on_loaded; a refused one leaves it open and shows why.
func _on_save_chosen(path: String) -> void:
	if not save_game.load_from_file(path):
		_set_status(save_game.message_text())


func _set_status(text: String) -> void:
	if _status == null:
		return
	_status.text = text
	_status.visible = text != ""


func _on_incidents_toggled(on: bool) -> void:
	if director != null:
		director.set_enabled(on)


func _free_layer() -> void:
	_shown = false
	var layer := _layer
	_layer = null
	_main_page = null
	audio_card = null
	_settings_page = null
	_load_page = null
	_save_list = null
	_status = null
	_incidents_switch = null
	if is_instance_valid(layer) and not layer.is_queued_for_deletion():
		layer.queue_free()


func _show_question() -> void:
	_question_layer = CanvasLayer.new()
	_question_layer.name = "IncidentQuestionLayer"
	_question_layer.layer = LAYER
	_question = IntroDialogue.new(tr("Daily incidents"), _question_body(), QUESTION_HEIGHT, true)
	_question_layer.add_child(_question)
	add_child(_question_layer)
	_question.chosen.connect(_on_chosen)
	var close_question := _close_question.bind(_question_layer)
	_question.dismissed.connect(close_question)
	_question.tree_exiting.connect(close_question)
	_question_layer.tree_exiting.connect(close_question)
	dialog_changed.emit(true)


## The question's four paragraphs, each one msgid, joined by line breaks.
func _question_body() -> String:
	var ask := tr(
		# gdlint:ignore = max-line-length
		"One more thing before the doors open. Some days bring trouble: a spill on the floor, an inspector, a holiday rush. Shall I send those your way?"
	)
	var choice := tr(
		# gdlint:ignore = max-line-length
		"Accept turns daily incidents on, Decline leaves them off. You can change this any time: press {key}, then Settings."
	)
	var hold := tr("The clock stays paused until you choose.")
	return "\n".join(PackedStringArray([ask, choice.format({"key": ESC_KEY}), hold]))


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
