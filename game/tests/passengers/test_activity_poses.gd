class_name TestActivityPoses
extends GdUnitTestSuite
## How activity visitors are drawn (ActivityPoses; decision
## activity-poses-sit-on-the-lounge-sofa-recline-in-the-nap-pod): seated on
## the lounge sofa's seat mounts, seated and reclined in the nap pod, standing
## in the shower washing under moving foam with its clothes off, and the play
## area unchanged. The seat spots come
## from the imported .glb mounts, the pose eases in and out at the edges of
## the one SHOP_BROWSE stage, and the view draws a loaded world exactly as the
## world it was saved from.

const SAVE_INTO_STAY := 30
## A load this many ticks into the sit-down (of SIT_DOWN_TICKS 24).
const MID_SIT_DOWN := 12
## Ticks the world plays on past that save before it is loaded back.
const LATER_SIT_DOWN := 18
## Ticks into a shower stay: washing bare under the full lather.
const MID_WASH := 70
## The most (metres) the lather's motion may take a bubble past where the
## still lather reaches.
const MOTION_MARGIN_M := 0.035

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
		&"shower": [ActivityPoses.Kind.SHOWER, "shower"],
		&"nap_pod": [ActivityPoses.Kind.RECLINE, "sit_idle"],
	}
	for type: StringName in want:
		_open(type)
		var p := _visitor()
		_world.run_to(_world.clock.tick + 60)
		var node := _views.node_for(p.id)
		var recline := _recline(node)
		var foam := node.get_node_or_null("ShowerFoam") as ShowerFoam
		var lather := foam.lather_shown() if foam != null else 0
		print(
			(
				"%s: kind %d clip %s recline %.2f foam %.2f balls %d seated %s"
				% [
					type,
					ActivityPoses.kind(_world.sim, p),
					_clip(p.id),
					recline,
					foam.amount if foam != null else 0.0,
					lather,
					node.get_meta(&"seated"),
				]
			)
		)
		assert_int(ActivityPoses.kind(_world.sim, p)).is_equal(want[type][0])
		assert_str(_clip(p.id)).override_failure_message(str(type)).is_equal(want[type][1])
		var reclines := type == &"nap_pod"
		assert_float(recline).is_equal(1.0 if reclines else 0.0)
		var showers := type == &"shower"
		# Only a showering passenger carries foam, and only a reclining one a
		# recline modifier.
		assert_bool(foam != null).is_equal(showers)
		assert_bool(node.has_meta(&"recline")).is_equal(reclines)
		assert_int(lather).is_equal(ShowerFoam.lather_count() if showers else 0)
		# Only a showering passenger has its clothes off.
		assert_bool(node.has_meta(&"dressed")).is_equal(showers)
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
	var left := node.get_node_or_null("ShowerFoam")
	print("after: foam node %s, lather was %d bubbles" % [left, ShowerFoam.lather_count()])
	assert_object(left).is_null()


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


func test_a_load_mid_sit_down_starts_the_clip_where_the_sim_is() -> void:
	_open(&"lounge")
	var p := _visitor()
	_world.run_to(p.stage_tick + MID_SIT_DOWN)
	var loaded := _load(_save(_world))
	var views := _make_views(loaded)
	views.snap()
	var node := views.node_for(p.id)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	var base: float = node.get_meta(&"base_speed")
	var want := MID_SIT_DOWN * SimClock.STEP * base
	var at := player.current_animation_position
	var clip := player.current_animation
	print(
		(
			"loaded %d ticks into sit-down: clip %s at %.3f s, want %.3f s"
			% [MID_SIT_DOWN, clip, at, want]
		)
	)
	views.free()
	loaded.free_all()
	assert_str(clip).is_equal("sit_down")
	assert_float(at).is_equal_approx(want, 0.01)
	assert_float(at).is_greater(0.3)


