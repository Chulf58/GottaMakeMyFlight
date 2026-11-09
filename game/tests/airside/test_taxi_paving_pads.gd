class_name TestTaxiPavingPads
extends GdUnitTestSuite
## TaxiPaving's stand pads and hold bars (board items R10 and 6a1833b8). A pad is
## sized for the classes up to its gate's max_class (Airside.set_gate_classes()),
## and follows it when it changes. At every
## legal stand of the north and south rows, every class model parked door-aligned
## sits on paving from nose to tail and wingtip to wingtip, and through taxi in,
## pushback and taxi out its nose and its own origin (the main gear's stand-in)
## stay on paving, as FlightPose poses them on main.tscn's airside. The tail and
## wingtips are left out while taxiing: at the lane's corners the rigidly turned
## tail of a large plane swings over the grass beside the strips, in the air.
## Hold bars lie across the stubs at HoldIn and HoldRunway and across each lead-in
## whose pushback ends far enough south.

const MAIN_SCENE := "res://main/main.tscn"
const SITE := preload("res://build/terminal_site.tres")
const GROUND: Array[int] = [
	FlightSim.State.TAXI_IN, FlightSim.State.PUSHBACK, FlightSim.State.TAXI_OUT
]
## The pose a ground state starts from is the end of the move before it.
const PREVIOUS_MOVE := {
	FlightSim.State.TAXI_IN: FlightSim.State.LANDING,
	FlightSim.State.PUSHBACK: FlightSim.State.TAXI_IN,
	FlightSim.State.TAXI_OUT: FlightSim.State.PUSHBACK,
}
## Progress steps sampled through each ground state, and the parked footprint's
## sample spacing in metres.
const POSE_STEPS := 400
const FOOTPRINT_STEP_M := 1.0
## The runway's asphalt (main.tscn: pieces from x -192 to 192, 64 m wide about
## the centreline), paving of its own where taxi in starts and taxi out ends.
const RUNWAY := Rect2(-192.0, StandPlacement.RUNWAY_Z - 32.0, 384.0, 64.0)

var _airside: Airside
var _grid: BuildGrid


## The real Airside markers from main.tscn's saved state, as test_taxi_paving.gd
## builds them.
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
	_grid = BuildGrid.new(SITE.grid_size, SITE.grid_origin)


func after() -> void:
	_airside.free()


func after_test() -> void:
	_airside.set_gate_stands({})
	_airside.set_gate_classes({})


## Gate A on `stand` with a large max_class, as GateDesks gives a gate whose whole
## large envelope is clear.
func _large_gate(stand: Dictionary) -> bool:
	_airside.set_gate_classes({"A": PlaneClasses.LARGE})
	return _airside.set_gate_stands({"A": stand})


## Stands out from north-facing exits on the grid's north row (wall z -210) and
## south row, at its west edge, middle and east edge, each legal on the empty
## grid: the plane's sweep is clear and every class's tail clears the lane band.
func _legal_stands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in [0, SITE.grid_size.y - 1]:
		for column in [0, SITE.grid_size.x / 2, SITE.grid_size.x - 1]:
			var stand := StandPlacement.for_cell(_grid, Vector2i(column, row))
			assert_bool(StandPlacement.aircraft_clear(_grid, SITE, stand)).is_true()
			for plane_class in PlaneClasses.ORDER:
				assert_bool(StandEnvelope.clears_lane(stand, plane_class)).is_true()
			out.append(stand)
	return out


## Every FOOTPRINT_STEP_M point of `model`'s parked footprint at `stand_point`
## that is off the paving.
func _footprint_off(stand_point: Vector3, model: String) -> Array[Vector3]:
	var rect := TaxiPaving.parked_footprint(stand_point, model)
	var off: Array[Vector3] = []
	var nx := ceili(rect.size.x / FOOTPRINT_STEP_M)
	var nz := ceili(rect.size.y / FOOTPRINT_STEP_M)
	for i in nx + 1:
		for k in nz + 1:
			var at := Vector3(
				rect.position.x + rect.size.x * i / nx, 0.0, rect.position.y + rect.size.y * k / nz
			)
			if not TaxiPaving.paved(_airside.paving.shown, _airside.paving.pads, at):
				off.append(at)
	return off


