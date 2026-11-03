extends "res://spike/landside_pull_in_strip_probe.gd"
## Windowed strips of the three car park follow-ups in the real main.tscn (board
## 00291df0). It reuses the pull-in probe's boot, camera, collider and proof helpers
## and runs only its own stages.
##
## Run (one windowed Godot run project-wide; this probe holds the slot while it runs):
##   Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game \
##     -s res://spike/landside_carpark_followups_strip_probe.gd
##
## main.tscn boots with a random sim seed (printed; replay with `-- --seed=<n>`), the
## starter terminal and two staff. Strips go to tools/blender/out/carpark-followups/:
## - barrier_entry_strip.png: the surface lot (lot spot 0) built, a car on its way in
##   past the entry arm: closed with the car on the access lane, three frames lifting,
##   up with the car under it, three frames dropping behind it, closed. Each frame is
##   taken on the tick the arm's lift (LotBarriers) passes the frame's mark; the arm
##   and the car are proved inside the tile and hit by camera rays, and the car's
##   wheels on the surface. The frame with the car under the arm needs the arm up.
## - bay2_get_out_strip.png: curb bay 2 (curb spot 1) built, a real passenger who got
##   out there, side-on at true scale (orthographic, from the road between the taxi and
##   the kerb, looking across the kerb) beside a 1 m reference cube on the sidewalk:
##   eight frames a tick apart from the tick it got out. A ray down at its feet meets
##   the sidewalk's top within 3 cm.
## - carpark_walk_gate_to_crossing_strip.png: the multi-storey (lot spot 1) built and a
##   stand-in walker from its gate down the apron, along the sidewalk and onto the road
##   at the crossing, east of the planter bed (the pull-in probe's crossing stage).
## - planter_walk_still.png: a still over the planter bed with markers along the walk
##   and the walker at its turn onto the crossing at x -2.

const FOLLOWUPS_REL := "res://../tools/blender/out/carpark-followups"
const SURFACE := 0
const ENTRY := "TP_Parking_01A_Entry_Barrier"
## From the far sidewalk south-west of the gate, the whole way in in front of it.
const GATE_EYE := Vector3(10.0, 6.0, -64.0)
const GATE_TARGET := Vector3(28.0, 2.5, -40.0)
## Over the road south-east of the planter bed, looking down at it and the turn.
const PLANTER_EYE := Vector3(1.0, 5.0, -47.0)
const PLANTER_TARGET := Vector3(-2.5, 0.2, -40.6)
## The arm's lift marks for the frames: closed, lifting, up, dropping, closed.
const RISING: Array[float] = [0.0, 0.2, 0.55, 1.0]
const FALLING: Array[float] = [0.7, 0.4, 0.1, 0.0]
const ARM_UP_Y := 4.0
## Curb bay 2 is curb spot 1; its berths are the definition's berths 6 and 7.
const BAY_2 := 1
## The side camera stands on the road between the berth's car (its kerb-side flank
## at z -58.15 for a taxi, -58.3 for a van) and the kerb's slope (from z -58.5),
## looking at the passenger 0.95 m away.
const SIDE_EYE_Z := -58.45
const LOOK_Y := 0.9
const SIDE_SIZE := 4.8
const CUBE_OFF := 1.3
const SIDE_GAP_TICKS := 1
const WAIT_TICKS := 30000

var _dir := ""


func _run() -> void:
	_dir = ProjectSettings.globalize_path(FOLLOWUPS_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_dir)
	print("PROBE followups_dir=", _dir)
	await _boot()
	if not _landside.build_lot(SURFACE):
		_invalid("the surface lot could not be built")
	else:
		_views.draw()
		await _plate_barrier()
	if not _failed:
		if not _landside.build_curb(BAY_2):
			_invalid("curb bay 2 could not be built")
		else:
			await _plate_bay_2()
	if not _failed:
		if not _landside.build_lot(MULTI):
			_invalid("the multi-storey could not be built")
		else:
			_views.draw()
			_followup_dir = _dir
			await _plate_crossing_walk()
	if not _failed:
		await _plate_planter()
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _entry_lift() -> float:
	return _views.barriers().lift(SURFACE, ENTRY)


