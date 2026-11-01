class_name TestMessRules
extends GdUnitTestSuite
## MessSim's rules on an open floor (decision mess-sim-technical-design-
## messsim-under-passengersim-counters-refuse-at-cap): every Nth use of one
## source leaves one mess, a bin in range and in sight takes litter until it is
## full, only litter grows and only after GROW_TICKS, at the cap a mess merges
## into one of its kind nearby or is refused and counted, messes never change
## walking, and an edit drops what it took away.

const SPOT := Vector2i(15, 10)

## One world for the file; each case starts with no messes and puts back the
## grid edits it made (_undo).
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


## Places `def_id` at `cell` and notes its removal for after_test().
func _place(def_id: StringName, cell: Vector2i) -> int:
	var id := PassengerTestWorld.place(_world.grid, def_id, cell, 0)
	_undo.append(BuildEdit.remove_object(id))
	return id


func _bin(cell: Vector2i) -> int:
	return _place(MessSim.BIN_ID, cell)


## Applies `edit` and notes `back` for after_test(); whether it applied.
func _edit(edit: BuildEdit, back: BuildEdit) -> bool:
	var ok := _world.grid.apply(edit).ok
	if ok:
		_undo.append(back)
	return ok


func test_every_nth_use_of_one_source_leaves_one_mess_at_its_spot() -> void:
	var visit := MessTestKit.cafe_visit(SPOT, "900:0")
	var other := MessTestKit.cafe_visit(SPOT + Vector2i(5, 0), "901:0")
	for i in MessSim.CAFE_EVERY - 1:
		_messes().cafe_used(visit)
	_messes().cafe_used(other)
	var before := _messes().mess_count()
	_messes().cafe_used(visit)
	var ids := _messes().mess_ids()
	print(
		(
			"uses %d and %d, messes %d -> %d, every %d"
			% [
				_messes().uses_of(MessSim.seat_source("900:0")),
				_messes().uses_of(MessSim.seat_source("901:0")),
				before,
				ids.size(),
				MessSim.CAFE_EVERY
			]
		)
	)
	assert_int(before).is_equal(0)
	assert_int(ids.size()).is_equal(1)
	var mess := _messes().get_mess(ids[0])
	assert_that(mess["cell"]).is_equal(SPOT)
	assert_that(mess["approach"]).is_equal(SPOT)
	assert_int(mess["kind"]).is_equal(MessSim.Kind.LITTER)
	assert_int(mess["born_tick"]).is_equal(_world.clock.tick)
	assert_int(_messes().uses_of(MessSim.seat_source("900:0"))).is_equal(MessSim.CAFE_EVERY)
	assert_int(_messes().uses_of(MessSim.seat_source("901:0"))).is_equal(1)


func test_a_bar_spills_and_a_bin_does_not_take_a_spill() -> void:
	_bin(SPOT + Vector2i(1, 0))
	var visit := MessTestKit.cafe_visit(SPOT, "900:0", &"bar")
	for i in MessSim.CAFE_EVERY:
		_messes().cafe_used(visit)
	var ids := _messes().mess_ids()
	assert_int(ids.size()).is_equal(1)
	assert_int(_messes().get_mess(ids[0])["kind"]).is_equal(MessSim.Kind.SPILL)
	assert_int(_messes().caught).is_equal(0)


func test_a_bin_in_range_and_in_sight_takes_the_litter() -> void:
	var bin := _bin(SPOT + Vector2i(MessSim.BIN_RANGE, 0))
	MessTestKit.litter(_world, SPOT)
	print(
		(
			"bin %d cells away: fill %d, messes %d"
			% [MessSim.BIN_RANGE, _messes().fill_of(bin), _messes().mess_count()]
		)
	)
	assert_int(_messes().fill_of(bin)).is_equal(1)
	assert_int(_messes().caught).is_equal(1)
	assert_int(_messes().mess_count()).is_equal(0)


