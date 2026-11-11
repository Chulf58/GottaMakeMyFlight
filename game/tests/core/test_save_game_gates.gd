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
## In gate A's medium swing square but not its small one (test_stand_envelope.gd).
const MEDIUM_CELL := Vector2i(32, 100)
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
	assert_int(SaveGame.SAVE_VERSION).is_equal(15)
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


## The flights part is staged with FlightSim.load_problem() on the saved gates'
## stands (Runway R7), so a save whose flight is at a stand other than its
## gate's, or whose taxi re-plan fails, is refused while staged and nothing is
## installed. (Staging used to check only FlightSnapshot.load(), and the refusal
## came at install, over a world already half loaded.)
func test_a_save_whose_flights_do_not_re_plan_is_refused_while_staged() -> void:
	# Until the starter's first occurrence is issued, so the save has a flight.
	for i in 6000:
		if not _flights.flight_ids().is_empty():
			break
		SaveTestKit.step(_main)
	var data := _taken()
	var flights: Array = data["flights"]["flights"]
	assert_array(flights).is_not_empty()
	var moved: Dictionary = flights[0]["stand"]
	moved["x"] = float(moved["x"]) + 8.0
	for i in 5:
		SaveTestKit.step(_main)
	var before := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(data)).is_false()
	print("refused: %s" % _save.message_text())
	assert_str(_save.message_text()).contains("is not at its gate's stand")
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)


## Gate A is a small gate (a floor built in the medium swing) in the saved
## grid, gates and stands, while the saved flights hold a running medium
## contract at gate A: staging refuses the save on the contract's class and
## nothing is installed. (The build guard would not let the player shrink the
## gate under a booked medium plane, so the save is put together from two.) A
## control: the unmixed save loads.
func test_a_save_whose_gate_shrank_below_a_contract_is_refused_while_staged() -> void:
	var floor_edit := BuildEdit.paint_floor(MEDIUM_CELL, BuildGrid.FLOOR_TILE, 1)
	assert_bool(_mode.grid.apply(floor_edit).ok).is_true()
	assert_str(_gates.max_class("A")).is_equal(PlaneClasses.SMALL)
	var small := _taken()
	assert_bool(_mode.grid.apply(BuildEdit.remove_floor(MEDIUM_CELL)).ok).is_true()
	var board := (_main.get_node("OfferDesk") as OfferDesk).board
	var taken := ""
	# A new game's runway is small (Runway R9); this case is about the gate's class.
	_flights.runway.size = PlaneClasses.MEDIUM
	# Whatever the draw gave, the day-0 offers are made medium.
	var offers := board.to_snapshot()
	for offer: Dictionary in offers["offers"]:
		offer["plane_size"] = PlaneClasses.MEDIUM
		offer["booked_passengers"] = PlaneClasses.passenger_range(PlaneClasses.MEDIUM)[0]
	assert_bool(board.from_snapshot(offers)).is_true()
	for offer in board.open_offers():
		if taken == "" and _flights.accept_problem(OfferBoard.terms_of(offer)) == "":
			assert_bool(board.accept(offer["id"], _flights)).is_true()
			taken = offer["id"]
	assert_str(taken).is_not_empty()
	assert_str(_flights.contract_of(taken)["gate"]).is_equal("A")
	var wide := _taken()
	var narrow := wide.duplicate(true)
	for key in ["grid", "gates", "apron"]:
		narrow[key] = small[key]
	for i in 5:
		SaveTestKit.step(_main)
	var before := SaveTestKit.checksum(_main)
	assert_bool(_save.load_world(narrow)).is_false()
	print("refused: %s" % _save.message_text())
	assert_str(_save.message_text()).contains("contract %s needs a medium gate" % taken)
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)
	# The same save with a small runway holds a medium contract (and its medium
	# offers) the runway cannot take: refused while staged, nothing installed.
	var small_runway := wide.duplicate(true)
	small_runway["runway"]["size"] = "small"
	assert_bool(_save.load_world(small_runway)).is_false()
	print("small runway: %s" % _save.message_text())
	assert_str(_save.message_text()).contains("is a medium plane but the runway is small")
	assert_str(SaveTestKit.checksum(_main)).is_equal(before)
	assert_bool(_save.load_world(wide)).is_true()
