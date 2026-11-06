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
## against the body (a snap into or out of the stand is 0.5 m or more). The cafe
## case's largest step measured 0.147 m on 26ce797, a margin of only 3 mm: a
## failure there just over JUMP_M may be that step grown, not a snap.
const JUMP_M := 0.15
## A tip watched up to and in the security queue (check-in, a boarding file, a gate
## standing spot; board 44b974cc) moves the bag less than this a frame against
## the body. These walkers often turn as they walk off (a check-in queue's
## bend, a gate spot facing away from the exit), and the turn (6 ticks,
## PassengerTurns) swings the bag round the body as the tip lifts it into the
## pull. The steps rise and fall in one smooth ease; peaks measured 2026-11-05
## (seed 1): 0.155 to 0.182 m stepping up a check-in place or walking off the
## desk, 0.195 m on a half turn in the check-in queue (the body's yaw 0.25 rad
## a frame), 0.168 m turning from a gate spot to the exit. With a 6-tick tip
## the check-in peak was still 0.159 m, so the pace is not the cause. A snap
## out of the stand is 0.5 m or more. A security-queue tip gets the same
## allowance (conductor ruling, 2026-11-05, board 34b0c378): with the queue
## ripple a walker tips its roller as it turns to step up, and the tip frames
## measured 0.173 to 0.201 m (seed 1) with the body turning 0.194 to 0.252 rad
## on the same frame, the check-in half turn's case.
const TIP_JUMP_M := 0.21
## Holding the stood roller the hips stay at least this share of their height
## standing idle just before the stand, and the stoop at most STOOP_EPS: with the
## bar at ROLL_RODS of the pull's length the guest held it with its knees bent
## (700ffaa).
const IDLE_SHARE := 0.99
const STOOP_EPS := 0.01
## Walkers sent through check-in and security together, so queues form.
const GUESTS_AT_DESKS := 5
## Any other move between two frames a third of a tick apart (test_roller_park).
const SNAP_M := 0.3

var _world: PassengerTestWorld
var _views: PassengerViews
var _guest: Passenger
## The walkers kept on time and whose clips are played by sim time (_tick()).
var _followed: Array[Passenger] = []


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
	_followed = []


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


## A stand refused at its stamp (here in a stall, parks() false) is asked for
## once a still spell, not again every TRANSFER_TICKS once the short move it left
## is over; walking and stopping again asks again (control). A swap's mark left
## on the settled roller is cleared by the ask, so the stand is hand-led.
func test_a_refused_stand_is_asked_for_once_a_still_spell() -> void:
	var bag := _pulled()
	bag["swap"] = true
	var now := 100.0
	for t in RollerPark.STILL_TICKS + 1:
		RollerPark.queue_stand(bag, ROLLER, true, now)
		now += 1.0
	assert_bool(RollerPark.restamps(bag)).is_true()
	assert_bool(CarryPlace.leads({}, bag)).is_true()
	bag["led"] = true
	bag["was"] = bag["home"]
	bag["carry_from"] = SecurityLooks.Carry.PULL
	CarryLead.stamp_move(bag, true, SecurityLooks.Home.HAND, Transform3D.IDENTITY)
	assert_bool(RollerPark.queued(bag)).is_false()
	assert_bool(RollerPark.restamps(bag)).is_false()
	var asks := 0
	for t in 60:
		RollerPark.queue_stand(bag, ROLLER, true, now)
		asks += int(RollerPark.restamps(bag))
		now += 1.0
	print("asks in 60 still ticks after a refusal: %d" % asks)
	assert_int(asks).is_equal(0)
	RollerPark.queue_stand(bag, ROLLER, false, now)
	for t in RollerPark.STILL_TICKS + 1:
		now += 1.0
		RollerPark.queue_stand(bag, ROLLER, true, now)
	assert_bool(RollerPark.restamps(bag)).is_true()


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


