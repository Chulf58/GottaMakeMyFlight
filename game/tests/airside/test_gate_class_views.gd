class_name TestGateClassViews
extends GdUnitTestSuite
## Where the player sees a gate's biggest plane (GateDesks.max_class; decision
## runway-and-taxi-technical-design-movement-plan-analytic-bookings-planned-
## pauses, section 3): the desk card says "Biggest plane: Large", and in build
## mode GateLinksView outlines that class's envelope on the ground and the
## gate's caption over its desk reads "Gate A" then "up to large planes" (the
## gate ribbon's form; no separate caption at the stand). Both follow the grid:
## building into the large-only space turns them to medium. An unlinked desk's
## sign names the two new reasons.
##
## The starter shell with its exit at (20, 112) and its gate desk at (19, 115);
## the cells are those of test_stand_envelope.gd.

const SITE := preload("res://build/terminal_site.tres")
const DESK := Vector2i(19, 115)
const LARGE_CELL := Vector2i(45, 100)
const FREE_CELL := Vector2i(60, 100)

var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks
var _view: GateLinksView


func before_test() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem
	_view = GateLinksView.new()
	add_child(_view)
	_view.bind(_grid, _gates)


func after_test() -> void:
	_view.free()


func _floor(cell: Vector2i) -> void:
	assert_bool(_grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1)).ok).is_true()


func _captions() -> Array:
	var out := []
	for caption in _view.gate_captions():
		out.append(caption.text)
	return out


func test_build_mode_outlines_the_max_class_envelope_with_its_class() -> void:
	var desk := _grid.apply(BuildEdit.place_object(GateDesks.DESK, DESK, 0))
	assert_bool(desk.ok).is_true()
	var stand := StandPlacement.for_exit(_grid, _gates.bindings[0]["exit"])
	var y := _grid.origin.y + GateLinksView.LIFT_M
	var large := GateLinksView.envelope_outline(stand, PlaneClasses.LARGE, y)
	var first := [_view.envelope_paths(), _captions()]
	_floor(FREE_CELL)
	var control := _captions()
	_floor(LARGE_CELL)
	var medium := GateLinksView.envelope_outline(stand, PlaneClasses.MEDIUM, y)
	print(
		"before %s; free cell %s; after the large-only cell %s" % [first[1], control, _captions()]
	)
	assert_array(first[0]).is_equal([large])
	assert_array(first[1]).is_equal(["Gate A\nup to large planes"])
	assert_array(control).is_equal(["Gate A\nup to large planes"])
	assert_array(_view.envelope_paths()).is_equal([medium])
	assert_array(_captions()).is_equal(["Gate A\nup to medium planes"])
	# The outline is the swing square and the way north as one closed shape, the
	# way reaching the taxi lane.
	assert_vector(large[0]).is_equal(large[-1])
	assert_float(large[3].z).is_equal_approx(StandPlacement.TAXI_LANE_Z, 0.0001)
	var verts: PackedVector3Array = (_view.envelope_node().mesh as ArrayMesh).surface_get_arrays(0)[
		Mesh.ARRAY_VERTEX
	]
	assert_int(verts.size()).is_equal((medium.size() - 1) * 4)
	# Shown with the links only while build mode lasts.
	assert_bool(_view.envelope_node().is_visible_in_tree()).is_false()
	_view.set_building(true)
	assert_bool(_view.envelope_node().is_visible_in_tree()).is_true()
	assert_bool(_view.gate_captions()[0].is_visible_in_tree()).is_true()


func test_the_desk_card_names_the_gates_biggest_plane() -> void:
	var desk := _grid.apply(BuildEdit.place_object(GateDesks.DESK, DESK, 0))
	assert_bool(desk.ok).is_true()
	var sim := auto_free(PassengerSim.new()) as PassengerSim
	sim.grid = _grid
	# The card wants a build mode (it reads only a landside pick from it); in
	# the tree, so its own member nodes are parented and freed with it.
	var finances := Finances.new()
	add_child(finances)
	var mode := BuildMode.new()
	mode.site = SITE
	mode.finances = finances
	add_child(mode)
	mode.set_process(false)
	var card := BuiltItemCard.new()
	card.sim = sim
	card.build_mode = mode
	card.gates = _gates
	card.selection = BuiltSelection.new()
	card.selection.kind = BuiltSelection.Kind.OBJECT
	card.selection.id = desk.object_id
	add_child(card)
	card.refresh()
	var before := card.field_text("planes")
	_floor(LARGE_CELL)
	card.invalidate()
	card.refresh()
	var after := card.field_text("planes")
	print("card: '%s' then '%s' (%s)" % [before, after, card.field_text("status")])
	assert_str(before).is_equal("Biggest plane: Large")
	assert_str(after).is_equal("Biggest plane: Medium")
	assert_str(card.field_text("status")).is_equal("Status: Linked to Gate A")
	card.free()
	mode.free()
	finances.free()


func test_an_unlinked_sign_names_no_room_and_a_blocked_way() -> void:
	var no_room := GateLinksView.caption_for({"why": GateDesks.Unlinked.NO_ROOM, "gate": ""})
	var blocked := GateLinksView.caption_for({"why": GateDesks.Unlinked.ROUTE_BLOCKED, "gate": ""})
	print("signs: '%s', '%s'" % [no_room, blocked])
	assert_str(no_room).is_equal("Unlinked: no room for a plane")
	assert_str(blocked).is_equal("Unlinked: way to the lane blocked")
