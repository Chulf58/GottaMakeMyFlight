class_name TestTaxiRoutes
extends GdUnitTestSuite
## TaxiRoutes is the one source of every phase path (board e1352963; decision
## airside-all-around-technical-design-one-route-source-per-con, slice S0).
## Its paths equal the ones the A* over the taxi graph drew before it, for
## every fallback gate (FlightGround.fallback()) on the lane, every phase and
## every class. The A* is rebuilt here as the oracle, the way Airside.rebuild()
## and phase_path() ran it, so this file keeps checking after it went. With
## several gates set the A* also passed through the other gates' joins,
## straight points on the lane that TaxiRoutes leaves out. Airside.phase_path()
## and FlightGround.routes() both give TaxiRoutes' paths.

const STATES: Array[int] = [
	FlightSim.State.APPROACH,
	FlightSim.State.LANDING,
	FlightSim.State.TAXI_IN,
	FlightSim.State.PUSHBACK,
	FlightSim.State.TAXI_OUT,
	FlightSim.State.TAKEOFF,
]
const TAXI_STATES: Array[int] = [FlightSim.State.TAXI_IN, FlightSim.State.TAXI_OUT]
const LANE_ENDS: Array[StringName] = [&"TaxiWest", &"TaxiEast"]

var _airside: Airside


func before() -> void:
	_airside = TestStandLaneClearance.scene_airside()
	add_child(_airside)


func after() -> void:
	_airside.free()


## The fallback gates whose join lies strictly inside the lane's ends.
static func _lane_gates() -> Array[String]:
	var p := FlightGround.points()
	var out: Array[String] = []
	for letter in FlightGround.LETTERS:
		var join := StandPlacement.lane_join(FlightGround.fallback(letter)["stand"])
		if join.x > (p[&"TaxiWest"] as Vector3).x and join.x < (p[&"TaxiEast"] as Vector3).x:
			out.append(letter)
	return out


static func _on_lane(waypoint: String) -> bool:
	return LANE_ENDS.has(StringName(waypoint)) or waypoint.begins_with("StandLane")


static func _gate_point(base: String, gate: String) -> StringName:
	return StringName("%s_%s" % [base, gate]) if gate != "" else StringName(base)


## The old drawn route: Airside.rebuild()'s graph (the scene's links less those
## between two lane waypoints, each gate's two stand links, the lane chain east
## to west through every join in falling x) and phase_path()'s A* routes.
func _old_path(state: int, gate: String, plane_class: String) -> PackedVector3Array:
	var astar := AStar3D.new()
	var ids := {}
	for child in _airside.get_children():
		if child is Marker3D:
			ids[child.name] = ids.size()
			astar.add_point(ids[child.name], _airside.transform * child.position)
	var join := func(a: StringName, b: StringName) -> void: astar.connect_points(ids[a], ids[b])
	for pair in _airside.links:
		var ends := pair.split(">")
		if not (_on_lane(ends[0]) and _on_lane(ends[1])):
			join.call(StringName(ends[0]), StringName(ends[1]))
	for g: String in _airside.gate_stands:
		join.call(_gate_point("StandLane", g), _gate_point("PushbackEnd", g))
		join.call(_gate_point("PushbackEnd", g), _gate_point("Stand", g))
	var joins: Array[StringName] = []
	for name: StringName in ids:
		var one_stand := name == &"StandLane" and not _airside.gate_stands.is_empty()
		if _on_lane(name) and not LANE_ENDS.has(name) and not one_stand:
			joins.append(name)
	joins.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			return astar.get_point_position(ids[a]).x > astar.get_point_position(ids[b]).x
	)
	var chain: Array[StringName] = [&"TaxiEast"]
	chain.append_array(joins)
	chain.append(&"TaxiWest")
	for i in range(1, chain.size()):
		join.call(chain[i - 1], chain[i])
	var at := func(name: StringName) -> Vector3: return astar.get_point_position(ids[name])
	var suffix: String = Airside.CLASS_SUFFIX[plane_class]
	var stand_name := gate if _airside.gate_stands.has(gate) else ""
	var stand := _gate_point("Stand", stand_name)
	var back := _gate_point("PushbackEnd", stand_name)
	if state == FlightSim.State.TAXI_IN:
		return astar.get_point_path(ids[&"RunwayExit"], ids[stand])
	if state == FlightSim.State.TAXI_OUT:
		return astar.get_point_path(ids[back], ids[&"RunwayEntry"])
	var names := {
		FlightSim.State.APPROACH: ["ApproachStart" + suffix, "Touchdown" + suffix],
		FlightSim.State.LANDING: ["Touchdown" + suffix, "RunwayExit"],
		FlightSim.State.PUSHBACK: [stand, back],
		FlightSim.State.TAKEOFF: ["RunwayEntry", "Liftoff" + suffix, "ClimbEnd"],
	}
	var path := PackedVector3Array()
	for name in names.get(state, []):
		path.append(at.call(StringName(name)))
	return path