func test_a_load_into_the_same_views_mid_sit_down_seeks_the_clip_back() -> void:
	_open(&"lounge")
	var p := _visitor()
	var id := p.id
	_world.run_to(p.stage_tick + MID_SIT_DOWN)
	var saved := _save(_world)
	_world.run_to(p.stage_tick + LATER_SIT_DOWN)
	var node := _views.node_for(id)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	var base: float = node.get_meta(&"base_speed")
	# The frames played the clip on with the world (a headless run draws none).
	player.seek(LATER_SIT_DOWN * SimClock.STEP * base, true)
	var before := player.current_animation_position
	_restore(saved)
	_views.snap()
	var at := player.current_animation_position
	var want := MID_SIT_DOWN * SimClock.STEP * base
	var clip := player.current_animation
	print(
		(
			"same views: before the load %s at %.3f s, after %s at %.3f s, want %.3f s"
			% [node.get_meta(&"clip"), before, clip, at, want]
		)
	)
	assert_object(_views.node_for(id)).is_same(node)
	assert_float(before).is_equal_approx(LATER_SIT_DOWN * SimClock.STEP * base, 0.01)
	assert_str(clip).is_equal("sit_down")
	assert_float(at).is_equal_approx(want, 0.01)


func test_a_deadline_brought_closer_during_stand_up_moves_the_clip_on() -> void:
	_open(&"lounge")
	var p := _visitor()
	_world.run_to(p.stage_tick + 60)
	var visit := _world.sim.shops.visit_of(p.id)
	visit.deadline = _world.clock.tick + 20
	_world.step()
	_world.step()
	var node := _views.node_for(p.id)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	var base: float = node.get_meta(&"base_speed")
	var first := player.current_animation_position
	visit.deadline -= 8
	_world.step()
	var at := player.current_animation_position
	var ticks := ActivityPoses.clip_ticks(_world.sim, p)
	print(
		(
			"stand-up %s at %.3f s, deadline 8 ticks closer: %d ticks in, clip at %.3f s"
			% [player.current_animation, first, ticks, at]
		)
	)
	assert_str(player.current_animation).is_equal("stand_up")
	assert_int(ticks).is_greater(10)
	assert_float(at).is_equal_approx(ticks * SimClock.STEP * base, 0.01)


func test_a_stay_cut_short_eases_the_body_back_to_its_slot() -> void:
	_open(&"lounge")
	var p := _visitor()
	_world.run_to(p.stage_tick + 60)
	# A re-forecast that brings the deadline close: the stay ends in 2 ticks.
	_world.sim.shops.visit_of(p.id).deadline = _world.clock.tick + 2
	var eased := _track_seat_offset(p, 20)
	print("deadline moved: seat offset per tick %s" % [eased])
	_assert_eased(eased)


func test_a_removed_sofa_eases_the_body_off_its_spot() -> void:
	_open(&"lounge")
	var p := _visitor()
	_world.run_to(p.stage_tick + 60)
	assert_bool(_world.grid.apply(BuildEdit.remove_object(_ids["use"])).ok).is_true()
	var eased := _track_seat_offset(p, 20)
	print("sofa removed: seat offset per tick %s" % [eased])
	_assert_eased(eased)


## The length of the drawn step onto the seat (draw minus sim position) on
## each of the next ticks, the current one first.
func _track_seat_offset(p: Passenger, ticks: int) -> Array[float]:
	var out: Array[float] = []
	for i in ticks:
		var step := _views.draw_position(p) - _world.sim.world_position(p)
		out.append(snappedf(step.length(), 0.001))
		_world.step()
	return out


## Seated at first, back on the slot at the end, never more than a walking
## step in a tick, and over more than one tick.
func _assert_eased(lengths: Array[float]) -> void:
	assert_float(lengths[0]).is_greater(0.5)
	assert_float(lengths[-1]).is_equal(0.0)
	var walk := PassengerSim.WALK_MM / 1000.0 + 0.001
	var between := 0
	for i in range(1, lengths.size()):
		assert_float(absf(lengths[i] - lengths[i - 1])).is_less_equal(walk)
		if lengths[i] > 0.0 and lengths[i] < lengths[0]:
			between += 1
	assert_int(between).is_greater_equal(4)


func test_the_shower_clip_loops_on_every_passenger_body_after_import() -> void:
	var looped := 0
	for body in PassengerLooks.BODIES.size():
		# A fresh load: PassengerViews sets loop modes on the cached clips too,
		# and this checks what the import itself wrote.
		var path := PassengerLooks.SCENES[body].resource_path
		var scene := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		var node := (scene as PackedScene).instantiate()
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		var wash := player.get_animation("shower")
		var once := player.get_animation("sit_down")
		print(
			(
				"%s: shower loop %d length %.2f s, sit_down loop %d"
				% [PassengerLooks.BODIES[body], wash.loop_mode, wash.length, once.loop_mode]
			)
		)
		if wash.loop_mode == Animation.LOOP_LINEAR:
			looped += 1
		assert_float(wash.length).is_equal_approx(5.0, 0.01)
		# Control: a one-shot clip stays one-shot, so the check can fail.
		assert_int(once.loop_mode).is_equal(Animation.LOOP_NONE)
		node.free()
	assert_int(looped).is_equal(PassengerLooks.BODIES.size())


