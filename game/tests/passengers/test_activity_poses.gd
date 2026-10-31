class_name TestActivityPoses
extends GdUnitTestSuite
## How activity visitors are drawn (ActivityPoses; decision
## activity-poses-sit-on-the-lounge-sofa-recline-in-the-nap-pod): seated on
## the lounge sofa's seat mounts, seated and reclined in the nap pod, standing
## in the shower under foam, and the play area unchanged. The seat spots come
## from the imported .glb mounts, the pose eases in and out at the edges of
## the one SHOP_BROWSE stage, and the view draws a loaded world exactly as the
## world it was saved from.

const SAVE_INTO_STAY := 30

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


func _open(type: StringName) -> void:
	var grid := BuildGrid.new()
	_ids = ActivityTestLayout.build(grid, type)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	_world.run_to(10)
	_views = _make_views(_world)


func _make_views(world: PassengerTestWorld) -> PassengerViews:
	var views := PassengerViews.new()
	views.clock = world.clock
	views.sim = world.sim
	add_child(views)
	return views


## A bored guest that commits to the room's piece and has just reached it.
func _visitor(cell := ShopTestLayout.AIRSIDE_CELL) -> Passenger:
	var p := ShopTestLayout.airside_guest(_world, 80, cell)
	assert_int(NeedsPolicy.arbitrate(_world.sim, p)).is_equal(NeedsPolicy.Need.BOREDOM)
	assert_object(_world.sim.shops.visit_of(p.id)).is_not_null()
	_run_to_browse(p)
	return p


func _run_to_browse(p: Passenger) -> void:
	while p.stage != Passenger.Stage.SHOP_BROWSE and _world.clock.tick < 3000:
		_world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.SHOP_BROWSE)


func _clip(id: int) -> String:
	return _views.node_for(id).get_meta(&"clip", "")


## A mount node's transform in its .glb scene's own frame.
func _mount(piece: String, mount: String) -> Vector3:
	var scene := (load("res://assets/interior/%s.glb" % piece) as PackedScene).instantiate()
	var node := scene.find_child(mount, true, false) as Node3D
	assert_object(node).override_failure_message("%s has no %s" % [piece, mount]).is_not_null()
	var xf := node.transform
	var parent := node.get_parent()
	while parent != null and parent != scene:
		xf = (parent as Node3D).transform * xf
		parent = parent.get_parent()
	scene.free()
	return xf.origin


func test_each_piece_draws_its_own_pose() -> void:
	var want := {
		&"play_area": [ActivityPoses.Kind.NONE, "idle"],
		&"lounge": [ActivityPoses.Kind.SEAT, "sit_idle"],
		&"shower": [ActivityPoses.Kind.SHOWER, "idle"],
		&"nap_pod": [ActivityPoses.Kind.RECLINE, "sit_idle"],
	}
	for type: StringName in want:
		_open(type)
		var p := _visitor()
		_world.run_to(_world.clock.tick + 60)
		var node := _views.node_for(p.id)
		var recline: float = (node.get_meta(&"recline") as PodRecline).amount
		var foam := node.get_node("ShowerFoam") as ShowerFoam
		print(
			(
				"%s: kind %d clip %s recline %.2f foam %.2f balls %d seated %s"
				% [
					type,
					ActivityPoses.kind(_world.sim, p),
					_clip(p.id),
					recline,
					foam.amount,
					foam.balls_shown(),
					node.get_meta(&"seated"),
				]
			)
		)
		assert_int(ActivityPoses.kind(_world.sim, p)).is_equal(want[type][0])
		assert_str(_clip(p.id)).override_failure_message(str(type)).is_equal(want[type][1])
		var reclines := type == &"nap_pod"
		assert_float(recline).is_equal(1.0 if reclines else 0.0)
		var showers := type == &"shower"
		assert_bool(foam.visible).is_equal(showers)
		assert_int(foam.balls_shown()).is_equal(ShowerFoam.BALLS.size() if showers else 0)
		assert_bool(node.get_meta(&"seated")).is_equal(type != &"play_area")
		# The thought bubble is still drawn over a showering passenger.
		assert_bool((node.get_node("Bubble") as Label3D).visible).is_true()
		_free()


