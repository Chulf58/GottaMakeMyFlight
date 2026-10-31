class_name TestCarryLaneLifecycle
extends GdUnitTestSuite
## Carry-on props through a security lane, tick by tick through the real sim
## and views (CarryOnProps; decision carry-on-bags-stay-in-the-hand-during-
## every-move-no-overhead): a tray stays at its table while a bag moves out of
## it and goes back after, also when its passenger loses the lane with its bags
## in the tray (finished, or sent back); a pooled body released in the middle
## of a hand-led move keeps no reach or stoop for the next passenger it draws;
## every roller lifted at security hangs by its grip bar; a roller going
## between the hand and the pull goes round the hand's side only at security.
##
## The world is SecurityTestWorld's lane rooted at the arch on (5, 6).

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


func _make() -> SecurityTestWorld:
	var w := SecurityTestWorld.make(true)
	_worlds.append(w)
	return w


func _views_of(w: SecurityTestWorld) -> PassengerViews:
	var views := PassengerViews.new()
	views.clock = w.world.clock
	views.sim = w.world.sim
	add_child(views)
	_views.append(views)
	return views


## One tick of the world, then the views drawn.
func _tick(w: SecurityTestWorld, views: PassengerViews) -> void:
	w.world.step()
	views.draw()


## Sends a passenger with `bags` bags whose first is a roller; one of another
## kind is cleared and sent on to the gate instead.
func _send_roller(w: SecurityTestWorld, bags := 1) -> int:
	for i in 40:
		var id := w.send(bags)
		var p := w.world.passenger(id)
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			return id
		p.cleared = true
		p.stage = Passenger.Stage.TO_GATE
	return -1


## Where a tray at `at` (IN or OUT) stands on `lane`, from the kit mount.
func _mount(w: SecurityTestWorld, lane: Dictionary, at: SecurityLooks.Tray) -> Transform3D:
	var mount: Array = CarryTray.TRAY_MOUNTS[at]
	return CarryOnProps.mount_world(w.world.sim.grid, lane, mount[0], mount[1])


## After pickup the tray stays on the pickup table while a bag moves out of it
## to the hand, and goes back once no bag moves. Control: frames with the tray
## kept were seen, and the bag did move out.
func test_a_tray_stays_at_its_table_while_a_bag_moves_out_and_goes_back_after() -> void:
	var w := _make()
	var views := _views_of(w)
	var props := views.carry_on_props()
	var sim := w.world.sim
	var id := w.send(2)
	var p := w.world.passenger(id)
	var lane := {}
	var kept := 0
	var off_table := 0.0
	var given_back := false
	for i in 3000:
		_tick(w, views)
		if lane.is_empty():
			lane = SecurityLooks.lane_of(sim, p)
		var tray: Node3D = props.props_of(id)["tray"]
		if tray == null:
			given_back = kept > 0
			if given_back:
				break
			continue
		if SecurityLooks.tray(sim, p) != SecurityLooks.Tray.NONE:
			continue
		kept += 1
		var at := _mount(w, lane, SecurityLooks.Tray.OUT)
		off_table = maxf(off_table, tray.global_position.distance_to(at.origin))
		var moving := props.transfer_progress(id, 0) < 1.0 or props.transfer_progress(id, 1) < 1.0
		assert_bool(moving).is_true()
	print("tray kept %d frames after pickup, %.4f m off the table at most" % [kept, off_table])
	assert_int(kept).is_greater(0)
	assert_float(off_table).is_less(0.001)
	assert_bool(given_back).is_true()