## TaxiRoutes' path for a fallback stand, as FlightGround plans it.
static func _new_path(state: int, stand: Dictionary, plane_class: String) -> PackedVector3Array:
	var p := FlightGround.points()
	var paths := TaxiRoutes.phase_paths(
		p, TaxiRoutes.stand_ends(stand), plane_class, TaxiRoutes.north_only(p)
	)
	return paths[state]


func test_each_fallback_gate_alone_gets_the_old_a_star_path_exactly() -> void:
	var gates := _lane_gates()
	print("fallback gates on the lane: %s" % [gates])
	assert_array(gates).is_equal(["A", "B", "C", "D", "E", "F"])
	var compared := 0
	for gate in gates:
		var stand: Dictionary = FlightGround.fallback(gate)["stand"]
		assert_bool(_airside.set_gate_stands({gate: stand})).is_true()
		for plane_class in PlaneClasses.ORDER:
			for state in STATES:
				var old := _old_path(state, gate, plane_class)
				var why := "gate %s %s state %d" % [gate, plane_class, state]
				assert_int(old.size()).override_failure_message(why).is_greater(1)
				var routed := _new_path(state, stand, plane_class)
				assert_array(Array(routed)).override_failure_message(why).is_equal(Array(old))
				var drawn := _airside.phase_path(state, gate, plane_class)
				assert_array(Array(drawn)).override_failure_message(why).is_equal(Array(old))
				var planned: PackedVector3Array = FlightGround.routes(stand, plane_class)[state]
				assert_array(Array(planned)).override_failure_message(why).is_equal(Array(old))
				compared += 1
	assert_bool(_airside.set_gate_stands({})).is_true()
	print("compared %d phase paths, each three ways" % compared)
	assert_int(compared).is_equal(6 * 3 * 6)


## With every lane gate set at once the A* route also passes each join between
## the lane end and the gate's own: straight points on the lane, the only
## difference from TaxiRoutes. Control: some were found.
func test_with_every_fallback_gate_set_the_old_a_star_only_adds_lane_joins() -> void:
	var stands := {}
	for gate in _lane_gates():
		stands[gate] = FlightGround.fallback(gate)["stand"]
	assert_bool(_airside.set_gate_stands(stands)).is_true()
	var lane_z := StandPlacement.TAXI_LANE_Z
	var compared := 0
	var extra := 0
	for gate: String in stands:
		for plane_class in PlaneClasses.ORDER:
			for state in STATES:
				var why := "gate %s %s state %d" % [gate, plane_class, state]
				var old := _old_path(state, gate, plane_class)
				var kept := PackedVector3Array()
				for i in old.size():
					var straight := (
						i > 0
						and i < old.size() - 1
						and old[i - 1].z == lane_z
						and old[i].z == lane_z
						and old[i + 1].z == lane_z
						and old[i - 1].x > old[i].x
						and old[i].x > old[i + 1].x
					)
					if straight:
						extra += 1
					else:
						kept.append(old[i])
				var routed := _new_path(state, stands[gate], plane_class)
				assert_array(Array(routed)).override_failure_message(why).is_equal(Array(kept))
				assert_float(FlightPose.path_length(routed)).is_equal_approx(
					FlightPose.path_length(old), 0.001
				)
				compared += 1
	assert_bool(_airside.set_gate_stands({})).is_true()
	print("compared %d phase paths; the A* added %d straight lane joins" % [compared, extra])
	assert_int(compared).is_equal(6 * 3 * 6)
	# Per class: taxi in to gate g passes the joins east of it, taxi out those
	# west of it, so each gate adds 5 between its two routes: 6 * 5 * 3 classes.
	assert_int(extra).is_equal(90)