func test_a_showering_passenger_washes_bare_and_dresses_again_on_step_out() -> void:
	_open(&"shower")
	var p := _visitor()
	# Bystanders on their way to the gate, at least one of the showering
	# passenger's own body, to show nobody else's look changes.
	var body := PassengerLooks.body_of(p.id, p.variant)
	var bystanders := 0
	while bystanders < 4 or _same_body_count(p.id, body) == 0:
		ShopTestLayout.airside_guest(_world, 0)
		bystanders += 1
		assert_int(bystanders).is_less(60)
	_world.step()
	var node := _views.node_for(p.id)
	assert_int(node.get_meta(&"body")).is_equal(body)
	var mi := PassengerLooks.body_mesh(node)
	var dressed := mi.mesh
	var dressed_materials := _materials(mi)
	var shared := PassengerLooks.plain_mesh(body).surface_get_material(0) as ShaderMaterial
	var shared_atlas: Texture2D = shared.get_shader_parameter("albedo_texture")
	# Still dressed while the lather builds up.
	_world.run_to(p.stage_tick + ActivityPoses.EASE_TICKS - 2)
	var building := [mi.mesh == dressed, node.has_meta(&"dressed"), _clip(p.id)]
	_world.run_to(p.stage_tick + MID_WASH)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	var bare := mi.mesh
	var skin := _skin_report(body, bare)
	var others := _other_looks(p.id)
	print(
		(
			"building %s; washing clip %s (%s) bare %s skin %s; others %s"
			% [building, _clip(p.id), player.current_animation, bare != dressed, skin, others]
		)
	)
	assert_array(building).is_equal([true, false, "shower"])
	assert_str(_clip(p.id)).is_equal("shower")
	assert_str(player.current_animation).is_equal("shower")
	assert_object(bare).is_same(ActivityPoses.bare_mesh(body))
	# Every clothes and shoe vertex samples the body's own hand skin, on the
	# shared atlas material (no copy to leak).
	assert_int(skin["vertices"]).is_greater(100)
	assert_int(skin["off_skin"]).is_equal(0)
	assert_int(skin["clothes_left"]).is_equal(0)
	assert_bool(skin["warm"]).is_true()
	for i in bare.get_surface_count():
		assert_object(bare.surface_get_material(i)).is_same(shared)
	# No other drawn passenger changed its look; the shared atlas is as it was.
	assert_int(others["count"]).is_greater_equal(bystanders)
	assert_int(others["same_body"]).is_greater(0)
	assert_int(others["bare"]).is_equal(0)
	assert_int(others["own_look"]).is_equal(others["count"])
	assert_object(shared.get_shader_parameter("albedo_texture")).is_same(shared_atlas)
	# The rinse puts the clothes back on before the step out.
	while ActivityPoses.share(_world.sim, p) > 0.0 and _world.clock.tick < 3000:
		_world.step()
	print("stepped out at tick %d: clip %s" % [_world.clock.tick - p.stage_tick, _clip(p.id)])
	assert_object(mi.mesh).is_same(dressed)
	assert_array(_materials(mi)).is_equal(dressed_materials)
	assert_bool(node.has_meta(&"dressed")).is_false()
	assert_str(_clip(p.id)).is_not_equal("shower")


func test_a_passenger_released_mid_shower_goes_back_to_the_pool_dressed() -> void:
	_open(&"shower")
	var p := _visitor()
	_world.run_to(p.stage_tick + MID_WASH)
	var node := _views.node_for(p.id)
	var body: int = node.get_meta(&"body")
	var mi := PassengerLooks.body_mesh(node)
	var dressed: Mesh = node.get_meta(&"dressed")
	var bare := mi.mesh
	# Drawn no more (as on boarding): the node goes back to the pool.
	p.stage = Passenger.Stage.MADE
	_views.sync()
	var released := [_views.node_for(p.id) == null, mi.mesh == dressed, node.has_meta(&"dressed")]
	# The next passenger of that body takes the same node, in its own look.
	var next := Passenger.new()
	next.variant = p.variant
	next.id = p.id + 1
	while PassengerLooks.body_of(next.id, next.variant) != body:
		next.id += 1
	var taken := _views._take(next)
	var tint := PassengerLooks.tint_of(next.id)
	var look := (
		PassengerLooks.plain_mesh(body) if tint == 0 else PassengerLooks.split_mesh(body, tint)
	)
	print(
		(
			"released %s; reused by %d (tint %d): same node %s"
			% [released, next.id, tint, taken == node]
		)
	)
	assert_bool(bare == dressed).is_false()
	assert_array(released).is_equal([true, true, false])
	assert_object(node.get_node_or_null("ShowerFoam")).is_null()
	assert_object(taken).is_same(node)
	assert_object(PassengerLooks.body_mesh(taken).mesh).is_same(look)


