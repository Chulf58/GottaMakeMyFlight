class_name AchievementToast
extends CanvasLayer
## Non-blocking achievement unlock celebration card (Stage 3 Slice S3-P4b).
## Styled after `BigFirsts.show_certification`, with `PROCESS_MODE_ALWAYS`
## auto-dismiss and bare `tr(...)` calls for translation guard compliance.

const TOAST_SECONDS := 6.0
const TOAST_W := 380.0
const LAYER_NAME := &"AchievementToastLayer"
const CARD_NAME := &"AchievementToast"

var _id := ""
var _title_msgid := ""
var _description_msgid := ""
var _card: PanelContainer
var _badge_label: Label
var _title_label: Label
var _body_label: Label
var _close_button: Button
var _timer: Timer


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree():
		_refresh_texts()


## Shows a non-blocking toast for an unlocked achievement and attaches it under `host`
## when provided, replacing any previous toast cleanly with zero orphans.
static func show_unlocked(
	id: String, title: String, description: String, host: Node = null
) -> AchievementToast:
	if host != null:
		var old := host.get_node_or_null(NodePath(LAYER_NAME))
		if old != null and is_instance_valid(old):
			host.remove_child(old)
			old.free()
	var toast := AchievementToast.new()
	toast._build(id, title, description)
	if host != null:
		host.add_child(toast)
	return toast


func achievement_id() -> String:
	return _id


func card() -> PanelContainer:
	return _card


func title_label() -> Label:
	return _title_label


func body_label() -> Label:
	return _body_label


func close_button() -> Button:
	return _close_button


func dismiss() -> void:
	if is_instance_valid(self):
		queue_free()


func _build(id: String, title: String, description: String) -> void:
	_id = id
	_title_msgid = title
	_description_msgid = description
	name = LAYER_NAME
	layer = TopRow.SHEET_LAYER + 1

	_card = PanelContainer.new()
	_card.name = CARD_NAME
	_card.theme = BuildMenu.HUD_THEME
	_card.theme_type_variation = &"HudCardGreen"
	_card.mouse_filter = Control.MOUSE_FILTER_PASS
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.offset_left = -TOAST_W * 0.5
	_card.offset_right = TOAST_W * 0.5
	var bottom_offset := -float(HudLayout.MARGIN + HudLayout.BAR_H + HudLayout.GAP)
	_card.offset_top = bottom_offset
	_card.offset_bottom = bottom_offset
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_card)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(box)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(header)

	_badge_label = Label.new()
	_badge_label.name = "AchievementBadge"
	_badge_label.theme_type_variation = &"HudHint"
	_badge_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_badge_label)

	_close_button = Button.new()
	_close_button.name = "AchievementClose"
	_close_button.theme_type_variation = &"HudButtonCompact"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.pressed.connect(dismiss)
	header.add_child(_close_button)

	_title_label = Label.new()
	_title_label.name = "AchievementTitle"
	_title_label.theme_type_variation = &"HudTitle"
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_title_label)

	_body_label = Label.new()
	_body_label.name = "AchievementBody"
	_body_label.theme_type_variation = &"HudSmall"
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_body_label)

	_refresh_texts()

	_timer = Timer.new()
	_timer.name = "AchievementTimer"
	_timer.wait_time = TOAST_SECONDS
	_timer.one_shot = true
	_timer.autostart = true
	_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_timer.timeout.connect(dismiss)
	add_child(_timer)


func _refresh_texts() -> void:
	if _badge_label != null:
		_badge_label.text = tr("Achievement Unlocked")
	if _close_button != null:
		_close_button.text = tr("Close")
	if _title_label != null:
		_title_label.text = tr(_title_msgid)
	if _body_label != null:
		_body_label.text = tr(_description_msgid)
