class_name TestApronStandSave
extends GdUnitTestSuite
## The live plane stand in a whole-world save (decision plane-stand-design-
## airside-moves-110-m-north-stand-snaps-to, point 8): a world saved while a
## better stand waits for the outgoing takeoff (wanted != live) loads into a
## twin with the same live stand, the same wanted one and the same checksum.

const SEED := 7_310_256
const WEST_EXIT := Vector2i(11, 112)

var _main: Node
var _twin: Node


func after_test() -> void:
	for node in [_main, _twin]:
		if is_instance_valid(node):
			node.free()


func _apron(main: Node) -> ApronStand:
	return main.get_node("ApronStand")


func test_a_save_with_a_pending_stand_move_loads_into_an_identical_twin() -> void:
	_main = SaveTestKit.boot(self, SEED)
	var flights: FlightSim = _main.get_node("FlightSim")
	var grid: BuildGrid = (_main.get_node("BuildMode") as BuildMode).grid
	# A one-off flight, run on until it is boarding at the starter stand.
	var boarding := FlightSim.State.BOARDING
	assert_bool(flights.add_flight("ONE", FlightSim.schedule_starts(flights.tick + 1))).is_true()
	while flights.state_of("ONE") < boarding:
		SaveTestKit.step(_main)
	assert_int(flights.state_of("ONE")).is_equal(boarding)
	# A second north exit, and floor straight out of the starter exit.
	assert_bool(grid.apply(BuildEdit.remove_wall(WEST_EXIT, BuildGrid.Side.NORTH)).ok).is_true()
	var west := grid.apply(BuildEdit.place_object(&"exit_door", WEST_EXIT, 0))
	assert_bool(west.ok).is_true()
	(
		assert_bool(
			grid.apply(BuildEdit.paint_floor(Vector2i(20, 110), BuildGrid.FLOOR_TILE, 1)).ok
		)
		. is_true()
	)
	SaveTestKit.step(_main)
	var apron := _apron(_main)
	print("before save: live %s wanted %s" % [apron.live, apron.wanted])
	assert_int(apron.wanted["exit"]).is_equal(west.object_id)
	assert_bool(ApronStand.same_stand(apron.live, apron.wanted)).is_false()
	var data := (
		JSON.parse_string(JSON.stringify(SaveTestKit.save_game(_main).snapshot())) as Dictionary
	)
	assert_int(int(data["save_version"])).is_equal(SaveGame.SAVE_VERSION)
	assert_bool(data.has("apron")).is_true()
	_twin = SaveTestKit.boot(self, SEED + 1)
	assert_bool(SaveTestKit.save_game(_twin).load_world(data)).is_true()
	var twin := _apron(_twin)
	print("twin: live %s wanted %s" % [twin.live, twin.wanted])
	assert_bool(ApronStand.same_stand(twin.live, apron.live)).is_true()
	assert_bool(ApronStand.same_stand(twin.wanted, apron.wanted)).is_true()
	var airside: Airside = _twin.get_node("Airside")
	assert_vector(airside.graph.position_of(&"Stand")).is_equal_approx(
		StandPlacement.stand_point(apron.live), Vector3.ONE * 0.001
	)
	assert_str(SaveTestKit.checksum(_twin)).is_equal(SaveTestKit.checksum(_main))
