class_name TestFloorRollerSlide
extends GdUnitTestSuite
## A roller lying on the floor at a gate chair whose way out of the walls
## (CarryPlace._off_walls(), ParkWalls) changes with a wall built or taken down
## beside it slides to its new spot at CarryPlace.SLIDE_M_PER_TICK from the
## edit's tick, instead of moving there in one frame (board 4cb91d64: a wall on
## the front cell's edge moved it 0.079 m in a tick). The slide is worked out
## from the edit's tick and the spot before it, so a first draw late after the
## edit draws the same spot. The way out is kept per bag and worked out again
## only when the spot or the grid changes. Drawn by real PassengerViews, a tick
## a draw, with no frames between.

## Ticks drawn after an edit: more than any slide of these takes.
const AFTER_TICKS := 30
## Ticks after the edit the late run draws first.
const LATE_TICKS := 2

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
	if _world != null:
		_world.free_all()
	_views = null
	_world = null


func _tick(draw := true) -> void:
	_world.step()
	if draw:
		_views.draw()


## A walker with one roller sat at the first gate chair, its roller lying
## settled on the floor beside the feet. Returns [the passenger, the edge
## (cell, side) of the chair front's cell on the roller's side].
func _seated() -> Array:
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	var seat: Dictionary = _world.sim.layout.seats[0]
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	var p := _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	while SecurityLooks.bag_kind(p, 0) != SecurityLooks.Kind.ROLLER:
		ToiletTestLayout.calm(p)
		p.carry_on = 0
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.at = seat["front"]
	p.clear_path()
	p.boarding_tick = _world.sim.tick + 100000
	for n in 4:
		_tick()
	p.seat_object = seat["object_id"]
	p.seat_piece = Relocation.placement(_world.grid, p.seat_object)
	p.stage = Passenger.Stage.SITTING_DOWN
	p.stage_tick = _world.sim.tick
	p.clear_path()
	for n in 60:
		_tick()
	var props := _views.carry_on_props()
	assert_int(int(props.bag_state(p.id, 0).get("place", -1)) / 4).is_equal(
		SecurityLooks.Home.FLOOR
	)
	assert_float(props.transfer_progress(p.id, 0)).is_equal(1.0)
	# +x of a frame facing out of the chair is on the left of one facing out.
	var front: Vector2i = seat["front"]
	var out: Vector2i = front - (seat["cell"] as Vector2i)
	var x := Basis(Vector3.UP, atan2(out.x, out.y)).x
	var right := Vector2i(roundi(-x.x), roundi(-x.z))
	var hand := SecurityLooks.hand_of(_world.sim, p, 0)
	var step := right if hand == 0 else -right
	return [p, front, BuildGrid.SIDE_STEP.find(step)]


func _node(p: Passenger) -> Node3D:
	return _views.carry_on_props().bag_state(p.id, 0)["node"]


## The drawn roller's largest move in a tick over AFTER_TICKS ticks from
## `edit` applied now, and where it ends.
func _drawn_after(p: Passenger, edit: BuildEdit) -> Array:
	var node := _node(p)
	var last := node.global_position
	assert_bool(_world.grid.apply(edit).ok).override_failure_message("edit refused").is_true()
	var most := 0.0
	for n in AFTER_TICKS:
		_tick()
		most = maxf(most, node.global_position.distance_to(last))
		last = node.global_position
	return [most, last]


## A wall built on the edge beside the lying roller moves it out of the wall
## by no more than SLIDE_M_PER_TICK in any tick, and the wall taken down again
## moves it back the same way. Control: the wall did move the roller (more
## than SLIDE_M_PER_TICK in all), it ends out of the wall, and it ends back
## where it lay once the wall is gone.
func test_a_wall_edit_beside_a_lying_roller_slides_it() -> void:
	var seated := _seated()
	var p: Passenger = seated[0]
	var before_at := _node(p).global_position
	var built := _drawn_after(p, BuildEdit.place_wall(seated[1], seated[2]))
	var walls := PullSide.walls_near(_world.grid, before_at)
	var out_of := not ParkWalls.inside(_node(p).global_transform, walls)
	var gone := _drawn_after(p, BuildEdit.remove_wall(seated[1], seated[2]))
	var moved := (built[1] as Vector3).distance_to(before_at)
	var back := (gone[1] as Vector3).distance_to(before_at)
	print(
		(
			"wall edit: built most %.4f moved %.4f out %s, removed most %.4f back %.4f"
			% [built[0], moved, out_of, gone[0], back]
		)
	)
	assert_float(moved).is_greater(CarryPlace.SLIDE_M_PER_TICK)
	assert_bool(out_of).is_true()
	assert_float(built[0]).is_less_equal(CarryPlace.SLIDE_M_PER_TICK + 0.0001)
	assert_float(gone[0]).is_less_equal(CarryPlace.SLIDE_M_PER_TICK + 0.0001)
	assert_float(back).is_less(0.0001)


