class_name AchievementToast
extends CanvasLayer
## Non-blocking achievement unlock celebration card (Stage 3 Slice S3-P4b).
## Styled after `BigFirsts.show_certification`, with `PROCESS_MODE_ALWAYS`
## auto-dismiss and bare `tr(...)` calls for translation guard compliance.

const TOAST_SECONDS := 6.0
const TOAST_W := float(HudLayout.RAIL_W)
const LAYER_NAME := &"AchievementToastLayer"
const CARD_NAME := &"AchievementToast"
const RAIL_KEY := &"achievement_unlocked"

var _id := ""
var _title_msgid := ""
var _description_msgid := ""
var _card: PanelContainer
var _badge_label: Label
var _title_label: Label
var _body_label: Label
var _close_button: Button
var _timer: Timer
var _rail: AlertStack
var _dismissing := false


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_inside_tree():
		_refresh_texts()


func _exit_tree() -> void:
	_detach_from_rail()


## Shows a non-blocking toast for an unlocked achievement and routes it into
## AlertStack when present under `host`, or top-right standalone otherwise.
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
	var rail := _find_rail(host)
	if host != null:
		host.add_child(toast)
	if rail != null:
		toast._attach_to_rail(rail)
	else:
		toast._anchor_standalone_top_right()
		toast.add_child(toast._card)
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
	if _dismissing or not is_instance_valid(self):
		return
	_dismissing = true
	_detach_from_rail()
	if not is_queued_for_deletion():
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
	_card.custom_minimum_size = Vector2(TOAST_W, 0.0)
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

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


static func _find_rail(host: Node) -> AlertStack:
	if host == null or not host.is_inside_tree():
		return null
	var tree := host.get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group(AlertStack.GROUP) as AlertStack


func _attach_to_rail(rail: AlertStack) -> void:
	_rail = rail
	if not _card.tree_exiting.is_connected(_on_card_exiting):
		_card.tree_exiting.connect(_on_card_exiting)
	rail.post_notice(
		RAIL_KEY,
		_card,
		TOAST_SECONDS,
		tr("Achievement Unlocked"),
		"%s: %s" % [tr(_title_msgid), tr(_description_msgid)]
	)


func _detach_from_rail() -> void:
	if is_instance_valid(_card) and _card.tree_exiting.is_connected(_on_card_exiting):
		_card.tree_exiting.disconnect(_on_card_exiting)
	if is_instance_valid(_rail) and _rail.notice_card(RAIL_KEY) == _card:
		_rail.drop_notice(RAIL_KEY)
	_rail = null


func _on_card_exiting() -> void:
	_rail = null
	if not _dismissing and is_instance_valid(self) and not is_queued_for_deletion():
		_dismissing = true
		queue_free()


func _anchor_standalone_top_right() -> void:
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.anchor_top = 0.0
	_card.anchor_bottom = 0.0
	_card.offset_right = -float(HudLayout.MARGIN)
	_card.offset_left = -float(HudLayout.MARGIN) - TOAST_W
	_card.offset_top = float(HudLayout.MARGIN)
	_card.offset_bottom = float(HudLayout.MARGIN)
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.grow_vertical = Control.GROW_DIRECTION_END


func _refresh_texts() -> void:
	if _badge_label != null:
		_badge_label.text = tr("Achievement Unlocked")
	if _close_button != null:
		_close_button.text = tr("Close")
	if _title_label != null:
		_title_label.text = tr(_title_msgid)
	if _body_label != null:
		_body_label.text = tr(_description_msgid)
