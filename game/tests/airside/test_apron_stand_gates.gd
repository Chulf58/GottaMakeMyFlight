class_name TestApronStandGates
extends GdUnitTestSuite
## ApronStand with gate desks (decision gates-technical-design-gate-desks-
## link-to-north-exits-one-st, point 2): one stand per gate, straight out from
## its exit; the guard covers what each gate's busy flight still needs and
## nothing of an idle gate; each gate says when its stand is unusable; gate
## desk refusals reach the site guard; the save holds each gate's stand.
##
## Two starter shells as in test_gate_desks.gd: gate A out of the starter exit
## (stand x -26), gate B out of the exit 44 cells east (stand x 18).

const SITE := preload("res://build/terminal_site.tres")
const EAST := Vector2i(44, 0)
const DESK_WEST := Vector2i(19, 115)
## Under the plane parked at gate A's stand (x -26, z -115), and at B's.
const FOOTPRINT_A := Vector2i(17, 95)
const FOOTPRINT_B := FOOTPRINT_A + EAST

var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks
var _apron: ApronStand
var _starts: Array[int] = []


func before_test() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	for result in _grid.apply_batch(ReferenceTerminal.shell_edits(SITE.starter_offset + EAST)):
		assert_bool(result.ok).is_true()
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(_grid, _flights)
	_apron = auto_free(ApronStand.new()) as ApronStand
	_apron.bind(_grid, SITE, _flights, _gates)
	_grid.guard = _apron.edit_problem
	for at in [DESK_WEST, DESK_WEST + EAST]:
		assert_bool(_grid.apply(BuildEdit.place_object(GateDesks.DESK, at, 0)).ok).is_true()
	_starts = FlightSim.schedule_starts(1000)


func _paint(cell: Vector2i) -> BuildResult:
	return _grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1))


func test_each_gate_has_the_stand_out_from_its_own_exit() -> void:
	print("gate stands %s" % [_apron.gate_stands])
	assert_array(_apron.gate_stands.keys()).is_equal(["A", "B"])
	for binding in _gates.bindings:
		var stand: Dictionary = _apron.gate_stands[binding["gate"]]["live"]
		assert_dict(stand).is_equal(StandPlacement.for_exit(_grid, binding["exit"]))
		assert_str(_apron.gate_stands[binding["gate"]]["placement"]["status"]).is_equal(
			StandPlacement.OK
		)
	assert_float(StandPlacement.stand_point(_apron.gate_stands["A"]["live"]).x).is_equal(-26.0)
	assert_float(StandPlacement.stand_point(_apron.gate_stands["B"]["live"]).x).is_equal(18.0)
	assert_dict(_apron.live).is_empty()


func test_the_guard_covers_only_the_gate_whose_flight_is_there() -> void:
	assert_bool(_flights.add_flight("AT_B", _starts, "B")).is_true()
	_flights.on_tick(_starts[FlightSim.State.BOARDING])
	var at_b := _paint(FOOTPRINT_B)
	var at_a := _paint(FOOTPRINT_A)
	print("boarding at B: B footprint %s, A footprint %s" % [at_b.reason_text(), at_a.ok])
	assert_int(at_b.reason).is_equal(BuildResult.Reason.PLANE_AREA)
	assert_bool(at_a.ok).is_true()
	assert_str(_apron.busy_flight("B")).is_equal("AT_B")
	assert_str(_apron.busy_flight("A")).is_equal("")
	_flights.on_tick(_starts[FlightSim.State.TAKEOFF])
	assert_array(_apron.guard_rects()).is_empty()
	assert_bool(_paint(FOOTPRINT_B).ok).is_true()


func test_a_gate_built_over_says_it_has_no_usable_stand() -> void:
	assert_str(_apron.gate_status_text("A")).is_equal("")
	assert_bool(_paint(FOOTPRINT_A).ok).is_true()
	print("A: '%s'; B: '%s'" % [_apron.gate_status_text("A"), _apron.gate_status_text("B")])
	assert_str(_apron.gate_status_text("A")).contains("no usable stand")
	assert_str(_apron.gate_status_text("B")).is_equal("")
	# The gate stays, at its own stand.
	assert_array(_flights.gate_ids()).is_equal(["A", "B"])


func test_gate_desk_refusals_reach_the_site_guard() -> void:
	var far := _grid.apply(BuildEdit.place_object(GateDesks.DESK, Vector2i(12, 125), 0))
	print("desk by the entrance: %s" % far.reason_text())
	assert_int(far.reason).is_equal(BuildResult.Reason.GATE_NO_EXIT)


func test_the_gate_stands_round_trip_a_snapshot_and_a_wrong_one_is_refused() -> void:
	var data: Dictionary = JSON.parse_string(JSON.stringify(_apron.to_snapshot()))
	print("apron part %s" % [data])
	assert_array((data["stands"] as Dictionary).keys()).is_equal(["A", "B"])
	assert_bool(_apron.from_snapshot(data)).is_true()
	assert_dict(_apron.gate_stands["B"]["live"]).is_equal(StandPlacement.for_exit(_grid, 4))
	var swapped := data.duplicate(true)
	swapped["stands"]["A"] = data["stands"]["B"]
	assert_bool(_apron.from_snapshot(swapped)).is_false()
	var missing := data.duplicate(true)
	(missing["stands"] as Dictionary).erase("B")
	assert_bool(_apron.from_snapshot(missing)).is_false()
	var one := {"live": data["stands"]["A"]}
	assert_bool(_apron.from_snapshot(one)).is_false()
	assert_str(ApronStand.stands_problem(swapped["stands"], _gates.bindings, _grid)).contains(
		"gate A"
	)
