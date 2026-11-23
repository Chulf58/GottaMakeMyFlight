class_name BuildMenuLayout
extends RefCounted
## The build menu's UI built in code: the category bar, the wrapping grid
## item tray and its compact 80x96 cards (Thumbnail + Name + Price), the status
## card (status line, rotate hint and cost line) and the money slot (split out of
## BuildMenu, which calls these from _ready). Static only: each function takes
## the menu and fills its node and lookup members in the order the menu always
## did, so node names, paths and draw order stay as they were.

## The coin before the money amount.
const COIN_ICON := "res://assets/ui/icons/coin.svg"
## The coin's side and the gap between it and the amount.
const COIN_SIDE := HudLayout.CHIP_H - 4
const COIN_GAP := 6
## A card's horizontal and vertical padding inside its 80x96 button.
const CARD_PAD := 4.0
const CARD_PAD_Y := 2.0
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
		if i == BuildMenuCatalog.remove_category():
			var tbtn := menu.templates_page.button
			tbtn.name = TemplatesPage.BUTTON_NAME
			dress_bar(tbtn, "templates", "Templates")
			tbtn.toggle_mode = true
			tbtn.custom_minimum_size = BuildMenu.CATEGORY_SIZE
			tbtn.focus_mode = Control.FOCUS_NONE
			row.add_child(tbtn)
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
	var panel_base := BuildMenu.HUD_THEME.get_stylebox(&"panel", &"PanelContainer") as StyleBoxFlat
	if panel_base != null:
		var tray_panel := panel_base.duplicate() as StyleBoxFlat
		tray_panel.content_margin_top = 5.0
		tray_panel.content_margin_bottom = 5.0
		menu._tray.add_theme_stylebox_override(&"panel", tray_panel)
	menu._tray.mouse_filter = Control.MOUSE_FILTER_STOP
	menu._tray.custom_minimum_size = Vector2(0.0, BuildMenu.TRAY_H)
	menu._tray.gui_input.connect(menu._on_tray_gui_input)
	anchor_bottom_centre(menu._tray, BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP)
	menu.add_child(menu._tray)
	menu._tray_root.name = "TrayRoot"
	menu._tray_root.add_theme_constant_override("separation", 0)
	menu._tray_root.mouse_filter = Control.MOUSE_FILTER_PASS
	menu._tray.add_child(menu._tray_root)
	var cats := BuildMenuCatalog.categories()
	for i in cats.size():
		var grid := GridContainer.new()
		grid.name = "Grid_" + str(cats[i]["id"])
		grid.columns = BuildMenu.MAX_COLUMNS
		grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		grid.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_theme_constant_override("h_separation", BuildMenu.CARD_SEP)
		grid.add_theme_constant_override("v_separation", BuildMenu.CARD_SEP)
		menu._tray_root.add_child(grid)
		menu._rows.append(grid)
		for tool in cats[i]["tools"]:
			if BuildMenuCatalog.item(tool).is_empty():
				continue
			var button := make_card(menu, tool)
			grid.add_child(button)
			menu._cards[tool] = button
	var pool := menu._room_cards_pool
	pool.name = "RoomCardsPool"
	pool.visible = false
	menu._tray_root.add_child(pool)
	for tool: BuildMode.Tool in BuildMenuCatalog.ROOM_TOOL_OWNERS:
		if BuildMenuCatalog.item(tool).is_empty():
			continue
		var button := make_card(menu, tool)
		pool.add_child(button)
		menu._cards[tool] = button
	build_room_context(menu)


