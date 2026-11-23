class_name TitleScreen
extends Control
## The title screen, the project's main scene (decision title-menu-with-continue-
## new-airport-load-and-quit-autosave): Continue (the newest save, greyed when
## none exists), New Airport, Load and Quit, stacked in one panel the way Two
## Point Hospital's front menu is. Continue and Load start main.tscn on a save
## through GameBoot; New Airport starts it with nothing to load. Load opens a
## page listing the saves (SaveList), and greys out like Continue when there is
## none. A boot load main.tscn refused comes back here with its message on top.
##
## The demo's wishlist link lives here too. It has no store page yet:
## WISHLIST_URL is an empty placeholder and the button stays hidden until it is
## set.

const PANEL_WIDTH := 520.0
const TITLE_FONT_SIZE := 56
const BACKGROUND := Color(0.52, 0.72, 0.86)
const MESSAGE_COLOR := Color(0.75, 0.16, 0.12)
## The project setting that holds the game's name, shown untranslated.
const NAME_SETTING := "application/config/name"
## PLACEHOLDER: the store page for the wishlist button. Empty until there is one.
const WISHLIST_URL := ""

## Changes to a scene file; tests swap in a recorder. Defaults to the tree's
## change_scene_to_file.
var change_scene: Callable
## Quits the game; tests swap in a recorder.
var quit_game: Callable
## Opens an external URL; tests swap in a recorder.
var open_url: Callable
## Feedback URL shown by the Send Feedback button; hidden when empty.
var feedback_url: String = DemoMode.FEEDBACK_URL
## Collapsible audio settings card below the main menu panel.
var audio_card: AudioSettingsCard
var language_picker: LanguagePicker

var _main_page: VBoxContainer
var _mode_page: VBoxContainer
var _mode_heading: Label
var _mode_summary: Label
var _sandbox_demo_note: Label
var _sandbox_options: VBoxContainer
var _unlimited_toggle: CheckButton
var _budget_note: Label
var _unlock_all_toggle: CheckButton
var _sandbox_selected := false
var _load_page: VBoxContainer
var _load_heading: Label
var _audio_bar: HBoxContainer
var _save_list: SaveList
var _message: Label
var _message_spec := {}
var _buttons := {}


func _ready() -> void:
	name = "TitleScreen"
	if not change_scene.is_valid():
		change_scene = get_tree().change_scene_to_file
	if not quit_game.is_valid():
		quit_game = get_tree().quit
	if not open_url.is_valid():
		open_url = func(url: String) -> void: OS.shell_open(url)
	_build()
	_show_message(GameBoot.take_refusal())
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()


## Greys Continue when no compatible save exists, Load when no save exists at
## all, refreshes the save list, and syncs optional link button visibility.
func refresh() -> void:
	button("Continue").disabled = SaveSlots.latest() == ""
	button("Load").disabled = SaveSlots.existing().is_empty()
	button("SendFeedback").visible = not feedback_url.is_empty()
	_save_list.fill(SaveSlots.all_paths(), SaveSlots.manual_path())
	_sync_mode_page()


func press_continue() -> void:
	var path := SaveSlots.latest()
	if path != "":
		GameBoot.start_load(path, change_scene)


func press_new_airport() -> void:
	_sandbox_selected = false
	if _unlimited_toggle != null:
		_unlimited_toggle.set_pressed_no_signal(true)
	if _unlock_all_toggle != null:
		_unlock_all_toggle.set_pressed_no_signal(true)
	_sync_mode_page()
	_main_page.visible = false
	_load_page.visible = false
	_audio_bar.visible = false
	audio_card.visible = false
	_mode_page.visible = true


func press_start_airport() -> void:
	GameBoot.start_new(change_scene, selected_rules())


func select_career() -> void:
	_sandbox_selected = false
	_sync_mode_page()


func select_sandbox() -> void:
	if DemoMode.is_demo():
		_sandbox_selected = false
	else:
		_sandbox_selected = true
	_sync_mode_page()