## A lane passenger whose bags are in the tray loses the lane (it is finished
## as missed, or sent back): the tray stays where it was on the tray table while
## the bags move out of it and then goes back, and the passenger behind it is
## still drawn every frame. Before the fix the lane was gone: each draw hit a
## script error at the tray (gdUnit counts it against the case) and the
## finished passenger's tray was drawn 1.06 m off the table.
func test_finished_or_sent_back_with_bags_in_the_tray() -> void:
	for send_back in [false, true]:
		var w := _make()
		var views := _views_of(w)
		var props := views.carry_on_props()
		var sim := w.world.sim
		var id := w.send(2)
		w.world.run_to(w.world.clock.tick + SecurityTestWorld.SPACING)
		var behind := w.send(1)
		var p := w.world.passenger(id)
		var lane := {}
		for i in 3000:
			_tick(w, views)
			var st: Dictionary = props.bag_state(id, 0)
			if (
				p.stage == Passenger.Stage.SECURITY
				and int(st.get("home", -1)) >= 0
				and int(st["home"]) / 4 == SecurityLooks.Home.TRAY
				and props.transfer_progress(id, 0) >= 1.0
			):
				lane = SecurityLooks.lane_of(sim, p)
				break
		assert_bool(lane.is_empty()).is_false()
		var tray_at := SecurityLooks.tray(sim, p)
		assert_int(tray_at).is_equal(SecurityLooks.Tray.IN)
		var bag := props.props_of(id)["bags"][0] as Node3D
		var in_tray := bag.global_position
		if send_back:
			# Out of its queue and its lane's record, as a station that goes.
			sim._leave_station(p)
			sim._send_back(p)
		else:
			sim._finish(p, false)
		var kept := 0
		var off_table := 0.0
		var given_back := false
		var bag_moved := 0.0
		var drawn_from := props.draws_of(behind)
		for i in 60:
			_tick(w, views)
			bag_moved = maxf(bag_moved, bag.global_position.distance_to(in_tray))
			# Only the tray kept from before (a passenger sent back may be let in
			# again and given a tray anew).
			if given_back or SecurityLooks.tray(sim, p) != SecurityLooks.Tray.NONE:
				continue
			var tray: Node3D = props.props_of(id)["tray"]
			if tray != null:
				kept += 1
				var at := _mount(w, lane, tray_at)
				off_table = maxf(off_table, tray.global_position.distance_to(at.origin))
			elif kept > 0:
				given_back = true
		var behind_draws := props.draws_of(behind) - drawn_from
		print(
			(
				(
					"%s: tray kept %d frames (%.4f m off the table), given back %s, bag moved %.2f m,"
					+ " the passenger behind drawn %d times in 60 frames"
				)
				% [
					"sent back" if send_back else "finished",
					kept,
					off_table,
					given_back,
					bag_moved,
					behind_draws
				]
			)
		)
		assert_int(kept).is_greater(0)
		assert_float(off_table).is_less(0.001)
		assert_bool(given_back).is_true()
		assert_float(bag_moved).is_greater(0.2)
		assert_int(behind_draws).is_equal(60)


## A passenger whose hand reaches low for a bag (stooping) is released from
## the views: its pooled body has no stoop targets and neither arm reaches.
## A bag-less passenger drawn by the same body then has none either. Control:
## the stoop was engaged before the release, and the body was reused.
func test_a_body_released_mid_move_keeps_no_stoop_or_reach() -> void:
	var w := _make()
	var views := _views_of(w)
	var props := views.carry_on_props()
	var id := w.send(1, false, true)
	var body: Node3D = null
	for i in 3000:
		_tick(w, views)
		var node := views.node_for(id)
		if node == null or not node.has_meta(&"carry_rig"):
			continue
		var stoop: CarryStoop = node.get_meta(&"carry_rig")["stoop"]
		if not stoop.targets.is_empty() and stoop.targets[0].y < 0.5:
			body = node
			print(
				(
					"stooping at tick %d: targets %s weights %s, move %.2f"
					% [
						w.world.clock.tick,
						stoop.targets,
						stoop.weights,
						props.transfer_progress(id, 0)
					]
				)
			)
			break
	assert_object(body).is_not_null()
	var rig: Dictionary = body.get_meta(&"carry_rig")
	views._release(id)
	_assert_no_reach(rig, "released")
	w.world.passenger(id).stage = Passenger.Stage.MADE
	# Nodes are pooled per body (PassengerLooks): the first later passenger drawn
	# with this body takes the node; others are sent away unseen.
	var variant: int = body.get_meta(&"variant")
	var other := w.send(0)
	while PassengerLooks.body_of(other, variant) != body.get_meta(&"body"):
		w.world.passenger(other).stage = Passenger.Stage.MADE
		other = w.send(0)
	w.world.passenger(other).variant = variant
	for i in 10:
		_tick(w, views)
	assert_object(views.node_for(other)).is_same(body)
	_assert_no_reach(rig, "reused bag-less")


func _assert_no_reach(rig: Dictionary, when: String) -> void:
	var stoop: CarryStoop = rig["stoop"]
	var weights: Array[float] = []
	for arm: CarryArm in rig["arms"]:
		weights.append(arm.reach_weight)
	print("%s: stoop targets %s, reach weights %s" % [when, stoop.targets, weights])
	assert_array(stoop.targets).is_empty()
	assert_array(stoop.weights).is_empty()
	assert_array(stoop.sides).is_empty()
	assert_array(weights).is_equal([0.0, 0.0])


## Every roller lifted into the hand at security hangs by its grip bar
## (by_bar), every frame of its lift. Control: lifted rollers were seen.
func test_every_lifted_roller_hangs_by_its_bar() -> void:
	var w := _make()
	var views := _views_of(w)
	var props := views.carry_on_props()
	var ids: Array[int] = []
	for n in 3:
		ids.append(_send_roller(w, 1 + n % 2))
		w.world.run_to(w.world.clock.tick + SecurityTestWorld.SPACING)
	var lifted := 0
	var off_bar := 0
	for i in 2500:
		_tick(w, views)
		for id in ids:
			var drawn: Dictionary = props.props_of(id)
			for b in (drawn["kinds"] as Array).size():
				if drawn["kinds"][b] != SecurityLooks.Kind.ROLLER:
					continue
				if drawn["carries"][b] != SecurityLooks.Carry.HAND:
					continue
				lifted += 1
				if not props.bag_state(id, b).get("by_bar", false):
					off_bar += 1
		if ids.all(func(x: int) -> bool: return w.cleared.has(x)):
			break
	print("lifted roller frames %d, not by the bar %d" % [lifted, off_bar])
	assert_int(lifted).is_greater(10)
	assert_int(off_bar).is_equal(0)


