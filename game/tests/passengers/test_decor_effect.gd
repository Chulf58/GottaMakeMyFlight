class_name TestDecorEffect
extends GdUnitTestSuite
## Decor calms the passengers near it (decision furniture-set-modelled-on-
## copenhagen-airport-decor-calms-pas): a passenger inside a piece's radius
## gains mood slowly, a passenger outside gains nothing, the total is capped,
## the bin, posts and chain give no calm, and the covered cells follow the
## grid when decor is placed or removed.

const SIZE := Vector2i(30, 20)
const GUEST_CELL := Vector2i(12, 8)
## Two rows north of GUEST_CELL.
const STATUE_CELL := Vector2i(12, 6)
const BOARDING := 5000
const DOORS := 6000
const START_MOOD := 50
## A multiple of DecorEffect.PERIOD_BEATS, so a run pays an exact number of points.
const BEATS := 30

var _world: PassengerTestWorld
var _extra: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_world = _make_world()


func after_test() -> void:
	_world.free_all()
	_world = null
	for world in _extra:
		world.free_all()
	_extra.clear()


func _make_world() -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(SIZE)
	PassengerTestWorld.place(grid, &"exit_door", Vector2i(2, 0), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, 19), 2)
	PassengerTestWorld.place(grid, &"seat_row", Vector2i(3, 14), 0)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(BOARDING, DOORS))
	world.sim.apron_waypoints = PackedVector3Array()
	world.run_to(10)
	return world


func _decor(def_id: StringName, cell: Vector2i, world := _world, facing := 0) -> int:
	return PassengerTestWorld.place(world.grid, def_id, cell, facing)


## A calm cleared passenger standing at `cell` with START_MOOD.
func _guest(cell := GUEST_CELL, world := _world) -> Passenger:
	var p := world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 0
	p.liquids = false
	p.alarm = false
	p.cleared = true
	p.stage = Passenger.Stage.STANDING
	p.stage_tick = world.clock.tick
	p.at = cell
	p.clear_path()
	p.mood = START_MOOD
	return p


## Steps `world` over `p`'s next `beats` beats.
func _run_beats(p: Passenger, beats: int, world := _world) -> void:
	for i in beats:
		var t := world.clock.tick + 1
		while posmod(t, PassengerSim.BEAT_TICKS) != posmod(p.id, PassengerSim.BEAT_TICKS):
			t += 1
		world.run_to(t)


## Like _run_beats, with every need held at 0: a long run would bore or starve the guest, and a
## needy passenger loses mood, which is not what these cases measure.
func _run_unbored(p: Passenger, beats: int, world := _world) -> void:
	for i in beats:
		ToiletTestLayout.calm(p)
		_run_beats(p, 1, world)


## The mood of a guest at GUEST_CELL after BEATS beats in a fresh world, with
## `def_id` at STATUE_CELL or, for an empty id, nothing there.
func _mood_after(def_id: StringName) -> int:
	var world := _make_world()
	_extra.append(world)
	if def_id != &"":
		_decor(def_id, STATUE_CELL, world)
	var p := _guest(GUEST_CELL, world)
	_run_beats(p, BEATS, world)
	return p.mood


func test_a_control_run_without_decor_ends_lower_than_one_with_decor_in_range() -> void:
	var control := _mood_after(&"")
	var with_decor := _mood_after(&"statue_indoor")
	print(
		"mood after %d beats: control %d, with a statue in range %d" % [BEATS, control, with_decor]
	)
	assert_int(control).is_equal(START_MOOD)
	assert_int(with_decor).is_greater(control)
	assert_int(with_decor).is_equal(
		START_MOOD + DecorEffect.calm_of(&"statue_indoor") * BEATS / DecorEffect.PERIOD_BEATS
	)


func test_a_passenger_outside_the_radius_gets_nothing() -> void:
	_decor(&"statue_indoor", STATUE_CELL)
	var radius := DecorEffect.radius_of(&"statue_indoor")
	var edge := STATUE_CELL + Vector2i(0, radius)
	var beyond := STATUE_CELL + Vector2i(0, radius + 1)
	var near := _guest(edge)
	var far := _guest(beyond)
	_run_beats(near, BEATS)
	print("radius %d: at %s mood %d, at %s mood %d" % [radius, edge, near.mood, beyond, far.mood])
	assert_int(near.mood).is_greater(START_MOOD)
	assert_int(far.mood).is_equal(START_MOOD)
	assert_int(_world.sim.decor.calm_at(beyond)).is_equal(0)


