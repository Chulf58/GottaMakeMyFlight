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

var _main_page: VBoxContainer
var _load_page: VBoxContainer
var _save_list: SaveList
var _message: Label
var _buttons := {}


func _ready() -> void:
	name = "TitleScreen"
	if not change_scene.is_valid():
		change_scene = get_tree().change_scene_to_file
	if not quit_game.is_valid():
		quit_game = get_tree().quit
	_build()
	_show_message(GameBoot.take_refusal())
	refresh()


## Greys Continue and Load when there is no save, and refills the save list.
func refresh() -> void:
	var none := SaveSlots.latest() == ""
	button("Continue").disabled = none
	button("Load").disabled = none
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
	_load_page.visible = true


func press_back() -> void:
	_load_page.visible = false
	_main_page.visible = true


func press_quit() -> void:
	quit_game.call()


func press_wishlist() -> void:
	if WISHLIST_URL != "":
		OS.shell_open(WISHLIST_URL)


## A button by node name: Continue, NewAirport, Load, Wishlist, Quit or Back.
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
	_add_button(_main_page, "Continue", tr("Continue"), press_continue, &"HudButtonGreen")
	_add_button(_main_page, "NewAirport", tr("New Airport"), press_new_airport)
	_add_button(_main_page, "Load", tr("Load", "menu"), press_load)
	_add_button(_main_page, "Wishlist", tr("Wishlist"), press_wishlist)
	button("Wishlist").visible = WISHLIST_URL != ""
	_add_button(_main_page, "Quit", tr("Quit"), press_quit)
	_load_page = VBoxContainer.new()
	_load_page.name = "LoadPage"
	_load_page.visible = false
	pages.add_child(_load_page)
	var heading := Label.new()
	heading.name = "Heading"
	heading.text = tr("Load", "menu")
	heading.theme_type_variation = &"HudLarge"
	_load_page.add_child(heading)
	_save_list = SaveList.new()
	_save_list.name = "SaveList"
	_save_list.chosen.connect(_on_save_chosen)
	_load_page.add_child(_save_list)
	_add_button(_load_page, "Back", tr("Back"), press_back)


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
	GameBoot.start_load(path, change_scene)


func _show_message(text: String) -> void:
	_message.text = text
	_message.visible = text != ""