func _entry_arm() -> Node3D:
	return _views.places().lot_node(SURFACE).find_child(ENTRY, true, false)


## A car of the surface lot on its access lane with the entry arm closed; its id, or 0.
func _await_coming_in() -> int:
	_stage = "wait coming in"
	while _clock.tick < TICK_LIMIT:
		_tick()
		for id in _landside.vehicle_ids():
			var v := _landside.get_vehicle(id)
			if (
				v.lot == SURFACE
				and v.lane == LandsideVehicle.Lane.ACCESS
				and _entry_lift() == 0.0
				and _views.has_vehicle(id)
			):
				return id
		if _clock.tick % 200 == 0:
			_beat("wait coming in %d" % _clock.tick)
			await process_frame
	return 0


## Whether car `id`'s body reaches the entry arm's line (z of the arm's hinge).
func _under_entry(id: int) -> bool:
	var node := _views.node_for(id)
	if node == null:
		return false
	var box: AABB = node.get_meta(&"box")
	var half := maxf(absf(box.position.z), absf(box.end.z))
	return absf(node.global_position.z - _entry_arm().global_position.z) <= half


func _plate_barrier() -> void:
	var id := await _await_coming_in()
	if id == 0:
		_invalid("no car came onto the surface lot's access lane by tick %d" % TICK_LIMIT)
		return
	print("BARRIER vehicle=%d tick=%d" % [id, _clock.tick])
	await _place_camera("barrier", GATE_EYE, GATE_TARGET)
	var strip := Image.create(STRIP_TILE.x * 4, STRIP_TILE.y * 2, false, Image.FORMAT_RGBA8)
	var marks: Array[float] = RISING.duplicate()
	marks.append_array(FALLING)
	var guard := 0
	var under_frames := 0
	for i in marks.size():
		var mark: float = marks[i]
		var rising := i < RISING.size()
		# Step until the arm's lift passes the frame's mark (for the up frame, also
		# until the car is under the arm).
		while guard < WAIT_TICKS:
			var lift := _entry_lift()
			var reached := lift >= mark if rising else lift <= mark
			if i == 0:
				reached = true
			if mark == 1.0 and rising:
				reached = lift >= 1.0 and _under_entry(id)
			if reached:
				break
			_tick()
			_views.draw()
			guard += 1
			if guard % 200 == 0:
				_beat("barrier frame %d %d" % [i, guard])
				await process_frame
		_views.draw()
		var arm := _entry_arm()
		var car := _views.node_for(id)
		var lift_now := _entry_lift()
		var top := _aabb_of(arm).end.y
		print(
			(
				"BARRIER_STRIP frame=%d tick=%d mark=%.2f lift=%.2f arm_top=%.2f car=%s under=%s"
				% [
					i,
					_clock.tick,
					mark,
					lift_now,
					top,
					car.global_position if car != null else "gone",
					_under_entry(id)
				]
			)
		)
		var box := _aabb_of(arm)
		if car != null:
			box = box.merge(_aabb_of(car))
		var crop := _tile_around(box.get_center())
		if not _prove_in_frame("barrier/frame %d" % i, box, Rect2(crop)):
			return
		await physics_frame
		await physics_frame
		if not _prove_visible("barrier/frame %d arm" % i, arm):
			return
		if car != null and car.visible:
			if not _prove_wheels("barrier/frame %d" % i, car):
				return
		if _under_entry(id):
			under_frames += 1
			if top < ARM_UP_Y:
				_invalid("barrier frame %d: the car is under the arm and the arm is down" % i)
				return
		var img := await _grab()
		strip.blit_rect(img, crop, Vector2i((i % 4) * STRIP_TILE.x, floori(i / 4.0) * STRIP_TILE.y))
	if under_frames < 1:
		_invalid("no barrier frame had the car under the arm")
	if not _failed:
		_save(strip, "barrier_entry_strip.png", _dir)


