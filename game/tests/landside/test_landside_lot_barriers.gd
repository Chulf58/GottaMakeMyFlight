class_name TestLandsideLotBarriers
extends GdUnitTestSuite
## Board 00291df0 point 1 (user ruling 2026-11-03, "Animate near cars"): the
## surface car park's barrier arms (TP_Parking_01A_Entry_Barrier and _Exit_Barrier,
## hinged at their posts on the gate line) lift as a car comes close on its way
## through and drop after it has passed. View only: the sim and the save do not
## change. The arms follow the cars once per sim tick (LandsideViews.sync, which
## SimClock.ticked drives), so at 3x speed, with one frame every three ticks, a
## car still never meets a closed arm (anti-pattern a-view-that-reacts-to-moving-
## sim-objects-must-check-them-on), and a load puts each arm where the loaded cars
## want it at once (anti-pattern a-per-id-view-record-holding-a-sim-tick-must-
## start-over-on-l). A bare LandsideSim on the starter road with the surface lot
## built, stepped by hand, and a LandsideViews with no clock, synced after each
## tick as the clock's signal does. Every check reads the drawn arm meshes.

const STARTER := preload("res://landside/starter_landside.tres")
const SURFACE := 0
const MULTI := 1
const ENTRY := "TP_Parking_01A_Entry_Barrier"
const EXIT := "TP_Parking_01A_Exit_Barrier"
## The arms pivot 1.5 m up and are 6.9 m long: a closed arm's top is under this,
## a raised arm's over it.
const UP_Y := 4.0
## A car's body counts as under an arm within this of the arm's line, past its ends.
const UNDER_SLACK := 0.3
const LIMIT := 3000
## Ticks run after the car has passed, for the arm to come down.
const AFTER_TICKS := 60

var _rng := RandomNumberGenerator.new()
var _sim: LandsideSim
var _views: LandsideViews
var _t := 1
## Arm name -> its drawn box at rest (closed), in the landside's frame.
var _rest := {}


func before_test() -> void:
	_rng.seed = 9
	_sim = auto_free(LandsideSim.new())
	assert_bool(_sim.use_definition(STARTER)).is_true()
	_sim.wallet = Wallet.new()
	assert_bool(_sim.build_lot(SURFACE)).is_true()
	_views = LandsideViews.new()
	_views.landside = _sim
	add_child(_views)
	_t = 1
	_rest.clear()
	for arm in [ENTRY, EXIT]:
		_rest[arm] = _arm_box(arm)


func after_test() -> void:
	_views.free()


func _car(booking: int) -> int:
	var bookings: Array[int] = [booking]
	return _sim.add_vehicle(LandsideVehicle.Kind.CAR, LandsideVehicle.Intent.PARK, bookings)


func _tick() -> void:
	_sim.step(_t, true, _rng)
	_t += 1
	_views.sync()


## The drawn arm's meshes' box in the landside's frame (LandsidePlaces' children).
func _arm_box(arm: String) -> AABB:
	var lot := _views.places().lot_node(SURFACE)
	var node: Node3D = lot.find_child(arm, true, false)
	var box := AABB()
	var first := true
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for mi: MeshInstance3D in meshes:
		var t := Transform3D()
		var n: Node = mi
		while n != _views.places():
			t = (n as Node3D).transform * t
			n = n.get_parent()
		var part: AABB = t * mi.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


## Whether vehicle `id`'s body (its drawn box along its nose) is under the arm
## as it stands closed: inside the arm's span across the lane, and reaching the
## arm's line.
func _under(id: int, arm: String) -> bool:
	var v := _sim.get_vehicle(id)
	if v == null or not _views.has_vehicle(id):
		return false
	var box: AABB = _views.node_for(id).get_meta(&"box")
	var half := maxf(absf(box.position.z), absf(box.end.z))
	var at := _sim.world_position(v)
	var rest: AABB = _rest[arm]
	var line_z := rest.get_center().z
	return (
		at.x >= rest.position.x and at.x <= rest.end.x and absf(at.z - line_z) <= half + UNDER_SLACK
	)


## Steps tick by tick until `done` holds, then AFTER_TICKS more, drawing a frame
## every `frame_every` ticks. On every drawn frame: each arm's top and whether the
## car is under it. Returns per arm {"under": frames under it, "up_under": of those
## with the arm raised, "rising": frames with the arm between closed and raised,
## "max": its highest top, "last": its top on the last frame}, and "ticks".
func _drive(id: int, done: Callable, frame_every: int) -> Dictionary:
	var out := {"ticks": 0}
	for arm in [ENTRY, EXIT]:
		out[arm] = {"under": 0, "up_under": 0, "rising": 0, "max": -INF, "last": 0.0}
	var after := -1
	while _t < LIMIT and after < AFTER_TICKS:
		_tick()
		out["ticks"] += 1
		if after >= 0:
			after += 1
		elif done.call():
			after = 0
		if out["ticks"] % frame_every != 0:
			continue
		_views.draw()
		for arm in [ENTRY, EXIT]:
			var top := _arm_box(arm).end.y
			var rest_top: float = (_rest[arm] as AABB).end.y
			var log: Dictionary = out[arm]
			log["max"] = maxf(log["max"], top)
			log["last"] = top
			log["rising"] += int(top > rest_top + 0.2 and top < UP_Y)
			if _under(id, arm):
				log["under"] += 1
				log["up_under"] += int(top > UP_Y)
	return out


