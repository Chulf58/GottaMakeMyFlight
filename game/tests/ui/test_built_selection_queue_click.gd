class_name TestBuiltSelectionQueueClick
extends GdUnitTestSuite
## A click on a built desk selects the desk even with a queue standing beside it
## (board cd0be5bc): inside the desk's footprint a passenger is picked only when
## the click is on the drawn body (PassengerViews.pick_body), not within the 40 px
## circle. On open floor the 40 px circle still picks, so passengers stay easy to
## click. A click right on a passenger standing at the desk still picks them.

const SEED := 6_113_312
const FLIGHT_ID := "GMF101"
## Metres beside the click: far enough that the passenger's body is not under the
## cursor, near enough that the 40 px circle still reaches it.
const BESIDE_M := 0.6

var _settings_path := SaveTestKit.run_path("queue_click_alerts")

var _main: Node
var _hud: PassengerHud
var _mode: BuildMode
var _sim: PassengerSim
var _views: PassengerViews
var _eye: Camera3D
var _inspect: PassengerInspect
var _desk := 0
var _plain_cell := Vector2i(-1, -1)


func before() -> void:
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	(_main.get_node("PassengerHud") as PassengerHud).alert_settings_path = _settings_path
	add_child(_main)
	_hud = _main.get_node("PassengerHud")
	_mode = _main.get_node("BuildMode")
	_sim = _main.get_node("PassengerSim")
	_views = _main.get_node("PassengerViews")
	(_main.get_node("TycoonCamera") as TycoonCamera).set_process(false)
	_eye = _main.get_node("TycoonCamera/Camera3D")
	_inspect = _hud.find_child("PassengerInspect", true, false) as PassengerInspect
	_hud.press_starter_terminal()
	StaffTestKit.staff_all(_main.get_node("Staff"))
	_desk = _sim.layout.desks[0]
	_plain_cell = _find_plain_cell()


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_settings_path)


func before_test() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	_views.selected_id = 0
	_selection().clear()
	_hud.refresh()


## A floor cell with no object, room or wall edge on it or within two cells.
func _find_plain_cell() -> Vector2i:
	var grid := _mode.grid
	var offset := ReferenceTerminal.offset_on(grid)
	var low := Vector2i(ReferenceTerminal.FLOOR_MIN.x + 1, ReferenceTerminal.DIVIDER_Y + 1) + offset
	var high := ReferenceTerminal.FLOOR_MAX + offset - Vector2i.ONE
	for y in range(low.y, high.y):
		for x in range(low.x, high.x):
			if _is_bare(grid, Rect2i(x - 2, y - 2, 5, 5)):
				return Vector2i(x, y)
	fail("no bare floor cell in the starter terminal")
	return Vector2i(-1, -1)


static func _is_bare(grid: BuildGrid, area: Rect2i) -> bool:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if (
				grid.floor_at(cell) == BuildGrid.FLOOR_NONE
				or grid.object_at(cell) != 0
				or grid.room_at(cell) != 0
			):
				return false
	return true


func _look_at(target: Vector3) -> void:
	_eye.look_at_from_position(target + Vector3(0.0, 30.0, 4.0), target)


## A real click pushed through the viewport (anti-pattern a-main-tscn-click-test-
## that-calls-unhandled-input-directly-m), the dispatch frame waited for.
func _click_screen(screen: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	_mode.pointer_override = screen
	get_viewport().push_input(motion, true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen
	click.global_position = screen
	get_viewport().push_input(click, true)
	await await_idle_frame()
	_mode.pointer_override = Vector2(-1.0, -1.0)
	_hud.refresh()


func _selection() -> BuiltSelection:
	return _inspect.built_card.selection


func _desk_centre() -> Vector3:
	return _mode.grid.cell_to_world(_mode.grid.get_object(_desk)["anchor"])


## A passenger drawn standing with their feet at `at`.
func _stand(at: Vector3) -> int:
	var passenger := _sim.spawn_now(FLIGHT_ID)
	_views.sync()
	_views.node_for(passenger).position = at
	return passenger


func test_a_click_on_the_desk_beside_a_queued_passenger_selects_the_desk() -> void:
	var centre := _desk_centre()
	_look_at(centre)
	var click := _eye.unproject_position(centre + Vector3(0.0, 0.4, 0.0))
	var passenger := _stand(centre + Vector3(BESIDE_M, 0.0, 0.0))
	var circle := _views.pick(_eye, click)
	var body := _views.pick_body(_eye, click)
	var gap := (
		_eye.unproject_position(_views.node_for(passenger).position + Vector3.UP).distance_to(click)
	)
	print(
		(
			"control: circle pick %d body pick %d gap %.1f px (passenger %d)"
			% [circle, body, gap, passenger]
		)
	)
	assert_int(circle).is_equal(passenger)
	assert_float(gap).is_less(PassengerViews.PICK_RADIUS_PX)
	assert_int(body).is_equal(0)
	await _click_screen(click)
	print(
		(
			"desk click: passenger %d, item kind %d id %d"
			% [_views.selected_id, _selection().kind, _selection().id]
		)
	)
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.OBJECT)
	assert_int(_selection().id).is_equal(_desk)
	assert_int(_views.selected_id).is_equal(0)


func test_a_click_right_on_a_passenger_at_the_desk_still_selects_the_passenger() -> void:
	var centre := _desk_centre()
	_look_at(centre)
	var passenger := _stand(centre)
	var click := _eye.unproject_position(centre + Vector3(0.0, 1.0, 0.0))
	print("control: body pick %d (passenger %d)" % [_views.pick_body(_eye, click), passenger])
	assert_int(_views.pick_body(_eye, click)).is_equal(passenger)
	await _click_screen(click)
	assert_int(_views.selected_id).is_equal(passenger)
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.NONE)


func test_on_open_floor_a_passenger_beside_the_click_is_still_picked() -> void:
	var centre := _mode.grid.cell_to_world(_plain_cell)
	_look_at(centre)
	var click := _eye.unproject_position(centre)
	var passenger := _stand(centre + Vector3(BESIDE_M, 0.0, 0.0))
	var body := _views.pick_body(_eye, click)
	print(
		(
			"open floor control: body pick %d, grid object %d"
			% [body, _mode.grid.object_at(_plain_cell)]
		)
	)
	assert_int(body).is_equal(0)
	assert_int(_mode.grid.object_at(_plain_cell)).is_equal(0)
	await _click_screen(click)
	assert_int(_views.selected_id).is_equal(passenger)
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.NONE)