func test_a_load_mid_shower_washes_bare_from_where_the_sim_is() -> void:
	_open(&"shower")
	var p := _visitor()
	_world.run_to(p.stage_tick + MID_WASH)
	var loaded := _load(_save(_world))
	var views := _make_views(loaded)
	views.snap()
	var node := views.node_for(p.id)
	var player := node.get_node("AnimationPlayer") as AnimationPlayer
	var want := fposmod((MID_WASH - ActivityPoses.SHUFFLE_TICKS) * SimClock.STEP, 5.0)
	var got := [player.current_animation, node.has_meta(&"dressed")]
	var at := player.current_animation_position
	print("loaded %d ticks in: %s at %.3f s, want %.3f s" % [MID_WASH, got, at, want])
	views.free()
	loaded.free_all()
	assert_array(got).is_equal(["shower", true])
	assert_float(at).is_equal_approx(want, 0.01)
	assert_float(at).is_greater(0.5)


func test_a_load_back_to_before_the_lather_puts_the_clothes_back_on() -> void:
	_open(&"shower")
	var p := _visitor()
	_world.run_to(p.stage_tick + 4)
	var saved := _save(_world)
	_world.run_to(p.stage_tick + MID_WASH)
	var node := _views.node_for(p.id)
	var was_bare := node.has_meta(&"dressed")
	# The same views, the clock gone back (ids survive a load).
	_restore(saved)
	_views.snap()
	var after := [node.has_meta(&"dressed"), _clip(p.id)]
	print("bare before the load %s; after %s" % [was_bare, after])
	assert_bool(was_bare).is_true()
	assert_bool(after[0]).is_false()
	assert_str(after[1]).is_not_equal("shower")


func test_the_lather_moves_within_its_envelope() -> void:
	var soap := ShowerFoam.soap()
	var code := soap.shader.code
	var worst := _lather_excess(ShowerFoam.DRIFT)
	# Control: a drift four times as far breaks the margin, so the check bites.
	var wild := _lather_excess(ShowerFoam.DRIFT * 4.0)
	print(
		(
			"lather: %d bubbles, motion reach %.4f m, worst excess %.4f m (control %.4f), margin %.3f"
			% [
				ShowerFoam.lather_count(),
				ShowerFoam.motion_reach_m(ShowerFoam.R_MAX),
				worst,
				wild,
				MOTION_MARGIN_M
			]
		)
	)
	# The bubbles move on their own (time and instance in the vertex shader),
	# with the swell and drift the bound is worked out from.
	assert_bool("TIME" in code and "INSTANCE_ID" in code).is_true()
	assert_float(soap.get_shader_parameter("swell")).is_equal(ShowerFoam.SWELL)
	assert_float(soap.get_shader_parameter("drift")).is_equal(ShowerFoam.DRIFT)
	assert_float(ShowerFoam.motion_reach_m(ShowerFoam.R_MAX)).is_greater(0.005)
	assert_float(worst).is_less_equal(MOTION_MARGIN_M)
	assert_float(wild).is_greater(MOTION_MARGIN_M)


## The most any bubble's surface, moving with drift `drift`, gets past the
## still lather's reach (R_MAX * (1 + OUT) out of its body envelope).
func _lather_excess(drift: float) -> float:
	var worst := -INF
	for b in ShowerFoam.bubbles():
		var reach := b.w * (1.0 + ShowerFoam.SWELL + drift * sqrt(1.25))
		var out := INF
		for part: Array in ShowerFoam.PARTS:
			if b.y < part[2] - 0.001 or b.y > part[3] + 0.001:
				continue
			var at := Vector2(b.x - part[0], b.z - part[1])
			out = minf(out, _ellipse_out(at, part[4], part[5]))
		worst = maxf(worst, out + reach - ShowerFoam.R_MAX * (1.0 + ShowerFoam.OUT))
	return worst


