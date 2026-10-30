class_name TestCarryBackpackGrip
extends GdUnitTestSuite
## A backpack is held by its top grab loop whenever a hand holds it (conductor
## ruling 2026-10-30 on the floating-bags lane: the palm closes on the loop,
## the pack hangs below the hand), on its whole toilet visit: off the back into
## the hand, the side hang, the front carry to the stall, set down and picked
## up in the stall, and back on the back. Every drawn frame a hand holds it, the
## grip is within the probes' GRIP_ON limit (spike/carry_float_check.gd, 3 cm)
## of the loop, and no finger, thumb or hand vertex of the holding hand is
## inside the pack's meshes. Controls: the grip measured is the one the pack is
## placed from (CarryOnProps' "held_at" lies on it), and each move was seen held.

const FloatCheck := preload("res://spike/carry_float_check.gd")
const CarryContact := preload("res://spike/carry_contact.gd")
const FRAME_TICKS := 0.75
## Frames followed after the walker has left the stall (the pack goes back on).
const AFTER_FRAMES := 40

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	if _views != null:
		_views.free()
	PassengerTestWorld.tracker = null


func _tick(ticks: float) -> void:
	_world.clock.advance(SimClock.STEP * ticks)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()


## A one-backpack passenger sent to a stall (as TestCarryStallLead).
func _visitor() -> Passenger:
	var grid := BuildGrid.new()
	ToiletTestLayout.build(grid)
	_world = PassengerTestWorld.make(grid, FlightSim.schedule_starts(0))
	_world.run_to(10)
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	RenderingServer.frame_pre_draw.disconnect(_views.carry_on_props()._unposed)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.BACKPACK:
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.liquids = false
	p.alarm = false
	p.stage = Passenger.Stage.TO_SECURITY
	p.at = Vector2i(20, 14)
	p.clear_path()
	assert_bool(_world.sim.toilets.try_visit(p)).is_true()
	return p


## How many vertices of the hand chain of `side` (".R" or ".L") of `body` lie
## inside the meshes of `bag`.
static func _fingers_in(body: Node3D, bag: Node3D, side: String) -> int:
	var owned := CarryContact.body_points_owned(body, [])
	var hand := PackedVector3Array()
	for n in (owned[0] as PackedVector3Array).size():
		var bone: String = owned[1][n]
		for part in CarryContact.HAND_CHAIN:
			if bone == part + side:
				hand.append(owned[0][n])
	return CarryContact.inside_meshes(hand, bag)


func test_a_held_backpack_is_held_by_its_loop_on_its_whole_visit() -> void:
	var p := _visitor()
	var props := _views.carry_on_props()
	var by_move := {}
	var placed_off := 0.0
	var worst := 0.0
	var fingers := 0
	var visited := false
	var after := 0
	while _world.clock.tick < 20000 and after < AFTER_FRAMES:
		var sat := _world.clock.tick - p.stage_tick
		if p.stage == Passenger.Stage.TOILET_USE and sat < ToiletSim.USE_TICKS - 4:
			_world.step()
			continue
		await _tick(FRAME_TICKS)
		visited = visited or p.stage == Passenger.Stage.TOILET_EXIT
		if visited and not Passenger.in_toilet(p.stage):
			after += 1
		var body := _views.node_for(p.id)
		var bag := props.bag_state(p.id, 0)
		var on := FloatCheck.grip_on_gap(props, p.id, 0, body)
		if not (on[0] as float) < INF:
			continue
		var holder: int = bag["held_by"]
		var node: Node3D = bag["node"]
		var grip := props.grip_of(body, holder)
		placed_off = maxf(
			placed_off, (node.global_transform * (bag["held_at"] as Vector3)).distance_to(grip)
		)
		var move := FloatCheck.move_of(props, p.id, 0).replace(".R", "").replace(".L", "")
		var key := move if move != "" else "settled"
		var inside := _fingers_in(body, node, [".R", ".L"][holder])
		var seen: Array = by_move.get(key, [0, 0.0, 0])
		by_move[key] = [seen[0] + 1, maxf(seen[1], snappedf(on[0], 0.001)), seen[2] + inside]
		worst = maxf(worst, on[0])
		fingers += inside
	print(
		(
			"held frames by move [frames, largest grip-to-loop gap m, hand vertices in the pack]: %s"
			% [by_move]
		)
	)
	print("grip to the point placed at it: at most %.4f m" % placed_off)
	assert_float(placed_off).is_less(0.005)
	for move in ["back>hand", "hand>back", "hand>floor", "floor>hand", "settled"]:
		assert_bool(by_move.has(move)).is_true()
	assert_float(worst).is_less_equal(FloatCheck.GRIP_ON_M)
	assert_int(fingers).is_equal(0)