## The first passenger who gets out at curb bay 2; its id, or 0.
func _await_bay_2_get_out() -> int:
	_stage = "wait bay 2"
	var sim: PassengerSim = _main.get_node("PassengerSim")
	var spot: LandsideCurbSpot = _landside.definition.curb_spots[BAY_2]
	var seen := {}
	for pid in sim.passenger_ids():
		seen[pid] = true
	var guard := 0
	while guard < WAIT_TICKS:
		_tick()
		guard += 1
		for pid in sim.passenger_ids():
			if seen.has(pid):
				continue
			seen[pid] = true
			var at := sim.world_position(sim.get_passenger(pid))
			for out in spot.get_out:
				if Vector2(at.x - out.x, at.z - out.z).length() < 0.3:
					print("BAY2 passenger=%d got out at %s (get-out %s)" % [pid, at, out])
					return pid
		if guard % 200 == 0:
			_beat("wait bay 2 %d" % guard)
			await process_frame
	return 0


func _plate_bay_2() -> void:
	var pid := await _await_bay_2_get_out()
	if pid == 0:
		_invalid("no passenger got out at curb bay 2 within %d ticks" % WAIT_TICKS)
		return
	var sim: PassengerSim = _main.get_node("PassengerSim")
	var views: PassengerViews = _main.get_node("PassengerViews")
	var start := sim.world_position(sim.get_passenger(pid))
	# The reference cube stands on the sidewalk beside the passenger, on the side it
	# does not walk to.
	var heading := views.walk_heading(sim.get_passenger(pid))
	var behind := -1.0 if heading.x > 0.0 else 1.0
	var cube := MeshInstance3D.new()
	cube.name = "ReferenceCube"
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE
	cube.mesh = box_mesh
	_main.add_child(cube)
	cube.global_position = Vector3(start.x + behind * CUBE_OFF, 0.2 + 0.5, start.z)
	# Orthographic at true scale, side-on: from between the car in the berth and the
	# kerb, looking across the kerb (its road-facing step in view) at the passenger.
	var look := Vector3(start.x - behind * 0.1, LOOK_Y, start.z)
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = SIDE_SIZE
	await _place_camera("bay2", Vector3(look.x, look.y, SIDE_EYE_Z), look)
	print("BAY2 heading %s cube at %s camera z %.2f" % [heading, cube.global_position, SIDE_EYE_Z])
	var strip := Image.create(STRIP_TILE.x * 4, STRIP_TILE.y * 2, false, Image.FORMAT_RGBA8)
	var on_top := 0
	for i in FRAMES:
		if i > 0:
			_advance(SIDE_GAP_TICKS)
		_views.draw()
		views.draw()
		var p := sim.get_passenger(pid)
		var node := views.node_for(pid)
		if p == null or node == null:
			_invalid("bay2 frame %d: passenger %d is not drawn" % [i, pid])
			break
		var feet := node.global_position
		print(
			(
				"BAY2_STRIP frame=%d tick=%d feet=%s sim=%s"
				% [i, _clock.tick, feet, sim.world_position(p)]
			)
		)
		var crop := _tile_around(look)
		# A body-sized box on the feet: a skinned mesh's own box is its rest pose's.
		var body := AABB(feet + Vector3(-0.3, 0.0, -0.3), Vector3(0.6, 1.8, 0.6))
		if not _prove_in_frame("bay2/frame %d" % i, body, Rect2(crop)):
			break
		if not _prove_in_frame("bay2/frame %d cube" % i, _aabb_of(cube), Rect2(crop)):
			break
		await physics_frame
		await physics_frame
		if not _prove_clear("bay2/frame %d" % i, feet):
			break
		var under := _surface_check(
			"bay2/frame %d feet" % i, feet, Vector3(0, 0, -1), _bodies_of(node)
		)
		if not under[0]:
			_invalid("bay2 frame %d: the passenger's feet are not on the surface at %s" % [i, feet])
			break
		on_top += int(absf(float(under[1]) - 0.2) < 0.01)
		var img := await _grab()
		strip.blit_rect(img, crop, Vector2i((i % 4) * STRIP_TILE.x, floori(i / 4.0) * STRIP_TILE.y))
	cube.free()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	print("BAY2 frames with the feet on the sidewalk top %d" % on_top)
	if not _failed and on_top < 1:
		_invalid("bay2: no frame had the feet on the sidewalk's top")
	if not _failed:
		_save(strip, "bay2_get_out_strip.png", _dir)