func test_seat_roots_are_the_imported_mounts() -> void:
	var mounts := {
		&"lounge_sofa": ["Mount_SitRoot_L", "Mount_SitRoot_R"],
		&"lounge_armchair": ["Mount_SitRoot"],
		&"nap_pod": ["Mount_SitRoot"],
	}
	for piece: StringName in mounts:
		var roots: Array = ActivityPoses.ROOTS[piece]
		assert_int(roots.size()).is_equal(mounts[piece].size())
		for i in roots.size():
			var at := _mount(piece, mounts[piece][i])
			print("%s %s glb %s root %s" % [piece, mounts[piece][i], at, roots[i]])
			assert_float(at.distance_to(Vector3(roots[i].x, 0.0, roots[i].y))).is_less(0.001)
	# The shower spot is inside the cubicle, behind its door (hinge at z 0.37).
	var door := _mount("shower_cubicle", "Door_Leaf_Shower")
	var use := _mount("shower_cubicle", "Mount_Use")
	var spot: Vector2 = ActivityPoses.ROOTS[&"shower_cubicle"][0]
	print("shower spot %s door %s use %s" % [spot, door, use])
	assert_float(spot.y).is_less(door.z - 0.3)
	assert_float(use.z).is_greater(door.z)


func test_sofa_visitors_sit_on_their_mounts_facing_out_at_every_facing() -> void:
	_open(&"lounge")
	var first := _visitor()
	var second := _visitor()
	_world.run_to(_world.clock.tick + 40)
	var record := _world.grid.get_object(_ids["use"])
	var piece := BuildView.object_transform(
		_world.grid,
		BuildCatalog.get_def(record["def"]).footprint(record["anchor"], record["facing"]),
		record["facing"]
	)
	var out := TerminalLayout.front_of(record["facing"])
	for p in [first, second]:
		var visit := _world.sim.shops.visit_of(p.id)
		var mount: String = ["Mount_SitRoot_L", "Mount_SitRoot_R"][visit.index]
		var want := piece * _mount("lounge_sofa", mount)
		var node := _views.node_for(p.id)
		var at := _views.tick_position(p.id, true)
		print("slot %d at %s want %s yaw %.3f" % [visit.index, at, want, node.rotation.y])
		assert_float(at.distance_to(want)).is_less(0.001)
		assert_float(node.rotation.y).is_equal_approx(atan2(out.x, out.y), 0.001)
	assert_int(_world.sim.shops.visit_of(first.id).index).is_not_equal(
		_world.sim.shops.visit_of(second.id).index
	)
	# Turned pieces: the spot turns with the piece the way BuildView draws it.
	var sofa := BuildCatalog.get_def(&"lounge_sofa")
	for facing in 4:
		var turned := {"def": &"lounge_sofa", "anchor": Vector2i(30, 10), "facing": facing}
		var frame := BuildView.object_transform(
			_world.grid, sofa.footprint(turned["anchor"], facing), facing
		)
		for i in 2:
			var mount: String = ["Mount_SitRoot_L", "Mount_SitRoot_R"][i]
			var spot := ActivityPoses.spot_of(_world.grid, turned, i)
			assert_float(spot.distance_to(frame * _mount("lounge_sofa", mount))).is_less(0.001)


func test_the_pose_eases_in_and_out_at_the_edges_of_the_stay() -> void:
	_open(&"nap_pod")
	var p := _visitor()
	var start := p.stage_tick
	var poses: Array[String] = []
	var biggest_step := 0.0
	var biggest_shuffle := 0.0
	var last_offset := Vector3.ONE
	var last := _views.draw_position(p)
	var seated_recline := 0.0
	var visited := 0
	while _world.sim.shops.visit_of(p.id) != null and _world.clock.tick < start + 1000:
		var spent := _world.clock.tick - start
		if p.stage == Passenger.Stage.SHOP_BROWSE:
			visited += 1
			var share := ActivityPoses.share(_world.sim, p)
			if spent == 0:
				assert_float(share).is_equal(0.0)
			if spent == ActivityPoses.SHUFFLE_TICKS:
				assert_float(share).is_equal(1.0)
			if spent == 150:
				seated_recline = ActivityPoses.recline(_world.sim, p)
			if spent < PassengerSim.SIT_DOWN_TICKS:
				assert_float(ActivityPoses.recline(_world.sim, p)).is_equal(0.0)
			var clip := _clip(p.id)
			if poses.is_empty() or poses[-1] != clip:
				poses.append(clip)
			last_offset = ActivityPoses.offset(_world.sim, p)
		var browsing := p.stage == Passenger.Stage.SHOP_BROWSE
		_world.step()
		var now := _views.draw_position(p)
		biggest_step = maxf(biggest_step, now.distance_to(last))
		if browsing and p.stage == Passenger.Stage.SHOP_BROWSE:
			biggest_shuffle = maxf(biggest_shuffle, now.distance_to(last))
		last = now
	var dwell := RoomTypes.get_type(&"nap_pod").dwell_ticks
	print(
		(
			(
				"clips %s, stay %d of %d ticks, recline mid-stay %.2f, biggest step %.3f m,"
				+ " biggest shuffle step %.3f m, offset on the last browse tick %s"
			)
			% [poses, visited, dwell, seated_recline, biggest_step, biggest_shuffle, last_offset]
		)
	)
	assert_int(visited).is_equal(dwell)
	assert_array(poses).is_equal(["sit_down", "sit_idle", "stand_up"])
	assert_float(seated_recline).is_equal(1.0)
	# The last browse tick drew it back on its slot cell, so it walks off from
	# where it stands. A walking step is WALK_MM a tick and the 0.55 m shuffle
	# over 12 ticks 0.046 m: nothing jumps at the stage edges, and the control
	# shows the shuffle was drawn.
	assert_float(last_offset.length()).is_less(0.001)
	assert_float(biggest_step).is_less_equal(PassengerSim.WALK_MM / 1000.0 + 0.001)
	assert_float(biggest_shuffle).is_greater(0.04)
	assert_float(biggest_shuffle).is_less(0.05)


