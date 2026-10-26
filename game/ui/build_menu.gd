class_name BuildMenu
extends CanvasLayer
## The build menu (decision hud-layout-bottom-category-bar-with-an-item-tray-time-and-fl):
## a bar of categories along the bottom edge; clicking one opens a tray of
## item cards above it (thumbnail, name, size, price, key hint); the status
## and refusal text sits at one fixed place above the tray's reserved space;
## a money slot sits top-left. BuildMode keeps the tool logic: the menu calls
## set_tool() and rotate_facing() and follows tool_changed and status_changed.
## Opening a category picks no tool; picking a card does, and a tool picked by
## key opens its own category. Esc (tool NONE) closes the tray.

const THUMBNAIL_DIR := "res://assets/ui/thumbnails/%s.png"
const CATEGORIES := [
	{
		"name": "Structure",
		"tools":
		[BuildMode.Tool.FLOOR, BuildMode.Tool.WALL, BuildMode.Tool.GLASS, BuildMode.Tool.DOOR],
	},
	{"name": "Doors", "tools": [BuildMode.Tool.ENTRANCE, BuildMode.Tool.EXIT]},
	{"name": "Check-in", "tools": [BuildMode.Tool.DESK]},
	{"name": "Security", "tools": [BuildMode.Tool.SCANNER]},
	{"name": "Gates", "tools": [BuildMode.Tool.SEATS]},
	{"name": "Remove", "tools": [BuildMode.Tool.REMOVE]},
]
## The category that is a single button with no tray.
const REMOVE_CATEGORY := 5
const NO_CATEGORY := -1
## Card name and thumbnail per tool. Object sizes come from BuildCatalog.
const ITEMS := {
	BuildMode.Tool.FLOOR: ["Floor", "floor", "1x1 tile"],
	BuildMode.Tool.WALL: ["Wall", "wall", "1 m edge"],
	BuildMode.Tool.GLASS: ["Glass", "glass", "1 m edge"],
	BuildMode.Tool.DOOR: ["Door", "door", "1 m edge"],
	BuildMode.Tool.ENTRANCE: ["Entrance", "entrance", ""],
	BuildMode.Tool.EXIT: ["Exit", "exit", ""],
	BuildMode.Tool.DESK: ["Check-in desk", "desk", ""],
	BuildMode.Tool.SCANNER: ["Scanner", "scanner", ""],
	BuildMode.Tool.SEATS: ["Seats", "seats", ""],
}
## The price slot until building costs money
## (decision building-costs-money-from-a-starting-budget-you-can-t-build).
const PRICE_TEXT := "Free"
const MONEY_TEXT := "Money  --"

## Geometry in pixels, measured up from the bottom edge.
const MARGIN := 8.0
const BAR_H := 52.0
const GAP := 6.0
const TRAY_H := 196.0
const STATUS_H := 52.0
## Width of the centre column the tray and status line live in; PassengerHud
## keeps the follow text left of it.
const COLUMN_W := 640.0
const CARD_SIZE := Vector2(112.0, 176.0)
const THUMB_SIZE := 72.0
const CATEGORY_SIZE := Vector2(100.0, 44.0)
const ROTATE_SIZE := Vector2(72.0, 176.0)

const PANEL_COLOR := Color(0.07, 0.08, 0.11, 0.86)
const BUTTON_COLOR := Color(0.14, 0.16, 0.21, 0.95)
const HOVER_COLOR := Color(0.2, 0.23, 0.3, 0.95)
const SELECTED_COLOR := Color(0.16, 0.3, 0.48, 1.0)
const BORDER_COLOR := Color(0.3, 0.33, 0.4)
const SELECTED_BORDER := Color(1.0, 0.8, 0.3)

@export var build_mode: BuildMode

var _open := NO_CATEGORY
## True while a category click clears the tool, so the tool_changed(NONE)
## that follows does not close the tray being opened.
var _browsing := false
var _bar := PanelContainer.new()
var _tray := PanelContainer.new()
var _rows: Array[HBoxContainer] = []
var _category_buttons: Array[Button] = []
var _cards: Dictionary = {}
var _status := Label.new()
var _money := Label.new()


