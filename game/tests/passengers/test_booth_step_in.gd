class_name TestBoothStepIn
extends GdUnitTestSuite
## A booth guest steps in from the bench's open end (board 64ee4dc0). The bench
## has a high end panel across its whole depth behind the seat root, so the
## shuffle from the approach cell first steps forward inside that cell, beside
## the bench, to a line just ahead of the root and then slides in along it: a
## straight line from the approach cell (0.45 m behind the root) would carry
## the body through the end panel (windowed probe game/spike/food_seats_probe.gd:
## 4 to 176 body points inside it at every booth seat). It leaves the approach
## cell at walking pace, with no lunge, and stands up along the same path. A
## guest with a roller stands at the approach cell while it sets the roller
## down (CafeSim.STEP_IN_HOLD_TICKS), then steps in and sits exactly as a guest
## with no roller does (board 5dc41129): eased in over the ticks the sit-down
## had left, its hips went back while it was still beside the end panel. The
## cafe table's chairs, also stepped into from a cell to the side, keep their
## straight shuffle.

## The body reaches this far to each side of its spot: while the spot is
## nearer the seat root than this plus PANEL_FACE_M, part of the body is past
## the end panel's outer face.
const BODY_HALF_M := 0.25
## The bench's end panel's outer face (towards the approach cell), across from
## the seat root (tools/blender/interior/build_services_kit.py: the panel at
## x 0.86-0.92 m, the roots at x 0.5 m, so its inner face is at 0.36 m).
const PANEL_FACE_M := 0.42
## From this share of the sit_down clip on, the hips are going back (the clip's
## Hips bone is 0.036 m back of its 0.53 m at 0.17, 0.08 m at 0.25).
const HIPS_BACK_SHARE := 0.1
## How far a roller guest's drawn spot may be from a guest's with no roller at
## the same share of the sit_down clip.
const SAME_SPOT_M := 0.02
## Half the width of a roller lying along the guest's line, across it (its outer
## edge 0.484 m from the approach cell's centre at 0.32 m, review of e1f5789).
const ROLLER_HALF_M := 0.164
## The guest's feet reach this far to each side of its centre line, standing.
const FEET_HALF_M := 0.15
## The approach cell's forward edge, ahead of the root (the root is 0.45 m from
## the seat cell's centre towards the table, the approach cell beside it).
const CELL_EDGE_M := 0.05
const WALK_M := PassengerSim.WALK_MM / 1000.0

var _worlds: Array[PassengerTestWorld] = []
var _views: Array[PassengerViews] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for views in _views:
		views.free()
	_views.clear()
	for world in _worlds:
		world.free_all()
	_worlds.clear()


## A guest of a restaurant with `table` (pulling a roller with `roller`)
## stepped to the first tick of its sit-down; with `drawn`, drawn by real
## PassengerViews from its visit's start (the views third in the result).
func _sitting(table: StringName, roller := false, drawn := false) -> Array:
	var grid := BuildGrid.new()
	CafeTestLayout.build(grid, false, &"restaurant", true, &"cafe_counter", table)
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_worlds.append(world)
	var p: Passenger = null
	for attempt in 200:
		p = world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		p.cafe_cooldown = 1000000
		p.hunger = 30
		p.carry_on = 1 if roller else 0
		if not roller or SecurityLooks.bag_kind(p, 0) == SecurityLooks.Kind.ROLLER:
			break
		p.carry_on = 0
		ToiletTestLayout.calm(p)
	p.liquids = false
	p.alarm = false
	while p.stage != Passenger.Stage.TO_GATE and world.clock.tick < 1500:
		world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.TO_GATE)
	var views: PassengerViews = null
	if drawn:
		views = PassengerTestWorld.views()
		views.clock = world.clock
		views.sim = world.sim
		add_child(views)
		_views.append(views)
	assert_bool(world.sim.cafes.try_visit(p)).override_failure_message("visit refused").is_true()
	while p.stage != Passenger.Stage.CAFE_SITTING_DOWN and world.clock.tick < 3000:
		world.step()
		if views != null:
			# The props are drawn a frame at a time (PassengerViews._process()).
			views.draw()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SITTING_DOWN)
	return [world, p, views]


