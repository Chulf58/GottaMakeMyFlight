class_name TestNeedIconHeadGap
extends GdUnitTestSuite
## A passenger's need icon row and its wish bubble sit one fixed screen gap over
## the top of the head as drawn, standing, seated on a gate chair, reclined in
## a nap pod and all through a stand-up, at the 70 and 38 degree camera steps;
## a count badge's chip keeps clear of the heads in a standing crowd (decision
## need-icons-and-wish-bubbles-sit-a-fixed-screen-gap-above-the, board
## b679fd1d). Measured on the real PassengerViews from the real Head bone, not
## from NeedIcons' constants: the head is taken as a ball HEAD_UP_M round the
## bone (the head top the need_icon_near_camera probe measured, 0.12 m over
## the bone), so its top on screen is the bone moved HEAD_UP_M along the
## camera's up. Before the ruling a seated row stood about 50 px over the head
## at 38 degrees, while a standing one at 70 degrees touched it. NeedIcons
## reads the same bone now, so this checks the projection and the drawn
## offsets; the windowed plates (game/spike/icon_head_gap_plates_probe.gd)
## check the head as drawn.

const TOILET := NeedIcons.Need.TOILET
const HEAD_UP_M := 0.12
## The camera's distance from the head, and the two angle steps measured.
const DISTANCE_M := 12.0
const PITCHES: Array[float] = [70.0, 38.0]
## The gap every row and wish bubble keeps over the head top, in screen
## pixels, and how far off it a measurement may be (the bone moves a little
## between the layout and the reading, and the ball is a model of the head).
const GAP_PX := 6.0
const TOLERANCE_PX := 3.0
## Ticks into the stand-up sampled (PassengerSim.STAND_UP_TICKS is the clip).
const RISE_TICKS: Array[int] = [0, 4, 8, 12, 16, 20, 24]
## The band a rising row's gap stays in, and its largest change between two
## sampled ticks (a sixth of the clip apart), in screen pixels.
const RISE_MIN_PX := 2.0
const RISE_MAX_PX := 12.0
const RISE_STEP_PX := 4.0
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
		var heads := _head_rects()
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
func _sitter(variant := 1) -> Passenger:
	_world = PassengerTestWorld.reference_world()
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
		var top := _head_top_y(node)
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


## The head's top on screen (y, pixels): the Head bone moved HEAD_UP_M along
## the camera's up.
func _head_top_y(node: Node3D) -> float:
	var head := _head_bone(node)
	return _camera.unproject_position(head + _camera.global_basis.y * HEAD_UP_M).y


## The bottom edge on screen (y, pixels) of a need icon sprite, or of the wish
## bubble sprite with `wish`, as drawn: its anchor's projection lifted by its
## offset.
func _bottom_y(sprite: Sprite3D, wish: bool) -> float:
	assert_bool(sprite.visible).is_true()
	var size := float(WishIconView.SIZE if wish else NeedIcons.SIZE)
	var px := WishIconView.WISH_PX if wish else NeedIcons.ICON_PX
	var lift := (sprite.offset.y - size / 2.0) * px / size
	return _camera.unproject_position(sprite.global_position).y - lift


## Passenger id -> its head's screen rect: a square HEAD_UP_M * 2 across from
## the head's top on screen down.
func _head_rects() -> Dictionary:
	var out := {}
	for id in _world.sim.passenger_ids():
		var node := _views.node_for(id)
		if node == null:
			continue
		var head := _head_bone(node)
		var top := _camera.unproject_position(head + _camera.global_basis.y * HEAD_UP_M)
		var side := _camera.unproject_position(head + _camera.global_basis.x * HEAD_UP_M)
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
