extends GdUnitTestSuite
## A lane returner's bags go into the tray on the walk up to the unpack cell,
## and it turns into the arch around that corner, so its hands, its bags and
## its body are along the arch's axis before it reaches the arch's entry
## (board 40d26b16). A returner (second pass, after a repack) does not stop at
## the unpack cell: it walks from the return route's end across the unpack
## cell into the arch. Its bags went in the tray (HAND to TRAY,
## SecurityLooks.bag_homes()) only once it stood on the unpack cell, and the
## hand-led move to the tray beside it ran on while the body walked into the
## arch: runner p15 on seed 1106001 --lane reached 0.636 m with a hand and
## 0.700 m with its shoulder bag across the 0.38 m half opening at z +0.392.
## The put-in and the turn are drawn by the distance walked (put_in_share(),
## return_walk_mm()), so a view drawn late draws what one drawn every frame
## does, and a change of the late flag never turns either back.

## How far (m, along the lane) from the arch cell's centre the body must still
## be when the bags are in the tray and it faces the arch: the probe's arch
## entry window ends 0.60 m out (basic_scanner_crossing_probe ENTRY_Z), and
## 0.05 m more is the margin.
const ENTRY_CLEAR_M := 0.65
## Two views at the same sim time draw the same bag and hand within this (m).
const SAME_M := 0.001
## A bag lies in its tray when drawn this near the tray's origin (m): a tray is
## about 0.6 m long and a bag's centre lies on its floor.
const IN_TRAY_M := 0.35

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


## A walking alarm passenger with two bags, drawn every tick: on its second
## pass, on every draw with the drawn body within ENTRY_CLEAR_M of the arch's
## centre (on its entry side), each bag lies in the tray, its move over and no
## hand on it. Controls: both bags were seen held in the move and in the tray,
## and draws near the arch were checked.
func test_walker_puts_its_bags_in_the_tray_before_the_arch() -> void:
	var seen := _watch_put_in(2, false)
	assert_int(seen["held"]).is_equal(2)
	assert_int(seen["settled"]).is_equal(2)
	assert_int(seen["near"]).is_greater(0)
	assert_int(seen["bad"]).is_equal(0)


## The same for a running alarm passenger with one bag (kept late every tick,
## as the lane probe keeps its runners): at about a metre a move, a move
## started on the unpack cell ended mid-arch.
func test_runner_puts_its_bag_in_the_tray_before_the_arch() -> void:
	var seen := _watch_put_in(1, true)
	assert_int(seen["held"]).is_equal(1)
	assert_int(seen["settled"]).is_equal(1)
	assert_int(seen["near"]).is_greater(0)
	assert_int(seen["bad"]).is_equal(0)


## A runner turns from across the lane to the arch's axis around the unpack
## cell's corner (SecurityLooks.setoff_yaw()), so on every tick of its arch
## walk within ENTRY_CLEAR_M of the arch's centre it faces the axis. Turned only
## once past the corner, runner p15 was 46 degrees off the axis at z +0.415.
## Controls: the turn was seen part way, and ticks near the arch were sampled.
func test_runner_faces_the_arch_before_its_entry() -> void:
	var w := _make()
	var p := w.world.passenger(w.send_all([[1, false, true]])[0])
	var arch := w.world.grid.cell_to_world(SecurityTestWorld.ARCH_AT)
	var axis := atan2(0.0, -1.0)
	var turning := 0
	var near := 0
	var worst := 0.0
	for n in 3000:
		p.late = true
		w.world.step()
		if w.cleared.has(p.id):
			break
		var yaw := SecurityLooks.setoff_yaw(w.world.sim, p)
		if is_nan(yaw) or is_nan(SecurityLooks.return_walk_mm(w.world.sim, p)):
			continue
		var off := absf(rad_to_deg(angle_difference(yaw, axis)))
		turning += int(off > 1.0 and off < 89.0)
		var z := absf(w.world.sim.world_position(p).z - arch.z)
		if z <= ENTRY_CLEAR_M:
			near += 1
			worst = maxf(worst, off)
	print("turning ticks %d, ticks near the arch %d, worst %.2f deg" % [turning, near, worst])
	assert_int(turning).is_greater(0)
	assert_int(near).is_greater(0)
	assert_float(worst).is_less(1.0)


