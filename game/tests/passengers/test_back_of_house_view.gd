class_name TestBackOfHouseView
extends GdUnitTestSuite
## A passenger who sees a bin or a bag room loses calm (decision back-of-house-
## view-penalty-bins-cost-1-calm-and-bag-rooms-2): a bin costs 1 and a bag room
## 2, subtracted from the decor calm before the MAX_CALM cap. A plain wall or a
## tall piece (tree, statue, tall planter) in the way hides it; glass and a short
## piece do not. Decor calm and screens see as before (test_decor_effect). Where the penalty
## outweighs the decor, mood drains at the same scale and period.

const SIZE := Vector2i(30, 20)
const GUEST_CELL := Vector2i(12, 8)
## Two rows north of GUEST_CELL: in the bin's reach, straight line of sight.
const BIN_CELL := Vector2i(12, 6)
## Two rows south of GUEST_CELL; a fountain's 2x2 footprint, so its calm reaches the guest.
const FOUNTAIN_CELL := Vector2i(12, 10)
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


func _decor(def_id: StringName, cell: Vector2i, world := _world) -> int:
	return PassengerTestWorld.place(world.grid, def_id, cell, 0)


func _guest(cell: Vector2i, world := _world) -> Passenger:
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


## The guest's mood after BEATS beats, every need held at 0 so only decor moves it.
func _run_beats(p: Passenger, world := _world) -> void:
	for i in BEATS:
		ToiletTestLayout.calm(p)
		var t := world.clock.tick + 1
		while posmod(t, PassengerSim.BEAT_TICKS) != posmod(p.id, PassengerSim.BEAT_TICKS):
			t += 1
		world.run_to(t)


## The mood after BEATS beats at GUEST_CELL in a fresh world holding `pieces`
## (def id -> anchor cell) and, if given, a bag room over `bag_room`.
func _mood_with(pieces: Dictionary, bag_room := Rect2i()) -> int:
	var world := _make_world()
	_extra.append(world)
	for def_id: StringName in pieces:
		_decor(def_id, pieces[def_id], world)
	if bag_room.has_area():
		assert_bool(world.grid.apply(BuildEdit.place_room(bag_room, &"bag_room")).ok).is_true()
	var p := _guest(GUEST_CELL, world)
	_run_beats(p, world)
	return p.mood


func _wall(cell: Vector2i, kind := BuildGrid.WallKind.PLAIN) -> void:
	var edit := BuildEdit.place_wall(cell, BuildGrid.Side.SOUTH, kind)
	assert_bool(_world.grid.apply(edit).ok).is_true()


func test_an_unscreened_bin_costs_a_point_of_calm() -> void:
	_decor(&"trash_can", BIN_CELL)
	_decor(&"fountain_indoor", FOUNTAIN_CELL)
	var decor := _world.sim.decor
	print(
		(
			"bin in view: calm %d, penalty %d, net %d"
			% [
				decor.calm_at(GUEST_CELL),
				decor.penalty_at(GUEST_CELL),
				decor.net_calm_at(GUEST_CELL)
			]
		)
	)
	assert_int(decor.penalty_at(GUEST_CELL)).is_equal(1)
	assert_int(decor.net_calm_at(GUEST_CELL)).is_equal(DecorEffect.calm_of(&"fountain_indoor") - 1)
	assert_int(decor.penalty_at(BIN_CELL + Vector2i(0, -3))).is_equal(0)


func test_a_bin_in_view_lowers_the_mood_gain_but_a_fountain_still_nets_positive() -> void:
	var fountain := DecorEffect.calm_of(&"fountain_indoor")
	var alone := _mood_with({&"fountain_indoor": FOUNTAIN_CELL})
	var with_bin := _mood_with({&"fountain_indoor": FOUNTAIN_CELL, &"trash_can": BIN_CELL})
	print("fountain alone %d, fountain and bin in view %d, from %d" % [alone, with_bin, START_MOOD])
	assert_int(alone).is_equal(START_MOOD + fountain * BEATS / DecorEffect.PERIOD_BEATS)
	assert_int(with_bin).is_equal(START_MOOD + (fountain - 1) * BEATS / DecorEffect.PERIOD_BEATS)
	assert_int(with_bin).is_greater(START_MOOD)


func test_a_bin_alone_lowers_mood_and_a_bag_room_alone_lowers_it_twice_as_much() -> void:
	var bin := _mood_with({&"trash_can": BIN_CELL})
	var bag_room := _mood_with({}, Rect2i(12, 5, 3, 2))
	print(
		(
			"mood from %d after %d beats: bin in view %d, bag room in view %d"
			% [START_MOOD, BEATS, bin, bag_room]
		)
	)
	assert_int(bin).is_equal(START_MOOD - BEATS / DecorEffect.PERIOD_BEATS)
	assert_int(bag_room).is_equal(START_MOOD - 2 * BEATS / DecorEffect.PERIOD_BEATS)
	assert_int(START_MOOD - bag_room).is_equal(2 * (START_MOOD - bin))


