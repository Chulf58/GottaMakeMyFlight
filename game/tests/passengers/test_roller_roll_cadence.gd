class_name TestRollerRollCadence
extends GdUnitTestSuite
## A roller's pick-up at a seat rolls the roller upright (or tips it) by one
## decision taken on sim ticks, never on drawn frames (board c0707a22): the
## same at every draw cadence. Drawn through the real views (PassengerViews,
## CarryOnProps, RollerPark), headless. The views sync on every tick; frames
## draw only where a cadence says, so the first draw of the pick-up can come
## many ticks after the bag left the floor (a frame running several ticks).
## Also pinned: a take before the lift's end keeps the k it was taken at, a
## forced take plans the same move for any hand height, and the roller drawn
## on every frame stays out of the sofa or pod.

## Draw cadences: [name, the tick of the pick-up the first draw comes on, the
## ticks between draws after it].
const CADENCES: Array = [["every", 0, 1], ["third", 0, 3], ["late9", 9, 1], ["late12", 12, 1]]
## Ticks of the pick-up played (past the forced end of a rolled move).
const RUN_TICKS := 60
## Planned roller poses compared from this tick of the pick-up (past the
## latest first draw's lift and park) on the ticks every cadence draws.
const SAME_FROM := 21
const SAME_M := 0.002
const SAME_RAD := 0.005
## The seat box (the seat frame, +z out of the front; as
## spike/cafe_roller_standup_probe.gd measures ROLLER_CLEAR).
const SEAT_HALF_M := 0.6
const SEAT_FRONT_M := 0.05
const SEAT_DEPTH_M := 0.9
const SEAT_TOP_M := 1.3

var _world: PassengerTestWorld
var _views: PassengerViews


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


## One drawn frame at the clock's time (as the game draws: the views'
## _process, the skeleton's pose, then the hand bags placed from it).
func _frame() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()


## An airside guest with a roller visiting a ready `type` room's piece, drawn
## through the views, stepped to the tick before its bag leaves the floor.
func _guest(type: StringName) -> Passenger:
	var grid := BuildGrid.new()
	ActivityTestLayout.build(grid, type)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	_world.run_to(10)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	var p: Passenger = null
	for attempt in 200:
		p = ShopTestLayout.airside_guest(_world, 0)
		if SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
	assert_int(SecurityLooks.bag_kind(p, 0)).is_equal(SecurityLooks.Kind.ROLLER)
	p.boredom = 80
	p.carry_on = 1
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < 3000:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
	# Drawn every tick of the stay, to the tick its bag leaves the floor (the
	# pick-up's first tick, played by _play()).
	while not ActivityPoses.bags_down(_world.sim, p) and _world.clock.tick < 6000:
		_world.step()
	while _world.clock.tick < 6000:
		await _frame()
		_world.step()
		if not ActivityPoses.bags_down(_world.sim, p):
			break
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)
	return p


## Plays the pick-up of `p` from the tick its bag left the floor with frames on
## `cadence`: {"rolls", "roll_at", "roll_tip", "ticks_at" (the move's length on
## each drawn tick), "plans" (tick -> RollerPark's planned roller), "clear"
## (the least clearance of the drawn roller from `seat` on any drawn frame),
## "took", "first"}.
func _play(p: Passenger, cadence: Array, seat: Dictionary) -> Dictionary:
	var props := _views.carry_on_props()
	var out := {"plans": {}, "ticks_at": {}, "rolls_at": {}, "clear": INF, "clear_at": -1}
	var since := _world.clock.tick
	var next: int = cadence[1]
	for n in RUN_TICKS + 1:
		if n > 0:
			_world.step()
		if n != next:
			continue
		next += int(cadence[2])
		await _frame()
		var rec := props.bag_state(p.id, 0)
		if not out.has("first"):
			out["first"] = n
			out["since"] = float(rec.get("since", -1.0)) - since
		out["ticks_at"][n] = CarryLead.ticks_of(rec)
		out["rolls_at"][n] = RollerPark.rolls(rec)
		# The drawn roller's largest move from one drawn tick to the next.
		var drawn := (rec["node"] as Node3D).global_position
		if out.has("last_at") and int(cadence[2]) == 1 and n <= RollerPark.ROLL_TO + 12:
			out["step"] = maxf(float(out.get("step", 0.0)), drawn.distance_to(out["last_at"]))
		out["last_at"] = drawn
		out["rolled"] = out.get("rolled", false) or RollerPark.rolls(rec)
		if CarryPlace.leading(rec, float(_world.clock.tick)) and rec.has("lead"):
			out["plans"][n] = rec["lead"]["xf"]
		if not seat.is_empty():
			var least := _clearance(seat, (rec["node"] as Node3D).global_transform)
			if least < out["clear"]:
				out["clear"] = least
				out["clear_at"] = n
	var rec := props.bag_state(p.id, 0)
	out["rolls"] = RollerPark.rolls(rec)
	out["roll_at"] = rec.get("roll_at", Vector3.INF)
	out["roll_tip"] = float(rec.get("roll_tip", NAN))
	out["took"] = float(rec.get("park_took", NAN))
	return out


