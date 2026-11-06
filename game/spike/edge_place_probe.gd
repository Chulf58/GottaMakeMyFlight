extends SceneTree
## Windowed probe for board fcc3c310 part b: does placing at the terminal edge
## land one cell off? It boots the real main scene (starter shell), picks the
## tray table, and for screen points across each edge of the shell compares
## three cells: where the pointer ray meets the floor (grid_point), the cell
## BuildMode.edit_at() picks, and the cell the ghost is drawn on.
##
## Two kinds of aim per edge, so the table separates the code path from the
## picture: "ground" aims at a floor point (the cell the player means), "wall"
## aims at the top of the 2 m wall line, which is what the eye sees at a low
## angle. The ray through a wall top meets the floor cells behind it.
##
## Run (one windowed Godot run project-wide; import first):
##   timeout 900 Godot_v4.7.2-stable_win64_console.exe --display-driver windows \
##     --rendering-driver vulkan --audio-driver Dummy \
##     --path <game> -s res://spike/edge_place_probe.gd
##
## Prints the world seed and a table (PROBE row ...), then PROBE summary lines.
## Plates go to tools/blender/out/edge-place/. A subject not in frame prints
## PROBE_INVALID and the probe exits 1.

const OUT_REL := "res://../tools/blender/out/edge-place"
const MAIN_SCENE := "res://main/main.tscn"
const MARGIN_PX := 24.0
const HANG_MS := 60000
const DISTANCE_M := 30.0
## The plate is framed closer so the ghost is big enough to judge.
const PLATE_DISTANCE_M := 12.0
## Distances along the edge's outward step, round the wall line, in metres.
const OFFSETS_M: Array[float] = [-1.0, -0.6, -0.3, -0.15, 0.0, 0.15, 0.3, 0.6, 1.0]
const YAWS: Array[float] = [0.0, 0.5, -0.5]
const CELLS_PER_EDGE := 2
## Rows printed in full per (step, yaw) config; the rest only count.
const PRINT_CONFIGS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 0)]

var _failed := false
var _stage := "boot"
var _beat_ms := 0
var _lock := Mutex.new()
var _stop := false
var _guard := Thread.new()
var _main: Node3D
var _mode: BuildMode
var _rig: TycoonCamera
var _cam: Camera3D
var _grid: BuildGrid
var _out_dir := ""
var _plated := false
var _mismatch := {"ground": 0, "wall": 0}
var _samples := {"ground": 0, "wall": 0}
var _ghost_mismatch := 0
var _unexplained := 0


func _initialize() -> void:
	_out_dir = ProjectSettings.globalize_path(OUT_REL).simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_beat("boot")
	_guard.start(_watch)
	_run.call_deferred()


func _beat(stage: String) -> void:
	_lock.lock()
	_stage = stage
	_beat_ms = Time.get_ticks_msec()
	_lock.unlock()


func _watch() -> void:
	while true:
		OS.delay_msec(500)
		_lock.lock()
		var stop := _stop
		var idle := Time.get_ticks_msec() - _beat_ms
		var stage := _stage
		_lock.unlock()
		if stop:
			return
		if idle > HANG_MS:
			print("PROBE_INVALID hang stage=%s idle=%d ms" % [stage, idle])
			OS.crash("edge place probe hung")


func _invalid(msg: String) -> void:
	print("PROBE_INVALID ", msg)
	_failed = true


