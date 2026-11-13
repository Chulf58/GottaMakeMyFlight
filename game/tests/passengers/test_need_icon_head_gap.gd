class_name TestNeedIconHeadGap
extends GdUnitTestSuite
## A passenger's need icon row and its wish bubble sit one fixed screen gap over
## the top of the head as drawn, standing, seated on a gate chair, reclined in
## a nap pod and all through a stand-up, at the 70 and 38 degree camera steps;
## a count badge's chip keeps clear of the heads in a standing crowd (decision
## need-icons-and-wish-bubbles-sit-a-fixed-screen-gap-above-the, board
## b679fd1d). Measured on the real PassengerViews from the real Head bone, not
## from NeedIcons' constants: the top of the tallest head on screen is the
## bone moved REACH_M along the camera's up (the furthest any of the twelve
## bodies' head or hair vertices reach from the bone that way, over 24 yaws,
## in the rest pose). Before the ruling a seated row stood about 50 px over
## the head at 38 degrees, while a standing one at 70 degrees touched it.
## NeedIcons reads the same bone, so test_a_rest_pose_row_clears_the_drawn_
## mesh_top checks against the body's mesh instead; the windowed plates
## (game/spike/icon_head_gap_plates_probe.gd) check the head as drawn.

const TOILET := NeedIcons.Need.TOILET
## Pitch (degrees) -> the tallest head's reach over its Head bone along the
## camera's up, metres.
const REACH_M := {70.0: 0.208, 38.0: 0.240}
## Mesh vertices over the Head bone and this near it across (horizontally) count
## as the head. The rest pose holds the arms out, and at a quarter turn an arm
## tip stands over the head on screen, which is no head.
const HEAD_NEAR_M := 0.3
## How much more than HEAD_GAP_PX a lower head may leave under the row at
## DISTANCE_M (the plainest head reaches 0.09 to 0.1 m less than the tallest).
const MESH_SLACK_PX := 12.0
## The camera's distance from the head, and the two angle steps measured.
const DISTANCE_M := 12.0
const PITCHES: Array[float] = [70.0, 38.0]
## The body yaws (degrees) the mesh top is measured at.
const YAWS: Array[float] = [0.0, 90.0, 180.0, 270.0]
## The gap every row and wish bubble keeps over the tallest head's top, in
## screen pixels (NeedIcons.HEAD_GAP_PX plus the ball's 0.015 m margin over
## REACH_M), and how far off it a measurement may be.
const GAP_PX := 7.5
const TOLERANCE_PX := 3.0
## Ticks into the stand-up sampled (PassengerSim.STAND_UP_TICKS is the clip).
const RISE_TICKS: Array[int] = [0, 4, 8, 12, 16, 20, 24]
## The band a rising row's gap stays in, and its largest change between two
## sampled ticks (a sixth of the clip apart), in screen pixels.
const RISE_MIN_PX := 2.0
const RISE_MAX_PX := 12.0
const RISE_STEP_PX := 4.0
## The largest change in a row's gap from one rendered frame to the next while a
## clip plays (0.4 px at most at 3x), the frames played after the clip ends (the
## crossfade out of it), and the most frames a clip takes.
const FRAME_STEP_PX := 1.0
## How far a row's anchor may be from the head centre as posed this frame, metres.
const TRAIL_M := 0.002
const SETTLE_AFTER := 20
const MAX_FRAMES := 4000
## The standing queue's length.
const QUEUE := 6
## Frames a settled sit takes to pose the skeleton.
const SETTLE_FRAMES := 30

var _world: PassengerTestWorld
var _views: PassengerViews
var _camera: Camera3D
var _screen: SubViewport
var _path: String


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _path != "":
		DirAccess.remove_absolute(_path)
		_path = ""
	if _screen != null:
		_screen.free()
		_screen = null
		_views = null
	if _world != null:
		_world.free_all()
		_world = null


