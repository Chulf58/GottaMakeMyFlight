class_name TestGateClearanceZone
extends GdUnitTestSuite
## Build-mode gate stand clearance zone (decision
## starter-shell-shifted-south-with-build-mode-gate-clearance-zone): while in
## build mode, hovering or dragging near (<= CLEARANCE_MARGIN_M) a gate's
## StandEnvelope fills its zone with CLEARANCE_NEAR_TINT, shifting to
## CLEARANCE_OVERLAP_TINT when a building edit or drag overlaps the envelope,
## and hiding outside build mode or when far away.

const SITE := preload("res://build/terminal_site.tres")

var _finances: Finances
var _mode: BuildMode
var _flights: FlightSim
var _gates: GateDesks
var _view: GateLinksView


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.site = SITE
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_process(false)
	LandKit.own_all(_mode.land_tool.land)
	assert_bool(StarterShell.place(_mode.grid, SITE.starter_offset)).is_true()
	_flights = FlightSim.new()
	_flights.open_airport()
	_gates = GateDesks.new()
	_gates.bind(_mode.grid, _flights)
	var site_grid := _mode.grid as SiteGrid
	site_grid.guard = _gates.edit_problem
	site_grid.warner = _gates.edit_warning
	var desk := ReferenceTerminal.gate_desk_edit(SITE.starter_offset)
	assert_bool(site_grid.apply(desk).ok).is_true()
	assert_str(_gates.max_class("A")).is_equal(PlaneClasses.LARGE)
	_view = GateLinksView.new()
	add_child(_view)
	_view.set_process(false)
	_view.bind(_mode.grid, _gates)
	_view.build_mode = _mode


func after_test() -> void:
	_view.free()
	_mode.free()
	_finances.free()
	_gates.free()
	_flights.free()


func _hover_cell(cell: Vector2i) -> void:
	_mode._update_ghost(_mode.grid.cell_to_world(cell))
	_view.update_clearance()


func _swing_rect(gate: String) -> Rect2:
	var plane_class := _gates.max_class(gate)
	return StandEnvelope.rects(_gates.stands[gate], plane_class)[0]


func test_clearance_zone_shows_near_and_stronger_on_overlap_and_hides_far_or_off() -> void:
	var swing := _swing_rect("A")
	var inside := _mode.grid.world_to_cell(Vector3(swing.get_center().x, 0.0, swing.get_center().y))
	var near := _mode.grid.world_to_cell(Vector3(swing.end.x + 3.0, 0.0, swing.get_center().y))
	var far := _mode.grid.world_to_cell(Vector3(swing.end.x + 12.0, 0.0, swing.get_center().y))
	var zone := _view.clearance_node("A")
	assert_object(zone).is_not_null()

	# Outside build mode: always hidden even when hovering inside the envelope.
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_view.set_building(false)
	_hover_cell(inside)
	assert_bool(zone.visible).is_false()

	# In build mode, hovering far away (> 6 cells): hidden.
	_view.set_building(true)
	_hover_cell(far)
	assert_bool(zone.visible).is_false()

	# Hovering within 6 cells: visible in soft near tint.
	_hover_cell(near)
	assert_bool(zone.visible).is_true()
	var near_mat := zone.material_override as StandardMaterial3D
	assert_that(near_mat.albedo_color).is_equal(GateLinksView.CLEARANCE_NEAR_TINT)

	# Hovering a building edit inside the envelope: stronger red-amber warning tint.
	_hover_cell(inside)
	assert_bool(zone.visible).is_true()
	var overlap_mat := zone.material_override as StandardMaterial3D
	assert_that(overlap_mat.albedo_color).is_equal(GateLinksView.CLEARANCE_OVERLAP_TINT)
	assert_float(overlap_mat.albedo_color.a).is_greater(near_mat.albedo_color.a)

	# Tool.NONE and Tool.REMOVE inside the envelope stay on soft near tint.
	_mode.set_tool(BuildMode.Tool.NONE)
	_hover_cell(inside)
	assert_bool(zone.visible).is_true()
	assert_that((zone.material_override as StandardMaterial3D).albedo_color).is_equal(
		GateLinksView.CLEARANCE_NEAR_TINT
	)
	_mode.set_tool(BuildMode.Tool.REMOVE)
	_hover_cell(inside)
	assert_bool(zone.visible).is_true()
	assert_that((zone.material_override as StandardMaterial3D).albedo_color).is_equal(
		GateLinksView.CLEARANCE_NEAR_TINT
	)

	# Leaving build mode hides it cleanly.
	_view.set_building(false)
	assert_bool(zone.visible).is_false()


func test_floor_drag_highlights_near_then_overlap_as_rectangle_reaches_envelope() -> void:
	var swing := _swing_rect("A")
	var far_start := _mode.grid.world_to_cell(
		Vector3(swing.end.x + 12.0, 0.0, swing.get_center().y)
	)
	var near_end := _mode.grid.world_to_cell(Vector3(swing.end.x + 3.0, 0.0, swing.get_center().y))
	var inside_end := _mode.grid.world_to_cell(
		Vector3(swing.end.x - 2.0, 0.0, swing.get_center().y)
	)
	var zone := _view.clearance_node("A")
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_view.set_building(true)
	_mode.begin_area(_mode.grid.cell_to_world(far_start))
	_view.update_clearance()
	assert_bool(zone.visible).is_false()

	_mode.move_area(_mode.grid.cell_to_world(near_end))
	_view.update_clearance()
	assert_bool(zone.visible).is_true()
	assert_that((zone.material_override as StandardMaterial3D).albedo_color).is_equal(
		GateLinksView.CLEARANCE_NEAR_TINT
	)

	_mode.move_area(_mode.grid.cell_to_world(inside_end))
	_view.update_clearance()
	assert_bool(zone.visible).is_true()
	assert_that((zone.material_override as StandardMaterial3D).albedo_color).is_equal(
		GateLinksView.CLEARANCE_OVERLAP_TINT
	)
	_mode.cancel_area()


