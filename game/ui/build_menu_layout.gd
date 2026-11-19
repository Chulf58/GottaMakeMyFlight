class_name BuildMenuLayout
extends RefCounted
## The build menu's UI built in code: the category bar, the horizontal-scroll
## item tray and its compact cards (Thumbnail + Name + Price), the status card
## (status line, rotate hint and cost line) and the money slot (split out of
## BuildMenu, which calls these from _ready). Static only: each function takes
## the menu and fills its node and lookup members in the order the menu always
## did, so node names, paths and draw order stay as they were.

## The coin before the money amount.
const COIN_ICON := "res://assets/ui/icons/coin.svg"
## The coin's side and the gap between it and the amount.
const COIN_SIDE := HudLayout.CHIP_H - 4
const COIN_GAP := 6
## A card's padding on each side of its column.
const CARD_PAD := 4.0
## A card name wraps onto at most two lines, then drops one font step
## (decision build-menu-card-names-wrap-to-two-lines-then-shrink-a-font-s).
const CARD_LINES := 2
const PRICE_LINES := 1

static var _words := Words.new()


## Anchors a control to the bottom centre with its bottom edge `bottom` px up;
## it grows up and out to both sides from there.
static func anchor_bottom_centre(control: Control, bottom: float) -> void:
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


static func build_bar(menu: BuildMenu) -> void:
	menu._bar.name = "CategoryBar"
	menu._bar.theme = BuildMenu.HUD_THEME
	menu._bar.theme_type_variation = &"HudBar"
	menu._bar.custom_minimum_size = Vector2(0.0, BuildMenu.BAR_H)
	anchor_bottom_centre(menu._bar, BuildMenu.MARGIN)
	menu.add_child(menu._bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	menu._bar.add_child(row)
	var cats := BuildMenuCatalog.categories()
	for i in cats.size():
		var button := Button.new()
		var cat: Dictionary = cats[i]
		var cat_id: String = cat["id"]
		var cat_name: String = cat["name"]
		dress_bar(button, cat_id, cat_name)
		button.name = "Bar" + cat_id.capitalize().replace(" ", "")
		button.toggle_mode = true
		button.custom_minimum_size = BuildMenu.CATEGORY_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(menu.press_category.bind(i))
		row.add_child(button)
		menu._category_buttons.append(button)
	menu.staff_button.name = "StaffButton"
	dress_bar(menu.staff_button, "staff", "Staff")
	menu.staff_button.toggle_mode = true
	menu.staff_button.custom_minimum_size = BuildMenu.CATEGORY_SIZE
	menu.staff_button.focus_mode = Control.FOCUS_NONE
	menu.staff_button.pressed.connect(menu.press_staff)
	row.add_child(menu.staff_button)


static func build_tray(menu: BuildMenu) -> void:
	menu._tray.name = "ItemTray"
	menu._tray.theme = BuildMenu.HUD_THEME
	menu._tray.mouse_filter = Control.MOUSE_FILTER_STOP
	menu._tray.custom_minimum_size = Vector2(0.0, BuildMenu.TRAY_H)
	menu._tray.gui_input.connect(menu._on_tray_gui_input)
	anchor_bottom_centre(menu._tray, BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP)
	menu.add_child(menu._tray)
	menu._scroll.name = "TrayScroll"
	# Ignore on the ScrollContainer itself so wheel events over cards and over tray
	# padding both reach _tray._on_tray_gui_input with one unified WHEEL_STEP while
	# child cards and the internal HScrollBar keep their own mouse input.
	menu._scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu._scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu._scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_RESERVE
	menu._scroll_content.name = "TrayRows"
	menu._scroll_content.mouse_filter = Control.MOUSE_FILTER_PASS
	menu._scroll_content.add_theme_constant_override("separation", 0)
	menu._scroll_content.minimum_size_changed.connect(menu._sync_scroll_width)
	menu._scroll.add_child(menu._scroll_content)
	menu._tray.add_child(menu._scroll)
	var cats := BuildMenuCatalog.categories()
	for i in cats.size():
		var row := HBoxContainer.new()
		row.name = "Row_" + str(cats[i]["id"])
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_theme_constant_override("separation", 6)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		menu._scroll_content.add_child(row)
		menu._rows.append(row)
		for tool in cats[i]["tools"]:
			if BuildMenuCatalog.item(tool).is_empty():
				continue
			var button := make_card(menu, tool)
			row.add_child(button)
			menu._cards[tool] = button


static func make_card(menu: BuildMenu, tool: BuildMode.Tool) -> Button:
	var card_item := BuildMenuCatalog.item(tool)
	var button := ItemCardButton.new()
	button.set_info(
		BuildMenuCatalog.shown(card_item[0]), ItemInfo.of(tool), BuildMenuCatalog.card_details(tool)
	)
	button.name = "Card%s" % card_item[1].capitalize()
	button.toggle_mode = true
	button.custom_minimum_size = BuildMenu.CARD_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.pressed.connect(menu.press_card.bind(tool))
	var column := card_column(button)
	var picture := TextureRect.new()
	var path := BuildMenuCatalog.THUMBNAIL_DIR % card_item[1]
	if ResourceLoader.exists(path):
		picture.texture = load(path)
	elif BuildMenu.PLACEHOLDER_THUMBNAILS.has(card_item[1]):
		var tile := ColorRect.new()
		tile.color = BuildMenu.PLACEHOLDER_COLOR
		tile.set_anchors_preset(Control.PRESET_FULL_RECT)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.add_child(tile)
	else:
		push_error("BuildMenu: no thumbnail at %s" % path)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(BuildMenu.THUMB_SIZE, BuildMenu.THUMB_SIZE)
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.name = "Thumbnail"
	column.add_child(picture)
	var name_label := card_label(
		column, BuildMenuCatalog.shown(card_item[0]), &"HudCardName", CARD_LINES
	)
	name_label.name = "Name"
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var price_label := card_label(column, _words.free_price(), &"HudPrice", PRICE_LINES)
	price_label.name = "Price"
	menu._price_labels[tool] = price_label
	watch_fit(button)
	return button


static func card_column(button: Button) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = CARD_PAD
	column.offset_top = CARD_PAD
	column.offset_right = -CARD_PAD
	column.offset_bottom = -CARD_PAD
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(column)
	return column


## A card line: centred, wrapping onto `lines` lines; fit_card() gives it its
## font size once the card is in the tree.
static func card_label(
	column: VBoxContainer, text: String, variation: StringName, lines: int
) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = lines
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(label)
	return label


## Fits the card when it enters the tree and again after a line redraws, which a
## new text (a price, "Locked", "In the full game") always causes; a wrapping
## Label's minimum size can stay the same for a longer text, so that signal would
## miss it. A fit that changes nothing causes no redraw, so this settles.
static func watch_fit(button: Button) -> void:
	button.tree_entered.connect(fit_card.bind(button))
	for label in button.get_child(0).get_children():
		if label is Label:
			(label as Label).draw.connect(fit_card.bind(button), CONNECT_DEFERRED)


## Wraps Name onto up to CARD_LINES lines at the caption size, one font step
## smaller only when that is still not enough (decision
## build-menu-card-names-wrap-to-two-lines-then-shrink-a-font-s), fits single-line
## Price onto PRICE_LINES, and keeps Thumbnail fixed at BuildMenu.THUMB_SIZE
## across both 1-line and 2-line card names. Measured from the font, not the
## Label, because a wrapping Label reports its height only after the container
## has sized it.
static func fit_card(button: Button) -> void:
	if not button.is_inside_tree():
		return
	var column := button.get_child(0) as VBoxContainer
	var width := button.custom_minimum_size.x - 2.0 * CARD_PAD
	for child in column.get_children():
		if not child is Label:
			continue
		var label := child as Label
		var font := label.get_theme_font(&"font")
		# atr() is the text the Label draws (it honours auto_translate_mode), so the
		# fit measures what is shown, whether it is expanded once or twice.
		var text := label.atr(label.text)
		var max_lines := label.max_lines_visible if label.max_lines_visible > 0 else CARD_LINES
		var size := HudLayout.fit_size(text, font, HudLayout.CAPTION, width, max_lines)
		if max_lines == 1:
			while (
				size > 9
				and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width
			):
				size -= 1
		if label.get_theme_font_size(&"font_size") != size:
			label.add_theme_font_size_override(&"font_size", size)


static func size_text(tool: BuildMode.Tool) -> String:
	return BuildMenuCatalog.size_text(tool)


## The status card (HUD 5/7): the status line, the "R rotate" hint and the cost
## line side by side on one HudTopCard, TRAY_W wide and BUTTON_H tall, GAP above
## the tray and centred. The status text takes the room the hint and the cost
## leave and wraps onto a second line when it is longer (the card grows up for
## it), then ends in an ellipsis; the hint and the cost keep their own width, so
## neither wraps. The card never takes a click.
static func build_status_card(menu: BuildMenu) -> void:
	var card := menu._status_card
	card.name = "StatusCard"
	var bottom := (
		BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP + BuildMenu.TRAY_H + BuildMenu.GAP
	)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.offset_left = -BuildMenu.COLUMN_W / 2.0
	card.offset_right = BuildMenu.COLUMN_W / 2.0
	card.offset_top = -bottom - BuildMenu.STATUS_H
	card.offset_bottom = -bottom
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.theme = BuildMenu.HUD_THEME
	card.theme_type_variation = &"HudTopCard"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.visible = false
	menu.add_child(card)
	var row := HBoxContainer.new()
	row.name = "StatusRow"
	row.add_theme_constant_override("separation", HudLayout.GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var status := menu._status
	status.name = "StatusLine"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.max_lines_visible = BuildMenu.STATUS_LINES
	status.theme_type_variation = &"HudCardName"
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(status)
	var hint := menu._rotate_hint
	hint.name = "RotateHint"
	hint.text = RotateHint.text()
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.theme_type_variation = &"HudHint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.visible = false
	row.add_child(hint)
	var cost := menu._cost
	cost.name = "CostLine"
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost.theme_type_variation = &"HudCardName"
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.visible = false
	row.add_child(cost)


static func build_money(menu: BuildMenu) -> void:
	var panel := menu._money_slot
	panel.name = "MoneySlot"
	panel.theme = BuildMenu.HUD_THEME
	panel.theme_type_variation = &"HudTopCard"
	panel.position = Vector2(HudLayout.MARGIN, HudLayout.MARGIN)
	panel.custom_minimum_size = Vector2(HudLayout.MONEY_W, HudLayout.BUTTON_H)
	menu.add_child(panel)
	menu._money.text = BuildMenu.MONEY_TEXT
	menu._money.theme_type_variation = &"HudMoney"
	menu._money.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A coin stands where the word "Money" was, so the slot has nothing to translate. The
	# coin and the amount are both direct children of the card (the card is the amount's
	# parent, and it keeps its own height and margin); the amount's left padding clears
	# the coin.
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = COIN_SIDE + COIN_GAP
	menu._money.add_theme_stylebox_override("normal", pad)
	var coin := TextureRect.new()
	coin.name = "MoneyIcon"
	coin.texture = load(COIN_ICON)
	coin.custom_minimum_size = Vector2(COIN_SIDE, COIN_SIDE)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(menu._money)
	panel.add_child(coin)


## A bar button's icon (keyed by stable `bar_id`) and its translated name in the tooltip.
static func dress_bar(button: Button, bar_id: String, label_msgid: String) -> void:
	BarIcons.dress(button, bar_id)
	button.tooltip_text = BuildMenuCatalog.shown(label_msgid)
	if button.text != "":
		button.text = button.tooltip_text


## tr() is an instance method, so the static code of this file asks a Words.
class Words:
	extends RefCounted

	func free_price() -> String:
		return tr("Free", "price")