## A roller going between the hand and the pull (a swap, held by its bar) goes
## round the hand's side at security and swings out SWAP_OUT_M elsewhere.
## Midway at security its drawn axle is CarryLead.swap_axle() of the hung and
## trailing axles plus half the palm offset (BAR_PALM_M), on the hand's side of
## the body; the same move drawn without the security flag puts the axle
## somewhere else. Every swap seen has the flag set exactly while its walker is
## at security. Control: a swap at security was seen. Changed for board item
## 5ed915b0: this test pinned a security swing SWAP_OPEN_M (0.2 m) wider than
## the narrow one, and that swing still put the roller behind the shins of a
## walker standing at a lane (crossing probe, lane mode); its first rewrite
## checked only a distance from the body that the narrow swing also passed.
func test_the_wide_swap_route_applies_only_at_security() -> void:
	var w := _make()
	var views := _views_of(w)
	var props := views.carry_on_props()
	var id := _send_roller(w)
	var p := w.world.passenger(id)
	var at_security := 0
	var elsewhere := 0
	var off := NAN
	var side := NAN
	var apart := NAN
	for i in 2500:
		_tick(w, views)
		var held: Dictionary = props._held.get(id, {})
		if held.is_empty() or not props.bag_state(id, 0).get("swap", false):
			continue
		if props.transfer_progress(id, 0) >= 1.0:
			continue
		var security := p.stage in [Passenger.Stage.SECURITY_QUEUE, Passenger.Stage.SECURITY]
		assert_bool(held.get("security", false)).is_equal(security)
		if not security:
			elsewhere += 1
			continue
		at_security += 1
		if is_nan(off):
			var body := views.node_for(id)
			var drawn: Transform3D = props._swap_transform(held, body, 0, 0.5)[0]
			held["security"] = false
			var narrow: Transform3D = props._swap_transform(held, body, 0, 0.5)[0]
			held["security"] = true
			var axle := drawn * CarryOnProps.ROLLER_AXLE
			var want := _swap_axle_midway(props, held, body)
			off = axle.distance_to(want)
			var frame := Transform3D(Basis(Vector3.UP, body.rotation.y), body.global_position)
			# +x is the body's left: the right hand (0) is on -x.
			side = (frame.affine_inverse() * axle).x * (-1.0 if held["hands"][0] == 0 else 1.0)
			apart = axle.distance_to(narrow * CarryOnProps.ROLLER_AXLE)
		if w.cleared.has(id):
			break
	print(
		(
			(
				"swap frames at security %d, elsewhere %d; midway the drawn axle is %.4f m from"
				+ " swap_axle's, %.4f m out on the hand's side, %.4f m from the narrow swing's"
			)
			% [at_security, elsewhere, off, side, apart]
		)
	)
	assert_int(at_security).is_greater(0)
	assert_float(off).is_less(0.001)
	assert_float(side).is_greater(0.0)
	assert_float(apart).is_greater(0.01)


## Where the axle of the swapping roller (bag 0) of `held` drawn on `body` is
## midway (t 0.5) at security: CarryLead.swap_axle() between its axle hung
## under the grip and its trailing axle, moved out half of BAR_PALM_M on the
## hand's side (CarryOnProps._swap_transform).
func _swap_axle_midway(props: CarryOnProps, held: Dictionary, body: Node3D) -> Vector3:
	var bag: Dictionary = held["bags"][0]
	var scale_by: float = held["scale"]
	var hand: int = held["hands"][0]
	var grip := props.grip_of(body, hand)
	var trailing: Vector3
	if bag["carry"] == SecurityLooks.Carry.PULL:
		trailing = bag.get("axle_now", Vector3.INF)
		if not trailing.is_finite():
			trailing = props._axle_drawn(bag, body, scale_by, hand)
	else:
		trailing = body.global_transform * ((bag["from"] as Transform3D) * CarryOnProps.ROLLER_AXLE)
	var hung := props._hung_axle(bag, grip, scale_by)
	var frame := Transform3D(Basis(Vector3.UP, body.rotation.y), body.global_position)
	var axle := CarryLead.swap_axle(frame, hung, trailing, 0.5, hand, CarryOnProps.SWING_RADIUS_M)
	return axle + CarryOnProps._outward(body, hand) * CarryOnProps.BAR_PALM_M * 0.5
