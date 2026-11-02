class_name TestTaxiPaving
extends GdUnitTestSuite
## TaxiPaving paves every taxi route (user ruling pave-the-taxi-lane-and-the-
## link-from-each-stand-to-it-so-pla): one lane strip, one strip per other leg
## stopping at the lane's edge, and on main.tscn's airside every point of
## every ground route, sampled each metre, lies on a strip, for the one stand
## and for two gates 44 m apart.

const MAIN_SCENE := "res://main/main.tscn"
const LANE_Z := StandPlacement.TAXI_LANE_Z
## Two stands 44 m apart, as test_airside_gate_stands.gd uses.
const STAND_A := {"exit": 2, "x": -22.5, "wall_z": -98.0}
const STAND_B := {"exit": 4, "x": 21.5, "wall_z": -98.0}
const GROUND: Array[int] = [
	FlightSim.State.TAXI_IN, FlightSim.State.PUSHBACK, FlightSim.State.TAXI_OUT
]

var _airside: Airside


## The real Airside markers from main.tscn's saved state, as
## test_airside_gate_stands.gd builds them.
func before() -> void:
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	_airside = Airside.new()
	for i in state.get_node_count():
		var props := {}
		for k in state.get_node_property_count(i):
			props[state.get_node_property_name(i, k)] = state.get_node_property_value(i, k)
		if String(state.get_node_path(i, true)) == "./Airside":
			if state.get_node_type(i) == &"Marker3D":
				var marker := Marker3D.new()
				marker.name = state.get_node_name(i)
				marker.transform = props.get(&"transform", Transform3D.IDENTITY)
				_airside.add_child(marker)
		elif String(state.get_node_path(i)) == "./Airside":
			_airside.links = props[&"links"]
	add_child(_airside)


func after() -> void:
	_airside.free()


func after_test() -> void:
	_airside.set_gate_stands({})


## Every metre along `routes`, with the points that are off the paving.
func _uncovered(routes: Array[PackedVector3Array]) -> Dictionary:
	var sampled := 0
	var off: Array[Vector3] = []
	for route in routes:
		for i in range(1, route.size()):
			var a := route[i - 1]
			var b := route[i]
			var steps := maxi(1, ceili(a.distance_to(b)))
			for k in steps + 1:
				var at := a.lerp(b, float(k) / steps)
				sampled += 1
				if not TaxiPaving.covers(_airside.paving.shown, at):
					off.append(at)
	return {"sampled": sampled, "off": off}


func _gate_routes(gate: String) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	for state in GROUND:
		out.append(_airside.phase_path(state, gate))
	return out


func test_lane_is_one_strip_and_each_leg_stops_at_its_edge() -> void:
	var route := PackedVector3Array(
		[
			Vector3(30, 0, -310),
			Vector3(30, 0, LANE_Z),
			Vector3(-26, 0, LANE_Z),
			Vector3(-26, 0, -143.9),
			Vector3(-26, 0, -114.9),
		]
	)
	var back := PackedVector3Array(
		[Vector3(-26, 0, -143.9), Vector3(-26, 0, LANE_Z), Vector3(-132, 0, LANE_Z)]
	)
	var routes: Array[PackedVector3Array] = [route, back]
	var got := TaxiPaving.strips(routes, LANE_Z)
	print("strips %s" % [got])
	var half := TaxiPaving.WIDTH_M / 2.0
	assert_int(got.size()).is_equal(3)
	assert_object(got[0]["rect"]).is_equal(
		Rect2(-132 - half, LANE_Z - half, 162 + TaxiPaving.WIDTH_M, TaxiPaving.WIDTH_M)
	)
	assert_bool(got[0]["across_x"]).is_false()
	# The stand's leg: merged from the taxi-in, pushback and taxi-out legs, from
	# the lane's south edge to the stand.
	assert_object(got[1]["rect"]).is_equal(
		Rect2(-26 - half, LANE_Z + half, TaxiPaving.WIDTH_M, -114.9 - (LANE_Z + half))
	)
	# The runway's leg: from the runway's centreline to the lane's north edge.
	assert_object(got[2]["rect"]).is_equal(
		Rect2(30 - half, -310, TaxiPaving.WIDTH_M, LANE_Z - half + 310)
	)
	assert_bool(got[2]["across_x"]).is_true()


