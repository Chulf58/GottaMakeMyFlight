extends SceneTree
## Windowed walk-through probe of the player-built terminal in the real game
## (board e34e358e; decision player-builds-the-terminal-floor-outer-walls-auto-
## roof-land-plots-starter-one-floor, point 6: on an empty starting plot the
## player paints floor, draws outer walls with an entrance and an exit, the
## roof appears, and a passenger walks from the road through the new building
## to the plane). It boots main.tscn with a new random world seed (printed),
## checks the plot is empty, and builds with BuildMode's tools only, one tool
## use at a time: ReferenceTerminal's layout moved OFFSET cells east and south
## (floor, outer walls and the security divider, desks, scanners, seats, then
## the entrance and the exit in the outer wall's two gaps). It hires one
## check-in agent and one security officer, who walk to their stations, then
## follows the first passenger from the road to the plane, printing each
## stage it reaches with its tick and position.
##
## Plates (tools/blender/out/cutover/): the gap markers while the outer wall
## is open (before the doors), the roof from far (150 m), the cutaway close
## in (40 m, roof faded out, walls cut), and the followed passenger at check-in,
## at security and walking to the plane. Every plate proves its subject is in
## frame (points projected inside the viewport by MARGIN_PX) and seen (rays
## from the camera against the site, every wall and floor piece, the build's
## objects, the roof while drawn, the gap bars and the planes) before it is
## saved; otherwise the probe prints PROBE_INVALID and exits 1.
##
## Run (one windowed Godot run project-wide; take the slot first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path C:/Users/chulf/Gotta-make-my-flight/game -s res://spike/walk_through_probe.gd

const OUT_REL := "res://../tools/blender/out/cutover"
const MAIN := "res://main/main.tscn"
## ReferenceTerminal's cells move this far: floor x 18-29, y 6-21, the exit
## at (28, 6) facing the plane, the entrance at (26, 21) facing the road.
const OFFSET := Vector2i(8, 4)
const TOOLS := {
	&"checkin_desk": BuildMode.Tool.DESK,
	&"security_scanner": BuildMode.Tool.SCANNER,
	&"seat_row": BuildMode.Tool.SEATS,
	&"entrance_door": BuildMode.Tool.ENTRANCE,
	&"exit_door": BuildMode.Tool.EXIT,
}
const TICKS_PER_FRAME := 10
const END_TICK := 9000
const MARGIN_PX := 8.0
const HIT_TOLERANCE := 0.05
const YAWS: Array[float] = [0.7, -0.7, 0.7 + PI, PI - 0.7]
const HANG_LIMIT_MS := 90000
const STAGE_LIMIT_MS := 300000

var _out_dir := ""
var _failed := false
var _main: Node
var _mode: BuildMode
var _sim: PassengerSim
var _clock: SimClock
var _staff: StaffSim
var _rig: TycoonCamera
var _cam: Camera3D
var _roof: RoofView
var _markers: GapMarkers
var _view: BuildView
var _followed := 0
var _reached := {}

var _stage := "init"
var _heartbeat_ms := 0
var _stage_started_ms := 0
var _guard_mutex := Mutex.new()
var _guard_stop := false
var _guard := Thread.new()


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_beat("boot")
	_guard.start(_watch)
	var seed := randi()
	print("PROBE seed=", seed, " out_dir=", _out_dir)
	_main = (load(MAIN) as PackedScene).instantiate()
	_clock = _main.get_node("SimClock") as SimClock
	_clock.seed_rng(seed)
	_clock.set_paused(true)
	root.add_child(_main)
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_beat(_stage)
	return false


func _beat(stage: String) -> void:
	_guard_mutex.lock()
	if stage != _stage:
		_stage_started_ms = Time.get_ticks_msec()
	_stage = stage
	_heartbeat_ms = Time.get_ticks_msec()
	_guard_mutex.unlock()


