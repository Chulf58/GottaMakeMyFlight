class_name TestActivityBags
extends GdUnitTestSuite
## Carry-on bags of an activity visitor (decision
## activity-poses-sit-on-the-lounge-sofa-recline-in-the-nap-pod, board item
## e9a2fdaf): on the lounge sofa and in the nap pod they are set down on the
## floor beside the seat once the visitor is on it and picked up as it steps
## off; at the shower they stand outside the cubicle door from the step in to
## the end of the stay and are picked up as it walks off. Checked on
## SecurityLooks.bag_homes over whole stays, and on the drawn bags
## (CarryOnProps through PassengerViews): on the floor, clear of the piece's
## body, the shower's bags clear of its door and the walk in, fixed in the
## world while the body steps about and after a snap, and held or resting on
## every drawn frame of the set-down and the pick-up (the probes' FLOAT and
## GRIP_ON checks, spike/carry_float_check.gd).

const FloatCheck := preload("res://spike/carry_float_check.gd")
const TYPES: Array[StringName] = [&"lounge", &"nap_pod", &"shower"]
const PIECES := {&"lounge": &"lounge_sofa", &"nap_pod": &"nap_pod", &"shower": &"shower_cubicle"}
## Sim ticks per drawn frame while a bag moves, as a game drawn faster than it
## ticks (two frames a tick).
const MOVE_FRAME_TICKS := 0.5
## Ticks drawn after the stage ends, for the pick-up.
const AFTER_TICKS := 16
## A bag this close to the piece's body (metres) counts as touching it.
const CLEAR_M := 0.02
## Half the width of the shower's walk in at a standing bag's height (0.5 m at
## most), from its middle line: the legs stepping in or out pass through here
## (the hands swing above a bag that low).
const WALK_IN_HALF_M := 0.17
## The cubicle's front face (its door), out from its middle (shower_cubicle.glb).
const SHOWER_FRONT_M := 0.42
## How far a resting bag may drift while the visitor stays (metres).
const STILL_M := 0.001

var _world: PassengerTestWorld
var _views: PassengerViews
var _ids: Dictionary


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	_free()


func _free() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.free_all()
		_world = null


func _open(type: StringName, drawn: bool) -> void:
	_free()
	var grid := BuildGrid.new()
	_ids = ActivityTestLayout.build(grid, type)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	_world.run_to(10)
	if not drawn:
		return
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	# The test runs the pre-draw fallback itself at the end of each frame.
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)


## A bored guest with `count` bags, the last of `kind` (any when -1), that
## commits to the room's piece, run to the first tick of its stay. Guests whose
## last bag is of another kind are left airside, not bored.
func _visitor(count: int, kind := -1) -> Passenger:
	var p := ShopTestLayout.airside_guest(_world, 0)
	while kind >= 0 and SecurityLooks.bag_kind(p, count - 1) != kind:
		p = ShopTestLayout.airside_guest(_world, 0)
	p.boredom = 80
	p.carry_on = count
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	assert_object(_world.sim.shops.visit_of(p.id)).is_not_null()
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < 3000:
		if _views != null:
			await _frame(1.0)
		else:
			_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
	return p


## One frame `ticks` sim ticks on, as the game draws them.
func _frame(ticks: float) -> void:
	_world.clock.advance(SimClock.STEP * ticks)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()


## The room piece's body bounds in the world (its .glb meshes, placed as
## BuildView places it).
func _piece_box(type: StringName) -> AABB:
	var record := _world.sim.grid.get_object(_ids["use"])
	var def := BuildCatalog.get_def(record["def"])
	var frame := BuildView.object_transform(
		_world.sim.grid, def.footprint(record["anchor"], record["facing"]), record["facing"]
	)
	var scene := (load("res://assets/interior/%s.glb" % PIECES[type]) as PackedScene).instantiate()
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := mi.transform
		var parent := mi.get_parent()
		while parent != null and parent != scene:
			xf = (parent as Node3D).transform * xf
			parent = parent.get_parent()
		var b := frame * xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	scene.free()
	return box


## The piece's frame: at its middle, +z out of its front.
func _piece_frame() -> Transform3D:
	var record := _world.sim.grid.get_object(_ids["use"])
	var out := TerminalLayout.front_of(record["facing"])
	var def := BuildCatalog.get_def(record["def"])
	var frame := BuildView.object_transform(
		_world.sim.grid, def.footprint(record["anchor"], record["facing"]), record["facing"]
	)
	return Transform3D(Basis(Vector3.UP, atan2(out.x, out.y)), frame.origin)


