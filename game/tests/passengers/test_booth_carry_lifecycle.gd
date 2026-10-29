class_name TestBoothCarryLifecycle
extends GdUnitTestSuite
## The carry lifecycle around a basic scanner booth and a lane's arch, tick by
## tick through the real sim and views (BoothCarry, CarryOnProps; board item
## pre-existing-carry-self-clips-found-by-game-spike-basic-scan): a queued
## roller is lifted in the approach and, when its station closes before it
## reaches the booth, goes back to the pull without ever tucking; a first
## walker coming straight in turns a step before the entry and has its roller
## in hand before the turn; a lane passenger tucks its arms through the arch.
##
## The world is SecurityTestWorld's basic scanner on (5, 5) (entry (5, 7),
## booth (5, 6) and (5, 5)) or its lane rooted at the arch on (5, 6).

const ENTRY := Vector2i(5, 7)
const BOOTH_FIRST := Vector2i(5, 6)

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


func _views_of(w: SecurityTestWorld) -> PassengerViews:
	var views := PassengerViews.new()
	views.clock = w.world.clock
	views.sim = w.world.sim
	add_child(views)
	_views.append(views)
	return views


## Sends a one-bag passenger whose first bag is (`roller`) or is not a roller;
## a spawned passenger of the other kind is cleared and sent on to the gate
## instead (with no way there past security, it stays out of the queue).
func _send_kind(w: SecurityTestWorld, roller: bool, alarm := false) -> int:
	for i in 40:
		var id := w.send(1, false, alarm)
		var p := w.world.passenger(id)
		if (SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER) == roller:
			return id
		p.cleared = true
		p.stage = Passenger.Stage.TO_GATE
	return -1


## One tick of the world, then the views drawn.
func _tick(w: SecurityTestWorld, views: PassengerViews) -> void:
	w.world.step()
	views.draw()


## A roller waiting in the queue two cells out is lifted into the hand there
## (BoothCarry.approaching(), before in_booth_passage() holds) with its arms
## still swinging; its station then closes (the officer is fired while the
## passenger ahead is served), it is sent back and leaves the approach area
## before any tuck: the turn back to the side ends, the roller goes back to the
## pull and that move finishes, and the arms never tuck.
func test_a_queued_roller_lifts_in_the_approach_and_leaves_it_before_any_tuck() -> void:
	var w := _make(false)
	var views := _views_of(w)
	var props := views.carry_on_props()
	var sim := w.world.sim
	# The first is served long (an alarm repack holds the booth), the second
	# waits at the entry, the roller behind it two cells out.
	var ids: Array[int] = [_send_kind(w, false, true)]
	w.world.run_to(w.world.clock.tick + SecurityTestWorld.SPACING)
	ids.append(_send_kind(w, false))
	w.world.run_to(w.world.clock.tick + SecurityTestWorld.SPACING)
	var id := _send_kind(w, true)
	assert_int(id).is_greater(0)
	var p := w.world.passenger(id)
	var lift_seen := false
	var lifted_waiting := 0
	var tuck_max := 0.0
	for i in 1500:
		_tick(w, views)
		tuck_max = maxf(tuck_max, props.tuck_of(id))
		var carries: Array = props.props_of(id)["carries"]
		if carries.is_empty() or carries[0] != SecurityLooks.Carry.HAND:
			continue
		lift_seen = lift_seen or props.transfer_progress(id, 0) < 1.0
		var only_approach := (
			BoothCarry.approaching(sim, p) and not SecurityLooks.in_booth_passage(sim, p)
		)
		if only_approach and not p.is_moving() and props.transfer_progress(id, 0) >= 1.0:
			lifted_waiting += 1
			if lifted_waiting >= 10:
				break
	print(
		(
			"queued roller %d at %s stage %d: lift seen=%s lifted waiting=%d tuck max=%.2f"
			% [id, p.at, p.stage, lift_seen, lifted_waiting, tuck_max]
		)
	)
	assert_bool(lift_seen).is_true()
	assert_int(lifted_waiting).is_greater_equal(10)
	assert_float(tuck_max).is_equal(0.0)
	# The station closes: no other officer is sent in its place.
	w.world.auto_staff = false
	assert_bool(w.world.staff.fire(StaffMember.Role.SECURITY)).is_true()
	var left_at := -1
	var lowered_seen := false
	var pulled_at := -1
	for i in 1500:
		_tick(w, views)
		tuck_max = maxf(tuck_max, props.tuck_of(id))
		if left_at < 0 and not BoothCarry.approaching(sim, p):
			left_at = w.world.clock.tick
		if left_at < 0:
			continue
		var carries: Array = props.props_of(id)["carries"]
		if carries.is_empty() or carries[0] != SecurityLooks.Carry.PULL:
			continue
		lowered_seen = lowered_seen or props.transfer_progress(id, 0) < 1.0
		if lowered_seen and props.transfer_progress(id, 0) >= 1.0:
			pulled_at = w.world.clock.tick
			break
	print(
		(
			(
				"after closing: left the approach at tick %d (stage %d, in booth passage %s),"
				+ " back on the pull at %d, front %.2f, tuck max %.2f"
			)
			% [
				left_at,
				p.stage,
				SecurityLooks.in_booth_passage(sim, p),
				pulled_at,
				props.front_weight_of(id),
				tuck_max
			]
		)
	)
	assert_int(left_at).is_greater(0)
	assert_bool(SecurityLooks.in_booth_passage(sim, p)).is_false()
	assert_bool(lowered_seen).is_true()
	assert_int(pulled_at).is_greater(left_at)
	assert_float(props.front_weight_of(id)).is_equal(0.0)
	assert_float(tuck_max).is_equal(0.0)