## Guard thread (anti-pattern a-frame-counting-watchdog-cannot-catch-a-stuck-
## main-thread): a frozen main thread never reaches _process.
func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_guard_mutex.lock()
		var stop := _guard_stop
		var now := Time.get_ticks_msec()
		var idle_ms := now - _heartbeat_ms
		var stage_ms := now - _stage_started_ms
		var stage := _stage
		_guard_mutex.unlock()
		if stop:
			return
		if idle_ms > HANG_LIMIT_MS or stage_ms > STAGE_LIMIT_MS:
			print(
				(
					"PROBE_INVALID hang stage=%s no heartbeat for %d ms, in stage for %d ms"
					% [stage, idle_ms, stage_ms]
				)
			)
			OS.crash("walk-through probe hung")


func _run() -> void:
	await _frames(3)
	_mode = _main.get_node("BuildMode") as BuildMode
	_sim = _main.get_node("PassengerSim") as PassengerSim
	_staff = _main.get_node("Staff") as StaffSim
	_rig = _main.get_node("TycoonCamera") as TycoonCamera
	_cam = _rig.get_node("Camera3D") as Camera3D
	_roof = _main.get_node("RoofView") as RoofView
	_markers = _main.get_node("GapMarkers") as GapMarkers
	_view = _mode.get_node("BuildView") as BuildView
	_sim.passenger_spawned.connect(_on_spawned)
	if _empty_plot() and await _build() and await _staff_up():
		await _follow()
	_finish()


func _finish() -> void:
	_guard_mutex.lock()
	_guard_stop = true
	_guard_mutex.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


# ------------------------------------------------------------ the walk-through


func _empty_plot() -> bool:
	_beat("empty")
	var grid := _mode.grid
	var floored := _floor_count()
	print(
		(
			"STAGE empty_plot site=%s grid=%s origin=%s floor=%d objects=%d roofed=%d balance=%d"
			% [
				_mode.site != null,
				grid.size,
				grid.origin,
				floored,
				grid.object_ids().size(),
				_roof.roofed_cell_count(),
				_mode.wallet().balance,
			]
		)
	)
	if _mode.site == null or _sim.site != _mode.site:
		_invalid("BuildMode or PassengerSim has no site")
		return false
	if floored != 0 or not grid.object_ids().is_empty():
		_invalid("the starting plot is not empty")
		return false
	return true


## Builds the terminal with the tools, plating the gap markers while the
## outer wall is still open, then the roof and the cutaway once it is shut.
func _build() -> bool:
	_beat("build")
	var doors: Array[BuildEdit] = []
	var rest: Array[BuildEdit] = []
	for edit in ReferenceTerminal.edits():
		var door := edit.kind == BuildEdit.Kind.PLACE_OBJECT and BuildCatalog.is_door(edit.def_id)
		(doors if door else rest).append(edit)
	if not await _build_open(rest) or not await _build_doors(doors):
		return false
	var centre := (ReferenceTerminal.FLOOR_MIN + ReferenceTerminal.FLOOR_MAX) / 2 + OFFSET
	if not await _shot("roof_far", centre, 150.0, "roof"):
		return false
	return await _shot("cutaway_close", centre, 40.0, "cutaway")


## Floor, walls and stations, with the outer wall's two door gaps open, and
## the gap marker plate.
func _build_open(edits: Array[BuildEdit]) -> bool:
	var walls := 0
	for edit in edits:
		if not _use_tool(edit):
			return false
		walls += int(edit.kind == BuildEdit.Kind.PLACE_WALL)
	_mode.set_tool(BuildMode.Tool.NONE)
	var gaps := EnclosureGaps.gap_edges(_mode.grid).size()
	print(
		(
			"STAGE walled floor=%d walls=%d objects=%d indoor=%d gap_edges=%d signs=%d roofed=%d"
			% [
				_floor_count(),
				walls,
				_mode.grid.object_ids().size(),
				_indoor_count(),
				gaps,
				_markers.sign_count(),
				_roof.roofed_cell_count(),
			]
		)
	)
	if _floor_count() == 0 or gaps == 0 or _markers.sign_count() == 0:
		_invalid("no floor or no gap marker before the doors")
		return false
	var entrance := ReferenceTerminal.ENTRANCE_CELL + OFFSET
	return await _shot("gap_marker", entrance, 30.0, "gap")