## Both skeletons (variant 0 male, 1 female; the male head stands higher).
func test_a_standing_row_and_wish_bubble_keep_the_gap_at_both_angles(
	variant: int, _test_parameters := [[0], [1]]
) -> void:
	_world = _facility_world()
	_open_views()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.passenger(id).variant = variant
	ToiletTestLayout.calm(_world.passenger(id))
	_world.step()
	_views.sync()
	# Frames for the clip to pose the skeleton; before them it stands in the
	# rest pose.
	for i in SETTLE_FRAMES:
		await await_idle_frame()
	var node := _views.node_for(id)
	assert_bool(node.get_meta(&"icon_seated", false)).is_false()
	var tag := "standing variant %d" % variant
	_check_gaps(node, tag)
	WishIconView.show_wish(node, [&"kiosk", WishTable.State.WANTED])
	_check_gaps(node, tag + "+wish", true)


## Against the body's mesh, not its bones, for every one of the twelve bodies
## (PassengerLooks.SCENES) at both camera steps and four yaws: before any frame
## poses it the body stands in its rest pose (the control: its Head bone at the
## skeleton's rest height), where the mesh's vertices are where they are drawn.
## The row's bottom stands HEAD_GAP_PX or more over the highest drawn vertex and
## never far over it, so a wrong bone picked by NeedIcons.find_head(), or a
## body whose hair or bun reaches past the fitted ball, fails here.
func test_a_rest_pose_row_clears_the_drawn_mesh_top(
	body: int, _test_parameters := [[0], [1], [2], [3], [4], [5], [6], [7], [8], [9], [10], [11]]
) -> void:
	_world = _facility_world()
	_open_views()
	# The passengers spawned on the way to this body's look stand at the same
	# cell, and their icons would merge into one badge with the row's.
	_views.cluster_needs = false
	var variant := body / PassengerLooks.PER_VARIANT
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT, variant)
	while PassengerLooks.body_of(id, variant) != body:
		id = _world.sim.spawn_now(PassengerTestWorld.FLIGHT, variant)
	ToiletTestLayout.calm(_world.passenger(id))
	_world.step()
	_views.sync()
	var node := _views.node_for(id)
	assert_int(node.get_meta(&"body", -1)).is_equal(body)
	var skeleton := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bone := skeleton.find_bone(NeedIcons.HEAD_BONE)
	assert_vector(skeleton.get_bone_global_pose(bone).origin).is_equal_approx(
		skeleton.get_bone_global_rest(bone).origin, Vector3.ONE * 0.001
	)
	var needs: Array[NeedIcons.Need] = [TOILET]
	NeedIcons.show_needs(node, needs)
	(node.get_node("Bubble") as Label3D).text = ""
	for yaw in YAWS:
		# The views draw the node with its turn's yaw, so the yaw is set there.
		_views._turns.place(id, deg_to_rad(yaw))
		for pitch in PITCHES:
			_views.draw()
			_aim(_head_bone(node), pitch)
			_views.draw()
			assert_float(absf(angle_difference(node.rotation.y, deg_to_rad(yaw)))).is_less(0.001)
			var row := _bottom_y(node.get_node(NeedIcons.SPRITES[0]), false)
			var gap := _mesh_top_y(node) - row
			var tag := "body %d yaw %.0f at %.0f degrees" % [body, yaw, pitch]
			print("rest pose %s: mesh gap %.1f px" % [tag, gap])
			var spr := node.get_node(NeedIcons.SPRITES[0]) as Sprite3D
			assert_float(gap).override_failure_message("%s: gap %.1f px" % [tag, gap]).is_between(
				NeedIcons.HEAD_GAP_PX - 0.5, NeedIcons.HEAD_GAP_PX + MESH_SLACK_PX
			)


## A VIP's crown stands GAP_PX over its icon row at both angles, not over the
## old fixed lift (decision need-icons-and-wish-bubbles-sit-a-fixed-screen-gap-
## above-the).
func test_a_crown_stacks_over_the_row_at_both_angles() -> void:
	_world = _facility_world()
	_open_views()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	ToiletTestLayout.calm(_world.passenger(id))
	_world.step()
	_views.sync()
	var node := _views.node_for(id)
	VipMarker.mark(node, true)
	var needs: Array[NeedIcons.Need] = [TOILET]
	NeedIcons.show_needs(node, needs)
	(node.get_node("Bubble") as Label3D).text = ""
	var crown := node.get_node(VipMarker.SPRITE) as Sprite3D
	for pitch in PITCHES:
		_aim(_head_bone(node), pitch)
		_views.draw()
		_views.draw()
		var row_top := _bottom_y(node.get_node(NeedIcons.SPRITES[0]), false) - NeedIcons.ICON_PX
		assert_bool(crown.visible).is_true()
		var lift := (crown.offset.y - VipMarker.SIZE / 2.0) * VipMarker.CROWN_PX / VipMarker.SIZE
		var crown_bottom := _camera.unproject_position(crown.global_position).y - lift
		print("crown at %.0f degrees: %.1f px over the row" % [pitch, row_top - crown_bottom])
		assert_float(row_top - crown_bottom).is_equal_approx(NeedIcons.GAP_PX, 0.5)