## The points of `model` posed at `pose` that a ground state checks: its nose and
## its own origin, and in PUSHBACK its tail too, which swings at the stand.
func _model_points(pose: Transform3D, model: String, state: int) -> Array[Vector3]:
	var shape: Dictionary = PlaneModels.PLANES[model]
	var offset := PlaneClasses.stand_offset(model)
	var out: Array[Vector3] = [pose * (offset + Vector3(0, 0, shape["nose"])), pose * offset]
	if state == FlightSim.State.PUSHBACK:
		out.append(pose * (offset - Vector3(0, 0, shape["tail"])))
	return out


## {"sampled": points checked, "off": "model state point" for each off the paving}
## over gate `gate`'s ground states, for each of `models` (every model by default).
func _ground_off(gate: String, models: Array = PlaneModels.PLANES.keys()) -> Dictionary:
	var sampled := 0
	var off: Array[String] = []
	for state in GROUND:
		var path := _airside.phase_path(state, gate)
		var entry := FlightPose.exit_dir(_airside.phase_path(PREVIOUS_MOVE[state], gate))
		for step in POSE_STEPS + 1:
			var pose := FlightPose.pose(state, float(step) / POSE_STEPS, path, entry)
			for model: String in models:
				for at in _model_points(pose, model, state):
					sampled += 1
					if RUNWAY.has_point(Vector2(at.x, at.z)):
						continue
					if not TaxiPaving.paved(_airside.paving.shown, _airside.paving.pads, at):
						off.append("%s state %d at %s" % [model, state, at])
	return {"sampled": sampled, "off": off}


func test_every_class_parks_on_paving_at_every_legal_stand_nose_to_tail() -> void:
	var checked := 0
	for stand in _legal_stands():
		assert_bool(_large_gate(stand)).is_true()
		var at := StandPlacement.stand_point(stand)
		assert_int(_airside.paving.pads.size()).is_equal(1)
		print("stand %s pad %s" % [stand, _airside.paving.pads[0]])
		for model: String in PlaneModels.PLANES:
			var off := _footprint_off(at, model)
			(
				assert_array(off)
				. override_failure_message("%s at %s: off the paving %s" % [model, stand, off])
				. is_empty()
			)
			checked += 1
		# The pad reaches the wall line the stand faces, where a north-row stand's
		# site paving starts.
		assert_float(_airside.paving.pads[0].end.y).is_equal_approx(float(stand["wall_z"]), 0.001)
	assert_int(checked).is_equal(6 * PlaneModels.PLANES.size())


func test_the_north_row_model_07_and_05_noses_are_paved_to_the_site() -> void:
	var stand := StandPlacement.for_cell(_grid, Vector2i(SITE.grid_size.x / 2, 0))
	assert_float(float(stand["wall_z"])).is_equal_approx(SITE.grid_origin.z, 0.001)
	assert_bool(_large_gate(stand)).is_true()
	var at := StandPlacement.stand_point(stand)
	# The route's own strips, as before the pads: the link stops at the stand
	# point. The shown strips run on over the pad to the wall line
	# (TaxiPaving.run_on_to_walls()), so they are paved there because of the pad.
	var route_strips := TaxiPaving.strips(_airside.taxi_routes(), StandPlacement.TAXI_LANE_Z)
	for model in ["tp_plane_05a", "tp_plane_07a"]:
		var rect := TaxiPaving.parked_footprint(at, model)
		var nose := Vector3(rect.get_center().x, 0.0, rect.end.y)
		print("%s north-row nose %s, tail z %.2f" % [model, nose, rect.position.y])
		# Before the pads only the link to the stand point was paved: the nose half
		# lay on grass.
		assert_bool(TaxiPaving.covers(route_strips, nose)).is_false()
		assert_bool(TaxiPaving.paved(_airside.paving.shown, _airside.paving.pads, nose)).is_true()
		var between := Vector3(nose.x, 0.0, (at.z + nose.z) / 2.0)
		assert_bool(TaxiPaving.covers(route_strips, between)).is_false()
		(
			assert_bool(TaxiPaving.paved(_airside.paving.shown, _airside.paving.pads, between))
			. is_true()
		)


func test_a_small_class_pad_leaves_a_large_tail_on_grass() -> void:
	# A control: the footprint check fails when the pad leaves a class out.
	var at := StandPlacement.stand_point(StandPlacement.for_cell(_grid, Vector2i(43, 0)))
	var small: Array[String] = [PlaneClasses.SMALL]
	var pad := TaxiPaving.stand_pad(at, small)
	var large := TaxiPaving.parked_footprint(at, "tp_plane_07a")
	print("small pad %s, model 07 footprint %s" % [pad, large])
	assert_bool(pad.encloses(large)).is_false()
	assert_bool(TaxiPaving.stand_pad(at).encloses(large)).is_true()
	assert_bool(TaxiPaving.stand_pad(at).encloses(pad)).is_true()


