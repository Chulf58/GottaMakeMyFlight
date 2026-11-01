extends "res://spike/landside_pull_in_strip_probe.gd"
## Windowed strips of the surface car park (lot spot 0) in the real main.tscn, board
## 297c9eb8: its lanes cross the sidewalk on its top and a paved apron
## (TP_Parking_01A_Apron) joins the sidewalk to the lot, so wheels and walkers stay on
## paving. It reuses the pull-in probe's boot, camera, collider and proof helpers and
## runs only its own stages.
##
## Run (one windowed Godot run project-wide; this probe holds the slot while it runs):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/landside_surface_lot_strip_probe.gd
##
## main.tscn boots with a random sim seed (printed; replay with `-- --seed=<n>`), the
## starter terminal and two staff, and lot spot 0 is built. Three strips go to
## tools/blender/out/car-park-lot0/, eight frames each (a STRIP_TILE tile around the
## subject, four a row):
## - a car on the access lane from the road over the sidewalk and the apron to the
##   gate, side-on from the west;
## - a car leaving the lot along the exit lane over the apron and the sidewalk to the
##   road, side-on from the east (a parked car's leave tick brought in as a fixture);
## - a stand-in walker on a stall's walk (LandsidePaths.lot_walk) from the gate over
##   the apron, the sidewalk, the road and the far kerb onto the far sidewalk, with
##   the cars hidden, the camera following it.
## Every frame proves the subject inside its tile and hit by camera rays, else
## PROBE_INVALID. In every car frame a ray down at each axle meets the surface within
## 3 cm (between the heights either side at a kerb) and not the lawn; in every walker
## frame a ray down at its feet does the same. Controls: the car rises onto the
## sidewalk top on both lanes, some car frames stand on the apron, and walker frames
## stand on both sidewalks and on the apron.

const LOT_OUT_REL := "res://../tools/blender/out/car-park-lot0"
const SURFACE := 0
const APRON_NAME := "TP_Parking_01A_Apron"
## Side-on and low from the west of the access lane (x 28) across the sidewalk.
const IN_EYE := Vector3(17.5, 1.1, -40.6)
const IN_TARGET := Vector3(28.0, 0.4, -40.6)
const IN_FROM := Vector3(28.0, 0.1, -43.0)
const IN_TO := Vector3(28.0, 0.1, -37.9)
## Side-on and low from the east of the exit lane (x 35.4), past the road's east end.
const OUT_EYE := Vector3(45.5, 1.1, -40.6)
const OUT_TARGET := Vector3(35.4, 0.4, -40.6)
const OUT_TO := Vector3(35.4, 0.1, -43.0)
## Where on the walk the walker frames are taken: by the gate, on the apron, on the
## sidewalk, at its kerb, on the road, at the far kerb, on the far sidewalk, the end.
const WALK_STATIONS: Array[Vector3] = [
	Vector3(26.5, 0.1, -37.85),
	Vector3(25.0, 0.1, -39.0),
	Vector3(25.0, 0.2, -40.6),
	Vector3(25.0, 0.15, -41.25),
	Vector3(25.0, 0.1, -48.0),
	Vector3(25.0, 0.15, -58.67),
	Vector3(25.0, 0.2, -59.6),
	Vector3(25.0, 0.2, -60.45),
]
## The walker camera, from the walker: west, toward the road and up.
const WALK_CAM := Vector3(-5.5, 3.2, -4.0)
const WAIT_TICKS := 20000

var _lot_dir := ""


func _run() -> void:
	_lot_dir = ProjectSettings.globalize_path(LOT_OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_lot_dir)
	print("PROBE lot_dir=", _lot_dir)
	await _boot()
	if not _landside.build_lot(SURFACE):
		_invalid("the surface lot could not be built")
	else:
		_views.draw()
		await _plate_lot_in()
	if not _failed:
		await _plate_lot_out()
	if not _failed:
		await _plate_lot_walk()
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


## Steps until a drawn car is on the surface lot's access lane no further than
## `before_mm` along it; its id, or 0.
func _await_lot_access(before_mm: int) -> int:
	_stage = "wait lot access"
	while _clock.tick < TICK_LIMIT:
		_tick()
		for id in _landside.vehicle_ids():
			var v := _landside.get_vehicle(id)
			if (
				v.lane == LandsideVehicle.Lane.ACCESS
				and v.lot == SURFACE
				and v.pos_mm <= before_mm
				and _views.has_vehicle(id)
			):
				return id
		if _clock.tick % 200 == 0:
			_beat("wait lot access %d" % _clock.tick)
			await process_frame
	return 0


