class_name TestCarryInStall
extends GdUnitTestSuite
## Carry-on bags drawn on a toilet visit (board item carry-on-bags-in-a-toilet-
## stall-clip; StallCarry): a bag set down on the stall's floor and picked up
## again stays under the stall's 2.22 m partitions (decision toilet-stall-kit-
## piece-1x2-footprint-side-partitions-out-to), no bag goes into a side
## partition or, while the passenger sits down, sits or gets up, into the door,
## and a pulled roller is not drawn over the bowl: it is carried in the hand in
## the stall and trails again only once its walker is out. Checked on the drawn
## bag nodes (CarryOnProps through PassengerViews), frame by frame, from the
## walk to the stall until the walker is AFTER_M past its approach cell.
##
## Each tick: the sim steps (the views sync), the frame is processed (the
## views draw, the skeleton reports and places the bags in hand), the pre-draw
## fallback runs, then each bag's bounds (its eight corners) are measured in
## the stall's frame: x across, y up, z out of the door from the footprint
## centre. A box built from the corners is larger than the bag when it is
## turned, so the checks err toward a clip.

## Every bag in or over the stall stays under this (the partitions are 2.22 m).
const UNDER_M := 2.2
## The stall's column for the height check: its partitions' outer faces and
## its back and door, with a margin.
const COLUMN_HALF_M := 0.6
const COLUMN_BACK_M := -1.0
const COLUMN_DOOR_M := 1.0
## The side partitions' inner and outer faces (and a neighbour's, 1 cm on),
## the back wall and the door's outer face, and the partitions' top.
const PARTITION_M := 0.47
const PARTITION_OUT_M := 0.53
const BACK_M := -0.92
const DOOR_OUT_M := 0.9
const TOP_M := 2.22
## The closed door's leaves: their inner face, their half width and their
## height.
const DOOR_IN_M := 0.881
const DOOR_HALF_M := 0.44
const DOOR_LOW_M := 0.15
const DOOR_HIGH_M := 1.9
## The toilet bowl and cistern: the rear of the stall out to just in front of
## Mount_Use (-0.05), up to the cistern's top.
const BOWL_OUT_M := 0.15
const BOWL_TOP_M := 1.0
## How far the walker walks on after the visit before the check ends.
const AFTER_M := 2.5
## Moves a pulled roller lands on the floor by this much of the move
## (CarryOnProps.ROLLER_LAND) and then waits there.
const LANDED := 0.85
## Sim ticks per frame: not a whole tick, so the frames fall part-way between
## ticks (a 6-tick move is seen at k = 0.125, 0.25, ..., 0.875) as in a game
## drawn faster than it ticks. FAST_TICKS is a frame at 3x speed.
const FRAME_TICKS := 0.75
const FAST_TICKS := 3.0

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	_free_world()
	PassengerTestWorld.tracker = null


func _free_world() -> void:
	if _views != null:
		_views.free()
		_world.free_all()
	_views = null


## A new world (each visit starts early in the flight's day, with every stall
## free) with the views drawing.
func _new_world() -> void:
	_free_world()
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	# The test runs the pre-draw fallback itself at the end of each frame.
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)


## A passenger with `count` bags, the first of `kind`, on its way to
## security, sent to a stall in a new world. The kind is a hash of the id, so
## passengers whose first bag is another kind are sent without bags until one
## fits.
func _visitor(kind: SecurityLooks.Kind, count := 1) -> Passenger:
	_new_world()
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, 0) != kind:
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = count
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.at = Vector2i(20, 14)
	p.clear_path()
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	return p


## One frame `ticks` sim ticks on, as the game draws them: part of a tick
## (the clock's alpha between ticks), or several (a frame at 2x or 3x).
func _tick(ticks: float) -> void:
	_world.clock.advance(SimClock.STEP * ticks)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()


