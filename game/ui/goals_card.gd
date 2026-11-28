class_name AirportGoalsCard
extends PanelContainer
## LeftColumn card displaying the 3 active Airport Goals with live progress
## counters and cash rewards. Yields while the airport is closed or while
## ChecklistCard (StaffPanel) is visible, and auto-collapses to a 1-line header
## pill whenever DeparturesBoard is open on compact viewports (<= 620 px high).

const COMPACT_VIEWPORT_H := 620.0
const FADED_ALPHA := HudLayout.GHOST_FADED_ALPHA
const FADE_SPEED := HudLayout.GHOST_FADE_SPEED

@export var goals: AirportGoals:
	set(value):
		if goals == value:
			return
		if is_instance_valid(goals) and goals.changed.is_connected(_on_goals_changed):
			goals.changed.disconnect(_on_goals_changed)
		goals = value
		if is_instance_valid(goals) and not goals.changed.is_connected(_on_goals_changed):
			goals.changed.connect(_on_goals_changed)
		_goals_dirty = true
		if is_node_ready():
			sync()
@export var flights: FlightSim
@export var departures_board: DeparturesBoard
@export var staff_panel: StaffPanel
@export var build_mode: BuildMode

var _box := VBoxContainer.new()
var _header := HBoxContainer.new()
var _title := Label.new()
var _toggle := Button.new()
var _rows := VBoxContainer.new()

var _manual_collapsed := false
var _auto_collapsed := false
var _auto_override := false
var _last_departures_open := false
var _goals_dirty := true
var _rows_dirty := true
var _header_dirty := true
var _cached_entries: Array[Dictionary] = []
var _rendered_entries: Array[Dictionary] = []
var _last_collapsed := false
var _last_header_count := -1


func _init() -> void:
	name = "AirportGoalsCard"
	theme = BuildMenu.HUD_THEME
	custom_minimum_size = Vector2(HudLayout.LIST_W, 0.0)
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false
	add_to_group(LeftColumn.CARD_GROUP)
	LeftColumn.dock_card(self)

	_box.name = "GoalsBox"
	_box.add_theme_constant_override("separation", 6)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)

	_header.name = "GoalsHeader"
	_header.add_theme_constant_override("separation", 6)
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_header)

	_title.name = "GoalsTitle"
	_title.theme_type_variation = &"HudCardName"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header.add_child(_title)

	_toggle.name = "GoalsToggle"
	_toggle.theme_type_variation = &"HudButtonCompact"
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.custom_minimum_size = Vector2(28.0, 24.0)
	_toggle.pressed.connect(toggle_collapsed)
	_header.add_child(_toggle)

	_rows.name = "GoalsRows"
	_rows.add_theme_constant_override("separation", 4)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_rows)


func _ready() -> void:
	LeftColumn.dock_card(self)
	if goals != null and not goals.changed.is_connected(_on_goals_changed):
		goals.changed.connect(_on_goals_changed)
	_goals_dirty = true
	_header_dirty = true
	_rows_dirty = true
	sync()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_goals_dirty = true
		_header_dirty = true
		_rows_dirty = true
		sync()


func _process(delta: float) -> void:
	sync()
	LeftColumn.follow(self)
	if build_mode != null and visible:
		var vp := get_viewport()
		var cam := vp.get_camera_3d() if vp != null else null
		var ghost := GhostBounds.build_rect(build_mode, cam)
		HudLayout.fade_under_ghost(self, ghost, delta, FADED_ALPHA, FADE_SPEED)
	elif not is_equal_approx(modulate.a, 1.0):
		modulate.a = 1.0


func toggle_collapsed() -> void:
	if _auto_collapsed:
		_auto_override = true
		_manual_collapsed = false
	else:
		_manual_collapsed = not _manual_collapsed
	_header_dirty = true
	sync()


func set_manual_collapsed(collapsed: bool) -> void:
	_manual_collapsed = collapsed
	if not collapsed:
		_auto_override = true
	_header_dirty = true
	sync()


func is_collapsed() -> bool:
	return _manual_collapsed or _auto_collapsed


func is_auto_collapsed() -> bool:
	return _auto_collapsed


func title_label() -> Label:
	return _title


func toggle_button() -> Button:
	return _toggle


func row_count() -> int:
	return _rows.get_child_count()


func rows_container() -> VBoxContainer:
	return _rows


func _on_goals_changed() -> void:
	_goals_dirty = true
	sync()


