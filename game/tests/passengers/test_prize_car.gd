class_name TestPrizeCar
extends GdUnitTestSuite
## The prize car's reach and its lookers (F4-4; decision furniture-set-modelled-
## on-copenhagen-airport-decor-calms-pas, point 2): the podium reaches floor
## cells within SPEND_RADIUS of its footprint that it can be seen from, follows
## the grid's edits and does not stack; a looker waiting within LOOK_RADIUS of
## it loses boredom where a non-looker, or a looker out of that radius, gains it.

const SIZE := Vector2i(30, 20)
## The 6x3 podium: x 12-17, y 6-8.
const PODIUM_CELL := Vector2i(12, 6)
const BOARDING := 5000
const DOORS := 6000
const START_BOREDOM := 60
## An even number of beats, so the half-rate drop pays an exact count.
const BEATS := 20
const S := BuildGrid.Side

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(SIZE)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(2, 0), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, 19), 2)
	PassengerTestWorld.place(grid, &"seat_row", Vector2i(3, 14), 0)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, DOORS))
	_world.sim.apron_waypoints = PackedVector3Array()
	_world.run_to(10)


func after_test() -> void:
	_world.free_all()
	_world = null


func _prize() -> PrizeCar:
	return _world.sim.boredom.prize


func _podium(cell := PODIUM_CELL) -> int:
	return PassengerTestWorld.place(_world.grid, PrizeCar.PODIUM_ID, cell, 0)


## A waiting cleared passenger standing at `cell`, `START_BOREDOM` bored, with
## no other need: a looker or not, as asked.
func _guest(cell: Vector2i, looker: bool) -> Passenger:
	var p: Passenger = null
	while p == null or PrizeCar.is_looker(p) != looker:
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.STANDING
	p.stage_tick = _world.clock.tick
	p.at = cell
	p.clear_path()
	p.boredom = START_BOREDOM
	return p


## Steps the world over `beats` simulated seconds: every passenger beats that
## many times, and exactly half of those seconds are even.
func _run_beats(beats: int) -> void:
	_world.run_to(_world.clock.tick + beats * PassengerSim.BEAT_TICKS)


func test_the_podium_is_a_priced_6_by_3_piece_with_a_daily_running_cost() -> void:
	var def := BuildCatalog.get_def(PrizeCar.PODIUM_ID)
	assert_object(def).is_not_null()
	assert_vector(Vector2(def.size)).is_equal(Vector2(6, 3))
	assert_int(PriceTable.price_of_object(PrizeCar.PODIUM_ID)).is_greater(0)
	assert_int(PriceTable.PRIZE_CAR_UPKEEP).is_greater(PriceTable.SCREEN_UPKEEP)


func test_the_boost_is_20_percent_rounded_half_up() -> void:
	assert_int(PrizeCar.SPEND_BONUS_PERCENT).is_equal(20)
	assert_int(PrizeCar.boosted(0)).is_equal(0)
	assert_int(PrizeCar.boosted(10)).is_equal(12)
	assert_int(PrizeCar.boosted(16)).is_equal(19)
	assert_int(PrizeCar.boosted(20)).is_equal(24)
	assert_int(PrizeCar.boosted(23)).is_equal(28)
	assert_int(PrizeCar.boosted(22)).is_equal(26)


func test_reach_counts_from_the_edge_of_the_footprint_and_stops_at_the_radius() -> void:
	_podium()
	var bottom := PODIUM_CELL.y + 2
	var inside := Vector2i(14, bottom + PrizeCar.SPEND_RADIUS)
	var outside := Vector2i(14, bottom + PrizeCar.SPEND_RADIUS + 1)
	var corner := Vector2i(17 + PrizeCar.SPEND_RADIUS, bottom + PrizeCar.SPEND_RADIUS)
	print(
		(
			"reach: %d at %s, %d at %s"
			% [_prize().distance_at(inside), inside, _prize().distance_at(outside), outside]
		)
	)
	assert_int(_prize().distance_at(inside)).is_equal(PrizeCar.SPEND_RADIUS)
	assert_int(_prize().distance_at(outside)).is_equal(PrizeCar.NO_REACH)
	assert_int(_prize().distance_at(corner)).is_equal(PrizeCar.SPEND_RADIUS)
	assert_int(_prize().distance_at(Vector2i(14, bottom + 1))).is_equal(1)
	# The podium's own cells are not reached.
	assert_int(_prize().distance_at(Vector2i(14, 7))).is_equal(PrizeCar.NO_REACH)


