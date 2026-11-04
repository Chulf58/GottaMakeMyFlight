class_name TestRollerQueueStand
extends GdUnitTestSuite
## A walker pulling a roller that stands still in a queue stands it upright
## beside it, held by the bar, and tips it back into the pull to walk on
## (decision a-guest-standing-still-in-a-queue-stands-the-roller-up-beside-them,
## board 3dc86b54; RollerPark.queue_stand()). The move's record is pinned on
## its own (asked for after RollerPark.STILL_TICKS, kept on while still, tipped
## on walking, the rods part out while it stands), and a hungry guest with a
## roller is followed through a cafe's queue and order to its seat as the game
## draws it: stood up beside it while it orders, in the pull again walking to
## its seat, and the bag held or resting on every frame (spike/
## carry_float_check.gd's FLOAT check).

const FloatCheck := preload("res://spike/carry_float_check.gd")
const ROLLER := SecurityLooks.Kind.ROLLER
## A roller stood up: its own +z (the shell's length) this close to straight up.
const UPRIGHT_DOT := 0.95
## Stood up beside the body: its axle at most this far from the feet, level.
const BESIDE_M := 0.6
## In the pull its axle trails at least this far behind (CarryOnProps
## TRAIL_BEHIND_MIN_M 0.95, less the frame's slack).
const TRAILS_M := 0.8
## Between two frames a third of a tick apart the bag moves less than this
## against the body (a snap into or out of the stand is 0.5 m or more).
const JUMP_M := 0.15

var _world: PassengerTestWorld
var _views: PassengerViews
var _guest: Passenger


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_world.free_all()
	_views = null
	_world = null
	_guest = null


## A roller's record settled in the right hand's pull since tick 0.
static func _pulled() -> Dictionary:
	var place := (SecurityLooks.Home.HAND * 2 + 0) * 2
	return {
		"kind": ROLLER,
		"place": place,
		"home": place,
		"carry": SecurityLooks.Carry.PULL,
		"settled": true,
		"since": 0.0,
		"changed": 0.0,
	}


## `bag` stamped as CarryOnProps stamps the move it asked for at `now`.
func _stamped(bag: Dictionary, now: float) -> void:
	bag["led"] = true
	bag["was"] = bag["home"]
	bag["carry_from"] = SecurityLooks.Carry.PULL
	bag["since"] = bag["changed"]
	CarryLead.stamp_move(bag, false, SecurityLooks.Home.HAND, Transform3D.IDENTITY)
	assert_float(float(bag["since"])).is_equal(now)


func test_a_stand_is_asked_for_after_still_ticks_of_standing() -> void:
	var bag := _pulled()
	for t in RollerPark.STILL_TICKS:
		RollerPark.queue_stand(bag, ROLLER, true, 100.0 + t)
		assert_bool(RollerPark.restamps(bag)).is_false()
	RollerPark.queue_stand(bag, ROLLER, true, 100.0 + RollerPark.STILL_TICKS)
	print("asked for at tick %.0f, changed %.0f" % [100.0 + RollerPark.STILL_TICKS, bag["changed"]])
	assert_bool(RollerPark.restamps(bag)).is_true()
	assert_float(float(bag["changed"])).is_equal(100.0 + RollerPark.STILL_TICKS)


## A walker stepping up one place (moving again before STILL_TICKS) asks for
## none, and its count starts again.
func test_a_short_stop_asks_for_no_stand() -> void:
	var bag := _pulled()
	for t in 30:
		RollerPark.queue_stand(bag, ROLLER, t % RollerPark.STILL_TICKS != 0, 100.0 + t)
		assert_bool(RollerPark.restamps(bag)).is_false()


## Only a roller settled in the pull asks: not one lifted, mid-move, on the
## floor, or of another kind.
func test_only_a_settled_pulled_roller_asks() -> void:
	var cases := {}
	var lifted := _pulled()
	lifted["place"] = int(lifted["place"]) + 1
	lifted["home"] = lifted["place"]
	cases["lifted"] = lifted
	var moving := _pulled()
	moving["settled"] = false
	cases["moving"] = moving
	var floor_bag := _pulled()
	floor_bag["place"] = SecurityLooks.Home.FLOOR * 4
	floor_bag["home"] = floor_bag["place"]
	cases["floor"] = floor_bag
	var case_bag := _pulled()
	case_bag["kind"] = SecurityLooks.Kind.CASE
	cases["case"] = case_bag
	for name: String in cases:
		var bag: Dictionary = cases[name]
		var kind: SecurityLooks.Kind = bag["kind"]
		for t in RollerPark.STILL_TICKS + 3:
			RollerPark.queue_stand(bag, kind, true, 100.0 + t)
		print("%s asks %s" % [name, RollerPark.restamps(bag)])
		assert_bool(RollerPark.restamps(bag)).is_false()
	# Control: the pulled one does.
	var pulled := _pulled()
	for t in RollerPark.STILL_TICKS + 3:
		RollerPark.queue_stand(pulled, ROLLER, true, 100.0 + t)
	assert_bool(RollerPark.restamps(pulled)).is_true()