## `at` in `seat`'s frame: [ahead of the root, across from the root].
func _seat_xy(world: PassengerTestWorld, seat: Dictionary, at: Vector3) -> Vector2:
	var facing: Vector2i = seat["facing"]
	var ahead := Vector3(facing.x, 0.0, facing.y)
	var d := at - BuildObjectDef.seat_root_world(world.grid, seat)
	var forward := d.dot(ahead)
	return Vector2(forward, (d - ahead * forward).length())


## The sim's spot each tick while `p` stays in `stage` (at most `ticks` + 1
## samples), in the seat's frame.
func _track(
	world: PassengerTestWorld, p: Passenger, stage: Passenger.Stage, ticks: int
) -> Array[Vector2]:
	var seat: Dictionary = world.sim.cafes.visit_of(p.id).seat
	var out: Array[Vector2] = []
	for k in ticks + 1:
		if p.stage != stage:
			break
		out.append(_seat_xy(world, seat, world.sim.cafes.seat_position(p)))
		world.step()
	return out


## Every spot of `path` where the body reaches past the bench end is ahead of
## the root; at least three such spots (or nothing was checked).
func _assert_clear_of_the_end_panel(path: Array[Vector2]) -> void:
	var near := 0
	for at in path:
		if at.y < PANEL_FACE_M + BODY_HALF_M:
			near += 1
			var why := "the body passes the bench end behind the root at %s" % at
			assert_float(at.x).override_failure_message(why).is_greater_equal(0.0)
	assert_int(near).is_greater(2)


## No tick's step is longer than `most` walking steps; the first and last no
## longer than 1.2 walking steps (the guest arrives walking and stops seated).
func _assert_no_lunge(path: Array[Vector2], most: float) -> Array[float]:
	var steps: Array[float] = []
	for i in range(1, path.size()):
		steps.append(path[i].distance_to(path[i - 1]))
	var moving: Array[float] = steps.filter(func(s: float) -> bool: return s > 1e-4)
	assert_int(moving.size()).is_greater(5)
	assert_float(moving[0]).is_less_equal(1.2 * WALK_M)
	assert_float(moving[-1]).is_less_equal(1.2 * WALK_M)
	for s in moving:
		assert_float(s).is_less_equal(most * WALK_M)
	return moving


func test_a_booth_guest_steps_in_ahead_of_the_end_panel_at_walking_pace() -> void:
	var made := _sitting(&"restaurant_booth")
	var path := _track(made[0], made[1], Passenger.Stage.CAFE_SITTING_DOWN, CafeSim.SHUFFLE_TICKS)
	var steps := _assert_no_lunge(path, 1.6)
	print("booth sit-down [ahead, across] per tick: %s steps %s" % [path, steps])
	# Control: the shuffle starts at the approach cell, behind the root and a
	# cell to its side, so a check on the bench end has something to see.
	assert_float(path[0].x).is_less(-0.4)
	assert_float(path[0].y).is_greater(0.9)
	_assert_clear_of_the_end_panel(path)
	assert_float(path[-1].length()).is_less(0.001)


## The spot stays inside the approach cell until it is inside the booth's
## footprint: no part of the path is on the next cell's edge, which the seat's
## reachability does not check.
func test_the_booth_step_in_path_keeps_inside_the_approach_cell() -> void:
	var made := _sitting(&"restaurant_booth")
	var world: PassengerTestWorld = made[0]
	var p: Passenger = made[1]
	var seat: Dictionary = world.sim.cafes.visit_of(p.id).seat
	var approach := world.grid.cell_to_world(seat["approach"])
	var root := BuildObjectDef.seat_root_world(world.grid, seat)
	var outside := 0
	for i in 101:
		var f := i / 100.0
		var at := _seat_xy(world, seat, approach.lerp(root, f) + world.sim.cafes.shuffle_bend(p, f))
		if at.y > 0.5:
			outside += 1
			var why := "the path leaves the approach cell at %s" % at
			assert_float(at.x).override_failure_message(why).is_less(CELL_EDGE_M)
	assert_int(outside).is_greater(10)