## A first walker coming straight in (no queue, so it is still on its way to
## security as it reaches the entry): its roller is lifted into the hand from
## the step before the entry, while it is on its way, and that move ends before
## the turn to the front starts. A first walker with a hard case has turned to
## the front before it is 1.6 m from the booth's centre, one with a roller
## before 1.4 m (the entry-end panels are 0.92 m out; a case was still turning
## 1.4 m out, and a roller lifted only at the entry), and carries in front in
## the booth's first cell. Control: each was seen at every distance from 2.6 m
## in, so the check covers the walk-up.
func test_a_first_walker_turns_before_the_entry_with_its_roller_already_in_hand() -> void:
	for roller in [true, false]:
		var w := _make(false)
		var views := _views_of(w)
		var props := views.carry_on_props()
		var sim := w.world.sim
		var id := _send_kind(w, roller)
		var p := w.world.passenger(id)
		var centre := (
			(
				sim.grid.cell_to_world(BOOTH_FIRST)
				+ sim.grid.cell_to_world(BOOTH_FIRST + Vector2i(0, -1))
			)
			* 0.5
		)
		var lift_stage := -1
		var turning_while_lifting := 0
		var nearest_turning := INF
		var farthest_seen := 0.0
		var front_at_booth := -1.0
		for i in 1500:
			_tick(w, views)
			var out := sim.world_position(p).distance_to(centre)
			if p.stage > Passenger.Stage.SECURITY or (p.at.y < BOOTH_FIRST.y):
				break
			if p.at == BOOTH_FIRST:
				front_at_booth = props.front_weight_of(id)
			farthest_seen = maxf(farthest_seen, out) if out <= 2.6 else farthest_seen
			var carries: Array = props.props_of(id)["carries"]
			var moving_bag := props.transfer_progress(id, 0) < 1.0
			if roller and lift_stage < 0 and moving_bag and carries[0] == SecurityLooks.Carry.HAND:
				lift_stage = p.stage
			var front := props.front_weight_of(id)
			if roller and moving_bag and front > 0.0:
				turning_while_lifting += 1
			if front > 0.0 and front < 1.0:
				nearest_turning = minf(nearest_turning, out)
		print(
			(
				(
					"first walker roller=%s: lift began at stage %d, turning while lifting %d,"
					+ " nearest turning %.2f m, seen from %.2f m"
				)
				% [roller, lift_stage, turning_while_lifting, nearest_turning, farthest_seen]
			)
		)
		print("  front weight in the booth's first cell: %.2f" % front_at_booth)
		assert_float(farthest_seen).is_greater(2.4)
		assert_float(nearest_turning).is_less(INF)
		# It reached the booth, carrying in front.
		assert_float(front_at_booth).is_equal(1.0)
		if roller:
			assert_int(lift_stage).is_equal(Passenger.Stage.TO_SECURITY)
			assert_int(turning_while_lifting).is_equal(0)
			# The lift comes first, so its turn ends later (1.5 m measured).
			assert_float(nearest_turning).is_greater(1.4)
		else:
			assert_float(nearest_turning).is_greater(1.6)


## A lane passenger without bags tucks both free arms through the arch: part
## way on several ticks first (no snap), fully in while it stands in the arch
## cell, and off again once it has walked on. Control: it reached the arch.
func test_a_lane_passenger_tucks_its_arms_through_the_arch() -> void:
	var w := _make(true)
	var views := _views_of(w)
	var props := views.carry_on_props()
	var ids := w.send_all([[0, false, false]])
	var id := ids[0]
	var p := w.world.passenger(id)
	var partway_before_full := 0
	var full := false
	var full_in_arch := 0
	var in_arch := 0
	var off_after := false
	for i in 3000:
		_tick(w, views)
		var tuck := props.tuck_of(id)
		if not full and tuck > 0.0 and tuck < 1.0:
			partway_before_full += 1
		full = full or tuck == 1.0
		if p.at == SecurityTestWorld.ARCH_AT:
			in_arch += 1
			if tuck == 1.0:
				full_in_arch += 1
		if in_arch > 0 and not SecurityLooks.in_arch_passage(w.world.sim, p) and tuck == 0.0:
			off_after = true
			break
	print(
		(
			(
				"arch tuck: in the arch %d ticks, fully tucked there %d, part way before full %d,"
				+ " off after %s"
			)
			% [in_arch, full_in_arch, partway_before_full, off_after]
		)
	)
	assert_int(in_arch).is_greater(0)
	assert_int(full_in_arch).is_equal(in_arch)
	assert_int(partway_before_full).is_greater(1)
	assert_bool(off_after).is_true()
