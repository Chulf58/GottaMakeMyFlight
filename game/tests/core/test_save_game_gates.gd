class_name TestSaveGameGates
extends GdUnitTestSuite
## The gates in the whole-world save (decision gates-technical-design-gate-
## desks-link-to-north-exits-one-st, points 1 and 2; save version 10): the part
## "gates" holds each gate's letter, desk and exit, and the apron part each
## gate's stand. The flights are checked against the saved gates, not the live
## ones, so a contract at a gate the live world has lost loads back. A save
## whose gates or stands do not match its grid is refused and the world is
## left as it was. One boot of main.tscn: the starter terminal with its gate
## desk (gate A), and a second shell 44 cells east with a gate desk (gate B),
## run until the airport opens with the starter contract at gate A.

const SEED := 4_401_017
const EAST := Vector2i(44, 0)
const DESK_EAST := Vector2i(63, 115)
const STARTER := FlightSim.DEFAULT_ID

var _main: Node
var _save: SaveGame
var _mode: BuildMode
var _flights: FlightSim
var _gates: GateDesks
var _apron: ApronStand


func before() -> void:
	_main = SaveTestKit.boot(self, SEED)
	_save = SaveTestKit.save_game(_main)
	_mode = _main.get_node("BuildMode")
	_flights = _main.get_node("FlightSim")
	_gates = _main.get_node("GateDesks")
	_apron = _main.get_node("ApronStand")
	SaveTestKit.start_airport(_main)
	var shell := ReferenceTerminal.shell_edits(_mode.site.starter_offset + EAST)
	var plots := {}
	for edit in shell:
		plots[_mode.land_tool.land.plot_of(edit.cell)] = true
	plots[_mode.land_tool.land.plot_of(DESK_EAST)] = true
	for plot: Vector2i in plots:
		LandKit.buy_to(_mode.land_tool.land, plot)
	for result in _mode.grid.apply_batch(shell):
		assert_bool(result.ok).is_true()
	assert_bool(_mode.grid.apply(BuildEdit.place_object(GateDesks.DESK, DESK_EAST, 0)).ok).is_true()
	# Until the airport opens with the starter contract (GMF101) at gate A.
	for i in 6000:
		if _flights.opened_tick >= 0:
			break
		SaveTestKit.step(_main)
	assert_int(_flights.opened_tick).is_greater_equal(0)


func after() -> void:
	_main.free()


## A save taken on the next tick, through JSON.
func _taken() -> Dictionary:
	SaveTestKit.step(_main)
	var data := _save.snapshot()
	assert_bool(data.is_empty()).is_false()
	return JSON.parse_string(JSON.stringify(data, "", true, true))


func _desk_of(gate: String) -> int:
	return _gates.binding_of(gate)["desk"]


func test_the_gates_and_their_stands_are_saved_and_a_lost_gate_loads_back() -> void:
	assert_array(_flights.gate_ids()).is_equal(["A", "B"])
	# The starter's days not yet issued move to gate B.
	assert_str(_flights.contract_of(STARTER)["gate"]).is_equal("A")
	assert_bool(_flights.reassign_gate(STARTER, "B")).is_true()
	var data := _taken()
	print(
		"save_version %s, gates %s, apron %s" % [data["save_version"], data["gates"], data["apron"]]
	)
	assert_int(int(data["save_version"])).is_equal(SaveGame.SAVE_VERSION)
	assert_int(SaveGame.SAVE_VERSION).is_equal(10)
	assert_int((data["gates"]["gates"] as Array).size()).is_equal(2)
	assert_array((data["apron"]["stands"] as Dictionary).keys()).is_equal(["A", "B"])
	var saved_bindings := _gates.bindings.duplicate(true)
	# Gate B goes: the starter moves back to A first.
	assert_bool(_mode.grid.apply(BuildEdit.remove_object(_desk_of("B"))).ok).is_true()
	assert_str(_flights.contract_of(STARTER)["gate"]).is_equal("A")
	assert_array(_flights.gate_ids()).is_equal(["A"])
	assert_bool(_save.load_world(data)).is_true()
	print(
		(
			"after the load: gates %s, starter at %s"
			% [_gates.bindings, _flights.contract_of(STARTER)["gate"]]
		)
	)
	assert_array(_gates.bindings).is_equal(saved_bindings)
	assert_array(_flights.gate_ids()).is_equal(["A", "B"])
	assert_str(_flights.contract_of(STARTER)["gate"]).is_equal("B")
	assert_array(_apron.gate_stands.keys()).is_equal(["A", "B"])
	var airside: Airside = _main.get_node("Airside")
	assert_bool(airside.graph.has_waypoint(&"Stand_B")).is_true()


func test_a_save_whose_gates_or_stands_do_not_match_its_grid_is_refused() -> void:
	var clean := _taken()
	var before := _gates.bindings.duplicate(true)
	var not_a_desk := clean.duplicate(true)
	not_a_desk["gates"]["gates"][0]["desk"] = not_a_desk["gates"]["gates"][0]["exit"]
	var swapped := clean.duplicate(true)
	swapped["apron"]["stands"]["A"] = clean["apron"]["stands"]["B"]
	var one_stand := clean.duplicate(true)
	one_stand["apron"] = {"live": clean["apron"]["stands"]["A"]}
	var old := clean.duplicate(true)
	old["save_version"] = 9
	for broken: Dictionary in [not_a_desk, swapped, one_stand, old]:
		assert_bool(_save.load_world(broken)).is_false()
		print("refused: %s" % _save.message_text())
	assert_array(_gates.bindings).is_equal(before)
	# A control: the clean save loads.
	assert_bool(_save.load_world(clean)).is_true()


## A save that leaves gate B out (its binding and its stand) is refused while
## it is staged, so nothing is installed: the world after the refusal is the
## world before it. (It used to pass staging; the load then linked desk B
## again, refused the stands at install and returned false over a world
## already half loaded.)
func test_a_save_missing_a_gate_is_refused_whole_and_changes_nothing() -> void:
	# No contract at B, so only the gates themselves can refuse the save.
	if _flights.contract_of(STARTER)["gate"] != "A":
		assert_bool(_flights.reassign_gate(STARTER, "A")).is_true()
	var data := _taken()
	var gates: Array = data["gates"]["gates"]
	var kept := gates.filter(func(entry: Dictionary) -> bool: return entry["gate"] != "B")
	data["gates"]["gates"] = kept
	(data["apron"]["stands"] as Dictionary).erase("B")
	assert_int(kept.size()).is_equal(1)
	# Moved on from the save, so a part installed from it would show.
	for i in 5:
		SaveTestKit.step(_main)
	var before := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(data)).is_false()
	print("refused: %s" % _save.message_text())
	assert_str(_save.message_text()).contains("no saved gate")
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)
	assert_array(_flights.gate_ids()).is_equal(["A", "B"])
