extends GdUnitTestSuite
## A one-bag guest's gate chair side (ParkSide.hand(), its stamp) survives a
## save and a load (board 4da2e8ff, Sol MEDIUM on board 1fe04f01): the stamps
## were cleared on load and chosen again from the guests there then, so a
## two-bag neighbour that took the chair on the guest's right after the guest
## chose (its roller bag 1, fixed in the left hand, lies in that gap) sent the
## guest's roller from the right gap to the left one across the load, with the
## roller lying on the floor. The reference world's first two neighbouring
## seats in a row, the guests put at their fronts as GateCapacity._take_seat()
## seats them; the save is the sim's snapshot through JSON, loaded back into
## the same sim.

var _world: PassengerTestWorld
## Two seats in a row: _seats[1]'s front is _seats[0]'s front less `left`
## (the cell on the right of a guest at _seats[0]'s front facing out).
var _seats: Array = []
## A one-bag guest whose roller is bag 0, and a two-bag guest whose roller is
## bag 1 only (it lies on the left).
var _one: Passenger
var _two: Passenger


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	_seats = []
	for a: Dictionary in _world.sim.layout.seats:
		var out: Vector2i = (a["front"] as Vector2i) - (a["cell"] as Vector2i)
		var right: Vector2i = (a["front"] as Vector2i) - Vector2i(out.y, -out.x)
		for b: Dictionary in _world.sim.layout.seats:
			if b["front"] == right and (b["front"] as Vector2i) - (b["cell"] as Vector2i) == out:
				_seats = [a, b]
				break
		if not _seats.is_empty():
			break
	assert_int(_seats.size()).is_equal(2)
	_one = null
	_two = null
	for attempt in 400:
		var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		ToiletTestLayout.calm(p)
		var first := SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER
		var second := SecurityLooks.bag_kind(p, 1) == SecurityLooks.Kind.ROLLER
		p.carry_on = 0
		p.cleared = true
		p.stage = Passenger.Stage.TO_EXIT
		if _one == null and first:
			_one = p
			p.carry_on = 1
		elif _two == null and second and not first:
			_two = p
			p.carry_on = 2
		if _one != null and _two != null:
			break
	assert_object(_one).is_not_null()
	assert_object(_two).is_not_null()


func after_test() -> void:
	_world = null


## The one-bag guest chooses at its front with both gaps free (its right),
## then the two-bag guest takes the chair on its right; after a save and a
## load the one-bag guest keeps its right. Control: chosen afresh with the
## two-bag guest there (the stamp taken away) the side is the left, so the
## late neighbour is the case the load used to flip.
func test_a_late_two_bag_neighbour_does_not_flip_the_side_after_a_load() -> void:
	_seat(_one, _seats[0])
	var chosen := ParkSide.hand(_world.sim, _one, 0)
	_seat(_two, _seats[1])
	var kept := ParkSide.hand(_world.sim, _one, 0)
	var two_hand := SecurityLooks.hand_of(_world.sim, _two, 1)
	var stamps: Dictionary = (_world.sim.get_meta(ParkSide.STAMPS) as Dictionary).duplicate(true)
	_world.sim.remove_meta(ParkSide.STAMPS)
	var fresh := ParkSide.hand(_world.sim, _one, 0)
	_world.sim.set_meta(ParkSide.STAMPS, stamps)
	var loaded := _load(_save())
	var after := ParkSide.hand(_world.sim, loaded, 0)
	print(
		(
			(
				"one-bag guest's side: chosen %d, kept with the two-bag neighbour (hand %d) %d,"
				+ " chosen afresh %d (1), after a load %d (= chosen)"
			)
			% [chosen, two_hand, kept, fresh, after]
		)
	)
	assert_int(chosen).is_equal(0)
	assert_int(two_hand).is_equal(1)
	assert_int(kept).is_equal(chosen)
	assert_int(fresh).is_equal(1)
	assert_int(after).is_equal(chosen)


## A load replaces the stamps with the saved ones: a stamp made after the
## save (here a left hand for the one-bag guest, alone in its row) is gone
## after the load, and the guest chooses again from the sim as loaded (its
## right, both gaps free).
func test_a_load_drops_stamps_made_after_the_save() -> void:
	_seat(_one, _seats[0])
	var data := _save()
	_world.sim.set_meta(ParkSide.STAMPS, {_one.id: ["gate %s" % _one.seat_cell, 1]})
	var loaded := _load(data)
	var stamps: Dictionary = _world.sim.get_meta(ParkSide.STAMPS, {})
	var after := ParkSide.hand(_world.sim, loaded, 0)
	print("stamps after the load %s, side chosen then %d (0)" % [stamps, after])
	assert_bool(stamps.has(_one.id)).is_false()
	assert_int(after).is_equal(0)


## A saved stamp that names no saved passenger, or holds a hand other than 0
## or 1, refuses the load.
func test_a_bad_saved_stamp_refuses_the_load() -> void:
	_seat(_one, _seats[0])
	ParkSide.hand(_world.sim, _one, 0)
	var data := _save()
	var good: Array = data["park_side"]
	assert_int(good.size()).is_equal(1)
	var bad: Array = [
		{"passenger": 999999, "seat": good[0]["seat"], "hand": 0},
		{"passenger": _one.id, "seat": good[0]["seat"], "hand": 2},
		{"passenger": _one.id, "seat": 7, "hand": 0},
		{"passenger": _one.id, "hand": 0},
	]
	for entry: Dictionary in bad:
		var broken := data.duplicate(true)
		broken["park_side"] = [entry]
		(
			assert_bool(_world.sim.from_snapshot(broken))
			. override_failure_message(str(entry))
			. is_false()
		)


## Puts `p` at `seat`'s front bound for it, as GateCapacity._take_seat() claims
## a seat (the claim is derived from seat_object and seat_cell on a load).
func _seat(p: Passenger, seat: Dictionary) -> void:
	_world.sim._seat_claims[seat["key"]] = p.id
	p.seat_object = seat["object_id"]
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.seat_piece = Relocation.placement(_world.sim.grid, seat["object_id"])
	p.stage = Passenger.Stage.TO_GATE
	p.stage_tick = _world.clock.tick
	p.at = seat["front"]
	p.clear_path()


## The sim's save, as the parsed JSON a load reads.
func _save() -> Dictionary:
	return JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))


## Loads `data` into the sim and returns the one-bag guest as loaded.
func _load(data: Dictionary) -> Passenger:
	assert_bool(_world.sim.from_snapshot(data)).is_true()
	var p := _world.passenger(_one.id)
	assert_object(p).is_not_null()
	return p