## Recomputes visibility, compact-viewport auto-collapse, and row contents.
func sync() -> void:
	if _goals_dirty:
		_cached_entries = goals.active_goals() if goals != null else ([] as Array[Dictionary])
		_goals_dirty = false
		if _cached_entries != _rendered_entries:
			_rows_dirty = true

	var opened := flights != null and flights.opened_tick >= 0
	var checklist_up := staff_panel != null and staff_panel.is_checklist_visible()
	var should_show := opened and not checklist_up and not _cached_entries.is_empty()
	if visible != should_show:
		visible = should_show
	if not should_show:
		return

	var vp := get_viewport()
	var viewport_h := vp.get_visible_rect().size.y if vp != null else 864.0
	var departures_open := departures_board != null and departures_board.is_panel_visible()
	if departures_open != _last_departures_open:
		_last_departures_open = departures_open
		_auto_override = false
		_header_dirty = true
	var compact := departures_open and viewport_h <= COMPACT_VIEWPORT_H
	var next_auto := compact and not _auto_override
	if next_auto != _auto_collapsed:
		_auto_collapsed = next_auto
		_header_dirty = true

	var collapsed := is_collapsed()
	var count := _cached_entries.size()
	if (
		not _rows_dirty
		and not _header_dirty
		and collapsed == _last_collapsed
		and count == _last_header_count
	):
		return

	if _header_dirty or collapsed != _last_collapsed or (collapsed and count != _last_header_count):
		_rows.visible = not collapsed
		if collapsed:
			_title.text = tr("Goals ({count})").format({"count": count})
			_toggle.text = tr("+")
			_toggle.tooltip_text = tr("Expand goals")
		else:
			_title.text = tr("Airport Goals")
			_toggle.text = tr("−")
			_toggle.tooltip_text = tr("Collapse goals")
		_last_collapsed = collapsed
		_last_header_count = count
		_header_dirty = false

	if _rows_dirty:
		_rendered_entries = _cached_entries.duplicate(true)
		_rebuild_rows(_cached_entries)
		_rows_dirty = false

	reset_size()


func _rebuild_rows(entries: Array[Dictionary]) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for entry in entries:
		_rows.add_child(_make_row(entry))


func _make_row(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "GoalRow_%s" % str(entry["id"])
	card.theme_type_variation = &"HudSubCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	var title := Label.new()
	title.name = "GoalTitle"
	title.text = tr(str(entry["title"]))
	title.theme_type_variation = &"HudSmall"
	title.add_theme_font_size_override("font_size", HudLayout.CAPTION)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title)

	var meta := VBoxContainer.new()
	meta.add_theme_constant_override("separation", 0)
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(meta)

	var counter := Label.new()
	counter.name = "GoalCounter"
	counter.text = "%d/%d" % [int(entry["progress"]), int(entry["target"])]
	counter.theme_type_variation = &"HudSmall"
	counter.add_theme_font_size_override("font_size", HudLayout.CAPTION)
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(counter)

	var reward := Label.new()
	reward.name = "GoalReward"
	reward.text = "+$%d" % int(entry["reward"])
	reward.theme_type_variation = &"HudHint"
	reward.add_theme_font_size_override("font_size", HudLayout.FIT_STEP)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	reward.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(reward)
	return card


## Builds a non-modal AlertStack notice card for a completed goal.
func completion_toast(goal: Dictionary) -> Control:
	var goal_id := str(goal.get("id", ""))
	var title := tr(str(goal.get("title", "")))
	var reward := int(goal.get("reward", 0))
	var card := PanelContainer.new()
	card.name = "GoalCompletedToast_%s" % goal_id
	card.theme = BuildMenu.HUD_THEME
	card.theme_type_variation = &"HudCardGreen"
	card.custom_minimum_size = Vector2(HudLayout.RAIL_W, 0.0)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var head_lbl := Label.new()
	head_lbl.text = tr("Goal completed")
	head_lbl.theme_type_variation = &"HudCardName"
	head_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head_lbl)
	var body_lbl := Label.new()
	body_lbl.text = (
		tr("{title} (+${reward})").format({"title": title, "reward": reward})
		if reward > 0
		else title
	)
	body_lbl.theme_type_variation = &"HudSmall"
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(body_lbl)
	return card


func post_completion_toast(alerts: AlertStack, goal: Dictionary, show_seconds: float) -> void:
	if alerts == null or not alerts.is_inside_tree():
		return
	var title := tr(str(goal.get("title", "")))
	var reward := int(goal.get("reward", 0))
	var heading := tr("Goal completed")
	var detail := (
		tr("{title} (+${reward})").format({"title": title, "reward": reward})
		if reward > 0
		else title
	)
	var key := StringName("goal_%s" % str(goal.get("id", "")))
	alerts.post_notice(key, completion_toast(goal), show_seconds, heading, detail)


## Wires `card` to `goals`, `flights`, `departures_board`, `build_mode`, and `alerts`.
static func mount(
	card: AirportGoalsCard,
	hud: Node,
	with_goals: AirportGoals,
	with_flights: FlightSim,
	with_board: DeparturesBoard,
	with_build_mode: BuildMode,
	alerts: AlertStack,
	toast_seconds: float
) -> void:
	card.goals = with_goals
	card.flights = with_flights
	card.departures_board = with_board
	card.staff_panel = hud.get_node_or_null("../StaffPanel") as StaffPanel
	card.build_mode = with_build_mode
	hud.add_child(card)
	if with_goals != null:
		with_goals.goal_completed.connect(
			func(goal: Dictionary) -> void:
				if hud.is_inside_tree():
					card.post_completion_toast(alerts, goal, toast_seconds)
		)
