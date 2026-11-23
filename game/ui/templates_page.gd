class_name TemplatesPage
extends ScrollContainer
## The Templates page inside the build tray (decisions room-templates-store-
## rooms-with-their-pieces-kept-in-each-sa and hud-layout-templates-tab-
## refinement-320-px-right-rail-compac): its button sits inside the bottom
## category bar between the domain tabs and Remove, and opens a horizontal row
## of Save room + rendered room template preview cards with size/lock badges.

const SAVE_CARD := "CardSaveRoom"
const BUTTON_NAME := "TemplatesButton"
const TEMPLATE_ICON := "res://assets/ui/icons/templates.svg"
const TEMPLATE_CARD_SIZE := Vector2(80.0, 96.0)
const TEMPLATE_THUMB_SIZE := 40.0

## The button that opens the page, placed inside CategoryBar by BuildMenuLayout.
var button := Button.new()

var _menu: BuildMenu
var _paste: TemplatePaste
var _row := HBoxContainer.new()
var _cards: Array[Button] = []
var _badges: Array[PanelContainer] = []
var _price_labels: Array[Label] = []
var _save_card: Button


## Puts the page inside `menu`'s tray content and wires template changes.
func attach(menu: BuildMenu) -> void:
	_menu = menu
	name = "TemplatesPage"
	visible = false
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_row.add_theme_constant_override("separation", 6)
	_row.mouse_filter = Control.MOUSE_FILTER_PASS
	_row.minimum_size_changed.connect(_sync_width)
	add_child(_row)
	menu.tray_content().add_child(self)
	button.pressed.connect(menu.press_category.bind(BuildMenu.TEMPLATES_PAGE))
	if menu.build_mode != null:
		_paste = menu.build_mode.templates
		_paste.library.changed.connect(_rebuild)
		_paste.armed_changed.connect(_mark_cards)
	_rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_retranslate()


## Shows or hides the page and marks its bar button.
func sync(open: bool) -> void:
	visible = open
	button.set_pressed_no_signal(open)
	if open:
		update_width()


## The card of template `index`.
func card(index: int) -> Button:
	return _cards[index]


func save_card() -> Button:
	return _save_card


func card_count() -> int:
	return _cards.size()


## Updates template lock badges, price labels, tints and tooltips when unlock state changes.
func refresh_locks() -> void:
	if _paste == null:
		return
	var unlocks := _unlocks()
	var required := _require_unlocks()
	for i in _cards.size():
		var template := _paste.library.get_template(i)
		var card_btn := _cards[i] as ItemCardButton
		var lock_args := BuildUnlocks.edits_lock_args(
			unlocks, required, template.plan(Vector2i.ZERO, 0)
		)
		var locked := not lock_args.is_empty()
		var badge := _badges[i]
		var badge_label := badge.get_child(0) as Label
		var style := badge.get_theme_stylebox(&"panel") as StyleBoxFlat
		if locked:
			badge_label.text = tr("Locked")
			if style != null:
				style.bg_color = Color(0.94, 0.56, 0.52, 0.96)
			_price_labels[i].text = (
				tr("In the full game")
				if DemoMode.is_demo() and int(lock_args.get("tier", 0)) > DemoMode.MAX_PLAYABLE_TIER
				else tr("Locked")
			)
			card_btn.modulate = BuildMenu.LOCKED_TINT
		else:
			badge_label.text = tr("{w}x{h}").format({"w": template.size.x, "h": template.size.y})
			if style != null:
				style.bg_color = Color(0.55, 0.80, 0.80, 0.96)
			var price := template.price()
			_price_labels[i].text = tr("Free", "price") if price == 0 else str(price)
			card_btn.modulate = Color.WHITE
		card_btn.requirement = _lock_text_for.bind(i) if locked else Callable()
		var room := RoomTypes.get_type(template.room_type)
		var count_line := tr("{count} pieces").format({"count": template.pieces.size()})
		(
			card_btn
			. set_info(
				template.name,
				[_summary_text(template)],
				[
					[room.display_name, &"HudHint"],
					["%dx%d" % [template.size.x, template.size.y], &"HudHint"],
					[count_line, &"HudHint"],
				]
			)
		)


func _rebuild() -> void:
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_cards.clear()
	_badges.clear()
	_price_labels.clear()
	_save_card = _make_save_card()
	if _paste != null:
		_save_card.pressed.connect(_paste.arm_capture)
	_row.add_child(_save_card)
	var count := _paste.library.size() if _paste != null else 0
	for i in count:
		var template := _paste.library.get_template(i)
		var each := _make_template_card(i, template)
		each.pressed.connect(_press_template_card.bind(i))
		_row.add_child(each)
		_cards.append(each)
	refresh_locks()
	_mark_cards()
	update_width()
	if visible and _menu != null and _menu.is_tray_open():
		_menu.sync_tray_bounds()


func _press_template_card(index: int) -> void:
	if _paste == null:
		return
	if not _paste.try_arm(index):
		_mark_cards()


