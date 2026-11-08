class_name TestLaneSetoffTurn
extends GdUnitTestSuite
## A lane passenger turns from the tray table back to the arch's axis before
## its first strides into the arch (SecurityLooks.setoff_yaw(),
## setting_off(); board bcad1dd0, finding
## why-does-the-body-reach-past-the-security-lane-arch-s-0-38-m): drawn with
## its walk heading by the arch's entry, its step to the table eased out, and
## the same yaw and offset for a view first drawn mid-turn as for one drawn on
## every tick (anti-pattern view-state-stepped-on-from-the-previous-draw-makes-
## a-carry-p). A returner's second pass and the basic scanner are left alone.
##
## The world is SecurityTestWorld's lane rooted at the arch on (5, 6).

## Walked from the unpack centre, where the widest feet were measured before:
## 0.40 m on, in front of the posts (0.70 m on).
const WIDE_FROM_MM := 400
## Radians: the same yaw.
const SAME_RAD := 0.01

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


func _make(use_lane := true) -> SecurityTestWorld:
	var w := SecurityTestWorld.make(use_lane)
	_worlds.append(w)
	return w


func _views_of(w: SecurityTestWorld) -> PassengerViews:
	var views := PassengerTestWorld.views()
	views.clock = w.world.clock
	views.sim = w.world.sim
	add_child(views)
	_views.append(views)
	return views


## Draws `views` near the end of the tick interval (no tick runs), where a
## view drawn on every tick and one first drawn on this tick meet.
func _draw_late(w: SecurityTestWorld, views: PassengerViews) -> void:
	w.world.clock.advance(SimClock.STEP * 0.999)
	views.draw()
	w.world.clock._accumulator = 0.0


func _axis_yaw(sim: PassengerSim, p: Passenger) -> float:
	var axis := -Vector2(SecurityLooks.lane_of(sim, p)["front"])
	return atan2(axis.x, axis.y)


func _walked_mm(p: Passenger) -> int:
	return p.seg_mm + p.path_index * Passenger.STRAIGHT_MM


## Through UNPACK and the arch walk of a walker: it turns most of the way to
## the tray table, and by the arch's entry it is drawn with its walk heading
## and its step to the table eased out; no tick turns it more than a smoothstep
## turn's steepest tick. Control: it did face toward the table, and it did walk
## to the entry.
func test_a_walker_faces_its_walk_heading_by_the_arch_entry() -> void:
	var w := _make()
	var views := _views_of(w)
	var sim := w.world.sim
	var id := w.send(1)
	var p := w.world.passenger(id)
	var most_off := 0.0
	var steepest := 0.0
	var last := NAN
	var at_entry := {}
	for i in 1500:
		w.world.step()
		views.draw()
		var node := views.node_for(id)
		if p.stage != Passenger.Stage.SECURITY:
			if p.stage > Passenger.Stage.SECURITY:
				break
			continue
		var phase := p.security_phase as SecurityRuntime.Phase
		if phase != SecurityRuntime.Phase.UNPACK and not SecurityLooks.setting_off(sim, p):
			continue
		_draw_late(w, views)
		var yaw := node.rotation.y
		if not is_nan(last):
			steepest = maxf(steepest, absf(angle_difference(last, yaw)))
		last = yaw
		most_off = maxf(most_off, absf(angle_difference(_axis_yaw(sim, p), yaw)))
		if at_entry.is_empty() and phase == SecurityRuntime.Phase.ARCH:
			if _walked_mm(p) >= WIDE_FROM_MM:
				var heading := views.walk_heading(p)
				at_entry = {
					"walked": _walked_mm(p),
					"off": absf(angle_difference(atan2(heading.x, heading.y), yaw)),
					"offset": views.security_offset(id).length(),
				}
	print(
		(
			"walker: most %.1f deg off the axis, steepest tick %.1f deg, at the entry %s"
			% [rad_to_deg(most_off), rad_to_deg(steepest), at_entry]
		)
	)
	assert_float(rad_to_deg(most_off)).is_greater(60.0)
	assert_bool(at_entry.is_empty()).is_false()
	assert_float(at_entry["off"]).is_less(SAME_RAD)
	assert_float(at_entry["offset"]).is_less(0.001)
	assert_float(rad_to_deg(steepest)).is_less(25.0)