func test_a_bin_out_of_range_or_behind_a_wall_does_not() -> void:
	var far := _bin(SPOT + Vector2i(MessSim.BIN_RANGE + 1, 0))
	MessTestKit.litter(_world, SPOT)
	assert_int(_messes().fill_of(far)).is_equal(0)
	assert_int(_messes().mess_count()).is_equal(1)
	# A bin two cells north, behind a plain wall.
	var spot := Vector2i(5, 10)
	var walled := _bin(spot + Vector2i(0, -2))
	var wall := BuildEdit.place_wall(spot, BuildGrid.Side.NORTH)
	assert_bool(_edit(wall, BuildEdit.remove_wall(spot, BuildGrid.Side.NORTH))).is_true()
	MessTestKit.litter(_world, spot, "902:0")
	print(
		(
			"far bin fill %d, walled bin fill %d, messes %d"
			% [_messes().fill_of(far), _messes().fill_of(walled), _messes().mess_count()]
		)
	)
	assert_int(_messes().fill_of(walled)).is_equal(0)
	assert_int(_messes().mess_count()).is_equal(2)


func test_a_full_bin_takes_no_more_and_the_litter_lands() -> void:
	var bin := _bin(SPOT + Vector2i(1, 1))
	for i in MessSim.BIN_CAPACITY:
		MessTestKit.litter(_world, SPOT)
	var full := _messes().fill_of(bin)
	var before := _messes().mess_count()
	MessTestKit.litter(_world, SPOT)
	print(
		(
			"fill %d of %d, messes %d -> %d"
			% [full, MessSim.BIN_CAPACITY, before, _messes().mess_count()]
		)
	)
	assert_int(full).is_equal(MessSim.BIN_CAPACITY)
	assert_int(before).is_equal(0)
	assert_int(_messes().fill_of(bin)).is_equal(MessSim.BIN_CAPACITY)
	assert_int(_messes().mess_count()).is_equal(1)
	assert_int(_messes().bin_for(SPOT)).is_equal(0)


func test_only_litter_grows_and_only_after_grow_ticks() -> void:
	var litter := _messes().add(MessSim.Kind.LITTER, SPOT)
	var spill := _messes().add(MessSim.Kind.SPILL, Vector2i(5, 5))
	var born := _world.clock.tick
	var edge := SPOT + Vector2i(MessSim.GROWN_RADIUS, 0)
	_world.run_to(born + MessSim.GROW_TICKS - 1)
	var before: bool = _messes().get_mess(litter)["grown"]
	var dirt_before := _messes().dirt_at(edge)
	_world.step()
	var after: bool = _messes().get_mess(litter)["grown"]
	print(
		(
			"litter grown at +%d %s, at +%d %s; dirt %d cells off %d -> %d"
			% [
				MessSim.GROW_TICKS - 1,
				before,
				MessSim.GROW_TICKS,
				after,
				MessSim.GROWN_RADIUS,
				dirt_before,
				_messes().dirt_at(edge)
			]
		)
	)
	assert_bool(before).is_false()
	assert_bool(after).is_true()
	assert_int(dirt_before).is_equal(0)
	assert_int(_messes().dirt_at(edge)).is_equal(MessSim.GROWN_DIRT)
	assert_bool(_messes().get_mess(spill)["grown"]).is_false()


func test_a_mess_on_a_cell_with_one_of_its_kind_merges_into_it() -> void:
	var first := _messes().add(MessSim.Kind.LITTER, SPOT)
	var again := _messes().add(MessSim.Kind.LITTER, SPOT)
	var spill := _messes().add(MessSim.Kind.SPILL, SPOT)
	# Below the cap, litter one cell over is a mess of its own.
	var beside := _messes().add(MessSim.Kind.LITTER, SPOT + Vector2i(1, 0))
	assert_int(again).is_equal(first)
	assert_int(spill).is_not_equal(first)
	assert_int(beside).is_not_equal(first)
	assert_int(_messes().mess_count()).is_equal(3)
	assert_int(_messes().merged).is_equal(1)


