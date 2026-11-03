class_name TestCarryStallFrontMargin
extends GdUnitTestSuite
## A bag hand-carried or pulled by a walker who has left a stall keeps clear of
## the stall front (board a791eb90). test_carry_in_stall.gd allows a bag to
## stand at the front plane itself; the hand-back wait at the end of a visit
## (VisitHandBack) took a step of lead off the walker and showed a hand-held
## roller hanging 1 to 3 cm inside the plane while it passed the stall's side
## partition. After the visit, whenever a bag is over the stall's column (its
## partitions' outer faces), its box stays at least MARGIN_M beyond the front
## plane. Every kind of bag, one bag and two; the control is that each bag was
## over the column on some frames.

## The stall's door outer face and the partitions' outer faces, in the stall's
## frame (metres out of the footprint centre, and across).
const FRONT_M := 0.9
const COLUMN_HALF_M := 0.53
## The clearance asked beyond the front plane (the partitions are 6 cm thick).
const MARGIN_M := 0.02
const AFTER_M := 4.0
## Sim ticks per frame: not a whole tick, so frames fall between ticks.
const FRAME_TICKS := 0.75

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


func _visitor(kind: SecurityLooks.Kind, count: int) -> Passenger:
	_free_world()
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


func _frame() -> void:
	_world.clock.advance(SimClock.STEP * FRAME_TICKS)
	await get_tree().process_frame
	await get_tree().create_timer(0.0, true, false, true).timeout
	_views.carry_on_props()._unposed()


## Runs `p`'s visit and the walk AFTER_M beyond it. Returns {"over": frames a
## bag was over the stall's column after the visit, "nearest": the lowest
## distance out of the stall's front plane of any such frame (in metres, minus
## FRONT_M), "at": the tick of that frame}.
func _after_visit(p: Passenger) -> Dictionary:
	var props := _views.carry_on_props()
	var stall := _world.sim.toilets.visit_of(p.id).stall
	var out := SecurityLooks.world_dir(stall["front"])
	var across := out.cross(Vector3.UP)
	var centre: Vector3 = stall["use"] - out * ToiletLayout.USE_M
	var approach := _world.sim.grid.cell_to_world(stall["approach"])
	var over := 0
	var nearest := INF
	var at := 0
	var visited := false
	while _world.clock.tick < 20000:
		var sat := _world.clock.tick - p.stage_tick
		if p.stage == Passenger.Stage.TOILET_USE and sat < ToiletSim.USE_TICKS - 4:
			_world.step()
			continue
		await _frame()
		var body := _views.node_for(p.id)
		visited = visited or p.stage == Passenger.Stage.TOILET_EXIT
		if visited and not Passenger.in_toilet(p.stage):
			var away := body.global_position - approach
			if Vector2(away.x, away.z).length() > AFTER_M:
				break
		if not visited or Passenger.in_toilet(p.stage):
			continue
		var held := props.props_of(p.id)
		for b in (held["bags"] as Array).size():
			var node: Node3D = held["bags"][b]
			var box := CarryOnProps.bag_box(held["kinds"][b])
			var lo := Vector3.INF
			var hi := -Vector3.INF
			for i in 8:
				var corner := node.global_transform * box.get_endpoint(i) - centre
				var local := Vector3(corner.dot(across), corner.y, corner.dot(out))
				lo = lo.min(local)
				hi = hi.max(local)
			if lo.x < COLUMN_HALF_M and hi.x > -COLUMN_HALF_M and lo.z < FRONT_M + 1.0:
				over += 1
				if lo.z - FRONT_M < nearest:
					nearest = lo.z - FRONT_M
					at = _world.clock.tick
	assert_bool(visited).is_true()
	return {"over": over, "nearest": nearest, "at": at}


func test_a_bag_leaving_a_stall_keeps_clear_of_its_front() -> void:
	for count in [1, 2]:
		for kind in SecurityLooks.Kind.values():
			var result := await _after_visit(_visitor(kind, count))
			print(
				(
					(
						"%d bags, first kind %d: frames over the column %d, nearest %.3f m beyond"
						+ " the front plane at tick %d"
					)
					% [count, kind, result["over"], result["nearest"], result["at"]]
				)
			)
			assert_int(result["over"]).is_greater(0)
			assert_float(result["nearest"]).is_greater_equal(MARGIN_M)
