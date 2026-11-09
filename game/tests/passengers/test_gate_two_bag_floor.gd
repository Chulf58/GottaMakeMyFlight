extends GdUnitTestSuite
## A two-bag guest's bags down at a gate chair (SecurityLooks.floor_spot(), the
## bags that are not a roller) lie clear of the guest's feet while it stands at
## the chair front, and stay clear seated (board fc38d1b2: standing, the second
## bag lay on the guest's own foot). Geometric, as test_gate_chair_roller_spot:
## each body's idle, sit_down and sit_idle clips posed at PHASES points and
## skinned by hand (TestRollerStandClearance._skinned()), and no vertex may lie
## in a bag's box grown by MARGIN_M. Everything is in the chair front's frame:
## the front cell's centre at the origin, out of the chair +z, cells 1 m apart.

const PHASES := 8
const MARGIN_M := 0.01
## How far (m, flat) a settled floor bag may be drawn off its spot.
const STILL_M := 0.001
## The bag kinds that lie where floor_spot() puts them at a gate chair (a
## roller lies beside the feet, GateRoller.spot()).
const FLOOR_KINDS: Array[SecurityLooks.Kind] = [
	SecurityLooks.Kind.CASE, SecurityLooks.Kind.BACKPACK, SecurityLooks.Kind.SHOULDER
]

## Per body (PassengerLooks.BODIES): its idle, sit_down (PHASES + 1) and
## sit_idle poses, each the body's vertices in its own frame (facing +z).
var _idle: Array = []
var _sit_down: Array = []
var _sit: Array = []
var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self
	for b in PassengerLooks.BODIES.size():
		var node := PassengerLooks.SCENES[b].instantiate() as Node3D
		add_child(node)
		var player := node.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for clip in ["idle", "sit_down", "sit_idle"]:
			player.play(clip)
			var poses: Array[PackedVector3Array] = []
			for n in PHASES + 1:
				if n == PHASES and clip != "sit_down":
					break
				player.seek(player.current_animation_length * n / PHASES, true)
				poses.append(TestRollerStandClearance._skinned(node))
			{"idle": _idle, "sit_down": _sit_down, "sit_idle": _sit}[clip].append(poses)
		node.free()


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
	if _world != null:
		_world.free_all()
	_views = null
	_world = null


func _tick() -> void:
	_world.clock.advance(SimClock.STEP)
	await get_tree().process_frame


## Every body standing at the chair front (idle), going down onto any of a
## row's three chairs (sit_down, eased from the front to the seat) and seated
## (sit_idle): no vertex in either bag's box, for every kind that lies by
## floor_spot(), at SecurityLooks.TWO_BAG_SCALE. The least gap per body is
## printed.
func test_two_floor_bags_clear_every_body_standing_and_seated() -> void:
	var hits := 0
	var least := INF
	for b in _idle.size():
		var near := INF
		var line := "body %d %s:" % [b, PassengerLooks.BODIES[b]]
		for kind in FLOOR_KINDS:
			for index in 2:
				var bag := SecurityLooks.gate_two_bag(b, index)
				var stand := _inside(_idle[b], Transform3D.IDENTITY, bag, kind)
				var down := 0
				var sat := 0
				for chair in GateChairs.CHAIR_OFFSET_M.size():
					down += _going_down(b, chair, bag, kind)
					sat += _inside(_sit[b], _seated(b, chair), bag, kind)
				var n := stand + down + sat
				hits += n
				if n > 0:
					line += (
						" %s bag %d: standing %d going down %d seated %d"
						% [SecurityLooks.Kind.keys()[kind], index, stand, down, sat]
					)
				near = minf(near, _gap(_idle[b], Transform3D.IDENTITY, bag, kind))
		least = minf(least, near)
		print("%s least standing gap %.3f m" % [line, near])
	print("vertices inside %d (0), least standing gap %.3f m (>= %.2f)" % [hits, least, MARGIN_M])
	assert_int(hits).is_equal(0)
	assert_float(least).is_greater_equal(MARGIN_M)


