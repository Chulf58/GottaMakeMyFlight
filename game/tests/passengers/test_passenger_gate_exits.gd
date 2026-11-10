class_name TestPassengerGateExits
extends GdUnitTestSuite
## Passengers leave by their flight's gate (decision gates-technical-design-
## gate-desks-link-to-north-exits-one-st, point 7): with gate desks each gate's
## exit walks to its own stand, a passenger may leave only by the exit of its
## flight's gate, the forecast prices that exit, and a passenger of a gate B
## flight walks past gate A's exit, out of B's and onto B's plane.
##
## One terminal on the site, columns 18 to 66 and rows 112 to 125 from the
## site's frame: the entrance on the south edge, a desk and a scanner, and two
## north exits 44 m apart, each with a gate desk beside it.

const SITE := preload("res://build/terminal_site.tres")
const EXIT_A := Vector2i(20, 112)
const EXIT_B := Vector2i(64, 112)
const ENTRANCE := Vector2i(24, 125)
const FLIGHT_B := "TO_B"

var _world: PassengerTestWorld
var _gates: GateDesks
var _apron: ApronStand
var _exit_a := 0
var _exit_b := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	var floor: Array[BuildEdit] = []
	for y in range(112, 126):
		for x in range(18, 67):
			floor.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(floor)
	PassengerTestWorld.place(grid, &"entrance_door", ENTRANCE, 2)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(23, 121), 0)
	PassengerTestWorld.place(grid, &"security_scanner", Vector2i(24, 116), 0)
	_exit_a = PassengerTestWorld.place(grid, &"exit_door", EXIT_A, 0)
	_exit_b = PassengerTestWorld.place(grid, &"exit_door", EXIT_B, 0)
	EnclosureKit.close_floor(grid)
	var starts := FlightSim.schedule_starts(0)
	_world = PassengerTestWorld.make(grid, starts)
	_world.sim.site = SITE
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(grid, _world.flights)
	PassengerTestWorld.place(grid, GateDesks.DESK, EXIT_A + Vector2i(-1, 2), 0)
	PassengerTestWorld.place(grid, GateDesks.DESK, EXIT_B + Vector2i(-1, 2), 0)
	_apron = auto_free(ApronStand.new()) as ApronStand
	_apron.passengers = _world.sim
	_apron.bind(grid, SITE, _world.flights, _gates)
	assert_bool(_world.flights.add_flight(FLIGHT_B, starts, "B")).is_true()


func test_each_gates_exit_walks_to_its_own_stand_and_serves_only_its_flights() -> void:
	var layout := _world.sim.layout
	var stand_b: Dictionary = _apron.gate_stands["B"]["live"]
	print(
		(
			"open %s, for A %s, for B %s, exit gates %s"
			% [
				layout.open_exits(_world.grid),
				layout.open_exits_for(_world.grid, "A"),
				layout.open_exits_for(_world.grid, "B"),
				layout.exit_gates
			]
		)
	)
	assert_array(layout.open_exits(_world.grid)).contains_exactly_in_any_order([_exit_a, _exit_b])
	assert_array(layout.open_exits_for(_world.grid, "A")).is_equal([_exit_a])
	assert_array(layout.open_exits_for(_world.grid, "B")).is_equal([_exit_b])
	assert_dict(layout.stand_of(_world.grid, _exit_b)).is_equal(stand_b)
	var walk := OutsideWalks.departure(_world.sim, _exit_b)
	var door := StandPlacement.door_point(stand_b)
	print("B's walk ends at %s, B's plane door %s" % [walk[walk.size() - 1], door])
	assert_float(walk[walk.size() - 1].x).is_equal_approx(door.x, 0.001)
	assert_float(walk[walk.size() - 1].z).is_equal_approx(door.z, 0.001)


