class_name TestQueueRippleSave
extends GdUnitTestSuite
## Passenger.halt_tick in a save (PassengerSim version 24, QueueRipple): a
## save taken while a lane walker waits on the stood roller ahead plays on
## exactly like the world that never stopped, and a halt_tick below 0 or after
## the saved tick is refused (QueueRipple would hold the lane until then).

const DESK_AT := Vector2i(3, 1)
const SCANNER_AT := Vector2i(8, 6)
const PLAY_TICKS := 400

var _a: PassengerTestWorld
var _b: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_a, _b]:
		if world != null:
			world.free_all()
	_a = null
	_b = null


func _save(world: PassengerTestWorld) -> Dictionary:
	return {
		"clock": world.clock.to_snapshot(),
		"flights": world.flights.to_snapshot(),
		"grid": world.grid.to_snapshot(),
		"passengers": world.sim.to_snapshot(),
	}


func _load(data: Dictionary, loads := [true]) -> PassengerTestWorld:
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	loads[0] = world.sim.from_snapshot(data["passengers"])
	return world


## The signature plus every passenger's halt_tick.
static func _signature(world: PassengerTestWorld) -> String:
	var halts := PackedStringArray()
	for id in world.sim.passenger_ids():
		halts.append("%d:%d" % [id, world.passenger(id).halt_tick])
	return "%s#%s" % [world.signature(), ",".join(halts)]


## A desk world with four calm walkers pulling a roller each, stepped until a
## lane walker waits on the walker ahead, whose roller is being stood up (it
## stands on its place, still for under QueueRipple.STAND_TICKS). Returns the
## waiting walker's id, or 0.
func _mid_ripple() -> int:
	var grid := PassengerTestWorld.floored(Vector2i(12, 16))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(5, 15), 2)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(8, 0), 0)
	PassengerTestWorld.place(grid, &"checkin_desk", DESK_AT, 0)
	PassengerTestWorld.place(grid, &"security_scanner", SCANNER_AT, 0)
	_a = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(3000, 6000))
	var sent := 0
	for attempt in 50:
		if sent == 4:
			break
		var p := _a.passenger(_a.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.carry_on = 1
		# One with another bag checks in with none (a save keeps every passenger,
		# so none is settled by hand).
		var roller := QueueRipple.pulls_roller(p)
		if not roller:
			p.carry_on = 0
		p.hunger = 0
		p.liquids = false
		p.alarm = false
		p.apron = []
		p.apron_mm = 0
		p.stage = Passenger.Stage.TO_CHECKIN
		p.clear_path()
		sent += 1 if roller else 0
		_a.run_to(_a.clock.tick + 3)
	var desk: int = _a.sim.layout.desks[0]
	var cells: Array = _a.sim.layout.lanes[desk]
	for t in 2000:
		_a.step()
		var lane := _a.sim.queue_of(desk)
		for i in range(1, lane.size()):
			var p := _a.passenger(lane[i])
			var ahead := _a.passenger(lane[i - 1])
			var waits: bool = not p.is_moving() and p.at != cells[i]
			var stands: bool = not ahead.is_moving() and ahead.at == cells[i - 1]
			var young := _a.clock.tick - ahead.halt_tick < QueueRipple.STAND_TICKS
			if waits and stands and young and QueueRipple.pulls_roller(ahead):
				return p.id
	return 0


func test_a_save_mid_ripple_plays_on_exactly() -> void:
	var waiting := _mid_ripple()
	assert_int(waiting).is_greater(0)
	var saved_at := _a.clock.tick
	var loaded := [false]
	_b = _load(_save(_a), loaded)
	assert_bool(loaded[0]).is_true()
	assert_str(_signature(_b)).is_equal(_signature(_a))
	var set_off := {}
	for t in PLAY_TICKS:
		_a.step()
		_b.step()
		for w: PassengerTestWorld in [_a, _b]:
			if not set_off.has(w) and w.passenger(waiting).is_moving():
				set_off[w] = w.clock.tick
		if _signature(_a) != _signature(_b):
			fail("tick %d: the loaded world differs" % _a.clock.tick)
			return
	print("saved at %d; walker %d set off at %s" % [saved_at, waiting, set_off.values()])
	assert_int(set_off.size()).is_equal(2)
	assert_int(int(set_off[_b])).is_equal(int(set_off[_a]))
	assert_int(int(set_off[_a])).is_greater(saved_at)


func test_a_halt_tick_below_zero_or_after_the_saved_tick_is_refused() -> void:
	var waiting := _mid_ripple()
	assert_int(waiting).is_greater(0)
	var good := _save(_a)
	var saved := str(good["passengers"]["tick"]).to_int()
	var cases := {"after the saved tick": saved + 1, "below zero": -1, "the saved tick": saved}
	for name: String in cases:
		var data: Dictionary = good.duplicate(true)
		for record: Dictionary in data["passengers"]["passengers"]:
			if int(record["id"]) == waiting:
				record["halt_tick"] = cases[name]
		var loaded := [false]
		var world := _load(data, loaded)
		var loads: bool = loaded[0]
		print("halt_tick %s (%d): loads %s" % [name, cases[name], loads])
		# The saved tick itself is legal: the control that loads.
		assert_bool(loads).override_failure_message(name).is_equal(name == "the saved tick")
		world.free_all()
