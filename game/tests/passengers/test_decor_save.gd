class_name TestDecorSave
extends GdUnitTestSuite
## Decor calm survives save and load without being saved (decision
## furniture-set-modelled-on-copenhagen-airport-decor-calms-pas): the covered
## cells come from the grid, so a world loaded from a save calms the same
## passengers by the same amount as the one that never stopped, and the
## passenger save holds nothing about decor.

const SIZE := Vector2i(30, 20)
const GUEST_CELL := Vector2i(12, 8)
const STATUE_CELL := Vector2i(12, 6)
const BOARDING := 5000
const DOORS := 6000
const START_MOOD := 50
const BEATS := 30

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


func _make(grid: BuildGrid) -> PassengerTestWorld:
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, DOORS), 7)
	world.sim.apron_waypoints = PackedVector3Array()
	return world


func _grid(with_statue: bool) -> BuildGrid:
	var grid := PassengerTestWorld.floored(SIZE)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(2, 0), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, 19), 2)
	# No gate seats: a standing passenger holding a spot takes a free seat on
	# its beat, and the guest must stay standing under the statue.
	if with_statue:
		PassengerTestWorld.place(grid, &"statue_indoor", STATUE_CELL, 0)
	return grid


func _guest(world: PassengerTestWorld) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.STANDING
	p.stage_tick = world.clock.tick
	p.at = GUEST_CELL
	p.clear_path()
	p.mood = START_MOOD
	# A standing passenger holds a standing spot on its cell; a version 14
	# save refuses one that does not (StandingSpots.checked()).
	var spots := world.sim.standing
	spots.rebuild(world.sim)
	for spot: int in spots.spots:
		if spots.cell_of(spot) == GUEST_CELL:
			spots.claim(p.id, spot)
			break
	assert_int(spots.spot_of(p.id)).is_not_equal(StandingSpots.NO_SPOT)
	return p


func _save(world: PassengerTestWorld) -> String:
	return (
		JSON
		. stringify(
			{
				"clock": world.clock.to_snapshot(),
				"flights": world.flights.to_snapshot(),
				"grid": world.grid.to_snapshot(),
				"passengers": world.sim.to_snapshot(),
			}
		)
	)


func _load(text: String) -> PassengerTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := _make(grid)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	return world


func test_a_loaded_world_calms_like_the_one_that_never_stopped() -> void:
	_a = _make(_grid(true))
	var guest := _guest(_a)
	_a.run_to(_a.clock.tick + 7 * PassengerSim.BEAT_TICKS)
	var saved := guest.mood
	_b = _load(_save(_a))
	var twin := _b.passenger(guest.id)
	assert_int(twin.mood).is_equal(saved)
	assert_int(_b.sim.decor.calm_at(GUEST_CELL)).is_equal(DecorEffect.calm_of(&"statue_indoor"))
	var end := _a.clock.tick + BEATS * PassengerSim.BEAT_TICKS
	_a.run_to(end)
	_b.run_to(end)
	print(
		(
			"mood %d at the save; after %d more beats: never stopped %d, loaded %d"
			% [saved, BEATS, guest.mood, twin.mood]
		)
	)
	assert_int(guest.mood).is_greater(saved)
	assert_int(twin.mood).is_equal(guest.mood)
	assert_str(_b.signature()).is_equal(_a.signature())


func test_a_save_without_decor_loads_into_a_world_that_has_none() -> void:
	# The control: the same save path, no decor on the grid, no calm.
	_a = _make(_grid(false))
	var guest := _guest(_a)
	_a.run_to(_a.clock.tick + 7 * PassengerSim.BEAT_TICKS)
	var saved := guest.mood
	_b = _load(_save(_a))
	var twin := _b.passenger(guest.id)
	_b.run_to(_b.clock.tick + BEATS * PassengerSim.BEAT_TICKS)
	print("control: mood %d at the save, %d after %d more beats" % [saved, twin.mood, BEATS])
	assert_int(_b.sim.decor.calm_at(GUEST_CELL)).is_equal(0)
	assert_int(twin.mood).is_equal(saved)


func test_the_passenger_save_holds_nothing_about_decor() -> void:
	_a = _make(_grid(true))
	_guest(_a)
	_a.run_to(_a.clock.tick + 5 * PassengerSim.BEAT_TICKS)
	var text := JSON.stringify(_a.sim.to_snapshot())
	assert_bool(text.contains("decor")).is_false()
	assert_bool(text.contains("calm")).is_false()