func selected_rules() -> GameRules:
	if not _sandbox_selected or DemoMode.is_demo():
		return GameRules.career()
	var unlimited := _unlimited_toggle != null and _unlimited_toggle.button_pressed
	var unlock_all := _unlock_all_toggle != null and _unlock_all_toggle.button_pressed
	return GameRules.make_sandbox(unlimited, unlock_all)


func press_load() -> void:
	refresh()
	_main_page.visible = false
	_mode_page.visible = false
	_audio_bar.visible = false
	audio_card.visible = false
	_load_page.visible = true


func press_back() -> void:
	_load_page.visible = false
	_mode_page.visible = false
	_main_page.visible = true
	_audio_bar.visible = true


func press_audio() -> void:
	audio_card.visible = not audio_card.visible


func press_quit() -> void:
	quit_game.call()


func press_wishlist() -> void:
	if WISHLIST_URL != "" and open_url.is_valid():
		open_url.call(WISHLIST_URL)


func press_feedback() -> void:
	if not feedback_url.is_empty() and open_url.is_valid():
		open_url.call(feedback_url)


## A button by node name: Continue, NewAirport, Load, Wishlist, SendFeedback,
## Quit or Back.
func button(button_name: String) -> Button:
	return _buttons.get(button_name) as Button


func main_page() -> Control:
	return _main_page


func mode_page() -> Control:
	return _mode_page


func save_list() -> SaveList:
	return _save_list


## The message on top (a refused load), "" when none shows.
func message_text() -> String:
	return _message.text if _message.visible else ""


func _build() -> void:
	theme = BuildMenu.HUD_THEME
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.name = "Background"
	background.color = BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.add_theme_constant_override("separation", 24)
	add_child(column)
	var title := Label.new()
	title.name = "GameTitle"
	# The game's name, never translated.
	title.text = str(ProjectSettings.get_setting(NAME_SETTING))
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.theme_type_variation = &"HudLarge"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	column.add_child(title)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(panel)
	var pages := VBoxContainer.new()
	pages.name = "Pages"
	panel.add_child(pages)
	_message = Label.new()
	_message.name = "Message"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", MESSAGE_COLOR)
	_message.visible = false
	pages.add_child(_message)
	_main_page = VBoxContainer.new()
	_main_page.name = "MainPage"
	pages.add_child(_main_page)
	_add_button(_main_page, "Continue", tr("Continue", "menu"), press_continue, &"HudButtonGreen")
	_add_button(_main_page, "NewAirport", tr("New Airport", "menu"), press_new_airport)
	_add_button(_main_page, "Load", tr("Load", "menu"), press_load)
	_add_button(_main_page, "Wishlist", tr("Wishlist", "menu"), press_wishlist)
	button("Wishlist").visible = WISHLIST_URL != ""
	_add_button(_main_page, "SendFeedback", tr("Send Feedback"), press_feedback)
	button("SendFeedback").visible = not feedback_url.is_empty()
	_add_button(_main_page, "Quit", tr("Quit", "menu"), press_quit)
	_build_mode_page(pages)
	_load_page = VBoxContainer.new()
	_load_page.name = "LoadPage"
	_load_page.visible = false
	pages.add_child(_load_page)
	_load_heading = Label.new()
	_load_heading.name = "Heading"
	_load_heading.text = tr("Load", "menu")
	_load_heading.theme_type_variation = &"HudLarge"
	_load_page.add_child(_load_heading)
	_save_list = SaveList.new()
	_save_list.name = "SaveList"
	_save_list.chosen.connect(_on_save_chosen)
	_load_page.add_child(_save_list)
	_add_button(_load_page, "Back", tr("Back", "menu"), press_back)
	_audio_bar = HBoxContainer.new()
	_audio_bar.name = "AudioBar"
	_audio_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_audio_bar.add_theme_constant_override("separation", 12)
	column.add_child(_audio_bar)
	_add_button(_audio_bar, "Audio", tr("Audio", "menu"), press_audio)
	language_picker = LanguagePicker.new()
	language_picker.name = "LanguagePicker"
	_audio_bar.add_child(language_picker)
	audio_card = AudioSettingsCard.new()
	audio_card.name = "AudioSettings"
	audio_card.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	audio_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	audio_card.visible = false
	column.add_child(audio_card)