func _frames(count: int) -> void:
	for i in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _run() -> void:
	_main = load(MAIN_SCENE).instantiate()
	var clock: SimClock = _main.get_node("SimClock")
	var world_seed := randi()
	if OS.has_environment("PROBE_SEED"):
		world_seed = OS.get_environment("PROBE_SEED").to_int()
	clock.seed_rng(world_seed)
	print("PROBE seed=", world_seed)
	root.add_child(_main)
	await _frames(6)
	_mode = _main.get_node("BuildMode")
	_rig = _main.get_node("TycoonCamera")
	_cam = _main.get_node("TycoonCamera/Camera3D")
	_grid = _mode.grid
	_mode.set_tool_for_move(BuildMode.Tool.TRAY_TABLE)
	var bounds := _floor_bounds()
	print("PROBE floor bounds=%s grid origin=%s" % [bounds, _grid.origin])
	if bounds.size.x < 4 or bounds.size.y < 4:
		_invalid("no starter shell floor found")
	var edges := _edges(bounds)
	var config_index := 0
	for step in 3:
		for yaw_index in YAWS.size():
			_rig.angle_step = step
			_rig.yaw = YAWS[yaw_index]
			var printed := PRINT_CONFIGS.has(Vector2i(step, yaw_index))
			for edge in edges:
				await _sweep(edge, step, yaw_index, printed)
			config_index += 1
	print(
		(
			(
				"PROBE summary ground samples=%d edit_vs_pointer_differs=%d | "
				+ "wall-top samples=%d edit_vs_pointer_differs=%d | ghost_vs_edit_differs=%d "
				+ "| differs_not_a_one_cell_snap_inward=%d"
			)
			% [
				_samples["ground"],
				_mismatch["ground"],
				_samples["wall"],
				_mismatch["wall"],
				_ghost_mismatch,
				_unexplained
			]
		)
	)
	_lock.lock()
	_stop = true
	_lock.unlock()
	_guard.wait_to_finish()
	print("PROBE done failed=%s" % _failed)
	quit(1 if _failed else 0)


## The rectangle of cells that have a floor, from a scan of the whole grid.
func _floor_bounds() -> Rect2i:
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for y in _grid.size.y:
		for x in _grid.size.x:
			if _grid.floor_at(Vector2i(x, y)) != BuildGrid.FLOOR_NONE:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## Each edge: a name, the outward step, and CELLS_PER_EDGE edge cells.
func _edges(bounds: Rect2i) -> Array:
	var out: Array = []
	var last := bounds.position + bounds.size - Vector2i.ONE
	var mid := bounds.position + bounds.size / 2
	for spec in [
		["south", Vector2i(0, 1), func(i: int) -> Vector2i: return Vector2i(mid.x + i * 3, last.y)],
		["east", Vector2i(1, 0), func(i: int) -> Vector2i: return Vector2i(last.x, mid.y + i * 3)],
		[
			"north",
			Vector2i(0, -1),
			func(i: int) -> Vector2i: return Vector2i(mid.x + i * 3, bounds.position.y)
		],
		[
			"west",
			Vector2i(-1, 0),
			func(i: int) -> Vector2i: return Vector2i(bounds.position.x, mid.y + i * 3)
		],
	]:
		for i in CELLS_PER_EDGE:
			out.append({"name": spec[0], "out": spec[1], "cell": spec[2].call(i)})
	return out