## A car on the access lane from the road before the sidewalk to the gate.
func _plate_lot_in() -> void:
	var access := _landside.definition.lots[SURFACE].access
	var from_mm := LandsideDefinition.mm_along(access, IN_FROM)
	var to_mm := LandsideDefinition.mm_along(access, IN_TO)
	var id := await _await_lot_access(from_mm - 3000)
	if id == 0:
		_invalid("no car came onto the surface lot's access lane by tick %d" % TICK_LIMIT)
		return
	var v := _landside.get_vehicle(id)
	while v.pos_mm < from_mm and _clock.tick < TICK_LIMIT:
		_tick()
	print("LOT_IN vehicle=%d lane %d..%d mm" % [id, from_mm, to_mm])
	await _place_camera("lot_in", IN_EYE, IN_TARGET)
	var gap := float(to_mm - from_mm) / LandsideSim.SPEED_MM / float(FRAMES - 1)
	await _car_strip("lot_in", id, gap, LandsideVehicle.Lane.ACCESS, "surface_lot_in_strip.png")


## A parked car leaves (a fixture: its leave tick brought in) and drives along the
## exit lane over the apron and the sidewalk onto the road.
func _plate_lot_out() -> void:
	var id := 0
	var guard := 0
	while id == 0 and guard < WAIT_TICKS:
		for vid in _landside.vehicle_ids():
			var w := _landside.get_vehicle(vid)
			if id == 0 and w.lot == SURFACE and w.stage == LandsideVehicle.Stage.PARKED:
				id = vid
		if id == 0:
			_tick()
			guard += 1
			if guard % 200 == 0:
				_beat("wait parked %d" % guard)
				await process_frame
	if id == 0:
		_invalid("no car parked in the surface lot within %d ticks" % WAIT_TICKS)
		return
	var v := _landside.get_vehicle(id)
	v.leave_tick = _clock.tick
	guard = 0
	while v.lane != LandsideVehicle.Lane.LOT_EXIT and guard < WAIT_TICKS:
		_tick()
		guard += 1
		if guard % 200 == 0:
			_beat("wait exit %d" % guard)
			await process_frame
	if v.lane != LandsideVehicle.Lane.LOT_EXIT:
		_invalid("vehicle %d never reached the exit lane (lane %d)" % [id, v.lane])
		return
	var exit := _landside.definition.lots[SURFACE].exit
	var to_mm := LandsideDefinition.mm_along(exit, OUT_TO)
	print("LOT_OUT vehicle=%d slot=%d from %d mm to %d mm" % [id, v.stop, v.pos_mm, to_mm])
	await _place_camera("lot_out", OUT_EYE, OUT_TARGET)
	var gap := float(to_mm - v.pos_mm) / LandsideSim.SPEED_MM / float(FRAMES - 1)
	await _car_strip("lot_out", id, gap, LandsideVehicle.Lane.LOT_EXIT, "surface_lot_out_strip.png")


## Eight frames of car `id` on `lane`, `gap` ticks apart, from the fixed camera: each
## in its tile, hit by camera rays, both axles on the surface. Controls: the car rose
## onto the sidewalk top, and a frame had a wheel on the apron.
func _car_strip(label: String, id: int, gap: float, lane: int, file: String) -> void:
	var v := _landside.get_vehicle(id)
	var strip := Image.create(STRIP_TILE.x * 4, STRIP_TILE.y * 2, false, Image.FORMAT_RGBA8)
	var highest := -INF
	var on_apron := 0
	var exclude: Array[RID] = []
	for i in FRAMES:
		if i > 0:
			_advance(gap)
		_views.draw()
		var node := _views.node_for(id)
		if node == null or v.lane != lane:
			_invalid("%s frame %d: vehicle %d left the lane (lane %d)" % [label, i, id, v.lane])
			return
		print(
			(
				"%s_STRIP frame=%d tick=%d pos_mm=%d at=%s pitch=%.3f"
				% [
					label.to_upper(),
					i,
					_clock.tick,
					v.pos_mm,
					node.global_position,
					node.global_basis.z.y
				]
			)
		)
		highest = maxf(highest, node.global_position.y)
		var crop := _tile_around(_aabb_of(node).get_center())
		if not _prove_in_frame("%s/frame %d" % [label, i], _aabb_of(node), Rect2(crop)):
			return
		await physics_frame
		await physics_frame
		if not _prove_visible("%s/frame %d" % [label, i], node):
			return
		if not _prove_wheels("%s/frame %d" % [label, i], node):
			return
		exclude = _bodies_of(node)
		var axles: Vector2 = node.get_meta(&"axles")
		for axle: float in [axles.x, axles.y]:
			var wheel := node.global_transform * Vector3(0.0, 0.0, axle)
			on_apron += int(_ground_at(wheel, exclude)[1] == APRON_NAME)
		var img := await _grab()
		strip.blit_rect(img, crop, Vector2i((i % 4) * STRIP_TILE.x, floori(i / 4.0) * STRIP_TILE.y))
	print("%s highest car origin %.3f, wheels on the apron %d" % [label, highest, on_apron])
	if highest < 0.15:
		_invalid("%s: the car never rose onto the sidewalk (highest %.3f)" % [label, highest])
	if on_apron < 1:
		_invalid("%s: no wheel stood on the apron" % label)
	if not _failed:
		_save(strip, file, _lot_dir)