func _add_button(
	page: Control, button_name: String, text: String, handler: Callable, variation := &""
) -> void:
	var made := Button.new()
	made.name = button_name
	made.text = text
	made.focus_mode = Control.FOCUS_NONE
	made.theme_type_variation = variation
	made.pressed.connect(handler)
	page.add_child(made)
	_buttons[button_name] = made


func _on_save_chosen(path: String) -> void:
	var ver := SaveSlots.file_save_version(path)
	if ver == SaveGame.SAVE_VERSION:
		GameBoot.start_load(path, change_scene)
		return
	if ver < 0:
		_show_save_error(&"unreadable")
	elif ver < SaveGame.SAVE_VERSION:
		_show_save_error(&"older")
	else:
		_show_save_error(&"newer")


func _show_save_error(kind: StringName) -> void:
	_message_spec = {"kind": kind}
	_render_message()


func _show_message(text: String) -> void:
	_message_spec = {} if text == "" else {"raw": text}
	_render_message()


func _render_message() -> void:
	if _message == null:
		return
	if _message_spec.is_empty():
		_message.text = ""
		_message.visible = false
		return
	var text := ""
	match _message_spec.get("kind", &""):
		&"unreadable":
			text = tr("This save file cannot be read.")
		&"older":
			text = tr(
				# gdlint:ignore = max-line-length
				"This save is from an older version and cannot be loaded after an update. Please start a New Airport."
			)
		&"newer":
			text = tr(
				"This save is from a newer version and cannot be loaded. Please update the game."
			)
		_:
			if _message_spec.has("msgid"):
				var ctx := str(_message_spec.get("context", ""))
				var msgid := str(_message_spec["msgid"])
				text = tr(msgid, ctx) if ctx != "" else tr(msgid)
				var args: Dictionary = _message_spec.get("args", {})
				if not args.is_empty():
					text = text.format(args)
			else:
				text = str(_message_spec.get("raw", ""))
	_message.text = text
	_message.visible = text != ""


func _retranslate() -> void:
	button("Continue").text = tr("Continue", "menu")
	button("NewAirport").text = tr("New Airport", "menu")
	button("Load").text = tr("Load", "menu")
	button("Wishlist").text = tr("Wishlist", "menu")
	button("SendFeedback").text = tr("Send Feedback")
	button("Quit").text = tr("Quit", "menu")
	button("Back").text = tr("Back", "menu")
	button("Audio").text = tr("Audio", "menu")
	if _load_heading != null:
		_load_heading.text = tr("Load", "menu")
	if _save_list != null:
		_save_list.fill(SaveSlots.all_paths(), SaveSlots.manual_path())
	if _mode_heading != null:
		_mode_heading.text = tr("New Airport", "menu")
		button("CareerMode").text = tr("Career")
		button("SandboxMode").text = tr("Free-Build Sandbox")
		_sandbox_demo_note.text = tr("In the full game")
		_unlimited_toggle.text = tr("Unlimited Funds")
		_unlock_all_toggle.text = tr("All Tiers & Land Unlocked")
		button("StartAirport").text = tr("Start Airport", "menu")
		button("ModeBack").text = tr("Back", "menu")
		_sync_mode_page()
	_render_message()