static func build_room_context(menu: BuildMenu) -> void:
	var room_box := menu._room_box
	room_box.name = "RoomContextBox"
	room_box.visible = false
	room_box.add_theme_constant_override("separation", 6)
	room_box.mouse_filter = Control.MOUSE_FILTER_PASS
	menu._tray_root.add_child(room_box)
	var header := menu._room_header
	header.name = "RoomContextHeader"
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	room_box.add_child(header)
	var back := menu._room_back_button
	back.name = "RoomBackButton"
	back.text = _words.back_label()
	back.focus_mode = Control.FOCUS_NONE
	back.theme_type_variation = &"HudButtonCompact"
	back.pressed.connect(menu.exit_room_context)
	header.add_child(back)
	var title := menu._room_title
	title.name = "RoomContextTitle"
	title.theme_type_variation = &"HudCardName"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)
	var summary := menu._room_summary
	summary.name = "RoomContextSummary"
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary.visible = false
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(summary)
	var room_grid := menu._room_grid
	room_grid.name = "RoomContextGrid"
	room_grid.columns = BuildMenu.MAX_COLUMNS
	room_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	room_grid.mouse_filter = Control.MOUSE_FILTER_PASS
	room_grid.add_theme_constant_override("h_separation", BuildMenu.CARD_SEP)
	room_grid.add_theme_constant_override("v_separation", BuildMenu.CARD_SEP)
	room_box.add_child(room_grid)


static func make_card(menu: BuildMenu, tool: BuildMode.Tool, price_table: Variant = null) -> Button:
	var prices: Dictionary = menu._price_labels if price_table == null else price_table
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
	name_label.add_theme_constant_override(&"line_spacing", 0)
	var price_label := card_label(column, _words.free_price(), &"HudPrice", PRICE_LINES)
	price_label.name = "Price"
	prices[tool] = price_label
	watch_fit(button)
	if BuildMenuCatalog.is_room_tool(tool):
		add_card_badge(
			button, BuildMenuCatalog.shown("Room"), Color(0.55, 0.80, 0.80, 0.96), &"RoomBadge"
		)
	return button


static func apply_required_badge(button: Control, mandatory: bool, satisfied: bool) -> void:
	var existing := button.get_node_or_null("RequiredBadge") as PanelContainer
	if not mandatory:
		if existing != null:
			existing.visible = false
		return
	var text := _words.satisfied_mark() if satisfied else _words.required_mark()
	var bg := Color(0.50, 0.80, 0.45, 0.96) if satisfied else Color(1.0, 0.85, 0.40, 0.96)
	if existing == null:
		add_card_badge(button, text, bg, &"RequiredBadge")
		return
	existing.visible = true
	var style := existing.get_theme_stylebox(&"panel") as StyleBoxFlat
	if style != null:
		style.bg_color = bg
	var lbl := existing.get_node_or_null("RequiredBadgeLabel") as Label
	if lbl != null:
		lbl.text = text


## Compact corner pill over a card's top-left corner (`Room`, `Locked`, `3x4`).
static func add_card_badge(
	button: Control, text: String, bg: Color, badge_name: StringName = &"CardBadge"
) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.name = badge_name
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.offset_left = 4.0
	pill.offset_top = 4.0
	pill.grow_horizontal = Control.GROW_DIRECTION_END
	pill.grow_vertical = Control.GROW_DIRECTION_END
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.1, 0.13, 0.26, 1.0)
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_right = 5
	style.corner_radius_bottom_left = 5
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	pill.add_theme_stylebox_override(&"panel", style)
	var label := Label.new()
	label.name = String(badge_name) + "Label"
	label.text = text
	label.add_theme_font_size_override(&"font_size", 10)
	label.add_theme_color_override(&"font_color", Color(0.1, 0.13, 0.26, 1.0))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(label)
	button.add_child(pill)
	return pill


static func sync_status_card_bottom(card: Control, bottom: float) -> void:
	card.offset_top = -bottom - BuildMenu.STATUS_H
	card.offset_bottom = -bottom


static func card_column(button: Button) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = CARD_PAD
	column.offset_top = CARD_PAD_Y
	column.offset_right = -CARD_PAD
	column.offset_bottom = -CARD_PAD_Y
	column.add_theme_constant_override("separation", 0)
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
	label.autowrap_mode = (
		TextServer.AUTOWRAP_OFF if lines <= 1 else TextServer.AUTOWRAP_WORD_SMART
	)
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