func test_a_booth_guest_stands_up_along_the_same_path() -> void:
	var made := _sitting(&"restaurant_booth")
	var world: PassengerTestWorld = made[0]
	var p: Passenger = made[1]
	while p.stage != Passenger.Stage.CAFE_SEATED and world.clock.tick < 4000:
		world.step()
	world.sim.cafes.visit_of(p.id).dwell_end = world.clock.tick + 1
	while p.stage != Passenger.Stage.CAFE_STANDING_UP and world.clock.tick < 4000:
		world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_STANDING_UP)
	var seat: Dictionary = world.sim.cafes.visit_of(p.id).seat
	var path := _track(world, p, Passenger.Stage.CAFE_STANDING_UP, CafeSim.up_ticks(p))
	# The stand-up's last tick ends at the approach cell, where the walk starts.
	path.append(_seat_xy(world, seat, world.grid.cell_to_world(seat["approach"])))
	var steps := _assert_no_lunge(path, 1.6)
	print("booth stand-up [ahead, across] per tick: %s steps %s" % [path, steps])
	assert_float(path[0].length()).is_less(0.001)
	# The sim's last spot standing up: a tick's step from the approach cell.
	assert_float(path[-2].distance_to(path[-1])).is_greater(0.05)
	assert_float(path[-1].x).is_less(-0.4)
	assert_float(path[-1].y).is_greater(0.9)
	_assert_clear_of_the_end_panel(path)


## Drawn as PassengerViews draws it: the sim's spot with the cafe seat step
## and SitHold.offset(), which is zero at a booth: the sim holds the guest at
## the approach cell for its step-in hold, then takes it in along the path.
func test_a_booth_guest_with_a_roller_takes_the_same_path_in() -> void:
	var made := _sitting(&"restaurant_booth", true)
	var world: PassengerTestWorld = made[0]
	var p: Passenger = made[1]
	var seat: Dictionary = world.sim.cafes.visit_of(p.id).seat
	var props: CarryOnProps = auto_free(CarryOnProps.new())
	var held := SitHold.held_ticks(props, world.sim, p)
	var path: Array[Vector2] = []
	# The whole sit-down, its step-in hold first (CafeSim.sit_ticks()).
	for k in CafeSim.sit_ticks(p, world.sim.cafes.visit_of(p.id).piece) + 1:
		var now := world.sim.world_position(p) + CafeChairs.offset(world.sim, p)
		path.append(_seat_xy(world, seat, now + SitHold.offset(props, world.sim, p, now)))
		world.step()
	print("booth roller sit-down, held %d ticks, drawn [ahead, across]: %s" % [held, path])
	# Control: a roller guest is held at the approach cell (the sim's step-in
	# hold), longer than the shuffle, before it steps in.
	assert_int(held).is_greater(CafeSim.SHUFFLE_TICKS)
	assert_float(path[held - 1].distance_to(path[0])).is_less(0.001)
	_assert_clear_of_the_end_panel(path)
	assert_float(path[-1].length()).is_less(0.03)


## On each tick of the sit-down of `p` (made by _sitting() with `drawn`), the
## share of the sit_down clip `views` have played before it and the drawn spot
## (seat frame): [share, spot]. The clip's place on a tick is (ticks into the
## stage - held) / its ticks, as PassengerViews seeks it.
func _drawn_sit_down(made: Array) -> Array:
	var world: PassengerTestWorld = made[0]
	var p: Passenger = made[1]
	var views: PassengerViews = made[2]
	var seat: Dictionary = world.sim.cafes.visit_of(p.id).seat
	var out := []
	var share := 0.0
	while p.stage == Passenger.Stage.CAFE_SITTING_DOWN:
		var node := views.node_for(p.id)
		var player := node.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var at := world.sim.world_position(p)
		var ease := SitHold.offset(
			views.carry_on_props(), world.sim, p, at + CafeChairs.offset(world.sim, p)
		)
		# The sim takes the booth's path itself: no view ease on top of it.
		assert_vector(ease).is_equal(Vector3.ZERO)
		# Without the body's own seat step (CafeChairs), which differs by body.
		out.append([share, _seat_xy(world, seat, at + ease)])
		if node.get_meta(&"clip", "") == "sit_down":
			share += SimClock.STEP * player.speed_scale / PassengerViews.SIT_CLIP_SECONDS
		world.step()
		views.draw()
	return out


