class_name TestScannerBoothCarry
extends GdUnitTestSuite
## The basic scanner booth's passage (decision basic-scanner-booth-passengers-
## carry-their-bags-in-front-and): a passenger in a booth cell, walking into
## one, or waiting at its entry in the security queue carries in front; a
## passenger walking up to the entry turns a step early; a roller is lifted
## into the hand before the turn starts; its free arms tuck in over CarryOnProps.TRANSFER_TICKS, a
## passenger without bags included, and come out again past the booth.
##
## The world is SecurityTestWorld's basic scanner on (5, 5), passage (5, 7)
## entry, (5, 6) and (5, 5) booth, (5, 4) exit.

const ENTRY := Vector2i(5, 7)
const BOOTH := Vector2i(5, 6)
const EXIT := Vector2i(5, 4)

var _worlds: Array[SecurityTestWorld] = []
var _views: Array[PassengerViews] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for v in _views:
		v.free()
	_views.clear()
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


func _make(use_lane: bool) -> SecurityTestWorld:
	var w := SecurityTestWorld.make(use_lane)
	_worlds.append(w)
	return w


## A passenger standing at `at`, walking the steps of `route` from its first.
func _walker(id: int, stage: Passenger.Stage, route: Array[Vector2i]) -> Passenger:
	var p := Passenger.new()
	p.id = id
	p.carry_on = 1
	p.stage = stage
	p.at = route[0]
	p.set_path(route)
	return p


## The first passenger id whose first bag is (or is not) a roller.
func _id_with_roller(roller: bool) -> int:
	for id in range(1, 200):
		var p := Passenger.new()
		p.id = id
		if (SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER) == roller:
			return id
	return -1


func test_the_booth_passage_means_a_front_carry() -> void:
	var w := _make(false)
	var sim := w.world.sim
	assert_array(sim.layout.passages[w.station]).is_equal([ENTRY, BOOTH, Vector2i(5, 5), EXIT])
	var case_id := _id_with_roller(false)
	# In a booth cell, standing.
	var p := _walker(case_id, Passenger.Stage.SECURITY, [BOOTH])
	assert_bool(SecurityLooks.carry_front(sim, p)).is_true()
	# Walking from the entry into the booth.
	p = _walker(case_id, Passenger.Stage.SECURITY, [ENTRY, BOOTH])
	assert_bool(p.is_moving()).is_true()
	assert_bool(SecurityLooks.carry_front(sim, p)).is_true()
	# Waiting at the entry as the queue front.
	p = _walker(case_id, Passenger.Stage.SECURITY_QUEUE, [ENTRY])
	assert_bool(SecurityLooks.carry_front(sim, p)).is_true()
	# Walking up to the entry in the queue: a step early.
	var up: Array[Vector2i] = [ENTRY + Vector2i(0, 1), ENTRY]
	p = _walker(case_id, Passenger.Stage.SECURITY_QUEUE, up)
	assert_bool(SecurityLooks.carry_front(sim, p)).is_true()
	# A roller passenger too (CarryOnProps lifts the roller first).
	var roller := _walker(_id_with_roller(true), Passenger.Stage.SECURITY_QUEUE, up)
	assert_bool(SecurityLooks.carry_front(sim, roller)).is_true()
	# Arrived past the booth: back to the side.
	p = _walker(case_id, Passenger.Stage.SECURITY, [EXIT])
	assert_bool(SecurityLooks.carry_front(sim, p)).is_false()
	# Control: the entry cell does not count for a passenger not at security.
	p = _walker(case_id, Passenger.Stage.TO_GATE, [ENTRY])
	assert_bool(SecurityLooks.carry_front(sim, p)).is_false()