## Fits Name (up to CARD_LINES lines) and Price (1 line) inside `button` without
## clipping horizontally or overflowing vertically, while keeping Thumbnail fixed
## at BuildMenu.THUMB_SIZE. Measured from the font, not the Label, because a
## wrapping Label reports its height only after the container has sized it.
static func fit_card(button: Button) -> void:
	if not button.is_inside_tree():
		return
	var column := button.get_child(0) as VBoxContainer
	var width := button.custom_minimum_size.x - 2.0 * CARD_PAD
	var labels: Array[Label] = []
	var thumb_h := 0.0
	for child in column.get_children():
		if child is Label:
			labels.append(child as Label)
		elif child is Control and (child as Control).visible:
			thumb_h += (child as Control).custom_minimum_size.y
	if labels.is_empty():
		return
	var sep := (
		float(column.get_theme_constant(&"separation"))
		* float(maxi(0, column.get_child_count() - 1))
	)
	var inner_h := button.custom_minimum_size.y - 2.0 * CARD_PAD_Y - thumb_h - sep
	var name_label: Label = null
	var used_h := 0.0
	for label in labels:
		var max_lines := label.max_lines_visible if label.max_lines_visible > 0 else CARD_LINES
		if max_lines > 1 and name_label == null:
			name_label = label
			continue
		var font := label.get_theme_font(&"font")
		var text := label.atr(label.text)
		var size := _fit_font_to_width(text, font, width, max_lines)
		if label.get_theme_font_size(&"font_size") != size:
			label.add_theme_font_size_override(&"font_size", size)
		used_h += font.get_height(size)
	if name_label != null:
		var font := name_label.get_theme_font(&"font")
		var text := name_label.atr(name_label.text)
		var max_lines := name_label.max_lines_visible
		var size := _fit_font_to_width(text, font, width, max_lines)
		var avail_h := maxf(0.0, inner_h - used_h)
		var line_sp := float(name_label.get_theme_constant(&"line_spacing"))
		while size > 9:
			var lines := HudLayout.line_count(text, font, size, width)
			var needed_h := (
				float(lines) * font.get_height(size) + float(maxi(0, lines - 1)) * line_sp
			)
			if needed_h <= avail_h + 0.5:
				break
			size = HudLayout.step_down(size) if size > HudLayout.FIT_STEP else size - 1
		if name_label.get_theme_font_size(&"font_size") != size:
			name_label.add_theme_font_size_override(&"font_size", size)


static func _fit_font_to_width(text: String, font: Font, width: float, max_lines: int) -> int:
	var size: int
	if max_lines <= 1:
		size = HudLayout.CAPTION
		while (
			size > 8 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width
		):
			size -= 1
		return size
	size = HudLayout.fit_size(text, font, HudLayout.CAPTION, width, max_lines)
	while (
		size > 9
		and (
			HudLayout.line_count(text, font, size, width) > max_lines
			or HudLayout.widest_word(text, font, size) > width
		)
	):
		size -= 1
	return size


static func size_text(tool: BuildMode.Tool) -> String:
	return BuildMenuCatalog.size_text(tool)


## The status card (HUD 5/7): the status line, the "R rotate" hint and the cost
## line side by side on one HudTopCard, TRAY_W wide and BUTTON_H tall, GAP above
## the tray (or above the bar while the tray is closed) and centred. The status
## text takes the room the hint and the cost
## leave and wraps onto a second line when it is longer (the card grows up for
## it), then ends in an ellipsis; the hint and the cost keep their own width, so
## neither wraps. The card never takes a click.
static func build_status_card(menu: BuildMenu) -> void:
	var card := menu._status_card
	card.name = "StatusCard"
	var bottom := BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.offset_left = -BuildMenu.COLUMN_W / 2.0
	card.offset_right = BuildMenu.COLUMN_W / 2.0
	sync_status_card_bottom(card, bottom)
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

	func back_label() -> String:
		return tr("← Back")

	func required_mark() -> String:
		return tr("★")

	func satisfied_mark() -> String:
		return tr("✓")