## How far point `at` lies outside the ellipse of half axes `rx`, `rz`
## (negative inside), by the nearest of 720 points round it.
func _ellipse_out(at: Vector2, rx: float, rz: float) -> float:
	var near := INF
	for i in 720:
		var turn := i * TAU / 720.0
		near = minf(near, at.distance_to(Vector2(cos(turn) * rx, sin(turn) * rz)))
	var inside := pow(at.x / rx, 2.0) + pow(at.y / rz, 2.0) < 1.0
	return -near if inside else near


func _materials(mi: MeshInstance3D) -> Array:
	var out := []
	for i in mi.mesh.get_surface_count():
		out.append(mi.get_active_material(i))
	return out


func _surface_materials(mesh: Mesh) -> Array:
	var out := []
	for i in mesh.get_surface_count():
		out.append(mesh.surface_get_material(i))
	return out


## How bare mesh `bare` of body `body` draws: its clothes surface's vertex
## count, how many of them sample anything but the body's skin texel, how
## many clothes triangles are left on the other surface, and whether the skin
## is a warm tone.
func _skin_report(body: int, bare: Mesh) -> Dictionary:
	var atlas := ActivityPoses.atlas_image(bare)
	var skin := ActivityPoses.atlas_colour(atlas, ActivityPoses.skin_uv(body))
	var arrays := bare.surface_get_arrays(1)
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var off := 0
	for i in index:
		if ActivityPoses.atlas_colour(atlas, uvs[i]) != skin:
			off += 1
	var kept := bare.surface_get_arrays(0)
	var colors: PackedColorArray = kept[Mesh.ARRAY_COLOR]
	var left: PackedInt32Array = PassengerLooks.cloth_split(kept[Mesh.ARRAY_INDEX], colors)[1]
	return {
		"vertices": index.size(),
		"off_skin": off,
		"clothes_left": left.size() / 3,
		"warm": skin.r > skin.g and skin.g > skin.b,
		"skin": skin.to_html(false),
	}


## Passengers in the sim other than `id` drawn with body `body`.
func _same_body_count(id: int, body: int) -> int:
	var count := 0
	for other in _world.sim.passenger_ids():
		var p := _world.sim.get_passenger(other)
		if other != id and PassengerLooks.body_of(other, p.variant) == body:
			count += 1
	return count


## Every other drawn passenger: how many, how many of them have the body of
## `id`, how many draw a bare mesh, and how many draw exactly their own look
## (PassengerLooks) with its materials.
func _other_looks(id: int) -> Dictionary:
	var body_of_id: int = _views.node_for(id).get_meta(&"body")
	var out := {"count": 0, "same_body": 0, "bare": 0, "own_look": 0}
	for other: int in _views._nodes:
		if other == id:
			continue
		var p := _world.sim.get_passenger(other)
		var body := PassengerLooks.body_of(other, p.variant)
		var tint := PassengerLooks.tint_of(other)
		var mi := PassengerLooks.body_mesh(_views.node_for(other))
		var look := (
			PassengerLooks.plain_mesh(body) if tint == 0 else PassengerLooks.split_mesh(body, tint)
		)
		out["count"] += 1
		if body == body_of_id:
			out["same_body"] += 1
		if mi.mesh == ActivityPoses.bare_mesh(body):
			out["bare"] += 1
		if mi.mesh == look and _materials(mi) == _surface_materials(look):
			out["own_look"] += 1
	return out


func _recline(node: Node3D) -> float:
	var recline: PodRecline = node.get_meta(&"recline") if node.has_meta(&"recline") else null
	return recline.amount if recline != null else 0.0


func _drawn(views: PassengerViews, id: int) -> Array:
	var node := views.node_for(id)
	return [
		views.tick_position(id, true).snapped(Vector3.ONE * 0.0001),
		snappedf(node.rotation.y, 0.0001),
		node.get_meta(&"clip", ""),
		snappedf(_recline(node), 0.0001),
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


## Loads a save back into the open world in place, as SaveGame does.
func _restore(text: String) -> void:
	var data: Dictionary = JSON.parse_string(text)
	assert_bool(_world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(_world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(_world.sim.from_snapshot(data["passengers"])).is_true()


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