func _build_mode_page(pages: Control) -> void:
	_mode_page = VBoxContainer.new()
	_mode_page.name = "ModePage"
	_mode_page.add_theme_constant_override("separation", 10)
	_mode_page.visible = false
	pages.add_child(_mode_page)
	_mode_heading = Label.new()
	_mode_heading.name = "Heading"
	_mode_heading.text = tr("New Airport", "menu")
	_mode_heading.theme_type_variation = &"HudLarge"
	_mode_page.add_child(_mode_heading)
	var mode_row := HBoxContainer.new()
	mode_row.name = "ModeRow"
	mode_row.add_theme_constant_override("separation", 8)
	_mode_page.add_child(mode_row)
	_add_button(mode_row, "CareerMode", tr("Career"), select_career)
	var career_btn := button("CareerMode")
	career_btn.toggle_mode = true
	career_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_button(mode_row, "SandboxMode", tr("Free-Build Sandbox"), select_sandbox)
	var sandbox_btn := button("SandboxMode")
	sandbox_btn.toggle_mode = true
	sandbox_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sandbox_demo_note = Label.new()
	_sandbox_demo_note.name = "SandboxDemoNote"
	_sandbox_demo_note.text = tr("In the full game")
	_sandbox_demo_note.theme_type_variation = &"HudHint"
	_sandbox_demo_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_sandbox_demo_note.visible = DemoMode.is_demo()
	_mode_page.add_child(_sandbox_demo_note)
	_mode_summary = Label.new()
	_mode_summary.name = "ModeSummary"
	_mode_summary.theme_type_variation = &"HudSmall"
	_mode_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_summary.custom_minimum_size = Vector2(PANEL_WIDTH - 32.0, 0.0)
	_mode_page.add_child(_mode_summary)
	_sandbox_options = VBoxContainer.new()
	_sandbox_options.name = "SandboxOptions"
	_sandbox_options.add_theme_constant_override("separation", 4)
	_mode_page.add_child(_sandbox_options)
	_unlimited_toggle = CheckButton.new()
	_unlimited_toggle.name = "UnlimitedFunds"
	_unlimited_toggle.text = tr("Unlimited Funds")
	_unlimited_toggle.button_pressed = true
	_unlimited_toggle.focus_mode = Control.FOCUS_NONE
	_unlimited_toggle.toggled.connect(func(_on: bool) -> void: _sync_mode_page())
	_sandbox_options.add_child(_unlimited_toggle)
	_budget_note = Label.new()
	_budget_note.name = "BudgetNote"
	_budget_note.theme_type_variation = &"HudHint"
	_sandbox_options.add_child(_budget_note)
	_unlock_all_toggle = CheckButton.new()
	_unlock_all_toggle.name = "UnlockAll"
	_unlock_all_toggle.text = tr("All Tiers & Land Unlocked")
	_unlock_all_toggle.button_pressed = true
	_unlock_all_toggle.focus_mode = Control.FOCUS_NONE
	_sandbox_options.add_child(_unlock_all_toggle)
	_add_button(
		_mode_page,
		"StartAirport",
		tr("Start Airport", "menu"),
		press_start_airport,
		&"HudButtonGreen"
	)
	_add_button(_mode_page, "ModeBack", tr("Back", "menu"), press_back)
	_sync_mode_page()


func _sync_mode_page() -> void:
	if _mode_page == null:
		return
	var demo := DemoMode.is_demo()
	if demo:
		_sandbox_selected = false
	var career_btn := button("CareerMode")
	var sandbox_btn := button("SandboxMode")
	career_btn.set_pressed_no_signal(not _sandbox_selected)
	sandbox_btn.set_pressed_no_signal(_sandbox_selected)
	sandbox_btn.disabled = demo
	sandbox_btn.modulate = Color(0.65, 0.65, 0.7, 0.85) if demo else Color.WHITE
	sandbox_btn.tooltip_text = tr("In the full game") if demo else ""
	_sandbox_demo_note.visible = demo
	_sandbox_options.visible = _sandbox_selected and not demo
	if _sandbox_selected and not demo:
		_mode_summary.text = tr("Free-build sandbox with rating, offers, and awards active.")
		if _unlimited_toggle.button_pressed:
			_budget_note.text = tr("No spending limit; Rescue Grant skipped.")
		else:
			_budget_note.text = tr("Starts with $250,000 budget.")
	else:
		_mode_summary.text = tr(
			"Standard $25,000 budget, unlock progression, 1-5★ certification, and Career achievements."
		)