## The entrance and the exit in the gaps: the building is closed in.
func _build_doors(doors: Array[BuildEdit]) -> bool:
	for edit in doors:
		if not _use_tool(edit):
			return false
	_mode.set_tool(BuildMode.Tool.NONE)
	await _frames(2)
	var layout := _sim.layout
	print(
		(
			(
				"STAGE doors entrances_in_service=%d open_exits=%d out_of_service=%d indoor=%d"
				+ " gap_edges=%d roofed=%d balance=%d"
			)
			% [
				layout.passenger_entrances.size(),
				layout.open_exits(_mode.grid).size(),
				layout.out_of_service.size(),
				_indoor_count(),
				EnclosureGaps.gap_edges(_mode.grid).size(),
				_roof.roofed_cell_count(),
				_mode.wallet().balance,
			]
		)
	)
	if layout.passenger_entrances.is_empty() or _roof.roofed_cell_count() == 0:
		_invalid("the entrance is not in service or no roof appeared")
		return false
	return true


## One tool use for `edit` (moved by OFFSET), as a player clicks it.
func _use_tool(edit: BuildEdit) -> bool:
	var cell := edit.cell + OFFSET
	var point := _mode.grid.cell_to_world(cell)
	match edit.kind:
		BuildEdit.Kind.PAINT_FLOOR:
			_set_tool(BuildMode.Tool.FLOOR, 0)
		BuildEdit.Kind.PLACE_WALL:
			_set_tool(BuildMode.Tool.WALL, 0)
			var step := BuildGrid.SIDE_STEP[edit.side]
			point += Vector3(step.x * 0.45, 0.0, step.y * 0.45)
		BuildEdit.Kind.PLACE_OBJECT:
			_set_tool(TOOLS[edit.def_id], edit.facing)
	var result := _mode.apply_at(point)
	if result == null or not result.ok:
		var why := "no edit" if result == null else result.reason_text()
		_invalid("tool %s at %s refused: %s" % [_mode.tool, cell, why])
		return false
	return true


func _set_tool(tool: BuildMode.Tool, turns: int) -> void:
	if _mode.tool != tool:
		_mode.set_tool(tool)
	while _mode.facing != turns:
		_mode.rotate_facing()


## One check-in agent and one security officer, hired as the staff panel
## does; they walk in from the entrance to their stations.
func _staff_up() -> bool:
	_beat("staff")
	_staff.hire(StaffMember.Role.CHECKIN)
	_staff.hire(StaffMember.Role.SECURITY)
	var desk: int = _sim.layout.desks[0]
	var scanner: int = _sim.layout.scanners[0]
	for i in 400:
		_tick(TICKS_PER_FRAME)
		await process_frame
		var checkin := _staff.on_duty_count(StaffMember.Role.CHECKIN)
		if checkin > 0 and _staff.on_duty_count(StaffMember.Role.SECURITY) > 0:
			print(
				(
					"STAGE staffed tick=%d checkin_on_duty=%d security_on_duty=%d"
					% [
						_clock.tick,
						_staff.on_duty_count(StaffMember.Role.CHECKIN),
						_staff.on_duty_count(StaffMember.Role.SECURITY),
					]
				)
			)
			return true
	for id in _staff.member_ids():
		var m := _staff.get_member(id)
		print(
			(
				"STAFF %d role=%d state=%d station=%d at=%s"
				% [id, m.role, m.state, m.station, m.at]
			)
		)
	print(
		(
			"STATIONS desk %d usable=%s unreachable=%s scanner %d usable=%s unreachable=%s"
			% [
				desk,
				_sim.layout.is_usable(desk),
				_staff.spot_unreachable(desk),
				scanner,
				_sim.layout.is_usable(scanner),
				_staff.spot_unreachable(scanner),
			]
		)
	)
	_invalid("the hired staff never opened the desk and the scanner")
	return false


