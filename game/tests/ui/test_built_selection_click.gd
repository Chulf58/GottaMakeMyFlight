class_name TestBuiltSelectionClick
extends GdUnitTestSuite
## On the real main scene, with no build tool picked, a click selects the built
## item under it (decision select-placed-items-design-click-order-gold-
## footprint-highlight-...): a desk by its box, a room by its open floor. The
## click order puts a passenger before the item beside it, a wall or plain
## floor clears, and the passenger inspect window shows the item's name and
## staff. With a build tool picked a click selects nothing.

const SEED := 6_113_311
## A flight id the sim takes for a spawned passenger (no contract is needed).
const FLIGHT_ID := "GMF101"
const ROOM_SIZE := Vector2i(3, 3)

var _settings_path := SaveTestKit.run_path("built_selection_alerts")

var _main: Node
var _hud: PassengerHud
var _mode: BuildMode
var _sim: PassengerSim
var _views: PassengerViews
var _eye: Camera3D
var _inspect: PassengerInspect
var _outline: BuiltOutline
var _land: LandsideSim
var _desk := 0
var _room_area := Rect2i()
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
	_outline = _hud.find_child("BuiltOutline", true, false) as BuiltOutline
	_land = _main.get_node("LandsideSim")
	_hud.press_starter_terminal()
	StaffTestKit.staff_all(_main.get_node("Staff"))
	_desk = _sim.layout.desks[0]
	_find_free_floor()
	var edit := _mode.grid.apply(BuildEdit.place_room(_room_area, &"cafe"))
	assert_bool(edit.ok).is_true()


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_settings_path)


func before_test() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	_views.selected_id = 0
	_selection().clear()
	_look_at(_mode.grid.cell_to_world(_mode.grid.get_object(_desk)["anchor"]))
	_hud.refresh()


## The first free ROOM_SIZE block of landside-hall floor for the room, and a
## free block well clear of it for the plain-floor click.
func _find_free_floor() -> void:
	var grid := _mode.grid
	var offset := ReferenceTerminal.offset_on(grid)
	var low := Vector2i(ReferenceTerminal.FLOOR_MIN.x + 1, ReferenceTerminal.DIVIDER_Y + 1) + offset
	var high := ReferenceTerminal.FLOOR_MAX + offset - Vector2i.ONE
	for y in range(low.y, high.y - ROOM_SIZE.y + 2):
		for x in range(low.x, high.x - ROOM_SIZE.x + 2):
			var area := Rect2i(Vector2i(x, y), ROOM_SIZE)
			if not _is_free(grid, area.grow(1)):
				continue
			if not _room_area.has_area():
				_room_area = area
			elif not area.intersects(_room_area.grow(3)):
				_plain_cell = area.position + Vector2i.ONE
	assert_bool(_room_area.has_area() and _plain_cell.x >= 0).is_true()


static func _is_free(grid: BuildGrid, area: Rect2i) -> bool:
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


## Looks almost straight down at `target`, a little from the south.
func _look_at(target: Vector3) -> void:
	_eye.look_at_from_position(target + Vector3(0.0, 30.0, 4.0), target)


## A real click: a mouse move then a left press pushed through the viewport, so
## the click goes down the same input path as the player's (the GUI first, then
## every unhandled-input node), and the frame it is dispatched in is waited for.
## BuildMode and the template paste read the pointer from pointer_override
## (their probe hook) rather than the window's mouse, so it is set to match.
func _click_world(at: Vector3) -> void:
	var screen := _eye.unproject_position(at)
	print("click world %s -> screen %s" % [at, screen])
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


func _cell_top(cell: Vector2i, height: float) -> Vector3:
	return _mode.grid.cell_to_world(cell) + Vector3(0.0, height, 0.0)


func _desk_anchor() -> Vector2i:
	return _mode.grid.get_object(_desk)["anchor"]