func test_a_small_gate_gets_a_small_pad_that_still_holds_its_small_planes() -> void:
	var stand := StandPlacement.for_cell(_grid, Vector2i(SITE.grid_size.x / 2, 0))
	var at := StandPlacement.stand_point(stand)
	_airside.set_gate_classes({"A": PlaneClasses.SMALL})
	assert_bool(_airside.set_gate_stands({"A": stand})).is_true()
	assert_int(_airside.paving.pads.size()).is_equal(1)
	var pad: Rect2 = _airside.paving.pads[0]
	var small: Array[String] = [PlaneClasses.SMALL]
	print("small gate pad %s" % pad)
	assert_object(pad).is_equal(TaxiPaving.stand_pad(at, small))
	# It holds the small swing square and every small model parked, nose to tail.
	var swing := StandEnvelope.rects(stand, PlaneClasses.SMALL)[0]
	assert_bool(pad.grow(TaxiPaving.SAME_M).encloses(swing)).is_true()
	var small_models: Array = PlaneClasses.CLASSES[PlaneClasses.SMALL]["models"]
	for model: String in small_models:
		assert_array(_footprint_off(at, model)).is_empty()
	var rolling := _ground_off("A", small_models)
	print("small gate: sampled %d, off %s" % [rolling["sampled"], rolling["off"]])
	assert_int(rolling["sampled"]).is_greater(3 * POSE_STEPS * 2)
	assert_array(rolling["off"]).is_empty()
	# It paves none of the medium swing square, where the player may still build.
	var medium := StandEnvelope.rects(stand, PlaneClasses.MEDIUM)[0]
	assert_bool(pad.encloses(medium)).is_false()
	assert_float(pad.size.x).is_less(medium.size.x)


func test_the_pad_follows_a_change_of_max_class() -> void:
	var stand := StandPlacement.for_cell(_grid, Vector2i(SITE.grid_size.x / 2, 0))
	var at := StandPlacement.stand_point(stand)
	assert_bool(_large_gate(stand)).is_true()
	var large: Rect2 = _airside.paving.pads[0]
	_airside.set_gate_classes({"A": PlaneClasses.MEDIUM})
	var medium: Rect2 = _airside.paving.pads[0]
	_airside.set_gate_classes({"A": PlaneClasses.SMALL})
	var small: Rect2 = _airside.paving.pads[0]
	print("pads large %s medium %s small %s" % [large, medium, small])
	assert_object(large).is_equal(TaxiPaving.stand_pad(at, Airside.classes_up_to("large")))
	assert_object(medium).is_equal(TaxiPaving.stand_pad(at, Airside.classes_up_to("medium")))
	assert_bool(large.encloses(medium) and medium.encloses(small)).is_true()
	assert_float(large.get_area()).is_greater(medium.get_area())
	assert_float(medium.get_area()).is_greater(small.get_area())
	# The mesh is rebuilt with it, and a gate with no class gets no pad.
	var verts: int = _airside.paving.mesh.surface_get_array_len(0)
	_airside.set_gate_classes({"A": ""})
	assert_array(_airside.paving.pads).is_empty()
	assert_int(_airside.paving.mesh.surface_get_array_len(0)).is_equal(verts - 4)


func test_every_class_rolls_on_paving_through_taxi_in_pushback_and_taxi_out() -> void:
	for stand in _legal_stands():
		assert_bool(_large_gate(stand)).is_true()
		var result := _ground_off("A")
		print("stand %s: sampled %d, off %s" % [stand, result["sampled"], result["off"]])
		assert_int(result["sampled"]).is_greater(3 * POSE_STEPS * PlaneModels.PLANES.size() * 2)
		assert_array(result["off"]).is_empty()


func test_the_one_stand_has_a_pad_and_rolls_on_paving() -> void:
	assert_int(_airside.paving.pads.size()).is_equal(1)
	var at := _airside.graph.position_of(&"Stand")
	assert_object(_airside.paving.pads[0]).is_equal(TaxiPaving.stand_pad(at))
	var result := _ground_off("")
	print("one stand: sampled %d, off %s" % [result["sampled"], result["off"]])
	assert_array(result["off"]).is_empty()