func test_a_bin_alone_has_negative_net_calm() -> void:
	_decor(&"trash_can", BIN_CELL)
	var decor := _world.sim.decor
	assert_int(decor.calm_at(GUEST_CELL)).is_equal(0)
	assert_int(decor.net_calm_at(GUEST_CELL)).is_equal(-1)


func test_a_screened_bin_alone_costs_no_mood() -> void:
	_wall(BIN_CELL + Vector2i(0, 1))
	_decor(&"trash_can", BIN_CELL)
	var p := _guest(GUEST_CELL)
	_run_beats(p)
	print("bin behind a wall: mood %d -> %d" % [START_MOOD, p.mood])
	assert_int(p.mood).is_equal(START_MOOD)


func test_the_drain_is_capped_and_mood_stops_at_zero() -> void:
	for i in 6:
		_decor(&"trash_can", Vector2i(11 + i % 3, 6 + i / 3))
	var decor := _world.sim.decor
	var p := _guest(GUEST_CELL)
	p.mood = 2
	var net := decor.net_calm_at(GUEST_CELL)
	_run_beats(p)
	print("net calm %d, mood 2 -> %d" % [net, p.mood])
	assert_int(net).is_less(-DecorEffect.MAX_CALM)
	assert_int(p.mood).is_equal(0)


func test_mood_above_the_ceiling_is_still_drained() -> void:
	_decor(&"trash_can", BIN_CELL)
	var p := _guest(GUEST_CELL)
	p.mood = DecorEffect.CEILING + 5
	_run_beats(p)
	print("mood %d -> %d" % [DecorEffect.CEILING + 5, p.mood])
	assert_int(p.mood).is_equal(DecorEffect.CEILING + 5 - BEATS / DecorEffect.PERIOD_BEATS)


func test_a_bin_behind_a_plain_wall_costs_nothing() -> void:
	_decor(&"trash_can", BIN_CELL)
	var decor := _world.sim.decor
	assert_int(decor.penalty_at(GUEST_CELL)).is_equal(1)
	_wall(BIN_CELL + Vector2i(0, 1))
	print("penalty at the guest after a wall between: %d" % decor.penalty_at(GUEST_CELL))
	assert_int(decor.penalty_at(GUEST_CELL)).is_equal(0)


func test_a_bin_behind_glass_still_costs() -> void:
	_decor(&"trash_can", BIN_CELL)
	_wall(BIN_CELL + Vector2i(0, 1), BuildGrid.WallKind.GLASS)
	var decor := _world.sim.decor
	print("penalty at the guest through glass: %d" % decor.penalty_at(GUEST_CELL))
	assert_int(decor.penalty_at(GUEST_CELL)).is_equal(1)


func test_a_bin_behind_a_tree_costs_nothing() -> void:
	# The 2x2 tree at (12, 6) covers (12..13, 6..7); the bin stands at (12, 5)
	# and the guest at (14, 7), the diagonal line crossing the tree's cell (13, 6).
	var bin := Vector2i(12, 5)
	var guest := Vector2i(14, 7)
	_decor(&"trash_can", bin)
	var decor := _world.sim.decor
	assert_int(decor.penalty_at(guest)).is_equal(1)
	_decor(&"tree_indoor", Vector2i(12, 6))
	print("penalty at %s with a tree between: %d" % [guest, decor.penalty_at(guest)])
	assert_int(decor.penalty_at(guest)).is_equal(0)


func test_each_tall_piece_hides_a_bin_and_each_short_one_does_not() -> void:
	for def_id: StringName in BackOfHouseView.TALL_IDS:
		var tall := _penalty_through(def_id)
		print("%s between the bin and the guest: penalty %d" % [def_id, tall])
		assert_int(tall).is_equal(0)
	for def_id: StringName in [&"bush", &"plant_pot_2a", &"fountain_indoor", &"bench_1a"]:
		var short := _penalty_through(def_id)
		print("%s between the bin and the guest: penalty %d" % [def_id, short])
		assert_int(short).is_equal(1)


## The penalty at a guest at (14, 7) from a bin at (12, 5) with `def_id` placed
## so its footprint covers (13, 6), the cell the diagonal line crosses, and
## neither end.
func _penalty_through(def_id: StringName) -> int:
	var world := _make_world()
	_extra.append(world)
	var def := BuildCatalog.get_def(def_id)
	_decor(&"trash_can", Vector2i(12, 5), world)
	_decor(def_id, Vector2i(14 - def.size.x, 6), world)
	return world.sim.decor.penalty_at(Vector2i(14, 7))