func test_a_plain_wall_blocks_the_view_and_glass_does_not() -> void:
	_podium()
	var behind := Vector2i(14, 12)
	assert_int(_prize().distance_at(behind)).is_equal(4)
	for x in range(10, 20):
		assert_bool(_world.grid.apply(BuildEdit.place_wall(Vector2i(x, 11), S.NORTH)).ok).is_true()
	assert_int(_prize().distance_at(behind)).is_equal(PrizeCar.NO_REACH)
	for x in range(10, 20):
		var glass := BuildEdit.place_wall(Vector2i(x, 11), S.NORTH, BuildGrid.WallKind.GLASS)
		assert_bool(_world.grid.apply(glass).ok).is_true()
	assert_int(_prize().distance_at(behind)).is_equal(4)


func test_reach_follows_the_grid_and_two_podiums_do_not_stack() -> void:
	var cell := Vector2i(14, 12)
	assert_int(_prize().distance_at(cell)).is_equal(PrizeCar.NO_REACH)
	var first := _podium()
	assert_int(_prize().distance_at(cell)).is_equal(4)
	_podium(Vector2i(12, 9))
	# The second stands right above the cell, 1 away: the nearer one counts.
	assert_int(_prize().distance_at(cell)).is_equal(1)
	assert_int(_prize().distance_at(Vector2i(14, 2))).is_equal(4)
	assert_bool(_world.grid.apply(BuildEdit.remove_object(first)).ok).is_true()
	assert_int(_prize().distance_at(Vector2i(14, 2))).is_equal(PrizeCar.NO_REACH)
	assert_int(_prize().distance_at(cell)).is_equal(1)


func test_a_looker_in_view_loses_boredom_and_a_non_looker_gains_it() -> void:
	_podium()
	var cell := Vector2i(14, 10)
	var looker := _guest(cell, true)
	var other := _guest(cell + Vector2i(1, 0), false)
	assert_bool(_prize().looks(looker)).is_true()
	assert_bool(_prize().looks(other)).is_false()
	_run_beats(BEATS)
	print("after %d beats: looker %d, non-looker %d" % [BEATS, looker.boredom, other.boredom])
	var expected_drop := BEATS / PrizeCar.LOOK_RELIEF_BEATS * PrizeCar.LOOK_RELIEF
	assert_int(looker.boredom).is_equal(START_BOREDOM - expected_drop)
	assert_int(other.boredom).is_equal(START_BOREDOM + BEATS * BoredomSim.RISE)


func test_a_looker_out_of_the_look_radius_or_without_a_car_gets_bored_as_usual() -> void:
	var near := _guest(Vector2i(14, 10), true)
	var far := _guest(Vector2i(14, 10 + PrizeCar.LOOK_RADIUS + 1), true)
	# No car yet: a control proving the looker is engaged only by the podium.
	_run_beats(BEATS)
	assert_int(near.boredom).is_equal(START_BOREDOM + BEATS)
	assert_int(far.boredom).is_equal(START_BOREDOM + BEATS)
	_podium()
	near.boredom = START_BOREDOM
	far.boredom = START_BOREDOM
	assert_int(_prize().distance_at(far.at)).is_between(
		PrizeCar.LOOK_RADIUS + 1, PrizeCar.SPEND_RADIUS
	)
	_run_beats(BEATS)
	print("with the car: near %d, %d cells out %d" % [near.boredom, far.at.y - 8, far.boredom])
	assert_int(near.boredom).is_less(START_BOREDOM)
	assert_int(far.boredom).is_equal(START_BOREDOM + BEATS)


func test_a_looker_who_is_not_waiting_does_not_look() -> void:
	_podium()
	var walker := _guest(Vector2i(14, 10), true)
	walker.stage = Passenger.Stage.TO_GATE
	assert_bool(_prize().looks(walker)).is_false()
	# Control: the same passenger in a queue does.
	walker.stage = Passenger.Stage.CAFE_QUEUE
	assert_bool(_prize().looks(walker)).is_true()