static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_corner_radius_all(6)
	style.set_content_margin_all(4.0)
	return style


static func button_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6.0)
	return style


## Gives a button the menu's look; pressed (selected) has a gold border.
static func style_button(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", button_style(BUTTON_COLOR, BORDER_COLOR, 1))
	button.add_theme_stylebox_override("hover", button_style(HOVER_COLOR, BORDER_COLOR, 1))
	var selected := button_style(SELECTED_COLOR, SELECTED_BORDER, 3)
	button.add_theme_stylebox_override("pressed", selected)
	button.add_theme_stylebox_override("hover_pressed", selected)


## "3" for the key bound to a tool's action, or "" when the tool has none.
static func key_hint(tool: BuildMode.Tool) -> String:
	for action in BuildMode.TOOL_ACTIONS:
		if BuildMode.TOOL_ACTIONS[action] != tool or not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			var key := event as InputEventKey
			if key != null:
				return OS.get_keycode_string(key.physical_keycode)
	return ""


## The category a tool belongs to, or NO_CATEGORY.
static func category_of(tool: BuildMode.Tool) -> int:
	for i in CATEGORIES.size():
		if CATEGORIES[i]["tools"].has(tool):
			return i
	return NO_CATEGORY


func _ready() -> void:
	layer = 2
	_build_bar()
	_build_tray()
	_build_status()
	_build_money()
	if build_mode != null:
		build_mode.tool_changed.connect(_on_tool_changed)
		build_mode.status_changed.connect(_on_status_changed)
		_on_status_changed(build_mode.status_text())
		_on_tool_changed(build_mode.tool)
	else:
		_sync()


## The open category, or NO_CATEGORY when the tray is closed.
func open_category() -> int:
	return _open


func is_tray_open() -> bool:
	return _tray.visible


## A category button click: opens its tray (picking no tool), closes it when
## it is already open, or picks Remove, which has no tray.
func press_category(index: int) -> void:
	if index == REMOVE_CATEGORY:
		build_mode.set_tool(BuildMode.Tool.REMOVE)
		return
	if index == _open:
		build_mode.set_tool(BuildMode.Tool.NONE)
		return
	_open = index
	_browsing = true
	build_mode.set_tool(BuildMode.Tool.NONE)
	_browsing = false
	_sync()


## A card click: picks its tool.
func press_card(tool: BuildMode.Tool) -> void:
	build_mode.set_tool(tool)


func category_button(index: int) -> Button:
	return _category_buttons[index]


func card(tool: BuildMode.Tool) -> Button:
	return _cards.get(tool)


func tray() -> Control:
	return _tray


func bar() -> Control:
	return _bar


func status_label() -> Label:
	return _status


func money_label() -> Label:
	return _money


func _on_tool_changed(tool: BuildMode.Tool) -> void:
	if tool == BuildMode.Tool.NONE:
		if not _browsing:
			_open = NO_CATEGORY
	else:
		var index := category_of(tool)
		_open = NO_CATEGORY if index == REMOVE_CATEGORY else index
	_sync()


func _on_status_changed(text: String) -> void:
	_status.text = text


## Shows the open category's row and marks the selected category and card.
func _sync() -> void:
	var tool := BuildMode.Tool.NONE if build_mode == null else build_mode.tool
	_tray.visible = _open != NO_CATEGORY
	for i in _rows.size():
		_rows[i].visible = i == _open
	for i in _category_buttons.size():
		var on := i == _open or (i == REMOVE_CATEGORY and tool == BuildMode.Tool.REMOVE)
		_category_buttons[i].set_pressed_no_signal(on)
	for key in _cards:
		_cards[key].set_pressed_no_signal(key == tool)


## Anchors a control to the bottom centre with its bottom edge `bottom` px up;
## it grows up and out to both sides from there.
func _anchor_bottom_centre(control: Control, bottom: float) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = 0.0
	control.offset_right = 0.0
	control.offset_top = -bottom
	control.offset_bottom = -bottom
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BEGIN


func _build_bar() -> void:
	_bar.name = "CategoryBar"
	_bar.add_theme_stylebox_override("panel", panel_style())
	_bar.custom_minimum_size = Vector2(0.0, BAR_H)
	_anchor_bottom_centre(_bar, MARGIN)
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_bar.add_child(row)
	for i in CATEGORIES.size():
		var button := Button.new()
		button.text = CATEGORIES[i]["name"]
		button.toggle_mode = true
		button.custom_minimum_size = CATEGORY_SIZE
		button.add_theme_font_size_override("font_size", 17)
		style_button(button)
		button.pressed.connect(press_category.bind(i))
		row.add_child(button)
		_category_buttons.append(button)


func _build_tray() -> void:
	_tray.name = "ItemTray"
	_tray.add_theme_stylebox_override("panel", panel_style())
	_tray.custom_minimum_size = Vector2(0.0, TRAY_H)
	_anchor_bottom_centre(_tray, MARGIN + BAR_H + GAP)
	add_child(_tray)
	for i in CATEGORIES.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		_tray.add_child(row)
		_rows.append(row)
		var turns := false
		for tool in CATEGORIES[i]["tools"]:
			if not ITEMS.has(tool):
				continue
			var button := _make_card(tool)
			row.add_child(button)
			_cards[tool] = button
			turns = turns or BuildMode.TOOL_OBJECTS.has(tool)
		if turns:
			row.add_child(_make_rotate_card())


func _make_card(tool: BuildMode.Tool) -> Button:
	var item: Array = ITEMS[tool]
	var button := Button.new()
	button.name = "Card%s" % item[1].capitalize()
	button.toggle_mode = true
	button.custom_minimum_size = CARD_SIZE
	style_button(button)
	button.pressed.connect(press_card.bind(tool))
	var column := _card_column(button)
	var picture := TextureRect.new()
	var path := THUMBNAIL_DIR % item[1]
	if ResourceLoader.exists(path):
		picture.texture = load(path)
	else:
		push_error("BuildMenu: no thumbnail at %s" % path)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(THUMB_SIZE, THUMB_SIZE)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(picture)
	var key := key_hint(tool)
	_card_label(column, item[0], 15, Color.WHITE)
	_card_label(column, _size_text(tool), 14, Color(0.75, 0.8, 0.88))
	_card_label(column, PRICE_TEXT, 14, Color(0.6, 0.9, 0.6))
	_card_label(column, "Key %s" % key if key != "" else "Click", 14, Color(1.0, 0.85, 0.45))
	return button


func _make_rotate_card() -> Button:
	var button := Button.new()
	button.name = "CardRotate"
	button.custom_minimum_size = ROTATE_SIZE
	style_button(button)
	button.pressed.connect(func() -> void: build_mode.rotate_facing())
	var column := _card_column(button)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_label(column, "Rotate", 15, Color.WHITE)
	_card_label(column, "Key R", 14, Color(1.0, 0.85, 0.45))
	return button


func _card_column(button: Button) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 6.0
	column.offset_top = 6.0
	column.offset_right = -6.0
	column.offset_bottom = -6.0
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(column)
	return column


func _card_label(column: VBoxContainer, text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(label)


func _size_text(tool: BuildMode.Tool) -> String:
	if BuildMode.TOOL_OBJECTS.has(tool):
		var def := BuildCatalog.get_def(BuildMode.TOOL_OBJECTS[tool])
		return "%dx%d" % [def.size.x, def.size.y]
	return ITEMS[tool][2]


func _build_status() -> void:
	_status.name = "StatusLine"
	var bottom := MARGIN + BAR_H + GAP + TRAY_H + GAP
	_status.anchor_left = 0.5
	_status.anchor_right = 0.5
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.offset_left = -COLUMN_W / 2.0
	_status.offset_right = COLUMN_W / 2.0
	_status.offset_top = -bottom - STATUS_H
	_status.offset_bottom = -bottom
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_constant_override("outline_size", 6)
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status)


func _build_money() -> void:
	var panel := PanelContainer.new()
	panel.name = "MoneySlot"
	panel.add_theme_stylebox_override("panel", panel_style())
	panel.position = Vector2(16.0, 12.0)
	panel.custom_minimum_size = Vector2(220.0, 0.0)
	add_child(panel)
	_money.text = MONEY_TEXT
	_money.add_theme_font_size_override("font_size", 22)
	panel.add_child(_money)