## Runs `p`'s visit from its walk to the stall until it has walked AFTER_M
## past the stall's approach cell; returns one entry per frame and bag:
## {"tick", "stage", "bag": its index, "kind", "lo" and "hi": its bounds in the
## stall's frame, "body": the body's offset out of the door, "carry", "home",
## "k": its move's progress (1 when settled), "axle_off": a pulled roller's
## axle distance from the body on the ground, or -1}. Each frame runs
## `ticks` sim ticks (FRAME_TICKS: moves are seen part-way between ticks).
func _visit_frames(p: Passenger, ticks := FRAME_TICKS) -> Array:
	var props := _views.carry_on_props()
	var stall := _world.sim.toilets.visit_of(p.id).stall
	var out := SecurityLooks.world_dir(stall["front"])
	var across := out.cross(Vector3.UP)
	var centre: Vector3 = stall["use"] - out * ToiletLayout.USE_M
	var approach := _world.sim.grid.cell_to_world(stall["approach"])
	var frames := []
	var visited := false
	while _world.clock.tick < 20000:
		var sat := _world.clock.tick - p.stage_tick
		if p.stage == Passenger.Stage.TOILET_USE and sat < ToiletSim.USE_TICKS - 4:
			# Sitting with the bags on the floor, nothing moves: no frames.
			_world.step()
			continue
		await _tick(ticks)
		var body := _views.node_for(p.id)
		visited = visited or p.stage == Passenger.Stage.TOILET_EXIT
		if visited and not Passenger.in_toilet(p.stage):
			var away := body.global_position - approach
			if Vector2(away.x, away.z).length() > AFTER_M:
				break
		var held := props.props_of(p.id)
		for b in (held["bags"] as Array).size():
			var node: Node3D = held["bags"][b]
			var lo := Vector3.INF
			var hi := -Vector3.INF
			var box := CarryOnProps.bag_box(held["kinds"][b])
			for i in 8:
				var at := node.global_transform * box.get_endpoint(i) - centre
				var local := Vector3(at.dot(across), at.y, at.dot(out))
				lo = lo.min(local)
				hi = hi.max(local)
			var axle_off := -1.0
			if held["carries"][b] == SecurityLooks.Carry.PULL:
				var axle := node.global_transform * CarryOnProps.ROLLER_AXLE - body.global_position
				axle_off = Vector2(axle.x, axle.z).length()
			(
				frames
				. append(
					{
						"tick": _world.clock.tick,
						"stage": p.stage,
						"bag": b,
						"kind": held["kinds"][b],
						"lo": lo,
						"hi": hi,
						"body": (body.global_position - centre).dot(out),
						"carry": held["carries"][b],
						"home": SecurityLooks.bag_homes(_world.sim, p)[b],
						"k": props.transfer_progress(p.id, b),
						"axle_off": axle_off,
					}
				)
			)
	assert_bool(visited).is_true()
	return frames


## Whether a bag's bounds reach into the stall's column.
static func _over_stall(frame: Dictionary) -> bool:
	var lo: Vector3 = frame["lo"]
	var hi: Vector3 = frame["hi"]
	return (
		lo.x < COLUMN_HALF_M
		and hi.x > -COLUMN_HALF_M
		and lo.z < COLUMN_DOOR_M
		and hi.z > COLUMN_BACK_M
	)


## Whether a bag's bounds overlap a side partition (from its inner face to
## its outer one, and a neighbour's 1 cm beyond) below its top, along the
## stall's depth.
static func _in_partition(frame: Dictionary) -> bool:
	var lo: Vector3 = frame["lo"]
	var hi: Vector3 = frame["hi"]
	var right := hi.x > PARTITION_M and lo.x < PARTITION_OUT_M
	var left := lo.x < -PARTITION_M and hi.x > -PARTITION_OUT_M
	return (right or left) and lo.z < DOOR_OUT_M and hi.z > BACK_M and lo.y < TOP_M