## The roller's spot LATE_TICKS ticks after a wall edit is the same whether
## every tick was drawn or the first draw after the edit came only then.
## Control: both worlds drew the roller at the same spot before the edit, and
## at LATE_TICKS it is partway along its slide, not at either end.
func test_a_late_first_draw_after_the_edit_draws_the_same_slide() -> void:
	var runs: Array[Dictionary] = []
	for late in [false, true]:
		var seated := _seated()
		var p: Passenger = seated[0]
		var start := _node(p).global_position
		assert_bool(_world.grid.apply(BuildEdit.place_wall(seated[1], seated[2])).ok).is_true()
		for n in LATE_TICKS:
			_tick(not late or n == LATE_TICKS - 1)
		var mid := _node(p).global_position
		for n in AFTER_TICKS:
			_tick()
		runs.append({"start": start, "mid": mid, "end": _node(p).global_position})
		_free()
	print("late first draw: every tick %s, late %s" % runs)
	var every: Dictionary = runs[0]
	var late_run: Dictionary = runs[1]
	assert_float((every["start"] as Vector3).distance_to(late_run["start"])).is_less(0.00001)
	assert_float((every["mid"] as Vector3).distance_to(late_run["mid"])).is_less(0.00001)
	var whole := (every["end"] as Vector3).distance_to(every["start"])
	var gone := (every["mid"] as Vector3).distance_to(every["start"])
	assert_float(gone).is_greater(0.001)
	assert_float(gone).is_less(whole - 0.001)


## A draw with nothing changed reads the kept way out (the same record),
## for 10 ticks; an edit makes a new one. Control: the record is there.
## bag_state() is a shallow copy, read again on every tick: "wall_off" in it is
## the record itself.
func test_the_way_out_is_kept_until_an_edit() -> void:
	var seated := _seated()
	var p: Passenger = seated[0]
	var props := _views.carry_on_props()
	var kept: Variant = props.bag_state(p.id, 0).get("wall_off")
	assert_bool(kept is Dictionary).override_failure_message("no kept way out").is_true()
	var same := 0
	for n in 10:
		_tick()
		if is_same(props.bag_state(p.id, 0).get("wall_off"), kept):
			same += 1
	assert_bool(_world.grid.apply(BuildEdit.place_wall(seated[1], seated[2])).ok).is_true()
	_tick()
	var renewed := not is_same(props.bag_state(p.id, 0).get("wall_off"), kept)
	print("kept way out: same on %d of 10 draws, new after the edit %s" % [same, renewed])
	assert_int(same).is_equal(10)
	assert_bool(renewed).is_true()


## A slide read at a tick before its start (the clock gone back, as after a
## load) is at its end; one tick in, it is SLIDE_M_PER_TICK along.
func test_a_slide_read_before_its_start_is_at_its_end() -> void:
	var off := {"from": Vector3.ZERO, "to": Vector3(0.1, 0.0, 0.0), "since": 10.0}
	assert_vector(CarryPlace.slid(off, 5.0)).is_equal(Vector3(0.1, 0.0, 0.0))
	assert_vector(CarryPlace.slid(off, 10.0)).is_equal(Vector3.ZERO)
	assert_vector(CarryPlace.slid(off, 11.0)).is_equal_approx(
		Vector3(CarryPlace.SLIDE_M_PER_TICK, 0.0, 0.0), Vector3.ONE * 0.000001
	)