## A view first drawn part way through a returner's put-in (a new view, or
## after a load) draws the same bags and hands as a view drawn on every tick,
## at the same sim time: the same move, not the bag already in the tray (Sol
## review of 893d5cc). Two worlds of one seed; one is drawn every tick, the
## other first on the tick its put-in is half way, both late in that tick.
## Control: the move was under way (share between 0 and 1) and a bag was held.
func test_a_view_first_drawn_mid_put_in_draws_the_same_bags_and_hands() -> void:
	var every := _make()
	var late := _make()
	var a := every.world.passenger(every.send_all([[2, false, true]])[0])
	var b := late.world.passenger(late.send_all([[2, false, true]])[0])
	var views_a := _views_of(every)
	var share := 0.0
	for n in 3000:
		every.world.step()
		late.world.step()
		views_a.draw()
		var past := SecurityLooks.return_walk_mm(every.world.sim, a)
		if not is_nan(past) and SecurityLooks.put_in_share(past) >= 0.5:
			share = SecurityLooks.put_in_share(past)
			break
	assert_float(share).is_between(0.5, 0.99)
	var views_b := _views_of(late)
	# Synced as a load syncs it (PassengerViews.snap()), on this tick.
	views_b.snap()
	_draw_late(every, views_a)
	_draw_late(late, views_b)
	var held := 0
	var apart := 0.0
	var body_a := views_a.node_for(a.id)
	var body_b := views_b.node_for(b.id)
	var props_a := views_a.carry_on_props()
	var props_b := views_b.carry_on_props()
	var bags_a: Array = props_a.props_of(a.id)["bags"]
	var bags_b: Array = props_b.props_of(b.id)["bags"]
	assert_int(bags_b.size()).is_equal(bags_a.size())
	for i in bags_a.size():
		var at_a := (bags_a[i] as Node3D).global_position
		var at_b := (bags_b[i] as Node3D).global_position
		apart = maxf(apart, at_a.distance_to(at_b))
		held += int(int(props_a.bag_state(a.id, i).get("held_by", -1)) >= 0)
		print(
			(
				"bag %d: every tick %s k %.3f, first drawn now %s k %.3f"
				% [
					i,
					at_a,
					float(props_a.bag_state(a.id, i).get("placed_k", -1.0)),
					at_b,
					float(props_b.bag_state(b.id, i).get("placed_k", -1.0))
				]
			)
		)
	for hand in 2:
		apart = maxf(
			apart, props_a.grip_of(body_a, hand).distance_to(props_b.grip_of(body_b, hand))
		)
	print("put-in share %.2f, bags held %d, widest gap %.5f m" % [share, held, apart])
	assert_int(held).is_greater(0)
	assert_float(apart).is_less(SAME_M)


