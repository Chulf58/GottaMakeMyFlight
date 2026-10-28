class_name TestSecurityLooks
extends GdUnitTestSuite
## How passengers at security look (Security 7/8, SecurityLooks and
## SecurityProps through PassengerViews): every lane phase maps to its tray,
## bag homes, facing and step; the basic scanner carries the bags and repacks
## on the floor; drawn passengers keep apart through the lane, a held queue
## front included; and the drawn spots clear the lane parts at every facing
## and mirror.

## A drawn body is about 0.4 m deep and 0.45 m wide at the shoulders.
const BODY_RADIUS := 0.22
const APART_M := 0.44

var _worlds: Array[SecurityTestWorld] = []
var _views: Array[PassengerViews] = []
var _lanes_were := false


func before() -> void:
	PassengerTestWorld.tracker = self
	_lanes_were = SecurityLanes.enabled
	SecurityLanes.enabled = true


func after() -> void:
	PassengerTestWorld.tracker = null
	SecurityLanes.enabled = _lanes_were


func after_test() -> void:
	for v in _views:
		v.free()
	_views.clear()
	for w in _worlds:
		w.world.free_all()
	_worlds.clear()


func _make(use_lane: bool) -> SecurityTestWorld:
	var w := SecurityTestWorld.make(use_lane)
	_worlds.append(w)
	var views := PassengerViews.new()
	views.clock = w.world.clock
	views.sim = w.world.sim
	add_child(views)
	_views.append(views)
	return w


## Steps until `ids` are cleared and returns, per id, phase -> what was seen:
## {"tray": {Tray: true}, "homes": {Home: true}, "face": Vector2, "step":
## Vector3, "pass": int (ARCH passes)}.
func _watch(w: SecurityTestWorld, ids: Array[int]) -> Dictionary:
	var seen := {}
	for id in ids:
		seen[id] = {}
	var sim := w.world.sim
	for i in 3000:
		w.world.step()
		for id in ids:
			var p := sim.get_passenger(id)
			if p.stage != Passenger.Stage.SECURITY:
				continue
			var key := "%d/%s" % [p.security_phase, p.incident_resolved]
			var entry: Dictionary = seen[id].get(key, {"tray": {}, "homes": {}})
			entry["tray"][SecurityLooks.tray(sim, p)] = true
			for home in SecurityLooks.bag_homes(sim, p):
				entry["homes"][home] = true
			entry["face"] = SecurityLooks.face(sim, p)
			entry["step"] = SecurityLooks.target_offset(sim, p)
			entry["bags_drawn"] = _views[-1].security_props().props_of(id)["bags"].size()
			seen[id][key] = entry
		if ids.all(func(id: int) -> bool: return w.cleared.has(id)):
			break
	return seen


func _lane(w: SecurityTestWorld) -> Dictionary:
	return w.world.sim.layout.security_lanes.lane(w.station)


func test_a_lane_shows_tray_unpack_ride_and_pickup() -> void:
	var w := _make(true)
	var ids := w.send_all([[2, false, false]])
	var seen: Dictionary = _watch(w, ids)[ids[0]]
	var lane := _lane(w)
	var side := SecurityLooks.world_dir(lane["side"]) * SecurityLooks.STEP_M
	print("lane phases seen: %s" % [seen])
	var unpack: Dictionary = seen["%d/false" % SecurityRuntime.Phase.UNPACK]
	assert_dict(unpack["tray"]).is_equal({SecurityLooks.Tray.IN: true})
	assert_dict(unpack["homes"]).contains_keys([SecurityLooks.Home.HAND, SecurityLooks.Home.TRAY])
	assert_that(unpack["face"]).is_equal(Vector2(lane["side"]))
	assert_that(unpack["step"]).is_equal(side)
	assert_int(unpack["bags_drawn"]).is_equal(2)
	var arch: Dictionary = seen["%d/false" % SecurityRuntime.Phase.ARCH]
	assert_dict(arch["tray"]).is_equal({SecurityLooks.Tray.RIDE: true})
	assert_dict(arch["homes"]).is_equal({SecurityLooks.Home.TRAY: true})
	var pickup: Dictionary = seen["%d/false" % SecurityRuntime.Phase.PICKUP]
	assert_dict(pickup["tray"]).is_equal({SecurityLooks.Tray.OUT: true})
	assert_dict(pickup["homes"]).contains_keys([SecurityLooks.Home.TRAY, SecurityLooks.Home.HAND])
	assert_that(pickup["face"]).is_equal(Vector2(lane["side"]))
	var leave: Dictionary = seen["%d/false" % SecurityRuntime.Phase.LEAVE]
	assert_dict(leave["tray"]).is_equal({SecurityLooks.Tray.NONE: true})
	assert_dict(leave["homes"]).is_equal({SecurityLooks.Home.HAND: true})