## The spot of `drawn` (_drawn_sit_down()) at clip share `share`, between the
## samples either side of it.
func _spot_at(drawn: Array, share: float) -> Vector2:
	for i in range(1, drawn.size()):
		var a: float = drawn[i - 1][0]
		var b: float = drawn[i][0]
		if share <= b and b > a:
			return (drawn[i - 1][1] as Vector2).lerp(drawn[i][1], (share - a) / (b - a))
	return drawn[-1][1]


## A roller guest at a booth stands at the approach cell while its roller goes
## down, then is on a guest with no roller's spot at every share of the
## sit_down clip from where the hips start going back: past the end panel
## before the hips reach it (board 5dc41129: 116 body points in the panel when
## it eased in over the 10 ticks left). Control: the guest with no roller sat
## at the same seat, the roller guest's clip played whole once, from the end
## of a hold as long as the roller's park, and moved off the approach cell.
func test_a_booth_guest_with_a_roller_sits_down_as_one_with_no_roller() -> void:
	var plain := _sitting(&"restaurant_booth", false, true)
	var plain_key: String = (
		(plain[0] as PassengerTestWorld).sim.cafes.visit_of(plain[1].id).seat["key"]
	)
	var bare := _drawn_sit_down(plain)
	var made := _sitting(&"restaurant_booth", true, true)
	var world: PassengerTestWorld = made[0]
	var p: Passenger = made[1]
	var key: String = world.sim.cafes.visit_of(p.id).seat["key"]
	var hold := world.sim.cafes.hold_now(p)
	var start := p.stage_tick
	var drawn := _drawn_sit_down(made)
	var bag := (made[2] as PassengerViews).carry_on_props().bag_state(p.id, 0)
	var park_end := float(bag.get("since", INF)) + CarryLead.ticks_of(bag) - start
	print("booth sit-down, no roller [share, spot]: %s" % [bare])
	print(
		"booth sit-down, roller held %d, park ends %.1f [share, spot]: %s" % [hold, park_end, drawn]
	)
	assert_str(key).is_equal(plain_key)
	# The roller's park ran, and its hand let go before the clip started.
	assert_bool(bag.get("park", false)).is_true()
	assert_float(park_end + SitHold.LET_GO_TICKS).is_less_equal(hold)
	assert_int(hold).is_greater_equal(ceili(RollerPark.TICKS_DOWN + SitHold.LET_GO_TICKS))
	assert_int(bare.size()).is_equal(PassengerSim.SIT_DOWN_TICKS)
	assert_int(drawn.size()).is_equal(hold + PassengerSim.SIT_DOWN_TICKS)
	assert_float(bare[-1][0]).is_equal_approx(1.0, 0.05)
	assert_float(drawn[-1][0]).is_equal_approx(1.0, 0.05)
	var standing := 0
	var compared := 0
	for sample: Array in drawn:
		var share: float = sample[0]
		var at: Vector2 = sample[1]
		if share <= 0.0:
			standing += 1
			assert_float(at.distance_to(drawn[0][1])).is_less(0.001)
		elif share >= HIPS_BACK_SHARE:
			compared += 1
			var want := _spot_at(bare, share)
			var why := "at clip share %.2f the roller guest is at %s, not %s" % [share, at, want]
			assert_float(at.distance_to(want)).override_failure_message(why).is_less(SAME_SPOT_M)
	assert_int(standing).is_greater_equal(hold - 1)
	assert_int(compared).is_greater(15)
	assert_float((drawn[-1][1] as Vector2).distance_to(drawn[0][1])).is_greater(1.0)