func _sweep(edge: Dictionary, step: int, yaw_index: int, printed: bool) -> void:
	var out_step: Vector2i = edge["out"]
	var cell: Vector2i = edge["cell"]
	var line := _grid.cell_to_world(cell) + Vector3(out_step.x * 0.5, 0.0, out_step.y * 0.5)
	_rig.position = line
	_rig.distance = DISTANCE_M
	await _frames(2)
	var outward := Vector3(out_step.x, 0.0, out_step.y)
	for kind in ["ground", "wall"]:
		for offset in OFFSETS_M:
			var aim := line + outward * offset
			if kind == "wall":
				aim.y += BuildView.WALL_HEIGHT
			var screen := _cam.unproject_position(aim)
			if not _in_frame(screen):
				_invalid("aim %s offscreen at %s" % [aim, screen])
				continue
			var row := await _measure(screen)
			_samples[kind] += 1
			var differs: bool = row["pointer"] != row["edit"]
			if differs:
				_mismatch[kind] += 1
				# The one allowed difference: the pointer is off the floor, within
				# the wall line's slack, and the edit snaps one cell inward.
				var gap: Vector2i = row["edit"] - row["pointer"]
				var snap_inward: bool = (
					absi(gap.x) + absi(gap.y) == 1
					and _grid.floor_at(row["pointer"]) == BuildGrid.FLOOR_NONE
					and _grid.floor_at(row["edit"]) != BuildGrid.FLOOR_NONE
				)
				if not snap_inward:
					_unexplained += 1
					_invalid("unexplained cell difference at %s: %s" % [screen, row])
			if row["ghost"] != row["edit"] and row["ghost_visible"]:
				_ghost_mismatch += 1
				_invalid("ghost cell differs from the edit cell at %s: %s" % [screen, row])
			if printed:
				print(
					(
						(
							"PROBE row step=%d yaw=%.1f edge=%s@%s aim=%s off=%+.2fm screen=(%d,%d) "
							+ "pointer=%s edit=%s ghost=%s%s%s"
						)
						% [
							step,
							YAWS[yaw_index],
							edge["name"],
							cell,
							kind,
							offset,
							screen.x,
							screen.y,
							row["pointer"],
							row["edit"],
							row["ghost"] if row["ghost_visible"] else "none",
							"  DIFF" if differs else "",
							(
								"  GHOST!=EDIT"
								if row["ghost"] != row["edit"] and row["ghost_visible"]
								else ""
							)
						]
					)
				)
	if not _plated and step == 1 and edge["name"] == "south":
		await _plate(line, edge)


## One screen point: the three cells.
func _measure(screen: Vector2) -> Dictionary:
	_mode.pointer_override = screen
	await _frames(2)
	var from := _cam.project_ray_origin(screen)
	var dir := _cam.project_ray_normal(screen)
	var point: Variant = _mode.grid_point(from, dir)
	var row := {"pointer": Vector2i(-999, -999), "edit": Vector2i(-999, -999)}
	row["ghost"] = Vector2i(-999, -999)
	row["ghost_visible"] = false
	if point == null:
		return row
	row["pointer"] = _grid.world_to_cell(point)
	var edit := _mode.edit_at(point)
	if edit != null:
		row["edit"] = edit.cell
	var ghost := _mode.get_node("Ghost") as Node3D
	if ghost.visible and ghost.get_child_count() > 0:
		row["ghost_visible"] = true
		row["ghost"] = _grid.world_to_cell((ghost.get_child(0) as Node3D).global_position)
	return row


func _in_frame(screen: Vector2) -> bool:
	var size := root.get_visible_rect().size
	return (
		screen.x >= MARGIN_PX
		and screen.y >= MARGIN_PX
		and screen.x <= size.x - MARGIN_PX
		and screen.y <= size.y - MARGIN_PX
	)


## A plate with the ghost at the south edge, aimed at the wall line.
func _plate(line: Vector3, edge: Dictionary) -> void:
	_plated = true
	_rig.distance = PLATE_DISTANCE_M
	await _frames(3)
	var out_step: Vector2i = edge["out"]
	var aim := line - Vector3(out_step.x, 0.0, out_step.y) * 0.3
	var screen := _cam.unproject_position(aim)
	_mode.pointer_override = screen
	await _frames(4)
	var ghost := _mode.get_node("Ghost") as Node3D
	if not ghost.visible or ghost.get_child_count() == 0:
		_invalid("the ghost is not shown for the plate")
		return
	var centre := (ghost.get_child(0) as Node3D).global_position
	var ghost_px := _cam.unproject_position(centre)
	print(
		(
			"PROBE plate aim_px=%s ghost_px=%s ghost_cell=%s"
			% [screen, ghost_px, _grid.world_to_cell(centre)]
		)
	)
	if not _in_frame(ghost_px):
		_invalid("the ghost is not in frame for the plate")
		return
	var img := root.get_texture().get_image()
	var path := _out_dir.path_join("ghost-south-edge.png")
	if img.save_png(path) != OK:
		_invalid("could not save " + path)
	else:
		print("PLATE saved %s size=%s" % [path, img.get_size()])
