class_name TestMessMood
extends GdUnitTestSuite
## A mess costs the mood of passengers who can see it (decision cleaner-staff-
## and-messes-visits-leave-messes-bins-fill-pooled-cleaners-nearest-mess, point
## 2): only within its radius and in sight, more once it is old, and never more
## than MessSim.MAX_DIRT per period however many are in view.

const MESS_CELL := Vector2i(15, 6)
## Two rows south of the mess.
const GUEST_CELL := Vector2i(15, 8)
## A multiple of DecorEffect.PERIOD_BEATS, so a run costs an exact number of points.
const BEATS := 30

## One world for the file; each case starts with no messes, measures fresh
## guests and puts back the grid edits it made (_undo). Guests of earlier cases
## stay standing where they were and are not read again.
var _world: PassengerTestWorld
var _undo: Array[BuildEdit] = []


func before() -> void:
	PassengerTestWorld.tracker = self
	_world = MessTestKit.open_world()


func after() -> void:
	_world.free_all()
	_world = null
	PassengerTestWorld.tracker = null


func before_test() -> void:
	assert_bool(MessTestKit.clear(_world)).is_true()


func after_test() -> void:
	MessTestKit.undo(_world, _undo)


func _messes() -> MessSim:
	return _world.sim.messes


## Mood points `dirt` costs over BEATS beats.
func _loss(dirt: int) -> int:
	return dirt * BEATS / DecorEffect.PERIOD_BEATS


func test_a_guest_in_range_and_in_sight_loses_mood_and_one_out_of_range_does_not() -> void:
	_messes().add(MessSim.Kind.SPILL, MESS_CELL)
	var near := MessTestKit.guest(_world, GUEST_CELL)
	var edge := MessTestKit.guest(_world, MESS_CELL + Vector2i(MessSim.RADIUS, 0))
	var beyond := MessTestKit.guest(_world, MESS_CELL + Vector2i(MessSim.RADIUS + 1, 0))
	var control := MessTestKit.guest(_world, Vector2i(5, 16))
	for i in BEATS:
		for p in [near, edge, beyond, control]:
			ToiletTestLayout.calm(p)
		MessTestKit.run_beats(_world, near, 1)
	print(
		(
			"after %d beats: near %d, at the radius %d, one past it %d, control %d"
			% [BEATS, near.mood, edge.mood, beyond.mood, control.mood]
		)
	)
	assert_int(control.mood).is_equal(MessTestKit.START_MOOD)
	assert_int(beyond.mood).is_equal(MessTestKit.START_MOOD)
	assert_int(near.mood).is_equal(MessTestKit.START_MOOD - _loss(MessSim.DIRT))
	assert_int(edge.mood).is_less(MessTestKit.START_MOOD)


func test_a_plain_wall_between_the_mess_and_the_guest_hides_it() -> void:
	_messes().add(MessSim.Kind.SPILL, MESS_CELL)
	assert_int(_messes().dirt_at(GUEST_CELL)).is_equal(MessSim.DIRT)
	var wall := BuildEdit.place_wall(MESS_CELL, BuildGrid.Side.SOUTH)
	assert_bool(_world.grid.apply(wall).ok).is_true()
	_undo.append(BuildEdit.remove_wall(MESS_CELL, BuildGrid.Side.SOUTH))
	var p := MessTestKit.guest(_world, GUEST_CELL)
	MessTestKit.run_beats(_world, p, BEATS)
	print("dirt behind the wall %d, mood %d" % [_messes().dirt_at(GUEST_CELL), p.mood])
	assert_int(_messes().dirt_at(GUEST_CELL)).is_equal(0)
	assert_int(p.mood).is_equal(MessTestKit.START_MOOD)


func test_an_old_mess_costs_more_than_a_fresh_one() -> void:
	_messes().add(MessSim.Kind.SPILL, MESS_CELL)
	var fresh := MessTestKit.guest(_world, GUEST_CELL)
	MessTestKit.run_beats(_world, fresh, BEATS)
	var fresh_loss := MessTestKit.START_MOOD - fresh.mood
	var aged_from := _world.clock.tick
	var born: int = _messes().get_mess(_messes().mess_ids()[0])["born_tick"]
	_world.run_to(born + MessSim.RAMP_TICKS)
	var aged := MessTestKit.guest(_world, GUEST_CELL + Vector2i(1, 0))
	MessTestKit.run_beats(_world, aged, BEATS)
	var aged_loss := MessTestKit.START_MOOD - aged.mood
	print(
		(
			"fresh loss %d over %d beats (from tick %d), aged loss %d (from tick %d)"
			% [fresh_loss, BEATS, born, aged_loss, aged_from]
		)
	)
	assert_int(fresh_loss).is_equal(_loss(MessSim.DIRT))
	assert_int(aged_loss).is_equal(_loss(MessSim.AGED_DIRT))
	assert_int(aged_loss).is_greater(fresh_loss)


func test_the_loss_is_capped_however_many_messes_are_in_view() -> void:
	for x in range(12, 19):
		_messes().add(MessSim.Kind.SPILL, Vector2i(x, MESS_CELL.y))
	var summed := _messes().dirt_at(GUEST_CELL)
	var p := MessTestKit.guest(_world, GUEST_CELL)
	MessTestKit.run_beats(_world, p, BEATS)
	print(
		(
			"summed dirt %d, cap %d, mood %d -> %d"
			% [summed, MessSim.MAX_DIRT, MessTestKit.START_MOOD, p.mood]
		)
	)
	assert_int(summed).is_greater(MessSim.MAX_DIRT)
	assert_int(p.mood).is_equal(MessTestKit.START_MOOD - _loss(MessSim.MAX_DIRT))


func test_a_passenger_not_yet_in_the_terminal_loses_nothing() -> void:
	_messes().add(MessSim.Kind.SPILL, MESS_CELL)
	var p := MessTestKit.guest(_world, GUEST_CELL)
	p.stage = Passenger.Stage.SPAWNED
	p.mood = MessTestKit.START_MOOD
	_messes().beat(p)
	assert_int(p.mood).is_equal(MessTestKit.START_MOOD)
