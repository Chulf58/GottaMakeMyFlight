class_name TemplatesPage
extends ScrollContainer
## The Templates page of the build tray (decision room-templates-store-rooms-
## with-their-pieces-kept-in-each-sa): a Save room card that arms saving
## (TemplatePaste.arm_capture()), one card per saved template that arms its
## paste, and a Rotate card. Its Templates button opens and closes it
## (BuildMenu.press_category(TEMPLATES_PAGE)); the page scrolls
## sideways when the cards are wider than the tray's column.
##
## A template card shows its name, its size and what its pieces cost; its
## picture is a plain tile with the room type's name until template thumbnails
## exist.
##
## The button sits on its own small panel at the left edge, just above the
## height of the category bar, not in the bar: every bar button carries a drawn icon and
## the bar keeps 200 px clear of each edge at 1536 px wide (HUD 6/7), and
## there is no Templates icon yet. Where it finally goes is open.

const SAVE_CARD := "CardSaveRoom"
const BUTTON_NAME := "TemplatesButton"

## The button that opens the page, on `dock`.
var button := Button.new()
var dock := PanelContainer.new()

var _menu: BuildMenu
var _paste: TemplatePaste
var _row := HBoxContainer.new()
var _cards: Array[Button] = []
var _save_card: Button


## Puts the page in `menu`'s tray and its button at the left edge above the bar.
func attach(menu: BuildMenu) -> void:
	_menu = menu
	name = "TemplatesPage"
	visible = false
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	custom_minimum_size = Vector2(BuildMenu.COLUMN_W, BuildMenu.CARD_SIZE.y + 12.0)
	_row.add_theme_constant_override("separation", 6)
	add_child(_row)
	menu.tray().add_child(self)
	button.name = BUTTON_NAME
	button.text = "Templates"
	button.tooltip_text = "Templates"
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0.0, BuildMenu.CATEGORY_SIZE.y)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(menu.press_category.bind(BuildMenu.TEMPLATES_PAGE))
	dock.name = "TemplatesDock"
	dock.theme = BuildMenu.HUD_THEME
	dock.theme_type_variation = &"HudBar"
	dock.custom_minimum_size = Vector2(0.0, BuildMenu.BAR_H)
	dock.anchor_top = 1.0
	dock.anchor_bottom = 1.0
	dock.offset_left = BuildMenu.MARGIN
	var bottom := BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP
	dock.offset_top = -bottom
	dock.offset_bottom = -bottom
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dock.add_child(button)
	menu.add_child(dock)
	if menu.build_mode != null:
		_paste = menu.build_mode.templates
		_paste.library.changed.connect(_rebuild)
		_paste.armed_changed.connect(_mark_cards)
	_rebuild()


## Shows or hides the page and marks its button.
func sync(open: bool) -> void:
	visible = open
	button.set_pressed_no_signal(open)


## The card of template `index`.
func card(index: int) -> Button:
	return _cards[index]


func save_card() -> Button:
	return _save_card


func card_count() -> int:
	return _cards.size()


func _rebuild() -> void:
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_cards.clear()
	_save_card = _make_card(SAVE_CARD, "Save room", ["Pick a room", "", "Click"])
	if _paste != null:
		_save_card.pressed.connect(_paste.arm_capture)
	_row.add_child(_save_card)
	var count := _paste.library.size() if _paste != null else 0
	for i in count:
		var template := _paste.library.get_template(i)
		var price := template.price()
		var lines := [
			"%dx%d" % [template.size.x, template.size.y],
			"Free" if price == 0 else str(price),
			"Click",
		]
		var room := RoomTypes.get_type(template.room_type).display_name
		var each := _make_card("CardTemplate%d" % i, template.name, lines, room)
		each.pressed.connect(func() -> void: _paste.arm(i))
		_row.add_child(each)
		_cards.append(each)
	var rotate := _make_card("CardRotate", "Rotate", ["Key R"])
	rotate.toggle_mode = false
	rotate.custom_minimum_size.x = 72.0
	rotate.pressed.connect(_rotate)
	_row.add_child(rotate)
	_mark_cards()


## A card: the plain picture tile (when `picture` is given), the name, then one
## label per line (size, price, hint).
func _make_card(card_name: String, title: String, lines: Array, picture := "") -> Button:
	var card_button := Button.new()
	card_button.name = card_name
	card_button.toggle_mode = true
	card_button.custom_minimum_size = BuildMenu.CARD_SIZE
	card_button.focus_mode = Control.FOCUS_NONE
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 6.0
	column.offset_top = 6.0
	column.offset_right = -6.0
	column.offset_bottom = -6.0
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_button.add_child(column)
	if picture != "":
		var tile := ColorRect.new()
		tile.color = BuildMenu.PLACEHOLDER_COLOR
		tile.custom_minimum_size = Vector2(BuildMenu.THUMB_SIZE, BuildMenu.THUMB_SIZE)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := _label(picture, &"HudCardName")
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color(0.98, 0.94, 0.85))
		tile.add_child(label)
		column.add_child(tile)
	column.add_child(_label(title, &"HudCardName"))
	var variations := [&"HudHint", &"HudPrice", &"HudHint"]
	for i in lines.size():
		column.add_child(_label(lines[i], variations[mini(i, variations.size() - 1)]))
	return card_button


func _label(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _rotate() -> void:
	if _paste != null and _paste.armed >= 0:
		_paste.rotate_turns()


func _mark_cards() -> void:
	if _paste == null:
		return
	_save_card.set_pressed_no_signal(_paste.capturing)
	for i in _cards.size():
		_cards[i].set_pressed_no_signal(_paste.armed == i)