## Over a whole stay at each piece, the bags are on the floor exactly while
## the visitor is on the seat (from SHUFFLE_TICKS into the stay, or from its
## start with a roller, to SHUFFLE_TICKS before its end) at the sofa and the
## pod, and for the whole stay
## at the shower; in hand before it and once it is over.
func test_bags_are_down_while_seated_and_for_the_whole_shower() -> void:
	for type in TYPES:
		for count in [1, 2]:
			_open(type, false)
			var p := await _visitor(count)
			var door := ActivityPoses.seat_door(_world.sim, p)
			var seen: Array = []
			while p.stage == Passenger.Stage.SHOP_BROWSE:
				seen.append(
					[_world.clock.tick - p.stage_tick, SecurityLooks.bag_homes(_world.sim, p)]
				)
				_world.step()
			var after := SecurityLooks.bag_homes(_world.sim, p)
			var stay := seen.size()
			var down := 0
			var wrong: Array = []
			for i in stay:
				var spent: int = seen[i][0]
				var left := stay - 1 - i
				# A roller is set down standing before the step onto the seat
				# (ActivityPoses.SEAT_DOOR_TICKS, board 76cb23c0).
				var stepped := spent >= ActivityPoses.SHUFFLE_TICKS or door > 0
				var on_seat := stepped and left >= ActivityPoses.SHUFFLE_TICKS
				var want := SecurityLooks.Home.FLOOR
				if type != &"shower" and not on_seat:
					want = SecurityLooks.Home.HAND
				if type == &"shower" and left < ActivityPoses.DOOR_OUT_TICKS:
					want = SecurityLooks.Home.HAND
				for home: SecurityLooks.Home in seen[i][1]:
					if home != want:
						wrong.append("spent %d left %d home %d want %d" % [spent, left, home, want])
				down += 1 if seen[i][1][0] == SecurityLooks.Home.FLOOR else 0
			print(
				(
					"%s %d bag(s): stay %d ticks, down %d, after %s, wrong %s"
					% [type, count, stay, down, after, wrong.slice(0, 4)]
				)
			)
			# Control: a stay long enough to sit, and bags down for part of it.
			assert_int(stay).is_greater(4 * ActivityPoses.SHUFFLE_TICKS)
			assert_int(down).is_greater(0)
			assert_array(wrong).is_empty()
			for home in after:
				assert_int(home).is_equal(SecurityLooks.Home.HAND)


## Drawn at the sofa: a roller alone (the largest bag, parked on its wheels on
## the way down and up, RollerPark), and a shoulder tote as the second of two.
func test_sofa_bags_are_set_down_beside_the_seat_and_picked_up() -> void:
	await _drawn_stay(&"lounge", 1, SecurityLooks.Kind.ROLLER)
	await _drawn_stay(&"lounge", 2, SecurityLooks.Kind.SHOULDER)


## Drawn at the nap pod: a hard case alone, and a roller as the second of two.
func test_pod_bags_are_set_down_beside_the_seat_and_picked_up() -> void:
	await _drawn_stay(&"nap_pod", 1, SecurityLooks.Kind.CASE)
	await _drawn_stay(&"nap_pod", 2, SecurityLooks.Kind.ROLLER)


## Drawn at the shower: a roller alone, and a backpack as the second of two.
func test_shower_bags_stand_outside_the_door_and_are_picked_up() -> void:
	await _drawn_stay(&"shower", 1, SecurityLooks.Kind.ROLLER)
	await _drawn_stay(&"shower", 2, SecurityLooks.Kind.BACKPACK)