## A walker still on its way to security (no queue: it is admitted at the
## entry without stopping) counts from the step into its own booth's entry,
## from straight ahead or from the side, and on the entry until it joins the
## queue; not on the cell before it, not at another station's entry, and not
## at a lane.
func test_a_walker_on_its_way_turns_a_step_before_its_own_entry() -> void:
	var w := _make(false)
	var sim := w.world.sim
	var id := _id_with_roller(false)
	var before := ENTRY + Vector2i(0, 1)
	var cases := [
		[[before, ENTRY], w.station, true],
		[[ENTRY + Vector2i(1, 0), ENTRY], w.station, true],
		[[ENTRY + Vector2i(1, 1), ENTRY], w.station, true],
		[[ENTRY], w.station, true],
		[[ENTRY], w.station + 1000, false],
		[[before], w.station, false],
		[[before + Vector2i(0, 1), before], w.station, false],
		[[before, ENTRY], w.station + 1000, false],
	]
	for c: Array in cases:
		var route: Array[Vector2i] = []
		route.assign(c[0])
		var p := _walker(id, Passenger.Stage.TO_SECURITY, route)
		p.station = c[1]
		(
			assert_bool(SecurityLooks.in_booth_passage(sim, p))
			. override_failure_message("route %s station %d" % [c[0], c[1]])
			. is_equal(c[2])
		)
	# Control: at a lane, walking into its unpack cell is no booth entry.
	var lane := _make(true)
	var unpack := SecurityTestWorld.ARCH_AT + Vector2i(0, 1)
	var q := _walker(id, Passenger.Stage.TO_SECURITY, [unpack + Vector2i(0, 1), unpack])
	q.station = lane.station
	assert_bool(SecurityLooks.in_booth_passage(lane.world.sim, q)).is_false()


## A lane's arch tucks the arms (decision security-lane-arch-is-narrowed-to-
## fit-inside-its-cell-beside-a): standing in it or walking into it, until the
## cell past it is reached; not standing on the unpack cell or past the arch.
func test_a_lane_arch_passage_tucks_the_arms() -> void:
	var w := _make(true)
	var sim := w.world.sim
	var arch := SecurityTestWorld.ARCH_AT
	var id := _id_with_roller(false)
	var cases := [
		[[arch], true],
		[[arch + Vector2i(0, 1), arch], true],
		[[arch, arch + Vector2i(0, -1)], true],
		[[arch + Vector2i(0, 1)], false],
		[[arch + Vector2i(0, -1)], false],
		[[arch + Vector2i(0, -1), arch + Vector2i(0, -2)], false],
	]
	for c: Array in cases:
		var route: Array[Vector2i] = []
		route.assign(c[0])
		var p := _walker(id, Passenger.Stage.SECURITY, route)
		(
			assert_bool(SecurityLooks.in_arch_passage(sim, p))
			. override_failure_message("route %s" % [c[0]])
			. is_equal(c[1])
		)
	# Control: a basic scanner's booth is no arch.
	var booth := _make(false)
	var b := _walker(id, Passenger.Stage.SECURITY, [BOOTH])
	assert_bool(SecurityLooks.in_arch_passage(booth.world.sim, b)).is_false()


## Control: a lane's arch is not a booth.
func test_a_lane_arch_is_not_a_booth() -> void:
	var w := _make(true)
	var p := _walker(_id_with_roller(false), Passenger.Stage.SECURITY, [SecurityTestWorld.ARCH_AT])
	assert_bool(SecurityLooks.in_booth(w.world.sim.grid, SecurityTestWorld.ARCH_AT)).is_false()
	assert_bool(SecurityLooks.in_booth_passage(w.world.sim, p)).is_false()


## A passenger without bags tucks both free arms in through the booth: the arms
## turn part way on several ticks before they are first fully in (no snap),
## stay fully in inside the booth, and are off again once it has walked on.
func test_a_passenger_without_bags_tucks_its_arms_through_the_booth() -> void:
	var w := _make(false)
	var views := _views_of(w)
	var ids := w.send_all([[0, false, false]])
	var p := w.world.passenger(ids[0])
	var partway_before_full := 0
	var full := false
	var full_in_booth := 0
	var arms_off_after := false
	for i in 3000:
		w.world.step()
		views.draw()
		var body := views.node_for(ids[0])
		if body == null or not body.has_meta(&"carry_rig"):
			continue
		var arms: Array = body.get_meta(&"carry_rig")["arms"]
		var weights: Array[float] = []
		for arm: CarryArm in arms:
			weights.append(arm.front_weight if arm.active else 0.0)
		if not full and weights.min() > 0.0 and weights.max() < 1.0:
			partway_before_full += 1
		full = full or weights.min() == 1.0
		if SecurityLooks.in_booth(w.world.sim.grid, p.at) and weights.min() == 1.0:
			full_in_booth += 1
		if w.cleared.has(ids[0]) and not SecurityLooks.in_booth_passage(w.world.sim, p):
			if arms.all(func(a: CarryArm) -> bool: return not a.active):
				arms_off_after = true
				break
	print(
		(
			"no-bag tuck: partway before full=%d tucked in the booth=%d arms off after=%s"
			% [partway_before_full, full_in_booth, arms_off_after]
		)
	)
	assert_int(partway_before_full).is_greater(1)
	assert_int(full_in_booth).is_greater(0)
	assert_bool(arms_off_after).is_true()