## The rods (RollerPark.queue_reach()): the pull's length at the start, the
## length that stands the bar QUEUE_BAR_M over the floor once stood (whatever
## the pull's length, at either bag scale), the pull's again by the tip's end.
## Replaces the rods case of 700ffaa, which pinned a share of the pull's length:
## the bar was then too low to reach standing (Opus review, posture).
func test_the_rods_stand_the_bar_at_its_height() -> void:
	var bag := {"park": true, "queue": true, "ticks": 50.0}
	var axle := CarryOnProps.ROLLER_AXLE
	var bar_in := 0.2
	var stood_k := (RollerPark.QUEUE_STAND_TICKS + 1.0) / 50.0
	for scale_by: float in [1.0, SecurityLooks.TWO_BAG_SCALE]:
		for pull: float in [0.83, 1.22]:
			var start := RollerPark.queue_reach(bag, 0.0, pull, bar_in, scale_by)
			var stood := RollerPark.queue_reach(bag, stood_k, pull, bar_in, scale_by)
			var bar_up: float = (axle.y + stood + bar_in - axle.z) * scale_by
			print(
				(
					"scale %.2f pull %.2f: rods %.3f to %.3f, bar %.3f m up"
					% [scale_by, pull, start, stood, bar_up]
				)
			)
			assert_float(start).is_equal_approx(pull, 0.001)
			assert_float(bar_up).is_equal_approx(RollerPark.QUEUE_BAR_M, 0.001)
	bag["queue_tip"] = 30.0
	bag["ticks"] = 30.0 + RollerPark.QUEUE_TIP_TICKS
	assert_float(RollerPark.queue_reach(bag, 1.0, 1.0, bar_in, 1.0)).is_equal_approx(1.0, 0.001)


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
			var hips := _hips(body)
			var stoop := _stoop(body)
			# Standing idle before the stand: the roller still settled in the pull.
			if (
				into >= 1
				and FloatCheck.move_of(props, p.id, 0) == ""
				and not RollerPark.queued(bag)
			):
				seen["idle_hips"] = maxf(seen.get("idle_hips", -1.0), hips)
			if into > RollerPark.STILL_TICKS + RollerPark.QUEUE_STAND_TICKS + 2:
				seen["stood_hips"] = minf(seen.get("stood_hips", INF), hips)
				seen["stood_stoop"] = maxf(seen.get("stood_stoop", 0.0), stoop)
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
	# Posture: standing straight holding the stood roller, as standing idle just
	# before (the hips no lower than IDLE_SHARE of that, no stoop drawn).
	var idle: float = seen.get("idle_hips", -1.0)
	var low: float = seen.get("stood_hips", -1.0)
	print(
		(
			"POSTURE idle hips %.3f m, lowest stood %.3f m, share %.3f (>= %.2f), stoop %.3f (<= %.2f)"
			% [
				idle,
				low,
				low / maxf(idle, 0.001),
				IDLE_SHARE,
				seen.get("stood_stoop", -1.0),
				STOOP_EPS
			]
		)
	)
	assert_float(idle).is_greater(0.5)
	assert_float(low / idle).is_greater_equal(IDLE_SHARE)
	assert_float(float(seen.get("stood_stoop", 1.0))).is_less_equal(STOOP_EPS)


