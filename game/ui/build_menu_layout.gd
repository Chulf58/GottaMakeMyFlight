class_name BuildMenuLayout
extends RefCounted
## The build menu's UI built in code: the category bar, the item tray and its
## cards, the status card (status line, rotate hint and cost line) and the money
## slot (split out of BuildMenu, which calls these from _ready). Static only: each function takes
## the menu and fills its node and lookup members in the order the menu always
## did, so node names, paths and draw order stay as they were.


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
	for i in BuildMenuCatalog.categories().size():
		var button := Button.new()
		# A later page's button stays hidden: it is there to keep the indices.
		if not BuildMenuCatalog.categories()[i].get("page", false):
			BarIcons.dress(button, BuildMenuCatalog.bar_name(i))
			# A name to find it by, now that it shows no text (BarDecor, BarCheckin).
			button.name = "Bar" + BuildMenuCatalog.bar_name(i).replace("-", "").replace(" ", "")
		button.toggle_mode = true
		button.custom_minimum_size = BuildMenu.CATEGORY_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(menu.press_category.bind(i))
		button.visible = not BuildMenuCatalog.categories()[i].get("page", false)
		row.add_child(button)
		menu._category_buttons.append(button)
	menu.staff_button.name = "StaffButton"
	BarIcons.dress(menu.staff_button, "Staff")
	menu.staff_button.toggle_mode = true
	menu.staff_button.custom_minimum_size = BuildMenu.CATEGORY_SIZE
	menu.staff_button.focus_mode = Control.FOCUS_NONE
	menu.staff_button.pressed.connect(menu.press_staff)
	row.add_child(menu.staff_button)


static func build_tray(menu: BuildMenu) -> void:
	menu._tray.name = "ItemTray"
	menu._tray.theme = BuildMenu.HUD_THEME
	menu._tray.custom_minimum_size = Vector2(0.0, BuildMenu.TRAY_H)
	anchor_bottom_centre(menu._tray, BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP)
	menu.add_child(menu._tray)
	for i in BuildMenuCatalog.categories().size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		menu._tray.add_child(row)
		menu._rows.append(row)
		for tool in BuildMenuCatalog.categories()[i]["tools"]:
			if BuildMenuCatalog.item(tool).is_empty():
				continue
			var button := make_card(menu, tool)
			row.add_child(button)
			menu._cards[tool] = button
		if BuildMenuCatalog.next_page(i) != BuildMenuCatalog.NO_CATEGORY:
			row.add_child(make_next_card(menu, BuildMenuCatalog.next_page(i)))


static func make_card(menu: BuildMenu, tool: BuildMode.Tool) -> Button:
	var card_item := BuildMenuCatalog.item(tool)
	var button := ItemCardButton.new()
	button.set_info(card_item[0], ItemInfo.of(tool))
	button.name = "Card%s" % card_item[1].capitalize()
	button.toggle_mode = true
	button.custom_minimum_size = BuildMenu.CARD_SIZE
	button.focus_mode = Control.FOCUS_NONE
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
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(picture)
	var key := BuildMenuCatalog.key_hint(tool)
	card_label(column, card_item[0], &"HudCardName")
	card_label(column, size_text(tool), &"HudHint")
	menu._price_labels[tool] = card_label(column, BuildMenu.PRICE_TEXT, &"HudPrice")
	if BuildMenuCatalog.CARD_NEEDS.has(tool):
		var need := card_label(column, BuildMenuCatalog.CARD_NEEDS[tool], &"HudAttentionText")
		need.add_theme_font_size_override("font_size", BuildMenu.CARD_HINT_FONT_SIZE)
		menu._hint_labels[tool] = need
	elif BuildMenuCatalog.running_cost(tool) > 0:
		menu._hint_labels[tool] = card_label(
			column,
			BuildMenuCatalog.RUNNING_COST_TEXT % BuildMenuCatalog.running_cost(tool),
			&"HudHint"
		)
	else:
		menu._hint_labels[tool] = card_label(
			column, "Key %s" % key if key != "" else BuildMenuCatalog.no_key_hint(tool), &"HudHint"
		)
	menu._hint_texts[tool] = menu._hint_labels[tool].text
	return button


## The Next card, which opens the page after this one.
static func make_next_card(menu: BuildMenu, next: int) -> Button:
	var button := Button.new()
	button.name = "CardNext"
	button.custom_minimum_size = BuildMenu.NEXT_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(menu.press_category.bind(next))
	var column := card_column(button)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	card_label(column, "Next", &"HudCardName")
	card_label(column, BuildMenuCatalog.categories()[next]["name"], &"HudHint")
	return button


static func card_column(button: Button) -> VBoxContainer:
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


static func card_label(column: VBoxContainer, text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(label)
	return label


static func size_text(tool: BuildMode.Tool) -> String:
	if BuildMode.tool_object(tool) != &"":
		var def := BuildCatalog.get_def(BuildMode.tool_object(tool))
		return "%dx%d" % [def.size.x, def.size.y]
	return BuildMenuCatalog.item(tool)[2]


## The status card (HUD 5/7): the status line, the "R rotate" hint and the cost
## line side by side on one HudTopCard, TRAY_W wide and BUTTON_H tall, GAP above
## the tray and centred. The status text takes the room the hint and the cost
## leave and is cut short with an ellipsis when it is longer; the hint and the
## cost keep their own width, so neither wraps. The card never takes a click.
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
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.max_lines_visible = 3
	status.clip_text = true
	status.theme_type_variation = &"HudCardName"
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(status)
	var hint := menu._rotate_hint
	hint.name = "RotateHint"
	hint.text = RotateHint.TEXT
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
	panel.add_child(menu._money)
