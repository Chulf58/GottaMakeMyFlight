class_name TestTaxiPavingSpurs
extends GdUnitTestSuite
## TaxiPaving at west and east stands (board airside-all-around-s4): the west
## and east stubs run on south of the lane as the spurs, one strip each from
## under the runway to past the farthest stand connector, with the lane ending
## at the spur's inner edge and each connector a strip of its own east-west.
## The spur is mitred under the lane and the connectors (anti_pattern
## perpendicular-paving-strips-that-each-map-a-dark-edge-light), so its outer
## edge stays the band's dark edge all the way along. Side stand pads are the
## north twin's pad turned, every model parks on paving and rolls on it nose
## and origin, and the hold bars on the spur head and on each connector run
## north-south across their east-west legs.

## Synthetic side stands: west ones with the sill at (0, -149.5) and
## (-20, -109.5), an east one at (0, -129.5), grid rows 60, 100 and 80.
const WEST_SILL := Vector2(0.0, -149.5)
const WEST_FAR_SILL := Vector2(-20.0, -109.5)
const EAST_SILL := Vector2(0.0, -129.5)
const GROUND: Array[int] = [
	FlightSim.State.TAXI_IN, FlightSim.State.PUSHBACK, FlightSim.State.TAXI_OUT
]
const PREVIOUS_MOVE := {
	FlightSim.State.TAXI_IN: FlightSim.State.LANDING,
	FlightSim.State.PUSHBACK: FlightSim.State.TAXI_IN,
	FlightSim.State.TAXI_OUT: FlightSim.State.PUSHBACK,
}
const POSE_STEPS := 400
## The runway's asphalt, paving of its own (test_taxi_paving_pads.gd).
const RUNWAY := Rect2(-192.0, StandPlacement.RUNWAY_Z - 32.0, 384.0, 64.0)

var _airside: Airside


func before() -> void:
	_airside = TestStandLaneClearance.scene_airside()
	add_child(_airside)


func after() -> void:
	_airside.free()


func after_test() -> void:
	_airside.set_gate_stands({})
	_airside.set_gate_classes({})


static func _west(sill := WEST_SILL) -> Dictionary:
	return StandPlacement.make(0, sill.x, sill.y, StandPlacement.WEST)


static func _east() -> Dictionary:
	return StandPlacement.make(0, EAST_SILL.x, EAST_SILL.y, StandPlacement.EAST)


func _use_gates(stands: Dictionary) -> bool:
	var classes := {}
	for gate: String in stands:
		classes[gate] = PlaneClasses.LARGE
	_airside.set_gate_classes(classes)
	return _airside.set_gate_stands(stands)


static func _half() -> float:
	return TaxiPaving.WIDTH_M / 2.0