## A roller guest's sit-down at a booth lasts its step-in hold longer, and the
## visit's forecast and the save check count it: a save in the hold past
## SIT_DOWN_TICKS loads and sits down on the same tick as it would have.
func test_a_booth_roller_sit_down_is_longer_and_the_forecast_and_save_count_it() -> void:
	var made := _sitting(&"restaurant_booth", true)
	var world: PassengerTestWorld = made[0]
	var p: Passenger = made[1]
	var piece: Dictionary = world.sim.cafes.visit_of(p.id).piece
	assert_int(CafeSim.STEP_IN_HOLD_TICKS).is_equal(
		ceili(RollerPark.TICKS_DOWN + SitHold.LET_GO_TICKS)
	)
	assert_int(CafeSim.sit_ticks(p, piece)).is_equal(
		PassengerSim.SIT_DOWN_TICKS + CafeSim.STEP_IN_HOLD_TICKS
	)
	var legs := {
		"pre_ticks": 0, "to_queue_mm": 0, "order_ticks": 0, "to_seat_mm": 0, "dwell_ticks": 0
	}
	var plain_end := CafeForecast.visit_end(world.sim, legs)
	legs["sit_ticks"] = CafeSim.sit_ticks(p, piece)
	assert_int(CafeForecast.visit_end(world.sim, legs) - plain_end).is_equal(
		CafeSim.STEP_IN_HOLD_TICKS
	)
	var start := p.stage_tick
	var due := start + CafeSim.sit_ticks(p, piece)
	world.run_to(start + PassengerSim.SIT_DOWN_TICKS + 2)
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SITTING_DOWN)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.sim.to_snapshot()))
	assert_bool(world.sim.from_snapshot(saved)).override_failure_message("load refused").is_true()
	var loaded := world.passenger(p.id)
	while loaded.stage == Passenger.Stage.CAFE_SITTING_DOWN and world.clock.tick < due + 5:
		world.step()
	print("booth roller sit-down from %d, seated at %d, due %d" % [start, loaded.stage_tick, due])
	assert_int(loaded.stage).is_equal(Passenger.Stage.CAFE_SEATED)
	assert_int(loaded.stage_tick).is_equal(due)


## A guest with no roller at a booth, and one with a roller at a cafe table,
## sit down over SIT_DOWN_TICKS as before.
func test_only_a_roller_guest_at_a_booth_holds_its_step_in() -> void:
	var made := _sitting(&"restaurant_booth")
	var p: Passenger = made[1]
	var booth: Dictionary = (made[0] as PassengerTestWorld).sim.cafes.visit_of(p.id).piece
	assert_int(CafeSim.sit_ticks(p, booth)).is_equal(PassengerSim.SIT_DOWN_TICKS)
	made = _sitting(&"cafe_table", true)
	p = made[1]
	var table: Dictionary = (made[0] as PassengerTestWorld).sim.cafes.visit_of(p.id).piece
	assert_bool(ParkRecovery.has_roller(p)).is_true()
	assert_int(CafeSim.sit_ticks(p, table)).is_equal(PassengerSim.SIT_DOWN_TICKS)
	assert_int((made[0] as PassengerTestWorld).sim.cafes.hold_now(p)).is_equal(0)


