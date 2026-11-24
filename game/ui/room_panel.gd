class_name RoomPanel
extends PanelContainer
## The room info panel: type, status ("Ready" or what the room still needs)
## and the facts of the room under the pointer (decision
## store-mechanics-draw-a-room-then-furnish-it-required-pieces): seats and base
## spend for a cafe, browse spots and base spend for a shop (a kiosk,
## pharmacy, duty free or fashion store; RoomTypes.RoomType.shop), the count of belt
## ends for a bag room, stalls, sinks and the upkeep per day as one room total
## for a toilet. Esc closes it. BuildMenu
## creates it top-left under the money slot; it is hidden while no room is
## followed. It reads RoomRules and follows the grid's own signals, so
## furniture placed while it is open shows on the next frame.

const POSITION := Vector2(TopRow.SHEET_MIN_LEFT, TopRow.SHEET_TOP)
const WIDTH := 280.0
const BAG_ROOM := &"bag_room"
const BELT_END := &"baggage_belt_end"
const CART := &"baggage_cart"
const TOILET := &"toilet"
const STALL := &"toilet_stall"
const SINK := &"toilet_sink"
const BREAK_ROOM := &"break_room"
const BENCH := &"bench_1a"
## A toilet's upkeep line is one room total (decision toilet-design-queue-free-
## reservable-stalls-per-stall-daily-u, point 2): what RoomRules.daily_upkeep
## charges at midnight while it is ready, and what it will once it is.

var staff: StaffSim

var _build_mode: BuildMode
var _watched_staff: StaffSim
var _room_id := 0
var _dirty := false
var _lines := VBoxContainer.new()
var _legend_card: Control


func _ready() -> void:
	name = "RoomPanel"
	position = POSITION
	custom_minimum_size = Vector2(WIDTH, 0.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = BuildMenu.HUD_THEME
	_lines.add_theme_constant_override("separation", 2)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lines)
	visible = false
	_place()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		if _build_mode != null and _room_id != 0:
			show_room(_room_id)


## Follows `mode`'s focused room and its grid's edits.
func watch(mode: BuildMode) -> void:
	_build_mode = mode
	mode.room_focus_changed.connect(show_room)
	mode.grid.edit_applied.connect(_on_edit_applied)
	mode.grid.graph_changed.connect(_on_graph_changed)
	show_room(mode.focused_room())


## The room shown, 0 for none.
func room_id() -> int:
	return _room_id


## Shows a room's status, or hides the panel for 0 or an unknown room.
func show_room(id: int) -> void:
	_room_id = id
	_dirty = false
	for child in _lines.get_children():
		child.free()
	var status := RoomRules.status(_build_mode.grid, id) if id != 0 else null
	visible = status != null
	if status == null:
		return
	_line(DisplayWords.room_type(status.type_name), &"HudTitle")
	if status.type_id == BAG_ROOM:
		_show_bag_room(status, id)
		_show_prestige(id, status.type_id)
		reset_size()
		_place()
		return
	if status.ok:
		_line(DisplayWords.ready(), &"HudGoodText")
	for note in DisplayWords.notes(status):
		_line(note, &"HudAttentionText")
	if status.type_id == TOILET:
		_line(tr("Stalls {count}").format({"count": status.pieces.get(STALL, 0)}))
		_line(tr("Sinks {count}").format({"count": status.pieces.get(SINK, 0)}))
		var upkeep := (
			tr("Upkeep ${amount} per day")
			if status.ok
			else tr("Upkeep ${amount} per day once ready")
		)
		_line(upkeep.format({"amount": status.upkeep}))
	elif status.type_id == BREAK_ROOM:
		_line(tr("Benches {count}").format({"count": status.pieces.get(BENCH, 0)}))
		_line(tr("Staff rest here during lulls"))
	elif RoomTypes.get_type(status.type_id).activity:
		_line(tr("Spots {count}").format({"count": status.seats}))
		if status.base_spend > 0:
			_line(tr("Fee ${amount} per visit").format({"amount": status.base_spend}))
		else:
			_line(tr("Free to use"))
	elif RoomTypes.get_type(status.type_id).shop:
		_line(tr("Browse spots {count}").format({"count": status.seats}))
		_line(tr("Base spend ${amount} per visit").format({"amount": status.base_spend}))
	else:
		if not RoomTypes.get_type(status.type_id).walk_on:
			_line(tr("Seats {count}").format({"count": status.seats}))
		_line(tr("Base spend ${amount} per visit").format({"amount": status.base_spend}))
	_show_prestige(id, status.type_id)
	reset_size()
	_place()


func _process(_delta: float) -> void:
	if _dirty:
		show_room(_room_id)
	elif visible:
		_place()