## A roller is lifted into the hand at the booth entry and that move ends
## before the turn to the front starts; past the booth it goes back to the pull
## only once the turn back to the side has ended, checked until 20 ticks after
## the last roller passenger cleared. Control: a roller was carried in front.
func test_a_roller_is_lifted_before_the_front_turn_and_lowered_after_it() -> void:
	var seen := _watch_rollers(_make(false))
	assert_int(seen["front_ticks"]).is_greater(0)
	assert_array(seen["moving_in_front"]).is_empty()
	assert_array(seen["pulled_in_front"]).is_empty()


## Past a booth whose exit cells are closed on both sides, the front carry goes
## on after the arms have tucked out; the roller stays in hand until it ends.
## Control: a roller was carried in front past the booth.
func test_a_roller_stays_lifted_through_a_closed_way_past_the_booth() -> void:
	var w := _make(false)
	for cell in [EXIT, EXIT + Vector2i(0, -1)]:
		for side in [BuildGrid.Side.WEST, BuildGrid.Side.EAST]:
			assert_bool(w.world.sim.grid.apply(BuildEdit.place_wall(cell, side)).ok).is_true()
	var seen := _watch_rollers(w)
	assert_int(seen["front_past_booth"]).is_greater(0)
	assert_array(seen["moving_in_front"]).is_empty()
	assert_array(seen["pulled_in_front"]).is_empty()


## Sends four one-bag passengers and watches the roller carriers among them
## every tick until 20 ticks after the last of them cleared.
func _watch_rollers(w: SecurityTestWorld) -> Dictionary:
	var views := _views_of(w)
	var props := views.carry_on_props()
	var ids := w.send_all(
		[[1, false, false], [1, false, false], [1, false, false], [1, false, false]]
	)
	var rollers: Array[int] = []
	for id in ids:
		if SecurityLooks.bag_kind(w.world.passenger(id), 0) == SecurityLooks.Kind.ROLLER:
			rollers.append(id)
	assert_int(rollers.size()).is_greater(0)
	var out := {
		"front_ticks": 0, "front_past_booth": 0, "moving_in_front": [], "pulled_in_front": []
	}
	var stop_at := -1
	for i in 4000:
		w.world.step()
		views.draw()
		for id in rollers:
			var carries: Array = props.props_of(id)["carries"]
			var weight := props.front_weight_of(id)
			if carries.is_empty() or weight <= 0.0:
				continue
			out["front_ticks"] += 1
			if w.world.passenger(id).at.y <= EXIT.y:
				out["front_past_booth"] += 1
			if props.transfer_progress(id, 0) < 1.0:
				out["moving_in_front"].append([id, w.world.clock.tick, weight])
			if carries[0] == SecurityLooks.Carry.PULL:
				out["pulled_in_front"].append([id, w.world.clock.tick, weight])
		if stop_at < 0 and rollers.all(func(id: int) -> bool: return w.cleared.has(id)):
			stop_at = w.world.clock.tick + 20
		if stop_at >= 0 and w.world.clock.tick >= stop_at:
			break
	print("rollers %s: %s" % [rollers, out])
	return out


