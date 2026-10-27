class_name TestBaggageCornerViews
extends GdUnitTestSuite
## BaggageViews on corner pieces (headless: positions only). The sim moves a
## bag straight to a corner's centre and turns it there, which put the bag's
## outer corner through the outer rail; the view now draws it along a turn
## of BaggageViews.TURN_RADIUS. A bag's footprint must stay inside the belt
## lane of every piece under it at every tick and at the in-between poses
## draw() makes (the newer heading on an interpolated position).
##
## Layout (BagTestWorld's desk at (2, 8)): a bag room at (5, 10) and one belt
## line from (3, 7) to (6, 10), so the desk's outlet cell (3, 7) is a corner
## (desk from the south, belt to the east) and (6, 7) a belt-to-belt corner
## (from the west, out to the south). The end (6, 10) is in the room.

## Belt lane half width and the corner lane's radii about the inner corner
## (build_baggage_kit.py LANE, EDGE - LANE, EDGE + LANE).
const LANE := 0.35
const TURN_IN := 0.15
const TURN_OUT := 0.85
const SLACK := 0.001
const ROOM := Rect2i(5, 10, 3, 2)
const LINE_TO := Vector2i(6, 10)
const DESK_CORNER := Vector2i(3, 7)
const BELT_CORNER := Vector2i(6, 7)

var _world: BagTestWorld
var _desk := 0
var _bag_box := AABB()


func before() -> void:
	var bag := BaggageViews.BAG_SCENE.instantiate() as Node3D
	for mi in bag.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb()
		_bag_box = box if _bag_box.size == Vector3.ZERO else _bag_box.merge(box)
	bag.free()


func before_test() -> void:
	_world = BagTestWorld.make(self, 2000)
	_world.room(ROOM)
	_desk = _world.desk(BagTestWorld.DESK)
	_world.lay(BagTestWorld.ENTRY, LINE_TO)


func test_the_layout_has_the_two_corners_and_ends_in_the_room() -> void:
	for cell in [DESK_CORNER, BELT_CORNER]:
		assert_str(str(_def_at(cell))).is_equal(str(BeltShaper.CORNER))
	assert_str(str(_def_at(LINE_TO))).is_equal(str(BeltShaper.END))
	assert_float(_bag_box.size.x).is_between(0.3, 0.45)
	assert_float(_bag_box.size.z).is_between(0.5, 0.6)


func test_turn_ends_meet_the_straight_legs_for_every_entry_side() -> void:
	var centre := Vector3(4.5, 0.0, 7.5)
	var count := 0
	for entry in BuildGrid.SIDE_STEP:
		for exit in [Vector2i(entry.y, -entry.x), Vector2i(-entry.y, entry.x)]:
			var e := Vector3(entry.x, 0.0, entry.y)
			var x := Vector3(exit.x, 0.0, exit.y)
			var up := Vector3(0.0, BaggageViews.BELT_TOP, 0.0)
			var start := BaggageViews.turn_transform(centre, entry, exit, 0.0)
			assert_vector(start.origin).is_equal_approx(centre + e * 0.5 + up, Vector3.ONE * 1e-4)
			assert_vector(start.basis.z).is_equal_approx(-e, Vector3.ONE * 1e-4)
			var finish := BaggageViews.turn_transform(centre, entry, exit, 1.0)
			assert_vector(finish.origin).is_equal_approx(centre + x * 0.5 + up, Vector3.ONE * 1e-4)
			assert_vector(finish.basis.z).is_equal_approx(x, Vector3.ONE * 1e-4)
			var middle := BaggageViews.turn_transform(centre, entry, exit, 0.5)
			var pivot := centre + (e + x) * 0.5
			var flat := Vector3(middle.origin.x - pivot.x, 0.0, middle.origin.z - pivot.z)
			assert_float(flat.length()).is_equal_approx(0.5207, 1e-3)
			assert_vector(middle.basis.z).is_equal_approx((x - e).normalized(), Vector3.ONE * 1e-4)
			count += 1
	assert_int(count).is_equal(8)