func test_clicking_a_desk_selects_it_and_the_window_shows_its_name_and_staff() -> void:
	var def := BuildCatalog.get_def(_mode.grid.get_object(_desk)["def"])
	await _click_world(_cell_top(_desk_anchor(), 0.4))
	var selected := _selection()
	print("hit kind %d id %d (desk %d)" % [selected.kind, selected.id, _desk])
	assert_int(selected.kind).is_equal(BuiltSelection.Kind.OBJECT)
	assert_int(selected.id).is_equal(_desk)
	assert_bool(_inspect.visible).is_true()
	var card := _inspect.built_card
	print(
		(
			"window: %s | %s | %s"
			% [card.name_text(), card.field_text("status"), card.field_text("staff")]
		)
	)
	assert_str(card.name_text()).is_equal(def.display_name)
	assert_str(card.field_text("staff")).is_equal("Staff: 1 on duty")
	assert_str(card.field_text("status")).is_equal("Status: Open")
	assert_int(_views.selected_id).is_equal(0)
	_outline.refresh()
	var frame := _outline.frame_aabb()
	var at := _mode.grid.cell_to_world(_desk_anchor())
	print("outline %s around desk cell %s" % [frame, at])
	assert_bool(_outline.is_showing()).is_true()
	assert_bool(frame.has_point(Vector3(at.x, frame.position.y, at.z))).is_true()
	assert_float(frame.position.y).is_equal_approx(_mode.grid.origin.y + BuiltOutline.LIFT_M, 0.001)


func test_a_passenger_standing_at_the_desk_is_picked_before_the_desk() -> void:
	var passenger := _sim.spawn_now(FLIGHT_ID)
	_views.sync()
	var at := _cell_top(_desk_anchor(), 0.0)
	_views.node_for(passenger).position = at
	await _click_world(at + Vector3(0.0, 1.0, 0.0))
	print("hit passenger %d, item kind %d" % [_views.selected_id, _selection().kind])
	assert_int(_views.selected_id).is_equal(passenger)
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.NONE)
	assert_str(_inspect.name_text()).is_equal("Passenger %d" % passenger)
	assert_bool(_inspect.built_card.visible).is_false()
	# And the reverse: clicking the desk clears the passenger.
	_views.node_for(passenger).position += Vector3(30.0, 0.0, 0.0)
	await _click_world(_cell_top(_desk_anchor(), 0.4))
	assert_int(_selection().id).is_equal(_desk)
	assert_int(_views.selected_id).is_equal(0)
	assert_bool(_inspect.built_card.visible).is_true()


func test_clicking_open_room_floor_selects_the_room() -> void:
	var middle := _room_area.position + _room_area.size / 2
	_look_at(_cell_top(middle, 0.0))
	await _click_world(_cell_top(middle, 0.0))
	var selected := _selection()
	print(
		(
			"hit kind %d id %d, room at cell %d"
			% [selected.kind, selected.id, _mode.grid.room_at(middle)]
		)
	)
	assert_int(selected.kind).is_equal(BuiltSelection.Kind.ROOM)
	assert_int(selected.id).is_equal(_mode.grid.room_at(middle))
	assert_str(_inspect.built_card.name_text()).is_equal("Cafe")
	assert_bool(_inspect.visible).is_true()
	_outline.refresh()
	var frame := _outline.frame_aabb()
	var floor_rect := Rect2(
		_mode.grid.origin.x + _room_area.position.x,
		_mode.grid.origin.z + _room_area.position.y,
		ROOM_SIZE.x,
		ROOM_SIZE.y
	)
	print("outline %s around room floor %s" % [frame, floor_rect])
	assert_bool(_outline.is_showing()).is_true()
	assert_float(frame.size.x).is_equal_approx(floor_rect.size.x, 0.001)
	assert_float(frame.size.z).is_equal_approx(floor_rect.size.y, 0.001)
	assert_float(frame.position.x).is_equal_approx(floor_rect.position.x, 0.001)


func test_clicking_plain_floor_clears_the_selection() -> void:
	await _click_world(_cell_top(_desk_anchor(), 0.4))
	assert_bool(_selection().is_selected()).is_true()
	_look_at(_cell_top(_plain_cell, 0.0))
	await _click_world(_cell_top(_plain_cell, 0.0))
	print("plain floor %s: kind %d" % [_plain_cell, _selection().kind])
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.NONE)
	assert_bool(_inspect.visible).is_false()