func test_envelope_fill_rects_have_no_overlap_on_north_and_side_stands() -> void:
	var north: Dictionary = _gates.stands["A"]
	var north_rects := GateLinksView.envelope_fill_rects(north, PlaneClasses.LARGE)
	assert_int(north_rects.size()).is_equal(2)
	assert_bool(north_rects[0].intersects(north_rects[1])).is_false()

	var west := StandPlacement.make(99, -43.0, -100.0, StandPlacement.WEST, -124.0)
	var west_rects := GateLinksView.envelope_fill_rects(west, PlaneClasses.MEDIUM)
	assert_int(west_rects.size()).is_equal(2)
	assert_bool(west_rects[0].intersects(west_rects[1])).is_false()


func test_apron_stand_resolves_build_mode_for_clearance_zone() -> void:
	var apron := ApronStand.new()
	apron.build_mode = _mode
	apron.flights = _flights
	apron.gates = _gates
	add_child(apron)
	apron.set_process(false)
	apron.links_view().set_process(false)
	apron.set_building(true)
	var swing := _swing_rect("A")
	var inside := _mode.grid.world_to_cell(Vector3(swing.get_center().x, 0.0, swing.get_center().y))
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode._update_ghost(_mode.grid.cell_to_world(inside))
	apron.links_view().update_clearance()
	var zone := apron.links_view().clearance_node("A")
	assert_object(zone).is_not_null()
	assert_bool(zone.visible).is_true()
	assert_that((zone.material_override as StandardMaterial3D).albedo_color).is_equal(
		GateLinksView.CLEARANCE_OVERLAP_TINT
	)
	apron.free()


func _make_cafe_room() -> Dictionary:
	var rect := Rect2i(SITE.starter_offset + Vector2i(11, 8), Vector2i(3, 3))
	var placed := _mode.grid.apply(BuildEdit.place_room(rect, &"cafe"))
	assert_bool(placed.ok).override_failure_message(placed.reason_text()).is_true()
	return {"id": placed.room_id, "cell": rect.position + Vector2i(1, 1)}


func test_template_paste_triggers_clearance_near_and_overlap() -> void:
	var room := _make_cafe_room()
	var template := RoomTemplate.capture(_mode.grid, room["id"])
	assert_object(template).is_not_null()
	_mode.templates.library.add(template)
	_mode.templates.arm(0)
	_view.set_building(true)
	var swing := _swing_rect("A")
	var far := _mode.grid.world_to_cell(Vector3(swing.end.x + 12.0, 0.0, swing.get_center().y))
	var near := _mode.grid.world_to_cell(Vector3(swing.end.x + 4.0, 0.0, swing.get_center().y))
	var edge_overlap := _mode.grid.world_to_cell(
		Vector3(swing.end.x + 0.5, 0.0, swing.get_center().y)
	)
	var zone := _view.clearance_node("A")

	_hover_cell(far)
	assert_bool(zone.visible).is_false()

	_hover_cell(near)
	assert_bool(zone.visible).is_true()
	assert_that((zone.material_override as StandardMaterial3D).albedo_color).is_equal(
		GateLinksView.CLEARANCE_NEAR_TINT
	)

	# Centred 3x3 template overlaps the envelope even when the pointer cell is just outside it.
	_hover_cell(edge_overlap)
	assert_bool(zone.visible).is_true()
	assert_that((zone.material_override as StandardMaterial3D).albedo_color).is_equal(
		GateLinksView.CLEARANCE_OVERLAP_TINT
	)
	_mode.templates.disarm()


func test_room_move_triggers_clearance_near_and_overlap() -> void:
	var room := _make_cafe_room()
	_view.set_building(true)
	assert_bool(_mode.room_mover.pick_up(_mode.grid.cell_to_world(room["cell"]), &"cafe")).is_true()
	var swing := _swing_rect("A")
	var far := _mode.grid.world_to_cell(Vector3(swing.end.x + 12.0, 0.0, swing.get_center().y))
	var near := _mode.grid.world_to_cell(Vector3(swing.end.x + 4.0, 0.0, swing.get_center().y))
	var edge_overlap := _mode.grid.world_to_cell(
		Vector3(swing.end.x + 0.5, 0.0, swing.get_center().y)
	)
	var zone := _view.clearance_node("A")

	_mode.room_mover.hover_at(far)
	_view.update_clearance()
	assert_bool(zone.visible).is_false()

	_mode.room_mover.hover_at(near)
	_view.update_clearance()
	assert_bool(zone.visible).is_true()
	assert_that((zone.material_override as StandardMaterial3D).albedo_color).is_equal(
		GateLinksView.CLEARANCE_NEAR_TINT
	)

	# Moved 3x3 room footprint reaches into the envelope even from one cell outside it.
	_mode.room_mover.hover_at(edge_overlap)
	_view.update_clearance()
	assert_bool(zone.visible).is_true()
	assert_that((zone.material_override as StandardMaterial3D).albedo_color).is_equal(
		GateLinksView.CLEARANCE_OVERLAP_TINT
	)
	_mode.room_mover.cancel()