## A view first drawn mid-turn (UNPACK's turn back, and ARCH's first strides)
## draws the same yaw, and in ARCH the same offset, as one drawn on every tick
## (a late first draw against a draw on every tick). Control: the two
## worlds put the passenger on the same spot, and the yaw is mid-turn (neither
## on the axis nor facing the table).
func test_a_view_first_drawn_mid_turn_draws_the_same_yaw_and_offset() -> void:
	var a := _make()
	var every := _views_of(a)
	var id := a.send(1)
	var p := a.world.passenger(id)
	var stops: Array[int] = []
	var wanted := [SecurityRuntime.Phase.UNPACK, SecurityRuntime.Phase.ARCH]
	for i in 1500:
		a.world.step()
		every.draw()
		if p.stage != Passenger.Stage.SECURITY or not wanted.has(p.security_phase):
			continue
		var turning_back := p.security_work < SecurityRuntime.LANE_UNPACK_BAG_TICKS
		var share := _table_share(a.world.sim, p)
		if turning_back and share > 0.05 and share < 0.95:
			stops.append(a.world.clock.tick)
			wanted.erase(p.security_phase)
		if wanted.is_empty():
			break
	assert_int(stops.size()).is_equal(2)
	# A view synced on every tick from the start, against one first synced at
	# the stop, each in a world of its own run to the stop.
	for stop in stops:
		var c := _make()
		var steady := _views_of(c)
		var cid := c.send(1)
		c.world.run_to(stop)
		var d := _make()
		var did := d.send(1)
		d.world.run_to(stop)
		var first := _views_of(d)
		first.sync()
		_draw_late(c, steady)
		_draw_late(d, first)
		var pc := c.world.passenger(cid)
		var pd := d.world.passenger(did)
		var yaw_c := steady.node_for(cid).rotation.y
		var yaw_d := first.node_for(did).rotation.y
		var apart := absf(angle_difference(yaw_c, yaw_d))
		var off_apart := steady.security_offset(cid).distance_to(first.security_offset(did))
		var share := _table_share(c.world.sim, pc)
		print(
			(
				"tick %d phase %d share %.2f: yaw %.4f and %.4f, %.5f rad apart, offsets %.5f m apart"
				% [stop, pc.security_phase, share, yaw_c, yaw_d, apart, off_apart]
			)
		)
		(
			assert_float(c.world.sim.world_position(pc).distance_to(d.world.sim.world_position(pd)))
			. is_less(0.0001)
		)
		assert_float(share).is_between(0.05, 0.95)
		assert_float(apart).is_less(0.001)
		# The step to the table at UNPACK is still walked from where it was
		# drawn (a new view steps out to it); from ARCH on it is set.
		if pc.security_phase == SecurityRuntime.Phase.ARCH:
			assert_float(off_apart).is_less(0.0001)


## How far `p`'s set-off yaw is turned from the axis toward the table, 0 to 1.
func _table_share(sim: PassengerSim, p: Passenger) -> float:
	var yaw := SecurityLooks.setoff_yaw(sim, p)
	if is_nan(yaw):
		return -1.0
	return absf(angle_difference(_axis_yaw(sim, p), yaw)) / (PI / 2.0)


## Steps `w` until its passenger `id` stands on the unpack cell as the queue
## front, not yet admitted, then makes it one that walked in from the side
## away from the tray table (its last path step toward the table), facing that
## way when `views` draws it. Returns whether that moment was reached.
func _enter_from_side(w: SecurityTestWorld, id: int, views: PassengerViews) -> bool:
	var sim := w.world.sim
	var p := w.world.passenger(id)
	var lane := sim.layout.security_lanes.lane(w.station)
	var unpack: Vector2i = lane["unpack"]
	var side: Vector2i = lane["side"]
	for i in 1500:
		w.world.step()
		if views != null:
			views.draw()
		if p.stage == Passenger.Stage.SECURITY:
			return false
		if p.stage == Passenger.Stage.SECURITY_QUEUE and p.at == unpack and not p.is_moving():
			var walked: Array[Vector2i] = [unpack - side, unpack]
			p.path = walked
			p.path_index = 1
			p.seg_mm = 0
			if views != null:
				views._turns.place(id, atan2(side.x, side.y))
			return true
	return false