## A booth roller guest stands up and steps out as one with no roller does,
## then stands at the approach cell for ParkRecovery.UP_HOLD_TICKS picking its
## roller up (CafeSim.up_ticks() for the booth), and the visit plan counts it.
## Control: it started on the seat root and the step out moved it off it.
func test_a_booth_roller_guest_steps_out_then_picks_its_roller_up() -> void:
	var made := _sitting(&"restaurant_booth", true)
	var world: PassengerTestWorld = made[0]
	var p: Passenger = made[1]
	var visit := world.sim.cafes.visit_of(p.id)
	while p.stage != Passenger.Stage.CAFE_SEATED and world.clock.tick < 4000:
		world.step()
	visit.dwell_end = world.clock.tick + 1
	while p.stage != Passenger.Stage.CAFE_STANDING_UP and world.clock.tick < 4000:
		world.step()
	var up := CafeSim.up_ticks(p, visit.piece)
	assert_int(up).is_equal(PassengerSim.STAND_UP_TICKS + ParkRecovery.UP_HOLD_TICKS)
	assert_int(CafeSim.up_ticks(p)).is_equal(up + CafeSim.SHUFFLE_TICKS)
	var path := _track(world, p, Passenger.Stage.CAFE_STANDING_UP, up)
	print("booth roller stand-up [ahead, across] per tick: %s" % [path])
	assert_int(path.size()).is_equal(up)
	assert_float(path[0].length()).is_less(0.001)
	var held := path.slice(path.size() - ParkRecovery.UP_HOLD_TICKS)
	for at: Vector2 in held:
		assert_float(at.distance_to(Vector2(-0.45, 1.0))).is_less(0.001)
	_assert_clear_of_the_end_panel(path)
	var legs := {
		"pre_ticks": 0,
		"to_queue_mm": 0,
		"order_ticks": 0,
		"to_seat_mm": 0,
		"dwell_ticks": 0,
		"leave_cell": visit.seat["approach"],
		"resume_stage": Passenger.Stage.TO_GATE,
	}
	# The plan's "up_ticks" leg is read (a boarding wait can hide a 12-tick
	# difference in the arrival, so the leg is made long enough to show).
	legs["up_ticks"] = up
	var booth := CafeForecast.visit_arrival(world.sim, p, legs)
	legs["up_ticks"] = up + 2000
	assert_int(CafeForecast.visit_arrival(world.sim, p, legs)).is_greater(booth)


## A booth roller lies fixed in the world at the approach cell where it was set
## down (RollerPark.chair_front(), floor_spot()), on every tick of the
## sit-down and seated, never in the body's frame, which carried it along the
## step in: on its hand's side unless a wall stands on that edge of the cell,
## inside the cell (inside the wall's face where a wall stands), clear of the
## end panel and of the guest's feet (BoothRoller). The walls are read from
## the grid here; control: the layout has a booth seat with its open side
## walled.
func test_a_booth_roller_lies_fixed_at_the_approach_inside_its_cell() -> void:
	var made := _sitting(&"restaurant_booth", true)
	var world: PassengerTestWorld = made[0]
	var p: Passenger = made[1]
	var visit := world.sim.cafes.visit_of(p.id)
	var approach := world.grid.cell_to_world(visit.seat["approach"])
	var kind := SecurityLooks.Kind.ROLLER
	var walled_open := 0
	for seat: Dictionary in world.sim.cafes.layout.cafe(visit.room).get("seats", []):
		var away: Vector3 = world.grid.cell_to_world(seat["approach"])
		away -= BuildObjectDef.seat_root_world(world.grid, seat)
		if _has_wall(world, seat["approach"], Vector3(away.x, 0.0, away.z)):
			walled_open += 1
	print("booth seats with the open side walled: %d" % walled_open)
	assert_int(walled_open).is_greater(0)
	var checked := 0
	for k in CafeSim.sit_ticks(p, visit.piece) + 10:
		var front: Variant = RollerPark.chair_front(world.sim, p, kind)
		assert_bool(front != null).override_failure_message("no fixed frame").is_true()
		if front == null:
			return
		var frame := front as Transform3D
		assert_vector(frame.origin).is_equal_approx(approach, Vector3.ONE * 0.001)
		for hand in 2:
			var own := -1.0 if hand == 0 else 1.0
			var spot := (frame * RollerPark.floor_spot(world.sim, p, kind, hand, 0, 1)).origin
			var across := (spot - frame.origin).dot(frame.basis.x)
			var walled := _has_wall(world, visit.seat["approach"], frame.basis.x * own)
			var want := -own if walled else own
			var lie := _seat_xy(world, visit.seat, spot)
			var why := "hand %d: the roller lies at %s (walled %s)" % [hand, lie, walled]
			assert_float(signf(across)).override_failure_message(why).is_equal(want)
			var edge := 0.5
			if _has_wall(world, visit.seat["approach"], frame.basis.x * want):
				edge = 0.5 - BuildView.WALL_THICKNESS / 2.0
			var reach := absf(across) + ROLLER_HALF_M
			assert_float(reach).override_failure_message(why).is_less_equal(edge)
			var panel := lie.y - ROLLER_HALF_M
			assert_float(panel).override_failure_message(why).is_greater(PANEL_FACE_M)
			var feet := absf(across) - ROLLER_HALF_M
			assert_float(feet).override_failure_message(why).is_greater(FEET_HALF_M)
		checked += 1
		world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SEATED)
	assert_int(checked).is_greater(CafeSim.STEP_IN_HOLD_TICKS)


