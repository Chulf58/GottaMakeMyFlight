class_name TestHoldLineSaturation
extends GdUnitTestSuite
## Every security line full (decision full-queue-design-a-derived-hold-line-
## behind-each-lane-gives): a passenger done at check-in stays on the desk
## cell as its occupant, the desk pauses and its next front does not step
## onto that cell; once a security place frees, the passenger that has waited
## longest takes it and its desk goes on.

## The scanner's front never finds a gate place (no exit door, so no
## standing spot): its line stays full until a member leaves.
const SCANNER_AT := Vector2i(10, 8)
const DESK_A := Vector2i(2, 2)
const DESK_B := Vector2i(5, 2)
## Both desks held: [desk meta, occupant meta].
const BOTH_HELD := [[&"a", &"x"], [&"b", &"y"]]

var _world: PassengerTestWorld
var _other: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_world, _other]:
		if world != null:
			world.free_all()
	_world = null
	_other = null


## Two desks and a basic scanner whose 18-cell line (lane (10, 10) to
## (10, 15), then the hold line) is full. X is done at desk A in 5 ticks with
## Z behind it, Y at desk B in 15. Metas: "scanner", "a", "b", "x", "y", "z".
static func _full_world() -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(Vector2i(14, 16))
	var a := PassengerTestWorld.place(grid, &"checkin_desk", DESK_A, 0)
	var b := PassengerTestWorld.place(grid, &"checkin_desk", DESK_B, 0)
	var scanner := PassengerTestWorld.place(grid, &"security_scanner", SCANNER_AT, 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(7, 15), 2)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	var sim := world.sim
	for i in sim.layout.line_of(scanner).size():
		HoldLineKit.member(world, scanner)
	var x := HoldLineKit.member(world, a)
	var z := HoldLineKit.member(world, a)
	var y := HoldLineKit.member(world, b)
	x.service_end = sim.tick + 5
	y.service_end = sim.tick + 15
	for pair in [["scanner", scanner], ["a", a], ["b", b], ["x", x.id], ["y", y.id], ["z", z.id]]:
		sim.set_meta(pair[0], pair[1])
	return world


static func _p(world: PassengerTestWorld, key: StringName) -> Passenger:
	return world.passenger(world.sim.get_meta(key))


## Steps `ticks` ticks; fails when anyone but its occupant stands still on
## the cell of a held desk, `held` pairs of [desk meta, occupant meta] (a
## walker passing through is not stopped there).
func _play_held(world: PassengerTestWorld, ticks: int, held := BOTH_HELD) -> void:
	var sim := world.sim
	for i in ticks:
		world.step()
		for pair: Array in held:
			var cell: Vector2i = sim.layout.lanes[sim.get_meta(pair[0])][0]
			for id in sim.passenger_ids():
				var p := sim.get_passenger(id)
				if p.at == cell and not p.is_moving() and id != sim.get_meta(pair[1]):
					fail("t%d passenger %d stands on desk cell %s" % [sim.tick, id, cell])
					return


## Frees one security place: the line's last member gives up and leaves.
static func _free_place(world: PassengerTestWorld) -> void:
	var scanner: int = world.sim.get_meta(&"scanner")
	var members := world.sim.queue_of(scanner) + world.sim.holding_of(scanner)
	var gone := world.passenger(members.back())
	world.sim._leave_station(gone)
	gone.stage = Passenger.Stage.TO_GATE


func test_a_passenger_done_at_check_in_waits_on_the_desk_while_security_is_full() -> void:
	_world = _full_world()
	var sim := _world.sim
	var scanner: int = sim.get_meta(&"scanner")
	assert_int(sim.layout.line_of(scanner).size()).is_equal(18)
	_play_held(_world, 40)
	var x := _p(_world, &"x")
	var y := _p(_world, &"y")
	var z := _p(_world, &"z")
	var a_cells: Array = sim.layout.lanes[sim.get_meta(&"a")]
	assert_int(x.stage).is_equal(Passenger.Stage.CHECKIN)
	assert_int(y.stage).is_equal(Passenger.Stage.CHECKIN)
	assert_that(x.at).is_equal(a_cells[0])
	assert_that(z.at).is_equal(a_cells[1])
	assert_int(z.stage).is_equal(Passenger.Stage.CHECKIN_QUEUE)
	assert_int(sim.queue_of(sim.get_meta(&"a"))[0]).is_equal(x.id)
	# One place frees: X, done first, takes it; Y, done later, waits on.
	_free_place(_world)
	var freed := sim.tick
	while x.stage == Passenger.Stage.CHECKIN and sim.tick < freed + 2:
		_world.step()
	print("X left desk A %d ticks after the place freed" % (sim.tick - freed))
	assert_int(x.stage).is_equal(Passenger.Stage.TO_SECURITY)
	assert_int(x.station).is_equal(scanner)
	_play_held(_world, 30, [[&"b", &"y"]])
	assert_int(y.stage).is_equal(Passenger.Stage.CHECKIN)
	assert_int(y.station).is_equal(sim.get_meta(&"b"))
	# Desk A goes on: Z steps up and is served.
	assert_int(z.stage).is_equal(Passenger.Stage.CHECKIN)
	assert_that(z.at).is_equal(a_cells[0])


func test_a_save_while_held_at_the_desk_plays_on_exactly() -> void:
	_world = _full_world()
	_play_held(_world, 30)
	assert_int(_p(_world, &"x").stage).is_equal(Passenger.Stage.CHECKIN)
	var data := {
		"clock": _world.clock.to_snapshot(),
		"flights": _world.flights.to_snapshot(),
		"grid": _world.grid.to_snapshot(),
		"passengers": _world.sim.to_snapshot(),
	}
	assert_int(int(data["passengers"]["save_version"])).is_equal(33)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	_other = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(_other.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(_other.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(_other.sim.from_snapshot(data["passengers"])).is_true()
	for key in [&"scanner", &"a", &"b", &"x", &"y", &"z"]:
		_other.sim.set_meta(key, _world.sim.get_meta(key))
	assert_str(_other.signature()).is_equal(_world.signature())
	for i in 200:
		if i == 20:
			_free_place(_world)
			_free_place(_other)
		_world.step()
		_other.step()
		assert_str(_other.signature()).is_equal(_world.signature())
	assert_int(_p(_other, &"x").stage).is_not_equal(Passenger.Stage.CHECKIN)
	# A save of the version before is refused (no migration before a release).
	var old: Dictionary = data["passengers"].duplicate(true)
	old["save_version"] = 26
	assert_bool(_other.sim.from_snapshot(old)).is_false()