## The seat of the piece `p` stays at: {"frame" (its seat frame, world), "box"
## (the bounds in it of the piece's mesh vertices near the seat)}.
func _seat_of(p: Passenger) -> Dictionary:
	var frame := ActivityPoses.stay_frame(_world.sim, p)
	var record := _world.sim.grid.get_object(_world.sim.shops.visit_of(p.id).display)
	var def := BuildCatalog.get_def(record["def"])
	var cells := def.footprint(record["anchor"], record["facing"])
	var piece := BuildView.object_transform(_world.sim.grid, cells, record["facing"])
	var to_seat := frame.affine_inverse() * piece
	var scene := (load("res://assets/interior/%s.glb" % record["def"]) as PackedScene).instantiate()
	var box := AABB()
	var count := 0
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := mi.transform
		var parent := mi.get_parent()
		while parent != null and parent != scene:
			xf = (parent as Node3D).transform * xf
			parent = parent.get_parent()
		for v in mi.mesh.get_faces():
			var at := to_seat * xf * v
			var near := absf(at.x) <= SEAT_HALF_M and at.y <= SEAT_TOP_M
			if near and at.z <= SEAT_FRONT_M and at.z >= -SEAT_DEPTH_M:
				box = AABB(at, Vector3.ZERO) if count == 0 else box.expand(at)
				count += 1
	scene.free()
	assert_int(count).override_failure_message("no seat vertices").is_greater(0)
	return {"frame": frame, "box": box}


## The least signed distance (negative inside) of the roller's box points
## (corners, face centres, centre) drawn at `xf` from the seat box.
static func _clearance(seat: Dictionary, xf: Transform3D) -> float:
	var local := CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER)
	var points: Array[Vector3] = [local.get_center()]
	for i in 8:
		points.append(local.get_endpoint(i))
	for axis in 3:
		for side in [0.0, 1.0]:
			var face := local.get_center()
			face[axis] = local.position[axis] + local.size[axis] * side
			points.append(face)
	var to_seat: Transform3D = (seat["frame"] as Transform3D).affine_inverse()
	var least := INF
	for point in points:
		least = minf(least, _signed(seat["box"], to_seat * (xf * point)))
	return least


static func _signed(box: AABB, point: Vector3) -> float:
	var out := Vector3(
		maxf(box.position.x - point.x, point.x - box.end.x),
		maxf(box.position.y - point.y, point.y - box.end.y),
		maxf(box.position.z - point.z, point.z - box.end.z)
	)
	if out.x > 0.0 or out.y > 0.0 or out.z > 0.0:
		return Vector3(maxf(out.x, 0.0), maxf(out.y, 0.0), maxf(out.z, 0.0)).length()
	return maxf(out.x, maxf(out.y, out.z))