func test_both_arms_stand_closed_with_no_car_near() -> void:
	for i in 20:
		_tick()
	_views.draw()
	for arm in [ENTRY, EXIT]:
		var box := _arm_box(arm)
		print("%s at rest %s, after 20 ticks %s" % [arm, _rest[arm], box])
		assert_float(box.end.y).is_less(2.0)
		assert_vector(box.end).is_equal_approx((_rest[arm] as AABB).end, Vector3.ONE * 0.001)
	# A control: the arms span the lanes on the gate line (z -37.5), entry over
	# the access lane at x 28 and exit over the exit lane at x 35.4.
	var entry: AABB = _rest[ENTRY]
	var exit: AABB = _rest[EXIT]
	assert_float(entry.position.x).is_less(28.0)
	assert_float(entry.end.x).is_greater(28.0)
	assert_float(exit.position.x).is_less(35.4)
	assert_float(exit.end.x).is_greater(35.4)
	assert_float(entry.get_center().z).is_equal_approx(-37.5, 0.1)


## A car turning in: the entry arm is fully up on every frame its body is under
## the arm, rose over several frames before (not a snap), and is down again after
## the car has parked. The exit arm stays closed.
func test_the_entry_arm_lifts_as_a_car_comes_in_and_drops_after_it() -> void:
	var id := _car(1)
	var v := _sim.get_vehicle(id)
	var found := _drive(id, func() -> bool: return v.stage == LandsideVehicle.Stage.PARKED, 1)
	print("in: %s" % found)
	var entry: Dictionary = found[ENTRY]
	var exit: Dictionary = found[EXIT]
	assert_int(v.stage).is_equal(LandsideVehicle.Stage.PARKED)
	# Control: the car's body was under the arm on several ticks.
	assert_int(entry["under"]).is_greater_equal(5)
	assert_int(entry["up_under"]).is_equal(entry["under"])
	assert_int(entry["rising"]).is_greater_equal(6)
	assert_float(entry["max"]).is_greater(UP_Y)
	assert_float(entry["last"]).is_less(2.0)
	assert_float(exit["max"]).is_less(2.0)


## The parked car leaves: the exit arm is up on every frame its body is under it
## and down again once it is gone; the entry arm stays closed.
func test_the_exit_arm_lifts_as_a_car_leaves_and_drops_after_it() -> void:
	var id := _car(1)
	var v := _sim.get_vehicle(id)
	while _t < LIMIT and v.stage != LandsideVehicle.Stage.PARKED:
		_tick()
	for i in AFTER_TICKS:
		_tick()
	v.leave_tick = _t
	var found := _drive(id, func() -> bool: return _sim.get_vehicle(id) == null, 1)
	print("out: %s" % found)
	var entry: Dictionary = found[ENTRY]
	var exit: Dictionary = found[EXIT]
	assert_object(_sim.get_vehicle(id)).is_null()
	assert_int(exit["under"]).is_greater_equal(5)
	assert_int(exit["up_under"]).is_equal(exit["under"])
	assert_int(exit["rising"]).is_greater_equal(6)
	assert_float(exit["last"]).is_less(2.0)
	assert_float(entry["max"]).is_less(2.0)


## At 3x speed one frame is drawn every three ticks: the arm still stands up on
## every drawn frame the car is under it, because it follows the ticks, not the
## frames.
func test_at_three_times_speed_a_car_never_meets_a_closed_arm() -> void:
	var id := _car(1)
	var v := _sim.get_vehicle(id)
	var found := _drive(id, func() -> bool: return v.stage == LandsideVehicle.Stage.PARKED, 3)
	print("3x: %s" % found)
	var entry: Dictionary = found[ENTRY]
	assert_int(entry["under"]).is_greater_equal(2)
	assert_int(entry["up_under"]).is_equal(entry["under"])
	assert_float(entry["last"]).is_less(2.0)


## A load draws each arm where the loaded cars want it at once: closed after
## loading back to an empty lot while a car was under the arm, and up after
## loading a save with a car under it.
func test_a_load_puts_each_arm_where_the_loaded_cars_want_it_at_once() -> void:
	var empty := _save()
	var id := _car(1)
	var v := _sim.get_vehicle(id)
	while _t < LIMIT and not _under(id, ENTRY):
		_tick()
	for i in 3:
		_tick()
	_views.draw()
	var up := _arm_box(ENTRY).end.y
	assert_bool(_under(id, ENTRY)).is_true()
	assert_int(v.lane).is_not_equal(LandsideVehicle.Lane.ROAD_IN)
	# Its passenger's flight closed on the way in, so the save lists no booking.
	_sim.drop_booking(id, 1)
	var under := _save()
	assert_bool(_sim.from_snapshot(empty, ArrivalBookings.new())).is_true()
	_views.snap()
	var after_empty := _arm_box(ENTRY).end.y
	assert_bool(_sim.from_snapshot(under, ArrivalBookings.new())).is_true()
	_views.snap()
	var after_under := _arm_box(ENTRY).end.y
	print(
		(
			"entry top: car under %.2f, loaded empty %.2f, loaded under %.2f"
			% [up, after_empty, after_under]
		)
	)
	assert_float(up).is_greater(UP_Y)
	assert_float(after_empty).is_less(2.0)
	assert_float(after_under).is_greater(UP_Y)


## The multi-storey has no barrier arms; building it leaves the surface lot's arms
## as they are and draws nothing else.
func test_the_multi_storey_has_no_arms_to_lift() -> void:
	assert_bool(_sim.build_lot(MULTI)).is_true()
	for i in 5:
		_tick()
	_views.draw()
	var multi := _views.places().lot_node(MULTI)
	assert_object(multi).is_not_null()
	assert_array(multi.find_children("*_Barrier", "Node3D", true, false)).is_empty()
	assert_float(_arm_box(ENTRY).end.y).is_less(2.0)


## The JSON text of the sim's save part, as a save file holds it.
func _save() -> Dictionary:
	return JSON.parse_string(JSON.stringify(_sim.to_snapshot(ArrivalBookings.new(), _t - 1)))