## Stamped, the move is a queue stand from the pull to the pull (a parking move,
## its home and hand held), kept on while the walker stands, and tipped on the
## first tick it walks on, the move then ending with the tip.
func test_the_stand_is_kept_while_still_and_tips_on_walking() -> void:
	var bag := _pulled()
	var now := 100.0
	for t in RollerPark.STILL_TICKS + 1:
		RollerPark.queue_stand(bag, ROLLER, true, now)
		now += 1.0
	now -= 1.0
	_stamped(bag, now)
	assert_bool(RollerPark.queued(bag)).is_true()
	assert_bool(RollerPark.restamps(bag)).is_false()
	assert_bool(RollerPark._parking(bag, ROLLER, now + 1.0)).is_true()
	for t in 200:
		now += 1.0
		RollerPark.queue_stand(bag, ROLLER, true, now)
	var at := now - float(bag["since"])
	print("standing %.0f ticks, move %.1f ticks" % [at, CarryLead.ticks_of(bag)])
	assert_float(CarryLead.ticks_of(bag)).is_greater(at + 1.0)
	assert_bool(bag.has("queue_tip")).is_false()
	now += 1.0
	RollerPark.queue_stand(bag, ROLLER, false, now)
	at = now - float(bag["since"])
	assert_float(float(bag["queue_tip"])).is_equal(at)
	assert_float(CarryLead.ticks_of(bag)).is_equal_approx(at + RollerPark.QUEUE_TIP_TICKS, 0.001)
	# Decided for good: standing again does not stand it up again mid-tip.
	RollerPark.queue_stand(bag, ROLLER, true, now + 1.0)
	assert_float(float(bag["queue_tip"])).is_equal(at)
	assert_bool(RollerPark.restamps(bag)).is_false()


## Unchanged: a pull>pull move asked for by nobody is no parking move.
func test_a_pull_to_pull_move_not_asked_for_does_not_park() -> void:
	var bag := _pulled()
	bag["led"] = true
	bag["was"] = bag["home"]
	bag["carry_from"] = SecurityLooks.Carry.PULL
	assert_bool(RollerPark.parks(bag, false, SecurityLooks.Home.HAND)).is_false()
	bag["queue_still"] = true
	assert_bool(RollerPark.parks(bag, false, SecurityLooks.Home.HAND)).is_true()
	# In a toilet stall never.
	assert_bool(RollerPark.parks(bag, true, SecurityLooks.Home.HAND)).is_false()


## The rods (from in to the pull's length): all out at the start, QUEUE_RODS of
## the way once stood, all out again by the tip's end.
func test_the_rods_are_part_out_while_it_stands() -> void:
	var bag := {"park": true, "queue": true, "ticks": 50.0}
	var start := RollerPark.rods_t(0.0, bag)
	var stood := RollerPark.rods_t((RollerPark.QUEUE_STAND_TICKS + 1.0) / 50.0, bag)
	bag["queue_tip"] = 30.0
	bag["ticks"] = 30.0 + RollerPark.QUEUE_TIP_TICKS
	var tipped := RollerPark.rods_t(1.0, bag)
	print("rods start %.3f stood %.3f tipped %.3f" % [start, stood, tipped])
	assert_float(start).is_equal_approx(1.0, 0.001)
	assert_float(stood).is_equal_approx(RollerPark.QUEUE_RODS, 0.001)
	assert_float(tipped).is_equal_approx(1.0, 0.001)