## Runs the sim and follows the first passenger, plating it at check-in, at
## security and on its walk out to the plane.
func _follow() -> void:
	_beat("follow")
	var shots := {
		Passenger.Stage.CHECKIN: "pax_checkin",
		Passenger.Stage.SECURITY: "pax_security",
	}
	var taken := {}
	while _clock.tick < END_TICK:
		_tick(TICKS_PER_FRAME)
		await process_frame
		if _followed == 0:
			continue
		var p := _sim.get_passenger(_followed)
		if p == null:
			_invalid("the followed passenger %d is gone" % _followed)
			return
		_note_stage(p)
		if shots.has(p.stage) and not taken.has(p.stage):
			taken[p.stage] = true
			if not await _passenger_shot(shots[p.stage], p):
				return
		if p.stage == Passenger.Stage.APRON and not taken.has(p.stage) and p.apron_mm > 3000:
			taken[p.stage] = true
			if not await _passenger_shot("pax_to_plane", p):
				return
		if p.stage == Passenger.Stage.MADE or p.stage == Passenger.Stage.MISSED:
			break
	var p: Passenger = _sim.get_passenger(_followed) if _followed != 0 else null
	var final: String = "none" if p == null else Passenger.Stage.keys()[p.stage]
	print(
		(
			"STAGE end tick=%d followed=%d final=%s reached=%s"
			% [_clock.tick, _followed, final, _reached.keys()]
		)
	)
	if p == null or p.stage != Passenger.Stage.MADE or taken.size() < 3:
		_invalid("the followed passenger did not walk through to the plane (%s)" % final)


func _note_stage(p: Passenger) -> void:
	var name: String = Passenger.Stage.keys()[p.stage]
	if _reached.has(name):
		return
	_reached[name] = _clock.tick
	var at := _sim.world_position(p)
	print(
		(
			"STAGE passenger %d %s tick=%d at=%s cell=%s apron_mm=%d/%d"
			% [p.id, name, _clock.tick, at, p.at, p.apron_mm, p.apron_total_mm()]
		)
	)


func _on_spawned(id: int) -> void:
	if _followed == 0:
		_followed = id
		var p := _sim.get_passenger(id)
		print("STAGE passenger %d spawned on the road at %s" % [id, _sim.world_position(p)])


func _tick(count: int) -> void:
	_clock.set_paused(false)
	for i in count:
		_clock.advance(SimClock.STEP)
	_clock.set_paused(true)


# ------------------------------------------------------------ shots


## A shot of the build: `kind` gap, roof or cutaway.
func _shot(name: String, cell: Vector2i, distance: float, kind: String) -> bool:
	_beat(name)
	var focus := _mode.grid.cell_to_world(cell)
	for yaw in YAWS:
		await _aim(focus, distance, yaw)
		var bodies := _colliders()
		await physics_frame
		await physics_frame
		var ok := _prove_build(name, kind, false)
		bodies.free()
		if ok:
			break
	var bodies := _colliders()
	await physics_frame
	await physics_frame
	var proven := _prove_build(name, kind, true)
	bodies.free()
	if not proven:
		return false
	_save(await _grab(), name + ".png")
	return true


func _prove_build(name: String, kind: String, loud: bool) -> bool:
	_camera_line(name)
	match kind:
		"gap":
			return _prove_gap(name, loud)
		"roof":
			return _prove_roof(name, loud)
		"cutaway":
			return _prove_cutaway(name, loud)
	return _fail(loud, "unknown shot kind %s" % kind)


func _prove_gap(name: String, loud: bool) -> bool:
	if _markers.sign_count() == 0:
		return _fail(loud, "%s: no gap sign" % name)
	var sign_at := _markers.signs()[0].global_position
	var bars: Array[Vector3] = []
	for t in _markers.bar_transforms():
		bars.append(t.origin + Vector3.UP * GapMarkers.BAR_HEIGHT * 0.5)
	return (
		_in_frame(name + "/sign", [sign_at], loud)
		and _in_frame(name + "/bars", bars, loud)
		and _seen(name + "/bars", bars, 0.5, loud)
	)


