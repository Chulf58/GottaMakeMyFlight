class_name TestBaggageSaveControl
extends GdUnitTestSuite
## A world loaded from a JSON save plays on exactly like an unsaved control
## (decision baggage-bag-sim-design-route-field-belt-capacity-cutoff): the
## same bag states on every tick and the same bag_settled events, exactly once
## each, across equal-route ties, a mid-edge edit, merge contention, a bag
## room taken away and given back, and the cutoff tick either side.


## Builds a layout on `world`; returns the desk ids it made.
func _tie_layout(world: BagTestWorld) -> Array[int]:
	world.room(Rect2i(0, 2, 3, 3))
	world.room(Rect2i(12, 2, 3, 3))
	var desk_id := world.desk(Vector2i(6, 4))
	world.lay(Vector2i(2, 3), Vector2i(12, 3))
	return [desk_id]


func _merge_layout(world: BagTestWorld) -> Array[int]:
	world.room(Rect2i(5, 8, 3, 3))
	var left := world.desk(Vector2i(2, 4))
	var right := world.desk(Vector2i(9, 4))
	world.lay(Vector2i(3, 3), Vector2i(10, 3))
	world.lay(Vector2i(6, 3), Vector2i(6, 9))
	return [left, right]


func _line_layout(world: BagTestWorld) -> Array[int]:
	return [world.line(), world.desk(Vector2i(5, 8))]


## Runs `world` to `to`, running events[t] (Callable(world, desks)) after
## tick t.
func _play(world: BagTestWorld, desks: Array[int], events: Dictionary, to: int) -> void:
	while world.clock.tick < to:
		if events.has(world.clock.tick):
			(events[world.clock.tick] as Callable).call(world, desks)
		world.step()


## A control world and a twin built and played the same way up to tick
## `save_at`, where the twin loads the control's save through JSON; both then
## play on through `until` and are compared on every tick.
func _compare(layout: Callable, doors: int, save_at: int, until: int, events: Dictionary) -> void:
	var control := BagTestWorld.make(self, doors)
	var desks: Array[int] = []
	desks.assign(layout.call(control))
	var loaded := BagTestWorld.make(self, doors)
	assert_array(layout.call(loaded)).is_equal(desks)
	_play(control, desks, events, save_at)
	_play(loaded, desks, events, save_at)
	var data: Variant = JSON.parse_string(JSON.stringify(control.sim.to_snapshot()))
	assert_bool(loaded.sim.from_snapshot(data)).is_true()
	var control_from := control.settled.size()
	var loaded_from := loaded.settled.size()
	assert_str(loaded.signature()).is_equal(control.signature())
	while control.clock.tick < until:
		_play(control, desks, events, control.clock.tick + 1)
		_play(loaded, desks, events, loaded.clock.tick + 1)
		if control.signature() != loaded.signature():
			fail(
				"tick %d: %s != %s" % [control.clock.tick, control.signature(), loaded.signature()]
			)
			return
	assert_array(loaded.settled.slice(loaded_from)).is_equal(control.settled.slice(control_from))
	assert_int(control.settled.size() - control_from).is_greater(0)
	var ids := {}
	for event in control.settled:
		assert_bool(ids.has(event[0])).override_failure_message("settled twice").is_false()
		ids[event[0]] = true
	for bag in control.sim.bags():
		assert_bool(ids.has(bag.id)).is_equal(bag.is_settled())


func _check_ins(count: int, desk_index := 0) -> Callable:
	return func(world: BagTestWorld, desks: Array[int]) -> void:
		for i in count:
			var passenger := world.clock.tick * 10 + i
			world.sim.check_in(passenger, BagTestWorld.FLIGHT, desks[desk_index])


func test_equal_route_ties_play_on_alike() -> void:
	var events := {0: _check_ins(4), 40: _check_ins(2)}
	_compare(_tie_layout, 600, 33, 700, events)


func test_merge_contention_plays_on_alike() -> void:
	var events := {0: _check_ins(3, 1), 20: _check_ins(3, 0)}
	_compare(_merge_layout, 600, 69, 700, events)


func test_a_mid_edge_edit_plays_on_alike() -> void:
	var cut := func(world: BagTestWorld, _desks: Array[int]) -> void:
		world.grid.apply(BuildEdit.reshape_belt(Vector2i(5, 7), &"baggage_belt", 0))
	var mend := func(world: BagTestWorld, _desks: Array[int]) -> void:
		world.grid.apply(BuildEdit.reshape_belt(Vector2i(5, 7), &"baggage_belt", 1))
	var events := {0: _check_ins(3), 35: cut, 60: mend, 70: _check_ins(2, 1)}
	_compare(_line_layout, 800, 44, 900, events)


func test_a_bag_room_taken_away_and_given_back_plays_on_alike() -> void:
	var take := func(world: BagTestWorld, _desks: Array[int]) -> void:
		world.grid.apply(BuildEdit.remove_room(world.grid.room_at(BagTestWorld.END)))
	var give := func(world: BagTestWorld, _desks: Array[int]) -> void: world.room(BagTestWorld.ROOM)
	var events := {0: _check_ins(3), 145: take, 170: give, 175: _check_ins(2, 1)}
	_compare(_line_layout, 800, 160, 900, events)


func test_the_cutoff_tick_and_the_one_before_play_on_alike() -> void:
	var events := {0: _check_ins(2)}
	var doors := BagTestWorld.ARRIVAL + BaggageSim.LOAD_LEAD_TICKS
	_compare(_line_layout, doors, BagTestWorld.ARRIVAL - 1, doors + 300, events)
	_compare(_line_layout, doors - 1, BagTestWorld.ARRIVAL - 2, doors + 300, events)