func test_the_radius_counts_from_the_edge_of_a_big_footprint() -> void:
	# The 4x4 tree bench: radius 2 from its nearest cell, not from its anchor.
	var anchor := Vector2i(10, 2)
	_decor(&"bench_2a_indoor", anchor)
	var radius := DecorEffect.radius_of(&"bench_2a_indoor")
	var inside := Vector2i(anchor.x + 3, anchor.y + 3 + radius)
	var outside := Vector2i(anchor.x + 3, anchor.y + 3 + radius + 1)
	assert_int(_world.sim.decor.calm_at(inside)).is_greater(0)
	assert_int(_world.sim.decor.calm_at(outside)).is_equal(0)


func test_the_bonus_is_capped_however_much_decor_is_in_range() -> void:
	for i in 4:
		_decor(&"fountain_indoor", Vector2i(10 + 3 * i, 5))
	var p := _guest(Vector2i(12, 8))
	var summed := _world.sim.decor.calm_at(p.at)
	_run_beats(p, BEATS)
	print(
		"summed calm %d, cap %d, mood %d -> %d" % [summed, DecorEffect.MAX_CALM, START_MOOD, p.mood]
	)
	assert_int(summed).is_greater(DecorEffect.MAX_CALM)
	assert_int(p.mood).is_equal(
		START_MOOD + DecorEffect.MAX_CALM * BEATS / DecorEffect.PERIOD_BEATS
	)


func test_decor_never_lifts_mood_above_the_ceiling() -> void:
	for i in 2:
		_decor(&"fountain_indoor", Vector2i(10 + 3 * i, 5))
	var below := _guest(Vector2i(12, 8))
	var above := _guest(Vector2i(13, 8))
	below.mood = DecorEffect.CEILING - 3
	above.mood = DecorEffect.CEILING + 5
	for i in 60:
		ToiletTestLayout.calm(above)
		_run_unbored(below, 1)
	print(
		(
			"ceiling %d: %d -> %d, %d stays %d"
			% [
				DecorEffect.CEILING,
				DecorEffect.CEILING - 3,
				below.mood,
				DecorEffect.CEILING + 5,
				above.mood
			]
		)
	)
	assert_int(below.mood).is_equal(DecorEffect.CEILING)
	assert_int(above.mood).is_equal(DecorEffect.CEILING + 5)


func test_the_bin_the_posts_and_the_chain_give_no_calm() -> void:
	_decor(&"trash_can", GUEST_CELL + Vector2i(0, -1))
	_decor(&"metal_pole", GUEST_CELL + Vector2i(1, 0))
	# The 1x3 chain, running along y from (11, 6) to (11, 8), beside the guest.
	_decor(&"metal_pole_chain", GUEST_CELL + Vector2i(-1, -2))
	var p := _guest()
	assert_int(_world.sim.decor.calm_at(p.at)).is_equal(0)
	_run_beats(p, BEATS)
	print("bin, post and chain beside the guest: mood %d -> %d" % [START_MOOD, p.mood])
	# Changed with the back-of-house view penalty: the bin in view now drains
	# 1 point per period (BackOfHouseView); the posts and the chain give and
	# take nothing.
	assert_int(p.mood).is_equal(START_MOOD - BEATS / DecorEffect.PERIOD_BEATS)
	assert_dict(_world.sim.decor.cells()).is_empty()


func test_every_decor_piece_with_a_calm_value_calms_the_cell_beside_it() -> void:
	for def_id: StringName in DecorEffect.TABLE:
		var world := _make_world()
		_extra.append(world)
		var def := BuildCatalog.get_def(def_id)
		assert_object(def).is_not_null()
		var anchor := Vector2i(12, 6)
		_decor(def_id, anchor, world)
		# One cell east of the footprint's east edge, level with its first row.
		var beside := Vector2i(anchor.x + def.size.x, anchor.y)
		var calm := world.sim.decor.calm_at(beside)
		print("%s beside it: calm %d" % [def_id, calm])
		assert_int(calm).is_equal(DecorEffect.calm_of(def_id))