## The one stand of main.tscn (no gate desks): TaxiRoutes from its Stand,
## PushbackEnd and StandLane waypoints gives the old A* path.
func test_the_one_stand_gets_the_old_a_star_path() -> void:
	assert_bool(_airside.set_gate_stands({})).is_true()
	var at := func(name: StringName) -> Vector3: return _airside.graph.position_of(name)
	var ends := {
		"spot": at.call(&"Stand"),
		"back": at.call(&"PushbackEnd"),
		"join": at.call(&"StandLane"),
	}
	var p := FlightGround.points()
	var compared := 0
	for plane_class in PlaneClasses.ORDER:
		var paths := TaxiRoutes.phase_paths(p, ends, plane_class, TaxiRoutes.north_only(p))
		for state in STATES:
			var old := _old_path(state, "", plane_class)
			var why := "one stand %s state %d" % [plane_class, state]
			assert_int(old.size()).override_failure_message(why).is_greater(1)
			assert_array(Array(paths[state])).override_failure_message(why).is_equal(Array(old))
			var drawn := _airside.phase_path(state, "", plane_class)
			assert_array(Array(drawn)).override_failure_message(why).is_equal(Array(old))
			compared += 1
	print("compared %d one-stand phase paths" % compared)
	assert_int(compared).is_equal(3 * 6)


## A fallback gate east of TaxiEast (G and on) is off the lane: Airside refuses
## its stand and draws no taxi route, while TaxiRoutes still gives FlightGround
## a route, one that runs on east past the lane's end (the plan for a stand the
## airside cannot have). Control: gate F is on the lane.
func test_a_fallback_gate_off_the_lane_is_refused_by_the_airside() -> void:
	var p := FlightGround.points()
	var layout := TaxiRoutes.north_only(p)
	var off := 0
	for letter in FlightGround.LETTERS:
		var ends := TaxiRoutes.stand_ends(FlightGround.fallback(letter)["stand"])
		if not TaxiRoutes.joins_lane(ends["join"], layout):
			off += 1
	print("fallback gates off the lane: %d of %d" % [off, FlightGround.LETTERS.length()])
	assert_int(off).is_equal(FlightGround.LETTERS.length() - _lane_gates().size())
	var stand: Dictionary = FlightGround.fallback("G")["stand"]
	assert_bool(_airside.set_gate_stands({"G": stand})).is_false()
	assert_int(_airside.phase_path(FlightSim.State.TAXI_IN, "G").size()).is_equal(0)
	assert_int(_airside.phase_path(FlightSim.State.TAXI_OUT, "G").size()).is_equal(0)
	var planned: PackedVector3Array = FlightGround.routes(stand, PlaneClasses.MEDIUM)[
		FlightSim.State.TAXI_IN
	]
	print("gate G planned taxi in: %s" % planned)
	assert_float(planned[2].x).is_greater(planned[1].x)
	var control: Dictionary = FlightGround.fallback("F")["stand"]
	assert_bool(_airside.set_gate_stands({"F": control})).is_true()
	assert_int(_airside.phase_path(FlightSim.State.TAXI_IN, "F").size()).is_equal(5)
	assert_bool(_airside.set_gate_stands({})).is_true()


## With every lane gate set at once, the drawn path of each gate, phase and
## class is the one FlightGround plans, the other gates' joins left out.
func test_with_every_fallback_gate_set_the_drawn_path_is_the_planned_one() -> void:
	var stands := {}
	for gate in _lane_gates():
		stands[gate] = FlightGround.fallback(gate)["stand"]
	assert_bool(_airside.set_gate_stands(stands)).is_true()
	var compared := 0
	for gate: String in stands:
		for plane_class in PlaneClasses.ORDER:
			var planned := FlightGround.routes(stands[gate], plane_class)
			for state in STATES:
				var drawn := _airside.phase_path(state, gate, plane_class)
				(
					assert_array(Array(drawn))
					. override_failure_message("gate %s %s state %d" % [gate, plane_class, state])
					. is_equal(Array(planned[state]))
				)
				compared += 1
	assert_bool(_airside.set_gate_stands({})).is_true()
	print("compared %d drawn and planned phase paths" % compared)
	assert_int(compared).is_equal(6 * 3 * 6)
