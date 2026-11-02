class_name TestGateSeatChoice
extends GdUnitTestSuite
## Passengers wait near their own flight's gate (user ruling 342df92a: they sit
## on the gate seats closest to their flight's gate desk, and with no seats near
## the gate they stand and get less calm): a gate B passenger takes B's seat
## even when A's is nearer its entry, stands near B when B's seats are full,
## and loses mood standing where a seated one gains it.
##
## The terminal is test_passenger_gate_exits' (two gates 44 m apart, entrance at
## the south-west), with a row of three seats south of each gate desk.

const SITE := preload("res://build/terminal_site.tres")
const EXIT_A := Vector2i(20, 112)
const EXIT_B := Vector2i(64, 112)
const ENTRANCE := Vector2i(24, 125)
## Beside the entrance and gate A's seats, 40 m from gate B's.
const ENTRY_SIDE := Vector2i(24, 122)
const FLIGHT_A := "TO_A"
const FLIGHT_B := "TO_B"

var _world: PassengerTestWorld
var _gates: GateDesks
var _apron: ApronStand
var _row_a := 0
var _row_b := 0
var _desk_b: Array[Vector2i] = []


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
	PassengerTestWorld.place(grid, &"exit_door", EXIT_A, 0)
	PassengerTestWorld.place(grid, &"exit_door", EXIT_B, 0)
	_row_a = PassengerTestWorld.place(grid, &"seat_row", EXIT_A + Vector2i(-1, 4), 0)
	_row_b = PassengerTestWorld.place(grid, &"seat_row", EXIT_B + Vector2i(-1, 4), 0)
	EnclosureKit.close_floor(grid)
	var starts := PassengerTestWorld.starts_with(3000, 3300)
	_world = PassengerTestWorld.make(grid, starts)
	_world.sim.site = SITE
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(grid, _world.flights)
	PassengerTestWorld.place(grid, GateDesks.DESK, EXIT_A + Vector2i(-1, 2), 0)
	var desk_b := PassengerTestWorld.place(grid, GateDesks.DESK, EXIT_B + Vector2i(-1, 2), 0)
	_desk_b = GateDesks.desk_footprint(grid, desk_b)
	_apron = auto_free(ApronStand.new()) as ApronStand
	_apron.passengers = _world.sim
	_apron.bind(grid, SITE, _world.flights, _gates)
	assert_bool(_world.flights.add_flight(FLIGHT_A, starts, "A")).is_true()
	assert_bool(_world.flights.add_flight(FLIGHT_B, starts, "B")).is_true()
	_world.sim.standing.rebuild(_world.sim)


## A calm, cleared passenger of `flight` on its way to the gate from `cell`.
func _at_gate(flight: String, cell := ENTRY_SIDE) -> Passenger:
	var p := _world.passenger(_world.sim.spawn_now(flight))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _world.clock.tick + 1
	p.at = cell
	p.clear_path()
	p.apron = []
	p.apron_mm = 0
	return p


## Steps until `p` is seated or standing, or 1000 ticks go by.
func _settle(p: Passenger) -> void:
	var limit := _world.clock.tick + 1000
	while (
		p.stage != Passenger.Stage.STANDING
		and p.stage != Passenger.Stage.SEATED
		and _world.clock.tick < limit
	):
		_world.step()


func _steps_from_b(p: Passenger) -> int:
	var spot := _world.sim.standing.spot_of(p.id)
	var cell := _world.sim.standing.cell_of(spot)
	var best := 1 << 30
	for desk_cell in _desk_b:
		best = mini(best, maxi(absi(cell.x - desk_cell.x), absi(cell.y - desk_cell.y)))
	return best


func test_a_gate_b_passenger_sits_at_bs_seats_though_as_are_nearer_its_entry() -> void:
	var b := _at_gate(FLIGHT_B)
	var a := _at_gate(FLIGHT_A)
	_settle(b)
	_settle(a)
	print("B sits on object %d (A's row %d, B's row %d)" % [b.seat_object, _row_a, _row_b])
	print("A sits on object %d" % a.seat_object)
	assert_int(b.seat_object).is_equal(_row_b)
	assert_int(a.seat_object).is_equal(_row_a)


func test_with_bs_seats_taken_a_b_passenger_stands_near_b_not_on_a_free_a_seat() -> void:
	var filler: Array[Passenger] = []
	for i in 3:
		filler.append(_at_gate(FLIGHT_B))
	for p in filler:
		_settle(p)
	var seated_at_b := filler.filter(func(p: Passenger) -> bool: return p.seat_object == _row_b)
	var extra := _at_gate(FLIGHT_B)
	_settle(extra)
	var near := _steps_from_b(extra)
	print(
		(
			"B seats taken %d, extra stage %s, steps from B's desk %s"
			% [seated_at_b.size(), Passenger.Stage.keys()[extra.stage], near]
		)
	)
	assert_int(seated_at_b.size()).is_equal(3)
	assert_int(extra.seat_object).is_equal(0)
	assert_int(extra.stage).is_equal(Passenger.Stage.STANDING)
	assert_int(near).is_less_equal(GateReach.NEAR_CELLS)


func test_standing_lowers_mood_against_a_seated_control() -> void:
	var seated: Array[Passenger] = []
	for i in 3:
		seated.append(_at_gate(FLIGHT_B))
	for p in seated:
		_settle(p)
	var standing := _at_gate(FLIGHT_B)
	_settle(standing)
	assert_int(standing.stage).is_equal(Passenger.Stage.STANDING)
	for p in seated + [standing]:
		p.mood = 60
	var until := _world.clock.tick + PassengerSim.BEAT_TICKS * 20
	while _world.clock.tick < until:
		_world.step()
	print("after 20 beats: seated %d, standing %d" % [seated[0].mood, standing.mood])
	assert_int(seated[0].stage).is_equal(Passenger.Stage.SEATED)
	assert_int(standing.stage).is_equal(Passenger.Stage.STANDING)
	assert_int(seated[0].mood).is_greater(60)
	assert_int(standing.mood).is_less(60)