## GUESTS_AT_DESKS walkers with one roller each through the reference
## terminal's check-in and security, drawn every third of a tick: stood up at
## the check-in desk or in its queue, and (where the security queue held one
## still long enough) in the security queue; through SECURITY_QUEUE into
## SECURITY no FLOAT frame, no jump over JUMP_M against the body, and the
## roller lifted into the hand in SECURITY as before (CarryOnProps._lifted()).
## The FLOAT and jump watch starts in the check-in queue, so the check-in
## stands and tips are watched too.
func test_walkers_stand_rollers_up_at_check_in_and_security_then_lift_them() -> void:
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	_world.clock.ticked.connect(_keep_on_time)
	while _followed.size() < GUESTS_AT_DESKS:
		var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		if SecurityLooks.bag_kind(p, 0) != ROLLER:
			p.carry_on = 0
			continue
		ToiletTestLayout.calm(p)
		p.carry_on = 1
		p.liquids = false
		p.alarm = false
		_followed.append(p)
	var props := _views.carry_on_props()
	var seen := {}
	var fails: Array[String] = []
	var last := {}
	var last_queued := {}
	var watch := {}
	for p in _followed:
		seen[p.id] = {"checkin_stood": 0, "security_stood": 0, "security_still": 0, "lifted": 0}
	var sent := false
	while _world.clock.tick < 3000 and _followed.any(_before_gate):
		await _tick(1.0 / 3.0)
		if not sent:
			sent = _send_to_security(seen)
		for p in _followed:
			var body := _views.node_for(p.id)
			if body == null or props.props_of(p.id).get("bags", []).is_empty():
				continue
			var node: Node3D = props.props_of(p.id)["bags"][0]
			var bag := props.bag_state(p.id, 0)
			var mine: Dictionary = seen[p.id]
			var up := node.global_transform.basis.z.normalized().dot(Vector3.UP)
			var stood := RollerPark.queued(bag) and up >= UPRIGHT_DOT
			if stood and p.stage in [Passenger.Stage.CHECKIN_QUEUE, Passenger.Stage.CHECKIN]:
				mine["checkin_stood"] += 1
			if p.stage == Passenger.Stage.SECURITY_QUEUE:
				mine["security_stood"] += int(stood)
				# Still with its roller in the pull and not turned to the front: the rule's own
				# exclusions (a walker at a booth's queue front has it lifted).
				var front: bool = props._held[p.id].get("front", false)
				var pulled: bool = bag.get("carry", -1) == SecurityLooks.Carry.PULL
				var still := RollerPark.queue_still(_world.sim, p) and pulled and not front
				mine["still_run"] = int(mine.get("still_run", 0)) + 1 if still else 0
				var needed := (RollerPark.STILL_TICKS + RollerPark.QUEUE_STAND_TICKS + 2) * 3
				mine["security_still"] += int(mine["still_run"] > needed)
			# Watched from the check-in queue (or the security queue, for a walker
			# sent there) to 30 ticks into SECURITY.
			var queueing := (
				p.stage
				in [
					Passenger.Stage.CHECKIN_QUEUE,
					Passenger.Stage.CHECKIN,
					Passenger.Stage.SECURITY_QUEUE,
				]
			)
			if queueing and not watch.has(p.id):
				watch[p.id] = INF
			if p.stage == Passenger.Stage.SECURITY and float(watch.get(p.id, -INF)) == INF:
				watch[p.id] = _world.clock.tick + 30.0
			if not watch.has(p.id) or _world.clock.tick > float(watch[p.id]):
				continue
			if (
				p.stage == Passenger.Stage.SECURITY
				and bag.get("carry", -1) == SecurityLooks.Carry.HAND
			):
				mine["lifted"] += 1
			var tag := (
				"id %d tick %d stage %d move %s"
				% [p.id, _world.clock.tick, p.stage, FloatCheck.move_of(props, p.id, 0)]
			)
			var state := FloatCheck.float_state(_world.sim, _views, p.id, 0)
			if state[0] == "float":
				fails.append("%s FLOAT %s" % [tag, state])
			var rel := node.global_position - body.global_position
			# JUMP_M for a queue stand; any other move SNAP_M (test_roller_park's): the
			# lift into the hand at a booth's queue front steps 0.164 m a frame with
			# the queue stand off too (STILL_TICKS 100000, same ticks and values).
			var limit := JUMP_M if RollerPark.queued(bag) or last_queued.has(p.id) else SNAP_M
			var tipping := (
				bag.has("queue_tip") or (last_queued.has(p.id) and not RollerPark.queued(bag))
			)
			if tipping and p.stage <= Passenger.Stage.SECURITY_QUEUE:
				limit = TIP_JUMP_M
			if last.has(p.id) and rel.distance_to(last[p.id]) > limit:
				fails.append(
					"%s bag jumped %.3f against the body" % [tag, rel.distance_to(last[p.id])]
				)
			last[p.id] = rel
			if RollerPark.queued(bag):
				last_queued[p.id] = true
			else:
				last_queued.erase(p.id)
	print("check-in and security: %s" % [seen])
	for line in fails.slice(0, 10):
		print(line)
	assert_array(fails).is_empty()
	var checkin := 0
	var lifted := 0
	var still := 0
	var security := 0
	for id: int in seen:
		checkin += int(seen[id]["checkin_stood"] > 0)
		lifted += int(seen[id]["lifted"] > 0)
		still += int(seen[id]["security_still"] > 0)
		security += int(seen[id]["security_stood"] > 0)
	assert_int(checkin).is_greater(0)
	assert_int(lifted).is_equal(watch.size())
	assert_int(watch.size()).is_greater(0)
	# Every walker held still long enough in the security queue stood its roller up,
	# and some were (else the line above passes on 0 >= 0).
	assert_int(still).is_greater(0)
	assert_int(security).is_greater_equal(still)