func test_a_seated_row_keeps_the_gap_at_both_angles(
	variant: int, _test_parameters := [[0], [1]]
) -> void:
	var p := _sitter(variant)
	_views.snap()
	# Frames for the seated clip to pose the skeleton (snap() seeks only the
	# clip the sim is in; the sit settles through the crossfade).
	for i in SETTLE_FRAMES:
		await await_idle_frame()
	var node := _views.node_for(p.id)
	assert_bool(node.get_meta(&"icon_seated", false)).is_true()
	var tag := "seated variant %d" % variant
	_check_gaps(node, tag)
	WishIconView.show_wish(node, [&"kiosk", WishTable.State.WANTED])
	_check_gaps(node, tag + "+wish", true)


func test_a_reclined_row_keeps_the_gap_at_both_angles() -> void:
	var grid := BuildGrid.new()
	ActivityTestLayout.build(grid, &"nap_pod")
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	_world.auto_staff_roles = [StaffMember.Role.CHECKIN, StaffMember.Role.SECURITY]
	_world.run_to(10)
	_open_views()
	var p := ShopTestLayout.airside_guest(_world, 80, ShopTestLayout.AIRSIDE_CELL)
	var limit := _world.clock.tick + 3000
	while ActivityPoses.recline(_world.sim, p) < 1.0 and _world.clock.tick < limit:
		_world.step()
	_views.snap()
	var node := _views.node_for(p.id)
	assert_bool(node.get_meta(&"icon_reclined", false)).is_true()
	_check_gaps(node, "reclined")


## Through the stand-up from a gate chair the row moves with the head (board
## 3a5e1d0d): the gap at every sampled tick, inside RISE_MIN_PX to RISE_MAX_PX
## whatever the tolerance, and a change of at most RISE_STEP_PX from one
## sampled tick to the next, so it never pops.
func test_a_rising_row_keeps_the_gap_through_the_stand_up() -> void:
	var p := _sitter()
	var last := {}
	for ticks in RISE_TICKS:
		p.stage = Passenger.Stage.STANDING_UP
		p.stage_tick = _world.sim.tick - ticks
		_views.snap()
		var node := _views.node_for(p.id)
		var gaps := _check_gaps(node, "rising %d" % ticks)
		for pitch: float in gaps:
			var gap: float = gaps[pitch]
			(
				assert_float(gap)
				. override_failure_message("rising %d at %.0f: gap %.1f px" % [ticks, pitch, gap])
				. is_between(RISE_MIN_PX, RISE_MAX_PX)
			)
			if last.has(pitch):
				(
					assert_float(absf(gap - float(last[pitch])))
					. override_failure_message("rising %d at %.0f: the row jumped" % [ticks, pitch])
					. is_less_equal(RISE_STEP_PX)
				)
			last[pitch] = gap