func test_a_large_bag_room_is_worked_out_in_one_pass_and_is_still_right() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(60, 60))
	var room := Rect2i(8, 8, 40, 40)
	assert_bool(grid.apply(BuildEdit.place_room(room, &"bag_room")).ok).is_true()
	var started := Time.get_ticks_msec()
	var seen := BackOfHouseView.penalties(grid)
	var elapsed := Time.get_ticks_msec() - started
	var ring := (40 + 2 * BackOfHouseView.REACH) * (40 + 2 * BackOfHouseView.REACH) - 40 * 40
	print("40x40 bag room: %d cells see it, worked out in %d ms" % [seen.size(), elapsed])
	# The work stays linear in the area scanned: every cell of the 44x44 area is
	# checked once against the room rectangle, and no room cell is ever listed.
	var scanned := (40 + 2 * BackOfHouseView.REACH) * (40 + 2 * BackOfHouseView.REACH)
	print(
		(
			"cells scanned %d, room cells listed %d"
			% [BackOfHouseView.cells_scanned, BackOfHouseView.cells_listed]
		)
	)
	assert_int(BackOfHouseView.cells_scanned).is_equal(scanned)
	assert_int(BackOfHouseView.cells_listed).is_equal(0)
	assert_int(seen.size()).is_equal(ring)
	assert_int(int(seen[Vector2i(7, 20)])).is_equal(2)
	assert_int(int(seen[Vector2i(6, 6)])).is_equal(2)
	assert_bool(seen.has(Vector2i(5, 20))).is_false()
	assert_bool(seen.has(Vector2i(20, 20))).is_false()


func test_a_bag_room_costs_two_and_only_outside_it_within_reach() -> void:
	var decor := _world.sim.decor
	assert_int(decor.penalty_at(Vector2i(13, 7))).is_equal(0)
	var placed := _world.grid.apply(BuildEdit.place_room(Rect2i(12, 4, 3, 2), &"bag_room"))
	assert_bool(placed.ok).is_true()
	var near := Vector2i(13, 7)
	var beyond := Vector2i(13, 8)
	var inside := Vector2i(13, 4)
	print(
		(
			"bag room penalty: near %d, beyond reach %d"
			% [decor.penalty_at(near), decor.penalty_at(beyond)]
		)
	)
	assert_int(decor.penalty_at(near)).is_equal(2)
	assert_int(decor.penalty_at(beyond)).is_equal(0)
	assert_int(decor.penalty_at(inside)).is_equal(0)
	# Removing the room clears the penalty again.
	assert_bool(_world.grid.apply(BuildEdit.remove_room(_world.grid.room_ids()[0])).ok).is_true()
	assert_int(decor.penalty_at(near)).is_equal(0)


func test_a_bag_room_behind_a_wall_costs_nothing_and_a_cafe_room_costs_nothing() -> void:
	var decor := _world.sim.decor
	(
		assert_bool(_world.grid.apply(BuildEdit.place_room(Rect2i(12, 4, 3, 2), &"bag_room")).ok)
		. is_true()
	)
	assert_int(decor.penalty_at(Vector2i(13, 7))).is_equal(2)
	_wall(Vector2i(13, 6))
	assert_int(decor.penalty_at(Vector2i(13, 7))).is_equal(0)
	assert_bool(_world.grid.apply(BuildEdit.place_room(Rect2i(20, 4, 3, 2), &"cafe")).ok).is_true()
	assert_int(decor.penalty_at(Vector2i(21, 7))).is_equal(0)


func test_a_bag_room_takes_two_calm_from_a_fountain() -> void:
	var fountain := DecorEffect.calm_of(&"fountain_indoor")
	_decor(&"fountain_indoor", FOUNTAIN_CELL)
	(
		assert_bool(_world.grid.apply(BuildEdit.place_room(Rect2i(12, 5, 3, 2), &"bag_room")).ok)
		. is_true()
	)
	var decor := _world.sim.decor
	print(
		(
			"bag room and fountain: calm %d, net %d"
			% [decor.calm_at(GUEST_CELL), decor.net_calm_at(GUEST_CELL)]
		)
	)
	assert_int(decor.penalty_at(GUEST_CELL)).is_equal(2)
	assert_int(decor.net_calm_at(GUEST_CELL)).is_equal(fountain - 2)


func test_the_penalty_comes_off_before_the_cap() -> void:
	for i in 3:
		_decor(&"fountain_indoor", Vector2i(10 + 3 * i, 10))
	_decor(&"trash_can", BIN_CELL)
	var decor := _world.sim.decor
	var summed := decor.calm_at(GUEST_CELL)
	print(
		"summed %d, net %d, cap %d" % [summed, decor.net_calm_at(GUEST_CELL), DecorEffect.MAX_CALM]
	)
	assert_int(summed).is_greater(DecorEffect.MAX_CALM + 1)
	assert_int(DecorEffect.capped(decor.net_calm_at(GUEST_CELL))).is_equal(DecorEffect.MAX_CALM)