func test_a_bag_through_both_corners_stays_inside_the_lane() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	var on_corner := {DESK_CORNER: 0, BELT_CORNER: 0}
	var prev := Transform3D()
	var seen := false
	while bag.state != Bag.State.IN_ROOM and _world.clock.tick < 400:
		_world.step()
		if not bag.on_belt():
			continue
		var after := BaggageViews.belt_transform(_world.grid, bag)
		if not seen:
			prev = after
			seen = true
		# draw() puts the newer heading on a position between the two ticks.
		for alpha in [0.0, 0.5, 1.0]:
			var drawn := Transform3D(after.basis, prev.origin.lerp(after.origin, alpha))
			var problem := _outside_lane(drawn, bag.from_desk)
			(
				assert_str(problem)
				. override_failure_message(
					"tick %d alpha %.1f: %s" % [_world.clock.tick, alpha, problem]
				)
				. is_empty()
			)
		var under := _world.grid.world_to_cell(after.origin)
		if on_corner.has(under):
			on_corner[under] += 1
		prev = after
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	# Positive control: the bag spent ticks on both corners (20 per cell).
	assert_int(on_corner[DESK_CORNER]).is_greater(5)
	assert_int(on_corner[BELT_CORNER]).is_greater(10)


func test_the_lane_check_catches_the_straight_path_through_a_corner_centre() -> void:
	# Control: the old drawing (straight to the centre, turned there) is what the
	# lane check exists to catch.
	var centre := _world.grid.cell_to_world(BELT_CORNER)
	var straight := Transform3D(
		Basis(Vector3.UP, atan2(1.0, 0.0)), centre + Vector3(0.0, BaggageViews.BELT_TOP, 0.0)
	)
	assert_str(_outside_lane(straight, false)).contains("corner")


func test_a_bag_moves_smoothly_through_the_corners() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	var last := Transform3D()
	var moves := 0
	while _world.clock.tick < 400:
		_world.step()
		if bag.state != Bag.State.RIDING or bag.from_desk:
			last = Transform3D()
			continue
		var now := BaggageViews.belt_transform(_world.grid, bag)
		if last != Transform3D():
			var moved := now.origin.distance_to(last.origin)
			var turned := rad_to_deg(now.basis.z.angle_to(last.basis.z))
			(
				assert_float(moved)
				. override_failure_message("tick %d moved %.4f m" % [_world.clock.tick, moved])
				. is_between(0.03, 0.051)
			)
			(
				assert_float(turned)
				. override_failure_message(
					"tick %d turned %.2f degrees" % [_world.clock.tick, turned]
				)
				. is_less_equal(6.0)
			)
			moves += 1
		last = now
	assert_int(moves).is_greater(100)


func test_a_bag_from_the_desk_still_starts_half_a_cell_in() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.step()
	var at := BaggageViews.belt_transform(_world.grid, bag)
	var expected := (
		_world.grid.cell_to_world(DESK_CORNER) + Vector3(0.0, BaggageViews.BELT_TOP, 0.45)
	)
	assert_vector(at.origin).is_equal_approx(expected, Vector3.ONE * 1e-4)
	assert_vector(at.basis.z).is_equal_approx(Vector3(0.0, 0.0, -1.0), Vector3.ONE * 1e-4)