## One stay drawn: each set-down bag stands on the floor clear of the sofa or
## pod (or, at the shower, outside the cubicle's door and clear of the walk
## in), beside the visitor's own seat, keeps its place while the visitor stays
## and over a snap, and is never in the air nor held off its grip from the
## set-down to the end of the pick-up.
func _drawn_stay(type: StringName, count: int, kind: SecurityLooks.Kind) -> void:
	_open(type, true)
	var label := "%s %d bag(s), last %s" % [type, count, SecurityLooks.Kind.keys()[kind]]
	var p := await _visitor(count, kind)
	var props := _views.carry_on_props()
	var piece := _piece_box(type)
	var frame := _piece_frame()
	var checks := {"frames": 0, "held": 0, "resting": 0, "float": [], "grip_off": []}
	# The set-down and the settle after it, two frames a tick.
	var settle := ActivityPoses.SHUFFLE_TICKS + int(RollerPark.TICKS_DOWN) + 2
	if type == &"shower":
		settle = ActivityPoses.DOOR_IN_TICKS + 1
	while _world.clock.tick - p.stage_tick < settle:
		await _frame(MOVE_FRAME_TICKS)
		_watch(p, checks)
	var placed := _placed_bags(p)
	for b in placed.size():
		var box: AABB = placed[b]
		var local: AABB = frame.affine_inverse() * box
		var slot := _world.sim.shops.visit_of(p.id).index
		var root := ActivityPoses.spot_of(_world.sim.grid, _piece_record(), slot)
		print(
			(
				"%s bag %d kind %d: box %s local %s piece %s"
				% [label, b, props.props_of(p.id)["kinds"][b], box, local, piece]
			)
		)
		assert_float(absf(box.position.y - _world.sim.grid.origin.y)).is_less(0.02)
		(
			assert_bool(piece.grow(CLEAR_M).intersects(box))
			. override_failure_message("%s: bag %d touches the piece" % [label, b])
			. is_false()
		)
		# Within the piece's own width: a wall can stand right beside it.
		var piece_local: AABB = frame.affine_inverse() * piece
		assert_float(local.position.x).is_greater_equal(piece_local.position.x)
		assert_float(local.end.x).is_less_equal(piece_local.end.x)
		if type == &"shower":
			assert_float(local.position.z).is_greater(SHOWER_FRONT_M + CLEAR_M)
			var clear := local.position.x > WALK_IN_HALF_M or local.end.x < -WALK_IN_HALF_M
			(
				assert_bool(clear)
				. override_failure_message("%s: bag %d in the walk in %s" % [label, b, local])
				. is_true()
			)
		else:
			# Beside its own seat: nearer it than the cell's width.
			var at := box.get_center()
			var from_seat := Vector2(at.x - root.x, at.z - root.z).length()
			assert_float(from_seat).is_less(0.7)
	var still := _bag_positions(p)
	# Stays put while the visitor stays: up to just before the step off
	# at the sofa and the pod, through the wash and the step out at the
	# shower (the body moving under it).
	var stop := ActivityPoses.SHUFFLE_TICKS
	if type == &"shower":
		stop = ActivityPoses.DOOR_OUT_TICKS
	while _ticks_left(p) > stop:
		await _frame(4.0 if _ticks_left(p) > stop + 8 else MOVE_FRAME_TICKS)
		_watch(p, checks)
	var drift := _drift(still, _bag_positions(p))
	_views.snap()
	await _frame(0.0)
	var snapped := _drift(still, _bag_positions(p))
	print("%s: drift %.4f, after a snap %.4f" % [label, drift, snapped])
	assert_float(drift).is_less(STILL_M)
	assert_float(snapped).is_less(STILL_M)
	# The pick-up and the walk off: each bag stays where it stood until a
	# hand takes it, while the body steps off or walks away.
	var end := -1
	var slide := {"most": 0.0, "frames": 0, "taken": {}}
	while end < 0 or _world.clock.tick - end < AFTER_TICKS:
		await _frame(MOVE_FRAME_TICKS)
		_watch(p, checks)
		_slide(p, still, slide)
		if end < 0 and p.stage != Passenger.Stage.SHOP_BROWSE:
			end = _world.clock.tick
	var slid := "%s: slide %.4f over %d frames before a hand took it"
	print(slid % [label, slide["most"], slide["frames"]])
	assert_int(int(slide["frames"])).is_greater(0)
	assert_int((slide["taken"] as Dictionary).size()).is_equal(count)
	assert_float(float(slide["most"])).is_less(STILL_M)
	print(
		(
			"%s: frames %d held %d resting %d float %s grip_off %s homes %s"
			% [
				label,
				checks["frames"],
				checks["held"],
				checks["resting"],
				(checks["float"] as Array).slice(0, 4),
				(checks["grip_off"] as Array).slice(0, 4),
				SecurityLooks.bag_homes(_world.sim, p)
			]
		)
	)
	# Controls: the bags were seen held and resting.
	assert_int(int(checks["held"])).is_greater(0)
	assert_int(int(checks["resting"])).is_greater(0)
	assert_array(checks["float"]).is_empty()
	assert_array(checks["grip_off"]).is_empty()
	for home in SecurityLooks.bag_homes(_world.sim, p):
		assert_int(home).is_equal(SecurityLooks.Home.HAND)