## Whether a wall stands on the edge of `cell` that `towards` (world, flat)
## points out through, read from the grid's own edge record.
func _has_wall(world: PassengerTestWorld, cell: Vector2i, towards: Vector3) -> bool:
	var step := Vector2i(roundi(signf(towards.x)), 0)
	if absf(towards.z) > absf(towards.x):
		step = Vector2i(0, roundi(signf(towards.z)))
	var sides := {Vector2i(0, -1): 0, Vector2i(1, 0): 1, Vector2i(0, 1): 2, Vector2i(-1, 0): 3}
	return world.grid.has_wall(cell, sides[step])


## A booth roller guest whose booth is moved (a room move, as
## test_room_move_cafe drives it) during its step-in hold turns back where it
## stands, at the approach cell: no jump onto the seat on the turn-back tick or
## the tick after (it was 0.5 of the way along the step-in path with the
## sit-down's spent ticks counting the hold).
func test_a_booth_roller_guest_turned_back_in_its_hold_stays_at_the_approach() -> void:
	var made := _sitting(&"restaurant_booth", true)
	var world: PassengerTestWorld = made[0]
	var p: Passenger = made[1]
	var visit := world.sim.cafes.visit_of(p.id)
	var approach := world.grid.cell_to_world(visit.seat["approach"])
	for n in 6:
		world.step()
	assert_int(p.stage).is_equal(Passenger.Stage.CAFE_SITTING_DOWN)
	var id := int(visit.seat["object_id"])
	var record := world.grid.get_object(id)
	var anchor: Vector2i = record["anchor"]
	var moved := Vector2i.ZERO
	for d: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if _place_booth(world, id, record, anchor + d, true):
			moved = d
			break
		_place_booth(world, id, record, anchor, false)
	print("booth moved by %s" % [moved])
	assert_bool(moved != Vector2i.ZERO).override_failure_message("no move was accepted").is_true()
	var turned := -1
	for n in 3:
		world.step()
		if p.stage == Passenger.Stage.CAFE_STANDING_UP and turned < 0:
			turned = world.clock.tick
		if turned >= 0:
			var at := world.sim.cafes.seat_position(p)
			var off := Vector2(at.x - approach.x, at.z - approach.z).length()
			print(
				(
					"tick %d after the turn-back: %.3f m from the approach"
					% [world.clock.tick - turned, off]
				)
			)
			assert_float(off).is_less(0.001)
	assert_int(turned).is_greater(0)
	assert_object(visit.relocation).is_not_null()


## Removes the booth `id` (its grid `record`) and places it again at `anchor`
## under its id, as a room move does; whether the place was accepted (the
## removal alone when `remove` is false).
func _place_booth(
	world: PassengerTestWorld, id: int, record: Dictionary, anchor: Vector2i, remove: bool
) -> bool:
	var place := BuildEdit.place_object(record["def"], anchor, record["facing"])
	place.object_id = id
	place.paid = int(record.get("paid", 0))
	var edits: Array[BuildEdit] = [place]
	if remove:
		edits.push_front(BuildEdit.remove_object(id))
	return world.grid.apply_batch(edits)[-1].ok