func test_a_corner_without_the_bags_side_draws_the_straight_path() -> void:
	# The desk corner's ports are south and east. A bag entering from the north
	# or leaving to the west does not travel through it, so it is drawn straight.
	var centre := _world.grid.cell_to_world(DESK_CORNER)
	var entering := _bag(DESK_CORNER, Vector2i(0, 1), 300)
	var drawn := BaggageViews.belt_transform(_world.grid, entering)
	assert_vector(drawn.origin).is_equal_approx(
		centre + Vector3(0.0, BaggageViews.BELT_TOP, -0.3), Vector3.ONE * 1e-4
	)
	var leaving := _bag(DESK_CORNER + Vector2i(-1, 0), Vector2i(-1, 0), 800)
	drawn = BaggageViews.belt_transform(_world.grid, leaving)
	assert_vector(drawn.origin).is_equal_approx(
		centre + Vector3(-0.2, BaggageViews.BELT_TOP, 0.0), Vector3.ONE * 1e-4
	)
	# Same corner, the bag's real sides: drawn on the turn, which runs inside
	# the straight path, toward the inner corner (south here).
	var real := _bag(DESK_CORNER + Vector2i(1, 0), Vector2i(1, 0), 800)
	drawn = BaggageViews.belt_transform(_world.grid, real)
	assert_float(drawn.origin.z - centre.z).is_greater(0.01)


func test_views_leave_the_sim_unchanged() -> void:
	var views: BaggageViews = auto_free(BaggageViews.new())
	views.clock = _world.clock
	views.sim = _world.sim
	add_child(views)
	_world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.sim.check_in(2, BagTestWorld.FLIGHT, _desk)
	for i in 60:
		_world.step()
		var was := _world.signature()
		views.sync()
		views.draw()
		assert_str(_world.signature()).is_equal(was)
	assert_int(views.active_count()).is_greater(0)


func _bag(cell: Vector2i, step: Vector2i, remain: int) -> Bag:
	var bag := Bag.new()
	bag.state = Bag.State.RIDING
	bag.cell = cell
	bag.from_step = step
	bag.remain_mm = remain
	return bag


func _def_at(cell: Vector2i) -> StringName:
	return StringName(_world.grid.get_object(_world.grid.object_at(cell)).get("def", ""))


## "" when every point of a 9 x 9 grid over the bottom of a bag drawn at `at`
## lies inside the belt lane of the piece under it, else the first point that
## does not. A point over the desk's outlet cell, within its lane, is allowed
## while the bag is still coming off the desk.
func _outside_lane(at: Transform3D, from_desk: bool) -> String:
	for i in 9:
		for j in 9:
			var local := (
				_bag_box.position
				+ Vector3(_bag_box.size.x * i / 8.0, 0.0, _bag_box.size.z * j / 8.0)
			)
			var p := at * local
			var cell := _world.grid.world_to_cell(p)
			var record := _world.grid.get_object(_world.grid.object_at(cell))
			var def := StringName(record.get("def", ""))
			var centre := _world.grid.cell_to_world(cell)
			var off := Vector2(p.x - centre.x, p.z - centre.z)
			var sides: Array[Vector2] = []
			for port in BuildCatalog.belt_ports(
				def, record.get("anchor", cell), record.get("facing", 0)
			):
				sides.append(Vector2(port["side"]))
			match def:
				BeltShaper.CORNER:
					var radius := off.distance_to((sides[0] + sides[1]) * 0.5)
					if radius < TURN_IN - SLACK or radius > TURN_OUT + SLACK:
						return (
							"point %s on the corner at %s is %.3f m from its pivot"
							% [p, cell, radius]
						)
				BeltShaper.BELT, BeltShaper.END:
					var across := absf(off.dot(Vector2(sides[0].y, -sides[0].x)))
					if across > LANE + SLACK:
						return (
							"point %s on %s at %s is %.3f m off its centre line"
							% [p, def, cell, across]
						)
				&"checkin_desk":
					# Only the desk's outlet cell, within the lane of its outlet.
					var outlet: Dictionary = (
						BuildCatalog.belt_ports(def, record["anchor"], record["facing"])[0]
					)
					var across := absf(off.dot(Vector2(sides[0].y, -sides[0].x)))
					if not from_desk or cell != outlet["cell"] or across > LANE + SLACK:
						return "point %s is over the desk off its outlet's lane" % p
				_:
					return "point %s at %s is on no belt (%s)" % [p, cell, def]
	return ""