func _prove_roof(name: String, loud: bool) -> bool:
	if not _roof.roof_node().visible:
		return _fail(loud, "%s: the roof is not drawn" % name)
	return (
		_in_frame(name + "/roof_box", _corners(_roof.roof_box()), loud)
		and _seen(name + "/roof_top", _roof_targets(), 0.6, loud)
	)


func _prove_cutaway(name: String, loud: bool) -> bool:
	var cut := _view.cut_edges().size()
	print(
		(
			"CUTAWAY %s roof_visible=%s cutaway_enabled=%s cut_edges=%d"
			% [name, _roof.roof_node().visible, _view.cutaway_enabled, cut]
		)
	)
	if _roof.roof_node().visible or not _view.cutaway_enabled or cut == 0:
		return _fail(loud, "%s: the roof is drawn or no wall is cut" % name)
	var floor := _floor_targets()
	return _in_frame(name + "/floor", floor, loud) and _seen(name + "/floor", floor, 0.5, loud)


## A shot of the followed passenger, held still while it is taken.
func _passenger_shot(name: String, p: Passenger) -> bool:
	_beat(name)
	var foot := _sim.world_position(p)
	var chest := foot + Vector3.UP * 1.2
	var head := foot + Vector3.UP * 1.7
	print(
		(
			"SUBJECT %s passenger %d stage=%s at=%s"
			% [name, p.id, Passenger.Stage.keys()[p.stage], foot]
		)
	)
	for yaw in YAWS:
		await _aim(foot, 22.0, yaw)
		var bodies := _colliders()
		await physics_frame
		await physics_frame
		var ok := _in_frame(name, [foot, head], false) and _seen(name, [chest, head], 1.0, false)
		bodies.free()
		if ok:
			break
	var bodies := _colliders()
	await physics_frame
	await physics_frame
	_camera_line(name)
	var proven := _in_frame(name, [foot, head], true) and _seen(name, [chest, head], 1.0, true)
	bodies.free()
	if not proven:
		return false
	_save(await _grab(), name + ".png")
	return true


func _aim(focus: Vector3, distance: float, yaw: float) -> void:
	_rig.position = Vector3(focus.x, 0.0, focus.z)
	_rig.distance = distance
	_rig.yaw = yaw
	_rig.zoom(1.0)
	# The camera eases to its distance and the roof then fades for
	# RoofCutaway.roof_fade_seconds; wait until both have settled.
	await _frames(10)
	for i in 600:
		if _roof.cutaway.roof_level == _roof.cutaway.roof_target:
			break
		await process_frame
	await _frames(10)


func _camera_line(name: String) -> void:
	print(
		(
			"CAMERA %s pos=%s yaw=%.2f distance=%.1f roof_level=%.2f roof_visible=%s"
			% [
				name,
				_cam.global_position,
				_rig.yaw,
				_rig.distance,
				_roof.cutaway.roof_level,
				_roof.roof_node().visible,
			]
		)
	)


func _fail(loud: bool, msg: String) -> bool:
	if loud:
		_invalid(msg)
	return false


func _in_frame(label: String, points: Array, loud: bool) -> bool:
	var rect := Rect2(Vector2.ZERO, root.get_visible_rect().size).grow(-MARGIN_PX)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for point: Vector3 in points:
		if _cam.is_position_behind(point):
			return _fail(loud, "%s: %s is behind the camera" % [label, point])
		var s := _cam.unproject_position(point)
		lo = lo.min(s)
		hi = hi.max(s)
	var ok := not points.is_empty() and rect.has_point(lo) and rect.has_point(hi)
	if loud:
		print(
			(
				"INFRAME %s points=%d screen=(%.0f,%.0f)-(%.0f,%.0f) ok=%s"
				% [label, points.size(), lo.x, lo.y, hi.x, hi.y, ok]
			)
		)
	return ok or _fail(loud, "%s: projected points leave the viewport" % label)