## Through the stand-up and the sit-down played frame by frame, as the game
## plays them (the clock advanced by each frame's real delta, the animation
## player running, the crossfade easing, at 1x and 3x speed): at every frame the
## row's anchor is the head as posed that frame (within TRAIL_M), the row stands
## GAP_PX over it within TOLERANCE_PX and moves at most FRAME_STEP_PX from one
## frame to the next. A row laid out from the bone read before the animation
## moved it this frame trails the head by a frame's motion (PassengerViews runs
## after the animation players, process_priority).
func test_the_row_follows_the_head_through_real_frames(
	stage: Passenger.Stage,
	speed: int,
	pitch: float,
	_test_parameters := [
		[Passenger.Stage.STANDING_UP, 1, 70.0],
		[Passenger.Stage.STANDING_UP, 3, 70.0],
		[Passenger.Stage.STANDING_UP, 1, 38.0],
		[Passenger.Stage.STANDING_UP, 3, 38.0],
		[Passenger.Stage.SITTING_DOWN, 1, 70.0],
		[Passenger.Stage.SITTING_DOWN, 3, 70.0],
		[Passenger.Stage.SITTING_DOWN, 1, 38.0],
		[Passenger.Stage.SITTING_DOWN, 3, 38.0],
	]
) -> void:
	# A world with a toilet built, or the toilet icon is not shown at all.
	var p := _sitter(1, true)
	p.toilet_need = ToiletSim.NEED_MAX
	# Settled where the clip starts: seated to stand up, standing to sit down.
	p.stage = (
		Passenger.Stage.SEATED if stage == Passenger.Stage.STANDING_UP else Passenger.Stage.STANDING
	)
	_views.snap()
	for i in SETTLE_FRAMES:
		await await_idle_frame()
	var node := _views.node_for(p.id)
	var row := node.get_node(NeedIcons.SPRITES[0]) as Sprite3D
	_aim(node.global_position + Vector3(0.0, 1.4, 0.0), pitch)
	_world.clock.set_speed(speed)
	p.stage = stage
	p.stage_tick = _world.sim.tick
	_views.sync()
	var tag := "%s at %dx, %.0f degrees" % [Passenger.Stage.keys()[stage], speed, pitch]
	var frames := 0
	var after := 0
	var seen := 0
	var trail := 0.0
	var last := INF
	var low := INF
	var high := -INF
	var worst := 0.0
	while after < SETTLE_AFTER and frames < MAX_FRAMES:
		var delta := clampf(_views.get_process_delta_time(), 0.001, 0.1)
		_world.clock.advance(delta)
		await await_idle_frame()
		frames += 1
		if p.stage != stage:
			after += 1
		if not row.visible:
			continue
		seen += 1
		var bubble := node.get_node("Bubble") as Label3D
		assert_str(bubble.text).override_failure_message("%s: a speech bubble" % tag).is_empty()
		# The row's anchor is where the head is posed now, not a frame back.
		var centre := node.global_transform * NeedIcons.head_centre(node)
		trail = maxf(trail, row.global_position.distance_to(centre))
		var gap := _head_top_y(node, pitch) - _bottom_y(row, false)
		if last < INF:
			worst = maxf(worst, absf(gap - last))
		last = gap
		low = minf(low, gap)
		high = maxf(high, gap)
	print(
		(
			"%s: %d frames (%d seen), gap %.1f to %.1f px, step %.2f px, trail %.4f m"
			% [tag, frames, seen, low, high, worst, trail]
		)
	)
	# The control: the row was drawn for most of the clip's frames.
	(
		assert_int(seen)
		. override_failure_message("%s: the row showed %d frames" % [tag, seen])
		. is_greater(frames / 2)
	)
	(
		assert_bool(p.stage != stage)
		. override_failure_message("%s: the clip never ended" % tag)
		. is_true()
	)
	assert_float(low).override_failure_message("%s: gap %.1f px" % [tag, low]).is_greater_equal(
		GAP_PX - TOLERANCE_PX
	)
	assert_float(high).override_failure_message("%s: gap %.1f px" % [tag, high]).is_less_equal(
		GAP_PX + TOLERANCE_PX
	)
	(
		assert_float(trail)
		. override_failure_message("%s: the row trails the head by %.4f m" % [tag, trail])
		. is_less_equal(TRAIL_M)
	)
	assert_float(worst).override_failure_message("%s: step %.2f px" % [tag, worst]).is_less_equal(
		FRAME_STEP_PX
	)