func test_a_shower_visitor_steps_in_under_foam_and_steps_out_again() -> void:
	_open(&"shower")
	var p := _visitor()
	var record := _world.grid.get_object(_ids["use"])
	var inside := ActivityPoses.spot_of(_world.grid, record, 0)
	var out := TerminalLayout.front_of(record["facing"])
	_world.step()
	var stepping := _clip(p.id)
	var yaw_in := _views.node_for(p.id).rotation.y
	_world.run_to(p.stage_tick + 100)
	var node := _views.node_for(p.id)
	var foam := node.get_node("ShowerFoam") as ShowerFoam
	print(
		(
			"stepping %s yaw %.2f, inside at %s (spot %s) yaw %.2f foam %.2f"
			% [
				stepping,
				yaw_in,
				_views.tick_position(p.id, true),
				inside,
				node.rotation.y,
				foam.amount
			]
		)
	)
	assert_str(stepping).is_equal("walk")
	assert_float(yaw_in).is_equal_approx(atan2(-out.x, -out.y), 0.001)
	var on_tray := inside + Vector3(0.0, ActivityPoses.SHOWER_TRAY_M, 0.0)
	assert_float(_views.tick_position(p.id, true).distance_to(on_tray)).is_less(0.001)
	assert_float(node.rotation.y).is_equal_approx(atan2(out.x, out.y), 0.001)
	assert_float(foam.amount).is_equal(1.0)
	while _world.sim.shops.visit_of(p.id) != null and _world.clock.tick < 3000:
		_world.step()
	print("after: foam %.2f visible %s" % [foam.amount, foam.visible])
	assert_float(foam.amount).is_equal(0.0)
	assert_bool(foam.visible).is_false()


func test_a_loaded_world_draws_the_pose_the_saved_one_drew() -> void:
	_open(&"nap_pod")
	var p := _visitor()
	_world.run_to(p.stage_tick + SAVE_INTO_STAY)
	var saved := _save(_world)
	# What the original draws on each of the next ticks.
	var want: Array = []
	for i in 40:
		want.append(_drawn(_views, p.id))
		_world.step()
	var loaded := _load(saved)
	var views := _make_views(loaded)
	views.snap()
	var got: Array = []
	for i in 40:
		got.append(_drawn(views, p.id))
		loaded.step()
	print("saved at %d into the stay: first %s, last %s" % [SAVE_INTO_STAY, got[0], got[-1]])
	views.free()
	loaded.free_all()
	assert_array(got).is_equal(want)
	# The recline eased in during those ticks, so the comparison saw it change.
	assert_float(want[0][3]).is_less(want[-1][3])


func _drawn(views: PassengerViews, id: int) -> Array:
	var node := views.node_for(id)
	return [
		views.tick_position(id, true).snapped(Vector3.ONE * 0.0001),
		snappedf(node.rotation.y, 0.0001),
		node.get_meta(&"clip", ""),
		snappedf((node.get_meta(&"recline") as PodRecline).amount, 0.0001),
	]


func _save(world: PassengerTestWorld) -> String:
	return (
		JSON
		. stringify(
			{
				"clock": world.clock.to_snapshot(),
				"flights": world.flights.to_snapshot(),
				"grid": world.grid.to_snapshot(),
				"passengers": world.sim.to_snapshot(),
			}
		)
	)


func _load(text: String) -> PassengerTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	return world