func test_a_cafe_table_guest_keeps_the_straight_shuffle() -> void:
	var made := _sitting(&"cafe_table")
	var path := _track(made[0], made[1], Passenger.Stage.CAFE_SITTING_DOWN, CafeSim.SHUFFLE_TICKS)
	print("cafe table shuffle [ahead, across] per tick: %s" % [path])
	assert_float(path[0].length()).is_greater(0.4)
	# Every spot on the line from the approach cell to the root.
	for at in path:
		assert_float(absf(at.x * path[0].y - at.y * path[0].x)).is_less(0.001)
	assert_float(path[-1].length()).is_less(0.001)


## A booth set-down's roller drawn into a wall's face (BoothRoller.clear_of(),
## with the faces BoothRoller.fix_start() keeps) moves back along the wall's
## normal by exactly its depth in it, and one clear of the face is not moved.
## Control: the roller was 0.1 m into the face.
func test_a_booth_set_down_roller_in_a_wall_moves_back_by_its_depth() -> void:
	var made := _sitting(&"restaurant_booth", true)
	var world: PassengerTestWorld = made[0]
	var cell := Vector2i(-1, -1)
	var out := Vector3.ZERO
	var steps := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for y in world.grid.size.y:
		for x in world.grid.size.x:
			for s in 4:
				if out == Vector3.ZERO and world.grid.has_wall(Vector2i(x, y), s):
					cell = Vector2i(x, y)
					out = Vector3(steps[s].x, 0.0, steps[s].y)
	assert_bool(out != Vector3.ZERO).override_failure_message("no wall in the layout").is_true()
	var face := world.grid.cell_to_world(cell) + out * (0.5 - BuildView.WALL_THICKNESS / 2.0)
	var faces := [[face, out]]
	var box := CarryOnProps.bag_box(SecurityLooks.Kind.ROLLER)
	var reach := -INF
	for k in 8:
		reach = maxf(reach, box.get_endpoint(k).dot(out))
	var into := Transform3D(Basis.IDENTITY, face - out * (reach - 0.1))
	var moved := BoothRoller.clear_of(into, faces)
	var deepest := -INF
	for k in 8:
		deepest = maxf(deepest, (moved * box.get_endpoint(k) - face).dot(out))
	var back := into.origin.distance_to(moved.origin)
	print("wall at %s: moved back %.3f m, box to %.4f m past the face" % [cell, back, deepest])
	assert_float(back).is_equal_approx(0.1, 0.0005)
	assert_float(deepest).is_equal_approx(0.0, 0.0005)
	var clear := Transform3D(Basis.IDENTITY, face - out * (reach + 0.05))
	assert_vector(BoothRoller.clear_of(clear, faces).origin).is_equal(clear.origin)


## The start of a roller's set-down from the pull is fixed in the world, with
## the wall faces kept, only at a booth seat; at a cafe table it stays in the
## body's frame as on main (CarryOnProps: frame * "from", no "from_world").
## Control: the cafe table guest's park was stamped.
func test_only_a_booth_set_down_starts_fixed_in_the_world() -> void:
	for table: StringName in [&"cafe_table", &"restaurant_booth"]:
		var made := _sitting(table, true, true)
		var world: PassengerTestWorld = made[0]
		var views: PassengerViews = made[2]
		for n in 2:
			world.step()
			views.draw()
		var bag := views.carry_on_props().bag_state((made[1] as Passenger).id, 0)
		var booth := table == &"restaurant_booth"
		print(
			"%s set-down: park %s, fixed start %s" % [table, bag.get("park"), bag.has("from_world")]
		)
		assert_bool(bag.get("park", false)).is_true()
		assert_bool(bag.has("from_world")).is_equal(booth)
		assert_bool(bag.has("wall_faces")).is_equal(booth)