## Every cadence of a `type` pick-up: its _play() by cadence name.
func _runs(type: StringName, with_seat: bool) -> Dictionary:
	var runs := {}
	for cadence: Array in CADENCES:
		var p := await _guest(type)
		var seat := _seat_of(p) if with_seat else {}
		var run := await _play(p, cadence, seat)
		print(
			(
				"%s %s: first %d since %+.1f took %.4f rolls %s stood %s roll_tip %.4f clear %.3f at %d"
				% [
					type,
					cadence[0],
					run["first"],
					run["since"],
					run["took"],
					run["rolls"],
					run["roll_at"],
					run["roll_tip"],
					run["clear"],
					run["clear_at"],
				]
			)
		)
		print(
			(
				"%s %s: drawn roller step at most %.3f m a tick"
				% [type, cadence[0], run.get("step", -1.0)]
			)
		)
		runs[cadence[0]] = run
		_free()
	return runs


## Every cadence decides as `rolls`. A rolled move also has the same stood
## point, tips on the same tick, keeps the same length and draws the same
## planned roller as a draw every tick. (A tipped one is not compared further:
## a walker walking off stamps new moves, each started where the bag was
## drawn last.)
func _assert_same(type: StringName, runs: Dictionary, rolls: bool) -> void:
	var every: Dictionary = runs["every"]
	assert_bool(every["rolls"]).override_failure_message("%s every" % type).is_equal(rolls)
	for name: String in runs:
		var run: Dictionary = runs[name]
		var line := "%s %s" % [type, name]
		assert_bool(run["rolls"]).override_failure_message(line).is_equal(rolls)
		# On every drawn frame, not only at the end.
		assert_bool(run["rolled"]).override_failure_message(line).is_equal(rolls)
		if not rolls:
			continue
		var stood: Vector3 = run["roll_at"]
		assert_float(stood.distance_to(every["roll_at"])).override_failure_message(line).is_less(
			0.001
		)
		assert_float(run["roll_tip"]).override_failure_message(line).is_equal_approx(
			every["roll_tip"], 0.0001
		)
		var compared := 0
		var worst := 0.0
		for n: int in run["ticks_at"]:
			# The roll and the move's length on every tick both draw, from the
			# first draw on.
			if every["ticks_at"].has(n):
				var at := "%s tick %d length" % [line, n]
				assert_float(run["ticks_at"][n]).override_failure_message(at).is_equal_approx(
					every["ticks_at"][n], 0.0001
				)
				assert_bool(run["rolls_at"][n]).override_failure_message(at).is_equal(
					every["rolls_at"][n]
				)
			# While it rolls upright: RollerPark's alone (the tip blends into the
			# pull's pose, which RollerPull steps once per draw).
			var rolling: bool = n < float(run["roll_tip"]) * RollerPark.TICKS_UP
			if n < SAME_FROM or not rolling or not every["plans"].has(n) or not run["plans"].has(n):
				continue
			var a: Transform3D = every["plans"][n]
			var b: Transform3D = run["plans"][n]
			var turn := a.basis.get_rotation_quaternion().angle_to(
				b.basis.get_rotation_quaternion()
			)
			var gap := a.origin.distance_to(b.origin)
			var at := "%s tick %d: %.4f m %.4f rad" % [line, n, gap, turn]
			assert_float(gap).override_failure_message(at).is_less(SAME_M)
			assert_float(turn).override_failure_message(at).is_less(SAME_RAD)
			worst = maxf(worst, gap)
			compared += 1
		print("%s: %d planned poses compared, worst %.5f m" % [line, compared, worst])
		if name != "every":
			assert_int(compared).override_failure_message(line).is_greater(0)


func test_a_sofa_pick_up_rolls_upright_at_every_draw_cadence() -> void:
	var runs := await _runs(&"lounge", true)
	_assert_same(&"lounge", runs, true)
	_assert_clear(&"lounge", runs)


func test_a_nap_pod_pick_up_rolls_upright_at_every_draw_cadence() -> void:
	var runs := await _runs(&"nap_pod", true)
	_assert_same(&"nap_pod", runs, true)
	_assert_clear(&"nap_pod", runs)


## The shower's door pick-up walks off before the park ends: it tips at
## every cadence, never rolls.
func test_a_shower_door_pick_up_tips_at_every_draw_cadence() -> void:
	var runs := await _runs(&"shower", false)
	_assert_same(&"shower", runs, false)