## The passenger models are skinned and get no probe colliders, so their occlusion
## check is the other way round: rays from the camera to points up the body standing
## at `feet` (the ankles, the hips, the chest) meet nothing before them.
func _prove_clear(label: String, feet: Vector3) -> bool:
	var space := _cam.get_world_3d().direct_space_state
	var clear := 0
	var blockers := {}
	for up: float in [0.15, 0.9, 1.4]:
		var target := feet + Vector3.UP * up
		var from := _cam.project_ray_origin(_cam.unproject_position(target))
		var q := PhysicsRayQueryParameters3D.create(from, target)
		var hit := space.intersect_ray(q)
		if not hit or (hit.position as Vector3).distance_to(target) < 0.3:
			clear += 1
		else:
			var by: Node = hit.collider.get_parent()
			blockers[by.name] = int(blockers.get(by.name, 0)) + 1
	print("VISIBLE %s clear rays %d/3 blocked_by=%s" % [label, clear, blockers])
	if clear < 3:
		_invalid("%s: something stands between the camera and the passenger" % label)
	return clear == 3


## A still over the planter bed west of the multi-storey (the site Road mesh raised
## over x -4..-3, z -41..-40): small markers every 0.5 m along the ground-floor walk
## from the apron's foot to the far kerb, and the stand-in walker at its turn onto the
## crossing at x -2. The bed and the walker are proved in frame and hit by rays. The
## cars are hidden for the plate.
func _plate_planter() -> void:
	var lot := _landside.definition.lots[MULTI]
	var walk := PackedVector3Array(_landside.paths.lot_walk(MULTI, 0))
	var foot := walk.find(lot.crossing[1])
	if foot < 0:
		_invalid("the ground-floor walk does not pass the apron's foot: %s" % [walk])
		return
	var route := PackedVector3Array(walk.slice(foot))
	var hidden: Array[Node3D] = []
	for id in _landside.vehicle_ids():
		var car := _views.node_for(id)
		if car != null and car.visible:
			car.visible = false
			hidden.append(car)
	var marks := Node3D.new()
	marks.name = "WalkMarks"
	_main.add_child(marks)
	var dot := SphereMesh.new()
	dot.radius = 0.06
	dot.height = 0.12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.6)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot.material = mat
	for mm in range(0, LandsideDefinition.length_mm(route) + 1, 500):
		var m := MeshInstance3D.new()
		m.mesh = dot
		m.position = LandsideDefinition.point_at(route, mm) + Vector3.UP * 0.06
		marks.add_child(m)
	var turn := lot.crossing[4]
	var walker := MeshInstance3D.new()
	walker.name = "ProbeWalker"
	var capsule := CapsuleMesh.new()
	capsule.radius = WALKER_RADIUS
	capsule.height = WALKER_HEIGHT
	walker.mesh = capsule
	_main.add_child(walker)
	walker.global_position = turn + Vector3.UP * (WALKER_HEIGHT / 2.0)
	print("PLANTER route %s, %d marks, walker at %s" % [route, marks.get_child_count(), turn])
	await _place_camera("planter", PLANTER_EYE, PLANTER_TARGET)
	var bed := AABB(Vector3(-4.0, 0.2, -41.0), Vector3(1.0, 0.06, 1.0))
	var ok := (
		_prove_in_frame("planter bed", bed) and _prove_in_frame("planter walker", _aabb_of(walker))
	)
	if ok:
		ok = _prove_point("planter bed", bed.get_center() + Vector3.UP * 0.03)
	if ok:
		ok = _prove_visible("planter walker", walker)
	if ok:
		_save(await _grab(), "planter_walk_still.png", _dir)
	walker.free()
	marks.free()
	for car in hidden:
		car.visible = true


## The pull-in probe's grab, scaled to the viewport's own size: under a display
## scale the window's texture has more pixels than the viewport rect that
## unproject_position() measures in, and a tile cut at projected coordinates from
## the unscaled image misses its subject.
func _grab() -> Image:
	var img := await super._grab()
	var view := Vector2i(root.get_visible_rect().size)
	if img.get_size() != view:
		print("GRAB image %s scaled to the viewport %s" % [img.get_size(), view])
		img.resize(view.x, view.y, Image.INTERPOLATE_LANCZOS)
	return img