func test_a_passenger_picks_and_is_forecast_through_its_gates_exit() -> void:
	var p := _world.passenger(_world.sim.spawn_now(FLIGHT_B))
	# Beside gate A's exit, the nearest one by far.
	var near_a := EXIT_A + Vector2i(1, 1)
	var any := JourneyForecast.nearest_exit(_world.sim, near_a)
	var its := JourneyForecast.nearest_exit(_world.sim, near_a, p)
	print("from %s: any exit %s, its gate's %s" % [near_a, any, its])
	assert_int(any.x).is_equal(_exit_a)
	assert_int(its.x).is_equal(_exit_b)
	assert_array(_world.sim.exits_for(p)).is_equal([_exit_b])
	# The forecast needs the desk and scanner staffed, from the first tick on.
	var own := {}
	while own.is_empty() and _world.clock.tick < 200:
		_world.step()
		own = JourneyForecast.own_times(_world.sim, p, _world.clock.tick, true)
	print("tick %d: forecast %s" % [_world.clock.tick, own])
	assert_int(own["door"]).is_equal(_exit_b)


func test_a_gate_b_passenger_boards_through_b_onto_bs_plane() -> void:
	var p := _world.passenger(_world.sim.spawn_now(FLIGHT_B))
	var exits := {}
	var doors := _world.flights.doors_close_tick(FLIGHT_B)
	while _world.clock.tick < doors and not p.is_done():
		_world.step()
		if p.exit_object != 0:
			exits[p.exit_object] = true
		if p.stage == Passenger.Stage.APRON:
			var end: Vector3 = p.apron[p.apron.size() - 1]
			exits["plane"] = Vector2(end.x, end.z)
	# A one-off flight flies the starter's plane 03, whose passengers walk out
	# of the jet bridge's apron door to its door on the ground (ruling plane-03-
	# boards-on-foot-from-the-apron-plane-04-docks-the-no).
	var model := PlaneClasses.flight_model(_world.flights, FLIGHT_B)
	var stand: Dictionary = _apron.gate_stands["B"]["live"]
	# It ends on the ground out from the 03's door, clear of the fuselage.
	var at := JetBridgePose.plane_door(stand, model)
	var door: Vector3 = at["door"] + (at["normal"] as Vector3) * JetBridgePose.APRON_END_OUT_M
	print(
		(
			"stage %s at tick %d, exits used %s, B's plane door %s"
			% [Passenger.Stage.keys()[p.stage], _world.clock.tick, exits, door]
		)
	)
	assert_str(model).is_equal("tp_plane_03a")
	assert_int(p.stage).is_equal(Passenger.Stage.MADE)
	assert_array(exits.keys()).contains_exactly_in_any_order([_exit_b, "plane"])
	assert_vector(exits["plane"]).is_equal_approx(Vector2(door.x, door.z), Vector2.ONE * 0.001)


## A saved apron walker must have come out of its flight's gate exit: one that
## names gate A's exit while flying from B is refused on load.
func test_a_save_with_an_apron_walker_from_another_gates_exit_is_refused() -> void:
	var p := _world.passenger(_world.sim.spawn_now(FLIGHT_B))
	var doors := _world.flights.doors_close_tick(FLIGHT_B)
	while (
		_world.clock.tick < doors
		and not (p.stage == Passenger.Stage.APRON and p.apron_mm >= BoardingFiles.GAP_MM)
	):
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.APRON)
	var by_id := {p.id: p}
	var data := _world.sim.to_snapshot()
	var as_saved := _world.sim.checked_boarding(data, by_id)
	p.exit_object = _exit_a
	var other_gate := _world.sim.checked_boarding(data, by_id)
	p.exit_object = _exit_b
	print(
		(
			"own exit: %s; gate A's exit: %s"
			% [as_saved.get("error", "ok"), other_gate.get("error", "ok")]
		)
	)
	assert_bool(as_saved.has("error")).is_false()
	assert_str(other_gate.get("error", "")).contains("not its flight's gate")