## Tallies in `slide` how far each bag of `p` has moved from where it stood
## (`still`) on the frames before a hand first holds it, once its pick-up is
## stamped ("most", "frames"; "taken" the bags a hand has held).
func _slide(p: Passenger, still: Array[Transform3D], slide: Dictionary) -> void:
	var props := _views.carry_on_props()
	var now := _bag_positions(p)
	for b in p.carry_on:
		var state := props.bag_state(p.id, b)
		if (slide["taken"] as Dictionary).has(b):
			continue
		if int(state.get("held_by", -1)) >= 0:
			slide["taken"][b] = true
			continue
		if int(state.get("place", -1)) / 4 != SecurityLooks.Home.HAND:
			continue
		slide["frames"] = int(slide["frames"]) + 1
		slide["most"] = maxf(slide["most"], still[b].origin.distance_to(now[b].origin))


## A visit cut short with its bags down (the piece taken away under the
## visitor): each bag is picked up from where it stood, not dragged with the
## body as it eases back to its cell, and never floats.
func test_bags_of_a_visit_cut_short_are_picked_up_where_they_stand() -> void:
	for type in [&"lounge", &"shower"]:
		_open(type, true)
		var p := await _visitor(1, SecurityLooks.Kind.CASE)
		var checks := {"frames": 0, "held": 0, "resting": 0, "float": [], "grip_off": []}
		while not ActivityPoses.bags_down(_world.sim, p) or _world.clock.tick - p.stage_tick < 40:
			await _frame(2.0)
		await _frame(MOVE_FRAME_TICKS)
		var still := _bag_positions(p)
		assert_bool(_world.sim.grid.apply(BuildEdit.remove_object(_ids["use"])).ok).is_true()
		var slide := {"most": 0.0, "frames": 0, "taken": {}}
		for i in 2 * AFTER_TICKS:
			await _frame(MOVE_FRAME_TICKS)
			_watch(p, checks)
			_slide(p, still, slide)
		print(
			(
				"%s cut short: stage %s, slide %.4f over %d frames, taken %s, float %s"
				% [
					type,
					Passenger.Stage.keys()[p.stage],
					slide["most"],
					slide["frames"],
					slide["taken"],
					checks["float"]
				]
			)
		)
		assert_int(int(slide["frames"])).is_greater(0)
		assert_int((slide["taken"] as Dictionary).size()).is_equal(1)
		assert_float(float(slide["most"])).is_less(STILL_M)
		assert_array(checks["float"]).is_empty()


## A nap pod visitor whose right side is closed (the room's wall beside its
## slot cell, as seated facing out) carries and sets down its one bag in the
## left hand, on the open side, from the start of the stay to its end: no
## change of hand, the same after a snap and after a save and load.
func test_a_closed_right_side_keeps_the_bag_in_the_left_hand() -> void:
	_open(&"nap_pod", true)
	# A wall on the west edge of the pod's slot cell: the right of a visitor
	# seated facing out (south). The east is open.
	var west := BuildGrid.SIDE_STEP.find(Vector2i(-1, 0))
	var slot := ActivityTestLayout.PIECES[&"nap_pod"][0][1] + Vector2i(0, 1)
	assert_bool(_world.sim.grid.apply(BuildEdit.place_wall(slot, west)).ok).is_true()
	assert_bool(_world.sim.grid.has_wall(slot, BuildGrid.SIDE_STEP.find(Vector2i(1, 0)))).is_false()
	var p := await _visitor(1)
	var root := ActivityPoses.stay_frame(_world.sim, p)
	var props := _views.carry_on_props()
	var hands := {}
	var save := ""
	while p.stage == Passenger.Stage.SHOP_BROWSE:
		await _frame(1.0)
		var place := int(props.bag_state(p.id, 0).get("place", -1))
		hands[SecurityLooks.hand_of(_world.sim, p, 0) * 10 + CarryLead.hand_of(place)] = true
		if save == "" and ActivityPoses.bags_down(_world.sim, p):
			await _frame(8.0)
			_views.snap()
			await _frame(0.0)
			place = int(props.bag_state(p.id, 0).get("place", -1))
			hands[SecurityLooks.hand_of(_world.sim, p, 0) * 10 + CarryLead.hand_of(place)] = true
			save = _snapshot()
			var spot := SecurityLooks.activity_floor(_world.sim, p, 1)[0]
			# The open side: left of the seated visitor, +x in its frame.
			assert_float((root.affine_inverse() * spot).origin.x).is_greater(0.0)
			_compare_loaded(save, p, spot)
	print("closed right: hands (sim * 10 + drawn) seen %s" % [hands.keys()])
	assert_str(save).is_not_empty()
	assert_array(hands.keys()).contains_exactly([11])