## A hungry guest with a roller in a cafe, drawn every third of a tick: walking
## to the counter in the pull (control), stood up beside it, upright and held,
## while it orders, in the pull again once it walks to its seat, and never a
## FLOAT frame on the way.
func test_a_cafe_guest_stands_its_roller_up_to_order_and_pulls_it_on() -> void:
	var p := await _cafe_guest()
	var props := _views.carry_on_props()
	var seen := {"walk_pulled": 0, "order_frames": 0, "stood": 0, "repulled": 0, "frames": 0}
	var fails: Array[String] = []
	var order_from := -1
	var walk_from := -1
	var order_end := -1
	var last_rel := Vector3.ZERO
	var worst := 0.0
	var worst_at := ""
	while _world.clock.tick < 2000 and p.stage != Passenger.Stage.CAFE_SITTING_DOWN:
		await _tick(1.0 / 3.0)
		var body := _views.node_for(p.id)
		if body == null or props.props_of(p.id).get("bags", []).is_empty():
			continue
		seen["frames"] += 1
		var node: Node3D = props.props_of(p.id)["bags"][0]
		var bag := props.bag_state(p.id, 0)
		var state := FloatCheck.float_state(_world.sim, _views, p.id, 0)
		if state[0] == "float":
			fails.append("tick %d stage %d FLOAT %s" % [_world.clock.tick, p.stage, state])
		var on := FloatCheck.grip_on_gap(props, p.id, 0, body)
		if int(bag.get("held_by", -1)) >= 0 and on[0] > on[1]:
			fails.append(
				"tick %d stage %d GRIP_ON %.3f > %.3f" % [_world.clock.tick, p.stage, on[0], on[1]]
			)
		# Against the body: a walker walking carries the bag about 0.03 m a frame.
		var rel := node.global_position - body.global_position
		if seen["frames"] > 1 and rel.distance_to(last_rel) > JUMP_M:
			fails.append(
				(
					"tick %d stage %d bag jumped %.3f against the body, move %s"
					% [
						_world.clock.tick,
						p.stage,
						rel.distance_to(last_rel),
						FloatCheck.move_of(props, p.id, 0)
					]
				)
			)
		if seen["frames"] > 1 and rel.distance_to(last_rel) > worst:
			worst = rel.distance_to(last_rel)
			var move := FloatCheck.move_of(props, p.id, 0)
			worst_at = "tick %d stage %d move %s" % [_world.clock.tick, p.stage, move]
		last_rel = rel
		var up := node.global_transform.basis.z.normalized().dot(Vector3.UP)
		var axle := node.global_transform * CarryOnProps.ROLLER_AXLE
		var flat := Vector2(axle.x - body.global_position.x, axle.z - body.global_position.z)
		var settled := props.transfer_progress(p.id, 0) >= 1.0
		var pulled := settled and up < 0.8 and flat.length() > TRAILS_M
		if p.stage == Passenger.Stage.CAFE_WALK and pulled:
			seen["walk_pulled"] += 1
		if p.stage == Passenger.Stage.CAFE_ORDER:
			if order_from < 0:
				order_from = _world.clock.tick
			order_end = _world.clock.tick
			seen["order_frames"] += 1
			var into := _world.clock.tick - order_from
			var held := int(bag.get("held_by", -1)) >= 0
			if into > RollerPark.STILL_TICKS + RollerPark.QUEUE_STAND_TICKS + 2:
				if up >= UPRIGHT_DOT and flat.length() <= BESIDE_M and held:
					seen["stood"] += 1
				else:
					fails.append(
						(
							"tick %d ordering %d ticks: up %.3f beside %.3f held %s move %s"
							% [
								_world.clock.tick,
								into,
								up,
								flat.length(),
								held,
								FloatCheck.move_of(props, p.id, 0)
							]
						)
					)
		if p.stage == Passenger.Stage.CAFE_TO_SEAT:
			if walk_from < 0:
				walk_from = _world.clock.tick
			if _world.clock.tick - walk_from > RollerPark.QUEUE_TIP_TICKS + 2 and pulled:
				seen["repulled"] += 1
	print(
		(
			"cafe guest %d: %s, order ticks %d to %d, largest step against the body %.3f m (%s)"
			% [p.id, seen, order_from, order_end, worst, worst_at]
		)
	)
	for line in fails.slice(0, 10):
		print(line)
	assert_array(fails).is_empty()
	# Controls: it was seen pulled walking in, and ordering long enough to stand.
	assert_int(seen["walk_pulled"]).is_greater(0)
	assert_int(order_end - order_from).is_greater(RollerPark.STILL_TICKS + 12)
	assert_int(seen["stood"]).is_greater(0)
	assert_int(seen["repulled"]).is_greater(0)


## A guest with one roller, committed to the cafe on its way to the gate.
func _cafe_guest() -> Passenger:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, 0) != ROLLER:
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.carry_on = 1
	p.hunger = 0
	p.cafe_cooldown = 1000000
	_guest = p
	_world.clock.ticked.connect(_keep_on_time)
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 900:
		_world.step()
	await _tick(1.0)
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	return p


## Kept on time: a late walker lifts its roller into the hand.
func _keep_on_time(_tick_now: int) -> void:
	if _guest != null:
		_guest.late = false


## One frame `ticks` sim ticks on, as test_roller_park draws them.
func _tick(ticks: float) -> void:
	_world.clock.advance(SimClock.STEP * ticks)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()
