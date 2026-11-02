class_name TestApronStandSave
extends GdUnitTestSuite
## The gate stands in a whole-world save (decisions plane-stand-design-
## airside-moves-110-m-north-stand-snaps-to, point 8, and gates-technical-
## design-gate-desks-link-to-north-exits-one-st, point 2): a world saved while
## the starter flight boards at gate A's stand loads into a twin with the same
## gate stands, the same airside stand waypoints and the same checksum. (Before
## gate desks this saved a pending move of the one stand; with gate desks a
## gate's stand never moves, test_apron_stand.gd keeps the one-stand rules.)

const SEED := 7_310_256
## Ticks the hiring, the walk, the opening and the starter's arrival may take.
const LIMIT_TICKS := 12000

var _main: Node
var _twin: Node


func after_test() -> void:
	for node in [_main, _twin]:
		if is_instance_valid(node):
			node.free()


func _apron(main: Node) -> ApronStand:
	return main.get_node("ApronStand")


func test_a_save_with_a_plane_at_a_gate_stand_loads_into_an_identical_twin() -> void:
	_main = SaveTestKit.boot(self, SEED)
	var flights: FlightSim = _main.get_node("FlightSim")
	SaveTestKit.start_airport(_main)
	# The starter's first flight, run on until it is boarding at gate A.
	var first := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	var boarding := FlightSim.State.BOARDING
	var limit := flights.tick + LIMIT_TICKS
	while flights.state_of(first) < boarding and flights.tick < limit:
		SaveTestKit.step(_main)
	assert_int(flights.state_of(first)).is_equal(boarding)
	assert_str(flights.flight_gate(first)).is_equal("A")
	var apron := _apron(_main)
	print("before save: gate stands %s, busy at A %s" % [apron.gate_stands, apron.busy_flight("A")])
	assert_str(apron.busy_flight("A")).is_equal(first)
	var data := (
		JSON.parse_string(JSON.stringify(SaveTestKit.save_game(_main).snapshot())) as Dictionary
	)
	assert_int(int(data["save_version"])).is_equal(SaveGame.SAVE_VERSION)
	assert_bool(data.has("apron")).is_true()
	_twin = SaveTestKit.boot(self, SEED + 1)
	assert_bool(SaveTestKit.save_game(_twin).load_world(data)).is_true()
	var twin := _apron(_twin)
	print("twin: gate stands %s" % [twin.gate_stands])
	assert_dict(ApronStand._stands_of(twin.gate_stands)).is_equal(
		ApronStand._stands_of(apron.gate_stands)
	)
	var airside: Airside = _twin.get_node("Airside")
	assert_vector(airside.graph.position_of(&"Stand_A")).is_equal_approx(
		StandPlacement.stand_point(apron.gate_stands["A"]["live"]), Vector3.ONE * 0.001
	)
	assert_str(SaveTestKit.checksum(_twin)).is_equal(SaveTestKit.checksum(_main))