func test_clicking_a_wall_clears_the_selection_even_with_an_item_behind_it() -> void:
	await _click_world(_cell_top(_desk_anchor(), 0.4))
	assert_bool(_selection().is_selected()).is_true()
	# The divider wall runs along the north edge of row DIVIDER_Y; the cutaway
	# draws it as a 0.3 m stub from this camera, so the click lands on the stub.
	var offset := ReferenceTerminal.offset_on(_mode.grid)
	var cell := Vector2i(ReferenceTerminal.FLOOR_MIN.x + 1, ReferenceTerminal.DIVIDER_Y) + offset
	assert_bool(_mode.grid.has_wall(cell, BuildGrid.Side.NORTH)).is_true()
	# A statue stands on the floor cell just behind it, where the click's ground
	# point falls: without the wall rule that cell would select the statue.
	var behind := cell + Vector2i(0, -1)
	var placed := _mode.grid.apply(BuildEdit.place_object(&"statue_indoor", behind, 0))
	assert_bool(placed.ok).is_true()
	var edge := _mode.grid.cell_to_world(cell) + Vector3(0.0, 0.2, -0.5)
	_look_at(edge)
	var screen := _eye.unproject_position(edge)
	var ground: Vector3 = BuildMode.ground_point(
		_eye.project_ray_origin(screen), _eye.project_ray_normal(screen), _mode.grid.origin.y
	)
	var view := _mode.get_node("BuildView") as BuildView
	var seen := SightPick.seen_wall(_mode.grid, view, _eye, ground)
	var ground_cell := _mode.grid.world_to_cell(ground)
	print(
		(
			"control: ground cell %s holds object %d (statue %d), wall edge seen %s"
			% [ground_cell, _mode.grid.object_at(ground_cell), placed.object_id, seen]
		)
	)
	assert_int(_mode.grid.object_at(ground_cell)).is_equal(placed.object_id)
	assert_int(seen.z).is_equal(BuildGrid.Side.NORTH)
	assert_int(SightPick.seen_object(_mode.grid, view, _eye, ground)).is_equal(0)
	await _click_world(edge)
	print("wall click: kind %d" % _selection().kind)
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.NONE)
	assert_bool(_inspect.visible).is_false()
	_mode.grid.apply(BuildEdit.remove_object(placed.object_id))


func test_with_a_build_tool_picked_a_click_selects_nothing() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	await _click_world(_cell_top(_desk_anchor(), 0.4))
	print("tool picked: kind %d" % _selection().kind)
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.NONE)
	assert_bool(_inspect.visible).is_false()
	# A selection made earlier is cleared when a tool is picked.
	_mode.set_tool(BuildMode.Tool.NONE)
	await _click_world(_cell_top(_desk_anchor(), 0.4))
	assert_bool(_selection().is_selected()).is_true()
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_hud.refresh()
	assert_bool(_selection().is_selected()).is_false()


func test_clicking_a_built_car_park_selects_it_and_a_click_beside_it_clears() -> void:
	var lot := _land.definition.lots[0]
	var lot_kind := LandsidePlacement.Kind.SURFACE_LOT
	if lot.kind != LandsideLotSpot.Kind.SURFACE:
		lot_kind = LandsidePlacement.Kind.MULTI_STOREY
	assert_bool(_land.build_lot(0)).is_true()
	_look_at(lot.centre)
	await _click_world(lot.centre)
	var selected := _selection()
	print(
		(
			"car park hit kind %d lot kind %d spot %d"
			% [selected.kind, selected.lot_kind, selected.spot]
		)
	)
	assert_int(selected.kind).is_equal(BuiltSelection.Kind.LANDSIDE)
	assert_int(selected.lot_kind).is_equal(lot_kind)
	assert_int(selected.spot).is_equal(0)
	assert_str(_inspect.built_card.name_text()).is_equal(LandsidePlacement.NAMES[lot_kind])
	assert_str(_inspect.built_card.field_text("status")).is_equal("Status: Open")
	_land.set_lot_closed(0, true)
	_hud.refresh()
	assert_str(_inspect.built_card.field_text("status")).is_equal("Status: Closed")
	_outline.refresh()
	var frame := _outline.frame_aabb()
	print("outline %s around car park %s" % [frame, lot.centre])
	assert_float(frame.size.x).is_equal_approx(lot.footprint.x, 0.001)
	assert_float(frame.size.z).is_equal_approx(lot.footprint.y, 0.001)
	# Ground beside the car park, outside its footprint, clears.
	var beside := lot.centre + Vector3(lot.footprint.x / 2.0 + 1.0, 0.0, 0.0)
	await _click_world(beside)
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.NONE)
	_land.set_lot_closed(0, false)
	_land.remove_lot(0)


