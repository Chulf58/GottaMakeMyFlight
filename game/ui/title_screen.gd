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


func press_continue() -> void:
	var path := SaveSlots.latest()
	if path != "":
		GameBoot.start_load(path, change_scene)


func press_new_airport() -> void:
	GameBoot.start_new(change_scene)


func press_load() -> void:
	refresh()
	_main_page.visible = false
	_audio_bar.visible = false
	audio_card.visible = false
	_load_page.visible = true


func press_back() -> void:
	_load_page.visible = false
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
	_render_message()