## Discriminating control: the spot before board fc38d1b2, SEAT_AHEAD_M ahead
## of the sim's seat spot (where the body stands once the sim's shuffle is
## done while it is still drawn at the front), takes in the feet of most
## bodies standing at the front.
func test_the_old_spot_takes_in_the_standing_feet() -> void:
	var bodies := 0
	for b in _idle.size():
		var n := 0
		for kind in FLOOR_KINDS:
			for index in 2:
				var side := (
					-SecurityLooks.FLOOR_APART_M if index == 0 else SecurityLooks.FLOOR_APART_M
				)
				var seat := _seated(b, 1).origin
				var old := Transform3D(
					Basis.IDENTITY, Vector3(seat.x + side, 0.0, seat.z + SecurityLooks.SEAT_AHEAD_M)
				)
				n += _inside(_idle[b], Transform3D.IDENTITY, old, kind)
		print("body %d %s at the old spot: %d" % [b, PassengerLooks.BODIES[b], n])
		bodies += int(n > 0)
	print("bodies with vertices in an old-spot bag %d of %d" % [bodies, _idle.size()])
	assert_int(bodies).is_greater(_idle.size() / 2)


## Drawn through the views: a two-bag walker sitting down at the reference
## terminal's first gate chair has its bag that is not a roller lie at its
## fixed spot in the chair front's frame (gate_two_bag(), within STILL_M) on
## every frame it is on the floor and settled, the frames the drawn body eases
## from the front onto the chair included (stepped half a tick at a time, so
## frames between ticks are drawn too), while the sim moves the body 0.55 m (the
## control). On each such frame no vertex of the body, posed in that frame's
## clip at its nearest PHASES point and drawn where the views draw it, lies in
## the bag. Before board fc38d1b2's fix round the bag was laid in the drawn
## body's frame less the tick's sit offset and moved 0.087 m while the body
## eased in.
func test_the_drawn_floor_bag_lies_still_at_its_spot_clear_of_the_feet() -> void:
	var p := await _sitting_walker()
	var props := _views.carry_on_props()
	var seat: Dictionary = _world.sim.layout.seats[0]
	var out: Vector3 = (
		_world.grid.cell_to_world(seat["front"]) - _world.grid.cell_to_world(seat["cell"])
	)
	var front := Transform3D(
		Basis(Vector3.UP, atan2(out.x, out.z)), _world.grid.cell_to_world(seat["front"])
	)
	var b := PassengerLooks.body_of(p.id, p.variant)
	var other := 0 if SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER else 1
	var kind := SecurityLooks.bag_kind(p, other)
	var want := SecurityLooks.gate_two_bag(b, other).origin
	var start := _world.sim.world_position(p)
	var moved := 0.0
	var off := 0.0
	var frames := 0
	var moving := 0
	var hits := 0
	var clips := {}
	var body := _views.node_for(p.id)
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	var drawn_was := body.global_position
	for n in 120:
		_world.clock.advance(SimClock.STEP * 0.5)
		await get_tree().process_frame
		moved = maxf(moved, start.distance_to(_world.sim.world_position(p)))
		var bag := props.bag_state(p.id, other)
		var stepped := body.global_position.distance_to(drawn_was) > 0.0001
		drawn_was = body.global_position
		if int(bag.get("place", -1)) / 4 != SecurityLooks.Home.FLOOR:
			continue
		if props.transfer_progress(p.id, other) < 1.0:
			continue
		var xf := front.affine_inverse() * (bag["node"] as Node3D).global_transform
		frames += 1
		moving += int(stepped)
		off = maxf(off, Vector2(xf.origin.x - want.x, xf.origin.z - want.z).length())
		var clip: String = body.get_meta(&"clip", "")
		clips[clip] = clips.get(clip, 0) + 1
		var poses: Array = {"idle": _idle, "sit_down": _sit_down, "sit_idle": _sit}.get(clip, [])
		assert_bool(poses.is_empty()).override_failure_message("clip %s" % clip).is_false()
		if poses.is_empty():
			continue
		var phases: Array = poses[b]
		var at := player.current_animation_position / maxf(player.current_animation_length, 0.001)
		var pose: PackedVector3Array = phases[clampi(roundi(at * PHASES), 0, phases.size() - 1)]
		var flat := Transform3D(xf.basis, Vector3(xf.origin.x, 0.0, xf.origin.z))
		hits += _inside_scaled([pose], front.affine_inverse() * body.global_transform, flat, kind)
	print(
		(
			(
				"body %d bag %d %s settled on the floor %d frames (%d with the drawn body moving),"
				+ " spot %s, most off it %.5f m (< %.3f); sim moved %.3f m; clips %s;"
				+ " vertices inside %d (0)"
			)
			% [
				b,
				other,
				SecurityLooks.Kind.keys()[kind],
				frames,
				moving,
				want,
				off,
				STILL_M,
				moved,
				clips,
				hits
			]
		)
	)
	assert_float(moved).is_greater(0.3)
	assert_int(moving).is_greater(4)
	assert_float(off).is_less(STILL_M)
	assert_int(hits).is_equal(0)


