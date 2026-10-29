class_name TestLandsideDefinition
extends GdUnitTestSuite
## The starter road keeps right (user correction 2026-10-29: "Cars are
## driving in the wrong side"): every lane stretch along the road keeps the
## centre line on the car's left, so cars in to the curb drive west on the
## near (terminal-side) carriageway with the curb on their right, and cars
## out of the car park drive east on the far one. A vehicle faces the way it
## drives. A lane flipped to the left side is refused.

const STARTER := preload("res://landside/starter_landside.tres")


## Every along-road segment of every lane, as [name, from, to].
func _along_road() -> Array:
	var lanes := {"road_in": STARTER.road_in, "road_out": STARTER.road_out}
	for i in STARTER.lots.size():
		lanes["access %d" % i] = STARTER.lots[i].access
		lanes["exit %d" % i] = STARTER.lots[i].exit
	var out := []
	for lane_name in lanes:
		var points: PackedVector3Array = lanes[lane_name]
		for i in range(1, points.size()):
			var d := points[i] - points[i - 1]
			if absf(d.x) > absf(d.z):
				out.append([lane_name, points[i - 1], points[i]])
	return out


func test_every_lane_along_the_road_keeps_the_centre_line_on_the_left() -> void:
	assert_str(STARTER.problem()).is_equal("")
	var checked := 0
	for segment in _along_road():
		var d: Vector3 = (segment[2] - segment[1]).normalized()
		# Godot: forward is -Z, right is +X, so left of (dx, 0, dz) is (dz, 0, -dx).
		var left := Vector3(d.z, 0.0, -d.x)
		var middle: Vector3 = (segment[1] + segment[2]) * 0.5
		var to_centre := Vector3(0.0, 0.0, STARTER.centre_line_z - middle.z)
		print(
			(
				"%s from %s to %s: centre on the left %s"
				% [segment[0], segment[1], segment[2], left.dot(to_centre) > 0.0]
			)
		)
		assert_float(left.dot(to_centre)).is_greater(0.0)
		checked += 1
	assert_int(checked).is_equal(STARTER.lots.size() + 2)


func test_the_near_carriageway_runs_west_with_the_curb_on_the_right() -> void:
	var d := (STARTER.road_in[1] - STARTER.road_in[0]).normalized()
	var right := Vector3(-d.z, 0.0, d.x)
	assert_float(d.x).is_less(0.0)
	assert_float(STARTER.road_in[0].z).is_less(STARTER.centre_line_z)
	for berth in STARTER.curb.berths:
		assert_float(right.dot(berth - STARTER.road_in[0])).is_greater(0.0)


func test_a_vehicle_faces_the_way_it_drives() -> void:
	var sim: LandsideSim = auto_free(LandsideSim.new())
	assert_bool(sim.use_definition(STARTER)).is_true()
	var bookings: Array[int] = [1]
	var v := sim.get_vehicle(
		sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.DROP, bookings)
	)
	var rng := RandomNumberGenerator.new()
	for t in range(1, 40):
		sim.step(t, true, rng)
	var before := sim.world_position(v)
	sim.step(40, true, rng)
	var moved := (sim.world_position(v) - before).normalized()
	print("moved %s heading %s" % [moved, sim.heading(v)])
	assert_float(moved.dot(sim.heading(v))).is_greater(0.99)


func test_a_lane_on_the_wrong_side_is_refused() -> void:
	var flipped: LandsideDefinition = STARTER.duplicate(true)
	var reversed := PackedVector3Array()
	for i in range(flipped.road_out.size() - 1, -1, -1):
		reversed.append(flipped.road_out[i])
	flipped.road_out = reversed
	print(flipped.problem())
	assert_str(flipped.problem()).contains("road_out segment 0 drives on the left")