## A runner whose late flag clears at any tick of its approach never has a bag
## go back from the tray to the hand, and turns only toward the arch's axis:
## the put-in and the turn are read from the distance walked, not the pace
## (Sol review of 893d5cc: read from the pace, the bags went back to the hand
## and the body turned back). One world per tick the flag clears on, from the
## arch walk's first tick on. Control: every world turned and put its bag in.
func test_a_late_flag_that_clears_never_turns_the_put_in_or_the_turn_back() -> void:
	var flips := 0
	for clear_at in 12:
		var w := _make()
		var p := w.world.passenger(w.send_all([[1, false, true]])[0])
		var axis := atan2(0.0, -1.0)
		var walked := -1
		var was: Array = SecurityLooks.bag_homes(w.world.sim, p)
		var back := 0
		var turned_back := 0
		var last_off := INF
		var in_tray := 0
		for n in 3000:
			if walked < clear_at:
				p.late = true
			w.world.step()
			if w.cleared.has(p.id):
				break
			if is_nan(SecurityLooks.return_walk_mm(w.world.sim, p)):
				continue
			walked += 1
			var now: Array = SecurityLooks.bag_homes(w.world.sim, p)
			for i in mini(now.size(), was.size()):
				back += int(was[i] == SecurityLooks.Home.TRAY and now[i] == SecurityLooks.Home.HAND)
				in_tray += int(
					was[i] == SecurityLooks.Home.HAND and now[i] == SecurityLooks.Home.TRAY
				)
			was = now
			var yaw := SecurityLooks.setoff_yaw(w.world.sim, p)
			if not is_nan(yaw):
				var off := absf(angle_difference(yaw, axis))
				turned_back += int(off > last_off + 1e-6)
				last_off = off
		print(
			(
				(
					"late clears after %d arch-walk ticks: back to the hand %d, into the tray"
					+ " %d, turned back %d, last off %.3f rad"
				)
				% [clear_at, back, in_tray, turned_back, last_off]
			)
		)
		assert_int(back).is_equal(0)
		assert_int(turned_back).is_equal(0)
		assert_int(in_tray).is_equal(1)
		assert_float(last_off).is_less(0.01)
		flips += 1
	assert_int(flips).is_equal(12)


func _make() -> SecurityTestWorld:
	var w := SecurityTestWorld.make(true)
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


## Sends one alarm passenger with `bags` bags through the lane (kept late when
## `late`), drawn every tick, and watches its second pass: each bag drawn held
## by a hand in its move to the tray ("held", once per bag), and each that then
## lies settled in the tray (its move over, CarryOnProps.transfer_progress 1,
## and drawn within IN_TRAY_M of the drawn tray), with how far the body is
## from the arch's centre along the lane on that tick ("settled_at"). Prints each.
func _watch_put_in(bags: int, late: bool) -> Dictionary:
	var w := _make()
	var p := w.world.passenger(w.send_all([[bags, false, true]])[0])
	var views := _views_of(w)
	var props := views.carry_on_props()
	var arch := w.world.grid.cell_to_world(SecurityTestWorld.ARCH_AT)
	var held := {}
	var settled := {}
	var settled_at: Array[float] = []
	var near := 0
	var bad := 0
	for n in 3000:
		if late:
			p.late = true
		w.world.step()
		views.draw()
		if w.cleared.has(p.id):
			break
		var second := p.incident_resolved and p.security_phase == SecurityRuntime.Phase.ARCH
		if not second:
			continue
		var homes := SecurityLooks.bag_homes(w.world.sim, p)
		# The body as drawn, which the drawn hand and bag go with.
		var off := views.node_for(p.id).global_position.z - arch.z
		for i in homes.size():
			if homes[i] != SecurityLooks.Home.TRAY:
				continue
			var held_by := int(props.bag_state(p.id, i).get("held_by", -1))
			if held_by >= 0:
				held[i] = true
			var tray: Node3D = props.props_of(p.id)["tray"]
			var bag: Node3D = props.props_of(p.id)["bags"][i]
			var to_tray := (
				INF if tray == null else bag.global_position.distance_to(tray.global_position)
			)
			var k := props.transfer_progress(p.id, i)
			var in_tray := k >= 1.0 and held_by < 0 and to_tray < IN_TRAY_M
			if in_tray and not settled.has(i):
				settled[i] = true
				settled_at.append(off)
				print(
					"bag %d in the tray at tick %d, drawn %.3f m out" % [i, w.world.clock.tick, off]
				)
			if off >= 0.0 and off <= ENTRY_CLEAR_M:
				near += 1
				if not in_tray:
					bad += 1
					print(
						(
							"bag %d at %.3f m: k %.2f held_by %d to_tray %.3f"
							% [i, off, k, held_by, to_tray]
						)
					)
	print(
		(
			"late %s: held %d, in the tray %d first at %s m, draws near the arch %d, not in the tray %d"
			% [late, held.size(), settled.size(), settled_at, near, bad]
		)
	)
	assert_bool(w.cleared.has(p.id)).is_true()
	return {"held": held.size(), "settled": settled.size(), "near": near, "bad": bad}