func test_coverage_follows_placing_and_removing_decor() -> void:
	var decor := _world.sim.decor
	assert_int(decor.calm_at(GUEST_CELL)).is_equal(0)
	var statue := _decor(&"statue_indoor", STATUE_CELL)
	assert_int(decor.calm_at(GUEST_CELL)).is_equal(DecorEffect.calm_of(&"statue_indoor"))
	var p := _guest()
	_run_unbored(p, BEATS)
	var with_statue := p.mood
	assert_bool(_world.grid.apply(BuildEdit.remove_object(statue)).ok).is_true()
	assert_int(decor.calm_at(GUEST_CELL)).is_equal(0)
	_run_unbored(p, BEATS)
	print(
		(
			"mood with the statue %d, after removing it and %d more beats %d"
			% [with_statue, BEATS, p.mood]
		)
	)
	assert_int(with_statue).is_greater(START_MOOD)
	assert_int(p.mood).is_equal(with_statue)


func test_a_plain_wall_between_the_piece_and_the_passenger_blocks_it() -> void:
	_decor(&"statue_indoor", STATUE_CELL)
	var decor := _world.sim.decor
	assert_int(decor.calm_at(GUEST_CELL)).is_greater(0)
	var wall := BuildEdit.place_wall(STATUE_CELL + Vector2i(0, 1), BuildGrid.Side.SOUTH)
	assert_bool(_world.grid.apply(wall).ok).is_true()
	assert_int(decor.calm_at(GUEST_CELL)).is_equal(0)
	# Glass lets it through.
	var glass := BuildEdit.place_wall(
		STATUE_CELL + Vector2i(0, 1), BuildGrid.Side.SOUTH, BuildGrid.WallKind.GLASS
	)
	var replaced := _world.grid.apply(glass)
	print(
		(
			"glass over the plain wall accepted: %s, calm now %d"
			% [replaced.ok, decor.calm_at(GUEST_CELL)]
		)
	)
	if replaced.ok:
		assert_int(decor.calm_at(GUEST_CELL)).is_greater(0)


func test_calm_is_paid_out_evenly_each_period() -> void:
	for calm in range(1, DecorEffect.MAX_CALM + 1):
		var paid := 0
		var longest_gap := 0
		var gap := 0
		for beat in range(1, DecorEffect.PERIOD_BEATS + 1):
			var due := DecorEffect.due(calm, beat)
			paid += due
			gap = 0 if due > 0 else gap + 1
			longest_gap = maxi(longest_gap, gap)
		assert_int(paid).is_equal(calm)
		# Spread, not bunched: no wait longer than the period divided by the points.
		assert_int(longest_gap).is_less_equal(DecorEffect.PERIOD_BEATS / calm)
	assert_int(DecorEffect.capped(99)).is_equal(DecorEffect.MAX_CALM)
	assert_int(DecorEffect.capped(-3)).is_equal(0)


func test_only_passengers_inside_the_terminal_are_calmed() -> void:
	_decor(&"statue_indoor", STATUE_CELL)
	# Beat number 5 pays one point of a calm of 2 (see due()).
	_world.sim.tick = 5 * PassengerSim.BEAT_TICKS
	assert_int(DecorEffect.due(DecorEffect.calm_of(&"statue_indoor"), 5)).is_equal(1)
	var calmed: Array[Passenger.Stage] = []
	var p := Passenger.new()
	p.at = GUEST_CELL
	for stage: Passenger.Stage in Passenger.Stage.values():
		p.stage = stage
		p.mood = START_MOOD
		_world.sim.decor.beat(p)
		if p.mood > START_MOOD:
			calmed.append(stage)
	var away := DecorEffect.AWAY_STAGES
	print("calmed in %d of %d stages; away: %s" % [calmed.size(), Passenger.Stage.size(), away])
	assert_int(calmed.size()).is_equal(Passenger.Stage.size() - away.size())
	for stage in away:
		assert_array(calmed).not_contains([stage])


func test_a_seated_passenger_is_calmed_at_its_chair() -> void:
	_decor(&"statue_indoor", STATUE_CELL)
	_world.sim.tick = 5 * PassengerSim.BEAT_TICKS
	var p := Passenger.new()
	p.stage = Passenger.Stage.SEATED
	p.at = Vector2i(1, 1)
	p.seat_cell = GUEST_CELL
	p.mood = START_MOOD
	_world.sim.decor.beat(p)
	assert_int(p.mood).is_equal(START_MOOD + 1)
	p.seat_cell = Vector2i(1, 1)
	p.mood = START_MOOD
	_world.sim.decor.beat(p)
	assert_int(p.mood).is_equal(START_MOOD)