func test_hold_bars_lie_across_the_stubs_and_south_lead_ins() -> void:
	var north := StandPlacement.for_cell(_grid, Vector2i(10, 0))
	var south := StandPlacement.for_cell(_grid, Vector2i(70, SITE.grid_size.y - 1))
	assert_bool(_airside.set_gate_stands({"A": north, "B": south})).is_true()
	var holds := _airside.hold_points()
	print("holds %s" % [holds])
	# HoldIn, HoldRunway and the south gate's lead-in: the north row has none.
	assert_int(holds.size()).is_equal(3)
	assert_vector(holds[0]).is_equal(_airside.graph.position_of(&"HoldIn"))
	assert_vector(holds[1]).is_equal(_airside.graph.position_of(&"HoldRunway"))
	var back := StandPlacement.pushback_end(south)
	assert_float(holds[2].x).is_equal_approx(back.x, 0.001)
	assert_float(holds[2].z).is_between(StandPlacement.TAXI_LANE_Z, back.z)
	assert_array(Airside.lead_in_hold(StandPlacement.pushback_end(north))).is_empty()
	# A plane heading north stopped on it keeps every model's nose south of the
	# lane band.
	for model: String in PlaneModels.PLANES:
		var reach: float = PlaneClasses.stand_offset(model).z + PlaneModels.PLANES[model]["nose"]
		assert_float(holds[2].z - reach).is_greater_equal(StandEnvelope.lane_band_south() - 0.001)
	var bars := _airside.paving.bars
	assert_int(bars.size()).is_equal(2 * holds.size())
	for i in holds.size():
		for bar in [bars[2 * i], bars[2 * i + 1]]:
			assert_float(bar.size.x).is_equal_approx(TaxiPaving.WIDTH_M, 0.001)
			assert_float(bar.size.y).is_equal_approx(TaxiPaving.HOLD_LINE_M, 0.001)
			# The bar lies on its leg's strip, corner to corner.
			for corner in [bar.position, bar.end]:
				var point := Vector3(corner.x, 0.0, corner.y)
				assert_bool(TaxiPaving.covers(_airside.paving.shown, point)).is_true()
		assert_float(bars[2 * i + 1].position.y - bars[2 * i].end.y).is_equal_approx(
			TaxiPaving.HOLD_GAP_M, 0.001
		)
	# The lead-in bar is centred on its hold line.
	assert_float((bars[4].position.y + bars[5].end.y) / 2.0).is_equal_approx(holds[2].z, 0.001)
	# HoldIn and HoldRunway lie under the runway's asphalt (64 m wide about z
	# -338), which would hide a bar, so theirs sit HOLD_GAP_M south of its edge.
	var edge := Airside.runway_south()
	print("runway asphalt south edge z %.2f, stub bars %s %s" % [edge, bars[0], bars[2]])
	assert_float(edge).is_equal_approx(StandPlacement.RUNWAY_Z + 32.0, 0.001)
	assert_float(holds[0].z).is_less(edge)
	for i in [0, 2]:
		assert_float(bars[i].position.y).is_equal_approx(edge + TaxiPaving.HOLD_GAP_M, 0.001)


func test_pads_and_bars_are_in_the_mesh_under_and_over_the_strips() -> void:
	var strip_list: Array[Dictionary] = [{"rect": Rect2(-10, -20, 30, 40), "across_x": true}]
	var pad_list: Array[Rect2] = [Rect2(-40, -10, 80, 50)]
	var bar_list := TaxiPaving.hold_bars(PackedVector3Array([Vector3(5, 0, 0)]))
	var mesh := TaxiPaving.mesh_of(strip_list, bar_list, pad_list)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# One pad, one strip and two bar lines.
	assert_int(verts.size()).is_equal(16)
	assert_int(index.size()).is_equal(24)
	for i in 4:
		assert_float(verts[i].y).is_equal_approx(
			TaxiPaving.HEIGHT_M - TaxiPaving.PAD_DROP_M, 0.0001
		)
		assert_vector(uvs[i]).is_equal_approx(
			Vector2(TaxiPaving.ASPHALT_U, TaxiPaving.ASPHALT_V_FROM), Vector2(0.00001, 0.00001)
		)
		assert_float(verts[i].y).is_greater(-0.1)
	for i in range(8, 16):
		assert_float(verts[i].y).is_equal_approx(
			TaxiPaving.HEIGHT_M + TaxiPaving.LINE_LIFT_M, 0.0001
		)
		assert_vector(uvs[i]).is_equal_approx(TaxiPaving.MARKING_UV, Vector2(0.00001, 0.00001))
	for t in range(0, index.size(), 3):
		var a := verts[index[t]]
		assert_float((verts[index[t + 1]] - a).cross(verts[index[t + 2]] - a).y).is_less(0.0)