## A two-bag walker (one roller and one other bag) at the first gate chair's
## front, drawn a few ticks bound for the chair, then sitting down there.
func _sitting_walker() -> Passenger:
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	var p: Passenger = null
	for attempt in 400:
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.carry_on = 2
		var kinds := [SecurityLooks.bag_kind(p, 0), SecurityLooks.bag_kind(p, 1)]
		if SecurityLooks.Kind.ROLLER in kinds and kinds[0] != kinds[1]:
			break
		p.carry_on = 0
	ToiletTestLayout.calm(p)
	p.liquids = false
	p.alarm = false
	p.cleared = true
	var seat: Dictionary = _world.sim.layout.seats[0]
	p.stage = Passenger.Stage.TO_GATE
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.at = seat["front"]
	p.clear_path()
	p.boarding_tick = _world.sim.tick + 100000
	for n in 4:
		await _tick()
	p.seat_object = seat["object_id"]
	p.seat_piece = Relocation.placement(_world.grid, p.seat_object)
	p.stage = Passenger.Stage.SITTING_DOWN
	p.stage_tick = _world.sim.tick
	p.clear_path()
	return p


## How many vertices of body `b` going down onto chair `chair` lie in `bag`
## (_inside()): each sit_down pose drawn eased (smoothstep) that share of the
## way from the front to the seat, as SitHold.offset() draws it.
func _going_down(b: int, chair: int, bag: Transform3D, kind: SecurityLooks.Kind) -> int:
	var count := 0
	var seat := _seated(b, chair)
	for n in _sit_down[b].size():
		var share := smoothstep(0.0, 1.0, n / float(PHASES))
		var at := Transform3D(Basis.IDENTITY, seat.origin * share)
		count += _inside([_sit_down[b][n]], at, bag, kind)
	return count


## Where body `b` is drawn seated on chair `chair` (footprint index) of a row
## at facing 0, in the chair front's frame (TestGateChairRollerSpot._seated()).
static func _seated(b: int, chair: int) -> Transform3D:
	var shift: Vector2 = PassengerLooks.SEAT_SHIFT_M[b]
	var ahead := -1.0 + PassengerSim.SIT_FORWARD_M + shift.x
	return Transform3D(Basis.IDENTITY, Vector3(GateChairs.CHAIR_OFFSET_M[chair], shift.y, ahead))


## How many vertices of `poses` (a body drawn at `body`) lie in the box of a bag
## of `kind` at `spot` (unscaled, its origin on the floor), drawn at
## SecurityLooks.TWO_BAG_SCALE, grown by MARGIN_M.
func _inside(poses: Array, body: Transform3D, spot: Transform3D, kind: SecurityLooks.Kind) -> int:
	var scaled := Transform3D(
		spot.basis.scaled(Vector3.ONE * SecurityLooks.TWO_BAG_SCALE), spot.origin
	)
	return _inside_scaled(poses, body, scaled, kind)


## The same for a bag drawn at `xf` (its scale in its basis).
func _inside_scaled(
	poses: Array, body: Transform3D, xf: Transform3D, kind: SecurityLooks.Kind
) -> int:
	var scale_by := xf.basis.get_scale().x
	var box := CarryOnProps.bag_box(kind).grow(MARGIN_M / scale_by)
	var to_bag := xf.affine_inverse() * body
	var count := 0
	for points: PackedVector3Array in poses:
		for v in points:
			count += int(box.has_point(to_bag * v))
	return count


## The least distance (m) from the box of a bag of `kind` at `spot` (drawn at
## TWO_BAG_SCALE, not grown) to a vertex of `poses` drawn at `body`; 0 inside.
func _gap(poses: Array, body: Transform3D, spot: Transform3D, kind: SecurityLooks.Kind) -> float:
	var scale_by := SecurityLooks.TWO_BAG_SCALE
	var box := CarryOnProps.bag_box(kind)
	var to_bag := (
		Transform3D(spot.basis.scaled(Vector3.ONE * scale_by), spot.origin).affine_inverse() * body
	)
	var least := INF
	for points: PackedVector3Array in poses:
		for v in points:
			var at := to_bag * v
			var out := (box.position - at).max(at - box.end).max(Vector3.ZERO)
			least = minf(least, out.length() * scale_by)
	return least
