class_name TestLandsideViewsHeading
extends GdUnitTestSuite
## Every drawn car and taxi faces its right-hand direction of travel
## (decision landside-traffic-drives-on-the-right-the-terminal-side-carri):
## on road_in and road_out it heads -x on the terminal-side carriageway, on a
## lot's access lane +z, in a curb berth -x, in a parking slot into its
## stall (away from the lot's middle aisle), and on the lot exit's stretch
## along the far carriageway +x. Moving between two ticks, on a lane or a
## berth's or slot's path, the model's nose (local +Z) points along the way it
## is drawn moving, except backing out of a stall, where it points back. A bare
## LandsideSim on the starter road with both car parks and curb spot 0 built,
## stepped by hand; the views sync after each step. Built once for the file.

const STEPS := 1200
## Cars handed in on these ticks: [kind, intent].
const ARRIVALS := {
	1: [LandsideVehicle.Kind.TAXI, LandsideVehicle.Intent.DROP],
	2: [LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK],
	30: [LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.DROP],
	31: [LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK],
	32: [LandsideVehicle.Kind.TAXI, LandsideVehicle.Intent.DROP],
	33: [LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.DROP],
	34: [LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.DROP],
	50: [LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK],
}
## The surface lot (spot 0) closes on this tick, after car 2 turned into it, so
## the later parking cars go to the multi-storey (spot 1).
const CLOSE_SURFACE_TICK := 45
## The way a parked car faces, by lot spot and slot row x, written out from
## starter_landside.tres (not from LandsidePlaces): into the stall, away from
## the aisle. The surface lot's aisle runs along x 31.7, the multi-storey's
## slots stand west of its middle.
const PARKED_NOSE := {
	0: {24.85: Vector3(-1, 0, 0), 38.55: Vector3(1, 0, 0)},
	1: {-7.6: Vector3(-1, 0, 0)},
}
const PLACE_NAMES := {
	LandsideVehicle.Lane.BERTH: "berth",
	LandsideVehicle.Lane.SLOT: "slot",
	LandsideVehicle.Lane.ROAD_IN: "road_in",
	LandsideVehicle.Lane.ROAD_OUT: "road_out",
	LandsideVehicle.Lane.ACCESS: "access",
}
## A parked car leaves this many ticks after it parks (instead of 1-3 days).
const PARKED_TICKS := 20

var _landside: LandsideSim
var _views: LandsideViews
## Lane or place name -> how many vehicle-ticks were checked there.
var _covered := {}
## Each failure, as text.
var _wrong: Array[String] = []
var _moving_checked := 0
var _backing_checked := 0
var _peak_nodes := 0
var _children_at_peak := 0


func before() -> void:
	_landside = auto_free(LandsideSim.new())
	_landside.use_definition(preload("res://landside/starter_landside.tres"))
	_landside.wallet = Wallet.new()
	assert_bool(_landside.build_lot(0)).is_true()
	assert_bool(_landside.build_lot(1)).is_true()
	assert_bool(_landside.build_curb(0)).is_true()
	_views = LandsideViews.new()
	_views.landside = _landside
	add_child(_views)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var booking := 1
	for tick in range(1, STEPS + 1):
		if ARRIVALS.has(tick):
			var bookings: Array[int] = [booking]
			booking += 1
			_landside.add_vehicle(ARRIVALS[tick][0], ARRIVALS[tick][1], bookings)
		if tick == CLOSE_SURFACE_TICK:
			assert_bool(_landside.set_lot_closed(0, true)).is_true()
		_landside.step(tick, true, rng)
		for id in _landside.vehicle_ids():
			var v := _landside.get_vehicle(id)
			if v.stage == LandsideVehicle.Stage.PARKED and v.leave_tick > tick + PARKED_TICKS:
				v.leave_tick = tick + PARKED_TICKS
		_views.sync()
		_check_tick()
		if _views.vehicle_count() > _peak_nodes:
			_peak_nodes = _views.vehicle_count()
			_children_at_peak = _views.get_child_count()


func after() -> void:
	_views.free()