## Once the first walker is through check-in, GUESTS_AT_DESKS more walkers with
## a roller each set off for security together from where it stands, so the
## security queue holds some still (checked in one at a time, the first batch
## reached it apart). Returns whether they were sent.
func _send_to_security(seen: Dictionary) -> bool:
	var first: Passenger = null
	for p in _followed:
		if p.stage == Passenger.Stage.TO_SECURITY:
			first = p
	if first == null:
		return false
	var sent := 0
	while sent < GUESTS_AT_DESKS:
		var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		if SecurityLooks.bag_kind(p, 0) != ROLLER:
			p.carry_on = 0
			continue
		ToiletTestLayout.calm(p)
		p.carry_on = 1
		p.liquids = false
		p.alarm = false
		p.apron = []
		p.apron_mm = 0
		p.stage = Passenger.Stage.TO_SECURITY
		p.stage_tick = _world.clock.tick
		p.at = first.at
		p.clear_path()
		_followed.append(p)
		seen[p.id] = {"checkin_stood": 0, "security_stood": 0, "security_still": 0, "lifted": 0}
		sent += 1
	return true


## Whether `p` has not yet passed security (still on its way to the gate).
func _before_gate(p: Passenger) -> bool:
	return p.stage < Passenger.Stage.TO_GATE


## The hips (the carry rig's pivot, Spine_01) over the feet of `body`.
static func _hips(body: Node3D) -> float:
	var rig: Dictionary = body.get_meta(&"carry_rig", {})
	if rig.is_empty():
		return -1.0
	return (rig["pivot"] as Node3D).global_position.y - body.global_position.y


## The stoop CarryStoop drew last on `body` (0 to 1).
static func _stoop(body: Node3D) -> float:
	var rig: Dictionary = body.get_meta(&"carry_rig", {})
	return (rig["stoop"] as CarryStoop).drawn if rig.has("stoop") else 0.0


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
	_followed = [p]
	_world.clock.ticked.connect(_keep_on_time)
	while p.stage != Passenger.Stage.TO_GATE and _world.clock.tick < 900:
		_world.step()
	await _tick(1.0)
	assert_bool(_world.sim.cafes.try_visit(p)).is_true()
	return p


## Kept on time: a late walker lifts its roller into the hand.
func _keep_on_time(_tick_now: int) -> void:
	for p in _followed:
		p.late = false


## One frame `ticks` sim ticks on, as test_roller_park draws them, the followed
## walkers' clips played by the same sim time (headless, by the frame's own
## time, they hardly move, and a walker that stops is still drawn mid-stride).
func _tick(ticks: float) -> void:
	_world.clock.advance(SimClock.STEP * ticks)
	for p in _followed:
		var body := _views.node_for(p.id)
		if body == null:
			continue
		var player := body.get_node("AnimationPlayer") as AnimationPlayer
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		player.advance(SimClock.STEP * ticks)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()