func test_an_alarm_steps_aside_repacks_on_the_floor_and_walks_back() -> void:
	var w := _make(true)
	var ids := w.send_all([[1, false, true]])
	var seen: Dictionary = _watch(w, ids)[ids[0]]
	var lane := _lane(w)
	print("alarm phases seen: %s" % [seen.keys()])
	for phase in [SecurityRuntime.Phase.TO_BERTH, SecurityRuntime.Phase.REPACK]:
		var entry: Dictionary = seen["%d/false" % phase]
		assert_dict(entry["tray"]).is_equal({SecurityLooks.Tray.NONE: true})
	var repack: Dictionary = seen["%d/false" % SecurityRuntime.Phase.REPACK]
	assert_dict(repack["homes"]).is_equal({SecurityLooks.Home.FLOOR: true})
	assert_that(repack["face"]).is_equal(-Vector2(lane["front"]))
	var back: Dictionary = seen["%d/true" % SecurityRuntime.Phase.RETURN]
	assert_dict(back["homes"]).is_equal({SecurityLooks.Home.HAND: true})
	# The second pass keeps the searched bag in hand and has no tray.
	var again: Dictionary = seen["%d/true" % SecurityRuntime.Phase.ARCH]
	assert_dict(again["tray"]).is_equal({SecurityLooks.Tray.NONE: true})
	assert_dict(again["homes"]).is_equal({SecurityLooks.Home.HAND: true})
	var pickup: Dictionary = seen["%d/true" % SecurityRuntime.Phase.PICKUP]
	assert_dict(pickup["tray"]).is_equal({SecurityLooks.Tray.NONE: true})


func test_the_basic_scanner_carries_the_bags_and_repacks_in_place() -> void:
	var w := _make(false)
	var ids := w.send_all([[2, false, true]])
	var seen: Dictionary = _watch(w, ids)[ids[0]]
	print("basic phases seen: %s" % [seen])
	var scan: Dictionary = seen["%d/false" % SecurityRuntime.Phase.SCAN]
	assert_dict(scan["tray"]).is_equal({SecurityLooks.Tray.NONE: true})
	assert_dict(scan["homes"]).is_equal({SecurityLooks.Home.HAND: true})
	assert_int(scan["bags_drawn"]).is_equal(2)
	var repack: Dictionary = seen["%d/false" % SecurityRuntime.Phase.REPACK]
	assert_dict(repack["homes"]).is_equal({SecurityLooks.Home.FLOOR: true})
	assert_that(repack["step"]).is_equal(Vector3.ZERO)