func _place() -> void:
	var tree := get_tree() if is_inside_tree() else null
	var vp := get_viewport()
	var view := vp.get_visible_rect().size if vp != null else Vector2(1280.0, 720.0)
	var min_x := LeftColumn.clear_right(tree, TopRow.SHEET_MIN_LEFT)
	var card_w := maxf(size.x, WIDTH)
	var max_x := maxf(float(HudLayout.MARGIN), view.x - card_w - float(HudLayout.MARGIN))
	var x := clampf(min_x, float(HudLayout.MARGIN), max_x)
	var y := TopRow.SHEET_TOP
	if (_legend_card == null or not is_instance_valid(_legend_card)) and vp != null:
		_legend_card = vp.find_child("MoodLegendCard", true, false) as Control
	if _legend_card != null and _legend_card.is_visible_in_tree():
		var lr := _legend_card.get_global_rect()
		if lr.end.x > x and lr.position.x < x + card_w:
			y = maxf(y, lr.end.y + float(HudLayout.GAP))
	var bottom_limit := view.y - float(BuildMenu.MARGIN + BuildMenu.BAR_H + BuildMenu.GAP)
	if size.y > 0.0:
		y = minf(y, maxf(TopRow.SHEET_TOP, bottom_limit - size.y))
	var target := Vector2(x, y)
	if not position.is_equal_approx(target):
		position = target


## Esc closes the panel and is not passed on, so it does not also drop a tool.
## The panel comes back when the pointer moves to another room.
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("build_tool_none"):
		show_room(0)
		get_viewport().set_input_as_handled()


func _on_edit_applied(_edit: BuildEdit, _result: BuildResult) -> void:
	_dirty = _room_id != 0


func _on_graph_changed(_cells: Array[Vector2i]) -> void:
	_dirty = _room_id != 0


func _on_staff_changed() -> void:
	_dirty = _room_id != 0


func _show_bag_room(status: RoomRules.RoomStatus, id: int) -> void:
	var belt_ends: int = status.pieces.get(BELT_END, 0)
	var connected := BagRoutes.build(_build_mode.grid).connected_desk_count(id)
	if belt_ends == 0:
		_line(tr("Needs a belt dragged inside"), &"HudAttentionText")
		var notes := DisplayWords.notes(status)
		for i in status.notes.size():
			if status.notes[i] != "Needs a belt end":
				_line(notes[i], &"HudAttentionText")
	elif not status.ok:
		for note in DisplayWords.notes(status):
			_line(note, &"HudAttentionText")
	elif connected == 0:
		_line(tr("Waiting for belt from check-in desk"), &"HudAttentionText")
	else:
		_line(DisplayWords.ready(), &"HudGoodText")
		if status.pieces.get(CART, 0) > 0:
			var s := _resolve_staff()
			if s != null and s.count(StaffMember.Role.RAMP) == 0:
				_line(tr("Needs a Ramp Agent (Staff)"), &"HudAttentionText")
	_line(tr("Belt ends {count}").format({"count": belt_ends}))
	_line(tr("Desks connected: {count}").format({"count": connected}))


func _show_prestige(id: int, type_id: StringName) -> void:
	var prestige := RoomPrestige.evaluate_room(_build_mode.grid, id)
	var level: int = prestige["level"]
	var score: int = prestige["score"]
	var spend_pct: int = prestige["spend_bonus_percent"]
	var room_type := RoomTypes.get_type(type_id)
	var is_commercial := (
		room_type != null and (room_type.food or (room_type.shop and not room_type.activity))
	)
	if is_commercial:
		_line(
			tr("Prestige: Lv. {level} / 5 ({score} pts · +{bonus}% spend)").format(
				{"level": level, "score": score, "bonus": spend_pct}
			)
		)
	elif type_id == BREAK_ROOM:
		var break_pct: int = prestige["break_bonus_percent"]
		_line(
			tr("Prestige: Lv. {level} / 5 ({score} pts · +{bonus}% recovery)").format(
				{"level": level, "score": score, "bonus": break_pct}
			)
		)
	else:
		_line(
			tr("Prestige: Lv. {level} / 5 ({score} pts)").format({"level": level, "score": score})
		)
	_line(
		(
			tr("Size {size} · Setup {setup} · Decor {decor} · Awards {trophy}")
			. format(
				{
					"size": prestige["size_points"],
					"setup": prestige["furnishing_points"],
					"decor": prestige["decor_points"],
					"trophy": prestige["trophy_points"],
				}
			)
		)
	)
	if level < RoomPrestige.MAX_LEVEL:
		_line(tr("Add decor or trophies to raise prestige"))


func _resolve_staff() -> StaffSim:
	var resolved := staff
	if resolved == null and is_inside_tree():
		var root := get_tree().root
		if root != null:
			resolved = root.find_child("Staff", true, false) as StaffSim
	if resolved != _watched_staff:
		if (
			_watched_staff != null
			and is_instance_valid(_watched_staff)
			and _watched_staff.staff_changed.is_connected(_on_staff_changed)
		):
			_watched_staff.staff_changed.disconnect(_on_staff_changed)
		_watched_staff = resolved
		if (
			_watched_staff != null
			and not _watched_staff.staff_changed.is_connected(_on_staff_changed)
		):
			_watched_staff.staff_changed.connect(_on_staff_changed)
	return resolved


func _line(text: String, variation := &"") -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Autowrap needs a width, or the label measures one word per line. The
	# width is what the theme card's content margins leave of WIDTH.
	var padding := get_theme_stylebox("panel").get_minimum_size().x
	label.custom_minimum_size = Vector2(WIDTH - padding, 0.0)
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_child(label)
