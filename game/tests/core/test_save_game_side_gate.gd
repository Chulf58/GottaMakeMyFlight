class_name TestSaveGameSideGate
extends GdUnitTestSuite
## A gate on a west exit goes through the whole-world save (slice S5 of design
## airside-all-around-technical-design-one-route-source-per-con): the gates part
## holds its binding, the apron part its west stand, and a load installs both,
## with the stand rebuilt as for_exit() gives it (ApronStand.stands_problem()).
## One boot of main.tscn: the starter terminal with its gate desk (gate A, the
## north exit), run until the airport opens so the starter flight takes gate A,
## then an exit low in the west wall with a gate desk beside it (gate B).

const SEED := 5_501_023
## ReferenceTerminal cells, moved onto the grid by the site's starter offset:
## the west wall's last airside row, its cell inside, and the desk two cells in
## with its rear staff spot free.
const WEST_EXIT := Vector2i(ReferenceTerminal.FLOOR_MIN.x, 8)
const WEST_DESK := Vector2i(ReferenceTerminal.FLOOR_MIN.x + 2, 8)

var _main: Node
var _save: SaveGame
var _mode: BuildMode
var _flights: FlightSim
var _gates: GateDesks
var _apron: ApronStand
var _west := 0


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_mode = _main.get_node("BuildMode")
	_flights = _main.get_node("FlightSim")
	_gates = _main.get_node("GateDesks")
	_apron = _main.get_node("ApronStand")
	SaveTestKit.start_airport(_main)
	for i in 6000:
		if _flights.opened_tick >= 0:
			break
		SaveTestKit.step(_main)
	assert_int(_flights.opened_tick).is_greater_equal(0)
	var offset := ReferenceTerminal.offset_on(_mode.grid)
	var exit_at := WEST_EXIT + offset
	var edits: Array[BuildEdit] = [
		BuildEdit.remove_wall(exit_at, BuildGrid.Side.WEST),
		BuildEdit.place_object(&"exit_door", exit_at, 3),
	]
	for result in _mode.grid.apply_batch(edits):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	_west = _mode.grid.object_at(exit_at)
	var desk := _mode.grid.apply(BuildEdit.place_object(GateDesks.DESK, WEST_DESK + offset, 0))
	assert_bool(desk.ok).override_failure_message(desk.reason_text()).is_true()


func after() -> void:
	_main.free()


func test_a_west_gate_round_trips_through_the_whole_world_save() -> void:
	print("bindings %s, stands %s" % [_gates.bindings, _gates.stands])
	assert_array(_flights.gate_ids()).is_equal(["A", "B"])
	assert_int(_gates.binding_of("B")["exit"]).is_equal(_west)
	var west_stand: Dictionary = _apron.gate_stands["B"]["live"]
	assert_str(StandPlacement.side_of(west_stand)).is_equal(StandPlacement.WEST)
	SaveTestKit.step(_main)
	var data: Dictionary = JSON.parse_string(JSON.stringify(_save.snapshot(), "", true, true))
	print("gates %s, apron %s" % [data["gates"], data["apron"]])
	assert_int(int(data["save_version"])).is_equal(SaveGame.SAVE_VERSION)
	assert_str(data["apron"]["stands"]["B"].get("side", "")).is_equal(StandPlacement.WEST)
	var saved_bindings := _gates.bindings.duplicate(true)
	# Gate B goes, so the load has to bring it back.
	var removed := _mode.grid.apply(BuildEdit.remove_object(_gates.binding_of("B")["desk"]))
	assert_bool(removed.ok).override_failure_message(removed.reason_text()).is_true()
	assert_array(_flights.gate_ids()).is_equal(["A"])
	assert_bool(_save.load_world(data)).override_failure_message(_save.message_text()).is_true()
	print("after the load: bindings %s, stands %s" % [_gates.bindings, _apron.gate_stands])
	assert_array(_gates.bindings).is_equal(saved_bindings)
	assert_array(_flights.gate_ids()).is_equal(["A", "B"])
	assert_dict(_apron.gate_stands["B"]["live"]).is_equal(west_stand)
	assert_dict(_gates.stands["B"]).is_equal(StandPlacement.for_exit(_mode.grid, _west))