## Whether a bag's bounds reach into the closed door's leaves.
static func _in_door(frame: Dictionary) -> bool:
	var lo: Vector3 = frame["lo"]
	var hi: Vector3 = frame["hi"]
	return (
		hi.z > DOOR_IN_M
		and lo.z < DOOR_OUT_M
		and hi.x > -DOOR_HALF_M
		and lo.x < DOOR_HALF_M
		and hi.y > DOOR_LOW_M
		and lo.y < DOOR_HIGH_M
	)


## Whether a bag's bounds reach over the bowl, in the stall.
static func _over_bowl(frame: Dictionary) -> bool:
	var lo: Vector3 = frame["lo"]
	var hi: Vector3 = frame["hi"]
	return (
		lo.z < BOWL_OUT_M
		and hi.z > BACK_M
		and lo.x < PARTITION_M
		and hi.x > -PARTITION_M
		and lo.y < BOWL_TOP_M
	)


## A one-line account of a frame for the printout.
static func _line(frame: Dictionary) -> String:
	var lo: Vector3 = frame["lo"]
	var hi: Vector3 = frame["hi"]
	return (
		(
			"t%d %s bag %d kind %d body_out=%.2f carry=%d home=%d k=%.2f"
			+ " across %.2f..%.2f up %.2f..%.2f out %.2f..%.2f axle_off=%.2f"
		)
		% [
			frame["tick"],
			Passenger.Stage.keys()[frame["stage"]],
			frame["bag"],
			frame["kind"],
			frame["body"],
			frame["carry"],
			frame["home"],
			frame["k"],
			lo.x,
			hi.x,
			lo.y,
			hi.y,
			lo.z,
			hi.z,
			frame["axle_off"],
		]
	)


## Counts the frames for which `check` holds, printing the first few when
## there is a `label`.
static func _count(frames: Array, check: Callable, label := "") -> int:
	var count := 0
	for frame: Dictionary in frames:
		if check.call(frame):
			count += 1
			if count <= 4 and label != "":
				print("%s: %s" % [label, _line(frame)])
	return count


## A backpack or roller set down on the stall's floor while its walker sits
## down, and picked up as it steps out, never rises over the partitions while
## any of it is over the stall, with one bag and with two, drawn part-way
## between ticks and (one bag) at 3x speed, several ticks a frame. Controls:
## each bag was seen moving down to the floor and up again over the stall.
func test_a_bag_set_down_and_picked_up_in_a_stall_stays_under_its_partitions() -> void:
	var runs := []
	for kind in [SecurityLooks.Kind.BACKPACK, SecurityLooks.Kind.ROLLER]:
		runs.append([kind, 1, FRAME_TICKS])
		runs.append([kind, 2, FRAME_TICKS])
		runs.append([kind, 1, FAST_TICKS])
	for run: Array in runs:
		var count: int = run[1]
		var frames := await _visit_frames(_visitor(run[0], count), run[2])
		var top := -INF
		var set_down := [0, 0]
		var picked_up := [0, 0]
		for frame: Dictionary in frames:
			if not _over_stall(frame):
				continue
			top = maxf(top, (frame["hi"] as Vector3).y)
			if frame["k"] < 1.0:
				if frame["home"] == SecurityLooks.Home.FLOOR:
					set_down[frame["bag"]] += 1
				elif frame["stage"] == Passenger.Stage.TOILET_EXIT:
					picked_up[frame["bag"]] += 1
		var high := func(frame: Dictionary) -> bool:
			return _over_stall(frame) and (frame["hi"] as Vector3).y >= UNDER_M
		var over := _count(frames, high, "over the partitions")
		print(
			(
				(
					"%d bags, first kind %d, %.2f ticks a frame: top over the stall %.3f m,"
					+ " frames over %d; moving over the stall per bag: set down %s, picked up %s"
				)
				% [count, run[0], run[2], top, over, set_down, picked_up]
			)
		)
		for b in count:
			assert_int(set_down[b]).is_greater(0)
			assert_int(picked_up[b]).is_greater(0)
		assert_int(over).is_equal(0)
		assert_float(top).is_less(UNDER_M)