func _snapshot() -> String:
	return (
		JSON
		. stringify(
			{
				"clock": _world.clock.to_snapshot(),
				"flights": _world.flights.to_snapshot(),
				"grid": _world.grid.to_snapshot(),
				"passengers": _world.sim.to_snapshot(),
			}
		)
	)


## The world saved in `text`, loaded: passenger `p` there has the same hand
## and the same floor spot `spot`.
func _compare_loaded(text: String, p: Passenger, spot: Transform3D) -> void:
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var loaded := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(loaded.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(loaded.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(loaded.sim.from_snapshot(data["passengers"])).is_true()
	var q := loaded.sim.get_passenger(p.id)
	var spots := SecurityLooks.activity_floor(loaded.sim, q, 1)
	print("loaded: hand %d spot %s" % [SecurityLooks.hand_of(loaded.sim, q, 0), spots])
	assert_int(SecurityLooks.hand_of(loaded.sim, q, 0)).is_equal(1)
	assert_int(spots.size()).is_equal(1)
	assert_float(spots[0].origin.distance_to(spot.origin)).is_less(0.0001)
	loaded.free_all()


func _piece_record() -> Dictionary:
	return _world.sim.grid.get_object(_ids["use"])


## Ticks the stay of `p` has left (as ActivityPoses counts them), from its
## visit's end.
func _ticks_left(p: Passenger) -> int:
	if p.stage != Passenger.Stage.SHOP_BROWSE:
		return -1
	var visit := _world.sim.shops.visit_of(p.id)
	var room := _world.sim.grid.get_room(visit.room)
	var type := RoomTypes.get_type(room["type"])
	var end := mini(p.stage_tick + ShopSim.browse_ticks(type), visit.deadline)
	return end - 1 - _world.clock.tick


## The FLOAT and GRIP_ON checks on each bag of `p` as drawn now.
func _watch(p: Passenger, checks: Dictionary) -> void:
	var props := _views.carry_on_props()
	var body := _views.node_for(p.id)
	checks["frames"] = int(checks["frames"]) + 1
	for b in p.carry_on:
		var state := FloatCheck.float_state(_world.sim, _views, p.id, b)
		var where := (
			"tick %d spent %d %s" % [_world.clock.tick, _world.clock.tick - p.stage_tick, state]
		)
		match state[0]:
			"held":
				checks["held"] = int(checks["held"]) + 1
			"resting":
				checks["resting"] = int(checks["resting"]) + 1
			"float":
				(checks["float"] as Array).append("bag %d %s" % [b, where])
		var gap := FloatCheck.grip_on_gap(props, p.id, b, body)
		if gap[0] != INF and gap[0] > gap[1]:
			(checks["grip_off"] as Array).append("bag %d gap %s %s" % [b, gap, where])


## Each bag of `p` as drawn now: its bounds in the world.
func _placed_bags(p: Passenger) -> Array[AABB]:
	var out: Array[AABB] = []
	var props := _views.carry_on_props().props_of(p.id)
	for b in (props["bags"] as Array).size():
		var node: Node3D = props["bags"][b]
		out.append(node.global_transform * CarryOnProps.bag_box(props["kinds"][b]))
	return out


func _bag_positions(p: Passenger) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for node: Node3D in _views.carry_on_props().props_of(p.id)["bags"]:
		out.append(node.global_transform)
	return out


func _drift(a: Array[Transform3D], b: Array[Transform3D]) -> float:
	var most := 0.0
	for i in a.size():
		most = maxf(most, a[i].origin.distance_to(b[i].origin))
		most = maxf(most, (a[i].basis.z - b[i].basis.z).length())
	return most