## Every tick, and halfway between ticks, the drawn passengers in the queue
## and the lane stay APART_M apart, and a drawn offset never moves faster than
## walking. Control: the queue front was held back on some ticks.
func test_drawn_passengers_keep_apart_through_the_lane() -> void:
	var w := _make(true)
	var views := _views[-1]
	var ids := w.send_all(
		[
			[2, false, false],
			[1, false, true],
			[0, false, false],
			[2, true, false],
			[1, false, false]
		]
	)
	var closest := INF
	var closest_at := ""
	var held_ticks := 0
	var fastest := 0.0
	var last := {}
	for i in 3000:
		w.world.step()
		var drawn := {}
		for id in ids:
			var p := w.world.passenger(id)
			if p.stage != Passenger.Stage.SECURITY and p.stage != Passenger.Stage.SECURITY_QUEUE:
				continue
			var before := views.tick_position(id, false)
			var now := views.tick_position(id, true)
			drawn[id] = [now, before.lerp(now, 0.5)]
			var offset := views.security_offset(id)
			if p.stage == Passenger.Stage.SECURITY_QUEUE and offset != Vector3.ZERO:
				held_ticks += 1
			if last.has(id):
				fastest = maxf(fastest, offset.distance_to(last[id]))
			last[id] = offset
		var keys := drawn.keys()
		for a in keys.size():
			for b in range(a + 1, keys.size()):
				for k in 2:
					var gap: float = (drawn[keys[a]][k] as Vector3).distance_to(drawn[keys[b]][k])
					if gap < closest:
						closest = gap
						closest_at = "tick %d ids %d,%d" % [w.world.sim.tick, keys[a], keys[b]]
		if ids.all(func(id: int) -> bool: return w.cleared.has(id)):
			break
	print(
		(
			"closest drawn pair %.3f m at %s; queue front held %d ticks; fastest offset step %.3f m"
			% [closest, closest_at, held_ticks, fastest]
		)
	)
	assert_bool(ids.all(func(id: int) -> bool: return w.cleared.has(id))).is_true()
	assert_int(held_ticks).is_greater(0)
	assert_float(closest).is_greater_equal(APART_M)
	assert_float(fastest).is_less_equal(PassengerSim.WALK_MM / 1000.0 + 0.0001)


## The spots a passenger stands on inside a lane keep a body's radius clear
## of the tray table, X-ray belt and pickup table (their kit bounds), at every
## facing and both mirrors. The arch is checked on the plates (its bounds
## enclose its opening).
func test_lane_spots_clear_the_parts_at_every_facing_and_mirror() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(12, 12))
	var worst := INF
	var worst_at := ""
	for facing in 4:
		for mirror in SecurityLanes.MIRRORS:
			var lane := SecurityLanes.geometry(Vector2i(5, 5), facing, mirror)
			lane["facing"] = facing
			var side := SecurityLooks.world_dir(lane["side"])
			var front := SecurityLooks.world_dir(lane["front"])
			var spots := {
				"unpack_step": grid.cell_to_world(lane["unpack"]) + side * SecurityLooks.STEP_M,
				"pickup_step": grid.cell_to_world(lane["pickup"]) + side * SecurityLooks.STEP_M,
				"queue_edge":
				grid.cell_to_world(lane["unpack"]) + front * SecurityLooks.QUEUE_EDGE_M,
				"berth": grid.cell_to_world(lane["berth"]),
				"exit": grid.cell_to_world(lane["exit"]),
				"arch_line": grid.cell_to_world(lane["arch"]),
			}
			for part in [
				SecurityLanes.TRAY_TABLE, SecurityLanes.XRAY_BELT, SecurityLanes.PICKUP_TABLE
			]:
				var cells: Array[Vector2i] = [lane[part]]
				var xf := BuildView.object_transform(grid, cells, facing)
				var box := _piece_box(part)
				for spot in spots:
					var gap := _gap(xf.affine_inverse() * spots[spot], box)
					if gap < worst:
						worst = gap
						worst_at = "facing %d mirror %d %s to %s" % [facing, mirror, spot, part]
	print("closest spot to a part %.3f m (%s)" % [worst, worst_at])
	assert_float(worst).is_greater_equal(BODY_RADIUS)


func _piece_box(piece: StringName) -> AABB:
	var node := InteriorKit.instantiate(piece)
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var b := mi.transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	node.free()
	return box


## Ground distance from a local point to a box's footprint (0 inside).
func _gap(at: Vector3, box: AABB) -> float:
	var dx := maxf(maxf(box.position.x - at.x, at.x - box.end.x), 0.0)
	var dz := maxf(maxf(box.position.z - at.z, at.z - box.end.z), 0.0)
	return Vector2(dx, dz).length()