## A roller is carried by its handle in the stall and trails again only once
## its walker is out: from the stand-up on no part of it is over the bowl,
## while it is pulled none of it is over the stall, and its axle, once landed
## behind the walker, is never drawn further than a trail and a margin from
## the body (a follower that started from where the roller was last pulled,
## before the stall, would stretch the rods to it). Controls: it is pulled
## again by the end, its axle a trail's length behind the body, and frames
## of the return to the pull after it landed (LANDED <= k < 1) were measured.
func test_a_pulled_roller_trails_only_once_its_walker_is_out_of_the_stall() -> void:
	var frames := await _visit_frames(_visitor(SecurityLooks.Kind.ROLLER))
	var getting_up := false
	var bowl := 0
	var pulled_over := 0
	var landed := 0
	var landing := 0
	var furthest := 0.0
	for frame: Dictionary in frames:
		getting_up = getting_up or frame["stage"] == Passenger.Stage.TOILET_STANDING_UP
		var pulled: bool = (
			frame["carry"] == SecurityLooks.Carry.PULL and frame["home"] == SecurityLooks.Home.HAND
		)
		if getting_up and _over_bowl(frame):
			bowl += 1
			if bowl <= 4:
				print("over the bowl: %s" % _line(frame))
		if pulled and frame["k"] >= LANDED and _over_stall(frame):
			pulled_over += 1
			if pulled_over <= 4:
				print("pulled over the stall: %s" % _line(frame))
		if pulled and frame["k"] >= LANDED and getting_up:
			landed += 1
			landing += 1 if frame["k"] < 1.0 else 0
			furthest = maxf(furthest, frame["axle_off"])
	var last: Dictionary = frames[-1]
	print(
		(
			(
				"roller: frames over the bowl %d, pulled over the stall %d, landed pulled frames"
				+ " after the visit %d (still landing %d), furthest axle %.3f m; last %s"
			)
			% [bowl, pulled_over, landed, landing, furthest, _line(last)]
		)
	)
	assert_int(bowl).is_equal(0)
	assert_int(pulled_over).is_equal(0)
	assert_int(landed).is_greater(0)
	assert_int(landing).is_greater(0)
	assert_int(last["carry"]).is_equal(SecurityLooks.Carry.PULL)
	assert_float(last["axle_off"]).is_greater(CarryOnProps.TRAIL_BEHIND_MIN_M - 0.05)
	assert_float(furthest).is_less(CarryOnProps.TRAIL_M + 0.2)


## Every kind, one bag and two: no bag reaches into a side partition on the
## whole visit (the walk in, the stall, the walk out), and none reaches into
## the closed door while its passenger sits down, sits or stands up (walkers
## step through the closed door, so stepping in and out is left out).
## Control: each bag was in the stall's column on some frames.
func test_no_bag_goes_into_a_side_partition_or_the_door() -> void:
	for count in [1, 2]:
		for kind in SecurityLooks.Kind.values():
			var frames := await _visit_frames(_visitor(kind, count))
			var seated := func(frame: Dictionary) -> bool:
				return (
					frame["stage"]
					in [
						Passenger.Stage.TOILET_SITTING_DOWN,
						Passenger.Stage.TOILET_USE,
						Passenger.Stage.TOILET_STANDING_UP
					]
				)
			var sides := _count(frames, _in_partition, "into a partition")
			var door := _count(
				frames,
				func(frame: Dictionary) -> bool: return seated.call(frame) and _in_door(frame),
				"into the door"
			)
			var inside := []
			for b in count:
				var bag_over := func(frame: Dictionary) -> bool:
					return frame["bag"] == b and _over_stall(frame)
				inside.append(_count(frames, bag_over))
			print(
				(
					(
						"%d bags, first kind %d: frames into a partition %d, into the door %d,"
						+ " over the stall per bag %s"
					)
					% [count, kind, sides, door, inside]
				)
			)
			for b in count:
				assert_int(inside[b]).is_greater(0)
			assert_int(sides).is_equal(0)
			assert_int(door).is_equal(0)