func test_at_the_cap_a_mess_merges_into_one_of_its_kind_nearby_or_is_refused() -> void:
	# MAX_MESSES litter on a 3-cell lattice in the north half, y 0 to 9.
	var placed := 0
	for y in range(0, 10, 3):
		for x in range(0, 30, 3):
			if (
				placed < MessSim.MAX_MESSES
				and _messes().add(MessSim.Kind.LITTER, Vector2i(x, y)) > 0
			):
				placed += 1
	assert_int(_messes().mess_count()).is_equal(MessSim.MAX_MESSES)
	var target := _messes().mess_ids()[5]
	var near: Vector2i = _messes().get_mess(target)["cell"] + Vector2i(1, 0)
	var merged_into := _messes().add(MessSim.Kind.LITTER, near)
	var other_kind := _messes().add(MessSim.Kind.SPILL, near)
	var far := _messes().add(MessSim.Kind.LITTER, Vector2i(15, 17))
	print(
		(
			(
				"at the cap %d: litter at %s merged into %d (target %d), spill -> %d, far litter -> %d;"
				+ " merged %d, overflow %d, count %d"
			)
			% [
				MessSim.MAX_MESSES,
				near,
				merged_into,
				target,
				other_kind,
				far,
				_messes().merged,
				_messes().overflow,
				_messes().mess_count()
			]
		)
	)
	assert_int(merged_into).is_equal(target)
	assert_int(other_kind).is_equal(0)
	assert_int(far).is_equal(0)
	assert_int(_messes().merged).is_equal(1)
	assert_int(_messes().overflow).is_equal(2)
	assert_int(_messes().mess_count()).is_equal(MessSim.MAX_MESSES)


func test_messes_do_not_change_walking() -> void:
	var from := Vector2i(1, 10)
	var to := Vector2i(28, 10)
	var path_before := _world.grid.find_path(from, to)
	for x in range(2, 28):
		_messes().add(MessSim.Kind.SPILL, Vector2i(x, 10))
	var path_after := _world.grid.find_path(from, to)
	var walkable := 0
	for x in range(2, 28):
		if _world.grid.is_walkable(Vector2i(x, 10)):
			walkable += 1
	print(
		(
			"messes %d on the row, walkable %d, path %d -> %d cells"
			% [_messes().mess_count(), walkable, path_before.size(), path_after.size()]
		)
	)
	assert_int(_messes().mess_count()).is_equal(26)
	assert_int(walkable).is_equal(26)
	assert_int(path_before.size()).is_greater(0)
	assert_array(path_after).is_equal(path_before)


func test_an_edit_drops_a_mess_off_the_floor_a_removed_bins_fill_and_a_gone_source() -> void:
	var kept := _messes().add(MessSim.Kind.SPILL, SPOT)
	var dropped := _messes().add(MessSim.Kind.SPILL, Vector2i(25, 15))
	var bin := _bin(Vector2i(4, 4))
	var table := _place(&"cafe_table", Vector2i(8, 4))
	MessTestKit.litter(_world, Vector2i(4, 5), "%d:0" % table)
	var source := MessSim.seat_source("%d:0" % table)
	assert_int(_messes().fill_of(bin)).is_equal(1)
	assert_int(_messes().uses_of(source)).is_equal(MessSim.CAFE_EVERY)
	var hole := Vector2i(25, 15)
	var refloor := BuildEdit.paint_floor(hole, BuildGrid.FLOOR_TILE, 1)
	assert_bool(_edit(BuildEdit.remove_floor(hole), refloor)).is_true()
	assert_bool(_world.grid.apply(BuildEdit.remove_object(bin)).ok).is_true()
	assert_bool(_world.grid.apply(BuildEdit.remove_object(table)).ok).is_true()
	var stale := _messes().stale
	_world.step()
	print(
		(
			"stale after the edits %s, then %s; messes %s; bin fill %d; uses %d"
			% [
				stale,
				_messes().stale,
				_messes().mess_ids(),
				_messes().fill_of(bin),
				_messes().uses_of(source)
			]
		)
	)
	assert_bool(stale).is_true()
	assert_bool(_messes().stale).is_false()
	assert_array(_messes().mess_ids()).is_equal([kept])
	assert_bool(_messes().get_mess(dropped).is_empty()).is_true()
	assert_int(_messes().fill_of(bin)).is_equal(0)
	assert_int(_messes().uses_of(source)).is_equal(0)


func test_a_mess_built_over_moves_its_approach_to_a_walkable_neighbour() -> void:
	var id := _messes().add(MessSim.Kind.SPILL, SPOT)
	_bin(SPOT)
	_world.step()
	var mess := _messes().get_mess(id)
	print(
		(
			"cell %s walkable %s, approach %s"
			% [mess["cell"], _world.grid.is_walkable(SPOT), mess["approach"]]
		)
	)
	assert_bool(_world.grid.is_walkable(SPOT)).is_false()
	assert_that(mess["cell"]).is_equal(SPOT)
	assert_that(mess["approach"]).is_equal(SPOT + MessSim.AROUND[0])
	assert_bool(_world.grid.is_walkable(mess["approach"])).is_true()
