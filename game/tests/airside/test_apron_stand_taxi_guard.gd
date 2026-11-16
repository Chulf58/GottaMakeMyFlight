class_name TestApronStandTaxiGuard
extends GdUnitTestSuite
## The guard on a plane taxiing out (ApronStand.route_rects; slice S3 of design
## airside-all-around-technical-design-one-route-source-per-con): every grid
## cell under the plane stays guarded at north, west and east stands, for a
## large plane on the straight way out and for medium and large planes before,
## at and after the lane corner.
##
## Each case builds the plane's box on its own: centred on the route point,
## PlaneModels "length" / 2 ahead and behind and "half_span" either side,
## turned to MovementPlan.heading_at() there, as FlightPose draws a plane off
## the stand. It samples the box every STEP_M (INSET_M inside its edges, so a
## sliver cells_under() ignores is not asked for) and asks that every sampled
## cell is in the guarded cells. The grid covers the stands, the lanes and the
## corners: x -128 to 128, z -340 to -84.

const NORTH := {"exit": 2, "x": -22.5, "wall_z": -98.0}
const WEST := {"exit": 3, "x": 62.0, "wall_z": -150.0, "side": "W"}
const EAST := {"exit": 4, "x": -62.0, "wall_z": -150.0, "side": "E"}
const GRID_SIZE := Vector2i(256, 256)
const GRID_ORIGIN := Vector3(-128.0, 0.0, -340.0)
const STEP_M := 0.25
const INSET_M := 0.05
## Model 05 and 07 with their classes.
const PLANES := [["tp_plane_05a", "medium"], ["tp_plane_07a", "large"]]

var _grid: BuildGrid


func before() -> void:
	_grid = BuildGrid.new(GRID_SIZE, GRID_ORIGIN)


static func _stands() -> Array[Dictionary]:
	return [NORTH, WEST, EAST] as Array[Dictionary]


## The way out to the lane and on along it: west on the north lane, north up a
## side lane (where board airside-all-around-s4 puts the spurs).
static func _route(stand: Dictionary) -> PackedVector3Array:
	var join := StandPlacement.lane_join(stand)
	var along := Vector3(0.0, 0.0, -120.0)
	if StandPlacement.side_of(stand) == StandPlacement.NORTH:
		along = Vector3(-120.0, 0.0, 0.0)
	return PackedVector3Array([StandPlacement.pushback_end(stand), join, join + along])


static func _entry(stand: Dictionary) -> Vector3:
	return MovementPlan.flat_dir(
		StandPlacement.stand_point(stand), StandPlacement.pushback_end(stand)
	)


## The TAXI_OUT progress that puts the plane `distance` along `path` with no
## pause (MovementPlan.fraction() is a smoothstep), by bisection.
static func _progress(path: PackedVector3Array, distance: float) -> float:
	var total := MovementPlan.path_length(path)
	var low := 0.0
	var high := 1.0
	for i in 60:
		var mid := (low + high) / 2.0
		if total * smoothstep(0.0, 1.0, mid) < distance:
			low = mid
		else:
			high = mid
	return (low + high) / 2.0


## The grid cells under `model`'s box `distance` along `path`.
func _box_cells(
	path: PackedVector3Array, distance: float, model: String, entry: Vector3
) -> Dictionary:
	var at := MovementPlan.point_at(path, distance)
	var nose := MovementPlan.heading_at(path, distance, entry)
	var left := Vector3(nose.z, 0.0, -nose.x)
	var half_length: float = PlaneModels.PLANES[model]["length"] / 2.0 - INSET_M
	var half_span: float = PlaneModels.PLANES[model]["half_span"] - INSET_M
	var out := {}
	var along := -half_length
	while along <= half_length + 0.0001:
		var across := -half_span
		while across <= half_span + 0.0001:
			var cell := _grid.world_to_cell(at + nose * along + left * across)
			if _grid.in_bounds(cell):
				out[cell] = true
			across = minf(across + STEP_M, half_span) if across < half_span else INF
		along = minf(along + STEP_M, half_length) if along < half_length else INF
	return out


