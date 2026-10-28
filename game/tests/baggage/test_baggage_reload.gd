class_name TestBaggageReload
extends GdUnitTestSuite
## Every state the bag sim reaches can be saved and loaded back: bags missed
## or lost part way along an edge, a flight whose cutoff falls before tick 0,
## and (a sweep) a save after every tick of a busy run with edits. Also one
## bag per passenger, in the sim and in a save.


## Saves `world`'s bags through JSON and loads them back into the same sim;
## "" or why that failed or changed anything.
func _reload_problem(world: BagTestWorld) -> String:
	var before := world.signature()
	var data: Variant = JSON.parse_string(JSON.stringify(world.sim.to_snapshot()))
	var loaded := BaggageSnapshot.load(data)
	if loaded.has("error"):
		return "tick %d: %s" % [world.clock.tick, loaded["error"]]
	if not world.sim.from_snapshot(data):
		return "tick %d: refused against the grid" % world.clock.tick
	if world.signature() != before:
		return "tick %d: %s became %s" % [world.clock.tick, before, world.signature()]
	return ""


func test_a_bag_missed_part_way_along_an_edge_reloads() -> void:
	var world := BagTestWorld.make(self, BagTestWorld.ARRIVAL - 1 + BaggageSim.LOAD_LEAD_TICKS)
	var bag := world.sim.check_in(1, BagTestWorld.FLIGHT, world.line())
	world.run_to(BagTestWorld.ARRIVAL - 1)
	assert_int(bag.cause).is_equal(Bag.Cause.LATE)
	assert_int(bag.remain_mm).is_equal(BaggageSim.BELT_MM)
	assert_str(_reload_problem(world)).is_equal("")


func test_a_bag_lost_part_way_along_an_edge_reloads() -> void:
	var world := BagTestWorld.make(self)
	var bag := world.sim.check_in(1, BagTestWorld.FLIGHT, world.line())
	world.run_to(38)
	world.unlay(Vector2i(4, 7))
	world.step()
	assert_int(bag.cause).is_equal(Bag.Cause.LOST)
	# Lost in the tick's reconcile, before it moved: where it stood after tick 38.
	assert_int(bag.remain_mm).is_equal(600)
	assert_str(_reload_problem(world)).is_equal("")


func test_a_flight_whose_cutoff_is_before_tick_0_reloads() -> void:
	var world := BagTestWorld.make(self, 150)
	var bag := world.sim.check_in(1, BagTestWorld.FLIGHT, world.line())
	assert_int(bag.cutoff_tick).is_equal(-50)
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	world.step()
	assert_str(_reload_problem(world)).is_equal("")


func test_a_passenger_checks_one_bag() -> void:
	var world := BagTestWorld.make(self)
	var desk_id := world.line()
	assert_object(world.sim.check_in(5, BagTestWorld.FLIGHT, desk_id)).is_not_null()
	(
		assert_error(func() -> void: world.sim.check_in(5, BagTestWorld.FLIGHT, desk_id))
		. is_push_error("BaggageSim.check_in: passenger 5 already has bag 1")
	)
	assert_int(world.sim.bag_ids().size()).is_equal(1)
	world.sim.check_in(6, BagTestWorld.FLIGHT, desk_id)
	world.step()
	var data: Dictionary = JSON.parse_string(JSON.stringify(world.sim.to_snapshot()))
	data["bags"][1]["passenger"] = 5
	assert_str(str(BaggageSnapshot.load(data).get("error", ""))).contains(
		"passenger 5 already has bag 1"
	)


func test_a_save_after_every_tick_of_a_busy_run_reloads() -> void:
	var world := BagTestWorld.make(self, 700)
	var desks: Array[int] = [world.line(), world.side_desk()]
	var states := {}
	while world.clock.tick < 950:
		world.step()
		var problem := _reload_problem(world)
		if problem != "":
			fail(problem)
			return
		for b in world.sim.bags():
			states["%d/%d" % [b.state, b.cause]] = true
		_busy_event(world, desks)
	# The run went through riding, blocked, in the room, loaded, late, lost.
	for key in ["1/0", "2/0", "3/0", "4/0", "5/1", "5/4"]:
		assert_bool(states.has(key)).override_failure_message("never reached %s" % key).is_true()


## Check-ins at both desks, a port turned away and back, belts taken away
## from under bags and laid again, the bag room removed and drawn again, and
## check-ins just before and after the cutoff (500).
func _busy_event(world: BagTestWorld, desks: Array[int]) -> void:
	var t := world.clock.tick
	var arrivals := {0: [3, 0], 5: [2, 1], 60: [3, 0], 470: [4, 0], 600: [1, 1]}
	if arrivals.has(t):
		for i in arrivals[t][0]:
			world.sim.check_in(t * 10 + i, BagTestWorld.FLIGHT, desks[arrivals[t][1]])
	match t:
		35:
			world.grid.apply(BuildEdit.reshape_belt(Vector2i(5, 7), &"baggage_belt", 0))
		60:
			world.grid.apply(BuildEdit.reshape_belt(Vector2i(5, 7), &"baggage_belt", 1))
		100:
			world.unlay(Vector2i(8, 7))
		101:
			world.lay(Vector2i(8, 7), Vector2i(8, 7))
		120:
			world.unlay(Vector2i(4, 7))
		130:
			world.lay(Vector2i(4, 7), Vector2i(4, 7))
		145:
			world.grid.apply(BuildEdit.remove_room(world.grid.room_at(BagTestWorld.END)))
		170:
			world.room(BagTestWorld.ROOM)