## A load (PassengerViews.snap()) while a passenger's arms are turning in on
## the approach draws it tucked at once, with bags (a backpack, worn, so both
## hands are free) and without. Before the snap both arms are part way in
## (strictly between 0 and 1); right after it they are fully in. Without the
## restore a fresh record would start untucked (0) and ease in again.
func test_a_load_during_the_turn_in_draws_the_arms_tucked() -> void:
	var w := _make(false)
	var views := _views_of(w)
	var backpack := -1
	for id in range(1, 200):
		var probe := Passenger.new()
		probe.id = id
		if SecurityLooks.bag_kind(probe, 0) == SecurityLooks.Kind.BACKPACK:
			backpack = id
			break
	# Spawns until the next id is a backpack passenger, then sends it with one
	# bag and one without.
	var ids: Array[int] = []
	while ids.size() < 2:
		var id := w.send(1 if ids.is_empty() else 0)
		var p := w.world.passenger(id)
		if ids.is_empty() and SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.BACKPACK:
			p.stage = Passenger.Stage.TO_GATE
			continue
		ids.append(id)
		w.world.run_to(w.world.clock.tick + SecurityTestWorld.SPACING)
	assert_int(backpack).is_greater(0)
	for id in ids:
		var p := w.world.passenger(id)
		var before: Array[float] = []
		for i in 3000:
			w.world.step()
			views.draw()
			if not SecurityLooks.in_booth_passage(w.world.sim, p):
				continue
			var weights := _arm_weights(views, id)
			if weights.min() > 0.0 and weights.max() < 1.0:
				before = weights
				views.snap()
				break
		var after := _arm_weights(views, id)
		print("load during the turn-in: passenger %d before=%s after=%s" % [id, before, after])
		assert_array(before).is_not_empty()
		assert_float(before.min()).is_greater(0.0)
		assert_float(before.max()).is_less(1.0)
		assert_float(after.min()).is_equal(1.0)


func _arm_weights(views: PassengerViews, id: int) -> Array[float]:
	var out: Array[float] = []
	var body := views.node_for(id)
	if body == null or not body.has_meta(&"carry_rig"):
		return [0.0]
	for arm: CarryArm in body.get_meta(&"carry_rig")["arms"]:
		out.append(arm.front_weight if arm.active else 0.0)
	return out


func _views_of(w: SecurityTestWorld) -> PassengerViews:
	var views := PassengerViews.new()
	views.clock = w.world.clock
	views.sim = w.world.sim
	add_child(views)
	_views.append(views)
	return views


## Bags go to the front BoothCarry.LEAD_M before the booth's first cell, on the
## way to security no, in the queue or at security, on the passage's line: two
## cells out yes, three no; not past the booth, beside the line or at another stage. Control:
## the two-cell spot is a real distance from the booth (more than the entry).
func test_bags_go_to_the_front_a_lead_before_the_booth() -> void:
	var w := _make(false)
	var sim := w.world.sim
	var id := _id_with_roller(false)
	var two := ENTRY + Vector2i(0, 1)
	var gap := sim.grid.cell_to_world(two).distance_to(sim.grid.cell_to_world(BOOTH))
	print(
		"two cells out: %.2f m from the booth's first cell, lead %.2f m" % [gap, BoothCarry.LEAD_M]
	)
	assert_float(gap).is_greater(1.5)
	assert_float(gap).is_less_equal(BoothCarry.LEAD_M)
	var cases := [
		[Passenger.Stage.SECURITY_QUEUE, two, true],
		[Passenger.Stage.SECURITY, ENTRY, true],
		[Passenger.Stage.SECURITY_QUEUE, ENTRY + Vector2i(0, 2), false],
		[Passenger.Stage.SECURITY, EXIT, false],
		[Passenger.Stage.SECURITY_QUEUE, two + Vector2i(1, 0), false],
		[Passenger.Stage.TO_GATE, two, false],
		[Passenger.Stage.TO_SECURITY, two, false],
	]
	for c: Array in cases:
		var route: Array[Vector2i] = [c[1]]
		var p := _walker(id, c[0], route)
		p.station = w.station
		(
			assert_bool(BoothCarry.approaching(sim, p))
			. override_failure_message("stage %d at %s" % [c[0], c[1]])
			. is_equal(c[2])
		)
	# Another station chosen (or none): not this booth's approach.
	var other := _walker(id, Passenger.Stage.SECURITY_QUEUE, [two] as Array[Vector2i])
	assert_bool(BoothCarry.approaching(sim, other)).is_false()
	other.station = w.station + 1000
	assert_bool(BoothCarry.approaching(sim, other)).is_false()
	# Control: a lane's arch is no booth to approach.
	var lane := _make(true)
	var before_arch := SecurityTestWorld.ARCH_AT + Vector2i(0, 2)
	var q := _walker(id, Passenger.Stage.SECURITY_QUEUE, [before_arch] as Array[Vector2i])
	q.station = lane.station
	assert_bool(BoothCarry.approaching(lane.world.sim, q)).is_false()