func test_a_click_while_a_template_is_being_saved_has_one_owner() -> void:
	var templates := _mode.templates
	var saved := templates.library.size()
	var middle := _room_area.position + _room_area.size / 2
	_look_at(_cell_top(middle, 0.0))
	# Saving a room runs with no tool picked: the click saves the room under it
	# and must not also select it.
	templates.arm_capture()
	assert_bool(BuiltSelection.clicks_taken(_mode)).is_true()
	await _click_world(_cell_top(middle, 0.0))
	print(
		(
			"template saved %d -> %d, selection kind %d"
			% [saved, templates.library.size(), _selection().kind]
		)
	)
	assert_int(templates.library.size()).is_equal(saved + 1)
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.NONE)
	assert_bool(_inspect.visible).is_false()
	# With the saving over, the same click selects the room.
	assert_bool(BuiltSelection.clicks_taken(_mode)).is_false()
	await _click_world(_cell_top(middle, 0.0))
	assert_int(_selection().kind).is_equal(BuiltSelection.Kind.ROOM)
	# A selection made earlier goes when a paste is armed.
	templates.arm(0)
	_hud.refresh()
	assert_bool(_selection().is_selected()).is_false()
	templates.disarm()


func test_a_room_being_moved_owns_the_clicks() -> void:
	assert_bool(BuiltSelection.clicks_taken(_mode)).is_false()
	_mode.room_mover.active = true
	assert_bool(BuiltSelection.clicks_taken(_mode)).is_true()
	_mode.room_mover.active = false


func test_the_card_works_the_grid_half_once_and_the_sim_half_once_per_tick() -> void:
	await _click_world(_cell_top(_desk_anchor(), 0.4))
	var card := _inspect.built_card
	var statics := card.static_builds
	var lives := card.live_builds
	for i in 5:
		_hud.refresh()
	print(
		(
			"5 refreshes: static %d -> %d, live %d -> %d"
			% [statics, card.static_builds, lives, card.live_builds]
		)
	)
	assert_int(card.static_builds).is_equal(statics)
	assert_int(card.live_builds).is_equal(lives)
	SaveTestKit.step(_main)
	_hud.refresh()
	assert_int(card.live_builds).is_equal(lives + 1)
	assert_int(card.static_builds).is_equal(statics)
	# A grid edit makes the grid half stale.
	var placed := _mode.grid.apply(BuildEdit.place_object(&"statue_indoor", _plain_cell, 0))
	assert_bool(placed.ok).is_true()
	_hud.refresh()
	assert_int(card.static_builds).is_equal(statics + 1)
	_mode.grid.apply(BuildEdit.remove_object(placed.object_id))


func test_a_gate_desk_shows_its_link_and_no_staff_or_queue() -> void:
	var desks := GateDesks.desk_ids(_mode.grid)
	assert_bool(desks.is_empty()).is_false()
	_select_object(desks[0])
	var card := _inspect.built_card
	print(
		(
			"gate desk: %s | %s | staff '%s' queue '%s'"
			% [
				card.name_text(),
				card.field_text("status"),
				card.field_text("staff"),
				card.field_text("queue")
			]
		)
	)
	assert_str(card.name_text()).is_equal("Gate desk")
	assert_str(card.field_text("status")).starts_with("Status: Linked to Gate ")
	assert_str(card.field_text("staff")).is_empty()
	assert_str(card.field_text("queue")).is_empty()


func test_an_incomplete_security_arch_says_what_the_lane_lacks() -> void:
	var placed := _mode.grid.apply(BuildEdit.place_object(SecurityLanes.ARCH, _plain_cell, 0))
	print("arch placement: ok %s %s" % [placed.ok, placed.reason_text()])
	assert_bool(placed.ok).is_true()
	_select_object(placed.object_id)
	var card := _inspect.built_card
	print(
		(
			"arch: %s | %s | staff '%s'"
			% [card.name_text(), card.field_text("status"), card.field_text("staff")]
		)
	)
	assert_str(card.field_text("status")).starts_with("Status: Not ready, ")
	assert_str(card.field_text("staff")).is_empty()
	assert_str(card.field_text("queue")).is_empty()
	_mode.grid.apply(BuildEdit.remove_object(placed.object_id))


func _select_object(object_id: int) -> void:
	_selection().kind = BuiltSelection.Kind.OBJECT
	_selection().id = object_id
	_hud.refresh()
