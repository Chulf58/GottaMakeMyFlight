class_name TestGateDeskBinding
extends GdUnitTestSuite
## Passengers wait by the gate desk their gate is bound to (GateDesks.bindings,
## the sticky saved links), not by whichever desk stands nearest its exit: gate A
## is bound to the older desk D1, and a newer, unbound desk D2 stands closer to
## A's exit. Also: a version 15 passenger save, whose seat and spot claims
## followed the old global nearest rule, is refused (version 16).
##
## One exit at (40, 112); D1 three cells west of it, D2 one cell east; a seat
## row 5 cells below each desk and 9 from the other one.

const SITE := preload("res://build/terminal_site.tres")
const EXIT := Vector2i(40, 112)
const DESK_1 := Vector2i(36, 113)
const DESK_2 := Vector2i(41, 113)
const ROW_1 := Vector2i(30, 118)
const ROW_2 := Vector2i(46, 118)
const MIDDLE := Vector2i(40, 122)
const FLIGHT := "TO_A"

var _world: PassengerTestWorld
var _gates: GateDesks
var _apron: ApronStand
var _desk_1 := 0
var _desk_2 := 0
var _row_1 := 0
var _row_2 := 0


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func _build(desk_2_first: bool) -> void:
	var grid := BuildGrid.new(SITE.grid_size, SITE.grid_origin)
	var floor: Array[BuildEdit] = []
	for y in range(112, 126):
		for x in range(18, 67):
			floor.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(floor)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(24, 125), 2)
	PassengerTestWorld.place(grid, &"exit_door", EXIT, 0)
	_row_1 = PassengerTestWorld.place(grid, &"seat_row", ROW_1, 0)
	_row_2 = PassengerTestWorld.place(grid, &"seat_row", ROW_2, 0)
	EnclosureKit.close_floor(grid)
	var starts := PassengerTestWorld.starts_with(3000, 3300)
	_world = PassengerTestWorld.make(grid, starts)
	_world.sim.site = SITE
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(grid, _world.flights)
	_desk_1 = PassengerTestWorld.place(grid, GateDesks.DESK, DESK_1, 0)
	# The newer desk, closer to the exit, finds the exit taken and stays unbound.
	if desk_2_first:
		_desk_2 = PassengerTestWorld.place(grid, GateDesks.DESK, DESK_2, 0)
	_apron = auto_free(ApronStand.new()) as ApronStand
	_apron.passengers = _world.sim
	_apron.bind(grid, SITE, _world.flights, _gates)
	if not desk_2_first:
		_desk_2 = PassengerTestWorld.place(grid, GateDesks.DESK, DESK_2, 0)
	assert_bool(_world.flights.add_flight(FLIGHT, starts, "A")).is_true()
	_world.sim.standing.rebuild(_world.sim)


func test_a_gate_waits_by_its_bound_desk_when_the_closer_desk_stood_before_the_stands() -> void:
	_build(true)
	_check_waits_by_the_bound_desk()


func test_a_gate_waits_by_its_bound_desk_when_the_closer_desk_comes_after() -> void:
	_build(false)
	_check_waits_by_the_bound_desk()


func _check_waits_by_the_bound_desk() -> void:
	var binding := _gates.binding_of("A")
	var reach_1 := GateDesks.reach_cells(
		_world.grid, GateDesks.desk_footprint(_world.grid, _desk_1), binding["exit"]
	)
	var reach_2 := GateDesks.reach_cells(
		_world.grid, GateDesks.desk_footprint(_world.grid, _desk_2), binding["exit"]
	)
	print(
		(
			"A is bound to desk %d (exit %d); D1 is %d cells from the exit, D2 (unbound) %d"
			% [binding["desk"], binding["exit"], reach_1, reach_2]
		)
	)
	assert_int(binding["desk"]).is_equal(_desk_1)
	assert_int(reach_2).is_less(reach_1)
	var p := _world.passenger(_world.sim.spawn_now(FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _world.clock.tick + 1
	p.at = MIDDLE
	p.clear_path()
	p.apron = []
	p.apron_mm = 0
	var limit := _world.clock.tick + 1000
	while p.stage != Passenger.Stage.SEATED and _world.clock.tick < limit:
		_world.step()
	print("sits on object %d (D1's row %d, D2's row %d)" % [p.seat_object, _row_1, _row_2])
	assert_int(_world.sim.layout.gate_desk_ids["A"]).is_equal(_desk_1)
	assert_int(p.seat_object).is_equal(_row_1)


func test_a_version_15_passenger_save_is_refused() -> void:
	_build(true)
	assert_int(PassengerSim.SAVE_VERSION).is_equal(23)
	# A grid edit settles on the next tick; a save waits for it.
	_world.step()
	var old: Dictionary = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))
	old["save_version"] = 15
	var before := _world.signature()
	assert_bool(_world.sim.from_snapshot(old)).is_false()
	assert_str(_world.signature()).is_equal(before)
	var current: Dictionary = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))
	assert_int(int(current["save_version"])).is_equal(23)