func _make_save_card() -> Button:
	var btn := ItemCardButton.new()
	btn.name = SAVE_CARD
	btn.toggle_mode = true
	btn.custom_minimum_size = TEMPLATE_CARD_SIZE
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	btn.set_info(
		tr("Save room"),
		[tr("Click a furnished room on the grid to save it as a reusable template.")],
		[[tr("Click", "card hint"), &"HudHint"]]
	)
	var column := BuildMenuLayout.card_column(btn)
	column.add_child(_make_thumbnail(load(TEMPLATE_ICON)))
	var name_label := BuildMenuLayout.card_label(
		column, tr("Save room"), &"HudCardName", BuildMenuLayout.CARD_LINES
	)
	name_label.name = "Name"
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var hint_label := BuildMenuLayout.card_label(
		column, tr("Pick a room"), &"HudHint", BuildMenuLayout.PRICE_LINES
	)
	hint_label.name = "SubLabel"
	BuildMenuLayout.watch_fit(btn)
	return btn


func _make_template_card(index: int, template: RoomTemplate) -> Button:
	var btn := ItemCardButton.new()
	btn.name = "CardTemplate%d" % index
	btn.toggle_mode = true
	btn.custom_minimum_size = TEMPLATE_CARD_SIZE
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_PASS
	var column := BuildMenuLayout.card_column(btn)
	var tex := _preview_texture(template.room_type)
	column.add_child(_make_thumbnail(tex))
	var name_label := BuildMenuLayout.card_label(
		column, template.name, &"HudCardName", BuildMenuLayout.CARD_LINES
	)
	name_label.name = "Name"
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var price := template.price()
	var price_text := tr("Free", "price") if price == 0 else str(price)
	var price_label := BuildMenuLayout.card_label(
		column, price_text, &"HudPrice", BuildMenuLayout.PRICE_LINES
	)
	price_label.name = "Price"
	_price_labels.append(price_label)
	BuildMenuLayout.watch_fit(btn)
	var badge := (
		BuildMenuLayout
		. add_card_badge(
			btn,
			"%dx%d" % [template.size.x, template.size.y],
			Color(0.55, 0.80, 0.80, 0.96),
			&"TemplateBadge",
		)
	)
	_badges.append(badge)
	return btn


func _make_thumbnail(tex: Texture2D) -> TextureRect:
	var picture := TextureRect.new()
	picture.name = "Thumbnail"
	picture.texture = tex
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.custom_minimum_size = Vector2(TEMPLATE_THUMB_SIZE, TEMPLATE_THUMB_SIZE)
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture


func _preview_texture(room_type: StringName) -> Texture2D:
	var thumb_id := BuildMenuCatalog.room_thumbnail(room_type)
	if thumb_id != "":
		var path := BuildMenuCatalog.THUMBNAIL_DIR % thumb_id
		if ResourceLoader.exists(path):
			return load(path)
	return load(TEMPLATE_ICON)


func _summary_text(template: RoomTemplate) -> String:
	if template.pieces.is_empty():
		return tr("Empty room footprint.")
	var counts: Dictionary = {}
	for piece in template.pieces:
		var def_id: StringName = piece["def"]
		counts[def_id] = int(counts.get(def_id, 0)) + 1
	var parts: Array[String] = []
	for def_id: StringName in counts:
		var def := BuildCatalog.get_def(def_id)
		var label := def.display_name if def != null and def.display_name != "" else String(def_id)
		parts.append("%dx %s" % [counts[def_id], label])
	return ", ".join(parts)


func _lock_text_for(index: int) -> String:
	if _paste == null or index < 0 or index >= _paste.library.size():
		return ""
	var template := _paste.library.get_template(index)
	return BuildUnlocks.edits_lock_text(
		_unlocks(), _require_unlocks(), template.plan(Vector2i.ZERO, 0)
	)


func _unlocks() -> BuildUnlocks:
	return _menu.build_mode.unlocks if _menu != null and _menu.build_mode != null else null


func _require_unlocks() -> bool:
	return _menu.build_mode.require_unlocks if _menu != null and _menu.build_mode != null else false


func needed_height() -> float:
	var h := BuildMenu.CARD_SIZE.y
	if _menu != null and _row.get_combined_minimum_size().x > _menu.tray_max_inner_width() + 0.5:
		var hbar := get_h_scroll_bar()
		if hbar != null:
			h += maxf(hbar.get_combined_minimum_size().y, hbar.size.y)
	return h


func update_width() -> void:
	if _menu == null:
		return
	var row_w := _row.get_combined_minimum_size().x
	custom_minimum_size = Vector2(minf(row_w, _menu.tray_max_inner_width()), needed_height())


func _sync_width() -> void:
	update_width()
	if visible and _menu != null and _menu.is_tray_open():
		_menu.sync_tray_bounds()


func _mark_cards() -> void:
	if _paste == null:
		return
	_save_card.set_pressed_no_signal(_paste.capturing)
	for i in _cards.size():
		_cards[i].set_pressed_no_signal(_paste.armed == i)


func _retranslate() -> void:
	if _save_card != null:
		_save_card.set_info(
			tr("Save room"),
			[tr("Click a furnished room on the grid to save it as a reusable template.")],
			[[tr("Click", "card hint"), &"HudHint"]]
		)
		var name_label := _save_card.get_child(0).get_node_or_null("Name") as Label
		if name_label != null:
			name_label.text = tr("Save room")
		var sub_label := _save_card.get_child(0).get_node_or_null("SubLabel") as Label
		if sub_label != null:
			sub_label.text = tr("Pick a room")
	refresh_locks()
	_sync_width()