## The drawn roller is out of the seat on every drawn frame of every cadence.
func _assert_clear(type: StringName, runs: Dictionary) -> void:
	for name: String in runs:
		var run: Dictionary = runs[name]
		var line := "%s %s: clear %.3f m at tick %d" % [type, name, run["clear"], run["clear_at"]]
		assert_float(run["clear"]).override_failure_message(line).is_greater(0.0)


## A take before the lift's end keeps the k it was taken at (a forced take at
## k 0.50 records 0.50; never backdated to TAKE_BY), and one by the hand at
## its grip keeps its k too. Control: before REACH_END with the hand far, no
## take.
func test_a_take_before_the_lift_end_keeps_its_k() -> void:
	var handle := Vector3(0.0, 0.2, 0.0)
	var far := {"grips": [Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.0, 0.0)]}
	var near := {"grips": [handle, handle]}
	var bag := {}
	assert_float(RollerPark._taken(bag, 0.2, handle, near, 0)).is_equal(-1.0)
	assert_float(RollerPark._taken(bag, 0.3, handle, far, 0)).is_equal(-1.0)
	assert_float(RollerPark._taken(bag, 0.50, handle, far, 0)).is_equal(0.50)
	assert_float(bag["park_took"]).is_equal(0.50)
	var by_hand := {}
	assert_float(RollerPark._taken(by_hand, 0.3, handle, near, 0)).is_equal(0.3)


## A pick-up first drawn at k 0.50 (8 ticks in, before the lift's end) through
## the views takes the bag at 0.50.
func test_a_sofa_pick_up_first_drawn_before_the_lift_end_takes_it_then() -> void:
	var p := await _guest(&"lounge")
	var run := await _play(p, ["late8", 8, 1], {})
	print("lounge late8: took %.4f rolls %s" % [run["took"], run["rolls"]])
	assert_float(run["took"]).is_equal_approx(8.0 / RollerPark.TICKS_UP, 0.0001)
	assert_bool(run["rolls"]).is_true()


## A floor>pull record for plan() at the origin, the roller lying beside the
## feet, stamped with a face.
func _plan_bag() -> Dictionary:
	var bag := {
		"kind": SecurityLooks.Kind.ROLLER,
		"led": true,
		"was": SecurityLooks.Home.FLOOR * 4,
		"carry_from": SecurityLooks.Carry.PULL,
		"carry": SecurityLooks.Carry.PULL,
		"home": SecurityLooks.Home.HAND * 4,
		"from": Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.34, 0.0, 0.07)),
	}
	RollerPark.stamp(bag, Transform3D.IDENTITY, 0.0)
	return bag


## The same forced take (k 0.45, past TAKE_BY) plans the same move with the
## hand drawn at two heights on its first draw (anti-pattern a-carry-move-must-
## not-take-its-shape-from-the-hand-it-is-pos), on that draw and after.
func test_a_forced_take_plans_the_same_for_any_first_drawn_hand_height() -> void:
	var start := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.34, 0.0, 0.07))
	var want := Transform3D(Basis.IDENTITY, Vector3(0.3, 0.0, -0.6))
	var plans: Array = []
	for height: float in [0.4, 1.1]:
		var bag := _plan_bag()
		var body := {
			"bar_z": 0.4,
			"scale": 1.0,
			"grips": [Vector3(0.3, height, 0.1), Vector3(-0.3, height, 0.1)],
		}
		var row: Array = []
		for k: float in [0.45, 0.6, 0.8, 0.95]:
			var plan := RollerPark.plan(bag, k, start, want, Transform3D.IDENTITY, {}, body)
			row.append(plan["xf"])
		plans.append(row)
	for i in plans[0].size():
		var a: Transform3D = plans[0][i]
		var b: Transform3D = plans[1][i]
		print("plan %d: %.5f m apart" % [i, a.origin.distance_to(b.origin)])
		assert_float(a.origin.distance_to(b.origin)).is_less(0.0001)
		assert_bool(a.basis.is_equal_approx(b.basis)).is_true()