func _strip_at_x(x: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for strip in _airside.paving.shown:
		var rect: Rect2 = strip["rect"]
		if strip["across_x"] and absf(rect.get_center().x - x) < 0.01:
			out.append(strip)
	return out


## The spurs are the stubs run on: one north-south strip at each spur's x from
## under the runway past the farthest connector by half a strip, so the corner
## square there is paved; the lane strip ends at each spur's inner edge; each
## connector is one east-west strip from the spur's edge on to its stand's
## wall line.
func test_the_spurs_run_on_from_the_stubs_and_the_connectors_meet_them() -> void:
	assert_bool(_use_gates({"A": _west(), "B": _west(WEST_FAR_SILL), "C": _east()})).is_true()
	var half := _half()
	var spur_x := StandPlacement.SIDE_LANE_X
	var far_join := StandPlacement.lane_join(_west(WEST_FAR_SILL))
	var west := _strip_at_x(-spur_x)
	var east := _strip_at_x(spur_x)
	print("west column %s, east column %s" % [west, east])
	assert_int(west.size()).is_equal(1)
	assert_int(east.size()).is_equal(1)
	var west_rect: Rect2 = west[0]["rect"]
	assert_float(west_rect.position.y).is_equal_approx(StandPlacement.RUNWAY_Z, 0.01)
	assert_float(west_rect.end.y).is_equal_approx(far_join.z + half, 0.01)
	var east_rect: Rect2 = east[0]["rect"]
	var east_join := StandPlacement.lane_join(_east())
	assert_float(east_rect.end.y).is_equal_approx(east_join.z + half, 0.01)
	var lane: Rect2 = Rect2()
	var rows: Array[Rect2] = []
	for strip in _airside.paving.shown:
		var rect: Rect2 = strip["rect"]
		if strip["across_x"] or strip.has("quad"):
			assert_bool(strip.has("quad")).override_failure_message("%s" % strip).is_false()
			continue
		if absf(rect.get_center().y - StandPlacement.TAXI_LANE_Z) < 0.01:
			lane = rect
		else:
			rows.append(rect)
	print("lane %s, connectors %s" % [lane, rows])
	assert_float(lane.position.x).is_equal_approx(-spur_x + half, 0.01)
	assert_float(lane.end.x).is_equal_approx(spur_x - half, 0.01)
	assert_int(rows.size()).is_equal(3)
	for stand in [_west(), _west(WEST_FAR_SILL), _east()]:
		var join := StandPlacement.lane_join(stand)
		var found := false
		for rect in rows:
			if absf(rect.get_center().y - join.z) > 0.01:
				continue
			var x_from := rect.position.x if join.x < 0.0 else rect.end.x
			var x_to := rect.end.x if join.x < 0.0 else rect.position.x
			# From the spur's edge to the stand's sill, its wall line.
			assert_float(x_from).is_equal_approx(join.x + signf(-join.x) * half, 0.01)
			assert_float(x_to).is_equal_approx(float(stand["x"]), 0.01)
			found = true
		assert_bool(found).override_failure_message("no connector for %s" % stand).is_true()


## The spur's outer edge is the band's dark edge from end to end, through the
## lane's square and past each connector: every mesh vertex on that edge has
## the band's edge shade. Control: the spur's centre line has the light middle.
func test_the_spur_is_mitred_so_its_outer_edge_stays_dark() -> void:
	assert_bool(_use_gates({"A": _west(), "C": _east()})).is_true()
	var mesh := _airside.paving.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var outer := StandPlacement.SIDE_LANE_X + _half()
	var on_edge := 0
	var light := 0
	var middle := 0
	for i in verts.size():
		var at := verts[i]
		# Asphalt only: the centre lines carry the marking colour.
		if absf(uvs[i].x - TaxiPaving.ASPHALT_U) > 0.0001:
			continue
		var v := uvs[i].y
		var dark := (
			absf(v - TaxiPaving.ASPHALT_V_FROM) < 0.0001
			or absf(v - TaxiPaving.ASPHALT_V_TO) < 0.0001
		)
		if absf(absf(at.x) - StandPlacement.SIDE_LANE_X) < 0.01 and not dark:
			middle += 1
		if absf(absf(at.x) - outer) > 0.01:
			continue
		on_edge += 1
		if not dark:
			light += 1
			print("light vertex on the outer edge: %s uv %s" % [at, uvs[i]])
	print(
		(
			"outer-edge vertices %d, not dark %d; lighter on the centre lines %d"
			% [on_edge, light, middle]
		)
	)
	assert_int(on_edge).is_greater_equal(4)
	assert_int(light).is_equal(0)
	assert_int(middle).is_greater(0)


## A side stand's pad is its north twin's pad turned onto it (TaxiPaving.
## pad_for()), and a north stand's is stand_pad() as before.
func test_a_side_pad_is_the_north_twin_pad_turned() -> void:
	for stand in [_west(), _east()]:
		var twin := StandPlacement.north_twin(stand)
		var twin_pad := TaxiPaving.stand_pad(StandPlacement.stand_point(twin))
		var want := StandPlacement.rects_to_world(stand, [twin_pad] as Array[Rect2])[0]
		var got := TaxiPaving.pad_for(stand)
		print("%s pad %s" % [StandPlacement.side_of(stand), got])
		assert_object(got).is_equal(want)
		# The pad reaches the sill, the wall line the stand faces.
		var wall := (
			got.end.x if StandPlacement.side_of(stand) == StandPlacement.WEST else got.position.x
		)
		assert_float(wall).is_equal_approx(float(stand["x"]), 0.001)
	var north := StandPlacement.make(0, 10.0, -149.5)
	assert_object(TaxiPaving.pad_for(north)).is_equal(
		TaxiPaving.stand_pad(StandPlacement.stand_point(north))
	)


## Every model parks on paving at a west and an east stand (its turned
## footprint sampled every metre) and, through taxi in, pushback and taxi out,
## its nose and origin stay on it (the runway's own asphalt left out), as
## test_taxi_paving_pads.gd checks north stands.
func test_every_model_parks_and_rolls_on_paving_at_side_stands() -> void:
	var stands := {"A": _west(), "C": _east()}
	assert_bool(_use_gates(stands)).is_true()
	var sampled := 0
	var off: Array[String] = []
	for gate: String in stands:
		var stand: Dictionary = stands[gate]
		var twin := StandPlacement.north_twin(stand)
		for model: String in PlaneModels.PLANES:
			var rect := TaxiPaving.parked_footprint(StandPlacement.stand_point(twin), model)
			var turned := StandPlacement.rects_to_world(stand, [rect] as Array[Rect2])[0]
			for i in ceili(turned.size.x) + 1:
				for k in ceili(turned.size.y) + 1:
					var at := Vector3(
						minf(turned.position.x + i, turned.end.x),
						0.0,
						minf(turned.position.y + k, turned.end.y)
					)
					sampled += 1
					if not TaxiPaving.paved(_airside.paving.shown, _airside.paving.pads, at):
						off.append("%s parked %s" % [model, at])
		for state in GROUND:
			var path := _airside.phase_path(state, gate)
			assert_int(path.size()).is_greater(1)
			var entry := FlightPose.exit_dir(_airside.phase_path(PREVIOUS_MOVE[state], gate))
			for step in POSE_STEPS + 1:
				var pose := FlightPose.pose(state, float(step) / POSE_STEPS, path, entry)
				for model: String in PlaneModels.PLANES:
					var shape: Dictionary = PlaneModels.PLANES[model]
					var offset := PlaneClasses.stand_offset(model)
					for at in [pose * (offset + Vector3(0, 0, shape["nose"])), pose * offset]:
						sampled += 1
						if RUNWAY.has_point(Vector2(at.x, at.z)):
							continue
						if not TaxiPaving.paved(_airside.paving.shown, _airside.paving.pads, at):
							off.append("%s %s state %d at %s" % [gate, model, state, at])
	print("side stands: sampled %d, off %d %s" % [sampled, off.size(), off.slice(0, 6)])
	assert_int(sampled).is_greater(10000)
	assert_array(off).is_empty()


## The hold bars at a west stand: HoldIn and HoldRunway across the stubs as
## before, the west spur head across the lane and the connector's H_g across
## the connector, both running north-south on their strips.
func test_spur_head_and_connector_hold_bars_run_across_their_legs() -> void:
	var stand := _west()
	assert_bool(_use_gates({"A": stand})).is_true()
	var holds := _airside.hold_points()
	var head := Airside.spur_head_hold(StandPlacement.lane_join(stand))
	var gate := GroundPlanner.gate_hold(stand)
	print("holds %s, spur head %s, H_g %s" % [holds, head, gate])
	assert_int(holds.size()).is_equal(4)
	assert_bool(holds.has(head)).is_true()
	assert_bool(holds.has(gate)).is_true()
	var bars := _airside.paving.bars
	assert_int(bars.size()).is_equal(2 * holds.size())
	for i in holds.size():
		var across_z := holds[i] == head or holds[i] == gate
		for bar in [bars[2 * i], bars[2 * i + 1]]:
			var size := Vector2(bar.size.x, bar.size.y)
			var want := Vector2(TaxiPaving.HOLD_LINE_M, TaxiPaving.WIDTH_M)
			if not across_z:
				want = Vector2(want.y, want.x)
			(
				assert_vector(size)
				. override_failure_message("hold %s bar %s" % [holds[i], bar])
				. is_equal_approx(want, Vector2.ONE * 0.001)
			)
			for corner in [bar.position, bar.end]:
				var point := Vector3(corner.x, 0.0, corner.y)
				assert_bool(TaxiPaving.covers(_airside.paving.shown, point)).is_true()