## A standing queue with the toilet need, one passenger a cell running away
## from the camera as a check-in or boarding queue does, forms a count badge;
## the badge and its count chip stay off every head at both angles.
func test_a_badge_and_its_chip_keep_clear_of_a_standing_queue() -> void:
	_world = _facility_world()
	_open_views()
	var ids: Array[int] = []
	for i in QUEUE:
		ids.append(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	_world.step()
	var start := _world.passenger(ids[0]).at
	for i in ids.size():
		var p := _world.passenger(ids[i])
		ToiletTestLayout.calm(p)
		p.toilet_need = ToiletSim.NEED_MAX
		p.at = start + Vector2i(0, -i)
		p.clear_path()
		p.stage = Passenger.Stage.STANDING
		p.stage_tick = _world.sim.tick
	_views.sync()
	_views.snap()
	for i in SETTLE_FRAMES:
		await await_idle_frame()
	var centre := Vector3.ZERO
	for id in ids:
		centre += _views.node_for(id).global_position
	centre /= ids.size()
	for pitch in PITCHES:
		_aim(centre + Vector3(0.0, 1.7, 0.0), pitch)
		_views.draw()
		_views.draw()
		var badges := _views.need_badges()
		(
			assert_int(badges.size())
			. override_failure_message("no count badge at %.0f degrees" % pitch)
			. is_greater(0)
		)
		var heads := _head_rects(pitch)
		for b: Dictionary in badges:
			var rect: Rect2 = b["rect"]
			# Where the badge wants to be before any dodge: over its anchor's
			# row, the chip under the icon clear of the anchor's own head (the
			# head under the badge's centre), as the row is.
			var shift: Vector2 = _views.need_clusters._shifts[b["id"]]
			var wanted := Rect2(rect.position - shift, rect.size)
			var own := _head_under(wanted, heads)
			var over: Array = []
			for id: int in heads:
				if rect.intersects(heads[id]):
					over.append(id)
			print(
				(
					"pitch %.0f badge %s wanted %s count %d own head %s over heads %s"
					% [pitch, rect, wanted, b["count"], own, over]
				)
			)
			(
				assert_float(own.position.y - wanted.end.y)
				. override_failure_message(
					"at %.0f degrees the chip reaches into its own head %s" % [pitch, own]
				)
				. is_greater_equal(0.0)
			)
			(
				assert_array(over)
				. override_failure_message(
					"at %.0f degrees the badge %s is over heads %s" % [pitch, rect, over]
				)
				. is_empty()
			)


func _facility_world() -> PassengerTestWorld:
	var grid := BuildGrid.new()
	NeedFacilityKit.build(grid)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	world.run_to(10)
	world.sim.shops.wishes = func(_p: Passenger) -> StringName: return WishTable.NONE
	return world


## The views drawn into a 1920 x 1080 viewport, as the game window draws.
func _open_views() -> void:
	_path = SaveTestKit.run_path("need_icon_head_gap")
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	_views.need_icons_toggle.settings_path = _path
	_screen = SubViewport.new()
	_screen.size = Vector2i(1920, 1080)
	add_child(_screen)
	_screen.add_child(_views)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_screen.add_child(_camera)
	_camera.make_current()


## A passenger settled on the first gate chair of the reference terminal.
func _sitter(variant := 1, facilities := false) -> Passenger:
	_world = _facility_world() if facilities else PassengerTestWorld.reference_world()
	_world.run_to(10)
	_open_views()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	p.variant = variant
	ToiletTestLayout.calm(p)
	p.cleared = true
	var seat: Dictionary = _world.sim.layout.seats[0]
	p.seat_object = seat["object_id"]
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.at = seat["front"]
	p.clear_path()
	p.stage = Passenger.Stage.SEATED
	p.stage_tick = _world.sim.tick
	_views.sync()
	return p


func _aim(target: Vector3, pitch_deg: float) -> void:
	var pitch := deg_to_rad(pitch_deg)
	_camera.global_position = target + Vector3(0.0, sin(pitch), cos(pitch)) * DISTANCE_M
	_camera.look_at(target)


## Shows the toilet icon on `node` (and keeps any wish it shows), lays it out
## at both angles and, with `strict`, checks the row's gap is GAP_PX within
## TOLERANCE_PX, and the wish bubble's with `wish`. Returns pitch -> the row's
## gap.
func _check_gaps(node: Node3D, tag: String, wish := false, strict := true) -> Dictionary:
	var out := {}
	var needs: Array[NeedIcons.Need] = [TOILET]
	NeedIcons.show_needs(node, needs)
	# No speech bubble: the row would stand on it instead (row_anchor()).
	(node.get_node("Bubble") as Label3D).text = ""
	var bone := node.global_transform.affine_inverse() * _head_bone(node)
	print("%s: head bone %s, body %d" % [tag, bone, node.get_meta(&"body", -1)])
	for pitch in PITCHES:
		_aim(_head_bone(node), pitch)
		_views.draw()
		_views.draw()
		var top := _head_top_y(node, pitch)
		var gaps: Array[float] = [top - _bottom_y(node.get_node(NeedIcons.SPRITES[0]), false)]
		if wish:
			gaps.append(top - _bottom_y(node.get_node(WishIconView.SPRITE), true))
		out[pitch] = gaps[0]
		for gap in gaps:
			print("%s at %.0f degrees: gap %.1f px" % [tag, pitch, gap])
			if not strict:
				continue
			(
				assert_float(gap)
				. override_failure_message(
					(
						"%s at %.0f degrees: the row stands %.1f px over the head top"
						% [tag, pitch, gap]
					)
				)
				. is_between(GAP_PX - TOLERANCE_PX, GAP_PX + TOLERANCE_PX)
			)
	return out


## The tallest head's top on screen (y, pixels) at `pitch`: the Head bone
## moved REACH_M along the camera's up.
func _head_top_y(node: Node3D, pitch: float) -> float:
	var head := _head_bone(node)
	return _camera.unproject_position(head + _camera.global_basis.y * float(REACH_M[pitch])).y


## The top on screen (y, pixels) of `node`'s body mesh as drawn in the rest
## pose: the highest projected vertex over the Head bone within HEAD_NEAR_M of it
## across. Read
## off the mesh, not the skeleton.
func _mesh_top_y(node: Node3D) -> float:
	var mesh := PassengerLooks.body_mesh(node)
	var head := _head_bone(node)
	var top := INF
	for s in mesh.mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			var at := mesh.global_transform * v
			var across := Vector2(at.x - head.x, at.z - head.z).length()
			if at.y >= head.y and across <= HEAD_NEAR_M:
				top = minf(top, _camera.unproject_position(at).y)
	return top


## The bottom edge on screen (y, pixels) of a need icon sprite, or of the wish
## bubble sprite with `wish`, as drawn: its anchor's projection lifted by its
## offset.
func _bottom_y(sprite: Sprite3D, wish: bool) -> float:
	assert_bool(sprite.visible).is_true()
	var size := float(WishIconView.SIZE if wish else NeedIcons.SIZE)
	var px := WishIconView.WISH_PX if wish else NeedIcons.ICON_PX
	var lift := (sprite.offset.y - size / 2.0) * px / size
	return _camera.unproject_position(sprite.global_position).y - lift


## Passenger id -> its head's screen rect at `pitch`: a square twice REACH_M
## across from the tallest head's top on screen down.
func _head_rects(pitch: float) -> Dictionary:
	var out := {}
	var reach: float = REACH_M[pitch]
	for id in _world.sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null:
			continue
		var head := _head_bone(node)
		var top := _camera.unproject_position(head + _camera.global_basis.y * reach)
		var side := _camera.unproject_position(head + _camera.global_basis.x * reach)
		var wide := 2.0 * side.distance_to(_camera.unproject_position(head))
		out[id] = Rect2(top - Vector2(wide / 2.0, 0.0), Vector2.ONE * wide)
	return out


## Of `heads` under `badge` (sharing some of its screen x), the one whose top
## lies nearest under the badge's centre: the head of the passenger the badge
## stands over.
func _head_under(badge: Rect2, heads: Dictionary) -> Rect2:
	var best := Rect2()
	var best_dy := INF
	var centre := badge.get_center()
	for id: int in heads:
		var head: Rect2 = heads[id]
		var dy := head.position.y - centre.y
		var across := head.position.x < badge.end.x and head.end.x > badge.position.x
		if across and dy > 0.0 and dy < best_dy:
			best_dy = dy
			best = head
	assert_float(best_dy).is_less(INF)
	return best


func _head_bone(node: Node3D) -> Vector3:
	for skeleton in node.find_children("*", "Skeleton3D", true, false):
		var bones := skeleton as Skeleton3D
		for i in bones.get_bone_count():
			if bones.get_bone_name(i).to_lower().contains("head"):
				return bones.global_transform * bones.get_bone_global_pose(i).origin
	fail("no head bone on passenger %s" % node.name)
	return Vector3.ZERO