## Rays from the camera to each target; a target is seen when nothing is hit
## before it, or the first hit is on it. At least `share` of them.
func _seen(label: String, targets: Array, share: float, loud: bool) -> bool:
	var space := _cam.get_world_3d().direct_space_state
	var from := _cam.global_position
	var seen := 0
	for t: Vector3 in targets:
		var q := PhysicsRayQueryParameters3D.create(from, t + (t - from).normalized() * 0.01)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit["position"] as Vector3).distance_to(t) <= HIT_TOLERANCE + 0.01:
			seen += 1
	var ok := targets.size() > 0 and seen >= ceili(targets.size() * share)
	if loud:
		print("VISIBLE %s seen=%d/%d share=%.2f ok=%s" % [label, seen, targets.size(), share, ok])
	return ok or _fail(loud, "%s: occluded (%d of %d rays)" % [label, seen, targets.size()])


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _grab() -> Image:
	await _frames(4)
	var img := root.get_texture().get_image()
	if img == null:
		_invalid("the viewport gave no image (a headless run draws nothing)")
		return Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.convert(Image.FORMAT_RGBA8)
	return img


func _save(img: Image, file: String) -> void:
	var path := _out_dir.path_join(file)
	if img.save_png(path) != OK:
		_invalid("could not save %s" % path)
		return
	print("PLATE saved %s size=%s" % [path, img.get_size()])


# ------------------------------------------------------------ subjects


func _floor_count() -> int:
	var count := 0
	for y in _mode.grid.size.y:
		for x in _mode.grid.size.x:
			count += int(_mode.grid.floor_at(Vector2i(x, y)) != BuildGrid.FLOOR_NONE)
	return count


func _indoor_count() -> int:
	var count := 0
	for y in _mode.grid.size.y:
		for x in _mode.grid.size.x:
			count += int(_mode.grid.is_indoor(Vector2i(x, y)))
	return count


## Points just above the roof top over a spread of indoor cells.
func _roof_targets() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var lift := _mode.grid.origin.y + _roof.roof_height + 0.02
	for cell in _spread():
		var at := _mode.grid.cell_to_world(cell)
		out.append(Vector3(at.x, lift, at.z))
	return out


## Points just above the floor over a spread of the terminal's floor cells.
func _floor_targets() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for cell in _spread():
		if _mode.grid.is_walkable(cell):
			out.append(_mode.grid.cell_to_world(cell) + Vector3.UP * 0.05)
	return out


func _spread() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var low := ReferenceTerminal.FLOOR_MIN + OFFSET
	var high := ReferenceTerminal.FLOOR_MAX + OFFSET
	for y in range(low.y + 1, high.y, 3):
		for x in range(low.x + 1, high.x, 3):
			out.append(Vector2i(x, y))
	return out


func _corners(box: AABB) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i in 8:
		out.append(box.get_endpoint(i))
	return out


# ------------------------------------------------------------ colliders


## Static bodies for the site, every BuildView piece and object, the roof
## while drawn, the gap bars and the planes. The passengers are not bodies.
func _colliders() -> Node3D:
	var bodies := Node3D.new()
	bodies.name = "ProbeColliders"
	root.add_child(bodies)
	for path in ["Airside/Terminal", "PlaneView", "PlaneView2"]:
		for node in _main.get_node(path).find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.is_visible_in_tree():
				bodies.add_child(_body(mi.mesh, mi.global_transform))
	for piece in _view.piece_counts():
		var parts := InteriorKit.meshes(piece)
		for t in _view.piece_transforms(piece):
			for part in parts:
				bodies.add_child(
					_body(part[0], _view.global_transform * t * (part[1] as Transform3D))
				)
	for node in _mode.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.is_visible_in_tree():
			bodies.add_child(_body(mi.mesh, mi.global_transform))
	for t in _markers.bar_transforms():
		bodies.add_child(_body(_markers.bar_node().multimesh.mesh, t))
	if _roof.roof_node().visible:
		bodies.add_child(_body(_roof.roof_node().mesh, _roof.roof_node().global_transform))
	return bodies


func _body(mesh: Mesh, at: Transform3D) -> StaticBody3D:
	var faces := PackedVector3Array()
	if mesh != null:
		for p in mesh.get_faces():
			faces.append(at * p)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	var body := StaticBody3D.new()
	body.add_child(shape_node)
	return body