## An empty lane walked into from the side: the body faces its walk as UNPACK
## begins and turns from there, never more in a tick (drawn one tick a frame)
## than a smoothstep turn's steepest tick, and a view first drawn during
## UNPACK's turn back draws the same yaw. Before, UNPACK's first tick drew the
## body near the arch's axis, 90 degrees from its walk in one tick. Control:
## the turn back did run (the yaw left the table by more than 30 degrees).
func test_a_side_entry_turns_smoothly_from_its_walk() -> void:
	var w := _make()
	var views := _views_of(w)
	var sim := w.world.sim
	var id := w.send(1)
	var p := w.world.passenger(id)
	assert_bool(_enter_from_side(w, id, views)).is_true()
	var side: Vector2i = sim.layout.security_lanes.lane(w.station)["side"]
	var table := atan2(side.x, side.y)
	# The yaw it was given for its walk in (the node is drawn with it next frame).
	var last := table
	var steepest := 0.0
	var off_table := 0.0
	var stop := -1
	for i in 60:
		w.world.step()
		_draw_late(w, views)
		var yaw := views.node_for(id).rotation.y
		steepest = maxf(steepest, absf(angle_difference(last, yaw)))
		off_table = maxf(off_table, absf(angle_difference(table, yaw)))
		last = yaw
		var turning_back := p.security_work < SecurityRuntime.LANE_UNPACK_BAG_TICKS
		if stop < 0 and p.security_phase == SecurityRuntime.Phase.UNPACK and turning_back:
			stop = w.world.clock.tick
		if p.security_phase == SecurityRuntime.Phase.ARCH and not SecurityLooks.setting_off(sim, p):
			break
	var other := _make()
	var other_id := other.send(1)
	assert_bool(_enter_from_side(other, other_id, null)).is_true()
	other.world.run_to(stop)
	var w2 := _make()
	var steady := _views_of(w2)
	var steady_id := w2.send(1)
	assert_bool(_enter_from_side(w2, steady_id, steady)).is_true()
	w2.world.run_to(stop)
	var first := _views_of(other)
	first.sync()
	_draw_late(other, first)
	_draw_late(w2, steady)
	var apart := absf(
		angle_difference(steady.node_for(steady_id).rotation.y, first.node_for(other_id).rotation.y)
	)
	print(
		(
			(
				"side entry: steepest tick %.1f deg, most %.1f deg off the table;"
				+ " first drawn at tick %d: %.5f rad apart"
			)
			% [rad_to_deg(steepest), rad_to_deg(off_table), stop, apart]
		)
	)
	assert_float(rad_to_deg(steepest)).is_less(25.0)
	assert_float(rad_to_deg(off_table)).is_greater(30.0)
	assert_int(stop).is_greater(0)
	assert_float(apart).is_less(0.001)


## A returner's second pass through the arch starts beside the unpack cell and
## is turned as any walker; at the basic scanner nothing sets off. Control: the
## returner did walk its second pass, and the scanner passenger was served.
func test_a_returner_and_the_basic_scanner_are_left_alone() -> void:
	var w := _make()
	var views := _views_of(w)
	var sim := w.world.sim
	var id := w.send(1, false, true)
	var p := w.world.passenger(id)
	var second := 0
	for i in 3000:
		w.world.step()
		views.draw()
		if p.stage > Passenger.Stage.SECURITY:
			break
		if p.incident_resolved and p.security_phase == SecurityRuntime.Phase.ARCH:
			second += 1
			assert_bool(SecurityLooks.setting_off(sim, p)).is_false()
			assert_bool(is_nan(SecurityLooks.setoff_yaw(sim, p))).is_true()
	var booth := _make(false)
	var booth_views := _views_of(booth)
	var bid := booth.send(1)
	var bp := booth.world.passenger(bid)
	var served := 0
	for i in 3000:
		booth.world.step()
		booth_views.draw()
		if bp.stage > Passenger.Stage.SECURITY:
			break
		if bp.stage == Passenger.Stage.SECURITY:
			served += 1
			assert_bool(SecurityLooks.setting_off(booth.world.sim, bp)).is_false()
			assert_bool(is_nan(SecurityLooks.setoff_yaw(booth.world.sim, bp))).is_true()
			assert_float(booth_views.security_offset(bid).length()).is_equal(0.0)
	print("returner second-pass ARCH ticks %d, scanner service ticks %d" % [second, served])
	assert_int(second).is_greater(0)
	assert_int(served).is_greater(0)