func test_mesh_has_one_upward_quad_per_strip_in_the_runway_asphalt() -> void:
	var strip_list: Array[Dictionary] = [
		{"rect": Rect2(-10, -20, 30, 40), "across_x": true},
		{"rect": Rect2(0, 0, 50, 30), "across_x": false},
	]
	var mesh := TaxiPaving.mesh_of(strip_list)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_int(verts.size()).is_equal(8)
	assert_int(index.size()).is_equal(12)
	assert_object(mesh.surface_get_material(0)).is_same(TaxiPaving.MATERIAL)
	for t in range(0, index.size(), 3):
		var a := verts[index[t]]
		var b := verts[index[t + 1]]
		var c := verts[index[t + 2]]
		# Clockwise seen from above: the right-handed cross product points down.
		assert_float((b - a).cross(c - a).y).is_less(0.0)
	for uv in uvs:
		assert_float(uv.x).is_equal_approx(TaxiPaving.ASPHALT_U, 0.00001)
	# The band runs across each strip: x for the first, z for the second.
	assert_float(uvs[0].y).is_equal_approx(TaxiPaving.ASPHALT_V_FROM, 0.00001)
	assert_float(uvs[1].y).is_equal_approx(TaxiPaving.ASPHALT_V_TO, 0.00001)
	assert_float(uvs[4].y).is_equal_approx(TaxiPaving.ASPHALT_V_FROM, 0.00001)
	assert_float(uvs[7].y).is_equal_approx(TaxiPaving.ASPHALT_V_TO, 0.00001)


func test_one_stand_routes_are_paved_everywhere() -> void:
	var routes := _airside.taxi_routes()
	var result := _uncovered(routes)
	print("one stand: sampled %d, off the paving %s" % [result["sampled"], result["off"]])
	assert_int(routes.size()).is_equal(3)
	assert_int(result["sampled"]).is_greater(300)
	assert_array(result["off"]).is_empty()


func test_two_gates_routes_are_paved_everywhere_and_follow_the_stands() -> void:
	assert_bool(_airside.set_gate_stands({"A": STAND_A, "B": STAND_B})).is_true()
	var routes := _airside.taxi_routes()
	var result := _uncovered(routes)
	print("two gates: sampled %d, off the paving %s" % [result["sampled"], result["off"]])
	assert_int(routes.size()).is_equal(6)
	assert_int(result["sampled"]).is_greater(600)
	assert_array(result["off"]).is_empty()
	for gate in ["A", "B"]:
		var path := _airside.phase_path(FlightSim.State.TAXI_IN, gate)
		assert_int(path.size()).is_greater(2)
		assert_bool(TaxiPaving.covers(_airside.paving.shown, path[path.size() - 1])).is_true()
	# The starter stand's leg (x -26) is not paved while gates have stands.
	var starter_leg := Vector3(-26 - TaxiPaving.WIDTH_M, 0, -225)
	assert_bool(TaxiPaving.covers(_airside.paving.shown, starter_leg)).is_false()
	var at_a := Vector3(StandPlacement.stand_point(STAND_A).x, 0, -225)
	var at_b := Vector3(StandPlacement.stand_point(STAND_B).x, 0, -225)
	assert_bool(TaxiPaving.covers(_airside.paving.shown, at_a)).is_true()
	assert_bool(TaxiPaving.covers(_airside.paving.shown, at_b)).is_true()


func test_paving_follows_a_stand_that_moves() -> void:
	assert_bool(_airside.set_gate_stands({"A": STAND_A})).is_true()
	var a_leg := Vector3(StandPlacement.stand_point(STAND_A).x, 0, -225)
	var b_leg := Vector3(StandPlacement.stand_point(STAND_B).x, 0, -225)
	assert_bool(TaxiPaving.covers(_airside.paving.shown, a_leg)).is_true()
	assert_bool(TaxiPaving.covers(_airside.paving.shown, b_leg)).is_false()
	assert_bool(_airside.set_gate_stands({"B": STAND_B})).is_true()
	assert_bool(TaxiPaving.covers(_airside.paving.shown, a_leg)).is_false()
	assert_bool(TaxiPaving.covers(_airside.paving.shown, b_leg)).is_true()
	assert_object(_airside.paving.mesh).is_not_null()
	assert_int((_airside.paving.mesh as ArrayMesh).get_surface_count()).is_equal(1)