## A stand-in walker on stall 0's walk from the gate to the far sidewalk, at the
## WALK_STATIONS, the camera following it. The cars are hidden for the plate.
func _plate_lot_walk() -> void:
	var lot := _landside.definition.lots[SURFACE]
	var walk := PackedVector3Array(_landside.paths.lot_walk(SURFACE, 0))
	var gate := walk.find(lot.access[lot.access.size() - 1])
	if gate < 0:
		_invalid("the surface lot walk does not pass the gate: %s" % [walk])
		return
	var route := PackedVector3Array(walk.slice(gate))
	print("LOT_WALK route %s" % [route])
	var hidden: Array[Node3D] = []
	for id in _landside.vehicle_ids():
		var car := _views.node_for(id)
		if car != null and car.visible:
			car.visible = false
			hidden.append(car)
	print("LOT_WALK hid %d vehicles" % hidden.size())
	var walker := MeshInstance3D.new()
	walker.name = "ProbeWalker"
	var capsule := CapsuleMesh.new()
	capsule.radius = WALKER_RADIUS
	capsule.height = WALKER_HEIGHT
	walker.mesh = capsule
	_main.add_child(walker)
	var strip := Image.create(STRIP_TILE.x * 4, STRIP_TILE.y * 2, false, Image.FORMAT_RGBA8)
	var on_sidewalk := 0
	var on_apron := 0
	for i in WALK_STATIONS.size():
		var at := LandsideDefinition.point_on(
			route, LandsideDefinition.mm_along(route, WALK_STATIONS[i])
		)
		var off := at.distance_to(WALK_STATIONS[i])
		if off > 0.05:
			_invalid("walk station %s is %.2f m off the walk" % [WALK_STATIONS[i], off])
			break
		walker.global_position = at + Vector3.UP * (WALKER_HEIGHT / 2.0)
		await _place_camera("lot_walk %d" % i, at + WALK_CAM, at + Vector3.UP * 0.8)
		print("LOT_WALK_STRIP frame=%d at=%s" % [i, at])
		var crop := _tile_around(at + Vector3.UP)
		if not _prove_in_frame("lot_walk/frame %d" % i, _aabb_of(walker), Rect2(crop)):
			break
		if not _prove_visible("lot_walk/frame %d" % i, walker):
			break
		var feet := _surface_check(
			"lot_walk/frame %d feet" % i, at, Vector3(0, 0, 1), _bodies_of(walker)
		)
		if not feet[0]:
			_invalid("lot walk frame %d: the walker is not on paving at %s" % [i, at])
			break
		on_sidewalk += int(absf(at.y - 0.2) < 0.005)
		on_apron += int(_ground_at(at, _bodies_of(walker))[1] == APRON_NAME)
		var img := await _grab()
		strip.blit_rect(img, crop, Vector2i((i % 4) * STRIP_TILE.x, floori(i / 4.0) * STRIP_TILE.y))
	walker.free()
	for car in hidden:
		car.visible = true
	print("LOT_WALK frames on a sidewalk top %d, on the apron %d" % [on_sidewalk, on_apron])
	if not _failed and (on_sidewalk < 3 or on_apron < 2):
		_invalid("lot walk: %d sidewalk and %d apron frames" % [on_sidewalk, on_apron])
	if not _failed:
		_save(strip, "surface_lot_walk_strip.png", _lot_dir)