## Where each car is drawn on the tick now (alpha 1, on the place the sim has
## it) faces its place's way; between two ticks the nose points along the way
## it is drawn moving, except backing out of a stall, where it points back.
## (Until cars drove a berth's or slot's path, the place was read at alpha 0.5;
## now a car can be drawn on the lane it just left at that alpha.)
func _check_tick() -> void:
	for id in _landside.vehicle_ids():
		if not _views.has_vehicle(id):
			continue
		var v := _landside.get_vehicle(id)
		var pose := _views.pose_at(id, 1.0)
		var nose := pose.basis.z
		var place := _place_name(v, pose.origin)
		var want := _want(place)
		if place == "slot":
			place = "slot_lot%d" % v.lot
			want = _parked_nose(v.lot, pose.origin.x)
			if want == Vector3.ZERO:
				_wrong.append("slot at %s has no written-out nose" % pose.origin)
		_covered[place] = int(_covered.get(place, 0)) + 1
		if want != Vector3.ZERO and nose.dot(want) < 0.99:
			_wrong.append("%s vehicle %d nose %s want %s" % [place, id, nose, want])
		var mid := _views.pose_at(id, 0.5).basis.z
		var a := _views.pose_at(id, 0.45).origin
		var b := _views.pose_at(id, 0.55).origin
		var moved := b - a
		var same_heading := _views.pose_at(id, 0.45).basis.z.dot(_views.pose_at(id, 0.55).basis.z)
		if moved.length() > 0.01 and same_heading > 0.999:
			_moving_checked += 1
			var way := mid.dot(moved.normalized())
			if _backing(v):
				_backing_checked += 1
				way = -way
			if way < 0.99:
				_wrong.append("%s vehicle %d moves %s nose %s" % [place, id, moved, mid])


## Whether the car is drawn backing out of its stall halfway through the tick
## that just ran (a car on its slot path moves a full step a tick).
func _backing(v: LandsideVehicle) -> bool:
	if v.lane != LandsideVehicle.Lane.SLOT or v.stage != LandsideVehicle.Stage.LEAVE or v.stop < 0:
		return false
	return v.pos_mm - LandsideSim.SPEED_MM / 2 < _landside.paths.slot_back[v.lot][v.stop]


## PARKED_NOSE for the row at `x` of lot spot `lot`, or zero for none.
static func _parked_nose(lot: int, x: float) -> Vector3:
	var rows: Dictionary = PARKED_NOSE[lot]
	for row: float in rows:
		if absf(row - x) < 0.01:
			return rows[row]
	return Vector3.ZERO


func _place_name(v: LandsideVehicle, at: Vector3) -> String:
	# On a berth's or slot's path, pulling in or out: the motion check covers it.
	var standing := v.stage in [LandsideVehicle.Stage.DWELL, LandsideVehicle.Stage.PARKED]
	if v.lane in [LandsideVehicle.Lane.BERTH, LandsideVehicle.Lane.SLOT] and not standing:
		return "berth_path" if v.lane == LandsideVehicle.Lane.BERTH else "slot_path_lot%d" % v.lot
	if PLACE_NAMES.has(v.lane):
		return PLACE_NAMES[v.lane]
	# The lot exit runs -z to the far carriageway, then +x along it; on the
	# corner itself either heading is right.
	if absf(at.z - -45.0) > 0.01:
		return "exit_to_road"
	var corner: Vector3 = _landside.definition.lots[v.lot].exit[1]
	return "exit_far_carriageway" if at.x > corner.x + 0.01 else "exit_corner"


static func _want(place: String) -> Vector3:
	match place:
		"berth", "road_in", "road_out":
			return Vector3(-1, 0, 0)
		"access":
			return Vector3(0, 0, 1)
		"exit_far_carriageway":
			return Vector3(1, 0, 0)
		"exit_to_road":
			return Vector3(0, 0, -1)
	return Vector3.ZERO


func test_every_drawn_vehicle_faces_its_right_hand_direction_of_travel() -> void:
	print("covered %s moving_checked %d wrong %s" % [_covered, _moving_checked, _wrong])
	for place in [
		"road_in", "berth", "road_out", "access", "slot_lot0", "slot_lot1", "exit_to_road"
	]:
		assert_int(int(_covered.get(place, 0))).is_greater(0)
	assert_int(int(_covered.get("exit_far_carriageway", 0))).is_greater(0)
	for place in ["berth_path", "slot_path_lot0", "slot_path_lot1"]:
		assert_int(int(_covered.get(place, 0))).is_greater(0)
	assert_int(_moving_checked).is_greater(100)
	assert_int(_backing_checked).is_greater(0)
	assert_array(_wrong).is_empty()


func test_cars_leave_the_view_with_the_sim_and_their_nodes_are_reused() -> void:
	var children := _views.get_child_count()
	print(
		(
			"peak drawn %d, children then %d, after all left %d"
			% [_peak_nodes, _children_at_peak, children]
		)
	)
	assert_int(_peak_nodes).is_greater(1)
	assert_array(_landside.vehicle_ids()).is_empty()
	assert_int(_views.vehicle_count()).is_equal(0)
	# Car 9 takes the model car 3 drove (9 % 3 == 3 % 3), from the pool.
	var bookings: Array[int] = [99]
	var id := _landside.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.DROP, bookings)
	_landside.step(STEPS + 1, true, RandomNumberGenerator.new())
	_views.sync()
	assert_int(id).is_equal(9)
	assert_bool(_views.has_vehicle(id)).is_true()
	assert_bool(_views.node_for(id).visible).is_true()
	assert_str(String(_views.node_for(id).name)).is_equal("Vehicle9")
	assert_int(_views.get_child_count()).is_equal(children)
