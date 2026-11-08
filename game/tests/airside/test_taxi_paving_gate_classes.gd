class_name TestTaxiPavingGateClasses
extends GdUnitTestSuite
## ApronStand sends each gate's max_class (GateDesks) to the airside, whose stand
## pad is sized for it (board item R10, conductor ruling 2026-11-08: a pad never
## paves a larger class's space, where the player may build). Building into a
## gate's larger envelope lowers its max_class and shrinks its pad, with no stand
## moving. Two starter shells as in test_apron_stand_gates.gd: gate A out of the
## starter exit (stand x -26), gate B out of the exit 44 cells east.

const MAIN_SCENE := "res://main/main.tscn"
const SITE := preload("res://build/terminal_site.tres")
const EAST := Vector2i(44, 0)
const DESK_WEST := Vector2i(19, 115)

var _grid: SiteGrid
var _gates: GateDesks
var _apron: ApronStand
var _airside: Airside


## The real Airside markers from main.tscn's saved state, as test_taxi_paving.gd
## builds them.
func _scene_airside() -> Airside:
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	var airside := Airside.new()
	for i in state.get_node_count():
		var props := {}
		for k in state.get_node_property_count(i):
			props[state.get_node_property_name(i, k)] = state.get_node_property_value(i, k)
		if String(state.get_node_path(i, true)) == "./Airside":
			if state.get_node_type(i) == &"Marker3D":
				var marker := Marker3D.new()
				marker.name = state.get_node_name(i)
				marker.transform = props.get(&"transform", Transform3D.IDENTITY)
				airside.add_child(marker)
		elif String(state.get_node_path(i)) == "./Airside":
			airside.links = props[&"links"]
	return airside


func before_test() -> void:
	_airside = auto_free(_scene_airside()) as Airside
	add_child(_airside)
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	for result in _grid.apply_batch(ReferenceTerminal.shell_edits(SITE.starter_offset + EAST)):
		assert_bool(result.ok).is_true()
	var flights := auto_free(FlightSim.new()) as FlightSim
	flights.open_airport()
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(_grid, flights)
	_apron = auto_free(ApronStand.new()) as ApronStand
	_apron.airside = _airside
	_apron.bind(_grid, SITE, flights, _gates)
	_grid.guard = _apron.edit_problem
	for at in [DESK_WEST, DESK_WEST + EAST]:
		assert_bool(_grid.apply(BuildEdit.place_object(GateDesks.DESK, at, 0)).ok).is_true()


## Gate `gate`'s pad, found by its stand's x.
func _pad_of(gate: String) -> Rect2:
	var at := StandPlacement.stand_point(_apron.gate_stands[gate]["live"])
	for pad in _airside.paving.pads:
		if pad.has_point(Vector2(at.x, at.z)):
			return pad
	return Rect2()


func test_each_gate_pad_is_sized_for_its_max_class() -> void:
	assert_array(_airside.gate_stands.keys()).contains_exactly_in_any_order(["A", "B"])
	print("max classes %s, sent %s" % [_gates.classes, _airside.gate_classes])
	assert_dict(_airside.gate_classes).is_equal(_gates.classes)
	assert_int(_airside.paving.pads.size()).is_equal(2)
	for gate in ["A", "B"]:
		var at := StandPlacement.stand_point(_apron.gate_stands[gate]["live"])
		var classes := Airside.classes_up_to(_gates.max_class(gate))
		assert_bool(classes.is_empty()).is_false()
		assert_object(_pad_of(gate)).is_equal(TaxiPaving.stand_pad(at, classes))


func test_building_in_the_larger_envelope_shrinks_the_pad() -> void:
	var stand: Dictionary = _apron.gate_stands["A"]["live"]
	var before := _gates.max_class("A")
	var pad_before := _pad_of("A")
	assert_str(before).is_not_equal(PlaneClasses.SMALL)
	# A cell inside A's current class swing square but outside the next class down's
	# swing square and way north.
	var lower := PlaneClasses.ORDER[PlaneClasses.ORDER.find(before) - 1]
	var at := StandPlacement.stand_point(stand)
	var reach := (StandEnvelope.radius(before) + StandEnvelope.radius(lower)) / 2.0
	var target := Vector3(at.x + reach, 0.0, at.z)
	var cell := _grid.world_to_cell(target)
	var result := _grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1))
	print(
		(
			"A was %s with pad %s; floor at %s (%s): %s; now %s with pad %s"
			% [before, pad_before, cell, target, result.ok, _gates.max_class("A"), _pad_of("A")]
		)
	)
	assert_bool(result.ok).is_true()
	assert_str(_gates.max_class("A")).is_equal(lower)
	assert_dict(_apron.gate_stands["A"]["live"]).is_equal(stand)
	var pad_after := _pad_of("A")
	assert_object(pad_after).is_equal(TaxiPaving.stand_pad(at, Airside.classes_up_to(lower)))
	assert_float(pad_after.get_area()).is_less(pad_before.get_area())
	# The new floor cell is off the pad: no asphalt lies under what the player built.
	assert_bool(pad_after.has_point(Vector2(target.x, target.z))).is_false()
	assert_bool(pad_before.has_point(Vector2(target.x, target.z))).is_true()