## How many cells under the plane `distance` along `stand`'s route are not
## guarded; prints the case. The plane must cover cells. With `ground_only`
## the plane's own box (route_rects()' last rectangle) is left out, so only
## the cut class ground is asked.
func _unguarded(stand: Dictionary, distance: float, plane: Array, ground_only := false) -> int:
	var path := _route(stand)
	var under := _box_cells(path, distance, plane[0], _entry(stand))
	var rects := ApronStand.route_rects(stand, path, _progress(path, distance), plane[0], plane[1])
	if ground_only:
		rects = rects.slice(0, rects.size() - 1)
	var guarded := StandPlacement.cells_under(_grid, rects)
	var missing := 0
	for cell: Vector2i in under:
		if not guarded.has(cell):
			missing += 1
	print(
		(
			"%s %s at %.1f m (corner at %.1f m): %d cells under it, %d not guarded"
			% [
				StandPlacement.side_of(stand),
				plane[0],
				distance,
				path[0].distance_to(path[1]),
				under.size(),
				missing
			]
		)
	)
	assert_int(under.size()).is_greater(100)
	return missing


## 24.35 m of a large plane's centred box lies behind its route point, 9.5 m
## past the old cut at the point plus StandPlacement.TAIL_M (14.85 m). On the
## straight the cut large envelope alone covers it, without the box.
func test_a_large_plane_on_the_straight_way_out_stays_guarded() -> void:
	var large: Array = PLANES[1]
	for stand in _stands():
		var corner := StandPlacement.pushback_end(stand).distance_to(
			StandPlacement.lane_join(stand)
		)
		for distance in [10.0, corner / 2.0, corner - 30.0]:
			assert_int(_unguarded(stand, distance, large, true)).is_equal(0)


func test_every_cell_under_the_plane_stays_guarded_through_the_lane_corner() -> void:
	for stand in _stands():
		var corner := StandPlacement.pushback_end(stand).distance_to(
			StandPlacement.lane_join(stand)
		)
		for plane: Array in PLANES:
			for offset in [-6.0, -2.0, 0.0, 2.0, 6.0, 25.0]:
				assert_int(_unguarded(stand, corner + offset, plane)).is_equal(0)


## Where the old cut covered the plane (a medium plane on the straight, its
## tail 14.62 m behind the point) the guard is the old one, value for value,
## plus the plane's own box.
func test_a_medium_plane_on_the_straight_keeps_the_old_cut() -> void:
	var path := _route(NORTH)
	var total := MovementPlan.path_length(path)
	for progress in [0.0, 0.1, 0.2, 0.3]:
		var at := MovementPlan.point_at(path, total * smoothstep(0.0, 1.0, progress))
		var old := StandPlacement.swept_rects(NORTH, at.z + StandPlacement.TAIL_M)
		var got := ApronStand.route_rects(NORTH, path, progress, "tp_plane_05a", "medium")
		print("progress %.1f: old %s, now %s" % [progress, old, got])
		assert_int(got.size()).is_equal(old.size() + 1)
		assert_array(got.slice(0, old.size())).is_equal(old)


static func _holds(rects: Array[Rect2], point: Vector3) -> bool:
	return rects.any(func(rect: Rect2) -> bool: return rect.has_point(Vector2(point.x, point.z)))


## Halfway down a west stand's way out the plane is 70 m west of its pushback
## end, on z -146.5. The guard has let go of the parked spot; a cut north of
## the tail's world z would keep it, as that way runs along z.
func test_a_west_stand_lets_go_of_the_parked_spot_a_world_z_cut_would_keep() -> void:
	var path := PackedVector3Array(
		[StandPlacement.pushback_end(WEST), StandPlacement.lane_join(WEST)]
	)
	var at := MovementPlan.point_at(path, MovementPlan.path_length(path) * 0.5)
	var spot := StandPlacement.stand_point(WEST)
	var got := ApronStand.route_rects(
		WEST, path, _progress(path, at.distance_to(path[0])), "tp_plane_05a", "medium"
	)
	var by_z: Array[Rect2] = []
	for rect in StandPlacement.swept_rects(WEST):
		var south := minf(rect.end.y, at.z + StandPlacement.TAIL_M)
		if south > rect.position.y:
			by_z.append(
				Rect2(rect.position.x, rect.position.y, rect.size.x, south - rect.position.y)
			)
	print("plane at %s, spot %s\nguard %s\nworld z cut %s" % [at, spot, got, by_z])
	assert_float(spot.x - at.x).is_greater(20.0)
	assert_bool(_holds(got, at)).is_true()
	assert_bool(_holds(got, spot)).is_false()
	assert_bool(_holds(by_z, spot)).is_true()
